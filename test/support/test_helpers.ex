defmodule BeamSpy.Test.Helpers do
  @moduledoc """
  Test helper functions for BeamSpy tests.
  """

  @fixture_dir "test/fixtures/beam"

  @doc """
  Get the path to a test fixture beam file.
  """
  def fixture_path(filename) when is_binary(filename) do
    Path.join(@fixture_dir, filename)
  end

  @doc """
  Get the path to a stdlib module's beam file.
  """
  def beam_path(module) when is_atom(module) do
    case :code.which(module) do
      :non_existing -> raise "Module #{module} not found"
      path -> to_string(path)
    end
  end

  @doc """
  Get the default theme for testing.
  """
  def default_theme do
    {:ok, theme} = BeamSpy.Theme.load("default")
    theme
  end

  @doc """
  Ensure test fixtures are built before running tests.
  Called from test_helper.exs
  """
  def ensure_fixtures do
    fixture_dir = Path.join(File.cwd!(), @fixture_dir)

    # Build fixtures if directory is empty or doesn't exist
    if not File.exists?(fixture_dir) or Enum.empty?(File.ls!(fixture_dir)) do
      BeamSpy.Test.BeamBuilder.build_all()
    end

    :ok
  end

  @doc """
  Get the path to a Gleam stdlib module's beam file.
  Compiles the Gleam stdlib if needed.
  """
  def gleam_beam_path(module_name) when is_binary(module_name) do
    deps_dir = Path.join(File.cwd!(), "deps/gleam_stdlib")
    ebin_dir = Path.join(deps_dir, "ebin")
    beam_file = Path.join(ebin_dir, "#{module_name}.beam")

    # Compile Gleam stdlib if beam files don't exist
    if not File.exists?(beam_file) do
      compile_gleam_stdlib(deps_dir, ebin_dir)
    end

    if File.exists?(beam_file), do: beam_file, else: nil
  end

  defp compile_gleam_stdlib(deps_dir, ebin_dir) do
    src_dir = Path.join(deps_dir, "src")

    if File.exists?(src_dir) do
      File.mkdir_p!(ebin_dir)

      src_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".erl"))
      |> Enum.each(fn file ->
        src_path = Path.join(src_dir, file)
        System.cmd("erlc", ["-o", ebin_dir, src_path], stderr_to_stdout: true)
      end)
    end
  end

  @doc """
  Get the path to the compiled Gleam test fixture.
  Ensures the Gleam artefacts are compiled to beam files.
  """
  def gleam_fixture_path(module_name \\ "test_fixture") do
    ebin_dir = Path.join([File.cwd!(), "_build/test/lib/beam_spy/ebin"])
    beam_file = Path.join(ebin_dir, "#{module_name}.beam")

    # Compile Gleam artefacts if beam file doesn't exist
    if not File.exists?(beam_file) do
      compile_gleam_artefacts()
    end

    if File.exists?(beam_file), do: beam_file, else: nil
  end

  defp compile_gleam_artefacts do
    artefacts_dir = Path.join([File.cwd!(), "_build/test/lib/beam_spy/_gleam_artefacts"])
    ebin_dir = Path.join([File.cwd!(), "_build/test/lib/beam_spy/ebin"])

    if File.exists?(artefacts_dir) do
      artefacts_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".erl"))
      |> Enum.each(fn file ->
        src_path = Path.join(artefacts_dir, file)
        System.cmd("erlc", ["-o", ebin_dir, src_path], stderr_to_stdout: true)
      end)
    end
  end
end
