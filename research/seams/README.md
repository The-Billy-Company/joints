# seams — the bytes a type does not own, everywhere else

[`../press/`](../press) found two record types whose bytes no field owns being
written straight to disk, by chasing one symptom. This dossier asks the question
that leaves open: **are there others**, in this repository and in the sibling
engine, and can the rule be a build failure instead of a habit.

A site in this class has three parts — a type with bytes no field owns, code
that turns a value of it into a byte sequence, and something downstream that
treats the sequence as if it meant the value. The third part is what sets the
severity, and the three are not close:

- **disk or a wire** — arbitrary process memory escapes into a file that gets
  cached, compared, and possibly shipped;
- **a hash or a comparison** — nothing leaks, but a byte image is not the value,
  so two equal values can be told apart by their slack. A map then keeps two
  rows for one key and the answer becomes a function of the allocator. (If the
  `hash` and the `eql` disagree about *which* question they are asking, it is
  worse still — the map's own invariant breaks rather than just its
  canonicalization.)
- **fully rewritten before use** — benign, and worth a line only where the
  reasoning is subtle.

| file | what |
| --- | --- |
| `PREDICTION-1-sweep.md` | written first, each claim with its falsifier |
| `RESULT-1-sweep.md` | every site classified, the gate, the zero-cells proof |

## What it found

Nothing else reaching disk here, and **every** hashed element type in this
repository seamless — `u32`, `enum(u32)`, `packed struct(u64)`. That is a clean
negative worth stating rather than a hole in the sweep, and it is now a *gated*
negative: the ten byte-keyed hash sites resolve to three named element types
(`lr0.Item`, `grammar.Symbol`, `roster.State`) and two scalar runs, and each of
the three carries a `hasUniqueRepresentation` assertion at its declaration —
which is where the edit that would break it lands. Two of those assertions are
trivially true today, which is exactly why they belong next to
`pub const Symbol = u32;` and not in a comment.

Two real things did come out of it. `flat`'s own guard admitted the bug it
exists to prevent: it refused a field that "is not an integer", and
`@sizeOf(u21)` is four while a store writes twenty-one bits. And the sibling
engine had a live site — `Op.uclass`'s `[]const [2]u21`, read as bytes by both
`hash` and `eql`, so two byte images of one Unicode class fail to intern as one
node. Measured on both arms it costs **zero** nodes today, because the parser's
store path zero-extends; the fix stands on the contract rather than on a number.
That half is written up in irregex's own `research/seams/`.

## The gate this leaves behind

`leaf.seamless(T)` — a comptime `@compileError` when a type's fields do not tile
it — applied over a roster **derived from the format**:

```zig
for (std.enums.values(Kind)) |k| seamless(Record(k));
```

so a section added tomorrow is checked without anyone remembering this exists.
It covers the half `flat` cannot: `collate.view` casts the mapping straight to
`[]Record(k)`, so there is no writer to route through.

Its anti-vacuity is three assertions in one test — that the walk saw every
section, that at least eight of them are structs rather than bare integers, and
that the predicate can still say **no** over the two shapes that started this.
A `for` loop over an empty roster passes, and so does a predicate that says yes
to everything; both read exactly like a clean bill of health.

## Measuring without being lied to

Every number here was taken against a **pinned** binary, because ten agents
share one `zig-out` and a comparison arm spelled as a path is whatever a sibling
last installed there:

```sh
python3 tool/pin.py build --name before   # zig build -p, and write the tree down
OUTLINER_BIN=$(python3 tool/pin.py path before) OUTLINER_WORK=.local/mine/work \
  python3 tool/standing.py --json
```

See [`../../CONTRIBUTING.md`](../../CONTRIBUTING.md#measure-against-a-pinned-binary-never-against-a-path).
The pin exists because a *prefix* alone is still a path: `tool/stamp.py` used to
infer a binary's source tree by walking up looking for a `build.zig`, find none
above a private prefix, fall back to the live repo and compare it against
itself — so `DRIFT` could never fire on the one binary you pinned in order to
notice drift. It fires now, and that was checked against the case that could
have embarrassed it as well as the case that could not: a moved tree reports
`DRIFT`, a current tree reports none, and the *same stale binary with its
`pin.json` withheld* reports none while claiming the live tree — the old
behaviour, beside the new one.
