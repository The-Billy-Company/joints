`Divergence.line` renders a verdict through a three-entry lookup — `refuse`,
`warn`, `declared` — with a bare `[]`. The fourth verdict, `vacuous`, was added
with the sixth case and never added here, so every code path that *printed* a
vacuous finding raised `KeyError: 'vacuous'` instead.

That is the case the gate was built for: thirty folios byte-identical across two
arms, offered as proof of no collateral, true and empty. `verify` never caught it
because its table reads `d.verdict` and `d.field` directly and never calls
`line`. The lookup is now a `.get` that falls back to shouting the verdict it has
not heard of, so a new verdict tomorrow is a loud row rather than a traceback in
the middle of a report.
