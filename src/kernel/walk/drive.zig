//! The ordinary parse, kept on purpose.
//!
//! Nothing in joints's pitch is about walking a file left to right — that is
//! the thing the monoid is supposed to replace. This file exists anyway, for
//! two reasons that are the same reason.
//!
//! It is the **oracle**. Every claim about composing segments is a claim that
//! the product equals the walk, and a claim like that is worth exactly as much
//! as the walk you can check it against.
//!
//! It is the **token stream**. Real terminals are context-dependent — a JSON
//! grammar's `string_content` is `[^\\"\n]+`, which is legal only between
//! quotes and, offered unconditionally, eats the rest of the line. So the only
//! way to get a true token stream out of a real grammar is to lex from the
//! parse state, which means the lexer needs a parser walking beside it. Every
//! measurement of segments has to start from a stream that is actually right,
//! and this is where one comes from.
//!
//! The loop is the textbook one and is meant to stay that way. Its value is in
//! being obviously correct, not in being fast.

const std = @import("std");
const press = @import("../../press/press.zig");
const lex = @import("../lex/scanner.zig");

pub const Token = lex.Token;

/// Why the walk stopped. Only `accepted` is a whole parse; the rest each name
/// the exact byte or token that ended it, because a parser that reports
/// "failed" is a parser you cannot debug a grammar with.
pub const Ending = union(enum) {
    accepted,
    /// No terminal *in this grammar* begins at this offset. A byte some state
    /// merely has no action for is `unexpected`, and the two are different
    /// walls: one is the lexer's and one is the table's.
    stray: u32,
    /// A token the state has no action for. It lexed; it just cannot go here.
    /// The state comes with it: "`=` is unexpected" is a complaint, "state 803
    /// has no `=`, and here is what it does have" is a diagnosis.
    ///
    /// So does the chain of folds that ran before the table gave up, because a
    /// rejection almost never happens where it starts: the token drives
    /// reductions until one lands somewhere the token is illegal, and *which
    /// reduction went wrong* is the only question worth asking. Borrowed from
    /// the `Drive` and valid until the next run.
    unexpected: struct { tok: Token, state: u32, folded: []const Fold },
    /// Input ended before the start symbol did.
    truncated,
};

/// One reduction the refused token drove, and where it stood to take it.
pub const Fold = struct { state: u32, prod: u32 };

pub const Trace = struct {
    tokens: []const Token,
    /// The state the walk stood in when it read each token — before the folds
    /// that token triggered, which is exactly what a segment starting there
    /// would be entered in. Parallel to `tokens`, and the only reason anything
    /// else can be checked against this one.
    enter: []const u32,
    ending: Ending,

    pub fn deinit(t: *Trace, gpa: std.mem.Allocator) void {
        gpa.free(t.tokens);
        gpa.free(t.enter);
        t.* = undefined;
    }
};

pub const Drive = struct {
    gpa: std.mem.Allocator,
    gr: *const press.Grammar,
    c: *const press.Collection,
    t: *const press.Tables,
    scanner: *lex.Scanner,

    /// The LR state stack. Symbols are not kept: nothing here needs them, and
    /// the segment machinery that does keeps its own.
    states: std.ArrayList(u32),
    /// Refilled once per token from the current state's action row.
    expected: lex.Scanner.Expected,
    /// The reductions the current token drove before it was shifted or
    /// refused. Cleared per token; only read when the token is refused.
    folded: std.ArrayList(Fold),

    pub fn init(
        gpa: std.mem.Allocator,
        gr: *const press.Grammar,
        c: *const press.Collection,
        t: *const press.Tables,
        scanner: *lex.Scanner,
    ) !Drive {
        return .{
            .gpa = gpa,
            .gr = gr,
            .c = c,
            .t = t,
            .scanner = scanner,
            .states = .empty,
            .expected = try scanner.expecting(gpa),
            .folded = .empty,
        };
    }

    pub fn deinit(d: *Drive) void {
        d.states.deinit(d.gpa);
        d.expected.deinit(d.gpa);
        d.folded.deinit(d.gpa);
        d.* = undefined;
    }

    /// Parse `bytes`, returning the tokens actually consumed and how it ended.
    /// A failed parse still hands back its prefix: for grammar work that prefix
    /// is the whole diagnosis.
    pub fn run(d: *Drive, bytes: []const u8) !Trace {
        d.states.clearRetainingCapacity();
        try d.states.append(d.gpa, 0);

        var tokens: std.ArrayList(Token) = .empty;
        errdefer tokens.deinit(d.gpa);
        var enter: std.ArrayList(u32) = .empty;
        errdefer enter.deinit(d.gpa);

        var at: u32 = 0;
        while (true) {
            d.offer();
            const here = d.states.getLast();
            switch (d.scanner.next(bytes, at, &d.expected)) {
                .end => return d.stop(&tokens, &enter, if (try d.close()) .accepted else .truncated),
                .stray => |off| if (d.blame(bytes, off)) |tok| {
                    if (!try d.absorb(tok.symbol)) {
                        const stuck = d.states.getLast();
                        return d.stop(&tokens, &enter, .{ .unexpected = .{
                            .tok = tok,
                            .state = stuck,
                            .folded = d.folded.items,
                        } });
                    }
                    try tokens.append(d.gpa, tok);
                    try enter.append(d.gpa, here);
                    at = tok.end();
                } else return d.stop(&tokens, &enter, .{ .stray = off }),
                .token => |tok| {
                    if (!try d.absorb(tok.symbol)) {
                        // The state that refused it, which is where the folds
                        // ran out — not `here`, which is where they started.
                        const stuck = d.states.getLast();
                        return d.stop(&tokens, &enter, .{ .unexpected = .{
                            .tok = tok,
                            .state = stuck,
                            .folded = d.folded.items,
                        } });
                    }
                    try tokens.append(d.gpa, tok);
                    try enter.append(d.gpa, here);
                    at = tok.end();
                },
            }
        }
    }

    fn stop(
        d: *Drive,
        tokens: *std.ArrayList(Token),
        enter: *std.ArrayList(u32),
        why: Ending,
    ) !Trace {
        return .{
            .tokens = try tokens.toOwnedSlice(d.gpa),
            .enter = try enter.toOwnedSlice(d.gpa),
            .ending = why,
        };
    }

    /// The terminals this state has any action for — tree-sitter's valid-symbol
    /// set, read straight off the table instead of maintained beside it. The
    /// reduce entries are what make it right: a state that would fold before
    /// shifting still accepts everything the fold leads to.
    fn offer(d: *Drive) void {
        d.expected.clear(d.scanner);
        const here = d.states.getLast();
        for (0..d.gr.terminal_count) |sym| {
            if (d.t.at(here, @intCast(sym)).kind != .err) d.expected.admit(d.scanner, @intCast(sym));
        }
    }

    /// Ask again with the narrowing stood down: a byte no *state* admits a
    /// terminal for is not the same thing as a byte the *grammar* cannot read,
    /// and only the second is a stray one. Null is the genuine article.
    ///
    /// Asked at the offset the narrowed attempt failed at, not at the parse's
    /// own: the scanner passes over the layout between them, and a wide slate
    /// handed the earlier offset lets whichever terminal reaches furthest name
    /// the layout rather than the token that is really there.
    fn blame(d: *Drive, bytes: []const u8, at: u32) ?Token {
        d.expected.clear(d.scanner);
        for (0..d.gr.terminal_count) |sym| d.expected.admit(d.scanner, @intCast(sym));
        return switch (d.scanner.next(bytes, at, &d.expected)) {
            .token => |tok| tok,
            else => null,
        };
    }

    /// Fold until the token can be shifted, then shift it. False means no
    /// sequence of folds makes this token legal here.
    fn absorb(d: *Drive, sym: press.Symbol) !bool {
        d.folded.clearRetainingCapacity();
        while (true) {
            const act = d.t.at(d.states.getLast(), sym);
            switch (act.kind) {
                .err => return false,
                .shift => {
                    try d.states.append(d.gpa, act.value);
                    return true;
                },
                .reduce => {
                    try d.folded.append(d.gpa, .{ .state = d.states.getLast(), .prod = act.value });
                    if (!try d.fold(act.value)) return false;
                },
                // Accept is only in the end column, which `absorb` is never
                // called with; treat it as "nothing further to shift".
                .accept => return true,
            }
        }
    }

    fn fold(d: *Drive, prod: u32) !bool {
        const p = d.gr.productions[prod];
        if (d.states.items.len <= p.rhs.len) return false;
        d.states.shrinkRetainingCapacity(d.states.items.len - p.rhs.len);
        const to = d.c.goto(d.states.getLast(), p.lhs) orelse return false;
        try d.states.append(d.gpa, to);
        return true;
    }

    /// Drive the end-of-input column until the automaton accepts or refuses.
    fn close(d: *Drive) !bool {
        while (true) {
            const act = d.t.at(d.states.getLast(), d.t.end);
            switch (act.kind) {
                .accept => return true,
                .reduce => {
                    try d.folded.append(d.gpa, .{ .state = d.states.getLast(), .prod = act.value });
                    if (!try d.fold(act.value)) return false;
                },
                .err, .shift => return false,
            }
        }
    }
};
