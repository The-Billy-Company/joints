# Result 2 — verilog's `_identifier` eight is not one reduce-reduce defect

The brief: *"eight verilog walls folding a bare `_identifier` under four
competing left-hand sides: one reduce-reduce family, not eight defects."*

Measured, it is **neither eight defects nor one family**. It is one lexer's
appetite, and all 6,591 bytes of it are the cold peel's cut.

## The eight walls are three states, and two of the three hold no contest

`joints state <g> --holding '-> _identifier .'` — the inverse query this lane
built — over `verilog.json`:

```
234 of 9763 state(s) hold a kernel item matching `-> _identifier .` (1460 items)
```

Of those 234, **176 have a genuine reduce/reduce contest** (more than one
distinct left-hand side), and the widest is eleven-way in 60 states. So a bare
`_identifier` folding under competing left-hand sides is not this row's
signature. It is verilog's normal condition, in three quarters of the states
that can fold one at all.

The eight walls sit in three states, and the contest is in only one of them:

| state | folds it holds | walls | bytes |
|---|---|---:|---:|
| 562 | `net_decl_assignment -> _identifier .` — **alone** | 5 | 2,596 |
| 513 | `variable_decl_assignment -> _identifier .` — **alone** | 1 | 2,262 |
| 164 | `data_type` ×2, `class_type`, `variable_decl_assignment` | 2 | 1,733 |

**4,858 B of the 6,591 (73.7%) are in states holding exactly one fold**, where
there is no competition to lose. The "four competing left-hand sides" are real
and are all in state 164, which carries 26.3% — and 164's four are three, since
`data_type -> _identifier .` is printed twice. (151 of the 234 states print a
duplicate production. That is worth someone's attention and it is not mine.)

**A reduce-reduce defect requires two folds in one state. Two of these three
states have one fold each.** The family does not exist.

## What the row actually is: one terminal, and the table is right

**6,477 of the 6,591 bytes (98.3%) are a single terminal, `macro_text`**,
refused in all three states. The remaining 114 B are `begin`, `end`, `endcase`,
`endtask`, `*)`.

`macro_text` is verilog's preprocessor macro body:

```json
{"type": "PATTERN", "value": "(\\\\(.|\\r?\\n)|[^\\\\\\n])*"}
```

Any run of non-backslash, non-newline bytes — **including the empty string**. It
matches `= 0;`, `[3:0]`, a whole line of anything. Under maximal munch it beats
every real token it overlaps.

And it belongs almost nowhere. `joints state <g> --census macro_text`:

> shift in **1 state(s)**, lookahead in 6

One state out of 9,763. Meanwhile state 562, after `wire foo`, accepts four
terminals of 444 and they are exactly the four a net declaration allows:

```
  row — shifts:      =    [
  row — lookahead:   ,    ;      fold  net_decl_assignment -> _identifier
```

**The table is correct.** `wire foo` followed by a macro body is not verilog.
Verilog declares **zero externals**, so there is no unrun C scanner to blame
either. A token legal in 1 of 9,763 states arriving in a state that admits 4 of
444 is a lexer producing something the parse never asked for.

## But the bytes are the peel's, not the lexer's

The warm peel — which never restarts, so it always has the real prefix — reaches
**none** of these walls in 400 rounds:

| wall | bytes | warm peel reaches it? |
|---|---:|---|
| `macro_text` in 562 | 2,483 | no — cold-only |
| `macro_text` in 513 | 2,262 | no — cold-only |
| `macro_text` in 164 | 1,732 | no — cold-only |
| `(?:[^\\"\n]+)` in 3183 | 1,638 | no — cold-only |
| `; in state 701` | 496 | **yes** |
| `: in state 701` | 20 | **yes** |
| the other ten | 164 | no — cold-only |

**8,278 B of verilog's 8,794 stranded bytes (94.1%) need the state-0 restart to
exist.** The mechanism is the same as swift's: the peel cuts mid-construct and
re-parses the tail cold, and a fragment starting inside a declaration lets
`macro_text` swallow the line.

So `macro_text` is a real lexer weakness — a pattern matching nearly everything,
offered where the state admits four terminals — but **it is not costing the
corpus 6,477 bytes.** It costs that much only on fragments the peel manufactures.
Fixing it would move ~0 bytes of real damage and should be sized accordingly.

Only **516 B** of verilog's stranded population survives a peel that keeps its
prefix, and it is `; in state 701` plus `: in state 701`. State 701 is already
one of the verilog lane's four hand verdicts, hand-attributed **`conflict`** from
a one-line witness (`x = {a[3], b};`) and used as `owners.py --control`. Nothing
new is owed there.

## Nothing here belongs to `src/kernel/quire/`

The brief warned that an attribution landing on the `gather`-takes-the-wrong-limb
defect should be handed over rather than raced. It does not land there. None of
the sixteen verilog stranded walls involves state 1762 or the `=` fork, and the
causal path runs through `tool/walls.py`'s cold peel, not the runtime tree.
No handover.

## The fix, if someone wants the lexer hardened anyway

Gate the lexer's candidate set on the parse state's row. `macro_text` is the
extreme case that makes the argument: a pattern matching almost any line, legal
as a shift in 1 of 9,763 states. A state-directed lexer cannot offer it in 562,
and the same gate retires `(?:[^\\"\n]+)` in 3183 for the same reason.

Do it for correctness on real fragments and on `--no-index`-style partial input,
not for the byte count — **the byte count is the peel's**. Anyone sizing this
work off the 6,591 on the board is sizing it off an artifact, which is what this
lane was built to stop.
