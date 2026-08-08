Editing `src/idiom.zig` made every board print `STALE - src/idiom.zig is newer
than the binary; rebuild before believing this`, and rebuilding did not help.

It could not. `charter.zone` names three faces and only `root.zig` is the CLI's
module - `proof.zig` roots `zig build test` and `idiom.zig` roots `zig build
idiom`. No byte of either reaches the product, so `zig build install` writes no
new binary, the mtime stays behind whatever you just edited, and the warning is
**permanent rather than transient**. That is worse than the markdown false alarm
this same denylist already fixed, because a test edit at least clears at the next
real build, and a gate that cannot be satisfied by doing what it asks is not
being cautious.

Both are excluded from the mtime side only. The digest still hashes them, because
"is this the same tree as over there" is a different question from "can this
binary be believed" and drift wants the whole answer. All 7 stamp hazards still
fire, STALE among them - what moved is which files can trip it, not whether it
can.
