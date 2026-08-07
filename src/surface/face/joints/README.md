# joints - the CLI face

Seven verbs over one library. This folder's job is to turn whatever the
library refuses to do into a sentence a terminal can read and an exit code a
script can branch on - never a stack trace.

| File | Role |
|---|---|
| `main.zig` | Dispatch, usage, and the four machinery verbs: `grammar`, `state`, `lex`, `--version`. |
| `intake.zig` | The one door every verb reads a path through - `slurp`, and the diagnostic it never lets a caller skip. |
| `parse.zig` | `parse` - load a grammar or a folio, build a tree, print it. |
| `amend.zig` | `amend` - re-parse across an edit without re-reading the file. |
| `mint.zig` | `mint` - press a grammar into a folio, or read one back and check it. |
| `survey.zig` | `survey` - rung 1 of `research/joinery/TESTING.md`: does a segment collapse to one answer. |

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
4. **Read exactly one way.** `intake.slurp` is the only path any verb takes to
   a file's bytes. It returns `?[]u8` and prints its own diagnostic before
   returning `null`, so a caller never `try`s a read and never spells the
   "cannot read" sentence itself. See `intake.zig`'s own doc comment for why
   that module exists - five verbs used to say the same sentence five
   different ways.

## What "properly handled" means, verb by verb

Every call to a fallible library seam - `import.treeSitter`,
`scanner.Scanner.compile`, `press.tables`, `folio.bind`, `folio.pack`,
`folio.map`, `folio.writeTo` - is wrapped at its call site:

```zig
var gr = import.treeSitter(gpa, source) catch |e| {
    try w.print("joints: cannot import {s}: {s}\n", .{ path, @errorName(e) });
    return 2;
};
```

or, where the library returns an optional atop the error union (a scanner
that compiled fine but found no lexable terminal is a `null`, not an error):

```zig
var sc = (scanner.Scanner.compile(gpa, &gr) catch |e| {
    try w.print("joints: cannot compile {s}'s scanner: {s}\n", .{ gr.name, @errorName(e) });
    return 2;
}) orelse {
    try w.print("joints: {s} has no lexable terminal at all\n", .{gr.name});
    return 1;
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
wrong. `press/lr0.zig` and `press/press.zig`, by contrast, lean on Zig's
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