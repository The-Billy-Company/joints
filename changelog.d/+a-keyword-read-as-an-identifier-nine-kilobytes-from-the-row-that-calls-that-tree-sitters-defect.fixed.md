`collate.py prove` printed `FAIL  clean tree drifts nothing` and nothing else. No
grammar, no span, no direction, on a check whose whole job is to notice that a
hand verdict stopped describing the trees. The lane that found it had to derive
verilog/go/php from somewhere else, and three of those five rows turned out to be
good news. **A falsifier that fires without saying what it caught costs its
reader the entire investigation.**

It says it now, per row: grammar, byte span, width, the verdict it carries, which
side moved, and both readings. Direction is the part that matters, because
`lost`/`gained`/`renamed` moved a row's *verdict* and `deeper`/`shallower` moved
only its *transcript* of the ancestor chain, and reading those as one finding is
exactly the mistake that was available:

```text
FAIL  every stored verdict still describes both live trees
      verilog [89368,89412) 44B  judged `ours` (outliner is right)
        DRIFTED ours lost: parameter_declaration -> —; neither tree has a node here any more
      verilog [50526,50629) 103B  judged `agree` (both say the same thing)
        DRIFTED ours deeper: expression/…/system_tf_call -> list_of_actual_arguments/expression/…/system_tf_call
```

**The headline is the first row, and it is a regression.** The bytes are
`parameter [31:0] MASKED_IRQ = 32'h 0000_0000` - A.2.1.1's
`parameter_declaration ::= parameter data_type_or_implicit
list_of_param_assignments`, which outliner used to name and tree-sitter covers
only with a 989-byte `operator_assignment` inside a root `ERROR`. Outliner now
builds no node over the span. What it builds instead is `simple_identifier
[89368,89377)` over the word `parameter`, a bare `[`/`constant_range`/`]`, and a
`variable_decl_assignment` over the tail. **That is the keyword read as an
identifier - the defect the [80096,80105) row of the same file adjudicates as
tree-sitter's, over the same nine-byte word, and that row has not drifted.** Same
word, same grammar, 9 KB apart, two readings, so nobody chose this.

Attributed rather than guessed. Deterministic first: six fresh processes on one
binary give one answer, so this is not the press-nondeterminism class that made
nine grammars press to different bytes this week. Then across thirteen pins the
reading tracks `src/press/bench.zig` - held on that file's pre-lane revision and
on the `unjudged`/`crowdonly`/`alone2` arms, lost on the
`bh`/`bonly`/`bhc`/`skeinsonly`/`ship` arm, which is the one that shipped - and
`src/kernel/quire/gather.zig` can rescue it at one fuse setting (`crowd64`). The
first arm to lose it is `bh`, whose source manifest differs from `heft`'s in
`src/press/bench.zig` and `src/press/ladder.zig` and nothing else.

That is the `unwritten` change, and this is the honest part: its claim is
*"costing nothing is the whole claim … nothing is overruled and no row moves"*,
measured in `built`, `nodes` and `standing`. A node replaced by three loose
siblings over the same bytes moves none of those - the bytes stay covered, the
node count barely twitches - so **the board it was measured on could not see
this.** Neither could the fuse census that justifies `crowd = 64 / skeins = 512`,
whose four corners are byte-identical at 309,356 square **without verilog**. This
row is the verilog those measurements left out. `bench.zig` is under another lane
right now and is not this lane's to change, so the row is left drifted, red, with
the bisection written into its `why`.

The other verilog row grew a fifth ancestor, `list_of_actual_arguments`, over the
same extent. It is an `agree` control whose stated claim is the *deepest* node, and
that is untouched, so the drift is in the stored chain string rather than the
verdict. It flips between pins `swift-raw` and `g-control`, an 18-minute window
with no pin in it whose manifests differ in three production files and no
changelog fragment naming any of them. Three files is not a named change, so it is
not re-transcribed either.

**Three rows were dissolved by siblings fixing the product, and are re-judged
rather than re-captured.** Each was `theirs` - tree-sitter right, outliner wrong -
and each now reads what tree-sitter reads:

| row | was | is | the change |
|---|---|---|---|
| go `fmt.Print("x")` | `type_conversion_expression` | `call_expression` | flips `aud-live` → `heft`, whose manifests differ in `src/kernel/quire/gather.zig` **alone** - the `collapse` merge |
| php `"x"` | no node at all | `encapsed_string` | flips `php-before` → `php-after`; four of `scan_encapsed_part_string`'s six terminals seated |
| php `$a = "x";` | no node at all | `expression_statement` | same window, one rung up |

The go row is the *same* dissolution `rack.py` already reported, arriving in a
second instrument: `rack` carried the identical tripwire on this identical
specimen and was re-asked of the corpus for it, and nobody checked whether
`verdicts.toml` held a copy. It did. All three are kept as the regression guard for the fix
that dissolved them, `side = agree`, with the old reading named - the shape swift's
`multiline_comment` row already had. 18 of 20 rows are live again and only verilog
is excluded from the totals.

**And the reference has an anchor now, which is the part that generalises.**
`verdicts.toml` is a *stored* artifact - `adjudicated` derives both trees live and
compares them to hand-written strings - so it has a ratchet baseline's failure
mode exactly: the cheap way out of a red row is to paste today's two names in and
leave `side` alone. Then the file asserts one parser is right about a span where
both now say the same thing, and that lie is mechanically visible in two
directions: a row naming a winner must have something for it to have won, and a
row saying `agree` must have its two names agree. (`neither` stays unconstrained -
both parsers saying the same wrong thing is a real verdict, and it is `neither`
rather than `agree` because it carries more.)

Demonstrated on the live red row rather than argued for. Paste today's reading
into verilog `[89368,89412)` and leave `side = "ours"`, which is precisely the
shortcut available this hour:

```text
re-captured row still drifts?  False        # the check it was meant to silence, silenced
anchor refuses it?             verilog [89368,89412) side=ours  — vs —
```

So a re-capture that skips the re-judgement fails a *different* check than the one
it silenced. The anchor is driven negative on whichever row can answer it today
rather than on a named row a sibling can dissolve, and it fails loudly if no row
can answer rather than passing over nothing.

None of this was done with `git log -p`, because it could not be: `src/press/bench.zig`
- the file the regression tracks - and `tool/collate.py` are both **untracked**, and
`gather.zig`'s working state is uncommitted at 141 dirty files against `f7ba400`.
There is no commit to name for the change behind the red row, and there never
was. `.local/pin/*/world.json` source manifests are the only delta instrument this
tree has, which is why every attribution above is a pin pair.

What I trust least is that attribution, and specifically its floor. Pins are
wall-clock snapshots of a working tree ten agents are editing, so a window is
"everything that landed between these two builds" and not one lane's change. The
two rows I acted on are one-file windows (`gather.zig` for go, a named
before/after pair for php) and the regression's first-loss window is two files in
the same directory; the row I did **not** act on is a three-file window, and that
difference is the whole reason one set moved and the other did not. If someone
committed twice inside one of those windows I would have no way to see it from
here.
