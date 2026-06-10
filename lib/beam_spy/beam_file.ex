defmodule BeamSpy.BeamFile do
  @moduledoc """
  Helpers for reading BEAM file chunks.

  Provides a nicer interface over `:beam_lib` with better error handling
  and more convenient return types.
  """

  @type chunk_id :: atom() | String.t()
  @type beam_error ::
          :not_a_beam_file
          | {:file_error, term()}
          | {:missing_chunk, chunk_id()}
          | {:invalid_chunk, charlist()}

  @typedoc """
  What every reader accepts: raw beam data, or a path to a beam file.

  Raw beam data is recognized by its leading bytes — the `"FOR1"` IFF header,
  or the gzip magic for compressed beams (`:beam_lib` gunzips those itself).
  Any other binary is treated as a file path. Paths may carry any extension
  (or none): the file is read here and its *contents* handed to `:beam_lib`,
  which would otherwise rewrite the filename to end in `".beam"`.
  """
  @type beam :: Path.t() | binary()

  @chunk_descriptions %{
    "AtU8" => "Atom table (UTF-8)",
    "Atom" => "Atom table (Latin-1)",
    "Code" => "Bytecode",
    "StrT" => "String table",
    "ImpT" => "Import table",
    "ExpT" => "Export table",
    "LitT" => "Literal table (compressed)",
    "LocT" => "Local function table",
    "FunT" => "Lambda/fun table",
    "Attr" => "Module attributes",
    "CInf" => "Compile info",
    "Dbgi" => "Debug info",
    "Docs" => "Documentation chunk",
    "ExCk" => "ExCheck chunk",
    "Line" => "Line number table",
    "Type" => "Type information",
    "Meta" => "Metadata",
    "Abst" => "Abstract code"
  }

  @doc """
  Load beam input into raw beam data for `:beam_lib`/`:beam_disasm`.

  Raw beam data passes through untouched; anything else is treated as a file
  path and read exactly once. Reading here — rather than handing `:beam_lib`
  the filename — is what makes arbitrary-extension paths work: `:beam_lib`
  rewrites any filename it receives to end in `".beam"`, so an extensionless
  temp file would fail with `:enoent`.
  """
  @spec load(beam()) :: {:ok, binary()} | {:error, beam_error()}
  def load(input) when is_binary(input) do
    if beam_data?(input) do
      {:ok, input}
    else
      case File.read(input) do
        {:ok, data} -> {:ok, data}
        {:error, reason} -> {:error, {:file_error, reason}}
      end
    end
  end

  @doc """
  Whether a binary is raw beam data rather than a file path.

  Recognizes the `"FOR1"` IFF header and the gzip magic (compressed beams,
  which `:beam_lib` gunzips itself). A *path* starting with those bytes is
  pathological enough to be out of scope.
  """
  @spec beam_data?(binary()) :: boolean()
  def beam_data?(<<"FOR1", _::binary>>), do: true
  def beam_data?(<<0x1F, 0x8B, _::binary>>), do: true
  def beam_data?(input) when is_binary(input), do: false

  @doc """
  Returns information about the BEAM file including all chunks.

  Returns a map with:
  - `:module` - The module name
  - `:file` - The file path (`nil` when raw beam data was given)
  - `:chunks` - List of chunk info maps

  """
  @spec info(beam()) :: {:ok, map()} | {:error, beam_error()}
  def info(input) do
    # Load once and stay at the data level: handing loaded *contents* back to
    # the load-taking readers would re-interpret non-beam junk as a path.
    with {:ok, beam} <- load(input),
         {:ok, chunks} <- do_read_all_chunks(beam),
         {:ok, module} <- do_get_module_name(beam) do
      chunk_info =
        Enum.map(chunks, fn {id, data} ->
          id_str = chunk_id_to_string(id)

          %{
            id: id_str,
            size: byte_size(data),
            description: Map.get(@chunk_descriptions, id_str, "Unknown chunk")
          }
        end)

      {:ok,
       %{
         module: module,
         file: if(beam_data?(input), do: nil, else: input),
         chunks: chunk_info
       }}
    end
  end

  @doc """
  Reads all chunks from a BEAM file.

  Returns raw chunk data as `{chunk_id, binary}` tuples.
  """
  @spec read_all_chunks(beam()) ::
          {:ok, [{atom() | charlist(), binary()}]} | {:error, beam_error()}
  def read_all_chunks(input) do
    with {:ok, beam} <- load(input) do
      do_read_all_chunks(beam)
    end
  end

  defp do_read_all_chunks(beam) do
    case :beam_lib.all_chunks(beam) do
      {:ok, _module, chunks} ->
        {:ok, chunks}

      {:error, :beam_lib, {:not_a_beam_file, _}} ->
        {:error, :not_a_beam_file}

      {:error, :beam_lib, {:file_error, _, reason}} ->
        {:error, {:file_error, reason}}
    end
  end

  @doc """
  Reads specific chunks from a BEAM file.
  """
  @spec read_chunks(beam(), [chunk_id()]) ::
          {:ok, [{chunk_id(), term()}]} | {:error, beam_error()}
  def read_chunks(input, chunk_ids) do
    chunk_atoms = Enum.map(chunk_ids, &normalize_chunk_id/1)

    with {:ok, beam} <- load(input) do
      do_read_chunks(beam, chunk_atoms)
    end
  end

  defp do_read_chunks(beam, chunk_atoms) do
    case :beam_lib.chunks(beam, chunk_atoms) do
      {:ok, {_module, chunks}} ->
        {:ok, chunks}

      {:error, :beam_lib, {:not_a_beam_file, _}} ->
        {:error, :not_a_beam_file}

      {:error, :beam_lib, {:file_error, _, reason}} ->
        {:error, {:file_error, reason}}

      {:error, :beam_lib, {:missing_chunk, _, chunk}} ->
        {:error, {:missing_chunk, chunk}}

      # A chunk that is present but fails :beam_lib's decoding/validation,
      # e.g. a Docs chunk whose term is not a recognized docs format.
      {:error, :beam_lib, {:invalid_chunk, _, chunk}} ->
        {:error, {:invalid_chunk, chunk}}
    end
  end

  @doc """
  Reads the atom table from a BEAM file.

  Returns a list of atoms (the index is stripped).
  """
  @spec read_atoms(beam()) :: {:ok, [atom()]} | {:error, beam_error()}
  def read_atoms(path) do
    case read_chunks(path, [:atoms]) do
      {:ok, [{:atoms, indexed_atoms}]} ->
        # Atoms come as {index, atom} tuples - extract just the atoms
        atoms = Enum.map(indexed_atoms, fn {_index, atom} -> atom end)
        {:ok, atoms}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Reads the export table from a BEAM file.

  Returns a list of `{function_name, arity, label}` tuples.
  """
  @spec read_exports(beam()) ::
          {:ok, [{atom(), non_neg_integer(), non_neg_integer()}]} | {:error, beam_error()}
  def read_exports(path) do
    case read_chunks(path, [:exports]) do
      {:ok, [{:exports, exports}]} -> {:ok, exports}
      {:error, _} = error -> error
    end
  end

  @doc """
  Reads the import table from a BEAM file.

  Returns a list of `{module, function_name, arity}` tuples.
  """
  @spec read_imports(beam()) ::
          {:ok, [{atom(), atom(), non_neg_integer()}]} | {:error, beam_error()}
  def read_imports(path) do
    case read_chunks(path, [:imports]) do
      {:ok, [{:imports, imports}]} -> {:ok, imports}
      {:error, _} = error -> error
    end
  end

  @doc """
  Reads the compile info from a BEAM file.

  Returns a keyword list with compilation metadata.
  """
  @spec read_compile_info(beam()) :: {:ok, keyword()} | {:error, beam_error()}
  def read_compile_info(path) do
    case read_chunks(path, [:compile_info]) do
      {:ok, [{:compile_info, info}]} -> {:ok, info}
      {:error, _} = error -> error
    end
  end

  @doc """
  Reads the module attributes from a BEAM file.
  """
  @spec read_attributes(beam()) :: {:ok, keyword()} | {:error, beam_error()}
  def read_attributes(path) do
    case read_chunks(path, [:attributes]) do
      {:ok, [{:attributes, attrs}]} -> {:ok, attrs}
      {:error, _} = error -> error
    end
  end

  @doc """
  Gets the module name from a BEAM file.
  """
  @spec get_module_name(beam()) :: {:ok, atom()} | {:error, beam_error()}
  def get_module_name(input) do
    with {:ok, beam} <- load(input) do
      do_get_module_name(beam)
    end
  end

  defp do_get_module_name(beam) do
    case :beam_lib.info(beam) do
      info when is_list(info) ->
        {:ok, Keyword.fetch!(info, :module)}

      {:error, :beam_lib, {:not_a_beam_file, _}} ->
        {:error, :not_a_beam_file}

      {:error, :beam_lib, {:file_error, _, reason}} ->
        {:error, {:file_error, reason}}
    end
  end

  @doc """
  Gets the MD5 hash of a BEAM file.
  """
  @spec get_md5(beam()) :: {:ok, binary()} | {:error, beam_error()}
  def get_md5(input) do
    with {:ok, beam} <- load(input) do
      case :beam_lib.md5(beam) do
        {:ok, {_module, md5}} -> {:ok, md5}
        {:error, :beam_lib, {:not_a_beam_file, _}} -> {:error, :not_a_beam_file}
        {:error, :beam_lib, {:file_error, _, reason}} -> {:error, {:file_error, reason}}
      end
    end
  end

  @doc """
  Disassembles a BEAM file into its function definitions.

  Returns a map with:
  - `:module` - The module name
  - `:exports` - List of exported functions
  - `:attributes` - Module attributes
  - `:compile_info` - Compilation information
  - `:functions` - List of function tuples from beam_disasm

  """
  @spec disassemble(beam()) :: {:ok, map()} | {:error, beam_error()}
  def disassemble(input) do
    with {:ok, beam} <- load(input) do
      case :beam_disasm.file(beam) do
        {:beam_file, module, exports, attributes, compile_info, functions} ->
          {:ok,
           %{
             module: module,
             exports: exports,
             attributes: attributes,
             compile_info: compile_info,
             functions: functions
           }}

        {:error, :beam_lib, {:not_a_beam_file, _}} ->
          {:error, :not_a_beam_file}

        {:error, :beam_lib, {:file_error, _, reason}} ->
          {:error, {:file_error, reason}}

        {:error, _beam_lib, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Reads a raw chunk by ID, returning the binary data.
  """
  @spec read_raw_chunk(beam(), chunk_id()) :: {:ok, binary()} | {:error, beam_error()}
  def read_raw_chunk(path, chunk_id) do
    with {:ok, chunks} <- read_all_chunks(path) do
      target_id = chunk_id_to_charlist(chunk_id)

      case Enum.find(chunks, fn {id, _} -> normalize_id_for_comparison(id) == target_id end) do
        {_, data} -> {:ok, data}
        nil -> {:error, {:missing_chunk, chunk_id}}
      end
    end
  end

  @doc """
  Returns a map of known chunk IDs to their descriptions.
  """
  @spec chunk_descriptions() :: %{String.t() => String.t()}
  def chunk_descriptions, do: @chunk_descriptions

  # Normalize chunk ID to atom format used by :beam_lib.chunks/2.
  defp normalize_chunk_id(id) when is_atom(id), do: id

  defp normalize_chunk_id(id) when is_binary(id) do
    String.to_atom(id)
  end

  # Convert chunk ID to charlist for comparison with all_chunks results.
  defp chunk_id_to_charlist(id) when is_atom(id), do: Atom.to_charlist(id)
  defp chunk_id_to_charlist(id) when is_binary(id), do: String.to_charlist(id)
  defp chunk_id_to_charlist(id) when is_list(id), do: id

  # Normalize ID from all_chunks for comparison.
  defp normalize_id_for_comparison(id) when is_list(id), do: id
  defp normalize_id_for_comparison(id) when is_atom(id), do: Atom.to_charlist(id)

  defp chunk_id_to_string(id) when is_atom(id), do: Atom.to_string(id)
  defp chunk_id_to_string(id) when is_binary(id), do: id
  defp chunk_id_to_string(id) when is_list(id), do: List.to_string(id)
end
