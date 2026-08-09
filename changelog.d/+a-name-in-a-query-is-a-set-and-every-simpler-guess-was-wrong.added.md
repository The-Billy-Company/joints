`src/kernel/gloss/` compiles a `.scm` query into a program and presses it into
the folio's `gloss` section, which stops being reserved in the same change that
gives it a reader. Five files: `rubric` (syntax, grammar-blind), `lemma` (the
grammar's facts indexed the way a query asks), `sift` (predicate policy),
`stencil` (the program and its codec), `gloss` (the lowering). The rung
`bench-gloss` compiles every `.scm` the thirty pinned grammars ship - 82 files
across 28 grammars - and **74 compile**.

The point is that none of this work depends on the file being edited. tree-sitter
re-parses `highlights.scm` per process, re-resolves every node name against the
symbol table, and compiles every `#match?` regex in the host binding once per
candidate match. Compiling the regex with the query instead measures **6.7x**
over the corpus's 59 `#match?` patterns and 708 simulated candidates, and that is
the floor rather than the claim: the ratio grows with candidates, and a
`highlights.scm` over one real file is thousands.

`lemma`'s index is a hash map. The DAFSA was re-measured rather than inherited
from last wave's storage verdict, and it loses **5.18x** on probe and 45x on
build over 8,820 keys - and it answers a different question anyway, an ordinal
over its own sorted keys, needing a second array to reach a symbol id and one
instance per sort.

**The three wrong models of a name, each of which shipped and then didn't.** A
query name is not a symbol id. One spelling can hold several sorts (Ruby's rule
`alias` and keyword `"alias"`; `class` in JavaScript, `module` in TypeScript,
`type` in Python) - the notation already distinguishes them, so the index keeps
a slot per sort. One spelling can hold several symbols of the *same* sort,
because a grammar mints a fresh terminal for `token(prec(1, "<"))` beside a
plain `"<"` - so a step carries a run of ids, and **twenty of the twenty-eight
grammars have at least one collided spelling**, Ruby thirty-one times. And some
names no symbol owns at all: this press carries `alias($.identifier,
$.type_identifier)` as a rename in a side table, and the tree node's kind is the
rename, so Rust's `highlights.scm` opens on a name that is not in the symbol
table. Renames are a second id space and a step carries a reading in each,
because C++ has a rule and a rename that spell the same.

Two relations the folio does not store fall out of one fixed point over the
productions. `Folio.supertypes()` says which rules *are* supertypes; the corpus
asks forty-three times which concrete kinds *belong* to one, and since a
supertype presses as `hidden` the membership is the splice. Which fields a kind
can carry is the same shape, unioned over its productions and over anything they
splice. Fixed point rather than one pass because a hidden rule's contents are
defined in terms of what it splices.

**Static reachability finds exactly one dead pattern in the corpus**, and the
number took work to earn. It proves a pattern can never match - a field this kind
never carries, a supertype membership that does not hold, a child no production
admits - and it reported seventy-two before the three name models above were
fixed. Every one of the seventy-one was the check being wrong about a name rather
than the file being wrong about the grammar. The survivor is real:
`lua/highlights.scm` alternates `"elseif"` under `(if_statement)`, and in
tree-sitter-lua that token belongs to `elseif_statement`. Where a name is
ambiguous the check declines rather than guesses, because "can never match" has
to be certain.

**The predicate vocabulary is not closed, so it is not treated as closed.**
`#eq?`, `#not-eq?`, `#any-of?`, `#match?` and `#not-match?` are evaluated here.
Everything else is carried as opaque metadata with its spelling and arguments
intact, and refused only if someone asks to *evaluate* it. That is not
permissiveness: `#set!` is the most common `#` form in the corpus at eighty uses
and it is a directive that filters nothing, and four more spellings
(`#lua-match?`, `#is-not?`, `#has-ancestor?`, `#not-kind-eq?`) have their
semantics in Neovim rather than in any parser. A `highlights.scm` written for an
editor loads intact and a host that understands `#set!` reads it back out.

The eight refusals are named rather than absorbed, and none is a gloss bug: four
name an anonymous keyword the press folded into a terminal (`fallthrough` is
`prec.left("fallthrough")`, a rule whose whole body is one string), two query
`(ERROR)` where this engine records repairs in `Quire.scars` instead of a node,
and two are `markdown-inline` queries checked against the markdown block grammar
because only one of that repository's two grammars is pinned.
