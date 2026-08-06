# Result 2 — the race, reproduced, and both rules watching it

`python3 research/generation/stage.py` — five trials, all real processes, none
of them touching the shared `.local/standing` that nine other agents read.

## The one that matters: `blind`

One warm private cache. **Three** re-minting agents running the older binary
over it. **Two** boards started at the same instant against that one cache —
one running `tool/` as it is now, one running a scratch copy of `tool/` with
the old rule appended back on (`cost.arm`, the same restore `cost.py` prices).
Same seconds, same cache, same publishes, two readings:

```
  the OLD rule - a stat, recorded and never looked at again  (0.9s, exit 0)
    the cache says          kept 30
    the content rule says   one generation, every row comparable
    the number a report repeats: 349259 built of 526798 (66.3% standing)

  the NEW rule - the same cache, the same agents, the same seconds  (0.9s, exit 3)
    the cache says          kept 30
    an mtime rule would say 5 of 31 artifact(s) moved
    the content rule says   SPLIT: 4 artifact(s) moved, 4 of 30 rows not comparable
      rows: cpp, css, elixir, go
      …/cache/cpp.folio: read bd4d888a0b4b, now 8c8e4f2b55c3 (2 generations)
      …/cache/css.folio: read 4270600ba2b5, now d3fa54252540 (2 generations)
      …/cache/elixir.folio: read 2860d1fd873a, now 5a8448a3e4b0 (2 generations)
      …/cache/go.folio: read a1e70d49dde0, now 5574d142a692 (2 generations)
    the number a report repeats: 349259 built of 526798 (66.3% standing)
      — 54824 of those bytes from a generation this tree no longer holds
```

Read the two `built` numbers. **They are the same number.** The old board is not
wrong-looking; it is identical and unmarked, `kept 30`, exit 0. That is the
failure as it actually happens — not a bad number, a good-looking number nobody
can attribute.

The threads in that trial are two `wait` calls. The three things racing are
three real processes plus two real board processes, because the pid is what
keeps two minting agents off one temp filename and a threaded stage would not be
exercising the thing under test.

## Against the predictions

**#1 — "the board today says nothing."** Held, exactly. `cache: kept 30`, no
`stamp:` line, exit 0.

**#2 — "the split is real and lands mid-table."** Held, but it took work, and
the work is the finding. A board over a *warm* cache is 0.9s and one agent's
first press takes longer than that, so the first run of `blind` provoked
nothing at all and said so rather than passing. It needed three agents and a
wait until the agents were genuinely mid-flight. Same for the binary swap: 0.25s
landed before the first row and 2.5s landed after the last, both times with the
mechanism correctly reporting one generation, so the trial now tries a series of
delays and reports **which one landed** (`swapped at 0.5s of a 3.8s run,
attempt 1`). A race you have to aim at is still a race; a race you never made
fail is not a fix.

**#3 — "the flagged set is a prefix of the row order."** Falsified, and the
prediction was just wrong about the shape. A row is flagged when its folio is
republished *after* that row read it, and the writer is not one sweep — three
agents cycling at their own speed against a board cycling at another. In `race`
the flagged set was `c, cpp, go, julia, python, ruby, rust, scala, sql, swift`,
which is not a prefix of anything. The claim that survives is the weaker,
correct one: not zero, not thirty, and each named row's read digest genuinely
disagrees with what is at that path when the run ends.

**#4 — "a same-binary re-mint is quiet."** Falsified, by Result 1. The press is
not reproducible for at least fourteen grammars, so the control fires too:

```
  the SAME binary re-minting the cache under the board  (8.2s, exit 3)
    an mtime rule would say 16 of 31 artifact(s) moved
    the content rule says   SPLIT: 2 artifact(s) moved, 2 of 30 rows not comparable
      rows: julia, python
```

The control still does the job it was built for, just not the job it was
predicted to do. **16 against 2** is the discrimination the whole design rests
on: fourteen artifacts were republished under that board with byte-identical
content, an mtime rule would have called every one of them a split, and the
digest called them the same file. The two it does flag are two genuinely
different folios, and they are different because the press wobbles, which is a
bug in the press and not a false positive in the ledger.

## What the board does about it

Three behaviours, and the middle one is the deliverable:

- **Silent** when every row's artifact is the one the tree holds now.
- **Loud** otherwise: each affected row gets ` · SPLIT` in the table, the footer
  names the artifacts with `read <digest>, now <digest>`, and the run exits
  **3**. Not 1 and not 2 — a mixed board is not a lane's bad day and not a
  parser fault, it is a table that is not one measurement, and a caller piping
  it somewhere has to be able to tell that from a table that is.
- **`--settle[=N]`** re-measures only the named rows, up to N times (default 2):

```
  a real older binary re-minting the cache under the board · --settle  (8.8s, exit 0)
    an mtime rule would say 17 of 31 artifact(s) moved
    the content rule says   one generation, every row comparable
      11 artifact(s) moved and every row that read the old generation was measured again
```

Eleven artifacts moved under that board and it still closed whole, because the
eleven rows that read the old generation were measured again against the new
one. Re-measuring the named rows rather than restarting the board is deliberate:
a restart throws away twenty-nine good rows because one folio moved, and against
a tree ten agents rebuild continuously an unbounded restart has no reason to
terminate. Bounded rounds can fail to settle, and then they say so and exit 3.

## The shape the mechanism cannot see, stated rather than defended against

A→B→A inside one run: two publishes that restore the original bytes between a
row's read and the reconcile pass. It needs two different minters and a
coincidence. And the digest is taken microseconds before the exec that reads the
file, so a publish landing inside *that* window is invisible to it — closing
that for real needs the binary to print the digest of the bytes it mapped, which
is `src/folio`'s to say and not Python's to infer. Both are holes, not scopes.
