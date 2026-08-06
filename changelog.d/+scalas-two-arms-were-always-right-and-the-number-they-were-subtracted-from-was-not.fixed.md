Scala's pair was priced against a control reading `damage 16,883` while the live
board read 4,150, and an uncommitted `src/press/` intermediate held a
12,733-byte scala regression for about ten minutes. 4,150 + 12,733 = 16,883.

`retake.py` re-takes the whole two-row population — both in, each out, both out —
from a snapshot refreshed off today's `src/`, with `standing.py --audit` paid
inside each arm's own work dir so `square` is a number rather than a zero.

Both solo arms come back at **11,913 and 6,557, the exact damages `arms.json`
recorded**. The arms were never wrong; the control was.

    was   control 16,883   worth  row 0 −4,970   row 4 −10,326   residual +5,500
    now   control  4,150   worth  row 0 +7,763   row 4  +2,407   residual −7,372

So the +5,500 does not survive and neither does its sign: it was the regression
counted once in the control and once out of each solo. The clean residual is
sub-additive, which means the opposite thing — each row alone recovers most of
what both recover together.

`square` says the residual is a ceiling rather than a coupling. Base 6,739; row 0
out costs **6,739** and row 4 out costs **6,536**, so each row alone accounts for
100.0% and 97.0% of scala's entire agreement with tree-sitter. Two rows cannot
each destroy all of a quantity and also sum, and the two residuals having
opposite signs — −7,372 on `damage`, +6,547 on `square` — is the plainest
available statement that the damage residual was not measuring what it was
quoted for.

The 1,305 → 5,784 node rise reproduces (1,772 → 5,784 clean), and the reading
offered for it does not. *A parser giving up and reducing one huge construct over
the wreckage* is one root; `roots` goes **26 → 1,273**. Twelve hundred roots,
`built` falling 15,957 → 13,550 and `square` collapsing 6,739 → 203 are one
event, and it is the file being shredded into small correct-looking pieces hung
in the wrong places. The original 1,305 was low because the control it came from
was itself a wreck — 3,224 built over 281 roots.

The joint arm is the only real disagreement with the retained family, 6,948
against 7,087. Four files separate the two trees, and a parse that has already
lost both rows is close enough to the floor that a press regression has almost
nothing left to spoil.
