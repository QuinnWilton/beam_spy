defmodule BeamSpy.BeamFileTest do
  use ExUnit.Case, async: true

  alias BeamSpy.BeamFile

  # Use a known stdlib module for testing
  @test_beam_path :code.which(:lists) |> to_string()

  describe "info/1" do
    test "returns info for valid beam file" do
      assert {:ok, info} = BeamFile.info(@test_beam_path)
      assert info.module == :lists
      assert info.file == @test_beam_path
      assert is_list(info.chunks)
      assert length(info.chunks) > 0
    end

    test "each chunk has id, size, and description" do
      {:ok, info} = BeamFile.info(@test_beam_path)

      for chunk <- info.chunks do
        assert is_binary(chunk.id)
        assert is_integer(chunk.size)
        assert chunk.size >= 0
        assert is_binary(chunk.description)
      end
    end

    test "returns error for non-beam file" do
      # Create a temp file that's not a BEAM file
      tmp_path = Path.join(System.tmp_dir!(), "not_a_beam.beam")
      File.write!(tmp_path, "not a beam file")

      try do
        assert {:error, :not_a_beam_file} = BeamFile.info(tmp_path)
      after
        File.rm(tmp_path)
      end
    end

    test "returns error for missing file" do
      assert {:error, {:file_error, _}} = BeamFile.info("/nonexistent/file.beam")
    end
  end

  describe "read_all_chunks/1" do
    test "returns all chunks as {id, binary} tuples" do
      assert {:ok, chunks} = BeamFile.read_all_chunks(@test_beam_path)
      assert is_list(chunks)
      assert length(chunks) > 0

      for {id, data} <- chunks do
        # IDs can be charlists or atoms depending on :beam_lib version
        assert is_atom(id) or is_list(id)
        assert is_binary(data)
      end
    end

    test "includes standard chunks" do
      {:ok, chunks} = BeamFile.read_all_chunks(@test_beam_path)
      # Convert all IDs to strings for comparison
      chunk_ids =
        Enum.map(chunks, fn {id, _} ->
          cond do
            is_atom(id) -> Atom.to_string(id)
            is_list(id) -> List.to_string(id)
          end
        end)

      # Every BEAM file should have these
      assert "AtU8" in chunk_ids or "Atom" in chunk_ids
      assert "Code" in chunk_ids
      assert "ExpT" in chunk_ids
      assert "ImpT" in chunk_ids
    end
  end

  describe "read_atoms/1" do
    test "returns list of atoms" do
      assert {:ok, atoms} = BeamFile.read_atoms(@test_beam_path)
      assert is_list(atoms)
      assert length(atoms) > 0

      for atom <- atoms do
        assert is_atom(atom)
      end
    end

    test "includes module name" do
      {:ok, atoms} = BeamFile.read_atoms(@test_beam_path)
      assert :lists in atoms
    end

    test "includes function names" do
      {:ok, atoms} = BeamFile.read_atoms(@test_beam_path)
      # lists module definitely has these functions
      assert :map in atoms
      assert :filter in atoms
    end
  end

  describe "read_exports/1" do
    test "returns list of export tuples" do
      assert {:ok, exports} = BeamFile.read_exports(@test_beam_path)
      assert is_list(exports)
      assert length(exports) > 0

      for export <- exports do
        # Exports can be {name, arity} or {name, arity, label}
        case export do
          {name, arity} ->
            assert is_atom(name)
            assert is_integer(arity) and arity >= 0

          {name, arity, label} ->
            assert is_atom(name)
            assert is_integer(arity) and arity >= 0
            assert is_integer(label) and label >= 0
        end
      end
    end

    test "includes known exports" do
      {:ok, exports} = BeamFile.read_exports(@test_beam_path)

      names_arities =
        Enum.map(exports, fn
          {n, a, _} -> {n, a}
          {n, a} -> {n, a}
        end)

      assert {:map, 2} in names_arities
      assert {:filter, 2} in names_arities
      assert {:reverse, 1} in names_arities
    end
  end

  describe "read_imports/1" do
    test "returns list of {module, name, arity} tuples" do
      assert {:ok, imports} = BeamFile.read_imports(@test_beam_path)
      assert is_list(imports)

      for {mod, name, arity} <- imports do
        assert is_atom(mod)
        assert is_atom(name)
        assert is_integer(arity) and arity >= 0
      end
    end
  end

  describe "read_compile_info/1" do
    test "returns keyword list with compile metadata" do
      assert {:ok, info} = BeamFile.read_compile_info(@test_beam_path)
      assert is_list(info)
      # Should have at least some standard keys
      assert Keyword.has_key?(info, :version) or Keyword.has_key?(info, :options)
    end
  end

  describe "read_attributes/1" do
    test "returns keyword list of module attributes" do
      assert {:ok, attrs} = BeamFile.read_attributes(@test_beam_path)
      assert is_list(attrs)
    end
  end

  describe "get_module_name/1" do
    test "returns module name for valid beam file" do
      assert {:ok, :lists} = BeamFile.get_module_name(@test_beam_path)
    end

    test "returns error for non-beam file" do
      tmp_path = Path.join(System.tmp_dir!(), "not_a_beam2.beam")
      File.write!(tmp_path, "not a beam file")

      try do
        assert {:error, :not_a_beam_file} = BeamFile.get_module_name(tmp_path)
      after
        File.rm(tmp_path)
      end
    end
  end

  describe "get_md5/1" do
    test "returns MD5 hash" do
      assert {:ok, md5} = BeamFile.get_md5(@test_beam_path)
      assert is_binary(md5)
      assert byte_size(md5) == 16
    end
  end

  describe "read_raw_chunk/2" do
    test "returns raw chunk data" do
      assert {:ok, data} = BeamFile.read_raw_chunk(@test_beam_path, "Code")
      assert is_binary(data)
      assert byte_size(data) > 0
    end

    test "accepts atom chunk id" do
      assert {:ok, data} = BeamFile.read_raw_chunk(@test_beam_path, :Code)
      assert is_binary(data)
    end

    test "returns error for missing chunk" do
      assert {:error, {:missing_chunk, "XXXX"}} =
               BeamFile.read_raw_chunk(@test_beam_path, "XXXX")
    end
  end

  describe "chunk_descriptions/0" do
    test "returns map of descriptions" do
      descriptions = BeamFile.chunk_descriptions()
      assert is_map(descriptions)
      assert Map.has_key?(descriptions, "Code")
      assert Map.has_key?(descriptions, "AtU8")
    end
  end

  describe "Elixir modules" do
    @elixir_beam_path :code.which(Enum) |> to_string()

    test "can read Elixir module" do
      assert {:ok, info} = BeamFile.info(@elixir_beam_path)
      assert info.module == Enum
    end

    test "Elixir modules have Dbgi chunk" do
      {:ok, info} = BeamFile.info(@elixir_beam_path)
      chunk_ids = Enum.map(info.chunks, & &1.id)
      assert "Dbgi" in chunk_ids
    end

    test "can read Elixir atoms" do
      {:ok, atoms} = BeamFile.read_atoms(@elixir_beam_path)
      assert Enum in atoms
    end
  end
end
