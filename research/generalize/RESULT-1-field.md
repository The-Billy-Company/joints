# Result 1 — Tier A, the reach sweep

`tool/field.py`. Roster pinned at
`nvim-treesitter/nvim-treesitter@3d3321b560a63ff92a8692401f303a5123336b86`,
`lua/nvim-treesitter/parsers.lua`, sha256 `4a8f2aac6a74…a92403`, **323 entries**.
Binary `.local/pin/generalize/bin/outliner`, build `f6569f034413`, tree
`299964a876ee`. Two runs: the strict one, which pins every repository to a
40-hex commit the roster itself states, and an addendum which resolves the ten
entries the roster pins by tag.

**No file was parsed and no oracle was consulted here.** Pressing is not
measuring, so Tier A costs nothing in validity and can be re-run at will.

That is now stated by the instrument rather than left to be inferred. A sibling
lane found that a grammar is not one thing on this disk — `attest.py` seats an
oracle on its sources and most grammars exist as several source trees at once —
so a sweep that names no oracle has to say it *has* none rather than leave a
missing line to be read as an omission. `field.py`'s footer says so, and
`sweep.json` carries the same sentence under `seat`.

What this sweep does depend on is pinned per row: **all 320 rows carry their
repository, revision and path in `sweep.json` under `pin`, beside each row's
`grammar.json` sha256 in `sha`.** A digest without a source is not re-fetchable
and a path is not a version; a cold run months from now needs both to prove it
read the same bytes. Nothing here reads `upstream/grammars/`.

## The headline

**320 of 320 obtainable tree-sitter grammars press. Every one.**

    outcome        n   of obtained
    clean        216         67.5%   tables built, nothing residual, nothing refusing
    refusing      39         12.2%   built, and some cell refuses a token it was handed
    residual      64         20.0%   built, with conflicts the resolver could not settle
    unlexable      1          0.3%   built, and cannot lex a byte — every terminal is external
    refused        0          0.0%   the press would not build tables
    timeout        0          0.0%   over the 120 s budget
    absent         0                 no committed grammar.json at the pinned revision

44.3 s of wall clock for the whole field: 34.8 MB of `grammar.json`, 508,087 LR
states. Median press **6.8 ms**, p95 501 ms, slowest 9.0 s (`systemtap`, 16,283
states). The largest grammar on the roster, `systemverilog` at 934 KB, presses
in 2.4 s.

The strict run is the reproducible one and reads the same: 310 pinnable
entries, 310 obtained, 310 pressed, 0 refused, 0 timeout, 0 absent.

## What could not be obtained, counted separately

**3 of 323**, and none of them is a grammar. `ecma`, `html_tags` and `jsx` are
`nvim-treesitter` aliases with no `url` field at all — rows that redirect to
another parser. There is nothing to fetch and nothing to press.

The other **10** the strict run could not pin (`c_sharp`, `desktop`,
`editorconfig`, `gnuplot`, `inko`, `jjdescription`, `python`, `robot`, `wit`,
`xresources`) name a tag rather than a commit. `field.py --tags` resolves the
tag to its commit through the GitHub API and presses them; all ten press. They
are reported as an addendum rather than folded into the strict number because
a tag is a mutable name and a sweep pinned by one is not reproducible.

**Zero grammars ship no `grammar.json`.** This is the sharpest surprise in
Tier A and it kills P1.5 outright — see below.

## The predictions

### P1.1 — ≥ 85% press, `clean` or better — **HELD, and by more than it asked for**

100.0% (320/320). The prediction allowed one in seven to fail at the front
door; none did.

### P1.2 — `refused` under 5%, `timeout` under 3% — **HELD**

0.0% and 0.0%. There is no grammar on this roster the press will not build
tables for, at any size, in any time budget worth naming.

### P1.3 — at least 25 `unlexable`, all external-only — **FALSIFIED**

**One.** `yaml`, the one the corpus already had, at 113 external terminals and
zero literals. The clause about the rule measuring what I thought it measures
did hold: the one unlexable grammar declares no literal and no regex.

I predicted the field's markup and layout-sensitive languages would push a
grammar's whole lexical structure into a C scanner. They push a great deal of
it: `rst` is 80.4% external, `vhdl` 81.9%, `djot` 56.8%, `markdown` 52.8%,
`typst` 40.2%. What none of them do is push *all* of it — every one keeps
enough literals in `grammar.json` to lex something, and only `yaml` reaches
zero.

So the prediction failed for a reason worth more than the prediction: **the
`unlexable` bucket is a bad proxy for "the scanner is where this stops."** It
is a threshold at exactly zero, and a grammar that hands 81.9% of its terminals
to a C scanner clears it. `yaml` is not the head of a distribution; it is the
one grammar that fell off the end of one. The share, not the bucket, is the
measurement — which is P1.4's business, below.

### P1.4 — external seating is where the field stops — **FALSIFIED on both clauses**

I predicted the median external share of terminals above 5%, and
external-declaring grammars outnumbering RESIDUAL-carrying ones by more than
3×.

    median external share      0.8%      (predicted > 5%)
    p75                        6.2%
    p90                       14.5%
    external-declaring          167
    RESIDUAL-carrying            64      → 2.6×  (predicted > 3×)

Both miss, and the median misses by a factor of six. **The median tree-sitter
grammar is 99.2% lexable from its own `grammar.json`.** 95 of 320 grammars
have an external share above 5%; 20 have one above 20%.

The median is doing something the prediction did not anticipate: the
distribution is bimodal. **153 of 320 grammars declare no external terminal at
all**, which drags the median to nearly zero; among the 167 that declare one,
the median share is **6.1%** and the median count is 5. So the population
splits into "no scanner" and "a scanner for five or six things", with almost
nobody in between. A single median over both is a summary of two different
populations, and my prediction quoted one.

This contradicts the brief's thesis as stated — reach across the field is not
bounded by external seating, because across the field externals are rare. What
survives, and what Tier B then confirms, is the weaker and more useful claim:
externals are rare *in count* and decisive *in effect*. 52.2% of grammars
declare at least one, and one unseated external anywhere in a file fells the
stack for the rest of it. A 0.8% share of terminals is not a 0.8% share of
outcomes.

### P1.5 — 15–40% of the roster ships no committed `grammar.json` — **FALSIFIED**

**0%.** Every one of the 320 obtainable entries has `src/grammar.json`
committed at its pinned revision. I expected a third of the ecosystem to
`.gitignore` its build artifacts and force the tree-sitter CLI into the loop.
The `nvim-treesitter` roster is the reason: it exists to be consumed by an
editor that compiles parsers from `src/`, so a repository that does not commit
`src/` cannot be on it.

That is a selection effect in the roster, and it is mine to declare rather than
the roster's to hide: **this sweep measures the field of grammars that commit
their generated tables, which is the field `nvim-treesitter` curates.** A
roster built from the tree-sitter organisation's own repository list, or from
crates.io, would carry a different denominator. What it does not change is the
answer to the question asked: of 320 grammars we could obtain, we press 320.

## Two observations the predictions did not reach for

**Refusing cells are concentrated, not spread.** 73 grammars carry at least one
refusing cell — 39 as their headline outcome, the rest also carrying RESIDUAL
and bucketed there. Of 27,595 refusing cells in the field, `systemtap` holds
**23,400**, more than the other 72 grammars put together. The next is `scala`
at 1,166, which is a corpus grammar.

**RESIDUAL is a family trait.** `arduino`, `cpp`, `cuda`, `hlsl` and `slang`
all report exactly **472** residual conflicts. They are forks of one C++
grammar, and they carry the same 472 conflicts because it is the same grammar.
Counting them as five independent data points about the press would be counting
one grammar five times — which is worth saying out loud, because a 320-row
board looks like 320 independent measurements and is not.

## Reproducing

    python3 tool/field.py run              # strict: 310 commit-pinned entries
    python3 tool/field.py run --tags       # addendum: + the 10 tag-pinned
    python3 tool/field.py report
    python3 tool/field.py verify           # 6 tripwires, including the roster pin
