# The board's terminal names were wrong for a majority of its walls

Handoff to the bench lane, which owns the board and `FAMILY`. **Nothing here
edits the board.** Two surveys are checked in beside this file, taken over the
same corpus at the same depth, minutes apart, differing only in the commit
below:

```bash
python3 tool/walls.py board --from-json research/joinery/walls/survey-before-spot.json
python3 tool/walls.py board --from-json research/joinery/walls/survey-after-spot.json
```

The classifier did not move. Its input did.

## What was wrong

`Gather.blame` is the diagnostic re-lex: when the narrowed slate finds nothing,
it re-asks with the narrowing stood down so a person is told 535 held a `{`
rather than that byte 535 is strange. It asked with **every terminal the grammar
has**, and it asked `next`, which is maximal munch.

Maximal munch is the right answer to "given that all of these were asked for,
which owns this byte". It is the wrong answer to "what is here". Every grammar
in the corpus holds a run-of-anything-but-a-delimiter, and that member reaches
further than every real token at every offset, so the answer came back as a fact
about the grammar's widest regex rather than about the byte. Measured over the
corpus: **540 of 822 peeled walls were named by that tier, at a median blamed
length of 1,777 bytes, against 1 byte on the state-derived tier.**

Two consequences, and the second is worse than the naming:

1. The wall is filed under the wide pattern's family instead of its own.
2. The token does not stop at the message. It goes on through
   `sprout`/`lift`/`absorb` like any other, so `mend` deleted the whole span.
   A misnamed wall also swallowed a kilobyte of source nothing had read.

Fixed in `fix: name a stuck byte by the shortest reading, not the widest one` -
`Scanner.spot`, shortest match over a flat slate with precedence dropped, and
`choose` settling the tie as usual.

## How much of the board moves

**315 distinct walls -> 343.** Up, not down, which is the part worth reading
twice: a wide blamed token used to consume the bytes that held the *next* few
walls, so the old naming was undercounting variety as well as misfiling it.

| family | lane | before | after | shapes | grammars |
|---|---|---:|---:|---|---|
| permissive body pattern | **scanner** | 105 | **40** | 22 -> 12 | 16 -> 9 |
| separator refused | **press** | 56 | **106** | 12 -> 17 | 12 -> 17 |
| bracket refused | **weave** | 63 | **88** | 8 -> 7 | 14 -> 16 |
| named terminal | unassigned | 55 | 54 | 44 -> 37 | 10 -> 12 |
| unrunnable external | **scanner** | 33 | 41 | 33 -> 36 | 5 -> 6 |
| string delimiter | **scanner** | 3 | 9 | 1 -> 2 | 2 -> 4 |

The scanner family that looked largest was mostly a reflection of the
instrument. `xml_text` goes **28 -> 1** in scala; swift's `(?:[^\\"]+)`
goes **14 -> 0**. What is left in that family is real: kotlin and swift share 20
walls on `(?:[^\r\n]*)`, which is a line-comment body genuinely being refused.

Almost all of it lands in **separator** and **bracket**, and both grew in
*grammars* as well as walls - separator picks up c, cpp, latex, php, swift, zig;
bracket picks up c, cpp, swift. So this is not scala's problem redistributed, it
is sixteen grammars that were filed wrong.

### 92 walls renamed at the same state

Full list is derivable from the two JSONs. A sample of the shape:

| grammar | state | was | is |
|---|---|---|---|
| scala | 1076 | `xml_text` | `:` |
| scala | 1504 | `xml_text` | `]` |
| scala | 4 | `xml_text` | `_interpolation_identifier` |
| c | 1146 | `(?:[^\\"\n]+)` | `,` |
| go | 485 | `(?:[^`]*)` | `)` |
| kotlin | 51 | `(?:[^\r\n]*)` | `:` |
| ocaml | 220 | `(?:[^\\"%@]+\|%\|@)` | `-` |
| php | 149 | `(?:[^\s<][^<]*)` | `/` |
| python | 1 | `(?:[^{}\n]+)` | `)` |
| swift | 38 | `(?:[^\\"]+)` | `.` |

## What did not move

`rust`, `java` and `json` produce **byte-identical** survey rows before and
after, so those three are untouched by this. No grammar's verdict (`kind`,
`why`, `closed`) changed anywhere in the corpus.

## One regression, and it is a budget unit rather than a name

Each mend now deletes about a byte where it used to delete about a kilobyte, so
the number of mends rises steeply for the same repair work:

| grammar | mends | reach | covered |
|---|---|---|---|
| haskell | 4,940 -> **16,384** | 34,239 -> 32,014 / 34,240 | 100.0% -> 93.5% |
| swift | 29 -> 9,538 | 28,468 -> 28,467 | unchanged |
| scala | 190 -> 549 | unchanged | unchanged |
| verilog | 1,711 -> 2,234 | unchanged | unchanged |
| go | 3 -> 8 | 1,189 -> 1,188 | 100.0% -> 99.9% |

Only haskell loses reach, and it loses it by hitting the **16,384 mend cap** -
the budget is denominated in mends, not in bytes deleted, so a correct 1-byte
repair costs the same budget as a 1,777-byte one that was mostly lying. Swift is
the control: 9,538 mends, same reach, same coverage.

Worth saying plainly that haskell's old 100% was partly manufactured. A blamed
token that is absorbed puts a node over its whole span, so the widest possible
misreading earns the most coverage. The number to trust after this is `reach`.

## Read the count as a floor, still

Unchanged from the board's own caveat: the cold peel resumes from a clean start,
so a wall reachable only after four thousand lines of context is invisible to
it. 343 is a floor on variety in the same way 315 was.

## The instrument, three times in one evening

This is the third instrument bias found tonight, and the worst of the three:

1. The peel stepped past `reach` - where the parse got to - rather than past
   `at`, the byte the verdict names. Changed a count.
2. 58 walls were state-0 restarts, an artifact of resuming rather than a
   difficulty in the text. Changed a count.
3. This one. Changed what each wall **is**.

None of the three announced itself. Each was found by asking whether the
instrument or the thing was at fault, and each read as a finding right up until
it was checked. The board is the most-trusted artifact in this project and it
has now been wrong three times in one evening. That is an argument for the board
carrying its own adverse tests, not an argument against the board.
