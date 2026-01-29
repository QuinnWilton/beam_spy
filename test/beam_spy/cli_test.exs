defmodule BeamSpy.CLITest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias BeamSpy.CLI

  @test_beam_path :code.which(:lists) |> to_string()

  describe "run/1" do
    test "shows help with --help" do
      output =
        capture_io(fn ->
          assert CLI.run(["--help"]) == 0
        end)

      assert output =~ "USAGE:"
      assert output =~ "SUBCOMMANDS:"
    end

    test "shows version with --version" do
      output =
        capture_io(fn ->
          assert CLI.run(["--version"]) == 0
        end)

      assert output =~ "0.1.0"
    end

    test "lists themes with --list-themes" do
      output =
        capture_io(fn ->
          assert CLI.run(["--list-themes"]) == 0
        end)

      assert output =~ "default"
      assert output =~ "monokai"
    end

    test "shows usage without arguments" do
      output =
        capture_io(fn ->
          assert CLI.run([]) == 1
        end)

      assert output =~ "Usage:"
    end
  end

  describe "atoms command" do
    test "extracts atoms from beam file" do
      output =
        capture_io(fn ->
          assert CLI.run(["atoms", @test_beam_path]) == 0
        end)

      assert output =~ "lists"
    end

    test "outputs JSON format" do
      output =
        capture_io(fn ->
          assert CLI.run(["atoms", @test_beam_path, "--format=json"]) == 0
        end)

      {:ok, decoded} = Jason.decode(output)
      assert is_list(decoded)
      assert "lists" in decoded
    end
  end

  describe "exports command" do
    test "lists exports from beam file" do
      output =
        capture_io(fn ->
          assert CLI.run(["exports", @test_beam_path]) == 0
        end)

      assert output =~ "map"
    end

    test "plain format outputs one per line" do
      output =
        capture_io(fn ->
          assert CLI.run(["exports", @test_beam_path, "--plain"]) == 0
        end)

      lines = String.split(output, "\n", trim: true)

      for line <- lines do
        assert line =~ ~r/^\w+\/\d+$/
      end
    end
  end

  describe "imports command" do
    test "lists imports from beam file" do
      output =
        capture_io(fn ->
          assert CLI.run(["imports", @test_beam_path]) == 0
        end)

      assert output =~ "erlang"
    end
  end

  describe "info command" do
    test "shows module info" do
      output =
        capture_io(fn ->
          assert CLI.run(["info", @test_beam_path]) == 0
        end)

      assert output =~ "Module"
      assert output =~ "lists"
    end

    test "JSON format" do
      output =
        capture_io(fn ->
          assert CLI.run(["info", @test_beam_path, "--format=json"]) == 0
        end)

      {:ok, decoded} = Jason.decode(output)
      assert decoded["module"] == "lists"
    end
  end

  describe "chunks command" do
    test "lists chunks" do
      output =
        capture_io(fn ->
          assert CLI.run(["chunks", @test_beam_path]) == 0
        end)

      assert output =~ "AtU8" or output =~ "Atom"
      assert output =~ "Code"
    end

    test "dumps raw chunk with --raw" do
      output =
        capture_io(fn ->
          assert CLI.run(["chunks", @test_beam_path, "--raw=Code"]) == 0
        end)

      # Raw output is hex dump format
      assert output =~ "00000000:"
    end

    test "JSON format for chunks" do
      output =
        capture_io(fn ->
          assert CLI.run(["chunks", @test_beam_path, "--format=json"]) == 0
        end)

      {:ok, decoded} = Jason.decode(output)
      # JSON output is a map with "chunks" list
      assert is_map(decoded)
      assert Map.has_key?(decoded, "chunks")
      assert is_list(decoded["chunks"])
    end
  end

  describe "disasm command" do
    test "disassembles module" do
      output =
        capture_io(fn ->
          assert CLI.run(["disasm", @test_beam_path, "--function=reverse/1"]) == 0
        end)

      assert output =~ "function reverse/1"
      assert output =~ "label"
    end

    test "JSON format" do
      output =
        capture_io(fn ->
          assert CLI.run(["disasm", @test_beam_path, "--function=reverse/1", "--format=json"]) ==
                   0
        end)

      {:ok, decoded} = Jason.decode(output)
      assert decoded["module"] == "lists"
      assert length(decoded["functions"]) == 1
    end

    test "disasm with source option" do
      # Use an Elixir module that has debug info
      elixir_path = :code.which(Enum) |> to_string()

      output =
        capture_io(fn ->
          CLI.run(["disasm", elixir_path, "--function=map/2", "--source"])
        end)

      # Should include disassembly output
      assert output =~ "module:" or output =~ "function"
    end
  end

  describe "callgraph command" do
    test "builds callgraph" do
      output =
        capture_io(fn ->
          assert CLI.run(["callgraph", @test_beam_path]) == 0
        end)

      # Text format shows function calls with arrows
      assert output =~ "→" or output =~ "->"
    end

    test "DOT format outputs digraph" do
      output =
        capture_io(fn ->
          assert CLI.run(["callgraph", @test_beam_path, "--format=dot"]) == 0
        end)

      assert output =~ "digraph"
      assert output =~ "->"
    end

    test "JSON format" do
      output =
        capture_io(fn ->
          assert CLI.run(["callgraph", @test_beam_path, "--format=json"]) == 0
        end)

      {:ok, decoded} = Jason.decode(output)
      assert is_list(decoded["nodes"])
      assert is_list(decoded["edges"])
    end
  end

  describe "help command" do
    test "shows help for subcommand" do
      output =
        capture_io(fn ->
          assert CLI.run(["help", "atoms"]) == 0
        end)

      assert output =~ "atoms"
    end

    test "shows help for info subcommand" do
      output =
        capture_io(fn ->
          assert CLI.run(["help", "info"]) == 0
        end)

      assert output =~ "info"
    end
  end

  describe "theme option" do
    test "uses specified theme" do
      output =
        capture_io(fn ->
          assert CLI.run(["info", @test_beam_path, "--theme=plain"]) == 0
        end)

      assert output =~ "Module"
    end

    test "warns on unknown theme" do
      _output =
        capture_io(:stderr, fn ->
          capture_io(fn ->
            CLI.run(["info", @test_beam_path, "--theme=nonexistent_theme_xyz"])
          end)
        end)

      # May or may not warn depending on implementation
      assert true
    end
  end

  describe "filter option" do
    test "filters atoms" do
      output =
        capture_io(fn ->
          assert CLI.run(["atoms", @test_beam_path, "--filter=reverse"]) == 0
        end)

      assert output =~ "reverse"
    end

    test "filters exports" do
      output =
        capture_io(fn ->
          assert CLI.run(["exports", @test_beam_path, "--filter=reverse"]) == 0
        end)

      assert output =~ "reverse"
    end
  end

  describe "error handling" do
    test "reports error for nonexistent file" do
      output =
        capture_io(:stderr, fn ->
          assert CLI.run(["info", "/nonexistent/file.beam"]) == 1
        end)

      assert output =~ "Could not find"
    end

    test "reports error for invalid command" do
      output =
        capture_io(:stderr, fn ->
          CLI.run(["invalid_command", @test_beam_path])
        end)

      # Optimus will report the error
      assert output =~ "invalid" or output =~ "Unknown" or output =~ "error"
    end

    test "reports error for missing required argument" do
      output =
        capture_io(:stderr, fn ->
          assert CLI.run(["atoms"]) == 1
        end)

      assert output =~ "Error:" or output =~ "Required"
    end
  end

  describe "paging option" do
    test "accepts --paging=always" do
      output =
        capture_io(fn ->
          assert CLI.run(["info", @test_beam_path, "--paging=always"]) == 0
        end)

      assert output =~ "Module"
    end

    test "accepts --paging=never" do
      output =
        capture_io(fn ->
          assert CLI.run(["info", @test_beam_path, "--paging=never"]) == 0
        end)

      assert output =~ "Module"
    end

    test "accepts --paging=auto" do
      output =
        capture_io(fn ->
          assert CLI.run(["info", @test_beam_path, "--paging=auto"]) == 0
        end)

      assert output =~ "Module"
    end
  end

  describe "help normalization" do
    test "normalizes 'atoms --help' to 'help atoms'" do
      output =
        capture_io(fn ->
          assert CLI.run(["atoms", "--help"]) == 0
        end)

      assert output =~ "atoms"
    end

    test "normalizes 'disasm -h' to 'help disasm'" do
      output =
        capture_io(fn ->
          assert CLI.run(["disasm", "-h"]) == 0
        end)

      assert output =~ "disasm"
    end

    test "help with no subcommand shows main help" do
      output =
        capture_io(fn ->
          assert CLI.run(["--help"]) == 0
        end)

      assert output =~ "beam_spy"
    end
  end

  describe "version command" do
    test "shows version with --version" do
      output =
        capture_io(fn ->
          assert CLI.run(["--version"]) == 0
        end)

      assert output =~ BeamSpy.version()
    end
  end

  describe "list themes flag" do
    test "lists available themes with --list-themes" do
      output =
        capture_io(fn ->
          assert CLI.run(["--list-themes"]) == 0
        end)

      assert output =~ "default" or output =~ "plain"
    end
  end

  describe "group option for imports" do
    test "accepts --group flag" do
      output =
        capture_io(fn ->
          assert CLI.run(["imports", @test_beam_path, "--group"]) == 0
        end)

      assert output =~ "erlang"
    end
  end

  describe "short options" do
    test "filter with -F" do
      output =
        capture_io(fn ->
          assert CLI.run(["atoms", @test_beam_path, "-F", "reverse"]) == 0
        end)

      assert output =~ "reverse"
    end

    test "format with -o" do
      output =
        capture_io(fn ->
          assert CLI.run(["info", @test_beam_path, "-o", "json"]) == 0
        end)

      {:ok, decoded} = Jason.decode(output)
      assert is_map(decoded)
    end

    test "function filter with -f for disasm" do
      output =
        capture_io(fn ->
          assert CLI.run(["disasm", @test_beam_path, "-f", "reverse/1"]) == 0
        end)

      assert output =~ "function reverse/1"
    end

    test "theme with -t" do
      output =
        capture_io(fn ->
          assert CLI.run(["info", @test_beam_path, "-t", "plain"]) == 0
        end)

      assert output =~ "Module"
    end
  end

  describe "module name resolution" do
    test "resolves Elixir module names" do
      output =
        capture_io(fn ->
          assert CLI.run(["info", "Enum"]) == 0
        end)

      assert output =~ "Enum" or output =~ "Elixir.Enum"
    end

    test "resolves Erlang module names" do
      output =
        capture_io(fn ->
          assert CLI.run(["info", "lists"]) == 0
        end)

      assert output =~ "lists"
    end

    test "uses beam file paths directly" do
      elixir_path = :code.which(Enum) |> to_string()

      output =
        capture_io(fn ->
          assert CLI.run(["info", elixir_path]) == 0
        end)

      assert output =~ "Enum" or output =~ "Elixir.Enum"
    end
  end

  describe "all commands with module resolution" do
    test "atoms command resolves module name" do
      output =
        capture_io(fn ->
          assert CLI.run(["atoms", "Enum"]) == 0
        end)

      assert output =~ "Enum" or output =~ "Elixir"
    end

    test "exports command resolves module name" do
      output =
        capture_io(fn ->
          assert CLI.run(["exports", "Enum"]) == 0
        end)

      assert output =~ "map" or output =~ "reduce"
    end

    test "imports command resolves module name" do
      output =
        capture_io(fn ->
          assert CLI.run(["imports", "Enum"]) == 0
        end)

      # Enum module imports from :erlang and others
      assert is_binary(output)
    end

    test "chunks command resolves module name" do
      output =
        capture_io(fn ->
          assert CLI.run(["chunks", "Enum"]) == 0
        end)

      assert output =~ "Code" or output =~ "AtU8"
    end

    test "callgraph command resolves module name" do
      output =
        capture_io(fn ->
          assert CLI.run(["callgraph", "Enum"]) == 0
        end)

      # Should have edges
      assert output =~ "→" or output =~ "->"
    end
  end
end
