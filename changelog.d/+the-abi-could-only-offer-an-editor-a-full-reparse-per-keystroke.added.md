`libjnt` had one door, `jnt_parse`, and one way to look at what came back:
children, by index, downward. Everything the package is actually good at was on
the wrong side of it. `weave` - the incremental parser, the reason any of the
monoid work exists - was reachable from Zig and from nothing else, so a host
editor's only honest option was to re-parse the whole file on every keystroke.
And a tree you can only descend is a tree you have to re-walk from the root to
answer "what encloses the cursor", which is the single most common question an
editor asks.

Two additions, both behind the same `jnt_tree` handle. `jnt_weave_new` /
`_warp` / `_amend` / `_tree` is the edit door: warp a file once, amend it with a
byte range and a replacement, and read the tree back. `jnt_node_parent`,
`_next`, `_prev`, `_next_named`, `_prev_named`, `_by_field`, `_depth`,
`_covering`, `_spread` are the neighborhood. No cursor type - a node reference is
already a `u32` index, so a stateful cursor object would be a handle wrapping a
handle and one more thing for a host to leak.

Three decisions that went the other way from the first draft.

The weave gets its own `Scanner` and its own `Loom` rather than sharing the
parser's. Sharing is one compile cheaper per open file and it is wrong: the
scanner carries a ruling, and a `jnt_parse` call landing between two amends
would read a ruling the weave had moved. A per-file scanner compile is a real
cost paid once at open; a corrupted ruling is a bug you find in a user's editor.

`jnt_weave_tree` hands back a *borrowed* tree that the weave owns and refreshes
in place, and `jnt_tree_free` is a no-op on it. The alternative - a fresh owned
tree per amend - makes every host that stores the pointer wrong in a way that
only shows up under fast typing, which is exactly when nobody is looking at
their allocator. The cost is that the returned tree changes underneath a host
that holds it across an amend, which is the trade and is documented on the
function.

Tree soundness went lazy. `jnt_parse` was computing a full `Survey` walk on
every parse so `jnt_tree_sound` could answer from a field, which is a whole-tree
traversal per keystroke to answer a question most callers never ask. It is
computed on first ask and cached, and `jnt_weave_amend` invalidates it. That
cost `jnt_tree_sound` its `const` on the tree pointer, so `jnt_abi_version` is
now 2 - source-compatible for every C caller, but the signature changed and the
version is the only place that can say so.

47 exports, 47 declarations in `include/jnt.h`, checked against each other. 6
tests on the weave door, covering re-warp (reloading a file through a live
weave, which had to deinit and reinit the inner weave or carry the old file's
state into the new one) and the borrowed-tree lifetime.
