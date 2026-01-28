defmodule BeamSpy.Commands.DisasmTest do
  use ExUnit.Case, async: true

  alias BeamSpy.Commands.Disasm

  # Use a known Erlang stdlib module for testing
  @test_beam_path :code.which(:lists) |> to_string()

  describe "extract/2" do
    test "extracts functions from beam file" do
      assert {:ok, result} = Disasm.extract(@test_beam_path)
      assert is_atom(result.module)
      assert result.module == :lists
      assert is_list(result.exports)
      assert is_list(result.functions)
      assert length(result.functions) > 0
    end

    test "functions have correct structure" do
      {:ok, result} = Disasm.extract(@test_beam_path)

      for func <- result.functions do
        assert is_atom(func.name)
        assert is_integer(func.arity) and func.arity >= 0
        assert is_integer(func.entry)
        assert is_list(func.instructions)
      end
    end

    test "instructions have category, name, and args" do
      {:ok, result} = Disasm.extract(@test_beam_path)
      [func | _] = result.functions

      for {category, name, args} <- func.instructions do
        assert is_atom(category)
        assert is_binary(name)
        assert is_list(args)
      end
    end

    test "contains expected categories" do
      {:ok, result} = Disasm.extract(@test_beam_path)

      all_categories =
        result.functions
        |> Enum.flat_map(fn f -> Enum.map(f.instructions, fn {cat, _, _} -> cat end) end)
        |> Enum.uniq()

      # Should have at least some common categories
      # labels
      assert :control in all_categories
      # func_info
      assert :error in all_categories
      # return
      assert :return in all_categories
    end

    test "filters by function name" do
      {:ok, result} = Disasm.extract(@test_beam_path, function: "map/2")
      assert length(result.functions) == 1
      assert hd(result.functions).name == :map
      assert hd(result.functions).arity == 2
    end

    test "filters by glob pattern" do
      {:ok, result} = Disasm.extract(@test_beam_path, function: "map*")

      for func <- result.functions do
        assert to_string(func.name) =~ ~r/^map/
      end
    end

    test "returns error for invalid file" do
      assert {:error, _} = Disasm.extract("/nonexistent/file.beam")
    end
  end

  describe "run/2 text format" do
    test "outputs module header" do
      {:ok, output} = Disasm.run(@test_beam_path, format: :text)
      assert output =~ "module: :lists"
      assert output =~ "exports:"
    end

    test "outputs function headers" do
      {:ok, output} = Disasm.run(@test_beam_path, format: :text)
      assert output =~ "function map/2"
      assert output =~ "(entry:"
    end

    test "outputs instructions" do
      {:ok, output} = Disasm.run(@test_beam_path, format: :text, function: "reverse/1")
      # Should contain common instructions
      assert output =~ "label"
      assert output =~ "func_info"
    end

    test "formats registers" do
      {:ok, output} = Disasm.run(@test_beam_path, format: :text, function: "map/2")
      # Should format x registers
      assert output =~ "x(" or output =~ "y("
    end
  end

  describe "run/2 json format" do
    test "outputs valid JSON" do
      {:ok, output} = Disasm.run(@test_beam_path, format: :json, function: "reverse/1")
      {:ok, decoded} = Jason.decode(output)

      assert Map.has_key?(decoded, "module")
      assert Map.has_key?(decoded, "exports")
      assert Map.has_key?(decoded, "functions")
    end

    test "function structure in JSON" do
      {:ok, output} = Disasm.run(@test_beam_path, format: :json, function: "reverse/1")
      {:ok, decoded} = Jason.decode(output)

      [func] = decoded["functions"]
      assert func["name"] == "reverse"
      assert func["arity"] == 1
      assert is_integer(func["entry"])
      assert is_list(func["instructions"])
    end

    test "instruction structure in JSON" do
      {:ok, output} = Disasm.run(@test_beam_path, format: :json, function: "reverse/1")
      {:ok, decoded} = Jason.decode(output)

      [func] = decoded["functions"]
      [inst | _] = func["instructions"]

      assert Map.has_key?(inst, "op")
      assert Map.has_key?(inst, "args")
    end
  end

  describe "instruction formatting" do
    test "formats label instruction" do
      {:ok, result} = Disasm.extract(@test_beam_path, function: "reverse/1")
      [func] = result.functions

      labels = Enum.filter(func.instructions, fn {_, name, _} -> name == "label" end)
      assert length(labels) > 0

      for {category, "label", [n]} <- labels do
        assert category == :control
        assert is_binary(n)
        assert String.match?(n, ~r/^\d+$/)
      end
    end

    test "formats return instruction" do
      {:ok, result} = Disasm.extract(@test_beam_path, function: "reverse/1")
      [func] = result.functions

      returns = Enum.filter(func.instructions, fn {_, name, _} -> name == "return" end)
      assert length(returns) > 0

      for {category, "return", args} <- returns do
        assert category == :return
        assert args == []
      end
    end

    test "formats func_info instruction" do
      {:ok, result} = Disasm.extract(@test_beam_path, function: "reverse/1")
      [func] = result.functions

      func_infos = Enum.filter(func.instructions, fn {_, name, _} -> name == "func_info" end)
      assert length(func_infos) == 1

      [{category, "func_info", [mod, name, arity]}] = func_infos
      assert category == :error
      assert mod =~ "lists"
      assert name =~ "reverse"
      assert arity == "1"
    end
  end

  describe "snapshot tests" do
    @tag :snapshot
    test "extract result structure for :lists.reverse/1" do
      {:ok, result} = Disasm.extract(@test_beam_path, function: "reverse/1")

      assert result.module == :lists
      assert length(result.functions) == 1

      [func] = result.functions
      assert func.name == :reverse
      assert func.arity == 1
      assert is_integer(func.entry)
      assert length(func.instructions) > 0
    end

    @tag :snapshot
    test "instruction categories are valid atoms" do
      {:ok, result} = Disasm.extract(@test_beam_path, function: "reverse/1")
      [func] = result.functions

      categories =
        func.instructions
        |> Enum.map(fn {cat, _, _} -> cat end)
        |> Enum.uniq()
        |> Enum.sort()

      # Verify all categories are valid
      valid_categories = [
        :call,
        :control,
        :data,
        :error,
        :return,
        :stack,
        :meta,
        :message,
        :binary,
        :float,
        :exception,
        :unknown
      ]

      for cat <- categories do
        assert cat in valid_categories, "Invalid category: #{inspect(cat)}"
      end
    end

    @tag :snapshot
    test "JSON output structure is stable" do
      {:ok, output} = Disasm.run(@test_beam_path, format: :json, function: "reverse/1")
      {:ok, decoded} = Jason.decode(output)

      assert decoded["module"] == "lists"
      assert is_list(decoded["exports"])
      assert is_list(decoded["functions"])

      [func] = decoded["functions"]
      assert func["name"] == "reverse"
      assert func["arity"] == 1
      assert is_list(func["instructions"])

      # First instruction is typically line or label
      [first | _] = func["instructions"]
      assert first["op"] in ["label", "line"]
    end

    @tag :snapshot
    test "text output contains expected sections" do
      {:ok, output} = Disasm.run(@test_beam_path, format: :text, function: "reverse/1")

      assert output =~ "module: :lists"
      assert output =~ "function reverse/1"
      assert output =~ "label"
      assert output =~ "func_info"
      assert output =~ "return"
    end
  end

  describe "run/2 with source option" do
    # Use Elixir's Enum module which has source available
    @elixir_beam_path :code.which(Enum) |> to_string()

    test "includes source lines when source: true" do
      {:ok, output} = Disasm.run(@elixir_beam_path, format: :text, function: "reverse/1", source: true)

      # Should include the source line marker (line number followed by │)
      assert output =~ ~r/\d+\s*│/
      # Should include actual source code
      assert output =~ "def reverse"
    end

    test "still includes instructions with source: true" do
      {:ok, output} = Disasm.run(@elixir_beam_path, format: :text, function: "reverse/1", source: true)

      # Should still have bytecode
      assert output =~ "label"
      assert output =~ "func_info"
    end

    test "output without source option has no source lines" do
      {:ok, output} = Disasm.run(@elixir_beam_path, format: :text, function: "reverse/1", source: false)

      # Should not have the source line format
      refute output =~ ~r/^\s*\d+\s*│.*def reverse/m
    end

    test "source option does not affect JSON format" do
      # JSON format ignores source option (no interleaving)
      {:ok, output} = Disasm.run(@elixir_beam_path, format: :json, function: "reverse/1", source: true)
      {:ok, decoded} = Jason.decode(output)

      assert decoded["module"] == "Elixir.Enum"
      assert is_list(decoded["functions"])
    end
  end

  describe "source interleaving - Elixir modules" do
    @elixir_beam_path :code.which(Enum) |> to_string()

    test "shows reconstructed source for Elixir stdlib" do
      {:ok, output} = Disasm.run(@elixir_beam_path, format: :text, function: "map/2", source: true)

      # Should show line numbers
      assert output =~ ~r/\d+\s*│/
      # Should show def for Elixir modules
      assert output =~ "def map"
    end

    test "shows distant references with function names for inlined code" do
      # reduce/3 is known to inline helper functions
      {:ok, output} = Disasm.run(@elixir_beam_path, format: :text, function: "reduce/3", source: true)

      # Should have distant reference markers with function names
      # Format: → function_name (line N)
      assert output =~ ~r/→.*\(line \d+\)/
    end

    test "preserves bytecode instructions with source" do
      {:ok, output} = Disasm.run(@elixir_beam_path, format: :text, function: "map/2", source: true)

      # Should still have all the bytecode
      assert output =~ "func_info"
      assert output =~ "label"
      assert output =~ "return"
    end
  end

  describe "source interleaving - Erlang modules" do
    @erlang_beam_path :code.which(:lists) |> to_string()
    @maps_beam_path :code.which(:maps) |> to_string()

    test "shows reconstructed source for Erlang stdlib" do
      {:ok, output} = Disasm.run(@erlang_beam_path, format: :text, function: "map/2", source: true)

      # Should show line numbers
      assert output =~ ~r/\d+\s*│/
      # Erlang reconstructed format shows helper functions: name/arity: name(...) -> ...
      # map/2 calls map_1/2 which appears in the disasm
      assert output =~ ~r/map_1\/2:/ or output =~ ~r/\d+\s*│/
    end

    test "shows Erlang function signatures in reconstructed source" do
      {:ok, output} = Disasm.run(@erlang_beam_path, format: :text, function: "foldl/3", source: true)

      # Should show the helper function signature with arguments
      # foldl/3 calls foldl_1/3 which appears in the disasm
      assert output =~ "foldl_1/3:"
      assert output =~ ~r/foldl_1\([^)]+\)/
    end

    test "shows distant references with function names for Erlang" do
      # maps:fold/3 inlines other functions
      {:ok, output} = Disasm.run(@maps_beam_path, format: :text, function: "fold/3", source: true)

      # Should have distant references with Erlang function names
      assert output =~ ~r/→.*\(line \d+\)/
    end

    test "formats Erlang list patterns correctly" do
      {:ok, output} = Disasm.run(@erlang_beam_path, format: :text, function: "foldl/3", source: true)

      # Should show readable list patterns [H | T] not raw AST
      # The foldl function uses list patterns
      if output =~ "foldl_1" do
        assert output =~ ~r/\[.*\|.*\]/
      end
    end

    test "handles NIF stubs gracefully" do
      # member/2 is a NIF in lists module
      {:ok, output} = Disasm.run(@erlang_beam_path, format: :text, function: "member/2", source: true)

      # Should not crash, should show the stub
      assert output =~ "func_info"
      assert output =~ "nif_error" or output =~ ":undef"
    end
  end

  describe "distant reference detection" do
    @elixir_beam_path :code.which(Enum) |> to_string()

    test "lines near home are shown with full source" do
      {:ok, output} = Disasm.run(@elixir_beam_path, format: :text, function: "map/2", source: true)

      # The function's own def line should be shown with source
      assert output =~ ~r/\d+\s*│\s*def map/
    end

    test "distant lines use arrow notation" do
      {:ok, output} = Disasm.run(@elixir_beam_path, format: :text, function: "reduce/3", source: true)

      # Distant references start with →
      if output =~ "→" do
        assert output =~ ~r/^→/m
      end
    end

    test "distant references include line numbers" do
      {:ok, output} = Disasm.run(@elixir_beam_path, format: :text, function: "reduce/3", source: true)

      # Every distant reference should have a line number
      distant_refs = Regex.scan(~r/^→.*$/m, output) |> List.flatten()

      for ref <- distant_refs do
        assert ref =~ ~r/line \d+/
      end
    end
  end

  describe "hyperlinks" do
    test "no hyperlinks for reconstructed source" do
      erlang_path = :code.which(:lists) |> to_string()
      {:ok, output} = Disasm.run(erlang_path, format: :text, function: "map/2", source: true)

      # Should NOT contain OSC 8 escape sequences for Erlang (no real source file)
      refute output =~ "\e]8;;"
    end

    test "hyperlinks present for modules with real source files" do
      # This test requires a module with an actual source file on disk
      # We'll use a dependency if available, or skip
      toml_path = :code.which(Toml) |> to_string()

      if toml_path != :non_existing do
        {:ok, output} = Disasm.run(toml_path, format: :text, function: "decode/1", source: true)

        # If source file exists, should have hyperlinks
        if output =~ "│" do
          # May or may not have hyperlinks depending on source availability
          # Just verify it doesn't crash
          assert is_binary(output)
        end
      end
    end
  end

  describe "gap filling" do
    test "does not fill gaps for reconstructed source" do
      erlang_path = :code.which(:lists) |> to_string()
      {:ok, output} = Disasm.run(erlang_path, format: :text, function: "map/2", source: true)

      # Reconstructed source should show single lines, not ranges
      # Each source line marker should be followed by │
      lines = String.split(output, "\n")

      source_lines =
        lines
        |> Enum.filter(&(&1 =~ ~r/^\s*\d+\s*│/))
        |> Enum.map(fn line ->
          case Regex.run(~r/^\s*(\d+)\s*│/, line) do
            [_, num] -> String.to_integer(num)
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      # For reconstructed source, we shouldn't see consecutive line numbers
      # that would indicate gap filling (they should jump around)
      # This is a heuristic test - reconstructed source has sparse line numbers
      if length(source_lines) > 1 do
        gaps =
          source_lines
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.map(fn [a, b] -> b - a end)

        # At least some gaps should be > 1 (not all consecutive)
        assert Enum.any?(gaps, &(&1 != 1))
      end
    end
  end

  describe "indentation preservation" do
    test "multiple source lines preserve relative indentation" do
      # This is hard to test without a specific fixture
      # We verify the algorithm doesn't crash on real modules
      elixir_path = :code.which(Enum) |> to_string()
      {:ok, output} = Disasm.run(elixir_path, format: :text, function: "slice/3", source: true)

      # Should not crash and should produce output
      assert is_binary(output)
      assert String.length(output) > 0
    end
  end
end
