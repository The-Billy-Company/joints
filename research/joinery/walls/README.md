# The wall board

Every distinct wall the tail holds, grouped by the **shape** of the terminal
that was refused, because the same shape is the same defect wherever it turns
up: `(?:[^\"\n]+)` is one bug with five witnesses, not five bugs.

**The tables are rendered, not typed** - `python3 tool/walls.py board
--from-json .local/walls/survey.json`, over a survey taken with `python3
tool/walls.py --depth 400 --json`. Re-render them rather than editing them; the
classifier is `FAMILY` and `family()` in `tool/walls.py`, and it is one table on
purpose so it can be argued with in one place. The prose above and below them is
written, and re-rendering is a splice between the two `---` rules.

**Read the count as a floor, and read the families as the answer.** The peel
resumes from a clean start, so a wall that only exists after four thousand lines
of accumulated context is invisible to it. `python3 tool/walls.py warm` measures
how far that undercounts by never restarting - it parses the whole file each
round and blanks the offending byte - and over 900 rounds on the three hardest
grammars it reached **31 walls the cold peel could not**, still arriving at
round 219 of 300 at a back-half rate of 1.3 to 2.7 per hundred.

So the total is a floor that grows with how long anyone peels. **The families
are not.** Every one of those 31 landed in a family that already existed here,
and the states repeat - one state refusing eleven terminals is one broken state.
Quote the family table and the rate; do not quote the total. A sixth family
appearing is the finding that would matter, and `python3 tool/walls.py gate` is
now what fails when one does - fixed roster, fixed 40 rounds, both peels, in CI.
It does not gate the total, for the reason above: that would go red on a longer
budget with nothing wrong.

## 58 of these are the peel restarting, not the parser failing

**18% of the board is an artifact of how it was measured.** The cold peel
resumes from a clean start, so round two onward begins in **state 0** holding
the middle of a construct. A sql start state refusing `end`, `else` and `or` is
not a defect; it is the correct behaviour of a grammar being handed the second
half of a statement.

Two checks say so, and they agree:

- **No grammar's *first* wall is in state 0.** Round one parses the whole file
  from byte 0 and is the only round that could honestly land there. Not one of
  the nineteen does.
- **The warm peel, which never restarts, produces zero state-0 walls** - against
  nine of haskell's ten from the cold peel.

So the honest figure is **257**, and haskell is genuinely one wall deep rather
than ten. The families below still hold; the largest correction is to sql (22 of
its 31) and haskell (9 of 10). This is the third instrument bias found by asking
whether a number is a floor or a ceiling, and the first one that made us look
*worse* than we are.

---

## Re-surveyed after the mask landed: the board moved, and the way it moved is the point

Everything below was measured against `60f59cb48`, before the scanner lane's
reachability mask reached the folio. Re-run against `79741763d`:

| | before | after |
|---|---:|---:|
| real walls | 257 | **269** |
| state-0 artifacts dropped | 58 | 74 |
| **permissive body pattern** | **105** | **33** |
| bracket refused | 63 | 70 |
| separator refused | 56 | 72 |
| named terminal | 55 | 43 |
| unrunnable external | 33 | 41 |
| string delimiter | 3 | 8 |

**The family the fix targeted fell by two thirds; the total went up.** Both are
the same event. A permissive body pattern that no longer swallows to end-of-file
stops being refused *and* stops hiding what is behind it, so the parse reaches
further into each file and meets walls that were never previously reachable. A
shrinking family beside a growing total is what a real fix looks like on this
board, and it is why the total was never the number to quote.

**This also answers the standing question about the work list.** The board is
measured through folios; the two paths were checked wall-for-wall over nine
grammars and agree exactly, so the list is not path-dependent. It *is* fix-
dependent, and it moves in the direction the fix predicts. `walls.py gate` now
carries the parity check so a divergence between the two paths fails rather than
being noticed a quarter later.

**Two walls now classify as nothing, and that is the alarm working.** Verilog's
`'2` in states 1328 and 534 - a based-literal prefix, punctuation glued to a
digit, neither a word nor pure punctuation. Read rather than shape-matched, as
the 59 were: both states admit **2 terminals of 444**, both are "after a comma,
expecting the next declared variable's name". By this board's own width rule
that is a repair cascade - a consequence of an earlier mis-repair, not an
independent defect - so it is **not** a sixth family and it is not work anyone
should schedule. The classifier was right to refuse to name it and the gate was
right to raise it. Note that the gate's fixed 40-round budget does not reach
these two, which the deeper `run` survey does: the gate proves closure *at its
budget*, and the survey is what finds the surprise.

---

315 distinct (terminal, state) walls over 19 grammars, by family.

| family | lane | walls | shapes | grammars |
|---|---|---:|---:|---|
| permissive body pattern | **scanner** | 105 | 22 | 16: c, cpp, elixir, go, haskell, kotlin, latex, ocaml, php, python, ruby, scala, sql, swift, verilog, zig |
| unrunnable external | **scanner** | 33 | 33 | 5: elixir, julia, markdown, scala, sql |
| bracket refused | **weave** | 63 | 8 | 14: bash, cpp, elixir, go, julia, kotlin, latex, ocaml, python, ruby, scala, sql, verilog, zig |
| separator refused | **press** | 56 | 12 | 12: cpp, elixir, go, haskell, julia, kotlin, ocaml, python, ruby, scala, sql, verilog |
| string delimiter | **scanner** | 3 | 1 | 2: c, cpp |
| named terminal | **unassigned** | 55 | 44 | 10: bash, elixir, haskell, julia, kotlin, latex, ocaml, scala, sql, verilog |

### permissive body pattern - scanner

a pattern that matches a run of anything-but-a-delimiter. This is the same family as the throughput defect: a permissive member survives to end-of-file, and bounding the walk is what stops it both refusing and costing.

| terminal | walls | grammars |
|---|---:|---|
| `xml_text` | 28 | scala |
| `(?:[^\\"]+)` | 14 | swift |
| `(?:[^\r\n]*)` | 12 | kotlin |
| `(?:[^\\"\n]+)` | 11 | c, cpp, verilog, zig |
| `(?:[^\\"%@]+\|%\|@)` | 7 | ocaml |
| `uninterpreted` | 6 | ruby |
| `(?:[^`]*)` | 4 | go |
| `(?:[^{}\n]+)` | 3 | python |
| `_comment_text` | 3 | scala |
| `macro_text` | 3 | verilog |
| `(?u:[_\p{Ll}\p{Lm}\p{Lo}\p{Nl}\x{1885}\x{1886}\x{2118}\x{212E}\x{309B}\x{309C}][\p{ID_Continue}]*[?!]?)` | 2 | elixir |
| `(?:[^\\'\r\n])` | 2 | ocaml |
| `escape_sequence` | 1 | c |
| `(?::\s)` | 1 | elixir |
| `(?:\r?\n)` | 1 | elixir |
| `(?:\()` | 1 | haskell |
| `word` | 1 | latex |
| `(?:[^\s<][^<]*)` | 1 | php |
| `(?:([uU]&\|[nN])?'([^']\|'')*')` | 1 | sql |
| `(?:[bBxX]'([^']\|'')*')` | 1 | sql |
| `(?:[iI][nN][tT])` | 1 | sql |
| `keyword_text` | 1 | sql |

### unrunnable external - scanner

no terminal was producible at that byte at all, which on a grammar that declares externals is the stand-in machinery rather than the table.

| terminal | walls | grammars |
|---|---:|---|
| `stray b':'` | 1 | elixir |
| `stray b'A'` | 1 | julia |
| `stray b'B'` | 1 | julia |
| `stray b'D'` | 1 | julia |
| `stray b'E'` | 1 | julia |
| `stray b'S'` | 1 | julia |
| `stray b'T'` | 1 | julia |
| `stray b'a'` | 1 | julia |
| `stray b'b'` | 1 | julia |
| `stray b'c'` | 1 | julia |
| `stray b'd'` | 1 | julia |
| `stray b'e'` | 1 | julia |
| `stray b'f'` | 1 | julia |
| `stray b'g'` | 1 | julia |
| `stray b'h'` | 1 | julia |
| `stray b'i'` | 1 | julia |
| `stray b'j'` | 1 | julia |
| `stray b'l'` | 1 | julia |
| `stray b'm'` | 1 | julia |
| `stray b'n'` | 1 | julia |
| `stray b'o'` | 1 | julia |
| `stray b'p'` | 1 | julia |
| `stray b'q'` | 1 | julia |
| `stray b'r'` | 1 | julia |
| `stray b's'` | 1 | julia |
| `stray b't'` | 1 | julia |
| `stray b'u'` | 1 | julia |
| `stray b'v'` | 1 | julia |
| `stray b'y'` | 1 | julia |
| `stray b'\n'` | 1 | markdown |
| `stray b'\x80'` | 1 | scala |
| `stray b'\x94'` | 1 | scala |
| `stray b"'"` | 1 | sql |

### bracket refused - weave

an opener or closer the state would not take. zig's `{` in 715 was already here as `offer()`; every other grammar in this row is a second witness.

| terminal | walls | grammars |
|---|---:|---|
| `)` | 26 | elixir, julia, kotlin, ocaml, python, scala, sql, verilog |
| `}` | 17 | bash, cpp, elixir, go, julia, kotlin, latex, ocaml, scala, zig |
| `]` | 6 | elixir, julia, ocaml, sql |
| `(` | 5 | elixir, kotlin, ocaml, scala, verilog |
| `[` | 4 | bash, elixir, ruby, sql |
| `{` | 3 | go, ocaml, zig |
| `]]` | 1 | bash |
| `*)` | 1 | verilog |

### separator refused - press

a comma, semicolon, colon, dot or operator refused where the table should have shifted it - a lookahead or merge question, not a lexing one.

| terminal | walls | grammars |
|---|---:|---|
| `,` | 18 | elixir, go, haskell, julia, kotlin, ruby, scala, sql, verilog |
| `:` | 9 | kotlin, ocaml, python, verilog |
| `=` | 8 | julia, kotlin, python, scala, sql |
| `.` | 7 | elixir, haskell, julia, kotlin, sql |
| `;` | 4 | cpp, julia, sql, verilog |
| `<` | 2 | kotlin |
| `>` | 2 | kotlin |
| `@` | 2 | kotlin |
| `'` | 1 | julia |
| `->` | 1 | kotlin |
| `*` | 1 | sql |
| `&&` | 1 | verilog |

### string delimiter - scanner

the quote that opens or closes the run a permissive body pattern matches. One machine with the body, so it is the same lane - c and cpp carry both halves and it would be perverse to route them apart.

| terminal | walls | grammars |
|---|---:|---|
| `"` | 3 | c, cpp |

### named terminal - unassigned

a keyword or a named terminal. No single lane owns these by shape; each needs reading, and they are the residue this classifier will not guess at.

| terminal | walls | grammars |
|---|---:|---|
| `_identifier` | 4 | sql |
| `public` | 3 | kotlin |
| `_lowercase_identifier` | 3 | ocaml |
| `keyword_rollback` | 3 | sql |
| `in` | 2 | julia |
| `_alpha_identifier` | 2 | kotlin, scala |
| `variable_name` | 1 | bash |
| `alias` | 1 | elixir |
| `atom` | 1 | elixir |
| `false` | 1 | elixir |
| `fn` | 1 | elixir |
| `integer` | 1 | elixir |
| `calling_convention` | 1 | haskell |
| `d` | 1 | haskell |
| `e` | 1 | haskell |
| `name` | 1 | haskell |
| `t` | 1 | haskell |
| `variable` | 1 | haskell |
| `_delimiter_str_1` | 1 | julia |
| `_power_operator` | 1 | julia |
| `as` | 1 | julia |
| `do` | 1 | julia |
| `get` | 1 | kotlin |
| `internal` | 1 | kotlin |
| `quest` | 1 | kotlin |
| `return` | 1 | kotlin |
| `wildcard_import` | 1 | kotlin |
| `\documentclass` | 1 | latex |
| `command_name` | 1 | latex |
| `_uppercase_identifier` | 1 | ocaml |
| `_natural_number` | 1 | sql |
| `keyword_array` | 1 | sql |
| `keyword_as` | 1 | sql |
| `keyword_else` | 1 | sql |
| `keyword_end` | 1 | sql |
| `keyword_in` | 1 | sql |
| `keyword_main` | 1 | sql |
| `keyword_off` | 1 | sql |
| `keyword_or` | 1 | sql |
| `keyword_procedure` | 1 | sql |
| `begin` | 1 | verilog |
| `end` | 1 | verilog |
| `endcase` | 1 | verilog |
| `endtask` | 1 | verilog |

**315 walls, 6 families, 120 distinct terminals.** 55 sit in the unassigned residue, which is the honest size of what shape alone cannot route.

---

## The 59 unassigned, read one at a time

Shape could not route them, so I read them - `outliner state <grammar> <n>`
prints the items and the row, which turns "a named terminal was refused" into
"here is what the state wanted instead". **It is the admitted set that carries
the diagnosis, not the refused terminal**, and that reframing does most of the
work below. **No new kind of difficulty turned up** - three causes, 19 of the 59
were the state-0 artifact above, and the one family that did get added (`string
delimiter`) is a shape the classifier should always have had rather than a
sixth kind of problem. That is why the gate keys on shapes nothing claims and
not on the number of families.

### (a) 6 walls, 3 states: the state wanted a terminal the scanner cannot make

The refused token is a red herring. These states admit **externals and nothing
else**, so no lexable byte on earth would have continued the parse:

| state | admits, in full | refuses |
|---|---|---|
| kotlin 110 | `_automatic_semicolon` | `@`, `internal`, `public`, `)`, `,`, `}` |
| kotlin 946 | `_automatic_semicolon` | `_alpha_identifier` |
| latex 537 | `_trivia_raw_env_verbatim` | `\documentclass`, `command_name` |

kotlin state 110 is the exhibit for the whole board: `source_file_repeat2 ->
_statement . _semi`, one admitted terminal, and **six distinct walls** that are
one cause with six witnesses. This is the `unrunnable external` family wearing
six different terminal names, and it is **scanner's** - the same automatic-
semicolon stand-in yaml needs at 113-of-113.

### (b) 3 walls: `"` in c and cpp is the string family's other half

c 523 and cpp 935/1513 refuse `"`. c and cpp already carry `(?:[^\\"\n]+)` in
the permissive body family - the body of the run that `"` opens and closes.
Delimiter and body are one machine and one lane. `family()` now has a **string
delimiter** row so this routes by shape rather than by reading, and it is
**scanner's**.

### (c) 31 walls: genuine table refusals, and 14 are a repair cascade

These are the residue that is really residue. The useful split inside it is the
**width of the admitted set**:

| | walls | reading |
|---|---:|---|
| state admits ≤ 4 terminals | 14 | the parse is somewhere it should not be |
| state admits 5-66 | 17 | a real refusal worth arguing about |

The narrow ones are consequences, not causes. verilog 562 is
`net_decl_assignment -> _identifier .` admitting `, = ; [` and refusing `begin`,
`end`, `endcase`, `endtask` - and it is **right to**, because after `wire foo`
you cannot write `begin`. The parser is inside a net declaration because an
earlier repair put it there. elixir 100 is the same story with a sharper edge:
`binary_operator -> operator_identifier . / integer`, exactly one admitted
terminal, refusing five ordinary expression starters. ocaml 239/240 likewise.

**Fix the upstream wall and these evaporate.** They should not be counted as
independent work, and a plan that treats all 315 as separate fixes is
over-counting by at least this much.

That leaves **17 walls in wide states** as the genuinely open named-terminal
question - sql's `_identifier` and `keyword_rollback`, kotlin's `wildcard_import`
and `public`, scala's `_alpha_identifier`. Those are contextual-keyword and
identifier-versus-keyword decisions, which is a press question. They are the
smallest of the three causes, and one of them - only **one** of the 40 - is a
declared external, so "these are all externals in disguise" is a tempting
hypothesis and a false one.

**59 → 6 scanner (one state), 3 scanner (string), 19 measurement artifact, 14
cascade, 17 press.** The last structural unknown on the board is closed, and the
part of it that is real work is 17 walls, not 59.

## Who holds what, settled

So nothing here gets planned twice or planned at all when it should not be.

| item | walls | holder |
|---|---:|---|
| permissive body pattern | 33 | **scanner** - same shape as the throughput defect, and the mask already took it from 105 |
| kotlin's six walls in one state, and the three `"` delimiters | 9 | **scanner**, and it has them |
| bracket refused - `offer()` | 70 | **weave**, three witnesses: zig 715, go 188, and the `)`/`}` neighbours |
| separator refused | 72 | **Griffin** |
| identifier-versus-keyword, wide states | 17 | **Griffin** |
| unrunnable external, yaml at 113-of-113 | 41 | **scanner** |
| repair cascades, narrow states | 14 (+2 verilog) | **nobody - do not schedule these** |

The cascade row is the one worth reading twice. Those walls are real refusals and
they will disappear when the mis-repair upstream of them is fixed, so treating
them as work would be paying for the same defect a second time and then reporting
a fix that closed walls nobody had to close.
stamp: outliner cf9722c1d at /Users/griffinstrier/Billy-Company/outliner/zig-out/bin/outliner built 2026-08-05T04:41:11Z from . 3e819413d · repo fd73da392+44 · run 2026-08-05T04:43:40Z
