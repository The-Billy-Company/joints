//! What a folio is made of, as bytes: the magic, the version, the section kinds,
//! and the fixed-width record behind each one.
//!
//! One vocabulary, spoken by both the writer and the reader, because those two
//! agreeing is the whole promise and there is nowhere else to make them agree.
//! Every section is `count * stride` bytes at an eight-aligned offset, so
//! checking one is a multiply and two comparisons rather than a parse — which is
//! what lets the reader prove the entire layout before it trusts a single byte
//! of payload.
//!
//! The records are the folio's own types and not the press's. An on-disk layout
//! that borrows an in-memory struct changes meaning the day somebody reorders a
//! field for cache reasons, and nothing says so. Here the writer converts field
//! by field, so a press-side change is a compile error in the writer instead of
//! a folio that reads back wrong.
//!
//! Integers are little-endian on disk regardless of host, which is why the
//! writer goes through `std.mem.writeInt` rather than memcpy'ing a struct. A
//! big-endian reader refuses instead of byte-swapping in place: swapping means
//! copying the tables, and not copying them is the point of the format.

const std = @import("std");
const irregex = @import("irregex");

pub const signet = irregex.signet;

pub const magic = "OTLFOLIO";

/// Bumped whenever anything below changes meaning — a new section, a new field
/// in a record, a new flag bit. The reader demands equality, so an old binary
/// refuses a new folio rather than reading the prefix it recognizes and
/// inventing the rest. That refusal is what lets `press` keep growing its IR:
/// every field it grows is a version here instead of a break.
pub const version: u16 = 1;

pub const header_len = 96;
pub const entry_len = 16;
/// Every section offset is a multiple of this, so a `u32` or a `u64` record
/// lands naturally aligned and can be viewed where it lies.
pub const section_align = 8;

/// `Head.word` when the grammar declared no word rule, and `StepRecord`'s two
/// fields when a step carries no rename and no field name. Not zero: zero is a
/// perfectly good symbol, alias, and field index.
pub const none: u32 = std.math.maxInt(u32);

/// Every way a folio can be refused. There is no partial acceptance and no
/// best-effort read: a reader either proves the whole layout or names the field
/// that stopped it.
pub const Error = error{
    /// Fewer bytes than a header and a seal. Nothing to even look at.
    FolioTooSmall,
    /// The first eight bytes are not `OTLFOLIO`. Some other file entirely.
    FolioBadMagic,
    /// Written by a different version of this format.
    FolioBadVersion,
    /// Same version number, different meaning — a record layout changed under a
    /// version somebody forgot to bump.
    FolioBadSchema,
    /// The BLAKE3 seal does not match the bytes. The only check that catches a
    /// flipped bit inside an otherwise legal field.
    FolioBadSeal,
    /// The header's own length disagrees with how many bytes there are.
    FolioBadLength,
    /// The section directory is not the fixed roster in the fixed order, or a
    /// record width is not the one this version writes.
    FolioBadDirectory,
    /// A section runs past the end of the file, or overlaps the one before it.
    FolioSectionOutOfBounds,
    /// A section does not begin on an eight-byte boundary, so its records
    /// cannot be viewed where they lie.
    FolioSectionMisaligned,
    /// A count disagrees with the header, or multiplying it by the record width
    /// overflows.
    FolioBadCount,
    /// A span table is not ascending, or its last entry is not the length of
    /// the array it indexes.
    FolioBadSpan,
    /// A symbol id past the end of the symbol table, or one on the wrong side
    /// of the terminal boundary.
    FolioBadSymbol,
    /// A state id past the end of the automaton.
    FolioBadState,
    /// A production id past the end of the production list, or a dot past the
    /// end of the production it sits in.
    FolioBadProduction,
    /// An index into the alias or field table that is past its end.
    FolioBadIndex,
    /// A name, pattern, or alias slice that runs past the text arena.
    FolioBadText,
    /// A flag bit or tag this version does not define. An unknown bit is a fact
    /// somebody meant to carry, so it fails closed rather than being masked off.
    FolioBadTag,
    /// A big-endian host. The tables would have to be copied to be read, and a
    /// copy is what this format exists to avoid.
    FolioBadEndian,
};

/// The sections, in the order they appear in the directory. A folio carries
/// every one of them exactly once and the reader checks that roster positionally,
/// so a missing section is caught by the same comparison that catches a
/// reordered one.
///
/// What is here is what a parse needs, plus what a *tree* needs to be named the
/// way tree-sitter names it: shapes, aliases, and field names are not table
/// data, but a folio that dropped them could still parse and could no longer
/// tell anyone what it parsed, which makes every `highlights.scm` in the world
/// useless against it.
///
/// What is deliberately absent is everything the press consumed on the way in —
/// step precedence and associativity, declared conflicts, precedence orderings —
/// and everything it produced as a report: the contested and frayed cells. A
/// folio is the table, not the argument that made it.
pub const Kind = enum(u16) {
    /// Every string in the grammar, run together. Names, patterns, aliases, and
    /// field names all point in here, so one bounds check covers all of them.
    text,
    /// Per symbol, its name. Byte-exact, because a node kind name that shifted
    /// is a query language that no longer matches.
    name,
    /// Per symbol; `.none` for every nonterminal.
    pattern,
    /// Per symbol. Nonterminals carry the default, which says nothing.
    lexis,
    /// Per symbol, where it stands in the tree: named, anonymous, hidden, or
    /// invented.
    shape,
    /// Per symbol, the rule a synthesized nonterminal was synthesized for.
    /// This is what stops a repeat helper from surfacing as a node name.
    owner,
    /// Hidden rules the author declared to be a category. Sorted.
    supertype,
    /// Terminals the lexer skips between tokens.
    extra,
    /// Every distinct `alias(rule, name)`, indexed by `StepRecord.alias`.
    alias,
    /// Every distinct `field(name, …)` name, indexed by `StepRecord.field`.
    field,
    /// `rhs_off .. rhs_off + rhs_len` locates the body in `rhs`.
    production,
    rhs,
    /// Parallel to `rhs`, one per symbol of every body: what the child it
    /// produces is renamed to and filed under. A rename belongs to the use site,
    /// never to the symbol, so it has to live out here beside the position.
    step,
    /// Dense, `state_count * width`, row-major by state.
    action,
    goto_span,
    /// Every transition, terminal ones included. They are not redundant with the
    /// shifts in `action`: precedence can delete a read from a state that still
    /// has the edge, and anything that wants to know what the automaton *could*
    /// have done needs the edge rather than the verdict.
    goto_edge,
    complete_span,
    /// Per state, the productions whose dot has reached the end there.
    complete,
    kernel_span,
    /// Per state, the items that identify it. Two states are the same state
    /// exactly when these match, so this is what makes an automaton in a file
    /// checkable against one in memory.
    kernel,
};

pub const kind_count = std.enums.values(Kind).len;

/// How a terminal recognizes itself. `external` means a scanner we do not have,
/// and it stays a distinct case rather than becoming `none` so a consumer can
/// refuse to lex rather than silently skipping the token.
pub const PatternKind = enum(u32) { none, literal, regex, external };

/// Where a symbol stands in the tree. Same four cases as the press, spelled
/// again here because this is the on-disk meaning of the number.
pub const ShapeKind = enum(u32) { named, anonymous, hidden, invented };

/// A slice of the text arena.
pub const Span = extern struct {
    off: u32,
    len: u32,
};

/// Lexis, flattened. Bit 0 is `token.immediate`; every other bit is reserved and
/// must be zero, so a lexical fact added later cannot be silently dropped by a
/// reader that predates it.
pub const LexisRecord = extern struct {
    flags: u32,
    prec: i32,

    pub const immediate: u32 = 1;
    pub const known: u32 = immediate;
};

pub const PatternRecord = extern struct {
    kind: u32,
    off: u32,
    len: u32,
};

/// An alias plus whether the name it installs counts as named. The flag is not
/// derivable from the name — `alias($.x, 'y')` and `alias($.x, '(')` differ only
/// by the author's say-so.
pub const AliasRecord = extern struct {
    off: u32,
    len: u32,
    named: u32,
};

pub const ProductionRecord = extern struct {
    lhs: u32,
    rhs_off: u32,
    rhs_len: u32,
};

pub const StepRecord = extern struct {
    alias: u32,
    field: u32,
};

pub const EdgeRecord = extern struct {
    symbol: u32,
    target: u32,
};

pub const ItemRecord = extern struct {
    prod: u32,
    dot: u32,
};

/// What a state does on a terminal, in the folio's own encoding.
///
/// Bit-identical to what the press decides, and a separate type on purpose:
/// this one is a promise about a file, and the writer's `switch` over the
/// press's verdicts is where a new one has to be spelled out rather than
/// arriving as a number nobody noticed.
pub const Action = packed struct(u32) {
    verb: Verb,
    /// Target state for a read, production index for a fold, zero otherwise.
    value: u30,

    pub const Verb = enum(u2) { err, shift, reduce, accept };
};

pub fn Record(comptime k: Kind) type {
    return switch (k) {
        .text => u8,
        .owner, .supertype, .extra, .rhs, .goto_span, .complete_span, .complete, .kernel_span => u32,
        .shape => ShapeKind,
        .name, .field => Span,
        .action => Action,
        .pattern => PatternRecord,
        .lexis => LexisRecord,
        .alias => AliasRecord,
        .production => ProductionRecord,
        .step => StepRecord,
        .goto_edge => EdgeRecord,
        .kernel => ItemRecord,
    };
}

const strides = blk: {
    var out: [kind_count]u16 = undefined;
    for (std.enums.values(Kind)) |k| out[@intFromEnum(k)] = @sizeOf(Record(k));
    break :blk out;
};

pub fn strideOf(k: Kind) u16 {
    return strides[@intFromEnum(k)];
}

/// One directory row: what a section is, how wide its records are, how many
/// there are, and where they start. The byte length is `count * stride` and is
/// not stored, because a stored length is a second opinion that can disagree.
pub const Entry = struct {
    kind: Kind,
    stride: u16,
    count: u32,
    offset: u64,

    pub fn write(e: Entry, buf: *[entry_len]u8) void {
        std.mem.writeInt(u16, buf[0..2], @intFromEnum(e.kind), .little);
        std.mem.writeInt(u16, buf[2..4], e.stride, .little);
        std.mem.writeInt(u32, buf[4..8], e.count, .little);
        std.mem.writeInt(u64, buf[8..16], e.offset, .little);
    }

    /// Refuses an out-of-range kind rather than masking it onto a legal one,
    /// because a folded tag is a wrong answer and the point is to have none.
    pub fn parse(buf: *const [entry_len]u8) Error!Entry {
        const raw = std.mem.readInt(u16, buf[0..2], .little);
        if (raw >= kind_count) return Error.FolioBadDirectory;
        return .{
            .kind = @enumFromInt(raw),
            .stride = std.mem.readInt(u16, buf[2..4], .little),
            .count = std.mem.readInt(u32, buf[4..8], .little),
            .offset = std.mem.readInt(u64, buf[8..16], .little),
        };
    }
};

/// The fixed part, which every later question is asked against.
pub const Head = struct {
    version: u16,
    section_count: u16,
    symbol_count: u32,
    terminal_count: u32,
    state_count: u32,
    /// Columns per action row: every terminal plus the synthetic end column.
    width: u32,
    /// Which column that end-of-input is. A parser cannot ask the table
    /// anything without it and it is not recoverable from the rest.
    end: u32,
    production_count: u32,
    start: u32,
    word: u32,
    /// How many rounds the press unfolded to separate merged lookaheads. Pure
    /// provenance: nothing reads it back and a folio that lost it would still
    /// parse. It is here because it is the difference between a table that
    /// needed the loop and one that did not, and that is worth a word.
    unfolded: u32,
    title: Span,
    schema: signet.Signet,
    file_len: u64,

    pub fn write(h: Head, buf: *[header_len]u8) void {
        @memcpy(buf[0..magic.len], magic);
        std.mem.writeInt(u16, buf[8..10], h.version, .little);
        std.mem.writeInt(u16, buf[10..12], h.section_count, .little);
        std.mem.writeInt(u32, buf[12..16], h.symbol_count, .little);
        std.mem.writeInt(u32, buf[16..20], h.terminal_count, .little);
        std.mem.writeInt(u32, buf[20..24], h.state_count, .little);
        std.mem.writeInt(u32, buf[24..28], h.width, .little);
        std.mem.writeInt(u32, buf[28..32], h.end, .little);
        std.mem.writeInt(u32, buf[32..36], h.production_count, .little);
        std.mem.writeInt(u32, buf[36..40], h.start, .little);
        std.mem.writeInt(u32, buf[40..44], h.word, .little);
        std.mem.writeInt(u32, buf[44..48], h.unfolded, .little);
        std.mem.writeInt(u32, buf[48..52], h.title.off, .little);
        std.mem.writeInt(u32, buf[52..56], h.title.len, .little);
        @memcpy(buf[56..88], &h.schema.bytes);
        std.mem.writeInt(u64, buf[88..header_len], h.file_len, .little);
    }

    pub fn parse(buf: *const [header_len]u8) Head {
        var out: Head = .{
            .version = std.mem.readInt(u16, buf[8..10], .little),
            .section_count = std.mem.readInt(u16, buf[10..12], .little),
            .symbol_count = std.mem.readInt(u32, buf[12..16], .little),
            .terminal_count = std.mem.readInt(u32, buf[16..20], .little),
            .state_count = std.mem.readInt(u32, buf[20..24], .little),
            .width = std.mem.readInt(u32, buf[24..28], .little),
            .end = std.mem.readInt(u32, buf[28..32], .little),
            .production_count = std.mem.readInt(u32, buf[32..36], .little),
            .start = std.mem.readInt(u32, buf[36..40], .little),
            .word = std.mem.readInt(u32, buf[40..44], .little),
            .unfolded = std.mem.readInt(u32, buf[44..48], .little),
            .title = .{
                .off = std.mem.readInt(u32, buf[48..52], .little),
                .len = std.mem.readInt(u32, buf[52..56], .little),
            },
            .schema = undefined,
            .file_len = std.mem.readInt(u64, buf[88..header_len], .little),
        };
        @memcpy(&out.schema.bytes, buf[56..88]);
        return out;
    }
};

/// What this version's layout actually is, spelled out so two versions that
/// forgot to differ in their version number still differ here.
///
/// Derived from the record types rather than restated beside them, so adding a
/// field to `ProductionRecord` changes the digest whether or not the person
/// adding it remembers what a digest is for.
pub const schema_preimage = blk: {
    @setEvalBranchQuota(20_000);
    var out: []const u8 = magic ++ std.fmt.comptimePrint("/v{d}", .{version});
    for (std.enums.values(Kind)) |k| out = out ++ ";" ++ @tagName(k) ++ "=" ++ spell(Record(k));
    break :blk out ++ ";";
};

pub fn schema() signet.Signet {
    return signet.of(.schema, schema_preimage);
}

fn spell(comptime T: type) []const u8 {
    return switch (@typeInfo(T)) {
        .int => |i| std.fmt.comptimePrint("{c}{d}", .{
            @as(u8, if (i.signedness == .signed) 'i' else 'u'),
            i.bits,
        }),
        .@"enum" => |e| "enum" ++ spell(e.tag_type),
        .@"struct" => |s| blk: {
            var out: []const u8 = "{";
            for (s.fields) |f| out = out ++ f.name ++ ":" ++ spell(f.type) ++ ",";
            break :blk out ++ "}";
        },
        else => @compileError("no folio spelling for " ++ @typeName(T)),
    };
}

/// `n` rounded up to the next section boundary.
pub fn align8(n: u64) u64 {
    return (n + section_align - 1) & ~@as(u64, section_align - 1);
}

const testing = std.testing;

test "the schema digest is a function of the layout and names every section" {
    try testing.expect(schema().eql(schema()));
    for (std.enums.values(Kind)) |k| {
        try testing.expect(std.mem.indexOf(u8, schema_preimage, @tagName(k)) != null);
    }
    // And of the fields inside a record, not just the section roster.
    try testing.expect(std.mem.indexOf(u8, schema_preimage, "rhs_off:u32") != null);
}

test "a directory row round-trips, and a wild kind is refused rather than folded" {
    var buf: [entry_len]u8 = undefined;
    const e: Entry = .{ .kind = .action, .stride = 4, .count = 1234, .offset = 4096 };
    e.write(&buf);
    const back = try Entry.parse(&buf);
    try testing.expectEqual(e.kind, back.kind);
    try testing.expectEqual(e.stride, back.stride);
    try testing.expectEqual(e.count, back.count);
    try testing.expectEqual(e.offset, back.offset);

    std.mem.writeInt(u16, buf[0..2], kind_count, .little);
    try testing.expectError(Error.FolioBadDirectory, Entry.parse(&buf));
}

test "a header round-trips through its own bytes" {
    var buf: [header_len]u8 = undefined;
    const h: Head = .{
        .version = version,
        .section_count = kind_count,
        .symbol_count = 9,
        .terminal_count = 4,
        .state_count = 11,
        .width = 5,
        .end = 4,
        .production_count = 7,
        .start = 4,
        .word = none,
        .unfolded = 2,
        .title = .{ .off = 3, .len = 4 },
        .schema = schema(),
        .file_len = 8192,
    };
    h.write(&buf);
    try testing.expectEqualStrings(magic, buf[0..magic.len]);
    const back = Head.parse(&buf);
    try testing.expectEqual(h.symbol_count, back.symbol_count);
    try testing.expectEqual(h.end, back.end);
    try testing.expectEqual(h.word, back.word);
    try testing.expectEqual(h.title.off, back.title.off);
    try testing.expectEqual(h.file_len, back.file_len);
    try testing.expect(h.schema.eql(back.schema));
}

test "every section's stride is the width of the record it carries" {
    try testing.expectEqual(@as(u16, 1), strideOf(.text));
    try testing.expectEqual(@as(u16, 4), strideOf(.action));
    try testing.expectEqual(@as(u16, 8), strideOf(.goto_edge));
    try testing.expectEqual(@as(u16, 12), strideOf(.production));
    // Nothing is padded, or the on-disk size would depend on the host's ABI.
    try testing.expectEqual(@as(usize, 12), @sizeOf(PatternRecord));
    try testing.expectEqual(@as(usize, 8), @sizeOf(LexisRecord));
    try testing.expectEqual(@as(usize, 8), @sizeOf(Span));
}

test "the action encoding is the one the press decides" {
    const a: Action = .{ .verb = .reduce, .value = 300 };
    const raw: u32 = @bitCast(a);
    const back: Action = @bitCast(raw);
    try testing.expectEqual(Action.Verb.reduce, back.verb);
    try testing.expectEqual(@as(u30, 300), back.value);
    // The verb is the low two bits, which is what makes a raw cell readable
    // without knowing the struct.
    try testing.expectEqual(@as(u32, 2), raw & 3);
}
