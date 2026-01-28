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
      output = Exports.run(@test_beam_path, format: :text)
      assert is_binary(output)
      assert output =~ "map"
    end

    test "plain format outputs function/arity" do
      output = Exports.run(@test_beam_path, format: :text, plain: true)
      lines = String.split(output, "\n", trim: true)

      for line <- lines do
        assert line =~ ~r/^\w+\/\d+$/
      end
    end
  end

  describe "run/2 json format" do
    test "outputs valid JSON" do
      output = Exports.run(@test_beam_path, format: :json)
      {:ok, decoded} = Jason.decode(output)
      assert is_list(decoded)

      for export <- decoded do
        assert Map.has_key?(export, "name")
        assert Map.has_key?(export, "arity")
      end
    end
  end
end
