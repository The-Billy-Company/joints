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
//! Three conditions, all cheap, and the last two are the ones that do the work:
//!
//!   1. The bytes under the node did not move relative to each other - it lies
//!      wholly after the edit, so the whole span shifts by one delta.
//!   2. The old parse read the symbol at that offset **standing in the state
//!      the new parse is standing in now**. That is the alignment mark, and it
//!      is the same predicate `Effect.entry` states: a run's meaning is a
//!      function of its bytes and of where it began.
//!   3. The scan the lift lands the parse in front of is the scan the old parse
//!      was in front of there. See below; for a scanner that remembers nothing
//!      this is free and always true.
//!
//! Given all three, the old derivation of those bytes is a derivation the new
//! parse could have made, so a goto on the node's symbol is a move the table
//! already allows. A `goto` that does not exist refuses the lift, and the parse
//! reads the bytes the ordinary way; nothing here can produce a wrong tree,
//! only a slower one.
//!
//! ## Why a state is not the whole of where a parse is standing
//!
//! Conditions 1 and 2 are the whole argument for a stateless lexer, and for
//! years they were the whole of this file, because "the meaning of a run is a
//! function of its bytes and its entry state" is true when the only entry state
//! is the table's.
//!
//! A scanner that remembers - html's stack of open tags, markdown's stack of
//! open blocks, python's column stack - has a second entry state, and a lift
//! **skips the bytes**, so it skips that scanner's answers over them and every
//! push and pop they carried. html is the shortest witness: an edit above
//! `</button>` lifts the whole `end_tag`, the `_end_tag_name` inside it is
//! never asked for, the pop it would have made never happens, and the parse
//! walks on with `button` still open. Nine bytes later a `</html>` finds a stack
//! that still owes a close and the scanner volunteers a zero-width
//! `_implicit_end_tag` a cold parse of the same bytes does not - a different
//! tree, from a lift both other conditions admitted.
//!
//! So the third condition is over the scan, and it is stated where the parse
//! lands rather than where it starts: **the scanner's memory now must be the
//! memory the old parse had in front of the token the lift lands on.** That is
//! sufficient on its own - it is exactly the premise the rest of the file
//! needs, that reading forward from here reads what reading forward from there
//! read - and it needs no assumption about how the span in between behaved.
//!
//! It costs a `u64` per token, which is what `Mark.stance` is. A balanced span
//! passes it: a whole `<div>…</div>` pushes and pops and leaves the stack where
//! it found it, so the wide lifts that pay for this machinery are the ones it
//! admits. A half-open one - a lone end tag, a block that opens and does not
//! close - is refused, and refusing is one ordinary re-read.

const std = @import("std");
const quire = @import("quire.zig");
const press = @import("../../press/press.zig");

/// Where the old parse stood when it read the symbol beginning here. Sorted by
/// `start`, which is what makes the lookup a binary search rather than a map.
pub const Mark = struct { start: u32, state: u32 };

/// Where the old parse's *scan* stood each time it was asked for a token, and
/// the offset it was asked at. Sorted by `at`, and one per token.
///
/// Keyed by where the scan resumed rather than by where the token turned out to
/// begin, because those differ by whatever extras stood in front of it and a
/// lift lands the next scan on the first of them. `word` is
/// `lex.Scanner.stance`, and it is zero throughout for every grammar whose
/// scanner remembers nothing between tokens.
///
/// Two fields and not one word, because the memory has two kinds of thing in
/// it. The states go in the hash, where all a reuse needs is to find them
/// unchanged. The one offset - where the hand's last answer with extent ended -
/// is kept plainly, because a reuse has to *move* it onto the new file's
/// coordinates the way it moves the offsets of every node it copies, and there
/// is no moving a hash. Zero is "no such answer yet", a state and not a place.
/// `wide` is whether the answer that ask returned covered any bytes. It is the
/// only thing in the ledger that is about the *parse* rather than the scan, and
/// it is here because it is the only place the fact survives: a node's span is
/// its visible extent, so a hidden zero-width terminal at the end of a
/// production widens nothing and leaves the tree unable to say whether the
/// answer standing at a node's end was inside that node or the next thing after
/// it. See `Bar.edge`.
pub const Stance = struct { at: u32, word: u64, since: u32 = 0, wide: bool = true };

pub const Graft = struct {
    gpa: std.mem.Allocator,
    /// Borrowed, and alive for the whole re-parse.
    old: *const quire.Quire,
    marks: []const Mark,
    /// Empty declines condition 3 by refusing every lift on a grammar whose
    /// scanner remembers something, and costs nothing on one that does not -
    /// which is what a caller with no record to offer wants either way.
    stances: []const Stance = &.{},
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
    /// Where the old tiling has its seams, ascending. A resume may only stand
    /// where one is: the spine is spliced leaf by leaf, so a stack picked up
    /// half way through a leaf leaves that leaf covering bytes the new parse is
    /// about to lay its own leaves over. Empty declines the check, which is
    /// what a caller with no tiling to protect wants.
    ///
    /// Every token boundary is a seam while a parse runs clean, so this costs
    /// nothing there. It bites where a mend has been: the bytes a mend steps
    /// over become one hole, the boundaries inside it stop being seams, and a
    /// ring taken at one of them is a resume the tiling cannot express.
    seam: []const u32 = &.{},
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
    /// Lifts that handed over a hidden symbol's children rather than one node.
    /// See `Verdict.spread`.
    spreads: u32 = 0,

    /// Why the walk did not take something wider than it took.
    ///
    /// A lift is only ever as good as the widest candidate `stoop` nominated,
    /// and there are exactly two ways for it to be small: the wide subtree was
    /// never on the chain, or it was on the chain and something refused it.
    /// These separate those, and they are the only way to know which fix the
    /// coverage problem wants. Read after the parse.
    /// Every call to `lift`, and what turned each one away before it ever
    /// reached a candidate. Counting only the probes that got past the gates
    /// is how an instrument reports a healthy walk over a file it barely
    /// looked at: 611 probes against 1383 tokens read says nothing about the
    /// 772 tokens that were never asked.
    asked: u64 = 0,
    turned_fork: u64 = 0,
    turned_align: u64 = 0,
    offered: u64 = 0,
    /// Candidates the walk passed over, at every probe and not only the ones
    /// that went on to lift. Scoping this to the lifting probes is the one
    /// thing it must not do: `lifts=0 passed=0` is then the reading for both a
    /// file that offered nothing and a file that offered thousands and refused
    /// every one, and telling those apart is the whole errand.
    passed: u64 = 0,
    /// What refused each of those: shape, then the table, then the break, then
    /// the two arms of the scan. Both scan arms are zero for every grammar whose
    /// scanner remembers nothing.
    ///
    /// `passed_stance` is condition 3 proper - the old parse stood somewhere at
    /// that offset and it was not here. A large number against a small `lifts`
    /// says the nodes on offer end where the memory moves, which is the tree's
    /// shape and not this check to look at.
    ///
    /// `passed_unasked` is the other arm, and it is not a disagreement: the old
    /// parse never asked the scanner anything at that offset, so there is no
    /// stance on record to vouch for one. It reads as a coverage problem in the
    /// ledger rather than a fact about the file, and a grammar whose every
    /// candidate lands here is one whose records are keyed on offsets the
    /// candidates never end at.
    ///
    /// `passed_edge` is the extent check that runs before either of those and
    /// for every grammar: the answer the resumed parse is about to be handed
    /// covered no bytes, so the tree cannot say whether the node already
    /// swallowed it. Expect it to be the whole story on grammars whose hidden
    /// terminals are zero-width - yaml blank lines, python and markdown
    /// dedents - and zero on grammars with none.
    passed_shape: u64 = 0,
    passed_goto: u64 = 0,
    passed_break: u64 = 0,
    passed_edge: u64 = 0,
    passed_stance: u64 = 0,
    passed_unasked: u64 = 0,
    /// `passed_shape` split by which shape fact refused it, since each asks for
    /// a different fix. Indexed by `Bar`.
    bars: [@typeInfo(Bar).@"enum".fields.len]u64 = @splat(0),
    /// Bytes in the widest candidate offered, over bytes actually taken. The
    /// gap is what a perfect ordering could still recover.
    widest: u64 = 0,
    taken: u64 = 0,

    const Step = struct { ref: quire.Ref, done: u32 };

    /// Whether the old tiling has a seam exactly here.
    pub fn seamed(gr: *const Graft, at: u32) bool {
        if (gr.seam.len == 0) return true;
        var lo: usize = 0;
        var hi: usize = gr.seam.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (gr.seam[mid] < at) lo = mid + 1 else hi = mid;
        }
        return lo < gr.seam.len and gr.seam[lo] == at;
    }

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

    /// Where the old parse's scan stood when it resumed at this new offset -
    /// the whole of condition 3, and null where the old parse never resumed
    /// here at all, which refuses, because a lift landing somewhere no scan
    /// resumed is landing somewhere the old parse cannot vouch for.
    ///
    /// The LAST ask at an offset, not the first, and the difference is the
    /// zero-width token. A hand answers where the cursor cannot move, so one
    /// offset can be asked several times - and every one of those answers but
    /// the last was consumed by the very node a lift is about to take whole.
    /// Python's `block` ends with a `_dedent` that costs no bytes: the node
    /// reads `[763, 883)` and the dedent it swallowed sits at 883, so the
    /// first ask there is *inside* the node and the scan that follows it is
    /// one level shallower than the scan in front of it. Anchoring on the
    /// first ask compared the lift against a moment the lift skips, admitted
    /// the take, and left the column stack one block too deep - which surfaced
    /// as an unexpected `_dedent` a hundred bytes later. The last ask is the
    /// one whose token the node does not contain, so it is the one the new
    /// parse is about to stand in.
    pub fn stance(gr: *const Graft, at: u32) ?Stance {
        const old = gr.back(at) orelse return null;
        var lo: usize = 0;
        var hi: usize = gr.stances.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (gr.stances[mid].at <= old) lo = mid + 1 else hi = mid;
        }
        if (lo == 0 or gr.stances[lo - 1].at != old) return null;
        return gr.stances[lo - 1];
    }

    /// Where the old parse's carried offset lands in this file, for a reuse
    /// about to jump the bytes between `from` and `to` in *old* coordinates.
    ///
    /// Three answers, and the third is the interesting one. Nothing carried is
    /// nothing to move, and it has to be nothing here too - a scan that has seen
    /// an answer with extent is not standing where one that has not is. An
    /// offset **inside** the span being jumped moves with the span, by the same
    /// delta every node in it moves by, and that is the case a reuse exists to
    /// serve: markdown's block ends with the line ending that closed it. An
    /// offset behind the span belongs to bytes this parse read for itself, so it
    /// asks for nothing and is only checked - `back` maps it, since the region it
    /// lives in may not be the region being jumped.
    pub fn moved(gr: *const Graft, rec: Stance, from: u32, to: u32, live: u32) ?u32 {
        if (rec.since == 0) return if (live == 0) 0 else null;
        if (rec.since >= from and rec.since <= to) {
            return @intCast(@as(i64, rec.since) + gr.delta + gr.skew);
        }
        const was = gr.back(live) orelse return null;
        return if (was == rec.since) live else null;
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
    /// ## Why the forest is refused, which is not because nobody finished it
    ///
    /// A mend leaves a forest, and this used to read as an unfinished descent:
    /// it enters at `roots[0]` and gives up when there is more than one root,
    /// and the roots are the same kind of run as a node's children - source
    /// order, no overlap, `Quire.survey` holds both to it - so picking the root
    /// that covers the offset is the same binary search as every step below.
    /// The refusal costs the whole suffix half of reuse on the 17 corpus
    /// grammars that mend: 11,606 probes across seven of them return an empty
    /// chain on one keystroke each.
    ///
    /// It was tried, and it is measured, and it is wrong. Descending the
    /// covering root turns lifts on across the forest and the speed is
    /// dramatic - 22 of 29 grammars faster, zig's keystroke 13,783us to 583us,
    /// html's 3,205us to 304us, the median gain over the mended set 1x to 3x.
    /// It also stops the amended tree being the tree a cold parse of the same
    /// bytes derives, on html (11 of 24 keystrokes), swift, verilog and lua,
    /// and the disagreement is in the **root count** - 2,974 amended against
    /// 2,971 cold on verilog, 215 against 220 on swift. A lift carried out from
    /// under one root and spliced into a parse whose mends fall elsewhere moves
    /// a hole's boundary, and a hole's boundary is where the roots are. The two
    /// conditions in the header are conditions on the *node*; nothing in them
    /// constrains the mend structure the node is being replanted into, and on a
    /// clean parse there is none to constrain.
    ///
    /// So the gate is load-bearing for correctness, and lifting across a forest
    /// needs the mend boundaries to be part of the offer - not a wider descent.
    /// `research/keystroke/` carries the measurement and the guard that caught
    /// it; `research/keystroke/abide.py` is the guard.
    pub fn stoop(gr: *Graft, at: u32) ![]const quire.Ref {
        gr.chain.clearRetainingCapacity();
        const old = gr.back(at) orelse return gr.chain.items;
        const q = gr.old;
        if (q.roots.len != 1) return gr.chain.items;

        var ref = holder(q, q.roots, old) orelse return gr.chain.items;
        while (true) {
            const n = q.nodes[ref];
            if (n.start == old) try gr.chain.append(gr.gpa, ref);
            ref = holder(q, q.kids[n.kids_at..][0..n.kids_len], old) orelse break;
        }
        return gr.chain.items;
    }

    /// Which of these siblings covers this offset, or none of them. They run in
    /// source order and do not overlap, which is what makes it a search; the
    /// gaps between them are the holes a mend stepped over, and an offset in
    /// one is held by nobody.
    fn holder(q: *const quire.Quire, kin: []const quire.Ref, old: u32) ?quire.Ref {
        var lo: usize = 0;
        var hi: usize = kin.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (q.nodes[kin[mid]].end() <= old) lo = mid + 1 else hi = mid;
        }
        if (lo == kin.len or q.nodes[kin[lo]].start > old) return null;
        return kin[lo];
    }

    /// Whether this node is a thing a parse can be handed rather than a thing a
    /// parse built for itself - and if it is, in which of the two ways, and if
    /// it is not, which of the three it is.
    ///
    /// The reason travels with the refusal because "the shape was wrong" is not
    /// a finding: `worn` is a fact about how the grammar names things and wants
    /// the grammar looked at, `high` is a fact about where the edit landed and
    /// wants nothing looked at, and `bare` is a fact about the size of what the
    /// tree offers here. They are different errands wearing one number.
    pub const Verdict = union(enum) {
        /// Hand over the node, under this symbol. The symbol is visible, so a
        /// parse reaching it makes exactly this one node and the adopting step
        /// only renames it.
        lift: press.Symbol,
        /// Hand over the node's *children*, under this symbol. The symbol is
        /// hidden, so a parse reaching it makes no node at all: it contributes
        /// the run its derivation built, and only a rename on the adopting step
        /// wraps that run in a node. The node in the old tree *is* such a
        /// wrapper, and whether there should be one here is the new parent's
        /// call - so give the parent the run and let it decide again. Which is
        /// also why a wrapper cannot be handed over whole: the parent would
        /// wrap it a second time.
        spread: press.Symbol,
        no: Bar,
    };

    /// A rename and a field are use-site facts written by the parent that
    /// reduced over it, so a node wearing either arrived at its name through a
    /// derivation this parse has not made yet. Both are re-decided by whoever
    /// adopts it, and the lift clears both rather than refusing - it can,
    /// because `Kind.under` carries the symbol the rename stands in front of.
    pub const Bar = enum {
        /// An extra: the grammar's `extras` put it there and no production asked
        /// for it, so there is no symbol to push it as.
        worn,
        /// Ends above the ceiling, so it is the end of the file and not a thing
        /// to be lifted into the middle of another parse.
        high,
        /// A leaf, or zero-width: lifting it saves one lex and costs one copy.
        bare,
    };

    pub fn liftable(gr: *const Graft, ref: quire.Ref) Verdict {
        const n = gr.old.nodes[ref];
        if (n.kind.extra) return .{ .no = .worn };
        if (n.start + n.len > gr.ceiling) return .{ .no = .high };
        if (n.kids_len == 0 or n.len == 0) return .{ .no = .bare };
        // A rename on a symbol that stands for itself is only a name, and the
        // new parent re-decides names anyway. On a hidden one the rename is the
        // node's whole reason to exist, so what carries over is what the hidden
        // symbol contributes, which is the children. See `Verdict.spread`.
        const sym = n.kind.under;
        if (n.kind.renamed and !gr.old.gr.shapeOf(sym).visible()) return .{ .spread = sym };
        return .{ .lift = sym };
    }
};
