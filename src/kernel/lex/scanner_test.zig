//! Tests for the terminal scanner (`scanner.zig`).
//!
//! Every case drives a real `grammar.json` through the real importer, because
//! the scanner's whole job is to be correct about what an imported grammar
//! actually says — a hand-built symbol table would test a fiction.

const std = @import("std");
const t = std.testing;
const scanner = @import("scanner.zig");
const import = @import("../../press/import.zig");
const g = @import("../../press/grammar.zig");

const Fixture = struct {
    gr: g.Grammar,
    sc: scanner.Scanner,

    fn init(src: []const u8) !Fixture {
        var gr = try import.treeSitter(t.allocator, src);
        errdefer gr.deinit();
        const sc = (try scanner.Scanner.compile(t.allocator, &gr)) orelse return error.NothingLexable;
        return .{ .gr = gr, .sc = sc };
    }

    fn deinit(f: *Fixture) void {
        f.sc.deinit();
        f.gr.deinit();
    }

    /// The token stream as terminal names, which is what a reader can check.
    fn names(f: *Fixture, src: []const u8) ![]const []const u8 {
        var run = try scanner.tokenize(&f.sc, t.allocator, src, null);
        defer run.deinit(t.allocator);
        try t.expectEqual(@as(?u32, null), run.stray);
        const out = try t.allocator.alloc([]const u8, run.tokens.len);
        for (out, run.tokens) |*n, tok| n.* = f.gr.nameOf(tok.symbol);
        return out;
    }

    fn symbolOf(f: *Fixture, name: []const u8) g.Symbol {
        for (0..f.gr.symbolCount()) |i| {
            if (std.mem.eql(u8, f.gr.nameOf(@intCast(i)), name)) return @intCast(i);
        }
        unreachable;
    }
};

fn expectNames(f: *Fixture, src: []const u8, want: []const []const u8) !void {
    const got = try f.names(src);
    defer t.allocator.free(got);
    try t.expectEqual(want.len, got.len);
    for (want, got) |w, o| try t.expectEqualStrings(w, o);
}

test "scanner: the longest terminal wins, not the first that fits" {
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"REPEAT1","content":{"type":"CHOICE","members":[
        \\   {"type":"SYMBOL","name":"gt"},{"type":"SYMBOL","name":"shr"},{"type":"SYMBOL","name":"shr_eq"}]}},
        \\ "gt":{"type":"STRING","value":">"},
        \\ "shr":{"type":"STRING","value":">>"},
        \\ "shr_eq":{"type":"STRING","value":">>="}}}
    ;
    var f = try Fixture.init(src);
    defer f.deinit();
    try expectNames(&f, ">>=", &.{"shr_eq"});
    try expectNames(&f, ">>>", &.{ "shr", "gt" });
}

test "scanner: a keyword beats a pattern of the same length" {
    // The rule every lexer generator needs and few state outright: `if` and
    // `[a-z]+` both reach two bytes, and the language means the keyword.
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"REPEAT1","content":{"type":"CHOICE","members":[
        \\   {"type":"SYMBOL","name":"kw_if"},{"type":"SYMBOL","name":"ident"}]}},
        \\ "ident":{"type":"PATTERN","value":"[a-z]+"},
        \\ "kw_if":{"type":"STRING","value":"if"}}}
    ;
    var f = try Fixture.init(src);
    defer f.deinit();
    try expectNames(&f, "if", &.{"kw_if"});
    // And it is a tie-break, not a prefix rule: `iffy` is longer as an ident.
    try expectNames(&f, "iffy", &.{"ident"});
}

test "scanner: a keyword written as a pattern still beats the word it is spelled as" {
    // The case declaration order cannot settle and `literal beats regex` does
    // not reach: C writes its type keywords as `token(choice('int','long',…))`,
    // which the press renders as ONE regex terminal. So `int` ties `identifier`
    // with two patterns, and the plain rule picks whichever was declared first
    // — here deliberately the word, so a scanner without the keyword rule
    // returns `ident` and the whole file is a list of names.
    const src =
        \\{"name":"t","word":"ident","rules":{
        \\ "doc":{"type":"REPEAT1","content":{"type":"CHOICE","members":[
        \\   {"type":"SYMBOL","name":"ident"},{"type":"SYMBOL","name":"prim"},
        \\   {"type":"SYMBOL","name":"sized"}]}},
        \\ "ident":{"type":"PATTERN","value":"[a-z]+"},
        \\ "prim":{"type":"TOKEN","content":{"type":"CHOICE","members":[
        \\   {"type":"STRING","value":"int"},{"type":"STRING","value":"long"}]}},
        \\ "sized":{"type":"TOKEN","content":{"type":"CHOICE","members":[
        \\   {"type":"STRING","value":"int"},{"type":"STRING","value":"short"}]}}},
        \\ "extras":[{"type":"PATTERN","value":"\\s"}]}
    ;
    var f = try Fixture.init(src);
    defer f.deinit();
    try t.expect(f.symbolOf("ident") < f.symbolOf("prim"));

    try expectNames(&f, "int", &.{"prim"});
    try expectNames(&f, "long", &.{"prim"});
    // Still a tie-break and not a prefix rule: longest match comes first, so a
    // name that merely starts with a keyword is a name.
    try expectNames(&f, "integer", &.{"ident"});
    // And the rule only ever removes the word from the running: `int` also ties
    // `sized`, and which of the two real keywords wins is still declaration
    // order, because that is the answer a grammar author can predict.
    try t.expect(f.symbolOf("prim") < f.symbolOf("sized"));
    try expectNames(&f, "int long short", &.{ "prim", "prim", "sized" });
}

test "scanner: an external this lexer can spell joins the slate under its own name" {
    // `string_content` is one of the four kinds that block the corpus, and it
    // is an external for a reason that has nothing to do with the bytes: it is
    // legal only between quotes, and a tree-sitter grammar cannot say that.
    // Lexing here is state-directed, so the state says it — and `outside.zig`
    // supplies the spelling the C scanner would have recognized.
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"SEQ","members":[
        \\   {"type":"SYMBOL","name":"open"},{"type":"SYMBOL","name":"string_content"},
        \\   {"type":"SYMBOL","name":"string_close"}]},
        \\ "open":{"type":"STRING","value":"\""}},
        \\ "externals":[{"type":"SYMBOL","name":"string_content"},
        \\   {"type":"SYMBOL","name":"string_close"}]}
    ;
    var f = try Fixture.init(src);
    defer f.deinit();

    // Neither is blind any more, and both answer to the grammar's own name —
    // inventing one would break every `highlights.scm` in the world.
    try t.expectEqual(@as(usize, 0), f.sc.blind.len);
    try t.expect(f.sc.provided.isSet(f.symbolOf("string_content")));
    try t.expect(f.sc.provided.isSet(f.symbolOf("string_close")));

    // Driven the way a parser drives it. Unconditionally the closing quote is
    // ambiguous — `open` is the same byte and a literal outranks a pattern — so
    // the state is what tells the two apart, which is the same context the C
    // scanner was written to carry.
    var inside = try f.sc.expecting(t.allocator);
    defer inside.deinit(t.allocator);
    inside.admit(&f.sc, f.symbolOf("string_content"));
    inside.admit(&f.sc, f.symbolOf("string_close"));

    const source = "\"a b\"";
    try expectStep(&f, source, 0, null, "open", 1);
    // The body reaches the whole span including the space: it is immediate, so
    // the extras never got a chance to eat the leading byte. That is not
    // decoration — a space inside a string belongs to the string.
    try expectStep(&f, source, 1, &inside, "string_content", 3);
    try expectStep(&f, source, 4, &inside, "string_close", 1);
}

fn expectStep(
    f: *Fixture,
    src: []const u8,
    at: u32,
    expected: ?*const scanner.Scanner.Expected,
    name: []const u8,
    len: u32,
) !void {
    switch (f.sc.next(src, at, expected)) {
        .token => |tok| {
            try t.expectEqualStrings(name, f.gr.nameOf(tok.symbol));
            try t.expectEqual(at, tok.start);
            try t.expectEqual(len, tok.len);
        },
        else => return error.ExpectedAToken,
    }
}

test "scanner: a stand-in for an external is never treated as a keyword" {
    // The one way the keyword rule could do damage. bash's `variable_name` is
    // a strict subset of its `word`, and it is emphatically not a keyword of
    // it: `declare rows` is two words, `rows=1` is an assignment, and only the
    // parse state knows which. tree-sitter's keyword pass never sees an
    // external at all, so neither does ours — without that exclusion every
    // bare word in the file would come back as an assignment target.
    const src =
        \\{"name":"t","word":"word","rules":{
        \\ "doc":{"type":"REPEAT1","content":{"type":"CHOICE","members":[
        \\   {"type":"SYMBOL","name":"word"},{"type":"SYMBOL","name":"variable_name"}]}},
        \\ "word":{"type":"PATTERN","value":"[a-zA-Z_][a-zA-Z0-9_]*"}},
        \\ "externals":[{"type":"SYMBOL","name":"variable_name"}]}
    ;
    var f = try Fixture.init(src);
    defer f.deinit();
    try t.expect(f.sc.provided.isSet(f.symbolOf("variable_name")));

    // Both reach the same four bytes and the word keeps the token.
    try expectNames(&f, "rows", &.{"word"});

    // A state that wants only the assignment target still gets it, which is
    // the whole point: the exclusion costs the stand-in nothing except the
    // right to win a tie it was never entitled to.
    var expected = try f.sc.expecting(t.allocator);
    defer expected.deinit(t.allocator);
    expected.admit(&f.sc, f.symbolOf("variable_name"));
    switch (f.sc.next("rows", 0, &expected)) {
        .token => |tok| try t.expectEqualStrings("variable_name", f.gr.nameOf(tok.symbol)),
        else => return error.ExpectedAToken,
    }
}

test "scanner: an extra never wins a tie against a terminal that carries meaning" {
    // ruby, exactly. Its newline ends a statement — `_line_break`, external
    // because only the state knows whether one may end here — while its
    // `extras` still carry a bare `\s` that matches the same one byte. Rank the
    // extra level with the terminal and it eats every significant newline in
    // the file: `attr_reader :rows, :tags` then a blank line, and the `def`
    // that follows arrives as a stray byte because the statement never ended.
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"REPEAT1","content":{"type":"CHOICE","members":[
        \\   {"type":"SYMBOL","name":"word"},{"type":"SYMBOL","name":"_line_break"}]}},
        \\ "word":{"type":"PATTERN","value":"[a-z]+"}},
        \\ "externals":[{"type":"SYMBOL","name":"_line_break"}],
        \\ "extras":[{"type":"PATTERN","value":"\\s"}]}
    ;
    var f = try Fixture.init(src);
    defer f.deinit();
    try t.expect(f.sc.provided.isSet(f.symbolOf("_line_break")));

    // A stand-in ranks below the grammar's own spellings and still above an
    // extra, so the newline survives and the space around it does not.
    try expectNames(&f, "a \n b", &.{ "word", "_line_break", "word" });
}

test "scanner: extras are skipped, and the tokens keep their true offsets" {
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"REPEAT1","content":{"type":"SYMBOL","name":"word"}},
        \\ "word":{"type":"PATTERN","value":"[a-z]+"},
        \\ "comment":{"type":"TOKEN","content":{"type":"SEQ","members":[
        \\   {"type":"STRING","value":"//"},
        \\   {"type":"REPEAT","content":{"type":"PATTERN","value":"[^\n]"}}]}}},
        \\ "extras":[{"type":"PATTERN","value":"\\s"},{"type":"SYMBOL","name":"comment"}]}
    ;
    var f = try Fixture.init(src);
    defer f.deinit();

    var run = try scanner.tokenize(&f.sc, t.allocator, "  a // skip me\n  bb", null);
    defer run.deinit(t.allocator);
    try t.expectEqual(@as(?u32, null), run.stray);
    try t.expectEqual(@as(usize, 2), run.tokens.len);
    try t.expectEqual(@as(u32, 2), run.tokens[0].start);
    try t.expectEqual(@as(u32, 1), run.tokens[0].len);
    // The second token's offset is past the comment, which is the whole point
    // of skipping rather than deleting: a span still points into the source.
    try t.expectEqual(@as(u32, 17), run.tokens[1].start);
    try t.expectEqual(@as(u32, 2), run.tokens[1].len);
}

/// A grammar with both shapes of extra: a comment rule the author named, and
/// an anonymous whitespace pattern nobody wrote a name for.
const commented =
    \\{"name":"t","rules":{
    \\ "doc":{"type":"REPEAT1","content":{"type":"SYMBOL","name":"word"}},
    \\ "word":{"type":"PATTERN","value":"[a-z]+"},
    \\ "comment":{"type":"TOKEN","content":{"type":"SEQ","members":[
    \\   {"type":"STRING","value":"//"},
    \\   {"type":"REPEAT","content":{"type":"PATTERN","value":"[^\n]"}}]}}},
    \\ "extras":[{"type":"PATTERN","value":"\\s"},{"type":"SYMBOL","name":"comment"}]}
;

test "scanner: the extras a walk steps over survive it, spans intact" {
    // What the tree needs and the parse does not. A comment is a node in
    // tree-sitter's output, and the skip is the only place its bytes are ever
    // seen — by the time a token comes back, they are behind it.
    var f = try Fixture.init(commented);
    defer f.deinit();

    // Only the named extra is kept. Whitespace interns as a symbol the author
    // never wrote, emits no node, and so is not the caller's business.
    try t.expectEqual(@as(usize, 1), f.sc.kept.count());
    try t.expect(f.sc.kept.isSet(f.symbolOf("comment")));
    try t.expect(f.sc.skipped.isSet(f.symbolOf("comment")));

    const src = "  a // one\n // two\n bb  // trailing\n";
    var keep: std.ArrayList(scanner.Token) = .empty;
    defer keep.deinit(t.allocator);

    // Leading whitespace only: nothing to keep.
    const first = try f.sc.nextKeeping(t.allocator, src, 0, null, &keep);
    try t.expectEqual(@as(u32, 2), first.token.start);
    try t.expectEqual(@as(usize, 0), keep.items.len);

    // Two comments and three runs of whitespace between the two words. Both
    // comments come back, in source order, and the whitespace does not.
    const second = try f.sc.nextKeeping(t.allocator, src, first.token.end(), null, &keep);
    try t.expectEqual(@as(u32, 20), second.token.start);
    try t.expectEqual(@as(usize, 2), keep.items.len);
    try t.expectEqualStrings("// one", src[keep.items[0].start..keep.items[0].end()]);
    try t.expectEqualStrings("// two", src[keep.items[1].start..keep.items[1].end()]);

    // And a comment with no token after it is still a comment. A trailing one
    // rides the step that ends the input, which is the only step it can ride.
    try t.expectEqual(scanner.Step.end, try f.sc.nextKeeping(t.allocator, src, second.token.end(), null, &keep));
    try t.expectEqual(@as(usize, 3), keep.items.len);
    try t.expectEqualStrings("// trailing", src[keep.items[2].start..keep.items[2].end()]);
}

test "scanner: keeping the extras changes nothing about the token stream" {
    // `next` is what the parser drives, and it has to be the same walk. The
    // two share their body for that reason; this is the assertion that the
    // sharing held.
    var f = try Fixture.init(commented);
    defer f.deinit();
    try expectSameWalk(&f, "  a // one\n // two\n bb  // trailing\n");
    try expectSameWalk(&f, "");
    try expectSameWalk(&f, "// nothing but a comment");
    // Including where the walk gives up: a stray must stay a stray, at the
    // same offset, whether or not anybody is collecting comments.
    try expectSameWalk(&f, "a // fine\n ? b");
}

fn expectSameWalk(f: *Fixture, src: []const u8) !void {
    var keep: std.ArrayList(scanner.Token) = .empty;
    defer keep.deinit(t.allocator);
    var at: u32 = 0;
    while (true) {
        const plain = f.sc.next(src, at, null);
        const kept = try f.sc.nextKeeping(t.allocator, src, at, null, &keep);
        try t.expectEqual(std.meta.activeTag(plain), std.meta.activeTag(kept));
        switch (plain) {
            .token => |tok| {
                try t.expectEqual(tok.symbol, kept.token.symbol);
                try t.expectEqual(tok.start, kept.token.start);
                try t.expectEqual(tok.len, kept.token.len);
                at = tok.end();
            },
            .stray => |off| return t.expectEqual(off, kept.stray),
            .end => return,
        }
    }
}

test "scanner: a byte no terminal can begin at stops the run and says where" {
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"REPEAT1","content":{"type":"SYMBOL","name":"word"}},
        \\ "word":{"type":"PATTERN","value":"[a-z]+"}}}
    ;
    var f = try Fixture.init(src);
    defer f.deinit();

    var run = try scanner.tokenize(&f.sc, t.allocator, "abc?def", null);
    defer run.deinit(t.allocator);
    try t.expectEqual(@as(usize, 1), run.tokens.len);
    try t.expectEqual(@as(?u32, 3), run.stray);
}

test "scanner: an external scanner's terminal is named blind, not guessed at" {
    const src =
        \\{"name":"t","rules":{"doc":{"type":"SEQ","members":[
        \\  {"type":"SYMBOL","name":"indent"},{"type":"SYMBOL","name":"word"}]},
        \\ "word":{"type":"PATTERN","value":"[a-z]+"}},
        \\ "externals":[{"type":"SYMBOL","name":"indent"}]}
    ;
    var f = try Fixture.init(src);
    defer f.deinit();

    try t.expectEqual(@as(usize, 1), f.sc.blind.len);
    try t.expectEqualStrings("indent", f.gr.nameOf(f.sc.blind[0]));
    // And the rest of the grammar still lexes — a blind terminal costs its own
    // recognition and nothing else.
    try expectNames(&f, "abc", &.{"word"});
}

test "scanner: a refused pattern leaves a hole, it does not renumber its neighbors" {
    // The bug this exists for: a munch reports the ordinals it was handed and
    // never renumbers around a refusal, so a scanner that compacted its own
    // ordinal->symbol map would shift every terminal after the refused one onto
    // its neighbor's name. Nothing crashes; the lexer just calls `}` an
    // `interface` forever. `back` is a backreference, which the linear engine
    // declines, and it sits FIRST so every later terminal would shift.
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"REPEAT1","content":{"type":"CHOICE","members":[
        \\   {"type":"SYMBOL","name":"back"},{"type":"SYMBOL","name":"aaa"},
        \\   {"type":"SYMBOL","name":"bbb"},{"type":"SYMBOL","name":"ccc"}]}},
        \\ "back":{"type":"PATTERN","value":"(a)\\1"},
        \\ "aaa":{"type":"STRING","value":"@"},
        \\ "bbb":{"type":"STRING","value":"#"},
        \\ "ccc":{"type":"STRING","value":"%"}}}
    ;
    var f = try Fixture.init(src);
    defer f.deinit();

    try t.expectEqual(@as(usize, 1), f.sc.blind.len);
    try t.expectEqualStrings("back", f.gr.nameOf(f.sc.blind[0]));
    try t.expectEqual(@as(usize, 3), f.sc.recognized());

    // Each of the three still answers to its own name.
    try expectNames(&f, "@#%", &.{ "aaa", "bbb", "ccc" });

    // And a blind terminal has no seat, so admitting it is a no-op rather than
    // a bit landing on whichever pattern inherited its ordinal.
    var expected = try f.sc.expecting(t.allocator);
    defer expected.deinit(t.allocator);
    expected.admit(&f.sc, f.symbolOf("back"));
    try t.expectEqual(scanner.Step{ .stray = 0 }, f.sc.next("@", 0, &expected));
}

test "scanner: a grammar of nothing but externals is not lexable at all" {
    const src =
        \\{"name":"t","rules":{"doc":{"type":"SYMBOL","name":"indent"}},
        \\ "externals":[{"type":"SYMBOL","name":"indent"}]}
    ;
    var gr = try import.treeSitter(t.allocator, src);
    defer gr.deinit();
    try t.expectEqual(@as(?scanner.Scanner, null), try scanner.Scanner.compile(t.allocator, &gr));
}

test "scanner: what a parse state expects changes which token is longest" {
    // The mechanism the real grammars need, on a grammar small enough to read.
    // `body` is JSON's `string_content` in miniature: legal only inside quotes,
    // and ruinous everywhere else.
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"REPEAT1","content":{"type":"CHOICE","members":[
        \\   {"type":"SYMBOL","name":"quote"},{"type":"SYMBOL","name":"colon"},
        \\   {"type":"SYMBOL","name":"body"}]}},
        \\ "quote":{"type":"STRING","value":"\""},
        \\ "colon":{"type":"STRING","value":":"},
        \\ "body":{"type":"PATTERN","value":"[^\"]+"}}}
    ;
    var f = try Fixture.init(src);
    defer f.deinit();

    // Unconditional, `body` eats the colon and everything after it.
    try expectNames(&f, "\":a:b\"", &.{ "quote", "body", "quote" });

    // Told that only structure is legal here, the same offset yields the colon.
    var expected = try f.sc.expecting(t.allocator);
    defer expected.deinit(t.allocator);
    expected.admit(&f.sc, f.symbolOf("quote"));
    expected.admit(&f.sc, f.symbolOf("colon"));

    var run = try scanner.tokenize(&f.sc, t.allocator, "\":a:b\"", &expected);
    defer run.deinit(t.allocator);
    // `"` then `:` — and then a stray at `a`, because `body` is genuinely not
    // permitted and the scanner says so instead of inventing a token.
    try t.expectEqual(@as(usize, 2), run.tokens.len);
    try t.expectEqualStrings("quote", f.gr.nameOf(run.tokens[0].symbol));
    try t.expectEqualStrings("colon", f.gr.nameOf(run.tokens[1].symbol));
    try t.expectEqual(@as(?u32, 2), run.stray);
}

test "scanner: a real grammar's context-free terminals are the trap, measured" {
    const grammar = @embedFile("json_grammar");
    var f = try Fixture.init(grammar);
    defer f.deinit();

    // Every terminal in tree-sitter-json is lexable — the difficulty here is
    // not a missing scanner, which makes it the cleanest demonstration that
    // difficulty and blindness are different problems.
    try t.expectEqual(@as(usize, 0), f.sc.blind.len);

    const source =
        \\{"a": [1, true, null], "b": "x"}
    ;

    // Asked unconditionally, `string_content` (`[^\"\n]+`) is legal nowhere in
    // particular and therefore longest almost everywhere: it takes
    // `: [1, true, null], ` in one bite. Thirteen tokens where a parser needs
    // twenty-one. This is pinned, not tolerated — it is the exact number that
    // must change when the cursor starts supplying the valid-terminal set, and
    // a silent improvement would be as suspicious as a silent regression.
    var loose = try scanner.tokenize(&f.sc, t.allocator, source, null);
    defer loose.deinit(t.allocator);
    try t.expectEqual(@as(?u32, null), loose.stray);
    try t.expectEqual(@as(usize, 13), loose.tokens.len);
    try t.expectEqualStrings("string_content", f.gr.nameOf(loose.tokens[4].symbol));
    try t.expectEqualStrings(": [1, true, null], ", source[loose.tokens[4].start..loose.tokens[4].end()]);

    // At that one offset, tell the scanner what a parse state sitting outside a
    // string would tell it — everything except `string_content` — and the
    // colon comes back. One call, on the real grammar, with no invented state
    // machine standing in for the parser: nineteen bytes become one.
    //
    // Deliberately not asserted here: a whole re-tokenization under that set.
    // `string_content` is illegal outside a string and REQUIRED inside one, so
    // a single static set cannot lex this file — only a per-state set can, and
    // producing one is the cursor's job, not this test's.
    var outside = try f.sc.expecting(t.allocator);
    defer outside.deinit(t.allocator);
    for (0..f.gr.terminal_count) |i| {
        const sym: g.Symbol = @intCast(i);
        if (!std.mem.eql(u8, f.gr.nameOf(sym), "string_content")) outside.admit(&f.sc, sym);
    }

    const at = loose.tokens[4].start;
    switch (f.sc.next(source, at, &outside)) {
        .token => |tok| {
            try t.expectEqualStrings(":", f.gr.nameOf(tok.symbol));
            try t.expectEqual(@as(u32, 1), tok.len);
            try t.expectEqual(at, tok.start);
        },
        else => return error.ExpectedAToken,
    }
}
