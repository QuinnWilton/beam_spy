defmodule BeamSpy.Filter do
  @moduledoc """
  Filter parsing and matching for atoms, functions, and other values.

  Supports three filter types:
  - Substring: case-insensitive contains match
  - Regex: full regex pattern matching
  - Glob: shell-style glob patterns (* and ?)

  ## Examples

      iex> filter = BeamSpy.Filter.substring("error")
      iex> BeamSpy.Filter.matches?(filter, "ErrorHandler")
      true

      iex> filter = BeamSpy.Filter.regex("^handle_[a-z]+$")
      iex> BeamSpy.Filter.matches?(filter, "handle_call")
      true

      iex> filter = BeamSpy.Filter.glob("handle_*")
      iex> BeamSpy.Filter.matches?(filter, "handle_info")
      true

  """

  @type t ::
          {:substring, String.t()}
          | {:regex, Regex.t()}
          | {:glob, String.t(), Regex.t()}

  @doc """
  Creates a substring filter.

  Substring matching is case-insensitive.
  """
  @spec substring(String.t()) :: t()
  def substring(pattern) when is_binary(pattern) do
    {:substring, String.downcase(pattern)}
  end

  @doc """
  Creates a regex filter.

  Raises if the pattern is not a valid regex.
  """
  @spec regex(String.t()) :: t()
  def regex(pattern) when is_binary(pattern) do
    {:regex, Regex.compile!(pattern)}
  end

  @doc """
  Creates a glob filter.

  Glob patterns support:
  - `*` matches any sequence of characters
  - `?` matches any single character

  The glob is converted to a regex internally.
  """
  @spec glob(String.t()) :: t()
  def glob(pattern) when is_binary(pattern) do
    regex = glob_to_regex(pattern)
    {:glob, pattern, regex}
  end

  @doc """
  Tests if a value matches the filter.

  The value is converted to a string if necessary.
  """
  @spec matches?(t(), String.t() | atom()) :: boolean()
  def matches?(filter, value) when is_atom(value) do
    matches?(filter, Atom.to_string(value))
  end

  def matches?({:substring, pattern}, value) when is_binary(value) do
    String.contains?(String.downcase(value), pattern)
  end

  def matches?({:regex, regex}, value) when is_binary(value) do
    Regex.match?(regex, value)
  end

  def matches?({:glob, _pattern, regex}, value) when is_binary(value) do
    Regex.match?(regex, value)
  end

  @doc """
  Filters a list of values, keeping only those that match.
  """
  @spec filter_list(t(), [String.t() | atom()]) :: [String.t() | atom()]
  def filter_list(filter, items) do
    Enum.filter(items, &matches?(filter, &1))
  end

  @doc """
  Applies a filter to a list of items, or returns items unchanged if pattern is nil.

  Parses the pattern using `parse/1` to support re:, glob:, and substring prefixes.
  Falls back to substring matching if parsing fails.
  """
  @spec maybe_apply([term()], String.t() | nil) :: [term()]
  def maybe_apply(items, nil), do: items

  def maybe_apply(items, pattern) when is_binary(pattern) do
    case parse(pattern) do
      {:ok, filter} -> filter_list(filter, items)
      {:error, _} -> filter_list(substring(pattern), items)
    end
  end

  @doc """
  Applies a filter to a list of items using a key extraction function.

  Like `maybe_apply/2` but extracts the matchable value from each item using key_fn.
  Useful for filtering lists of tuples or maps.
  """
  @spec maybe_apply_with_key([term()], String.t() | nil, (term() -> term())) :: [term()]
  def maybe_apply_with_key(items, nil, _key_fn), do: items

  def maybe_apply_with_key(items, pattern, key_fn) when is_binary(pattern) do
    case parse(pattern) do
      {:ok, filter} ->
        Enum.filter(items, fn item -> matches?(filter, key_fn.(item)) end)

      {:error, _} ->
        filter = substring(pattern)
        Enum.filter(items, fn item -> matches?(filter, key_fn.(item)) end)
    end
  end

  @doc """
  Parses a filter from a string with optional type prefix.

  If no prefix is given, defaults to substring matching.

  ## Prefixes

  - `re:` or `regex:` - Regex pattern
  - `glob:` - Glob pattern
  - (no prefix) - Substring match

  ## Examples

      iex> BeamSpy.Filter.parse("error")
      {:ok, {:substring, "error"}}

      iex> BeamSpy.Filter.parse("re:^handle_")
      {:ok, {:regex, ~r/^handle_/}}

      iex> BeamSpy.Filter.parse("glob:handle_*")
      {:ok, {:glob, "handle_*", ~r/^handle_.*$/}}

  """
  @spec parse(String.t()) :: {:ok, t()} | {:error, String.t()}
  def parse(input) when is_binary(input) do
    cond do
      String.starts_with?(input, "re:") ->
        pattern = String.slice(input, 3..-1//1)
        parse_regex(pattern)

      String.starts_with?(input, "regex:") ->
        pattern = String.slice(input, 6..-1//1)
        parse_regex(pattern)

      String.starts_with?(input, "glob:") ->
        pattern = String.slice(input, 5..-1//1)
        {:ok, glob(pattern)}

      true ->
        {:ok, substring(input)}
    end
  end

  defp parse_regex(pattern) do
    case Regex.compile(pattern) do
      {:ok, regex} -> {:ok, {:regex, regex}}
      {:error, {reason, _}} -> {:error, "Invalid regex: #{reason}"}
    end
  end

  defp glob_to_regex(glob) do
    regex_str =
      glob
      |> Regex.escape()
      |> String.replace("\\*", ".*")
      |> String.replace("\\?", ".")

    Regex.compile!("^#{regex_str}$")
  end
end
