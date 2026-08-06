# Prediction 1 — what the coverage gate will say, before it exists

Written after reading `outside.zig`'s troupe contract and counting declared
externals out of the thirty `grammar.json` files, and before writing a line of
`tool/specimen.py` or running any join. The only measurements taken so far are
the declared counts, Kotlin's blind count of 8, and three hand-run parses of a
three-line Kotlin scratch file.

Every claim below names the measurement that falsifies it.

## The gate I am about to build

Four populations per grammar, each with one honest definition:

- **declared** — the named entries of `externals[]` in `grammar.json`.
- **blind** — the terminals outliner's own report says it has no stand-in for.
- **seated** = declared − blind. *"This tree can make that token."*
- **exercised** — a seated external that some file in this tree actually
  reaches during a real parse. *"Something here would notice if it broke."*

The first three are exact. The fourth is the one I trust least and the one this
lane exists to produce, so its direction of error is declared up front: it is a
**floor**, never a clearance.

## P1 — no grammar exercises all of its seated externals

**Falsified by:** the gate reporting any grammar with `seated > 0` and
`exercised == seated`.

If a grammar existed whose every seatable external is reached by something in
this tree, the corpus would already be doing the job this lane says it cannot
do, for at least one language.

## P2 — fewer than half of all seated externals across the tree are exercised

**Falsified by:** the tree-wide ratio `exercised / seated` coming back at 0.5
or above.

This is the headline. The brief's whole premise is that the corpus is silent
about the awkward constructs, and externals are exactly the constructs a regex
could not lex — which is why they were hand-written in the first place. If the
corpus were reaching most of them, two lanes would not have independently
named it as the instrument that lied.

## P3 — Swift's `multiline_comment` is blind

**Falsified by:** `multiline_comment` appearing in Swift's seated set.

A lane handed this over as Swift's own wall, worth 3,997 orphan bytes. I have
not checked it. If it is *seated* and still costing bytes, the handover named
the wrong mechanism and the finding is that, not the comment.

## P4 — Julia's string interiors are seated, and its specimens parse clean

**Falsified by:** a Julia string specimen producing more than one root, or any
mend at all.

The brief says Julia's interiors were seated today and are stateless. If that
is true, Julia is a regression floor: the specimens should be green on arrival.
A red Julia specimen means either the seating is narrower than reported or my
specimen is wrong, and I have to say which before touching either.

## P5 — every Kotlin string specimen is red today

**Falsified by:** any Kotlin specimen exercising a string construct passing
against the current binary.

Kotlin declares 10 externals and is blind to 8, so `seated = 2`. I have already
watched a three-line file with one interpolation and one triple-quote shatter
into 9 roots with 12 mends. I am predicting this generalises: there is no
Kotlin string construct this tree parses correctly today. If one passes, the
blind set is not the whole story and I need to find what else is standing.

## P6 — the greedy-close specimen distinguishes a first-match reader

**Falsified by:** the assertion I write for `"""x "q" $n"""` being satisfied by
a hand that closes at the embedded `"q"`.

This is the anti-vacuity test for the specimen tier itself. The tier's entire
claim is that a stateless or first-match hand *cannot* pass it. If my strongest
awkward case is satisfiable by the wrong hand, the tier is decoration and I
have rebuilt the instrument I was sent to replace.

## P7 — yaml is the worst grammar the gate reports

**Falsified by:** any grammar coming back with a lower seated ratio than yaml's.

yaml declares 113 externals, more than twice the next grammar. A grammar that
hands that much of itself to a scanner and gets none of it back is the shape of
finding the brief told me to prefer over another Kotlin fixture.

## P8 — the gate refuses to score a grammar with no externals

**Falsified by:** the gate printing a coverage percentage, or anything reading
as a pass, for `c`, `go`, `java`, `json`, `zig`, `verilog`, or
`embedded-template` — the seven grammars that declare zero externals.

This is my own anti-vacuity guard and the failure I was created to prevent. A
gate that reports `0/0 = clean` for seven grammars has found nothing and said
everything is fine, which is precisely how a stateless hand ships.

## What I expect to be wrong about

P3 and P7. P3 is a claim about a handover I have not verified, and P4 says
plainly that if the handover is wrong the handover is the finding. P7 is an
argument from a count rather than from reading yaml's grammar, which is the
kind of reasoning six lanes have now found a flattering number inside.
