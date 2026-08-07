`stranded` is 30 walls and 22,179 bytes - states holding a completed item,
where a fold could have left the parse there and the wall's own state cannot
say whose defect it is. It is the second-largest unresolved population on the
board and nobody had described its shape.

`owners.py --stranded` groups it two ways, and the two disagree. By whole
completed item it is 22 distinct items with 14 held by exactly one wall, which
reads as *does not collapse, budget a project*. By the **body** the fold is
over - the item minus its left-hand side - the top two carry 71% of the bytes
and the top three carry 88%, over nine walls. The item grouping is the one that
misleads, and I wrote the wrong conclusion off it before regrouping.

What the byte-weighted view finds is one family that was invisible as four
rows: **eight verilog walls, 6,591 bytes, sitting in states that can fold a
bare `_identifier` under four competing left-hand sides** - `net_decl_assignment`,
`data_type`, `class_type`, `variable_decl_assignment`. That is a reduce-reduce
family wearing eight faces, not eight defects. Swift's 13,056 bytes are two
walls folding the same top-level statement separator spelled with and without
its repeat.

**What the population needs, and does not have.** An item-indexed inverse query
- which states can reach this fold - and then a fold chain from the wall back
to the state that committed. The brief for this work named
`joints state <grammar.json> --holding <item>` as the tool. That flag has
never existed in this tree: `state` takes a state number or `--census
<terminal>`, `--census` is indexed by terminal and cannot ask this question,
and `git log -S'--holding' -- src/` returns no commit. `inquest` says the same
thing from the other side on every `press?` line it prints: "no fold chain was
supplied to say whether this wall is downstream of it". Until one of those
exists the population stays exactly where it is, and 71% of it is two questions
rather than thirty.
