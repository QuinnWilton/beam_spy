defmodule BeamSpy.Render do
  @moduledoc """
  Rendering of instruction operands to display strings.

  Two entry families share one set of formatting rules:

  - `raw_args/2` / `raw_arg/1` format raw beam_disasm operand terms — the
    formatter that historically lived in `BeamSpy.Commands.Disasm`, moved
    here verbatim.
  - `args/1` / `operand/1` format the typed model (`BeamSpy.Instruction` /
    `BeamSpy.Operand`) to **character-identical** output. The test suite
    asserts the two paths agree across the fixture corpus, which is the proof
    that the typed model captures everything the strings ever showed.
  """

  alias BeamSpy.{Instruction, Operand}

  # --- typed rendering --------------------------------------------------------

  @doc "Render a typed instruction's operands (one string per operand)."
  @spec args(Instruction.t()) :: [String.t()]
  def args(%Instruction{operands: operands}), do: Enum.map(operands, &operand/1)

  @doc "Render one typed operand exactly as the legacy formatter would."
  @spec operand(Operand.t()) :: String.t()
  def operand({:x, n}), do: "x(#{n})"
  def operand({:y, n}), do: "y(#{n})"
  def operand({:fr, n}), do: "fr(#{n})"
  def operand({:f, n}), do: "f(#{n})"
  def operand({:atom, a}), do: inspect(a)
  def operand({:integer, n}), do: to_string(n)
  def operand({:u, n}), do: to_string(n)
  def operand({:literal, lit}), do: format_literal(lit)
  # Typed register: show the register; the type travels in the model.
  def operand({:tr, reg, _type}), do: operand(reg)
  def operand({:ext_func, m, f, a}), do: "#{inspect(m)}:#{inspect(f)}/#{a}"
  # Legacy formatting had no MFA clause; it fell through to the literal path.
  def operand({:mfa, m, f, a}), do: format_literal({m, f, a})
  def operand({:alloc, props}), do: alloc(props)
  def operand({:string, bin}), do: string(bin)
  def operand({:list, items}), do: items |> Enum.map(&operand/1) |> join_list()
  def operand({:map_pairs, :get, pairs}), do: map_get_pairs(pairs)
  def operand({:map_pairs, :put, pairs}), do: map_put_pairs(pairs)
  def operand(nil), do: "[]"
  def operand({:float, f}), do: "{float, #{format_literal(f)}}"
  def operand({:tagged, tag, value}), do: "{#{tag}, #{operand(value)}}"
  def operand({:raw, other}), do: format_literal(other)

  defp map_get_pairs(pairs) do
    pairs
    |> Enum.map(fn {key, value} -> "#{map_key(key)} => #{operand(value)}" end)
    |> then(fn formatted -> "[#{Enum.join(formatted, ", ")}]" end)
    |> truncate_if_long(80)
  end

  defp map_put_pairs(pairs) do
    pairs
    |> Enum.map(fn {key, value} -> "#{map_key(key)}: #{operand(value)}" end)
    |> then(fn formatted -> "%{#{Enum.join(formatted, ", ")}}" end)
    |> truncate_if_long(80)
  end

  defp map_key({:atom, a}), do: to_string(a)
  defp map_key({:literal, a}) when is_atom(a), do: to_string(a)
  defp map_key(other), do: operand(other)

  # --- raw rendering (moved verbatim from BeamSpy.Commands.Disasm) -----------

  @doc "Format a raw instruction's args, with the per-opcode special cases."
  @spec raw_args(atom(), [term()]) :: [String.t()]
  def raw_args(:get_map_elements, [fail, src, {:list, pairs}]) do
    [raw_arg(fail), raw_arg(src), format_map_get_pairs(pairs)]
  end

  def raw_args(:get_map_elements, [fail, src, pairs]) when is_list(pairs) do
    [raw_arg(fail), raw_arg(src), format_map_get_pairs(pairs)]
  end

  def raw_args(:put_map_assoc, [fail, src, dst, live, {:list, pairs}]) do
    [raw_arg(fail), raw_arg(src), raw_arg(dst), raw_arg(live), format_map_put_pairs(pairs)]
  end

  def raw_args(:put_map_assoc, [fail, src, dst, live, pairs]) when is_list(pairs) do
    [raw_arg(fail), raw_arg(src), raw_arg(dst), raw_arg(live), format_map_put_pairs(pairs)]
  end

  def raw_args(:put_map_exact, [fail, src, dst, live, {:list, pairs}]) do
    [raw_arg(fail), raw_arg(src), raw_arg(dst), raw_arg(live), format_map_put_pairs(pairs)]
  end

  def raw_args(:put_map_exact, [fail, src, dst, live, pairs]) when is_list(pairs) do
    [raw_arg(fail), raw_arg(src), raw_arg(dst), raw_arg(live), format_map_put_pairs(pairs)]
  end

  def raw_args(_opcode, args), do: Enum.map(args, &raw_arg/1)

  defp format_map_get_pairs(pairs) do
    pairs
    |> Enum.chunk_every(2)
    |> Enum.map(fn
      [key, dest] -> "#{format_map_key(key)} => #{raw_arg(dest)}"
      other -> Enum.map_join(other, ", ", &raw_arg/1)
    end)
    |> then(fn formatted -> "[#{Enum.join(formatted, ", ")}]" end)
    |> truncate_if_long(80)
  end

  defp format_map_put_pairs(pairs) do
    pairs
    |> Enum.chunk_every(2)
    |> Enum.map(fn
      [key, val] -> "#{format_map_key(key)}: #{raw_arg(val)}"
      other -> Enum.map_join(other, ", ", &raw_arg/1)
    end)
    |> then(fn formatted -> "%{#{Enum.join(formatted, ", ")}}" end)
    |> truncate_if_long(80)
  end

  defp format_map_key({:atom, a}), do: to_string(a)
  defp format_map_key({:literal, a}) when is_atom(a), do: to_string(a)
  defp format_map_key(other), do: raw_arg(other)

  @doc "Format one raw operand term."
  @spec raw_arg(term()) :: String.t()
  def raw_arg({:x, n}), do: "x(#{n})"
  def raw_arg({:y, n}), do: "y(#{n})"
  def raw_arg({:fr, n}), do: "fr(#{n})"
  def raw_arg({:f, n}), do: "f(#{n})"
  def raw_arg({:atom, a}), do: inspect(a)
  def raw_arg({:integer, n}), do: to_string(n)
  def raw_arg({:literal, lit}), do: format_literal(lit)
  def raw_arg({:tr, reg, _type}), do: raw_arg(reg)
  def raw_arg({:extfunc, m, f, a}), do: "#{inspect(m)}:#{inspect(f)}/#{a}"
  def raw_arg({:alloc, props}) when is_list(props), do: alloc(props)
  def raw_arg({:string, bin}) when is_binary(bin), do: string(bin)
  def raw_arg({:list, items}), do: items |> Enum.map(&raw_arg/1) |> join_list()
  def raw_arg(items) when is_list(items), do: items |> Enum.map(&raw_arg/1) |> join_list()
  def raw_arg(nil), do: "[]"
  def raw_arg(n) when is_integer(n), do: to_string(n)
  def raw_arg(a) when is_atom(a), do: inspect(a)
  def raw_arg(bin) when is_binary(bin), do: format_literal(bin)
  def raw_arg({tag, value}) when is_atom(tag), do: "{#{tag}, #{raw_arg(value)}}"
  def raw_arg(other), do: format_literal(other)

  # --- shared helpers ---------------------------------------------------------

  # Format alloc tuples compactly: {alloc, [{words, 2}, {funs, 1}]} -> alloc(w:2, fn:1)
  defp alloc(props) do
    parts =
      props
      |> Enum.filter(fn {_key, val} -> val != 0 end)
      |> Enum.map(fn
        {:words, n} -> "w:#{n}"
        {:floats, n} -> "fl:#{n}"
        {:funs, n} -> "fn:#{n}"
        {key, val} -> "#{key}:#{val}"
      end)

    case parts do
      [] -> "alloc()"
      _ -> "alloc(#{Enum.join(parts, ", ")})"
    end
  end

  # Format string tuples in bs_create_bin - show actual string content
  defp string(bin) do
    if String.printable?(bin) do
      truncated = if byte_size(bin) > 30, do: String.slice(bin, 0, 27) <> "...", else: bin
      "{string, #{inspect(truncated)}}"
    else
      "{string, <<#{byte_size(bin)} bytes>>}"
    end
  end

  defp join_list(formatted) do
    truncate_if_long("[#{Enum.join(formatted, ", ")}]", 80)
  end

  # Format literals with truncation for readability
  defp format_literal(lit) when is_binary(lit) do
    if byte_size(lit) > 20 do
      preview = binary_part(lit, 0, min(16, byte_size(lit)))
      "<<#{inspect_binary_bytes(preview)}...>> (#{byte_size(lit)} bytes)"
    else
      inspect(lit)
    end
  end

  defp format_literal(lit) when is_list(lit) do
    truncate_if_long(inspect(lit, limit: 8, printable_limit: 50), 80)
  end

  defp format_literal(lit) when is_map(lit) do
    truncate_if_long(inspect(lit, limit: 4, printable_limit: 50), 80)
  end

  defp format_literal(lit) do
    truncate_if_long(inspect(lit, limit: 8, printable_limit: 50), 80)
  end

  defp inspect_binary_bytes(bin) do
    bin
    |> :binary.bin_to_list()
    |> Enum.map_join(", ", &to_string/1)
  end

  defp truncate_if_long(str, max_len) do
    if String.length(str) > max_len do
      String.slice(str, 0, max_len) <> "..."
    else
      str
    end
  end
end
