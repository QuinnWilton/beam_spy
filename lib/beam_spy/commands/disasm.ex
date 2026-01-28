defmodule BeamSpy.Commands.Disasm do
  @moduledoc """
  Disassemble BEAM bytecode into readable assembly.

  Uses `:beam_disasm.file/1` to extract bytecode and formats it
  with opcode categories for theming.
  """

  alias BeamSpy.Opcodes
  alias BeamSpy.Format
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
    case :beam_disasm.file(to_charlist(path)) do
      {:beam_file, module, exports, _attr, _compile_info, functions} ->
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

      {:error, _beam_lib, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Run disassembly and format output.
  """
  @spec run(String.t(), keyword()) :: String.t()
  def run(path, opts \\ []) do
    case extract(path, opts) do
      {:ok, result} ->
        # Add path to opts for source loading
        opts = Keyword.put(opts, :path, path)
        format_output(result, opts)

      {:error, reason} ->
        "Error: #{inspect(reason)}"
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
    formatted_args = Enum.map(args, &format_arg/1)
    {category, to_string(opcode), formatted_args}
  end

  # Format individual argument values
  defp format_arg({:x, n}), do: "x(#{n})"
  defp format_arg({:y, n}), do: "y(#{n})"
  defp format_arg({:fr, n}), do: "fr(#{n})"
  defp format_arg({:f, n}), do: "f(#{n})"
  defp format_arg({:atom, a}), do: inspect(a)
  defp format_arg({:integer, n}), do: to_string(n)
  defp format_arg({:literal, lit}), do: inspect(lit, limit: :infinity, printable_limit: 100)
  defp format_arg({:tr, reg, _type}), do: format_arg(reg)

  defp format_arg({:extfunc, m, f, a}) do
    "#{inspect(m)}:#{inspect(f)}/#{a}"
  end

  defp format_arg({:list, items}) do
    formatted = Enum.map(items, &format_arg/1)
    "[#{Enum.join(formatted, ", ")}]"
  end

  defp format_arg(nil), do: "[]"
  defp format_arg(n) when is_integer(n), do: to_string(n)
  defp format_arg(a) when is_atom(a), do: inspect(a)
  defp format_arg({tag, value}) when is_atom(tag), do: "{#{tag}, #{format_arg(value)}}"
  defp format_arg(other), do: inspect(other, limit: :infinity)

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

    instructions =
      if map_size(source_lines) > 0 do
        format_instructions_with_source(func, source_lines, line_table, theme)
      else
        func.instructions
        |> Enum.map(&format_instruction_text(&1, theme))
        |> Enum.join("\n")
      end

    header <> instructions
  end

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
