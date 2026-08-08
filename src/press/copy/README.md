# copy - somebody else's grammar, lowered

*Copy* is the printer's word for the manuscript that arrives: not yours, not
finished, and the whole job starts by reading it. What arrives here is a
`grammar.json` written for tree-sitter, and what leaves is the IR in
`grammar.zig`. Three hundred maintained grammars get imported this way and never
rewritten, which is the entire go-to-market.

This is the floor of the press, and it is a floor in the load-bearing sense:
**nothing in this directory imports anything outside it.** No automaton, no
conflict machine, not even the door above. That is checkable rather than
aspirational - `charter.zone` judges it - and it is why the front end can be read
without holding the rest of the press in your head.

By the time anything leaves, EBNF is gone. The builder above never learns what a
`repeat` is.

| File | Role |
|---|---|
| `import.zig` | The door and the pass order. The order *is* the design: the census runs before anything is numbered, the numbering before anything interns a symbol, and both before a single body is lowered. |
| `grammar.zig` | The IR everything above meets at, and the builder that interns into it. Deliberately smaller than a tree-sitter grammar. |
| `galley.zig` | The state every pass writes into, and the only place `grammar.json`'s dynamic shape is narrowed. Type that has been set and not yet imposed. |
| `spelling.zig` | What a node lexes as, and the standing it lexes at. `terminalKey` is the judgement the rest of the front end rests on: whether two spellings are one terminal or two. |
| `muster.zig` | The roll call - every symbol named and numbered, over the whole rule set at once. Nobody here looks inside a body except to find the atoms in it. |
| `spread.zig` | One rule body, spread into every straight run of symbols it admits. `Alt` is the only type that crosses back out. |
| `lexeme.zig` | Rendering a `token(...)` down to one regex, since a lexical expression never reaches the parser as structure. |
| `fold.zig` | Substituting an `inline` rule away before the tables see it, which is how those names cost no conflicts. |
| `import_test.zig` | The front door's tests, every one end to end, because what the passes have to agree about is the finished grammar. |

## Why the shape is this way

A terminal's identity is two facts, not one - the bytes it matches and the
standing it matches them under - and three different passes have to answer that
question the same way or a rule and an inline literal spelling the same bytes
come apart. That is the whole reason `spelling.zig` exists as its own module
rather than as a handful of helpers wherever they were first needed. `muster`
asks it while counting claims and again while numbering; `spread` asks it while
lowering a body; and the census turns the answer into `wrapping`, which decides
whether a rule *is* a token or merely derives one.

Symbol numbering is load-bearing for the same reason. The lowest surviving id is
the last rung of the lexical tie-break, so the order terminals are interned in
decides which of two tokens matching the same bytes the lexer hands back. That
is why the numbering is a pass of its own rather than a side effect of whoever
interns first.
