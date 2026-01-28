defmodule BeamSpy.Pager do
  @moduledoc """
  Automatic paging for long output.

  When output exceeds the terminal height, pipes it through the
  system pager (PAGER env var, or `less -R` by default).
  """

  alias BeamSpy.Terminal

  @doc """
  Check if output should be paged based on terminal size.
  """
  @spec should_page?(String.t()) :: boolean()
  def should_page?(output) do
    Terminal.interactive?() and output_exceeds_terminal?(output)
  end

  @doc """
  Maybe page the output if it exceeds terminal height.

  Options:
    * `:paging` - :auto (default), :always, or :never
  """
  @spec maybe_page(String.t(), keyword()) :: :ok
  def maybe_page(output, opts \\ []) do
    paging_mode = Keyword.get(opts, :paging, :auto)

    should_page =
      case paging_mode do
        :always -> Terminal.interactive?()
        :never -> false
        :auto -> should_page?(output)
        _ -> should_page?(output)
      end

    if should_page do
      page(output)
    else
      IO.puts(output)
    end
  end

  @doc """
  Pipe output through the system pager.
  """
  @spec page(String.t()) :: :ok
  def page(output) do
    pager = System.get_env("PAGER", "less -R")

    # Use Port to pipe to pager
    port =
      Port.open({:spawn, pager}, [
        :binary,
        :use_stdio,
        :exit_status
      ])

    Port.command(port, output)
    Port.close(port)

    :ok
  rescue
    _ ->
      # Fallback to just printing if pager fails
      IO.puts(output)
      :ok
  end

  # Check if output line count exceeds terminal rows
  defp output_exceeds_terminal?(output) do
    case Terminal.rows() do
      rows when is_integer(rows) and rows > 0 ->
        line_count = count_lines(output)
        line_count > rows - 2  # Leave room for prompt

      _ ->
        false
    end
  end

  defp count_lines(output) do
    output
    |> String.split("\n")
    |> length()
  end
end
