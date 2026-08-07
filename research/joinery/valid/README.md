# valid input we stop on

`broken/` asks what happens when the input is wrong. This folder asks the
harder question: **what perfectly ordinary code do we refuse?**

It exists because of one fixture that turned out to be misfiled. I wrote
`broken/javascript/dangling-keyword.js` - a bare `return` at program level -
expecting it to be a break. tree-sitter-javascript accepts it whole, with no
`ERROR` node anywhere. So it was never a recovery finding; it was an ordinary
differential finding in a grammar this dossier calls byte-exact, and the corpus
had simply never thought to ask.

## The cause, and it is one terminal

`_automatic_semicolon`, the first of the eight externals javascript declares.
JavaScript does not require a `;`; the spec inserts one at a newline when the
next token cannot continue the statement, and tree-sitter's scanner emits that
insertion as a **zero-width** external token. We are blind to it, so every
place a real program leans on it, we stop.

Reduced to four lines, it is not about `return` at all:

| probe | joints |
|---|---|
| `const a = 1;` / `const b = 2;` | accepted, 1 root |
| `const a = 1` / `const b = 2` | stray byte at 12 |
| `const a = 1;` / `return` / `const b = 2;` | stray byte at 26 |
| `const a = 1;` / `return;` / `const b = 2;` | accepted, 1 root |

Byte 12 is exactly where the first missing `;` would go. Put the semicolon in
and the same file is accepted. tree-sitter's own `-x` output for the
semicolon-free pair is two clean `lexical_declaration` nodes and no `;`
anywhere, because a zero-width token leaves no bytes to print.

## What that costs the headline

`ledger.js` and `ledger.ts` are byte-exact at 324 and 442 nodes, and they earn
it - but every statement in both files ends in an explicit semicolon. So the
honest claim is **byte-exact on semicolon-terminated JavaScript**, and the
qualifier is not a small one; a large fraction of real-world JS omits them by
house style. Routed to the externals lane, where it joins rust's nested
`block_comment` and ocaml's nested comment as the same missing feature rather
than three problems.

## Adding to it

One file per finding, named after the construct rather than the grammar, under
the language it is written in. The bar for entry is the bar this folder was
born from: **tree-sitter accepts it and we do not**, on input a person would
write on purpose.
