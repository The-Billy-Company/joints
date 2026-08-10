`differential.py` now asks the preprocessor which headers a scanner opens, after
the regex has taken the ones it can see, and `bench.transcribe` carries every
authored file in `src/` rather than a list of the ones somebody remembered.

yaml reached no axis of the bench at all, because its oracle would not build:

    fatal error: 'schema.core.c' file not found

`includes` finds `#include "…"` with a regex, which is every include in 29 of
the 30 grammars. tree-sitter-yaml writes the thirtieth:

    #define _file(x) _str(schema.x.c)
    #include _file(YAML_SCHEMA)

There is no quoted string there to match, so the closure ended one file short. A
regex cannot resolve that - a preprocessor resolves it by definition, so `unseen`
asks clang. `-MG` is the whole trick: it makes clang *list* a header it cannot
find instead of stopping at the first one, so one call names everything missing.

It runs after the textual closure and takes only what is still absent from disk,
which keeps the regex authoritative where it has an answer - `includes` also
decides containment in `sandboxed`, and two walks disagreeing about what a
scanner includes is a fault this file already fixed once. No clang on the
machine, no opinion: the build that needs the file will say so itself.

`transcribe` was the second half. It copied `scanner.c*` and `*.h`, so it would
have left `schema.core.c` behind even once fetched. It now names what to *leave*
out - the three generated files and the CLI's `tree_sitter/` - which is the right
way round: a new authored file is carried by default, where a list of what to
take drops it silently and builds a parser nobody upstream can run.

yaml is now measurable on every axis, and the first thing it measured is not
flattering. A keystroke inside a `block_sequence` costs **16,884 us against
tree-sitter's 27.6** - 612x - and our own cold open of the same file is 16,978
us, so the edit is paying 99.4% of reopening the file. That is the `holds` slate
defect in `research/keystroke/`, now visible on a fifth grammar instead of
hidden behind a missing oracle.
