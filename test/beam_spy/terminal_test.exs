defmodule BeamSpy.TerminalTest do
  use ExUnit.Case, async: true

  alias BeamSpy.Terminal

  describe "columns/0" do
    test "returns a positive integer" do
      cols = Terminal.columns()
      assert is_integer(cols)
      assert cols > 0
    end

    test "returns actual terminal columns or fallback" do
      cols = Terminal.columns()
      # In a real terminal, returns actual size (could be any positive value)
      # Without a terminal, falls back to 80
      assert cols > 0
    end
  end

  describe "rows/0" do
    test "returns a positive integer" do
      rows = Terminal.rows()
      assert is_integer(rows)
      assert rows > 0
    end

    test "returns actual terminal rows or fallback" do
      rows = Terminal.rows()
      # In a real terminal, returns actual size (could be any positive value)
      # Without a terminal, falls back to 24
      assert rows > 0
    end
  end

  describe "interactive?/0" do
    test "returns a boolean" do
      assert is_boolean(Terminal.interactive?())
    end
  end

  describe "supports_color?/0" do
    test "returns a boolean" do
      assert is_boolean(Terminal.supports_color?())
    end

    test "returns false when NO_COLOR is set" do
      # Save original value
      original = System.get_env("NO_COLOR")

      try do
        System.put_env("NO_COLOR", "1")
        refute Terminal.supports_color?()
      after
        # Restore original value
        if original do
          System.put_env("NO_COLOR", original)
        else
          System.delete_env("NO_COLOR")
        end
      end
    end
  end

  describe "supports_256_color?/0" do
    test "returns a boolean" do
      assert is_boolean(Terminal.supports_256_color?())
    end

    test "checks TERM environment variable for 256color" do
      # In test environment (non-interactive), this always returns false
      # because supports_color?() returns false when not interactive.
      # We just verify it doesn't crash with various TERM values.
      original = System.get_env("TERM")

      try do
        System.put_env("TERM", "xterm-256color")
        assert is_boolean(Terminal.supports_256_color?())

        System.put_env("TERM", "xterm")
        assert is_boolean(Terminal.supports_256_color?())
      after
        if original do
          System.put_env("TERM", original)
        else
          System.delete_env("TERM")
        end
      end
    end
  end

  describe "supports_truecolor?/0" do
    test "returns a boolean" do
      assert is_boolean(Terminal.supports_truecolor?())
    end

    test "checks COLORTERM environment variable" do
      # In test environment (non-interactive), this always returns false.
      # We verify it doesn't crash with various COLORTERM values.
      original = System.get_env("COLORTERM")

      try do
        System.put_env("COLORTERM", "truecolor")
        assert is_boolean(Terminal.supports_truecolor?())

        System.put_env("COLORTERM", "24bit")
        assert is_boolean(Terminal.supports_truecolor?())

        System.delete_env("COLORTERM")
        assert is_boolean(Terminal.supports_truecolor?())
      after
        if original do
          System.put_env("COLORTERM", original)
        else
          System.delete_env("COLORTERM")
        end
      end
    end
  end

  describe "resolve_color_mode/1" do
    test "returns boolean for all valid modes" do
      for mode <- [:auto, :always, :never] do
        assert is_boolean(Terminal.resolve_color_mode(mode))
      end
    end

    test ":never always returns false" do
      refute Terminal.resolve_color_mode(:never)
    end

    test ":always returns false when NO_COLOR is set" do
      original = System.get_env("NO_COLOR")

      try do
        System.put_env("NO_COLOR", "1")
        refute Terminal.resolve_color_mode(:always)
      after
        if original do
          System.put_env("NO_COLOR", original)
        else
          System.delete_env("NO_COLOR")
        end
      end
    end

    test "defaults to :auto for unknown modes" do
      # Unknown modes should behave like :auto
      assert Terminal.resolve_color_mode(:unknown) == Terminal.resolve_color_mode(:auto)
    end

    test ":always returns true when NO_COLOR is not set and environment allows" do
      original = System.get_env("NO_COLOR")

      try do
        System.delete_env("NO_COLOR")
        # :always returns true when NO_COLOR is not set
        assert Terminal.resolve_color_mode(:always) == true
      after
        if original do
          System.put_env("NO_COLOR", original)
        else
          System.delete_env("NO_COLOR")
        end
      end
    end
  end
end
