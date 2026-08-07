//! The stack-effect monoid — M2, and the one piece of this design that has to
//! be proved rather than cited.
//!
//! Consuming a run of tokens does exactly one thing to an LR stack: it removes
//! some symbols from the top and leaves some string of symbols in their place.
//! Write that as `(α, σ)` — pop `α`, push `σ`, both read bottom-to-top — and the
//! effect of doing one run and then another is
//!
//! ```
//! |σ₁| ≥ |α₂|,  top(σ₁, |α₂|) = α₂   →   (α₁,               σ₁[0 .. |σ₁|−|α₂|] · σ₂)
//! |σ₁| < |α₂|,  top(α₂, |σ₁|) = σ₁   →   (α₂[0 .. |α₂|−|σ₁|] · α₁,          σ₂)
//! ```
//!
//! with identity `(ε, ε)`. The two cases are the same statement read from either
//! side: the second run eats into what the first one left, and whatever it eats
//! past that it charges to whoever comes before.
//!
//! **What came off is a depth, and what was under it is a ledger of rosters**,
//! and getting to that took two corrections in opposite directions, both forced
//! by measurement rather than argument.
//!
//! The first correction undid an overshoot. Carrying the popped *symbols* looks
//! strictly better — it is more information, and it is free to record — and it
//! is what this module did until the corpus was measured. It is ruinous. The
//! symbols a segment pops below its own base are not observed; they are *deduced
//! from the scenario it is entertaining*, so recording them makes every
//! hypothesis about the unseen left a separate element. Four levels of JSON
//! nesting produced 1024 elements where 68 configurations existed, purely
//! because sixteen guesses about the same stack were being written down sixteen
//! ways. Forgetting the symbols dropped the p99 rank from 1920 to 68 and the
//! fan rate from 5.8% to zero. Nothing was lost, because **the left neighbour
//! already knows the symbols** — it pushed them.
//!
//! The second: what a run assumed cannot be reduced to one fact. Its guard is a
//! **roster per popped depth** ([`ledger.zig`](ledger.zig)), not a single floor,
//! because when a run pops past its left neighbour entirely the neighbour's own
//! floor lands at a depth interior to the pair — and a pair that cannot write
//! that down is not associative. Both cheaper stories were tried and both fail;
//! the ledger's own header records how.
//!
//! Each roster is a set rather than a state, and that is the pruning that pays
//! for all of it. Popping a `{` uncovers exactly the four places a `{` may be
//! written, and all four then do the identical thing to the stack, so splitting
//! into four answers doubles the joint on every closing brace and learns
//! nothing. One answer guarded by a four-state roster says the same thing and
//! stays one answer. Composition **intersects**: the left neighbour walks its own
//! push, lands somewhere definite, and every scenario the guard held that
//! disagrees is dropped. A chain of segments narrows instead of branching, and a
//! roster down to one member is a run that has learned exactly where it stands.
//!
//! That is why this module knows about the automaton at all. The depth-and-push
//! algebra below is a monoid on paper and a relation in practice; the guard is
//! what makes it a function.
//!
//! So composition is **partial**, and that is the point rather than a wart. A
//! `null` is not an error: it is the algebra refusing a pairing that no parse
//! could have produced, which is exactly the pruning that keeps a joint small.
//! Where it is defined it is associative, which is all a scan needs — the
//! product of a range is derivable from the products of its parts, in any
//! association, so the parse of a file becomes a balanced tree of effects
//! instead of a walk. An edit rebuilds the O(log n) products above it and
//! nothing else, wherever it lands, which is the thing tree-sitter's directional
//! reuse cannot do.
//!
//! An effect is twelve bytes and two effects compare in one instruction, because
//! the guard and the push are both hash-consed ids and the entry is a state.
//! That is deliberate: every question asked of this monoid is an equality
//! question, and the measurement that decides whether the whole design is real —
//! how many distinct effects a segment has across entry states — is a count of
//! distinct twelve-byte values.

const std = @import("std");
const stack = @import("stack.zig");
const roster = @import("roster.zig");
const ledger = @import("ledger.zig");
const press = @import("../../press/press.zig");

pub const Symbol = stack.Symbol;
pub const Pool = stack.Pool;

/// Everything an effect is interned against. Two pools rather than one because
/// they intern different things — symbol strings and state sets — and a type
/// that conflated them would let a stack be used as a guard.
pub const Arena = struct {
    stacks: *stack.Pool,
    floors: *roster.Pool,
    guards: *ledger.Pool,
    /// The goto graph, which is what turns a guess about the floor into a
    /// question with an answer.
    c: *const press.Collection,
};

pub const Effect = struct {
    /// The state the run began in. Its domain key, and the one thing about it
    /// that is observed rather than assumed.
    entry: u32 = nowhere,
    /// What it assumed about the stack below its base: one roster per symbol it
    /// took, deepest at the bottom. Empty means it took nothing and is a closed
    /// statement about itself.
    guard: ledger.Id = .empty,
    /// Symbols left in their place, bottom-to-top.
    push: stack.Pool.Id = .empty,

    /// An entry nowhere in the automaton. Only the identity has one: every real
    /// run begins somewhere, and where it began is a claim about its neighbour
    /// even when the run never pops.
    pub const nowhere: u32 = std.math.maxInt(u32);

    /// Doing nothing. The identity on both sides.
    pub const identity: Effect = .{};

    /// The bytes a parse read and then declined to hold a stack over: the span
    /// a mend stepped across. Not a stack transformation, and deliberately not
    /// spelled as one - it is the absorbing element, and `compose` refuses on
    /// either side of it, so anything spanning it is refused too.
    ///
    /// The zero was already here; it was only unrepresentable. `compose`
    /// already returns null for a pairing that never happened and
    /// `arbor.mul` already reads null as absorbing, so a spine node over a
    /// break already carries the right answer and the nodes either side of it
    /// already carry theirs. All this constant does is let a *leaf* be the
    /// thing the algebra could already say.
    ///
    /// It must not be the identity. An identity composes away, which would
    /// claim the two sides were adjacent - the one thing a mend exists to
    /// deny - and would hand back a product for a file whose stack the parser
    /// threw away.
    pub const broken: u32 = std.math.maxInt(u32) - 1;
    pub const hole: Effect = .{ .entry = broken };

    pub fn eql(a: Effect, b: Effect) bool {
        return a.entry == b.entry and a.guard == b.guard and a.push == b.push;
    }

    /// A key for counting distinct effects.
    pub const Key = struct { entry: u32, guard: ledger.Id, push: stack.Pool.Id };

    pub fn key(e: Effect) Key {
        return .{ .entry = e.entry, .guard = e.guard, .push = e.push };
    }

    /// What the run *did*, with the guard left out — and the thing rung one
    /// counts. The guard is a claim about the neighbour, recoverable from where
    /// the run was entered; two entry states that make the same edit to the
    /// stack are one answer for the purpose of tabulating a joint, even though
    /// they are separate elements for the purpose of composing one.
    pub const Shape = struct { pop: u32, push: stack.Pool.Id };

    pub fn shape(e: Effect, x: Arena) Shape {
        return .{ .pop = e.reaches(x), .push = e.push };
    }

    /// How far below its own base a run reached. Zero means it composes with
    /// anything on its left without consulting it, and that is the case worth
    /// being fast.
    pub fn reaches(e: Effect, x: Arena) u32 {
        return x.guards.depth(e.guard);
    }

    /// The deepest thing it assumed, which is the claim a left neighbour has to
    /// satisfy first.
    pub fn floor(e: Effect, x: Arena) roster.Id {
        return ledger.floor(x.guards, e.guard);
    }

    /// Whether this run could have happened at the very beginning of the input,
    /// where there is nothing under the stack for it to have taken.
    ///
    /// The one fact about the world the algebra deliberately does not carry. A
    /// pair whose right half reached past its left half's push charges the excess
    /// to whoever comes further left, and refuses nothing, because the symbols
    /// down there belong to a run neither of them can name — the only predicate
    /// available is "some string of that length reaches here", and reverse
    /// reachability does not distribute over intersection, so putting it in
    /// composition costs associativity. Left as a boundary condition it costs one
    /// comparison, at the one place where the answer is known for certain.
    pub fn grounded(e: Effect, x: Arena) bool {
        return e.reaches(x) == 0;
    }

    pub fn format(e: Effect, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.print("({d}: -{d} +{d})", .{
            e.entry,
            @intFromEnum(e.guard),
            @intFromEnum(e.push),
        });
    }
};

/// `a` and then `b`, or null when they describe runs that were never adjacent.
/// A refusal is the pruning that keeps a joint small, not an error.
///
/// The whole of the work is one question asked once per scenario `a` still
/// entertains: **stand at `a`'s base and walk its push — does everything `b`
/// claims to have found on the way hold?** `b`'s entry is the state at the top of
/// that walk, and `b`'s claim at depth `d` is the state `d` symbols down from it.
/// A scenario that disagrees anywhere along the walk describes a parse that never
/// happened and leaves. This is the check the popped symbols used to stand in
/// for, and it is strictly the better one: `a` is the run that actually pushed
/// them, so it is not guessing.
pub fn compose(x: Arena, a: Effect, b: Effect) !?Effect {
    // Before the identity checks, because absorbing beats neutral: a hole
    // beside the identity is still a hole.
    if (a.entry == Effect.broken or b.entry == Effect.broken) return null;
    if (a.entry == Effect.nowhere) return b;
    if (b.entry == Effect.nowhere) return a;
    const p = x.stacks;

    const left = p.depth(a.push);
    const eaten = b.reaches(x);
    // Borrowed from the stack pool's scratch, so every `concat` below has to wait
    // until the walking is done.
    const path = try p.flatten(a.push);
    const seen = Walk{ .x = x, .path = path, .b = b, .eaten = eaten };

    // `a`'s own claim about its base is either a roster, when it popped to get
    // there, or the single state it was entered in.
    var guard = a.guard;
    if (guard == .empty) {
        if (!seen.holds(a.entry)) return null;
    } else {
        const narrowed = try x.floors.refine(ledger.floor(x.guards, guard), seen, Walk.holds);
        if (narrowed == .nowhere) return null;
        guard = try ledger.seat(x.guards, guard, narrowed);
    }

    if (left >= eaten) return .{
        .entry = a.entry,
        .guard = guard,
        .push = try p.concat(p.drop(a.push, eaten).?, b.push),
    };
    // `b` popped through everything `a` left and kept going. The claims it made
    // below `a`'s base are about symbols neither of the pair pushed, so they are
    // charged to whoever precedes the pair — appended under `a`'s own, at the
    // depths they really sit at. Nothing is approximated and nothing is dropped,
    // which is the entire reason the guard is a column and not one roster.
    //
    // Whether anything is *down there to take* is not asked, and cannot be
    // without losing associativity — see `Effect.grounded`, which is where that
    // question is answered instead.
    return .{
        .entry = a.entry,
        .guard = try x.guards.concat(x.guards.drop(b.guard, left).?, guard),
        .push = b.push,
    };
}

/// One scenario's survival test: stand at the left run's base and walk its push,
/// checking the right run's claims against each height on the way.
const Walk = struct {
    x: Arena,
    path: []const Symbol,
    b: Effect,
    eaten: u32,

    fn holds(w: Walk, from: roster.State) bool {
        const left: u32 = @intCast(w.path.len);
        var at = from;
        for (w.path, 0..) |sym, i| {
            // Height `i` above the left base is depth `left - i` below the right
            // base — a claim only when the right run reached that far. Both halves
            // get checked here: `at` is the state the right run would have had to
            // find, `sym` is the symbol it believed it was taking off, and the
            // left run is the one that put it there.
            const d = left - @as(u32, @intCast(i));
            const claim = ledger.at(w.x.guards, w.b.guard, if (d <= w.eaten) d else 0);
            if (!claim.admits(w.x.floors, at, sym)) return false;
            at = w.x.c.goto(at, sym) orelse return false;
        }
        return at == w.b.entry;
    }
};

/// The product of a run of effects, left to right. The point of the monoid is
/// that this is *not* the only way to get the answer — any association gives
/// the same one — but it is the way a single thread wants it.
pub fn fold(x: Arena, effects: []const Effect) !?Effect {
    var acc: Effect = .identity;
    for (effects) |e| acc = try compose(x, acc, e) orelse return null;
    return acc;
}

/// The effect of a single reduction over a right-hand side standing on `under`:
/// take the right-hand side off, put the left-hand side on. Every parse effect is
/// a product of these and of shifts. The run's entry is where the whole
/// right-hand side had already carried the parser to, which is the only state it
/// ever observed.
pub fn reduce(x: Arena, under: roster.State, rhs: []const Symbol, lhs: Symbol) !Effect {
    return .{
        .entry = x.c.walk(under, rhs) orelse return error.NoSuchParse,
        .guard = try ledger.plunge(x.guards, x.floors, .empty, rhs, try x.floors.one(under)),
        .push = try x.stacks.push(.empty, lhs),
    };
}

/// The effect of a single shift taken in `at`. It assumes nothing: a shift only
/// ever adds.
pub fn shift(x: Arena, at: roster.State, terminal: Symbol) !Effect {
    return .{ .entry = at, .push = try x.stacks.push(.empty, terminal) };
}

const testing = std.testing;

/// `S -> ( S ) | x`, and its automaton — the guard is a claim about a real
/// goto graph, so the algebra cannot be tested against invented states.
const Fix = struct {
    gr: press.Grammar,
    built: press.Result,
    p: Pool,
    r: roster.Pool,
    g: ledger.Pool,
    lp: Symbol,
    rp: Symbol,
    x: Symbol,
    s: Symbol,

    fn init() !*Fix {
        const gpa = testing.allocator;
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

        const f = try gpa.create(Fix);
        f.gr = try b.finish("parens", start, &.{}, &.{});
        f.built = try press.tables(gpa, &f.gr);
        f.p = Pool.init(gpa);
        f.r = roster.Pool.init(gpa);
        f.g = ledger.Pool.init(gpa);
        f.lp = 0;
        f.rp = 1;
        f.x = 2;
        f.s = f.gr.start + 1;
        return f;
    }

    fn deinit(f: *Fix) void {
        f.g.deinit();
        f.r.deinit();
        f.p.deinit();
        f.built.deinit();
        f.gr.deinit();
        testing.allocator.destroy(f);
    }

    fn arena(f: *Fix) Arena {
        return .{ .stacks = &f.p, .floors = &f.r, .guards = &f.g, .c = &f.built.collection };
    }

    /// A run entered in `entry` that took the string `pop` off a stack it believes
    /// stood on one of `under`, and left `push`. The popped string is spelled out
    /// rather than counted because that is what a real run knows: it is the
    /// right-hand side of the production it reduced.
    fn took(
        f: *Fix,
        entry: u32,
        pop: []const Symbol,
        under: []const roster.State,
        push: []const Symbol,
    ) !Effect {
        return .{
            .entry = entry,
            .guard = if (pop.len == 0) .empty else try ledger.plunge(
                &f.g,
                &f.r,
                .empty,
                pop,
                try f.r.of(under),
            ),
            .push = try f.p.of(push),
        };
    }
};

/// A spread wide enough to hit every verdict: pops the next push satisfies, pops
/// it does not, floors the walk reaches and floors it cannot, guards narrow
/// enough to refuse and wide enough to be narrowed.
fn sample(f: *Fix, out: *std.ArrayList(Effect)) !void {
    const strings = [_][]const Symbol{ &.{}, &.{f.x}, &.{ f.lp, f.s } };
    const pops = [_][]const Symbol{ &.{f.x}, &.{ f.s, f.rp } };
    const unders = [_][]const roster.State{ &.{0}, &.{ 0, f.built.collection.goto(0, f.lp).? } };
    for (0..@min(3, f.built.collection.states.len)) |entry| for (strings) |push| {
        try out.append(testing.allocator, try f.took(@intCast(entry), &.{}, &.{}, push));
        for (pops) |pop| for (unders) |under| {
            try out.append(testing.allocator, try f.took(@intCast(entry), pop, under, push));
        };
    };
}

/// Both defined and equal, or both refused. Partial associativity is the real
/// claim: a scan may reassociate freely, including across the pairings that do
/// not exist.
fn same(a: ?Effect, b: ?Effect) bool {
    if (a == null or b == null) return a == null and b == null;
    return Effect.eql(a.?, b.?);
}

test "identity does nothing from either side" {
    const f = try Fix.init();
    defer f.deinit();
    var all: std.ArrayList(Effect) = .empty;
    defer all.deinit(testing.allocator);
    try sample(f, &all);

    for (all.items) |e| {
        try testing.expect(same(e, try compose(f.arena(), .identity, e)));
        try testing.expect(same(e, try compose(f.arena(), e, .identity)));
    }
}

test "composition associates over every pairing of the sample" {
    const f = try Fix.init();
    defer f.deinit();
    var all: std.ArrayList(Effect) = .empty;
    defer all.deinit(testing.allocator);
    try sample(f, &all);

    var defined: u32 = 0;
    for (all.items) |a| for (all.items) |b| for (all.items) |c| {
        const ab = try compose(f.arena(), a, b);
        const bc = try compose(f.arena(), b, c);
        const left = if (ab) |x| try compose(f.arena(), x, c) else null;
        const right = if (bc) |x| try compose(f.arena(), a, x) else null;
        try testing.expect(same(left, right));
        defined += @intFromBool(left != null);
    };
    // Not vacuous in either direction: the sample contains triples that do
    // compose and triples that do not, and the law is checked on both.
    try testing.expect(defined > 0);
    try testing.expect(defined < all.items.len * all.items.len * all.items.len);
}

test "a pop that outruns the push is charged to the left" {
    const f = try Fix.init();
    defer f.deinit();
    const inside = f.built.collection.goto(0, f.lp).?;
    const x = f.arena();

    // A run entered inside a paren, which parsed `S` and shifted the `)`; then
    // the reduction of `S -> ( S )`, which takes all three. Only two of those
    // three were left standing by the run, so one symbol of debt is charged to
    // whoever came before — and at the depth it really sits at, one below the
    // pair's own base.
    const a = try f.took(inside, &.{}, &.{}, &.{ f.s, f.rp });
    const b = try reduce(x, 0, &.{ f.lp, f.s, f.rp }, f.s);
    const ab = (try compose(x, a, b)).?;
    try testing.expectEqual(@as(u32, 1), ab.reaches(x));
    try testing.expectEqual(try f.r.one(0), ab.floor(x));
    try testing.expectEqual(try f.p.of(&.{f.s}), ab.push);
    // The pair was entered where the left run was, not where the right one was:
    // a composite is a statement about the whole segment's beginning.
    try testing.expectEqual(inside, ab.entry);
}

test "a pop the push absorbs leaves the left alone" {
    const f = try Fix.init();
    defer f.deinit();
    const x = f.arena();

    // The same reduction, but the run on the left shifted the `(` itself, so
    // everything the reduction takes is its own and nothing is charged left.
    const a = try f.took(0, &.{}, &.{}, &.{ f.lp, f.s, f.rp });
    const b = try reduce(x, 0, &.{ f.lp, f.s, f.rp }, f.s);
    const ab = (try compose(x, a, b)).?;
    try testing.expectEqual(@as(u32, 0), ab.reaches(x));
    try testing.expectEqual(ledger.Id.empty, ab.guard);
    try testing.expectEqual(try f.p.of(&.{f.s}), ab.push);
}

test "a pop the left never left standing does not compose at all" {
    const f = try Fix.init();
    defer f.deinit();
    const x = f.arena();

    // Both runs pop one symbol, so the lengths agree and only the automaton can
    // tell that these two were never adjacent. The right one reduces `S -> x`
    // off a floor it says is the start state; the left one pushed `( )`, so
    // dropping one leaves a `(` and the walk lands *inside* a paren instead. A
    // depth with no claim attached would take this pairing; a ledger does not.
    const a = try f.took(0, &.{}, &.{}, &.{ f.lp, f.rp });
    const b = try reduce(x, 0, &.{f.x}, f.s);
    try testing.expectEqual(@as(?Effect, null), try compose(x, a, b));
}

test "a claim below the pair's own base is kept at its real depth" {
    const f = try Fix.init();
    defer f.deinit();
    const x = f.arena();
    const opened = f.built.collection.walk(0, &.{ f.lp, f.s }).?;
    const closed = f.built.collection.walk(0, &.{ f.lp, f.s, f.rp }).?;

    // The case a single floor cannot express, which is the whole reason the guard
    // is a column. `deep` pops three where `shallow` left one, so two symbols of
    // the debt belong to a run neither of them can see — and `shallow`'s own claim
    // about *its* floor ends up at a depth interior to the pair: below the pair's
    // base, above the pair's floor.
    const shallow = try f.took(closed, &.{f.rp}, &.{opened}, &.{f.rp});
    const deep = try reduce(x, 0, &.{ f.lp, f.s, f.rp }, f.s);
    const owing = (try compose(x, shallow, deep)).?;
    try testing.expectEqual(@as(u32, 3), owing.reaches(x));
    try testing.expectEqual(try f.r.one(opened), ledger.at(&f.g, owing.guard, 1).states);
    try testing.expectEqual(ledger.anywhere, ledger.at(&f.g, owing.guard, 2).states);
    try testing.expectEqual(try f.r.one(0), ledger.at(&f.g, owing.guard, 3).states);

    // And the symbol half survives the splice at its real depth too. It is the
    // half that answers "was it *this* string down there", which is the question
    // the states cannot ask: `( S )` read bottom-to-top is `lp` deepest.
    try testing.expectEqual(try f.r.one(f.rp), ledger.at(&f.g, owing.guard, 1).symbols);
    try testing.expectEqual(try f.r.one(f.s), ledger.at(&f.g, owing.guard, 2).symbols);
    try testing.expectEqual(try f.r.one(f.lp), ledger.at(&f.g, owing.guard, 3).symbols);

    // Every depth of it is then checked against a left neighbour that really does
    // have the symbols: `( S )` satisfies all three and composes. That the
    // interior claim has to be *kept* rather than approximated is not visible in
    // one pairing — it is the associativity test, where dropping it makes
    // `(a·b)·c` disagree with `a·(b·c)`.
    const covering = try f.took(0, &.{}, &.{}, &.{ f.lp, f.s, f.rp });
    try testing.expect((try compose(x, covering, owing)) != null);

    // Nothing above refused it for reaching below the start state, and nothing
    // could have: the symbols down there belong to a neighbour further left. That
    // the file has no such neighbour is the caller's fact, and this is where the
    // caller states it.
    try testing.expect(!owing.grounded(x));
    try testing.expect(shallow.grounded(x) == false and deep.grounded(x) == false);
    try testing.expect(Effect.identity.grounded(x));
}

test "a right neighbour that guessed the wrong floor is refused by the walk" {
    const f = try Fix.init();
    defer f.deinit();
    const inside = f.built.collection.goto(0, f.lp).?;
    const x = f.arena();

    // The guard doing the work the popped symbols used to. Both of these reduce
    // `S -> x` after a run that left an `x` standing, so the pop is one symbol
    // either way and nothing about the lengths separates them. They differ only
    // in the state they claim was underneath — and the left run's own walk, over
    // symbols it really pushed, says which one is true.
    const a = try f.took(0, &.{}, &.{}, &.{ f.lp, f.x });
    const right = try reduce(x, inside, &.{f.x}, f.s);
    const wrong = try reduce(x, 0, &.{f.x}, f.s);
    try testing.expect((try compose(x, a, right)) != null);
    try testing.expectEqual(@as(?Effect, null), try compose(x, a, wrong));
}

test "a guard wide enough to be wrong is narrowed rather than believed" {
    const f = try Fix.init();
    defer f.deinit();
    const inside = f.built.collection.goto(0, f.lp).?;
    const x = f.arena();

    // What the roster buys. A segment that folded `S -> x` off an unknown prefix
    // cannot say where the `x` was written — the start state and inside a paren
    // both admit one — so it claims both and stays a single answer instead of
    // becoming two. Both scenarios reach the same state after the `x`, which is
    // why one entry still covers them.
    const loose = try f.took(f.built.collection.walk(0, &.{f.x}).?, &.{f.x}, &.{ 0, inside }, &.{f.s});

    // Put a `(` in front of it and one scenario survives. The composite carries
    // the *narrowed* guard, so the next neighbour inherits what this one learned
    // — the other scenario was never refuted by symbols, since both pop an `x`,
    // only by where the walk arrives.
    const opened = try f.took(0, &.{}, &.{}, &.{ f.lp, f.x });
    const joined = (try compose(x, opened, loose)).?;
    try testing.expectEqual(@as(u32, 0), joined.reaches(x));
    try testing.expectEqual(try f.p.of(&.{ f.lp, f.s }), joined.push);

    // Narrowing is visible where it matters. This run also cannot say where it
    // stood, but the `S` it left behind goes somewhere different from each of the
    // two places — so a neighbour that arrived after that `S` settles it, and the
    // composite hands the single survivor on rather than re-deriving it.
    const held = try f.took(f.built.collection.walk(0, &.{f.x}).?, &.{f.x}, &.{ 0, inside }, &.{f.s});
    const closing = try shift(x, f.built.collection.walk(inside, &.{f.s}).?, f.rp);
    const settled = (try compose(x, held, closing)).?;
    try testing.expectEqual(try f.r.one(inside), settled.floor(x));

    // And a left neighbour that lands nowhere the roster allows is still
    // refused, so widening the guard did not weaken it into always agreeing.
    const stray = try f.took(0, &.{}, &.{}, &.{ f.lp, f.s, f.rp, f.x });
    try testing.expectEqual(@as(?Effect, null), try compose(x, stray, loose));
}

test "a reduction is the product of the shifts it consumes" {
    const f = try Fix.init();
    defer f.deinit();
    const inside = f.built.collection.goto(0, f.lp).?;

    // `(`, `x`, `)` shifted from the start state, then `S -> ( S )` reduced —
    // with the `x` folded to an `S` on the way, because that is the only stack
    // the automaton can actually be holding. The product is one step that
    // pushes `S`, which is the statement that makes a parse foldable at all.
    const walked = (try fold(f.arena(), &.{
        try shift(f.arena(), 0, f.lp),
        try shift(f.arena(), inside, f.x),
        try reduce(f.arena(), inside, &.{f.x}, f.s),
        try shift(f.arena(), f.built.collection.walk(0, &.{ f.lp, f.s }).?, f.rp),
        try reduce(f.arena(), 0, &.{ f.lp, f.s, f.rp }, f.s),
    })).?;
    try testing.expectEqual(@as(u32, 0), walked.entry);
    try testing.expectEqual(ledger.Id.empty, walked.guard);
    try testing.expectEqual(try f.p.of(&.{f.s}), walked.push);
}

test "folding in halves agrees with folding straight through" {
    const f = try Fix.init();
    defer f.deinit();
    const inside = f.built.collection.goto(0, f.lp).?;

    // The claim the whole design rests on, stated as a test: every split of a
    // run gives the same product, so a run can be parsed as a tree. Built from
    // the steps of a real parse rather than from the sample, because a run that
    // refuses itself halfway has no product to be associative about.
    var run: std.ArrayList(Effect) = .empty;
    defer run.deinit(testing.allocator);
    try run.appendSlice(testing.allocator, &.{
        try shift(f.arena(), 0, f.lp),
        try shift(f.arena(), inside, f.lp),
        try shift(f.arena(), inside, f.x),
        try reduce(f.arena(), inside, &.{f.x}, f.s),
        try shift(f.arena(), f.built.collection.walk(inside, &.{f.s}).?, f.rp),
        try reduce(f.arena(), inside, &.{ f.lp, f.s, f.rp }, f.s),
    });

    const whole = (try fold(f.arena(), run.items)).?;
    for (0..run.items.len + 1) |cut| {
        const left = (try fold(f.arena(), run.items[0..cut])).?;
        const right = (try fold(f.arena(), run.items[cut..])).?;
        try testing.expect(same(whole, try compose(f.arena(), left, right)));
    }
}
