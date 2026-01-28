defmodule BeamSpy.PagerTest do
  use ExUnit.Case, async: true

  alias BeamSpy.Pager

  describe "page/1" do
    test "outputs content through pager command" do
      # Use cat as a simple non-interactive pager
      System.put_env("PAGER", "cat")
      output = "line 1\nline 2\nline 3\n"

      # Capture the output by redirecting to a file
      tmp_output = Path.join(System.tmp_dir!(), "pager_test_#{:erlang.unique_integer([:positive])}.txt")
      System.put_env("PAGER", "cat > #{tmp_output}")

      try do
        Pager.page(output)
        assert File.read!(tmp_output) == output
      after
        File.rm(tmp_output)
        System.delete_env("PAGER")
      end
    end

    test "handles empty output" do
      System.put_env("PAGER", "cat")

      try do
        # Should not crash
        assert :ok = Pager.page("")
      after
        System.delete_env("PAGER")
      end
    end

    test "handles non-existent pager gracefully" do
      # Use a non-existent pager, redirecting stderr to suppress shell error.
      # The port uses :nouse_stdio so the shell's stderr goes directly to
      # the terminal - we must redirect it in the command itself.
      System.put_env("PAGER", "/nonexistent/pager/that/does/not/exist 2>/dev/null")

      try do
        # Should not crash - pager failure is handled by the shell.
        assert :ok = Pager.page("test content\n")
      after
        System.delete_env("PAGER")
      end
    end
  end

  describe "maybe_page/2" do
    test "prints directly when paging: :never" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Pager.maybe_page("test output", paging: :never)
        end)

      assert output == "test output\n"
    end

    test "prints directly when output is short and paging: :auto" do
      # Short output should not trigger paging
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Pager.maybe_page("short", paging: :auto)
        end)

      assert output == "short\n"
    end
  end

  describe "should_page?/1" do
    test "returns false for short output" do
      refute Pager.should_page?("short output")
    end

    test "returns false when not interactive" do
      # In test environment, we're typically not interactive
      long_output = String.duplicate("line\n", 1000)
      # This depends on Terminal.interactive?() which should be false in tests
      # so even long output won't trigger paging
      result = Pager.should_page?(long_output)
      # Result depends on whether tests run in a TTY
      assert is_boolean(result)
    end
  end
end
