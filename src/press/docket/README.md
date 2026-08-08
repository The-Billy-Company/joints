# docket - the job ticket, for a job that went through the whole shop

A docket travels with the work and records what happened at every station. These
two tests do the same thing: neither one checks the press by reading the press.
They run the finished job - press, write, scan, parse, walk - and check what came
out the far end.

That is why they live in a directory of their own instead of loose beside the code
they exercise. They are integration tests, and for most of this repository's life
they wore a unit test's address: they sat in `press/`, which put them in the
press's zone, which meant every downstream module they legitimately needed was an
import pointing *up* the page. The charter carried four ratified variances to
excuse it, each with a note saying the fix was a zone of their own and the cost
was colocation nobody wanted to pay.

Splitting `press/` into its four real layers made that cost vanish. Once the area
has interior directories, this is simply one more of them, and the four variances
are gone rather than repointed. `charter.zone` now zones `press/docket/**` above
`folio`, which is what these files always were.

| File | What it runs the whole job for |
|---|---|
| `carry_test.zig` | The artifact against the IR, field by field, by reflection. `press` computes an IR and `folio` writes it down; between them is a byte format, and it is the one boundary in this package where a field can go missing without anybody writing a line of wrong code. |
| `census_test.zig` | Thirty grammars in, one owner per wall out. Every grammar that does not parse whole stops somewhere, and deciding which of four subsystems each stop belongs to used to be a markdown table - which is to say a snapshot, and stale. Now it is a program. A generator's census that stopped at the generator would be recording the generator's opinion of itself. |
