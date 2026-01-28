defmodule BeamSpy.SourceTest do
  use ExUnit.Case, async: true

  alias BeamSpy.Source

  # Use a known Elixir stdlib module that has debug info
  @elixir_beam_path :code.which(Enum) |> to_string()
  # Use a known Erlang module
  @erlang_beam_path :code.which(:lists) |> to_string()

  describe "load_source/1" do
    test "loads source from Elixir module with debug info" do
      # Elixir modules typically have source paths that may not exist
      # on the build machine, but we can test that it at least tries
      result = Source.load_source(@elixir_beam_path)

      # Should either succeed with source or try to reconstruct
      case result do
        {:ok, lines} ->
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
        {:ok, lines} ->
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

      {:ok, lines} = Source.load_source(@erlang_beam_path, source_path: tmp_path)
      assert Map.get(lines, 1) =~ "defmodule"

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
end
