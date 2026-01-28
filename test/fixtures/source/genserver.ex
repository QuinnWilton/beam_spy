defmodule TestGenServer do
  use GenServer

  def init(arg), do: {:ok, arg}
  def handle_call(:get, _from, state), do: {:reply, state, state}
  def handle_cast({:set, val}, _state), do: {:noreply, val}
  def handle_info(:tick, state), do: {:noreply, state}
end
