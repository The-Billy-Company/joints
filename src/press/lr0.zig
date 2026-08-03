//! The LR(0) canonical collection: the shape of the automaton, before any
//! question of lookahead.
//!
//! A state is its kernel. The closure is derivable from the kernel and is
//! recomputed rather than stored, which is the usual trade and the right one
//! here: closures are large, kernels are tiny, and the whole collection is
//! visited a bounded number of times afterward.
//!
//! This layer deliberately knows nothing about terminals-versus-lookahead. It
//! produces states, the transitions between them, and which productions are
//! complete in each state. Deciding *when* a complete production may reduce is
//! `lalr.zig`'s job, and keeping the two apart is what makes it possible to
//! swap that decision — for SLR, for LALR, for a semiring-weighted variant —
//! without touching the automaton.

const std = @import("std");
const g = @import("grammar.zig");

/// A production with a position in it. Packed because these are hashed by
/// their bytes and compared in bulk.
pub const Item = packed struct(u64) {
    prod: u32,
    dot: u32,

    fn before(a: Item, b: Item) bool {
        return if (a.prod != b.prod) a.prod < b.prod else a.dot < b.dot;
    }
};

pub const Edge = struct { symbol: g.Symbol, target: u32 };

pub const State = struct {
    /// Sorted, deduplicated. Two states are the same state exactly when these
    /// match, which is what makes the collection finite.
    kernel: []const Item,
    /// Sorted by symbol, so a goto is a binary search.
    edges: []const Edge,
    /// Productions whose dot has reached the end here — the reduction
    /// candidates, including epsilon productions contributed by the closure.
    complete: []const u32,
};

pub const Collection = struct {
    arena: std.heap.ArenaAllocator,
    states: []const State,

    pub fn deinit(c: *Collection) void {
        c.arena.deinit();
        c.* = undefined;
    }

    pub fn goto(c: Collection, state: u32, symbol: g.Symbol) ?u32 {
        const edges = c.states[state].edges;
        var lo: usize = 0;
        var hi: usize = edges.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (edges[mid].symbol < symbol) lo = mid + 1 else hi = mid;
        }
        return if (lo < edges.len and edges[lo].symbol == symbol) edges[lo].target else null;
    }

    /// Walk a right-hand side from a state, returning where it lands. Null
    /// means the path leaves the automaton, which cannot happen for a path the
    /// automaton itself produced — every caller here walks such a path.
    pub fn walk(c: Collection, from: u32, symbols: []const g.Symbol) ?u32 {
        var at = from;
        for (symbols) |s| at = c.goto(at, s) orelse return null;
        return at;
    }
};

/// The interner that makes the collection finite: a kernel seen twice is one
/// state. Keys are the kernel slices themselves, hashed by their bytes.
const Index = std.HashMap([]const Item, u32, struct {
    pub fn hash(_: @This(), k: []const Item) u64 {
        return std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(k));
    }
    pub fn eql(_: @This(), a: []const Item, b: []const Item) bool {
        return std.mem.eql(Item, a, b);
    }
}, std.hash_map.default_max_load_percentage);

/// One closure item paired with the symbol its dot sits before, so the whole
/// successor set can be sorted once and read off in runs.
const Step = struct {
    symbol: g.Symbol,
    item: Item,

    fn before(_: void, x: Step, y: Step) bool {
        return if (x.symbol != y.symbol) x.symbol < y.symbol else x.item.before(y.item);
    }
};

pub fn build(gpa: std.mem.Allocator, gr: *const g.Grammar) !Collection {
    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    const a = arena.allocator();

    var index = Index.init(gpa);
    defer index.deinit();
    var kernels: std.ArrayList([]const Item) = .empty;
    defer kernels.deinit(gpa);
    var states: std.ArrayList(State) = .empty;
    defer states.deinit(gpa);

    // Scratch reused across every state, so the walk allocates once and then
    // stops allocating.
    var expanded = try gpa.alloc(bool, gr.nonterminalCount());
    defer gpa.free(expanded);
    var closure: std.ArrayList(Item) = .empty;
    defer closure.deinit(gpa);
    var steps: std.ArrayList(Step) = .empty;
    defer steps.deinit(gpa);
    var complete: std.ArrayList(u32) = .empty;
    defer complete.deinit(gpa);
    var edges: std.ArrayList(Edge) = .empty;
    defer edges.deinit(gpa);

    // Production 0 is the augmented `$start -> S`, so the initial kernel is
    // that production with the dot at its front.
    _ = try intern(gpa, a, &index, &kernels, &states, &.{.{ .prod = 0, .dot = 0 }});

    var at: usize = 0;
    while (at < kernels.items.len) : (at += 1) {
        const kernel = kernels.items[at];

        closure.clearRetainingCapacity();
        try closure.appendSlice(gpa, kernel);
        @memset(expanded, false);
        var i: usize = 0;
        while (i < closure.items.len) : (i += 1) {
            const item = closure.items[i];
            const rhs = gr.productions[item.prod].rhs;
            if (item.dot == rhs.len) continue;
            const s = rhs[item.dot];
            if (gr.isTerminal(s)) continue;
            const n = s - gr.terminal_count;
            if (expanded[n]) continue;
            expanded[n] = true;
            for (gr.productionsOf(s)) |p| try closure.append(gpa, .{ .prod = p, .dot = 0 });
        }

        steps.clearRetainingCapacity();
        complete.clearRetainingCapacity();
        for (closure.items) |item| {
            const rhs = gr.productions[item.prod].rhs;
            if (item.dot == rhs.len) {
                try complete.append(gpa, item.prod);
            } else {
                try steps.append(gpa, .{
                    .symbol = rhs[item.dot],
                    .item = .{ .prod = item.prod, .dot = item.dot + 1 },
                });
            }
        }
        std.mem.sort(Step, steps.items, {}, Step.before);

        edges.clearRetainingCapacity();
        var run: usize = 0;
        while (run < steps.items.len) {
            const symbol = steps.items[run].symbol;
            var end = run;
            while (end < steps.items.len and steps.items[end].symbol == symbol) end += 1;

            var target: std.ArrayList(Item) = .empty;
            defer target.deinit(gpa);
            for (steps.items[run..end]) |s| {
                // Sorted, so a duplicate can only be adjacent.
                const last = target.getLastOrNull();
                if (last == null or !std.meta.eql(last.?, s.item)) try target.append(gpa, s.item);
            }
            try edges.append(gpa, .{
                .symbol = symbol,
                .target = try intern(gpa, a, &index, &kernels, &states, target.items),
            });
            run = end;
        }

        states.items[at] = .{
            .kernel = kernel,
            .edges = try a.dupe(Edge, edges.items),
            .complete = try a.dupe(u32, complete.items),
        };
    }

    // Allocated before the arena is moved, never as a later field of the same
    // literal: the arena's buffer list is captured by value, so a buffer the
    // allocation appends afterward would be invisible to it.
    const owned = try a.dupe(State, states.items);
    return .{ .arena = arena, .states = owned };
}

fn intern(
    gpa: std.mem.Allocator,
    a: std.mem.Allocator,
    index: *Index,
    kernels: *std.ArrayList([]const Item),
    states: *std.ArrayList(State),
    kernel: []const Item,
) !u32 {
    const slot = try index.getOrPut(kernel);
    if (slot.found_existing) return slot.value_ptr.*;
    const owned = try a.dupe(Item, kernel);
    slot.key_ptr.* = owned;
    slot.value_ptr.* = @intCast(kernels.items.len);
    try kernels.append(gpa, owned);
    // Filled in when the walk reaches it; the id has to exist first so an edge
    // pointing back at a state still being built has something to name.
    try states.append(gpa, undefined);
    return slot.value_ptr.*;
}

const testing = std.testing;

/// `S -> ( S ) | x`, the smallest grammar with both a shift chain and a
/// reduction, hand-built so the test does not depend on the importer.
fn parens(gpa: std.mem.Allocator) !g.Grammar {
    var b = g.Builder.init(gpa);
    defer b.deinit();
    const lp = try b.intern("(", "(", .{ .literal = "(" });
    const rp = try b.intern(")", ")", .{ .literal = ")" });
    const x = try b.intern("x", "x", .{ .literal = "x" });
    const start = try b.intern("$start", "$start", null);
    const s = try b.intern("S", "S", null);
    try b.addProduction(start, &.{s}, 0, .none);
    try b.addProduction(s, &.{ lp, s, rp }, 0, .none);
    try b.addProduction(s, &.{x}, 0, .none);
    return b.finish("parens", start, &.{}, &.{});
}

test "the collection is finite and every edge lands in it" {
    var gr = try parens(testing.allocator);
    defer gr.deinit();
    var c = try build(testing.allocator, &gr);
    defer c.deinit();

    // Six kernels: {$start -> . S}, {$start -> S .}, {S -> ( . S )},
    // {S -> ( S . )}, {S -> ( S ) .}, {S -> x .}.
    try testing.expectEqual(@as(usize, 6), c.states.len);
    for (c.states) |st| for (st.edges) |e| try testing.expect(e.target < c.states.len);

    // A second `(` from inside a paren re-enters the same state, because the
    // kernel it produces is the one that state already is. That self-loop is
    // why an LR stack stays bounded on arbitrarily nested input, and it is why
    // the collection is six states rather than one per nesting depth.
    const lp = gr.productions[1].rhs[0];
    const inside = c.goto(0, lp).?;
    try testing.expectEqual(@as(?u32, inside), c.goto(inside, lp));
    for (c.states) |st| for (st.edges) |e| try testing.expect(e.target < c.states.len);
}

test "a completed item is reported exactly in the state that completes it" {
    var gr = try parens(testing.allocator);
    defer gr.deinit();
    var c = try build(testing.allocator, &gr);
    defer c.deinit();

    var accepting: usize = 0;
    var reducing: usize = 0;
    for (c.states) |st| for (st.complete) |p| {
        if (p == 0) accepting += 1 else reducing += 1;
    };
    // One accept state, and one reduce state for each of `S -> ( S )` and
    // `S -> x` — reached from the start state and from inside a paren, which
    // LR(0) merges because the kernels are identical.
    try testing.expectEqual(@as(usize, 1), accepting);
    try testing.expectEqual(@as(usize, 2), reducing);
}

test "walking a right-hand side from the start state lands where goto does" {
    var gr = try parens(testing.allocator);
    defer gr.deinit();
    var c = try build(testing.allocator, &gr);
    defer c.deinit();

    const rhs = gr.productions[1].rhs; // ( S )
    const landed = c.walk(0, rhs).?;
    try testing.expectEqual(@as(usize, 1), c.states[landed].complete.len);
    try testing.expectEqual(@as(u32, 1), c.states[landed].complete[0]);
}
