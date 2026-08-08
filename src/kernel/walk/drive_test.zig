//! What `drive.zig` claims, checked against a grammar built for the claim.
//!
//! Lexing from the parse state is not an optimization here, it is the whole
//! difference: the fixture's `text` terminal is `[^"]+`, which asked
//! unconditionally eats every byte to the closing quote of the file. So the
//! four tests below are one question asked four ways - does the walk ask the
//! state what is legal *here*, or does it ask the scanner what matches *next*.
//!
//! The grammar is hand-built rather than imported so the property is visible in
//! the file that depends on it, and so the test does not fail when a corpus
//! grammar changes for reasons of its own.

const std = @import("std");
const press = @import("../../press/press.zig");
const lex = @import("../lex/scanner.zig");
const drive = @import("drive.zig");

const Drive = drive.Drive;
const Token = drive.Token;
const Ending = drive.Ending;
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
