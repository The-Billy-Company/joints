# RESULT-2 — why 5,241 wide cells bought zero bytes

[RESULT-1-arity.md](RESULT-1-arity.md) found that verilog holds 5,241 of the
corpus's 5,614 multi-drop cells (93%) and 7,199 of its 7,584 unreachable
readings (95%), and gained **nothing** from the widening that took cpp from 185
to 1,408 square. This is why.

**The short version.** Three independent filters stand between a wide cell and a
byte, and verilog fails all three. 83% of its wide cells are never entered; the
17% that are entered opened 1,808 extra forks; and **every one of those 1,808
died** — 1,674 merged away, 134 refuted, net standing readings *exactly* zero.
They die because verilog declares **no `prec.dynamic` anywhere in the grammar**,
so `Reading.heft` is identically zero and `Reading.beats` degenerates to
speculation depth, which a rival loses by construction because it is born later
than the reading it split from. All 2,708 of verilog's merges read `heft 0 and
heft 0`. Seven of cpp's seventeen read a nonzero difference, and that difference
is the whole 1,223 bytes.

And underneath all of it: verilog's damage is **not in these cells**. All four
of the defect wall states hold no contested cell at all.

The `residual` label is **correct where it appears and explains 0.3% of the
population** — 16 of 5,241. Hypothesis 1's cheap answer is the wrong one.

---

## The arms

Two pins one change apart, each with its own `OUTLINER_WORK` and its own oracle
seat (`pin.py arm` reports both sighted, 30 of 30 verdicts).

| arm | what it is |
|---|---|
| `arity-control2` | one dropped reading per contested cell (`settle.Conflict.other`) |
| `arity-wide` | every dropped reading (`rest` + the `rival` folio section, split site a loop) |

**Folio identity is not the control here** — the widening changed the folio
format, so every digest moves by construction. The control is `built` per row,
and it can say no: it says **yes** on four rows and **no** on verilog.

| row | control `built` | wide `built` | Δ |
|---|---|---|---|
| c | 893 | 1,444 | **+551** (whole, zero damage) |
| cpp | 1,039 | 1,408 | **+369** (whole, zero damage) |
| swift | 25,279 | 26,091 | **+812** |
| scala | 15,957 | 15,957 | 0 |
| **verilog** | **32,477** | **32,477** | **0** — bit-identical in every column |
| **haskell** | **9,191** | **8,919** | **−272** |

Verilog's zero is a **delta**, so it is invariant to the inter-token-whitespace
question a sibling lane is adjudicating: both arms price it the same way, and
62,180 → 62,180 either way. Nothing here rests on the disputed portion.

---

## Hypothesis 1 — residual/unreachable

**Half right, and not the half proposed.**

`reach.py` crosses the folio's conflict section by class. The label:

| class | verilog contested | of which wide | `forks.zig` |
|---|---|---|---|
| `declared` | 18,710 | **5,225** | enters |
| `unwritten` | 481 | 0 | enters |
| `residual` | 136 | **16** | **declines** |
| `repetition` | 2 | 0 | declines |

**5,225 of 5,241 (99.7%) are `declared`** — the class `forks.zig` does fork. The
sibling lane's `=` cell is real, and `residual` is the right label for it, but
it is 16 cells. The widening is not being declined at the index.

Reachability is the half that holds, and it is bigger. `reach.py --source`
crosses the wide cells against the states a real parse actually splits in:

```text
wide cells        5241 over  188 states, 7199 rival readings
in a state the parse SPLITS in
                   891 over   21 states, 1188 rival readings   (17.0%)
never entered     4350 over  167 states                        (83.0%)
```

**4,350 wide cells (83%) sit in 167 states `picorv32.v` never stands in.** They
are table entries, not ambiguities anybody had. This is not a defect — it is a
1,600-rule grammar having more states than one 94 kB file visits — but it means
the corpus-wide arity headline was counting a population four fifths of which
could not have paid on this file whatever the runtime did.

cpp is the same shape and nobody noticed because its numbers are small: **only
3 of its 27 wide cells (11%) are entered** on `ledger.cpp`.

**Priced: 0 bytes, over 83% of the cells.**

## Hypothesis 2 — carried but refused downstream

**This is the one, and it is exact.**

The `quire` trace, same regex on both arms. A strand that is born either merges
back, is refuted, or is still standing:

| row | arm | split | merged | refuted | denied | standing |
|---|---|---|---|---|---|---|
| verilog | control | 1,688 | 1,034 | 2,669 | 0 | −2,015 |
| verilog | wide | 3,496 | 2,708 | 2,803 | **42** | −2,015 |
| | **Δ** | **+1,808** | **+1,674** | **+134** | **+42** | **+0** |
| haskell | control | 1,632 | 518 | 2,363 | 0 | −1,249 |
| haskell | wide | 2,103 | 536 | 2,750 | 0 | −1,183 |
| | **Δ** | **+471** | **+18** | **+387** | +0 | **+66** |
| cpp | control | 45 | 17 | 31 | 0 | −3 |
| cpp | wide | 45 | 17 | 28 | 0 | 0 |
| | **Δ** | **+0** | **+0** | **−3** | +0 | **+3** |

**1,674 + 134 = 1,808.** Verilog's births and deaths balance to the unit. The
widened record was read, the forks were opened, and the parse ended standing on
exactly the readings it stood on before. That is hypothesis 2 confirmed and
priced: **the record is filled, the fork is taken, and the reading is merged
away one step later.**

The `denied` column is the widening's *cost*. Forty-two forks hit the
`crowd`/`skeins` budget that the control never hit — and they are in states
1832, 2901 and 2903, **none of which holds a wide cell**. The extra strands
crowd out forks somewhere else entirely. On verilog that cost zero because the
denied forks were not buying anything either; the mechanism for haskell's −272
is the same shape.

### cpp gained without splitting once more

The row that should have been read more carefully in RESULT-1. **cpp opens the
same 45 forks on both arms.** Its +1,223 square is not extra forks — it is
*three strands not being refuted*, because at the same fork site the wider
record cast a different limb. RESULT-1 attributed the 1,223 bytes to "those 27
cells"; only 3 of the 27 are entered, and the trace diff shows the gain arriving
at states 1627, 499 and 1091. The attribution to arity was too coarse. The
mechanism is right and the byte count is right; the cell count in that sentence
is not what earned it.

## Hypothesis 3 — precedence erased before the cell

**Falsified, and replaced by something sharper.**

Nothing is erased. **Nothing was ever written.** `reach.py` counts productions
carrying a nonzero `prec.dynamic`:

| grammar | wide cells | keyed productions |
|---|---|---|
| scala | 42 | 306 |
| kotlin | 62 | 270 |
| cpp | 27 | 113 |
| typescript | 79 | 52 |
| c | 6 | 44 |
| **haskell** | **92** | **0** |
| **verilog** | **5,241** | **0** |

**The two keyless grammars hold 5,333 of the corpus's 5,614 wide cells — 95%.**

`Reading.beats` consults `heft` (the running sum of `prec.dynamic` over
everything a reading has folded) and falls back to `rank`, the speculation
depth. On a keyless grammar `heft` is identically zero for every reading, so
`beats` **is** depth — and a rival is born later than the reading it split from,
so it carries the strictly higher depth and loses every time, both to `collapse`
where the two fold back onto one state stack and to `first` where they do not.

A widened record on a keyless grammar can therefore only ever *substitute* a
rival for a reading that died. It can never let one be **preferred**.

The `merged:` trace line prints both hefts, so this is not an argument:

| grammar | merges | heft pairs |
|---|---|---|
| verilog | 2,708 | **`0 vs 0` — all 2,708** |
| haskell | 536 | **`0 vs 0` — all 536** |
| cpp | 17 | `2 vs 2` ×8, `2 vs 4` ×3, `3 vs 5` ×2, `0 vs 0` ×2, `6 vs 8`, `3 vs 4` |

**Seven of cpp's seventeen merges are decided by an unequal nonzero heft.** Not
one of verilog's 2,708 could be. That single column is the difference between
+1,223 bytes and zero.

Haskell is the confirming case, and it confirms in the unflattering direction:
also keyless, 66 rivals *did* survive (their incumbent was refuted, so
substitution applied), and the row **lost 272 bytes**. When the only thing a
keyless grammar can do with a rival is substitute it for a corpse, the
substitute is not reliably better.

**Priced: 0 bytes on verilog, −272 on haskell, and the mechanism is proven
rather than inferred.**

## Hypothesis 4 — the damage is not conflict-shaped

**Confirmed, and it is the floor under everything above.**

Even a surviving rival would have to be somewhere near the damage.
[`../verilog/README.md`](../verilog/README.md) attributes the whole file to four
defects. Crossing their wall states against the conflict section:

| defect | bytes | wall | contested cell there? | wide cell there? |
|---|---|---|---|---|
| a directive in statement position | 21,535 | `` ` `` in 1108 | **no** | no |
| a select inside a concatenation | 19,928 | `;` in 701 | **no** | no |
| `$signed` both sides | 360 | `(` in 3772 | **no** | no |
| an indexed blocking lvalue | 93 | `=` in 2394 | **no** | no |

**Not one of the four walls is a contested state.** This independently
reproduces RESULT-2-splice ("all three walls named states that hold no contested
cell at all") from the other direction, and extends it to the fourth.

And 45,102 of verilog's 62,180 damage bytes — **72.5%** — are `spoil`, bytes the
parse never reached at all. A fork changes which tree is built over bytes that
are read. The largest single bucket of verilog's damage is bytes that are not.

---

## What I did not repair, and why

Three directions out of the merge. Two are already closed by measurement in
[RESULT-5-merge.md](../verilog/RESULT-5-merge.md): keeping the higher rank costs
**23,985 bytes** of agreement with tree-sitter (elixir falls from 23,879 square
to one), and declining the merge costs **57,627 bytes** and hands back the same
trees.

The third is the one this lane's finding newly makes visible, and I am declining
to ship it: **gate the widening off on keyless grammars.** It is measurable
without a build, because the control arm *is* the gated arm on exactly the two
keyless rows — so it is worth **+272 bytes** (haskell restored, verilog
unchanged, keyed rows untouched by construction). That is a feature-disable
wearing a repair's clothes: it turns the mechanism off over 95% of the cells it
was built for to recover 272 bytes, and it would make the arity number
permanently unpayable. Not worth it.

**What can actually move these bytes** is the tie-break, not the merge.
`Reading.beats` has two rungs, heft then depth, and on a keyless grammar the
first is vacuous and the second is arbitrary — "born later" is not a claim about
which tree is right. Tree-sitter's `ts_parser__condense_stack` has a third rung
we do not: after error cost and dynamic precedence it compares the *subtrees*
structurally, and only then falls back to keeping the earlier version. A
structural tie-break is the rung that would give a keyless grammar's 5,333 wide
cells something to win with. It is real work in `gather.zig`, which two other
lanes are editing right now, so this is a handoff and not a patch.

Note for the lane on `collate.py prove`: **I moved no tables.** Everything here
is measurement and one script under `research/joinery/arity/`.

## What I trust least

1. **`--source` is one file per grammar.** The 83%-never-entered figure is a
   statement about `picorv32.v`, not about verilog. A different file enters
   different states. The class and keys columns are properties of the table and
   do not have this problem; the reach column does, and `reach.py` prints the
   file name in the header for that reason.
2. **The balance sheet is a count of strands, not an identity of them.** Δbirths
   = Δdeaths proves the *number* standing did not move. It is verilog's
   bit-identical board that proves the same *readings* survived; on its own the
   arithmetic would permit a swap.
3. **`standing` is negative on every row**, because `refuted` counts incumbents
   dying as well as rivals. Only the delta is meaningful, and only against the
   same binary pair.
4. **Verilog is 100% unjudged** — its oracle disagrees with itself — so every
   verilog number here is `built`/`damage`, never `square`. The square figures
   quoted for cpp, c and elixir come from the arms' own oracle seats.
5. **The keyless argument is mechanical, not exhaustive.** I proved `heft ≡ 0`
   from the production table and confirmed all 3,244 merges across both keyless
   grammars read `0 vs 0`. I did not prove that no path through `gather` can
   prefer a later-born rival for some other reason; I proved that neither
   `collapse` nor `first` does.

## Reproduce

```bash
eval "$(python3 tool/pin.py arm arity-wide)"
python3 research/joinery/arity/reach.py                       # class x arity x keys, corpus
python3 research/joinery/arity/reach.py \
    --source upstream/sources/picorv32.v upstream/grammars/verilog.json
```
