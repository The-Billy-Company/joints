# Prediction 1 — what the 18 "grammar gaps" turn out to be

Written after locating all eighteen constructs in the corpus and reading each
grammar's `externals` array, and **before running tree-sitter or joints over a
single witness.** That ordering is deliberate and it is the only ordering that
makes a score mean anything here; it also means these predictions are informed
rather than blind, and the informed half is written down below so a reader can
discount it.

What I knew when I wrote this:

* the source text at all eighteen wall offsets (`locate.py`), so I know what
  construct each row is actually about;
* the `externals` array of every grammar involved, so I know which rows *could*
  be scanner work and which structurally cannot be.

What I did not know: whether tree-sitter accepts any of them, whether joints
accepts any of them standing alone, or what either tree looks like.

## The eighteen, as located

`GAPS.md` prices these by peel bytes and names them by `<terminal> in state <n>`.
The state number is not the key — two binaries differing by one line renumber
the whole LR(0) collection — so every row below is keyed on the **byte offset and
the source text there**, which no rebuild can move.

| # | grammar | GAPS row | B | the construct actually standing there |
|---|---|---|---:|---|
| 1 | php | `/` s68 | 40,996 | `preg_replace("/(.*)\s.*/", '$1', $trimmed)` — the `/` is *inside* a double-quoted string |
| 2 | kotlin | `,` s110 | 35,369 | `private object EmptyMap : Map<Any?, Nothing>, Serializable {` — the `,` between two supertypes |
| 3 | elixir | `alias` s100 | 25,556 | `routes \|> Enum.map(...)` — a capitalised alias after `\|>`, all 14 hits |
| 4 | julia | `_word_identifier` s674 | 3,420 | `@assert (a && b \|\| c && d) "type mismatch"` then the next statement |
| 5 | cpp | `"` s907 | 638 | `push("seed" + std::to_string(i), seed[i]);` |
| 6 | bash | `]` s35 | 495 | `if [[ ! $value =~ ^-?[0-9]+$ ]]; then` |
| 7 | elixir | identifier regex s100 | 148 | `\|> then(fn {a, b} -> ... end)` — a lowercase call after `\|>` |
| 8 | zig | `{` s715 | 58 | `pub const whitespace = [_]u8{ ' ', '\t', ... };` |
| 9 | verilog | `` ` `` s534 | 36 | `` `endif `` inside a module port list |
| 10 | verilog | `` ` `` s3438 | 21 | `` `ifdef RISCV_FORMAL `` inside a module port list |
| 11 | cpp | `;` s184 | 14 | `std::cout << kBanner << "total=" << led.total() << "\n";` |
| 12 | latex | `<` s1739 | 10 | `\usepackage{latexsym,<packages>}` inside `\begin{verbatim}` |
| 13 | scala | `"` s610 | 9 | `throw new NoSuchElementException("None.get")` |
| 14 | c | `,` s822 | 8 | `fputs(BANNER, stdout);` |
| 15 | c | `"` s401 | 7 | `printf("total=%ld\n", ledger_total(&l));` |
| 16 | swift | `(?:[^\r\n]*)` s66 | 7 | `endOfChunk(startingAt: base.startIndex, offset: 0)` |
| 17 | c | `%` s171 | 3 | the `%` inside `"total=%ld\n"` |
| 18 | verilog | `2` s1328 | 3 | `{..., mem_rdata_latched[6], 2'b00};` — a sized literal in a concatenation |

**GAPS.md renders rows 9 and 10 with an apostrophe.** The terminal is a
**backtick**; the generator wrapped it in backticks inside a markdown table and
the cell collapsed. A lane authoring a witness from that column alone would
write Verilog string-quoting code and adjudicate the wrong construct. Rows 9, 10
and the state-0 `` ` `` row are all this.

## The method each prediction is scored against

For each row: author a minimal, self-contained file in that language holding the
construct, then

* **joints** parses it (`joints parse <folio> <witness>`) — whole or walled;
* **tree-sitter 0.26.11** parses it from the same `grammar.json` — tree, with or
  without `ERROR`/`MISSING`;
* **tree-sitter again with a stubbed external scanner** — every
  `tree_sitter_<lang>_external_scanner_scan` replaced by one that returns
  `false`, so the parse runs on `grammar.json` alone. This is what separates
  *ours* from *external*, and it is an experiment rather than a name lookup: a
  terminal can be declared external and never be the reason a construct parses.

Innocent controls ride along: constructs from the same grammars that nothing
has ever walled on. A harness that calls everything a gap and a harness that
calls nothing a gap both score well without them.

---

## P1 — the gap column is mostly wrong, by bytes

**≥ 80% of the 106,798 B adjudicates to something other than `real gap`.**
Falsified below 50%.

Reasoning: rows 1, 14, 15, 17 are walls *inside or at the edge of a string
literal*, and every language here has string literals. Row 3 is `|> Enum.map`,
which is the single most common line of Elixir written. Rows 9 and 10 are
`` `ifdef ``, and tree-sitter-verilog carries 704 rules precisely so it can
parse the preprocessor. A grammar with no derivation for any of those is not a
grammar anybody shipped.

## P2 — the two biggest are not gaps, and they part company

**Rows 1 and 2 — 76,365 B, 71.5% of the total — both return a tree-sitter tree
with no `ERROR` or `MISSING` over the construct.** Falsified if either errors.

And they land in **different** columns: **php is `external`** (it declares
`encapsed_string_chars`, and the body of a double-quoted string is exactly what
that token is for), **kotlin is `ours`** (it declares string and semicolon
externals, and a comma between two supertypes is none of them). Falsified
independently: php still parsing with the scanner stubbed makes it `ours`;
kotlin failing with the scanner stubbed makes it `external`.

## P3 — six rows structurally cannot be external, and that is checkable before
anything runs

**zig, verilog and c declare zero externals**, so rows 8, 9, 10, 14, 15, 17, 18
— seven rows, 136 B — can only be `real gap` or `ours`. **I predict at least 5
of those 7 are `ours`.** Falsified if 3 or more stand as real gaps.

This is the cheapest prediction on the page and it is here because it is the one
that cannot be rescued by an "it was the scanner" story.

## P4 — at least four rows are `external`, and the named candidates are these

**≥ 4 of 18 are `external`.** Falsified at 1 or fewer.

Named in advance, with the token I expect to be responsible:

| row | grammar | the external I expect to be doing the work |
|---|---|---|
| 1 | php | `encapsed_string_chars` |
| 4 | julia | `_immediate_paren` — `@assert (x)` with a space is not an immediate paren, and that distinction is the whole construct |
| 6 | bash | `regex` / `test_operator` — `=~ ^-?[0-9]+$` inside `[[ ]]` |
| 12 | latex | `_trivia_raw_env_verbatim` — the wall is literally inside `\begin{verbatim}` |
| 13 | scala | `_simple_string_start` / `_simple_string_middle` |

Naming five when predicting four leaves room to be wrong about one and still
have made a real prediction rather than a hedge.

## P5 — the mechanism, and this is the one I care about

**≥ 6 of the 18 walls refuse a terminal the language does not have at that
byte.** Falsified below 3.

`/` inside `"/(.*)\s.*/"`, `%` inside `"total=%ld\n"`, `"` opening a string,
`(?:[^\r\n]*)` where a `0` stands — in each of those the wall's terminal is a
**lexing outcome**, not a token of the program. And that is the failure mode
`settled` cannot see: asked "does the grammar derive `%` in this state", the
closure correctly answers no, because the program has no `%` there. The verdict
is sound about a terminal that does not exist and is filed as a fact about a
construct that does.

If P5 holds, `gap` is not merely over-claimed; the question it asks is
undefined whenever the lexer has already gone wrong, and no fix to `settled`
repairs that.

## P6 — a witness that joints parses whole

**≥ 4 of 18 witnesses parse whole in joints**, i.e. the construct is
derivable here and the corpus wall is context, not the construct.

Falsified at 0. **Named limit, before the fact:** a minimal witness parsing
whole does not prove the corpus wall is spurious — it proves the grammar
derives the construct, which is enough to void a `gap` verdict and not enough
to price the bytes anywhere else. I will report those rows as `ours` on the
verdict and as *unpriced against the file* on the bytes, rather than moving
them into a column I cannot defend.

## P7 — both wrong

**≥ 1 row where both parsers return a tree and both trees are wrong.**
Falsified at 0. Lowest confidence on the page; the verilog lane found two such
spans in 20 adjudications, and my rows are mostly one-line constructs where
there is less room to be creatively wrong.

---

## What would make me retract the whole exercise

If the innocent controls — constructs from these grammars that have never
walled — come back walled in joints too, then the witnesses are measuring my
ability to write valid PHP rather than anything about the grammar, and none of
the eighteen verdicts survive that.
