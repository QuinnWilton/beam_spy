defmodule BeamSpy.Commands.Exports do
  @moduledoc """
  Extract and display exported functions from a BEAM file.
  """

  alias BeamSpy.{BeamFile, Filter, Format, Theme}

  @doc """
  Extract exports from a BEAM file.

  ## Options

    * `:filter` - Filter exports by function name

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

      exports = maybe_filter(exports, opts[:filter])
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
  @spec run(String.t(), keyword()) :: String.t()
  def run(path, opts \\ []) do
    format = Keyword.get(opts, :format, :text)
    plain = Keyword.get(opts, :plain, false)
    theme = Keyword.get(opts, :theme, Theme.default())

    case extract(path, opts) do
      {:ok, exports} ->
        format_output(exports, format, plain, theme)

      {:error, reason} ->
        format_error(reason)
    end
  end

  defp maybe_filter(exports, nil), do: exports

  defp maybe_filter(exports, pattern) when is_binary(pattern) do
    filter = Filter.substring(pattern)

    Enum.filter(exports, fn {name, _arity} ->
      Filter.matches?(filter, name)
    end)
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
