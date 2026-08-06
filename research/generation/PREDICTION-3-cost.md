# Prediction 3 — what it costs, with the process included

This file exists because the flattery it guards against was already committed
in this exact file, one lane ago: `order.accepts` documented `55 us for json`
and `~13 ms` overall for a check that really costs **2.7 ms** and **136 ms**,
because it timed the binary's internal work and left the `fork`/`exec` out. A
tenfold flattering number, sitting inside the fix for flattering numbers.

So the measurement here is **`/usr/bin/time -p python3 tool/standing.py`**, the
whole process, before and after, and nothing smaller is reported as the cost.
An in-process timer around the hashing loop is exactly the number that lied.

## The shape of the work added

Per board run over thirty grammars, against a 14.4 MB folio cache and a 1.75 MB
binary:

- one sha256 of the folio at each read - 30 reads;
- one sha256 of the binary at each read - 30 reads, no memo, because a stat
  deciding whether to re-read the bytes is the mtime rule sneaking back in
  through the side door;
- one reconcile pass at the end - 31 digests.

In-process that is ~6.5 ms per pass over the cache (measured: 2,221 MB/s) and
~0.96 ms per binary digest, so ~38 ms of hashing.

**Prediction:** the whole-process cost lands under **5%** of the 0.81 s
baseline - so under ~0.85 s, with the median of five runs moving by 30-50 ms.

*Falsifier:* the median of five after-runs exceeds 0.85 s.

If it does exceed it, the memo on the binary's stat key is the lever, and taking
it means saying out loud that one artifact's identity is decided by a stat.

## The second cost, which is not time

A reconciliation that fires on a tree ten agents rebuild continuously has a
false-alarm budget too. If Prediction 1 says minting is deterministic, the
expected rate is low, because the common event (an instrument re-minting a cache
another instrument is reading) produces identical bytes. If minting is
nondeterministic, every overlapping instrument run flags the board, and the
right answer would then be to fix minting rather than to soften the rule.
