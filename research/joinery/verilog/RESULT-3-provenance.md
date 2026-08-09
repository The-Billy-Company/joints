# RESULT-3 — the provenance bit, and what it uncovers

Against `PREDICTION-3-provenance.md`. Nine predictions, **two failed and one
held on a falsifier too weak to have caught it being wrong**, and those three
are the finding. The bit works, it costs the other twenty-nine grammars
nothing, and it turns a silent misreading in verilog into a visible fork that
`gather` then answers wrong.

| | prediction | outcome |
|---|---|---|
| P1 | no folio change is needed | **held** — `leaf.StepRecord` is not `g.Step` |
| P2 | the ledger is blind here today | **held**, demonstrated both ways |
| P3 | state 1184's row gains a shift on `[` | **held** |
| P4 | W7 and W8 seat, controls standing | held — **but W7 seats wrong-shaped** |
| P5 | W9 seats too, W5/W6 do not | **FAILED** — W9 does not seat |
| P6 | this is not repair B narrowed | **held** — damage is baseline, not 62,645 |
| P7 | scala and elixir regress, by less than B | **FAILED** — neither moves at all |
| P8 | every grammar presses to the same bytes twice | **held**, 30 of 30 |
| P9 | no grammar buys `built` and pays `square` | **held** — rack is flat everywhere |

## The change

`g.Step` grows one bit.

```zig
spliced: bool = false,
```

It means: the `prec`/`assoc` on this step arrived inside a rule the press folded
away, and was authored for *that* rule's reading rather than for the production
that now names it. `fold.zig::expand` sets it on every step it splices in that
carries a rank of its own, and the boundary step inherits the host's provenance
along with the host's rank, so a second fold round cannot launder it clean —
which is exactly what happens to `clockvar` when `_identifier` folds in behind
`hierarchical_identifier`. `column.Folds` records whether any surviving
reduction authored its own side; `Ladder.purely` answers no when none did.

Nothing about *which* rank wins at a splice boundary moves. Repair A was that,
and it measured worse.

**The behavioural surface is one line.** Everything else is bookkeeping:

```zig
if (f.loose or !f.authored) return false;
```

That is load-bearing below, because it is what makes a clean control possible.

## P1 — the format change does not exist

The handover said `Step` is `leaf.StepRecord`, an `extern struct`, so the bit
was a folio format change and `impose`'s ledger owned the decision. It is not.
`leaf.StepRecord` holds `alias` and `field` and nothing else; `prec` and `assoc`
are press inputs spent while the cells are decided, and `binding.zig` says so where
it rebuilds a step. A bit *about* those two ranks lives where they do. No
version bump, no `extern struct` widened, no padding to re-zero.

That is a claim that had to be falsified rather than asserted, so it is proved
twice over: by a round-trip test that packs a grammar whose fixture really
contains a spliced rank and asserts the bound step comes back with `prec`,
`assoc` and `spliced` empty and `alias`/`field` exact; and by P8 below.

The round-trip's own anti-vacuity matters here. The existing round trip presses
`sample`, whose productions are built by hand, so no step in it was ever
substituted into anything and `spliced` is false everywhere for reasons that
have nothing to do with the writer. **A section of records that all happen to be
zero round-trips perfectly however wrong the writer is** — which is how a
dropped field once reported thirty grammars byte-identical. So the new test
builds verilog's shape in miniature, folds it, and asserts *before writing
anything* that exactly one step is spliced and that the rank which survived is
the victim's 0 rather than the host's 37.

## P2 — the ledger was blind here, and here is the demonstration

`impose`'s comptime ledger covered `lalr.Conflict`, `settle.Frayed` and
`lalr.Tables`. It never covered `g.Step`. The exact bug it exists to stop was
unguarded for the one type this change touches.

Not a hedge, a demonstration. Add a sixth field to `g.Step` and build.

Ledger as this lane leaves it:

```text
src/folio/impose.zig:100:16: error: press.grammar.Step.canary is new to the
press and unaccounted for in the folio. Give it a slot in its `leaf` record and
write it below, or name it in `ledger` with a comment saying why the file does
not need it. Silence here reads downstream as `your change did nothing`.
```

Ledger as it was this morning (`accounts(g.Step, ledger.step)` removed, canary
still present): **compiles clean.** A fourth press-only field could have been
added tomorrow with the same silence that once reported thirty grammars moved.

And the round trip is not vacuous either. Corrupt the writer so it never writes
an alias:

```zig
.alias = leaf.none, // CORRUPTED: writer drops the alias
```

```text
FAIL folio.folio_test.test.a spliced rank is spent by the press and reaches
no reader through the file: TestExpectedEqual — expected 0, found null
```

Both guards say no when they should.

## P3 — state 1184

Before, on `[`: nothing. The tie was answered by a `left` that `clockvar`
inherited from `hierarchical_identifier`, `standing` came to 1, and `decide`
returned before recording.

```text
prov-before  shift 5, lookahead 20 — 25 terminal(s) accepted of 444
prov-after   [   read on   [residual shift_reduce, over fold  clockvar -> _identifier   [prec 0 left]]
             shift 7, lookahead 18 — 25 terminal(s) accepted of 444
```

The same thing happens at **state 1762**, which is where the rest of this
dossier lives:

```text
prov-before  =   fold  variable_lvalue -> _identifier   [prec 0 left]
                 [declared reduce_reduce, over fold  nonrange_variable_lvalue -> _identifier]
prov-after   =   read on   [residual shift_reduce, over fold  variable_lvalue -> _identifier]
```

Before, `=` could only fold to `variable_lvalue`: the shift into
`variable_decl_assignment -> _identifier . = expression` was suppressed by the
ladder folding on an inherited side. The press was deciding a question it had no
authored rank to decide, and in that cell it happened to decide right.

## The board, the rack, and thirty trees

Pinned binaries either side (`tool/pin.py`: `prov-before` `907cae363861`,
`prov-after` `986eb8ece142`), compared as trees, plus a paired control built
below.

| | verilog | scala | elixir | seats | controls |
|---|---|---|---|---|---|
| baseline | 63,937 | 4,150 | 1,559 | — | 17/17 |
| A · host's rank wins the splice | 67,349 | — | — | W5 W6 W7 W8 | 17/17 |
| B · record the side-rung cell | 62,645 | **16,883** | **8,917** | W5 W6 W7 W8 | 17/17 |
| C · …only across different rules | — | **16,883** | — | W7 W8 | 17/17 |
| D · drop a spliced side on clash | — | — | — | none | 17/17 |
| **this · provenance on the step** | **63,937** | **4,150** | **1,559** | **W7 W8** | **17/17** |

Damage in bytes, `tool/standing.py`. A dash is "did not move".

Board totals are **142,083 damage / 97,898 describes / 5,586 bare leaves on both
sides**, matching handover exactly. Across all thirty rows and every column
`standing.py` prints, **exactly one number moves**: verilog's `nodes`, 22,222 →
22,210. Same bytes, same roots, same `built`, twelve fewer nodes.

- **`tool/rack.py --square`: totally flat.** `built` 384,715, `square` 265,603,
  `racked` 39,110, `askew` 44,059, `crooked` 83,169 — identical either side, and
  no individual grammar moves a field. Nothing buys `built` and pays `square`,
  because nothing buys `built` at all.
- **Folios: 27 of 30 byte-identical.** rust, scala and verilog moved.
- **Trees: 29 of 30 identical.** rust's and scala's tables changed and their
  derivations did not. verilog moved at **one root out of 3,534**.
- **Press-twice: 0 of 30 differ.** No `extern struct` grew, so no padding came
  back — but that is the argument, and this is the measurement.

Elixir's folio is byte-identical, so elixir cannot have regressed. That is P7
failing, and it is the difference between this and repair B: B paid elixir
7,358 bytes; this does not touch it.

### The clean pair, because the pins were not obviously clean

`prov-after`'s pin record says `"newest": "src/kernel/quire/graft.zig"` — the
gather lane landed an edit between the two pins, so the pair differs by my
change *plus* whatever that was. Rather than assume it was inert:

rsync the live tree to a scratch copy, ablate the single behavioural line
(`if (f.loose) return false;`), build, restore it, build again. Two binaries
from one snapshot differing by one line.

- ablated arm vs `prov-before`: **all 30 folios byte-identical**
- restored arm vs `prov-after`: **all 30 folios byte-identical**
- ablated vs restored: **rust, scala, verilog** — the same three

So the quire edit changed no folio, the pins were clean, `spliced` in `dedup`'s
key collapses nothing, and every number above survives the check. Production
and LR(0) state counts are also identical either side (verilog 4,296 / 9,763),
which is why state numbers are comparable in this dossier where they were not in
`RESULT-2` — that lane's pair renumbered 9,763 → 9,276.

## P4 and P5 — the witnesses, and the one that lied

`smallest.py`, pinned, with an isolated folio cache per side (see the last
section for why that qualifier is not decoration):

| | before | after |
|---|---|---|
| fail | W1 W2 W3 W5 W6 **W7 W8** W9 W16 (9) | W1 W2 W3 W5 W6 W9 W16 (7) |
| controls | 17/17 stand | 17/17 stand |

**W7 and W8 seat. No witness is lost and no control is relaxed.** W5/W6's wall
moves from state 3772 to state 1371 — a different state, not a renumber — and
they still fail, as predicted. W9 and W16 are unchanged at `; in 701`, so **P5
failed**: the concatenation is not this cell.

And then the part P4's falsifier could not see.

`smallest.py` asks whether a snippet parses whole. `c[i] = 0;` now parses whole.
It parses whole as a **`block_item_declaration`**.

```text
before   unexpected = at 86 in state 2394
after    (seq_block (block_item_declaration (data_declaration
           (list_of_variable_decl_assignments (variable_decl_assignment …)))))
```

That is not a blocking assignment. W8 (`for (i = 0; …) c[i] = 0;`) *is* seated
correctly, and only because a declaration is ungrammatical in a for body, so
the fork has one limb. **W7 traded a wall for a misreading and the sweep scored
it a seat**, which is the same class of failure as `c[i] <= 0;` building
`clocking_drive`: the board and the sweep can each see one of the two symptoms.

## What this actually costs verilog

The twelve nodes are one block in `picorv32.v`, line 2348:

```verilog
always @* begin
    instr_mul = 0;
    instr_mulh = 0;
    instr_mulhsu = 0;
    instr_mulhu = 0;
    if (resetn && …) begin
```

Four `blocking_assignment`s became four `block_item_declaration`s. Same spans,
so `built`, `covered`, `spoil` and `damage` are all identical and all wrong. The
three-line reproducer:

```verilog
module m;
  always @* begin
    instr_mul = 0;
  end
endmodule
```

`accepted, 1 root` on both sides; a statement on one and a declaration on the
other.

There is also a hard regression, narrower than it looks:

| body | before | after |
|---|---|---|
| `c[i] <= 0;` | accepted (as `clocking_drive`) | **unexpected `<` in state 2603** |
| `c[3] <= 0;` | accepted | accepted |
| `a[3:0] <= 0;` | accepted | accepted |
| `x <= 0;` | accepted | accepted |
| `c[i] = 0;` | unexpected `=` in state 2394 | accepted (as a declaration) |

Only `ident[ident] <= …` breaks, because only an *identifier* index is also a
legal associative-array dimension — `c[3]` cannot be a type, so there is no
fork. picorv32 contains exactly two of these, both behind `` `ifdef `` blocks
the parser already walls on (W1–W3), which is the only reason the board did not
move. That is luck, and it is worth writing down as luck.

## Does the gather wrong-limb defect survive? Yes — it is now the whole cost

`RESULT-2` found that repair B's scala and elixir regressions were the press
offering a legitimate fork and `gather` taking the wrong limb, one layer down in
`src/kernel/quire/`. The question this lane was asked to answer is whether that
still matters once the press stops erasing ranks.

It matters more, and this is the clean statement of it: **a press that no longer
erases authored ranks offers more legitimate forks, and every additional fork is
another chance for `gather` to answer wrong.** With the rank erased, state 1762
had one action on `=` and gather was never asked. Now it is asked, and of the
four situations observed:

| situation | limb taken | right? |
|---|---|---|
| `c[i] = 0;` at statement position | declaration | no |
| `x = 0;` at statement position | declaration | no |
| `ident[ident] <= 0;` | declaration, then walls | no |
| `for (…) c[i] = 0;` | statement | yes — the only limb there is |

Gather is right exactly once, where the grammar left it no choice.

This is a better handover than scala and elixir were. Those were whole-file
regressions in grammars this lane does not own; this is three lines of verilog,
one state, one terminal, and both limbs printed by `joints state … 1762`.
**Handing over to the quire lane:** in a `seq_block`, on `=` in state 1762, the
press now offers `read on` (→ `variable_decl_assignment`) beside `fold
variable_lvalue -> _identifier` (→ `blocking_assignment`), and the statement
limb is the one wanted in all four cases above.

## What this lane ships, and what it does not claim

The bit is right and it is the root fix: rung 3 can now tell a rank a rule wrote
from a rank it absorbed, which is what all four of the previous repairs were
trying to guess from the outside. It is free on twenty-nine of thirty grammars —
not "cheap", free, byte-identical trees — where B taxed two.

**It is not yet a net win on verilog.** It seats W8 honestly, seats W7
dishonestly, breaks `ident[ident] <= …`, and turns four picorv32 statements into
declarations, and the board prices all of that at zero. On its own it is a wash
that moves the defect from a place no instrument could see to a place with a
three-line reproducer and a named owner. That is worth shipping and it is not
worth calling a fix, and the honest reading of the table above is that this lane
did not seat verilog either.

## The instrument I trust least

**`tool/order.py::miss`, and the mtime rule every harness in `research/` inherits
from it.** Not because it is careless — its docstring is three paragraphs of
hard-won caution about exactly this — but because it is keyed on a *path* and a
*clock* in a tree where a path is not a version, and it is one line of a helper
nobody reads while measuring.

I caught it inside my own work, and it had already flipped my conclusion.

The first time I ran the witness sweep pinned either side, the two tables came
back **byte-identical, including the state numbers**, with W7 and W8 standing on
both. I nearly wrote that down as "the sweep is insensitive to this change".

```python
if folio.stat().st_mtime < BIN.stat().st_mtime:
```

`prov-before` was built at 17:15:59. `prov-after` at 17:50:20. The cached folio
in the shared `.local/standing/` was written at 17:56:48 — newer than *both*
binaries, so `miss()` returned "use it" for both, and the sweep handed
`prov-before` the table `prov-after` had minted.

```text
cached .local/standing/verilog.folio   sha 811e808412d78cbc
prov-before mints                      sha 3ed97566244be7e3
prov-after  mints                      sha 811e808412d78cbc
```

The "before" arm never once read its own table. Both runs measured the after
grammar; the only reason they agreed is that they were the same grammar.

The demonstration is the fix: give each arm its own `JOINTS_WORK`, and the
folio shas separate — and so do the results, from 9 failing witnesses to 7. The
whole of P4 was invisible until then.

The general shape, for whoever hits it next: **a cache keyed on a path plus an
mtime cannot express "which binary made this", and two pinned binaries are
always both older than a folio either of them minted five minutes ago.** The
freshness rule is correct and still answers the wrong question. Until it keys on
the binary's digest the way `standing.py`'s audit rows already key on theirs,
every before/after in `research/` that shares a work directory is measuring one
side twice — silently, and in the flattering direction, because two runs of the
same table always agree.
