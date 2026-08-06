//! Rung 4: whose ambiguity is left, once precedence and associativity have both
//! declined to say.
//!
//! The other three rungs read the grammar's *declarations*. This one reads the
//! automaton backwards, because the question it answers is not "which reading
//! wins" but "which rules were in the room" — and for a reading the front end
//! synthesized there is no author to ask, only the states that were expecting
//! it. That needs a reverse index over the collection, a second closure, and
//! four scratch lists, none of which any other rung wants.
//!
//! So it is a fixture with a two-word interface. A bench `note`s each reading as
//! it polls the state, then asks `of` for the class; `named` is the party that
//! answer was reached on, which the conflict record carries as its evidence.
//! Eight fields and a hundred lines of unwinding sit behind those three words,
//! and the bench that drives it needs to know none of it.

const std = @import("std");
const g = @import("grammar.zig");
const lr0 = @import("lr0.zig");
const retrace = @import("retrace.zig");
const settle = @import("settle.zig");

const Case = settle.Case;
const Conflict = settle.Conflict;

/// Who was party to a cell, and what that makes the cell's class.
pub const Attribution = struct {
    x: Case,
    gpa: std.mem.Allocator,
    /// A closure of its own, for the predecessor states an attribution reads. It
    /// cannot share the bench's: the items being judged are a slice into that
    /// one.
    origin: lr0.Closure,
    rev: retrace.Retrace,
    /// One cell's party, built in two parts because the second part has more
    /// than one candidate: `owners` are the rules named outright by a reading,
    /// `lists` are the synthesized readings that have to be traced back to
    /// whoever was expecting them, and `party` is the candidate under test.
    owners: std.ArrayList(g.Symbol) = .empty,
    lists: std.ArrayList(Pending) = .empty,
    party: std.ArrayList(g.Symbol) = .empty,
    exposed: std.ArrayList(u32) = .empty,

    /// A synthesized reading waiting to be attributed: the rule the front end
    /// invented, and the part of it this state has consumed.
    const Pending = struct { lhs: g.Symbol, prefix: []const g.Symbol };

    pub fn init(x: Case, gpa: std.mem.Allocator) !Attribution {
        return .{
            .x = x,
            .gpa = gpa,
            .origin = try lr0.Closure.init(gpa, x.gr),
            .rev = try retrace.Retrace.build(gpa, x.c),
        };
    }

    pub fn deinit(a: *Attribution) void {
        a.origin.deinit(a.gpa);
        a.rev.deinit(a.gpa);
        a.owners.deinit(a.gpa);
        a.lists.deinit(a.gpa);
        a.party.deinit(a.gpa);
        a.exposed.deinit(a.gpa);
    }

    /// Begin a fresh poll of one cell.
    pub fn open(a: *Attribution) void {
        a.owners.clearRetainingCapacity();
        a.lists.clearRetainingCapacity();
    }

    /// One reading of the cell, as the poll meets it: a rule the author wrote is
    /// enrolled outright, a rule the front end synthesized is held for `of` to
    /// trace back.
    pub fn note(a: *Attribution, lhs: g.Symbol, prefix: []const g.Symbol) !void {
        if (a.x.gr.isSynthetic(lhs)) {
            try a.lists.append(a.gpa, .{ .lhs = lhs, .prefix = prefix });
        } else {
            try enrol(a.gpa, &a.owners, a.x.gr.owner[lhs]);
        }
    }

    /// The party the answer was reached on, for the conflict record.
    pub fn named(a: Attribution) []const g.Symbol {
        return a.party.items;
    }

    /// Whose ambiguity the cell is, once the synthesized readings have been
    /// traced back to the rules that were expecting them.
    ///
    /// A list the front end invented has no author, so naming it after the rule
    /// that happened to mention it first names an artifact of traversal order.
    /// Worse, it is wrong in exactly the case that matters: a list body written
    /// identically in a dozen rules is *one* symbol, shared, and the rule it is
    /// building here is whichever rule was expecting it — a fact about this
    /// state, not about the grammar.
    ///
    /// Unwinding the consumed part of the production gives the states that were
    /// expecting it, and there is generally more than one, because that is what
    /// an LR state is for. Each is a separate candidate rather than one union:
    /// they are different stacks, and a declaration sanctions an ambiguity
    /// between rules that can actually be confused *on some stack*. Unioning
    /// them instead reports a group no parse ever holds — C would come back
    /// claiming `attributed_declarator` and `attributed_statement` are confused
    /// with each other, when the truth is that each is separately confused with
    /// its own list.
    ///
    /// A grammar's own declarations are the arbiter of which candidate to
    /// believe: the first one the author sanctioned is the reading they meant.
    /// With none sanctioned there is nothing to choose between, and the union is
    /// reported — the honest superset, and the shape a reader needs to see to
    /// write the declaration that would settle it.
    pub fn of(a: *Attribution, state: u32) !Conflict.Class {
        a.party.clearRetainingCapacity();
        try a.party.appendSlice(a.gpa, a.owners.items);
        if (a.lists.items.len == 0) {
            return if (a.x.gr.declared(a.party.items)) .declared else .residual;
        }

        // Every production of a list unwinds to a state where that list was
        // expected — `L -> x` over one step and `L -> L x` over two both land
        // where the `L` began — so the candidates line up across readings and
        // can be indexed by that state.
        a.exposed.clearRetainingCapacity();
        for (a.lists.items) |l| {
            for (try a.rev.back(a.gpa, state, l.prefix)) |q| {
                if (std.mem.indexOfScalar(u32, a.exposed.items, q) == null) {
                    try a.exposed.append(a.gpa, q);
                }
            }
        }

        for (a.exposed.items) |q| {
            a.party.clearRetainingCapacity();
            try a.party.appendSlice(a.gpa, a.owners.items);
            for (a.lists.items) |l| try a.hosts(q, l.lhs);
            if (a.party.items.len > 0 and a.x.gr.declared(a.party.items)) return .declared;
        }

        a.party.clearRetainingCapacity();
        try a.party.appendSlice(a.gpa, a.owners.items);
        for (a.exposed.items) |q| {
            for (a.lists.items) |l| try a.hosts(q, l.lhs);
        }
        // Nobody the author wrote was visibly waiting: reachable only through
        // another synthesized rule, or from the frame itself. Name the list's
        // host so the report says something a reader can act on.
        if (a.party.items.len == 0) {
            for (a.lists.items) |l| try enrol(a.gpa, &a.party, a.x.gr.owner[l.lhs]);
        }
        return .residual;
    }

    /// The rules holding the dot before `list` in state `q`, added to the
    /// candidate party.
    ///
    /// Only rules the author wrote count. A list is left-recursive, so `L -> . L
    /// x` sits in the very state that expects it and would otherwise enrol the
    /// list's own naming host in every party it appears in — which is how C came
    /// back claiming `attributed_declarator` was confused with
    /// `attributed_statement`, when the whole conflict was one statement's
    /// attribute list deciding whether it was finished. A list expecting itself
    /// is not two rules being confused.
    fn hosts(a: *Attribution, q: u32, list: g.Symbol) !void {
        for (try a.origin.of(a.gpa, a.x.gr, a.x.c.states[q].kernel)) |item| {
            if (item.prod == 0) continue;
            const p = a.x.gr.productions[item.prod];
            if (item.dot == p.rhs.len or p.rhs[item.dot] != list) continue;
            if (a.x.gr.isSynthetic(p.lhs)) continue;
            try enrol(a.gpa, &a.party, a.x.gr.owner[p.lhs]);
        }
    }
};

/// Add one rule to a party, keeping it sorted and deduplicated. Sorted
/// because a party is compared against the author's declared groups as a
/// set, and a set spelled in traversal order is not comparable.
fn enrol(gpa: std.mem.Allocator, into: *std.ArrayList(g.Symbol), rule: g.Symbol) !void {
    const at = std.sort.lowerBound(g.Symbol, into.items, rule, order);
    if (at == into.items.len or into.items[at] != rule) try into.insert(gpa, at, rule);
}

fn order(key: g.Symbol, item: g.Symbol) std.math.Order {
    return std.math.order(key, item);
}
