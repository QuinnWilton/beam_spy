defmodule BeamSpy.Application do
  @moduledoc false
  use Application

  # Burrito is an optional dependency (it only ships with the packaged
  # binary), so downstream consumers compile beam_spy without it. This is
  # the documented way to tell the compiler the module may be absent; the
  # Code.ensure_loaded?/1 check below guards the call at runtime.
  @compile {:no_warn_undefined, Burrito.Util.Args}

  @impl true
  def start(_type, _args) do
    # In a Burrito release, run the CLI and exit. In dev/test (and in the
    # unexpected case of a non-Burrito release), start the supervisor.
    if release_mode?() and Code.ensure_loaded?(Burrito.Util.Args) do
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
