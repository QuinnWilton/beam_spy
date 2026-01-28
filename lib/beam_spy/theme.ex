defmodule BeamSpy.Theme do
  @moduledoc """
  Theme loading and style application for BeamSpy output.

  Themes are TOML files that define colors for various elements:
  - UI elements: headers, borders, keys, values
  - Data types: atoms, modules, functions, numbers
  - Opcodes: call, control, data, stack, etc.
  - Registers: x, y, fr

  Themes are loaded from:
  1. Bundled themes (in priv/themes/)
  2. User themes (~/.config/beam_spy/themes/)
  """

  alias BeamSpy.Terminal

  defstruct [:name, :variant, :colors]

  @type color :: atom() | String.t() | {non_neg_integer(), non_neg_integer(), non_neg_integer()}
  @type style :: color() | %{fg: color(), bg: color() | nil, style: atom() | [atom()]}
  @type t :: %__MODULE__{
          name: String.t(),
          variant: :dark | :light,
          colors: %{String.t() => style()}
        }

  # Path to bundled themes
  @themes_dir Path.join(:code.priv_dir(:beam_spy), "themes")

  # User config directory
  @user_themes_dir Path.join([System.user_home() || "~", ".config", "beam_spy", "themes"])

  @doc """
  Load a theme by name.

  Searches in order:
  1. User themes directory
  2. Bundled themes directory
  """
  @spec load(String.t()) :: {:ok, t()} | {:error, term()}
  def load(name) do
    with {:ok, path} <- find_theme(name),
         {:ok, content} <- File.read(path),
         {:ok, parsed} <- Toml.decode(content) do
      {:ok, from_toml(parsed)}
    end
  end

  @doc """
  Load a theme by name, raising on error.
  """
  @spec load!(String.t()) :: t()
  def load!(name) do
    case load(name) do
      {:ok, theme} -> theme
      {:error, reason} -> raise "Failed to load theme #{name}: #{inspect(reason)}"
    end
  end

  @doc """
  Get the default theme based on terminal capabilities.
  """
  @spec default() :: t()
  def default do
    case load("default") do
      {:ok, theme} -> theme
      {:error, _} -> fallback_theme()
    end
  end

  @doc """
  List available themes.
  """
  @spec list() :: [String.t()]
  def list do
    bundled = list_themes(@themes_dir)
    user = list_themes(@user_themes_dir)

    (bundled ++ user)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Apply a style to text based on theme element.

  Returns an IO list with ANSI codes if colors are enabled.
  """
  @spec styled(String.t(), String.t(), t()) :: iodata()
  def styled(text, element, theme) do
    if Terminal.supports_color?() do
      case Map.get(theme.colors, element) do
        nil -> text
        style -> apply_style(text, style)
      end
    else
      text
    end
  end

  @doc """
  Apply a style to text, returning a binary string.
  """
  @spec styled_string(String.t(), String.t(), t()) :: String.t()
  def styled_string(text, element, theme) do
    styled(text, element, theme) |> IO.iodata_to_binary()
  end

  # Find theme file path
  defp find_theme(name) do
    user_path = Path.join(@user_themes_dir, "#{name}.toml")
    bundled_path = Path.join(@themes_dir, "#{name}.toml")

    cond do
      File.exists?(user_path) -> {:ok, user_path}
      File.exists?(bundled_path) -> {:ok, bundled_path}
      true -> {:error, :not_found}
    end
  end

  defp list_themes(dir) do
    if File.dir?(dir) do
      dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".toml"))
      |> Enum.map(&String.trim_trailing(&1, ".toml"))
    else
      []
    end
  end

  defp from_toml(parsed) do
    %__MODULE__{
      name: Map.get(parsed, "name", "unknown"),
      variant: parse_variant(Map.get(parsed, "variant", "dark")),
      colors: Map.get(parsed, "colors", %{})
    }
  end

  defp parse_variant("dark"), do: :dark
  defp parse_variant("light"), do: :light
  defp parse_variant(_), do: :dark

  # Apply ANSI style to text
  defp apply_style(text, style) when is_atom(style) do
    [ansi_code(style), text, IO.ANSI.reset()]
  end

  defp apply_style(text, style) when is_binary(style) do
    [ansi_code(String.to_atom(style)), text, IO.ANSI.reset()]
  end

  defp apply_style(text, %{} = style) do
    codes = []

    codes =
      case Map.get(style, "style") do
        nil -> codes
        s -> [ansi_code(String.to_atom(s)) | codes]
      end

    codes =
      case Map.get(style, "fg") do
        nil -> codes
        fg -> [ansi_code(parse_color(fg)) | codes]
      end

    codes =
      case Map.get(style, "bg") do
        nil -> codes
        bg -> [ansi_bg_code(parse_color(bg)) | codes]
      end

    [Enum.reverse(codes), text, IO.ANSI.reset()]
  end

  defp parse_color(color) when is_atom(color), do: color
  defp parse_color(color) when is_binary(color), do: String.to_atom(color)
  defp parse_color(_), do: :default

  # Map color names to ANSI codes
  defp ansi_code(:black), do: IO.ANSI.black()
  defp ansi_code(:red), do: IO.ANSI.red()
  defp ansi_code(:green), do: IO.ANSI.green()
  defp ansi_code(:yellow), do: IO.ANSI.yellow()
  defp ansi_code(:blue), do: IO.ANSI.blue()
  defp ansi_code(:magenta), do: IO.ANSI.magenta()
  defp ansi_code(:cyan), do: IO.ANSI.cyan()
  defp ansi_code(:white), do: IO.ANSI.white()
  defp ansi_code(:bright_black), do: IO.ANSI.light_black()
  defp ansi_code(:bright_red), do: IO.ANSI.light_red()
  defp ansi_code(:bright_green), do: IO.ANSI.light_green()
  defp ansi_code(:bright_yellow), do: IO.ANSI.light_yellow()
  defp ansi_code(:bright_blue), do: IO.ANSI.light_blue()
  defp ansi_code(:bright_magenta), do: IO.ANSI.light_magenta()
  defp ansi_code(:bright_cyan), do: IO.ANSI.light_cyan()
  defp ansi_code(:bright_white), do: IO.ANSI.light_white()
  defp ansi_code(:bold), do: IO.ANSI.bright()
  defp ansi_code(:dim), do: IO.ANSI.faint()
  defp ansi_code(:italic), do: IO.ANSI.italic()
  defp ansi_code(:underline), do: IO.ANSI.underline()
  defp ansi_code(:default), do: IO.ANSI.default_color()
  defp ansi_code(_), do: ""

  defp ansi_bg_code(:black), do: IO.ANSI.black_background()
  defp ansi_bg_code(:red), do: IO.ANSI.red_background()
  defp ansi_bg_code(:green), do: IO.ANSI.green_background()
  defp ansi_bg_code(:yellow), do: IO.ANSI.yellow_background()
  defp ansi_bg_code(:blue), do: IO.ANSI.blue_background()
  defp ansi_bg_code(:magenta), do: IO.ANSI.magenta_background()
  defp ansi_bg_code(:cyan), do: IO.ANSI.cyan_background()
  defp ansi_bg_code(:white), do: IO.ANSI.white_background()
  defp ansi_bg_code(_), do: ""

  # Fallback theme when no theme files are available
  defp fallback_theme do
    %__MODULE__{
      name: "fallback",
      variant: :dark,
      colors: %{
        "ui.header" => :white,
        "ui.border" => :bright_black,
        "ui.key" => :cyan,
        "ui.value" => :default,
        "atom" => :cyan,
        "atom.special" => :cyan,
        "module" => :yellow,
        "function" => :green,
        "number" => :magenta,
        "string" => :green,
        "opcode.call" => :green,
        "opcode.control" => :magenta,
        "opcode.data" => :default,
        "opcode.stack" => :default,
        "opcode.return" => :red,
        "opcode.exception" => :cyan,
        "opcode.error" => :red,
        "opcode.message" => :blue,
        "opcode.binary" => :yellow,
        "opcode.meta" => :bright_black,
        "register.x" => :yellow,
        "register.y" => :bright_yellow,
        "register.fr" => :bright_cyan,
        "label" => :yellow
      }
    }
  end
end
