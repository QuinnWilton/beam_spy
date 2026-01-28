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
      output = Disasm.run(@test_beam_path, format: :text)
      assert output =~ "module: :lists"
      assert output =~ "exports:"
    end

    test "outputs function headers" do
      output = Disasm.run(@test_beam_path, format: :text)
      assert output =~ "function map/2"
      assert output =~ "(entry:"
    end

    test "outputs instructions" do
      output = Disasm.run(@test_beam_path, format: :text, function: "reverse/1")
      # Should contain common instructions
      assert output =~ "label"
      assert output =~ "func_info"
    end

    test "formats registers" do
      output = Disasm.run(@test_beam_path, format: :text, function: "map/2")
      # Should format x registers
      assert output =~ "x(" or output =~ "y("
    end
  end

  describe "run/2 json format" do
    test "outputs valid JSON" do
      output = Disasm.run(@test_beam_path, format: :json, function: "reverse/1")
      {:ok, decoded} = Jason.decode(output)

      assert Map.has_key?(decoded, "module")
      assert Map.has_key?(decoded, "exports")
      assert Map.has_key?(decoded, "functions")
    end

    test "function structure in JSON" do
      output = Disasm.run(@test_beam_path, format: :json, function: "reverse/1")
      {:ok, decoded} = Jason.decode(output)

      [func] = decoded["functions"]
      assert func["name"] == "reverse"
      assert func["arity"] == 1
      assert is_integer(func["entry"])
      assert is_list(func["instructions"])
    end

    test "instruction structure in JSON" do
      output = Disasm.run(@test_beam_path, format: :json, function: "reverse/1")
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
      valid_categories = [:call, :control, :data, :error, :return, :stack, :meta, :message, :binary, :float, :exception, :unknown]

      for cat <- categories do
        assert cat in valid_categories, "Invalid category: #{inspect(cat)}"
      end
    end

    @tag :snapshot
    test "JSON output structure is stable" do
      output = Disasm.run(@test_beam_path, format: :json, function: "reverse/1")
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
      output = Disasm.run(@test_beam_path, format: :text, function: "reverse/1")

      assert output =~ "module: :lists"
      assert output =~ "function reverse/1"
      assert output =~ "label"
      assert output =~ "func_info"
      assert output =~ "return"
    end
  end
end
