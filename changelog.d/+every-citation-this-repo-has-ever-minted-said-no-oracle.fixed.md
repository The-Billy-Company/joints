`standing.py --cite` exists so a page can name the world its figure was read in,
and the oracle is a third of that world. It printed `**no oracle** - outliner's
own words` **every time it has ever been run**, including on an arm whose board
had just printed `30 oracle(s) d85e736fa attributed` in the same terminal.

Not a bug in the field - a consequence of the design decision beside it.
`--cite` takes no survey on purpose (an attribution that costs a 30-second board
is an attribution that gets skipped), and the survey is also the only thing that
calls `attest.attribute`, which is the only thing that seats a court. So
`still.take` read an empty `attest.SEATED` and the witness had nothing to say.
The absence was structural, which is why nobody caught it by reading a number:
the field could not have read anything else.

Seating the court in `--cite` is not the fix, and the arm that proves it took
one command. `bench()` is cheap (0.35 s, reads no `parser.c`) but it answers
*which tree-sitter would answer for each grammar in this repo* - a property of
the checkout, not of the arm. Pointed at a work dir with no verdicts at all it
then minted:

```text
outliner `1885792a7` · tree `4f018b60f` (pin) · oracle `d85e736fa` (30 attributed)
```

for an arm whose every `square` and `crooked` column reads 0. That is the
stronger of the two available lies - the first understated the evidence, this one
tells the next page a figure was judged when nothing judged it, and 0 is also
what thirty agreeing grammars print.

So the witness now carries **live verdicts on the arm** beside the court:
`pin.oracled`'s body moved to `still.live_verdicts(work, binary)`, taking the
pair every arm has rather than the directory layout only a pin has, and `pin.py`
became its caller so the two instruments cannot disagree about whether an arm can
see. `None` means "did not look" and is what a witness written before this field
honestly says; `(0, N)` means "looked, and this arm holds nothing", which is a
measurement and gets its own sentence. Three states, three spellings:

```text
oracle `d85e736fa` (30 of 30 live, 30 attributed)
oracle `d85e736fa` seated but **no verdict live on this arm** (0 of 30 held) — `square` and `crooked` off it are unmeasured zeroes
**no oracle** — outliner's own words
```

The middle one is new and is the point. It also catches the `folio: missing`
shape the liveness check was written for: thirty verdicts held, none live,
because the folios they are about were never pressed in that seat - and it is
what a bare `--cite` beside `OUTLINER_BIN=<a pin>` now says, correctly, because
the shared default seat's thirty verdicts were minted by a different binary.

Two things it is honest to state about the new field. `live_verdicts` is
`Held.matches` **minus** `source`, so it is an upper bound on what a board would
accept rather than a reproduction of that decision: it cannot claim live where
the board would refuse, but a `source` mismatch could still leave a citation
saying `30 of 30 live` over a board that judged fewer. And the seat is passed in
by the caller rather than defaulted here, because `standing`, `plumb` and
`collate` each already spell `OUTLINER_WORK or ROOT/.local/standing` and a
fourth copy in the witness is how a witness comes to disagree with the board it
witnesses about which seat it read.

Cost: `--cite` went from ~0.2 s to ~0.55 s. That is inside the budget the
command's own comment sets for itself, and the alternative was a stamp that
disclaimed the oracle on every page in the repo.
