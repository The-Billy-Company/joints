# Prediction 1 — seating Kotlin's string fence

Written before a line of `fence.zig` or `outside.zig` was edited, after reading
the pinned `scanner.c` (979 lines) and the six red specimens, and after taking
the baseline board and the baseline specimen run. Each prediction names the
measurement that would falsify it.

## The baseline, so nothing here can be re-anchored later

Board, pin `kot-before` (tree `bd7b3e939`, binary `dfc481e49`), 2026-08-05:

```
built 363,987 of 526,798 = 69.09% standing · describes 97,595 nodes
kotlin  size 35,815  built 14,841  orphan 19,705  rubble 333  spoil 936
        roots 419  leaves 237  nodes 8,322  damage 20,974  standing 41.44%
swift   size 28,468  built 23,131  orphan  3,997  rubble 300  spoil 1,040
        roots 308  leaves 179  nodes 6,084  damage  5,337  standing 81.25%
```

Specimens: **7 of 17 sound**. All six Kotlin specimens red, 1 claim of 29
holding (`nested-interpolation.kt`'s `lacks lambda_literal`, which holds for the
wrong reason — that file builds no lambda because it never gets that far).

`Maps.kt` counted here rather than quoted: 35,815 bytes, **90 `"`, 0 `"""`,
0 `$`, 0 `\`**. The corpus is silent about every hard case.

## P1 — the greedy-close specimen's content claim contradicts the scanner

`greedy-close.kt.expect` asserts `spans string_content 11 13` for
`val t = """a""""`, derived from the Kotlin language reference and flagged in
its own comment as having no oracle behind it. Reading `scan_string_content`
as the specification, I predict the tree-sitter answer is **`string_content`
[11, 12) and `_string_end` [12, 16)** — the scanner emits the lone `a` as
content and then swallows *all four* quotes into the end token, because its
end-of-string branch does `while (lookahead == end_char) { advance; mark_end; }`
and its own comment says "there's no point in going to the effort of
specifically separating the string end from string contents".

`spans string_literal 8 16` — the claim that actually discriminates a greedy
close from a first-match one — holds under both readings.

**Falsified by**: compiling the pinned `scan_string_content` against a stub
`TSLexer` over `"""a""""` and reading where it marks end. If it marks 13, I am
wrong and joints owes [11, 13).

## P2 — five of six Kotlin specimens go green, and the sixth goes green but one

I predict `embedded-quote`, `escaped-quote`, `interpolation`,
`nested-interpolation` and `unterminated` reach full marks, and `greedy-close`
holds 4 of its 5 claims with only the P1 content span outstanding.

**Falsified by**: `python3 tool/specimen.py run`.

## P3 — kotlin's damage falls below 1,500 bytes

The orphan lane's length-preserving ablation put `built` at 35,569 with the
strings gone, i.e. damage 246. That was an ablation and not a measurement of
this fix — it measured a file with no strings in it, not a file whose strings
are read. I predict the seated fence lands **built ≥ 34,300 and damage ≤ 1,500**,
which is the ablation's number with room for the LR path differing.

**Falsified by**: kotlin's `damage` column on the board.

## P4 — `describes` rises by more than 400 nodes corpus-wide

Blanking the 45 literals to identifiers moved kotlin's node count 8,322 →
8,580 (+258). A seated fence builds `string_literal(string_content)` where the
ablation built a bare `simple_identifier`, so it should exceed that. If
`describes` falls while `built` rises, the fix is reading less and the whole
thing is void.

**Falsified by**: the `describes` line on the board.

## P5 — 29 or 30 of 30 grammars tree-identical, and only kotlin moves

`fence.read` is shared by python, ruby, rust\_raw and heredoc. Kotlin's greedy
close and its escape rule are both changes to territory those four stand on, so
this is the prediction most likely to fail and the one worth stating loudest.

**Falsified by**: a tree-by-tree compare of `parse --ranges --all` output over
all thirty corpus files, before against after. Not folio digests.

## P6 — the interpolation produces no zero-width run, so `Spent.ceiling` stays unexercised

The lane before me lowered its ceiling from 256 to 16 to 4 with every grammar
byte-identical, and asked whether Kotlin's interpolation would be its first real
exercise. I predict **not**: every answer my hand gives consumes bytes — `${`
is two, `$` before a name is one, content is at least one, the close is at
least one. The deepest zero-width run in the corpus should stay at three.

**Falsified by**: instrumenting `Spent.total`'s high-water mark over the corpus
and the specimens. Anything above 3 exercises the constant.

## P7 — `_import_dot` becomes the named wall on `Maps.kt` and is worth zero bytes

The orphan lane measured that removing `_import_dot` while leaving the strings
moved `built` by zero and moved `orphan` the **wrong** way, 19,705 → 19,730. I
predict that once the strings are seated, `inquest`'s verdict on `Maps.kt` names
`_import_dot`, and that it is still worth nothing.

**Falsified by**: the verdict string on kotlin's board row, and the residual
`damage` after the fix.

## P8 — seating Swift's `multiline_comment` *lowers* swift's `built`

`/* c\n d */` today parses as one root, zero mends, the comment read as
arithmetic — `prefix_expression` over `multiplicative_expression`. Those bytes
are counted `built`. Reading the comment correctly makes it a top-level extra
with no parent, which is `orphan`. I predict swift's `built` **falls** and its
`orphan` **rises** by roughly the comment bytes, and that this is a correction
rather than a regression.

**Falsified by**: swift's built/orphan columns. If `built` rises, the comment
was already attaching somewhere and my account of the mechanism is wrong.

## P9 — kotlin's bare leaves fall below 20

237 today; the ablation reached 5.

**Falsified by**: the `leaves` column.

## P10 — the board cannot see the half of this change that matters

`Maps.kt` holds zero `$`, zero `"""` and zero `\`, so a stateless
`"[^"]*"` regex would move every board number I predict above by the same
amount. I predict the board moves and the specimens are the *only* evidence
that the hand is sound.

**Falsified by**: nothing — this one is already settled by the character count
above. It is written down so that a reader of the result cannot mistake P3 for
the proof.
