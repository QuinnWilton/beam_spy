defmodule BeamSpy.Format do
  @moduledoc """
  Shared formatting utilities for command output.

  Provides functions for JSON encoding, table rendering, key-value formatting,
  and styled text output.
  """

  alias BeamSpy.Terminal

  @doc """
  Encodes data as JSON.

  ## Options

    * `:pretty` - Pretty-print with indentation (default: true)

  """
  @spec json(term(), keyword()) :: String.t()
  def json(data, opts \\ []) do
    pretty = Keyword.get(opts, :pretty, true)

    if pretty do
      Jason.encode!(data, pretty: true)
    else
      Jason.encode!(data)
    end
  end

  @doc """
  Renders a table with headers.

  ## Options

    * `:plain` - Force plain text output without borders (default: false)
    * `:style` - TableRex style to use (default: auto-detected)

  In interactive mode, renders with box-drawing borders.
  When piped or with `:plain` option, renders as plain text.
  """
  @spec table([[String.t()]], [String.t()], keyword()) :: String.t()
  def table(rows, headers, opts \\ []) do
    plain = Keyword.get(opts, :plain, false)
    use_borders = not plain and Terminal.interactive?()

    if use_borders do
      render_bordered_table(rows, headers, opts)
    else
      render_plain_table(rows, headers)
    end
  end

  defp render_bordered_table(rows, headers, _opts) do
    TableRex.quick_render!(rows, headers)
  end

  defp render_plain_table(rows, _headers) do
    rows
    |> Enum.map(fn row -> Enum.join(row, "\t") end)
    |> Enum.join("\n")
  end

  @doc """
  Renders key-value pairs with aligned keys.

  ## Options

    * `:separator` - Separator between key and value (default: " : ")

  """
  @spec key_value([{String.t(), term()}], keyword()) :: String.t()
  def key_value(pairs, opts \\ []) do
    separator = Keyword.get(opts, :separator, " : ")

    max_key_len =
      pairs
      |> Enum.map(fn {k, _} -> String.length(to_string(k)) end)
      |> Enum.max(fn -> 0 end)

    pairs
    |> Enum.map(fn {key, value} ->
      padded_key = String.pad_trailing(to_string(key), max_key_len)
      "#{padded_key}#{separator}#{format_value(value)}"
    end)
    |> Enum.join("\n")
  end

  @doc """
  Formats a value for display.

  Handles common types appropriately:
  - Numbers with thousand separators
  - Atoms with leading colon
  - Lists joined with commas
  - Other values via inspect
  """
  @spec format_value(term()) :: String.t()
  def format_value(nil), do: "-"
  def format_value(value) when is_binary(value), do: value

  def format_value(value) when is_integer(value) do
    value
    |> Integer.to_string()
    |> add_thousand_separators()
  end

  def format_value(value) when is_atom(value), do: inspect(value)
  def format_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def format_value(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)

  def format_value(values) when is_list(values) do
    values
    |> Enum.map(&format_value/1)
    |> Enum.join(", ")
  end

  def format_value(value), do: inspect(value)

  defp add_thousand_separators(num_str) do
    num_str
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  @doc """
  Applies ANSI styling to text.

  If colors are disabled, returns the text unchanged.

  ## Style specification

  Can be:
  - An atom (ANSI color name): `:red`, `:green`, `:cyan`
  - A map with `:fg`, `:bg`, and/or `:style` keys

  """
  @spec styled(String.t(), atom() | map(), boolean()) :: IO.chardata()
  def styled(text, _style, false), do: text

  def styled(text, style, true) when is_atom(style) do
    [apply(IO.ANSI, style, []), text, IO.ANSI.reset()]
  end

  def styled(text, %{} = style, true) do
    codes =
      []
      |> maybe_add_style(style[:style])
      |> maybe_add_fg(style[:fg])
      |> maybe_add_bg(style[:bg])

    [codes, text, IO.ANSI.reset()]
  end

  defp maybe_add_style(codes, nil), do: codes

  defp maybe_add_style(codes, styles) when is_list(styles) do
    Enum.reduce(styles, codes, fn style, acc ->
      [ansi_style(style) | acc]
    end)
  end

  defp maybe_add_style(codes, style) when is_atom(style) do
    [ansi_style(style) | codes]
  end

  # Map style names to IO.ANSI functions.
  # IO.ANSI uses "bright" instead of "bold".
  defp ansi_style(:bold), do: IO.ANSI.bright()
  defp ansi_style(:dim), do: IO.ANSI.faint()
  defp ansi_style(:italic), do: IO.ANSI.italic()
  defp ansi_style(:underline), do: IO.ANSI.underline()
  defp ansi_style(:blink), do: IO.ANSI.blink_slow()
  defp ansi_style(:reverse), do: IO.ANSI.reverse()
  defp ansi_style(:hidden), do: IO.ANSI.conceal()
  defp ansi_style(:strikethrough), do: IO.ANSI.crossed_out()
  defp ansi_style(other), do: apply(IO.ANSI, other, [])

  defp maybe_add_fg(codes, nil), do: codes
  defp maybe_add_fg(codes, color) when is_atom(color), do: [apply(IO.ANSI, color, []) | codes]

  defp maybe_add_fg(codes, "#" <> hex) do
    {r, g, b} = hex_to_rgb(hex)
    [IO.ANSI.color(r, g, b) | codes]
  end

  defp maybe_add_bg(codes, nil), do: codes

  defp maybe_add_bg(codes, color) when is_atom(color) do
    bg_color = String.to_atom("#{color}_background")
    [apply(IO.ANSI, bg_color, []) | codes]
  end

  defp hex_to_rgb(hex) do
    hex = String.trim_leading(hex, "#")

    case hex do
      <<r::binary-size(2), g::binary-size(2), b::binary-size(2)>> ->
        {String.to_integer(r, 16), String.to_integer(g, 16), String.to_integer(b, 16)}

      _ ->
        {255, 255, 255}
    end
  end

  @doc """
  Renders a horizontal separator line.
  """
  @spec separator(pos_integer()) :: String.t()
  def separator(width \\ 60) do
    String.duplicate("─", width)
  end

  @doc """
  Renders a hex dump of binary data.

  Output format is similar to `hexdump -C`:
  - Offset in hex
  - 16 bytes of data in hex
  - ASCII representation

  """
  @spec hex_dump(binary(), keyword()) :: String.t()
  def hex_dump(data, opts \\ []) do
    bytes_per_line = Keyword.get(opts, :bytes_per_line, 16)

    data
    |> :binary.bin_to_list()
    |> Enum.chunk_every(bytes_per_line)
    |> Enum.with_index()
    |> Enum.map(fn {bytes, index} ->
      offset = index * bytes_per_line
      hex_part = format_hex_bytes(bytes, bytes_per_line)
      ascii_part = format_ascii_bytes(bytes)

      :io_lib.format("~8.16.0B: ~s |~s|", [offset, hex_part, ascii_part])
      |> IO.iodata_to_binary()
    end)
    |> Enum.join("\n")
  end

  defp format_hex_bytes(bytes, bytes_per_line) do
    hex =
      bytes
      |> Enum.map(fn b -> :io_lib.format("~2.16.0B", [b]) end)
      |> Enum.join(" ")

    # Pad to full width
    padding_bytes = bytes_per_line - length(bytes)
    padding = String.duplicate("   ", padding_bytes)
    hex <> padding
  end

  defp format_ascii_bytes(bytes) do
    bytes
    |> Enum.map(fn
      b when b >= 32 and b < 127 -> <<b>>
      _ -> "."
    end)
    |> Enum.join()
  end
end
