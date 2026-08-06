defmodule BeamSpy.DebugInfo do
  @moduledoc """
  Parses the `DbgB` chunk — OTP 28's BEAM debug information, emitted by
  the `beam_debug_info` compiler option.

  The chunk stores one dense item per `debug_line/4` instruction —
  frame size plus the live source variables, `{name, {:x, n} | {:y, n}
  | {:value, constant}}` (every variable's register, or its
  compile-time value when the compiler folded it). Items are positional
  (the absolute `Index` operands are dropped at emit time), so
  `by_line/1` recovers the mapping by offsetting each `debug_line`'s
  `Index` against the module's smallest one.

  This is the static equivalent of `code:get_debug_info/1`: no module
  loading, no `+D` emulator flag. `parse/1` returns the chunk as-is
  (positional); `by_line/1` joins it with the code's `debug_line`
  instructions and the Line chunk to key entries by source line.

  ## Encoding

  Each item is a complete BEAM-encoded pseudo-instruction
  `{call, FrameSize, {list, [Name, Where, ...]}}` (the `call` opcode is
  used only because it has two operands — see `beam_asm:build_bdi/2`).
  Operands use the compact term format (`CTF`); variable names are
  literal-table references, except entry items which may name
  parameters by position.
  """

  alias BeamSpy.BeamFile
  alias BeamSpy.Commands.Atoms
  alias BeamSpy.Commands.Literals
  alias BeamSpy.Source

  # genop.tab: call/2 = opcode 4.
  @call_opcode 4

  @typedoc "Where a variable lives: a register, or its folded value."
  @type where :: {:x, non_neg_integer()} | {:y, non_neg_integer()} | {:value, term()}

  @typedoc "A variable name — a binary, or a parameter position in entry items."
  @type name :: binary() | non_neg_integer()

  @type item :: %{
          position: pos_integer(),
          frame: :none | :entry | non_neg_integer(),
          vars: [{name(), where()}]
        }

  @type line_entry :: %{
          line: pos_integer(),
          kind: :entry | :line,
          index: pos_integer(),
          frame: :none | :entry | non_neg_integer(),
          vars: [{name(), where()}]
        }

  @doc """
  Parses the `DbgB` chunk into positional items: `position` 1 is the
  first `debug_line` item in module order, and so on (the chunk does
  not store the absolute `Index` operands). Use `by_line/1` to key by
  source line.

  Returns `{:error, :missing_debug_chunk}` for beams compiled without
  `beam_debug_info`.
  """
  @spec parse(BeamFile.beam()) :: {:ok, [item()]} | {:error, term()}
  def parse(input) do
    with {:ok, beam} <- BeamFile.load(input),
         {:ok, chunk} <- debug_chunk(beam),
         {:ok, atoms} <- Atoms.extract(beam),
         {:ok, literals} <- Literals.extract(beam) do
      parse_chunk(chunk, List.to_tuple(atoms), Map.new(literals))
    end
  end

  @doc """
  The debug information keyed by source line: `parse/1` joined with the
  code's `debug_line` instructions through the Line chunk. A line can
  carry several entries (a function head has an `:entry` item and often
  a `:line` item).
  """
  @spec by_line(BeamFile.beam()) :: {:ok, [line_entry()]} | {:error, term()}
  def by_line(input) do
    with {:ok, beam} <- BeamFile.load(input),
         {:ok, items} <- parse(beam),
         {:ok, line_table} <- Source.parse_line_table(beam),
         {:ok, disasm} <- BeamFile.disassemble(beam) do
      debug_lines =
        for {:function, _name, _arity, _entry, instrs} <- disasm.functions,
            {:debug_line, {:atom, kind}, ref, index, _live} <- instrs,
            do: %{index: index, kind: kind, ref: ref}

      # Items are dense from the module's smallest debug_line Index, so
      # position (1-based) = Index - base + 1.
      base = debug_lines |> Enum.map(& &1.index) |> Enum.min(fn -> 1 end)
      by_position = Map.new(items, &{&1.position, &1})

      entries =
        for %{index: index, kind: kind, ref: ref} <- debug_lines,
            line = Map.get(line_table, ref),
            line != nil,
            item = Map.get(by_position, index - base + 1),
            item != nil do
          %{line: line, kind: kind, index: index, frame: item.frame, vars: item.vars}
        end

      {:ok, Enum.sort_by(entries, &{&1.line, &1.index})}
    end
  end

  defp debug_chunk(beam) do
    case :beam_lib.chunks(beam, [~c"DbgB"]) do
      {:ok, {_mod, [{~c"DbgB", chunk}]}} -> {:ok, chunk}
      {:error, :beam_lib, {:missing_chunk, _, _}} -> {:error, :missing_debug_chunk}
      {:error, :beam_lib, reason} -> {:error, reason}
    end
  end

  defp parse_chunk(<<0::32, items::32, _vars::32, rest::binary>>, atoms, literals) do
    parse_items(rest, 1, items, atoms, literals, [])
  end

  defp parse_chunk(<<version::32, _::binary>>, _atoms, _literals) do
    {:error, {:unsupported_debug_version, version}}
  end

  defp parse_chunk(_other, _atoms, _literals), do: {:error, :malformed_debug_chunk}

  defp parse_items(_rest, _index, 0, _atoms, _literals, acc), do: {:ok, Enum.reverse(acc)}

  defp parse_items(<<@call_opcode, rest::binary>>, index, n, atoms, literals, acc) do
    {frame_term, rest} = CTF.decode(rest)
    {{:list, ops}, rest} = CTF.decode(rest)

    item = %{
      position: index,
      frame: frame(frame_term, atoms),
      vars: vars(ops, atoms, literals)
    }

    parse_items(rest, index + 1, n - 1, atoms, literals, [item | acc])
  rescue
    e -> {:error, {:malformed_debug_item, index, e}}
  end

  defp parse_items(_other, index, _n, _atoms, _literals, _acc) do
    {:error, {:malformed_debug_item, index, :bad_opcode}}
  end

  # FrameSize: nil (atom index 0) = no frame yet; the atom `entry` marks
  # the function-entry item; a raw unsigned is the frame size.
  defp frame({:atom, 0}, _atoms), do: :none
  defp frame({:literal, size}, _atoms), do: size

  defp frame({:atom, index}, atoms) do
    case atom_at(atoms, index) do
      :entry -> :entry
      other -> raise ArgumentError, "unexpected frame atom #{inspect(other)}"
    end
  end

  defp vars(ops, atoms, literals) do
    ops
    |> Enum.chunk_every(2)
    |> Enum.map(fn [name_term, where_term] ->
      {var_name(name_term, literals), where(where_term, atoms, literals)}
    end)
  end

  # Inside the vars list a `{:literal, _}` is always a literal-table
  # reference (names are binaries there; raw unsigneds never occur —
  # entry items name parameters with tagged integers).
  defp var_name({:literal, index}, literals), do: Map.fetch!(literals, index)
  defp var_name({:integer, position}, _literals), do: position

  defp where({:x, _} = reg, _atoms, _literals), do: reg
  defp where({:y, _} = reg, _atoms, _literals), do: reg
  defp where({:integer, value}, _atoms, _literals), do: {:value, value}
  defp where({:float, value}, _atoms, _literals), do: {:value, value}
  defp where({:atom, 0}, _atoms, _literals), do: {:value, []}
  defp where({:atom, index}, atoms, _literals), do: {:value, atom_at(atoms, index)}
  defp where({:literal, index}, _atoms, literals), do: {:value, Map.fetch!(literals, index)}

  defp atom_at(atoms, index) when index >= 1 and index <= tuple_size(atoms) do
    elem(atoms, index - 1)
  end
end
