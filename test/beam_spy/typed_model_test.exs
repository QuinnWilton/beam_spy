defmodule BeamSpy.TypedModelTest do
  # The typed operand model must capture everything the legacy strings ever
  # showed: rendering the typed model is asserted character-identical to the
  # raw formatter across the whole fixture corpus plus two real stdlib
  # modules. The {:raw, _} fallback must never fire on that corpus — when a
  # future OTP adds an operand shape, this fails loudly instead of the model
  # silently degrading.
  use ExUnit.Case, async: true

  alias BeamSpy.{BeamFile, Instruction, Operand, Render}

  @fixtures Path.wildcard(Path.join(__DIR__, "../fixtures/beam/*.beam"))

  defp corpus do
    stdlib = [to_string(:code.which(:lists)), to_string(:code.which(Enum))]

    for path <- @fixtures ++ stdlib,
        {:ok, %{functions: functions}} = BeamFile.disassemble(path),
        {:function, _name, _arity, _entry, instructions} <- functions,
        raw <- instructions,
        do: raw
  end

  test "typed rendering is character-identical to the raw formatter" do
    for raw <- corpus() do
      typed = Instruction.from_raw(raw)

      {expected_opcode, expected_args} =
        case raw do
          opcode when is_atom(opcode) -> {opcode, []}
          {opcode} -> {opcode, []}
          tuple -> with [op | args] <- Tuple.to_list(tuple), do: {op, Render.raw_args(op, args)}
        end

      assert typed.opcode == expected_opcode
      assert Render.args(typed) == expected_args, "diverged for #{inspect(raw, limit: 12)}"
    end
  end

  test "no {:raw, _} operand occurs anywhere in the corpus" do
    for raw <- corpus(), instr = Instruction.from_raw(raw), operand <- instr.operands do
      refute has_raw?(operand), "unmodeled operand in #{inspect(raw, limit: 12)}"
    end
  end

  test "normalize/1 rewrites the container forms to real genop instructions" do
    test_raw = {:test, :is_eq_exact, {:f, 7}, [{:x, 0}, {:atom, :ok}]}
    normalized = test_raw |> Instruction.from_raw() |> Instruction.normalize()
    assert normalized.opcode == :is_eq_exact
    assert normalized.operands == [{:f, 7}, {:list, [{:x, 0}, {:atom, :ok}]}]

    bif_raw = {:bif, :tuple_size, {:f, 0}, [{:x, 0}], {:x, 1}}
    assert (bif_raw |> Instruction.from_raw() |> Instruction.normalize()).opcode == :bif1

    float_raw = {:bif, :fmul, {:f, 0}, [fr: 0, fr: 1], {:fr, 0}}
    normalized = float_raw |> Instruction.from_raw() |> Instruction.normalize()
    assert normalized.opcode == :fmul
    refute match?([{:atom, :fmul} | _], normalized.operands)

    gc_raw = {:gc_bif, :length, {:f, 0}, 1, [{:x, 0}], {:x, 0}}
    normalized = gc_raw |> Instruction.from_raw() |> Instruction.normalize()
    assert normalized.opcode == :gc_bif1
    # The BIF name stays as the first operand — it says *which* built-in.
    assert [{:atom, :length} | _] = normalized.operands
  end

  test "normalize/1 is idempotent and a no-op for plain instructions" do
    plain = Instruction.from_raw({:move, {:x, 0}, {:y, 1}})
    assert Instruction.normalize(plain) == plain

    once =
      {:test, :is_nil, {:f, 3}, [{:x, 0}]} |> Instruction.from_raw() |> Instruction.normalize()

    assert Instruction.normalize(once) == once
  end

  test "map operands are typed as pairs, not flat lists" do
    raw = {:get_map_elements, {:f, 5}, {:x, 0}, {:list, [atom: :a, x: 1, atom: :b, x: 2]}}
    instr = Instruction.from_raw(raw)

    assert [_fail, _src, {:map_pairs, :get, pairs}] = instr.operands
    assert pairs == [{{:atom, :a}, {:x, 1}}, {{:atom, :b}, {:x, 2}}]
  end

  test "disasm extract carries the typed model alongside the legacy strings" do
    {:ok, %{functions: [func | _]}} =
      BeamSpy.Commands.Disasm.extract(to_string(:code.which(:lists)))

    assert length(func.typed_instructions) == length(func.raw_instructions)
    assert Enum.all?(func.typed_instructions, &match?(%Instruction{}, &1))
  end

  defp has_raw?({:raw, _}), do: true
  defp has_raw?({:tr, reg, _type}), do: has_raw?(reg)
  defp has_raw?({:list, items}), do: Enum.any?(items, &has_raw?/1)
  defp has_raw?({:tagged, _tag, value}), do: has_raw?(value)

  defp has_raw?({:map_pairs, _kind, pairs}),
    do: Enum.any?(pairs, fn {k, v} -> has_raw?(k) or has_raw?(v) end)

  defp has_raw?(_), do: false

  # Operand.from_raw is referenced for the doc link; exercise it directly too.
  test "bare and tagged atoms stay distinguishable from the empty list" do
    assert Operand.from_raw(nil) == nil
    assert Operand.from_raw({:atom, nil}) == {:atom, nil}
    assert Render.operand(nil) == "[]"
    assert Render.operand({:atom, nil}) == "nil"
  end
end
