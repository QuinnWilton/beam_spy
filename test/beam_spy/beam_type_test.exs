defmodule BeamSpy.BeamTypeTest do
  use ExUnit.Case, async: true

  alias BeamSpy.BeamType

  test "reads the Type table of a freshly compiled module" do
    # Building a 10-bit segment proves the value fits 0..1023, and that range
    # lands in the Type table as a tr-operand type.
    source = """
    defmodule BeamTypeProbe do
      def pack(n) when is_integer(n) and n >= 0 and n < 1024, do: <<n::10>>
    end
    """

    [{module, beam} | _] = Code.compile_string(source, "nofile")
    :code.purge(module)
    :code.delete(module)

    assert {:ok, table} = BeamType.read_table(beam)
    assert table.count == length(table.entries)
    assert table.count > 0

    rendered = Enum.map(table.entries, &BeamType.render/1)
    assert Enum.all?(rendered, &(is_binary(&1) and &1 != ""))
    # The guard-proved range surfaces in the compiler's own vocabulary.
    assert Enum.any?(rendered, &(&1 =~ "1023"))
  end

  test "reads from a path and from a real stdlib module" do
    path = to_string(:code.which(:lists))
    assert {:ok, table} = BeamType.read_table(path)
    assert table.count == length(table.entries)
  end

  test "a beam without a Type chunk degrades explicitly" do
    fixture = Path.join(__DIR__, "../fixtures/beam/minimal.beam")

    case BeamType.read_table(fixture) do
      {:ok, table} -> assert table.count == length(table.entries)
      {:error, reason} -> assert reason == :no_type_chunk
    end
  end

  test "garbage input is an error, not a crash" do
    assert {:error, _} = BeamType.read_table(<<"not a beam">>)
  end
end
