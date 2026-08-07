# Prediction 1 — how much of `built` is built wrong

Written **before** the instrument existed, against the board as it read at
2026-08-05T22:14Z on pin `plumb` (tree `bd7b3e939`). Each prediction names the
measurement that falsifies it.

## What I knew when I wrote this

- The board: `built 363,987 + orphan 56,343 + rubble 24,167 + spoil 82,301 =
  526,798`, **69.09% standing**. (The brief quotes 354,893 and 67.37%; somebody
  landed a fix between the brief and this pin. The corpus size is unchanged, so
  the buckets moved and the denominator did not.)
- Twelve of thirty grammars read **100.0% standing** — go, java, javascript,
  typescript, python, rust, json, css, embedded-template, html, lua, toml —
  worth **100,399 bytes**, 27.6% of all `built`. Every board instrument calls
  these perfect. html alone is 72,288 of them.
- `research/joinery/specimen/RESULT-1-coverage.md`: swift seats 21 of 33
  externals, `multiline_comment` blind; kotlin seats 2 of 10; markdown seats 0
  of 47; latex 0/12, php 0/12, sql 0/3; yaml seats all 113.
- `tool/differential.py` exists, its tree-sitter oracle is installed
  (0.26.11), and 27 languages are already generated under `.local/differential/
  lang/`. I had **not** run it when these predictions were written.
- The Swift observation: `/* c\n   d */` parses as `prefix_expression` over
  `multiplicative_expression`, one root, zero mends, and those bytes are
  counted `built`.

## The measure I am about to build

For each byte of the corpus, the **deepest node covering it** in joints's
forest and in tree-sitter's tree. Same byte, two names. A byte whose two names
differ is **askew**; a byte whose names agree is **plumb**; a byte the oracle
cannot adjudicate is **unjudged**. Restricted to the `built` population, so
`built = plumb + askew + unjudged` and no other bucket moves.

Byte-indexed rather than tree-aligned on purpose: joints hands back a forest
on 18 of 30 grammars, and an alignment over 3,544 roots is a guess. Two
functions from offset to name need no alignment at all.

| | prediction | falsified by |
|---|---|---|
| P1 | `askew` is **at least 2%** of `built` corpus-wide — this is not one Swift comment | `askew / built < 0.02` |
| P2 | Swift is **not** the largest single contributor of askew bytes | swift tops the askew ranking |
| P3 | At least one of the twelve **100.0%-standing** grammars carries nonzero askew | all twelve read exactly 0 |
| P4 | The askew order and the `damage` order **disagree**: their top three share at most one grammar | the two top-threes share two or three |
| P5 | The oracle cannot reach **at least five** of the thirty grammars (scanner absent, generate fails, or its two printers refuse to agree) | fewer than five skip |
| P6 | **My own instrument lies first, in the flattering-to-me direction**: the first run that produces numbers reports nonzero askew on javascript, which `differential.py` records as byte-exact and which is therefore my green control | javascript reads exactly 0 askew on the first numeric run |
| P7 | `unjudged` is **larger** than `askew` — more of `built` is beyond the oracle's reach than is provably wrong under it | `askew > unjudged` |
| P8 | html — 72,288 bytes, 19.9% of all `built`, and the single largest row on the board — contributes **more** askew bytes than the four mending corpus files (c, ruby, bash, cpp) put together | html's askew ≤ the sum of those four |

## Why each

**P1.** Four grammars seat zero externals and still report 62–87% standing
(php 87.2, sql 62.1, latex 77.4). An external a grammar declares is a token
the ordinary lexer cannot spell; a grammar that declares twelve, seats none,
and still claims 87% of its bytes is either not using them or reading them as
something else. php is 59,146 built bytes with zero seated externals. 2% of
`built` is 7,280 bytes and php alone could carry that.

**P2.** Swift's blind `multiline_comment` costs the bytes of Swift's comments,
and `Chunked.swift` is 28,468 bytes total with 23,131 built. php's whole
external set is blind over 59,146 built bytes, which is 2.5× swift's entire
file.

**P3.** A grammar reaches 100% standing by handing back one root with a child.
That is a statement about *placement* and says nothing about the token stream
underneath. The Swift specimen is the existence proof at the file scale: one
root, zero mends, arithmetic where a comment should be.

**P4.** `damage` is `size − built`; askew is a partition *of* `built`. They are
measured over disjoint byte sets by construction. A grammar with high damage
has little `built` left to be wrong in — kotlin's entire `built` is 14,841
bytes, so it cannot out-askew a grammar with 59,146.

**P5.** `differential.py`'s own docstring says seven of eleven pins need a
hand-written C scanner fetched from the same commit, that a monorepo grammar
needs its repository depth reproduced, and that a CST/XML disagreement is a
refusal. Thirty grammars through that gauntlet will not all arrive.

**P6.** The specimen lane predicted this about its coverage count and was
right; the board lane predicted it about its guard and was right. My
normalisation has to reconcile named/anonymous spelling, aliases, fields,
supertypes, hidden rules and invented nodes across two printers, and the
failure mode of getting one wrong is a wall of differences that reads exactly
like a finding.

**P7.** Five grammars are already known to have no oracle path, and any
grammar whose tree-sitter parse contains an `ERROR` is an oracle that cannot
adjudicate the bytes under it. Both count as `unjudged`, and both are large
categories.

**P8.** html is 24 hundredths of the corpus and every instrument here calls it
perfect. Either it is perfect — in which case P8 fails and that is worth
knowing about the single biggest row — or nothing in this repository has ever
looked at it.

## What I am deliberately not predicting

**Whether the board should change.** That depends on the magnitude, and
predicting it would make the measurement's job to agree with me. The
constraint is fixed in advance instead: any column I add must leave `built`,
`orphan`, `rubble`, `spoil`, their sum, and `standing` reading exactly what
they read on this pin. If I cannot add a column under that constraint, I add
no column.

## The tripwire

Two-sided, and both sides are cases whose answer I know independently of the
instrument:

- **must be red** — `research/joinery/specimen/swift/multiline-comment.swift`,
  whose tree is written out by hand in `specimen/RESULT-1-coverage.md`:
  `custom_operator` and `"*"`/`"/"` where a comment belongs. If plumb reports
  those bytes as agreeing, plumb is broken.
- **must be green** — javascript, which `differential.py` calls byte-exact and
  uses as the substrate for its own span fixtures precisely because "a
  difference here is the reader and never the parser". If plumb reports
  javascript askew, plumb is broken.

A run where either side moves is not reportable.
