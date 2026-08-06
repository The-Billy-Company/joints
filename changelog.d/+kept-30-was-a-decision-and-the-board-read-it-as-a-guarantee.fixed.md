`cache: kept 30` says what `folio_for` decided when each row asked it. Between
that decision and the end of the board sits the entire measurement. On
2026-08-05 a sibling's `zig build` landed at 11:43:49 and something re-minted
every folio in the cache between 11:43:55 and 11:44:04 while the board was
running and printing exactly that line, and the atomic publish makes the failure
invisible by construction: folios go to a temp path and `os.replace` in, so every
reader gets a whole, individually valid folio and there is no torn byte anywhere
to give it away. A board can assemble a table out of two generations and be
telling the truth about the question it asked.

The rule is now that an instrument records **what it read, by content, at read
time**, and reads everything again at the end. `stamp.fed` used to store an
mtime and never look at it; it now stores a `Sight` - sha256 of the bytes, size,
mtime, and the row that was being measured - for the folio *and* for the binary,
on every row. `stamp.reconcile` re-reads each artifact once when the measuring
stops and returns a `Ledger`. If a row's last read agrees with what is at that
path now, that row is comparable. If it does not, **that row is named**, because
a partial answer that knows it is partial is worth more here than a clean number
averaged over two trees. The board marks each such row ` · SPLIT`, prints the
artifacts with `read <digest>, now <digest>`, and exits **3** - not 1, which is a
lane's bad day, and not 2, which is a parser fault, but "read it, do not compare
it". `--settle[=N]` re-measures only the named rows, up to N rounds; restarting
the whole board would throw away twenty-nine good rows because one folio moved,
and against a tree ten agents rebuild continuously an unbounded restart has no
reason to terminate.

Reproduced before it was fixed, and the reproduction is the argument.
`research/generation/stage.py blind` runs **three** re-minting agents driving the
older `.local/ink/base/bin/outliner` over one warm cache, and starts **two**
boards against that cache at the same instant - one on `tool/` as it stands, one
on a scratch copy with the old stat-and-forget rule appended back on, restored
explicitly rather than broken and called equivalent. Same seconds, same cache,
same publishes. The old rule: `kept 30`, no warning, exit 0, **349,259 built of
526,798, 66.3% standing**. The new rule: `SPLIT`, exit 3, `cpp css elixir go`
named, **the same 349,259 built** with 54,824 of those bytes marked as coming
from a generation the tree no longer holds. The old board is not wrong-looking.
It is identical and unmarked, which is the whole defect. Real processes
throughout - five of them - because the pid is what keeps two minting agents off
one temp filename and a threaded stage would not exercise the thing under test.

The binary needed its own identity and that turned out to be the expensive half.
`STALE`, `DRIFT` and `MOVED` all watch the *sources*, and a rebuild need not
touch one, so `stage.py binary` installs a real older binary over the running one
mid-board - with an mtime **older** than the folios, so the freshness rule stays
quiet, which is every pinned build and every `cp -p` - and today's detectors say
**nothing** while sixteen of thirty rows are measured by a build that is no
longer there and the board reports 62.1% standing unmarked. Getting that to
happen took three tries: 0.25s landed before the first row and 2.5s after the
last, both with the mechanism correctly reporting one generation, so the trial
now sweeps delays and prints which one landed. A race you have to aim at is
still a race.

What it costs is **+68 ms of whole process, +8.3% of an 850 ms board**, seven
runs an arm, alternating, measured with `fork`/`exec` included and with the old
rule restored in a scratch tree rather than subtracted out. That falsifies the
prediction written before the run, which said under 5% and 30-50 ms; the
estimate had priced the hashing (~34 ms, and `hashlib.file_digest` is not faster
than the loop already there) and had no line for pulling 14.4 MB of folio through
the page cache into user space. Three quarters of the bytes are the binary, read
once per row, and the lever - memoise it on its stat key - stays unpulled,
because deciding one artifact's identity by a stat is this bug, and per-row
digesting is exactly what turns a mid-run rebuild into "sixteen of thirty rows"
instead of "something moved".

Where it goes the wrong way: **the press is not reproducible.** Pressing each
grammar six times with one binary, nothing changed between them, gives more than
one folio for **at least fourteen of thirty** - `cpp css elixir go haskell
javascript julia latex ocaml python scala sql swift verilog` - and seven of those
produce three distinct byte *lengths* in six presses, so it is a different
amount of data being written and not a table interned in hash-map order. The
count moves with how hard you look: two mints each said nine, six said fourteen,
and a second six-mint pass said thirteen (the same set without `julia`), so
fourteen is a floor and not a total. So the ledger has a false-alarm floor of
nearly half the board: any instrument re-pressing one of those while the board
reads it splits the board for a reason nobody can act on. That falsified the
other prediction, which had assumed a re-mint by
an unchanged binary was not a generation change at all. The control trial is
still the argument for hashing over stat-ing, just not the argument it was
predicted to be - an mtime rule called **16 of 31** artifacts moved there where
the digest called **2**, and the fourteen in between were byte-identical
republishes an mtime rule would have screamed at. The `republished` field carries
that count into the output so the difference stays visible after the argument has
been read once. The fourteen are somebody's real bug, in the press and not here:
a folio that is not a function of its grammar cannot be content-addressed and
makes every "byte-identical" claim about folios unstable - including the board's
own `30 grammars byte-identical, 0 moved`, which is already on this project's
list of instruments that lied. `order.py` round-trips mint→readback for all
thirty; it does not compare two mints, and nothing else in the tree does either,
which is how this survived.

The instrument that lied this time was found inside the fix, which is the third
time in a row that has happened in this file. `order.CACHE` was written per call,
`folio_for` is called twice per row, and the second call's `kept` overwrote the
first call's `re-minted` - so a board that pressed all thirty folios from an
empty cache printed `cache: kept 30`, the exact string this whole lane exists
because of, describing thirty presses it had just performed. `note()` now makes a
significant status sticky, and the `cache:` line says out loud that it reports
what the cache *decided*, not what was read, and points at the generation line
below it for that. A smaller one beside it: an artifact that moved and was then
re-measured by `--settle` printed `read X, now X` under a heading calling it
moved, because the ledger reported the last sighting rather than the first. Both
were mine, both were in the code that reports honesty, and neither would have
been found by anything except reading the output of a run whose answer I already
knew.
