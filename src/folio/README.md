# folio - a pressed grammar as one file

The claim: **a grammar is data, so a grammar is a file.** tree-sitter turns a
grammar into a C program, and everything painful downstream follows from that
one choice - a 30 MB `parser.c`, a shared library per language, an ABI window
between the two, 25 MB of WASM before a browser can highlight ten languages.
Here `press` turns a grammar into tables and this folder turns those tables into
bytes, so one binary plus one folio is every language.

| File | Role |
|---|---|
| `folio.zig` | The seam: re-exports, atomic publish (`writeTo`), and `map` - the mmap path that is the reason for the format. |
| `leaf.zig` | The on-disk vocabulary both sides speak: magic, version, the section roster, and the fixed-width record behind each one. |
| `impose.zig` | The writer. Two passes: intern every string, then lay the sections out at eight-aligned offsets and seal. |
| `collate.zig` | The reader. `open` proves the whole layout; after it, an accessor is a slice. |
| `audit.zig` | The part of `open` that doubts the *contents* - every id, span, and tag inside the sections. |
| `folio_test.zig` | Round-trip field by field, one rejection test per failure mode, and two fuzzers. |

## The shape

One header, one fixed directory of 20 sections, then the sections, then a
32-byte BLAKE3 seal. Every section is `count * stride` bytes at an eight-aligned
offset, so checking one is a multiply and two comparisons rather than a parse  - 
which is what lets the reader prove the entire layout before it trusts a single
byte of payload. Every integer is little-endian on disk regardless of host.

Loading allocates nothing. `Folio` is a pointer, a parsed header, and 20
directory rows; every accessor is a view into the mapped bytes. A big-endian
host is refused rather than byte-swapped, because swapping means copying the
tables and not copying them is the point.

## Fail-closed, and what that costs

A folio a future version could silently misread is worse than one it refuses to
load. So: the version must match exactly, and a **schema digest** derived from
the record types has to match too - that one catches the case where somebody
adds a field to `ProductionRecord` and forgets what a version number is for.
There is no recognized-prefix path and no field the reader will skip. An
undefined flag bit is a refusal, not a mask, because an unknown bit is a fact
somebody meant to carry.

Every refusal is a named error. `open` is the only place that ever doubts the
file, and it doubts everything: 18 error cases, and a rejection test for each of
the 17 a little-endian host can produce.

## What is in a folio and what is deliberately not

In: symbol names byte-exact (every `highlights.scm` in the world is keyed on
them), terminal patterns and lexis, shapes, aliases and field names, the
productions with their steps, the dense action table, and per state the goto
edges, the completed productions, and the kernel items.

Out: everything the press *consumed* - step precedence, associativity, declared
conflicts - and everything it produced as a report: contested and frayed cells.
A folio is the table, not the argument that made it.

The goto edges are not redundant with the shifts in `action`. Precedence can
delete a read from a state that still has the edge, so anything that wants to
know what the automaton *could* have done needs the edge rather than the
verdict.

## What it measures

`outliner mint upstream/grammars/<lang>.json`:

| Grammar | grammar.json | pressed in memory | folio | vs pressed |
|---|---|---|---|---|
| json | 12,913 | 10,996 | 7,664 | 0.70x |
| c | 237,474 | 3,277,158 | 3,049,320 | 0.93x |
| typescript | 281,518 | 12,857,674 | 11,811,888 | 0.92x |

The folio is smaller than the tables it came from because it drops the report
and packs spans instead of slice headers, and it is 12x the grammar.json for C
because a grammar.json is a description and a table is the expansion of it.
Three quarters of a large folio is the dense action table (76% for C, 75% for
TypeScript) at 23% and 20% density - that is the number worth attacking next,
and attacking it is a format version, not a rewrite.
