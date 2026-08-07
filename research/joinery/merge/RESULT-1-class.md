# Result 1 — the remaining board is mostly one defect, and I could not reproduce it in miniature

Measured on outliner `beb695b5d` · tree `e973ce73c` (pin) · oracle `d85e736fa`
(30 of 30 live, 30 attributed). Nothing in `src/` changed on this lane, so there
is no treatment arm and no `still` comparison to run - the only files it adds
are this page and the two beside it.

## What I set out to do

Close the next wall. Scala's strings had just landed and the two obvious
follow-ups were the remaining blind terminals - ruby's `heredoc_beginning` and
bash's `_concat`. I read both in their real scanners first, which is now cheap,
and neither is a row. That sent me to look at what else was left, and what else
was left turned out to be mostly the same thing five times.

## The two hands, and why neither is a spelling

Both are on disk under `.local/differential/lang/<grammar>/src/scanner.c`,
because the differential harness builds every grammar with its own C.

**bash `_concat` is zero-width.** The whole common path is a lookahead
assertion that consumes nothing:

```c
if (!(lookahead == 0 || iswspace(lookahead) || lookahead == '>' || … )) {
    lexer->result_symbol = CONCAT;
    …
    } else {
        return true;          // nothing advanced, nothing marked
    }
```

It says "the next byte is not a terminator, so these two words are one word".
The slate must refuse a zero-length match, so no `Provision` can express it. The
`hands` seam can - `outside.step` returns `{symbol, skip, len}` and nothing on
that path checks `len > 0` - but a zero-width emission needs the state to change
underneath it or the parser reads it forever, and that is a real design question
rather than a row.

**ruby `heredoc_beginning` carries a tag.** It matches `<<[-~]?WORD`, which is
spellable, but the point of it is the line after:

```c
scan_heredoc_word(lexer, &heredoc);
if (heredoc.word.size == 0) { … return false; }
array_push(&scanner->open_heredocs, heredoc);
lexer->result_symbol = HEREDOC_START;
```

The tag goes on a stack so `heredoc_end` can match *that* word lines later.
Seating the opener alone opens a heredoc that can never close, which is the
fail-open shape scala's `_multiline_string_end` was deliberately left blind to
avoid. It is a hand, and it is the same hand shape as `fence` with a remembered
word.

Together they are 857 bytes of damage. Both now have a read reason rather than
an argued one.

## How to read any of these scanners

Worth writing down because it cost me a wrong turn. `heredoc_beginning` does not
appear in ruby's `scanner.c` at all - I searched for it and got nothing, and for
a minute thought the oracle was building a different grammar than we parse. It
is not: the four grammars I checked hash byte-identical between
`upstream/grammars/<g>.json` and `.local/differential/lang/<g>/src/grammar.json`.

The enum names in a scanner are the *scanner author's* names. tree-sitter binds
them to the grammar **positionally** - `externals[i]` is enum entry `i`. Aligning
ruby's 30 externals against its enum lines them up exactly, and
`heredoc_beginning` is the scanner's `HEREDOC_START` at index 14. Any scanner
can be read this way; none of them have to agree with the grammar on names.

## The class

> **Corrected twice.** `RESULT-3-floor.md`: I let the shared verdict imply that
> one fix collects the 61.5%, and it does not - 94.2% of every refusal on the
> corpus is sealed under any split. `RESULT-4-walls.md`: worse, four of these
> five walls are not merge defects at all. sql never said `press?`, and
> verilog's `` ` `` - 89% of the class by damage - is upstream's grammar
> refusing a preprocessor directive inside a port list, and tree-sitter puts an
> `ERROR` node on the same byte. What survives is zig's 1,375 bytes.

| row | damage | crooked |
| --- | ---: | ---: |
| verilog | 62,852 | 14,133 |
| swift | 2,377 | 9,563 |
| sql | 2,309 | 179 |
| julia | 1,955 | 158 |
| zig | 1,375 | 10 |
| **class** | **70,868** | **24,043** |
| corpus | 115,281 remaining | 33,653 |
| share | **61.5%** | **71.4%** |

Both totals are the board's own, not arithmetic on remembered rows: `damage by
what it is made of — 115281 bytes over 11 of 30 grammars`, and
`340998 square + 33653 crooked + 10620 soft + 414 unaudited = 411517`. The
crooked column is also reproducible straight from `audit.json` without taking a
board at all.

Every other lane left is either small (bash 413, ruby 444, ocaml 2,182) or its
own project (yaml's 113 externals, markdown's 47).

## The specimen

Zig is the cleanest of the five, so I took it apart. The wall is byte 4101 of
`ascii.zig`:

```zig
pub const whitespace = [_]u8{ ' ', '\t', '\n', '\r', control_code.vt, control_code.ff };
```

Byte 4101 is the `{` of `[_]u8{`, an array initializer. The parse dies at state
715, which is `variable_declaration -> pub _variable_declaration_header =
expression . ;` - by then `[_]u8` has already folded all the way to
`expression`, and `--chain 715` confirms it arrives on `expression` from one
state and nothing folds there. So 715 is where the body was found, not where it
was killed.

The killing is at **state 208**, and the row says it outright:

```
  items:
    type_expression -> primary_type_expression .
    struct_initializer -> primary_type_expression . initializer_list

  row — shifts: this state CONSUMES the token, so a lexer competes here
    (none)

  row — lookahead: …
    {   fold  type_expression -> primary_type_expression   [prec 0 right]

  shift 0, lookahead 68 — 68 terminal(s) accepted of 154
```

The state holds an item that needs `{` to start an `initializer_list`, and the
shift row is **empty**. `{` folds instead. Once `primary_type_expression` folds
to `type_expression` the initializer is unreachable, and the `{` has nowhere to
go for the rest of the declaration. `wall_test.zig` already records this cell as
`read_dropped`.

That is not a grammar limitation. `zig.json` spells
`struct_initializer -> primary_type_expression initializer_list`, and
`[_]u8{ … }` is ordinary zig.

## The two controls, both of which said no

I tried to reproduce it in a twelve-rule grammar. Both attempts failed, and
failing is the point of building them.

**Control 1 - is the shape enough?** A grammar with a var-decl (`const x = expr ;`)
and a function decl whose return type is a `type_expr` followed by a `{` body,
so that `{` is legitimately in FOLLOW(`type_expr`). Against a control with the
function decl removed. Input `const x = y{};` in both.

Both accepted, identically. And `--holding 'type_expr -> prim .'` explains why:
two states, not one. In the return-type position a struct init was not
reachable, so the cores differed and nothing merged. My grammar did not have the
shape I thought it had.

**Control 2 - now with cores that really coincide.** I made the return type a
full `expr` so both contexts produce the same item set, and varied only whether
the body starts with `{` (`{ }`) or not (`begin end`) - so the two arms differ
only in whether `{` enters the merged lookahead.

Both accepted again. And this time the states are worth quoting, because they
overturned my model:

```
=== merged state 15 ===          === merged state 22 ===
  struct_init -> prim . init_list   struct_init -> prim . init_list
  type_expr -> prim .               type_expr -> prim .

  shifts:                           shifts:
    { read on [residual              { read on
      shift_reduce, over
      fold type_expr -> prim]       lookahead:
                                      ; fold type_expr -> prim
```

Byte-identical item sets, kept as **separate states** with different rows. So
outliner does not merge coinciding LR(0) cores the way a textbook LALR does -
and where it does hit the conflict, it keeps the *shift* and records a
`residual`, which is the opposite of what zig's 208 does.

I had been reading "merge" as LALR state merging for two hypotheses running.
Both controls said no, and they were right to.

## What the mechanism actually is

It is in the code, and it is about lookaheads rather than states -
`bench.zig:161`:

> A rule's own tail only outranks its fold where the fold had no business in
> this column: `frays` is true exactly when the lookahead admits the terminal
> under the union over arrivals and not under the intersection, so the
> permission is the merge's invention rather than the grammar's.

That is the DeRemer-Pennello union. States stay apart; the lookahead sets do
not, and `frays` is the existing detector for exactly the case where the union
granted a permission the intersection would not have. Zig's 208 on `{` is a
frayed cell whose read was dropped.

So there is already a guard meant for this - `survey.continues = survey.continues
and frayed and b.strands(state, t)`, which walks the fold chain to ask whether
folding actually loses the rule's tail. At zig's 208 it did not save the read.
**Why not is the open question**, and it is the next lane's.

## What I trust least

The class sizing rests on the mechanism verdicts agreeing, and every one of them
prints `press?` with a question mark. That is not decoration: `inquest.zig` sets
`out.proven = false` on this branch and says so - "the damage is real somewhere
and nothing places this wall downstream of it". Five rows naming one suspicion
is a good reason to look there first; it is not five proofs. Zig is the only one
of the five I traced to a specific cell, and even there the link from 208 to the
wall at 715 is an argument about reachability rather than a recorded chain.

The 61.5% figure is also flattered by verilog being 89% of the class by damage.
If verilog turns out to be its own thing, the remaining four are 8,016 bytes and
this page is a much smaller claim.
