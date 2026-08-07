# Prediction 1 — what "identity" has to mean

Before picking a mechanism, decide what a generation *is*. Three candidates,
and the choice between them is not cosmetic - it decides whether the new rule
is quieter than the old one or merely louder.

| candidate | answers | fails at |
|---|---|---|
| mtime | *when* was this last written | says a file changed when identical bytes were republished; says nothing about *what* is in it |
| the folio's schema signet | which press-side struct shape wrote it | two generations minted a second apart by two different builds share it |
| sha256 of the bytes | *what* was read | costs a pass over the bytes |

The cache's existing rule (`order.miss`) compares the folio's mtime against the
binary's, and that rule has now failed twice: it could not see a schema change
(a folio the binary refuses is *fresher* than the binary refusing it), and it
cannot see a generation change at all, because it is a decision made at open
time rather than a record of what was read.

**Prediction:** minting is deterministic - the same binary pressing the same
`grammar.json` twice produces byte-identical folios.

*Falsifier:* sha256 of two consecutive `mint` runs over one grammar differ.
Run it over all thirty, not one, and over two orderings, because a folio that
carries an interned table built from a hash map could be stable for small
grammars and unstable for large ones.

## Why the answer changes the design

If minting **is** deterministic, then a re-mint by an unchanged binary is *not*
a generation change, and a content hash is strictly better than an mtime in
both directions at once: it stays **silent** through a no-op republish (which an
mtime rule would scream at, and a channel that screams is a channel people learn
to scroll past - the `stale` warning already had to exclude `*_test.zig` for
exactly this reason) and it **fires** on a real one. That is the argument, and
it needs the measurement to be made.

If minting is **not** deterministic, then every re-mint is a new generation by
this definition, the reconciliation will be noisy in a tree ten agents rebuild,
and I will have to say so and price it rather than call the noise a finding.

## What I predict about the binary

The binary is an artifact the measurement reads too - every row is an exec of
it. Today `stamp.take()` digests it **once, at the start of the run**, and
nothing looks again.

**Prediction:** a binary replaced mid-run with unchanged sources produces *no*
warning from today's stamp. `STALE` compares source mtimes against the binary
captured at `take`; `DRIFT` compares two source digests; `MOVED` re-surveys the
repo's sources. None of the three re-reads the binary, so a `zig build` that
changes only the compiler's output - or any lane installing a binary built
elsewhere - is invisible.

*Falsifier:* swap `zig-out/bin/joints` mid-run without touching `src/` and see
any of TOLD / STALE / DRIFT / MOVED / FED fire.
