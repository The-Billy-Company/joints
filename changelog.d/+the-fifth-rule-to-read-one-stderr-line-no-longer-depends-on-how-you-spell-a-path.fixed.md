`stamp.behind()` found the binary's verdict by matching `outliner: <source>: ` with
`<source>` spelled **exactly** as the caller spelled it. Every caller today passes
the same object it invoked the binary with, so it holds - and nothing made it hold
tomorrow. A caller that resolved the path first, or passed `tool/./stamp.py` where
it invoked `tool/stamp.py`, got `None` back, and `verdict()` fell through to the
next stderr line, which is an `inquest` line. That is the same defect this project
has now shipped three times in four attempts at reading one stderr line, and the
last repair took `mends` 0 to 4,551 and `reach` 19.1% to 96.4% of the corpus, so
the cost of it re-arming quietly is known rather than hypothetical.

`behind()` now tries the verbatim match first - it is the common case and free -
and only when that misses does it walk the line's `: ` boundaries comparing each
candidate path against the source **resolved**: `realpath` when the path exists,
`abspath` when it does not, `normpath` if the filesystem refuses to answer. So
`tool/stamp.py`, `tool/./stamp.py`, `tool//stamp.py` and the absolute spelling all
read the same verdict, and two genuinely different files do not.

The reason the row pinning this existed rather than a fix is that the gate had no
fixture with the failure shape - `STOPS` never carried a differently-spelled path,
so it certified the behaviour it was pinning. It now carries four, plus a control
where `./a.md` and `/a.md` are different files and must stay different. And
`verdict()`/`outcome()` take an optional reader so `stops()` can run the **old**
verbatim-only rule beside the new one and print a `verbatim` column: the fixtures
the fix saves show `wrong` in that column and are counted, so the fixture proves
the repair rather than merely coexisting with it.

The `path spelled differently` row that pinned the hazard **flips** rather than
disappearing: it used to assert that a differently-spelled path returns nothing
and falls through, and now asserts it reads the stop. That is a pinned
expectation being inverted, which is a thing to say out loud rather than notice
in a diff - the pin was recording a defect, not protecting a contract, and the
row that keeps this from becoming "trust any prefix" is the new one where two
genuinely different files must still compare unequal.

`stamp.py` is shared and its owner of record is another lane, so this changes one
function's path comparison and the fixtures that exercise it - no signature that
any caller passes positionally, no change to `Outcome`, and the new `reader`
parameter defaults to the behaviour every existing caller already gets.
