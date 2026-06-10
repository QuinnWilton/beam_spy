defmodule BeamSpy.Commands.Docs do
  @moduledoc """
  Read the EEP-48 `Docs` chunk from a BEAM file.

  The chunk stores a `{:docs_v1, ...}` term whose entries this reader
  normalizes into maps, keeping each doc body verbatim (a `"text/markdown"`
  body is a binary; other formats keep whatever terms the producer stored —
  rendering is the consumer's decision, keyed off `:format`).

  The chunk is optional: modules compiled without docs (or stripped) simply
  do not carry it, surfaced as `{:error, :no_docs_chunk}` rather than a guess.
  """

  alias BeamSpy.BeamFile

  @typedoc "A doc body: per-language content, or explicitly absent/hidden."
  @type doc_content :: %{String.t() => term()} | :none | :hidden

  @typedoc "One documented entry (function, type, or callback)."
  @type entry :: %{
          kind: atom(),
          name: atom(),
          arity: non_neg_integer(),
          signature: [String.t()],
          doc: doc_content(),
          metadata: map()
        }

  @typedoc "The normalized Docs chunk."
  @type docs :: %{
          language: atom(),
          format: String.t(),
          module_doc: doc_content(),
          metadata: map(),
          entries: [entry()]
        }

  @doc """
  Extract the documentation as a normalized map.

  Returns `{:error, :no_docs_chunk}` when the module carries no `Docs` chunk.
  A present-but-unrecognized docs term surfaces as
  `{:error, {:invalid_chunk, ~c"Docs"}}` — `:beam_lib` validates the chunk
  before this reader sees it — with `{:unsupported_docs_version, term}` kept
  as a defensive gate should that validation ever loosen.
  """
  @spec extract(BeamFile.beam(), keyword()) :: {:ok, docs()} | {:error, term()}
  def extract(path, _opts \\ []) do
    case BeamFile.read_chunks(path, [:documentation]) do
      {:ok, [{:documentation, docs_term}]} -> normalize(docs_term)
      {:error, {:missing_chunk, _}} -> {:error, :no_docs_chunk}
      {:error, _} = error -> error
    end
  end

  defp normalize({:docs_v1, _anno, language, format, module_doc, metadata, entries}) do
    {:ok,
     %{
       language: language,
       format: to_string(format),
       module_doc: module_doc,
       metadata: metadata,
       entries: Enum.map(entries, &normalize_entry/1)
     }}
  end

  defp normalize(other), do: {:error, {:unsupported_docs_version, other}}

  defp normalize_entry({{kind, name, arity}, _anno, signature, doc, metadata}) do
    %{
      kind: kind,
      name: name,
      arity: arity,
      signature: Enum.map(signature, &to_string/1),
      doc: doc,
      metadata: metadata
    }
  end
end
