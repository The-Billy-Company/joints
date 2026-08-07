# Result 1 — Kotlin's string fence, seated

Measured against `PREDICTION-1-sigil.md`, written before a line of `fence.zig`
moved. Ten predictions; **two failed**, and both failures are the findings.

Pins: `lex-before` (binary `dfc481e49`) and `lex-after` (`c7bc59177`, kotlin
only) and `lex-swift` (`08150f7e7`, kotlin plus swift's comment), plus
`lex-final` (tree `273999fd4d9e`) re-pinned from the tree at hand-off. Every
before/after below is one of those against another, never a rebuild of
`zig-out` — see the instruments section for what happened the one time I let a
tool reach for `zig-out` itself.

The full suite passes: `zig build test --summary all`, 32 of 32 shards green,
exit 0.

## What landed

`fence.Dialect` gains `kotlin`; `fence.Span` gains `prefix_len`; `fence.Read`
gains `enters`; `outside.Troupe`/`Cast` gain `sigils`. One new troupe row seats
five of kotlin's eight blind externals — `_string_start`, `_string_end`,
`string_content` and both interpolation starts — held off ruby, which shares the
anchor, by `_by_delegation_hint`.

The reader is its own function rather than four more flags on the shared driver.
All three of kotlin's moves differ from the driver's, and splitting is what
makes the other four dialects byte-identical by construction rather than by
inspection.

## Specimens — the correctness test

**28 of kotlin's 29 claims hold, up from 1.** Five of the six specimens are
whole; the sixth holds 4 of 5, and its outstanding claim is unsatisfiable (see
below).

```
FAIL kotlin/embedded-quote.kt        4/5   lacks simple_identifier - got present
ok   kotlin/escaped-quote.kt         4/4
ok   kotlin/greedy-close.kt          5/5
ok   kotlin/interpolation.kt         7/7
ok   kotlin/nested-interpolation.kt  7/7
ok   kotlin/unterminated.kt          1/1
```

`val s = "a ${n + 1} b"` no longer returns a `lambda_literal`. `"${"$n"}"` — the
case a stateless hand structurally cannot reach — builds both literals at their
right extents, because the outer span sits under the interpolation while the
inner one pushes its own.

The tier grew while this ran (other lanes are adding specimens), so the headline
moved 7/17 → 14/20 rather than 7/17 → 12/17.

## P1 failed, and the specimen was right where I predicted the scanner

I predicted `greedy-close.kt.expect`'s `spans string_content 11 13` contradicted
the pinned `scan_string_content`, which swallows all four quotes of `"""a""""`
into its end token and hands back `a`. That prediction about the C is correct —
but I implemented the specimen's reading instead, and the specimen is right.

`"""a""""` **is** the string `a"` in Kotlin. A raw literal terminates at the last
`"""` in a run, and `string_content` is the node a reader takes the value from,
so a content span of `[11, 12)` is a correct parse carrying a wrong value.
tree-sitter-kotlin's own comment says it saw "no point in going to the effort of
specifically separating the string end from string contents" — an incidental
artifact of a parser that never needed the value, not a specification of the
language. The grammar's raw-string rule and the language reference agree with the
specimen.

So: **this hand deliberately diverges from the pinned scanner in one place**, and
it is the place the specimen tier was built to pin. `spans string_literal 8 16`
holds under both readings; only `string_content` discriminates.

## P4 failed — `describes` rose by 303, not by more than 400

Corpus-wide **97,595 → 97,898 nodes**, all of it kotlin (8,322 → 8,625). I
predicted more than 400 on the reasoning that a seated fence builds
`string_literal(string_content)` where the ablation built a bare
`simple_identifier`, so it should beat the ablation's +258.

It beat it by 45, not by 150. The reason is a flattering assumption inside my own
argument: not every literal becomes two nodes. `_string_start` and `_string_end`
are hidden in kotlin's grammar, an empty `""` builds `string_literal` with no
content child at all, and `Maps.kt`'s 45 literals are mostly short single-token
strings. The prediction priced the shape I was proud of rather than the shape the
file holds.

The direction is what the check is for and the direction holds: `built` rose
20,728 bytes while `describes` rose 303 nodes, so the fix reads *more*, not less.

## The board, as a consequence and not as proof

| | before | after |
|---|---|---|
| kotlin `built` | 14,841 | **35,569** |
| kotlin `orphan` | 19,705 | **208** |
| kotlin `rubble` | 333 | 22 |
| kotlin `spoil` | 936 | 16 |
| kotlin `damage` | 20,974 | **246** |
| kotlin `roots` | 419 | 11 |
| kotlin **bare leaves** | 237 | **5** |
| kotlin `covered` | — | 100.0% |
| kotlin standing | 41.44% | **99.3%** |
| corpus `built` | 363,987 | 384,715 |
| corpus standing | 69.09% | **73.0%** |
| corpus `describes` | 97,595 | 97,898 |

`built` rose by exactly 20,728 corpus-wide, which is exactly kotlin's own rise,
so nothing else moved a byte. P3 (damage ≤ 1,500, built ≥ 34,300) and P9 (bare
leaves < 20) both hold, and `covered` at 100.0% with 5 bare leaves means the
coverage is not being bought by bare leaves standing over unread bytes.

**P10 stands and is worth repeating.** `Maps.kt` holds 90 `"`, **zero `"""`,
zero `$`, zero `\`**. A stateless `"[^"]*"` regex would have moved every number
in that table by the same amount. The specimens are the only evidence that this
hand is sound; the board is the consequence.

## P5 held — 29 of 30 grammars tree-identical, and only kotlin moved

Compared as trees (`parse --ranges --all`, node names and extents, per file over
the whole 30-grammar roster), never as folio digests.

```
29 of 30 grammars tree-identical
moved: kotlin
```

The prediction I called most likely to fail did not: python, ruby, rust_raw and
heredoc are untouched, which is what the split reader was for.

## P7 held — the residual wall is worth 246 bytes

With the strings gone, `walls.py` names three distinct walls on kotlin: `,` in
state 110, `.` in state 253, and `wildcard_import` in state 436. All three are
the `import a.b.*` cohort the earlier lane flagged — `_import_dot` is the
terminal, and removing it moved `built` by zero and moved `orphan` the *wrong*
way. It is 246 bytes of 35,815, and a lane following the verdict would fix
nothing.

## P6 held, and the ceiling is still unexercised — but the profile is sharper

`outside.Spent.ceiling` carries the whole termination proof and the lane before
me could not find a corpus case that exercises it. Kotlin's interpolation does
not either: every arm of the new reader consumes at least one byte, so it emits
no zero-width answers at all.

Measured rather than asserted, by lowering the constant and re-comparing all 30
grammars as trees:

| ceiling | grammars tree-identical | moved |
|---|---|---|
| 4 | 30 of 30 | none |
| 3 | 30 of 30 | none |
| 2 | 29 of 30 | python |
| 1 | 28 of 30 | python, scala |

So the deepest zero-width run in the corpus is still **three**, and it is
python's. One refinement to hand on: **scala's is two**, which the previous
lane's probe did not separate out — at ceiling 1 two grammars move, not one. The
constant sits at 256 with the whole corpus satisfied at 3.

## The fold half was never unexercised — it just isn't spelled `fold`

The second gap handed over was that `inquest`'s fold branch is dead: *"all eight
findings on the board say `shift`, none say `fold` … a reader would conclude the
fold half never happens."*

That reading is wrong, and the reason is one line of `lalr.zig`:

```zig
.shift => "shift",
.fold  => "lookahead",
```

`Half.fold.word()` prints **`lookahead`**. Grepping the board for `fold` finds
zero rows no matter how many folds there are, which is exactly the conclusion the
handover drew. Swept over all 30 grammars, both pins, counting the findings that
name a stand-in *and* a half:

| pin | shift | lookahead (= fold) |
|---|---|---|
| `lex-before` | 3 | **1** — latex `_trivia_raw_env_verbatim` |
| `lex-final` | 2 | **2** — latex, plus kotlin `_import_dot` |

So the branch was already live before my lane, on latex. What my fix adds is the
second, and it is the useful one: kotlin's finding moves from `_string_start,
admitted by shift` to `_import_dot, admitted by lookahead`. The half is doing
precisely the job it was built for — a lookahead means "this state tolerates that
token on the way somewhere else, and the wall is probably not its", which is the
same near-miss the brief warns about from the other side. A lane reading the new
bracket is told not to chase `_import_dot` before it spends a day on it.

Both statements in the handover are true of the *symbol* and false of the
*string*: the branch runs, the tests cover it, and no board row will ever say
`fold`.

## Two instruments, and the one I trust least

**`walls.py`'s `voice` column, because `stamp.ask().mends` is broken.** The brief
warned about this and it is worth confirming from the other side: `walls.py`
printed `voice 1.0` for kotlin and `2.8` for swift, and `voice` divides by a mend
count that `verdict()` reads as 0 on every grammar that mends. I used `walls.py`
only for its `state`/name lines and took every mend count off `standing.py`. A
lane is fixing that field; nothing here rests on it.

**`tool/specimen.py`'s default binary, caught live at the end of this lane.** It
falls back to `zig-out/bin/joints` when `JOINTS_BIN` is unset, and on the
final verification pass that shared binary reported **7/20** — every kotlin claim
and both swift comment claims red — against a working tree that builds 14/20.
A sibling lane had rebuilt `zig-out` from a different state two hours earlier.
Nothing in the output says so: the run is not marked stale, and a lane that read
it would have concluded its own fix had been reverted. Rebuilt into a fresh pin
(`lex-final`, tree `273999fd4d9e`) and got 14/20 back, identical to `lex-swift`.
This is the brief's "a path is not a version" hazard, confirmed by walking into
it. **Never run the specimen tier without `JOINTS_BIN` pointing at a pin.**

**The one I trust least is `parse`'s own root count as a soundness signal** —
and Swift below is the proof, not a worry. `/* c\n d */` parses today as **one
root with zero mends**, which is every signal this parser emits saying "fine",
while the comment is being read as a division operator and a multiplication.
`roots` and `mends` cannot see a confidently wrong tree; only a specimen with
`holds`/`spans` on it can. That is the same instrument the board's `built` column
is computed from.

## Swift's `multiline_comment` — seated, and it contradicts the brief

Seated on a new `marrow` vein. Swift's `eat_comment` is byte-for-byte kotlin's
`scan_multiline_comment` — same `after_star` flag, same three cases, same
"a `/` not preceded by `*` opens a level when a `*` follows" — with **exactly one
difference**: kotlin accepts an unterminated comment at end of input and swift
returns `STOP_PARSING_END_OF_FILE` and refuses. One walk, two veins, that one
line a parameter. A separate vein rather than kotlin's also keeps the two rows'
pinned permissions apart, which one shared vein could not: both rows anchor on
the same terminal name.

Before, `multiline-comment.swift`:

```
  prefix_expression [10, 14)
    operation: custom_operator [10, 12)     ← the `/*`
    target: simple_identifier [13, 14)      ← the `c`
  multiplicative_expression [18, 22)
    lhs: simple_identifier [18, 19)         ← the `d`
    op: "*" [20, 21)
    rhs: "/" [21, 22)
```

After:

```
  multiline_comment [10, 22)
```

Both comment specimens go 2/4 → **4/4**, including the nested
`/* x /* y */ z */` at `[10, 27)`, which read as a `regex_literal` before.

### The contradiction: it is worth zero bytes on the board

The brief prices this at **3,997 orphan bytes**, the second-largest row in the
blind-comment cohort. That attribution is wrong.

**`upstream/sources/Chunked.swift` contains zero `/*`.** It has 237 `//` line
comments and no block comment at all, so a blind `multiline_comment` cannot be
responsible for one byte of swift's orphan. Measured: swift's row is
byte-for-byte unchanged across the seating — `built 23,131 · orphan 3,997 ·
damage 5,337` before and after — and the whole roster is **30 of 30
tree-identical**.

So **P8 is falsified**. I predicted swift's `built` would fall and its `orphan`
rise by roughly the comment bytes. Neither moved, because the correction is real
and the corpus never asks for it. This is `_import_dot` again with a different
name: a cohort table said where the bytes were and was silent about the file.

What actually walls swift, from `walls.py` — 11 distinct walls, none of them a
comment: `(?:[^\r\n]*)` in state 66 (the `comment` rule's own tail), the
identifier pattern in state 130, and `)` in states 0, 130 and 141. Its two
red raw-string specimens point at `raw_str_part`, not here. **The blind-comment
cohort's 37,575 orphan bytes should be re-derived per file before the next lane
takes scala or php on that ranking.**

### For the lane measuring wrongly-claimed bytes

This is the exhibit that lane asked for, and it is stronger than a byte count.
`/* c\n d */` is 12 bytes counted `built`, under a root, with zero mends, read as
arithmetic. Nothing in `roots`, `mends`, `covered` or `built` distinguishes it
from a correct parse — and after this change those 12 bytes are *still* `built`,
because the comment attaches as a top-level extra rather than orphaning. So the
board number does not move even in the direction I predicted: the correction is
invisible to it in both columns. The tree is the only witness.

## The specimen claim that cannot be satisfied

`embedded-quote.kt.expect` asserts `lacks simple_identifier` on
`val t = """x "q" y"""`, meaning to discriminate against a reader that closes at
byte 13 and takes `q` as an identifier. But the file's own `val t` requires one:
kotlin's `property_declaration` reaches `variable_declaration`, whose first
member is `simple_identifier`. The claim is unsatisfiable by any hand, and the
tree confirms it — the specimen's other four claims all hold, including
`spans string_literal 8 21`.

I have left the file alone rather than edit a claim to go green. `lacks
string_content`-style discrimination on that file would need a probe without a
binding, or the `spans` claim it already carries is doing the work by itself.
Handing to the lane that owns the tier.

## Files

- `src/kernel/lex/fence.zig` — `kotlin` dialect, `Span.prefix_len`,
  `Read.enters`, `openKotlin`, `readKotlin`, `sigil`; four new tests
- `src/kernel/lex/marrow.zig` — `swift_block` vein, `kotlinBlock` → `slashStar`
  with the end-of-input rule as a parameter; two new tests
- `src/kernel/lex/outside.zig` — `Troupe.sigils`/`Cast.sigils`, the `.enters`
  arm in `inside`, the kotlin fence row and the swift comment row
- `src/kernel/lex/scanner_test.zig` — two pinned seats and their key arms

Both new claims were watched failing first: reverting the greedy close to the
scanner's reading reddens the fence test (`expected 2, found 1`), and giving
swift kotlin's end-of-input rule reddens the marrow test (`expected null, found
15`).
