# joints: A Parsing Engine Whose Grammars Are Data

> [!NOTE]
> Nothing here is ready to sit under an editor you depend on. There is a
> parser, a tree, an incremental re-parse and a C ABI, and ten of the thirty
> pinned grammars still stop somewhere. Take
> [tree-sitter](https://tree-sitter.github.io/tree-sitter/) for production work.
>
> Everything below says where that line is and how to move it.

- [Overview](#overview)
- [Should I Be Using This?](#should-i-be-using-this)
- [Support](#support)
- [Install](#install)
- [Where It Stands](#where-it-stands)
- [Scanners as Data](#scanners-as-data)
- [Why Not tree-sitter](#why-not-tree-sitter)
- [The Idea](#the-idea)
- [The Vocabulary](#the-vocabulary)
- [The C ABI](#the-c-abi)
- [Layout](#layout)
- [Build and Test](#build-and-test)
- [How It Is Proven](#how-it-is-proven)
- [Provenance](#provenance)

## Overview

joints is a parsing system for editors and agents: hand it a file, get back a
concrete syntax tree that survives edits, tolerates broken code, and answers
structural queries. That is tree-sitter's job description too.

The difference is what a grammar becomes. tree-sitter compiles a grammar into a
C program, and everything painful downstream follows from that one choice - a
30 MB `parser.c`, a shared library per language, an ABI window to keep matched,
25 MB of WASM before a browser can highlight ten languages.

Here a grammar becomes data: tables in one mmap-able file called a **folio**.
One binary plus one folio is every language you support, with no C compiler in
the loop and no generated source in git.

The scanner becomes data too. The part of a tree-sitter grammar that stays C
after the table is generated - the external scanner, with its own `malloc`, its
own `serialize`/`deserialize`, and its own struct carried between calls - is a
**customary** here: rules over typed organs, read by one interpreter that ships
once for every language.

That is what takes the asterisk off the sentence above, and it is the newest
half of the design. [Scanners as Data](#scanners-as-data) is what it cost and
what it bought.

The input is the ecosystem's own work rather than a new notation. `grammar.json`
is a declarative file committed in most tree-sitter grammar repositories, and
three hundred maintained grammars with their `highlights.scm` are person-decades
that cannot be out-engineered, so they get imported and their node names are
preserved byte for byte.

## Should I Be Using This?

Six answers, and the first one is no.

- **To ship a syntax-aware feature this quarter** – no, take
  [tree-sitter](https://tree-sitter.github.io/tree-sitter/). It parses more
  languages more completely than this does today and it has the ecosystem, and
  no amount of algebra downstream changes either fact this year.
- **To embed several languages with no per-language build story** – here. One
  binary links `libjnt`, opens one file, and gains every grammar pressed into
  it, with no toolchain, no `.so` per language, and no Emscripten pin.
- **To parse a grammar whose CI cannot build it** – here, and this is the
  clearest statement of the problem. A grammar that needs 20 GB of RAM to
  compile a C table is a grammar the incumbent cannot ship.
- **To read how an LR parse becomes an algebra** – [The Idea](#the-idea), then
  [`research/LANDSCAPE.md`](research/LANDSCAPE.md). Every stage is a folder with
  its own README.
- **To take the argument rather than the code** – [`research/`](research/README.md),
  where each dossier separates what is claimed from what the world already knew
  from what would prove it wrong.
- **For a Python or Rust package** – not yet. Both names are reserved at
  `0.0.0` and export nothing, because a stub returning plausible values is worse
  than an empty one.

The dividing line is whether you want a parser or an argument about parsers.
Today this repository is much better at the second, and it says so in numbers
rather than in adjectives.

## Support

- Bugs and feature requests go through this repository's issues. A parse
  complaint wants the grammar pin, the bytes, and the verb you ran, because a
  tree without its subject is a tree nobody can reproduce.
- Vulnerabilities never go in a public issue. Open a private security advisory
  on this repository instead.
- [irregex](https://github.com/The-Billy-Company/irregex),
  [gist](https://github.com/The-Billy-Company/gist),
  [relate](https://github.com/The-Billy-Company/relate) and
  [blast](https://github.com/The-Billy-Company/blast) are separate repositories
  with their own trackers. File a regex or a search problem there; it moves here
  if the cause turns out to be the parse.

## Install

Two prerequisites, and neither is a download to remember: **Zig 0.16.0**, the
`minimum_zig_version` in [`build.zig.zon`](build.zig.zon), and a checkout of
irregex as a *sibling directory*, because the manifest resolves it as
`../irregex` while the two halves of the lexer conversation still move together.

```sh
git clone https://github.com/The-Billy-Company/irregex
git clone https://github.com/The-Billy-Company/joints
cd joints
zig build
```

That writes three artifacts under `zig-out/`: the `joints` CLI, `libjnt` as both
a shared library and a static archive, and [`include/jnt.h`](include/jnt.h).
Nothing else is needed to parse a file, and no step of it touches the network.

The eight CLI verbs split in two. `parse`, `amend`, `query` and `mint` are the
product - a tree, the tree again after an edit without re-reading the file, a
compiled `.scm` asked about one, and a grammar pressed into a folio. `grammar`,
`lex`, `state` and `survey` look at the machinery, and they are why the other
four could be written at all.

```sh
joints mint python.json -o python.folio          # a grammar becomes a file
joints parse python.folio app.py                 # a file becomes a tree
joints amend python.folio app.py 120..124=chunk  # an edit becomes a re-parse
joints query python.folio highlights.scm app.py  # a tree becomes answers
```

`joints --version` and a bare `joints` print the synopsis, which is built from
the verb table at comptime so it cannot describe a set the dispatcher does not
have. Exit codes follow the family: 0 ran, 1 a clean negative answer, 2 an
error.

## Where It Stands

There is a parser, and most of the machinery the design asked for is under it.

- **Built and measured** – the press (a `grammar.json` importer, an LR(0)
  collection, LALR lookaheads, and conflict resolution that reaches zero
  residual conflicts on eleven real grammars), the terminal scanner and the
  customaries beneath it, every monoid in [The Idea](#the-idea), the tree with
  delete-and-supply repair at every refusal, the incremental weave, the folio
  and the codex that packs many into one, the query engine, the CLI, and
  `libjnt`. [Layout](#layout) is the directory-by-directory version.
- **Reachable from a C host** – parsing, editing, and the whole node
  neighborhood. See [The C ABI](#the-c-abi).
- **Built but not reachable from a C host** – the query engine. `joints query`
  drives it and `libjnt` has no `jnt_query_*`, which is exactly where an editor
  would reach for it. This is the largest thing missing.
- **Proven but not wired** – the tropical semiring the repair walks under.
  `mend` ships four author-facing policies rather than taking the semiring as
  the parameter it should be.

The order those landed in was deliberate. The central claim has a falsifier
measurable *before* a parser exists, so the measurement came first: the product
of segment effects reproduces the whole-file effect no matter how finely the
file is cut, across eleven grammars, with nothing disagreeing. Read
[rung 1's verdict](research/joinery/TESTING.md) for what the numbers were,
including the part where the kill condition as originally written was not met
and why that number turned out to be the wrong one to have chosen.

Where the parse stands is one command rather than a paragraph, because a count
pasted into a page is a count that ages into a lie. `python3 tool/standing.py`
holds every byte of the pinned corpus and answers coverage, structure and
agreement as three separate questions. As this was written it reads **20 of 30
grammars whole, all 30 handing back a sound forest over 114,019 nodes, 79.5% of
the corpus standing and 89.6% covered**:

```text
joints `a25375c50` · tree `60651098a` (live) · oracle `d85e736fa` seated but
**no verdict live on this arm** (0 of 30 held)
```

That stamp is not decoration. Four boards published in one morning here
disagreed by ~1,900 bytes with all four correct about different trees - and the
second half of this one says no oracle judged these bytes, which is why nothing
above claims the trees are *right* rather than present.

The ten grammars that stop are named and owned. `zig build census` says which
wall each hits and whose defect it is, which is the sentence worth having:
"nobody wrote a scanner" is a wall you cannot act on, and "this grammar's book
claims this terminal and produced nothing here" points at the rule to fix.

The size claim is met, and not by the monoid that was supposed to carry it.
[Rung 4](research/joinery/TESTING.md#rung-4---is-the-quotient-worth-its-build-time)
measures the folio against tree-sitter's compiled parser in bits per production
and joints is smaller on all eleven, from 0.139x to 0.987x, with no grammar
losing - recorded at `f6018936c`. That win is the folio's encoding. The
quotient contributed almost none of it: the bisimulation merges 0 to 19 states
out of thousands, the column alphabet narrows by 1.00x to 1.09x, and the DAFSA
*loses* to a sorted array by 2.85x to 4.33x, so the folio keeps writing the
array.

One caveat cuts the other way. Our side includes a lexicon section per grammar
that tree-sitter emits as compiled machine code inside the `.so` and so does not
pay for in this currency. A prediction that came out right for the wrong reason
is still a prediction that came out wrong, and both halves are above.

## Scanners as Data

A tree-sitter grammar can declare an **external scanner**, a hand-written C
function that lexes what a regex cannot: Python's indentation, Ruby's heredocs,
OCaml's nested comments. Shipping per-language C is the one thing this package
exists not to do, so joints transcribes the mechanism instead.

A customary is a grammar's scanner written as data - rules over a fixed algebra
of typed organs, a frame stack for layout, a mark stack for delimited spans,
eight registers - read by one interpreter that ships once for every language.
Eight books ride in the binary today, for elixir, haskell, html, kotlin,
markdown, scala, swift and yaml.

A grammar gets a rule only when its own declarations earn it, never because a
token is spelled the way some other language spells it. If nothing earns it the
grammar gets silence, because a token we cannot produce beats a token we produce
wrongly, and the wrong kind is invisible until somebody reads the tree.

html is the strong evidence. Its 72,288 bytes parse whole under one root, its
505-line hand-written ancestry scanner is deleted, and the differential against
tree-sitter reports no differences at all.

yaml and markdown are the honest halves of the same result. Both went from
nothing to a whole tree once their scanners became data, and only markdown's is
judged against tree-sitter's own tree - yaml's is unjudged, every byte of it,
because tree-sitter's yaml scanner does not compile here and there is no oracle
to hold it against. A tree where there was no tree is worth having, and it is
not a claim that the tree is right.

How many externals a book actually claims is a live number and is deliberately
not written here. `joints lex` says it for any grammar, and
[`research/customary/CENSUS.md`](research/customary/CENSUS.md) reads each
scanner's `serialize` as the specification of what a stand-in has to hold. That
census is also where the roster got corrected: the prose used to say eight
grammars keep state in C across calls, and read against `serialize` it is six.

So be concrete about what a grammar with unanswered externals still gets. It
imports, it presses, it ships a folio smaller than the shared library, and it
parses every construct that does not need the external. "Parses whole except
inside heredocs" is a real product; "supports every language" would be a lie,
which is why it is not the title.

## Why Not tree-sitter

Today, reach and nothing else, and only if reach is what is stopping you. The
pitch when the rest lands is four things, and throughput is not one of them.

- **Size** – tree-sitter's dense parse table is 64% of `parser.c` at 24.3%
  density. Predicate minterms plus action-bisimulation plus a DAFSA should land
  materially under its in-flight compressed-row work, which itself takes C# from
  29 MB to 8.5 MB.
- **Reach** – one artifact and no toolchain. The grammars that cannot be built
  today because CI runs out of memory are the clearest possible statement of the
  problem.
- **Recovery you can steer** – tree-sitter's `error_cost` is a greedy heuristic
  with no author-facing knob, which is why typing `justif` in a CSS rule gives
  you an `attribute_name` inside an `ERROR`. Here repair is a shortest path in
  the tropical semiring with weights declared in the grammar, so that case is a
  one-line grammar edit rather than a core patch.
- **Edits that do not invalidate the suffix** – tree-sitter reuses left to
  right, so opening a block comment at the top of a file re-parses the file.
  Because a segment here stores a *function* rather than a *state*, that edit
  costs `O(log n)`.

Throughput's absence from that list is a decision about what to argue rather
than a concession. It used to be a concession, while the parse was quadratic in
file length; that defect is closed, and `python3 tool/bench.py run
--axis=throughput` now splits fourteen grammars **seven rows to joints and seven
to tree-sitter** at 128 KB each on one machine.

The split is neither noise nor evenly spread. Every measured grammar whose
external scanner keeps state in C is a loss, which is the customary interpreter
being an interpreter where tree-sitter runs compiled C, and six of the eight
grammars without one are wins.

So the honest version is that throughput is no longer a reason to avoid joints
on an ordinary grammar, it is still a reason to avoid it on markdown or yaml,
and nobody is waiting on a parser either way.

## The Idea

A monoid is a set with an associative product and an identity, and that is the
whole prerequisite for three things at once.

Parallel evaluation, because a product can be re-bracketed freely and so becomes
a prefix scan of `O(log n)` depth. Incremental update, because the product kept
in a balanced tree costs `O(log n)` to repair when one factor changes.
Composition with no base point, because an element is a *function* and does not
care what came before it.

That third property is the one tree-sitter gives up, and it is where suffix
invalidation comes from. A state must be recomputed when its predecessor
changes; a function need not.

joints runs five monoids over one balanced tree, and the research dossiers call
them M1 to M5.

- **M1, lexical transition functions**, buy data-parallel lexing and an edit
  that does not invalidate downstream lexing. The scanner tokenizes real files,
  the customaries answer the externals whose C keeps state between calls, and
  the vectorized first pass under it pays up to 3.6x on a forward walk - though
  its line index repays only a forward sweep and costs 0.08x to 0.43x on
  jumbled access.
- **M2, LR stack effects, the joints**, buy position-independent reparse,
  parallel parse, and GLR paid only where the element is multi-valued. This is
  the one genuinely new thing here and the one rung 1 was built to kill.
- **M3, balanced parentheses**, buy the tree itself at 2n+o(n) bits, navigated
  by range min-max. It is built both ways: the spine is generic over the monoid
  and verified against random edit streams, and vellum settles it at 2.82 bits
  of shape a node, 1.96x smaller end to end, 5x faster on `depth`, 30-100x
  slower on `parent`, and 105x faster to re-index after a keystroke.
- **M4, a semiring parameter**, buys least-cost repair, ranking and ambiguity
  counting from one walk with a different `⊕`. Repair ships as `mend` with four
  author-facing policies; the semiring is proven in irregex and `mend` does not
  take it yet.
- **M5, Myhill-Nerode quotients**, were supposed to buy the size win and
  [found almost nothing](#where-it-stands). The relation is worth keeping
  because it is the only thing that can assert no two states are
  interchangeable, and the size win at rung 4 belongs to the folio's encoding.

Four features, one splice implementation, one set of tests. That economy is the
actual argument; the individual monoids are mostly known.

The new claim has a clean way to die. If joints do not converge toward rank one
on real grammars and real files, composition costs `|Q|` per join and
tree-sitter's O(1)-per-token walk wins - a measurement that needs no parser and
is [rung 1](research/joinery/TESTING.md).

## The Vocabulary

The metaphor is bookmaking, and it carries weight rather than decoration: you
write a rubric, the press compiles it into a folio, and at runtime the grain
reads the material, joints compose along the spine, mend repairs what is torn,
gloss answers questions, and the result settles from quire into vellum.

- **rubric** – the grammar source you write.
- **press** – the compiler: rubric to LR(1) to quotient to DAFSA to folio.
- **folio** – the artifact: one pressed grammar, one mmap-able file.
- **codex** – several folios under one cover, which is the whole of the "N
  languages, one file" claim.
- **grain** – the SIMD first pass over strings, comments, brackets and indent
  columns.
- **joint** – one stack-effect element.
- **spine** – the monoid-annotated balanced tree everything is bound to.
- **mend** – least-cost repair under the tropical semiring.
- **quire** and **vellum** – the live editable tree, and its settled succinct
  encoding.
- **gloss** – the query engine: a `.scm` pressed into a program, and run against
  a tree.

## The C ABI

`libjnt` is 47 exports behind [`include/jnt.h`](include/jnt.h), symbols prefixed
`jnt_`, matching irregex's `libirgx` and `irgx_`.

There are two doors on the same tree. `jnt_parse` answers *what is this file*,
and `jnt_weave_*` answers *what is it now, given that it was that a moment
ago* - the question an editor asks a thousand times an hour, and the only
question an incremental parser exists for.

One node vocabulary covers both, because which door a tree came through is not a
thing a highlighter should have to know. `jnt_node_parent`, `_next`, `_prev`,
`_next_named`, `_prev_named`, `_by_field`, `_depth` and `_covering` walk in every
direction rather than down only, and the last of them answers what encloses the
cursor, which is the question a viewport asks.

There is no cursor type, on purpose. tree-sitter ships one because its `TSNode`
is a struct whose parent costs a walk from the root; here a node is a `u32`
index into an arena and its parent is a field read, so a cursor would be a
handle wrapping a handle and one more thing for a host to leak.

A weave hands back a *borrowed* tree that it owns and refreshes in place, so
`jnt_tree_free` on it is a no-op. The alternative, a fresh owned tree per amend,
makes every host that stores the pointer wrong in a way that only shows up under
fast typing, which is exactly when nobody is looking at their allocator.

Nothing aborts. Every entry returns a status, so a malformed file, a wrong
language or a host that miscounted an edit span can never terminate the process,
and `jnt_last_error()` holds the sentence the CLI would have printed. The rest
of the host's obligations are in
[`src/surface/abi/README.md`](src/surface/abi/README.md).

## Layout

Two trees, and the split between them is the point: `research/` is the argument
and `src/` is the part of it that compiles.

```text
research/          the argument, and the claim that has to be earned
  LANDSCAPE.md     the map: incumbent measured, five monoids, order of proof
  joinery/         CLAIM · PRIOR_ART · TESTING for the one new thing
  joinery/corpus/  one ledger program in eleven languages
grammars.toml      the thirty tree-sitter grammars the rungs measure over, pinned
tool/              fetch and check those grammars; run the rungs as gates
customary/         one book per grammar: the scanner-as-data, embedded at build
test/grammar/      the one grammar committed, so the test build needs no network
charter.zone       the zoning import topology, judged against the real @import graph
include/           jnt.h, the normative statement of the C ABI
bindings/          the reserved Python and Rust packages
src/press/         the compiler: grammar.json in, LR(0) → LALR → resolved out
src/folio/         the artifact: write, map, verify, slice - and the codex
src/kernel/grain/  the vectorized structural pass: lines and indents
src/kernel/lex/    the terminal scanner, and the customary interpreter under it
src/kernel/joint/  the stack-effect monoid and the cursor that composes it
src/kernel/walk/   a single-stack reference LR walk, to check the algebra against
src/kernel/spine/  the monoid-annotated balanced tree everything binds to
src/kernel/quire/  the tree a parse yields, with mend at every refusal
src/kernel/weave/  a file held open: spine and quire maintained across an edit
src/kernel/vellum/ the tree settled into balanced parentheses
src/kernel/gloss/  the query engine
src/surface/face/  the CLI: grammar · lex · state · survey · parse · amend · query · mint
src/surface/abi/   libjnt: the parse door, the edit door, and one node vocabulary
```

Two directories landed one band higher than the plan guessed, for the same
reason. vellum reads the quire it settles *and* the spine it hangs the
parenthesis word on, and gloss reads the folio for the query it was handed and
the quire for the tree it matches against, so either one filed under
`kernel/quire/` would have been importing up the page.

## Build and Test

There are three test binaries, one per root, and a filter only searches the one
you name. An unfiltered `zig build test` runs all three.

```sh
zig build check                    # compile everything, install nothing - the fastest red
zig build test                     # the library, the CLI and the ABI
zig build face -Dtest-filter=...   # just the CLI's tests
zig build abi                      # just the C ABI's
zig build idiom                    # the package-wide vocabulary proof
```

Only the grammar sweep needs the network, and it is the last thing CI runs so a
press regression is never downstream of somebody else's repository being
reachable. The thirty grammars are pinned in [`grammars.toml`](grammars.toml) by
repo, commit, path and sha256 rather than vendored.

```sh
python3 tool/grammars.py fetch     # the only verb that uses the network
python3 tool/grammars.py verify    # hash disk against the manifest, offline
python3 tool/rung1.py              # the falsifier, ~13 s over eleven grammars
python3 tool/standing.py           # the board: coverage, structure, agreement
python3 tool/glance.py             # the query differential against tree-sitter
```

Measure against a pin and never against a path. Everyone builds into the same
`zig-out`, so a comparison naming `zig-out/bin/joints` is naming whatever is
there when each half runs - which once turned a reference arm into a treatment
arm mid-measurement and produced a clean thirty-of-thirty for entirely the wrong
reason. `tool/pin.py` builds a prefix plus a record of the tree that produced
it, and every instrument reads `JOINTS_BIN`.

[CONTRIBUTING.md](CONTRIBUTING.md) has the rest, including the house rules that
come up in review and the reason a passing test writes to stdout.

## How It Is Proven

Two of the design's rungs have been run, rung 1 and rung 4, and the rest have
not. Every number on this page is either measured, in which case the instrument
that produced it is named beside it and reproducible from a clone, or a target
with a kill condition attached, in which case it is labelled as one.

- **A falsifier that ran before the parser existed.** Rung 1 fails if any
  grammar keeps a residual conflict, if any chain disagrees about the product of
  its segment effects, or if the residue gets past two. It is a CI gate, not a
  one-time result.
- **An oracle that is a different parser.** `tool/glance.py` asks `joints query`
  and `tree-sitter query` the same harvested `.scm` files over the same sources
  and diffs the answers twice, as multisets and as sequences. Every real fault
  in the matcher so far was invisible to the unit tests, which agreed with the
  implementation because both were written from one reading of the notation.
- **A compiler that refuses out loud.** Seventy-four of the eighty-two query
  files the pinned grammars ship compile, and the eight refusals trace to three
  causes, each named in
  [`src/kernel/gloss/README.md`](src/kernel/gloss/README.md). A compiler that
  accepted all eighty-two by treating the hard ones as no-ops would be worth
  less than one that accepts seventy-four and says which eight and why.
- **A page that names the tree its numbers are true of.** CI's `record` job
  refuses a page you changed that reports a measured figure and names no tree or
  binary, ratcheting forward from a committed pin.
- **Structure as law.** [`charter.zone`](charter.zone) declares zones, seals and
  a reach ceiling, judged by `zoning verify` against the real `@import` graph
  rather than against anybody's memory of it.
- **A test list that cannot quietly shrink.** Every `*_test.zig` is named in
  [`src/proof.zig`](src/proof.zig) and no production file may name one, because
  a suite that silently lost a file is indistinguishable from a green one.
  `python3 tool/roll.py` refuses both halves.

## Provenance

joints is the fifth package in a family built on
[irregex](https://github.com/The-Billy-Company/irregex), the regex engine and
C-ABI floor the others stand on. Its siblings are
[gist](https://github.com/The-Billy-Company/gist) for indexed ripgrep-parity
search, [relate](https://github.com/The-Billy-Company/relate) for
compression-as-search kinship, and
[blast](https://github.com/The-Billy-Company/blast) for provenance and blast
radius.

Most of what joints needs already existed down there: mmap portals, BLAKE3
signets, atomic artifact publishing, the dual-clock freshness model, bitsets,
hash-consing, union-find, byte-balanced parallel fan-out, and the succinct
rank/select and wavelet structures. Seven pieces were missing, all seven general
mathematics, so all seven belong in irregex rather than here.

The payoff runs back the other way too. relate currently finds function
boundaries by counting braces and climbing sixteen lines looking for something
that resembles a signature, and normalizes identifiers to `I` and numbers to `N`
against a hand-unioned keyword list. Both are honest approximations of a parse,
and an actual parser retires both.

joints reads tree-sitter grammars; it does not link, vendor or ship tree-sitter
itself, and nothing at run time depends on it. [NOTICE](NOTICE) attributes the
one third-party file in the tree, the committed json grammar fixture.

Apache-2.0. See [LICENSE](LICENSE). The changelog is towncrier: fragments in
[`changelog.d/`](changelog.d/README.md) fold into a release.
