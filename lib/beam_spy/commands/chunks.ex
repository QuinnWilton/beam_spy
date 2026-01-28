defmodule BeamSpy.Commands.Chunks do
  @moduledoc """
  List and inspect BEAM file chunks.
  """

  alias BeamSpy.{BeamFile, Format, Theme}

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
        run_raw_dump(path, chunk_id, opts)
    end
  end

  defp run_list(path, opts) do
    format = Keyword.get(opts, :format, :text)
    theme = Keyword.get(opts, :theme, Theme.default())

    case extract(path, opts) do
      {:ok, data} ->
        format_output(data, format, theme)

      {:error, reason} ->
        format_error(reason)
    end
  end

  defp run_raw_dump(path, chunk_id, opts) do
    theme = Keyword.get(opts, :theme, Theme.default())

    case BeamFile.read_raw_chunk(path, chunk_id) do
      {:ok, data} ->
        styled_id = Theme.styled_string(chunk_id, "chunk_id", theme)
        styled_size = Theme.styled_string("#{byte_size(data)}", "number", theme)
        header = "Chunk: #{styled_id} (#{styled_size} bytes)\n"
        header <> Format.hex_dump(data)

      {:error, {:missing_chunk, _}} ->
        "Error: Chunk '#{chunk_id}' not found"

      {:error, reason} ->
        format_error(reason)
    end
  end

  defp format_output(data, :text, theme) do
    rows =
      Enum.map(data.chunks, fn chunk ->
        styled_id = Theme.styled_string(chunk.id, "chunk_id", theme)
        styled_size = Theme.styled_string(format_size(chunk.size), "number", theme)
        [styled_id, chunk.description, styled_size]
      end)

    header_id = Theme.styled_string("ID", "ui.header", theme)
    header_desc = Theme.styled_string("Description", "ui.header", theme)
    header_size = Theme.styled_string("Size", "ui.header", theme)
    table = Format.table(rows, [header_id, header_desc, header_size])

    # Add total row
    styled_total = Theme.styled_string(format_size(data.total_size), "number", theme)
    total_line = "\nTotal: #{styled_total}"

    table <> total_line
  end

  defp format_output(data, :json, _theme) do
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
