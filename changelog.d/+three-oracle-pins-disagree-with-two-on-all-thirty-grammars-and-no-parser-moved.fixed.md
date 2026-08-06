Five oracle pins sit on this machine, frozen between 00:55Z and 04:16Z today.
Point the three older ones at the live tree and every one of their thirty rows
refuses: `bash: pin moved`, `c: pin moved`, thirty times. Read at face value that
is the oracle drifting under a day's work — the exact hazard four lanes writing
one shared vendored tree were expected to produce.

No parser moved. `attest.survey` stopped folding generated files into the
identity somewhere between 02:14Z and 03:49Z, and it was right to: a `parser.c`
is an output of inputs the digest already holds, and its mere *presence* is a
cache state any measurement creates. So the older pins and the newer ones are two
rulers, and thirty convincing drift reports were thirty measurements of the
distance between them. The only reason it was caught is that `attest.was` — the
retired rule — was kept around to disagree.

`attest.rule()` digests the code that computes an oracle digest: the three
functions the identity is made of and the two constants they partition on.
`freeze` writes it into `pin.json`; `still.take` puts it on the witness. When two
arms' identities were computed under different rules, `still.differ` now refuses
**once**, saying so, and returns before the per-grammar rows can fire — because
reporting thirty drifts would bury the one fact that explains all thirty.
`attest.py under` distinguishes a pin whose bytes moved from one whose ruler did,
since the remedies are opposite: a stray write versus a re-freeze. `attest.py
list` gains a `rule` column that is *measured* for the pins minted before the
digest existed, by re-deriving three of their own rows under each rule and seeing
which reproduces what they wrote down.

The five pins now read `retired · retired · retired · current · current`, in the
order they were taken.
