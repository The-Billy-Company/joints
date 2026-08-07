A folio's freshness was checked by mtime, and an mtime cannot see a schema
change. Folios minted at 10:13 on 2026-08-05 were refused by the 10:59 binary -
`FolioBadTag`, 11 of 30 grammars - while being, by every clock in this tree,
*newer* than the binary refusing them. So the freshness rule held, the cache
kept all eleven, and `standing.py` rendered eleven refusals as `built` down
**98,247 bytes with twelve grammars dead**. That is the shape of a catastrophic
parser regression and it was very nearly reported as one; the lane that hit it
spent an afternoon proving it was not theirs, ran the unmodified base binary
against the same folios to get the identical collapse, and still concluded a
live regression next door. There was no regression. Every grammar round-tripped
the whole time, in a cache nobody was reading.

The rule is now that a refusal is a **cache miss**. Not staleness, which is what
the mtime answers, and not a parse failure, which is what a row is for - a miss,
whose only correct answer is to recompute. `miss` names the three ways to have
one and asks the binary about the third, because `folio/leaf.zig` has sixteen
ways to refuse a folio and every one is a comparison against a layout the Python
side cannot see; working that judgement out here would be a second copy of the
file format, and the first thing to drift the next time a section is added. So
`accepts` shells `mint <folio>`, takes the **exit status** as the decision, and
only ever quotes the word. If a folio pressed seconds ago is then refused, that
raises `Refused` and stops the run, because a binary that will not read what it
just wrote has not produced a bad row - it has produced a measurement in which
no other row means anything either.

Nothing about refusal is softened, and the guard that fails the build on an
unaccounted press-side field is untouched. `open` refusing a foreign folio is
that system working. This change is entirely downstream of it: the format is
still allowed to say no, and the cache now hears it.

Reproduced before it was fixed, with `.local/bench/pin/joints` (built Aug 4
12:45) as the poison - a real older binary rather than a staged corruption, so
the event is the actual one. Twelve folios minted with it, all twelve
`FolioBadVersion` to today's binary, cache mtime 11:40:35 against a binary mtime
of 11:24:48: fresh by every rule in the tree. Under the old rule the board reads
`0 built + 0 rubble + 84,757 spoil`, **0 nodes, twelve grammars `void`**. Under
the new one, the same poisoned cache reads `37,218 built + 28,908 orphan + 8,462
rubble + 10,169 spoil`, **17,160 nodes, nothing void**, and a second run agrees
with the first. `python3 .local/lane-folio/collapse.py both` is the whole thing
in one command.

What it costs is a process per folio per run, and the honest number is worse
than the docstring's was. `accepts` is a `fork`/`exec`, so the floor is the
spawn and not the folio: 2.7 ms for json's 10 KB, 4.7 ms for rust's 590 KB, 11.8
ms for sql's 1.4 MB, **136 ms across the board's thirty** against a run that
would otherwise finish in ~750. A sixth of a clean board, spent asking a
question whose answer is nearly always yes. The docstring claimed `55 us for
json` and `~13 ms` overall, which were the binary's own map-and-bind timings
with the process left out - a tenfold flattering number sitting in the fix for
flattering numbers, now measured and replaced. The trade is still right, because
the alternative is to remember verdicts across runs keyed on the same mtimes
that could not see a schema change in the first place. That is this bug, one
indirection further out. Within a run a memo keyed on both the folio's identity
*and* the binary's makes repeat callers free, since ten agents share this tree
and either end can move under a run.

The atomic write the previous lane added while chasing the wrong hypothesis is
kept and now tested, because it is a real hazard even though it was not this
one: the freshness rule fires for everybody at once the moment anyone's `zig
build` lands, so overlapping mints are the normal case rather than the unlucky
one. `press` publishes beside the cache and `os.replace`s it in, with the pid
naming the agent and a serial keeping one agent's own overlapping mints off each
other's temp file. `order.py cache` drives eight adversarial cache states and
then two concurrent minters against one path, as real processes rather than
threads - a thread shares the pid, so a threaded test would not have exercised
the thing that makes the temp name unique. **70 publishes, 0 readers ever saw a
partial file.** The in-place control, same harness with the rename removed, tore
55 of 99.

`sole.py` went green on the truth rather than on a comment. Its one red was
`standing.py` shelling `parse` itself, and `stamp.ask(tree=True)` does serve it:
`ranged` now asks `stamp` and reads `len(seen)` for its node count. Getting
there needed `stamp.Outcome` to grow an `unsound` field, since the duplicate was
carrying an unsoundness clause the shared reader parsed and then discarded into
the verdict string. Both readers were run against all thirty grammars first and
agreed on all thirty, so the collapse is behaviour-preserving rather than
hopefully-equivalent. While in there, the gate now prints its **corpus** on
every run next to the rule it already admits being blind to: seventeen
`tool/*.py` files, and every `.zig` file under `src/` outside it - counted live
on each run, because that second number grew twice while this was being written.
That is a hole rather than a scope - it is where an `ast`-shaped reader happened
to stop - and it has been paid for once already, by a containment rule spelled
twice in Zig, live in one copy and dead in a test, that walked past this gate
because no pass over `src/` exists for it to fail.

The board is where it was measured, and the last paragraph is about the
instrument rather than the fix. 30 grammars, 12 whole, `341,506 built + 63,374
orphan + 30,282 rubble + 91,636 spoil = 526,798`, 64.8% standing and 82.6%
covered, describing 97,079 nodes, 1 of 30 unsound (toml, one loose child). All
thirty round-trip mint→readback clean with zero `FolioBad*`. The instrument that
lied is `standing.py` itself, and it lied in the most expensive direction an
instrument can: it turned an artifact it could not open into a byte it said was
not there. `void` and `whole` are both legitimate rows, `spoil` absorbed the
difference without comment, and the four buckets still summed to the corpus, so
the board stayed internally consistent while being entirely wrong. It now prints
one line - `cache: kept 30`, or `re-minted 12`, or the names of the grammars it
skipped and why - under every measurement. One line is the difference between
that afternoon and a minute, and it is there because a board that reports only
its numbers reads as a board that earned them.
