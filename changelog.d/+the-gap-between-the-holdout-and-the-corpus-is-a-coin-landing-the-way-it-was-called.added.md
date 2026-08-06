`holdout.py doubt` pools every measured row from both arms of the generalization
gate, forgets which side each came from, and re-splits them at random into a
group the holdout's size and a group the corpus's size ten thousand times,
scoring each split exactly the way the headline is scored.

The headline it doubts is Tier B's deliverable: the sealed holdout reads 23.8%
trued against the working corpus's 50.5%, a gap of 26.7 points, and the whole
dossier existed to produce that one number.

    absence set aside        gap 26.7 points    p = 0.2697
    absence charged as zero  gap 15.9 points    p = 0.4898
    null distribution, 5th / 50th / 95th:   -39.2 / 0.1 / 36.7 points

A random partition of the same grammars clears the observed gap 27% of the time
under the first counting rule and 49% under the second. Twenty grammars weighted
by their own file sizes cannot resolve a 27-point difference — one large row
landing on one side moves the number further than the effect being measured. I
had written "and it is real under either rule" into the result before running
this; it is not, and the retraction is in the file.

This does not rescue the corpus figure either: the same arithmetic says 50.5%
has an error bar nobody has ever printed beside it. What it kills is the
inference everyone wanted, that the ratio 0.47x measures how much of this month
generalises. The direction is what I would bet on; the magnitude is not measured.

The verb reads only the aggregate `Sealed` rows the gate already prints, so it
costs nothing against the seal — there is no finer information in a p-value than
in the number it doubts. The seed is fixed so the p-value is a fact rather than
a draw, and both counting rules are reported because a headline that is only
significant under the framing that discards rows is a framing, not a finding.

What survives the doubt, and is worth more than the gap: three unseen grammars
(`func`, `jsonnet`, `rasi`) read 100.0% trued byte-exact against tree-sitter,
which is a fact about individual rows that no sample-size argument touches; and
43.8% of off-corpus built bytes sit under a frame we never built against 17.2%
on-corpus, which is a claim about the composition of failure rather than the
distance between two means.
