# RESULT 1 — the derivations, scored

Every claim in `PREDICTION-1-derivation.md`, judged against what the code and
the board actually did. Four held, three died, and the three that died are the
useful part.

## 1a — elixir's `scan_newline` is a `caesura`, and it is not zero-extent — **HELD**

Seated as `caesura.Tongue.elixir` with three seams. The extent correction was
load-bearing: `mark_end` comes after the newline **and** after the inline
whitespace loop, so the token routinely claims 7 bytes on `router.ex`. Nothing
structural had to change for that — `caesura.Break` already carried `skip` and
`len` for swift's spelled `;` — but a zero-extent ledger would have bounded it
wrongly.

What the row *did* need was `seams`: three names, one function, and no implied
fourth. elixir's break is the opposite claim from an automatic semicolon. ecma
says a statement ended; elixir says it did **not**, and the next line resumes
it. A break followed by none of the three is not a token here at all — the
extras eat it and nothing is owed — which is why the row has no `body`.

## 1b — the arm is chosen by a peek, and the comment arm is ungated — **HELD**

The C reads one byte after the mark and dispatches. The comment arm reads no
permission set, which is a slip in the specification, and I narrowed it: the arm
is gated on `valid_symbols` anyway, because handing back a token the state must
reject is worse than staying silent. Same call `spelt` already documents for
julia's `_end_str`.

## 1c — elixir's wall is the binary-operator arm — **HELD, AND INCOMPLETE**

Seating the arm moved the wall off 17,006. It did not make the file whole: the
parse then walled at **22,229** with 76 roots, and `square` stayed at **one
byte** even though `damage` fell 1,559 → 583 and roots fell 255 → 76.

Byte 22,229 is the `:` of `:"__match_route_#{verb}__"` — a **second** blind
external, `_quoted_atom_start`, which I had not named. It is not the caesura's
mechanism and not a hand at all: the C advances one byte over the `:`, calls
`mark_end`, and then only *looks* at the next byte, returning true for `"` or
`'`. A spelling plus trailing context — `outside.Provision`, the same shape
ruby's `hash_key_symbol` already uses, and eleven lines of data.

`router.ex` holds exactly two of them (22,229 and 24,175). Seating it took
elixir to **one root, zero damage, 100% standing** and `square` from 1 to
23,228.

**So the prediction was right about the wall and wrong about the file.** Naming
one blind external correctly is not the same as knowing it is the only one, and
the instrument that would have told me — `specimen.py coverage`, which reports
`declared` against `seated` per grammar — I ran only afterwards, where it says
elixir went `seated 20` to `seated 24`.

## 1d — `defp f(x) do` is a different defect and survives — **HELD**

`specimen/elixir/do-block-on-inner-call.ex` is 4/5 before and 4/5 after. elixir's
racked bytes did not come back as square; they went **up**, 17,654 → 22,724,
because the file now builds a whole tree over bytes that previously had no
parent to be wrong about. That is the honest shape of the win: 46,089 bytes now
judged where 44,530 were, 23,386 unframed bytes converted into a frame, and a
right-leaf-wrong-parent defect that is still there and still elixir's largest.

## 1e — latex closes on a string, and one member closes on a command — **HELD**

`Mark.shut` stayed a `u8` and gained `tail: []const u8` for the rest of the
close, plus `command: bool` for `\fi`. Twelve rows of data behind one walk, and
the dispatcher's "refuse if two or more are admitted" became `Troupe.lone`
rather than twelve `rival` entries — the C counts live symbols across the whole
roster and refuses on the second, so the whole-roster rule is what it says.

`_trivia_raw_fi` is in the roster, which is the opposite call from php's two
heredoc members and made on opposite evidence: the heredoc pair's first
statement reads a tag stack, so it is a fence wearing a family's name, while
`\fi` reads the same keyword loop as the other eleven and differs only in
`is_command_name`, a parameter of that loop.

## 1f — bash's `regex` is php's family shape — **DEAD, twice**

**The mechanism is not php's.** The surface is identical — three terminals, one
labelled block, dispatched on `valid_symbols`, every piece of state zeroed
inside the block. Underneath, there is no close for a roster to name. The C
keeps **three independent depth counters** plus an in-single-quote flag and
stops on the first closer that would go negative; `marrow` walks to a delimiter
the roster spells. And half the decision is a refusal on the *matched text*
rather than on what follows: a run of only `[A-Za-z0-9$_-]` is a word and not a
regex.

It does not fit `Provision` either, and the reason is a correctness hole rather
than an inconvenience. A pattern can carry depth-1 nesting. It cannot say "a `$`
that is not followed by `(`", which is what the C refuses on purpose —
`// do not parse a command substitution` — so that the grammar's own
`command_substitution` can take it. Approximating that eats a node we currently
build none of, which is the confidently-wrong shape the troupe contract calls
worse than silence. So bash stays blind, deliberately, and the specimen says so.

**And the wall attribution was wrong.** I wrote that `unexpected [ at 565` was
`_concat`, an `abut`. Byte 565 of `ledger.sh` is the `[` of the `[0-9]` **inside
the regex** — `if [[ ! $value =~ ^-?[0-9]+$ ]]`. Our forest over the same
construct in 44 bytes shreds [0, 24) into seven bare leaves with no
`test_command`, no `binary_expression` and no `regex`. So this mechanism owns
bash's wall after all, and its price is bash's whole 413-byte damage rather than
the ~120 I predicted.

That is the second time a lane has been wrong about bash by reasoning from a
neighbour instead of the bytes. I reasoned from the wall's *reported terminal*
without opening the file at that offset.

## 1g — scala is the same mechanism as php, and its wall is not — **HALF DEAD**

**Mechanism: held.** `scan_string_content(lexer, is_multiline, string_mode)` is
one function, six terminals, fixed priority, and `marrow`'s animal. It needs two
widenings, not one: `string_mode` is three-valued where `interpolates` is a
bool (in `RAW` a `\` is stepped over, in `INTERPOLATED` the same `\` *ends* the
run), and the close is a **different terminal from the content and is consumed**
— a single-line body returns `SINGLE_LINE_STRING_END` having eaten the quote,
where php and latex stop before the close and leave it to the grammar.

**"Its wall is not this mechanism": dead.** Byte 20,093 is inside `"None.get"`.
It is a simple string literal and it is exactly `scan_string_content`.

I still decline it, and the reason is no longer bytes. scala's scanner is the
only one of the four with **real memory** — an `indents` array, `last_column`,
`after_colon_eol`, and a `serialize`/`deserialize` pair over an indent stack.
php's four members and elixir's three seams were seated on the argument that a
scanner with no memory cannot answer differently for having been asked before
(`create` returns NULL, `serialize` returns 0). scala's does not meet that bar.
Seating its strings on `marrow` would take standing from a scanner half of which
is an offside machine, which is a different soundness argument from the two I
made today and belongs to whoever seats `INDENT`/`OUTDENT`. The 7× instability
in the board's scala reading is a second reason and the weaker one.

## Order of work, and where I departed from bytes

Ordered by square available, elixir (44,529) then latex (3,953) then scala
(9,218, declined) then bash (195, mispriced — really 413). I worked elixir,
latex, bash-derived-and-declined, scala-derived-and-declined.

The one departure from "order by bytes" is scala, ahead of bash on the board and
behind it here. The reason is the soundness bar above, not the size.
