defmodule BeamSpy.Commands.InfoTest do
  use ExUnit.Case, async: true

  alias BeamSpy.Commands.Info

  @test_beam_path :code.which(:lists) |> to_string()

  describe "extract/2" do
    test "extracts info from beam file" do
      assert {:ok, info} = Info.extract(@test_beam_path)
      assert is_map(info)
    end

    test "info contains required fields" do
      {:ok, info} = Info.extract(@test_beam_path)

      assert Map.has_key?(info, :module)
      assert Map.has_key?(info, :size_bytes)
      assert Map.has_key?(info, :export_count)
      assert Map.has_key?(info, :import_count)
      assert Map.has_key?(info, :atom_count)
    end

    test "module field matches actual module" do
      {:ok, info} = Info.extract(@test_beam_path)
      assert info.module == :lists
    end

    test "size_bytes is positive" do
      {:ok, info} = Info.extract(@test_beam_path)
      assert is_integer(info.size_bytes)
      assert info.size_bytes > 0
    end

    test "counts are non-negative integers" do
      {:ok, info} = Info.extract(@test_beam_path)

      assert is_integer(info.export_count) and info.export_count >= 0
      assert is_integer(info.import_count) and info.import_count >= 0
      assert is_integer(info.atom_count) and info.atom_count >= 0
    end
  end

  describe "run/2 text format" do
    test "outputs key-value pairs" do
      output = Info.run(@test_beam_path, format: :text)
      assert is_binary(output)
      assert output =~ "Module"
      assert output =~ "lists"
    end

    test "includes size information" do
      output = Info.run(@test_beam_path, format: :text)
      assert output =~ "Size" or output =~ "bytes"
    end
  end

  describe "run/2 json format" do
    test "outputs valid JSON" do
      output = Info.run(@test_beam_path, format: :json)
      {:ok, decoded} = Jason.decode(output)
      assert is_map(decoded)
    end

    test "JSON has expected fields" do
      output = Info.run(@test_beam_path, format: :json)
      {:ok, decoded} = Jason.decode(output)

      assert decoded["module"] == "lists"
      assert is_integer(decoded["size_bytes"])
      assert is_integer(decoded["export_count"])
    end
  end
end
