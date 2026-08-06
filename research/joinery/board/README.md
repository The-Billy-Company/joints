# board — the instrument that routes the other instruments

`tool/standing.py` is the board every lane on this parser gets dispatched off.
It decomposes the corpus into four buckets that total it exactly — `built +
orphan + rubble + spoil = 526,798` — prints `standing = built / size` as the
headline, and offered `unbound = rubble + spoil` as the priority column.

**`unbound` excludes `orphan`, and dispatches came off `unbound`.** That is the
whole finding. The exclusion is right as a definition and wrong as a work order,
because an orphan byte is still a byte the tree failed to place. The two columns
disagreed about who was worst by seven places, and a day of dispatches went out
on the wrong one.

This dossier fixes the ranking without moving anything a previous measurement
used.

## Files

| File | What |
|---|---|
| `PREDICTION-1-order.md` | Five predictions, written against the baseline board before anything was built. Names the measurement that falsifies each. |
| `RESULT-1-order.md` | Four held, **P2 failed**. The corrected ranking, the gate stated in the board's own columns, and why the guard I shipped is not the guard I predicted. |
| `RESULT-2-flatter.md` | The flattering number inside this fix, and the one in the brief that sent me. |
| `probe.py` | P1, P2, P4 — reads a board JSON, re-asks `stamp` for mend counts, ranks both ways. |
| `gameable.py` | P5 — verilog under `--mend=fell` against `--mend=keep`. |

Both probes take a board JSON so they can be re-pointed at any pin. `probe.py
.local/lane-board/base.json` reproduces every number in `RESULT-1`.

## What changed on the board

`damage = size − built = orphan + rubble + spoil`, as a column and a `--damage`
sort. It **redefines nothing** — a rollup of three of the four buckets, and
`damage / size` is exactly `1 − standing` to the eighth digit. `unbound` still
means `rubble + spoil`; `standing` still reads 67.37%.

`most` names which bucket holds more than half the damage, or `mixed` when none
does. It is arithmetic on three columns and reads no verdict text, because
`inquest`'s stand-in name is a guess that has been wrong twice. The footer
groups by it, which prints the blind-external pattern a lane previously had to
find by hand.

Three `CHECK` lines carry the orphan mechanism's facts, and they now ride the
`--json` output as well as the terminal:

- **the gate is binary** — `leaves == 0` ⟺ `roots ≤ 1`, on 30 of 30. It is `≤`
  and not `==` because yaml builds no tree and hands back **zero** roots, so
  "zero mends" has two meanings the stderr framing cannot separate.
- **and not vacuous** — 13 rows on one side, 17 on the other, so the
  biconditional had a counterexample available and did not find one.
- **the magnitude is graded** — ranking the mending rows by `roots` puts scala
  10 places from where `damage` does, at a 26× spread in bytes-per-root. This
  asks whether the two *orders* disagree rather than whether a spread clears a
  threshold; see `RESULT-1` for why the threshold version was a false red.

## What is not here

**No mend count.** `stamp.ask().mends` reads 0 on all 17 rows that mend —
`verdict()` takes the last non-blank stderr line, and a walled grammar's last
line is `inquest`'s, not the stop line. The board states the gate in `roots` and
`leaves` instead, which come off the same tree as `built`. `tool/stamp.py`
belongs to another lane; the correction is one line and is written down in
`RESULT-1`.

**No classifier over the stand-in terminal name.** Recorded in the prediction
file in advance, along with what would have counted as that decision failing.

## Reading the board without being misled

- `damage` is `size − built`, so it inherits every way `built` can rise by
  describing **less**. `--mend=keep` buys 25,457 bytes of it on `picorv32.v`
  while printing 9,550 fewer nodes. **Only `describes` catches that** — not
  `covered`, not `spoil`, not `rubble`, not bare leaves. Read the two together.
- `damage` and `worst share` are both the work order and they disagree.
  markdown is 2nd by share and 9th by bytes; elixir is 96.6% standing and still
  carries 1,559 bytes. The board says so in words rather than leaving it to
  whoever reads the columns.
- The verdict tail is a **location, not a diagnosis**. Its owner word is
  trustworthy; the bracketed stand-in name is a guess. Nothing on the board
  branches on either.
