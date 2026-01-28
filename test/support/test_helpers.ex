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
end
