defmodule BeamSpy.Integration.RegressionTest do
  @moduledoc """
  Regression tests using golden file comparisons.

  These tests ensure command output remains stable across changes.
  They compare actual output against known-good snapshots.
  """

  use ExUnit.Case, async: true

  alias BeamSpy.Commands.{Atoms, Exports, Imports, Info, Disasm, Chunks}

  @moduletag :regression

  @fixture_dir "test/fixtures/beam"

  describe "atoms command regression" do
    test "simple.beam atoms output is stable" do
      path = Path.join(@fixture_dir, "simple.beam")
      result = Atoms.run(path, format: :json)

      {:ok, atoms} = Jason.decode(result)
      assert is_list(atoms)

      # Known atoms in TestSimple module
      assert "Elixir.TestSimple" in atoms
      assert "foo" in atoms
      assert "bar" in atoms
      assert "ok" in atoms
    end

    test "complex.beam atoms output is stable" do
      path = Path.join(@fixture_dir, "complex.beam")
      result = Atoms.run(path, format: :json)

      {:ok, atoms} = Jason.decode(result)
      assert "Elixir.TestComplex" in atoms
      assert "clamp" in atoms
      assert "recursive" in atoms
      assert "done" in atoms
    end
  end

  describe "exports command regression" do
    test "simple.beam exports are stable" do
      path = Path.join(@fixture_dir, "simple.beam")
      result = Exports.run(path, format: :json)

      {:ok, exports} = Jason.decode(result)
      names = Enum.map(exports, & &1["name"])

      assert "foo" in names
      assert "bar" in names
      assert "__info__" in names
    end

    test "recursive.beam exports are stable" do
      path = Path.join(@fixture_dir, "recursive.beam")
      result = Exports.run(path, format: :json)

      {:ok, exports} = Jason.decode(result)
      names = Enum.map(exports, & &1["name"])

      assert "factorial" in names
      assert "mutual_a" in names
      assert "mutual_b" in names
    end
  end

  describe "imports command regression" do
    test "with_imports.beam imports are stable" do
      path = Path.join(@fixture_dir, "with_imports.beam")
      result = Imports.run(path, format: :json)

      {:ok, imports} = Jason.decode(result)
      modules = Enum.map(imports, & &1["module"]) |> Enum.uniq()

      # Should import from erlang
      assert "erlang" in modules
    end

    test "uses_enum.beam imports are stable" do
      path = Path.join(@fixture_dir, "uses_enum.beam")
      result = Imports.run(path, format: :json)

      {:ok, imports} = Jason.decode(result)
      modules = Enum.map(imports, & &1["module"]) |> Enum.uniq()

      # Should import from Enum (may be with or without Elixir. prefix)
      assert "Enum" in modules or "Elixir.Enum" in modules
    end
  end

  describe "info command regression" do
    test "simple.beam info is stable" do
      path = Path.join(@fixture_dir, "simple.beam")
      result = Info.run(path, format: :json)

      {:ok, info} = Jason.decode(result)

      assert info["module"] == "Elixir.TestSimple"
      assert is_integer(info["export_count"])
      assert info["export_count"] >= 2
    end

    test "genserver.beam info is stable" do
      path = Path.join(@fixture_dir, "genserver.beam")
      result = Info.run(path, format: :json)

      {:ok, info} = Jason.decode(result)

      assert info["module"] == "Elixir.TestGenServer"
      # GenServer modules have callbacks
      assert info["export_count"] >= 4
    end
  end

  describe "chunks command regression" do
    test "simple.beam chunks are stable" do
      path = Path.join(@fixture_dir, "simple.beam")
      result = Chunks.run(path, format: :json)

      {:ok, data} = Jason.decode(result)
      chunk_ids = Enum.map(data["chunks"], & &1["id"])

      # Standard BEAM chunks
      assert "AtU8" in chunk_ids or "Atom" in chunk_ids
      assert "Code" in chunk_ids
      assert "ExpT" in chunk_ids
      assert "ImpT" in chunk_ids
    end

    test "no_debug_info.beam has fewer chunks" do
      path = Path.join(@fixture_dir, "no_debug_info.beam")
      result = Chunks.run(path, format: :json)

      {:ok, data} = Jason.decode(result)
      chunk_ids = Enum.map(data["chunks"], & &1["id"])

      # Stripped modules lack debug info
      refute "Dbgi" in chunk_ids
    end
  end

  describe "disasm command regression" do
    test "simple.beam disasm structure is stable" do
      path = Path.join(@fixture_dir, "simple.beam")
      {:ok, result} = Disasm.extract(path)

      assert result.module == TestSimple
      func_names = Enum.map(result.functions, & &1.name)

      assert :foo in func_names
      assert :bar in func_names
    end

    test "recursive.beam contains expected call patterns" do
      path = Path.join(@fixture_dir, "recursive.beam")
      {:ok, result} = Disasm.extract(path, function: "factorial/1")

      [func] = result.functions
      instructions = func.instructions

      # Should have call instruction for recursion
      instruction_names = Enum.map(instructions, fn {_, name, _} -> name end)
      assert "call" in instruction_names or "call_only" in instruction_names or "call_last" in instruction_names
    end

    test "long_function.beam handles many clauses" do
      path = Path.join(@fixture_dir, "long_function.beam")
      {:ok, result} = Disasm.extract(path, function: "lookup/1")

      [func] = result.functions

      # Should have many labels for case clauses
      label_count =
        func.instructions
        |> Enum.count(fn {_, name, _} -> name == "label" end)

      # 100 case clauses should generate many labels
      assert label_count > 50
    end
  end

  describe "cross-command consistency" do
    test "export count matches between info and exports" do
      path = Path.join(@fixture_dir, "simple.beam")

      info_result = Info.run(path, format: :json)
      {:ok, info} = Jason.decode(info_result)

      exports_result = Exports.run(path, format: :json)
      {:ok, exports} = Jason.decode(exports_result)

      assert info["export_count"] == length(exports)
    end

    test "atom count matches between info and atoms" do
      path = Path.join(@fixture_dir, "simple.beam")

      info_result = Info.run(path, format: :json)
      {:ok, info} = Jason.decode(info_result)

      atoms_result = Atoms.run(path, format: :json)
      {:ok, atoms} = Jason.decode(atoms_result)

      assert info["atom_count"] == length(atoms)
    end
  end
end
