`square` is the only column on the board that is a claim about agreement with a
second parser, and it comes off an `audit.json` living in `JOINTS_WORK`. The
third house rule gives every isolation arm a work dir of its own, so two arms
cannot contaminate each other — and that is exactly what empties the column, to
**zero**, which is also what a board prints when thirty grammars agree
perfectly. Nineteen controlled comparisons were read as a no-collateral
clearance off that zero.

`blind.py` walked every board retained under `.local` and summed the square each
one *accepted* rather than the square its cache claimed:

    blind 28  ·  sighted 4  ·  told 1

All four sighted boards paid `--audit` inside their own work dir. None inherited
sight, because the shared default cache holds thirty verdicts carrying no
`oracle` field at all and confers nothing on anybody. The separator is not care
and it is not the default dir; it is a lane deciding in advance that it would
need the other parser.

The `told` board is a second defect and it is upstream. `standing.py audit()`
digested `WORK/<name>.folio` with `marks()` *before* `plumb.read()`, and
`plumb.read` is what presses that folio into existence — so on a work dir nobody
has measured in yet, which is precisely the one `pin.py arm` hands out, the
recorded digest is the literal string `missing` and the next board refuses all
thirty rows as `stale`. Two caches on this disk are 30-of-30 `folio: missing`,
both minted by lanes that paid the four-minute sweep and got nothing for it. The
read is now first; the four caches minted after the change read 0-of-30 missing.

Seeding a neighbour's cache is not the fix and the machinery already said so — a
verdict is keyed on folio, binary, source and oracle, and two arms differ in the
binary by construction. Copied into a sibling arm it reads `graded: stale` on 30
of 30 and mints no square, with no code change needed to refuse it. So verdicts
are minted per arm, and the only thing worth building was making that one
command: `pin.py oracle <name>` runs the sweep inside the arm's own environment
and exits 1 if the arm cannot read its own verdicts back, because a sweep that
wrote thirty nobody can accept is the failure the verb exists to end rather than
a success with a sad number in it.

`pin.py arm` now closes on the arm's oracle state, on stderr so it survives
`eval` and changes nothing a lane pipes:

    # oracle: NONE — every `square`/`crooked` column off this arm will read 0, and
    #         a comparison against it is not a claim about agreement with tree-sitter.
    #         Mint one: python3 tool/pin.py oracle fz-control

The check is a digest of the binary and one `stat` per folio, deliberately, because
`arm` is a line of shell lanes evaluate constantly and a check that opened thirty
folios is a check somebody turns off.

Sight costs 60–92 seconds per arm. That is why nobody paid it, and why the arm
says so unbidden now instead of a dossier saying it three lanes later.
