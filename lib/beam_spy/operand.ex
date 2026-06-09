defmodule BeamSpy.Operand do
  @moduledoc """
  Typed instruction operands.

  `:beam_disasm` emits operands as a zoo of tagged tuples and bare terms;
  this module normalizes them into one closed union so consumers can pattern
  match on operand *meaning* (register, label, literal, external function,
  typed register, …) instead of re-parsing rendered strings.

  `from_raw/1` is total: every raw operand maps to some typed operand, with
  `{:raw, term}` as the loud last resort for shapes this module has never
  seen (a future-OTP tripwire — the test suite asserts no `{:raw, _}` occurs
  across the fixture corpus). `BeamSpy.Render.operand/1` renders any typed
  operand back to exactly the string the legacy formatter produced.
  """

  @type t ::
          {:x, non_neg_integer()}
          | {:y, non_neg_integer()}
          | {:fr, non_neg_integer()}
          | {:f, non_neg_integer()}
          | {:atom, atom()}
          | {:integer, integer()}
          | {:float, float()}
          | {:literal, term()}
          | {:string, binary()}
          | {:ext_func, module(), atom(), arity()}
          | {:mfa, module(), atom(), arity()}
          | {:tr, t(), term()}
          | {:alloc, keyword()}
          | {:list, [t()]}
          | {:map_pairs, :get | :put, [{t(), t()}]}
          | nil
          | {:u, non_neg_integer()}
          | {:tagged, atom(), t()}
          | {:raw, term()}

  @doc """
  Normalize one raw beam_disasm operand.

  The clause order mirrors the legacy formatter's, so the typed model makes
  exactly the distinctions the rendering always made (e.g. a bare `nil` is
  the empty list, while `{:atom, nil}` is the atom).
  """
  @spec from_raw(term()) :: t()
  def from_raw({:x, n}) when is_integer(n), do: {:x, n}
  def from_raw({:y, n}) when is_integer(n), do: {:y, n}
  def from_raw({:fr, n}) when is_integer(n), do: {:fr, n}
  def from_raw({:f, n}) when is_integer(n), do: {:f, n}
  def from_raw({:atom, a}) when is_atom(a), do: {:atom, a}
  def from_raw({:integer, n}) when is_integer(n), do: {:integer, n}
  def from_raw({:float, f}) when is_float(f), do: {:float, f}
  def from_raw({:literal, lit}), do: {:literal, lit}
  def from_raw({:tr, reg, type}), do: {:tr, from_raw(reg), type}
  def from_raw({:extfunc, m, f, a}), do: {:ext_func, m, f, a}

  # Local call targets resolved by beam_disasm to a same-module MFA.
  def from_raw({m, f, a}) when is_atom(m) and is_atom(f) and is_integer(a) and a >= 0,
    do: {:mfa, m, f, a}

  def from_raw({:alloc, props}) when is_list(props), do: {:alloc, props}
  def from_raw({:string, bin}) when is_binary(bin), do: {:string, bin}
  def from_raw({:list, items}) when is_list(items), do: {:list, Enum.map(items, &from_raw/1)}
  def from_raw(items) when is_list(items), do: {:list, Enum.map(items, &from_raw/1)}
  def from_raw(nil), do: nil
  def from_raw(n) when is_integer(n) and n >= 0, do: {:u, n}
  def from_raw(n) when is_integer(n), do: {:integer, n}
  def from_raw(a) when is_atom(a), do: {:atom, a}
  def from_raw(bin) when is_binary(bin), do: {:literal, bin}

  # Well-formed register/label tuples matched above; anything else tagged
  # falls through here, exactly as the legacy formatter's generic clause did.
  def from_raw({tag, value}) when is_atom(tag), do: {:tagged, tag, from_raw(value)}

  def from_raw(other), do: {:raw, other}
end
