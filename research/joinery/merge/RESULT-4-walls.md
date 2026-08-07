# Result 4 — four of the five walls are not merge defects, and the biggest one is not ours

joints `beb695b5d` · tree `e973ce73c` (pin) · oracle `d85e736fa` (30 of 30
live, 30 attributed), tree-sitter CLI 0.26.11. No `src/` change, so no treatment
arm. Every claim below is read off the shipped CLI, the grammar JSON, or a live
tree-sitter parse.

## What I set out to do

Result 3 closed by admitting the gap: the floor counts *cells*, not walls, so it
bounds what a split could reach without showing that any particular wall sits in
a sealed cell. This page closes that gap by going to the walls themselves, one
at a time. Four of the five turned out not to be merge defects at all, and the
one carrying 89% of the class's damage is not joints's defect in any sense.

## The verdicts, read properly

The five rows do not print the same verdict. I had been reading the shared
*sentence* and missing that one of them names a different owner and a different
mechanism:

```
zig      press?  on {                 in state  715  (1 dropped,  5 misfolded)
julia    press?  on _delimiter_str_1  in state  136  (0 dropped, 14 misfolded)
swift    press?  on <identifier>      in state 1103  (0 dropped,  3 misfolded)
verilog  press?  on `                 in state 3438  (1 dropped, 23 misfolded)
sql      weave   on _identifier       in state  275  (2194 read, 1267 fold, 0 frayed)
```

Four `press?`, one `weave`. And every `press?` closes with the same clause, which
is the whole reason for the question mark:

> a merge damaged this terminal's cell elsewhere, **and no fold chain was
> supplied to say whether this wall is downstream of it**

That is `inquest.zig:610` firing: `folded == null` and the table has *some*
damage on this terminal *somewhere*. It is an inability to rule the press out,
and I built a class on it.

## verilog: the grammar does not allow it, so neither does anyone

Byte 3712 of `picorv32.v` is the backtick of:

```verilog
	output reg [31:0] eoi,

`ifdef RISCV_FORMAL
	output reg        rvfi_valid,
```

A preprocessor conditional **inside a module port list**. State 3438 is exactly
where you would expect:

```
  items:
    list_of_port_declarations_repeat18 -> … , . _description_repeat4 ansi_port_declaration
    list_of_port_declarations_repeat18 -> … , . ansi_port_declaration

  shift 47, lookahead 0 — 47 terminal(s) accepted of 444
```

**Empty lookahead row.** No fold at all, so nothing here was resolved away, and
the 47 accepted terminals do not include a backtick in either spelling. Nothing
was dropped; the token is simply not a legal continuation.

The grammar agrees, and it is the shorter proof:

```json
"list_of_port_declarations": "(" attribute_instance* ansi_port_declaration
                             ("," attribute_instance* ansi_port_declaration)* ")"
```

After the comma the grammar admits `attribute_instance` - `(* … *)` - and
nothing else. `_description_repeat4` is our importer's name for that repeat, not
for a directive list. Directives live one level up, in `_description`, between
whole declarations. tree-sitter-verilog spells `` `ifdef `` as a `PATTERN`
aliased to `directive_ifdef` inside `id_directive`, and there is exactly one
backtick *literal* in the entire grammar, in `simple_text_macro_usage`. Neither
is reachable from a port list.

So the state row and the grammar JSON say the same thing from opposite ends:
**upstream's grammar cannot parse `picorv32.v`.**

And the oracle agrees, which turns this from an inference into a measurement.
tree-sitter 0.26.11 over the same file emits **267 `ERROR` nodes**, and one of
them lands on the byte:

```
byte 3712 is row 122 col 0 = '`'
ERROR spans covering it:  [122, 0] - [123, 7]
                          [0, 0]  - [3049, 0]
```

The tight span starts at exactly our wall. The outer one covers essentially the
whole file. So tree-sitter does not parse `picorv32.v` either; it differs from us
by covering the refusal with an `ERROR` node rather than stopping, which is a
recovery difference and not a table one.

Verilog is **62,852 bytes - 89% of the class by damage - and none of it is a
merge.** Result 1 named this exact risk in its own "what I trust least": *"If
verilog turns out to be its own thing, the remaining four are 8,016 bytes and
this page is a much smaller claim."* It is its own thing.

## sql: proven, and proven to be a different shape

sql is the one row that never said `press?`. Its verdict is complete:

> `weave` on `_identifier` in state 275 (2194 read, 1267 fold, **0 frayed**): the
> cell is empty, and a merged lookahead is a superset of every canonical one it
> stands for, **so it is empty under every split**

Zero frayed cells on that terminal, an owner that is the loop rather than the
press, and the verdict itself saying no split reaches it. Grouping it with the
`press?` four was reading the root-cause clause and ignoring the owner.

## julia and swift: still open, and not yet attributable

Neither is settled here, and neither is obviously a merge.

**julia** walls on the `"` of `"type mismatch"` in

```julia
@assert (… A isa AbstractSet) "type mismatch"
```

a string as the second, space-separated argument of a macro call. The terminal
is the string opener `_delimiter_str_1`, which puts it in the same family as
scala's `_simple_string_start` - a lexer question first, whatever the table then
does with it.

**swift** walls on the `b` of `baseStartIdx` in `let baseStartIdx = baseIdx ?? baseBound`,
24,582 bytes into a file whose earlier `let` bindings parsed fine, having
surveyed 6,231 of 13,863 nodes. An ordinary identifier after `let` is not a
defect you can read off one state; it is downstream of something earlier, and
saying what needs the fold chain nobody supplies.

## The instrument gap, now precise

`inquest.refused` can prove attribution - it walks the chain, finds the cell,
and reports its `lalr.Floor` bucket - but only if it is handed `folded`. It
never is on a real parse:

- `kernel/walk/drive.zig` **does** record the chain. `d.folded` is cleared per
  token and appended on every reduce, and its `.unexpected` carries
  `{ tok, state, folded }`. It is the single-stack differential loop, used only
  by `gather_test.zig`.
- `kernel/quire/gather.zig` - the GLR loop the CLI actually runs - records only
  the endpoints: `.unexpected = { symbol, at, state = x.refused }`, with the
  comment noting that `x.refused` is where the folds ran out rather than where
  they started. The states in between are walked and discarded.

So every wall verdict from the shipped binary is structurally unprovable
whenever the table has any damage on that terminal anywhere. That is not a
missing analysis; it is one list not being kept in a loop that already walks it.

**That is the next build**, and it is small: thread the fold chain through
`quire`'s reduce path to the stop, or run `nzig` alongside for the verdict only.
Until it exists, `press?` means "cannot rule the press out", and this page is
what happens when four of those get read as an indictment.

> **Built, in `RESULT-5-chain.md`.** Every conclusion below survived it, which is
> the strongest thing I can say about a page that argued from grammar JSON and
> state rows rather than from the instrument: verilog and swift now print
> `weave` - empty under every split - julia prints `oracle`, and zig is the one
> `press`. The two rows this page called undiagnosed are diagnosed and neither
> is a merge.

## What the class actually is now

| row | damage | verdict here | what it is | verdict after Result 5 |
| --- | ---: | --- | --- | --- |
| verilog | 62,852 | `press?` | upstream grammar admits no directive in a port list | `weave` |
| swift | 2,377 | `press?` | unattributed; downstream of something 6,231 nodes back | `weave` |
| sql | 2,309 | `weave` | empty cell, 0 frayed, empty under every split | `weave` |
| julia | 1,955 | `press?` | string opener as a macro's second argument | `oracle` |
| zig | 1,375 | `press?` | the one genuine frayed `open` cell | **`press`** |

Result 1 claimed 61.5% of remaining damage for one mechanism. What survives is
zig's 1,375 bytes - **1.2%** - as the only wall on the board traced to a frayed
cell, plus two rows that need their own look and two that are answered.

## What I trust least

I nearly shipped this page saying tree-sitter was unavailable to check it,
because `which tree-sitter` came back empty. It is not on `PATH` and never was:
the harness owns its own CLI under `.local/differential/cli/node_modules/.bin/`,
and `differential.py oracle` is the question to ask. One wrong command turned an
available falsifier into a caveat, and the caveat would have read like diligence.

With it actually run, the verilog section now rests on three independent
readings that agree - the grammar JSON, state 3438's own row, and tree-sitter's
`ERROR` on the byte - so I trust it least no longer.

julia and swift are described here, not diagnosed. I looked at one byte and one
state for each and stopped, because the honest next move on both is the fold
chain rather than more staring.

The 267 `ERROR` count is also not a damage figure. It says tree-sitter's tree
over that file is largely error, not how many bytes either of us loses; the
board's 62,852 is ours and I have not derived a comparable number for the
oracle.
