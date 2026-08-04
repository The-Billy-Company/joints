//! `outliner parse` — a file in, a tree out.
//!
//! The verb the whole package is for. Prints the tree as an s-expression in
//! tree-sitter's own shape, because the fastest way to know whether two parsers
//! agree is to read both answers side by side.
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
//!
//! **The tree goes to stdout and the verdict goes to stderr**, because they are
//! answers to different questions and a caller that pipes the tree into a diff
//! must not find a status line in it. A parse that accepted and one that died
//! partway both hand back a tree, so nothing but the verdict tells them apart:
//!
//!   outliner: <path>: accepted, 1 root
//!   outliner: <path>: stray byte at 41, 4 roots
//!   outliner: <path>: unexpected number at 3 in state 12, 2 roots
//!   outliner: <path>: truncated, 4 roots
//!
//! Exit follows the family: 0 every file accepted, 1 at least one stopped
//! early, 2 nothing could be read or pressed.

const std = @import("std");
const outliner = @import("outliner");

const import = outliner.press.import;
const press = outliner.press;
const scanner = outliner.kernel.lex.scanner;
const quire = outliner.kernel.quire;

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
    var paths: std.ArrayList([]const u8) = .empty;
    defer paths.deinit(gpa);
    for (files) |a| {
        if (std.mem.eql(u8, a, "--all")) show = .all //
        else if (std.mem.eql(u8, a, "--ranges")) ranges = true //
        else if (std.mem.eql(u8, a, "--quiet")) quiet = true //
        else try paths.append(gpa, a);
    }
    if (paths.items.len == 0) {
        try w.writeAll("outliner: parse needs at least one source file\n");
        return 2;
    }

    var buf: [4096]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(io, &buf);
    const e = &stderr.interface;
    defer e.flush() catch {};

    const source = slurp(gpa, io, e, grammar_path) orelse return 2;
    defer gpa.free(source);
    var gr = import.treeSitter(gpa, source) catch |err| {
        try e.print("outliner: cannot import {s}: {s}\n", .{ grammar_path, @errorName(err) });
        return 2;
    };
    defer gr.deinit();

    var built = try press.tables(gpa, &gr);
    defer built.deinit();

    var sc = (try scanner.Scanner.compile(gpa, &gr)) orelse {
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

    // One press, one scanner, one gather, however many files. `Gather.run`
    // clears its own state, so a file costs a parse rather than a setup.
    var gather = try quire.Gather.init(gpa, &gr, &built.collection, &built.tables, &sc);
    defer gather.deinit();

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
        try verdict(e, &gr, path, &q);
        if (q.stop != .accepted and worst == 0) worst = 1;
    }
    return worst;
}

/// One node per line: `field: name [start, end)`, indented two spaces a level.
///
/// The same tree the s-expression prints, spread out so each node carries the
/// bytes it covers. Anonymous children are skipped whole under `.named` rather
/// than descended through, which is what `ts_node_named_child` does — only an
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
fn verdict(
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
    try e.print(", {d} root{s}\n", .{ q.roots.len, if (q.roots.len == 1) "" else "s" });
}

fn slurp(gpa: std.mem.Allocator, io: std.Io, e: *std.Io.Writer, path: []const u8) ?[]u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64 << 20)) catch |err| {
        e.print("outliner: cannot read {s}: {s}\n", .{ path, @errorName(err) }) catch {};
        return null;
    };
}
