# kernel/lex — M1, bytes to tokens

The claim: **a lexer is not a program to generate, it is one anchored
longest-match question asked once per token.** Every terminal a grammar
declares is a regex (a literal is the degenerate case), irregex answers exactly
that question, and so this folder contains no automaton of its own.

| File | Role |
|---|---|
| `scanner.zig` | The grammar's terminals as one irregex slate, the tie-break, the extras skip, and the list of terminals nothing here can recognize. |
| `admit.zig` | What the walk is allowed to consider: the precedence tiers, the immediacy cut, and the per-state permission set shaped like them. |
| `outside.zig` | What an external scanner would have produced, declared as data: a spelling plus its lexical standing, keyed by the terminal's own name. |
| `scanner_test.zig` | Longest-wins, keyword-beats-pattern, extras, strays, blindness — and the measured trap that a real grammar sets for an unconditional slate. |

## What is here and what is deliberately elsewhere

irregex owns everything that is a property of *automata*: grouping a slate past
one 64-bit attribution mask, admitting patterns by bisection so one unusable
token body is charged to itself rather than to the other hundred and fifty, and
narrowing the slate to a permitted subset during the walk.

This folder owns what is a property of *this grammar*:

- **Which terminals form the slate**, and the map back from a pattern ordinal
  to the symbol that owns it.
- **The tie-break.** `if` and `[a-z]+` both reach two bytes, and which one the
  language means is a fact about the language. tree-sitter's rule — a string
  beats a pattern of equal length, earlier declaration otherwise — is the rule
  here, and it is expressible exactly because the IR kept `.literal` and
  `.regex` apart. Two floors sit under it: a stand-in for an external scanner
  loses to the grammar's own spelling of the same bytes, and an extra loses to
  everything, because an extra is what steps over bytes nobody asked for.
- **The keyword rule.** `Grammar.word` names the terminal a keyword is spelled
  as before anybody knows it is a keyword. When that terminal wins a tie the
  language almost always meant the other one, so the pick runs again with the
  word and every stand-in withheld. C is the case it was written for: `int`
  reaches three bytes as both `primitive_type` and `identifier`, and
  declaration order is a coincidence rather than an answer.
- **What we are blind to.** External scanners and token bodies irregex
  declined, named once at compile rather than discovered mid-file as a
  mysterious stray byte.
- **What the skip threw away.** An extra is stepped over, but a comment is a
  node on the tree and after the skip nobody can tell where it was.
  `nextKeeping` is `next`'s walk with the extras handed back instead of
  dropped — only the ones that emit a node, so whitespace stays invisible and
  a caller never has to re-decide what the tree keeps.

## Externals, without a language name in the code

Ten of the eleven grammars in `upstream/` hand terminals to a C function we do
not link and never will. Read those scanners, though, and most of what they do
is **recognize a spelling the DSL could not host** — bash's `variable_name` is
`[a-zA-Z_]\w*`, ruby's `simple_symbol` is a colon and a method name. The C was
written not because the bytes are exotic but because the terminal is legal only
*somewhere*, and a tree-sitter grammar has no way to say where. We do: the parse
state's permission set is exactly the context those scanners were reaching for.

So `outside.zig` is a roll of rows keyed by the terminal's **own** name — never
by a language's — and a row is a pattern plus the `immediate`/`prec` standing
the IR has no wrapper to carry for an external. One row serves every grammar
that shares the convention, which is why `string_content` appears once rather
than three times. A grammar that means something different by a name in that
table is a bug report, not a special case to add.

Two kinds are deliberately absent. A terminal that must remember something
about the bytes before it — a heredoc's tag, which fence opened a Python
string, the column stack behind `_indent` — is run state rather than a slate
pattern, and the table would be lying if it claimed them. A zero-width terminal
is out for a harder reason: the scan advances by the match, so a terminal that
accepts the empty string pins it at one offset forever.

## Lexing is state-directed, and that is not a refinement

The naive reading — offer every terminal at every offset — does not survive
contact with a real grammar, and the smallest grammar we have is already enough
to break it. tree-sitter-json declares

```
string_content: token.immediate(prec(1, /[^\\"\n]+/))
```

which is legal only between quotes. Asked unconditionally, it is longest almost
everywhere. Over `{"a": [1, true, null], "b": "x"}` it takes `: [1, true,
null], ` in one bite, and thirty-two bytes that should be twenty-one tokens
become thirteen. `outliner lex` prints exactly this, which is the cheapest way
to watch it happen.

So `Scanner.next` takes an `Expected` — the terminals the parse state will
accept — and the restriction rides irregex's walk rather than filtering its
answer. Filtering afterward recovers nothing: the long illegal match has
already suppressed every short legal one behind it, and there is no result left
to filter. Passing `null` asks the unconditional question, which is honest only
for a grammar with no context-dependent terminal.

Producing the per-state set is `kernel/joint`'s job, because the set *is* the
LALR row. That is the seam where M1 and M2 meet, and it is why the two are
separate folders rather than one lexer that also parses.

## What the corpus says

The measure that means anything is the state-directed one — `outliner joints
<grammar.json> <file>`, which lexes from the live LALR row. Over
`research/joinery/corpus/`, blind counts from `outliner lex`:

| Grammar | Blind | Where the walk stops, and whose problem that is |
|---|---|---|
| json | 0 | accepted |
| rust | 9 | accepted — `string_content` and `string_close` were the whole gap |
| c | 0 | byte 490. `long ledger_total(` reads as a `sized_type_specifier`, so by `(` the only live item is `parenthesized_declarator` and `primitive_type` is not in the row. A table fact |
| go | 0 | byte 167, `&Ledger{`. `{` has no action in state 192 — the composite-literal conflict. A table fact |
| java | 0 | byte 265, `rows.addAll(`. A table fact |
| cpp | 2 | byte 248, `for (std::size_t i`. A table fact |
| javascript | 3 | byte 123, `constructor(seed = [])`. A table fact |
| typescript | 5 | byte 267, the `=>` after `(v, i)`. State 1554 holds only `parenthesized_expression -> ( expression ) .`, so `=>` is not in the row. A table fact |
| ruby | 25 | byte 136. `_line_break` and `simple_symbol` work now; the string family needs the delimiter stack |
| bash | 19 | byte 113, `declare -a rows=()`. An array value is glued by `_concat`, which is zero-width |
| python | 7 | byte 0, a module docstring. `string_start` needs to remember which fence opened |

Seven of the nine remaining stops are the table collapsing a conflict
tree-sitter keeps alive with GLR. A lexer cannot fix a table; those belong to
whoever owns the press.

Getting there cost four fixes, three of them in irregex, and each was a real
defect rather than a missing feature:

- **`\p{XID_Start}` / `\p{XID_Continue}` did not resolve.** They are how Go,
  Java, C, Rust, and JavaScript each spell "identifier character". The UCD data
  was already pinned; the generator lifted only the three properties `\w` was
  built from. It now reads every binary property in the file.
- **The slate compiled with Unicode off.** irregex's library default is
  byte-wise; source files are UTF-8 and tree-sitter patterns are JavaScript
  regexes, so `café` was being split mid-character.
- **The determinizer's cost budget refused `\w+`.** `max_visits` is calibrated
  for a pattern the user typed a second ago; a lexer slate is compiled once and
  amortized over every byte it ever sees. Every refusal measured was
  `too_costly`, never `too_large`.
- **A refused pattern renumbered its neighbours.** A munch reports the ordinals
  it was handed and never renumbers around a refusal, so compacting the
  ordinal→symbol map here shifted every terminal after the first refusal onto
  its neighbour's name — Go reported `}` as an `interface` and nothing crashed.

## Known gap

The stateful half of the externals. An indent/dedent column stack, a heredoc tag
stack, and a delimiter-matched raw span are three general built-ins that would
cover python, bash's heredocs, and ruby's strings between them, and none of them
is a pattern — each needs run state the slate has nowhere to keep. That is the
next thing this folder should grow, and it is a mechanism rather than a table
row, which is why `outside.zig` does not pretend to hold it.
