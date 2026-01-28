defmodule BeamSpy.Commands.Imports do
  @moduledoc """
  Extract and display imported functions from a BEAM file.
  """

  alias BeamSpy.{BeamFile, Filter, Format}

  @doc """
  Extract imports from a BEAM file.

  ## Options

    * `:filter` - Filter imports by function name

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

      imports = maybe_filter(imports, opts[:filter])
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
  @spec run(String.t(), keyword()) :: String.t()
  def run(path, opts \\ []) do
    format = Keyword.get(opts, :format, :text)
    group = Keyword.get(opts, :group, false)

    case extract(path, opts) do
      {:ok, imports} ->
        format_output(imports, format, group)

      {:error, reason} ->
        format_error(reason)
    end
  end

  defp maybe_filter(imports, nil), do: imports

  defp maybe_filter(imports, pattern) when is_binary(pattern) do
    filter = Filter.substring(pattern)

    Enum.filter(imports, fn {_mod, name, _arity} ->
      Filter.matches?(filter, name)
    end)
  end

  defp format_output(imports, :text, true) do
    imports
    |> Enum.group_by(fn {mod, _, _} -> mod end)
    |> Enum.sort_by(fn {mod, _} -> Atom.to_string(mod) end)
    |> Enum.map(fn {mod, funs} ->
      header = format_module_name(mod)

      funcs =
        funs
        |> Enum.map(fn {_, name, arity} -> "  #{name}/#{arity}" end)
        |> Enum.join("\n")

      "#{header}\n#{funcs}"
    end)
    |> Enum.join("\n\n")
  end

  defp format_output(imports, :text, false) do
    rows =
      Enum.map(imports, fn {mod, name, arity} ->
        [format_module_name(mod), Atom.to_string(name), Integer.to_string(arity)]
      end)

    Format.table(rows, ["Module", "Function", "Arity"])
  end

  defp format_output(imports, :json, _group) do
    imports
    |> Enum.map(fn {mod, name, arity} ->
      %{
        module: format_module_name(mod),
        name: Atom.to_string(name),
        arity: arity
      }
    end)
    |> Format.json()
  end

  defp format_module_name(mod) when is_atom(mod) do
    mod_str = Atom.to_string(mod)

    # Remove Elixir. prefix for display
    case mod_str do
      "Elixir." <> rest -> rest
      other -> other
    end
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
