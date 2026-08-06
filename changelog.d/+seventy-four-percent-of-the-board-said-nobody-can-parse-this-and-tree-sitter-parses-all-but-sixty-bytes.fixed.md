The owners lane put **134,358 B — 74% of the board — into `gap`**, a verdict
meaning *no derivation exists in the vendored `grammar.json`*, i.e. nobody in
this tree can do the work. It also said plainly that the test gating those bytes
was the one it trusted least and that exactly one hand-checked wall had ever
exercised that branch.

Tree-sitter reads the same `grammar.json`, so every one of those rows was a
falsifiable prediction. `research/joinery/adjudicate/` takes the 18
real-construct gaps `GAPS.md` prices at **106,798 B**, authors one witness each
plus an innocent control per grammar, and parses each three ways: outliner,
tree-sitter, and tree-sitter with a stub scanner that answers `false` to every
external.

**60 bytes survive.** Three verilog walls — `` `ifdef ``/`` `endif `` in a module
port list, and a part-select inside a concatenation. Of the rest, **67,214 B
(62.9%) are externals we have not seated** and **39,503 B (37.0%) are press work
that tree-sitter derives from `grammar.json` alone**; 21 B are constructs both
parsers accept, where the wall was the peel's resume context and not a construct
at all. Over the whole 181,588 B priced corpus the split moves from *9.8% ours /
74.0% upstream* to **72.6% work this tree can do / 0.03% upstream**. Measured on
two binaries built from two different trees, byte-identical both times.

Four unseated externals are now named with the token responsible:
`encapsed_string_chars` (php, 40,996 B), `_newline_before_binary_operator`
(elixir, 25,704 B across two rows that are one fix), `regex` (bash, 495 B),
`_trivia_raw_env_verbatim` (latex), `_simple_string_start` (scala).

`settled` itself is sound and unchanged — it asks whether a state holds a
completed item and errs toward withholding. What fails is the sentence bolted to
its output: *"no LR parser over this grammar takes it here."* The item set comes
from **our** LR(0) collection, so a reading our table construction lost is
indistinguishable from a reading the grammar never had — which is precisely the
`prec.left(37)`-erased-by-`prec.left(0)` splice another lane is fixing right
now. And in five of eighteen walls the refused terminal is not in the program at
all (`/` inside `"/(.*)\s.*/"`, `%` inside a format string, `[` inside a bash
regex), so the closure answers correctly about a terminal that does not exist.

Where the numbers cost something: **the instrument that lied is the wall's own
terminal.** Four of eighteen witnesses refuse a different terminal than
`GAPS.md` names, and `verilog-sized` is named after a construct that is
provably innocent — it blames `2'b00`, but `{a, b, 2'b00}` parses whole here.
The harness now carries a `wall` column comparing the two and reports the
disagreement rather than absorbing it. A second lie is one line:
`closure.py`'s `blind` set keeps only externals declared as named symbols and
silently drops the 21 declared as literals across 8 grammars — including bash's
`]`, which is the terminal `GAPS.md` row 14 names, so a wall that should have
read `scanner` read `gap`. That also rehabilitates the owners lane's
worst-scoring prediction (≥45 scanner walls, found 9): the prediction was closer
to right than the check was. The one-line widening is written down and
deliberately **not** applied, because re-labelling 170 walls mid-session moves a
board other lanes are reading.

Seven predictions were written before any of it ran: three held, two were
falsified, two cleared their floor and missed their claim. P7 (both parsers
wrong) could have been scored green by counting a narrowing found afterwards and
is reported as falsified instead.
