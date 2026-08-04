//! The reader: bytes in, a folio you can ask questions of, or a named refusal.
//!
//! `open` proves the whole file before it answers anything — magic, version,
//! schema, seal, then every section's place in the layout, then every id and
//! every span inside them. After that the accessors below do no checking at all,
//! because there is nothing left to check; a `nameOf` is two loads and a slice.
//!
//! Nothing is copied. Every accessor returns a view into the caller's bytes, so
//! a folio can be mmap'd and used, and the parse pays for the pages it touches
//! and no others. That is the reason the format exists, so `open` is written to
//! make it safe rather than to make it fast: it is the only place that ever
//! doubts the file, and it doubts everything.
//!
//! The one thing `open` does NOT do is tolerate. There is no "recognized prefix"
//! path and no field it will skip: a folio a future version could half-read is
//! worse than one it refuses, because the half-read one produces a tree that
//! looks fine and is wrong.

const std = @import("std");
const builtin = @import("builtin");
const leaf = @import("leaf.zig");
const audit = @import("audit.zig");

pub const Error = leaf.Error;

/// A pattern as the folio spells it. Same three cases as the press, and `null`
/// for a nonterminal, which is a different fact from `.external`.
pub const Pattern = union(enum) {
    literal: []const u8,
    regex: []const u8,
    external,
};

pub const Alias = struct { name: []const u8, named: bool };

/// A verified folio. Three fields, because everything else is a view computed
/// from the directory on demand — a slice is a pointer add and a length, and
/// caching twenty of them would only be a second copy of the truth.
pub const Folio = struct {
    bytes: []align(leaf.section_align) const u8,
    head: leaf.Head,
    dir: [leaf.kind_count]leaf.Entry,

    // ── the grammar's vocabulary ──

    pub fn title(f: *const Folio) []const u8 {
        return f.slice(f.head.title);
    }

    pub fn symbolCount(f: *const Folio) u32 {
        return f.head.symbol_count;
    }

    pub fn isTerminal(f: *const Folio, sym: u32) bool {
        return sym < f.head.terminal_count;
    }

    /// Byte-exact, which is the whole compatibility story: every
    /// `highlights.scm` in the world is keyed on these bytes.
    pub fn nameOf(f: *const Folio, sym: u32) []const u8 {
        return f.slice(f.view(.name, leaf.Span)[sym]);
    }

    pub fn patternOf(f: *const Folio, sym: u32) ?Pattern {
        const rec = f.view(.pattern, leaf.PatternRecord)[sym];
        const spelling: leaf.Span = .{ .off = rec.off, .len = rec.len };
        return switch (@as(leaf.PatternKind, @enumFromInt(rec.kind))) {
            .none => null,
            .literal => .{ .literal = f.slice(spelling) },
            .regex => .{ .regex = f.slice(spelling) },
            .external => .external,
        };
    }

    pub fn lexisOf(f: *const Folio, sym: u32) leaf.LexisRecord {
        return f.view(.lexis, leaf.LexisRecord)[sym];
    }

    pub fn shapeOf(f: *const Folio, sym: u32) leaf.ShapeKind {
        return f.view(.shape, leaf.ShapeKind)[sym];
    }

    /// The rule a synthesized nonterminal was synthesized for. Every other
    /// symbol owns itself.
    pub fn ownerOf(f: *const Folio, sym: u32) u32 {
        return f.view(.owner, u32)[sym];
    }

    pub fn supertypes(f: *const Folio) []const u32 {
        return f.view(.supertype, u32);
    }

    pub fn extras(f: *const Folio) []const u32 {
        return f.view(.extra, u32);
    }

    pub fn aliasCount(f: *const Folio) u32 {
        return f.dir[@intFromEnum(leaf.Kind.alias)].count;
    }

    pub fn aliasOf(f: *const Folio, i: u32) Alias {
        const rec = f.view(.alias, leaf.AliasRecord)[i];
        return .{ .name = f.slice(.{ .off = rec.off, .len = rec.len }), .named = rec.named != 0 };
    }

    pub fn fieldCount(f: *const Folio) u32 {
        return f.dir[@intFromEnum(leaf.Kind.field)].count;
    }

    pub fn fieldOf(f: *const Folio, i: u32) []const u8 {
        return f.slice(f.view(.field, leaf.Span)[i]);
    }

    /// The terminal a keyword is spelled as before anyone knows it is a
    /// keyword. Null when the grammar declared no word rule.
    pub fn word(f: *const Folio) ?u32 {
        return if (f.head.word == leaf.none) null else f.head.word;
    }

    // ── the productions ──

    pub fn productions(f: *const Folio) []const leaf.ProductionRecord {
        return f.view(.production, leaf.ProductionRecord);
    }

    pub fn rhsOf(f: *const Folio, prod: u32) []const u32 {
        const p = f.productions()[prod];
        return f.view(.rhs, u32)[p.rhs_off..][0..p.rhs_len];
    }

    /// What each child of this production is renamed to and filed under. A
    /// rename belongs to the use site, so it is indexed the same way the body
    /// is rather than hung on the symbol.
    pub fn stepsOf(f: *const Folio, prod: u32) []const leaf.StepRecord {
        const p = f.productions()[prod];
        return f.view(.step, leaf.StepRecord)[p.rhs_off..][0..p.rhs_len];
    }

    // ── the table ──

    /// The whole dense table. Hoist this out of a parse loop; `at` is for the
    /// one-off question.
    pub fn actions(f: *const Folio) []const leaf.Action {
        return f.view(.action, leaf.Action);
    }

    pub fn at(f: *const Folio, state: u32, terminal: u32) leaf.Action {
        return f.actions()[state * f.head.width + terminal];
    }

    pub fn edgesOf(f: *const Folio, state: u32) []const leaf.EdgeRecord {
        return f.span(.goto_span, .goto_edge, leaf.EdgeRecord, state);
    }

    /// Where a symbol takes this state, terminal or not. Binary search, because
    /// the writer keeps edges sorted the way the press does.
    pub fn gotoOf(f: *const Folio, state: u32, symbol: u32) ?u32 {
        const edges = f.edgesOf(state);
        var lo: usize = 0;
        var hi: usize = edges.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (edges[mid].symbol < symbol) lo = mid + 1 else hi = mid;
        }
        return if (lo < edges.len and edges[lo].symbol == symbol) edges[lo].target else null;
    }

    pub fn completeOf(f: *const Folio, state: u32) []const u32 {
        return f.span(.complete_span, .complete, u32, state);
    }

    /// The items that identify a state. Two states are the same state exactly
    /// when these match, so this is what lets an automaton in a file be checked
    /// against one in memory.
    pub fn kernelOf(f: *const Folio, state: u32) []const leaf.ItemRecord {
        return f.span(.kernel_span, .kernel, leaf.ItemRecord, state);
    }

    // ── the views themselves ──

    /// Records where they lie. The `@alignCast` is sound because `open` proved
    /// every section offset is a multiple of eight and the buffer itself is,
    /// and no record here wants more than eight.
    pub fn view(f: *const Folio, comptime k: leaf.Kind, comptime T: type) []const T {
        comptime std.debug.assert(@alignOf(T) <= leaf.section_align);
        comptime std.debug.assert(@sizeOf(T) == leaf.strideOf(k));
        const e = f.dir[@intFromEnum(k)];
        const off: usize = @intCast(e.offset);
        const raw = f.bytes[off..][0 .. @as(usize, e.count) * @sizeOf(T)];
        return std.mem.bytesAsSlice(T, @as([]align(@alignOf(T)) const u8, @alignCast(raw)));
    }

    fn span(
        f: *const Folio,
        comptime spans: leaf.Kind,
        comptime items: leaf.Kind,
        comptime T: type,
        i: u32,
    ) []const T {
        const table = f.view(spans, u32);
        return f.view(items, T)[table[i]..table[i + 1]];
    }

    fn slice(f: *const Folio, s: leaf.Span) []const u8 {
        return f.view(.text, u8)[s.off..][0..s.len];
    }
};

/// Prove these bytes are a folio, or name what stopped you.
///
/// The buffer must be eight-aligned, which every mmap and every `pack` result
/// already is; a `[]u8` off a general allocator is not, and that is a caller
/// bug rather than a corrupt file, so it is a compile-time requirement in the
/// signature instead of a runtime error.
pub fn open(bytes: []align(leaf.section_align) const u8) Error!Folio {
    if (builtin.cpu.arch.endian() != .little) return Error.FolioBadEndian;

    // Magic before size, so a file that is simply something else says so
    // instead of being described as a folio that got cut short.
    if (bytes.len < leaf.magic.len) return Error.FolioTooSmall;
    if (!std.mem.eql(u8, bytes[0..leaf.magic.len], leaf.magic)) return Error.FolioBadMagic;
    const floor = leaf.header_len + leaf.kind_count * leaf.entry_len + leaf.signet.len;
    if (bytes.len < floor) return Error.FolioTooSmall;

    const head = leaf.Head.parse(bytes[0..leaf.header_len]);
    if (head.version != leaf.version) return Error.FolioBadVersion;
    if (!head.schema.eql(leaf.schema())) return Error.FolioBadSchema;
    if (head.file_len != bytes.len) return Error.FolioBadLength;
    if (head.section_count != leaf.kind_count) return Error.FolioBadDirectory;

    // Before anything downstream believes a count. A torn write inside a
    // perfectly legal-looking field is the failure the layout checks cannot
    // see, and it is the common one: a folio is written once and read forever.
    leaf.signet.verify(bytes) catch return Error.FolioBadSeal;

    var f: Folio = .{ .bytes = bytes, .head = head, .dir = undefined };
    const payload = bytes.len - leaf.signet.len;
    var at: u64 = leaf.align8(leaf.header_len + leaf.kind_count * leaf.entry_len);
    for (std.enums.values(leaf.Kind), 0..) |k, i| {
        const e = try leaf.Entry.parse(bytes[leaf.header_len + i * leaf.entry_len ..][0..leaf.entry_len]);
        // Positional: the roster is fixed, so a missing section and a reordered
        // one are the same comparison.
        if (e.kind != k or e.stride != leaf.strideOf(k)) return Error.FolioBadDirectory;
        if (e.offset % leaf.section_align != 0) return Error.FolioSectionMisaligned;
        if (e.offset < at) return Error.FolioSectionOutOfBounds;
        const end = e.offset + @as(u64, e.count) * e.stride;
        if (end > payload) return Error.FolioSectionOutOfBounds;
        at = leaf.align8(end);
        f.dir[i] = e;
    }
    try audit.counts(&f);
    try audit.contents(&f);
    return f;
}

const testing = std.testing;

test "a real magic on a buffer too short to hold a directory is too small, not bad magic" {
    var short: [leaf.header_len]u8 align(leaf.section_align) = @splat(0);
    @memcpy(short[0..leaf.magic.len], leaf.magic);
    try testing.expectError(Error.FolioTooSmall, open(&short));
}

test "a buffer shorter than the magic itself is too small" {
    const stub: [2]u8 align(leaf.section_align) = .{ 'o', 'u' };
    try testing.expectError(Error.FolioTooSmall, open(&stub));
}

test "a big enough buffer of zeros is refused for its magic" {
    var buf: [4096]u8 align(leaf.section_align) = @splat(0);
    try testing.expectError(Error.FolioBadMagic, open(&buf));
}
