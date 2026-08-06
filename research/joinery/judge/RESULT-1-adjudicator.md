# Result 1 — the oracle had an answer on 94% of the bytes it was said to refuse

Every number below was read on arm `judgelane` (binary from tree `1d7a512f8`,
repo `f7ba40004+145`), oracle `eacad4bfc` / tree-sitter 0.26.11, source
`upstream/sources/picorv32.v`, 94,657 bytes. Reproduce with
`python3 research/joinery/judge/judge.py`.

## 1. How tree-sitter actually fails on verilog

Not "it fails". It fails to **close the top-level parse**, and nothing else.

| | |
|---|---:|
| root node | `ERROR [0, 94657)` — 100% of the file |
| recovery nodes | **333** — 266 `ERROR`, 52 `MISSING ;`, 10 `MISSING ++`, 5 `MISSING end` |
| span of all recovery nodes **except the root** | **12,526 B — 13.2%** |
| nodes built | **48,883** |
| leaves built | **17,290** |
| does it crash / decline / time out | no, no, no |

The whole-file `ERROR` is the grammar failing to reduce a start symbol over the
file, so tree-sitter labels the top node as recovered and keeps everything it
built underneath. The four widest *inner* recovery spans are module
instantiations with named port connections
(`picorv32_axi_adapter axi_adapter (.clk (clk), …)`, 3,776 B;
`picorv32 #(.ENABLE_COUNTERS (…))`, 2,556 B), one `assign` chain (2,249 B) and
one `if` inside a `generate` (1,410 B). 67 of the 332 inner spans are
zero-width and 50 are a single byte — the long tail is inserted-token recovery,
not lost text.

**This is the finding that changes the lane.** `plumb.hurt()` taints a byte by
`ERROR` **ancestry**. With a root `ERROR`, every byte in the file inherits that
one node's verdict, and `rack.py`'s `veiled` branch — `who < 0 or (bad and not
tk)` — then refuses every un-leafed byte. The oracle was not silent. **The
distance the rule measures was wrong**: it asked an ancestor 94,657 bytes wide
instead of the node actually covering the byte.

## 2. The survey

I needed a judge for one question — *does a real SystemVerilog parser stand a
token on this byte?* — which is lexical, so tree-shape mapping was never
required and the survey collapsed to "who emits byte offsets, cheaply".

| candidate | tree with byte offsets? | licence | build | Python | verdict |
|---|---|---|---|---|---|
| [**Verible**](https://github.com/chipsalliance/verible) (Google → CHIPS Alliance) | **yes** — `--export_json --printtree/--printrawtokens`; every token carries `start`/`end` byte offsets, [documented as a stable contract](https://chipsalliance.github.io/verible/verilog_syntax.html) and Google [ships a Python driver](https://github.com/chipsalliance/verible/blob/master/verible/verilog/tools/syntax/export_json_examples/verible_verilog_syntax.py) for it | Apache-2.0 | **none** — [prebuilt macOS binary](https://github.com/chipsalliance/verible/releases), 7.9 MB | subprocess + JSON | **used** |
| [**slang**](https://github.com/MikePopoloski/slang) | yes (`--cst-json`), and `pyslang` exposes the tree in-process | MIT | **none** — `pip install pyslang` wheel | native bindings | **used, narrowly** |
| [**Icarus Verilog**](https://github.com/steveicarus/iverilog) | no — a simulator; the parse tree is an elaboration artifact, reachable only via target back-ends | GPL-2.0 | autotools | none | rejected |
| [**Surelog/UHDM**](https://github.com/chipsalliance/Surelog) | yes, a UHDM database with source ranges | Apache-2.0 | heavy CMake + submodules | via UHDM bindings | rejected — cost, and it is post-elaboration |
| IEEE 1800 grammar as a spec | n/a — derives expected *shapes*, cannot answer *did a token stand here* | — | — | — | not the question |

Both survivors installed and answered in **under 90 seconds combined**, which
is why the "is it worth seating one" question turned out to be cheap rather
than a judgement call. What is *not* cheap is seating one in `attest` — see §5.

**They disagree with each other by construction, and that is the useful part.**
slang runs the preprocessor: its first token is at byte 1,863 where Verible's
is at 1,018, and it covers 57,698 bytes to Verible's 74,194, because inactive
`` `ifdef `` branches and macro bodies leave no token behind. So slang
*under*-covers and cannot price a byte — it would free bytes that are code in
another configuration. Verible lexes the text as written, which is exactly what
tree-sitter and `outliner` are both doing. Verible prices; slang certifies.

### What each one says about the file

- **slang: zero syntax errors.** One diagnostic, `MisleadingIndentation`, a
  style lint. `picorv32.v` is unambiguously valid Verilog, so tree-sitter's
  whole-file `ERROR` is tree-sitter's and not the corpus's.
- **Verible: 10 parse errors**, all ten identical — `` `FORMAL_KEEP reg … ``
  (lines 691–699, 1184). `` `FORMAL_KEEP `` expands to nothing when `FORMAL`
  and `DEBUGNETS` are both undefined, and Verible does not expand macros, so it
  sees a macro call where a declaration must start. A preprocessor boundary,
  not a grammar hole — and it does not touch this lane's verdict, which is
  lexical.

## 3. The re-pricing

Same oracle, asked by **innermost cover** instead of by ancestry:

| | bytes | share | verdict |
|---|---:|---:|---|
| innermost cover is a **named construct** | **4,373** | 94.2% | `slack` — the oracle built structure here and left it un-leafed, as we did |
| …and **both trees name it identically** | 3,430 | 78.4% of those | not silence — **agreement** |
| innermost cover is `ERROR`/`MISSING` | **271** | 5.8% | **the bound** |
| no oracle node covers the byte | 0 | 0.0% | — |

The constructs the oracle built over the bytes it was said to be silent on:
`named_parameter_assignment` 644, `string_literal` 480, `operator_assignment`
356, `expression` 316, `seq_block` 229, `ansi_port_declaration` 211,
`conditional_expression` 208, `data_declaration` 185.

**The bound is 271 bytes — 0.29% of the file — and every one of them is
whitespace.** Verible stands a token on **0** of them; they are 185 runs, the
widest eight bytes of indentation each. Nothing available adjudicates them and
nothing plausible would charge them.

### Verible charges 590 of the freed bytes, and every one is a convention

Of the 4,373 freed, Verible stands a token on 590. That looked like a real
charge until it was broken down by what the oracle covers them with:

| oracle's innermost node | bytes | we build the same node on |
|---|---:|---:|
| `string_literal` | 480 | **480** |
| `attribute_instance` | 40 | **40** |
| `list_of_arguments_parent` | 38 | — (a tree-sitter-only node name) |
| `expression` | 24 | **24** |
| `conditional_expression` | 8 | **8** |

Every one is a byte **both** trees put under the same construct and **neither**
leafs. Verible emits one `TK_StringLiteral` spanning quotes and body; tree-sitter
and `outliner` both decompose a string into two quote-leaves around a bare
interior. Checked directly at `[53962, 54000)`: both trees carry
`string_literal [53962,54000)` with leaves only at `[53962,53963)` and
`[53999,54000)`. Charging these would be charging us for a tree-shape
convention, which is precisely what `warp` must never do.

**So `warp` stays 0 — by verdict from three parsers, not by default from one
declining.** `owed = damage + warp = 62,180 + 0 = **62,180**`, unchanged, and
`damage` was never a stretch column so it does not move either. The row's value
did not change. **What changed is that it is now a measurement.**

## 4. We do not beat tree-sitter on verilog

The brief's second premise was that verilog is the corpus's strongest case for
the claim. Measured against Verible's lexing (74,194 bytes carry a non-blank
token):

| | leaf bytes | of token bytes | nodes | leaves |
|---|---:|---:|---:|---:|
| outliner | 44,911 | **60.5%** | 23,497 | 9,394 |
| tree-sitter | 73,357 | **98.8%** | 48,883 | 17,290 |

| | bytes |
|---|---:|
| both stand a leaf | 44,867 |
| **only outliner** | **0** |
| only tree-sitter | 28,417 |

**Zero.** Checked over the whole file and not just the token bytes: there is no
byte of verilog we lex that tree-sitter does not. Our leaf set is a strict
subset of theirs, 44,911 ⊂ 73,357.

There is no proven improvement to document here, and this file is the record of
that. The one thing that *reads* like a win — that we emit no whole-file
`ERROR` — is a difference in what each tool does when it gives up, and
tree-sitter did not give up: it built 2.1× our nodes and 1.8× our leaves
underneath the label.

## 5. Why no second oracle was seated

`attest.rule()` digests the transitive closure of what the identity rule reads,
so a seated judge must be pinned, digested and reproducible on every arm and in
every before/after pair. That weight buys nothing here.

The verdict that moved the row — 4,373 freed, 271 bounded — came from the
oracle **already seated**, read by a rule that does not throw away 94% of its
answer. Verible and slang settled two facts that do not vary with a tree (*is
the file valid*, *is a token hiding here*), and re-checking a constant on every
board is paying an identity cost for nothing.

If it changes, seat **Verible**: byte offsets, no preprocessing, one static
binary with a release digest, and a JSON contract Google ships a driver for.
Its identity rule is one line — the release tag plus
`66e9c3c65206f2d3faf3ae13c68d7611dc5e70f0061732fb4513cad90d422d27`.

## 6. Tripwires

- `judge.py` runs with **neither** external judge present and prints the
  verdict marked uncorroborated, so the load-bearing number cannot silently
  depend on a machine-local download. The two judges are only ever asked
  questions whose answers do not vary with our tree, so a sibling fixing the
  product cannot dissolve this witness — the failure mode that took out two
  lanes this week.
- `judge.py` recomputes `rack.py`'s partition from `plumb` rather than reading
  the board, and prints `veiled` beside it; if the two ever disagree, the
  header line stops matching `rack.py run --only verilog`.
- The subset claim in §4 is asserted over the **whole file**, not over
  Verible's token mask, so it cannot be an artifact of the yardstick.

## 7. What I trust least

**First: the 271 bound is a floor on ignorance, not a ceiling.** It counts
bytes whose innermost cover is a recovery node. A byte whose innermost cover is
a *healthy* node that tree-sitter built **in the wrong place** is counted as
adjudicated `slack`, and this lane cannot tell those apart — the 78.4%
name-agreement figure is the only thing standing between that number and the
same blindness `plumb`'s ancestry rule had. On the 943 bytes where the two
trees name the innermost cover *differently*, I am trusting tree-sitter and
have not checked it.

**Second, and this is the one I would attack:** the fix here is a rule change,
and I have only demonstrated it on verilog. Ancestry-vs-innermost differs on
any row whose oracle tree carries a wide `ERROR`, and `veiled` reads 4,673
corpus-wide against verilog's 4,644 — so 29 bytes elsewhere would move too, but
I have not confirmed that no *other* column reads `plumb.hurt()` and would
shift under the same correction. **I have deliberately not changed
`plumb.hurt()` or `rack.py`** — both are live under other lanes, and a rule
change is theirs to make with the corpus-wide sweep I did not run.

**Third:** this is one file. Verilog's damage row is `picorv32.v` alone, so
every percentage here is a statement about one 94 KB source and the phrase
"verilog" is doing more work than it has earned.

**Fourth:** the arm reports `DRIFT — the binary's tree 1d7a512f8 is not the
repo's`, which is correct and expected for an isolation arm but means these
numbers describe a tree that siblings have already moved past. `damage 62,180`
reproduced exactly on this arm; the rest was measured nowhere else.

**Fifth:** `TESTING.md` line 971 states that "sql and verilog have no oracle we
can build from their pinned sources". On this arm `pin.py oracle judgelane`
minted 30 of 30 verdicts and `rack.py` scored verilog against a real
tree-sitter oracle. Those two statements are about different paths — the press
survey versus the differential — but one of them is stale, and it is not mine
to fix.
