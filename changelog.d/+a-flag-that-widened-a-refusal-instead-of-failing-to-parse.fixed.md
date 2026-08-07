`still.py against --mine` took `--mine a,b` as **one claim naming no file**.
`standing.py --mine` splits on commas, and `tool/README.md` documents the flag of
that name as "repeatable and comma-separable", so the spelling that did not work
is the one a lane arrives already holding.

What made it worth a fragment is the direction it failed in. A flag that does not
parse should error; this one silently *widened* the refusal:

```text
$ still.py against before handoff --mine src/kernel/lex/,src/.DS_Store
still: REFUSE - the two arms were built from trees differing in 4 file(s),
    4 of which you have not claimed and could move the binary
```

against the correct spelling's `ok - 4 file(s) differ and you claim all of them`.
So the mis-parse read as *your isolation is worse than you thought* - a plausible,
alarming, actionable-looking report - rather than as a typo. A lane that trusted
it would have gone looking for a sibling's edit that was never there, or split
its arm again to chase collateral it had already claimed.

Fixed by splitting on commas at the parse site, so the two flags of one name
cannot disagree about their own syntax. The gate can still say no: a partial
claim (`--mine src/kernel/lex/writ.zig,src/.DS_Store`) still refuses and still
names the two files it was not handed.
