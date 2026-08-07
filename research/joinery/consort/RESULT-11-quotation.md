# Result 11 — the cross-lane quotation hole, and the half of it no gate reaches

Parts 1 and 2 of this lane fixed what a *board* prints and what a *page* must
carry. This is about the gap they leave: a lane reads another lane's board and
quotes its total in a report. That is how four correct boards became four
disagreeing headlines yesterday morning, and how a lane last week carried a
sibling's `built` figure across an arm boundary and had it move 30,720 → 32,193
underneath it.

**Verdict: the hole splits in two, and only one half is a gate's business.**
"Which world was this taken in?" is now closed to a floor. "Is this figure
actually from that world?" is **not reachable by any gate present or buildable
at this project's cost ceiling**, and the reason is structural rather than
budgetary. Both halves are argued below, and the ergonomic remedy for the second
is shipped, because the second half is not an enforcement problem.

## What was already solved, and what it left

`attest.rule()`, `still.take` and `rack.py`'s rule-digest solve the **machine**
half completely. Two boards read from different trees cannot be diffed:
`rack.py against` and `still against` refuse at exit 4 and name the files that
differ. That is airtight, and it is airtight because both operands are boards.

The moment one operand is a **sentence**, every one of those instruments is
blind. A number in prose has no witness attached, no digest to compare, and no
type. `still.differ` cannot refuse a comparison it is not asked to make.

## Five mechanisms, and why four of them fail

**1. A board that refuses to be read without its stamp.** Already true, and
already insufficient. `standing.py` prints `stamp:` and `witness board:` on
every board it has ever printed. A lane copies the *row*, not the footer — and
that is not carelessness, it is the correct thing to copy. Interleaving the
stamp into every row makes the board unreadable, at which point lanes read it
through `--json | jq` or `| head`, both of which strip the footer by
construction. **A footer cannot defend against a partial read, and reading is
partial.** No arrangement of glyphs on a board fixes this.

**2. Refuse to print at all until the stamp is acknowledged.** Fails harder. The
lane acknowledges once, gets a board, and pastes numbers from it an hour later
after three siblings have landed. Ceremony at print time proves nothing about
paste time, and the interval between them is exactly where the 1,900 bytes went.

**3. Accept a link to the page a figure was taken from.** Explicitly refused, and
the refusal is the finding. `RESULT-8-sighted.md` published `square` **311,540**
and `RESULT-4-borrow.md` published `square` **311,540**, and both are unstamped:
a page citing either inherits its blindness while looking scrupulous. The
`--gate` built in Part 2 does *not* treat a markdown link as attribution,
because "another page said so" is the precise mechanism under investigation.

**4. A gate that verifies the figure against the stamp.** This is the one that
would actually close the hole, and it is unreachable on three independent
grounds. To check `311,540` against `joints e51716d6c` the gate must re-press
the corpus at that binary: the binary may be a pinned arm long since pruned from
`.local`; the tree may never have been committed, so it cannot be restored; and
a press costs ~30 s where the standing ceiling is 1 s. Any one of those is
fatal.

The cached variant is more interesting and fails for a better reason. Boards
*are* saved with their witnesses, so a gate could look one up by digest. But the
number in prose is untyped: `311,540` does not say it is `square`, corpus-wide,
over the `all` set. To check it you must first make the page say so — a
structured citation, a machine format embedded in prose, typed by a human. At
which point **the failure mode changes from "no attribution" to "a citation that
typechecks and is still wrong"**, which is strictly worse: it wears a machine's
authority. A gate that can be satisfied by careful typing has not closed a hole
that careless typing opened; it has raised the price of the same mistake.

**5. Make the attributed form the cheapest form.** This one works, and it is not
a gate. It is shipped, in two pieces:

```
$ python3 tool/standing.py --cite
joints `e51716d6c` · tree `61c93c367` (live) · **no oracle** — joints's own words

$ python3 tool/standing.py --cite=board.json --quote=damage
`damage` reads **125,011** over 30 row(s) — joints `e51716d6c` · tree `61c93c367` (live) · oracle `d85e736fa` (30 attributed)
```

The second is the mechanism and the first is its degenerate case. The figure and
the world it came from are **rendered by the same call**, so they arrive as one
paste and cannot drift apart by accident — separating them becomes a deliberate
act rather than the default one. It reads a saved `--json` board rather than
measuring, costs **~80 ms**, and therefore works on the board a lane took an
hour ago, which is the case that goes wrong by hand.

It also inherits Part 1's discipline rather than restating it. Ask it for a
column no oracle judged and it refuses to mint the sentence at all:

```
$ python3 tool/standing.py --cite=board.json --quote=square
standing.py: no oracle judged a byte of this board, so its `square` is a sum of
30 unmeasured zeroes and not a figure.
```

That is the `damage 0` trap arriving by addition, and it is the exact sentence
this lane exists because of. Thirty rows of unmeasured zero sum to a real
integer, and a total is the one place a bare zero is invisible.

## The gate refused two of this lane's own pages, and it is half right

Written down because it is the first evidence about the gate's precision and it
arrived within an hour of the gate existing.

Both refusals are on the **blind** axis, which predates this lane; every page
written here passes the stamp axis it added. The two are the changelog fragments
for `shear.py` and for `--cite`, and both quote `rubble` and `damage` — our
columns, no oracle. `shear.py` presses **the same bytes with the same grammar
twice** and reports the difference; there is no second parser in the question it
asks, and demanding one is asking it to prove something it is not claiming.
`onlydamage.FOREST` already carries this exemption for tree-identity proofs
("oracle-free and answers the same question more cheaply") and has no spelling
for a self-comparison instrument.

Left unfixed on purpose. Widening a classifier so that this lane's own pages go
green is the shape of a check being edited to match its author, and the fix
belongs to whoever holds `onlydamage.py`'s vocabulary. It is stated here as the
gate's known false-refusal class and as the strongest argument in the
blocking-versus-advisory question: **the stamp axis has no false refusal anybody
has found, and the blind axis has one that fires on correct work.**

## What this does not do

`--quote` proves that *this* figure came from *this* board. It proves nothing
about a figure a lane typed by hand next to a `--cite` line pasted from a fresh
run. That case remains open and will remain open: the number was typed, and
typing is unfalsifiable at the point of typing. The honest description is that
this lane converted a **default** into a **choice** — the attributed form now
costs one command and one paste, so the unattributed form is no longer the lazy
path, and the wrong-attributed form requires somebody to mean it.

If that turns out not to be enough, the next rung is not a better gate. It is
that a figure should not be typed at all: the board emits the sentence and the
page includes it, the way `bench.report.md` already includes its stamp block
verbatim. `--quote` is the first inch of that road, and whether it is worth
paving is a question for a lane that can measure whether unattributed pages stop
appearing. **The gate in Part 2 is the instrument that will answer it**, since
it counts the population by the day it was written.

## The measurement

Over the record as it stands — 386 pages under `research/` and `changelog.d/`:

| | pages |
|---|---|
| quote no measured figure (never asked for anything) | 128 |
| quote a measured figure | 258 |
| ...of those, **blind** — our columns, never the oracle's | 103 |
| ...of those, **unstamped** — name no tree or binary | 181 |
| ...of those, sighted **and** unstamped — the new axis alone | 103 |
| refused by `sighting.py --gate` on either count | **206** |

The corpus exhibits all four corners of the two axes, which is asserted as a
check rather than a remark: if it ever stops exhibiting one, the second axis has
collapsed into the first and one of them should be deleted.

Taken on `joints e51716d6c` · tree `61c93c367` (live) · no oracle — this page
quotes no oracle column, and the counts above are `sighting.py`'s own, not the
board's.
