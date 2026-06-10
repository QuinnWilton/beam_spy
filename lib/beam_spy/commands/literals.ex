defmodule BeamSpy.Commands.Literals do
  @moduledoc """
  Extract the literal pool (the `LitT` chunk) from a BEAM file.

  Every constant too large for an immediate operand — maps, tuples, lists,
  binaries, floats — lives in the module's literal pool, and `{:literal, _}`
  operands in the disassembly reference these terms. The chunk is optional:
  the compiler omits it entirely when a module has no pooled literals, so a
  missing chunk means an empty pool, not an error.
  """

  alias BeamSpy.BeamFile

  @typedoc "A literal pool entry: the pool index and the decoded term."
  @type entry :: {non_neg_integer(), term()}

  @doc """
  Extract the literal pool as `{index, term}` pairs, in pool order.

  Returns `{:ok, []}` when the module has no `LitT` chunk (an empty pool).
  """
  @spec extract(String.t(), keyword()) :: {:ok, [entry()]} | {:error, term()}
  def extract(path, _opts \\ []) do
    case BeamFile.read_chunks(path, [:literals]) do
      {:ok, [{:literals, literals}]} -> {:ok, literals}
      {:error, {:missing_chunk, _}} -> {:ok, []}
      {:error, _} = error -> error
    end
  end
end
