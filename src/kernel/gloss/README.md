# gloss — a query, pressed

A `.scm` query is source. tree-sitter ships it as source, and every editor that
loads a grammar re-parses `highlights.scm` at startup, resolves every node name
against the symbol table, and compiles every `#match?` regex in the host
binding - again, per process, forever. None of that depends on the file being
edited, so none of it needs to happen on the user's machine.

This directory does it once, at mint, and puts the result in the folio. What
comes out is a program: names are already symbol ids, fields are already field
ids, a supertype is already a membership test, and a regex is already an
`irregex` program. Reading it back is a bounds check and a cast.

Running it against a tree is not here. The compiler needs no tree at all, which
is why it could be built in the same wave as the tree surface it will eventually
use.

## Five files, and the seam between them is the interesting part

| | What it owns |
|---|---|
| `rubric.zig` | Syntax. `.scm` bytes in, a pattern AST out. Knows nothing about any grammar - it will happily parse `(nonexistent_rule)`. |
| `lemma.zig` | The grammar's facts, indexed the way a query asks for them. The reverse of the folio's name tables, plus two relations the folio does not store. |
| `sift.zig` | The predicate policy: which four we evaluate, what the rest are, and what a refusal means. |
| `stencil.zig` | The program - the bytes the folio carries and the view a matcher reads them through. |
| `gloss.zig` | The lowering: rubric + lemma + sift → stencil, with the reachability check on the way past. |

`rubric` is deliberately grammar-blind. Splitting syntax from resolution is what
lets the compiler say *which* of the two a file got wrong, and the corpus made
that pay: every one of the eight files this compiler refuses is a resolution
refusal naming a specific word, not a parse error pointing at a byte.

## A name is a set, and that is the thing to know before reading `lemma`

The obvious model - a query name is a symbol id - is wrong three separate ways,
and each one silently mismatched real files before it was fixed.

**One spelling, several sorts.** Ruby has a rule `alias` and a keyword
`"alias"`. JavaScript has `class` both ways; TypeScript `module`; Python `type`.
The query notation already distinguishes them - `(class)` is the rule, `"class"`
is the keyword - so the index keeps a slot per sort rather than one entry per
name.

**One spelling, several symbols of the same sort.** A grammar can mint a fresh
terminal for `token(prec(1, "<"))` beside a plain `"<"`, and both print as `<`,
so one written name resolves to two ids. A step therefore carries a *run* of
symbol ids rather than one.

Between them these are not a corner: **twenty of the twenty-eight grammars have
at least one symbol whose spelling another symbol already took**, Ruby thirty-one
times. The rung's `shared` column counts them per grammar.

**Names no symbol owns.** The press carries tree shaping rather than applying
it, so `alias($.identifier, $.type_identifier)` leaves the symbol as
`identifier` and records the rename in a side table. A tree node's kind is the
rename, so that is what a query writes: Rust's `highlights.scm` opens on
`(type_identifier)`. Renames are a second id space, indexed here beside the
first, and a step carries a reading in each - both may be set at once, because
C++ has a rule `function_declarator` *and* renames another symbol to the same
spelling.

## Two relations the folio does not store

Both fall out of one fixed point over the productions, in `close`.

**Supertype membership.** `Folio.supertypes()` says which rules *are*
supertypes, not which concrete kinds belong to one, and the corpus asks the
second question forty-three times. A supertype presses as `hidden`, so it emits
no node and splices its children - which means the membership *is* the splice.

**Which fields a kind can carry.** Same shape: a field is written on a
production's child position, so a kind's fields are the union over its
productions, and over anything hidden those productions splice.

The walk is a fixed point rather than one pass because a hidden rule's contents
are defined in terms of whatever it splices, which recurses wherever the grammar
does. `Lemma.passes` reports how many rounds a grammar took.

## Predicates: four run here, the rest are carried

The predicate vocabulary is **not closed**, and pretending otherwise would fail
files that are not wrong. `#set!` is the single most common `#` form in the
corpus at eighty uses and it is a *directive* - metadata for the host, filtering
nothing. Four more spellings are editor extensions whose semantics live in
Neovim rather than in any parser: `#lua-match?`, `#is-not?`, `#has-ancestor?`,
`#not-kind-eq?`.

So: `#eq?`, `#not-eq?`, `#any-of?`, `#match?` and `#not-match?` are **evaluated
here**. Everything else is **carried as opaque metadata** - spelling and
arguments preserved, kept in the program, never run. A refusal happens only if
someone asks to evaluate one. A Neovim `highlights.scm` loads intact; a host
that understands `#set!` reads it straight out of the program. `sift.zig`'s
header is the authority on this.

`#match?` is the one worth measuring, because tree-sitter compiles its regex in
the host binding once per candidate match. Here it is compiled with the query.
The rung reports the ratio.

## Static reachability, and how few it finds

The compiler holds the grammar's tables, so it can prove a pattern will never
match before anyone runs it: a field this kind never carries, a supertype
membership that does not hold, a child no production admits.

Over the eighty-two real query files it finds **one**: `lua/highlights.scm`
groups `"elseif"` into an alternation under `(if_statement)`, and in
tree-sitter-lua that token belongs to `elseif_statement`. The pattern is not
merely unlikely, it is unsatisfiable.

One is the honest number and it took work to get down to. Earlier versions of
the check reported seventy-two, and every one of the extras was the check being
wrong about a name rather than the file being wrong about the grammar - the
three set-valued facts above, each discovered by hand-checking a claim against
the grammar that supposedly contradicted it. A "can never match" claim has to be
certain, so wherever the answer is ambiguous - a spelling with two readings, a
rename over several symbols - the check declines rather than guesses.

## The rung, and what it refuses

`bench/rungs/gloss` compiles every `.scm` file the thirty pinned grammars ship -
eighty-two files across twenty-eight grammars - and reports per file. It needs
`upstream/grammars/` fetched, which is why it is a rung and not a test.

**Seventy-four of eighty-two compile.** The eight that do not trace to three
causes, none of them in this directory:

- **Four** name an anonymous keyword the press folded away. `fallthrough_statement`
  is `prec.left("fallthrough")` - a rule whose entire body is one string - and
  the press resolves it to a terminal, so no symbol is named `fallthrough`.
  tree-sitter emits the keyword as an anonymous child. That is a press question.
- **Two** query `(ERROR)`. This engine has no error node by design: a repair is
  recorded in `Quire.scars`, with the range it deleted or the terminal it
  supplied, rather than as a node in the tree. A query wanting error regions
  should ask that channel.
- **Two** are `markdown-inline` queries checked against the markdown *block*
  grammar. Two grammars ship from that repository and only one is pinned, so
  these files are being compiled against a grammar they were never written for.

Refusing these is the point. A compiler that accepted eighty-two by treating the
hard ones as no-ops would be worth less than one that accepts seventy-four and
says which eight and why.
