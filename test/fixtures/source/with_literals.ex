defmodule TestWithLiterals do
  @big_map %{a: 1, b: 2, c: 3, d: 4, e: 5, f: 6}
  @big_list Enum.to_list(1..100)

  def get_map, do: @big_map
  def get_list, do: @big_list
  def nested, do: %{data: [1, [2, [3, [4]]]]}
end
