`shear.py` answers one question: is a grammar's `rubble` an artefact of the wall
it hit, or is it code the tables could not shape? It cuts the file at the last
byte before the refusal and re-presses the prefix. Nine of twelve grammars hand
back one root over every byte at 100% standing and zero rubble; three never
complete a top-level construct, so there is no prefix to cut.

Those three printed the *same numbers as a perfect cut*:

```
ruby      1020   21   56.5%     42  ->     0    0     0.0%     0
haskell  34240 2683   26.0%   7849  ->     0    0     0.0%     0
markdown  3304  430    5.4%    415  ->     0    0     0.0%     0
```

`cut_rubble 0` beside a whole-file `rubble` of 7,849 reads as *the cut removed
every unstructured byte*. It means **no cut was found**. `budge.py` had been
reporting `shear.Cut.cut_rubble` as `flat/open — 0 ×152` across 8 documents all
week, which is that finding stated from the other end by an instrument that
could not see what it was looking at.

`wall`, `kept`, `cut_roots`, `cut_standing` and `cut_rubble` are now
`int | None` and are `None` when the search returned no prefix, printing `—`.
`flipped` - the property that decides whether a grammar's rubble is a wall
artefact - stopped short-circuiting on `kept is None` before comparing, so a row
with no cut can no longer be counted as a flip on the strength of a zero it
never measured.

Same shape as the `damage 0` fix landing beside it and the `recall 0.00` fix
after it: a column that reads zero both when the answer is zero and when nobody
asked is two facts wearing one glyph, and the board cannot tell the reader
which one it is holding.

Measured on `joints e51716d6c`, tree `61c93c367`, 12 grammars with a wall, no
oracle - `shear` is a self-comparison and does not need one.
