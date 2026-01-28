defmodule Mix.Tasks.BeamSpy do
  @moduledoc """
  Runs the BeamSpy CLI.

  This task allows running BeamSpy commands during development without
  building an escript first.

  ## Usage

      mix beam_spy <command> [options] <file>

  ## Examples

      mix beam_spy info Enum
      mix beam_spy atoms lists --format=json
      mix beam_spy disasm MyModule --function="handle_*"
      mix beam_spy --help

  For full command documentation, run `mix beam_spy --help`.
  """

  use Mix.Task

  @shortdoc "Runs BeamSpy CLI commands"

  @impl Mix.Task
  def run(args) do
    # Ensure the application is started (loads themes, etc.)
    Mix.Task.run("app.start", [])

    # Run CLI and exit with the appropriate code
    exit_code = BeamSpy.CLI.run(args)

    if exit_code != 0 do
      Mix.raise("BeamSpy exited with code #{exit_code}")
    end
  end
end
