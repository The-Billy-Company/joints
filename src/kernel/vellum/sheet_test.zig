//! The settled tree against the live one, node by node.
//!
//! There is exactly one thing this file has to prove and it is not subtle: for
//! every node of every tree, every question the quire answers and the sheet
//! answers has to get the same answer. A succinct structure that is right about
//! 99.9% of a file is not 99.9% correct, it is broken - the whole point of it
//! is that a walk can trust arithmetic instead of pointers, and a walk that has
//! to check is slower than the pointers were.
//!
//! So the oracle is the quire itself, over real files parsed by the real
//! grammars, and the comparison is total rather than sampled. The test's own
//! DFS builds the expected parenthesis word and the expected ref-to-spot map
//! independently of `settle`, which is what keeps this from being a mirror of
//! the code under test: if `settle` emitted the word in the wrong order, the
//! word comparison fails before a single navigation op is asked.
//!
//! The adverse shapes at the bottom are the ones a corpus does not contain and
//! the ones that break a different assumption each: one node (every op has a
//! null answer), a deep left spine (the recursive walk overflows), a wide flat
//! parent (`nextSibling` is the only affordable way across), the last node in
//! DFS order (the one whose `nextSibling` runs off the end of the word).

const std = @import("std");
const t = std.testing;
const press = @import("../../press/press.zig");
const lex = @import("../lex/scanner.zig");
const quire = @import("../quire/quire.zig");
const vellum = @import("vellum.zig");
const word = @import("word.zig");

const json_src = @embedFile("json_grammar");

/// A grammar, its tables, a scanner, and the gather over them. Same shape the
/// quire's own tests use, for the same reason: a hand-built symbol table cannot
/// tell you whether the settled tree matches the one a parse really makes.
const Fixture = struct {
    gpa: std.mem.Allocator,
    gr: press.Grammar,
    built: press.Result,
    scanner: lex.Scanner,
    gather: quire.Gather,

    fn init(gpa: std.mem.Allocator, source: []const u8) !*Fixture {
        const f = try gpa.create(Fixture);
        errdefer gpa.destroy(f);
        f.gpa = gpa;
        f.gr = try press.treeSitter(gpa, source);
        errdefer f.gr.deinit();
        f.built = try press.tables(gpa, &f.gr);
        errdefer f.built.deinit();
        f.scanner = (try lex.Scanner.compile(gpa, &f.gr)) orelse return error.NothingLexable;
        errdefer f.scanner.deinit();
        f.gather = try quire.Gather.init(gpa, &f.gr, &f.built.collection, &f.built.tables, &f.scanner);
        return f;
    }

    fn deinit(f: *Fixture) void {
        const gpa = f.gpa;
        f.gather.deinit();
        f.scanner.deinit();
        f.built.deinit();
        f.gr.deinit();
        gpa.destroy(f);
    }
};

/// A file off the shelf, or `error.FileNotFound` when the tree is not
/// underfoot. Fixtures, not build inputs, so a run that cannot see them skips.
fn shelf(gpa: std.mem.Allocator, path: []const u8) ![]u8 {
    var threaded = std.Io.Threaded.init(gpa, .{});
    defer threaded.deinit();
    return std.Io.Dir.cwd().readFileAlloc(threaded.io(), path, gpa, .limited(64 << 20));
}

/// The quire walked the test's own way: preorder refs, the word that walk
/// writes, and the map back. Everything the comparison needs, derived without
/// asking `settle` anything.
const Walk = struct {
    gpa: std.mem.Allocator,
    /// Preorder index to the quire's ref.
    order: []quire.Ref,
    /// Preorder index to the bit position of that node's `(`.
    spot: []vellum.Spot,
    /// The quire's ref to its preorder index, or `none`.
    rank: []u32,
    /// The parenthesis word this walk writes.
    letters: []u8,

    fn of(gpa: std.mem.Allocator, q: *const quire.Quire) !Walk {
        var order: std.ArrayList(quire.Ref) = .empty;
        errdefer order.deinit(gpa);
        var spot: std.ArrayList(vellum.Spot) = .empty;
        errdefer spot.deinit(gpa);
        var letters: std.ArrayList(u8) = .empty;
        errdefer letters.deinit(gpa);
        const rank = try gpa.alloc(u32, q.nodes.len);
        errdefer gpa.free(rank);
        @memset(rank, quire.none);

        // Explicit stack, because the corpus reaches depths a recursive walk
        // does not survive - and the deep case below is worse on purpose.
        const Frame = struct { ref: quire.Ref, kid: u32 };
        var stack: std.ArrayList(Frame) = .empty;
        defer stack.deinit(gpa);
        var next_root: usize = 0;
        while (true) {
            if (stack.items.len == 0) {
                if (next_root == q.roots.len) break;
                const r = q.roots[next_root];
                next_root += 1;
                rank[r] = @intCast(order.items.len);
                try spot.append(gpa, @intCast(letters.items.len));
                try order.append(gpa, r);
                try letters.append(gpa, '(');
                try stack.append(gpa, .{ .ref = r, .kid = 0 });
                continue;
            }
            const top = stack.items.len - 1;
            const held = stack.items[top];
            const kids = q.children(held.ref);
            if (held.kid == kids.len) {
                try letters.append(gpa, ')');
                _ = stack.pop();
                continue;
            }
            stack.items[top].kid += 1;
            const c = kids[held.kid];
            rank[c] = @intCast(order.items.len);
            try spot.append(gpa, @intCast(letters.items.len));
            try order.append(gpa, c);
            try letters.append(gpa, '(');
            try stack.append(gpa, .{ .ref = c, .kid = 0 });
        }
        return .{
            .gpa = gpa,
            .order = try order.toOwnedSlice(gpa),
            .spot = try spot.toOwnedSlice(gpa),
            .rank = rank,
            .letters = try letters.toOwnedSlice(gpa),
        };
    }

    fn deinit(w: *Walk) void {
        w.gpa.free(w.order);
        w.gpa.free(w.spot);
        w.gpa.free(w.rank);
        w.gpa.free(w.letters);
        w.* = undefined;
    }

    /// The quire's own answer for a ref, as a spot. `none` in, null out.
    fn spotFor(w: *const Walk, ref: quire.Ref) ?vellum.Spot {
        return if (ref == quire.none) null else w.spot[w.rank[ref]];
    }

    /// The sheet's answer for a preorder index, which is what the sweep holds.
    fn spotAt(w: *const Walk, i: usize) vellum.Spot {
        return w.spot[i];
    }
};

/// Depth by the only definition that needs no structure: hops to a root.
fn depthOf(q: *const quire.Quire, ref: quire.Ref) u32 {
    var d: u32 = 0;
    var at = q.nodes[ref].parent;
    while (at != quire.none) : (at = q.nodes[at].parent) d += 1;
    return d;
}

/// Subtree size by counting, which is what the quire costs and the sheet does
/// not. Iterative: the deep case below is 2000 frames of recursion otherwise.
fn sizeOf(gpa: std.mem.Allocator, q: *const quire.Quire, ref: quire.Ref) !u32 {
    var stack: std.ArrayList(quire.Ref) = .empty;
    defer stack.deinit(gpa);
    try stack.append(gpa, ref);
    var n: u32 = 0;
    while (stack.pop()) |at| {
        n += 1;
        for (q.children(at)) |c| try stack.append(gpa, c);
    }
    return n;
}

/// The sibling after `ref` under its parent, or under the root list.
fn afterOf(q: *const quire.Quire, ref: quire.Ref) ?quire.Ref {
    const p = q.nodes[ref].parent;
    const among = if (p == quire.none) q.roots else q.children(p);
    for (among, 0..) |c, i| if (c == ref) return if (i + 1 < among.len) among[i + 1] else null;
    return null;
}

fn beforeOf(q: *const quire.Quire, ref: quire.Ref) ?quire.Ref {
    const p = q.nodes[ref].parent;
    const among = if (p == quire.none) q.roots else q.children(p);
    for (among, 0..) |c, i| if (c == ref) return if (i > 0) among[i - 1] else null;
    return null;
}

/// The deepest common ancestor by climbing two parent chains, which is the
/// answer a pointer tree has to compute. The sheet's is a range-min query.
fn ancestorOf(q: *const quire.Quire, a: quire.Ref, b: quire.Ref) ?quire.Ref {
    var x = a;
    var y = b;
    var dx = depthOf(q, x);
    var dy = depthOf(q, y);
    while (dx > dy) : (dx -= 1) x = q.nodes[x].parent;
    while (dy > dx) : (dy -= 1) y = q.nodes[y].parent;
    while (x != y) {
        // Equal depth, so they run out of parents together: two different
        // roots of the same forest have no common ancestor at all.
        if (q.nodes[x].parent == quire.none) return null;
        x = q.nodes[x].parent;
        y = q.nodes[y].parent;
    }
    return x;
}

/// Every node, every op, against the quire. The whole point of the file.
fn confront(gpa: std.mem.Allocator, q: *const quire.Quire) !void {
    var w = try Walk.of(gpa, q);
    defer w.deinit();
    var s = try vellum.settle(gpa, q);
    defer s.deinit();

    // Before a single navigation op: the word itself. A settle that walked the
    // tree in a different order would still answer every op self-consistently
    // and be answering about a different tree.
    try t.expectEqual(w.order.len, s.count());
    try t.expectEqual(w.letters.len, s.shape.bitLen());
    for (w.letters, 0..) |c, k| try t.expectEqual(c == '(', s.shape.isOpen(k));

    for (w.order, 0..) |ref, i| {
        const spot = w.spot[i];

        // The handle and its inverse.
        try t.expectEqual(@as(u32, @intCast(i)), s.preorder(spot));
        try t.expectEqual(@as(?vellum.Spot, spot), s.spotOf(@intCast(i)));

        // The five the brief names.
        try t.expectEqual(w.spotFor(q.nodes[ref].parent), s.parent(spot));
        const kids = q.children(ref);
        try t.expectEqual(
            if (kids.len == 0) null else w.spotFor(kids[0]),
            s.firstChild(spot),
        );
        try t.expectEqual(
            if (afterOf(q, ref)) |n| w.spotFor(n) else null,
            s.nextSibling(spot),
        );
        try t.expectEqual(try sizeOf(gpa, q, ref), s.subtreeSize(spot));
        try t.expectEqual(depthOf(q, ref), s.depth(spot));

        // And the rest of the quire's surface, because an op that only most of
        // the API agrees with is the same bug arriving later.
        try t.expectEqual(
            if (kids.len == 0) null else w.spotFor(kids[kids.len - 1]),
            s.lastChild(spot),
        );
        try t.expectEqual(
            if (beforeOf(q, ref)) |n| w.spotFor(n) else null,
            s.prevSibling(spot),
        );
        try t.expectEqualStrings(q.name(ref), s.name(spot));
        try t.expectEqual(q.isNamed(ref), s.isNamed(spot));
        try t.expectEqual(q.isExtra(ref), s.isExtra(spot));
        try t.expectEqual(q.nodes[ref].start, s.start(spot));
        try t.expectEqual(q.nodes[ref].end(), s.end(spot));
        if (q.field(ref)) |f| try t.expectEqualStrings(f, s.field(spot).?) else try t.expect(s.field(spot) == null);

        // The iterator against the flat list, in order.
        var it = s.kids(spot);
        for (kids) |c| try t.expectEqual(w.spotFor(c), it.next());
        try t.expectEqual(@as(?vellum.Spot, null), it.next());
    }

    // Ancestry over a sample of pairs rather than all of them, and only here:
    // it is `O(n²)` to be exhaustive and the two ops above already pin the
    // parent chain node by node, so what a pair adds is the range-min query.
    var prng = std.Random.DefaultPrng.init(0x0AC7_0BE0_0000_0001);
    const rng = prng.random();
    if (w.order.len > 1) for (0..@min(4000, 8 * w.order.len)) |_| {
        const ia = rng.uintLessThan(usize, w.order.len);
        const ib = rng.uintLessThan(usize, w.order.len);
        const want = if (ancestorOf(q, w.order[ia], w.order[ib])) |r| w.spotFor(r) else null;
        try t.expectEqual(want, s.lca(w.spotAt(ia), w.spotAt(ib)));
        try t.expectEqual(
            want != null and want.? == w.spotAt(ia),
            s.isAncestor(w.spotAt(ia), w.spotAt(ib)),
        );
    };
}

fn over(gpa: std.mem.Allocator, grammar: []const u8, bytes: []const u8) !void {
    const f = try Fixture.init(gpa, grammar);
    defer f.deinit();
    var q = try f.gather.run(bytes);
    defer q.deinit();
    try confront(gpa, &q);
}

test "vellum: the settled tree answers what the live tree answers, over json" {
    const gpa = t.allocator;
    const src = shelf(gpa, "research/joinery/corpus/ledger.json") catch |e| {
        if (e == error.FileNotFound) return error.SkipZigTest;
        return e;
    };
    defer gpa.free(src);
    try over(gpa, json_src, src);
}

test "vellum: the settled tree answers what the live tree answers, over five grammars" {
    // Different grammars make different trees - java is deep and narrow where
    // json is shallow and wide, and go's expression grammar nests where
    // python's block structure does not - so a navigation bug that only shows
    // on one shape is the bug this lane exists not to ship. Whatever forest
    // each parse leaves is what gets settled, and a partial parse is the harder
    // case rather than the easier one: several roots, no single top.
    //
    // Fixtures rather than build inputs, so a tree without `upstream/` skips.
    const gpa = t.allocator;
    const cases = [_]struct { grammar: []const u8, file: []const u8 }{
        .{ .grammar = "upstream/grammars/java.json", .file = "research/joinery/corpus/Ledger.java" },
        .{ .grammar = "upstream/grammars/c.json", .file = "research/joinery/corpus/ledger.c" },
        .{ .grammar = "upstream/grammars/go.json", .file = "research/joinery/corpus/ledger.go" },
        .{ .grammar = "upstream/grammars/python.json", .file = "research/joinery/corpus/ledger.py" },
        .{ .grammar = "upstream/grammars/rust.json", .file = "research/joinery/corpus/ledger.rs" },
    };
    var ran: u32 = 0;
    for (cases) |c| {
        const grammar = shelf(gpa, c.grammar) catch |e| {
            if (e == error.FileNotFound) continue;
            return e;
        };
        defer gpa.free(grammar);
        const bytes = shelf(gpa, c.file) catch |e| {
            if (e == error.FileNotFound) continue;
            return e;
        };
        defer gpa.free(bytes);
        over(gpa, grammar, bytes) catch |e| {
            // A grammar this press cannot take yet is a fact about the press,
            // not about the settled tree, and it is another lane's. Anything
            // that got as far as a parse and then disagreed is mine.
            if (e == error.NothingLexable) continue;
            std.debug.print("\nvellum: {s} disagreed with the live tree\n", .{c.file});
            return e;
        };
        ran += 1;
    }
    if (ran == 0) return error.SkipZigTest;
}

test "vellum: the adverse shapes, against the live tree" {
    const gpa = t.allocator;
    const f = try Fixture.init(gpa, json_src);
    defer f.deinit();

    // Deep: json's only recursion is nesting, so a left spine is a stack of
    // open brackets. Deep enough that a recursive settle would not return.
    var deep: std.ArrayList(u8) = .empty;
    defer deep.deinit(gpa);
    for (0..2000) |_| try deep.append(gpa, '[');
    for (0..2000) |_| try deep.append(gpa, ']');

    // Wide: one parent, thousands of children, which is where the quire's
    // `nextSibling` costs a scan of the kid list and the sheet's does not.
    var wide: std.ArrayList(u8) = .empty;
    defer wide.deinit(gpa);
    try wide.append(gpa, '[');
    for (0..4000) |i| {
        if (i != 0) try wide.append(gpa, ',');
        try wide.append(gpa, '1');
    }
    try wide.append(gpa, ']');

    const shapes = [_][]const u8{
        // One node, and the ops that have no answer at all.
        "1",
        "true",
        // Two roots is a forest, which is what a partial parse leaves.
        "1 2",
        "[]",
        "[[]]",
        "{\"a\":1}",
        deep.items,
        wide.items,
    };
    for (shapes) |bytes| {
        var q = try f.gather.run(bytes);
        defer q.deinit();
        confront(gpa, &q) catch |e| {
            std.debug.print("\nvellum: adverse shape of {d} bytes disagreed\n", .{bytes.len});
            return e;
        };
    }
}

test "vellum: an empty sheet is a reachable state and answers null" {
    // Not reachable by parsing nothing - json's recovery supplies enough to
    // leave a node - so the empty forest is built directly. It is still a state
    // the type can be in, and `root` on it is the one query with no node to
    // return, which is exactly where an off-by-one lives.
    const gpa = t.allocator;
    const f = try Fixture.init(gpa, json_src);
    defer f.deinit();
    var empty: quire.Quire = .{
        .gpa = gpa,
        .gr = &f.gr,
        .nodes = &.{},
        .kids = &.{},
        .roots = &.{},
        .stop = .accepted,
    };
    var s = try vellum.settle(gpa, &empty);
    defer s.deinit();
    try t.expectEqual(@as(u32, 0), s.count());
    try t.expectEqual(@as(?vellum.Spot, null), s.root());
    try t.expectEqual(@as(usize, 0), s.shape.bitLen());
    try t.expectEqual(@as(usize, 0), s.shape.nodeCount());

    // And parsing nothing settles to whatever the parse really left, which the
    // sweep then holds to the live tree like any other file.
    var q = try f.gather.run("");
    defer q.deinit();
    try confront(gpa, &q);
}

test "vellum: the last node in DFS order runs off the end of the word cleanly" {
    // The one node whose `nextSibling` has nothing after it in the whole word,
    // as opposed to nothing after it under its parent. `confront` covers it in
    // the sweep; it is named here because it is the index-out-of-range this
    // structure has, and a sweep that happened to stop one node early would
    // pass without ever asking.
    const gpa = t.allocator;
    const f = try Fixture.init(gpa, json_src);
    defer f.deinit();
    var q = try f.gather.run("[1,[2,3]]");
    defer q.deinit();
    var s = try vellum.settle(gpa, &q);
    defer s.deinit();
    const last = s.spotOf(s.count() - 1).?;
    try t.expectEqual(@as(?vellum.Spot, null), s.nextSibling(last));
    try t.expectEqual(@as(?vellum.Spot, null), s.firstChild(last));
    try t.expectEqual(@as(u32, 1), s.subtreeSize(last));
    try t.expect(s.parent(last) != null);
}

test "vellum: a settled sheet and a word off it are the same tree" {
    // The two halves against each other. `Word` is the sheet's shape on the
    // spine, so a round trip that lost a parenthesis would be a `Word` that
    // measures a different tree than the one it came from.
    const gpa = t.allocator;
    const f = try Fixture.init(gpa, json_src);
    defer f.deinit();
    var q = try f.gather.run("{\"a\":[1,2,{\"b\":null}],\"c\":true}");
    defer q.deinit();
    var s = try vellum.settle(gpa, &q);
    defer s.deinit();

    var w = try vellum.Word.of(gpa, &s);
    defer w.deinit();
    try w.verify();
    try t.expect(w.balanced());
    try t.expectEqual(s.count(), w.count() / 2);

    var again = try w.seal(gpa);
    defer again.deinit(gpa);
    try t.expectEqual(s.shape.bitLen(), again.bitLen());
    for (0..again.bitLen()) |k| try t.expectEqual(s.shape.isOpen(k), again.isOpen(k));

    // And the measure the spine holds is the word's, checked against a scan.
    var letters: std.ArrayList(u8) = .empty;
    defer letters.deinit(gpa);
    for (0..s.shape.bitLen()) |k| try letters.append(gpa, if (s.shape.isOpen(k)) '(' else ')');
    try t.expect(word.measure(letters.items).balanced());
}
