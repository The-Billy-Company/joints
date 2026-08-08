# joints - the CLI face

Seven verbs over one library. This folder's job is to turn whatever the
library refuses to do into a sentence a terminal can read and an exit code a
script can branch on - never a stack trace.

One verb per file, and a dispatcher that knows nothing about any of them beyond
the row in its table.

| File | Role |
|---|---|
| `main.zig` | The dispatcher, and only that: the `verbs` table, the arity guard it drives, the usage text built from it, and `--version`. |
| `intake.zig` | The one door every verb turns a path into a parser through - `slurp`, `grammar`, `tables`, `scanner`, and the diagnostics it never lets a caller skip. `choice` / `spellings` / `default` are the same argument aimed at a flag whose values are an enum's members. |
| `grammar.zig` | `grammar` - import a tree-sitter grammar, report its shape, group its conflicts by whose ambiguity they are. |
| `lex.zig` | `lex` - run the terminal scanner over a file with no parse state gating it, on purpose. |
| `state.zig` | `state` - one LR state whole, or a census, a holding search, or a chain. Owns its own four sub-forms. |
| `parse.zig` | `parse` - load a grammar or a folio, build a tree, print it. |
| `amend.zig` | `amend` - re-parse across an edit without re-reading the file. |
| `mint.zig` | `mint` - press a grammar into a folio, or read one back and check it. |
| `survey.zig` | `survey` - rung 1 of `research/joinery/TESTING.md`: does a segment collapse to one answer. |
| `whence.zig` | Where a state came from, for `state`'s chain and holding forms. |

Each verb's `run` has one signature - `(gpa, io, w, args) !u8`, where `args` is
everything after the verb - so the table holds function pointers rather than a
`switch`. A verb parses its own flags and its own sub-forms, because those are
its grammar and nobody else's; the dispatcher supplies only the arity guard,
from the `min` its row declares.

## The contract

Every verb function returns `!u8`. The `!` is the escape hatch for what this
process did not anticipate - an allocator out of memory, a bug - and it is
meant to stay empty in ordinary operation: **anticipated failure does not
travel through it.** Instead:

1. **Catch at the seam, not at the top.** The moment a library call can fail
   for a reason a user caused - an unreadable path, a malformed grammar, an
   unparsable scanner, a folio with the wrong magic - the verb catches it
   right there, prints one line, and returns. A `try` that reaches all the way
   back to `main` turns "you gave me a bad grammar.json" into a crash with a
   trace, which is the correct behavior for a bug and the wrong one for a
   typo.
2. **One sentence shape.** Every diagnostic this face prints follows
   `joints: <what> <path-or-name>: <error message>` (`@errorName(err)` for
   the last part, since the library's error sets already name themselves in
   sentence case - `FolioBadMagic`, `Unsplittable`) or, when there is no error
   value to name, a hand-written reason (`joints: {s} has no lexable
   terminal at all`). It always goes to the writer the caller already owns
   (`w` for a fresh run, `e` for `parse`'s stderr), never to `std.debug.print`
   or a second stream the caller doesn't control.
3. **Three exit codes, and they mean different things.** `0` ran and answered.
   `1` is a **clean negative answer** - the machinery worked and the answer is
   "no": a grammar with no lexable terminal, a `survey` run that tripped its
   kill condition, a folio that doesn't parse as one so it must be a grammar
   instead. `2` is a **failure** - the thing asked for could not be attempted:
   an unreadable file, a grammar tree-sitter itself rejects, a scanner that
   fails to compile. Getting this distinction right is why `lex` returns `1`
   when a grammar has no lexable terminal (a true fact about the grammar, not
   a defect in reading it) but `2` when the scanner fails to *compile* (the
   press's fault, not the grammar's shape).

   **The same condition is `1` in one verb and `2` in another, deliberately.**
   `lex` and `survey` were asked what a grammar tokenizes to, and "nothing" is
   that question's answer, so a grammar with no lexable terminal is their `1`.
   `parse` and `amend` were asked for a tree, and the same grammar is not a
   tree they built and rejected but a tree they could not attempt, so it is
   their `2`. The rule is the one above; only the question changes. This is
   load-bearing outside the binary - `tool/sound.py` tells a yaml SKIP from a
   wiring failure by exactly this code - so `intake.Unlexable` hands back
   *which* failure happened and lets each verb say what it is worth, rather
   than deciding for them.
4. **Reach the library exactly one way.** `intake` owns all four steps from a
   path to a parser - `slurp` for the bytes, `grammar` for the import, `tables`
   for the press, `scanner` for the terminal scanner - and no verb in this
   folder does any of them itself. The first three return `?T` and print their
   own diagnostic before returning `null`, so a caller never `try`s one and
   never spells the sentence itself. See `intake.zig`'s doc comment for why:
   five verbs used to say "cannot read" five different ways, and the same
   argument held for the other three, which were pasted seven, six, and four
   times.
5. **A flag's vocabulary is its enum.** `--mend` and `--policy` take an enum's
   members by name, so `intake.choice` resolves one and `intake.spellings`
   renders the whole set - for the refusal *and* for `main.zig`'s usage line -
   off `@typeInfo`. Never write the spellings out beside the lookup: both flags
   did, in opposite directions. `--mend` named four policies in a string next to
   the lookup that already accepted them, so a fifth would have been taken by a
   CLI that denied it existed; `--policy` refused without ever saying what it
   wanted. Their defaults live in `intake.default` for the same reason - the
   usage line named one as a word while the parser applied it as a value.

## What "properly handled" means, verb by verb

Every call to a fallible library seam is wrapped, and for the four on the path
from a path to a parser the wrapper is already written - a verb reads one line
and the sentence is spelled in `intake.zig`:

```zig
const source = intake.slurp(gpa, io, w, path) orelse return 2;
var gr = intake.grammar(gpa, w, path, source) orelse return 2;
var built = intake.tables(gpa, w, &gr) orelse return 2;
var sc = intake.scanner(gpa, w, &gr) catch |r| return intake.tokenless(r);
```

`scanner` is the one that hands back an error rather than a `null`, because its
two failures earn different exit codes and which one is a per-verb judgment -
see contract point 3. `intake.tokenless` is the mapping for a verb that was
asked about tokens; `parse` and `amend` write `catch return 2` instead.

The seams `intake` does not cover - `folio.bind`, `folio.pack`, `folio.map`,
`folio.writeTo` - are wrapped at their call sites, in the one verb that uses
each, following the same sentence shape:

```zig
const bytes = folio.pack(gpa, &gr, &built) catch |e| {
    try w.print("joints: cannot pack {s}: {s}\n", .{ gr.name, @errorName(e) });
    return 2;
};
```

The one place this loosens on purpose is a verb walking *several* files
(`survey`, `parse`'s multi-file form): one path's read failure is reported and
that path is skipped with `continue`, because the other files a user named on
the command line are still owed an answer. That is a different shape from
`intake.slurp`'s single-file `null`-and-return, not a violation of it - a
recoverable per-item failure and a fatal single-input failure are different
facts, and printing them differently is precise, not inconsistent.

## Why not one error type for the whole CLI

The library beneath this face already picks its error shape per module, and
on purpose: `folio.leaf` declares an explicit `Error` set for every way a
folio can be malformed, `folio/impose.zig` names `GrammarTooLarge` and
`StepsNotParallel` beside the allocator and scanner errors it composes with
`||`, and `kernel/lex/scanner.zig` splits `CompileError` from `FreezeError`
because those are different moments to fail at - all three are *public API
boundaries*, where a caller outside the module needs to `switch` on what went
wrong. `press/cast/lr0.zig` and `press/press.zig`, by contrast, lean on Zig's
inferred `!T` for `build`/`tables`: every caller, in `press/` or here, either
propagates the whole union or handles one specific member by name
(`error.Unsplittable`, inside `press.zig` itself), so a hand-maintained set
would just restate what the compiler already tracks precisely.

This face's job is to *catch* whichever shape a given seam returns, not to
re-declare it as a CLI-flavored union - a `CliError` wrapping "cannot import"
/ "cannot press" / "cannot bind" would be a second name for facts the library
already states, and every new library failure mode would need a second edit
here to stay in sync. `@errorName(e)` reads whatever the library named it,
inferred or explicit alike, so the two layers can't drift.
