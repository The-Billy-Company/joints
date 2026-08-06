# Result 2 — nobody has two oracles; three instruments wrote the copies that looked like it

Predictions in [`PREDICTION-3-oracle.md`](PREDICTION-3-oracle.md), written after
reading `oracle_build` and `attest.verify` and before measuring anything. Scored
at the bottom.

## The reconciliation, with paths

Three numbers were in the air and all three are about **different populations**.
None of them contradicts another.

| who | population | measured |
|---|---|---|
| me | `upstream/grammars/*.json` vs `.local/differential/lang/*/src/grammar.json` | byte-identical |
| `attest.verify` | compiled `.dylib` across `seat/*/lib/` **and** the legacy `lib/` | 28 of 29 have ≥2 distinct files; css 62.3% apart |
| holdout lane | oracle *source trees* under every `…/lang/<name>/` | 14 of 27 corpus rows have ≥2 |

I looked at one file and said "the sources". That was too small a population and
it happened to be the right answer. Measured properly — **159 source trees, 30
grammars, every file under each `src/`**:

```
grammars with >1 source tree : 30   (trees surveyed: 159)
  disagreeing under attest.survey     : 2   css (8 copies) · toml (7 copies)
  still disagreeing on AUTHORED bytes : 0
```

**Not one grammar on this machine has two different authored oracle sources.**
Every `grammar.json`, every `scanner.c`, every companion header is singular
across all 159 trees. css's eight `grammar.json` copies are one digest
(`1a170e0c9300`); its eight `scanner.c` copies are one digest (`18dae8c8c4f5`).

So the "several different copies" is real as bytes and empty as parsers, and it
comes from exactly two things, one per population.

## Population one — the 62.3% library, and it is inert

`attest.verify` builds its list as `[every seat] + [WORK]` and compares
`libs[0]` against `libs[-1]`, so it compares **one current seat against
`.local/differential/lib/`** — the *pre-seat* library directory, last written
2026-08-04 09:39, before `TREE_SITTER_LIBDIR` was moved per-lane. Nothing writes
there any more.

Nineteen css libraries exist, all 151,080 bytes, **all nineteen distinct**:

| pair | differing bytes | |
|---|---|---|
| seat `twice` vs seat `twice2` | 61 / 151,080 (0.0%) | Mach-O UUID + build id in two 4 K windows |
| seat `twice` vs the legacy `lib/` | 94,071 / 151,080 (62.3%) | uniform across every window |

Uniform 62.3% is not a build id. But it is also not an oracle, and this is the
measurement that settles it — I planted that exact orphan
(`05ec353b4c86`) as a scratch seat's library and asked it one question:

```
planted relic 05ec353b4c86 -> after one parse a01e997efe11   rebuilt=True
rebuilt relic vs seat twice: 53/151080 bytes differ (0.0351%) — same length
```

**It was rebuilt before it could answer**, and what came back is the same parser
every seat has, 53 bytes of build id apart. The CLI's own staleness criterion —
a library older than the sources beside it, `attest`'s own fourth claim — fires
first, every time. So the divergent copy cannot have produced a number, cannot
be selected, and its provenance does not matter.

That is a correction to a reading, not to a measurement. `attest.verify`'s third
row says the tree *"really is holding two oracles at once."* It is holding one
oracle and one file that gets overwritten by the first question anyone asks it.

## Population two — the divergent source trees, and we wrote them

The two grammars whose `src/` digests disagree, css and toml, **agree the moment
generated files leave the comparison**. `parser.c` and `tree_sitter/*.h` are the
output of `tree-sitter generate src/grammar.json`; they carry no information the
digest does not already hold via the grammar and the CLI version. The only
difference between css's two identities is that one tree has a `parser.c` and
the other does not:

```
.local/differential/lang/css   6a77f0ca8967  files=6  (no parser.c)
.local/attest/frame/lang/css   f8550686ee89  files=7  (with parser.c)
```

**And the deletion was ours.** `differential.fetch_scanners` wrote every
scanner with `write_bytes` unconditionally and then unlinked the `parser.c`
beside it *to force a relink*. css's `scanner.c` is dated 2026-08-05 17:37 and is
byte-identical to every other copy on the machine — a `cp` of a file onto its own
bytes, followed by the deletion of a generated artifact that is inside the
identity. `beside()` did the same to companion headers without the unlink, which
moves only the mtime — and the mtime is what `attest.stale` reads, so an
unconditional refresh reports every oracle on the machine as about to change
parsers.

Before, every run: **28 of 28 `wrote`**, 11 of them unlinking a parser. After:

```
28 same
```

## The measurement changed the thing it measured

The sharpest way to see it. Two real fork trees another lane left on disk, with
two genuinely different `attest` identities, audited one after the other:

```
6a77f0ca8   oracle=f8550686ee89  parser.c=True  built=6138 square=6138 racked=0 their_nodes=794
f8550686e   oracle=f8550686ee89  parser.c=True  built=6138 square=6138 racked=0 their_nodes=794

two different oracle IDENTITIES:  f8550686e vs f8550686e
all 14 measured columns:          IDENTICAL
```

Read the first column twice. The fork *named* `6a77f0ca8` surveyed as
`f8550686e` — measuring it regenerated its `parser.c`, and its identity
converged onto the other's. The two oracles became one because I asked them a
question. Both populations tell the same story: **the divergent copy does not
survive being used.**

## So: is `oracle_build` safe concurrently? No, and it is now

`oracle_build` overwrites `lang/<name>/src/grammar.json`, deletes
`src/tree_sitter/`, deletes `parser.c`, and runs `generate` — in the directory
`differential.py`'s own comment calls *"shared, and locked"*. It held no lock.
The lock was the caller's job, and of **twelve call sites, nine did it**:
`recover.py` (three), `research/joinery/adjudicate/prepare`, and this file's own
`graft_fields` did not.

Raced deliberately — two processes, one language, different grammar bytes, six
rounds each, with the lock stood down:

```
5   B grammar=B parser=B ok
3   A grammar=B parser=B ok      ← lane A measured lane B's grammar and called it its own
3   A grammar=A parser=A ok
1   B grammar=A parser=B TORN    ← a grammar.json from A beside a parser.c from B
```

The `TORN` row is the loud failure. **The three flattering rows are the real
defect**: internally consistent, silent, and about somebody else's grammar. With
the lock inside the function:

```
6   B grammar=B parser=B ok
6   A grammar=A parser=A ok
1     waiting on json: another lane is building it
```

Twelve of twelve, one queue. `alone()` is re-entrant within a process now, so
the nine callers that already hold it are unchanged; `flock` is per open file
description, so a nested acquire on a fresh fd would otherwise wait on a lock
the same process holds. A *writer* nested inside a *reader* refuses instead —
that one is a real lock-order fault and the readers-writer split exists to stop
it:

```
json: a build inside a measurement - take alone('json', writing=True) before the read, never inside it
```

## Naming the shape, because it is four instruments now

`specimen.py`'s defaulted stop line · `order.py::miss`'s mtime key ·
`fetch_scanners`' unconditional write · `oracle_build`'s unlocked mutation. The
common shape is not "a bug in setup". It is:

> **The comparison's setup writes to the thing being compared.**

And the corollary that makes it dangerous rather than merely wrong: *after the
setup runs, the two arms are more alike than they were*, so the error is
**always** in the direction of agreement, and the instrument's own check passes
because both arms now say the same thing. A falsifier cannot catch it, because
the falsifier runs after the setup.

Two of the four also share a subtler property worth separating out: they encode
**a fact about when, standing in for a fact about what**. `miss` asked an mtime
which binary made a folio; `attest.survey` asks whether a generated file is
present, which answers *how recently did anyone measure this*, not *which parser
is this*. That is why the identity is not stable under observation.

The gate I can express without editing another lane's verb is the one already
in `order.py cache`: **stage the shared input, run the read verb, assert the
input did not move.** `scanners` printing `same` on all 28 is that assertion
made visible on every run — a `wrote` where nothing changed is now a bug you can
see from the terminal.

## What the divergence did to numbers already taken: nothing

Dropped as instructed, and the reason is measured rather than assumed. The
divergent library rebuilds before it can answer (53 bytes from its seat's own);
the divergent source tree regenerates and converges on first use (14 of 14
columns identical, 794 oracle nodes each). No css or toml number on this board
was taken against a second parser, because there has never been a second parser
— only copies that could not answer.

## What I recommend to `attest`'s owner, and did not do myself

**Take `parser.c` and `tree_sitter/*.h` out of `survey`'s digest and leave them
in its mtime.** They are outputs of `tree-sitter generate` over inputs the digest
already covers, so they add no identity and subtract stability: their presence is
a cache state that any measurement creates and any scanner refresh used to
destroy. Measured, that change collapses css's and toml's two identities to one
and leaves the other 28 grammars bit-for-bit unchanged. The mtime side should
keep them, because *"is the library older than what it was built from"* is a
different question and wants the whole tree.

I did not make that change — `tool/attest.py` is another lane's. My board keeps
keying on `attest`'s digest exactly as it is, because a second definition of
"which oracle" is how this project got 9,087 and 1,938 both called *crooked*.
The guard's failure direction is safe: it refuses a valid verdict and costs a
re-audit, rather than accepting an invalid one. And the window that made it fire
was `scanners` deleting a `parser.c` between an audit and a read — which is
closed.

`attest.verify`'s third row should also stop saying *"the tree really is holding
two oracles at once."* On the evidence here it is holding one, and a file that
gets rebuilt by the first question. The number is right; the sentence is the
sort of claim this project retracts.

## The predictions, scored

| | claim | |
|---|---|---|
| **P1** | `oracle_build` holds no lock; ≥1 caller reaches it without one | **held** — none, and 3 of 12 |
| **P2** | the window is the gap between `unlink` and `generate`, reachable without a crash | **held** — 1 torn observation in 12, plus 3 silent-wrong |
| **P3** | steady state is a no-op, so a storm needs two different `want` | **held**, and the corpus/holdout name sets do not overlap |
| **P4** | `oracle_build` did **not** write the 62.3% | **held** — that population is `.dylib`, which it never touches |
| **P5** | the 62.3% is css's `scanner.c` changing today | **falsified** — every `scanner.c` on the machine is one digest; the 17:37 mtime is a `cp` onto its own bytes |
| **P6** | my "byte-identical sources" was right about the file, wrong about the tree | **half held** — right about the file, and right about the tree too once measured: 0 of 30 authored trees diverge |
| **P7** | the guard catches a real source change | **not tested — no such change exists here** |
| **P8** | the shape is nameable and gateable | **held** — see above |

**P5 is the interesting failure.** I predicted a real scanner edit and went
looking for the diff. There is no diff: 8 copies, one digest, and a mtime moved
by an instrument rewriting a file with its own contents. I had the right suspect
— something wrote to css at 17:37 — and the wrong crime. The correct one is
worse and duller: nobody changed the parser, an instrument just made it look
like somebody had.

**P7 is the one that stays open**, and it is the same gap I named at the end of
[RESULT-1](RESULT-1-board.md). I now know *why* there is no genuinely different
oracle to test against, which is more than I knew before — the sources are pinned
by digest in `grammars.toml` and every copy on the machine derives from those
pins — but knowing the reason is not the same as having watched the guard catch
one. It remains the instrument I trust least, for the same reason and with
better evidence.

## Reproducing

```sh
python3 tool/differential.py scanners        # 28 same, 0 wrote — was 28 wrote every run
OUTLINER_LANE=probe python3 tool/attest.py verify
```
