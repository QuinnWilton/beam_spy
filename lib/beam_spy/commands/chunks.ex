defmodule BeamSpy.Commands.Chunks do
  @moduledoc """
  List and inspect BEAM file chunks.
  """

  alias BeamSpy.{BeamFile, Format}

  @doc """
  Extract chunk information from a BEAM file.

  Returns a map with:
  - `:chunks` - List of chunk info maps
  - `:total_size` - Total size of all chunks

  """
  @spec extract(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def extract(path, _opts \\ []) do
    with {:ok, info} <- BeamFile.info(path) do
      total_size = Enum.sum(Enum.map(info.chunks, & &1.size))

      {:ok,
       %{
         chunks: info.chunks,
         total_size: total_size
       }}
    end
  end

  @doc """
  Run the chunks command with formatting.

  ## Options

    * `:format` - Output format: `:text` (default), `:json`
    * `:raw` - Chunk ID to dump as hex

  """
  @spec run(String.t(), keyword()) :: String.t()
  def run(path, opts \\ []) do
    case opts[:raw] do
      nil ->
        run_list(path, opts)

      chunk_id ->
        run_raw_dump(path, chunk_id)
    end
  end

  defp run_list(path, opts) do
    format = Keyword.get(opts, :format, :text)

    case extract(path, opts) do
      {:ok, data} ->
        format_output(data, format)

      {:error, reason} ->
        format_error(reason)
    end
  end

  defp run_raw_dump(path, chunk_id) do
    case BeamFile.read_raw_chunk(path, chunk_id) do
      {:ok, data} ->
        header = "Chunk: #{chunk_id} (#{byte_size(data)} bytes)\n"
        header <> Format.hex_dump(data)

      {:error, {:missing_chunk, _}} ->
        "Error: Chunk '#{chunk_id}' not found"

      {:error, reason} ->
        format_error(reason)
    end
  end

  defp format_output(data, :text) do
    rows =
      Enum.map(data.chunks, fn chunk ->
        [chunk.id, chunk.description, format_size(chunk.size)]
      end)

    table = Format.table(rows, ["ID", "Description", "Size"])

    # Add total row
    total_line = "\nTotal: #{format_size(data.total_size)}"

    table <> total_line
  end

  defp format_output(data, :json) do
    %{
      chunks:
        Enum.map(data.chunks, fn chunk ->
          %{
            id: chunk.id,
            description: chunk.description,
            size: chunk.size
          }
        end),
      total_size: data.total_size
    }
    |> Format.json()
  end

  defp format_size(size) when is_integer(size) do
    Format.format_value(size)
  end

  defp format_error(:not_a_beam_file) do
    "Error: Not a valid BEAM file"
  end

  defp format_error({:file_error, reason}) do
    "Error: #{:file.format_error(reason)}"
  end

  defp format_error(reason) do
    "Error: #{inspect(reason)}"
  end
end
