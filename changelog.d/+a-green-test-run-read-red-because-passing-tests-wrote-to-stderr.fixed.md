`zig build test` passed 404 tests, reported `Build Summary: 108/108 steps
succeeded`, exited 0 - and printed ten `failed command:` lines on the way. It had
been doing that long enough that you learned to scroll past it, which is the
actual cost: a run whose output you have trained yourself not to read is a run
that cannot tell you anything the day it goes wrong.

One cause, three habits. brigade renders any shard that writes to stderr through
its failure printer, because a test runner that stays silent about a crashed
child is worse than one that cries wolf. So every stderr write from a *passing*
test was a false alarm, and there were three kinds.

**Narration.** Around twenty sites where a passing test prints its board - the
edit-cost tables, the seam locators, the census rows. brigade already ships
`note` for exactly this: stdout, which the build step captures and drops, and
which a failing shard discards along with everything else. These were only ever
on `std.debug.print` because it is the one everybody reaches for.

**Negative controls.** `amend_test.zig` runs four deliberately wrong composes and
asserts each one gets caught. Its assertions were `t.expectEqual`, which prints
`expected .accepted, found .unexpected` on the mismatch - and the mismatch is the
*point*. Thirteen lines of a green run describing failures it had asked for. The
comparisons are now silent when the run is bent and loud when it is honest, which
is the distinction the test was already making in every other respect.

**Library diagnostics.** `quire.verify` and `bough.verify` walked a tree, printed
the first fault, and raised. Their one caller is that same negative control, so
the library was narrating corruption somebody had ordered. Both now hand the
fault back - `quire.survey` returns it, `bough.verify` returns it, and a `Blame`
/ `Fault` formatter renders the sentence they used to print - because whether a
fault is news is the caller's question and only the caller has the answer.
`spine.verify` already had this shape; this is the package being consistent
with itself.

Those two formatters then had no cover at all, their only caller being a branch
that fires on a real defect, so `survey_test.zig` pins the rendered bytes of
both. The branch worth pinning most: half the faults a survey reports are "that
ref is not a node", so the sentence may not dereference the ref it is reporting
on, and an untested guard is a diagnostic that reads past the end of `nodes` the
first time you need it.

`fold.zig`'s announcement was the interesting one, because it looked like the
exception that should stay. It fires only on a defect, and its docstring was
right about the hazard: a `Report` computed on every import and read by nobody
is how `Scanner.declined` hid a twenty-thousand-byte bug. But printing from
inside the sweep did not make anybody read the report. It made the *library* the
reader, and left `import.zig` spelling the call `_ = try fold.nonterminals(…)`.
So the cure went where the docstring wanted it: `import.zig` reads it now,
and `Report.told` returns the sentence or `null`. The test that provoked it -
the only cover the line has, since no grammar of the thirty declines a fold -
asserts the rendered bytes instead, which checks more than the old probe did.

A green run is now silent. The three that still write to stderr each return an
error within a line or two.
