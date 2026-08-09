//! The memory a customary is allowed to have, and nothing else.
//!
//! Every external scanner in the eight-grammar census keeps its state in one of
//! three shapes, and the shapes are what `serialize` proves: a stack of
//! `(width, kind)` pairs (python/scala/yaml indent stacks, markdown's open-block
//! stack), a stack of `(kind, count, tag)` marks (heredocs, kotlin `$`-strings,
//! swift `#`-strings, html's tag stack), and a handful of scalar counters
//! (swift's one `u32`, markdown's three packed flags plus three counters). So
//! those are the organs, they are fixed-capacity, and there is no fourth.
//!
//! Fixed capacity is load-bearing in three separate ways:
//!
//!   * **A step cannot fail.** `Organs` is a plain value with no allocator, so
//!     the interpreter has no error set and `outside.step`'s contract - a hand
//!     answers or it does not - survives the customary arriving.
//!   * **A save is a copy.** `Scanner.Save` is documented pointer-free, and it
//!     stays that way with the organs inside it, which is what makes `Gather`'s
//!     fork state *exact* where tree-sitter's `serialize` is capped at 1024
//!     lossy bytes.
//!   * **A pass terminates.** `pass` iterates over one organ bounded by that
//!     organ's own depth, so a bounded stack is what keeps a loop over it from
//!     being a loop at all.
//!
//! Nothing here reads a byte or a rule. It is the state half of the algebra,
//! deliberately separable: `outside.Carry` embeds it and the interpreter writes
//! it, and neither of those two knows about the other.

const std = @import("std");

/// Symbol as the interpreter sees one. `press.Symbol` spells the same thing;
/// it is restated here so this directory reads nothing above `kernel/lex`, and
/// name resolution stays where the grammar is (see `engine.Engine.bind`).
pub const Symbol = u32;

/// Sizes, and each one is a census number rather than a round one.
///
/// `frames` is markdown's declared organ size and the deepest of the eight -
/// the same 96 `offside.Columns` chose, for the same reason: it is the depth of
/// nesting a real file reaches before the answer is that the file is generated.
/// `marks` is 8 because the deepest carried-state nesting anyone found is
/// kotlin's interpolation inside a triple-quoted string inside an
/// interpolation, and that is three. `regs` is 8 because markdown needs six.
pub const frames_max = 96;
pub const marks_max = 8;
pub const regs_max = 8;
/// How wide a remembered delimiter may be. A heredoc tag is an identifier and a
/// raw-string fence is a run of `#`, so this is generous; a longer one is
/// refused at load rather than truncated at scan, because a truncated tag would
/// close a string the author did not close.
pub const tag_max = 24;

/// One open layout region: how many columns it holds and what kind it is.
///
/// A `u16` width because a column is a column - the tab stop multiplies, so
/// 65,535 already describes a line no editor renders - and a `u8` kind because
/// a book declares its own kinds and the widest of the eight declares five.
pub const Frame = extern struct { width: u16, kind: u8, pad: u8 = 0 };

/// One open delimited region: what kind, a count it carries, and the bytes that
/// close it.
///
/// The count is the whole reason a mark is not a frame: swift remembers how
/// many `#`s opened a raw string, kotlin how many `$`s prefix an interpolation,
/// a fence how many backticks it owes. The tag is the other half - a heredoc
/// remembers a word, and `marks.top.tag` compares the bytes at the offset
/// against it, optionally case-folded.
pub const Mark = extern struct {
    kind: u8,
    len: u8,
    count: u16,
    tag: [tag_max]u8,

    pub fn text(m: *const Mark) []const u8 {
        return m.tag[0..m.len];
    }
};

/// Two stacks and a register bank. Copied by value; compared with `same`.
pub const Organs = struct {
    frames: [frames_max]Frame = undefined,
    marks: [marks_max]Mark = undefined,
    regs: [regs_max]u32 = @splat(0),
    frame_len: u8 = 0,
    mark_len: u8 = 0,

    pub fn reset(o: *Organs) void {
        o.frame_len = 0;
        o.mark_len = 0;
        o.regs = @splat(0);
    }

    pub fn frameDepth(o: *const Organs) u32 {
        return o.frame_len;
    }

    pub fn markDepth(o: *const Organs) u32 {
        return o.mark_len;
    }

    pub fn frameAt(o: *const Organs, i: u32) ?Frame {
        return if (i < o.frame_len) o.frames[i] else null;
    }

    pub fn frameTop(o: *const Organs) ?Frame {
        return if (o.frame_len == 0) null else o.frames[o.frame_len - 1];
    }

    pub fn markTop(o: *const Organs) ?*const Mark {
        return if (o.mark_len == 0) null else &o.marks[o.mark_len - 1];
    }

    /// Push, or refuse. A refusal is a full stack, and a full stack is a file
    /// nesting past the census depth: the answer is to decline the push and let
    /// the rule's other actions stand, exactly as `offside.Columns` does, rather
    /// than to grow without a bound or to fault a parse over a pathological
    /// file.
    pub fn pushFrame(o: *Organs, width: u32, kind: u8) void {
        if (o.frame_len == frames_max) return;
        o.frames[o.frame_len] = .{ .width = @intCast(@min(width, std.math.maxInt(u16))), .kind = kind };
        o.frame_len += 1;
    }

    pub fn pushMark(o: *Organs, kind: u8, count: u32, tag: []const u8) void {
        if (o.mark_len == marks_max) return;
        const len: u8 = @intCast(@min(tag.len, tag_max));
        var m: Mark = .{ .kind = kind, .len = len, .count = @intCast(@min(count, std.math.maxInt(u16))), .tag = @splat(0) };
        @memcpy(m.tag[0..len], tag[0..len]);
        o.marks[o.mark_len] = m;
        o.mark_len += 1;
    }

    pub fn popFrame(o: *Organs) void {
        if (o.frame_len > 0) o.frame_len -= 1;
    }

    pub fn popMark(o: *Organs) void {
        if (o.mark_len > 0) o.mark_len -= 1;
    }

    /// Pop down to and including the innermost entry of `kind`, or empty the
    /// stack if it holds none. html's implied closes are this: a `</table>`
    /// closes every row and cell still open inside it, and the C spells that as
    /// a loop with the same fallthrough.
    pub fn popFrameUntil(o: *Organs, kind: u8) void {
        while (o.frame_len > 0) {
            const at = o.frames[o.frame_len - 1].kind;
            o.frame_len -= 1;
            if (at == kind) return;
        }
    }

    pub fn popMarkUntil(o: *Organs, kind: u8) void {
        while (o.mark_len > 0) {
            const at = o.marks[o.mark_len - 1].kind;
            o.mark_len -= 1;
            if (at == kind) return;
        }
    }

    pub fn hasFrame(o: *const Organs, kind: u8) bool {
        for (o.frames[0..o.frame_len]) |f| if (f.kind == kind) return true;
        return false;
    }

    pub fn hasMark(o: *const Organs, kind: u8) bool {
        for (o.marks[0..o.mark_len]) |m| if (m.kind == kind) return true;
        return false;
    }

    /// Whether two organ banks are the same lexical state.
    ///
    /// Use this and never `std.meta.eql`: both stacks are fixed-capacity arrays
    /// with a live prefix, and everything past that prefix is `undefined`, so a
    /// structural comparison of two identical states can answer no - and answer
    /// differently in a release build than in a debug one. Same rule, same
    /// reason, as `outside.Carry.same`.
    pub fn same(a: *const Organs, b: *const Organs) bool {
        if (a.frame_len != b.frame_len or a.mark_len != b.mark_len) return false;
        if (!std.mem.eql(u32, &a.regs, &b.regs)) return false;
        for (a.frames[0..a.frame_len], b.frames[0..b.frame_len]) |x, y| {
            if (x.width != y.width or x.kind != y.kind) return false;
        }
        for (a.marks[0..a.mark_len], b.marks[0..b.mark_len]) |*x, *y| {
            if (x.kind != y.kind or x.count != y.count) return false;
            if (!std.mem.eql(u8, x.text(), y.text())) return false;
        }
        return true;
    }

    /// This state in one word, for the zero-width progress ledger.
    ///
    /// An organ absent from this is an organ whose moves cannot be told apart,
    /// and markdown's `_block_close` is exactly that hazard: three open blocks
    /// ending on one line owe three zero-width closes at one offset, and each is
    /// a different question only because the one before it popped a frame. See
    /// `outside.Spent` for what consumes it.
    ///
    /// The registers are folded in and not only the depths, because markdown's
    /// `budget` is moved by rules that emit nothing wide - a close that spends a
    /// carried column has made progress the depths do not show. That does weaken
    /// the ledger's *quality* arm, since a register nothing decides on now reads
    /// as progress too; it does not weaken termination, which rests on
    /// `Spent.ceiling` and not on this word.
    ///
    /// Zero for untouched organs, exactly, which is the zero-cost property: a
    /// grammar with no customary folds a zero into `Carry.shape` and gets the
    /// same word the hands got before this organ existed.
    pub fn shape(o: *const Organs) u64 {
        var out: u64 = (@as(u64, o.frame_len) << 8) | o.mark_len;
        for (o.regs, 0..) |r, i| out ^= @as(u64, r) *% (0x9E37_79B9_7F4A_7C15 +% i);
        return out;
    }
};

/// What grain measures, restated for one offset. Not state: a function of the
/// bytes, so it is recomputed per ask and carried nowhere.
pub const Facts = struct {
    bol: bool,
    /// Columns of blank in front of the line's first non-blank byte, plus
    /// whatever budget the grammar was carrying. In the `layout` phase this is
    /// the C's `s->indentation` exactly.
    lead: u32,
    blank: bool,
    /// Whether the line *before* this one is blank. A blank line is where
    /// markdown ends an html block, and the grammar spends the blank line first
    /// and only then asks for the close - so the question at the offset that
    /// answers it is about the line just left, not the line arrived at.
    lull: bool,
    column: u32,
    eof: bool,
};

/// Blanks from `at`, as a new offset and the columns they are worth.
///
/// The whole of the C's `while (lookahead == ' ' || '\t') indentation +=
/// advance(...)`, and the reason it is a function rather than a shape two rules
/// repeat: the layout sweep does it once before deciding anything, and each
/// block matcher does it again against its own target.
pub fn soak(bytes: []const u8, at: u32, tab: u32, carry: u32) struct { u32, u32 } {
    var off = at;
    var col = carry;
    while (off < bytes.len and (bytes[off] == ' ' or bytes[off] == '\t')) {
        col = if (bytes[off] == '\t') col + tab - (col % tab) else col + 1;
        off += 1;
    }
    return .{ off, col };
}

fn lineStart(bytes: []const u8, at: u32) u32 {
    var i = @min(at, bytes.len);
    while (i > 0 and bytes[i - 1] != '\n') i -= 1;
    return i;
}

fn lineEnd(bytes: []const u8, at: u32) u32 {
    var i = @min(at, bytes.len);
    while (i < bytes.len and bytes[i] != '\n') i += 1;
    return i;
}

/// Everything about the line at `at`, measured from the bytes.
///
/// `carry` seeds `lead` with the budget a grammar was holding, so a matcher's
/// idea of the indentation is the C's: consumed-but-unspent columns plus the
/// blanks in front of the offset.
pub fn facts(bytes: []const u8, at: u32, tab: u32, carry: u32) Facts {
    const head = lineStart(bytes, at);
    const tail = lineEnd(bytes, at);
    const soaked = soak(bytes, head, tab, carry);
    var lull = false;
    if (head > 0) {
        // The line before this one, and whether its blanks reach its own end.
        // `head - 1` is that line's newline, so its start is the newline before
        // that; a run of blanks arriving at or past the newline is a blank line.
        const prior = lineStart(bytes, head - 1);
        const before = soak(bytes, prior, tab, 0);
        lull = before[0] >= head - 1;
    }
    return .{
        .bol = at == 0 or bytes[@min(at, bytes.len) - 1] == '\n',
        .lead = soaked[1],
        .blank = soaked[0] >= tail,
        .lull = lull,
        .column = at - head,
        .eof = at >= bytes.len,
    };
}

test "a frame stack refuses to grow past the census depth" {
    var o: Organs = .{};
    for (0..frames_max + 4) |i| o.pushFrame(@intCast(i), 1);
    try std.testing.expectEqual(@as(u32, frames_max), o.frameDepth());
    o.popFrame();
    try std.testing.expectEqual(@as(u32, frames_max - 1), o.frameDepth());
}

test "pop until empties a stack that never holds the kind" {
    var o: Organs = .{};
    o.pushFrame(0, 1);
    o.pushFrame(0, 2);
    o.popFrameUntil(9);
    try std.testing.expectEqual(@as(u32, 0), o.frameDepth());
}

test "pop until stops at the innermost entry of the kind" {
    var o: Organs = .{};
    o.pushFrame(0, 7);
    o.pushFrame(0, 1);
    o.pushFrame(0, 2);
    o.popFrameUntil(1);
    try std.testing.expectEqual(@as(u32, 1), o.frameDepth());
    try std.testing.expectEqual(@as(u8, 7), o.frameTop().?.kind);
}

test "same reads the live prefix and not the dead bytes" {
    var a: Organs = .{};
    var b: Organs = .{};
    a.pushFrame(4, 2);
    a.popFrame();
    // `a` has a stale entry past its length and `b` never had one.
    try std.testing.expect(a.same(&b));
    a.pushMark(3, 2, "EOF");
    try std.testing.expect(!a.same(&b));
    b.pushMark(3, 2, "EOF");
    try std.testing.expect(a.same(&b));
    b.marks[0].tag[0] = 'e';
    try std.testing.expect(!a.same(&b));
}

test "a tag longer than the ceiling is truncated rather than overrunning" {
    var o: Organs = .{};
    const long = "A" ** (tag_max + 9);
    o.pushMark(1, 0, long);
    try std.testing.expectEqual(@as(usize, tag_max), o.markTop().?.text().len);
}

test "untouched organs weigh nothing in the progress word" {
    var o: Organs = .{};
    try std.testing.expectEqual(@as(u64, 0), o.shape());
    o.regs[3] = 1;
    try std.testing.expect(o.shape() != 0);
    o.regs[3] = 0;
    try std.testing.expectEqual(@as(u64, 0), o.shape());
    o.pushFrame(2, 1);
    try std.testing.expect(o.shape() != 0);
}

test "soak counts a tab to the next stop and not as one column" {
    const got = soak("\t  x", 0, 4, 0);
    try std.testing.expectEqual(@as(u32, 3), got[0]);
    try std.testing.expectEqual(@as(u32, 6), got[1]);
}

test "lull is about the line just left" {
    const text = "a\n\nb\n";
    // Line 3 (`b`) follows a blank line.
    try std.testing.expect(facts(text, 3, 4, 0).lull);
    // Line 1 follows nothing.
    try std.testing.expect(!facts(text, 0, 4, 0).lull);
    // Line 2 is itself blank; the line before it is not.
    try std.testing.expect(!facts(text, 2, 4, 0).lull);
    try std.testing.expect(facts(text, 2, 4, 0).blank);
}

test "facts read the line the offset sits in, wherever in it that is" {
    const text = "  hi there\n";
    const f = facts(text, 5, 4, 0);
    try std.testing.expectEqual(@as(u32, 2), f.lead);
    try std.testing.expectEqual(@as(u32, 5), f.column);
    try std.testing.expect(!f.bol);
    try std.testing.expect(!f.blank);
    try std.testing.expect(facts(text, 0, 4, 0).bol);
    try std.testing.expect(facts(text, text.len, 4, 0).eof);
}
