# Result 1 — elixir: the fold that was never there

Scores `PREDICTION-1-elixir.md`. Pin `tenon` (`4d7074db7`, tree `fa7fcaee5`,
repo `f7ba40004+106`). Two of three predictions hold; the one that fails is the
finding.

## The witness

```elixir
defp f(x) do x end
```

21 bytes, seated as `research/joinery/specimen/elixir/do-block-on-inner-call.ex`.
`joints parse` says `accepted, 1 root`. Every one of the seven tokens agrees
with tree-sitter 0.26.11, name and extent. The disagreement is one edge:

```
  joints                          tree-sitter
  call [0, 20)                      call [0, 20)
    identifier  "defp"                identifier  "defp"
    arguments [5, 20)   <- 20         arguments [5, 9)    <- 9
      call [5, 20)      <- 20           call [5, 9)       <- 9
        identifier "f"                    identifier "f"
        arguments "(x)"                   arguments "(x)"
        do_block [10, 20)             do_block [10, 20)   <- sibling
```

`defp f(x) do ... end` desugars to `defp(f(x), do: ...)`. The block is an
argument of `defp`. Joints says it belongs to the function being defined.

## Three controls, all green

| Control | Why it matters |
|---|---|
| `defp f do x end` | No inner call, so nothing to steal the block. Identical trees. |
| `defp(f(x), do: x)` | The desugared form, inner call still present. Identical trees. |
| `def f(x), do: x` | The one-line form. Identical trees. |

The first is the load-bearing one. Joints attaches a `do_block` to a
definition correctly whenever it is the only candidate. The failure needs two
candidates, which pins the defect to a decision rather than to the construct.

## P1 — CONFLICT, not GAP. **HOLDS.**

`do_block` is reachable in tree-sitter's position without passing through
`arguments`: elixir.json's `call` is
`seq(target, optional(_call_arguments_with_parentheses), optional(do_block))`,
so the outer call may carry both an argument list and a block as siblings. The
vendored grammar can express the right tree. Nothing here is unseatable.

## P2 — a shift taken where a reduce was available. **FAILS.**

This is the prediction I most wanted to be right about, and it is wrong in the
direction its own falsifier named as worse:

> **Falsifier.** `joints state elixir.json <n>` at that point shows a single
> action with no rival. That would mean the wrong tree was already decided when
> the table was built — a lost production, not a resolved contest — and would
> be a strictly worse defect than a mis-resolution.

The state is 272. The cell is:

```
    do                           read on
```

That is the whole row. No bracket, no `declared`, no `residual`, no rival of
any class. Compare the two grammars whose defects *are* contests, in the same
format from the same binary:

```
go     state 1   .     read on   [declared shift_reduce, over fold  _expression -> identifier]
python state 6   (     read on   [declared shift_reduce, over fold  primary_expression -> print   [prec -3 none]]
elixir state 272 do    read on
```

go and python print what they beat. Elixir beats nothing, because by the time
the table exists there is nothing there to beat. The fold that would hand `do`
to the outer call — reducing the inner `call` while `do` is the lookahead — is
absent from state 272's row, so LALR merging dropped `do` from that reduction's
lookahead set. The press never chose. It was never asked.

That distinction is load-bearing for whoever seats the fix. A mis-resolution is
repaired in the ladder — the four rungs in `src/press/settle.zig`. A missing
lookahead is not reachable from the ladder at all: `Forks.of` builds the fork
table exclusively from `tables.conflicts`, and this cell is not in
`tables.conflicts`, so no amount of re-ranking reaches it. It is the classic
dangling-else, and it needs either the lookahead recovered or the ambiguity
declared so that a fork exists to resolve.

## P3 — the corpus damage is this construct. **HOLDS**, emphatically.

`rack show elixir`, nine widest runs:

```
  [13337, 15152)  1815  racked  arguments  vs  do_block   'do\n    conn = prepare.(con'
  [11229, 12766)  1537  racked  arguments  vs  do_block   'do\n    quote unquote: fals'
  [23192, 23945)   753  racked  arguments  vs  do_block   'do\n    {pipe_name, acc_pip'
  [10380, 10979)   599  racked  arguments  vs  do_block   'do\n    quote do\n      opts'
  [29414, 29969)   555  racked  arguments  vs  do_block   'do\n      raise ArgumentErr'
  [29970, 30452)   482  racked  arguments  vs  do_block   'do\n          try do\n      '
  [28354, 28761)   407  racked  arguments  vs  do_block   'do\n    quote do\n      @pho'
  [24444, 24840)   396  racked  arguments  vs  do_block   'do\n    %{\n      path: path'
  [21247, 21624)   377  racked  arguments  vs  do_block   'do\n    {pipe_name, ...'
```

Every one. `arguments` where the oracle says `do_block`, and every run opens on
the literal bytes `do`. 6,921 bytes in nine runs, out of 17,734 crooked, all one
construct. Nesting it inside a module reproduces it unchanged:

```
defmodule M do
  defp f(x) do x end
end
```

→ `40 built · 27 square · 1 askew · 12 racked`, the 8 racked bytes being
`do x end` under `arguments` vs `do_block`.

## What this costs, with denominators

elixir is 44,530 built of 526,798 corpus bytes. `rack` charges it 17,734
crooked (39.9% of judged, 4.6% of corpus), 17,660 of that hard by `rack soft`'s
test. `extent.py` (this lane) re-sorts the same charge: 1,873 bytes are a right
parent measured wrong, 15,791 are a parent genuinely in dispute — the largest
disputed figure of any grammar with a working oracle except php.

Every byte of it is one shift on one terminal in one state.
