//! Folding a nonterminal into the productions that use it.
//!
//! Tree-sitter grammars carry an `inline` list, and it is not a hint. Those
//! rules exist as names for readability, and the generator substitutes each
//! one away before building tables *because leaving them in creates conflicts
//! that the grammar author never saw*. A rule like C's `_type_identifier` is a
//! one-line alias whose presence forces the parser to decide which alias it is
//! looking at one token too early. Import the grammar without folding and you
//! inherit hundreds of conflicts that belong to the importer, not the language.
//!
//! Folding is the obvious substitution — replace each occurrence of the symbol
//! with each of its alternatives, take the cartesian product when a right-hand
//! side mentions it more than once — with three details that matter.
//!
//! A **recursive** rule cannot be folded at all: substituting `loop -> loop x`
//! into itself produces a longer body that still mentions `loop`, forever. So
//! the fold graph is checked for cycles first and anything on one is declined,
//! which is the same answer tree-sitter gives, reached before the work instead
//! of during it.
//!
//! Folded rules **mention each other**, so the substitution runs to a fixpoint
//! rather than once. With cycles already excluded that fixpoint is reached in
//! at most the depth of the remaining graph.
//!
//! And nothing is deleted by name. A victim's productions are removed only by
//! a reachability sweep at the end, because a victim that another victim still
//! references is a rule the grammar still needs — dropping it by name is how
//! you turn a fold into a nonterminal that derives nothing.

const std = @import("std");
const g = @import("grammar.zig");

/// Alternatives one production may fan out into before the fold is declined for
/// it. Real `inline` lists are a handful of rules with a handful of
/// alternatives each; anything near this bound is a grammar doing something the
/// substitution was not meant for.
const fan_budget = 1024;

pub const Report = struct {
    /// Victims no right-hand side mentions any more.
    folded: usize,
    /// Victims still standing: recursive, or fanning out past the budget.
    declined: usize,
};

/// Substitute every symbol in `victims` away, rewriting `b.productions` in
/// place. `roots` are the symbols the grammar exists to derive, in the builder's
/// own unresolved numbering - the sweep needs to know what the grammar is *for*
/// before it can say which rules it no longer needs.
///
/// **Every root, not just the start symbol.** A tree-sitter grammar derives its
/// extras from nowhere: an extra is by construction not reachable from `$start`,
/// which is exactly what makes it an extra. Seeded with the start symbol alone
/// the sweep deletes every production a *nonterminal* extra owns, and the
/// language quietly loses the thing that extra was there for. It reached rust and
/// julia and nothing else of thirty, because it needs both halves of a
/// conjunction: a nonterminal extra, and a non-empty `inline` list to make the
/// caller run the sweep in the first place. lua has the extra with no `inline`
/// list, which is why lua was fine; c, cpp and bash have `TOKEN` extras, which
/// own no productions to lose.
///
/// Symbols are not renumbered. A folded nonterminal keeps its id and its name
/// and simply stops being referenced, because renumbering would invalidate
/// every id the caller is holding to buy nothing: the LR closure never expands
/// what nothing references, so an unreachable nonterminal costs one name.
pub fn nonterminals(gpa: std.mem.Allocator, b: *g.Builder, roots: []const u32, victims: []const u32) !Report {
    if (victims.len == 0) return .{ .folded = 0, .declined = 0 };

    var scratch = std.heap.ArenaAllocator.init(gpa);
    defer scratch.deinit();

    var victim = std.AutoHashMap(u32, void).init(gpa);
    defer victim.deinit();
    for (victims) |v| try victim.put(v, {});
    try declineCycles(scratch.allocator(), b, &victim);

    // With cycles excluded, each round strictly shortens the longest remaining
    // chain of victim-to-victim references, so the fixpoint arrives within as
    // many rounds as there are victims.
    var rounds: usize = 0;
    while (victim.count() > 0 and rounds <= victims.len) : (rounds += 1) {
        _ = scratch.reset(.retain_capacity);
        if (!try substitute(gpa, scratch.allocator(), b, &victim)) break;
    }

    _ = scratch.reset(.retain_capacity);
    try sweep(gpa, scratch.allocator(), b, roots);
    return tally(b, victims);
}

/// One substitution round: every right-hand side against the alternatives the
/// victims have *right now*. Returns whether anything moved.
fn substitute(
    gpa: std.mem.Allocator,
    s: std.mem.Allocator,
    b: *g.Builder,
    victim: *const std.AutoHashMap(u32, void),
) !bool {
    var alts = Alts.init(s);
    for (b.productions.items) |p| {
        if (!victim.contains(p.lhs)) continue;
        const slot = try alts.getOrPut(p.lhs);
        if (!slot.found_existing) slot.value_ptr.* = .empty;
        try slot.value_ptr.append(s, .{ .rhs = p.rhs, .steps = p.steps });
    }

    var rewritten: std.ArrayList(g.Production) = .empty;
    defer rewritten.deinit(gpa);
    var touched = false;
    for (b.productions.items) |p| {
        const fan = try expand(s, p, &alts) orelse {
            try rewritten.append(gpa, p); // over budget: keep the alias
            continue;
        };
        if (fan.len == 1 and std.mem.eql(u32, fan[0].rhs, p.rhs)) {
            try rewritten.append(gpa, p);
            continue;
        }
        touched = true;
        const a = b.arena.allocator();
        // Copy the host and name only what the substitution rewrote, rather than
        // listing the fields. A rewrite that enumerates them is a defect
        // generator: it was written when `Production` had three, and when
        // `dynamic` became the fourth every ranked production that inlines
        // anything silently came out at 0. That is all of c's
        // `sized_type_specifier`, since they inline `_type_identifier`, and it
        // read as tree-sitter disagreeing about `long total;` for three rounds.
        //
        // The host's values are the right default for the same reason the host's
        // rank was: substituting a hidden rule into its caller keeps the
        // *caller's* reading, so anything the author said about the caller has to
        // survive the rewrite.
        for (fan) |alt| {
            var out = p;
            out.rhs = try a.dupe(u32, alt.rhs);
            out.steps = try a.dupe(g.Step, alt.steps);
            try rewritten.append(gpa, out);
        }
    }

    b.productions.clearRetainingCapacity();
    try b.productions.appendSlice(gpa, rewritten.items);
    return touched;
}

/// Drop every production whose left-hand side is no longer reachable from any
/// root. This is what actually removes a folded rule, and doing it by
/// reachability rather than by name is what keeps a victim's rules alive while
/// a *declined* victim still references them.
fn sweep(gpa: std.mem.Allocator, s: std.mem.Allocator, b: *g.Builder, roots: []const u32) !void {
    var live = std.AutoHashMap(u32, void).init(s);
    var queue: std.ArrayList(u32) = .empty;
    for (roots) |r| {
        if ((try live.getOrPut(r)).found_existing) continue;
        try queue.append(s, r);
    }

    while (queue.pop()) |sym| {
        for (b.productions.items) |p| {
            if (p.lhs != sym) continue;
            for (p.rhs) |r| {
                if (g.Builder.isTerminalRaw(r)) continue;
                if ((try live.getOrPut(r)).found_existing) continue;
                try queue.append(s, r);
            }
        }
    }

    var kept: std.ArrayList(g.Production) = .empty;
    defer kept.deinit(gpa);
    for (b.productions.items) |p| {
        if (live.contains(p.lhs)) try kept.append(gpa, p);
    }
    b.productions.clearRetainingCapacity();
    try b.productions.appendSlice(gpa, kept.items);
}

/// Remove from `victim` every symbol that can reach itself through other
/// victims. A cycle cannot be substituted away — each round yields a longer
/// body that still names a member — so finding them up front is the difference
/// between declining and diverging.
fn declineCycles(s: std.mem.Allocator, b: *g.Builder, victim: *std.AutoHashMap(u32, void)) !void {
    var recursive: std.ArrayList(u32) = .empty;
    var it = victim.keyIterator();
    while (it.next()) |v| {
        var seen = std.AutoHashMap(u32, void).init(s);
        var queue: std.ArrayList(u32) = .empty;
        try queue.append(s, v.*);
        const cyclic = walk: while (queue.pop()) |sym| {
            for (b.productions.items) |p| {
                if (p.lhs != sym) continue;
                for (p.rhs) |r| {
                    if (r == v.*) break :walk true;
                    if (!victim.contains(r)) continue;
                    if ((try seen.getOrPut(r)).found_existing) continue;
                    try queue.append(s, r);
                }
            }
        } else false;
        if (cyclic) try recursive.append(s, v.*);
    }
    for (recursive.items) |r| _ = victim.remove(r);
}

/// A victim is folded when nothing mentions it any more — which is the honest
/// question, and covers a cycle declined up front and a fan-out declined
/// mid-round with one answer.
fn tally(b: *const g.Builder, victims: []const u32) Report {
    var r: Report = .{ .folded = 0, .declined = 0 };
    for (victims) |v| {
        const standing = for (b.productions.items) |p| {
            if (std.mem.indexOfScalar(u32, p.rhs, v) != null) break true;
        } else false;
        if (standing) r.declined += 1 else r.folded += 1;
    }
    return r;
}

const Alt = struct { rhs: []const u32, steps: []const g.Step };
const Alts = std.AutoHashMap(u32, std.ArrayList(Alt));

/// The cartesian product of one production against the alternatives of every
/// victim it mentions. Null means the product exceeded the budget, and the
/// caller keeps the original right-hand side intact.
///
/// Precedence splices with the body rather than being recomputed for the whole
/// production: each substituted step keeps the rank it had inside the rule
/// being folded away, and only the *last* of them falls back to the rank the
/// host had written on the step it replaced — and only where it has none of
/// its own. That is what makes inlining precedence-neutral. The version that
/// picked one rank for the fused production by magnitude is how Rust's
/// `_non_special_token`, whose whole content is `prec.right(0, repeat1(…))`,
/// arrived in its callers with the associativity dropped: rank 0 never
/// out-magnitudes anything, so the host's silence won every time.
///
/// Shaping splices the other way round, and overwrites rather than defers: a
/// host that wrote `field('name', $._victim)` was naming *the whole thing it
/// referenced*, so every step that arrives in its place answers to that name.
/// The rule vanishing is what makes this the only chance to say so.
fn expand(s: std.mem.Allocator, p: g.Production, alts: *const Alts) !?[]Alt {
    var out: std.ArrayList(Alt) = .empty;
    try out.append(s, .{ .rhs = &.{}, .steps = &.{} });

    for (p.rhs, p.steps) |sym, host| {
        var next: std.ArrayList(Alt) = .empty;
        if (alts.get(sym)) |list| {
            if (out.items.len * list.items.len > fan_budget) return null;
            for (out.items) |prefix| for (list.items) |body| {
                const steps = try std.mem.concat(s, g.Step, &.{ prefix.steps, body.steps });
                if (steps.len > prefix.steps.len) {
                    for (steps[prefix.steps.len..]) |*inserted| {
                        if (host.alias) |x| inserted.alias = x;
                        if (host.field) |x| inserted.field = x;
                    }
                    const last = &steps[steps.len - 1];
                    if (last.prec == .none) last.prec = host.prec;
                    if (last.assoc == .none) last.assoc = host.assoc;
                }
                try next.append(s, .{
                    .rhs = try std.mem.concat(s, u32, &.{ prefix.rhs, body.rhs }),
                    .steps = steps,
                });
            };
        } else {
            for (out.items) |prefix| {
                const grown = try s.alloc(u32, prefix.rhs.len + 1);
                @memcpy(grown[0..prefix.rhs.len], prefix.rhs);
                grown[prefix.rhs.len] = sym;
                const steps = try s.alloc(g.Step, grown.len);
                @memcpy(steps[0..prefix.steps.len], prefix.steps);
                steps[prefix.steps.len] = host;
                try next.append(s, .{ .rhs = grown, .steps = steps });
            }
        }
        out = next;
    }
    return out.items;
}

const testing = std.testing;

test "a folded alias disappears into every caller" {
    var b = g.Builder.init(testing.allocator);
    defer b.deinit();
    const x = try b.intern("x", "x", .{ .literal = "x" });
    const y = try b.intern("y", "y", .{ .literal = "y" });
    const start = try b.intern("$start", "$start", null);
    const top = try b.intern("top", "top", null);
    const alias = try b.intern("alias", "alias", null);

    try b.addProduction(start, &.{top}, &.{});
    try b.addProduction(top, &.{ alias, y }, &.{});
    try b.addProduction(alias, &.{x}, &.{});
    try b.addProduction(alias, &.{y}, &.{});

    _ = try nonterminals(testing.allocator, &b, &.{start}, &.{alias});
    var gr = try b.finish("t", start, &.{}, &.{});
    defer gr.deinit();

    // `top -> alias y` became `top -> x y` and `top -> y y`, and `alias` has
    // no productions left at all.
    try testing.expectEqual(@as(usize, 3), gr.productions.len);
    for (gr.productions) |p| for (p.rhs) |s| try testing.expect(gr.isTerminal(s) or s == gr.start + 1);
}

test "a nonterminal extra keeps its productions, being a root of its own" {
    var b = g.Builder.init(testing.allocator);
    defer b.deinit();
    const x = try b.intern("x", "x", .{ .literal = "x" });
    const hash = try b.intern("#", "#", .{ .literal = "#" });
    const start = try b.intern("$start", "$start", null);
    const top = try b.intern("top", "top", null);
    const alias = try b.intern("alias", "alias", null);
    const comment = try b.intern("comment", "comment", null);

    try b.addProduction(start, &.{top}, &.{});
    try b.addProduction(top, &.{alias}, &.{});
    try b.addProduction(alias, &.{x}, &.{});
    // Reachable from nothing, which is what being an extra means.
    try b.addProduction(comment, &.{hash}, &.{});

    _ = try nonterminals(testing.allocator, &b, &.{ start, comment }, &.{alias});
    var gr = try b.finish("t", start, &.{comment}, &.{});
    defer gr.deinit();

    // Seeded with `start` alone the sweep takes this to zero, and the grammar
    // parses a language with no comments in it. rust lost 8 extras that way and
    // julia 5.
    var owns: usize = 0;
    for (gr.productions) |p| {
        if (std.mem.eql(u8, gr.nameOf(p.lhs), "comment")) owns += 1;
    }
    try testing.expectEqual(@as(usize, 1), owns);
}

test "the caller's rank survives folding a victim into it" {
    var b = g.Builder.init(testing.allocator);
    defer b.deinit();
    const x = try b.intern("x", "x", .{ .literal = "x" });
    const y = try b.intern("y", "y", .{ .literal = "y" });
    const start = try b.intern("$start", "$start", null);
    const top = try b.intern("top", "top", null);
    const alias = try b.intern("alias", "alias", null);

    try b.addProduction(start, &.{top}, &.{});
    try b.addProductionDynamic(top, &.{ alias, y }, &.{}, -1);
    try b.addProduction(alias, &.{x}, &.{});
    try b.addProduction(alias, &.{y}, &.{});

    _ = try nonterminals(testing.allocator, &b, &.{start}, &.{alias});
    var gr = try b.finish("t", start, &.{}, &.{});
    defer gr.deinit();

    // Both halves of the fan carry it. Losing it here is why c's
    // `sized_type_specifier` read as unranked: every one of them inlines
    // `_type_identifier`, so every one of them was rewritten.
    var ranked: usize = 0;
    for (gr.productions) |p| {
        if (p.lhs != gr.start + 1) continue;
        try testing.expectEqual(@as(i16, -1), p.dynamic);
        ranked += 1;
    }
    try testing.expectEqual(@as(usize, 2), ranked);
}

test "one right-hand side mentioning a victim twice fans out as a product" {
    var b = g.Builder.init(testing.allocator);
    defer b.deinit();
    const x = try b.intern("x", "x", .{ .literal = "x" });
    const y = try b.intern("y", "y", .{ .literal = "y" });
    const start = try b.intern("$start", "$start", null);
    const top = try b.intern("top", "top", null);
    const alias = try b.intern("alias", "alias", null);

    try b.addProduction(start, &.{top}, &.{});
    try b.addProduction(top, &.{ alias, alias }, &.{});
    try b.addProduction(alias, &.{x}, &.{});
    try b.addProduction(alias, &.{y}, &.{});

    _ = try nonterminals(testing.allocator, &b, &.{start}, &.{alias});
    var gr = try b.finish("t", start, &.{}, &.{});
    defer gr.deinit();

    // xx, xy, yx, yy, plus the augmented production.
    try testing.expectEqual(@as(usize, 5), gr.productions.len);
}

test "a victim inside a victim resolves rather than surviving one round" {
    var b = g.Builder.init(testing.allocator);
    defer b.deinit();
    const x = try b.intern("x", "x", .{ .literal = "x" });
    const start = try b.intern("$start", "$start", null);
    const top = try b.intern("top", "top", null);
    const outer = try b.intern("outer", "outer", null);
    const inner = try b.intern("inner", "inner", null);

    try b.addProduction(start, &.{top}, &.{});
    try b.addProduction(top, &.{outer}, &.{});
    try b.addProduction(outer, &.{inner}, &.{});
    try b.addProduction(inner, &.{x}, &.{});

    const report = try nonterminals(testing.allocator, &b, &.{start}, &.{ outer, inner });
    try testing.expectEqual(@as(usize, 0), report.declined);
    try testing.expectEqual(@as(usize, 2), report.folded);

    var gr = try b.finish("t", start, &.{}, &.{});
    defer gr.deinit();
    try testing.expectEqual(@as(usize, 2), gr.productions.len);
    try testing.expectEqual(@as(usize, 1), gr.productions[1].rhs.len);
    try testing.expect(gr.isTerminal(gr.productions[1].rhs[0]));
}

test "a recursive victim is declined, not chased forever" {
    var b = g.Builder.init(testing.allocator);
    defer b.deinit();
    const x = try b.intern("x", "x", .{ .literal = "x" });
    const start = try b.intern("$start", "$start", null);
    const top = try b.intern("top", "top", null);
    const loop = try b.intern("loop", "loop", null);

    try b.addProduction(start, &.{top}, &.{});
    try b.addProduction(top, &.{loop}, &.{});
    try b.addProduction(loop, &.{ loop, x }, &.{});
    try b.addProduction(loop, &.{x}, &.{});

    const report = try nonterminals(testing.allocator, &b, &.{start}, &.{loop});
    try testing.expectEqual(@as(usize, 1), report.declined);

    // Declining is not damaging: the grammar it hands back is the one it was
    // given, still able to derive `x`.
    var gr = try b.finish("t", start, &.{}, &.{});
    defer gr.deinit();
    try testing.expectEqual(@as(usize, 4), gr.productions.len);
}
