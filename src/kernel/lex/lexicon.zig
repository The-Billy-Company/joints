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
const magic: u32 = 0x4c58_4e32; // "LXN2"

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

/// Deflating fails only where the machine does; there is no file here, only an
/// allocating writer, and `WriteFailed` is that writer's name for the same fact
/// `OutOfMemory` names. An automaton this format cannot describe is `null`, not
/// a member - see `freeze`.
pub const Frozen = error{WriteFailed} || std.mem.Allocator.Error;

/// Inflating fails on the machine, or on bytes that do not read back. Every
/// *expected* reason not to inflate - no section, a stale digest, a different
/// pattern count - is `null`, because a slate can always be determinized again
/// and a folio that declines to help is only slower. `LexiconUnreadable` is the
/// one that is not that: the block announced its own shape and then did not
/// have it, under a seal that already matched.
pub const Thawed = error{LexiconUnreadable} || std.mem.Allocator.Error;

/// A slate's automata, deflated. Free with `gpa.free`.
///
/// Null when the slate holds an automaton this format cannot describe: one
/// carrying a start-state dwell, which is derived only for an unanchored start
/// and so cannot arise from a munch. Refused rather than dropped, because
/// dropping it would be a scanner that skips bytes it should have walked.
pub fn freeze(gpa: std.mem.Allocator, m: *const Munch, stamp: u64) Frozen!?[]u8 {
    var raw: std.Io.Writer.Allocating = .init(gpa);
    defer raw.deinit();
    const w = &raw.writer;

    try w.writeAll(&flat(Preamble, .{
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
        // The reachability mask is written like any other table, and unlike
        // any other table its *absence* is silent: `reachableFrom` answers
        // all-ones without one, so a block that dropped it lexes the same
        // tokens and walks to end-of-file at every position to get them.
        //
        // So the two sides agree on exactly when it is there, and the rule is
        // checkable from the block alone. An automaton over one pattern has no
        // attribution table and therefore no mask, and needs none: `permitted`
        // for such a voice is all-or-nothing, so the mask could only ever
        // repeat what the dead state already says. Every other voice carries
        // one per state, or this format will not describe it.
        if (d.reach.len != if (v.ordinals.len == 1) 0 else d.nstates) return null;
        // The dense attribution row travels as runs — `freeze` grouped equal
        // pattern sets contiguous, so the wire form is a handful of
        // (bound, mask) pairs where the row is a mask per match state. The
        // bounds are premultiplied like every other state value in the block.
        var pat_runs: std.ArrayList(Dfa.PatRun) = .empty;
        defer pat_runs.deinit(gpa);
        var pi: usize = 0;
        while (pi < d.pats.len) {
            var pj = pi + 1;
            while (pj < d.pats.len and d.pats[pj] == d.pats[pi]) pj += 1;
            try pat_runs.append(gpa, .{ .hi = @as(u32, @intCast(pj)) * d.ncls, .mask = d.pats[pi] });
            pi = pj;
        }
        try seat(&raw);
        try w.writeAll(&flat(Head, .{
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
            .pat_runs = @intCast(pat_runs.items.len),
            .reach = @intCast(d.reach.len),
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
        // One at a time rather than `sliceAsBytes`, for the reason `flat`
        // exists: `PatRun` is `{ hi: u32, mask: u64 }`, so Zig seats the word
        // first and rounds the pair to sixteen, and the four bytes past `hi`
        // belong to whatever the run builder's array list was allocated over.
        // The elements keep the layout `thaw` views them at; only the bytes
        // between them stop being somebody else's.
        for (pat_runs.items) |run| try w.writeAll(&flat(Dfa.PatRun, run));
        try seat(&raw);
        try w.writeAll(std.mem.sliceAsBytes(d.reach));
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
pub fn thaw(gpa: std.mem.Allocator, block: []const u8, npatterns: usize, stamp: u64) Thawed!?Lexicon {
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
            if (v.dfa.pats.len != 0) gpa.free(v.dfa.pats);
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
        const reach = r.slice(u64, h.reach) orelse return null;
        const ordinals = r.slice(u32, h.ordinals) orelse return null;

        // The walk indexes `trans[state + class[b]]` unchecked, so a table that
        // does not match its own row count is the one corruption that faults
        // rather than misreads. Everything past this point it can survive.
        if (h.ncls == 0 or h.ncls > 256) return null;
        if (trans_in.len != @as(usize, h.nstates) * h.ncls) return null;
        if (trans_fin.len != trans_in.len) return null;
        if (trans_in_w.len != 0 and trans_in_w.len != trans_in.len) return null;
        if (h.match_hi > trans_in.len) return null;
        // `freeze`'s rule, read back: one mask per state, except for the
        // single-pattern voice that provably needs none. A block disagreeing
        // was written by a binary that did not have the mask, and loading it
        // would be correct and quadratic - so it determinizes again instead.
        if (reach.len != if (ordinals.len == 1) 0 else @as(usize, h.nstates)) return null;

        // The wire carries runs; the walk wants the dense row back — one mask
        // per match state, so `patternsAt` at every accepting byte is a load
        // rather than a search. Owned by the automaton even though its tables
        // are borrowed, which `Dfa.deinit` knows. Runs that do not tile the
        // match prefix exactly were written by nobody — determinize instead.
        const nmatch = h.match_hi / h.ncls;
        const pats: []u64 = if (pat_runs.len == 0) &.{} else dense: {
            const row = try gpa.alloc(u64, nmatch);
            var id: u32 = 0;
            for (pat_runs) |run| {
                const hi = run.hi / h.ncls;
                if (hi > nmatch or hi < id) break;
                while (id < hi) : (id += 1) row[id] = run.mask;
            }
            if (id != nmatch) {
                gpa.free(row);
                return null;
            }
            break :dense row;
        };
        errdefer if (pats.len != 0) gpa.free(pats);
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
            .pats = pats,
            .reach = reach,
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

/// A record as bytes, with every one of them assigned.
///
/// `std.mem.asBytes` hands over `@sizeOf(T)`, and `@sizeOf` rounds a struct up
/// to its own alignment - so a record whose fields stop short of that carries
/// bytes no field owns. `Head` is sixty bytes of fields in a type that rounds
/// to sixty-four; `Dfa.PatRun` is twelve in a type that rounds to sixteen. Zig
/// promises nothing about what is in the difference, and the two answers it
/// gives in practice are both bad: a struct literal inherits the stack frame,
/// an array-list element inherits the allocation.
///
/// That put arbitrary process memory into a file meant to travel between
/// machines, and - because the block is deflated - made the *length* of the
/// section move, so twelve of thirty grammars pressed to different bytes twice
/// in a row from one binary. The tables underneath were identical every time;
/// only these bytes were not. See `research/press/RESULT-1-scope.md`.
///
/// Field by field into a zeroed cell, so the padding is written rather than
/// hoped about, and reflectively, so a field added to `Head` tomorrow is
/// carried without anyone remembering this exists.
fn flat(comptime T: type, v: T) [@sizeOf(T)]u8 {
    comptime for (@typeInfo(T).@"struct".fields) |f| {
        // A field with slack of its own carries it: assigning the field whole
        // copies the source's bytes over the zeroed cell, and the ones no
        // sub-field owns are the same bug one level down, invisible again. A
        // nested struct is the obvious way in; a `u21` is the quiet one, four
        // bytes wide and twenty-one bits full, which the older spelling of this
        // check - "is it an integer" - waved straight through.
        //
        // The predicate is `std.meta.hasUniqueRepresentation`, the same one
        // `std.mem.eql` consults before it will `memcmp` a type and the same
        // one `leaf`'s section gate holds every folio record to. One law with
        // one spelling, so there is one thing to keep right.
        if (!std.meta.hasUniqueRepresentation(f.type)) @compileError(@typeName(T) ++
            "." ++ f.name ++ " has bytes no field of it owns, so `flat` cannot" ++
            " promise every byte of it is assigned. Widen it to a whole number" ++
            " of bytes, or spell its slack as a field - do not reach for" ++
            " `asBytes`, which is what wrote four bytes of this process's heap" ++
            " into every folio on disk.");
    };
    var out: [@sizeOf(T)]u8 align(@alignOf(T)) = @splat(0);
    const cell: *T = @ptrCast(&out);
    inline for (@typeInfo(T).@"struct".fields) |f| @field(cell, f.name) = @field(v, f.name);
    return out;
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
    /// The per-state reachability mask. Written and read like every other
    /// array here, and called out only because it is the one whose *absence*
    /// is silent: a folio without it still lexes, still returns the same
    /// tokens, and costs a walk to end-of-file per position for the rest of
    /// the file's life. See `thaw`.
    reach: u32,
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

const testing = std.testing;

/// The three records this file writes whole. Named once so the test below and
/// a reader looking for what `flat` is for see the same list.
const written = .{ Preamble, Head, Dfa.PatRun };

test "a record is written with every byte of it assigned, padding included" {
    // The failure this stands against: `asBytes` on a struct literal hands over
    // `@sizeOf(T)`, and the bytes past the last field are whatever the frame or
    // the allocation held. Two of these three have such bytes - `Head` stops at
    // sixty of sixty-four, `PatRun` at twelve of sixteen - and writing them put
    // heap in a folio and made eleven of thirty grammars press to different
    // bytes twice running.
    //
    // Reflective on both sides: which bytes a field owns comes from `@offsetOf`
    // rather than from remembered numbers, so a field added to `Head` tomorrow
    // is covered without anybody editing this.
    inline for (written) |T| {
        var owned: [@sizeOf(T)]bool = @splat(false);
        // Every field all-ones, so an owned byte reading zero is one `flat`
        // failed to assign rather than one that was legitimately zero.
        var loud: T = undefined; // and its padding is the poison
        inline for (@typeInfo(T).@"struct".fields) |f| {
            @memset(owned[@offsetOf(T, f.name)..][0..@sizeOf(f.type)], true);
            @field(loud, f.name) = std.math.maxInt(f.type);
        }
        const bytes: [@sizeOf(T)]u8 align(@alignOf(T)) = flat(T, loud);
        for (bytes, owned) |b, mine| try testing.expectEqual(mine, b != 0);
        // And the fields are still what they were: a `flat` that zeroed
        // everything would pass the half above and write an empty record.
        const back: *const T = @ptrCast(&bytes);
        inline for (@typeInfo(T).@"struct".fields) |f| {
            try testing.expectEqual(@field(loud, f.name), @field(back, f.name));
        }
    }
}

test "at least one of the written records has padding to get wrong" {
    // Otherwise the test above is green because there was nothing to check,
    // which is the shape of every flattering instrument in this tree. If a
    // future layout makes all three seamless, delete this and say so.
    var slack = false;
    inline for (written) |T| {
        comptime var fields: usize = 0;
        inline for (@typeInfo(T).@"struct".fields) |f| fields += @sizeOf(f.type);
        if (fields != @sizeOf(T)) slack = true;
    }
    try testing.expect(slack);
}
