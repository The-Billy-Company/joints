# Prediction 2 — the inverse query, and what it is allowed to claim

Written before the query was repaired. Scored in `RESULT-2-instrument.md`.

## What was already here, and what the brief said about it

The brief says `joints state --holding <item>` "is **not in the binary and
never has been**; `git log -S` finds no commit that added it", and
`owners.py::stranded()` says the same sentence in the tree.

**Both are wrong, and the reason they are wrong is worth more than the flag.**
`--holding` is in the working tree right now — `state.zig` implements
`spelling()`, `main.zig` dispatches it, and the pinned binary answers it.
`git log -S` finds no commit because **`state.zig` is untracked**: `git status`
reports `?? src/surface/face/joints/state.zig`. A history search cannot see a
file that has never been committed, and in a tree where ~90% of `src/` is
uncommitted that is not an edge case.

So the first half of this lane is not "build the flag". It is "find out what
the flag that already exists actually answers", which turns out not to be the
question either.

## P5 — the existing `--holding` answers a different question than it is asked

**Claim.** `spelling()` matches with `std.mem.indexOf` on the item's printed
text, so a query for a **completed** item is a strict prefix of every item with
the dot one position earlier. Asking for `variable_lvalue -> _identifier .`
therefore also matches `variable_lvalue -> _identifier . select1`, and the
answer is inflated.

**Measured before writing this:** the query returns **92 states**, and every
printed line is the dot-in-the-middle item. So the count is not just inflated,
**none of the rows shown is the item asked for.**

I predict the true number of states holding the completed
`variable_lvalue -> _identifier .` is **under 20**.

**Kill condition.** 20 or more.

## P6 — a per-state break hides items

**Claim.** `spelling()` does `break` after the first matching kernel item, so a
state holding two matching items reports one, and which one depends on kernel
order. I predict at least one state in the verilog population holds more than
one item matching a body-level query.

**Kill condition.** No state holds two.

## P7 — the fold chain is the half that attributes

**Claim.** Naming the states that hold an item is navigation. What decides
ownership is **where the fold goes** — the goto edge the reduce takes, and the
predecessors that shift into the wall state. I predict that for the swift pair,
the chain distinguishes `scanner` from `conflict` in one step, and that for
verilog it shows the four left-hand sides are *not* in contention.

**Kill condition.** The chain is consistent with both owners for either row, in
which case it does not discriminate and I have built a second navigation aid.

## What this instrument may not claim

A state holding an item is not proof the parse went through it. The collection
is **ours**; a reading our press lost is invisible to a query over our own item
sets, which is the same blind spot that made `gap` false. So every verdict this
lane reaches names the evidence that would overturn it, and no row here is an
upstream claim.
