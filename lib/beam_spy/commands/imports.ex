defmodule BeamSpy.Commands.Imports do
  @moduledoc """
  Extract and display imported functions from a BEAM file.
  """

  alias BeamSpy.{BeamFile, Filter, Format, Theme}

  @doc """
  Extract imports from a BEAM file.

  ## Options

    * `:filter` - Filter imports by function name (supports re:, glob:, or substring)

  Returns a list of `{module, name, arity}` tuples.
  """
  @spec extract(String.t(), keyword()) ::
          {:ok, [{atom(), atom(), non_neg_integer()}]} | {:error, term()}
  def extract(path, opts \\ []) do
    with {:ok, imports} <- BeamFile.read_imports(path) do
      imports =
        imports
        |> Enum.sort_by(fn {mod, name, arity} ->
          {Atom.to_string(mod), Atom.to_string(name), arity}
        end)

      imports =
        Filter.maybe_apply_with_key(imports, opts[:filter], fn {_mod, name, _arity} -> name end)

      {:ok, imports}
    end
  end

  @doc """
  Run the imports command with formatting.

  ## Options

    * `:format` - Output format: `:text` (default), `:json`
    * `:group` - Group by module (default: false)
    * `:filter` - Filter imports by name

  """
  @spec run(String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def run(path, opts \\ []) do
    format = Keyword.get(opts, :format, :text)
    group = Keyword.get(opts, :group, false)
    theme = Keyword.get(opts, :theme, Theme.default())

    case extract(path, opts) do
      {:ok, imports} ->
        {:ok, format_output(imports, format, group, theme)}

      {:error, reason} ->
        {:error, Format.format_beam_error(reason)}
    end
  end

  defp format_output(imports, :text, true, theme) do
    imports
    |> Enum.group_by(fn {mod, _, _} -> mod end)
    |> Enum.sort_by(fn {mod, _} -> Atom.to_string(mod) end)
    |> Enum.map(fn {mod, funs} ->
      header = Theme.styled_string(Format.format_module_name(mod), "module", theme)

      funcs =
        funs
        |> Enum.map(fn {_, name, arity} ->
          styled_name = Theme.styled_string(Atom.to_string(name), "function", theme)
          styled_arity = Theme.styled_string(Integer.to_string(arity), "arity", theme)
          "  #{styled_name}/#{styled_arity}"
        end)
        |> Enum.join("\n")

      "#{header}\n#{funcs}"
    end)
    |> Enum.join("\n\n")
  end

  defp format_output(imports, :text, false, theme) do
    rows =
      Enum.map(imports, fn {mod, name, arity} ->
        styled_mod = Theme.styled_string(Format.format_module_name(mod), "module", theme)
        styled_name = Theme.styled_string(Atom.to_string(name), "function", theme)
        styled_arity = Theme.styled_string(Integer.to_string(arity), "arity", theme)
        [styled_mod, styled_name, styled_arity]
      end)

    header_mod = Theme.styled_string("Module", "ui.header", theme)
    header_func = Theme.styled_string("Function", "ui.header", theme)
    header_arity = Theme.styled_string("Arity", "ui.header", theme)
    Format.table(rows, [header_mod, header_func, header_arity])
  end

  defp format_output(imports, :json, _group, _theme) do
    imports
    |> Enum.map(fn {mod, name, arity} ->
      %{
        module: Format.format_module_name(mod),
        name: Atom.to_string(name),
        arity: arity
      }
    end)
    |> Format.json()
  end
end
