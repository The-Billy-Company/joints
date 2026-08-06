# mends — the field that read 0 on every row anyone cared about

`stamp.ask().mends` reported **0 on all seventeen grammars that mend** and
correctly on the thirteen that do not. Kotlin's 142, verilog's 2,109 and php's 1
all came back zero, and `tool/walls.py`'s `voice` - mends per distinct wall -
divided by it, so every walled grammar's tail read as pure depth with no
repetition in it at all.

[RESULT-1-verdict.md](RESULT-1-verdict.md) is the repair and its scoring;
[PREDICTION-1-verdict.md](PREDICTION-1-verdict.md) was written first and two of
its four predictions failed.

**The cause.** `verdict()` took the last non-blank stderr line. `inquest` prints
*after* the stop on every walled row, prefixed with the grammar name rather than
the source path, so the reader returned inquest's prose - and `outcome()`
derives `kind`, `reach`, `roots`, `at` and `wall` from that one string, so five
fields moved together. `BLIND` and `UNSOUND` search the whole stderr with a
regex and were right the whole time.

**The repair.** Find the line the **source** names, by searching in reverse
rather than counting from either end. Corpus-wide, both rules run over the same
captured stderr from one pinned binary: `mends` 0 -> 4,551, `reach` 100,399 ->
507,850 bytes, `roots` 30 -> 8,435, kinds `{state: 15, whole: 12, other: 3}` ->
`{mended: 17, whole: 12, other: 1}`.

**Why the gate did not catch it.** `stamp.py --probe` had no fixture with an
inquest line under the verdict, so it passed green against the broken reader.
It now runs all **three** generations of the rule side by side over 20 shapes
and prints how many each prior rule gets wrong - 6 for the original `rsplit`,
5 for the last-line rule this replaces. The two dead rules are kept as named
functions for exactly that purpose; a gate that cannot show itself biting is a
gate nobody can trust.
