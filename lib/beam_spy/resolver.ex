defmodule BeamSpy.Resolver do
  @moduledoc """
  Resolve module names to .beam file paths.

  Supports both direct file paths and module names, with automatic
  resolution through Mix projects, Erlang code paths, and ERL_LIBS.

  ## Resolution Order

  1. Direct file path (if input contains "/" or ends with ".beam")
  2. Current directory: `./ModuleName.beam`
  3. Mix project (if in a Mix project):
     - `_build/dev/lib/*/ebin/ModuleName.beam`
     - `_build/prod/lib/*/ebin/ModuleName.beam`
  4. Erlang code path: `:code.get_path()` locations
  5. `ERL_LIBS` environment variable paths

  ## Examples

      # Direct file path
      iex> BeamSpy.Resolver.resolve("./module.beam")
      {:ok, "./module.beam"}

      # Elixir module name
      iex> BeamSpy.Resolver.resolve("Enum")
      {:ok, "/path/to/elixir/ebin/Elixir.Enum.beam"}

      # Erlang module name
      iex> BeamSpy.Resolver.resolve("lists")
      {:ok, "/path/to/stdlib/ebin/lists.beam"}

  """

  @type resolve_error :: :not_found | :invalid_path

  @doc """
  Resolve an input to a .beam file path.

  ## Options

    * `:path` - Additional search paths (list or single path)

  """
  @spec resolve(String.t(), keyword()) :: {:ok, String.t()} | {:error, resolve_error()}
  def resolve(input, opts \\ []) do
    cond do
      # Direct file path
      String.contains?(input, "/") or String.ends_with?(input, ".beam") ->
        resolve_file_path(input)

      # Module name
      true ->
        resolve_module_name(input, opts)
    end
  end

  @doc """
  Like `resolve/2` but raises on error.
  """
  @spec resolve!(String.t(), keyword()) :: String.t()
  def resolve!(input, opts \\ []) do
    case resolve(input, opts) do
      {:ok, path} -> path
      {:error, :not_found} -> raise "Could not find beam file for: #{input}"
      {:error, :invalid_path} -> raise "Invalid path: #{input}"
    end
  end

  defp resolve_file_path(path) do
    if File.exists?(path) do
      {:ok, Path.expand(path)}
    else
      {:error, :not_found}
    end
  end

  defp resolve_module_name(name, opts) do
    beam_name = module_to_beam_name(name)
    search_paths = build_search_paths(opts)

    case find_in_paths(beam_name, search_paths) do
      nil -> {:error, :not_found}
      path -> {:ok, path}
    end
  end

  defp module_to_beam_name(name) do
    # Handle both "Elixir.Foo" and "Foo" for Elixir modules.
    # Erlang modules like "lists" stay as-is.
    cond do
      # Already has Elixir prefix
      String.starts_with?(name, "Elixir.") ->
        "#{name}.beam"

      # Starts with uppercase -> Elixir module
      String.match?(name, ~r/^[A-Z]/) ->
        "Elixir.#{name}.beam"

      # Lowercase -> Erlang module
      true ->
        "#{name}.beam"
    end
  end

  defp build_search_paths(opts) do
    extra = opts |> Keyword.get(:path, []) |> List.wrap()

    extra ++
      ["."] ++
      mix_project_paths() ++
      erlang_code_paths() ++
      erl_libs_paths()
  end

  defp mix_project_paths do
    case find_mix_project() do
      nil ->
        []

      root ->
        # Search in _build for all environments and all apps
        Path.wildcard(Path.join([root, "_build", "*", "lib", "*", "ebin"]))
    end
  end

  defp find_mix_project(dir \\ File.cwd!()) do
    mix_path = Path.join(dir, "mix.exs")

    cond do
      File.exists?(mix_path) -> dir
      dir == "/" -> nil
      true -> find_mix_project(Path.dirname(dir))
    end
  end

  defp erlang_code_paths do
    :code.get_path()
    |> Enum.map(&to_string/1)
  end

  defp erl_libs_paths do
    case System.get_env("ERL_LIBS") do
      nil ->
        []

      libs ->
        libs
        |> String.split(":")
        |> Enum.flat_map(fn lib_path ->
          Path.wildcard(Path.join(lib_path, "*/ebin"))
        end)
    end
  end

  defp find_in_paths(beam_name, paths) do
    Enum.find_value(paths, fn path ->
      full_path = Path.join(path, beam_name)
      if File.exists?(full_path), do: full_path
    end)
  end

  @doc """
  Returns the search paths that would be used for resolution.

  Useful for debugging path resolution issues.
  """
  @spec search_paths(keyword()) :: [String.t()]
  def search_paths(opts \\ []) do
    build_search_paths(opts)
  end
end
