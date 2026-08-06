`order.miss` decided a cached folio was fresh by comparing its `st_mtime`
against the binary's. That answers *was this file made before that file*, asked
of a **path** — and a before/after pair is two binaries, both of them older than
a folio either one minted five minutes ago. So the stale check never fired and
both arms read whichever folio was written last.

Staged with two real pins sharing one `OUTLINER_WORK`: pin `tenon` mints
verilog's folio at `3ed97566244be7e3` and reads `nodes 22222`; pin `derive-only`
mints `811e808412d78cbc` and reads `22210`. Run second into the shared
directory, `derive-only` reports `cache: kept 30` and **22222** — the other
pin's number, silently, in the flattering direction, because two runs of the
same table always agree.

A folio now carries a ticket beside it, `<name>.folio.by`, holding the sha256 of
the binary that pressed it. `press` writes the ticket **before** the folio and by
the same `os.replace`, so the worst interleaving is a ticket over a folio that is
not there yet, which `miss` reads as `missing` and recomputes. `miss` compares
digests and names which of four things went wrong: `missing`, `no record of
which binary pressed it`, `another binary pressed it (<theirs>, not <ours>)`,
or `refused - <what the binary said>`.

Strictly stronger and also strictly quieter. Stronger because an mtime is
structurally blind to the two-pin case — the digest is not, and the same staging
after the change reports `re-minted - another binary pressed it` on all thirty
and zero rows differing from a private-directory run. Quieter because a rebuild
landing on the same bytes, or a bare `touch`, no longer invalidates thirty
folios that are still exactly what this binary would press.

`order.py cache` now stages *a fresher folio another pin minted* and *a folio
with no record of its minter*, and asserts the retired rule's other half — *an
older folio this same binary minted* — is **kept**, because a freshness rule
that only ever re-mints is not a cache.

Where it costs: one extra file per folio and one sha256 per press. And it
widened a teardown race in `research/generation/stage.py`, whose `race` trial
keeps a presser running while the board reads; doubling the writes into the temp
cache lets a write land after `rmtree`'s scan (`OSError: Directory not empty`).
All four of that harness's trials report correctly first — that is a cleanup
race in another lane's file, named here rather than reached into.
