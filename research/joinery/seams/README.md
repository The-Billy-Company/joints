# seams — the four externals php's lane handed on

php's `scan_encapsed_part_string` was worth 67,183 bytes in one change, and four
more externals came out of that lane wearing what looked like the same shape.
Two of them are seated here, and the useful half of the work is which two.

**elixir and latex are done.** `router.ex` goes from **1 square byte in 44,530
built** to `accepted, 1 root` and 23,228 square; `ltnews01.tex` from **108 in
4,061** to whole and 5,246 of 5,246 bytes matching tree-sitter's derivation, 0.0%
crooked. Corpus square 272,358 → **300,723**, unframed 41,467 → **12,506**,
standing 74.7% → **75.2%**, and two more grammars parse whole. Against an
isolation build, exactly those two move and no third moves one byte.

**bash and scala are not, deliberately.** bash is php's *surface* — three
terminals from one function on `valid_symbols` — and a different animal per byte:
three depth counters, an in-quote flag, and a refusal on the matched text rather
than on what follows. It is not `marrow` and it is not a `Provision` either,
because a pattern cannot say "a `$` not followed by `(`" and approximating it eats
the grammar's own `command_substitution`. scala *is* `marrow.Family` and needs two
widenings, then fails on a third thing neither reaches: its scanner carries an
`indents` array across calls and `marrow`'s walks are memoryless.

Neither mechanism was derived from the resemblance. Every terminal here was read
back out of the C, which is how 1f and 1g below died.

Predictions were written before the measurement that judges them, each naming the
number that would kill it.

| # | Prediction | Verdict | Result |
|---|---|---|---|
| 1a | elixir's `scan_newline` is a `caesura`, and the handover's zero-extent claim is wrong | held | [RESULT-1](RESULT-1-derivation.md) |
| 1b | the arm is chosen by a peek, and one of the three is ungated | held | [RESULT-1](RESULT-1-derivation.md) |
| 1c | elixir's wall is the binary-operator arm | held, **and incomplete — a second blind external behind it** | [RESULT-1](RESULT-1-derivation.md) |
| 1d | `defp f(x) do` is a different defect and survives | held | [RESULT-1](RESULT-1-derivation.md) |
| 1e | latex closes on a string, and one member closes on a command | held | [RESULT-1](RESULT-1-derivation.md) |
| 1f | bash's `regex` is php's family shape | **dead, twice** | [RESULT-1](RESULT-1-derivation.md) |
| 1g | scala is php's mechanism, and its wall is not | half dead | [RESULT-1](RESULT-1-derivation.md) |
| 2a | elixir passes 30,000 square | **dead — 23,228** | [RESULT-2](RESULT-2-numbers.md) |
| 2b | corpus square passes 305,000 and no other grammar moves | **dead, and the measurement was the wrong shape** | [RESULT-2](RESULT-2-numbers.md) |
| 2c | latex's `\iffalse … \fi` is the largest single piece | held — 990 of 5,246 bytes | [RESULT-2](RESULT-2-numbers.md) |
| 2d | the widening costs the single-byte closes nothing | held, measured | [RESULT-2](RESULT-2-numbers.md) |
| 2e | bash gains under 120 bytes and its wall does not move | half dead — wall right, attribution and price wrong | [RESULT-2](RESULT-2-numbers.md) |
| 2f | the two inherited guard holes close, and prove they can say no | both closed, one with a caveat | [RESULT-2](RESULT-2-numbers.md) |
| 2g | the folio hazard, obeyed rather than argued with | obeyed — **and the check I built on it was weaker than I claimed** | [RESULT-2](RESULT-2-numbers.md) |

## The two mechanisms, in one line each

**elixir — `caesura`, three seams, one peek.** `scan_newline` marks its end after
the newline *and* the inline-whitespace loop, then looks once to choose between a
comment, a `do`, and a binary operator. Its claim is the opposite of an automatic
semicolon's: ecma's seam says a statement ended, elixir's says it did not and the
next line resumes it. So the row carries `seams` and no `body` — a break followed
by none of the three is not a token, and the extras eat it.

**latex — `marrow.Family`, twelve rows, one walk, closing on a string.**
`Mark.shut` stayed the close's first byte and gained a `tail`; four call sites
read that byte and none of them changed. `Troupe.lone` carries the dispatcher's
own rule, which counts live symbols across all twelve and refuses on the second.
`_trivia_raw_fi` is in the roster — the opposite call from php's two heredoc
members, made on opposite evidence: the heredoc pair reads a tag stack, `\fi`
reads the same keyword loop as the other eleven and differs only in a parameter
of it. That difference is 990 of latex's 5,246 bytes.

Seating elixir also surfaced a **second** blind external, `_quoted_atom_start`,
which is not a hand at all — one byte plus a look at the next, so eleven lines in
`roll` beside ruby's `hash_key_symbol`. Naming one blind external correctly is not
knowing it is the only one, and that is where 2a died.

## What is deliberately not here

`specimen/bash/regex-in-test-command.sh` is a **handover, not a falsifier**, and
its `.expect` says so on line one: it is 0/6 today, cannot fall further, and
cannot tell a break from a baseline. Its job is to name the mechanism and price
it. The price is bash's whole **413-byte** damage, and the board's
`unexpected [ at 565` is the `[` of `[0-9]` inside `^-?[0-9]+$` — not `_concat`,
and not the `[[` of the test command, both of which the handover asserted.

scala has no specimen because the honest one would be a string with an escape at
a boundary, and writing it would invite seating a stateful scanner's string half
on a stateless mechanism. A separate lane also carries a 7× instability in the
board's scala reading (1,278 / 1,938 / 9,087), so no tail-row delta here could
have been believed.

## The pins every number here was taken against

A path is not a version in this tree, and two pinned binaries sharing an
`JOINTS_WORK` measure one side twice — always flatteringly. Each arm got its own
directory, started from empty, and every folio carries its minter's digest.

| arm | what | digest |
|---|---|---|
| before | `.local/lane-seat3/before-bin` | `5c962f8d` — the tree when this lane opened |
| iso | `.local/lane-seat3/iso-bin` | today's tree with my three rows deleted, plumbing left in |
| after | `.local/lane-seat3/after2-bin` | `15c266a9` |
| oracle | `attest.py freeze seat3` | frozen before any measurement |

**The `iso` arm was not in the plan and is the only one that attributes
anything.** Up to ten agents share this tree; between `before` and `after`,
siblings landed edits in `admit.zig`, `fence.zig`, `lexicon.zig`, `offside.zig`,
`scanner.zig`, a new `writ.zig`, and in `outside.zig` itself — whose `step` gained
an argument. Nine grammars moved in that pair and none of them were mine. It needs
a scratch tree rather than a revert for exactly that reason, rsynced beside the
repo so `../irregex` still resolves.

**The folio check is weaker than the hazard note implies.** A folio is the pressed
table, and a `Troupe` seat does not change one — latex's folio is byte-identical
between the arm scoring 108 and the arm scoring 5,246. Only the `roll` provision
moved a folio at all. Folio identity proves no table moved and says nothing about
whether a derivation did; the isolation build is what answered "no collateral
damage".
