`Gather.offer` answered the same question thousands of times per file: which
terminals can this state actually shift, given the stack it is standing on. The
lookahead walks that answer it are deterministic in the table, the perch states
they descend through, and nothing else - and they re-ran on every token, then
re-admitted their answer into `Expected` one terminal at a time through the tier
machinery, hundreds of `admit` calls per position. A quarter of a cold cpp parse
was the walks; another slice was the re-admission of answers nobody had changed.

Both halves are memoized now, and the second half is not even a copy. A state's
slate keeps records per stack context - 16-way associative, LRU by a running
tick, walk answers packed into a 512-bit mask by unsure ordinal - and `recall`
re-admits the whole slate when the recorded suffix still holds, which on real
files is nearly every token. The permission set those admissions build is
interned once as a whole `Expected` (a `Look`), and a token whose record already
knows its veil hands the scanner the snapshot itself, by pointer. The fast path
moves one pointer where it used to move every tier word and both masks; the
interned `Expected` is immutable by construction, so the scan reads it where it
lies. `plant` takes the worn veil id from the token whose refusal asked for the
supply, rather than re-interning a scratch `Expected` that no longer tracks the
fast path.

Measured on the 129 KB cpp corpus: 170.9 ns/byte to 97.3 for the records plus
the interning, then 72.9 once the pointer replaced the copy - past tree-sitter's
74.5 on the same clock, the last of nine grammars to cross. The invariant the
suite holds is that a veiled offer and a rebuilt offer produce byte-identical
admissions; `tool/order.py` holds the complexity claim - same bytes, same nodes,
opposite order, every swing at or under 1.6x.
