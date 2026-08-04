//! What a previous parse leaves behind for the next one.
//!
//! An incremental re-parse is only cheaper than a cold one if it can decline to
//! do work, and there are exactly two things it can decline: re-lexing bytes
//! that did not move, and re-deriving nodes over them. A graft is the offer of
//! both - the old tree, the byte shift that maps it onto the new text, and the
//! states the old parse stood in while it read.
//!
//! ## Which half of the old stack is on offer
//!
//! A parse's stack is its past; its state is what it will do with the future.
//! An edit divides the file into a past that did not move and a future that
//! did, and the stack divides along the same line.
//!
//! The tempting move is the wrong half: keep the old perch chain from the
//! point the edit stopped mattering, and jump to the end. That is unsound. A
//! perch holds a run of finished nodes, and a reduction firing after the join
//! pops perches from *below* it - perches the edit changed. Every node the old
//! parse built by reducing across the join is a node over bytes that no longer
//! read that way.
//!
//! The other half is sound for exactly the mirrored reason. Every perch
//! standing below the first disturbed byte was raised by tokens the edit did
//! not touch, out of a state chain that begins on the ground. Nothing above it
//! is named inside it. So a parse handed that chain is standing where a cold
//! parse of the new bytes would be standing, and it has read the same tokens
//! to get there. That is `firm`, and it is why an edit at the bottom of a file
//! does not cost the top of it.
//!
//! A finished subtree is the same argument at a different granularity: it is
//! closed, so it can be lifted whole into a parse that reached the same state
//! at the same offset. Forking shares a stack because two readings disagree
//! about the future; reuse shares one because two parses agree about the past.
//! Prefix, subtree and fork are one mechanism seen three ways - a stretch of
//! stack is transferable exactly when nothing outside it can still name it.
//!
//! ## What makes a lift safe
//!
//! Two conditions, both cheap, and the second is the one that does the work:
//!
//!   1. The bytes under the node did not move relative to each other - it lies
//!      wholly after the edit, so the whole span shifts by one delta.
//!   2. The old parse read the symbol at that offset **standing in the state
//!      the new parse is standing in now**. That is the alignment mark, and it
//!      is the same predicate `Effect.entry` states: a run's meaning is a
//!      function of its bytes and of where it began.
//!
//! Given both, the old derivation of those bytes is a derivation the new parse
//! could have made, so a goto on the node's symbol is a move the table already
//! allows. A `goto` that does not exist refuses the lift, and the parse reads
//! the bytes the ordinary way; nothing here can produce a wrong tree, only a
//! slower one.

const std = @import("std");
const g = @import("../../press/grammar.zig");
const quire = @import("quire.zig");

/// Where the old parse stood when it read the symbol beginning here. Sorted by
/// `start`, which is what makes the lookup a binary search rather than a map.
pub const Mark = struct { start: u32, state: u32 };

pub const Graft = struct {
    gpa: std.mem.Allocator,
    /// Borrowed, and alive for the whole re-parse.
    old: *const quire.Quire,
    marks: []const Mark,
    /// The first old offset the edit did not disturb. Nothing below this is on
    /// offer, whatever the tree says.
    stable: u32,
    /// The first *new* offset the edit did disturb. Below it the two files are
    /// the same bytes, so a stretch of the old parse's stack that ended down
    /// there is a stretch this parse can stand back up on; see the header.
    /// Zero declines every resume, which is what a cold parse wants.
    firm: u32,
    /// The last old offset on offer, which is where the old parse's final token
    /// begins. The file's closing folds and its trailing bytes are gathered
    /// into whatever covers the end, so the end is not a thing that can be
    /// lifted into the middle of another parse.
    ceiling: u32,
    /// New offset minus old offset, for everything at or past `stable`.
    delta: i32,
    /// Whether finished subtrees are on offer as well as the prefix stack. The
    /// two halves of reuse are independent: declining lifts leaves a parse
    /// that reads every byte after the edit and none before it, which is the
    /// shape an oracle can be held to segment for segment.
    lifting: bool = true,
    /// Added to `delta` when a transcribed node is placed, and only then. Zero
    /// in every parse; a test sets it to prove the fuzz can see a lift that
    /// lands on the wrong bytes.
    skew: i32 = 0,
    /// Added to the byte offset a resumed parse stands back up at. Zero in
    /// every parse; `skew`'s twin for the prefix, and the same failure - a
    /// stack that is right about everything except where it is.
    adrift: i32 = 0,
    /// Resume on the last stretch of stack there is rather than the last one
    /// below `firm`, which is a resume that never checked the edit was in
    /// front of it. Never in a parse; the control for the refusal itself.
    trusting: bool = false,

    /// The nodes beginning at one offset, outermost first. Refilled per probe.
    chain: std.ArrayList(quire.Ref) = .empty,
    /// A transcription in progress: the descent, and the new refs of the nodes
    /// it has finished. Fields rather than locals so a file's worth of lifts
    /// allocates once.
    walk: std.ArrayList(Step) = .empty,
    made: std.ArrayList(quire.Ref) = .empty,

    /// What the reuse actually bought, which is the only reason to believe in
    /// it. Read after the parse.
    lifts: u32 = 0,
    /// Nodes carried over rather than derived.
    carried: u32 = 0,
    /// Bytes those nodes covered - the part of the file that was not re-lexed.
    skipped: u32 = 0,
    /// Offsets where a lift was considered. `lifts` over this is the hit rate.
    probes: u32 = 0,

    const Step = struct { ref: quire.Ref, done: u32 };

    pub fn deinit(gr: *Graft) void {
        gr.chain.deinit(gr.gpa);
        gr.walk.deinit(gr.gpa);
        gr.made.deinit(gr.gpa);
        gr.* = undefined;
    }

    /// Whether the old parse read a symbol at this new offset from this state.
    /// The whole of condition 2.
    pub fn aligned(gr: *const Graft, at: u32, state: u32) bool {
        const old = gr.back(at) orelse return false;
        var lo: usize = 0;
        var hi: usize = gr.marks.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (gr.marks[mid].start < old) lo = mid + 1 else hi = mid;
        }
        return lo < gr.marks.len and gr.marks[lo].start == old and gr.marks[lo].state == state;
    }

    /// The old offset a new one came from, or null when it came from the edit
    /// itself and has no old counterpart.
    pub fn back(gr: *const Graft, at: u32) ?u32 {
        const old = @as(i64, at) - gr.delta;
        if (old < gr.stable) return null;
        return @intCast(old);
    }

    /// Every old node beginning at this new offset, outermost first. The
    /// outermost is the biggest lift, and the caller walks inward only because
    /// the table may refuse the outermost's symbol here.
    pub fn stoop(gr: *Graft, at: u32) ![]const quire.Ref {
        gr.chain.clearRetainingCapacity();
        const old = gr.back(at) orelse return gr.chain.items;
        const q = gr.old;
        if (q.roots.len != 1) return gr.chain.items;

        var ref = q.roots[0];
        while (true) {
            const n = q.nodes[ref];
            if (old < n.start or old >= n.end()) break;
            if (n.start == old) try gr.chain.append(gr.gpa, ref);
            const kids = q.kids[n.kids_at..][0..n.kids_len];
            // Siblings are in source order and do not overlap, so the first
            // child that has not already ended is the one holding this offset.
            var lo: usize = 0;
            var hi: usize = kids.len;
            while (lo < hi) {
                const mid = lo + (hi - lo) / 2;
                if (q.nodes[kids[mid]].end() <= old) lo = mid + 1 else hi = mid;
            }
            if (lo == kids.len or q.nodes[kids[lo]].start > old) break;
            ref = kids[lo];
        }
        return gr.chain.items;
    }

    /// Whether this node is a thing a parse can be handed rather than a thing a
    /// parse built for itself.
    ///
    /// A rename and a field are use-site facts written by the parent that
    /// reduced over it, so a node wearing either arrived at its name through a
    /// derivation this parse has not made yet. The rename is the fatal one - it
    /// overwrites the symbol, so the node can no longer say what it is - and a
    /// field is merely re-decided by whoever adopts it, which is why the lift
    /// clears it rather than refusing.
    pub fn liftable(gr: *const Graft, ref: quire.Ref) ?g.Symbol {
        const n = gr.old.nodes[ref];
        if (n.kind.renamed or n.kind.extra) return null;
        if (n.start + n.len > gr.ceiling) return null;
        // A leaf is one token; lifting it saves one lex and costs one copy.
        if (n.kids_len == 0 or n.len == 0) return null;
        return @intCast(n.kind.index);
    }
};
