//! The goto automaton read backwards: what could have preceded this?
//!
//! A segment of a parse knows the state it started in and every symbol it has
//! pushed since. What it does not know is what was underneath, and a reduction
//! whose right-hand side is longer than the segment is exactly the moment that
//! stops being ignorable — the parser needs the state the pop exposes, and that
//! state belongs to whatever came before.
//!
//! It is not unknowable, though, and this is the hinge of the whole design.
//! The pop is not arbitrary: it removes a *known string of symbols*, the tail of
//! some production's right-hand side. So the exposed state is any state from
//! which that exact string leads to where we are — and following goto edges
//! backwards over a known string answers that with a set, usually a very small
//! one, because a symbol string is a strong constraint on where you can have
//! been.
//!
//! That set is the joint's domain, and how fast it collapses back to a single
//! state as more symbols are read is [rung one](../../../research/joinery/CLAIM.md):
//! the measurement that decides whether stack effects are cheap enough to be
//! worth composing. Tree-sitter's graph-structured stack stores this
//! information explicitly, per parse, as nodes and edges it allocates and
//! refcounts. Here it is a property of the table, computed once, shared by
//! every parse of every file in that language.

const std = @import("std");
const press = @import("../../press/press.zig");
const lr0 = press.lr0;
const lalr = press.lalr;

/// A predecessor: state `from` reaches the state this link is filed under by
/// consuming `symbol`.
const Link = struct {
    symbol: press.Symbol,
    from: u32,

    fn before(_: void, a: Link, b: Link) bool {
        return if (a.symbol != b.symbol) a.symbol < b.symbol else a.from < b.from;
    }
};

/// Whether a parse can really have arrived along this edge.
fn walkable(gr: *const press.Grammar, t: *const lalr.Tables, from: u32, e: lr0.Edge) bool {
    if (!gr.isTerminal(e.symbol)) return true;
    const a = t.at(from, e.symbol);
    return a.kind == .shift and a.value == e.target;
}

/// How wide the **uncovered floor** may get. Nothing here treats hitting it as
/// an error — it is the answer, and the answer means this position is one where
/// a parse has to branch. It bounds a per-token cost rather than a memory one:
/// every state a floor still believes possible is a table question on every
/// token that follows, so this is the width at which carrying the set honestly
/// costs more than admitting the position is undetermined. Interior depths are
/// not held to it; see `rewind`.
///
/// Raising it does not buy answers, which is worth knowing before trying. Swept
/// against go — 814 states, 184 conflicts the table could not resolve — 64
/// leaves 14% of pairs undetermined here and 7% branching past the limb
/// ceiling; 256 leaves 0% here and 20% there, for 1.7× the time and 0.8pp more
/// pairs answered. The width is a symptom of a nondeterministic table, so
/// widening relabels the failure rather than removing it, and the cheap
/// labelling is the one to keep.
pub const fan_ceiling = 64;

pub const Reverse = struct {
    gpa: std.mem.Allocator,
    /// CSR over target state: `links[offset[s] .. offset[s + 1]]`, sorted by
    /// symbol, so every predecessor over one symbol is a contiguous run.
    offset: []const u32,
    links: []const Link,
    /// Reused across walks. A walk is called once per reduction per parse
    /// thread, so allocating for it would dominate everything else it does.
    front: std.ArrayList(u32),
    back: std.ArrayList(u32),
    /// The last walk's `Trail`, flattened. Reused for the same reason the
    /// frontiers are: a reduction that pops below its base happens once per
    /// token in the worst case.
    flat: std.ArrayList(u32),
    ends: std.ArrayList(u32),
    /// Stamp per state, bumped once per walk step, for O(1) deduplication
    /// without clearing an array the size of the automaton every time.
    seen: []u32,
    epoch: u32,
    /// How wide an uncovered floor may get before `rewind` gives up on saying
    /// where it is. `fan_ceiling` unless a caller has a reason; a field rather
    /// than the constant so the behaviour is reachable from a test on a
    /// seven-state grammar instead of only from an eight-hundred-state one.
    fan: u32 = fan_ceiling,

    /// Over the **resolved** automaton, not the raw item graph. An LR(0) state
    /// keeps a shift edge on a terminal that precedence later deleted from the
    /// action table — `E -> E • + E` inside `E -> E + E •` is the standard one —
    /// and walking such an edge backwards invents a stack the parser can never
    /// build. Under left association that mistake is unbounded: it reads
    /// `E + E + E …` as a possible prefix and hands the caller one more origin
    /// per repetition, forever. So a terminal edge survives here only if the
    /// table really shifts along it. Gotos are kept as they are: a nonterminal
    /// has no action cell to be resolved against.
    pub fn build(
        gpa: std.mem.Allocator,
        gr: *const press.Grammar,
        c: *const lr0.Collection,
        t: *const lalr.Tables,
    ) !Reverse {
        const n = c.states.len;
        const offset = try gpa.alloc(u32, n + 1);
        errdefer gpa.free(offset);
        @memset(offset, 0);

        var total: usize = 0;
        for (c.states, 0..) |st, from| for (st.edges) |e| {
            if (!walkable(gr, t, @intCast(from), e)) continue;
            offset[e.target + 1] += 1;
            total += 1;
        };
        for (1..n + 1) |i| offset[i] += offset[i - 1];

        const links = try gpa.alloc(Link, total);
        errdefer gpa.free(links);
        var cursor = try gpa.dupe(u32, offset[0..n]);
        defer gpa.free(cursor);
        for (c.states, 0..) |st, from| for (st.edges) |e| {
            if (!walkable(gr, t, @intCast(from), e)) continue;
            links[cursor[e.target]] = .{ .symbol = e.symbol, .from = @intCast(from) };
            cursor[e.target] += 1;
        };
        for (0..n) |s| std.mem.sort(Link, links[offset[s]..offset[s + 1]], {}, Link.before);

        const seen = try gpa.alloc(u32, n);
        errdefer gpa.free(seen);
        @memset(seen, 0);

        return .{
            .gpa = gpa,
            .offset = offset,
            .links = links,
            .front = .empty,
            .back = .empty,
            .flat = .empty,
            .ends = .empty,
            .seen = seen,
            .epoch = 0,
        };
    }

    pub fn deinit(r: *Reverse) void {
        r.gpa.free(r.offset);
        r.gpa.free(r.links);
        r.gpa.free(r.seen);
        r.front.deinit(r.gpa);
        r.back.deinit(r.gpa);
        r.flat.deinit(r.gpa);
        r.ends.deinit(r.gpa);
        r.* = undefined;
    }

    /// Every state that reaches `to` over `symbol`, in one contiguous slice.
    pub fn predecessors(r: *const Reverse, to: u32, symbol: press.Symbol) []const Link {
        const run = r.links[r.offset[to]..r.offset[to + 1]];
        var lo: usize = 0;
        var hi: usize = run.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (run[mid].symbol < symbol) lo = mid + 1 else hi = mid;
        }
        var end = lo;
        while (end < run.len and run[end].symbol == symbol) end += 1;
        return run[lo..end];
    }

    /// Where the stack could have been at *every* depth the pop passed, not only
    /// at the far end. Both halves get used and for different reasons: the far
    /// end is the state the parser needs in order to continue, and the interior
    /// is what a neighbour is later held to.
    ///
    /// Keeping the interior is not a refinement, it is the difference between a
    /// sound guard and a useless one. A reduction consults the table only under
    /// its whole right-hand side, so a run that pops one recorded nothing in
    /// between — and the measurement showed exactly what leaks through: two
    /// scenarios that assumed *different symbol strings* of similar length below
    /// the base both compose with the same left neighbour, because the only
    /// thing that could have told them apart was the states those symbols pass
    /// through, and nobody wrote them down. Here they are; the walk already
    /// computes them.
    pub const Trail = struct {
        /// Frontiers back to back, shallowest first, each sorted.
        flat: []const u32,
        /// `flat[..ends[0]]` is one symbol back, `flat[ends[0]..ends[1]]` two.
        ends: []const u32,

        pub fn depth(t: Trail) u32 {
            return @intCast(t.ends.len);
        }

        /// The states the stack could hold `d` symbols below where the walk
        /// began. `d` runs from 1 to `depth()`; zero is where it began, which
        /// the caller already had.
        pub fn at(t: Trail, d: u32) []const u32 {
            std.debug.assert(d >= 1 and d <= t.ends.len);
            return t.flat[if (d == 1) 0 else t.ends[d - 2]..t.ends[d - 1]];
        }

        /// The far end: what the whole pop uncovered.
        pub fn floor(t: Trail) []const u32 {
            return t.at(t.depth());
        }
    };

    pub const Rewind = union(enum) {
        /// Owned by the `Reverse` and valid until the next walk.
        exposed: Trail,
        /// The floor the pop uncovered has more than `fan_ceiling` candidates:
        /// the segment cannot say where it is without being told, which is a
        /// real answer and a branch point.
        fanned,
        /// No state reaches here over that string. The automaton says the parse
        /// that produced this position never happened.
        impossible,
    };

    /// Walk `symbols` (bottom-to-top, as a right-hand side reads) backwards out
    /// of every state in `states`.
    pub fn rewind(r: *Reverse, states: []const u32, symbols: []const press.Symbol) !Rewind {
        r.front.clearRetainingCapacity();
        try r.front.appendSlice(r.gpa, states);
        r.flat.clearRetainingCapacity();
        r.ends.clearRetainingCapacity();

        var i = symbols.len;
        while (i > 0) {
            i -= 1;
            r.epoch += 1;
            r.back.clearRetainingCapacity();
            for (r.front.items) |s| for (r.predecessors(s, symbols[i])) |link| {
                if (r.seen[link.from] == r.epoch) continue;
                r.seen[link.from] = r.epoch;
                try r.back.append(r.gpa, link.from);
            };
            if (r.back.items.len == 0) return .impossible;
            // Only the far end is held to the ceiling, and the asymmetry is the
            // point. The far end becomes a live floor, and a live floor costs a
            // table question per state per token forever after — that is a real
            // budget. An interior frontier is only ever read as a claim, and a
            // claim nobody can narrow is merely vacuous: it admits everything,
            // refutes nothing, and costs one interned set. Failing the whole
            // rewind because a *middle* depth went wide threw away the far end
            // too, which is how an 800-state grammar came to report "cannot say
            // where this is" on one out of seven positions.
            if (i == 0 and r.back.items.len > r.fan) return .fanned;
            std.mem.swap(std.ArrayList(u32), &r.front, &r.back);
            std.mem.sort(u32, r.front.items, {}, std.sort.asc(u32));
            try r.flat.appendSlice(r.gpa, r.front.items);
            try r.ends.append(r.gpa, @intCast(r.flat.items.len));
        }
        return .{ .exposed = .{ .flat = r.flat.items, .ends = r.ends.items } };
    }
};

const testing = std.testing;

/// `S -> ( S ) | x`, the same grammar `lr0` proves itself against.
fn parens(gpa: std.mem.Allocator) !press.Grammar {
    var b = press.Builder.init(gpa);
    defer b.deinit();
    const lp = try b.intern("(", "(", .{ .literal = "(" });
    const rp = try b.intern(")", ")", .{ .literal = ")" });
    const x = try b.intern("x", "x", .{ .literal = "x" });
    const start = try b.intern("$start", "$start", null);
    const s = try b.intern("S", "S", null);
    try b.addProduction(start, &.{s}, &.{});
    try b.addProduction(s, &.{ lp, s, rp }, &.{});
    try b.addProduction(s, &.{x}, &.{});
    return b.finish("parens", start, &.{}, &.{});
}

test "every forward edge appears exactly once backwards" {
    var gr = try parens(testing.allocator);
    defer gr.deinit();
    var c = try lr0.build(testing.allocator, &gr, .{});
    defer c.deinit();
    var t = try lalr.build(testing.allocator, &gr, &c);
    defer t.deinit();
    var r = try Reverse.build(testing.allocator, &gr, &c, &t);
    defer r.deinit();

    for (c.states, 0..) |st, from| for (st.edges) |e| {
        const back = r.predecessors(e.target, e.symbol);
        var found = false;
        for (back) |link| found = found or link.from == from;
        try testing.expect(found);
    };
    try testing.expectEqual(r.links.len, r.offset[c.states.len]);
}

test "rewinding a right-hand side lands where the forward walk started" {
    var gr = try parens(testing.allocator);
    defer gr.deinit();
    var c = try lr0.build(testing.allocator, &gr, .{});
    defer c.deinit();
    var t = try lalr.build(testing.allocator, &gr, &c);
    defer t.deinit();
    var r = try Reverse.build(testing.allocator, &gr, &c, &t);
    defer r.deinit();

    // `S -> ( S )`. Walk it forward out of every state that can take it, then
    // rewind from where it landed: the origin must be in the answer. This is
    // the correctness statement the whole scheme rests on — popping a known
    // string can never lose the state you actually came from.
    const rhs = gr.productions[1].rhs;
    for (0..c.states.len) |from| {
        const landed = c.walk(@intCast(from), rhs) orelse continue;
        const back = try r.rewind(&.{@intCast(landed)}, rhs);
        try testing.expect(std.mem.indexOfScalar(u32, back.exposed.floor(), @intCast(from)) != null);
    }
}

test "a string nothing can have produced is impossible, not empty" {
    var gr = try parens(testing.allocator);
    defer gr.deinit();
    var c = try lr0.build(testing.allocator, &gr, .{});
    defer c.deinit();
    var t = try lalr.build(testing.allocator, &gr, &c);
    defer t.deinit();
    var r = try Reverse.build(testing.allocator, &gr, &c, &t);
    defer r.deinit();

    // `) (` is not a suffix of any path in this automaton.
    const lp = gr.productions[1].rhs[0];
    const rp = gr.productions[1].rhs[2];
    for (0..c.states.len) |s| {
        try testing.expectEqual(Reverse.Rewind.impossible, try r.rewind(&.{@intCast(s)}, &.{ rp, lp }));
    }
}

test "the symbol string is what keeps the answer small" {
    var gr = try parens(testing.allocator);
    defer gr.deinit();
    var c = try lr0.build(testing.allocator, &gr, .{});
    defer c.deinit();
    var t = try lalr.build(testing.allocator, &gr, &c);
    defer t.deinit();
    var r = try Reverse.build(testing.allocator, &gr, &c, &t);
    defer r.deinit();

    // Rewinding three symbols out of *every* state at once — the worst case a
    // segment can pose — still names at most a couple of origins, because the
    // string `( S )` can only have been walked from somewhere that takes a `(`.
    var all: [8]u32 = undefined;
    for (0..c.states.len) |i| all[i] = @intCast(i);
    const back = try r.rewind(all[0..c.states.len], gr.productions[1].rhs);
    try testing.expect(back.exposed.floor().len <= 2);
}

test "the trail holds every depth the walk passed, not just the far end" {
    var gr = try parens(testing.allocator);
    defer gr.deinit();
    var c = try lr0.build(testing.allocator, &gr, .{});
    defer c.deinit();
    var t = try lalr.build(testing.allocator, &gr, &c);
    defer t.deinit();
    var r = try Reverse.build(testing.allocator, &gr, &c, &t);
    defer r.deinit();

    // The contract the guard rests on: whatever forward path really produced
    // this position, the trail must hold its state at *every* depth, not only
    // at the bottom. A trail that dropped an interior state would let a guard
    // refuse a pairing some parse produced, which is the one error nothing
    // downstream can recover from.
    //
    // Checked by walking each right-hand side forward and reading the states
    // off as it goes, then insisting the backward trail admits all of them.
    for (gr.productions) |p| {
        if (p.rhs.len == 0) continue;
        for (0..c.states.len) |from| {
            var forward: [8]u32 = undefined;
            var at: u32 = @intCast(from);
            var ok = true;
            for (p.rhs, 0..) |s, i| {
                forward[i] = at;
                at = c.goto(at, s) orelse {
                    ok = false;
                    break;
                };
            }
            if (!ok) continue;

            const back = try r.rewind(&.{at}, p.rhs);
            try testing.expectEqual(@as(u32, @intCast(p.rhs.len)), back.exposed.depth());
            // Depth `d` back from the landing is the state that stood before
            // symbol `rhs.len - d` was read.
            for (1..p.rhs.len + 1) |d| {
                const want = forward[p.rhs.len - d];
                const seen = back.exposed.at(@intCast(d));
                try testing.expect(std.mem.indexOfScalar(u32, seen, want) != null);
            }
            try testing.expectEqualSlices(u32, back.exposed.at(@intCast(p.rhs.len)), back.exposed.floor());
        }
    }
}

/// `S -> u v | p v | q v`. Three ways to reach a `v`, one of which is over `u`,
/// so rewinding `u v` passes through a wide interior — every state that could
/// be about to read a `v` — and lands on a floor of exactly one.
fn funnel(gpa: std.mem.Allocator) !press.Grammar {
    var b = press.Builder.init(gpa);
    defer b.deinit();
    const v = try b.intern("v", "v", .{ .literal = "v" });
    const start = try b.intern("$start", "$start", null);
    const s = try b.intern("S", "S", null);
    try b.addProduction(start, &.{s}, &.{});
    for ([_][]const u8{ "u", "p", "q" }) |lead| {
        try b.addProduction(s, &.{ try b.intern(lead, lead, .{ .literal = lead }), v }, &.{});
    }
    return b.finish("funnel", start, &.{}, &.{});
}

test "only the floor is held to the ceiling, because only the floor is paid for" {
    var gr = try funnel(testing.allocator);
    defer gr.deinit();
    var c = try lr0.build(testing.allocator, &gr, .{});
    defer c.deinit();
    var t = try lalr.build(testing.allocator, &gr, &c);
    defer t.deinit();
    var r = try Reverse.build(testing.allocator, &gr, &c, &t);
    defer r.deinit();

    var all: [16]u32 = undefined;
    for (0..c.states.len) |i| all[i] = @intCast(i);
    const states = all[0..c.states.len];
    const rhs = gr.productions[1].rhs; // `u v`

    // A ceiling of one, so a frontier of three is well over it. Started from
    // every state at once — the worst case a segment can pose — the walk still
    // answers, because the depth that went wide is only ever read as a claim.
    // A wide claim is vacuous, which is free; a wide floor is a table question
    // per state per token for the rest of the segment, which is not.
    r.fan = 1;
    const back = try r.rewind(states, rhs);
    try testing.expectEqual(@as(usize, 1), back.exposed.floor().len);
    try testing.expectEqual(@as(usize, 3), back.exposed.at(1).len);

    // The floor itself still is: one more origin than the ceiling allows and
    // the walk says so, rather than handing back a set nobody budgeted for.
    r.fan = 0;
    try testing.expectEqual(Reverse.Rewind.fanned, try r.rewind(states, rhs));
}
