# press - a grammar in, tables out

Everything here runs once, at build time, and nothing here ever sees a byte of
the text you are parsing. A `grammar.json` written for tree-sitter arrives, and
what leaves is an LR automaton with an action table that `folio` can write down
and the kernel can drive. The whole folder is one function with a lot of
argument.

Two halves. The **front end** reads someone else's grammar and lowers it to the
IR in `grammar.zig`; the **builder** takes that IR and makes the automaton. They
meet only at `grammar.zig`, which is deliberately smaller than a tree-sitter
grammar: EBNF is already gone by the time the builder sees anything, so the
builder never learns what a `repeat` is.

## The front end

`import.zig` is the door. It was one file until the seam got obvious, which is
that one of these looks at a rule body and the rest look at the grammar.

| File | Role |
|---|---|
| `import.zig` | The door and the pass order. The order is the design: the census runs before anything is numbered, the numbering before anything else interns a symbol, and both before a single body is lowered. |
| `galley.zig` | The state all of them write into, and the only place `grammar.json`'s dynamic shape is narrowed. Type that has been set and not yet imposed. |
| `spelling.zig` | What a node lexes as, and the standing it lexes at. `terminalKey` is the judgement the rest of the front end rests on: whether two spellings are one terminal or two. |
| `muster.zig` | The roll call - every symbol named and numbered, over the whole rule set at once. Nobody here looks inside a body except to find the atoms in it. |
| `spread.zig` | One rule body, spread into every straight run of symbols it admits. `Alt` is the only type that crosses back out. |
| `lexeme.zig` | Rendering a `token(...)` down to one regex, since a lexical expression never reaches the parser as structure. |
| `fold.zig` | Substituting an `inline` rule away before the tables see it, which is how those names cost no conflicts. |
| `import_test.zig` | The front door's tests, every one end to end, because what the passes have to agree about is the finished grammar. |

## The builder

| File | Role |
|---|---|
| `grammar.zig` | The IR both halves meet at, and the builder that interns into it. |
| `press.zig` | The entry point the rest of the package builds tables through, and the loop that exists because LALR is not quite enough. |
| `first.zig` | Nullability and FIRST over the whole symbol space, in one fixpoint because they are one fixpoint. |
| `lr0.zig` | The canonical collection - the automaton's shape, before any question of lookahead. |
| `lalr.zig` | LALR(1) lookaheads by DeRemer-Pennello, and the action table they decide. |
| `sets.zig` | A flat matrix of equal-width bit sets, because LALR spends nearly all of its time taking unions along a relation. |
| `settle.zig` | Deciding a contested cell: what a state does when it could both read on and fold up. Six files - see below. |
| `retrace.zig` | Walking the automaton backwards, for the questions that need to know what could have been on the stack. |
| `inquest.zig` | Why a parse stopped where it did, in one sentence per verdict. Reads the wall state's row and items and names the cause; nothing here presses. |

## Settling a contested cell

`settle.zig`'s doc comment lays out a ladder of four rungs, consulted in the
order the author's declarations were meant to be. That list is also the file
seam: one rung per file, so a reader who has the ladder has the folder.

| File | Rung |
|---|---|
| `settle.zig` | The record and the entry point. `Action`, `Conflict`, `Frayed`, `Tally`, the `Case` that goes in and the `Verdict` that comes out - which is what the rest of the press, the folio, and `impose`'s comptime ledger see. |
| `column.zig` | **Rung 1** - reduction against reduction, inside one column of one state. `Folds` is the column; `keener` orders a tie the author ranked. |
| `ladder.zig` | **Rungs 2 and 3** - read against fold, by precedence and then by associativity. `Survey` is what the state's readings said; `Ladder.step` is the verdict, including the exception on rung 2 that looks like a bug and is not. |
| `attribution.zig` | **Rung 4** - whose ambiguity is left, once precedence and associativity have both declined to say. Traces a synthesized reading back to the rules that were expecting it. |
| `bench.zig` | The fixture the rungs are walked on: one state's row at a time, and the scratch that makes doing it thirty thousand times affordable. |
| `forks.zig` | Not settling at all - the index a parse loop reads off a finished verdict to know which cells it may split at. |

## Why the front end is shaped this way

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
