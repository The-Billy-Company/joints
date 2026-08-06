Two lanes hours apart named the corpus as the instrument that lied to them
hardest, and they were right in a way no board number could show. `Maps.kt` and
`Chunked.swift` between them contain no interpolation, no triple quote and no
raw string, so a **stateless** hand - one keeping no memory across a string
body, and therefore wrong the moment a string interpolates - measures
byte-perfect on every number this repository takes. A correct, well-understood,
20,728-byte Kotlin fix sat undone because nothing in the tree could tell it from
a wrong one.

`tool/specimen.py` and `research/joinery/specimen/` are the missing population.
Seventeen small files across kotlin, swift and julia carrying the awkward cases
on purpose - interpolation inside interpolation, `"""a""""` where the close is
greedy, `##"a "# b"##` where the delimiter appears in its own body, a nested
block comment - each with claims over the **forest** rather than a byte count.
`spans NAME START END` is the claim that does the work: a first-match reader
closing `"""a""""` at byte 15 instead of 16 produces a node of the correct name,
and only the extent separates them. Every extent is read off the source text,
never off a parser. Specimens are enumerated from their own directory and never
enter `upstream/sources/` or the ledger corpus, so no board number taken today
moves; `verify` asserts that against the live board file list.

The larger half is the coverage gate, joining two facts that both existed and
had never been put together - what a grammar declares in `externals[]`, and what
outliner already knows it has no stand-in for. Across thirty grammars: **461
declared, 252 seated (55%), 21 exercised.** markdown declares 47 and seats
**none**; latex, php and sql are also at zero, and those four have more to say
about coverage than Kotlin does. Kotlin seats 2 of 10 with five of the eight
blind terminals being the string, which is the 20,728-byte unblock named
exactly. Swift seats 21 of 33, and its blind `multiline_comment` turns
`/* c\n   d */` into a `prefix_expression` over a `multiplicative_expression` -
one root, zero mends, the comment parsed as **arithmetic**. Those bytes are not
orphaned, they are claimed, so `covered` counts them as read and every byte
measurement calls that file perfect.

Where it goes the wrong way, printed on every run: `exercised` is a floor twice
over. 216 of the 252 seated externals are `_`-prefixed and never become nodes,
so the gate can witness only **36 of 252**, 14%; for the rest the honest answer
is that it does not know. And a construct can parse whole with its external
blind, because the press keeps an ordinary token for any spelling it can lex -
Swift's line strings work with all 33 externals blind - so `seated` is a floor
on capability too, and only a specimen settles a given construct.

The instrument that lied was this one, twice, both times understating. The first
gate read `outliner grammar`'s closing `note: external scanner tokens cannot be
lexed here: ...`, which reads exactly like the blind set and is not it - on
julia that note names all sixteen declared externals where `lex` and `parse`
both report **five**. It is a restatement of `externals[]` wearing a blindness
sentence, and believing it produced the headline **`declared 461 seated 0`**:
this tree can lex none of the externals it declares, false by a factor of
infinity, and it would have been repeated downstream. It was caught only because
`julia/command.jl` passes 6/6 and a grammar that can lex nothing cannot pass a
specimen. The second lie was smaller and the same direction: the row pattern
reading `parse --ranges --all` did not allow a `field: ` prefix, so on Swift it
read a forest containing `value: line_string_literal [18, 32)` and reported the
literal absent - 0/6 specimens sound became 2/6 on a one-line fix.

Also recorded, because it cost a morning: rename ablation is **unsound** as a
coverage oracle. A one-character case change to one blind Kotlin external took
its blind count from 8 to 10, because `provision` requires a troupe's full cast
and losing any member unseats every other member with it. It survives in
`verify` for the one job it is honest at - deliberately breaking a hand, then
watching `command.jl` drop from 6/6 to 0/6, which is the anti-vacuity assertion
proving the tier notices a regression rather than arguing that it would.
