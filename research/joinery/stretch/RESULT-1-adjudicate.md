# Result 1 — tree-sitter adjudicates the sentence, and makes the same claim

The sentence, from the lane that shipped `stretch` and `airy`:

> *a leaf is a token, so whitespace between two tokens is under no leaf and is
> not a defect.*

Its own closing words: **"Nothing in the repository adjudicates the sentence."**
Something outside the repository does. Tree-sitter's answer is **yes, and it is
my rule too** - the hole `stretch` measures is what both parsers do with the
space between two tokens, not something outliner failed at.

**The sentence survives. The column that rests on it does not.** `airy` asks
whether a byte is a space; the sentence asks whether a token stands on it. Those
are different predicates, they disagree 1,927 times corpus-wide, and the
disagreement runs mostly in the direction nobody expected - including me.

| figure | corpus | verilog | what it is |
|---|---|---|---|
| `damage` | **125,011** | **62,180** | the board. `size - built` |
| `owed` | **125,174** | **62,180** | **adjudicated.** `damage + warp` |
| `text` | 127,920 | 62,604 | the byte class. `damage + stretch - airy` |
| `honest` | 205,003 | 66,824 | every bare byte charged |

The 77,000-byte swing the lane left open closes at **163 bytes** - 0.13% of
`damage`. Neither 129,836 nor 206,555 is the number, and both were computed on a
board that has since moved anyway (see §6).

All figures measured on one arm, `pin.py` pin `stretchlane`, oracle seat minted
for it (30 of 30 verdicts live), tree-sitter 0.26.11, price `charged`.

---

## 1. What tree-sitter does, from its own source

Pinned at `v0.26.11`, the version of the CLI this repo's oracle seat runs.
Three lines carry the whole answer.

**A parent inherits its first child's padding and swallows every later child's.**
`lib/src/subtree.c:374-379`, in `ts_subtree_summarize_children`:

```c
if (i == 0) {
  self.ptr->padding = ts_subtree_padding(child);
  self.ptr->size = ts_subtree_size(child);
} else {
  self.ptr->size = length_add(self.ptr->size, ts_subtree_total_size(child));
}
```

`total_size` is `padding + size` (`subtree.h:295-297`). So for every child after
the first, the whitespace *in front of it* is added to the **parent's `size`**.
The leading whitespace of the first child is instead hoisted up as the parent's
own `padding`, and hoisted again by *its* parent, all the way to the root.

**A child's own node excludes that padding.** `lib/src/node.c:93-102`, in
`ts_node_child_iterator_next`:

```c
if (self->child_index > 0) {
  self->position = length_add(self->position, ts_subtree_padding(*child));
}
*result = ts_node_new(self->tree, child, self->position, alias_symbol);
self->position = length_add(self->position, ts_subtree_size(*child));
```

The position advances *past* the padding **before** the node is minted, and
`ts_node_start_byte` returns that position verbatim (`node.c:39-41`).

**A node ends at start + size, not start + total_size.** `node.c:449-451`:

```c
uint32_t ts_node_end_byte(TSNode self) {
  return ts_node_start_byte(self) + ts_subtree_size(ts_node__subtree(self)).bytes;
}
```

So: **inter-token whitespace is inside every ancestor's `[start_byte, end_byte)`
and inside no leaf's.** The two questions in the brief - *inside a parent's span?*
and *inside any leaf?* - have **different answers**, and the difference is
exactly `padding`. That difference is the entire population `stretch` counts.

## 2. ...and from its own output, on real corpus bytes

`research/joinery/corpus/ledger.go`, 1,189 bytes, parsed by the seated oracle -
438 nodes, root `source_file [0, 1189)`.

```text
inside the root, under no LEAF of tree-sitter's : 193
inside the root, under NO NODE of tree-sitter's :   0
```

One witness, byte 784:

```text
witness byte   784  = b'\n'
   depth 0  source_file          [0, 1189)   leaf=False
   depth 1  method_declaration   [710, 889)  leaf=False
   depth 2  block                [741, 889)  leaf=False
   depth 3  statement_list       [744, 888)  leaf=False
   token before  }      [783, 784)  b'}'
   token after   var    [786, 789)  b'var'
   the gap       [784, 786)  b'\n\t'
```

Four nodes' spans contain that byte and not one of them is a leaf. The gap is
`var`'s padding, hoisted out of `var`'s node by `node.c:94` and absorbed into
`statement_list`'s `size` by `subtree.c:378`.

**This corrects my own prediction.** P1.2 said the byte would be inside "no node
at all - not merely no leaf". That is false, and the output above is what falsifies
it: the byte is inside four interior nodes. The accurate statement is *inside
every ancestor and inside no leaf*, and I have fixed the two docstrings in
`rack.py` that carried my wrong phrasing.

Corroboration worth stating: go's row on the board reads `stretch` **193** and
`padding` **193**, and this independent walk over the root finds **193**. Three
routes, one number.

## 3. Does outliner's `quire` make the same claim? Yes, in its own code

Not inferred from output. `src/kernel/quire/quire.zig:237-239`, on `Node.start`:

> *Byte offset of the first byte this node covers. **A node spans from its first
> token to its last, so the extras between them are inside it and the ones around
> it are not.***

And the code that does it, `src/kernel/quire/gather.zig:2794-2807`:

```zig
var start = x.at;
var end = x.at;
var seen = false;
for (p.rhs, mine) |sym, *f| {
    if (f.start == f.end and !(f.owns > 0 and sym < x.gr.terminal_count)) continue;
    end = if (seen) @max(end, f.end) else f.end;
    if (!seen) start = f.start;
    seen = true;
}
```

`start` is the first *consuming* child's start and `end` is `@max` over child
ends. The comment above it names tree-sitter's padding hoist without naming
tree-sitter:

> *A nullable child sits at the offset the previous token ended, and letting it
> set the start would pull the node back over the whitespace in front of the
> first real one.*

That is `if (i == 0) self.ptr->padding = ts_subtree_padding(child)` reached by a
different route. `@max(end, f.end)` is `size += total_size(child)`. **Two
independently written parsers, the same rule, the same reason.**

## 4. The measurement: whose bare bytes are they?

`tool/rack.py` now splits `stretch` by asking the oracle instead of asking the
byte. Three buckets, exhaustive on every row (`stretch == warp + slack + veiled`,
asserted for all 29 measurable rows):

- **`warp`** - tree-sitter stands a live leaf here and we stand none. **A token
  we owe.**
- **`slack`** - under no leaf on *either* tree. The shared representation.
- **`veiled`** - the oracle declines. `plumb`'s own blind rule, not a fourth one.

Plus **`padding`**: of the same `built` scope, the bytes **tree-sitter's own tree**
leaves under no leaf of its own. The oracle's answer to the question this column
asks about us.

```text
                      ours_bare theirs_bare   both_bare        warp  warp_white   air_wrong
c                           304         304         304           0           0           0
html                      25241       25241       25241           0           0           4
php                       12229       12229       12229           0           0           0
elixir                     6690        6690        6690           0           0           0
ocaml                      5387        5387        5387           0           0           0
swift                      4645        4582        4582          63           0           0
verilog                    4644        4644        4644           0           0           0
julia                      4941        4900        4900          41           0          41
zig                        2765        2765        2765           0           0           0
toml                       1972        1972        1972           0           0        1552
rust                        668         668         668           0           0         269
bash                        152         100         100          52           1           1
sql                         850         934         850           0           0           9
CORPUS                    79992       79913       79829         163           2        2324
```

(`witness.py` beside this file, full 29 rows in the `.json` it writes to
`.local/stretch/`. Re-run it on a sighted arm and it reproduces the corpus row
byte for byte; that is the only claim it makes, and it is not `rack`'s route
twice - it paints both trees itself and cross-tabs the byte class against the
oracle, which is the one comparison `rack` reports as totals rather than pairs.)

**On 24 of 29 rows the three counts are byte-for-byte identical.** Not similar
magnitudes - the same number, including the corpus's four biggest rows (html
25,241, php 12,229, elixir 6,690, ocaml 5,387). `both_bare / ours_bare =
79,829 / 79,992 = **99.80%**`.

`sql` is the one row where the oracle leaves *more* bare than we do (934 vs 850):
we stand leaves on 84 bytes tree-sitter files as padding. The gap runs both ways,
which is worth knowing before anyone reads `padding` as a ceiling.

### The 163 bytes we actually owe

By the oracle's own name for the token:

| grammar | token | bytes |
|---|---|---|
| swift | `..<` | 54 |
| bash | `variable_name` | 51 |
| julia | `"""` | 36 |
| swift | `...` | 9 |
| kotlin | `is` | 6 |
| julia | `"` | 5 |
| ruby | `heredoc_content` | 1 |
| bash | `string_content` | 1 |

Range operators, a variable name, string delimiters, a keyword. Real tokens,
real defects, and **161 of the 163 are non-whitespace bytes** - so the byte class
was already charging them. `airy`'s over-excusing costs exactly **2 bytes**.

### Where the byte class actually goes wrong

`air_wrong` = **2,324** bytes: non-whitespace, bare on our tree, and bare on
tree-sitter's too. The byte class **charges** every one of them, and the oracle
cannot defend charging any of them. toml 1,552, rust 269, scala 171, markdown 142,
kotlin 90, css 45, julia 41, sql 9, html 4, bash 1.

rust is the cleanest illustration: `damage` **0** on the board, and `text`
charges it **269**. A file nothing is wrong with, priced at 269 bytes of damage
by a rule that mistook "not a space" for "a token should be here".

And the largest of them is the previous lane's own headline row. Its
`RESULT-9-verilog.md` names **toml at 1,552 of 1,972** as the corpus's widest
"source-text stretch" - the bytes it kept charging after the whitespace was
excused. Every one of those 1,552 is bare on tree-sitter's tree too. The column
it trusted most is the column the oracle declines to charge at all, which is a
better argument for adjudication than anything I could have constructed.

## 5. So which price is correct

**`owed = damage + warp`.** Every term is a byte some parser put a token over
and we did not. It is `125,174` corpus-wide and `62,180` on verilog.

`text` is wrong in both directions and mostly in the charging one: **+2,324**
bytes it charges that the oracle leaves bare, **-2** it excuses that the oracle
tokenises. Net against the adjudicated figure, **+2,746** (the remainder is
`veiled`, where the oracle has no verdict either way).

`honest` charges 79,992 bytes of which the oracle stands a leaf on 0.2%. It is
not a conservative reading of anything; it is the representation billed as a
defect.

`text` is **kept, not deleted** - a lane holds a baseline in it, and a baseline
nobody can re-derive is a number rather than a measurement. It is now printed
labelled as the byte-class rule with its error against the oracle beside it.

### verilog specifically

verilog's entire 4,644-byte `stretch` is **`veiled`**: every one of those bytes
is under an oracle node in recovery, so tree-sitter has no verdict on any of
them. `warp` is **0**. Its own tree leaves the same 4,644 bytes under no leaf of
its own (`padding` 4,644).

So the reconciliation the previous lane flipped to `62,888` on the strength of
the sentence **buys verilog nothing either way**: not one of those bytes is a
token tree-sitter builds, and not one is a byte tree-sitter will adjudicate.
verilog's adjudicated damage is its board `damage`, **62,180**, unchanged.

Three lanes optimised verilog against `damage` before `square` could be read on
the row. The fourth figure they were about to be handed would have been derived
from a column the oracle is blind on.

## 6. The board moved underneath the numbers in the brief

Measured on my arm against the figures the brief carries:

| | the lane's board | this arm | Δ |
|---|---|---|---|
| corpus `damage` | 126,927 | **125,011** | -1,916 |
| corpus `stretch` | 79,628 | **79,992** | +364 |
| corpus `airy` | 76,719 | **77,083** | +364 |

Exactly the drift P1.5 predicted and the brief warned about. **Nothing here is
differenced against the record**; every figure in this dossier is from one arm,
one sweep, one oracle seat.

Two population notes so nobody differences the wrong pair later:

- `rack.py run` sweeps 30 rows; `rack.py verify` sweeps the 29 that produce a
  verdict (yaml builds nothing). The verify banner therefore reads `damage
  106,076 ≤ owed 106,239 ≤ honest 186,068` over its own subset. **The corpus
  headline is the `run` figure**, 125,011 / 125,174.
- `standing.py --audit` reports verilog at 32,477 `built`; that is the same
  number `rack` reads. The 30,720 → 32,193 move in the brief predates both.
- Every figure quoted here was re-taken as a **separate process after the code
  stopped moving** - `rack.py run`, `rack.py verify` and `witness.py` each in
  their own - and each came back with the same number. That is the fourth house
  rule applied to my own edits rather than to a sibling's: a board taken while
  its own instrument is mid-edit is a timestamp, and the first `verify` I ran was
  one (I changed `rack.py` 34 seconds into it). The re-run is the one that counts.

## 7. The tripwires

Eight new rows in `rack.py verify`, in `adjudged()`, plus two that prove the
gates bite. **All ten held, and the whole slate held with them** - `38 of 38` on
the last run, and that total is a sibling's to move, so the claim here is the ten
rows and not the count. All corpus-shaped - none names a grammar, because two
lanes had falsifiers dissolved this week by siblings fixing the product the
witness stood on.

```text
ok  the population exists to be adjudicated: 79992 byte(s) of `built` sit under no leaf of ours
ok  and the ORACLE leaves a hole of its own in the same scope: 79913 byte(s) ...
ok  and it is the same order of magnitude, not a token gesture: theirs 79913 against ours 79992 (99.9%)
ok  the split partitions it on every row: `stretch == warp + slack + veiled` holds for all 29
ok  and it is overwhelmingly the SHARED gap rather than a token we owe: 75156 of 79992 (94.0%) ...
ok  `warp` still means something on its own: 163 byte(s) over 5 row(s) ...
ok  and the byte class is demonstrably not the rule it stands for: `airy` excuses 77083 where the
    oracle leaves 75156 bare — 1927 byte(s) apart
ok  the three prices stay ordered on every row: damage ≤ owed ≤ honest
ok  the adjudication can be failed: a board where the oracle leaves no hole of its own turns 3 of 8 red
ok  and it fails for the right reason — the population row still holds
```

The load-bearing ones and what turns them red:

- **the oracle's hole exists, and is the same order as ours.** Red if
  tree-sitter's leaves ever tile its root inside our scope - which is precisely
  the world in which the sentence is false and `honest` is the right price.
- **`warp` still means something.** Red if `warp` reads 0 everywhere, because a
  column that only ever reads zero is an assertion wearing a measurement's
  clothes. This is the both-poles gate: some bare bytes must be the shared
  representation *and* some must be a token we owe, whichever rows those are.
- **the byte class is not the rule.** Red if `airy == slack`, which would mean
  `owed` measures nothing `text` did not and should be retired.
- **the split partitions `stretch` on every row.** Red the moment the three
  sub-columns stop being a partition and become three numbers.
- **`warp`/`slack`/`veiled`/`padding` are in `shaded`'s price-move set.** The
  oracle's answer about a byte must not move with *our* pricing policy; if one
  ever does, the adjudication is reading our own rule back to itself.

The can-say-no rows hand `adjudged()` a constructed board where the oracle leaves
no hole and every bare byte is owed. Three rows go red, the population row stays
green - so the red is about the oracle's answer and not about having measured
nothing. That board cannot be produced by editing the corpus, which is why it is
constructed rather than found.

## 8. Scoring my own predictions

**4 of 6 held. P1.3 and P1.4 failed, together, for one reason.**

| | verdict | |
|---|---|---|
| P1.1 | **held** | oracle's own hole non-zero and same order: 79,913 vs 79,992 |
| P1.2 | **half wrong** | inside no *leaf*, yes. "Inside no node at all" is false - §2 |
| P1.3 | **wrong, inverted** | see below |
| P1.4 | **wrong** | see below |
| P1.5 | **held** | the board moved; `damage` -1,916 before any re-pricing |
| P1.6 | **held** | both poles exist today: `warp` 163, `slack` 75,156 |

**P1.3 predicted the two directions backwards.** I said whitespace-inside-a-leaf
would be "**thousands** of bytes... concentrated in html (25,241) and php
(12,229)", and non-whitespace-with-no-oracle-leaf would be "**tens**, not
thousands". The measurement: **2** and **2,324**. Both magnitudes inverted, and
html and php produced `warp` **0** apiece.

**Why, plainly:** I reasoned from which rows have a big `stretch` instead of from
what puts a byte in `stretch`. The `text` nodes we fail to build - html's, php's,
verilog's `macro_text` - are outside `built` entirely. They are `damage`. They
were never candidates for this column, and I predicted them into it because they
were the largest thing nearby.

**That is the previous lane's error in a new place.** It predicted from a column's
*name*; I predicted from a column's *size*. Same mistake one step out: reading a
number's magnitude as evidence about its composition. The fix is the same one the
brief prescribes and I only half-followed - read the code that puts bytes in the
bucket, which for `warp` is "a leaf of theirs over a byte with no leaf of ours
inside a region we did build", a population html and php have almost none of.

**P1.4 fell out of P1.3.** I said `129,836` was a *floor* and the adjudicated
figure would be *strictly greater*. It is **lower**, `125,174` against
`127,920`, because the byte class over-charges by 2,324 and under-excuses by 2.
The lane's
figure was a **ceiling** on the adjudicable part, not a floor. I did at least
decline to predict a position inside the interval, and the interval itself
(strictly between `damage` and `honest`) held.

## 9. What I trust least

1. **`veiled`, at 4,673 bytes - 5.8% of `stretch`, and 4,644 of them are
   verilog.** The oracle declines there, so `owed` prices those bytes at zero by
   *default* rather than by verdict. That is the right fail-closed direction for
   a damage figure, but it means verilog's adjudication rests on the oracle being
   silent rather than on it agreeing. If verilog's grammar starts parsing without
   recovery, those 4,644 bytes get a verdict for the first time and `owed` can
   move on the corpus's largest `damage` row. Nothing in this lane predicts which
   way.
2. **`warp` is 163 bytes, and 163 is small enough to be an artifact.** The
   `t_ok` paint excludes leaves tree-sitter names `ERROR`/`MISSING`, matching
   `plumb`'s blind rule by construction. If that rule is wrong anywhere, `warp`
   is where it shows, and 163 is too small a number to notice being wrong by
   half. The both-poles tripwire guards it reading *zero*; nothing guards it
   reading 163 when it should read 300.
3. **`padding` is measured over our `built` scope, not over tree-sitter's root.**
   That is deliberate - it has to be the same population to be comparable - but
   it means `padding` says nothing about the bytes outside `built`, which is
   where `damage` lives. `sql`'s 934-vs-850 is the visible edge of that choice.
4. **Every number here comes from one arm on one machine at one time.** The
   oracle seat was minted 8 minutes before the board was taken. The drift table
   in §6 is what happens when that is not true, and I have no second machine's
   reading of these figures. The arm's own stamp says the rest of it out loud:
   the pinned binary was built from tree `e6d3fe044` while the repo has since
   moved on under it, so this is a coherent board of *one* tree rather than a
   board of the tree as it stands this minute. That is the trade `pin.py` exists
   to make - a moving binary would be worse - but it means re-deriving these
   figures starts with `pin.py bin`, not with reading them back off this page.

## 10. Instruments found along the way

- **`hollow()` divided by `damage`.** `rack.py run json` - any single clean
  grammar - died with `ZeroDivisionError` on the report, and had since the
  column shipped. A clean board was the one input the reconciliation report could
  not print. Fixed.
- **`verify` swept the corpus twice.** `shaded()` took the slate and measured
  all 30 rows itself; my gate needed the same rows. Two sweeps are two
  populations whenever a sibling lands mid-run, and the two gates would then
  disagree about a board they both call "the corpus". Now one sweep, passed to
  both - which also halves an 80-second verify.
- **The oracle mint fails silently into a shell that has exited.** `nohup ... &`
  from an agent shell left `pin.py oracle` dead with 2 of 30 folios pressed and
  an empty log, and `pin.py arm` correctly reported `oracle: NONE`. That report
  is the only thing between this lane and a board of thirty phantom zeros. It
  earned its keep; worth saying out loud that it did.
- **`Seen` has 4 required positional fields more than it had this morning** and
  two construction sites. The mint crashed on the second one mid-edit. Both are
  keyword-called, which is why the crash named the missing fields instead of
  silently putting `built` in the `square` slot - the failure mode `blank()`'s
  docstring already warns about.
