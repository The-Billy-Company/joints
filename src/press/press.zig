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
//! as frayed cells and this loop unfolds them — build, name the frayed kernels,
//! build again with their arrivals kept apart. Each round strictly narrows
//! lookaheads, so the count can only shrink; the loop stops when it does not.
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

/// How many times to unfold before accepting the residue. Each round splits the
/// states that are still contested, which is the same lane one step further
/// back; four reaches contexts four gotos apart, and no real grammar has needed
/// a second.
const rounds = 4;

/// How far the automaton may grow while unfolding, as a multiple of the
/// un-unfolded collection. Splitting a state clones its arrivals and everything
/// downstream of them, and a grammar with a thousand frayed cells can ask for
/// more automaton than the frayed cells are worth. The loop keeps the best
/// result it reached, so a refusal here costs accuracy in the report, never
/// correctness of the table.
var growth: u32 = 8;

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
};

pub fn tables(gpa: std.mem.Allocator, gr: *const g.Grammar) !Result {
    // Kernels naming the states to split. They are read out of one automaton
    // and handed to the next, so they are copied here rather than borrowed:
    // the automaton that named them is often the one being thrown away. The
    // list only grows — a kernel that was worth splitting stays split, or the
    // damage it was hiding comes straight back and the loop chases its own tail.
    var scratch = std.heap.ArenaAllocator.init(gpa);
    defer scratch.deinit();
    var split: std.ArrayList([]const lr0.Item) = .empty;

    var best: ?Result = null;
    errdefer if (best) |*b| b.deinit();
    var ceiling: u32 = 1 << 19;
    // How much of the list this round dares use. Splitting is not additive:
    // marked states on a common path multiply, so a list that is merely twice
    // as long can be an automaton fifty times the size. Rather than abandon the
    // round, drop back to the head of the list — which is ordered by damage —
    // and take the unfolding that fits.
    var dare = split.items.len;

    for (0..rounds + 1) |round| {
        var c = while (true) {
            break lr0.build(gpa, gr, .{
                .split = split.items[0..dare],
                .ceiling = ceiling,
            }) catch |e| switch (e) {
                error.Unsplittable => {
                    if (trace) {
                        std.debug.print("round {d}: {d} split is past {d} states\n", .{
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
        if (trace) {
            const d = try defects(gpa, &round_result);
            std.debug.print("round {d}: {d} states, {d} split, residual {d}, refused {d}\n", .{
                round,      round_result.collection.states.len,
                dare,       d.residual,
                d.refused,
            });
        }
        const now = try defects(gpa, &round_result);
        const better = best == null or now.betterThan(try defects(gpa, &best.?));

        if (now.clean()) {
            if (best) |*b| b.deinit();
            return round_result;
        }

        // Named from the newest automaton whether or not that automaton is
        // kept. A round that gained nothing still split *something*, and the
        // states frayed after it are one context further back than the ones
        // frayed before — which is the only way a fray two gotos deep is ever
        // reached. Keeping the best table and continuing the search are
        // separate decisions.
        const was = split.items.len;
        try contested(scratch.allocator(), &split, dare, &round_result);
        if (split.items.len == was) {
            if (better) {
                if (best) |*b| b.deinit();
                best = round_result;
            } else round_result.deinit();
            break;
        }
        dare = split.items.len;

        if (better) {
            if (best) |*b| b.deinit();
            best = round_result;
        } else round_result.deinit();
    }
    return best.?;
}

/// What is still wrong with a table that unfolding could fix. Both terms are
/// merge damage: a reduce/reduce nobody declared, and a cell whose contest only
/// exists because arrivals were pooled.
fn defects(gpa: std.mem.Allocator, r: *const Result) !Defects {
    var out: Defects = .{ .residual = r.tables.tally().residual.reduce_reduce };

    // By kernel, not by state. Splitting makes copies, and a fray in a state
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
        out.refused += 1;
    }
    return out;
}

/// Ordered, not summed. A reduce/reduce residue is a cell the report calls a
/// defect, so a round that trades one of those for any number of frayed cells
/// has made the table worse by the measure the table is judged on.
const Defects = struct {
    residual: u32 = 0,
    refused: u32 = 0,

    fn betterThan(a: Defects, b: Defects) bool {
        if (a.residual != b.residual) return a.residual < b.residual;
        return a.refused < b.refused;
    }

    fn clean(d: Defects) bool {
        return d.residual == 0 and d.refused == 0;
    }
};

/// The kernels of every state still holding merge damage — and, where splitting
/// that state has already been tried and failed, the states it is reached from.
///
/// Splitting a kernel by predecessor separates the ways in *as the current
/// automaton counts them*. If the disagreement is older than that — if the two
/// contexts already converged one goto earlier — every arrival comes from the
/// same merged predecessor, the split makes one state where there was one
/// state, and the fray survives untouched. Naming that state again next round
/// would do the identical nothing forever.
///
/// So a fray that survives its own split escalates: the predecessors are named
/// too, and the disagreement is separated one goto further back. Rounds walk
/// backwards along the paths that actually disagree, rather than splitting the
/// whole automaton on the chance that it helps.
fn contested(
    gpa: std.mem.Allocator,
    out: *std.ArrayList([]const lr0.Item),
    prior: usize,
    r: *const Result,
) !void {
    var back: ?Back = null;
    defer if (back) |*b| b.deinit(gpa);

    // Worst first. The list is a preference order, not a set: when the whole of
    // it does not fit under the ceiling the head of it is what gets used, so
    // the states holding the most refused tokens have to be at the front.
    var damage: std.AutoArrayHashMapUnmanaged(u32, u32) = .empty;
    defer damage.deinit(gpa);
    for (r.tables.conflicts) |k| {
        if (k.class != .residual or k.kind != .reduce_reduce) continue;
        const slot = try damage.getOrPutValue(gpa, k.state, 0);
        slot.value_ptr.* += 1;
    }
    for (r.tables.frayed) |f| {
        const slot = try damage.getOrPutValue(gpa, f.state, 0);
        slot.value_ptr.* += @as(u32, if (f.harm == .read_dropped) 4 else 1);
    }
    const states = damage.keys();
    const counts = damage.values();
    const order = try gpa.alloc(u32, states.len);
    defer gpa.free(order);
    for (order, 0..) |*o, i| o.* = @intCast(i);
    std.mem.sort(u32, order, counts, struct {
        fn less(c: []const u32, x: u32, y: u32) bool {
            return c[x] > c[y];
        }
    }.less);

    for (order) |i| try escalate(gpa, out, prior, r, &back, states[i]);
}

fn escalate(
    gpa: std.mem.Allocator,
    out: *std.ArrayList([]const lr0.Item),
    prior: usize,
    r: *const Result,
    back: *?Back,
    state: u32,
) !void {
    const kernel = r.collection.states[state].kernel;
    const known = try name(gpa, out, kernel);
    // Splitting this one has already been tried and the fray is still here, so
    // the contexts had already converged before it: separate them one goto
    // further back instead of asking for the same state twice.
    if (!known or indexOf(out.items[0..prior], kernel) == null) return;
    if (back.* == null) back.* = try Back.of(gpa, &r.collection);
    for (back.*.?.into(state)) |from| {
        _ = try name(gpa, out, r.collection.states[from].kernel);
    }
}

fn indexOf(haystack: []const []const lr0.Item, kernel: []const lr0.Item) ?usize {
    for (haystack, 0..) |seen, i| {
        if (std.mem.eql(lr0.Item, seen, kernel)) return i;
    }
    return null;
}

/// Which states lead into each state, bucketed. Built at most once per round,
/// and only when some fray has survived a split.
const Back = struct {
    base: []u32,
    from: []u32,

    fn of(gpa: std.mem.Allocator, c: *const lr0.Collection) !Back {
        const n = c.states.len;
        const base = try gpa.alloc(u32, n + 1);
        errdefer gpa.free(base);
        @memset(base, 0);
        for (c.states) |st| {
            for (st.edges) |e| base[e.target + 1] += 1;
        }
        for (1..n + 1) |i| base[i] += base[i - 1];

        const from = try gpa.alloc(u32, base[n]);
        errdefer gpa.free(from);
        const fill = try gpa.alloc(u32, n);
        defer gpa.free(fill);
        @memset(fill, 0);
        for (c.states, 0..) |st, q| {
            for (st.edges) |e| {
                from[base[e.target] + fill[e.target]] = @intCast(q);
                fill[e.target] += 1;
            }
        }
        return .{ .base = base, .from = from };
    }

    fn into(b: Back, state: u32) []const u32 {
        return b.from[b.base[state]..b.base[state + 1]];
    }

    fn deinit(b: *Back, gpa: std.mem.Allocator) void {
        gpa.free(b.base);
        gpa.free(b.from);
    }
};

/// Add a kernel to the list if it is not already there, reporting whether it
/// already was.
fn name(
    gpa: std.mem.Allocator,
    out: *std.ArrayList([]const lr0.Item),
    kernel: []const lr0.Item,
) !bool {
    if (indexOf(out.items, kernel) != null) return true;
    try out.append(gpa, try gpa.dupe(lr0.Item, kernel));
    return false;
}

const testing = std.testing;

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

fn eqOf(gr: *const g.Grammar) u32 {
    for (0..gr.terminal_count) |t| {
        if (std.mem.eql(u8, gr.nameOf(@intCast(t)), "=")) return @intCast(t);
    }
    unreachable;
}
