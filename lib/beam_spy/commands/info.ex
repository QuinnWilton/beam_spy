defmodule BeamSpy.Commands.Info do
  @moduledoc """
  Extract and display module metadata from a BEAM file.
  """

  alias BeamSpy.{BeamFile, Format}

  @doc """
  Extract module info from a BEAM file.

  Returns a map with:
  - `:module` - Module name
  - `:file` - Original source file path
  - `:compile_time` - Compilation timestamp
  - `:md5` - Module MD5 hash
  - `:size_bytes` - File size
  - `:chunk_count` - Number of chunks
  - `:export_count` - Number of exports
  - `:import_count` - Number of imports
  - `:atom_count` - Number of atoms

  """
  @spec extract(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def extract(path, _opts \\ []) do
    with {:ok, module} <- BeamFile.get_module_name(path),
         {:ok, md5} <- BeamFile.get_md5(path),
         {:ok, atoms} <- BeamFile.read_atoms(path),
         {:ok, exports} <- BeamFile.read_exports(path),
         {:ok, imports} <- BeamFile.read_imports(path),
         {:ok, beam_info} <- BeamFile.info(path) do
      compile_info = get_compile_info(path)

      info = %{
        module: module,
        file: compile_info[:source],
        compile_time: format_compile_time(compile_info[:time]),
        otp_version: get_otp_version(compile_info),
        elixir_version: get_elixir_version(path),
        md5: Base.encode16(md5, case: :lower),
        size_bytes: get_file_size(path),
        chunk_count: length(beam_info.chunks),
        export_count: length(exports),
        import_count: length(imports),
        atom_count: length(atoms)
      }

      {:ok, info}
    end
  end

  @doc """
  Run the info command with formatting.

  ## Options

    * `:format` - Output format: `:text` (default), `:json`

  """
  @spec run(String.t(), keyword()) :: String.t()
  def run(path, opts \\ []) do
    format = Keyword.get(opts, :format, :text)

    case extract(path, opts) do
      {:ok, info} ->
        format_output(info, format)

      {:error, reason} ->
        format_error(reason)
    end
  end

  defp get_compile_info(path) do
    case BeamFile.read_compile_info(path) do
      {:ok, info} -> info
      {:error, _} -> []
    end
  end

  defp format_compile_time(nil), do: nil

  defp format_compile_time({{year, month, day}, {hour, min, sec}}) do
    NaiveDateTime.new!(year, month, day, hour, min, sec)
    |> NaiveDateTime.to_iso8601()
    |> Kernel.<>("Z")
  end

  defp format_compile_time(_), do: nil

  defp get_otp_version(compile_info) do
    case Keyword.get(compile_info, :version) do
      nil -> nil
      version when is_list(version) -> List.to_string(version)
      version -> to_string(version)
    end
  end

  defp get_elixir_version(path) do
    case BeamFile.read_attributes(path) do
      {:ok, attrs} ->
        case Keyword.get(attrs, :vsn) do
          # Elixir modules have vsn as a list with a hash
          [_hash] ->
            # Try to get Elixir version from compile options
            case BeamFile.read_compile_info(path) do
              {:ok, info} ->
                case Keyword.get(info, :options) do
                  options when is_list(options) ->
                    # Elixir version might be in compiler options
                    nil

                  _ ->
                    nil
                end

              _ ->
                nil
            end

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp get_file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> size
      _ -> nil
    end
  end

  defp format_output(info, :text) do
    pairs = [
      {"Module", format_module_name(info.module)},
      {"File", info.file || "-"},
      {"Compile time", info.compile_time || "-"},
      {"OTP version", info.otp_version || "-"},
      {"Elixir vsn", info.elixir_version || "-"},
      {"MD5", info.md5},
      {"Size", format_size(info.size_bytes)},
      {"Chunks", info.chunk_count},
      {"Exports", info.export_count},
      {"Imports", info.import_count},
      {"Atoms", info.atom_count}
    ]

    Format.key_value(pairs)
  end

  defp format_output(info, :json) do
    %{
      module: format_module_name(info.module),
      file: info.file,
      compile_time: info.compile_time,
      otp_version: info.otp_version,
      elixir_version: info.elixir_version,
      md5: info.md5,
      size_bytes: info.size_bytes,
      chunk_count: info.chunk_count,
      export_count: info.export_count,
      import_count: info.import_count,
      atom_count: info.atom_count
    }
    |> Format.json()
  end

  defp format_module_name(mod) when is_atom(mod) do
    Atom.to_string(mod)
  end

  defp format_size(nil), do: "-"

  defp format_size(bytes) when is_integer(bytes) do
    Format.format_value(bytes) <> " bytes"
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
