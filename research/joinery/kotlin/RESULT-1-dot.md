# Result 1 — kotlin was two spellings short of whole

Treatment arm `joints d95f68e4a` · tree `b8757cdcc` (pin) · oracle `d85e736fa`
(30 of 30 live, 30 attributed). Control arm `joints 1885792a7` · tree
`4f018b60f` · same oracle `d85e736fa`. `still against handoff kotlin-dot` reads
**comparable**: one file differs and this lane claims it.

## What was wrong

Kotlin read `damage 244` over two repairs and stopped one root short of whole:

```
scar 388..389 1B fell unexpected . in state 253, 1 heads, +44 tokens
scar 399..400 1B fell unexpected wildcard_import in state 436, 2 heads, +2 tokens
verdict: kotlin: lexer on . in state 253 [no stand-in for _import_dot, admitted by lookahead]
```

Byte 388 is the dot in `import kotlin.contracts.*`. The verdict names the cause
exactly: `_import_dot` is one of the ten terminals kotlin hands to a C external
scanner, joints links no tree-sitter runtime, and the roll in
`src/kernel/lex/outside.zig` had no row for it. The second scar is the first one
downstream - the `fell` restarted in state zero mid-import, so the `*` had
nothing to be a wildcard of.

Kotlin was blind to three terminals in all: `_primary_constructor_keyword`,
`_import_dot`, `_by_delegation_hint`. The other seven were already provided.

## Why a spelling is enough

This is the roll preamble's own case, not a new mechanism. Read what the grammar
does with them:

```
_import_identifier  ->  simple_identifier | _import_identifier _import_dot simple_identifier
import_header       ->  'import' _import_identifier ((_import_dot wildcard_import) | import_alias)? _semi
primary_constructor ->  ((modifiers? _primary_constructor_keyword) | BLANK) _class_parameters
```

`_import_dot` is a dot. `_primary_constructor_keyword` is the word
`constructor`. Neither is an exotic byte sequence - both are ordinary spellings
that are **only legal somewhere**, and a tree-sitter grammar has no way to say
where, which is the whole reason the author wrote C. Lexing here is
state-directed, so the parse state's permission set *is* the context that
scanner was reaching for: `_import_dot` appears in exactly two rules, both under
`import_header`, so the only dots a state admits it at are the dots inside an
import path.

Neither row states trailing context, so by `outside.guards` both are unguarded
and **defer to anything the grammar spelled itself**. Where a state admits the
literal `.` or a `simple_identifier` as well, the grammar's own terminal still
wins; these fire only where it has none. That is what makes a bare `\.` safe to
seat in a language whose member access is also a dot.

Each row carries a cohort of the other two, so it fires only for a grammar
declaring the whole set. No other grammar in the thirty declares
`_primary_constructor_keyword` or `_by_delegation_hint`, so the gate is tight.

## The third one gets no row, on purpose

`_by_delegation_hint` sits **before** the literal `'by'` in both rules that use
it:

```
explicit_delegation ->  (user_type|function_type) (_by_delegation_hint | BLANK) 'by' _expression_no_trailing_lambda
property_delegate   ->  (_by_delegation_hint | BLANK) 'by' _expression
```

A marker in front of a token it does not consume is zero-width, and the slate
must refuse a zero-length match. That is the hand seam's business, not a
spelling, and inventing a pattern for it would be a guess. It is optional in
both rules, so its absence costs no structure - kotlin still reads whole
without it. The blind count goes 3 -> 1 rather than 3 -> 0, and the 1 is
honest.

**Correction, after `scala/RESULT-1-strings.md`.** The action above is right and
the reason is wrong, which matters because the reason tells the next lane to go
build a hand. Kotlin's real scanner is on this machine - the differential
harness builds every grammar with its own C - and it says so itself:

> `BY_DELEGATION_HINT` is declared in the grammar (optional, before `by` in
> `explicit_delegation` and `property_delegate`) purely so it appears in
> `valid_symbols` when the parser is in a delegation context. The scanner never
> emits it; it's used only as a context flag in `scan_automatic_semicolon`.

So it is not a zero-width token awaiting a hand. It is **not a token at all**,
and there is nothing for any seam to stand in for. No row, no hand, and the
blind count of 1 is not a debt.

The same reading tightens two other claims below. `_primary_constructor_keyword`
requires a word boundary the C tests explicitly (`matched &&
!is_word_char(lookahead)`) and my bare `constructor` does not - it is safe only
because `simple_identifier` is longer at that offset and an unguarded row defers
to it, which is the argument I gave, not the one the C gives. And
`scan_import_dot` does more than match a dot: it refuses dots that would let a
malformed import bleed into the next statement, and emits an automatic semicolon
instead when a newline and `import` follow. My `\.` models none of that refusal.
Neither gap shows on this corpus; both are now read rather than assumed.

## What it bought

`still against` reads **comparable** - `src/kernel/lex/outside.zig` is the only
file that differs and this lane claims it. Both arms carry oracle `d85e736fa`,
so the judge is held constant. Diffing every audit bucket across all thirty
rows:

| bucket | before | after | delta |
|---|---:|---:|---:|
| built | 35,571 | 35,815 | **+244** |
| square | 35,324 | 35,568 | **+244** |
| crooked | 186 | 186 | 0 |
| soft | 61 | 61 | 0 |
| unframed | 0 | 0 | 0 |
| unaudited | 0 | 0 | 0 |

**29 of the 30 rows are byte-identical**; kotlin is the only one that moved, and
corpus `crooked` holds at 33,653 exactly. So all 244 bytes went to `square` -
every byte this change built, the oracle defends. That is the opposite outcome
to `haskell/RESULT-2-cost.md`, where a commit built 6,008 bytes and gained
**zero** square; the distinction the three-axis board exists to draw, drawn in
the paying direction for once.

Kotlin's verdict is now `accepted, 1 root, surveyed 8627 of 9676 nodes`, its
`damage` is 0, and the board's `reached whole` goes **17 -> 18**.

## What it did not buy

`whole on ALL THREE` stays at **17**. Kotlin reads `trued 99.3%`, because it
carries **186 crooked bytes - and it carried all 186 before this change too**.
That is a pre-existing disagreement this lane neither caused nor fixed, and the
board now names kotlin in a list it was previously too broken to appear on:
*"2 row(s) cost more wrong than missing and are placed by `crooked`: swift,
kotlin"*. Closing kotlin's third axis is a separate lane, and it now has nothing
in front of it.

## What the next lane inherits

The same verdict line names a missing stand-in for four other grammars, and
each is a different amount of work:

| grammar | missing at the first wall | spellable? |
|---|---|---|
| scala | `_simple_string_start` | one of 21 blind, the rest string machinery |
| ruby | `heredoc_beginning` | the opener is, the body needs the tag - hand seam |
| bash | `_concat` | no - zero-width, hand seam |
| haskell | `_cond_qual_dot` | no - conditional, hand seam |

sql looked like a fifth and is not: its three blind terminals are all
dollar-quoted string machinery (`$tag$ ... $tag$`, stateful), while its actual
first refusal is `_identifier`, which is not external at all. Different defect,
different lane.

## What I trust least

**One file per grammar.** `Maps.kt` uses `_import_dot` and does not use
`_primary_constructor_keyword` anywhere - the corpus proves the first row and
merely fails to contradict the second. I seated `constructor` on the same
reading of the same grammar rule, and the honest statement is that it is
unexercised by any measurement here. A kotlin file with a primary constructor
would be the falsifier and the corpus does not hold one.

**The safety of the bare `\.` rests on an argument, not a sweep.** I argued it
from `outside.guards` (unguarded rows defer to the grammar's own terminals) and
from `_import_dot` appearing in only two rules. The 29 byte-identical rows prove
no *other grammar* moved, which the cohort gate already guaranteed; they prove
nothing about a kotlin file whose import list is followed by member access the
lexer might now see differently. Only one kotlin file was read.

**`trued 99.3%` is not this lane's number to be proud of.** The 186 crooked
bytes were there before, so the change is a clean `+244 square`. But kotlin
appearing on the `crooked` list for the first time is a consequence of it
finally building a tree, and a reader skimming the board could easily charge
those 186 bytes to this commit. They are not its.
