defmodule BeamSpy do
  @moduledoc """
  BeamSpy - A comprehensive BEAM file analysis tool.

  BeamSpy combines the roles of `objdump`, `strings`, and `readelf` but
  designed specifically for the BEAM VM's unique architecture.

  ## Usage

      # Extract atom table
      {:ok, atoms} = BeamSpy.atoms("path/to/module.beam")

      # List exported functions
      {:ok, exports} = BeamSpy.exports("path/to/module.beam")

      # Get module info
      {:ok, info} = BeamSpy.info("path/to/module.beam")

      # Disassemble bytecode
      {:ok, disasm} = BeamSpy.disasm("path/to/module.beam")

  ## Module Resolution

  BeamSpy accepts file paths, module names, and raw beam data:

      # Direct file path (any extension — the file's contents are read here,
      # so extensionless temp files work too)
      BeamSpy.info("./lib/my_app.beam")
      BeamSpy.info("/tmp/plug-upload-1234")

      # Module name (resolved automatically)
      BeamSpy.info("Elixir.Enum")
      BeamSpy.info("lists")

      # Raw beam data, recognized by its leading bytes
      # (see `t:BeamSpy.BeamFile.beam/0`)
      BeamSpy.info(File.read!("module.beam"))

  """

  @version Mix.Project.config()[:version]

  @doc """
  Returns the BeamSpy version.
  """
  def version, do: @version

  @doc """
  Extract atoms from a BEAM file.

  ## Options

    * `:filter` - Filter atoms by substring match

  ## Examples

      {:ok, atoms} = BeamSpy.atoms("Elixir.Enum.beam")
      {:ok, atoms} = BeamSpy.atoms("Enum", filter: "map")

  """
  def atoms(input, opts \\ []) do
    with {:ok, path} <- BeamSpy.Resolver.resolve(input) do
      BeamSpy.Commands.Atoms.extract(path, opts)
    end
  end

  @doc """
  Extract exported functions from a BEAM file.

  ## Options

    * `:filter` - Filter exports by name

  ## Examples

      {:ok, exports} = BeamSpy.exports("Elixir.Enum.beam")

  """
  def exports(input, opts \\ []) do
    with {:ok, path} <- BeamSpy.Resolver.resolve(input) do
      BeamSpy.Commands.Exports.extract(path, opts)
    end
  end

  @doc """
  Extract imported functions from a BEAM file.

  ## Options

    * `:filter` - Filter imports by name
    * `:group` - Group by module (default: false)

  ## Examples

      {:ok, imports} = BeamSpy.imports("Elixir.Enum.beam")

  """
  def imports(input, opts \\ []) do
    with {:ok, path} <- BeamSpy.Resolver.resolve(input) do
      BeamSpy.Commands.Imports.extract(path, opts)
    end
  end

  @doc """
  Get module metadata from a BEAM file.

  ## Examples

      {:ok, info} = BeamSpy.info("Elixir.Enum.beam")

  """
  def info(input, opts \\ []) do
    with {:ok, path} <- BeamSpy.Resolver.resolve(input) do
      BeamSpy.Commands.Info.extract(path, opts)
    end
  end

  @doc """
  List BEAM file chunks.

  ## Options

    * `:raw` - Chunk ID to dump as hex (e.g., "AtU8")

  ## Examples

      {:ok, chunks} = BeamSpy.chunks("Elixir.Enum.beam")

  """
  def chunks(input, opts \\ []) do
    with {:ok, path} <- BeamSpy.Resolver.resolve(input) do
      BeamSpy.Commands.Chunks.extract(path, opts)
    end
  end

  @doc """
  Disassemble BEAM bytecode.

  ## Options

    * `:function` - Filter to specific function(s), supports globs
    * `:source` - Interleave source code (default: false)

  ## Examples

      {:ok, disasm} = BeamSpy.disasm("Elixir.Enum.beam")
      {:ok, disasm} = BeamSpy.disasm("Enum", function: "map/2")
      {:ok, disasm} = BeamSpy.disasm("Enum", source: true)

  """
  def disasm(input, opts \\ []) do
    with {:ok, path} <- BeamSpy.Resolver.resolve(input) do
      BeamSpy.Commands.Disasm.extract(path, opts)
    end
  end

  @doc """
  Read the OTP 25+ `Type` chunk: the operand type table that `{:tr, reg, type}`
  operands index into.

  ## Examples

      {:ok, table} = BeamSpy.types("Elixir.Enum.beam")
      {:ok, table} = BeamSpy.types(Enum)

  """
  def types(input) do
    with {:ok, path} <- BeamSpy.Resolver.resolve(input) do
      BeamSpy.BeamType.read_table(path)
    end
  end

  @doc """
  Extract the literal pool (the `LitT` chunk) as `{index, term}` pairs.

  A missing chunk means the module pools no literals, so it yields `{:ok, []}`.

  ## Examples

      {:ok, literals} = BeamSpy.literals("Elixir.Enum.beam")
      {:ok, literals} = BeamSpy.literals("lists")

  """
  def literals(input) do
    with {:ok, path} <- BeamSpy.Resolver.resolve(input) do
      BeamSpy.Commands.Literals.extract(path)
    end
  end

  @doc """
  Read the EEP-48 `Docs` chunk as a normalized map.

  Returns `{:error, :no_docs_chunk}` for modules compiled without docs.

  ## Examples

      {:ok, docs} = BeamSpy.docs("Elixir.Enum.beam")
      {:ok, docs} = BeamSpy.docs("lists")

  """
  def docs(input) do
    with {:ok, path} <- BeamSpy.Resolver.resolve(input) do
      BeamSpy.Commands.Docs.extract(path)
    end
  end

  @doc """
  Build a call graph from a BEAM file.

  ## Examples

      {:ok, graph} = BeamSpy.callgraph("Elixir.Enum.beam")

  """
  def callgraph(input, opts \\ []) do
    with {:ok, path} <- BeamSpy.Resolver.resolve(input) do
      BeamSpy.Commands.Callgraph.extract(path, opts)
    end
  end
end
