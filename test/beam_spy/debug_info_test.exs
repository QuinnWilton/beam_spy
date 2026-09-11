defmodule BeamSpy.DebugInfoTest do
  use ExUnit.Case, async: true

  alias BeamSpy.DebugInfo

  # An Erlang fixture compiled with beam_debug_info: rebinding across a
  # stack frame gives x-register, y-register, and frame-size coverage.
  @source ~C"""
  -module(debug_info_toy).
  -export([requeue/2]).

  requeue(Job, State0) ->
      Requeued = Job#{status => available},
      State = State0#{jobs => Requeued},
      self() ! State,
      {reply, requeued, State}.
  """

  setup_all do
    dir = Path.join(System.tmp_dir!(), "beam_spy_dbgb_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "debug_info_toy.erl")
    File.write!(path, @source)

    {:ok, :debug_info_toy, beam} =
      :compile.file(String.to_charlist(path), [:beam_debug_info, :binary, :report])

    on_exit(fn -> File.rm_rf!(dir) end)
    %{beam: beam}
  end

  test "parse/1 yields frame sizes and variable locations", %{beam: beam} do
    assert {:ok, items} = DebugInfo.parse(beam)
    assert items != []

    # The entry item names parameters; later items carry named variables
    # in registers.
    assert Enum.any?(items, &(&1.frame == :entry))
    assert Enum.all?(items, &is_integer(&1.position))

    named =
      for %{vars: vars} <- items, {name, where} <- vars, is_binary(name), do: {name, where}

    assert {"State0", {:x, 1}} in named
    assert Enum.any?(named, &match?({"State", {:y, _}}, &1))
  end

  test "by_line/1 keys entries by source line", %{beam: beam} do
    assert {:ok, entries} = DebugInfo.by_line(beam)

    # Line 7 (`self() ! State`) sees State in an x register; by line 8
    # (`{reply, requeued, State}`) a frame exists and State lives in y0.
    send_line = Enum.find(entries, &(&1.line == 7))
    assert send_line
    assert {"State", {:x, _}} = Enum.find(send_line.vars, &match?({"State", _}, &1))

    reply_line = Enum.find(entries, &(&1.line == 8))
    assert is_integer(reply_line.frame)
    assert Enum.any?(reply_line.vars, &match?({"State", {:y, _}}, &1))
  end

  test "a beam without the chunk reports it honestly" do
    # An ordinary compiled module is not a debug build.
    beam = :code.which(BeamSpy) |> to_string()
    assert {:error, :missing_debug_chunk} = DebugInfo.parse(beam)
  end
end
