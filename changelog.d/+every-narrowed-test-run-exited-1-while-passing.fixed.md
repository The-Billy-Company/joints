`zig build test -Dtest-filter=folio` ran the folio tests, passed all of them, and
then printed two fatals and a red `Build Summary` over the top. It had been doing
that for as long as the test build has had three roots, and it is the documented
inner loop.

The cause is a good guard in the wrong place. `test` compiled three binaries - the
library, the CLI, the C ABI - and hung them all off one step. Brigade fails a
shard whose filter matched none of its tests, which is exactly right for one
binary, because you typo'd the name and a green run over zero tests is the worst
possible answer. Across three it is wrong: `folio` is not a typo just because it
does not appear in the CLI's 8 tests or the ABI's 5.

So the guard fired on every legitimate filtered run, which is worse than not
having it. A gate that cries wolf on the command you type forty times a day
teaches you to stop reading its output, and then it is not there for the one time
it was right.

One step per root now. `test` is the library; `zig build face` and `zig build abi`
are the other two, and `test` folds them in whenever nothing narrowed the run -
so an unfiltered run and CI still cover all three, and a filtered hunt names the
binary it hunts in. Brigade ships `narrowed()` for precisely this fold, with
a docstring describing this hazard, so the fix was reading the dependency rather
than patching it.

The guard still bites where it should: a real typo misses all 404 library tests
and fails, and each of the three steps judges the filter against its own count.
