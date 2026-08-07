#!/usr/bin/env python3
"""Bytes under a root is not the same question as bytes under a TREE.

`reach` was a watermark: the largest end offset any root reached, so a parse
that mended past trouble and resumed flew over the hole and reported the file
whole. `covered` replaced it with the union of the top-level root spans, which
is honest about holes and is the number the dossier now quotes.

`covered` has its own watermark, one level down. It counts a byte as read when
a **bare leaf token** stands over it, and a mend leaves exactly that: a lone
token where a subtree should have been. So a file the parse shredded into 2,596
one-token roots and a file it parsed whole can report the same `covered`, and
the shredded one has no structure at all. kotlin is the exhibit - 91.5% covered,
42.8% standing, 17,464 bytes under leaves in a grammar the board reads as nearly
finished.

So split it. A top-level root with at least one child is a CONSTRUCT: the parse
recognised something and the bytes beneath it are structured. A root with none
is a LEAF. `built` is bytes under a construct, `strewn` is bytes under a leaf,
and `standing` is `built` as a share of the file.

  covered  = built + strewn   did the parse READ these bytes
  standing = built            did it UNDERSTAND them

The two move independently, which is the point. Measured 2026-08-05, the same
engine fix moved julia 21.2 -> 67.2 covered and swift 49.5 -> 77.0; swift's
bytes landed in `built` and most of julia's did too, but julia also gained 3,732
bytes of `strewn` - identifiers that now lex correctly inside a docstring whose
external scanner still walls, so they are named rubble rather than tree. Reading
`covered` alone would have called those a win. Reading a spot-check of the tree
alone would have thrown away the 8,847 bytes that were real.

**And `strewn` has a watermark of its own, which is what the last two columns
are for.** A declared **extra** - a comment, a docstring, a pragma - is a leaf
node in *any* parse, healthy or broken: it has no subtree to be missing. It
becomes a top-level root only because the mend put the stack down and left no
parent to adopt it. So charging its bytes to "a token lying where a tree should
be" prices a comment at the weight of a lost construct, and the gap then tracks
the file's comment density rather than the grammar's health. Split it the same
way:

  strewn = orphan + rubble    orphan = under a leaf the grammar calls an extra
                              rubble = under a leaf that is code

Measured 2026-08-05 over all thirty: 89,364 strewn is **50,486 orphan and 38,878
rubble**, so more than half of the headline gap is comments. It reorders the
board. kotlin - the exhibit, 17,464 bytes under leaves - is 15,573 bytes of
KDoc and **1,891 bytes of code**; php's 5,744 is 20 bytes of code; haskell's
8,133 is 10. verilog, elixir, julia and scala barely move, and they are the
real work.

**And `rubble` has a watermark of its own, which is the one that nearly cost a
lane a night.** Every column above is a share of `under`: `built`, `strewn`,
`orphan` and `rubble` all describe bytes the parse got *some* root over. A byte
no root reached at all is in none of them - not in `rubble`, not in `strewn`,
nowhere. The metric goes silent in exactly the case where the parse did worst,
and silence reads as a zero.

Two grammars make it unanswerable. haskell is 34,240 bytes at 23.8% covered with
16,635 mends and scores **10 bytes** of rubble - less than `c` scores on a
1,444-byte file. yaml lexes no terminal at all, builds no tree, and scores **0**,
tying a grammar that read everything. Read as the work order that board sends the
next lane to verilog while haskell sits at 23.8%, and on 2026-08-05 it did.

So name the fourth bucket and close the identity:

  size = built + orphan + rubble + spoil

  spoil   = under NO top-level root at all - the parse never reached these bytes
  unbound = rubble + spoil - bytes with no structural account of any kind

`unbound` is a **bound, not a measurement**, and the docstring says so because
the column cannot. Some spoil is comment and would have been `orphan` had a root
ever got over it - but the parse emitted no node to say which, and splitting it
on a guess would be the same silence wearing a number.

`rubble` stays. Misattributed structure among *reached* bytes is a real quantity
and the only one that survives `shear.py`. But it is never printed alone here,
because **the two move in opposite directions**: a lane that seats yaml's lexer
moves up to 18,935 bytes out of `spoil` and into `rubble`, so the corrected
headline rises for the right reason. Known in advance this time.

**And `unbound` is a bound on the wrong question, which is what `damage` is
for.** `unbound` excludes `orphan` deliberately and correctly: an orphan byte is
a declared extra, a leaf in any parse, so charging it as "a token lying where a
tree should be" would make the column track comment density. True as a statement
about a comment. Read as a *work order* it is catastrophic, because an orphan
byte is still a byte the tree failed to place, and orphans are produced **by**
walls rather than instead of them. So the board printed one number as the
headline and a different, smaller one as the priority, and they disagreed about
who was worst by seven places:

  damage  = size - built = orphan + rubble + spoil

`damage` **redefines nothing**. It is a rollup of three of the four buckets, not
a fifth bucket, and it is the headline's own complement - `damage / size` is
exactly `1 - standing`. Everything it says, `standing` was already saying as a
share; nobody had spelled it as bytes, so nobody could sort by it. Measured
2026-08-05 over the thirty, ranking by `damage` instead of `unbound` moves
scala 15 -> 8, kotlin 8 -> 3, php 10 -> 6 and zig 16 -> 13, and demotes elixir
7 -> 12 and markdown 5 -> 9. scala is the exhibit: **104 bytes of `unbound`
standing in front of 4,150 bytes of damage, a 40x flattery**, on a grammar no
work order would ever have reached.

`unbound` keeps meaning `rubble + spoil`, because a headline that silently
redefines itself is the same crime one bucket lower. What changed is that the
order that hides orphan now says which row it is hiding, the way `--rubble`
already says which row it sinks.

**`most` is what the damage is made of**, and it is arithmetic on the three
buckets rather than a reading of anything: the bucket holding more than half,
or `mixed` when none does. It refuses a plurality that is not one - haskell is
36% spoil, 32% orphan, 32% rubble and is reported as `mixed`, where naming the
largest would have described a three-way split as a spoil problem. Grouped, it
is the pattern the board could have shown and did not: the four widest `orphan`
rows are kotlin, php, swift and scala, and all four stop on a blind external
this package cannot run, worth 39,160 bytes between them. **No grammar in
thirty has `rubble` as the plurality of its damage**, which is a standing fact
about the sort order `--rubble` offers.

**And `damage` is exactly as corruptible as the `built` it is made of.**
Measured on `picorv32.v` 2026-08-05: `--mend=keep` against `fell` moves
`damage` 63,937 -> 38,480 and `standing` 32.5% -> 59.3% while `describes` falls
22,222 -> 12,672 nodes. Twenty-five thousand bytes of work order bought by
describing 43% less. Every guard on this board except one clears it: `covered`
rises, `spoil` falls 46,613 -> 35,373, `rubble` collapses 14,057 -> 8, bare
leaves fall 2,481 -> 48, roots fall 3,544 -> 186. **Only `describes` catches
it**, so `describes` is not a footnote to `damage` - it is the other half of
reading it.

**The zero in `orphan` had three meanings and one value**, which is the defect
`inquest` was just cured of. It now carries the basis it was arrived at:

  read   extras declared and leaf roots exist - the number is a measurement
  whole  one root, no leaf roots - zero is a fact, nothing could be orphaned
  bare   the grammar declares no `extras` - zero is vacuous by construction
  void   no tree at all - every column on the row is zero and means nothing

Eleven grammars are `whole`. markdown is the only `bare` one, and its 415 bytes
of rubble are 415 bytes the metric can say nothing about, not 415 bytes of code.
yaml is `void`.

The control is `built` refusing to notice. Blank every comment in a file to
spaces, keeping the length and every offset: kotlin's `built` stays 15,319 to
the byte, its wall stays `unexpected @ at 245 in state 944` and its mend count
stays 426, while `covered` falls 91.5% -> 48.1% and `strewn` falls 17,464 ->
1,891. Same for swift (7,794 built either way, 14,134 -> 4,935) and verilog
(28,337 built either way). The comments were carrying nothing. And the five
grammars that parse whole - java, javascript, typescript, rust, json - have
*zero* leaf roots, because a healthy parse hands every comment to the one root
as a child. The effect exists only where the parse was already broken.

**And the whole board has a watermark, which is what the `generation:` line is
for.** Every column here is read off a folio, and folios are published with
`os.replace` - so a re-mint landing mid-run hands every reader a whole,
individually valid folio and leaves no torn byte to notice it by. The `cache:`
line reports what the cache **decided** when each row asked it; between that
decision and the last row sits the entire measurement. On 2026-08-05 a sibling's
`zig build` landed at 11:43:49 and something re-minted all thirty folios between
11:43:55 and 11:44:04 while this board was running and printing `cache: kept 30`.

So each artifact is digested at the moment it is read, and every one is read
again at the end. A row whose folio is still the folio on disk was measured
against what this tree holds now; a row whose folio is not is marked `SPLIT` and
named, and the totals say how many bytes of which generation they are adding
together. `--settle` re-measures exactly those rows. Exit 3 means the table is
not one measurement.

**The gate is binary and the magnitude is graded, and the board says both.**
A parse hands back one root and nothing loose, or many roots and something
loose; there is no middle, and `leaves == 0` iff `roots <= 1` over all thirty.
That is the `crown` gate in `gather.zig` (`won.ok and x.mends == 0`) seen from
the tree instead of from stderr, and it is stated in `roots` rather than in
mends on purpose - every other column here is a property of the tree that was
scored, and a mend count is a property of a stderr line from a parse nothing
guarantees was the same one. `roots <= 1` rather than `== 1` because zero mends
has two meanings and yaml is the second: it builds no tree and hands back
**zero** roots, which the mend framing cannot tell from parsing whole.

But the count does not price the bytes. php reaches 8,091 orphan bytes and 119
roots on a **single** mend over a single byte; verilog spends 3,544 roots to
reach 3,267. Across the seventeen mending rows `damage / roots` spans 26x -
scala 160 against elixir 6 - so no count on this board is a price, and a board
that reports fellings is not reporting damage. The three assertions on the
`checks:` line hold exactly this, including that both sides of the gate are
inhabited, so it cannot pass by being asked of an empty set.

**And `built` has the watermark none of the four buckets can see, because it is
not about which bucket a byte is in. It is about whether the tree over it is
RIGHT.** Every column above prices bytes the parse failed to place. A byte the
parse placed *confidently and wrongly* is scored in `built`, adds to `standing`,
and is subtracted from `damage`. Swift used to read `/* c\n d */` as a
`custom_operator` over a multiplicative expression - a comment parsed as
arithmetic - and it was one root, zero mends, zero orphan, zero rubble, zero
spoil, 100% standing. A consumer folds the wrong region with total confidence
and every instrument on this page calls it a clean success.

So `built` splits again, and this time against an outside opinion:

  built = square + crooked + soft + unaudited

  square     the derivation matches tree-sitter's, renames excused - `rack.py`
  crooked    it does not, and the disagreement is structural. **Misread.**
  soft       it does not, and the disagreement is where an EXTRA hangs. Not a
             misreading by either side, and separated for exactly that reason
  unaudited  no tree-sitter verdict over these bytes at all

`trued = square / size` is the corrected headline and `standing` is unchanged
beside it, because a headline that silently redefines itself is the crime this
file has already been fixed for twice. The two are printed together and the
drop is stated as a **correction**: the bytes were always wrong, and the board
was always counting them.

`unaudited` is subtracted from the headline but is **not** charged as damage,
and the distinction is the whole of the honesty here. tree-sitter `ERROR`s over
34,687 bytes of verilog and sql and adjudicates nothing; a byte it could not
judge is not evidence the parse was wrong, and filing it as `crooked` would be
silence-as-a-zero pointed the other way. So `trued` is a **floor** - bytes
proven right - `standing` is the ceiling, and a row where they are far apart is
a row nobody has audited rather than a row that failed.

Measured 2026-08-05 over the thirty, this is what it costs: see the `AUDIT`
block the board prints under the totals, which quotes both numbers and the
displacement between the two work orders.

**The oracle is not free and is not always there**, so it is cached rather than
run: `--audit` sweeps `rack.py` over every grammar and writes `audit.json` next
to the folios; the board reads it and matches each row against the **folio,
binary, source and ORACLE digests the verdict was computed under**. A verdict
from a different generation is not shown - the row prints `stale` and a dash,
the same fail-closed shape as `SPLIT` - and one whose tree still holds but whose
tree-sitter has moved prints `other`, which is different news. A board with no
audit at all prints `graded: none` on every row and no `trued` column, and that
is a board that has not been asked rather than a board that came back clean.

## The default order is two keys, and neither is added to the other

`crooked` is inside `built`; `damage` is `size - built`. They are complements
over the same file, so **each is blind to exactly the other** and no single key
is the work order. Ranked by `crooked`, verilog is 29th of 30 on `crooked 0`
against `damage 63,937` - the largest damaged row on the board, scored clean.
Ranked by `damage`, php is 4th on 8,699 while carrying 24,539 bytes it built and
got *wrong*. On this corpus the two orders disagree by up to 28 places.

So the default is `max(damage, crooked)` and the `by` column says which key
placed each row. `--damage` and `--crooked` still rank by one; `--standing`
keeps the old ratio default, which is blind to file size.

## Two numbers are only comparable if they were measured the same way

Not a claim the board makes about itself - a thing it will check:

  python3 tool/standing.py --twice[=N]      run me N times, diff every number
  python3 tool/standing.py --against=<json> diff this tree against a saved run
  python3 tool/standing.py --against=<json> --mine=src/press/,src/kernel/lex/x.zig
  python3 tool/standing.py --cite=<b.json> --quote=square
                                            the figure AND the world it was taken
                                            in, as one sentence off a saved board.
                                            Refuses a column the board never asked
                                            an oracle about, rather than summing
                                            thirty unmeasured zeroes into a total.
  python3 tool/standing.py --cite           one markdown line naming the binary,
                                            the tree and the oracle — what a page
                                            quoting a figure off this board owes
                                            it. Costs ~110 ms and runs no survey,
                                            because an attribution priced at a
                                            board is one nobody pays.

Both print what moved AND what the runs differed in, separately, so a `crooked`
that moved because the oracle moved is never read as a board that wanders.
`pin.py arm <name>` hands out the three exports that make an arm an arm.

`--twice` answers *is this binary's board reproducible*. It does not answer *is
this board's tree the tree I think it is*, and on a tree ten lanes edit those
diverge - two controls four minutes apart, each perfectly stable, disagreed by
63 standing points on scala because a sibling landed between them. So every
board carries a **witness**: the per-file manifest of the tree it read, folded
to one digest, recorded unbidden. A diff of two boards read from trees that
differ in a file you did not claim is **refused** and exits 4, naming the
files. `--mine=<path|dir|glob>` claims one, repeatable and comma-separable -
that is what tells your own edit from a sibling's. A board saved before this
carries no witness and is diffed as before, with a note.

And a comparison that read no `square` on either side is refused by the same
door, because `square` is the only column here that is a claim about a second
parser and an unaudited board prints `0` for it - the same value thirty
agreeing grammars print. Nineteen controlled comparisons were read as a
no-collateral clearance off that zero. Two shapes go: neither arm read a square
(nothing about agreement was established) and only one arm did (the delta is a
measurement minus a silence). `--unjudged` declares the narrow reading and
prints the label beside the numbers; it is not a way to make the sentence go
away. `pin.py oracle <pin>` is how an arm stops being square-blind.

Exit: 0 nothing moved · 1 numbers moved · 2 error · 3 the table is not one
measurement · 4 the two boards are not a comparison.

  python3 tool/standing.py            the table
  python3 tool/standing.py --json     machine output
  python3 tool/standing.py --audit    re-run the oracle sweep, then the table
  python3 tool/standing.py --set=corpus | --set=breadth
  python3 tool/standing.py --standing worst ratio first - the old default
  python3 tool/standing.py --gap      worst gap first, the original work order
  python3 tool/standing.py --rubble   worst rubble first, blind to unreached bytes
  python3 tool/standing.py --unbound  worst unbound first, blind to orphan bytes
  python3 tool/standing.py --damage   worst UNBUILT first, blind to what is misbuilt
  python3 tool/standing.py --crooked  worst MISREAD first, blind to what is unbuilt
  python3 tool/standing.py --settle[=N]  re-measure any row an artifact moved under
  python3 tool/standing.py --against=<json> --unjudged   ...scored on `damage`
                                      only, and say so on the page

  OUTLINER_WORK=<dir>                 press the folio cache somewhere else
  OUTLINER_BIN=<path>                 measure a pinned binary (`tool/pin.py`)
  OUTLINER_LANE=<tag>                 which oracle seat `--audit` consults
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import NamedTuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
import stamp  # noqa: E402
import still  # noqa: E402
from order import CACHE, GRAMMARS, Refused, folio_for, ledger  # noqa: E402
from rung1 import pairs  # noqa: E402
from walls import roster  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
BIN = Path(os.environ.get("OUTLINER_BIN", ROOT / "zig-out" / "bin" / "outliner"))
# Overridable so the mid-run-republish reproduction in `research/generation/`
# can stage the race against a cache of its own. Ten agents read the default
# one and a stage that re-minted into it would be somebody else's confusing
# afternoon; the same reason `sole.probe` builds its adverse tree in a tmpdir.
WORK = Path(os.environ.get("OUTLINER_WORK", ROOT / ".local" / "standing"))
PATIENCE = 240
# Where `--audit` leaves the oracle's opinion. Beside the folios rather than in
# a directory of its own, because a verdict is only readable against the folio
# it was computed under and the two should go stale together.
AUDIT = WORK / "audit.json"

# `--ranges --all` prints one line per node, `name [start, end)`, children
# indented under their parent. Column zero is therefore exactly the top-level
# roots, and the indent is exactly "this root has structure under it".
SPAN = re.compile(r"^(\s*)(\S.*?)\s*\[(\d+), (\d+)\)\s*$")
# The same shape, allowed to span the raw newline an anonymous node's own text
# can carry. `parse.zig`'s `quoted` escapes `"` and `\` and nothing else, so a
# token whose literal body IS a newline - verilog's directive terminator, the
# only one in this corpus - prints its closing quote on the next line.
WRAPPED = re.compile(SPAN.pattern, re.S)
# How many lines one node's name may be spread over before the join is judged a
# runaway and dropped. Two is what a single embedded newline needs; the margin
# is for a token carrying several.
STRADDLE = 8
# `1 loose, 0 disorder, 0 torn` - the three counts inside `Quire.survey`'s
# complaint. Read here so `Row.shape` can print the class that actually fired
# rather than the word `UNSOUND`, which says a row is broken and not how: the
# three fail for different reasons and a reader acts on them differently.
FAULT = re.compile(r"(\d+) (loose|disorder|torn)")
# The run kinds `rack.Seen.crooked` is made of, and the only kinds `soft` may be
# drawn from. Named here because `soft` is subtracted from `crooked` and a
# sample has to come out of the population it is charged against; `audit`
# re-derives the equality against rack's own total on every row rather than
# trusting this tuple, because it is a second copy of somebody else's
# definition and that is exactly what went wrong.
CROOKED = ("askew", "racked")


class Held(NamedTuple):
    """One grammar's oracle verdict, and the generation it was computed under.

    The four digests are the whole point. A verdict is a statement about a
    tree, a tree is what one binary made of one source through one folio, and
    all three move in this repository several times an hour. `SPLIT` exists on
    this board because a folio republished mid-run made thirty valid rows into
    one invalid table; a cached verdict is that hazard with a longer fuse, so
    it carries what it was measured against and the board refuses it when any
    of them has moved.

    **`oracle` is the fourth and it was missing.** The other three all describe
    *outliner*, and every number in this class is a comparison of two parsers.
    A sibling regenerating one grammar's tree-sitter sources moved `crooked`
    while the three digests read clean and the row printed `graded: read` -
    which is how the same pinned binary came to be quoted at 1,278 crooked in
    one run and 9,087 in the next, with nothing in either report able to say
    the two runs had asked different judges. `attest.Court.digest` is the
    identity of the judge, over `(grammar, source-tree)` pairs and the CLI
    version, and a verdict that does not carry it is not attributable.
    """

    square: int       # derivation matches the oracle's, renames excused
    crooked: int      # it does not, and the disagreement is structural
    soft: int         # it does not, and the disagreement is extras placement
    unaudited: int    # no oracle verdict over these bytes (unjudged + unwindowed)
    built: int        # what `built` was when this was computed - the identity's total
    why: str          # why there is no verdict, when there is none
    folio: str
    binary: str
    source: str
    oracle: str = ""  # which tree-sitter answered - see the docstring
    # The spines agree rung for rung, under a frame the oracle builds and we do
    # not: `<p>x</q>` is one `element` there and two roots here. `rack` grew
    # this bucket and took it out of `square`; this board did not learn about
    # it, so the partition below silently stopped totalling `built` - short by
    # 105 bytes on c, 178 on markdown (its whole file), 18,354 on php. It is
    # **not** added to `crooked` and the two must not be summed: one says the
    # derivation over a byte differs, the other says there is a node above it
    # on one side and nothing on ours. Different questions, own column.
    unframed: int = 0
    # Which run kinds `soft` was summed from, and how much each gave, as
    # `askew 56, racked 30`. The number travels with the population it came
    # out of, because `soft` is *subtracted* from `crooked` and the five-bucket
    # identity is structurally incapable of noticing when it was drawn from
    # somewhere else: soft is added in one bucket and taken out of another, so
    # it cancels whatever it is a sample of. It was drawn from `unframed` for
    # the whole life of this column, and the sum totalled `built` every time -
    # including on three boards printing a NEGATIVE count of misread bytes.
    # Empty means a verdict minted before this field existed, which `audited`
    # treats as unattributable rather than as clean when `soft` is non-zero.
    drawn: str = ""

    @property
    def graded(self) -> str:
        """Why `crooked` reads the way it does. Four causes, one column.

        `orphan`'s zero had three meanings and one value, and that defect is
        one bucket lower than this one - a `crooked` of 0 means "audited and
        clean", "the oracle refused this grammar", "there was no tree to
        audit", or "the verdict is from another generation", and those are not
        the same news. Ordered by strength of claim: `void` first because a row
        with nothing built has nothing any of the others could describe.
        """
        if not self.built:
            return "void"
        if self.why:
            return "none"      # the oracle refused, or there is no oracle here
        if self.unaudited * 2 > self.built:
            return "part"      # more than half of `built` has no verdict
        return "read"

    def matches(self, folio: str, binary: str, source: str, oracle: str) -> bool:
        """Is this verdict about the tree in front of us, judged by today's judge?

        Both halves required. A cache written before the oracle was recorded
        carries `oracle == ""`, which equals no live oracle and so is refused -
        deliberately, because "we do not know which tree-sitter said this" and
        "the wrong one did" are the same amount of evidence.
        """
        return (self.folio, self.binary, self.source, self.oracle) == (
            folio, binary, source, oracle) and bool(oracle)


# An audit ran, and it has nothing usable for this row - it was never swept, or
# its verdict was computed against a folio/binary/source that has since moved.
# Distinct from `held is None`, which means no audit ran at all: a board nobody
# has audited must not print thirty rows reading `stale`, because that spells
# "re-run me" on a tree where re-running is not what is missing.
STALE = Held(0, 0, 0, 0, -1, "", "", "", "", "")
# The verdict IS of this row's tree, and a different tree-sitter pronounced it.
# Different news from `stale`, and worth its own word: stale says the thing
# being judged moved, this says the *judge* did, which is the failure that let
# one grammar be quoted at 1,278 and 9,087 with every guard on the page green.
SWAYED = STALE._replace(why="another oracle")


class Row(NamedTuple):
    name: str
    set_: str
    size: int
    built: int
    strewn: int
    orphan: int
    roots: int
    leaves: int
    verdict: str
    declared: int  # how many `extras` the grammar declares, which `orphan` needs
    nodes: int = 0  # every node the parse printed, not just the roots - see LAST_NODES
    unsound: str = ""  # what `Quire.survey` found wrong with the forest, if anything
    # The positive half of the same clause: nodes `Quire.survey` reached, out of
    # nodes the arena held. **-1 means the parse never said it surveyed**, which
    # is `unasked` and is emphatically not `sound` - see `Row.shape`.
    walked: int = -1
    arena: int = -1
    held: Held | None = None  # the oracle's opinion, when one was cached for THIS tree

    @property
    def under(self) -> int:
        return self.built + self.strewn

    @property
    def audited(self) -> bool:
        """Is there a live verdict over this row's own `built`?

        The `built` equality is not belt-and-braces on top of the digests. A
        row can be re-measured by `--settle` after the audit was matched, and
        an audit whose four parts no longer total this row's `built` is an
        audit of a different tree however well its digests read.
        """
        h = self.held
        return h is not None and not h.why and h.built == self.built

    @property
    def crooked(self) -> int:
        """Built bytes whose DERIVATION the oracle defends as wrong. The number.

        Structural disagreement only: extras placement is `soft` and is not in
        here, because where a parser hangs a comment is an internal choice
        rather than a claim about structure, and charging it would inflate this
        by 27.7% over a difference neither parser is wrong about.
        """
        return self.held.crooked if self.audited else 0

    @property
    def soft(self) -> int:
        return self.held.soft if self.audited else 0

    @property
    def unframed(self) -> int:
        """Built bytes the oracle hangs under a frame this parse never built.

        Out of `square` because the oracle disagrees, out of `crooked` because
        the disagreement is not a derivation - see `Held.unframed`.
        """
        return self.held.unframed if self.audited else 0

    @property
    def unaudited(self) -> int:
        """Built bytes with no oracle verdict at all.

        Withheld from `trued` and withheld from `crooked` both. It is the
        oracle's silence, and this board has twice been caught reading a
        silence as a zero in whichever direction flattered the page.
        """
        return self.held.unaudited if self.audited else self.built

    @property
    def square(self) -> int:
        """Built bytes the oracle defends as RIGHT: the corrected numerator."""
        return self.held.square if self.audited else 0

    @property
    def graded(self) -> str:
        """Why `crooked` reads the way it does - and `stale` is not `none`.

        The first draft gated this on `audited`, which is false for a row the
        oracle *refused* as well as for a row whose verdict is from another
        generation - so verilog and sql, where tree-sitter's own CST and XML
        disagree and there is no verdict to be had, printed `stale` and read as
        "re-run the audit". They are the two grammars the oracle cannot judge
        at all, which is the single most important caveat on this page, and the
        column was spelling it as a cache problem.

        The second draft spelled a board with NO audit as thirty stale rows,
        for the same shape of reason one level out. `held is None` is now only
        that case, and it reads `—` alongside the `trued` it also withholds.
        """
        if self.held is None:
            return "—"
        if self.held is SWAYED:
            return "other"    # this row's tree, judged by a tree-sitter that has moved
        if self.held.built != self.built:
            return "stale"    # the verdict is real, but not of this row's tree
        return self.held.graded

    @property
    def trued(self) -> float:
        """`square / size` - the headline that does not score wrong structure.

        A FLOOR, not a replacement for `standing`. Every unaudited byte is
        outside the numerator, so a grammar tree-sitter cannot judge reads low
        here for a reason that is nothing to do with its parse. Read the pair.
        """
        return self.square / self.size if self.size else 0.0

    @property
    def shape(self) -> str:
        """Is what was built a TREE - the third axis, in one word.

        The board has two headline axes and both are unions over spans, so both
        are structurally blind to parentage. `standing` is `built / size` where
        `built` is the union of the top-level roots that have a child, and
        `tops()` throws every indented row away before the union is taken - so
        a child outside its parent contributes its bytes exactly as a
        well-placed one does. So does a child out of source order, a node
        reached twice, and a whole subtree hung under the wrong parent. That is
        not a bug in either column; it is what a union IS.

        `Quire.survey` is the one instrument that can see it, and it is the
        cheapest thing on this page: one walk, one bit per node, ten seconds
        over the corpus, no oracle. There is no argument for it living in a
        separate tool while `trued` - which costs minutes and a second parser -
        sits in the headline.

        Five words, and the two that are not verdicts are the point:

          `tree`     surveyed, and every node is reached once, inside its
                     parent, in source order
          `loose` / `disorder` / `torn`  surveyed, and it is not a tree; the
                     word is the first fault class the walk counted
          `void`     no forest at all, so there is nothing to be a tree
          `unasked`  the parse never said it surveyed. NOT `tree` - it is the
                     absence of evidence, which is what a binary that stopped
                     calling `survey` produces, and reading it as a clearance
                     is the vacuous pass three other columns on this board have
                     already been repaired for.
        """
        if self.basis == "void":
            return "void"
        if self.walked < 0:
            return "unasked"
        if not self.unsound:
            return "tree"
        worst = [w for n, w in FAULT.findall(self.unsound) if int(n)]
        return worst[0][:8] if worst else "UNSOUND"

    @property
    def rubble(self) -> int:
        """The strewn bytes that are code - misattributed structure, not damage.

        Correct over the bytes the parse reached and silent about every byte it
        did not, so it is never the whole answer. Pair it with `spoil`.
        """
        return self.strewn - self.orphan

    @property
    def spoil(self) -> int:
        """Bytes under no top-level root at all - the bucket that was counted
        nowhere. `covered` reports its share; nothing reported its weight."""
        return self.size - self.under

    @property
    def unbound(self) -> int:
        """Bytes with no structural account: `rubble + spoil`.

        An upper bound. Some spoil is comment and would have been `orphan` had
        a root reached it, but no node exists to say which, so the bound is the
        strongest honest statement available.
        """
        return self.rubble + self.spoil

    @property
    def damage(self) -> int:
        """Every byte the tree failed to place: `orphan + rubble + spoil`.

        A **rollup of three of the four buckets, not a fifth bucket**, and the
        distinction is the whole reason it is safe to add: the four still sum to
        `size`, `unbound` still means `rubble + spoil`, and nothing a previous
        measurement quoted has moved. It is `size - built`, so it is the
        headline's own complement - `damage / size` is exactly `1 - standing` -
        which is why it can be the work order without disagreeing with the
        number at the top of the page. `unbound` could not: it excludes
        `orphan`, so it ranked kotlin 8th on a grammar `standing` saw at 41%.

        Inherits every watermark `built` has, and the worst one is real: see the
        `--mend=keep` measurement in the module docstring. Read `describes`
        beside it or do not read it.
        """
        return self.size - self.built

    @property
    def clearance(self) -> bool:
        """`damage 0` with no `trued` bytes behind it - the half that flatters.

        `damage` is two different facts wearing one column. Non-zero, it is a
        charge this parser brings against itself: nobody has to corroborate it,
        it cannot flatter, and it needs no second parser to be believed. Zero,
        it is a **clearance** - and a clearance is a claim about being right,
        which is the one claim no column made out of our own forest can make.

        php, html and elixir all read `damage 0` and `standing 100.0%` on the
        audited base board. Two of them are finished. Elixir builds every byte
        of `router.ex` and derives 22,210 of them under parents tree-sitter
        does not use, 48% of the file. Fifteen rows read `damage 0` there and
        thirteen were `trued 100%`; nothing in the column said which two were
        the other kind, and `bench.report.md` quoted elixir off it as the
        rubble table's finished row.

        So the row prints the dash `crooked`, `trued` and `most` already print
        beside it, and a page that copies the row inherits the label instead of
        inheriting the zero. `--json` is untouched: a machine reading `damage`
        also reads `square`, and a diff that started rendering dashes would
        report a printer change as a board that moved.
        """
        return not self.damage and not self.square

    @property
    def most(self) -> str:
        """Which bucket the damage is mostly made of, or `mixed` when none is.

        More than half, not the largest. A plurality of 36% is not a
        description, and naming it one would report haskell's near-perfect
        three-way split (8,052 orphan · 7,945 rubble · 9,051 spoil) as a spoil
        problem and send a lane to the wrong half of it. Two of the eighteen
        damaged rows are `mixed`, so the refusal is doing work rather than
        decorating.

        Arithmetic on three printed columns, so it makes no claim the row does
        not already carry - which is deliberate. The obvious richer column is
        *what kind of wall* stands behind the damage, and that would have to be
        read off `inquest`'s stand-in name, which is a guess this project has
        already caught being wrong twice. Grouping on a guess manufactures
        families. Grouping on the buckets does not, and it is enough: sorted by
        damage inside `most`, kotlin, php, swift and scala come out as the four
        widest `orphan` rows, adjacent, each printing its own blind external.
        The board shows the pattern; it does not name it.
        """
        if not self.damage:
            return "—"
        big = max(("orphan", self.orphan), ("rubble", self.rubble), ("spoil", self.spoil),
                  key=lambda kv: kv[1])
        return big[0] if big[1] * 2 > self.damage else "mixed"

    @property
    def basis(self) -> str:
        """Why `orphan` reads the way it does - four causes, one column.

        Ordered by strength of claim, not by degeneracy, and the order is
        load-bearing: `embedded-template` declares no `extras` AND parses whole,
        so it qualifies as both `bare` and `whole`. `whole` wins because it is
        the stronger fact - with no leaf roots, zero orphans is proven whatever
        the grammar declares, where `bare` only bites when leaf roots exist and
        no declaration can ever classify them. Ordering these the other way put
        `embedded-template` in `bare` and left `whole` at ten; the corpus says
        eleven.
        """
        if not self.under:
            return "void"     # no tree: every tree-derived column is meaningless
        if not self.leaves:
            return "whole"    # no leaf roots: nothing could be orphaned, so 0 is a fact
        if not self.declared:
            return "bare"     # leaf roots but no `extras`: 0 is vacuous by construction
        return "read"

    @property
    def covered(self) -> float:
        return self.under / self.size if self.size else 0.0

    @property
    def standing(self) -> float:
        return self.built / self.size if self.size else 0.0

    @property
    def gap(self) -> float:
        return self.covered - self.standing

    def as_dict(self) -> dict:
        return {**self._asdict(), "held": self.held._asdict() if self.held else None,
                "under": self.under, "rubble": self.rubble,
                "spoil": self.spoil, "unbound": self.unbound, "basis": self.basis,
                "shape": self.shape,
                "damage": self.damage, "most": self.most,
                "covered": round(self.covered, 4),
                "standing": round(self.standing, 4),
                "gap": round(self.gap, 4),
                "square": self.square, "crooked": self.crooked, "soft": self.soft,
                "unframed": self.unframed,
                "unaudited": self.unaudited, "graded": self.graded,
                "trued": round(self.trued, 4),
                "adrift": round(self.unbound / self.size, 4) if self.size else 0.0}


def rows(text: str) -> list[tuple[int, str, int, int]]:
    """Every node the render printed, as (indent, name, start, end).

    Column zero is a root and an indent is a child, which is only true of a
    render where one node is one line. A node whose anonymous name contains a
    raw newline breaks that: its tail starts at column zero and reads as a
    second root, and - worse than the byte it miscounts - it becomes the root
    every following child is credited to. So an unterminated line is held and
    rejoined until it closes a span, and the indent is taken from the line that
    opened the node rather than the one that finished it.

    Measured 2026-08-05: nine such nodes in `picorv32.v` and none anywhere else
    in the corpus, worth nine strewn bytes of verilog's 15,090. Immaterial to
    the board, which is the finding - the split it could have discredited was
    the one that promoted verilog to first place. `quire.escape` now spells a
    control byte rather than emitting it, so the corpus no longer contains one;
    the rejoin stays because it costs nothing and a folio minted by an older
    binary still renders the old way.

    Split out of `spans` so the node count reads the same rows the spans do.
    It did not: `LAST_NODES` counted non-blank *lines* and so counted each of
    those nine nodes twice, ninety lines below the docstring naming them.
    """
    out: list[tuple[int, str, int, int]] = []
    held: list[str] = []
    for line in text.splitlines():
        if not held and not line.strip():
            continue  # a blank line opens nothing; joining onto it fakes an indent
        held.append(line)
        joined = "\n".join(held)
        if (m := (SPAN if len(held) == 1 else WRAPPED).match(joined)) is None:
            if len(held) > STRADDLE:
                held.clear()
            continue
        held.clear()
        out.append((len(m.group(1)), m.group(2), int(m.group(3)), int(m.group(4))))
    return out


def spans(text: str) -> list[tuple[str, int, int, bool]]:
    """Top-level spans as (name, start, end, has_child)."""
    return tops(rows(text))


def tops(seen: list[tuple[int, str, int, int]]) -> list[tuple[str, int, int, bool]]:
    """The column-zero rows, each carrying whether anything was indented under it."""
    out: list[tuple[str, int, int, bool]] = []
    for wide, name, a, b in seen:
        if wide:  # indented: a child of the root above it
            if out:
                n, x, y, _ = out[-1]
                out[-1] = (n, x, y, True)
            continue
        out.append((name, a, b, False))
    return out


def extras(name: str) -> set[str]:
    """What this grammar declares as an extra, by the node name the tree prints.

    Read out of the same pinned `grammar.json` the press read, because "is this
    node an extra" is the grammar's answer and not a list anybody here should be
    keeping. A `PATTERN` extra (whitespace) never closes a named node, so only
    the symbols can ever show up as a root - but taking all three shapes costs
    nothing and means a grammar that spells one differently is not silently
    misclassified.
    """
    path = GRAMMARS / f"{name}.json"
    if not path.exists():
        return set()
    got = json.loads(path.read_text())
    return {e.get("name") or e.get("value") for e in got.get("extras", ())} - {None}


def spent(drawn: dict[str, int]) -> str:
    """`{'askew': 56, 'racked': 30}` as `askew 56, racked 30`. Sorted, so two
    verdicts of the same sample are the same string."""
    return ", ".join(f"{k} {v}" for k, v in sorted(drawn.items()))


def paid(drawn: str) -> dict[str, int]:
    """...and back, for the board that has only the cache to read.

    Total on anything it cannot parse rather than raising or skipping: a
    provenance the board cannot read is a provenance it cannot certify, and
    `-1` is a width no sum of run widths can equal, so the check fails closed
    on a malformed field instead of passing over it.
    """
    out: dict[str, int] = {}
    for part in (p.strip() for p in drawn.split(",") if p.strip()):
        kind, _, wide = part.rpartition(" ")
        out[kind or part] = int(wide) if wide.isdigit() else -1
    return out


_BENCH: dict[str, str] | None = None


def bench() -> dict[str, str]:
    """Which tree-sitter would answer for each grammar right now.

    Per grammar rather than one digest over the slate, because a verdict is per
    grammar and a corpus-wide identity would invalidate twenty-nine cached rows
    every time a sibling regenerated the thirtieth. A guard that cries that
    often gets turned off, which is a worse outcome than the one it prevents.
    The CLI version rides along because the same grammar bytes lowered by two
    CLIs are two parsers.

    `attest.attribute` and not `attest.consult`: the identity is the source
    digest, and consulting additionally feeds every oracle source into the
    generation ledger and digests what `generate` wrote, which would make a
    board that asked nobody anything read scala's 28 MB `parser.c`. `--audit`
    pays that, because it really is asking tree-sitter; a board reading a cached
    verdict is only asking *who said this*.

    Seating it is the point of going through `attest` at all rather than calling
    `survey` in a loop: `still.take` reads the seated court, so the board's
    witness now carries the judge its numbers are attributed to. That field read
    `0 oracle(s)` on every board taken before this line existed, and a board's
    numbers rest on an oracle whether or not the board opened a file of it.

    Once per process, and only when something is going to check it: a board
    with no audit cache has nothing to attribute and should cost what it always
    did. Missing here is `""`, and `Held.matches` refuses an empty one, so an
    unidentifiable oracle spends a re-run of the audit rather than printing a
    number nobody can attribute.
    """
    global _BENCH
    if _BENCH is None:
        _BENCH = {}
        try:
            import attest  # noqa: PLC0415 - optional; not every checkout has an oracle
            import plumb  # noqa: PLC0415 - see `audit`: the cycle is deliberate, one-way
            slate = plumb.slate()
            seen = attest.attribute(slate)
            # Zipped rather than keyed off `row.name`: `attest` names a row for
            # the directory under `lang/`, and a monorepo grammar can put two
            # cases there (ocaml's `ocaml` and `interface`). The board's key is
            # the case's own name, and mapping through the other one would give
            # two cached rows one identity.
            for case, row in zip(slate, seen.rows, strict=True):
                if row.tree:
                    _BENCH[case.name] = f"{row.tree[:12]}/{seen.cli}"
        except (ImportError, OSError):
            pass
    return _BENCH


def marks(name: str, src: Path) -> tuple[str, str, str, str]:
    """The four digests a verdict is only true against.

    Folio, binary and source say which tree was judged; `bench` says who judged
    it. The fourth was missing for the whole life of this column and cost the
    board its only unattributed number - see `Held`.
    """
    def of(p: Path) -> str:
        try:
            return stamp.digest(p)[:16]
        except OSError:
            return "missing"
    return of(WORK / f"{name}.folio"), of(BIN), of(src), bench().get(name, "")


def audit() -> int:
    """Sweep the oracle over every grammar and write down what it said.

    Expensive - it builds and runs tree-sitter per grammar and walks two spines
    over every byte of thirty files - which is the entire reason it is a
    separate verb writing a cache instead of a column the board computes. A
    board nobody runs because it takes four minutes is a board that stops
    catching the thing it was extended to catch.

    `rack` is imported here rather than at the top because `plumb` imports THIS
    module for `tops`/`rows` - the board owns what `built` means and every
    instrument reads it from here rather than restating it. A module-level
    import would close that into a cycle; a local one keeps the dependency
    pointing the one direction it has always pointed.
    """
    import plumb  # noqa: PLC0415 - see the docstring: the cycle is deliberate, and one-way
    import rack  # noqa: PLC0415
    out: dict[str, dict] = {}
    for case in plumb.slate():
        # The read comes FIRST, and the order is the whole difference between a
        # verdict and a rumour. `marks` digests `WORK/<name>.folio`, and
        # `plumb.read` is what presses that folio - so taken beforehand, on a
        # work dir nobody has measured in yet, the digest is `missing` for every
        # grammar and the board that reads this cache back refuses all thirty
        # rows as `stale`. That is precisely the work dir `pin.py arm` hands out:
        # two of the six audit caches on this disk are 30-of-30 `folio: missing`,
        # both minted by lanes that paid the four-minute sweep inside an
        # isolation arm and got a cache that could never match.
        saw = plumb.read(case)
        if saw is None:
            continue
        folio, binary, source, oracle = marks(case.name, case.source)
        if saw.why or not saw.built:
            out[case.name] = Held(0, 0, 0, 0, saw.built, saw.why or "nothing built",
                                  folio, binary, source, oracle)._asdict()
            print(f"audit: {case.name}: {saw.why or 'nothing built'}", file=sys.stderr)
            continue
        # `top` past any plausible run count, because the soft attribution below
        # is over ALL of the crooked runs and a truncated list would understate
        # the soft share - which is the direction that shrinks `crooked` and
        # flatters this page.
        seen = rack.survey(case.name, saw, top=1 << 20)
        was = extras(case.name)
        # `rack.soft`'s rule: a crooked RUN whose bytes are blank, or whose name
        # on either side is an extra the grammar declares. Run granularity and
        # not cut - a cut-level test calls the leading spaces of a non-blank run
        # soft and quietly shrinks the number this board is about to subtract.
        # Held to rack's own total by `research/joinery/flag/spans.py check`.
        #
        # ...and drawn ONLY from the kinds `crooked` is made of, which is the
        # line this defect was. `rack.widest` returns the widest runs OF EACH
        # KIND and its docstring predicts the rest: an `unframed` run answers
        # the extra-name test whenever the frame we failed to build is named
        # `comment`, so the sample was drawn from `askew + racked + unframed`
        # and subtracted from `askew + racked`. The tally is kept per kind so
        # the population rides with the number - see `Held.drawn`.
        drawn: dict[str, int] = {}
        for w in seen.worst:
            if w.kind not in CROOKED:
                continue
            if not saw.blob[w.start:w.end].strip() or w.ours in was or w.theirs in was:
                drawn[w.kind] = drawn.get(w.kind, 0) + w.width
        soft = sum(drawn.values())
        # And the constant above is asserted rather than trusted, per row,
        # against rack's own total. `CROOKED` names a definition that lives in
        # `rack.Seen.crooked`, and a copy of a definition is how this board
        # arrived here in the first place: if rack ever counts a third kind,
        # these runs stop totalling that column and the sample silently starts
        # under-reading instead of over-drawing. Same defect, other sign.
        whole = sum(w.width for w in seen.worst if w.kind in CROOKED)
        if whole != seen.crooked:
            print(f"audit: {case.name}: DRIFT — the runs of {'+'.join(CROOKED)} total"
                  f" {whole} and `rack.Seen.crooked` reads {seen.crooked}; `soft` is a"
                  f" sample of a population this module no longer names correctly",
                  file=sys.stderr)
        out[case.name] = Held(seen.square + seen.renamed, seen.crooked - soft, soft,
                              seen.unjudged + seen.unwindowed, saw.built, "",
                              folio, binary, source, oracle, seen.unframed,
                              spent(drawn))._asdict()
        print(f"audit: {case.name}: {seen.crooked - soft} crooked · {soft} soft ·"
              f" {seen.unframed} unframed · {seen.unjudged + seen.unwindowed} unaudited"
              f" of {saw.built} built", file=sys.stderr)
    if not out:
        print("standing.py: --audit resolved no grammar to a source", file=sys.stderr)
        return 2
    AUDIT.parent.mkdir(parents=True, exist_ok=True)
    AUDIT.write_text(json.dumps(out, indent=2))
    print(f"audit: wrote {len(out)} verdict(s) to {AUDIT}", file=sys.stderr)
    return 0


def loaded() -> dict[str, Held] | None:
    """Whatever `--audit` last wrote, or `None`. Never a failure.

    A malformed or absent cache means the board prints `graded: —` and no
    `trued`, which is the truthful report of an unasked question. Refusing to
    print a board because an *optional* overlay is unreadable would be the
    stronger failure in the weaker place.

    `None` and `{}` are different answers and the caller needs both: `None` is
    "nobody has audited this tree", where every row's silence is the same
    silence, and a dict is "an audit ran", where a row missing from it is a
    fact about that row. Returning `{}` for both spelled an unaudited board as
    thirty stale rows.
    """
    try:
        got = json.loads(AUDIT.read_text())
    except (OSError, ValueError):
        return None
    try:
        return {k: Held(**v) for k, v in got.items()}
    except TypeError:
        print(f"standing.py: {AUDIT} is not the shape this board reads; re-run --audit",
              file=sys.stderr)
        return None


def union(got: list[tuple[int, int]]) -> int:
    """Bytes covered by a set of possibly-overlapping spans."""
    total, end = 0, -1
    for a, b in sorted(got):
        a = max(a, end)
        if b > a:
            total += b - a
            end = b
    return total


# How many nodes the last `ranged` parse printed, at every depth rather than just
# the roots. Module-level rather than a third tuple member because `shear.py`
# unpacks this function's return, and a column is not worth breaking a sibling's
# tool over.
#
# It exists because `built` cannot tell "more structure" from "one bigger root".
# `built` is the union of top-level spans that have at least one child, so a root
# spanning 30 KB with a single child contributes all 30 KB - and a parse that
# gives up on a token, keeps its stack, and reduces one enormous construct over
# the wreckage scores *higher* than one that reads carefully. Measured on
# picorv32.v: `--mend=keep` scores 59.3% standing against `fell`'s 32.5% and
# drops `rubble` from 14,057 to 8, while printing 10,256 nodes against 17,997 and
# naming 54 ports against 65. Three columns improved by describing 43% less. This
# is the number that catches that, so no recovery policy can be adopted on the
# strength of the board alone.
LAST_NODES = 0

# What the parse said about the shape of the forest it handed back, verbatim.
# Module-level for the same reason `LAST_NODES` is: `shear.py` unpacks
# `ranged`'s return and a third tuple member would break a sibling's tool.
#
# Read by `stamp.outcome` and carried on the `Outcome`, because the clause rides
# the stop's own line and the last `outliner:` line is the *owner*'s on every
# grammar that hit a wall - so on most of the thirty it is not on the line a
# verdict comes from. That is a fact about how the binary talks, which is the
# one thing `stamp` exists to know.
LAST_UNSOUND = ""

# And the positive half of it, for the same reason and by the same route. Two
# ints rather than a bool: `walked of held` is a claim with a size in it, so the
# board can cross-check the survey's own count of the forest against the number
# of node lines the printer wrote - two independent readings of one parse, which
# is the only corroboration available without a second parser.
LAST_WALKED = -1
LAST_ARENA = -1


def ranged(name: str, src: Path) -> tuple[list[tuple[str, int, int, bool]], str] | None:
    """One top-level `--ranges --all` parse: the spans, and what it said at the end.

    Through `stamp.ask`, which is **the only place an instrument runs outliner
    and reads its answer back**. This file used to spell that exchange itself,
    which is the fifth-reader shape `sole.py` exists to catch: sharing the rule
    did not stop a copy being written, so the whole exchange is what is shared.
    `ask(tree=True)` is exactly this - the forest flags, the same patience, the
    same timeout - and both readers were driven over all thirty grammars before
    the swap to prove they said the same thing.

    Still the single place this instrument parses anything, so a caller that
    wants the tree's own construct boundaries (`shear.py`) reads them from here.
    """
    folio = folio_for(name, WORK)
    if folio is None or not src.exists():
        return None
    got = stamp.ask(BIN, folio, src, tree=True, patience=PATIENCE)
    if got.kind == "timeout":
        return None
    global LAST_NODES, LAST_UNSOUND, LAST_WALKED, LAST_ARENA
    # One node, one row. Counted off the same rejoined rows the spans are taken
    # from, because counting non-blank lines counted a node whose own text held
    # a raw newline twice - nine of them, all verilog `"` tokens.
    seen = rows(got.tree)
    LAST_NODES = len(seen)
    LAST_UNSOUND = got.unsound
    LAST_WALKED, LAST_ARENA = got.surveyed, got.arena
    return tops(seen), got.verdict


def ask(name: str, src: Path, set_: str, seen: dict[str, Held] | None = None) -> Row | None:
    if folio_for(name, WORK) is None or not src.exists():
        return None
    size = src.stat().st_size
    was = extras(name)
    # The verdict is attached only if it was computed against **this** folio,
    # **this** binary and **this** source. Digested after `folio_for` has
    # pressed, so the folio being digested is the one the parse below will read.
    held = None if seen is None else seen.get(name, STALE)
    if held is not None and held is not STALE and not held.matches(*(got := marks(name, src))):
        # Which half moved decides which word the row prints. A verdict whose
        # three tree digests still hold and whose oracle does not is not stale
        # - the tree it describes is the tree in front of us, and re-running the
        # audit will move the number because the other parser changed its mind.
        held = SWAYED if (held.folio, held.binary, held.source) == got[:3] else STALE
    read = ranged(name, src)
    if read is None:
        return Row(name, set_, size, 0, 0, 0, 0, 0, "timeout", len(was))
    top, verdict = read
    # `built` first, then `strewn` against what `built` did not already claim: a
    # leaf standing inside a construct's span is not a second reading of those
    # bytes, and counting it twice would put `covered` above 100%.
    stands = [(a, b) for _, a, b, kid in top if kid]
    built = union(stands)
    under = union([(a, b) for _, a, b, _ in top])
    # Same subtraction one level down, and for the same reason: an extra sitting
    # inside a construct is already `built`, so `orphan` is only what the extra
    # leaves add beyond it.
    orphan = union(stands + [(a, b) for n, a, b, kid in top if not kid and n in was]) - built
    return Row(name, set_, size, built, under - built, orphan, len(top),
               sum(1 for *_, kid in top if not kid), verdict, len(was), LAST_NODES,
               LAST_UNSOUND, LAST_WALKED, LAST_ARENA, held)


def sources() -> dict[str, Path]:
    return dict(roster())


def survey(want: str) -> list[Row]:
    # Which eleven are "the corpus" comes from the corpus's own README, the same
    # place `census.py` reads it, rather than from a slice of `roster()` - the
    # roster puts them first today and a language added tomorrow would silently
    # relabel one.
    corpus = {n for n, _ in pairs()}
    keep = {"all": ("corpus", "held-out"),
            "corpus": ("corpus",), "breadth": ("held-out",)}[want]
    seen, rows = loaded(), []
    for name, src in roster():
        set_ = "corpus" if name in corpus else "held-out"
        if set_ not in keep:
            continue
        if (row := ask(name, src, set_, seen)) is not None:
            rows.append(row)
    return rows


def checks(rows: list[Row]) -> list[tuple[bool, str]]:
    """The gate, asserted rather than described, and made unable to pass vacuously.

    Three, and the third is the one that can still say no. A biconditional over
    thirty rows is worth nothing if every row sits on one side of it, so the
    second assertion exists solely to prove the first was asked of a real
    partition - a board where every grammar parsed whole would satisfy
    `leaves == 0 iff roots <= 1` by having no counterexample available.

    The third is `research/joinery/orphan/`'s finding turned into a guard: the
    gate is binary, the magnitude is not, and the two get conflated every time
    someone reports a felling count as a cost.

    **It asks whether the two ORDERS disagree, and the first draft asked for a
    spread threshold instead.** `damage / roots` spans 26x over the thirty, so
    `>= 10x` passed - and then reddened on `--set=corpus`, where the four
    mending rows are all small C-family files and the spread is 2x. That red was
    false. Ranking those same four by `roots` gives ruby, cpp, c, bash and
    ranking them by `damage` gives c, ruby, bash, cpp: not one row in the same
    place, a count routing a lane somewhere else entirely. The threshold was
    measuring the homogeneity of a sample and calling it proportionality. What
    the board needs to know is whether a count would route you where the bytes
    do, so that is what is asked, and it needs no constant - if `damage` ever
    did become proportional to `roots` the orders would coincide and this
    reddens. The spread rides along as evidence rather than as the gate.
    """
    gate = [r.name for r in rows if (r.leaves == 0) != (r.roots <= 1)]
    one = [r for r in rows if r.roots <= 1]
    many = [r for r in rows if r.roots > 1]
    priced = {r.name: r.damage / r.roots for r in many if r.damage}
    lo = min(priced.items(), key=lambda kv: kv[1], default=("", 0.0))
    hi = max(priced.items(), key=lambda kv: kv[1], default=("", 0.0))
    spread = hi[1] / lo[1] if lo[1] else 0.0
    none = [r for r in rows if not r.roots]
    # Both orders break ties on the NAME, not on the order `rows` arrived in.
    # Caught in the act: `--damage` hands this function its rows already in
    # damage order, so a stable sort by `roots` inherited that as its tiebreak
    # and the same corpus reported scala 9 places under one flag and 10 under
    # another. A displacement that depends on how you asked is not a fact about
    # the corpus, and this board has no business printing one.
    counted = {r.name: i for i, r in enumerate(sorted(many, key=lambda r: (-r.roots, r.name)))}
    weighed = {r.name: i for i, r in enumerate(sorted(many, key=lambda r: (-r.damage, r.name)))}
    off = max(((abs(counted[n] - weighed[n]), n) for n in counted), default=(0, ""))
    return [
        (not gate, f"the gate is binary: leaves==0 iff roots<=1 on {len(rows)} of"
                   f" {len(rows)} rows" + (f" — BROKEN on {', '.join(gate)}" if gate else "")
                   + f" (<=1 and not ==1: {len(none)} row(s) build no tree at all and hand"
                     f" back zero, which a mend count cannot tell from parsing whole)"),
        (bool(one) and bool(many),
         f"and not vacuous: {len(one)} row(s) at roots<=1, {len(many)} above it, so the"
         f" biconditional had a counterexample available and did not find one"),
        (len(many) > 1 and off[0] > 0,
         f"the magnitude is graded: ranking the {len(many)} mending rows by `roots` puts"
         f" {off[1]} {off[0]} place(s) from where `damage` does, and damage/roots spans"
         f" {spread:.0f}x ({hi[0]} {hi[1]:.0f} vs {lo[0]} {lo[1]:.0f}) — a count is not a price"),
        *cleared(rows),
        *shaped(rows),
        *audited(rows),
    ]


def shaped(rows: list[Row]) -> list[tuple[bool, str]]:
    """The third axis, asserted rather than printed - including that it was ASKED.

    Three, and each closes a different way this column could go quiet:

    **The wiring.** Every row that built a forest must carry a `surveyed` clause.
    A row without one is not sound, it is unlooked-at, and the difference is
    invisible in the only evidence this column had before today. This is the
    corpus-shaped half of the guard; `src/kernel/quire/survey_test.zig` holds
    the arenas that make the walk say no, and `parse.zig`'s own tests hold the
    sentence, but neither can tell you the binary in front of THIS board still
    prints it.

    **The corroboration.** The survey counts the forest from the arena, on
    stderr; the printer writes one line per node, on stdout; `rows()` counts
    those lines. Two independent readings of one parse, and they must agree. A
    walk that stopped early and a printer that dropped a subtree each break
    this, and nothing else on the page would notice either.

    **The non-vacuity.** `shape` is worth asserting only if it could have come
    out otherwise, so the third clause says how much forest was actually put
    under the walk. A board of thirty `void` rows satisfies the first two
    perfectly and has checked nothing.
    """
    built = [r for r in rows if r.basis != "void"]
    if not built:
        return []
    mute = [r.name for r in built if r.shape == "unasked"]
    # Compared over rows that answered, because an `unasked` row has no number
    # to compare and is already the first clause's business.
    seen = [r for r in built if r.walked >= 0]
    off = [f"{r.name} walked {r.walked} vs printed {r.nodes}"
           for r in seen if r.walked != r.nodes]
    walked = sum(r.walked for r in seen)
    trees = [r for r in seen if r.shape == "tree"]
    return [
        (not mute,
         f"the interior was actually looked at: {len(seen)} of {len(built)} forest-building"
         f" row(s) carry a `surveyed` clause"
         + (f" — BROKEN: {', '.join(mute)} cleared themselves on an absence" if mute else
            ", so `sound` is evidence and not the lack of a complaint")),
        (bool(seen) and not off,
         f"and two readings of the same forest agree: the survey's node count equals the"
         f" printer's on {len(seen) - len(off)} of {len(seen)} row(s)"
         + (f" — BROKEN on {' · '.join(off)}" if off else
            f" ({walked} node(s), counted once off stderr and once off stdout)" if seen else
            " — VACUOUS: no row answered, so nothing was compared and this agrees about"
            " nothing")),
        (walked > 0 and bool(trees),
         f"and not vacuous: {walked} node(s) across {len(trees)} sound forest(s) were put"
         f" under the walk, so a fault had somewhere to be found"),
    ]


def cleared(rows: list[Row]) -> list[tuple[bool, str]]:
    """`damage 0` is a clearance, and the board must not print one it cannot back.

    Two, and the second is what makes the first worth asserting. The first is
    the rendering invariant: no row shows a bare zero in `damage` without
    `square` bytes standing behind it. That one is cheap and it is checked
    against `Row.clearance` itself, so a printer that drifted away from the
    predicate reddens here rather than going quiet.

    The second is the finding, re-derived over whatever corpus is in front of
    it rather than quoted from the night it was found: **`damage 0` and
    `trued 100%` are different sets**, and the rows in the difference are named.
    On the audited base board that difference was elixir and toml - elixir
    deriving 48% of its file under parents tree-sitter does not use while every
    byte of it was `built`. A board where the two sets coincide cannot exhibit
    the trap, and says so instead of printing a green that proves nothing.
    """
    flat = [r for r in rows if not r.damage]
    if not flat:
        return []
    hid = [r.name for r in flat if r.clearance]
    stood = [r for r in flat if not r.clearance]
    # The rendering invariant, asked of the predicate the printer uses. A row
    # is allowed to print `damage 0` only where the oracle defends a byte.
    bare = [r.name for r in flat if not r.clearance and not r.square]
    # The two populations, and what separates them. `trued == 100%` is the
    # correctness set; `damage == 0` is the coverage set; a row in the first
    # and not the second is a grammar that built everything and got some of it
    # wrong, which is the whole shape this column was hiding.
    short = [f"{r.name} {r.trued * 100:.1f}%" for r in stood if r.trued < 1.0]
    got = [
        (not bare,
         f"a `damage` of zero is only printed where the oracle defends a byte:"
         f" {len(stood)} of {len(flat)} zero-damage row(s) carry `trued` bytes,"
         f" {len(hid)} print `—`"
         + (f" — BROKEN: {', '.join(bare)} printed a bare zero on no evidence" if bare else "")),
    ]
    # Silent, not red, when no zero-damage row was judged at all. A clause that
    # reddens because an optional overlay was not run teaches a reader to skip
    # the column, and this board carries sixteen gates already. The absence is
    # already loud two lines up, where all 17 rows print `—`.
    if stood:
        got.append((
            bool(short),
            f"and the two sets differ: {len(short)} row(s) build every byte and are NOT"
            f" `trued 100%` ({', '.join(short)}) — `damage 0` is coverage, `trued` is"
            f" agreement, and a board where they coincided could not show it"
            if short else
            f"and the two sets coincide on this board: all {len(stood)} corroborated"
            f" zero-damage row(s) are `trued 100%`, so nothing here exhibits the split"
            f" — an absence of counterexample rather than a clearance"))
    return got


def audited(rows: list[Row]) -> list[tuple[bool, str]]:
    """The audit's own identity, asserted on this run rather than quoted.

    Five, and they are ordered by how much of the partition each can see. The
    sum says the five buckets do not redefine `built`. The negative gate says
    no bucket is an impossibility. The **provenance** gate says each bucket is
    a count of the bytes it names, which is the one the other two cannot reach
    from either side: a sample subtracted from the wrong population leaves the
    sum alone by construction, and stays a plausible positive number until the
    overdraw happens to exceed the balance. Then the anti-vacuity guard, and
    then the digest guard.

    The anti-vacuity one is the guard the sum needs. A split that totals
    `built` on every row is trivially satisfied by a split that put everything
    in one bucket - which is exactly what an audit reading a stale or empty
    cache produces, and it would print `CHECK` while measuring nothing. So it
    asks whether the partition is inhabited on both sides.

    Silent with no audit at all. A gate that reddens because an *optional*
    overlay was not run teaches a reader to ignore it, and this board has
    fourteen gates on it already.
    """
    live = [r for r in rows if r.audited]
    if not live:
        return []
    off = [r.name for r in live
           if r.square + r.crooked + r.soft + r.unframed + r.unaudited != r.built]
    # And that no part of the partition is a negative number, which the sum
    # above cannot see: an identity is satisfied just as well by a bucket that
    # borrowed from its neighbours. `crooked` is `rack`'s crooked total less the
    # `soft` share attributed off the crooked RUNS, and on a shredded parse -
    # 1,273 top-level roots, scala with its comment row un-seated - the soft
    # attribution exceeded the total and the column read **-335**. The sum
    # checked out, so this gate passed a board reporting negative misread bytes.
    under = [f"{r.name} {what} {got}" for r in live
             for what, got in (("square", r.square), ("crooked", r.crooked),
                               ("soft", r.soft), ("unframed", r.unframed),
                               ("unaudited", r.unaudited)) if got < 0]
    # And that `soft` is a count of the bytes IT names, which is the property
    # neither assertion above reaches. The sum cannot: `soft` is added to one
    # bucket and subtracted from another, so it cancels whatever population it
    # was sampled from. The negative gate cannot either: it fires once an
    # overdraw has grown past the balance it was drawing on, so it caught
    # scala's -8,669 and certified six rows understated by up to 34% - always
    # in the flattering direction, because a bucket can only borrow *down*.
    # What identifies both is provenance: every kind `soft` was summed from
    # must be a kind `crooked` counts, and the widths must total the `soft`
    # this row printed. Neither half is a threshold.
    borrow, mute = [], []
    for r in live:
        if r.held is None:
            continue
        got = paid(r.held.drawn)
        if stray := sorted(k for k in got if k not in CROOKED):
            borrow.append(f"{r.name} drew {sum(got[k] for k in stray)} of"
                          f" {'+'.join(stray)}")
        elif r.soft and not r.held.drawn:
            # A charge with no population recorded at all - a verdict minted
            # before `soft` carried one. Its own clause rather than fourteen
            # copies of one sentence, and only a row that spent something needs
            # to answer: a `soft` of zero has nothing to attribute.
            mute.append(r.name)
        elif sum(got.values()) != r.soft:
            borrow.append(f"{r.name} names {sum(got.values())} against soft {r.soft}")
    clean = [r for r in live if not r.crooked]
    dirty = [r for r in live if r.crooked]
    # The guard on the newest column, re-derived rather than asserted in a
    # dossier. Each live row's verdict is offered back with one of its four
    # digests replaced, and `matches` must refuse all four - so a run cannot
    # print `graded: read` under a guard that has quietly stopped checking
    # something. The oracle is the one that was missing and it is checked here
    # like the other three, because the way this project loses a guard is by
    # adding a field and not adding the case that would notice it was ignored.
    held = [(r, r.held) for r in live if r.held is not None]
    kept = {what: [r.name for r, h in held
                   if h.matches(*[("moved" if k == what else v) for k, v in
                                  (("folio", h.folio), ("binary", h.binary),
                                   ("source", h.source), ("oracle", h.oracle))])]
            for what in ("folio", "binary", "source", "oracle")}
    leak = {w: who for w, who in kept.items() if who}
    return [
        (not off, f"the audit splits `built` and does not redefine it: square + crooked +"
                  f" soft + unframed + unaudited == built on {len(live)} of {len(live)}"
                  f" audited rows"
                  + (f" — BROKEN on {', '.join(off)}" if off else "")),
        (not under,
         f"and every part of it is a count: no negative bucket on {len(live)} of"
         f" {len(live)} audited rows"
         + (f" — BROKEN: {', '.join(under)}; the sum identity above cannot see"
            " this, because a bucket that borrowed from its neighbours still"
            " totals `built`" if under else "")),
        (not borrow and not mute,
         f"and `soft` is drawn from the population it is charged against:"
         f" {'+'.join(CROOKED)} and nothing else, on {len(live)} of {len(live)}"
         f" audited rows"
         + (f" — BROKEN: {', '.join(borrow)}. Both gates above pass on this —"
            " the sum cancels `soft` whatever it sampled, and a bucket can only"
            " borrow DOWN, so the count stays plausible until the overdraw"
            " exceeds the balance" if borrow else "")
         + (f" — BROKEN: {len(mute)} row(s) charge a `soft` naming no population"
            f" ({', '.join(mute)}); minted before this field existed, so re-run"
            " `--audit`" if mute else "")
         + ("; the two gates above are blind to this, which is how six rows"
            " stood understated by up to 34% with every check green"
            if not borrow and not mute else "")),
        (bool(clean) and bool(dirty),
         f"and not vacuous: {len(clean)} audited row(s) carry no crooked byte and"
         f" {len(dirty)} do, so the oracle distinguished them rather than filing"
         f" every row the same way"),
        (not leak,
         f"a verdict is refused when ANY of its four digests moves — folio, binary,"
         f" source and ORACLE — on {len(held)} of {len(held)} live verdicts"
         + ("".join(f" — BROKEN: a moved {w} still matched on {', '.join(who)}"
                    for w, who in leak.items()) if leak else
            "; the fourth is why the same pin could be quoted at 1,278 and 9,087")),
    ]


def tally(rows: list[Row]) -> None:
    """What each grammar's damage is made OF, grouped so a pattern can print itself.

    The board reported four disjoint buckets and a rank, and a lane still had to
    find by hand that kotlin, php and scala were 31,842 orphan bytes behind three
    blind string-interior externals. Nothing here was hidden - it was spread over
    three columns and eighteen rows in an order that put those three 8th, 10th
    and 15th. Grouping by `most` and sorting by `damage` inside it puts them
    adjacent with their walls beside them, and swift - handed back by that same
    lane as the same defect class - lands between them where it belongs.

    The tail is the verdict, truncated and not parsed. It is `inquest`'s line,
    whose **owner** word is trustworthy and whose bracketed stand-in name is a
    guess; both are printed verbatim so a reader can tell which is which, and
    nothing here branches on either.
    """
    hurt = [r for r in rows if r.damage]
    if not hurt:
        return
    seen: dict[str, list[Row]] = {}
    for r in hurt:
        seen.setdefault(r.most, []).append(r)
    print(f"\ndamage by what it is made of — {sum(r.damage for r in hurt)} bytes over"
          f" {len(hurt)} of {len(rows)} grammars, and the groups total it exactly")
    # Both sorts break ties on the NAME. `damage` is unique per group today, so
    # nothing moves - but `checks()` shipped with exactly this hole and printed
    # a different displacement under `--damage` than under the default sort,
    # because a stable sort inherits the display order it was handed as its
    # tiebreak. A grouping that reorders itself when you change how you asked
    # for it is this board's own defect one bucket lower.
    for what, mine in sorted(seen.items(), key=lambda kv: (-sum(r.damage for r in kv[1]), kv[0])):
        print(f"  {what:<7}{sum(r.damage for r in mine):>8}  over {len(mine)} grammar(s)")
        for r in sorted(mine, key=lambda r: (-r.damage, r.name)):
            print(f"    {r.name:<18}{r.damage:>8}{r.orphan:>8}{r.rubble:>7}{r.spoil:>8}"
                  f"  {r.verdict[:78]}")
    # A bucket that is never anybody's plurality is a fact about the sort order
    # offered for it, and it is only visible from up here. Stated as a count so
    # it stops being true the moment it stops being true.
    print(f"  {'rubble':<7}{sum(r.damage for r in seen.get('rubble', ())):>8}  over"
          f" {len(seen.get('rubble', ()))} grammar(s) — `--rubble` sorts by a bucket that is"
          f" the plurality of nobody's damage")
    # The rows this table drops, and why dropping them silently is the trap.
    # Every grammar absent from the block above is absent because it read
    # `damage 0`, and that is exactly the population where the zero means two
    # different things. Named here so the block cannot be quoted as "these are
    # the damaged ones and the rest are finished".
    flat = [r for r in rows if not r.damage]
    if flat:
        hid = [r for r in flat if r.clearance]
        thin = [f"{r.name} {r.trued * 100:.0f}%" for r in flat
                if not r.clearance and r.trued < 1.0]
        print(f"  {'(none)':<7}{0:>8}  over {len(flat)} grammar(s) reading `damage 0`,"
              f" which is not one fact: {len(flat) - len(hid)} have `trued` bytes"
              f" behind the zero and {len(hid)} print `—` because nobody asked"
              + (f"\n{'':11}of the corroborated ones, {len(thin)} build every byte and"
                 f" still are not `trued 100%`: {', '.join(thin)}" if thin else ""))


def corrected(rows: list[Row]) -> None:
    """The headline, and the headline it corrects, side by side.

    Printed as a **correction and not a regression**, because nothing here got
    worse: the misread bytes were always misread and the board was always
    scoring them. The only thing that changed is that it stopped.

    Two numbers rather than one, and the second is not decoration. `trued` puts
    every unaudited byte outside the numerator, so it is a floor - the bytes
    proven right. `standing - crooked/size` is the ceiling - everything not
    proven wrong. A row where the two are far apart has not been audited; a row
    where they are close has been, and the number means what it says.
    """
    live = [r for r in rows if r.audited]
    if not live:
        print(f"\n{'AUDIT':<18}no live oracle verdict for any of these {len(rows)} rows —"
              f" `--audit` has not run against this tree.\n{'':18}`trued` is not printed,"
              f" because a board that never asked is not a board that came back clean.")
        return
    size = sum(r.size for r in rows)
    built = sum(r.built for r in rows)
    square = sum(r.square for r in live)
    crook = sum(r.crooked for r in live)
    soft = sum(r.soft for r in live)
    blind = sum(r.unaudited for r in live) + sum(r.built for r in rows if not r.audited)
    print(f"\nAUDIT — `built` against tree-sitter's derivation, over {len(live)} of"
          f" {len(rows)} rows ({sum(r.built for r in live)} of {built} built bytes)")
    print(f"  {square} square + {crook} crooked + {soft} soft + {blind} unaudited"
          f" = {built} — the four are disjoint and total `built`")
    print(f"  {'was':<8}{built / size * 100:>6.1f}% standing   `built / size`, which scores a"
          f" confidently wrong tree exactly like a right one")
    print(f"  {'now':<8}{square / size * 100:>6.1f}% trued      `square / size` — bytes whose"
          f" DERIVATION the oracle defends. A floor.")
    print(f"  {'':8}{(built - crook) / size * 100:>6.1f}% at most    everything not proven"
          f" wrong. The {blind} unaudited bytes are between the two and are neither.")
    print(f"  {'':8}{crook / size * 100:>6.1f}% of the corpus is built, counted, and WRONG —"
          f" {crook} bytes,\n{'':10}{crook / built * 100:.1f}% of `built`, and no column on this"
          f" board could see one of them before now.")
    print(f"  {soft} further crooked bytes are extras placement — where a comment hangs is a"
          f" parser's\n{'':2}choice, not a claim about structure, so they are separated and"
          f" NOT charged. Quote {crook}, never {crook + soft}.")
    worst = sorted(live, key=lambda r: -r.crooked)[:5]
    print("widest by CROOKED " + " · ".join(f"{r.name} {r.crooked}" for r in worst)
          + "\n" + " " * 18 + "← the order the other five are blind to: these bytes are"
          " inside `built` and out of `damage`")
    # The row where being wrong costs more than failing. Not an anecdote - the
    # whole claim of this block is that `damage` is the wrong work order for
    # some rows, and a claim like that is worth nothing without the counts.
    over = sorted((r for r in live if r.crooked > r.damage), key=lambda r: -r.crooked)
    print(f"{'crooked > damage':<18}{len(over)} row(s)"
          + (": " + " · ".join(f"{r.name} {r.crooked} vs {r.damage}" for r in over[:5])
             + "\n" + " " * 18 + "← confidently wrong cost more than visibly failing, and"
                                 " `--damage` ranks by the smaller one" if over else
             " — `--damage` still ranks every row by its larger fault"))


def table(rows: list[Row], order: str, split: frozenset[str] = frozenset()) -> None:
    key = {"gap": lambda r: -r.gap, "rubble": lambda r: -r.rubble,
           "unbound": lambda r: -r.unbound, "damage": lambda r: -r.damage,
           "crooked": lambda r: -r.crooked, "worst": lambda r: -max(r.damage, r.crooked),
           "": lambda r: r.standing}[order]
    rows = sorted(rows, key=key)
    # `gap` left the table when `spoil` and `unbound` joined it: it is
    # `cover - stand` and both are still printed, where the new pair is derivable
    # from nothing on the row. It is still in `--json` and still a sort order.
    # `damage` sits beside `unbound` and not beside `built`, because the whole
    # finding is that those two are different numbers and a reader who cannot see
    # them in one glance will keep taking the smaller one for the work order.
    # `unjudg` rides beside `crooked` and not in a footnote. `graded` says why
    # the oracle is quiet over a row; it never said HOW MUCH, and a word cannot,
    # because its `read` covers a row with 14% of `built` unadjudicable as
    # readily as one with none. Three lanes spent a day optimising verilog while
    # every byte of it was unjudged and this page said `stale` in one column and
    # nothing anywhere else. The number is the part that cannot be skimmed past.
    # Said on the board's own face, above the numbers, and not only in the
    # `AUDIT` block below them. 28 of the 33 boards on this disk had never read
    # a `square` byte and not one of them said so where a reader skimming for a
    # row would see it, which is how the blindness spread by inheritance rather
    # than by anybody's decision.
    if not any(r.audited for r in rows):
        print(f"\nUNSIGHTED — no row below has an oracle verdict, so every column here is"
              f" outliner's own words about\n{'':12}outliner's own forest. `--audit` buys"
              f" `trued`; until then a `damage` of zero is not a clearance.")
    # Three axes, and they are the three columns in the middle: `stand` is
    # coverage at the root frontier, `shape` is whether what stands is a tree,
    # `trued` is whether the tree agrees with another parser. Printed adjacent
    # and never combined - a fused number blending the three is precisely the
    # instrument this board has spent the week dismantling, and each answers a
    # question the other two structurally cannot. A row can be 100% standing,
    # `loose`, and unaudited; another can be 41% standing, `tree`, and trued on
    # every byte it built. The board used to render both the same.
    print(f"\n{'grammar':<19}{'set':<9}{'bytes':>8}{'cover':>7}{'stand':>7}{'shape':>9}"
          f"{'trued':>7}"
          f"{'built':>8}{'crooked':>8}{'unjudg':>8}{'by':>4}{'graded':>7}"
          f"{'strewn':>7}{'orphan':>7}{'basis':>7}{'rubble':>7}{'spoil':>8}{'damage':>8}"
          f"{'most':>7}{'unbound':>9}{'adrift':>7}{'roots':>6}{'leaves':>7}  where it stops")
    print("-" * 210)
    for r in rows:
        # A tree-derived column on a `void` row is a zero nothing measured, which
        # is the shape this round exists to abolish. Print the dash and let
        # `spoil` and `unbound` - which need no tree - carry the row.
        num = (lambda v: f"{v:>7}") if r.basis != "void" else (lambda _: f"{'—':>7}")
        orph = f"{r.orphan:>7}" if r.basis in ("read", "whole") else f"{'—':>7}"
        # `crooked` on an unaudited row is a dash and not a zero, for the exact
        # reason `orphan` grew a `basis` column: the value 0 would mean "clean"
        # and "nobody asked" with one glyph, and this board has been caught on
        # that shape at three different depths now.
        seen = r.audited
        # `damage 0` is a clearance and a clearance needs a second parser — see
        # `Row.clearance`. A non-zero damage is a charge against ourselves and
        # prints whatever the audit did or did not say.
        dmg = f"{'—':>8}" if r.clearance else f"{r.damage:>8}"
        print(f"{r.name:<19}{r.set_:<9}{r.size:>8}{r.covered * 100:>6.1f}%"
              f"{r.standing * 100:>6.1f}%"
              + f"{r.shape:>9}"
              + (f"{r.trued * 100:>6.1f}%" if seen else f"{'—':>7}")
              + f"{r.built:>8}" + (f"{r.crooked:>8}" if seen else f"{'—':>8}")
              # `unaudited` falls back to the whole of `built` on an unaudited
              # row, which is true and is the point: a row nobody could judge
              # prints its entire `built` here rather than a dash, so the two
              # ways of having no verdict are told apart by `graded` and are
              # both loud on the face.
              + (f"{r.unaudited:>8}" if seen else f"{r.built:>8}")
              # Which of the two keys placed this row. A two-keyed order that
              # will not say which key spoke is a fused score wearing a
              # disguise, and this board has been fooled by a single number
              # standing in for two questions four times.
              + f"{('crk' if r.crooked > r.damage else 'dmg') if order == 'worst' else '':>4}"
              + f"{r.graded:>7}"
              + f"{num(r.strewn)}{orph}{r.basis:>7}"
              f"{num(r.rubble)}{r.spoil:>8}" + dmg + f"{r.most:>7}"
              f"{r.unbound:>9}{r.unbound / r.size * 100:>6.1f}%"
              f"{r.roots:>6}{r.leaves:>7}  {r.verdict[:30]}"
              # No ` · UNSOUND` tail any more: `shape` above carries it, and
              # carries the fault CLASS where the tail carried only a flag. The
              # counts and the first fault are in the `sound` footer, which is
              # the one place they fit.
              # Marked on the row rather than only in the footer, because the
              # footer is what a reader skips and the row is what a report
              # quotes. A row measured against a folio this tree no longer
              # holds is not comparable with the row beneath it.
              + (" · SPLIT" if r.name in split else ""))

    size = sum(r.size for r in rows)
    built = sum(r.built for r in rows)
    under = sum(r.under for r in rows)
    orphan = sum(r.orphan for r in rows)
    rubble = under - built - orphan
    spoil = size - under
    # Three tallies, one per axis, named for what each is - and then the
    # intersection, which is the only one of the four that means what a reader
    # hears when they read "N of 30 grammars parse whole".
    #
    # `whole` has always meant *one root over every byte*, a coverage fact, and
    # four pages read it as a correctness fact. `agreed` split the correctness
    # half off it. Neither says anything about the INTERIOR: `built` is a union
    # of root spans and `tops()` discards every indented row before taking it,
    # so a child outside its parent, a child out of source order, a node reached
    # twice, and an entire subtree under the wrong parent all contribute their
    # bytes exactly as well-placed ones do. toml read `100% standing, 0 damage`
    # while holding a loose child for as long as anyone had looked, and the only
    # reason that was ever noticed is that a census kept a second copy of the
    # walk.
    #
    # So the third tally is the shape one, and the fourth is the conjunction.
    # NOT a score - four counts of four different populations, each printed with
    # the question it answers, because a single fused number blending coverage,
    # shape and agreement is the instrument this board keeps being repaired for.
    whole = [r for r in rows if r.roots == 1]
    agreed = [r for r in rows if r.audited and r.trued >= 1.0]
    asked = [r for r in rows if r.audited]
    trees = [r for r in rows if r.shape == "tree"]
    mute = [r for r in rows if r.shape == "unasked"]
    # The conjunction, and it is deliberately over rows that were ASKED all
    # three questions. A row nobody audited is not perfect on three axes; it is
    # perfect on two and silent on the third, which is the distinction the whole
    # page exists to keep.
    trine = [r for r in whole if r in trees and r.audited and r.trued >= 1.0]
    print(f"\n{len(rows)} grammars · {len(whole)} reached whole (one root over every byte,"
          f" no gap by construction)\n{'':13} "
          f"{len(trees)} surveyed sound (every node reached once, inside its parent, in"
          f" source order)"
          + (f", {len(mute)} UNASKED" if mute else "")
          + f"\n{'':13} "
          + (f"{len(agreed)} agreed whole (`trued` 100% — the oracle defends every byte),"
             f" over the {len(asked)} row(s) it judged" if asked else
             "agreed whole — unasked: no oracle judged a byte of this board"))
    print(f"{'':13} {len(trine)} whole on ALL THREE — coverage, shape and agreement are"
          f" different questions and this is\n{'':15}"
          f" the only count that means what `{len(whole)} parse whole` sounds like"
          + (f": {', '.join(r.name for r in trine)}" if trine and len(trine) <= 16 else "")
          if asked else
          f"{'':13} whole on all three — unasked: with no oracle the third axis is silent,"
          f" so this cannot be counted")
    # Print the identity, not the fragment. Every byte of the corpus is in
    # exactly one of these four, so a reader cannot take one of them for the
    # damage without noticing what it is being subtracted from.
    print(f"bytes: {built} built + {orphan} orphan + {rubble} rubble + {spoil} spoil"
          f" = {size} — the four are disjoint and total")
    if split:
        # The identity above is a sum, and a sum does not care that its terms
        # came from two different trees. Say it here, next to the number a
        # report repeats, and not only in the stamp four lines down.
        bad = [r for r in rows if r.name in split]
        print(f"       ⚠ {len(bad)} of these {len(rows)} rows were measured against an"
              f" artifact this tree no longer holds ({', '.join(r.name for r in bad)}),"
              f"\n         so the totals above add {sum(r.size for r in bad)} bytes of one"
              f" generation to {size - sum(r.size for r in bad)} of another. Re-run, or"
              f" `--settle` to re-measure just those rows.")
    print(f"       {built / size * 100:.1f}% standing · {under / size * 100:.1f}% covered ·"
          f" {(rubble + spoil) / size * 100:.1f}% UNBOUND ({rubble + spoil} bytes with no"
          f" structural account)")
    print(f"       rubble is misattributed structure among the {under} bytes the parse REACHED;"
          f"\n       spoil is the {spoil} it never did. Neither is the damage on its own,"
          f" and they move opposite ways.")
    # Name the grammars carrying it rather than leaving a reader to sort the
    # table - and name it four times, because the orders disagree about who is
    # worst. `strewn` puts kotlin second and php sixth on a comment budget;
    # `rubble` is the same question asked about code but only where the parse
    # arrived; `unbound` is the question asked about the file, minus orphan;
    # `DAMAGE` is the whole of it, and it is the one that agrees with the
    # headline three lines up.
    crook = sum(r.crooked for r in rows)
    # `damage` was the work order while `built` was one number. It stopped being
    # the whole of it the day `crooked` split `built`, because the two partition
    # the file between them: what damage cannot see is exactly what crooked can.
    # So the claim is spent the moment there is an audit to spend it against.
    for what, get in (("DAMAGE", lambda r: r.damage), ("strewn", lambda r: r.strewn),
                      ("rubble", lambda r: r.rubble), ("UNBOUND", lambda r: r.unbound)):
        worst = sorted((r for r in rows if r.roots > 1 or r.spoil), key=lambda r: -get(r))[:5]
        print(f"widest by {what:<8}" + " · ".join(f"{r.name} {get(r)}" for r in worst)
              + (("  ← half the work order: `size - built`, blind to the "
                  f"{crook} bytes built wrong" if crook else
                  "  ← the work order: `size - built`, so `1 - standing` in bytes")
                 if what == "DAMAGE" else
                 "  ← excludes orphan, so it is the same question about a smaller file"
                 if what == "UNBOUND" else ""))
    share = sorted(rows, key=lambda r: -r.unbound / r.size if r.size else 0)[:5]
    print(f"{'worst share':<18}" + " · ".join(f"{r.name} {r.unbound / r.size * 100:.0f}%"
                                              for r in share)
          + "  ← disagrees with the line above; both are the work order")
    # Every order that is blind to a bucket names the row it sinks hardest,
    # against the order that can see it. Not the widest row - the widest one may
    # top both orders and then the caution proves nothing. The demotion is the
    # whole point, and it is what `--unbound` never said: it sank scala to 15th
    # on 104 bytes while 4,046 orphan bytes stood behind it.
    blind = {"rubble": ("unbound", lambda r: -r.unbound,
                        lambda r: f"{r.rubble} rubble hiding {r.spoil} bytes the parse never"
                                  f" reached", f"the {spoil} unreached bytes"),
             "unbound": ("damage", lambda r: -r.damage,
                         lambda r: f"{r.unbound} unbound standing in front of {r.damage} bytes"
                                   f" of damage, {r.damage / max(r.unbound, 1):.0f}x",
                         f"the {orphan} orphan bytes"),
             # `damage` is now a blind order too, and it is the one the board
             # has been calling THE work order. It is `size - built`, so every
             # misread byte is on the wrong side of it by construction.
             "damage": ("crooked", lambda r: -r.crooked,
                        lambda r: f"{r.damage} damage in front of {r.crooked} bytes it built"
                                  f" and got wrong",
                        f"the {crook} bytes built WRONG"),
             # And the converse, which is the half nobody had written down.
             # `crooked` is a subset of `built` and `damage` is `size - built`,
             # so the two are **complements over the same file** and each is
             # blind to exactly the other. A survey ranked by `crooked` put
             # verilog 29th of 30 on `crooked 0` against `damage 63,937` - the
             # largest damaged row on the board, scored clean. That zero is not
             # wrong (verilog's damage is unbuilt, and `crooked` measures
             # misbuilt) which is precisely why a single key cannot be the work
             # order: the right answer to the wrong question still routes a
             # lane to the wrong grammar.
             "crooked": ("worst", lambda r: -max(r.damage, r.crooked),
                         lambda r: f"{r.crooked} crooked in front of {r.damage} bytes it"
                                   f" never built at all",
                         f"the {sum(r.damage for r in rows)} bytes never BUILT")}
    if not crook:
        # Without a live audit `--crooked` ranks a column of zeros, and the
        # caution would name a displacement nothing measured.
        blind.pop("damage")
        blind.pop("crooked")
    if order in blind:
        better, rank, why, what = blind[order]
        here = {r.name: i for i, r in enumerate(rows)}
        there = {r.name: i for i, r in enumerate(sorted(rows, key=rank))}
        sunk = max(rows, key=lambda r: here[r.name] - there[r.name])
        print(f"\n  NOTE: sorted by `{order}`, which is blind to {what}."
              f"\n  {sunk.name} ranks {here[sunk.name] + 1} here and {there[sunk.name] + 1} by"
              f" `{better}` — {why(sunk)}.\n  Use --{better} for the work order.")
    if order == "worst" and crook:
        # The two-keyed order has to justify itself on this corpus rather than
        # in a docstring: how far apart the two single-key orders actually are,
        # and which rows each one would have buried. If they ever agree, the
        # extra key is dead weight and this line will say so.
        one = {r.name: i for i, r in enumerate(sorted(rows, key=lambda r: (-r.damage, r.name)))}
        two = {r.name: i for i, r in enumerate(sorted(rows, key=lambda r: (-r.crooked, r.name)))}
        gap = max(rows, key=lambda r: abs(one[r.name] - two[r.name]))
        lift = [r.name for r in rows if r.crooked > r.damage]
        print(f"\n  NOTE: two keys, `max(damage, crooked)`, and the `by` column says which one"
              f"\n  placed each row. They are complements — `crooked` is inside `built` and"
              f"\n  `damage` is `size - built` — so each is blind to exactly the other, and on"
              f"\n  this corpus they disagree by up to {abs(one[gap.name] - two[gap.name])}"
              f" places ({gap.name}: {one[gap.name] + 1} by damage,"
              f" {two[gap.name] + 1} by crooked)."
              f"\n  {len(lift)} row(s) cost more wrong than missing and are placed by `crooked`:"
              f" {', '.join(lift) or 'none'}."
              "\n  Neither number is added to the other; --damage and --crooked still rank by one.")
    if order == "damage":
        # `damage` is `size - built` and `built` rises when roots get BIGGER, so
        # this order is bought outright by a recovery policy that keeps its stack
        # and reduces one construct over the wreckage. Measured, not feared:
        # `--mend=keep` on picorv32.v moves damage 63,937 -> 38,480 while
        # `describes` falls 22,222 -> 12,672. Every other guard on this page
        # clears it - covered rises, spoil falls, rubble collapses, bare leaves
        # fall - so the caution has to name the one column that does not.
        print("\n  NOTE: sorted by `damage`, which is `size - built` and inherits every way"
              "\n  `built` can rise by describing LESS. `--mend=keep` buys 25,457 bytes of this"
              "\n  order on picorv32.v alone while printing 9,550 fewer nodes, and only"
              "\n  `describes` catches it — not covered, not spoil, not rubble, not bare leaves."
              "\n  Read the `describes` line below against any change that moves this one.")
    # The denominator none of the byte columns have. `built` is the union of
    # top-level spans that have a child, so it rises when roots get *bigger* and
    # cannot tell that from structure being found - a parse that abandons tokens
    # and reduces one huge construct over them scores better on three columns at
    # once. Printed beside them so a change that moves bytes the right way and
    # this the wrong way is visible as the regression it is.
    print(f"{'describes':<18}{sum(r.nodes for r in rows)} nodes over {len(rows)} grammars"
          " — a policy that lifts `built` while lowering this is reading less, not more")
    # Whether what was described is a tree at all. Every byte column above is a
    # union over spans, and a union is silent about parentage - a child outside
    # its parent contributes its bytes to `built` exactly as a well-placed one
    # does. `Quire.survey` runs on every parse and says so in the verdict; this
    # is where the board reads it, because a check whose only reader is a
    # terminal is the shape this project has now caught fourteen times.
    # ... and it now says how many nodes it walked to find out, because until
    # 2026-08-06 the only evidence behind this line was the ABSENCE of a
    # complaint - which is also what a binary that stopped calling `survey`
    # prints. `parse.zig` says `surveyed N of M nodes` on every parse for that
    # reason, and a row that does not is `unasked` here rather than counted
    # clean. One row on this corpus was already being counted clean that way:
    # yaml has no lexable terminal, never parses, and had been contributing to
    # `30 of 30 sound` on the strength of saying nothing.
    bad = [r for r in rows if r.shape not in ("tree", "void", "unasked")]
    mute = [r for r in rows if r.shape == "unasked"]
    void = [r for r in rows if r.shape == "void"]
    walked = sum(r.walked for r in rows if r.walked > 0)
    print(f"{'sound':<18}"
          + (f"{len(bad)} of {len(rows)} UNSOUND — "
             + " · ".join(f"{r.name}: {r.unsound}" for r in bad) if bad else
             f"{len(rows) - len(mute) - len(void)} of {len(rows)} grammars hand back a"
             f" tree, over {walked} node(s) walked")
          + (f" · {len(void)} built no forest ({', '.join(r.name for r in void)})"
             if void else "")
          + (f" · {len(mute)} UNASKED: no `surveyed` clause, so this board has NO evidence"
             f" about {', '.join(r.name for r in mute)} — rebuild, then check"
             f" `verdict` in src/surface/face/outliner/parse.zig" if mute else ""))
    tell = {}
    for r in rows:
        tell.setdefault(r.basis, []).append(r.name)
    print("\norphan basis: " + " · ".join(
        f"{k} {len(v)}" + (f" ({', '.join(v)})" if k in ("bare", "void") else "")
        for k, v in sorted(tell.items())))
    # The orphan mechanism, asserted on this run rather than quoted from the
    # dossier that found it. A board that reports a finding is a report; a board
    # that re-derives it every time is an instrument, and this project has now
    # caught twenty-two of the first kind.
    for ok, said in checks(rows):
        print(f"{'CHECK' if ok else '**BROKEN**':<18}{said}")
    corrected(rows)
    tally(rows)


# Columns that are a fact about the RUN rather than about the parse, so a diff
# does not report them as movement. `held` is unrolled into the four identity
# fields below it and reported separately; the rest are derived and would say
# the same thing twice.
NOISE = frozenset({"held"})


def facts(got: dict) -> dict[tuple[str, str], object]:
    """One run's every printed number, keyed by (grammar, column)."""
    return {(r["name"], k): v for r in got.get("row", ())
            for k, v in r.items() if k not in NOISE}


def parts(got: dict) -> dict[tuple[str, str], str]:
    """What each row was measured *from*: the four digests behind its verdict.

    Read out of the cached verdict rather than recomputed, because the question
    is what the run in the file was looking at, and that run is over.
    """
    out: dict[tuple[str, str], str] = {}
    for r in got.get("row", ()):
        for k, v in (r.get("held") or {}).items():
            if k in ("folio", "binary", "source", "oracle"):
                out[(r["name"], k)] = v
    return out


def comparable(runs: list[dict], names: list[str], mine: tuple[str, ...]) -> bool:
    """Were these boards read against the same tree, and if not, which files?

    `--twice` asks *is this binary's board reproducible*. It does not ask *is
    this board's tree the tree I think it is*, and on a tree ten lanes edit
    those diverge: two controls four minutes apart were each perfectly stable
    under `--twice` and disagreed by 63 standing points on scala, because a
    sibling had landed between them. Reproducibility is a property of a moment;
    the board was reporting it as a property of a change.

    So every board now carries the per-file manifest of the tree it read, and a
    diff of two boards is refused when their trees differ in a file the lane
    has not claimed. `still.differ` draws the line - claimed is declared,
    unclaimed-and-test-only is a note, unclaimed-and-build-bearing sinks it.

    A board saved before boards carried witnesses is not refused, it is
    reported as unwitnessed. Every file on disk today is one of those, so the
    gate arrives switched off and switches itself on as boards are saved, with
    no flag day for the three lanes measuring right now.
    """
    seen = [still.revive(r["witness"]) if isinstance(r.get("witness"), dict) else None
            for r in runs]
    if blind := [n for w, n in zip(seen, names, strict=False) if w is None]:
        print(f"\n  ⚠ {len(blind)} of these boards carries no witness"
              f" ({', '.join(blind)}), so nothing below can say whether the two"
              " trees were the same one. Boards saved from here on do.")
    kept = [(w, n) for w, n in zip(seen, names, strict=False) if w is not None]
    bad, fields = False, set()
    for (x, a), (y, b) in zip(kept, kept[1:], strict=False):
        # `inert` because the board's evidence is its own numbers, and `spread`
        # below already says whether they moved. `still.vacuous` asks whether
        # the *artifacts* moved, which for a scanner seating is the wrong object
        # - that is the sixth case, and firing it here would restage it.
        rows = still.differ(x, y, mine=mine,
                            varying=("binary",) if x.binary != y.binary else (),
                            inert=True)
        # Two runs of the *same bytes* is `--twice`: a reproducibility question,
        # not a comparison. A source tree that moved under a fixed binary cannot
        # have moved a number on this board - the binary is what the board reads
        # through, and it did not change - so that is a note about provenance and
        # not a defect in the pair. Demoted rather than dropped, because it is
        # still true and a lane reading a stale binary should see it said.
        #
        # The strict reading would refuse here, and it would refuse on nearly
        # every unpinned `--twice` this tree runs, which is the direction the
        # brief warns makes the gate unusable. The falsifier's claim is *these
        # differ in something undeclared that could have moved the numbers*, and
        # under one binary the source tree is not that thing.
        if x.binary == y.binary:
            rows = [r._replace(verdict="warn", said=r.said + " — but both runs"
                               " ran the same bytes, so this could not have moved"
                               " a number here")
                    if r.field == "subject" and r.verdict == "refuse" else r
                    for r in rows]
        for r in rows:
            if r.verdict != "declared":
                print(f"  {a} vs {b}: {r.line().removeprefix('still: ')}")
        fields |= {r.field for r in rows if r.verdict in ("refuse", "vacuous")}
        bad |= still.sank(rows)
    if bad:
        # The oracle is deliberately NOT demoted the way `subject` is above. One
        # binary means the source tree could not have moved a number here; it
        # does not mean the oracle could not, because `crooked` comes out of a
        # cache whose rows are accepted only while the identity that produced
        # them holds. Two runs of one binary under two oracles is exactly the
        # comparison this gate exists to stop.
        judge = "different oracles" if "oracle" in fields else ""
        print(f"\nNOT COMPARABLE — these boards were read against different trees"
              f"{' AND ' + judge if judge else ''}, and the rows above are ones this"
              "\ncomparison did not claim. Whatever moved below, it is not only what"
              "\nyou changed. Claim a file with `--mine=<path|dir|glob>` if it IS"
              "\nyour change; an oracle difference is not claimable and means one of"
              "\nthese two numbers was measured by a parser the other never met.")
    return not bad


def sighted(got: dict) -> int:
    """`square` this board actually read, over rows whose verdict was live.

    Summed off the rows rather than off the cache, because the cache is what
    was offered and the row is what was accepted - a board holding thirty
    verdicts it refused as `stale` has read no square at all, and that is the
    case this exists to catch.
    """
    return sum(r.get("square", 0) for r in got.get("row", ())
               if r.get("graded") in ("read", "part"))


def unjudged(runs: list[dict], names: list[str], declared: bool) -> bool:
    """Does this comparison say anything about agreement with the other parser?

    `square` is the only column here that is a claim about a second parser, and
    it comes off a per-work-dir `audit.json`. The third house rule gives every
    arm a work dir of its own - so the discipline that makes two numbers
    comparable is exactly what empties the column, and it empties it to **zero**,
    which is the same value a board prints when thirty grammars agree perfectly.
    Nineteen controlled comparisons were run and read as a no-collateral
    clearance on that zero.

    Two shapes are refused and they are different news:

      **square-silent** - no board on either side read a square. Whatever moved
      below, both arms are outliner's own words about its own forest, and a
      change can leave `built` untouched while moving every leaf to a different
      parent. This is not a defect in the boards; it is a comparison that has
      not been given the instrument its conclusion needs.

      **one-eyed** - one side read a square and the other did not. Worse, and
      quieter: the delta between a measurement and a silence is neither, and it
      prints as an enormous improvement. One retained pair on this disk is
      exactly this - an arm at 311,540 square against a control whose thirty
      verdicts were all refused as stale.

    Silent when the runs share a binary, matching `comparable`'s reasoning for
    demoting `subject`: `--twice` asks whether a board is reproducible and makes
    no claim about agreement, so a gate that reddened it would be a gate lanes
    learn to pass.

    `--unjudged` declares the narrow reading rather than buying silence: the
    label is printed with the numbers so it travels with them into whatever
    reads this next. That is what the previous audit had to reconstruct three
    lanes later from an empty column.
    """
    if len(runs) < 2:
        return False
    binaries = {r.get("stamp", {}).get("build", "") or
                (r.get("witness") or {}).get("binary", "") for r in runs}
    if len(binaries) < 2:
        return False
    saw = [sighted(r) for r in runs]
    if all(saw):
        return False
    blind = [n for n, s in zip(names, saw, strict=False) if not s]
    one_eyed = any(saw)
    said = ("UNJUDGED (declared)" if declared else "NOT A CLAIM ABOUT AGREEMENT")
    if one_eyed:
        print(f"\n{said} — one side of this comparison read a square and the other"
              f"\ndid not ({', '.join(blind)} read none). The difference between a"
              "\nmeasurement and a silence is neither of them; whatever the oracle"
              "\ncolumns show below is the shape of the missing audit, not of your"
              "\nchange.")
    else:
        print(f"\n{said} — no board here read a single square byte, so nothing"
              "\nbelow is a claim about agreement with tree-sitter. `built` and"
              "\n`damage` are outliner's own words about its own forest, and a"
              "\nchange can leave both untouched while moving every leaf to a"
              "\ndifferent parent.")
    if not declared:
        print("Give each arm its own oracle - `python3 tool/pin.py oracle <pin>` -"
              "\nor declare the narrower reading with `--unjudged`, which labels the"
              "\ncomparison instead of silencing this.")
    return not declared


def spread(runs: list[dict], names: list[str], mine: tuple[str, ...] = (),
           declared: bool = False) -> int:
    """Say what moved across a set of runs, and be the exit code.

    The whole instrument, and it is deliberately one function: the answer a
    lane needs is a list of columns that are not a constant, and everything
    else here is presentation. Zero moved is exit 0 and is the only clean
    result - a board whose numbers are not a function of its inputs cannot
    support a before/after, however good the change under it was.
    """
    keys = sorted({k for r in runs for k in facts(r)})
    moved = {k: seen for k in keys
             if len(seen := [facts(r).get(k) for r in runs]) and len(set(map(repr, seen))) > 1}
    # Movement in the inputs is reported beside movement in the answers, and
    # never folded into it. A `crooked` that moved because the oracle moved is
    # a comparable pair of numbers about two different questions; a `crooked`
    # that moved with every digest held is the board being nondeterministic,
    # and those two want opposite responses from the reader.
    swung = {k: seen for k in sorted({k for r in runs for k in parts(r)})
             if len(seen := [parts(r).get(k) for r in runs]) and len(set(map(repr, seen))) > 1}
    rowed = len({k[0] for k in keys})
    cols = len({k[1] for k in keys})
    print(f"\n{len(runs)} run(s) · {rowed} grammar(s) × {cols} column(s)"
          f" = {len(keys)} number(s) compared")
    for i, (r, name) in enumerate(zip(runs, names, strict=False)):
        led, was = r.get("generation", {}), r.get("stamp", {})
        # The source tree the binary was built from, not the path it sits at. A
        # path is not a version - that is what `pin.py` exists to say - and two
        # runs of two different pins print the same path under `OUTLINER_BIN`.
        print(f"  [{i + 1}] {name[:26]:<28}tree {was.get('tree', '?'):<14}"
              f"built {was.get('built', '?'):<22}"
              f"{'one generation' if led.get('uniform', True) else 'SPLIT'}")
    # Whether the runs are comparable at all, said once and plainly, because
    # `MOVED` under two different binaries means the opposite of `MOVED` under
    # one. A mixed board is not a measurement whichever way its numbers read.
    trees = {r.get("stamp", {}).get("tree", "?") for r in runs}
    if torn := [n for r, n in zip(runs, names, strict=False)
                if not r.get("generation", {}).get("uniform", True)]:
        print(f"  ⚠ {len(torn)} of these runs spanned two generations ({', '.join(torn)});"
              " nothing below is one measurement.")
    print(f"  {'one binary — anything that moved is the board' if len(trees) == 1 else
             f'{len(trees)} binaries — what moved may be the change under test'}")
    # Asked before the numbers are shown, because a reader who has already read
    # a delta has already formed the claim this would have refused.
    torn_tree = not comparable(runs, names, mine)
    # And asked in the same place for the same reason: an empty oracle column is
    # indistinguishable from a perfect one, so a reader who has reached the
    # deltas has already read `crooked 0` as agreement.
    mute = unjudged(runs, names, declared)
    if swung:
        print(f"\n{len(swung)} input(s) differ between these runs — anything below that moved"
              "\nmay have moved for this reason rather than for the reason you are testing:")
        for (row, what), seen in sorted(swung.items()):
            print(f"  {row:<19}{what:<8}" + " → ".join(str(s)[:22] for s in seen))
    if not moved:
        print(f"\nSTABLE — every one of the {len(keys)} numbers is identical across all"
              f" {len(runs)} runs.")
        return 4 if torn_tree or mute else 0
    print(f"\nMOVED — {len(moved)} of {len(keys)} numbers are not the same in every run,"
          f" over {len({k[0] for k in moved})} grammar(s):")
    for (row, col), seen in sorted(moved.items()):
        print(f"  {row:<19}{col:<10}" + " → ".join(str(s)[:18] for s in seen))
    # 4 rather than 1, because a lane's script tells them apart: 1 is *your
    # numbers moved*, which is the answer a before/after is asking for, and 4 is
    # *there is no before/after here*. Overloading one code would make a refusal
    # read as a result.
    return 4 if torn_tree or mute else 1


def rerun(argv: list[str], times: int) -> int:
    """Run this board `times` times as separate processes, and diff the lot.

    Separate processes and not a loop over `survey`, because half of what makes
    a number move lives outside the survey: the folio cache decides once per
    process, `accepts` memoises once per process, the oracle is identified once
    per process, and a second pass inside one interpreter would inherit all
    three and report stability it did not test. A lane comparing two runs is
    comparing two processes, so that is what this compares.
    """
    keep = [a for a in argv[1:]
            if not a.startswith(("--twice", "--against", "--json", "--mine", "--unjudged"))]
    runs = []
    for i in range(times):
        got = subprocess.run([sys.executable, __file__, *keep, "--json"],
                             capture_output=True, text=True)
        try:
            runs.append(json.loads(got.stdout))
        except ValueError:
            print(f"standing.py: run {i + 1} of {times} printed no board"
                  f" (exit {got.returncode})\n{got.stderr.strip()[-400:]}", file=sys.stderr)
            return 2
    return spread(runs, [f"run {i + 1}" for i in range(times)], claims(argv),
                  "--unjudged" in argv)


def claims(argv: list[str]) -> tuple[str, ...]:
    """The files this lane says are its own change, for the tree comparison.

    A file, a directory, or a glob - see `still.claimed`. Repeatable, and
    comma-separable, because the shape a lane reaches for is
    `--mine=src/press/,src/kernel/quire/` and a flag that refuses that is a flag
    whose list stays empty.
    """
    return tuple(x for a in argv if a.startswith("--mine=")
                 for x in a.split("=", 1)[1].split(",") if x)


def against(argv: list[str], was: Path) -> int:
    """Diff this tree's board against one somebody saved, inputs included."""
    try:
        before = json.loads(was.read_text())
    except (OSError, ValueError) as exc:
        print(f"standing.py: cannot read {stamp.here(was)}: {exc}", file=sys.stderr)
        return 2
    keep = [a for a in argv[1:]
            if not a.startswith(("--twice", "--against", "--json", "--mine", "--unjudged"))]
    got = subprocess.run([sys.executable, __file__, *keep, "--json"],
                         capture_output=True, text=True)
    try:
        now = json.loads(got.stdout)
    except ValueError:
        print(f"standing.py: this tree printed no board (exit {got.returncode})"
              f"\n{got.stderr.strip()[-400:]}", file=sys.stderr)
        return 2
    return spread([before, now], [stamp.here(was), "this tree"], claims(argv),
                  "--unjudged" in argv)


# A corpus total is a sum, and only some columns are ones. A rate is a rate of
# something and does not add up over rows; a verdict word is not arithmetic. The
# refusal is the point: a lane asking to quote `trued` corpus-wide is asking for
# a number that does not exist, and inventing one for it is how a board starts
# lying politely.
SUMMABLE = ("size", "built", "square", "crooked", "soft", "unframed",
            "damage", "rubble", "spoil", "orphan", "unbound", "roots", "leaves")
# Columns that are a claim about a SECOND parser. Summing one over a board that
# never asked gives a real integer made entirely of zeroes nobody measured -
# which is the `damage 0` trap in a different column, arriving by addition.
ASKED = ("square", "crooked", "soft", "unframed", "graded")


def quote(at: Path, column: str) -> int:
    """One board, one column, one sentence a page can carry.

    The figure and the world it was taken in, rendered together and inseparably,
    because every failure this closes is a failure of the two travelling apart.
    Reads a saved `--json` board rather than measuring, so it costs milliseconds
    and can be run against a board taken an hour ago - which is exactly the
    case that goes wrong when a lane does it by hand.
    """
    try:
        board = json.loads(at.read_text())
        rows_, seen = board["row"], still.Witness(**{
            k: v for k, v in board["witness"].items()
            if k in still.Witness._fields})
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(f"standing.py: {stamp.here(at)} is not a board: {exc}", file=sys.stderr)
        return 2
    if column not in SUMMABLE:
        print(f"standing.py: `{column}` does not add up over rows. Summable: "
              f"{', '.join(SUMMABLE)}", file=sys.stderr)
        return 2
    # Built bytes an oracle actually adjudicated. Arithmetic rather than a
    # vocabulary check, because `graded` is a word and a word list has to be
    # kept complete to stay honest; this one is exact whatever the board calls
    # its verdicts.
    judged = sum((r.get("built") or 0) - (r.get("unaudited") or 0) for r in rows_)
    if column in ASKED and judged <= 0:
        print(f"standing.py: no oracle judged a byte of this board, so its "
              f"`{column}` is a sum of {len(rows_)} unmeasured zeroes and not "
              f"a figure.\n            Re-take it with `--audit` before "
              f"quoting it.", file=sys.stderr)
        return 2
    total = sum(r.get(column) or 0 for r in rows_)
    over = (f"over {judged:,} adjudicated byte(s) in {len(rows_)} row(s)"
            if column in ASKED else f"over {len(rows_)} row(s)")
    print(f"`{column}` reads **{total:,}** {over} — {seen.cite()}")
    return 0


def main(argv: list[str]) -> int:
    if "--help" in argv or "-h" in argv:
        print(__doc__)
        return 0
    if (col := next((a.split("=", 1)[1] for a in argv
                     if a.startswith("--quote=")), "")):
        board = next((a.split("=", 1)[1] for a in argv
                      if a.startswith("--cite=")), "")
        if not board:
            print("standing.py: --quote needs the board it is quoting: "
                  "--cite=<board.json> --quote=square", file=sys.stderr)
            return 2
        return quote(Path(board), col)
    want = next((a.split("=", 1)[1] for a in argv if a.startswith("--set=")), "all")
    if want not in ("all", "corpus", "breadth"):
        print(f"standing.py: --set must be all, corpus or breadth, not {want!r}", file=sys.stderr)
        return 2
    if not BIN.exists():
        print(f"standing.py: no binary at {BIN}", file=sys.stderr)
        return 2
    if "--audit" in argv and (bad := audit()):
        return bad
    # Before the survey, because both of these ARE surveys - several of them,
    # each in its own process, and running one here first would only add a
    # board nobody diffed.
    if (at := next((a.split("=", 1)[1] for a in argv if a.startswith("--against=")), "")):
        return against(argv, Path(at))
    if "--cite" in argv:
        # No survey. A lane quoting a figure needs the world it was taken in,
        # not the figure re-measured, and an attribution that costs a 30-second
        # board is an attribution that gets skipped. This is the supply side of
        # `sighting.py --gate`: the gate refuses a page that names no tree, and
        # a refusal with no cheap remedy beside it is a gate that gets disabled.
        #
        # `bench()` first, and it is not optional. Skipping the survey also
        # skipped the only call that seats a court, so the line this command
        # exists to mint said `**no oracle** — outliner's own words` on every
        # arm ever cited, including one whose board printed `30 oracle(s)
        # d85e736fa attributed` in the same terminal. It costs 0.35 s, reads no
        # `parser.c` (see `bench`), and `verdicts` in the witness is what keeps
        # seating a court from becoming the opposite claim on a blind arm.
        bench()
        print(still.take(os.environ.get("OUTLINER_LANE") or "board", BIN, WORK).cite())
        return 0
    if any(a == "--twice" or a.startswith("--twice=") for a in argv):
        many = next((int(a.split("=", 1)[1]) for a in argv if a.startswith("--twice=")), 2)
        if many < 2:
            print("standing.py: --twice needs at least 2 runs to compare", file=sys.stderr)
            return 2
        return rerun(argv, many)
    mark = stamp.take(BIN)
    try:
        rows = survey(want)
    except Refused as e:
        # The one thing worth refusing to print a board for. Every column here
        # is derived from a folio, so a binary that will not read its own is not
        # a row's problem - it is every number on the page.
        print(f"standing.py: {e}", file=sys.stderr)
        return 2
    if not rows:
        print("standing.py: no grammar resolved to a source", file=sys.stderr)
        return 1
    rows, led = settle(rows, tries(argv))
    # After the survey, not before: the artifact field is whatever this run
    # actually read, and before the survey it has read nothing. Costs one
    # `world.json` read for a pinned binary and ~90 digests for the tree's own,
    # which is milliseconds - cheap enough that no board has an excuse to skip
    # it, which is the entire design constraint. Kept unbidden, because a
    # witness a lane has to remember to record is a witness the pairs that
    # needed it will not have.
    seen = still.take(os.environ.get("OUTLINER_LANE") or "board", BIN, WORK)
    still.keep(seen)
    if "--json" in argv:
        # The checks ride the machine output too. A gate whose only reader is a
        # terminal is the shape this project has caught fourteen times, and this
        # board's own footer says so four lines from here about `Quire.survey`.
        # The exit code is deliberately left alone: 3 already means "not one
        # measurement", and a broken invariant is a different fault from a split
        # table - overloading one code would make them indistinguishable to the
        # caller that has to tell them apart.
        print(json.dumps({"stamp": mark.as_dict(), "cache": dict(CACHE),
                          "generation": led.as_dict(), "witness": seen.as_dict(),
                          "check": [{"held": ok, "said": said} for ok, said in checks(rows)],
                          "row": [{**r.as_dict(), "split": r.name in led.rows}
                                  for r in rows]}, indent=2))
        return 0 if led.uniform else 3
    # The default is the two-keyed order, and it falls back to the single key it
    # can measure. A board with no audit has `crooked == 0` on every row, where
    # `max(damage, crooked)` IS `damage` - so the default degrades to the old
    # work order exactly, rather than to a column of zeros. `--standing` keeps
    # the ratio order this used to open with; it is blind to file size, which is
    # why it is no longer what a reader gets without asking.
    table(rows, "rubble" if "--rubble" in argv else "gap" if "--gap" in argv
          else "unbound" if "--unbound" in argv else "damage" if "--damage" in argv
          else "crooked" if "--crooked" in argv else "" if "--standing" in argv
          else "worst", frozenset(led.rows))
    # What the board was actually read off. On 2026-08-05 eleven of these were
    # folios this binary refused, and the board said `built` was down 98,247
    # bytes rather than that it had failed to open eleven of its own inputs.
    print(ledger())
    print(mark.line())
    print(seen.line())
    # A mixed board is not a bad day in a lane and it is not a parser fault, so
    # it is not exit 1 or exit 2. It is a table that is not one measurement, and
    # a caller piping this somewhere has to be able to tell that from a table
    # that is - which is the whole shape of defect this file keeps being fixed
    # for. Exit 3 says "read it, but do not compare it".
    return 0 if led.uniform else 3


def tries(argv: list[str]) -> int:
    """How many times to re-measure the rows a mid-run publish overtook.

    Zero by default, and that is a judgement rather than an omission. Restarting
    the whole board would throw away twenty-nine good rows because one folio
    moved, and in a tree ten agents rebuild continuously an unbounded restart
    has no reason to ever terminate. Re-measuring only the named rows converges
    on exactly the run that produced them, and it is bounded, so it can fail to
    settle and say so rather than spin.
    """
    for a in argv:
        if a == "--settle":
            return 2
        if a.startswith("--settle="):
            return int(a.split("=", 1)[1])
    return 0


def settle(rows: list[Row], rounds: int) -> tuple[list[Row], stamp.Ledger]:
    """Re-measure the rows an artifact moved under, up to `rounds` times."""
    led, src = stamp.reconcile(), {}
    for _ in range(rounds):
        if led.uniform:
            break
        src = src or sources()
        again = set(led.rows)
        print(f"standing.py: re-measuring {len(again)} row(s) whose artifact moved"
              f" mid-run: {', '.join(sorted(again))}", file=sys.stderr)
        rows = [ask(r.name, src[r.name], r.set_) or r if r.name in again else r
                for r in rows]
        led = stamp.reconcile(again=True)
    return rows, led


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
