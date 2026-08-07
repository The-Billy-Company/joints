`research/joinery/specimen/html/erroneous-end-tag.html` is nine bytes:

```html
<p>x</q>
```

tree-sitter reads one `element [0, 8)` over three children. joints reads two
roots and no `element`. `rack.py` scored that **7 square, 0 crooked — a perfect
row**, and its own author demonstrated the case and left the hole open. The
reason is structural: `rack` compares spines inside built windows, one window
per built root, and `within()` drops every rung as wide as the window or wider.
That drop is load-bearing — it is what stopped zig charging 11,914 bytes to a
frame disagreement the two parsers have by construction — and it is also the
hole. A node we never built is in no window, so nothing on our side ever stood
where it was.

**A frame is missing when the oracle has a bracket, other than its own root,
wholly containing two or more of joints's built roots, and joints has no
node with that extent.** Its built bytes go to a new `unframed` column, taken
**only** from `square` and `renamed`, and never added to `crooked` — one column
says the derivation over a byte differs, the other says there is a node above it
on one side and nothing on ours. Summing them answers neither question.

```text
before  265,603 sq + 47 ren + 44,059 askew + 39,110 racked
                                    + 35,896 unjudged = 384,715
after   205,583 sq +  0 ren + 44,059 askew + 39,110 racked
                 + 60,067 unframed + 35,896 unjudged = 384,715
```

`square` fell 60,020 and `renamed` fell 47, which is the new bucket exactly, and
`askew` and `racked` did not move by a byte. The specimen goes 7 square → **7 of
7 unframed**, and `verify` asserts the *old* scoring as a tripwire so the hole
cannot reopen quietly.

**Where it goes the wrong way, and it is most of it.** The prediction written
before the measurement said the failure mode to look for was a grammar charging
its whole file to one wrapper node, and that if it were there it would be named
and held out rather than averaged in. It is there. `engulf` counts the bytes
under the single widest missing frame on a row: **56,715 of 60,067 unframed
bytes — 94.4% — are ONE frame per file.** Elixir's entire 26,756 is a single
file-wide `do_block`. Where a file is one construct that is the
forest-versus-tree difference wearing a new name, and `orphan`/`rubble`/`spoil`
already price it. **The seam charge is 3,352 bytes, 0.87% of built.** The board
prints the split rather than the total, and `verify` pins both shapes —
haskell's 624 roots costing 6,070 of 9,192, strictly between none and all of it,
and elixir's 26,756 of 26,756 being one node.

Three predictions failed and the arithmetic is in
`research/joinery/frame/RESULT-1-frame.md`: the widest new charge is elixir and
not haskell, the total is 15.61% of built against a predicted bound of 10%, and
one prediction was self-contradictory in a way I did not notice while writing
it. The two grammars that stop reading clean are the two named in advance and no
third — `c` at 105 unframed and `markdown` at **178 of 178, its entire file**.
None of the twelve grammars the board reads at 100.0% standing moves, because
all twelve hand back a single root and a rule keyed on the seam between two
roots cannot fire without a second root.
