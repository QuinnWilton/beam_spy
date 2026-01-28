defmodule BeamSpy.Commands.ImportsTest do
  use ExUnit.Case, async: true

  alias BeamSpy.Commands.Imports

  @test_beam_path :code.which(:lists) |> to_string()

  describe "extract/2" do
    test "extracts imports from beam file" do
      assert {:ok, imports} = Imports.extract(@test_beam_path)
      assert is_list(imports)
      assert length(imports) > 0
    end

    test "imports have correct structure" do
      {:ok, imports} = Imports.extract(@test_beam_path)

      for {mod, name, arity} <- imports do
        assert is_atom(mod)
        assert is_atom(name)
        assert is_integer(arity) and arity >= 0
      end
    end

    test "includes erlang module calls" do
      {:ok, imports} = Imports.extract(@test_beam_path)
      modules = Enum.map(imports, fn {m, _, _} -> m end) |> Enum.uniq()
      assert :erlang in modules
    end

    test "filters imports" do
      {:ok, imports} = Imports.extract(@test_beam_path, filter: "length")

      for {_mod, name, _arity} <- imports do
        assert Atom.to_string(name) =~ ~r/length/i
      end
    end
  end

  describe "run/2 text format" do
    test "renders table with columns" do
      {:ok, output} = Imports.run(@test_beam_path, format: :text)
      assert is_binary(output)
      assert output =~ "Module" or output =~ "erlang"
    end

    test "grouped format groups by module" do
      {:ok, output} = Imports.run(@test_beam_path, format: :text, group: true)
      assert output =~ "erlang"
    end
  end

  describe "run/2 json format" do
    test "outputs valid JSON" do
      {:ok, output} = Imports.run(@test_beam_path, format: :json)
      {:ok, decoded} = Jason.decode(output)
      assert is_list(decoded)

      for import <- decoded do
        assert Map.has_key?(import, "module")
        assert Map.has_key?(import, "name")
        assert Map.has_key?(import, "arity")
      end
    end
  end

  describe "snapshot tests" do
    @tag :snapshot
    test "extract returns list of imports with correct structure" do
      {:ok, imports} = Imports.extract(@test_beam_path)

      assert is_list(imports)
      assert length(imports) > 0

      modules = Enum.map(imports, fn {m, _, _} -> m end) |> Enum.uniq()
      assert :erlang in modules
    end

    @tag :snapshot
    test "JSON output structure is stable" do
      {:ok, output} = Imports.run(@test_beam_path, format: :json)
      {:ok, decoded} = Jason.decode(output)

      assert is_list(decoded)
      modules = Enum.map(decoded, & &1["module"]) |> Enum.uniq()

      assert "erlang" in modules
    end

    @tag :snapshot
    test "text output contains module names" do
      {:ok, output} = Imports.run(@test_beam_path, format: :text)

      assert is_binary(output)
      assert output =~ "erlang"
    end
  end
end
