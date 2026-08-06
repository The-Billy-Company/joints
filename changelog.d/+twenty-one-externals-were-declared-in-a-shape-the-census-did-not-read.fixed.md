`closure.py` built its declared-external set from `e["name"]` where
`type == "SYMBOL"`, and tree-sitter lets a grammar declare an external as a
bare literal instead. Those carry `"type": "STRING"` with a `value` and no
`name`, so twenty-one of them across eight grammars were read as if the
grammar had never declared them - bash's `]`, `}`, `(`, `esac`, `<<`, `<<-`;
scala's six keywords; python's four closers; one each in html, javascript,
ocaml, ruby and typescript. A wall on a terminal the grammar hands to a C
scanner then read as a wall on a terminal the grammar has no rule for.

That is not hypothetical: bash's `]` is exactly what `GAPS.md` row 14 named,
495 bytes filed as work nobody in this tree can do, when the grammar says on
its own first page that a scanner produces it.

**The fix as it was written down is still incomplete, and that is the more
useful half.** The dossier that found this proposed widening to
`type in ("SYMBOL", "STRING")`, which is an enumeration of the two shapes
somebody had already met. The corpus holds a third: two `PATTERN` externals,
bash's and haskell's `\n`, both in walled grammars. Listing shapes is how the
first spelling of the line got it wrong, so `declared()` now says a `SYMBOL`
answers to its name and **everything else answers to `names()`** - total over
the node kinds `render()` knows, contributing nothing for one it does not.
Census: 492 declared spellings over 30 grammars where the named-only read saw
461. `owners.py --externals` prints both reads and the difference per grammar,
so the counterfactual stays runnable instead of being a paragraph here.

What it moved, measured 2026-08-05 over 170 distinct walls and 181,588 B of
peel: **one wall, 495 bytes.** bash `] in state 35`, `gap` to `scanner`. The
brief for the repair said it would rehabilitate a prediction of "at least 45
scanner walls" that had scored 9; it takes that to 10. The prediction was
falsified 5.0x and is now falsified 4.5x. A fix can be right about the
mechanism and worth applying and still not be the reason a number was wrong.
