# HANDOVER — the wrong-limb defect, to whoever owns `src/kernel/quire/`

Short answer to the question the press lane was asked: **yes, the gather
wrong-limb defect survives, and after the press stopped erasing authored ranks
it is the entire remaining cost of the verilog splice fix.** Full working in
[RESULT-3-provenance.md](RESULT-3-provenance.md); this file is only the
reproducer and the cell, so you do not have to read that to start.

## The reproducer

Three lines. Both binaries say `accepted, 1 root`, so nothing on the board or in
`smallest.py` reports a problem.

```verilog
module m;
	always @* begin
		instr_mul = 0;
	end
endmodule
```

Before the press fix:

```
(seq_block (statement_or_null (statement (statement_item (blocking_assignment
  (operator_assignment (variable_lvalue (simple_identifier)) …))))))
```

After:

```
(seq_block (block_item_declaration (data_declaration
  (list_of_variable_decl_assignments (variable_decl_assignment …)))))
```

`instr_mul = 0;` inside `always @*` is a blocking assignment. It is not a
declaration.

## The cell

`joints state upstream/grammars/verilog.json 1762`, on `=`:

```
before   =   fold  variable_lvalue -> _identifier   [prec 0 left]
after    =   read on   [residual shift_reduce, over fold  variable_lvalue -> _identifier   [prec 0 left]]
```

Before, the ladder folded on a `left` that `variable_lvalue` never wrote — it
absorbed it from `hierarchical_identifier` during a splice — so there was one
action and gather was never asked. The press now declines a side it inherited,
the cell is a genuine `shift_reduce`, and both limbs are offered:

- **read on** → `variable_decl_assignment -> _identifier . = expression`
- **fold** → `variable_lvalue -> _identifier .` → `blocking_assignment`

**The statement limb is the one wanted.** The declaration limb exists because
SystemVerilog really does allow an implicitly-typed `data_declaration` at the
head of a `seq_block`, and `c[i]` really is spellable as an associative-array
dimension. It is a legal fork; it is just the wrong branch here.

State 1184 has the same shape one terminal over, on `[` and `.`, against
`clockvar -> _identifier`.

## Four situations, and gather is right in one

| body (inside `always @* begin … end`) | limb taken | right? |
|---|---|---|
| `c[i] = 0;` | declaration | no |
| `x = 0;` | declaration | no |
| `c[i] <= 0;` | declaration, then walls on `<` in state 2603 | no |
| `for (i = 0; …) c[i] = 0;` | statement | yes |

The last one is right only because a declaration is ungrammatical in a for body,
so the fork has one limb. Wherever gather has a choice here it takes the
declaration.

The `<=` row is the only hard regression the press fix causes. It is narrow —
only `ident[ident] <= …`, because only an identifier index is also spellable as
a type, so `c[3] <= 0;` and `a[3:0] <= 0;` are unaffected — and `picorv32.v`'s
two instances are both behind `` `ifdef `` blocks the parser already walls on,
which is the only reason the board did not move.

## Why this is a better specimen than scala and elixir

`RESULT-2` diagnosed the same defect from repair B's regressions: scala's
`@SerialVersionUID(0) class Some[+A]`, and 7,358 bytes of elixir. Those are
whole-file effects in two grammars, mixed with everything else those files do.

This is three lines, one state, one terminal, two named productions, and a
verdict you can read straight out of `joints state`. It also has no board
signal at all — `built`, `covered`, `spoil` and `damage` are identical either
side because the spans are identical, and `rack --square` prints
`THE GUARD CANNOT RUN HERE` for verilog. **If you fix this you will not be able
to prove it on the board.** Diff the tree of `picorv32.v` instead: the four
statements at line 2348 are the whole visible difference, worth 12 nodes, and
they should read `blocking_assignment`.
