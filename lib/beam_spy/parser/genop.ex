defmodule BeamSpy.Parser.Genop do
  @moduledoc """
  Parse OTP's genop.tab file at compile time.

  The genop.tab file defines all BEAM opcodes with their numbers, names,
  arities, and documentation.

  ## Line Formats

  - `# ...` - Single hash comment (ignored)
  - `## @spec name Arg1 Arg2 ...` - Parameter specification
  - `## @doc Description...` - Documentation
  - `##      Continuation...` - Documentation continuation
  - `N: name/arity` - Active opcode definition
  - `N: -name/arity` - Deprecated opcode
  - `BEAM_FORMAT_NUMBER=N` - Format version (metadata)
  - blank lines - Section separators

  """

  @type opcode :: %{
          opcode: non_neg_integer(),
          name: atom(),
          arity: non_neg_integer(),
          deprecated: boolean(),
          spec: String.t() | nil,
          doc: String.t() | nil,
          args: [String.t()]
        }

  @doc """
  Parse genop.tab content into a list of opcode definitions.
  """
  @spec parse(String.t()) :: [opcode()]
  def parse(content) do
    content
    |> String.split("\n")
    |> parse_lines(nil, [])
    |> Enum.reverse()
  end

  # Parse state: {current_doc, results}
  # current_doc = %{spec: nil, doc: [], args: []}

  defp parse_lines([], _doc, acc), do: acc

  # Skip blank lines
  defp parse_lines(["" | rest], doc, acc) do
    parse_lines(rest, doc, acc)
  end

  # Skip BEAM_FORMAT_NUMBER line
  defp parse_lines(["BEAM_FORMAT_NUMBER" <> _ | rest], doc, acc) do
    parse_lines(rest, doc, acc)
  end

  # Parse @spec line: "## @spec name Arg1 Arg2 ..."
  # NOTE: Must come before the single-hash pattern below
  defp parse_lines(["## @spec " <> spec | rest], _doc, acc) do
    [name | args] = String.split(spec)
    new_doc = %{spec: spec, doc: [], args: args, spec_name: name}
    parse_lines(rest, new_doc, acc)
  end

  # Parse @doc line (first line): "## @doc Description..."
  defp parse_lines(["## @doc " <> text | rest], doc, acc) do
    new_doc = if doc, do: %{doc | doc: [text]}, else: %{spec: nil, doc: [text], args: []}
    parse_lines(rest, new_doc, acc)
  end

  # Parse continuation doc line: "##      More text..."
  defp parse_lines(["##" <> text | rest], %{doc: lines} = doc, acc) when lines != [] do
    # Strip leading whitespace from continuation
    text = String.trim_leading(text)
    new_doc = %{doc | doc: [text | lines]}
    parse_lines(rest, new_doc, acc)
  end

  # Skip single-hash comments (but not ## which are doc lines)
  # NOTE: Must come after ## patterns above
  defp parse_lines(["#" <> _ | rest], doc, acc) do
    parse_lines(rest, doc, acc)
  end

  # Parse opcode definition: "N: name/arity" or "N: -name/arity"
  defp parse_lines([line | rest], doc, acc) do
    case Regex.run(~r/^(\d+):\s*(-?)(\w+)\/(\d+)$/, line) do
      [_, num, deprecated, name, arity] ->
        opcode = %{
          opcode: String.to_integer(num),
          name: String.to_atom(name),
          arity: String.to_integer(arity),
          deprecated: deprecated == "-",
          spec: doc && doc[:spec],
          doc: doc && doc[:doc] |> Enum.reverse() |> Enum.join(" "),
          args: (doc && doc[:args]) || []
        }

        parse_lines(rest, nil, [opcode | acc])

      nil ->
        # Unknown line format, skip
        parse_lines(rest, doc, acc)
    end
  end
end
