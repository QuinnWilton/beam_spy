defmodule BeamSpy.BeamType do
  @moduledoc """
  Reader for the `Type` chunk (OTP 25+): the shared operand type table that
  type-annotated registers (`{:tr, reg, type}` operands) index into.

  The chunk layout is `<<Version:32, Count:32, Table/binary>>`. Older table
  versions are upgraded via `:beam_types.convert_ext`, which returns
  `:none` for versions this OTP release cannot read — that is the version
  gate, surfaced as `{:error, {:unsupported_version, v}}` rather than a
  guess. Entries decode with `:beam_types.decode_ext` and render through
  the compiler's own pretty-printer (`:beam_ssa_pp.format_type`), so the
  strings shown are exactly the compiler's vocabulary.
  """

  defmodule Table do
    @moduledoc "A decoded Type chunk: the on-disk version and its entries."

    @enforce_keys [:version, :count, :entries]
    defstruct [:version, :count, :entries]

    @type t :: %__MODULE__{
            version: pos_integer(),
            count: non_neg_integer(),
            entries: [term()]
          }
  end

  alias BeamSpy.BeamFile

  @chunk_id ~c"Type"

  @doc """
  Read and decode a module's Type table from a beam path (any extension)
  or raw beam data — see `t:BeamSpy.BeamFile.beam/0`.

  Returns `{:error, :no_type_chunk}` for modules compiled before OTP 25 or
  with `strip_types`, and `{:error, {:unsupported_version, v}}` for table
  versions newer than this OTP release understands.
  """
  @spec read_table(BeamFile.beam()) :: {:ok, Table.t()} | {:error, term()}
  def read_table(input) do
    with {:ok, beam} <- BeamFile.load(input) do
      case :beam_lib.chunks(beam, [@chunk_id]) do
        {:ok, {_module, [{@chunk_id, <<version::32, count::32, table::binary>>}]}} ->
          decode_table(version, count, table)

        {:ok, {_module, [{@chunk_id, _malformed}]}} ->
          {:error, :malformed_type_chunk}

        {:error, :beam_lib, {:missing_chunk, _, _}} ->
          {:error, :no_type_chunk}

        {:error, :beam_lib, reason} ->
          {:error, reason}
      end
    end
  end

  @doc "Render a decoded type with the compiler's own pretty-printer."
  @spec render(term()) :: String.t()
  def render(type) do
    type |> :beam_ssa_pp.format_type() |> IO.iodata_to_binary()
  end

  defp decode_table(version, count, table) do
    case :beam_types.convert_ext(version, table) do
      :none ->
        {:error, {:unsupported_version, version}}

      converted when is_binary(converted) ->
        entries = decode_entries(converted, [])

        if length(entries) == count do
          {:ok, %Table{version: version, count: count, entries: entries}}
        else
          {:error, {:count_mismatch, count, length(entries)}}
        end
    end
  end

  defp decode_entries(binary, acc) do
    case :beam_types.decode_ext(binary) do
      :done -> Enum.reverse(acc)
      {type, rest} -> decode_entries(rest, [type | acc])
    end
  end
end
