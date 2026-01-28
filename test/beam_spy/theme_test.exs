defmodule BeamSpy.ThemeTest do
  use ExUnit.Case, async: true

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
  end

  describe "load!/1" do
    test "returns theme on success" do
      theme = Theme.load!("default")
      assert theme.name == "Default"
    end

    test "raises on failure" do
      assert_raise RuntimeError, fn ->
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
  end

  describe "list/0" do
    test "returns list of available themes" do
      themes = Theme.list()
      assert is_list(themes)
      assert "default" in themes
      assert "monokai" in themes
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
  end

  describe "styled_string/3" do
    test "returns a binary string" do
      theme = Theme.default()
      result = Theme.styled_string("test", "atom", theme)
      assert is_binary(result)
    end
  end
end
