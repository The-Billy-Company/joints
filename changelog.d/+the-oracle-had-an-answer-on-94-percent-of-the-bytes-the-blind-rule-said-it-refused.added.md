Verilog's 4,644 `veiled` bytes — the whole of the corpus's largest damage row's
un-leafed population, priced at zero **by default** because the oracle was said
to decline — re-price to **4,373 `slack` by verdict and a bound of 271**.
`research/joinery/judge/` seats the judges and holds the measurement.

**The oracle was never silent.** Tree-sitter's verilog grammar fails to *close*
the top-level parse and wraps `picorv32.v` in one `ERROR` spanning all 94,657
bytes. `plumb.hurt()` taints by ERROR **ancestry**, so every byte inherits that
single node's verdict and `rack.py`'s `veiled` branch refuses the file. Beneath
that root tree-sitter built **48,883 nodes and 17,290 leaves**, and its 333
recovery nodes (266 `ERROR`, 52 `MISSING ;`, 10 `MISSING ++`, 5 `MISSING end`)
*minus the root* swallow **12,526 B — 13.2%**. It never crashed, never timed
out, never declined. The root `ERROR` is a label on a file it parsed.

Asked by **innermost cover** instead of ancestry — the node `plumb.paint`
already computes — the same oracle answers on **4,373 of 4,644 (94.2%)** with a
construct it built and left un-leafed exactly as we did: `named_parameter_assignment`
644, `string_literal` 480, `operator_assignment` 356, `expression` 316,
`seq_block` 229. On **3,430** of those both trees name the construct with the
identical string. Not silence — agreement. **The bound is 271 bytes, 0.29% of
the file, every one of them whitespace**, in 185 runs.

**Two independent parsers corroborate, and disagree with each other on
purpose.** [slang](https://github.com/MikePopoloski/slang) (MIT, `pip install
pyslang`) parses the file with **zero syntax errors** — one
`MisleadingIndentation` lint — so the file is valid Verilog and the whole-file
`ERROR` is tree-sitter's, not the corpus's. [Verible](https://github.com/chipsalliance/verible)
(Apache-2.0, prebuilt 7.9 MB binary, byte offsets in `--export_json
--printrawtokens`) lexes the text as written and stands a token on **0** of the
271 bounded bytes. It charges 590 of the 4,373 freed — and all 590 are bytes
both trees put under the *same* construct and neither leafs (`string_literal`
480/480, `attribute_instance` 40/40, `expression` 24/24): Verible emits one
token per string literal where tree-sitter and we both decompose it into
quote-leaves around a bare body. A convention, not a defect. **`warp` stays 0
by verdict from three parsers**, and `owed = damage + warp = 62,180` is
unchanged — but it is now a measurement instead of a default.

**No second oracle was seated, and the reason is that it would buy nothing.**
`attest.rule()` digests the transitive closure of the identity rule; the verdict
that moved this row came from the oracle already seated, read at the right
distance. Verible and slang settle two facts that do not vary with a tree, and
re-checking a constant on every board is an identity cost for nothing. If it
changes, seat Verible — digest `66e9c3c6…d422d27`, `v0.0-4121-gc2ec3416`.
Icarus Verilog (a simulator; no byte-offset tree) and Surelog/UHDM (heavy CMake,
post-elaboration) were weighed and rejected.

**And the premise this lane was sent to prove is false.** Against Verible's
74,194 token bytes, tree-sitter stands a leaf on **98.8%** and joints on
**60.5%** (23,497 nodes / 9,394 leaves against 48,883 / 17,290). Bytes we leaf
and tree-sitter does not, over the whole file: **0**. Our verilog leaf set is a
strict subset of theirs, 44,911 ⊂ 73,357. **Verilog is not a place we beat
tree-sitter; it is the widest margin against us on the board**, and emitting no
whole-file `ERROR` is a difference in what each tool does when it gives up, not
a win — tree-sitter did not give up.

Read on arm `judgelane`, binary from tree `1d7a512f8`, repo `f7ba40004+145`,
oracle `eacad4bfc` / tree-sitter 0.26.11, verible `v0.0-4121-gc2ec3416`,
pyslang 11.0.0. `damage 62,180` reproduced to the byte on this arm.

Three things to distrust. **The 271 is a floor on ignorance, not a ceiling**: a
byte whose innermost cover is a *healthy* node tree-sitter built in the wrong
place counts as adjudicated `slack`, and on the 943 bytes where the two trees
name that cover differently I am trusting tree-sitter and have not checked it.
**The fix is a rule change demonstrated on one row** — ancestry-vs-innermost
differs wherever an oracle tree carries a wide `ERROR`, and I have not swept the
corpus for other columns reading `plumb.hurt()`; `plumb.py` and `rack.py` are
deliberately untouched, both being live under other lanes. **And verilog is one
94 KB file**, so every percentage here is a statement about `picorv32.v` and the
word "verilog" is doing more work than it has earned.
