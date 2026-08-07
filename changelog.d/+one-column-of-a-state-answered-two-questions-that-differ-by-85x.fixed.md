`joints state` printed one flat list of every terminal a state acts on, with
the verb in a second column. Complete and accurate, and worse than a known
liar: "the terminals of this state" has two answers, and for swift's
`_implicit_semi` they differ by 85x — 20 states admit it by shift against 1,712
that have it in their expected set. A reader after the lexical question wants
the first and a reader after the table question wants the second, and one flat
list makes the distinction an annotation the eye slides over. A lane wrote up
both readings as authoritative, hours apart, in the same folder, and its
correction of the first was itself wrong.

The split is the fix and it is not cosmetic: **a shift consumes a byte and a
fold does not**, so a reduce lookahead never puts a token in the hand a scanner
competes with. Two headers that say which is which, a `(none)` where a half is
empty — a state that can only fold is exactly the evidence a lexical lane is
after and an absent header reads as an oversight — and a footer that names both
counts so neither can be taken for the other by a reader in a hurry.

The verb also grew `--census <terminal>...`, which answers over every state at
once what the row answers for one: how many shift it, how many only look ahead
at it, the min/median/max company where it shifts, and — for each pair of the
named terminals — how many states shift *both*. That last column is what a
partial seating turns on, and it is one second over scala's 11,602 states.

It lives in `state.zig` beside the row and shares `Half.of` with it rather than
re-deriving the split, because a census of a mechanism and the mechanism itself
are two implementations of one fact and this repo has already been bitten by
them disagreeing — `lex`'s blind count called swift blind to a terminal the
parser was emitting, because the count read a field that had not heard about
the new role. A test walks the verb enum exhaustively so a fifth verb added
later fails there rather than silently vanishing from one of the two lists.

`inspect`, `rule` and `verdict` moved out of `main.zig` with it; `main.zig` is
600 lines and over the rule.
