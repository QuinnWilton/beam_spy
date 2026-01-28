defmodule BeamSpy.Test.Generators do
  @moduledoc """
  StreamData generators for property-based testing.

  Provides generators for beam files, opcodes, instructions,
  and filter patterns.
  """

  use ExUnitProperties

  alias BeamSpy.Test.Helpers

  @fixture_dir "test/fixtures/beam"

  @doc """
  Generator for paths to test fixture .beam files.
  """
  def beam_file do
    fixture_files()
    |> Enum.map(&Path.join(@fixture_dir, &1))
    |> member_of()
  end

  @doc """
  Generator for paths to real stdlib .beam files.
  Useful for testing against real-world modules.
  """
  def stdlib_beam_file do
    stdlib_modules()
    |> StreamData.member_of()
    |> StreamData.map(&Helpers.beam_path/1)
  end

  @doc """
  Generator for any available .beam file (fixture or stdlib).
  """
  def any_beam_file do
    StreamData.one_of([beam_file(), stdlib_beam_file()])
  end

  @doc """
  Generator for valid opcode names (atoms).
  Uses actual opcodes from the Opcodes module.
  """
  def opcode_name do
    BeamSpy.Opcodes.all()
    |> Enum.map(& &1.name)
    |> member_of()
  end

  @doc """
  Generator for opcode categories.
  """
  def opcode_category do
    member_of([
      :call,
      :control,
      :data,
      :stack,
      :return,
      :exception,
      :error,
      :message,
      :binary,
      :meta,
      :unknown
    ])
  end

  @doc """
  Generator for x register references.
  """
  def x_register do
    StreamData.map(StreamData.integer(0..255), fn n -> {:x, n} end)
  end

  @doc """
  Generator for y register references.
  """
  def y_register do
    StreamData.map(StreamData.integer(0..255), fn n -> {:y, n} end)
  end

  @doc """
  Generator for any register reference.
  """
  def register do
    StreamData.one_of([x_register(), y_register()])
  end

  @doc """
  Generator for label references.
  """
  def label_ref do
    StreamData.map(StreamData.positive_integer(), fn n -> {:f, n} end)
  end

  @doc """
  Generator for atom literals.
  """
  def atom_literal do
    StreamData.one_of([
      StreamData.constant({:atom, :ok}),
      StreamData.constant({:atom, :error}),
      StreamData.constant({:atom, nil}),
      StreamData.constant({:atom, true}),
      StreamData.constant({:atom, false}),
      StreamData.map(StreamData.atom(:alphanumeric), fn a -> {:atom, a} end)
    ])
  end

  @doc """
  Generator for integer literals.
  """
  def integer_literal do
    StreamData.map(StreamData.integer(), fn n -> {:integer, n} end)
  end

  @doc """
  Generator for instruction arguments.
  """
  def instruction_arg do
    StreamData.one_of([
      register(),
      label_ref(),
      atom_literal(),
      integer_literal()
    ])
  end

  @doc """
  Generator for simple instructions (move, return, etc).
  """
  def simple_instruction do
    StreamData.one_of([
      # return
      StreamData.constant({:return}),
      # move src, dst
      StreamData.map(
        StreamData.tuple({register(), register()}),
        fn {src, dst} -> {:move, src, dst} end
      ),
      # label n
      StreamData.map(
        StreamData.positive_integer(),
        fn n -> {:label, n} end
      ),
      # jump label
      StreamData.map(
        label_ref(),
        fn label -> {:jump, label} end
      )
    ])
  end

  @doc """
  Generator for filter patterns (glob, regex, substring).
  """
  def filter_pattern do
    StreamData.one_of([
      # Substring pattern
      StreamData.string(:alphanumeric, min_length: 1, max_length: 20),
      # Glob pattern
      glob_pattern(),
      # Regex pattern (simple)
      regex_pattern()
    ])
  end

  @doc """
  Generator for glob patterns.
  """
  def glob_pattern do
    StreamData.one_of([
      # prefix*
      StreamData.map(
        StreamData.string(:alphanumeric, min_length: 1, max_length: 10),
        fn s -> s <> "*" end
      ),
      # *suffix
      StreamData.map(
        StreamData.string(:alphanumeric, min_length: 1, max_length: 10),
        fn s -> "*" <> s end
      ),
      # *middle*
      StreamData.map(
        StreamData.string(:alphanumeric, min_length: 1, max_length: 10),
        fn s -> "*" <> s <> "*" end
      )
    ])
  end

  @doc """
  Generator for simple regex patterns.
  """
  def regex_pattern do
    StreamData.one_of([
      # Word pattern
      StreamData.map(
        StreamData.string(:alphanumeric, min_length: 1, max_length: 10),
        fn s -> "~r/#{s}/" end
      ),
      # Pattern with word boundary
      StreamData.map(
        StreamData.string(:alphanumeric, min_length: 1, max_length: 10),
        fn s -> "~r/\\b#{s}\\b/" end
      )
    ])
  end

  @doc """
  Generator for function name/arity pairs.
  """
  def function_signature do
    StreamData.tuple({
      StreamData.atom(:alphanumeric),
      StreamData.integer(0..10)
    })
  end

  @doc """
  Generator for module names.
  """
  def module_name do
    StreamData.one_of([
      # Elixir-style module
      StreamData.map(
        StreamData.string(:alphanumeric, min_length: 1, max_length: 20),
        fn s -> Module.concat([String.capitalize(s)]) end
      ),
      # Erlang-style module (lowercase atom)
      StreamData.atom(:alphanumeric)
    ])
  end

  # Private helpers

  defp fixture_files do
    case File.ls(@fixture_dir) do
      {:ok, files} -> Enum.filter(files, &String.ends_with?(&1, ".beam"))
      _ -> []
    end
  end

  defp stdlib_modules do
    [
      # Elixir modules
      Enum,
      List,
      Map,
      String,
      Keyword,
      Tuple,
      IO,
      File,
      Path,
      # Erlang modules
      :lists,
      :maps,
      :ets,
      :gen_server,
      :supervisor,
      :erlang
    ]
  end
end
