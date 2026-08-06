The attribution gate is now merge-blocking, as the `record` job in CI. It is a
forward ratchet: it asks about the pages a diff names since a pinned ref and
never about the record it inherited, because relitigating 206 pages is exactly
the sweep this lane's own finding says does not work.

That is honest for precisely as long as nobody can move the ref quietly. A pin
nudged past an inconvenient page clears it while every run still prints `pass`,
which is a worse failure than no gate - it is a gate that certifies. So the ref
is a committed, append-only ledger at `research/joinery/consort/sighting.since`,
the live pin is its last line, and four things stand behind it:

1. **Every run prints it, pass or fail** - the ref and its age, before any
   verdict, so it is never off-screen in the log of the run it silenced.
2. **A working-tree copy differing from the committed one refuses the run** at
   exit 2. Moving the pin costs a reviewed commit and can never be a local
   convenience.
3. **`--since` may only reach further back than the pin.** Asking about more
   pages is how a lane checks its own work harder than CI will; asking about
   fewer is the pin moved by a flag, and it exits 2.
4. **`--pin` says what the move buys before it writes it.** It prints exactly
   which currently-refused pages would stop being asked, then appends a row
   carrying that count and a mandatory `--because`. A move that clears pages has
   to be typed next to the number of pages it clears.

Both refs in rule 3 are **resolved** before they are compared, not compared as
text. The first spelling of that rule refused `--since HEAD` on the day the pin
*is* HEAD - the same ref, differently spelled - while a descendant sha would
have walked past it as "not equal". A guard that refuses the honest invocation
and admits the dishonest one is the wrong way round.

**Page granularity is the wrong granularity**, and one edit found it out: adding
a row to a dossier's table of contents made this lane answerable for 23 figures
further down the page that somebody else wrote months ago. *Refuses a page the
diff names and never a page already written* is only true if "written" means the
bytes. So a page is asked when the lines it **gained** carry a measured figure.
Prose, a link, a fixed typo and a table of contents ask nothing; an added data
row does, because every table's header is re-seated over the diff hunk before
the count is taken - the hunk holds `| 311,540 |` and the word `square` is three
hundred lines up. An untracked page has no diff and is asked whole.

Cost on the real enforcement path, whole processes with real git, median of
seven, on a laptop with nine sibling lanes compiling: **115 ms** at one page,
**229 ms** at ten, **319 ms** at twenty-five, **344 ms** at fifty. Quiet, the
same four are 91 / 180 / 276 / 330 ms; the contended column is the one to plan
against. The live run at the pin `459c097` on this machine is **270 ms** over the
twelve pages the diff names. The one reading over the ceiling is a diff naming
the whole record - **1.2 s** over 409 pages, which was this tree for the hour
between turning the gate on and the record landing in a commit. The gate now
prints that number when it happens rather than being quietly slow, and says what
a diff that wide means: either a record nobody has committed, or the sweep the
ratchet exists to make unnecessary.

That hour is also the first thing the ledger had to record. The record was
committed *after* the first pin, so 405 pages read as authored under a gate that
did not exist when they were written; the pin moved to `459c097` and the ledger
line says it cleared 219 refused pages, because a move that clears pages has to
be typed next to the number of pages it clears.

`--check` grew from 9 assertions to 28, each built and watched to fail: that the
stamp axis blocks and the blind axis does not, that `--strict` reverses it, that
the module spawning the oracle is never exempt, that a column nothing reports
earns nothing, that a contents row asks nothing while a data row does, that an
edited comment in the ledger is not a moved pin while an appended row is, and
each of the four ledger rules above.

The `record` job is the only one in `ci.yml` that clones with `fetch-depth: 0`,
because a ratchet needs a diff and a depth-1 checkout has none. No toolchain, no
sibling, no network past the clone.
