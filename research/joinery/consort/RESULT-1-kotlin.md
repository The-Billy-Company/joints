# Result 1 — kotlin's rows never touch; the 40 KB is one gate counted twice

## The claim being resized

`vacuity/RESULT-5-pairs.md`: `worth(2) = +20,737`, `worth(12) = +19,229`,
`joint = +19,678`, residual **−20,288**, verdict *cooperating*, with the reading
*"each row alone destroys kotlin"* and *"they are two permissions the same walk
needs."*

The arithmetic is right and re-derives to the byte. The word *cooperating* does
not survive a second fixture.

## The two rows

| row | seat | terminals it needs |
|---|---|---|
| 2 | `_string_start/.fence/.kotlin` | `_string_start` `string_content` `_string_end` … (6) |
| 12 | `_automatic_semicolon/.caesura/.kotlin` | `_automatic_semicolon` `_by_delegation_hint` |

**They compete for nothing.** The only name in both is `_by_delegation_hint`,
an evidence marker the roster never emits; the emitted sets are disjoint. That
was P1 and it holds.

## Falsifier 1 — each row moves its own construct by the same amount either way

Three fixtures, four arms, from `gate.py`. `aud-base` is both rows in, `aud-rN`
is row N out, `aud-r2-12` is both out.

| fixture | arm | verdict |
|---|---|---|
| `val a = 1` ⏎ `val b = 2` | both in | accepted, 1 root |
| | **row 2 out** | **accepted, 1 root** |
| | row 12 out | `unexpected = at 16` |
| | both out | `unexpected = at 16` |
| `val a = "x"` | both in | accepted, 1 root |
| | row 2 out | `unexpected at 8, no stand-in for _string_start` |
| | **row 12 out** | **truncated — input ended before the start symbol closed** |
| | both out | `unexpected at 8, no stand-in for _string_start` |

Read the columns, not the rows. On the separator fixture, **row 2's presence
changes nothing at all** - `worth(2) = 0` exactly, in both row-12 states. On the
string fixture, removing row 2 produces the identical failure at byte 8 whether
row 12 is seated or not. Each row's effect on its own construct is invariant in
the other's state, which is the definition of independence and the exact
opposite of *"one row's mechanism depends on the other having consumed
something."*

The one asymmetry is honest and is row 12's own: with the caesura un-seated the
one-statement file is `truncated`, because in kotlin the caesura is what closes
a statement at end-of-input too. That is row 12 acting on row 12's construct.

## Falsifier 2 — the residual follows the file, not the rows

Two fixtures, 200 statements each, identical except for **which line carries the
one string literal**:

| fixture | string at byte | worth(2) | worth(12) | joint | residual |
|---|---:|---:|---:|---:|---|
| `kotlin-gate-early.kt` | 52 | 13 | 601 | 602 | −12 |
| `kotlin-gate-late.kt` | 2,698 | 203 | 601 | 602 | **−202** |
| `kotlin-separator-only.kt` | *none* | **0** | 5 | 5 | **+0** |

`worth(12)` is 601 on both, because the caesura gates all 200 statement
boundaries. `worth(2)` swings 13 → 203 and the residual swings −12 → −202 with
nothing changed but a byte offset. On a fixture with no string at all the pair
is **perfectly additive**. A coupling between two rows cannot be switched off by
moving a literal down the page.

## The mechanism, which is arithmetic on reach

`built` is bytes under a construct and a walk reaches bytes in file order. The
head of `Maps.kt`:

```text
byte 210  @file:kotlin.jvm.JvmName("MapsKt")     ← the first file annotation
byte 245  @                                       ← the SECOND one begins
byte 270  "                                       ← the string inside it
byte 388  .                                       ← where a healthy walk gets to
```

Two gates, **25 bytes apart**, and 35,571 bytes of file behind them.

| arm | first stop | built | of 35,815 |
|---|---|---:|---:|
| both in | 388 `_import_dot` | 35,571 | 99.3% |
| row 12 out (caesura) | **245** `_automatic_semicolon` | 16,342 | 45.6% |
| row 2 out (fence) | **270** `_string_start` | 14,834 | 41.4% |
| both out | 245 `_automatic_semicolon` | 15,893 | 44.4% |

The caesura clears the gate at 245 - the parser needs a statement separator
before the second `@file:` - and the fence clears the one at 270. Clearing only
the caesura advances the walk **25 bytes** and buys +449. Clearing only the
fence advances it **zero** bytes and costs −1,059, because the walk still stops
at 245 and lands its mend recovery somewhere marginally worse.

So each single-row arm measures *"the file behind both gates"*, and both measure
the **same** 19,678 bytes. Summing them counts that stretch twice. That is the
40 KB, and it is one 20 KB gate reported by two instruments that were each
holding the other gate open.

## What kotlin's seating is worth

- **The pair is one unit: +19,678 B.** That is the whole of it.
- `worth(2) = +20,737` and `worth(12) = +19,229` are each **true as marginals**
  - what that row buys *given the other is already seated* - and neither is what
  the row buys. They may not be added, averaged, or quoted as a per-row figure.
- The only per-row credit that adds back to the pair is the Shapley split, over
  both orders:

  | row | alone | marginal given the other | **credit** |
  |---|---:|---:|---:|
  | 2 `_string_start/.fence/.kotlin` | +449 | +19,229 | **+10,593** |
  | 12 `_automatic_semicolon/.caesura/.kotlin` | −1,059 | +20,737 | **+9,085** |
  | | | | *sums to 19,678* |

## Where the record needed the qualifier, and where it did not

**Did not.** The historical `+20,728` in `board/RESULT-2-flatter.md`,
`orphan/`, `sigil/` and `specimen/RESULT-1-coverage.md` is the fence's landing
delta, measured on a tree where the caesura was **already in** (the caesura
landed first, and cost kotlin 1,075 bytes doing so). It is the same marginal the
ablation re-derives as 20,737, and it is true. Those pages describe one landing
and are correct.

**Did.** Two places put both marginals in one column with no marker that the
column may not be summed:

- `vacuity/RESULT-2-arms.md`'s `worth` table, rows 1 and 3;
- `changelog.d/+fourteen-rows-were-seated-today-…`'s table, lines 18–19.

The changelog fragment carries a prose caveat below its table (*"Kotlin's two
rows are not additive"*), and that sentence has its own defect: it says
*"removing either restores about 20,000 bytes"* where removing either **costs**
about 20,000. A correction note is appended to each; neither number is edited,
because both are true.

## The hazard this turned up and did not fix

Kotlin's caesura row spells **no `hushed` list**, where ecma's spells
`_template_chars` and `jsx_text` precisely so a break is never inserted inside a
template body. Today that costs nothing - measured, not assumed: with the fence
seated the caesura does not misfire in a string (`val a = "x"` is accepted), and
with the fence un-seated the walk never enters a string body to find out. So
there is no arm on this tree that can show the hazard, and adding a suppressor
with no falsifier behind it would be a change nothing can judge. Recorded here
as an unproven hazard rather than a fix.
