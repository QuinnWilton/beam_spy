defmodule BeamSpy.Commands.CallgraphTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias BeamSpy.Commands.Callgraph
  alias BeamSpy.Test.Helpers

  @test_beam_path :code.which(:lists) |> to_string()

  describe "extract/2" do
    test "extracts graph from beam file" do
      assert {:ok, graph} = Callgraph.extract(@test_beam_path)
      assert is_list(graph.nodes)
      assert is_list(graph.edges)
      assert length(graph.nodes) > 0
    end

    test "nodes contain module functions" do
      {:ok, graph} = Callgraph.extract(@test_beam_path)

      # Should contain known functions from :lists
      assert Enum.any?(graph.nodes, &String.contains?(&1, "lists.map/2"))
      assert Enum.any?(graph.nodes, &String.contains?(&1, "lists.reverse/1"))
    end

    test "edges reference existing nodes" do
      {:ok, graph} = Callgraph.extract(@test_beam_path)

      for {from, to} <- graph.edges do
        assert from in graph.nodes, "Edge source #{from} not in nodes"
        assert to in graph.nodes, "Edge target #{to} not in nodes"
      end
    end

    test "edges contain external calls to erlang" do
      {:ok, graph} = Callgraph.extract(@test_beam_path)

      # lists module should call erlang functions
      erlang_calls =
        Enum.filter(graph.edges, fn {_from, to} ->
          String.starts_with?(to, "erlang.")
        end)

      assert length(erlang_calls) > 0
    end

    test "returns error for invalid file" do
      assert {:error, _} = Callgraph.extract("/nonexistent/file.beam")
    end
  end

  describe "run/2 text format" do
    test "outputs function names with calls" do
      output = Callgraph.run(@test_beam_path, format: :text)
      assert is_binary(output)
      assert output =~ "lists."
      # Arrow for call edges
      assert output =~ "→"
    end

    test "shows functions with no calls" do
      output = Callgraph.run(@test_beam_path, format: :text)
      # Some functions should have "(no calls)"
      assert output =~ "(no calls)" or output =~ "→"
    end
  end

  describe "run/2 json format" do
    test "outputs valid JSON" do
      output = Callgraph.run(@test_beam_path, format: :json)
      {:ok, decoded} = Jason.decode(output)

      assert Map.has_key?(decoded, "nodes")
      assert Map.has_key?(decoded, "edges")
      assert is_list(decoded["nodes"])
      assert is_list(decoded["edges"])
    end

    test "edges have from and to fields" do
      output = Callgraph.run(@test_beam_path, format: :json)
      {:ok, decoded} = Jason.decode(output)

      for edge <- decoded["edges"] do
        assert Map.has_key?(edge, "from")
        assert Map.has_key?(edge, "to")
      end
    end
  end

  describe "run/2 dot format" do
    test "outputs valid DOT graph" do
      output = Callgraph.run(@test_beam_path, format: :dot)

      assert output =~ "digraph callgraph"
      assert output =~ "rankdir=LR"
      assert output =~ "->"
      assert String.ends_with?(String.trim(output), "}")
    end

    test "escapes special characters in DOT" do
      output = Callgraph.run(@test_beam_path, format: :dot)

      # Should not have unescaped quotes in node names
      # (other than the wrapping quotes)
      lines = String.split(output, "\n")

      for line <- lines do
        if String.contains?(line, "->") or String.match?(line, ~r/^\s*"[^"]+";$/) do
          # Count quotes - should be even
          quote_count = line |> String.graphemes() |> Enum.count(&(&1 == "\""))
          assert rem(quote_count, 2) == 0, "Unbalanced quotes in: #{line}"
        end
      end
    end
  end

  describe "property tests" do
    @stdlib_modules [Enum, List, Map, String, :lists, :maps, :ets]

    property "graph edges only reference existing nodes" do
      check all(module <- member_of(@stdlib_modules)) do
        beam_path = Helpers.beam_path(module)
        {:ok, graph} = Callgraph.extract(beam_path)

        for {from, to} <- graph.edges do
          assert from in graph.nodes, "Edge source #{from} not in nodes"
          assert to in graph.nodes, "Edge target #{to} not in nodes"
        end
      end
    end

    property "DOT output has valid basic syntax" do
      check all(module <- member_of(@stdlib_modules)) do
        beam_path = Helpers.beam_path(module)
        dot = Callgraph.run(beam_path, format: :dot)

        # Must start with digraph declaration
        assert dot =~ ~r/^digraph\s+\w+\s*\{/

        # Must end with closing brace
        assert String.trim(dot) |> String.ends_with?("}")

        # All edge lines should have balanced quotes
        lines = String.split(dot, "\n")

        for line <- lines, String.contains?(line, "->") do
          quote_count = line |> String.graphemes() |> Enum.count(&(&1 == "\""))
          assert rem(quote_count, 2) == 0, "Unbalanced quotes in: #{line}"
        end
      end
    end

    property "JSON output has valid structure" do
      check all(module <- member_of(@stdlib_modules)) do
        beam_path = Helpers.beam_path(module)
        output = Callgraph.run(beam_path, format: :json)

        {:ok, decoded} = Jason.decode(output)
        assert is_list(decoded["nodes"])
        assert is_list(decoded["edges"])

        # All edges should have from and to
        for edge <- decoded["edges"] do
          assert Map.has_key?(edge, "from")
          assert Map.has_key?(edge, "to")
        end
      end
    end

    property "node count is consistent across formats" do
      check all(module <- member_of(@stdlib_modules)) do
        beam_path = Helpers.beam_path(module)

        {:ok, graph} = Callgraph.extract(beam_path)
        json_output = Callgraph.run(beam_path, format: :json)
        {:ok, json_data} = Jason.decode(json_output)

        # Node count should match between extract and JSON output
        assert length(graph.nodes) == length(json_data["nodes"])
        assert length(graph.edges) == length(json_data["edges"])
      end
    end
  end

  describe "snapshot tests" do
    @tag :snapshot
    test "extract returns graph with nodes and edges" do
      {:ok, graph} = Callgraph.extract(@test_beam_path)

      assert is_list(graph.nodes)
      assert is_list(graph.edges)
      assert length(graph.nodes) > 20

      # Known :lists functions should be nodes
      assert Enum.any?(graph.nodes, &(&1 =~ "lists.map/2"))
      assert Enum.any?(graph.nodes, &(&1 =~ "lists.reverse/1"))
    end

    @tag :snapshot
    test "JSON output structure is stable" do
      output = Callgraph.run(@test_beam_path, format: :json)
      {:ok, decoded} = Jason.decode(output)

      assert Map.has_key?(decoded, "nodes")
      assert Map.has_key?(decoded, "edges")
      assert is_list(decoded["nodes"])
      assert is_list(decoded["edges"])

      # Edges have correct structure
      for edge <- decoded["edges"] do
        assert Map.has_key?(edge, "from")
        assert Map.has_key?(edge, "to")
      end
    end

    @tag :snapshot
    test "DOT output structure is stable" do
      output = Callgraph.run(@test_beam_path, format: :dot)

      assert output =~ "digraph callgraph"
      assert output =~ "rankdir=LR"
      assert String.trim(output) |> String.ends_with?("}")
    end

    @tag :snapshot
    test "text output shows function calls" do
      output = Callgraph.run(@test_beam_path, format: :text)

      assert is_binary(output)
      assert output =~ "lists."
      # Should have call arrows or "no calls" markers
      assert output =~ "→" or output =~ "(no calls)"
    end
  end
end
