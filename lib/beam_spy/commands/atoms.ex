defmodule BeamSpy.Commands.Atoms do
  @moduledoc """
  Extract and display the atom table from a BEAM file.

  The atom table contains all atoms referenced by the module.
  Similar to `strings` but for atoms.
  """

  alias BeamSpy.{BeamFile, Filter, Format}

  @doc """
  Extract atoms from a BEAM file.

  ## Options

    * `:filter` - Filter atoms by pattern (substring match)

  """
  @spec extract(String.t(), keyword()) :: {:ok, [atom()]} | {:error, term()}
  def extract(path, opts \\ []) do
    with {:ok, atoms} <- BeamFile.read_atoms(path) do
      atoms = maybe_filter(atoms, opts[:filter])
      {:ok, atoms}
    end
  end

  @doc """
  Run the atoms command with formatting.

  ## Options

    * `:format` - Output format: `:text` (default), `:json`
    * `:filter` - Filter atoms by pattern

  """
  @spec run(String.t(), keyword()) :: String.t()
  def run(path, opts \\ []) do
    format = Keyword.get(opts, :format, :text)

    case extract(path, opts) do
      {:ok, atoms} ->
        format_output(atoms, format)

      {:error, reason} ->
        format_error(reason)
    end
  end

  defp maybe_filter(atoms, nil), do: atoms

  defp maybe_filter(atoms, pattern) when is_binary(pattern) do
    filter = Filter.substring(pattern)
    Filter.filter_list(filter, atoms)
  end

  defp format_output(atoms, :text) do
    atoms
    |> Enum.map(&Atom.to_string/1)
    |> Enum.join("\n")
  end

  defp format_output(atoms, :json) do
    atoms
    |> Enum.map(&Atom.to_string/1)
    |> Format.json()
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
