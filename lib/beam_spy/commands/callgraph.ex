defmodule BeamSpy.Commands.Callgraph do
  @moduledoc """
  Build a function call graph from BEAM bytecode.

  Analyzes the disassembled bytecode to identify function calls
  and builds a graph of call relationships.
  """

  alias BeamSpy.Format
  alias BeamSpy.Theme

  @type edge :: {String.t(), String.t()}
  @type graph :: %{nodes: [String.t()], edges: [edge()]}

  @doc """
  Extract call graph from a BEAM file.

  Returns `{:ok, graph}` where graph contains nodes and edges.
  """
  @spec extract(String.t(), keyword()) :: {:ok, graph()} | {:error, term()}
  def extract(path, _opts \\ []) do
    case :beam_disasm.file(to_charlist(path)) do
      {:beam_file, module, _exports, _attr, _compile_info, functions} ->
        graph = build_graph(module, functions)
        {:ok, graph}

      {:error, _beam_lib, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Run callgraph extraction and format output.
  """
  @spec run(String.t(), keyword()) :: String.t()
  def run(path, opts \\ []) do
    case extract(path, opts) do
      {:ok, graph} ->
        format_output(graph, opts)

      {:error, reason} ->
        "Error: #{inspect(reason)}"
    end
  end

  # Build the call graph from disassembled functions
  defp build_graph(module, functions) do
    # Collect all local functions as nodes
    local_nodes =
      for {:function, name, arity, _entry, _instructions} <- functions do
        format_mfa(module, name, arity)
      end

    # Collect all edges (calls) from each function
    {edges, external_nodes} =
      Enum.reduce(functions, {[], MapSet.new()}, fn
        {:function, name, arity, _entry, instructions}, {edges_acc, ext_acc} ->
          caller = format_mfa(module, name, arity)
          {new_edges, new_ext} = extract_calls(caller, module, instructions)
          {edges_acc ++ new_edges, MapSet.union(ext_acc, new_ext)}
      end)

    # All nodes = local functions + external functions
    all_nodes = local_nodes ++ MapSet.to_list(external_nodes)

    %{
      nodes: Enum.uniq(all_nodes),
      edges: Enum.uniq(edges)
    }
  end

  # Extract call edges from a function's instructions
  defp extract_calls(caller, _module, instructions) do
    Enum.reduce(instructions, {[], MapSet.new()}, fn inst, {edges, ext} ->
      case extract_call_target(inst) do
        nil ->
          {edges, ext}

        {:external, mod, name, arity} ->
          callee = format_mfa(mod, name, arity)
          {[{caller, callee} | edges], MapSet.put(ext, callee)}
      end
    end)
  end

  # Extract call target from an instruction
  # Need label resolution
  defp extract_call_target({:call, _arity, {:f, _label}}), do: nil

  defp extract_call_target({:call_ext, _arity, {:extfunc, mod, name, arity}}) do
    {:external, mod, name, arity}
  end

  defp extract_call_target({:call_ext_only, _arity, {:extfunc, mod, name, arity}}) do
    {:external, mod, name, arity}
  end

  defp extract_call_target({:call_ext_last, _arity, {:extfunc, mod, name, arity}, _}) do
    {:external, mod, name, arity}
  end

  # Dynamic call
  defp extract_call_target({:call_fun, _arity}), do: nil
  # Dynamic call
  defp extract_call_target({:call_fun2, _, _, _}), do: nil
  # Dynamic call
  defp extract_call_target({:apply, _}), do: nil
  # Dynamic call
  defp extract_call_target({:apply_last, _, _}), do: nil

  defp extract_call_target({:bif0, {:extfunc, mod, name, arity}, _}) do
    {:external, mod, name, arity}
  end

  defp extract_call_target({:bif1, _, {:extfunc, mod, name, arity}, _, _}) do
    {:external, mod, name, arity}
  end

  defp extract_call_target({:bif2, _, {:extfunc, mod, name, arity}, _, _, _}) do
    {:external, mod, name, arity}
  end

  defp extract_call_target({:gc_bif1, _, _, {:extfunc, mod, name, arity}, _, _}) do
    {:external, mod, name, arity}
  end

  defp extract_call_target({:gc_bif2, _, _, {:extfunc, mod, name, arity}, _, _, _}) do
    {:external, mod, name, arity}
  end

  defp extract_call_target({:gc_bif3, _, _, {:extfunc, mod, name, arity}, _, _, _, _}) do
    {:external, mod, name, arity}
  end

  defp extract_call_target(_), do: nil

  defp format_mfa(module, name, arity) do
    "#{module}.#{name}/#{arity}"
  end

  # Format output based on options
  defp format_output(graph, opts) do
    theme = Keyword.get(opts, :theme, Theme.default())

    case Keyword.get(opts, :format, :text) do
      :json -> format_json(graph)
      :dot -> format_dot(graph)
      :text -> format_text(graph, theme)
      _ -> format_text(graph, theme)
    end
  end

  defp format_json(graph) do
    data = %{
      nodes: graph.nodes,
      edges:
        Enum.map(graph.edges, fn {from, to} ->
          %{from: from, to: to}
        end)
    }

    Format.json(data)
  end

  defp format_dot(graph) do
    edges =
      graph.edges
      |> Enum.map(fn {from, to} ->
        ~s(  "#{escape_dot(from)}" -> "#{escape_dot(to)}";)
      end)
      |> Enum.join("\n")

    # Add nodes with no outgoing edges
    isolated_nodes =
      graph.nodes
      |> Enum.reject(fn node ->
        Enum.any?(graph.edges, fn {from, _} -> from == node end)
      end)
      |> Enum.map(fn node -> ~s(  "#{escape_dot(node)}";) end)
      |> Enum.join("\n")

    """
    digraph callgraph {
      rankdir=LR;
      node [shape=box, fontname="monospace"];

    #{isolated_nodes}
    #{edges}
    }
    """
  end

  defp escape_dot(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
  end

  defp format_text(graph, theme) do
    # Group edges by caller
    by_caller =
      graph.edges
      |> Enum.group_by(fn {from, _} -> from end, fn {_, to} -> to end)

    # Also include nodes with no calls
    all_callers = graph.nodes

    all_callers
    |> Enum.map(fn caller ->
      styled_caller = Theme.styled_string(caller, "function", theme)
      callees = Map.get(by_caller, caller, [])

      if Enum.empty?(callees) do
        dim_text = Theme.styled_string("(no calls)", "ui.dim", theme)
        "#{styled_caller}\n  #{dim_text}"
      else
        arrow = Theme.styled_string("→", "ui.arrow", theme)

        calls =
          Enum.map_join(callees, "\n", fn callee ->
            styled_callee = Theme.styled_string(callee, "function", theme)
            "  #{arrow} #{styled_callee}"
          end)

        "#{styled_caller}\n#{calls}"
      end
    end)
    |> Enum.join("\n\n")
  end
end
