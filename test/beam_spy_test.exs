defmodule BeamSpyTest do
  use ExUnit.Case

  @lists_beam :code.which(:lists) |> to_string()

  describe "version/0" do
    test "returns version string" do
      assert is_binary(BeamSpy.version())
      assert BeamSpy.version() =~ ~r/^\d+\.\d+\.\d+/
    end
  end

  describe "atoms/2" do
    test "extracts atoms from a beam file path" do
      assert {:ok, atoms} = BeamSpy.atoms(@lists_beam)
      assert is_list(atoms)
      assert :lists in atoms
    end

    test "extracts atoms from a module name" do
      assert {:ok, atoms} = BeamSpy.atoms("lists")
      assert is_list(atoms)
      assert :lists in atoms
    end

    test "supports filter option" do
      assert {:ok, atoms} = BeamSpy.atoms("lists", filter: "reverse")
      assert :reverse in atoms
    end

    test "returns error for non-existent module" do
      assert {:error, _} = BeamSpy.atoms("NonExistentModule12345")
    end
  end

  describe "exports/2" do
    test "extracts exports from a beam file path" do
      assert {:ok, exports} = BeamSpy.exports(@lists_beam)
      assert is_list(exports)
      assert Enum.any?(exports, fn {name, _arity} -> name == :reverse end)
    end

    test "extracts exports from a module name" do
      assert {:ok, exports} = BeamSpy.exports("lists")
      assert is_list(exports)
    end

    test "supports filter option" do
      assert {:ok, exports} = BeamSpy.exports("lists", filter: "reverse")
      assert Enum.all?(exports, fn {name, _arity} ->
        name |> Atom.to_string() |> String.contains?("reverse")
      end)
    end

    test "returns error for non-existent module" do
      assert {:error, _} = BeamSpy.exports("NonExistentModule12345")
    end
  end

  describe "imports/2" do
    test "extracts imports from a beam file path" do
      assert {:ok, imports} = BeamSpy.imports(@lists_beam)
      assert is_list(imports)
    end

    test "extracts imports from a module name" do
      assert {:ok, imports} = BeamSpy.imports("Enum")
      assert is_list(imports)
      # Enum imports from erlang
      assert Enum.any?(imports, fn {mod, _name, _arity} -> mod == :erlang end)
    end

    test "returns error for non-existent module" do
      assert {:error, _} = BeamSpy.imports("NonExistentModule12345")
    end
  end

  describe "info/2" do
    test "extracts info from a beam file path" do
      assert {:ok, info} = BeamSpy.info(@lists_beam)
      assert is_map(info)
      assert info.module == :lists
    end

    test "extracts info from a module name" do
      assert {:ok, info} = BeamSpy.info("Enum")
      assert info.module == Enum
    end

    test "returns error for non-existent module" do
      assert {:error, _} = BeamSpy.info("NonExistentModule12345")
    end
  end

  describe "chunks/2" do
    test "extracts chunks from a beam file path" do
      assert {:ok, chunks} = BeamSpy.chunks(@lists_beam)
      assert is_map(chunks)
      assert is_list(chunks.chunks)
      # All BEAM files have a Code chunk
      assert Enum.any?(chunks.chunks, fn chunk -> chunk.id == "Code" end)
    end

    test "extracts chunks from a module name" do
      assert {:ok, chunks} = BeamSpy.chunks("Enum")
      assert is_map(chunks)
    end

    test "returns error for non-existent module" do
      assert {:error, _} = BeamSpy.chunks("NonExistentModule12345")
    end
  end

  describe "disasm/2" do
    test "disassembles a beam file path" do
      assert {:ok, disasm} = BeamSpy.disasm(@lists_beam)
      assert is_map(disasm)
      assert disasm.module == :lists
      assert is_list(disasm.functions)
    end

    test "disassembles a module name" do
      assert {:ok, disasm} = BeamSpy.disasm("Enum")
      assert disasm.module == Enum
    end

    test "supports function filter option" do
      assert {:ok, disasm} = BeamSpy.disasm("lists", function: "reverse/1")
      assert length(disasm.functions) == 1
      assert hd(disasm.functions).name == :reverse
      assert hd(disasm.functions).arity == 1
    end

    test "returns error for non-existent module" do
      assert {:error, _} = BeamSpy.disasm("NonExistentModule12345")
    end
  end

  describe "callgraph/2" do
    test "builds callgraph from a beam file path" do
      assert {:ok, graph} = BeamSpy.callgraph(@lists_beam)
      assert is_map(graph)
      assert is_list(graph.nodes)
      assert is_list(graph.edges)
    end

    test "builds callgraph from a module name" do
      assert {:ok, graph} = BeamSpy.callgraph("Enum")
      assert is_map(graph)
    end

    test "returns error for non-existent module" do
      assert {:error, _} = BeamSpy.callgraph("NonExistentModule12345")
    end
  end
end
