//! What a folio is made of, as bytes: the magic, the version, the section kinds,
//! and the fixed-width record behind each one.
//!
//! One vocabulary, spoken by both the writer and the reader, because those two
//! agreeing is the whole promise and there is nowhere else to make them agree.
//! Every section is `count * stride` bytes at an eight-aligned offset, so
//! checking one is a multiply and two comparisons rather than a parse - which is
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

pub const signet = irregex.index.signet;

pub const magic = "OTLFOLIO";

/// Bumped whenever anything below changes meaning - a new section, a new field
/// in a record, a new flag bit. The reader demands equality, so an old binary
/// refuses a new folio rather than reading the prefix it recognizes and
/// inventing the rest. That refusal is what lets `press` keep growing its IR:
/// every field it grows is a version here instead of a break.
pub const version: u16 = 4;

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
    /// Same version number, different meaning - a record layout changed under a
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
/// What is deliberately absent is everything the press *consumed* on the way in
/// - step precedence and associativity, declared ambiguity groups, precedence
/// orderings. A folio is the table, not the argument that made it.
///
/// `prec.dynamic` is not one of them and is carried: it is the rank the press
/// could not spend, because the cell it orders keeps both actions and the
/// choice is still open when a parse reaches it. See `ProductionRecord.rank`.
///
/// Also absent, and this one was here once: the kernel items that identify each
/// state. They are the automaton's construction identity, and no parse and no
/// tree build reads them; keeping them was carrying a second opinion about
/// what the table already says, at eight percent of the file. What a folio can
/// still be checked against a pressing by is its behaviour, which is what
/// `mint` compares and what actually has to match.
///
/// What it does carry, and did not at first, is the press's *verdict* on the
/// cells the grammar left contested. That is not provenance: a parse forks at a
/// cell the author declared ambiguous, and the reading it forks into is the one
/// the table dropped there, which exists nowhere else. A folio without it parses
/// a declaredly-ambiguous grammar as though the author had declared nothing.
///
/// The table itself is `row` through `odd`, and its shape is worth stating
/// once. A parse table written out in full is 97% cells that say nothing, and
/// the 3% that do say something say it over and over: a state, a value, and the
/// set of columns holding that value repeat across an automaton far more than
/// they vary. So each layer is stored once and pointed at - a state names a
/// row, a row names its groups, a group names a value and a column set, and a
/// column set is shared by every group that happens to have it. Terminals and
/// nonterminals share the column space, so a goto is a group like any other.
/// Nothing here is compressed; there is simply one copy of each distinct thing,
/// which is what lets it still be read where it lies.
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
    /// Parallel to `rhs`, one per symbol of every body: which step it takes. A
    /// rename belongs to the use site and never to the symbol, so it has to
    /// live out here beside the position - but a grammar has a few dozen
    /// distinct things to say and tens of thousands of positions to say them
    /// at, and almost every one of them is "nothing". Narrow: see `narrow`.
    stepref,
    /// Every distinct step, interned.
    step,
    /// Per state, which row it uses. Thousands of states share a few hundred
    /// rows in every real grammar, and this indirection is what lets them.
    row,
    /// Per row, where its groups begin in `groupref`. `rows + 1` long.
    row_span,
    /// A group id, ascending within a row. Narrow: see `narrow`.
    groupref,
    /// One thing a row says, and the columns it says it about. Interned across
    /// the whole file, because "reduce production 41 on any of these nine
    /// terminals" is a sentence hundreds of rows say verbatim.
    group,
    /// Per set, where its columns begin in `setsym`. `sets + 1` long.
    set_span,
    /// A column, ascending within a set. Narrow: see `narrow`. Columns below
    /// `width` are terminals and the end marker; the rest are nonterminals,
    /// offset by `width - terminal_count`.
    setsym,
    /// The transitions the table cannot account for. A shift cell already says
    /// where a terminal goes, so nearly every terminal edge is derivable from
    /// the row it is already written in; these are the ones where precedence or
    /// unfolding left the cell saying something else, or nothing.
    odd,
    complete_span,
    /// Per state, the productions whose dot has reached the end there.
    complete,
    /// Every cell the grammar did not determine, with what the table chose and
    /// one of the readings it dropped. Sorted by cell.
    conflict,
    /// The rules party to each conflict, run together; a `ConflictRecord` names
    /// its own slice. Deduplicated and sorted by the press, which is what makes
    /// a measured group comparable to a declared one by bytes.
    party,
    /// Cells that are only contested because one LR(0) state stands in for
    /// several LR(1) ones. A report, not a decision - but a report the press
    /// cannot reproduce from a folio, so dropping it would make a loaded
    /// grammar look cleaner than the pressed one it came from.
    frayed,
    /// The terminal slate, already determinized, deflated. Opaque here: the
    /// layout belongs to `kernel/lex/lexicon.zig` and nothing else reads it.
    ///
    /// It is the only section a reader may ignore. Everything else in the file
    /// is the grammar; this is an answer about the grammar that we could always
    /// work out again, and a folio written without it - or with one this binary
    /// does not recognize - still loads and still parses. It is here because
    /// working it out again is the whole of startup.
    lexicon,
    /// The readings each conflict dropped *past* the first, run together; a
    /// `ConflictRecord` names its own slice. Empty for every grammar whose
    /// declared ambiguities are all two-way, and the whole difference between a
    /// binary fork and a ternary one where they are not.
    ///
    /// Last because this list is the file format: a section is addressed by its
    /// ordinal, so appending is safe and inserting renames every folio already
    /// written.
    rival,
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
/// derivable from the name - `alias($.x, 'y')` and `alias($.x, '(')` differ only
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
    /// What `prec.dynamic` declared, and the only rank that survives the press.
    ///
    /// A static rank resolves a cell while the table is built, so the loser is
    /// gone before a parse begins and there is nothing to carry. A dynamic one
    /// resolves nothing: the cell keeps both actions, the parse forks, and this
    /// is the tie-break between readings that are all still alive at the end.
    /// So it is the one precedence a *loaded* grammar still needs, and without
    /// it a fork re-ranking its own versions compares zeros.
    ///
    /// Widened from the IR's `i16` rather than packed beside another field,
    /// because a record whose fields are all one word is a view into mapped
    /// bytes and not a decode.
    rank: i32,
};

pub const StepRecord = extern struct {
    alias: u32,
    field: u32,
};

/// One thing a row says: the cell, and which columns hold it.
///
/// The cell is a raw `Action` rather than the struct, because a group is also
/// how a goto is written - `shift` into the nonterminal half of the column
/// space is exactly what a goto is - and a raw word makes that one encoding
/// instead of two that have to agree.
pub const GroupRecord = extern struct {
    cell: u32,
    set: u32,
};

/// A transition that is not what the row it lives in implies.
///
/// Terminal edges are nearly all derivable: a `shift` cell says where the
/// terminal goes, and that is the edge. The exceptions are real and both
/// directions occur - precedence can delete a read from a state that still has
/// the edge, so the cell is silent where an edge exists; and unfolding can
/// leave a read whose target is not the edge's. `target` of `none` is the third
/// case, a cell that reads where the automaton has no edge at all. Anything
/// that wants to know what the automaton *could* have done needs these; the
/// verdict alone is not the same fact.
pub const OddRecord = extern struct {
    state: u32,
    symbol: u32,
    target: u32,
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

/// Which two readings collided. Same two cases as the press.
pub const ConflictKind = enum(u32) { shift_reduce, reduce_reduce };

/// Whose ambiguity a contested cell is. Only `declared` and `unwritten` change
/// what a parse does - those are the cells a reading is allowed to fork at -
/// but all four are written, because a folio that carried only the forkable
/// ones could no longer answer how much residue the grammar left.
///
/// **Append only, and the ordinals are the file format.** A class is stored as
/// its ordinal, so inserting one renames every class after it in every folio
/// already on disk. `settle.Conflict.Class` is kept in the same order for the
/// same reason, and `impose` asserts at comptime that the two agree. An older
/// binary meeting a class it has no name for refuses the file at `audit.tag`
/// rather than folding it into a neighbour, which is why appending is safe and
/// reordering is not.
pub const ConflictClass = enum(u32) { repetition, declared, residual, unwritten };

/// Which way a merged answer went in a frayed cell.
pub const Harm = enum(u32) { read_dropped, fold_dropped };

pub const ConflictRecord = extern struct {
    state: u32,
    terminal: u32,
    kind: u32,
    class: u32,
    /// The `Action` the table will take here, and one of the readings that lost.
    /// Both as raw cells, so this record stays the same width whatever the
    /// action encoding does.
    chosen: u32,
    other: u32,
    party_off: u32,
    party_len: u32,
    /// `rival_off .. rival_off + rival_len` locates the readings this cell
    /// dropped behind `other`, in `rival`. Appended, never inserted.
    rival_off: u32,
    rival_len: u32,
};

pub const FrayedRecord = extern struct {
    state: u32,
    terminal: u32,
    harm: u32,
};

pub fn Record(comptime k: Kind) type {
    return switch (k) {
        .text, .lexicon => u8,
        .owner, .supertype, .extra, .rhs, .row, .row_span, .set_span, .complete_span, .complete, .party, .rival => u32,
        .groupref, .setsym, .stepref => u32,
        .shape => ShapeKind,
        .name, .field => Span,
        .pattern => PatternRecord,
        .lexis => LexisRecord,
        .alias => AliasRecord,
        .production => ProductionRecord,
        .step => StepRecord,
        .group => GroupRecord,
        .odd => OddRecord,
        .conflict => ConflictRecord,
        .frayed => FrayedRecord,
    };
}

/// Sections whose every record is one bare id, written at the narrowest width
/// that holds the largest id in *this* file: two bytes below 65,536 of whatever
/// they index, four above.
///
/// These three are half the file between them and the ids are dense from zero,
/// so the top sixteen bits are zero in every grammar anyone has. Spending them
/// anyway would be the single largest remaining piece of longhand in the file.
/// It is only safe because they are bare ids: there is no field to misread and
/// no sign to lose, the width is in the sealed directory, and `open` refuses
/// any width but the two.
pub fn narrow(k: Kind) bool {
    return switch (k) {
        .groupref, .setsym, .stepref => true,
        else => false,
    };
}

/// Refuse, at compile time, a record type whose bytes are not all owned by a
/// field.
///
/// `impose.fill` writes a section as a run of fields into a zeroed buffer;
/// `collate.view` reads it back as `[]Record(k)` straight out of the mapping.
/// Those two agree only while a record's fields tile it exactly. Give one a
/// `u64` after an odd number of `u32`s and `@sizeOf` opens an alignment hole
/// the writer's next `put` does not skip, so every row after it is read from
/// four bytes to the left - a silent misread of the whole section rather than
/// a refusal, and one the schema digest cannot see, because the digest spells
/// the fields and the hole is what the fields are not.
///
/// The other way in is the one that already happened. A section written with
/// `sliceAsBytes` instead of field by field hands `@sizeOf(T)` per record to
/// the file, and the bytes past the last field are whatever the allocation
/// held: `kernel/lex/lexicon.zig` did exactly that and put four bytes of this
/// process into every folio on disk. `flat` is the repair on that side; this is
/// the repair on the side where there is no writer to route through, because
/// the reader casts the mapping directly.
///
/// The predicate is `std.meta.hasUniqueRepresentation` - the same one
/// `std.mem.eql` consults before it will `memcmp` a type, and the same one
/// `flat` holds each of its fields to.
pub fn seamless(comptime T: type) void {
    comptime if (!std.meta.hasUniqueRepresentation(T)) @compileError(
        @typeName(T) ++ " spans " ++ std.fmt.comptimePrint("{d}", .{@sizeOf(T)}) ++
            " bytes and its fields do not, so a section of them has bytes no" ++
            " writer assigns and no reader means. Widen the short field, or" ++
            " spell the slack as one.",
    );
}

comptime {
    // Exhaustive by construction: a section added tomorrow is checked without
    // anyone remembering this exists, which is the only kind of roster that
    // survives. The test below proves the loop is not empty.
    for (std.enums.values(Kind)) |k| seamless(Record(k));
}

const strides = blk: {
    var out: [kind_count]u16 = undefined;
    for (std.enums.values(Kind)) |k| out[@intFromEnum(k)] = @sizeOf(Record(k));
    break :blk out;
};

/// The fixed width of a section that has one. Narrow sections do not; ask
/// `strideFor` on the way in and the directory on the way out.
pub fn strideOf(k: Kind) u16 {
    return strides[@intFromEnum(k)];
}

/// How wide to write `k`, given how many distinct things its ids point at.
pub fn strideFor(k: Kind, span: u32) u16 {
    return if (narrow(k) and span <= 1 << 16) 2 else strideOf(k);
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
    // A narrow section spells as its shape and not its width, because the width
    // is a property of the grammar rather than of the layout, and the sealed
    // directory is where it is stated.
    for (std.enums.values(Kind)) |k| {
        out = out ++ ";" ++ @tagName(k) ++ "=" ++ (if (narrow(k)) "id" else spell(Record(k)));
    }
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

test "every section's record is seamless, and the check looked at a real set" {
    // The comptime block above is the gate; this is its anti-vacuity, because a
    // `for` over an empty roster passes and a predicate that says yes to
    // everything passes, and both would read exactly like a clean bill.
    //
    // Three things, in the order they could go wrong:
    comptime var counted: usize = 0;
    comptime var structs: usize = 0;
    inline for (std.enums.values(Kind)) |k| {
        counted += 1;
        // Re-asserted here rather than trusted from the comptime block, so the
        // count and the claim come from the same walk.
        try testing.expect(std.meta.hasUniqueRepresentation(Record(k)));
        if (@typeInfo(Record(k)) == .@"struct") structs += 1;
    }
    // One: the set is the whole directory, not a leftover subset.
    try testing.expectEqual(@as(usize, kind_count), counted);
    // Two: it is not all `u8` and `u32`, which own their bytes for free and
    // would make the gate true of a format that never had a record at all.
    try testing.expect(structs >= 8);
    // Three: the predicate can still say no. The control is the shape that put
    // four bytes of this process into every folio - `Dfa.PatRun`, whose `u64`
    // Zig seats first and whose `u32` leaves four bytes past the end.
    try testing.expect(!std.meta.hasUniqueRepresentation(struct { hi: u32, mask: u64 }));
    // And the near miss that has no visible gap: an `i32` after three `u32`s is
    // seamless, but make one of them a `u64` and the hole opens mid-record.
    try testing.expect(!std.meta.hasUniqueRepresentation(extern struct { a: u32, b: u64 }));
}

test "the schema digest is a function of the layout and names every section" {
    try testing.expect(schema().eql(schema()));
    for (std.enums.values(Kind)) |k| {
        try testing.expect(std.mem.indexOf(u8, schema_preimage, @tagName(k)) != null);
    }
    // And of the fields inside a record, not just the section roster.
    try testing.expect(std.mem.indexOf(u8, schema_preimage, "rhs_off:u32") != null);
    // Signedness too, since a rank read as unsigned is a rank read backwards.
    try testing.expect(std.mem.indexOf(u8, schema_preimage, "rank:i32") != null);
}

test "a directory row round-trips, and a wild kind is refused rather than folded" {
    var buf: [entry_len]u8 = undefined;
    const e: Entry = .{ .kind = .group, .stride = 8, .count = 1234, .offset = 4096 };
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

test "a narrow section is written at the width its own count needs" {
    try testing.expectEqual(@as(u16, 2), strideFor(.groupref, 40_000));
    try testing.expectEqual(@as(u16, 2), strideFor(.setsym, 1 << 16));
    try testing.expectEqual(@as(u16, 4), strideFor(.setsym, (1 << 16) + 1));
    // And a fixed section ignores the count entirely.
    try testing.expectEqual(@as(u16, 8), strideFor(.group, 3));
    try testing.expectEqual(@as(u16, 8), strideFor(.group, 1 << 30));
}

test "every section's stride is the width of the record it carries" {
    try testing.expectEqual(@as(u16, 1), strideOf(.text));
    try testing.expectEqual(@as(u16, 8), strideOf(.group));
    try testing.expectEqual(@as(u16, 12), strideOf(.odd));
    try testing.expectEqual(@as(u16, 16), strideOf(.production));
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
