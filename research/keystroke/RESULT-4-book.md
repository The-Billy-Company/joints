# Result 4 — the prefix half on a scanner that is only a book

No prediction file. This came out of the customaries lane's rung-5 benchmarking
rather than from a question this folder asked, and it lands squarely on this
folder's subject, so it is recorded here in the shape the others have.
Instrument: `research/keystroke/probe.py` and `research/keystroke/abide.py`,
collate's own keystroke offsets, `zig build` default optimize.

## The third reason `holds` declines

Result 1 named one: `holds` re-lexed each recorded token under a slate the parse
never used. Result 3 attempted the repair three ways. Both were about *which
terminals* the replay admits.

There is a third, and it is not about the slate at all. `holds` restores the
scanner before its replay only when `x.scanner.casts.len > 0` — the old spelling
of "does this grammar have an external scanner", from when the only external
scanner was a hand-written one. A customary is the other half of "outside" now.
The write side had already been moved onto `Scanner.outward`, with a comment on
`remembers` saying why. **The read side had not.** So every grammar whose whole
scanner is a book kept one `Save` per ring, a few kilobytes each, and read none
of them back — the replay ran with whatever memory the attempt it was replacing
had left in the scanner.

yaml is the extreme of it. `_bl` is the blank line the grammar owes itself, zero
bytes wide, and whether one is due is a fact about the organs:

    holds: ring 21 at 8838 wanted _b_sgl_pln_str_blk 8849..8855 got _bl 8849..8849
    holds: ring 20 at 8057 wanted _br_sgl_pln_str_blk 8068..8087 got _bl 8068..8068
    holds: ring 19 at 7523 wanted _br_blk_str_ctn 7530..7603 got _bl 7530..7530
    holds: ring 18 at 6993 wanted _b_sgl_pln_str_blk 7011..7015 got _bl 7011..7011
    alight: declined - firm=9467 unseamed=0 unfit=0 unheld=4 lowest=6928

Four candidates, four disagreements over bytes nobody touched, and a cold parse
from the top of the file for a keystroke in the middle of it. One word.

| yaml, 24 keystrokes | read | prefix | per key |
|---|---|---|---|
| before | 1,327 tok | 0.97 | 2,529 µs |
| after | 669 tok | **0.49** | **1,388 µs** |

A prefix near 0.5 on edits spread through the interior is the honest floor for a
grammar whose suffix is not being lifted: it means the parse now stands up *at*
the edit and reads only what is after it. html's `_end_tag_name` /
`erroneous_end_tag_name` decline from Result 1's era was the same root cause and
is gone with it — that one is the tag stack rather than a blank line, but it is
the same stale organs.

Three of `holds`'s four exits were silent, which is why this sat behind a counter
reading `unheld=4`. `alight` says *which* of its three questions declined, and
that was enough to know the replay was the one and useless for knowing why. All
four exits now say what they saw. The counter said where to look; the traces said
what to fix.

## Falsified: taking a ring where a lift lands

`.lifted => continue` in the token loop skips the ring-taking that `.took` does,
so a parse that lifts its whole tail records no ring over that tail, and the next
keystroke below it has nothing to stand on. java lays 6 rings on the open and 0
on each of the three edits after it. Reuse eating its own future is a real shape
and the counters show it plainly.

**Fixing it did not help, twice.**

Charging the lift one tick like a token: yaml 1,591 → 1,326 µs, markdown 179 →
168, and latex 79 → 87, toml 38 → 45, embedded-template 77 → 92. java, rust and
html — the grammars it was built for — did not move at all (0.98, 0.99, 0.98),
because a 15-move parse never reaches a stride however you count it. Two markdown
edits stopped spinning.

Charging it the leaves the subtree stood in for — the moves the previous parse
actually made there, counted for free in `transcribe`'s existing walk, which is
the principled version — was **worse**: median prefix 0.25 → 0.27, median gain 9x
→ 7x, and six grammars lost spins (python, javascript, embedded-template, latex,
markdown, toml). java still 0.98.

Both reverted. The ledger being empty ahead of a lifting parse is not what is
costing java, rust and html their prefix, and a ring policy is not the repair.
Kept as a negative result because the shape is convincing enough that somebody
will propose it again.

## Open: a ring whose `at` and `token` disagree

What *is* refusing the remaining grammars looks like a different defect, and
three of them show one shape — the replay starts **behind** the token the ring
indexes:

| grammar | trace | behind by |
|---|---|---|
| haskell | `ring 22 at 5321 wanted _cmd_layout_start 5323..5323 got … 5321..5321` | 2 B |
| kotlin | `ring 20 at 5513 wanted inline 5521..5527 got public 5514..5520` | 7 B |
| elixir | `ring 2 lift call begins at 10029, re-read reached 10027` | 2 B |

kotlin is the legible one: at ring 19's `at` of 5513 the next token in the new
bytes is `public` at 5514..5520, and ring 19's `token` index points past it at
`inline`. The offset and the token count are describing two different places, so
the replay is asked to match a stream it is not standing at the head of. Both
haskell and kotlin mend on the open, which is where a deleted token advances
`x.at` without appending an entry, but that skew runs the *other* way, so the mend
path is a suspect and not an explanation. Not chased here.

## What did not change

`abide.py` reads 17 of 30 grammars agreeing element-for-element with a cold parse
after all 24 edits, the same 17 as before this lane, and `--prove` refuses all 30
— the guard is demonstrably able to say no. `zig build test` green.
