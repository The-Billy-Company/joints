# tool - the scripts a clone needs

Python, stdlib only, `python3`. Nothing here is built or imported by the
package; these exist so a fresh clone can get to the same numbers this
repository's dossier quotes. They all follow the CLI's exit-code family: **0**
ran, **1** a clean negative answer, **2** an error.

## `grammars.py` - resolve and check the pinned grammars

Every per-language measurement runs over eleven tree-sitter `grammar.json`
files, and `upstream/` is gitignored on purpose - what lives there are clones
kept for study, not sources this package vendors. So the grammars are pinned in
[`../grammars.toml`](../grammars.toml) instead: a repo, a commit, a path, and
the sha256 of the exact bytes. This script is the only thing that turns a pin
back into a file.

```
python3 tool/grammars.py fetch     # populate upstream/grammars/ (the only verb that uses the network)
python3 tool/grammars.py verify    # hash what is on disk against the manifest, offline
python3 tool/grammars.py status    # every pin and its state in one glance
python3 tool/grammars.py list      # the manifest as a table
```

`--json` on the read verbs; `--dest=DIR` to work somewhere other than
`upstream/grammars`, which is how you try a fetch without disturbing a corpus
somebody else is reading.

`fetch` refuses a file whose bytes do not match its pin rather than overwriting
it, because a surprising local edit is a thing to be told about. Delete the file
and re-run if you did mean to take the pin.

**Nothing else in the repository needs the fetch.** `zig build test` carries its
own grammar: `build.zig` embeds one, a build graph that reads a gitignored path
cannot be resolved from a clean checkout, so that one is committed at
`../test/grammar/json.json`. The pin it came from names it with `fixture = …`,
and `verify` hashes the committed copy against the pin and fails naming both
paths and both hashes if they ever disagree. That check is load-bearing rather
than tidy: wrong bytes in that file would compile and pass.

It reads TOML through `tomllib` where there is one and through a closed
subset reader where there is not - the python a bare macOS ships is 3.9.6 and
`tomllib` landed in 3.11, and nobody should need a newer interpreter to check a
hash. That reader raises on anything outside `[[grammar]]` plus
`key = "string"` / `key = 123`, so if you grow the manifest past that shape it
refuses rather than guessing.

## `rung1.py` - hold the dossier's claims to a real run

[`research/joinery/TESTING.md`](../research/joinery/TESTING.md) rests on three
things, and this fails if any of them stops being true:

- every grammar presses to **zero residual conflicts**;
- **nothing disagrees** - the product of the segment effects is the effect of
  the whole file, at every segmentation;
- the **residue never gets past two**.

```
python3 tool/rung1.py              # all eleven
python3 tool/rung1.py c rust       # narrow to a few
python3 tool/rung1.py --json
```

Needs `zig-out/bin/outliner`, so run `zig build` first; `OUTLINER_BIN` points it
somewhere else. It takes about 13 seconds over the whole corpus in ReleaseFast
and minutes in Debug, so build the release binary.

Refusals are reported and not gated. Thirty of them are documented and owned,
and they are the lexer and the fork rather than the monoid, so gating their
count would only fail the people fixing them. json is gated on still reading to
the end, because it is the one grammar that does.

Which corpus file belongs to which grammar comes out of
[`research/joinery/corpus/README.md`](../research/joinery/corpus/README.md)'s
own table, not a copy of it here - that table is what you edit when you add a
language, and a gate that restated it would drift by exactly one file.

`outliner joints` exits 1 whenever anything refused, which is nine grammars out
of eleven today, so this reads what the run *said* rather than what it returned.
A `--json` on `joints` would retire the scraping.

## `differential.py` - is outliner's tree the tree tree-sitter builds?

Node names are the whole compatibility surface: every `highlights.scm` and every
editor integration in the ecosystem is keyed on them, and a tree built from a
*misreading* of tree-sitter's naming rules passes every test written from the
same misreading. Only tree-sitter can settle that, so this runs both parsers on
the same bytes from the same pinned grammar and reports where the two trees
disagree. Rung 6 of [`research/joinery/TESTING.md`](../research/joinery/TESTING.md).

```
python3 tool/differential.py install          # put a dev-only tree-sitter CLI under .local/ (the network verb)
python3 tool/differential.py run              # compare every case
python3 tool/differential.py run --case=corpus/json
python3 tool/differential.py show --case=probe/alias    # both trees, side by side
python3 tool/differential.py list             # the cases, and where each grammar comes from
python3 tool/differential.py spans            # every reader of their stdout, per span shape
python3 tool/differential.py oracle           # is the CLI here, and which version
python3 tool/differential.py sandbox         # does every scanner include stay inside its own grammar
python3 tool/differential.py scanners        # lay every external scanner down, pinned bytes where pinned
```

`--grammar=NAME` for every case on one grammar, `--json` on the read verbs, and
`--verbose` for every finding rather than the first few per case. `run` exits 1
when a difference is left that nobody owns, and 0 when every difference found is
one of the known gaps.

**Reading their output is the part that keeps breaking.** Two readers here have
now broken at a newline - `cst_tree` on a token spanning rows, then
`graft_fields` on a *capture* spanning rows - because their tree printers branch
on `end.row > start.row` and a corpus with nothing multi-line in it cannot see
that branch. So the span shapes live in
[`research/joinery/spans/`](../research/joinery/spans/README.md) and compare as
ordinary cases on every `run`; `spans` is the diagnostic that says which reader
broke on which shape. That README carries the check that the fixture set can
still fail.

**The workspace is split by what a second writer corrupts**, because up to ten
lanes cowork in one checkout and every shared path keyed by a language name has
now bitten. A measurement is three CLI invocations that must all see one
library, so:

- **Shared, and locked.** `lang/<name>/` holds the generated parser, and
  `tree-sitter generate` on c and cpp costs minutes, so it is worth queueing
  for. `alone()` is a readers-writer `flock` per language - exclusive for a
  build, shared for a measurement. A lane that queues says so; one that waits
  past `OUTLINER_ORACLE_PATIENCE` (300 s) refuses rather than writing beside
  the holder; and a run that queued *and* skipped says not to quote it.
- **Owned outright.** `seat/<lane>/` holds the compiled `.dylib`
  (`TREE_SITTER_LIBDIR`) and the CLI's own cache (`XDG_CACHE_HOME`). The CLI
  keeps a lockfile per language in there and **deletes it on exit**, so two
  processes sharing it have one removing the file the other is opening; and it
  recompiles on a criterion this side cannot predict, saying so itself when two
  get there at once. Compiling is seconds, so owning one beats any protocol for
  sharing it. The lane is the calling shell by default - two runs in one
  terminal reuse everything, two terminals share nothing writable -
  and `OUTLINER_LANE` names it explicitly.

Sharing a seat on purpose is a knob, and it reproduces the fault: four lanes on
one seat skip 55 of 76 cases with `printer says value, its query says
declaration`; four lanes on their own seats agree on every row.

**The lock lives in the writer now, not in the caller.** `oracle_build` is the
function that overwrites `lang/<name>/src/grammar.json` and deletes the
`parser.c` beside it, and it used to trust twelve call sites to take `alone()`
first. Nine did. `recover.py`, `research/joinery/adjudicate/`, and
`differential.py`'s own `graft_fields` did not. Raced deliberately, two lanes
handing one language different grammar bytes, unlocked: **one observation in
twelve read a `grammar.json` from arm A beside a `parser.c` generated from arm
B**, and three more had a lane measure the *other* arm's grammar and call it its
own - internally consistent, silent, wrong. Locked: twelve of twelve consistent,
one lane queued once. `alone()` is re-entrant within a process now, so the nine
callers that already held it are unchanged; a *writer* nested inside a reader
refuses rather than deadlocking, because that one is a genuine lock-order fault.

**And a refresh only writes when the bytes differ.** `scanners` used to
`write_bytes` every scanner unconditionally and unlink the generated `parser.c`
beside it. Since `attest` digests an oracle by its whole `src/`, copying a file
onto its own bytes gave one parser two identities. That is the entire source
divergence on this machine: 30 grammars exist as more than one tree, 28 are
byte-identical, and the two that are not - css and toml - agree the moment
generated files come out of the comparison. `scanners` now prints `same` where
it used to print `wrote`.

`differential.py sandbox` is the other half of the same lesson. Three grammars -
ocaml, php, typescript - are monorepo shims whose scanner is one `#include` of a
`common/scanner.h` above its own directory, and php's and typescript's climb the
same distance. Laid out flat they resolve to one path holding 18,018 or 10,097
bytes depending on who wrote last. So `oracle_home()` reproduces each pin's own
repository depth under a per-grammar root - 27 of 30 unchanged - and `sandbox`
fails if any `#include` resolves above `lang/<name>/`.

**tree-sitter is an oracle, never a dependency.** `install` puts the CLI under
gitignored `.local/differential/` and nothing else in the package looks for it:
outliner does not link, vendor, or ship tree-sitter, and that is a hard
contract. With no CLI present `run` prints what is missing and exits **0**, so a
clone without node is not a failing build.

Both sides read the *same* `grammar.json` the press read, out of
`upstream/grammars/`, because a tree-sitter built from a different commit is a
different language and a diff against it means nothing. Seven of the eleven
grammars also need the external scanner from that same commit before
`tree-sitter generate` will produce a parser, and `install` fetches those beside
the pins.

Comparison is on names, on the field a parent reached a child through, on
whether a node is named or anonymous, and on the bytes each node covers.
Position *formatting* is normalized - both sides land in one byte-offset model -
and nothing else is. A name, a field, or a node's presence is the thing under
test and is never normalized away.

Six small grammars are written here rather than pinned, because the corpus does
not happen to contain the shapes that decide the naming rules: an alias landing
on an already-visible symbol, a field on a rule that splices, a hidden
supertype, the four ways to spell one anonymous terminal, and a visible extra.
They are the fastest way to ask tree-sitter a question about a rule shape.

## `census.py` - thirty grammars, and what stopped each one

The eleven corpus grammars have had a reach table since the beginning; the
nineteen held-out ones never had one. This asks all thirty the same question and
sorts the answers by the wall, not the byte.

**This is the board.** It replaces the `reach.py` several lanes still quote,
which lived in gitignored scratch rather than in the tree and read a `truncated`
parse - every byte lexed, no root closed - as reach 0. `--set=corpus` prints the
same eleven rows, corrected.

It reads a wall through `stamp.outcome` rather than deciding one here, which is
why the corpus went from 71.6% of bytes to 100.0% without the parser changing:
this file and `breadth.py` each used to carry their own rule, and neither knew
that **`mended`** means the parse kept reading past the stop its verdict names.
A mended row's `reach` is how far the forest extends, which is not a claim that
what it holds is right - the summary line says so, and keeping *covered* and
*correct* apart is the whole reason the differential exists beside this.

```
python3 tool/census.py                # the table
python3 tool/census.py --set=corpus   # or --set=breadth
python3 tool/census.py --json
```

The `wall` column is derived from the verdict rather than assigned by hand, so
it cannot drift from the parser: `whole` accepted, `unclosed` read every byte
and never closed a root, `lexical` produced no terminal at that offset, `state`
lexed a token the state then refused.

**`lexical` is not a synonym for a lexer bug, and the distinction has cost a
lane a round.** No terminal at an offset happens both when nothing could lex
those bytes and when the terminal exists but the state never offered it. C tells
them apart in five lines, and C declares zero externals: `f("x")` is a stray
byte where `f(y)` is accepted. Read the `blind` column beside it - it counts
externals the grammar declares that we cannot run, and it is the strongest
single predictor of the first kind.

## `standing.py` - covered bytes, split by whether anything was built

`census.py` reports `reach`, and `reach` is a watermark: a parse that mends past
trouble and resumes flies over the hole. The dossier now quotes `covered`
instead - the union of the top-level root spans - which is honest about holes.

`covered` has its own watermark one level down, and this script is what finds
it. `covered` counts a byte as read when a **bare leaf token** stands over it,
and a mend leaves exactly that: a lone token where a subtree should have been.
So a file shredded into 2,596 one-token roots and a file parsed whole can report
the same number.

A top-level root with at least one child is a **construct**; one with none is a
**leaf**. `built` is bytes under a construct, `strewn` is bytes under a leaf,
and the split is the two questions kept apart:

```
covered  = built + strewn      did the parse READ these bytes
standing = built               did it UNDERSTAND them
```

```
python3 tool/standing.py              # the table, worst standing first
python3 tool/standing.py --damage     # worst damage first, which is the work order
python3 tool/standing.py --gap        # worst gap first
python3 tool/standing.py --rubble     # worst rubble first - one bucket, see below
python3 tool/standing.py --unbound    # rubble + spoil, which is NOT the work order
python3 tool/standing.py --set=corpus # or --set=breadth
python3 tool/standing.py --json
python3 tool/standing.py --settle     # re-measure any row an artifact moved under
OUTLINER_WORK=/tmp/mine python3 tool/standing.py   # a private folio cache
```

### Three axes, and the only count that means what `parse whole` sounds like

`built` is the union of the spans of the top-level roots that have a child, and
`tops()` discards every indented row before it is computed. **So neither
`standing` nor `damage` has ever read a byte below the root frontier.** On a
file one root covers whole they read 100% and 0 no matter what the tree
underneath looks like: a child outside its parent contributes its bytes exactly
like a well-placed one, and so do a child out of source order, a node reached
twice, and a whole subtree hung under the wrong parent. That is not a bug in
either column - it is what a frontier measurement *is*, and coverage is worth
measuring. It is only a lie when it is read as correctness.

So the board carries three columns that answer three different questions, and
never adds them up:

```
stand   coverage    did one root reach this byte              built / size
shape   structure   is what it built a TREE                   Quire.survey
trued   agreement   does the oracle defend the derivation     square / size
```

`shape` is the cheapest of the three by a wide margin - ten seconds, no oracle,
every grammar that parses - and it prints one word per row: `tree` when the walk
liked the forest, `loose`/`disorde`/`torn` naming the worst class when it did
not, `void` when nothing was built, and **`unasked`** when the binary handed
back no survey at all. That last one is the point; see `sound.py` below.

The headline is four tallies rather than one, and the fourth is the one to
quote:

```
30 grammars · 17 reached whole (one root over every byte, no gap by construction)
              29 surveyed sound (every node reached once, inside its parent, in source order)
              16 agreed whole (`trued` 100% - the oracle defends every byte), over the 29 row(s) it judged
              16 whole on ALL THREE - coverage, shape and agreement are different questions and this is
                the only count that means what `17 parse whole` sounds like
```

Read on `pin-shapelane` 2026-08-06 (binary `4c262974e`, oracle `d85e736fa`, 30
attributed). **17 -> 16**: the hole this split was cut to size costs exactly one
row, elixir, which builds every byte of its file into one root that surveys
sound and whose derivation the oracle rejects over 22,089 bytes - 48% of the
file. Every other row that reached whole also survives both interior questions.
So the finding is a documentation fix in its magnitude and a real one in its
kind: nothing was silently wrong at 100%/0 except elixir, and no column on this
board could have told you that before now.

Three assertions in `checks()` keep the third axis from going quiet, and all
three redden when pointed at a binary from before the contract (measured against
pin `sound`, binary `b9bd1cc19`, built 2026-08-06T00:15Z): every forest-building
row must carry a `surveyed` clause; the survey's node count off stderr must equal
the printer's line count off stdout (109,717 either way, two independent readings
of one parse); and the walk must have had somewhere to find a fault.

### `--cite` - the one line to paste beside a number you are writing down

A board's footer names the world it was taken in, and a lane copies the *row*.
That is not carelessness - the row is the correct thing to copy - and it is how
four correct boards became four disagreeing headlines in one morning. So the
attribution is a command of its own, priced so it never gets skipped: no survey,
no press, just the world.

```
python3 tool/standing.py --cite                             # ~130 ms, one markdown line
outliner `a525dc9b8` · tree `3d0d2e481` (live) · **no oracle** — outliner's own words

python3 tool/standing.py --cite=board.json --quote=built    # ~100 ms off a saved board
`built` reads **400,044** over 30 row(s) — outliner `346d880fc` · tree `c3d371769` (live) · oracle `d85e736fa` (30 attributed)
```

Those two lines were taken four minutes apart and name different binaries,
because a sibling lane reinstalled `zig-out` in between. That is the whole
argument for the second form in one accident.

The second form is the better one when you have the board, because it renders
the figure and its world **from the same board** and so they cannot drift apart
the way a hand-pasted pair can. It refuses a column that does not add up over
rows, and refuses an oracle column on a board no oracle judged rather than
totalling unmeasured zeroes.

This is the supply side of `sighting.py --gate`, which is CI's `record` job: the
gate refuses a page you changed that reports a measured figure and names no
tree, and it prints whichever of these two commands fits the page. A refusal
with no cheap remedy beside it is a gate that gets disabled.

**Exit 3 means the table is not one measurement.** Every folio and the binary
are digested at read time and read again at the end (`stamp.reconcile`); if a
row's artifact moved in between, that row is marked ` · SPLIT`, the footer names
it with `read <digest>, now <digest>`, and the run exits 3 rather than 0. Not 1,
which is a lane's bad day, and not 2, which is a parser fault. `--settle[=N]`
re-measures only the named rows, up to N rounds, and exits 0 if the table closes
whole. The `cache:` line above it reports what the cache **decided** when each
row asked; the `generation:` line reports what was **read**. Why, and what it
costs (+68 ms, +8.3% of a board): `research/generation/`.

**The gap is the column nothing else here reports, and it reorders the board.**
Measured 2026-08-05 over all thirty: 73.1% covered against **56.1% standing**,
so a sixth of every byte this project calls read is under a leaf. haskell is the
extreme: 23.8% covered, **0.0% standing**, ninety-four roots and ninety-four
leaves, not one construct in the file.

The two numbers move independently, which is the whole point of carrying both.
The same engine fix moved julia 21.2 -> 67.2 covered; 8,847 of those bytes
landed in `built` and 3,732 in `strewn`, so reading `covered` alone would have
overclaimed and dismissing it on a spot-check of the tree would have thrown away
the real ones.

### `strewn` had a watermark of its own, and it was more than half the gap

**A declared extra is a leaf node in a healthy parse too.** A comment, a
docstring, a pragma has no subtree to be missing - it becomes a *top-level* root
only because the mend put the stack down and left no parent to adopt it. Pricing
it as "a token lying where a tree should be" charges a construct's weight to a
comment, so the gap tracks the file's comment density rather than the grammar's
health. Two more columns split it:

```
strewn = orphan + rubble       orphan = under a leaf the grammar calls an extra
                               rubble = under a leaf that is code
```

Measured 2026-08-05 over all thirty, 89,364 strewn is **50,486 orphan and 38,878
rubble**, and the two orders disagree about who is worst:

| by `strewn` | verilog 18,348 · kotlin 17,464 · swift 14,134 · julia 8,800 · haskell 8,133 |
|---|---|
| by `rubble` | verilog 15,081 · elixir 6,984 · julia 6,426 · swift 4,935 · scala 2,126 |

kotlin - the exhibit - is 15,573 bytes of KDoc and **1,891 bytes of code**;
php's 5,744 is 20 bytes of code, haskell's 8,133 is 10, and the corpus five
(c · bash · cpp · go · ruby) are 323 bytes of code between them against 1,797
of comment. elixir, which no board named, is the second-largest real loss.

**The control is `built` refusing to notice.** Blank every comment in a file to
spaces, keeping the length and every offset (`walls.py warm`'s trick), and
kotlin's `built` stays **15,319 to the byte**, its wall stays `unexpected @ at
245 in state 944` and its mend count stays 426, while `covered` falls 91.5% ->
48.1% and `strewn` falls 17,464 -> 1,891. swift holds 7,794 built either way
(14,134 -> 4,935) and verilog 28,337 (18,348 -> 16,233). The comments were
carrying nothing. And the grammars that parse whole have **zero** leaf roots,
because a healthy parse hands every comment to the one root as a child - so the
effect exists only where the parse was already broken, which is what makes it a
symptom worth keeping and a *magnitude* worth distrusting.

### `unbound` was a bound on the wrong question, and it was the dispatch column

The split above is right, and the column built on top of it was not. `unbound =
rubble + spoil` excludes `orphan` on exactly the reasoning in this section - an
orphan byte is a declared extra, a leaf in any parse, so charging it as "a token
lying where a tree should be" would make the column track comment density. True
as a statement about a comment. Read as a **work order** it is catastrophic,
because an orphan byte is still a byte the tree failed to place, and orphans are
produced *by* walls rather than instead of them.

```
damage = size - built = orphan + rubble + spoil
```

`damage` **redefines nothing**. It is a rollup of three of the four buckets, not
a fifth, and it is the headline's own complement - `damage / size` is exactly
`1 - standing`. Everything it says, `standing` was already saying as a share;
nobody had spelled it in bytes, so nobody could sort by it. `unbound` keeps
meaning `rubble + spoil`, because a headline that silently redefines itself is
the same crime one bucket lower.

Measured 2026-08-05 over the thirty, ranking by `damage` instead of `unbound`
moves scala **15 -> 8**, kotlin **8 -> 3**, php **10 -> 6** and zig **16 -> 13**,
and demotes elixir **7 -> 12** and markdown **5 -> 9**. scala is the exhibit:
**104 bytes of `unbound` standing in front of 4,150 bytes of damage, a 40x
flattery**, on a grammar no work order would ever have reached.

`most` is what the damage is made of - the bucket holding more than half, or
`mixed` when none does. It is arithmetic on three columns and never a reading of
the verdict, because `inquest`'s stand-in name is a guess. It refuses a
plurality that is not one: haskell is 36% spoil, 32% orphan, 32% rubble and
reads `mixed`. Grouped in the footer it prints a pattern a lane previously found
by hand - the four widest `orphan` rows are kotlin, php, swift and scala, all
four stopped on a blind external this package cannot run. **No grammar in thirty
has `rubble` as the plurality of its damage**, which is what `--rubble` sorts by.

**`damage` is exactly as corruptible as the `built` it is made of.** On
`picorv32.v`, `--mend=keep` against `fell` moves it 63,937 -> 38,480 and
`standing` 32.5% -> 59.3% while `describes` falls 22,222 -> 12,672 nodes. Every
guard here except one clears that: `covered` rises, `spoil` falls, `rubble`
collapses 14,057 -> 8, bare leaves fall 2,481 -> 48. **Only `describes` catches
it.** Full dossier, five predictions and the two that were wrong:
`research/joinery/board/`.

## `sound.py` - is what it built a tree at all?

`standing` asks whether a root reached a byte. `crooked` asks whether the
oracle agrees with the derivation, and costs minutes and an oracle seat. This
one asks the question in between, which nothing else asks and which costs ten
seconds: **is the thing the parser handed back a tree?** Every node reached
exactly once, every child inside its parent's span, siblings disjoint and in
source order. A forest can fail all four and still stand at 100% with zero
damage, because a misplaced child's bytes count exactly like a well-placed
one's.

```
python3 tool/sound.py                 # every grammar in the roster
python3 tool/sound.py --set=corpus    # or --set=breadth
```

It iterates the roster rather than naming a witness on purpose: toml was the
row that exposed the hole (one loose node under a `string` whose span
`Gather.reduce` computed without its children), but the defect was structural
and any grammar could have carried it.

**Three answers, not two.** The reason this file exists in the shape it does is
that `Quire.survey`'s verdict used to arrive only as a complaint, so a gate
reading it could not tell a sound tree from a tree nobody looked at - the same
defect `collate.py`'s `recall` and `shear.py`'s `cut_rubble` were repaired for,
both of which read zero for "none there were" and for "nobody asked". So
`parse.zig` now prints `surveyed N of M nodes` on **every** parse, before the
optional `UNSOUND:` clause, and `stamp.Outcome` carries `surveyed`/`arena` off
it:

```
outliner: /t/a.toml: accepted, 1 root, surveyed 731 of 731 nodes
outliner: /t/b.zig: stray byte at 41, 4 roots, surveyed 31 of 31 nodes, UNSOUND: 1 loose, 0 disorder, 0 torn
```

A row with no clause is `UNASKED` and fails, loudly, naming `verdict` in
`src/surface/face/outliner/parse.zig`. `survey_test.zig` holds the arenas that
make the walk say no across all four violation classes plus the two legal
shapes a naive containment check would wrongly flag - but no unit test can tell
you the binary in front of *this* board still calls `survey`, which is what the
clause is for. Pointing the gate at pin `sound` (binary `b9bd1cc19`, built
2026-08-06T00:15Z, from before the contract) turns all 29 rows `UNASKED`
instead of clearing them, which is the falsifier the old evidence could not
have.

**29 of 29 asked grammars hand back a tree**, 109,717 nodes walked, measured on
`pin-shapelane` 2026-08-06 (binary `4c262974e`). yaml is the thirtieth and is a
skip rather than a pass: the binary refuses the file outright, so there is no
forest to survey, and the earlier `30 of 30` counted that refusal as a
clearance.

The arenas hold 145,351 nodes against those 109,717, and twenty rows carry
slack (widest verilog, 18,240). That shortfall is arena the roots abandoned -
speculative nodes `Gather.reduce` allocated and no root ended up pointing at -
not forest that went unchecked. Every node any root reaches was walked, which
is exactly what `sound` claims and no more.

## `shear.py` - is the forest one refusal's shadow, or real?

The blanking control above says `covered - standing` moves with comment content.
This one says it moves with **extent**, from the other side: hold the content
fixed and shorten the file instead.

It walks each file's own top-level construct boundaries, ascending, and hands the
same grammar each prefix until one stops being accepted. That locates the *first*
refusal - which the verdict never names, because the verdict names the last one.
The prefix below it is the claim.

```
python3 tool/shear.py                 # every grammar that hands back a forest
python3 tool/shear.py --set=corpus    # or --set=breadth
python3 tool/shear.py --json
```

**Eleven of the nineteen forests hand back one root over every byte of the
prefix, at 100% standing and zero rubble, on identical bytes and an identical
grammar.** 2,206 childless roots across those eleven are downstream of a single
refused token. scala is the extreme: 1,267 roots over 20,107 bytes, and a 75-byte
prefix stands alone.

Two ways to run this wrong, both of which I ran first:

- **Cut at the wall byte.** Lands mid-construct, prefix comes back `truncated`,
  and proves only that half a function is half a function.
- **Cut before the wall the verdict names.** That is the *last* refusal, so every
  earlier one is still in the file: c keeps 13 roots, cpp 24, go 15, bash 20.

The eight that do **not** flip are the interesting rows rather than a failure of
the method: no prefix of them stands alone, because they break before a single
top-level construct closes. They are also, in order, the rubble board - verilog,
elixir, julia, swift, kotlin, markdown, ruby, haskell. So the two groups are two
different failures wearing the same forest, and only the second is a work order.

## `recover.py` - what happens when the file is broken

Every file in the corpus is valid, and so is every held-out file, which is a
strange thing to be true of an incremental parser. `research/joinery/broken/`
holds twenty-five deliberate breaks - unclosed brace, bracket, paren, string, a
dangling keyword, a stray token, an edit caught mid-word - in the four grammars
that are byte-exact on valid input, each with valid code after the break so
"does it recover, or just stop?" has an answer.

```
python3 tool/recover.py                 # the table
python3 tool/recover.py --valid         # the inverse: valid input we refuse
python3 tool/recover.py --spans         # gate its reader on the span shapes
python3 tool/recover.py --show=NAME     # both parsers' answers for one fixture
python3 tool/recover.py --list
```

`--spans` exists because `theirs` here is the **fourth** reader of tree-sitter's
output and the only one `differential.py spans` does not drive. It reads their
default s-expression printer, whose claim is that a node spanning rows is still
one line; that claim is now tested rather than assumed, 18/18. It survives for
the reason the other two broke: a reader is in danger when it reconstructs a
tree from an *indented* human-facing printer, and this printer is not one.

`--valid` reads `research/joinery/valid/` and asks the opposite question, which
turned out to be the one with a finding in it: input a person would write on
purpose, which tree-sitter accepts with no `ERROR` and no `MISSING`, and which
we refuse. It exists because one `broken/` fixture was misfiled - a bare
`return` at program level is perfectly good JavaScript - and the cause was
`_automatic_semicolon`, a **zero-width** external we are blind to. It exits
non-zero while any row stands.

tree-sitter returns one root spanning the whole file on all twenty-five, marking
repairs with `MISSING` and `ERROR`. We return one on none of them.

Read the `verdict` column rather than the byte count. `truncated` means the
lexer read every byte and no root ever closed - the forest still covers the code
after the break - where `stray byte at N` means the parse stopped at N and never
looked at N+1. Flattening those two to "reach 0" is exactly the mistake this
tool made on its first pass, and `breadth.py` had it too.

## `resync.py` - what would recovery be worth, before anyone builds it

The census says we cover 11.2% of the thirty grammars' bytes, and eighteen of
them stop on a wall. Grinding those down one at a time is 461 externals of
per-grammar spelling. Resynchronising the parse instead is one parse-loop
feature. This prices the second so the two can be compared, and **recovery does
not have to exist to be measured**: parse; when it stops, skip the offending
token and parse the rest as a fresh file; add up what each pass reached.

```
python3 tool/resync.py                  # the table
python3 tool/resync.py --set=corpus     # or --set=breadth
python3 tool/resync.py --cap=26000      # hops one file may take before we call it
python3 tool/resync.py --json
```

**11.2% today, under 82.4% resynced.** It is an upper bound and a generous one -
a resumed pass starts in the start state rather than the stack state a real
resynchronisation would resume in, it counts bytes reached rather than bytes
placed correctly, and it steps over one punctuation byte at a time. Read it as
an order of magnitude. The `hops` column is the other half of the answer: php's
whole 67 KB sits behind **one** token.

It mints a folio per grammar rather than pressing per hop, because a press is
109 ms against 6 ms for a minted folio and this walks a file thousands of times.

## `bench.py` - what does outliner cost, against what tree-sitter costs?

The differential asks whether the tree is right. This asks whether the rest of
the pitch is true, and it runs against the same oracle, from the same install,
under the same contract: no tree-sitter, every axis skips, exit **0**.

```
python3 tool/bench.py run                  # every axis, every pinned grammar
python3 tool/bench.py run --grammar=json --axis=artifact
python3 tool/bench.py verify               # hold this machine to bench.baseline.json
python3 tool/bench.py record               # write that baseline from a fresh run
python3 tool/bench.py list                 # the axes, and what each one runs on
python3 tool/bench.py oracle               # is the CLI here, and which version
```

`--reps=N` sets the replicates (default 7; the press axis takes at most 3
because one `tree-sitter generate` of C++ is seventeen seconds). `--json` on
the read verbs. A whole `run` is about three minutes, nearly all of it inside
`tree-sitter generate`. Everything it writes lands in gitignored
`.local/bench/`, never in the differential's tree and never in
`~/.cache/tree-sitter` - the oracle's own parser is compiled to a path we own,
with `tree-sitter build -o`, so two harnesses cannot fight over one cache.

**It builds its own binary**, `-Dcli-optimize=ReleaseFast` into
`.local/bench/build`, and does not read `zig-out`. `zig-out` is whatever the
last person built, and a debug binary measured by accident reads as a
catastrophic regression that is not there. When the tree does not compile - it
often does not, with lanes in `src` - the run falls back to the last good build
in that prefix and stamps the line with the date it was built, so the commit in
the header and the binary under it can be seen to disagree. `OUTLINER_BIN`
overrides the whole thing and is reported as unverified, because at that point
somebody else chose the optimisation mode.

Six axes, each a **cost**, so `ratio = ours / theirs` and under 1.0 always
means outliner is cheaper:

| axis | what it puts side by side |
|---|---|
| `artifact` | one folio against the dynamic library a user installs for that language |
| `install` | one binary + N folios against the CLI (or just the runtime) + N libraries |
| `press` | `mint` against `generate` + `build` - time to a parser you can actually run |
| `throughput` | the marginal cost of one more parse, in nanoseconds per byte |
| `startup` | everything before the first tree: our press, their `dlopen` |
| `memory` | peak resident set for one parse of the same file, from `wait4` |

Two of those need explaining, because they are where a cost benchmark gets
flattered.

**A partial parse is never a throughput number.** Ten of the eleven grammars
stop somewhere in the middle today, and a parser that quits early looks fast. A
timing case is admitted only when *both* parsers swallow the whole input -
outliner says `accepted`, tree-sitter's `--json-summary` says `successful` -
and every grammar that fails that gate is printed with the verdict that failed
it rather than dropped.

**Nothing is subtracted from one side that is not subtracted from the other.**
`outliner parse` presses the grammar on every run and `tree-sitter parse` loads
a library somebody already compiled, so a head-to-head wall clock would be
timing our press. Instead both sides parse the same file k times in one process
and the *slope* between two k's is the marginal cost of one parse - which
cancels process start, dynamic link, grammar load and the press, on both sides,
by the same arithmetic. The fixed cost that removes is not thrown away; it is
the `startup` axis, and it is the worst number in the report. The slope is
sanity-checked against tree-sitter's own `--json-summary` clock, which times
`ts_parser_parse` with no file read around it and is printed beside every
throughput row. On JSON the slope lands 7% above their own clock, which is
about the file read; on Rust it lands 27% *below* it, because their clock is
the first parse in the process and the slope is a warm one. Same order either
way, which is all the check is for.

The input is the corpus file for that language, repeated until it clears 128 KB
(JSON's copies go in an array, since its top level is one value). Same
constructs every other rung measures over, and a clone rebuilds it with no
network.

Every `artifact` row also prints what the folio **deflates** to. Nobody wants to
inflate a parse table before parsing, so that is not a shippable number; it is
there because when the size axis is a loss - and as of `35f3da5` it is a loss on
ten of eleven grammars - the compressed size is the one cheap measurement that
says whether the loss is the format or the design. Today they deflate to 3-6% of
themselves, with the `action` section 65-76% of the bytes, which is a dense table
of near-identical rows written out longhand.

`bench.baseline.json` sits beside this file rather than under a new top-level
`bench/`, because it is one artifact of one tool and `tool/` is already where a
clone looks. `verify` re-measures and fails if a guarded number got worse:
bytes are held absolutely and tightly (2%), because they are deterministic;
durations are held by their *ratio* to tree-sitter with 20-30% slack, because a
duration does not travel between machines but the ratio of two durations taken
in the same run mostly does. A row that is not in the baseline is reported as
new and never fails a run.

The baseline is a **committed measurement of a moving subject**: it carries the
commit, the working-tree cleanliness, both versions, the build mode and the
machine, and every number in it was taken while three lanes were editing `src`.
Re-record it after a change that is meant to move a number, in the same commit,
the way a ratchet baseline is refreshed.

## `pin.py` - a path is not a version

Ten lanes share one `zig-out`, so a comparison arm spelled as a path is
whatever a sibling last installed there. That is not a hypothetical: a lane's
reference binary was rebuilt underneath it twice in one afternoon, once
transiently broken and once **silently rebuilt with that lane's own fix in it**,
which turned a pre-fix arm into a post-fix one and made a before/after read
thirty-of-thirty for the wrong reason.

```
python3 tool/pin.py build                 build this tree into a pin of its own
python3 tool/pin.py build --name before   ... under a name you'll recognise
python3 tool/pin.py arm before            the three exports a measurement needs
python3 tool/pin.py list                  every pin, newest first
python3 tool/pin.py show before           one pin in full
python3 tool/pin.py path before           the binary, for OUTLINER_BIN=$(...)
python3 tool/pin.py verify                every pin's bytes still hash to its record
```

### Taking a before/after that is actually a comparison

**A binary is one third of a measurement.** `arm` prints all three exports,
because the other two are each their own way to read one arm twice:

```sh
eval "$(python3 tool/pin.py arm before)"          # BIN + WORK + LANE, all under the pin
python3 tool/standing.py --json > before.json
eval "$(python3 tool/pin.py arm after)"
python3 tool/standing.py --against=before.json    # every cell, plus what differed
python3 tool/standing.py --twice=3                # is this row stable at all?
```

`OUTLINER_WORK` is a folio cache **under the pin**, because a folio is a derived
artifact of a binary and two pins sharing one cache read whichever pressed last
(the ticket in `order.py` now catches that, and re-mints rather than lying - but
a shared cache still costs both arms a full re-press every time they alternate).

**A folio cache per arm is a hygiene rule, not a collateral check.** Two lanes
have now read "all 30 folios byte-identical across my arms" as proof their change
broke no other grammar. It proves that for a **press** change, because a press
change moves folios and the ones holding still held still against an instrument
demonstrably able to move. It proves nothing for a scanner seating, a lex fix or
a parse-loop change, none of which can move a pressed table at all - there the
agreement is true, verifiable, and about the wrong object. `still.py against`
refuses that clearance now (`vacuous`), and the control you actually want is the
isolation arm: today's tree with only your rows deleted. See the fifth house rule
in [`research/joinery/TESTING.md`](../research/joinery/TESTING.md).
`OUTLINER_LANE` is an oracle seat named after the pin, because without one the
seat is keyed on `os.getppid()` - *which shell you ran from* - and the oracle is
the other parser in every audited column.

**`--twice=N` re-runs the board as N separate processes, and that is the point.**
A loop inside one interpreter inherits the folio decisions, the `accepts` memo
and the oracle identity from the first pass, so it re-prints the first answer N
times and reports the agreement as stability. It cannot fail. Only a fresh
process re-asks every question, which is why `--twice` shells `sys.executable`
instead of calling `table()` in a loop.

**And `--twice` still asks the wrong question on this tree.** It asks *is this
binary's board reproducible*, not *is this board's tree the tree I think it is*,
and with ten lanes editing those diverge: two controls four minutes apart were
each 930-for-930 stable across three processes and **disagreed by 63 standing
points on scala**. Reproducibility is a property of a moment; the board was
publishing it as a property of a change, and had no field in which to say what
else had moved.

So every board now carries a **witness** - `still.take` after the survey, printed
in the footer, embedded under a `witness` key in `--json`, and kept unbidden at
`.local/still/witness/<lane>.json`. It costs 24 ms on a ~950 ms board and 14 KB
of JSON, which is the design constraint: a check anyone is tempted to skip is a
check that does not exist. `--against` and `--twice` then compare the two
**trees** before the numbers, and a diff whose two arms were built from trees
differing in a file you did not claim is refused with the file named, at exit 4.

```sh
python3 tool/standing.py --against=before.json --mine=src/press/,src/kernel/lex/x.zig
```

`--mine` takes a **file, a directory, or a glob**, repeatable and
comma-separable, because a lane's change is `src/press/` and a flag that makes
you spell fourteen paths is a flag whose list stays empty. Two deliberate
looseness decisions, both so the gate survives contact with the tree:

- an unclaimed **`*_test.zig`** is a note, not a refusal - `stamp.builds` already
  draws that line, and a gate firing on a sibling's test edit would fire most of
  the time;
- two boards that ran the **same bytes** cannot have been moved by a source
  difference, so that too is a note. The refusal is for the case where a
  different binary was built from a tree somebody else also touched.

A board saved before this carries no witness and diffs exactly as it used to,
with a line saying the tree question could not be asked - so nothing already on
disk breaks and the gate switches itself on as boards are saved.

`--against` prints movement and provenance **separately** - `2 binaries - what
moved may be the change under test` above the diff - so a `crooked` that moved
because the oracle moved is never read as a board that wanders. Exit codes: 0
nothing moved, 1 numbers moved, 2 error, 3 the table is not one measurement, 4
the two boards are not a comparison.

Anything after `build` goes to `zig build` (`build --name fast
-Dcli-optimize=ReleaseFast`), and pins live under gitignored `.local/pin/`.

`zig build -p <dir>` is the whole cure and has always been there, so the flag is
not the useful part. **A prefix is still a path**: point at
`.local/mine/bin/outliner` a day later and nothing on disk says what it was
built from. A pin is a prefix *plus* a record - the source digest at build time,
the commit, how dirty the tree was, the flags, and the sha256 of the bytes that
came out - and that record is what `stamp.py` reads.

Without it, `DRIFT` could not fire on a pinned binary **at all**: `stamp` infers
a source tree by walking up from the binary looking for a `build.zig`, finds
none above a private prefix, falls back to the live repo, and compares that tree
against itself. The one binary you pinned *because* you expected the tree to
move underneath it was the one that could never report that it had.

Two smaller decisions worth knowing. The source survey is taken **after** the
build, not before, because a sibling can land inside a thirty-second build and
of the two available lies "records the tree it may have read" beats "records the
tree it was asked for" - the honest failure is a pin claiming drift it does not
have, which sends you to look. And `verify` re-hashes rather than trusting the
record, because a pin whose binary somebody overwrote is worse than no pin: it
is a path wearing a version's clothes.

## `stamp.py` - which tree produced this number

A library the other scripts call, not a verb you drive, though
`python3 tool/stamp.py` prints one line if you want to look. Four lanes edit
this repo at once, so every measurement is a claim about a tree state nothing
recorded, and that has already cost two lanes a set of numbers.

`differential.py run`, `rung1.py`, `breadth.py show` and the reach instrument
each take a stamp - before the sweep, not after, so a lane landing mid-run shows
as a stamp that disagrees with the numbers under it - and print it without being
asked: in the text footer, under a `stamp` key
in `--json`, and inside any artifact they save. The load-bearing fact is a
digest of **the source the binary was built from** rather than of the repo the
run happened in, because a measurement is only ever about the former; git is
context around it.

Four hazards, four detectors, because each sees something the others cannot:

- **`TOLD`** - `OUTLINER_BIN` chose this binary rather than the tree's own. A
  lane once left it exported from a scratch build and every instrument here
  silently measured a pre-fix binary for an afternoon. Note that `STALE` cannot
  catch this: a freshly-copied scratch binary has a new mtime and reads as
  perfectly fresh.
- **`STALE`** - something under the binary's own source root is newer than the
  binary, so an in-place rebuild is overdue.
- **`DRIFT`** - the binary's source root no longer matches the live repo. A
  snapshot build is internally consistent and perfectly happy while the world
  moves on without it, so a staleness check alone sees nothing. A binary that
  wrote its own tree down - see `pin.py` - is believed over a guess from its
  path, which is the whole difference between a path and a version.
- **`MOVED`** - the repo's sources changed *between* taking the stamp and
  printing it. Asked at print time, because it is a question about an interval
  and the interval is not over until somebody prints.

None of them fails a run. Measuring an old binary on purpose is what a
before/after pair *is*; the point is that the run says so. Costs ~60 ms.

`python3 tool/stamp.py --hazards` drives all four from the condition each
exists for, constructed rather than staged - proving `MOVED` by touching a file
under `src/` would make every other lane's stamp read `STALE`, and an
instrument that has to vandalise the tree to test itself is not one anybody
runs.

### It also holds the rules for reading what the binary said

Three of them, each of which used to exist in two or three copies that drifted
apart. They live here because this module depends on nothing, so every
instrument can import it and none has an excuse to restate it.

- **`behind(line, source)`** - strips the `outliner: <path>: ` prefix using the
  path the caller passed in. Nothing infers a prefix; two readers used to, with
  a non-greedy `.*?: ` that takes too little the moment a payload contains the
  delimiter.
- **`verdict(stderr, source)`** - what the parse said. `--verdicts` drives it
  across eight shapes with the rule it replaced beside it, which gets 2 wrong.
- **`outcome(stderr, source, size, tree="")`** - what the parse *did* and how
  far it got, in one vocabulary: `whole · unclosed · mended · lexical · state ·
  other`. **`mended` is the one three copies disagreed about** - the parse hit a
  wall, put the stack down and kept reading, and its verdict still names its
  *first* stop. Reading `at N` as the answer reports the parses that read the
  most as the ones that read least. Pass `tree` when the answer has to be right;
  without it a mended reach is -1 and says so rather than guessing zero.
- **`ask(binary, grammar, src, ...)`** - the whole exchange, not just the rule.
  Sharing `outcome` fixed the reading and did not stop the next instrument
  reaching for `subprocess` and writing a fifth reader, so this is the only
  place an instrument runs a parse and hears back what it did. `tree=None`
  fetches the forest only for the parses whose reach needs it, which is the few
  that mended.

## `sole.py` - the audit, as a gate

Six second copies of the rules above were once found here **by hand**, and five
of them were live defects: the reach rule had three copies, only `recover`'s
knew what `mended` meant, and the other two under-reported byte coverage by 28
points for rounds. An audit finds that once. Nobody remembers to run it again.

```
python3 tool/sole.py            the audit; exit 1 if a second copy exists
python3 tool/sole.py --list     what each owner owns, and how firmly it is held
python3 tool/sole.py --probe    build the four copies it claims to catch, and catch them
```

**It holds no copy of what it polices**, which is the whole design: a checker
that restates the rules is itself the next copy to drift. It is handed one fact
- `CLAIMS`, a map of who owns what and which of their functions to read it out
of - and derives every witness from the owner's own AST. Change `stamp.outcome`'s
vocabulary and the gate changes with it, with nothing to update.

Ten rules, and **five are held by shape rather than by text**: a file that
shells `parse` on `BIN`, or writes out six of the eleven corpus names, is caught
whatever it calls its variables. The other five are held by literal, so a copy
that invents its own vocabulary walks past them; `--list` says which is which
rather than presenting one green line for both. One rule - the tree reader -
decides with punctuation and slicing, so there is no literal to match and no
shape to see, and the gate reports that it is blind to it every run.

Exceptions are written where they live, the way a `MONOLITHIC` marker is. A
`# sole: <reason>` comment on or just above the line excuses it and prints the
reason on every run; two exist, and both are real distinctions rather than
fatigue.

**Its corpus is the other `tool/*.py` files, and that is a hole rather than a
scope.** It globs one directory and reads it with Python's `ast`, so every
`.zig` file under `src/` - the product itself - is somewhere this gate has never
looked. It counts both populations on every run rather than quoting them here,
because the second one grows most days. Nobody chose that boundary; it is where an `ast`-shaped
reader happened to stop. It has already been paid for once: a containment rule
spelled twice in Zig, live in one copy and dead in a test, went past this gate
because there was no pass over `src/` for it to be caught by. The audit above
found six second copies by hand and five were defects, and there is no reason
that rate is a property of Python. So the gate prints its corpus on every run,
for the same reason it prints the one rule it is blind to - a gate that reports
only what it looked at reads as a gate that looked everywhere. Extending it
needs a Zig reader, which is its own piece of work and not yet done.

## `order.py` - the same work in a different order costs the same

A complexity gate. It asserts **no duration** - every absolute time this project
quotes is laptop-specific and the report says so - only a **ratio between two
parses on the same machine in the same process**, over the same bytes and the
same nodes, differing solely in which end the bulk token sits at.

```
python3 tool/order.py            all five grammars, held to a 1.6x ceiling
python3 tool/order.py status     the same table, gating nothing
python3 tool/order.py verify     the committed pair is what the construction makes
python3 tool/order.py build      rewrite the pair from the construction
python3 tool/order.py list       which grammars are pinned here
python3 tool/order.py --calibrate --reps 3     the spread the ceiling came from
```

The pair it gates is committed at
[`../research/joinery/order/`](../research/joinery/order/README.md), and its
README carries why the construction matters. The short version: **holding bytes
constant is not holding work constant**, which is what an earlier ablation got
wrong at the cost of a retracted finding, and this is the first pair here that
pins bytes *and* nodes at once. So `verify` re-derives the committed files from
the construction rather than trusting them, and every measuring run re-compares
both counts - a pair that stopped matching reports that it proves nothing rather
than reporting a ratio.

**The ceiling is measured, not chosen.** json ran 0.96 / 1.01 / 1.00 and java
0.88 / 0.96 / 0.99 over three replicates, so 12% is the widest excursion a
grammar without this defect showed; 1.6x leaves about five times that against the
4.3x load swing `bench.py` measured. `--reps` takes the **best** ratio of N,
because noise only ever inflates the slow side and a gate judging the worst
replicate gates the machine.

Both flat grammars stay in the run after they go quiet, because they are the
gate's own control: broken-green would show json passing and mean nothing,
broken-red would show json failing too. Both directions are exercised at once.

**`lex` is a false-negative surface for this class.** The same pair through the
bare lexer costs 46 ms and 47 ms - flat in both orders, and 350x cheaper than the
slow one. The scanner lane's mechanism explains why, and it reads as impossible
until you see it: the expensive thing is a union walk that runs to end-of-file,
and with everything permitted that giant match is both recorded *and taken*, so
the file is swallowed in about ten positions. Narrow the `allow` and the
identical walk happens, the giant match is discarded, the parse takes a
three-byte keyword and pays the same walk again - about 28,000 times. Permitting
less never made a call dearer; it made the correct number of calls, each of them
always this expensive.

So a gate built on `lex` would stay green through a quadratic parse forever.
This one goes through `stamp.ask`, and it re-times the lexer over the worst pair
every run and prints both, so the trap is demonstrated rather than written down
once.

The same "everything permitted" is a false-*positive* surface for parse quality,
and that half was only written here. Read as a token stream, `lex` shows
javascript's ledger as **one** token and kotlin's as one per line - because with
no state naming its terminals, an `immediate` body pattern (a string's interior,
a JSX fragment, a shebang tail) is live at offsets no parse would offer it, and a
negated class wins longest-match. `parse` on the same bytes builds the full tree.
Measured 2026-08-05; `lex` now prints `admitted context-free` under its count, so
the reading is refused at the surface instead of only here.

## `walls.py` - how deep is the tail, really

Every reach table in the dossier names each grammar's **first** wall and stops.
Twenty grammars mend past that wall and stop somewhere it never names, and some
mend in the thousands doing it. The mend count is the one statistic that cannot
tell four thousand defects from one defect shouting four thousand times, and
that is the difference between a bounded tail and a second project.

```
python3 tool/walls.py                   all thirty, sorted by depth
python3 tool/walls.py --names 5         print the widest distinct walls per row
python3 tool/walls.py --grammar julia   just this one (repeatable)
python3 tool/walls.py --json            machine-readable, distinct walls included
python3 tool/walls.py list              the roster and its sizes
```

```
python3 tool/walls.py warm --grammar haskell        peel without ever restarting
python3 tool/walls.py board --from-json <survey>    the work list, by family and lane
python3 tool/walls.py gate                         CI: does every wall still have a family?
```

It **peels**: parse, take the wall the verdict names, resume from just past it,
repeat, and count how many of the walls were *different*. Two kinds come back
and keeping them apart is most of the value, because they have different owners
- `state` (`unexpected T in state S`, the table refused a token it was handed)
and `lexical` (`stray byte`, nothing could tokenize there at all, which on a
grammar with unrunnable externals is usually theirs). A lexical wall is named by
the **byte itself**, so fifty stray bytes that are all one UTF-8 lead byte read
as one wall and not fifty.

`reach` is `furthest(tree)` over the forest, never the byte in the verdict: a
mended verdict names where trouble *began*, so reading it as reach reports the
parses that read the most as the ones that read least. `voice` is **mends per
distinct wall** - haskell at 4,940 is one bug with a loud voice, and the same
4,940 over four hundred walls would be the second project.

**Take the byte the verdict names, never `reach`.** For a mended parse those are
opposite ends of the file - haskell says `unexpected . at 681 ... mended 4940`
over 34,240 bytes - so a peel that steps past `reach` steps past everything and
reports exactly one wall per grammar. It did, the number was published, and it
was retracted two hours later. `stamp.Outcome.at` exists so the next caller does
not have to know that.

**What the cold peel is not.** Resuming parses the remaining bytes from a clean
start, so each round begins in state 0 rather than in the state the product loop
had accumulated. A peeled wall is one this grammar hits reading that text
*cold* - real and reproducible, and not guaranteed to be the identical wall the
mending loop met there. Rows that hit a timeout, stop advancing, or exhaust
`--depth` say so and are lower bounds rather than answers.

**`warm` bounds that bias**, by never restarting: it parses the whole file every
round and blanks the offending byte with a space, so the prefix stays real and
the accumulated state is the one the parser would have. Blanking rather than
deleting keeps offsets stable across rounds, and it widens on the spot when a
multi-byte terminal survives one blank. It then diffs against the cold peel and
reports the walls only warm could reach, the round each arrived at, and the
back-half arrival rate - which is the statistic that tells a bounded handful
from a layer that keeps giving.

**`board` classifies rather than counts.** Walls are grouped by the *shape* of
the terminal, because the same shape is the same defect wherever it appears, and
each family carries the lane that owns it. The classification is judgment, so it
is one table (`FAMILY`) rather than scattered conditionals, and anything shape
cannot route is printed as an unassigned residue rather than pushed into the
nearest bucket. `--from-json` reads a saved survey, since the classifier is pure
and the survey costs twenty minutes.

**`gate` is `board`'s claim, held.** It peels a fixed nine grammars for a fixed
40 rounds, cold and warm, and fails when a wall belongs to **none** of the
families - which is why `family()` returns `None` rather than falling through to
`named terminal`. A total classifier cannot report a surprise, so making the
residue a predicate instead of an else-branch is the whole design. It does not
gate the wall count: that is a floor which grows with the budget, and gating it
would go red on a longer run with nothing wrong. Roster picked for family spread
rather than depth, because the question is whether anything new in *kind* turns
up. 74 seconds, of which the parity check below is the newer half.

**What green means, and what it does not.** The gate reaches 9 of 30 grammars at
40 rounds. That is deep enough that none of the nine is still finding new
families by the end, and it is **not** the whole space: `walls.py run` peels the
full roster deeper and found two walls the gate never reaches - verilog's `'2` in
states 1328 and 534, which are a repair cascade rather than a family. So a green
gate means **no new kind of difficulty inside that reach**, never "no
unclassified wall exists". The distinction matters because the second reading
would license the deep survey to stop, and the deep survey is the thing that
finds the surprise. The gate prints its own reach on every run so this cannot be
inferred wrongly from a green line alone.

**`gate` also holds the two code paths together.** A grammar can be named to
`outliner parse` as a `grammar.json` or as a minted folio, and for one afternoon
those differed by 110x because the reachability mask was derived at import and
never written through. That loss was in **cost**; the gate asserts it was never
in **meaning**, peeling both ways over the same nine grammars at a smaller
`PARITY` budget and failing on any wall one path has and the other does not. They
agree exactly. The board is measured through folios, because a folio is what
ships, and this is what says the board is not a list of one path's walls.

**A wall lands in a family by the shape of the terminal, and the shapes are
predicates, not lists.** Its first run failed on `:=` and `@` - not a sixth
family, just an enumeration of operators that had never met those two. Anything
tempted to add a row to a list here should ask what predicate the list is
approximating.

**The refused terminal is not always the diagnosis.** `outliner state <grammar>
<n>` prints what the state *admits*, and a state admitting one unproducible
external refuses whatever arrives next - kotlin 110 is six distinct walls and
one cause. Read the row before believing the terminal.

## `likeness.py` - is the generated corpus like real code?

`order.py` reads a **ratio** off a synthetic pair, which no amount of
unrepresentativeness can forge - both halves are the same generated bytes. But
the same construction also put **absolute** numbers on the board, and those did
cross the boundary. This prices every corpus grammar twice on one axis: real
corpus code inflated to the throughput target, and the generated half of its
order pair.

```
python3 tool/likeness.py                 every grammar, real beside generated
python3 tool/likeness.py --grammar java  just this one (repeatable)
python3 tool/likeness.py list            the roster and the generated sizes
```

Neither construction lives here - the inflation is `bench.scale`, the generated
half is `order.build`, both imported. A grammar that **mended** on real code did
less work than a whole parse, so it is printed with its verdict and left out of
the summary rather than compared to a whole one.

The verdict is deliberately three-way. Two poles - "the generator" and "not the
generator" - would have to fall one way or the other on a knife edge, and the
honest shape of today's answer is neither: some grammars pay a large gap and
some pay none, so an absolute number off the generated table needs a **per-row**
caveat and no grammar's gap is evidence about another's.

It does **not** measure the admitted set. Per-position cost is governed by how
far the union walk runs, which voice composition sets - one permissive member
surviving to end-of-file makes every pattern sharing its voice pay a to-EOF walk
- and not by how many terminals are permitted. That was settled in the scanner
lane by mechanism; a correlation here would at best have found a confound.

## `specimen.py` - which externals does anything here actually exercise

The corpus is honest about typical code and silent about everything else, and
the silence is load-bearing. `Maps.kt` and `Chunked.swift` between them contain
no interpolation, no triple quote and no raw string, so a **stateless** hand -
one keeping no memory across a string body, and therefore wrong the moment a
string interpolates - measures byte-perfect on every number this repository
takes. A 20,728-byte Kotlin fix sat undone because nothing could tell it from a
wrong one.

```
python3 tool/specimen.py coverage                    the gate, thirty grammars, ~25 s
python3 tool/specimen.py coverage -v --grammar swift and name the difference
python3 tool/specimen.py coverage --corpus-only      what the real corpus reaches alone
python3 tool/specimen.py coverage --json             machine-readable, all four populations
```

```
python3 tool/specimen.py run [--grammar G]  judge every specimen against its claims
python3 tool/specimen.py show <path>        one specimen, its forest, its claims
python3 tool/specimen.py verify             prove this instrument can still say no
python3 tool/specimen.py list | status
```

Four populations. **declared** is `externals[]` in `grammar.json`. **blind** is
what outliner has no stand-in for, read from `lex` and **not** from `grammar`'s
closing `note: external scanner tokens cannot be lexed here:` - that note names
every declared external rather than the blind ones, and believing it produced a
first gate reporting `seated 0` for all twenty-three scorable grammars.
**seated** is the difference; **exercised** is a seated external some file here
reaches as a node.

Blind has to be *pried out*: every reporting path caps its list at eight names
and appends `+N more`, so the gate rotates `externals[]` by eight and unions the
windows. Sound because `provision` resolves a troupe **by name** and never by
position - and the blind total is compared across every rotation anyway, so a
grammar where order does matter comes back `UNSTEADY` rather than averaged.
Renaming a single external is **not** sound and must never be used for this: a
one-character case change to one blind Kotlin external took its count from 8 to
10, because a cast requires full membership and losing one part unseats the
troupe.

`exercised` is a **floor twice over** and every run says so. 227 of the 263
seated externals in this tree can never become nodes - 225 are `_`-prefixed,
and **2 are aliased away by their own grammar**, which is the later correction:
rust emits `string_close` as the anonymous `"` and `raw_string_literal_content`
as `string_content` at every use site, so tree-sitter itself builds those
constructs correctly and never says either name. Those two could not reach
`exercised` however right the parser was, and the denominator that contained
them was scoring the instrument. 36 can be witnessed at all - the per-row
`(N hidden)` column exists so that Julia's `0 exercised` reads as a blind spot
in the instrument rather than a finding.

The alias rule is "aliased somewhere and referenced plainly nowhere", and both
halves were learned the hard way. Firing on the first alias found reported bash
`exercised 5 of 4 visible` - bash aliases `test_operator` in one production and
admits it plainly in another - and a ratio above one is what an over-tight rule
looks like when nothing checks it. Then counting the symbol *inside* an ALIAS as
its own plain reference made every aliased external look plainly referenced and
produced `0 aliased` across all thirty grammars, so the walk stops descending
into an ALIAS. `inline` and `supertypes` are two further ways a declared name
can fail to reach a tree and neither is read yet, so 36 is an upper bound.

And a construct can parse whole with its external blind, because the
press keeps an ordinary token for any spelling it can lex, so `seated` is a
floor on capability too and only a specimen settles a given construct.

A specimen's verdict is a **tree**, never a byte count. Claims live in a
`.expect` beside the file - `roots`, `mends`, `holds`, `lacks`, `spans` - and
`spans NAME START END` is the one that does the work, because a first-match
reader closing `"""a""""` at byte 15 instead of 16 produces a node of the
correct name and only the extent separates them. Extents are read off the source
text, never off a parser.

Specimens live in `research/joinery/specimen/` and never enter
`upstream/sources/` or the ledger corpus, so no board number moves because the
tier exists. `verify` asserts that against the live board file list, and runs
five more assertions whose whole job is to show a predicate can still say no -
including a real hand regression: `_end_cmd` renamed in a scratch julia.json
unseats the command troupe and `command.jl` drops from 6/6 to 0/6.

**A refusal is not a parse**, and the sixth assertion is there because this
tier got that wrong about itself. `stop()` read roots and mends off the stop
line and defaulted a missing line to one root and no mends, which is the shape
of a perfect parse, so `yaml/comment.yml` scored `roots 1` and `mends 0` as
HELD against a binary that exits 2 with `yaml has no lexable terminal at all`.
The test is now "the binary named no root count at all" - not a nonzero exit,
which swept up seven honest mended and truncated parses - and a refused
specimen prints `REFUSED`, holds nothing, and names the refusal on every claim.
The assertion finds a grammar that refuses and requires `roots 1` and `mends 0`
to fail against it, those two precisely, because they are the pair a defaulted
read makes true for free.

**Exercising an external is not the same as being right about it.** html's
specimen `<p>x</q>` exercises `erroneous_end_tag_name` at the correct extent
and fails anyway, on the `element` above it that outliner never closes - three
roots where the oracle has one. A coverage gate at 100% would have called that
row done, which is the argument for claims over counts stated as a measurement.
See `research/joinery/specimen/RESULT-3-html.md`.

## `absent.py` - what the corpus never presents

The inverse of the gate above, and the reason this tier exists. The Swift
`multiline_comment` fix moved zero bytes on every board in this repository
because `Chunked.swift` contains no `/*`. Every number here is bounded above by
what thirty found files happen to contain, and nothing measured that bound.

```
python3 tool/absent.py run             thirty grammars, the lexical reading
python3 tool/absent.py show <grammar>  its absent spellings and impossible rules
python3 tool/absent.py aim             unwitnessed constructs ranked by pull
python3 tool/absent.py oracle          add the structural half (needs tree-sitter)
python3 tool/absent.py verify          ten assertions, the Swift case first
```

It reads every `STRING` and `PATTERN` leaf out of all thirty `grammar.json`
files and asks whether the corpus file grading that grammar contains the bytes.
**2,050 of 5,198 judgeable spellings are present - 39.4%.**

ABSENT is a **floor**, declared on every run: a spelling counts present if its
bytes occur anywhere, including inside a comment or a string, so the tool can
miss an absence but cannot invent one. The 54 patterns it cannot compile and 32
that match the empty string are counted present for the same reason and
reported separately rather than folded in. yaml spells zero literals - its rules
are all externals - and is reported as outside every number rather than counted
clean.

It is blind to more than it can read, and says which half: **456 of the 461
declared externals have no body in `grammar.json`**, so their spelling lives in
a C scanner. That population is `specimen.py coverage`'s 36-of-461. Neither
instrument covers the other's, and the run prints both denominators rather than
a ratio over the part it can see.

What it is for is aim. Four of the twelve grammars the board reads at 100.0%
standing sit below the 51.1% median presence - latex at **9.1%**, c at 30.3%,
python at 45.3%, javascript at 49.3%. latex reads perfect off a file presenting
one spelling in eleven of what latex declares. That is not evidence about latex
in either direction; it is the size of what the board cannot tell from
correctness.

The structural half (`oracle`: which named rules the oracle's parse never
yields) is calibrated but needs tree-sitter, so it is missing on exactly the
34,687 bytes where tree-sitter ERRORs - where the lexical half is the only
reading available and is the weaker of the two.

## `budge.py` - which columns have only ever held one thing

`still.py against` refuses evidence that is byte-identical either side of a
treatment as `vacuous`: an instrument that did not respond to your change cannot
clear it. That argument is not about boards. `budge` applies it to a single
column of a single record, over every value that column has held in every JSON
this tree has written - which is the instrument the `0 oracle(s)` field
(`research/joinery/still/RESULT-5-oracle.md`) lived its whole life without.

```
python3 tool/budge.py                       the sweep
python3 tool/budge.py show still.Witness    one record: writers, values, documents
python3 tool/budge.py --budget 0            the whole population, not the default slice
python3 tool/budge.py --keep                file this board, so the next run sweeps this one
python3 tool/budge.py against               newly-red rows against the last kept board
python3 tool/budge.py verify                restore the shipped bug, watch one row of eighteen redden
```

**A static half and a dynamic half, and they answer different questions.**
Static: every NamedTuple and dataclass under `tool/` and `research/`, every field
it declares, and every source expression that can decide that field's value -
**107 records, 784 fields**, complete over the tree and blind to what ran.
Dynamic: **2,516 documents, 250 MB, 13,687 objects** attributed to a record by
key-set, 8 that fit two records equally and were charged to neither.

One value is four different findings and the report keeps them apart. `budged`
two or more values, and it is over. `flat` exactly one non-empty value - `0` and
`false` are values, so a boolean always false is `flat` and may be perfectly
right. `void` every observation empty. `silent` the record reached disk and this
key never did. `unseen` no document carried the record at all, which is a hole in
*this sweep* and prints as one rather than as a verdict about the field. Then the
second column says why it did not move: `unwritten` nothing in the tree sets it,
`sealed` one writer and it is a literal, `unasked` its one value is a default its
own CLI declares, `open` the record moved and this column did not, `thin` the
record barely moved either. **Only `open` and `unwritten` convict.** A `thin` row
is an `absent.py` finding wearing a different hat and is answered by widening the
corpus, not by touching the field.

**14 red rows over 784 fields.** The largest is `field.Press.reason`, `""` on all
640 rows on disk against five writers of which four build a real string.
`stamp.Ledger.moved` and `republished` are `[]` on all 55 - a ledger whose
purpose is naming an artifact that moved under a run has never named one.
`walls.Priced.roofed` is declared and absent from all 501 `Priced` written.
`still.Witness.asked` false and `lowered` `{}` on all 19 is one fact rather than
two, and is the honest half of the board: no witness on disk was taken by a run
that *consulted* the oracle rather than attributing one, and driven directly the
pair fills. That is a corpus finding and the row says so.

**A budget changes the verdict, so the board records the one it was taken
under.** Over the default slice, six of `walls.Warm`'s columns read red that read
green over all 250 MB, and `field.Press.reason` - the largest finding here - reads
green as `thin`, the verdict that means *too narrow to say*. `against` refuses two
boards taken under different budgets or different scopes at **exit 4**, in the
same words a board refuses a cross-tree comparison.

**`verify` is the falsifier, and it gates.** It restores the shipped
`0 oracle(s)` bug through `still.stems`, requires exactly one of eighteen
`Witness` fields to redden, and separately requires an empty population to report
eighteen `unseen` and fail nothing - a sweep that reddens on absence of evidence
is the next bug in this family. It plants its own three-grammar corpus rather
than reading the thirty in `.local`, so it holds on a fresh clone with no
toolchain and no `tree-sitter`, which is why it sits in CI's `grammars` job
beside `sole.py --probe` at **2.12 s**. The full sweep deliberately does not
gate; `research/joinery/budge/` carries the predictions, the board and that
argument.
