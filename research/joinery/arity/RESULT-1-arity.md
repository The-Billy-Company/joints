# Result — a contested cell that can only name one loser

Two defects, one data structure, and they are not the same defect. Measured on
one frozen oracle (`attest.py freeze arity`, tree-sitter 0.26.11) across three
arms one change apart:

| arm | what it holds |
|---|---|
| `arity-control2` | control, tree `37700c1f2d0d` |
| `arity-unwritten` | + a frayed unranked read/fold cell is `unwritten`, not `residual` |
| `arity-wide` | + a contested cell carries every dropped reading, not one |

## The headline

**+1,900 square corpus-wide. No row loses a square byte. 25 of 30 rows
bit-identical end to end.**

| | Δ square | Δ built | Δ damage | Δ crooked |
|---|---|---|---|---|
| cpp | **+1,223** (185 → 1,408) | +369 | −369 | −680 |
| c | **+677** (767 → 1,444) | +551 | −551 | −21 |
| swift | 0 | +812 | −812 | **+839** |
| ruby | 0 | +88 | −88 | **+66** |
| haskell | 0 | **−272** | +272 | −36 |

Both cpp and c now read their whole fixture perfectly: 100% standing, zero
damage, zero orphan, zero rubble. cpp's gain is *above* the C++ lane's predicted
883–1,197 band.

The two changes separate cleanly, and that separation is the finding:

- **The widening is the entire square gain.** cpp +1,223, c +677, haskell's
  −272 built. 27 of 30 rows bit-identical.
- **The class fix buys no square at all.** swift +812 built and **+839
  crooked**; ruby +88 built and +66 crooked. 28 of 30 rows bit-identical. It
  converts damage into `built` and the newly-built bytes disagree with the
  oracle. Judged on the only column that is a claim about a second parser, it is
  worth a construct and not a byte.

## Q2 — did swift's `if let` need the widening, or only the ordering?

**Only the ordering, and it is proven in both directions on two nineteen-and-a-bit
byte witnesses.**

```
func f() -> Int { if let limit = limit { return limit }; return 0 }
  control      press? on integer_literal in state 1103 (0 dropped, 3 misfolded)
  unwritten    accepted, 1 root          <- fixed by the class change
  wide         accepted, 1 root          <- widening adds nothing

void g() { f(y); }
  control      compound_statement (declaration …)
  unwritten    compound_statement (declaration …)          <- class change adds nothing
  wide         compound_statement (expression_statement …) <- fixed by the widening
```

Swift's cell drops exactly one reading; the corpus survey finds **3** cells in
all of swift that drop more than one, and none of them is this. Swift had exactly
**one** `residual` shift/reduce cell in the whole grammar (10,605 declared, 1
residual); it is now zero. That one cell was the `if let`.

So these are two different claims about what the press was doing wrong:

- **cpp**: the press *recorded* one loser where the grammar declared three
  readings. The reading tree-sitter takes was never a strand, and no ordering
  could have produced it — which is exactly why the dynamic-precedence lane moved
  cpp zero bytes.
- **swift**: the press recorded both readings and then **its own class label
  threw one away**. `forks.zig` offers a fork for `declared` and `unwritten` and
  declines one for `residual`, and a frayed cell where an unranked fold loses to
  a read on a level nobody wrote was being called `residual`. Silence is not a
  decision. 598 cells across 10 grammars change class; no cell changes `chosen`.

## Q3 — the arity count

`research/joinery/arity/arity.py`, reading the folio directly:

```
5,614 of 85,786 contested cells (6.54%) drop more than one reading,
and carry 7,584 reading(s) a binary fork could not.
widest cell on the corpus drops 5 reading(s) past the first.
```

| grammar | cells | wide | rivals | spread (extra readings : cells) |
|---|---|---|---|---|
| verilog | 19,329 | **5,241** | **7,199** | 1:3891 2:935 3:311 4:15 5:89 |
| haskell | 5,672 | 92 | 92 | 1:92 |
| typescript | 2,207 | 79 | 79 | 1:79 |
| kotlin | 10,190 | 62 | 62 | 1:62 |
| scala | 8,477 | 42 | 42 | 1:42 |
| go | 218 | 28 | 28 | 1:28 |
| cpp | 4,069 | **27** | 27 | 1:27 |
| java | 219 | 22 | 22 | 1:22 |
| php | 172 | 10 | 22 | **2:8 3:2** |
| c | 1,138 | 6 | 6 | 1:6 |
| swift | 10,680 | 3 | 3 | 1:3 |
| javascript | 659 | 2 | 2 | 1:2 |

Eighteen grammars have none. **Verilog holds 93% of the cells and 95% of the
readings**, which makes it the only grammar where cell arity is structural rather
than a handful of sites, and every other row a rounding error beside it. cpp's 27
are all exactly ternary — and they are the whole of its worst-row-on-the-board
defect, which is the ratio worth noticing: 27 cells of 85,786 were worth 1,223
square bytes. PHP is the only grammar whose cells go deeper than one extra
reading in bulk.

The distribution matters more than the total. Verilog's `1:3891 2:935 3:311
4:15 5:89` says a fork widened to carry **three** readings recovers most of what
one widened to carry nine would.

### The bound, and why it is not a silent one

A column keeps `column.spares_max` tied reductions past `rival`, so it can report
at most `spares_max + 1` dropped readings. A bound sitting exactly on the widest
thing it has been shown is indistinguishable from one that has been truncating
all along, **because the number it reports is the number it can hold**. So:

- `spares_max` is 8 where the corpus's widest cell needs 5.
- `arity.py` **exits 1** if the widest cell ever reaches the bound, rather than
  printing a floor as a total.
- Raising it from 6 to 8 moved **no number**, which is the positive control that
  it was never truncating.

## Predictions, scored

Five hits, two misses, two half-misses. The misses first.

**P4 — MISS on magnitude.** I said "low hundreds corpus-wide". It is 5,614 cells
and 7,584 readings — an order of magnitude out. I had verilog as "the most likely
leader" (hit) but predicted verilog + cpp + typescript would hold "over half";
verilog alone holds 93%, and cpp's 27 and typescript's 79 are noise. Right
grammar, wrong scale, and right conclusion for the wrong reason.

**P8 — MISS on scope.** I said the trailing-separator extent gap would be
"corpus-wide". It is not corpus-wide at all — see below. Not mine: hit.

**P2 — HALF.** "Swift's cell is `residual` and that is the whole bug." The class
diagnosis was exactly right — one residual cell in the grammar, and it was that
one. But "the whole bug" was the wrong boundary: the 28 KB fixture still walls,
128 → 108 roots and not `accepted, 1 root`. The brief's target is **not met**.

**P3 — HALF, and the boundary I drew was the useless half.** `chosen` moves
nowhere: the `.eq` arm's assignments to `chosen` are untouched and only the
*dropped* actions are now retained, and the press test asserts the table's cell
equals the recorded `chosen` at every contested address. But I wrote *"if any
row's folio digest moves, I have made a mistake rather than a discovery"*, and
that was wrong by construction — the widening **changes the folio format**
(`ConflictRecord` grows `rival_off`/`rival_len`, a `rival` section is appended),
so every folio's bytes and schema digest move whatever the tables say. Folio
identity was therefore worthless as a control on this change and I had to
substitute board-row identity (27 of 30) plus the address assertions.

**P1 — HIT.** Swift did not need the widening. Proven both ways.

**P5 — HIT, and this was the one most worth being wrong about.** cpp's third
reading was a *tied fold dropped by the two-slot bound*, not erased at rung 1 by
precedence. Had it been erased, widening the record could not have recovered it
and the witness would still read `declaration`. It reads `expression_statement`.

**P6 — HIT, exactly.** The widening moved cpp's square (+1,223) and swift's not
at all (+0).

**P7 — UNSETTLED, not hit.** No row that is whole today lost anything and no row
lost square, so nothing observable bound. But I did not read the per-row denial
counters after the widening, so I am not entitled to the claim. Recorded as
unverified rather than scored.

## Q4a — is the extent gap corpus-wide? No, and it is a statement-separator family

I counted racked runs where **our node name equals the oracle's** — a pure extent
disagreement rather than a shape disagreement — over the widest runs `rack.py
show` prints:

| grammar | same-name runs | bytes | different-name runs | bytes | same-name node |
|---|---|---|---|---|---|
| swift | 20 | 3,167 | 0 | 0 | `statements` (**100%**) |
| ruby | 7 | 183 | 0 | 0 | `body_statement` |
| kotlin | 2 | 136 | 4 | 94 | `statements` |
| toml | 3 | 16 | 1 | 9 | `pair` |
| haskell | 4 | 64 | 16 | 307 | `apply` |
| scala | 1 | 42 | 19 | 6,972 | — |
| elixir · verilog · ocaml · sql · julia | **0** | **0** | 20 each | 11,843 / 665 / 1,894 / 163 / 114 | — |

So it is **not** a cheap corpus-wide correction. It concentrates in exactly the
grammars with an optional or implied statement terminator — swift, kotlin, ruby —
and swift is the extreme case where *every* one of its widest racked runs is
`statements` against `statements`. That is the same defect as the implied-semi
finding, seen from the other side: the separator the oracle folds into the extent
is the one we never shifted.

Everything the brief grouped with swift "under the same signature" is a genuine
shape bug instead. Elixir's 11,843 crooked bytes are `arguments` against
`do_block` — 100% different-name, zero extent gap. Scala's are `block_comment`
against `function_definition`; ocaml's are `match_expression` against
`let_binding`. Those are not extents and nobody should go looking for three bytes
in them.

## Q4b — the implied separator, and swift's remaining wall

Not settled, but narrowed, and it is **not** the cell I fixed.

Swift's fixture now walls at byte 24,582 — `let baseStartIdx = baseIdx ??
baseBound` — in **state 1103**, whose entire item set is:

```
_fn_call_lambda_arguments_repeat13 -> simple_identifier . : lambda_literal
   1 terminal(s) accepted of 224 — `:`
```

That is a lambda **argument-label** state. So at 24,582 the parse is still inside
`_fn_call_lambda_arguments` — the trailing-closure misread the brief names, at a
*second site*, several hundred bytes past the `if let` I fixed. The brief said
the two readings are separated only by `PREC_DYNAMIC(-1)` on
`_fn_call_lambda_arguments` under **three** single-symbol conflicts; I repaired
the cell that guards one of them, and the fixture proves the other entries are
still open. Swift's remaining 10,605 conflicts are all `declared` — already
forkable — so what is left is not a class problem at all: it is ordering among
readings that already fork, or capacity, or the lexer. It is the next lane's, and
it is a narrower question than the one I was handed.

## The instrument I trust least

**`rack.py show`'s `worst` list, which is what every number in Q4a rests on.**

Not because it is wrong — it reports what it says. Because it prints only the
*widest* runs per grammar, so "swift is 100% same-name" is a statement about
swift's twenty largest disagreements and I have quietly presented it as a
statement about swift. The direction of the bias is unknown to me: small runs
could be overwhelmingly same-name (making the effect larger) or overwhelmingly
shape (making it smaller), and a three-byte extent gap is by construction a
*small* run, so the population I cannot see is exactly the population the claim
is about. Passing its own checks does not clear it, because it makes no claim
about coverage to check.

Two more, briefly. **`damage` is not a proxy for anything**, and cpp was the
proof before this change: 369 damage against c's 551 and one quarter the square.
A board sorted by damage put cpp ahead of c while cpp had every parent wrong.
And the **`unwritten` reclassification's own falsifier** was a bucket count
(`residual.shift_reduce == shared`) that my change moved. I did not update the
number — a count in a bucket is satisfiable by an unrelated cell arriving in the
bucket. It now asserts the addresses: every contested cell is at a state that
reads `=`, carries the read as `chosen`, and is offered exactly one fork.

---

**Followed by [RESULT-2-reach.md](RESULT-2-reach.md)**, which took the 5,241
verilog cells above and priced why they bought zero: 83% are never entered, the
rest opened +1,808 forks that balance exactly against +1,674 merges and +134
refusals, and verilog declares no `prec.dynamic` at all — all 2,708 of its
merges read `heft 0 and heft 0`, so a rival can never be preferred, only
substituted. It also corrects two attributions on this page. cpp opens the
**same 45 forks on both arms**, so its 1,223 bytes are three strands not being
refuted at an existing site rather than 27 cells paying out; and only 3 of those
27 cells are entered on `ledger.cpp` at all.
