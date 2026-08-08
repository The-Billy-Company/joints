`Weave.open` is now `Weave.warp`, and that is the whole change: seven call sites,
one definition, one README line.

`open` was the package's one genuinely overloaded verb. `folio.open`,
`codex.open` and the C ABI's `bank.open` all mean *prove these bytes are an
artifact* - one operation, three artifacts, consistent. Then the parse path used
the same word for something unrelated: install this text and read it cold. The
place it actually hurt was `amend_test.zig`, where `bolt.open()` hands back a
fresh weave and `w.open(text)` parses a file, two lines apart, sharing a name and
sharing nothing else.

`warp` is what you call mounting the lengthwise threads on a loom before any
cloth exists, which is this and not a metaphor stretched to fit. The file was
already speaking that dialect - `Loom`, `shed`, `rip`, `spun` - so it is an
insider word in a room full of them rather than a clever one dropped in. It also
pairs: `warp` then `amend` reads as dress the loom, then mend the cloth, where
`open` then `amend` read as two unrelated things you happen to do in order.

The four loading functions on the folio facade got a comment instead of a rename.
They look like verb drift - `open`, `openVolume`, `map`, `mapVolume` - and they
are a 2x2 over two real axes: what the file may hold (one grammar, or either
artifact) and where its bytes are (in hand, or still on disk). `map` is not a
politer `open`; `open` proves bytes the caller owns, `map` acquires pages you must
`close`, and one verb over both would have hidden exactly the difference that
decides whether you leak.
