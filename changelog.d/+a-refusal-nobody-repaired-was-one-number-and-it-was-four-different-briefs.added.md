"1,929 scars an insertion could fix" was never a measurable claim, because a
refusal insertion declines is not one thing. `research/joinery/supply/residue.py`
partitions every refusal the parse meets, off a `quire` trace the runtime emits
at each stand-down point:

| | count | whose brief |
|---|---:|---|
| **supplied** | 130 | closed |
| **none** | 1,288 | no anonymous literal resumes the parse — mostly haskell's external scanner |
| **stray** | 444 | no terminal was refused at all; the lexer could not make a token |
| **spurned** | 54 | several literals resume it; the table declines to say which |
| **ground** | 20 | the stack is empty, so nothing was begun and nothing omitted |

(`--mend=fell`, the twelve grammars tree-sitter derives clean, 1,936 refusals.)

So **1,806 of the 1,936 are out of this rule's reach, and they are four
different problems**: a lexer one, an external-scanner one, a ranking one, and
one deliberate refusal. Only the 54 `spurned` are the second move's unfinished
business, and closing them is a *ranking* rule rather than a richer vocabulary.
`markdown`'s entire repair population is `stray` — 79 of 79 — and `supply` is
never even asked about them.

The census reads two independent channels and cross-checks them on every row:
the trace says why `supply` declined, the scar channel says what the parse
actually did, and supplies-announced must equal supplies-printed while
deletions must equal strays plus traced declines. The `adrift` column is that
check.

**It read 0 on all twenty-four rows because it could only ever read 0.** The
first form computed `cut + gave - sum(seen.values())`, and `seen` is the counter
every trace line is put into, so the expression is identically zero whether the
channels agree or not - a failure column that lived inside the failing branch of
a test and could never report its own failure. It is now a signed quantity with
a three-case self-test that shows it failing (`residue.py --selftest`), because
a check that only passes is not one.

**With the check repaired, the census does not close.** On tree `83cf2f249d8b`
it exits 1 on ten of twelve grammars with **+1,337** repairs the two channels
disagree about, and `none` - the largest bucket in the table above - reads
**0**. The refusals it used to hold now emit no trace at all, and `supply` has
no untraced exit that fits, so they are not reaching it: the change is upstream
in `absorb`/`blame` rather than in the rule. **The table above is an older
tree's and is currently unreproducible.** Its shape holds - the residue really
is four different briefs - but the counts want re-taking, and the falsifier that
would have caught this the first time now exists and works.

`reach.py` is the companion and answers the two questions no board does.
**Localization**: the union of deleted byte spans, control against arm, so
"does a richer repair vocabulary tempt the parse to sprawl" is measured rather
than assumed (it does not — verilog goes 52% → 23% under `keep`) — though the
same table shows c and cpp tightening the most while losing `square`, so reach
is a measure of how much the parse repairs, not of whether it is right. **The
blind spot**: `--spans` writes every repair site of a run as
`{at, over, gave, felled, why}` per grammar — 34,419 sites under `keep`, 4,196
under `fell`. `research/joinery/scars/` bounded `square`'s exposure to repaired
ground at 19.9–23.0% with no column anywhere distinguishing it; that file is the
join key for the column, handed to the lane that owns `tool/rack.py` rather than
built into their board.

The trace costs nothing unless lit (`OUTLINER_TRACE=quire`) and names every exit
`supply` has — the four declines `fuse`, `ground`, `none` and `unseated`, plus
`spurned` and `supplied` — so a lane asked to shrink the residue knows which
quarter it is standing in. `fuse` and `unseated` read 0 across this corpus; both
are real paths and neither was reached.
