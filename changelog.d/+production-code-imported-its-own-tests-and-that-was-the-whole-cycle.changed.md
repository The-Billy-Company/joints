`zig build test` reaches a test only if something imports it, and the only
importer on offer was production code: each area's module root named its own
`*_test.zig`. Those tests then read downstream, because a parser generator is
only worth testing against what it generates for - so `folio -> press/press.zig
-> press/carry_test.zig -> folio` was a real cycle in the import graph, and
`charter.zone` paid for it with a 15-file `variance cycle` that held five
directories in one undifferentiated zone.

The test build has its own root now. `src/proof.zig` names every module and every
`*_test.zig`; no production file names a test. The variance is deleted rather
than deferred, and the zone stack it was flattening is real: 11 zones with
`press` at the floor, so a file under `press/` can no longer quietly start
reading `folio`. Four single-edge variances remain, all of them one direction out
of two integration tests that live beside the code they check.

Named tests before and after: 394 and 394. The suite's count moves 404 -> 403,
which is three empty aggregation blocks removed against two added, and no
assertion either way. `tool/roll.py` is the new gate - every `*_test.zig` is
named, every name is a file, and production names none of them - because a hand
list that silently lost an entry reads exactly like a green run.
