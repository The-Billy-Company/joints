`built`, `orphan`, `rubble` and `spoil` all answer *where did this byte end
up*. None of them answers *should it have*, and a wrong tree is still a tree —
so a Swift comment read as a `prefix_expression` over a
`multiplicative_expression` costs zero mends, yields one clean root, and scores
better than the honest failure it should have been. `tool/plumb.py` walks every
byte the board calls `built` and asks tree-sitter what it puts there.

Measured on pin `plumb` (`dfc481e49`, tree `bd7b3e939`) against tree-sitter
0.26.11, 2026-08-05: of 363,987 built bytes, **222,024 plumb, 33,634 regrouped
(9.24%), 794 relabelled, 1,268 renamed, 71,580 interstice, 34,687 unjudged**.
The five partition `built` exactly; `built + orphan + rubble + spoil = 526,798`
and `standing = 69.09%` are untouched, read out of `standing.py` and reprinted,
and `plumb.py board` closes with three checks it fails on rather than asserting
that in prose.

**97% of it is one grammar and 97% of that is one token.** php declares twelve
externals and seats none; one of them, `encapsed_string_chars`, is the body of
a double-quoted string, so php cannot lex `"x"` at all. That alone would cost a
few bytes. What it costs is everything downstream, because `text` — php's node
for inline HTML *outside* `<?php`, rule `[^\s<][^<]*` at precedence 1 — is the
mender's cheapest landing. In `Str.php` the first double-quoted string is at
byte 26,850 and the 40,995 bytes after it become one `text` node under a
`program` root with a child, which is the board's definition of `built`. php
reports **87.2% standing** while more than half of what it claims to have read
is filed as raw HTML. The recovery does not orphan the remainder; it claims it.

**Where it goes the wrong way.** The number is a floor, and the exhibit is
`research/joinery/specimen/go/selector-field.go`: go is 100.0% standing, zero
damage, parses with zero mends, and reads `fmt.Print("x")` as a
`type_conversion_expression` over a `qualified_type` — a cast, not a call.
`plumb` scores that file at **5 misread bytes of 996**, the length of `Print`,
because it is the only *leaf* whose name moves and every other byte sits under
a leaf both parsers agree on. A byte-indexed comparison cannot see a wrong
shape over right leaves, which is the same blind spot one level up that `built`
has over wrong trees. Byte-indexing was chosen because outliner returns a
forest on 18 of 30 grammars and aligning 3,544 roots is a guess; the cost is
that a tree-aligned lane will report a larger number than 9.24%.

**The instrument lied first, exactly where it was predicted to.** The
prediction file named the falsifier in advance: the red tripwire is a Swift
comment whose wrong tree is written out by hand two directories away, and on
the first run it reported **0 askew and passed**. `measure()` looked the folio
up by the row's *label* (`swift-comment`) rather than its *grammar* (`swift`),
found none, returned `None`, and the assertion read `None` as agreement — an
instrument built to catch describing-wrong spent its first run describing a
known-wrong tree as right. `verify` now asserts a row was produced at all
before asserting anything about it.

The second lie was quieter and moved a conclusion. The first draft had one
disagreement class, and swift came out second-worst in the corpus — on 1,096
bytes that are method names outliner resolves to `type_identifier` where
tree-sitter leaves `simple_identifier`, a rename **swift's own grammar
declares**. Splitting `renamed` off the `ALIAS` table, and `relabelled` off
`regrouped` by extent, is what moved swift from second-worst to sixth at 117
bytes. The observation this lane was opened on is real and reproduces; as a
share of the corpus it is 0.6%, and saying so is the finding.

Three specimens carry it, all failing today and all asserting tree-sitter's
answer rather than outliner's: `php/double-quoted-string.php` (6 claims),
`php/text-swallows-remainder.php` (4), `go/selector-field.go` (8, of which
`roots 1` and `mends 0` pass).
