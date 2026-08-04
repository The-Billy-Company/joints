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
  moves on without it, so a staleness check alone sees nothing.
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
