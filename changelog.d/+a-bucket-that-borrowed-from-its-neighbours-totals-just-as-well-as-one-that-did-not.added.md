One arm of the scala retake reported **`crooked −335`**. There cannot be a
negative number of misread bytes.

`crooked` is `rack`'s crooked total less the `soft` share attributed off the
crooked *runs* — extras placement, where a parser hangs a comment, which is an
internal choice rather than a claim about structure and would otherwise inflate
the column by 27.7%. On a shredded parse the subtraction runs out of room: 1,273
top-level roots, blank and extra-named runs everywhere, and the soft share
exceeds the total it is being taken out of.

The board's own consistency check passed on that row. It asserts `square +
crooked + soft + unframed + unaudited == built`, and −335 satisfies it exactly:

    203 + (-335) + 1,353 + 3,878 + 8,451 = 13,550 = built

A bucket that borrowed from its neighbours totals just as well as one that did
not, so the check was structurally blind to it — it was written to catch a
*redefinition* of `built` and cannot see a redistribution inside it.

A fourth assertion runs beside the sum now. It is a strengthening and not a
repair: the −335 still prints, and the board says it is impossible.

    CHECK       the audit splits `built` and does not redefine it: … on 29 of 29
    **BROKEN**  and every part of it is a count: no negative bucket on 29 of 29
                audited rows — BROKEN: scala crooked -335; the sum identity above
                cannot see this, because a bucket that borrowed from its
                neighbours still totals `built`

Green on the healthy control, red on the arm, and it names the row and the
column. The arithmetic in `rack.soft` belongs to another lane and is handed
back, not chased.
