defmodule BeamSpy.Instruction do
  @moduledoc """
  A structured BEAM instruction: the opcode, its category, and typed operands
  (`BeamSpy.Operand`), with the untouched beam_disasm term kept for audit.

  `from_raw/1` is the faithful decomposition — the opcode is whatever
  beam_disasm named the tuple, including the `test`/`bif`/`gc_bif` container
  forms. `normalize/1` then rewrites those containers to the *real* genop
  instruction (`is_eq_exact`, `bif1`, `gc_bif2`, `fadd`, …), which is what
  teaching and ISA-linking consumers want.
  """

  alias BeamSpy.{Opcodes, Operand}

  @enforce_keys [:opcode, :category, :operands, :raw]
  defstruct [:opcode, :category, :operands, :raw]

  @type t :: %__MODULE__{
          opcode: atom(),
          category: atom(),
          operands: [Operand.t()],
          raw: tuple() | atom()
        }

  # beam_disasm decodes the dedicated float-arithmetic opcodes into
  # `{:bif, name, ...}` form; normalize/1 restores the genop names.
  @float_bifs [:fadd, :fsub, :fmul, :fdiv, :fnegate]

  @doc "Build the typed instruction from a raw beam_disasm term."
  @spec from_raw(tuple() | atom()) :: t()
  def from_raw(opcode) when is_atom(opcode), do: build(opcode, [], opcode)
  def from_raw({opcode} = raw) when is_atom(opcode), do: build(opcode, [], raw)

  # Map reads/writes carry flat [k1, v1, k2, v2, ...] pair lists; type them as
  # pairs so consumers (and the renderer) see the map structure.
  def from_raw({:get_map_elements, fail, src, pairs} = raw) do
    build(
      :get_map_elements,
      [Operand.from_raw(fail), Operand.from_raw(src), pairs(:get, pairs)],
      raw
    )
  end

  def from_raw({op, fail, src, dst, live, pairs} = raw)
      when op in [:put_map_assoc, :put_map_exact] do
    operands =
      Enum.map([fail, src, dst, live], &Operand.from_raw/1) ++ [pairs(:put, pairs)]

    build(op, operands, raw)
  end

  def from_raw(raw) when is_tuple(raw) do
    [opcode | args] = Tuple.to_list(raw)
    build(opcode, Enum.map(args, &Operand.from_raw/1), raw)
  end

  @doc """
  Rewrite container forms to the real genop instruction.

  - `{:test, name, ...}` → opcode `name`, the duplicated name operand dropped.
  - `{:bif, name, ...}` → `bif0`/`bif1`/`bif2` by argument count, keeping the
    BIF name as the first operand (it identifies *which* built-in) — except
    the float-arithmetic family, whose genop opcode *is* the name.
  - `{:gc_bif, name, ...}` → `gc_bif1`..`gc_bif3` likewise.

  Everything else passes through unchanged. Idempotent.
  """
  @spec normalize(t()) :: t()
  def normalize(%__MODULE__{opcode: :test, operands: [_name | rest], raw: raw} = instr) do
    name = elem(raw, 1)
    %{instr | opcode: name, category: Opcodes.category(name), operands: rest}
  end

  def normalize(%__MODULE__{opcode: :bif, raw: {:bif, name, _fail, _args, _dst}} = instr)
      when name in @float_bifs do
    %{instr | opcode: name, category: Opcodes.category(name), operands: tl(instr.operands)}
  end

  def normalize(%__MODULE__{opcode: :bif, raw: {:bif, _name, _fail, args, _dst}} = instr) do
    opcode = :"bif#{length(args)}"
    %{instr | opcode: opcode, category: Opcodes.category(opcode)}
  end

  def normalize(
        %__MODULE__{opcode: :gc_bif, raw: {:gc_bif, _n, _fail, _live, args, _dst}} = instr
      ) do
    opcode = :"gc_bif#{length(args)}"
    %{instr | opcode: opcode, category: Opcodes.category(opcode)}
  end

  def normalize(%__MODULE__{} = instr), do: instr

  defp build(opcode, operands, raw) do
    %__MODULE__{opcode: opcode, category: Opcodes.category(opcode), operands: operands, raw: raw}
  end

  defp pairs(kind, {:list, flat}) when is_list(flat), do: pairs(kind, flat)

  defp pairs(kind, flat) when is_list(flat) and rem(length(flat), 2) == 0 do
    typed =
      flat
      |> Enum.chunk_every(2)
      |> Enum.map(fn [key, value] -> {Operand.from_raw(key), Operand.from_raw(value)} end)

    {:map_pairs, kind, typed}
  end

  defp pairs(_kind, other), do: Operand.from_raw(other)
end
