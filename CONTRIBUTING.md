# Contributing

There is a parser, and this paragraph spent a long time saying there wasn't.
What exists: the press (a tree-sitter `grammar.json` importer that reaches zero
residual conflicts on eleven real grammars), the stack-effect monoid and the
cursor that composes it, a terminal scanner, a single-stack reference walk to
check the algebra against, a GLR parse loop in [`src/kernel/quire/`](src/kernel/quire)
that hands back a forest and mends past what it cannot read, the folio those
tables ship as, the CLI that measures all of it, and `libjnt`, the C ABI. The
quotient is still ahead.

How much of that works is deliberately not written here. It moves most days, and
a count pasted into a page is a count that ages into a lie - which is the same
argument the rest of this file makes about pins and stamps, so it would be an odd
place to make an exception. `python3 tool/standing.py` is the board, and it
answers coverage, structure and agreement as three separate questions. The useful
contributions are still the ones that make a measurement sharper or a claim
harder to hold, and the fastest way to know whether you have one is to reproduce
rung 1 yourself.

## Get to a green test run

Two prerequisites, and neither is a download you have to remember: **Zig
0.16.0** (the `minimum_zig_version` in `build.zig.zon`) and a checkout of
[irregex](https://github.com/The-Billy-Company/irregex) as a *sibling
directory*, because `build.zig.zon` resolves it as `../irregex` while the two
halves of the lexer conversation are still moving together.

```sh
git clone https://github.com/The-Billy-Company/irregex
git clone https://github.com/The-Billy-Company/joints
cd joints
zig build check     # compile, install nothing - the fastest red
zig build test
```

That is all of it. The test suite carries the one grammar it needs, committed at
[`test/grammar/json.json`](test/grammar/json.json), because `build.zig` embeds it
and a build graph that reads a gitignored path cannot be resolved from a clean
checkout at all.

## Reproduce a rung-1 number

This is the step that needs the grammars, and the only one. Eleven tree-sitter
grammars are pinned in [`grammars.toml`](grammars.toml) - a repo, a commit, a
path and the sha256 of the exact bytes - rather than committed, because
`upstream/` holds clones kept for study rather than sources this package
vendors:

```sh
python3 tool/grammars.py fetch     # ~3 s, eleven files, ~2.3 MB
python3 tool/grammars.py verify    # offline; hashes disk against grammars.toml
zig build                          # the installed ReleaseFast binary the sweep runs
```

`verify` also proves the committed fixture still holds the bytes its pin claims,
which is worth knowing because wrong bytes in that file would compile and pass.
[`tool/README.md`](tool/README.md) has the rest of the verbs.

Rung 1 is the falsifier for the whole design, and it needs no parser. One
grammar, one file, one line per segmentation:

```sh
zig-out/bin/joints survey upstream/grammars/json.json research/joinery/corpus/ledger.json
```

That should end with `worst p99 rank 42 · widest residue 2 · 8/8 chains held`,
which is json's row in [`research/joinery/TESTING.md`](research/joinery/TESTING.md).
The whole sweep, and the gate CI runs, is:

```sh
python3 tool/rung1.py    # ~13 s over all eleven
```

It fails if a grammar keeps a residual conflict, if any chain disagrees, or if
the residue gets past two. It does *not* fail on refusals - thirty of those are
documented and owned, and they are the lexer and the fork rather than the
monoid.

`survey` exits 1 whenever anything refused, so nine grammars out of eleven
"fail" on their own today. Read what a run says, not what it returns.

## Measure against a pinned binary, never against a path

Everyone builds into the same `zig-out`, so a before/after comparison that
names `zig-out/bin/joints` is naming *whatever is there when each half runs*.
That is not a hypothetical. One lane's reference arm was silently rebuilt
mid-measurement with that lane's own fix in it, turning the "before" binary
into an "after" binary and producing a clean thirty-of-thirty for entirely the
wrong reason. **In this tree, a path is not a version.**

`zig build -p <dir>` installs somewhere else and has always been there, but a
private prefix is still only a path: a week later nothing on disk says what it
was built from. So build a *pin*, which is a prefix plus a record of the tree
that produced it:

```sh
python3 tool/pin.py build --name before    # zig build -p .local/pin/before, and write down the tree
# … land your change …
python3 tool/pin.py build --name after
JOINTS_BIN=$(python3 tool/pin.py path before) python3 research/press/wobble.py --reps 6
python3 tool/pin.py verify                 # do both pins still hold the bytes they recorded?
```

Every instrument here reads `JOINTS_BIN`, and `tool/stamp.py` reads the pin's
record, so a run against a pin whose tree has since moved prints `DRIFT` and
says which file moved. Without the record it cannot: `stamp` otherwise infers
the source tree by walking up from the binary looking for a `build.zig`, finds
none above a private prefix, falls back to the live repo and compares it
against itself — so the binary you pinned *because* you expected the tree to
move underneath it was the one binary that could never report that it had.
`pin.py list` is the inventory; `pin.py show <name>` is one pin against the
tree as it stands now.

## House rules that will come up in review

- **Node kind names are byte-identical to tree-sitter's.** Every
  `highlights.scm` in the world is keyed on them and that compatibility is the
  entire point, so never invent, prettify or re-case one. If a name you need is
  not in the imported grammar, that is a bug to report, not a name to synthesize.
- **joints never links tree-sitter and never shells its runtime.** Its CLI may
  appear in a comparison harness, and any such call skips when the CLI is
  absent: a missing baseline tool skips a test, it never fails one.
- **A number is not a result until it is timed against bytes**, and you have to
  price both halves of the exchange. An `O(log n)` splice that allocates is not
  automatically better than an `O(n)` walk that does not.
- **A path is not a version.** Ten lanes share one `zig-out`; a comparison arm
  spelled as a path is whatever a sibling last installed there. Pin it — see
  the section above — and say which pin a number came from.
- **A number written into a page names the tree it is true of.** This is a
  gate, not an aspiration: CI's `record` job refuses a page you changed that
  reports a measured figure and names no tree or binary. Four boards published
  in one morning here disagreed by ~1,900 bytes with all four correct about
  different trees, so a figure with no world attached is not a small omission.
  The remedy is one command and one paste, and the refusal prints it for you:

  ```sh
  python3 tool/standing.py --cite            # 188 ms, one markdown line
  # joints `a525dc9b8` · tree `3d0d2e481` (live) · **no oracle** — joints's own words

  # or, when the figure came off a board you saved, so the two cannot drift:
  python3 tool/standing.py --cite=board.json --quote=built
  ```

  What is checked is that a stamp is *present*, never that it is that figure's
  own — binding those needs a re-press at ~30 s a page, which
  [`RESULT-11-quotation.md`](research/joinery/consort/RESULT-11-quotation.md)
  argues is unreachable. It is a floor, and it is the floor the record did not
  have. Only pages your diff touches are asked; the ratchet's pin lives at
  `research/joinery/consort/sighting.since`, is committed, and moves only by
  `sighting.py --pin <ref> --because "..."`, which prints what the move clears
  before it writes it. Run it yourself with `python3
  research/joinery/consort/sighting.py --gate`.
- **A binary's `sha256` is not an oracle for behaviour**, for the same reason a
  folio's is not an oracle for a press. Two builds differing only in comment
  lines come out the same size with different digests, because added lines move
  the DWARF line program and a digest cannot tell a shifted line table from a
  shifted instruction. If the claim is "this change moves nothing", compare the
  thing you actually care about — board cells, sections by name, a parse — and
  never a whole-file hash of either artifact.
- **A test about uninitialized memory must not build its fixture with
  `@memcpy`.** A copy carries the *source's* bytes, so copying from a
  `.rodata` literal lays that literal's zeros over your poison and the slack you
  meant to exercise is never read — the test then passes against the *unfixed*
  code, which is worse than having no test. Assign field by field, the way the
  production writer does, and open the test by asserting the two fixtures really
  do differ byte-wise before asserting they compare equal. Both halves of this
  were learned the hard way in `irregex`'s `intern.zig` and `dag_test.zig`.
- **Never spell a harness's control arm as an empty environment variable.**
  `JOINTS_X= cmd` sets `JOINTS_X` to `""`, and `getenv` answers that with a
  pointer to an empty string rather than null - so a gate written as
  `getenv(name) != null` reads the *control* arm as on and runs the treatment in
  both. The board that measured the composite-literal fix did this and printed
  nine go repros accepted under a baseline that refuses six of them, which is a
  confidently wrong report rather than an error, and the arms agreeing is what
  it looks like. Either unset the variable in the control arm, or test the first
  byte: `got != null and got.?[0] != 0`.
- **A new `*_test.zig` has to be named in [`src/proof.zig`](src/proof.zig)**, and
  no production file may name one. `zig build test` reaches a test only if
  something imports it, and while that something was production code the arrow
  `press/press.zig -> press/carry_test.zig -> folio` made five directories one
  indivisible zone over a cycle that was never in the program. The test build has
  its own root now, so the list is hand-written — which means a file nobody added
  to it compiles into nothing and takes its assertions with it, and a suite that
  quietly shrank is indistinguishable from a green one. `python3 tool/roll.py`
  refuses both halves, and CI runs it beside `zoning verify`.
- **Files stay under 500 lines**, and a new leaf folder gets a `README.md`.
- **Comments say why this shape and what breaks otherwise**, ideally naming the
  case that forced it. Not what the next line does, and never a line count.
- **Run `zig fmt` on what you touched**, and add a corpus file only by the rule
  in [`research/joinery/corpus/README.md`](research/joinery/corpus/README.md):
  the same little ledger program again, in one more language, and nothing else.

## Releasing

Not yet - this package has no `release.yml`, no release-please, and no
registry it publishes to, deliberately: parts of the design (gloss, vellum,
the quotient) are still ahead, and wiring release automation onto a `0.0.0`
package would document a promise the code doesn't keep. When it does ship
something worth versioning, it graduates onto the shared model every other
Billy-Company OSS package follows - see
[RELEASING.md](https://github.com/The-Billy-Company/.github/blob/main/RELEASING.md).

## What CI will run

[`.github/workflows/ci.yml`](.github/workflows/ci.yml), on Linux and macOS, in
that order for a reason: `zig build check`, `zig build test`, `zig build`, *then*
the grammar fetch and its hash check, then the rung-1 sweep as a gate. The
network comes last because only the sweep needs it, so a press regression is
never downstream of somebody else's repository being reachable. A second job
checks the pins on a bare checkout with no toolchain at all. A third checks the
import topology against `charter.zone`. A fourth, `record`, asks
whether the pages you changed still say which tree their numbers are true of —
it is the only job that clones with history, because a forward ratchet needs a
diff. No credentials, no GPU, no tree-sitter.

Apache-2.0, same as the rest of the family. By opening a pull request you are
licensing your change under it.
