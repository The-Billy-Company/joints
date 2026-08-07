# weave

The spine holds effects. The quire holds nodes. The weave holds a *file* -
its text, its spine and its tree, all three maintained together - and answers
one question: apply this edit and give me both again.

Until something owned both halves they were two subsystems with a hyphen
between them. This is that something, and it is deliberately small: a `Loom`
(one pressed grammar and the interning space its effects live in), a `Weave`
(one open file on that loom), `open`, `amend`, `product`. The CLI verb is
`joints amend`.

## What a leaf is

A leaf covers the bytes from the end of the previous token to the end of this
one - whitespace, comments and all - and its element is the product of every
move the parse made while reading it. The elements come from the parse's own
move trail rather than from a second walk of the automaton, so a segment that
a survey would have fanned into nine limbs is one element here: a parse knows
what it did, and a re-exploration only knows what it could have done.

## The re-mint window

`Effect.entry` pins a leaf to the state its run began in, so an edit that
moves the state at some offset invalidates every leaf downstream and an edit
that does not changes nothing downstream at all. How far to widen before
stopping is a cost question, never a correctness one - a mismatch composes to
a refusal, never to a wrong tree - and `Policy` names the three answers.
`prove` is the one in force: the entry state matching *and* the old suffix
composing onto the new prefix, the suffix read out of the spine as a range
query rather than folded leaf by leaf.

`.local/orchestrate/weave.report.md` has the measurements and says why.

## A lift is a read of a nonterminal

A lifted subtree is one move where a cold parse made hundreds. It is priced
as `effect.shift` of the nonterminal it lands, not as the old spine's product
over those bytes - that product prices the *inside* of the subtree and the
reduce that finishes it falls outside, so pricing it that way drops a fold and
the file comes out one reduce short. As a shift it costs one composition,
needs nothing from the old spine, and composes to the product a cold parse
derives.

The consequence is that the tiling is not a function of the bytes alone: a
lift is one leaf where a cold parse has many. Both spines answer every product
question the same way; only the seams differ.

## The tests

`amend_test.zig` is an edit-sequence fuzz, checked after every single edit
against a from-scratch parse - tree, spans, product, and leaves - because an
incremental parser that is right at the end and wrong in the middle is wrong.
It carries its own negative control (`Bend`), a delta-debugging shrinker, and
the two measurements the policy question needed.
