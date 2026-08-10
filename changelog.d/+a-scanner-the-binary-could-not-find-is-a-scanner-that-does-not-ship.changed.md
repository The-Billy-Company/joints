`build.zig` now embeds every `customary/*.json` into the binary, and
`Scanner.compile` reads that shelf for a grammar that arrived without a book.

There were three ways to a book before, and all three needed somebody to say
where it was: a typed `--customary`, the `JOINTS_CUSTOMARY` knob, and a
`<stem>.customary.json` beside the grammar. A folio minted with `--customary`
carried one, so the gates and the harness always had them. Everything else did
not. A bare `joints lex html.json`, the C ABI, and every library embedder found
no book and fell through to the hand-written scanner:

    $ joints lex upstream/grammars/html.json <file>      # before
      8 terminal(s) answered by hand
    $ joints lex upstream/grammars/html.json <file>      # after
      8 terminal(s) answered by customary

That asymmetry is what made every hand permanently load-bearing, and it is the
real finding of this rung. A hand is compiled in and always there; a book needed
a path. So no amount of transcription could retire one - the binary still
depended on the fallback at any offset reached without a path typed. Rung 3
finished eight books and *zero* hands became deletable, which reads as the
transcription being incomplete and was actually the shipping being incomplete.

Embedding does not pick a default directory. It deletes the question, which is
the objection `intake.zig` raises against defaulting to one ("nothing has to
guess a repo root from a binary's cwd"). The three deliberate ways still outrank
the shelf, so a typed `--customary` and the knob behave exactly as before - and
because `tool/stamp.py` hands the knob to every parse the harness makes, the
shelf is never consulted under the board or the differential and cannot have
moved a number there.

220 KB of books in a 2.9 MB binary. The shelf is generated off the directory
rather than listed, so adding a book is adding a file; `charter.zone` carries the
grant, because a module leaving the package is a decision somebody writes down.
