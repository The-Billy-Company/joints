# Result 3 — what it costs, whole process, and the prediction it broke

`python3 research/generation/cost.py 7` — seven board runs per arm, alternating,
over one warm private cache of 30 folios (14.4 MB) and a 1.75 MB binary.

Every number here is a **whole board process** timed from outside it. No
in-process timer around the hashing loop appears anywhere in this file, because
that is the exact number that lied one lane ago: `order.accepts` documented
`55 us for json` and `~13 ms` overall for a check that really costs 2.7 ms and
136 ms, having timed the binary's internal work and left the `fork`/`exec` out.

"Before" is the old rule **restored explicitly**, not subtracted or estimated:
`tool/` is copied into a scratch tree and a printed block is appended to the
copy's `stamp.py` rebinding `fed` to the stat it used to be and `reconcile` to a
ledger of nothing. Both arms get the same scratch-tree treatment so the scratch
tree cancels; a third arm runs the real `tool/` out of the real repo in the same
alternating series to show what the scratch tree costs.

```
  before - stat, no ledger     median     829 ms   min     812   max     968
  after  - digest + reconcile  median     897 ms   min     876   max     943
  after, out of the real tree  median     852 ms   min     841   max     885
  an empty interpreter         median      25 ms   min      25   max      25

  the ledger costs +68 ms of whole process, +8.3% of a board
```

## Prediction 3 is falsified

> **Prediction:** the whole-process cost lands under **5%** of the 0.81 s
> baseline - so under ~0.85 s, with the median of five runs moving by 30-50 ms.
> *Falsifier:* the median of five after-runs exceeds 0.85 s.

+68 ms and +8.3%, and the real-tree median is 852 ms. Falsified on both halves,
narrowly on the second.

The estimate was 38 ms because it priced the hashing and nothing else. A
microbench of the two candidate implementations says the hashing itself is
about half of it — 20.3 ms for thirty binary digests, 6.8 ms for the thirty
folios, ~7 ms for the reconcile pass, so ~34 ms — and `hashlib.file_digest`
is not faster than the block loop already in `stamp.digest` (20.4 vs 20.3 ms;
sha256 is running at ~2.5 GB/s here, which is hardware). The other ~34 ms is
what the estimate had no line for: the before arm never reads a folio's bytes
into user space at all, and the after arm pulls 14.4 MB of them through the page
cache, plus 91 open/stat/Path round trips.

## Where it goes, and the lever I did not pull

| work | reads | bytes |
|---|---|---|
| folio digest at read time | 30 | 14.4 MB |
| **binary digest at read time** | **30** | **52.5 MB** |
| reconcile pass at the end | 31 | 16.1 MB |

The binary is three quarters of the bytes, because it is 1.75 MB read once per
row. The lever is obvious — memoize it on its stat key — and taking it means
saying out loud that one artifact's identity is decided by a stat, in a file
whose entire subject is that a stat is not an identity. RESULT-1 is the reason
it stays unpulled: the binary swap is the artifact change that *no* existing
detector sees, and per-row digesting is what turned that into "16 of 30 rows"
instead of "something moved". Row-level attribution of a mid-run rebuild costs
about 50 ms of an 850 ms board, and that is the trade, priced.

## The second cost, which is not time

The false-alarm rate. Prediction 3 said it depended on Prediction 1, and
Prediction 1 came back non-deterministic for **at least fourteen of thirty**
grammars, so: **any instrument re-pressing one of `cpp css elixir go haskell
javascript julia latex ocaml python scala sql swift verilog` while the board
reads it splits the board, for no reason a reader can act on.** Measured in the
control trial: two to three rows flagged out of thirty against a re-minter that
changed nothing.

The fix for that is in the press, not here. Softening the rule to "only complain
when the bytes matter" would require knowing which folio bytes are semantic,
which is `src/folio`'s knowledge and not the measurement layer's, and would be
the seventeenth instrument in this file's list rather than the answer to it.
