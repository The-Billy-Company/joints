`customary/markdown.json` gains the two rules its transcription had dropped, and
markdown parses whole files correctly for the first time.

Eight lines of markdown - a heading, a fenced block, a two-item list - came back
`truncated, 8 roots`, and the 132K file the bench types into came back
`accepted` only in the sense that 297 roots and a repair had been called an
answer. Nobody had noticed, because the falsifier says the book is perfect and
it is right: `tool/customary.py check markdown` reports 100% recall on every one
of the eleven terminals it can observe, 0 missed, and 0 spurious under the
permission envelope, over 10,673 answers.

It can only observe terminals that reach tree-sitter's tree as a named leaf. The
two that were missing are structurally invisible to it:

- **`_eof`.** The C checks it *first* at `:1332`, before the block-close
  fallback at `:1336`, so a state admitting `_eof` gets `_eof` and never the
  close. Our book had only the fallback - so at the end of every file the
  grammar asked for the one terminal nothing could make, and the start symbol
  never closed. It is zero-width and hidden, so it has never appeared in an
  oracle tree and the falsifier has never had an opinion about it.
- **A line ending behind the line's own indentation.** The C's not-matching
  branch (`:1345`) advances over the leading blanks before it looks at
  anything, so when the switch `break`s at `:1380` the lookahead it reads at
  `:1542` is the newline the soak stopped on. Our rule probed for that newline
  at the raw offset, where the byte is still a space. `layout` is the phase
  that soaks and re-stands - the engine already had the mechanism, the rule was
  just in `ordered`, one phase too late.

Both are permission-gated, and the falsifier deliberately models `wanted` as
"everything", which is the more useful question for the other 44 rules and
exactly the wrong one for these two.

| | before | after |
|---|---|---|
| 8-line file | `truncated, 8 roots` | `accepted, 1 root` |
| `markdown-40.md`, 132K | `accepted, 297 roots`, mended | `accepted, 1 root` |
| blind terminals | 9 | 8 |

`joints lex` now answers 39 of markdown's 47 externals. The eight left are
`_error` and `_trigger_error` (the C's own way of killing a GLR branch),
`_html_block_1_end`, `_no_indented_chunk`, `minus_metadata`, `plus_metadata`,
`_pipe_table_start`, `_pipe_table_line_ending`.

The falsifier is unchanged by this - same 0 missed, 0 spurious, same spurious
breakdown to the answer - which is the point: these rules live where it cannot
look, and nothing it *can* look at moved.

**This was never an incremental defect,** which is what it had been filed as.
The bench's keystroke pair on markdown refused every insert with `unexpected
_whitespace at 129505 in state 59`, and a cold parse of the identical bytes
refused in exactly the same words, while tree-sitter accepted them. What is left
after this fix *is* an incremental defect and is now visible as one: the insert
amends to `stray byte at 129595` where a cold parse of those bytes accepts, the
same shape `abide.py` reports as `7 roots amended, 1 cold`. The delete already
behaves - 1 leaf reminted of 49,400, where before the fix it was 808.
