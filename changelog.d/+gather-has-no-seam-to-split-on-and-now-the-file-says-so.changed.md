`gather.zig` is 4,276 lines against a house rule of 500, and it carried no
statement of why. The obvious errand is to cut it into five or six even modules.
I measured whether that is possible before doing it, and it is not.

Grouping the fifty-eight methods into the eight clusters anybody would draw on
sight - the loop, mend, weave, the memo, growth, absorb, strands, reduce - and
asking which of the struct's seventy-six fields each cluster touches:

| cluster | lines | fields read | owns exclusively |
|---|---:|---:|---:|
| absorb | 612 | 37 | 2 |
| mend | 512 | 38 | 3 |
| memo | 509 | 24 | **6** |
| reduce | 482 | 21 | **0** |
| weave | 423 | 34 | **0** |
| strand | 216 | 24 | 4 |
| grow | 213 | 11 | **0** |
| loop | 195 | 41 | 2 |

`init` and `deinit` are excluded, since a constructor touching every field is
not evidence about anything. Three clusters own nothing at all. Seventeen fields
are touched by exactly one cluster, and twenty-four by four or more.

So a file split hands each new file a pointer to a struct it does not own and
lets it mutate twenty to forty of that struct's fields. That is the same monolith
with `@import` lines in front of it, a worse locality story for the loop whose
working set is the entire point, and five new interfaces that hide nothing. The
cap is a proxy for simplicity; this is the case where paying it buys the opposite.

Written into the file's own header rather than only here, because the next person
to see 4,276 lines will reach for the same errand and deserves the measurement
rather than my conclusion.

**And the negative result names its one exception.** The memo cluster is the only
one with real encapsulation - it exclusively owns `descent`, `menus`, `lands`,
`veiled`, `looks` and `ticks`, which is a cache with its own invariants and could
become a struct behind a narrow interface. That is a design job, since the
eighteen other fields it reads have to become arguments or stay behind, and it is
worth doing on its merits and not as a line-count errand. Nobody should confuse
the two, which is why both halves are recorded.
