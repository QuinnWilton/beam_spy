defmodule BeamSpy.CLITest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias BeamSpy.CLI

  @test_beam_path :code.which(:lists) |> to_string()

  describe "main/1" do
    test "shows help with --help" do
      # Optimus prints help directly to stdout before returning :help
      # We just verify it returns 0 and doesn't crash
      assert CLI.main(["--help"]) == 0
    end

    test "shows version with --version" do
      # Optimus prints version directly to stdout before returning :version
      assert CLI.main(["--version"]) == 0
    end

    test "lists themes with --list-themes" do
      output = capture_io(fn ->
        assert CLI.main(["--list-themes"]) == 0
      end)

      assert output =~ "default"
      assert output =~ "monokai"
    end

    test "shows usage without arguments" do
      output = capture_io(fn ->
        assert CLI.main([]) == 1
      end)

      assert output =~ "Usage:"
    end
  end

  describe "atoms command" do
    test "extracts atoms from beam file" do
      output = capture_io(fn ->
        assert CLI.main(["atoms", @test_beam_path]) == 0
      end)

      assert output =~ "lists"
    end

    test "outputs JSON format" do
      output = capture_io(fn ->
        assert CLI.main(["atoms", @test_beam_path, "--format=json"]) == 0
      end)

      {:ok, decoded} = Jason.decode(output)
      assert is_list(decoded)
      assert "lists" in decoded
    end
  end

  describe "exports command" do
    test "lists exports from beam file" do
      output = capture_io(fn ->
        assert CLI.main(["exports", @test_beam_path]) == 0
      end)

      assert output =~ "map"
    end

    test "plain format outputs one per line" do
      output = capture_io(fn ->
        assert CLI.main(["exports", @test_beam_path, "--plain"]) == 0
      end)

      lines = String.split(output, "\n", trim: true)

      for line <- lines do
        assert line =~ ~r/^\w+\/\d+$/
      end
    end
  end

  describe "imports command" do
    test "lists imports from beam file" do
      output = capture_io(fn ->
        assert CLI.main(["imports", @test_beam_path]) == 0
      end)

      assert output =~ "erlang"
    end
  end

  describe "info command" do
    test "shows module info" do
      output = capture_io(fn ->
        assert CLI.main(["info", @test_beam_path]) == 0
      end)

      assert output =~ "Module"
      assert output =~ "lists"
    end

    test "JSON format" do
      output = capture_io(fn ->
        assert CLI.main(["info", @test_beam_path, "--format=json"]) == 0
      end)

      {:ok, decoded} = Jason.decode(output)
      assert decoded["module"] == "lists"
    end
  end

  describe "chunks command" do
    test "lists chunks" do
      output = capture_io(fn ->
        assert CLI.main(["chunks", @test_beam_path]) == 0
      end)

      assert output =~ "AtU8" or output =~ "Atom"
      assert output =~ "Code"
    end
  end

  describe "disasm command" do
    test "disassembles module" do
      output = capture_io(fn ->
        assert CLI.main(["disasm", @test_beam_path, "--function=reverse/1"]) == 0
      end)

      assert output =~ "function reverse/1"
      assert output =~ "label"
    end

    test "JSON format" do
      output = capture_io(fn ->
        assert CLI.main(["disasm", @test_beam_path, "--function=reverse/1", "--format=json"]) == 0
      end)

      {:ok, decoded} = Jason.decode(output)
      assert decoded["module"] == "lists"
      assert length(decoded["functions"]) == 1
    end
  end

  describe "error handling" do
    test "reports error for nonexistent file" do
      output = capture_io(:stderr, fn ->
        assert CLI.main(["info", "/nonexistent/file.beam"]) == {:error, 1}
      end)

      assert output =~ "Could not find"
    end

    test "reports error for invalid command" do
      output = capture_io(:stderr, fn ->
        CLI.main(["invalid_command", @test_beam_path])
      end)

      # Optimus will report the error
      assert output =~ "invalid" or output =~ "Unknown" or output =~ "error"
    end
  end
end
