# Result 1 - markdown is not a stand-in problem

`RESULT-6-fragment.md` corrected the work list and markdown came out first:
**3,284 bytes on the document, 72% of everything left**, and the only grammar on
the board whose wall cost is entirely real - 0% fragment. This is what it costs
to find out that the mechanism everyone would reach for cannot have it.

The cheap rung was disproved before it was built. That is the whole result.

## What markdown does today

`upstream/sources/README.md`, 3,304 bytes:

```
joints: markdown: blind to 47 externally scanned terminal(s)
joints: markdown: 1 pattern(s) the engine would not build: entity_reference
joints: ... stray byte at 20, 430 roots, mended 79 over 79B
joints: markdown: lexer? at byte 20 (unlexed): no terminal in the grammar
  matches here even with the row's restriction lifted, so no table was consulted
```

**430 roots for 3,304 bytes.** Every scar is one byte and every one is a
newline: 79 newlines, 79 mends. markdown is not parsed, it is enumerated.

## Why `scry` cannot have it

The bar `scry.zig` sets is not "is the scanner small" - haskell's scanner has a
struct too. It is that joints "reads only the four functions that never touch
it", and the reason is stated in the same header, about haskell's layout:

> a hand that compared columns and nothing else would not fall silent on them -
> it would nest them wrongly, which is the one kind of answer worth less than
> none.

markdown's newline touches the struct on every path. From the pinned
`tree-sitter-markdown` `scanner.c`, deciding a single `\n`:

```c
if (!(s->state & STATE_CLOSE_BLOCK) &&
    (valid_symbols[SOFT_LINE_ENDING] || valid_symbols[PIPE_TABLE_LINE_ENDING])) {
    ...
    while (s->matched < (uint8_t)s->open_blocks.size) {
        if (match(s, lexer, s->open_blocks.items[s->matched])) { s->matched++; ... }
```

It reads `s->state`, `s->matched`, and walks `s->open_blocks`, and mutates
`indentation`, `column`, `simulate` and `state` on the way. `create` mallocs a
`Scanner` with an open-block stack and `serialize` writes real state. So the
same bytes answer differently for having been asked before, which is exactly
what a memoryless hand cannot reproduce.

## Why the table cannot rescue it either

There is a tempting second move, and it is the one worth writing down because it
is *nearly* right. Notice the C above only consults the stack **inside** a
`valid_symbols[...]` test: where the table admits one newline terminal, the
answer is forced by the table and the memory is never reached. tree-sitter must
break the remaining tie with the stack because it is deterministic. joints is
GLR - it could decline to break it and fork, which is not guessing.

So: how often does the table leave it open?

```
joints state upstream/grammars/markdown.json --census \
  _line_ending _soft_line_ending _block_close block_continuation _blank_line_start
```

| terminal | shifts in | sole shift in |
|---|---:|---:|
| `_line_ending` | 201 states | 27 |
| `_soft_line_ending` | 214 states | 6 |
| `_block_close` | 62 states | 26 |
| `block_continuation` | 40 states | 34 |
| `_blank_line_start` | 53 states | 3 |

and the pair that matters:

| pair | both shift | both in the permission set |
|---|---:|---:|
| `_line_ending` / `_soft_line_ending` | **133** | 548 |

133 of the 201 states where `_line_ending` can shift also shift
`_soft_line_ending` - **66%**. The table disambiguates the newline in 27 states
and leaves it open in 133. A forking hand would fork at nearly every one of a
file's newlines, and nothing guarantees the wrong limb dies: both readings are
frequently grammatical, which is how a fork becomes two roots instead of one.

So the fork is not a cheaper stack. It is the same stack, deferred, paid for in
limbs.

## What is left

markdown needs a hand **with memory** - an open-block stack, a matched count, and
the line-start simulate pass - which is a capability class `outside.zig` does not
have and was deliberately built without: every existing `kind` is a pure function
of the bytes at an offset. That is a real piece of work and it is the honest
shape of the corrected list's first item. It is not a `Provision` row.

Two things follow that are worth having now:

- **The board's head is a project, not a row.** 72% of the remaining wall cost
  sits behind one capability nobody has started. Any plan that read the work
  list as "six families, some lexer rows" was wrong about the biggest sixth of
  it.
- **Nothing else on the list is blocked on it.** haskell's `.` (825 B),
  `(?:\))` (385 B) and the rest are independent, and together they are 1,307
  bytes - less than half of markdown's one cell.

## The other half of markdown's report, which is ours and is nearly closed

`blind` and `declined` are two populations with different owners: a blind
terminal is someone else's C, a declined one is our engine refusing a pattern.
Over all thirty grammars:

| | count |
|---|---:|
| `blind` (externals, someone else's C) | 167 over 15 grammars |
| `declined` (our engine) | **1** |

The one is markdown's `entity_reference` - the full HTML entity table, 2,231
alternatives in a single alternation. Bisected against the real list, the engine
takes 1,355 of them and declines at 1,356 (`lobrk`); a synthetic 2,200-way
alternation of `a0000|a0001|...` builds fine, so the ceiling is on **DFA states**
- trie shape - and not on how many alternatives were written. A shared-prefix
trie of ~1,400 English entity names is simply a bigger machine than 2,200
uniformly-shaped ones.

That is one pattern between this corpus and *every terminal in it being
buildable*, and it is ours. `scanner.zig`'s comment claiming the declined
population is "far more common than anyone assumed" and citing php's
eighty-seven is now stale in the good direction - php declines none - and has
been corrected in place.

## Provenance

```
stamp: joints 40a520f18 at zig-out/bin/joints built 2026-08-07T17:31:50Z
       from . 010af3c60 · repo fdda15a2a+29
```

Scanner quoted from `.local/differential/lang/markdown/tree-sitter-markdown/src/scanner.c`
(1,602 lines, pinned). Nothing is linked; it is read.
