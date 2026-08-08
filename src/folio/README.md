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
| `forme.zig` | Locks the parse table into the interned shape that makes a folio small - the same job the metal frame of that name does for a page of type. |
| `impose.zig` | The writer. Two passes: intern every string, then lay the sections out at eight-aligned offsets and seal. |
| `collate.zig` | The reader. `open` proves the whole layout; after it, an accessor is a slice. |
| `audit.zig` | The part of `open` that doubts the *contents* - every id, span, and tag inside the sections. |
| `binding.zig` | Hands a mapped folio back as the three types a parse takes, so `joints parse x.folio` costs a map instead of a press. |
| `codex.zig` | Binds several folios into one file, which is the whole of the "N languages, one binary" claim. |
| `folio_test.zig` | Round-trip field by field, one rejection test per failure mode, and two fuzzers. |

## The shape

One header, one fixed directory of 31 sections, then the sections, then a
32-byte BLAKE3 seal. Every section is `count * stride` bytes at an eight-aligned
offset, so checking one is a multiply and two comparisons rather than a parse  - 
which is what lets the reader prove the entire layout before it trusts a single
byte of payload. Every integer is little-endian on disk regardless of host.

Loading allocates nothing. `Folio` is a pointer, a parsed header, and 31
directory rows; every accessor is a view into the mapped bytes. A big-endian
host is refused rather than byte-swapped, because swapping means copying the
tables and not copying them is the point.

Three of the 31 are **reserved**: named and carried, always empty, with no reader
here. They are byte-opaque, which is the whole trick - the schema digest spells
each record's fields, so a section reserved as a *shape* would break the schema
the day somebody filled it, and reserving one as bytes does not. So three areas
that each need a section cost one version bump between them instead of three, and
whichever lands first fills its section without another. A reader that meets one
with records in it refuses (`FolioReservedSection`) rather than answering as
though they were not there; see `leaf.reserved`.

## Fail-closed, and what that costs

A folio a future version could silently misread is worse than one it refuses to
load. So: the version must match exactly, and a **schema digest** derived from
the record types has to match too - that one catches the case where somebody
adds a field to `ProductionRecord` and forgets what a version number is for.
There is no recognized-prefix path and no field the reader will skip. An
undefined flag bit is a refusal, not a mask, because an unknown bit is a fact
somebody meant to carry.

Every refusal is a named error. `open` is the only place that ever doubts the
file, and it doubts everything: 19 error cases, and a rejection test for each of
the 18 a little-endian host can produce.

## What is in a folio and what is deliberately not

In: symbol names byte-exact (every `highlights.scm` in the world is keyed on
them), terminal patterns and lexis, shapes, aliases and field names, the
productions with their steps and their dynamic ranks, the dense action table,
and per state the goto edges and the completed productions.

Also in, and easy to miss because it reads like a report: the contested cells
and the frayed ones, each with the action the table chose, one of the readings
it dropped, and the rules party to it. They are here because a GLR loop uses
them - `Forks` is an index over exactly this section - so they are table, not
commentary.

Out: everything the press *consumed* - step precedence, associativity, the
author's declared ambiguity groups. Also out, and this one was in once: the
kernel items that identify each state, which no parse and no tree build reads.
A folio is the table, not the argument that made it.

`prec.dynamic` is the one precedence that is *not* a press input and so is the
one that stays. A static rank resolves a cell while the table is built and the
loser is gone before a parse begins; a dynamic one resolves nothing, the cell
keeps both actions, and the rank is the tie-break between readings that are all
still alive at the end. A fork re-ranking its own versions - what tree-sitter's
GLR does at run time - has to read it from the file or compare zeros.

The goto edges are not redundant with the shifts in `action`. Precedence can
delete a read from a state that still has the edge, so anything that wants to
know what the automaton *could* have done needs the edge rather than the
verdict.

## A field the press adds and the file does not carry

This is the failure this directory is most exposed to, and it does not announce
itself. A press-side struct grows a field; its `leaf` record has no slot; the
writer does not write it; `bind` fills it with the type's default; and every
check anybody owns still passes. Worse than passing: a corpus board that presses
most of its rows from folios then reports *every grammar byte-identical, nothing
moved*, which is a lie in the direction of "your change did nothing" and whose
correct response is to abandon a change that works. A `switch` does not catch it
- a switch fires on a **rename**, and the new field is silent on both sides.

So it is caught twice, deliberately at two different levels.

`impose` opens with a **ledger**: a written roster of every field of
`lalr.Conflict`, `settle.Frayed` and `lalr.Tables`, and a `comptime` block that
asserts the roster and the struct are the same set in both directions. A new
field fails the build with its own name and the two things that may be done
about it - give it a slot, or name it in the ledger with a comment saying why
the file does not need it. Not to forbid a field, but to make its absence a
decision somebody made rather than one nobody noticed. The same block asserts
that the three press enums and their `leaf` twins have the same names on the
same ordinals, because the ordinal is the file format: appending is safe,
reordering renames every folio already written.

The ledger cannot see a field that is accounted for and written *wrong*, so
`folio_test` closes the other half. The round trip compares conflict and frayed
records field by field through `std.meta.fields` rather than against a list
somebody maintains, and the fixture grammar was extended until it presses an
`unwritten` cell, which the test asserts is there - a reflective comparison over
an empty conflict list is a green light for nothing. Adding a class means adding
a rule to that grammar that provokes it. `joints mint
<grammar.json>` makes the same comparison on the way out - it presses, writes,
maps the file back and checks the reloaded table against the one still in
memory - so any grammar on disk is a case you can run.

## What it measures

`joints mint upstream/grammars/<lang>.json`:

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
