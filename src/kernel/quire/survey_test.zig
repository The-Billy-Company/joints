//! The negative control for `Quire.survey` - proof it can still say no.
//!
//! `survey` is the only instrument in this project that can see the SHAPE of a
//! tree. Every byte column on the board is a union over spans, and a union is
//! silent about parentage: a child outside its parent contributes its bytes to
//! `built` exactly as a well-placed one does, so toml read `100% standing, 0
//! damage` while holding one for as long as anyone had looked.
//!
//! An instrument that valuable has one failure mode worse than being wrong,
//! and it is going quiet. The corpus gate above it (`tool/sound.py`) reads
//! thirty grammars and passes when none of them complains - which is exactly
//! what it would also do if `survey` stopped walking, if `parse.zig` stopped
//! calling it, or if the verdict clause it is read out of were renamed. Its
//! green is only worth what this file is worth, because these are the trees
//! that make it say no on demand and that no repair to a grammar can dissolve.
//!
//! Hand-built arenas rather than parsed ones, for that reason: a fault planted
//! here is a fault the walk must find, and it stays plantable after every
//! grammar in the corpus is sound.

const std = @import("std");
const t = std.testing;
const quire = @import("quire.zig");
const bough = @import("bough.zig");
const press = @import("../../press/press.zig");

/// An arena in the terms `survey` reads it in, and in no others. `survey`
/// touches `nodes`, `kids` and `roots` and never reaches the grammar - names
/// belong to the report, and this asks for the counts.
fn arena(nodes: []const quire.Node, kids: []const quire.Ref, roots: []const quire.Ref) quire.Quire {
    const gr: *const press.Grammar = undefined;
    return .{
        .gpa = t.allocator,
        .gr = gr,
        .nodes = nodes,
        .kids = kids,
        .roots = roots,
        .stop = .accepted,
    };
}

fn node(start: u32, len: u32, kids_at: u32, kids_len: u32) quire.Node {
    return .{ .kind = .of(0), .start = start, .len = len, .kids_at = kids_at, .kids_len = kids_len };
}

test "a well-formed tree is sound" {
    // parent [0, 10) over two disjoint children in source order.
    const nodes = [_]quire.Node{
        node(0, 10, 0, 2),
        node(0, 4, 0, 0),
        node(5, 5, 0, 0),
    };
    const kids = [_]quire.Ref{ 1, 2 };
    const q = arena(&nodes, &kids, &.{0});

    const found = try q.survey(t.allocator);
    try t.expect(found.sound());
    try t.expectEqual(@as(u32, 0), found.loose);
    try t.expectEqual(@as(u32, 0), found.disorder);
    try t.expectEqual(@as(u32, 0), found.torn);
}

test "a child wholly outside its parent is loose" {
    // Exactly toml's shape: `pair [8, 15)` holding `comment [17, 20)`, an
    // extra carried in from the next symbol's lead by a span the reduction
    // computed from the production's own right-hand side. Disjoint, not merely
    // overhanging - the case a containment check written as an overlap test
    // would miss.
    const nodes = [_]quire.Node{
        node(8, 7, 0, 1),
        node(17, 3, 0, 0),
    };
    const kids = [_]quire.Ref{1};
    const q = arena(&nodes, &kids, &.{0});

    const found = try q.survey(t.allocator);
    try t.expect(!found.sound());
    try t.expectEqual(@as(u32, 1), found.loose);
    const f = found.first orelse return error.NoFaultReported;
    try t.expectEqual(@as(quire.Ref, 1), f.ref);
    try t.expectEqual(@as(quire.Ref, 0), f.under);
    try t.expectEqualStrings("child outside its parent", f.why);
}

test "a child overhanging one edge is loose" {
    // The half-case. A child that starts inside and ends past the parent is as
    // loose as a disjoint one, and it is the shape a span that widened for the
    // start and not the end would leave behind.
    const nodes = [_]quire.Node{
        node(0, 10, 0, 1),
        node(5, 20, 0, 0),
    };
    const kids = [_]quire.Ref{1};
    const q = arena(&nodes, &kids, &.{0});

    const found = try q.survey(t.allocator);
    try t.expectEqual(@as(u32, 1), found.loose);
}

test "siblings out of source order are disorder" {
    const nodes = [_]quire.Node{
        node(0, 10, 0, 2),
        node(4, 6, 0, 0),
        node(0, 4, 0, 0),
    };
    const kids = [_]quire.Ref{ 1, 2 };
    const q = arena(&nodes, &kids, &.{0});

    const found = try q.survey(t.allocator);
    try t.expectEqual(@as(u32, 1), found.disorder);
    try t.expectEqual(@as(u32, 0), found.loose);
}

test "a node reached twice is torn" {
    // One node in two parents' child lists. It prints as two nodes and every
    // byte column counts it once, which is why nothing else in this project
    // can see it.
    const nodes = [_]quire.Node{
        node(0, 10, 0, 2),
        node(0, 4, 2, 1),
        node(4, 6, 2, 1),
        node(4, 2, 0, 0),
    };
    const kids = [_]quire.Ref{ 1, 2, 3 };
    const q = arena(&nodes, &kids, &.{0});

    const found = try q.survey(t.allocator);
    try t.expect(found.torn >= 1);
}

test "an empty forest is sound and says so" {
    // Nothing to walk is not a fault. The vacuity guard belongs one level up,
    // in the caller that decides whether asking nothing counts as a clearance.
    const q = arena(&.{}, &.{}, &.{});
    const found = try q.survey(t.allocator);
    try t.expect(found.sound());
}

test "sound() alone cannot tell a clean walk from no walk" {
    // The falsifier for the silence, stated as an arena rather than as prose.
    // A `Survey` nobody ran is `sound()`, and so is a survey of a three-node
    // tree - so a caller holding only that bit reads a check that stopped
    // being called as a corpus that is clean. `walked`/`held` is the half that
    // separates them, and this asserts the separation exists rather than
    // trusting the field to keep being filled in.
    const never: quire.Quire.Survey = .{};
    try t.expect(never.sound());
    try t.expectEqual(@as(u32, 0), never.held);

    const nodes = [_]quire.Node{
        node(0, 10, 0, 2),
        node(0, 4, 0, 0),
        node(5, 5, 0, 0),
    };
    const kids = [_]quire.Ref{ 1, 2 };
    const q = arena(&nodes, &kids, &.{0});
    const found = try q.survey(t.allocator);
    try t.expect(found.sound());
    // Same bit, different evidence: three nodes reached out of three held.
    try t.expectEqual(@as(u32, 3), found.walked);
    try t.expectEqual(@as(u32, 3), found.held);
}

test "a node no root reaches is held and not walked" {
    // Not a fault - an arena may hold a node the roots abandoned, and calling
    // that "not a tree" would redden every mended parse. But the survey must
    // not report it as covered, because `walked == held` is what a caller
    // leans on to say the walk saw the whole arena.
    const nodes = [_]quire.Node{
        node(0, 10, 0, 1),
        node(0, 4, 0, 0),
        node(20, 4, 0, 0), // reachable from nothing
    };
    const kids = [_]quire.Ref{1};
    const q = arena(&nodes, &kids, &.{0});

    const found = try q.survey(t.allocator);
    try t.expect(found.sound());
    try t.expectEqual(@as(u32, 2), found.walked);
    try t.expectEqual(@as(u32, 3), found.held);
}

test "a zero-length child at its parent's edge is legal" {
    // A nullable reduction lands a zero-width node where the parse stood, and
    // both edges of a parent are places the parse stood. The ordering is
    // `end <= start` for that reason, and a containment check written as a
    // strict one would report every mended parse as unsound.
    const nodes = [_]quire.Node{
        node(0, 10, 0, 2),
        node(0, 0, 0, 0),
        node(10, 0, 0, 0),
    };
    const kids = [_]quire.Ref{ 1, 2 };
    const q = arena(&nodes, &kids, &.{0});

    const found = try q.survey(t.allocator);
    try t.expect(found.sound());
}

test "the guard against naming a ref that is not a node" {
    // `Blame.format` is the sentence you read the day a quire is corrupt, and
    // nothing else in the suite executes it: its one caller is the honest arm of
    // `amend_test`'s negative control, which fires only on a real defect. So this
    // is the same hole `fold.zig`'s decline test was dug for - an untested
    // diagnostic is a line that crashes the first time it is ever needed.
    //
    // And the way it would crash is the branch below. Half the faults a survey
    // reports are "that ref is not a node", so the sentence may not dereference
    // the ref it is reporting on; the guard is the whole reason the function has
    // two arms rather than one. Inverted, or off by one, and asking what went
    // wrong reads past the end of `nodes`.
    //
    // The other arm needs a grammar, because naming a node goes through `name`,
    // and `arena` above deliberately does not have one - `survey` never reaches
    // the grammar, which is what lets these tests be counts over a literal. So
    // that arm stays covered by the negative control alone.
    const q = arena(&.{node(0, 10, 0, 0)}, &.{}, &.{0});
    const past: quire.Quire.Fault = .{ .why = "a ref that is not a node", .ref = 7, .under = quire.none };

    var buf: [128]u8 = undefined;
    try t.expectEqualStrings(
        "quire: a ref that is not a node - ref 7 past 1 nodes, 1 roots",
        try std.fmt.bufPrint(&buf, "{f}", .{q.blame(past)}),
    );
}

test "a bough fault says which ring, and where that ring stood" {
    // Same reasoning as the quire sentence above, and the ring's own marks are
    // the point: a fault at byte 0 of a ring standing at byte 9000 is a different
    // bug from the same fault at its edge, and the ring is gone by the time
    // anybody could go looking. This one needs no grammar - it is all scalars -
    // so there is no arm left uncovered.
    const f: bough.Bough.Fault = .{
        .why = "carried twice by one ring",
        .ring = 3,
        .at = .{
            .at = 9000,
            .token = 41,
            .trail = 8800,
            .nodes = 512,
            .kids = 700,
            .perch = 4,
            .perched = 9,
            .ref = 11,
            .refed = 6,
            .roots = 8,
            .mends = 2,
        },
        .ref = 17,
    };

    var buf: [160]u8 = undefined;
    try t.expectEqualStrings(
        "bough: carried twice by one ring - ring 3 at byte 9000 (token 41, 512 nodes, 8 roots, 2 mends), node 17",
        try std.fmt.bufPrint(&buf, "{f}", .{f}),
    );
}
