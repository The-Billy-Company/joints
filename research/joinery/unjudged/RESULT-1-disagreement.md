# Result 1 - what the disagreement actually was

Scores [`PREDICTION-1-disagreement.md`](PREDICTION-1-disagreement.md), written
before anything was run against verilog.

## The finding, in one paragraph

`tree-sitter parse --cst` does **not** indent two spaces a level. It indents two
spaces a level **plus one further space for any node that sits inside an error
subtree without carrying an error itself**. Our reader took the body column as
pure indentation, so that one space made a clean node read a level deeper than
it is - and the bulleted sibling that followed it read a level shallower, and
got adopted by the node above it. No whole-render `shift` can undo a per-row
perturbation, which is why `reconciled` tried both of its readings and refused.

That is one of two defects. The second is smaller and independent: `--cst`
prints an inserted anonymous token as `MISSING: "kind"`, `-x` has no element for
it, and `cst_tree` marks it named so a caller counting repairs can see it - so
it was in `named_only()`, facing an XML that could never have it. Twenty-one
inserted semicolons in verilog, one inserted `]` in the fixture below.

## The witness

Not inferred from the output. Read out of the printer that wrote it -
`crates/cli/src/parse.rs` at `v0.26.11`, the version `differential.py oracle`
reports, in `cst_render_node`:

```rust
write!(out, "{}{}", "  ".repeat(indent_level),
       if in_error && !node.has_error() { " " } else { "" })?;
...
if node.has_error() || node.is_error() { write!(out, "{}", paint(..., "•"))?; }
```

Three things fall out of those five lines, and all three contradict what the
reader believed:

1. **The bullet costs zero columns.** It is written *after* the indent and after
   any `field:` and its space, so it is part of the body. Every bulleted row in
   every render stands at its true indentation. The `shift` of one was never the
   bullet - it was standing in for the extra space that a bulleted node is the
   one kind of node that never gets, which is why it read correctly inside an
   error region and wrongly outside one.
2. **The extra space is `in_error && !has_error`,** and `in_error` is only ever
   set when descending to a first child that has an error, and only cleared
   climbing back out to a parent that has none. So it is sticky, per-row, and a
   function of the tree rather than of the render.
3. **The range prefix is not a fixed width.** `render_node_range` pads each
   position to `max(1, total_width - ilog10(row) - ilog10(col))`, so the column
   the body starts at is `prefix + 2*depth + extra` with a `prefix` the CLI
   never states. `indents()` now inverts that arithmetic: every row that was not
   clamped states `total_width` outright, so the smallest value any row implies
   is it, and clamping can only ever raise a row's padding.

With the prefix subtracted, indentation is even and the extra space is the odd
bit, so integer division drops it. On verilog: `total_width = 6`, prefix 20, and
`(column - 20) // 2` is the depth for all 48,883 rows.

### The row that shows it

`picorv32.v`, CST rows 3250-3253, columns 44 and 47:

```text
206:2  - 302:4                            •conditional_statement
206:2  - 206:4                               "if"
206:5  - 206:6                               "("
206:6  - 206:20                              cond_predicate
```

`conditional_statement` carries an error, so no extra space: `44 = 20 + 2*12`.
Its three children do not, and each got one: `47 = 20 + 2*13 + 1`. Read as
columns, the children sit three past their parent instead of two, and the next
bulleted node - which is a *sibling* of the parent - lands between the two
levels and is re-parented. Under `shift = 1` the same file has the opposite
failure at row 133, where `•module_ansi_header` is outside any error region and
`shift` pushes it a level too deep, under the `module_header` it should follow.

One file, both failures, which is exactly why no constant could read it.

### Why only two grammars

The extra space only exists inside an error subtree, so a grammar whose oracle
tree is clean cannot trip either defect. Swept over all 30: the oracle refused
exactly the two rows where `cst_tree` reported `hurt` - verilog and sql - and
read the other 27 under both the old reader and the new. That biconditional is
the diagnosis restated as a measurement.

## The falsifier

Five error shapes now live in [`../spans/errors/`](../spans/errors) and run in
`differential.py spans` on every invocation, where a refusal is now a `BROKE`
rather than a shrug. Pointing the shipped gate at the pre-fix reader:

| reader | broke | which |
|---|---|---|
| as shipped | 0 | — |
| pre-fix, both defects | 2 | `01-error-under-a-clean-parent`, `03-missing-token-under-a-named-parent` |
| pre-fix columns only | 1 | `01-error-under-a-clean-parent` |
| pre-fix `named_only` only | 1 | `03-missing-token-under-a-named-parent` |

Each fixture catches exactly one defect and neither catches the other, so the
set is not one shape counted twice. `01` is three lines of javascript:

```js
function m() {
  for (let i = 0; i < 10 i++) {}
}
```

The eighteen span shapes that were already here are all byte-exact javascript.
That is the whole reason this survived: **not one fixture in the reader's own
gate had an error in it**, and the perturbation only exists inside an error.

## Scoring

Seven of nine held, one was right about the conclusion and wrong about the
mechanism, and one was three claims out of four.

| | prediction | verdict |
|---|---|---|
| P1.1 | the refusal carries `(the tree has errors in it)` | **held** - and it is the discriminator, not a detail |
| P1.2 | the bullet column varies within one render; no global shift can work | **half** - see below |
| P1.3 | our reader, not the oracle | **held** |
| P1.4 | not truncation / anonymous nodes / aliases / a partial form | **3 of 4** - see below |
| P1.5 | first divergence deep and local, subtree below intact | **held** - CST row 3253 of 48,883, depth 12 |
| P1.6 | not a genuine property of the oracle | **held** |
| P1.7 | exactly one more grammar in this state, others refusing for other reasons | **held** - sql; yaml refuses for having nothing to parse |
| P1.8 | `square < 50%` of verilog's built, `unframed` large | **held** - 2.0% square, 41% unframed |
| P1.9 | damage survives and is uninformative rather than wrong | **held** - 63,937 exactly |

**P1.2 was the load-bearing prediction and it named the wrong mechanism.** Its
conclusion - that no single `shift` can read this tree, and that the
whole-render assumption is what fails - is right, and it is the half that
mattered for knowing the loop could not be fixed by adding values to it. But the
reason is not that bullets stand at two different columns. Bullets stand at one
column in every render, in every tree, always. It is the *unbulleted* rows that
move, and they move in the other direction. I predicted a varying bullet because
`cst_tree`'s own docstring had already concluded that, and I inherited its frame
instead of reading the printer. The printer is a `curl` away and settled it in
one read; four hours of column arithmetic did not.

**P1.4 lost the claim it was least sure of, and lost it squarely.** "Not an
anonymous or extra-node difference - `named_only()` already drops every
anonymous node before the comparison" is false, and it is false for a reason the
prediction could have found by reading four lines: `cst_tree` promotes an
anonymous `MISSING` placeholder to named on purpose, so `named_only()` never had
the chance to drop it. Half of this bug *is* an anonymous-node difference. The
other three sub-claims held.

## What is not claimed

The extra space is documented nowhere in the tree-sitter CLI and is not part of
any stated contract, so `indents()` is an inversion of one version's
implementation, pinned at `0.26.11`. If the CLI changes its indent rule, this
reader is wrong again - and `spans` will say so, on five shapes, loudly, which
is the whole point of the previous section.
