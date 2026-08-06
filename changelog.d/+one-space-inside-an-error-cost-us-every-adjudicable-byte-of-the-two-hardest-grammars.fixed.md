`tree-sitter parse --cst` does not indent two spaces a level. It indents two
spaces a level **plus one further space for a node that sits inside an error
subtree without carrying an error itself** - `in_error && !node.has_error()` in
`cst_render_node`, `crates/cli/src/parse.rs` at 0.26.11 - and its range prefix is
padded to a width the render never states. Our reader took the body column as
pure indentation under a whole-render `shift` of one or zero, so a clean node
inside an error read a level too deep and the bulleted **sibling** after it read
a level too shallow and was adopted by the node above it. No constant can undo a
per-row perturbation. `reconciled` tried both readings, agreed with neither XML,
and refused the grammar - which `rack` filed as `unjudged` on every built byte.

`picorv32.v` has both failures in one file, which is why no constant could read
it. At CST rows 3250-3253 a bulleted `conditional_statement` stands at column 44
and its three clean children at 47, three past their parent instead of two; at
row 133 `•module_ansi_header` is outside any error region entirely, where a
`shift` of one pushes it a level too deep under the `module_header` it should
follow. `indents()` now inverts the CLI's arithmetic rather than guessing at it:
every row whose padding was not clamped states `total_width` outright, so the
smallest width any row implies is the real one, and clamping can only raise a
row's padding. With the prefix subtracted the indent is even and the extra space
is the odd bit, so integer division drops it - `(column - 20) // 2` is the depth
for all 48,883 verilog rows. **The bullet costs zero columns, in every render,
always**; it is written after the indent, so the `shift` was never the bullet.

Second, independent defect: `--cst` prints an inserted anonymous token as
`MISSING: "kind"`, `cst_tree` marks it named so a caller counting repairs can
see it, and `named_only()` therefore handed the comparison a node the XML has no
element for. Twenty-one inserted semicolons in verilog.

| | before | after |
|---|---|---|
| corpus unjudged | 35,837 of 396,158 built - **9.05%** | 5,564 - **1.40%** |
| verilog | 30,720 - **100% of built** | 4,293 - 14.0% |
| sql | 3,967 - **100% of built** | 121 - 3.1% |

Swept over all thirty: the oracle refused exactly the two rows where `cst_tree`
reported `hurt`, and read the other 27 identically under both readers. That
biconditional is the diagnosis restated as a measurement. `built` is unchanged
to the byte on every row - no parse moved - and `rack verify` holds 18 of 19
with byte-identical output before and after.

**The reader's own gate could not have caught this.** `differential.py spans`
had eighteen fixtures and **not one of them contained a syntax error**, while
the perturbation only exists inside an error subtree. Five error shapes now live
in `research/joinery/spans/errors/`, a reconciliation refusal is a `BROKE` there
rather than a shrug, and each fixture isolates one defect: pointing the shipped
gate at the pre-fix reader breaks 2, at columns-only breaks 1, at
`named_only`-only breaks the other 1.

`indents()` inverts one version's undocumented implementation. If the CLI
changes its indent rule this reader is wrong again and `spans` will say so, on
five shapes, loudly. That is the trade.
