# merge — one sentence I read as a class, and it was four different things

Once the blind-terminal walls started closing (kotlin, scala), the obvious next
question was which grammar to fix next. I asked every remaining row what
mechanism its wall names, and four of them gave back the same sentence:

```
zig      press? on { in state 715      (1 dropped,  5 misfolded): a merge damaged this terminal's cell elsewhere
julia    press? on _delimiter_str_1 …  (0 dropped, 14 misfolded): a merge damaged this terminal's cell elsewhere
swift    press? on <identifier> …                                 a merge damaged this terminal's cell elsewhere
verilog  press? on ` in state 3438     (1 dropped, 23 misfolded): a merge damaged this terminal's cell elsewhere
```

sql gives the same root cause with the other symptom - `the cell is empty, and a
merged lookahead is a superset of every canonical one it stands for`. Five rows
naming one mechanism, between them 61.5% of all remaining damage.

**They do not share a fix.** That took three passes to establish, and the
correction is the point of this folder.

| file | what |
| --- | --- |
| `RESULT-1-class.md` | the sizing, the specimen, and the two controls that said no |
| `PREDICTION-2-zero.md` | a declared zero should decline like an absent one, with its falsifiers |
| `RESULT-2-zero.md` | refuted on the first measurement, and where both routes bottom out |
| `RESULT-3-floor.md` | first correction - 94.2% of refusals are sealed under any split |
| `RESULT-4-walls.md` | second correction - four of the five walls are not merges, and verilog's is upstream's grammar |
| `PREDICTION-5-chain.md` | the missing list is diagnostics-only, with the falsifiers that would kill it |
| `RESULT-5-chain.md` | the class settled by the instrument: one press defect of five, and the result-location trap on the way |

There is no `PREDICTION-1` on purpose. That lane ran a survey, then tried twice
to reproduce the defect in miniature and failed both times; the falsifiers are in
the result page at the point each one fired.

Prediction 2 did run a treatment and was refuted on the first measurement - it
fixed every `[_]u8{ … }` in zig and broke every `return switch { … };`, costing
2,480 bytes net. Reverted. What it bought was a sharp statement of the open
problem: the splitter cannot partition on which arrival a state was reached by,
and the ladder cannot condition on it.

Result 3 was meant to size that problem before building it, and killed it
instead. `lalr.Floor` has been tallying the answer the whole time: of 2,196
refusals on the corpus, **1,921 are `alone`** - the lookahead was widened through
a *single* arrival, so there is no partition of arrivals to take. Only 128 cells
are `open`. Zig is the one row of the five that is entirely open; julia is
entirely sealed.

So the dominant defect is not state merging. It is LALR merging lookaheads for
one LR(0) item across the LR(1) contexts sharing it, in states one path reaches -
and that lives on the item, not on the arrival.

Result 4 then went to the walls themselves and found the class thinner still.
sql never printed `press?` - it prints `weave`, with 0 frayed cells and a
verdict that says outright it is empty under every split. verilog's `` ` `` is
`` `ifdef `` inside a module port list, which upstream's own grammar does not
admit after a comma - tree-sitter 0.26.11 puts an `ERROR` node on the same byte.
That is 89% of the class by damage and no press can reach it. julia and swift
are undiagnosed. **zig's 1,375 bytes is what is left** - 1.2% of remaining
damage, not 61.5%.

Every figure on this page is read off outliner `beb695b5d` · tree `e973ce73c`
(pin) · oracle `d85e736fa` (30 of 30 live, 30 attributed); each result page
carries its own stamp.

All four `press?` verdicts closed with *"no fold chain was supplied"*, which is
`inquest` saying it cannot rule the press out rather than that the press is
guilty. `walk/nzig` records that chain and is test-only; `quire`, the loop the
CLI runs, walked the same states and discarded them.

Result 5 supplied it, and the class settled where Result 4 predicted without
having to argue: **zig is the only press defect of the five.** verilog and swift
join sql as `weave` - empty under every split - and julia is an `oracle` case
whose fork the table still offers. Every row of the board is byte-identical,
because this records what the loop already walked. The census reads *30 grammars
· 5 whole · 11 lexer · 1 press · 10 weave · 3 oracle (2 unproven)* where four
walls were unattributable before.

## The instrument

Everything here is the shipped CLI - no new script.

```sh
outliner grammar <grammar.json>               # the floor tally: agreed/alone/stuck/open
outliner state <grammar.json> <n>             # one state: its items and its row
outliner state <grammar.json> --holding <item> # which states hold a reading
outliner state <grammar.json> --chain <n>     # how a parse reaches n
outliner parse <grammar.json> <file> --scars  # the wall, and the mechanism verdict
```
