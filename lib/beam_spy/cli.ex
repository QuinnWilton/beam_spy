defmodule BeamSpy.CLI do
  @moduledoc """
  Command-line interface for BeamSpy using Optimus.

  Provides subcommands for analyzing BEAM files:
  - atoms: Extract atom table
  - exports: List exported functions
  - imports: List imported functions
  - info: Show module metadata
  - chunks: List BEAM chunks
  - disasm: Disassemble bytecode
  - callgraph: Build function call graph
  """

  alias BeamSpy.Resolver
  alias BeamSpy.Theme
  alias BeamSpy.Commands.{Atoms, Exports, Imports, Info, Chunks, Disasm, Callgraph}

  @doc """
  Main entry point for the CLI.
  """
  def main(argv) do
    case Optimus.parse(optimus(), argv) do
      {:ok, subcommands, parsed} when is_list(subcommands) ->
        dispatch(subcommands, parsed)

      {:ok, parsed} when is_map(parsed) ->
        # No subcommand - dispatch based on flags
        dispatch([], parsed)

      {:error, errors} ->
        for error <- List.wrap(errors) do
          IO.puts(:stderr, "Error: #{error}")
        end

        1

      :help ->
        0

      :version ->
        0
    end
  end

  defp optimus do
    Optimus.new!(
      name: "beam_spy",
      description: "BEAM file analysis tool",
      version: BeamSpy.version(),
      allow_unknown_args: false,
      parse_double_dash: true,
      flags: [
        list_themes: [
          long: "--list-themes",
          help: "List available themes and exit"
        ]
      ],
      options: [
        theme: [
          short: "-t",
          long: "--theme",
          help: "Color theme to use",
          parser: :string,
          default: "default"
        ]
      ],
      subcommands: [
        atoms: atoms_command(),
        exports: exports_command(),
        imports: imports_command(),
        info: info_command(),
        chunks: chunks_command(),
        disasm: disasm_command(),
        callgraph: callgraph_command()
      ]
    )
  end

  # Subcommand definitions

  defp atoms_command do
    [
      name: "atoms",
      about: "Extract atom table from a BEAM file",
      args: [
        file: [
          value_name: "FILE",
          help: "BEAM file or module name",
          required: true,
          parser: :string
        ]
      ],
      options: [
        format: format_option(),
        filter: filter_option()
      ]
    ]
  end

  defp exports_command do
    [
      name: "exports",
      about: "List exported functions from a BEAM file",
      args: [
        file: [
          value_name: "FILE",
          help: "BEAM file or module name",
          required: true,
          parser: :string
        ]
      ],
      options: [
        format: format_option(),
        filter: filter_option()
      ],
      flags: [
        plain: [
          long: "--plain",
          help: "Output plain text (one per line, for piping)"
        ]
      ]
    ]
  end

  defp imports_command do
    [
      name: "imports",
      about: "List imported functions from a BEAM file",
      args: [
        file: [
          value_name: "FILE",
          help: "BEAM file or module name",
          required: true,
          parser: :string
        ]
      ],
      options: [
        format: format_option(),
        filter: filter_option()
      ],
      flags: [
        group: [
          long: "--group",
          short: "-g",
          help: "Group imports by module"
        ]
      ]
    ]
  end

  defp info_command do
    [
      name: "info",
      about: "Show module metadata from a BEAM file",
      args: [
        file: [
          value_name: "FILE",
          help: "BEAM file or module name",
          required: true,
          parser: :string
        ]
      ],
      options: [
        format: format_option()
      ]
    ]
  end

  defp chunks_command do
    [
      name: "chunks",
      about: "List BEAM file chunks",
      args: [
        file: [
          value_name: "FILE",
          help: "BEAM file or module name",
          required: true,
          parser: :string
        ]
      ],
      options: [
        format: format_option(),
        raw: [
          long: "--raw",
          short: "-r",
          help: "Hex dump of specific chunk (e.g., --raw AtU8)",
          parser: :string
        ]
      ]
    ]
  end

  defp disasm_command do
    [
      name: "disasm",
      about: "Disassemble BEAM bytecode",
      args: [
        file: [
          value_name: "FILE",
          help: "BEAM file or module name",
          required: true,
          parser: :string
        ]
      ],
      options: [
        format: format_option(),
        function: [
          long: "--function",
          short: "-f",
          help: "Filter to specific function (supports globs: handle_*)",
          parser: :string
        ]
      ],
      flags: [
        source: [
          long: "--source",
          short: "-S",
          help: "Interleave source code with disassembly"
        ]
      ]
    ]
  end

  defp callgraph_command do
    [
      name: "callgraph",
      about: "Build function call graph",
      args: [
        file: [
          value_name: "FILE",
          help: "BEAM file or module name",
          required: true,
          parser: :string
        ]
      ],
      options: [
        format: [
          long: "--format",
          help: "Output format: text, json, dot",
          parser: :string,
          default: "text"
        ]
      ]
    ]
  end

  # Common options

  defp format_option do
    [
      long: "--format",
      help: "Output format: text, json",
      parser: :string,
      default: "text"
    ]
  end

  defp filter_option do
    [
      long: "--filter",
      help: "Filter pattern (substring match)",
      parser: :string
    ]
  end

  # Dispatch to commands

  defp dispatch([], %{flags: %{list_themes: true}}) do
    for theme <- Theme.list() do
      IO.puts(theme)
    end

    0
  end

  defp dispatch([], _parsed) do
    IO.puts("Usage: beam_spy <command> [options] <file>")
    IO.puts("Run 'beam_spy --help' for more information.")
    1
  end

  defp dispatch([subcommand], parsed) do
    case subcommand do
      :atoms -> run_atoms(parsed)
      :exports -> run_exports(parsed)
      :imports -> run_imports(parsed)
      :info -> run_info(parsed)
      :chunks -> run_chunks(parsed)
      :disasm -> run_disasm(parsed)
      :callgraph -> run_callgraph(parsed)
      _ -> unknown_command(subcommand)
    end
  end

  defp unknown_command(cmd) do
    IO.puts(:stderr, "Unknown command: #{cmd}")
    1
  end

  # Command runners

  defp run_atoms(parsed) do
    with {:ok, path} <- resolve_file(parsed) do
      opts = build_opts(parsed, [:format, :filter])
      output = Atoms.run(path, opts)
      IO.puts(output)
      0
    end
  end

  defp run_exports(parsed) do
    with {:ok, path} <- resolve_file(parsed) do
      opts = build_opts(parsed, [:format, :filter, :plain])
      output = Exports.run(path, opts)
      IO.puts(output)
      0
    end
  end

  defp run_imports(parsed) do
    with {:ok, path} <- resolve_file(parsed) do
      opts = build_opts(parsed, [:format, :filter, :group])
      output = Imports.run(path, opts)
      IO.puts(output)
      0
    end
  end

  defp run_info(parsed) do
    with {:ok, path} <- resolve_file(parsed) do
      opts = build_opts(parsed, [:format])
      output = Info.run(path, opts)
      IO.puts(output)
      0
    end
  end

  defp run_chunks(parsed) do
    with {:ok, path} <- resolve_file(parsed) do
      opts = build_opts(parsed, [:format, :raw])
      output = Chunks.run(path, opts)
      IO.puts(output)
      0
    end
  end

  defp run_disasm(parsed) do
    with {:ok, path} <- resolve_file(parsed) do
      opts = build_opts(parsed, [:format, :function, :source])
      output = Disasm.run(path, opts)
      IO.puts(output)
      0
    end
  end

  defp run_callgraph(parsed) do
    with {:ok, path} <- resolve_file(parsed) do
      opts = build_opts(parsed, [:format])

      # Convert dot format string
      opts =
        case Keyword.get(opts, :format) do
          "dot" -> Keyword.put(opts, :format, :dot)
          _ -> opts
        end

      output = Callgraph.run(path, opts)
      IO.puts(output)
      0
    end
  end

  # Helpers

  defp resolve_file(%{args: %{file: file}}) do
    case Resolver.resolve(file) do
      {:ok, path} ->
        {:ok, path}

      {:error, :not_found} ->
        IO.puts(:stderr, "Error: Could not find BEAM file: #{file}")
        {:error, 1}
    end
  end

  defp build_opts(parsed, keys) do
    opts = []

    # Add options
    opts =
      Enum.reduce(keys, opts, fn key, acc ->
        case get_option(parsed, key) do
          nil -> acc
          value -> Keyword.put(acc, key, value)
        end
      end)

    # Convert format string to atom
    opts =
      case Keyword.get(opts, :format) do
        "json" -> Keyword.put(opts, :format, :json)
        "text" -> Keyword.put(opts, :format, :text)
        _ -> opts
      end

    # Load theme (from top-level --theme option)
    theme_name = get_option(parsed, :theme) || "default"

    theme =
      case Theme.load(theme_name) do
        {:ok, t} -> t
        {:error, _} -> Theme.default()
      end

    Keyword.put(opts, :theme, theme)
  end

  defp get_option(%{options: options, flags: flags}, key) do
    cond do
      Map.has_key?(options, key) -> Map.get(options, key)
      Map.has_key?(flags, key) -> Map.get(flags, key)
      true -> nil
    end
  end
end
