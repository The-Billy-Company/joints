`outliner parse --scars` enumerates every repair the parse performed: one line
per mend, where it was, what it deleted, and what the stack did about it.

```
scar 24582..24594 12B kept unexpected identifier in state 398, 122 heads, +3501 tokens
scar 24626..24627  1B kept unexpected comment in state 398,      1 heads,    +0 tokens
```

Until now the only signal a consumer had was `mended N over MB` on the verdict
line - a count and a total, with no location attached - so nothing reading the
forest could tell a region the parser understood from one it papered over. That
is the same hole `research/joinery/reprice/` hit and named: a node covering a
byte proves round 1 did not refuse *there*, not that the byte was read as the
author wrote it.

The record is `Quire.scars`, a **side channel** - a sorted disjoint list parallel
to the node array - and the shape is argued rather than assumed. A mend is not a
node: every repair this runtime performs is a deletion (skip to the next token
some root can act on; under `fell`, put the stack down and stand it up in state
zero), so a node over those bytes would invent a parent for text the parser
explicitly refused and would move `built` on every board counting bytes under
nodes. It is not an annotation either: a scar sits *between* the subtree built
before the refusal and the one built after it, and an annotation would have to
pick one and lie about the other. It is deliberately not spelled `[start, end)`,
because that shape means "a node covers these bytes" everywhere else in this
binary and here it means the opposite - so a reader pattern-matching node lines
cannot match a scar by accident. `--scars` replaces the tree on stdout rather
than interleaving with it.

Six fields, each because a caller cannot work without it. `at`/`over` are the
refusal and the resume, and `over - at` is what the repair deleted. `why` is the
refused terminal and the state that refused it, or a lexer's byte. `felled` says
whether the standing chain was carried off or survived, which is what "how
confident is the structure around this" comes to in this runtime. `heads` is the
live readings standing at the break. `shifted` is tokens shifted at the refusal,
printed as a delta - and **`+0` means this refusal is the previous one
re-reported against the next token** rather than a second wall.

That last field is the one that earns its keep immediately. Deciding whether a
wall was real or a cascade of the one before it previously cost a whole extra
parse per byte with the byte blanked - `reprice` spent a round proving the warm
peel was double-counting one break across a whole corpus that way. It is now an
integer already on the record: **48,154 of verilog's 48,339 repairs and 16,632
of haskell's 16,634 shifted nothing**.

`Quire.mends` stays a `u32` count and `Quire.skipped` a byte total; the list is
added beside them rather than widening either, which is what let this land in a
file another lane holds without touching a line of theirs.

Free where nothing mends and unmeasurable where it does: whole-board wall clock
1.26s to 1.23s, per-grammar parse within noise on every row (verilog +1.9%,
haskell -0.6%, swift -2.5%), and `built`/`square` byte-identical on all thirty
rows against an isolation control.
