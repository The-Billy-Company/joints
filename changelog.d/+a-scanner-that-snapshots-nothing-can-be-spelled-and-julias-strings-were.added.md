Julia's eight string and command interiors and both of their closes are seated,
so `"""…"""` is a string rather than a heap of identifiers. Julia goes 39.0% ->
**59.6% standing**, 68.6% -> 80.3% covered, unbound 14,307 -> **8,912**, bare
leaves 1,539 -> 897, and the whole board 66.30% -> 67.37% with unbound down
5,395. Twenty-nine of thirty rows are byte-identical in every board column;
julia is the only one that moved.

The classification is the reusable part. Not "does the grammar rule look
stateful" but **what does `serialize` write**, because tree-sitter forces a
scanner to declare its whole memory there so the runtime can snapshot it at
every GLR fork. Julia writes zero bytes and `create` returns NULL, so it has no
answer that can depend on which reading asked and the soundness bar is met by
construction. Kotlin writes a stack (2 bytes a frame, `[delimiter|triple,
prefix_len]`) and swift a `uint32_t ongoing_raw_str_hash_count`; both interiors
re-enter arbitrarily far from their opener, so neither is a fixed or captured
close and both are declined. That decline costs at most kotlin's whole
remaining unbound of 1,269 bytes and swift's 1,340 — and kotlin's real problem
is not strings at all but 19,705 orphan bytes, 55% of the file, in KDoc sitting
as top-level leaf roots.

Julia is a `marrow` **family with its own walk**, not eight rows under
elixir's, and reusing `matter` would have silently changed elixir's answers in
three places: julia refuses at end of input where elixir hands back matter to
the end, its interpolation sigil is a bare `$` and not `#{`, and its raw arm
stops on `\\` as well as on an escaped delimiter. `marrow.walk` returns
`matter | close | none` because julia emits `_end_str` from inside the content
scan, where the delimiter's width is knowable and nowhere else. The roster
takes the first member a state admits and puts the plain terminals ahead of the
raw ones, so it was worth censusing whether a raw interior can also admit its
plain twin — the interpolating walk over a raw run would stop at a `$` that raw
julia keeps. Every pair involving a raw terminal is `set 0`, never in one
permission set at all, so the order cannot reach a wrong member. The corpus
could not have caught that one: neither julia file holds a raw string.

**The instrument that lied was `state --census`, and it lied by answering a
neighbouring question in the vocabulary of mine.** It reduced each pair to
co-admission **by shift** and printed a wall of zeros, which reads exactly like
the clearance the swift `!` precedent taught us to look for. But the permission
set a hand reads is `drive.offer`'s — every terminal with any non-error action,
shifts and reduce-lookaheads alike, because that is tree-sitter's
`valid_symbols`. In *that* column six of julia's ten sit together in three
states, first at state 1, where 103 terminals all fold `identifier ->
_word_identifier`. A seating built on the shift column would have had no
`rival` guard and would have answered string content over every identifier in
the language. `together` now prints `shift` and `set` side by side. This is the
second time this session a mechanism and its census disagreed about which half
of a state row they meant, after `lex`'s blind count called swift blind to a
terminal the parser was emitting.

Two more things went the wrong way and are not being smoothed. `describes` fell
2,130 nodes while `built` rose 5,634 — the signature the notes call the verilog
`keep` trap. It is not that trap here (`spoil` fell 3,194 and `covered` rose, so
the parse reached *more* bytes) but the falsifier as written could not tell the
two apart, and the sharper rule is that falling nodes are only reading-less when
`covered` falls or `spoil` rises with them. A docstring that was hundreds of
bare leaves is now one `(string_literal (content))`; that is consolidation. And
four of nine predictions failed outright: rubble and spoil **both** fell where
one was predicted to rise, roots landed at 1,591 against a predicted 500
because the wall only moved rather than clearing, and julia's orphan fell 239
bytes where it was predicted to rise.

Also sharpened, because the roster guard fired and adding an entry was not the
fix: `troupeKey` now keys on the anchor as well as the mechanism. Two rows —
kotlin's `multiline_comment` and scala's `block_comment` — shared the single
permission `marrow/kotlin_block` pinned to `{kotlin, scala}`, so either could
have widened onto the other's grammar with the test still green. The claim that
they could not lived in a comment beside the pin where nothing checked it.
There is now a test asserting one permission per row, which fails on the old
key.

Julia's remaining five blind terminals are the `_immediate_*` cohort and they
are stateless too, but they answer zero-width while moving no memory, and
`step`'s pin refuses a zero-width answer whose `Carry.shape()` did not move.
That is a new `kind` rather than a new row; it is handed over with its census
already run.
