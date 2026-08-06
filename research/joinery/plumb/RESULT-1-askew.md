# Result 1 — how much of `built` is built wrong

**9.24% of `built` is regrouped** — 33,634 of 363,987 bytes that outliner and
tree-sitter cut apart differently. **97% of it is one grammar**, and **97% of
that grammar's share traces to one unlexable token.**

So the brief's fear is real and its shape is not what the brief guessed. This
is not diffuse rot across thirty grammars. It is one defect, in php, with a
mechanism, a specimen, and a fix that is somebody's afternoon.

Measured on pin `plumb` (`dfc481e49`, tree `bd7b3e939`), oracle tree-sitter
0.26.11, 2026-08-05.

## The number

```
built 363,987 = 222,024 plumb
              +  33,634 regrouped    9.24% of built  ← the answer
              +     794 relabelled   0.22%
              +   1,268 renamed      0.35%
              +  71,580 interstice  19.7%
              +  34,687 unjudged      9.5%
```

The five partition `built` exactly. `built + orphan + rubble + spoil =
526,798` and `standing = 69.09%` read exactly what they read before this lane
existed; nothing above is subtracted from anything.

**Regrouped** is the class the brief opened on: the two parsers disagree about
where one token ends and the next begins. A comment read as arithmetic is
regrouped. **Relabelled** is same bytes, same cuts, different name, with no
`ALIAS` in the grammar to account for it — a compatibility defect, not a byte
read wrong. **Renamed** is the same thing where the grammar *does* declare the
alias, so it is not even a defect in the tree, only in what a `highlights.scm`
would key on.

Three denominators, because the honest one is arguable and hiding that would
be the twenty-fourth instrument:

| | share | what it says |
|---|---|---|
| 33,634 / 363,987 | **9.24%** | of everything the board calls `built` |
| 33,634 / 257,720 | **13.05%** | of the bytes the oracle could actually adjudicate |
| 33,634 / 526,798 | **6.38%** | of the corpus |

The middle one is the least flattering to outliner and the most defensible:
34,687 built bytes have no oracle verdict at all, and counting silence as
agreement is the exact move this board has been caught on twice.

**Upper bound.** If every unjudged byte were also wrong: **68,321 bytes,
18.77% of `built`**. That is the defended ceiling; the floor is 9.24%.

## Where it is

```
grammar     built  regrouped+relabelled  share of judged
php        59,146      32,615                  68.7%
haskell     9,192         648                   9.0%
cpp           997         464                  58.4%
ocaml      14,696         287                   3.1%
swift      23,131         117                   0.6%
scala      15,957          80                   0.5%
...all others combined                        <  100 bytes each
```

Remove php and the corpus reads **1,813 misread bytes, 0.7% of judged**. The
headline is one grammar wearing a corpus-sized number.

## The mechanism, and why a blind external costs 3,400× its own bytes

php declares 12 externals and seats **none**. One of them is
`encapsed_string_chars` — the *body of a double-quoted string*. So php cannot
lex `"x"`. Outliner says so itself, unprompted:

```
unexpected (?:\?[^'\]+) at 12 in state 68
[no stand-in for encapsed_string_chars, admitted by shift]
```

That alone would cost a few bytes. What it actually costs is everything after
it, because of where the mender lands. `text` is php's node for inline HTML
**outside** `<?php`, and its rule is `[^\s<][^<]*` at precedence 1 — it
matches almost anything, for almost any distance. So the cheapest repair after
the derail is *"the rest of this file is HTML"*, and `text` takes it.

In `Str.php`: the first double-quoted string is at byte **26,850**
(`preg_replace("/(.*)\s.*/", ...)`). Everything from there to EOF — **40,995
bytes** — becomes one `text` node. `program` is a top-level node with a child,
so the board counts all of it `built`. php scores **87.2% standing** while
more than half of what it claims to have read is filed as raw HTML.

**That is the whole finding in one sentence: the recovery does not orphan the
remainder, it claims it.** Honest failure would have put those bytes in
`orphan` and dropped php's standing to ~40%. Describing them wrong scored them
as a win — exactly the asymmetry the brief predicted, now with a mechanism.

## Contradicting the brief

**Swift's comment is not the problem.** It is real — it reproduces, the red
tripwire is built on it, and it costs 12 bytes in the specimen. In the corpus
it costs **117 misread bytes of 19,207 judged, 0.6%**. Swift is *sixth*. The
observation that opened this lane is sound as an observation and would have
been a footnote as a finding.

**And 1,096 of swift's 1,213 askew bytes are not defects at all.** They are
method names outliner resolves to `type_identifier` where tree-sitter leaves
`simple_identifier`, and swift's own grammar declares that `ALIAS`. My first
draft folded those in and swift came out second-worst in the corpus on a
defect that misreads nothing. Splitting `renamed` off is the single change
that most moved this report's conclusions.

**The brief's guess about where to look second was right.** "A grammar seating
zero externals is the most likely place for wrongly-claimed bytes to hide…
php is 6th on the damage board and it seats zero." That is the whole answer,
and it was in the brief.

## Does the board need a column?

**Yes, and it is already there and costs nothing.** `plumb.py board` prints
`standing.py`'s rows with five columns spliced in, and closes with three
checks it fails on:

```
CHECK  the four buckets still total the corpus: 526798 bytes
CHECK  the split totals `built` on every row it judged: 363987 bytes
CHECK  and it judged every built byte the board has: 363987 of 363987
```

`built`, `orphan`, `rubble`, `spoil`, their sum, `standing` and `damage` are
read from `standing.py` and reprinted unmodified. The scope the split walks is
`standing.tops(standing.rows(...))` — the board's own function, not a
restatement — because two instruments that each define `built` are two
instruments that will eventually disagree about it.

**I did not touch `standing.py`.** A reader who wants the old board gets the
old board, byte for byte. Every measurement taken today stays comparable.

## Predictions: four held, four failed

| | called | outcome |
|---|---|---|
| P1 | askew ≥ 2% of built | **HELD** — 9.46% |
| P2 | swift is not the largest contributor | **HELD** — php, by 279× |
| P3 | a 100%-standing grammar carries nonzero askew | **HELD** — go 8, python 5 |
| P4 | askew top-3 and damage top-3 share ≤ 1 grammar | **HELD** — exactly 1 (haskell) |
| P5 | the oracle misses ≥ 5 of 30 grammars | **FAILED** — 3 |
| P6 | my instrument lies first, on javascript | **FAILED** — see below |
| P7 | unjudged > askew | **FAILED** — 34,687 vs 35,696 |
| P8 | html out-askews c+ruby+bash+cpp | **FAILED** — html 0, those four 555 |

**P6 is the one worth reading.** The falsifier I named was "javascript reads 0
askew on the first numeric run", and javascript read 0. By its own terms the
prediction failed. But the *claim* — that my instrument would lie first, in
the direction that made my work look necessary — held, by a route I had not
imagined: the first run of the red tripwire reported **0 askew on the Swift
comment and called it a pass**, because `measure()` looked the folio up by the
row's *label* (`swift-comment`) instead of its *grammar* (`swift`), found
none, returned `None`, and the assertion read `None` as clean. An instrument
built to catch describing-wrong spent its first run describing a known-wrong
tree as right. It was caught only because I had written down in advance what
that case must say.

I am scoring P6 **failed** rather than claiming the spirit held, because
choosing which reading of my own prediction to grade against is the move this
whole lane exists to catch.

**P7 is knife-edge and I am scoring it against the definition I wrote, not
the one I invented later.** As written, `askew` was one category; it totals
35,696, so unjudged is smaller and P7 failed by 1,009 bytes. Under the
`misread`/`renamed` split I introduced *after* writing it, unjudged (34,687)
exceeds misread (34,428) by 259 and P7 would hold. Refining a category after
seeing the data and then grading with the refinement is not a prediction.

## Limits of the oracle, stated

1. **34,687 built bytes have no verdict** (9.5%). verilog (30,720) and sql
   (3,967) refuse because tree-sitter's own parse contains `ERROR` — for
   `picorv32.v` the ERROR is the **root**, spanning the whole file. The
   corpus's #1 damage row is a file the oracle itself cannot parse with the
   pinned grammar. That is a fact about the pin, not about outliner, and it
   means outliner's 30,720 built bytes there are compared against nothing.
2. **A byte-indexed comparison undercounts structural misreadings** — see
   below. This is the big one.
3. **Interstitial bytes are not judged on name.** 71,580 bytes sit under an
   oracle *interior* node rather than a leaf; outliner elides hidden rules and
   invents alias nodes, so a difference there can be node shaping. They are
   reported separately (60,816 agree, 10,764 differ) and never folded in.
4. **The oracle is a pin, not a truth.** Where outliner's `grammar.json` and
   the generated tree-sitter parser came from different commits, a legitimate
   difference reads as a defect. The `renamed` class removes the one form of
   this I could detect mechanically; others may remain.

## The instrument I trust least — mine

**`plumb` compares two trees and calls one wrong, and its number is a floor
for a reason I can demonstrate rather than hedge about.**

`research/joinery/specimen/go/selector-field.go` is the exhibit. go is 1,189
bytes, 1,189 built, **100.0% standing, 0 damage** — every instrument here
scores it perfect. Outliner reads `fmt.Print("x")` as a
`type_conversion_expression` over a `qualified_type`: not "call Print with x"
but "convert x to the type fmt.Print". Tree-sitter reads `call_expression` over
`selector_expression`. Opposite meanings, same file.

**`plumb` scores that file at 5 misread bytes out of 996.** Five — the length
of `Print`, the only *leaf* whose name moves. Every other byte sits under a
leaf both parsers agree on, so a byte-indexed comparison files them `plumb`,
which is the word my own instrument uses for *correct*.

That is the structural blind spot, and it is the same shape as the one this
lane was opened to expose. `built` cannot see a wrong tree because a wrong
tree is still a tree. `plumb` cannot see a wrong *shape* because the leaves
underneath it are still the right leaves. I chose byte-indexing deliberately —
outliner returns a forest on 18 of 30 grammars and aligning 3,544 roots is a
guess — and the cost of that choice is that **9.24% is a floor whose ceiling I
have not measured**. A tree-aligned comparison is the next lane, and it will
report a larger number than this one.

Two smaller ones. `plumb` is only as good as the `built` scope it walks, which
it takes from `standing.tops` — if that is wrong, so is this, and the two will
agree while both being wrong. And `verify` proves the comparison can say *no*
on a Swift comment and *yes* on javascript; it does not prove it says the
right thing on the twenty-eight grammars in between.

## Handover

Three specimens, all failing today, all carrying tree-sitter's answer rather
than outliner's:

- **`php/double-quoted-string.php`** — 6 claims. php cannot lex `"x"`;
  `encapsed_string_chars` is blind. Fix this one and ~32,600 of the corpus's
  33,634 regrouped bytes go away.
- **`php/text-swallows-remainder.php`** — 4 claims. The mechanism: 57 of 70
  bytes read as inline HTML and *counted built*. This is the one to read.
- **`go/selector-field.go`** — 8 claims, of which `roots 1` and `mends 0`
  **pass**. A clean parse, zero mends, 100% standing, and a call read as a
  cast.

`python3 tool/plumb.py run` for the sweep, `board` for the spliced board with
its three checks, `show <grammar>` for the widest runs with their bytes,
`verify` for the five tripwires.
