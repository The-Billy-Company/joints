//! Compile and run the existing gloss engine through libjnt. A query owns its
//! grammar index and compiled program; results own their match/capture arrays.
//! Node refs remain views into the tree that was queried, so free results before
//! freeing or editing that tree. A query borrows its parser as its identity.

const std = @import("std");
const joints = @import("joints");
const bank = @import("bank.zig");
const gloss = joints.kernel.gloss;
const folio = joints.folio;
const gpa = std.heap.c_allocator;
const Status = bank.Status;

pub const Query = struct {
    parser: *const bank.Parser,
    bytes: []align(folio.align_bytes) u8,
    f: folio.Folio,
    index: gloss.Lemma,
    compiled: gloss.Compiled,
};

const Match = struct { pattern: u32, first: u32, count: u32 };

pub const Result = struct {
    /// Borrowed identities. Captured refs address this tree, and capture IDs
    /// address this query; neither owner may be freed while the result lives.
    query: *const Query,
    tree: *const bank.Tree,
    matches: []Match,
    captures: []gloss.Capture,
};

fn failed(comptime operation: []const u8, err: anyerror) Status {
    return bank.fail(if (err == error.OutOfMemory) .out_of_memory else .format, operation ++ ": {s}", .{@errorName(err)});
}

pub fn compile(parser: ?*const bank.Parser, source: ?[*]const u8, len: usize, out: ?**Query) Status {
    bank.clear();
    const slot = out orelse return bank.fail(.invalid, "jnt_query_compile: out is NULL", .{});
    const p = parser orelse return bank.fail(.invalid, "jnt_query_compile: parser is NULL", .{});
    const scm = if (len == 0) &.{} else (source orelse
        return bank.fail(.invalid, "jnt_query_compile: source is NULL", .{}))[0..len];
    const q = gpa.create(Query) catch return failed("jnt_query_compile", error.OutOfMemory);
    q.parser = p;
    // The mapped and pressed paths produce the same owned metadata. A Lemma
    // retains a pointer to its Folio, so initialize in the allocated handle.
    q.bytes = switch (p.bank.source) {
        .mapped => |*mapped| blk: {
            const f = mapped.volume.pick(bank.parserLanguage(p)) catch |err| {
                gpa.destroy(q);
                return failed("jnt_query_compile", err);
            };
            const bytes = gpa.alignedAlloc(u8, .fromByteUnits(folio.align_bytes), f.bytes.len) catch {
                gpa.destroy(q);
                return failed("jnt_query_compile", error.OutOfMemory);
            };
            @memcpy(bytes, f.bytes);
            break :blk bytes;
        },
        .pressed => |*x| folio.pack(gpa, &x.gr, &x.built) catch |err| {
            gpa.destroy(q);
            return failed("jnt_query_compile", err);
        },
    };
    q.f = folio.open(q.bytes) catch |err| {
        gpa.free(q.bytes);
        gpa.destroy(q);
        return failed("jnt_query_compile", err);
    };
    q.index = gloss.index(gpa, &q.f) catch |err| {
        gpa.free(q.bytes);
        gpa.destroy(q);
        return failed("jnt_query_compile", err);
    };
    var fault: gloss.Fault = .{};
    q.compiled = gloss.compile(gpa, &q.index, scm, &fault) catch |err| {
        // Fault.name can borrow the source, so render it before returning.
        const status = bank.fail(if (err == error.OutOfMemory) .out_of_memory else .format, "jnt_query_compile: {s} at byte {d}: {s}", .{ @errorName(err), fault.at, fault.name });
        q.index.deinit();
        gpa.free(q.bytes);
        gpa.destroy(q);
        return status;
    };
    slot.* = q;
    return .ok;
}

pub fn free(q: *Query) void {
    q.compiled.deinit();
    q.index.deinit();
    gpa.free(q.bytes);
    gpa.destroy(q);
}

pub fn patternCount(q: *const Query) u32 {
    return q.compiled.view().?.patternCount();
}

pub fn captureCount(q: *const Query) u32 {
    return q.compiled.view().?.captureCount();
}

pub fn captureName(q: *const Query, id: u32) ?[]const u8 {
    const program = q.compiled.view().?;
    return if (id < program.captureCount()) program.captureAt(id) else null;
}

pub fn exec(query: ?*const Query, tree: ?*const bank.Tree, source: ?[*]const u8, len: usize, foreign: c_int, out: ?**Result) Status {
    bank.clear();
    const slot = out orelse return bank.fail(.invalid, "jnt_query_exec: out is NULL", .{});
    const q = query orelse return bank.fail(.invalid, "jnt_query_exec: query is NULL", .{});
    const t = tree orelse return bank.fail(.invalid, "jnt_query_exec: tree is NULL", .{});
    if (q.parser != t.parser) return bank.fail(.invalid, "jnt_query_exec: tree belongs to a different parser", .{});
    const policy: gloss.Foreign = switch (foreign) {
        0 => .refuse,
        1 => .admit,
        2 => .deny,
        else => return bank.fail(.invalid, "jnt_query_exec: unknown foreign policy {d}", .{foreign}),
    };
    const text = if (len == 0) &.{} else (source orelse
        return bank.fail(.invalid, "jnt_query_exec: source is NULL", .{}))[0..len];
    var cursor = gloss.open(gpa, q.compiled.view().?, .{
        .q = &t.q,
        .src = text,
        .index = &q.index,
        .foreign = policy,
    }) catch |err| return failed("jnt_query_exec", err);
    defer cursor.deinit();
    var matches: std.ArrayList(Match) = .empty;
    defer matches.deinit(gpa);
    var captures: std.ArrayList(gloss.Capture) = .empty;
    defer captures.deinit(gpa);
    while (cursor.next() catch |err| return failed("jnt_query_exec", err)) |m| {
        if (matches.items.len == std.math.maxInt(u32) or
            m.captures.len > std.math.maxInt(u32) - captures.items.len)
            return failed("jnt_query_exec", error.QueryTooLarge);
        matches.append(gpa, .{ .pattern = m.pattern, .first = @intCast(captures.items.len), .count = @intCast(m.captures.len) }) catch
            return failed("jnt_query_exec", error.OutOfMemory);
        captures.appendSlice(gpa, m.captures) catch return failed("jnt_query_exec", error.OutOfMemory);
    }
    if (cursor.declined != 0) return bank.fail(.format, "jnt_query_exec: unsupported query group inside a choice ({d} declined attempts)", .{cursor.declined});
    const r = gpa.create(Result) catch return failed("jnt_query_exec", error.OutOfMemory);
    const owned_matches = matches.toOwnedSlice(gpa) catch {
        gpa.destroy(r);
        return failed("jnt_query_exec", error.OutOfMemory);
    };
    const owned_captures = captures.toOwnedSlice(gpa) catch {
        gpa.free(owned_matches);
        gpa.destroy(r);
        return failed("jnt_query_exec", error.OutOfMemory);
    };
    r.* = .{ .query = q, .tree = t, .matches = owned_matches, .captures = owned_captures };
    slot.* = r;
    return .ok;
}

pub fn resultFree(r: *Result) void {
    gpa.free(r.matches);
    gpa.free(r.captures);
    gpa.destroy(r);
}

pub fn resultCount(r: *const Result) u32 {
    return @intCast(r.matches.len);
}

pub fn resultPattern(r: *const Result, match: u32) u32 {
    return if (match < r.matches.len) r.matches[match].pattern else bank.none;
}

pub fn resultCaptureCount(r: *const Result, match: u32) u32 {
    return if (match < r.matches.len) r.matches[match].count else 0;
}

fn captured(r: *const Result, match: u32, capture: u32) ?gloss.Capture {
    if (match >= r.matches.len) return null;
    const m = r.matches[match];
    return if (capture < m.count) r.captures[m.first + capture] else null;
}

pub fn resultCaptureId(r: *const Result, match: u32, capture: u32) u32 {
    return if (captured(r, match, capture)) |cap| cap.id else bank.none;
}

pub fn resultCaptureNode(r: *const Result, match: u32, capture: u32) u32 {
    return if (captured(r, match, capture)) |cap| cap.node else bank.none;
}

const testing = std.testing;

test "ABI query captures predicate-filtered JSON nodes and owns compiled source" {
    const b = try bank.testBank();
    defer bank.close(b);
    var p: *bank.Parser = undefined;
    try testing.expectEqual(Status.ok, bank.parserNew(b, null, &p));
    defer bank.parserFree(p);
    const text = "{\"one\": 1, \"two\": 2}";
    var tree: *bank.Tree = undefined;
    try testing.expectEqual(Status.ok, bank.parse(p, text.ptr, text.len, &tree));
    defer bank.treeFree(tree);
    var scm = "((number) @selected (#eq? @selected \"2\"))\n(string) @key".*;
    var query: *Query = undefined;
    try testing.expectEqual(Status.ok, compile(p, &scm, scm.len, &query));
    defer free(query);
    @memset(&scm, ' ');
    try testing.expectEqual(@as(u32, 2), patternCount(query));
    try testing.expectEqual(@as(u32, 2), captureCount(query));
    try testing.expectEqualStrings("selected", captureName(query, 0).?);
    try testing.expect(captureName(query, 9) == null);
    var result: *Result = undefined;
    try testing.expectEqual(Status.ok, exec(query, tree, text.ptr, text.len, 0, &result));
    defer resultFree(result);
    try testing.expectEqual(@as(u32, 3), resultCount(result));
    var selected: u32 = 0;
    var keys: u32 = 0;
    for (0..resultCount(result)) |i| {
        const match: u32 = @intCast(i);
        try testing.expectEqual(@as(u32, 1), resultCaptureCount(result, match));
        const id = resultCaptureId(result, match, 0);
        const node = resultCaptureNode(result, match, 0);
        if (resultPattern(result, match) == 0) {
            selected += 1;
            try testing.expectEqual(@as(u32, 0), id);
            try testing.expectEqualStrings("number", bank.nodeName(tree, node).?);
            try testing.expectEqualStrings("2", text[bank.nodeStart(tree, node)..bank.nodeEnd(tree, node)]);
        } else {
            keys += 1;
            try testing.expectEqual(@as(u32, 1), id);
            try testing.expectEqualStrings("string", bank.nodeName(tree, node).?);
        }
    }
    try testing.expectEqual(@as(u32, 1), selected);
    try testing.expectEqual(@as(u32, 2), keys);
    try testing.expectEqual(bank.none, resultPattern(result, 99));
    try testing.expectEqual(bank.none, resultCaptureNode(result, 0, 99));
}

test "ABI query distinguishes no matches, malformed source and wrong parser" {
    const b = try bank.testBank();
    defer bank.close(b);
    var p: *bank.Parser = undefined;
    var other: *bank.Parser = undefined;
    try testing.expectEqual(Status.ok, bank.parserNew(b, null, &p));
    defer bank.parserFree(p);
    try testing.expectEqual(Status.ok, bank.parserNew(b, null, &other));
    defer bank.parserFree(other);
    const text = "{\"a\": 1}";
    var tree: *bank.Tree = undefined;
    var other_tree: *bank.Tree = undefined;
    try testing.expectEqual(Status.ok, bank.parse(p, text.ptr, text.len, &tree));
    defer bank.treeFree(tree);
    try testing.expectEqual(Status.ok, bank.parse(other, text.ptr, text.len, &other_tree));
    defer bank.treeFree(other_tree);
    var query: *Query = undefined;
    const scm = "(true) @nothing";
    try testing.expectEqual(Status.ok, compile(p, scm.ptr, scm.len, &query));
    defer free(query);
    var result: *Result = undefined;
    try testing.expectEqual(Status.ok, exec(query, tree, text.ptr, text.len, 0, &result));
    try testing.expectEqual(@as(u32, 0), resultCount(result));
    resultFree(result);
    try testing.expectEqual(Status.invalid, exec(query, other_tree, text.ptr, text.len, 0, &result));
    try testing.expect(std.mem.indexOf(u8, std.mem.span(bank.lastError()), "different parser") != null);
    var bad: *Query = undefined;
    try testing.expectEqual(Status.format, compile(p, "(number", 7, &bad));
    try testing.expect(std.mem.indexOf(u8, std.mem.span(bank.lastError()), "byte") != null);
    try testing.expectEqual(Status.format, compile(p, "(unknown) @a", 12, &bad));
    try testing.expectEqual(Status.invalid, compile(null, null, 0, &bad));
    try testing.expectEqual(Status.invalid, compile(p, null, 1, &bad));
    try testing.expectEqual(Status.invalid, compile(p, scm.ptr, scm.len, null));
    try testing.expectEqual(Status.invalid, exec(null, tree, text.ptr, text.len, 0, &result));
    try testing.expectEqual(Status.invalid, exec(query, null, text.ptr, text.len, 0, &result));
    try testing.expectEqual(Status.invalid, exec(query, tree, text.ptr, text.len, 0, null));
    try testing.expectEqual(Status.invalid, exec(query, tree, null, text.len, 0, &result));
}

test "ABI query foreign policy and source requirements fail explicitly" {
    const b = try bank.testBank();
    defer bank.close(b);
    var p: *bank.Parser = undefined;
    try testing.expectEqual(Status.ok, bank.parserNew(b, null, &p));
    defer bank.parserFree(p);
    var tree: *bank.Tree = undefined;
    try testing.expectEqual(Status.ok, bank.parse(p, "2", 1, &tree));
    defer bank.treeFree(tree);
    var query: *Query = undefined;
    const scm = "((number) @n (#is? local))";
    try testing.expectEqual(Status.ok, compile(p, scm.ptr, scm.len, &query));
    defer free(query);
    var result: *Result = undefined;
    try testing.expectEqual(Status.format, exec(query, tree, "2", 1, 0, &result));
    try testing.expectEqual(Status.ok, exec(query, tree, "2", 1, 1, &result));
    try testing.expectEqual(@as(u32, 1), resultCount(result));
    resultFree(result);
    try testing.expectEqual(Status.ok, exec(query, tree, "2", 1, 2, &result));
    try testing.expectEqual(@as(u32, 0), resultCount(result));
    resultFree(result);
    try testing.expectEqual(Status.invalid, exec(query, tree, "2", 1, 99, &result));
    var filtered: *Query = undefined;
    const filter = "((number) @n (#eq? @n \"2\"))";
    try testing.expectEqual(Status.ok, compile(p, filter.ptr, filter.len, &filtered));
    defer free(filtered);
    try testing.expectEqual(Status.format, exec(filtered, tree, null, 0, 0, &result));
    try testing.expect(std.mem.indexOf(u8, std.mem.span(bank.lastError()), "QuerySourceShort") != null);
}

test "ABI query indexes a mapped folio and preserves eager results across later executions" {
    const pressed = try bank.testBank();
    defer bank.close(pressed);
    const bytes = try folio.pack(testing.allocator, &pressed.source.pressed.gr, &pressed.source.pressed.built);
    defer testing.allocator.free(bytes);
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "g.folio", .data = bytes });
    const path = try std.fmt.allocPrintSentinel(testing.allocator, ".zig-cache/tmp/{s}/g.folio", .{tmp.sub_path}, 0);
    defer testing.allocator.free(path);
    var mapped: *bank.Bank = undefined;
    try testing.expectEqual(Status.ok, bank.open(path.ptr, &mapped));
    defer bank.close(mapped);
    try testing.expect(mapped.source == .mapped);
    var parser: *bank.Parser = undefined;
    try testing.expectEqual(Status.ok, bank.parserNew(mapped, null, &parser));
    defer bank.parserFree(parser);
    var tree: *bank.Tree = undefined;
    try testing.expectEqual(Status.ok, bank.parse(parser, "[1, 2]", 6, &tree));
    defer bank.treeFree(tree);
    var query: *Query = undefined;
    const scm = "(number) @n";
    try testing.expectEqual(Status.ok, compile(parser, scm.ptr, scm.len, &query));
    defer free(query);
    var first: *Result = undefined;
    try testing.expectEqual(Status.ok, exec(query, tree, "[1, 2]", 6, 0, &first));
    defer resultFree(first);
    var second: *Result = undefined;
    try testing.expectEqual(Status.ok, exec(query, tree, "[1, 2]", 6, 0, &second));
    defer resultFree(second);
    try testing.expectEqual(@as(u32, 2), resultCount(first));
    try testing.expectEqual(@as(u32, 2), resultCount(second));
    try testing.expectEqual(resultCaptureNode(first, 0, 0), resultCaptureNode(second, 0, 0));
    try testing.expectEqualStrings("n", captureName(query, resultCaptureId(first, 0, 0)).?);
}

test "ABI query refuses unsupported branches without publishing partial results" {
    const b = try bank.testBank();
    defer bank.close(b);
    var p: *bank.Parser = undefined;
    try testing.expectEqual(Status.ok, bank.parserNew(b, null, &p));
    defer bank.parserFree(p);
    const text = "[1, true]";
    var tree: *bank.Tree = undefined;
    try testing.expectEqual(Status.ok, bank.parse(p, text.ptr, text.len, &tree));
    defer bank.treeFree(tree);
    var query: *Query = undefined;
    const scm = "[((number)) (true)] @x";
    try testing.expectEqual(Status.ok, compile(p, scm.ptr, scm.len, &query));
    defer free(query);
    var result: *Result = @ptrFromInt(@alignOf(Result));
    const before = result;
    try testing.expectEqual(Status.format, exec(query, tree, text.ptr, text.len, 0, &result));
    try testing.expectEqual(before, result);
    try testing.expect(std.mem.indexOf(u8, std.mem.span(bank.lastError()), "unsupported") != null);
}

test "ABI query runs regex predicates on the captured source bytes" {
    const b = try bank.testBank();
    defer bank.close(b);
    var p: *bank.Parser = undefined;
    try testing.expectEqual(Status.ok, bank.parserNew(b, null, &p));
    defer bank.parserFree(p);
    const text = "[12, 23, 32]";
    var tree: *bank.Tree = undefined;
    try testing.expectEqual(Status.ok, bank.parse(p, text.ptr, text.len, &tree));
    defer bank.treeFree(tree);
    var query: *Query = undefined;
    const scm = "((number) @n (#match? @n \"^2[0-9]$\"))";
    try testing.expectEqual(Status.ok, compile(p, scm.ptr, scm.len, &query));
    defer free(query);
    var result: *Result = undefined;
    try testing.expectEqual(Status.ok, exec(query, tree, text.ptr, text.len, 0, &result));
    defer resultFree(result);
    try testing.expectEqual(@as(u32, 1), resultCount(result));
    const node = resultCaptureNode(result, 0, 0);
    try testing.expectEqualStrings("23", text[bank.nodeStart(tree, node)..bank.nodeEnd(tree, node)]);
}
