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
      output = Atoms.run(@test_beam_path, format: :text)
      lines = String.split(output, "\n", trim: true)
      assert length(lines) > 0
    end

    test "filters atoms" do
      output = Atoms.run(@test_beam_path, format: :text, filter: "reverse")
      assert output =~ "reverse"
    end
  end

  describe "run/2 json format" do
    test "outputs valid JSON array" do
      output = Atoms.run(@test_beam_path, format: :json)
      {:ok, decoded} = Jason.decode(output)
      assert is_list(decoded)

      for atom <- decoded do
        assert is_binary(atom)
      end
    end
  end
end
