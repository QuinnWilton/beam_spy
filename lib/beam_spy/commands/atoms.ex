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

    * `:filter` - Filter atoms by pattern (supports re:, glob:, or substring)

  """
  @spec extract(String.t(), keyword()) :: {:ok, [atom()]} | {:error, term()}
  def extract(path, opts \\ []) do
    with {:ok, atoms} <- BeamFile.read_atoms(path) do
      atoms = Filter.maybe_apply(atoms, opts[:filter])
      {:ok, atoms}
    end
  end

  @doc """
  Run the atoms command with formatting.

  ## Options

    * `:format` - Output format: `:text` (default), `:json`
    * `:filter` - Filter atoms by pattern

  """
  @spec run(String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def run(path, opts \\ []) do
    format = Keyword.get(opts, :format, :text)
    theme = Keyword.get(opts, :theme, Theme.default())

    case extract(path, opts) do
      {:ok, atoms} ->
        {:ok, format_output(atoms, format, theme)}

      {:error, reason} ->
        {:error, Format.format_beam_error(reason)}
    end
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
end
