The reflective troupe fixture in `outside.zig` reads each role's shape off the
field so that spelling a role in both `Troupe` and `Cast` is all it takes to be
seated there. It understood a name, a run of names, and a run of records
carrying one name. Haskell's bracket orders are a run of records carrying
*two* - an open and its close, which have to resolve together or the seat
strands a frame nothing can pop - so the loop matched no branch, skipped the
field in silence, left both halves null, and failed the row it was seating.
That is the third time this fixture has gone stale, and all three times the
same way: a hand-written understanding of what a role can look like, one shape
behind the roster.

Records are now paired by field name too, the way the outer loop already pairs
the structs - every `?g.Symbol` in a seat slot is filled from the spelling of
the same name in the troupe's record - so a role carrying three names would
need nothing here at all. Against the risk of teaching a fixture to fill
everything and then assert what it filled, the generalisation is held by a
second test that keeps half a role half-resolved: an open with no close must
still be refused, and filling only the closes must flip the same cast to
seated, so the fixture's new reach is measured by a difference rather than
asserted.

`Cast` had also grown a copy of each pair's frame. It is troupe data, and every
other piece of troupe data in this file is read back off `c.troupe[k]` at the
offset a slot resolved at, the way `roster` reads its `mark`. Copying it gave
one fact two homes that could disagree; the copy is gone and the frame is read
where it lives.
