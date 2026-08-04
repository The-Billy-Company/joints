//! The gate that guards the format: press, pack, load, and compare field by
//! field — then break the bytes on purpose, one failure mode at a time, and
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
//! what a determined corrupter — or an older writer — would do anyway, which is
//! precisely the case the layout checks exist for.

const std = @import("std");
const folio = @import("folio.zig");
const leaf = @import("leaf.zig");
const g = @import("../press/grammar.zig");
const press = @import("../press/press.zig");

const testing = std.testing;

/// A grammar small enough to check by hand and rich enough to exercise every
/// section: two literal terminals, a regex, an external, an immediate token
/// with a lexical precedence, an extra, a word rule, a supertype, a rename, a
/// field, and a hidden rule.
fn sample(gpa: std.mem.Allocator) !g.Grammar {
    var b = g.Builder.init(gpa);
    defer b.deinit();

    const id = try b.intern("id", "identifier", .{ .regex = "[a-z]+" });
    const kw = try b.intern("kw", "let", .{ .literal = "let" });
    const eq = try b.intern("eq", "=", .{ .literal = "=" });
    const semi = try b.intern("semi", ";", .{ .literal = ";" });
    const ws = try b.intern("ws", "whitespace", .{ .regex = "\\s+" });
    const raw = try b.intern("raw", "raw_text", .external);
    b.describe(raw, .{ .immediate = true, .prec = 3 });
    b.describe(kw, .{ .prec = 1 });
    b.word = id;

    const start = try b.intern("$start", "$start", null);
    const stmt = try b.intern("stmt", "statement", null);
    const expr = try b.intern("expr", "_expression", null);
    const helper = try b.intern("helper", "statement_repeat1", null);
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
        for (prod.steps, f.stepsOf(@intCast(i))) |step, back| {
            try testing.expectEqual(step.alias orelse leaf.none, back.alias);
            try testing.expectEqual(step.field orelse leaf.none, back.field);
        }
    }

    for (0..c.states.len) |i| {
        const q: u32 = @intCast(i);
        const st = c.states[i];
        try testing.expectEqualSlices(u32, st.complete, f.completeOf(q));
        for (st.edges, f.edgesOf(q)) |want, back| {
            try testing.expectEqual(want.symbol, back.symbol);
            try testing.expectEqual(want.target, back.target);
            try testing.expectEqual(@as(?u32, want.target), f.gotoOf(q, want.symbol));
        }
        for (st.kernel, f.kernelOf(q)) |want, back| {
            try testing.expectEqual(want.prod, back.prod);
            try testing.expectEqual(want.dot, back.dot);
        }
        for (0..t.width) |col| {
            const want = t.at(q, @intCast(col));
            const back = f.at(q, @intCast(col));
            try testing.expectEqualStrings(@tagName(want.kind), @tagName(back.verb));
            try testing.expectEqual(want.value, back.value);
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
        @intFromPtr(f.actions().ptr),
        @intFromPtr(f.productions().ptr),
        @intFromPtr(f.nameOf(0).ptr),
        @intFromPtr(f.edgesOf(0).ptr),
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
    const e = entryAt(bytes, .action);
    std.mem.writeInt(u64, e[8..16], bytes.len + 4096, .little);
    reseal(bytes);
    try testing.expectError(leaf.Error.FolioSectionOutOfBounds, folio.open(bytes));
}

test "an offset off the alignment is refused" {
    var p = try Pressed.of(testing.allocator);
    defer p.deinit();
    const bytes = try corrupt(testing.allocator, &p);
    defer testing.allocator.free(bytes);
    const e = entryAt(bytes, .action);
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
    const e = entryAt(bytes, .goto_edge);
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
    const at: usize = @intCast(std.mem.readInt(u64, entryAt(bytes, .action)[8..16], .little));
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
    const at: usize = @intCast(std.mem.readInt(u64, entryAt(bytes, .action)[8..16], .little));
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
    const at: usize = @intCast(std.mem.readInt(u64, entryAt(bytes, .goto_span)[8..16], .little));
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
        sink +%= f.rhsOf(@intCast(i)).len +% f.stepsOf(@intCast(i)).len;
    }
    for (0..f.head.state_count) |i| {
        const q: u32 = @intCast(i);
        sink +%= f.edgesOf(q).len +% f.completeOf(q).len +% f.kernelOf(q).len;
        for (0..f.head.width) |col| sink +%= f.at(q, @intCast(col)).value;
    }
    sink +%= f.title().len +% f.extras().len +% f.supertypes().len;
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
