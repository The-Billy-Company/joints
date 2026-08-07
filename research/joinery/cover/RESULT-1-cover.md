# Result 1 — the refusal was an ancestor's, on a corpus where one ancestor is the file

**Arm.** `pin.py` isolation arm `coverlane` — binary `346d880fc`, built from
tree `05e300803`, its own `JOINTS_WORK`, its own oracle seat (30 of 30
verdicts local). `stamp` reports `DRIFT — the binary's tree 05e300803 is not the
repo's 07388886c`, which is correct and expected for an isolation arm: **every
number below describes that tree**, and the before/after pair was measured on
that one binary with that one oracle, which is the only thing that makes the
difference between them a measurement rather than two unrelated runs.

**This arm is not the tree this morning's figures were published on.** Its
corpus `owed` reads 126,917 where the published headline was 125,174 and
verilog's `damage` reads 62,986 where the finding lane reproduced 62,180 — the
binary moved underneath both. So the claim here is about the **delta the rule
change causes**, held on one arm, plus the absolute figures on that arm. The
published numbers are re-derived below in the only sense that is available:
whether this correction moves them.

---

## 0. What moved in the published columns: nothing

Lead with it, because the brief asked for it and the answer is the boring one.

| column | before | after | Δ |
|---|---:|---:|---:|
| `owed` (corpus) | 126,917 | 126,917 | **0** |
| `damage` (corpus) | 126,754 | 126,754 | **0** |
| `warp` (corpus) | 163 | 163 | **0** |
| `stretch` (corpus) | 79,388 | 79,388 | **0** |
| `honest` (corpus) | 206,142 | 206,142 | **0** |
| verilog `owed` | 62,986 | 62,986 | **0** |

`owed = damage + warp`, and neither addend reads `plumb.hurt()` in a way this
touches. The finding lane predicted verilog's `owed` would hold and it holds;
what it could not say is whether any other row moved, and **none did.** The
headline published this morning stands, and it stands by verdict now rather
than by nobody having checked.

**What did move is the adjudication.**

| column | before | after | Δ |
|---|---:|---:|---:|
| `veiled` (corpus) | 4,615 | **300** | −4,315 |
| `slack` (corpus) | 74,610 | 78,925 | +4,315 |
| `unjudged` (corpus) | 4,704 | **389** | −4,315 |
| `mute` (corpus) | 3,727 | 373 | −3,354 |
| `judged` (corpus) | 395,318 | 399,631 | +4,313 |

`veiled` was **93.5% wrong**. 4,315 bytes the board reported as "the oracle
declines" were bytes the oracle had named, and `stretch == warp + slack +
veiled` held the whole time because the three exhaust the population however
you mis-split them — which is exactly why nothing caught it.

And those 4,315 bytes did not vanish into a second silence. They went into real
buckets:

| bucket | Δ |
|---|---:|
| `unframed` | +2,016 |
| `square` | +908 |
| `racked` | +820 |
| `askew` | +569 |
| `unwindowed` | +2 |

2,016 + 908 + 820 + 569 + 2 = **4,315**, to the byte. **1,389 of them are a
charge** — `askew` + `racked`, bytes where the two derivations disagree — and
verilog's `crooked` rises 10,964 → 12,353 to say so. Its `share` **falls**,
40.48% → 39.34%, because the denominator grew faster than the numerator. The
row is materially worse in absolute charge and marginally better as a ratio,
and a report that quoted only the percentage would have called this an
improvement.

---

## 1. The sweep: nine readers, three questions, one fix

`gist 'hurt\(' -g '*.py'` and `gist 'HURT' -g '*.py'` over the tree. Nine
call sites read `plumb.hurt()`. Four more instruments test `ERROR`/`MISSING`
without it, and **those four were already right** — which is the finding that
made the fix safe, because it shows the two questions were being distinguished
everywhere except in the one function that answers both.

### Asked "can the oracle NAME this byte?" — all wrong, all fixed

| site | consumed as | fixed by |
|---|---|---|
| `tool/plumb.py:judge` | `unjudged` vs `interstice` | `hurt` is now the cover; the two branches collapsed to one |
| `tool/rack.py:survey` `blind` | `unjudged` | `blind = them is None or t_bad[p]` |
| `tool/rack.py:survey` `veiled` | `veiled` vs `slack` | `who < 0 or bad` |
| `research/joinery/flag/spans.py` | dissects `rack`'s buckets | same one-test form |
| `research/joinery/unjudged/unwindowed.py` | `unjudged` | same |
| `research/joinery/tenon/extent.py` | skips unjudged | same |
| `research/joinery/cpp/confuse.py` | `blind` into `rack.bucket` | same |
| `research/joinery/stretch/witness.py` | re-derives `warp`/`slack`/`veiled` | same |

Every one of these spelled some variant of

```python
them is None or (not them.leaf and t_bad[p]) or (t_bad[p] and them.name.startswith(HURT))
```

which is **the same rule twice**, once by ancestry and once by cover, with the
ancestry arm guarded to fire only on non-leaf bytes. That guard is why the bug
was survivable: it kept tree-sitter's 17,290 verilog *tokens* out of the
refusal, so only the interstitial bytes were written off, and interstitial
bytes are exactly the ones nobody looks at. Once `hurt` asks the cover, the
first clause is a strict subset of the second and both collapse to `t_bad[p]`.

### Asked "is this region a recovery artifact?" — all correct, untouched

The brief warned these might not want the same answer. They do not, and they
already had it:

| site | asks | verdict |
|---|---|---|
| `tool/collate.py:refusals` | union of `ERROR` extents | **correct** — it wants the region, and paints extents on purpose |
| `tool/collate.py:survivors` | what tree-sitter kept *inside* one | **correct**, and it is the counterweight that proves the sub-tree is real |
| `research/joinery/scars/against.py` | recovery extents + `MISSING` count | **correct** |
| `tool/specimen.py` | "did the oracle error at all" | **correct** — a node count, not a byte taint |
| `research/joinery/judge/judge.py` | the finding lane's own instrument | **left alone** — it compares both rules; that is its subject |

So the fix is: `hurt()` asks the cover, and the ancestry answer keeps a name of
its own — **`engulfed()`** — so a caller that wants a region can have one and a
caller that wants a verdict can no longer be handed a region by accident.

`tool/collate.py` was already doing by hand what `engulfed` now does. It is
left alone rather than rewired: this lane's edit to two files under other lanes
is as small as it can be, and a second instrument is not a defect.

---

## 2. Which grammars carried a wide `ERROR`: two, and only one mattered

`python3 tool/plumb.py decline` over all thirty rows:

| grammar | bytes | E-nodes | widest | rest | cover | region | gap | named | token | one bracket for all? |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| verilog | 94,657 | 333 | 94,657 | 12,526 | 271 | 31,671 | **31,400** | 31,400 | 27,085 | **YES** |
| sql | 6,390 | 19 | 258 | 515 | 118 | 239 | **121** | 121 | 121 | — |

**Twenty-seven of thirty rows carry no recovery node at all.** Both rules read
zero on them, which is agreement and not evidence — and is precisely why the
corpus-shaped check below has to assert that *some* row can still tell the two
rules apart.

`rest` excludes the widest node. That matters: the union of every recovery
extent *including* it is 94,657 on verilog, because the root bracket contains
every other one, so a test against the plain union can only ever say no. Asked
correctly, verilog's real recovery is **12,526 bytes** — reproducing the
finding lane's figure independently on a different arm.

**haskell and scala were the brief's suspects and both are clean.** Neither
carries a single recovery node in tree-sitter's tree on this corpus; their
damage is entirely our own. The row that was silently misjudged besides verilog
is **sql**, which nobody named.

### But sql moves nothing, and that is worth stating

sql's 121 disputed bytes are **all leaf-covered**. Under the old rule the
ancestry arm only fired on non-leaf bytes, so sql's leaves were never refused —
`rack`'s sql row is byte-identical before and after. The gap was real, it was
just already being handled by the guard.

**Only verilog moves, by 4,315 bytes.** One grammar, one file. The corpus-wide
sweep the finding lane declined to run found one more affected row and zero
further movement, and both facts are worth more than the guess would have been.

---

## 3. The check: `plumb.py decline`, and it can fail

The defect's shape is not "verilog" and the guard must not be. A refusal column
reads zero the same way an unasked question does, so the class is: *an
instrument converting somebody else's answer into its own silence.* Four
assertions, corpus-shaped:

```
ok  NESTS   the consumed rule refines the region rule on all 30 row(s)
ok  SOUND   every one of the 389 refused byte(s) is covered by an ERROR/MISSING of its own
ok  PARTS   2 row(s) still tell the two rules apart: verilog 31400 · sql 121
ok  SPOKEN  the oracle NAMES all 31521 disputed byte(s), 27206 with a token
```

`SOUND` is the rule restated **over the tree** rather than over the
implementation — asking `hurt` whether it did what it says is a check that
cannot go red. `PARTS` is the anti-vacuity assertion and the more interesting
one: **the day the corpus holds no wide bracket, the other three hold for free
and prove nothing, so that day this says so and exits 1.** `SPOKEN` is the
falsifier for the fix itself — if the disputed bytes were genuinely unnameable
the old rule was right, and it is checked rather than assumed.

**Watched failing.** Putting the ancestry paint back (`hurt = engulfed`) on
verilog + sql + javascript:

```
FAIL  SOUND   every one of the 31910 refused byte(s) is covered by an
              ERROR/MISSING of its own — sql, verilog is not
FAIL  PARTS   NO ROW can tell the two rules apart — this check is proving
              nothing. A corpus with no wide recovery bracket cannot witness
              this defect; add one or retire the column.
2 of 4 held · exit 1
```

Note `SPOKEN` goes *green* under the revert, on a population of zero. That is
the vacuity `PARTS` exists to catch, and it caught it.

The corpus sweep costs ~70 s, which is too slow to be the only guard, so
`plumb.py verify` carries the same claim against a four-node tree written out
in the file — one bracket over 100 bytes with real structure underneath —
including the byte class that is the whole defect: **interior to a construct
built inside the bracket.** A test that only checked the leaves would have been
green throughout the bug.

### A witness dissolved, and was kept

`plumb.verify`'s RED tripwire asserted that swift's `/* c\n d */` **must** come
back askew. It no longer does: a sibling lane seated `multiline_comment` on its
own `marrow` vein and the two specimens went 2/4 → 4/4
(`changelog.d/+swifts-comment-was-arithmetic-and-the-board-called-it-built`).
So the assertion encoded the defect rather than the contract, and it was
failing before this lane touched anything — verified by restoring the ancestry
rule over that exact row and getting the same 0 misread, on a tree with **zero
recovery nodes**, where the two rules are identical by construction.

It is kept, pointed at the same bytes, demanding the correct reading: those
bytes must be `multiline_comment` and must be `plumb`. It is now the regression
guard for the seating that dissolved it. The negative it used to supply is
supplied by a new one that does not depend on the parser still being wrong
about anything: two trees over the same twelve bytes, one calling them a
comment and one calling them arithmetic, plus the control that the same walk
over two *agreeing* trees comes back silent.

`plumb.py verify` was 4 assertions with 2 failing. It is now **10, all
holding.**

---

## 4. The residue: 943 bytes, checked

The finding lane's caution, in full: the 271 bound counts bytes whose innermost
cover is a recovery node, but a byte whose cover is a *healthy node built in
the wrong place* counts as adjudicated `slack`, and on the 943 bytes where the
two trees name that cover differently it was trusting tree-sitter unchecked.

On this arm the residue is **840**, not 943 (freed 4,315 not 4,373, agreeing
3,475 not 3,430) — the binary moved, so the name-agreement split moved with it.
Same population, different tree.

`research/joinery/cover/residue.py` asks Verible two questions. It runs in
about five seconds and does not touch `attest`, which is the use the finding
lane endorsed.

**Q1 — does a token stand there?** `slack` claims no leaf on either tree. A
third lexer standing a token on the byte makes that two-against-one.

**Q2 — is the cover in the right place?** The sharper question and the one the
caution is actually about. A node built in the wrong place cuts across real
lexical structure; Verible's token boundaries *are* that structure, so a cover
whose extent slices a token in half is demonstrably misplaced whatever it is
named. **This is the falsifier: it can come back saying tree-sitter is wrong.**

| | bytes |
|---|---:|
| residue | 840 |
| Verible **declined** to lex (`MacroArg`) | 38 |
| lexed, and no token stands there | 802 (all of them) |
| — of those, cover corroborated | **794** |
| — of those, cover cuts a token in half | **8** |

### Q1 holds. Q2 does not, and the failure is real

**Verible stands a token on zero of the 802 residue bytes it lexed.** `slack`
is corroborated by a third parser on every byte it can speak to.

**Six covers cut a Verible token in half, over 8 bytes** — three
`clocking_drive`, two `operator_assignment`, one `data_declaration`. The
clearest is `clocking_drive [46430, 46501)`, which starts **one byte inside**
Verible's `` `ifdef `` token: tree-sitter read the backtick as a clocking-drive
operator and began a node in the middle of a preprocessor directive. That is
exactly the class the caution named, and it is present.

**So the bound is 271 + 8 = 279 on this arm**, and it is no longer a floor over
this population — 794 of the 840 are corroborated and 38 are bytes a third
parser declined to answer about.

### The check made this lane's own mistake first, and it is worth recording

The first draft charged **38 bytes**, all single spaces, as tokens joints
owed. `picorv32.v` is full of `` `debug($display("…", a, b);) ``, and **Verible
does not lex inside a macro-call argument** — it captures the whole thing
verbatim as one `MacroArg` token, up to 104 bytes of it, spaces and semicolons
included. Reading that blob as "a token stands on these bytes" is *precisely
the defect this lane exists to repair*, with the parsers swapped: a refusal to
answer, counted as an answer.

It also produced 27 spurious `PLACED` failures for the same reason — covers
whose ends fall inside a `MacroArg`, where tree-sitter lexed and Verible
declined to. Those are tree-sitter being **finer-grained**, the opposite of the
caution.

`MacroArg` is now carved out into a third state and reported rather than folded
either way. The 8 that survive are the ones Verible actually looked at.

---

## 5. What I trust least

**First: `slack` is still not a verdict, it is two absences agreeing.** This
lane moved 4,315 bytes out of `veiled` and into it, so `slack` is now 78,925
corpus-wide and carries this correction's whole weight. `slack` means "under no
leaf on either tree" — it says nothing about whether a leaf *should* be there,
and Verible corroborated it on 794 verilog bytes and 794 only. The other 78,131
are unchecked by anything but the two parsers that disagree about everything
else.

**Second: the 8 bytes are a sample, not a total.** They are the residue's
misplaced covers — bytes where the two trees *name the cover differently*. A
cover both trees name identically and both build in the wrong place is invisible
to every instrument here, and the 3,475 agreeing bytes were never checked
against Verible at all. The right next measurement is Q2 over the whole freed
population rather than the residue; it costs the same five seconds and I did not
run it.

**Third: one file.** verilog's damage row is `picorv32.v` alone. 4,315 of the
4,315 bytes that moved are in one 94 KB source, and "verilog" is doing more
work than it has earned — as the finding lane already said and as remains true.

**Fourth: `decline` proves the rule is applied, not that the rule is right.**
`SOUND` checks every refused byte's cover is a recovery node. Nothing here
checks the converse at corpus scale — that every byte under a healthy cover is
genuinely adjudicable — because the only instrument that could is a third
parser, and there is one for SystemVerilog and none for the other twenty-nine.
On a corpus where 27 rows carry no recovery node that gap is small. It will not
stay small if a grammar regresses.

**Fifth: `PARTS` depends on the corpus keeping a wide bracket.** It fails loudly
when that stops being true, which is the design — but "fails loudly" means the
next lane will find a red check and a message telling them to add a bracket or
retire the column, and the tempting third option is to delete the assertion.
It is the one thing here I would expect to be quietly removed.

---

## 6. Reproducing

```bash
eval "$(python3 tool/pin.py arm coverlane)"
python3 tool/plumb.py decline              # the corpus-shaped check, ~70 s
python3 tool/plumb.py verify               # 10 assertions, ~5 s
python3 tool/rack.py verify                # 38 assertions, unchanged by this
python3 tool/rack.py run --json            # the board the deltas above are read off
python3 research/joinery/cover/residue.py  # the residue, needs Verible on disk
```

## 7. What was touched

Two files live under other lanes, edited as small as the change allows, with
`git status` clean on both before and only these hunks after.

- **`tool/plumb.py`** — `hurt()` asks the cover; `engulfed()` keeps the ancestry
  answer; `judge`'s two refusal branches collapse to one; the `decline` verb and
  its `Authority` row; three assertions in `verify`; the dissolved RED tripwire
  kept as the seating's regression guard; module docstring.
- **`tool/rack.py`** — three lines: `hurt` takes the paint `paint` already made,
  `blind` is one test, `veiled` drops the guard the ancestry rule needed.
- `research/joinery/{flag/spans,unjudged/unwindowed,tenon/extent,cpp/confuse,stretch/witness}.py`
  — the same one-test collapse, so the rule reads the same in all six places.
- `research/joinery/cover/` — this dossier, its README, and `residue.py`.
