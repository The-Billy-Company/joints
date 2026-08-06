The repair for *"four bytes of this process went into every automaton we wrote"*
was twelve lines in one function, and a rule that lives in one function is a
rule the next writer will not find. This is the sweep behind it and the gate
that makes it structural.

Every `asBytes` / `sliceAsBytes` / `bytesAsSlice` in `src/` was enumerated, its
element type resolved, and classified by what the bytes reach — disk, a hash, or
nothing. Nothing else reaches disk with slack, and **every hashed element type
here is seamless**: `u32`, `enum(u32)`, and `lr0.Item`'s `packed struct(u64)`.
That is a clean negative and it is worth saying, because the six interners that
key on `sliceAsBytes` were relying on it rather than asserting it.

They assert it now, at the type rather than at the call site, which is where the
edit that would break it happens: `lr0.Item`, `grammar.Symbol` and
`roster.State` each carry a `hasUniqueRepresentation` assertion, and between
them they are the element type of every byte-keyed hash in the tree. Two of
those read as trivially true today — a bare `u32` owns its bytes — and that is
the point of putting them at a `pub const Symbol = u32;` rather than in a
comment: widening one to a struct is a two-line edit that would make two
identical right-hand sides hash apart and stop deduplicating, silently. `Item`'s
sits inside the struct body next to the `packed struct(u64)` that makes padding
unrepresentable, against the day somebody drops the backing integer to add a
field. All three spell the predicate as `std.meta.hasUniqueRepresentation`
rather than importing `leaf.seamless`: the production arrow is folio → press and
nothing under `press/` may read folio back, so one law in std's own spelling
beats one law and a cycle.

Two real things came out of the sweep. `flat`'s own guard admitted the bug it
exists to prevent: it refused a field that "is not an integer", and
`@sizeOf(u21)` is four while a store writes twenty-one bits, so an integer field
could carry eleven bits of the source's slack into the zeroed cell. Its
predicate is now `std.meta.hasUniqueRepresentation`, which is what the property
actually is and is the same one `std.mem.eql` consults before it will `memcmp` a
type. And the sibling engine had a live site of its own — irregex's AST interner
read `[]const [2]u21` as bytes in both `hash` and `eql`, so two byte images of
one Unicode class could fail to intern as one node. Fixed there and measured
there: it turns out to cost **zero** nodes today, because the parser's store
path zero-extends. The dossier in irregex's `research/seams/` carries the number
and why the fix stands anyway.

The gate is `leaf.seamless(T)`, a comptime `@compileError` when a type's fields
do not tile it, applied over a roster derived from the format —
`for (std.enums.values(Kind)) |k| seamless(Record(k))` — so a section added
tomorrow is checked without anyone remembering this exists. It covers the half
`flat` cannot: `collate.view` casts a mapping straight to `[]Record(k)`, with no
writer to route through, and a record that grew an alignment hole would be read
four bytes to the left from the second row on. That is a silent misread the
schema digest cannot see, because the digest spells the fields and the hole is
what the fields are not. `forme.Said` carries the same assertion on the hash
side.

Anti-vacuity is three assertions in one test, because a `for` over an empty
roster passes and so does a predicate that says yes to everything: the walk
counts `kind_count` records, at least eight of them are structs rather than bare
integers, and the predicate still says **no** over `struct { hi: u32, mask: u64 }`
— the shape that started this — and over `extern struct { a: u32, b: u64 }`,
the near miss with no visible gap.

Zero board cells moved, measured rather than argued: one snapshot of `src/`
copied twice, the second arm with exactly the three gate edits removed
(`diff -rq` reports three files and no others), both built at the same path,
each boarded into its own folio cache. **665 cells compared, 240 of them damage
or structure numbers, 0 moved** — and perturbing one cell by one makes the
comparator report exactly that cell, so the zero is a measurement and not an
empty walk. The three interner assertions landed after that run and are not
covered by it; they are `comptime` blocks, which have no runtime form the
compiler could emit differently, and both shapes were checked to actually fire
— an in-struct `comptime` and a top-level one, each over a type with slack.

The instrument that lied was my own prediction. I expected the two arms to
produce byte-identical binaries, since every difference between them is a
`comptime` block, a `test` block, or a comment. They came out the same size
(1,763,160 bytes) with different `sha256`: added comment lines move the DWARF
line program, and a digest cannot tell a shifted line table from a shifted
instruction. A binary's sha256 is not an oracle for behaviour, for the same
reason a folio's is not an oracle for a press.
