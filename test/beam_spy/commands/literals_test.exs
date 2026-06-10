defmodule BeamSpy.Commands.LiteralsTest do
  use ExUnit.Case, async: true

  alias BeamSpy.Commands.Literals

  @enum_beam_path :code.which(Enum) |> to_string()
  @lists_beam_path :code.which(:lists) |> to_string()

  describe "extract/2" do
    test "extracts the literal pool from Enum in pool order" do
      assert {:ok, entries} = Literals.extract(@enum_beam_path)
      assert entries != []
      assert Enum.map(entries, &elem(&1, 0)) == Enum.to_list(0..(length(entries) - 1))
    end

    test "every {:literal, _} disasm operand of :lists is a pool term" do
      {:ok, entries} = Literals.extract(@lists_beam_path)
      pool = entries |> Enum.map(&elem(&1, 1)) |> MapSet.new()

      {:ok, %{functions: functions}} = BeamSpy.disasm(@lists_beam_path)

      referenced =
        functions
        |> Enum.flat_map(& &1.raw_instructions)
        |> Enum.flat_map(&collect_literals/1)

      assert referenced != []

      for term <- referenced do
        assert MapSet.member?(pool, term),
               "disasm references literal #{inspect(term)} not present in the pool"
      end
    end

    test "a module with no LitT chunk has an empty pool", %{} do
      path = compile_minimal_fixture("beam_spy_literals_empty")

      try do
        assert {:ok, []} = Literals.extract(path)
      after
        File.rm(path)
      end
    end

    test "returns a file error for a missing path" do
      assert {:error, {:file_error, :enoent}} = Literals.extract("does_not_exist.beam")
    end
  end

  describe "BeamSpy.literals/1" do
    test "resolves module names" do
      assert {:ok, entries} = BeamSpy.literals("Elixir.Enum")
      assert entries != []
    end
  end

  # Walk a raw beam_disasm instruction term for {:literal, term} operands.
  defp collect_literals({:literal, term}), do: [term]

  defp collect_literals(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.flat_map(&collect_literals/1)

  defp collect_literals(list) when is_list(list),
    do: Enum.flat_map(list, &collect_literals/1)

  defp collect_literals(_other), do: []

  # An Erlang module returning only an immediate: nothing is pooled, so the
  # compiler omits the LitT chunk entirely.
  defp compile_minimal_fixture(name) do
    module = String.to_atom(name)

    forms = [
      {:attribute, 1, :module, module},
      {:attribute, 2, :export, [{:f, 0}]},
      {:function, 3, :f, 0, [{:clause, 3, [], [], [{:atom, 3, :ok}]}]}
    ]

    {:ok, ^module, binary} = :compile.forms(forms, [:return_errors])
    path = Path.join(System.tmp_dir!(), "#{name}.beam")
    File.write!(path, binary)
    path
  end
end
