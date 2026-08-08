`kernel/walk` was the one area whose tests lived inside the production file. 147
of `drive.zig`'s 398 lines were a fixture, a helper, and four tests, and they
were collected because `proof.zig` named `drive.zig` in its *production* list -
so the roster gate that refuses a suite which quietly shrank could not see them.
`tool/roll.py` counted twelve test files and there were thirteen sets of tests.

They are `drive_test.zig` now, named in the roster like every other one, and
`drive.zig` is 250 lines of parser with nothing else in it. The hand-built
JSON-shaped grammar moved with them, which is where it belonged: its `text`
terminal is `[^"]+` deliberately, and that fact is the premise of all four
tests rather than anything the parser needs to know.

Confirmed the tests did not quietly leave the suite on the way: all four appear
in the built test binary under `kernel.walk.drive_test`, and the full run is
green. Worth writing down that `-Dtest-filter` cannot answer this question - it
reports every shard that matched nothing as a failure, on a name that predates
the change just as readily - so the binary's own list is the thing to read.
