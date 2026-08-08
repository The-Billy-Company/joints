//! The compiled query, as the bytes the folio carries and as the view a matcher
//! reads them through.
//!
//! This is the whole point of the lane. tree-sitter ships `highlights.scm` as
//! source and re-parses it every time a process starts; a folio carries the
//! program, so the parse happens once, at press time, on a machine that is not
//! the user's. Names are already symbol ids, fields are already field ids, and
//! a supertype is already a membership test.
//!
//! **Everything is `u32` and nothing is a struct.** The section is byte-opaque
//! to the folio (`leaf.Kind.gloss` is `u8`), and a folio's promise is that a
//! reader views records where they lie rather than copying them - but the
//! section's own start is the only offset anybody aligned, so an `extern
//! struct` view would be relying on an alignment nothing checked. Fixed-width
//! words read with `readInt` cost one load and are correct on any host, which
//! is the same trade `quotient` made one section over.
//!
//! Layout, and the whole of it:
//!
//!     0  tag `GLSS`         5  captures       (span pairs)
//!     1  revision           6  predicates
//!     2  patterns           7  args
//!     3  steps              8  text length
//!     4  refs               9  zero
//!
//! then the six tables in that order and the text blob last. Every count is in
//! the header, so `read` can prove the length is exactly what the header
//! implies before it believes a single index - which is what makes it total.

const std = @import("std");
const sift = @import("sift.zig");

/// What a step matches. `wildcard` is the bare `_`; `(_)` is a `node` whose
/// kind is `any`, which is a different question - see `rubric.Shape`.
pub const Op = enum(u32) { node, literal, wildcard, group, choice };

pub const Quantifier = enum(u32) { one, optional, star, plus };

/// No id. Same sentinel the folio spends on an absent field, so a step read out
/// of the section and a step read out of a production compare the same way.
pub const none: u32 = std.math.maxInt(u32);

pub const flag_anchored: u32 = 1;
pub const flag_closed: u32 = 2;

/// A pattern the compiler proved can never match. Carried rather than dropped:
/// the file said it, so the program says it, and the matcher gets to skip it
/// for a reason it can print.
pub const flag_dead: u32 = 1;

const tag: u32 = 0x5353_4c47; // "GLSS"

/// Bumped for any layout change here. A section written before one is refused
/// rather than read as its replacement.
const revision: u32 = 2;

const head_words = 10;
const pattern_words = 5;
const step_words = 14;
const capture_words = 2;
const pred_words = 5;
const arg_words = 3;

// ── the view ──

pub const Pattern = struct {
    root: u32,
    preds: Run,
    /// Byte offset in the `.scm` this came from, so a diagnostic can point at
    /// the file rather than at the program.
    at: u32,
    flags: u32,

    pub fn dead(p: Pattern) bool {
        return p.flags & flag_dead != 0;
    }
};

pub const Step = struct {
    op: Op,
    /// Every symbol this position names, as a run of `refs`. A SET rather than
    /// an id, because a spelling is: tree-sitter mints a fresh terminal for
    /// `token(prec(1, "<"))` beside the plain `"<"` and both print as `<`, so
    /// Rust's `"<" @punctuation.bracket` means two symbols and twenty-two of
    /// the corpus's twenty-eight grammars share a spelling somewhere. Empty for
    /// a wildcard, a group, a choice, `(_)`, and for a name that only a rename
    /// answers to.
    kinds: Run,
    /// The RENAME this position names, or `none`. A second id space, and a
    /// second reading of the same word the file wrote.
    ///
    /// A tree node's kind is not always a symbol. `alias($.identifier,
    /// $.type_identifier)` puts a node called `type_identifier` in the tree
    /// while the symbol underneath stays `identifier`, and ten of the corpus's
    /// grammars query that name - Rust's `highlights.scm` opens on one. The
    /// press carries renames rather than applying them, so the folio keeps them
    /// in their own interned table and this is an index into it.
    ///
    /// Both this and `kinds` may be populated at once, and that is the point of
    /// two fields rather than one tagged word. C++ has a rule
    /// `function_declarator` AND renames `_function_field_declarator` to the
    /// same spelling, so `(function_declarator)` means either, and a matcher
    /// satisfies the step on whichever reading the node in hand answers to.
    /// Collapsing that to one id made the reachability check below call forty
    /// live patterns dead.
    alias: u32,
    /// The category in `(supertype/subtype)`, already resolved to the hidden
    /// rule's symbol. `none` when the author named no category.
    category: u32,
    field: u32,
    quantifier: Quantifier,
    flags: u32,
    kids: Run,
    captures: Run,
    /// `!field` - the fields this node must not carry.
    absent: Run,

    pub fn anchored(s: Step) bool {
        return s.flags & flag_anchored != 0;
    }

    /// A trailing `.`: no sibling after the last child.
    pub fn closed(s: Step) bool {
        return s.flags & flag_closed != 0;
    }

    /// Does this step pin a kind at all? False for a wildcard, a group, a
    /// choice, and `(_)`, all of which take any node.
    pub fn pinned(s: Step) bool {
        return s.kinds.len != 0 or s.alias != none;
    }
};

pub const Predicate = struct {
    op: sift.Op,
    /// The spelling, so an opaque one can be reported by the name the file
    /// used rather than as "unknown".
    name: Text,
    args: Run,
};

pub const Arg = union(enum) {
    /// An index into the program's capture table.
    capture: u32,
    text: Text,
};

/// A slice of the shared `refs` array. Kids, captures and absent fields all
/// live there, because three arrays of `u32` with three (off, len) pairs is
/// one array of `u32` with three pairs.
pub const Run = struct { off: u32, len: u32 };

/// A slice of the text blob, already resolved to bytes.
pub const Text = []const u8;

/// A compiled query, read where it lies. Nothing below copies a byte.
pub const Program = struct {
    raw: []const u8,
    counts: Counts,

    const Counts = struct {
        patterns: u32,
        steps: u32,
        refs: u32,
        captures: u32,
        predicates: u32,
        args: u32,
        text: u32,
    };

    pub fn patternCount(p: Program) u32 {
        return p.counts.patterns;
    }

    pub fn stepCount(p: Program) u32 {
        return p.counts.steps;
    }

    pub fn captureCount(p: Program) u32 {
        return p.counts.captures;
    }

    pub fn predicateCount(p: Program) u32 {
        return p.counts.predicates;
    }

    pub fn patternAt(p: Program, i: u32) Pattern {
        const w = p.words(.pattern, i);
        return .{
            .root = w[0],
            .preds = .{ .off = w[1], .len = w[2] },
            .at = w[3],
            .flags = w[4],
        };
    }

    pub fn stepAt(p: Program, i: u32) Step {
        const w = p.words(.step, i);
        return .{
            .op = @enumFromInt(w[0]),
            .kinds = .{ .off = w[1], .len = w[2] },
            .alias = w[3],
            .category = w[4],
            .field = w[5],
            .quantifier = @enumFromInt(w[6]),
            .flags = w[7],
            .kids = .{ .off = w[8], .len = w[9] },
            .captures = .{ .off = w[10], .len = w[11] },
            .absent = .{ .off = w[12], .len = w[13] },
        };
    }

    pub fn predicateAt(p: Program, i: u32) Predicate {
        const w = p.words(.pred, i);
        return .{
            .op = @enumFromInt(w[0]),
            .name = p.text(w[1], w[2]),
            .args = .{ .off = w[3], .len = w[4] },
        };
    }

    pub fn argAt(p: Program, i: u32) Arg {
        const w = p.words(.arg, i);
        return if (w[0] == 0) .{ .capture = w[1] } else .{ .text = p.text(w[1], w[2]) };
    }

    /// The name a capture was written as, `@` dropped.
    pub fn captureAt(p: Program, i: u32) Text {
        const w = p.words(.capture, i);
        return p.text(w[0], w[1]);
    }

    /// One entry of a `Run`. The runs hold step ids, capture ids and field ids
    /// depending on which one you took, and the `Step` that handed it to you is
    /// what says which.
    pub fn refAt(p: Program, i: u32) u32 {
        return p.words(.ref, i)[0];
    }

    /// One record, by value. Read a word at a time rather than viewed as a
    /// `[]const u32`, because the only alignment anybody promised is the
    /// section's own - the folio aligns where a section starts and says nothing
    /// about what is inside it.
    fn words(p: Program, comptime t: Table, i: u32) [t.width()]u32 {
        var out: [t.width()]u32 = undefined;
        const at = p.base(t) + @as(usize, i) * t.width() * 4;
        for (&out, 0..) |*v, j| v.* = word(p.raw[at..], j);
        return out;
    }

    fn text(p: Program, off: u32, len: u32) Text {
        const at = p.base(.text) + off;
        return p.raw[at..][0..len];
    }

    fn base(p: Program, comptime t: Table) usize {
        var at: usize = head_words * 4;
        inline for (comptime std.enums.values(Table)) |k| {
            if (k == t) return at;
            at += @as(usize, p.count(k)) * k.width() * 4;
        }
        unreachable;
    }

    fn count(p: Program, comptime t: Table) u32 {
        return switch (t) {
            .pattern => p.counts.patterns,
            .step => p.counts.steps,
            .ref => p.counts.refs,
            .capture => p.counts.captures,
            .pred => p.counts.predicates,
            .arg => p.counts.args,
            .text => p.counts.text,
        };
    }
};

/// The tables, in the order they are laid out. The order is the format.
const Table = enum {
    pattern,
    step,
    ref,
    capture,
    pred,
    arg,
    text,

    fn width(t: Table) usize {
        return switch (t) {
            .pattern => pattern_words,
            .step => step_words,
            .ref => 1,
            .capture => capture_words,
            .pred => pred_words,
            .arg => arg_words,
            // Bytes, not words. `base` multiplies by four, so the text blob's
            // width is a quarter of one - which is why its count is a byte
            // count and the header says so.
            .text => 0,
        };
    }
};

/// How long the section is for these counts. Every caller of `read` gets to
/// check the length against the header before believing an index, which is what
/// makes the reader total.
fn size(c: Program.Counts) usize {
    var at: usize = head_words * 4;
    at += @as(usize, c.patterns) * pattern_words * 4;
    at += @as(usize, c.steps) * step_words * 4;
    at += @as(usize, c.refs) * 4;
    at += @as(usize, c.captures) * capture_words * 4;
    at += @as(usize, c.predicates) * pred_words * 4;
    at += @as(usize, c.args) * arg_words * 4;
    return at + c.text;
}

/// A `gloss` section, read against nothing but itself.
///
/// Total: every way the bytes can fail to be a program is `null`, including
/// being empty. `collate` turns that into a refusal, for the same reason it
/// does for a `quotient` that does not fit - a folio carrying a section this
/// binary cannot account for is worse than one carrying none.
///
/// What it proves: the tag, the revision, that the length is exactly what the
/// header implies, and that every index in every table lands inside the table
/// it points at. After that a matcher can read the program without a bounds
/// check, which is the point.
pub fn read(bytes: []const u8) ?Program {
    if (bytes.len < head_words * 4) return null;
    if (word(bytes, 0) != tag or word(bytes, 1) != revision) return null;
    if (word(bytes, 9) != 0) return null;

    const c: Program.Counts = .{
        .patterns = word(bytes, 2),
        .steps = word(bytes, 3),
        .refs = word(bytes, 4),
        .captures = word(bytes, 5),
        .predicates = word(bytes, 6),
        .args = word(bytes, 7),
        .text = word(bytes, 8),
    };
    if (bytes.len != size(c)) return null;

    const p: Program = .{ .raw = bytes, .counts = c };
    for (0..c.patterns) |i| {
        const x = p.patternAt(@intCast(i));
        if (x.root >= c.steps) return null;
        if (!fits(x.preds, c.predicates)) return null;
    }
    for (0..c.steps) |i| {
        const s = p.stepAt(@intCast(i));
        if (@intFromEnum(s.op) > @intFromEnum(Op.choice)) return null;
        if (@intFromEnum(s.quantifier) > @intFromEnum(Quantifier.plus)) return null;
        if (!fits(s.kids, c.refs) or !fits(s.captures, c.refs) or
            !fits(s.absent, c.refs) or !fits(s.kinds, c.refs)) return null;
        // Step ids in `kids`, so a matcher can descend without checking.
        for (0..s.kids.len) |k| {
            if (p.refAt(s.kids.off + @as(u32, @intCast(k))) >= c.steps) return null;
        }
        for (0..s.captures.len) |k| {
            if (p.refAt(s.captures.off + @as(u32, @intCast(k))) >= c.captures) return null;
        }
    }
    for (0..c.predicates) |i| {
        const w = p.words(.pred, @intCast(i));
        if (w[0] > @intFromEnum(sift.Op.opaque_meta)) return null;
        if (!inText(p, w[1], w[2])) return null;
        if (!fits(.{ .off = w[3], .len = w[4] }, c.args)) return null;
    }
    for (0..c.args) |i| {
        const w = p.words(.arg, @intCast(i));
        if (w[0] > 1) return null;
        if (w[0] == 0) {
            if (w[1] >= c.captures or w[2] != 0) return null;
        } else if (!inText(p, w[1], w[2])) return null;
    }
    for (0..c.captures) |i| {
        const w = p.words(.capture, @intCast(i));
        if (!inText(p, w[0], w[1])) return null;
    }
    return p;
}

fn fits(r: Run, n: u32) bool {
    return @as(u64, r.off) + r.len <= n;
}

fn inText(p: Program, off: u32, len: u32) bool {
    return @as(u64, off) + len <= p.counts.text;
}

fn word(bytes: []const u8, i: usize) u32 {
    return std.mem.readInt(u32, bytes[i * 4 ..][0..4], .little);
}

// ── writing one ──

/// The program under construction. Everything is appended in the order the
/// lowering visits it; `finish` is the only place a byte of the section exists.
pub const Draft = struct {
    gpa: std.mem.Allocator,
    patterns: std.ArrayList(u32) = .empty,
    steps: std.ArrayList(u32) = .empty,
    refs: std.ArrayList(u32) = .empty,
    captures: std.ArrayList(u32) = .empty,
    preds: std.ArrayList(u32) = .empty,
    args: std.ArrayList(u32) = .empty,
    text: std.ArrayList(u8) = .empty,
    /// Capture names are the one thing worth interning: a `highlights.scm` has
    /// two thousand captures over a few dozen distinct names.
    seen: std.StringHashMapUnmanaged(u32) = .empty,

    pub fn deinit(d: *Draft) void {
        d.patterns.deinit(d.gpa);
        d.steps.deinit(d.gpa);
        d.refs.deinit(d.gpa);
        d.captures.deinit(d.gpa);
        d.preds.deinit(d.gpa);
        d.args.deinit(d.gpa);
        d.text.deinit(d.gpa);
        d.seen.deinit(d.gpa);
        d.* = undefined;
    }

    /// A step with no children yet. The lowering fills the runs afterwards,
    /// because a parent's id has to exist before its children can name it and
    /// its children's ids have to exist before it can name them.
    pub fn step(d: *Draft, s: Step) std.mem.Allocator.Error!u32 {
        const id: u32 = @intCast(d.steps.items.len / step_words);
        try d.steps.appendSlice(d.gpa, &.{
            @intFromEnum(s.op),         s.kinds.off, s.kinds.len, s.alias,
            s.category,                 s.field,
            @intFromEnum(s.quantifier), s.flags,
            s.kids.off,                 s.kids.len,
            s.captures.off,             s.captures.len,
            s.absent.off,               s.absent.len,
        });
        return id;
    }

    /// Rewrite one step's runs, now that the things they point at exist.
    pub fn wire(d: *Draft, id: u32, kids: Run, captures: Run, absent: Run) void {
        const w = d.steps.items[@as(usize, id) * step_words ..][0..step_words];
        w[8] = kids.off;
        w[9] = kids.len;
        w[10] = captures.off;
        w[11] = captures.len;
        w[12] = absent.off;
        w[13] = absent.len;
    }

    /// A run of ids in the shared array, whatever they are ids of.
    pub fn run(d: *Draft, ids: []const u32) std.mem.Allocator.Error!Run {
        const off: u32 = @intCast(d.refs.items.len);
        try d.refs.appendSlice(d.gpa, ids);
        return .{ .off = off, .len = @intCast(ids.len) };
    }

    /// The id of a capture name, minting one the first time it is seen.
    pub fn capture(d: *Draft, name: []const u8) std.mem.Allocator.Error!u32 {
        const slot = try d.seen.getOrPut(d.gpa, name);
        if (slot.found_existing) return slot.value_ptr.*;
        const at = try d.intern(name);
        slot.value_ptr.* = @intCast(d.captures.items.len / capture_words);
        try d.captures.appendSlice(d.gpa, &.{ at.off, at.len });
        return slot.value_ptr.*;
    }

    pub fn predicate(d: *Draft, op: sift.Op, name: []const u8, args: Run) std.mem.Allocator.Error!u32 {
        const id: u32 = @intCast(d.preds.items.len / pred_words);
        const at = try d.intern(name);
        try d.preds.appendSlice(d.gpa, &.{ @intFromEnum(op), at.off, at.len, args.off, args.len });
        return id;
    }

    pub fn argCapture(d: *Draft, id: u32) std.mem.Allocator.Error!void {
        try d.args.appendSlice(d.gpa, &.{ 0, id, 0 });
    }

    pub fn argText(d: *Draft, s: []const u8) std.mem.Allocator.Error!void {
        const at = try d.intern(s);
        try d.args.appendSlice(d.gpa, &.{ 1, at.off, at.len });
    }

    pub fn argCount(d: *const Draft) u32 {
        return @intCast(d.args.items.len / arg_words);
    }

    pub fn predCount(d: *const Draft) u32 {
        return @intCast(d.preds.items.len / pred_words);
    }

    pub fn pattern(d: *Draft, root: u32, preds: Run, at: u32, flags: u32) std.mem.Allocator.Error!void {
        try d.patterns.appendSlice(d.gpa, &.{ root, preds.off, preds.len, at, flags });
    }

    fn intern(d: *Draft, s: []const u8) std.mem.Allocator.Error!Run {
        const off: u32 = @intCast(d.text.items.len);
        try d.text.appendSlice(d.gpa, s);
        return .{ .off = off, .len = @intCast(s.len) };
    }

    /// The section's bytes. Free with `gpa.free`.
    pub fn finish(d: *const Draft) std.mem.Allocator.Error![]u8 {
        const c: Program.Counts = .{
            .patterns = @intCast(d.patterns.items.len / pattern_words),
            .steps = @intCast(d.steps.items.len / step_words),
            .refs = @intCast(d.refs.items.len),
            .captures = @intCast(d.captures.items.len / capture_words),
            .predicates = @intCast(d.preds.items.len / pred_words),
            .args = @intCast(d.args.items.len / arg_words),
            .text = @intCast(d.text.items.len),
        };
        const out = try d.gpa.alloc(u8, size(c));
        errdefer d.gpa.free(out);

        var at: usize = 0;
        for ([_]u32{
            tag,        revision, c.patterns, c.steps, c.refs,
            c.captures, c.predicates, c.args, c.text,  0,
        }) |v| {
            std.mem.writeInt(u32, out[at..][0..4], v, .little);
            at += 4;
        }
        for ([_][]const u32{
            d.patterns.items, d.steps.items,  d.refs.items,
            d.captures.items, d.preds.items, d.args.items,
        }) |table| {
            for (table) |v| {
                std.mem.writeInt(u32, out[at..][0..4], v, .little);
                at += 4;
            }
        }
        @memcpy(out[at..], d.text.items);
        return out;
    }
};
