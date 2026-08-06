# Prediction 1 — which string interiors carry a memory

Written before the census was run, before a line of Zig was touched, and
before any board was taken after the baseline of 2026-08-05T19:34Z.

## The axis

Not "does the grammar rule look stateful" — that produced a false positive
immediately last session (bash's `file_descriptor` is `[0-9]+` before a `>`
and read as stateful from its rule shape). Tree-sitter forces a scanner to
declare its whole memory through `serialize`/`deserialize` so the runtime can
snapshot it at every GLR fork. So the axis is exactly: **what does `serialize`
write?**

## What the three scanners write

Read out of the pinned sources under `.local/breadth/lang/<name>/src/scanner.c`.

| Grammar | `create` | `serialize` writes | Reading |
|---|---|---|---|
| julia | `return NULL` | `return 0` | **no memory at all** |
| kotlin | `ts_calloc` an `Array(char)` | the whole stack, 2 bytes per frame: `[delimiter\|triple, prefix_len]` | a **stack** — nesting is real |
| swift | `calloc` one struct | 4 bytes, `uint32_t ongoing_raw_str_hash_count` | a **scalar** — one live raw string |

Julia's is the whole file's answer in two lines:

```c
void *tree_sitter_julia_external_scanner_create() { return NULL; }
unsigned tree_sitter_julia_external_scanner_serialize(void *p, char *b) { return 0; }
```

A scanner that snapshots nothing has nothing to snapshot. Every one of julia's
sixteen externals is therefore a function of the bytes at the offset and the
`valid_symbols` set — which is precisely the pair `marrow` is defined over,
and precisely the pair the soundness bar allows (**bytes and memory, never
which reading asked** — with the memory here empty).

## P1a — julia is seatable with no new carried state

`scan_content(lexer, symbol, end_char, n_delim, interp)` is
`marrow.Mark{ .shut, .wide, .interpolates }` with the arguments renamed. The
eight `_content_{str,cmd}_{1,3}[_raw]` terminals are eight rows of that table,
and `marrow.zig`'s own header already says so, sight unseen, in the sentence
that defines `Family`.

**Falsifier:** a field in julia's `serialize`, or a `scan_content` argument
that is not derivable from the terminal the state named.

## P1b — the parse state separates the eight, so no byte has to

If two content terminals of different width are co-admitted **by shift** in
one state, then a hand asked at that offset cannot know whether the close is
`"` or `"""`, and the width would have to come from a memory julia does not
keep. The whole `Family` premise is that it never happens.

I predict: **zero co-admission-by-shift between any two of the eight**, and
`_end_str` co-admitted with str-content terminals only (never with cmd).

**Measurement:**

```
outliner state upstream/grammars/julia.json --census \
  _content_str_1 _content_str_3 _content_str_1_raw _content_str_3_raw \
  _content_cmd_1 _content_cmd_3 _content_cmd_1_raw _content_cmd_3_raw \
  _end_str _end_cmd
```

**Falsifier:** any co-admitted-by-shift pair of differing `wide`. One state is
not zero — the swift `_bang_custom`/`_fake_try_bang` precedent is that a
single state is enough to keep a seating out.

## P1c — `_end_str` is one terminal for two widths and still needs no memory

Julia declares one `_end_str` for both `"` and `"""`. The C never asks a
memory which it is: `scan_content` emits `END_STR` from *inside* the content
scan, so the width is the `n_delim` of whichever content terminal was valid at
that call. If P1b holds, the state names the width, and the hand can too.

**Falsifier:** a state admitting `_end_str` with both `_content_str_1` and
`_content_str_3` shiftable. Then the width is genuinely ambiguous and julia
joins kotlin.

## P1d — kotlin and swift cannot use julia's trick

`marrow` gets away with a captured close (c++ `R"tag(`, lua `[==[`) because
the opener is **immediately behind** a content offset by construction, so the
capture is a fixed walk backwards through live bytes rather than a carry.

Kotlin and swift both interpolate: `"a ${ f("b") } c"` re-enters content after
the `}`, arbitrarily far from the `"` that opened it, and kotlin's stack has
depth for exactly that reason. So the backwards walk cannot recover
`is_triple` or `prefix_len`, and these are `fence` (a mark stack) rather than
`marrow`.

**Falsifier:** every string-content offset in `upstream/sources/Maps.kt` and
`Chunked.swift` sits immediately behind its own opener. Then a walk suffices
and the memory is decoration.

## P1e — what I expect to be wrong about

The honest place for this to break is that julia's `scan_content` is *not*
elixir's `matter` with different arguments, even though both are "run to a
delimiter". Two differences I can already see in the C and expect to cost a
separate walk rather than a row:

- julia refuses at end of input (`while ((next = lexer->lookahead))` falls out
  and `return false`), where elixir's `matter` hands back matter-to-the-end;
- julia's interpolation sigil is a bare `$`, elixir's is `#{`; and julia's
  raw branch also stops on `\\`, where elixir's stops only on its own
  delimiter.

If I try to reuse `matter` with a wider `Mark` I will silently change
elixir's answers. Prediction: a **separate walk** is required, and the check
that catches me if I take the shortcut is elixir's own board row and tree
staying byte-identical.
