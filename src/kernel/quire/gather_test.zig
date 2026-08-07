//! Tests for the tree a parse yields.
//!
//! Every expected s-expression here was derived by hand from the grammar and
//! from tree-sitter's node-naming rules, and none of it was captured from this
//! builder. That distinction is the only thing that makes these tests worth
//! running: an expectation copied out of the code under test proves the code
//! is deterministic and nothing else.
//!
//! The naming rules being applied, from `import.zig` and `grammar.zig`:
//!
//!   - A rule whose whole body is one lexical atom becomes a *terminal* under
//!     its own rule name, so json's `true`, `number` and `string_content` are
//!     leaves that print as `(true)`, `(number)`, `(string_content)`.
//!   - A bare string inside a rule is anonymous: visible, spelled as itself,
//!     invisible to a named-only walk.
//!   - A leading underscore hides a rule, and so does a `supertypes` entry.
//!     json's `_value` is both.
//!   - A repeat helper is invented, so a list contributes its elements to the
//!     host and no node of its own.
//!
//! The differential at the bottom is the other half: `walk/drive.zig` walks the
//! same automaton with no tree at all, so where the two disagree about a token
//! or a state, one of them is wrong.

const std = @import("std");
const t = std.testing;
const g = @import("../../press/grammar.zig");
const import = @import("../../press/import.zig");
const press = @import("../../press/press.zig");
const lex = @import("../lex/scanner.zig");
const drive = @import("../walk/drive.zig");
const quire = @import("quire.zig");

/// A grammar, its tables, a scanner, and both parse loops over them. Heap
/// allocated because `Gather` and `Drive` both borrow the other fields.
const Fixture = struct {
    gpa: std.mem.Allocator,
    gr: g.Grammar,
    built: press.Result,
    scanner: lex.Scanner,
    gather: quire.Gather,

    fn init(gpa: std.mem.Allocator, source: []const u8) !*Fixture {
        const f = try gpa.create(Fixture);
        errdefer gpa.destroy(f);
        f.gpa = gpa;
        f.gr = try import.treeSitter(gpa, source);
        errdefer f.gr.deinit();
        f.built = try press.tables(gpa, &f.gr);
        errdefer {
            f.built.tables.deinit();
            f.built.collection.deinit();
        }
        f.scanner = (try lex.Scanner.compile(gpa, &f.gr)) orelse return error.NothingLexable;
        errdefer f.scanner.deinit();
        f.gather = try quire.Gather.init(gpa, &f.gr, &f.built.collection, &f.built.tables, &f.scanner);
        return f;
    }

    fn deinit(f: *Fixture) void {
        const gpa = f.gpa;
        f.gather.deinit();
        f.scanner.deinit();
        f.built.tables.deinit();
        f.built.collection.deinit();
        f.gr.deinit();
        gpa.destroy(f);
    }

    fn parse(f: *Fixture, bytes: []const u8) !quire.Quire {
        return f.gather.run(bytes);
    }
};

/// Parse `bytes` and render the whole result, roots and all. A forest prints as
/// its roots separated by spaces, so a partial parse is legible rather than
/// silently truncated to its first tree.
fn render(f: *Fixture, bytes: []const u8, show: quire.Show) ![]u8 {
    var q = try f.parse(bytes);
    defer q.deinit();
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(t.allocator);
    for (q.roots, 0..) |r, i| {
        if (i != 0) try out.append(t.allocator, ' ');
        const one = try q.sexp(t.allocator, r, show);
        defer t.allocator.free(one);
        try out.appendSlice(t.allocator, one);
    }
    return out.toOwnedSlice(t.allocator);
}

fn expectTree(f: *Fixture, bytes: []const u8, show: quire.Show, want: []const u8) !void {
    const got = try render(f, bytes, show);
    defer t.allocator.free(got);
    try t.expectEqualStrings(want, got);
}

/// Extras, so the hand-written fixtures below can be written with spaces in
/// them. json brings its own.
const spaces = ",\"extras\":[{\"type\":\"PATTERN\",\"value\":\"\\\\s\"}]";

// ── json, the one grammar that reads to the end of a real file ──

const json_src = @embedFile("json_grammar");

/// The pieces every json expectation is built from. Spelled once, because
/// every one of them is a claim about the grammar and each claim should be
/// made in exactly one place.
///
///   - `string` is `seq('"', _string_content, '"')`, and `_string_content` is
///     hidden, so a plain string's one named child is the `string_content`
///     token it spliced in.
///   - `pair` files its key under `key` and its value under `value`, and the
///     value goes through the hidden `_value`, so the field lands on whatever
///     `_value` spliced.
const js = struct {
    const string = "(string (string_content))";
    const key = "key: " ++ string;

    fn pair(comptime value: []const u8) []const u8 {
        return "(pair " ++ key ++ " value: " ++ value ++ ")";
    }

    fn node(comptime name: []const u8, comptime kids: []const []const u8) []const u8 {
        comptime var out: []const u8 = "(" ++ name;
        inline for (kids) |k| out = out ++ " " ++ k;
        return out ++ ")";
    }
};

/// The tree `research/joinery/corpus/ledger.json` describes, transcribed
/// construct by construct from the file rather than captured from a run. Every
/// leaf is the grammar's answer for that literal: a quoted word is a `string`
/// holding one `string_content`, a bare integer is a `number`, and `true` and
/// `null` are terminals named after their own single-atom rules.
///
/// Last reconciled against the corpus at:
///   outliner 4d64f888c built 2026-08-04T14:59:37Z from . d839aa01b
///   repo 35f3da5f0+75
///
/// That line is here so the next person can tell staleness from breakage
/// without re-deriving it. If this test is red, first check whether the corpus
/// file moved since that commit; a transcription goes stale when the *file*
/// changes, which is not the same failure as the parser changing. Reconcile it
/// by reading the new construct out of the corpus and writing down what the
/// grammar says about it - never by pasting the `found:` output, which would
/// turn a spec into a snapshot of whatever we currently do.
const ledger_tree = blk: {
    const num = "(number)";
    // `{ "tag": …, "value": …, "note": … }`, with and without a note.
    const row = js.node("object", &.{ js.pair(js.string), js.pair(num), js.pair("(null)") });
    const noted = js.node("object", &.{ js.pair(js.string), js.pair(num), js.pair(js.string) });
    const tags = js.node("object", &.{ js.pair(num), js.pair(num), js.pair(num), js.pair(num) });
    // The three shapes of history entry: a seeded one, a totalled one, and the
    // push whose third value is an object rather than a scalar.
    const seeded = js.node("object", &.{
        js.pair(js.string),
        js.pair(js.string),
        js.pair(js.node("array", &.{ num, num, num })),
    });
    const totalled = js.node("object", &.{ js.pair(js.string), js.pair(js.string), js.pair(num) });
    const pushed = js.node("object", &.{
        js.pair(js.string),
        js.pair(js.string),
        js.pair(js.node("object", &.{ js.pair(js.string), js.pair(num) })),
    });
    // `"ledger receipt\n--------------\n"`. `_string_content` is
    // `repeat1(choice(string_content, escape_sequence))`, so the two `\n`
    // splice in as their own nodes between the runs of text - and the second
    // one ends the string, so no `string_content` follows it. The rule itself
    // is pinned independently on `"a\nb"` further down this file, which is why
    // this stays a transcription rather than becoming a snapshot.
    const banner = "(string (string_content) (escape_sequence) (string_content) (escape_sequence))";
    const ledger = js.node("object", &.{
        js.pair(js.string),
        js.pair(banner),
        js.pair("(true)"),
        js.pair(num),
        js.pair(js.node("array", &.{ row, noted, row, noted })),
        js.pair(tags),
        js.pair(js.node("array", &.{ seeded, totalled, pushed, totalled })),
    });
    break :blk js.node("document", &.{js.node("object", &.{js.pair(ledger)})});
};

test "quire: a json document is the values it holds, with no node for the repeat" {
    var f = try Fixture.init(t.allocator, json_src);
    defer f.deinit();

    // `document` is `repeat($._value)`, which lowers to an invented left
    // recursive helper. The helper is invisible, so the values land directly
    // under `document` and nothing named `document_repeat…` is ever on the
    // tree. `_value` is hidden twice over - underscore and supertype - so it
    // splices too, and what shows up is the `object` or `number` underneath.
    try expectTree(f, "1 2 3", .named, js.node("document", &.{ "(number)", "(number)", "(number)" }));
    // An empty document still exists: `document -> ε` is a real production.
    try expectTree(f, "", .named, "(document)");
}

test "quire: json's pair files its key and its value through a hidden symbol" {
    var f = try Fixture.init(t.allocator, json_src);
    defer f.deinit();

    // `field('value', $._value)` is the load-bearing case: the step splices, so
    // the field has to reach the child spliced in from it rather than staying
    // on a node that was never made.
    const doc = js.node("document", &.{js.node("object", &.{
        js.pair(js.node("array", &.{ "(number)", "(true)" })),
        js.pair("(null)"),
    })});
    try expectTree(f, "{\"a\": [1, true], \"b\": null}", .named, doc);
}

test "quire: the full json tree keeps its anonymous nodes, spelled as themselves" {
    var f = try Fixture.init(t.allocator, json_src);
    defer f.deinit();

    // What a query sees. The braces, the comma and the colon are visible and
    // unnamed; the quotes around a string are too, and they sit inside the
    // `string` node rather than beside it.
    try expectTree(f, "{\"a\":1}", .all,
        \\(document (object "{" (pair key: (string "\"" (string_content) "\"") ":" value: (number)) "}"))
    );
    try expectTree(f, "[]", .all, "(document (array \"[\" \"]\"))");
}

test "quire: an escape sequence is its own node, spliced in beside the text" {
    var f = try Fixture.init(t.allocator, json_src);
    defer f.deinit();

    // `_string_content` is `repeat1(choice(string_content, escape_sequence))`,
    // so its helper splices a run of alternating tokens into the `string`.
    const doc = js.node("document", &.{"(string (string_content) (escape_sequence) (string_content))"});
    try expectTree(f, "\"a\\nb\"", .named, doc);
    // An empty string takes the other alternative of `string` and holds
    // nothing at all - two anonymous quotes and no content.
    try expectTree(f, "\"\"", .named, "(document (string))");
    try expectTree(f, "\"\"", .all, "(document (string \"\\\"\" \"\\\"\"))");
}

test "quire: a node spans its own tokens and no further" {
    var f = try Fixture.init(t.allocator, json_src);
    defer f.deinit();

    const src = "  { \"ab\" : 12 }  ";
    var q = try f.parse(src);
    defer q.deinit();

    const doc = q.root().?;
    const object = q.children(doc)[0];
    // The object runs from its `{` to its `}`, so the leading and trailing
    // whitespace is outside it and the whitespace inside it is not.
    try t.expectEqualStrings("{ \"ab\" : 12 }", src[q.nodes[object].start..q.nodes[object].end()]);

    const pair = q.children(object)[1]; // after the `{`
    try t.expectEqualStrings("\"ab\" : 12", src[q.nodes[pair].start..q.nodes[pair].end()]);
    const string = q.children(pair)[0];
    try t.expectEqualStrings("\"ab\"", src[q.nodes[string].start..q.nodes[string].end()]);
    const content = q.children(string)[1];
    try t.expectEqualStrings("ab", src[q.nodes[content].start..q.nodes[content].end()]);
    try t.expectEqualStrings("string_content", q.name(content));
}

test "quire: a parse that stops early keeps its prefix and says where it stopped" {
    var f = try Fixture.init(t.allocator, json_src);
    defer f.deinit();

    // Nothing is papered over: the object never closed, so the tree is the
    // forest of what did complete and the stop names the reason.
    var q = try f.parse("[1, 2");
    defer q.deinit();
    try t.expectEqual(quire.Stop.truncated, q.stop);
    try t.expectEqual(@as(?quire.Ref, null), q.root());
    // Four nodes stand completed and nothing joins them: every reduction the
    // prefix can take has an invisible left-hand side (`_value` is hidden, the
    // list helper is invented), and the one visible node - the `array` - needs
    // the `]` that never came.
    try t.expectEqual(@as(usize, 4), q.roots.len);
    for (q.roots, [_][]const u8{ "[", "number", ",", "number" }) |r, want| {
        try t.expectEqualStrings(want, q.name(r));
    }

    // A token that lexes and cannot go here names itself and the state.
    var bad = try f.parse("[1 2]");
    defer bad.deinit();
    try t.expectEqualStrings("number", f.gr.nameOf(bad.stop.unexpected.symbol));
    try t.expectEqual(@as(u32, 3), bad.stop.unexpected.at);
}

// ── the recipe's hard cases, on grammars small enough to read ──

test "quire: an alias renames the child at the site that renamed it, and only there" {
    // The same symbol, reached twice, wearing two names - C's
    // `_old_style_function_definition` in miniature. Hang the rename on the
    // symbol and both sites collapse onto whichever was read last.
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"REPEAT1","content":{"type":"CHOICE","members":[
        \\  {"type":"SEQ","members":[{"type":"STRING","value":"a"},{"type":"SYMBOL","name":"thing"}]},
        \\  {"type":"SEQ","members":[{"type":"STRING","value":"b"},
        \\    {"type":"ALIAS","named":true,"value":"other","content":{"type":"SYMBOL","name":"thing"}}]}]}},
        \\ "thing":{"type":"PATTERN","value":"[0-9]+"}}
    ++ spaces ++ "}";
    var f = try Fixture.init(t.allocator, src);
    defer f.deinit();

    try expectTree(f, "a 1 b 2", .named, "(doc (thing) (other))");
    try expectTree(f, "a 1 b 2", .all, "(doc \"a\" (thing) \"b\" (other))");
}

test "quire: an alias declared unnamed is spelled as itself, not matched by name" {
    // `named: false` is the difference between a query writing `(other)` and
    // one writing `\"other\"`, so the alias has to carry it onto the node.
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"SEQ","members":[{"type":"STRING","value":"a"},
        \\  {"type":"ALIAS","named":false,"value":"other","content":{"type":"SYMBOL","name":"thing"}}]},
        \\ "thing":{"type":"PATTERN","value":"[0-9]+"}}
    ++ spaces ++ "}";
    var f = try Fixture.init(t.allocator, src);
    defer f.deinit();

    try expectTree(f, "a 1", .named, "(doc)");
    try expectTree(f, "a 1", .all, "(doc \"a\" \"other\")");
}

test "quire: an alias over a hidden symbol mints the node its splice hangs under" {
    // The reason a rename is checked before the symbol's own shape: the symbol
    // is spliced everywhere else and appears here, wrapping what it hid.
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"CHOICE","members":[
        \\  {"type":"SEQ","members":[{"type":"STRING","value":"a"},{"type":"SYMBOL","name":"_inner"}]},
        \\  {"type":"SEQ","members":[{"type":"STRING","value":"b"},
        \\    {"type":"ALIAS","named":true,"value":"group","content":{"type":"SYMBOL","name":"_inner"}}]}]},
        \\ "_inner":{"type":"SEQ","members":[{"type":"SYMBOL","name":"item"},{"type":"SYMBOL","name":"item"}]},
        \\ "item":{"type":"PATTERN","value":"[0-9]+"}}
    ++ spaces ++ "}";
    var f = try Fixture.init(t.allocator, src);
    defer f.deinit();

    // Unaliased, `_inner` splices its two items straight into `doc`.
    try expectTree(f, "a 1 2", .named, "(doc (item) (item))");
    // Aliased, the same two items sit under a node the author named here.
    try expectTree(f, "b 1 2", .named, "(doc (group (item) (item)))");
}

test "quire: a field on a spliced step reaches every child spliced in from it" {
    // The rule that is load-bearing rather than an edge case. `_pair` is
    // hidden, so the step that names it produces no node - and the field has
    // to land on both of the children it contributed instead of vanishing.
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"SEQ","members":[
        \\  {"type":"FIELD","name":"part","content":{"type":"SYMBOL","name":"_pair"}},
        \\  {"type":"STRING","value":"."}]},
        \\ "_pair":{"type":"SEQ","members":[{"type":"SYMBOL","name":"item"},{"type":"SYMBOL","name":"item"}]},
        \\ "item":{"type":"PATTERN","value":"[0-9]+"}}
    ++ spaces ++ "}";
    var f = try Fixture.init(t.allocator, src);
    defer f.deinit();

    try expectTree(f, "1 2 .", .named, "(doc part: (item) part: (item))");
}

test "quire: a field written inside a repeat reaches the elements, not the list" {
    // `repeat(seq(',', field('init', $.expression)))` is why the rule above
    // exists. The list helper is invisible; if the field stayed on the step
    // that named the list, nothing would carry it.
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"SEQ","members":[
        \\  {"type":"SYMBOL","name":"item"},
        \\  {"type":"REPEAT","content":{"type":"SEQ","members":[
        \\    {"type":"STRING","value":","},
        \\    {"type":"FIELD","name":"init","content":{"type":"SYMBOL","name":"item"}}]}}]},
        \\ "item":{"type":"PATTERN","value":"[0-9]+"}}
    ++ spaces ++ "}";
    var f = try Fixture.init(t.allocator, src);
    defer f.deinit();

    try expectTree(f, "1", .named, "(doc (item))");
    try expectTree(f, "1 , 2 , 3", .named, "(doc (item) init: (item) init: (item))");
}

test "quire: splicing is recursive, so a hidden rule inside a hidden rule leaves nothing" {
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_outer"},{"type":"STRING","value":"!"}]},
        \\ "_outer":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_inner"},{"type":"SYMBOL","name":"item"}]},
        \\ "_inner":{"type":"SEQ","members":[{"type":"SYMBOL","name":"item"},{"type":"SYMBOL","name":"item"}]},
        \\ "item":{"type":"PATTERN","value":"[0-9]+"}}
    ++ spaces ++ "}";
    var f = try Fixture.init(t.allocator, src);
    defer f.deinit();

    try expectTree(f, "1 2 3 !", .named, "(doc (item) (item) (item))");
    try expectTree(f, "1 2 3 !", .all, "(doc (item) (item) (item) \"!\")");
}

test "quire: an inline regex consumes bytes and contributes no node" {
    // tree-sitter files a bare `/regex/` written mid-rule as auxiliary, so it
    // is invisible - but the rule containing it still covers the bytes it ate.
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"SEQ","members":[
        \\  {"type":"SYMBOL","name":"item"},{"type":"PATTERN","value":"[!?]+"},{"type":"SYMBOL","name":"item"}]},
        \\ "item":{"type":"PATTERN","value":"[0-9]+"}}
    ++ spaces ++ "}";
    var f = try Fixture.init(t.allocator, src);
    defer f.deinit();

    try expectTree(f, "1 !? 2", .all, "(doc (item) (item))");
    var q = try f.parse("1 !? 2");
    defer q.deinit();
    try t.expectEqual(@as(u32, 0), q.nodes[q.root().?].start);
    try t.expectEqual(@as(u32, 6), q.nodes[q.root().?].len);
}

test "quire: no invented symbol ever reaches the tree, on a real grammar" {
    // The blunt version of the claim, swept rather than spot-checked: after a
    // whole json file, nothing on the tree is named after machinery the
    // importer invented or a rule the author hid.
    var f = try Fixture.init(t.allocator, json_src);
    defer f.deinit();
    var q = try f.parse("{\"a\": [1, {\"b\": \"c\\t\"}], \"d\": [true, false, null, -1.5e3]}");
    defer q.deinit();
    try t.expectEqual(quire.Stop.accepted, q.stop);

    for (0..q.nodes.len) |i| {
        const name = q.name(@intCast(i));
        try t.expect(std.mem.indexOf(u8, name, "_repeat") == null);
        try t.expect(std.mem.indexOf(u8, name, "_choice") == null);
        try t.expect(!std.mem.eql(u8, name, "_value"));
        try t.expect(!std.mem.eql(u8, name, "_string_content"));
        try t.expect(!std.mem.eql(u8, name, "$start"));
    }
}

test "quire: a child's parent is the node that claimed it" {
    var f = try Fixture.init(t.allocator, json_src);
    defer f.deinit();
    var q = try f.parse("[1]");
    defer q.deinit();

    const doc = q.root().?;
    try t.expectEqual(quire.none, q.nodes[doc].parent);
    const array = q.children(doc)[0];
    try t.expectEqual(doc, q.nodes[array].parent);
    for (q.children(array)) |c| try t.expectEqual(array, q.nodes[c].parent);
}

// ── extras, and the parent each one lands on ──

/// Extras with something visible in them. `comment` is
/// `token(seq('#', /[^\n]*/))`, and the rule itself is spelled once because
/// every grammar below needs it.
const asides =
    \\ "comment":{"type":"TOKEN","content":{"type":"SEQ","members":[
    \\  {"type":"STRING","value":"#"},{"type":"PATTERN","value":"[^\\n]*"}]}}}
++
    \\,"extras":[{"type":"PATTERN","value":"\\s"},{"type":"SYMBOL","name":"comment"}]}
;

test "quire: an extra between two symbols is theirs, and one after the last is not" {
    // The whole placement rule in one file. `# one` sits between the two items
    // of a pair, so the reduction that pops both takes it. `# two` sits after
    // the pair's last token, so that same reduction leaves it behind and the
    // list above claims it - which is why it comes out a sibling of the pairs
    // rather than the last child of the first one.
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"REPEAT1","content":{"type":"SYMBOL","name":"pair"}},
        \\ "pair":{"type":"SEQ","members":[{"type":"SYMBOL","name":"item"},{"type":"SYMBOL","name":"item"}]},
        \\ "item":{"type":"PATTERN","value":"[a-z]+"},
    ++ asides;
    var f = try Fixture.init(t.allocator, src);
    defer f.deinit();

    const pair = "(pair (item) (comment) (item))";
    try expectTree(f, "a # one\nb # two\nc # three\nd", .named, "(doc " ++ pair ++ " (comment) " ++ pair ++ ")");
}

test "quire: an extra sinks no deeper than the reduction that popped it" {
    // Nesting, and the two directions it can go wrong in. `# c` is inside the
    // braces because `}` still follows it; `# d` is outside them because
    // nothing of `inner` does. A rule that placed an extra by span alone would
    // put `# d` inside `inner` on the strength of `outer` being wider.
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"REPEAT1","content":{"type":"SYMBOL","name":"outer"}},
        \\ "outer":{"type":"SEQ","members":[{"type":"STRING","value":"["},
        \\  {"type":"SYMBOL","name":"inner"},{"type":"SYMBOL","name":"item"},{"type":"STRING","value":"]"}]},
        \\ "inner":{"type":"SEQ","members":[{"type":"STRING","value":"{"},
        \\  {"type":"SYMBOL","name":"item"},{"type":"STRING","value":"}"}]},
        \\ "item":{"type":"PATTERN","value":"[a-z]+"},
    ++ asides;
    var f = try Fixture.init(t.allocator, src);
    defer f.deinit();

    const inner = "(inner (comment) (item) (comment))";
    try expectTree(f, "[ # a\n{ # b\nx # c\n} # d\ny # e\n] # f\n", .named, "(doc (outer (comment) " ++ inner ++ " (comment) (item) (comment)) (comment))");
}

test "quire: an extra spliced in from a field-bearing step does not carry the field" {
    // A field is indexed by structural child, and an extra is not one. So the
    // rule that files every child a hidden step spliced in has to stop at the
    // comment that rode along with them.
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"SEQ","members":[
        \\  {"type":"FIELD","name":"part","content":{"type":"SYMBOL","name":"_pair"}},
        \\  {"type":"STRING","value":"."}]},
        \\ "_pair":{"type":"SEQ","members":[{"type":"SYMBOL","name":"item"},{"type":"SYMBOL","name":"item"}]},
        \\ "item":{"type":"PATTERN","value":"[a-z]+"},
    ++ asides;
    var f = try Fixture.init(t.allocator, src);
    defer f.deinit();

    try expectTree(f, "a # x\nb .", .named, "(doc part: (item) (comment) part: (item))");
}

test "quire: the extras nothing reduced over are the root's outermost children" {
    // Neither of these can reach a production. A leading extra sits under
    // every frame on the stack and a trailing one sits above the last, so no
    // reduction ever pops either - acceptance is what collects them.
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"REPEAT1","content":{"type":"SYMBOL","name":"group"}},
        \\ "group":{"type":"SEQ","members":[{"type":"STRING","value":"("},
        \\  {"type":"REPEAT","content":{"type":"SYMBOL","name":"item"}},{"type":"STRING","value":")"}]},
        \\ "item":{"type":"PATTERN","value":"[a-z]+"},
    ++ asides;
    var f = try Fixture.init(t.allocator, src);
    defer f.deinit();

    try expectTree(f, "# lead\n(a # in\nb # last\n) # between\n(c) # trail\n", .named, "(doc (comment) (group (item) (comment) (item) (comment))" ++
        " (comment) (group (item)) (comment))");
}

test "quire: the root reaches end of input, and every other node stops at its tokens" {
    var f = try Fixture.init(t.allocator, json_src);
    defer f.deinit();

    // The trailing newline is nobody's token and no extra either, and the root
    // covers it anyway. This is the one extent that is a fact about the file.
    var q = try f.parse("{\"a\":1}\n");
    defer q.deinit();
    try t.expectEqual(@as(u32, 0), q.nodes[q.root().?].start);
    try t.expectEqual(@as(u32, 8), q.nodes[q.root().?].end());
    // Its object still ends where its `}` does.
    try t.expectEqual(@as(u32, 7), q.nodes[q.children(q.root().?)[0]].end());

    // Leading whitespace is not a node, so it does not drag the root back -
    // but the trailing whitespace is still inside it.
    var pad = try f.parse("  42  \n");
    defer pad.deinit();
    try t.expectEqual(@as(u32, 2), pad.nodes[pad.root().?].start);
    try t.expectEqual(@as(u32, 7), pad.nodes[pad.root().?].end());

    // A file with nothing in it has an empty root at the end rather than at
    // the start: there was never any content for the padding to come before.
    var blank = try f.parse("   \n");
    defer blank.deinit();
    try t.expectEqual(@as(u32, 4), blank.nodes[blank.root().?].start);
    try t.expectEqual(@as(u32, 0), blank.nodes[blank.root().?].len);
}

test "quire: json's own comments are nodes, and say they are extras" {
    var f = try Fixture.init(t.allocator, json_src);
    defer f.deinit();

    // json declares `comment` in its `extras`, so the same placement rule
    // applies on a grammar nobody wrote for this test.
    try expectTree(f, "/* a */ [1 /* b */] // c\n", .named, "(document (comment) (array (number) (comment)) (comment))");

    var q = try f.parse("/* a */ 1");
    defer q.deinit();
    const kids = q.children(q.root().?);
    try t.expect(q.isExtra(kids[0]));
    try t.expectEqualStrings("comment", q.name(kids[0]));
    try t.expect(!q.isExtra(kids[1]));
}

// ── the differential against the oracle ──

/// Both loops over the same bytes, checked against each other. `drive.zig`
/// keeps no symbols at all, so agreeing on the tokens read and the states they
/// were read in is the whole of what the two can be compared on - and it is
/// enough, because a tree built from a different fold sequence would have to
/// have entered a different state somewhere.
fn differ(f: *Fixture, bytes: []const u8) !void {
    var d = try drive.Drive.init(t.allocator, &f.gr, &f.built.collection, &f.built.tables, &f.scanner);
    defer d.deinit();
    var trace = try d.run(bytes);
    defer trace.deinit(t.allocator);

    var q = try f.parse(bytes);
    defer q.deinit();

    try t.expectEqual(trace.tokens.len, f.gather.tokens.items.len);
    for (trace.tokens, f.gather.tokens.items) |a, b| {
        try t.expectEqual(a.symbol, b.symbol);
        try t.expectEqual(a.start, b.start);
        try t.expectEqual(a.len, b.len);
    }
    try t.expectEqualSlices(u32, trace.enter, f.gather.enter.items);

    // And on how it ended, which is the same question asked twice: a tree that
    // accepted where the oracle truncated would be a tree built out of folds
    // the automaton never took.
    try t.expectEqual(std.meta.activeTag(trace.ending) == .accepted, q.stop == .accepted);
    switch (trace.ending) {
        .stray => |off| try t.expectEqual(off, q.stop.stray),
        .unexpected => |u| {
            try t.expectEqual(u.tok.symbol, q.stop.unexpected.symbol);
            try t.expectEqual(u.state, q.stop.unexpected.state);
        },
        else => {},
    }
}

test "quire: the tree loop and the oracle read the same tokens in the same states" {
    var f = try Fixture.init(t.allocator, json_src);
    defer f.deinit();

    const cases = [_][]const u8{
        "",
        "1",
        "[]",
        "{}",
        "[1, 2, 3]",
        "{\"a\": {\"b\": [true, false, null]}}",
        "\"a\\u0041b\" // trailing comment\n",
        "/* leading */ [1]",
        // Stops, which have to agree too: the oracle is the reference for
        // where a parse dies as much as for where it succeeds.
        "[1, 2",
        "[1 2]",
        "{\"a\" 1}",
        "@",
    };
    for (cases) |case| try differ(f, case);
}

test "quire: a refusal reports the folds that reached it, and says so even when there were none" {
    var f = try Fixture.init(t.allocator, json_src);
    defer f.deinit();

    // `2` is refused where a `,` or `]` belongs - but only after `1` has folded
    // up through the value rules, and those folds are the whole of why the wall
    // is where it is. `press/inquest.zig` can name the cell that killed the
    // parse over this path and cannot without it.
    {
        var q = try f.parse("[1 2]");
        defer q.deinit();
        try t.expectEqual(quire.Stop.unexpected, std.meta.activeTag(q.stop));
        const chain = q.stop.unexpected.folded orelse
            return error.TestExpectedChain;
        try t.expect(chain.len > 0);
        // Each step names a state that exists and a production of this grammar,
        // which is the least a verdict has to be able to look up.
        for (chain) |step| {
            try t.expect(step.state < f.built.tables.action.len / f.built.tables.width);
            try t.expect(step.prod < f.gr.productions.len);
        }
    }

    // The other half of the contract, and the reason the field is optional
    // rather than a plain slice: a `}` in the opening state drove no reduces at
    // all. Empty is the measurement - this token folded through nothing, so no
    // cell on its path can be blamed - where null would mean nobody looked, and
    // a verdict reading the two the same reports a suspicion as a proof.
    {
        var q = try f.parse("}");
        defer q.deinit();
        try t.expectEqual(quire.Stop.unexpected, std.meta.activeTag(q.stop));
        const chain = q.stop.unexpected.folded orelse
            return error.TestExpectedChain;
        try t.expectEqual(@as(usize, 0), chain.len);
    }
}

test "quire: the two loops agree on a whole real file" {
    var f = try Fixture.init(t.allocator, json_src);
    defer f.deinit();
    const src = corpus(t.allocator, "ledger.json") catch |e| switch (e) {
        error.FileNotFound => return error.SkipZigTest,
        else => return e,
    };
    defer t.allocator.free(src);
    try differ(f, src);
}

/// One of the committed corpus files, or `error.FileNotFound` when the tree is
/// not underfoot. A fixture, not a build input, so a run that cannot see it
/// skips rather than fails.
fn corpus(gpa: std.mem.Allocator, name: []const u8) ![]u8 {
    const path = try std.fmt.allocPrint(gpa, "research/joinery/corpus/{s}", .{name});
    defer gpa.free(path);
    var threaded = std.Io.Threaded.init(gpa, .{});
    defer threaded.deinit();
    return std.Io.Dir.cwd().readFileAlloc(threaded.io(), path, gpa, .limited(64 << 20));
}

test "quire: the corpus json file parses to the tree its source describes" {
    var f = try Fixture.init(t.allocator, json_src);
    defer f.deinit();
    const src = corpus(t.allocator, "ledger.json") catch |e| switch (e) {
        error.FileNotFound => return error.SkipZigTest,
        else => return e,
    };
    defer t.allocator.free(src);

    // Written the way the file is: one composition per json construct, so the
    // expectation reads as a transcription of the source rather than as a
    // string somebody once printed. Every leaf is the grammar's answer for
    // that literal - a bare word is a `string` holding one `string_content`, a
    // bare integer is a `number`, and `true`/`null` are terminals named after
    // their own rules.
    try expectTree(f, src, .named, ledger_tree);
}
