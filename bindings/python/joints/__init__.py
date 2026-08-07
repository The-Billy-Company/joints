"""Incremental parsing built on composable stack effects.

This version is a name reservation and exports nothing
-----------------------------------------------------
There is no API here yet - not a narrow one, not a provisional one. The engine
is written in Zig and reached through a C ABI (``libjnt``, with ``jnt_``
symbols), and the Python binding over it has not been written. Publishing an
empty ``0.0.0`` is the honest way to hold the name while that is true: a stub
that returned plausible values would be worse than nothing, because a dependency
that imports is one somebody builds on.

Importing this package today gets you this docstring and ``__version__``.
Nothing will break when the binding lands, because there is no surface to break.

What the project is
-------------------
A parser generator and incremental parser that reads tree-sitter's own
``grammar.json``, so the grammars the ecosystem already wrote are the input
rather than something to re-author. What it does differently is algebraic: a
parse step's effect on the stack is an element of a monoid, so the effects of two
adjacent regions compose into the effect of the region containing both. That one
property buys the rest - a region parses without knowing what precedes it, the
file cuts into segments that parse in parallel and reduce pairwise, an edit
invalidates only the segments it touches, and N languages pack into one
mmap-able file so a tool ships one binary and one file instead of a shared
library per grammar.

The claim that composed segment effects reproduce a whole-file parse has a
falsifier measurable before a parser exists, and it was measured first, across
eleven real grammars.

Status
------
Early. The generator, scanner, monoid, balanced tree, concrete syntax tree with
repair, incremental reparse, packed artifact, CLI and C ABI all exist and are
tested. The SIMD first pass, the query engine, the settled succinct encoding and
the quotient the size claim rests on do not. Source opens under
https://github.com/The-Billy-Company alongside the sibling packages.
"""

# Kept in step with `pyproject.toml` by hand while this is the only fact the
# package exposes. It becomes generated the moment there is a build step to
# generate it from - a second hand-maintained copy of a version is exactly the
# drift `x-release-please-version` markers exist to prevent.
__version__ = "0.0.0"

__all__ = ["__version__"]
