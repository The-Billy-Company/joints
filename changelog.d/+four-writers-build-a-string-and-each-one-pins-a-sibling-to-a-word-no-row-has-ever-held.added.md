`field.Press.reason` was the largest finding on the board and it reads exactly
like the bug the board was built for: `""` on all 640 rows on disk, against
five writers, three of which build a real string. The brief on it was "a value
that is constructed and then does not arrive is a serialization defect - find
where the string is lost".

It is not lost. Each of those three writers sits in a `Press(...)` that also
hands `outcome` a **literal** - `absent`, `refused`, `timeout` - and `outcome`
is a column this same sweep has watched take four values across those same 640
rows: `clean` 432, `residual` 128, `refusing` 78, `unlexable` 2. None of the
three. The near-miss is a naming one and it is worth writing down: `refusing`
is a *successful* press over a table that has refusing cells, and `refused` is
a press that would not run. 78 rows read one and zero rows read the other. So
the sweep is not looking at a string that was built and dropped; it is looking
at three constructions that have never been executed, and it can name the
observation that would prove otherwise.

`unreached` is that verdict. It is `unasked` one level in - `unasked` reads a
default off an `add_argument` and says nobody passed the flag; this reads a
literal off the construction beside the field and says nobody took the branch.
Both are facts about how the instrument was driven and neither is an edit.

Three narrownesses, because an excuse that fires easily is worse than none:

- Every site that could hand over **something other than the value observed**
  must be marked. The site spelling the observed value is the one that ran; a
  splat re-hydrating a record from its own JSON originates no value. One
  unmarked site that could have moved the column and didn't is still a defect.
- The discriminant must be a **string literal** whose sibling has been observed
  holding *something*. An unobserved sibling proves nothing, and matching `0` /
  `False` / `""` would turn real findings amber by coincidence.
- It is checked against the population, so it **dissolves the moment it stops
  being true**. It cannot be spent twice.

That last one is the falsifier, and it is the one worth running: three press
rows outcome `clean`/`residual`/`refusing` leave `reason` `void/unreached` and
green; add a fourth row that **is** `refused` and still carries an empty
`reason`, and `outcome` has now been observed holding the literal the excuse
was standing on - the excuse lapses by itself and the row goes `void/open`,
red. Exactly one of eighteen columns moves between those two arms, and it is
`reason`. The retired `still.Witness.oracles` rule is minted at a site whose
every argument is computed, so there is no literal to read and no excuse to
find; it still reddens.

It also caught `bench.Row.axis` and `bench.Row.unit`, which cross-witness each
other: eight construction sites, and only `axis='press'` / `unit='ms'` has ever
been benched. Neither column is a defect and neither needed touching.

`verify` gained four falsifiers and got **faster** - 2.0s to 0.9s - because the
static half is now parsed once per process instead of once per sweep, and
`verify` takes six.

Board: **12 red → 9**.
