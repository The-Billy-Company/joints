# Result 1 — what the 1x is

Measured against pin `stoop-before` / `holds-trace` (tree `f7c6b3ef0ccf`, commit
`f7ba40004+105`), folio set digest `1b1a9a5d`, on collate's own keystroke
offsets so this and the scoreboard ask about the same edits.
Instrument: `research/keystroke/probe.py`.

## The premise I was handed is false

> php is the sole exception, at a 65x gain — which says the machinery works and
> the rest is a re-mint policy.

php's first collate keystroke lands at **byte 3**, and byte 3 of
`upstream/sources/*.php` is inside `<?php`. The edit makes it `<?pxhp`, the
opening tag stops being a tag, and the remaining 23 keystrokes are timed against
a file that reads as **73 tokens instead of 2,744**. The tree php returns after
that edit begins `(_php_tag)` and stops.

| php, 24 keystrokes | open | median edit | gain |
|---|---|---|---|
| collate's 24 offsets | 9,108 µs / 2,744 tok | **143 µs / 73 tok** | **63.7x** |
| the same minus the first | 9,296 µs / 2,744 tok | 5,247 µs / 1,135 tok | **1.8x** |

So php is not the working instance of incremental parsing. It is the thirtieth
instrument, and its 65x is one destroyed keystroke propagating through 23
measurements. **1.8x is php's real number, and 1.8x is what everything else on
the mended set gets too.** There was no working exception to generalize from.

`collate.keystrokes` is not wrong about anything it claims - it says "inside an
identifier, never in a string or at a boundary", and `p` inside `php` is an
identifier interior by every test it applies. It has no way to know that one
language's file-scope opener is spelled as a word.

## The 1x, in one line

Joints's incremental cost is `(1 − p) × cold` where `p` is the edit's position
in the file, **except** where the tiling was dropped, and then it is `cold`.
Both halves of reuse are independently off, for two independent and completely
separate reasons, and the split across the corpus is exact.

### The suffix half: one line refuses every lift on every mended file

`graft.stoop` opens with `if (q.roots.len != 1) return gr.chain.items;`. A parse
has one root exactly when it was `accepted`; a mend leaves a forest. So on every
file that mends, `stoop` nominates no candidate at any offset, and the counters
say so with no ambiguity at all - one keystroke each, at the file midpoint:

| grammar | roots | probes reaching `stoop` | `offered` | `lifts` |
|---|---|---|---|---|
| python | 1 | 7 | 11 | 5 |
| css | 1 | 21 | 69 | 19 |
| go | 1 | 10 | 11 | 4 |
| toml | 1 | 17 | 27 | 11 |
| json | 1 | 20 | 32 | 8 |
| swift | 308 | 926 | **0** | 0 |
| kotlin | 11 | 2,237 | **0** | 0 |
| verilog | 3,544 | 3,426 | **0** | 0 |
| latex | 72 | 517 | **0** | 0 |
| ocaml | 167 | 2,098 | **0** | 0 |
| scala | 26 | 634 | **0** | 0 |
| zig | 55 | 1,768 | **0** | 0 |

**11,606 probes across those seven forests get past the fork and alignment
gates, reach `stoop`, and are handed an empty chain.** Corpus-wide the
correlation is 29 of 29: `lifts = 0` on all 17 mended grammars, `lifts > 0` on
the clean ones.

### The prefix half: `holds` re-lexes with a slate the parse never used

`gather.alight` tries four rings and takes the first that seams, fits and
**holds**. `holds` drives the recorded states over the new bytes and demands the
same tokens back, and it builds the terminal slate for each token from one
state's raw row:

```zig
for (0..x.gr.terminal_count) |sym|
    if (x.t.at(state, @intCast(sym)).kind != .err) x.expected.admit(x.scanner, @intCast(sym));
```

`offer` - what the parse actually used - is a different set three ways: it
unions over **every live reading**, it narrows with `shiftable` (which follows
the folds down the stack, so a terminal whose reduce chain dies is *not*
offered), and it admits **every sprig's first terminal**. A different slate is a
different maximal munch, so `holds` gets a different token and declines a ring
whose bytes never moved.

That is not a deduction, it is the trace. Four grammars, one keystroke each, all
four rings refused:

```
swift    ring 57 at 13332 wanted ) 13335..13336 got _implicit_semi 13332..13332 from state 2
ocaml    ring 63 at  8160 wanted _lowercase_identifier 8161..8165 got then 8161..8165 from state 42
verilog  ring 136 at 47163 wanted = 47164..47165 got macro_text 47163..47191 from state 1
scala    ring 12 at  9538 wanted @  9902..9903  got stray from state 810
ocaml    ring 64 at  8349 wanted _lowercase_identifier 8350..8363 got stray from state 0
```

Read them as three distinct causes:

1. **The wider slate.** ocaml's `then` covers the same bytes as
   `_lowercase_identifier` and out-ranks it; verilog's `macro_text` swallows 28
   bytes where the parse read one `=`; swift's `_implicit_semi` is *zero width*,
   so `holds` cannot even advance. `.kind != .err` admits all three;
   `shiftable` did not.
2. **State 0 mid-file.** After a mend the recorded entry state is the ground
   state, whose slate is the file-start slate, and nothing mid-file lexes out of
   it. ocaml rings 61 and 64.
3. **Holes.** scala re-lexes from `back.at = 9538` while the first recorded
   token in the stretch starts at **9902** - 364 bytes a mend stepped over that
   no token covers. On a mended file the recorded stream is not a tiling of the
   bytes, and `holds` walks it as if it were.

`unheld=4` is the whole of `alight`'s decline on swift, ocaml, scala and
verilog: `unseamed=0, unfit=0`. The seam watermark a previous lane added is
doing its job; this is the check underneath it.

## The two populations the median was hiding

Splitting the mended 17 by whether the prefix resume succeeds separates the
board cleanly, and it is the split that matters because only one of them is
Swift's problem:

- **prefix works, suffix blocked** — kotlin (`stood=17,182` for an edit at
  17,907), zig (7,962 / 8,062), latex (2,570 / 2,623), julia. Cost is the tail
  re-read, so `≈ (1 − p) × cold`, so **~2x at the median edit**.
- **both blocked** — swift, verilog, ocaml, scala. `alight` declines, the parse
  starts on the ground, `stoop` refuses. Cost is **cold, every keystroke.**
  This is the 30,740 µs row.

And one more thing the median hid, which is in my own instrument: `probe.py`'s
`open` column is the **open** verdict, and the gate reads the **previous edit's**
verdict. java, rust, typescript and lua all open cleanly and then accept only 5
or 6 of 24 warm parses - they are forests for most of the sequence, and the
`roots.len != 1` gate was blocking them too. Calling them "the clean 12" was
wrong, and Result 2 is where it cost me a prediction.

## What this does not explain

Swift's second ceiling, which no policy in this lane touches: **4,283 of 6,622
asks (65%) are turned away by `turned_fork`** before `stoop` is reached at all.
verilog 36%, scala 30%, kotlin 29%. An offset inside a live GLR fork cannot be
lifted into, and on swift that is two thirds of the file.
