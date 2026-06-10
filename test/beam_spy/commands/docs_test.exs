defmodule BeamSpy.Commands.DocsTest do
  use ExUnit.Case, async: true

  alias BeamSpy.Commands.Docs

  @enum_beam_path :code.which(Enum) |> to_string()
  @lists_beam_path :code.which(:lists) |> to_string()

  describe "extract/2 on real modules" do
    test "reads Elixir docs from Enum" do
      assert {:ok, docs} = Docs.extract(@enum_beam_path)
      assert docs.language == :elixir
      assert docs.format == "text/markdown"
      assert %{"en" => module_doc} = docs.module_doc
      assert is_binary(module_doc)

      map2 =
        Enum.find(docs.entries, &(&1.kind == :function and &1.name == :map and &1.arity == 2))

      assert %{signature: [sig], doc: %{"en" => body}} = map2
      assert sig =~ "map("
      assert is_binary(body)
    end

    test "reads Erlang docs from :lists" do
      assert {:ok, docs} = Docs.extract(@lists_beam_path)
      assert docs.language == :erlang
      assert docs.entries != []
      assert Enum.any?(docs.entries, &(&1.kind == :function))
    end

    test "every entry is fully normalized" do
      {:ok, docs} = Docs.extract(@enum_beam_path)

      for entry <- docs.entries do
        assert is_atom(entry.kind)
        assert is_atom(entry.name)
        assert is_integer(entry.arity) and entry.arity >= 0
        assert is_list(entry.signature) and Enum.all?(entry.signature, &is_binary/1)
        assert is_map(entry.metadata)
        assert match?(%{}, entry.doc) or entry.doc in [:none, :hidden]
      end
    end
  end

  describe "extract/2 error space" do
    test "a module compiled without docs yields :no_docs_chunk" do
      path = compile_fixture("beam_spy_docs_none", [])

      try do
        assert {:error, :no_docs_chunk} = Docs.extract(path)
      after
        File.rm(path)
      end
    end

    test "an unrecognized docs term is rejected by :beam_lib's validation" do
      docs_chunk = :erlang.term_to_binary({:docs_v99, :from_the_future})
      path = compile_fixture("beam_spy_docs_future", extra_chunks: [{"Docs", docs_chunk}])

      try do
        assert {:error, {:invalid_chunk, ~c"Docs"}} = Docs.extract(path)
      after
        File.rm(path)
      end
    end

    test "returns a file error for a missing path" do
      assert {:error, {:file_error, :enoent}} = Docs.extract("does_not_exist.beam")
    end
  end

  describe "BeamSpy.docs/1" do
    test "resolves module names" do
      assert {:ok, %{language: :erlang}} = BeamSpy.docs("lists")
    end
  end

  defp compile_fixture(name, opts) do
    module = String.to_atom(name)

    forms = [
      {:attribute, 1, :module, module},
      {:attribute, 2, :export, [{:f, 0}]},
      {:function, 3, :f, 0, [{:clause, 3, [], [], [{:atom, 3, :ok}]}]}
    ]

    extra = Keyword.get(opts, :extra_chunks, [])
    {:ok, ^module, binary} = :compile.forms(forms, [:return_errors, {:extra_chunks, extra}])
    path = Path.join(System.tmp_dir!(), "#{name}.beam")
    File.write!(path, binary)
    path
  end
end
