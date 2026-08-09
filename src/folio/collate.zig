//! The reader: bytes in, a folio you can ask questions of, or a named refusal.
//!
//! `open` proves the whole file before it answers anything - magic, version,
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
const press = @import("../press/press.zig");

pub const Error = leaf.Error;

/// A pattern as the folio spells it. Same three cases as the press, and `null`
/// for a nonterminal, which is a different fact from `.external`.
pub const Pattern = union(enum) {
    literal: []const u8,
    regex: []const u8,
    external,
};

pub const Alias = struct { name: []const u8, named: bool };

/// A run of bare ids at whatever width this file writes them.
///
/// Two widths and no third, so `at` is one predictable branch; the alternative
/// was a `[]const u16` and a `[]const u32` in a union at every call site, which
/// is the same branch spelled by the caller.
pub const Ids = struct {
    raw: []const u8,
    stride: u8,

    pub fn len(x: Ids) u32 {
        return @intCast(x.raw.len / x.stride);
    }

    pub fn at(x: Ids, i: u32) u32 {
        const off = i * x.stride;
        return if (x.stride == 2)
            std.mem.readInt(u16, x.raw[off..][0..2], .little)
        else
            std.mem.readInt(u32, x.raw[off..][0..4], .little);
    }

    fn cut(x: Ids, off: u32, n: u32) Ids {
        return .{ .raw = x.raw[off * x.stride ..][0 .. n * x.stride], .stride = x.stride };
    }
};

/// A verified folio. Three fields, because everything else is a view computed
/// from the directory on demand - a slice is a pointer add and a length, and
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

    /// Which step each child of this production takes. A rename belongs to the
    /// use site, so it is indexed the same way the body is rather than hung on
    /// the symbol; the steps themselves are interned, because a grammar has far
    /// more positions than it has distinct things to say about them.
    pub fn stepsOf(f: *const Folio, prod: u32) Ids {
        const p = f.productions()[prod];
        return f.ids(.stepref).cut(p.rhs_off, p.rhs_len);
    }

    pub fn stepAt(f: *const Folio, id: u32) leaf.StepRecord {
        return f.view(.step, leaf.StepRecord)[id];
    }

    // ── the table ──

    /// Columns in a row: a column per terminal, one for end of input, then one
    /// per nonterminal. The last stretch is where the gotos live.
    pub fn columnCount(f: *const Folio) u32 {
        return f.head.width + (f.head.symbol_count - f.head.terminal_count);
    }

    /// Which symbol a column past the terminals is about. Undefined below
    /// `width`, where a column is its own terminal and the end marker has no
    /// symbol at all.
    pub fn symbolAt(f: *const Folio, column: u32) u32 {
        return column - f.head.width + f.head.terminal_count;
    }

    pub fn rowOf(f: *const Folio, state: u32) u32 {
        return f.view(.row, u32)[state];
    }

    pub fn rowCount(f: *const Folio) u32 {
        return f.dir[@intFromEnum(leaf.Kind.row_span)].count - 1;
    }

    /// The groups a row is made of, ascending by id.
    pub fn groupsOf(f: *const Folio, row: u32) Ids {
        return f.run(.row_span, .groupref, row);
    }

    pub fn groupAt(f: *const Folio, id: u32) leaf.GroupRecord {
        return f.view(.group, leaf.GroupRecord)[id];
    }

    /// The columns one group covers, ascending.
    pub fn columnsOf(f: *const Folio, set: u32) Ids {
        return f.run(.set_span, .setsym, set);
    }

    /// Every transition the rows do not already imply, sorted by state and
    /// then by symbol. Small: on real grammars this is under a percent of the
    /// edges, which is the whole reason the rest are derived.
    pub fn odds(f: *const Folio) []const leaf.OddRecord {
        return f.view(.odd, leaf.OddRecord);
    }

    pub fn completeOf(f: *const Folio, state: u32) []const u32 {
        return f.span(.complete_span, .complete, u32, state);
    }

    /// Every cell the grammar left contested. The `declared` ones are what a
    /// parse forks at; the rest are the honest measure of what it cost.
    pub fn conflicts(f: *const Folio) []const leaf.ConflictRecord {
        return f.view(.conflict, leaf.ConflictRecord);
    }

    /// The rules party to one conflict, sorted and deduplicated.
    pub fn partyOf(f: *const Folio, k: leaf.ConflictRecord) []const u32 {
        return f.view(.party, u32)[k.party_off..][0..k.party_len];
    }

    /// The readings this cell dropped behind `other`, as packed action cells.
    /// Empty is the common answer: an ambiguity has to be at least three ways
    /// before there is a third reading to carry.
    pub fn rivalsOf(f: *const Folio, k: leaf.ConflictRecord) []const u32 {
        return f.view(.rival, u32)[k.rival_off..][0..k.rival_len];
    }

    pub fn frayed(f: *const Folio) []const leaf.FrayedRecord {
        return f.view(.frayed, leaf.FrayedRecord);
    }

    /// The determinized slate, as bytes nobody here interprets. Empty is a
    /// normal answer and means the lexer builds its own.
    pub fn lexicon(f: *const Folio) []const u8 {
        return f.view(.lexicon, u8);
    }

    /// The compiled query programs, as bytes nobody here interprets. Empty is
    /// the normal answer and means the folio was minted without a query.
    ///
    /// Raw bytes rather than a parsed view, and unlike `quotient` the interior
    /// is *not* checked at `open`. That is a fact about the topology and not a
    /// gap: `press/quotient.zig` sits below this file, so `open` can ask it
    /// whether a class map fits, whereas the query program's codec is
    /// `kernel/gloss/stencil.zig`, which stands *above* `folio` and reads it.
    /// Asking upward is the one thing `charter.zone` forbids outright, and
    /// restating the layout down here to dodge that would put the same format
    /// in two files - the exact drift the byte-opaque reservation was for.
    ///
    /// So the doubt is delegated the other way, to the reader: `stencil.read`
    /// is fail-closed and returns null for a program it cannot account for,
    /// having bounds-checked every table and every span against the section it
    /// was handed. The posture is `lexicon`'s, for a related reason.
    pub fn gloss(f: *const Folio) []const u8 {
        return f.view(.gloss, u8);
    }

    /// This grammar's scanner, as the bytes `customary/book.zig` proves. Empty is
    /// the normal answer for most grammars and means the externals this grammar
    /// declares have no answer here - the `awaited_external` wall, honestly.
    ///
    /// Aligned, where `gloss` and `lexicon` are not, because the book is read
    /// where it lies: its rows are `extern struct`s viewed straight out of the
    /// mapping, so eight is a precondition rather than a preference. `open` has
    /// already proved every section offset is a multiple of eight and that the
    /// buffer is, which is what makes the cast sound - the same argument `view`
    /// makes, spelled out here because this accessor bypasses it to keep the
    /// alignment in the type.
    ///
    /// The interior is unchecked at `open`, for the topology reason `gloss`
    /// states at length: the codec is `kernel/lex/`'s and stands above `folio`.
    /// `book.read` is the fail-closed reader that carries the doubt.
    pub fn customary(f: *const Folio) []align(leaf.section_align) const u8 {
        const e = f.dir[@intFromEnum(leaf.Kind.customary)];
        const off: usize = @intCast(e.offset);
        return @alignCast(f.bytes[off..][0..@as(usize, e.count)]);
    }

    /// Which states no parse can tell apart, as the class map `press` wrote.
    ///
    /// Null means the folio carries none, which is a normal answer for the same
    /// reason an empty `lexicon` is: the relation is a pure function of the
    /// table, so a caller that wants one can press it out again. A map that is
    /// present and does not fit never reaches here - `open` refused the file.
    pub fn quotient(f: *const Folio) ?press.quotient.Classes {
        const raw = f.view(.quotient, u8);
        if (raw.len == 0) return null;
        return press.quotient.classes(raw, f.head.state_count);
    }

    // ── the views themselves ──

    /// Records where they lie. The `@alignCast` is sound because `open` proved
    /// every section offset is a multiple of eight and the buffer itself is,
    /// and no record here wants more than eight.
    pub fn view(f: *const Folio, comptime k: leaf.Kind, comptime T: type) []const T {
        comptime std.debug.assert(!leaf.narrow(k));
        comptime std.debug.assert(@alignOf(T) <= leaf.section_align);
        comptime std.debug.assert(@sizeOf(T) == leaf.strideOf(k));
        const e = f.dir[@intFromEnum(k)];
        const off: usize = @intCast(e.offset);
        const raw = f.bytes[off..][0 .. @as(usize, e.count) * @sizeOf(T)];
        return std.mem.bytesAsSlice(T, @as([]align(@alignOf(T)) const u8, @alignCast(raw)));
    }

    /// A narrow section's bytes, still where they lie.
    pub fn ids(f: *const Folio, comptime k: leaf.Kind) Ids {
        comptime std.debug.assert(leaf.narrow(k));
        const e = f.dir[@intFromEnum(k)];
        const off: usize = @intCast(e.offset);
        return .{
            .raw = f.bytes[off..][0 .. @as(usize, e.count) * e.stride],
            .stride = @intCast(e.stride),
        };
    }

    /// One entry's slice of a narrow section, by its span table.
    fn run(f: *const Folio, comptime spans: leaf.Kind, comptime items: leaf.Kind, i: u32) Ids {
        const table = f.view(spans, u32);
        return f.ids(items).cut(table[i], table[i + 1] - table[i]);
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
        // one are the same comparison. A narrow section is the one place the
        // width is the file's to choose, and it chooses between exactly two.
        if (e.kind != k) return Error.FolioBadDirectory;
        if (leaf.narrow(k)) {
            if (e.stride != 2 and e.stride != 4) return Error.FolioBadDirectory;
        } else if (e.stride != leaf.strideOf(k)) return Error.FolioBadDirectory;
        // A section this binary reserves but cannot read, with records in it. The
        // version and the schema both matched, because a reserved section is
        // byte-opaque and filling one changes neither - which is exactly what
        // makes this the only check that can catch it. See `leaf.reserved`.
        if (leaf.reserved(k) and e.count != 0) return Error.FolioReservedSection;
        if (e.offset % leaf.section_align != 0) return Error.FolioSectionMisaligned;
        if (e.offset < at) return Error.FolioSectionOutOfBounds;
        const end = e.offset + @as(u64, e.count) * e.stride;
        if (end > payload) return Error.FolioSectionOutOfBounds;
        at = leaf.align8(end);
        f.dir[i] = e;
    }
    try audit.counts(&f);
    try audit.contents(&f);
    // The class map, against the automaton it claims to partition. Here rather
    // than in `audit` because the section is byte-opaque and its interior is
    // `press/quotient.zig`'s, so this is the one doubt `open` delegates. A map
    // that is present and does not fit is a map for some other automaton, which
    // is `FolioBadState` in every way that matters: every id in it is a claim
    // about a state of this one.
    if (f.view(.quotient, u8).len != 0 and f.quotient() == null) return Error.FolioBadState;
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
