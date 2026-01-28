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

  Uses a temp file approach for reliable interaction with pagers like `less`.
  The pager runs interactively, reading from the file while the user can
  scroll through the content.
  """
  @spec page(String.t()) :: :ok
  def page(output) do
    pager_cmd = System.get_env("PAGER", "less -R")

    # Write output to a temp file
    tmp_path = Path.join(System.tmp_dir!(), "beam_spy_#{:erlang.unique_integer([:positive])}.txt")

    try do
      File.write!(tmp_path, output)

      # Run pager with the file. Using :nouse_stdio ensures the pager
      # can interact directly with the terminal (not through our port).
      port =
        Port.open(
          {:spawn_executable, System.find_executable("sh")},
          [
            :binary,
            :exit_status,
            :nouse_stdio,
            args: ["-c", "#{pager_cmd} #{escape_path(tmp_path)}"]
          ]
        )

      wait_for_exit(port)
    after
      File.rm(tmp_path)
    end

    :ok
  rescue
    error ->
      # Fallback to just printing if pager fails
      IO.puts(:stderr, "Warning: pager failed (#{inspect(error)}), printing directly")
      IO.puts(output)
      :ok
  end

  # Escape path for shell command
  defp escape_path(path) do
    "'" <> String.replace(path, "'", "'\\''") <> "'"
  end

  defp wait_for_exit(port) do
    receive do
      {^port, {:exit_status, _status}} ->
        :ok

      {^port, _} ->
        # Ignore other port messages and keep waiting
        wait_for_exit(port)
    after
      # Timeout after 30 minutes (interactive paging can take a while)
      1_800_000 ->
        Port.close(port)
        :ok
    end
  end

  # Check if output line count exceeds terminal rows
  defp output_exceeds_terminal?(output) do
    case Terminal.rows() do
      rows when is_integer(rows) and rows > 0 ->
        line_count = count_lines(output)
        # Leave room for prompt
        line_count > rows - 2

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
