# Result 2 — size, build, speed, and the keystroke

**Joints wins size and build by a wide margin, loses cold parse by 2.9x, and
loses the keystroke by 5.6x — and the keystroke loss is not a ratio, it is a
category.** On 17 of 29 grammars a keystroke costs what re-opening the file
costs. Joints is not incremental on most of the corpus, and incremental
re-parse is the reason editors adopted tree-sitter.

That is the paragraph that contradicts the brief, and it is first because it is
the largest true thing on this axis.

Measured on pin `collate` (tree `735a2c2ee2e8`, binary `a01fcb3448c4`) against
tree-sitter 0.26.11, 2026-08-05, all thirty grammars generated from the same
pinned `grammar.json`. `--fresh`, so every dylib was generated and compiled
inside the timed region.

## Prediction 2, scored

| | | |
|---|---|---|
| Q1 | folio smaller on ≥24 of 30, median ratio ≤0.40 | **held** — 28 of 28, median **0.34** |
| Q2 | at least one grammar where the folio is bigger | **FALSIFIED** — none. And Q2's *reason* was right anyway; see below |
| Q3 | mint ≥5x faster than generate+cc at the median | **held** — **19.6x**, and markdown loses at 0.7x |
| Q4 | cold parse a loss by ≥2x at the median | **held** — **2.9x** |
| Q5 | the incremental ratio is worse than the cold ratio | **held, and understated** — 5.6x against 2.9x, with a shape change underneath |
| Q6 | 0 folios need a compiler, ≥20 of 30 grammars ship a scanner | **held** — 22 of 28 ship one, 486,301 bytes of C |
| Q7 | fewer than 15 of 30 seat every declared external | **held by one** — 14 of 30 |
| Q8 | my speed instrument flatters joints on its first run | **held** — see below |

## Improvement — the artifact is a third the size, and no compiler touches it

**Consumer: anyone installing a parser. And anyone shipping one inside an app,
where a C toolchain at install time is a support burden and an attack surface.**

```
size   folio smaller on 28 of 28, median ratio 0.34
       14,285,440B of folio against 75,574,240B of dylib
C      22 of 28 grammars ship a hand-written external scanner, 486,301 bytes,
       compiled per grammar
       0 of 28 folios need a compiler at all
```

The extremes: julia 0.08, latex and ocaml 0.09, verilog **0.10** (1.9 MB against
18.3 MB). The narrowest is javascript at 0.68. sql's dylib is 11.1 MB and
verilog's is 18.3 MB; a folio is data and a dylib is machine code, and that is
the whole mechanism.

**But Q2 was right to look for a losing row, and the per-grammar ratio hides
one.** Each side has a fixed cost the ratio omits: joints's 1,764,104-byte
binary against libtree-sitter. At one language tree-sitter is smaller; the
crossover is two.

```
1 language  (median)   joints 2.07 MB   tree-sitter ~1.6 MB    tree-sitter
2 languages            joints 2.38 MB   tree-sitter ~2.8 MB    joints
all thirty             joints 16.0 MB   tree-sitter  76.0 MB   joints
```

(libtree-sitter is not measured here — only the 20 MB CLI is on this machine,
which is the generator and not the runtime. The crossover is two languages for
any libtree-sitter between 300 KB and 600 KB, so the conclusion does not depend
on the estimate.) **Labelled: improvement from two languages up, gap at one.**

## Improvement — grammar to usable artifact, 19.6x faster and one process

**Consumer: anyone iterating on a grammar, and any build that has to produce
parsers for N languages.**

```
build  median 19.6x faster to mint
       the whole slate 8.6s against 212.1s
```

`joints mint` is one in-process press over `grammar.json`. Tree-sitter is
`tree-sitter generate` writing a `parser.c` and then a C compiler. sql is 916 ms
against 61.7 s (67x), julia 115 ms against 16.8 s (146x), ocaml 92x, kotlin 83x.

The losing row exists: **markdown, 1,146 ms to mint against 799 ms to generate
and compile, 0.7x.** Also bash at 2.0x and scala at 5.7x, both below the median
by a lot. Those three are the handover: whatever makes markdown's press slow is
a press question, not a grammar question, since its dylib is small.

## Gap — cold parse, 2.9x

**Consumer: a one-shot indexer, a batch linter, anything parsing a tree from
cold.**

```
parse  median 2.9x tree-sitter's time per byte
       faster on 1 of 27 resolvable rows; worst latex at 31.7x
```

Both sides on comparable clocks: joints from the **slope** of parsing the same
file K times in one process (which charges it the file open, the read, the tree
build and the free), tree-sitter from its own `--stat` bytes/ms (which charges
it only `ts_parser_parse`). The asymmetry runs against us on purpose.

The worst rows are the handover, and they cluster: **latex 31.7x, swift 14.3x,
zig 12.8x, kotlin 12.4x, ocaml 12.4x, julia 9.8x, elixir 6.5x.** Everything else
is between 1.0x and 4x. The single row joints wins is **html at 0.96x**, a
dead heat on a 72 KB file — call it a tie rather than a win.

json is printed as `noise` and excluded: 774 bytes came back at 254,965 B/ms,
which is three microseconds of parse read off a one-millisecond ruler. The
resolution guard is structural (`Cost.resolved`) and `collate.py prove` requires
it to fire.

## Gap — the keystroke, and it is a category not a ratio

**Consumer: an editor. This is the axis tree-sitter exists for.**

```
ours   median   661 us per keystroke,  1x cheaper than re-opening the file
theirs median    98 us per keystroke,  8x cheaper than re-opening
       median 5.6x tree-sitter's time; faster on 1 of 29
```

The ratio is the smaller half of the story. **The `gain` column is the story:**
joints's median gain from having an existing tree is **1x**. On 17 of 29
grammars, typing one character costs the same as opening the file.

```
swift    28,468B    30,740 us/key   gain 1x   theirs 73 us    →  422x
latex     5,246B    11,527 us/key   gain 1x   theirs 34 us    →  342x
ocaml    16,878B    24,792 us/key   gain 1x   theirs 218 us   →  114x
zig      16,125B    11,134 us/key   gain 1x   theirs 98 us    →  114x
html     72,288B     2,686 us/key   gain 2x   theirs 30 us    →   88x
scala    20,107B     4,083 us/key   gain 1x   theirs 70 us    →   58x
kotlin   35,815B    26,978 us/key   gain 1x   theirs 634 us   →   43x
verilog  94,657B    57,555 us/key   gain 1x   theirs 11,997 us→    5x
```

30 ms per keystroke on a 28 KB Swift file is a dropped frame on every character.
Tree-sitter answers the same edit in 73 microseconds.

Both numbers are each side's **own inner clock** — `joints amend` prints
microseconds per edit, `tree-sitter parse -t` prints one `Edit:` total — because
`tree-sitter parse` spends ~295 ms per path resolving the language, which would
drown a 10-microsecond re-parse three hundred times over. Twenty-four edits per
file, one character each, inserted into identifier interiors so the edit grows a
real token and keeps both files valid.

**Handover:** the mechanism is visible in `amend`'s own report. Where joints is
incremental it says `2/307 leaves reminted`; where it is not, it reminted
everything. The owning layer is whatever decides the re-mint window — `amend`
already takes `--policy=prove|snap|whole`, so the knob exists and this
measurement is a benchmark for it.

## ~~Improvement — php's keystroke, 2x faster than tree-sitter~~ — WITHDRAWN

**Withdrawn 2026-08-06 by the keystroke lane, which was sent to generalize it.
See [`research/keystroke/RESULT-1-mechanism.md`](../keystroke/RESULT-1-mechanism.md).
This section is kept rather than deleted because the claim was cited.**

```
php   67,845B   138 us/key   gain 65x   theirs 300 us   →  0.5x
```

The number is real and it measures a destroyed file. **php's first keystroke
lands at byte 3, and byte 3 of the php source is inside `<?php`.** The edit makes
it `<?pxhp`, the opening tag stops being a tag, and the remaining 23 keystrokes
are timed against a file that reads as **73 tokens instead of 2,744**, returning
a tree that begins `(_php_tag)` and stops. Drop that one edit and keep the other
23 and php is **1.8x**, which is what every other mended grammar gets:

| php, 24 keystrokes | open | median edit | gain |
|---|---|---|---|
| these 24 offsets | 9,108 µs / 2,744 tok | 143 µs / 73 tok | **63.7x** |
| the same minus the first | 9,296 µs / 2,744 tok | 5,247 µs / 1,135 tok | **1.8x** |

`keystrokes()` is not wrong about anything it claims - `p` inside `php` is an
identifier interior by every test it applies, and nothing tells it that one
language spells its file-scope opener as a word. But the sentence built on top of
it - *"it proves the machinery works and the other 28 rows are a policy problem
rather than an absence"* - was the premise of a whole work order, and the
machinery does not work anywhere on the mended set. Both halves of reuse are off
there for two unrelated reasons, neither of them a re-mint policy.

The row above it stands and gets worse, not better: **gain 1x on 17 of 29 is 18
of 29.**

It remains true that php is also the grammar whose *tree* is worst (Result 1:
25,338 misread bytes), and the two facts are now the same fact.

## Improvement — externals seat from declared structure, no C

**Consumer: whoever would otherwise write and maintain the scanner.**

```
declared 461   seated 263 (57% of declared)
22 of 28 grammars ship a hand-written external scanner: 486,301 bytes of C
 0 of 28 folios need a compiler
```

The README's headline is 252 of 461; it is now **263 of 461**. Measured with
`tool/specimen.py coverage`, which is the authority here — **`joints grammar`
is not.** Its `note: external scanner tokens cannot be lexed here` lists all 33
of swift's externals, while 22 of them are in fact seated; that note is about
the ordinary lexer, not about troupe seating, and reading it as a seating census
would have reported 0 seated everywhere. That is a third instrument that would
have lied, caught before it printed a number.

**Q7 holds, and the token-weighted headline does not survive being asked per
grammar.** 57% of *tokens* are seated; **14 of 30 grammars** have every declared
external accounted for, and that count only reaches 14 by including the 7 that
declare none. Of the 23 that declare externals, **7 seat all of theirs** —
yaml (113/113), julia, html, python, lua, toml, cpp. Four seat **none**:
markdown (0/47), latex (0/12), php (0/12), sql (0/3).

A user has one language, not 461 tokens. Both numbers belong in the claim.

The C figure is the sharpest thing on this page and it needed the walk to be
right: php's `scanner.c` is 595 bytes and does nothing but include
`../../common/scanner.h`, which is 18,018. Counting only the `.c` would have
priced php's external lexer at 3% of itself.

## Gap — one grammar tree-sitter cannot install here at all

yaml. `tree-sitter generate` succeeds; the compile does not, because
`scanner.c` does `#include _file(YAML_SCHEMA)` and no fetcher can see a
macro-constructed include. `fatal error: 'schema.core.c' file not found`.

This is labelled a **gap on our side too**, because joints's yaml row is
0 built of 18,935 bytes — it seats all 113 externals and still builds nothing.
Neither system parses yaml on this machine. Tree-sitter's failure is at install
time and loud; ours is at parse time and reported as 100% damage, which is at
least honest.

## Q8 — the instrument, caught

The first cost instrument timed one process over the real file against one over
an empty file and subtracted. Its first numeric run:

```
go   ours 0.1 ms   theirs 46.6 ms   →  400x faster
```

400x, on a 1,189-byte file, on a machine where tree-sitter's own clock says it
parses at 4 MB/s. Both terms were process-start jitter with a parse somewhere
inside them, and the sign of the noise picked the winner. It picked us.

The replacement measures a slope on our side and reads their own clock on
theirs, for the reason in `theirs_speed`'s docstring: the same slope over
tree-sitter's CLI reads **219 ms** for that go file, because it re-resolves the
language per path. That number would have been a 600x win and a measurement of
their argument loop.

Q8 predicted this would happen and it took one run. It is the same failure P7
predicted on the correctness lane, which also fired.

## Reproducing

```bash
export JOINTS_BIN=.local/pin/collate/bin/joints
python3 tool/collate.py cost --fresh --runs=3     # size, build, cold parse   (~12 min)
python3 tool/collate.py keystroke --runs=3        # incremental               (~2 min)
python3 tool/specimen.py coverage                 # declared / seated / exercised
python3 tool/collate.py prove                     # every guard, asked to say no
```

`--fresh` deletes each `parser.c` and dylib so the compile is inside the timed
region; without it the build column measures a cache.

## Limits

- **One machine, one run of three.** Minimum-of-three, because the minimum is
  the run least interrupted by the other nine agents on this tree. Nothing here
  has been reproduced on the Anvil box.
- **The two parse clocks are not identical.** Ours carries the file open, read
  and tree build; theirs carries only the parse. The asymmetry costs us and is
  left in rather than corrected, because correcting it means choosing how much
  to subtract.
- **embedded-template and yaml have no cost row** — tree-sitter cannot compile
  them here, so 28 grammars, not 30.
- **Memory is not measured.** It is on the brief and it is not in this result.
