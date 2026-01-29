defmodule BeamSpy.Commands.ExportsTest do
  use ExUnit.Case, async: true

  alias BeamSpy.Commands.Exports

  @test_beam_path :code.which(:lists) |> to_string()

  describe "extract/2" do
    test "extracts exports from beam file" do
      assert {:ok, exports} = Exports.extract(@test_beam_path)
      assert is_list(exports)
      assert length(exports) > 0

      for {name, arity} <- exports do
        assert is_atom(name)
        assert is_integer(arity)
      end
    end

    test "returns error for non-existent file" do
      assert {:error, {:file_error, :enoent}} = Exports.extract("/nonexistent/file.beam")
    end

    test "returns error for invalid beam file" do
      tmp_path = Path.join(System.tmp_dir!(), "not_a_beam_exports.beam")
      File.write!(tmp_path, "not a beam file")

      try do
        assert {:error, :not_a_beam_file} = Exports.extract(tmp_path)
      after
        File.rm(tmp_path)
      end
    end

    test "includes known functions" do
      {:ok, exports} = Exports.extract(@test_beam_path)
      assert {:map, 2} in exports
      assert {:filter, 2} in exports
    end

    test "exports are sorted" do
      {:ok, exports} = Exports.extract(@test_beam_path)
      names = Enum.map(exports, fn {name, _} -> Atom.to_string(name) end)
      assert names == Enum.sort(names)
    end

    test "filters exports" do
      {:ok, exports} = Exports.extract(@test_beam_path, filter: "map")

      for {name, _} <- exports do
        assert Atom.to_string(name) =~ ~r/map/i
      end
    end
  end

  describe "run/2 text format" do
    test "renders table" do
      {:ok, output} = Exports.run(@test_beam_path, format: :text)
      assert is_binary(output)
      assert output =~ "map"
    end

    test "returns error message for invalid file" do
      {:error, msg} = Exports.run("/nonexistent/file.beam", format: :text)
      assert is_binary(msg)
      assert msg =~ "Error:"
    end

    test "plain format outputs function/arity" do
      {:ok, output} = Exports.run(@test_beam_path, format: :text, plain: true)
      lines = String.split(output, "\n", trim: true)

      for line <- lines do
        assert line =~ ~r/^\w+\/\d+$/
      end
    end
  end

  describe "run/2 json format" do
    test "outputs valid JSON" do
      {:ok, output} = Exports.run(@test_beam_path, format: :json)
      {:ok, decoded} = Jason.decode(output)
      assert is_list(decoded)

      for export <- decoded do
        assert Map.has_key?(export, "name")
        assert Map.has_key?(export, "arity")
      end
    end
  end

  describe "snapshot tests" do
    @tag :snapshot
    test "extract returns sorted list of exports" do
      {:ok, exports} = Exports.extract(@test_beam_path)

      assert is_list(exports)
      assert length(exports) > 20

      # Known :lists exports
      assert {:map, 2} in exports
      assert {:filter, 2} in exports
      assert {:reverse, 1} in exports
      assert {:module_info, 0} in exports
    end

    @tag :snapshot
    test "JSON output structure is stable" do
      {:ok, output} = Exports.run(@test_beam_path, format: :json)
      {:ok, decoded} = Jason.decode(output)

      assert is_list(decoded)
      names = Enum.map(decoded, & &1["name"])

      assert "map" in names
      assert "filter" in names
      assert "reverse" in names
    end

    @tag :snapshot
    test "plain text output format is stable" do
      {:ok, output} = Exports.run(@test_beam_path, format: :text, plain: true)

      lines = String.split(output, "\n", trim: true)
      assert length(lines) > 20

      # Each line should be function/arity format
      for line <- lines do
        assert line =~ ~r/^\w+\/\d+$/
      end

      assert "map/2" in lines
      assert "reverse/1" in lines
    end
  end
end
