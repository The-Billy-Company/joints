A resumed parse that hits a wall before laying a leaf of its own charges its
trailing folds across the resume, onto the last leaf the *previous* parse laid.
`Weave.distil` raised `error.TrailRefused` when the algebra refused that pairing,
on the stated grounds that a refusal there would mean the algebra disagrees with
the parser about what the parser did. That is true of its other three call sites
and false of this one: those two runs are claimed adjacent by the resume, not by
the parser's account of its own moves, so when the composition fails what is
false is the claim. `distil` now takes the floor where this parse's own leaves
begin and declines the tiling below it — the verdict round 14 reached one
question over, in the `seam refused` block directly above it. `Weave.unspun`
gains `charge` beside `off`/`seam`/`win`, because a cleared tiling without the
reason is the shape a verdict hides in.

It cost nothing measurable and it cannot fire in the tree as it stands, because
reaching it needs a resume where `alight` currently grounds. The reproducer is
one keystroke against a `quire` that descends past a `holds` decline:
`amend verilog.folio picorv32.v '20086..20086=x'`, refusing at move 9,559 of
29,995 at byte 19,623 — the resume offset itself, with 2,990 kept leaves and
none of its own. `abide` reads 27 of 30 grammars whole either side, and `probe`
is byte-for-byte identical: swift 3,628 tokens, verilog 8,951, ocaml 4,192,
scala 1,277.

The instrument that made this expensive was the error itself. `TrailRefused`
names neither the move, the byte, nor the operands, and four sites raise it, so
telling them apart meant bisecting keystrokes until the crash moved. Under
`OUTLINER_TRACE=weave` each site now says which pairing refused, at which move
of how many, at which byte, with both entry states — and a declined splice says
so in its own words rather than borrowing the fatal's.
