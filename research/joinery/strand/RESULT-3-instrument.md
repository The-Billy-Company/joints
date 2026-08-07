# Result 3 — the inverse query, scored

Against `PREDICTION-2-instrument.md`. **One of three predictions failed**, and it
failed in the direction that would have flattered the repair.

## What shipped

`src/surface/face/joints/state.zig` grew an `Ask` union and dispatches to a new
`src/surface/face/joints/whence.zig` (360 lines; `state.zig` is 392, both under
the 500-line rule). Two verbs, because the population needed two questions:

```sh
joints state <grammar.json> --holding '<item>'   # which states hold this reading?
joints state <grammar.json> --chain <n>          # how does a parse reach n, and
                                                   # where does a fold there go?
```

`--holding` takes a whole item (`variable_lvalue -> _identifier .`) or a bare
body (`-> _identifier .`) and matches **structurally** — left-hand side, full
body, dot position — never as a substring. It reports every matching kernel item
in a state, not the first, and closes with a census line.

`--chain` answers the attribution question directly: what symbols arrive at this
state and from where, what folds here, how far each fold pops, which states it
uncovers, and where the goto lands. A fold whose handle origin is more than one
state is flagged as **frayed** — the LALR merge damage `TESTING.md` names, and a
conflict suspect.

### The backward walk was already in the tree, and I wrote it twice

`--chain` calls `press.retrace`, which has done this since 3 August: a CSR of
inverted edges and an unwind crossing only edges labelled by the body symbol at
each position, exported from `root.zig` with a doc comment naming this exact
question. I wrote a second copy — `Back`, `unwind`, and a module of their own —
carried it through review and a file split, and only found the incumbent while
reading `root.zig` for an unrelated reason. The duplicate is deleted.

The swap is proven inert rather than assumed: `--holding` and `--chain` on
verilog are **byte-identical** across it, with a separate `JOINTS_WORK` per arm
so the two are not reading one folio.

One thing was worth keeping. `retrace`'s two tests check hand-picked positions on
a five-production toy, which is what a walk ignoring the edge symbols would also
pass — on a small automaton "every state within `|rhs|` steps" is usually the
same set as the right answer, so the fixture agrees with the bug. The property is
now asserted directly, in `src/press/retrace.zig` beside the code it constrains:
over every completed item of every state of a grammar pressed through the real
front end, every uncovered origin must read its body forward and land back where
it started, plus an anti-vacuity count, because a walk reaching nothing passes a
for-all. **This is the only press file this lane touched, and the touch is
additive** — one test and one import, no behavior.

Worth naming as a method failure and not just a tidy-up: I searched for the words
my own design used, and the incumbent is filed under different ones.

## P5 — the old `--holding` inflates its count. FAILED.

The old `spelling()` matched with `std.mem.indexOf`, so a completed item is a
strict prefix of the same item with the dot one position earlier. Asking for
`variable_lvalue -> _identifier .` returned 92 states, **and every row printed
was the dot-in-the-middle item** — none of them the item asked for. That part
was measured before the prediction and is not in dispute.

I predicted the true count of states holding the completed item was **under 20**.
It is **92** — the same number.

The two items co-occur: any state whose closure holds
`variable_lvalue -> _identifier . select1` also holds
`variable_lvalue -> _identifier .`, so the substring match was over-matching onto
exactly the set it should have returned. **The bug was real and its consequence
was not.** The old flag printed the wrong rows and the right count, and I
predicted the count would move because I had only checked the rows.

Worth saying plainly: had I scored this by count instead of by row, the repair
would have looked like a no-op and I would have shipped the substring match. The
number a broken instrument produces can be right for a reason that has nothing to
do with it working.

## P6 — a per-state `break` hides items. PASSED, and by a wide margin.

Predicted: at least one verilog state holds more than one item matching a
body-level query. Measured over `--holding '-> _identifier .'`:

> **177 of 234 states hold more than one matching item.** The widest is state
> 710 with **14**.

The old `break` reported 1 of those 14, and which one depended on kernel order.
For a reduce-reduce question — which is the question this population was framed
as — showing one fold per state is showing the absence of the thing being looked
for.

## P7 — the fold chain is the half that attributes. PASSED for verilog, PARTLY for swift.

**Verilog: passed as written.** `--holding` showed the four competing left-hand
sides are all in one state (164), that two of the three walled states hold
exactly one fold each, and that 176 of 234 states have a contest — so the
contest is verilog's normal condition, not this row's signature. That is
precisely "the four left-hand sides are not in contention", in one query.

**Swift: the chain discriminated, but not into the categories I named.**
`--chain 141` reported the arrival on `user_type` from **196 states** and flagged
the fold's handle origin as frayed. That is a one-step read and it sent me
straight to the right question — whether the single lookahead was merge damage.
It was not: `FOLLOW(_navigable_type_expression)` is genuinely `{_dot_custom}`,
one production site. So the chain told me *the table is right here*, which is
worth a lot and is not what P7 promised. It promised `scanner` versus `conflict`,
and the true owner was neither.

**The owner came from an instrument I did not build.** `tool/walls.py warm`
settled 96.3% of the population in two runs. My query narrowed swift from
13,167 B to a 95 B suspect and proved verilog's row was not a reduce-reduce
family; it could not have told me either row was the peel's own scissors,
because nothing about a state says how the parse got its bytes.

So the honest claim for this instrument is smaller than the brief hoped: it is a
very good navigation and falsification tool, it kills wrong hypotheses in one
step, and **it is not an attribution instrument on its own.** Attribution needed
a second parse of the same file under different cutting rules.

## What it may not claim

Unchanged from the prediction, and now load-bearing: a state holding an item is
not proof the parse went through it. The collection is **ours**, so a reading our
press lost is invisible to a query over our own item sets — the same blind spot
that made `gap` false. Every verdict in this dossier names what would overturn
it, and none is an upstream claim.

One more the measurement added: `--holding` counts *kernel items as printed*, and
151 of the 234 states print a duplicate production. Any count off this flag is a
count of items, not of distinct readings, and the two differ by a factor I have
not chased.
