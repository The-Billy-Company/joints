# PREDICTION 1 — what each of the four externals actually is

Written before any code changed. Derived from the C in
`.local/differential/lang/<name>/src/scanner.c` and from each grammar's own
`externals[]` / rule bodies, never from the name of the function the terminal
lives in. The php lane's bash prediction died because it reasoned from bash's
heredoc stack instead of re-deriving; so every claim below cites the line of C
that decides it.

## 1a — elixir's `scan_newline` is a `caesura`, and the lane's extent claim is wrong

**Claim.** The mechanism is `caesura` — a break decided by *what the parser
would accept next* rather than by the bytes alone. Three terminals from one
function, each gated on its own `valid_symbols` entry:
`_newline_before_comment`, `_newline_before_do`,
`_newline_before_binary_operator`.

**And it is not zero-extent.** The handover said:

> `scan_newline` calls `mark_end` immediately after the newline and its
> whitespace, then only *peeks* at the operator. Zero extent, no close.

The second half is right and the first is not: `mark_end` comes *after*
`advance(lexer)` over the newline **and** after `while (is_whitespace(...))
advance(lexer)`. Those bytes are claimed. The C says so in its own comment —
"we include all the whitespace after newline, so that the parser doesn't have to
go through it again". So the token's extent is the newline plus every following
whitespace byte, which on `router.ex` is routinely 7 bytes and not 0.

This costs nothing structurally, because `caesura.Break` already carries `skip`
and `len` for swift's spelled `;`. What it *does* cost is the assumption that a
caesura is the zero-width hand: `outside.step`'s zero-extent ledger will not be
what bounds this one, the cursor will.

**What will kill this prediction:** finding a `mark_end` before the whitespace
loop, or finding the three terminals reached from three different functions.

## 1b — the arm is chosen by a peek, and one of the three is ungated

**Claim.** After the mark, the C reads exactly one byte and dispatches:

| lookahead | arm | gated on `valid_symbols`? |
|---|---|---|
| `#` | `_newline_before_comment` | **no** |
| `d` | `_newline_before_do`, then `o` and `is_token_end` | yes |
| anything in the operator table | `_newline_before_binary_operator`, then `check_operator_end` | yes |

The comment arm reading no permission set is the specification's, and it is
almost certainly a slip in it. This tree's established answer to that is a
**narrowing** — guard on the permission set anyway, because handing back a token
the state must reject is worse than staying silent (`spelt`'s header says this
about julia's `_end_str`). I will narrow, and say so where it happens.

## 1c — elixir's wall is the binary-operator arm, and it is `\n |>`

**Claim.** The board's `unexpected alias at 17006 in state 100` is
`routes_with_exprs\n      |> Enum.map(...)`. `|>` lexes as `operator_identifier`,
which puts the parse in state 100 — `binary_operator -> operator_identifier . /
integer`, a state that accepts exactly one terminal (`/`, the arity slash) — and
`Enum` is not it.

Two of the three arms are **`extras`**, not members of any rule
(`_newline_before_comment` and `_newline_before_binary_operator` appear zero
times in `rules`), and `_newline_before_do` is one arm of a
`choice(_newline_before_do, blank)` in five call rules. My first reading of that
was that an extra which duplicates the plain `\r?\n` extra could not be
load-bearing. **That reading is wrong**, and the binary already says so:
`outliner parse` on `x =\n  a\n  |> f()` refuses at byte 13 and names the reason
itself — `[no stand-in for _newline_before_binary_operator]`. Reading the
grammar told me it could not matter; running the parser told me it does.

**What will kill this prediction:** seating the arm and finding the wall still at
17,006.

## 1d — `defp f(x) do` is a *different* elixir defect and is not mine

`research/joinery/specimen/elixir/do-block-on-inner-call.ex` scores elixir's
largest racked run: `defp f(x) do x end` hangs the `do_block` inside
`arguments`, with every one of its seven leaves agreed. There is no newline in
it, so `_newline_before_do` is not what decides it — the grammar takes the
`blank` branch and the block still attaches, just to the wrong call.

**Claim.** Seating the caesura fixes elixir's *wall* and its unframed root, and
leaves that attachment defect exactly where it is. So elixir's 17,654 racked
bytes will not all come back as square, and any report that says they did is
measuring something else.

## 1e — latex's family closes on a string, and one member closes on a command

**Claim.** All twelve of latex's externals are `find_verbatim(lexer, KEYWORD,
is_command_name)` — one walk, twelve rows of data, no state carried
(`serialize` returns 0). Each is a **required** member of exactly one rule, so
blind means that environment cannot parse at all. That is a `marrow.Family`, and
its `Mark` needs two things it does not have:

* a close of more than one byte (`\end{verbatim}`, `\end{luacode*}`, …);
* `_trivia_raw_fi`'s rule that `\fi` closes only when it is a whole command name
  — a following letter, `:`, `_` or `@` makes it content and the walk continues.

**Claim about the dispatch.** The C refuses outright when *two or more* of the
twelve are admitted at once (`if (found) return false`). That is `rival`
generalised from a named pair to "any two", and it wants its own field rather
than twelve `rival` entries.

## 1f — bash's `regex` is php's family shape, and it is worth almost nothing here

**Claim (mechanism).** `regex` / `_regex_no_slash` / `_regex_no_space` are three
terminals reached from one labelled block, dispatched on `valid_symbols`, with
every piece of state (`paren_depth`, `bracket_depth`, `brace_depth`,
`in_single_quote`, `last_was_escape`, `advanced_once`) declared and zeroed
*inside* the block. Memoryless. **php's family shape exactly**, as handed to me.

**Claim (value).** And it will not be worth doing first. bash's whole row is 655
built bytes, 460 already square, 0 racked, 118 unframed, and its wall is
`unexpected [ at 565 in state 1163` — which the binary attributes to
`_concat`, a zero-width adjacency marker and therefore `abut`'s animal, not
this one. `ledger.sh` contains exactly one regex, `^-?[0-9]+$`, 11 bytes.

**What will kill this prediction:** bash's wall moving when the regex family
seats, or the row gaining more than ~120 bytes of square.

## 1g — scala is the same mechanism as php and I am not going to claim its number

**Claim (mechanism).** `scan_string_content(lexer, is_multiline, string_mode)` —
one function, two parameters, six terminals dispatched on `valid_symbols` in a
fixed priority order, no state carried across calls. That is php's family shape
for the third time, and scala is therefore a fourth `marrow.Family`.

**Claim (why it does not fit today's `Mark`).** `is_multiline` maps onto `wide`
(1 vs 3). `string_mode` does **not** map onto `interpolates`, because it has
three values and the third changes the walk: in `STRING_MODE_RAW` a `\` is
stepped over (and a following `"` or `\\` with it), where in
`STRING_MODE_INTERPOLATED` the same `\` *ends the run* and is handed to the
grammar. A bool cannot hold that, so scala needs a three-valued mode — the same
correction `marrow`'s own header already made about julia: same table,
different walk.

**Claim (why I will not seat it).** scala's wall is `_simple_string_start` at
byte **20,093 of a 20,107-byte file** — the `"None.get"` in the last
declaration. Its 9,087 crooked bytes are all *upstream* of that, so they are not
this mechanism's to collect, and scala's board reading is the row under a
separate lane's 7× instability investigation (1,278 / 1,938 / 9,087). Seating
scala's strings here would buy a few dozen bytes and hand somebody a number
nobody can currently reproduce.

## Order of work, and the reason

By bytes available as square, against the frozen `seat3` oracle:

| grammar | built | square now | available | wall is this mechanism? |
|---|---|---|---|---|
| elixir | 44,530 | **1** | 44,529 | yes — `\n \|>` at 17,006 |
| latex | 4,061 | 108 | 3,953 | yes — `\begin{verbatim}` at 3,037 |
| scala | 15,957 | 6,739 | 9,218 | no — wall is the last 14 bytes of the file |
| bash | 655 | 460 | 195 | no — wall is `_concat`, an `abut` |

So elixir, then latex, then bash; scala derived and declined. The one place I
depart from "order by bytes" is scala, and the reason is in 1g: its number is
not this mechanism's and is not currently reproducible.
