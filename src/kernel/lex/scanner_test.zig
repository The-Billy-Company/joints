//! Tests for the terminal scanner (`scanner.zig`).
//!
//! Every case drives a real `grammar.json` through the real importer, because
//! the scanner's whole job is to be correct about what an imported grammar
//! actually says - a hand-built symbol table would test a fiction.

const std = @import("std");
const t = std.testing;
const scanner = @import("scanner.zig");
const outside = @import("outside.zig");
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
    // - here deliberately the word, so a scanner without the keyword rule
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
    // Lexing here is state-directed, so the state says it - and `outside.zig`
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

    // Neither is blind any more, and both answer to the grammar's own name -
    // inventing one would break every `highlights.scm` in the world.
    try t.expectEqual(@as(usize, 0), f.sc.blind.len);
    try t.expect(f.sc.provided.isSet(f.symbolOf("string_content")));
    try t.expect(f.sc.provided.isSet(f.symbolOf("string_close")));

    // Driven the way a parser drives it. Unconditionally the closing quote is
    // ambiguous - `open` is the same byte and a literal outranks a pattern - so
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
    // decoration - a space inside a string belongs to the string.
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
    // external at all, so neither does ours - without that exclusion every
    // bare word in the file would come back as an assignment target.
    const src =
        \\{"name":"t","word":"word","rules":{
        \\ "doc":{"type":"REPEAT1","content":{"type":"CHOICE","members":[
        \\   {"type":"SYMBOL","name":"word"},{"type":"SYMBOL","name":"variable_name"}]}},
        \\ "word":{"type":"PATTERN","value":"[a-zA-Z_][a-zA-Z0-9_]*"}},
        \\ "externals":[{"type":"SYMBOL","name":"variable_name"},
        \\   {"type":"SYMBOL","name":"file_descriptor"},
        \\   {"type":"SYMBOL","name":"test_operator"}]}
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
    // ruby, exactly. Its newline ends a statement - `_line_break`, external
    // because only the state knows whether one may end here - while its
    // `extras` still carry a bare `\s` that matches the same one byte. Rank the
    // extra level with the terminal and it eats every significant newline in
    // the file: `attr_reader :rows, :tags` then a blank line, and the `def`
    // that follows arrives as a stray byte because the statement never ended.
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"REPEAT1","content":{"type":"CHOICE","members":[
        \\   {"type":"SYMBOL","name":"word"},{"type":"SYMBOL","name":"_line_break"}]}},
        \\ "word":{"type":"PATTERN","value":"[a-z]+"}},
        \\ "externals":[{"type":"SYMBOL","name":"_line_break"},
        \\   {"type":"SYMBOL","name":"simple_symbol"},
        \\   {"type":"SYMBOL","name":"hash_key_symbol"}],
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
    // seen - by the time a token comes back, they are behind it.
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
    // And the rest of the grammar still lexes - a blind terminal costs its own
    // recognition and nothing else.
    try expectNames(&f, "abc", &.{"word"});
}

test "scanner: an extra spelled as a rule is named, not passed over" {
    // lua's shape, reduced. `comment` is an extra and a SEQ around `--`, so it
    // is a nonterminal; the skip loop can only seat terminals. Passing over it
    // silently is what left lua and julia straying on the first comment byte of
    // every file, at byte zero, with `blind` empty and nothing to read.
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"REPEAT1","content":{"type":"SYMBOL","name":"word"}},
        \\ "word":{"type":"PATTERN","value":"[a-z]+"},
        \\ "comment":{"type":"SEQ","members":[
        \\   {"type":"STRING","value":"--"},{"type":"PATTERN","value":"[^\n]*"}]},
        \\ "space":{"type":"PATTERN","value":"\\s"}},
        \\ "extras":[{"type":"SYMBOL","name":"comment"},{"type":"SYMBOL","name":"space"}]}
    ;
    var f = try Fixture.init(src);
    defer f.deinit();

    // Nothing is blind: every terminal here lexes. The incompleteness is of the
    // other kind, and it has to be reachable or it is not reported at all.
    try t.expectEqual(@as(usize, 0), f.sc.blind.len);
    try t.expectEqual(@as(usize, 1), f.sc.unskippable.len);
    try t.expectEqualStrings("comment", f.gr.nameOf(f.sc.unskippable[0]));

    // The terminal extra beside it is unaffected - one rule extra does not cost
    // the grammar its whitespace skip.
    //
    // Read off the scanner rather than through a lex, and the reason is worth
    // keeping: `names` tokenizes with no expected set, so it offers the whole
    // slate, and the slate contains `[^\n]*`. That terminal exists only as a
    // member of the `comment` rule the parser can never enter, and it
    // out-matches `word` at every offset - "aa bb" comes back as one token. The
    // shadowing is real and is its own finding; it is not what this test pins,
    // and a lex here would fail for a reason that has nothing to do with extras.
    try t.expect(f.sc.skipped.isSet(f.symbolOf("space")));
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

    // `back` is the engine's refusal, not an unanswered external, so it lands in
    // `declined`; `blind` is empty because this grammar declares no external at
    // all. Two populations, two fields, and this grammar has one of each.
    try t.expectEqual(@as(usize, 0), f.sc.blind.len);
    try t.expectEqual(@as(usize, 1), f.sc.declined.len);
    try t.expectEqualStrings("back", f.gr.nameOf(f.sc.declined[0]));
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
    // `"` then `:` - and then a stray at `a`, because `body` is genuinely not
    // permitted and the scanner says so instead of inventing a token.
    try t.expectEqual(@as(usize, 2), run.tokens.len);
    try t.expectEqualStrings("quote", f.gr.nameOf(run.tokens[0].symbol));
    try t.expectEqualStrings("colon", f.gr.nameOf(run.tokens[1].symbol));
    try t.expectEqual(@as(?u32, 2), run.stray);
}

/// A grammar shaped like Python's layout: the three externals by the names
/// tree-sitter-python gives them, plus the brackets its scanner reads.
const layout_grammar =
    \\{"name":"t","rules":{
    \\ "doc":{"type":"REPEAT1","content":{"type":"CHOICE","members":[
    \\   {"type":"SYMBOL","name":"_newline"},{"type":"SYMBOL","name":"_indent"},
    \\   {"type":"SYMBOL","name":"_dedent"},{"type":"SYMBOL","name":"name"},
    \\   {"type":"STRING","value":")"}]}},
    \\ "name":{"type":"PATTERN","value":"[a-z]+"}},
    \\ "extras":[{"type":"PATTERN","value":"[ \\t\\n]"}],
    \\ "externals":[{"type":"SYMBOL","name":"_newline"},{"type":"SYMBOL","name":"_indent"},
    \\   {"type":"SYMBOL","name":"_dedent"}]}
;

/// Every symbol admitted, which is the permissive state the offside rule is
/// meant to be decided *by the bytes* in. A test that admitted only the token
/// it wanted would be asserting its own answer.
fn everything(f: *Fixture) !scanner.Scanner.Expected {
    var e = try f.sc.expecting(t.allocator);
    for (0..f.gr.terminal_count) |i| e.admit(&f.sc, @intCast(i));
    return e;
}

/// Take one token from `at` the way `tokenize` does, letting the extras move
/// past leading whitespace first, and hand back the offset to resume from.
fn expectTake(
    f: *Fixture,
    src: []const u8,
    at: u32,
    expected: ?*const scanner.Scanner.Expected,
    name: []const u8,
    len: u32,
) !u32 {
    switch (f.sc.next(src, at, expected)) {
        .token => |tok| {
            try t.expectEqualStrings(name, f.gr.nameOf(tok.symbol));
            try t.expectEqual(len, tok.len);
            return tok.end();
        },
        else => return error.ExpectedAToken,
    }
}

/// Walk a whole source, naming each token and how many bytes it took.
fn expectWalk(f: *Fixture, src: []const u8, want: []const []const u8) !void {
    var e = try everything(f);
    defer e.deinit(t.allocator);
    f.sc.rewind();
    var at: u32 = 0;
    var seen: usize = 0;
    while (true) switch (f.sc.next(src, at, &e)) {
        .end => break,
        .stray => |off| {
            std.debug.print("stray at {d} after {d} tokens\n", .{ off, seen });
            return error.Stray;
        },
        .token => |tok| {
            if (seen == want.len) return error.TooManyTokens;
            try t.expectEqualStrings(want[seen], f.gr.nameOf(tok.symbol));
            seen += 1;
            at = tok.end();
        },
    };
    try t.expectEqual(want.len, seen);
}

test "scanner: the offside rule opens and closes blocks nothing in the bytes marks" {
    // The shape tree-sitter-python's scanner.c specifies: a line indented past
    // the enclosing block opens one, a line short of it closes one, a line
    // level with it ends a statement, and end of input closes everything left
    // open. Two of the three tokens are zero width, which is the whole reason
    // the slate cannot host them.
    //
    // Driven with every symbol admitted, so the answer is the bytes' and not a
    // state set this test invented. That makes the spec's own checking order
    // visible: it tries indent, then dedent, then newline, so a line that both
    // opens a block and ends the statement before it yields the indent first.
    var f = try Fixture.init(layout_grammar);
    defer f.deinit();
    try t.expectEqual(@as(usize, 0), f.sc.blind.len);
    try t.expectEqual(@as(usize, 1), f.sc.casts.len);

    try expectWalk(&f, "a\n  b\n  c\nd\n", &.{
        "name", "_indent", "_newline", // `a`, then the deeper line opens a block
        "name", "_newline", // `b`, then `c` is level with it
        "name", "_dedent", "_newline", // `c`, then `d` leaves the block
        "name", "_newline", // `d`, then the trailing line ending
    });

    // Two blocks left open at end of input owe two dedents, innermost first,
    // and end of input is a line ending so the last statement still ends.
    try expectWalk(&f, "a\n  b\n    c", &.{
        "name",     "_indent", "_newline",
        "name",     "_indent", "_newline",
        "name",     "_dedent", "_dedent",
        "_newline",
    });
}

test "scanner: what the state will take decides which layout token fires" {
    // The same offset, two states, two answers - which is the whole reason
    // this cannot be a pattern. A state that has an action for a statement end
    // but none for a block gets the newline; one that will take either gets
    // the indent, because the spec checks indent first.
    var f = try Fixture.init(layout_grammar);
    defer f.deinit();
    const source = "a\n  b";

    var ending = try f.sc.expecting(t.allocator);
    defer ending.deinit(t.allocator);
    ending.admit(&f.sc, f.symbolOf("name"));
    ending.admit(&f.sc, f.symbolOf("_newline"));

    f.sc.rewind();
    try expectStep(&f, source, 1, &ending, "_newline", 0);

    var opening = try everything(&f);
    defer opening.deinit(t.allocator);
    f.sc.rewind();
    try expectStep(&f, source, 1, &opening, "_indent", 0);
}

test "scanner: an unclosed bracket suspends the offside rule" {
    // The spec's guard, and the reason `brackets` is on the troupe at all:
    // inside `(`, `[`, or `{` a line break carries no meaning, so a state that
    // is still holding a close bracket open may not be handed a dedent it
    // would otherwise be owed.
    var f = try Fixture.init(layout_grammar);
    defer f.deinit();
    const source = "a\n  b\nc";

    var all = try everything(&f);
    defer all.deinit(t.allocator);
    // A state mid-expression: a name or the closing bracket, and no action for
    // either a statement end or a block boundary. That is what a parser sitting
    // inside `f(` reports.
    var in_paren = try f.sc.expecting(t.allocator);
    defer in_paren.deinit(t.allocator);
    in_paren.admit(&f.sc, f.symbolOf("name"));
    in_paren.admit(&f.sc, f.symbolOf(")"));

    f.sc.rewind();
    var at = try expectTake(&f, source, 0, &all, "name", 1);
    try expectStep(&f, source, at, &all, "_indent", 0); // column two opens a block
    try expectStep(&f, source, at, &all, "_newline", 0);
    at = try expectTake(&f, source, at, &all, "name", 1);

    // Column zero is shallower than the block, so a dedent is owed - and the
    // open bracket is what withholds it. The name on the next line comes back
    // instead, with the block still standing.
    _ = try expectTake(&f, source, at, &in_paren, "name", 1);
}

test "scanner: a file does not inherit the last file's blocks" {
    // The memory is per file, not per grammar. Without the rewind, the column
    // opened by the first source is still standing when the second starts, and
    // its first line reads as leaving a block it never entered.
    var f = try Fixture.init(layout_grammar);
    defer f.deinit();
    try expectWalk(&f, "a\n  b", &.{ "name", "_indent", "_newline", "name", "_dedent", "_newline" });
    try expectWalk(&f, "a\nb", &.{ "name", "_newline", "name", "_newline" });
}

test "scanner: a delimited span's terminals go to the hand, not to the roll" {
    // `string_content` has a row in `outside.roll` - Rust's spelling, `[^"\\]+`
    // - and Ruby declares a fence troupe that claims the same name. The hand
    // has to win, because only it knows which delimiter opened this span. The
    // seated pattern would read `ab' y` here; the fence stops at the quote it
    // remembered.
    // The whole cast, because a troupe now seats only when the grammar declares
    // every part of it. Three of the eight names is what kotlin declares, and
    // that shape has its own test below.
    var f = try Fixture.init(ruby_span_grammar);
    defer f.deinit();
    try t.expectEqual(@as(usize, 0), f.sc.blind.len);
    // Claimed, so no seat and no stand-in: the roll does not get to answer for
    // a name a troupe took.
    try t.expectEqual(scanner.Scanner.no_seat, f.sc.seat[f.symbolOf("string_content")]);
    try t.expect(!f.sc.provided.isSet(f.symbolOf("string_content")));

    var e = try everything(&f);
    defer e.deinit(t.allocator);
    f.sc.rewind();
    const source = "x 'ab' y";
    try expectStep(&f, source, 0, &e, "name", 1);
    try expectStep(&f, source, 2, &e, "_string_start", 1);
    try expectStep(&f, source, 3, &e, "string_content", 2);
    try expectStep(&f, source, 5, &e, "_string_end", 1);
    try expectStep(&f, source, 7, &e, "name", 1);
}

/// Ruby's span convention declared whole: six openers, one body, one closer.
const ruby_span_grammar =
    \\{"name":"t","rules":{
    \\ "doc":{"type":"REPEAT1","content":{"type":"CHOICE","members":[
    \\   {"type":"SYMBOL","name":"_string_start"},{"type":"SYMBOL","name":"_symbol_start"},
    \\   {"type":"SYMBOL","name":"_subshell_start"},{"type":"SYMBOL","name":"_regex_start"},
    \\   {"type":"SYMBOL","name":"_string_array_start"},
    \\   {"type":"SYMBOL","name":"_symbol_array_start"},
    \\   {"type":"SYMBOL","name":"string_content"},
    \\   {"type":"SYMBOL","name":"_string_end"},{"type":"SYMBOL","name":"name"}]}},
    \\ "name":{"type":"PATTERN","value":"[a-z]+"}},
    \\ "extras":[{"type":"PATTERN","value":"[ \\t\\n]"}],
    \\ "externals":[{"type":"SYMBOL","name":"_string_start"},
    \\   {"type":"SYMBOL","name":"_symbol_start"},{"type":"SYMBOL","name":"_subshell_start"},
    \\   {"type":"SYMBOL","name":"_regex_start"},
    \\   {"type":"SYMBOL","name":"_string_array_start"},
    \\   {"type":"SYMBOL","name":"_symbol_array_start"},
    \\   {"type":"SYMBOL","name":"string_content"},{"type":"SYMBOL","name":"_string_end"}]}
;

test "scanner: a grammar sharing three of a troupe's names gets none of it" {
    // Kotlin's defect, in miniature. It declares `_string_start` - the anchor of
    // the Ruby troupe - along with `string_content` and `_string_end`, and
    // nothing else Ruby means by that convention. Binding on the anchor handed
    // it `%w[`, `%i[` and a subshell for a language that has none, which is a
    // confidently wrong token rather than a missing one.
    //
    // What it must get instead is silence: no hand, and no seat either, since
    // there is no spelling for an external the grammar never wrote down.
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"REPEAT1","content":{"type":"CHOICE","members":[
        \\   {"type":"SYMBOL","name":"_string_start"},{"type":"SYMBOL","name":"string_content"},
        \\   {"type":"SYMBOL","name":"_string_end"},{"type":"SYMBOL","name":"name"}]}},
        \\ "name":{"type":"PATTERN","value":"[a-z]+"}},
        \\ "extras":[{"type":"PATTERN","value":"[ \\t\\n]"}],
        \\ "externals":[{"type":"SYMBOL","name":"_string_start"},
        \\   {"type":"SYMBOL","name":"string_content"},{"type":"SYMBOL","name":"_string_end"}]}
    ;
    var f = try Fixture.init(src);
    defer f.deinit();

    var e = try everything(&f);
    defer e.deinit(t.allocator);
    f.sc.rewind();
    // Ruby would have opened a span on the quote and then owned every byte to
    // the matching one. This grammar never said a quote opens anything, so no
    // opener may be produced there.
    const source = "x 'ab' y";
    switch (f.sc.next(source, 2, &e)) {
        .token => |tok| try t.expect(!std.mem.eql(u8, "_string_start", f.gr.nameOf(tok.symbol))),
        else => {},
    }

    // And it reaches silence rather than the next wrong answer down. The roll
    // used to catch `string_content` on the name and hand back Rust's
    // `[^"\\]+`; it now wants the cohort that spelling was read with, which is
    // `string_close`, and this grammar does not declare it. So there is no
    // hand and no stand-in either.
    try t.expect(!f.sc.provided.isSet(f.symbolOf("string_content")));
}

test "scanner: a raw string closes on the mark its opener declared" {
    // Rust's `r#"..."#`, where the closing mark is not in the grammar at all -
    // it is whatever hash run the opener happened to carry. That is the case
    // no fixed spelling can cover, so the inner bare quote is content.
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"REPEAT1","content":{"type":"CHOICE","members":[
        \\   {"type":"SYMBOL","name":"_raw_string_literal_start"},
        \\   {"type":"SYMBOL","name":"raw_string_literal_content"},
        \\   {"type":"SYMBOL","name":"_raw_string_literal_end"},
        \\   {"type":"SYMBOL","name":"name"}]}},
        \\ "name":{"type":"PATTERN","value":"[a-z]+"}},
        \\ "extras":[{"type":"PATTERN","value":"[ \\t\\n]"}],
        \\ "externals":[{"type":"SYMBOL","name":"_raw_string_literal_start"},
        \\   {"type":"SYMBOL","name":"raw_string_literal_content"},
        \\   {"type":"SYMBOL","name":"_raw_string_literal_end"}]}
    ;
    var f = try Fixture.init(src);
    defer f.deinit();
    try t.expectEqual(@as(usize, 0), f.sc.blind.len);

    var e = try everything(&f);
    defer e.deinit(t.allocator);
    f.sc.rewind();
    const source = "x r#\"a\"b\"# y";
    var at = try expectTake(&f, source, 0, &e, "name", 1);
    at = try expectTake(&f, source, at, &e, "_raw_string_literal_start", 3);
    try expectStep(&f, source, at, &e, "raw_string_literal_content", 3);
    try expectStep(&f, source, at + 3, &e, "_raw_string_literal_end", 2);
    _ = try expectTake(&f, source, at + 5, &e, "name", 1);
}

test "scanner: a stand-in that states its refusal is asked before the slate" {
    // bash's shape, and the reason a tie-break could not have fixed it. Its
    // `word` matches `rows=` where `variable_name` matches only `rows`, so
    // longest-match hands the assignment target to `word` before any tie is
    // reached. tree-sitter never runs that comparison: its scanner answers
    // first, and answers `variable_name` exactly when an `=` follows.
    const src =
        \\{"name":"t","word":"word","rules":{
        \\ "doc":{"type":"REPEAT1","content":{"type":"CHOICE","members":[
        \\   {"type":"SYMBOL","name":"word"},{"type":"SYMBOL","name":"variable_name"},
        \\   {"type":"STRING","value":"="}]}},
        \\ "word":{"type":"PATTERN","value":"[a-zA-Z0-9_=]+"}},
        \\ "extras":[{"type":"PATTERN","value":"[ \\t\\n]"}],
        \\ "externals":[{"type":"SYMBOL","name":"variable_name"},
        \\   {"type":"SYMBOL","name":"file_descriptor"},
        \\   {"type":"SYMBOL","name":"test_operator"}]}
    ;
    var f = try Fixture.init(src);
    defer f.deinit();

    var e = try everything(&f);
    defer e.deinit(t.allocator);
    f.sc.rewind();

    // `rows=` is five bytes of `word` and four of `variable_name`, and the
    // guard holds, so the shorter one takes the position. The `=` after it is
    // the slate's own answer with no guard in it: `word` reaches the same one
    // byte, and a string beats a pattern of equal length.
    const assignment = "rows= 1";
    var at = try expectTake(&f, assignment, 0, &e, "variable_name", 4);
    _ = try expectTake(&f, assignment, at, &e, "=", 1);

    // The same four bytes with nothing following them are a bare word: the
    // scanner refused, so the slate answers and takes all five.
    at = try expectTake(&f, "rows x", 0, &e, "word", 4);
    _ = try expectTake(&f, "rows x", at, &e, "word", 1);
}

test "scanner: only a guarded stand-in goes first, and none of them is immediate" {
    // The pre-pass reads neither precedence nor immediacy, which is only sound
    // while the roll's guarded rows carry neither. Held here rather than
    // assumed, because a row that grew a `token.immediate` would start
    // beginning where an extra had already moved past.
    for (&outside.roll) |*p| {
        if (!outside.guards(p)) continue;
        try t.expect(!p.lexis.immediate);
        try t.expectEqual(@as(i32, 0), p.lexis.prec);
    }

    // And the guard itself: `never` is read before `after`, so a name before
    // `::` is not a hash key however well the colon reads.
    // Taken from the table rather than through `provisionFor`, which now wants
    // a grammar to check the row's cohort against; what is under test here is
    // the guard, not the binding.
    const key = for (&outside.roll) |*p| {
        if (std.mem.eql(u8, p.name, "hash_key_symbol")) break p;
    } else unreachable;
    try t.expect(outside.holds(key, "name: 1", 4));
    try t.expect(!outside.holds(key, "Name::x", 4));
    try t.expect(!outside.holds(key, "name x", 4));
}

test "scanner: a real grammar's context-free terminals are the trap, measured" {
    const grammar = @embedFile("json_grammar");
    var f = try Fixture.init(grammar);
    defer f.deinit();

    // Every terminal in tree-sitter-json is lexable - the difficulty here is
    // not a missing scanner, which makes it the cleanest demonstration that
    // difficulty and blindness are different problems.
    try t.expectEqual(@as(usize, 0), f.sc.blind.len);

    const source =
        \\{"a": [1, true, null], "b": "x"}
    ;

    // Asked unconditionally, `string_content` (`[^\"\n]+`) is legal nowhere in
    // particular and therefore longest almost everywhere: it takes
    // `: [1, true, null], ` in one bite. Thirteen tokens where a parser needs
    // twenty-one. This is pinned, not tolerated - it is the exact number that
    // must change when the cursor starts supplying the valid-terminal set, and
    // a silent improvement would be as suspicious as a silent regression.
    var loose = try scanner.tokenize(&f.sc, t.allocator, source, null);
    defer loose.deinit(t.allocator);
    try t.expectEqual(@as(?u32, null), loose.stray);
    try t.expectEqual(@as(usize, 13), loose.tokens.len);
    try t.expectEqualStrings("string_content", f.gr.nameOf(loose.tokens[4].symbol));
    try t.expectEqualStrings(": [1, true, null], ", source[loose.tokens[4].start..loose.tokens[4].end()]);

    // At that one offset, tell the scanner what a parse state sitting outside a
    // string would tell it - everything except `string_content` - and the
    // colon comes back. One call, on the real grammar, with no invented state
    // machine standing in for the parser: nineteen bytes become one.
    //
    // Deliberately not asserted here: a whole re-tokenization under that set.
    // `string_content` is illegal outside a string and REQUIRED inside one, so
    // a single static set cannot lex this file - only a per-state set can, and
    // producing one is the cursor's job, not this test's.
    var structural = try f.sc.expecting(t.allocator);
    defer structural.deinit(t.allocator);
    for (0..f.gr.terminal_count) |i| {
        const sym: g.Symbol = @intCast(i);
        if (!std.mem.eql(u8, f.gr.nameOf(sym), "string_content")) structural.admit(&f.sc, sym);
    }

    const at = loose.tokens[4].start;
    switch (f.sc.next(source, at, &structural)) {
        .token => |tok| {
            try t.expectEqualStrings(":", f.gr.nameOf(tok.symbol));
            try t.expectEqual(@as(u32, 1), tok.len);
            try t.expectEqual(at, tok.start);
        },
        else => return error.ExpectedAToken,
    }
}

test "scanner: a captured-close cast seats and leaves nothing for the roll" {
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"SEQ","members":[
        \\   {"type":"STRING","value":"R\""},
        \\   {"type":"SYMBOL","name":"raw_string_delimiter"},
        \\   {"type":"STRING","value":"("},
        \\   {"type":"SYMBOL","name":"raw_string_content"},
        \\   {"type":"STRING","value":")"},
        \\   {"type":"SYMBOL","name":"raw_string_delimiter"},
        \\   {"type":"STRING","value":"\""}]}},
        \\ "externals":[{"type":"SYMBOL","name":"raw_string_delimiter"},
        \\   {"type":"SYMBOL","name":"raw_string_content"}]}
    ;
    var f = try Fixture.init(src);
    defer f.deinit();

    // The whole cast is present, so the row seats: neither external is blind,
    // and both answer to the grammar's own names. What the hand then reads out
    // of the bytes - that `)x"` inside the body is not the close, because the
    // close is the spelling captured at the open - is `marrow.zig`'s own test,
    // since `names` tokenizes with no expected set and so never asks a hand.
    // Blind is the whole claim: it lists the externals nothing answers, so an
    // empty one says both are spoken for. `provided` is not the field to ask -
    // it marks the roll's seated patterns, and a hand deliberately does not
    // take a seat there.
    try t.expectEqual(@as(usize, 0), f.sc.blind.len);
}

test "scanner: a grammar spelling one of a marrow cast's names gets silence" {
    // Lua's shape, and the reason the cast exists. It declares
    // `_block_comment_content` - the anchor of Rust's row - for comments
    // spelled `--[==[ ]==]`, which nest by their own equals count and not by
    // `/*`. Seating Rust's dialect here would hand it a close it never wrote.
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"SEQ","members":[
        \\   {"type":"SYMBOL","name":"word"},
        \\   {"type":"SYMBOL","name":"_block_comment_start"},
        \\   {"type":"SYMBOL","name":"_block_comment_content"},
        \\   {"type":"SYMBOL","name":"_block_comment_end"}]},
        \\ "word":{"type":"PATTERN","value":"[a-z]+"}},
        \\ "externals":[{"type":"SYMBOL","name":"_block_comment_start"},
        \\   {"type":"SYMBOL","name":"_block_comment_content"},
        \\   {"type":"SYMBOL","name":"_block_comment_end"}]}
    ;
    var f = try Fixture.init(src);
    defer f.deinit();

    // All three stay blind. Rust's cast is the content plus both doc markers,
    // and lua declares neither marker, so the row does not seat - the grammar
    // is told it has no answer rather than handed the wrong one.
    try t.expectEqual(@as(usize, 3), f.sc.blind.len);
    try t.expect(!f.sc.provided.isSet(f.symbolOf("_block_comment_content")));
}

// ─────────────── the binding, pinned against the population ───────────────

/// Which grammars in `upstream/grammars/` each troupe row is allowed to seat.
///
/// Four mis-bindings have been caught on this build by a human listing
/// grammars by hand - kotlin handed Ruby's openers, scala handed Python's
/// column stack, lua nearly handed Rust's block-comment close, and this
/// round kotlin, php and scala all nearly handed JavaScript's continuation
/// set, because all three declare `_automatic_semicolon` and all three carry
/// a `||` token. Every one of those catches left no artifact. This is the
/// artifact: the enumeration, run against the real binding, so a row that
/// widens turns red with the name of the grammar it widened onto.
///
/// Each set is derived from the declarations rather than from our own output:
/// a grammar seats a row when it declares every part the row names as an
/// external. Adding a language to this list is a claim that the language
/// follows that convention, and it belongs in the same change as the row.
const seats = [_]struct { troupe: []const u8, grammars: []const []const u8 }{
    .{ .troupe = "offside", .grammars = &.{"python"} },
    .{ .troupe = "fence/python", .grammars = &.{"python"} },
    .{ .troupe = "fence/ruby", .grammars = &.{"ruby"} },
    .{ .troupe = "fence/rust_raw", .grammars = &.{"rust"} },
    .{ .troupe = "fence/heredoc", .grammars = &.{"bash"} },
    .{ .troupe = "marrow/rust_block", .grammars = &.{"rust"} },
    .{ .troupe = "marrow/cpp_raw", .grammars = &.{"cpp"} },
    .{ .troupe = "marrow/kotlin_block", .grammars = &.{"kotlin"} },
    .{ .troupe = "marrow/html_comment", .grammars = &.{"html"} },
    .{ .troupe = "marrow/rust_string", .grammars = &.{"rust"} },
    .{ .troupe = "marrow/julia_block", .grammars = &.{"julia"} },
    .{ .troupe = "marrow/lua_string", .grammars = &.{"lua"} },
    .{ .troupe = "marrow/lua_comment", .grammars = &.{"lua"} },
    .{ .troupe = "caesura", .grammars = &.{ "javascript", "typescript" } },
    .{ .troupe = "scry/css", .grammars = &.{"css"} },
    .{ .troupe = "scry/toml", .grammars = &.{"toml"} },
    // Three of these four spellings are among the commonest external names in
    // the population, so this row is the one whose exclusivity is least
    // self-evident and most worth pinning. `kin` is what buys it.
    .{ .troupe = "scry/haskell", .grammars = &.{"haskell"} },
    // Anchored on `_implicit_end_tag`, which is the one spelling in html's
    // cohort no other grammar in the thirty declares - `comment` is declared by
    // half of them and `raw_text` by four.
    .{ .troupe = "lineage/html", .grammars = &.{"html"} },
};

/// A troupe's place in the pinned list, by the same key the list spells.
fn troupeKey(t_: *const outside.Troupe) []const u8 {
    return switch (t_.kind) {
        .offside => "offside",
        .fence => switch (t_.dialect) {
            .python => "fence/python",
            .ruby => "fence/ruby",
            .rust_raw => "fence/rust_raw",
            .heredoc => "fence/heredoc",
        },
        .marrow => switch (t_.vein) {
            .rust_block => "marrow/rust_block",
            .cpp_raw => "marrow/cpp_raw",
            .kotlin_block => "marrow/kotlin_block",
            .html_comment => "marrow/html_comment",
            .rust_string => "marrow/rust_string",
            .julia_block => "marrow/julia_block",
            .lua_string => "marrow/lua_string",
            .lua_comment => "marrow/lua_comment",
        },
        .caesura => "caesura",
        .scry => switch (t_.sight) {
            .css => "scry/css",
            .toml => "scry/toml",
            .haskell => "scry/haskell",
        },
        .lineage => switch (t_.line) {
            .html => "lineage/html",
        },
    };
}

/// The externals one grammar declares, which is all the seating rule reads.
///
/// A grammar's ordinary tokens are not visible without pressing it, so
/// `terminal` answers only externals. That is exact for what this test pins:
/// every part `seated` requires is resolved as an external, and the fields
/// resolved as terminals - `gate`, `sign`, `hushed` - are refinements a cast
/// seats without. A change that made one of them load-bearing would have to
/// widen this resolver, which is the review this test exists to force.
const Declared = struct {
    names: []const []const u8,

    pub fn external(d: Declared, name: []const u8) ?g.Symbol {
        if (name.len == 0) return null;
        for (d.names, 0..) |n, i| if (std.mem.eql(u8, n, name)) return @intCast(i);
        return null;
    }
    pub fn terminal(d: Declared, name: []const u8) ?g.Symbol {
        return d.external(name);
    }
};

test "scanner: every troupe seats exactly the grammars its convention names" {
    var arena: std.heap.ArenaAllocator = .init(t.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var threaded = std.Io.Threaded.init(t.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var dir = try std.Io.Dir.cwd().openDir(io, "upstream/grammars", .{ .iterate = true });
    defer dir.close(io);

    var seen: std.ArrayList([]const u8) = .empty;
    var wrong: std.ArrayList([]const u8) = .empty;
    var files: usize = 0;

    var walk = dir.iterate();
    while (try walk.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".json")) continue;
        files += 1;
        const lang = entry.name[0 .. entry.name.len - ".json".len];
        const path = try std.fmt.allocPrint(gpa, "upstream/grammars/{s}", .{entry.name});
        const src = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64 << 20));

        const Shape = struct {
            externals: []const struct { name: ?[]const u8 = null, value: ?[]const u8 = null } = &.{},
        };
        const doc = try std.json.parseFromSliceLeaky(Shape, gpa, src, .{ .ignore_unknown_fields = true });
        var names: std.ArrayList([]const u8) = .empty;
        for (doc.externals) |e| try names.append(gpa, e.name orelse e.value orelse continue);

        const declared: Declared = .{ .names = names.items };
        for (&outside.troupes) |*row| {
            if (outside.provision(row, declared) == null) continue;
            const key = troupeKey(row);
            const note = try std.fmt.allocPrint(gpa, "{s} <- {s}", .{ key, lang });
            try seen.append(gpa, note);
            const allowed = for (seats) |s| {
                if (std.mem.eql(u8, s.troupe, key)) break s.grammars;
            } else &[_][]const u8{};
            for (allowed) |a| {
                if (std.mem.eql(u8, a, lang)) break;
            } else try wrong.append(gpa, note);
        }
    }

    // A row that stopped seating is as much a defect as one that widened, so
    // the pinned list is checked in both directions.
    var missing: std.ArrayList([]const u8) = .empty;
    for (seats) |s| for (s.grammars) |lang| {
        const note = try std.fmt.allocPrint(gpa, "{s} <- {s}", .{ s.troupe, lang });
        for (seen.items) |got| {
            if (std.mem.eql(u8, got, note)) break;
        } else try missing.append(gpa, note);
    };

    for (wrong.items) |w| std.debug.print("\nseated where it must not: {s}", .{w});
    for (missing.items) |m| std.debug.print("\nstopped seating: {s}", .{m});
    try t.expectEqual(@as(usize, 0), wrong.items.len);
    try t.expectEqual(@as(usize, 0), missing.items.len);
    // The population is the thirty pinned grammars; a shrunken one would make
    // every absence look like a pass.
    try t.expectEqual(@as(usize, 30), files);
}

test "scanner: a save is a value, and comparing one structurally is a trap" {
    var f = try Fixture.init(layout_grammar);
    defer f.deinit();

    // Walk an indented file, so the column stack has a live prefix and a dead
    // tail behind it.
    const walked = try f.names("a\n  b");
    defer t.allocator.free(walked);
    const first = f.sc.save();

    // The trap the weave lane asked about, demonstrated rather than asserted
    // from the type: a byte-identical state built a second way can disagree
    // under `std.meta.eql` because the dead tail is whatever memory held.
    var forged = first;
    for (forged.carry.columns.deep[forged.carry.columns.len..]) |*d| d.* = 0xBEEF;
    for (forged.carry.spans.open[forged.carry.spans.len..]) |*s| s.mark_len = 0xFF;
    try t.expect(first.same(&forged));

    // And restore actually puts it back: run on, then rewind, then restore.
    f.sc.rewind();
    try t.expect(!first.same(&f.sc.save()));
    f.sc.restore(first);
    try t.expect(first.same(&f.sc.save()));
}
/// A grammar shaped like every real one: a body pattern that runs until a
/// delimiter, and the delimiters it stops at. Sixteen of the corpus's grammars
/// hold this shape, which is why the reading below was not a scala problem.
const bodied =
    \\{"name":"t","rules":{
    \\ "doc":{"type":"REPEAT1","content":{"type":"CHOICE","members":[
    \\   {"type":"SYMBOL","name":"text"},{"type":"SYMBOL","name":"comma"},
    \\   {"type":"SYMBOL","name":"semi"}]}},
    \\ "text":{"type":"PATTERN","value":"[^\"]+"},
    \\ "comma":{"type":"STRING","value":","},
    \\ "semi":{"type":"STRING","value":";"}}}
;

test "scanner: with nobody vouching for the slate, the shortest reading names the byte" {
    // What `blame` asks and what it used to be told. There is no state here -
    // that is the situation, not a shortcut - so the slate is every terminal
    // the grammar has, and maximal munch over such a slate reports whichever
    // member reaches furthest. That member is always the body pattern, so the
    // answer is a fact about the grammar rather than about the offset: on the
    // real board this named `xml_text` over 1,777 bytes of a scala file with
    // no XML in it, at an offset holding a comma.
    var f = try Fixture.init(bodied);
    defer f.deinit();

    const src = "," ++ "x" ** 2048;

    // The old reading, pinned rather than deleted: it is still what `next`
    // says, and still correct for the question `next` answers. Nothing about
    // maximal munch moved; what moved is which question `blame` asks.
    var wide = try everything(&f);
    defer wide.deinit(t.allocator);
    const longest = f.sc.next(src, 0, &wide).token;
    try t.expectEqualStrings("text", f.gr.nameOf(longest.symbol));
    try t.expectEqual(@as(u32, src.len), longest.len);

    // And the reading `spot` gives instead. `text` accepts a lone comma too,
    // so this is a tie rather than an exclusion - `choose` settles it the
    // ordinary way, and a literal outranks a regex that merely also fits.
    const near = f.sc.spot(src, 0).token;
    try t.expectEqualStrings("comma", f.gr.nameOf(near.symbol));
    try t.expectEqual(@as(u32, 1), near.len);

    // The cost claim, which is the half a name comparison cannot show. A
    // caller that mints a token goes on to step past it, so the old reading
    // did not merely misname this offset - it consumed the file to do it, and
    // `mend` deleted every byte of what it consumed.
    try t.expect(near.len * 64 < longest.len);
}

test "scanner: spot is state-free by construction, not by a caller remembering" {
    // Two ways to get the wrong answer back, and neither is available: the
    // slate `spot` reads is built once at compile time from every seated
    // terminal, so there is no `expected` argument to pass and no tier to
    // fall through. Precedence is dropped with it - a lexical precedence says
    // which terminal owns a byte *when both were asked for*, and over the
    // whole grammar it elects the same wide member reach did.
    var f = try Fixture.init(bodied);
    defer f.deinit();

    // Mid-file, after a body run, where the offset is unambiguous to a reader
    // and was not to the old question.
    const src = "abc,def";
    const at = f.sc.spot(src, 3).token;
    try t.expectEqualStrings("comma", f.gr.nameOf(at.symbol));
    try t.expectEqual(@as(u32, 3), at.start);
    try t.expectEqual(@as(u32, 1), at.len);

    // Where the shortest reading *is* the body pattern, it still answers - the
    // narrowing is "stop at the first accept", not "prefer literals".
    const body = f.sc.spot(src, 0).token;
    try t.expectEqualStrings("text", f.gr.nameOf(body.symbol));
    try t.expectEqual(@as(u32, 1), body.len);

    // Asking twice from the same offset gives the same answer: `spot` resets
    // whatever state the layout hands carry, the way `next` does, so a
    // diagnostic cannot be perturbed by the parse that led to it.
    const again = f.sc.spot(src, 3).token;
    try t.expectEqual(at.symbol, again.symbol);
    try t.expectEqual(at.len, again.len);

    // Past the end there is nothing to name, and nothing is what it says.
    try t.expectEqual(scanner.Step.end, f.sc.spot(src, @intCast(src.len)));
}
