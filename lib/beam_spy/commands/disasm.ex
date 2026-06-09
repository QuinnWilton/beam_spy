defmodule BeamSpy.Commands.Disasm do
  @moduledoc """
  Disassemble BEAM bytecode into readable assembly.

  Uses `BeamFile.disassemble/1` to extract bytecode and formats it
  with opcode categories for theming.
  """

  alias BeamSpy.BeamFile
  alias BeamSpy.Format
  alias BeamSpy.Instruction
  alias BeamSpy.Opcodes
  alias BeamSpy.Render
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
      typed_instructions: Enum.map(instructions, &Instruction.from_raw/1),
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
    {category, to_string(opcode), Render.raw_args(opcode, args)}
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
    {source_lines, line_table, source_type} = load_source_if_requested(opts)
    theme = Keyword.get(opts, :theme, Theme.default())

    module_label = Theme.styled_string("module:", "ui.key", theme)
    module_name = Theme.styled_string(inspect(result.module), "module", theme)
    exports_label = Theme.styled_string("exports:", "ui.key", theme)
    exports_list = result.exports |> Enum.map_join(", ", &format_export/1)

    header = "#{module_label} #{module_name}\n#{exports_label} [#{exports_list}]\n"

    functions =
      result.functions
      |> Enum.map(&format_function_text(&1, source_lines, line_table, source_type, theme))
      |> Enum.join("\n")

    header <> "\n" <> functions
  end

  defp load_source_if_requested(opts) do
    case Keyword.get(opts, :source) do
      true ->
        path = Keyword.get(opts, :path)

        {source_lines, source_type} =
          case Source.load_source(path) do
            {:ok, lines, type} -> {lines, type}
            _ -> {%{}, nil}
          end

        line_table =
          case Source.parse_line_table(path) do
            {:ok, table} -> table
            _ -> %{}
          end

        {source_lines, line_table, source_type}

      _ ->
        {%{}, %{}, nil}
    end
  end

  defp format_function_text(func, source_lines, line_table, source_type, theme) do
    func_header = "function #{func.name}/#{func.arity} (entry: #{func.entry})"
    styled_header = Theme.styled_string(func_header, "ui.header", theme)
    border = Theme.styled_string(String.duplicate("─", 56), "ui.border", theme)

    header = "\n#{styled_header}\n#{border}\n"

    # source_lines being non-empty means we have actual source to show
    # line_table being non-empty means source was requested (even if unavailable)
    source_requested_but_unavailable = map_size(source_lines) == 0 and map_size(line_table) > 0

    instructions =
      if map_size(source_lines) > 0 do
        format_instructions_with_source(func, source_lines, line_table, source_type, theme)
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

  # --- Source Interleaving ---
  #
  # When --source is enabled, we interleave source code with bytecode.
  # The algorithm:
  #   1. Group instructions by their line markers
  #   2. For each group, decide whether to show full source or a reference
  #   3. "Near" lines (within @home_range of the function's first line) show source
  #   4. "Distant" lines (likely inlined code) show just a reference with function name
  #   5. For real source files, we fill small gaps between consecutive line markers

  # Lines more than this distance from the function's home line are
  # considered "distant" (likely inlined from other functions).
  @home_range 100

  # Small gaps (≤ this many lines) are filled when showing source from real files.
  @small_gap 10

  # Pattern to detect function definitions (for gap-filling boundaries and function index).
  @func_def_pattern ~r/^\s*((def|defp|defmacro|defmacrop|defguard|defguardp|defdelegate)\s+(\w+)|\s*(\w+)\/\d+:)/

  defp format_instructions_with_source(func, source_lines, line_table, source_type, theme) do
    grouped = Source.group_by_line(func.raw_instructions, line_table)
    home_line = first_line_number(grouped)
    source_path = if match?({:file, _}, source_type), do: elem(source_type, 1)
    can_fill_gaps? = match?({:file, _}, source_type)

    # Build function index lazily - only if we'll need it for distant references
    func_index = lazy_func_index(source_lines, grouped, home_line)

    grouped
    |> with_end_lines(source_lines, can_fill_gaps?)
    |> Enum.map_join("\n", fn {start_line, end_line, insts} ->
      parsed = Enum.map(insts, &parse_instruction/1)

      format_line_group(
        start_line,
        end_line,
        home_line,
        source_path,
        source_lines,
        func_index,
        parsed,
        theme
      )
    end)
  end

  # Find the first actual line number (skip nil groups).
  defp first_line_number(grouped) do
    Enum.find_value(grouped, fn {line, _} -> line end)
  end

  # Only build the function index if there are distant lines that need it.
  defp lazy_func_index(source_lines, grouped, home_line) do
    has_distant? =
      Enum.any?(grouped, fn {line, _} ->
        line != nil and not line_near_home?(line, home_line)
      end)

    if has_distant?, do: build_function_index(source_lines), else: nil
  end

  # Annotate each group with its end line (for gap filling).
  defp with_end_lines(groups, source_lines, can_fill_gaps?) do
    groups
    |> Enum.chunk_every(2, 1, [{nil, []}])
    |> Enum.map(fn [{start, insts}, {next, _}] ->
      end_line = compute_end_line(start, next, source_lines, can_fill_gaps?)
      {start, end_line, insts}
    end)
  end

  # Determine the end line for a group. Gap-filling only happens for real source
  # files when the gap is small and contains no function boundaries.
  defp compute_end_line(nil, _, _, _), do: nil
  defp compute_end_line(start, _, _, false), do: start
  defp compute_end_line(start, nil, _, _), do: start

  defp compute_end_line(start, next, source_lines, true)
       when next > start and next - start <= @small_gap do
    case find_func_boundary_in_range(source_lines, start + 1, next - 1) do
      nil -> next - 1
      boundary -> max(start, boundary - 1)
    end
  end

  defp compute_end_line(start, _, _, _), do: start

  # Find the first function definition in a line range (stops gap-filling there).
  defp find_func_boundary_in_range(source_lines, from, to) when from <= to do
    Enum.find(from..to, fn line ->
      case Map.get(source_lines, line) do
        nil -> false
        text -> Regex.match?(@func_def_pattern, text)
      end
    end)
  end

  defp find_func_boundary_in_range(_, _, _), do: nil

  # Build a map of line_number -> function_name for all lines in the source.
  # Each line maps to the function that contains it (the most recent def above it).
  defp build_function_index(source_lines) do
    # Find all function definitions
    func_defs =
      source_lines
      |> Enum.flat_map(fn {line, text} ->
        case extract_func_name(text) do
          nil -> []
          name -> [{line, name}]
        end
      end)
      |> Enum.sort_by(&elem(&1, 0))

    case func_defs do
      [] ->
        %{}

      _ ->
        func_starts = Map.new(func_defs)
        max_line = source_lines |> Map.keys() |> Enum.max(fn -> 0 end)

        # Walk through lines, tracking current function
        {result, _} =
          Enum.reduce(1..max_line, {%{}, nil}, fn line, {map, current} ->
            new_func = Map.get(func_starts, line, current)

            if new_func do
              {Map.put(map, line, new_func), new_func}
            else
              {map, current}
            end
          end)

        result
    end
  end

  # Extract function name from Elixir (def foo) or Erlang (foo/N:) format.
  # Elixir match returns 4 elements: [full, outer, keyword, name]
  # Erlang match returns 5 elements: [full, outer, "", "", name]
  defp extract_func_name(text) do
    case Regex.run(@func_def_pattern, text) do
      [_, _, _, name] when is_binary(name) -> name
      [_, _, _, _, name] when is_binary(name) and name != "" -> name
      _ -> nil
    end
  end

  # Direct map lookup for function containing a line.
  defp lookup_func_name(nil, _line), do: nil
  defp lookup_func_name(func_index, line), do: Map.get(func_index, line)

  # Check if a line is within reasonable range of the home line.
  defp line_near_home?(_line, nil), do: true
  defp line_near_home?(line, home), do: abs(line - home) <= @home_range

  # --- Formatting ---

  defp format_line_group(nil, _, _, _, _, _, instructions, theme) do
    format_bytecode_block(instructions, theme)
  end

  defp format_line_group(start, end_line, home, path, source, func_index, instructions, theme) do
    if line_near_home?(start, home) do
      format_source_block(start, end_line, path, source, instructions, theme)
    else
      format_distant_reference(start, path, func_index, instructions, theme)
    end
  end

  # Format a distant line as a reference (shows function name if known).
  defp format_distant_reference(line_num, source_path, func_index, instructions, theme) do
    func_name = lookup_func_name(func_index, line_num)

    ref_text = if func_name, do: "#{func_name} (line #{line_num})", else: "line #{line_num}"
    styled_ref = Theme.styled_string(ref_text, "ui.dim", theme)

    linked_ref =
      if source_path, do: make_hyperlink(styled_ref, source_path, line_num), else: styled_ref

    arrow = Theme.styled_string("→", "ui.dim", theme)
    header = "#{arrow} #{linked_ref}"

    join_blocks([header, format_bytecode_block(instructions, theme)])
  end

  # Format source lines followed by bytecode.
  defp format_source_block(start_line, end_line, source_path, source_lines, instructions, theme) do
    border = Theme.styled_string("│", "ui.border", theme)

    # Collect non-empty source lines
    lines_with_text =
      for line <- start_line..end_line,
          text = Map.get(source_lines, line),
          text != nil and String.trim(text) != "",
          do: {line, text}

    source_header =
      case lines_with_text do
        [] ->
          # No source text - just show line number
          "#{format_line_number(start_line, source_path, theme)} #{border}"

        lines ->
          # Dedent and format each source line
          min_indent = lines |> Enum.map(&elem(&1, 1)) |> find_min_indent()

          lines
          |> Enum.map(fn {line, text} ->
            dedented = remove_indent(text, min_indent)
            line_styled = format_line_number(line, source_path, theme)
            source_styled = Theme.styled_string(dedented, "ui.source", theme)
            "#{line_styled} #{border} #{source_styled}"
          end)
          |> Enum.join("\n")
      end

    join_blocks([source_header, format_bytecode_block(instructions, theme)])
  end

  # Format a block of bytecode instructions.
  defp format_bytecode_block(instructions, theme) do
    border = Theme.styled_string("│", "ui.border", theme)
    padding = "     "

    inst_lines =
      Enum.map(instructions, fn inst ->
        "#{padding}#{border}    #{format_instruction_text(inst, theme)}"
      end)

    trailing = "#{padding}#{border}"
    Enum.join(inst_lines ++ [trailing], "\n")
  end

  # Join non-empty blocks with newlines.
  defp join_blocks(blocks) do
    blocks |> Enum.reject(&(&1 == "")) |> Enum.join("\n")
  end

  # Format a line number with optional hyperlink.
  defp format_line_number(line, source_path, theme) do
    line_str = to_string(line)
    padding = String.duplicate(" ", max(0, 4 - String.length(line_str)))
    styled = Theme.styled_string(line_str, "ui.dim", theme)

    if source_path do
      padding <> make_hyperlink(styled, source_path, line)
    else
      padding <> styled
    end
  end

  # Create an OSC 8 hyperlink.
  defp make_hyperlink(text, file_path, line) do
    "\e]8;;file://#{file_path}:#{line}\e\\#{text}\e]8;;\e\\"
  end

  # --- Indentation helpers ---

  defp find_min_indent([]), do: 0
  defp find_min_indent(lines), do: lines |> Enum.map(&count_leading_spaces/1) |> Enum.min()

  defp count_leading_spaces(text) do
    text
    |> String.graphemes()
    |> Enum.take_while(&(&1 in [" ", "\t"]))
    |> Enum.reduce(0, fn
      " ", n -> n + 1
      "\t", n -> n + 2
    end)
  end

  defp remove_indent(text, 0), do: text
  defp remove_indent(text, n), do: do_remove_indent(text, n)

  defp do_remove_indent(text, 0), do: text
  defp do_remove_indent("", _), do: ""
  defp do_remove_indent(" " <> rest, n), do: do_remove_indent(rest, n - 1)
  defp do_remove_indent("\t" <> rest, n) when n >= 2, do: do_remove_indent(rest, n - 2)
  defp do_remove_indent("\t" <> rest, 1), do: " " <> rest
  defp do_remove_indent(text, _), do: text

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
