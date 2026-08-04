//! Whose wall is this? The question asked of the table rather than of a person.
//!
//! A parse stops somewhere. Four subsystems could be why: the scanner had no
//! terminal for the bytes, the table has no cell for the token, the resolution
//! took a cell the grammar wanted, or the parse loop was standing in a state
//! where the token was never legal. Every round of grammar work spends its first
//! hour deciding which, and the deciding has been done by hand - by someone who
//! reconstructs an argument about lookahead unions from memory, and who gets it
//! wrong in the direction of whichever subsystem they own.
//!
//! It does not need to be done by hand. Three of the four answers are *decidable
//! from the artifact*, by arguments about the whole automaton rather than by
//! sampling it:
//!
//!   1. **A byte nothing can tokenize is nobody's table's fault.** The scanner is
//!      driven by a state's action row, so a stray byte means *this row* offered
//!      no terminal that matched. Re-lex the same offset with the row's
//!      restriction lifted: if a terminal matches there, the bytes were lexable
//!      and the wall is about which cell a state holds. If nothing matches with
//!      the whole slate admitted, no table could have been consulted at all -
//!      the terminal that would cover those bytes is one the grammar hands to an
//!      external scanner we cannot run.
//!
//!   2. **An empty cell is empty under every split.** LALR lookaheads are
//!      supersets of the canonical LR(1) ones - merging states unions their
//!      contexts, and a union only ever adds. So a token absent from a merged
//!      row is absent from every canonical row the merge stood in for, and
//!      splitting the state cannot put it back. `err` here is `err` in LR(1),
//!      and the press has nothing to answer for.
//!
//!   3. **A read is only ever lost to a fold.** The one way this press removes a
//!      reading is `settle` preferring a reduce over a shift. So if no state
//!      anywhere folds on the token, no state anywhere dropped a read of it, and
//!      every state refusing it never had it to lose. This is the argument that
//!      retires a wall in one number: cpp's 112 states refusing `number_literal`
//!      after `(`, against 0 states folding on it.
//!
//! What is left after those three is press's, and it is not a judgement either:
//! `settle` records the cells a merge invented as `Frayed`, so the damage has an
//! address. If one sits on the path the refused token actually drove - the wall's
//! own cell, or any state the token folded through on its way there - the wall is
//! downstream of that cell and this says which one, with `lalr.Floor.Cause`
//! saying whether another arrival partition would remove it.
//!
//! The strength of the answer is part of the answer. A caller that cannot supply
//! the fold chain (the CLI prints a verdict, not a path) gets `proven = false`
//! when the table drops the terminal *somewhere* but nothing places the wall
//! downstream of it. That is a suspicion about a table, and it reads differently
//! from a proof about a parse. Conflating the two is how the census misrouted c
//! for three rounds.
//!
//! Nothing here allocates or walks the collection: it is four scans of the frayed
//! list and one of an action column, so it costs less than printing the answer.

const std = @import("std");
const g = @import("grammar.zig");
const lalr = @import("lalr.zig");
const settle = @import("settle.zig");

/// One reduction the refused token drove, and the state it was taken in. A
/// structural mirror of `kernel/walk/drive.zig`'s `Fold`: press is the build
/// side and cannot import the run time, and the two fields are the whole type.
pub const Fold = struct { state: u32, prod: u32 };

/// Where a parse stopped, in the only terms a table can answer about.
pub const Wall = union(enum) {
    whole,
    /// Every byte lexed and no root ever closed.
    unclosed,
    /// No terminal the state offered begins at `at`. `lexable` is argument 1: the
    /// only thing separating a byte nothing can tokenize from a byte this state
    /// would not hear, and the answer is only a proof if somebody asked.
    ///
    /// `state` is optional because the verdict does not print it - the walk knows
    /// which state it stood in and reports only the offset. Absent, an invented
    /// cell *at* the wall cannot be checked and only the table-wide arguments run.
    stray: struct { at: u32, state: ?u32 = null, lexable: Lexable = .unasked },
    /// The token lexed and the row had nothing for it. `folded` is the chain of
    /// reductions the token drove before the table gave up, `null` when the
    /// caller has a verdict but not a path.
    refused: struct { terminal: u32, state: u32, folded: ?[]const Fold = null },

    /// A wall out of the words the CLI already prints for it, so a census is the
    /// parser's own verdict handed back to the press rather than a second
    /// vocabulary someone has to keep in step:
    ///
    ///     outliner: f.c: unexpected , at 1354 in state 803, 2 roots
    ///     outliner: x.rb: stray byte at 357, 4 roots
    ///
    /// A `stray` needs one fact the verdict does not carry - whether anything in
    /// the grammar lexes there at all - so `lexable` carries what the unrestricted
    /// scanner found, and whether anyone ran it.
    ///
    /// Keyword-directed rather than positional: the prefix is a path, and a
    /// parser that counts colons breaks on the first file with one in its name.
    pub fn read(gr: *const g.Grammar, line: []const u8, lexable: Lexable) ?Wall {
        if (std.mem.indexOf(u8, line, "unexpected ")) |i| {
            const tail = line[i + "unexpected ".len ..];
            const at = std.mem.indexOf(u8, tail, " at ") orelse return null;
            const in = std.mem.indexOf(u8, tail, " in state ") orelse return null;
            const terminal = terminalOf(gr, tail[0..at]) orelse return null;
            const state = std.fmt.parseInt(u32, upto(tail[in + " in state ".len ..], ','), 10) catch
                return null;
            return .{ .refused = .{ .terminal = terminal, .state = state } };
        }
        if (std.mem.indexOf(u8, line, "stray byte at ")) |i| {
            const at = std.fmt.parseInt(
                u32,
                upto(line[i + "stray byte at ".len ..], ','),
                10,
            ) catch return null;
            return .{ .stray = .{ .at = at, .lexable = lexable } };
        }
        if (std.mem.indexOf(u8, line, "truncated") != null) return .unclosed;
        if (std.mem.indexOf(u8, line, "accepted") != null) return .whole;
        return null;
    }
};

/// What the scanner finds at a stray offset with the action row's restriction
/// lifted. `unasked` is a third state on purpose: a census that did not look, or
/// looked only at the literals, has not proved the bytes unlexable - and an
/// unproven `lexer` must not print like a proven one.
pub const Lexable = union(enum) { unasked, nothing, terminal: u32 };

/// The longest literal terminal standing at `at`, if one does. Argument 1 in the
/// half a table can answer on its own: matching a regex is the run time's job and
/// needs the engine, but a literal is a string compare, and a hit is a *proof*
/// that the bytes are lexable - which is the whole question for a stray on `,` or
/// `"` in a grammar whose row simply did not offer it.
///
/// A miss proves nothing (a pattern terminal may still match), so the caller
/// answers `unasked` rather than `nothing`. Extras are skipped: a terminal the
/// lexer passes over between tokens never appears in an action row, so finding
/// one here would route a wall to `nowhere` on the strength of a comment.
pub fn literalAt(gr: *const g.Grammar, bytes: []const u8, at: u32) ?u32 {
    if (at >= bytes.len) return null;
    var best: ?u32 = null;
    var longest: usize = 0;
    for (gr.patterns[0..gr.terminal_count], 0..) |pat, sym| {
        const lit = switch (pat orelse continue) {
            .literal => |s| s,
            else => continue,
        };
        if (lit.len <= longest or !std.mem.startsWith(u8, bytes[at..], lit)) continue;
        if (std.mem.indexOfScalar(g.Symbol, gr.extras, @intCast(sym)) != null) continue;
        best = @intCast(sym);
        longest = lit.len;
    }
    return best;
}

/// The terminal of that name, or null. Terminals only: a nonterminal cannot be a
/// wall, and answering with one would put a column index past the table's width.
pub fn terminalOf(gr: *const g.Grammar, name: []const u8) ?u32 {
    for (gr.names[0..gr.terminal_count], 0..) |it, sym| {
        if (std.mem.eql(u8, it, name)) return @intCast(sym);
    }
    return null;
}

fn upto(s: []const u8, sentinel: u8) []const u8 {
    return s[0 .. std.mem.indexOfScalar(u8, s, sentinel) orelse s.len];
}

/// Who has to change something for this wall to move.
pub const Owner = enum {
    /// Nothing stopped.
    whole,
    /// The scanner: no terminal covers these bytes, usually because the grammar
    /// hands them to an external scanner that is not implemented here.
    lexer,
    /// The press: a cell a merge invented sits on the path the token drove.
    press,
    /// The parse loop: every cell on the path is what the grammar means, and the
    /// state the loop was standing in refuses the token under every split of it.
    weave,
    /// The front end: the token is readable in no state at all, so no parse
    /// could ever have used it. A grammar imported wrongly, not a table decided
    /// wrongly - and press's, since press is the front end.
    nowhere,
    /// Input ended first. Nothing refused anything.
    unclosed,
};

/// The argument, not the label. Every one of these is a sentence about the whole
/// automaton that can be checked; `why` spells it out.
pub const Because = enum {
    accepted,
    input_ended,
    /// Argument 1, negative half: the whole terminal slate matches nothing here.
    nothing_lexes,
    /// The wall's own cell is one a merge invented.
    dropped_here,
    /// A state the token folded through holds a cell a merge invented.
    dropped_upstream,
    /// A merge damaged this terminal somewhere, and nothing places this wall
    /// downstream of it. The only unproven answer.
    dropped_elsewhere,
    /// Argument 3: no state folds on this terminal, so no state lost a read of
    /// it.
    never_folded,
    /// Argument 2: the cell is empty, and a merged row is a superset of every
    /// canonical row it stands for.
    empty_under_every_split,
    /// No state reads this terminal at all.
    never_read,

    pub fn why(b: Because) []const u8 {
        return switch (b) {
            .accepted => "accepted",
            .input_ended => "input ended before the start symbol closed; nothing refused a token",
            .nothing_lexes => "no terminal in the grammar matches here even with the row's " ++
                "restriction lifted, so no table was consulted",
            .dropped_here => "this cell is one a state merge invented, and the read it removed " ++
                "was legal after some of the paths that arrive here",
            .dropped_upstream => "the token folded through a cell a state merge invented; the " ++
                "refusal here is that fold's downstream",
            .dropped_elsewhere => "a merge damaged this terminal's cell elsewhere, and no fold " ++
                "chain was supplied to say whether this wall is downstream of it",
            .never_folded => "no state anywhere folds on this terminal, and a read is only ever " ++
                "lost to a fold, so no state ever had it to lose",
            .empty_under_every_split => "the cell is empty, and a merged lookahead is a superset " ++
                "of every canonical one it stands for, so it is empty under every split",
            .never_read => "no state reads this terminal, so no parse could have used it",
        };
    }
};

/// What the table says about one wall, and how strongly.
pub const Finding = struct {
    owner: Owner,
    because: Because,
    /// False only for `dropped_elsewhere`: a suspicion about a table rather than
    /// a proof about a parse.
    proven: bool = true,
    /// The invented cell, when one is on the path.
    cell: ?settle.Frayed = null,
    /// Whether an arrival partition removes that cell. `open` is the only bucket
    /// another press round could reach; see `lalr.Floor`.
    cause: ?lalr.Floor.Cause = null,
    /// The terminal's column, table-wide. `folds == 0` is argument 3 and
    /// `reads == 0` is `never_read`; both are here so a reader can check the
    /// argument rather than take the label.
    reads: u32 = 0,
    folds: u32 = 0,
    /// States that dropped a read of this terminal to a fold a merge invented.
    dropped: u32 = 0,
    /// States where a merge instead picked the wrong *fold* on this terminal, so
    /// the refusal surfaces further along. Together with `dropped` this is all the
    /// merge damage the terminal carries anywhere: at zero, no upstream fold on
    /// this token can be the press's either, which is what makes an unreachable
    /// wall cell a *proof* about the whole path rather than about one cell.
    misfolded: u32 = 0,
};

/// The classifier. Reads the action column for the terminal and the frayed list;
/// touches nothing else.
pub fn over(t: *const lalr.Tables, wall: Wall) Finding {
    return switch (wall) {
        .whole => .{ .owner = .whole, .because = .accepted },
        .unclosed => .{ .owner = .unclosed, .because = .input_ended },
        // A stray byte the whole slate cannot match never reached a table. One
        // it can match is a state that would not hear a terminal other states
        // read, which is the same question as a refused token whose fold chain
        // is empty - the scanner refuses before the row is consulted, so there
        // is no path to be downstream of.
        .stray => |s| switch (s.lexable) {
            .terminal => |sym| refused(t, sym, s.state, &.{}),
            .nothing => .{ .owner = .lexer, .because = .nothing_lexes },
            .unasked => .{ .owner = .lexer, .because = .nothing_lexes, .proven = false },
        },
        .refused => |r| refused(t, r.terminal, r.state, r.folded),
    };
}

fn refused(t: *const lalr.Tables, terminal: u32, state: ?u32, folded: ?[]const Fold) Finding {
    var out: Finding = .{ .owner = .weave, .because = .empty_under_every_split };
    for (0..t.action.len / t.width) |at| switch (t.at(@intCast(at), terminal).kind) {
        .shift => out.reads += 1,
        .reduce => out.folds += 1,
        else => {},
    };
    for (t.frayed) |f| {
        if (f.terminal != terminal) continue;
        switch (f.harm) {
            .read_dropped => out.dropped += 1,
            .fold_dropped => out.misfolded += 1,
        }
    }

    // The path first, nearest end first: the wall's own cell, then every state
    // the token folded through. A cell on the path is a proof; the same cell
    // anywhere else is not.
    if (onPath(t, terminal, state, folded)) |hit| {
        out.owner = .press;
        out.because = if (state != null and hit.state == state.?)
            .dropped_here
        else
            .dropped_upstream;
        out.cell = hit;
        out.cause = t.cause(hit);
        return out;
    }
    // With the path known, an intact path is a proof. Without it, the table's own
    // damage on this terminal decides: none anywhere and no fold this token drove
    // could have been the press's either, so the wall cell being unreachable
    // settles the whole path. Any damage at all, and it cannot.
    if (folded == null and out.dropped + out.misfolded > 0) {
        out.owner = .press;
        out.because = .dropped_elsewhere;
        out.proven = false;
        return out;
    }
    if (out.reads == 0) {
        out.owner = .nowhere;
        out.because = .never_read;
    } else if (out.folds == 0) {
        out.because = .never_folded;
    }
    return out;
}

/// The invented cell nearest the wall on the path the token drove, if any. Both
/// harms count: a `read_dropped` cell the chain stood in took a reading away, and
/// a `fold_dropped` one sent the parse down a production the token cannot finish.
/// Which of the two it was is `Frayed.harm`, and the caller wants to know.
fn onPath(t: *const lalr.Tables, terminal: u32, state: ?u32, folded: ?[]const Fold) ?settle.Frayed {
    if (state) |s| if (t.frayedAt(s, terminal)) |f| return f;
    const chain = folded orelse return null;
    var i = chain.len;
    while (i > 0) {
        i -= 1;
        if (t.frayedAt(chain[i].state, terminal)) |f| return f;
    }
    return null;
}

/// One row of a census: `<owner> <because>`, plus whichever counts carry the
/// argument. Written rather than returned as a string so nothing here allocates.
pub fn write(f: Finding, gr: *const g.Grammar, wall: Wall, w: *std.Io.Writer) !void {
    try w.print("{s}", .{@tagName(f.owner)});
    if (!f.proven) try w.writeAll("?");
    switch (wall) {
        .refused => |r| try w.print(" on {s} in state {d}", .{ gr.nameOf(r.terminal), r.state }),
        .stray => |s| switch (s.lexable) {
            .terminal => |sym| try w.print(" on {s} at byte {d}", .{ gr.nameOf(sym), s.at }),
            .nothing => try w.print(" at byte {d}", .{s.at}),
            .unasked => try w.print(" at byte {d} (unlexed)", .{s.at}),
        },
        else => {},
    }
    if (f.cell) |c| try w.print(
        " [state {d}, {s}, {s}]",
        .{ c.state, @tagName(c.harm), @tagName(f.cause.?) },
    );
    switch (f.because) {
        .never_folded, .empty_under_every_split, .never_read => try w.print(
            " ({d} read, {d} fold, {d} frayed)",
            .{ f.reads, f.folds, f.dropped + f.misfolded },
        ),
        .dropped_elsewhere => try w.print(
            " ({d} dropped, {d} misfolded)",
            .{ f.dropped, f.misfolded },
        ),
        else => {},
    }
    try w.print(": {s}", .{f.because.why()});
}

const testing = std.testing;

/// A table by hand. The classifier reads an action column and a frayed list and
/// nothing else, so a hand-built one is the whole input - and it is the only way
/// to test the buckets a real grammar happens not to be in this week.
const Bench = struct {
    arena: std.heap.ArenaAllocator,
    action: []lalr.Action,
    frayed: std.ArrayList(settle.Frayed) = .empty,
    seams: std.ArrayList(lalr.Seam) = .empty,
    width: u32,

    fn init(states: u32, width: u32) !Bench {
        const action = try testing.allocator.alloc(lalr.Action, states * width);
        @memset(action, lalr.Action.err);
        return .{
            .arena = std.heap.ArenaAllocator.init(testing.allocator),
            .action = action,
            .width = width,
        };
    }

    fn deinit(b: *Bench) void {
        testing.allocator.free(b.action);
        b.frayed.deinit(testing.allocator);
        b.seams.deinit(testing.allocator);
        b.arena.deinit();
    }

    fn put(b: *Bench, state: u32, terminal: u32, act: lalr.Action) void {
        b.action[state * b.width + terminal] = act;
    }

    fn fray(b: *Bench, state: u32, terminal: u32, harm: settle.Frayed.Harm) !void {
        try b.frayed.append(testing.allocator, .{ .state = state, .terminal = terminal, .harm = harm });
    }

    /// A seam that over-permits `terminal` through `arrivals` paths, which is
    /// what makes a frayed cell `open` rather than `alone`.
    fn seam(b: *Bench, state: u32, terminal: u32, arrivals: u32) !void {
        const over_set = try b.arena.allocator().dupe(u32, &.{terminal});
        try b.seams.append(testing.allocator, .{
            .state = state,
            .arrivals = arrivals,
            .over = over_set,
            .stubborn = &.{},
            .lanes = &.{},
        });
    }

    fn tables(b: *const Bench) lalr.Tables {
        return .{
            .arena = std.heap.ArenaAllocator.init(testing.allocator),
            .end = b.width - 1,
            .width = b.width,
            .action = b.action,
            .conflicts = &.{},
            .frayed = b.frayed.items,
            .seams = b.seams.items,
        };
    }
};

test "a byte no terminal matches never reached the table, and not looking is not a proof" {
    var b = try Bench.init(2, 3);
    defer b.deinit();
    var tab = b.tables();
    defer tab.arena.deinit();

    const asked = over(&tab, .{ .stray = .{ .at = 41, .lexable = .nothing } });
    try testing.expectEqual(Owner.lexer, asked.owner);
    try testing.expectEqual(Because.nothing_lexes, asked.because);
    try testing.expect(asked.proven);

    const not = over(&tab, .{ .stray = .{ .at = 41 } });
    try testing.expectEqual(Owner.lexer, not.owner);
    try testing.expect(!not.proven);
}

test "a byte that does lex is a cell question, not a lexer one" {
    var b = try Bench.init(3, 3);
    defer b.deinit();
    // Two states read terminal 1; the one the parse stood in does not.
    b.put(1, 1, lalr.Action.shift(2));
    b.put(2, 1, lalr.Action.shift(1));
    var tab = b.tables();
    defer tab.arena.deinit();

    const f = over(&tab, .{ .stray = .{ .at = 41, .lexable = .{ .terminal = 1 } } });
    try testing.expectEqual(Owner.weave, f.owner);
    // No state folds on it, so argument 3 applies and is the stronger sentence.
    try testing.expectEqual(Because.never_folded, f.because);
    try testing.expectEqual(@as(u32, 2), f.reads);
    try testing.expectEqual(@as(u32, 0), f.folds);
}

test "no state folds the token, so no state dropped a read of it" {
    var b = try Bench.init(4, 3);
    defer b.deinit();
    b.put(1, 1, lalr.Action.shift(2));
    // A fray on a *different* terminal must not be read as this one's.
    try b.fray(1, 2, .read_dropped);
    var tab = b.tables();
    defer tab.arena.deinit();

    const f = over(&tab, .{ .refused = .{ .terminal = 1, .state = 3, .folded = &.{} } });
    try testing.expectEqual(Owner.weave, f.owner);
    try testing.expectEqual(Because.never_folded, f.because);
    try testing.expectEqual(@as(u32, 0), f.dropped);
}

test "a fold on the token elsewhere leaves the empty cell empty under every split" {
    var b = try Bench.init(4, 3);
    defer b.deinit();
    b.put(1, 1, lalr.Action.shift(2));
    b.put(2, 1, lalr.Action.reduce(7));
    var tab = b.tables();
    defer tab.arena.deinit();

    const f = over(&tab, .{ .refused = .{ .terminal = 1, .state = 3, .folded = &.{} } });
    try testing.expectEqual(Owner.weave, f.owner);
    try testing.expectEqual(Because.empty_under_every_split, f.because);
    try testing.expectEqual(@as(u32, 1), f.folds);
}

test "a terminal no state reads is the front end's, not the table's" {
    var b = try Bench.init(4, 3);
    defer b.deinit();
    b.put(2, 1, lalr.Action.reduce(7));
    var tab = b.tables();
    defer tab.arena.deinit();

    const f = over(&tab, .{ .refused = .{ .terminal = 1, .state = 3, .folded = &.{} } });
    try testing.expectEqual(Owner.nowhere, f.owner);
    try testing.expectEqual(Because.never_read, f.because);
}

test "an invented cell on the fold chain is the press's, and says which cell" {
    var b = try Bench.init(6, 3);
    defer b.deinit();
    b.put(1, 1, lalr.Action.shift(2));
    b.put(4, 1, lalr.Action.reduce(9));
    // State 4 folded on the token a merge let it fold on; the refusal surfaces
    // two states later, in 5, which holds nothing.
    try b.fray(4, 1, .read_dropped);
    try b.seam(4, 1, 3);
    var tab = b.tables();
    defer tab.arena.deinit();

    const chain: []const Fold = &.{.{ .state = 4, .prod = 9 }};
    const f = over(&tab, .{ .refused = .{ .terminal = 1, .state = 5, .folded = chain } });
    try testing.expectEqual(Owner.press, f.owner);
    try testing.expectEqual(Because.dropped_upstream, f.because);
    try testing.expectEqual(@as(u32, 4), f.cell.?.state);
    // Three arrivals and not stubborn: an arrival partition removes it.
    try testing.expectEqual(lalr.Floor.Cause.open, f.cause.?);
    try testing.expect(f.proven);
}

test "the same cell off the path is a suspicion, and says so" {
    var b = try Bench.init(6, 3);
    defer b.deinit();
    b.put(1, 1, lalr.Action.shift(2));
    b.put(4, 1, lalr.Action.reduce(9));
    try b.fray(4, 1, .read_dropped);
    var tab = b.tables();
    defer tab.arena.deinit();

    // Chain supplied and it does not pass through state 4: proven weave.
    const elsewhere: []const Fold = &.{.{ .state = 2, .prod = 3 }};
    const known = over(&tab, .{ .refused = .{ .terminal = 1, .state = 5, .folded = elsewhere } });
    try testing.expectEqual(Owner.weave, known.owner);
    try testing.expect(known.proven);

    // No chain at all: press, unproven. The distinction the census needs.
    const blind = over(&tab, .{ .refused = .{ .terminal = 1, .state = 5 } });
    try testing.expectEqual(Owner.press, blind.owner);
    try testing.expectEqual(Because.dropped_elsewhere, blind.because);
    try testing.expect(!blind.proven);
}

test "a wall reads back out of the words the CLI prints for it" {
    var b = g.Builder.init(testing.allocator);
    defer b.deinit();
    const s = try b.intern("S", "S", null);
    const comma = try b.intern(",", ",", .{ .literal = "," });
    try b.addProduction(s, &.{comma}, &.{});
    var gr = try b.finish("t", s, &.{}, &.{});
    defer gr.deinit();

    // The whole line, path prefix and root count and all.
    const one = Wall.read(&gr, "outliner: f.c: unexpected , at 1354 in state 803, 2 roots", .unasked);
    try testing.expectEqual(comma, one.?.refused.terminal);
    try testing.expectEqual(@as(u32, 803), one.?.refused.state);
    try testing.expectEqual(@as(?[]const Fold, null), one.?.refused.folded);

    const two = Wall.read(&gr, "outliner: x.rb: stray byte at 357, 4 roots, mended 3", .nothing);
    try testing.expectEqual(@as(u32, 357), two.?.stray.at);
    try testing.expectEqual(Lexable.nothing, two.?.stray.lexable);

    try testing.expectEqual(Wall.whole, Wall.read(&gr, "outliner: a.c: accepted, 1 root", .unasked).?);
    try testing.expectEqual(Wall.unclosed, Wall.read(&gr, "outliner: a.c: truncated, 3 roots", .unasked).?);

    // A terminal this grammar does not have is not a wall in this grammar, and
    // guessing a column index would read some other terminal's table.
    try testing.expectEqual(
        @as(?Wall, null),
        Wall.read(&gr, "outliner: f.c: unexpected ; at 3 in state 4", .unasked),
    );
    try testing.expectEqual(@as(?Wall, null), Wall.read(&gr, "outliner: f.c: no source fetched", .unasked));
}

test "an accepted parse and a truncated one are not walls" {
    var b = try Bench.init(2, 3);
    defer b.deinit();
    var tab = b.tables();
    defer tab.arena.deinit();

    try testing.expectEqual(Owner.whole, over(&tab, .whole).owner);
    try testing.expectEqual(Owner.unclosed, over(&tab, .unclosed).owner);
}
