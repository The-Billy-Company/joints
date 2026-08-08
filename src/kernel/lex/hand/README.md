# hand - the memory a table cannot hold

Ten of the eleven grammars upstream hand some terminals to a C function we do not
link and never will. Most of what those scanners do is recognize a spelling the
DSL could not host, and `../outside.zig` answers that with a table of rows.

These seven files are the rest: the cases where the answer is a function of the
bytes **and a memory every previous token built** - a column stack behind
`_indent`, a heredoc's tag, which fence opened a Python string, what element is
still open in an HTML document. That is a different animal from a row, so it gets
a different seam rather than a cleverer table.

They are the *hands*, and they are entirely internal. Nothing outside
`kernel/lex/` may name one - the charter seals this area through
`../scanner.zig` - and nothing in here imports anything above it. `../outside.zig`
is the only caller: it stays at the area root because it is the hub that drives
all seven and the one file here that knows what a grammar is. The hands
themselves know about bytes and about their own memory, and that is all.

| File | The shape it remembers |
|---|---|
| `offside.zig` | The offside rule - Landin's name for it, and Python's whole block structure. A stack of columns, and reading one line's indentation, blankness, comment column and continuation. |
| `fence.zig` | Delimited spans: read an opener, remember what closes it, hunt the match. A stack of open marks, a per-dialect opener, and one shared hunt. |
| `marrow.zig` | Content bounded by marks the parser itself lexes. Carries nothing: at a content offset the captured close is still in the bytes behind it. |
| `scry.zig` | A token whose extent is not the bytes that decided it. |
| `lineage.zig` | The stack of open elements: what encloses what, and when a close is implied. HTML is the language that needs it. |
| `writ.zig` | Layout the parser *commands*, where the offside rule is layout a scanner detects. Haskell's, and the inversion is the whole module. |
| `caesura.zig` | A break the line demands and the file never spells - JavaScript's automatic semicolon. Carries no memory either, and decides on the parser's expected set rather than on state. |

## Why a hand and not a row

Three properties separate them, and each one is why the seam is here rather than
in the table:

- **A hand runs before the slate.** The whitespace in front of a Python line *is*
  its indentation, so an extra must not eat it before the offside rule sees it.
- **A hand may answer zero-width.** The slate must refuse a zero-length match -
  nothing in a regex promises the next call differs - but a hand need not, and
  `outside.Spent` is why: zero-width answers are counted per offset under a hard
  ceiling, so the walk terminates whatever a hand does. Some of them move memory
  (every `_dedent` pops a column) and some move none (julia's five `_immediate_*`
  markers), so "the memory moved" was never the whole proof.
- **A hand is asked at end of input.** A file ending inside three open blocks
  still owes three dedents.

What generalises is the memory, not the scanners. Both stacks are fixed-capacity,
so a push cannot fail and nothing allocates mid-scan. An opener's *spelling* never
generalises, and `../outside.zig` does not pretend it does - `troupes` maps one
language's terminal names onto the parts of a shape, which is the most that is
true.
