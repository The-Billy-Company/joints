//! `joints lex` - tokenize a file with a grammar's scanner and nothing else.
//!
//! The verb exists to make one thing visible, so it deliberately does the wrong
//! thing: it runs the scanner with no parse state gating it. Read the footer it
//! prints before reading the stream.

const std = @import("std");
const joints = @import("joints");
const intake = @import("intake.zig");

const assay = joints.assay;
const press = joints.press;
const scanner = joints.kernel.lex.scanner;

/// Tokenize `path` with the grammar at `grammar_path`, unconditionally.
///
/// Unconditionally is the point, and the output says so: without the parse
/// state's valid-terminal set, a context-dependent terminal (JSON's
/// `string_content`, a shell heredoc body) is longest almost everywhere and
/// eats the structure around it. The summary reports how much of the file went
/// into how few tokens, which is the cheapest way to see that happen.
pub fn run(
    gpa: std.mem.Allocator,
    io: std.Io,
    w: *std.Io.Writer,
    args: []const []const u8,
) !u8 {
    const grammar_path, const path = .{ args[0], args[1] };
    const source = intake.slurp(gpa, io, w, grammar_path) orelse return 2;
    defer gpa.free(source);
    var gr = intake.grammar(gpa, w, grammar_path, source) orelse return 2;
    defer gr.deinit();
    if (!intake.customary(io, w, &gr, grammar_path, null)) return 2;

    const text = intake.slurp(gpa, io, w, path) orelse return 2;
    defer gpa.free(text);

    var sc = intake.scanner(gpa, w, &gr) catch |r| return intake.tokenless(r);
    defer sc.deinit();

    const lexing = assay.Span.open(io);
    // `null` and not a parse's `Expected`: this verb is the scanner asked what
    // it *can* match, not what the parse lets it. The two differ by more than a
    // little - with no state naming its terminals, every contextual one is live
    // everywhere, so an `immediate` body pattern (a string's interior, a JSX
    // fragment, a shebang tail) is admitted at offsets no parse would offer it
    // and, being a negated class, usually wins longest-match and swallows the
    // line. Reading this run as the parse's token stream reads a whole file as
    // one `string_fragment`; the tree from `parse` on the same bytes is fully
    // built. The footer below says so, because nothing else here does.
    var stream = try scanner.tokenize(&sc, gpa, text, null);
    defer stream.deinit(gpa);
    const us = lexing.read(io).us();

    for (stream.tokens) |tok| {
        try w.print("{d:>7} {d:>4}  {s: <24}", .{ tok.start, tok.len, gr.nameOf(tok.symbol) });
        try writeClipped(w, text[tok.start..tok.end()]);
        try w.writeAll("\n");
    }

    var covered: usize = 0;
    for (stream.tokens) |tok| covered += tok.len;
    try w.print("\n{s}: {d} tokens over {d} bytes ({d} covered) in {d} us\n", .{
        gr.name, stream.tokens.len, text.len, covered, us,
    });
    try w.writeAll("  admitted context-free: no parse state gates these, so a" ++
        " contextual\n  terminal fires where the parse would refuse it — use" ++
        " `parse` for the real stream\n");
    if (sc.blind.len > 0) {
        try w.print("  blind to {d} terminal(s):", .{sc.blind.len});
        try names(w, &gr, sc.blind);
    }
    // Named rather than counted, for the reason the blindness is: "2 by hand" is
    // a number nobody can act on, and *which* two is the difference between
    // reading a hand and reading a rule. It is also how a hand is retired -
    // where a grammar's book claims everything a hand would have answered, this
    // list is empty, and that is the evidence the troupe row is dead code.
    if (sc.transcribed.len > 0) {
        try w.print("  {d} terminal(s) answered by customary:", .{sc.transcribed.len});
        try names(w, &gr, sc.transcribed);
    }
    if (sc.handed.len > 0) {
        try w.print("  {d} terminal(s) answered by hand:", .{sc.handed.len});
        try names(w, &gr, sc.handed);
    }
    if (sc.declined.len > 0) {
        // Ours rather than someone else's C, which is why it reads differently
        // from `blind`: a declined pattern is the engine refusing a spelling we
        // could support, and it is invisible in the token stream above - the
        // terminal simply never wins, so the row it should have owned is either
        // a wider neighbour's or a stray.
        try w.print("  {d} pattern(s) the engine would not build:", .{sc.declined.len});
        try names(w, &gr, sc.declined);
    }
    if (stream.stray) |off| {
        try w.print("  stray byte at {d}: no terminal begins here\n", .{off});
        return 1;
    }
    return 0;
}

/// The terminals in one of the scanner's four rosters, closing the line.
///
/// Capped at eight and then counted, because the populations differ by two
/// orders of magnitude - swift is blind to seven, yaml's book claims a hundred
/// and one - and a diagnostic that wraps for one grammar is a diagnostic nobody
/// reads for the other. The cap lived in four copies before, one per roster,
/// which is three chances for them to disagree about what "+N more" counts.
fn names(w: *std.Io.Writer, gr: *const press.Grammar, syms: []const press.Symbol) !void {
    for (syms, 0..) |s, i| {
        if (i == 8) {
            try w.print(" +{d} more", .{syms.len - i});
            break;
        }
        try w.print(" {s}", .{gr.nameOf(s)});
    }
    try w.writeAll("\n");
}

/// One line's worth of a token's text, with the whitespace made visible — a
/// token that is a newline should not silently end the row describing it.
fn writeClipped(w: *std.Io.Writer, text: []const u8) !void {
    const clip = @min(text.len, 48);
    for (text[0..clip]) |c| switch (c) {
        '\n' => try w.writeAll("\\n"),
        '\t' => try w.writeAll("\\t"),
        '\r' => try w.writeAll("\\r"),
        else => try w.writeByte(c),
    };
    if (text.len > clip) try w.print("… +{d}", .{text.len - clip});
}
