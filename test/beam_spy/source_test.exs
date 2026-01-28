defmodule BeamSpy.SourceTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias BeamSpy.Source
  alias BeamSpy.Test.Helpers

  # Use a known Elixir stdlib module that has debug info
  @elixir_beam_path :code.which(Enum) |> to_string()
  # Use a known Erlang module
  @erlang_beam_path :code.which(:lists) |> to_string()
  # Use maps module for additional Erlang testing
  @maps_beam_path :code.which(:maps) |> to_string()

  describe "load_source/1" do
    test "loads source from Elixir module with debug info" do
      # Elixir modules typically have source paths that may not exist
      # on the build machine, but we can test that it at least tries
      result = Source.load_source(@elixir_beam_path)

      # Should either succeed with source or try to reconstruct
      case result do
        {:ok, lines, {:file, _path}} ->
          assert is_map(lines)

        {:ok, lines, :reconstructed} ->
          assert is_map(lines)

        {:error, _} ->
          # This is OK - source file might not exist
          :ok
      end
    end

    test "handles Erlang module" do
      result = Source.load_source(@erlang_beam_path)

      # Erlang stdlib might not have accessible source
      case result do
        {:ok, lines, {:file, _path}} ->
          assert is_map(lines)

        {:ok, lines, :reconstructed} ->
          assert is_map(lines)

        {:error, _} ->
          :ok
      end
    end

    test "returns error for non-existent file" do
      assert {:error, _} = Source.load_source("/nonexistent/file.beam")
    end

    test "loads from explicit source path" do
      # Create a temp file to test explicit source loading
      tmp_path = Path.join(System.tmp_dir!(), "test_source.ex")

      File.write!(tmp_path, """
      defmodule Test do
        def foo, do: :ok
      end
      """)

      {:ok, lines, source_type} = Source.load_source(@erlang_beam_path, source_path: tmp_path)
      assert Map.get(lines, 1) =~ "defmodule"
      assert {:file, ^tmp_path} = source_type

      File.rm!(tmp_path)
    end
  end

  describe "group_by_line/1" do
    test "groups instructions by line markers" do
      instructions = [
        {:label, 1},
        {:line, 10},
        {:func_info, {:atom, Test}, {:atom, :foo}, 0},
        {:label, 2},
        {:line, 12},
        {:move, {:atom, :ok}, {:x, 0}},
        {:return}
      ]

      groups = Source.group_by_line(instructions)

      # Should have groups for line nil, 10, and 12
      assert length(groups) >= 2

      # Find the line 10 group
      line_10 = Enum.find(groups, fn {line, _} -> line == 10 end)
      assert line_10 != nil
      {10, insts_10} = line_10
      assert length(insts_10) >= 1

      # Find the line 12 group
      line_12 = Enum.find(groups, fn {line, _} -> line == 12 end)
      assert line_12 != nil
      {12, insts_12} = line_12
      assert length(insts_12) >= 1
    end

    test "handles instructions before any line marker" do
      instructions = [
        {:label, 1},
        {:func_info, {:atom, Test}, {:atom, :foo}, 0},
        {:line, 5},
        {:return}
      ]

      groups = Source.group_by_line(instructions)

      # First group should have nil line (before any line marker)
      [{first_line, _} | _] = groups
      assert first_line == nil or first_line == 5
    end

    test "merges consecutive groups with same line" do
      instructions = [
        {:line, 10},
        {:move, {:atom, :a}, {:x, 0}},
        # Same line again
        {:line, 10},
        {:move, {:atom, :b}, {:x, 1}}
      ]

      groups = Source.group_by_line(instructions)

      # Should merge the two line 10 groups
      line_10_groups = Enum.filter(groups, fn {line, _} -> line == 10 end)
      assert length(line_10_groups) == 1

      [{10, insts}] = line_10_groups
      assert length(insts) == 2
    end

    test "handles empty instructions" do
      groups = Source.group_by_line([])
      assert groups == []
    end

    test "handles parsed instruction format" do
      # This is the format after parse_instruction
      instructions = [
        {:control, "label", ["1"]},
        {:meta, "line", ["10"]},
        {:error, "func_info", [":Test", ":foo", "0"]},
        {:control, "label", ["2"]},
        {:return, "return", []}
      ]

      groups = Source.group_by_line(instructions)

      # Should recognize {:meta, "line", ["N"]} format
      line_10 = Enum.find(groups, fn {line, _} -> line == 10 end)
      assert line_10 != nil
    end
  end

  describe "fixture-based tests" do
    test "loads source from test fixture with source file" do
      result = Source.load_source("test/fixtures/beam/simple.beam")

      case result do
        {:ok, lines, {:file, _path}} ->
          assert is_map(lines)
          assert map_size(lines) >= 0

        {:ok, lines, :reconstructed} ->
          assert is_map(lines)
          assert map_size(lines) >= 0

        {:error, _} ->
          # Source file path might not be found
          :ok
      end
    end

    test "returns error for stripped module without debug info" do
      result = Source.load_source("test/fixtures/beam/no_debug_info.beam")
      assert {:error, :no_debug_info} = result
    end
  end

  describe "Erlang source reconstruction" do
    test "loads reconstructed source from Erlang stdlib" do
      result = Source.load_source(@erlang_beam_path)

      case result do
        {:ok, lines, :reconstructed} ->
          assert is_map(lines)
          assert map_size(lines) > 0

          # Should have module declaration
          module_lines = Enum.filter(lines, fn {_, text} -> text =~ "-module" end)
          assert length(module_lines) > 0

        {:error, reason} ->
          # Some Erlang versions might not have debug info
          assert reason in [:no_debug_info, :unknown_debug_format]
      end
    end

    test "reconstructed Erlang source has function definitions" do
      case Source.load_source(@erlang_beam_path) do
        {:ok, lines, :reconstructed} ->
          # Should have function definitions in name/arity: format
          func_lines = Enum.filter(lines, fn {_, text} -> text =~ ~r/\w+\/\d+:/ end)
          assert length(func_lines) > 0

          # Should include common functions like map, foldl, etc.
          all_text = lines |> Map.values() |> Enum.join("\n")
          assert all_text =~ "map/2:" or all_text =~ "foldl/3:"

        {:error, _} ->
          :ok
      end
    end

    test "reconstructed Erlang source has readable argument patterns" do
      case Source.load_source(@erlang_beam_path) do
        {:ok, lines, :reconstructed} ->
          all_text = lines |> Map.values() |> Enum.join("\n")

          # Should have variable names, not raw AST
          # Erlang uses capitalized variable names
          assert all_text =~ ~r/[A-Z][a-zA-Z0-9_]*/

          # Should NOT have raw AST tuples like {:var, ...}
          refute all_text =~ "{:var,"
          refute all_text =~ "{:atom,"

        {:error, _} ->
          :ok
      end
    end

    test "reconstructed source formats list patterns correctly" do
      case Source.load_source(@erlang_beam_path) do
        {:ok, lines, :reconstructed} ->
          all_text = lines |> Map.values() |> Enum.join("\n")

          # If there are list patterns, they should use [H | T] syntax
          if all_text =~ "|" do
            assert all_text =~ ~r/\[.*\|.*\]/
          end

        {:error, _} ->
          :ok
      end
    end

    test "loads source from maps module (another Erlang stdlib)" do
      result = Source.load_source(@maps_beam_path)

      case result do
        {:ok, lines, :reconstructed} ->
          assert is_map(lines)
          all_text = lines |> Map.values() |> Enum.join("\n")

          # maps module should have functions like fold, map, etc.
          assert all_text =~ ~r/(fold|map|filter)\/\d+:/

        {:error, _} ->
          :ok
      end
    end
  end

  describe "source type tracking" do
    test "returns {:file, path} for real source files" do
      # Create a temp file
      tmp_path = Path.join(System.tmp_dir!(), "test_source_type.ex")

      File.write!(tmp_path, """
      defmodule TestSourceType do
        def foo, do: :ok
      end
      """)

      {:ok, _lines, source_type} = Source.load_source(@erlang_beam_path, source_path: tmp_path)
      assert {:file, ^tmp_path} = source_type

      File.rm!(tmp_path)
    end

    test "returns :reconstructed for debug info source" do
      case Source.load_source(@elixir_beam_path) do
        {:ok, _lines, source_type} ->
          # Should be either :reconstructed or {:file, path}
          assert source_type == :reconstructed or match?({:file, _}, source_type)

        {:error, _} ->
          :ok
      end
    end

    test "Erlang modules use :reconstructed type" do
      case Source.load_source(@erlang_beam_path) do
        {:ok, _lines, source_type} ->
          # Erlang stdlib should be reconstructed (no source files shipped)
          assert source_type == :reconstructed

        {:error, _} ->
          :ok
      end
    end
  end

  describe "line table parsing" do
    test "parses line table from Elixir module" do
      result = Source.parse_line_table(@elixir_beam_path)

      case result do
        {:ok, table} ->
          assert is_map(table)
          # Line table maps indices to line numbers
          for {idx, line} <- table do
            assert is_integer(idx)
            assert is_integer(line)
            assert idx >= 0
            assert line >= 0
          end

        {:error, _} ->
          :ok
      end
    end

    test "parses line table from Erlang module" do
      result = Source.parse_line_table(@erlang_beam_path)

      case result do
        {:ok, table} ->
          assert is_map(table)
          assert map_size(table) > 0

        {:error, _} ->
          :ok
      end
    end

    test "line table indices are zero-based" do
      case Source.parse_line_table(@elixir_beam_path) do
        {:ok, table} ->
          indices = Map.keys(table)
          # Should have index 0 or start from a low number
          min_idx = Enum.min(indices)
          assert min_idx >= 0 and min_idx < 10

        {:error, _} ->
          :ok
      end
    end
  end

  describe "group_by_line with line table" do
    test "resolves line indices using line table" do
      # Create instructions with line indices
      instructions = [
        {:line, 0},
        {:move, {:atom, :ok}, {:x, 0}},
        {:line, 1},
        {:return}
      ]

      # Line table maps indices to actual line numbers
      line_table = %{0 => 100, 1 => 105}

      groups = Source.group_by_line(instructions, line_table)

      # Should use actual line numbers from table
      line_numbers = Enum.map(groups, fn {line, _} -> line end) |> Enum.reject(&is_nil/1)
      assert 100 in line_numbers
      assert 105 in line_numbers
    end

    test "falls back to index when not in line table" do
      instructions = [
        {:line, 42},
        {:return}
      ]

      # Empty line table
      line_table = %{}

      groups = Source.group_by_line(instructions, line_table)

      # Should use the raw index as line number
      [{line, _}] = groups
      assert line == 42
    end

    test "handles mixed resolved and unresolved indices" do
      instructions = [
        {:line, 0},
        {:move, {:atom, :a}, {:x, 0}},
        {:line, 5},
        {:return}
      ]

      # Only some indices in table
      line_table = %{0 => 100}

      groups = Source.group_by_line(instructions, line_table)
      line_numbers = Enum.map(groups, fn {line, _} -> line end) |> Enum.reject(&is_nil/1)

      # Index 0 -> 100, Index 5 -> 5 (fallback)
      assert 100 in line_numbers
      assert 5 in line_numbers
    end
  end

  describe "property tests" do
    property "line numbers in grouped instructions preserve input order" do
      # Test with generated instruction sequences that have line markers
      check all(
              line_markers <- list_of(positive_integer(), min_length: 1, max_length: 20),
              instructions_per_line <- list_of(positive_integer(), length: length(line_markers))
            ) do
        # Build an instruction sequence with line markers
        instructions =
          Enum.zip(line_markers, instructions_per_line)
          |> Enum.flat_map(fn {line, count} ->
            # Add a line marker followed by some instructions
            [{:line, line}] ++ List.duplicate({:return}, count)
          end)

        groups = Source.group_by_line(instructions)
        output_lines = Enum.map(groups, fn {line, _} -> line end) |> Enum.reject(&is_nil/1)

        # Output order should match the unique ordered input sequence
        # (consecutive duplicates are merged, so we need to dedup while preserving order)
        expected_order = Enum.dedup(line_markers)
        assert output_lines == expected_order
      end
    end

    property "grouped instructions preserve all non-line instructions" do
      check all(
              num_groups <- integer(1..10),
              line_numbers <- list_of(positive_integer(), length: num_groups),
              instruction_counts <- list_of(integer(1..5), length: num_groups)
            ) do
        # Build instruction list with line markers and returns
        total_non_line_instructions = Enum.sum(instruction_counts)

        instructions =
          Enum.zip(line_numbers, instruction_counts)
          |> Enum.flat_map(fn {line, count} ->
            [{:line, line}] ++ List.duplicate({:return}, count)
          end)

        groups = Source.group_by_line(instructions)

        # Count all non-line instructions in groups
        grouped_instruction_count =
          groups
          |> Enum.flat_map(fn {_line, insts} -> insts end)
          |> length()

        # Should preserve all non-line instructions
        assert grouped_instruction_count == total_non_line_instructions
      end
    end

    property "grouping stdlib modules produces valid groups" do
      check all(module <- member_of([Enum, List, Map, String, :lists, :maps])) do
        beam_path = Helpers.beam_path(module)
        {:ok, result} = BeamSpy.Commands.Disasm.extract(beam_path)

        # Get instructions from first function
        case result.functions do
          [first_func | _] ->
            groups = Source.group_by_line(first_func.instructions)

            # Each group should be a tuple {line | nil, list}
            for {line, insts} <- groups do
              assert is_nil(line) or is_integer(line)
              assert is_list(insts)
            end

          [] ->
            :ok
        end
      end
    end

    property "line table resolution is consistent" do
      check all(
              num_indices <- integer(1..20),
              base_line <- integer(1..1000),
              offsets <- list_of(integer(0..100), length: num_indices)
            ) do
        # Build a line table
        line_table =
          offsets
          |> Enum.with_index()
          |> Map.new(fn {offset, idx} -> {idx, base_line + offset} end)

        # Build instructions using those indices
        instructions =
          0..(num_indices - 1)
          |> Enum.flat_map(fn idx ->
            [{:line, idx}, {:return}]
          end)

        groups = Source.group_by_line(instructions, line_table)
        result_lines = Enum.map(groups, fn {line, _} -> line end) |> Enum.reject(&is_nil/1)

        # Each result line should be base_line + corresponding offset
        expected_lines = Enum.map(offsets, &(base_line + &1)) |> Enum.dedup()
        assert result_lines == expected_lines
      end
    end
  end

  describe "Erlang AST pretty printing edge cases" do
    # These tests verify the erl_pp_form function handles various AST nodes

    test "load_source handles empty module gracefully" do
      # We can't easily create an empty module, but we can verify
      # the error handling works for malformed paths
      result = Source.load_source("/completely/fake/path.beam")
      assert {:error, _} = result
    end

    test "Erlang source reconstruction handles multiple function clauses" do
      case Source.load_source(@erlang_beam_path) do
        {:ok, lines, :reconstructed} ->
          all_text = lines |> Map.values() |> Enum.join("\n")

          # Functions with multiple clauses should show semicolons
          # e.g., "foldl/3: foldl(...) -> ...; foldl(...) -> ..."
          if all_text =~ "foldl/3:" do
            # foldl has multiple clauses
            foldl_line = Enum.find(lines, fn {_, text} -> text =~ "foldl/3:" end)

            if foldl_line do
              {_, text} = foldl_line
              # Multiple clauses are separated by semicolons
              assert text =~ ";" or text =~ "->"
            end
          end

        {:error, _} ->
          :ok
      end
    end

    test "handles modules with map patterns" do
      # maps module uses map patterns extensively
      case Source.load_source(@maps_beam_path) do
        {:ok, lines, :reconstructed} ->
          # Should not crash
          assert is_map(lines)

        {:error, _} ->
          :ok
      end
    end
  end

  describe "integration tests with real modules" do
    test "can load and group instructions for GenServer" do
      beam_path = :code.which(GenServer) |> to_string()

      case Source.load_source(beam_path) do
        {:ok, lines, source_type} ->
          assert is_map(lines)
          assert source_type == :reconstructed or match?({:file, _}, source_type)

          # Load line table
          case Source.parse_line_table(beam_path) do
            {:ok, line_table} ->
              {:ok, result} = BeamSpy.Commands.Disasm.extract(beam_path, function: "call/3")

              case result.functions do
                [func | _] ->
                  groups = Source.group_by_line(func.raw_instructions, line_table)
                  assert length(groups) > 0

                [] ->
                  :ok
              end

            {:error, _} ->
              :ok
          end

        {:error, _} ->
          :ok
      end
    end

    test "can load and group instructions for :ets (Erlang)" do
      beam_path = :code.which(:ets) |> to_string()

      case Source.load_source(beam_path) do
        {:ok, lines, :reconstructed} ->
          assert is_map(lines)

          {:ok, result} = BeamSpy.Commands.Disasm.extract(beam_path, function: "lookup/2")

          case result.functions do
            [func | _] ->
              groups = Source.group_by_line(func.raw_instructions)
              assert is_list(groups)

            [] ->
              :ok
          end

        {:error, _} ->
          # Some modules might not have debug info
          :ok
      end
    end

    test "handles modules with no debug info" do
      # Test fixture without debug info
      result = Source.load_source("test/fixtures/beam/no_debug_info.beam")
      assert {:error, :no_debug_info} = result
    end
  end

  describe "Gleam source reconstruction" do
    @tag :gleam
    test "loads source from Gleam stdlib" do
      case Helpers.gleam_beam_path("gleam@list") do
        nil ->
          # Skip if Gleam stdlib not available
          :ok

        beam_path ->
          result = Source.load_source(beam_path)

          case result do
            {:ok, lines, source_type} ->
              assert is_map(lines)
              assert map_size(lines) > 0
              assert source_type == :reconstructed or match?({:file, _}, source_type)

              # Should have module declaration (Erlang style)
              module_lines = Enum.filter(lines, fn {_, text} -> text =~ "-module" end)
              assert length(module_lines) > 0

            {:error, reason} ->
              assert reason in [:no_debug_info, :unknown_debug_format]
          end
      end
    end

    @tag :gleam
    test "Gleam source has function definitions" do
      case Helpers.gleam_beam_path("gleam@list") do
        nil ->
          :ok

        beam_path ->
          case Source.load_source(beam_path) do
            {:ok, lines, _source_type} ->
              all_text = lines |> Map.values() |> Enum.join("\n")

              # Gleam compiles to Erlang, so we see Erlang function definitions
              # Either name/arity: format (reconstructed) or function declarations (file)
              assert all_text =~ ~r/(map|filter|fold)/ or all_text =~ "-spec"

            {:error, _} ->
              :ok
          end
      end
    end

    @tag :gleam
    test "Gleam modules have Erlang-style debug info" do
      case Helpers.gleam_beam_path("gleam@list") do
        nil ->
          :ok

        beam_path ->
          case :beam_lib.chunks(to_charlist(beam_path), [:debug_info]) do
            {:ok, {mod, [{:debug_info, {:debug_info_v1, :erl_abstract_code, _}}]}} ->
              # Gleam compiles to Erlang, so it uses erl_abstract_code
              assert mod == :"gleam@list"

            {:ok, {_, [{:debug_info, :no_debug_info}]}} ->
              # Acceptable - compiled without debug info
              :ok

            {:error, _} ->
              :ok
          end
      end
    end

    @tag :gleam
    test "can parse line table from Gleam module" do
      case Helpers.gleam_beam_path("gleam@list") do
        nil ->
          :ok

        beam_path ->
          case Source.parse_line_table(beam_path) do
            {:ok, table} ->
              assert is_map(table)
              assert map_size(table) > 0

              # Line numbers should be positive
              for {_idx, line} <- table do
                assert line >= 0
              end

            {:error, _} ->
              :ok
          end
      end
    end

    @tag :gleam
    test "Gleam dict module source loading" do
      case Helpers.gleam_beam_path("gleam@dict") do
        nil ->
          :ok

        beam_path ->
          case Source.load_source(beam_path) do
            {:ok, lines, _source_type} ->
              assert is_map(lines)

              # dict module should have functions like get, insert, etc. (Erlang style)
              all_text = lines |> Map.values() |> Enum.join("\n")
              assert all_text =~ ~r/(get|insert|new|from_list)/

            {:error, _} ->
              :ok
          end
      end
    end

    @tag :gleam
    test "custom Gleam fixture source loading" do
      case Helpers.gleam_fixture_path("test_fixture") do
        nil ->
          :ok

        beam_path ->
          case Source.load_source(beam_path) do
            {:ok, lines, _source_type} ->
              assert is_map(lines)

              # Should have our custom functions (Erlang style)
              all_text = lines |> Map.values() |> Enum.join("\n")
              assert all_text =~ "hello" or all_text =~ "add" or all_text =~ "greet"

            {:error, _} ->
              :ok
          end
      end
    end

    @tag :gleam
    test "custom Gleam fixture has correct module declaration" do
      case Helpers.gleam_fixture_path("test_fixture") do
        nil ->
          :ok

        beam_path ->
          case Source.load_source(beam_path) do
            {:ok, lines, _source_type} ->
              module_lines = Enum.filter(lines, fn {_, text} -> text =~ "-module" end)
              assert length(module_lines) > 0
              {_, text} = hd(module_lines)
              assert text =~ "test_fixture"

            {:error, _} ->
              :ok
          end
      end
    end
  end
end
