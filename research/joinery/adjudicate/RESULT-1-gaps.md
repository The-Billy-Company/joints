# Result 1 — the eighteen, adjudicated

**Of the 106,798 B `GAPS.md` files as work nobody in this tree can do, 60 B
survive contact with tree-sitter.**

Not 60%. Sixty bytes — three verilog walls, all of them preprocessor directives
standing inside a module port list. Everything else parses on the other side of
the same `grammar.json`, and the largest column on the board has been telling us
to stop looking at our own work.

| verdict | rows | bytes | of the 106,798 |
|---|---:|---:|---:|
| **gap** — tree-sitter refuses it too | 3 | 60 | 0.1% |
| **external** — tree-sitter parses it, and only with its C scanner | 6 | 67,214 | 62.9% |
| **ours** — tree-sitter parses it from `grammar.json` alone | 7 | 39,503 | 37.0% |
| **void** — both parsers take the construct | 2 | 21 | 0.0% |
| **both wrong** | 0 | 0 | 0.0% |

Measured twice, on two binaries built from two different trees
(`df015ae32`/`f7c6b3ef0` and `93513d7c8`/`986eb8ece`), byte-identical both
times. State numbers renumber between builds; none of these verdicts is keyed on
one.

## The board

`outliner` is what our parser did with the witness. `wall` compares the terminal
it actually refused against the one `GAPS.md` names. `tree-sitter` and `blinded`
are the oracle with its scanner live and with every external answered `no`, and
both are read **only over the construct's own byte span**.

| row | grammar | B | outliner | wall | tree-sitter | blinded | verdict |
|---|---|---:|---|---|---|---|---|
| php-encapsed | php | 40,996 | mended | same | clean | refuses | **external** |
| kotlin-supertypes | kotlin | 35,369 | mended | same | clean | clean | **ours** |
| elixir-pipe-alias | elixir | 25,556 | mended | same | clean | refuses | **external** |
| julia-macro-juxt | julia | 3,420 | mended | same | clean | clean | **ours** |
| cpp-string-concat | cpp | 638 | mended | same | clean | clean | **ours** |
| bash-regex-test | bash | 495 | mended | `[` ≠ `]` | clean | refuses | **external** |
| elixir-pipe-call | elixir | 148 | mended | same | clean | refuses | **external** |
| zig-char-array | zig | 58 | mended | same | clean | *no scanner* | **ours** |
| verilog-endif | verilog | 36 | mended | same | refuses | *no scanner* | **gap** |
| verilog-ifdef | verilog | 21 | mended | same | refuses | *no scanner* | **gap** |
| cpp-stream-chain | cpp | 14 | **whole** | accepts | clean | clean | **void** |
| latex-verbatim | latex | 10 | mended | `\documentclass` ≠ `<` | clean | refuses | **external** |
| scala-string-arg | scala | 9 | mended | same | clean | refuses | **external** |
| c-fputs-comma | c | 8 | mended | same | clean | *no scanner* | **ours** |
| c-open-quote | c | 7 | mended | same | clean | *no scanner* | **ours** |
| swift-labelled | swift | 7 | **whole** | accepts | clean | refuses | **void** |
| c-format-percent | c | 3 | mended | `"` ≠ `%` | clean | *no scanner* | **ours** |
| verilog-sized | verilog | 3 | mended | `;` ≠ `2` | refuses | *no scanner* | **gap** |

Every grammar's innocent control parsed whole. That was the stated retraction
condition and it did not fire.

## The six externals, with the token doing the work

These are **67,214 B of seatable work**, not damage. Each row names the declared
external whose absence explains it, and each is confirmed by the blinded arm
breaking on the construct while the live arm is clean.

| row | B | the external | why it is that one |
|---|---:|---|---|
| php-encapsed | 40,996 | `encapsed_string_chars` | the refused `/` is *inside* `"/(.*)\s.*/"`. With no string-content token, `/` lexes as division. |
| elixir-pipe-alias | 25,556 | `_newline_before_binary_operator` | `\|>` opening a continuation line is exactly what that token exists to announce. |
| elixir-pipe-call | 148 | `_newline_before_binary_operator` | same defect, lowercase callee instead of an alias. **One fix, 25,704 B.** |
| bash-regex-test | 495 | `regex` (and `_regex_no_slash`/`_regex_no_space`) | `=~ ^-?[0-9]+$`; without it the `[` of `[0-9]` lexes as a bracket. Narrowed: `[[ ! $v =~ x ]]` parses whole here — a regex with no metacharacter needs no scanner. |
| latex-verbatim | 10 | `_trivia_raw_env_verbatim` | narrowed to `plain words only` inside `\begin{verbatim}` and it still walls. The body is the construct; `<` was incidental. |
| scala-string-arg | 9 | `_simple_string_start` / `_simple_string_middle` | `new NoSuchElementException("None.get")`. |

Two of the six were not named in advance (both elixir rows); four of the five
named in advance were right. **They go to the specimen/externals lane**, which
reports 461 declared, 252 seated, 36 witnessable, 21 exercised — these are four
distinct unseated externals across four grammars.

## The seven ours, and the one shape they share

**39,503 B of press work filed as unreachable.** Six of the seven are a refusal
*at or immediately after a string or literal*, and the four c/zig rows are in
grammars that declare **no externals at all**, so no scanner story can rescue
them.

| row | B | what we refuse that tree-sitter takes from the same file |
|---|---:|---|
| kotlin-supertypes | 35,369 | `object EmptyMap : Map<Any?, Nothing>, Serializable` — the comma between two supertypes |
| julia-macro-juxt | 3,420 | `@assert (a && b) c` — a macro call with a juxtaposed second argument |
| cpp-string-concat | 638 | `push("seed" + std::to_string(i), seed[i])` |
| zig-char-array | 58 | `[_]u8{ ' ', '\t' }` |
| c-fputs-comma | 8 | `fputs(BANNER, stdout);` |
| c-open-quote | 7 | the opening `"` of `printf("total=%ld\n", …)` |
| c-format-percent | 3 | the `%` inside that same string — **downstream of the row above** |

The last two are **one defect wearing two prices**. The `"` walls first in every
C source where a `%` can appear at all, so `c-format-percent` can never be
reached independently; `GAPS.md` prices it as a separate wall.

`julia-macro-juxt` was bisected five ways because the corpus construct carries a
string. `x = "msg"` parses whole here; `@assert (a && b) "msg"` walls; `@assert
(a && b) c` walls too and is **clean with julia's scanner blinded**. So the
juxtaposition is derivable from `grammar.json` and the string is not the defect —
the row is `ours`, not the `external` I predicted.

## The three real gaps, and the caveat they carry

| row | B | construct | tree-sitter |
|---|---:|---|---|
| verilog-endif | 36 | `` `endif `` inside a module port list | `(ERROR [8,0]-[8,6])` |
| verilog-ifdef | 21 | `` `ifdef RISCV_FORMAL `` inside a module port list | `(ERROR [5,0]-[6,7])` |
| verilog-sized | 3 | `{a[12:11], b, 2'b00}` | `ERROR` over the concatenation |

Verilog declares **zero externals**, so there is no scanner to appeal to and
these are honest refusals of `grammar.json` itself.

**Say it per row, as the brief asks: verilog is where this oracle is weakest.**
`rack --square` prints `THE GUARD CANNOT RUN HERE` for verilog because the
oracle refuses the grammar outright on corpus files, and the verilog lane
retired the guard. My witnesses are 4-line modules the oracle *does* answer on,
which is why these rows are measurable at all — but the only three bytes I
certify as upstream's sit in the one grammar where the cross-check cannot run.
**Sixty bytes is the number to distrust here, and it is the only number that
survived.**

`verilog-sized` also shows `GAPS.md` misnaming its own construct. The row blames
the sized literal `2'b00`; `{a, b, 2'b00}` parses **whole** here and clean in
tree-sitter. The refusal is the **part-select** `a[12:11]` inside a
concatenation. And narrowed to `{a[12:11], b}`, tree-sitter answers with
`(MISSING "++")` — a token the file does not contain — so that neighbourhood is
`both wrong`, though the row as `GAPS.md` states it is not.

## The two void rows

`cpp-stream-chain` (14 B) and `swift-labelled` (7 B) **parse whole in outliner**.
There is no defect at those constructs on either side; the wall exists because
the peel resumed mid-file and asked about a byte in a context the construct never
has. `GAPS.md`'s swift row names the terminal `(?:[^\r\n]*)` — a comment-body
pattern — standing where `startingAt:` is written. That is not a construct
refusing to parse; it is a lexer already lost.

I am **not** moving those 21 B into `ours` on the file. The witness proves the
grammar derives the construct, which voids the `gap` verdict and is not enough to
price the bytes anywhere else. That limit was written down in the prediction
before the result, and it is the same limit that applies to the four `wall ≠
GAPS.md` rows.

## The revised split, over all 181,588 B

| owner | bytes | share | was |
|---|---:|---:|---|
| **ours — press work** | 57,321 | 31.6% | 17,797 (9.8%) |
| **ours — externals to seat** | 74,468 | 41.0% | 7,254 (4.0%) |
| **upstream, genuinely** | 60 | 0.03% | 134,358 (74.0%) |
| stranded — neither owner | 22,179 | 12.2% | 22,179 (12.2%) |
| gap, unadjudicated (state-0 resume artifacts) | 27,560 | 15.2% | — |

Press work is 17,797 conflict + 39,503 gap→ours + 21 void. Externals are 7,254
scanner + 67,214 gap→external. The 27,560 B left in `gap` are the **24 state-0
walls the owners lane itself flagged "not real"**; I did not adjudicate them and
I am not claiming them, but every one of the two I checked in that shape
(`cpp-stream-chain`, `swift-labelled`) came back `void`, so that column is more
likely to shrink than grow.

**Work this tree can do: 131,789 B, 72.6%.** The number the previous file
reported was 9.8%.

## Self-score

Seven predictions, written after locating the constructs and before running
anything. **Three held, two falsified, two cleared their floor and missed their
claim.**

| | claim | result | |
|---|---|---|---|
| **P1** | ≥ 80% of bytes are not a real gap | **99.94%** | held |
| **P2** | php and kotlin both clean, and they part company (php `external`, kotlin `ours`) | exactly that, 3/3 | held — **with a disclosure below** |
| **P3** | of the 7 rows in zero-external grammars, ≥ 5 are `ours`; falsified at 3 real gaps | 4 ours, **3 real gaps** | **falsified** |
| **P4** | ≥ 4 rows `external` | 6 | held; 4 of 5 named candidates right, julia wrong, both elixir rows unnamed |
| **P5** | ≥ 6 walls refuse a terminal the language does not have at that byte; falsified below 3 | **5** (php `/`, c `%`, bash `[`, latex body, swift comment-pattern) | claim missed, floor cleared |
| **P6** | ≥ 4 witnesses parse whole in outliner; falsified at 0 | **2** | claim missed, floor cleared |
| **P7** | ≥ 1 row where both trees are wrong; falsified at 0 | **0** on the rows as stated | **falsified** |

**P7 could have been scored green and is not.** Narrowing `verilog-sized` to
`{a[12:11], b}` makes tree-sitter emit `MISSING "++"`, which is a token the file
does not contain and is exactly what P7 describes. But the prediction was about
*a row*, and no row as `GAPS.md` states it produced one. Counting the narrowing
would be scoring a verdict invented after the prediction, which is the specific
thing the previous lane confessed to and the reason this line exists.

**P2's disclosure.** The first table this harness printed said kotlin was
`external`, which would have falsified half of P2. I then changed the instrument
to read errors over the construct's byte span instead of the whole file, and
kotlin became `ours`. That ordering is exactly how a prediction gets rescued by a
knob, so here is the evidence that it was a repair and not a knob: the
construct sits at `[2,26]-[2,58]`, and blinded kotlin's **only** error is
`(ERROR [5,17]-[5,23])` — the word `equals`, three statements away. Blinding
removes `_automatic_semicolon` along with everything else, and a whole-file
reading was filing **35,369 B** on evidence about a function name. `prove` now
holds both directions of that test. Discount P2 as you see fit; the underlying
fact — kotlin clean with its scanner stubbed — does not depend on the reading.

**P3 is the one that hurt and it is the informative failure.** I predicted
grammars with no scanner would be where our own defects concentrate, and they
are — 4 of 7 — but I also assumed tree-sitter-verilog's 704 rules meant it
parsed the preprocessor. It does not parse it *in a module port list*. The three
bytes of that assumption are the entire upstream column.

## Reproducing

```bash
export OUTLINER_BIN=$PWD/.local/pin/adjudicate2/bin/outliner
python3 research/joinery/adjudicate/adjudicate.py run
python3 research/joinery/adjudicate/adjudicate.py prove          # 6 guards
python3 research/joinery/adjudicate/adjudicate.py probe php-encapsed
python3 research/joinery/adjudicate/locate.py php kotlin          # row -> byte -> source
```
