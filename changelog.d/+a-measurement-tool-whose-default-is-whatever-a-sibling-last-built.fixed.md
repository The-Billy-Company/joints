`tool/specimen.py` fell back to the shared `zig-out/bin/outliner` whenever
`OUTLINER_BIN` was unset, and printed a verdict without mentioning which binary
produced it. Ten lanes build into that prefix. A lane on its final pass read
**7 of 20 specimens sound from a tree that actually builds 14 of 20** - a
sibling had rebuilt the prefix from a different state mid-run - and nothing in
the output said so. It was caught because the number was implausible against
work that lane had just finished, which is not a mechanism.

Every report now carries `stamp.line()`, printed after the verdict rather than
before it, so `moved()` covers the run's own interval - sweeps here take minutes
and four lanes land inside one. And a run is **refused, exit 3**, when it is
both unattributed and out of date: the default prefix with no `OUTLINER_BIN`,
*and* a binary older than a source in the tree or built from different sources
than the repo now holds. Those two conditions together are precisely the failure
that happened and nothing else is refused - a deliberate `pin.py` binary drifts
by design, and a prefix somebody just rebuilt passes untouched. `--anyway`
downgrades the refusal to a printed hazard, and reads where a hand would put it,
after the verb.

It fired on its first invocation in this tree, against a `zig-out` older than
`src/surface/face/outliner/state.zig`. **It also caught the lane that wrote it**:
a specimen pass taken earlier through a stale pin read 7 of 22, and the same
suite against a binary built from the current tree reads 15 of 22 - swift's
`multiline-comment` and `nested-comment` and kotlin's three string specimens had
all been fixed by a lex lane while the number said otherwise. Every figure in
`research/joinery/plumb/RESULT-2-racked.md` was retaken.

Separately, `specimen/kotlin/embedded-quote.kt` asserted `lacks
simple_identifier`, which no tree can satisfy, because the file's own `val t`
binds a name. Deleted rather than rewritten, and it cost the specimen nothing:
`spans string_literal 8 21` was already on the next line and says the whole
thing, since a reader that closes on the `"` at byte 13 cannot also reach byte
21. Checked both ways before removing it - 0/5 against the tree before kotlin's
strings were seated, 5/5 after - because deleting an unsatisfiable claim and
weakening a live one look identical in a diff, and only the demonstration tells
them apart.
