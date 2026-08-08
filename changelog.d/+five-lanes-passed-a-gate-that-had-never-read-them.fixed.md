`zig build idiom` asks one question about every type that frees itself: does it
take `deinit(self)` or `deinit(self, gpa)`, according to whether the allocator is
reachable from the value. It asks it of a hand-kept list of `@import` lines,
because a proof about a package has to name the package and Zig cannot walk a
directory at comptime.

So the gate could be short, and it was, five waves running. `quotient`, `vellum`,
`grain` and `gloss` each shipped files declaring self-freeing types, each ran this
gate, and each was told zero - not because the code was right but because no line
reached it. Thirteen of the sixteen types that arrived over those waves had never
been read the day their lane closed. Every one of them turned out to be correct
when finally judged, which is the part that makes this worth fixing rather than
celebrating: a gate whose passes are silence tells you nothing when it passes, and
you only learn that afterwards.

The pin in that file is not the guard and could not be. It counts what the walk
judged, so it notices a type that departed and is structurally blind to an area
that arrived - the roster still names every file it lists, and the answer is just
quietly smaller.

`tool/roll.py` asks the missing question, from outside, where a directory walk is
available. It already held the same shape for the other hand-kept roster in this
package - every `*_test.zig` is named in `src/proof.zig`, or it does not run - and
this is that question about `src/idiom.zig`: every file declaring a `deinit` must
be **reached** by the lifecycle roster.

Reached and not named, because a facade is a legitimate way on and in one place
the only sensible one. `kernel/joint/joint.zig` is listed and the four files
behind it are not, so `roster.Pool` and its siblings are judged once through the
door instead of twice; demanding the leaf be spelled would demand a type be
judged twice, which is what the count is there to refuse. `surface/` is exempt and
cannot not be - the CLI and the ABI are separate compilations that reach the
library through a module name, so no import path from `src/idiom.zig` arrives
there at all.

Both hazards were injected before this was believed. A new file owning memory that
nobody lists fails with the file named; a roster line whose file is gone fails
twice over, once for the dead name and once for whatever it had been carrying.
Thirty-seven files own memory in this package and the proof now reaches all of
them, four of those only through a facade - so the hop is load-bearing rather than
generous. CI already ran `tool/roll.py`, so this blocks a merge with no wiring.
