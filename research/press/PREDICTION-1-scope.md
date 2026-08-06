# Prediction 1 — semantic or representational, and where the wobble lives

Written before the measurement that decides it. `RESULT-1-identity.md` next door
found nine of thirty grammars pressing to different bytes twice in a row from
one binary. The question this dossier exists to answer is whether those are
**different tables** or **the same tables written down differently**, because
the first invalidates a day of attribution controls and the second does not.

## Prediction 1a — the wobble is confined to one section

> **Prediction:** the difference between two mints of one grammar is not spread
> across the file. It lives in a section, and the LALR tables — `production`,
> `row`, `group`, `set_span`, `setsym`, `complete`, `conflict`, `party` — are
> byte-identical between the two.
>
> *Falsifier:* extract each of the twenty sections out of two folios of the same
> grammar by the sealed directory and compare them; any table section differing
> falsifies this and makes the finding immediately semantic.

## Prediction 1b — the deflated lexicon, inflating to a *nearly* equal image

> **Prediction:** the differing section is `lexicon` — the deflated DFA block —
> and inflating both blocks yields images of **the same length** that differ at
> a small number of scattered byte offsets rather than at a shifted run.
>
> A same-length image differing in scattered bytes cannot be a different
> automaton: an automaton with one more state, one more class, or one more
> transition changes the length of `trans_in` and every offset after it. Equal
> lengths with local differences is either padding or a value that does not
> index anything.
>
> *Falsifier:* the two inflated images differ in length, or the differences run
> contiguously from one offset to the end. Either says the block describes a
> different machine, and the finding is semantic for lexing.

## Prediction 1c — the cause is uninitialized padding in `Head`

> **Prediction:** `lexicon.Head` is an `extern struct` of six `u32`, a `u64`,
> and seven more `u32` — sixty bytes of fields in a type aligned to eight, so
> `@sizeOf(Head)` is **64 and the last four bytes are padding**. `freeze` writes
> it with `std.mem.asBytes(&Head{…})`, which writes all sixty-four, and Zig does
> not promise a struct literal's padding is zero. So every voice contributes
> four bytes of whatever the stack held, the deflate compresses that differently
> run to run, and the block's length moves.
>
> *Falsifier:* the differing offsets in the inflated image are **not** at
> `voice_base + 60 .. voice_base + 64`. If they land inside a table, this is not
> padding and the diagnosis is wrong.

If 1c holds, this is **uninitialized memory reaching a persisted artifact**,
which is a materially worse class of bug than an unstable iteration order: the
same mechanism that makes the file unreproducible also writes four bytes of
arbitrary process memory per automaton into a file meant to be shared between
machines.

## Prediction 1d — the nine are the grammars with the most voices

> **Prediction:** whether a grammar wobbles is not about declared conflicts,
> externals, or grammar size as such. It is about how many bytes of padding the
> block carries and whether they happen to land on values the deflater encodes
> differently. Grammars that never wobble should be the ones with few voices, or
> ones whose padding happens to be reliably zero.
>
> *Falsifier:* a grammar with many voices that is perfectly reproducible over
> many mints while a small one wobbles, with no other explanation.

## Prediction 1e — the three attribution claims survive

> **Prediction:** the precedence fix's "28 of 30 byte-identical", the layout
> seating's "29 of 30", and the separator seating's "only two rows moved" all
> compared **board output** — parse results and node counts — and not folio
> bytes. A lexicon whose deflated length moves but whose automata are identical
> changes no token, so those controls are sound as written.
>
> *Falsifier:* the inflated images differ somewhere a scan reads, or any of
> those three controls turns out to have compared folio digests. Then its
> attribution has a nine-grammar noise floor and has to be re-run.
