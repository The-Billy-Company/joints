//! A query sees the name and namedness a use-site alias gives a node, while a
//! supertype asks about the symbol that node reduced. These can disagree in
//! either direction, so a grammar with only ordinary names cannot guard them.

const std = @import("std");
const t = std.testing;
const gloss = @import("gloss.zig");
const folio = @import("../../folio/folio.zig");
const press = @import("../../press/press.zig");
const lex = @import("../lex/scanner.zig");
const quire = @import("../quire/quire.zig");
const gpa = t.allocator;

const grammar =
    \\{"name":"alias_query","supertypes":["expression"],"rules":{
    \\ "doc":{"type":"CHOICE","members":[{"type":"SEQ","members":[
    \\   {"type":"FIELD","name":"first","content":{"type":"ALIAS","named":true,"value":"name","content":{"type":"STRING","value":"p"}}},
    \\   {"type":"STRING","value":","},
    \\   {"type":"FIELD","name":"second","content":{"type":"ALIAS","named":false,"value":"op","content":{"type":"SYMBOL","name":"word"}}},
    \\   {"type":"STRING","value":";"},
    \\   {"type":"FIELD","name":"third","content":{"type":"ALIAS","named":true,"value":"name","content":{"type":"SYMBOL","name":"_hidden"}}},
    \\   {"type":"STRING","value":":"},{"type":"SYMBOL","name":"expression"}]},
    \\   {"type":"SYMBOL","name":"word"},{"type":"SYMBOL","name":"member"}]},
    \\ "word":{"type":"STRING","value":"w"},
    \\ "_hidden":{"type":"SEQ","members":[{"type":"STRING","value":"h"},{"type":"STRING","value":"!"}]},
    \\ "expression":{"type":"CHOICE","members":[
    \\   {"type":"ALIAS","named":true,"value":"renamed_member","content":{"type":"SYMBOL","name":"member"}},
    \\   {"type":"SYMBOL","name":"number"}]},
    \\ "member":{"type":"STRING","value":"m"},
    \\ "number":{"type":"PATTERN","value":"[0-9]+"}}}
;
const source = "p,w;h!:m";

// Heap storage keeps Gather's borrowed tables and scanner stable for the run.
const Bench = struct {
    gr: press.Grammar,
    built: press.Result,
    scanner: lex.Scanner,
    gather: quire.Gather,
    bytes: []align(folio.align_bytes) u8,
    f: folio.Folio,
    l: gloss.Lemma,

    fn init() !*Bench {
        const b = try gpa.create(Bench);
        errdefer gpa.destroy(b);
        b.gr = try press.treeSitter(gpa, grammar);
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

    fn expect(b: *Bench, scm: []const u8, want: []const u8) !void {
        var q = try b.gather.run(source);
        defer q.deinit();
        try t.expect(q.stop == .accepted);
        try t.expectEqual(1, q.roots.len);
        try t.expectEqual(0, q.mends);
        var compiled = try gloss.compile(gpa, &b.l, scm, null);
        defer compiled.deinit();
        var cur = try gloss.open(gpa, compiled.view().?, .{ .q = &q, .src = source, .index = &b.l });
        defer cur.deinit();
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        var buf: [128]u8 = undefined;
        while (try cur.next()) |m| for (m.captures) |cap| {
            const n = q.nodes[cap.node];
            if (out.items.len != 0) try out.append(gpa, '\n');
            try out.appendSlice(gpa, try std.fmt.bufPrint(&buf, "{s}={s}@{d}..{d}", .{
                compiled.view().?.captureAt(cap.id), q.name(cap.node), n.start, n.end(),
            }));
        };
        try t.expectEqualStrings(want, out.items);
    }
};

test "scribe alias: named wildcards use the alias namedness and preserve fields" {
    const b = try Bench.init();
    defer b.deinit();
    try b.expect("(_) @a", "a=doc@0..8\na=name@0..1\na=name@4..6\na=renamed_member@7..8");
    try b.expect("(doc first: (_) @a third: (_) @b)", "a=name@0..1\nb=name@4..6");
    try b.expect("_ @a", "a=doc@0..8\na=name@0..1\na=,@1..2\na=op@2..3\na=;@3..4\na=name@4..6\na=h@4..5\na=!@5..6\na=:@6..7\na=renamed_member@7..8");
    try b.expect("(doc second: _ @a)", "a=op@2..3");
    try b.expect("(name) @a", "a=name@0..1\na=name@4..6");
    try b.expect("\"op\" @a", "a=op@2..3");
    try b.expect("(word) @a", "");
    try b.expect("[(number) (_)] @a", "a=doc@0..8\na=name@0..1\na=name@4..6\na=renamed_member@7..8");
}

test "scribe alias: a bare supertype tests the symbol under a rename" {
    const b = try Bench.init();
    defer b.deinit();
    try b.expect("(expression) @a", "a=renamed_member@7..8");
    try b.expect("(renamed_member) @a", "a=renamed_member@7..8");
    try b.expect("(member) @a", "");
}
