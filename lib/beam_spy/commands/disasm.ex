defmodule BeamSpy.Commands.Disasm do
  @moduledoc """
  Disassemble BEAM bytecode into readable assembly.

  Uses `:beam_disasm.file/1` to extract bytecode and formats it
  with opcode categories for theming.
  """

  alias BeamSpy.Opcodes
  alias BeamSpy.Format

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
        format_output(result, opts)

      {:error, reason} ->
        "Error: #{inspect(reason)}"
    end
  end

  # Parse a function from beam_disasm output
  defp parse_function({:function, name, arity, entry, instructions}) do
    parsed_instructions = Enum.map(instructions, &parse_instruction/1)

    %{
      name: name,
      arity: arity,
      entry: entry,
      instructions: parsed_instructions
    }
  end

  # Parse a single instruction into {category, name, args}
  defp parse_instruction({:label, n}) do
    {:control, "label", [to_string(n)]}
  end

  defp parse_instruction({:line, n}) do
    {:meta, "line", [to_string(n)]}
  end

  defp parse_instruction({:func_info, mod, name, arity}) do
    {:error, "func_info", [format_arg(mod), format_arg(name), to_string(arity)]}
  end

  defp parse_instruction(:return) do
    {:return, "return", []}
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
  defp format_arg({:literal, lit}), do: inspect(lit, limit: 5, printable_limit: 50)
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
  defp format_arg(other), do: inspect(other, limit: 5)

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

  defp matches_function_filter?(%{name: name, arity: arity}, {:exact, pattern_name, pattern_arity}) do
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

  defp format_text(result, _opts) do
    header = """
    module: #{inspect(result.module)}
    exports: [#{Enum.map_join(result.exports, ", ", &format_export/1)}]
    """

    functions =
      result.functions
      |> Enum.map(&format_function_text/1)
      |> Enum.join("\n")

    header <> "\n" <> functions
  end

  defp format_function_text(func) do
    header = """

    function #{func.name}/#{func.arity} (entry: #{func.entry})
    #{String.duplicate("─", 56)}
    """

    instructions =
      func.instructions
      |> Enum.map(&format_instruction_text/1)
      |> Enum.join("\n")

    header <> instructions
  end

  defp format_instruction_text({_category, "label", [n]}) do
    "  label #{n}:"
  end

  defp format_instruction_text({_category, op, []}) do
    "  #{op}"
  end

  defp format_instruction_text({_category, op, args}) do
    "  #{op} #{Enum.join(args, ", ")}"
  end
end
