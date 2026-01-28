defmodule BeamSpy.Integration.RealWorldTest do
  @moduledoc """
  Integration tests against real Elixir/Erlang stdlib modules.

  These tests verify BeamSpy works correctly on production modules
  with complex bytecode patterns.
  """

  use ExUnit.Case, async: true

  alias BeamSpy.Commands.{Atoms, Exports, Imports, Info, Disasm, Chunks, Callgraph}
  alias BeamSpy.Test.Helpers

  @moduletag :real_world

  # Elixir stdlib modules to test
  @elixir_modules [Enum, List, Map, String, Keyword, GenServer, Supervisor, Agent]

  # Erlang stdlib modules to test (excluding :erlang which has special handling)
  @erlang_modules [:lists, :maps, :ets, :gen_server, :supervisor]

  describe "atoms command on stdlib" do
    for mod <- @elixir_modules do
      @tag target: mod
      test "extracts atoms from #{inspect(mod)}" do
        path = Helpers.beam_path(unquote(mod))
        {:ok, result} = Atoms.run(path, format: :json)

        assert {:ok, atoms} = Jason.decode(result)
        assert is_list(atoms)
        assert length(atoms) > 0

        # Module name should be in atoms
        mod_name = to_string(unquote(mod))
        assert mod_name in atoms or String.replace(mod_name, "Elixir.", "") in atoms
      end
    end

    for mod <- @erlang_modules do
      @tag target: mod
      test "extracts atoms from #{inspect(mod)}" do
        path = Helpers.beam_path(unquote(mod))
        {:ok, result} = Atoms.run(path, format: :json)

        assert {:ok, atoms} = Jason.decode(result)
        assert is_list(atoms)
        assert length(atoms) > 0
      end
    end
  end

  describe "exports command on stdlib" do
    for mod <- @elixir_modules do
      @tag target: mod
      test "lists exports from #{inspect(mod)}" do
        path = Helpers.beam_path(unquote(mod))
        {:ok, result} = Exports.run(path, format: :json)

        assert {:ok, exports} = Jason.decode(result)
        assert is_list(exports)
        assert length(exports) > 0

        # All Elixir modules have __info__/1
        names = Enum.map(exports, & &1["name"])
        assert "__info__" in names
      end
    end

    for mod <- @erlang_modules do
      @tag target: mod
      test "lists exports from #{inspect(mod)}" do
        path = Helpers.beam_path(unquote(mod))
        {:ok, result} = Exports.run(path, format: :json)

        assert {:ok, exports} = Jason.decode(result)
        assert is_list(exports)
        assert length(exports) > 0

        # All modules have module_info
        names = Enum.map(exports, & &1["name"])
        assert "module_info" in names
      end
    end
  end

  describe "imports command on stdlib" do
    for mod <- @elixir_modules do
      @tag target: mod
      test "lists imports from #{inspect(mod)}" do
        path = Helpers.beam_path(unquote(mod))
        {:ok, result} = Imports.run(path, format: :json)

        assert {:ok, imports} = Jason.decode(result)
        assert is_list(imports)
        # Most modules have imports (erlang BIFs at minimum)
      end
    end
  end

  describe "info command on stdlib" do
    for mod <- @elixir_modules ++ @erlang_modules do
      @tag target: mod
      test "shows info for #{inspect(mod)}" do
        path = Helpers.beam_path(unquote(mod))
        {:ok, result} = Info.run(path, format: :json)

        assert {:ok, info} = Jason.decode(result)
        assert is_map(info)
        assert Map.has_key?(info, "module")
      end
    end
  end

  describe "chunks command on stdlib" do
    for mod <- @elixir_modules ++ @erlang_modules do
      @tag target: mod
      test "lists chunks for #{inspect(mod)}" do
        path = Helpers.beam_path(unquote(mod))
        {:ok, result} = Chunks.run(path, format: :json)

        assert {:ok, data} = Jason.decode(result)
        chunks = data["chunks"]
        assert is_list(chunks)
        assert length(chunks) > 0

        # All BEAM files have these standard chunks
        chunk_ids = Enum.map(chunks, & &1["id"])
        assert "AtU8" in chunk_ids or "Atom" in chunk_ids
        assert "Code" in chunk_ids
        assert "ExpT" in chunk_ids
      end
    end
  end

  describe "disasm command on stdlib" do
    test "disassembles Enum without unknown opcodes" do
      path = Helpers.beam_path(Enum)
      {:ok, result} = Disasm.extract(path)

      for func <- result.functions,
          {category, _op, _args} <- func.instructions do
        refute category == :unknown,
               "Found unknown opcode in Enum: #{inspect(func.name)}/#{func.arity}"
      end
    end

    test "disassembles :lists without unknown opcodes" do
      path = Helpers.beam_path(:lists)
      {:ok, result} = Disasm.extract(path)

      for func <- result.functions,
          {category, _op, _args} <- func.instructions do
        refute category == :unknown,
               "Found unknown opcode in :lists: #{inspect(func.name)}/#{func.arity}"
      end
    end

    test "disassembles GenServer with all opcode categories" do
      path = Helpers.beam_path(GenServer)
      {:ok, result} = Disasm.extract(path)

      categories =
        result.functions
        |> Enum.flat_map(& &1.instructions)
        |> Enum.map(fn {cat, _, _} -> cat end)
        |> Enum.uniq()

      # GenServer should have a variety of instruction types
      assert :call in categories
      assert :data in categories
      assert :control in categories
    end

    test "disasm text output is valid for Enum.map/2" do
      path = Helpers.beam_path(Enum)
      {:ok, output} = Disasm.run(path, function: "map/2", format: :text)

      assert is_binary(output)
      assert output =~ "function map/2"
      assert output =~ "label"
    end

    test "disasm JSON output is valid for :lists.reverse/1" do
      path = Helpers.beam_path(:lists)
      {:ok, output} = Disasm.run(path, function: "reverse/1", format: :json)

      assert {:ok, data} = Jason.decode(output)
      assert is_map(data)
      assert Map.has_key?(data, "functions")

      # Should have the reverse function
      func_names = Enum.map(data["functions"], & &1["name"])
      assert "reverse" in func_names
    end

    @tag :slow
    test "disassembles large module :ets without crashing" do
      path = Helpers.beam_path(:ets)
      {:ok, output} = Disasm.run(path, format: :text)

      assert is_binary(output)
      # :ets has many functions
      assert String.length(output) > 5_000
    end
  end

  describe "callgraph command on stdlib" do
    test "builds callgraph for Enum" do
      path = Helpers.beam_path(Enum)
      {:ok, output} = Callgraph.run(path, format: :json)

      assert {:ok, graph} = Jason.decode(output)
      assert is_map(graph)
      assert Map.has_key?(graph, "nodes")
      assert Map.has_key?(graph, "edges")
      assert length(graph["nodes"]) > 0
    end

    test "DOT output is valid syntax for GenServer" do
      path = Helpers.beam_path(GenServer)
      {:ok, output} = Callgraph.run(path, format: :dot)

      assert is_binary(output)
      assert output =~ ~r/^digraph/
      assert output =~ ~r/\}$/
    end
  end

  describe "edge cases in real modules" do
    test "handles :ets with binary matching opcodes" do
      path = Helpers.beam_path(:ets)
      {:ok, output} = Disasm.run(path, format: :text)

      assert is_binary(output)
      refute output =~ "Error:"
    end

    test "handles :gen_server with receive/message opcodes" do
      path = Helpers.beam_path(:gen_server)
      {:ok, result} = Disasm.extract(path)

      categories =
        result.functions
        |> Enum.flat_map(& &1.instructions)
        |> Enum.map(fn {cat, _, _} -> cat end)
        |> Enum.uniq()

      # gen_server uses message passing
      assert :message in categories or :control in categories
    end
  end
end
