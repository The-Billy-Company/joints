//! The repair provenance the parser already records, without inventing error
//! nodes or reconstructing repair spans from the surviving tree.
const std = @import("std");
const bank = @import("bank.zig");

pub const Scar = extern struct {
    at: u32,
    over: u32,
    supplied: u32,
    heads: u32,
    shifted: u32,
    felled: u32,
    stop: c_int,
};

pub fn count(tree: *const bank.Tree) u32 {
    return @intCast(tree.q.scars.len);
}

pub fn get(tree: ?*const bank.Tree, i: u32, out: ?*Scar) bank.Status {
    bank.clear();
    const t = tree orelse return bank.fail(.invalid, "jnt_tree_scar: tree is NULL", .{});
    const slot = out orelse return bank.fail(.invalid, "jnt_tree_scar: out is NULL", .{});
    if (i >= t.q.scars.len) return bank.fail(.invalid, "jnt_tree_scar: index {d} is out of range", .{i});
    const s = t.q.scars[i];
    slot.* = .{
        .at = s.at,
        .over = s.over,
        .supplied = @intFromBool(s.gave != null),
        .heads = s.heads,
        .shifted = s.shifted,
        .felled = @intFromBool(s.felled),
        .stop = @intFromEnum(switch (s.why) {
            .stray => bank.StopKind.stray,
            .unexpected => bank.StopKind.unexpected,
            else => unreachable,
        }),
    };
    return .ok;
}

pub fn word(tree: *const bank.Tree, i: u32) ?[]const u8 {
    if (i >= tree.q.scars.len) return null;
    const symbol = tree.q.scars[i].gave orelse return null;
    return tree.parser.grammar().nameOf(symbol);
}

test "ABI repair provenance is the parser's actual scar list" {
    const testing = std.testing;
    const b = try bank.testBank();
    defer bank.close(b);
    var p: *bank.Parser = undefined;
    try testing.expectEqual(bank.Status.ok, bank.parserNew(b, null, &p));
    defer bank.parserFree(p);
    // A byte JSON cannot lex, inside an otherwise complete array.
    const text = "[1, @, 2]";
    var tree: *bank.Tree = undefined;
    try testing.expectEqual(bank.Status.ok, bank.parse(p, text.ptr, text.len, &tree));
    defer bank.treeFree(tree);
    try testing.expect(count(tree) > 0);
    try testing.expectEqual(@as(usize, tree.q.mends + tree.q.supplied), tree.q.scars.len);
    var total: u32 = 0;
    for (tree.q.scars, 0..) |s, i| {
        var got: Scar = undefined;
        try testing.expectEqual(bank.Status.ok, get(tree, @intCast(i), &got));
        try testing.expectEqual(s.at, got.at);
        try testing.expectEqual(s.over, got.over);
        try testing.expectEqual(s.heads, got.heads);
        try testing.expectEqual(@intFromBool(s.gave != null), got.supplied);
        total += got.over - got.at;
        if (s.gave) |symbol| {
            try testing.expectEqualStrings(p.grammar().nameOf(symbol), word(tree, @intCast(i)).?);
        } else try testing.expect(word(tree, @intCast(i)) == null);
    }
    try testing.expectEqual(tree.q.skipped, total);
    var absent: Scar = undefined;
    try testing.expectEqual(bank.Status.invalid, get(tree, count(tree), &absent));
    try testing.expectEqual(bank.Status.invalid, get(null, 0, &absent));
    try testing.expectEqual(bank.Status.invalid, get(tree, 0, null));
    try testing.expect(word(tree, count(tree)) == null);
}
