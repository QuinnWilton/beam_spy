defmodule TestRecursive do
  def factorial(0), do: 1
  def factorial(n), do: n * factorial(n - 1)

  def mutual_a(0), do: :done
  def mutual_a(n), do: mutual_b(n - 1)

  def mutual_b(n), do: mutual_a(n)
end
