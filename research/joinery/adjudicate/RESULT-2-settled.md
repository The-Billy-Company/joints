# Result 2 — the verdict on `settled`

**`settled` holds. `gap` should be retired.**

They are not the same claim, and separating them is the whole finding. The
previous lane named `settled` as the instrument it trusted least and asked for an
external check on the branch it gates. The check says the test is fine and the
**word bolted onto its output is false in 15 of 18 cases and 99.9% of the
bytes.**

## What `settled` actually asserts

```python
def settled(items: tuple[str, ...]) -> bool:
    return all(not item.endswith(" .") for item in items) and bool(items)
```

*Does this state hold an item with the dot at the end?* If it does, a fold could
have left the parse here, so the wall may belong to the fold rather than the
construct — that is `stranded`. If it does not, nothing completed, so the parse
shifted in and the refusal is about the construct.

**That is true, and it stays true.** The ambiguity it worries about (the printer
writes the dot as a bare `.`, and `.` is also a terminal, so `A -> b . .` reads
as complete under one of two readings) is resolved toward *unsettled*, the
direction that withholds a gap. It is conservative in the direction a
conservative test should be conservative. I found nothing wrong with it, and I
went looking with eighteen hand-authored witnesses.

## What is bolted onto it

```python
if not firm:
    return "stranded", "a fold can leave this state …"
return "gap", ("shifted into, nothing folded: outside FIRST(beta) and FOLLOW(A) "
               "over every item, so no LR parser over this grammar takes it here")
```

**"No LR parser over this grammar takes it here."** Tree-sitter is an LR parser
over that grammar. It takes it, on 15 of the 18. The sentence is not a
conservative approximation that occasionally over-claims; on this population it
is wrong far more often than it is right.

Three distinct leaps get you from a sound test to a false sentence.

### 1. The state is ours, and the state is the thing under test

`viable()` computes FIRST/FOLLOW over the grammar, but the **item set** comes
from `joints state <grammar> <n>` — our LR(0) collection, built by our table
construction, after our precedence handling and our conflict resolution. A
terminal outside a state's viability set is a fact about **the automaton we
built from the grammar**, not about the grammar.

This is the board's own documented blind spot one level up: `covered`, `spoil`
and `built` may not check each other because all three derive from the same
spans. `gap` derives its evidence from the parser whose defects it is being used
to rule out. A lane in `src/press/` is right now fixing a splice where
`variable_lvalue`'s `prec.left(37)` is erased by an intermediate rule's
`prec.left(0)` — a reading deleted with no conflict recorded. **A reading
deleted from the table is invisible to `viable()` and indistinguishable from a
reading the grammar never had.** That is `ours` reported as upstream's, by
construction.

39,503 B landed there.

### 2. The question is undefined once the lexer is wrong

Five of the eighteen walls refuse a terminal **the program does not contain at
that byte**: `/` inside `"/(.*)\s.*/"`, `%` inside `"total=%ld\n"`, `[` inside
`^-?[0-9]+$`, plain words inside `\begin{verbatim}`, and a comment-body pattern
standing where `startingAt:` is written.

Asked *"does the grammar derive `%` in this state"*, the closure correctly
answers no — because there is no `%` there. The verdict is sound about a
terminal that does not exist and is filed as a fact about a construct that does.
**No repair to `settled` reaches this**, because `settled` is answering the
question it was asked. The question is the defect.

### 3. `scanner` tests the wrong symbol

```python
if kin & g.blind:
    return "scanner", "a named external - tree-sitter runs a C scanner for it"
```

This asks whether **the refused terminal is itself** a declared external. It
cannot see the far more common case: a terminal refused *because an external
upstream of it was never produced*. php's `/` is not an external; the
`encapsed_string_chars` that should have swallowed it is. Six rows — **67,214
B, 62.9% of the adjudicated bytes** — are that shape, and every one of them was
filed `gap`.

This also rehabilitates the previous lane's worst-scoring prediction. It
predicted **≥ 45 scanner walls and found 9**, and recorded the miss as
better-than-2× wrong. The prediction was closer to right than the instrument
was: at least 6 more walls in this sample alone are the scanner's, and they were
invisible to a check that only matches the refused symbol's own name.

## The demonstration: one line, reproducible in isolation

`closure.py:346` builds the set of externals `scanner` consults:

```python
blind = frozenset(e["name"] for e in (g.get("externals") or [])
                  if isinstance(e, dict) and e.get("type") == "SYMBOL" and "name" in e)
```

Tree-sitter lets a grammar declare an external as a **literal** rather than a
named symbol, and those carry `"type": "STRING"` with a `value` and no `name`.
The filter drops them silently.

```
bash        29 externals,  6 dropped: '}' ']' '<<' '<<-' '(' 'esac'
scala       31 externals,  6 dropped: 'else' 'catch' 'finally' 'extends' 'derives' 'with'
python      12 externals,  4 dropped: ')' ']' '}' 'except'
ruby        30 externals,  1 dropped: '/'
ocaml        7 externals,  1 dropped: '"'
javascript   8 externals,  1 dropped: '||'
typescript  10 externals,  1 dropped: '||'
html         9 externals,  1 dropped: '/>'

across the corpus: 463 named externals seen, 21 literal externals dropped
```

**`GAPS.md` row 14 is `bash: ] in state 35`, 495 B.** `]` is one of the six bash
drops. It is a declared external. The `scanner` branch should have claimed it
and could not, because `g.blind` holds 22 of bash's 29 externals:

```
bash   ']'  spellings=['\]', ']']  blind-hit=[]  |blind|=22
```

Widen the set by one clause and the hit is there:

```
bash  named blind=22  widened=28  added=['(', '<<', '<<-', ']', 'esac', '}']
```

**And the widened verdict agrees with my witness.** I adjudicated bash
independently — a hand-authored `if [[ ! $v =~ ^-?[0-9]+$ ]]` that tree-sitter
parses clean and refuses with its scanner stubbed — and got `external`. The
one-line fix moves those 495 B from `gap` to `scanner`, which is the direction
the witness proves. That is a fix confirmed by evidence collected before the fix
was found.

The fix:

```python
blind = frozenset(
    e["name"] if e.get("type") == "SYMBOL" else e["value"]
    for e in (g.get("externals") or [])
    if isinstance(e, dict) and e.get("type") in ("SYMBOL", "STRING")
)
```

I have **not** applied it. `owners.py` is mine now, but re-labelling 170 walls
mid-session moves a board other lanes are reading, and the exposure beyond bash
is in the 76 withheld walls and the python/ruby/ocaml/scala columns I did not
measure. The counterfactual above is the honest report; the re-run belongs to
whoever next owns that board, and it can only move bytes **out** of `gap`.

## So: holds, over-claims, or retire?

- **`settled` — holds.** Keep it, unchanged. It answers a real question about a
  real automaton and it errs toward withholding.
- **`gap` — retire the word.** It means "nobody in this tree" and it is a
  four-way ambiguity: our table lost a reading, our lexer lost the token, an
  external was never seated, or the grammar genuinely has nothing. Three of
  those four are ours and the fourth was 0.03% of the board.
- **What the column should say instead:** *"this state, as we built it, admits
  no reading for this terminal."* That sentence is true, it is what the code
  computes, it is still useful for triage, and it does not tell anybody to stop
  looking.

## The instrument I trust least

Not `settled` — **the wall's terminal itself.**

Four of my eighteen witnesses refuse a *different* terminal than `GAPS.md`
names, all four adjacent tokens of the same construct (`[` for `]`,
`\documentclass` for `<`, `"` for `%`, `;` for `2`). And one row is named after
a construct that is provably innocent: `verilog-sized` blames the sized literal
`2'b00`, but `{a, b, 2'b00}` parses **whole** here — the refusal is the
part-select `a[12:11]`.

A terminal-and-state pair is where the parse **stopped**, and the whole
`stranded` verdict exists because that is frequently downstream of the defect.
`GAPS.md` then prices, ranks and names every row by exactly that pair. My own
board carries a `wall` column comparing the two for this reason, and it is the
column I would add first to anything downstream of a peel.

The corresponding thing to distrust in **my** report is the 60 B. All three real
gaps are verilog, and `rack --square` prints `THE GUARD CANNOT RUN HERE` for
verilog because the oracle refuses the grammar on corpus files. My witnesses are
four-line modules the oracle does answer on — which is why the rows are
measurable — but the only bytes I certify as upstream's sit in the one grammar
where the cross-check cannot run.
