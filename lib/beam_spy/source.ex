defmodule BeamSpy.Source do
  @moduledoc """
  Extract and correlate source code with bytecode.

  Loads source lines from the original file or reconstructs them
  from the debug info (Dbgi) chunk when available.
  """

  import Bitwise

  @typedoc "Source type: {:file, path} for real source, :reconstructed for debug info"
  @type source_type :: {:file, String.t()} | :reconstructed

  @doc """
  Load source lines for a module.

  Returns `{:ok, %{line_num => text}, source_type}` or `{:error, reason}`.
  The source_type is `:file` when loaded from the original source file,
  or `:reconstructed` when rebuilt from debug info.

  Resolution order:
  1. Try original source file (path from CInf chunk)
  2. Fall back to AST reconstruction from Dbgi chunk
  3. Return error if neither available
  """
  @spec load_source(String.t(), keyword()) :: {:ok, map(), source_type()} | {:error, term()}
  def load_source(beam_path, opts \\ []) do
    case Keyword.get(opts, :source_path) do
      nil ->
        load_from_beam(beam_path)

      path ->
        case load_from_file(path) do
          {:ok, lines} -> {:ok, lines, {:file, path}}
          error -> error
        end
    end
  end

  @doc """
  Parse the Line chunk to build a mapping from bytecode line indices
  to actual source line numbers.

  The bytecode contains `{:line, N}` instructions where N is an index
  into the Line chunk's table, not an actual line number. This function
  builds the lookup table to resolve those indices.

  Returns `{:ok, %{index => line_number}}` or `{:error, reason}`.
  """
  @spec parse_line_table(String.t()) :: {:ok, map()} | {:error, term()}
  def parse_line_table(beam_path) do
    case :beam_lib.chunks(to_charlist(beam_path), [~c"Line"]) do
      {:ok, {_, [{~c"Line", data}]}} ->
        parse_line_chunk(data)

      {:error, :beam_lib, reason} ->
        {:error, reason}

      _ ->
        {:error, :no_line_chunk}
    end
  end

  defp parse_line_chunk(
         <<_version::32, _flags::32, _instr_count::32, num_lines::32, _num_files::32,
           rest::binary>>
       ) do
    {entries, _remaining} = decode_line_entries(rest, num_lines, [])

    # Build index -> line_number map (0-based indices, matching bytecode LINE instructions)
    # Each entry is a location value that may encode file index in high bits
    table =
      entries
      |> Enum.with_index(0)
      |> Map.new(fn {location, idx} ->
        # Extract line number from location (low 24 bits)
        line = location &&& 0xFFFFFF
        {idx, line}
      end)

    {:ok, table}
  rescue
    e -> {:error, {:parse_error, e}}
  end

  defp decode_line_entries(rest, 0, acc), do: {Enum.reverse(acc), rest}

  defp decode_line_entries(binary, n, acc) do
    # Line entries are encoded using BEAM compact term format.
    # The tag varies but we only need the numeric value.
    {term, rest} = CTF.decode(binary)
    value = extract_compact_value(term)
    decode_line_entries(rest, n - 1, [value | acc])
  end

  # Extract the numeric value from a compact term, regardless of tag.
  defp extract_compact_value({_tag, value}) when is_integer(value), do: value
  defp extract_compact_value({:tr, inner, _type}), do: extract_compact_value(inner)

  @doc """
  Group instructions by their source line numbers.

  Takes a list of instructions (from disassembly) and an optional line table
  (from `parse_line_table/1`) to resolve line indices to actual line numbers.

  The `{:line, N}` values in bytecode are indices into the Line chunk, not
  actual line numbers. Pass the line_table to get correct source correlation.

  Returns a list of `{line_number, [instructions]}` where line_number
  can be nil for instructions before any line marker.
  """
  @spec group_by_line([tuple()], map()) :: [{non_neg_integer() | nil, [tuple()]}]
  def group_by_line(instructions, line_table \\ %{}) do
    {groups, current_line, current_insts} =
      Enum.reduce(instructions, {[], nil, []}, fn
        {:line, idx}, {groups, current_line, current_insts} ->
          # Look up the actual line number from the line table
          actual_line = Map.get(line_table, idx, idx)

          # Finish current group (if any) and start a new one
          new_groups =
            if current_insts != [] do
              [{current_line, Enum.reverse(current_insts)} | groups]
            else
              groups
            end

          {new_groups, actual_line, []}

        {:meta, "line", [n_str]}, {groups, current_line, current_insts} ->
          # Handle parsed instruction format - same logic
          idx = String.to_integer(n_str)
          actual_line = Map.get(line_table, idx, idx)

          new_groups =
            if current_insts != [] do
              [{current_line, Enum.reverse(current_insts)} | groups]
            else
              groups
            end

          {new_groups, actual_line, []}

        inst, {groups, current_line, current_insts} ->
          # Add instruction to current group
          {groups, current_line, [inst | current_insts]}
      end)

    # Don't forget the last group
    final_groups =
      if current_insts != [] do
        [{current_line, Enum.reverse(current_insts)} | groups]
      else
        groups
      end

    final_groups
    |> Enum.reverse()
    |> merge_same_line_groups()
  end

  # Merge consecutive groups with the same line number
  defp merge_same_line_groups([]), do: []

  defp merge_same_line_groups([{line, insts1}, {line, insts2} | rest]) do
    merge_same_line_groups([{line, insts1 ++ insts2} | rest])
  end

  defp merge_same_line_groups([group | rest]) do
    [group | merge_same_line_groups(rest)]
  end

  # Load source from the beam file's metadata
  defp load_from_beam(beam_path) do
    with {:ok, source_path} <- get_source_path(beam_path),
         {:ok, lines} <- load_from_file(source_path) do
      {:ok, lines, {:file, source_path}}
    else
      _ -> try_reconstruct_from_dbgi(beam_path)
    end
  end

  # Get original source path from CInf chunk
  defp get_source_path(beam_path) do
    case :beam_lib.chunks(to_charlist(beam_path), [:compile_info]) do
      {:ok, {_, [{:compile_info, info}]}} ->
        case Keyword.get(info, :source) do
          nil -> {:error, :no_source_path}
          path -> {:ok, to_string(path)}
        end

      _ ->
        {:error, :no_compile_info}
    end
  end

  # Load source from a file path
  defp load_from_file(path) do
    case File.read(path) do
      {:ok, content} ->
        lines =
          content
          |> String.split("\n")
          |> Enum.with_index(1)
          |> Map.new(fn {text, num} -> {num, text} end)

        {:ok, lines}

      {:error, reason} ->
        {:error, {:file_error, reason}}
    end
  end

  # Try to reconstruct source from Dbgi chunk
  defp try_reconstruct_from_dbgi(beam_path) do
    case :beam_lib.chunks(to_charlist(beam_path), [:debug_info]) do
      {:ok, {_, [{:debug_info, {:debug_info_v1, backend, data}}]}} ->
        case reconstruct_source(backend, data) do
          {:ok, lines} -> {:ok, lines, :reconstructed}
          error -> error
        end

      {:ok, {_, [{:debug_info, :no_debug_info}]}} ->
        {:error, :no_debug_info}

      _ ->
        {:error, :no_debug_info}
    end
  end

  # Reconstruct source from Elixir debug info
  defp reconstruct_source(:elixir_erl, {:elixir_v1, map, _}) do
    # Elixir stores definitions as AST
    case Map.get(map, :definitions) do
      nil ->
        {:error, :no_definitions}

      definitions ->
        lines = reconstruct_elixir_defs(definitions, map)
        {:ok, lines}
    end
  end

  # Reconstruct source from Erlang abstract code
  # Old format: {:raw_abstract_v1, forms}
  defp reconstruct_source(:erl_abstract_code, {:raw_abstract_v1, forms}) do
    lines = reconstruct_erlang_forms(forms)
    {:ok, lines}
  end

  # New format (OTP 24+): {forms, options} where forms is a list of abstract forms
  defp reconstruct_source(:erl_abstract_code, {forms, _options}) when is_list(forms) do
    lines = reconstruct_erlang_forms(forms)
    {:ok, lines}
  end

  defp reconstruct_source(_, _), do: {:error, :unknown_debug_format}

  # Reconstruct Elixir definitions to source-like text
  defp reconstruct_elixir_defs(definitions, map) do
    module_name = Map.get(map, :module, :unknown)

    # Build a map of line -> reconstructed text (just function heads, not bodies)
    lines =
      for {{name, _arity}, kind, _meta, clauses} <- definitions,
          {meta, args, _guards, _body} <- clauses do
        line = Keyword.get(meta, :line, 0)

        # Just show the function head, not the body
        head = reconstruct_function_head(kind, name, args)

        {line, head}
      end

    # Add module declaration at line 1 if not present
    lines = [{1, "defmodule #{inspect(module_name)} do"} | lines]

    Map.new(lines)
  end

  defp reconstruct_function_head(:def, name, args) do
    args_str = args |> Enum.map(&try_macro_to_string/1) |> Enum.join(", ")
    "def #{name}(#{args_str})"
  end

  defp reconstruct_function_head(:defp, name, args) do
    args_str = args |> Enum.map(&try_macro_to_string/1) |> Enum.join(", ")
    "defp #{name}(#{args_str})"
  end

  defp reconstruct_function_head(:defmacro, name, args) do
    args_str = args |> Enum.map(&try_macro_to_string/1) |> Enum.join(", ")
    "defmacro #{name}(#{args_str})"
  end

  defp reconstruct_function_head(_kind, name, args) do
    args_str = args |> Enum.map(&try_macro_to_string/1) |> Enum.join(", ")
    "def #{name}(#{args_str})"
  end

  defp try_macro_to_string(ast) do
    try do
      Macro.to_string(ast)
    rescue
      _ -> inspect(ast, limit: 50)
    end
  end

  # Reconstruct Erlang abstract forms to source-like text
  defp reconstruct_erlang_forms(forms) do
    forms
    |> Enum.flat_map(&reconstruct_erlang_form/1)
    |> Map.new()
  end

  # Extract line number from Erlang anno (handles both old integer and new {line, col} format)
  defp extract_line({line, _col}) when is_integer(line), do: line
  defp extract_line(line) when is_integer(line), do: line
  defp extract_line(_), do: 0

  defp reconstruct_erlang_form({:function, anno, name, arity, clauses}) do
    line = extract_line(anno)
    # Build a simple representation
    clause_texts =
      Enum.map(clauses, fn {:clause, _cline, args, _guards, _body} ->
        args_str = Enum.map_join(args, ", ", &erl_pp_form/1)
        "#{name}(#{args_str}) -> ..."
      end)

    [{line, "#{name}/#{arity}: " <> Enum.join(clause_texts, "; ")}]
  end

  defp reconstruct_erlang_form({:attribute, anno, :module, name}) do
    line = extract_line(anno)
    [{line, "-module(#{name})."}]
  end

  defp reconstruct_erlang_form({:attribute, anno, :export, exports}) do
    line = extract_line(anno)
    exports_str = Enum.map_join(exports, ", ", fn {n, a} -> "#{n}/#{a}" end)
    [{line, "-export([#{exports_str}])."}]
  end

  defp reconstruct_erlang_form(_), do: []

  # Simple Erlang term pretty-printing
  defp erl_pp_form({:var, _, name}), do: to_string(name)
  defp erl_pp_form({:atom, _, name}), do: to_string(name)
  defp erl_pp_form({:integer, _, n}), do: to_string(n)
  defp erl_pp_form({:float, _, f}), do: to_string(f)
  defp erl_pp_form({:string, _, s}), do: inspect(to_string(s))
  defp erl_pp_form({:char, _, c}), do: "$#{<<c::utf8>>}"
  defp erl_pp_form({nil, _}), do: "[]"
  # Cons cell (list pattern)
  defp erl_pp_form({:cons, _, head, tail}) do
    "[#{erl_pp_form(head)} | #{erl_pp_form(tail)}]"
  end

  # Tuple pattern
  defp erl_pp_form({:tuple, _, elements}) do
    "{#{Enum.map_join(elements, ", ", &erl_pp_form/1)}}"
  end

  # Map pattern
  defp erl_pp_form({:map, _, pairs}) do
    pairs_str =
      Enum.map_join(pairs, ", ", fn
        {:map_field_exact, _, k, v} -> "#{erl_pp_form(k)} := #{erl_pp_form(v)}"
        {:map_field_assoc, _, k, v} -> "#{erl_pp_form(k)} => #{erl_pp_form(v)}"
        other -> inspect(other, limit: 10)
      end)

    "\#{#{pairs_str}}"
  end

  # Binary pattern
  defp erl_pp_form({:bin, _, _}), do: "<<...>>"
  # Match pattern
  defp erl_pp_form({:match, _, left, right}) do
    "#{erl_pp_form(left)} = #{erl_pp_form(right)}"
  end

  defp erl_pp_form(other), do: inspect(other, limit: 20)
end
