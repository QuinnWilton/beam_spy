defmodule BeamSpy.Commands.InfoTest do
  use ExUnit.Case, async: true

  alias BeamSpy.Commands.Info

  @test_beam_path :code.which(:lists) |> to_string()

  describe "extract/2" do
    test "extracts info from beam file" do
      assert {:ok, info} = Info.extract(@test_beam_path)
      assert is_map(info)
    end

    test "returns error for non-existent file" do
      assert {:error, {:file_error, :enoent}} = Info.extract("/nonexistent/file.beam")
    end

    test "returns error for invalid beam file" do
      tmp_path = Path.join(System.tmp_dir!(), "not_a_beam_info.beam")
      File.write!(tmp_path, "not a beam file")

      try do
        assert {:error, :not_a_beam_file} = Info.extract(tmp_path)
      after
        File.rm(tmp_path)
      end
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

    test "info has compile time when available" do
      {:ok, info} = Info.extract(@test_beam_path)
      # compile_time may be nil or a string
      assert is_nil(info.compile_time) or is_binary(info.compile_time)
    end

    test "info has otp version when available" do
      {:ok, info} = Info.extract(@test_beam_path)
      # otp_version may be nil or a string
      assert is_nil(info.otp_version) or is_binary(info.otp_version)
    end

    test "info has md5 hash" do
      {:ok, info} = Info.extract(@test_beam_path)
      assert is_binary(info.md5)
      # MD5 as hex is 32 characters
      assert String.length(info.md5) == 32
    end
  end

  describe "run/2 text format" do
    test "outputs key-value pairs" do
      {:ok, output} = Info.run(@test_beam_path, format: :text)
      assert is_binary(output)
      assert output =~ "Module"
      assert output =~ "lists"
    end

    test "returns error message for invalid file" do
      {:error, msg} = Info.run("/nonexistent/file.beam", format: :text)
      assert is_binary(msg)
      assert msg =~ "Error:"
    end

    test "includes size information" do
      {:ok, output} = Info.run(@test_beam_path, format: :text)
      assert output =~ "Size" or output =~ "bytes"
    end
  end

  describe "run/2 json format" do
    test "outputs valid JSON" do
      {:ok, output} = Info.run(@test_beam_path, format: :json)
      {:ok, decoded} = Jason.decode(output)
      assert is_map(decoded)
    end

    test "JSON has expected fields" do
      {:ok, output} = Info.run(@test_beam_path, format: :json)
      {:ok, decoded} = Jason.decode(output)

      assert decoded["module"] == "lists"
      assert is_integer(decoded["size_bytes"])
      assert is_integer(decoded["export_count"])
    end

    test "JSON has all expected keys" do
      {:ok, output} = Info.run(@test_beam_path, format: :json)
      {:ok, decoded} = Jason.decode(output)

      expected_keys = ~w(module md5 size_bytes chunk_count export_count import_count atom_count)

      for key <- expected_keys do
        assert Map.has_key?(decoded, key), "Missing key: #{key}"
      end
    end

    test "returns error message for invalid file" do
      {:error, msg} = Info.run("/nonexistent/file.beam", format: :json)
      assert is_binary(msg)
      assert msg =~ "Error:"
    end
  end

  describe "Elixir modules" do
    @elixir_beam_path :code.which(Enum) |> to_string()

    test "extracts info from Elixir module" do
      {:ok, info} = Info.extract(@elixir_beam_path)
      assert info.module == Enum
    end

    test "Elixir module has file field" do
      {:ok, info} = Info.extract(@elixir_beam_path)
      # Elixir modules have file as charlist, which gets converted to nil or string
      # The file field can be nil, a binary, or a charlist depending on the module
      assert is_nil(info.file) or is_binary(info.file) or is_list(info.file)
    end

    test "text output includes all sections" do
      {:ok, output} = Info.run(@elixir_beam_path, format: :text)
      assert output =~ "Module"
      assert output =~ "MD5"
      assert output =~ "Exports"
      assert output =~ "Imports"
      assert output =~ "Atoms"
    end

    test "chunk count matches chunks" do
      {:ok, info} = Info.extract(@elixir_beam_path)
      assert is_integer(info.chunk_count)
      assert info.chunk_count > 0
    end
  end

  describe "default format" do
    test "defaults to text format" do
      {:ok, output} = Info.run(@test_beam_path)
      # Default format is text, which has "Module:" key
      assert output =~ "Module"
      # JSON would have braces
      refute output =~ "{"
    end
  end

  describe "Erlang modules" do
    @maps_beam_path :code.which(:maps) |> to_string()

    test "extracts info from maps module" do
      {:ok, info} = Info.extract(@maps_beam_path)
      assert info.module == :maps
    end

    test "maps module has exports" do
      {:ok, info} = Info.extract(@maps_beam_path)
      assert info.export_count > 0
    end
  end

  describe "format_size helper" do
    test "formats size correctly in text output" do
      {:ok, output} = Info.run(@test_beam_path, format: :text)
      # Should have size with "bytes" suffix
      assert output =~ "bytes"
    end
  end

  describe "snapshot tests" do
    @tag :snapshot
    test "extract returns complete info map" do
      {:ok, info} = Info.extract(@test_beam_path)

      assert info.module == :lists
      assert is_integer(info.size_bytes) and info.size_bytes > 0
      assert is_integer(info.export_count) and info.export_count > 20
      assert is_integer(info.import_count) and info.import_count >= 0
      assert is_integer(info.atom_count) and info.atom_count > 50
    end

    @tag :snapshot
    test "JSON output structure is stable" do
      {:ok, output} = Info.run(@test_beam_path, format: :json)
      {:ok, decoded} = Jason.decode(output)

      assert decoded["module"] == "lists"
      assert is_integer(decoded["size_bytes"])
      assert is_integer(decoded["export_count"])
      assert is_integer(decoded["import_count"])
      assert is_integer(decoded["atom_count"])
    end

    @tag :snapshot
    test "text output contains all info fields" do
      {:ok, output} = Info.run(@test_beam_path, format: :text)

      assert output =~ "Module"
      assert output =~ "lists"
      assert output =~ ~r/[Ss]ize/
      assert output =~ ~r/[Ee]xport/
    end
  end
end
