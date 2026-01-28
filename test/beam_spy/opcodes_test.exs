defmodule BeamSpy.OpcodesTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias BeamSpy.Opcodes

  describe "info/1" do
    test "returns info for known opcode" do
      info = Opcodes.info(4)
      assert info.name == :call
      assert info.arity == 2
      assert info.deprecated == false
    end

    test "returns info for deprecated opcode" do
      info = Opcodes.info(14)
      assert info.name == :allocate_zero
      assert info.deprecated == true
    end

    test "returns unknown for invalid opcode" do
      info = Opcodes.info(9999)
      assert info.name == :unknown_9999
    end
  end

  describe "name/1" do
    test "returns name for known opcode" do
      assert Opcodes.name(1) == :label
      assert Opcodes.name(4) == :call
      assert Opcodes.name(19) == :return
    end

    test "returns unknown for invalid opcode" do
      assert Opcodes.name(9999) == :unknown_9999
    end
  end

  describe "arity/1" do
    test "returns arity for known opcode" do
      # call/2
      assert Opcodes.arity(4) == 2
      # return/0
      assert Opcodes.arity(19) == 0
    end
  end

  describe "deprecated?/1" do
    test "returns false for active opcodes" do
      # call
      refute Opcodes.deprecated?(4)
      # return
      refute Opcodes.deprecated?(19)
    end

    test "returns true for deprecated opcodes" do
      # allocate_zero
      assert Opcodes.deprecated?(14)
    end
  end

  describe "number/1" do
    test "returns opcode number for known name" do
      assert Opcodes.number(:call) == 4
      assert Opcodes.number(:return) == 19
      assert Opcodes.number(:label) == 1
    end

    test "returns nil for unknown name" do
      assert Opcodes.number(:not_an_opcode) == nil
    end
  end

  describe "all/0" do
    test "returns list of all opcodes" do
      all = Opcodes.all()
      assert is_list(all)
      assert length(all) > 100
    end

    test "opcodes have required fields" do
      for opcode <- Opcodes.all() do
        assert Map.has_key?(opcode, :opcode)
        assert Map.has_key?(opcode, :name)
        assert Map.has_key?(opcode, :arity)
        assert Map.has_key?(opcode, :deprecated)
      end
    end
  end

  describe "active/0" do
    test "returns only non-deprecated opcodes" do
      active = Opcodes.active()
      assert is_list(active)

      for opcode <- active do
        refute opcode.deprecated
      end
    end

    test "active count is less than all count" do
      assert length(Opcodes.active()) < length(Opcodes.all())
    end
  end

  describe "count/0" do
    test "returns total opcode count" do
      assert Opcodes.count() == length(Opcodes.all())
      assert Opcodes.count() > 100
    end
  end

  describe "category/1" do
    @category_examples [
      {:call, :call},
      {:call_ext, :call},
      {:call_only, :call},
      {:gc_bif2, :call},
      {:allocate, :stack},
      {:deallocate, :stack},
      {:trim, :stack},
      {:move, :data},
      {:get_tuple_element, :data},
      {:put_list, :data},
      {:is_tuple, :control},
      {:is_eq_exact, :control},
      {:select_val, :control},
      {:jump, :control},
      {:label, :control},
      {:try, :exception},
      {:catch, :exception},
      {:raise, :exception},
      {:badmatch, :error},
      {:case_end, :error},
      {:func_info, :error},
      {:send, :message},
      {:wait, :message},
      {:bs_match, :binary},
      {:bs_create_bin, :binary},
      {:return, :return},
      {:line, :meta}
    ]

    for {name, expected} <- @category_examples do
      test "category(#{name}) == #{expected}" do
        assert Opcodes.category(unquote(name)) == unquote(expected)
      end
    end

    test "unknown opcodes return :unknown category" do
      assert Opcodes.category(:not_a_real_opcode) == :unknown
    end
  end

  describe "property tests" do
    property "all active opcodes have valid structure" do
      opcodes = Opcodes.active()

      check all(opcode <- member_of(opcodes)) do
        assert is_integer(opcode.opcode) and opcode.opcode >= 0
        assert is_atom(opcode.name)
        assert is_integer(opcode.arity) and opcode.arity >= 0
        assert is_boolean(opcode.deprecated)
        refute opcode.deprecated
      end
    end

    property "opcode numbers are unique" do
      opcodes = Opcodes.all()
      numbers = Enum.map(opcodes, & &1.opcode)
      assert numbers == Enum.uniq(numbers)
    end

    property "info/1 and name/1 are consistent" do
      check all(opcode <- member_of(Opcodes.all())) do
        info = Opcodes.info(opcode.opcode)
        name = Opcodes.name(opcode.opcode)
        assert info.name == name
      end
    end

    property "number/1 and name/1 are inverses" do
      check all(opcode <- member_of(Opcodes.all())) do
        number = Opcodes.number(opcode.name)
        assert number == opcode.opcode
      end
    end

    property "all active opcodes have a defined category" do
      check all(opcode <- member_of(Opcodes.active())) do
        category = Opcodes.category(opcode.name)

        assert category in [
                 :call,
                 :stack,
                 :data,
                 :control,
                 :exception,
                 :error,
                 :message,
                 :binary,
                 :return,
                 :meta,
                 :unknown
               ]
      end
    end
  end
end
