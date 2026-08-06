# Result 1 — verilog's 63,937 bytes, attributed

Scored against [PREDICTION-1-wall.md](PREDICTION-1-wall.md). All numbers from
the pinned binary `.local/pin/mendlane` (`33a3dac8b`, tree `bd7b3e939`).

```
verilog  94,657 bytes   32.5% standing   30,720 built   63,937 damage
         3,267 orphan + 14,057 rubble + 46,613 spoil
```

## The headline, up front

**Two constructs are worth 11,529 bytes of `built`, of which 8,175 survive a
stretch audit. Four more are named to a single line of verilog each and are
worth, together, essentially nothing.** The file's
remaining 49,446 bytes sit in one module and are 92.1% procedural, and no
ablation I ran takes them down.

The trap the brief aimed at this file is **real and larger than its headline**
- but the tree's own rule for detecting it says the opposite, because the rule's
two witnesses are derived from the same spans as the thing they witness. That is
the paragraph I would keep if I could keep one.

> **Re-pointed, not overturned, 2026-08-06 — and the paragraph above is the reason
> it survives.** Every number on this page is `built`, `damage`, `describes`,
> `stretch` or `standing`: outliner's own words about its own forest. The one
> question none of them asks is whether the bytes verilog puts under a construct
> are under **tree-sitter's** construct. Sighted, they are mostly not:
>
> | | bytes |
> |---|---:|
> | size | 94,657 |
> | built | 32,193 |
> | of built, the oracle adjudicates | 27,598 |
> | ...of those, **`square`** — same derivation as tree-sitter | **2,184** |
> | ...**7.9%** | |
>
> So the file's 63,937-byte `damage` headline is honest — `rack.honest` puts it
> at 68,119 once `stretch` is added back — and it is **not the largest number on
> this page any more**. 30,009 bytes are built and uncorroborated, and of the
> bytes the oracle rules on at all, six in seven are derived differently.
>
> **What that does to Part 1.** The two constructs really are worth +11,529
> `built` and +8,175 honest built; the ablation arithmetic re-derives and the
> comment control still holds `built` to the byte. What the page cannot claim is
> that those are 8,175 bytes of *correct* structure. On tonight's evidence, work
> that converts verilog's damage into `built` converts unbuilt bytes into
> misderived ones — so the next lane to open this file should price its ablations
> on `square` before it prices them on `built`. `--audit` inside the arm's own
> work dir is what makes that possible and is one flag.
>
> **What that does to Part 4.** Nothing, and it is the part of this page that
> ages best. *"`square` is the only column here not made out of the thing it
> checks"* is now `rack.py`'s own argument for existing, and this page reached the
> collinearity finding without it — from `stretch`, an independent construction.
> The `covered`/`spoil` guard is exactly as dead as Part 4 says.
>
> **Why this page could not have been written sighted.** verilog was **100%
> unadjudicable** until 2026-08-05: its oracle's two renderings disagreed, so no
> `square` reading of this file existed at any point while it was being measured.
> That is a fact about the instrument, not a shortcut anyone took. 4,595 of the
> 32,193 built bytes are *still* unaudited, which is why the ratio above is
> quoted over 27,598 and not over 32,193.
>
> Numbers from the audited base arm of `../consort/RESULT-8-sighted.md`
> (`.local/sighted/boards/base.json`, `outliner 68e8f0e395e8`). Deliberately not
> quoted off `crooked`, which is under repair tonight
> (`../consort/HANDOFF-crooked.md`); both candidate fixes only move bytes among
> `crooked`, `soft` and `unframed`, so `square / (built − unaudited)` is invariant
> under either.

---

## Part 1 — the two constructs that pay

| ablation | built | Δ built | describes | Δ desc | stands |
|---|---|---|---|---|---|
| baseline | 30,720 | +0 | 22,222 | +0 | 32.5% |
| A `` `ifdef `` in a port list | 40,508 | **+9,788** | 26,370 | **+4,148** | 42.8% |
| B `$signed(` | 32,424 | **+1,704** | 23,276 | **+1,054** | 34.3% |
| A+B+C | 42,249 | **+11,529** | 27,414 | **+5,192** | 44.6% |
| control: all 3,934 bytes of comment | 30,720 | **+0** | 22,168 | −54 | 32.5% |

Both winners raise `built` **and** `describes` together, which is P5's
condition. Held to the stricter test Part 4 ends up needing - `built` with a
token of some depth actually standing on it - they survive but are discounted:

| ablation | built | stretch | stretched | **honest built** | Δ honest |
|---|---|---|---|---|---|
| baseline | 30,720 | 4,182 | 13.6% | 26,538 | +0 |
| A | 40,508 | 7,035 | 17.4% | 33,473 | **+6,935** |
| B | 32,424 | 4,665 | 14.4% | 27,759 | **+1,221** |
| A+B+C | 42,249 | 7,536 | 17.8% | 34,713 | **+8,175** |

So the number to carry is **8,175**, not 11,529; 3,354 bytes of the headline are
hole. It is still the only thing on this file worth thousands, and it is the
opposite sign to `--mend=keep`'s −10,410. The comment control
leaves `built` unchanged **to the byte** and `mends` unchanged **at 2,109**, so
this is an impossibility argument and not a correlation.

The impossibility argument gets sharper when the file is split into its eight
`module`/`endmodule` blocks and each is parsed alone (`modules.py`). Three
already stand whole. Under A, two more go from walled to **100.0%**:

| module | bytes | baseline | A | B | A+B+C |
|---|---|---|---|---|---|
| picorv32 | 69,204 | 28.6% | 29.1% | 28.6% | **29.2%** |
| picorv32_regs | 343 | 100.0% | – | – | 100.0% |
| picorv32_pcpi_mul | 2,949 | 100.0% | – | – | 100.0% |
| picorv32_pcpi_fast_mul | 2,545 | 73.4% | 72.0% | **100.0%** | 100.0% |
| picorv32_pcpi_div | 2,404 | 59.1% | 56.2% | 59.1% | 56.2% |
| picorv32_axi | 6,223 | 54.2% | **100.0%** | 54.2% | 100.0% |
| picorv32_axi_adapter | 1,978 | 100.0% | – | – | 100.0% |
| picorv32_wb | 6,074 | 54.3% | **100.0%** | 54.3% | 100.0% |

Every percentage in that table is `standing`, so **"100.0%" means one root over
every byte and not one root tree-sitter agrees with** — the whole file reads
34.0% standing against 2.3% `trued`, and no per-module `square` reading has ever
been taken. A module going 54.2% → 100.0% under an ablation is a real change in
what the parse covers and an open question about what it derives.

A 6,223-byte module that walls at 54.2% and reads whole when one construct is
blanked is named. **The near-miss in the same table:** A makes `pcpi_div`
*worse* (59.1% -> 56.2%) and `fast_mul` worse (73.4% -> 72.0%), because the
directive lines were serving as recovery anchors. A fix is not free everywhere
it is a fix somewhere.

**Contamination is real and large.** The three modules that stand whole alone
read 41.7%, 33.5% and 45.3% *in situ* - 3,243 bytes lost to a felled stack
arriving from the module above them, in modules that have nothing wrong.

## Part 2 — four walls named to one line each, worth nothing

Every one of these reproduces in a single line and none of them moves the
board. This is the `_import_dot` shape: a perfect diagnosis worth zero bytes.

**D — an indexed lvalue in a blocking assignment.**
```verilog
module m; initial begin x    = 0; end endmodule   // accepted, 1 root
module m; initial begin c[i] = 0; end endmodule   // press? on = in state 2394
module m; initial begin c[i] <= 0; end endmodule  // accepted, 1 root
```
Same stop under `if`, `while`, `repeat`, `for` and `always`, and under none of
them without the indexed lvalue - so the `for (i = 0; …)` the verdict pointed at
is a location, not a diagnosis. `inquest` reads the cell as merge-damaged:
*"a merge damaged this terminal's cell elsewhere."* **`picorv32.v` holds 8 of
them; neutralising all 8 moves `built` by −167.**

**E — a bracketed selection inside a concatenation.**
```verilog
x = a[3];        accepted      x = {b, c, d};   accepted
x = (a[3] + b);  accepted      x = {f(1), b};   accepted
x = {a[3]};      press? on ; in state 701
```
Selections fine, concatenations fine, `[` inside `{ }` not. **112 sites; +68
built, and `describes` −1,103.** Worth nothing, and suspect even at +68.

**F — a user macro in statement position.**
```verilog
x = `WIDTH;                     accepted
module m; `debug(x) endmodule   accepted
always @* begin `debug end      press? on ` in state 1108
```
**Blanking all of them costs −2,176 built:** the walling lines were net
contributors.

**G — `&&` before a unary reduction (`… && |pcpi_rs2`).** +0 built, −8
describes. Not a wall at all; I predicted one and was wrong.

## Part 3 — where the 49,446 actually is, and why I could not take it down

Three readings are dead, each killed by a measurement:

- **"one bad line"** — `core.py` blanked the line the stop named for 61 rounds.
  `built` went **down** every round, −1,508 total, and rounds 4–47 marched one
  line at a time through forty-four `wire [31:0] dbg_reg_xN = cpuregs[N];`
  declarations losing exactly that line's bytes. A stop that moves to the next
  line when you delete the line it named is resynchronisation, not a wall.
- **"the module header"** — `header.py` deleted the entire 1,045-byte parameter
  port list *and* the entire 1,927-byte port list. `built` moved **exactly 0**
  and the stop stayed on the identical byte, while a control blanking 1,051
  bytes of ordinary declarations cost 1,019 built. `built` is sensitive to body
  bytes and blind to header bytes; the header is innocent.
- **"a statement form inside the procedural blocks"** — every arm in `inside.py`
  went negative or nowhere, because blanking a construct that *partly* parses
  removes the bytes it was contributing. Both negative controls were clean
  (comments +0, identifier renaming **+0 built and +0 describes, to the byte**),
  so the instrument was honest and the answer was no.

What survives is a partition rather than a diagnosis. One parse of the real
file, `built` clipped to each span (`procedural.py`, `blocks.py`):

| | bytes | built | stands | mends | bare leaves |
|---|---|---|---|---|---|
| declarations etc. | 14,836 | 13,394 | **90.3%** | 24 | 46 |
| 28 procedural blocks | 54,368 | 8,827 | **16.2%** | 1,400 | 1,544 |

**92.1% of the module's damage is procedural, and 69.9% of that is three
`always @(posedge clk)` blocks** of 17,547 / 13,349 / 4,881 bytes. Wrapped in a
bare module and parsed alone they reach 23.0% / 13.4% / 30.9% — so the damage
travels with the blocks and is not contamination. A fourth, `always @* begin` at
2,351 bytes, parses **100% whole with 0 mends** alone and reads **0.9%** in
situ, which is the contamination bound on the other three.

I could not name a construct inside them worth more than 68 bytes. I am
reporting that as the result rather than dressing a −167 up.

## Part 4 — the trap is real, and the rule for detecting it is not

The brief calls `--mend=keep` on this file *"the largest describing-less trap on
the board"*: +25,457 bytes for 9,550 fewer nodes. Both halves reproduce exactly.

| policy | built | Δ | describes | Δ | covered | spoil | rubble | bare leaves |
|---|---|---|---|---|---|---|---|---|
| fell | 30,720 | +0 | 22,222 | +0 | 50.8% | 43,346 | 17,324 | 2,481 |
| **keep** | 56,177 | **+25,457** | 12,672 | **−9,550** | **62.6%** | **32,274** | **3,107** | **48** |
| none | 2,045 | −28,675 | 1,513 | −20,709 | 3.8% | 89,546 | 1,546 | 44 |

By the earlier lane's sharper rule — *falling node counts are only reading-less
when `covered` falls or `spoil` rises alongside them* — this is not
reading-less: `covered` **rises** 11.8 points and `spoil` **falls** 11,072. That
is the exact falsification condition I wrote into P3, so I wrote down "the trap
is not a trap" and moved on. **That was wrong, and it is the flattering number
this lane found in its own work.**

`covered` is the union of top-level spans over file size; `spoil` is what is
left after `built`, `rubble` and `orphan` come out of it. Both are built from
the same spans as `built`. One root stretched across a hole raises `built`,
raises `covered` and lowers `spoil` in a single stroke — the rule asks two
questions that cannot disagree with the answer.

`stretch.py` asks an independent one: bytes a top-level construct claims with
**no token, at any depth, standing on them**.

| policy | built | tokens in built | stretch | stretched | honest built |
|---|---|---|---|---|---|
| fell | 30,720 | 26,538 | 4,182 | 13.6% | **26,538** |
| keep | 56,177 | 16,128 | 40,049 | **71.3%** | **16,128** |
| none | 2,045 | 1,682 | 363 | 17.8% | 1,682 |

**71.3% of `keep`'s `built` has nothing on it**, and netted out `keep` stands
over **10,410 fewer real bytes** than `fell`. The board's warning was right; the
trap is bigger than its headline; and the +11.8 points of `covered` is the same
40,049 bytes of hole counted twice. So P3 is **held on its claim and falsified
on its test** — the finding is that the `covered`/`spoil` guard cannot detect
the class of defect it was written for and should be `stretch` wherever it is
used as one.

A smaller instance of the same collinearity, in my own table: at top level
`rubble` **is** the bare-leaf byte count. `braces.py` printed both columns and
they were identical in every row, because the only non-`built` top-level spans
are the childless ones. One fact, two columns, and the appearance of
corroboration.

## Scoring the predictions

| | claim | outcome |
|---|---|---|
| P1 | directive lines worth ≥ 25,000 bytes | **falsified** — +9,788, 39% of the claim |
| P2 | comments leave `built` and `mends` unchanged to the byte | **held** — 30,720 -> 30,720, 2,109 -> 2,109 |
| P3 | `keep` is a trap: `covered` falls or `spoil` rises | **split** — the trap holds (71.3% stretch, −10,410 honest bytes); its test fails |
| P4 | warm peel names **fewer** than the cold peel's 40 | **held** — 10 distinct in 400 rounds |
| P5 | winning ablation raises `built` *and* `describes` | **held** — +11,529 / +5,192, and +8,175 after the stretch audit. **Both witnesses are ours**: `describes` is our node count and `built` our span union, so P5's condition cannot detect structure that is right by volume and wrong by parent. See the re-pointing at the head of this page |

P4 deserves its own line because it was the one I was least confident in, and
because the warm peel independently found what my ablations did. It reaches **9
walls the cold peel cannot**, at a back-half arrival rate of **0.0 per 100
rounds** — a bounded handful, not an onion — and **seven of the nine are `in
state 2394`**, which is the state my one-line reproducer for wall D lands in.
Two methods with nothing in common converged on the same state.

And then disagreed about its worth: **the state that recurs most is not the
state that costs most.** State 2394 dominates the warm peel and is worth −167
bytes; the two constructs worth 11,529 bytes are in states 3438 and 3761 and
the warm peel never dwells on them.

## The instrument I trust least — mine

`modules.py` first printed `picorv32_regs … 6790.4% standing`. `built` is a
union of top-level root spans, and a 343-byte module padded to 94,657 hands back
one root spanning the padding, so every blank byte counted as built. The three
walled modules in the same table scored 54–73% and looked perfectly reportable.
**The only reason the bug was visible is that one row was absurd**; had the file
held no tiny module, I would have published the contaminated numbers.

Second, quieter, same script: `procedurals()` matched `^\s*(always|initial)`,
and under `re.M` a `\s*` lets `^` match at an earlier blank line and eat the
newlines, so every block's label printed empty while its span was right. A bug
that damages only the presentation is the one that survives review.

Third, and I did not fix it: the whole ablation method has a blind spot this
file found. Blanking a construct removes the bytes it was contributing, so a
grammar gap and a productive construct both read as a negative delta and the
instrument cannot tell them apart. Every arm in `inside.py` is uninterpretable
for that reason. The method that worked instead was building the smallest module
that fails, from nothing — which is how D, E, F and G got named, and why all
four are exact.
