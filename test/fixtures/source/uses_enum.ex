defmodule TestUsesEnum do
  def double_all(list), do: Enum.map(list, &(&1 * 2))
  def sum(list), do: Enum.reduce(list, 0, &+/2)
end
