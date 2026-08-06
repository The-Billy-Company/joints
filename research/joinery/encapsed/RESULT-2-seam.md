# Result 2 — marrow, not fence. Held, and the census contradicted its own
# first reading.

Prediction 2 said php's non-heredoc string interiors belong on a `marrow`
family rather than a `fence`, that the roster would be four parts, that
`marrow.Mark` would need one new field, and that roster order would matter.
All four held. The census bought something the prediction did not anticipate.

## Why marrow and not fence

The whole argument is one `if` in php's own scanner. `scan_encapsed_part_string`
takes five arguments; with `is_heredoc` true its first statement reads
`scanner->heredocs`, a stack of tags one token pushes and another spends. With
it false, nothing in the function touches `scanner` at all — the answer is the
bytes at the cursor plus two booleans.

And the two booleans are not memory. `is_after_variable` and
`is_execution_string` are supplied by *which terminal the parse state named*:
php declares `encapsed_string_chars` and
`encapsed_string_chars_after_variable` as separate externals, and the state
inside an interpolation asks for the second. So the distinction arrives with
the question rather than being carried to it, which is the definition
`outside.Part` exists for.

That is the line the seating draws, and it is why four of six are seated and
two are not.

## The one new field

`marrow.Mark` gained `after: bool`. Everything else php needs — which quote
closes the run — was already `shut`. The comment on the field says what it is
for, because the temptation to read it as history is the whole hazard: `"$a[0]"`
and `"a[0]"` differ not because the scanner remembers a variable but because
the parser asked a different question.

## The census, and it disagreed with itself

`outliner state php.json --census` over the four terminals reports **shift 0
for all six pairs** — no LR state ever shifts two of them at once. Read alone,
that says roster order cannot matter and no guard is needed.

The permission set says otherwise, and this is the same trap julia's row
documented. In the set a hand sees, three states admit
`encapsed_string_chars` together with its after-variable twin, and eleven
admit the encapsed and execution families together. Two of those eleven are
states 174 and 410:

```
174:  _simple_variable -> dynamic_variable_name .
410:  variable_name -> $ name .
      shifts: (none)
      lookahead: ; & , = as { } : => ( ) ? | + - …  ← nearly every terminal
```

Those are bare folds that stand in **ordinary php code**, after any `$foo`. A
hand reading the union there would have answered string content over the rest
of the statement. So the row carries
`.rival = .{ "encapsed_string_chars", "execution_string_chars" }`: you cannot
be inside a `"` string and a backtick string at once, so a state admitting both
is inside neither. The two real interiors are untouched — state 386 holds no
execution terminal and state 408 holds no encapsed one, which is the check that
makes the rival safe rather than merely cautious.

Roster order is the specification's own dispatch order — after-variable before
plain, encapsed before execution — and state 386 is where it earns itself:
`variable_name .` inside an interpolation, `->` and `[` both live shifts, and
after-variable the right reading.

## Two things verified rather than assumed

**php's externals are all `SYMBOL`-typed.** The interrupting lane warned that
`closure.py` silently drops the 21 literal-declared externals across 8
grammars. php declares twelve and every one is symbol-typed, so nothing built
on that closure misreports php. Checked against `grammar.json` directly rather
than through the closure, per that lane's instruction. (Separately: the
seating gate in `scanner_test.zig` reads `e.name orelse e.value`, so it was
never subject to the defect.)

**All four names are php's alone across the thirty grammars**, and four
arriving together is not a collision anyone reaches by accident. `kin` is
`sentinel_error` anyway — read at the top of the same `scan()` and also php's
alone — because the row should not depend on the roster being unusual.
