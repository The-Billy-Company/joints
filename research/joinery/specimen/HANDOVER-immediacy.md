# Handover — Julia's `_immediate_*` family, with the three specimens that prove it

For whoever holds zero-width work in `src/kernel/lex/outside.zig` / `step`.
Found by the specimen tier on 2026-08-05, not fixed here, because the hand is
yours and this lane's job was to build the thing that can see it.

## What the brief said, and what is actually true

Julia was handed to me as "seated today and stateless — a regression floor
rather than an unblock". Half of that is right and the half that is wrong costs
two whole constructs.

**The interiors really are seated and really do work.** `julia/command.jl`
passes 6/6, including `$n` interpolation inside a backtick literal.
`julia/triple-quote.jl` — `s = """x "q" y"""` — parses to a single root with the
literal at exactly [4, 17), so the triple-quote close is correct and greedy
where it needs to be. Those two are green regression floors as promised.

**What is blind is the immediacy family**, five zero-width markers:

```
_immediate_paren  _immediate_bracket  _immediate_brace
_immediate_string_start  _immediate_command_start
```

Each says *this bracket is glued to the token before it*. `joints lex` names
all five; the gate reports julia at `declared 16, seated 11`.

## What it costs, in constructs the corpus cannot see

| specimen | source | today |
|---|---|---|
| `interpolation.jl` | `s = "a $(n + 1) b"` | 8 roots, 3 mends, **no `string_literal` node at all** |
| `raw-string.jl` | `s = raw"a\b"` | 3 roots, 2 mends, **no `prefixed_string_literal`** |
| `nested-interpolation.jl` | `s = "$("$n")"` | builds the **inner** literal at [13, 17) and never the outer |

All three wall in the same place:

```
unexpected ( at 12 in state 290, 5 roots, mended 2 over 2B
julia: lexer on ( in state 290 [no stand-in for _immediate_paren]
```

So the **parenthesised** interpolation form does not parse, and neither does any
prefixed literal — `raw"..."`, `r"..."`, `b"..."`, the whole family, since
`prefixed_string_literal` opens on `_immediate_string_start`.

The nested case is worth a second look, because it reads like a stateless close
and is not one. The hand never gets to start: the `$(` at byte 11 walls, and
what survives is the inner string the recovery happened to find. A reader
glancing at `spans string_literal 10 19 - got [13, 17)` would diagnose "the
outer string closed at the inner opener", which is the classic stateless
failure and the wrong answer here. `joints parse`'s failure state being a
location and not a diagnosis is exactly the trap; the stderr line naming
`_immediate_paren` is what settles it.

## Why nothing caught this before

`set.jl`, the 27,360-byte Julia corpus file, contains **zero** `$(` and **zero**
`raw"`. Four bare `$ident` interpolations, which are the one interpolation form
that works. Every byte number this repository takes for Julia is taken over a
file that leans on none of it.

## Reproducing

```bash
python3 tool/specimen.py run --grammar julia
python3 tool/specimen.py show research/joinery/specimen/julia/interpolation.jl
python3 tool/specimen.py coverage -v --grammar julia
```

The three specimens are already written and already red. If you seat the
family, they go green with no edit to the tier — and if a later change unseats
it again, they go red without anyone having to remember why. That is the whole
point of handing this over as fixtures rather than as a paragraph.

## One thing not to trust while working on this

Do **not** ablate by renaming an external to test whether it matters.
`provision` in `outside.zig` requires a troupe's full cast, so renaming any one
member unseats every other member with it — a one-character case change to one
blind Kotlin external took its blind count from 8 to 10. A rename ablation
reports every part of a seated troupe as load-bearing whether it is or not. It
is only honest for the inverse job: deliberately breaking a hand to check
something notices, which is what `specimen.py verify`'s fifth assertion does.
