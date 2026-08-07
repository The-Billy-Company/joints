# Prediction 2 — how much of `built` is built in the wrong *shape*

Written **before** the tree-aligned comparison existed, against the board as it
reads on pin `plumb` (`dfc481e49`, tree `bd7b3e939`). Each prediction names the
measurement that falsifies it.

## What I knew when I wrote this

- **The board, unmoved:** `built 363,987 + orphan 56,343 + rubble 24,167 +
  spoil 82,301 = 526,798`, **69.09% standing**. I reproduced the previous
  lane's `plumb run` on the same pin and got its numbers to the byte: 222,024
  plumb · 34,428 misread (33,634 regrouped + 794 relabelled) · 1,268 renamed ·
  71,580 interstice · 34,687 unjudged. So **9.24% of `built` is regrouped**,
  13.05% of adjudicable bytes, ceiling 18.77%.
- **Twelve grammars read 100.0% standing** — go, java, javascript, typescript,
  python, rust, json, css, embedded-template, html, lua, toml — worth 100,399
  bytes, 27.6% of `built`. Eleven of the twelve read `accepted, 1 root`; toml
  reads `accepted, 1 root · UNSOUND` (one child outside its parent).
- **The demonstration I was handed.** `fmt.Print("x")` reads as a
  `type_conversion_expression` over a `qualified_type` — a cast, not a call —
  at 100.0% standing, 0 mends, and `plumb` scores it 5 misread bytes of 996,
  because `Print` is the only *leaf* whose name moves.
- **Two design probes**, run before writing this, because a definition chosen
  without them would have been a guess:
  - **javascript's two trees carry 324 nodes each and their labeled bracket
    sets — `(name, named, start, end)` — are identical: 324 shared, 0 on
    either side alone.** So joints's node shaping (hidden rules, inlining,
    invented alias nodes) does *not* structurally swamp a strict comparison on
    a grammar that works. A strict measure is viable.
  - **go's corpus file carries the specimen's defect, not just the specimen.**
    4 brackets ours-only (`type_conversion_expression`, `qualified_type`,
    `package_identifier`, `type_identifier` over `fmt.Print(banner)` at
    [1132, 1149)) against 5 theirs-only (`call_expression`,
    `selector_expression`, `identifier`, `field_identifier`, `argument_list`).
- **`--mend=` takes `none`, `keep`, `fell`, `relent`.** The verilog lane
  measured `keep` at +25,457 `built` and −9,550 nodes, with `covered` **rising**
  11.8 points and `spoil` **falling** 11,072 — the retired guard's two
  witnesses both moving the flattering way, because both are built from the
  same top-level spans as `built`. Its independent column, `stretch.py`, found
  **71.3% of `keep`'s `built` has no token on it** and `keep` standing over
  10,410 fewer real bytes than `fell`.
- **The oracle already cannot reach verilog or sql** (tree-sitter's own CST and
  XML disagree because its tree has errors in it), which is 34,687 built bytes,
  9.5% of `built`, and includes the corpus's largest damage row.

## The measure I am about to build

Same scope, same oracle, same pin. For each top-level `built` root R = [a, b)
from `standing.tops`, and for each byte i inside it:

- **`spine(i)`** is the sequence of `(name, named, start, end)` for every node
  covering i, outermost first — joints's from R down, tree-sitter's
  restricted to nodes **contained in [a, b)**. Tree-sitter's ancestors that
  reach past R are dropped: joints never claimed a bracket that wide, and
  judging it on one would report *"joints returned a forest"*, which the
  board already measures as `orphan`/`rubble`/`spoil`.

Five buckets, disjoint, totalling `built`:

| bucket | means |
|---|---|
| `unjudged` | plumb's rule, unchanged — no oracle node, or an interior position under an `ERROR` |
| `square` | the two spines are identical |
| `renamed` | identical once the grammar's own declared `ALIAS` pairs are applied |
| `askew` | the spines differ **at the deepest node** — the class `plumb` already sees |
| `racked` | the deepest node agrees and something **above** it differs — a right leaf under a wrong parent |

`racked` is the class this lane exists to count. `askew ∪ racked` is the
corrected number, and it is a superset of `plumb`'s `misread` over the same
population by construction, because the spine test compares the deepest node
*and* everything over it where `plumb` compares only the deepest.

## The predictions

| | prediction | falsified by |
|---|---|---|
| P1 | the corrected number **rises**: `askew + racked` exceeds `plumb`'s 33,634 regrouped bytes | `askew + racked ≤ 33,634` |
| P2 | it exceeds the previous lane's **defended ceiling** — 68,321 bytes, 18.77% of `built`, the number it got by assuming every unjudged byte was also wrong | `askew + racked ≤ 68,321` |
| P3 | at least **three of the eleven** whole grammars other than go carry nonzero `racked + askew` | two or fewer do |
| P4 | **html** — 72,288 bytes, the largest row on the board, 100.0% standing, and exactly **0** askew under `plumb` — reads nonzero | html reads exactly 0 |
| P5 | on the twelve whole grammars taken together, `racked` **exceeds** `askew`: their defect is shape, not tokens | `racked ≤ askew` over those twelve |
| P6 | **php is still the largest single contributor** of `askew + racked` | any other grammar tops it |
| P7 | **my own instrument lies first, in the direction that makes my lane look necessary**: the first numeric run reports nonzero `askew + racked` on javascript, whose 324 brackets I have already checked are identical | javascript reads exactly 0 on the first numeric run |
| P8 | the oracle **can** serve as the retired `covered`/`spoil` guard: on at least one grammar it reaches, a mend policy that **raises** `built` **lowers** `square` | on every reachable grammar, every built-raising policy holds or raises `square` |

## Why each

**P1.** The go probe is the existence proof at the file scale: nine brackets
disagree and `plumb` charges five bytes. Every such case in the corpus is
currently priced at the width of its leaves rather than the width of its
construct, and constructs are wider than leaves.

**P2.** 18.77% was defended as a ceiling under the assumption that the only
uncounted bytes were the unjudged ones. It is a ceiling on a *different*
question — "what if the oracle's silence is all bad?" — and says nothing about
bytes the oracle spoke on and the method could not hear. If the structural
class is real at all, it comes out of the 222,024 bytes currently filed
`plumb`, which is a bigger pool than the 34,687 the ceiling was built from.

**P3.** Twelve grammars where nothing ever reddens is twelve grammars nothing
has ever looked at above the leaf. go was checked and go was wrong on the first
look. If go is the only one, that is a strong and surprising fact about the
other eleven; I do not expect it.

**P4.** The previous lane predicted html would out-askew four mending grammars
and html read **0**, which is either "html is perfect" or "nothing has looked".
html is 19.9% of all `built` and 24 hundredths of the corpus. A byte-indexed
comparison over html's text nodes is nearly all leaf agreement by construction,
because most of an HTML file *is* text. The shape above that text is where an
error would live and is exactly what has never been compared.

**P5.** A grammar that parses whole with zero mends has, by definition, no
token it could not read — so its leaves are the half most likely to be right.
Whatever is wrong with a whole grammar has to be above them, or there is
nothing wrong at all.

**P6.** php's `text` node swallows 40,995 bytes of `Str.php` in one leaf. Under
a spine comparison those bytes are wrong at the leaf *and* at every node over
it, so php cannot get smaller. The only way P6 fails is if something else grows
faster, and the largest candidate — html — would need 32,616 bytes.

**P7.** This is the prediction the previous lane failed by its own terms and
held in spirit, and I am making it again because my exposure is worse than
theirs. Theirs compared one name per byte. Mine compares a sequence of
`(name, named, start, end)` per byte, restricted by a containment rule I wrote,
over a forest, with a rename excuse applied position by position. Every one of
those is a place where getting it wrong produces a wall of differences that
reads exactly like a finding — and the flattering direction is *more*
differences, because more differences is a bigger number for the lane whose
whole claim is that the number should be bigger.

**P8.** `covered` and `spoil` are functions of the same top-level spans as
`built`, so one root stretched over a hole moves all three the flattering way.
`square` is not: it is agreement with a second parser's derivation, and a
stretched root's bytes have a spine the oracle does not share, whatever the
board's arithmetic says. If that is true it must show up as a policy that buys
`built` and pays `square`. If it does not show up on any reachable grammar,
either the guard cannot be built this way or the trap is rarer than the verilog
lane found it — and I would rather find that out than assert the guard works.

## What I am deliberately not predicting

**Whether the correction should replace `plumb`'s number.** Both are true of
different questions and picking the flattering one after seeing them is the
move this lane exists to catch. Both get printed, with all three denominators
and with php split out, whichever way they land.

**How much of the rise is interstitial.** A byte between two tokens has no
token-kind, so `plumb` set 71,580 of them aside; a spine comparison *can* judge
them, because whitespace inside a construct is described by that construct. I
will count them and report them as their own cross-cut, and I am not predicting
the split, because a prediction here would give me a reason to want the
interstitial share to land on whichever side made the headline better.

## The tripwires

Both sides, and both are cases whose answer is known independently of the
instrument:

- **must be red** — `specimen/go/selector-field.go`. `plumb` scores it 5 bytes.
  A tree-aligned comparison must charge it the width of the **construct**, and
  the misread run must fall inside `fmt.Print("x")`. If it reports 5, this
  measure is the old one with more code.
- **must stay green** — javascript, 324 brackets shared and 0 on either side.
  If the byte-spine walk finds a disagreement where the bracket sets have none,
  the walk is wrong and not the parser.
- **must not be vacuous** — a run that judged nothing must not read as a run
  that judged everything clean. `square` is asserted to be **less** than
  `built`, and the buckets are asserted to total `built`, on every row.
