//! The word: a tree's parentheses held on the spine, so an edit does not
//! re-index the sheet.
//!
//! `sheet.zig` is static. Every query it answers reads immutable storage, and
//! the price of that is that a keystroke rebuilds the whole file: the rank
//! samples and the range min-max tree are both derived end to end. For a file
//! at rest that is the right trade and for a file being typed into it is not,
//! so this is the other half - the same parenthesis word under the same measure
//! (`spine.Excess`, and it really is the same one), maintained on the
//! monoid-annotated balanced tree M2 already lives on. An amend re-multiplies
//! the branches above the leaves it touched and nothing else.
//!
//! **What this is not, stated plainly.** Sadakane & Navarro's dynamic variant
//! puts the *bit string itself* into the leaves, so an insertion is `O(log n)`
//! end to end. `Tree(M)`'s leaf is `{ bytes, element }` and can hold a count and
//! a measure but not a block of bits, so the word here stays flat and an
//! insertion still shifts the tail. That is a real gap; `README.md` says what
//! closing it would cost and it is not papered over by calling this a dynamic
//! BP. What it does remove is the larger of the two costs - re-deriving the
//! index - leaving a `memmove` of raw bytes.
//!
//! One byte a parenthesis, which is deliberate rather than lazy. The packed
//! form is the sealed sheet's, and the storage that matters is what a file is
//! at rest in; what is maintained here is the *measure*, and eight bits a
//! parenthesis while you are typing is two bytes a node against the quire's
//! thirty-two. Bit-plumbing the editing form would buy nothing anyone is
//! waiting on and would cost the `memmove` its one virtue, which is that it is
//! a `memmove`.
//!
//! **An unbalanced word is a legal state here**, and that is the difference in
//! posture between the two halves. An editor passes through non-forests on the
//! way between forests - delete a `{` and the file is unbalanced until you type
//! the next one - so `amend` takes any run of the two letters and `balanced`
//! reports rather than refuses. The refusal lives at `seal`, where the static
//! structure is built and a non-forest genuinely has no meaning.

const std = @import("std");
const parens = @import("irregex").math.succinct.parens;
const spine = @import("../spine/spine.zig");
const sheet = @import("sheet.zig");

/// Parentheses to a leaf. Sized against the same cache line the static
/// structure scans - the flat tail `memmove` dominates an amend either way, so
/// this trades a slightly taller tree for a scan that stays in L1.
pub const block: u32 = 512;

pub const Word = struct {
    gpa: std.mem.Allocator,
    /// The word itself, flat. See the header for why this is not bits.
    run: std.ArrayList(u8),
    /// The measure over it, per block, on the spine.
    tree: spine.Bp,
    /// Scratch the minter hands back. Owned here because `Tree.edit` copies
    /// what a minter returns before it touches anything, which is exactly the
    /// contract a borrowed buffer needs.
    fresh: std.ArrayList(spine.Bp.Leaf),

    pub fn deinit(w: *Word) void {
        w.run.deinit(w.gpa);
        w.fresh.deinit(w.gpa);
        w.tree.deinit();
        w.* = undefined;
    }

    /// Lift a settled sheet back into an editable word. The shape survives; the
    /// ink does not, because the ink is the sheet's and an edit invalidates it.
    pub fn of(gpa: std.mem.Allocator, s: *const sheet.Sheet) !Word {
        var run: std.ArrayList(u8) = .empty;
        errdefer run.deinit(gpa);
        try run.ensureTotalCapacity(gpa, s.shape.bitLen());
        for (0..s.shape.bitLen()) |k| run.appendAssumeCapacity(if (s.shape.isOpen(k)) '(' else ')');
        return grow(gpa, run);
    }

    pub fn fromShape(gpa: std.mem.Allocator, letters: []const u8) !Word {
        try admit(letters);
        var run: std.ArrayList(u8) = .empty;
        errdefer run.deinit(gpa);
        try run.appendSlice(gpa, letters);
        return grow(gpa, run);
    }

    pub fn shape(w: *const Word) []const u8 {
        return w.run.items;
    }

    /// Parentheses, not nodes - the two differ by a factor of two only while
    /// the word is balanced, which is precisely when it is not interesting.
    pub fn count(w: *const Word) u32 {
        return @intCast(w.run.items.len);
    }

    /// One field read. The reason the spine is here.
    pub fn product(w: *const Word) spine.Excess {
        return w.tree.product() orelse spine.Excess.identity;
    }

    pub fn balanced(w: *const Word) bool {
        return w.product().balanced();
    }

    /// The excess after `k` parentheses: `O(log n)` down the spine to the leaf
    /// holding `k`, then a scan of at most one block.
    pub fn excess(w: *const Word, k: u32) !i32 {
        std.debug.assert(k <= w.count());
        const span = w.tree.touched(.{ .from = k, .to = k, .insert = 0 });
        const head = (try w.tree.between({}, 0, span.first)) orelse spine.Excess.identity;
        return head.total + measure(w.run.items[span.from..k]).total;
    }

    /// Replace `from .. to` with `replacement`. The flat run shifts; the tree
    /// re-mints only the blocks the cut disturbed.
    pub fn amend(w: *Word, from: u32, to: u32, replacement: []const u8) !void {
        std.debug.assert(from <= to and to <= w.count());
        try admit(replacement);
        // The tree is asked what a cut disturbs in terms of the word *after*
        // it, so the run moves first and `touched` reads the pre-edit tree.
        try w.run.replaceRange(w.gpa, from, to - from, replacement);
        const cut: spine.Bp.Cut = .{ .from = from, .to = to, .insert = @intCast(replacement.len) };
        _ = try w.tree.edit({}, cut, Mint{ .w = w });
    }

    /// Settle the word into the static structure. The only place a non-forest
    /// is refused, and `error.NonCanonical` is the refusal.
    pub fn seal(w: *const Word, gpa: std.mem.Allocator) !parens.Parens {
        return parens.Parens.fromShape(gpa, w.run.items);
    }

    /// The tree against the word, bottom-up. A debug instrument: a rebalance
    /// that dropped an annotation leaves a tree that still looks well-formed,
    /// and this is the only thing that catches it.
    pub fn verify(w: *const Word) !void {
        try w.tree.verify({});
        if (w.tree.bytes() != w.count()) return error.WordDriftedFromTree;
        if (!spine.Excess.eql(w.product(), measure(w.run.items))) return error.LostMeasure;
    }

    fn grow(gpa: std.mem.Allocator, run: std.ArrayList(u8)) !Word {
        var w: Word = .{ .gpa = gpa, .run = run, .tree = .init(gpa), .fresh = .empty };
        errdefer w.tree.deinit();
        errdefer w.fresh.deinit(gpa);
        const seeds = try w.chunk(0, @intCast(w.run.items.len));
        _ = try w.tree.build({}, seeds);
        return w;
    }

    /// The leaves covering `from .. to` of the current run. Blocks are cut from
    /// the range rather than from the file, so an amend leaves the boundaries
    /// around it where they were - the tree is a measure, not an alignment, and
    /// re-blocking the file to keep it tidy would cost `O(n)` to buy nothing.
    fn chunk(w: *Word, from: u32, to: u32) ![]const spine.Bp.Leaf {
        w.fresh.clearRetainingCapacity();
        var k = from;
        while (k < to) {
            const stop = @min(k + block, to);
            try w.fresh.append(w.gpa, .{ .bytes = stop - k, .element = measure(w.run.items[k..stop]) });
            k = stop;
        }
        return w.fresh.items;
    }

    const Mint = struct {
        w: *Word,

        pub fn mint(m: Mint, from: u32, to: u32) ![]const spine.Bp.Leaf {
            return m.w.chunk(from, to);
        }
    };
};

/// The measure of a run, scanned directly. The definition `compose` has to
/// agree with, and the oracle the property tests hold it to.
pub fn measure(run: []const u8) spine.Excess {
    var e: spine.Excess = .identity;
    for (run) |c| {
        e.total += if (c == '(') @as(i32, 1) else -1;
        e.min = @min(e.min, e.total);
        e.max = @max(e.max, e.total);
    }
    return e;
}

/// Two letters, and nothing else is a parenthesis word. Refused at the door
/// rather than silently measured as a close, because a third letter arriving
/// here means a caller built the word wrong and the measure would hide it.
fn admit(letters: []const u8) !void {
    for (letters) |c| if (c != '(' and c != ')') return parens.Parens.Error.NonCanonical;
}
