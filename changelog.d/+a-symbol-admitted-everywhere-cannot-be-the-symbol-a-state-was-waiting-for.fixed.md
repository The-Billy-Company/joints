`inquest`'s stand-in picker named a declared extra whenever one was in the wall
state's row, because it scanned the blind externals in symbol order and took the
first cell that was not empty — a shift outright, or the first fold if no shift
turned up. A declared extra is admitted almost everywhere by construction, so in
swift, whose `multiline_comment` is both an extra and the lowest-numbered
external of thirty-three, it won that scan wherever it appeared. State 1226 is
the clean exhibit: the item is `_class_member_declarations ->
_type_level_declaration . …`, so the token the state wanted is a statement
separator, and the row reads `}` fold, `multiline_comment` read, `_implicit_semi`
read, `_explicit_semi` read. The picker answered `multiline_comment`. Two lanes
were sent to the comment scanner for a defect the separator guard owns.

The rule is now four tiers, high wins: a non-extra shift, a non-extra fold, then
those two again for an extra. Strictly-greater comparison, so declaration order
still breaks a tie inside a tier and a row holding one kind answers exactly as it
did before. Ranking an extra's *shift* below a non-extra's *fold* is the one
place this trades against the shift preference the picker already had, and it is
deliberate: the fold at least narrows to something this state tolerates, where
the extra's shift is true of nearly every state in the automaton.

Measured over a stride of swift's 3,416 states on 2026-08-05: 156 answer at all,
the name moves in 60 of them, and `multiline_comment` — which won all 60 — wins
none afterwards. `_implicit_semi` goes from 19 to 72. kotlin and scala do not
move at all, because their extra is not their lowest-numbered blind external, so
order had been answering correctly there by luck.

**Where this goes the wrong way, and the instrument that lied about it.** The
diagnosis handed over said an extra wins because *an extra shifts in nearly every
state*. Measured, that is the minority path: of the 60 displacements, **59 the
extra won as a fold and one as a shift**. A fix that deranked the extra in the
shift pass alone — which is what the diagnosis literally prescribes, and 1226 is
an instance of it — would have repaired one wall in sixty and reported the win.

**And it does not move any of the thirty walls the corpus actually hits.** Swift's
own wall still prints `multiline_comment`, and this change is not what would
alter that: that name comes from the *second* half of argument 5, `blindExtra`,
an existential over the grammar that fires when any blind terminal is an extra
and prints as `lexer?` — unproven, by design. `awaited` is silent at swift's
state 141 because the row admits no blind external there at all. Swift's census
wall, state 585, admits exactly one — `raw_str_part`, a fold — and named it
correctly before and after. So the picker is now right, and the report a reader
sees on a corpus file is unchanged; those are two separate facts and the second
one is the one worth writing down, because measuring only the corpus would have
shown thirty identical rows and read as "the fix does nothing".

`blindExtra`'s position below the path is left alone, and the same cure does not
apply to it. "Make an extra the last resort" is meaningless in a scan whose
predicate *is* being an extra, and swift has nothing to choose among anyway: it
declares three extras — `comment`, `multiline_comment`, `\s+` — and only
`multiline_comment` is one of the thirty-three externals, so it is the unique
blind extra rather than the first of several. The name it prints is the correct
answer to the question it asks; what is uncertain is whether the file holds one
of those bytes at all, which is exactly what the `lexer?` word and the closing
"this is the best reading rather than a proof" already say. Running it above the
path once misfiled three grammars and printed a loop's limit as the scanner's
fault.
