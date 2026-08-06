# PREDICTION 2 — the numbers, written before the measurement that judges them

Baseline, taken with `.local/lane-seat3/before-bin` against the frozen oracle
`attest.py freeze seat3`, in its own empty `OUTLINER_WORK`:

```
grammar   built  square  askew  racked  unframed  crooked%   roots  damage
elixir    44530       1     80   17654     26756     39.9%     255    1559
latex      4061     108     28    1049      2856     26.7%      72    1185
scala     15957    6739    443    8644       131     56.9%      26    4150
bash        655     460     76       0       118     11.6%      26     413
corpus   393414  272766   3929   39110     41713     10.94%      —  133384
```

Each prediction names the number that kills it.

## 2a — elixir goes from 1 square byte to more than 30,000

`built` is 44,530 and `square` is **one byte**. 26,756 of the crooked total is
the single missing top-level frame — the whole `defmodule`, which cannot be
built while the parse ends in 255 roots. Seat the binary-operator arm and the
wall at 17,006 goes; the file should reach one root and that frame should appear.

**Predicted:** elixir `square` ≥ 30,000, `roots` ≤ 3, `unframed` ≤ 1,000,
`damage` ≤ 200.

**Dies if:** `square` lands under 20,000, or `roots` stays above 10.

**Deliberately not predicted:** that racked goes to zero. Prediction 1d says the
`defp … do` attachment defect survives this, so I expect a few thousand racked
bytes to remain and I am not counting them as a failure.

## 2b — corpus square passes 300,000 and no other grammar moves a byte

php's lane moved 205,583 → 272,766 and nothing else shifted. The same discipline
applies: elixir + latex are the only grammars whose casts change, so every other
row's folio should come out byte-identical between the two arms.

**Predicted:** corpus `square` ≥ 305,000; crooked share of built falls below
9%; the 28 grammars other than elixir and latex are unchanged in every rack
column, and their minted folios are byte-identical across the two work
directories.

**Dies if:** any third grammar's `square` moves at all — that is a widened
roster or a leaked mark, and it is the exact failure the strengthened pin in
`scanner_test.zig` is being written for.

## 2c — latex's `\iffalse … \fi` is the largest single piece, and it is one member

`ltnews01.tex` is 5,246 bytes. Bytes 2–992 are one `\iffalse … \fi` block —
**990 bytes, 18.9% of the file** — and that is `_trivia_raw_fi`, the one member
of the twelve whose close is a command name rather than an `\end{…}`. The two
verbatim bodies are 51 and 76 bytes.

So the member that needs the *extra* rule (`is_command_name`) is worth thirteen
times the two that only need the string widening. If I had implemented the string
close and stopped, I would have collected 127 bytes and reported a family seated.

**Predicted:** latex `square` ≥ 3,000, `unframed` ≤ 300, `damage` ≤ 250, and the
wall at 3,057 is gone.

**Dies if:** latex `square` stays under 1,000, or the parse still walls inside a
verbatim body.

## 2d — widening the close costs the single-byte families nothing

`Mark.shut` is read in four places: `marrow.matter` (elixir), `marrow.quoted`
(julia), `marrow.encapsed` (php) and `outside.shutOf`, which keys a family's own
closing terminal *by that byte*. Turning it into a slice would make three
per-byte comparisons a `memcmp` and make `shutOf` compare strings.

So the widening keeps `shut: u8` as the close's **first** byte and adds a `tail`
for the rest. The three existing walks never read `tail`; `shutOf` is untouched.

**Predicted:** php, julia and elixir's quoted content are byte-identical in every
rack column after the widening — measured, not asserted.

**Dies if:** any of the three moves.

## 2e — bash gains under 120 bytes and its wall does not move

**Predicted:** bash `square` ≤ 580, wall still `unexpected [ at 565` attributed
to `_concat`.

**Dies if:** the wall moves, which would mean I mis-derived which terminal was
doing the work — the same error the php lane made about bash, one layer down.

## 2f — the two guard holes, and what closing them has to prove

Inherited open, from the php lane attacking its own work:

1. `scanner_test.zig`'s roster pin **compares names only**, so a member with the
   right name and the wrong `mark` passes. Widening latex's close is exactly that
   failure mode. **Predicted:** rendering each claim as `name shut=… wide=… …`
   and pinning the rendering makes a wrong mark fail. I will prove it by
   corrupting one mark and watching the test go red.

2. **A failing specimen has no number below zero to fall to.** The php lane's
   guard specimen was already 0/7 when it tried to break its own build.
   **Predicted:** every specimen I add passes on the seated build *first*, and
   then fails when I break the thing it guards. Both directions run, both
   reported — a specimen that only ever passes is not a falsifier, and one that
   never passes is not either.

## 2g — the folio hazard, obeyed rather than argued with

`tool/order.py::miss` keys freshness on a path plus an mtime, so two pinned
binaries sharing an `OUTLINER_WORK` read whichever folio was written last, and
the error is always flattering because two runs of the same table agree.

**Predicted:** each arm gets its own directory, started empty, and the 28
unchanged grammars' folios come out byte-identical between them while elixir's
and latex's differ. If they *all* come out identical, the arms did not see
different binaries and every number above is void.
