//! A mapped folio, wearing the three types a parse takes.
//!
//! `quire.Gather` asks for a `Grammar`, a `Collection` and a `Tables`, and it is
//! right to: those are what a parse reads, and none of them should grow a second
//! spelling just because the bytes arrived from a file this time. So `bind`
//! rebuilds exactly those three and the parse loop cannot tell where they came
//! from, which is the whole trick behind `outliner parse x.folio` costing a map
//! instead of a press.
//!
//! **A bound grammar is a parser, not a re-pressable grammar.** A folio carries
//! the table and not the argument that made it, so the fields the press consumed
//! on the way in come back empty: step precedence and associativity, the
//! precedence orderings, the declared ambiguity groups, and the kernel items
//! that named each state while it was being built. Everything a parse or a tree
//! build reads is exact - including `Production.dynamic`, which reads as a rank
//! and not as a zero, because a rank the press could not spend is not an input
//! it consumed. Saying so here rather than leaving it to be discovered
//! by somebody whose second pressing came out different.
//!
//! Most of it is not copied - the bodies, the per-state completions and the
//! conflict parties are views straight into the mapped bytes. The table is the
//! exception, and it is a deliberate one. On disk it is interned three layers
//! deep (see `forme`); in memory `quire` indexes it as a grid, so this is where
//! it gets laid back out flat. That costs a `states * width` allocation and a
//! sweep of the live cells, single-digit milliseconds on the largest grammar in
//! the corpus, and it buys the file being a fraction of the size that grid
//! would be. Paying it once at open, in a form the parse loop then reads
//! without a branch, is the right side of that trade; paying it per cell in the
//! parse loop would not be.

const std = @import("std");
const collate = @import("collate.zig");
const leaf = @import("leaf.zig");
const g = @import("../press/grammar.zig");
const lalr = @import("../press/lalr.zig");
const lr0 = @import("../press/lr0.zig");
const settle = @import("../press/settle.zig");

pub const Error = std.mem.Allocator.Error;

/// The three halves of a parser, and the one arena behind them.
///
/// Each press type is handed an empty arena of its own so that its `deinit`
/// stays correct and free; the allocations are all in this one, which outlives
/// them by a line.
pub const Bound = struct {
    arena: std.heap.ArenaAllocator,
    grammar: g.Grammar,
    collection: lr0.Collection,
    tables: lalr.Tables,

    pub fn deinit(b: *Bound) void {
        b.grammar.deinit();
        b.collection.deinit();
        b.tables.deinit();
        b.arena.deinit();
        b.* = undefined;
    }
};

/// Rebuild a parser from a verified folio. The folio's bytes must outlive the
/// result, which is the point: the tables are not copied out of them.
pub fn bind(gpa: std.mem.Allocator, f: *const collate.Folio) Error!Bound {
    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    const a = arena.allocator();

    // The grid first, because both of the other two are read out of it.
    const dense = try cells(a, f);
    var out: Bound = .{
        .arena = undefined,
        .grammar = try vocabulary(a, f),
        .collection = try automaton(a, f, dense),
        .tables = try tabulation(a, f, dense),
    };
    // Moved last for the reason `Builder.finish` gives: a struct literal
    // evaluates in source order, so an arena captured first holds the buffer
    // list as it was then and frees none of what the later fields allocated.
    out.arena = arena;
    arena = std.heap.ArenaAllocator.init(gpa);
    return out;
}

fn vocabulary(a: std.mem.Allocator, f: *const collate.Folio) Error!g.Grammar {
    const n = f.symbolCount();
    const names = try a.alloc([]const u8, n);
    const patterns = try a.alloc(?g.Pattern, n);
    const lexis = try a.alloc(g.Lexis, n);
    const shapes = try a.alloc(g.Shape, n);
    var externals: std.ArrayList(g.Symbol) = .empty;
    for (0..n) |i| {
        const s: u32 = @intCast(i);
        names[i] = f.nameOf(s);
        patterns[i] = if (f.patternOf(s)) |p| switch (p) {
            .literal => |lit| .{ .literal = lit },
            .regex => |rx| .{ .regex = rx },
            .external => blk: {
                try externals.append(a, s);
                break :blk .external;
            },
        } else null;
        const lx = f.lexisOf(s);
        lexis[i] = .{ .immediate = lx.flags & leaf.LexisRecord.immediate != 0, .prec = lx.prec };
        shapes[i] = switch (f.shapeOf(s)) {
            .named => .named,
            .anonymous => .anonymous,
            .hidden => .hidden,
            .invented => .invented,
        };
    }

    const aliases = try a.alloc(g.Alias, f.aliasCount());
    for (aliases, 0..) |*slot, i| {
        const al = f.aliasOf(@intCast(i));
        slot.* = .{ .name = al.name, .named = al.named };
    }
    const fields = try a.alloc([]const u8, f.fieldCount());
    for (fields, 0..) |*slot, i| slot.* = f.fieldOf(@intCast(i));

    const productions = try a.alloc(g.Production, f.head.production_count);
    const steps = try a.alloc(g.Step, f.view(.rhs, u32).len);
    for (productions, f.productions(), 0..) |*slot, rec, i| {
        const mine = steps[rec.rhs_off..][0..rec.rhs_len];
        const refs = f.stepsOf(@intCast(i));
        for (mine, 0..) |*step, j| {
            const st = f.stepAt(refs.at(@intCast(j)));
            // Precedence and associativity are press inputs and are not in the
            // file; a bound step carries only what names a child.
            step.* = .{
                .alias = if (st.alias == leaf.none) null else st.alias,
                .field = if (st.field == leaf.none) null else st.field,
            };
        }
        slot.* = .{
            .lhs = rec.lhs,
            .rhs = f.rhsOf(@intCast(i)),
            .steps = mine,
            // The one precedence that outlives the press. `audit` has already
            // held the record to the IR's width, so this narrows without a
            // question at bind time.
            .dynamic = @intCast(rec.rank),
        };
    }

    return .{
        .arena = std.heap.ArenaAllocator.init(a),
        .name = f.title(),
        .names = names,
        .patterns = patterns,
        .lexis = lexis,
        .shapes = shapes,
        .terminal_count = f.head.terminal_count,
        .productions = productions,
        .by_lhs = try index(a, productions, n - f.head.terminal_count, f.head.terminal_count),
        .start = f.head.start,
        .extras = f.extras(),
        .owner = f.view(.owner, u32),
        .supertypes = f.supertypes(),
        .aliases = aliases,
        .field_names = fields,
        .externals = try externals.toOwnedSlice(a),
        .word = f.word(),
        // Read where it lies, like everything else here: the scanner inflates
        // out of the mapping rather than copying it first.
        .lexicon = f.lexicon(),
        // Press inputs; see the header. Empty, never absent, so every reader
        // that iterates them reads zero of them rather than a null.
        .declared_conflicts = &.{},
        .prec_names = &.{},
        .orderings = &.{},
    };
}

/// `by_lhs`: which productions each nonterminal has. Rebuilt rather than
/// written, because it is an index over the production list and a folio that
/// carried it would be carrying a second opinion about its own contents.
fn index(a: std.mem.Allocator, productions: []const g.Production, nts: u32, base: u32) Error![]const []const u32 {
    const counts = try a.alloc(u32, nts);
    @memset(counts, 0);
    for (productions) |p| counts[p.lhs - base] += 1;
    const out = try a.alloc([]u32, nts);
    for (out, counts) |*slot, k| slot.* = try a.alloc(u32, k);
    @memset(counts, 0);
    for (productions, 0..) |p, i| {
        const k = p.lhs - base;
        out[k][counts[k]] = @intCast(i);
        counts[k] += 1;
    }
    return out;
}

/// The transitions, put back together out of the row and the strays.
///
/// A row already says where a terminal reads to, and that is the edge in every
/// state but a handful, so this walks the expanded row rather than a stored
/// edge list and lets `odd` overrule it where the two were made to differ. The
/// nonterminal edges are in the row outright, out past the terminal columns.
///
/// Takes the dense table because `tabulation` has just built it. Expanding the
/// same rows twice to answer two questions about them would be the sort of
/// tidiness that shows up in the load time.
fn automaton(a: std.mem.Allocator, f: *const collate.Folio, dense: []const lalr.Action) Error!lr0.Collection {
    const n = f.head.state_count;
    const width = f.head.width;
    const terminals = f.head.terminal_count;
    const states = try a.alloc(lr0.State, n);

    var all: std.ArrayList(lr0.Edge) = .empty;
    const spans = try a.alloc(u32, n + 1);
    const strays = f.odds();
    var s: usize = 0;
    for (0..n) |i| {
        const q: u32 = @intCast(i);
        spans[q] = @intCast(all.items.len);
        const row = dense[q * width ..][0..width];

        // Terminals, ascending, from two sources at once: the reads the row
        // states and the strays that overrule them. Exactly the inverse of
        // what `forme` did to separate them.
        var col: u32 = 0;
        while (true) {
            while (col < terminals and row[col].kind != .shift) col += 1;
            const read = if (col < terminals) col else leaf.none;
            const stray = if (s < strays.len and strays[s].state == q) strays[s].symbol else leaf.none;
            const symbol = @min(read, stray);
            if (symbol == leaf.none) break;
            if (stray == symbol) {
                if (strays[s].target != leaf.none) {
                    try all.append(a, .{ .symbol = symbol, .target = strays[s].target });
                }
                s += 1;
                if (read == symbol) col += 1;
            } else {
                try all.append(a, .{ .symbol = symbol, .target = row[col].value });
                col += 1;
            }
        }

        // Nonterminals. They arrive grouped by target rather than by symbol,
        // so the tail is sorted; a state has a few of these where it has
        // dozens of terminal columns.
        const nts = all.items.len;
        const groups = f.groupsOf(f.rowOf(q));
        for (0..groups.len()) |k| {
            const rec = f.groupAt(groups.at(@intCast(k)));
            const cols = f.columnsOf(rec.set);
            for (0..cols.len()) |j| {
                const at = cols.at(@intCast(j));
                if (at < width) continue;
                const act: lalr.Action = @bitCast(rec.cell);
                try all.append(a, .{ .symbol = f.symbolAt(at), .target = act.value });
            }
        }
        std.mem.sort(lr0.Edge, all.items[nts..], {}, bySymbol);
    }
    spans[n] = @intCast(all.items.len);
    for (states, 0..) |*slot, i| slot.* = .{
        // Kernels are press provenance and are not in the file; see the header.
        .kernel = &.{},
        .edges = all.items[spans[i]..spans[i + 1]],
        .complete = f.completeOf(@intCast(i)),
    };
    return .{ .arena = std.heap.ArenaAllocator.init(a), .states = states };
}

fn bySymbol(_: void, x: lr0.Edge, y: lr0.Edge) bool {
    return x.symbol < y.symbol;
}

fn tabulation(a: std.mem.Allocator, f: *const collate.Folio, dense: []const lalr.Action) Error!lalr.Tables {
    const conflicts = try a.alloc(lalr.Conflict, f.conflicts().len);
    for (conflicts, f.conflicts()) |*slot, rec| slot.* = .{
        .state = rec.state,
        .terminal = rec.terminal,
        .kind = switch (@as(leaf.ConflictKind, @enumFromInt(rec.kind))) {
            .shift_reduce => .shift_reduce,
            .reduce_reduce => .reduce_reduce,
        },
        .class = switch (@as(leaf.ConflictClass, @enumFromInt(rec.class))) {
            .repetition => .repetition,
            .declared => .declared,
            .residual => .residual,
            .unwritten => .unwritten,
        },
        .chosen = @bitCast(rec.chosen),
        .other = @bitCast(rec.other),
        // Same 32 bits either way: the file writes an action as its cell and a
        // reader hands the slice straight back rather than copying it.
        .rest = @ptrCast(f.rivalsOf(rec)),
        .party = f.partyOf(rec),
    };
    const frayed = try a.alloc(settle.Frayed, f.frayed().len);
    for (frayed, f.frayed()) |*slot, rec| slot.* = .{
        .state = rec.state,
        .terminal = rec.terminal,
        .harm = switch (@as(leaf.Harm, @enumFromInt(rec.harm))) {
            .read_dropped => .read_dropped,
            .fold_dropped => .fold_dropped,
        },
    };
    return .{
        .arena = std.heap.ArenaAllocator.init(a),
        .end = f.head.end,
        .width = f.head.width,
        .action = dense,
        .conflicts = conflicts,
        .frayed = frayed,
        // Seams are the unfolding search's input, and that search runs against a
        // freshly pressed result holding its item collection. A folio is the
        // answer after it converged, so there is nothing left to read them for.
        .seams = &.{},
    };
}

/// The table, laid back out as the grid a parse indexes.
///
/// One allocation, one fill of the empty cell, then a sweep of the groups. The
/// fill is what dominates - it is the whole grid, and the live cells are three
/// percent of it - so the cost here is the size of the answer rather than the
/// size of the file.
///
/// `@bitCast` on the cell is sound because `mirrors` proves the two spellings
/// are the same thirty-two bits, and `collate.open` already proved every cell
/// in this file names something that is there.
fn cells(a: std.mem.Allocator, f: *const collate.Folio) Error![]const lalr.Action {
    comptime mirrors();
    const width = f.head.width;
    const out = try a.alloc(lalr.Action, @as(usize, f.head.state_count) * width);
    @memset(out, .{ .kind = .err, .value = 0 });
    for (0..f.head.state_count) |i| {
        const row = out[i * width ..][0..width];
        const groups = f.groupsOf(f.rowOf(@intCast(i)));
        for (0..groups.len()) |k| {
            const rec = f.groupAt(groups.at(@intCast(k)));
            const act: lalr.Action = @bitCast(rec.cell);
            const cols = f.columnsOf(rec.set);
            for (0..cols.len()) |j| {
                const at = cols.at(@intCast(j));
                // Past `width` is a goto, which is the automaton's business and
                // has no cell in the grid.
                if (at < width) row[at] = act;
            }
        }
    }
    return out;
}

/// The one place a folio cell is trusted as a press cell. Written as a
/// comparison rather than a comment so that the day either struct is reordered,
/// this stops being a build.
fn mirrors() void {
    if (@bitSizeOf(leaf.Action) != @bitSizeOf(lalr.Action)) @compileError("action width drifted");
    for (std.enums.values(leaf.Action.Verb)) |verb| {
        const mine: leaf.Action = .{ .verb = verb, .value = 0x2A2A2A };
        const theirs: lalr.Action = @bitCast(@as(u32, @bitCast(mine)));
        if (theirs.value != mine.value) @compileError("the action value moved");
        if (!std.mem.eql(u8, @tagName(theirs.kind), @tagName(verb))) {
            @compileError("action verb " ++ @tagName(verb) ++ " no longer means itself");
        }
    }
}
