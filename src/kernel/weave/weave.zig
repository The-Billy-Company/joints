//! The weave: a file held open, with its spine and its tree both maintained.
//!
//! The spine holds effects and the quire holds nodes, and until something owns
//! both there is no incremental parse - only two subsystems with a hyphen
//! between them. This is that something. It keeps the text, keeps a spine whose
//! leaves tile the file, keeps the tree, and answers one question: apply this
//! edit and give me both again.
//!
//! ## What a leaf is, and why it is a token
//!
//! A leaf covers the bytes from the end of the previous token to the end of
//! this one - whitespace, comments and all - and its element is the product of
//! every move the parse made while reading it: the folds the token triggered,
//! then the shift itself. Tokens are the finest grain that has an effect at all
//! (a byte does not), and the coarsest grain that still isolates a keystroke.
//!
//! The elements come from the parse's own move trail rather than from a second
//! walk of the automaton. That is not an optimisation, it is the difference
//! between a fact and a guess: `Cursor.run` re-explores every reading a state
//! and a token admit and hands back all of them, which is the right answer to
//! "what could this segment have done" and the wrong answer to "what did it
//! do". A parse knows. So it says (`gather.Move`), and a segment that would
//! have fanned into nine limbs is one element here.
//!
//! ## Where the re-mint window comes from, which is the question this owns
//!
//! `Effect.entry` pins a leaf to the state its run began in. So an edit that
//! changes the state at some offset invalidates every leaf downstream of it,
//! and an edit that does not changes nothing downstream at all. The spine is
//! safe either way - a mismatch composes to a refusal, never to a wrong tree -
//! so the only question is how far the minter should widen before it stops, and
//! the wrong answer re-mints a file to fix a comma. Two policies are
//! implemented and both are measured; see `Policy`.
//!
//! ## A lift is a read of a nonterminal, and nothing here knows the difference
//!
//! A lifted subtree is one move where a cold parse made hundreds. Two ways to
//! price it look plausible and only one is right. The tempting one is to ask
//! the previous spine for the product it already holds over exactly those
//! bytes; that was built, and it is wrong, because it prices the *inside* of
//! the subtree and the reduce that finishes it is not inside. It falls in the
//! next old leaf, so the lift silently drops a fold and the file's product
//! comes out one reduce short.
//!
//! What the parse did to the stack is push one symbol, from a known state,
//! over a known span. That is a shift of a nonterminal, so `distil` composes
//! `effect.shift` and does not branch: a lift is a read whose symbol happens
//! to be a nonterminal and whose span happens to be long. It costs one
//! composition rather than `log n`, needs nothing from the old spine, and
//! composes to the same file product a cold parse derives - the constituents
//! it did not push and the reduce it did not make cancel exactly.
//!
//! The tiling is therefore *not* a function of the bytes alone: a lift is one
//! leaf where a cold parse has many, and the fold that closes the subtree sits
//! on the other side of a seam. Both spines answer every product question the
//! same way; only the seams differ, which is why the fuzz holds the reuse path
//! to the tree and the file product, and holds a second weave with lifts
//! declined to the cold parse's leaves one element at a time.

const std = @import("std");
const g = @import("../../press/grammar.zig");
const lr0 = @import("../../press/lr0.zig");
const lalr = @import("../../press/lalr.zig");
const lex = @import("../lex/scanner.zig");
const effect = @import("../joint/effect.zig");
const jstack = @import("../joint/stack.zig");
const roster = @import("../joint/roster.zig");
const ledger = @import("../joint/ledger.zig");
const spine = @import("../spine/spine.zig");
const quire = @import("../quire/quire.zig");
const graft = @import("../quire/graft.zig");

pub const Joint = spine.Joint;
pub const Leaf = Joint.Leaf;
pub const Cut = Joint.Cut;
pub const Effect = effect.Effect;
pub const Move = quire.gather.Move;

/// How far to widen the re-mint window when an edit destabilises the entry
/// state. A cost decision, never a correctness one: every policy here produces
/// the same leaves, and they differ only in how many of them they derive again.
pub const Policy = enum {
    /// Stop at the first leaf standing where an old leaf stood, in the state
    /// that old leaf began in. From there rightward the two parses read the
    /// same bytes from the same state, so their elements are the same elements
    /// and the old ones stand. One integer comparison per candidate.
    snap,
    /// Stop only when the algebra says so: when the new prefix's product
    /// composes with the old suffix's. Strictly the more conservative of the
    /// two, because a composition demands the guard be satisfiable as well as
    /// the entry matching - and it is what a minter with no record of the old
    /// entry states is left with.
    prove,
    /// Re-derive everything from the first disturbed leaf. The baseline, and
    /// what an integration that never asked the question does by accident.
    whole,
};

/// A deliberate break, so the fuzz can be proved able to fail.
///
/// Every value but `none` is a bug somebody could plausibly write here, and a
/// harness that catches only the one it was designed against is not evidence.
/// They live on the type rather than in the test because each one is a single
/// decision this file makes, and a copy of `amend` that made them differently
/// would be proving the copy.
pub const Bend = enum {
    none,
    /// Land a lifted subtree one byte off. The bug a flat arena of absolute
    /// offsets invites, and one an s-expression cannot see at all.
    skew,
    /// Stop the re-mint window at the first old offset that still exists,
    /// asking nothing about whether the parse rejoined there: the policy
    /// question answered by never widening.
    deaf,
    /// Stand the resumed parse up one byte from where its kept stack was
    /// standing. `skew` for the prefix: the stack is a real stack and the
    /// state is a real state, and everything after it describes other bytes.
    adrift,
    /// Resume on the newest kept stack rather than the newest one below the
    /// edit. The bug of believing a snapshot because it exists, which reads
    /// the file as though the edit had not happened.
    trusting,
};

/// What one amend cost, in the units the claim is stated in.
pub const Cost = struct {
    /// Leaves the spine holds over the whole file.
    leaves: u32 = 0,
    /// The spine's height, which is what a one-for-one splice costs in
    /// compositions.
    height: u32 = 0,
    /// Where the re-mint window opened, which is not a policy: it is the first
    /// leaf whose bytes or element moved.
    at: u32 = 0,
    /// Leaves re-derived: the re-mint window, and the number a policy decides.
    minted: u32 = 0,
    /// Leaves whose old elements were kept untouched.
    kept: u32 = 0,
    /// Subtrees lifted out of the previous tree, and the bytes under them.
    lifts: u32 = 0,
    skipped: u32 = 0,
    /// Nodes copied to lift those subtrees. The flat arena's tax.
    carried: u32 = 0,
    /// Nodes in the tree that came out.
    nodes: u32 = 0,
    /// Stream entries this run actually moved over: the tokens it lexed, plus
    /// one for each subtree it lifted instead. The other half of what an edit
    /// costs, and the half reuse is for - a lift declines the ones after the
    /// edit, a resumed stack declines the ones before it.
    read: u32 = 0,
    /// Where the parse itself began: the byte the kept stack was standing at,
    /// or zero for one that started on the ground. This is the number that
    /// decides whether an edit at the bottom of a file costs the top of it.
    stood: u32 = 0,
};

/// The frame a weave is made on: one grammar, pressed once, and the interning
/// space its effects live in.
///
/// The pools are here rather than on the weave because an effect *is* three
/// indices into them. Two weaves over the same file with two sets of pools do
/// not merely waste memory - they cannot compare their answers at all, since
/// the same element is a different triple in each. So the intern space is a
/// property of the grammar, which is also how an editor holding several files
/// open would want it.
pub const Loom = struct {
    gpa: std.mem.Allocator,
    gr: *const g.Grammar,
    c: *const lr0.Collection,
    t: *const lalr.Tables,
    sc: *lex.Scanner,
    stacks: jstack.Pool,
    floors: roster.Pool,
    guards: ledger.Pool,

    pub fn init(
        gpa: std.mem.Allocator,
        gr: *const g.Grammar,
        c: *const lr0.Collection,
        t: *const lalr.Tables,
        sc: *lex.Scanner,
    ) Loom {
        return .{
            .gpa = gpa,
            .gr = gr,
            .c = c,
            .t = t,
            .sc = sc,
            .stacks = jstack.Pool.init(gpa),
            .floors = roster.Pool.init(gpa),
            .guards = ledger.Pool.init(gpa),
        };
    }

    pub fn deinit(l: *Loom) void {
        l.guards.deinit();
        l.floors.deinit();
        l.stacks.deinit();
        l.* = undefined;
    }

    pub fn arena(l: *Loom) effect.Arena {
        return .{ .stacks = &l.stacks, .floors = &l.floors, .guards = &l.guards, .c = l.c };
    }
};

pub const Weave = struct {
    gpa: std.mem.Allocator,
    loom: *Loom,
    gather: quire.Gather,

    text: std.ArrayList(u8),
    spine: Joint,
    /// The spine's leaves, kept beside it. Not a shadow for testing: the
    /// re-mint window is decided by comparing old leaves with new ones, and a
    /// tree can say what its leaves are but not what they were.
    leaves: std.ArrayList(Leaf),
    /// Where the parse stood at the start of each leaf, and where each leaf
    /// begins. Together they are what lets a policy align two parses.
    entries: std.ArrayList(u32),
    starts: std.ArrayList(u32),
    /// The alignment marks the next amend offers subtrees against.
    marks: std.ArrayList(graft.Mark),
    trail: std.ArrayList(Move),
    /// Stretches of the last parse's stack, so the next one can start in the
    /// middle of the file rather than at the top of it. See `bough.zig`.
    bough: quire.Bough,
    /// The previous parse's leaves, held across an amend.
    held: std.ArrayList(Leaf),
    held_at: std.ArrayList(u32),
    held_in: std.ArrayList(u32),

    tree: ?quire.Quire = null,
    policy: Policy = .prove,
    /// Whether finished subtrees are offered to the next parse. Off leaves the
    /// prefix resume on its own, which is the shape that re-reads every byte
    /// after the edit and so tiles the file exactly as a cold parse does; the
    /// fuzz holds that one to a cold parse segment for segment.
    reusing: bool = true,
    /// A deliberate break. `none` everywhere but the negative control.
    bend: Bend = .none,
    /// Whether the last parse's trail was usable. A forked parse has no single
    /// account of its own moves and a stopped one has no whole file, so the
    /// spine stands down rather than holding an element nobody made.
    spun: bool = false,
    cost: Cost = .{},

    pub fn init(gpa: std.mem.Allocator, loom: *Loom) !Weave {
        return .{
            .gpa = gpa,
            .loom = loom,
            .gather = try quire.Gather.init(gpa, loom.gr, loom.c, loom.t, loom.sc),
            .text = .empty,
            .spine = Joint.init(gpa),
            .leaves = .empty,
            .entries = .empty,
            .starts = .empty,
            .marks = .empty,
            .trail = .empty,
            .bough = .{ .gpa = gpa },
            .held = .empty,
            .held_at = .empty,
            .held_in = .empty,
        };
    }

    pub fn deinit(w: *Weave) void {
        if (w.tree) |*q| q.deinit();
        w.gather.deinit();
        w.spine.deinit();
        w.text.deinit(w.gpa);
        w.leaves.deinit(w.gpa);
        w.entries.deinit(w.gpa);
        w.starts.deinit(w.gpa);
        w.marks.deinit(w.gpa);
        w.trail.deinit(w.gpa);
        w.bough.deinit();
        w.held.deinit(w.gpa);
        w.held_at.deinit(w.gpa);
        w.held_in.deinit(w.gpa);
        w.* = undefined;
    }

    pub fn arena(w: *Weave) effect.Arena {
        return w.loom.arena();
    }

    /// Read a file cold. Everything an amend needs, from nothing.
    pub fn open(w: *Weave, text: []const u8) !void {
        w.text.clearRetainingCapacity();
        try w.text.appendSlice(w.gpa, text);
        _ = try w.rip(null);
        _ = try w.spine.build(w.arena(), w.leaves.items);
        w.cost = .{
            .leaves = @intCast(w.leaves.items.len),
            .height = w.spine.height(),
            .minted = @intCast(w.leaves.items.len),
            .nodes = @intCast(w.tree.?.nodes.len),
            .read = @intCast(w.gather.tokens.items.len),
        };
    }

    /// Apply an edit and hand back both halves, maintained.
    ///
    /// The tree is re-parsed with the old one on offer; the spine is spliced
    /// over the window the policy chose. Both describe the whole new text - the
    /// point is what they cost, not what they contain.
    pub fn amend(w: *Weave, cut: Cut, insert: []const u8) !void {
        std.debug.assert(cut.from <= cut.to and cut.to <= w.text.items.len);
        std.debug.assert(insert.len == cut.insert);

        try w.stow();
        try w.text.replaceRange(w.gpa, cut.from, cut.to - cut.from, insert);
        const delta = @as(i32, @intCast(cut.insert)) - @as(i32, @intCast(cut.to - cut.from));

        var old = w.tree;
        w.tree = null;
        defer if (old) |*q| q.deinit();
        // Two clauses, and the accepted-parse one is what a resume across a
        // break costs. It is a narrowing *on top of* `w.spun`: a mended parse
        // tiles the file perfectly well now that a hole is an element, and the
        // spine over that tiling verifies. What is not settled is standing a new
        // parse up on a tiling a break shaped, and two separate defects live
        // there. Both were found by widening this clause and reverting it.
        //
        // The first is a leaf. A run that walks into a wall is mid-derivation,
        // and the folds it had pending belong to it rather than to the hole - so
        // `distil` composes them onto the leaf before the hole. That leaf is
        // right for the file that broke and wrong for any later one that does
        // not, because it records a pop no parse of the fixed text makes. One
        // leaf, same bytes, same entry state, so the tree, the spans, the mend
        // count and the byte partition all still agree and only the product
        // disagrees. Clamping the window below the lowest such leaf fixes it and
        // keeps the win, since the leaf sits at the break rather than at the
        // edit; it is not here because with this clause narrow it is
        // unreachable, and a guard nothing can reach is worse than a note.
        //
        // The second is not diagnosed: resuming across a break leaves rust's
        // tiling short of the end of the file - `1297` of `1437` bytes on the
        // reproducer - which the first defect was masking, because the coverage
        // check runs before the product one. Different symptom, different check,
        // so presumed a different cause. Round 10 in
        // `.local/orchestrate/weave.report.md` has both.
        const offering = old != null and old.?.stop == .accepted and w.spun;
        var gr: ?graft.Graft = if (offering) .{
            .gpa = w.gpa,
            .old = &old.?,
            .marks = w.marks.items,
            .stable = cut.to,
            // A parse resuming at the last segment's start has no segment left
            // to resume into: the file's closing folds and its trailing bytes
            // are already folded into that one, so it is re-derived rather than
            // picked up. Below that, `cut.from` is the whole of the condition.
            .firm = @min(cut.from, w.starts.getLastOrNull() orelse 0),
            .ceiling = if (w.marks.items.len == 0) 0 else w.marks.items[w.marks.items.len - 1].start,
            .delta = delta,
            .lifting = w.reusing,
            .skew = if (w.bend == .skew) 1 else 0,
            .adrift = if (w.bend == .adrift) 1 else 0,
            .trusting = w.bend == .trusting,
        } else null;
        defer if (gr) |*it| it.deinit();

        const floor = try w.rip(if (gr) |*it| it else null);

        w.cost = .{
            .height = w.spine.height(),
            .lifts = if (gr) |it| it.lifts else 0,
            .skipped = if (gr) |it| it.skipped else 0,
            .carried = if (gr) |it| it.carried else 0,
            .nodes = @intCast(w.tree.?.nodes.len),
            .read = @intCast(w.gather.tokens.items.len - if (w.gather.stood) |r| r.token else 0),
            .stood = if (w.gather.stood) |r| r.at else 0,
        };
        if (!w.spun) {
            _ = try w.spine.build(w.arena(), w.leaves.items);
            w.cost.minted = @intCast(w.leaves.items.len);
            w.cost.leaves = w.cost.minted;
            return;
        }

        const win = try w.window(cut, delta, floor);
        w.cost.at = win.from;
        w.cost.minted = win.to - win.from;
        w.cost.kept = @as(u32, @intCast(w.held.items.len)) - (win.was - win.from);
        // Past the window the leaves are the old ones by decision, so the
        // shadow has to say the same thing the spine is about to be told.
        w.leaves.shrinkRetainingCapacity(win.to);
        w.entries.shrinkRetainingCapacity(win.to);
        w.starts.shrinkRetainingCapacity(win.to);
        for (w.held.items[win.was..], w.held_at.items[win.was..], w.held_in.items[win.was..]) |l, at, in| {
            try w.leaves.append(w.gpa, l);
            try w.starts.append(w.gpa, @intCast(@as(i64, at) + delta));
            try w.entries.append(w.gpa, in);
        }
        _ = try w.spine.replace(w.arena(), win.from, win.was, w.leaves.items[win.from..win.to]);
        w.cost.leaves = @intCast(w.leaves.items.len);
        w.cost.height = w.spine.height();
    }

    /// The maintained product of the whole file, or null when some pairing in
    /// it was refused.
    pub fn product(w: *const Weave) ?Effect {
        return w.spine.product();
    }

    /// The same answer computed the expensive way, for anything that has to
    /// check the cheap one.
    pub fn scratch(w: *Weave) !?Effect {
        var acc: ?Effect = .identity;
        for (w.leaves.items) |l| acc = try w.then(acc, l.element);
        return acc;
    }

    /// Set the previous parse's leaves aside, since deriving the new ones
    /// overwrites them and the window is the difference between the two.
    fn stow(w: *Weave) !void {
        w.held.clearRetainingCapacity();
        w.held_at.clearRetainingCapacity();
        w.held_in.clearRetainingCapacity();
        try w.held.appendSlice(w.gpa, w.leaves.items);
        try w.held_at.appendSlice(w.gpa, w.starts.items);
        try w.held_in.appendSlice(w.gpa, w.entries.items);
    }

    /// `from .. to` of the new leaves replaces `from .. was` of the old ones.
    const Window = struct { from: u32, to: u32, was: u32 };

    /// Which leaves the spine has to be told about, under the policy in force.
    ///
    /// The left edge is not a policy: it is the first leaf whose bytes or
    /// element moved, which can never be later than the leaf the cut opened in.
    /// The right edge is the whole question.
    ///
    /// `floor` is where the parse itself picked up. Leaves below it are not
    /// merely equal to the old ones, they *are* the old ones - no parse ran
    /// over those bytes - so the search for the first moved leaf starts there
    /// rather than at zero, and a keystroke stops paying for the file above it.
    fn window(w: *Weave, cut: Cut, delta: i32, floor: u32) !Window {
        const was = w.held.items;
        const now = w.leaves.items;
        var from: u32 = floor;
        while (from < was.len and from < now.len) : (from += 1) {
            if (w.held_at.items[from] >= cut.from) break;
            if (was[from].bytes != now[from].bytes) break;
            if (!Joint.same(was[from].element, now[from].element)) break;
        }
        const all: Window = .{ .from = from, .to = @intCast(now.len), .was = @intCast(was.len) };
        if (w.policy == .whole) return all;

        // The leaves below `from` are the same in both parses by definition, so
        // the head is a range query on the spine the old ones are still in -
        // `replace` has not run. A fold here would be the one place a keystroke
        // still cost the length of the file.
        var head: ?Effect = try w.spine.between(w.arena(), 0, from);

        var i = from;
        while (i < now.len) : (i += 1) {
            const back = @as(i64, w.starts.items[i]) - delta;
            if (back >= @as(i64, cut.to)) if (seek(w.held_at.items, @intCast(back))) |j| {
                const stops = if (w.bend == .deaf) true else switch (w.policy) {
                    // Tree-sitter's convergence test: the parse is in the state
                    // it was in, over bytes it has already read, so the rest
                    // must go the way it went. The fuzz says otherwise.
                    .snap => w.held_in.items[j] == w.entries.items[i],
                    // The same test, and then the algebra's: does the old
                    // suffix's *guard* still hold against the stack this head
                    // actually leaves? That is the question a state cannot
                    // answer, and the one that decides the answer.
                    //
                    // The spine still holds the old leaves here - `replace`
                    // has not run yet - so the suffix is a range query rather
                    // than a fold, which is what keeps a keystroke off the
                    // length of the file.
                    .prove => w.held_in.items[j] == w.entries.items[i] and
                        head != null and rejoins: {
                            const tail = try w.spine.between(w.arena(), @intCast(j), @intCast(was.len));
                            break :rejoins tail != null and
                                try effect.compose(w.arena(), head.?, tail.?) != null;
                        },
                    .whole => unreachable,
                };
                if (stops) return .{ .from = from, .to = i, .was = @intCast(j) };
            };
            head = try w.then(head, now[i].element);
        }
        return all;
    }

    inline fn then(w: *Weave, acc: ?Effect, e: Effect) !?Effect {
        return if (acc) |a| try effect.compose(w.arena(), a, e) else null;
    }

    /// Parse the text and derive everything that hangs off a parse: the tree,
    /// the leaves, the entry states, the alignment marks.
    fn rip(w: *Weave, gr: ?*graft.Graft) !u32 {
        w.gather.graft = gr;
        w.gather.bough = &w.bough;
        w.gather.trail = &w.trail;
        // Ownership moves in one step and nothing fallible runs between the
        // parse and the handover, so there is no window an `errdefer` would
        // cover - and one here would free a tree the weave still holds, which
        // is a double free rather than a cleanup.
        const q = try w.gather.run(w.text.items);
        if (w.tree) |*stale| stale.deinit();
        w.tree = q;

        // A resumed parse's trail, leaves and marks all begin where its stack
        // did, so everything below that point is what the last parse said and
        // is picked up rather than derived. The three arrays are indexed
        // differently - moves, segments, and tokens - which is why the ring
        // carries the trail's cut and the other two are found from it.
        const stood = w.gather.stood;
        const trail = if (stood) |r| r.trail else 0;
        const at = if (stood) |r| r.at else 0;
        var leaf: u32 = 0;
        if (stood) |r| {
            leaf = @intCast(seek(w.starts.items, r.at) orelse w.starts.items.len);
            w.marks.shrinkRetainingCapacity(r.token);
        } else w.marks.clearRetainingCapacity();

        // From the trail rather than from `enter`, because a mark's whole job
        // is to be compared against the state a later parse will do its goto
        // from, and that is the state a token was shifted from - which is what
        // the trail records and what `enter` deliberately does not.
        for (w.trail.items[trail..]) |m| switch (m) {
            .read => |r| try w.marks.append(w.gpa, .{ .start = r.from, .state = r.at }),
            // A mark past a mend is still a state a token was really shifted
            // from, so it is still a truthful thing to compare a later parse
            // against; a mend changes which states occur, not whether the
            // recorded one occurred.
            .fold, .mend => {},
        };
        w.leaves.shrinkRetainingCapacity(leaf);
        w.entries.shrinkRetainingCapacity(leaf);
        w.starts.shrinkRetainingCapacity(leaf);
        // Tiling the file and deriving one product for it are two claims, and
        // this makes them one. The tiling half is no longer the reason: a
        // mended parse tiles the file, because a hole is an element and
        // `distil` lays one over the bytes a mend stepped across. What is not
        // settled is that a *resumed* mended parse tiles it the way a cold one
        // does, so the whole claim stays until that does. Which leaf disagrees,
        // and why, is on `offering` above; dropping `accepted` here is the other
        // half of the same one-line change and the fuzz refuses the pair.
        w.spun = !w.gather.torn and q.stop == .accepted;
        if (!w.spun) {
            // The trail could not be replayed, so there is nothing to fold and
            // the leaves the prefix left behind describe a spine nobody is
            // going to be told about.
            w.leaves.clearRetainingCapacity();
            w.entries.clearRetainingCapacity();
            w.starts.clearRetainingCapacity();
            return 0;
        }
        try w.distil(trail, at);
        return leaf;
    }

    /// The move trail, folded into one element per token span.
    ///
    /// A composition here cannot be refused *within a run*: these are moves a
    /// parse actually made one after the other, so the pairing is one that
    /// happened. A refusal would mean the algebra disagrees with the parser
    /// about what the parser did, which is worth an error rather than a null.
    ///
    /// Between runs it is refused by construction, and that is the point. A
    /// mend is the parser saying these two runs were never adjacent, so the
    /// fold lays `Effect.hole` over the bytes it stepped across and starts the
    /// accumulator again. The spine then carries a real element on every node
    /// that sits entirely to one side of a break and the zero on every node
    /// that spans one, which is exactly the shape reuse needs: a subtree the
    /// break did not touch is still a subtree with an answer.
    fn distil(w: *Weave, from: u32, begin: u32) !void {
        const x = w.arena();
        var acc: Effect = .identity;
        var at: u32 = begin;

        for (w.trail.items[from..]) |mv| switch (mv) {
            .fold => |f| {
                const p = w.loom.gr.productions[f.prod];
                const e = try effect.reduce(x, f.under, p.rhs, p.lhs);
                acc = try effect.compose(x, acc, e) orelse return error.TrailRefused;
            },
            .read => |r| {
                acc = try effect.compose(x, acc, try effect.shift(x, r.at, r.symbol)) orelse
                    return error.TrailRefused;
                // A zero-width symbol is not a segment; it rides on the next
                // one that covers a byte, which keeps every leaf spendable.
                if (r.end == at) continue;
                try w.lay(at, acc, r.end - at);
                at = r.end;
                acc = .identity;
            },
            .mend => |m| {
                // Whatever the last run had going when it hit the wall is part
                // of that run and belongs to the leaf before the hole; the
                // hole itself covers only the bytes nothing read.
                if (if (acc.entry == Effect.nowhere) null else w.charge()) |last| {
                    last.element = try effect.compose(x, last.element, acc) orelse
                        return error.TrailRefused;
                }
                // A leaf covering no bytes has no place in the byte order, and
                // a mend always resumes past where the parse stood, so this
                // holds; the branch is here because "always" is a property of
                // two modules agreeing rather than of one.
                if (m.at > at) {
                    try w.lay(at, .hole, m.at - at);
                    at = m.at;
                } else if (w.leaves.items.len > 0) {
                    w.leaves.items[w.leaves.items.len - 1].element = .hole;
                }
                acc = .identity;
            },
        };

        if (w.leaves.items.len == 0) return;
        // The folds the end-of-input column fired belong to the file as much as
        // any others, and there is no token left to hang them on.
        if (acc.entry != Effect.nowhere) if (w.charge()) |last| {
            last.element = try effect.compose(x, last.element, acc) orelse
                return error.TrailRefused;
        };
        // And the bytes past the last token, which are whitespace by
        // definition: the spine tiles the file or it is not addressing it.
        // Unconditional where the folds above are not: a hole is not somewhere
        // to charge an element, but it is still a span, and the tiling has to
        // reach the end of the file whether or not the last thing in it is one.
        w.leaves.items[w.leaves.items.len - 1].bytes += @intCast(w.text.items.len - at);
    }

    /// The leaf a run's trailing folds belong to, when there is one.
    ///
    /// Null over an empty tiling, and null when the last thing laid was a hole
    /// - folds cannot be charged to bytes nobody read, and composing onto the
    /// zero is refused by the algebra rather than by a check here. The refusal
    /// would be correct and it would also be fatal, so the question is asked
    /// before it is put that way.
    inline fn charge(w: *Weave) ?*Joint.Leaf {
        if (w.leaves.items.len == 0) return null;
        const last = &w.leaves.items[w.leaves.items.len - 1];
        return if (last.element.entry == effect.Effect.broken) null else last;
    }

    inline fn lay(w: *Weave, at: u32, e: Effect, bytes: u32) !void {
        try w.starts.append(w.gpa, at);
        try w.entries.append(w.gpa, e.entry);
        try w.leaves.append(w.gpa, .{ .bytes = bytes, .element = e });
    }

};

/// Where an offset sits in a sorted list of them, exactly. Null when nothing
/// begins there, which for an alignment probe is the ordinary answer.
fn seek(at: []const u32, want: u32) ?usize {
    var lo: usize = 0;
    var hi: usize = at.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        if (at[mid] < want) lo = mid + 1 else hi = mid;
    }
    return if (lo < at.len and at[lo] == want) lo else null;
}

test {
    _ = @import("amend_test.zig");
}
