# Prediction 2 — where scala's win lands, and what would prove me wrong

Written against `baseline-board.json`, minted before a line of this lane's
code existed.

```
grammar   size    built  orphan  rubble  spoil  unbound  nodes  roots  leaves  basis
scala    20107     8204   10415     476   1012     1488   1571    314     179  read
```

**The brief quotes scala at "~4,100 unbound". The board says 1,488.** No
column on scala's row is 4,100 and no pair of them sums to it, so the number
is inherited from somewhere the board does not reproduce. That is the first
thing this lane measured and the first thing it is reporting, because a lane
that budgets against 4,100 will read a 1,488-byte drain as a failure.

## Prediction 2a — this is a `standing` win, not an `unbound` win

Scala's damage is not unbound bytes. It is **10,415 bytes of `orphan`** — 52%
of the file sitting under top-level *leaf* roots the grammar calls extras.
Scala's corpus file is comment-dense, the parse shreds into 314 roots, and
every comment the mend could not hand to a parent became a root of its own.

So I predict: seating scala's layout moves the bulk of those bytes back under
a construct. **`built` rises by at least 3× the amount `unbound` falls.**

**Falsifier:** if `unbound` falls by more than `built` rises, my read of where
scala's damage lives is wrong and the layout organ was not the lever.

**Second falsifier, the kotlin trap inverted:** if `orphan` *rises*, bytes
escaped further out rather than coming home, and that is a regression inside
the win. Kotlin's seating did exactly this — `built` fell 1,075 while unbound
fell 67%. I will report it plainly rather than net it against the headline.

## Prediction 2b — the separator alone moves almost nothing

In `tree-sitter-scala/src/scanner.c` the `AUTOMATIC_SEMICOLON` arm at line
1156 is reached only after the `INDENT` arm (963) and both `OUTDENT` arms (910,
1063) have declined. Those three read the indent stack; the separator arm does
not read it at all. So the separator is not *downstream of* a memory the way
`CLASSIFICATION.md` says — it is **sequenced behind** one.

That distinction is testable and I predict it costs a shortcut its life: a
`caesura` tongue for scala, seated alone, leaves every state that wants
`_indent` walled, so it drains **less than 1,000 bytes** of scala's `built`
deficit.

**Falsifier:** build the separator-only treatment as its own measurement. If
scala's `built` rises by more than 1,000 bytes with no stack seated, the arms
are more independent than the C reads, and the layout organ is optional rather
than required.

## Prediction 2c — rubble and spoil, established rather than guessed

The brief warns these do not move in a fixed relationship and that it has been
wrong in both directions. Scala's case is establishable in advance rather than
predictable: with `covered` at 92.6% (`under` 18,619 of 20,107) the parse is
**already reaching** almost every byte. That is swift's case, not haskell's —
so I expect **both to fall**, and `spoil` (1,012) to have very little room to
fall in.

**Falsifier:** if rubble rises, bytes entered the metric's reach for the first
time, which would mean the parse was *not* already reaching them and my read
of `covered` is wrong.
