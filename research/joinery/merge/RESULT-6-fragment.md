# Result 6 - the work list was ranking suffixes

`walls.py board` is the map an agent reads to pick what to fix next. It ranked
six families by what each costs in bytes. **93% of those bytes are fragment**,
and when the column is split every family moves - including which one is first.

I found this by following the board's own ranking and watching it send me to the
wrong grammar.

## What the board said, and what was true

The board's byte column summed every wall's `cost` with no filter:

```python
def bytes_of(rows_in) -> int:
    return sum(p.cost for r, k, w in rows_in
               if (p := cost.get((r.name, k, w))) is not None)
```

`Priced.torn` was already on every one of those rows, and `run` already prints
the caution per grammar - *"subtract this before quoting a cost"* - because a
torn wall stands behind a **fragment**, a suffix whose openers round 1 left
behind, which is not text this parser meets reading the file whole. The board
never subtracted it and never showed it.

| family | board rank / bytes | on the document | overstated |
|---|---:|---:|---:|
| unrunnable external | 4th - 5,629 | **3,284** (1st) | - |
| separator refused | **1st - 25,477** | 826 (2nd) | 31x |
| permissive body pattern | 3rd - 10,316 | 385 (3rd) | 27x |
| bracket refused | 2nd - 20,021 | 66 (4th) | 303x |
| string delimiter | 6th - 57 | 21 (5th) | 3x |
| named terminal | 5th - 3,787 | 9 (6th) | 421x |

Every row changed place. The whole remaining wall tail is **4,591 bytes on the
document, not 65,392** - a 14x overstatement of the size of the remaining work.

Per grammar, the fragment share is near-total almost everywhere:

| grammar | behind | fragment | frag % |
|---|---:|---:|---:|
| sql | 3,483 | 3,480 | 99.9% |
| ruby | 663 | 662 | 99.8% |
| julia | 3,440 | 3,434 | 99.8% |
| verilog | 11,070 | 11,049 | 99.8% |
| zig | 12,024 | 11,966 | 99.5% |
| ocaml | 14,882 | 14,700 | 98.8% |
| bash | 503 | 495 | 98.4% |
| swift | 3,886 | 3,683 | 94.8% |
| haskell | 12,157 | 11,332 | 93.2% |
| **markdown** | **3,284** | **0** | **0.0%** |
| TOTAL | 65,392 | 60,801 | 93.0% |

markdown is the only grammar on the board whose wall cost is entirely on the
document, and it was ranked fourth.

## How the defect showed itself

I picked a target *from the board*: `macro_text`, verilog, 6,477 bytes over 3
walls - the densest cell on it, with the family blurb already naming a mechanism
("a permissive member survives to end-of-file"). It is 96.3% fragment.

Reading the actual bytes killed the target and found the defect. Byte 3710 of
`picorv32.v` is `` `ifdef RISCV_FORMAL `` **inside a module port list**. The
grammar declares `` `ifdef `` (`id_directive`, under `_directives`) but not
reachable from a port list, which is the upstream limitation `RESULT-4-walls.md`
already established. A minimal witness separates the two cleanly:

```verilog
module m (
	output reg a,
`ifdef F
	output reg b,
`endif
	output reg c
);
endmodule
```

```
scar 25 gave [ unexpected ` in state 2088, 1 heads, +7 tokens
scar 33..34 1B fell unexpected macro_text in state 766
scar 47..49 2B fell unexpected macro_text in state 562
scar 69..70 1B fell unexpected macro_text in state 562
scar 71..72 1B fell unexpected ) in state 0
verilog: weave on ` in state 2088: the cell is empty, and a merged lookahead is
a superset of every canonical one it stands for, so it is empty under every split
```

Delete the three directive lines and the same file **accepts as one root**. So
every `macro_text` byte is aftershock of one refused backtick: the mend drops the
parser into macro-definition context, where ordinary port declarations lex as
macro bodies. The peel already knew - it had marked them torn - and the board
had thrown that away.

## The change

`board` now computes `on doc` and `fragment` as separate columns and ranks on
`on doc`. `bytes_of` grew one keyword-only `frag` filter rather than a second
function, and `doc_of` is the one-line partial that names the important case.
Both columns print, because a fragment wall is a provenance and not a dismissal;
only one of them is an amount of work.

`walls.py gate` is unchanged in behavior and still green: every wall lands in one
of 6 known families.

The two columns **partition** - `on doc + fragment` reproduces the old total on
every family and on the headline (3,284 + 2,345 = 5,629; 826 + 24,651 = 25,477;
4,591 + 60,801 = 65,392) - so nothing was reclassified or double-counted on the
way. The old number is still there; it was just never one number.

## What this retargets

The corrected head of the work list, by document bytes:

| terminal | on doc | walls | grammar |
|---|---:|---:|---|
| `stray b'\n'` | 3,284 | 1 | markdown |
| `.` | 825 | 16 | haskell, sql, verilog |
| `(?:\))` | 385 | 8 | haskell |
| `` ` `` | 21 | 2 | verilog |

72% of everything left is **one cell in one grammar**. markdown declares 47
externals and `outside.zig` provisions none of them, so a bare `\n` produces no
terminal at all - `_line_ending` and `_soft_line_ending` are the two names under
that byte. haskell's `stray b':'` (1,164) and `stray b'>'` (1,132), which the
old board ranked as the next scanner work, are **100% fragment** and cost
nothing reading the document.

The three biggest *families* by the old ranking - separator refused, bracket
refused, named terminal - are together **901 bytes** on the document, over 97
walls. They are not where the remaining work is.

## Provenance

Every figure on this page is one survey, taken once and read twice - the old
arithmetic and the new one ran over the same `walls.py run --json`, so nothing
here is two measurements that might have drifted apart. Default depth; the
per-grammar peel reports verilog and haskell as lower bounds, which moves
`fragment` and not `on doc`.

```
stamp: outliner 40a520f18 at zig-out/bin/outliner built 2026-08-07T17:31:50Z
       from . 010af3c60 · repo fdda15a2a+29
```

`walls.py gate --from-json` green on the same survey: every wall lands in one of
6 known families.
