# walk — the ordinary parse, on purpose

Everything else in `kernel/` is trying to avoid walking a file left to right.
This folder does it anyway, because two things need it and both are load-bearing.

**It is the oracle.** Every claim about composing segments is a claim that the
product equals the walk. A claim like that is worth exactly as much as the walk
you can check it against, so the reference implementation is kept obvious rather
than fast.

**It is where a true token stream comes from.** Real terminals are
context-dependent. A JSON grammar's `string_content` is `[^\\"\n]+`, legal only
between quotes; offered unconditionally it eats the rest of the line. So the
only honest token stream for a real grammar is one lexed *from the parse state*,
and that needs a parser walking beside the lexer. Every measurement in
[`research/joinery/TESTING.md`](../../../research/joinery/TESTING.md) starts from
a stream produced here.

| File | What it is |
|---|---|
| `drive.zig` | LR state stack, `Expected` refilled per token from the current state's action row, textbook reduce-then-shift loop. Returns the tokens it consumed and an `Ending` that names the exact byte or token that stopped it. |

## What the valid-symbol set is read from

Nothing is maintained alongside the parser. The terminals a state accepts are
the columns of its action row that are not `err` — which is right precisely
because the reduce entries are in there too, so a state that would fold before
shifting still offers everything the fold leads to. Tree-sitter keeps the same
set; it generates it into the parser instead of reading it off the table.

## A consequence worth knowing before you debug a grammar

Because the lexer is only ever offered legal terminals, **a wrong token usually
cannot lex at all**. `{"a" "b"}` against a grammar wanting `:` does not report
*unexpected `"`* — it reports a stray byte at offset 5, because after a closing
quote the state offered only `:` and whitespace and neither matches there.

That is sharper about *where* and blunter about *what*. Naming the offending
token needs a second, unconditional lex at that offset, which is a recovery
feature and not something the walk should guess at. The `Ending.unexpected`
variant stays for a table that disagrees with itself; in a well-formed grammar
you will see `stray`.
