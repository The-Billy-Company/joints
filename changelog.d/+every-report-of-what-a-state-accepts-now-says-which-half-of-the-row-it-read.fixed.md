An LR row has two halves - shifts, where the state consumes the token, and
reduce-lookaheads, where it only folds - and `drive.offer` hands the scanner
both, because that is tree-sitter's `valid_symbols` and `valid_symbols` is all a
scanner reads. Every count taken over "what this state admits" was therefore one
of two facts without saying which, and the error is always in the same direction:
the narrow read is the shift read, the shift read prints zeros, zeros read as a
clearance, and a clearance licenses work that is unsound. `state --census` was
fixed for this yesterday after printing `shift 0` across 28 pairs that sit
together ten times in the column a hand reads. This is the rest of the family.

**`inquest`** computed which half admitted its stand-in and threw the answer
away, so a wall's owner line named a terminal with no way to tell whether the
state was waiting for it or merely tolerating it as a lookahead - and `inquest`
is what `parse` prints and what the board's damage table quotes, so the
conflation reached every reader of every wall. Findings carry `admitted:
?lalr.Half` now and the line reads `[no stand-in for X, admitted by shift]`.
**`joints legal`** printed `it accepts:` over one flat list of every non-error
action truncated at twelve, so a state with three shifts and two hundred
lookaheads showed a mixed dozen and read as a state that consumes twelve tokens;
it prints `it reads:` and `it folds on:` as two separately counted, separately
truncated lists. **`Expected.wanted`** is not a report but is the same bug: two
offers fill it with two different sets - `drive.offer` the union, `Gather.offer`
only what survives its folds to a shift - both deliberately, and the field said
neither. The split itself was a private enum in `state.zig`; it is `lalr.Half`
beside `Action` now, so a census of a mechanism and the mechanism cannot drift
the way `lex`'s blind count did when it called swift blind to `_explicit_semi`
while the parser was emitting it.

**Zero board cells move, and that is the result.** Two pins through
`tool/standing.py`: every numeric column identical, `363,987 built + 56,343
orphan + 24,167 rubble + 82,301 spoil = 526,798`, `describes` 97,595, thirty of
thirty trees identical. The entire diff is eight diagnostic sentences growing
`, admitted by shift` plus the stamp lines.

Three gates, each with an anti-vacuity half, because a gate over "every report
names its half" passes perfectly while examining nothing. `Half.of` is total and
disjoint over the verb enum, written as an exhaustive `inline for` so a fifth
verb reddens rather than quietly leaving one list - **and** a pressed grammar
must contain a state where both halves are occupied and unequal, or the whole
distinction has nothing behind it. `inquest` must set `admitted` whenever it sets
`unlexable` - **and** both `.shift` and `.fold` must occur among the findings.

Where it is weaker than it looks: **all eight findings on the board say `shift`
and not one says `fold`.** That is not a defect - `awaited` ranks shifts above
folds, so the fold pass only speaks when no blind shift is in the row - but it
means the fold branch of the newly honest report is exercised by no grammar in
the corpus and only by a hand-built row in a unit test. A reader trusting the
board would conclude the fold half never happens, which is this same error one
size smaller. And the sweep that looked for a fifth member found none, so it
confirmed a reading rather than testing it; the prediction written before the
sweep said it would catch a site reading had missed, and it is logged as failed.
