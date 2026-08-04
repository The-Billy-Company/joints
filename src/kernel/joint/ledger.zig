//! What a run assumed about the stack it could not see — one claim per symbol it
//! popped from below its own base, read bottom-to-top so the deepest claim is the
//! bottom and the base is just past the top.
//!
//! A run that never reaches below its base has an empty ledger and is a closed
//! statement about itself. A run that does reach below assumed, at every depth it
//! passed, that a particular symbol stood there and that the table would find a
//! particular state under it. Both halves are load-bearing and neither implies the
//! other, which took three representations to learn:
//!
//!   * **The symbol** is what the run *knows*. A reduction pops a whole
//!     right-hand side, so the string below the base is not a guess about
//!     content — it is `rhs[0..below]`, spelled out. And the left neighbour
//!     pushed those symbols, so it can check them exactly. Two scenarios that
//!     popped different strings are told apart here and nowhere else.
//!   * **The state** is what the run *consulted*. A limb splits when the table
//!     gives two of its scenarios different actions, and the thing that
//!     distinguishes the halves afterwards is which states each still believes
//!     possible at the depth they parted. Drop that and two branches with the
//!     same pop depth become indistinguishable.
//!
//! Why a column and not one claim. The obvious element is `(depth, floor)` — how
//! far down, and what was there — and it is what this had until the monoid law was
//! checked against a real table. When a run pops past its left neighbour
//! entirely, the neighbour's own floor ends up at a depth *interior* to the pair,
//! and a single field has nowhere to put it: `(a·b)·c` keeps a constraint that
//! `a·(b·c)` has already thrown away, so the two disagree and there is no monoid.
//! Approximating it — asking the automaton whether *any* string of that length
//! reaches it — fails too, because reverse reachability does not distribute over
//! intersection. Associativity is the only reason to want any of this, so the
//! interior claim has to be kept at its real depth. That is the column.
//!
//! It is not the pop string in another costume either, though it contains one.
//! The first version recorded the popped symbols as an interned *string*, which
//! made every hypothesis about the unseen left its own element — 1024 of them
//! where 68 configurations existed, because sixteen guesses about the same stack
//! were written sixteen ways. A column of *sets* holds the same information and
//! lets two hypotheses that a neighbour cannot tell apart be one element.

const std = @import("std");
const stack = @import("stack.zig");
const roster = @import("roster.zig");

/// What stood at one depth: which symbol, and which state under it. Sets rather
/// than singletons because a fused limb is several runs at once and no longer
/// knows which of them it is.
pub const Claim = struct {
    /// States the table could have found here. `anywhere` when nothing looked.
    states: roster.Id = anywhere,
    /// Symbols that could have stood here. `anywhere` when nothing looked, which
    /// in practice never happens: a run always knows what it popped.
    symbols: roster.Id = anywhere,

    /// A depth a run passed without any belief about it. Not reachable by
    /// interning, so it can be a sentinel rather than a lookup.
    pub const nothing: Claim = .{};

    /// Whether a symbol at a known depth, standing on a known state, is one this
    /// claim would accept.
    pub fn admits(k: Claim, p: *const roster.Pool, state: roster.State, symbol: roster.State) bool {
        return holds(p, k.states, state) and holds(p, k.symbols, symbol);
    }

    fn holds(p: *const roster.Pool, set: roster.Id, member: roster.State) bool {
        return set == anywhere or p.has(set, member);
    }
};

pub const Pool = stack.Column(Claim);
pub const Id = Pool.Id;

/// A set nobody narrowed. The unit of `meet` and the absorbing element of
/// `widen`, which is what makes an unconsulted depth free to carry.
pub const anywhere: roster.Id = @enumFromInt(std.math.maxInt(u32));

/// The claim at `depth` symbols below the base, or nothing past the bottom.
/// Depth 1 is the first symbol popped; depth 0 is the base itself, which is not
/// a ledger's business — it is the state the run was entered in.
pub fn at(p: *const Pool, id: Id, depth: u32) Claim {
    if (depth == 0 or depth > p.depth(id)) return .nothing;
    return p.top(p.drop(id, depth - 1).?).?;
}

/// The states the whole pop uncovered — the claim a left neighbour has to satisfy
/// first, and the one the walk starts from.
pub fn floor(p: *const Pool, id: Id) roster.Id {
    return (p.bottom(id) orelse Claim.nothing).states;
}

/// Narrow the deepest claim's states, leaving its symbol alone. The states down
/// there go on narrowing as neighbours arrive; the symbol was never in doubt.
pub fn seat(p: *Pool, id: Id, states: roster.Id) !Id {
    const deep = p.bottom(id) orelse return id;
    return p.reseat(id, .{ .states = states, .symbols = deep.symbols });
}

/// One more popped depth, deeper than everything already recorded.
pub fn sink(p: *Pool, id: Id, claim: Claim) !Id {
    return p.concat(try p.push(.empty, claim), id);
}

/// A whole right-hand side popped at once: `symbols` bottom-to-top, with `under`
/// the states the table could find beneath all of them. The shape every real pop
/// has, because a reduction removes a production's right-hand side and consults
/// the state under it rather than the states inside it.
pub fn plunge(
    p: *Pool,
    sets: *roster.Pool,
    id: Id,
    symbols: []const roster.State,
    under: roster.Id,
) !Id {
    var base: Id = .empty;
    for (symbols, 0..) |sym, i| {
        base = try p.push(base, .{
            .states = if (i == 0) under else anywhere,
            .symbols = try sets.one(sym),
        });
    }
    return p.concat(base, id);
}

/// Both claims at every depth, which is what it means for two runs to be talking
/// about the same stack. Null when some depth has nothing both would accept: the
/// pair describes a parse that never happened.
pub fn agree(p: *Pool, sets: *roster.Pool, a: Id, b: Id) !?Id {
    if (a == b) return a;
    var out: Id = .empty;
    var d = @max(p.depth(a), p.depth(b));
    while (d > 0) : (d -= 1) {
        const x = at(p, a, d);
        const y = at(p, b, d);
        const both: Claim = .{
            .states = try meet(sets, x.states, y.states),
            .symbols = try meet(sets, x.symbols, y.symbols),
        };
        if (both.states == .nowhere or both.symbols == .nowhere) return null;
        out = try p.push(out, both);
    }
    return out;
}

/// Either claim at every depth — the ledger of a run that is one of two runs and
/// no longer remembers which. Both must be the same depth, since a ledger's depth
/// is how far below the base it reached and two runs that reached different
/// distances are not candidates for being confused.
///
/// This is the one deliberately lossy operation in the algebra, and where it is
/// used is the whole reason it exists. Fusing limbs on the exact column makes the
/// cursor's limb count the number of distinct *interior histories*, which on real
/// grammars is exponential in the segment length — a `}` five deep in an object
/// carries a different interior than the same `}` five deep in an array, and the
/// two never reconverge. Fusing on the depth alone and widening the interiors
/// collapses the count to the number of distinct depths, which is small, at the
/// price of admitting a path that mixes two histories.
pub fn join(p: *Pool, sets: *roster.Pool, a: Id, b: Id) !Id {
    if (a == b) return a;
    std.debug.assert(p.depth(a) == p.depth(b));
    var out: Id = .empty;
    var d = p.depth(a);
    while (d > 0) : (d -= 1) {
        const x = at(p, a, d);
        const y = at(p, b, d);
        out = try p.push(out, .{
            .states = try widen(sets, x.states, y.states),
            .symbols = try widen(sets, x.symbols, y.symbols),
        });
    }
    return out;
}

/// Two beliefs about one depth, widened. `anywhere` absorbs: a depth one run
/// never looked at is a depth the pair cannot claim anything about.
pub fn widen(sets: *roster.Pool, a: roster.Id, b: roster.Id) !roster.Id {
    if (a == anywhere or b == anywhere) return anywhere;
    return sets.join(a, b);
}

/// Two beliefs about one depth, narrowed, or `.nowhere` when they exclude each
/// other. `anywhere` is the unit, which is why an unconsulted depth costs nothing.
pub fn meet(sets: *roster.Pool, a: roster.Id, b: roster.Id) !roster.Id {
    if (a == anywhere) return b;
    if (b == anywhere) return a;
    return sets.meet(a, b);
}

const testing = std.testing;

test "a plunge writes the symbols it took at the depths they stood at" {
    var p = Pool.init(testing.allocator);
    defer p.deinit();
    var f = roster.Pool.init(testing.allocator);
    defer f.deinit();

    // Two pops: one symbol, then a three-symbol right-hand side. Every depth
    // knows its symbol, because a reduction takes a production's whole right side
    // and that string is not a guess. Only the far end of each pop was
    // *consulted*, so the states in between are holes and the ledger says so
    // rather than inventing a constraint there.
    const near = try f.one(3);
    const far = try f.of(&.{ 5, 6 });
    var l: Id = .empty;
    l = try plunge(&p, &f, l, &.{9}, near);
    l = try plunge(&p, &f, l, &.{ 7, 8, 9 }, far);

    try testing.expectEqual(@as(u32, 4), p.depth(l));
    try testing.expectEqual(near, at(&p, l, 1).states);
    try testing.expectEqual(try f.one(9), at(&p, l, 1).symbols);
    // The second plunge sits under the first: its top symbol is `rhs[2]`.
    try testing.expectEqual(anywhere, at(&p, l, 2).states);
    try testing.expectEqual(try f.one(9), at(&p, l, 2).symbols);
    try testing.expectEqual(try f.one(8), at(&p, l, 3).symbols);
    try testing.expectEqual(far, at(&p, l, 4).states);
    try testing.expectEqual(try f.one(7), at(&p, l, 4).symbols);
    try testing.expectEqual(far, floor(&p, l));

    // Past the bottom, and at the base itself, a ledger has nothing to say.
    try testing.expectEqual(Claim.nothing, at(&p, l, 5));
    try testing.expectEqual(Claim.nothing, at(&p, l, 0));
    try testing.expectEqual(anywhere, floor(&p, .empty));

    // Seating narrows the deepest states and leaves its symbol alone: which
    // state is down there goes on narrowing as neighbours arrive, but what was
    // taken off was never in doubt.
    const seated = try seat(&p, l, try f.one(5));
    try testing.expectEqual(try f.one(5), at(&p, seated, 4).states);
    try testing.expectEqual(try f.one(7), at(&p, seated, 4).symbols);
    try testing.expectEqual(at(&p, l, 3), at(&p, seated, 3));
    try testing.expectEqual(@as(Id, .empty), try seat(&p, .empty, try f.one(5)));
}

test "agreeing keeps every claim either side made" {
    var p = Pool.init(testing.allocator);
    defer p.deinit();
    var f = roster.Pool.init(testing.allocator);
    defer f.deinit();

    // One ledger constrains depth 1 and nothing else; the other constrains
    // depth 2 out of three. The meet has to hold all of it — and be as deep as
    // the deeper of the two, since a claim nobody contradicted is still a claim.
    const wide = try f.of(&.{ 1, 2, 3 });
    const narrow = try f.of(&.{ 2, 3 });
    const shallow = try sink(&p, .empty, .{ .states = wide });
    const deep = try sink(&p, try sink(&p, try p.push(.empty, .nothing), .nothing), .{ .states = narrow });

    const both = (try agree(&p, &f, shallow, deep)).?;
    try testing.expectEqual(@as(u32, 3), p.depth(both));
    try testing.expectEqual(wide, at(&p, both, 1).states);
    try testing.expectEqual(anywhere, at(&p, both, 2).states);
    try testing.expectEqual(narrow, at(&p, both, 3).states);

    // Overlapping claims at one depth narrow to the overlap.
    const other = try sink(&p, .empty, .{ .states = narrow });
    try testing.expectEqual(narrow, at(&p, (try agree(&p, &f, shallow, other)).?, 1).states);

    // And claims that share no state at all refuse the pairing outright.
    const elsewhere = try sink(&p, .empty, .{ .states = try f.one(9) });
    try testing.expectEqual(@as(?Id, null), try agree(&p, &f, shallow, elsewhere));

    // A disagreement about the *symbol* refuses just as hard, and it is the
    // half that separates two runs which popped equally far through different
    // strings — the case no state claim can see.
    const took_a = try sink(&p, .empty, .{ .symbols = try f.one(4) });
    const took_b = try sink(&p, .empty, .{ .symbols = try f.one(5) });
    try testing.expectEqual(@as(?Id, null), try agree(&p, &f, took_a, took_b));
}

test "identical ledgers are one value, however they were built" {
    var p = Pool.init(testing.allocator);
    defer p.deinit();
    var f = roster.Pool.init(testing.allocator);
    defer f.deinit();

    // The property the rank measurement rests on: two runs that assumed the same
    // things are one element, compared in one instruction, no matter what route
    // each took to the assumption.
    const under = try f.of(&.{ 4, 7 });
    const chunked = try plunge(&p, &f, .empty, &.{ 1, 2, 3 }, under);
    var stepped = try sink(&p, .empty, .{ .states = under, .symbols = try f.one(1) });
    stepped = try sink(&p, stepped, .{ .symbols = try f.one(2) });
    // Careful: `sink` goes *deeper*, so replaying a plunge means going the other
    // way. Built downward it is a different ledger, and that is the point — the
    // depths are ordered and the interning respects it.
    try testing.expect(chunked != stepped);

    var by_hand = try p.push(.empty, .{ .states = under, .symbols = try f.one(1) });
    by_hand = try p.push(by_hand, .{ .symbols = try f.one(2) });
    by_hand = try p.push(by_hand, .{ .symbols = try f.one(3) });
    try testing.expectEqual(chunked, by_hand);
}

test "widening two runs into one admits both and nothing narrower" {
    var p = Pool.init(testing.allocator);
    defer p.deinit();
    var f = roster.Pool.init(testing.allocator);
    defer f.deinit();

    // Fusing limbs is the cursor's one lossy move, so what it costs is worth
    // pinning: a run that took `4` standing on `1` and a run that took `5`
    // standing on `2`, once fused, admit both — and, unavoidably, the two mixed
    // pairings neither of them ever performed.
    const one = try sink(&p, .empty, .{ .states = try f.one(1), .symbols = try f.one(4) });
    const two = try sink(&p, .empty, .{ .states = try f.one(2), .symbols = try f.one(5) });
    const either = try join(&p, &f, one, two);
    const k = at(&p, either, 1);
    try testing.expect(k.admits(&f, 1, 4));
    try testing.expect(k.admits(&f, 2, 5));
    try testing.expect(k.admits(&f, 1, 5));
    try testing.expect(!k.admits(&f, 3, 4));
    try testing.expect(!k.admits(&f, 1, 6));

    // Widening is idempotent and a hole absorbs, or an unconsulted depth would
    // start costing something to carry.
    try testing.expectEqual(either, try join(&p, &f, either, one));
    const blind = try sink(&p, .empty, .nothing);
    try testing.expectEqual(Claim.nothing, at(&p, try join(&p, &f, one, blind), 1));
}
