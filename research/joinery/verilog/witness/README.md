# Witnesses for the verilog leaf gap

Two files, fifty-odd bytes each, differing by one pair of parentheses and
disagreeing about whether verilog is parseable. They are checked by

```bash
python3 research/joinery/verilog/leaf.py --check
```

which reads the manifest in `../leaf.floor.json` and asserts each file still
reaches the verdict written beside it.

`lone-select.v` is expected to **refuse** today. That is deliberate and it is
the point: a witness whose expected verdict is a defect fails the moment
somebody repairs the defect, and the failure says so in words rather than going
quietly green. When that happens, flip the row to `accepted` in the same commit
as the repair and the witness becomes its regression guard, which is what a
falsifier is for once it has been falsified.

`lone-select-parenthesised.v` is expected to **accept**, and it is the arm that
makes the first one a claim about one construct rather than about the file.
If it ever refuses, the diagnosis in [`../RESULT-7-leaf.md`](../RESULT-7-leaf.md)
is wrong and the wall is somewhere else entirely.

## What they are witnesses to

A concatenation element that is *exactly* one selected identifier — `{a[3]}`,
`{a[3:0], b}`, `{m.a[3]}`, `{2{a[1:0]}}` — walls at the following token.
Anything that makes the element bigger than the select rescues it: an operator
(`{a[3]+1}`), a unary prefix (`{!a[3]}`), parentheses (`{(a[3])}`), or dropping
the select (`{a}`). Outside braces a select is fine everywhere — `assign c =
a[3];`, `if (a[0])`, `$f(a[3])` all parse.

The two readings that survive to the wall both sit in dead ends that accept
almost nothing: state 701 is `casting_type -> constant_primary .`, one item and
**one terminal of 444** (the cast `'`), and state 707 is
`inc_or_dec_expression -> variable_lvalue .`, which reads on only for `++`,
`--`, `(*`. Neither can do anything with a `;`.

Two cells put it there, and the second is the one that decides.

Statically, state 1701 holds both completed readings —
`primary -> _identifier select1` and `variable_lvalue -> _identifier select1` —
and folds to `primary` on every lookahead **except** `,`, `=` and `}`, where
`variable_lvalue`'s `prec 37 left` beats `primary`'s nothing. Two of those three
are precisely the tokens that follow an element of a concatenation.

Dynamically — and this is what the 56-byte witness actually executes —
`JOINTS_TRACE=quire` never reaches 1701 at all:

```text
split: state 2979 on ] at 729 rank 0 - keeps fold constant_primary #4021,
                                       casts fold primary #4043
refuted: state 701 on ; at 731 rank 0 - keeps nothing, casts nothing
```

At the `]` closing the select, with **rank 0 on both sides**, the parse keeps the
cast operand and casts off the reading a concatenation needs. `grammar.json`
declares `['primary', 'variable_lvalue']` — the author asked for this to be
forked and adjudicated, not decided.

## What they are *not* witnesses to

Not much of `picorv32.v`. Parenthesising its 32 rvalue lone selects moves leaf
coverage against Verible by **+0.4 points**, because a directive defect walls
first there and costs six.

They are witnesses to most of the rest of verilog. On `simpleuart.v` three of
these rewrites take coverage from 86.7% to **100.0%**, and on `spimemio.v` eight
take it from 95.0% to **100.0%** — deficit zero on both. State 701 is the first
wall on both files. See [`../RESULT-7-leaf.md`](../RESULT-7-leaf.md) §5.
