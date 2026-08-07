//! One LR state, whole: what it has read, and what it will do with every
//! terminal.
//!
//! The question a wrong table raises is never "how many conflicts" — it is
//! "why did *this* cell say that", and answering it needs the state's items
//! beside its row. A reduce on a terminal that cannot follow the folded rule
//! is a lookahead bug; the same reduce beside a shift the ladder passed over
//! is a resolution bug; and the two are indistinguishable from a count.
//!
//! # Why the row is printed as two sets
//!
//! This verb used to print one flat list with the verb in a second column, and
//! that shape cost a lane a night. "The terminals of this state" has **two
//! answers**, and for swift's `_implicit_semi` they differ by 85x — 20 states
//! admit it by shift, 1,712 have it in their expected set. One flat list makes
//! the distinction an annotation most eyes read past, so a lane can measure
//! either one, write it up as authoritative, and never see that it answered a
//! question one column away from the one it asked. That lane wrote up both,
//! hours apart, and its correction of the first was itself wrong.
//!
//! The split is not cosmetic and it is not arbitrary: **a shift consumes a
//! byte and a fold does not.** So when the question is a lexical one — what
//! does a scanner have to compete with here — the shifts are the whole answer
//! and the lookaheads are none of it, because a reduce puts no token in the
//! hand. When the question is a table one — what may follow this state at all
//! — the union is the answer, and that is what tree-sitter's `valid_symbols`
//! reports to an external scanner. Both are real; they are not
//! interchangeable, and nothing in the old output said so.
//!
//! Two headers and a footer that names both counts, so neither reading can be
//! taken for the other by a reader in a hurry or by a script with a regex.
//! Every accepted cell appears exactly once — a cell holds one chosen action,
//! and a contested one is filed under what the table *does*, with the losing
//! action still printed beside it.

const std = @import("std");
const joints = @import("joints");
const intake = @import("intake.zig");
const whence = @import("whence.zig");

const press = joints.press;
const Grammar = joints.press.Grammar;
const Action = joints.press.Action;
const Verb = @FieldType(Action, "kind");

/// What this verb was asked for. One of the four, and the shape says so rather
/// than three optionals whose illegal combinations the dispatcher has to know
/// about — `--census` with a state number is not a question.
pub const Ask = union(enum) {
    /// One state, whole: its items and both halves of its row.
    at: u32,
    /// How many states admit each of these terminals, in each half.
    census: []const []const u8,
    /// Which states hold a reading — the inverse of `at`.
    holding: []const u8,
    /// How a parse arrives at a state, and where a fold there goes.
    chain: u32,
};

/// Import and press the grammar at `grammar_path`, then answer `ask`.
pub fn run(
    gpa: std.mem.Allocator,
    io: std.Io,
    w: *std.Io.Writer,
    grammar_path: []const u8,
    ask: Ask,
) !u8 {
    const source = intake.slurp(gpa, io, w, grammar_path) orelse return 2;
    defer gpa.free(source);
    var gr = press.treeSitter(gpa, source) catch |e| {
        try w.print("joints: cannot import {s}: {s}\n", .{ grammar_path, @errorName(e) });
        return 2;
    };
    defer gr.deinit();

    var built = joints.press.tables(gpa, &gr) catch |e| {
        try w.print("joints: cannot press {s}: {s}\n", .{ gr.name, @errorName(e) });
        return 2;
    };
    defer built.deinit();

    return switch (ask) {
        .at => |n| one(w, &gr, &built, n),
        .census => |wanted| census(gpa, w, &gr, &built, wanted),
        .holding => |item| whence.holding(gpa, w, &gr, &built.collection, item),
        .chain => |n| whence.chain(gpa, w, &gr, &built.collection, n),
    };
}

fn one(
    w: *std.Io.Writer,
    gr: *const Grammar,
    built: *const joints.press.Result,
    at: u32,
) !u8 {
    if (at >= built.collection.states.len) {
        try w.print("joints: {s} has {d} states\n", .{ gr.name, built.collection.states.len });
        return 2;
    }

    try w.print("state {d} of {s}\n\n  items:\n", .{ at, gr.name });
    for (built.collection.states[at].kernel) |item| {
        const p = gr.productions[item.prod];
        try w.print("    {s} ->", .{gr.nameOf(p.lhs)});
        for (p.rhs, 0..) |sym, k| {
            if (k == item.dot) try w.writeAll(" .");
            try w.print(" {s}", .{gr.nameOf(sym)});
        }
        if (item.dot == p.rhs.len) try w.writeAll(" .");
        try w.writeAll("\n");
    }

    const shift = try row(w, gr, built, at, .shift);
    const fold = try row(w, gr, built, at, .fold);
    try w.print(
        "\n  shift {d}, lookahead {d} — {d} terminal(s) accepted of {d}\n",
        .{ shift, fold, shift + fold, gr.terminal_count },
    );
    return 0;
}

/// How many states admit each named terminal, by half, and what else is
/// shiftable beside it where it is.
///
/// This exists because the question a lexical lane actually has is never about
/// one state — it is "if I seat a hand for this terminal, how often does it
/// have to beat a rival, and which". Answering that by eye over 3,416 states is
/// how a guess becomes a design.
///
/// It shares `Half.of` with the row above rather than re-deriving the split,
/// and that is the whole reason it lives in this file. A census of a mechanism
/// and the mechanism itself are two implementations of one fact, and this repo
/// has already been bitten by them disagreeing: `lex`'s blind count called
/// swift blind to a terminal the parser was emitting, because the count read a
/// field that had not heard about the new role. One function, one answer.
fn census(
    gpa: std.mem.Allocator,
    w: *std.Io.Writer,
    gr: *const Grammar,
    built: *const joints.press.Result,
    wanted: []const []const u8,
) !u8 {
    const states: u32 = @intCast(built.collection.states.len);
    try w.print("{s}: {d} states, {d} terminals\n", .{ gr.name, states, gr.terminal_count });

    var found: u32 = 0;
    for (wanted) |name| {
        const sym = symbolOf(gr, name) orelse {
            try w.print("\n{s}\n  no such terminal\n", .{name});
            continue;
        };
        found += 1;

        // Company per shifting state, kept so the spread can be reported
        // rather than a mean that hides it. The previous lane's whole finding
        // was a median of one under a prediction of tens.
        var company: std.ArrayList(u32) = .empty;
        defer company.deinit(gpa);
        var folds: u32 = 0;
        var alone: u32 = 0;
        var rivals: std.ArrayList(u16) = .empty;
        defer rivals.deinit(gpa);

        for (0..states) |at| {
            const half = Half.of(built.tables.at(@intCast(at), sym).kind) orelse continue;
            if (half == .fold) {
                folds += 1;
                continue;
            }
            var beside: u32 = 0;
            for (0..gr.terminal_count) |other| {
                if (other == sym) continue;
                if (Half.of(built.tables.at(@intCast(at), @intCast(other)).kind) != .shift) continue;
                beside += 1;
                for (rivals.items) |seen| {
                    if (seen == other) break;
                } else try rivals.append(gpa, @intCast(other));
            }
            if (beside == 0) alone += 1;
            try company.append(gpa, beside);
        }

        try w.print("\n{s}\n  shift in {d} state(s), lookahead in {d}\n", .{
            name, company.items.len, folds,
        });
        if (company.items.len == 0) continue;
        std.mem.sort(u32, company.items, {}, std.sort.asc(u32));
        try w.print("  company where it shifts: min {d}, median {d}, max {d}" ++
            " — sole shift in {d} state(s)\n", .{
            company.items[0],
            company.items[company.items.len / 2],
            company.items[company.items.len - 1],
            alone,
        });
        try w.print("  {d} distinct rival(s) across those states:", .{rivals.items.len});
        for (rivals.items, 0..) |r, i| {
            if (i == 12) {
                try w.print(" +{d} more", .{rivals.items.len - i});
                break;
            }
            try w.print(" {s}", .{gr.nameOf(r)});
        }
        try w.writeAll("\n");
    }

    // Pairwise co-admission, which is the question a partial seating turns on:
    // a hand for A may skip a state that also wants B only if the two are never
    // shiftable together. Zero here is what makes "seat one of the cohort"
    // sound; one is what kept swift's `!` out.
    if (found > 1) try together(w, gr, built, wanted);
    return if (found == 0) 1 else 0;
}

/// For every pair among `wanted`, the states that admit both — in each half,
/// separately, because a hand reads one of them and this table used to print
/// only the other.
///
/// The `shift` column is the narrow question: both terminals would consume at
/// this offset, so a hand answering one has taken the other's bytes. The `set`
/// column is the question a hand *actually* faces, and they are not the same
/// column. `drive.offer` admits every terminal the state has any non-error
/// action for — shifts and reduce-lookaheads alike — because that is
/// tree-sitter's `valid_symbols`, and `valid_symbols` is the only thing a
/// scanner reads. So a pair at zero shifts and nine set-admissions is a pair
/// a hand has to resolve nine times, and reading the shift column alone says
/// it never has to resolve it at all.
///
/// This is the same 85× split the row above prints under two headers, arriving
/// a second time in a second place. It was found by a lane whose design had
/// already been written against the shift column.
fn together(
    w: *std.Io.Writer,
    gr: *const Grammar,
    built: *const joints.press.Result,
    wanted: []const []const u8,
) !void {
    try w.writeAll("\nco-admitted (shift = both consume; set = both in the" ++
        " permission set a hand reads):\n");
    for (wanted, 0..) |a_name, i| {
        const a = symbolOf(gr, a_name) orelse continue;
        for (wanted[i + 1 ..]) |b_name| {
            const b = symbolOf(gr, b_name) orelse continue;
            var shifts: u32 = 0;
            var set: u32 = 0;
            var first: ?u32 = null;
            var first_set: ?u32 = null;
            for (0..built.collection.states.len) |at| {
                const ha = Half.of(built.tables.at(@intCast(at), a).kind) orelse continue;
                const hb = Half.of(built.tables.at(@intCast(at), b).kind) orelse continue;
                if (first_set == null) first_set = @intCast(at);
                set += 1;
                if (ha != .shift or hb != .shift) continue;
                if (first == null) first = @intCast(at);
                shifts += 1;
            }
            try w.print("  {s: <26} {s: <26} shift {d: <5} set {d}", .{
                a_name, b_name, shifts, set,
            });
            if (first) |at| {
                try w.print("  (first shift: state {d})", .{at});
            } else if (first_set) |at| {
                try w.print("  (first set: state {d})", .{at});
            }
            try w.writeAll("\n");
        }
    }
}

fn symbolOf(gr: *const Grammar, name: []const u8) ?u32 {
    for (0..gr.terminal_count) |sym| {
        if (std.mem.eql(u8, gr.nameOf(@intCast(sym)), name)) return @intCast(sym);
    }
    return null;
}

/// Which half of the row a cell belongs to.
///
/// Owned by `lalr` and not by this file. It used to live here, which was right
/// while this was the only instrument making the split and wrong the moment a
/// second one had to: `inquest` names the terminal a wall was waiting for and
/// `survey` prints what a state accepts, and both were answering the union
/// while sounding like they meant the shifts. A shared definition is what makes
/// "which half" one fact rather than three.
const Half = joints.press.Half;

const headings = std.enums.EnumArray(Half, []const u8).init(.{
    .shift =
    \\
    \\  row — shifts: this state CONSUMES the token, so a lexer competes here
    \\
    ,
    .fold =
    \\
    \\  row — lookahead: this terminal only TRIGGERS a fold, consuming no byte
    \\
    ,
});

/// One half of the row, and how many cells it held.
fn row(
    w: *std.Io.Writer,
    gr: *const Grammar,
    built: *const joints.press.Result,
    at: u32,
    half: Half,
) !u32 {
    var cells: u32 = 0;
    for (0..gr.terminal_count) |sym| {
        const act = built.tables.at(at, @intCast(sym));
        if (Half.of(act.kind) != half) continue;
        if (cells == 0) try w.writeAll(headings.get(half));
        cells += 1;
        try w.print("    {s: <28} ", .{gr.nameOf(@intCast(sym))});
        try verdict(w, gr, act);
        for (built.tables.conflicts) |k| {
            if (k.state != at or k.terminal != sym) continue;
            try w.print("   [{s} {s}, over ", .{ @tagName(k.class), @tagName(k.kind) });
            try verdict(w, gr, k.other);
            try w.writeAll("]");
            break;
        }
        try w.writeAll("\n");
    }
    // A state with no shift at all is a state that can only fold, and saying so
    // is worth a line: the empty half is exactly the evidence a lexical lane is
    // usually after, and an absent header reads as an oversight.
    if (cells == 0) {
        try w.writeAll(headings.get(half));
        try w.writeAll("    (none)\n");
    }
    return cells;
}

/// One production, with the precedence and side each step carries — because in
/// a conflict report those two are usually the whole answer to "why didn't this
/// resolve". Printed against the final step, which is the one a completed
/// reading is judged on.
pub fn rule(w: *std.Io.Writer, gr: *const Grammar, prod: u32) !void {
    const p = gr.productions[prod];
    try w.print("{s} ->", .{gr.nameOf(p.lhs)});
    if (p.rhs.len == 0) try w.writeAll(" ε");
    for (p.rhs) |s| try w.print(" {s}", .{gr.nameOf(s)});
    const last = p.consumed(p.rhs.len);
    if (last.prec != .none or last.assoc != .none) {
        try w.writeAll("   [prec ");
        switch (last.prec) {
            .none => try w.writeAll("-"),
            .level => |v| try w.print("{d}", .{v}),
            .name => |n| try w.print("'{s}'", .{gr.prec_names[n]}),
        }
        try w.print(" {s}]", .{@tagName(last.assoc)});
    }
}

/// What a cell decided, in the vocabulary of the grammar rather than of the
/// table: a shift names the token read, a reduce names the rule folded.
pub fn verdict(w: *std.Io.Writer, gr: *const Grammar, a: Action) !void {
    switch (a.kind) {
        .shift => try w.writeAll("read on"),
        .accept => try w.writeAll("accept"),
        .err => try w.writeAll("nothing"),
        .reduce => {
            try w.writeAll("fold  ");
            try rule(w, gr, a.value);
        },
    }
}

test "state: the halves partition every verb but the empty one" {
    // Guarding `lalr.Half` from this file on purpose. The partition is what
    // lets the footer add two counts and call the sum the accepted set, and
    // this verb is the reader that would print the lie if a fifth action verb
    // arrived and landed in neither half.
    // The point of the split, asserted rather than left to the printer: every
    // action a cell can hold lands in exactly one half, so the footer may add
    // the two counts and call the sum the accepted set. Written as an
    // exhaustive walk of the verb enum so that a fifth verb added later fails
    // here rather than silently vanishing from one of the two lists — the
    // failure mode this whole file exists to prevent is a row that quietly
    // answers less than it claims.
    var seen: u32 = 0;
    inline for (@typeInfo(Verb).@"enum".fields) |f| {
        const half = Half.of(@enumFromInt(f.value));
        if (std.mem.eql(u8, f.name, "err")) {
            try std.testing.expectEqual(@as(?Half, null), half);
        } else {
            try std.testing.expect(half != null);
            seen += 1;
        }
    }
    try std.testing.expectEqual(@as(u32, 3), seen);
}
