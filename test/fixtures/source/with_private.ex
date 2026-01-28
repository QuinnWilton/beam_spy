defmodule TestWithPrivate do
  def public_fn(x), do: private_helper(x) + 1

  defp private_helper(x), do: x * 2
end
