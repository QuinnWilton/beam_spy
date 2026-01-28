defmodule BeamSpy.FilterTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias BeamSpy.Filter

  describe "substring/1" do
    test "creates a substring filter" do
      filter = Filter.substring("error")
      assert {:substring, "error"} = filter
    end

    test "lowercases the pattern" do
      filter = Filter.substring("ERROR")
      assert {:substring, "error"} = filter
    end
  end

  describe "regex/1" do
    test "creates a regex filter" do
      filter = Filter.regex("^handle_[a-z]+$")
      assert {:regex, %Regex{}} = filter
    end

    test "raises on invalid regex" do
      assert_raise Regex.CompileError, fn ->
        Filter.regex("[invalid")
      end
    end
  end

  describe "glob/1" do
    test "creates a glob filter" do
      filter = Filter.glob("handle_*")
      assert {:glob, "handle_*", %Regex{}} = filter
    end

    test "preserves original pattern" do
      filter = Filter.glob("foo?bar*")
      assert {:glob, "foo?bar*", _} = filter
    end
  end

  describe "matches?/2 with substring" do
    test "matches case-insensitively" do
      filter = Filter.substring("error")
      assert Filter.matches?(filter, "ErrorHandler")
      assert Filter.matches?(filter, "handle_error")
      assert Filter.matches?(filter, "ERROR")
    end

    test "does not match when substring is absent" do
      filter = Filter.substring("error")
      refute Filter.matches?(filter, "success")
      refute Filter.matches?(filter, "warning")
    end

    test "works with atoms" do
      filter = Filter.substring("info")
      assert Filter.matches?(filter, :module_info)
      assert Filter.matches?(filter, :__info__)
    end

    test "empty pattern matches everything" do
      filter = Filter.substring("")
      assert Filter.matches?(filter, "anything")
      assert Filter.matches?(filter, "")
    end
  end

  describe "matches?/2 with regex" do
    test "matches regex patterns" do
      filter = Filter.regex("^handle_[a-z]+$")
      assert Filter.matches?(filter, "handle_call")
      assert Filter.matches?(filter, "handle_cast")
      assert Filter.matches?(filter, "handle_info")
    end

    test "does not match partial regex" do
      filter = Filter.regex("^handle_[a-z]+$")
      refute Filter.matches?(filter, "do_handle_call")
      refute Filter.matches?(filter, "handle_call_async")
      refute Filter.matches?(filter, "handle_123")
    end

    test "works with atoms" do
      filter = Filter.regex("^__.*__$")
      assert Filter.matches?(filter, :__info__)
      refute Filter.matches?(filter, :info)
    end
  end

  describe "matches?/2 with glob" do
    test "matches * wildcard" do
      filter = Filter.glob("handle_*")
      assert Filter.matches?(filter, "handle_call")
      assert Filter.matches?(filter, "handle_")
      assert Filter.matches?(filter, "handle_anything")
    end

    test "does not match without prefix" do
      filter = Filter.glob("handle_*")
      refute Filter.matches?(filter, "do_handle_call")
    end

    test "matches ? wildcard" do
      filter = Filter.glob("get_?")
      assert Filter.matches?(filter, "get_x")
      assert Filter.matches?(filter, "get_1")
      refute Filter.matches?(filter, "get_xy")
      refute Filter.matches?(filter, "get_")
    end

    test "matches combined wildcards" do
      filter = Filter.glob("*_?")
      assert Filter.matches?(filter, "foo_x")
      assert Filter.matches?(filter, "bar_baz_1")
      refute Filter.matches?(filter, "foo")
    end

    test "works with atoms" do
      filter = Filter.glob("module_*")
      assert Filter.matches?(filter, :module_info)
      refute Filter.matches?(filter, :info)
    end

    test "matches exact string without wildcards" do
      filter = Filter.glob("exact")
      assert Filter.matches?(filter, "exact")
      refute Filter.matches?(filter, "not_exact")
    end
  end

  describe "filter_list/2" do
    test "filters a list of strings" do
      filter = Filter.substring("error")
      items = ["error_handler", "success", "error_log", "warning"]
      result = Filter.filter_list(filter, items)
      assert result == ["error_handler", "error_log"]
    end

    test "filters a list of atoms" do
      filter = Filter.glob("handle_*")
      items = [:handle_call, :handle_cast, :init, :terminate]
      result = Filter.filter_list(filter, items)
      assert result == [:handle_call, :handle_cast]
    end

    test "returns empty list when nothing matches" do
      filter = Filter.substring("nonexistent")
      items = ["foo", "bar", "baz"]
      assert Filter.filter_list(filter, items) == []
    end
  end

  describe "parse/1" do
    test "parses plain string as substring" do
      assert {:ok, {:substring, "error"}} = Filter.parse("error")
    end

    test "parses re: prefix as regex" do
      assert {:ok, {:regex, %Regex{}}} = Filter.parse("re:^handle_")
    end

    test "parses regex: prefix as regex" do
      assert {:ok, {:regex, %Regex{}}} = Filter.parse("regex:^handle_")
    end

    test "parses glob: prefix as glob" do
      assert {:ok, {:glob, "handle_*", %Regex{}}} = Filter.parse("glob:handle_*")
    end

    test "returns error for invalid regex" do
      assert {:error, msg} = Filter.parse("re:[invalid")
      assert msg =~ "Invalid regex"
    end
  end

  # Property tests
  describe "property tests" do
    property "filtered results are always subset of input" do
      check all(
              items <- list_of(string(:alphanumeric, min_length: 1), min_length: 1),
              pattern <- string(:alphanumeric, min_length: 1)
            ) do
        filter = Filter.substring(pattern)
        filtered = Filter.filter_list(filter, items)

        assert MapSet.subset?(MapSet.new(filtered), MapSet.new(items))
      end
    end

    property "empty substring matches everything" do
      check all(items <- list_of(string(:alphanumeric))) do
        filter = Filter.substring("")
        filtered = Filter.filter_list(filter, items)
        assert filtered == items
      end
    end

    property "glob without wildcards matches exactly" do
      check all(exact <- string(:alphanumeric, min_length: 1)) do
        filter = Filter.glob(exact)
        assert Filter.matches?(filter, exact)
        refute Filter.matches?(filter, exact <> "extra")
        refute Filter.matches?(filter, "prefix" <> exact)
      end
    end

    property "regex anchored patterns match exactly" do
      check all(exact <- string(:alphanumeric, min_length: 1)) do
        escaped = Regex.escape(exact)
        filter = Filter.regex("^#{escaped}$")
        assert Filter.matches?(filter, exact)
      end
    end
  end
end
