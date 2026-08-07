# Result 3 — the class is one verdict, not one fix, and the real defect has nothing to partition

joints `beb695b5d` · tree `e973ce73c` (pin) · oracle `d85e736fa` (30 of 30
live, 30 attributed) — the same control arm Result 2 measured against. The oracle
is seated but idle here: nothing on this page needs a verdict, because the floor
is a property of the press rather than of anyone's judgement of its trees.
Nothing in `src/` changed, so there is no treatment arm.

## What I set out to do

Result 2 ended by naming the open problem - carry predecessor-distinguishing
information for the few kernels that need it - and I was about to start building
it. Before spending a day on a generator change, I wanted the size of the prize.
The number came back at a twentieth of what Result 1 implied, and it came from a
tally the binary has been printing the whole time.

## The instrument was already shipped

`joints grammar <g>` prints it. There is no new script on this page.

```
$ joints grammar upstream/grammars/zig.json
  frayed         2006 cells contested only by state merging (1 REFUSE a token)
                 0 agreed, 0 alone, 0 stuck, 1 open — 0 SEALED under any split
```

The four buckets are `lalr.Floor`, and its docstring already carried the whole
answer for zig, worked example and all: *"Zig's `{` is the worked example... Its
cell is `open`; the round that separated its kernel was built, 1834 states
against 1720, and the cell survived with the same kernel hash under a new id.
Three ceilings - 4, 16, 64 - give byte-identical automata, so the plan was not
truncated either."* I confirmed the zig row myself before trusting the rest.

What the buckets mean, in the order that matters:

- **`alone`** - invented, but through a *single* arrival. There is no partition
  of one.
- **`stuck`** - several arrivals, none of them tellable apart here.
- **`agreed`** - not invented at all; LR(1) builds the same cell.
- **`open`** - the arrivals do differ, and a partition exists that `Plan.cut`
  cannot express.

`sealed` is the first three. Only `open` is reachable by any amount of state
splitting.

## The corpus

| bucket | cells | share |
| --- | ---: | ---: |
| `alone` | 1,921 | 87.5% |
| `stuck` | 130 | 5.9% |
| `agreed` | 17 | 0.8% |
| **sealed** | **2,068** | **94.2%** |
| `open` | 128 | 5.8% |
| total | 2,196 | |

**Ninety-four percent of every refusal on the corpus is sealed under any split.**
The design project Result 2 pointed at can reach 128 cells, and that is the
ceiling on it rather than an estimate of it - `open` is the bucket another round
*can* reach, not one it will.

## The five rows of Result 1's "class"

| row | refuse | agreed | alone | stuck | open | sealed |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| verilog | 72 | 0 | 64 | 4 | 4 | 94.4% |
| swift | 59 | 0 | 45 | 8 | 6 | 89.8% |
| sql | 61 | 0 | 58 | 0 | 3 | 95.1% |
| julia | 8 | 0 | 8 | 0 | 0 | **100%** |
| zig | 1 | 0 | 0 | 0 | 1 | **0%** |

Zig is the only one of the five that is entirely `open`, and julia is entirely
sealed. So the five rows do share a verdict - `press?`, a merge damaged this
cell - and they do not share a fix. Solving zig's 208 perfectly buys 4 of
verilog's 72, 6 of swift's 59, 3 of sql's 61, and **none** of julia's 8.

Result 1 said "five rows, one mechanism, and between them 61.5% of all remaining
damage". The mechanism sentence is still true. The implication I let it carry -
that one fix would collect the 61.5% - is not, and this page is the correction.

## What `alone` actually is, and why it is the interesting one

`alone` is 87.5% of the board and it is not a state-merging defect at all.
`Seam.arrivals` says it plainly: *"One means there is nothing to separate: the
merge widened the lookahead through a single context, so no partition of
arrivals exists at all."*

One arrival, and the lookahead is still wider than the grammar wants. So the
widening did not happen *across* arrivals - it happened inside the follow
computation, in the `reads`/`includes` graph DeRemer and Pennello walk. That is
LALR merging lookaheads for one LR(0) item across the LR(1) contexts that share
it, in a state only one path reaches.

No arrival partition touches that, at any price. IELR, lane tracing over states,
Pager's weak compatibility, and the predecessor-carrying scheme Result 2 sketched
are all answers to the same question - *which arrival are we on* - and `alone`
cells do not have a second arrival to be on. The fix for them lives one level
down, on the item and its lookahead, which is a different piece of machinery and
a much bigger one.

## An aside worth writing down: refusals do not track damage

scala has **1,177** refusals, 98.9% of them sealed - more than the rest of the
corpus put together - and after the string provisions landed it is not a damage
row worth naming. bash has 358 and 413 bytes of damage. zig has 1 refusal and
1,375 bytes.

So a refusal count is not a damage forecast, and I should stop reading it as
one. A sealed cell in a corner of the grammar the corpus never walks costs
nothing. That cuts the other way too: the 128 `open` cells are not 128 bytes and
not 128 fixes, and I have not shown that any of them except zig's stands under a
wall.

## What I trust least

The floor counts **cells**, not walls. It bounds what a split can reach; it does
not prove that julia's wall, or sql's, sits in a sealed cell. Every one of those
verdicts still prints `press?` with the question mark `inquest.zig` puts there on
purpose, and I have traced exactly one wall - zig's - to a specific cell.

So the honest statement is the bound, not the attribution: *whatever* cell each
of those walls is downstream of, in julia 100% of the candidates are sealed, in
sql 95%, in verilog 94%, in swift 90%. That is enough to stop me building the
predecessor scheme today. It is not enough to say what will fix them.

I also took the whole survey on one binary in one pass, and the tree moved
underneath me twice while I worked - other lanes are editing `src/`, and a bare
`--cite` reported a different digest each time I asked. Everything here was run
against `.local/pin/scala-string/bin/joints` by path, so it is reproducible
from that pin; it is not reproducible from `HEAD` unless `HEAD` is that commit.

One trap worth recording, since it nearly put a wrong stamp on this page: a
stale `JOINTS_BIN` exported in an earlier session pointed at the `zero-strand`
arm while `JOINTS_WORK` pointed at `scala-string`, and `--cite` obligingly
reported the mismatch as `0 of 30 held`. `stamp.py` caught it - `TOLD`, then
`DRIFT` naming the tree that no longer exists. That gate earns its keep.
