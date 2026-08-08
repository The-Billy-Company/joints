# rung: gloss

`zig build bench-gloss`

Compiles every `.scm` query file the pinned grammars actually ship — 82 files
across 28 grammars — and reports per grammar. This is a rung and not a test
because it needs the grammars underfoot: run `python3 tool/grammars.py fetch`
first, and a grammar that is missing is a skipped row.

Four sections, and only one of them is a benchmark in the usual sense.

| Section | Question |
|---|---|
| acceptance | how many files compile, and what refused the rest |
| statically dead | how many patterns name only real things and still cannot match |
| name lookup | hash map against `press.dafsa.rank()`, same keys, both arms |
| `#match?` | compiled with the query against compiled per candidate |

## Acceptance is the premise, so it prints the failures by name

**74 of 82.** Every refusal is listed with the file, the error, and *the word
that did it* — `QueryUnknownLiteral fallthrough at byte 969`, not a count. That
list is the section's real output; the totals row is context for it. A compiler
that accepted all 82 by treating an unresolvable name as a wildcard would print a
nicer number and be worth less.

Every accepted file is **read back through the folio codec inside the rung**, per
file. "Compiles" here means a reader holding only bytes can read it, because a
program that fails to read back is a program that would have been written into a
folio.

`src B` and `prog B` are tallied over the **same** files — accepted ones. They
were not, at first: source counted every file and program bytes only the accepted
ones, so a grammar with a refusal printed sub-1x "compression" that was a missing
numerator. The ratio is ~3.16x and it is an **expansion**: the win is that the
bytes are resolved, never that they are smaller.

`core` and `carried` split the predicates the policy evaluates from the ones it
carries as opaque metadata. Both numbers matter — a corpus is mostly directives.

## The dead-pattern count is meant to be small

**One**, in `lua/highlights.scm`. The section prints a per-cause breakdown so a
future regression says *which* kind of proof started firing. It reported 72 while
the name model was wrong, so a jump here is far more likely to be this check
breaking than the corpus rotting.

## The DAFSA arm loses, and the row stays anyway

Same shape as the `quotient` rung's `names` row and the same discipline: the
comparison is printed every run so "the map wins" keeps having to be true. It
currently loses **5.18x** on probe and 45x on build over 8,820 keys. Scala's
12.26x is a shape effect — long shared prefixes are where the automaton's walk is
longest.

`shared` counts symbols whose spelling another symbol already took. It is not a
performance number; it is there because it is **20 of 28 grammars** and that fact
is why a query name resolves to a set rather than an id.

## `#match?` is the headline and the ratio is a floor

708 candidates over 59 patterns is ~12 each, which is pessimistic on purpose. The
compile is paid once per query program either way, so the number of candidates is
the whole trade — a `highlights.scm` over one real file is thousands, and at one
candidate we would lose. The section prints both arms so that stays visible.
