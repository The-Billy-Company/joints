`absent.py` counted a spelling present if its bytes occurred anywhere in the
file, comments and strings included. Its author measured their own defect and
declined to fix it:

> **34 of 211 multi-byte spellings called present never occur outside a comment
> or string — 16.1%**, and 45.5% for css, 31.7% for scala. `ledger.scala`
> contains `true` 17 times and `false` 16 times and **not one is a
> `boolean_literal`.**

Their reason for declining was good and stands: `absent.py` is the only reading
available on the 34,687 built bytes where tree-sitter itself ERRORs, and an
instrument that needs an oracle cannot be that. So the byte reading is untouched
and a second one sits beside it.

**A spelling is present as a node when some occurrence of its bytes is covered
by an oracle node named by a rule that spells it**, or by the name that grammar
aliases that rule to. The test is deliberately not "is it inside a comment" —
that is what fooled the previous detector, which flagged lua `--` at 44
occurrences and css `/*` at 71, comment *openers* that of course sit inside the
node they open. The test is "is it inside the thing that declares it", and lua
`--` comes back present.

Of the **1,767** spellings the byte reading calls present over the 27 grammars
with an oracle: **506** are spelled only inside a `token(...)` and no tree can
answer for them; of the **1,261** that remain, **288 are never tokenised by the
oracle at all — 22.8%.** That is the overcount `present` was carrying.
**253** of the 288 occur only ever strictly inside another token, and each one
now names its host — `scala true inside block_comment`, `bash '|' inside "||"`,
`c '%' inside string_content`. Widest share is css at 16 of 30. Corpus-wide
`present` goes **2,050 → 1,762 of 5,198 judgeable, 39.4% → 33.9%.**

`impossible` therefore becomes a range rather than a number. The byte reading
cannot invent an absence and misses some; the node reading cannot miss one and
invents some, because a literal folded into a `token(...)` or a C scanner is
never a token of its own however often the construct occurs. Over the 27 oracled
grammars: **floor 903, ceiling 1,094 — and 5 of that 1,094 are rules the oracle
actually BUILT, so 1,089 is the most the ceiling can honestly claim.** The
published 1,319 is the lower end of a range.

**Where it costs.** 506 of 1,767 — 28.6% — are outside the node reading
entirely, and three whole grammars (verilog, sql, yaml) get no node reading at
all. The prediction written beforehand called this the result that would hurt,
and it does: the honest headline is not "the number was 39.4% and is really
lower" but **two readings, each blind where the other sees**, and neither
percentage means anything quoted without the other.

Two rows nearly shipped as false findings and were run down instead. TypeScript's
`string` rule collided with the anonymous `string` token in `type Foo = string;`,
and toml's `escape_sequence` is produced by an `ALIAS` from a different rule;
both would have printed as "the oracle built a rule this file calls impossible",
which is a defect in the instrument and not a finding. `witness` filters to
named nodes and resolves aliases, and the cross-check now prints `none — the two
readings never contradict each other`. That line is a tripwire, not decoration.
