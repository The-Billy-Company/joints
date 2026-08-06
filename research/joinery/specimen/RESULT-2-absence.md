# Result 2 — what the corpus does not contain

Scored against `PREDICTION-2-absence.md`, written before `tool/absent.py`
existed. Five of seven held. Both failures are in the paragraph below.

All numbers from pin `spec2` (tree `fa7fcaee5`, commit `f7ba40004+105`). The
tree moved ~100 commits under me while I worked - ten agents share it - so
every report here carries its stamp and the DRIFT line is real, not ignored.

## The answer

**The thirty corpus files present 2,050 of 5,198 judgeable spellings - 39.4%.
3,148 spellings the grammars write down never occur in the file that grades
them.** That is the defensible answer to the question that made this lane
necessary, and it is a floor rather than an estimate: `absent.py` counts a
spelling PRESENT if its bytes occur anywhere, including inside a comment or a
string, so it can miss an absence but cannot invent one. 54 patterns it cannot
compile and 32 that match the empty string are also counted present for the
same reason.

There is a second half it cannot read at all. **456 of the 461 declared
externals have no body in `grammar.json`** - their spelling lives in a C
scanner. That population belongs to `specimen.py coverage`, which witnesses 36
of the 461. Neither instrument covers the other's half, and both say so on
every run rather than reporting a ratio over the part they can see.

## Scores

**P1 - the corpus presents fewer than half of what the grammars spell. HELD.**
39.4%, against a predicted "something near 35%". The prediction was slightly
pessimistic and the direction was right.

**P2 - Swift's corpus file contains no match for `[\/]+[*]+`. HELD**, and this
is the calibration rather than the finding. `Chunked.swift` contains no `/*` at
all. The one absence in this tree whose consequence was already known is
reproduced by the instrument's first assertion, which is the only reason to
read the other numbers.

**P3 - a `whole` grammar sits below the corpus median for literal presence.
HELD, four times.** Median presence across 29 judgeable grammars is 51.1%.
Below it, all reading 100.0% standing and zero damage on the board:

| grammar | presents | |
|---|---|---|
| latex | 9.1% | |
| c | 30.3% | |
| python | 45.3% | already known wrong (`print(x)`) |
| javascript | 49.3% | |

latex reads 100.0% standing off a file that presents **9.1%** of what latex
spells. That row is not evidence of correctness in any direction; it is a
statement about `ledger.tex`. The board cannot distinguish the two and does not
claim to - this is the number that says by how much.

Worth stating the other end too: **html presents 93.8%**, the best-sampled of
the twelve, and a specimen still found a defect in it. Sampling more of a
vocabulary narrows this gap; it does not close it.

**P4 - three or more of the fifteen unexercised externals resist an authored
input. FAILED.** One did. Thirteen of the fifteen lit up on first authorship,
two were the P5 category, and the single holdout is yaml's, which resists for a
reason no specimen can fix: `outliner parse upstream/grammars/yaml.json` exits
2 with `yaml has no lexable terminal at all`. yaml is 113 externals and zero
literals; there is nothing for a lexer to be built out of.

The finding this failure carries is the one I would not have written down: **the
gap was corpus silence and a gate overcount, not defect.** I predicted the
specimen tier would separate "we cannot do this" from "nobody asked", and
expected a meaningful pile in the first bin. The first bin has one thing in it.

It does *not* follow that exercising an external means the construct is right.
html's specimen exercises `erroneous_end_tag_name` correctly - the claim holds -
and fails anyway, on the parent above it. A coverage gate at 100% would have
called that row done.

**P5 - two or more of the fifteen cannot be witnessed even when correct. HELD,
and the brief's number was wrong.** rust's `string_close` and
`raw_string_literal_content` are aliased at **every** use site - to `"` and to
`string_content` - so no parse of any input can name them however correctly it
reads. tree-sitter itself builds `fn m() { let s = "x"; }` perfectly and never
says `string_close`. "Exercised" was never a reachable state for those two rows
and the gate was scoring against an unreachable denominator.

The gate now excludes them and prints what they wear instead. The denominator
moved **38 → 36** and the ratio **23/38 → 22/36**.

The first version of that fix was too strong and the tier caught it: an alias at
*one* use site is not an alias at all of them, and treating it as one made bash
report `exercised 5 of 4 visible`. A ratio above one is what an over-tight rule
looks like when nothing checks it. The rule is now "aliased at every reference
and referenced plainly nowhere", and the walk stops descending into an ALIAS so
the inner symbol is not counted as its own plain reference.

**P6 - a specimen finds a real defect in a grammar the board calls whole.
HELD.** html. Full derivation in `RESULT-3-html.md`; it is the proof this lane
was asked for.

**P7 - innocent controls will outnumber guilty ones. HELD, by more than I
predicted.** Of fifteen new specimens, thirteen hold every claim, one fails and
one is refused - **13% guilty against a predicted ~33%.** The thirteen are what
make the two credible, and I would rather report a tier that is mostly green
than one selected to be red.

## What I got wrong about my own instrument

`specimen.py`'s `stop()` read roots and mends off the binary's stop line and
**defaulted a missing line to one root and no mends** - which is the exact shape
of a perfect parse. So a grammar the binary refuses to lex scored `roots 1` and
`mends 0` as claims HELD. yaml/comment.yml reported **2 of 4 against a binary
that had not read a byte of it**, and the two were the structural claims, the
ones an author is least likely to re-derive by hand.

That makes thirty. It was in my own tier, in the fifteen minutes after I added
the specimen that triggered it, and it was flattering in the direction that
would have let me report a higher number.

A refusal is now its own outcome: every claim fails, named with the refusal, and
`run` prints `REFUSED` rather than `FAIL` so it cannot be read as a wrong
answer. `specimen.py verify` gained a sixth assertion that performs it - it
finds a grammar the binary refuses, asserts `roots 1` and `mends 0` against it
because those are precisely the two a defaulted read makes true for free, and
requires zero held. If no grammar refuses, it reports that it proved nothing
rather than passing.

The overcorrection is worth recording too, because it was live for one run: I
first treated any nonzero exit as a refusal, which swept up seven honest
mended, truncated and many-rooted parses. A parse that mends is a parse. The
condition is now "the binary named no root count at all".

## What I trust least, demonstrated

`absent.py`'s **present** side. ABSENT is a floor and I believe that half: a
substring or regex search cannot invent an absence. PRESENT is the weak half,
because a spelling counts present if its bytes occur *anywhere* - including
inside a comment or a string, where they are not the construct at all. I said
so on every run. Saying so is a hedge, so here is the size of it.

For twelve grammars, take every multi-byte `STRING` spelling `absent.py` calls
present, find all its occurrences, and ask the oracle whether **every one** of
them sits strictly inside a `comment`, `string` or `text` node:

**34 of 211 - 16.1% - never occur outside one.**

| grammar | false present | of | |
|---|---|---|---|
| css | 5 | 11 | 45.5% |
| latex | 4 | 10 | 40.0% |
| scala | 13 | 41 | 31.7% |
| lua | 2 | 16 | 12.5% |
| javascript | 3 | 30 | 10.0% |
| ocaml | 3 | 33 | 9.1% |
| go | 2 | 22 | 9.1% |
| c | 1 | 19 | 5.3% |
| python | 1 | 21 | 4.8% |

The individual rows are worse than the ratio. `ledger.scala` contains `true` 17
times and `false` 16 times and **not one of them is a `boolean_literal`** -
every occurrence is inside a comment or a string. Same for `return` at 33 and
`match` at 27. `absent.py` reports scala's `boolean_literal` spellings present;
the file never uses one.

So the 39.4% is an overcount and true presence is lower, which means **the real
absence is larger than 3,148 spellings, not smaller.** The error runs in the
declared direction, which is the only reason the number is usable at all, but
"floor" was doing more work in that sentence than it had earned.

The confound in the demonstration is worth recording because it nearly became
the finding. The first pass reported 16 hits including lua `--` at 44
occurrences and css `/*` at 71 - and those are the comment *openers*, which of
course sit inside the comment node they open. That was a defect in my detector,
not in `absent.py`. Requiring the hit to start strictly after the hiding node's
start removed every one of them and left the 34 above. A demonstration that
does not get audited as hard as the thing it demonstrates is just a louder
hedge.

I have not "fixed" this by intersecting with the oracle. That would make the
lexical reading depend on tree-sitter, and its entire reason to exist is being
the only reading available on the 34,687 bytes where tree-sitter ERRORs. The
right shape is to report both and let the gap be visible, which is what this
section is.

## What this does not answer

`absent.py`'s structural half - "which named rules does the oracle's own parse
never yield" - is built and passes its calibration, but it needs the oracle and
is therefore missing on exactly the **34,687 bytes where tree-sitter itself
ERRORs**. The lexical half is the only reading available there, and it is the
weaker of the two. Where both are silent, a specimen's claim is the only ground
truth in this tree, which is the argument for this tier stated as a measurement
rather than as a sentence.
