# Result 2 — refuted, and both routes out of zig's 208 bottom out on the same missing fact

Prediction 2 said a fold ranked at a declared zero should decline in a frayed
cell the way an unranked one already does. **Falsifier 2 fired on the first
measurement.** The change is reverted; `src/press/bench.zig` is byte-identical to
HEAD and `zig build check` is green.

Treatment arm `zero-frayed` (joints tree `ab968b8352f7`) against control
`scala-string` — joints `beb695b5d` · tree `e973ce73c` · oracle `d85e736fa`
(30 of 30 live).

## What happened

The change was the one condition Prediction 2 named, `.none` widened to "`.none`
or a level equal to zero". It did exactly what it was supposed to do at the cell
it was written for, and the tree proves it - `[_]u8{ … }` came out as
`anonymous_struct_initializer (initializer_list …)`, built for the first time.

And zig got worse.

| | control | `zero-frayed` |
| --- | ---: | ---: |
| zig built | 14,750 | 12,270 |
| zig damage | 1,375 | **3,855** |
| roots | 55 | 247 |
| wall | `{` at 4101 | `;` at **2852** |

Every other row on the board was byte-identical, so the change is contained -
and containment is not a defence. Opening the `{` at 4101 closed a worse wall
2,480 bytes earlier.

Byte 2852 is the semicolon in

```zig
return switch (c) {
    'A'...'Z', 'a'...'z' => true,
    else => false,
};
```

so the version that fixed every `[_]u8{ … }` broke every `return switch { … };`.
Declining the comparison wherever the fold merely ranks zero declines it in
plenty of cells where the fold was right.

## The narrowing that should have saved it, and why it did not

The codebase already owns the discriminator. `strands(state, t)` asks whether
folding "would leave the terminal with nowhere to go", and `decide` already uses
it to narrow `continues` to frayed cells where folding really loses the tail.
That is precisely the difference between the two cells above: at 208 the `{`
becomes unreachable, and at the switch it does not.

So I moved the rule there - `.fold => keep_read = loses_tail and zeroish(f.prec)` -
and zig went straight back to walling at 4101. `strands(208, '{')` is **false**.

It is false for a reason worth writing down, because it is the same reason twice:

```zig
for (b.walked.items[room..]) |q| {
    if (b.x.c.goto(q, t) != null) return false;
```

`strands` pops the handle, takes the goto, and asks whether the landing state has
an edge on `t` - over **every** arrival. And one of zig's arrivals does have a
`{` edge after a `type_expression`: a function signature's return type is
followed by its block. That is the *same* arrival the fray is recording. So in a
frayed cell `strands` inherits exactly the confusion the fray exists to name, and
its own docstring concedes the shape of it: over-answering "only says a reading
exists somewhere above".

A guard built out of the union cannot adjudicate a defect caused by the union.

## Where this actually lands

The two independent routes out of zig's 208 converge on one missing fact.

**The splitter's route.** `press.zig` already unfolds frayed cells - build, ask
which arrivals disagree, rebuild keeping them apart, up to four rounds. On zig it
runs two, grows 1,720 → 1,830 states, and reports the same refusing kernel both
times (`refusing 208 on terminal 38` then `refusing 276 on terminal 38`, kernel
`5f5124b26fda5199` both). Its own comment says why: *"arrivals that share a
predecessor kernel share a lane, so when the difference lives in the predecessor
the partition cannot express it."*

**The ladder's route.** Above.

Both need the same thing: **which arrival we are on**, when the disagreement
lives one level further back than the state records. The splitter cannot
partition on it and the ladder cannot condition on it.

And walking backwards was already tried. `press.zig`: *"separate the state one
arrival apiece, and failing that its predecessors, walking the disagreement
backwards a goto per round. On all eleven grammars it bought two frayed cells and
cost three to five times the press: bash reached 24,572 states against 7,753."*

So the open problem is sharper than "fix the merge". It is: **carry
predecessor-distinguishing information for the few kernels that need it, without
paying for it on the automaton as a whole.** That is a real design question.

> **Corrected by `RESULT-3-floor.md`.** I closed this sentence with "and it is
> the one standing between this parser and 61.5% of its remaining damage". It is
> not. Sizing the prize before building it put the ceiling at 128 cells corpus-
> wide - 5.8% of refusals - because 87.5% of them were invented through a single
> arrival and have no arrival partition to take at any price.

## What I trust least

The 2,480-byte loss is one grammar on one file, and I read one new wall out of
it. I did not check whether the other 29 rows would have moved on a *different*
corpus file - the board says they were byte-identical here, which is weaker than
saying the change is inert for them.

I also never proved that forking 208 would produce the *right* tree, only that
it would produce one. The oracle was never asked, because the arm lost bytes
before it was worth minting verdicts for. If somebody solves the predecessor
problem, that is still an open question rather than a foregone win.

Finally, `zeroish` treating `prec.right(0)` as "not really a rank" is an
interpretation of the author's intent, not a fact about the grammar. It survives
here only because the change was reverted before it could be wrong in public.
