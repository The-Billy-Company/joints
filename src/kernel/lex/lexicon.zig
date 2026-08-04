//! The slate, already determinized: a compiled `Munch` as a block of bytes.
//!
//! Determinizing a slate is the whole of startup. A folio maps and binds in
//! under five milliseconds; the eleven corpus grammars then spend two to eighty
//! more turning their terminals into automata, and a single Unicode identifier
//! pattern - `[_\p{XID_Start}][_\p{XID_Continue}]*`, whose UTF-8 expansion runs
//! hundreds of byte ranges deep - is fifteen of those on its own in six of them.
//! Partitioning the slate cannot reach past it: the cheapest grouping anyone can
//! build still pays the same fifteen, and pays them across three to seven times
//! as many automata, which the scan loop then walks on every byte.
//!
//! But the answer is a pure function of the slate, and the slate is a pure
//! function of the grammar - so a grammar that is a file can carry it. This is
//! the format that lets it: the automata, written down, and read back rather
//! than rebuilt.
//!
//! **The folio holds an opaque run of bytes.** This file is the only thing that
//! knows what they mean; the scanner asks for a `Munch` and never learns whether
//! one was determinized or read.
//!
//! **Fail-safe, not fail-closed.** Every other refusal in the artifact path is
//! loud, because a misread table is a wrong parse. This one is quiet on purpose:
//! a lexicon is a cache of something we can always recompute, so `thaw` answers
//! null to anything it does not fully recognize - a short block, a foreign
//! layout, a digest naming a different slate, a table that does not fit its own
//! row count - and the caller determinizes. The one outcome ruled out is reading
//! a block wrong.
//!
//! That is also why the records are written in native byte order while the rest
//! of the folio is explicitly little-endian: a block written on the other
//! endianness fails its own magic on the first word, which is the answer this
//! section wants anyway. Nothing here is load-bearing enough to be worth a
//! per-field swap on a path whose entire purpose is to be fast.

const std = @import("std");
const irregex = @import("irregex");

const Munch = irregex.Munch;
const Dfa = Munch.Dfa;

/// What a block claims to be. Bumped for any layout change, so a block written
/// before one is refused rather than read as the shape that replaced it.
const magic: u32 = 0x4c58_4e31; // "LXN1"

/// The window `std.compress.flate` needs on both sides. Named once because both
/// directions allocate one and neither should guess.
const window = std.compress.flate.max_window_len;

/// Every record begins on a multiple of this, which is the widest alignment any
/// of them needs - two carry a `u64`, and a run of `u32`s before one can leave
/// the cursor on a four. Both directions seat every record the same way, so the
/// writer's padding and the reader's skip are the same arithmetic; getting that
/// wrong is a refusal rather than a misread, but it is still a refusal, and the
/// grammars it hit were the ones whose tables happened to sum to an odd four.
const grain = 8;

/// A slate's automata, deflated. Free with `gpa.free`.
///
/// Null when the slate holds an automaton this format cannot describe: one
/// carrying a start-state dwell, which is derived only for an unanchored start
/// and so cannot arise from a munch. Refused rather than dropped, because
/// dropping it would be a scanner that skips bytes it should have walked.
pub fn freeze(gpa: std.mem.Allocator, m: *const Munch, stamp: u64) !?[]u8 {
    var raw: std.Io.Writer.Allocating = .init(gpa);
    defer raw.deinit();
    const w = &raw.writer;

    try w.writeAll(std.mem.asBytes(&Preamble{
        .magic = magic,
        .voices = @intCast(m.voices.len),
        .npatterns = @intCast(m.seats.len),
        .declined = @intCast(m.declined.len),
        .digest = stamp,
    }));
    try seat(&raw);
    try w.writeAll(std.mem.sliceAsBytes(m.declined));

    for (m.voices) |v| {
        const d = v.dfa;
        if (d.start_dwell != null) return null;
        try seat(&raw);
        try w.writeAll(std.mem.asBytes(&Head{
            .ncls = d.ncls,
            .nstates = d.nstates,
            .match_hi = d.match_hi,
            .start = d.start,
            .start_w = d.start_w,
            .dead = d.dead,
            .empty_pats = d.empty_pats,
            .trans_in = @intCast(d.trans_in.len),
            .trans_fin = @intCast(d.trans_fin.len),
            .trans_in_w = @intCast(d.trans_in_w.len),
            .pat_runs = @intCast(d.pat_runs.len),
            .ordinals = @intCast(v.ordinals.len),
            .flags = (if (d.empty_match) Flag.empty_match else 0) |
                (if (d.anchored) Flag.anchored else 0) |
                (if (d.word_ctx) Flag.word_ctx else 0) |
                (if (d.unicode_word) Flag.unicode_word else 0),
        }));
        try seat(&raw);
        try w.writeAll(&d.class);
        try seat(&raw);
        try w.writeAll(std.mem.sliceAsBytes(d.trans_in));
        try seat(&raw);
        try w.writeAll(std.mem.sliceAsBytes(d.trans_fin));
        try seat(&raw);
        try w.writeAll(std.mem.sliceAsBytes(d.trans_in_w));
        try seat(&raw);
        try w.writeAll(std.mem.sliceAsBytes(d.pat_runs));
        try seat(&raw);
        try w.writeAll(std.mem.sliceAsBytes(v.ordinals));
    }
    // The image the reader allocates is this long, so the last record has to
    // end where the cursor will: on the grain, not wherever its bytes ran out.
    try seat(&raw);

    // A transition table is mostly one repeated dead row, so this is not a
    // marginal saving: the eleven corpus grammars deflate to between two and
    // three percent, which is what makes carrying them affordable at all. The
    // inflated length leads, uncompressed, so the reader can allocate its image
    // aligned and exact instead of growing one and copying it straight.
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll(std.mem.asBytes(&@as(u64, raw.written().len)));
    const scratch = try gpa.alloc(u8, window);
    defer gpa.free(scratch);
    var z = try std.compress.flate.Compress.init(&out.writer, scratch, .raw, .level_6);
    try z.writer.writeAll(raw.written());
    try z.finish();
    return try out.toOwnedSlice();
}

/// The automata in `block`, ready to lex `slate`. Null means determinize.
///
/// The result owns one inflate image and one handle per automaton; releasing
/// both is `Lexicon.deinit`, because the automata are borrowed and free nothing
/// of their own.
pub fn thaw(gpa: std.mem.Allocator, block: []const u8, npatterns: usize, stamp: u64) !?Lexicon {
    if (block.len < @sizeOf(u64)) return null;
    const want = std.mem.bytesToValue(u64, block[0..@sizeOf(u64)]);
    if (want == 0 or want % grain != 0 or want > max_image) return null;

    // One allocation behind every table, so the whole lexicon is one free and
    // no automaton has to know which part of it is its own.
    const image = try gpa.alignedAlloc(u8, .of(u64), @intCast(want));

    // Refusing is not an error, so an `errdefer` would miss every `return null`
    // below - and by then the image, the roster, and some automata are already
    // standing. One flag covers both ways out.
    var adopted = false;
    var voices: []Munch.Voice = &.{};
    var declined: []u32 = &.{};
    var built: usize = 0;
    defer if (!adopted) {
        for (voices[0..built]) |v| {
            gpa.free(v.ordinals);
            gpa.destroy(v.dfa);
        }
        gpa.free(voices);
        gpa.free(declined);
        gpa.free(image);
    };

    var src: std.Io.Reader = .fixed(block[@sizeOf(u64)..]);
    const scratch = try gpa.alloc(u8, window);
    defer gpa.free(scratch);
    var dst: std.Io.Writer = .fixed(image);
    var z = std.compress.flate.Decompress.init(&src, .raw, scratch);
    // Everything above returns null for a section that is absent or not ours,
    // which is a legitimate "determinize instead". This is not that. The folio's
    // seal is verified over the whole file before any of this runs, so these are
    // the bytes the writer wrote: a section that states an inflated length and
    // then does not inflate to it is our own bug, and recompiling quietly would
    // hide it behind nothing worse than a slow start, forever, on every machine
    // that reads the folio.
    const n = z.reader.streamRemaining(&dst) catch return error.LexiconUnreadable;
    if (n != want) return error.LexiconUnreadable;

    var r: Cursor = .{ .bytes = image };
    const pre = r.take(Preamble) orelse return null;
    if (pre.magic != magic or pre.npatterns != npatterns or pre.digest != stamp) return null;

    // A munch frees its roster and each voice's ordinals, so these two are
    // copied out rather than pointed into the image. They are a handful of
    // words beside tables of tens of thousands; the alternative is teaching
    // irregex a second kind of ownership to save nothing worth measuring.
    declined = try gpa.dupe(u32, r.slice(u32, pre.declined) orelse return null);

    voices = try gpa.alloc(Munch.Voice, pre.voices);
    for (voices) |*v| {
        const h = r.take(Head) orelse return null;
        const class = r.take([256]u8) orelse return null;
        const trans_in = r.slice(u32, h.trans_in) orelse return null;
        const trans_fin = r.slice(u32, h.trans_fin) orelse return null;
        const trans_in_w = r.slice(u32, h.trans_in_w) orelse return null;
        const pat_runs = r.slice(Dfa.PatRun, h.pat_runs) orelse return null;
        const ordinals = r.slice(u32, h.ordinals) orelse return null;

        // The walk indexes `trans[state + class[b]]` unchecked, so a table that
        // does not match its own row count is the one corruption that faults
        // rather than misreads. Everything past this point it can survive.
        if (h.ncls == 0 or h.ncls > 256) return null;
        if (trans_in.len != @as(usize, h.nstates) * h.ncls) return null;
        if (trans_fin.len != trans_in.len) return null;
        if (trans_in_w.len != 0 and trans_in_w.len != trans_in.len) return null;
        if (h.match_hi > trans_in.len) return null;

        const own = try gpa.dupe(u32, ordinals);
        errdefer gpa.free(own);
        const d = try gpa.create(Dfa);
        d.* = .{
            .class = class.*,
            .ncls = @intCast(h.ncls),
            .nstates = h.nstates,
            .trans_in = trans_in,
            .trans_fin = trans_fin,
            .trans_in_w = trans_in_w,
            .pat_runs = pat_runs,
            .match_hi = h.match_hi,
            .start = h.start,
            .start_w = h.start_w,
            .dead = h.dead,
            .empty_pats = h.empty_pats,
            .empty_match = h.flags & Flag.empty_match != 0,
            .anchored = h.flags & Flag.anchored != 0,
            .word_ctx = h.flags & Flag.word_ctx != 0,
            .unicode_word = h.flags & Flag.unicode_word != 0,
            .allocator = gpa,
            .borrowed = true,
        };
        v.* = .{ .dfa = d, .ordinals = own };
        built += 1;
    }
    // A block with bytes left over describes something this reader did not
    // fully understand, which is the same answer as not understanding it. The
    // cursor stops where the last record ended; the image runs to the grain the
    // writer seated it on, so the comparison has to be made on the same footing.
    if (std.mem.alignForward(usize, r.at, grain) != image.len) return null;

    const m = try Munch.adopt(gpa, pre.npatterns, voices, declined);
    adopted = true;
    return .{ .munch = m, .image = image };
}

/// Advance the written length to the next grain, so the record after it starts
/// where `Cursor` will look for it.
fn seat(raw: *std.Io.Writer.Allocating) !void {
    const at = raw.written().len;
    try raw.writer.splatByteAll(0, std.mem.alignForward(usize, at, grain) - at);
}

/// A slate read back, and the one buffer its automata live in.
pub const Lexicon = struct {
    munch: Munch,
    image: []align(@alignOf(u64)) u8,

    pub fn deinit(l: *Lexicon, gpa: std.mem.Allocator) void {
        l.munch.deinit();
        gpa.free(l.image);
        l.* = undefined;
    }
};

/// A slate's identity: every pattern in order, each with its own length folded
/// in so that a different cut of the same concatenation cannot forge it, and
/// the options it was determinized under.
///
/// The options belong in here because the automata are a function of both. The
/// same patterns read with `multiline` off and on are different machines, and
/// a stamp that covered only the text would let a folio minted before such a
/// change hand back automata that answer the old question - the one failure
/// this section is built to make impossible.
pub fn digest(slate: []const []const u8, how: Munch.Options) u64 {
    var h = std.hash.Wyhash.init(0x0741_5445);
    inline for (@typeInfo(Munch.Options).@"struct".fields) |f| {
        h.update(std.mem.asBytes(&@field(how, f.name)));
    }
    for (slate) |p| {
        h.update(std.mem.asBytes(&@as(u64, p.len)));
        h.update(p);
    }
    return h.final();
}

/// The largest image `thaw` will allocate on a block's say-so. The widest slate
/// measured is under three megabytes, so this is two orders of room and still
/// small enough that a corrupt length cannot ask for the machine.
const max_image: u64 = 256 << 20;

/// Everything about an automaton that is not one of its arrays. Fixed width, so
/// the arrays after it are found by arithmetic rather than by scanning.
const Head = extern struct {
    ncls: u32,
    nstates: u32,
    match_hi: u32,
    start: u32,
    start_w: u32,
    dead: u32,
    empty_pats: u64,
    trans_in: u32,
    trans_fin: u32,
    trans_in_w: u32,
    pat_runs: u32,
    ordinals: u32,
    flags: u32,
};

const Flag = struct {
    const empty_match: u32 = 1 << 0;
    const anchored: u32 = 1 << 1;
    const word_ctx: u32 = 1 << 2;
    const unicode_word: u32 = 1 << 3;
};

/// The fixed part of a block, before the voices.
const Preamble = extern struct {
    magic: u32,
    voices: u32,
    npatterns: u32,
    declined: u32,
    /// The slate these automata were determinized from. A folio and its grammar
    /// travel together, so this can only differ after somebody rebuilt one of
    /// them alone - and then the automata name terminals that have moved.
    digest: u64,
};

/// Cut successive records out of one image, refusing rather than reading past
/// its end. A cursor rather than four slices because the records are variable
/// width and each one's length is in the record before it.
const Cursor = struct {
    bytes: []align(@alignOf(u64)) u8,
    at: usize = 0,

    fn take(c: *Cursor, comptime T: type) ?*const T {
        c.at = std.mem.alignForward(usize, c.at, grain);
        if (@sizeOf(T) > c.bytes.len -| c.at) return null;
        defer c.at += @sizeOf(T);
        return @ptrCast(@alignCast(c.bytes[c.at..].ptr));
    }

    fn slice(c: *Cursor, comptime T: type, n: u32) ?[]const T {
        c.at = std.mem.alignForward(usize, c.at, grain);
        const want = @as(usize, n) * @sizeOf(T);
        if (want > c.bytes.len -| c.at) return null;
        defer c.at += want;
        return @alignCast(std.mem.bytesAsSlice(T, c.bytes[c.at..][0..want]));
    }
};

comptime {
    // The whole alignment argument in one line: a grain-aligned base, and every
    // record seated on the grain, means no record can begin at an offset its own
    // type could not be read from. Checking against the grain rather than against
    // `u64` is the point - the looser form admitted a `Head` at a four, which is
    // what got written for eight of the eleven grammars.
    for (.{ Preamble, Head, [256]u8, u32, Dfa.PatRun }) |T| {
        std.debug.assert(@alignOf(T) <= grain);
    }
    std.debug.assert(grain % @alignOf(u64) == 0);
}
