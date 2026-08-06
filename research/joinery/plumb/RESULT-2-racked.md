# Result 2 — the tree-aligned comparison, and what it costs

`tool/rack.py`. Compares **derivations**, not byte membership: for every built
byte, the ordered spine of `(name, named, start, end)` from the framing root
down, on both sides. A right leaf under a wrong parent is now the error it is.

Two pins, because the tree moved under me mid-lane and the honest thing is to
show both. Predictions were written against **`plumb`** (`dfc481e49`, tree
`bd7b3e939`, board 69.09%) and are scored there. Everything else is retaken on
**`rack2`** (`5226fef11`, tree `a271b4a39`, board **73.03%**) after a lex lane
seated Swift's `multiline_comment` and Kotlin's strings.

## The number

**83,169 of 384,715 built bytes are built in a shape tree-sitter does not
build.** `plumb` saw 33,634 of them.

| | of `built` | of adjudicable | of the 526,798-byte corpus |
|---|---|---|---|
| **all thirty grammars** | **21.62%** | **23.84%** | **15.79%** |
| **without php** | **13.22%** | **14.86%** | **8.17%** |

`plumb` read 9.24% / 13.05% / 6.38% and 0.7% without php. The corpus number
roughly doubled; the **non-php** number went up **nineteen-fold**, because php's
defect is a leaf that a leaf-indexed comparison could already see and everyone
else's defect is not.

**34,687 built bytes over verilog and sql have no verdict at all**, because
tree-sitter's own CST and XML disagree there — its tree has errors in it. That
includes `picorv32.v`, the corpus's largest damage row. The oracle is absent
exactly where parsing is hardest, and the first denominator above silently reads
those bytes as clean.

### The split

```
265,603 square + 47 renamed + 44,059 askew + 39,110 racked + 35,896 unjudged = 384,715
```

`racked` — **39,110 bytes** — is the class this lane exists to count: the
deepest node agrees and something *above* it does not. It is 47% of the wrong
shape and **essentially all of the non-php wrong shape** (39,110 of 43,039).
`plumb` files every one of those bytes as correct.

### And 27.7% of it is soft — `rack.py soft`

The part I would not defend. An `extra` (a comment, a blank line) attaches
wherever a parser chooses, and my walk charges every byte of it to whichever
spine it isn't on. tree-sitter swallows a leading scaladoc into the
`function_definition` it precedes; outliner keeps it a sibling. Neither has
misread anything.

| | crooked | soft | **hard** |
|---|---|---|---|
| all thirty | 83,169 | 23,031 (27.7%) | **60,138** |
| without php | 43,039 | 8,289 | **34,744** |

**Scala is 78.7% soft** — 6,820 of its 9,087 bytes are scaladoc placement — and
scala is the corpus's third-largest contributor. Read whole, this instrument
puts scala third; read honestly, scala is smaller than ocaml and haskell.

**The defensible number is 60,138 bytes: 15.63% of `built`, 17.24% of
adjudicable, 11.42% of the corpus. Without php, 34,744 — 10.67% / 11.99% /
6.60%.** Quote that one.

## The twelve whole grammars, individually — `rack.py whole`

**Three of the twelve are wrong, and all three are wrong in shape.** 73 bytes,
56 of them racked. Nine are genuinely clean, bracket for bracket.

| grammar | built | askew | racked | recall | the wrong shape |
|---|---|---|---|---|---|
| **toml** | 3,544 | 4 | 25 | 99.9% | `comment` where tree-sitter has `pair` |
| **python** | 1,728 | 5 | 22 | 99.4% | `print_statement` where tree-sitter has `call` |
| **go** | 1,189 | 8 | 9 | 98.9% | `type_conversion_expression` where tree-sitter has `call_expression` |
| java, javascript, typescript, rust, json, css, embedded-template, html, lua | 94,938 | 0 | 0 | 100.0% | — |

**This contradicts the brief, and it contradicts me.** The brief expected the
twelve to be where shape errors hide; I predicted at least three of the eleven
non-go grammars would be dirty (P3) and that html specifically would read
nonzero (P4). Both failed. **html is 72,288 bytes, 13,971 brackets, and every
single one is shared.** The nine clean grammars are clean at node granularity,
not merely at byte granularity, which is a much stronger statement than anything
the board could make about them.

So "whole" mostly does mean whole. It is wrong for **a quarter of the twelve**,
which is not nothing — but the headline this lane was pointed at is not the
finding.

### python is the one worth reading

`print(x)` derives as Python 2's print **statement**:

```
outliner                      tree-sitter
print_statement [0, 8)        call [0, 8)
  "print"                       identifier "print"
  parenthesized_expression      argument_list
```

`python.json` really does carry `print_statement` — tree-sitter-python keeps it
for Python 2 sources — so this is not an invented node. It is a live ambiguity
resolved the other way, and it costs: under `print_statement`, `print` is not an
identifier and `(x)` is not an argument list, so anything walking this tree for
calls does not see one. Handed over as
`specimen/python/print-as-statement.py`.

**toml is soft** and I am not claiming it. Its whole disagreement is where the
`#:c` comment hangs, and `comment` is a declared `extra` in `toml.json`.
44.8% soft by the same measure that convicts scala. Not filed as a specimen.

## The demonstration `plumb` could not see — 21 bytes of elixir

`specimen/elixir/do-block-on-inner-call.ex`:

```elixir
defp f(x) do
  x
end
```

```
outliner                      tree-sitter
call [0, 20)                  call [0, 20)
  identifier "defp"             identifier "defp"
  arguments [5, 20)  <-- 20     arguments [5, 9)   <-- 9
    call [5, 20)                  call [5, 9)
      identifier "f"                identifier "f"
      arguments "(x)"               arguments "(x)"
      do_block [10, 20)         do_block [10, 20)  <-- sibling of arguments
```

`defp f(x) do ... end` is `defp(f(x), do: ...)`; the block is an argument of
`defp`. Outliner hangs it inside the call being *defined*.

**Every leaf is identical.** All seven tokens, all seven extents, agreed.
`plumb` scores this file **0 misread bytes** — there is no leaf to index.
`rack` scores **15 of 21**.

That is not a curiosity: **elixir is the corpus's largest source of racked bytes
at 17,654**, more than every non-php grammar's total crooked, and **99.6% of it
survives the extras subtraction**. The brief was handed go; go is worth 9 bytes.

## The guard — yes, and it runs — `rack.py guard`

`covered` and `spoil` are built from the same top-level spans as `built`, so one
root stretched over a hole moves all three the flattering way. `square` is not:
it is agreement with a second parser's derivation, and a stretched root's bytes
have a spine the oracle does not share whatever the board's arithmetic says.

It fires. Across `--mend={none,keep,fell,relent}` on every grammar the oracle
reaches, **8 policy changes on 7 grammars buy `built` and pay `square`**:

| grammar | policy | Δbuilt | Δsquare |
|---|---|---|---|
| **swift** | `keep` | **+2,696** | **−11,582** |
| php | `relent` | +5,206 | −574 |
| swift | `relent` | +47 | −20 |
| ruby | `relent` | +56 | −114 |
| haskell | `keep` | +191 | −118 |
| latex | `relent` | +38 | −4 |
| bash | `keep` | +61 | −164 |

Swift's `keep` is the retired guard's failure reproduced exactly: **+2,696
`built` and −11,582 `square`.** A future lane claiming a `built` gain runs
`rack.py guard <grammar>` and reads whether `square` came with it.

**Its boundary, stated:** it cannot judge verilog, sql or yaml at all, and it
prints `THE GUARD CANNOT RUN HERE` rather than silence — which matters, because
verilog is the grammar the retired guard was retired over.

## Predictions — 5 held, 3 failed

Scored on the pin they were written against (`plumb`), per
`PREDICTION-2-racked.md`.

| | prediction | |
|---|---|---|
| P1 | corrected number exceeds 33,634 | **held** — 83,274 |
| P2 | exceeds the 68,321 defended ceiling | **held** — 83,274 |
| P3 | ≥3 of the eleven non-go whole grammars dirty | **FAILED** — two (toml, python) |
| P4 | html reads nonzero | **FAILED** — 0, and 13,971/13,971 brackets shared |
| P5 | over the twelve, `racked` > `askew` | **held** — 56 vs 17 |
| P6 | php still the largest contributor | **held** — 40,130 |
| P7 | my instrument lies first, on javascript | **FAILED** by its falsifier |
| P8 | the oracle can serve as the guard | **held** — 8 cases |

**P7 is scored failed and the claim held twice.** The falsifier named javascript
and javascript read exactly 0 on the first numeric run. The instrument lied
anyway, by two routes I had not imagined:

1. **Zig, 11,914 bytes — 81.3% of the grammar — charged to a spine that was
   otherwise identical rung for rung.** Outliner's root stops at the last token
   (`source_file [4163, 16124)`), tree-sitter's reaches EOF (`[0, 16125)`). My
   first containment rule dropped theirs for overreaching and kept ours, so
   every byte beneath disagreed. **The bracket-recall column read 99.9% at the
   same moment**, which is what a byte number driven by one wide node looks
   like. Fixed by judging only the derivation *below* the frame.
2. **`inorder` broke same-extent ties alphabetically by name.** A parent and its
   only child routinely share an extent — tree-sitter's `expression_statement
   [23, 35)` over `call_expression [23, 35)` — and `call_expression` sorts
   above its own parent while outliner's pair happened to sort right. It moved
   **340 bytes** between `askew` and `racked` corpus-wide and **left the total
   untouched**, so nothing else here would have caught it.

Both flattered this lane. Scored failed regardless: picking which route counts
is the move this lane exists to catch.

## The instrument I trust least — and it is this one

Not a hedge. Three demonstrations, in order of how much they cost.

**1. Extras placement — 23,031 bytes, 27.7% of my own headline.** Shown above.
`rack.py soft` exists so the number cannot be quoted whole without meeting it.

**2. The number moved 340 bytes between its two most load-bearing buckets and
nothing noticed.** The alphabetical tie-break. `askew` and `racked` are the
entire point of this file — one is "plumb already saw this", the other is "this
lane exists for this" — and they traded 340 bytes while the total, every
per-grammar row, and all nine tripwires stayed green. There is now a tenth
tripwire that asks the oracle's real go tree whether a parent still sorts above
its same-extent child; **it fails on the old ordering and passes on the new
one**, watched both ways.

**3. It decides which of two trees is wrong, and on toml I think it decides
wrong.** Every `crooked` byte is charged on the premise that tree-sitter is
right. For toml's 29 bytes that premise is doing all the work: the disagreement
is a declared `extra`, and outliner keeping the comment a sibling of `pair` is
at least as defensible as tree-sitter swallowing it. I report toml as one of the
three dirty whole grammars because that is what the measurement says, and I am
telling you I would not defend it.

## The corpus is a weaker instrument than any metric here

Handed to me mid-lane: a lex lane seated Swift's `multiline_comment`. `/* c\n d
*/` went from a `custom_operator` over a multiplicative expression to a single
`multiline_comment`. **Wrong before, correct after, and the board does not move
one byte** — those twelve bytes were `built` before and are `built` after.

`rack`'s swift row does not move either: 23,131 built, 14,275 square, 8,807
crooked, identical across both pins.

**But `rack` is not blind to it.** Run against a file that contains the
construct — `specimen/swift/multiline-comment.swift`, 33 bytes:

| | askew | brackets shared |
|---|---|---|
| before | **12 of 33** | 14/15 |
| after | **0** | **15/15** |

`Chunked.swift` contains **zero** `/*`. The board is silent because the corpus
is silent, not because the metric is coarse. Every instrument in this repository
— `standing`, `plumb`, and mine — is bounded above by what the corpus happens to
contain, and the only tier that caught this correctness change was the specimen
tier, because a specimen is built to contain the construct rather than found to.

That reframes the lane. I was sent to find a better metric over this corpus. The
better metric found 83,169 bytes and the sharper finding is that **a real fix
can be invisible to all three metrics at once and visible to a 33-byte file.**

*(Related: the 3,997 orphan bytes previously attributed to Swift's comment were
misattributed — `Chunked.swift` has no `/*`. Not chased; a lane classifying all
181 walls will name the real cause.)*

## What I changed, and what I did not

- **`tool/rack.py`** — new. `run · whole · show · soft · guard · board · verify`.
- **`tool/specimen.py`** — closed the shared-`zig-out` hazard (below).
- **`tool/standing.py`** — **not touched.** `rack.py board` reprints its rows
  unmodified, walks `standing.tops` rather than restating the scope, and closes
  on four checks it would fail: the four buckets still total 526,798, the split
  totals `built` on every judged row, it judged 384,715 of 384,715 built bytes,
  and `square` is neither 0 nor all of them.

### The specimen hazard, closed

`tool/specimen.py` fell back to the shared `zig-out` when `OUTLINER_BIN` was
unset and said nothing. A lane got **7 of 20 sound from a tree that builds 14 of
20** because a sibling rebuilt the prefix mid-run.

Now every report carries `stamp.line()`, and a run is **refused, exit 3**, when
it is both unattributed *and* the binary does not match the tree (`stale` or
`drift`). Narrowly: a deliberate pin drifts by design, and a fresh `zig build`
passes untouched — only the exact failure is refused. `--anyway` downgrades it
to a printed hazard. **It fired on its first run in this tree**, on a `zig-out`
older than `src/surface/face/outliner/state.zig`.

**It caught my own work.** My earlier specimen pass read 7 of 22; on a pin built
from the current tree it reads **15 of 22**. Everything above is retaken.

### Handed over

- `specimen/elixir/do-block-on-inner-call.ex` — the do-block on the inner call.
- `specimen/python/print-as-statement.py` — `print(x)` as a Python 2 statement.
- `specimen/kotlin/embedded-quote.kt` — **repaired a claim, by deleting it.**
  `lacks simple_identifier` was unsatisfiable: the file's own `val t` binds a
  name. It cost nothing to remove, because `spans string_literal 8 21` was
  already on the next line and says the whole thing — a reader that closes on
  the `"` at byte 13 cannot reach byte 21. Checked both ways before removing:
  **0/5 against the tree before Kotlin's strings were seated, 5/5 after.**
  Deleting an unsatisfiable claim is not weakening a live one, and that
  demonstration is the difference.

I did not fix php.
