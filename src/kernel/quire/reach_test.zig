//! What a query can reach from a node, and whether it reaches the same thing
//! tree-sitter reaches.
//!
//! Five of the neighbourhood accessors already have an oracle in the tree -
//! `vellum/sheet_test.zig` walks a quire the slow obviously-correct way to
//! check the settled form's clever way, and that sweep now holds `parent`,
//! `nextSibling`, `prevSibling`, `depth` and `subtreeSize` to it node by node
//! over six grammars. This file is the other four, plus the two shapes a
//! corpus does not reliably contain.
//!
//! The oracles here are deliberately not the code under test spelled twice:
//!
//!   * The named walks are checked as a COMPOSITION of `nextSibling`, which the
//!     sweep next door already proved. First-named-after is then a claim about
//!     `isNamed` and nothing else.
//!   * `descendantForByteRange` is checked against its CHARACTERISATION rather
//!     than a second search - the answer covers the range, no child of it does,
//!     every ancestor of it does - and against an exhaustive max-depth sweep on
//!     the shapes small enough to afford one. A bisection checked by a linear
//!     scan of the same list would agree with itself about an off-by-one.
//!   * The two tables are copied off the pinned tree-sitter CLI's own output
//!     (0.26.11, `tree-sitter parse` on the fixture in the doc comment), not
//!     off ours. That is the whole point of the extras question: our tree and
//!     the incumbent's agree node for node on where a comment lands, so what
//!     remains is whether a *walk* over it skips the comment, and the answer
//!     has to come from the incumbent.
//!
//! The forest is hand-built. A json parse that stops early is not reliably a
//! multi-root tree - the grammar accepts `1 2` as one document - and the forest
//! rule is exactly what a matcher gets wrong, so the several-root case is
//! constructed rather than hoped for. It carries the real grammar, because
//! `isNamed` and `childByFieldName` ask it real questions.

const std = @import("std");
const t = std.testing;
const press = @import("../../press/press.zig");
const lex = @import("../lex/scanner.zig");
const quire = @import("quire.zig");

const json_src = @embedFile("json_grammar");

/// A grammar, its tables, a scanner, and the gather over them. Heap allocated
/// because `Gather` borrows the other fields.
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

/// The first node after `ref` in its run that a query could match by name,
/// reached one plain step at a time. `nextSibling` is proved against the
/// oracle next door, so this composition asks only about `isNamed`.
fn namedAfter(q: *const quire.Quire, ref: quire.Ref) ?quire.Ref {
    var at = ref;
    while (q.nextSibling(at)) |n| : (at = n) if (q.isNamed(n)) return n;
    return null;
}

fn namedBefore(q: *const quire.Quire, ref: quire.Ref) ?quire.Ref {
    var at = ref;
    while (q.prevSibling(at)) |p| : (at = p) if (q.isNamed(p)) return p;
    return null;
}

fn covers(q: *const quire.Quire, ref: quire.Ref, from: u32, to: u32) bool {
    return q.nodes[ref].start <= from and to <= q.nodes[ref].end();
}

/// Every accessor with no oracle in the tree, over one parse.
fn reach(q: *const quire.Quire) !void {
    for (0..q.nodes.len) |i| {
        const ref: quire.Ref = @intCast(i);

        // The named walks, and the two properties that pin them from outside.
        // A run cannot hold a named node this one both reaches and is not
        // reached back from, so the round trip is the anchor a query's `.`
        // will lean on in both directions.
        const after = q.nextNamedSibling(ref);
        const before = q.prevNamedSibling(ref);
        try t.expectEqual(namedAfter(q, ref), after);
        try t.expectEqual(namedBefore(q, ref), before);
        if (after) |n| if (q.isNamed(ref)) try t.expectEqual(@as(?quire.Ref, ref), q.prevNamedSibling(n));
        if (before) |p| if (q.isNamed(ref)) try t.expectEqual(@as(?quire.Ref, ref), q.nextNamedSibling(p));

        // Field lookup against the field ids on the children, which is the
        // other side of the same map: whatever `childByFieldName` answers has
        // to be the FIRST child carrying that name and never an extra.
        for (q.children(ref)) |c| if (q.field(c)) |name| {
            const found = q.childByFieldName(ref, name).?;
            try t.expect(!q.isExtra(found));
            try t.expectEqualStrings(name, q.field(found).?);
            for (q.children(ref)) |d| {
                if (d == found) break;
                if (q.field(d)) |other| try t.expect(!std.mem.eql(u8, other, name));
            }
        };
        try t.expectEqual(@as(?quire.Ref, null), q.childByFieldName(ref, "no_such_field"));

        // A node's own span asks for itself, or for whatever sits inside it at
        // the identical span - never for an ancestor, which is the direction a
        // descent that stopped one level early would fail in.
        const n = q.nodes[ref];
        const found = q.descendantForByteRange(n.start, n.end()).?;
        try t.expectEqual(n.start, q.nodes[found].start);
        try t.expectEqual(n.end(), q.nodes[found].end());
        try t.expect(q.depth(found) >= q.depth(ref));
    }

    // The characterisation, over every boundary the tree has. Deepest is the
    // claim, so both directions are checked: nothing under the answer covers
    // the range, and everything over it does.
    for (0..q.nodes.len) |i| {
        const n = q.nodes[@intCast(i)];
        const probes = [_][2]u32{
            .{ n.start, n.start },
            .{ n.start, n.end() },
            .{ n.end(), n.end() },
            .{ n.start, n.end() + 1 },
        };
        for (probes) |p| {
            const found = q.descendantForByteRange(p[0], p[1]) orelse {
                // Nothing covers it, so nothing may: the roots are the whole
                // of what a forest offers.
                for (q.roots) |r| try t.expect(!covers(q, r, p[0], p[1]));
                continue;
            };
            try t.expect(covers(q, found, p[0], p[1]));
            for (q.children(found)) |c| try t.expect(!covers(q, c, p[0], p[1]));
            var up = q.parent(found);
            while (up) |a| : (up = q.parent(a)) try t.expect(covers(q, a, p[0], p[1]));
        }
    }

    // And the same claim the expensive way, on a tree small enough to afford
    // asking every node. Only for a non-empty range: an empty one on a
    // boundary is covered by the node ending there and the node starting
    // there, so "the deepest" is not a single node and the accessor documents
    // which of them it answers with instead.
    if (q.nodes.len <= 400) for (0..q.nodes.len) |i| {
        const n = q.nodes[@intCast(i)];
        if (n.len == 0) continue;
        const found = q.descendantForByteRange(n.start, n.end()).?;
        var deepest: u32 = 0;
        for (0..q.nodes.len) |j| {
            const c: quire.Ref = @intCast(j);
            if (covers(q, c, n.start, n.end())) deepest = @max(deepest, q.depth(c));
        }
        try t.expectEqual(deepest, q.depth(found));
    };

    // Past the end of the text nothing covers anything, which is the query an
    // editor makes on the frame after a delete.
    const beyond: u32 = @intCast(q.nodes.len + 1_000_000);
    try t.expectEqual(@as(?quire.Ref, null), q.descendantForByteRange(beyond, beyond + 1));
}

test "quire: the neighbourhood, over json and the adverse shapes" {
    const gpa = t.allocator;
    const f = try Fixture.init(gpa, json_src);
    defer f.deinit();

    // Deep enough that a recursive walk would not return, wide enough that a
    // scan of the kid list is the whole cost of a sibling step.
    var deep: std.ArrayList(u8) = .empty;
    defer deep.deinit(gpa);
    for (0..2000) |_| try deep.append(gpa, '[');
    for (0..2000) |_| try deep.append(gpa, ']');

    var wide: std.ArrayList(u8) = .empty;
    defer wide.deinit(gpa);
    try wide.append(gpa, '[');
    for (0..4000) |i| {
        if (i != 0) try wide.append(gpa, ',');
        try wide.append(gpa, '1');
    }
    try wide.append(gpa, ']');

    const shapes = [_][]const u8{
        "1",
        "[]",
        "[1,[2,3]]",
        "{\"a\":1,\"b\":[2,3]}",
        // Comments, which is where the extras decision shows.
        "{\"a\":/*x*/1,\n// note\n\"b\":[2,3]}",
        "[1, // one\n 2]",
        // A refused parse, whose roots are the whole forest.
        "1,2",
        "{\"a\" 1 \"b\" 2",
        "",
        deep.items,
        wide.items,
    };
    for (shapes) |bytes| {
        var q = try f.gather.run(bytes);
        defer q.deinit();
        reach(&q) catch |e| {
            std.debug.print("\nquire: the neighbourhood disagreed on {d} bytes\n", .{bytes.len});
            return e;
        };
    }
}

test "quire: a named walk steps onto a comment, because the incumbent's does" {
    // The named tree below is the pinned CLI's own output for these bytes, and
    // it is reproduced here because it is the evidence rather than decoration:
    //
    //   (document (object
    //     (pair key: (string (string_content)) (comment) value: (number))
    //     (comment)
    //     (pair key: (string (string_content)) value: (array (number) (number)))))
    //
    // `tree-sitter parse` prints the NAMED tree, so a comment appearing in it is
    // the incumbent stating that a comment is named and visible - which is the
    // same predicate `ts_node_next_named_sibling` tests. Being an extra exempts
    // it from the field map and from nothing else. The one place a matcher must
    // not see it is `childByFieldName`, and `gather` is what keeps it out:
    // `value:` files the number even with the comment sitting between them.
    //
    // The runs indexed below are the same tree with its anonymous nodes shown,
    // which the incumbent's default print omits and a query still sees:
    //
    //   (object "{" (pair …) "," (comment) (pair …) "}")
    //   (pair key: (string …) ":" (comment) value: (number))
    const gpa = t.allocator;
    const f = try Fixture.init(gpa, json_src);
    defer f.deinit();
    var q = try f.gather.run("{\"a\":/*x*/1,\n// note\n\"b\":[2,3]}");
    defer q.deinit();

    const object = q.children(q.root().?)[0];
    const kids = q.children(object);
    try t.expectEqual(@as(usize, 6), kids.len);
    const pair = kids[1];
    try t.expectEqualStrings("pair", q.name(pair));

    // Inside the pair: key, `:`, comment, value. The plain walk sees all four,
    // the named walk skips only the `:`.
    const inside = q.children(pair);
    try t.expectEqual(@as(usize, 4), inside.len);
    try t.expectEqualStrings(":", q.name(inside[1]));
    try t.expectEqualStrings("comment", q.name(inside[2]));
    try t.expect(q.isExtra(inside[2]));
    try t.expect(q.isNamed(inside[2]));
    try t.expectEqual(@as(?quire.Ref, inside[1]), q.nextSibling(inside[0]));
    try t.expectEqual(@as(?quire.Ref, inside[2]), q.nextNamedSibling(inside[0]));
    try t.expectEqual(@as(?quire.Ref, inside[3]), q.nextNamedSibling(inside[2]));
    try t.expectEqual(@as(?quire.Ref, inside[2]), q.prevNamedSibling(inside[3]));

    // And the field map is the one walk it is absent from.
    try t.expectEqual(@as(?quire.Ref, inside[0]), q.childByFieldName(pair, "key"));
    try t.expectEqual(@as(?quire.Ref, inside[3]), q.childByFieldName(pair, "value"));
    try t.expect(q.field(inside[2]) == null);

    // Between the pairs, a comment is a sibling of both, the `,` is what the
    // named walk steps over, and the comment is what it lands on.
    try t.expectEqualStrings(",", q.name(kids[2]));
    try t.expectEqualStrings("comment", q.name(kids[3]));
    try t.expectEqual(@as(?quire.Ref, kids[2]), q.nextSibling(pair));
    try t.expectEqual(@as(?quire.Ref, kids[3]), q.nextNamedSibling(pair));
    try t.expectEqual(@as(?quire.Ref, kids[4]), q.nextNamedSibling(kids[3]));
    try t.expectEqual(@as(?quire.Ref, pair), q.prevNamedSibling(kids[3]));
}

test "quire: a forest has no top, and every accessor says so" {
    // Hand-built, because the forest rule has to be tested at `roots.len > 1`
    // and json's recovery does not reliably leave one. Three roots with a gap
    // between the second and the third, which is what a stretch of text a mend
    // walked past looks like from here.
    //
    //   [0,4)  holding [0,2) and [2,4)
    //   [6,8)
    //   [12,16)
    const gpa = t.allocator;
    const f = try Fixture.init(gpa, json_src);
    defer f.deinit();
    const nodes = [_]quire.Node{
        .{ .kind = .of(0), .start = 0, .len = 4, .kids_at = 0, .kids_len = 2 },
        .{ .kind = .of(0), .start = 0, .len = 2, .kids_at = 0, .kids_len = 0, .parent = 0 },
        .{ .kind = .of(0), .start = 2, .len = 2, .kids_at = 0, .kids_len = 0, .parent = 0 },
        .{ .kind = .of(0), .start = 6, .len = 2, .kids_at = 0, .kids_len = 0 },
        .{ .kind = .of(0), .start = 12, .len = 4, .kids_at = 0, .kids_len = 0 },
    };
    const kids = [_]quire.Ref{ 1, 2 };
    const roots = [_]quire.Ref{ 0, 3, 4 };
    const q: quire.Quire = .{
        .gpa = gpa,
        .gr = &f.gr,
        .nodes = &nodes,
        .kids = &kids,
        .roots = &roots,
        .stop = .truncated,
    };

    // The roots are a sibling run like any other.
    try t.expectEqual(@as(?quire.Ref, null), q.root());
    for (roots) |r| {
        try t.expectEqual(@as(?quire.Ref, null), q.parent(r));
        try t.expectEqual(@as(u32, 0), q.depth(r));
        try t.expectEqualSlices(quire.Ref, &roots, q.among(r));
    }
    try t.expectEqual(@as(?quire.Ref, 3), q.nextSibling(0));
    try t.expectEqual(@as(?quire.Ref, 4), q.nextSibling(3));
    try t.expectEqual(@as(?quire.Ref, null), q.nextSibling(4));
    try t.expectEqual(@as(?quire.Ref, null), q.prevSibling(0));
    try t.expectEqual(@as(?quire.Ref, 3), q.prevSibling(4));

    // Depth is measured from whichever root you are under, and a child of the
    // first root is not deeper than a child of the third would be.
    try t.expectEqual(@as(u32, 1), q.depth(1));
    try t.expectEqual(@as(u32, 1), q.depth(2));
    try t.expectEqual(@as(u32, 3), try q.subtreeSize(gpa, 0));
    try t.expectEqual(@as(u32, 1), try q.subtreeSize(gpa, 3));

    // A range inside the gap is covered by nothing, and that is the answer -
    // there is no crown to hand back instead.
    try t.expectEqual(@as(?quire.Ref, 1), q.descendantForByteRange(0, 2));
    try t.expectEqual(@as(?quire.Ref, 2), q.descendantForByteRange(2, 4));
    try t.expectEqual(@as(?quire.Ref, 0), q.descendantForByteRange(1, 3));
    try t.expectEqual(@as(?quire.Ref, 3), q.descendantForByteRange(6, 8));
    try t.expectEqual(@as(?quire.Ref, 4), q.descendantForByteRange(13, 14));
    try t.expectEqual(@as(?quire.Ref, null), q.descendantForByteRange(9, 10));
    try t.expectEqual(@as(?quire.Ref, null), q.descendantForByteRange(4, 7));
    try t.expectEqual(@as(?quire.Ref, null), q.descendantForByteRange(20, 21));

    // And the empty forest, which is a state the type can be in.
    const bare: quire.Quire = .{
        .gpa = gpa,
        .gr = &f.gr,
        .nodes = &.{},
        .kids = &.{},
        .roots = &.{},
        .stop = .accepted,
    };
    try t.expectEqual(@as(?quire.Ref, null), bare.descendantForByteRange(0, 0));
    try t.expectEqual(@as(?quire.Ref, null), bare.descendantForByteRange(0, 1));
}
