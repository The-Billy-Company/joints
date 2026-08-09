# The rungs, and what each one is allowed to conclude

One rung per claim, cheapest first, each with a kill condition written before it
ran. `../joinery/TESTING.md` is the pattern and the reason: a rung that cannot
fail is a demonstration, and a demonstration proves the demonstrator.

Every number below was measured on this tree. Re-run rather than trust it.

---

## Rung 0 - the dossier · **passed**

**Question.** Is the memory the eight scanners keep expressible in a closed set
of typed organs, and is every decision a function of inputs we can name?

**Kill condition.** Any external whose decision requires an input outside
{bytes at or after the offset, line-start/indent/column facts, `valid_symbols`,
declared organs}.

**Method.** Read all eight `scanner.c` against what each one's own `serialize`
writes, since tree-sitter requires that to be the whole carried state.
[`CENSUS.md`](CENSUS.md) is the reading.

**Result.** Not met. Every decision reads only the named inputs; four cases came
close enough to write down (markdown's `simulate`, haskell's classified
lookahead, swift's comment depth living on the C stack outside `serialize`, and
`valid_symbols[error]`) and each resolves to something already in the set or to
an engine structure rather than an input. The organ set closes at **two stacks
and a register bank**, confirmed independently by four scanners that each keep a
`{kind, width}` stack under a different name.

**Two corrections to the roster the README was built on.** Of the eight
grammars named as keeping per-language state:

- **elixir keeps none.** `tree_sitter_elixir_external_scanner_serialize` is
  `return 0`. Its 26 externals are a delimiter table walked against the bytes.
- **html's memory is one stack joints already holds.** It sits at zero blind and
  parses `viewer.html` whole, 72,288 bytes, one root.

So the ceiling is six grammars, not eight.

**One addition to the instruction set**, forced by yaml and not by a preference:
a rule must be able to **rename its own answer** by running a second pressed
table over the text it matched. Six of yaml's terminals are one scan and a
schema classification, co-admitted by shift in all 19 states that admit any of
them, so nothing downstream can pick between them.

### The baseline every later rung is measured against

`python3 tool/census.py --set=breadth` and `python3 tool/plumb.py board`, both
captured under `.local/customary/`:

| grammar | externals | blind | board standing | where it stops |
|---|---:|---:|---:|---|
| yaml | 113 | 113 | 0.0% | no lexable terminal at all |
| markdown | 47 | 47 | 5.4% | stray byte at 20, 430 roots |
| haskell | 48 | 30 | 43.6% | `_cond_qual_dot` admitted by shift, no stand-in |
| scala | 25 | 17 | 100.0% | - |
| swift | 33 | 10 | 91.7% | a table wall at 24582, not a lexical one |
| elixir | 26 | 2 | 100.0% | - |
| kotlin | 10 | 1 | 100.0% | - |
| html | 8 | 0 | 100.0% | - |

Corpus-wide: **78.12% standing over 526,798 bytes**; 411,517 built, 20,319
orphan, 19,434 rubble, 75,528 spoil.

The addressable prize for this lane is the three rows that are not lexically
whole - yaml's 18,935 bytes at zero, markdown's 3,126 damage, haskell's 19,313
damage - which is 41,374 of the 115,281 bytes the corpus does not stand on.
scala, kotlin, elixir and html are already at 100%, so for them a customary has
to be *byte-identical* or it is a regression: they are the control arm.

---

## Rung 1 - two falsifiers, no Zig · **passed**

**1a - expressiveness.** An offline interpreter of the frozen instruction set
(`tool/customary.py`) executes draft customaries against tree-sitter's own token
stream over the corpus. *Kill: a mismatch no customary edit fixes* - which means
the algebra is short a test or an action and the census missed it.

**1b - composition.** Organ effects taken per segment and composed as stack
effects must reproduce whole-file organ state across arbitrary cuts. *Kill: a cut
where the product disagrees with the whole.* This is the `O(log n)` claim's
foundation and it needs neither parser nor oracle.

**Result.** Neither met. [`RESULT-1-algebra.md`](RESULT-1-algebra.md) is the
measurement. markdown: 10,568 observable answers, **0 missed**, and its 183
extra answers over 27 of 531 files reduce to **0** once the ask is fenced to
where a lexer is called and to terminals the covering rule can reach - this side
has no `valid_symbols`, and that is the whole residue. kotlin: 139 answers, **0
missed and 0 extra with no fence at all**, asked at every byte, so its delimiter
stack decides where a string ends without the parse table's help. Composition
held at **3,306 of 3,306** cut schedules, compared at every cut rather than only
at end of input.

The rung cost four widenings of the instruction set - `pass`, `nest`, `abstain`,
`span` - each one a case `CENSUS.md` had recorded without naming who would
execute it, and three of the four are *effects*, so rung 0's kill condition about
what a rule may **read** still stands after two full transcriptions.

## Rung 2 - the engine

Organs and interpreter at the seam `outside.step` occupies, a customary section
in the folio, exact save/restore through `Gather`, organ effects annotated on the
spine. *Kill: a measurable cost on a grammar with no customary.*

## Rung 3 - the six, in board order

markdown, then haskell, then yaml; scala/kotlin/elixir/html as the control arm
that must not move. *Kill: any grammar whose `trued` share falls.*

## Rung 4 - migration and the shake

Per-grammar tables out of the binary, `inquest` learns to say "answered by a
customary" apart from "blind", and the README's ceiling paragraph becomes a
status. *Kill: a fact the census can no longer report.*

## Rung 5 - the speed proof

Forward throughput against the C scanners, and the keystroke bench extended to
edits *inside* stateful regions, where the `O(log n)` claim is either observable
or it is not. *Kill: it is not.*
