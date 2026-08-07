# joints

**Incremental parsing built on composable stack effects.** A parser generator
that reads tree-sitter's own `grammar.json`, so the grammars the ecosystem
already wrote are the input, and packs every language into one mmap-able file.

## This version exports nothing, on purpose

`0.0.0` reserves the name. The engine is Zig, reached through a C ABI (`libjnt`,
`jnt_` symbols); the Rust binding over it is not written yet. A stub that
returned plausible values would be worse than an empty crate, because a
dependency that compiles is one somebody builds on. Nothing will break when the
real binding lands, because there is no surface here to break.

## The idea

A parse step's effect on the stack is an element of a monoid, so the effects of
two adjacent regions compose into the effect of the region containing both.
Everything else follows from that one property:

| Property | Why it holds |
|---|---|
| Position independence | a region parses without knowing what precedes it - its effect is composed in afterward instead of inherited |
| Parallelism | the file cuts into segments that parse independently, then reduce pairwise |
| Incrementality | an edit invalidates only the segments it touches; the surrounding composition is reused, not re-derived |
| One artifact | N languages pack into one file, so a tool ships one binary and one file rather than a shared library per grammar |

The claim that composed segment effects really do reproduce a whole-file parse
has a falsifier measurable *before* a parser exists, so that measurement came
first - across eleven real grammars, with nothing disagreeing.

## Status

Built and tested: the grammar importer, the LR(0) collection with LALR
lookaheads and conflict resolution, the terminal scanner, the stack-effect
monoid and the cursor that composes it, the balanced tree, the concrete syntax
tree with delete-and-supply repair at every refusal, the incremental reparse
across edits, the packed multi-language artifact, the CLI, and the C ABI.

Not built: the SIMD first pass, the query engine, the settled succinct encoding,
and the quotient the size claim depends on - so the size claim is still a
target, not a result.

Source opens under [The Billy Company](https://github.com/The-Billy-Company),
alongside [irregex](https://github.com/The-Billy-Company/irregex) (the regex
engine), [gist](https://github.com/The-Billy-Company/gist) (indexed
ripgrep-parity search),
[relate](https://github.com/The-Billy-Company/relate) (similarity by
compression), and [blast](https://github.com/The-Billy-Company/blast)
(provenance and blast radius).

## License

Apache-2.0. See `LICENSE` and `NOTICE`.
