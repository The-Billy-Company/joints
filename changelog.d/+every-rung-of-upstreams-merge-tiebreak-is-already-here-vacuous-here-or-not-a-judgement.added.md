`RESULT-2-reach.md` closed by naming the rung that would pay: a structural
tie-break in `Reading.beats`, which tree-sitter's `ts_parser__condense_stack`
has and we don't. It doesn't have one. Read at v0.26.11,
`ts_parser__condense_stack` (`parser.c:1772`) compares in-error-ness, error cost
and dynamic precedence through `ts_parser__compare_versions` (`parser.c:246`)
and nothing else, and when they tie it returns `ErrorComparisonNone` and
**merges** — `ts_stack_merge` (`stack.c:708`) splices both derivations onto one
node and keeps them. Upstream's answer to a tie is not to choose, and declining
the merge is already priced here at −57,627 bytes.

The structural comparison is a layer down, in `ts_parser__select_tree`
(`parser.c:872`) into `ts_subtree_compare` (`subtree.c:596`): symbol, then child
count, then recurse, first difference wins. Of its rungs, error cost is vacuous
here because `mended` fires on a refusal of the whole parse, so two readings
standing at a merge have taken the same mends; symbol is vacuous because
`twinned` pins the state chain; and what is left is a first-difference
lexicographic order whose outcome upstream itself logs as `select_earlier` — a
rule for naming a determinate representative, which `rank` already is.

Built anyway, in both directions the child-count rung admits, as
`Reading.folds`: reductions taken since `roost` last put the parse back to one
reading, copied at the fork like `heft`, sitting below `heft` and above `rank`.
Two isolation pairs, each pin with its own work dir and oracle seat, each pair's
`world.json` differing in exactly `src/kernel/quire/gather.zig`. Preferring the
smaller derivation costs 46 square bytes and 1,104 built (python off 100% trued,
verilog −167). Preferring the larger — the faithful reading, since fewer
immediate children means *more* nesting — costs 609 square (elixir −651 against
kotlin +53) and drops markdown from a small tree to `graded void`. Twenty-two of
thirty rows never move, and cpp is bit-identical both ways, so heft still leads
and its seven decided merges are untouched.

Nothing shipped but the finding. `research/joinery/arity/RESULT-3-structure.md`
has both boards, the citations, and the three controls — including the one that
refused a cross-tree comparison that would otherwise have published a
4,368-byte zig regression four sibling lanes caused.
