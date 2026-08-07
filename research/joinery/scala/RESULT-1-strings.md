# Result 1 — scala could not open a string

Treatment arm outliner `beb695b5d` · tree `e973ce73c` (pin) · oracle `d85e736fa`
(30 of 30 live, 30 attributed). Control arm outliner `aece1211e` · tree
`a9353c78b` · same oracle `d85e736fa` (30 of 30 live, 30 attributed).
`still against ocaml-orphan scala-string --mine src/kernel/lex/outside.zig
--mine src/kernel/lex/scanner_test.zig` reads **comparable**: two files differ
and this lane claims both.

## What was wrong

Scala walled on the last real string in its corpus file:

```
unexpected " at 20093 in state 610, 26 roots, mended 4 over 4B, supplied 0, spurned 1
verdict: scala: lexer on " in state 610 [no stand-in for _simple_string_start, admitted by shift]
```

Byte 20093 is the opening quote of `throw new NoSuchElementException("None.get")`.
The file holds 66 double-quote characters, but 31 of the 32 strings a regex finds
are inside scaladoc block comments - `"name"`, `"something"`, `"http"` - so
`"None.get"` is the only string in code, and it is 14 bytes from the end. Scala
parsed 20,093 of 20,107 bytes and then had nowhere to put a quote.

Scala was blind to 21 of its externals. `_simple_string_start` is the one that
mattered, and the verdict said which half of the row admitted it: **shift**, a
token that state would genuinely have consumed.

## The find that made this cheap

I was about to infer the spelling from the grammar rule, the way the kotlin lane
did, and `kotlin/RESULT-1-dot.md` names that as the thing it trusted least.
There was no need. The differential harness builds each grammar with its real
scanner, so **every upstream `scanner.c` is already on this machine** under
`.local/differential/lang/<grammar>/src/`. Nineteen of the thirty have one:
haskell at 3,471 lines, scala at 1,680, yaml at 1,417, bash at 1,217, ruby at
1,110, swift at 1,079, kotlin at 979.

That is a gitignored build artifact, not a repo path, so nothing may depend on
it - but for reading, it turns "what did the author mean by this external" from
an argument into a lookup. Every remaining blind-terminal lane on the board can
be done this way, and the kotlin rows I already shipped can be checked against
the C rather than defended from the rule.

## What the scanner actually does

The opener, and it settles a question the rule cannot:

```c
if (valid_symbols[SIMPLE_STRING_START] && lexer->lookahead == '"') {
    advance(lexer);
    lexer->mark_end(lexer);          // the token ends after the FIRST quote
    if (lexer->lookahead == '"') { advance(lexer);
      if (lexer->lookahead == '"') { advance(lexer);
        lexer->result_symbol = SIMPLE_MULTILINE_STRING_START;   // `"""`
        lexer->mark_end(lexer); return true; } }
    lexer->result_symbol = SIMPLE_STRING_START;                  // `"`
    return true;
}
```

So the start is exactly one byte, `"""` is a *different terminal* rather than a
longer reading of the same one, and `""` is an opener plus an end - the end mark
is already set before the second quote is looked at.

The body is `scan_string_content(lexer, false, STRING_MODE_SIMPLE)`, which loops
and stops three ways: a `"` is consumed and the token is
`SINGLE_LINE_STRING_END`; a `\` ends the token *before* itself as
`SIMPLE_STRING_MIDDLE`, because the escape is the grammar's own
`escape_sequence`; a newline or EOF returns false, so a simple string cannot
span a line. `$` is ordinary here - the interpolation branch is guarded by
`string_mode != STRING_MODE_SIMPLE`.

That is three patterns:

| terminal | spelling | from |
|---|---|---|
| `_simple_string_start` | `"` | mark_end after the first quote |
| `_simple_string_middle` | `[^"\\\n]+` | stops before the backslash, newline ends the scan |
| `_single_line_string_end` | `[^"\\\n]*"` | consumes the closing quote |

The `string_mode` that C function carries is the memory a hand would exist to
keep, and here the state already has it. `string -> _simple_string_start
(_simple_string_middle escape_sequence)* _single_line_string_end` admits the
middle and the end only after the start, and interpolation is a separate
production reached through a literal `imm('"')` the slate already lexes. So this
is the roll preamble's own case again and not a fence.

The middle and the end split the body the way rust's `string_content` /
`string_close` do, for a reason worth stating: at the offset after the opener
**both** match, and the end reaches one byte further because it takes the
closing quote, so longest wins. Where a backslash stops the end from reaching a
quote at all, the middle is the only reading left, and the grammar's
`escape_sequence` gets its turn.

## The guard that does not guard

My first version spelled only those three and put `never = {"\"\""}` on the
opener, so a `"""` would refuse rather than match one quote of a triple and read
`""` as an empty string. The regression test I wrote for it failed, and it was
right to: **a stand-in that refuses does not take the position.**

`Scanner.refusing` is a priority pass asked before the slate, and its docstring
says a failed trailing context loses the position outright. It does not. It
returns `null`, and `next` falls straight through to `s.reach`, where the same
row is still in the ordinary slate and matches the bare quote anyway. The
guard's real job is ordering - bash's `variable_name` has to beat `word` to
`rows=` - and I had read it as a veto.

So `"""` has to lose the position to *something*, and the honest something is
the longer opener. `_simple_multiline_string_start` gets a row spelled `"""`,
longest-match settles it exactly the way the C settles it by looking for two
more quotes before it commits, and **`_multiline_string_end` stays blind on
purpose**: it closes on three-or-more quotes not followed by a quote, and a
longest-match engine with no lazy repeat cannot spell a body that stops at the
first of them. A multiline string therefore refuses - which is what it did
before any of these rows existed, and the cheaper of the two failures the board
prices.

Four rows. Blind goes 21 -> 17.

## What it bought

One row of thirty moved:

| bucket | before | after | delta |
|---|---:|---:|---:|
| built | 407,367 | 411,517 | **+4,150** |
| square | 336,717 | 340,998 | **+4,281** |
| crooked | 33,653 | 33,653 | **0** |
| soft | 10,620 | 10,620 | 0 |
| unframed | 25,963 | 25,832 | -131 |
| unaudited | 414 | 414 | 0 |

Scala itself: `built 15,957 -> 20,107` (every byte of the file), `square 6,739
-> 11,020`, `crooked 1,938 -> 1,938`, `unframed 131 -> 0`. Its verdict is
`accepted, 1 root, surveyed 1780 of 5167 nodes` and its `damage` is 0.

Square rose by **more** than built did, because the 131 unframed bytes got a
frame as well. Not one newly built byte is judged wrong. That is the paying
direction, and it is worth putting beside `haskell/RESULT-2-cost.md`, where a
commit built 6,008 bytes, gained zero square and added 3,080 crooked - the same
board, the same oracle, opposite outcomes.

Corpus: `reached whole` **18 -> 19**, `trued` **63.9% -> 64.7%**.

## What it did not buy

`whole on ALL THREE` stays at **17**. Scala reads `trued 54.8%` on 1,938 crooked
bytes, and it carried all 1,938 before this change - `crooked` moved by exactly
zero corpus-wide and scala is the only row that moved at all. The board now
names scala in a list it was previously too broken to appear on: *"3 row(s) cost
more wrong than missing and are placed by `crooked`: swift, scala, kotlin"*.
That is a consequence of finally building a tree, not a cost of building it.

## What the next lane inherits

The eight orphan rows are two different defects wearing one bucket, and the
verdict tells them apart. Five of them no longer name a missing stand-in at all:

| grammar | damage | wall | class |
|---|---:|---|---|
| ruby | 444 | `heredoc_beginning` | blind terminal; needs the tag, so a hand |
| bash | 413 | `_concat` | blind terminal; zero-width, so a hand |
| ocaml | 2,182 | `line_number_directive` | blind terminal that is a declared *extra* |
| swift | 2,377 | not a blind terminal | table |
| sql | 2,309 | `_identifier`, which is not external | table |
| julia | 1,955 | no blind terminals at all | table |
| zig | 1,375 | no blind terminals at all | table |
| markdown | 3,126 | not a blind terminal (47 blind, none of them the wall) | table |

Julia and zig are the interesting pair: they hand nothing to a C scanner and
still lose 3,330 bytes between them, so whatever is wrong there is ours.

## What I trust least

**One string.** The corpus proves `_simple_string_start` and
`_single_line_string_end` on exactly one literal, `"None.get"`, with no escape
in it. `_simple_string_middle` is therefore **unexercised by any measurement
here** - it is spelled straight off the C and defended by a unit test I wrote,
which is a weaker thing than a byte moving. Same for `""`, and same for the
`"""` row, since the file holds zero triple-quote runs.

**The multiline opener is a row nothing on this board can reach.** It exists to
stop a wrong tree that no corpus file produces. I believe the argument - a
guarded `"` demonstrably matched one quote of a triple, which is how the test
caught it - but "this prevents a bug" and "no measurement here can tell" are
both true of it.

**Reading the scanner settles intent, not behaviour.** I read
`scan_string_content` and transcribed three stopping conditions into three
patterns. What I did not do is run tree-sitter's scanner and outliner's slate
over the same bytes and diff the token streams. The oracle compares *trees*, so
a spelling that is wrong in a way the parse recovers from would not show up in
+4,281 square.
