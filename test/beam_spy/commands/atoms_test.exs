defmodule BeamSpy.Commands.AtomsTest do
  use ExUnit.Case, async: true

  alias BeamSpy.Commands.Atoms

  @test_beam_path :code.which(:lists) |> to_string()

  describe "extract/2" do
    test "extracts atoms from beam file" do
      assert {:ok, atoms} = Atoms.extract(@test_beam_path)
      assert is_list(atoms)
      assert length(atoms) > 0

      for atom <- atoms do
        assert is_atom(atom)
      end
    end

    test "returns error for non-existent file" do
      assert {:error, {:file_error, :enoent}} = Atoms.extract("/nonexistent/file.beam")
    end

    test "returns error for invalid beam file" do
      tmp_path = Path.join(System.tmp_dir!(), "not_a_beam_atoms.beam")
      File.write!(tmp_path, "not a beam file")

      try do
        assert {:error, :not_a_beam_file} = Atoms.extract(tmp_path)
      after
        File.rm(tmp_path)
      end
    end

    test "filter with no matches returns empty list" do
      {:ok, atoms} = Atoms.extract(@test_beam_path, filter: "xyz_nonexistent_pattern_abc")
      assert atoms == []
    end

    test "includes module name in atoms" do
      {:ok, atoms} = Atoms.extract(@test_beam_path)
      assert :lists in atoms
    end

    test "filters atoms with pattern" do
      {:ok, atoms} = Atoms.extract(@test_beam_path, filter: "map")

      for atom <- atoms do
        assert Atom.to_string(atom) =~ ~r/map/i
      end
    end
  end

  describe "run/2 text format" do
    test "outputs one atom per line" do
      {:ok, output} = Atoms.run(@test_beam_path, format: :text)
      lines = String.split(output, "\n", trim: true)
      assert length(lines) > 0
    end

    test "returns error message for invalid file" do
      {:error, msg} = Atoms.run("/nonexistent/file.beam", format: :text)
      assert is_binary(msg)
      assert msg =~ "Error:"
    end

    test "filters atoms" do
      {:ok, output} = Atoms.run(@test_beam_path, format: :text, filter: "reverse")
      assert output =~ "reverse"
    end
  end

  describe "run/2 json format" do
    test "outputs valid JSON array" do
      {:ok, output} = Atoms.run(@test_beam_path, format: :json)
      {:ok, decoded} = Jason.decode(output)
      assert is_list(decoded)

      for atom <- decoded do
        assert is_binary(atom)
      end
    end
  end

  describe "snapshot tests" do
    @tag :snapshot
    test "extract returns list of atoms" do
      {:ok, atoms} = Atoms.extract(@test_beam_path)

      assert is_list(atoms)
      assert length(atoms) > 50
      assert :lists in atoms
      assert :module_info in atoms
    end

    @tag :snapshot
    test "JSON output structure is stable" do
      {:ok, output} = Atoms.run(@test_beam_path, format: :json)
      {:ok, decoded} = Jason.decode(output)

      assert is_list(decoded)
      assert "lists" in decoded
      assert "module_info" in decoded
    end

    @tag :snapshot
    test "text output format is stable" do
      {:ok, output} = Atoms.run(@test_beam_path, format: :text)

      assert is_binary(output)
      assert output =~ "lists"
      # One atom per line
      lines = String.split(output, "\n", trim: true)
      assert length(lines) > 50
    end
  end
end
