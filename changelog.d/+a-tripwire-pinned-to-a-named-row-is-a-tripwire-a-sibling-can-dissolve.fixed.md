`rack verify` held 18 of 19 for a day, and the failing one carried no
information. The assertion is `fat.engulf > fat.unframed * 0.9`, and `engulf` —
*of the bytes charged `unframed`, how many the single widest missing frame
accounts for* — exists so a reader can tell **one file-wide frame we failed to
build** from **N missing constructs**: two facts with the same byte count and
opposite work orders.

It was asked of **elixir**, whose corpus file is one `do_block` over 46,063 of
46,089 bytes, so `engulf` had to account for nearly all its `unframed`. Then an
in-flight press change let elixir build that `do_block`, `unframed` went to 0,
and `0 > 0 * 0.9` is false.

**The bug is not that the row moved. It is that a falsifier was pinned to a
named row a sibling can dissolve**, so it failed for a reason with nothing to do
with what it guards — and had the inequality been non-strict it would have gone
**vacuous** and read green forever on a column that had stopped being checked.
Picking a different row is not the fix, because the next row is dissolvable too.

So it is asked of the **corpus**: some row's `unframed` must be one wide frame
and some row's must not, whichever rows those are today, and the population
itself is asserted — a corpus with no `unframed` left fails loudly instead of
passing by having nothing to say. The widest of each pole is kept rather than the
first, so the line names a row where quoting `unframed` whole would actually
mislead.

```text
ok    and `engulf` still tells one frame from many: haskell 6020/6070 is a
      single frame, cpp 102/167 is not

19 of 19 held
```

Driven negative on restricted slates rather than argued for, because an assertion
that cannot fail is the thing this dossier is about:

| slate | verdict |
|---|---|
| the corpus | 19 of 19 |
| one-frame pole only (haskell) | `FAIL  every row with unframed is one wide frame — haskell 6020/6070 — so the column cannot be seen to discriminate` · exit 1 |
| many-construct pole only (cpp) | `FAIL  every row with unframed is several constructs — cpp 102/167 — …` · exit 1 |
| no row with `unframed` at all | `FAIL  no row on the board has any unframed left, so this pole cannot be read at all` · exit 1 |

**The assertion one line above it had the identical shape** and is generalised the
same way: *"a forest is not swallowed whole"* is a claim about the seam rule — that
a rule charging every forest its whole file is refused — and it was asked only of
haskell, so a press change on haskell would have failed it for the same
non-reason. It now takes haskell first and any row that can answer second, and
fails loudly when none can. Its comment also carried a count that had moved (it
said 2,562 roots; the row says 624), so the count is read off the measurement now
and cannot go stale again.

Every remaining assertion in `verify` hangs on a checked-in specimen —
`selector-field.go`, `erroneous-end-tag.html`, javascript's 1,080-byte case, a
hand-built `Rung` pair — which is why those are the right shape: a sibling
cannot move them.

**And for whoever is holding an elixir baseline: it moved 66.75 points and the
move is uncommitted.** A clean-HEAD control built in a detached worktree, with
the working tree's `tool/` copied in so only the Zig varies:

| elixir | clean HEAD | HEAD + the in-flight press |
|---|---|---|
| built | 15,324 | **46,089** |
| roots | 4,958 | **1** |
| damage | 30,765 | **0** |
| standing | 33.25% | **100.00%** |

`git log -- src/press` has `32390eb feat: … and stop elixir folding on do`,
committed 2026-08-04 and an ancestor of HEAD, which reads like the change has
landed. At clean HEAD — with that commit in it — elixir still stands at 33.25%
over 4,958 roots. Whatever finishes the job is in the 19 modified and 5 new
uncommitted files under `src/press/`. A commit message is not a measurement.

The 100% is not a stretched root — `rack` prices the same arm at 23,879 square of
46,089 built with 97.7% node-weighted bracket recall — and the other half of that
sentence is the part a work order needs: **22,210 bytes of elixir (48.2%) are
built in a shape tree-sitter does not build**, 22,089 of them under a right leaf
and a wrong parent. A row reading 100% standing and zero damage is misreading
nearly half its bytes, and `damage` cannot say so.
