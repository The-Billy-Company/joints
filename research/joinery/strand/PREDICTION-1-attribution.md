# Prediction 1 — who owns the 22,179 stranded bytes

Written before any state was read, against the population as
`owners.py --stranded` reports it on `joints 0446f4bc6`
(`.local/strand/joints`, pinned out of `zig-out/` before measuring). Scored in
`RESULT-1-attribution.md`, failures included.

The population is 30 walls / 22,179 B, and it concentrates onto three fold
bodies carrying 19,647 B (88.6%):

| body | folded as | walls | bytes | share |
|---|---|---:|---:|---:|
| swift `_top_level_statement _semi` | `source_file` | 1 | 9,160 | 41.3% |
| verilog `_identifier` | 4 competing lhs | 8 | 6,591 | 29.7% |
| swift `_top_level_statement source_file_repeat1 _semi` | `source_file` | 1 | 3,896 | 17.6% |

The two swift rows are the same separator spelled with and without its repeat,
so by construct it is **two** problems, not three: swift `}` at 13,056 B
(58.9%) and verilog `_identifier` at 6,591 B (29.7%).

## P1 — swift is `scanner`, and the external is a semicolon

**Claim.** Both swift walls (`}` in 681, `}` in 1166, 13,056 B) attribute to
**scanner**: an external we do not seat.

**Reasoning.** Swift declares 33 externals, and two of them are `_implicit_semi`
and `_explicit_semi` — the statement separator that appears in the fold body of
both walls. Swift inserts a statement terminator at a newline the way JavaScript
inserts a semicolon, and this tree is already known to be blind to that shape in
JavaScript (`_automatic_semicolon`, `TESTING.md`). A `}` refused in a state that
has *just folded a whole top-level statement* reads as a parse sitting at file
level when it should be inside a brace body.

**Kill condition.** If the fold chain lands on a state where a non-external
reading was available and our table dropped it, this is `conflict` and P1 is
wrong. Also wrong if the chain shows `_semi` is being produced fine and the
refusal is about the brace itself.

## P2 — the verilog eight are NOT one reduce-reduce family

**Claim.** The brief describes the verilog row as "eight verilog walls folding a
bare `_identifier` under four competing left-hand sides: one reduce-reduce
family, not eight defects". **I predict that is wrong**, and that the row is
dominated by something else entirely.

**Reasoning.** The eight walls are only **three states** (562, 513, 164), and
**6,477 of the 6,591 bytes (98.3%) are one terminal, `macro_text`** — verilog's
preprocessor macro body. The remaining five walls are 114 B of `begin`, `end`,
`endcase`, `endtask`, `*)`. A reduce-reduce family among four left-hand sides
over a bare `_identifier` would show up as a contested cell; a `macro_text`
refusal after an `_identifier` fold reads as the **directive path** — `` `define
FOO … `` — where the macro body is a lexical construct, not a competition
between `class_type` and `data_type`.

So I predict the `_identifier` fold body is **a coincidence of which states
happen to hold a completed `_identifier` item**, not the mechanism. Concretely:
≥95% of the row's bytes attribute to the directive/`macro_text` path, and the
four competing left-hand sides play no part in the refusal.

**Kill condition.** If `--holding` shows the four left-hand sides completing in
the *same* state with a genuine reduce/reduce contest whose lookahead includes
`macro_text`, then it is one r/r family, the brief is right and P2 is wrong.

## P3 — a third of the population moves off `stranded`

**Claim.** With a working inverse query and a fold chain, **at least 2 of the 30
walls and at least 60% of the 22,179 B** get a named owner (`conflict`,
`scanner`, or a demonstrated genuine unownability) rather than staying
`stranded`.

**Reasoning.** 88.6% of the bytes are three fold bodies; naming two of them
names most of the population. 60% is chosen so that naming swift alone (58.9%)
is *not* enough to pass — the bar requires verilog too.

**Kill condition.** Under 60% of bytes named, or a chain that names no owner at
all — in which case the inverse query is a navigation aid and not an
attribution instrument, and I have to say so.

## P4 — the verilog family lands on someone else's defect

**Claim.** At least one of the three fold bodies attributes to the known
`gather`-takes-the-wrong-limb defect in `src/kernel/quire/`
(`research/joinery/verilog/HANDOVER-wrong-limb.md`) and gets handed over rather
than fixed here.

**Reasoning.** Verilog state 1762 already has a real `shift_reduce` on `=` where
`gather` picks the declaration limb. A population defined as "a fold could have
left this state" is exactly the population a wrong-limb pick produces.

**Kill condition.** All three bodies attribute to the press or to the scanner
with no runtime involvement.
