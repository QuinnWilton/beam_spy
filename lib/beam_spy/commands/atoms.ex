defmodule BeamSpy.Commands.Atoms do
  @moduledoc """
  Extract and display the atom table from a BEAM file.

  The atom table contains all atoms referenced by the module.
  Similar to `strings` but for atoms.
  """

  alias BeamSpy.{BeamFile, Filter, Format, Theme}

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
    theme = Keyword.get(opts, :theme, Theme.default())

    case extract(path, opts) do
      {:ok, atoms} ->
        format_output(atoms, format, theme)

      {:error, reason} ->
        format_error(reason)
    end
  end

  defp maybe_filter(atoms, nil), do: atoms

  defp maybe_filter(atoms, pattern) when is_binary(pattern) do
    filter = Filter.substring(pattern)
    Filter.filter_list(filter, atoms)
  end

  defp format_output(atoms, :text, theme) do
    atoms
    |> Enum.map(fn atom ->
      str = Atom.to_string(atom)
      element = if special_atom?(atom), do: "atom.special", else: "atom"
      Theme.styled_string(str, element, theme)
    end)
    |> Enum.join("\n")
  end

  defp format_output(atoms, :json, _theme) do
    atoms
    |> Enum.map(&Atom.to_string/1)
    |> Format.json()
  end

  # Atoms that have special meaning in BEAM
  defp special_atom?(atom) when atom in [nil, true, false], do: true
  defp special_atom?(atom) when atom in [:error, :ok, :undefined], do: true

  defp special_atom?(atom) do
    str = Atom.to_string(atom)
    String.starts_with?(str, "Elixir.")
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
