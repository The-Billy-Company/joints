//! The lines of the page, ruled once and kept across edits.
//!
//! A ruling is one record per line: where the line starts, where its leading
//! whitespace ends, what column that lands on, and which of four shapes the
//! line is. That is the whole structural index, and it is small on purpose -
//! see the README for what is deliberately absent and why.
//!
//! ## The invariant the whole thing rests on
//!
//! **A line's record is a pure function of that line's own bytes.** Nothing in
//! it depends on the line before it - not a block comment carried in, not a
//! string left open, not a bracket depth. That is what makes `splice` local:
//! an edit inside line `f` can only change the records of the lines the edit
//! touched, so every other record survives untouched and the tail just moves
//! by the edit's delta.
//!
//! It is also what makes the measurement in `measure.zig` provably identical
//! with a ruling and without one. `measure.lead` has no cross-line memory
//! either - it enters a bounded comment only when it *sees* the opener while
//! walking - so a record that says "this line is spaces then code at column 4"
//! is exactly what the byte loop would have concluded. The moment a record
//! claimed something about the line before it, the two would part.
//!
//! The price is `.rough`: every line the record cannot state without breaking
//! the invariant is marked and walked a byte at a time. That is a carriage
//! return or a form feed inside the leading run (both reset the column, which
//! the arithmetic here does not carry), a backslash continuation, a bounded
//! comment opening the line, and the last line of a file whose whitespace runs
//! into the end of input. On the corpus that is a percent or two of lines.
//!
//! ## Why a record answers about both comment spellings at once
//!
//! `# x` opens a comment in Python and is a shell fragment in C, so a line's
//! shape is a question with two answers and the classification has to have
//! picked one. Storing both is what keeps a ruling a fact about **bytes** and
//! nothing else - which matters more than the byte it costs, because the file's
//! owner is the editor and the comment spelling belongs to the grammar. A
//! ruling that had to be told the spelling would have to be threaded from the
//! grammar down through the scanner to the material, and the material is where
//! it starts. Both answers fit in the padding the record already had.

const std = @import("std");
const sweep = @import("sweep.zig");

/// A tab advances to the next multiple of this. Python's own tokenizer and
/// tree-sitter's scanner both use eight, so a file mixing tabs and spaces
/// blocks the same way here as it does there.
pub const tab_stop = 8;

/// How a language spells the comment a measurement has to see through.
///
/// Not a decoration on the rule - for the corpus this lexer measures itself
/// against it is the dominant case. 499 of the 628 lines of the scala fixture
/// begin with a comment, so a measurement that reads `/**` as content puts the
/// wrong column on four lines in five, and every block boundary derived from
/// those columns is a guess. Python's own scanner has the same clause for the
/// same reason; the only thing that differs between the two languages is the
/// spelling, so that is the only thing this names.
///
/// `slashes` nests, because scala's block comment does and C's does not - a
/// `/* /* */ */` closed at the first `*/` would hand the rest of the comment to
/// the parser as code.
pub const Note = enum {
    hash,
    slashes,

    /// Whether a comment opens at `bytes[i]`, and how wide its opener is.
    pub fn opens(n: Note, bytes: []const u8, i: u32) ?struct { u32, bool } {
        return switch (n) {
            .hash => if (bytes[i] == '#') .{ 1, false } else null,
            .slashes => blk: {
                if (bytes[i] != '/' or i + 1 >= bytes.len) break :blk null;
                break :blk switch (bytes[i + 1]) {
                    '/' => .{ 2, false },
                    '*' => .{ 2, true },
                    else => null,
                };
            },
        };
    }
};

/// What a line turned out to be, once its leading run was measured.
pub const Kind = enum {
    /// Spaces and tabs, then the line ending. Nothing to measure.
    blank,
    /// Spaces and tabs, then a comment that runs to the line ending.
    note,
    /// Spaces and tabs, then a byte that is neither, and that byte is the
    /// line's content at the column the record names.
    code,
    /// A line the record declines to state. Walked a byte at a time; see the
    /// header for the four shapes that land here.
    rough,
};

/// One line. `body` is where the leading run of spaces and tabs stops, and
/// `column` is where that lands with tabs expanded - `undefined` in neither
/// case, but meaningless for `.rough`, which is what `.rough` means.
pub const Line = struct {
    start: u32,
    body: u32,
    column: u16,
    /// The shape under each spelling. Two fields rather than one and a
    /// parameter on the ruling; see the header for why the material declines
    /// to know which language is reading it.
    hash: Kind,
    slashes: Kind,

    pub fn shape(l: Line, note: Note) Kind {
        return switch (note) {
            .hash => l.hash,
            .slashes => l.slashes,
        };
    }
};

/// An edit as the editor states it. Structurally the spine's `Cut` and
/// deliberately not an import of it: the spine is a zone above this one, so
/// `grain` naming it would point up the page. The caller writing
/// `.{ .from = cut.from, … }` costs one line at the one seam that has both.
pub const Cut = struct { from: u32, to: u32, insert: u32 };

/// Every line of a file, measured once.
pub const Ruling = struct {
    /// The bytes this describes, kept so a reader can prove the ruling is
    /// *this* file's before trusting it. One scanner reads many files and a
    /// stale ruling would answer confidently about the wrong one, so the check
    /// is identity of the slice rather than a hash: exact, and free.
    text: []const u8,
    lines: std.ArrayList(Line),
    /// Where the last lookup landed. A memo, not a position: see `at`.
    cursor: u32 = 0,

    pub fn of(gpa: std.mem.Allocator, bytes: []const u8) !Ruling {
        var r: Ruling = .{ .text = bytes, .lines = .empty };
        errdefer r.lines.deinit(gpa);
        try rule(gpa, bytes, 0, @as(u32, @intCast(bytes.len)) +| 1, &r.lines);
        return r;
    }

    pub fn deinit(r: *Ruling, gpa: std.mem.Allocator) void {
        r.lines.deinit(gpa);
        r.* = undefined;
    }

    /// Whether this ruling describes exactly these bytes.
    pub fn covers(r: *const Ruling, bytes: []const u8) bool {
        return r.text.ptr == bytes.ptr and r.text.len == bytes.len;
    }

    /// How far the memo below is walked forward before the lookup gives up and
    /// bisects. A scan that moved on by more than this did not move on - it
    /// jumped, and a jump is what bisection is for.
    const stride = 8;

    /// Which line `at` falls in. `at == text.len` answers the last line, so a
    /// caller walking to the end of input needs no special step.
    ///
    /// Bisection, in front of a one-line memo, and the memo is the whole
    /// reason a ruling is worth having. A scanner asks about a line, then about
    /// the line after it: the answer is the last answer or its successor almost
    /// every time, so the common case is a compare rather than log n branches
    /// the predictor cannot learn. Measured on `bench/rungs/grain`, answering
    /// *which line* dominated reading the line's record - the ruled arm was
    /// three times the byte walk on this repository's own largest source file
    /// until the memo landed, and is a third of it after.
    ///
    /// A wrong memo costs exactly the bisection it replaced, which is why it
    /// takes `*Ruling`: nothing here is state, and the answer is the same
    /// whether the memo was right, wrong, or shared with another reader.
    pub fn at(r: *Ruling, offset: u32) u32 {
        const lines = r.lines.items;
        var lo: u32 = 0;
        var hi: u32 = @intCast(lines.len);
        const memo = @min(r.cursor, hi -| 1);
        if (hi > 1 and lines[memo].start <= offset) {
            var k = memo;
            var step: u32 = 0;
            while (k + 1 < hi and lines[k + 1].start <= offset and step < stride) : (step += 1) k += 1;
            if (step < stride) {
                r.cursor = k;
                return k;
            }
            lo = k;
        }
        while (hi - lo > 1) {
            const mid = lo + (hi - lo) / 2;
            if (lines[mid].start <= offset) lo = mid else hi = mid;
        }
        r.cursor = lo;
        return lo;
    }

    /// Where line `k` ends, which is where line `k + 1` begins - or the end of
    /// input for the last one.
    pub fn after(r: *const Ruling, k: u32) u32 {
        return if (k + 1 < r.lines.items.len)
            r.lines.items[k + 1].start
        else
            @intCast(r.text.len);
    }

    /// Re-derive only the lines the edit touched.
    ///
    /// `after` is the text as it stands now; the cut is stated against the
    /// text as it stood. Two facts make this local and they are both worth
    /// stating, because either one failing turns this into a rebuild:
    ///
    ///   * a record is a pure function of its own line's bytes (see header),
    ///     so a line the edit did not touch keeps its shape;
    ///   * the newline that ends the last touched line **cannot** be inside
    ///     the cut. `to` sits in that line by construction, and the line's
    ///     newline is its last byte, so `[from, to)` stops before it. That is
    ///     why the boundary below is a real line start in the new text rather
    ///     than a hope.
    pub fn splice(r: *Ruling, gpa: std.mem.Allocator, text: []const u8, cut: Cut) !void {
        std.debug.assert(cut.from <= cut.to and cut.to <= r.text.len);
        const delta = @as(i64, cut.insert) - @as(i64, cut.to - cut.from);
        std.debug.assert(@as(i64, @intCast(r.text.len)) + delta == @as(i64, @intCast(text.len)));

        const first = r.at(cut.from);
        const last = r.at(cut.to);
        const shift: u32 = @intCast(@as(i64, r.after(last)) + delta);
        const tail: u32 = if (last + 1 < r.lines.items.len) shift else @as(u32, @intCast(text.len)) +| 1;

        var fresh: std.ArrayList(Line) = .empty;
        defer fresh.deinit(gpa);
        try rule(gpa, text, r.lines.items[first].start, tail, &fresh);

        for (r.lines.items[last + 1 ..]) |*l| {
            l.start = @intCast(@as(i64, l.start) + delta);
            l.body = @intCast(@as(i64, l.body) + delta);
        }
        try r.lines.replaceRange(gpa, first, last + 1 - first, fresh.items);
        r.text = text;
    }
};

/// Rule the lines whose starts fall in `[from, upto)`, appending in order.
///
/// One forward walk, two vectorized questions per line: where the leading run
/// stops, and where the line does. Collecting all the newlines first and then
/// measuring each line would read the file twice and want an array to hold the
/// answers in between, and the second read is the expensive one. The column
/// arithmetic stays scalar - an indent is a handful of bytes and a tab stop
/// does not add, so there is nothing there for a vector to do.
fn rule(
    gpa: std.mem.Allocator,
    bytes: []const u8,
    from: u32,
    upto: u32,
    out: *std.ArrayList(Line),
) !void {
    var start = from;
    while (start < upto) {
        const body = sweep.past(bytes, start, " \t");
        try out.append(gpa, .{
            .start = start,
            .body = body,
            .column = width(bytes[start..body]),
            .hash = shape(bytes, .hash, body),
            .slashes = shape(bytes, .slashes, body),
        });
        const stop = sweep.find(bytes, body, "\n");
        if (stop >= bytes.len) break;
        start = stop + 1;
    }
}

/// The column a run of spaces and tabs lands on. Saturating, exactly as the
/// byte loop it replaces was: a line indented past 65535 columns is not a line
/// anybody is editing, and wrapping would open a block at column three.
fn width(run: []const u8) u16 {
    var column: u16 = 0;
    for (run) |c| column = if (c == '\t') (column / tab_stop +| 1) *| tab_stop else column +| 1;
    return column;
}

fn shape(bytes: []const u8, note: Note, body: u32) Kind {
    if (body >= bytes.len) return .rough;
    return switch (bytes[body]) {
        '\n' => .blank,
        '\r', 0x0c, '\\' => .rough,
        else => if (note.opens(bytes, body)) |open|
            if (open[1]) .rough else .note
        else
            .code,
    };
}

test "ruling: the line starts are the newline partition" {
    const gpa = std.testing.allocator;
    const src = "a\n\n  b\n";
    var r = try Ruling.of(gpa, src);
    defer r.deinit(gpa);
    // Four, not three: a file ending in a newline has an empty last line, and
    // dropping it would make `at(src.len)` answer about the line before it.
    try std.testing.expectEqual(@as(usize, 4), r.lines.items.len);
    try std.testing.expectEqual(@as(u32, 0), r.lines.items[0].start);
    try std.testing.expectEqual(@as(u32, 2), r.lines.items[1].start);
    try std.testing.expectEqual(@as(u32, 3), r.lines.items[2].start);
    try std.testing.expectEqual(@as(u32, 7), r.lines.items[3].start);
    try std.testing.expectEqual(@as(u16, 2), r.lines.items[2].column);
    try std.testing.expectEqual(Kind.blank, r.lines.items[1].hash);
    try std.testing.expectEqual(Kind.code, r.lines.items[2].hash);
}

test "ruling: at answers the containing line however the asks arrive" {
    const gpa = std.testing.allocator;
    // Long enough that a memo can be more than `stride` out of date, which is
    // the arm that has to fall back to bisection: forwards walks the memo,
    // backwards defeats it every time, and the shuffle defeats it at random.
    var src: std.ArrayList(u8) = .empty;
    defer src.deinit(gpa);
    for (0..200) |i| try src.appendSlice(gpa, if (i % 3 == 0) "\n" else "abcd\n");

    var r = try Ruling.of(gpa, src.items);
    defer r.deinit(gpa);
    const n = src.items.len;

    var order: std.ArrayList(u32) = .empty;
    defer order.deinit(gpa);
    for (0..n + 1) |o| try order.append(gpa, @intCast(o));
    var prng = std.Random.DefaultPrng.init(0x11_11_00);
    prng.random().shuffle(u32, order.items);

    for (0..n + 1) |o| try expectHolds(&r, @intCast(o));
    for (0..n + 1) |o| try expectHolds(&r, @intCast(n - o));
    for (order.items) |o| try expectHolds(&r, o);
}

fn expectHolds(r: *Ruling, offset: u32) !void {
    const k = r.at(offset);
    try std.testing.expect(r.lines.items[k].start <= offset);
    try std.testing.expect(offset <= r.after(k));
}

test "ruling: the four shapes, under both spellings at once" {
    const gpa = std.testing.allocator;
    const src = "  \n  # note\n  code\n  /* bounded\n  \\\n";
    var r = try Ruling.of(gpa, src);
    defer r.deinit(gpa);
    try std.testing.expectEqual(Kind.blank, r.lines.items[0].shape(.hash));
    try std.testing.expectEqual(Kind.note, r.lines.items[1].shape(.hash));
    try std.testing.expectEqual(Kind.code, r.lines.items[2].shape(.hash));
    try std.testing.expectEqual(Kind.rough, r.lines.items[4].shape(.hash));
    // The two spellings disagreeing about the same bytes is the whole reason
    // a record carries both: `/*` is code to Python and a bounded comment to
    // scala, and `# note` is the other way round.
    try std.testing.expectEqual(Kind.code, r.lines.items[3].shape(.hash));
    try std.testing.expectEqual(Kind.rough, r.lines.items[3].shape(.slashes));
    try std.testing.expectEqual(Kind.code, r.lines.items[1].shape(.slashes));
}

test "ruling: a splice lands on the same records a rebuild would" {
    const gpa = std.testing.allocator;
    const before = "def f():\n    x = 1\n    y = 2\n\n# tail\n";
    // Four edits with different shapes: inside a line, spanning a newline, a
    // pure insertion on a boundary, and a deletion that merges two lines.
    const cuts = [_]struct { Cut, []const u8 }{
        .{ .{ .from = 13, .to = 14, .insert = 3 }, "zzz" },
        .{ .{ .from = 9, .to = 18, .insert = 0 }, "" },
        .{ .{ .from = 9, .to = 9, .insert = 8 }, "    q\n\n" ++ "\t" },
        .{ .{ .from = 17, .to = 19, .insert = 0 }, "" },
    };
    for (cuts) |pair| {
        const cut, const insert = pair;
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(gpa);
        try text.appendSlice(gpa, before);
        try text.replaceRange(gpa, cut.from, cut.to - cut.from, insert);

        var spliced = try Ruling.of(gpa, before);
        defer spliced.deinit(gpa);
        try spliced.splice(gpa, text.items, cut);

        var rebuilt = try Ruling.of(gpa, text.items);
        defer rebuilt.deinit(gpa);
        try std.testing.expectEqualSlices(Line, rebuilt.lines.items, spliced.lines.items);
    }
}
