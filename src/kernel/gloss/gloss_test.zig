//! The compiler against a real pressed grammar, because the interesting half
//! is the resolution and a hand-built symbol table cannot get that wrong.
//!
//! Everything here runs on the committed `test/grammar/json.json` fixture that
//! `press/docket` already presses, so the ids a query resolves to are the ids
//! the folio actually wrote. The eighty-two-file corpus is the acceptance rung
//! (`bench/rungs/gloss`), not a test: it needs `upstream/grammars/` fetched,
//! and a suite that fails in a fresh clone is a suite people stop reading.

const std = @import("std");
const gloss = @import("gloss.zig");
const lemma = @import("lemma.zig");
const rubric = @import("rubric.zig");
const sift = @import("sift.zig");
const stencil = @import("stencil.zig");
const folio = @import("../../folio/folio.zig");
const press = @import("../../press/press.zig");

const gpa = std.testing.allocator;

/// The one symbol a step names, asserting on the way past that it names exactly
/// one. A step carries a SET of symbols, because a spelling can be several; in
/// this fixture every spelling asked about below is one, and saying so is a
/// stronger claim than reading the first and moving on.
fn sole(p: stencil.Program, s: stencil.Step) !u32 {
    try std.testing.expectEqual(1, s.kinds.len);
    return p.refAt(s.kinds.off);
}

/// A pressed json folio and the index over it, which is what every test below
/// actually wants.
const Board = struct {
    bytes: []align(folio.align_bytes) u8,
    f: folio.Folio,
    l: gloss.Lemma,

    fn of() !Board {
        var gr = try press.treeSitter(gpa, @embedFile("json_grammar"));
        defer gr.deinit();
        var built = try press.tables(gpa, &gr);
        defer built.deinit();
        // A folio rather than the `Grammar` straight out of the press: the
        // artifact is what a query is compiled against in the real path, and
        // the ids only agree if that is what the test uses too.
        const bytes = try folio.pack(gpa, &gr, &built);
        errdefer gpa.free(bytes);

        var b: Board = .{ .bytes = bytes, .f = try folio.open(bytes), .l = undefined };
        b.l = try gloss.index(gpa, &b.f);
        return b;
    }

    fn deinit(b: *Board) void {
        b.l.deinit();
        gpa.free(b.bytes);
        b.* = undefined;
    }

    fn compile(b: *Board, src: []const u8) !gloss.Compiled {
        return gloss.compile(gpa, &b.l, src, null);
    }
};

test "lemma: every symbol name resolves to the id the folio wrote" {
    var b = try Board.of();
    defer b.deinit();

    var checked: u32 = 0;
    for (0..b.f.symbolCount()) |i| {
        const sym: u32 = @intCast(i);
        const sort: lemma.Sort = switch (b.f.shapeOf(sym)) {
            .named => .kind,
            .anonymous => .literal,
            .hidden => .category,
            .invented => continue,
        };
        // A duplicate name resolves to the first symbol that claimed it, so the
        // round trip is on the name rather than on the id.
        const got = b.l.lookup(b.f.nameOf(sym), sort).?;
        try std.testing.expectEqualStrings(b.f.nameOf(sym), b.f.nameOf(got));
        checked += 1;
    }
    try std.testing.expect(checked > 0);
}

test "lemma: json's pair carries a key field and nothing else does" {
    var b = try Board.of();
    defer b.deinit();

    // json writes `key:` and `value:` on `pair`'s own children and writes no
    // field anywhere else, which makes it the sharpest available check on the
    // closure: a walk that leaked a field upward would put `key` on `object`
    // (which holds the pair) and on `document` (which holds the object through
    // a hidden `_value`), and both are one splice away.
    const pair = b.l.lookup("pair", .kind).?;
    const key = b.l.field("key").?;
    const value = b.l.field("value").?;
    try std.testing.expect(b.l.carries(pair, key));
    try std.testing.expect(b.l.carries(pair, value));
    for ([_][]const u8{ "object", "document", "array", "string" }) |name| {
        const sym = b.l.lookup(name, .kind).?;
        try std.testing.expect(!b.l.carries(sym, key));
        try std.testing.expect(!b.l.carries(sym, value));
    }
}

test "lemma: json's one supertype has the seven members its choice names" {
    var b = try Board.of();
    defer b.deinit();

    // `_value` is hidden and emits no node, so nothing in a tree is ever a
    // `_value` - which is exactly why the membership has to be derived. The
    // seven are the arms of its own CHOICE.
    const value = b.l.lookup("_value", .category).?;
    for ([_][]const u8{ "object", "array", "number", "string", "true", "false", "null" }) |name| {
        const sym = b.l.lookup(name, .kind) orelse b.l.lookup(name, .literal).?;
        try std.testing.expect(b.l.member(value, sym));
    }
    // And the relation discriminates: `pair` is reachable under `_value` only
    // through `object`, so it is not a member.
    try std.testing.expect(!b.l.member(value, b.l.lookup("pair", .kind).?));
}

test "lemma: a field lands on the kind that absorbed the splice" {
    var b = try Board.of();
    defer b.deinit();

    // `pair` writes `key:` and `value:` on its own children, so this is the
    // easy half. The hard half is that json's `_value` is hidden: `document`
    // holds an object it never names directly, and the closure has to see it.
    const document = b.l.lookup("document", .kind).?;
    const object = b.l.lookup("object", .kind).?;
    try std.testing.expect(b.l.admits(document, object));
}

test "gloss: a query resolves names to the ids the folio wrote" {
    var b = try Board.of();
    defer b.deinit();

    var c = try b.compile("(pair key: (string) @name) @entry");
    defer c.deinit();

    const p = c.view().?;
    try std.testing.expectEqual(1, p.patternCount());
    const root = p.stepAt(p.patternAt(0).root);
    try std.testing.expectEqual(stencil.Op.node, root.op);
    try std.testing.expectEqual(b.l.lookup("pair", .kind).?, try sole(p, root));
    try std.testing.expectEqual(1, root.kids.len);

    const kid = p.stepAt(p.refAt(root.kids.off));
    try std.testing.expectEqual(b.l.field("key").?, kid.field);
    try std.testing.expectEqualStrings("name", p.captureAt(p.refAt(kid.captures.off)));
    try std.testing.expectEqualStrings("entry", p.captureAt(p.refAt(root.captures.off)));
}

test "gloss: an anonymous literal resolves to its own symbol" {
    var b = try Board.of();
    defer b.deinit();

    var c = try b.compile("(object \"{\" @open)");
    defer c.deinit();

    const p = c.view().?;
    const kid = p.stepAt(p.refAt(p.stepAt(p.patternAt(0).root).kids.off));
    try std.testing.expectEqual(stencil.Op.literal, kid.op);
    try std.testing.expectEqualStrings("{", b.f.nameOf(try sole(p, kid)));
}

test "gloss: an unknown name is refused, not silently matched against nothing" {
    var b = try Board.of();
    defer b.deinit();

    try std.testing.expectError(gloss.Error.QueryUnknownKind, b.compile("(binary_expresion) @x"));
    try std.testing.expectError(gloss.Error.QueryUnknownField, b.compile("(pair kee: (string))"));
    try std.testing.expectError(gloss.Error.QueryUnknownLiteral, b.compile("(object \"<<<\")"));
}

test "gloss: the name a refusal reports outlives the reader that found it" {
    var b = try Board.of();
    defer b.deinit();

    // The bug this pins was invisible to every test above, because none of them
    // read `fault.name` - and it was not a wrong name, it was freed memory.
    // `compile` frees the rubric's arena on its way out, a literal's unescaped
    // text lives in that arena, so the one refusal that names a literal handed
    // back a slice of released memory. It printed as blanks against a real
    // grammar. Asserted here against `src`'s own address range rather than by
    // comparing the text, since the text is what read *correctly* right up
    // until the allocator reused the page.
    const src = "(object \"<<<\")";
    var fault: gloss.Fault = .{};
    try std.testing.expectError(gloss.Error.QueryUnknownLiteral, gloss.compile(gpa, &b.l, src, &fault));
    try std.testing.expect(fault.name.len > 0);
    const lo = @intFromPtr(src.ptr);
    const at = @intFromPtr(fault.name.ptr);
    try std.testing.expect(at >= lo and at + fault.name.len <= lo + src.len);
    // Quotes and all, so a reader can tell which of the two namespaces was
    // searched - `"<<<"` is a token that does not exist, not a rule.
    try std.testing.expectEqualStrings("\"<<<\"", fault.name);

    // A name written as a bare word was always source-backed and has to stay
    // that way: the repair must not start re-cutting every refusal from the
    // first quote it can find, which for this query is nowhere.
    var word: gloss.Fault = .{};
    const other = "(binary_expresion) @x";
    try std.testing.expectError(gloss.Error.QueryUnknownKind, gloss.compile(gpa, &b.l, other, &word));
    try std.testing.expectEqualStrings("binary_expresion", word.name);
}

test "gloss: a field this kind never carries is dead, and says where" {
    var b = try Board.of();
    defer b.deinit();

    // `key` is a real field and `document` is a real kind. Neither name is
    // wrong; the combination cannot occur, and that is the check tree-sitter
    // does not do.
    var c = try b.compile("(document key: (string)) @x");
    defer c.deinit();

    try std.testing.expectEqual(1, c.dead.len);
    try std.testing.expectEqual(gloss.Cause.field_not_carried, c.dead[0].cause);
    try std.testing.expect(c.view().?.patternAt(0).dead());
}

test "gloss: a live pattern is not reported dead" {
    var b = try Board.of();
    defer b.deinit();

    var c = try b.compile("(pair key: (string) @k value: (_) @v) @p");
    defer c.deinit();

    try std.testing.expectEqual(0, c.dead.len);
    try std.testing.expect(!c.view().?.patternAt(0).dead());
}

test "gloss: the core four compile, and the rest are carried" {
    var b = try Board.of();
    defer b.deinit();

    var c = try b.compile(
        \\((string) @s (#match? @s "^\"[a-z]+\"$"))
        \\((string) @s (#eq? @s "\"id\""))
        \\((string) @a (string) @c (#not-eq? @a @c))
        \\((string) @s (#any-of? @s "\"a\"" "\"b\""))
        \\((string) @s (#set! priority 105) (#lua-match? @s "%a"))
    );
    defer c.deinit();

    const p = c.view().?;
    try std.testing.expectEqual(5, p.patternCount());
    try std.testing.expectEqual(2, c.opaque_predicates);

    const want = [_]sift.Op{ .match, .eq_text, .not_eq_capture, .any_of };
    for (want, 0..) |op, i| {
        const pat = p.patternAt(@intCast(i));
        try std.testing.expectEqual(1, pat.preds.len);
        try std.testing.expectEqual(op, p.predicateAt(pat.preds.off).op);
    }

    // The directive keeps its spelling, because that is all a host has to go on.
    const last = p.patternAt(4);
    try std.testing.expectEqual(2, last.preds.len);
    try std.testing.expectEqualStrings("set!", p.predicateAt(last.preds.off).name);
    try std.testing.expectEqual(sift.Op.opaque_meta, p.predicateAt(last.preds.off).op);
    try std.testing.expectEqualStrings("lua-match?", p.predicateAt(last.preds.off + 1).name);
}

test "gloss: a regex the engine will not take is refused at compile time" {
    var b = try Board.of();
    defer b.deinit();

    try std.testing.expectError(sift.Error.QueryBadRegex, b.compile(
        \\((string) @s (#match? @s "[unclosed"))
    ));
    try std.testing.expectError(sift.Error.QueryPredicateArity, b.compile(
        \\((string) @s (#eq? @s))
    ));
}

test "gloss: a core predicate may not name a capture the pattern never bound" {
    var b = try Board.of();
    defer b.deinit();

    try std.testing.expectError(gloss.Error.QueryUnknownCapture, b.compile(
        \\((string) @s (#eq? @nowhere "x"))
    ));
    // An opaque one may, because its vocabulary is not ours.
    var c = try b.compile(
        \\((string) @s (#is-not? @elsewhere local))
    );
    defer c.deinit();
    try std.testing.expectEqual(1, c.opaque_predicates);
}

test "sift: the policy is a closed core and an open tail" {
    // The written-down half of the policy, checked rather than described. Five
    // spellings filter and are ours to run; everything else - directives the
    // host reads, and the four Neovim extensions in the real corpus whose
    // semantics live in an editor - is carried under its own name so a
    // `highlights.scm` still loads.
    const core = [_][]const u8{ "eq?", "not-eq?", "match?", "not-match?", "any-of?" };
    for (core) |name| try std.testing.expect(!sift.directive(name));

    const carried = [_][]const u8{
        "set!",          "strip!",     "offset!",    "select-adjacent!",
        "set-adjacent!", "lua-match?", "is-not?",    "has-ancestor?",
        "not-kind-eq?",  "contains?",  "any-eq?",    "vim-match?",
    };
    for (carried) |name| {
        const got = try sift.read(gpa, .{ .name = name, .args = &.{}, .at = 0 });
        try std.testing.expectEqual(sift.Op.opaque_meta, got.op);
        try std.testing.expectEqualStrings(name, got.name);
        try std.testing.expect(!got.op.core());
    }
}

test "sift: a core predicate is resolved by the shape of its arguments" {
    // `#eq?` is two predicates wearing one name: capture-to-text and
    // capture-to-capture. Deciding which at compile time is the point - a
    // matcher that had to look at the argument per candidate would be doing the
    // parse tree-sitter does at runtime, one match at a time.
    const cap: rubric.Arg = .{ .capture = "s" };
    const txt: rubric.Arg = .{ .text = "x" };

    try std.testing.expectEqual(sift.Op.eq_text, (try sift.read(gpa, .{
        .name = "eq?",
        .args = &.{ cap, txt },
        .at = 0,
    })).op);
    try std.testing.expectEqual(sift.Op.eq_capture, (try sift.read(gpa, .{
        .name = "eq?",
        .args = &.{ cap, cap },
        .at = 0,
    })).op);
    // Arity is checked here rather than at the match, for the same reason.
    try std.testing.expectError(sift.Error.QueryPredicateArity, sift.read(gpa, .{
        .name = "any-of?",
        .args = &.{cap},
        .at = 0,
    }));
    // And so is the shape: the first argument of every core predicate names a
    // capture, and a literal there is a query that can never mean anything.
    try std.testing.expectError(sift.Error.QueryPredicateShape, sift.read(gpa, .{
        .name = "match?",
        .args = &.{ txt, txt },
        .at = 0,
    }));
}

test "stencil: the reader refuses everything the writer cannot have written" {
    var b = try Board.of();
    defer b.deinit();

    var c = try b.compile("(pair key: (string) @k) @p");
    defer c.deinit();
    try std.testing.expect(c.view() != null);

    try std.testing.expect(stencil.read(&.{}) == null);
    try std.testing.expect(stencil.read(c.bytes[0 .. c.bytes.len - 1]) == null);

    // One byte of the tag, and one of a count. Both have to be refused, and the
    // second is the one a truncated write would produce.
    const spoiled = try gpa.dupe(u8, c.bytes);
    defer gpa.free(spoiled);
    spoiled[0] +%= 1;
    try std.testing.expect(stencil.read(spoiled) == null);
    spoiled[0] = c.bytes[0];
    spoiled[12] +%= 1;
    try std.testing.expect(stencil.read(spoiled) == null);
}

test "gloss: a whole highlights-shaped query round trips through the section" {
    var b = try Board.of();
    defer b.deinit();

    var c = try b.compile(
        \\(pair key: (string) @property)
        \\(array "," @punctuation.delimiter)
        \\[ (true) (false) (null) ] @constant.builtin
        \\(document (_) @root)
        \\((string) @string (#match? @string "^\"[A-Z]"))
    );
    defer c.deinit();

    const p = c.view().?;
    try std.testing.expectEqual(5, p.patternCount());
    try std.testing.expectEqual(0, c.dead.len);

    // A choice is one position with three readings, so its own step plus three.
    const alt = p.stepAt(p.patternAt(2).root);
    try std.testing.expectEqual(stencil.Op.choice, alt.op);
    try std.testing.expectEqual(3, alt.kids.len);

    // `(_)` is a node with no kind, which is not the same step as a bare `_`.
    const any = p.stepAt(p.refAt(p.stepAt(p.patternAt(3).root).kids.off));
    try std.testing.expectEqual(stencil.Op.node, any.op);
    try std.testing.expectEqual(0, any.kinds.len);
    try std.testing.expectEqual(stencil.none, any.alias);
    try std.testing.expect(!any.pinned());
}

test "folio: a compiled query survives the section it is written into" {
    // The whole reason the program is pressed rather than parsed: this is the
    // second process, holding nothing but bytes, and it asks the same questions
    // of the same ids without seeing a `.scm` file.
    var gr = try press.treeSitter(gpa, @embedFile("json_grammar"));
    defer gr.deinit();
    var built = try press.tables(gpa, &gr);
    defer built.deinit();

    const bare = try folio.pack(gpa, &gr, &built);
    defer gpa.free(bare);
    var first = try folio.open(bare);
    var l = try gloss.index(gpa, &first);
    defer l.deinit();
    var c = try gloss.compile(gpa, &l, "(pair key: (string) @property) @entry", null);
    defer c.deinit();

    const with = try folio.impose.packWith(gpa, &gr, &built, .{ .gloss = c.bytes });
    defer gpa.free(with);
    const f = try folio.open(with);

    try std.testing.expectEqual(c.bytes.len, f.gloss().len);
    const p = stencil.read(f.gloss()).?;
    try std.testing.expectEqual(1, p.patternCount());
    const root = p.stepAt(p.patternAt(0).root);
    try std.testing.expectEqual(l.lookup("pair", .kind).?, try sole(p, root));
    try std.testing.expectEqualStrings("property", p.captureAt(p.refAt(
        p.stepAt(p.refAt(root.kids.off)).captures.off,
    )));

    // And the folio without one is still a folio - an empty section is the
    // normal answer, not a missing one.
    try std.testing.expectEqual(0, first.gloss().len);
    try std.testing.expect(stencil.read(first.gloss()) == null);
}
