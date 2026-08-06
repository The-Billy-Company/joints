# Prediction 2 — the warm peel manufactures walls too, and what that costs

Written after one three-parse probe on swift and before grading the corpus. The
probe is the reason this file exists, so it is evidence for the mechanism and
**not** for any number below.

## The probe that started it

`Chunked.swift`, one grammar, three parses of one file under a pinned binary:

| body | verdict |
|---|---|
| as written | `unexpected ) at 1492 in state 141, 308 roots, mended 31` |
| `)` at 1492 blanked | `unexpected } at 1498 in state 141, 308 roots, mended 30` |
| `}` at 1498 blanked, `)` left alone | `unexpected ) at 1492 in state 141, 308 roots, mended 30` |

Row three says `}` at 1498 **is not a wall in the file as written**. Row two says
it becomes one the moment the `)` before it is blanked — in **state 141, with 308
roots and reach 28,467, all three unchanged**. The blank bought the parse
nothing. It is the same refusal, re-reported against the next token.

So the warm peel is not only mending: from a stuck state it eats the file one
token at a time. Swift's first six blanks are `)`1492, `}`1498, `}`1502, `}`1504,
`extension`1507, identifier 1508 — six rounds walking forward through a file that
has one wall in it, and 400 rounds to reach byte 2,904 of 28,467.

That matters beyond warm's own rows, because `../strand/RESULT-3-instrument.md`
and my own `RESULT-1-provenance.md` both use *warm agrees* as the clearing
evidence for a cold wall. If warm's agreement can be its own cascade, the join
clears walls it should convict.

## Predictions

**P7 — the alias cascade is most of warm's rounds, not a swift curiosity.** A
blank "bought" something if the next parse closes more roots or reaches further.
I predict that across the corpus **over half of all warm rounds bought nothing**,
and that the four grammars which burn the whole 400-round budget (haskell, sql,
swift, verilog) are over 80% barren. Falsifier: if barren rounds are under a
third corpus-wide, warm is mostly mending and the swift row is an outlier.

**P8 — grading witnesses by whether the blank bought anything will delete most of
the `witnessed` bucket.** `RESULT-1-provenance.md` put 15,527 B in `witnessed`
under the plain byte join, 13,475 B of it swift. Swift's witnesses are exactly
the cascade above, so I predict `witnessed` falls **below 3,000 B corpus-wide**
and that swift contributes **0**. I expect to be wrong in the direction of too
much surviving, because a barren round mid-run can still be followed by a real
one.

**P9 — no bucket moves into `document`.** Round 1 is the only observation of the
file as written, and nothing I am adding can promote a later round into it. So
the priced-as-damage population stays at exactly the round-1 walls, and I predict
that total is **under 4,000 B for all thirty grammars combined** — about 1.5% of
the ~270 KB the peel currently prices. If it comes out above 10,000 B I have a
counting error, not a discovery.

**P10 — `untested` beats `torn` on the four budget-bound grammars and loses
everywhere else.** Frontiers of 1,906 (haskell), 2,904 (swift), 4,390 (sql) and
12,466 (verilog) leave most of each file outside warm's view, while the twenty-one
grammars whose warm run reads whole have a frontier at end-of-file and no
`untested` at all. I predict verilog's eight `_identifier` walls — the 6,591 B the
inherited finding calls peel — split, with the ones past byte 12,466 landing in
`untested`, and that **the honest verilog statement is therefore weaker than the
one I inherited**, not stronger.

**P11 — the corpus-wide claim will not reach 96.3%.** The inherited headline was
two grammars. Widened to thirty and with `untested` carved out of it, I predict
the fraction of the priced peel that is demonstrably instrument is between **80%
and 93%**, with the remainder split between a small honest population and a
larger "nobody can tell from here" one. A number above 96.3% on thirty grammars
would mean the widening made the claim *stronger*, which is the shape of a
flattering instrument and should be disbelieved on sight.

## What I am not predicting

Whether the alias test is the last hole. It is a test over the *tree* output of
two adjacent parses, so it cannot see a blank that closes a root somewhere
irrelevant and calls that a purchase. I expect that to be the next lane's finding.
