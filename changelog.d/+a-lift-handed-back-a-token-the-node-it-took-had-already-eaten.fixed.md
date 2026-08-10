A lift now asks the scan where it stood at the *last* ask on the offset it
lands on, and the ask that finds the end of the file is recorded like any
other.

Condition 3 says a lift may only skip bytes the scan does not need to read:
the memory a hand is carrying has to already be standing where those skipped
answers would have left it. It was asking the right question against the wrong
moment.

A hand answers where the cursor cannot move, so one offset can be asked several
times, and every one of those answers but the last was consumed by the very
node a lift is about to take whole. Python's `block` ends on a zero-width
`_dedent`. The node reads `[763, 883)` - the dedent it swallowed costs no bytes
and sits at 883 - so the old parse's record at 883 is three asks deep: a
`_newline` and a `_dedent` inside the block, then the first token after it.
Reading the first of those compared the lift against a moment the lift skips.
The take was admitted, the column stack stayed one block too deep, and the
parse tripped a hundred bytes later:

    joints amend python.folio ledger.py '4..4=x'
    → unexpected _dedent at 884 in state 106

The end of the file is the same defect wearing the other hat. Every stance is
written beside the token it was taken in front of, and the ask that finds EOF
has no token - so the last offset in a file was the one offset condition 3
could not speak about, and it fell back on the stance in front of the
zero-width token the last node had eaten. That ask is recorded now.

Two more things while the condition was open:

- The refusal is per candidate, not per probe. Two nodes beginning here end in
  different places; a wide one the scan cannot vouch for says nothing about a
  narrower one that ends before the memory moves. `passed_stance` joins
  `passed_shape`/`goto`/`break` in the walk's accounting, where it belongs.
- `JOINTS_NO_STANCE`, the knob this was A/B'd against, is gone. A soundness
  condition does not get an environment variable.

**It is a correctness fix and it costs no reuse.** On the python repro the
broken condition took 16 lifts over 738 bytes and then failed; it now takes 6
lifts over 1,369 bytes and accepts - byte for byte what the same binary takes
with the condition stood down entirely, which is the claim: the check refuses
exactly the unsound takes and nothing else.

`abide.py` compares the amended tree against a cold parse of the same bytes
after all 24 keystrokes, on every grammar. Same binary, condition on and off:

| | off | on |
|---|---|---|
| python | 22 of 24 | 24 |
| markdown | 21 of 24 | 24 |
| grammars where every amended tree equals a cold one | 15 of 30 | 17 |

Nothing else moved a row.

And the html reproducer that started this - 243 bytes, two `<button>`s, an
insert at every caret, each amended tree diffed against a cold parse of the
same bytes:

| | diverging carets |
|---|---|
| condition off | 129 of 244 |
| condition on | 0 |

The 18 carets html still refuses are the ones that insert into `<!--`; a cold
parse refuses them too.
