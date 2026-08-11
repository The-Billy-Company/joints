//! The edit door: a file held open, and what one keystroke costs.
//!
//! `jnt_parse` answers "what is this file". This answers "what is it now, given
//! that it was that a moment ago", which is the question an editor asks a
//! thousand times an hour and the only one an incremental parser exists for.
//! Until this file existed the whole weave was reachable from the CLI alone, so
//! an embedder's only way to follow a keystroke was to re-parse the file - the
//! exact cost the package was built to avoid.
//!
//! **The handle is the file, not the parse.** `jnt_weave_tree` hands back a
//! borrowed `jnt_tree *` that the weave owns and *refreshes in place*: the
//! pointer stays valid and stays correct across every amend, and everything
//! reachable through it - names, spans, children, the neighbourhood - moves to
//! the new text underneath it. What does not survive an amend is a `u32` node
//! ref taken before it, because the arena those index into is rebuilt. Refs are
//! per parse; the handle is per file. tree-sitter draws this line in the same
//! place and pays for it with an owned tree per edit.
//!
//! **A weave carries its own scanner, and that is not a duplicate.** The
//! scanner holds the ruling - the file's line structure - and the ruling is a
//! fact about one file's bytes. Sharing the parser's would leave a
//! `jnt_parse` on that parser reading through a ruling describing some other
//! document. It costs one scanner compile per file opened, paid once, against a
//! wrong answer per parse.
//!
//! Lifetimes extend the same chain the header states: a weave borrows its
//! parser, which borrows its bank. Free weaves, then parsers, then the bank.

const std = @import("std");
const joints = @import("joints");

const bank = @import("bank.zig");

const scanner = joints.kernel.lex.scanner;
const weave = joints.kernel.weave;

const Status = bank.Status;
const gpa = std.heap.c_allocator;

/// How far the re-mint window widens when an edit destabilises the state a
/// leaf begins in. A cost decision and never a correctness one - all three
/// derive the same leaves and differ only in how many they derive again - so a
/// host may pick one on measurement alone.
pub const Policy = enum(c_int) {
    /// Stop only when the algebra says so: when the new prefix's product
    /// composes with the old suffix's. The conservative one, and the default.
    prove = 0,
    /// Stop at the first leaf standing where an old leaf stood, in the state
    /// it began in. One integer compare per candidate - tree-sitter's test.
    snap = 1,
    /// Re-derive everything past the edit. What an integration that never
    /// asked the question does by accident, kept as the baseline to beat.
    whole = 2,
};

/// What the last edit cost, in the units the incremental claim is stated in.
///
/// One struct rather than eleven getters because these are read together or
/// not at all: a status line wants the whole row, and eleven calls to collect
/// eleven adjacent `u32`s is eleven calls. `extern` fixes the layout so a
/// binding can declare it once.
pub const Cost = extern struct {
    /// Leaves the spine holds over the whole file, and its height - what a
    /// one-for-one splice costs in compositions.
    leaves: u32,
    height: u32,
    /// Where the re-mint window opened. Not a policy: the first leaf whose
    /// bytes or element moved.
    at: u32,
    /// Leaves re-derived, and leaves whose old elements stood untouched.
    minted: u32,
    kept: u32,
    /// Subtrees lifted whole out of the previous tree, the bytes under them,
    /// and the nodes copied to carry them over - the flat arena's tax.
    lifts: u32,
    skipped: u32,
    carried: u32,
    /// Nodes in the tree that came out.
    nodes: u32,
    /// Stream entries this run moved over: tokens lexed, plus one per subtree
    /// lifted instead of read. The half of the cost that reuse is for.
    read: u32,
    /// The byte the parse began at - where the kept stack was standing, or 0
    /// for one that started on the ground. This is the number that decides
    /// whether an edit at the bottom of a file costs the top of it.
    stood: u32,
};

/// A file held open. Self-referential by construction - the loom points at the
/// scanner beside it and the weave at the loom - which is why it is created on
/// the heap and never moved, the same shape `Parser` already keeps.
pub const Held = struct {
    parser: *bank.Parser,
    sc: scanner.Scanner,
    loom: weave.Loom,
    w: weave.Weave,
    /// The borrowed view a host reads through, refreshed on every change.
    face: bank.Tree,
    /// Whether any text has been read in yet. `jnt_weave_tree` is absence
    /// until it has, rather than a tree over nothing.
    dressed: bool = false,
};

/// `jnt_weave_new`. Compiles this grammar's scanner a second time, on purpose:
/// see the header.
pub fn weaveNew(parser: ?*bank.Parser, out: ?**Held) Status {
    bank.clear();
    const slot = out orelse return bank.fail(.invalid, "jnt_weave_new: out is NULL", .{});
    const p = parser orelse return bank.fail(.invalid, "jnt_weave_new: parser is NULL", .{});
    const gr = p.grammar();

    const h = gpa.create(Held) catch return bank.fail(.out_of_memory, "out of memory", .{});
    h.parser = p;
    h.dressed = false;
    h.sc = (scanner.Scanner.compile(gpa, gr) catch |err| {
        gpa.destroy(h);
        return bank.fail(.grammar, "cannot compile {s}'s scanner: {s}", .{ gr.name, @errorName(err) });
    }) orelse {
        gpa.destroy(h);
        return bank.fail(.grammar, "{s} has no lexable terminal at all", .{gr.name});
    };
    h.loom = weave.Loom.init(gpa, gr, p.collection(), p.tables(), &h.sc);
    h.w = weave.Weave.init(gpa, &h.loom) catch {
        h.loom.deinit();
        h.sc.deinit();
        gpa.destroy(h);
        return bank.fail(.out_of_memory, "out of memory", .{});
    };
    h.face = .{ .parser = p, .q = undefined, .own = false };
    slot.* = h;
    return .ok;
}

pub fn weaveFree(h: *Held) void {
    h.face.stale();
    h.w.deinit();
    h.loom.deinit();
    h.sc.deinit();
    gpa.destroy(h);
}

/// `jnt_weave_warp`. Read a file in cold, which is what every later edit is
/// measured against.
///
/// Calling it twice is a second file - or the same one reloaded from disk -
/// and it is answered by standing a fresh weave up on the same loom rather
/// than by re-dressing the one standing. A weave carries the previous parse's
/// leaves, marks, stances and stack stretches precisely so the next edit can
/// use them, and every one of those describes a document that is now gone.
pub fn weaveWarp(held: ?*Held, text: ?[*]const u8, len: usize) Status {
    bank.clear();
    const h = held orelse return bank.fail(.invalid, "jnt_weave_warp: weave is NULL", .{});
    const bytes: []const u8 = if (len == 0) &.{} else b: {
        const t = text orelse return bank.fail(.invalid, "jnt_weave_warp: text is NULL with len {d}", .{len});
        break :b t[0..len];
    };
    if (h.dressed) {
        const policy = h.w.policy;
        h.face.stale();
        h.dressed = false;
        h.w.deinit();
        h.w = weave.Weave.init(gpa, &h.loom) catch {
            return bank.fail(.out_of_memory, "out of memory", .{});
        };
        h.w.policy = policy;
    }
    h.w.warp(bytes) catch |err| {
        return bank.fail(.out_of_memory, "cannot read the file in: {s}", .{@errorName(err)});
    };
    settle(h);
    return .ok;
}

/// `jnt_weave_amend`. Replace `[from, to)` with `insert[0..len]` and maintain
/// both halves over the result.
///
/// The offsets address the file **as it stands**, so a run of these is a
/// session and not a set of patches: the second one's offsets are the first
/// one's result. An empty insert is a deletion and `from == to` is an
/// insertion. The kernel asserts the span; here it is checked and refused,
/// because a host that miscounts must get a status and not a stopped process.
pub fn weaveAmend(held: ?*Held, from: u32, to: u32, insert: ?[*]const u8, len: usize) Status {
    bank.clear();
    const h = held orelse return bank.fail(.invalid, "jnt_weave_amend: weave is NULL", .{});
    if (!h.dressed) return bank.fail(.invalid, "jnt_weave_amend: nothing has been read in yet", .{});
    const wide = h.w.text.items.len;
    if (from > to or to > wide) {
        return bank.fail(.invalid, "jnt_weave_amend: {d}..{d} does not address a span of {d} bytes", .{ from, to, wide });
    }
    const put: []const u8 = if (len == 0) &.{} else b: {
        const s = insert orelse return bank.fail(.invalid, "jnt_weave_amend: insert is NULL with len {d}", .{len});
        break :b s[0..len];
    };
    if (put.len > std.math.maxInt(u32)) {
        return bank.fail(.invalid, "jnt_weave_amend: insert of {d} bytes is past the addressable file", .{put.len});
    }

    h.face.stale();
    h.w.amend(.{ .from = from, .to = to, .insert = @intCast(put.len) }, put) catch |err| {
        // The tree the host was reading is gone either way, so the handle is
        // stood down rather than left pointing at the parse before the edit.
        h.dressed = false;
        return bank.fail(.out_of_memory, "cannot amend: {s}", .{@errorName(err)});
    };
    settle(h);
    return .ok;
}

/// Point the borrowed handle at the parse that just came out. The quire is
/// copied by value - it is a struct of slices into the weave's own arena - so
/// the handle carries no ownership and the weave stays the only owner.
fn settle(h: *Held) void {
    h.face.stale();
    h.face.q = h.w.tree.?;
    h.dressed = true;
}

/// `jnt_weave_tree`. Borrowed, stable across edits, and never freed by the
/// host. Absence until something has been read in.
pub fn weaveTree(h: *Held) ?*bank.Tree {
    return if (h.dressed) &h.face else null;
}

/// `jnt_weave_len`: how many bytes the file holds as it stands, which is what
/// the next amend's offsets are checked against.
pub fn weaveLen(h: *const Held) usize {
    return h.w.text.items.len;
}

/// `jnt_weave_policy`. Takes effect from the next amend.
pub fn weavePolicy(held: ?*Held, policy: c_int) Status {
    bank.clear();
    const h = held orelse return bank.fail(.invalid, "jnt_weave_policy: weave is NULL", .{});
    h.w.policy = switch (policy) {
        @intFromEnum(Policy.prove) => .prove,
        @intFromEnum(Policy.snap) => .snap,
        @intFromEnum(Policy.whole) => .whole,
        else => return bank.fail(.invalid, "jnt_weave_policy: {d} is not a policy", .{policy}),
    };
    return .ok;
}

/// `jnt_weave_cost`: what the last warp or amend cost.
pub fn weaveCost(held: ?*const Held, out: ?*Cost) Status {
    bank.clear();
    const h = held orelse return bank.fail(.invalid, "jnt_weave_cost: weave is NULL", .{});
    const slot = out orelse return bank.fail(.invalid, "jnt_weave_cost: out is NULL", .{});
    const c = h.w.cost;
    slot.* = .{
        .leaves = c.leaves,
        .height = c.height,
        .at = c.at,
        .minted = c.minted,
        .kept = c.kept,
        .lifts = c.lifts,
        .skipped = c.skipped,
        .carried = c.carried,
        .nodes = c.nodes,
        .read = c.read,
        .stood = c.stood,
    };
    return .ok;
}

// -------------------------------------------------------- the wiring, asserted

const testing = std.testing;

/// One json document held open, with the parser and bank under it. Returned
/// rather than built inline because every test below wants the same three
/// handles in the same lifetime order.
const Open = struct {
    bank: *bank.Bank,
    parser: *bank.Parser,
    held: *Held,

    fn of() !Open {
        const bk = try bank.testBank();
        var p: *bank.Parser = undefined;
        try testing.expectEqual(Status.ok, bank.parserNew(bk, null, &p));
        var h: *Held = undefined;
        try testing.expectEqual(Status.ok, weaveNew(p, &h));
        return .{ .bank = bk, .parser = p, .held = h };
    }

    fn close(o: Open) void {
        weaveFree(o.held);
        bank.parserFree(o.parser);
        bank.close(o.bank);
    }

    fn warp(o: Open, text: []const u8) !void {
        try testing.expectEqual(Status.ok, weaveWarp(o.held, text.ptr, text.len));
    }

    fn amend(o: Open, from: u32, to: u32, put: []const u8) !void {
        try testing.expectEqual(Status.ok, weaveAmend(o.held, from, to, put.ptr, put.len));
    }

    /// The tree as the CLI would print it, named nodes only.
    fn shape(o: Open) []const u8 {
        var n: usize = 0;
        const s = bank.sexp(weaveTree(o.held).?, false, &n).?;
        return s[0..n];
    }
};

test "a file held open re-parses across edits, and the handle survives them" {
    const o = try Open.of();
    defer o.close();
    try o.warp("{\"a\": 1}");

    const face = weaveTree(o.held).?;
    try testing.expectEqualStrings("(document (object (pair key: (string (string_content)) value: (number))))\n", o.shape());

    // `1` becomes `true`, which changes the node's kind and not just its span.
    try o.amend(6, 7, "true");
    try testing.expectEqualStrings("{\"a\": true}", o.held.w.text.items);
    try testing.expectEqual(@as(usize, 11), weaveLen(o.held));
    // The same pointer, answering about the new text.
    try testing.expectEqual(face, weaveTree(o.held).?);
    try testing.expectEqualStrings("(document (object (pair key: (string (string_content)) value: (true))))\n", o.shape());

    // And a deletion, which is an amend with nothing to put.
    try o.amend(1, 10, "");
    try testing.expectEqualStrings("{}", o.held.w.text.items);
    try testing.expectEqualStrings("(document (object))\n", o.shape());
}

test "an edit near the end does not re-read the top of the file" {
    const o = try Open.of();
    defer o.close();
    // Wide enough for the resume to have somewhere to stand.
    var doc: std.ArrayList(u8) = .empty;
    defer doc.deinit(testing.allocator);
    try doc.appendSlice(testing.allocator, "[");
    for (0..400) |i| {
        if (i != 0) try doc.appendSlice(testing.allocator, ", ");
        try doc.appendSlice(testing.allocator, "1");
    }
    try doc.appendSlice(testing.allocator, "]");
    try o.warp(doc.items);

    var cold: Cost = undefined;
    try testing.expectEqual(Status.ok, weaveCost(o.held, &cold));
    try testing.expect(cold.leaves > 1);
    try testing.expectEqual(@as(u32, 0), cold.stood);

    // A digit near the end of the file.
    const at: u32 = @intCast(doc.items.len - 2);
    try o.amend(at, at + 1, "2");
    var hot: Cost = undefined;
    try testing.expectEqual(Status.ok, weaveCost(o.held, &hot));
    // The claim, in the units it is stated in: the parse stood somewhere in
    // the middle of the file, and re-derived a fraction of its leaves.
    // The claim, in the units it is stated in. The parse began deep inside the
    // file rather than at the top of it; every leaf the previous parse derived
    // stood, because a digit swapped for a digit is the same token from the
    // same state and so the same element; and the run moved over a small
    // fraction of the stream - 33 entries of 801 when this was written, and the
    // bound below is loose enough that only a real regression trips it.
    try testing.expect(hot.stood > 0);
    try testing.expectEqual(cold.leaves, hot.kept);
    try testing.expectEqual(@as(u32, 0), hot.minted);
    try testing.expect(hot.read * 10 < cold.read);
}

test "the tree a weave lends is the weave's: freeing it is a no-op" {
    const o = try Open.of();
    defer o.close();
    try o.warp("[1]");
    const face = weaveTree(o.held).?;
    // A host that frees what it was lent must not take the weave down with it,
    // and must not be answered with a use-after-free on the next question.
    bank.treeFree(face);
    try testing.expectEqual(face, weaveTree(o.held).?);
    try testing.expectEqualStrings("document", bank.nodeName(face, bank.rootAt(face, 0)).?);
}

test "warping twice reads a second file rather than layering it on the first" {
    const o = try Open.of();
    defer o.close();
    try o.warp("[1, 2, 3]");
    try o.warp("{}");
    try testing.expectEqual(@as(usize, 2), weaveLen(o.held));
    try testing.expectEqualStrings("(document (object))\n", o.shape());
    // The policy set before a re-warp is a property of the host's session, not
    // of the document, so it survives one.
    try testing.expectEqual(Status.ok, weavePolicy(o.held, @intFromEnum(Policy.snap)));
    try o.warp("[1]");
    try testing.expectEqual(weave.Policy.snap, o.held.w.policy);
}

test "an amend outside the file is refused rather than asserted" {
    const o = try Open.of();
    defer o.close();
    try o.warp("[1]");
    try testing.expectEqual(Status.invalid, weaveAmend(o.held, 2, 1, "", 0));
    try testing.expectEqual(Status.invalid, weaveAmend(o.held, 0, 99, "", 0));
    try testing.expectEqual(Status.invalid, weaveAmend(o.held, 0, 1, null, 4));
    try testing.expectEqual(Status.invalid, weavePolicy(o.held, 7));
    // Refused, and the file is exactly as it was.
    try testing.expectEqual(@as(usize, 3), weaveLen(o.held));
    try testing.expectEqualStrings("(document (array (number)))\n", o.shape());
}

test "nothing read in yet is absence, not a tree over nothing" {
    const o = try Open.of();
    defer o.close();
    try testing.expect(weaveTree(o.held) == null);
    try testing.expectEqual(Status.invalid, weaveAmend(o.held, 0, 0, "x", 1));
    try testing.expectEqual(Status.invalid, weaveNew(null, null));
}
