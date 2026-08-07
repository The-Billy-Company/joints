# Prediction 1 - why verilog's oracle cannot be read

Written before running anything against verilog. Scored in
[`RESULT-1-disagreement.md`](RESULT-1-disagreement.md).

## What is already known without measuring

`rack` scores verilog `unjudged` on every built byte. The path is exact and
reading it needs no run:

- `plumb.read` calls `plumb.oracle`, which builds the oracle tree twice - once
  from `tree-sitter parse -x` (`differential.xml_tree`) and once from
  `tree-sitter parse --cst` (`differential.cst_tree`, via `reconciled`).
- `reconciled` reads the CST under **two whole-render bullet columns**,
  `shift = 1` then `shift = 0`, and keeps the first whose `named_only()` shape
  satisfies `same()` against the XML. `same` is exact: field, name, namedness,
  start, end, child count, recursively.
- Neither reading satisfying it returns `None`, which `plumb.oracle` turns into
  `ValueError("tree-sitter's CST and XML disagree with each other")`.
- `plumb.read` catches that into `Read.why`, and `rack.measure` turns a non-empty
  `why` into `blank(...)`, which files **every built byte as `unjudged`** and
  reports the row with an empty `square`.

So the row is not a measurement that came back zero. It is a refusal, printed
into a column named after the oracle's inability rather than ours.

## The predictions

**P1.1 - the message will carry `(the tree has errors in it)`.** verilog's
oracle tree has `ERROR`/`MISSING` nodes in it, so `cst_tree` sets `hurt`.
*Confidence: high.* This is the cheap one and it only tells us which branch we
are in.

**P1.2 - the cause is the bullet column, and it is `reconciled`'s
whole-render assumption that is wrong, not the shift values.** `cst_tree`'s
own docstring already concedes the bullet offset "is 1 in some trees and 0 in
others, and no function of depth, row width or parent I could find predicts
which". The untested half of that sentence is whether it is constant *within*
one render. I predict it is **not**: verilog's CST holds bulleted rows at both
offsets, so no single global `shift` can reconcile, and the `for shift in (1, 0)`
loop is structurally incapable of reading this tree however many values it
tries. *Confidence: medium-high.* This is the load-bearing prediction.

**P1.3 - it is a defect of our reader, not a property of the oracle.** The two
renders are two faces of one parse; the XML nests unambiguously and carries
every named node's field and exact span. Nothing about verilog's grammar makes
the parse unreadable - only our column arithmetic does. *Confidence: high.*

**P1.4 - the disagreement is not any of the four cheaper candidates.**
Specifically I predict **not** truncation by a size or depth bound (the CST is
whole and `cst_tree` would have raised `has N roots`, a different message);
**not** an anonymous/extra-node difference (`named_only()` already drops every
anonymous node before the comparison, and extras appear in both renders);
**not** aliases or supertypes (those change a *name*, identically in both
printers, since both read the same compiled language); and **not** the oracle
erroring with one form reporting it - both forms are produced by the same
`tree-sitter parse` invocation over the same library and neither returns an
error code, or `oracle_run` would have raised first. *Confidence: medium.*
P1.4 is four separate claims and I expect to lose at least one of them.

**P1.5 - the first divergence will be deep and local, not at the root.** If it
were the root or the first few rows, a whole-render shift would have been
noticed the day it was written. I predict the first `same()` failure sits far
into the file, at a node whose bulleted ancestor was read one column off, and
that the *subtree below it* is intact. *Confidence: medium.*

## The prediction that would make this a dead end

**P1.6 - I predict this is NOT a genuine property of the oracle.** If the
opposite holds - if the two renders describe genuinely different parses - then
no reader fixes it, and the job becomes making `rack` refuse loudly. I put this
at under 20%, but the brief is right that it is the branch that has to be named
rather than assumed, and the loud refusal is owed either way: silence is the
defect independent of which branch we are on.

## Sweep

**P1.7 - verilog is not the only row in this state.** The condition is
mechanical and nothing in it is verilog-specific, so I predict **at least one
more grammar** among the thirty either refuses its oracle outright or carries a
non-trivial `unjudged` share nobody has read. *Confidence: medium.* I expect the
other refusals to be a *different* reason (no oracle at all) rather than this
one, so my specific guess is: exactly one other grammar shares this precise
CST/XML failure, and I would not name which.

## Re-pricing

**P1.8 - verilog's `built` will be mostly not-square.** A grammar that mends
1,652 times and hands back 3,544 roots is not agreeing with tree-sitter about
its derivation. I predict `square < 50%` of verilog's built bytes once it can be
adjudicated, and that `unframed` is large, because 3,544 roots against one
oracle tree is exactly the seam shape `unframed` was written to charge.
*Confidence: medium.*

**P1.9 - the 63,937 `damage` figure will survive contact, and will turn out to
be uninformative rather than wrong.** `damage = size - built` is arithmetic over
joints's own forest; adjudication cannot move it. What adjudication adds is
the column that says whether the `built` complement of it was worth anything.
I predict the honest sentence at the end of this lane is *"the number was
correct and was never the question"*. *Confidence: high.*
