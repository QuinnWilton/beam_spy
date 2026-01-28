defmodule BeamSpy.Opcodes do
  @moduledoc """
  BEAM opcode definitions generated from genop.tab.

  This module is generated at compile time by parsing OTP's genop.tab file,
  which defines all BEAM opcodes with their numbers, names, arities, and
  documentation.

  ## Usage

      iex> BeamSpy.Opcodes.info(4)
      %{name: :call, arity: 2, deprecated: false, doc: "Call the function...", args: ["Arity", "Label"]}

      iex> BeamSpy.Opcodes.category(:call)
      :call

  """

  alias BeamSpy.Parser.Genop

  @genop_path Path.join(:code.priv_dir(:beam_spy), "genop.tab")
  @external_resource @genop_path

  # Parse at compile time
  @opcodes @genop_path |> File.read!() |> Genop.parse()

  # Filter to active (non-deprecated) opcodes
  @active_opcodes Enum.reject(@opcodes, & &1.deprecated)

  # Category definitions based on opcode name patterns
  @call_ops ~w(call call_last call_only call_ext call_ext_last call_fun call_fun2 apply apply_last)a
  @bif_ops ~w(bif0 bif1 bif2 gc_bif1 gc_bif2 gc_bif3)a
  @stack_ops ~w(allocate allocate_heap allocate_zero allocate_heap_zero deallocate trim test_heap init init_yregs)a
  @data_ops ~w(move swap get_list get_hd get_tl get_tuple_element set_tuple_element put_list put_tuple2 make_fun3 update_record)a
  @control_ops ~w(label jump select_val select_tuple_arity)a
  @test_ops ~w(is_lt is_ge is_eq is_ne is_eq_exact is_ne_exact is_integer is_float is_number is_atom is_pid is_reference is_port is_nil is_binary is_list is_nonempty_list is_tuple is_function is_function2 is_boolean is_bitstr is_map is_tagged_tuple test_arity has_map_fields)a
  @exception_ops ~w(try try_end try_case try_case_end catch catch_end raise build_stacktrace raw_raise)a
  @error_ops ~w(badmatch if_end case_end badrecord func_info)a
  @message_ops ~w(send remove_message timeout loop_rec loop_rec_end wait wait_timeout recv_marker_bind recv_marker_clear recv_marker_reserve recv_marker_use)a
  @bs_ops ~w(bs_get_integer2 bs_get_float2 bs_get_binary2 bs_skip_bits2 bs_test_tail2 bs_test_unit bs_match_string bs_init_writable bs_get_utf8 bs_skip_utf8 bs_get_utf16 bs_skip_utf16 bs_get_utf32 bs_skip_utf32 bs_get_tail bs_start_match3 bs_start_match4 bs_get_position bs_set_position bs_create_bin bs_match)a

  # Generate lookup functions for each opcode
  for %{opcode: num, name: name, arity: arity, deprecated: dep, doc: doc, args: args} <- @opcodes do
    def info(unquote(num)) do
      %{
        name: unquote(name),
        arity: unquote(arity),
        deprecated: unquote(dep),
        doc: unquote(doc),
        args: unquote(args)
      }
    end

    def name(unquote(num)), do: unquote(name)
    def arity(unquote(num)), do: unquote(arity)
    def deprecated?(unquote(num)), do: unquote(dep)
  end

  # Fallback for unknown opcodes
  def info(n),
    do: %{name: :"unknown_#{n}", arity: 0, deprecated: false, doc: nil, args: []}

  def name(n), do: :"unknown_#{n}"
  def arity(_), do: 0
  def deprecated?(_), do: false

  # Reverse lookup: name -> opcode number
  for %{opcode: num, name: name} <- @opcodes do
    def number(unquote(name)), do: unquote(num)
  end

  def number(_), do: nil

  @doc """
  Returns all opcode definitions.
  """
  @spec all() :: [map()]
  def all, do: @opcodes

  @doc """
  Returns only active (non-deprecated) opcodes.
  """
  @spec active() :: [map()]
  def active, do: @active_opcodes

  @doc """
  Returns the total number of opcodes.
  """
  @spec count() :: non_neg_integer()
  def count, do: length(@opcodes)

  @doc """
  Returns the category for an opcode name.

  Categories are used for syntax highlighting and organization.
  """
  @spec category(atom()) :: atom()
  def category(name) when name in @call_ops, do: :call
  def category(name) when name in @bif_ops, do: :call
  def category(name) when name in @stack_ops, do: :stack
  def category(name) when name in @data_ops, do: :data
  def category(name) when name in @control_ops, do: :control
  def category(name) when name in @test_ops, do: :control
  def category(name) when name in @exception_ops, do: :exception
  def category(name) when name in @error_ops, do: :error
  def category(name) when name in @message_ops, do: :message
  def category(name) when name in @bs_ops, do: :binary
  def category(:return), do: :return
  def category(:line), do: :meta
  def category(:executable_line), do: :meta
  def category(:debug_line), do: :meta
  def category(:int_code_end), do: :meta
  def category(:on_load), do: :meta
  def category(:nif_start), do: :meta
  def category(_), do: :unknown

  @doc """
  Returns a list of all categories.
  """
  @spec categories() :: [atom()]
  def categories do
    [
      :call,
      :stack,
      :data,
      :control,
      :return,
      :exception,
      :error,
      :message,
      :binary,
      :meta,
      :unknown
    ]
  end
end
