The Python binding has an import contract: `bindings/python/binding.zone`,
governing `joints-python` the way `charter.zone` governs the Zig side.

There is no binding yet - `joints/__init__.py` is a docstring and a version,
holding the name on PyPI while the engine is still Zig only - and that is
exactly the state worth pinning. The contract says zero hops and no imports, so
the first real module lands against a stated shape instead of inventing one on
the way in.

Needs `zoning` 1.3.1, which is where the `python` dialect and root-anchored
contracts both arrive.
