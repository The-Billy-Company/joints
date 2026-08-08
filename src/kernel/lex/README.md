# kernel/lex - M1, bytes to tokens

The claim: **a lexer is not a program to generate, it is one anchored
longest-match question asked once per token.** Every terminal a grammar
declares is a regex (a literal is the degenerate case), irregex answers exactly
that question, and so this folder contains no automaton of its own.

One door in. `scanner.zig` is the entry, and `charter.zone` seals this directory
through it, so nothing outside may name any other file here. The four at the root
are the compiled path plus the one file standing in for an external scanner; the
seven in `hand/` are the memories a table cannot hold, and they have their own
[README](hand/README.md).

| File | Role |
|---|---|
| `scanner.zig` | The door. The grammar's terminals as one irregex slate, the tie-break, the guarded pre-pass, the extras skip, and the list of terminals nothing here can recognize. |
| `lexicon.zig` | The slate, already determinized: a compiled `Munch` as a block of bytes, because determinizing a slate is the whole of startup and a folio can map one instead. |
| `admit.zig` | What the walk is allowed to consider: the precedence tiers, the immediacy cut, and the per-state permission set shaped like them. |
| `outside.zig` | What an external scanner would have produced. Front half: a roll of spellings keyed by the terminal's own name. Back half: the hub that drives `hand/`, which is why it stays here rather than moving in with them. |
| `hand/` | Seven shapes of scanner memory - column stacks, span stacks, implied closes, commanded layout. Internal to this directory. |
| `scanner_test.zig` | Longest-wins, keyword-beats-pattern, extras, strays, blindness, the offside walk, the fence, the guards - and the measured trap that a real grammar sets for an unconditional slate. |
| `lexicon_test.zig` | The compiled slate round-tripped: what a folio wrote is what binds. |

## What is here and what is deliberately elsewhere

irregex owns everything that is a property of *automata*: grouping a slate past
one 64-bit attribution mask, admitting patterns by bisection so one unusable
token body is charged to itself rather than to the other hundred and fifty, and
narrowing the slate to a permitted subset during the walk.

This folder owns what is a property of *this grammar*:

- **Which terminals form the slate**, and the map back from a pattern ordinal
  to the symbol that owns it.
- **The tie-break.** `if` and `[a-z]+` both reach two bytes, and which one the
  language means is a fact about the language. tree-sitter's rule - a string
  beats a pattern of equal length, earlier declaration otherwise - is the rule
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
  dropped - only the ones that emit a node, so whitespace stays invisible and
  a caller never has to re-decide what the tree keeps.

## Externals, without a language name in the code

Ten of the eleven grammars in `upstream/` hand terminals to a C function we do
not link and never will. Read those scanners, though, and most of what they do
is **recognize a spelling the DSL could not host** - bash's `variable_name` is
`[a-zA-Z_]\w*`, ruby's `simple_symbol` is a colon and a method name. The C was
written not because the bytes are exotic but because the terminal is legal only
*somewhere*, and a tree-sitter grammar has no way to say where. We do: the parse
state's permission set is exactly the context those scanners were reaching for.

So `outside.zig` is a roll of rows keyed by the terminal's **own** name - never
by a language's - and a row is a pattern plus the `immediate`/`prec` standing
the IR has no wrapper to carry for an external. One row serves every grammar
that shares the convention, which is why `string_content` appears once rather
than three times. A grammar that means something different by a name in that
table is a bug report, not a special case to add.

A row may also state its **trailing context**, `after` and `never`, and that is
not a spelling. bash's `variable_name` stands in for a scanner that refuses
unless an `=` follows, and a bare pattern for it loses to `word` on `rows=()` by
pure length rather than by any tie. tree-sitter never runs that comparison
because its scanner answers first, so a guarded row is asked first here too:
`Scanner.refusing` is a pre-pass over just the guarded terminals, ahead of the
slate, and it reads neither precedence nor immediacy because no guarded row
carries either.

## The hands, for what a row cannot hold

A row is a function of the bytes at one offset. The rest of what an external
scanner does is a function of the bytes **and a memory every previous token
built**, which is a different animal and gets a different seam rather than a
cleverer table. That seam is [`hand/`](hand/README.md) - seven shapes of memory,
and the three properties that separate a hand from a row.

The binding is the part that lives out here: a grammar binds a troupe by
declaring its anchor as an external, and binding **claims** the other members, so
the roll stops seating a flat pattern for a name a hand now answers.

## Lexing is state-directed, and that is not a refinement

The naive reading - offer every terminal at every offset - does not survive
contact with a real grammar, and the smallest grammar we have is already enough
to break it. tree-sitter-json declares

```javascript
string_content: token.immediate(prec(1, /[^\\"\n]+/))
```

which is legal only between quotes. Asked unconditionally, it is longest almost
everywhere. Over `{"a": [1, true, null], "b": "x"}` it takes
`: [1, true, null],` plus its trailing space in one bite, and thirty-two bytes
that should be twenty-one tokens become thirteen. `joints lex` prints exactly
this, which is the cheapest way to watch it happen.

So `Scanner.next` takes an `Expected` - the terminals the parse state will
accept - and the restriction rides irregex's walk rather than filtering its
answer. Filtering afterward recovers nothing: the long illegal match has
already suppressed every short legal one behind it, and there is no result left
to filter. Passing `null` asks the unconditional question, which is honest only
for a grammar with no context-dependent terminal.

Producing the per-state set is `kernel/joint`'s job, because the set *is* the
LALR row. That is the seam where M1 and M2 meet, and it is why the two are
separate folders rather than one lexer that also parses.

## What the corpus says

The measure that means anything is the state-directed one - `joints survey
<grammar.json> <file>`, which lexes from the live LALR row. Over
`research/joinery/corpus/`, blind counts from `joints lex`:

| Grammar | Where the walk stops, and whose problem that is |
|---|---|
| json | accepted |
| rust | accepted |
| java | accepted |
| javascript | accepted |
| typescript | accepted |
| c | byte 841, the `"` of `printf(…)`. Twelve roots deep in recovery, and c declares no external at all, so nothing lexical is missing. A table fact |
| cpp | byte 290, the same shape at twenty-five roots. A table fact |
| go | byte 167, `&Ledger{`. `{` has no action in state 194 - the composite-literal conflict. A table fact |
| python | byte 153, the `:` of a typed parameter. The layout tokens in front of it are all correct. A table fact |
| ruby | byte 136. The string family works; the space after `@rows` arrives as ruby's `%w[]` separator, which is `\s+` spelled as a significant terminal |
| bash | byte 143, the `\n` after an assignment. bash declares `\n` as an **anonymous external** and the press drops it, so the terminator terminal does not exist |

Five of the six remaining stops are the table collapsing a conflict tree-sitter
keeps alive with GLR. A lexer cannot fix a table; those belong to whoever owns
the press.

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
  its neighbour's name - Go reported `}` as an `interface` and nothing crashed.

## Known gaps

**The press hands us a numbering that is not tree-sitter's.** The tie-break
chain here matches tree-sitter rung for rung, derived from tree-sitter's own
generated parsers rather than from us, but the last rung sorts on symbol id and
`import.zig` numbers a named token rule below an earlier rule's inline pattern
where tree-sitter numbers the inline one first. That is every `#include` in the
C corpus becoming `preproc_call`. Two smaller siblings: a negative token
precedence is clamped to zero, and an `externals` entry that is a `STRING` or
`PATTERN` rather than a `SYMBOL` is skipped entirely, which is what deletes
bash's statement terminator.

**C++ raw strings.** cpp's delimiter is a node the grammar names, and `fence`
models one mark and one close. Bending the model to fit it meant special-casing
it into meaninglessness, so it is absent rather than half-built.

**Heredocs.** bash and ruby both want the tag from the opener carried to a body
that begins on the next line. That is the same mark stack `fence` already has,
plus a deferral to a line boundary, and it is the next honest thing to grow.
