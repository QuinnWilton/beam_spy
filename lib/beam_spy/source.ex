defmodule BeamSpy.Source do
  @moduledoc """
  Extract and correlate source code with bytecode.

  Loads source lines from the original file or reconstructs them
  from the debug info (Dbgi) chunk when available.
  """

  @doc """
  Load source lines for a module.

  Returns `{:ok, %{line_num => text}}` or `{:error, reason}`.

  Resolution order:
  1. Try original source file (path from CInf chunk)
  2. Fall back to AST reconstruction from Dbgi chunk
  3. Return error if neither available
  """
  @spec load_source(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def load_source(beam_path, opts \\ []) do
    case Keyword.get(opts, :source_path) do
      nil -> load_from_beam(beam_path)
      path -> load_from_file(path)
    end
  end

  @doc """
  Group instructions by their source line numbers.

  Takes a list of instructions (from disassembly) and groups them
  by the line number from {:line, N} pseudo-instructions.

  Returns a list of {line_number, [instructions]} where line_number
  can be nil for instructions before any line marker.
  """
  @spec group_by_line([tuple()]) :: [{non_neg_integer() | nil, [tuple()]}]
  def group_by_line(instructions) do
    {groups, current_line, current_insts} =
      Enum.reduce(instructions, {[], nil, []}, fn
        {:line, n}, {groups, current_line, current_insts} ->
          # Finish current group (if any) and start a new one
          new_groups =
            if current_insts != [] do
              [{current_line, Enum.reverse(current_insts)} | groups]
            else
              groups
            end

          {new_groups, n, []}

        {:meta, "line", [n_str]}, {groups, current_line, current_insts} ->
          # Handle parsed instruction format - same logic
          n = String.to_integer(n_str)

          new_groups =
            if current_insts != [] do
              [{current_line, Enum.reverse(current_insts)} | groups]
            else
              groups
            end

          {new_groups, n, []}

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
      {:ok, lines}
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
        reconstruct_source(backend, data)

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
  defp reconstruct_source(:erl_abstract_code, {:raw_abstract_v1, forms}) do
    lines = reconstruct_erlang_forms(forms)
    {:ok, lines}
  end

  defp reconstruct_source(_, _), do: {:error, :unknown_debug_format}

  # Reconstruct Elixir definitions to source-like text
  defp reconstruct_elixir_defs(definitions, map) do
    module_name = Map.get(map, :module, :unknown)

    # Build a map of line -> reconstructed text
    lines =
      for {{name, _arity}, kind, _meta, clauses} <- definitions,
          {meta, args, _guards, body} <- clauses do
        line = Keyword.get(meta, :line, 0)

        # Reconstruct the function head
        head = reconstruct_function_head(kind, name, args)

        # Try to reconstruct the body (simplified)
        body_text = try_macro_to_string(body)

        {line, "#{head}, do: #{body_text}"}
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

  defp reconstruct_erlang_form({:function, line, name, arity, clauses}) do
    # Build a simple representation
    clause_texts =
      Enum.map(clauses, fn {:clause, _cline, args, _guards, _body} ->
        args_str = Enum.map_join(args, ", ", &erl_pp_form/1)
        "#{name}(#{args_str}) -> ..."
      end)

    [{line, "#{name}/#{arity}: " <> Enum.join(clause_texts, "; ")}]
  end

  defp reconstruct_erlang_form({:attribute, line, :module, name}) do
    [{line, "-module(#{name})."}]
  end

  defp reconstruct_erlang_form({:attribute, line, :export, exports}) do
    exports_str = Enum.map_join(exports, ", ", fn {n, a} -> "#{n}/#{a}" end)
    [{line, "-export([#{exports_str}])."}]
  end

  defp reconstruct_erlang_form(_), do: []

  # Simple Erlang term pretty-printing
  defp erl_pp_form({:var, _, name}), do: to_string(name)
  defp erl_pp_form({:atom, _, name}), do: to_string(name)
  defp erl_pp_form({:integer, _, n}), do: to_string(n)
  defp erl_pp_form({nil, _}), do: "[]"
  defp erl_pp_form(other), do: inspect(other, limit: 20)
end
