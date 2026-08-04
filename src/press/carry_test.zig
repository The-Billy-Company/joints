//! The artifact against the IR, field by field, by reflection.
//!
//! `press` computes an IR, `folio` writes it, `folio.bind` reads it back - and
//! between those two there is a byte format, which is the one boundary in this
//! package where a field can go missing without anybody writing a line of wrong
//! code. The writer enumerates fields into a record by hand and the reader
//! enumerates them back out by hand, so every field either survives the round
//! trip or reads as zero on the far side. Zero is a legal value for most of
//! them, which is why `Production.dynamic` was lost for as long as it was and
//! was found by a grammar behaving oddly rather than by a test.
//!
//! So this walks `std.meta.fields` instead of naming the fields it cares about,
//! and a field nobody thought about is compared anyway. Two things are what make
//! that actually fail closed:
//!
//!   - **the sample gives every field a distinguishable value**, since a field
//!     left at its default on both sides compares equal whether it crossed or
//!     not; the survey reports such a field as one it could not see, and that is
//!     a failure rather than a pass, because a green run that checked nothing is
//!     worse than a red one; and
//!   - **the field counts are asserted at comptime**, because a *newly added*
//!     field is the one case reflection cannot catch by itself: it would be
//!     defaulted in the sample too, cross as a zero, and pass. Adding one stops
//!     the build here with what to do about it.
//!
//! Losses that are correct are declared with their reason. A folio carries the
//! decided table and not the argument that decided it, so a press input is gone
//! by design; `bind`'s header says which ones in prose, and `consumed` below is
//! that paragraph made mechanical - it fails if such a field starts crossing,
//! too, so the list cannot rot into a description of an older format.

const std = @import("std");
const testing = std.testing;
const folio = @import("../folio/folio.zig");
const g = @import("grammar.zig");
const lalr = @import("lalr.zig");
const lr0 = @import("lr0.zig");
const press = @import("press.zig");

/// A field the round trip drops, and why.
const Loss = struct { at: []const u8, why: []const u8 };

/// Press inputs, consumed before the artifact exists. Correct losses.
const consumed = [_]Loss{
    .{ .at = "Step.prec", .why = "resolved the cell while the table was built" },
    .{ .at = "Step.assoc", .why = "the same, for the side it resolved to" },
    .{ .at = "Grammar.prec_names", .why = "the names a resolved Prec.name indexed" },
    .{ .at = "Grammar.orderings", .why = "the partial order those names compared in" },
    .{ .at = "Grammar.declared_conflicts", .why = "which cells the press was allowed to leave contested" },
    .{ .at = "State.kernel", .why = "the items that named a state while it was being built" },
    .{ .at = "Tables.seams", .why = "the search's own note of what a merge over-permitted" },
};

/// A loss with a contract to fix it rather than a reason to keep it: a field the
/// parse would read if it were there. When one lands, this test goes red with
/// "declared lost but crossed", which is the reminder to delete the entry.
const pending = [_]Loss{
    .{
        .at = "Production.dynamic",
        .why = "ProductionRecord carries no rank; the fork cannot order branches it cannot see",
    },
};

/// Fields the artifact answers *more* about than the IR it was pressed from -
/// the other direction, and not a loss. Declared for the same reason the losses
/// are: so that a field which starts differing for some third reason cannot hide
/// among them.
const added = [_]Loss{
    .{ .at = "Grammar.lexicon", .why = "the determinized terminal slate, which a pressed grammar does not have until it is written" },
};

comptime {
    // Reflection covers a field that stops crossing. It cannot cover a field
    // that never crossed, because `sample` would leave a new one at its default
    // and a default matches a default. So the counts are pinned: grow one of
    // these types and come back here.
    assertWidth(g.Grammar, 21);
    assertWidth(g.Production, 4);
    assertWidth(g.Step, 4);
    assertWidth(lr0.State, 3);
    assertWidth(lalr.Tables, 7);
}

fn assertWidth(comptime T: type, comptime want: usize) void {
    if (std.meta.fields(T).len != want) @compileError(
        @typeName(T) ++ " changed width: give the new field a distinguishing value in " ++
            "`sample`, then either carry it through the folio or declare the loss in " ++
            "`consumed`/`pending` and update the count here",
    );
}

test "every field of the IR either crosses the artifact or is a declared loss" {
    const gpa = testing.allocator;
    var gr = try sample(gpa);
    defer gr.deinit();

    var lost: Lost = .{};
    var blind: Lost = .{};

    {
        var pressed = try press.tables(gpa, &gr);
        defer pressed.deinit();
        try trip(gpa, &gr, &pressed, &lost, &blind);
    }
    {
        // A second trip from the automaton the search starts at, because the one
        // it finishes at has nothing frayed left to carry: the split separates
        // the wing below and `Tables.frayed` comes out empty, so a survey of the
        // shipped press alone can never tell whether the artifact carries that
        // record or drops it.
        const c = try lr0.build(gpa, &gr, .{});
        const t = try lalr.build(gpa, &gr, &c);
        var raw: press.Result = .{ .collection = c, .tables = t, .unfolded = 0 };
        defer raw.deinit();
        var also: Lost = .{};
        try trip(gpa, &gr, &raw, &lost, &also);
        blind.keep(&also);
    }

    var bad: usize = 0;
    // A field neither side ever set is a field this test did not check, and a
    // green run that says otherwise is worse than a red one.
    for (blind.at[0..blind.n]) |at| {
        std.debug.print("sample never sets {s}, so the round trip cannot see it\n", .{at});
        bad += 1;
    }
    for (lost.at[0..lost.n], lost.kind[0..lost.n]) |at, kind| {
        if (listed(if (kind == .loses) &(consumed ++ pending) else &added, at)) continue;
        std.debug.print("folio {s} {s}, and nothing says it should\n", .{ @tagName(kind), at });
        bad += 1;
    }
    for (consumed ++ pending ++ added) |d| {
        if (lost.has(d.at)) continue;
        std.debug.print("{s} agrees now; delete its entry ({s})\n", .{ d.at, d.why });
        bad += 1;
    }
    if (bad != 0) return error.FolioIdentityMoved;
}

/// One pressing, out through the bytes and back, surveyed against itself.
fn trip(
    gpa: std.mem.Allocator,
    gr: *const g.Grammar,
    pressed: *press.Result,
    lost: *Lost,
    blind: *Lost,
) !void {
    const bytes = try folio.pack(gpa, gr, pressed);
    defer gpa.free(bytes);
    const f = try folio.open(bytes);
    var back = try folio.bind(gpa, &f);
    defer back.deinit();

    // One-element slices so a single value and a list of them survey the same
    // way. Copying a `Grammar` by value is a read here and nothing deinits the
    // copy, so the arena it carries is never touched twice.
    survey(g.Grammar, "Grammar", &.{ "arena", "productions" }, &.{gr.*}, &.{back.grammar}, lost, blind);
    survey(lalr.Tables, "Tables", &.{"arena"}, &.{pressed.tables}, &.{back.tables}, lost, blind);
    survey(g.Production, "Production", &.{"steps"}, gr.productions, back.grammar.productions, lost, blind);
    survey(lr0.State, "State", &.{}, pressed.collection.states, back.collection.states, lost, blind);

    // Steps are surveyed flat rather than through `Production.steps`, so a lost
    // step field is named as itself instead of as the production that held it.
    var mine: std.ArrayList(g.Step) = .empty;
    defer mine.deinit(gpa);
    var theirs: std.ArrayList(g.Step) = .empty;
    defer theirs.deinit(gpa);
    for (gr.productions) |p| try mine.appendSlice(gpa, p.steps);
    for (back.grammar.productions) |p| try theirs.appendSlice(gpa, p.steps);
    survey(g.Step, "Step", &.{}, mine.items, theirs.items, lost, blind);
}

/// What this field holds when the grammar said nothing about it - the declared
/// default where there is one, since that is precisely the value a lost field
/// comes back as, and an empty of the type where there is not.
fn unsaid(comptime field: std.builtin.Type.StructField) field.type {
    if (field.default_value_ptr) |p| {
        return @as(*const field.type, @ptrCast(@alignCast(p))).*;
    }
    return switch (@typeInfo(field.type)) {
        .pointer => &.{},
        else => std.mem.zeroes(field.type),
    };
}

/// A grammar small enough to press in a test and wide enough that every field of
/// the IR holds something a zero could not be mistaken for: both signs of a
/// dynamic rank, a levelled and a named precedence, both associativities, a
/// rename and a field name, an immediate external, all four shapes, a word, an
/// extra, a supertype, a declared conflict and an ordering.
fn sample(gpa: std.mem.Allocator) !g.Grammar {
    var b = g.Builder.init(gpa);
    defer b.deinit();

    const id = try b.intern("id", "identifier", .{ .regex = "[a-z]+" });
    const kw = try b.intern("kw", "let", .{ .literal = "let" });
    const eq = try b.intern("eq", "=", .{ .literal = "=" });
    const plus = try b.intern("plus", "+", .{ .literal = "+" });
    const semi = try b.intern("semi", ";", .{ .literal = ";" });
    const ws = try b.intern("ws", "whitespace", .{ .regex = "\\s+" });
    const raw = try b.intern("raw", "raw_text", .external);
    b.describe(raw, .{ .immediate = true, .prec = 3 });
    b.describe(kw, .{ .prec = 1 });
    b.word = id;

    const start = try b.intern("$start", "$start", null);
    const stmt = try b.intern("stmt", "statement", null);
    const expr = try b.intern("expr", "_expression", null);
    const helper = try b.intern("helper", "statement_repeat1", null);
    b.shape(helper, .invented);
    b.ascribe(helper, stmt);
    b.shape(expr, .hidden);
    b.shape(eq, .anonymous);
    try b.elevate(expr);

    const name_field = try b.internField("name");
    const rename = try b.internAlias("binding", true);
    // Both spellings of a rename, because `named` is a bool and a reader that
    // hardcoded either one would still round-trip a sample that only used that
    // one. The same argument as the two signs of a dynamic rank.
    const punct = try b.internAlias("=>", false);
    const sum = try b.internPrec("sum");
    try b.addOrdering(&.{ .{ .name = sum }, .{ .symbol = expr } });

    try b.addProduction(start, &.{stmt}, &.{});
    try b.addProduction(stmt, &.{ kw, id, eq, expr, semi }, &.{
        .{}, .{ .field = name_field, .alias = rename }, .{}, .{ .prec = .{ .level = 2 }, .assoc = .left }, .{},
    });
    try b.addProduction(stmt, &.{helper}, &.{.{ .alias = punct }});
    try b.addProduction(helper, &.{id}, &.{});
    try b.addProduction(helper, &.{ helper, id }, &.{});
    // Both signs, so a rank that crosses as zero is caught whichever way the
    // reader defaults it.
    try b.addProductionDynamic(expr, &.{ expr, plus, expr }, &.{
        .{}, .{ .prec = .{ .name = sum }, .assoc = .right }, .{},
    }, -1);
    try b.addProductionDynamic(expr, &.{id}, &.{}, 2);
    try b.addProduction(expr, &.{raw}, &.{});

    // Knuth's LALR wing, the four-way one: `a A d | b B d | a B e | b A e` over
    // `A -> c` and `B -> c`. Two contexts arrive at the same LR(0) core, the
    // merged lookahead admits both reduces under both, and the table comes out
    // frayed - which is the only way a sample can exercise `Tables.frayed` and
    // `Tables.seams` at all. Without it both are empty on both sides of the
    // round trip and agree by vacancy, which is a pass that has checked nothing.
    const a_t = try b.intern("a", "a", .{ .literal = "a" });
    const b_t = try b.intern("b", "b", .{ .literal = "b" });
    const c_t = try b.intern("c", "c", .{ .literal = "c" });
    const d_t = try b.intern("d", "d", .{ .literal = "d" });
    const e_t = try b.intern("e", "e", .{ .literal = "e" });
    const av = try b.intern("A", "left_leaf", null);
    const bv = try b.intern("B", "right_leaf", null);
    try b.addProduction(stmt, &.{ a_t, av, d_t }, &.{});
    try b.addProduction(stmt, &.{ b_t, bv, d_t }, &.{});
    try b.addProduction(stmt, &.{ a_t, bv, e_t }, &.{});
    try b.addProduction(stmt, &.{ b_t, av, e_t }, &.{});
    try b.addProduction(av, &.{c_t}, &.{});
    try b.addProduction(bv, &.{c_t}, &.{});
    return b.finish("sample", start, &.{ws}, &.{&.{ stmt, expr }});
}

const Lost = struct {
    /// Which way a field failed to be itself: `loses` is the dangerous one,
    /// where the recovered value is exactly what the field reads as when nobody
    /// ever set it, so a reader cannot tell a dropped field from an unset one.
    const Kind = enum { loses, changes };

    at: [64][]const u8 = undefined,
    kind: [64]Kind = undefined,
    n: usize = 0,

    fn note(l: *Lost, at: []const u8, kind: Kind) void {
        if (l.has(at) or l.n == l.at.len) return;
        l.at[l.n] = at;
        l.kind[l.n] = kind;
        l.n += 1;
    }

    fn has(l: *const Lost, at: []const u8) bool {
        for (l.at[0..l.n]) |seen| {
            if (std.mem.eql(u8, seen, at)) return true;
        }
        return false;
    }

    /// Intersect, which is what two runs mean for blindness: a field one
    /// pressing could not see is checked if the other one could.
    fn keep(l: *Lost, other: *const Lost) void {
        var out: usize = 0;
        for (l.at[0..l.n], l.kind[0..l.n]) |at, kind| {
            if (!other.has(at)) continue;
            l.at[out] = at;
            l.kind[out] = kind;
            out += 1;
        }
        l.n = out;
    }
};

fn listed(list: []const Loss, at: []const u8) bool {
    for (list) |d| {
        if (std.mem.eql(u8, d.at, at)) return true;
    }
    return false;
}

/// Every field of `T` that differs anywhere between the two runs, named
/// `label.field`. `skip` is for a field surveyed somewhere else and for the
/// arena, which is an allocator rather than a fact about the grammar.
fn survey(
    comptime T: type,
    comptime label: []const u8,
    comptime skip: []const []const u8,
    mine: []const T,
    theirs: []const T,
    lost: *Lost,
    blind: *Lost,
) void {
    if (mine.len != theirs.len) return lost.note(label ++ ".*count*", .changes);
    inline for (std.meta.fields(T)) |field| {
        if (comptime !named(skip, field.name)) {
            var differs = false;
            var emptied = true;
            var said = false;
            for (mine, theirs) |x, y| {
                if (!same(field.type, @field(x, field.name), unsaid(field))) said = true;
                if (!same(field.type, @field(y, field.name), unsaid(field))) said = true;
                if (same(field.type, @field(x, field.name), @field(y, field.name))) continue;
                differs = true;
                if (!same(field.type, @field(y, field.name), unsaid(field))) emptied = false;
            }
            if (differs) lost.note(label ++ "." ++ field.name, if (emptied) .loses else .changes);
            if (!said) blind.note(label ++ "." ++ field.name, .loses);
        }
    }
}

fn named(comptime list: []const []const u8, comptime want: []const u8) bool {
    for (list) |entry| {
        if (std.mem.eql(u8, entry, want)) return true;
    }
    return false;
}

/// Structural equality, over whatever the IR is made of. Recursive rather than
/// per type, so it keeps working on a field whose type nobody here has seen.
fn same(comptime T: type, x: T, y: T) bool {
    return switch (@typeInfo(T)) {
        .void => true,
        .int, .bool, .@"enum", .float => x == y,
        .optional => |o| if (x == null or y == null)
            x == null and y == null
        else
            same(o.child, x.?, y.?),
        .pointer => |p| switch (p.size) {
            .slice => blk: {
                if (x.len != y.len) break :blk false;
                if (p.child == u8) break :blk std.mem.eql(u8, x, y);
                for (x, y) |a, b| {
                    if (!same(p.child, a, b)) break :blk false;
                }
                break :blk true;
            },
            else => @compileError("no equality for " ++ @typeName(T)),
        },
        .@"struct" => |s| blk: {
            inline for (s.fields) |field| {
                if (!same(field.type, @field(x, field.name), @field(y, field.name))) break :blk false;
            }
            break :blk true;
        },
        .@"union" => |u| blk: {
            if (u.tag_type == null) @compileError("no equality for bare union " ++ @typeName(T));
            if (std.meta.activeTag(x) != std.meta.activeTag(y)) break :blk false;
            inline for (u.fields) |field| {
                if (std.meta.activeTag(x) == @field(std.meta.Tag(T), field.name))
                    break :blk same(field.type, @field(x, field.name), @field(y, field.name));
            }
            break :blk true;
        },
        else => @compileError("no equality for " ++ @typeName(T)),
    };
}
