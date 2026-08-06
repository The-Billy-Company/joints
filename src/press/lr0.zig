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

    comptime {
        // The sentence above, as a build failure. Six interners key on
        // `sliceAsBytes` of a run of these while comparing them with
        // `std.mem.eql` - and `eql` consults exactly this predicate before it
        // will `memcmp`, so a type with slack makes the two halves disagree
        // about which states are one state. `packed struct(u64)` cannot hold
        // slack today; the assertion is against the day somebody drops the
        // backing integer to add a field, which compiles and looks harmless.
        // Stated as `std.meta.hasUniqueRepresentation` rather than through
        // `folio/leaf.zig`'s `seamless`, which says the same thing for the
        // sections on disk: the production arrow is folio -> press and nothing
        // under `press/` reads folio back. One law, std's spelling, no cycle.
        if (!std.meta.hasUniqueRepresentation(Item)) @compileError(
            "lr0.Item is hashed by its bytes and compared by its fields, so" ++
                " every byte of it has to belong to a field.",
        );
    }

    fn before(a: Item, b: Item) bool {
        return if (a.prod != b.prod) a.prod < b.prod else a.dot < b.dot;
    }
};

pub const Edge = struct {
    symbol: g.Symbol,
    target: u32,
};

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

/// A kernel, plus what distinguishes two states that have it.
///
/// `mark` is zero for the usual case, where a kernel *is* the state and seeing
/// it twice means arriving somewhere already known. For a kernel named in
/// `Options.split` it is the lane the arrival was assigned, which puts arrivals
/// in different lanes into different states — see `Options.split`.
///
/// A lane is chosen per *source kernel* rather than per source state id, and the
/// difference is the difference between terminating and not. An id is minted by
/// splitting: split a state that lies on a cycle through itself and each copy is
/// a new id, which is a new mark, which is another copy — a 1300-state automaton
/// walks past a quarter of a million states and never closes. A kernel is what
/// the state *is*, so it is the same before and after any split, and the copies
/// of a marked kernel are at most the lanes its callers asked for.
const Key = struct { kernel: []const Item, mark: u32 };

/// The interner that makes the collection finite: a key seen twice is one
/// state. Kernels are hashed by their bytes.
const Index = std.HashMap(Key, u32, struct {
    pub fn hash(_: @This(), k: Key) u64 {
        return std.hash.Wyhash.hash(k.mark, std.mem.sliceAsBytes(k.kernel));
    }
    pub fn eql(_: @This(), a: Key, b: Key) bool {
        return a.mark == b.mark and std.mem.eql(Item, a.kernel, b.kernel);
    }
}, std.hash_map.default_max_load_percentage);

/// One arrival at one state, and which copy of that state it belongs to.
///
/// Both ends are named by kernel rather than by state id, so a lane assignment
/// computed on one automaton still means the same thing on the next one — which
/// is what lets the caller iterate.
pub const Lane = struct {
    /// The state being unfolded.
    kernel: []const Item,
    /// The state the arrival comes from.
    from: []const Item,
    /// Which copy. Arrivals of an unfolded kernel that nobody named fall to
    /// lane zero and share one state, which is the un-unfolded behaviour.
    lane: u32,
};

/// Arrival to lane, keyed by both kernels.
const Lanes = std.HashMap(struct { []const Item, []const Item }, u32, struct {
    pub fn hash(_: @This(), k: struct { []const Item, []const Item }) u64 {
        var h: std.hash.Wyhash = .init(0);
        h.update(std.mem.sliceAsBytes(k[0]));
        h.update(std.mem.sliceAsBytes(k[1]));
        return h.final();
    }
    pub fn eql(_: @This(), a: struct { []const Item, []const Item }, b: struct { []const Item, []const Item }) bool {
        return std.mem.eql(Item, a[0], b[0]) and std.mem.eql(Item, a[1], b[1]);
    }
}, std.hash_map.default_max_load_percentage);

pub const Options = struct {
    /// How to unfold: which arrivals at which kernels belong in separate copies.
    ///
    /// Merging states that share a kernel is what makes this an LR(0)
    /// collection rather than a tree, and it is almost always right — it is
    /// the reason the automaton is finite. But the merge also unions what can
    /// follow each arrival, so a reduction is decided from lookaheads that
    /// belong to a context the parser is not in. That is the whole of the
    /// LALR-versus-canonical gap.
    ///
    /// The obvious repair is one copy per way in, and it is far too much
    /// automaton: a state reached forty ways becomes forty states to separate
    /// two lookaheads, and every copy multiplies downstream. So the caller says
    /// which arrivals need separating from which, and arrivals that agree stay
    /// merged. `lalr` computes that partition from the lookaheads themselves,
    /// which makes it both sufficient and coarsest — see `lalr.Seam`.
    split: []const Lane = &.{},
    /// A ceiling on states. Splitting by source kernel terminates, but it can
    /// still cost more automaton than the conflict it buys is worth. Reaching
    /// it returns `error.Unsplittable` rather than a collection nobody asked
    /// for.
    ceiling: u32 = 1 << 19,
};

/// The closure of a kernel, and the scratch it needs to compute one.
///
/// Exposed because the closure is the only place the *items* of a state still
/// exist. The collection keeps kernels and reductions, which is all a table
/// needs; anything that has to say which items disagree — a conflict report, an
/// LR(1) lookahead — has to re-derive them, and should re-derive them the same
/// way the automaton did.
pub const Closure = struct {
    items: std.ArrayList(Item) = .empty,
    /// Per nonterminal, whether its productions are already in `items`. A set
    /// rather than a scan: without it the walk is quadratic in the closure.
    expanded: []bool,

    pub fn init(gpa: std.mem.Allocator, gr: *const g.Grammar) !Closure {
        return .{ .expanded = try gpa.alloc(bool, gr.nonterminalCount()) };
    }

    pub fn deinit(c: *Closure, gpa: std.mem.Allocator) void {
        c.items.deinit(gpa);
        gpa.free(c.expanded);
        c.* = undefined;
    }

    /// The closure of `kernel`, valid until the next call.
    pub fn of(
        c: *Closure,
        gpa: std.mem.Allocator,
        gr: *const g.Grammar,
        kernel: []const Item,
    ) ![]const Item {
        c.items.clearRetainingCapacity();
        try c.items.appendSlice(gpa, kernel);
        @memset(c.expanded, false);
        var i: usize = 0;
        while (i < c.items.items.len) : (i += 1) {
            const item = c.items.items[i];
            const rhs = gr.productions[item.prod].rhs;
            if (item.dot == rhs.len) continue;
            const s = rhs[item.dot];
            if (gr.isTerminal(s)) continue;
            const n = s - gr.terminal_count;
            if (c.expanded[n]) continue;
            c.expanded[n] = true;
            for (gr.productionsOf(s)) |p| try c.items.append(gpa, .{ .prod = p, .dot = 0 });
        }
        return c.items.items;
    }
};

/// One closure item paired with the symbol its dot sits before, so the whole
/// successor set can be sorted once and read off in runs.
const Step = struct {
    symbol: g.Symbol,
    item: Item,

    fn before(_: void, x: Step, y: Step) bool {
        return if (x.symbol != y.symbol) x.symbol < y.symbol else x.item.before(y.item);
    }
};

pub fn build(gpa: std.mem.Allocator, gr: *const g.Grammar, opts: Options) !Collection {
    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    const a = arena.allocator();

    var index = Index.init(gpa);
    defer index.deinit();
    var lanes = Lanes.init(gpa);
    defer lanes.deinit();
    for (opts.split) |l| try lanes.put(.{ l.kernel, l.from }, l.lane);
    var kernels: std.ArrayList([]const Item) = .empty;
    defer kernels.deinit(gpa);
    var states: std.ArrayList(State) = .empty;
    defer states.deinit(gpa);

    // Scratch reused across every state, so the walk allocates once and then
    // stops allocating.
    var closure = try Closure.init(gpa, gr);
    defer closure.deinit(gpa);
    var steps: std.ArrayList(Step) = .empty;
    defer steps.deinit(gpa);
    var complete: std.ArrayList(u32) = .empty;
    defer complete.deinit(gpa);
    var edges: std.ArrayList(Edge) = .empty;
    defer edges.deinit(gpa);

    // Production 0 is the augmented `$start -> S`, so the initial kernel is
    // that production with the dot at its front. The start state is entered
    // from nowhere, so it is never split.
    _ = try intern(gpa, a, &index, &kernels, &states, .{
        .kernel = &.{.{ .prod = 0, .dot = 0 }},
        .mark = 0,
    });

    var at: usize = 0;
    while (at < kernels.items.len) : (at += 1) {
        const kernel = kernels.items[at];

        const items = try closure.of(gpa, gr, kernel);

        steps.clearRetainingCapacity();
        complete.clearRetainingCapacity();
        for (items) |item| {
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
                .target = try intern(gpa, a, &index, &kernels, &states, .{
                    .kernel = target.items,
                    .mark = lanes.get(.{ target.items, kernel }) orelse 0,
                }),
            });
            if (states.items.len > opts.ceiling) return error.Unsplittable;
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
    key: Key,
) !u32 {
    const slot = try index.getOrPut(key);
    if (slot.found_existing) return slot.value_ptr.*;
    const owned = try a.dupe(Item, key.kernel);
    slot.key_ptr.* = .{ .kernel = owned, .mark = key.mark };
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
    try b.addProduction(start, &.{s}, &.{});
    try b.addProduction(s, &.{ lp, s, rp }, &.{});
    try b.addProduction(s, &.{x}, &.{});
    return b.finish("parens", start, &.{}, &.{});
}

test "the collection is finite and every edge lands in it" {
    var gr = try parens(testing.allocator);
    defer gr.deinit();
    var c = try build(testing.allocator, &gr, .{});
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
    var c = try build(testing.allocator, &gr, .{});
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
    var c = try build(testing.allocator, &gr, .{});
    defer c.deinit();

    const rhs = gr.productions[1].rhs; // ( S )
    const landed = c.walk(0, rhs).?;
    try testing.expectEqual(@as(usize, 1), c.states[landed].complete.len);
    try testing.expectEqual(@as(u32, 1), c.states[landed].complete[0]);
}
