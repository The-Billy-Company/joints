# Result 1 — the sweep, and the one prediction that failed

Measured 2026-08-05, macOS arm64, Zig 0.16.0. Five of the six predictions in
[`PREDICTION-1-sweep.md`](PREDICTION-1-sweep.md) held. **1f failed**, and the
way it failed is the useful part.

## The sweep, classified by what the bytes reach

Every `asBytes` / `sliceAsBytes` / `bytesAsSlice` under `src/`, each element
type resolved.

| Where | Views | Reaches | Verdict |
|---|---|---|---|
| `kernel/lex/lexicon.zig` `freeze` | `Head` · `Dfa.PatRun` | **disk** | the known defect, repaired by `flat` |
| `kernel/lex/lexicon.zig` | `[]u32` (`declined`, `trans_*`, `reach`, `ordinals`) | disk | seamless |
| `folio/collate.zig` `view` | `Record(k)`, any section | **disk** | seamless — now gated |
| `folio/forme.zig` `intern` | `[]Said {u32,u32}` · `[]u32` | hash | seamless — now gated |
| `kernel/joint/roster.zig` | `[]const State = []const u32` | hash | seamless |
| `kernel/joint/cursor.zig` | `ledger.Id`/`enum(u32)` · `[]Symbol` · `[]u32` | hash | seamless |
| `press/lr0.zig` · `press/press.zig` | `[]const Item`, `packed struct(u64)` | hash | seamless |
| `press/lalr.zig` | `u32` slot · `[]u64` folds | hash | seamless |
| `press/grammar.zig` `dedup` | `[]const Symbol` · `i16` · flattened optionals | hash | seamless, and deliberately so |
| `press/spread.zig` | `[]u32`, flattened optionals | in-process name | seamless |

**1a held**: nothing else reaches disk with slack. **1b held in the negative,
which is worth stating plainly** — every hashed element type here is seamless,
so the hash paths are sound. Not by discipline: `lr0.Item` is a `packed
struct(u64)` because the author wanted it dense, and `roster.State` is a bare
`u32`.

### Whether that negative is gated, or still luck

It was luck. It is now gated, and the seam turned out to be smaller than the
count of interners suggested.

Ten byte-keyed hash sites across six files sounds like ten places to guard, and
that framing is what makes it look like a refactor. Resolve each one's element
type and there are **three named types and two scalars**: `lr0.Item` (`lr0.zig`
twice, `press.zig` three times), `grammar.Symbol` (`grammar.dedup`, and
`cursor.treading` over the symbols above a limb), `roster.State`, plus bare
`u32` and `u64` runs in `forme`, `cursor` and `lalr`. The edit that would break
any of them is a change to a **type declaration**, not to a call site — so the
assertion belongs at the declaration, and three of them cover every site.

`irregex` closed its hash side by putting the predicate inside `mix.SliceCtx`,
because it *has* a shared context. Joints has none: every one of these maps
declares its own `struct { hash, eql }` inline, over key shapes that are not
each other (`Key{kernel, mark}`, a tuple of two slices, `[]const State`, and two
`StringHashMap`s already keyed on `[]const u8`). Giving them a common context is
a real refactor and it would be buying the same guarantee twice.

Two of the three assertions are trivially true today — a bare `u32` owns its
bytes — and that is the argument for writing them at `pub const Symbol = u32;`
rather than in a comment. They cost nothing, and the day someone widens one they
are the difference between a build failure and two identical right-hand sides
that quietly stop deduplicating.

All three spell it `std.meta.hasUniqueRepresentation` rather than importing
`leaf.seamless`. That is not a second spelling of the rule — the rule *is* std's
predicate, and `seamless` is a wrapper with a better error message. Importing
the wrapper would mean `press/` reading `folio/`, which reverses the one
production arrow this package's zone contract is built on. One law and a cycle
is worse than one law spelled by std.

Both assertion shapes were checked to actually fire, because a decorative gate
is the failure mode this whole dossier is about: an in-struct `comptime` block
over `struct { hi: u32, mask: u64 }` errors when the type is referenced, and a
top-level one errors when the file is merely imported and nothing in it is used.

`grammar.zig`'s `dedup` is the exception that already knew. It flattens
`?u32` to `maxInt(u32)` before hashing, with a comment saying an absent optional
leaves its payload bytes undefined and "feeding those to a hash is how a
deduplicator starts giving different answers on different runs." That is this
class, correctly handled, in this repository, before anybody named it.

**The sibling engine had one live site**, written up next door in
[`irregex/research/seams/RESULT-1-seams.md`](https://github.com/The-Billy-Company/irregex):
`Op.uclass` is `[]const [2]u21`, read as bytes by **both** `hash` and `eql`, so
two byte images of one `\p{L}` fail to intern as one node. Measured on both
arms, it costs **zero** nodes today — the parser's store path zero-extends, so
the byte image is canonical by code generation rather than by contract. The fix
stands because the contract is what a second target or a second store spelling
will honour; the number is recorded so nobody rediscovers the type and assumes
it was expensive.

## 1d held, and it was in the fix

`flat` — the twelve-line repair the press dossier landed — guarded itself with
*"is this field an integer"*. `@sizeOf(u21)` is **4** and `@bitSizeOf(u21)` is
**21**, so an integer field can carry eleven bits of the source's slack into the
zeroed cell. The guard would have admitted the exact bug it exists to prevent,
one level down, where nobody would look for it. This is the fourth or fifth time
on this problem that a flattering number turned up inside somebody's own fix; I
went looking for mine because the brief said to expect it, and it was there.

The predicate is now `std.meta.hasUniqueRepresentation` — the same one
`std.mem.eql` consults before it will `memcmp` a type, and the same one the
section gate below uses. One law, one spelling.

## The gate (1c held)

`leaf.seamless(T)` is a comptime `@compileError` when `T`'s fields do not tile
it, and the roster is derived rather than listed:

```zig
comptime {
    for (std.enums.values(Kind)) |k| seamless(Record(k));
}
```

A section added tomorrow is checked without anyone remembering this exists. It
covers `collate.view`, which is the half `flat` cannot: the reader casts the
mapping straight to `[]Record(k)`, so there is no writer to route through, and a
record that grew an alignment hole would be read four bytes to the left from the
second row on — a silent misread that the schema digest cannot see, because the
digest spells the fields and the hole is what the fields are not.

`forme.Said` carries the same assertion for the same reason on the hash side.

**Anti-vacuity, three ways**, because a `for` over an empty roster passes and a
predicate that says yes to everything passes:

1. the walk counts and asserts it saw `kind_count` records, so the set is the
   whole directory rather than a leftover subset;
2. it asserts at least eight of them are `struct`s, so the gate is not true of
   a format made entirely of `u8` and `u32`;
3. it asserts the predicate still says **no** — over `struct { hi: u32, mask:
   u64 }`, the shape that put four bytes of this process into every folio, and
   over `extern struct { a: u32, b: u64 }`, the near miss with no visible gap.

## 1e held: zero of 665 board cells moved

The measurement, because a claim like this is only as good as the arms.

One snapshot of `src/`, copied twice. The **after** arm is the tree as it
stands; the **before** arm is that same snapshot with exactly my three edits
removed — `diff -rq` between the arms reports three files and no others. Both
arms were built **at the same path**, sequentially, so nothing a compiler
embeds about its own location can differ. Each binary then boarded into its own
folio cache under its own `JOINTS_WORK`, and the two `--json` boards were
compared cell by cell with the stamp's volatile fields named and excluded one at
a time rather than wildcarded.

> **665 cells compared, 240 of them damage or structure numbers, 0 moved.**

The comparator's own anti-vacuity: perturbing one cell by one makes it report
exactly that cell. So the zero is a measurement rather than an empty walk.

Attribution, since the board does not match the numbers this lane was handed.
`standing` reads 67.4% against a briefed 66.30%, `describes` 95,150 against
97,280, `unbound` 115,139 against 120,534 — while `built + orphan + rubble +
spoil = 526,798` and 12 of 30 whole match exactly. **None of that is this
lane's**, and the evidence is in the same file I was editing: a sibling is
mid-flight in `folio/leaf.zig` taking the folio format from version 3 to 4,
adding `ProductionRecord.rank: i32` and a fourth `ConflictClass`. A rank a fork
uses to order its own readings is precisely what moves `describes` and
`standing`. Their new record is seamless, incidentally — sixteen bytes of four
`u32`-wide fields — so it passes the gate this lane added under it.

## 1f failed: a binary digest is not an oracle for behaviour

I predicted the two arms would produce byte-identical binaries, since every
difference between them is a `comptime` block, a `test` block, or a comment.
They came out **1,763,160 bytes each and with different `sha256`**. Same size,
different bytes: the added comment lines shift the DWARF line program, and the
digest cannot tell a moved line table from a moved instruction.

So the cheap check was not available and the board diff above was not
belt-and-braces, it was the only instrument. Worth writing down beside the
dossier next door that says a *folio's* sha256 is not an oracle either: the
temptation to reach for a digest as a proxy for "did anything change" is the
same temptation both times, and it is wrong for the same reason — a digest
answers a question about bytes when the question was about meaning.

## Near-misses rejected

- **`press/spread.zig` building a name out of `sliceAsBytes(words.items)`** read
  like a serialization site. It is `[]u32` with optionals already flattened to
  `maxInt(u32)`, and the result is an in-process key.
- **`kernel/joint/cursor.zig` hashing `ledger.Id`** looked like a struct. It is
  `enum(u32)`.
- **The whole `press/` hash family** looked like the richest seam in the sweep —
  six interners keyed on `sliceAsBytes` — and every one of them views `[]const
  Item` where `Item` is `packed struct(u64)`. Nothing to fix. I spent longer here
  than anywhere else and came away with nothing, which is the correct outcome and
  not a wasted hour. It is a clean negative rather than a gated one until the
  assertions above, which is a distinction I did not make the first time I
  reported it.

## The instrument I trust least

**`tool/stamp.py`'s `DRIFT`, on exactly the binary you pinned to avoid drift.**
`stamp` infers a binary's source tree by walking up from its path looking for a
`build.zig`. Above a private prefix there is none, so it falls back to the live
repo and then compares the live repo against itself — `drift` is `False` for
every pinned binary, permanently. The one binary you took out of the shared
`zig-out` *because* you expected the tree to move underneath it was the one
binary that could never report that it had, and it would have printed a clean
stamp under the false before/after that started item 2 of this brief.

That is fixed here — `tool/pin.py` records the tree digest beside the binary at
build time and `stamp` reads it — but the general shape is what to distrust: an
instrument that infers a fact it could have been told, and whose inference
degrades silently in exactly the situation you reached for it.

Fixed is a claim, so it was checked in the direction that could embarrass it as
well as the one that could not. A pin whose tree has moved prints
`DRIFT — the binary's tree 98abef26d is not the repo's 7053c3169`; a pin built
from the tree as it stands prints no `DRIFT` at all, so the guard is not simply
shouting; and **the same stale binary with its `pin.json` withheld** prints no
`DRIFT` and reports the live tree as its source, which is the old behaviour
reproduced beside the new one. A guard that has stopped lying and a guard that
works are different claims, and only the middle and last rows separate them.

Runner-up: **the `zig build test` shard runner under contention.** This lane
produced a false red by leaving three of its own probe processes spinning at
100% and then `kill -9`ing what it took to be its zombies, one of which was the
build's own shard 22/32. The suite reported `process terminated with signal
KILL` and 71 of 73 steps green. Every red here needs its cause named before it
is reported, and "I killed it" is a cause.
