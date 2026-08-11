`stamp` warns `STALE` when something under `src/` is newer than the binary it is
standing on, and it already excluded `src/proof.zig` and `src/idiom.zig` because
neither reaches the CLI - editing one wrote no new binary, left its mtime behind,
and made the warning permanent instead of transient. The fragment that landed
that fix named two roots. There are four.

`src/surface/abi/` is the root module of `libjnt` - its own `addLibrary` in
`build.zig`, reached from `exports.zig`, named by nothing on the CLI's side of
the tree. So the first ABI edit in a while turned `STALE` on for every
measurement in the repo and no rebuild could turn it off. `python3 tool/order.py`
printed a green gate under a line telling you not to believe it, which is worse
than either verdict alone.

Excluded as a directory prefix rather than a file, because `bank.zig` and
`loom.zig` are reachable only through `exports.zig`, so the island stands or
falls together. Only the mtime side takes the exclusion; the digest still hashes
every byte, since "is this the same tree as over there" is a different question.

Worth saying plainly, because the denylist has now grown twice by the same
route: the predicate is really asking "could this file have moved *the binary I
am standing on*", and it has no idea which binary that is - `home()` always
derives the CLI. `libjnt` is emphatically a product, more of one than the CLI for
anybody linking it. If `stamp` ever stands on the library, this wants a binary
argument and not a fifth entry.
