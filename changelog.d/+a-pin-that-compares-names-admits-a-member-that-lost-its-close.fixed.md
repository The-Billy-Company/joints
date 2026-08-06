`scanner_test.zig`'s roster pin — *a row claims the terminals it is pinned to and
no others* — compared **names only**. It caught a roster widened by a member and
would have passed `_quoted_content_heredoc_single` keeping its name and losing
its `wide = 3`, which is the same walk reading one quote where three end a
heredoc: a wrong tree rather than a missing one, and the failure the troupe
contract calls worse than silence.

Every field of `marrow.Mark` is now rendered into the pinned claim — the `shut`
byte, the `tail`, `xN` for a close wider than one byte, then a letter per flag
(`i` interpolates, `a` after-a-variable, `c` command-name) — and an unprintable
close goes out as `\xNN` so a pin stays a diffable line. A caesura's `seams` are
pinned the same way and for the same reason: three names a hand can extend by one
line, in the enum's order rather than the row's, so a seam moved between arms
shows up as two changed lines and not as a reordering.

Proven by breaking it rather than by passing it. Truncating
`_trivia_raw_env_verbatim`'s tail from `end{verbatim}` to `end` in a scratch tree
fails the test at the byte:

```
expected:
_trivia_raw_env_verbatim \end{verbatim}
                             ^ ('\x7b')
found:
_trivia_raw_env_verbatim \end
                             ^ (end of string)
```

One test of that shard's eleven fails and the ten beside it pass, so the red is
the corruption and not the scratch tree.

The same discipline applied to the four new specimens, because the other
inherited hole was that **a failing specimen has no number below zero to fall
to** — the guard the php lane tried to break was already 0/7. Each of the four
was run seated and unseated: 7/7 → 2/7, 7/7 → 3/7, 7/7 → 1/7, 8/8 → 6/8.

That last row is the caveat worth keeping. `latex/iffalse-fi.tex` still scores
`roots 1` and `mends 0` unseated, because latex's recovery builds a
`block_comment` over the first eight bytes instead of shredding; only its three
`spans` claims fall. A specimen whose structural claims survive the break is
carried entirely by its extents, and `roots`/`mends` on a grammar that recovers
politely are close to free.
