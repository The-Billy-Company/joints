# Result 5 - the press change is in flight, and elixir has moved 66.75 points

Scored against [PREDICTION-2](PREDICTION-2-rederive.md) P3.1–P3.3. Two arms, the
control pinned **after** the arm as the house rules require:

| | arm | control |
|---|---|---|
| pin | `unjudged` | `headonly` |
| binary | `94d59d9ad`, tree `05a18fcd1` | `43e134cfc`, tree `37b6cfda9` |
| zig source | `f7ba40004` **+ 129 uncommitted files** | `f7ba40004`, **clean** - `git status -- src build.zig` is empty |
| built at | 2026-08-06T04:28Z | 2026-08-06T06:09Z |

The control is a detached `git worktree` at HEAD (`.local/wt-head`, with
`.local/irregex` symlinked so its `build.zig` can find the sibling) carrying the
*working tree's* `tool/` copied in, so the instrument is held fixed and only the
Zig moves. `headonly` is pinned **inside that worktree** - it is its own repo
root, so `pin.py list` in the main tree does not show it; look in
`.local/wt-head/.local/pin/headonly/`, which is deliberately left in place so
the control can be re-read rather than re-argued.

Both rows read the same oracle seat (`pin-unjudged`) - a comparison whose two
halves saw different oracles is not one - each with its own folio cache. Nothing
in the shared tree was touched to build it: `git worktree` is additive, and no
`stash`, `checkout --` or `restore` was involved.

## For whoever is holding an elixir baseline: read this line

> **elixir is a different row on the two arms, and the difference is uncommitted.**

| elixir | clean HEAD | HEAD + the in-flight press | move |
|---|---|---|---|
| size | 46,089 | 46,089 | - |
| **built** | **15,324** | **46,089** | **+30,765** |
| roots | 4,958 | **1** | −4,957 |
| damage | 30,765 | **0** | −30,765 |
| **standing** | **33.25%** | **100.00%** | **+66.75 points** |

None of those four columns needs an oracle, so none of them is exposed to the
seat churning underneath this session - and it was churning: the elixir artifact
changed digest three times in four minutes (`ABSENT` → `d06ab3480` →
`9fea0d8b3` → `d3e6f559f`) while I was measuring, which is the hazard the brief
warned about, observed.

**P3.1 held** (scored no credit - it was measured before it was written). The
change is **in flight**. If it is reworked or dropped, elixir's baseline goes
back to 33.25% and every number quoted against 100% becomes a number about a
tree that no longer exists.

### The trap in the git log

`git log -- src/press` has this, and it is an ancestor of HEAD:

```text
32390eb 2026-08-04 11:44:54 -0700  feat: split the import, carry dynamic
                                   precedence, and stop elixir folding on do
```

So a reader who greps the log for the change finds it, sees it committed a day
and a half ago, and concludes the baseline is settled. **It is not.** At clean
HEAD - with `32390eb` in it - elixir still stands at 33.25% over 4,958 roots.
Whatever finishes the job is in the 19 modified and 5 new files under
`src/press/` that nobody has committed (`settle.zig` alone is −861 lines).
A commit message is not a measurement.

### And the 100% is not a stretched root

A single root over a whole file at zero damage is the exact shape the board
distrusts, so it is worth saying that this one survives the check: `rack`
prices the same arm at **23,879 square of 46,089 built (51.8%)** with
**97.7% node-weighted bracket recall**. Real structure, node for node.

The other half of that sentence is the part a work order needs: **22,210 bytes
of elixir (48.2%) are built in a shape tree-sitter does not build**, 22,089 of
them under a right leaf and a wrong parent. A row reading 100% standing and 0
damage is misreading nearly half its bytes, and `damage` cannot say so.

## What the tripwire was guarding, and where it is now pointed

The assertion is `fat.engulf > fat.unframed * 0.9`. `engulf` is *of the bytes
charged `unframed`, how many the single widest missing frame accounts for*, and
it exists so a reader can tell **one file-wide frame we failed to build** from
**N missing constructs** - two facts with the same byte count and opposite work
orders.

elixir was the "one wide frame" pole: its corpus file is one `do_block` over
46,063 of 46,089 bytes, so `engulf` had to account for nearly all its
`unframed`. The in-flight press change lets elixir build that `do_block`,
`unframed` went to **0**, and `0 > 0 * 0.9` is false.

**The bug is not that the row moved. It is that a falsifier was pinned to a
named row a sibling can dissolve.** Two consequences, and the second is worse:

1. It failed for a reason with nothing to do with what it guards, so the failure
   carried no information - 18 of 19 for a day, over a green instrument.
2. Had the inequality been non-strict (`>=`), it would have gone **vacuous** and
   read green forever, on a column that had stopped being checked.

Picking a different row is not the fix, because the next row is dissolvable too.
So it is now asked of the **corpus**: *some* row's `unframed` must be one wide
frame and *some* row's must not, whichever rows those are today - and the
population itself is asserted, so a corpus with no `unframed` left fails loudly
instead of passing by having nothing to say. The widest of each pole is kept
rather than the first, so the line names a row where quoting `unframed` whole
would actually mislead.

```text
ok    and `engulf` still tells one frame from many: haskell 6020/6070 is a
      single frame, cpp 102/167 is not

19 of 19 held
```

### It responds to the treatment - all three ways

An assertion that cannot fail is what this dossier is about, so the new one was
driven negative on a restricted slate rather than argued for:

| slate | verdict |
|---|---|
| the corpus | `ok  … haskell 6020/6070 is a single frame, cpp 102/167 is not` · **19 of 19** |
| one-frame pole only (haskell) | `FAIL  every row with unframed is one wide frame - haskell 6020/6070 - so the column cannot be seen to discriminate` · 18 of 19, exit 1 |
| many-construct pole only (cpp) | `FAIL  every row with unframed is several constructs - cpp 102/167 - …` · 18 of 19, exit 1 |
| no row with `unframed` at all | `FAIL  no row on the board has any unframed left, so this pole cannot be read at all` · 17 of 19, exit 1 |

## P3.3 - and it was not unique to that row

**Held.** The assertion immediately above it had the identical shape:

> `and a forest is not swallowed whole: haskell's 624 roots cost it 6070
> unframed of 9192 built`

Its claim is about the **seam rule** - that a rule charging every forest its
whole file is refused - and it was asked only of haskell. A press change on
haskell would fail it for the same non-reason. It is now asked of haskell first
and of any row that can answer second, and it fails loudly when none can (see
the fourth row of the table above, where it did).

Two smaller things fell out of reading it:

- **Its comment carried a number that had moved.** It said *"haskell is 2,562
  roots"*; the row says 624. The count is now read off the measurement, so it
  cannot go stale again.
- The remaining assertions in `verify` hang on **checked-in specimens**
  (`selector-field.go`, `erroneous-end-tag.html`, a hand-built `Rung` pair) or
  on `javascript`'s 1,080-byte specimen, not on corpus rows. Those are the ones
  a sibling cannot move, and that is why they are the right shape.

## Scoring

| | claim | verdict |
|---|---|---|
| **P3.1** | the change is in flight, not committed; elixir's baseline has already moved more than once today | **held** - and scored **no credit**, because it was measured before it was written. The clean-HEAD control is the arm's-length version of it, and it agrees. |
| **P3.2** | the tripwire guards `engulf`'s ability to tell one frame from N; **php** supplies the other pole; the precondition should be *asserted* rather than assumed | **half.** The guarding claim held and the assertion-not-assumption fix is what shipped. **php was the wrong guess** - I named it from its corpus file being one `declaration_list` over 67,146 of 67,845 bytes, which is a fact about php's *file*, not about php's `unframed`; the corpus scan picks **haskell** for that pole and **cpp** for the other. Naming a row at all was the error the fix exists to correct, and I made it again inside the prediction. |
| **P3.3** | at least one other assertion in `verify` is guarded by an unasserted precondition of the same shape, and naming them is worth more than fixing the one | **held** - the haskell "forest is not swallowed whole" assertion, one line above, generalised the same way. |
