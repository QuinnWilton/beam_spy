defmodule BeamSpy.Parser.GenopTest do
  use ExUnit.Case, async: true

  alias BeamSpy.Parser.Genop

  describe "parse/1" do
    test "parses simple opcode definition" do
      input = "4: call/2"
      assert [%{opcode: 4, name: :call, arity: 2}] = Genop.parse(input)
    end

    test "parses deprecated opcode" do
      input = "14: -allocate_zero/2"
      assert [%{deprecated: true}] = Genop.parse(input)
    end

    test "parses non-deprecated opcode" do
      input = "4: call/2"
      assert [%{deprecated: false}] = Genop.parse(input)
    end

    test "parses @spec annotation" do
      input = """
      ## @spec call Arity Label
      4: call/2
      """

      assert [%{args: ["Arity", "Label"]}] = Genop.parse(input)
    end

    test "parses @doc annotation" do
      input = """
      ## @doc Call the function at Label.
      4: call/2
      """

      assert [%{doc: "Call the function at Label."}] = Genop.parse(input)
    end

    test "parses multi-line @doc" do
      input = """
      ## @doc Call the function at Label.
      ##      Save the next instruction.
      4: call/2
      """

      [opcode] = Genop.parse(input)
      assert opcode.doc =~ "Call the function"
      assert opcode.doc =~ "Save the next"
    end

    test "skips single-hash comments" do
      input = """
      # This is a comment
      4: call/2
      """

      assert [%{opcode: 4}] = Genop.parse(input)
    end

    test "skips BEAM_FORMAT_NUMBER" do
      input = """
      BEAM_FORMAT_NUMBER=0
      4: call/2
      """

      assert [%{opcode: 4}] = Genop.parse(input)
    end

    test "skips blank lines" do
      input = """
      4: call/2

      5: call_last/3
      """

      assert [%{opcode: 4}, %{opcode: 5}] = Genop.parse(input)
    end

    test "parses multiple opcodes" do
      input = """
      1: label/1
      2: func_info/3
      4: call/2
      """

      opcodes = Genop.parse(input)
      assert length(opcodes) == 3
      assert Enum.map(opcodes, & &1.opcode) == [1, 2, 4]
    end
  end

  describe "parse/1 with actual genop.tab" do
    @genop_content File.read!(Path.join(:code.priv_dir(:beam_spy), "genop.tab"))

    test "parses actual genop.tab without errors" do
      opcodes = Genop.parse(@genop_content)
      assert length(opcodes) > 100
    end

    test "all opcodes have valid structure" do
      opcodes = Genop.parse(@genop_content)

      for opcode <- opcodes do
        assert is_integer(opcode.opcode) and opcode.opcode >= 0
        assert is_atom(opcode.name)
        assert is_integer(opcode.arity) and opcode.arity >= 0
        assert is_boolean(opcode.deprecated)
      end
    end

    test "opcode numbers are unique" do
      opcodes = Genop.parse(@genop_content)
      numbers = Enum.map(opcodes, & &1.opcode)
      assert numbers == Enum.uniq(numbers)
    end

    test "contains known opcodes" do
      opcodes = Genop.parse(@genop_content)
      names = Enum.map(opcodes, & &1.name)

      assert :call in names
      assert :return in names
      assert :move in names
      assert :label in names
    end
  end
end
