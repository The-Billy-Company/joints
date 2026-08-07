# Handover — the complaint standing already prints, and the seat it will need

For whoever holds `tool/standing.py`. Found on 2026-08-05 by the `frame` lane
while wiring `rack` into the board. Nothing in `standing.py` was changed here:
its output shape and its headline are exactly as they were, and the brief said
to keep them that way.

## 1. standing was right about toml and nobody read it

`standing.py` prints this in its footer, and has for as long as the toml row has
existed:

```text
sound   1 of 30 UNSOUND — toml: 1 loose, 0 disorder, 0 torn
        [child outside its parent: comment [47, 56) in pair [27, 45)]
```

The row itself carries `· UNSOUND` too. And the same grammar scores **100.0%
standing** and `whole` on the columns anyone actually reads. So the board says
"perfect" in the place people look and "this is not a tree" in the place they do
not, and the second sentence has been losing for as long as both have printed.

**It is not a false alarm.** A sibling lane adjudicated toml properly — zero
declared conflicts, zero contested cells across 175 states — and the mechanism
is exactly what the complaint says: both parsers hang the `comment` under the
same `pair`, and joints's `pair` merely ends at byte 7 with a child starting
at 9. A moved right edge. `rack.py soft` prices the same class corpus-wide at
**12,439 bytes**, of which toml is 29, latex 96% of its row and zig 80% of its.

So `standing.py` diagnosed, from joints's own forest and with no oracle
present at all, a defect that took `rack` an oracle and two revisions to find.
That is the most useful thing either instrument did this week and it needed no
new code.

## 2. What this lane did about it, and what it deliberately did not

`rack.py board` now reprints every row carrying a soundness complaint underneath
its own table, with the complaint's full text and the standing figure beside it:

```text
1 row(s) here carry a soundness complaint the PARSE ITSELF printed,
which no board reads:
  toml   100.0% standing  UNSOUND: 1 loose, ... [child outside its parent: ...]
  These are joints's own words about its own forest. A grammar can score
  100.0% and `whole` on a board that never asked.
```

`rack` reads `standing`'s rows and reprints them unmodified — that contract is
unchanged, and `board` still closes with the four CHECK lines proving the split
totals `built` and the four buckets total the corpus. **No column, headline or
footer of `standing.py` moved.**

What this lane did **not** do, because it is yours: `standing.py` reports
*that* a row is unsound and does not report *what kind*. `1 loose, 0 disorder,
0 torn` is three counts of three different diseases sharing one word. A loose
child whose parent's edge moved is a bounded, cheap, single-grammar defect; a
torn byte is not. If the footer distinguished them, the toml row would have read
as actionable rather than as a warning about an unspecified thing on a grammar
scoring 100%.

## 3. The seat, which is new

`standing.py` is oracle-free — it reads joints and nothing else — so nothing
here forces a change today. But two things now true will reach it.

**The oracle moves under you.** `rack` stamped fourteen fields and all fourteen
were about joints; a sibling measured **scala at 1,278 crooked in one run and
9,087 in the next, same pin, same unedited script, stamp byte-identical**,
because three grammar libraries were rebuilt mid-session by other lanes.
`tool/attest.py` now seats the oracle by digesting each grammar's **sources**
rather than its library, and `rack`/`absent` print the seat on every table.

**Twenty-eight of twenty-nine grammars currently exist as several different
files at once** (`attest.py verify`), and divergence between copies is not
cosmetic — css differs in 62.3% of its bytes between two copies in this tree,
verilog in 0.0003%. A library digest cannot tell a rebuild from a genuinely
different parser; that is why the identity is the sources.

The practical rule for the board: **any table that puts a `standing` column next
to a `rack` or `absent` column must carry the seat**, or the two halves are
describing different oracles and the reader cannot know.
`attest.consult(cases, tag)` and `attest.told()` are two calls and are already
what both tools do.

## 4. The other thing standing cannot see, in case it wants to

`rack` now charges **60,067 bytes to `unframed`** — a byte where the oracle has
a bracket containing two or more of our roots and we built no node with that
extent. **56,715 of those (94.4%) are ONE frame per file**, which is the
forest-versus-tree difference `orphan`/`rubble`/`spoil` already price; **3,352
are genuine seams**.

`standing.py` cannot distinguish those two cases and does not claim to. But it
does own `roots`, and the single most useful column it could add for the next
lane is **how many bytes the widest root covers as a share of the file** — the
whole-file-wrapper shape, from our side, with no oracle needed. Where that share
is near 1.0 a forest is one construct and `unframed` will be a wrapper; where it
is small the forest is real and `unframed` is seams. `rack` derives it the
expensive way, per byte, against tree-sitter. `standing` could derive it for
free. That is a suggestion and not a finding — nobody has measured it.

## Reproducing any of the above

```sh
python3 tool/standing.py                      # the footer, unchanged
python3 tool/rack.py board  --oracle=frame    # same rows + the unread complaints
python3 tool/rack.py soft   --oracle=frame    # the 12,439 moved-edge bytes
python3 tool/attest.py verify                 # why the identity is the sources
```

Full working: [`RESULT-1-frame.md`](RESULT-1-frame.md) ·
[`README.md`](README.md).
