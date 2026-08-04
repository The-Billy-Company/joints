# Contributing

Most of this is not built yet. There is no parser: what exists is the press (a
tree-sitter `grammar.json` importer that reaches zero residual conflicts on
eleven real grammars), the stack-effect monoid and the cursor that composes it,
a terminal scanner, a single-stack reference walk to check the algebra against,
and the CLI that measures all of it. The tree, repair, the quotient, the folio
and `libotl` are ahead. So the useful contributions right now are the ones that
make a measurement sharper or a claim harder to hold, and the fastest way to
know whether you have one is to reproduce rung 1 yourself.

## Get to a green test run

Two prerequisites, and neither is a download you have to remember: **Zig
0.16.0** (the `minimum_zig_version` in `build.zig.zon`) and a checkout of
[irregex](https://github.com/The-Billy-Company/irregex) as a *sibling
directory*, because `build.zig.zon` resolves it as `../irregex` while the two
halves of the lexer conversation are still moving together.

```sh
git clone https://github.com/The-Billy-Company/irregex
git clone https://github.com/The-Billy-Company/outliner
cd outliner
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
zig-out/bin/outliner joints upstream/grammars/json.json research/joinery/corpus/ledger.json
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

`joints` exits 1 whenever anything refused, so nine grammars out of eleven
"fail" on their own today. Read what a run says, not what it returns.

## House rules that will come up in review

- **Node kind names are byte-identical to tree-sitter's.** Every
  `highlights.scm` in the world is keyed on them and that compatibility is the
  entire point, so never invent, prettify or re-case one. If a name you need is
  not in the imported grammar, that is a bug to report, not a name to synthesize.
- **outliner never links tree-sitter and never shells its runtime.** Its CLI may
  appear in a comparison harness, and any such call skips when the CLI is
  absent: a missing baseline tool skips a test, it never fails one.
- **A number is not a result until it is timed against bytes**, and you have to
  price both halves of the exchange. An `O(log n)` splice that allocates is not
  automatically better than an `O(n)` walk that does not.
- **Files stay under 500 lines**, and a new leaf folder gets a `README.md`.
- **Comments say why this shape and what breaks otherwise**, ideally naming the
  case that forced it. Not what the next line does, and never a line count.
- **Run `zig fmt` on what you touched**, and add a corpus file only by the rule
  in [`research/joinery/corpus/README.md`](research/joinery/corpus/README.md):
  the same little ledger program again, in one more language, and nothing else.

## What CI will run

[`.github/workflows/ci.yml`](.github/workflows/ci.yml), on Linux and macOS, in
that order for a reason: `zig build check`, `zig build test`, `zig build`, *then*
the grammar fetch and its hash check, then the rung-1 sweep as a gate. The
network comes last because only the sweep needs it, so a press regression is
never downstream of somebody else's repository being reachable. A second job
checks the pins on a bare checkout with no toolchain at all. No credentials, no
GPU, no tree-sitter.

Apache-2.0, same as the rest of the family. By opening a pull request you are
licensing your change under it.
