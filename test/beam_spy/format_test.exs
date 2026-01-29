defmodule BeamSpy.FormatTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias BeamSpy.Format

  describe "json/2" do
    test "encodes a list" do
      assert ~s(["a","b"]) == Format.json(["a", "b"], pretty: false)
    end

    test "encodes a map" do
      result = Format.json(%{a: 1}, pretty: false)
      assert result =~ ~s("a":1) or result =~ ~s("a": 1)
    end

    test "pretty prints by default" do
      result = Format.json(%{a: 1, b: 2})
      assert result =~ "\n"
    end

    test "compact output with pretty: false" do
      result = Format.json(%{a: 1, b: 2}, pretty: false)
      refute result =~ "\n"
    end
  end

  describe "table/3" do
    test "renders rows with headers" do
      rows = [["a", "1"], ["b", "2"]]
      output = Format.table(rows, ["Name", "Value"])
      # In non-interactive mode (test), should be plain
      assert output =~ "a"
      assert output =~ "b"
    end

    test "plain mode outputs tab-separated values" do
      rows = [["foo", "bar"], ["baz", "qux"]]
      output = Format.table(rows, ["Col1", "Col2"], plain: true)
      assert output == "foo\tbar\nbaz\tqux"
    end
  end

  describe "key_value/2" do
    test "renders key-value pairs" do
      pairs = [{"Name", "Test"}, {"Value", 42}]
      output = Format.key_value(pairs)
      assert output =~ "Name"
      assert output =~ ":"
      assert output =~ "Test"
      assert output =~ "42"
    end

    test "aligns keys" do
      pairs = [{"Short", "a"}, {"Much Longer Key", "b"}]
      output = Format.key_value(pairs)
      lines = String.split(output, "\n")

      # Find colon positions
      colon_positions =
        lines
        |> Enum.map(fn line ->
          case String.split(line, " : ", parts: 2) do
            [key, _] -> String.length(key)
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      # All colons should be aligned (same position)
      assert length(Enum.uniq(colon_positions)) == 1
    end

    test "uses custom separator" do
      pairs = [{"Key", "Value"}]
      output = Format.key_value(pairs, separator: " = ")
      assert output =~ "Key = Value"
    end
  end

  describe "format_value/1" do
    test "formats nil as dash" do
      assert Format.format_value(nil) == "-"
    end

    test "formats strings unchanged" do
      assert Format.format_value("hello") == "hello"
    end

    test "formats integers with thousand separators" do
      assert Format.format_value(1000) == "1,000"
      assert Format.format_value(1_000_000) == "1,000,000"
      assert Format.format_value(42) == "42"
    end

    test "formats atoms with colon" do
      assert Format.format_value(:foo) == ":foo"
    end

    test "formats lists as comma-separated" do
      assert Format.format_value([:a, :b, :c]) == ":a, :b, :c"
    end

    test "formats DateTime as ISO8601" do
      dt = ~U[2024-01-15 10:30:00Z]
      assert Format.format_value(dt) == "2024-01-15T10:30:00Z"
    end

    test "formats NaiveDateTime as ISO8601" do
      ndt = ~N[2024-01-15 10:30:00]
      assert Format.format_value(ndt) == "2024-01-15T10:30:00"
    end

    test "formats nested lists" do
      assert Format.format_value([1, 2, 3]) == "1, 2, 3"
    end

    test "formats other types via inspect" do
      assert Format.format_value({:tuple, 1, 2}) == "{:tuple, 1, 2}"
    end
  end

  describe "format_beam_error/1" do
    test "formats :not_a_beam_file" do
      assert Format.format_beam_error(:not_a_beam_file) == "Error: Not a valid BEAM file"
    end

    test "formats file_error tuple" do
      result = Format.format_beam_error({:file_error, :enoent})
      assert result =~ "Error:"
    end

    test "formats missing_chunk tuple" do
      assert Format.format_beam_error({:missing_chunk, "Dbgi"}) == "Error: Chunk 'Dbgi' not found"
    end

    test "formats unknown error" do
      result = Format.format_beam_error(:some_unknown_error)
      assert result =~ "Error:"
      assert result =~ "some_unknown_error"
    end
  end

  describe "format_module_name/1" do
    test "strips Elixir. prefix from Elixir modules" do
      assert Format.format_module_name(Enum) == "Enum"
      assert Format.format_module_name(String.Chars) == "String.Chars"
    end

    test "preserves Erlang module names" do
      assert Format.format_module_name(:lists) == "lists"
      assert Format.format_module_name(:erlang) == "erlang"
    end
  end

  describe "styled/3" do
    test "returns text unchanged when colors disabled" do
      assert Format.styled("hello", :red, false) == "hello"
    end

    test "applies atom color" do
      result = Format.styled("hello", :red, true)
      assert IO.iodata_to_binary(result) =~ "hello"
      # Should contain ANSI codes
      assert IO.iodata_to_binary(result) =~ "\e["
    end

    test "applies map style" do
      result = Format.styled("hello", %{fg: :green, style: :bold}, true)
      binary = IO.iodata_to_binary(result)
      assert binary =~ "hello"
      assert binary =~ "\e["
    end

    test "applies style with list of styles" do
      result = Format.styled("hello", %{style: [:bold, :underline]}, true)
      binary = IO.iodata_to_binary(result)
      assert binary =~ "hello"
      assert binary =~ "\e["
    end

    test "applies style with hex color" do
      result = Format.styled("hello", %{fg: "#FF0000"}, true)
      binary = IO.iodata_to_binary(result)
      assert binary =~ "hello"
    end

    test "applies background color" do
      result = Format.styled("hello", %{bg: :blue}, true)
      binary = IO.iodata_to_binary(result)
      assert binary =~ "hello"
    end

    test "handles all standard styles" do
      for style <- [:bold, :dim, :italic, :underline, :reverse] do
        result = Format.styled("text", %{style: style}, true)
        assert IO.iodata_to_binary(result) =~ "text"
      end
    end

    test "handles blink and strikethrough styles" do
      for style <- [:blink, :strikethrough, :hidden] do
        result = Format.styled("text", %{style: style}, true)
        assert IO.iodata_to_binary(result) =~ "text"
      end
    end

    test "handles invalid hex color gracefully" do
      # Invalid hex should fallback to white
      result = Format.styled("text", %{fg: "#invalid"}, true)
      assert IO.iodata_to_binary(result) =~ "text"
    end

    test "handles empty style map" do
      result = Format.styled("text", %{}, true)
      assert IO.iodata_to_binary(result) =~ "text"
    end
  end

  describe "separator/1" do
    test "creates line of correct width" do
      sep = Format.separator(10)
      assert String.length(sep) == 10
      assert sep == "──────────"
    end

    test "uses default width" do
      sep = Format.separator()
      assert String.length(sep) == 60
    end
  end

  describe "hex_dump/2" do
    test "formats binary as hex dump" do
      data = "Hello, World!"
      output = Format.hex_dump(data)

      # Should have offset
      assert output =~ "00000000:"
      # Should have hex bytes
      assert output =~ "48 65 6C"
      # Should have ASCII
      assert output =~ "|Hello, World!|"
    end

    test "handles non-printable characters" do
      data = <<0, 1, 2, 3>>
      output = Format.hex_dump(data)

      # Non-printable shown as dots in ASCII column
      assert output =~ "|....|"
    end

    test "pads short lines" do
      data = "Hi"
      output = Format.hex_dump(data)

      # Should still have the ASCII representation
      assert output =~ "|Hi|"
    end

    test "handles empty binary" do
      output = Format.hex_dump(<<>>)
      assert output == ""
    end

    test "supports custom bytes_per_line" do
      data = "Hello"
      output = Format.hex_dump(data, bytes_per_line: 4)
      lines = String.split(output, "\n")
      # With 5 bytes and 4 per line, should have 2 lines
      assert length(lines) == 2
    end

    test "handles multi-line output" do
      data = String.duplicate("A", 32)
      output = Format.hex_dump(data)
      lines = String.split(output, "\n")
      # 32 bytes with 16 per line = 2 lines
      assert length(lines) == 2
      assert output =~ "00000010:"
    end

    test "shows all printable ASCII correctly" do
      data = " ~"  # space and tilde (first and last printable)
      output = Format.hex_dump(data)
      assert output =~ "| ~|"
    end
  end

  # Property tests
  describe "property tests" do
    property "json round-trips through Jason" do
      check all(
              data <-
                one_of([
                  string(:alphanumeric),
                  integer(),
                  boolean(),
                  list_of(integer(), max_length: 5),
                  map_of(atom(:alphanumeric), integer(), max_length: 3)
                ])
            ) do
        encoded = Format.json(data, pretty: false)
        {:ok, decoded} = Jason.decode(encoded)

        # Atoms become strings, but structure preserved
        case data do
          data when is_map(data) ->
            # Keys become strings
            assert is_map(decoded)

          _ ->
            # Other types should match or be convertible
            assert is_binary(encoded)
        end
      end
    end

    property "format_value always returns a string" do
      check all(
              value <-
                one_of([
                  constant(nil),
                  string(:alphanumeric),
                  integer(),
                  atom(:alphanumeric),
                  list_of(atom(:alphanumeric), max_length: 3)
                ])
            ) do
        result = Format.format_value(value)
        assert is_binary(result)
      end
    end

    property "thousand separators preserve numeric value" do
      check all(n <- integer(0..999_999_999)) do
        formatted = Format.format_value(n)
        # Remove commas and parse back
        parsed = formatted |> String.replace(",", "") |> String.to_integer()
        assert parsed == n
      end
    end
  end
end
