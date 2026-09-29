# Commit policy; run with `mix presubmit`, installed as hooks by `mix presubmit.install`.
[
  {Presubmit.Rules.Elixir, except: [:removals_deprecated, :pure_move]},
  # test/fixtures/beam/ holds .beam files on purpose: they are what beam_spy reads.
  {Presubmit.Rules.Hygiene,
   artifacts: [
     ~r/\.DS_Store$/,
     ~r/\.(orig|rej)$/,
     ~r{^_build/},
     ~r{^(?!test/fixtures/).*\.beam$}
   ]},
  Presubmit.Rules.Mix,
  {Presubmit.Rules.Changelog, warn: [:api_changes_logged]},
  # `type(scope): text`: the text is free, since it often opens with a proper noun, a version
  # or a flag. A long subject is worth a look, not a refused commit.
  {Presubmit.Rules.Message,
   subject:
     ~r/^(feat|fix|docs|test|ci|chore|refactor|perf|build|style)(\([a-z0-9_.\/-]+\))?!?: \S/,
   max_subject_length: 72,
   warn: [:subject_length],
   trailers: [
     {fn commit ->
        Enum.any?(
          Presubmit.Query.trailer(commit, "Co-Authored-By"),
          &(&1 =~ ~r/anthropic\.com/)
        )
      end, "Claude-Session", ~r{^https://claude\.ai/code/session_}}
   ]}
]
