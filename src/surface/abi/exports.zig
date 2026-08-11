//! `libjnt` - the C-ABI artifact's root, and nothing else.
//!
//! A different root from `src/root.zig` on purpose, the same split the
//! sibling packages keep: a Zig `export fn` is emitted by every compilation
//! that reaches it, so shims living in the library module would be duplicated
//! into every downstream artifact that imports it, and a host linking two
//! would hit duplicate symbols for a symbol it asked for once. Keeping the
//! `export fn`s here means the symbols exist exactly where the `.a`/`.dylib`
//! named after them is.
//!
//! Header: `include/jnt.h`, the normative statement of these signatures.
//! Bodies: `bank.zig`, tested without going through C.

const std = @import("std");
const builtin = @import("builtin");
const bank = @import("bank.zig");
const loom = @import("loom.zig");

/// Same upstream MSVC workaround the siblings carry: a static or object
/// artifact for any `-msvc` target cannot compile the default panic's stack
/// walk in zig 0.16.0, so that one target degrades to the message-only
/// handler and every other keeps full symbolication.
pub const panic = if (builtin.abi == .msvc)
    std.debug.simple_panic
else
    std.debug.FullPanic(std.debug.defaultPanic);

/// The C-ABI compatibility integer. Bump only for a breaking layout or
/// signature change; an additive symbol keeps it.
export fn jnt_abi_version() u32 {
    // 2: the weave door and the neighbourhood arrived, both additive - but
    // `jnt_tree_sound` lost its `const` and gained JNT_NOMEM, and a caller
    // holding a `const jnt_tree *` has to know.
    return 2;
}

/// The package semver, NUL-terminated and static, so a binding can gate the
/// shared library it loaded against the version it was generated from.
export fn jnt_version() [*:0]const u8 {
    return @import("build_options").version;
}

/// The sentence behind the last failing call on THIS thread, or "" after a
/// success. NUL-terminated, valid until this thread's next `jnt_*` call.
/// Reading does not consume.
export fn jnt_last_error() [*:0]const u8 {
    return bank.lastError();
}

// ── the bank: a file of languages ────────────────────────────────────────────

/// Open `path` - a folio, a codex, or a tree-sitter grammar.json - and write
/// the handle to `*out`. Which of the three it is decides what this costs:
/// the mapped two are milliseconds, the JSON is imported and pressed here.
/// 0 on success; negative with the reason in `jnt_last_error`.
export fn jnt_open(path: ?[*:0]const u8, out: ?**bank.Bank) c_int {
    return @intFromEnum(bank.open(path, out));
}

/// Release a bank. Every parser lent from it must be freed first.
export fn jnt_close(b: *bank.Bank) void {
    bank.close(b);
}

/// How many languages the bank holds. 1 for a folio or a grammar.json; a
/// codex answers its directory.
export fn jnt_bank_count(b: *const bank.Bank) u32 {
    return b.count();
}

/// The name of language `i`, as a borrowed pointer + length (NOT
/// NUL-terminated - it is a view into the mapped file). NULL when `i` is out
/// of range. `*len` receives the length when `len` is non-NULL.
export fn jnt_bank_title(b: *const bank.Bank, i: u32, len: ?*usize) ?[*]const u8 {
    const t = b.title(i) orelse return null;
    if (len) |l| l.* = t.len;
    return t.ptr;
}

// ── the parser: one language, standing ───────────────────────────────────────

/// Bind language `language` out of the bank and write the parser to `*out`.
/// NULL means "the obvious one", which exists only when the bank holds
/// exactly one; a codex of several is refused with its roster in
/// `jnt_last_error`, never guessed at. The parser borrows the bank: free
/// every parser before its bank, and use one parser from one thread.
export fn jnt_parser_new(b: ?*bank.Bank, language: ?[*:0]const u8, out: ?**bank.Parser) c_int {
    return @intFromEnum(bank.parserNew(b, language, out));
}

/// Release a parser. Trees lent from it must be freed first.
export fn jnt_parser_free(p: *bank.Parser) void {
    bank.parserFree(p);
}

/// The name of the grammar this parser parses, as a borrowed pointer +
/// length. Never NULL.
export fn jnt_parser_language(p: *const bank.Parser, len: ?*usize) [*]const u8 {
    const t = bank.parserLanguage(p);
    if (len) |l| l.* = t.len;
    return t.ptr;
}

/// How many externally scanned terminals this grammar declares that no lexer
/// rule can produce. Zero for most grammars; nonzero is the number to read
/// before blaming a stopped parse on the parser.
export fn jnt_parser_blind(p: *const bank.Parser) u32 {
    return bank.parserBlind(p);
}

// ── the parse ────────────────────────────────────────────────────────────────

/// Parse `text[0..len]` and write the tree to `*out`. A tree comes back on
/// every 0 return, accepted or not - a partial tree plus the reason is
/// strictly more useful than an error with no prefix - and `jnt_tree_stop`
/// says which this is. The tree borrows the parser; `text` may be freed the
/// moment this returns.
export fn jnt_parse(p: ?*bank.Parser, text: ?[*]const u8, len: usize, out: ?**bank.Tree) c_int {
    return @intFromEnum(bank.parse(p, text, len, out));
}

/// Release a tree and every render lent from it.
export fn jnt_tree_free(t: *bank.Tree) void {
    bank.treeFree(t);
}

/// How the parse ended: JNT_ACCEPTED, JNT_STRAY, JNT_UNEXPECTED, or
/// JNT_TRUNCATED.
export fn jnt_tree_stop(t: *const bank.Tree) c_int {
    return @intFromEnum(bank.stopKind(t));
}

/// The byte the stop names, for JNT_STRAY and JNT_UNEXPECTED; 0 otherwise.
export fn jnt_tree_stop_at(t: *const bank.Tree) u32 {
    return bank.stopAt(t);
}

/// The terminal an JNT_UNEXPECTED stop refused, as a borrowed pointer +
/// length; NULL for the other three stops.
export fn jnt_tree_stop_word(t: *const bank.Tree, len: ?*usize) ?[*]const u8 {
    const word = bank.stopWord(t) orelse return null;
    if (len) |l| l.* = word.len;
    return word.ptr;
}

/// How many times the parse deleted its way past a refusal, and how many
/// bytes those deletions walked over. Zero mends is a parse that reached its
/// stop and ended there; more is a parse that kept reading past it.
export fn jnt_tree_mends(t: *const bank.Tree) u32 {
    return t.q.mends;
}

export fn jnt_tree_skipped(t: *const bank.Tree) u32 {
    return t.q.skipped;
}

/// How many terminals the parse supplied that the author did not write.
export fn jnt_tree_supplied(t: *const bank.Tree) u32 {
    return t.q.supplied;
}

/// Whether the arena is a tree at all - every node reached once, children in
/// order and inside their parents. 1 sound, 0 not, JNT_NOMEM when the walk
/// could not be afforded. Walked on the first ask and kept, so asking twice
/// costs once and never asking costs nothing.
export fn jnt_tree_sound(t: *bank.Tree) c_int {
    return bank.treeSound(t);
}

/// The whole forest as an s-expression, one root per line, in tree-sitter's
/// own spelling. `all` nonzero keeps the anonymous nodes. Borrowed from the
/// tree, rendered once and cached, NUL-terminated; `*len` receives the length
/// when `len` is non-NULL. NULL only on out of memory.
export fn jnt_tree_sexp(t: *bank.Tree, all: c_int, len: ?*usize) ?[*:0]const u8 {
    return bank.sexp(t, all != 0, len);
}

// ── the nodes ────────────────────────────────────────────────────────────────
// A node is a u32 ref into the tree it came from; JNT_NONE is the answer
// that is not a node. Every accessor bounds-checks, so a stale or invented
// ref reads as absence rather than as memory.

/// The nodes standing at the top when the parse stopped: 1 for a whole
/// parse, a forest for one that stopped early.
export fn jnt_tree_roots(t: *const bank.Tree) u32 {
    return bank.rootCount(t);
}

/// Root `i`, or JNT_NONE past the end.
export fn jnt_tree_root(t: *const bank.Tree, i: u32) u32 {
    return bank.rootAt(t, i);
}

/// The node's name in the grammar's own spelling, borrowed pointer + length;
/// NULL for a ref that is not a node.
export fn jnt_node_name(t: *const bank.Tree, ref: u32, len: ?*usize) ?[*]const u8 {
    const name = bank.nodeName(t, ref) orelse return null;
    if (len) |l| l.* = name.len;
    return name.ptr;
}

/// Whether a query could match this node by name: 1 named, 0 for a node
/// spelled as itself (`"+"`) or a ref that is not a node.
export fn jnt_node_named(t: *const bank.Tree, ref: u32) c_int {
    return @intFromBool(bank.nodeNamed(t, ref));
}

/// The byte span this node covers, `[start, end)`.
export fn jnt_node_start(t: *const bank.Tree, ref: u32) u32 {
    return bank.nodeStart(t, ref);
}

export fn jnt_node_end(t: *const bank.Tree, ref: u32) u32 {
    return bank.nodeEnd(t, ref);
}

/// How many children this node holds - all of them, anonymous included,
/// which is the tree a query actually walks.
export fn jnt_node_kids(t: *const bank.Tree, ref: u32) u32 {
    return bank.nodeKids(t, ref);
}

/// Child `i` of `ref`, or JNT_NONE past the end.
export fn jnt_node_kid(t: *const bank.Tree, ref: u32, i: u32) u32 {
    return bank.nodeKid(t, ref, i);
}

/// The field name this node is filed under in its parent, borrowed pointer +
/// length; NULL when the grammar filed it under nothing.
export fn jnt_node_field(t: *const bank.Tree, ref: u32, len: ?*usize) ?[*]const u8 {
    const f = bank.nodeField(t, ref) orelse return null;
    if (len) |l| l.* = f.len;
    return f.ptr;
}

// ── the neighbourhood ────────────────────────────────────────────────────────
// No cursor handle, deliberately: a node here is a u32 index and its parent is
// a field read, so a cursor would hold the integers the host already has. See
// `bank.zig`.

/// Whoever holds this node; JNT_NONE for a root, and for a ref that is not a
/// node. The top of the tree is a run rather than a node, so the roots of a
/// parse that stopped early are siblings of each other and children of nothing.
export fn jnt_node_parent(t: *const bank.Tree, ref: u32) u32 {
    return bank.nodeParent(t, ref);
}

/// The neighbours in the run holding this node, anonymous ones included.
export fn jnt_node_next(t: *const bank.Tree, ref: u32) u32 {
    return bank.nodeNext(t, ref);
}

export fn jnt_node_prev(t: *const bank.Tree, ref: u32) u32 {
    return bank.nodePrev(t, ref);
}

/// The neighbours a query could match by name. A comment is one of them.
export fn jnt_node_next_named(t: *const bank.Tree, ref: u32) u32 {
    return bank.nodeNextNamed(t, ref);
}

export fn jnt_node_prev_named(t: *const bank.Tree, ref: u32) u32 {
    return bank.nodePrevNamed(t, ref);
}

/// The child this node files under `field[0..len]`, or JNT_NONE. `len` 0 with
/// a NUL-terminated `field` is not accepted - pass the length, as everywhere
/// else a string crosses in this direction.
export fn jnt_node_by_field(t: *const bank.Tree, ref: u32, field: ?[*]const u8, len: usize) u32 {
    const f = field orelse return bank.none;
    return bank.nodeByField(t, ref, f[0..len]);
}

/// Parent hops to a root, so every root is 0.
export fn jnt_node_depth(t: *const bank.Tree, ref: u32) u32 {
    return bank.nodeDepth(t, ref);
}

/// The deepest node covering [from, to), or JNT_NONE when no root does. The
/// viewport question, answered without a walk from the top.
export fn jnt_node_covering(t: *const bank.Tree, from: u32, to: u32) u32 {
    return bank.nodeCovering(t, from, to);
}

/// Nodes under this one, counting it; 0 for a non-node and 0 when the walk
/// could not be afforded.
export fn jnt_node_spread(t: *const bank.Tree, ref: u32) u32 {
    return bank.nodeSpread(t, ref);
}

// ── the weave: one file, held open ───────────────────────────────────────────

/// Hold a file open on this parser. The weave borrows the parser exactly as a
/// tree does; free weaves before the parser they came from.
export fn jnt_weave_new(p: ?*bank.Parser, out: ?**loom.Held) c_int {
    return @intFromEnum(loom.weaveNew(p, out));
}

export fn jnt_weave_free(h: *loom.Held) void {
    loom.weaveFree(h);
}

/// Read `text[0..len]` in cold. Calling it a second time reads a second file:
/// everything the weave was holding about the first is stood down.
export fn jnt_weave_warp(h: ?*loom.Held, text: ?[*]const u8, len: usize) c_int {
    return @intFromEnum(loom.weaveWarp(h, text, len));
}

/// Replace [from, to) with `insert[0..len]`. The offsets address the file as
/// it stands, so a run of these is a session and not a set of patches.
export fn jnt_weave_amend(h: ?*loom.Held, from: u32, to: u32, insert: ?[*]const u8, len: usize) c_int {
    return @intFromEnum(loom.weaveAmend(h, from, to, insert, len));
}

/// The tree as the file stands: BORROWED from the weave, stable across edits,
/// and not to be freed. NULL until something has been read in. Node refs taken
/// before an edit do not survive it; this handle does.
export fn jnt_weave_tree(h: *loom.Held) ?*bank.Tree {
    return loom.weaveTree(h);
}

/// How many bytes the file holds, which is what the next amend is checked
/// against.
export fn jnt_weave_len(h: *const loom.Held) usize {
    return loom.weaveLen(h);
}

/// How far the re-mint window widens: JNT_POLICY_PROVE (the default),
/// JNT_POLICY_SNAP, or JNT_POLICY_WHOLE. A cost decision, never a correctness
/// one. Takes effect from the next amend.
export fn jnt_weave_policy(h: ?*loom.Held, policy: c_int) c_int {
    return @intFromEnum(loom.weavePolicy(h, policy));
}

/// What the last warp or amend cost, written into `*out`.
export fn jnt_weave_cost(h: ?*const loom.Held, out: ?*loom.Cost) c_int {
    return @intFromEnum(loom.weaveCost(h, out));
}

test {
    // The shims are one-liners over tested bodies; what a test here can still
    // catch is a signature that stopped compiling as C-callable.
    std.testing.refAllDecls(@This());
    _ = bank;
    _ = loom;
}
