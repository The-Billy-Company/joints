# The keyword that became a name

`parameter-port-list.v` is 193 bytes and it is the whole of verilog
`[89368,89412)`, the adjudicated row that `collate.py adjudicated` has been
exiting 1 on. Byte 128 is the word `parameter` opening the second declaration of
a module's parameter port list. The parse builds `parameter_declaration
[128,164)` over it or it builds `simple_identifier [128,137)`, and which one it
builds is the row.

```bash
joints parse upstream/grammars/verilog.json --ranges \
  research/joinery/parameter/parameter-port-list.v | grep '\[128,'
```

Read on pin `heft` that prints `parameter_declaration [128, 164)`. Read on `bh`,
whose `gather.zig` is byte-identical to `heft`'s and whose `bench.zig` is not, it
prints `simple_identifier [128, 137)`. Every pin since is the second answer.

The module above it exists to put an `ifdef` in a port list, which is what gets
the parse into the wrong context in the first place; without it the port list
parses and there is nothing to witness. That is why the file is 193 bytes and
not 60.

## Why the keyword lexes as a name here and not nine kilobytes away

`[80096,80105)` is the same nine-byte word in the same grammar and has never
drifted. The difference is not the word and not the lexer's tie-break. It is
which reading is standing when the scanner is asked.

State 324 holds `list_of_param_assignments -> param_assignment .` and the same
rule with its dot before its own synthesized repeat. On a comma the table folds,
because the author wrapped the rule in `prec.left(0)`; `Ladder.sided` sees a
side declared over the whole rule beating a rank nobody wrote, spares the read,
and `forks.zig` makes the cell a `sided` fork. In a parameter *port* list
that comma separates two `parameter_port_declaration`s, so the fold is refuted
on the very token that opened the split. The spared read is orphaned at birth
and is the only reading left. It shifts the comma into state 819:

```
state 819 — list_of_param_assignments_repeat51 -> , . param_assignment
  shifts: simple_identifier, \
```

Two symbols. `offer` unions one reading, so that is the entire slate handed to
the scanner, the keyword automaton for `parameter` never runs, and
`Scanner.choose` wins a tie with one contestant in it. And because a reading
survived, the parse never refuses, so the mend that on `heft` rebuilt the
declaration whole never runs either.

`JOINTS_TRACE=quire` says it in three lines - a `split` at 125, a `refuted` at
125, and on `heft` no third line at all.

## What has been ruled out

Both are measured against pin `coverlane`, whose tree differs from the arm in
exactly the one file under test, both arms sighted 30 of 30 by `pin.py oracle`.

The first two are measured against pin `coverlane`, whose tree differs from the
arm in exactly the one file under test, both arms sighted 30 of 30 by `pin.py
oracle`. The third is measured by gating one line behind an env var so a single
binary is both arms, which is the only clean A/B while other lanes hold
uncommitted work in this tree.

| Repair | Seats the row | Corpus |
|---|---|---|
| A spared reading dies with the keeper it was cast beside | yes | verilog square 3,472 → 668, kotlin 35,324 → 34,589, go `accepted` → `unexpected {` |
| Keyword extraction stops consulting the slate | yes, and better - `parameter_port_declaration/parameter_declaration` | verilog +4,798 built, php square 67,697 → 662, scala 6,739 → 201 |
| Only a `sided` orphan dies, and only as sole survivor | yes | 29 of 30 grammars byte-identical; verilog −1,460 built, −1,024 nodes |

The first says the `unwritten` change is right: its inheritance is what carries
go's `&T{}`, whose keeper also dies on the token that casts it, and what carries
kotlin's whole `sided` win. The second says tree-sitter's keyword pass is not
transplantable as-is, because twenty-one grammars name a `word` and their
literals are not all reserved words - go's `make` and `new` are the counter-
example.

The third is the one the new `sided` class made expressible, and it is the
sharpest of them: `collate.py adjudicated` goes from **ours 7 verdicts 1,299B**
to **8 verdicts 1,343B**, the delta being exactly this row, with nothing
outside verilog moving a byte. It still loses, and not near the repair. At
`[78013,78454)` the baseline builds a 441-byte `statement` over `if (resetn &&
pcpi_valid …) begin`; the repair shreds it into loose top-level
`simple_identifier` tokens, which is this defect moved rather than fixed.
Narrowing from "dies with its keeper" to "dies only as sole survivor" changed
no number, which is its own finding: wherever a `sided` orphan's keeper died,
the orphan already was the only survivor.

So the discriminator is not the class either. A `sided` orphan is fatal at
89368 and load-bearing at 78013 - same grammar, same class, and the same shape
down to the trace lines. Whatever separates them is finer than anything the
cell carries. Naming it is the open question.
