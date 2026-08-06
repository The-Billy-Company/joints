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
const assay = @import("irregex").assay;
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
    /// Which parse minted each leaf. Not needed to parse and not read by any
    /// policy: it is the one fact that tells a leaf derived beside its
    /// neighbour apart from a leaf retained past a re-parse of it, which is
    /// the difference between a lift that composes badly and a prefix that
    /// kept something it had no right to keep.
    gens: std.ArrayList(u32),
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
    held_gen: std.ArrayList(u32),

    tree: ?quire.Quire = null,
    /// Which parse this is. Only ever compared, never arithmetic: two leaves
    /// carrying the same one were derived by the same run.
    era: u32 = 0,
    /// Where the last parse picked up and where the last window opened, kept
    /// only so a failure can say whether the seam had room to move.
    lastfloor: u32 = 0,
    lastfrom: u32 = 0,
    lastto: u32 = 0,
    lastwas: u32 = 0,
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
    /// The lowest byte whose leaf absorbed folds a run had pending when it hit
    /// a wall. `maxInt` when there is no such leaf, which is every clean file.
    ///
    /// Those folds belong to the run rather than to the hole, so `distil`
    /// charges them onto the leaf before it - right for the file that broke,
    /// and wrong for any later one that does not, because the leaf then records
    /// a pop no parse of the fixed text makes. Nothing else can see it: same
    /// bytes, same entry state, so the tree, the spans, the mend count and the
    /// byte partition all agree and only the algebra objects. And it objects
    /// only sometimes, because a refusal is not absorbing - whether the bad
    /// pairing is *asked* depends on how the spine happens to be grouped, which
    /// is why it shows up as the maintained product disagreeing with a rebuild
    /// over its own leaves.
    ///
    /// So no window may stand above it. The win survives the clamp because the
    /// leaf sits at the break and the edit is somewhere else.
    frail: u32 = std.math.maxInt(u32),
    /// Why the last parse kept no tiling, when it kept none. Three sites clear
    /// it and they want different repairs - `off` is a resume that landed
    /// inside a leaf, `seam` is the prefix product refusing the first leaf the
    /// resume derived, `charge` is the resumed parse walling before it laid a
    /// leaf of its own so its folds fell on the previous parse's last one - and
    /// `spun` alone cannot tell them apart. Named because a count of cleared
    /// tilings without the reason is the same shape as the verdict
    /// `recover.py` was filing before round 8.
    unspun: enum { none, off, seam, charge, win } = .none,
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
            .held_gen = .empty,
            .gens = .empty,
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
        w.held_gen.deinit(w.gpa);
        w.gens.deinit(w.gpa);
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

        w.era += 1;
        try w.stow();
        try w.text.replaceRange(w.gpa, cut.from, cut.to - cut.from, insert);
        const delta = @as(i32, @intCast(cut.insert)) - @as(i32, @intCast(cut.to - cut.from));

        var old = w.tree;
        w.tree = null;
        defer if (old) |*q| q.deinit();
        // A broken file is resumed from, and that is the point: a hole is an
        // element, so a mended parse tiles the file and the spine over that
        // tiling verifies. This clause used to also demand the old parse was
        // accepted, which cost a keystroke the length of the file every time -
        // and the shape it cost it on is the common one, since typing something
        // broken and continuing to type is most of an editing session.
        //
        // Standing a new parse up on a tiling a break shaped hid three defects,
        // each found by widening this clause and reverting it, and all three
        // repairs are in the tree: `w.frail` clamps the window below a leaf
        // that absorbed a run's pending folds; `rip` declines a tiling it
        // cannot splice rather than keeping one that covers the same bytes
        // twice; and `rip` declines a resume whose first leaf the prefix
        // product refuses. Rounds 12 to 14 in
        // `.local/orchestrate/weave.report.md`.
        const offering = old != null and w.spun;
        var gr: ?graft.Graft = if (offering) .{
            .gpa = w.gpa,
            .old = &old.?,
            .marks = w.marks.items,
            .stable = cut.to,
            // A parse resuming at the last segment's start has no segment left
            // to resume into: the file's closing folds and its trailing bytes
            // are already folded into that one, so it is re-derived rather than
            // picked up. Below that, `cut.from` is the whole of the condition.
            // `w.frail` used to floor this too - the lowest byte whose leaf
            // absorbed a run's pending folds, so a resume could not stand above
            // a break. Round 19 measured it inert and dropped it: the fuzz's
            // every column is byte-identical with it in and out, because
            // `cut.from` already floors the resume below any wall the edit can
            // reach, and a ring inside the frail leaf is not a seam so `alight`
            // declines it anyway. It was costing the case it never protected -
            // an edit far above a break, which is most of an editing session.
            .firm = @min(cut.from, w.starts.getLastOrNull() orelse 0),
            .ceiling = if (w.marks.items.len == 0) 0 else w.marks.items[w.marks.items.len - 1].start,
            .seam = w.starts.items,
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
        // What the lift walk was offered against what it took. `passed` is the
        // whole question: candidates strictly wider than the one taken, since
        // the chain is ordered widest first. Zero means nothing wider was ever
        // nominated and the ceiling is nomination; a large number means the
        // ordering or the break is losing answers that were on the table.
        if (gr) |it| assay.trace(.weave, "lifts={d} taken={d}B widest={d}B offered={d} passed={d} (shape={d} goto={d} break={d}) asked={d} probes={d} turned(fork={d} align={d})\n", .{
            it.lifts,        it.taken,
            it.widest,       it.offered,
            it.passed,       it.passed_shape,
            it.passed_goto,  it.passed_break,
            it.asked,        it.probes,
            it.turned_fork,  it.turned_align,
        });
        if (!w.spun) {
            _ = try w.spine.build(w.arena(), w.leaves.items);
            w.cost.minted = @intCast(w.leaves.items.len);
            w.cost.leaves = w.cost.minted;
            return;
        }

        w.lastfloor = floor;
        // A refused window is a declined tiling, not a wider one. The leaves
        // are dropped rather than spliced, so the next amend re-tiles from a
        // cold parse: correct and slow, where a spliced seam that does not
        // compose would be fast and wrong.
        const win = try w.window(cut, delta, floor) orelse {
            w.spun = false;
            w.unspun = .win;
            w.leaves.clearRetainingCapacity();
            w.entries.clearRetainingCapacity();
            w.starts.clearRetainingCapacity();
            w.gens.clearRetainingCapacity();
            _ = try w.spine.build(w.arena(), w.leaves.items);
            w.cost.minted = 0;
            w.cost.leaves = 0;
            return;
        };
        w.lastfrom = win.from;
        w.lastto = win.to;
        w.lastwas = win.was;
        w.cost.at = win.from;
        w.cost.minted = win.to - win.from;
        w.cost.kept = @as(u32, @intCast(w.held.items.len)) - (win.was - win.from);
        // Past the window the leaves are the old ones by decision, so the
        // shadow has to say the same thing the spine is about to be told.
        w.leaves.shrinkRetainingCapacity(win.to);
        w.entries.shrinkRetainingCapacity(win.to);
        w.starts.shrinkRetainingCapacity(win.to);
        w.gens.shrinkRetainingCapacity(win.to);
        for (
            w.held.items[win.was..],
            w.held_at.items[win.was..],
            w.held_in.items[win.was..],
            w.held_gen.items[win.was..],
        ) |l, at, in, gen| {
            try w.leaves.append(w.gpa, l);
            try w.starts.append(w.gpa, @intCast(@as(i64, at) + delta));
            try w.entries.append(w.gpa, in);
            try w.gens.append(w.gpa, gen);
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
        w.held_gen.clearRetainingCapacity();
        try w.held.appendSlice(w.gpa, w.leaves.items);
        try w.held_at.appendSlice(w.gpa, w.starts.items);
        try w.held_in.appendSlice(w.gpa, w.entries.items);
        try w.held_gen.appendSlice(w.gpa, w.gens.items);
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
    fn window(w: *Weave, cut: Cut, delta: i32, floor: u32) !?Window {
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
            // A hole ends the search for a right edge, and ending the search
            // is not the same as declining the tiling.
            //
            // A hole is the zero: no product spanning it can say anything
            // about the run above it, so there is no rejoin left to prove and
            // every policy below is out of questions. Round 14 had only two
            // answers here and a hole was given the wrong one - `null`, which
            // drops the *whole* tiling including the prefix below the cut that
            // was never in doubt, so the next keystroke is cold. On json that
            // was 293 of 293 mended edits, and it is the common case rather
            // than a corner: a file being typed into is momentarily invalid
            // almost continuously.
            //
            // `all` is the third answer and it concedes exactly what the hole
            // costs: re-mint every leaf from `from` on, which is what `.whole`
            // does on every edit and which the fuzz holds to a cold parse.
            // Nothing above the break is kept, and nothing below `from` was in
            // question. Round 19 tried this and java refused it, returning a
            // tree with its leading `(block_comment)` twice - which round 21
            // located in `holds`, a ring probe leaving its own scan in the
            // extras list, one module away and reachable with no window
            // involved at all. With that repaired the same stream takes it.
            //
            // The distinction is the whole of the fix: `head == null` below is
            // a *seam* refusing - two runs the parse never put side by side -
            // and that is still a decline, because the tiling really is
            // unusable. Asking which of the two happened is the local question
            // this lane has now had to ask three times.
            if (now[i].element.entry == Effect.broken) return all;
            head = try w.then(head, now[i].element);
            // A null head is not "no stop found yet"; it is the opposite. The
            // leaves so far describe runs that were never adjacent, and every
            // policy above needs a head to ask its question with, so widening
            // rightward from here searches with the question already
            // unanswerable. Falling through to `all` looked like the safe
            // default and is the bug: it re-mints the whole suffix, keeps the
            // seam that refused, and reports a spine over a pairing no parse
            // made. The left edge is where the answer would be, and `from` is
            // already floored at the resume, so there is nothing to walk down
            // to; declining is what is left. Hazard named in round 14.
            if (head == null) {
                // No `hole=` here any more: a hole returned above, so every
                // refusal that reaches this line is a seam. The field was
                // carrying the distinction back when the code did not.
                assay.trace(.weave, "window refused at leaf {d} of {d}, entry={d}\n", .{
                    i, now.len, now[i].element.entry,
                });
                return null;
            }
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
        // A resume has to land on a seam of the old tiling, because that tiling
        // is what the leaves below it are: keeping leaves that reach past `r.at`
        // and then laying new ones from `r.at` covers those bytes twice, and a
        // spine addressing a file nobody has is silent - the product is still an
        // element, just the wrong one over the wrong bytes. Every token boundary
        // is a seam while a parse runs clean; a mend is where that stops, since
        // the bytes it steps over become one hole and the boundaries inside it
        // are no longer starts. `alight` prefers a seamed ring so this is rarely
        // paid, and when it is paid the tiling is dropped rather than doubled.
        var aligned = true;
        if (stood) |r| {
            if (seek(w.starts.items, r.at)) |k| {
                leaf = @intCast(k);
            } else aligned = false;
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
        w.gens.shrinkRetainingCapacity(leaf);
        w.starts.shrinkRetainingCapacity(leaf);
        // Every frail leaf is at or above the resume, because `firm` was held
        // under the lowest of them, so all of them have just been shrunk away.
        w.frail = std.math.maxInt(u32);
        // Tiling the file and deriving one product for it used to be one claim
        // here, and a mend forfeited both. Only the first is really at stake: a
        // mended parse tiles the file, because a hole is an element and
        // `distil` lays one over the bytes a mend stepped across, and the
        // product over that tiling is the zero exactly where it should be. So
        // what is left is whether the trail can be replayed at all, which is
        // `torn`, and whether the resume landed on a seam of the old tiling,
        // which is `aligned`. Whether a *resumed* mended parse composes is
        // asked below, once there is something to ask it about.
        w.spun = aligned and !w.gather.torn;
        // Four words, and they turned an inference into a fact: `spun=false`
        // alone cannot say whether the trail was unusable or the resume merely
        // landed off a seam, and those want different repairs. Naming the parse
        // verdict beside them is what showed that java and javascript are torn
        // on a *clean* parse - which is why an incremental path they have never
        // once been on never looked like a failure. Round 15.
        assay.trace(.weave, "spun={} aligned={} torn={} rifts={d} roosts={d} merges={d} rings={d} tokens={d} stood={d} roots={d} mends={d} stop={s}\n", .{
            w.spun,          aligned,
            w.gather.torn,   w.gather.rifts,
            w.gather.roosts, w.gather.merges,
            w.bough.rings.items.len, w.gather.tokens.items.len,
            if (stood) |r| r.at else 0,
            q.roots.len,     q.mends,
            @tagName(q.stop),
        });
        w.unspun = .none;
        if (!w.spun) {
            w.unspun = .off;
            // The trail could not be replayed, so there is nothing to fold and
            // the leaves the prefix left behind describe a spine nobody is
            // going to be told about.
            w.leaves.clearRetainingCapacity();
            w.entries.clearRetainingCapacity();
            w.gens.clearRetainingCapacity();
            w.starts.clearRetainingCapacity();
            return 0;
        }
        if (!try w.distil(trail, at, leaf)) {
            w.unspun = .charge;
            return w.shed();
        }
        // The resume is a claim that two runs were adjacent, and the algebra is
        // the only thing that checks it. `holds` proves the ring's stack is one
        // this text reaches; it does not prove the leaf below the ring can
        // stand under the leaf above it, and those are different questions once
        // a lift is involved: a lifted leaf's push is a coarse summary that was
        // a legal left operand for the leaf it was minted beside and need not
        // be one for a leaf derived later against a different suffix.
        //
        // Found by `Run.continuous`, which asks each adjacent pair on its own
        // rather than waiting for the whole product to give out. The seam it
        // named sat at `floor` every time - the resume boundary itself - so
        // there is no left edge to walk down and nothing to re-mint: below the
        // floor no parse ran. Declining is the only honest answer, and it is
        // the one `aligned` already gives an unspliceable tiling. Round 14 in
        // `.local/orchestrate/weave.report.md`.
        if (leaf > 0 and leaf < w.leaves.items.len) {
            // The prefix product rather than the leaf below, because that is
            // the question the spine will ask: whether everything already read
            // can stand under the first thing this parse derived. A neighbour
            // on its own is a narrower operand than the range a node folds, so
            // asking pairwise here would decline resumes the algebra accepts.
            const under = try w.spine.between(w.arena(), 0, leaf);
            const over = w.leaves.items[leaf].element;
            if (under != null and over.entry != effect.Effect.broken and
                try effect.compose(w.arena(), under.?, over) == null)
            {
                assay.trace(.weave, "seam refused: leaf={d} under.entry={d} over.entry={d}\n", .{
                    leaf, under.?.entry, over.entry,
                });
                w.unspun = .seam;
                return w.shed();
            }
        }
        return leaf;
    }

    /// Keep no tiling, and say so to the one caller that reads a leaf count.
    /// The reason is the caller's to set, because it is the only thing the two
    /// sites differ by.
    fn shed(w: *Weave) u32 {
        w.spun = false;
        w.leaves.clearRetainingCapacity();
        w.entries.clearRetainingCapacity();
        w.gens.clearRetainingCapacity();
        w.starts.clearRetainingCapacity();
        return 0;
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
    ///
    /// There is a third case neither sentence covers, and it is fatal only by
    /// accident. A run's trailing folds are charged onto the last leaf laid -
    /// and a *resumed* parse that walls before it has laid one charges them onto
    /// the last leaf of the parse before it, across the resume. Those two runs
    /// are claimed adjacent by the resume itself, so the composition has to
    /// hold; when it does not, what is false is the claim, not the parser's
    /// account of its own moves. `floor` is where this parse's own leaves begin,
    /// so a charge below it is that claim failing, and false is the answer -
    /// the same answer `aligned` gives a resume that landed off a seam. Raising
    /// would let a resume that merely cannot be spliced kill the process, which
    /// is what it did: verilog's keystroke at 20,086, one edit, `mend onto
    /// leaf` at the resume byte with nothing of its own laid yet.
    ///
    /// False means the tiling is gone. True does not mean it is good - the
    /// prefix product still has to accept the first leaf, which is the caller's
    /// next question.
    fn distil(w: *Weave, from: u32, begin: u32, floor: u32) !bool {
        const x = w.arena();
        var acc: Effect = .identity;
        var at: u32 = begin;

        for (w.trail.items[from..], from..) |mv, j| switch (mv) {
            .fold => |f| {
                const p = w.loom.gr.productions[f.prod];
                const e = try effect.reduce(x, f.under, p.rhs, p.lhs);
                acc = try effect.compose(x, acc, e) orelse return w.torn(j, at, "fold", acc, e);
            },
            .read => |r| {
                const e = try effect.shift(x, r.at, r.symbol);
                acc = try effect.compose(x, acc, e) orelse return w.torn(j, at, "read", acc, e);
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
                    last.element = try effect.compose(x, last.element, acc) orelse {
                        if (w.leaves.items.len <= floor) return w.snapped(j, at, "mend");
                        return w.torn(j, at, "mend onto leaf", last.element, acc);
                    };
                    w.frail = @min(w.frail, w.starts.items[w.leaves.items.len - 1]);
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

        if (w.leaves.items.len == 0) return true;
        // The folds the end-of-input column fired belong to the file as much as
        // any others, and there is no token left to hang them on.
        if (acc.entry != Effect.nowhere) if (w.charge()) |last| {
            const end: u32 = @intCast(w.trail.items.len);
            last.element = try effect.compose(x, last.element, acc) orelse {
                if (w.leaves.items.len <= floor) return w.snapped(end, at, "close");
                return w.torn(end, at, "close onto leaf", last.element, acc);
            };
        };
        // And the bytes past the last token, which are whitespace by
        // definition: the spine tiles the file or it is not addressing it.
        // Unconditional where the folds above are not: a hole is not somewhere
        // to charge an element, but it is still a span, and the tiling has to
        // reach the end of the file whether or not the last thing in it is one.
        w.leaves.items[w.leaves.items.len - 1].bytes += @intCast(w.text.items.len - at);
        return true;
    }

    /// The resume claimed two runs were adjacent and the algebra says otherwise.
    /// Not a fault of either side: see `distil`.
    fn snapped(w: *Weave, move: usize, at: u32, what: []const u8) bool {
        assay.trace(.weave, "resume snapped: move {d} of {d} at byte {d}: {s} fell across the resume\n", .{
            move, w.trail.items.len, at, what,
        });
        return false;
    }

    /// Say which pairing the algebra refused, then refuse.
    ///
    /// `error.TrailRefused` on its own is the least useful shape a fatal has:
    /// four call sites raise it, three of them mean "the parser did something
    /// the algebra says it could not have done" and one means "these two runs
    /// were never adjacent", and the error names neither the move nor the
    /// operands. A lane that reached one of them spent its afternoon bisecting
    /// keystrokes to find out which. The lens is `weave`, and the error is
    /// unchanged so nothing downstream reads a different failure.
    fn torn(w: *Weave, move: usize, at: u32, what: []const u8, left: Effect, right: Effect) error{TrailRefused} {
        assay.trace(.weave, "trail refused: move {d} of {d} at byte {d}: {s}," ++
            " left.entry={d} right.entry={d}, leaves={d} era={d}\n", .{
            move,             w.trail.items.len, at,   what,
            left.entry,       right.entry,       w.leaves.items.len,
            w.era,
        });
        return error.TrailRefused;
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
        try w.gens.append(w.gpa, w.era);
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
