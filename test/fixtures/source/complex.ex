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
