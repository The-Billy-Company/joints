Four pages published a corpus `square` total yesterday morning: **311,540**
(`consort/RESULT-4-borrow.md`, `consort/RESULT-8-sighted.md`,
`consort/PREDICTION-3-sighted.md`, `bench.report.md`), **313,440**
(`changelog.d/+the-parser-had-one-move…`), **309,356** (`fuses/README.md`,
`fuses/RESULT-1-series.md`). They differ by 1,900 bytes. **None of them is
wrong.** A cpp fix landed between them, and the third excludes verilog.

Every one of those pages is `sighted` under the classification `sighting.py` has
been running all week: they quote `square`, which is the oracle's word and not
ours, so they asked a second parser. The old `--gate --since` passes all of
them. Naming the oracle says the figure was *compared*; it does not say what it
was compared **on**, and two of the three carry no digest of any kind.

So the gate reads a second axis, orthogonal to the first:

- **blind** - quotes our columns and never the oracle's. 103 of 258 measuring
  pages.
- **unstamped** - quotes a measured figure and names no tree or binary. 181 of
  258, and **103 of those are sighted**, which is the population the old gate
  was structurally unable to see.

Both, and 206 of 386 pages fail one. The corpus exhibits all four corners of
the two axes, so neither is the other wearing a hat - that is a check, not a
remark, and it fails if the corpus ever stops exhibiting a corner rather than
passing over an empty set.

A stamp is any run of seven or more hex characters with a letter in it -
`joints f6a34cd7c`, `repo f7ba40004+55`, `tree c0cdbde69`, a `stamp:` line.
Deliberately not anchored to a keyword: the keyword-anchored variant refuses 203
where this refuses 184, and the 19 it adds are pages carrying a digest in a
spelling the keyword list had not met. A list that must be complete to avoid a
false refusal is the wrong shape for something lanes have to live under. The
`[a-f]` is load-bearing - `\b[0-9a-f]{7,}\b` alone reads a seven-digit *number*
as a digest, and this record is made of seven-digit numbers.

**It is priced at the diff, not at the record.** The old form surveyed all 386
pages and then filtered to the changed ones, which costs the whole record to
answer a question about a handful of files and gets slower every week somebody
writes a page. `gate()` reads only the paths the diff names: **~23 ms fixed**
(17.6 ms `git diff` + 5.4 ms page walk) **+ ~0.55 ms per page**. A ten-page lane
change costs **~28 ms**. The whole uncommitted record - 376 pages, the worst
case that exists - costs **480 ms**, still inside the one-second ceiling.

Prose is never asked for anything: 128 of the 386 pages quote no measured figure
and the gate does not look at them twice. That is the whole of its claim to
being affordable to leave on.

`sighting.py --check` is new and is corpus-shaped on purpose. A check pinned to
`RESULT-4-borrow.md` being sighted-and-unstamped dies the morning somebody
stamps that one page, and dies looking like a pass.

**Blocking, not advisory — with the ref pinned to the commit it is turned on
at.** Advisory is what the record has had all week, and the finding it produced
is that 116 was not a backlog: five blind pages were written *after* attribution
was possible, three within three minutes of each other. An advisory gate is
indistinguishable from the state that produced them. Blocking is affordable
because the cost is the diff's and not the record's, and because the remedy is
110 ms of `standing.py --cite`. What it cannot be is retroactive: 206 of 386
pages fail, so a `--since` reaching before today refuses the whole record. That
makes it the same forward ratchet the `.baseline` gates already are, and it is
honest as long as nobody quietly moves the ref forward to clear a page.

One known false-refusal class, found within the hour by the gate refusing two of
this lane's own changelog fragments. Both are on the **blind** axis, which
predates this change; `shear.py` presses the same bytes with the same grammar
twice and has no second parser in the question it asks, and
`onlydamage.FOREST`'s oracle-free exemption has no spelling for a
self-comparison instrument. Left for whoever owns that vocabulary rather than
widened here, because widening a classifier until its author's pages go green is
the shape of a check being edited to match its evidence. The stamp axis has no
false refusal anybody has found yet.
