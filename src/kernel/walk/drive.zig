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

const testing = std.testing;

/// A hand-built JSON-shaped grammar, small enough to read and big enough to
/// have the one property that matters here: a terminal that is only legal in
/// one place. `text` is `[^"]+`, which asked unconditionally swallows a whole
/// line of structure, so a walk that gets this right is a walk that is really
/// lexing from the parse state.
const Doc = struct {
    f: *Fixture,
    lbrace: press.Symbol = 0,
    rbrace: press.Symbol = 1,
    comma: press.Symbol = 2,
    colon: press.Symbol = 3,
    quote: press.Symbol = 4,
    text: press.Symbol = 5,
    space: press.Symbol = 6,

    const Fixture = struct {
        gpa: std.mem.Allocator,
        gr: press.Grammar,
        built: press.Result,
        scanner: lex.Scanner,
        drive: Drive,

        fn deinit(f: *Fixture) void {
            const gpa = f.gpa;
            f.drive.deinit();
            f.scanner.deinit();
            f.built.tables.deinit();
            f.built.collection.deinit();
            f.gr.deinit();
            gpa.destroy(f);
        }
    };

    fn init(gpa: std.mem.Allocator) !Doc {
        var b = press.Builder.init(gpa);
        defer b.deinit();
        const lbrace = try b.intern("{", "{", .{ .literal = "{" });
        const rbrace = try b.intern("}", "}", .{ .literal = "}" });
        const comma = try b.intern(",", ",", .{ .literal = "," });
        const colon = try b.intern(":", ":", .{ .literal = ":" });
        const quote = try b.intern("\"", "\"", .{ .literal = "\"" });
        const text = try b.intern("text", "text", .{ .regex = "[^\"]+" });
        const space = try b.intern("space", "space", .{ .regex = "[ \t\n]+" });
        const start = try b.intern("$start", "$start", null);
        const obj = try b.intern("object", "object", null);
        const pairs = try b.intern("pairs", "pairs", null);
        const pair = try b.intern("pair", "pair", null);
        const str = try b.intern("string", "string", null);

        try b.addProduction(start, &.{obj}, &.{});
        try b.addProduction(obj, &.{ lbrace, pairs, rbrace }, &.{});
        try b.addProduction(pairs, &.{pair}, &.{});
        try b.addProduction(pairs, &.{ pairs, comma, pair }, &.{});
        try b.addProduction(pair, &.{ str, colon, str }, &.{});
        try b.addProduction(str, &.{ quote, text, quote }, &.{});

        const f = try gpa.create(Doc.Fixture);
        f.gpa = gpa;
        f.gr = try b.finish("doc", start, &.{space}, &.{});
        f.built = try press.tables(gpa, &f.gr);
        f.scanner = (try lex.Scanner.compile(gpa, &f.gr)).?;
        f.drive = try Drive.init(gpa, &f.gr, &f.built.collection, &f.built.tables, &f.scanner);
        return .{ .f = f };
    }

    fn deinit(d: *Doc) void {
        d.f.deinit();
    }
};

fn names(gpa: std.mem.Allocator, gr: *const press.Grammar, tokens: []const Token) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (tokens, 0..) |tok, i| {
        if (i != 0) try out.append(gpa, ' ');
        try out.appendSlice(gpa, gr.nameOf(tok.symbol));
    }
    return out.toOwnedSlice(gpa);
}

test "the walk lexes from the state, so a greedy terminal stays in its own place" {
    var d = try Doc.init(testing.allocator);
    defer d.deinit();

    // `[^"]+` reaches from the first `a` to the closing quote of the file if
    // nobody stops it. What stops it is that after a `"` the state expects
    // `text` and after `text` it expects `"` — and never both at once.
    var trace = try d.f.drive.run("{\"a\" : \"b\", \"c\":\"d\"}");
    defer trace.deinit(testing.allocator);
    try testing.expectEqual(Ending.accepted, trace.ending);

    const got = try names(testing.allocator, &d.f.gr, trace.tokens);
    defer testing.allocator.free(got);
    try testing.expectEqualStrings(
        "{ \" text \" : \" text \" , \" text \" : \" text \" }",
        got,
    );
}

test "an unconditional lex of the same bytes is not the same token stream" {
    var d = try Doc.init(testing.allocator);
    defer d.deinit();

    // The control. Offered the whole slate at every offset, `text` takes every
    // run between quotes — including ` : `, so the colon that holds the pair
    // together is simply gone, eaten by a terminal that was never legal there.
    // Same bytes, same slate, a token stream no parser could use: this is why
    // the segment measurements cannot be run off a context-free lexer.
    var run = try lex.tokenize(&d.f.scanner, testing.allocator, "{\"a\" : \"b\"}", null);
    defer run.deinit(testing.allocator);
    const got = try names(testing.allocator, &d.f.gr, run.tokens);
    defer testing.allocator.free(got);
    try testing.expectEqualStrings("{ \" text \" text \" text \" }", got);
}

test "lexing from the state is sharp about where, and asks again about what" {
    var d = try Doc.init(testing.allocator);
    defer d.deinit();

    // A second string where a `:` belongs. Narrowing the scanner to what the
    // state offers means nothing matches at all, so the failure arrives at the
    // exact offset rather than several states later - sharper about *where*.
    // This test used to end there, and named the second unconditional lex as
    // the thing recovery would want; recovery has since landed, so the walk
    // asks it, and the byte is named instead of being called unreadable.
    //
    // Both walls are still reported, and the difference is load-bearing: a
    // grammar that cannot lex a byte and a table that cannot shift a token
    // are different faults with different repairs.
    var trace = try d.f.drive.run("{\"a\" \"b\"}");
    defer trace.deinit(testing.allocator);
    try testing.expectEqual(@as(u32, 5), trace.ending.unexpected.tok.start);
    // The prefix is kept: `{ " text "` parsed before the offending token.
    try testing.expectEqual(@as(usize, 4), trace.tokens.len);
}

test "input that stops mid-object is truncated, not accepted" {
    var d = try Doc.init(testing.allocator);
    defer d.deinit();

    var trace = try d.f.drive.run("{\"a\":\"b\"");
    defer trace.deinit(testing.allocator);
    try testing.expectEqual(Ending.truncated, trace.ending);
    // `{ " text " : " text "` — everything lexed; the object just never closed.
    try testing.expectEqual(@as(usize, 8), trace.tokens.len);
}
