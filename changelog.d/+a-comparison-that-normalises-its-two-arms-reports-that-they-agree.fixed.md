`holdout.py forked` reads one source file against every copy of a grammar's
oracle that exists on this disk, to answer whether the multi-copy situation
`attest.py` surfaced means a corpus number is a number *per copy*. Its first
version reported perfect agreement across fourteen grammars — css 100.0% and
100.0%, scala 33.5% and 33.5%, toml 99.2% three times, a spread of zero on every
row. A reassuring result, and entirely manufactured by the instrument.

`plumb.read` calls `differential.oracle_build`, which overwrites a tree's
`src/grammar.json` with the one it was handed whenever the two digests differ,
and regenerates `parser.c` from it. So the verb normalised every copy to the
same grammar before reading it, then reported that the copies agreed. They did.
After being made identical.

Nothing in the verdict could show this: it was clean, and it was clean twice.
What showed it was asking what actually differs between the directories —
thirteen of the fourteen differ in `grammar.json` itself, and two trees with
different grammars cannot produce identical `trued` to one decimal place on the
same file. Either the digests were wrong or the comparison was not comparing.

`oracle_build` is now stood down for the duration of the verb, and that is the
whole of its correctness; the docstring says so first. With it stood down the
answer arrives honestly: of 14 forked grammars and 29 distinct source trees,
**exactly one copy per grammar can answer at all** — the rest carry no generated
`parser.c` and will not compile — so no measured number in this dossier depends
on which copy was found. Same conclusion as the broken version, reached for a
reason rather than by accident.

Where it costs something: the verb now reports a copy that cannot answer as
unable to answer, which reads as a thinner comparison than the first version's
fourteen tidy pairs. That is the point. The general shape is this tree's
recurring one and it has now caught three instruments — `specimen.py`'s `stop()`
defaulting a missing stop line to one root and no mends, `order.py::miss` keying
folio freshness on a path plus an mtime so a before-arm reads its after-arm's
table, and this. A comparison whose setup silently makes its two arms equal will
report that they are equal, and the error is always flattering, because two
readings of the same thing always agree.
