//! The parse stack: what a symbol standing on it holds, and how a stretch of it
//! is kept so a later parse can start in the middle of a file.
//!
//! The four small types are here rather than in `gather.zig` because the fifth
//! one is about keeping them, and a keeper that has to reach across a module
//! for the shape of the thing it keeps is a seam in the wrong place.
//!
//! ## Why a bough is worth keeping
//!
//! A parse of a two-megabyte file is two megabytes of lexing and a few hundred
//! thousand reductions, and an editor's most common edit is at the bottom of
//! the file its author is writing. Subtree reuse answers the half of that after
//! the edit; nothing answers the half before it, and that half is nearly all of
//! it. So an incremental parse that starts on the ground is incremental only
//! near the top, which is the opposite of where people type.
//!
//! Every perch below the first disturbed byte was raised out of bytes the edit
//! did not touch, by a chain that begins on the ground. Handing that chain to
//! the next parse puts it exactly where a cold parse of the new text would be
//! standing, having read exactly the tokens a cold parse would have read. See
//! the argument in `graft.zig`; this is its storage.
//!
//! ## What a ring is, and what it is not
//!
//! A ring is a whole snapshot, not a delta: the perch chain, the runs those
//! perches hold, and the high-water marks of everything the parse appends to.
//! Rings are taken every `stride` tokens, so a resume lands at most that many
//! tokens before the edit and the last stretch is re-read - which is the point,
//! since those are the tokens the edit could have changed the reading of.
//!
//! Storage is the whole cost, and it is bounded rather than tuned: when the
//! arrays pass `budget` the stride doubles and every other ring is dropped, so
//! a file twice as long is kept at the same bytes and twice the granularity.
//! That is the classic exponential-thinning trade, and the thing it protects is
//! the machine rather than the parse - a resume from a coarser ring is slower
//! and never wrong.
//!
//! Nothing here is consulted unless a graft says where the edit was. A cold
//! parse writes rings and reads none, and pays one bounds check per token for
//! it.

const std = @import("std");
const quire = @import("quire.zig");
const lex = @import("../lex/scanner.zig");

/// A child's place in its parent: the rename that applied at this site, and
/// the field it was filed under. Both are decided by the parent that reduced
/// over the child, so neither is a fact about the child itself.
pub const Mark = packed struct(u32) {
    field: u16 = none,
    alias: u16 = none,

    pub const none: u16 = std.math.maxInt(u16);
};

/// A run of children, and their places. The marks are only written where the
/// grammar declares a conflict; everywhere else they are spent on the spot and
/// this is one array.
pub const Run = struct {
    ref: std.ArrayList(quire.Ref) = .empty,
    mark: std.ArrayList(Mark) = .empty,

    pub const Slice = struct {
        ref: []const quire.Ref = &.{},
        mark: []const Mark = &.{},
    };

    pub fn deinit(r: *Run, gpa: std.mem.Allocator) void {
        r.ref.deinit(gpa);
        r.mark.deinit(gpa);
    }

    pub inline fn len(r: *const Run) u32 {
        return @intCast(r.ref.items.len);
    }

    pub inline fn clear(r: *Run) void {
        r.ref.clearRetainingCapacity();
        r.mark.clearRetainingCapacity();
    }

    pub inline fn shrink(r: *Run, n: u32) void {
        r.ref.shrinkRetainingCapacity(n);
        if (r.mark.items.len > n) r.mark.shrinkRetainingCapacity(n);
    }

    pub inline fn at(r: *const Run, from: u32, n: u32) Slice {
        return .{
            .ref = r.ref.items[from..][0..n],
            .mark = if (r.mark.items.len == 0) &.{} else r.mark.items[from..][0..n],
        };
    }

    pub inline fn all(r: *const Run) Slice {
        return r.at(0, r.len());
    }
};

/// One symbol on the stack: the state it put the parse in, the nodes it holds,
/// the extras read in front of it, and the bytes it covers.
pub const Perch = struct {
    state: u32,
    own: u32,
    owns: u32,
    lead: u32,
    leads: u32,
    start: u32,
    end: u32,
};

/// A perch's links, kept only while a grammar can fork at all: which perch it
/// stands on, and how far up it is. Both are the array index for the flat
/// stack the deterministic loop had.
pub const Stand = struct { down: u32, depth: u32 };

/// Stretches of a finished parse's stack, indexed by where in the file they
/// were standing.
pub const Bough = struct {
    gpa: std.mem.Allocator,
    rings: std.ArrayList(Ring) = .empty,
    /// The chains and the runs, packed end to end. A ring is a pair of slices
    /// into these, so one allocation holds a file's worth of snapshots and a
    /// resume is two `appendSlice` calls.
    perches: std.ArrayList(Perch) = .empty,
    refs: std.ArrayList(quire.Ref) = .empty,
    marks: std.ArrayList(Mark) = .empty,
    /// What those nodes looked like at the moment they were kept.
    ///
    /// The arena is append-and-backpatch, not append-only: a reduction writes
    /// a field, a rename and a parent into children that already exist, so the
    /// prefix of a finished parse's node array is not the prefix that parse had
    /// while it was standing here. Every node a later step can still write to
    /// is one the stack is holding - once a node is filed under a minted
    /// parent, nothing downstream names it again - so this array is exactly as
    /// long as `refs` and restoring it is what makes the resume honest. It is
    /// the whole of the difference between a stack and a snapshot of one.
    held: std.ArrayList(quire.Node) = .empty,
    /// What the scanner remembered here, for the grammars where that is not
    /// nothing: rust's nesting block comment, cpp's captured raw-string
    /// delimiter, python's column stack. One per ring and parallel to them,
    /// but left empty for a scanner with no casts at all - which is most of
    /// them, and is why a resume in json costs nothing for a field it does
    /// not use. See `lex.Scanner.Save`.
    saves: std.ArrayList(lex.Scanner.Save) = .empty,

    /// Tokens between rings, and the ceiling that doubles it.
    stride: u32 = 32,
    budget: u32 = 1 << 18,
    since: u32 = 0,

    /// Where one parse stood, and everything the next one needs to stand
    /// there. Byte offset and token index are the two coordinates a caller
    /// resumes in; the rest are high-water marks of arrays the parse appends
    /// to, which is all "restore" means for an array that only grows.
    pub const Ring = struct {
        at: u32,
        token: u32,
        trail: u32,
        nodes: u32,
        kids: u32,
        perch: u32,
        perched: u32,
        ref: u32,
        refed: u32,
        /// How many roots had been carried off the stack by the time this ring
        /// was taken. Zero while a parse runs clean, because a root only leaves
        /// the chain at a mend or at the end - which is exactly why a ring past
        /// a mend used not to be taken at all: the chain is no longer the whole
        /// tree, and a resume that restores only the chain drops everything the
        /// break already closed over. With the watermark the resume can adopt
        /// them from the old parse the same way it adopts its nodes.
        roots: u32 = 0,
        /// How many times the parse had mended when this ring was taken, so a
        /// resume picks up the count rather than reporting a recovered file as
        /// a clean one. `Quire.mends` is read by every consumer that has to
        /// tell "stopped here" from "stopped here and kept reading".
        mends: u32 = 0,
        /// And the bytes those mends walked past. Rides the ring for the same
        /// reason `mends` does, and for one more: the recovery fuse is
        /// denominated in this, so a resume that restarted the budget at zero
        /// would let a warm parse mend where a cold parse of the same bytes
        /// gave up. The fuzz compares the two every edit.
        skipped: u32 = 0,
    };

    pub fn deinit(b: *Bough) void {
        b.rings.deinit(b.gpa);
        b.perches.deinit(b.gpa);
        b.refs.deinit(b.gpa);
        b.marks.deinit(b.gpa);
        b.held.deinit(b.gpa);
        b.saves.deinit(b.gpa);
        b.* = undefined;
    }

    pub fn clear(b: *Bough) void {
        b.rings.clearRetainingCapacity();
        b.perches.clearRetainingCapacity();
        b.refs.clearRetainingCapacity();
        b.marks.clearRetainingCapacity();
        b.held.clearRetainingCapacity();
        b.saves.clearRetainingCapacity();
        b.since = 0;
    }

    /// One token has gone by. True when the next boundary is worth keeping.
    pub inline fn tick(b: *Bough) bool {
        b.since += 1;
        return b.since >= b.stride;
    }

    /// Keep this chain and its runs. `ring`'s slice fields are filled in here,
    /// since only the bough knows where they landed.
    pub fn keep(
        b: *Bough,
        ring: Ring,
        up: []const Perch,
        stack: Run.Slice,
        arena: []const quire.Node,
        memory: ?lex.Scanner.Save,
    ) !void {
        b.since = 0;
        var m = ring;
        m.perch = @intCast(b.perches.items.len);
        m.perched = @intCast(up.len);
        m.ref = @intCast(b.refs.items.len);
        m.refed = @intCast(stack.ref.len);
        try b.perches.appendSlice(b.gpa, up);
        try b.refs.appendSlice(b.gpa, stack.ref);
        try b.marks.appendSlice(b.gpa, stack.mark);
        for (stack.ref) |ref| try b.held.append(b.gpa, arena[ref]);
        if (memory) |sv| try b.saves.append(b.gpa, sv);
        try b.rings.append(b.gpa, m);
        if (b.perches.items.len + b.refs.items.len > b.budget) b.thin();
    }

    /// The last ring standing at or before `at`. Null when the edit is in front
    /// of every ring, which is an edit near the top of the file - the case that
    /// was already cheap.
    pub fn before(b: *const Bough, at: u32) ?u32 {
        var i = b.rings.items.len;
        while (i > 0) {
            i -= 1;
            if (b.rings.items[i].at <= at) return @intCast(i);
        }
        return null;
    }

    pub fn chain(b: *const Bough, i: u32) []const Perch {
        const r = b.rings.items[i];
        return b.perches.items[r.perch..][0..r.perched];
    }

    pub fn run(b: *const Bough, i: u32) Run.Slice {
        const r = b.rings.items[i];
        return .{
            .ref = b.refs.items[r.ref..][0..r.refed],
            .mark = if (b.marks.items.len == 0) &.{} else b.marks.items[r.ref..][0..r.refed],
        };
    }

    /// What the scanner remembered here. Null for a scanner that remembers
    /// nothing between tokens, where an offset is the whole of its state.
    pub fn save(b: *const Bough, i: u32) ?lex.Scanner.Save {
        return if (i < b.saves.items.len) b.saves.items[i] else null;
    }

    /// Those nodes as they stood, parallel to `run(i).ref`.
    pub fn borne(b: *const Bough, i: u32) []const quire.Node {
        const r = b.rings.items[i];
        return b.held.items[r.ref..][0..r.refed];
    }

    /// Drop every ring from `n` on, and the storage behind them. A resumed
    /// parse trims to just past the ring it stood on, since everything above it
    /// describes a file that no longer exists.
    pub fn trim(b: *Bough, n: u32) void {
        if (n >= b.rings.items.len) return;
        var perches: u32 = 0;
        var refs: u32 = 0;
        if (n > 0) {
            const cut = b.rings.items[n - 1];
            perches = cut.perch + cut.perched;
            refs = cut.ref + cut.refed;
        }
        b.rings.shrinkRetainingCapacity(n);
        if (b.saves.items.len > n) b.saves.shrinkRetainingCapacity(n);
        b.perches.shrinkRetainingCapacity(perches);
        b.refs.shrinkRetainingCapacity(refs);
        b.held.shrinkRetainingCapacity(refs);
        if (b.marks.items.len > refs) b.marks.shrinkRetainingCapacity(refs);
        b.since = 0;
    }

    /// Whether every ring is a snapshot the quire beside it could be resumed
    /// from. The falsifier a tree comparison structurally cannot be.
    ///
    /// A ring is not in the tree. It is a set of high-water marks plus a chain,
    /// and a resume reads it back as *the whole of what the parse was holding*
    /// below `at`: the roots a break already closed over, then each perch's
    /// lead extras and the nodes it owns. That sequence has to be a tiling -
    /// left to right, no node in it twice - because the next parse appends to
    /// it and hands the result out as a tree. A ring that carries one node in
    /// two of those places is a ring that resumes into a tree with the node
    /// twice, and *nothing about the parse that took the ring is wrong yet*:
    /// its own tree is fine, its own roots are fine, and it will compare equal
    /// to a cold parse. The damage is a generation later, in whatever stands
    /// back up here - which is why round 20 spent an edit stream looking for a
    /// defect two hundred edits downstream of the edit that shipped it.
    ///
    /// Spans come from `held` for the stack, because the arena is
    /// append-and-backpatch and those nodes were snapshotted before the writes
    /// that came after. Roots come from the arena, whose starts and lengths
    /// nothing past a mend rewrites.
    pub fn verify(b: *const Bough, gpa: std.mem.Allocator, q: *const quire.Quire) !void {
        var seen = try std.DynamicBitSet.initEmpty(gpa, q.nodes.len);
        defer seen.deinit();

        for (b.rings.items, 0..) |r, i| {
            if (r.nodes > q.nodes.len or r.kids > q.kids.len or r.roots > q.roots.len) {
                return fault(i, r, quire.none, "watermark past the end of the quire");
            }
            seen.setRangeValue(.{ .start = 0, .end = q.nodes.len }, false);
            const stack = b.run(@intCast(i));
            const held = b.borne(@intCast(i));
            if (stack.ref.len != held.len) return fault(i, r, quire.none, "held is not parallel to the run");

            var at: u32 = 0;
            // The roots first: a mend carried them off the chain, so they are
            // the left of everything the chain is still standing on.
            for (q.roots[0..r.roots]) |ref| {
                if (ref >= r.nodes) return fault(i, r, ref, "root above the ring's own arena");
                try step(&seen, &at, i, r, ref, q.nodes[ref]);
            }
            for (b.chain(@intCast(i))) |p| {
                for ([_][2]u32{ .{ p.lead, p.leads }, .{ p.own, p.owns } }) |span| {
                    if (span[0] + span[1] > stack.ref.len) return fault(i, r, quire.none, "perch run outside the kept stack");
                    for (stack.ref[span[0]..][0..span[1]], held[span[0]..][0..span[1]]) |ref, n| {
                        if (ref >= r.nodes) return fault(i, r, ref, "held node above the ring's own arena");
                        try step(&seen, &at, i, r, ref, n);
                    }
                }
            }
            if (at > r.at) return fault(i, r, quire.none, "the carry reaches past where the ring stands");
        }
    }

    /// One node of a ring's carry: it comes after everything before it, and it
    /// is not something the ring is already carrying somewhere else.
    fn step(
        seen: *std.DynamicBitSet,
        at: *u32,
        i: usize,
        r: Ring,
        ref: quire.Ref,
        n: quire.Node,
    ) !void {
        if (seen.isSet(ref)) return fault(i, r, ref, "carried twice by one ring");
        seen.set(ref);
        if (n.start < at.*) return fault(i, r, ref, "carried out of order");
        at.* = n.end();
    }

    fn fault(i: usize, r: Ring, ref: quire.Ref, why: []const u8) error{BoughCorrupt} {
        std.debug.print(
            "bough: {s} - ring {d} at byte {d} (token {d}, {d} nodes, {d} roots, {d} mends), node {d}\n",
            .{ why, i, r.at, r.token, r.nodes, r.roots, r.mends, ref },
        );
        return error.BoughCorrupt;
    }

    /// Halve the rings and double the stride, compacting the storage behind
    /// them. The newest is always kept, because it is the one nearest the edit
    /// anyone is about to make.
    fn thin(b: *Bough) void {
        b.stride *|= 2;
        var w: u32 = 0;
        var p: u32 = 0;
        var r: u32 = 0;
        const last = b.rings.items.len - 1;
        for (b.rings.items, 0..) |ring, i| {
            if (i % 2 == 1 and i != last) continue;
            var m = ring;
            std.mem.copyForwards(
                Perch,
                b.perches.items[p..][0..ring.perched],
                b.perches.items[ring.perch..][0..ring.perched],
            );
            std.mem.copyForwards(
                quire.Ref,
                b.refs.items[r..][0..ring.refed],
                b.refs.items[ring.ref..][0..ring.refed],
            );
            std.mem.copyForwards(
                quire.Node,
                b.held.items[r..][0..ring.refed],
                b.held.items[ring.ref..][0..ring.refed],
            );
            if (b.marks.items.len > 0) std.mem.copyForwards(
                Mark,
                b.marks.items[r..][0..ring.refed],
                b.marks.items[ring.ref..][0..ring.refed],
            );
            if (b.saves.items.len > i) b.saves.items[w] = b.saves.items[i];
            m.perch = p;
            m.ref = r;
            p += ring.perched;
            r += ring.refed;
            b.rings.items[w] = m;
            w += 1;
        }
        b.rings.shrinkRetainingCapacity(w);
        if (b.saves.items.len > w) b.saves.shrinkRetainingCapacity(w);
        b.perches.shrinkRetainingCapacity(p);
        b.refs.shrinkRetainingCapacity(r);
        b.held.shrinkRetainingCapacity(r);
        if (b.marks.items.len > r) b.marks.shrinkRetainingCapacity(r);
    }
};
