//! The gate that guards the format: press, pack, load, and compare field by
//! field - then break the bytes on purpose, one failure mode at a time, and
//! insist on the named refusal.
//!
//! The round trip alone is not enough and never was. A writer and a reader that
//! agree on a wrong layout round-trip perfectly, and the file they agree on is
//! still a file that some other version will misread. So the second half of this
//! is adversarial: every check `open` makes gets a test that trips exactly it,
//! and a fuzz pass that hands the reader arbitrary bytes and demands a refusal
//! rather than a crash.
//!
//! Rejection tests re-seal after mutating, because otherwise every one of them
//! would stop at `FolioBadSeal` and prove only that BLAKE3 works. Re-sealing is
//! what a determined corrupter - or an older writer - would do anyway, which is
//! precisely the case the layout checks exist for.

const std = @import("std");
const folio = @import("folio.zig");
const leaf = @import("leaf.zig");
const fold = @import("../press/fold.zig");
const g = @import("../press/grammar.zig");
const press = @import("../press/press.zig");
const settle = @import("../press/settle.zig");

const testing = std.testing;

/// A grammar small enough to check by hand and rich enough to exercise every
/// section: two literal terminals, a regex, an external, an immediate token
/// with a lexical precedence, an extra, a word rule, a supertype, a rename, a
/// field, and a hidden rule.
///
/// It also carries one contested cell of each class the format can spell, so
/// the round trip below has something to be about. A section whose records all
/// happen to be zero round-trips perfectly no matter what the writer forgot,
/// and the conflict section is the one where that already happened once.
fn sample(gpa: std.mem.Allocator) !g.Grammar {
    var b = g.Builder.init(gpa);
    defer b.deinit();

    const id = try b.intern("id", "identifier", .{ .regex = "[a-z]+" });
    const kw = try b.intern("kw", "let", .{ .literal = "let" });
    const eq = try b.intern("eq", "=", .{ .literal = "=" });
    const semi = try b.intern("semi", ";", .{ .literal = ";" });
    const ws = try b.intern("ws", "whitespace", .{ .regex = "\\s+" });
    const raw = try b.intern("raw", "raw_text", .external);
    const open = try b.intern("open", "{", .{ .literal = "{" });
    const close = try b.intern("close", "}", .{ .literal = "}" });
    b.describe(raw, .{ .immediate = true, .prec = 3 });
    b.describe(kw, .{ .prec = 1 });
    b.word = id;

    const start = try b.intern("$start", "$start", null);
    const stmt = try b.intern("stmt", "statement", null);
    const expr = try b.intern("expr", "_expression", null);
    const helper = try b.intern("helper", "statement_repeat1", null);
    const tag = try b.intern("tag", "tag", null);
    const body = try b.intern("body", "body", null);
    b.shape(helper, .invented);
    b.ascribe(helper, stmt);
    b.shape(expr, .hidden);
    try b.elevate(expr);

    const name_field = try b.internField("name");
    const rename = try b.internAlias("binding", true);

    try b.addProduction(start, &.{stmt}, &.{});
    try b.addProduction(stmt, &.{ kw, id, eq, expr, semi }, &.{
        .{}, .{ .field = name_field, .alias = rename }, .{}, .{}, .{},
    });
    try b.addProduction(stmt, &.{helper}, &.{});
    try b.addProduction(helper, &.{id}, &.{});
    try b.addProduction(helper, &.{ helper, id }, &.{});
    try b.addProduction(expr, &.{id}, &.{});
    try b.addProduction(expr, &.{raw}, &.{});

    // Go's `&T{}` in miniature, and the reason this grammar has a `{` at all.
    // After `id`, `tag -> id .` is a legal fold on `{` and `stmt -> id . body`
    // wants to read it. The reading is ranked -1 and the fold is ranked by
    // nobody, so the only thing that separates them is upstream reading an
    // absent level as zero - which is exactly the comparison that may order the
    // two and may not delete one. The cell comes out `unwritten`.
    try b.addProduction(stmt, &.{ tag, body }, &.{});
    try b.addProduction(stmt, &.{ id, body }, &.{ .{ .prec = .{ .level = -1 } }, .{} });
    try b.addProduction(tag, &.{id}, &.{});
    try b.addProduction(body, &.{ open, close }, &.{});
    return b.finish("sample", start, &.{ws}, &.{});
}

const Pressed = struct {
    grammar: g.Grammar,
    result: press.Result,

    fn of(gpa: std.mem.Allocator) !Pressed {
        var gr = try sample(gpa);
        errdefer gr.deinit();
        return .{ .grammar = gr, .result = try press.tables(gpa, &gr) };
    }

    fn deinit(p: *Pressed) void {
        p.result.deinit();
        p.grammar.deinit();
    }
};

test "a pressed grammar survives the round trip field by field" {
    var p = try Pressed.of(testing.allocator);
    defer p.deinit();
    const bytes = try folio.pack(testing.allocator, &p.grammar, &p.result);
    defer testing.allocator.free(bytes);

    const f = try folio.open(bytes);
    const gr = &p.grammar;
    const c = &p.result.collection;
    const t = &p.result.tables;

    try testing.expectEqualStrings(gr.name, f.title());
    try testing.expectEqual(gr.symbolCount(), f.symbolCount());
    try testing.expectEqual(gr.terminal_count, f.head.terminal_count);
    try testing.expectEqual(gr.start, f.head.start);
    try testing.expectEqual(gr.word, f.word());
    try testing.expectEqual(p.result.unfolded, f.head.unfolded);
    try testing.expectEqual(t.width, f.head.width);
    try testing.expectEqual(t.end, f.head.end);

    for (0..gr.symbolCount()) |i| {
        const s: u32 = @intCast(i);
        // Byte-exact, not merely equal-looking: this is the compatibility
        // promise every `highlights.scm` is keyed on.
        try testing.expectEqualStrings(gr.nameOf(s), f.nameOf(s));
        try testing.expectEqual(gr.isTerminal(s), f.isTerminal(s));
        try testing.expectEqual(gr.owner[s], f.ownerOf(s));
        try testing.expectEqual(gr.lexisOf(s).immediate, f.lexisOf(s).flags & leaf.LexisRecord.immediate != 0);
        try testing.expectEqual(gr.lexisOf(s).prec, f.lexisOf(s).prec);
        try testing.expectEqual(@tagName(gr.shapeOf(s)), @tagName(f.shapeOf(s)));
        switch (gr.patterns[s] orelse {
            try testing.expectEqual(@as(?folio.Pattern, null), f.patternOf(s));
            continue;
        }) {
            .literal => |want| try testing.expectEqualStrings(want, f.patternOf(s).?.literal),
            .regex => |want| try testing.expectEqualStrings(want, f.patternOf(s).?.regex),
            .external => try testing.expectEqual(folio.Pattern.external, f.patternOf(s).?),
        }
    }
    try testing.expectEqualSlices(u32, gr.extras, f.extras());
    try testing.expectEqualSlices(u32, gr.supertypes, f.supertypes());
    for (gr.aliases, 0..) |a, i| {
        const back = f.aliasOf(@intCast(i));
        try testing.expectEqualStrings(a.name, back.name);
        try testing.expectEqual(a.named, back.named);
    }
    for (gr.field_names, 0..) |name, i| {
        try testing.expectEqualStrings(name, f.fieldOf(@intCast(i)));
    }

    for (gr.productions, 0..) |prod, i| {
        try testing.expectEqual(prod.lhs, f.productions()[i].lhs);
        try testing.expectEqualSlices(u32, prod.rhs, f.rhsOf(@intCast(i)));
        const refs = f.stepsOf(@intCast(i));
        for (prod.steps, 0..) |step, j| {
            const back = f.stepAt(refs.at(@intCast(j)));
            try testing.expectEqual(step.alias orelse leaf.none, back.alias);
            try testing.expectEqual(step.field orelse leaf.none, back.field);
        }
    }
    // Two of `Step`'s five fields are on disk and three are not, and *which*
    // three is a decision rather than an accident. `impose`'s ledger already
    // refuses a sixth field silently; this refuses one being added to `Step`
    // without somebody choosing which side of the format it falls on.
    comptime {
        const carried: []const []const u8 = &.{ "alias", "field" };
        const spent: []const []const u8 = &.{ "prec", "assoc", "spliced" };
        for (std.meta.fields(g.Step)) |fld| {
            for (carried) |n| {
                if (std.mem.eql(u8, n, fld.name)) break;
            } else for (spent) |n| {
                if (std.mem.eql(u8, n, fld.name)) break;
            } else @compileError("g.Step." ++ fld.name ++ " is neither asserted" ++
                " through the folio above nor listed as spent during the press." ++
                " A field nobody round-trips is a field that vanishes quietly.");
        }
    }

    for (0..c.states.len) |i| {
        try testing.expectEqualSlices(u32, c.states[i].complete, f.completeOf(@intCast(i)));
    }
}

test "a spliced rank is spent by the press and reaches no reader through the file" {
    // Verilog's shape in miniature, and the reason this test is not the one
    // above: `sample` builds its productions by hand, so no step in it was ever
    // substituted into anything and `spliced` would be false everywhere for
    // reasons that have nothing to do with the writer. A section of records
    // that all happen to be zero round-trips perfectly however wrong the writer
    // is, which is how a dropped field once reported thirty grammars moved
    // nothing at all.
    var b = g.Builder.init(testing.allocator);
    defer b.deinit();
    const word = try b.intern("word", "word", .{ .regex = "[a-z]+" });
    const open = try b.intern("open", "[", .{ .literal = "[" });
    const close = try b.intern("close", "]", .{ .literal = "]" });
    const start = try b.intern("$start", "$start", null);
    const top = try b.intern("top", "top", null);
    const lvalue = try b.intern("lvalue", "lvalue", null);
    const hidden = try b.intern("hidden", "_hierarchical", null);
    const rename = try b.internAlias("bound", true);

    try b.addProduction(start, &.{top}, &.{});
    try b.addProduction(top, &.{lvalue}, &.{});
    // The host ranks its whole body at 37; the victim it reaches through
    // already ranked itself at 0, so the boundary step keeps the victim's rank
    // and the 37 is dropped. That is the defect, and after the fold the only
    // thing that can still say so is the provenance bit.
    try b.addProduction(lvalue, &.{ hidden, open, word, close }, &.{
        .{ .prec = .{ .level = 37 }, .assoc = .left },
        .{ .prec = .{ .level = 37 }, .assoc = .left },
        .{ .prec = .{ .level = 37 }, .assoc = .left, .alias = rename },
        .{ .prec = .{ .level = 37 }, .assoc = .left },
    });
    try b.addProduction(hidden, &.{word}, &.{.{ .prec = .{ .level = 0 }, .assoc = .left }});

    _ = try fold.nonterminals(testing.allocator, &b, &.{start}, &.{hidden});
    var gr = try b.finish("splice", start, &.{}, &.{});
    defer gr.deinit();

    // Anti-vacuity, before anything is written: the fixture really did splice a
    // rank, and the rank that survived really is the victim's.
    var spliced: usize = 0;
    for (gr.productions) |prod| {
        for (prod.steps) |step| {
            if (!step.spliced) continue;
            spliced += 1;
            try testing.expectEqual(g.Prec{ .level = 0 }, step.prec);
        }
    }
    try testing.expectEqual(@as(usize, 1), spliced);

    var result = try press.tables(testing.allocator, &gr);
    defer result.deinit();
    const bytes = try folio.pack(testing.allocator, &gr, &result);
    defer testing.allocator.free(bytes);
    const f = try folio.open(bytes);
    var back = try folio.bind(testing.allocator, &f);
    defer back.deinit();

    // And a bound step carries what names a child, exactly, and none of what
    // the press spent deciding the cells - `spliced` included, since a bit
    // about a rank that is not in the file would be a bit about nothing.
    try testing.expectEqual(gr.productions.len, back.grammar.productions.len);
    for (gr.productions, back.grammar.productions) |want, got| {
        try testing.expectEqualSlices(g.Symbol, want.rhs, got.rhs);
        for (want.steps, got.steps) |a, c| {
            try testing.expectEqual(a.alias, c.alias);
            try testing.expectEqual(a.field, c.field);
            try testing.expectEqual(g.Prec.none, c.prec);
            try testing.expectEqual(g.Assoc.none, c.assoc);
            try testing.expect(!c.spliced);
        }
    }
    // The rename is the control on the line above: a step that carries nothing
    // agrees with an empty one no matter what the writer forgot.
    var renamed: usize = 0;
    for (back.grammar.productions) |prod| {
        for (prod.steps) |step| {
            if (step.alias != null) renamed += 1;
        }
    }
    try testing.expectEqual(@as(usize, 1), renamed);
}

test "the table and the automaton come back out of the interned form intact" {
    var p = try Pressed.of(testing.allocator);
    defer p.deinit();
    const bytes = try folio.pack(testing.allocator, &p.grammar, &p.result);
    defer testing.allocator.free(bytes);
    const f = try folio.open(bytes);

    // The table is not stored as a table any more: rows are shared, groups are
    // interned, and the edges are derived from the shifts. So the round trip
    // that matters is through `bind`, which is what a parse actually gets.
    var back = try folio.bind(testing.allocator, &f);
    defer back.deinit();
    const c = &p.result.collection;
    const t = &p.result.tables;

    try testing.expectEqual(t.width, back.tables.width);
    try testing.expectEqual(t.end, back.tables.end);
    try testing.expectEqualSlices(u32, @ptrCast(t.action), @ptrCast(back.tables.action));
    try testing.expectEqual(c.states.len, back.collection.states.len);
    for (c.states, back.collection.states) |want, got| {
        try testing.expectEqualSlices(u32, want.complete, got.complete);
        try testing.expectEqual(want.edges.len, got.edges.len);
        for (want.edges, got.edges) |a, b| {
            try testing.expectEqual(a.symbol, b.symbol);
            try testing.expectEqual(a.target, b.target);
        }
    }
    try testing.expectEqual(t.conflicts.len, back.tables.conflicts.len);
    try testing.expectEqual(t.frayed.len, back.tables.frayed.len);
    for (t.conflicts, back.tables.conflicts) |want, got| try mirrors(want, got);
    for (t.frayed, back.tables.frayed) |want, got| try mirrors(want, got);

    // And the comparison had something to compare. A field the writer drops
    // comes back as its default, so a section of default-shaped records agrees
    // with itself however wrong it is - which is how a dropped `merged` flag
    // once reported thirty grammars byte-identical and nothing moved.
    var seen: std.EnumSet(settle.Conflict.Class) = .initEmpty();
    for (t.conflicts) |k| seen.insert(k.class);
    try testing.expect(seen.count() > 0);
    try testing.expect(seen.contains(.unwritten));
}

/// Every field of a record, compared by reflection rather than by name.
///
/// The list of fields worth comparing is the list of fields, and writing it out
/// by hand is how one stops being the other. `impose`'s `ledger` already fails
/// the build when the press grows a field the format has no room for; this is
/// the other half - the field has room, and the writer or the reader is not
/// using it. Neither half catches what the other does: a slot can exist and go
/// unwritten, and a decision to carry a field can be made and then implemented
/// backwards.
fn mirrors(want: anytype, got: @TypeOf(want)) !void {
    inline for (std.meta.fields(@TypeOf(want))) |f| {
        const a = @field(want, f.name);
        const b = @field(got, f.name);
        const info = @typeInfo(f.type);
        if (info == .pointer and info.pointer.size == .slice) {
            try testing.expectEqualSlices(info.pointer.child, a, b);
        } else {
            try testing.expectEqual(a, b);
        }
    }
}

test "the same pressing packs to the same bytes" {
    var p = try Pressed.of(testing.allocator);
    defer p.deinit();
    const first = try folio.pack(testing.allocator, &p.grammar, &p.result);
    defer testing.allocator.free(first);
    const again = try folio.pack(testing.allocator, &p.grammar, &p.result);
    defer testing.allocator.free(again);
    // Padding included. A folio that differs run to run cannot be cached,
    // diffed, or content-addressed, and the seal would be the only thing in it
    // that ever moved.
    try testing.expectEqualSlices(u8, first, again);
}

test "the same grammar pressed twice packs to the same bytes" {
    // The test above holds one `press.Result` and packs it twice, and that is
    // weaker than it reads: the tables are the same objects both times, so it
    // sees nothing that varies between *pressings*. It was green for the whole
    // life of a writer that put four bytes of uninitialized memory into every
    // automaton it wrote, because a second `asBytes` of the same literal in the
    // same process lands on the same stack slot and reads back the same
    // garbage. Eleven of thirty real grammars were not reproducible while this
    // file was passing.
    //
    // So this one presses from the grammar twice - fresh determinization,
    // fresh allocations - which is what a caller minting the same grammar in
    // two processes actually does.
    var a = try Pressed.of(testing.allocator);
    defer a.deinit();
    var b = try Pressed.of(testing.allocator);
    defer b.deinit();
    const first = try folio.pack(testing.allocator, &a.grammar, &a.result);
    defer testing.allocator.free(first);
    const again = try folio.pack(testing.allocator, &b.grammar, &b.result);
    defer testing.allocator.free(again);
    try testing.expectEqualSlices(u8, first, again);
}

test "loading copies nothing" {
    var p = try Pressed.of(testing.allocator);
    defer p.deinit();
    const bytes = try folio.pack(testing.allocator, &p.grammar, &p.result);
    defer testing.allocator.free(bytes);
    const f = try folio.open(bytes);

    // Every view is a slice of the caller's buffer. If any of these ever became
    // an allocation, this is where it would show.
    const inside = @intFromPtr(bytes.ptr);
    const end = inside + bytes.len;
    for ([_]usize{
        @intFromPtr(f.view(.group, leaf.GroupRecord).ptr),
        @intFromPtr(f.productions().ptr),
        @intFromPtr(f.nameOf(0).ptr),
        @intFromPtr(f.groupsOf(f.rowOf(0)).raw.ptr),
        @intFromPtr(f.stepsOf(0).raw.ptr),
    }) |at| {
        try testing.expect(at >= inside and at < end);
    }
}

// ── rejection: one test per way a folio can be wrong ──

fn corrupt(gpa: std.mem.Allocator, p: *const Pressed) ![]align(leaf.section_align) u8 {
    return folio.pack(gpa, &p.grammar, &p.result);
}

/// Re-seal after a mutation, so the test that follows trips the check it is
/// named for rather than stopping at the seal.
fn reseal(buf: []u8) void {
    leaf.signet.sealAt(buf, buf.len - leaf.signet.len);
}

fn entryAt(buf: []u8, k: leaf.Kind) *[leaf.entry_len]u8 {
    return buf[leaf.header_len + @intFromEnum(k) * leaf.entry_len ..][0..leaf.entry_len];
}

test "a truncated folio is refused" {
    var p = try Pressed.of(testing.allocator);
    defer p.deinit();
    const bytes = try corrupt(testing.allocator, &p);
    defer testing.allocator.free(bytes);

    // Cut in half: long enough to hold a directory, short enough that the
    // header's own length is a lie.
    const half = std.mem.alignBackward(usize, bytes.len / 2, leaf.section_align);
    try testing.expectError(leaf.Error.FolioBadLength, folio.open(bytes[0..half]));

    // And cut below the floor, where there is not even a directory.
    try testing.expectError(leaf.Error.FolioTooSmall, folio.open(bytes[0..leaf.header_len]));
}

test "wrong magic is refused" {
    var p = try Pressed.of(testing.allocator);
    defer p.deinit();
    const bytes = try corrupt(testing.allocator, &p);
    defer testing.allocator.free(bytes);
    bytes[0] = 'X';
    reseal(bytes);
    try testing.expectError(leaf.Error.FolioBadMagic, folio.open(bytes));
}

test "a future version is refused rather than half-read" {
    var p = try Pressed.of(testing.allocator);
    defer p.deinit();
    const bytes = try corrupt(testing.allocator, &p);
    defer testing.allocator.free(bytes);
    std.mem.writeInt(u16, bytes[8..10], leaf.version + 1, .little);
    reseal(bytes);
    try testing.expectError(leaf.Error.FolioBadVersion, folio.open(bytes));
}

test "a layout change under the same version is caught by the schema digest" {
    var p = try Pressed.of(testing.allocator);
    defer p.deinit();
    const bytes = try corrupt(testing.allocator, &p);
    defer testing.allocator.free(bytes);
    bytes[56] ^= 1;
    reseal(bytes);
    try testing.expectError(leaf.Error.FolioBadSchema, folio.open(bytes));
}

test "a flipped bit anywhere in the payload is caught by the seal" {
    var p = try Pressed.of(testing.allocator);
    defer p.deinit();
    const bytes = try corrupt(testing.allocator, &p);
    defer testing.allocator.free(bytes);
    // Deep in the action table, where no layout check would ever look.
    bytes[bytes.len - leaf.signet.len - 5] ^= 0x40;
    try testing.expectError(leaf.Error.FolioBadSeal, folio.open(bytes));
}

test "an offset pointing outside the file is refused" {
    var p = try Pressed.of(testing.allocator);
    defer p.deinit();
    const bytes = try corrupt(testing.allocator, &p);
    defer testing.allocator.free(bytes);
    const e = entryAt(bytes, .group);
    std.mem.writeInt(u64, e[8..16], bytes.len + 4096, .little);
    reseal(bytes);
    try testing.expectError(leaf.Error.FolioSectionOutOfBounds, folio.open(bytes));
}

test "an offset off the alignment is refused" {
    var p = try Pressed.of(testing.allocator);
    defer p.deinit();
    const bytes = try corrupt(testing.allocator, &p);
    defer testing.allocator.free(bytes);
    const e = entryAt(bytes, .group);
    const was = std.mem.readInt(u64, e[8..16], .little);
    std.mem.writeInt(u64, e[8..16], was + 4, .little);
    reseal(bytes);
    try testing.expectError(leaf.Error.FolioSectionMisaligned, folio.open(bytes));
}

test "a count that overflows its section is refused" {
    var p = try Pressed.of(testing.allocator);
    defer p.deinit();
    const bytes = try corrupt(testing.allocator, &p);
    defer testing.allocator.free(bytes);
    const e = entryAt(bytes, .group);
    std.mem.writeInt(u32, e[4..8], std.math.maxInt(u32), .little);
    reseal(bytes);
    // `count * stride` is computed in u64 precisely so this is a bounds
    // failure and not a wrap into a small, plausible length.
    try testing.expectError(leaf.Error.FolioSectionOutOfBounds, folio.open(bytes));
}

test "a count that disagrees with the header is refused" {
    var p = try Pressed.of(testing.allocator);
    defer p.deinit();
    const bytes = try corrupt(testing.allocator, &p);
    defer testing.allocator.free(bytes);
    const e = entryAt(bytes, .name);
    std.mem.writeInt(u32, e[4..8], 1, .little);
    reseal(bytes);
    try testing.expectError(leaf.Error.FolioBadCount, folio.open(bytes));
}

test "a reordered directory is refused" {
    var p = try Pressed.of(testing.allocator);
    defer p.deinit();
    const bytes = try corrupt(testing.allocator, &p);
    defer testing.allocator.free(bytes);
    var scratch: [leaf.entry_len]u8 = undefined;
    @memcpy(&scratch, entryAt(bytes, .name));
    @memcpy(entryAt(bytes, .name), entryAt(bytes, .pattern));
    @memcpy(entryAt(bytes, .pattern), &scratch);
    reseal(bytes);
    try testing.expectError(leaf.Error.FolioBadDirectory, folio.open(bytes));
}

test "a name slice that runs past the text arena is refused" {
    var p = try Pressed.of(testing.allocator);
    defer p.deinit();
    const bytes = try corrupt(testing.allocator, &p);
    defer testing.allocator.free(bytes);
    const at: usize = @intCast(std.mem.readInt(u64, entryAt(bytes, .name)[8..16], .little));
    std.mem.writeInt(u32, bytes[at + 4 ..][0..4], 1 << 20, .little);
    reseal(bytes);
    try testing.expectError(leaf.Error.FolioBadText, folio.open(bytes));
}

test "a shift naming a state that is not there is refused" {
    var p = try Pressed.of(testing.allocator);
    defer p.deinit();
    const bytes = try corrupt(testing.allocator, &p);
    defer testing.allocator.free(bytes);
    const at: usize = @intCast(std.mem.readInt(u64, entryAt(bytes, .group)[8..16], .little));
    const cell: leaf.Action = .{ .verb = .shift, .value = 1 << 20 };
    std.mem.writeInt(u32, bytes[at..][0..4], @bitCast(cell), .little);
    reseal(bytes);
    try testing.expectError(leaf.Error.FolioBadState, folio.open(bytes));
}

test "a fold naming a production that is not there is refused" {
    var p = try Pressed.of(testing.allocator);
    defer p.deinit();
    const bytes = try corrupt(testing.allocator, &p);
    defer testing.allocator.free(bytes);
    const at: usize = @intCast(std.mem.readInt(u64, entryAt(bytes, .group)[8..16], .little));
    const cell: leaf.Action = .{ .verb = .reduce, .value = 1 << 20 };
    std.mem.writeInt(u32, bytes[at..][0..4], @bitCast(cell), .little);
    reseal(bytes);
    try testing.expectError(leaf.Error.FolioBadProduction, folio.open(bytes));
}

test "a span table that goes backwards is refused" {
    var p = try Pressed.of(testing.allocator);
    defer p.deinit();
    const bytes = try corrupt(testing.allocator, &p);
    defer testing.allocator.free(bytes);
    const at: usize = @intCast(std.mem.readInt(u64, entryAt(bytes, .row_span)[8..16], .little));
    std.mem.writeInt(u32, bytes[at..][0..4], 7, .little);
    reseal(bytes);
    try testing.expectError(leaf.Error.FolioBadSpan, folio.open(bytes));
}

test "an undefined flag bit is refused rather than masked off" {
    var p = try Pressed.of(testing.allocator);
    defer p.deinit();
    const bytes = try corrupt(testing.allocator, &p);
    defer testing.allocator.free(bytes);
    const at: usize = @intCast(std.mem.readInt(u64, entryAt(bytes, .lexis)[8..16], .little));
    std.mem.writeInt(u32, bytes[at..][0..4], 1 << 9, .little);
    reseal(bytes);
    try testing.expectError(leaf.Error.FolioBadTag, folio.open(bytes));
}

test "a symbol id past the end of the symbol table is refused" {
    var p = try Pressed.of(testing.allocator);
    defer p.deinit();
    const bytes = try corrupt(testing.allocator, &p);
    defer testing.allocator.free(bytes);
    const at: usize = @intCast(std.mem.readInt(u64, entryAt(bytes, .rhs)[8..16], .little));
    std.mem.writeInt(u32, bytes[at..][0..4], 1 << 20, .little);
    reseal(bytes);
    try testing.expectError(leaf.Error.FolioBadSymbol, folio.open(bytes));
}

test "an alias index past the end of the alias table is refused" {
    var p = try Pressed.of(testing.allocator);
    defer p.deinit();
    const bytes = try corrupt(testing.allocator, &p);
    defer testing.allocator.free(bytes);
    const at: usize = @intCast(std.mem.readInt(u64, entryAt(bytes, .step)[8..16], .little));
    std.mem.writeInt(u32, bytes[at..][0..4], 1 << 20, .little);
    reseal(bytes);
    try testing.expectError(leaf.Error.FolioBadIndex, folio.open(bytes));
}

// ── fuzz: the reader against bytes nobody designed ──

/// Touch everything a consumer could reach. A folio that `open` accepted must
/// be walkable end to end without a bounds check firing, which is the whole
/// claim the accessors make by not checking anything themselves.
fn sweep(f: *const folio.Folio) void {
    var sink: usize = 0;
    for (0..f.symbolCount()) |i| {
        const s: u32 = @intCast(i);
        sink +%= f.nameOf(s).len +% f.ownerOf(s) +% @intFromEnum(f.shapeOf(s));
        sink +%= switch (f.patternOf(s) orelse .external) {
            .literal, .regex => |text| text.len,
            .external => 0,
        };
    }
    for (0..f.aliasCount()) |i| sink +%= f.aliasOf(@intCast(i)).name.len;
    for (0..f.fieldCount()) |i| sink +%= f.fieldOf(@intCast(i)).len;
    for (0..f.head.production_count) |i| {
        const refs = f.stepsOf(@intCast(i));
        sink +%= f.rhsOf(@intCast(i)).len +% refs.len();
        for (0..refs.len()) |j| sink +%= f.stepAt(refs.at(@intCast(j))).alias;
    }
    // Every state, down all three interning layers to the columns themselves,
    // because a row id that is in range and a group id that is not would pass
    // any check that stopped at the first hop.
    for (0..f.head.state_count) |i| {
        const q: u32 = @intCast(i);
        sink +%= f.completeOf(q).len;
        const groups = f.groupsOf(f.rowOf(q));
        for (0..groups.len()) |j| {
            const gp = f.groupAt(groups.at(@intCast(j)));
            const cols = f.columnsOf(gp.set);
            sink +%= gp.cell +% cols.len();
            for (0..cols.len()) |k| sink +%= cols.at(@intCast(k));
        }
    }
    for (f.odds()) |o| sink +%= o.state +% o.symbol +% o.target;
    for (f.conflicts()) |k| sink +%= f.partyOf(k).len;
    sink +%= f.frayed().len +% f.title().len +% f.extras().len +% f.supertypes().len;
    std.mem.doNotOptimizeAway(sink);
}

test "arbitrary bytes are refused, never followed" {
    var prng: std.Random.DefaultPrng = .init(0x01f0110);
    const rand = prng.random();
    const buf = try testing.allocator.alignedAlloc(u8, comptime .fromByteUnits(leaf.section_align), 8192);
    defer testing.allocator.free(buf);

    for (0..512) |round| {
        rand.bytes(buf);
        // Half the rounds wear the magic, so the run gets past the cheapest
        // rejection and into the layout checks that are worth fuzzing.
        if (round % 2 == 0) @memcpy(buf[0..leaf.magic.len], leaf.magic);
        const len = 1 + rand.uintLessThan(usize, buf.len);
        const view = buf[0..std.mem.alignBackward(usize, len, leaf.section_align)];
        if (folio.open(view)) |f| sweep(&f) else |_| {}
    }
}

test "a mutated folio is refused or walkable, never in between" {
    var p = try Pressed.of(testing.allocator);
    defer p.deinit();
    const good = try folio.pack(testing.allocator, &p.grammar, &p.result);
    defer testing.allocator.free(good);
    const buf = try testing.allocator.alignedAlloc(u8, comptime .fromByteUnits(leaf.section_align), good.len);
    defer testing.allocator.free(buf);

    var prng: std.Random.DefaultPrng = .init(0xf0110ed);
    const rand = prng.random();
    for (0..2048) |round| {
        @memcpy(buf, good);
        for (0..1 + rand.uintLessThan(usize, 8)) |_| {
            buf[rand.uintLessThan(usize, buf.len)] = rand.int(u8);
        }
        // Most rounds re-seal, because a seal that always catches the mutation
        // first would leave every layout check in here untested.
        if (round % 4 != 0) reseal(buf);
        if (folio.open(buf)) |f| sweep(&f) else |_| {}
    }
}
