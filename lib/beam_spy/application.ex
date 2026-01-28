defmodule BeamSpy.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # In a release, run CLI and exit
    # In dev/test, start supervisor for normal operation
    if release_mode?() do
      args = Burrito.Util.Args.get_arguments()
      code = BeamSpy.CLI.main(args)
      System.halt(code)
    else
      Supervisor.start_link([], strategy: :one_for_one, name: BeamSpy.Supervisor)
    end
  end

  # Check if we're running as a release
  defp release_mode? do
    # Releases set RELEASE_ROOT environment variable
    System.get_env("RELEASE_ROOT") != nil
  end
end
