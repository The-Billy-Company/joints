# Prediction 2 — the arms are blind, scala was priced on wreckage, three rows have no falsifier

Written before a measurement, against the brief and `RESULT-4-clearance.md` §1.
Two facts are already in hand and are declared here rather than dressed up as
predictions, because inventing a prediction after seeing the answer is worse
than admitting the order:

* **Declared, not predicted.** `find .local -name audit.json` was run while
  reading, and there are **six** audit caches on this disk and **none** under
  `.local/aud-iso/`. So the twenty-one-pin ablation family is oracle-blind; that
  is confirmation of the brief, not a finding of mine.
* **Declared, not predicted.** The oracle CLI resolves at
  `.local/differential/cli/node_modules/.bin/tree-sitter`, version 0.26.11,
  matching the brief's claim that the CLI has not moved today.

## The predictions

**P1 — what separates a sighted lane from a blind one is the *default* work
dir, not care.** A lane that never ran `pin.py arm` inherits
`.local/standing/audit.json` and gets an oracle column for free; a lane that
armed got an empty private dir and lost it. So I predict every sighted board on
this disk is sighted for one of exactly two reasons — it used the default work
dir, or it explicitly paid `--audit` — and **zero** arms are sighted by
accident. The corollary I care about: the discipline that makes a comparison
trustworthy is the thing that blinds it, so the more careful the lane, the
blinder its board.

**P2 — copying an audit into an arm's work dir is not a fix, and the machinery
already knows it.** `Held.matches` keys a verdict on folio + binary + source +
oracle, and two arms differ in binary and source by construction. So a seeded
`audit.json` reads `graded: stale` on 30 of 30 rows and mints no square. I
predict this holds *without* a code change, which is what makes "seed it" the
wrong design.

**P3 — the blast radius is wider than the aud-iso family.** Even the shared
default cache is old. I predict **at most two** of the boards retained under
`.local` carry a `square` that is live against the binary that board was taken
with; the rest are either absent (`graded: —`) or `stale`. A board reading
`stale` is not oracle-blind in the same way — it was told and printed a dash —
but it made no claim about agreement either.

**P4 — scala's +5,500 does not survive a clean tree.** The residual was two
harms overlapping on a 16,883-byte damaged parse. Remove the 12,733-byte press
regression and there is much less spoiled region for two rows to share, so I
predict `|residual| < 1000` on `Option.scala` — verdict **additive** — and at
least one of the two worths moves from negative to non-negative.

**P5 — the 1,305 → 5,784 node rise does not reproduce.** That is the shape
`standing.py`'s own docstring warns about, a parse giving up and reducing one
construct over the wreckage, and the wreckage was the regression. I predict the
gap between "both in" and "row 4 out" node counts shrinks by more than half.

**P6 — at least two of the three corpus-only rows are witnessable.** A row can
be invisible to the specimen tier for two reasons: nobody wrote the specimen, or
the row genuinely does nothing. The brief's three rows are all *nested-construct*
rows (scala offside-through-comments, scala block comment, ocaml nested comment),
and nested comments are the single most falsifiable thing in this corpus. I
predict ≥2 of 3 flip a specimen when un-seated, and therefore that their
negative board worth is a `built`-reach artifact rather than evidence of harm.

**P7 — the square-silent refusal fires on the family and not on `--twice`.**
Once the refusal lands I predict it reddens the retained aud-iso boards and
stays silent on every same-binary stability run, because the precondition has to
be the same one `vacuous` uses: two arms, two binaries, and no agreement
measured between them. If it fires on a `--twice` run I got the precondition
wrong and the gate is one people will learn to pass.

**P8 — the cost of sight is the rack sweep and nothing else.** I predict a
per-arm `--audit` costs minutes, not seconds, and that this is why nobody paid
it — so any fix that only *documents* the requirement will be skipped again by
the next lane under the same pressure.
