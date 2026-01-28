defmodule BeamSpy.Commands.Disasm do
  @moduledoc """
  Disassemble BEAM bytecode into readable assembly.

  Uses `BeamFile.disassemble/1` to extract bytecode and formats it
  with opcode categories for theming.
  """

  alias BeamSpy.BeamFile
  alias BeamSpy.Format
  alias BeamSpy.Opcodes
  alias BeamSpy.Source
  alias BeamSpy.Theme

  @type function_info :: %{
          name: atom(),
          arity: non_neg_integer(),
          entry: non_neg_integer(),
          instructions: [instruction()]
        }

  @type instruction :: {atom(), atom() | String.t(), [String.t()]}

  @doc """
  Extract disassembled functions from a BEAM file.

  Returns `{:ok, result}` where result contains module info and functions.
  """
  @spec extract(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def extract(path, opts \\ []) do
    case BeamFile.disassemble(path) do
      {:ok, %{module: module, exports: exports, functions: functions}} ->
        funcs = Enum.map(functions, &parse_function/1)

        funcs =
          case Keyword.get(opts, :function) do
            nil -> funcs
            pattern -> filter_functions(funcs, pattern)
          end

        {:ok,
         %{
           module: module,
           exports: exports,
           functions: funcs
         }}

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  Run disassembly and format output.
  """
  @spec run(String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def run(path, opts \\ []) do
    case extract(path, opts) do
      {:ok, result} ->
        # Add path to opts for source loading
        opts = Keyword.put(opts, :path, path)
        {:ok, format_output(result, opts)}

      {:error, reason} ->
        {:error, Format.format_beam_error(reason)}
    end
  end

  # Parse a function from beam_disasm output
  defp parse_function({:function, name, arity, entry, instructions}) do
    parsed_instructions = Enum.map(instructions, &parse_instruction/1)

    # Extract line numbers for source correlation
    line_mapping = extract_line_mapping(instructions)

    %{
      name: name,
      arity: arity,
      entry: entry,
      instructions: parsed_instructions,
      raw_instructions: instructions,
      line_mapping: line_mapping
    }
  end

  # Extract a mapping of instruction index to line number
  defp extract_line_mapping(instructions) do
    {mapping, _current_line, _idx} =
      Enum.reduce(instructions, {%{}, nil, 0}, fn
        {:line, n}, {map, _line, idx} ->
          {Map.put(map, idx, n), n, idx + 1}

        _inst, {map, line, idx} ->
          if line do
            {Map.put(map, idx, line), line, idx + 1}
          else
            {map, line, idx + 1}
          end
      end)

    mapping
  end

  # Parse a single instruction into {category, name, args}.
  # Categories are looked up via Opcodes.category/1 which is generated from genop.tab.
  defp parse_instruction(opcode) when is_atom(opcode) do
    category = Opcodes.category(opcode)
    {category, to_string(opcode), []}
  end

  defp parse_instruction({opcode}) when is_atom(opcode) do
    category = Opcodes.category(opcode)
    {category, to_string(opcode), []}
  end

  defp parse_instruction(instruction) when is_tuple(instruction) do
    [opcode | args] = Tuple.to_list(instruction)
    category = Opcodes.category(opcode)
    formatted_args = format_instruction_args(opcode, args)
    {category, to_string(opcode), formatted_args}
  end

  # Special formatting for specific instructions
  defp format_instruction_args(:get_map_elements, [fail, src, {:list, pairs}]) do
    [format_arg(fail), format_arg(src), format_map_get_pairs(pairs)]
  end

  defp format_instruction_args(:get_map_elements, [fail, src, pairs]) when is_list(pairs) do
    [format_arg(fail), format_arg(src), format_map_get_pairs(pairs)]
  end

  defp format_instruction_args(:put_map_assoc, [fail, src, dst, live, {:list, pairs}]) do
    [format_arg(fail), format_arg(src), format_arg(dst), format_arg(live), format_map_put_pairs(pairs)]
  end

  defp format_instruction_args(:put_map_assoc, [fail, src, dst, live, pairs]) when is_list(pairs) do
    [format_arg(fail), format_arg(src), format_arg(dst), format_arg(live), format_map_put_pairs(pairs)]
  end

  defp format_instruction_args(:put_map_exact, [fail, src, dst, live, {:list, pairs}]) do
    [format_arg(fail), format_arg(src), format_arg(dst), format_arg(live), format_map_put_pairs(pairs)]
  end

  defp format_instruction_args(:put_map_exact, [fail, src, dst, live, pairs]) when is_list(pairs) do
    [format_arg(fail), format_arg(src), format_arg(dst), format_arg(live), format_map_put_pairs(pairs)]
  end

  defp format_instruction_args(_opcode, args) do
    Enum.map(args, &format_arg/1)
  end

  # Format get_map_elements pairs: [key, dest, key, dest, ...] -> [key => dest, ...]
  defp format_map_get_pairs(pairs) do
    pairs
    |> Enum.chunk_every(2)
    |> Enum.map(fn
      [key, dest] -> "#{format_map_key(key)} => #{format_arg(dest)}"
      other -> Enum.map_join(other, ", ", &format_arg/1)
    end)
    |> then(fn formatted -> "[#{Enum.join(formatted, ", ")}]" end)
    |> truncate_if_long(80)
  end

  # Format put_map pairs: [key, val, key, val, ...] -> %{key: val, ...}
  defp format_map_put_pairs(pairs) do
    pairs
    |> Enum.chunk_every(2)
    |> Enum.map(fn
      [key, val] -> "#{format_map_key(key)}: #{format_arg(val)}"
      other -> Enum.map_join(other, ", ", &format_arg/1)
    end)
    |> then(fn formatted -> "%{#{Enum.join(formatted, ", ")}}" end)
    |> truncate_if_long(80)
  end

  # Format map keys - show atoms without leading colon for cleaner syntax
  defp format_map_key({:atom, a}), do: to_string(a)
  defp format_map_key({:literal, a}) when is_atom(a), do: to_string(a)
  defp format_map_key(other), do: format_arg(other)

  # Format individual argument values
  defp format_arg({:x, n}), do: "x(#{n})"
  defp format_arg({:y, n}), do: "y(#{n})"
  defp format_arg({:fr, n}), do: "fr(#{n})"
  defp format_arg({:f, n}), do: "f(#{n})"
  defp format_arg({:atom, a}), do: inspect(a)
  defp format_arg({:integer, n}), do: to_string(n)
  defp format_arg({:literal, lit}), do: format_literal(lit)
  # Typed register - just show the register, ignore JIT type info
  defp format_arg({:tr, reg, _type}), do: format_arg(reg)

  defp format_arg({:extfunc, m, f, a}) do
    "#{inspect(m)}:#{inspect(f)}/#{a}"
  end

  # Format alloc tuples compactly: {alloc, [{words, 2}, {floats, 0}, {funs, 1}]} -> alloc(w:2, fn:1)
  defp format_arg({:alloc, props}) when is_list(props) do
    parts =
      props
      |> Enum.filter(fn {_key, val} -> val != 0 end)
      |> Enum.map(fn
        {:words, n} -> "w:#{n}"
        {:floats, n} -> "fl:#{n}"
        {:funs, n} -> "fn:#{n}"
        {key, val} -> "#{key}:#{val}"
      end)

    case parts do
      [] -> "alloc()"
      _ -> "alloc(#{Enum.join(parts, ", ")})"
    end
  end

  # Format string tuples in bs_create_bin - show actual string content
  defp format_arg({:string, bin}) when is_binary(bin) do
    if String.printable?(bin) do
      truncated = if byte_size(bin) > 30, do: String.slice(bin, 0, 27) <> "...", else: bin
      "{string, #{inspect(truncated)}}"
    else
      "{string, <<#{byte_size(bin)} bytes>>}"
    end
  end

  # Handle both {:list, items} from beam_disasm and raw Elixir lists
  defp format_arg({:list, items}), do: format_arg_list(items)
  defp format_arg(items) when is_list(items), do: format_arg_list(items)

  defp format_arg(nil), do: "[]"
  defp format_arg(n) when is_integer(n), do: to_string(n)
  defp format_arg(a) when is_atom(a), do: inspect(a)
  defp format_arg(bin) when is_binary(bin), do: format_literal(bin)
  defp format_arg({tag, value}) when is_atom(tag), do: "{#{tag}, #{format_arg(value)}}"
  defp format_arg(other), do: format_literal(other)

  defp format_arg_list(items) do
    formatted = Enum.map(items, &format_arg/1)
    result = "[#{Enum.join(formatted, ", ")}]"
    truncate_if_long(result, 80)
  end

  # Format literals with truncation for readability
  defp format_literal(lit) when is_binary(lit) do
    if byte_size(lit) > 20 do
      # Show first few bytes of binary
      preview = binary_part(lit, 0, min(16, byte_size(lit)))
      "<<#{inspect_binary_bytes(preview)}...>> (#{byte_size(lit)} bytes)"
    else
      inspect(lit)
    end
  end

  defp format_literal(lit) when is_list(lit) do
    result = inspect(lit, limit: 8, printable_limit: 50)
    truncate_if_long(result, 80)
  end

  defp format_literal(lit) when is_map(lit) do
    result = inspect(lit, limit: 4, printable_limit: 50)
    truncate_if_long(result, 80)
  end

  defp format_literal(lit) do
    result = inspect(lit, limit: 8, printable_limit: 50)
    truncate_if_long(result, 80)
  end

  defp inspect_binary_bytes(bin) do
    bin
    |> :binary.bin_to_list()
    |> Enum.map_join(", ", &to_string/1)
  end

  defp truncate_if_long(str, max_len) do
    if String.length(str) > max_len do
      String.slice(str, 0, max_len) <> "..."
    else
      str
    end
  end

  # Filter functions by pattern
  defp filter_functions(funcs, pattern) do
    filter = parse_function_filter(pattern)

    Enum.filter(funcs, fn func ->
      matches_function_filter?(func, filter)
    end)
  end

  defp parse_function_filter(pattern) do
    cond do
      # Exact match with arity: foo/2
      String.contains?(pattern, "/") ->
        [name, arity] = String.split(pattern, "/", parts: 2)
        {:exact, name, String.to_integer(arity)}

      # Glob pattern: foo*, *bar, handle_*
      String.contains?(pattern, "*") ->
        {:glob, pattern}

      # Simple name match
      true ->
        {:name, pattern}
    end
  end

  defp matches_function_filter?(
         %{name: name, arity: arity},
         {:exact, pattern_name, pattern_arity}
       ) do
    to_string(name) == pattern_name and arity == pattern_arity
  end

  defp matches_function_filter?(%{name: name}, {:glob, pattern}) do
    regex =
      pattern
      |> Regex.escape()
      |> String.replace("\\*", ".*")
      |> then(&Regex.compile!("^#{&1}$"))

    Regex.match?(regex, to_string(name))
  end

  defp matches_function_filter?(%{name: name}, {:name, pattern}) do
    String.contains?(to_string(name), pattern)
  end

  # Format output based on options
  defp format_output(result, opts) do
    case Keyword.get(opts, :format, :text) do
      :json -> format_json(result)
      :text -> format_text(result, opts)
      _ -> format_text(result, opts)
    end
  end

  defp format_json(result) do
    data = %{
      module: to_string(result.module),
      exports: Enum.map(result.exports, &format_export/1),
      functions:
        Enum.map(result.functions, fn func ->
          %{
            name: to_string(func.name),
            arity: func.arity,
            entry: func.entry,
            instructions:
              Enum.map(func.instructions, fn {_category, op, args} ->
                %{op: op, args: args}
              end)
          }
        end)
    }

    Format.json(data)
  end

  # Format export tuple - can be {name, arity} or {name, arity, label}
  defp format_export({name, arity}), do: "#{name}/#{arity}"
  defp format_export({name, arity, _label}), do: "#{name}/#{arity}"

  defp format_text(result, opts) do
    {source_lines, line_table} = load_source_if_requested(opts)
    theme = Keyword.get(opts, :theme, Theme.default())

    module_label = Theme.styled_string("module:", "ui.key", theme)
    module_name = Theme.styled_string(inspect(result.module), "module", theme)
    exports_label = Theme.styled_string("exports:", "ui.key", theme)
    exports_list = result.exports |> Enum.map_join(", ", &format_export/1)

    header = "#{module_label} #{module_name}\n#{exports_label} [#{exports_list}]\n"

    functions =
      result.functions
      |> Enum.map(&format_function_text(&1, source_lines, line_table, theme))
      |> Enum.join("\n")

    header <> "\n" <> functions
  end

  defp load_source_if_requested(opts) do
    case Keyword.get(opts, :source) do
      true ->
        path = Keyword.get(opts, :path)

        source_lines =
          case Source.load_source(path) do
            {:ok, lines} -> lines
            _ -> %{}
          end

        line_table =
          case Source.parse_line_table(path) do
            {:ok, table} -> table
            _ -> %{}
          end

        {source_lines, line_table}

      _ ->
        {%{}, %{}}
    end
  end

  defp format_function_text(func, source_lines, line_table, theme) do
    func_header = "function #{func.name}/#{func.arity} (entry: #{func.entry})"
    styled_header = Theme.styled_string(func_header, "ui.header", theme)
    border = Theme.styled_string(String.duplicate("─", 56), "ui.border", theme)

    header = "\n#{styled_header}\n#{border}\n"

    # source_lines being non-empty means we have actual source to show
    # line_table being non-empty means source was requested (even if unavailable)
    source_requested_but_unavailable = map_size(source_lines) == 0 and map_size(line_table) > 0

    instructions =
      if map_size(source_lines) > 0 do
        format_instructions_with_source(func, source_lines, line_table, theme)
      else
        func.instructions
        |> maybe_filter_line_instructions(source_requested_but_unavailable)
        |> Enum.map(&format_instruction_text(&1, theme))
        |> Enum.join("\n")
      end

    header <> instructions
  end

  # Filter out line instructions when source was requested but unavailable
  defp maybe_filter_line_instructions(instructions, true) do
    Enum.reject(instructions, fn {_category, name, _args} -> name == "line" end)
  end

  defp maybe_filter_line_instructions(instructions, false), do: instructions

  defp format_instructions_with_source(func, source_lines, line_table, theme) do
    # Group instructions by line number, resolving indices via line_table
    grouped = Source.group_by_line(func.raw_instructions, line_table)

    grouped
    |> Enum.map(fn {line_num, insts} ->
      parsed_insts = Enum.map(insts, &parse_instruction/1)
      format_source_group(line_num, source_lines, parsed_insts, theme)
    end)
    |> Enum.join("\n")
  end

  defp format_source_group(nil, _source_lines, instructions, theme) do
    border = Theme.styled_string("│", "ui.border", theme)
    padding = "     "

    inst_text =
      instructions
      |> Enum.map(fn inst ->
        "#{padding}#{border}    " <> String.trim_leading(format_instruction_text(inst, theme))
      end)
      |> Enum.join("\n")

    trailing = "#{padding}#{border}"
    inst_text <> "\n" <> trailing
  end

  defp format_source_group(line_num, source_lines, instructions, theme) do
    case Map.get(source_lines, line_num) do
      nil ->
        format_source_group(nil, source_lines, instructions, theme)

      text ->
        text = String.trim_leading(text)

        if text == "" do
          format_source_group(nil, source_lines, instructions, theme)
        else
          border = Theme.styled_string("│", "ui.border", theme)
          padding = "     "

          line_num_styled =
            Theme.styled_string(String.pad_leading(to_string(line_num), 4), "ui.dim", theme)

          source_styled = Theme.styled_string(text, "ui.source", theme)
          source_header = "#{line_num_styled} #{border} #{source_styled}"

          inst_text =
            instructions
            |> Enum.map(fn inst ->
              "#{padding}#{border}    " <>
                String.trim_leading(format_instruction_text(inst, theme))
            end)
            |> Enum.join("\n")

          trailing = "#{padding}#{border}"

          [source_header, inst_text, trailing]
          |> Enum.join("\n")
        end
    end
  end

  defp format_instruction_text({_category, "label", [n]}, theme) do
    label = Theme.styled_string("label", "label", theme)
    num = Theme.styled_string(n, "label", theme)
    "  #{label} #{num}:"
  end

  defp format_instruction_text({category, op, []}, theme) do
    styled_op = Theme.styled_string(op, "opcode.#{category}", theme)
    "  #{styled_op}"
  end

  defp format_instruction_text({category, op, args}, theme) do
    styled_op = Theme.styled_string(op, "opcode.#{category}", theme)
    styled_args = Enum.map(args, &style_arg(&1, theme))
    "  #{styled_op} #{Enum.join(styled_args, ", ")}"
  end

  # Style arguments based on their type
  defp style_arg(arg, theme) do
    cond do
      String.starts_with?(arg, "x(") ->
        Theme.styled_string(arg, "register.x", theme)

      String.starts_with?(arg, "y(") ->
        Theme.styled_string(arg, "register.y", theme)

      String.starts_with?(arg, "fr(") ->
        Theme.styled_string(arg, "register.fr", theme)

      String.starts_with?(arg, "f(") ->
        Theme.styled_string(arg, "label", theme)

      String.starts_with?(arg, ":") ->
        Theme.styled_string(arg, "atom", theme)

      Regex.match?(~r/^-?\d+$/, arg) ->
        Theme.styled_string(arg, "number", theme)

      String.contains?(arg, ":/") ->
        # External function call like Enum:map/2
        Theme.styled_string(arg, "function", theme)

      true ->
        arg
    end
  end
end
