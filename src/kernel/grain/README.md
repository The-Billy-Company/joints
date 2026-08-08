# grain - what the bytes are shaped like, before any of them is a token

Every layout-sensitive mechanism in `../lex/` starts by asking the same question
of the same bytes: *where does this line begin, how far in does its content sit,
and is there a comment in the way?* Each of them used to answer it with its own
`while (i < bytes.len) : (i += 1)`, once per line, forever. This area answers it
once, in blocks, and hands the answer over.

Nothing here knows what a token is, what a grammar is, or what the scanner is
doing. It reads bytes and reports their shape. That is why it is the lowest zone
in the charter and why the one arrow between it and `lex` points down the page.

| File | What it is |
|---|---|
| `sweep.zig` | The block primitives. Load 64 bytes into a `@Vector`, compare against a class, get a `u64` back: `find` (next byte in a set), `past` (end of a run), `seek` (next two-byte pair, carried across the block seam). Each peels a handful of bytes scalar first, because a vector wins on runs and loses on decisions. |
| `ruling.zig` | The index. One record per line - start, where the leading run stops, what column that lands on, which of four shapes the line is - plus `splice`, which re-derives only the lines an edit touched, and a one-line memo in front of the lookup. |
| `measure.zig` | The measurement `lead`, which walks from an offset to the next line that means something. One body, optionally accelerated by a ruling. Plus `through`, for a bounded comment. |
| `grain.zig` | The door. |

## The invariant, which is the whole design

**A line's record is a pure function of that line's own bytes.** No carried
block comment, no open string, no bracket depth. Two things fall out of that and
both are load-bearing:

- **`splice` is local.** An edit inside a line can only change the records of
  the lines it touched; every other record survives and the tail moves by the
  edit's delta. That is what makes this survivable in an editor rather than
  something rebuilt on every keystroke.
- **The fast path cannot drift from the slow one.** `measure.lead` has no
  cross-line memory either - it enters a comment only when it *sees* the opener
  while walking - so "this line is spaces then code at column 4" is exactly the
  conclusion the byte walk reaches. There is one function body, and the ruling
  only ever lets it skip ahead to a conclusion it would have reached anyway.
  `grain_test.zig` holds that to every offset of every corpus file under both
  comment spellings, which is the only standard worth having.

The price is the fourth shape, `.rough`: any line the record cannot state
without breaking the invariant is marked and walked a byte at a time. A carriage
return or form feed inside the leading run, a backslash continuation, a bounded
comment opening the line, and the last line of a file whose whitespace runs into
the end of input. On the corpus that is one or two lines in a hundred.

## What is deliberately absent

The lane brief asked for line boundaries, string spans, comment spans, and
bracket nesting. Two of those four are here and two are not, and the reason is
the same invariant:

- **Comment spans and string spans are not spliceable.** A block comment or a
  triple-quoted string crosses lines, so a table of them is a global fact:
  typing `/*` at the top of a file re-derives every span below it, which is the
  cost the index exists to avoid. Worse, the table would be *wrong* rather than
  slow if it were stale. So `measure.through` walks a bounded comment with
  `sweep.find` instead - vectorized, no table, correct by construction. The
  string case is `../lex/hand/fence.zig`'s and it already carries the stack that
  makes it decidable; a span table below it would be a second, weaker authority.
- **Bracket nesting is not a fact about bytes.** A `(` inside a string is not a
  bracket, and knowing which ones are requires the string spans above. simdjson
  can do this in one pass because JSON has one string spelling and no comments;
  a generator that has to serve Python, Ruby, shell, and JavaScript at once does
  not have that luxury. The depth that matters is already `fence.Spans`, which
  is built by a scanner that knows the dialect.

Both of those are findings rather than omissions, and both would be worth
revisiting if the bracket question ever gets asked per-dialect rather than
per-package.

## Who this is for, which the bench decided rather than the design

`Ruling.at` is a bisection behind a memo of where the last lookup landed, so
the common case is a compare. That makes the index worth having to a reader
that sweeps forward - which is what a parse is - and worth nothing to a reader
that jumps, where every ask misses the memo and pays a full bisection on top of
a walk it barely shortened. The bench measures both orders side by side and the
gap is an order of magnitude, so this is a property of the area rather than a
number that might drift: **grain is a scanner's index.** The one installer is
`../weave/weave.zig`, and a parse sweeps.

The same board says the pre-pass does not repay itself inside a single cold
parse of a single file. It repays across an editing session, because `splice`
is ~100x cheaper than a rebuild on a real file. An index built once and thrown
away would be a loss; an index built once and kept is not.

## Portability

There is no intrinsic and no target branch anywhere in this area.
`@Vector(64, u8)` compiles on every backend Zig has; the block is 64 rather than
the machine's native width because **the mask is the product** - a `u64` is one
word to shift, to `@ctz`, and to hand back, where four `u16`s are four of
everything and a seam between each pair. Zig legalizes the wide compare into the
register-sized ones the core actually has. On aarch64 that is four NEON
compares, on x86-64 with AVX2 it is two, and on a target with no vector unit at
all it is a scalar loop that is still correct. That is the entire fallback
story: one implementation, legalized per target, byte-identical answers.

## Measuring it

`zig build bench-grain` times both the vectorized walk and the ruling against
the byte walk they replace, over the real corpus and over generated shapes
chosen to make each arm lose. Read `../../../bench/rungs/grain/README.md` before
quoting a number from it - the shapes where it loses are the interesting rows,
and there are three of them.
