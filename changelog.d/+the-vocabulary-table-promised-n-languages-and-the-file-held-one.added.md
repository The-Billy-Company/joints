The vocabulary table has said **"folio: the artifact: N languages, one
mmap-able file"** since the README was written, and the format held exactly
one. Worse than unimplemented: `mint a.json b.json` parsed both paths and
silently pressed only the last one, so the flag-shaped lie had a data-shaped
lie under it.

N languages is now a **codex** - a second magic (`OTLCODEX`) over the same
`.folio` extension, holding a sealed directory of titles and byte ranges with
one ordinary folio per member, each at its own alignment, each carrying its own
signet. The seal covers the directory rather than the members, so opening a
codex verifies the table of contents in microseconds and each member proves
itself only when someone actually picks it - the proportional-cost rule the
single folio already lived by. A `Volume` union hands both shapes to every
caller through one seam: `mapVolume` sniffs the magic, `pick` resolves a name.

`mint` now presses **every** path it was handed - several grammars, several
folios, or a mix - into one codex, and reading a codex back describes every
member rather than the first. `parse` and `amend` grew `--language=NAME`; a
single-title volume stays the default (nothing about the one-language workflow
moved), and a many-title volume with no `--language` refuses **with the roster
in the sentence** rather than guessing - a python file parsed with the rust
tables hands back a tree that looks fine and is wrong, which is the worst
possible success.

The refusals are typed at the pack site too: a repeated title, an empty member
list, and a title past `u16` are `PackError`s with their own names, not
assertion failures. Round-trip, reproducible-bytes, corruption, and
pick-refusal cases are in `folio_test.zig` beside the format they check.
