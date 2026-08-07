# Prediction 1 — the bytes tree-sitter refuses

Written **before** the instrument existed, at 2026-08-05T23:14Z, on pin
`collate` (tree `735a2c2ee2e8`, binary `a01fcb3448c4`, commit `f7ba40004+98`).
Each row names the measurement that falsifies it.

This is the half of the scoreboard the brief said to start with: the 34,687
built bytes `plumb` could not judge because tree-sitter's own tree is in
recovery there. The brief calls them a candidate win. The amendment sharpens
that to: **a candidate win is a gap until the structure we put there is
adjudicated**, because an honest ERROR beats a confident wrong tree, and this
repository has a proof of that in `specimen/swift/multiline-comment.swift`.

## What I knew when I wrote this

Read, not measured by me:

- The board: `built 363,987 + orphan 56,343 + rubble 24,167 + spoil 82,301 =
  526,798`, **69.09% standing**, thirty grammars.
- `plumb`'s five buckets over `built`: 222,024 plumb, 33,634 regrouped, 794
  relabelled, 1,268 renamed, 71,580 interstice, **34,687 unjudged**.
- `RESULT-1-askew.md` limit 1: the unjudged bytes are **verilog 30,720 and sql
  3,967** — those two sum to 34,687 exactly, so on the pin `plumb` measured,
  no third grammar contributed an ERROR byte inside the `built` scope.
- For `picorv32.v`, tree-sitter's `ERROR` is the **root**, spanning the file.
- verilog is the corpus's #1 damage row: 94,657 bytes, 32.5% standing, 3,544
  roots, and `--mend=keep` versus `fell` moves damage 63,937 → 38,480 while
  `describes` falls 22,222 → 12,672 nodes.
- All thirty grammars have a generated oracle on this machine
  (`plumb.py list`: `gen yes` on every row), so a missing oracle is not why
  anything goes unjudged.
- tree-sitter 0.26.11, generated from the same pinned `grammar.json` the press
  reads.

I had **not** run any oracle myself when this was written.

## The measures I am about to build

1. **Refusal census.** For every one of the thirty corpus files, tree-sitter's
   whole tree, and the union of bytes under an `ERROR` or `MISSING` node —
   over the *whole file*, not clipped to joints's `built`. Symmetrically,
   joints's own damage (`orphan + rubble + spoil`) and its mend count.
2. **What survives inside a refusal.** For the ERROR regions, the named
   descendants tree-sitter still hands back inside them, and the bytes they
   cover. A root-level ERROR is not the same claim as an empty tree.
3. **Hand adjudication.** A sample of joints's constructs inside the ERROR
   region of `picorv32.v`, read against the Verilog grammar itself, each
   scored right / wrong / neutral by hand and written out so a reader can
   disagree with me case by case.

| | prediction | falsified by |
|---|---|---|
| P1 | tree-sitter produces an `ERROR` or `MISSING` node on **at least 5** of the thirty corpus files, more than the two `plumb` sees, because `plumb` only looks inside joints's `built` and a file joints barely builds hides the oracle's own damage | fewer than five files carry one |
| P2 | **tree-sitter's root ERROR on `picorv32.v` is not empty**: named descendants under it cover **≥ 50%** of the file. "Tree-sitter produces nothing usable for that file" is the brief's framing and I expect it to be wrong — the honest reading is that tree-sitter hands over structure *and says it is untrustworthy* | named descendants under ERROR cover < 50% of the file |
| P3 | Of a hand-adjudicated sample of joints constructs inside that region, **fewer than half are right**. The candidate win is mostly a gap in improvement's clothing | ≥ 50% of the sample adjudicates right |
| P4 | Joints's **self-report recall over its own misreadings is 0.00 by construction** on every grammar: `plumb`'s misread bytes are a subset of `built`, and `built` is disjoint from `damage`, so no misread byte can ever be a flagged byte. This is a structural property, not a measurement, and I expect to prove it as an identity rather than a statistic | any grammar reports a misread byte that also lies in `orphan + rubble + spoil` |
| P5 | On **php** — the exhibit against us — tree-sitter flags **0 bytes** of `Str.php` as ERROR while joints misreads 32,615 and reports 87.2% standing. So the honesty axis on php is a **gap**, and not a close one | tree-sitter's tree over `Str.php` contains an ERROR or MISSING node |
| P6 | There is **at least one** file where the comparison runs the other way: tree-sitter ERRORs over bytes joints both builds *and* builds right (`plumb`-clean under adjudication). If P6 fails, the entire candidate win is empty and the honest scoreboard says so | no file has a single adjudicated-right joints construct inside an oracle ERROR |
| P7 | **My own instrument lies first, in the direction that makes this lane look necessary.** Concretely: the first numeric run of the refusal census reports at least one file as oracle-ERROR that is really my own harness failing — a build, a printer disagreement, or a timeout — read as a refusal | the first numeric run's ERROR set contains no harness artefact |
| P8 | Counting bytes under ERROR is itself a flattering metric for us, because an ERROR *root* charges the whole file. So the ERROR-byte total across the thirty will be **dominated by ≤ 2 files at ≥ 80%** of it, and any headline built on the raw total is one file wearing a corpus number — the same shape `plumb` found in php | the top two files are less than 80% of the ERROR byte total |

## Why each

**P1.** `plumb` clips to `built`. verilog and sql are the two grammars where
joints builds enough *and* tree-sitter fails; a file where joints builds
almost nothing (haskell at 23.8% covered, yaml at zero) could have an oracle
ERROR that `plumb` never sees, because there is no built byte underneath it to
report. The census is over whole files, so it can only go up.

**P2.** Tree-sitter's recovery keeps reducing. An ERROR node adopts the
subtrees it already built; that is the entire point of its `error_cost`
heuristic. A root-level ERROR means "I could not close the file", not "I read
nothing". If P2 holds, the brief's strongest sentence about this lane is
wrong, and saying so is worth more than the win it would have handed me.

**P3.** verilog is the corpus's worst row by damage, 3,544 roots over 94,657
bytes, and the board's own docstring records that a recovery policy change
bought 25,000 bytes of apparent standing by *describing 43% less*. A parser
that shreds a file into 3,544 top-level pieces is not one I expect to be
mostly right inside the pieces. I would rather predict against myself and be
pleasantly surprised.

**P4.** This is an identity, and I am predicting it because if I am wrong the
board's buckets overlap and something much worse than a scoreboard is broken.
Written as a prediction so the instrument has to assert it rather than assume
it.

**P5.** php is the oracle for php. It parsed `Str.php` well enough for `plumb`
to adjudicate 59,146 built bytes against it and find 32,615 of them regrouped.
An oracle that adjudicates cannot have been in recovery over the same bytes.

**P6.** The whole candidate win rests on this. If there is no such case, the
honest scoreboard has an empty improvements row here and I will write it that
way.

**P7.** Twenty-six instruments have been caught here. Mine reads two printers
across thirty grammars and has to tell "the oracle refused this file" from
"my harness refused this file", and those two failures produce the same
absence. The flattering direction is obvious: every harness failure I fail to
notice becomes a byte tree-sitter "could not parse".

**P8.** `picorv32.v` is 94,657 bytes and its ERROR is the root. One file is
18% of the corpus. Any total I quote is that file plus rounding, and a
scoreboard that leads with the total is doing what `unbound` did.

## What I am deliberately not predicting

**How many bytes the improvement is worth.** That is the number this lane
exists to produce and predicting it would give the instrument a target to
agree with. What is fixed in advance instead is the *rule*: a byte counts
toward an improvement only if (a) tree-sitter refuses it, (b) joints builds
it, and (c) the structure joints builds there is adjudicated right by hand
against the language's own grammar, with the adjudication written out. Bytes
failing (c) are a gap, and bytes I did not adjudicate are neither.

## The tripwires

Both sides, both known independently of the instrument:

- **must be red** — `research/joinery/specimen/swift/multiline-comment.swift`.
  Joints reads that comment as arithmetic with zero mends; tree-sitter reads
  it as a `multiline_comment`. Under my adjudication rule this file must score
  as a **gap** and must not appear anywhere in an improvements column. An
  instrument that scores it a win is broken in exactly the way this lane
  exists to catch.
- **must be green** — javascript. `differential.py` calls it byte-exact and
  `plumb` reads it at zero. The refusal census must report **zero** ERROR
  bytes on `ledger.js` from either side.
