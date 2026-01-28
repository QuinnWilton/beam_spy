defmodule BeamSpy.Test.BeamBuilder do
  @moduledoc """
  Build .beam files programmatically for controlled testing.

  This module compiles Elixir/Erlang source code to .beam files
  in the test fixtures directory.
  """

  @fixture_dir "test/fixtures/beam"
  @source_dir "test/fixtures/source"

  def build_all do
    File.mkdir_p!(@fixture_dir)
    File.mkdir_p!(@source_dir)

    build_simple_module()
    build_complex_module()
    build_with_imports()
    build_uses_enum()
    build_with_private()
    build_genserver()
    build_no_imports()
    build_recursive()
    build_with_literals()
    build_stripped_module()
    build_unicode_atoms()
    build_special_atoms()
    build_minimal()
    build_empty_module()
    build_single_return()
    build_nested_literal()
    build_erlang_module()
    build_long_function()

    :ok
  end

  def build_simple_module do
    code = """
    defmodule TestSimple do
      def foo, do: :ok
      def bar(x), do: x + 1
    end
    """

    compile_to_fixture(code, "simple.beam", "simple.ex")
  end

  def build_complex_module do
    code = """
    defmodule TestComplex do
      def clamp(n, min, max) do
        cond do
          n < min -> min
          n > max -> max
          true -> n
        end
      end

      def recursive(0), do: :done
      def recursive(n) when n > 0, do: recursive(n - 1)
    end
    """

    compile_to_fixture(code, "complex.beam", "complex.ex")
  end

  def build_with_imports do
    code = """
    defmodule TestWithImports do
      def add(a, b), do: :erlang.+(a, b)
      def length_of(list), do: :erlang.length(list)
    end
    """

    compile_to_fixture(code, "with_imports.beam", "with_imports.ex")
  end

  def build_uses_enum do
    code = """
    defmodule TestUsesEnum do
      def double_all(list), do: Enum.map(list, &(&1 * 2))
      def sum(list), do: Enum.reduce(list, 0, &+/2)
    end
    """

    compile_to_fixture(code, "uses_enum.beam", "uses_enum.ex")
  end

  def build_with_private do
    code = """
    defmodule TestWithPrivate do
      def public_fn(x), do: private_helper(x) + 1

      defp private_helper(x), do: x * 2
    end
    """

    compile_to_fixture(code, "with_private.beam", "with_private.ex")
  end

  def build_genserver do
    code = """
    defmodule TestGenServer do
      use GenServer

      def init(arg), do: {:ok, arg}
      def handle_call(:get, _from, state), do: {:reply, state, state}
      def handle_cast({:set, val}, _state), do: {:noreply, val}
      def handle_info(:tick, state), do: {:noreply, state}
    end
    """

    compile_to_fixture(code, "genserver.beam", "genserver.ex")
  end

  def build_no_imports do
    code = """
    defmodule TestNoImports do
      def constant, do: 42
      def tuple, do: {:ok, :value}
      def list, do: [1, 2, 3]
    end
    """

    compile_to_fixture(code, "no_imports.beam", "no_imports.ex")
  end

  def build_recursive do
    code = """
    defmodule TestRecursive do
      def factorial(0), do: 1
      def factorial(n), do: n * factorial(n - 1)

      def mutual_a(0), do: :done
      def mutual_a(n), do: mutual_b(n - 1)

      def mutual_b(n), do: mutual_a(n)
    end
    """

    compile_to_fixture(code, "recursive.beam", "recursive.ex")
  end

  def build_with_literals do
    code = """
    defmodule TestWithLiterals do
      @big_map %{a: 1, b: 2, c: 3, d: 4, e: 5, f: 6}
      @big_list Enum.to_list(1..100)

      def get_map, do: @big_map
      def get_list, do: @big_list
      def nested, do: %{data: [1, [2, [3, [4]]]]}
    end
    """

    compile_to_fixture(code, "with_literals.beam", "with_literals.ex")
  end

  def build_stripped_module do
    code = """
    defmodule TestStripped do
      def foo, do: :ok
    end
    """

    # Compile normally first
    [{_module, binary}] = Code.compile_string(code, "nofile")

    # Strip debug info using :beam_lib
    {:ok, {_mod, stripped}} = :beam_lib.strip(binary)

    beam_path = Path.join(@fixture_dir, "no_debug_info.beam")
    File.write!(beam_path, stripped)
    {:ok, beam_path}
  end

  def build_unicode_atoms do
    code = """
    defmodule TestUnicodeAtoms do
      def hello, do: :hello_world
      def world, do: :test_atom
      def cafe, do: :coffee
    end
    """

    compile_to_fixture(code, "unicode_atoms.beam", "unicode_atoms.ex")
  end

  def build_special_atoms do
    code = """
    defmodule TestSpecialAtoms do
      def with_at, do: :"foo@bar"
      def with_underscore, do: :with_underscore
      def numeric_end, do: :test123
    end
    """

    compile_to_fixture(code, "special_atoms.beam", "special_atoms.ex")
  end

  def build_minimal do
    code = """
    defmodule TestMinimal do
    end
    """

    compile_to_fixture(code, "minimal.beam", nil)
  end

  def build_empty_module do
    code = """
    defmodule TestEmpty do
    end
    """

    compile_to_fixture(code, "empty_module.beam", nil)
  end

  def build_single_return do
    code = """
    defmodule TestSingleReturn do
      def noop, do: nil
    end
    """

    compile_to_fixture(code, "single_return.beam", nil)
  end

  def build_nested_literal do
    code = """
    defmodule TestNestedLiteral do
      @nested [[[1, 2], [3, 4]], [[5, 6], [7, 8]]]
      def get, do: @nested
    end
    """

    compile_to_fixture(code, "nested_literal.beam", "nested_literal.ex")
  end

  def build_erlang_module do
    # Create a simple Erlang module
    erlang_code = """
    -module(test_erlang).
    -export([hello/0, add/2]).

    hello() -> world.

    add(A, B) -> A + B.
    """

    erlang_source = Path.join(@source_dir, "test_erlang.erl")
    File.write!(erlang_source, erlang_code)

    # Compile Erlang source
    beam_path = Path.join(@fixture_dir, "erlang_module.beam")

    case :compile.file(to_charlist(erlang_source), [
           :binary,
           :debug_info,
           {:outdir, to_charlist(@fixture_dir)}
         ]) do
      {:ok, _module, binary} ->
        File.write!(beam_path, binary)
        {:ok, beam_path}

      {:ok, _module} ->
        # Module was written directly by compiler
        {:ok, beam_path}

      error ->
        {:error, error}
    end
  end

  def build_long_function do
    # Generate a module with a function containing many instructions
    # This creates a function with 100+ case clauses
    clauses =
      Enum.map(1..100, fn n ->
        "      #{n} -> :value_#{n}"
      end)
      |> Enum.join("\n")

    code = """
    defmodule TestLongFunction do
      def lookup(n) do
        case n do
    #{clauses}
          _ -> :not_found
        end
      end

      def chain(x) do
        x
        |> step1()
        |> step2()
        |> step3()
        |> step4()
        |> step5()
        |> step6()
        |> step7()
        |> step8()
        |> step9()
        |> step10()
      end

      defp step1(x), do: x + 1
      defp step2(x), do: x * 2
      defp step3(x), do: x - 1
      defp step4(x), do: div(x, 2)
      defp step5(x), do: x + 10
      defp step6(x), do: x * 3
      defp step7(x), do: x - 5
      defp step8(x), do: rem(x, 100)
      defp step9(x), do: x + 50
      defp step10(x), do: x
    end
    """

    compile_to_fixture(code, "long_function.beam", nil)
  end

  # Helper functions

  defp compile_to_fixture(code, beam_filename, source_filename, _opts \\ []) do
    # Write source file if provided
    source_path =
      if source_filename do
        path = Path.join(@source_dir, source_filename)
        File.write!(path, code)
        path
      else
        "nofile"
      end

    try do
      [{_module, binary}] = Code.compile_string(code, source_path)
      beam_path = Path.join(@fixture_dir, beam_filename)
      File.write!(beam_path, binary)
      {:ok, beam_path}
    rescue
      e -> {:error, e}
    end
  end
end
