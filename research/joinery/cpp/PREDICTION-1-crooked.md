# PREDICTION - what C++'s 63% crooked and 28.9% recall will turn out to be

Written before a single number was taken on this lane. Everything here comes
from `research/joinery/TESTING.md`, `tool/README.md`, `tool/rack.py`'s own
docstring, and the row as it was handed to me (411 damage, 330 orphan, 31
rubble, 36 roots, first wall `"` at 690 in state 907, 6 mends, 63% crooked,
28.9% bracket recall, 29 dynamic precedences). No parse has been run.

Scored honestly in `RESULT-1-crooked.md`. A prediction that turns out
unfalsifiable counts as a miss, not a pass.

---

## P1 - the confusion is C++'s declaration/expression ambiguity, named in
## declarator vocabulary

I predict the widest single crooked family is us building a **declarator
chain** (`declaration` / `init_declarator` / `function_declarator`) where
tree-sitter builds an **expression** (`expression_statement` /
`call_expression` / `binary_expression`), or the mirror of it. C's already-known
finding is exactly this shape one grammar over: `long total;` read as one
`sized_type_specifier` swallowing the identifier, on a `prec.dynamic(-1)`
branch. cpp's two differential findings are recorded as "the template argument,
the same shape".

**Kill:** the widest run names neither a declarator nor an expression node on
either side.

## P2 - `racked` dominates `askew`, by more than 2:1

63% crooked against 411 bytes of damage means the leaves are largely right - a
byte we lexed and placed under *some* node. A right leaf under a wrong parent is
`racked` by construction. If `askew` dominated instead, the deepest node itself
is wrong, which would be a lexer/leaf-naming story and would have shown up on
`plumb` already.

**Kill:** `askew >= racked`.

## P3 - 28.9% recall is one missing or extra *frame* repeated at every level of
## the recursion, not thirty distinct confusions

Node-weighted recall that low, on a file whose bytes are nearly all built,
cannot be a handful of misplaced constructs. I predict a single structural
level-shift - one node kind we systematically never build (or one we insert that
the oracle does not) - whose absence moves every ancestor spine below it, so the
same defect is counted once per node at every depth. My named guess for the
frame is a **block/body frame**: `compound_statement` or `function_definition`,
with `declaration_list`/`field_declaration_list` the alternates.

**Kill:** the crooked runs name three or more unrelated frames with no
recursive relationship, or the top confusion accounts for under a third of the
crooked bytes.

## P4 - it is owned by the press tables, not the lexer and not fork selection

cpp declares few externals we are blind to (TESTING records `cpp 2`), the first
wall is a `state` wall (`unexpected "` - the token lexed and state 907 refused
it) rather than a `stray byte`, and dynamic precedence moving **zero** bytes
says the runtime is never handed two actions to choose between. That leaves the
table. I predict the deciding cells are **statically resolved in the press** -
either by the precedence ladder or by an LALR merge (the `frayed` class, of
which cpp had 116 at last count, the most of any grammar in that table).

**Kill:** `inquest`/wall census attributes the widest crooked run to a lexer
seat, or the runtime turns out to be declining a live fork.

## P5 - the single fixture badly under-represents C++, and the crooked share is
## itself a fixture artifact in one direction

`ledger.cpp` is one small program. `absent.py` will report cpp well under the
51.1% median presence of declared spellings. I predict the *share* (63%) is
robust but the *bytes* are small enough that a specimen-tier or wider fixture
would move the absolute number by more than 3x.

**Kill:** cpp's presence share is at or above the corpus median.

## P6 - dynamic precedence read zero because the contested cell was already
## deleted in the press

The non-result is the clue. I predict the states carrying the crooked
derivation hold **no contested cell at all** at runtime - the reading was
removed at press time (the `frayed`/`read_dropped` mechanism), so a runtime that
newly consults `Production.dynamic` has nothing to consult. This is the same
finding verilog's RESULT-2 reached from the other side.

**Kill:** the state the widest crooked run sits in holds a live contested cell
with two actions.

## P7 - cpp is not alone, and the co-offenders are grammars that parse "whole"

`damage` is blind here because a wrong parent over right leaves is `built`.
So the signature - low damage, high crooked, low recall - should appear on
exactly the grammars the board calls healthy. I predict **at least two** other
rows share it, and I predict at least one of them is a grammar in the board's
"whole"/100%-standing set (the twelve `rack.py whole` covers). I further predict
c itself is one of them, because C's `sized_type_specifier` finding is the same
defect one grammar down.

**Kill:** cpp is the only row on the board with the signature, or no
100%-standing grammar carries it.

## P8 - price: over half of cpp's adjudicable bytes are recoverable by one
## repair

If P3 holds and it is one frame, fixing that one frame re-parents everything
under it. I predict the top single confusion is worth **more than 50%** of
cpp's crooked bytes, and that cpp ranks first or second on the board by
recoverable `square` bytes per repair.

**Kill:** the top confusion is worth under 50%, or another grammar offers more
recoverable square for a cheaper repair.

## P9 - the 36 roots and the 411 damage are the same event as the crooked

I predict the wall at 690 is upstream of the fragmentation: the file breaks into
36 roots because of one refusal, and the crooked derivation is what the mend
built afterwards. So `square` and `damage` will not be independent here - the
crooked bytes will cluster *after* byte 690.

**Kill:** crooked bytes are evenly distributed across the file, or the bulk sits
before 690.
