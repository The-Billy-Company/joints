Swift could not read a second member of anything. Not a corner case: `let a = 1`
died on the `=`, one struct member parsed and two did not, and **a written `;`
died too**, because swift hands both `_implicit_semi` and `_explicit_semi` to its
external scanner and nothing else in its member rules spells a separator. So a
file could not say what the scanner refused to hear. 1,879 roots and 836 mends
over 813 non-blank lines, 27.4% standing.

Two mechanisms were missing and they are different mechanisms. `caesura.zig`
already answered javascript's zero-width semicolon; swift and kotlin need that
shape with a different rule, so it now selects among three transcriptions rather
than parameterising one. That matters because **swift's rule is the inverse of
ecma's**: javascript suppresses a break before a line resuming with an operator,
since `x\n + y` is one expression, while swift requires a binary operator to sit
on the line it continues - which is why `_plus_then_ws` is external and named for
its trailing whitespace - so swift inserts a separator before a leading `+`
quite happily. Only `?`, `:` and `{` suppress one. A parameterised rule would
have had to be wrong for one of them. A break also carries a width now, since a
written `;` is the same decision reached a second way with its own terminal.

The other half is 19 operator and keyword rows for swift, transcribed rather than
named. The scanner keeps three parallel tables - `OPERATORS` for the spelling,
`OP_SYMBOLS` for the terminal, `OP_ILLEGAL_TERMINATORS` for the refusal - and
`swift_roll` is those three joined at the index, so `where_keyword` is spelled
`where` because the scanner's table says so at that position and not because the
name ends in `_keyword`. Every refusal group turned out to be trailing context,
which `Provision.never` and `Provision.after` already had. These terminals are
external because swift lets you define operators, so `=~` is a user's operator
and `=` is assignment and only the next byte separates them.

Measured 2026-08-05, baseline 17:13Z against treatment 17:40Z on the same
commit. Swift 27.4% -> 81.2% standing and 77.0% -> 96.4% covered; built 7,795 ->
23,131, roots 1,879 -> 308, mends 836 -> 31. Kotlin unbound 3,847 -> 1,269.
Board unbound 134,630 -> 121,918, standing 62.1% -> 64.8%. Rubble and spoil both
fell rather than trading places (swift 4,931 -> 300 and 6,543 -> 1,040), which is
the opposite of what seating haskell's layout did, because swift's bytes were
already being *reached* - the parse was touching everything and structuring
almost none of it. Nodes described went up 2,881 (swift 3,950 -> 6,084) and bare
leaves went down 1,642 (swift 1,367 -> 179), so the lifted `built` is not a
policy reading less.

Where it goes the wrong way: **kotlin's `built` fell 1,075 bytes and its
`standing` fell three points**, even though its unbound fell 67% and its
code-rubble 82%. 3,653 bytes moved into `orphan` - KDoc comments the parse now
reaches and recognises, sitting as top-level leaf roots, which `standing` charges
the same as a lost construct. Part of that is a known watermark in the metric,
but `built` falling means bytes that were under a construct are not any more, and
that is a real if smaller regression inside the win. Kotlin's remaining wall is
its string troupe, which needs carried state.

Declined, with reasons: scala's `_automatic_semicolon` looks like kotlin's and is
not, because Scala 3's newline inference depends on the indentation region the
newline is in and a region is a stack - so it wants a layout troupe, not a
tongue, and its board row is byte-identical. Swift keeps 12 blind terminals: the
raw-string family and nesting comments need memory (`serialize` writes exactly
one `uint32_t`, the raw-string hash count, which is how we know those four are
the only stateful ones); `_custom_operator` is a whole-match filter against 31
reserved spellings, which trailing context cannot express; and `_bang_custom` is
conditioned on `FAKE_TRY_BANG` not being wanted, which is a question about the
parse table that a pattern cannot ask - seating it would lex the `!` of `try!` as
a postfix operator, a tree that parses and is wrong. That last one is priced
rather than asserted: walking all 3,416 states, the two are never shiftable
together and share an expected set in exactly one, state 42, so a bytes-only `!`
would match the real scanner everywhere but there. One state is not zero, so it
stays out. Each of these fails closed on its own already, since a blind external
is in no action row.

Two instruments lied. The brief this work started from stated that
`outside.Provision` requires a grammar's whole external cohort - all N or none -
and that is not the rule: `provisionFor` requires *a row's own* cohort, and eight
grammars were already running partially seated, bash at 3 of 4 and ruby at 3 of
7. A day could have gone into designing a fail-closed partial for a door that was
never shut. And `joints lex`'s blind count reported swift blind to
`_explicit_semi` while the parser was emitting it and the probes were passing,
because the count reads `claimed` and `claimed` did not know about the new role;
the census of the mechanism and the mechanism were two implementations of one
fact with nothing making them agree. It reads 12 now, matching the derivation.
