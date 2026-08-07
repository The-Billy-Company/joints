`collate.py cost` prices joints's mint against tree-sitter's generate-and-
compile, and to do it honestly with `--fresh` it deletes the built artifacts
first so the build time is a build rather than a cache read. It deletes
`lang/<name>/src/parser.c` and the seat's `<name>.dylib`, then shells
`tree-sitter generate` into `lang/<name>/`, then measures. **It holds no lock
while doing any of it**, and `lang/` is the directory every lane shares - the
same directory whose own comment calls it *"shared, and locked"*, and the same
mutation `oracle_build` was repaired for. The repair does not reach here,
because `cost` does not call `oracle_build`; it shells the CLI directly.

`collate.theirs` takes the shared side of `alone()` before it measures, so the
instrument knows the lock exists. The build path is the one that skipped it, and
`alone`'s exclusive side exists for exactly this: a second writer of a `.dylib`
hands the first lane a file it is halfway through `dlopen`-ing.

Found by `still.py sweep`, which walks every module in `tool/` and `research/`
for the places it puts bytes somewhere - 76 modules, 146 write sites in 47 of
them - and then runs what it can inside an observing seal. Demonstrated rather
than argued: `collate.cost` on json, under the seal, reports three writes into
shared state and one of them read back as evidence -
`.local/differential/lang/json/src/parser.c`, written by a child at
`collate.py:809 in timed`.

The seal's first pass over that same run reported **twelve** writes, eleven of
which were sibling lanes' files under `.local/strand/` and `.local/walls/`:
`timed` runs its children with `cwd=ROOT`, so the bracket had snapshotted the
whole repository and attributed an hour of ten agents' work to collate's child.
A bracket it cannot make sound now declines and says so, and the declining is
printed whether or not anything else fired - a detector that goes quiet when it
stops working is the shape this whole lane is about.
