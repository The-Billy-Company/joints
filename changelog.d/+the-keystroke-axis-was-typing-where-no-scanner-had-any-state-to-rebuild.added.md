The `incremental` axis now types a second keystroke *inside* each booked
grammar's stateful region, not only at 98% of the file.

98% is the right place to ask the general question and the wrong place to ask
this one. It lands in ordinary code, where neither parser has scanner state to
reconstruct - so the row that exercises a customary at all was the row that
did not exist, and the axis could look healthy while the case the customaries
were built for went untested.

`within` finds the caret rather than pinning one. Each booked grammar declares
the *node kind* naming its stateful region - elixir `quoted_content` (a heredoc
body, whose terminator lives in registers), html `raw_text` (a `<script>` body,
which stops being raw only at the tag the open tag named), markdown
`indented_code_block` (an opaque frame the layout rules skip), yaml
`block_sequence` (an indentation frame on the organ stack). The name is
grammar-specific knowledge and is not derivable; the position is derived, from
the largest instance of that kind in the real parse of the real file. So the
caret follows the corpus instead of rotting into a stale byte offset, and a
grammar with no such node skips with a reason rather than quietly measuring an
ordinary offset. The space still goes just before a newline, for the reason
`caret` already gives: trailing whitespace keeps the edited file parsing on both
sides, so the axis stays about the incremental path.

**What it measures, now that it is measured rather than asserted: the O(log n)
claim does not hold inside a stateful region today.** One grammar of four
produces a two-sided row at all.

| | keystroke | tree-sitter | |
|---|---|---|---|
| elixir @98% | 381 us | 2,457 us | 0.16x |
| elixir @quoted_content | **1,580 us** | 2,313 us | **0.68x** |

We still win mid-heredoc, and we win it against their real C scanner. But the
edit costs 4.1x what the same edit costs in ordinary code while theirs does not
move, so the win is their forward re-lex being slow, not our resume being fast.

The other three do not reach a row, each for its own pre-existing reason, and
none of them is the caret's doing:

- **yaml** has no oracle to compare against: its `scanner.c` includes
  `schema.core.c` through a macro (`_file(YAML_SCHEMA)`), and the include
  follower in `differential.beside` reads text, so the file is never fetched and
  `tree-sitter build` fails. Our own side is measurable and is not good: an edit
  inside a `block_sequence` re-reads all 1,372 tokens with 0 lifts, 3,867 us
  against a 4,488 us cold open. That is a parse that reopens the file wearing a
  keystroke's name.
- **html** refuses any insert, at the stateful caret and at 98% alike:
  `4481..4481 +1` reports `unexpected (?:[^>]+) at 72283 in state 3`. The delete
  that follows is accepted, so the file is fine and the resume is not.
- **markdown** and **scala** raise `error.TrailRefused` on any amend, which
  `research/keystroke/RESULT-3-slate.md` already documents.

Four grammars, four different walls, and the axis now names each one on every
run instead of reporting eleven healthy rows about languages with no scanner
state at all.
