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
//! back from one call; what is here is presentation and a verdict. Five flags,
//! each adding information rather than decoration, and each written *after* the
//! grammar path, which is the first positional:
//!
//!   --all      keep the anonymous nodes. `.named` is what `tree-sitter parse`
//!              prints and what a test corpus is written in; `.all` is the tree
//!              a query actually walks.
//!   --ranges   one node per line, indented, carrying the bytes it covers. The
//!              s-expression cannot say where a node begins, and a differential
//!              against another parser needs that to line two trees up when one
//!              of them stopped early.
//!   --scars    the repair sites instead of the tree: one line per mend, where
//!              it was, what it deleted, and what the stack did about it. A
//!              node covering a byte proves the parse did not refuse *there*,
//!              not that the byte was read as written, so this is the only way
//!              a caller can tell a stretch we understood from one we papered
//!              over. It replaces the tree on stdout rather than joining it,
//!              because a caller piping the tree into a diff must not find
//!              status in it - the same rule that keeps the verdict on stderr.
//!   --quiet    the verdict without the tree, for a run that only wants the
//!              exit code. Suppresses `--scars` too: it means no stdout.
//!   --mend=P   what to do about a token the parse cannot read. `fell`, the
//!              default, closes the standing stack into roots and begins again
//!              in state zero past the break; `none` stops there, which is
//!              what every parse did before recovery existed; `keep` drops the
//!              token and reads on with the stack standing; `relent` keeps once
//!              then fells. The verdict names the first break whichever is
//!              chosen - what changes is how much of the file is under a root
//!              after it.
//!   --no-supply
//!              take away the second move. A refusal is repaired by deleting
//!              only, which is the whole vocabulary this parser had before
//!              `supply` existed. Not a tuning knob and not a default anybody
//!              should want: it is the **control arm**, so a board can price
//!              what insertion bought over the same tree and the same binary
//!              rather than against another commit. Orthogonal to `--mend`,
//!              which is about the stack rather than the vocabulary.
//!
//! **The tree goes to stdout and the verdict goes to stderr**, because they are
//! answers to different questions and a caller that pipes the tree into a diff
//! must not find a status line in it. A parse that accepted and one that died
//! partway both hand back a tree, so nothing but the verdict tells them apart:
//!
//!   outliner: <path>: accepted, 1 root, surveyed 9 of 9 nodes
//!   outliner: <path>: stray byte at 41, 4 roots, surveyed 31 of 31 nodes
//!   outliner: <path>: stray byte at 41, 9 roots, mended 3, surveyed 52 of 52 nodes
//!   outliner: <path>: unexpected number at 3 in state 12, 2 roots, surveyed 6 of 6 nodes
//!   outliner: <path>: truncated, 4 roots, surveyed 12 of 12 nodes
//!
//! **`surveyed N of M nodes` is on every one of them, and that is the point.**
//! `Quire.survey` is the only interior check this binary runs, and until it
//! said so out loud its readers had nothing but the absence of an `UNSOUND:`
//! clause to go on - which is also what a binary that stopped calling it
//! produces. The clause is the positive half: a reader can insist the walk
//! happened, and see how much of the arena it covered, instead of inferring a
//! clean tree from silence.
//!
//! Exit follows the family: 0 every file accepted, 1 at least one stopped
//! early, 2 nothing could be read or pressed.

const std = @import("std");
const outliner = @import("outliner");
const intake = @import("intake.zig");

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
    var scars = false;
    var mend: quire.Mend = .fell;
    var supplying = true;
    var paths: std.ArrayList([]const u8) = .empty;
    defer paths.deinit(gpa);
    for (files) |a| {
        if (std.mem.eql(u8, a, "--all")) show = .all //
        else if (std.mem.eql(u8, a, "--ranges")) ranges = true //
        else if (std.mem.eql(u8, a, "--quiet")) quiet = true //
        else if (std.mem.eql(u8, a, "--scars")) scars = true //
        else if (std.mem.eql(u8, a, "--no-supply")) supplying = false //
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

    var sc = (scanner.Scanner.compile(gpa, gr) catch |err| {
        try e.print("outliner: cannot compile {s}'s scanner: {s}\n", .{ gr.name, @errorName(err) });
        return 2;
    }) orelse {
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
    if (sc.declined.len > 0) {
        // The other half of the same honesty, and until now the half nobody
        // could see: `declined` was computed, used to clear a seat, and printed
        // by no reader anywhere. So a grammar whose commonest token body the
        // engine would not build lexed as if it were whole, and every byte of
        // that token surfaced downstream as a stray, a blamed name, and a mend -
        // and every instrument we own read that as a wall somewhere else. swift
        // and julia were the exhibit until 2026-08-05: both spell their
        // identifier with `&&` set intersection, which irregex did not parse, so
        // both declined it silently and the wall board filed the consequence
        // under `unrunnable external`, a family neither belonged to. Fixing the
        // engine moved swift 49.5% -> 77.0% and julia 21.2% -> 67.2% of the file
        // under a root, on `upstream/sources/{Chunked.swift,set.jl}`. markdown's
        // `entity_reference` still declines - a 16 KB, 2,231-branch alternation.
        try e.print("outliner: {s}: {d} pattern(s) the engine would not build:", .{
            gr.name, sc.declined.len,
        });
        for (sc.declined, 0..) |s, i| {
            if (i == 8) {
                try e.print(" +{d} more", .{sc.declined.len - i});
                break;
            }
            try e.print(" {s}", .{gr.nameOf(s)});
        }
        try e.writeAll("\n");
    }

    // One grammar, one scanner, one gather, however many files. `Gather.run`
    // clears its own state, so a file costs a parse rather than a setup.
    var gather = try quire.Gather.init(gpa, gr, parser.collection(), parser.tables(), &sc);
    defer gather.deinit();
    gather.mend = mend;
    gather.supplying = supplying;

    var worst: u8 = 0;
    for (paths.items) |path| {
        const text = intake.slurp(gpa, io, e, path) orelse {
            worst = 2;
            continue;
        };
        defer gpa.free(text);

        var q = try gather.run(text);
        defer q.deinit();

        if (!quiet) {
            if (scars) try seams(&q, w, gr) else for (q.roots) |r| {
                if (ranges) try outline(&q, w, r, show, 0) else {
                    const one = try q.sexp(gpa, r, show);
                    defer gpa.free(one);
                    try w.print("{s}\n", .{one});
                }
            }
        }
        // Flushed before the verdict so the two streams read in the order the
        // work happened when both land on one terminal.
        try w.flush();
        // Asked of every parse, not of a fuzz. `Quire.survey` demands exactly
        // the invariant toml's 731st node violates, and until 2026-08-05 its
        // only caller was the amend fuzz - so a tree that was not a tree
        // printed, scored and reported as one, and the violation was known only
        // because a census kept a second copy of the walk. A check nothing runs
        // is a check nobody has.
        const found = try q.survey(gpa);
        try verdict(e, gr, path, &q, parser.tables(), sc.blind, found);
        if (q.stop != .accepted and worst == 0) worst = 1;
        // The exit code is deliberately NOT moved by this. The family is
        // published three values wide - 0 accepted, 1 stopped early, 2 nothing
        // could be read or pressed - and an unsound tree is none of them: toml
        // accepts, reads whole, and hands back a forest with one child outside
        // its parent. Overloading `2` would make every reader of the code
        // report "toml cannot be pressed", which is false, and false in exactly
        // the flattering-instrument shape this check exists to end. The fact
        // belongs where every instrument already reads - the verdict line, and
        // the `unsound` column the board takes from it.
    }
    return worst;
}

/// The grammar argument, whichever of the two things it is. Null means it was
/// neither and the reason is already on stderr.
pub fn load(gpa: std.mem.Allocator, io: std.Io, e: *std.Io.Writer, path: []const u8) !?Parser {
    if (folio.map(io, std.Io.Dir.cwd(), path)) |opened| {
        var mapped = opened;
        errdefer mapped.close();
        const bound = folio.bind(gpa, &mapped.folio) catch |err| {
            try e.print("outliner: cannot bind {s}: {s}\n", .{ path, @errorName(err) });
            return null;
        };
        return .{ .minted = .{ .mapped = mapped, .bound = bound } };
    } else |err| switch (err) {
        // Not a folio, so it is a grammar.json until proven otherwise.
        error.FolioBadMagic, error.FolioTooSmall => {},
        else => {
            try e.print("outliner: {s} does not load: {s}\n", .{ path, @errorName(err) });
            return null;
        },
    }

    const source = intake.slurp(gpa, io, e, path) orelse return null;
    defer gpa.free(source);
    var gr = import.treeSitter(gpa, source) catch |err| {
        try e.print("outliner: cannot import {s}: {s}\n", .{ path, @errorName(err) });
        return null;
    };
    errdefer gr.deinit();
    const built = press.tables(gpa, &gr) catch |err| {
        try e.print("outliner: cannot press {s}: {s}\n", .{ gr.name, @errorName(err) });
        return null;
    };
    return .{ .pressed = .{ .grammar = gr, .built = built } };
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

/// One repair per line: where it was, what it deleted, and what it cost.
///
///     scar 24582..24594 12B kept unexpected identifier in state 398, 122 heads, +3501 tokens
///     scar 24626..24627 1B kept unexpected comment in state 398, 1 heads, +0 tokens
///
/// Deliberately not spelled `[start, end)`. That shape means "a node covers
/// these bytes" everywhere else in this binary and here it means the exact
/// opposite - nothing covers them, they were walked past - so a reader that
/// pattern-matches node lines must not match these by accident.
///
/// `N heads` is the readings alive at the refusal, which is not the verdict
/// line's root count and must not be read as one: a break is met by stacks, and
/// the roots are what the break leaves behind.
///
/// `+N tokens` is the tokens shifted since the previous repair, subtracted here
/// rather than stored, and it is the field to read first: **`+0` means this
/// refusal is the previous one re-reported against the next token**, not a
/// second wall. An instrument that priced the two separately was double-counting
/// one break - which is what `research/joinery/reprice/` caught the warm peel
/// doing across a whole corpus, at the cost of a second parse per byte.
fn seams(q: *const quire.Quire, w: *std.Io.Writer, gr: *const g.Grammar) !void {
    var shifted: u32 = 0;
    for (q.scars) |s| {
        // Two moves and two spellings. A deletion says how many bytes it walked
        // past and what it did with the stack; a supply walked past none and
        // did neither, so printing `0B kept` for it would be three fields of
        // nothing where the one fact that matters - which terminal was written
        // in - has nowhere to go.
        if (s.gave) |sym| {
            try w.print("scar {d} gave {s} ", .{ s.at, gr.nameOf(sym) });
        } else try w.print("scar {d}..{d} {d}B {s} ", .{
            s.at, s.over, s.len(), if (s.felled) "fell" else "kept",
        });
        switch (s.why) {
            .stray => try w.writeAll("stray"),
            .unexpected => |u| try w.print("unexpected {s} in state {d}", .{
                gr.nameOf(u.symbol), u.state,
            }),
            // `mended` is reached from the two walls only; the other two arms
            // end a parse rather than being recovered from.
            .accepted, .truncated => try w.writeAll("unreported"),
        }
        try w.print(", {d} heads, +{d} tokens\n", .{ s.heads, s.shifted - shifted });
        shifted = s.shifted;
    }
}

/// An anonymous node, spelled as itself. Same escaping as the s-expression
/// printer's - literally the same, `quire.escape` - so the two views of one
/// tree name a node the same way and neither can drift alone. Each was its own
/// two-byte rule until 2026-08-05, and both were missing the control bytes that
/// break this render's one-node-per-line contract.
fn quoted(w: *std.Io.Writer, name: []const u8) !void {
    try w.writeByte('"');
    var buf: [4]u8 = undefined;
    for (name) |ch| try w.writeAll(quire.escape(ch, &buf));
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
    t: *const lalr.Tables,
    blind: []const g.Symbol,
    found: quire.Quire.Survey,
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
    // Both numbers, because neither implies the other and the fuse is
    // denominated in the second: sixty small holes and one skipped file read
    // the same in a count and nothing alike in bytes.
    if (q.mends > 0) try e.print(", mended {d} over {d}B", .{ q.mends, q.skipped });
    // Kept out of `mended` on purpose - a supply resynchronises nothing and
    // walks past no bytes, so folding it in would move a number every board
    // already reads for a repair that is not what that number means. `spurned`
    // is the refusals where several terminals would each have resumed the
    // parse: the half of the residue that wants a ranking rule rather than a
    // second move.
    if (q.supplied > 0 or q.spurned > 0) {
        try e.print(", supplied {d}, spurned {d}", .{ q.supplied, q.spurned });
    }
    // Said on the same line as the stop, because it is the same kind of fact:
    // what this parse handed back. A stop says how far it got; this says
    // whether what it got is a tree.
    //
    // Printed on EVERY parse, sound or not, and that is the contract rather
    // than a decoration. Until 2026-08-06 this line was silent on a sound tree,
    // so the only evidence `tool/sound.py` had was an absence - and an absence
    // is what a binary that stopped calling `survey` produces too. Thirty rows
    // would have read `sound` off a check nobody ran, which is the exact
    // failure two other instruments were repaired for the same morning. A
    // reader can now insist the walk happened and see how much of the arena it
    // covered, so `not looked at` is a different answer from `looked, fine`.
    try e.print(", surveyed {d} of {d} node{s}", .{
        found.walked, found.held, if (found.held == 1) "" else "s",
    });
    if (!found.sound()) {
        try e.print(", UNSOUND: {d} loose, {d} disorder, {d} torn", .{
            found.loose, found.disorder, found.torn,
        });
        // Half of what `survey` reports is "that ref is not a node", so the
        // ref being reported on is exactly the one that may not be indexed.
        if (found.first) |f| {
            if (f.ref < q.nodes.len) {
                const n = q.nodes[f.ref];
                try e.print(" [{s}: {s} [{d}, {d})", .{ f.why, q.name(f.ref), n.start, n.end() });
            } else {
                try e.print(" [{s}: ref {d} past {d} nodes", .{ f.why, f.ref, q.nodes.len });
            }
            if (f.under != quire.none and f.under < q.nodes.len) {
                const p = q.nodes[f.under];
                try e.print(" in {s} [{d}, {d})", .{ q.name(f.under), p.start, p.end() });
            }
            try e.writeAll("]");
        }
    }
    try e.writeAll("\n");
    try owner(e, gr, q, t, blind);
}

/// Who has to change something for this wall to move.
///
/// The line above says *where* a parse stopped; this one says *whose* it is,
/// and the two are not the same question - a wall named in state 803 is very
/// often not state 803's fault. `inquest` has been able to answer it from the
/// artifact for as long as the verdict has been printed, and until now the only
/// caller was a test: the answer was computed, was acted on inside press, and
/// reached no human. A lane spent a round building a second instrument to guess
/// at it from the outside, and that instrument turned out to be measuring
/// something else. This line is so the next one does not have to.
///
/// Silent on an accepted parse, where the answer is `whole` and says nothing.
fn owner(
    e: *std.Io.Writer,
    gr: *const outliner.press.grammar.Grammar,
    q: *const quire.Quire,
    t: *const lalr.Tables,
    blind: []const g.Symbol,
) !void {
    const wall: press.inquest.Wall = switch (q.stop) {
        .accepted => return,
        .truncated => .unclosed,
        // The walk knows the state it stood in and the verdict does not print
        // it, so it is handed over here rather than parsed back out of the line
        // - which is what let `inquest`'s cell arguments run at all.
        .stray => |off| .{ .stray = .{ .at = off } },
        .unexpected => |u| .{ .refused = .{ .terminal = u.symbol, .state = u.state } },
    };
    // No fold chain: `Quire` keeps the stop, not the path the token drove to
    // reach it, so a table-damage answer here comes back `proven = false` and
    // prints with a `?`. That is the honest strength of it and not a rounding.
    const found = press.inquest.over(t, gr, wall, blind);
    try e.print("outliner: {s}: ", .{gr.name});
    try press.inquest.write(found, gr, wall, e);
    try e.writeAll("\n");
}

// -------------------------------------------------------- the wiring, asserted

/// One verdict line, rendered off a hand-built arena, so a test can read the
/// sentence rather than the code that writes it.
///
/// The tables are undefined on purpose and never dereferenced: `owner` returns
/// on `.accepted` before it touches them. The grammar carries names and nothing
/// else, because the fault report names the node it is complaining about -
/// dragging a pressed grammar in would make the test cost a press and stop
/// being a test of this file. Same trick, same reason, as
/// `kernel/quire/survey_test.zig`'s `arena`.
fn said(gpa: std.mem.Allocator, gr: *const g.Grammar, q: *const quire.Quire,
        found: quire.Quire.Survey) ![]u8 {
    const tables: *const lalr.Tables = undefined;
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try verdict(&out.writer, gr, "/x/a.json", q, tables, &.{}, found);
    return out.toOwnedSlice();
}

fn named(names: []const []const u8) g.Grammar {
    var gr: g.Grammar = undefined;
    gr.names = names;
    return gr;
}

fn accepted(gr: *const g.Grammar, nodes: []const quire.Node, kids: []const quire.Ref,
            roots: []const quire.Ref) quire.Quire {
    return .{ .gpa = std.testing.allocator, .gr = gr, .nodes = nodes,
              .kids = kids, .roots = roots, .stop = .accepted };
}

fn leaf(start: u32, len: u32) quire.Node {
    return .{ .kind = .of(0), .start = start, .len = len, .kids_at = 0, .kids_len = 0 };
}

test "the verdict says it surveyed, on a tree it liked" {
    // The assertion `survey_test.zig` structurally cannot make. Those arenas
    // prove the WALK still finds every fault; this proves the walk is still
    // WIRED - that `parse.zig` calls it and prints the result in the spelling
    // `tool/stamp.py` reads. Delete the `survey` call, or reword the clause,
    // and the hand-built arenas stay green while thirty corpus rows go on
    // reporting `sound` off a check nobody ran.
    const nodes = [_]quire.Node{
        .{ .kind = .of(0), .start = 0, .len = 10, .kids_at = 0, .kids_len = 2 },
        leaf(0, 4),
        leaf(5, 5),
    };
    const kids = [_]quire.Ref{ 1, 2 };
    const gr = named(&.{"pair"});
    const q = accepted(&gr, &nodes, &kids, &.{0});
    const found = try q.survey(std.testing.allocator);
    try std.testing.expect(found.sound());

    const line = try said(std.testing.allocator, &gr, &q, found);
    defer std.testing.allocator.free(line);
    // A sound tree is the case that used to print nothing at all.
    try std.testing.expect(std.mem.indexOf(u8, line, ", surveyed 3 of 3 nodes") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "UNSOUND") == null);
}

test "the verdict still says it surveyed when it disliked what it found" {
    // toml's shape: one child disjoint from the parent holding it. Both clauses
    // ride the same line, in this order, because `stamp.outcome` lifts the
    // second off the first and a reader that got the order wrong would take
    // half of one for the whole of the other.
    const nodes = [_]quire.Node{
        .{ .kind = .of(0), .start = 8, .len = 7, .kids_at = 0, .kids_len = 1 },
        leaf(17, 3),
    };
    const kids = [_]quire.Ref{1};
    const gr = named(&.{"pair"});
    const q = accepted(&gr, &nodes, &kids, &.{0});
    const found = try q.survey(std.testing.allocator);
    try std.testing.expect(!found.sound());

    const line = try said(std.testing.allocator, &gr, &q, found);
    defer std.testing.allocator.free(line);
    const at = std.mem.indexOf(u8, line, ", surveyed 2 of 2 nodes") orelse
        return error.NoPositiveSignal;
    const bad = std.mem.indexOf(u8, line, ", UNSOUND: 1 loose, 0 disorder, 0 torn") orelse
        return error.NoUnsoundClause;
    try std.testing.expect(at < bad);
}

test "an empty forest surveys nothing and still says so" {
    // The vacuous case, which is the whole reason the clause carries a size.
    // `0 of 0` is a walk that ran over nothing; no clause at all is a walk
    // nobody ran, and a gate has to be able to tell those apart.
    const gr = named(&.{});
    const q = accepted(&gr, &.{}, &.{}, &.{});
    const found = try q.survey(std.testing.allocator);
    const line = try said(std.testing.allocator, &gr, &q, found);
    defer std.testing.allocator.free(line);
    try std.testing.expect(std.mem.indexOf(u8, line, ", surveyed 0 of 0 nodes") != null);
}
