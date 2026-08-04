//! `outliner parse` - a file in, a tree out.
//!
//! The verb the whole package is for. Prints the tree as an s-expression in
//! tree-sitter's own shape, because the fastest way to know whether two parsers
//! agree is to read both answers side by side.
//!
//! **The grammar argument is either a `grammar.json` or a folio, and which one
//! it is decides what the first parse costs.** A folio is mapped and bound in
//! single-digit milliseconds; a grammar.json is imported and pressed, which on
//! Rust is two hundred times that. Same tables either way - `mint` checks them
//! cell by cell - so the only reason to hand this a grammar.json is that you
//! have not minted one yet.
//!
//! Which of the two it is gets answered by the file's first eight bytes rather
//! than by its name. Anything else that goes wrong in a folio - a version this
//! binary does not write, a broken seal - is that folio failing and is reported
//! as such, because retrying it as JSON would turn "minted by an older
//! outliner" into "malformed grammar" and bury the one fact worth having.
//!
//! Thin on purpose. The parse belongs to `kernel/quire`, and the tree comes
//! back from one call; what is here is presentation and a verdict. Three flags,
//! each adding information rather than decoration:
//!
//!   --all      keep the anonymous nodes. `.named` is what `tree-sitter parse`
//!              prints and what a test corpus is written in; `.all` is the tree
//!              a query actually walks.
//!   --ranges   one node per line, indented, carrying the bytes it covers. The
//!              s-expression cannot say where a node begins, and a differential
//!              against another parser needs that to line two trees up when one
//!              of them stopped early.
//!   --quiet    the verdict without the tree, for a run that only wants the
//!              exit code.
//!   --mend=P   what to do about a token the parse cannot read. `fell`, the
//!              default, closes the standing stack into roots and begins again
//!              in state zero past the break; `none` stops there, which is
//!              what every parse did before recovery existed; `keep` drops the
//!              token and reads on with the stack standing; `relent` keeps once
//!              then fells. The verdict names the first break whichever is
//!              chosen - what changes is how much of the file is under a root
//!              after it.
//!
//! **The tree goes to stdout and the verdict goes to stderr**, because they are
//! answers to different questions and a caller that pipes the tree into a diff
//! must not find a status line in it. A parse that accepted and one that died
//! partway both hand back a tree, so nothing but the verdict tells them apart:
//!
//!   outliner: <path>: accepted, 1 root
//!   outliner: <path>: stray byte at 41, 4 roots
//!   outliner: <path>: stray byte at 41, 9 roots, mended 3
//!   outliner: <path>: unexpected number at 3 in state 12, 2 roots
//!   outliner: <path>: truncated, 4 roots
//!
//! Exit follows the family: 0 every file accepted, 1 at least one stopped
//! early, 2 nothing could be read or pressed.

const std = @import("std");
const outliner = @import("outliner");

const folio = outliner.folio;
const import = outliner.press.import;
const press = outliner.press;
const g = outliner.press.grammar;
const lalr = outliner.press.lalr;
const lr0 = outliner.press.lr0;
const scanner = outliner.kernel.lex.scanner;
const quire = outliner.kernel.quire;

/// Where the tables came from. Both arms hand over the same three things; only
/// what they cost to obtain differs, and that difference is the whole reason
/// the folio exists.
pub const Parser = union(enum) {
    minted: struct { mapped: folio.Mapped, bound: folio.Bound },
    pressed: struct { grammar: g.Grammar, built: press.Result },

    pub fn deinit(p: *Parser) void {
        switch (p.*) {
            .minted => |*m| {
                m.bound.deinit();
                m.mapped.close();
            },
            .pressed => |*x| {
                x.built.deinit();
                x.grammar.deinit();
            },
        }
    }

    pub fn grammar(p: *const Parser) *const g.Grammar {
        return switch (p.*) {
            .minted => |*m| &m.bound.grammar,
            .pressed => |*x| &x.grammar,
        };
    }

    pub fn collection(p: *const Parser) *const lr0.Collection {
        return switch (p.*) {
            .minted => |*m| &m.bound.collection,
            .pressed => |*x| &x.built.collection,
        };
    }

    pub fn tables(p: *const Parser) *const lalr.Tables {
        return switch (p.*) {
            .minted => |*m| &m.bound.tables,
            .pressed => |*x| &x.built.tables,
        };
    }
};

pub fn run(
    gpa: std.mem.Allocator,
    io: std.Io,
    w: *std.Io.Writer,
    grammar_path: []const u8,
    files: []const []const u8,
) !u8 {
    var show: quire.Show = .named;
    var ranges = false;
    var quiet = false;
    var mend: quire.Mend = .fell;
    var paths: std.ArrayList([]const u8) = .empty;
    defer paths.deinit(gpa);
    for (files) |a| {
        if (std.mem.eql(u8, a, "--all")) show = .all //
        else if (std.mem.eql(u8, a, "--ranges")) ranges = true //
        else if (std.mem.eql(u8, a, "--quiet")) quiet = true //
        else if (std.mem.startsWith(u8, a, "--mend=")) {
            mend = std.meta.stringToEnum(quire.Mend, a["--mend=".len..]) orelse {
                try w.print("outliner: --mend wants none, keep, fell or relent, not '{s}'\n", .{
                    a["--mend=".len..],
                });
                return 2;
            };
        } else try paths.append(gpa, a);
    }
    if (paths.items.len == 0) {
        try w.writeAll("outliner: parse needs at least one source file\n");
        return 2;
    }

    var buf: [4096]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(io, &buf);
    const e = &stderr.interface;
    defer e.flush() catch {};

    var parser = (try load(gpa, io, e, grammar_path)) orelse return 2;
    defer parser.deinit();
    const gr = parser.grammar();

    var sc = (try scanner.Scanner.compile(gpa, gr)) orelse {
        try e.print("outliner: {s} has no lexable terminal at all\n", .{gr.name});
        return 2;
    };
    defer sc.deinit();
    if (sc.blind.len > 0) {
        // Said once, before any tree: a terminal no lexer rule can produce is
        // why ten of the eleven corpus grammars stop partway, and a reader who
        // does not know that reads the stop as a parser bug.
        try e.print("outliner: {s}: blind to {d} externally scanned terminal(s)\n", .{
            gr.name, sc.blind.len,
        });
    }

    // One grammar, one scanner, one gather, however many files. `Gather.run`
    // clears its own state, so a file costs a parse rather than a setup.
    var gather = try quire.Gather.init(gpa, gr, parser.collection(), parser.tables(), &sc);
    defer gather.deinit();
    gather.mend = mend;

    var worst: u8 = 0;
    for (paths.items) |path| {
        const text = slurp(gpa, io, e, path) orelse {
            worst = 2;
            continue;
        };
        defer gpa.free(text);

        var q = try gather.run(text);
        defer q.deinit();

        if (!quiet) for (q.roots) |r| {
            if (ranges) try outline(&q, w, r, show, 0) else {
                const one = try q.sexp(gpa, r, show);
                defer gpa.free(one);
                try w.print("{s}\n", .{one});
            }
        };
        // Flushed before the verdict so the two streams read in the order the
        // work happened when both land on one terminal.
        try w.flush();
        try verdict(e, gr, path, &q);
        if (q.stop != .accepted and worst == 0) worst = 1;
    }
    return worst;
}

/// The grammar argument, whichever of the two things it is. Null means it was
/// neither and the reason is already on stderr.
pub fn load(gpa: std.mem.Allocator, io: std.Io, e: *std.Io.Writer, path: []const u8) !?Parser {
    if (folio.map(io, std.Io.Dir.cwd(), path)) |opened| {
        var mapped = opened;
        errdefer mapped.close();
        return .{ .minted = .{ .mapped = mapped, .bound = try folio.bind(gpa, &mapped.folio) } };
    } else |err| switch (err) {
        // Not a folio, so it is a grammar.json until proven otherwise.
        error.FolioBadMagic, error.FolioTooSmall => {},
        else => {
            try e.print("outliner: {s} does not load: {s}\n", .{ path, @errorName(err) });
            return null;
        },
    }

    const source = slurp(gpa, io, e, path) orelse return null;
    defer gpa.free(source);
    var gr = import.treeSitter(gpa, source) catch |err| {
        try e.print("outliner: cannot import {s}: {s}\n", .{ path, @errorName(err) });
        return null;
    };
    errdefer gr.deinit();
    return .{ .pressed = .{ .grammar = gr, .built = try press.tables(gpa, &gr) } };
}

/// One node per line: `field: name [start, end)`, indented two spaces a level.
///
/// The same tree the s-expression prints, spread out so each node carries the
/// bytes it covers. Anonymous children are skipped whole under `.named` rather
/// than descended through, which is what `ts_node_named_child` does - only an
/// *invisible* symbol lifts its children, and an anonymous node is visible.
fn outline(
    q: *const quire.Quire,
    w: *std.Io.Writer,
    ref: quire.Ref,
    show: quire.Show,
    depth: u32,
) !void {
    try w.splatByteAll(' ', depth * 2);
    if (q.field(ref)) |f| try w.print("{s}: ", .{f});
    if (q.isNamed(ref)) try w.writeAll(q.name(ref)) else try quoted(w, q.name(ref));
    const n = q.nodes[ref];
    try w.print(" [{d}, {d})\n", .{ n.start, n.end() });
    for (q.children(ref)) |c| {
        if (show == .named and !q.isNamed(c)) continue;
        try outline(q, w, c, show, depth + 1);
    }
}

/// An anonymous node, spelled as itself. Same escaping as the s-expression
/// printer's, so the two views of one tree name a node the same way.
fn quoted(w: *std.Io.Writer, name: []const u8) !void {
    try w.writeByte('"');
    for (name) |ch| {
        if (ch == '"' or ch == '\\') try w.writeByte('\\');
        try w.writeByte(ch);
    }
    try w.writeByte('"');
}

/// How the parse ended, in the terms of the file it ended in. The root count
/// rides along because it is the shape of the answer: one root is a whole
/// tree, several are the forest a stop left standing.
pub fn verdict(
    e: *std.Io.Writer,
    gr: *const outliner.press.grammar.Grammar,
    path: []const u8,
    q: *const quire.Quire,
) !void {
    try e.print("outliner: {s}: ", .{path});
    switch (q.stop) {
        .accepted => try e.writeAll("accepted"),
        .stray => |off| try e.print("stray byte at {d}", .{off}),
        .unexpected => |u| try e.print("unexpected {s} at {d} in state {d}", .{
            gr.nameOf(u.symbol), u.at, u.state,
        }),
        .truncated => try e.writeAll("truncated"),
    }
    try e.print(", {d} root{s}", .{ q.roots.len, if (q.roots.len == 1) "" else "s" });
    // The stop above says where reading got hard, and on a mended parse that
    // is not where reading stopped. Saying so is the whole of how a gap is
    // represented: no node stands for it, so the count is the only place a
    // reader can learn the forest continues past the byte just named.
    if (q.mends > 0) try e.print(", mended {d}", .{q.mends});
    try e.writeAll("\n");
}

pub fn slurp(gpa: std.mem.Allocator, io: std.Io, e: *std.Io.Writer, path: []const u8) ?[]u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64 << 20)) catch |err| {
        e.print("outliner: cannot read {s}: {s}\n", .{ path, @errorName(err) }) catch {};
        return null;
    };
}
