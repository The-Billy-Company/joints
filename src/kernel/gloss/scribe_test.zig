//! The matcher against a real pressed grammar and a real parse.
//!
//! Every expectation below was derived from `test/grammar/json.json` and from
//! tree-sitter's query notation, not captured from a run. The two facts they all
//! rest on, and which are worth having in one place:
//!
//!   - `{"a": 1, "b": true}` is nineteen bytes and parses to `document` over
//!     `object` over two `pair`s. `document: $ => $._value` and `_value` is
//!     hidden, so the document's one child is the object itself and the two
//!     share a span. A `pair` is `key: (string)`, `":"`, `value: (_value)`, and
//!     `_value` splices, so the field lands on whatever it spliced.
//!   - `string` is `seq('"', _string_content, '"')` with `_string_content`
//!     hidden, so a plain string's one named child is the `string_content` it
//!     spliced and its two quotes are anonymous children either side.
//!
//! Which fixes the ten named nodes, in the pre-order a walk hands back:
//! `document` and `object` at 0..19, `pair` at 1..7, `string` at 1..4,
//! `string_content` at 2..3, `number` at 6..7, `pair` at 9..18, `string` at
//! 9..12, `string_content` at 10..11, `true` at 14..18. Nine anonymous ones
//! stand between them - one `{`, one `}`, one `,`, two `:` and four `"`.

const std = @import("std");
const t = std.testing;

const gloss = @import("gloss.zig");
const folio = @import("../../folio/folio.zig");
const press = @import("../../press/press.zig");
const lex = @import("../lex/scanner.zig");
const quire = @import("../quire/quire.zig");

const gpa = t.allocator;

/// The document every test below that does not say otherwise runs on.
const doc = "{\"a\": 1, \"b\": true}";

/// A grammar pressed twice over: into the tables a parse walks, and into the
/// folio a query is compiled against. Both from the one `press.Grammar`, so the
/// ids a step carries are the ids the tree holds - which is the whole point of
/// running the matcher against a pressed artifact rather than a hand-built one.
///
/// Heap allocated because `Gather` borrows the grammar, the collection, the
/// tables and the scanner, all of which live in here.
const Bench = struct {
    gr: press.Grammar,
    built: press.Result,
    scanner: lex.Scanner,
    gather: quire.Gather,
    bytes: []align(folio.align_bytes) u8,
    f: folio.Folio,
    l: gloss.Lemma,

    fn of() !*Bench {
        const b = try gpa.create(Bench);
        errdefer gpa.destroy(b);
        b.gr = try press.treeSitter(gpa, @embedFile("json_grammar"));
        errdefer b.gr.deinit();
        b.built = try press.tables(gpa, &b.gr);
        errdefer b.built.deinit();
        b.scanner = (try lex.Scanner.compile(gpa, &b.gr)) orelse return error.NothingLexable;
        errdefer b.scanner.deinit();
        b.gather = try quire.Gather.init(gpa, &b.gr, &b.built.collection, &b.built.tables, &b.scanner);
        errdefer b.gather.deinit();
        b.bytes = try folio.pack(gpa, &b.gr, &b.built);
        errdefer gpa.free(b.bytes);
        b.f = try folio.open(b.bytes);
        b.l = try gloss.index(gpa, &b.f);
        return b;
    }

    fn deinit(b: *Bench) void {
        b.l.deinit();
        gpa.free(b.bytes);
        b.gather.deinit();
        b.scanner.deinit();
        b.built.deinit();
        b.gr.deinit();
        gpa.destroy(b);
    }
};

/// How a run may differ from the ordinary one. Defaults are what nearly every
/// test wants, so a test that needs something else says only that.
const Tweak = struct {
    /// The bytes to parse.
    on: []const u8 = doc,
    foreign: gloss.Foreign = .refuse,
    /// Whether the ask carries the grammar's index. Off for the one test that
    /// proves a bare supertype is refused rather than answered no.
    index: bool = true,
};

/// Every match of one query over one document, rendered as one line each:
/// the pattern's index, then `name=text` per capture in the order the match
/// bound them.
///
/// A rendering rather than a struct comparison because the interesting failures
/// are "one match too many" and "the right node under the wrong name", and both
/// read straight off a string diff. Caller owns the bytes.
fn glean(b: *Bench, scm: []const u8, tw: Tweak) ![]u8 {
    var q = try b.gather.run(tw.on);
    defer q.deinit();
    var compiled = try gloss.compile(gpa, &b.l, scm, null);
    defer compiled.deinit();

    var cur = try gloss.open(gpa, compiled.view().?, .{
        .q = &q,
        .src = tw.on,
        .index = if (tw.index) &b.l else null,
        .foreign = tw.foreign,
    });
    defer cur.deinit();

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var buf: [16]u8 = undefined;
    while (try cur.next()) |m| {
        if (out.items.len != 0) try out.append(gpa, '\n');
        try out.appendSlice(gpa, try std.fmt.bufPrint(&buf, "{d}", .{m.pattern}));
        for (m.captures) |cap| {
            const n = q.nodes[cap.node];
            try out.append(gpa, ' ');
            try out.appendSlice(gpa, compiled.view().?.captureAt(cap.id));
            try out.append(gpa, '=');
            try out.appendSlice(gpa, tw.on[n.start..n.end()]);
        }
    }
    return out.toOwnedSlice(gpa);
}

fn expect(b: *Bench, scm: []const u8, want: []const u8) !void {
    const got = try glean(b, scm, .{});
    defer gpa.free(got);
    try t.expectEqualStrings(want, got);
}

// ── the shapes a name can take ──

test "scribe: a kind matches every node of that kind, in reading order" {
    const b = try Bench.of();
    defer b.deinit();
    try expect(b, "(string_content) @c", "0 c=a\n0 c=b");
}

test "scribe: an anonymous node is reachable only by its own spelling" {
    const b = try Bench.of();
    defer b.deinit();
    // One comma in the document, and the `:` twice - which is the check that a
    // literal resolves to the terminal rather than to any rule of that name.
    try expect(b, "\",\" @x", "0 x=,");
    try expect(b, "\":\" @x", "0 x=:\n0 x=:");
}

test "scribe: `(_)` takes any named node and `_` takes any node at all" {
    const b = try Bench.of();
    defer b.deinit();
    // The ten named nodes of the header, spans and all.
    try expect(b, "(_) @a",
        \\0 a={"a": 1, "b": true}
        \\0 a={"a": 1, "b": true}
        \\0 a="a": 1
        \\0 a="a"
        \\0 a=a
        \\0 a=1
        \\0 a="b": true
        \\0 a="b"
        \\0 a=b
        \\0 a=true
    );
    // And the same ten plus the nine anonymous ones. Counted rather than
    // spelled: the point here is the count, and the order is pinned above.
    const all = try glean(b, "_ @a", .{});
    defer gpa.free(all);
    try t.expectEqual(19, std.mem.count(u8, all, "\n") + 1);
}

test "scribe: a bare supertype is a membership test, and needs the index to run" {
    const b = try Bench.of();
    defer b.deinit();
    // json's `_value` is hidden, so nothing in the tree is ever one. The five
    // members present are the object, both strings, the number and the `true` -
    // and the key string is one of them, because membership is a fact about the
    // symbol and not about the position it was written at.
    try expect(b, "(_value) @v",
        \\0 v={"a": 1, "b": true}
        \\0 v="a"
        \\0 v=1
        \\0 v="b"
        \\0 v=true
    );
    try t.expectError(error.QueryNeedsIndex, glean(b, "(_value) @v", .{ .index = false }));
}

// ── fields, anchors and the sibling run ──

test "scribe: a field prefix constrains which child answers" {
    const b = try Bench.of();
    defer b.deinit();
    try expect(b, "(pair key: (string) @k)", "0 k=\"a\"\n0 k=\"b\"");
    // The value side of the same two pairs is a number and a `true`, so a
    // `value:` on a string matches neither - which is the check that the field
    // is being read off the child rather than assumed from the position.
    try expect(b, "(pair value: (string) @v)", "");
}

test "scribe: an anchor pins a child to the end of the run it is written at" {
    const b = try Bench.of();
    defer b.deinit();
    try expect(b, "(object . (pair) @first)", "0 first=\"a\": 1");
    try expect(b, "(object (pair) @last .)", "0 last=\"b\": true");
    // Both at once says "exactly one pair", so it takes a one-pair object and
    // refuses this one. The `{` and `}` either side are anonymous and an anchor
    // steps over those; the second pair is named and it may not.
    try expect(b, "(object . (pair) @only .)", "");
    const one = try glean(b, "(object . (pair) @only .)", .{ .on = "{\"a\": 1}" });
    defer gpa.free(one);
    try t.expectEqualStrings("0 only=\"a\": 1", one);
}

test "scribe: a quantifier is greedy, so a capture under one binds the whole run" {
    const b = try Bench.of();
    defer b.deinit();
    // One match holding both pairs, not two matches holding one each. This is
    // the behaviour every doc-comment rule in the corpus is written against.
    try expect(b, "(object (pair)+ @p)", "0 p=\"a\": 1 p=\"b\": true");
    // And `*` at zero is a match with nothing bound, which is not the same
    // answer as no match.
    const empty = try glean(b, "(object (pair)* @p)", .{ .on = "{}" });
    defer gpa.free(empty);
    try t.expectEqualStrings("0", empty);
}

test "scribe: a choice takes whichever arm the node answers to, and binds it" {
    const b = try Bench.of();
    defer b.deinit();
    try expect(b, "[(number) (true)] @lit", "0 lit=1\n0 lit=true");
    // A kind named twice over two arms must not hand back the match twice: the
    // sieve files a pattern once per key however many arms reach it.
    try expect(b, "[(number) (number)] @lit", "0 lit=1");
}

test "scribe: a group is a run of siblings and is matched under a parent" {
    const b = try Bench.of();
    defer b.deinit();
    // Two pairs as siblings, which the one object satisfies once.
    try expect(b, "((pair) @x (pair) @y)", "0 x=\"a\": 1 y=\"b\": true");
}

// ── predicates ──

test "scribe: the core filters read a capture's own bytes" {
    const b = try Bench.of();
    defer b.deinit();
    try expect(b, "((string_content) @x (#eq? @x \"a\"))", "0 x=a");
    try expect(b, "((string_content) @x (#not-eq? @x \"a\"))", "0 x=b");
    try expect(b, "((string_content) @x (#any-of? @x \"b\" \"z\"))", "0 x=b");
    try expect(b, "((string_content) @x (#match? @x \"^[ab]$\"))", "0 x=a\n0 x=b");
    try expect(b, "((string_content) @x (#not-match? @x \"^a$\"))", "0 x=b");
}

test "scribe: `#eq?` between two captures compares the bytes, not the nodes" {
    const b = try Bench.of();
    defer b.deinit();
    const scm =
        "(pair key: (string (string_content) @k) " ++
        "value: (string (string_content) @v) (#eq? @k @v))";
    const same = try glean(b, scm, .{ .on = "{\"a\": \"a\"}" });
    defer gpa.free(same);
    try t.expectEqualStrings("0 k=a v=a", same);

    const differ = try glean(b, scm, .{ .on = "{\"a\": \"b\"}" });
    defer gpa.free(differ);
    try t.expectEqualStrings("", differ);
}

test "scribe: a directive holds and a foreign filter is the policy's business" {
    const b = try Bench.of();
    defer b.deinit();
    // `#set!` filters nothing, so it holds under the strictest policy there is.
    try expect(b, "((string_content) @x (#set! foo \"bar\"))", "0 x=a\n0 x=b");

    const lua = "((string_content) @x (#lua-match? @x \"%a\"))";
    try t.expectError(error.QueryOpaquePredicate, glean(b, lua, .{}));
    const admitted = try glean(b, lua, .{ .foreign = .admit });
    defer gpa.free(admitted);
    try t.expectEqualStrings("0 x=a\n0 x=b", admitted);
    const denied = try glean(b, lua, .{ .foreign = .deny });
    defer gpa.free(denied);
    try t.expectEqualStrings("", denied);
}

// ── the stream itself ──

test "scribe: matches come out in pattern order at each node" {
    const b = try Bench.of();
    defer b.deinit();
    try expect(b, "(number) @a\n(number) @b", "0 a=1\n1 b=1");
    // A pinned pattern and an open one are two ascending lists, merged - so the
    // open one still arrives after the pinned one it outnumbers.
    try expect(b, "(number) @a\n(true) @w",
        \\0 a=1
        \\1 w=true
    );
}

test "scribe: a match is handed over where it finishes, not where it begins" {
    const b = try Bench.of();
    defer b.deinit();
    // The pair pattern opens at byte 1, before the `string_content` at 2, and is
    // still handed over after it - because it is not settled until the number at
    // 6. Both `string_content`s bracket it for the same reason.
    try expect(b, "(pair key: (string) @k value: (number) @v)\n(string_content) @c",
        \\1 c=a
        \\0 k="a" v=1
        \\1 c=b
    );
}

test "scribe: two matches finishing together go to the one that opened higher" {
    const b = try Bench.of();
    defer b.deinit();
    // Both settle on the number at 6, and neither captures anything before it,
    // so the only thing separating them is that the pair pattern has been open
    // since byte 1. It is written second and comes out first, which is the whole
    // of the claim: the order is about the tree, not about the file.
    try expect(b, "(number) @n\n(pair value: (number) @v)", "1 v=1\n0 n=1");
}

test "scribe: a pattern the compiler proved dead is never tried" {
    const b = try Bench.of();
    defer b.deinit();
    // `string` carries no `key` field - only `pair` does - so the first pattern
    // cannot match anything, and the compiler says so before the walk starts.
    var compiled = try gloss.compile(gpa, &b.l, "(string key: (string_content)) @d\n(number) @n", null);
    defer compiled.deinit();
    try t.expectEqual(1, compiled.dead.len);
    try t.expectEqual(gloss.Cause.field_not_carried, compiled.dead[0].cause);
    try expect(b, "(string key: (string_content)) @d\n(number) @n", "1 n=1");
}

test "scribe: a group inside a choice is declined rather than guessed at" {
    const b = try Bench.of();
    defer b.deinit();
    var q = try b.gather.run(doc);
    defer q.deinit();
    var compiled = try gloss.compile(gpa, &b.l, "[((number)) (true)] @x", null);
    defer compiled.deinit();
    var cur = try gloss.open(gpa, compiled.view().?, .{ .q = &q, .src = doc, .index = &b.l });
    defer cur.deinit();

    var hits: u32 = 0;
    while (try cur.next()) |_| hits += 1;
    // The `(true)` arm still answers; the group arm consumes a run where a
    // choice is asking about one node, and saying so is the point.
    try t.expectEqual(1, hits);
    try t.expect(cur.declined > 0);
}
