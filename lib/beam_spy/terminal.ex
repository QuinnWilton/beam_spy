defmodule BeamSpy.Terminal do
  @moduledoc """
  Terminal capability detection and utilities.

  Provides functions to detect whether output is going to an interactive
  terminal, and what capabilities that terminal supports.
  """

  @doc """
  Returns true if stdout is connected to an interactive terminal (TTY).

  This is used to determine whether to enable colors, paging, and other
  interactive features.
  """
  @spec interactive?() :: boolean()
  def interactive? do
    match?({:ok, _}, :io.columns()) and match?({:ok, _}, :io.rows())
  end

  @doc """
  Returns the terminal width in columns.

  Falls back to 80 if the terminal width cannot be determined.
  """
  @spec columns() :: pos_integer()
  def columns do
    case :io.columns() do
      {:ok, cols} -> cols
      _ -> 80
    end
  end

  @doc """
  Returns the terminal height in rows.

  Falls back to 24 if the terminal height cannot be determined.
  """
  @spec rows() :: pos_integer()
  def rows do
    case :io.rows() do
      {:ok, rows} -> rows
      _ -> 24
    end
  end

  @doc """
  Returns true if the terminal supports colors.

  This checks that:
  - stdout is an interactive terminal
  - the NO_COLOR environment variable is not set

  The NO_COLOR convention (https://no-color.org/) allows users to disable
  colors in all supporting applications.
  """
  @spec supports_color?() :: boolean()
  def supports_color? do
    interactive?() and System.get_env("NO_COLOR") == nil
  end

  @doc """
  Returns true if the terminal supports 256 colors.

  Checks for "256color" in the TERM environment variable.
  """
  @spec supports_256_color?() :: boolean()
  def supports_256_color? do
    supports_color?() and
      String.contains?(System.get_env("TERM", ""), "256color")
  end

  @doc """
  Returns true if the terminal supports true color (24-bit RGB).

  Checks the COLORTERM environment variable for "truecolor" or "24bit".
  """
  @spec supports_truecolor?() :: boolean()
  def supports_truecolor? do
    supports_color?() and
      System.get_env("COLORTERM") in ["truecolor", "24bit"]
  end

  @doc """
  Resolves the color mode based on the given option and terminal capabilities.

  ## Options

    * `:auto` - Enable colors if terminal supports them (default)
    * `:always` - Always enable colors (unless NO_COLOR is set)
    * `:never` - Never enable colors

  Note: NO_COLOR takes precedence even over `:always`.
  """
  @spec resolve_color_mode(atom()) :: boolean()
  def resolve_color_mode(mode \\ :auto)

  def resolve_color_mode(:auto), do: supports_color?()

  def resolve_color_mode(:always) do
    # NO_COLOR takes precedence even over explicit --color=always
    System.get_env("NO_COLOR") == nil
  end

  def resolve_color_mode(:never), do: false

  def resolve_color_mode(_), do: supports_color?()
end
