//! The front door's tests: a `grammar.json` in, and what the IR has to say
//! about it.
//!
//! Every one drives `treeSitter` end to end rather than any single pass,
//! because what the passes have to agree about is the finished grammar. A
//! terminal's number is decided in `muster`, spelled in `spelling`'s key and
//! spent by the lexer, and a test of any one of the three alone would pass
//! while the three of them disagreed about the same token.
//!
//! Expectations are derived from the grammar under test, or from what
//! tree-sitter's own generated parser does with it. None is derived by running
//! this importer and writing down what it said.

const std = @import("std");
const g = @import("grammar.zig");
const treeSitter = @import("import.zig").treeSitter;

const testing = std.testing;

test "a rule whose body is one atom becomes a terminal, not a nonterminal" {
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"SYMBOL","name":"word"},
        \\ "word":{"type":"PATTERN","value":"[a-z]+"}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();
    try testing.expectEqual(@as(u32, 1), gr.terminal_count);
    try testing.expectEqualStrings("word", gr.nameOf(0));
    try testing.expect(gr.isTerminal(0));
}

test "repeat is a left-recursive auxiliary and the emptiness lives in the host" {
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"REPEAT","content":{"type":"STRING","value":"a"}}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    const doc = for (0..gr.symbolCount()) |i| {
        if (std.mem.eql(u8, gr.nameOf(@intCast(i)), "doc")) break @as(g.Symbol, @intCast(i));
    } else unreachable;

    // The host carries the choice: one body with the list, one without.
    const host = gr.productionsOf(doc);
    try testing.expectEqual(@as(usize, 2), host.len);
    try testing.expectEqual(@as(usize, 1), gr.productions[host[0]].rhs.len);
    try testing.expectEqual(@as(usize, 0), gr.productions[host[1]].rhs.len);

    // The auxiliary is `repeat1` — one element, or itself and one more — and
    // crucially never ε, so no state has to decide whether a list is empty
    // before it has seen anything.
    const aux = gr.productions[host[0]].rhs[0];
    var saw_single = false;
    var saw_loop = false;
    for (gr.productionsOf(aux)) |p| {
        const rhs = gr.productions[p].rhs;
        try testing.expect(rhs.len != 0);
        if (rhs.len == 1) saw_single = true;
        if (rhs.len == 2 and rhs[0] == aux) saw_loop = true;
    }
    try testing.expect(saw_single);
    try testing.expect(saw_loop);
}

test "one rule writing the same list twice gets one auxiliary, not two" {
    // Java's `try_statement` writes `repeat($.catch_clause)` in two alternatives.
    // Two auxiliaries for it are distinguishable only by a name the language
    // does not have, so folding one element becomes a reduce/reduce conflict
    // over which list is being built.
    const src =
        \\{"name":"t","rules":{"doc":{"type":"CHOICE","members":[
        \\ {"type":"SEQ","members":[{"type":"STRING","value":"try"},
        \\   {"type":"REPEAT1","content":{"type":"STRING","value":"c"}}]},
        \\ {"type":"SEQ","members":[{"type":"STRING","value":"do"},
        \\   {"type":"REPEAT1","content":{"type":"STRING","value":"c"}}]}]}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    var lists: usize = 0;
    for (gr.terminal_count..gr.symbolCount()) |s| {
        const sym: g.Symbol = @intCast(s);
        if (gr.isSynthetic(sym)) lists += 1;
    }
    try testing.expectEqual(@as(usize, 1), lists);
}

test "two different rules writing the same list also get one auxiliary" {
    // Java writes `repeat($._annotation)` in a dozen rules and C repeats one
    // attribute list in three declarator shapes. Keeping the auxiliary per host
    // is the tidy boundary rather than the sound one: the merge cannot make the
    // grammar ambiguous, because two lists with identical bodies already derive
    // the same strings under two names.
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"a"},{"type":"SYMBOL","name":"b"}]},
        \\ "a":{"type":"SEQ","members":[{"type":"STRING","value":"try"},
        \\   {"type":"REPEAT1","content":{"type":"STRING","value":"c"}}]},
        \\ "b":{"type":"SEQ","members":[{"type":"STRING","value":"do"},
        \\   {"type":"REPEAT1","content":{"type":"STRING","value":"c"}}]}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    var lists: usize = 0;
    for (gr.terminal_count..gr.symbolCount()) |s| {
        const sym: g.Symbol = @intCast(s);
        if (gr.isSynthetic(sym)) lists += 1;
    }
    try testing.expectEqual(@as(usize, 1), lists);
}

test "a list declaring precedence keeps it, and does not share with one that does not" {
    // Python's `union_pattern` is `repeat1(prec.left(seq('|', pattern)))`. Drop
    // the `prec.left` on the way in and the ladder has nothing to settle the
    // list's own continue-or-stop with; keep it and the cell resolves.
    const src =
        \\{"name":"t","rules":{"doc":{"type":"SEQ","members":[
        \\ {"type":"REPEAT1","content":{"type":"PREC_LEFT","value":1,
        \\   "content":{"type":"STRING","value":"x"}}},
        \\ {"type":"REPEAT1","content":{"type":"STRING","value":"x"}}]}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    var ranked: usize = 0;
    var plain: usize = 0;
    for (gr.productions) |p| {
        if (!gr.isSynthetic(p.lhs)) continue;
        const last = p.consumed(p.rhs.len);
        if (last.prec.eql(.{ .level = 1 }) and last.assoc == .left) ranked += 1 else plain += 1;
    }
    // Two productions each (`L -> x` and `L -> L x`), and the ranked list is a
    // different rule from the unranked one because precedence is part of what
    // the productions say.
    try testing.expectEqual(@as(usize, 2), ranked);
    try testing.expectEqual(@as(usize, 2), plain);
}

test "choice distributes inside a sequence while the product stays small" {
    const src =
        \\{"name":"t","rules":{"doc":{"type":"SEQ","members":[
        \\ {"type":"CHOICE","members":[{"type":"STRING","value":"a"},{"type":"STRING","value":"b"}]},
        \\ {"type":"STRING","value":"!"}]}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();
    // `$start -> doc` plus the two distributed alternatives, and no auxiliary.
    try testing.expectEqual(@as(usize, 3), gr.productions.len);
    try testing.expectEqual(@as(u32, 3), gr.terminal_count);
}

test "the word rule survives, because longest match cannot decide a keyword" {
    // Both terminals match `int` at the same offset and nothing about either
    // pattern breaks the tie. `word` is the author saying which one is the
    // spelling and which one is the meaning.
    const src =
        \\{"name":"t","word":"identifier","rules":{
        \\ "doc":{"type":"CHOICE","members":[
        \\  {"type":"SYMBOL","name":"identifier"},{"type":"SYMBOL","name":"kw"}]},
        \\ "identifier":{"type":"PATTERN","value":"[a-z]+"},
        \\ "kw":{"type":"STRING","value":"int"}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();
    const word = gr.word orelse return error.WordDropped;
    try testing.expectEqualStrings("identifier", gr.nameOf(word));
    try testing.expect(gr.isTerminal(word));
}

test "a word naming something that is not a token is refused rather than trusted" {
    const src =
        \\{"name":"t","word":"doc","rules":{
        \\ "doc":{"type":"SEQ","members":[
        \\  {"type":"STRING","value":"a"},{"type":"STRING","value":"b"}]}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();
    try testing.expectEqual(@as(?g.Symbol, null), gr.word);
}

/// The finished-grammar symbol a rule name landed on.
fn symbolNamed(gr: *const g.Grammar, name: []const u8) g.Symbol {
    for (0..gr.symbolCount()) |s| {
        if (std.mem.eql(u8, gr.nameOf(@intCast(s)), name)) return @intCast(s);
    }
    unreachable;
}

/// The one production of a single-alternative rule, for the shaping tests.
fn onlyProduction(gr: *const g.Grammar, rule: []const u8) g.Production {
    const rules = gr.productionsOf(symbolNamed(gr, rule));
    std.debug.assert(rules.len == 1);
    return gr.productions[rules[0]];
}

test "an alias renames a child where it was renamed, and leaves the symbol alone" {
    // C aliases `_old_style_function_definition` to `function_definition` at
    // two sites and leaves it hidden everywhere else. Hang the rename on the
    // symbol and both readings collapse into whichever site was seen last.
    const src =
        \\{"name":"t","rules":{"doc":{"type":"CHOICE","members":[
        \\ {"type":"SEQ","members":[{"type":"STRING","value":"a"},{"type":"SYMBOL","name":"thing"}]},
        \\ {"type":"SEQ","members":[{"type":"STRING","value":"b"},
        \\   {"type":"ALIAS","named":true,"value":"other","content":{"type":"SYMBOL","name":"thing"}}]}]},
        \\ "thing":{"type":"PATTERN","value":"[a-z]+"}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    const thing = symbolNamed(&gr, "thing");
    const rules = gr.productionsOf(symbolNamed(&gr, "doc"));
    try testing.expectEqual(@as(usize, 2), rules.len);

    // One symbol, reached twice, wearing two different names.
    const plain = gr.productions[rules[0]];
    const renamed = gr.productions[rules[1]];
    try testing.expectEqual(thing, plain.rhs[1]);
    try testing.expectEqual(thing, renamed.rhs[1]);
    try testing.expectEqual(@as(?g.Alias, null), gr.aliasOf(plain.steps[1]));
    try testing.expectEqualStrings("other", gr.aliasOf(renamed.steps[1]).?.name);
    try testing.expect(gr.aliasOf(renamed.steps[1]).?.named);
    // And the symbol itself is untouched: it is still `thing`, still named.
    try testing.expectEqualStrings("thing", gr.nameOf(thing));
    try testing.expectEqual(g.Shape.named, gr.shapeOf(thing));
}

test "a field names a child at its use site, and composes with an alias" {
    const src =
        \\{"name":"t","rules":{"doc":{"type":"SEQ","members":[
        \\ {"type":"FIELD","name":"key","content":{"type":"SYMBOL","name":"word"}},
        \\ {"type":"FIELD","name":"value","content":
        \\   {"type":"ALIAS","named":false,"value":"lit","content":{"type":"SYMBOL","name":"word"}}}]},
        \\ "word":{"type":"PATTERN","value":"[a-z]+"}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    const doc = onlyProduction(&gr, "doc");
    try testing.expectEqualStrings("key", gr.fieldOf(doc.steps[0]).?);
    try testing.expectEqual(@as(?g.Alias, null), gr.aliasOf(doc.steps[0]));
    try testing.expectEqualStrings("value", gr.fieldOf(doc.steps[1]).?);
    try testing.expectEqualStrings("lit", gr.aliasOf(doc.steps[1]).?.name);
    // `named: false` is not a detail: it is the difference between a query
    // matching `(lit)` and one matching `"lit"`.
    try testing.expect(!gr.aliasOf(doc.steps[1]).?.named);
}

test "a rename inside a precedence group is not handed back with the rank" {
    // The `prec` group ends before the production does, so its rank is handed
    // back to the surroundings — but a node is still called what it is called.
    const src =
        \\{"name":"t","rules":{"doc":{"type":"SEQ","members":[
        \\ {"type":"PREC","value":1,"content":
        \\   {"type":"ALIAS","named":true,"value":"renamed","content":{"type":"SYMBOL","name":"word"}}},
        \\ {"type":"STRING","value":"!"}]},
        \\ "word":{"type":"PATTERN","value":"[a-z]+"}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    const doc = onlyProduction(&gr, "doc");
    try testing.expect(doc.steps[0].prec == .none);
    try testing.expectEqualStrings("renamed", gr.aliasOf(doc.steps[0]).?.name);
}

test "a leading underscore hides a rule, and so does being a supertype" {
    // C's `expression` carries no underscore and has never appeared in a C
    // parse tree, because tree-sitter hides every `supertypes` entry on the
    // way in. A tree builder that read only the name would emit a node the
    // world's highlight queries do not expect.
    const src =
        \\{"name":"t","supertypes":["expression"],"rules":{
        \\ "doc":{"type":"SYMBOL","name":"expression"},
        \\ "expression":{"type":"CHOICE","members":[
        \\   {"type":"SYMBOL","name":"_inner"},{"type":"STRING","value":"lit"}]},
        \\ "_inner":{"type":"PATTERN","value":"[0-9]+"}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    const expression = symbolNamed(&gr, "expression");
    try testing.expectEqual(g.Shape.hidden, gr.shapeOf(expression));
    try testing.expect(gr.isSupertype(expression));
    try testing.expectEqual(g.Shape.named, gr.shapeOf(symbolNamed(&gr, "doc")));
    try testing.expect(!gr.isSupertype(symbolNamed(&gr, "doc")));
    // Hiding by name reaches a rule that resolved into the terminal space too.
    try testing.expectEqual(g.Shape.hidden, gr.shapeOf(symbolNamed(&gr, "_inner")));
}

test "named, anonymous, and invented are three different answers" {
    const src =
        \\{"name":"t","rules":{"doc":{"type":"SEQ","members":[
        \\ {"type":"STRING","value":"+"},
        \\ {"type":"PATTERN","value":"[0-9]+"},
        \\ {"type":"REPEAT1","content":{"type":"STRING","value":"z"}},
        \\ {"type":"SYMBOL","name":"word"}]},
        \\ "word":{"type":"PATTERN","value":"[a-z]+"}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    // A bare string is a node you can see and cannot name; an inline pattern
    // is not a node at all; a rule is both. Read off the body rather than by
    // name, because the name of an inline pattern is the rendered regex.
    const doc = onlyProduction(&gr, "doc");
    try testing.expectEqual(g.Shape.anonymous, gr.shapeOf(doc.rhs[0]));
    try testing.expectEqualStrings("+", gr.nameOf(doc.rhs[0]));
    try testing.expectEqual(g.Shape.invented, gr.shapeOf(doc.rhs[1]));
    try testing.expectEqual(g.Shape.named, gr.shapeOf(doc.rhs[3]));
    try testing.expectEqualStrings("word", gr.nameOf(doc.rhs[3]));
    try testing.expectEqual(g.Shape.invented, gr.shapeOf(gr.start));

    // The repeat helper is invisible *and* nobody's rule, which is the whole
    // reason `invented` is not spelled the same way as `hidden`.
    try testing.expectEqual(g.Shape.invented, gr.shapeOf(doc.rhs[2]));
    try testing.expect(!gr.shapeOf(doc.rhs[2]).visible());
}

test "two bodies that differ only in what they call a child stay two bodies" {
    // Deduplication collapses two identical productions because no parser can
    // tell them apart. Two trees over one parse is exactly the case where that
    // reasoning stops applying.
    const src =
        \\{"name":"t","rules":{"doc":{"type":"CHOICE","members":[
        \\ {"type":"SYMBOL","name":"word"},
        \\ {"type":"ALIAS","named":true,"value":"other","content":{"type":"SYMBOL","name":"word"}}]},
        \\ "word":{"type":"PATTERN","value":"[a-z]+"}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    const rules = gr.productionsOf(symbolNamed(&gr, "doc"));
    try testing.expectEqual(@as(usize, 2), rules.len);
    try testing.expectEqual(@as(?g.Alias, null), gr.aliasOf(gr.productions[rules[0]].steps[0]));
    try testing.expectEqualStrings("other", gr.aliasOf(gr.productions[rules[1]].steps[0]).?.name);
}

test "two lists that differ only in a field are two auxiliaries" {
    // Sharing a repeat helper by content is what keeps a grammar's conflict
    // count honest, and the content includes what the elements are filed
    // under: merge these and one of the two fields is gone.
    const src =
        \\{"name":"t","rules":{"doc":{"type":"SEQ","members":[
        \\ {"type":"REPEAT1","content":
        \\   {"type":"FIELD","name":"a","content":{"type":"STRING","value":"x"}}},
        \\ {"type":"REPEAT1","content":{"type":"STRING","value":"x"}}]}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    var filed: usize = 0;
    var bare: usize = 0;
    for (gr.productions) |p| {
        if (gr.shapeOf(p.lhs) != .invented or p.lhs == gr.start) continue;
        if (gr.fieldOf(p.steps[p.steps.len - 1]) != null) filed += 1 else bare += 1;
    }
    // Two productions each: `L -> x` and `L -> L x`.
    try testing.expectEqual(@as(usize, 2), filed);
    try testing.expectEqual(@as(usize, 2), bare);
}

/// One of the committed tree-sitter grammars, or `error.FileNotFound` when the
/// corpus is not underfoot. It is a fixture, not a build input, so a run that
/// cannot see it skips rather than fails.
fn corpus(gpa: std.mem.Allocator, name: []const u8) ![]u8 {
    const path = try std.fmt.allocPrint(gpa, "upstream/grammars/{s}.json", .{name});
    defer gpa.free(path);
    var threaded = std.Io.Threaded.init(gpa, .{});
    defer threaded.deinit();
    return std.Io.Dir.cwd().readFileAlloc(threaded.io(), path, gpa, .limited(64 << 20));
}

test "an inheriting grammar arrives already expanded, so `inherits` needs no code" {
    // cpp says `inherits: c` and typescript says `inherits: javascript`, and
    // this importer ignores both. It can, because `tree-sitter generate`
    // resolves inheritance in JavaScript, up in the DSL, and the grammar.json
    // a repository commits is the *result* of that — cpp's file already holds
    // all 182 of c's rule names, 53 of them overridden.
    //
    // Implementing it here would be worse than redundant. The committed
    // javascript.json defines `using_declaration` and typescript.json does
    // not, because the two files were generated at different times against
    // different upstreams; splicing today's parent into yesterday's child
    // would build a grammar neither project has ever shipped.
    //
    // The proof is that the import completes: `alts` refuses a `SYMBOL` naming
    // a rule the grammar does not define, so a single unresolved inherited
    // reference would come back as `error.MalformedGrammar` rather than as a
    // quietly smaller table.
    const inherited = .{ .{ "cpp", "sizeof_expression" }, .{ "typescript", "arrow_function" } };
    inline for (inherited) |pair| {
        const src = corpus(testing.allocator, pair[0]) catch |e| switch (e) {
            error.FileNotFound => return error.SkipZigTest,
            else => return e,
        };
        defer testing.allocator.free(src);
        var gr = try treeSitter(testing.allocator, src);
        defer gr.deinit();
        _ = symbolNamed(&gr, pair[1]); // a parent's rule, present in the child
    }
}

test "an external scanner token survives as unlexable rather than as a guess" {
    const src =
        \\{"name":"t","rules":{"doc":{"type":"SYMBOL","name":"indent"}},
        \\ "externals":[{"type":"SYMBOL","name":"indent"}]}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();
    try testing.expectEqual(@as(usize, 1), gr.externals.len);
    try testing.expectEqualStrings("indent", gr.nameOf(gr.externals[0]));
}

test "every wrapper over a string is still the string's own visible node" {
    // tree-sitter names an anonymous terminal after the bytes it matches and
    // shows it, and a lexical wrapper is not part of that name: its
    // `node-types.json` for all four of these carries one `{"type":")",
    // "named":false}` and nothing else. Rendering the wrapper instead filed
    // three of them as patterns, and a pattern written inline is auxiliary,
    // so the node vanished without the parse ever objecting.
    const src =
        \\{"name":"t","rules":{"doc":{"type":"SEQ","members":[
        \\ {"type":"STRING","value":")"},
        \\ {"type":"TOKEN","content":{"type":"STRING","value":")"}},
        \\ {"type":"IMMEDIATE_TOKEN","content":{"type":"STRING","value":")"}},
        \\ {"type":"PREC","value":1,"content":{"type":"STRING","value":")"}}]}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    const doc = onlyProduction(&gr, "doc");
    try testing.expectEqual(@as(usize, 4), doc.rhs.len);
    for (doc.rhs) |sym| {
        try testing.expect(gr.isTerminal(sym));
        try testing.expectEqualStrings(")", gr.nameOf(sym));
        try testing.expectEqual(g.Shape.anonymous, gr.shapeOf(sym));
        try testing.expect(gr.shapeOf(sym).visible());
    }
}

test "a token wrapping more than one atom is the pattern it renders to" {
    // `token(seq('#', /[^\n]*/))` is the shape every comment rule is written
    // in: one terminal spelled in pieces, which only a rendered pattern can
    // express. `prec` cannot do that, because it ranks a reading rather than
    // fusing one, so the same body under `prec` stays two symbols. Both stay
    // where they were; unwrapping asks what is inside first and gets nothing.
    const src =
        \\{"name":"t","rules":{"doc":{"type":"SEQ","members":[
        \\ {"type":"TOKEN","content":{"type":"SEQ","members":[
        \\   {"type":"STRING","value":"#"},{"type":"PATTERN","value":"[^\n]*"}]}},
        \\ {"type":"PREC","value":1,"content":{"type":"SEQ","members":[
        \\   {"type":"STRING","value":"!"},{"type":"STRING","value":"?"}]}}]}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    const doc = onlyProduction(&gr, "doc");
    try testing.expectEqual(@as(usize, 3), doc.rhs.len);
    try testing.expect(gr.isTerminal(doc.rhs[0]));
    try testing.expectEqual(g.Shape.invented, gr.shapeOf(doc.rhs[0]));
    try testing.expectEqualStrings("!", gr.nameOf(doc.rhs[1]));
    try testing.expectEqualStrings("?", gr.nameOf(doc.rhs[2]));
}

test "a wrapper chain reaches the literal without spending its standing" {
    // The pattern walk and the `lexis` walk read the same chain for different
    // answers, and neither may cost the other one. `token(prec(2, '!'))` is
    // the `!` node ranked 2, not a `!` node and not a rank on its own.
    const src =
        \\{"name":"t","rules":{"doc":{"type":"SEQ","members":[
        \\ {"type":"TOKEN","content":{"type":"PREC","value":2,
        \\   "content":{"type":"STRING","value":"!"}}},
        \\ {"type":"IMMEDIATE_TOKEN","content":{"type":"PREC","value":3,
        \\   "content":{"type":"STRING","value":"?"}}}]}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    const doc = onlyProduction(&gr, "doc");
    try testing.expectEqualStrings("!", gr.nameOf(doc.rhs[0]));
    try testing.expectEqual(@as(i32, 2), gr.lexisOf(doc.rhs[0]).prec);
    try testing.expect(!gr.lexisOf(doc.rhs[0]).immediate);
    try testing.expectEqualStrings("?", gr.nameOf(doc.rhs[1]));
    try testing.expectEqual(@as(i32, 3), gr.lexisOf(doc.rhs[1]).prec);
    try testing.expect(gr.lexisOf(doc.rhs[1]).immediate);
}

test "one spelling at one standing is one terminal, however it is written" {
    // The deduplication tree-sitter does do: `extract_tokens` unwraps a bare
    // `token(...)` before it interns, so both sites land on the single
    // `anon_sym_RPAREN` its generated parser holds.
    //
    // The choice has two arms and the grammar keeps one production, which is
    // the merge stated twice: interning collapsed the terminal, and then two
    // bodies that had become identical collapsed too.
    const src =
        \\{"name":"t","rules":{"doc":{"type":"CHOICE","members":[
        \\ {"type":"STRING","value":")"},
        \\ {"type":"TOKEN","content":{"type":"STRING","value":")"}}]}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    const rules = gr.productionsOf(symbolNamed(&gr, "doc"));
    try testing.expectEqual(@as(usize, 1), rules.len);
    try testing.expectEqual(@as(u32, 1), gr.terminal_count);
    try testing.expectEqualStrings(")", gr.nameOf(gr.productions[rules[0]].rhs[0]));
}

test "a rule is still the token it spells when nothing else spells it" {
    // The sole claimant keeps the name, which is how `identifier: /[a-z]+/`
    // becomes a named token. tree-sitter's parser for this grammar carries
    // `ACCEPT_TOKEN(sym_kw)` and never reduces `kw`, and so does its parser for
    // go's `blank_identifier` and java's `underscore_pattern`, whose only other
    // sightings of `_` are sealed inside a `token(seq(...))`.
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"SEQ","members":[{"type":"SYMBOL","name":"kw"},{"type":"SYMBOL","name":"word"}]},
        \\ "kw":{"type":"TOKEN","content":{"type":"STRING","value":"go"}},
        \\ "word":{"type":"PATTERN","value":"[a-z]+"}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    const kw = symbolNamed(&gr, "kw");
    try testing.expect(gr.isTerminal(kw));
    try testing.expectEqual(g.Shape.named, gr.shapeOf(kw));
    try testing.expectEqual(@as(usize, 0), gr.productionsOf(kw).len);
}

test "a rule another place also spells derives that token instead of being it" {
    // Generated for real, this grammar holds one `anon_sym_go` and a `kw` that
    // carries `REDUCE(sym_kw, 1)` and no `ACCEPT_TOKEN`; `node-types.json`
    // keeps `kw` named and visible and `"go"` anonymous and visible, and
    // `tree-sitter parse` answers `(doc (kw))` for `go !` and `(doc (word))`
    // for `go ab`. Naming both put two terminals matching identical bytes on
    // one state's row, where nothing downstream could pick between them.
    const src =
        \\{"name":"t","rules":{"doc":{"type":"CHOICE","members":[
        \\ {"type":"SEQ","members":[{"type":"STRING","value":"go"},{"type":"SYMBOL","name":"word"}]},
        \\ {"type":"SEQ","members":[{"type":"SYMBOL","name":"kw"},{"type":"STRING","value":"!"}]}]},
        \\ "kw":{"type":"TOKEN","content":{"type":"STRING","value":"go"}},
        \\ "word":{"type":"PATTERN","value":"[a-z]+"}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    const kw = symbolNamed(&gr, "kw");
    try testing.expect(!gr.isTerminal(kw));
    try testing.expectEqual(g.Shape.named, gr.shapeOf(kw));

    const wraps = onlyProduction(&gr, "kw");
    try testing.expectEqual(@as(usize, 1), wraps.rhs.len);
    try testing.expect(gr.isTerminal(wraps.rhs[0]));
    try testing.expectEqualStrings("go", gr.nameOf(wraps.rhs[0]));
    try testing.expectEqual(g.Shape.anonymous, gr.shapeOf(wraps.rhs[0]));

    // The point of the whole exercise: one terminal for those bytes, so the
    // arm that wants the bare `"go"` reaches the same symbol `kw` wraps.
    const arms = gr.productionsOf(symbolNamed(&gr, "doc"));
    try testing.expectEqual(wraps.rhs[0], gr.productions[arms[0]].rhs[0]);
}

test "two rules spelling one token both wrap it, and neither is named after it" {
    // It is the count that decides, not the anonymity: with no inline spelling
    // anywhere, tree-sitter still mints an `anon_sym_go` neither rule is named
    // after and reduces `kwa` and `kwb` alike.
    const src =
        \\{"name":"t","rules":{"doc":{"type":"CHOICE","members":[
        \\ {"type":"SEQ","members":[{"type":"SYMBOL","name":"kwa"},{"type":"STRING","value":"!"}]},
        \\ {"type":"SEQ","members":[{"type":"SYMBOL","name":"kwb"},{"type":"STRING","value":"?"}]}]},
        \\ "kwa":{"type":"TOKEN","content":{"type":"STRING","value":"go"}},
        \\ "kwb":{"type":"TOKEN","content":{"type":"STRING","value":"go"}}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    const a = onlyProduction(&gr, "kwa");
    const b = onlyProduction(&gr, "kwb");
    try testing.expect(!gr.isTerminal(symbolNamed(&gr, "kwa")));
    try testing.expect(!gr.isTerminal(symbolNamed(&gr, "kwb")));
    try testing.expectEqual(a.rhs[0], b.rhs[0]);
    try testing.expectEqualStrings("go", gr.nameOf(a.rhs[0]));
}

test "one spelling at two standings is two terminals wearing one name" {
    // The deduplication tree-sitter does not do: ask it for `'|'` beside
    // `token.immediate('|')` and its parser holds `anon_sym_PIPE` and
    // `anon_sym_PIPE2`, mapped onto one public symbol. Merging here would
    // union the two records instead, and `immediate` unions by `or`, so the
    // unrestricted `|` would inherit a restriction it never asked for and
    // stop lexing anywhere a token had not just ended.
    const src =
        \\{"name":"t","rules":{"doc":{"type":"CHOICE","members":[
        \\ {"type":"STRING","value":"|"},
        \\ {"type":"IMMEDIATE_TOKEN","content":{"type":"STRING","value":"|"}},
        \\ {"type":"TOKEN","content":{"type":"PREC","value":2,
        \\   "content":{"type":"STRING","value":"|"}}}]}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    const rules = gr.productionsOf(symbolNamed(&gr, "doc"));
    try testing.expectEqual(@as(usize, 3), rules.len);
    const bare = gr.productions[rules[0]].rhs[0];
    const immediate = gr.productions[rules[1]].rhs[0];
    const ranked = gr.productions[rules[2]].rhs[0];
    try testing.expectEqual(@as(u32, 3), gr.terminal_count);
    for ([_]g.Symbol{ bare, immediate, ranked }) |sym| {
        try testing.expectEqualStrings("|", gr.nameOf(sym));
        try testing.expectEqual(g.Shape.anonymous, gr.shapeOf(sym));
    }
    try testing.expectEqual(g.Lexis{}, gr.lexisOf(bare));
    try testing.expectEqual(g.Lexis{ .immediate = true }, gr.lexisOf(immediate));
    try testing.expectEqual(g.Lexis{ .prec = 2 }, gr.lexisOf(ranked));
}

test "terminals are numbered where the grammar declares them" {
    // The last rung of the lexical tie-break is the lowest symbol id, so this
    // ordering is the difference between C reading `#include` and reading a
    // bare directive. Generate this shape and tree-sitter numbers it
    // `sym_ident` 1, `anon_sym_Z` 2, `sym_tok` 3, `sym_comment` 4, `sym_ext` 5:
    // the word hoisted to the front, then one walk over the rules in
    // declaration order descending into each body, then the externals. Note
    // `Z` beating `tok`: `doc` is declared first, so its *inline* atom outranks
    // the *name* of a rule declared after it. Interning every named rule up
    // front inverts precisely that pair.
    const src =
        \\{"name":"t","word":"ident","rules":{
        \\ "doc":{"type":"REPEAT1","content":{"type":"CHOICE","members":[
        \\  {"type":"STRING","value":"Z"},
        \\  {"type":"SYMBOL","name":"ident"},
        \\  {"type":"SYMBOL","name":"ext"},
        \\  {"type":"SYMBOL","name":"tok"}]}},
        \\ "tok":{"type":"PATTERN","value":"t[a-z]*"},
        \\ "ident":{"type":"PATTERN","value":"[a-z_]+"},
        \\ "comment":{"type":"PATTERN","value":"#[^\n]*"}},
        \\ "extras":[{"type":"PATTERN","value":"\\s"},{"type":"SYMBOL","name":"comment"}],
        \\ "externals":[{"type":"SYMBOL","name":"ext"}]}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    const order = [_][]const u8{ "ident", "Z", "tok", "comment", "ext" };
    var previous: g.Symbol = symbolNamed(&gr, order[0]);
    try testing.expect(gr.isTerminal(previous));
    for (order[1..]) |name| {
        const sym = symbolNamed(&gr, name);
        try testing.expect(gr.isTerminal(sym));
        try testing.expect(previous < sym);
        previous = sym;
    }
}

test "a rank ranks the token only from inside one" {
    // Where the `prec` sits decides what it ranks. Generate both spellings and
    // tree-sitter answers plainly: `x: prec(-1, ';')` leaves one
    // `anon_sym_SEMI` and emits `REDUCE(sym_x, 1)`, so the rule is a
    // nonterminal wrapping the shared token; `x: token(prec(-1, ';'))` puts
    // `sym_x` among the terminals with no reduction at all, a second token
    // beside the first. Reading a rank from outside the `token` would collapse
    // that distinction and take ruby's `empty_statement` off the shared `;`.
    const src =
        \\{"name":"t","rules":{"doc":{"type":"CHOICE","members":[
        \\ {"type":"STRING","value":";"},
        \\ {"type":"SYMBOL","name":"outside"},
        \\ {"type":"SYMBOL","name":"inside"}]},
        \\ "outside":{"type":"PREC","value":2,"content":{"type":"STRING","value":";"}},
        \\ "inside":{"type":"TOKEN","content":{"type":"PREC","value":2,
        \\   "content":{"type":"STRING","value":";"}}}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    // Two terminals, not three: the outside rank never reached the key.
    try testing.expectEqual(@as(u32, 2), gr.terminal_count);

    const outside = symbolNamed(&gr, "outside");
    try testing.expect(!gr.isTerminal(outside));
    const shared = onlyProduction(&gr, "outside").rhs[0];
    try testing.expectEqual(g.Lexis{}, gr.lexisOf(shared));

    const inside = symbolNamed(&gr, "inside");
    try testing.expect(gr.isTerminal(inside));
    try testing.expectEqual(g.Lexis{ .prec = 2 }, gr.lexisOf(inside));
}

test "a dynamic rank reaches the production and stops there" {
    // `prec.dynamic` is the only rank a production gets one of, and the only
    // one the table must never see. Generate this and tree-sitter emits
    // `REDUCE(sym_a, 2, -5, …)` beside a plain `REDUCE(sym_b, 2, 0, …)` - the
    // third argument being the per-production dynamic rank - while both cells
    // keep both actions, because a dynamic rank resolves nothing at table time.
    //
    // The value read is the inner `-5`, not the outer `2` and not their sum.
    // Swapping the two numbers between the layers still generates `-5`, so the
    // rule is the loudest declaration in the body, whichever layer wrote it.
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"CHOICE","members":[
        \\  {"type":"SYMBOL","name":"a"},{"type":"SYMBOL","name":"b"}]},
        \\ "a":{"type":"PREC_DYNAMIC","value":2,"content":{"type":"SEQ","members":[
        \\   {"type":"STRING","value":"x"},
        \\   {"type":"PREC_DYNAMIC","value":-5,"content":{"type":"STRING","value":"y"}}]}},
        \\ "b":{"type":"SEQ","members":[
        \\   {"type":"STRING","value":"x"},{"type":"STRING","value":"y"}]}},
        \\ "conflicts":[["a","b"]]}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    const a = onlyProduction(&gr, "a");
    try testing.expectEqual(@as(i16, -5), a.dynamic);
    try testing.expectEqual(@as(i16, 0), onlyProduction(&gr, "b").dynamic);

    // And it stayed out of the static rank on every step it passed over. A
    // dynamic rank that leaked into `Step.prec` would resolve the very cell it
    // exists to leave forked, deleting the reading it was written to rank.
    for (a.steps) |s| try testing.expectEqual(g.Prec.none, s.prec);
}

test "a dynamic rank belongs to the production, in every shape one is written" {
    // The four wrappers `prec.dynamic` is written around in the pinned
    // grammars. Generated, tree-sitter emits `REDUCE(sym_two, 2, 3, …)` beside
    // `REDUCE(sym_two, 2, -1, …)` - one symbol, two productions, two different
    // ranks, which is why this cannot live on the symbol - plus `sym_plain` at
    // 0, `sym_righty` at -10 through an associativity wrapper, and `sym_member`
    // at 2 from a rank written around one member of a sequence.
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"CHOICE","members":[
        \\  {"type":"SYMBOL","name":"two"},{"type":"SYMBOL","name":"plain"},
        \\  {"type":"SYMBOL","name":"righty"},{"type":"SYMBOL","name":"member"}]},
        \\ "two":{"type":"CHOICE","members":[
        \\  {"type":"PREC_DYNAMIC","value":3,"content":{"type":"SEQ","members":[
        \\    {"type":"STRING","value":"p"},{"type":"STRING","value":"q"}]}},
        \\  {"type":"PREC_DYNAMIC","value":-1,"content":{"type":"SEQ","members":[
        \\    {"type":"STRING","value":"p"},{"type":"STRING","value":"r"}]}}]},
        \\ "plain":{"type":"SEQ","members":[
        \\   {"type":"STRING","value":"p"},{"type":"STRING","value":"q"}]},
        \\ "righty":{"type":"PREC_DYNAMIC","value":-10,"content":{
        \\   "type":"PREC_RIGHT","value":1,"content":{"type":"SEQ","members":[
        \\     {"type":"STRING","value":"s"},{"type":"STRING","value":"t"}]}}},
        \\ "member":{"type":"SEQ","members":[
        \\   {"type":"STRING","value":"m"},
        \\   {"type":"PREC_DYNAMIC","value":2,"content":{"type":"STRING","value":"n"}}]}},
        \\ "conflicts":[["two","plain"]]}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    const two = gr.productionsOf(symbolNamed(&gr, "two"));
    try testing.expectEqual(@as(usize, 2), two.len);
    var ranks = [_]i16{ gr.productions[two[0]].dynamic, gr.productions[two[1]].dynamic };
    std.mem.sort(i16, &ranks, {}, std.sort.asc(i16));
    try testing.expectEqualSlices(i16, &.{ -1, 3 }, &ranks);

    try testing.expectEqual(@as(i16, 0), onlyProduction(&gr, "plain").dynamic);
    try testing.expectEqual(@as(i16, -10), onlyProduction(&gr, "righty").dynamic);

    // The static wrapper underneath still ranks its steps; the two numbers pass
    // through each other rather than one standing in for the other.
    for (onlyProduction(&gr, "righty").steps) |s| {
        try testing.expectEqual(g.Assoc.right, s.assoc);
    }

    // Written around one member, carried by the whole body: the reading is what
    // a dynamic rank ranks, and `m n` is the reading.
    try testing.expectEqual(@as(i16, 2), onlyProduction(&gr, "member").dynamic);
}
