A `grain.Ruling` is a structural index over a file, and the only thing that
travels from a file's owner to a hand - the scanner between them is per grammar,
not per file. So installing one was `w.loom.sc.carry.ruled = &w.ruling.?`: three
hops through two types to set a field whose whole lifetime rule lives in a doc
comment on the field itself, one type further in. Grain filed it as sound but
wider than the operation, and it was not grain's file to narrow.

`Scanner.rule(?*grain.Ruling)` now is the operation. Where the handle is kept is
the scanner's business again, and what a caller owes is only the rule it can
actually keep: the ruling outlives every scan that can see it, and null takes it
back before the owner lets go.

The caveat is in the doc comment because it is the kind that bites later.
`Carry` is copied by value and `Save` is documented pointer-free - about a
kilobyte, no allocation - which holds exactly as long as a save is a copy in this
process, and stops holding the moment one is written to a file, where a
serialized `Save` carries a pointer into a dead address space. So it is a cache
handle, not state: anything that persists a `Save` drops this on the way out and
re-offers on the way back in. Nothing is load-bearing for correctness either way
- `grain.lead` consults a ruling only when it describes the exact bytes in hand -
so an installer that forgets costs a measurement, never a column, which is also
why a bench is the only instrument that would ever catch it.

`kernel/weave`'s three reach-through sites still spell it the old way. Rewiring
them is one line each and belongs to whoever owns that file; the method, its
contract and its test are here.
