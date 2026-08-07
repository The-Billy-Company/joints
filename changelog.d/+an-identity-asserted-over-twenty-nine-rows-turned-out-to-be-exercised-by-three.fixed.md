`collate.py honesty` asserts P4, and it is an identity rather than a statistic:
`plumb`'s misread bytes are a subset of `built`, `damage` is the complement of
`built` over the file, so a misread byte cannot be a flagged byte and joints's
recall over its own misreadings is exactly `0.00` on every grammar forever. The
board printed that `0.00` on **29 of 29 rows** and read as 29 pieces of
evidence.

It is three. `recall = ours_caught / misread if misread else 0.0` returned the
same zero for *caught none of the ones there were* and for *there were none*,
and on the live corpus only bash (1 misread byte), haskell (17) and php (708)
have a misread byte at all. The other 26 rows cannot fail to flag a misreading
they do not have. **The identity is asserted over 29 rows and exercised by 3**,
and the board could not say so because both facts printed `0.00`.

`recall` now returns `None` where `misread` is empty and the row prints `—`, and
the summary states the split rather than leaving it to be counted:

```
726 bytes joints reads wrong where the oracle is sound; it flags 0 of them — recall 0.00
3 of 29 row(s) exercise it. The other 26 print `—` rather than `0.00`
```

The self-check gains a sibling. `the honesty verb finds php's misreadings at
all` was already there and is a real guard, but it is one grammar's name: the
morning php's 708 bytes get fixed, that check dies and dies looking like a pass,
and the identity above it goes back to being asserted over nothing. The new
line asks the same question of the sampled population instead - *at least one
row has a misread byte* - so the guard survives the fix that would dissolve the
witness, and prints the count it is standing on either way.

Measured on `joints e51716d6c`, tree `61c93c367`, oracle tree-sitter 0.26.11,
29 of 30 rows adjudicated (yaml has no lexable terminal and is `not measured`).
