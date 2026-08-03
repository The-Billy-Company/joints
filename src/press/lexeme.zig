//! Rendering a tree-sitter token rule down to one regex.
//!
//! `token(seq('//', /.*/))` is a *lexical* expression: it never reaches the
//! parser as structure, only as one terminal. So the press flattens it here,
//! once, into the single pattern the lexer will compile — and a rule tree that
//! cannot be flattened (because it reaches a nonterminal, or an external
//! scanner) says so by returning null rather than by producing a pattern that
//! quietly matches the wrong bytes.
//!
//! The output dialect is deliberately plain: literals, classes, alternation,
//! and the three quantifiers. tree-sitter's own patterns are already regexes
//! and pass through untouched inside a non-capturing group, so whatever
//! dialect they were written in is the dialect the engine must accept.

const std = @import("std");
const json = std.json;

/// How deep a `SYMBOL` chain may be inlined before we call it recursive. A
/// genuinely recursive token is not a token, and tree-sitter rejects one too.
const max_depth = 32;

pub const Resolver = struct {
    ctx: *const anyopaque,
    /// Returns the rule body a `SYMBOL` names, or null when that name is not a
    /// lexical rule (a nonterminal, or an external scanner's token).
    lookup: *const fn (ctx: *const anyopaque, name: []const u8) ?json.Value,
};

/// Render `node` into `out`. Returns false when the node reaches something no
/// regex can stand in for, leaving `out` in an unspecified state — a caller
/// that gets false must discard it rather than ship a half-rendered pattern.
pub fn render(
    out: *std.ArrayList(u8),
    gpa: std.mem.Allocator,
    node: json.Value,
    r: Resolver,
    depth: u32,
) error{OutOfMemory}!bool {
    if (depth > max_depth) return false;
    const obj = if (node == .object) node.object else return false;
    const kind = if (obj.get("type")) |t| (if (t == .string) t.string else return false) else return false;

    if (std.mem.eql(u8, kind, "BLANK")) return true;

    if (std.mem.eql(u8, kind, "STRING")) {
        const v = obj.get("value") orelse return false;
        if (v != .string) return false;
        try escape(out, gpa, v.string);
        return true;
    }

    if (std.mem.eql(u8, kind, "PATTERN")) {
        const v = obj.get("value") orelse return false;
        if (v != .string) return false;
        // Flags ride on the node (`i` for case-insensitive). An inline group
        // keeps the flag scoped to this fragment rather than the whole token.
        const flags = if (obj.get("flags")) |f| (if (f == .string) f.string else "") else "";
        if (flags.len == 0) {
            try out.appendSlice(gpa, "(?:");
        } else {
            try out.appendSlice(gpa, "(?");
            try out.appendSlice(gpa, flags);
            try out.append(gpa, ':');
        }
        try out.appendSlice(gpa, v.string);
        try out.append(gpa, ')');
        return true;
    }

    if (std.mem.eql(u8, kind, "SYMBOL")) {
        const v = obj.get("name") orelse return false;
        if (v != .string) return false;
        const body = r.lookup(r.ctx, v.string) orelse return false;
        return render(out, gpa, body, r, depth + 1);
    }

    if (std.mem.eql(u8, kind, "SEQ")) {
        const members = obj.get("members") orelse return false;
        if (members != .array) return false;
        for (members.array.items) |m| if (!try render(out, gpa, m, r, depth + 1)) return false;
        return true;
    }

    if (std.mem.eql(u8, kind, "CHOICE")) {
        const members = obj.get("members") orelse return false;
        if (members != .array) return false;
        try out.appendSlice(gpa, "(?:");
        for (members.array.items, 0..) |m, i| {
            if (i > 0) try out.append(gpa, '|');
            if (!try render(out, gpa, m, r, depth + 1)) return false;
        }
        try out.append(gpa, ')');
        return true;
    }

    if (std.mem.eql(u8, kind, "REPEAT") or std.mem.eql(u8, kind, "REPEAT1")) {
        const content = obj.get("content") orelse return false;
        try out.appendSlice(gpa, "(?:");
        if (!try render(out, gpa, content, r, depth + 1)) return false;
        try out.appendSlice(gpa, if (kind.len == 6) ")*" else ")+");
        return true;
    }

    // Wrappers that shape the tree or the tables, never the bytes.
    if (isWrapper(kind)) {
        const content = obj.get("content") orelse return false;
        return render(out, gpa, content, r, depth + 1);
    }

    return false;
}

/// Node kinds that carry a `content` and contribute nothing to what the bytes
/// look like: naming (`ALIAS`, `FIELD`), lexing hints (`TOKEN`,
/// `IMMEDIATE_TOKEN`), and conflict resolution (`PREC*`).
pub fn isWrapper(kind: []const u8) bool {
    for ([_][]const u8{
        "TOKEN",       "IMMEDIATE_TOKEN", "ALIAS",         "FIELD",
        "PREC",        "PREC_LEFT",       "PREC_RIGHT",    "PREC_DYNAMIC",
    }) |w| if (std.mem.eql(u8, kind, w)) return true;
    return false;
}

/// Write `s` so a regex engine reads it as those exact bytes.
pub fn escape(out: *std.ArrayList(u8), gpa: std.mem.Allocator, s: []const u8) !void {
    for (s) |c| {
        if (std.mem.indexOfScalar(u8, "\\^$.|?*+()[]{}", c) != null) try out.append(gpa, '\\');
        try out.append(gpa, c);
    }
}

const testing = std.testing;

fn renderSource(gpa: std.mem.Allocator, src: []const u8) !?[]u8 {
    const parsed = try json.parseFromSlice(json.Value, gpa, src, .{});
    defer parsed.deinit();
    const none = struct {
        fn lookup(_: *const anyopaque, _: []const u8) ?json.Value {
            return null;
        }
    };
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    const ok = try render(&out, gpa, parsed.value, .{ .ctx = undefined, .lookup = none.lookup }, 0);
    if (!ok) {
        out.deinit(gpa);
        return null;
    }
    return try out.toOwnedSlice(gpa);
}

test "a line comment flattens into one pattern" {
    const src =
        \\{"type":"TOKEN","content":{"type":"SEQ","members":[
        \\  {"type":"STRING","value":"//"},
        \\  {"type":"REPEAT","content":{"type":"PATTERN","value":"[^\n]"}}]}}
    ;
    const got = (try renderSource(testing.allocator, src)).?;
    defer testing.allocator.free(got);
    try testing.expectEqualStrings("//(?:(?:[^\n])*)", got);
}

test "literal metacharacters are escaped, not interpreted" {
    const got = (try renderSource(testing.allocator, "{\"type\":\"STRING\",\"value\":\"a.b*\"}")).?;
    defer testing.allocator.free(got);
    try testing.expectEqualStrings("a\\.b\\*", got);
}

test "a token reaching an unresolvable symbol renders nothing at all" {
    const src = "{\"type\":\"SEQ\",\"members\":[{\"type\":\"STRING\",\"value\":\"x\"},{\"type\":\"SYMBOL\",\"name\":\"expr\"}]}";
    try testing.expectEqual(@as(?[]u8, null), try renderSource(testing.allocator, src));
}
