# Prediction 1 — generated files out of the oracle's identity

Written before measuring anything. The recommendation is
[`twice/RESULT-2`](../twice/RESULT-2-oracle.md#what-i-recommend-to-attests-owner-and-did-not-do-myself)'s,
made by a lane that could not make it because `tool/attest.py` was not its file.
It is my file, so the predictions below are mine and so is the score.

## What I have read, and what I have not measured

I have read `attest.survey`, `differential.oracle_home`, and the twice dossier.
I have listed the files under five `lang/<name>/` trees and counted the trees on
this machine. I have run no instrument and taken no digest. Everything below is
a claim about what will happen when I do.

`survey(home)` walks `home/"src"`, hashes `(relpath, bytes)` for every file, and
carries the newest mtime beside the digest. Under `src/` today live, per
grammar:

| authored | generated |
|---|---|
| `grammar.json` (copied in from the pin) · `scanner.c` where there is one | `parser.c` · `node-types.json` · `tree_sitter/{parser,alloc,array}.h` |

Both halves are in the digest. The recommendation is that the second half
belongs in the mtime only.

## P1 — the split collapses, and it collapses to *one*

Today 28 of 30 grammars are one identity across every tree on the machine and
two — css and toml — are two, entirely because one copy has a `parser.c` and
another does not.

**Predicted:** with generated files out of the digest, **30 of 30** grammars
are a single identity across all trees on this machine, and the two that
disagreed stop disagreeing. Every grammar's digest *value* changes, since the
input set changed; that is not a finding, it is arithmetic, and the thing to
check is single-identity rather than a stable number.

**Kills it:** a grammar still holding two identities after the change. That
would mean the divergence was never only generated files and the twice lane's
`0 authored divergent bytes` was measured over too small a population — twice.

## P2 — it still refuses a genuinely different authored source

This is [`twice`'s P7](../twice/RESULT-2-oracle.md#the-predictions-scored), the
one that stayed open because there is no genuinely different oracle on this
machine to test against. There is no need to wait for one: a scratch tree can
hold a real edit.

**Predicted:** one byte flipped in a scratch `scanner.c` moves the digest; one
byte flipped in a scratch `grammar.json` moves the digest; a file *added* under
`src/` moves it and a file removed moves it. Four directions, because a digest
that catches an edit and not a deletion is not a digest of a tree.

**Kills it:** any of the four coming back with the same digest.

## P3 — it stops calling a rebuilt artifact a different parser

**Predicted:** delete `parser.c` and `src/tree_sitter/`, re-run `tree-sitter
generate`, and the digest is **identical across the deletion and the rebuild** —
including at the moment in between, when the generated files are absent
altogether. That third state is the one that matters: it is the state
`fetch_scanners` used to leave the tree in, and the reason css had two
identities.

The mtime must move across all three, because *"is the compiled library older
than what it was built from"* is a different question and a rebuilt `parser.c`
is a real answer to it.

**Kills it:** a digest that moves across a regenerate, or an mtime that does
not.

## P4 — there is an authored file `survey` never looks at, and it is the wrong direction

`survey` digests `home/"src"`. `oracle_home` reproduces each monorepo pin's own
repository depth, so ocaml, php and typescript are handed `lang/<name>/<deep>/`
and their shared `common/scanner.h` sits **above** that at `lang/<name>/common/`.
A `find` says those three grammars are the only ones with a file outside `src/`.

**Predicted:** editing php's `common/scanner.h` today changes **no** attest
identity — the authored C that php's whole external scanner consists of is
outside the digest that exists to identify it. If that holds, narrowing the
digest to authored bytes without widening its reach would leave three grammars
whose real scanner is unattested, which fails the second half of P2 for exactly
the grammars where an external scanner is the interesting part.

**Kills it:** the edit moving the digest, meaning `survey` reaches further than
I think it does.

## P5 — `verify`'s third row is a sentence this project retracts

The twice lane says so and I agree before measuring: `attest.verify` prints
*"the tree really is holding two oracles at once"* on the strength of a 62.3%
byte difference against `.local/differential/lib/`, a pre-seat directory nothing
has written since Aug 4, whose contents get rebuilt by the first question anyone
asks them.

**Predicted:** the number stays true and the sentence has to go, and the row
should say which population it is about. I also predict the *first* row —
`N of 30 grammars exist as several different files at once` — keeps holding,
because it is about `.dylib` files, which no change to `survey` touches. If
`verify` goes green-by-getting-quieter after my change, I have moved a claim
instead of fixing an instrument.

**Kills it:** any row of `verify` passing after the change *because* it is
measuring less.
