# Prediction 1 — elixir, the largest racked source in the corpus

Written before any measurement in this lane. Pin `shape` (`d0e7647e8`, tree
`2d4aad445`, commit `f7ba40004+101`). Scored in `RESULT-1-elixir.md`, unedited
after that.

The witness handed to me is 21 bytes and every leaf agrees:

```elixir
defp f(x) do x end
```

Joints hangs `do_block` inside the inner `call`'s `arguments`; tree-sitter
makes it a sibling of `arguments` under the outer `defp` call.

## P1 — this is a CONFLICT, not a GAP

The reachability closure over `upstream/grammars/elixir.json` will show that
`do_block` **is** derivable in the position tree-sitter puts it — as a member
of the outer `call`'s own body, not only inside `arguments`. Nothing about the
vendored grammar forbids the right tree.

**Falsifier.** If `do_block` is unreachable from the outer `call`'s production
without passing through `arguments`, this is a GAP and no work in `src/press/`
could ever seat it.

## P2 — the decision is a shift the table took where a reduce was available

At the byte where `do` arrives — after `f(x)` is complete on the stack — the
state will hold **both** a shift of `do` (continuing the inner call) and a
reduce of the inner call (handing `do` to the outer one). Joints takes the
shift.

**Falsifier.** `joints state elixir.json <n>` at that point shows a single
action with no rival. That would mean the wrong tree was already decided when
the table was built — a lost production, not a resolved contest — and would be
a strictly worse defect than a mis-resolution.

## P3 — the corpus damage is this construct and not a long tail

Elixir's 17,654 racked bytes are dominated by this one attachment. The widest
runs `rack show elixir` prints will name `arguments` / `do_block` / `call` on
the majority of the bytes in its top runs.

**Falsifier.** Fewer than half the bytes in the widest runs involve a
`do_block` or an `arguments` node. Then elixir is several defects wearing one
number and the witness is not representative of it.
