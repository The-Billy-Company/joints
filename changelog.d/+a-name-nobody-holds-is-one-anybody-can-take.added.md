`bindings/rust` and `bindings/python` - the two registry packages, published at
`0.0.0` to hold the name `joints` on crates.io and PyPI.

Neither exports anything, and that is the point. The engine is Zig behind a C
ABI (`libjnt`, `jnt_` symbols) and no binding over it is written yet, so a stub
returning plausible values would be strictly worse than an empty package: a
dependency that compiles is one somebody builds on, and then the first real
release is a breaking change against a surface that never worked. An empty
`0.0.0` cannot break, because there is nothing there to break. Each package says
so in its own description, on the line the registry shows in search results,
rather than burying it below the fold.

`jnt` - the short form that would have agreed with the symbol prefix and the
shared library - is already taken on crates.io, and crate names are permanent.
`joints` was free on both indexes, which is the better outcome anyway: the
registry entry is the first surface a stranger reads, and it should be a word.

Neither package carries a `repository` or documentation URL, though
[CONTRIBUTING.md](../CONTRIBUTING.md) already tells people to clone
`The-Billy-Company/joints`. That repository is not public yet, and a metadata
field is a promise the registry renders as a clickable link; a 404 on the one
page a stranger lands on is worse than an absent row. Both fields go in with the
release that ships beside the public repository. `homepage` points at the
organisation, which does exist.

The layout was already decided before this commit: `.gitignore` has carried
rules for `bindings/rust/target`, `bindings/rust/PROJECT_README.md` and
`bindings/python` since before either directory existed. The one piece not
ported from the sibling packages is the README mint - upstream, the registry
landing page is the repository's own README with its relative links rewritten to
absolute ones, because a visitor who lands on crates.io has nowhere else to look.
That rewrite needs a public repository to rewrite the links *to*, so for now each
package carries a short self-contained page instead, and the mint arrives with
the URLs it needs.
