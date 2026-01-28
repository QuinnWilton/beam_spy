defmodule BeamSpy.Commands.Exports do
  @moduledoc """
  Extract and display exported functions from a BEAM file.
  """

  alias BeamSpy.{BeamFile, Filter, Format, Theme}

  @doc """
  Extract exports from a BEAM file.

  ## Options

    * `:filter` - Filter exports by function name (supports re:, glob:, or substring)

  Returns a list of `{name, arity}` tuples.
  """
  @spec extract(String.t(), keyword()) :: {:ok, [{atom(), non_neg_integer()}]} | {:error, term()}
  def extract(path, opts \\ []) do
    with {:ok, exports} <- BeamFile.read_exports(path) do
      # Normalize to {name, arity} format
      exports =
        exports
        |> Enum.map(fn
          {name, arity, _label} -> {name, arity}
          {name, arity} -> {name, arity}
        end)
        |> Enum.sort_by(fn {name, arity} -> {Atom.to_string(name), arity} end)

      exports = Filter.maybe_apply_with_key(exports, opts[:filter], fn {name, _arity} -> name end)
      {:ok, exports}
    end
  end

  @doc """
  Run the exports command with formatting.

  ## Options

    * `:format` - Output format: `:text` (default), `:json`
    * `:plain` - Use plain text output (one per line)
    * `:filter` - Filter exports by name

  """
  @spec run(String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def run(path, opts \\ []) do
    format = Keyword.get(opts, :format, :text)
    plain = Keyword.get(opts, :plain, false)
    theme = Keyword.get(opts, :theme, Theme.default())

    case extract(path, opts) do
      {:ok, exports} ->
        {:ok, format_output(exports, format, plain, theme)}

      {:error, reason} ->
        {:error, Format.format_beam_error(reason)}
    end
  end

  defp format_output(exports, :text, true, theme) do
    exports
    |> Enum.map(fn {name, arity} ->
      styled_name = Theme.styled_string(Atom.to_string(name), "function", theme)
      styled_arity = Theme.styled_string(Integer.to_string(arity), "arity", theme)
      "#{styled_name}/#{styled_arity}"
    end)
    |> Enum.join("\n")
  end

  defp format_output(exports, :text, false, theme) do
    rows =
      Enum.map(exports, fn {name, arity} ->
        styled_name = Theme.styled_string(Atom.to_string(name), "function", theme)
        styled_arity = Theme.styled_string(Integer.to_string(arity), "arity", theme)
        [styled_name, styled_arity]
      end)

    header_func = Theme.styled_string("Function", "ui.header", theme)
    header_arity = Theme.styled_string("Arity", "ui.header", theme)
    Format.table(rows, [header_func, header_arity])
  end

  defp format_output(exports, :json, _plain, _theme) do
    exports
    |> Enum.map(fn {name, arity} -> %{name: Atom.to_string(name), arity: arity} end)
    |> Format.json()
  end
end
