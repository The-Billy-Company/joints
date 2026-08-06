Ten agents share one `zig-out`, so a comparison arm spelled as a path is
whatever a sibling last installed there. That is not hypothetical: the press
lane had its reference binary rebuilt underneath it twice, once transiently
broken and once **silently rebuilt with that lane's own fix in it** — which
turned a pre-fix arm into a post-fix arm and made a before/after read
thirty-of-thirty for entirely the wrong reason.

`tool/pin.py` makes the safe path the short one. `pin.py build --name before`
runs `zig build -p .local/pin/before` — Zig's own prefix argument, no new build
plumbing — and writes a `pin.json` beside it recording the source-tree digest,
the commit, whether the tree was dirty, the flags, and the binary's own hash.
`path`, `show`, `list`, and `verify` read it back; `verify` re-hashes the binary
and re-surveys the tree, so a pin that a later `zig build -p` overwrote says so
instead of being trusted. `CONTRIBUTING.md` gains the recipe next to the
empty-`OUTLINER_WORK` trap, and a house rule: **a path is not a version** — say
which pin a number came from.

A prefix alone would not have been enough, which is the part worth writing down.
`tool/stamp.py` infers a binary's source tree by walking up from it looking for
a `build.zig`; above a private prefix there is none, so it fell back to the live
repository and compared that tree against itself. `DRIFT` was therefore
structurally unable to fire on the one binary you pinned *in order to* notice
drift, and it would have reported `ok` forever. It now reads `pin.json` when
there is one and believes the binary over a guess from its path. `staleness`
comes from the pin's recorded build-time mtime rather than the live tree's, so a
snapshot reads as never stale instead of as accidentally ancient.

A guard that stops lying is not the same as a guard that works, so it was
checked in all three directions rather than in the one that would have flattered
it — because "no longer silently self-comparing" and "actually fires" are
different claims and only the second one is useful.

| what was stamped | verdict |
|---|---|
| a pin whose tree has since moved | `DRIFT — the binary's tree 98abef26d is not the repo's 7053c3169` |
| a pin built from the tree as it stands | no `DRIFT` — only `TOLD`, which is correct |
| **the same stale binary with its `pin.json` withheld** | no `DRIFT`, and it claims the live tree as its source |

The third row is the old behaviour reproduced side by side against the second:
same binary, same digest, one of them able to say it is stale and the other
not. That is the whole of what the record buys.

Near-miss worth recording: the first version resolved the pin root with
`Path.cwd()` and `home()` resolved symlinks, so on macOS — where every path
under `/var` is a symlink — a repository reached through one read as a foreign
tree and reported drift against itself. Both sides resolve now.
