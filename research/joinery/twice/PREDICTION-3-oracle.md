# Prediction 3 — is `oracle_build` a mutation, and did it write the divergence

Written before measuring, after reading `differential.oracle_build` and
`attest.verify` and nothing else. Each names the number that kills it.

## What I have already read (not predictions — inspection)

`oracle_build(lang, want)` does four things to a **shared** directory:

```python
if not src.exists() or digest(src) != digest(want):
    shutil.copyfile(want, src)                      # overwrite grammar.json
    shutil.rmtree(lang / "src" / "tree_sitter", ...) # delete the headers
    (lang / "src" / "parser.c").unlink(...)          # delete the parser
if (lang / "src" / "parser.c").exists(): return
got = cli([str(TS), "generate", "src/grammar.json"], lang)
```

`differential.py` says of that directory, in its own comment: *"What stays
shared is `lang/`, where the expensive work is … guarded by `alone()`."* So the
hazard is real by the file's own account; the question is whether the guard is
actually held on this path, and what the mutation costs.

## P1 — `oracle_build` holds no lock of its own

It will call `alone()` nowhere in its body, and at least one caller will reach
it without one. **Killed by** finding `alone()` inside it or on every path in.

## P2 — the window is not the copy, it is the gap

The dangerous interval is between `parser.c.unlink()` and `generate`
succeeding: during it the tree is a grammar with no parser, and a concurrent
reader gets a language that is *sitting right there* and cannot answer. That is
the same shape the holdout lane described as *"trees with no generated
`parser.c`"* — I predict at least some of those are not un-generated trees but
**tornoff ones, mid-rebuild**, and that the state is reachable without any
crash, purely by two lanes overlapping. **Killed by** the unlink+generate being
atomic (a temp dir and a rename), or by no caller being able to hand a
different `want`.

## P3 — steady state is a no-op, so the ping-pong needs two different `want`

Handed the same bytes twice, the digest compare short-circuits and nothing is
written. So a mutation storm requires two arms holding **different
`grammar.json` for one language name**. I predict corpus
(`upstream/grammars/<n>.json`) and holdout (`holdout/vendor/grammars/<n>.json`)
are exactly such a pair, and that the overlap between those two name sets is
**empty by design** — the holdout is a held-out set. If the overlap is empty,
the ping-pong between *those two* arms cannot happen and the divergence needs a
third source. **Killed by** a non-empty overlap (which would make this much
worse than I think) or by the two arms sharing one `lang/` root anyway.

## P4 — `oracle_build` did NOT manufacture the 62.3%

`attest.verify` compares `.dylib` files:

```python
libs = [f for s in seats for x in (".dylib", ".so") if (f := s/"lib"/(name+x)).is_file()]
a, b = libs[0].read_bytes(), libs[-1].read_bytes()
```

That is a **compiled-library** population, not a source-tree population.
`oracle_build` never writes a `.dylib`. So the 62.3% is not our footprint in the
sense asked; it is two builds of css's parser at different times. **Killed by**
`verify` turning out to digest sources, or by the two css libraries being
byte-identical when re-measured.

## P5 — the 62.3% is css's `scanner.c`, and it changed today

`ls` already shows `lang/css/src/scanner.c` at **Aug 5 17:37**, `grammar.json`
at Aug 4 09:02, the root `lib/css.dylib` at **Aug 4 09:39**, and every seat's
css library after 18:22 today. I predict the root library is a pre-17:37 build
and the seat libraries are post-17:37, so the two arms `verify` compares are a
real parser change — **in the scanner, which `oracle_build` does not touch at
all**. **Killed by** the root library rebuilding to the seat library's bytes, or
by scanner.c not being in the compiled output's difference.

## P6 — my "the sources are byte-identical" was true of one file and false of the tree

I compared `upstream/grammars/*.json` against
`.local/differential/lang/*/src/grammar.json` and generalised from the grammar
to the sources. `scanner.c` is in `attest.survey`'s digest and was not in my
comparison. I predict my statement is **wrong as written and right about the
population I checked**, and that at least one grammar's `src/` digest has moved
today. **Killed by** every `src/` digest being unchanged since yesterday.

## P7 — the guard catches the scanner change

`attest.survey` digests everything under `src/`, so a verdict written before
17:37 and read after carries a different oracle digest and prints `other`.
I predict an audit cache written pre-17:37 exists or can be honestly staged from
the real pre-change bytes, and that the board refuses css off it. **Killed by**
the board reading such a verdict as `read`.

## P8 — the shape has a name and it is gateable

Three instruments now: `specimen.py`'s defaulted stop line, `order.py::miss`'s
mtime key, `plumb`'s fork comparison via `oracle_build`. I predict the common
shape is **the comparison's setup writes to the thing being compared** — a
normalising step inside the measurement path — and that it is detectable
generically: *a read verb must not write to a shared input*. I predict I can
gate it for the oracle tree specifically without needing to change anyone's
verb. **Killed by** the three not actually sharing that shape, or by no gate
being expressible without editing another lane's file.
