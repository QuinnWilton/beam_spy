defmodule BeamSpy.ResolverTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias BeamSpy.Resolver

  describe "resolve/2 with direct file paths" do
    test "resolves existing file path" do
      # Use a known beam file
      beam_path = :code.which(:lists) |> to_string()
      assert {:ok, resolved} = Resolver.resolve(beam_path)
      assert resolved == beam_path
    end

    test "returns error for missing file" do
      assert {:error, :not_found} = Resolver.resolve("./nonexistent.beam")
    end

    test "recognizes path containing slash as file path" do
      assert {:error, :not_found} = Resolver.resolve("./some/path.beam")
    end

    test "recognizes .beam suffix as file path" do
      assert {:error, :not_found} = Resolver.resolve("module.beam")
    end

    test "expands relative paths" do
      # Create a temp file
      tmp_dir = System.tmp_dir!()
      tmp_file = Path.join(tmp_dir, "test_resolver.beam")
      File.write!(tmp_file, "fake beam")

      try do
        {:ok, resolved} = Resolver.resolve(tmp_file)
        assert Path.expand(tmp_file) == resolved
      after
        File.rm(tmp_file)
      end
    end
  end

  describe "resolve/2 with Erlang module names" do
    test "resolves Erlang stdlib module" do
      assert {:ok, path} = Resolver.resolve("lists")
      assert path =~ "lists.beam"
      assert File.exists?(path)
    end

    test "resolves Erlang stdlib module (ets)" do
      assert {:ok, path} = Resolver.resolve("ets")
      assert path =~ "ets.beam"
      assert File.exists?(path)
    end

    test "resolves Erlang stdlib module (gen_server)" do
      assert {:ok, path} = Resolver.resolve("gen_server")
      assert path =~ "gen_server.beam"
      assert File.exists?(path)
    end
  end

  describe "resolve/2 with Elixir module names" do
    test "resolves Elixir stdlib module with prefix" do
      assert {:ok, path} = Resolver.resolve("Elixir.Enum")
      assert path =~ "Elixir.Enum.beam"
      assert File.exists?(path)
    end

    test "resolves Elixir stdlib module without prefix" do
      assert {:ok, path} = Resolver.resolve("Enum")
      assert path =~ "Elixir.Enum.beam"
      assert File.exists?(path)
    end

    test "resolves nested Elixir module" do
      assert {:ok, path} = Resolver.resolve("Enum.EmptyError")
      assert path =~ "Elixir.Enum.EmptyError.beam"
      assert File.exists?(path)
    end

    test "returns error for non-existent module" do
      assert {:error, :not_found} = Resolver.resolve("NonExistentModule")
    end
  end

  describe "resolve/2 with :path option" do
    test "searches additional paths" do
      # Create a temp file in a custom location
      tmp_dir = System.tmp_dir!()
      custom_dir = Path.join(tmp_dir, "custom_beam_path")
      File.mkdir_p!(custom_dir)
      beam_file = Path.join(custom_dir, "Elixir.CustomModule.beam")
      File.write!(beam_file, "fake beam")

      try do
        # Without custom path, should not find it
        assert {:error, :not_found} = Resolver.resolve("CustomModule")

        # With custom path, should find it
        assert {:ok, path} = Resolver.resolve("CustomModule", path: custom_dir)
        assert path == beam_file
      after
        File.rm_rf!(custom_dir)
      end
    end

    test "accepts list of paths" do
      assert {:ok, _} = Resolver.resolve("lists", path: ["/nonexistent", "/also/nonexistent"])
    end
  end

  describe "resolve!/2" do
    test "returns path on success" do
      path = Resolver.resolve!("lists")
      assert path =~ "lists.beam"
    end

    test "raises on not found" do
      assert_raise RuntimeError, ~r/Could not find/, fn ->
        Resolver.resolve!("NonExistentModule")
      end
    end
  end

  describe "search_paths/1" do
    test "returns list of paths" do
      paths = Resolver.search_paths()
      assert is_list(paths)
      assert length(paths) > 0
    end

    test "includes current directory" do
      paths = Resolver.search_paths()
      assert "." in paths
    end

    test "includes Erlang code paths" do
      paths = Resolver.search_paths()
      # Should include stdlib ebin
      assert Enum.any?(paths, &String.contains?(&1, "stdlib"))
    end

    test "includes custom paths" do
      paths = Resolver.search_paths(path: "/custom/path")
      assert "/custom/path" in paths
    end
  end

  # Property tests
  describe "property tests" do
    property "resolution is deterministic" do
      # Use known modules for deterministic testing
      modules = ["lists", "ets", "gen_server", "Enum", "Map", "String"]

      check all(module_name <- member_of(modules)) do
        result1 = Resolver.resolve(module_name)
        result2 = Resolver.resolve(module_name)
        assert result1 == result2
      end
    end

    property "resolved paths exist" do
      modules = ["lists", "ets", "gen_server", "Enum", "Map", "String"]

      check all(module_name <- member_of(modules)) do
        {:ok, path} = Resolver.resolve(module_name)
        assert File.exists?(path)
      end
    end
  end
end
