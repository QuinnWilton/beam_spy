defmodule BeamSpy.BinaryInputTest do
  use ExUnit.Case, async: true

  alias BeamSpy.BeamFile
  alias BeamSpy.Resolver

  @moduledoc """
  The access form must never change the answer: every public reader has to
  yield identical results whether it is given a `.beam` path, the same path
  without an extension, or the file's raw bytes. The path-reading happens in
  `BeamFile.load/1` precisely because `:beam_lib` rewrites any filename it
  receives to end in `".beam"`, which breaks extensionless temp files.
  """

  @fixture Path.expand("../fixtures/beam/with_literals.beam", __DIR__)

  # Every top-level reader that takes a single beam input. `BeamSpy.types/1`
  # and `BeamSpy.docs/1` may legitimately error on chunk-less subjects; the
  # invariant under test is result *equality* across access forms.
  defp readers do
    [
      atoms: &BeamSpy.atoms/1,
      exports: &BeamSpy.exports/1,
      imports: &BeamSpy.imports/1,
      info: &BeamSpy.info/1,
      chunks: &BeamSpy.chunks/1,
      disasm: &BeamSpy.disasm/1,
      literals: &BeamSpy.literals/1,
      docs: &BeamSpy.docs/1,
      types: &BeamSpy.types/1,
      callgraph: &BeamSpy.callgraph/1
    ]
  end

  defp subjects do
    [@fixture, to_string(:code.which(:lists))]
  end

  defp extensionless_copy(path) do
    copy = Path.join(System.tmp_dir!(), "beam_spy_noext_#{System.unique_integer([:positive])}")
    File.cp!(path, copy)
    on_exit(fn -> File.rm(copy) end)
    copy
  end

  describe "raw beam data input" do
    test "every reader yields the same result as the path form" do
      for path <- subjects(), {name, reader} <- readers() do
        data = File.read!(path)

        assert reader.(data) == reader.(path),
               "#{name} disagrees between raw data and path for #{path}"
      end
    end

    test "gzip-compressed beam data is accepted (beam_lib gunzips it)" do
      data = File.read!(@fixture)
      gzipped = :zlib.gzip(data)

      assert BeamSpy.atoms(gzipped) == BeamSpy.atoms(@fixture)
    end

    test "BeamFile.info reports no file for raw data" do
      data = File.read!(@fixture)

      assert {:ok, info} = BeamFile.info(data)
      assert info.file == nil

      assert {:ok, %{file: @fixture}} = BeamFile.info(@fixture)
    end
  end

  describe "extensionless paths" do
    test "every reader works on a path without the .beam extension" do
      for path <- subjects() do
        copy = extensionless_copy(path)

        for {name, reader} <- readers() do
          assert reader.(copy) == reader.(path),
                 "#{name} disagrees between extensionless copy and #{path}"
        end
      end
    end

    test "the Type table reads from an extensionless tmp file and from raw data" do
      source = """
      defmodule BeamSpyBinaryInputProbe do
        def pack(n) when is_integer(n) and n >= 0 and n < 1024, do: <<n::10>>
      end
      """

      [{module, beam} | _] = Code.compile_string(source, "nofile")
      :code.purge(module)
      :code.delete(module)

      copy = Path.join(System.tmp_dir!(), "beam_spy_type_#{System.unique_integer([:positive])}")
      File.write!(copy, beam)
      on_exit(fn -> File.rm(copy) end)

      assert {:ok, table} = BeamSpy.types(copy)
      assert table.count == length(table.entries)
      assert BeamSpy.types(beam) == BeamSpy.types(copy)
    end
  end

  describe "BeamFile.load/1" do
    test "raw beam data passes through untouched" do
      data = File.read!(@fixture)
      assert {:ok, ^data} = BeamFile.load(data)
    end

    test "a missing path is a file error, whatever its extension" do
      assert {:error, {:file_error, :enoent}} = BeamFile.load("/nonexistent/no_such.beam")
      assert {:error, {:file_error, :enoent}} = BeamFile.load("/nonexistent/no_such_file")
    end

    test "a non-beam file loads but fails downstream as not_a_beam_file" do
      path = Path.join(System.tmp_dir!(), "beam_spy_junk_#{System.unique_integer([:positive])}")
      File.write!(path, "plain text, no IFF header")
      on_exit(fn -> File.rm(path) end)

      assert {:ok, "plain text" <> _} = BeamFile.load(path)
      assert {:error, :not_a_beam_file} = BeamFile.read_all_chunks(path)
    end
  end

  describe "Resolver.resolve/2" do
    test "raw beam data needs no resolution" do
      data = File.read!(@fixture)
      assert {:ok, ^data} = Resolver.resolve(data)
    end
  end
end
