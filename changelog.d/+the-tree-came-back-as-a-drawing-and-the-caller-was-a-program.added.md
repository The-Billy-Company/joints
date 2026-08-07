`parse` rendered its tree one way: indented lines for a person, s-expressions
under `--sexp` for a person who grew up on tree-sitter. Both are drawings. A
program consuming outliner - an editor plugin, a harness, an agent - had to
re-parse the drawing, which is a parser feeding people who own parsers a
format that needs one.

`parse --json` now emits one JSON object per file: the language it was parsed
as, the path, how the parse stopped and where, the mend/skip/supply counts,
the scars when recovery ran, the soundness survey, and the tree itself as
nested nodes carrying name, span, field, and children. String escaping is the
JSON spec's, not a hope that node names stay ASCII. `--json` composes with
`--all` and `--language`, and refuses `--ranges`/`--scars` loudly rather than
silently emitting a shape nobody documented - those are views of the human
render, and a flag that changes nothing should say so rather than pass.
