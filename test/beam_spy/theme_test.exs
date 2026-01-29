defmodule BeamSpy.ThemeTest do
  use ExUnit.Case, async: true
  use Mneme

  alias BeamSpy.Theme

  describe "load/1" do
    test "loads bundled default theme" do
      assert {:ok, theme} = Theme.load("default")
      assert theme.name == "Default"
      assert theme.variant == :dark
      assert is_map(theme.colors)
    end

    test "loads bundled monokai theme" do
      assert {:ok, theme} = Theme.load("monokai")
      assert theme.name == "Monokai"
      assert theme.variant == :dark
    end

    test "returns error for unknown theme" do
      assert {:error, :not_found} = Theme.load("nonexistent_theme")
    end

    test "theme has expected color definitions" do
      {:ok, theme} = Theme.load("default")

      # Check some expected colors exist
      assert Map.has_key?(theme.colors, "atom")
      assert Map.has_key?(theme.colors, "opcode.call")
      assert Map.has_key?(theme.colors, "register.x")
    end

    test "loads light variant theme" do
      assert {:ok, theme} = Theme.load("default-light")
      assert theme.variant == :light
    end

    test "loads all bundled themes without error" do
      for theme_name <- [
            "default",
            "monokai",
            "dracula",
            "nord",
            "plain",
            "solarized-dark",
            "solarized-light",
            "default-light"
          ] do
        assert {:ok, _theme} = Theme.load(theme_name), "Failed to load theme: #{theme_name}"
      end
    end
  end

  describe "load!/1" do
    test "returns theme on success" do
      theme = Theme.load!("default")
      assert theme.name == "Default"
    end

    test "raises on failure" do
      assert_raise RuntimeError, ~r/Failed to load theme/, fn ->
        Theme.load!("nonexistent")
      end
    end
  end

  describe "default/0" do
    test "returns a theme" do
      theme = Theme.default()
      assert %Theme{} = theme
      assert is_map(theme.colors)
    end

    test "default theme has required colors" do
      theme = Theme.default()
      assert Map.has_key?(theme.colors, "atom")
      assert Map.has_key?(theme.colors, "ui.header")
      assert Map.has_key?(theme.colors, "opcode.call")
    end
  end

  describe "list/0" do
    test "returns list of available themes" do
      themes = Theme.list()
      assert is_list(themes)
      assert "default" in themes
      assert "monokai" in themes
    end

    test "returns sorted list" do
      themes = Theme.list()
      assert themes == Enum.sort(themes)
    end

    test "contains all bundled themes" do
      themes = Theme.list()

      expected = [
        "default",
        "default-light",
        "dracula",
        "monokai",
        "nord",
        "plain",
        "solarized-dark",
        "solarized-light"
      ]

      for theme <- expected do
        assert theme in themes, "Missing theme: #{theme}"
      end
    end
  end

  describe "styled/3" do
    test "applies color to text when colors enabled" do
      theme = Theme.default()

      # Can't easily test ANSI output in automated tests since
      # Terminal.supports_color?() returns false in test env
      # Just verify it doesn't crash
      result = Theme.styled("test", "atom", theme)
      assert is_binary(result) or is_list(result)
    end

    test "returns plain text for unknown element" do
      theme = Theme.default()
      result = Theme.styled("test", "unknown_element", theme)
      # Should return the original text
      text = if is_list(result), do: IO.iodata_to_binary(result), else: result
      assert text =~ "test"
    end

    test "handles nil element gracefully" do
      theme = Theme.default()
      result = Theme.styled("test", "nonexistent.element", theme)
      text = if is_list(result), do: IO.iodata_to_binary(result), else: result
      assert text == "test"
    end
  end

  describe "styled_string/3" do
    test "returns a binary string" do
      theme = Theme.default()
      result = Theme.styled_string("test", "atom", theme)
      assert is_binary(result)
    end

    test "converts iolist to binary" do
      theme = Theme.default()
      result = Theme.styled_string("hello world", "ui.header", theme)
      assert is_binary(result)
      assert result =~ "hello world"
    end
  end

  describe "theme variants" do
    test "dark themes have :dark variant" do
      for theme_name <- ["default", "monokai", "dracula", "nord", "solarized-dark"] do
        {:ok, theme} = Theme.load(theme_name)
        assert theme.variant == :dark, "Expected #{theme_name} to have :dark variant"
      end
    end

    test "light themes have :light variant" do
      for theme_name <- ["default-light", "solarized-light"] do
        {:ok, theme} = Theme.load(theme_name)
        assert theme.variant == :light, "Expected #{theme_name} to have :light variant"
      end
    end
  end

  describe "color categories" do
    test "themes have UI colors" do
      {:ok, theme} = Theme.load("default")
      ui_keys = ["ui.header", "ui.border", "ui.dim", "ui.key", "ui.value"]

      for key <- ui_keys do
        assert Map.has_key?(theme.colors, key), "Missing UI color: #{key}"
      end
    end

    test "themes have opcode colors" do
      {:ok, theme} = Theme.load("default")
      opcode_keys = ["opcode.call", "opcode.control", "opcode.data", "opcode.return"]

      for key <- opcode_keys do
        assert Map.has_key?(theme.colors, key), "Missing opcode color: #{key}"
      end
    end

    test "themes have register colors" do
      {:ok, theme} = Theme.load("default")
      register_keys = ["register.x", "register.y"]

      for key <- register_keys do
        assert Map.has_key?(theme.colors, key), "Missing register color: #{key}"
      end
    end
  end

  describe "snapshot tests" do
    @tag :snapshot
    test "default theme color definitions" do
      {:ok, theme} = Theme.load("default")
      assert %{name: "Default", variant: :dark} = Map.take(theme, [:name, :variant])
      assert Map.has_key?(theme.colors, "atom")
      assert Map.has_key?(theme.colors, "opcode.call")
    end

    @tag :snapshot
    test "monokai theme color definitions" do
      {:ok, theme} = Theme.load("monokai")
      assert %{name: "Monokai", variant: :dark} = Map.take(theme, [:name, :variant])
    end

    @tag :snapshot
    test "theme list is stable" do
      themes = Theme.list() |> Enum.sort()

      assert themes == [
               "default",
               "default-light",
               "dracula",
               "monokai",
               "nord",
               "plain",
               "solarized-dark",
               "solarized-light"
             ]
    end

    @tag :snapshot
    test "all bundled themes load successfully" do
      for theme_name <- Theme.list() do
        assert {:ok, theme} = Theme.load(theme_name)
        assert is_binary(theme.name)
        assert theme.variant in [:dark, :light]
        assert map_size(theme.colors) > 0
      end
    end
  end
end
