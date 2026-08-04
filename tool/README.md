# tool - the three scripts a clone needs

Python, stdlib only, `python3`. Nothing here is built or imported by the
package; these exist so a fresh clone can get to the same numbers this
repository's dossier quotes. Both follow the CLI's exit-code family: **0** ran,
**1** a clean negative answer, **2** an error.

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
python3 tool/differential.py oracle           # is the CLI here, and which version
```

`--grammar=NAME` for every case on one grammar, `--json` on the read verbs, and
`--verbose` for every finding rather than the first few per case. `run` exits 1
when a difference is left that nobody owns, and 0 when every difference found is
one of the known gaps.

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
