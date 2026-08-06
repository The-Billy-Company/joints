# RESULT-2 — the 49,446 bytes, named

`picorv32`'s main module carries 49,446 bytes of damage, 92.1% of it inside
procedural blocks. `PREDICTION-1` fenced off the header (deleting the whole
parameter port list *and* port list moves `built` by exactly 0) and then ran out
of method, because **ablation cannot separate a grammar gap from a productive
construct**: blanking something that partly parses takes away the bytes it was
contributing, so every arm of a statement-form sweep moves `built` down and none
of them can be read.

This is the other direction — **build the smallest module that fails, from
nothing** — run at corpus scale and then by hand.

## The answer

**Four distinct grammar defects, two of which carry 98.4% of the refused bytes.
One of the two is a gap in the grammar that no work on the press can seat.**

| defect | smallest witness | control that stands | wall | owner | bytes | share |
|---|---|---|---|---|---|---|
| 1 · a directive in statement position | `` `assert(a); `` | `` x = `WIDTH; `` | `` ` `` in 1108 | **gap** | 21,535 | 51.1% |
| 2 · a select inside a concatenation | `x = {a[3], b};` | `x = {a, b};` · `x = a[3];` | `;` in 701 | conflict | 19,928 | 47.3% |
| 3 · `$signed` on both sides of an operator | `lt = $signed(a) < $signed(b);` | `lt = $signed(a) < b;` | `(` in 3772 | conflict | 360 | 0.9% |
| 4 · an indexed lvalue under a *blocking* assignment | `c[i] = 0;` | `c[i] <= 0;` · `x = 0;` | `=` in 2394 | conflict | 93 | 0.2% |
| — unattributed | | | | | 250 | 0.6% |

Bytes are the size of the real `picorv32` statements that fail when seated alone
in an otherwise-empty module — 42,166B of the 55,668B of statements lifted out
of the file's procedural blocks, against the module's 49,446B of damage.

A fifth witness belongs to the same gap as #1 at a different position: a
`` `ifdef `` **between two port declarations** (`` ` `` in 2088) fails while the
same directive between two module items stands. That is `RESULT-1`'s wall A,
and it is now the same defect as #1 rather than a separate one.

## Why #1 and #2 have different owners

`reach.py` answers this off the grammar's own reachability closure, with no
parse, no oracle, and no tree-sitter — from the nonterminal that governs a
position, can the offending symbol be derived *at all*?

```
wall                        position                    must derive     verdict
A  `ifdef in a port list    list_of_port_declarations   id_directive    GAP - no derivation exists
F  macro as a statement     statement_item              text_macro_usage GAP - no derivation exists
D  indexed lvalue, blocking variable_lvalue             select1         CONFLICT - the grammar can derive it
E  select inside a concat   concatenation               select1         CONFLICT - the grammar can derive it
B  $signed in an operand    expression                  system_tf_call  CONFLICT - the grammar can derive it
```

`_directives` is referenced by exactly three rules in the whole grammar —
`_description`, `_non_port_module_item`, `class_item` — and neither a port list
nor a statement is one of them. That is an impossibility argument in the strict
sense: not "we measured and it did not work" but "no derivation exists". No
amount of work on the table will ever seat it, and the fix is a grammar change
in `upstream/grammars/verilog.json`, which is vendored.

The closure earns its verdicts on a control table rather than asserting them:

| target | `_description` | `_non_port_module_item` | `class_item` | `primary_literal` | `statement_item` |
|---|---|---|---|---|---|
| `id_directive` | yes | yes | yes | – | – |
| `text_macro_usage` | yes | yes | yes | – | – |
| `simple_text_macro_usage` | yes | yes | yes | **yes** | **yes** |
| `system_tf_call` | yes | yes | yes | – | yes |
| `select1` | yes | yes | yes | – | yes |

The third row is the control. `simple_text_macro_usage` **is** reachable from
expression and statement position, which is exactly why `` x = `WIDTH; ``
parses while `` `assert(a); `` does not — and a closure that could not tell
those two apart would be reading itself.

## Anti-vacuity

- **The frame.** Every synthesised module is checked against the empty harness
  `module m; … always @* begin x = 0; end endmodule`, which must stand at 100%.
  If it does not, every row is the frame's failure wearing a statement's name.
- **The pass column.** 178 of 204 lifted statements stand alone at 100%. A sweep
  where everything fails is a sweep measuring its own extraction.
- **A control per witness.** 8 of the 17 authored constructs stand next to their
  control — attribute instances before `case`, reduction operators after `&&`,
  unary minus and string literals as ternary arms, `$display` with a format
  string, sized binary literals, shifts by a literal, and `` `ifdef `` between
  two *module items*. Each was a plausible suspect drawn from the failing
  statements and each is innocent.

## What the sweep got wrong about itself

No prediction file was written for this segment, which is this lane's own lapse
against house discipline. What follows is offered in its place, and it is four
instruments — all of them mine, all found inside this result:

1. **A fixed scratch path.** `.local/witness/w.v` was shared, and two runs
   overlapping by milliseconds had the second read the first's 3,328-byte
   statement as its own 90-byte control frame. The control duly reported the
   frame broken. It is per-pid now, which in a tree ten agents share is not a
   nicety.
2. **The `for` header split on its own semicolons.** `for (i = 0; i < n; i =
   i+1)` became three fragments, each of which failed to parse, each of which
   clustered separately — and three grammar defects that do not exist arrived on
   the first board. Caught only because the witnesses printed were not whole
   statements.
3. **`if (a) x; else y;` split at the `else`.** Same class, two more phantoms.
   The splitter is bracket-aware and glues `else` back now; the distinct-wall
   count went 16 → 13.
4. **The automatic shrink was destructive and still looked right.** Deleting any
   token while the wall held turned `alu_lts <= $signed(a) < $signed(b);` into
   `alu_lts <= $signed < $signed(b);`, which is not a smaller version of the
   defect — it is a different defect that shares a state number. Every one of
   the sixteen shrunk witnesses named the same LR state as its parent, so the
   shrink was *green*. The reported witnesses are authored, not shrunk.

## Frequency is not cost, and this file proves it twice

Ranked by how many statements a wall stops, `` ` `` in 1108 is first with nine.
Ranked by bytes, `` ` `` in 1953 is first with one statement and 16,289 bytes —
**one statement carrying 4.5× the bytes of nine.** Those are different walls and
only one of them is worth a day.

This is the second time the two orderings disagreed on this file. In the warm
peel, state 2394 takes seven of nine warm-only walls and costs **−167 bytes**:
the state that recurs most is very nearly the state that costs least. Under the
byte ranking above, 2394 is twelfth of thirteen at 93 bytes.

So any ranking built from wall **counts** — including `walls.py`'s own peel,
which reports `distinct` and derives `voice` from it — is ranking the wrong
thing. `witness.py` sorts by bytes and says on every run which wall the count
ordering would have put first, so the disagreement is visible rather than
rediscoverable.

## Scripts

| script | what it answers |
|---|---|
| `reach.py` | gap or conflict, off the grammar's reachability closure — no parse, no oracle |
| `witness.py` | how many distinct defects there are, and what each costs in bytes |
| `smallest.py` | what each one *is*, as an authored witness beside a control that stands |
