# Result 2 — the row that does nothing has been passing a falsifier the whole time

## The claim

`vacuity/RESULT-5-pairs.md`: *"`multiline_comment/.marrow/.swift_block` moves
swift by 0 bytes alone, by 0 bytes beside `_implicit_semi`, and the pair arm
reproduces the `_implicit_semi` arm to the byte. It is a **seated row that
changes nothing in any combination available to it**."*

The brief's standing rule is that an inert implementation is deleted. **Do not
delete this one.**

## Falsifier — the specimen tier, run against the row's own isolation arm

`aud-base` is the control; `aud-r3` is today's tree with exactly this row
deleted and every line of `marrow.zig` left standing.

| specimen | `aud-base` | `aud-r3` |
|---|---|---|
| `swift/multiline-comment.swift` | **ok 4/4** | **FAIL 2/4** — `holds multiline_comment → absent` |
| `swift/nested-comment.swift` | **ok 4/4** | **FAIL 2/4** — `holds multiline_comment → absent` |

Two bound falsifiers, both green with the row in, both red with it out. The row
is alive, it is exercised, and it was exercised before this lane arrived. The
pair sweep and the specimen tier simply never met.

`nested-comment.swift` is the one that earns the seating rather than a regex:
`/* x /* y */ z */` closes at byte 21 for a non-nesting reader and at byte 27
for a hand carrying a depth counter, and only the latter is right.

## Why the board reads zero

`Chunked.swift`, swift's single corpus fixture, contains **zero** `/*` and
**zero** `*/`. It carries 237 `//` line comments, 167 of them `///`.

So the construct this row seats does not occur in the only file the board reads.
Every board arm - single, pair, and the fourteen-row union - is structurally
incapable of moving on it. The zero is a fact about `Chunked.swift`, and the
sentence *"in any combination available to it"* was scoped to the board without
saying so; the specimen tier was a combination available to it.

Answering the brief's three options directly: **not misdiagnosed, not shadowed
by another row - the target is not in the corpus.**

## Was it seated at the wrong target?

**Right construct, wrong motivating number.** Both `.expect` headers, and the
handover behind them, justify the seating with swift's *"3,997 orphan bytes."*
Split by node name off the control arm's own parse of `Chunked.swift`:

| node | orphan bytes |
|---|---:|
| `comment` (the `//` line comment) | **3,997** |
| `multiline_comment` | **0** |

All 3,997 belong to the line-comment extra. Not one belongs to the construct the
row was seated for, and none could: the file has no block comment. The previous
lane that called swift's orphan *misattributed* was right, and this is the
attribution it was pointing at.

That is a motivation defect, not a seating defect. Block comments nest in swift,
`nested-comment.swift` shows a stateless reader getting it wrong, and the row is
what makes it right. The two `.expect` prose headers are corrected; their
`roots`/`mends`/`holds`/`spans` claims are untouched.

## What swift's damage column is actually pointing at

Swift builds 23,131 of 28,468 bytes across **308 top-level roots**, of which
3,997 bytes are line comments that fell out as roots because the mend put the
stack down, and only 300 are code rubble. The real defect is whatever produced
308 roots, and the specimen tier already names a live piece of it: on the
**control** arm, `raw-string.swift` scores 1/5 and `raw-delimiter-in-body.swift`
scores 0/4, both on `holds raw_string_literal → absent`. Swift has an unseated
raw-string external. That is a finding for whoever takes swift next, not for
this lane.

## The action

1. **The row stays.** Deleting it would turn two green specimens red.
2. `vacuity/RESULT-5-pairs.md` gets a correction note: the zero is corpus
   silence, and the strong sentence is scoped to the board.
3. The two `.expect` headers lose the false 3,997-byte attribution.
4. `witnessed.py` lands so the next lane cannot make this mistake: it joins each
   seated row's board arm to the specimen tier and prints which specimens flip.
   Over all fourteen rows, **eleven are witnessed by a flipping specimen** -
   including this one, the only row on the board that reads zero.
