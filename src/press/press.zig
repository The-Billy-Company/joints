//! A grammar in, an automaton and its table out — the one entry point the rest
//! of the package builds tables through.
//!
//! There is a loop here, and it exists because LALR is not quite enough.
//!
//! Merging states that share an LR(0) kernel is what makes the collection
//! finite, and the merge is right nearly everywhere. Where it is wrong it is
//! wrong in exactly one way: two arrivals at the same kernel from different
//! contexts have their lookaheads unioned, so a cell is answered once for
//! contexts that want different answers.
//!
//! It shows up twice, and the second one is the dangerous one.
//!
//! **As a reduce/reduce residue.** C++ has two. `A<int>;` is a declaration whose
//! `template_type` folds to `type_specifier`; `template<> class A<int>;` is a
//! specialization whose `template_type` folds to `_class_name`. Both reach the
//! same kernel, both can be followed by `;`, and neither context admits the
//! other's fold. The grammar is not ambiguous. The state is. This one announces
//! itself: nobody declared the conflict, so it lands in the residue.
//!
//! **As a shift silently dropped.** C's `*p->q = 1` assigns through the pointer,
//! so after `* field_expression` the `=` must fold `field_expression` up to
//! `expression`; `p->q = 1` assigns to the field, so the same `=` must be read.
//! Both arrivals share a kernel. Merged, `=` joins the fold's lookahead, the
//! fold outranks the read (assignment carries a negative rank), and the read is
//! removed — from *both* contexts. Nothing is reported, because from inside the
//! merged state that is an author's precedence doing its job. The grammar then
//! cannot parse `p->q = 1`, which is not a subtle failure.
//!
//! The classical result that merging invents no shift/reduce conflict assumes
//! canonical LR(1) had none to begin with. Here it has one — in the `*` context,
//! where dropping the read is correct. Merging does not create the conflict; it
//! spreads its resolution to a context that never had it.
//!
//! So the signal is not "what is still contested" but "what is contested *only
//! because of the merge*": a terminal in a reduction's lookahead union that is
//! not in its intersection over the paths that reach it. `settle` records those
//! as frayed cells and this loop unfolds them — build, ask the lookaheads which
//! of a damaged state's arrivals actually disagree, build again with those kept
//! apart. The loop stops the first time a round does not improve, which on every
//! grammar tried is the second one.
//!
//! Building canonical LR(1) everywhere would answer both at once and cost an
//! order of magnitude in states for every grammar, including the ones that need
//! nothing. Undoing the merge where it is measured to be wrong pays only where
//! it is wrong.
//!
//! What is left after that is a grammar that really is ambiguous there, which is
//! a fact about the language and belongs in the report rather than in a bigger
//! automaton.

const std = @import("std");
const g = @import("grammar.zig");
const lalr = @import("lalr.zig");
const lr0 = @import("lr0.zig");
pub const inquest = @import("inquest.zig");

/// A ceiling on unfolding, not a schedule: the loop stops as soon as a round
/// fails to improve, and no grammar tried has improved twice. It stays above one
/// so that a grammar whose second automaton exposes a seam the first one hid can
/// still take it.
const rounds = 4;

/// How far the automaton may grow while unfolding, as a multiple of the
/// un-unfolded collection. Splitting a state clones its arrivals and everything
/// downstream of them, and a grammar with a thousand frayed cells can ask for
/// more automaton than the frayed cells are worth. The loop keeps the best
/// result it reached, so a refusal here costs accuracy in the report, never
/// correctness of the table.
///
/// Four, because it is the smallest multiple that fits the cut ruby stops on.
/// The plan is ordered by value, and a ceiling too low does not shorten the
/// automaton so much as truncate the plan: at two, ruby's ceiling forces `dare`
/// to halve twice, the 43-copy separation of `_nonlocal_variable` falls off the
/// end, and the grammar goes back to stopping at byte 136.
var growth: u32 = 4;

pub fn setGrowth(n: u32) void {
    growth = n;
}

/// Say what each round cost and bought, on stderr. Off unless a caller asks:
/// the loop is the part of the press whose behaviour is least obvious from its
/// output, and "why did this grammar not unfold" has no other answer.
var trace = false;

pub fn setTrace(on: bool) void {
    trace = on;
}

pub const Result = struct {
    collection: lr0.Collection,
    tables: lalr.Tables,
    /// How many times the automaton was unfolded. Zero is plain LALR, which is
    /// every grammar that has no reduce/reduce residue to begin with.
    unfolded: u32,

    pub fn deinit(r: *Result) void {
        r.tables.deinit();
        r.collection.deinit();
        r.* = undefined;
    }

    /// Whose wall a stopped parse is, decided from this table rather than by
    /// hand. See `inquest.zig` for the three arguments; a caller that can supply
    /// the fold chain the token drove gets a proof about that parse rather than a
    /// suspicion about the table.
    ///
    /// Here rather than exported beside `tables` because every caller already has
    /// the `Result` - the question is about a table, and asking it should not need
    /// a second import.
    pub fn whose(r: *const Result, wall: inquest.Wall) inquest.Finding {
        return inquest.over(&r.tables, wall);
    }

    /// Re-exported so a caller that can ask the question can also name it. A
    /// `Result` is the only thing an outside caller is handed, and a method whose
    /// argument type is unreachable from there is a method nobody can call.
    pub const Wall = inquest.Wall;
    pub const Finding = inquest.Finding;
};

pub fn tables(gpa: std.mem.Allocator, gr: *const g.Grammar) !Result {
    // The unfolding is read out of one automaton and handed to the next, so it
    // is copied into this arena rather than borrowed: the automaton that named a
    // kernel is usually the one being thrown away.
    var scratch = std.heap.ArenaAllocator.init(gpa);
    defer scratch.deinit();
    var plan: Plan = .{ .gpa = gpa, .a = scratch.allocator() };
    defer plan.deinit();

    var best: ?Result = null;
    errdefer if (best) |*b| b.deinit();
    var ceiling: u32 = 1 << 19;
    // How much of the plan this round dares use. Splitting is not additive:
    // unfolded states on a common path multiply, so a plan that is merely twice
    // as long can be an automaton fifty times the size. Rather than abandon the
    // round, drop back to the head of the plan — which is ordered by damage —
    // and take the unfolding that fits.
    var dare = plan.cuts.items.len;

    for (0..rounds + 1) |round| {
        var c = while (true) {
            break lr0.build(gpa, gr, .{
                .split = try plan.flatten(dare),
                .ceiling = ceiling,
            }) catch |e| switch (e) {
                error.Unsplittable => {
                    if (trace) {
                        std.debug.print("round {d}: {d} unfolded is past {d} states\n", .{
                            round, dare, ceiling,
                        });
                    }
                    if (dare == 0) return e;
                    dare /= 2;
                    continue;
                },
                else => return e,
            };
        };
        errdefer c.deinit();
        var t = try lalr.build(gpa, gr, &c);
        errdefer t.deinit();
        var round_result: Result = .{ .collection = c, .tables = t, .unfolded = @intCast(round) };

        if (best == null) {
            ceiling = @max(4096, growth * @as(u32, @intCast(round_result.collection.states.len)));
        }
        const now = try defects(gpa, &round_result);
        if (trace) {
            std.debug.print("round {d}: {d} states, {d} unfolded, residual {d}, contested {d}\n", .{
                round, round_result.collection.states.len, dare, now.residual, now.contested,
            });
        }
        const better = best == null or now.betterThan(try defects(gpa, &best.?));

        if (now.clean()) {
            if (best) |*b| b.deinit();
            return round_result;
        }

        // A round that gained nothing is where the search stops, because on all
        // eleven grammars it is also where the search stops gaining: every one
        // of them improves on the first unfolding and none of them improves on
        // any later one. What the later rounds do instead is pay - typescript
        // 9424 states to 27009, bash 7753 to 24572 - for a table that is
        // discarded, since the best one reached is what gets returned. A
        // disagreement the lookaheads cannot reach in one step is a disagreement
        // this shape of search does not reach at all.
        if (!better) {
            round_result.deinit();
            break;
        }

        const was = plan.cuts.items.len;
        try unfold(&plan, &round_result);
        if (best) |*b| b.deinit();
        best = round_result;
        if (plan.cuts.items.len == was) break;
        dare = plan.cuts.items.len;
    }
    return best.?;
}

/// The unfolding accumulated so far, one cut per kernel, ordered by the damage
/// that named it — because when the whole plan does not fit under the ceiling,
/// the head of it is what gets used.
///
/// A kernel is cut at most once. A later round may add kernels but never revise
/// one, which is what keeps the search monotone: every round's automaton is a
/// refinement of the last, so the seam a cut removed cannot come back and the
/// loop cannot chase its own tail.
const Plan = struct {
    gpa: std.mem.Allocator,
    /// Kernels and lane arrays live here, since they outlive the automaton that
    /// named them.
    a: std.mem.Allocator,
    cuts: std.ArrayList(Cut) = .empty,
    /// The same kernels by hash. A plan reaches thousands of cuts and every
    /// candidate asks whether it is already in one, so the answer has to be a
    /// lookup rather than a scan comparing item arrays: rust spent forty times
    /// its own press time in that scan.
    marks: std.AutoHashMapUnmanaged(u64, void) = .empty,

    const Cut = struct { kernel: []const lr0.Item, lanes: []const lr0.Lane };

    fn deinit(p: *Plan) void {
        p.cuts.deinit(p.gpa);
        p.marks.deinit(p.gpa);
    }

    fn mark(kernel: []const lr0.Item) u64 {
        return std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(kernel));
    }

    fn cutting(p: Plan, kernel: []const lr0.Item) bool {
        return p.marks.contains(mark(kernel));
    }

    /// Separate `kernel`'s arrivals as `lanes` says, addressing both ends by the
    /// kernel of the state rather than its id so the cut survives the rebuild
    /// that acts on it. Arrivals that share a kernel share a lane, taking the
    /// lower of the two: copies of one predecessor are one context as far as any
    /// later automaton can tell.
    fn cut(p: *Plan, c: *const lr0.Collection, kernel: []const lr0.Item, lanes: []const lalr.Seam.Lane) !void {
        const mine = try p.a.dupe(lr0.Item, kernel);
        var out: std.ArrayList(lr0.Lane) = .empty;
        defer out.deinit(p.gpa);
        var seen: std.AutoHashMapUnmanaged(u64, u32) = .empty;
        defer seen.deinit(p.gpa);
        for (lanes) |l| {
            const from = c.states[l.from].kernel;
            const slot = try seen.getOrPut(p.gpa, mark(from));
            if (slot.found_existing) {
                const at = &out.items[slot.value_ptr.*];
                at.lane = @min(at.lane, l.lane);
                continue;
            }
            slot.value_ptr.* = @intCast(out.items.len);
            try out.append(p.gpa, .{
                .kernel = mine,
                .from = try p.a.dupe(lr0.Item, from),
                .lane = l.lane,
            });
        }
        const owned = try p.a.dupe(lr0.Lane, out.items);
        if (trace) {
            var copies: u32 = 0;
            for (owned) |l| copies = @max(copies, l.lane + 1);
            std.debug.print("  cut {d} items, {d} arrivals -> {d} copies\n", .{
                mine.len, owned.len, copies,
            });
        }
        try p.cuts.append(p.gpa, .{ .kernel = mine, .lanes = owned });
        try p.marks.put(p.gpa, mark(mine), {});
    }

    /// The first `n` cuts as the one flat list `lr0.build` reads.
    fn flatten(p: Plan, n: usize) ![]const lr0.Lane {
        var total: usize = 0;
        for (p.cuts.items[0..n]) |c| total += c.lanes.len;
        const out = try p.a.alloc(lr0.Lane, total);
        var at: usize = 0;
        for (p.cuts.items[0..n]) |c| {
            @memcpy(out[at..][0..c.lanes.len], c.lanes);
            at += c.lanes.len;
        }
        return out;
    }
};

/// What is still wrong with a table that unfolding could fix. Both terms are
/// merge damage a reader can *see*: a reduce/reduce nobody declared, and a cell
/// where the invented permission was contested — a read deleted, or two folds
/// disagreeing.
///
/// Deliberately not `lalr.Tables.seams`, though those are named for splitting.
/// The uncontested seams outnumber the contested ones by two orders of magnitude
/// (ruby: 27548 cells against 347) and nearly all of them are harmless, so
/// ranking two automata by that count ranks noise. It was tried: judging by
/// seams put rust and c on a round whose seam count was lower and whose parse
/// was worse — rust 1006 bytes to 213. The count that discriminates is the one
/// that only rises when something was actually taken away.
fn defects(gpa: std.mem.Allocator, r: *const Result) !Defects {
    var out: Defects = .{ .residual = r.tables.tally().residual.reduce_reduce };

    // By kernel, not by state. Splitting makes copies, and damage in a state
    // that was copied five times is five cells describing one defect. Counted
    // per cell, unfolding looks like it made every grammar worse the moment it
    // made any grammar bigger — which is the search comparing two automata by
    // how much automaton they are.
    var seen: std.AutoHashMapUnmanaged(struct { u64, u32 }, void) = .empty;
    defer seen.deinit(gpa);
    for (r.tables.frayed) |f| {
        const kernel = r.collection.states[f.state].kernel;
        const key = .{ std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(kernel)), f.terminal };
        if ((try seen.getOrPut(gpa, key)).found_existing) continue;
        out.contested += 1;
    }
    return out;
}

/// Ordered, not summed. A reduce/reduce residue is a cell the report calls a
/// defect, so a round that trades one of those for any number of frayed cells
/// has made the table worse by the measure the table is judged on.
///
/// Splitting `read_dropped` out as a third term, ranked above the bulk count, was
/// tried on the reasoning that a token dying in its own cell is worse news than a
/// fold taken wrongly - and every wall this package can attribute to the press is
/// a `read_dropped` cell whose cut the plan already holds. It moved nothing: the
/// cut does not remove the cell. zig cuts seven kernels, one of them the 396
/// arrivals behind `struct_initializer`, reaches 1834 states, and reports
/// contested 2006 either way, so the round is discarded and the grammar returns
/// `unfolded 0`. Across the thirty it changed one automaton (scala, state 126 to
/// 144) and no grammar's reach. The reason is a level down, in `Plan.cut`:
/// arrivals that share a predecessor *kernel* share a lane, so when the
/// difference lives in the predecessor the partition cannot express it.
const Defects = struct {
    residual: u32 = 0,
    contested: u32 = 0,

    fn betterThan(a: Defects, b: Defects) bool {
        if (a.residual != b.residual) return a.residual < b.residual;
        return a.contested < b.contested;
    }

    fn clean(d: Defects) bool {
        return d.residual == 0 and d.contested == 0;
    }
};

/// Extend the plan with a cut for every damaged state the lookaheads can say
/// how to separate, best value first.
///
/// A state whose arrivals all draw the same lookahead is left alone, and that is
/// the whole discipline: splitting it would be a guess that its predecessors
/// differ where it did not. Guessing was tried - separate the state one arrival
/// apiece, and failing that its predecessors, walking the disagreement backwards
/// a goto per round. On all eleven grammars it bought two frayed cells and cost
/// three to five times the press: bash reached 24572 states against 7753, and
/// the refusing counts that motivate the whole exercise did not move at all
/// (ruby 104, bash 380, rust 35, either way). What the lookaheads cannot locate
/// in one step, a bigger automaton does not find.
fn unfold(plan: *Plan, r: *const Result) !void {
    const gpa = plan.gpa;

    // Whether this table has enough fixable damage to be worth guessing about.
    // The aim below licenses a cut on a merged lookahead nothing has contested,
    // on the evidence that one of its terminals is refused *somewhere*. That
    // evidence is only worth acting on where the refusals are the kind a cut can
    // reach: `open`, meaning a partition of the arrivals exists. A table whose
    // refusals are all `alone`, `stuck` or `agreed` cannot be improved by any
    // partition at any price, so every speculative copy it buys is a tax.
    //
    // Measured, per grammar rather than per cell, because per cell there is
    // nothing to read: go's single refusing cell *is* open, and the contested
    // cuts remove it either way - splitting spent 902 states on it and go stops
    // at the same byte with or without them. Ungated, that tax was go +75%
    // (1919 against 1095), python +82% (2913/1600) and typescript +22%
    // (11439/9338), all three for byte-identical reach and identical refusing
    // counts. c, cpp, ruby, rust and bash are untouched by the gate, and they
    // are the five that buy bytes.
    //
    // Five is a calibration, not a law, and the eleven make it auditable: plain
    // LALR leaves java, javascript, typescript and json at 0 open, go at 1 and
    // python at 3, then rust 10, cpp 140, c 67, ruby 47, bash 305. The widest
    // gap in that sample is 3 to 10 and the threshold sits inside it.
    const speculate = r.tables.floor().open >= 5;

    // Best value first, and the plan is a preference order rather than a set:
    // when the whole of it does not fit under the ceiling the head of it is what
    // gets used. Value is cells removed *per copy the cut costs*, because the
    // two are wildly uncorrelated — ruby's fatal state carries 137 invented
    // permissions and separates into 43 copies, while hundreds of one-cell seams
    // separate into 2. Ranking by damage alone spends the whole ceiling on the
    // expensive end of that list.
    var worth: std.AutoArrayHashMapUnmanaged(u32, Worth) = .empty;
    defer worth.deinit(gpa);
    for (r.tables.conflicts) |k| {
        if (k.class != .residual or k.kind != .reduce_reduce) continue;
        const slot = try worth.getOrPutValue(gpa, k.state, .{});
        slot.value_ptr.removes += 1;
        slot.value_ptr.contested += 1;
    }
    // A cell the merge invented *and* something contested is worth more of a
    // ceiling than the rest: the refusal is in that very cell rather than a few
    // states along, and it is the only kind a reader can see without knowing
    // what will be parsed. Their terminals are also the table's own evidence
    // about which inventions matter, which is what gates the rest.
    var refused: std.AutoHashMapUnmanaged(u32, void) = .empty;
    defer refused.deinit(gpa);
    for (r.tables.frayed) |f| {
        const slot = try worth.getOrPutValue(gpa, f.state, .{});
        slot.value_ptr.removes += if (f.harm == .read_dropped) 8 else 2;
        slot.value_ptr.contested += 1;
        if (f.harm == .read_dropped) try refused.put(gpa, f.terminal, {});
    }
    var lanes: std.AutoHashMapUnmanaged(u32, []const lalr.Seam.Lane) = .empty;
    defer lanes.deinit(gpa);
    for (r.tables.seams) |s| {
        if (s.lanes.len == 0) continue;
        const slot = try worth.getOrPutValue(gpa, s.state, .{});
        slot.value_ptr.removes += @intCast(s.over.len);
        for (s.lanes) |l| slot.value_ptr.copies = @max(slot.value_ptr.copies, l.lane + 1);
        // An uncontested invention is worth separating only where the table has
        // said, somewhere, that one of these very terminals gets refused. That
        // is the difference between ruby's fatal state - whose `\s+` is
        // uncontested here and refused further along the fold chain - and the
        // hundreds of states whose merged lookahead nothing anywhere objects to.
        // Unaimed, every one of those is a copy bought on spec: java 3298 states
        // and javascript 3144 became 1953 and 2229 under the aim, with identical
        // refusing counts, and the sweep against HEAD went from 9.5% smaller to
        // 18.1% smaller.
        //
        // A table with nothing refused therefore takes no speculative cuts at
        // all, which is the same statement read from the other end.
        //
        // Somewhere, rather than nearby, and that is not for want of trying to
        // localise it. Aiming at refusals *forward-reachable* from the seam
        // reads the automaton's arrows in the wrong direction, since taking an
        // invented fold pops back to an arrival: ruby fell to 1866 states and
        // stopped at byte 136 again. Aiming at the fold's own landing state -
        // pop to the arrival, goto on the folded head - is the relation the
        // parser actually follows, and it too dropped the one cut that matters
        // (4403 states, byte 136), while keeping the same 95 refusing cells the
        // 223-byte table has. Which is the lesson: it is not the count.
        if (slot.value_ptr.contested == 0) {
            if (!speculate) continue;
            for (s.over) |t| {
                if (!refused.contains(t)) continue;
                try lanes.put(gpa, s.state, s.lanes);
                break;
            }
        } else try lanes.put(gpa, s.state, s.lanes);
    }
    const states = worth.keys();
    const order = try gpa.alloc(u32, states.len);
    defer gpa.free(order);
    for (order, 0..) |*o, i| o.* = @intCast(i);
    std.mem.sort(u32, order, worth.values(), Worth.before);

    for (order) |i| {
        const separable = lanes.get(states[i]) orelse continue;
        const kernel = r.collection.states[states[i]].kernel;
        if (plan.cutting(kernel)) continue;
        try plan.cut(&r.collection, kernel, separable);
    }
}

/// What cutting one state buys and what it costs, so the plan can be ordered by
/// the ratio rather than by either half of it.
const Worth = struct {
    removes: u32 = 0,
    copies: u32 = 0,
    /// Cells here that something actually contested, as against invented and
    /// unremarked. Zero makes the cut speculative - see `unfold`.
    contested: u32 = 0,

    fn before(w: []const Worth, x: u32, y: u32) bool {
        // Cross-multiplied rather than divided, so the comparison is exact and a
        // state nobody could separate (zero copies) sorts by damage alone
        // against the same.
        const a = w[x];
        const b = w[y];
        return a.removes * @max(1, b.copies) > b.removes * @max(1, a.copies);
    }
};

const testing = std.testing;
// Test-only: the front end, for a proof that starts at `grammar.json` rather than
// at a `Builder` call, and `Forks`, which is the shape a parse consumes a
// contested cell in.
const import = @import("import.zig");
const settle = @import("settle.zig");

/// The smallest grammar that is LR(1) and not LALR(1), and the shape of C++'s
/// `A<int>;`.
///
/// After `p` and after `q`, both folds of `w` are pending, so both arrivals
/// have the kernel `{L -> w., R -> w.}` and LR(0) makes them one state. Merging
/// unions the lookaheads: `L` may be followed by `c` after `p` and by `d` after
/// `q`, and once that is one state both folds look legal on both terminals.
/// Neither context is actually ambiguous — the state is.
fn twoWaysIn(gpa: std.mem.Allocator) !g.Grammar {
    var b = g.Builder.init(gpa);
    defer b.deinit();
    const p = try b.intern("p", "p", .{ .literal = "p" });
    const q = try b.intern("q", "q", .{ .literal = "q" });
    const w = try b.intern("w", "w", .{ .literal = "w" });
    const c = try b.intern("c", "c", .{ .literal = "c" });
    const d = try b.intern("d", "d", .{ .literal = "d" });
    const start = try b.intern("$start", "$start", null);
    const s = try b.intern("S", "S", null);
    const l = try b.intern("L", "L", null);
    const r = try b.intern("R", "R", null);
    try b.addProduction(start, &.{s}, &.{});
    try b.addProduction(s, &.{ p, l, c }, &.{});
    try b.addProduction(s, &.{ p, r, d }, &.{});
    try b.addProduction(s, &.{ q, l, d }, &.{});
    try b.addProduction(s, &.{ q, r, c }, &.{});
    try b.addProduction(l, &.{w}, &.{});
    try b.addProduction(r, &.{w}, &.{});
    return b.finish("two-ways-in", start, &.{}, &.{});
}

test "an lalr merge artifact is unfolded away" {
    var gr = try twoWaysIn(testing.allocator);
    defer gr.deinit();

    // Plain LALR merges the two arrivals at `w` and reports the conflict.
    var flat = try lr0.build(testing.allocator, &gr, .{});
    defer flat.deinit();
    var merged = try lalr.build(testing.allocator, &gr, &flat);
    defer merged.deinit();
    try testing.expect(merged.tally().residual.reduce_reduce > 0);

    var out = try tables(testing.allocator, &gr);
    defer out.deinit();
    try testing.expectEqual(@as(u32, 0), out.tables.tally().residual.reduce_reduce);
    try testing.expectEqual(@as(u32, 1), out.unfolded);
    // Paid for by exactly the one state the conflict needed.
    try testing.expectEqual(flat.states.len + 1, out.collection.states.len);
}

test "a grammar with nothing to unfold is not unfolded" {
    // `R -> w` removed, so `w` has one reading and the merge costs nothing.
    var b = g.Builder.init(testing.allocator);
    defer b.deinit();
    const p = try b.intern("p", "p", .{ .literal = "p" });
    const w = try b.intern("w", "w", .{ .literal = "w" });
    const e = try b.intern("e", "e", .{ .literal = "e" });
    const start = try b.intern("$start", "$start", null);
    const s = try b.intern("S", "S", null);
    const l = try b.intern("L", "L", null);
    try b.addProduction(start, &.{s}, &.{});
    try b.addProduction(s, &.{ p, l, e }, &.{});
    try b.addProduction(l, &.{w}, &.{});
    var plain = try b.finish("plain", start, &.{}, &.{});
    defer plain.deinit();

    var out = try tables(testing.allocator, &plain);
    defer out.deinit();
    try testing.expectEqual(@as(u32, 0), out.unfolded);

    var flat = try lr0.build(testing.allocator, &plain, .{});
    defer flat.deinit();
    try testing.expectEqual(flat.states.len, out.collection.states.len);
}

test "a genuine ambiguity is left alone rather than unfolded forever" {
    // Both folds are reachable from the *same* context, so no amount of
    // splitting separates them. The loop must notice and stop.
    var b = g.Builder.init(testing.allocator);
    defer b.deinit();
    const w = try b.intern("w", "w", .{ .literal = "w" });
    const e = try b.intern("e", "e", .{ .literal = "e" });
    const start = try b.intern("$start", "$start", null);
    const s = try b.intern("S", "S", null);
    const l = try b.intern("L", "L", null);
    const r = try b.intern("R", "R", null);
    try b.addProduction(start, &.{s}, &.{});
    try b.addProduction(s, &.{ l, e }, &.{});
    try b.addProduction(s, &.{ r, e }, &.{});
    try b.addProduction(l, &.{w}, &.{});
    try b.addProduction(r, &.{w}, &.{});
    var gr = try b.finish("ambiguous", start, &.{}, &.{});
    defer gr.deinit();

    var out = try tables(testing.allocator, &gr);
    defer out.deinit();
    try testing.expect(out.tables.tally().residual.reduce_reduce > 0);
    var flat = try lr0.build(testing.allocator, &gr, .{});
    defer flat.deinit();
    // Kept the smaller automaton: the round that split it gained nothing.
    try testing.expectEqual(flat.states.len, out.collection.states.len);
}

/// C's `p->q = 1`, reduced to the six productions that break it.
///
/// `asn -> f = e` reads the `=` after an `f`; `e -> f` folds it. In a statement
/// the fold can only be followed by `;`, so there is no contest and the `=` is
/// read. Under a `*` the fold can be followed by `=` too — `* f = e` assigns
/// through the pointer, so `e` there really can precede an `=` — and because
/// `e -> asn` puts `asn` in the closure under the `*` as well, both arrivals
/// reach the same kernel and LR(0) makes them one state.
///
/// Merged, the fold is legal on `=` and outranks the read, whose step carries
/// the negative rank an assignment carries in every C-family grammar. The read
/// is deleted from a state that both contexts share, and the statement is no
/// longer a sentence of the language.
fn assignsThroughAPointer(gpa: std.mem.Allocator) !g.Grammar {
    var b = g.Builder.init(gpa);
    defer b.deinit();
    const id = try b.intern("id", "id", .{ .literal = "id" });
    const eq = try b.intern("=", "=", .{ .literal = "=" });
    const star = try b.intern("*", "*", .{ .literal = "*" });
    const semi = try b.intern(";", ";", .{ .literal = ";" });
    const start = try b.intern("$start", "$start", null);
    const stmt = try b.intern("stmt", "stmt", null);
    const e = try b.intern("e", "e", null);
    const asn = try b.intern("asn", "asn", null);
    const deref = try b.intern("deref", "deref", null);
    const f = try b.intern("f", "f", null);

    const low: g.Step = .{ .prec = .{ .level = -2 } };
    try b.addProduction(start, &.{stmt}, &.{});
    try b.addProduction(stmt, &.{ e, semi }, &.{});
    try b.addProduction(asn, &.{ f, eq, e }, &.{ low, low, low });
    try b.addProduction(asn, &.{ deref, eq, e }, &.{ low, low, low });
    try b.addProduction(deref, &.{ star, e }, &.{});
    try b.addProduction(e, &.{f}, &.{});
    try b.addProduction(e, &.{deref}, &.{});
    try b.addProduction(e, &.{asn}, &.{});
    try b.addProduction(f, &.{id}, &.{});
    return b.finish("assign", start, &.{}, &.{});
}

test "a read that precedence deleted from a context that never contested it" {
    var gr = try assignsThroughAPointer(testing.allocator);
    defer gr.deinit();

    // Plain LALR: the merged state answers `=` with a fold, and says nothing
    // about it — precedence resolved the cell, so it is not a conflict. The one
    // record of the damage is that the fold's lookahead is context-dependent.
    var flat = try lr0.build(testing.allocator, &gr, .{});
    defer flat.deinit();
    var merged = try lalr.build(testing.allocator, &gr, &flat);
    defer merged.deinit();
    try testing.expectEqual(@as(u32, 0), merged.tally().residual.total());

    var refused: u32 = 0;
    for (merged.frayed) |x| {
        if (x.harm == .read_dropped) refused += 1;
    }
    try testing.expect(refused > 0);
    // Every state that can read `=` has had that read taken away.
    for (flat.states, 0..) |st, q| {
        for (st.edges) |edge| {
            if (edge.symbol != eqOf(&gr)) continue;
            try testing.expect(merged.at(@intCast(q), eqOf(&gr)).kind != .shift);
        }
    }

    // Unfolded: the contexts are separated, and `id = id ;` is a sentence again.
    var out = try tables(testing.allocator, &gr);
    defer out.deinit();
    try testing.expect(out.unfolded > 0);
    var reads: u32 = 0;
    for (0..out.collection.states.len) |q| {
        if (out.tables.at(@intCast(q), eqOf(&gr)).kind == .shift) reads += 1;
    }
    try testing.expect(reads > 0);
    for (out.tables.frayed) |x| try testing.expect(x.harm != .read_dropped);
}

test "a reading the author ranked below the fold stops being the primary" {
    // The shape of c's `long total;`: after `a`, the state can read `x` to
    // finish `S -> a x`, or fold `A -> a` and read it as `S -> A x`. Nothing
    // static separates them, so the table takes the read - unless the author
    // ranked that reading below, which is what `prec.dynamic(-1, …)` says.
    for ([_]i16{ 0, -1 }) |rank| {
        var b = g.Builder.init(testing.allocator);
        defer b.deinit();
        const a = try b.intern("a", "a", .{ .literal = "a" });
        const x = try b.intern("x", "x", .{ .literal = "x" });
        const start = try b.intern("$start", "$start", null);
        const s = try b.intern("S", "S", null);
        const nt = try b.intern("A", "A", null);
        try b.addProduction(start, &.{s}, &.{});
        try b.addProduction(s, &.{ nt, x }, &.{});
        try b.addProductionDynamic(s, &.{ a, x }, &.{}, rank);
        try b.addProduction(nt, &.{a}, &.{});
        var gr = try b.finish("ranked", start, &.{}, &.{&.{ s, nt }});
        defer gr.deinit();

        var flat = try lr0.build(testing.allocator, &gr, .{});
        defer flat.deinit();
        var built = try lalr.build(testing.allocator, &gr, &flat);
        defer built.deinit();

        // Whichever way it lands, both readings still stand: a rank orders a
        // fork, it never resolves one.
        var forked = false;
        for (built.conflicts) |k| {
            if (k.terminal != x) continue;
            forked = true;
            const led: lalr.Action.Kind = if (rank < 0) .reduce else .shift;
            try testing.expectEqual(led, built.at(k.state, x).kind);
            try testing.expectEqual(led, k.chosen.kind);
            try testing.expectEqual(
                @as(lalr.Action.Kind, if (rank < 0) .shift else .reduce),
                k.other.kind,
            );
        }
        try testing.expect(forked);
    }
}

/// c's `f(a);`, small enough to press in a millisecond: `f(a)` is a
/// `parenthesized_declarator` inside a declaration, or a call inside an
/// expression statement, and the two bodies are the same four tokens. The rank is
/// a parameter because the proof is the *flip* - see the test.
fn twoReadingsOfACall(gpa: std.mem.Allocator, rank: i16) !g.Grammar {
    const src = try std.fmt.allocPrint(gpa,
        \\{{"name":"decl","rules":{{
        \\ "statement":{{"type":"CHOICE","members":[
        \\  {{"type":"SYMBOL","name":"declaration"}},
        \\  {{"type":"SYMBOL","name":"expression_statement"}}]}},
        \\ "declaration":{{"type":"SEQ","members":[
        \\  {{"type":"SYMBOL","name":"declarator"}},{{"type":"STRING","value":";"}}]}},
        \\ "expression_statement":{{"type":"SEQ","members":[
        \\  {{"type":"SYMBOL","name":"call"}},{{"type":"STRING","value":";"}}]}},
        \\ "declarator":{{"type":"PREC_DYNAMIC","value":{d},"content":{{
        \\  "type":"SEQ","members":[
        \\   {{"type":"SYMBOL","name":"identifier"}},{{"type":"STRING","value":"("}},
        \\   {{"type":"SYMBOL","name":"identifier"}},{{"type":"STRING","value":")"}}]}}}},
        \\ "call":{{"type":"SEQ","members":[
        \\  {{"type":"SYMBOL","name":"identifier"}},{{"type":"STRING","value":"("}},
        \\  {{"type":"SYMBOL","name":"identifier"}},{{"type":"STRING","value":")"}}]}},
        \\ "identifier":{{"type":"PATTERN","value":"[a-z]+"}}}},
        \\ "conflicts":[["declarator","call"]],"extras":[]}}
    , .{rank});
    defer gpa.free(src);
    return import.treeSitter(gpa, src);
}

test "a dynamic rank crosses the whole press and is still there for the fork" {
    // The rank's journey, in one test, because every rung of it has been lost at
    // least once: the front end reads `prec.dynamic`, `spread` reconciles it over
    // a body, `fold` carries it through a substitution, `dedup` keys on it,
    // `settle.keener` orders two tied folds by it, and `Forks` hands the loser to
    // a parse. Nothing here resolves the cell - a rank orders a fork and must
    // never remove one - so the assertions are about *which* reading leads and
    // that both survive.
    //
    // The proof is the flip. Press the same grammar twice with the rank negated
    // and the leading fold has to change sides; if it does not, the order came
    // from production indices and the rank was decoration. c writes -10 on its
    // three parenthesized declarators, so the negative run is the real grammar
    // and the positive one is the control.
    for ([_]i16{ -10, 10 }) |rank| {
        var gr = try twoReadingsOfACall(testing.allocator, rank);
        defer gr.deinit();

        const declarator = gr.productionsOf(named(&gr, "declarator"))[0];
        const call = gr.productionsOf(named(&gr, "call"))[0];
        try testing.expectEqual(rank, gr.productions[declarator].dynamic);
        try testing.expectEqual(@as(i16, 0), gr.productions[call].dynamic);

        var out = try tables(testing.allocator, &gr);
        defer out.deinit();
        const semi = named(&gr, ";");

        // Declared, so it is a fork rather than a defect, and it stayed one: no
        // amount of unfolding separates two readings of the same four tokens.
        const tally = out.tables.tally();
        try testing.expectEqual(@as(u32, 0), tally.residual.total());
        try testing.expect(tally.declared > 0);

        var seen = false;
        for (out.tables.conflicts) |k| {
            if (k.terminal != semi) continue;
            seen = true;
            try testing.expectEqual(settle.Conflict.Kind.reduce_reduce, k.kind);
            try testing.expectEqual(settle.Conflict.Class.declared, k.class);
            // The rank decides, and the table agrees with the record.
            const ahead = if (rank < 0) call else declarator;
            const behind = if (rank < 0) declarator else call;
            try testing.expectEqual(ahead, k.chosen.value);
            try testing.expectEqual(behind, k.other.value);
            try testing.expectEqual(k.chosen, out.tables.at(k.state, semi));
        }
        try testing.expect(seen);

        // And what a parse is handed at that cell: the reading the table dropped,
        // as a production index. The rank that ordered the two is *not* in there,
        // and cannot be recovered from a loaded grammar either - `ProductionRecord`
        // carries no rank, which `carry_test.zig` holds as the one pending loss.
        // Until it does, a fork that re-ranks its own versions reads 0 for every
        // production of every grammar.
        var forks = try settle.Forks.of(
            testing.allocator,
            out.tables.conflicts,
            out.collection.states.len,
            out.tables.width,
        );
        defer forks.deinit(testing.allocator);
        try testing.expect(forks.count() > 0);
        for (out.tables.conflicts) |k| {
            if (k.terminal != semi) continue;
            const other = forks.at(k.state, semi) orelse return error.ForkNotOffered;
            try testing.expectEqual(k.other, other);
        }
    }
}

fn named(gr: *const g.Grammar, name: []const u8) g.Symbol {
    for (0..gr.symbolCount()) |s| {
        if (std.mem.eql(u8, gr.nameOf(@intCast(s)), name)) return @intCast(s);
    }
    unreachable;
}

fn eqOf(gr: *const g.Grammar) u32 {
    for (0..gr.terminal_count) |t| {
        if (std.mem.eql(u8, gr.nameOf(@intCast(t)), "=")) return @intCast(t);
    }
    unreachable;
}

test {
    // Reached from here rather than from `root`, because what it protects is a
    // press invariant: the IR this file computes has to arrive at a parse
    // intact, and the folio is the only place it can quietly not.
    _ = @import("carry_test.zig");
    _ = @import("inquest.zig");
    // The census over a verdict list, which `zig build census` narrows to. Also
    // inert without its request file, so being in the suite costs a no-op.
    _ = @import("census_test.zig");
    // An instrument rather than an assertion: it answers "which cell decided
    // this" over a real grammar, and returns immediately unless asked.
    _ = @import("wall_test.zig");
}
