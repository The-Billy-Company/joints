Kotlin was two spellings short of a whole tree.

Treatment `outliner d95f68e4a` · tree `b8757cdcc` (pin) · oracle `d85e736fa`
(30 of 30 live, 30 attributed), against control `outliner 1885792a7` · tree
`4f018b60f` on the same oracle. `still against` reads comparable: one file
differs and this lane claims it.

Kotlin stopped on the dot in `import kotlin.contracts.*` because `_import_dot`
is one of the ten terminals it hands to a C external scanner and the roll in
`src/kernel/lex/outside.zig` had no row for it. It is not an exotic byte - it is
a dot that is only legal inside an import, which is the roll preamble's own
case, since lexing here is state-directed and the parse state's permission set
is exactly the context that scanner was reaching for. Seated `_import_dot` and
`_primary_constructor_keyword` (the word `constructor`) as unguarded rows, so
both defer to anything the grammar spelled itself. Kotlin's third external,
`_by_delegation_hint`, gets no row and needs no hand either: its own scanner
never emits it. It is declared so it shows up in `valid_symbols`, where the
automatic-semicolon branch reads it as a flag for "we are in a delegation
context", so it is not a token at all and nothing could stand in for one. Blind
goes 3 -> 1 and the 1 is honest.

Kotlin now reads `accepted, 1 root`, its `damage` goes 244 -> 0, and the board's
`reached whole` goes 17 -> 18. 29 of the 30 audit rows are byte-identical and
all 244 newly built bytes landed in `square`: corpus `crooked` holds at 33,653
exactly. `whole on ALL THREE` stays 17 - kotlin reads `trued 99.3%` on 186
crooked bytes it already carried before this change.

`research/joinery/kotlin/RESULT-1-dot.md` has the arm comparison, the per-bucket
delta, the four grammars whose verdict names a missing stand-in next, and what
I trust least - chiefly that one kotlin file exercises `_import_dot` and nothing
in the corpus exercises `constructor` at all.
