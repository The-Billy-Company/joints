# Result 5 — the chain, and the class dissolving on contact with it

Treatment: joints `2657b5416` · tree `cec2e31ee` (pin) · oracle `d85e736fa`
(30 of 30 live, 30 attributed).
Control: joints `2ec8d6492` · tree `b9c36ab21` (pin) · same oracle
`d85e736fa` (30 of 30 live, 30 attributed).

One court, two binaries, both arms fully live. `still against` says
**comparable**: the two trees differ in four files, three of them mine and the
fourth `src/.DS_Store`, a Finder artifact no build graph reads. The control is a
worktree at `HEAD` carrying the lex lane's uncommitted files, so the arms differ
by my change and nothing else.

## What I set out to do

Result 4 ended on an instrument gap rather than an answer. Four walls printed
`press?` and closed with *"no fold chain was supplied to say whether this wall is
downstream of it"* - `inquest` saying it cannot rule the press out, which I had
spent a page reading as an indictment. The fix was named there and it was small:
`kernel/walk/drive.zig` keeps the chain and is test-only; `kernel/quire/gather.zig`,
the loop the CLI runs, walks the same states and keeps only the endpoints.

## The change

Both absorb loops append `{state, prod}` for the table's own reading - the
`rank == 0` condition `x.refused` already uses, because a stack that took the
losing side of a conflict explains the file worse than the one that did not. The
list is cleared per token and sealed when a stop becomes the one the parse will
report, then duped into the `Quire`, which outlives the gather that walked it.

`folded` is `?[]const Fold` and the question mark is load-bearing. Empty already
means something: a token refused before folding anything drove no reduces, so no
cell on its path can be blamed. Null is nobody having looked. A verdict that
reads the two the same reports a suspicion as a proof, which is the exact defect
this page is fixing.

## The four falsifiers, and the one that fired

**Every row byte-identical.** The board over both arms, diffed line by line:
identical. This records what the loop already walked, and it moved no `built`,
`damage`, `square` or `crooked` anywhere.

**No verdict got worse.** Four moved, all from unproven to proven:

| row | before | after |
| --- | --- | --- |
| zig | `press?` (1 dropped, 5 misfolded) | **`press`** — state 208, `read_dropped`, **`open`** |
| julia | `press?` (0 dropped, 14 misfolded) | **`oracle`** — state 523, `fold_dropped`, `alone`; *fork still offers `tuple_expression`* |
| swift | `press?` (0 dropped, 3 misfolded) | **`weave`** — empty under every split |
| verilog | `press?` (1 dropped, 23 misfolded) | **`weave`** — empty under every split |

The other twenty-six rows print the same verdict, character for character. The
census the test suite takes now reads **30 grammars · 5 whole · 11 lexer · 1
press · 10 weave · 3 oracle (2 unproven)**.

**No parse-time regression.** Ten runs of verilog - the mend-heaviest row, 2,034
mends - three rounds: control 9.306 / 9.289 / 9.362 s, treatment 9.439 / 9.380 /
9.305 s. Under a percent, and the sign flips in round three. Kotlin, the heaviest
row at 1.34 s of user time, is identical to the centisecond. The chain is cleared
per token, so it stays as long as one token's reduces and no longer.

**No leak, no dangling read.** The suite is green under the testing allocator;
the shard covering the resume-and-mend path reports `0 leaked` explicitly.

## The falsifier that fired, and what it taught

Verilog did not move on the first build. Its chain came back **null** where
zig's, julia's and swift's came back with 7, 7 and 1 folds - and the probe said
`seal` was called 1,983 times on that file and found the stop already remembered
every single time.

The cause is Zig result-location semantics. The supply path spells it:

```zig
if (x.why == null) x.why = .{
    .unexpected = .{ …, .folded = try x.seal() },   // wrong
};
```

The literal is built **in place** in `x.why`, so the tag lands before the field
expression runs, and `seal` - whose whole job is to decline once a stop is
already remembered - found the stop it was being called *for* already there.
Sealing into a name first fixes it. Verilog then reports a chain of **length
zero**, which is the right answer and the reason the field is optional: the
backtick drove no reduces, exactly as Result 4 read off state 3438's empty
lookahead row.

It only showed on grammars whose *first* refusal is a supply. Four of five rows
were fine, the survey looked done, and the one that was not was the row I had
already explained away on other grounds. Without the two-arm verdict diff over
all thirty rows I would have shipped it.

## What this does to Result 1's class

| row | damage | Result 1 | now |
| --- | ---: | --- | --- |
| verilog | 62,852 | `press?` | `weave` — empty under every split |
| swift | 2,377 | `press?` | `weave` — empty under every split |
| sql | 2,309 | `weave` | unchanged |
| julia | 1,955 | `press?` | `oracle` — a declared ambiguity, fork still offered |
| zig | 1,375 | `press?` | **`press`** — the one frayed `open` cell |

Result 1 read one sentence as one mechanism holding 61.5% of remaining damage.
The sentence was `inquest` declining to guess. **One row of the five is a press
defect** - zig's 1,375 bytes, 1.2% - and the instrument says so now rather than
me arguing it from grammar JSON. Verilog's independent confirmations still stand
and now agree with the binary: the grammar admits no directive in a port list,
state 3438 has an empty lookahead row, tree-sitter 0.26.11 puts an `ERROR` on the
same byte, and the verdict reads `weave`.

## What I trust least

The `oracle` verdict on julia is new to me and I have not audited what it means
as carefully as I have audited `press`. It says the invented cell on the path is
one the author declared and the fork is still offered, which reads as *the table
is not at fault and a single-stack loop would be* - but I have traced zig's cell
by hand and not julia's, and Result 3's floor says julia's candidates are 100%
sealed. Those are consistent; I have not proved they are the same fact.

The timing is three rounds of ten on one machine, with other lanes building. It
is enough to say there is no percent-scale regression and not enough to say there
is none at all. The append is one per reduce on the table's own reading, so if it
ever shows up it will show on a fold-dense grammar, and verilog at 2,211 folds is
the one I measured.

I also did not thread the chain onto `Scar.why`. Scar stops never reach
`inquest`, so they carry `null` - honestly, since nobody sealed them - but if a
future caller does ask a scar who owns it, it will get the unproven answer this
page exists to remove.
