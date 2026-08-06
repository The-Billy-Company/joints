# Result 2 — Tier B, the sealed twenty

`tool/holdout.py`. Selection rule: `SELECTION.md`, written before it ran. Pins:
`holdout/holdout.toml`. Seal: `holdout/README.md`, `holdout/ledger.json`, and
`holdout.py prove`. Bytes: `holdout/vendor/`, gitignored, 40 files verifying to
their pinned sha256.

Oracle `8df5c72f4` over 20 grammars, tree-sitter 0.26.11, **UNPINNED** — this
is the shared tree four lanes write to. Binary `f6569f034413`, tree
`299964a876ee`.

## The one cold number

    holdout    23.8%  trued   over 18 of 20 rows, 218,268 bytes
    corpus     50.5%  trued   over 27 of 30 rows, 406,816 bytes
    gap        26.7 points — the holdout is 0.47× the working corpus

Both numbers are from **one run of one function** (`holdout.score`), one binary,
one oracle, ninety seconds apart. The corpus number is not quoted from the
board; `holdout.py gate --versus` measures it.

Charging the rows nobody could measure as zero instead of setting them aside:

    holdout    23.1%      corpus  39.0%      gap 15.9 points

Both framings are printed by the gate because the choice is worth ten points
and a reader shown one of them is being handed a framing rather than a
measurement. The gap is 16 to 27 points wide depending on how you count
absence.

## The gap does not survive being doubted

I wrote "and it is real under either rule" here, and then tested it. It is not.

    holdout.py doubt

pools all fifty rows, forgets which side each came from, and re-splits them at
random into a group the holdout's size and a group the corpus's size, ten
thousand times, scoring each split exactly the way the headline is scored.

    absence set aside        gap 26.7 points    p = 0.2697
    absence charged as zero  gap 15.9 points    p = 0.4898

    null distribution, 5th / 50th / 95th:   −39.2 / 0.1 / 36.7 points

**A random partition of these same grammars produces a gap at least this wide
27% of the time under the first rule and 49% of the time under the second.**
The null is ±37 points at the 5th and 95th percentiles. Twenty grammars,
weighted by their own file sizes, cannot resolve a 27-point difference — one
large row landing on one side moves the number further than the effect being
measured.

So the honest statement of Tier B's headline is: **the holdout scored 23.8%
against the corpus's 50.5%, and that difference is not distinguishable from
which twenty grammars happened to be drawn.** P2.1 held. It held at a
resolution that cannot tell the prediction from a coin.

This does not make the holdout worthless, and it does not rescue the corpus
number either — the same arithmetic says the corpus's own 50.5% has an error
bar nobody has ever printed beside it. What it kills is the specific inference
everyone wanted from this lane: *the ratio 0.47× is not measurable at n=20.*
The one thing in Tier B that does survive is the structural finding below —
43.8% unframed off-corpus against 17.2% on-corpus — because that is a claim
about where the failures sit, not about how far apart two means are, and it
does not rest on the difference of two byte-weighted averages.

The permutation cannot tell a harder holdout from an overfitted corpus; both
produce the same p-value. Only `SELECTION.md` argues it is the second, and
`SELECTION.md` is an argument, not a measurement.

## Which copy answered — and the count is still twenty

A sibling lane found that a grammar is not one thing on this disk: `attest.py`
seats an oracle on its **sources**, and most grammars exist as several source
trees at once, css's two differing in 62.3% of their bytes. For a sealed
holdout that is the specific fatality sealing exists to prevent — unsealing
later against a different copy would read as generalization failure or success
with no way to tell which.

Measured, over the 47 rows this gate reads:

    holdout   20 of 20 grammars have exactly ONE oracle source tree on disk
    corpus    14 of 27 measured rows have two or more (toml has three)

**The multiplicity is entirely on the comparator arm.** It has to be: the
holdout's oracle is generated from `holdout/vendor/`, which is this lane's
alone and which no other lane writes to, while the corpus arm reads the shared
`.local` trees ten agents rebuild. So the number at risk was never 23.8%. It
was 50.5%.

So I measured what the copies are worth. `holdout.py forked <grammar>` reads
the same source bytes against each copy in turn, each in its own seat:

    14 forked grammars · 29 distinct oracle source trees
    grammars where two or more copies could answer at all:   0
    grammars whose `trued` depends on which copy answered:   0

**Exactly one copy per grammar can answer.** The others are source trees with
no generated `parser.c` — they cannot be compiled, so they were never a second
opinion. `attest.survey` is right that the bytes differ and right to say so; the
reading that 28 grammars exist as several different *parsers* is one step
further than the digests support, at least for these 47.

The mechanism underneath is why, and it is worth stating because it is what
actually protects both arms: `differential.oracle_build` overwrites a tree's
`src/grammar.json` with the one it was handed whenever the digests differ, and
regenerates from it. **The oracle is a function of the `grammar.json` the caller
passes plus the CLI version — not of which directory was found.** Both of mine
are digest-pinned: the corpus arm's by `upstream/grammars/`, the holdout arm's
by a committed manifest of repo + commit + sha256.

**The count does not change. The holdout is still twenty.**

### What is now recorded

`holdout/oracle.json`, written by the gate on every run and tracked in git:
per row, the oracle's `src/` tree digest, its home, and how many distinct
copies of it exist on this disk — beside the run's `attest` court digest, the
CLI version, the seat, and the binary. The gate prints the same facts in its
own footer, including a `FORKED` line naming the grammars with more than one
copy and stating that the digest above is the copy that answered.

`told()` now consults twice: each row's oracle is digested at the instant that
row is read, and the court is taken again at the foot of the report. If a
sibling rebuilds something mid-run the two disagree and the gate says
`MOVED MID-RUN` and names the rows, rather than attributing a two-parser
aggregate to one identity. It did not fire on these runs.

The residual hazard the copy survey cannot close is a `parser.c` generated from
something other than the `grammar.json` beside it: `oracle_build` compares only
the grammar digests, so a stale generated parser next to a correct grammar is
used as-is. `attest.survey` covers `parser.c`, so the recorded digest moves —
and `prove` now asserts that by moving one byte of a scratch copy rather than
by assuming it, with an untouched-copy control so a sensor that just returns a
fresh number each call cannot pass.

Tier A never consults an oracle at all — pressing parses nothing — so its
identity is each row's `grammar.json` sha256 plus its pin. All 320 rows now
carry repo + revision + path in `sweep.json`, and the sweep says in its own
footer that it has no oracle rather than leaving a reader to infer it.

## Selection, and how it survived first contact

`SELECTION.md`'s rule ran over all 310 commit-pinned roster entries: 37
eligible, alphabetical stride to 20. Two full runs of `select` produced a
**byte-identical** `eligibility.json` (sha256 `6ab9efc9fb9e6458…`), which is the
determinism claim discharged rather than asserted.

The first run sealed **19**, not 20. `hcl`'s chosen source file is
`example/real_world_stuff/coreos/coreos%tectonic-installer%…%main.tf` — a path
with `%` in it — and my fetcher spliced it into a URL unquoted, so GitHub read
`%te` as an escape and returned 404. The tool reported "bytes vanished between
listing and fetch", which is what it should say and was not what happened.
Percent-encoding the path restored `hcl` and changed nothing else; the
manifests differ by exactly that one row.

Worth naming because of what it nearly did: **the instrument silently dropped
the single largest holdout candidate and reported a clean 19.** A gate whose
failure mode is "one fewer row, no error" is the shape this tree keeps getting
caught by.

Shape of the twenty, reported *after* selection as an observation and not used
in it: 14 declare at least one external terminal, 4 carry a RESIDUAL cell, 20
of 20 press. Sources 1,123 to 48,409 bytes, 218,268 total.

## Is the holdout a thinner sample than the corpus?

No — it is a **denser** one. `holdout.py thin` runs `absent.py`'s own reader
over the twenty files:

    the corpus presents  39.4%  of 5,198 declared spellings
    the holdout presents 53.3%  of 2,793

So the gap cannot be explained away as "the holdout files exercise less of
their grammars." They exercise more. That runs against the direction I
predicted and it makes the gap harder to dismiss, not easier.

(297 of the holdout's declared externals have no body in `grammar.json` at all.
This reader cannot see one of them, so 53.3% is an overcount in the same way
the corpus's 39.4% is.)

## What the failures are made of

Aggregate per grammar, which is all the seal permits and all that is needed.

**Declaring an external is the single loudest signal on the board.**

    declares no external terminal   6 rows · 5 at or above 50% trued
    declares at least one          12 rows · 3 at or above 50% trued

**And the dominant failure is not a wrong leaf — it is no parent at all.**
`unframed` is rack's column for bytes whose derivation agrees rung for rung
*under a frame outliner never built*. Same run, same rack:

    holdout    45,284 of 103,358 built bytes are unframed   43.8%
    corpus     60,067 of 350,028                            17.2%

2.5×. Seven holdout rows are more than half unframed and one is 100%: it builds
every byte of its file and not one of them sits under the right parent. This is
the class the brief says `rack` was blind to until this week — html producing
three roots and no `element` and scoring clean — and off-corpus it is not an
edge case, it is the main event.

## The predictions

### P2.1 — holdout trued below 25% — **HELD**

23.8%, and 23.1% under the harsh denominator. It held by 1.2 points, which is
close enough that I would not want to defend it against a different twenty —
and `holdout.py doubt` then showed I cannot: a random re-split of the same
grammars clears this margin about a quarter of the time. **The prediction held
and the instrument cannot tell that from luck.** Both halves of that sentence
are the result.

### P2.2 — no holdout grammar reads 100% trued — **FALSIFIED**

**Three do.** `func`, `jsonnet` and `rasi`: unseen grammars, unseen files,
byte-exact derivation against tree-sitter with nothing in this repository ever
tuned toward them. `strace` reads 99.7%.

By the prediction's own words this is "the single best result available from
this lane", and it is the finding I would put first. The 23.8% is not a parser
that is uniformly 76% wrong; it is a parser that is **exactly right on some
whole languages it has never seen** and falls off a cliff on others.

### P2.3 — unseated externals dominate, tables do not — **HALF HELD**

Among the 10 measured rows below 50% trued:

    declare ≥ 1 external    9 of 10   90%   (predicted > 70%)  ✓
    carry a RESIDUAL cell   3 of 10   30%   (predicted < 25%)  ✗

The external clause holds comfortably. The RESIDUAL clause misses, and the
miss is the interesting half: **conflict resolution is not clean off-corpus.**
The corpus reaches zero residual on eleven grammars; three of ten holdout
failures carry residual cells. That is the shape of a resolver tuned against
eleven grammars.

### P2.4 — my re-measured corpus is not 50.4% — **FALSIFIED**

**50.5%.** Within 0.1 points of the number in the brief. I predicted the
corpus figure would move under me because `rack` is being repaired live and
because the oracle is unattributed; it did not. That is good news about the
tree's stability and it means I could have quoted the brief.

It is *not* an argument that quoting would have been correct. Half an hour
earlier, `rack.py board` over the same corpus reported `php` at 662 square
where the cached `standing` audit had 19,016. The two instruments disagree
about a single row by a factor of 29 while agreeing about the corpus total to
0.1 points, because they differ in which rows enter the denominator, not in
the arithmetic. A quote that landed on the right number for the wrong reason
is still a quote.

### P2.5 — the gap is not a clean estimate of overfitting

**FALSIFIED as stated, and I still believe the claim.**

I predicted the holdout would present below 39.4% of its declared spellings. It
presents 53.3%. The specific mechanism I named — a thinner holdout inflating
the gap — is not there, and runs the other way.

The claim underneath survives on different evidence. The holdout is 20 files
and the corpus is 30; `unframed` is 2.8× as large a share off-corpus, which is
a difference in *kind* of failure and not only degree; and two of twenty
produced no verdict at all for reasons that have nothing to do with either
parser. I am reporting the gap as the best estimate anybody has and not as a
clean one.

### P2.6 — at least three of twenty cannot be measured — **FALSIFIED**

**Two.** `vhdl` builds nothing (167 of its 204 terminals are external, and the
press said so before the oracle was ever asked). `tera` gets no verdict because
tree-sitter's own CST and XML output disagree — an oracle-side failure, and the
same one that takes `sql` and `verilog` out of the corpus denominator.

Both are recorded as `none`/`void` and sit in **neither** the numerator nor the
denominator. Absence is its own outcome here; that rule is the direct
descendant of `specimen.py`'s `stop()` defaulting a missing stop line to the
shape of a perfect parse.

### P2.7 — I can violate my own seal and be caught — **HELD, 9/9**

See below. The first two versions of the leak test were both wrong, in opposite
directions, and that is the part worth reading.

## The seal, and breaking it on purpose

`holdout.py prove` — nine constructed assertions, exit 1 if any fails.

    ok  there is a manifest to seal: 20 pin(s)
    ok  the sealed row type has no field a diagnosis fits in
    ok  4 node name(s) and 53 byte offset(s) held beside the gate for one sealed
        row; 0 name(s) and 0 offset(s) reached its output over the human and
        --json channels, after 1 row(s) with nothing to smuggle
    ok  and the detector is not blind: one witness stapled to the gate's own
        output is found (0 name(s), 1 offset(s))
    ok  a second `select` refuses rather than re-rolling the twenty
    ok  an unsealing with a blank reason is refused
    ok  an unsealing of a grammar that is not sealed is refused
    ok  a real unsealing takes the holdout 20 -> 19 and writes one ledger entry
        naming who and why
    ok  and the live ledger is untouched by the proof above

The third assertion is the real one and it took three tries.

**Version one** scanned `gate`'s own source constants for the words "state" and
"unexpected". It passed, and it could not have done anything else: it asserted
that literals I wrote do not contain words I did not write. A green light with
no bulb in it.

**Version two** measured a sealed row for real, intercepted the `rack.Seen` on
its way past — every disagreeing run with both parsers' node names and both
byte offsets — and searched the gate's output for all of them. It **failed**,
reporting one escaped witness, which was a byte offset that happened to equal
one of the aggregates the row is entitled to print. A birthday-paradox
detector, not a leak detector.

**Version three** subtracts the row's own printable integers, and then renders
the gate a second time over a control row with every measured value blanked.
Anything present in both renders is template and could not have been carried by
the measurement. That is what passes now, and the fourth assertion staples a
real witness to the output and confirms the detector still finds it.

An unsealing is `holdout.py unseal <name> --reason "…"`. It appends to
`holdout/ledger.json` with the grammar, the reason, the timestamp, the lane,
and how many are left, and there is no verb that undoes it. `prove` performs a
real one against a scratch ledger in a tmpdir and then asserts the live ledger
is untouched — so the mechanism is exercised without spending a grammar.

**Nothing has been unsealed. The holdout is twenty.**

## A defect the corpus could not have found

Two of eighteen holdout rows report a **negative `crooked`**.

The board's soft rule (`standing.audit`, copied into `holdout.score` rather
than restated) subtracts, from `crooked`, the width of every widest RUN whose
bytes are blank or whose node name on either side is a declared extra. But
`crooked` is `askew + racked`, and the widest-run list also contains `unframed`
runs, which are in neither. **`soft` is sampled from a population wider than
the column it is taken out of.** Feed it a grammar with enough unframed bytes
and the subtraction goes past zero.

Thirty corpus rows never produce it — 0 of 27 measured rows on this same run.
Off-corpus it took eighteen rows to find twice.

This crosses the seal as a **shape and not a witness**: the mechanism above is
readable from `rack.py`'s and `standing.py`'s own definitions with no holdout
byte in hand, and I have not looked at which runs in which files did it. Both
files are owned by other lanes and I have not touched either. `trued` is
unaffected — it is `square / size` and never reads `crooked`.

## The honest reading of the gap

The holdout parses at **0.47×** the working corpus's rate, on files that
exercise **more** of their grammars, measured by one instrument on one run.

What that supports: a month of work generalises **partially**. Three unseen
languages come out byte-exact, which no amount of overfitting to thirty
grammars produces by accident — the press and the spine are doing real general
work. Eight of eighteen rows clear 50%.

What it does not support: "we take any `grammar.json`" as a claim about
*parsing*. As a claim about *pressing* it is now measured and true — 320 of 320
(Tier A). As a claim about producing tree-sitter's derivation it is off by
roughly half, and the deficit is concentrated in one class: **43.8% of the
bytes we build off-corpus sit under a frame we never built**, against 17.2%
on-corpus. That is not a lexing problem and it is not a table problem. It is
the class the board could not see until this week.

What nobody can get from this lane: whether 26.7 points is *the* number, or
whether it is a number at all. `doubt` says a random partition of these same
grammars clears it 27% of the time. **The gap is the deliverable and the gap is
not resolvable at n=20.** The direction is what I would bet on and the
magnitude is not measured.

So the four sentences worth carrying out of Tier B, ordered by how much weight
each will hold:

1. **Three unseen languages read 100% trued.** One run, one binary, byte-exact
   against tree-sitter. This is a fact about individual rows and no sample size
   argument touches it.
2. **43.8% of off-corpus built bytes are unframed, against 17.2% on-corpus.**
   A claim about the *composition* of failure, not the distance between two
   means, and it points at a named class in a named file.
3. **Pressing generalises completely** — 320 of 320 (Tier A), and that one is
   not a sample, it is a census.
4. **The holdout scored 23.8% against 50.5%, p = 0.27.** Directionally the
   thing everyone expected; statistically a coin landing the way it was called.

Before today the answer was unmeasured. It is now measured badly, which is a
different and better state, and the way to improve it is more rows rather than
more looks at these twenty.

## The instrument I trust least, and how I caught it

Not `rack`, not `stamp.verdict`, not the oracle. **`holdout.py forked`, the
verb I wrote an hour ago to check the copies** — and it is the right answer
because it is the one that already lied to me and nearly got published.

Its first version staged each copy of a grammar's oracle and read the same file
against each. It printed this, across fourteen grammars:

    14 forked grammars; 0 whose `trued` depends on which copy answered
    css   100.0% 100.0%      scala  33.5% 33.5%      toml  99.2% 99.2% 99.2%

Fourteen rows of perfect agreement. It is exactly the shape of a reassuring
result, I had a section half-written around it, and it was an artifact of the
instrument. `plumb.read` calls `differential.oracle_build`, which **overwrites a
copy's `src/grammar.json` with the one it was handed and regenerates
`parser.c`**. So the verb normalised every copy to the same grammar and then
reported that the copies agreed. They did. After being made identical.

What caught it was not the verdict — the verdict was clean, twice. It was
asking a question the verdict cannot answer: *what actually differs between
these directories on disk?*

    css     parser.c
    scala   alloc.h, array.h, grammar.json, node-types.json, parser.c, parser.h

Thirteen of the fourteen differed in `grammar.json` itself. Two trees with
different grammars cannot produce identical trued to one decimal place on the
same file, so either the copies were not what the digest said or the comparison
was not comparing them. It was the second.

Standing `oracle_build` down is now the whole correctness of the verb, and it
is the first thing its docstring says. With it stood down the honest answer
appeared immediately: every alternate copy is an ungenerated tree that cannot
be compiled at all, so **one copy answers and there is no second opinion to
disagree with**. Same conclusion, arrived at for a reason instead of by
accident — and if it had gone the other way I would have shipped the accident.

The general shape, which is this tree's recurring one: **a comparison whose
setup silently makes the two arms equal will report that they are equal, and it
reads exactly like a clean result.** `specimen.py`'s `stop()` defaulted a
missing stop line to one root and no mends. `order.py::miss` keys folio
freshness on a path plus an mtime, so a before-arm reads its after-arm's table
and the error is always flattering, because two runs of the same table always
agree. Mine normalised the input. Three instruments, one failure: the flattering
default.

Two things follow that I would not have written yesterday. First, the `doubt`
verb exists for the same reason and I trust it for the same reason — it is
built to make my own headline look worse, and it did, so its bias runs against
me. Second, every "no difference" in this dossier is worth less than every
"difference", because a null is what an instrument returns when it is broken
and a spread is not. The 43.8%-vs-17.2% unframed split is the finding I would
defend hardest; the p = 0.27 and the zero fork spread are the two I would
re-derive first if anything downstream depended on them.

## Reproducing

    python3 tool/holdout.py status            # what is sealed, what is spent
    python3 tool/holdout.py verify            # offline: 40 pinned files
    python3 tool/holdout.py press             # tables only; spends nothing
    python3 tool/holdout.py thin              # absent.py over the twenty
    python3 tool/holdout.py gate --versus     # the two numbers, one run
    python3 tool/holdout.py doubt             # permute the labels; p on the gap
    python3 tool/holdout.py forked <grammar>  # one file, every copy of its oracle
    python3 tool/holdout.py prove             # 12 assertions on the seal

`doubt` reads only the aggregate `Sealed` rows the gate already prints, so it
costs nothing against the seal — there is no finer information in a p-value
than in the number it doubts.
