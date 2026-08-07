# What the bracket seat cost on the axis it was never measured against

`RESULT-1-brackets.md` ends by naming its own gap, second in its "what I trust
least":

> **`nodes 6868 → 12051` is a count, not a correctness claim.** A bigger tree is
> what a working seat produces and also what a runaway one produces. [...]
> nothing here checks the new nodes against the oracle - and `standing`/`damage`
> are structurally blind to interior structure, so they cannot check it either.

This is that check. **It cost 3,080 crooked bytes, and not one of the 6,008
bytes the seat newly built is defended by the oracle.**

Two arms, both pinned, both judged by the same court:

| arm | citation |
|---|---|
| before | joints `03b61a184` · tree `eb08d2a2b` (pin) · oracle `d85e736fa` (30 of 30 live, 30 attributed) |
| after | joints `1885792a7` · tree `4f018b60f` (pin) · oracle `d85e736fa` (30 of 30 live, 30 attributed) |

## The arm, and why it is one change wide

`c589a31` - *haskell's parser-issued brackets are a frame the layout stack
already held* - is **the only commit that touched `src/` at all** between the
elixir board and `fdda15a`:

```text
$ git log --oneline 992aa73..fdda15a -- src/
c589a31 feat: haskell's parser-issued brackets are a frame the layout stack already held
```

Everything else in that window is tooling and pages. So the before-arm is
`c589a31^` built in a detached worktree, and the shared tree was never moved to
take it.

Two tooling commits in the window (`c921b4f`, on `plumb.hurt`, and `e0dc005`)
*can* move `crooked` without the binary moving, which is the whole reason this
is an arm and not an inference: `built` is a union of root spans and only source
can move it, but `crooked` is an audit bucket and re-bucketing is invisible in
the diff of a number. Both arms are therefore judged by **today's** `tool/`.
That is exact rather than approximate - `fdda15a` touched only `changelog.d/`
and haskell research pages, so `tool/` is byte-identical between the worktree
and HEAD, and the audit is held constant by construction rather than by care.

`still.py against` confirms the arms differ only where I claimed:

```text
$ python3 tool/still.py against before handoff --mine src/kernel/lex/,src/.DS_Store
still: ok - subject: 4 file(s) differ and you claim all of them
still: comparable — 1 note(s), none fatal
```

The fourth file is `src/.DS_Store`, a Finder artefact no build graph reads. It
is claimed rather than excused; a partial claim still refuses, so the door was
checked in the direction that matters.

### The apparatus corroborates against another lane

The before-arm reproduces the elixir dossier's corpus totals **to the byte** -
`built 401,115`, `crooked 30,573` - on a different binary, in a different
worktree, taken on a different day by a different lane. That is not part of the
finding; it is the reason to believe the finding.

## One row moves, and every byte of it is accounted for

Thirty rows, twenty-nine byte-identical on all twelve columns. haskell alone:

| column | before | after | delta |
|---|---|---|---|
| built | 8,919 | 14,927 | **+6,008** |
| damage | 25,321 | 19,313 | **−6,008** |
| strewn | 15,901 | 12,627 | −3,274 |
| roots | 2,683 | 2,003 | −680 |
| nodes | 4,691 | 5,526 | +835 |
| standing | 26.05% | 43.60% | +17.55pp |

`built` and `damage` move by the same 6,008 in opposite directions, which is the
seat doing exactly what it claims: bytes that were unbuilt are now under a
construct. `size` is unchanged, so nothing here is a denominator effect.

**Then the third axis, which is the part `RESULT-1` could not see.** Split the
+6,008 by what the oracle says about it:

| bucket | before | after | delta | what it means |
|---|---|---|---|---|
| square | 5 | 1 | **−4** | the oracle defends the derivation |
| crooked | 2,029 | 5,109 | **+3,080** | the oracle defends it as *structurally wrong* |
| soft | 86 | 1,590 | +1,504 | disagreement is extras placement - neither parser is wrong |
| unframed | 6,799 | 8,226 | +1,427 | the oracle hangs these under a frame this parse never built |
| unaudited | 0 | 1 | +1 | no verdict at all |

`3,080 + 1,504 + 1,427 + 1 − 4 = 6,008`. The decomposition is exact, and it is
the finding: **`square` is the one bucket that did not receive any of the new
bytes.** It went *down*. Of 6,008 bytes of structure that did not exist before,
the oracle defends zero, calls 3,080 wrong outright, and hangs 1,427 more under
parents this parse never built.

The commit's own summary reads `nodes 6868 to 12051, so the tree is 75% larger -
structure being built that was not built before, which is what a seat produces
and a suppressed mend does not`. That reading survives this page intact. A
suppressed mend does not raise `built` by 6,008 while dropping `damage` by
6,008, and it does not add 835 surveyed nodes. The seat builds. What the commit
could not say, because no arm asked, is that the oracle agrees with none of it.

## Reading it honestly, in both directions

The temptation is to call this a regression, and the board's own language
supports the charge: it prints `← confidently wrong cost more than visibly
failing` over the rows where `crooked > damage`. **haskell is not one of those
rows.** After the seat, haskell reads `crooked 5,109` against `damage 19,313`,
so visible failure still dominates its fault by nearly 4×, and 6,008 bytes of it
just stopped being visible failure. On the corpus, `damage` fell 125,683 →
119,675 while `crooked` rose 30,573 → 33,653.

The defensible statement is narrower than either headline:

- **On coverage, the seat is a clear win** and was measured as one: `standing`
  26.05% → 43.60%, `roots` −25%, `damage` −6,008.
- **On agreement, it is a cost that was never priced**: +3,080 crooked, and the
  whole corpus's crooked delta for the day is this one row.
- **It is not a trade the three-axis board can settle for you**, which is the
  argument for the board. Adding the columns would net out to something; the
  board refuses to add them precisely because 6,008 bytes moving from "we could
  not read this" to "we read this and tree-sitter says we read it wrong" is not
  a scalar.

haskell's `trued` was 0.0% before and 0.0% after (`square` 5 and 1, both against
a 34,240-byte file). So the seat did not lose the agreement axis - **haskell
never had it.** Whatever haskell's tree is, the oracle has never defended more
than five bytes of it, and that is the prior finding this page most wants
someone to chase.

## Two instruments had to be repaired to write this page

Both were confidently wrong rather than broken, which is the local pattern.

1. **`standing.py --cite` stamped every citation it ever minted `**no oracle** -
   joints's own words`.** It skips the survey by design - an attribution that
   costs a 30-second board gets skipped - but the survey is also the only thing
   that seats a court, so the field was structurally absent rather than
   measured. The board printed `30 oracle(s) d85e736fa attributed` in the same
   terminal. Seating the court in `--cite` is not the whole fix, because the
   court is a property of the *repo*: on an arm with an empty seat it then
   printed `oracle d85e736fa (30 attributed)`, which is the stronger lie. The
   witness now carries live-verdict counts for the arm, and the citation has
   three states rather than two - including `seated but **no verdict live on
   this arm**`, which is what a square-blind arm should say and previously could
   not.
2. **`still.py against --mine` took a comma-separated list as one path naming no
   file.** `standing.py` splits on commas and `tool/README.md` documents the
   flag of that name as comma-separable, so the wrong spelling is the one a lane
   arrives holding. The mis-parse *widened* the refusal - it reported four
   unclaimed files where the correct spelling reports none - so it read as "your
   isolation is worse than you thought" rather than as a flag that did not
   parse.

Both citations in the table above are minted by the repaired `--cite`.

## What I trust least

1. **`unframed +1,427` is a bucket I am quoting, not one I have audited.** Its
   definition - bytes the oracle hangs under a frame this parse never built - is
   the most interpretable of the three non-square buckets, and it grew by nearly
   a quarter of the new structure. It could be the seat hanging real structure
   under the wrong parent, or the oracle's frame being one this parse
   deliberately does not build. Nothing here distinguishes those, and the
   difference decides whether `+3,080 crooked` is an undercount.
2. **One source per grammar.** haskell's corpus row is one file of 34,240 bytes.
   `built` and `crooked` are byte counts over that file, so a single construct
   with a wide span can carry this entire delta, and I have not localised the
   3,080 to a construct. The seat's warrant was censused over all 3,543 states;
   this cost is measured over one file.
3. **`square 5 → 1` is four bytes and I am reading it as a sign.** At that
   magnitude it is as likely to be an incidental boundary shift as a
   consequence. The load-bearing claim is that `square` received *none* of the
   6,008, which does not depend on the sign of the four.
4. **The two tooling commits are excluded by the arm, not by inspection.** I
   held `tool/` constant and let the binary vary, which is the right shape, but
   I never read `c921b4f` to check whether it re-buckets haskell specifically.
   If it does, this arm still attributes correctly - both sides were bucketed
   the same way - but the *elixir dossier's* 30,573 and my 33,653 would then be
   comparable only by the coincidence that they agree on the before-arm. They
   do agree, exactly, which is the evidence against that worry rather than a
   proof.
