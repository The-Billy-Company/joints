# cover — the refusal rule, and who is entitled to make it

`plumb.hurt()` decides whether tree-sitter can be quoted about a byte. It used
to decide by **ancestry**: a recovery node anywhere above the byte and the byte
was unadjudicable. That is a verdict about a file wearing the shape of a verdict
about a byte, and on verilog the two are 94,657 bytes apart.

This lane made it ask the node actually covering the byte, swept every reader,
and built the check that would have caught it.

| file | what it is |
|---|---|
| `RESULT-1-cover.md` | the dossier: the sweep, the corpus re-derivation, the residue |
| `residue.py` | the 943 bytes the finding lane declined to check, checked against Verible |

The committed instruments live in `tool/`:

- **`plumb.py decline`** — every row's refusal and on whose authority, with four
  assertions. Two are the invariant; two exist so it cannot pass vacuously.
- **`plumb.py verify`** — three cheap assertions on a tree written out in the
  file, so the ordinary tripwire run catches a revert without the corpus sweep.

```
python3 tool/plumb.py decline              # corpus-shaped, ~70 s
python3 tool/plumb.py verify               # ~5 s, includes the same claim
python3 research/joinery/cover/residue.py  # the verilog residue, needs Verible
```
