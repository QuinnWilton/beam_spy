defmodule TestWithImports do
  def add(a, b), do: :erlang.+(a, b)
  def length_of(list), do: :erlang.length(list)
end
