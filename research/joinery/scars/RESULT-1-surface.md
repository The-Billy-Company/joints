# Result 1 — the surface, what it cost, and the field of mine that was a constant

`outliner parse --scars` prints one line per repair. It is a **side channel**:
a sorted, disjoint `[]Scar` on `Quire`, parallel to the node array and indexed
by nothing. P1–P4 scored below; the design argument that produced this shape is
in `PREDICTION-1-surface.md` and held up, with one correction I had to make to
my own record after measuring it.

## The surface

```
scar 24582..24594 12B kept unexpected identifier in state 398, 122 heads, +3501 tokens
scar 24626..24627  1B kept unexpected comment in state 398,      1 heads,    +0 tokens
```

| field | what it answers |
|---|---|
| `at` | the byte the parse refused at — the join key every instrument here is indexed by |
| `over` | the byte it read again; `over - at` is what the repair deleted |
| `why` | the refused terminal and the state that refused it, or a lexer's byte |
| `felled` | did the standing chain get carried off and stood back up in state zero, or did the surrounding structure survive |
| `heads` | live readings standing at the refusal |
| `shifted` | tokens shifted when it refused; the delta between neighbours is printed as `+N`, and **`+0` means this refusal is the previous one re-reported against the next token** |

Three things it deliberately is not:

- **Not a node.** Every mend this runtime performs is a *deletion* — skip to the
  next token some root can act on, and under `fell` put the stack down and stand
  it up in state zero. A node over those bytes would invent a parent for text the
  parser explicitly refused, and would move `built` on every board that counts
  bytes under nodes.
- **Not an annotation.** There is no node to annotate: a scar sits *between* the
  subtree built before the refusal and the one built after it, and an annotation
  would have to pick one and lie about the other.
- **Not spelled `[start, end)`.** That shape means "a node covers these bytes"
  everywhere else in the binary and here it means the exact opposite, so a reader
  pattern-matching node lines cannot match these by accident. `--scars` replaces
  the tree on stdout rather than interleaving with it.

`Quire.mends` stays a `u32` count and `Quire.skipped` stays a byte total. Adding
a field beside them rather than widening either is what let this land in a file
another lane is actively editing without touching a line it holds.

## The field that was a constant, which I found by looking

`heads` was first spelled `roots` and recorded `x.roots.len()` **after** the
unwind, on the argument that a break should report the structure that survived
it. Under `--mend=keep` nothing is ever unwound, so it read **0 on every scar of
every grammar in the corpus** — 66,395 records, one value. It passed every test
in this dossier, because a constant agrees with itself.

What caught it was not a test. It was printing the field for all fourteen
mending grammars and noticing the `min` and the `max` were the same number.

Counted at the refusal instead — before either branch touches `live`, since both
clear it — it reads 1 to 3, and **28 of 66,395 scars are met by more than one
live reading**. So the corrected field is honest but nearly degenerate on this
corpus: by the time this parser refuses, the GLR fork set has almost always
already collapsed to one. That is a finding about the runtime and I am reporting
it rather than quietly keeping a column that is 1 everywhere. The 28 are the
breaks where an ambiguity collapsed instead, and they are the ones a consumer
ranking repairs would want first.

---

## P1 — the side channel disturbs no byte on the board · **HELD**

Arm and isolation control, audited separately, each with its own folio cache and
oracle seat:

| | binary | `built` | `square` | rows moved |
|---|---|---|---|---|
| arm | `c7ad0942e6a1fbd9` | 399,871 B | 311,540 B | — |
| control | `e1e3ae3bc7b7e735` | 399,871 B | 311,540 B | **0 of 30** |

Byte-identical on both columns for all thirty rows. The control is the isolation
arm: today's live tree with my six edits reverted and the plumbing left in, so it
carries every sibling's in-flight work and differs from the arm only by this
lane.

**Identical evidence is `vacuous` unless the instrument could have moved**, and
this board can: substituting an older pin for the arm binary shifts the same
columns immediately. So "no row moved" is a measurement here and not a silence.

## P2 — one mending parse against the warm peel's 400 rounds · **HELD on both stated terms, and not a superset**

`python3 research/joinery/scars/seat.py --from-json … --warm .local/reprice/warm2.json`

| grammar | warm rounds | distinct bytes warm found | distinct bytes one parse found | of warm's, covered |
|---|---|---|---|---|
| haskell | 400 | 400 | **16,634** | 100% |
| sql | 400 | 400 | **991** | 56% |
| swift | 400 | 400 | **438** | 0% |
| verilog | 400 | 400 | **48,339** | 92% |

The prediction was "at least as many distinct refusal bytes, in under 1% of the
wall clock". Both hold: every row enumerates more, by 1.1x to 121x, and sql's
warm seat costs **12.37 s** against **16.0 ms** for the one scars parse — 773x,
where the falsifier was 100x.

**What I did not predict is that the two sets are not nested**, and the reason
matters more than the ratio:

- **swift's 0% is the tree moving under a cached instrument.** Warm's survey is
  from the tree where swift refused at byte 1492; a sibling has since landed a
  lexer fix and today's binary reads to 24,582 before it refuses at all. Every
  one of warm's 400 swift bytes is a wall that no longer exists. This is the
  hazard `TESTING.md` names, caught in my own lane, and it is why the `untested`
  resolution below is reported against a freshly-derived board and not against
  the re-price's published one.
- **sql and verilog miss for a real reason.** Warm *blanks* the wall byte, so its
  next round reads a file this parse never sees. One mending parse cannot reach
  a byte that only exists after a deletion. The surfaces answer neighbouring
  questions, and a lane wanting warm's exact population still needs warm — it
  just no longer needs it to answer "where does this file refuse".

## P3 — `+0 tokens` finds the cascade · **HELD in shape, wrong in the byte**

Predicted: swift's scar list shows a first scar at 1492 followed by a run of
`tokens == 0`. Measured, on today's tree:

```
scar 24582..24594 12B kept unexpected identifier in state 398, 122 heads, +3501 tokens
scar 24622..24625  3B kept unexpected let in state 398,          1 heads,    +4 tokens
scar 24626..24627  1B kept unexpected comment in state 398,      1 heads,    +0 tokens
scar 24778..24784  6B kept unexpected identifier in state 141,   1 heads,   +23 tokens
scar 24785..24786  1B kept unexpected comment in state 141,      1 heads,    +0 tokens
scar 24786..24787  1B kept unexpected comment in state 141,      1 heads,    +0 tokens
```

The predicted phenomenon is exactly there; the predicted byte is from the tree
warm was measured on, for the reason in P2. Corpus-wide the field earns its keep
outright: **48,154 of verilog's 48,339 scars and 16,632 of haskell's 16,634
shifted nothing**. The re-price needed one whole extra parse per byte to make
that call. It is now one integer already on the record.

## P4 — free on a clean parse, under 3% on the worst · **HELD**

Whole-board wall clock, three runs each in separate processes — arm median
**1.23 s**, control median **1.26 s**. Per-grammar parse, median of nine:

| grammar | control | arm | delta |
|---|---|---|---|
| verilog | 75.7 ms | 77.1 ms | +1.9% |
| haskell | 23.9 ms | 23.7 ms | −0.6% |
| swift | 58.7 ms | 57.2 ms | −2.5% |
| sql | 16.2 ms | 16.6 ms | +2.5% |
| html | 5.3 ms | 5.5 ms | +4.9% |
| php | 31.2 ms | 31.0 ms | −0.6% |

No grammar moves more than 10%; the largest reading is html, which mends zero
times and therefore cannot have paid for a scar, so +4.9% is the noise floor of
a 5 ms measurement rather than a cost. The append is one `ArrayList` push per
mend on a path that was already allocating.

## Tests

`zig build test` fails on shard 27/32 under the full run and **passes in
isolation** (`brigade 27/32: 11 passed, 0 skipped, 0 failed`), which is the flap
`TESTING.md` attributes to siblings' in-flight edits to `src/kernel/lex/` and
`src/kernel/quire/`. Confirmed before writing this rather than after.
