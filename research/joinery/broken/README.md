# broken/ - the case nothing had ever asked

Every file in `corpus/` is valid. Every held-out file in the breadth sweep is
valid. So every number in this dossier is measured on input that parses, and
this is an *incremental* parser, whose whole reason to exist is a buffer being
edited. A buffer under edit is syntactically broken most of the time; between
`if (` and `if (x)` every intermediate state is invalid, and in an editor that
is the common case rather than the exception.

These are the fixtures that ask what happens then. Read them with
`tool/recover.py`.

## The shapes

Twenty-five files, one deliberate break each, in the four grammars that are
byte-exact on valid input - java, javascript, typescript, json. That choice is
the control: a difference here cannot be blamed on a grammar we could not read
anyway, because on the whole ledger program in those four languages we agree
with tree-sitter to the byte.

| Break | What it is |
|---|---|
| `unclosed-brace` | a block that never closes; the file ends inside it |
| `unclosed-bracket` | `[1, 2, 3;` - a list closed with the wrong byte |
| `unclosed-paren` | `f(x {` - a parameter list closed with the wrong byte |
| `unclosed-string` | a quote opened and never closed, so the rest of the line is swallowed |
| `dangling-keyword` | a keyword with nothing after it |
| `stray-token` | a byte the grammar has no terminal for, mid-statement |
| `mid-word` | `func` where `function` was being typed - the edit caught halfway |

Every fixture has **valid code after the break**, and that is the load-bearing
part of the design. Without it, "does it recover, or does it just stop?" has no
answer; with it, the question is simply whether anything past the break gets a
node.

json has no keywords and no `mid-word` to catch, so it carries four of the seven.

## What they found

tree-sitter returns one root spanning the whole file on all twenty-five, marking
its repairs with `MISSING` (zero-width, where a byte should have been) and
`ERROR` (a subtree it could not place). outliner returns one root on none of
them. It has neither node kind, and hands back a forest of partial roots plus a
verdict naming the byte.

The verdict is the distinction worth keeping:

- **`truncated`** - the lexer read every byte and no root ever closed. The
  forest still covers the code after the break; it is simply not joined. Five of
  the twenty-five.
- **`stray byte at N` / `unexpected X at N`** - the parse stopped at N and never
  looked at N+1. Everything after the break is invisible. Twenty of the
  twenty-five.

One fixture is not broken at all. `javascript/dangling-keyword.js` is a bare
`return` at program level, which tree-sitter-javascript **accepts** - zero ERROR,
zero MISSING. We stop at byte 25. That one is an ordinary differential finding
that the corpus never asked, not a recovery gap, and it is worth more than the
fixture it arrived in.

## Adding one

Drop a file in the language's directory named for its break; `recover.py` walks
the tree and needs no registration. Keep valid code on both sides of the break,
keep it small enough to read whole, and prefer a break an editor would actually
produce over one contrived to be hard.
