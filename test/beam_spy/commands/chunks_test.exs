defmodule BeamSpy.Commands.ChunksTest do
  use ExUnit.Case, async: true

  alias BeamSpy.Commands.Chunks

  @test_beam_path :code.which(:lists) |> to_string()

  describe "extract/2" do
    test "extracts chunks from beam file" do
      assert {:ok, data} = Chunks.extract(@test_beam_path)
      assert is_map(data)
      assert Map.has_key?(data, :chunks)
      assert is_list(data.chunks)
      assert length(data.chunks) > 0
    end

    test "chunks have correct structure" do
      {:ok, data} = Chunks.extract(@test_beam_path)

      for chunk <- data.chunks do
        assert Map.has_key?(chunk, :id)
        assert Map.has_key?(chunk, :size)
        assert is_integer(chunk.size) and chunk.size >= 0
      end
    end

    test "includes standard chunks" do
      {:ok, data} = Chunks.extract(@test_beam_path)
      ids = Enum.map(data.chunks, & &1.id) |> Enum.map(&to_string/1)

      # Every BEAM file should have these
      # Atom table
      assert Enum.any?(ids, &(&1 =~ "At"))
      assert Enum.any?(ids, &(&1 == "Code"))
      assert Enum.any?(ids, &(&1 == "ExpT"))
      assert Enum.any?(ids, &(&1 == "ImpT"))
    end
  end

  describe "run/2 text format" do
    test "renders table with chunks" do
      {:ok, output} = Chunks.run(@test_beam_path, format: :text)
      assert is_binary(output)
      assert output =~ "Code"
    end

    test "shows total size" do
      {:ok, output} = Chunks.run(@test_beam_path, format: :text)
      assert output =~ "Total" or output =~ "total" or String.contains?(output, "bytes")
    end
  end

  describe "run/2 json format" do
    test "outputs valid JSON" do
      {:ok, output} = Chunks.run(@test_beam_path, format: :json)
      {:ok, decoded} = Jason.decode(output)

      assert Map.has_key?(decoded, "chunks")
      assert is_list(decoded["chunks"])
    end

    test "chunks have id and size in JSON" do
      {:ok, output} = Chunks.run(@test_beam_path, format: :json)
      {:ok, decoded} = Jason.decode(output)

      for chunk <- decoded["chunks"] do
        assert Map.has_key?(chunk, "id")
        assert Map.has_key?(chunk, "size")
      end
    end
  end

  describe "raw dump" do
    test "dumps raw bytes for chunk" do
      {:ok, output} = Chunks.run(@test_beam_path, raw: "Code")

      # Should be hex dump format
      assert output =~ ~r/[0-9a-f]{2}/i
    end

    test "returns error for non-existent chunk" do
      {:error, output} = Chunks.run(@test_beam_path, raw: "XXXX")
      assert output =~ "not found" or output =~ "error" or output =~ "Error"
    end
  end

  describe "snapshot tests" do
    @tag :snapshot
    test "extract returns standard BEAM chunks" do
      {:ok, data} = Chunks.extract(@test_beam_path)

      assert is_map(data)
      assert is_list(data.chunks)

      ids = Enum.map(data.chunks, & &1.id)

      # Standard chunks every BEAM file has
      assert "Code" in ids
      assert "ExpT" in ids
      assert "ImpT" in ids
      # Atom table (AtU8 for UTF-8 atoms, or Atom for legacy)
      assert Enum.any?(ids, &(&1 in ["AtU8", "Atom"]))
    end

    @tag :snapshot
    test "JSON output structure is stable" do
      {:ok, output} = Chunks.run(@test_beam_path, format: :json)
      {:ok, decoded} = Jason.decode(output)

      assert Map.has_key?(decoded, "chunks")
      assert is_list(decoded["chunks"])

      for chunk <- decoded["chunks"] do
        assert Map.has_key?(chunk, "id")
        assert Map.has_key?(chunk, "size")
        assert is_binary(chunk["id"])
        assert is_integer(chunk["size"])
      end
    end

    @tag :snapshot
    test "text output shows chunk table" do
      {:ok, output} = Chunks.run(@test_beam_path, format: :text)

      assert is_binary(output)
      assert output =~ "Code"
      assert output =~ "ExpT"
    end
  end
end
