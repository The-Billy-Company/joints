A resume re-lexes the stretch between two rings and demands the same tokens
back, and to do that it has to stand the scanner where the ring below it left
off. `Gather.holds` decided whether to bother with `x.scanner.casts.len > 0`.

That predicate is the old spelling of "does this grammar have an external
scanner", from when the only external scanner was a hand-written one. A
customary is the other half of "outside" now, and `Scanner.outward` is the
question that covers both - the write side had already been moved onto it, with
a comment on `remembers` saying exactly why. The read side had not. So every
grammar whose whole scanner is a book kept one `Save` per ring, a few kilobytes
each, and read none of them back.

What the re-lex ran with instead was whatever memory the attempt being replaced
had left in the scanner. On yaml that is not a subtle difference: `_bl` is the
blank line the grammar owes itself, zero bytes wide, and whether one is due is a
fact about the organs. Four rings deep, every single time, the ring wanted a
plain scalar and the stale organs answered the `_bl`:

    holds: ring 21 at 8838 wanted _b_sgl_pln_str_blk 8849..8855 got _bl 8849..8849
    holds: ring 20 at 8057 wanted _br_sgl_pln_str_blk 8068..8087 got _bl 8068..8068
    holds: ring 19 at 7523 wanted _br_blk_str_ctn 7530..7603 got _bl 7530..7530
    holds: ring 18 at 6993 wanted _b_sgl_pln_str_blk 7011..7015 got _bl 7011..7011
    alight: declined - firm=9467 unseamed=0 unfit=0 unheld=4 lowest=6928

Four candidates, four re-lex disagreements over bytes nobody had touched, and a
cold parse from the top of the file for a keystroke in the middle of it. One
word.

Fixed, on `research/keystroke/probe.py` over 24 keystrokes: yaml reads 669
tokens where it read 1,327, prefix falls 0.97 → 0.49, and a keystroke costs
1,591 us where it cost 2,529. A prefix of ~0.5 on edits spread through the
interior is the honest floor - it means the parse now stands up *at* the edit and
reads only what is after it.

Three of the four exits from `holds` were silent, which is why this sat behind a
counter reading `unheld=4` for as long as it did. `alight` counts *which* of its
three questions declined, and that was enough to know the re-lex was the one and
useless for knowing why; the two early returns and the final offset comparison
now each say what they saw. The counter told me where to look and the traces told
me what to fix, and it took adding the second to get from one to the other.
