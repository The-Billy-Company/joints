A supply is a hypothesis, and `--mend=fell` was publishing the ones the parse
never confirmed. `supply` writes a terminal in on the strength of clause 2,
which justifies it for exactly **one** token: the refused token shifts next, and
what happens after that is the parse's answer about whether the omission was
real. A fold taking the ghost as a child is that answer arriving. A second
refusal reaching `unwind` first is the answer never arriving - and `unwind`
carried the whole standing chain into the roots regardless, ghost included.

The shape of the defect is a **zero-width node at depth 0**: a node covering no
bytes, standing under no parent, asserting a terminal at a position where the
file holds nothing. `plant`'s own anchor rule says the supply offset "is the
only offset at which a zero-width child is inside its parent", so as a root it
completed nothing. Corpus-wide under `--mend=fell` there were **127** of them.
Under `--mend=keep` there is **1**, because `keep` never puts the chain down and
every ghost stays live until a fold takes it: all **59** of verilog's are inside
a parent by the time the parse ends. The arm with no second move builds **no**
zero-width node at all.

That is the whole of the `keep`/`fell` split the supply dossier reported, and it
is a property of the policy rather than of the rule. `unwind` now stops
publishing `own` runs at the first unconfirmed supply on the chain. The `lead`
runs still go out at every perch - a perch's leading extras are comments the
file really holds, and those belong to the forest whatever the parse decided
about the structure over them.

Reading the ghost back off the perch is exact rather than a guess, and clause 1
is why: a supply is *always* anonymous, and the terminals that are legitimately
zero-width - swift's `_implicit_semi`, haskell's layout hand - are named and the
scanner's to produce.

Measured arm against control, same binary one `--no-supply` flag apart, on its
own pinned oracle seat (`tool/pin.py arm felled`, 30 of 30 verdicts live):

| `--mend=fell`, arm vs control | before | after |
|---|---|---|
| corpus `crooked` | **+688** | **+112** |
| verilog `crooked` | +713 | +137 |
| verilog `built` | +284 | −369 |
| corpus `unbuilt` (`crooked + unframed`) | +255 | −348 |

`--mend=keep`'s headline is untouched at **+3,124 square**, which is what makes
this a repair rather than a policy boolean wearing a different hat: it fires
only where a supply was left unconfirmed, and under `keep` that essentially
never happens. The default is no longer worse on `crooked` than it was before
the second move landed - it is better.

Two pins on two trees, because siblings were landing in `src/press/` throughout:
`unproven` (tree `ace700af2993`) read +95 corpus / +120 verilog and `felled`
(tree `b78d53779933`) reads +112 / +137. verilog's `--mend=keep` row moved by
~13,000 between those two trees on a change that is not this one; it is recorded
here as unattributed rather than quoted.
