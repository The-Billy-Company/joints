//! Nullability and FIRST, over the whole symbol space.
//!
//! Two facts, one fixpoint, because they are the same fixpoint: a production
//! contributes to its left-hand side's FIRST exactly as far as its right-hand
//! side stays nullable, so the walk that discovers nullability is the walk that
//! accumulates FIRST. Splitting them would mean iterating twice to learn one
//! thing.
//!
//! Rows cover *every* symbol, not just nonterminals. A terminal's FIRST is the
//! singleton containing itself, which is trivially true and worth a row anyway:
//! it makes `ofSuffix` a loop with no branch on which half of the symbol space
//! it is walking, and that loop is the inner loop of an LR(1) closure.
//!
//! The row width includes the end-of-input column even though no FIRST set can
//! contain it. An LR(1) closure unions FIRST of a suffix with an inherited
//! lookahead that *can* be end-of-input, and a set that cannot represent it
//! would force the caller to special-case the one bit that matters most.
//!
//! One trap, because it is invisible until it bites: this is the **optimistic**
//! FIRST, the one every textbook states. A production contributes its prefix
//! without ever asking whether the rest of the body can finish, so a symbol
//! that derives no terminal string at all still comes back with an inhabited
//! FIRST — `S -> live loop` has `FIRST(live)` in it whether or not `loop` can
//! ever bottom out. FIRST is therefore only meaningful on a grammar already
//! known productive, and "does this derive anything" is a different fixpoint,
//! answered by `Grammar.barren`.

const std = @import("std");
const g = @import("../copy/grammar.zig");
const sets = @import("sets.zig");

pub const First = struct {
    /// One row per symbol, `terminal_count + 1` bits wide.
    set: sets.Matrix,
    /// Per nonterminal index, whether it derives the empty string.
    empty: []bool,
    terminal_count: u32,

    pub fn deinit(f: *First, gpa: std.mem.Allocator) void {
        f.set.deinit(gpa);
        gpa.free(f.empty);
        f.* = undefined;
    }

    pub fn nullable(f: First, s: g.Symbol) bool {
        return s >= f.terminal_count and f.empty[s - f.terminal_count];
    }

    /// Whether every symbol of `rhs` is nullable — so the whole sequence is.
    pub fn nullableAll(f: First, rhs: []const g.Symbol) bool {
        for (rhs) |s| if (!f.nullable(s)) return false;
        return true;
    }

    pub fn has(f: First, s: g.Symbol, terminal: u32) bool {
        return f.set.isSet(s, terminal);
    }

    /// Union FIRST of `rhs` into row `dst` of `into`, and report whether `rhs`
    /// is nullable — which is what the caller needs to know to decide whether
    /// its own inherited lookahead also belongs there.
    pub fn ofSuffix(f: First, into: sets.Matrix, dst: usize, rhs: []const g.Symbol) bool {
        for (rhs) |s| {
            into.unionFrom(dst, f.set, s);
            if (!f.nullable(s)) return false;
        }
        return true;
    }
};

pub fn build(gpa: std.mem.Allocator, gr: *const g.Grammar) !First {
    const width = gr.terminal_count + 1;
    var f: First = .{
        .set = try sets.Matrix.init(gpa, gr.symbolCount(), width),
        .empty = try gpa.alloc(bool, gr.nonterminalCount()),
        .terminal_count = gr.terminal_count,
    };
    errdefer f.deinit(gpa);
    @memset(f.empty, false);
    for (0..gr.terminal_count) |t| f.set.set(t, t);

    // One fixpoint for both facts. A production stops contributing at its first
    // non-nullable symbol, and nullability learned this round widens what the
    // next round can see past — so both keep the loop alive.
    var changed = true;
    while (changed) {
        changed = false;
        for (gr.productions) |p| {
            const n = p.lhs - gr.terminal_count;
            for (p.rhs) |s| {
                changed = f.set.unionInto(p.lhs, s) or changed;
                if (!f.nullable(s)) break;
            } else if (!f.empty[n]) {
                f.empty[n] = true;
                changed = true;
            }
        }
    }
    return f;
}

const testing = std.testing;

/// `S -> A B`, `A -> a | ε`, `B -> b`. Small enough to check by hand and big
/// enough to need the fixpoint: FIRST(S) can only learn `b` after A is known
/// nullable, which happens on a later pass than FIRST(S) first gets touched.
fn nullableChain(gpa: std.mem.Allocator) !g.Grammar {
    var b = g.Builder.init(gpa);
    defer b.deinit();
    const a_tok = try b.intern("a", "a", .{ .literal = "a" });
    const b_tok = try b.intern("b", "b", .{ .literal = "b" });
    const start = try b.intern("$start", "$start", null);
    const s = try b.intern("S", "S", null);
    const a = try b.intern("A", "A", null);
    const bb = try b.intern("B", "B", null);
    try b.addProduction(start, &.{s}, &.{});
    try b.addProduction(s, &.{ a, bb }, &.{});
    try b.addProduction(a, &.{a_tok}, &.{});
    try b.addProduction(a, &.{}, &.{});
    try b.addProduction(bb, &.{b_tok}, &.{});
    return b.finish("chain", start, &.{}, &.{});
}

test "first reaches past a nullable prefix, and nullability stops at the first solid symbol" {
    var gr = try nullableChain(testing.allocator);
    defer gr.deinit();
    var f = try build(testing.allocator, &gr);
    defer f.deinit(testing.allocator);

    const a_tok: g.Symbol = 0;
    const b_tok: g.Symbol = 1;
    const s = gr.productions[1].lhs;
    const a = gr.productions[1].rhs[0];
    const bb = gr.productions[1].rhs[1];

    try testing.expect(f.nullable(a));
    try testing.expect(!f.nullable(bb));
    try testing.expect(!f.nullable(s));
    // S can start with either, because A may vanish.
    try testing.expect(f.has(s, a_tok));
    try testing.expect(f.has(s, b_tok));
    try testing.expect(!f.has(bb, a_tok));
    // A terminal is its own FIRST and nothing else's.
    try testing.expect(f.has(a_tok, a_tok));
    try testing.expect(!f.has(a_tok, b_tok));
}

test "a suffix reports its own nullability while contributing what it can start with" {
    var gr = try nullableChain(testing.allocator);
    defer gr.deinit();
    var f = try build(testing.allocator, &gr);
    defer f.deinit(testing.allocator);

    var out = try sets.Matrix.init(testing.allocator, 1, gr.terminal_count + 1);
    defer out.deinit(testing.allocator);

    const rhs = gr.productions[1].rhs; // A B
    try testing.expect(!f.ofSuffix(out, 0, rhs));
    try testing.expectEqual(@as(usize, 2), out.count(0));
    // The empty suffix is nullable and contributes nothing, which is what lets
    // a completed item inherit its lookahead unchanged.
    try testing.expect(f.ofSuffix(out, 0, rhs[2..]));
    try testing.expectEqual(@as(usize, 2), out.count(0));
}
