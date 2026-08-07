Three rows off last night's audited base board, on the two columns every page in
this repository quotes:

```
grammar   size     built    damage  standing   square   trued
php       67,845   67,845        0    100.0%   67,845  100.0%
html      72,288   72,288        0    100.0%   72,288  100.0%
elixir    46,089   46,089        0    100.0%   23,879   51.8%
```

php and html are finished. elixir builds every byte of `router.ex` and derives
22,210 of them under parents tree-sitter does not use - 48% of the file. `damage`
and `standing` are structurally incapable of saying so, because both are
joints's own words about joints's own forest, and the reader who copies that
row into a page copies a bare zero.

**`damage 0` is not one fact.** It is *audited and clean* on php, and it is
*nobody asked* on every row of every unaudited board - which is 28 of the 33
boards on this disk. `tool/standing.py` now refuses to print the second one:
a row with no `trued` byte behind its zero prints `—`, and the em dash reads as
a question nobody put rather than as a clearance somebody earned. A **non**-zero
`damage` still prints, deliberately and against the letter of the handoff: it is
a charge we levy on ourselves in the one direction no oracle is needed to
believe, and blanking it would empty the column on every board that has not paid
for an audit, which is all of them by default.

Three more things fall out of the same distinction:

- The board opens **UNSIGHTED** when no row on it has an oracle verdict. The
  header already records the tree it read and refuses cross-tree comparison;
  this is the same header saying no second parser was consulted, on the face of
  the board rather than in the reader's inference.
- `whole N of 30` split in two. It meant *one root over every byte* - a
  coverage fact four pages had already read as a correctness fact. Now
  **reached whole** (that, unchanged) and **agreed whole** (`trued` 100%), and
  on an unasked board the second reads `agreed whole — unasked` rather than
  zero.
- A new check: *a `damage` of zero is only printed where the oracle defends a
  byte*. On this tree it reports **0 of 17 zero-damage rows carry `trued`
  bytes, 17 print `—`**. The second half of the check - that the two sets
  differ, so `damage 0` and `trued 100%` cannot be mistaken for each other -
  stays silent rather than green when there is no corroborated row to exhibit
  it, because a check that passes over an empty set is the shape being fixed.

Measured on `joints e51716d6c`, tree `61c93c367`, no oracle - which is exactly
why every `damage` column on it now reads `—` or a charge and never a clearance.
