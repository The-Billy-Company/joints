//! `outliner amend` - a file, a series of edits, and the tree after each one.
//!
//! `parse` answers "what is this file"; this answers "what is it now, given
//! that it was that a moment ago", which is the question an editor asks a
//! thousand times an hour and the one incremental re-parse exists for. It is
//! also the only way to measure that from outside the tests: a cold `parse`
//! re-run per keystroke measures the thing incremental parsing is meant to
//! avoid.
//!
//! An edit is written `FROM..TO=TEXT` in bytes, against the file **as it
//! stands** - so a run of them is a session, not a set of patches, and the
//! second one's offsets are the first one's result. `TEXT` may be empty (a
//! deletion) and `FROM` may equal `TO` (an insertion). `\n` and `\t` are the
//! only escapes, because a shell has already eaten everything else.
//!
//! The tree goes to stdout and the verdict to stderr, as in `parse`. The
//! verdict carries what the edit cost, which is the point of the verb:
//!
//!   outliner: ledger.json: 61..61 +1: accepted, 5/274 leaves reminted at 4,
//!             height 9, 3 lifts over 402 bytes, 71 of 274 tokens read
//!
//! `--cold` re-reads the whole file for every edit instead, which is the
//! comparison the numbers above only mean something against. `--policy` picks
//! how far the re-mint window widens (`prove`, the default and the only sound
//! one; `snap`, tree-sitter's state test, kept because it is what the cheap
//! answer costs; `whole`, everything past the edit).
//!
//! Exit follows the family: 0 every state of the file accepted, 1 one of them
//! stopped early, 2 nothing could be read or pressed.

const std = @import("std");
const outliner = @import("outliner");
const parse = @import("parse.zig");

const scanner = outliner.kernel.lex.scanner;
const quire = outliner.kernel.quire;
const weave = outliner.kernel.weave;

pub fn run(
    gpa: std.mem.Allocator,
    io: std.Io,
    w: *std.Io.Writer,
    grammar_path: []const u8,
    rest: []const []const u8,
) !u8 {
    var show: quire.Show = .named;
    var quiet = false;
    var cold = false;
    var policy: weave.Policy = .prove;
    var path: ?[]const u8 = null;
    var script: std.ArrayList([]const u8) = .empty;
    defer script.deinit(gpa);

    var buf: [4096]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(io, &buf);
    const e = &stderr.interface;
    defer e.flush() catch {};

    for (rest) |a| {
        if (std.mem.eql(u8, a, "--all")) show = .all //
        else if (std.mem.eql(u8, a, "--quiet")) quiet = true //
        else if (std.mem.eql(u8, a, "--cold")) cold = true //
        else if (std.mem.startsWith(u8, a, "--policy=")) {
            policy = std.meta.stringToEnum(weave.Policy, a["--policy=".len..]) orelse {
                try e.print("outliner: no such re-mint policy: {s}\n", .{a["--policy=".len..]});
                return 2;
            };
        } else if (path == null) path = a //
        else try script.append(gpa, a);
    }
    if (path == null) {
        try e.writeAll("outliner: amend needs a source file and at least one FROM..TO=TEXT\n");
        return 2;
    }

    // Spelling is checked before the grammar is pressed, because pressing rust
    // to discover a missing `=` is two hundred milliseconds spent on a typo.
    // The offsets cannot be checked yet - each edit addresses the file the one
    // before it left - so those are still `lex`'s answer, later.
    for (script.items) |spell| {
        if (std.mem.indexOfScalar(u8, spell, '=')) |eq| {
            if (std.mem.indexOf(u8, spell[0..eq], "..") != null) continue;
        }
        try e.print("outliner: {s} is not FROM..TO=TEXT\n", .{spell});
        return 2;
    }

    var parser = (try parse.load(gpa, io, e, grammar_path)) orelse return 2;
    defer parser.deinit();
    const gr = parser.grammar();

    var sc = (try scanner.Scanner.compile(gpa, gr)) orelse {
        try e.print("outliner: {s} has no lexable terminal at all\n", .{gr.name});
        return 2;
    };
    defer sc.deinit();

    const text = parse.slurp(gpa, io, e, path.?) orelse return 2;
    defer gpa.free(text);

    var loom = weave.Loom.init(gpa, gr, parser.collection(), parser.tables(), &sc);
    defer loom.deinit();
    var it = try weave.Weave.init(gpa, &loom);
    defer it.deinit();
    it.policy = policy;
    it.reusing = !cold;

    const opened = std.Io.Clock.awake.now(io);
    try it.open(text);
    var worst: u8 = 0;
    try report(e, gr, path.?, &it, null, since(io, opened));

    for (script.items) |spell| {
        const cut = (try lex(e, spell, it.text.items.len)) orelse return 2;
        var put: std.ArrayList(u8) = .empty;
        defer put.deinit(gpa);
        try unescape(gpa, &put, spell[std.mem.indexOfScalar(u8, spell, '=').? + 1 ..]);

        const started = std.Io.Clock.awake.now(io);
        try it.amend(.{
            .from = cut.from,
            .to = cut.to,
            .insert = @intCast(put.items.len),
        }, put.items);
        try report(e, gr, path.?, &it, .{
            .from = cut.from,
            .to = cut.to,
            .insert = @intCast(put.items.len),
        }, since(io, started));
        if (it.tree.?.stop != .accepted and worst == 0) worst = 1;
    }

    const q = &it.tree.?;
    if (!quiet) for (q.roots) |r| {
        const one = try q.sexp(gpa, r, show);
        defer gpa.free(one);
        try w.print("{s}\n", .{one});
    };
    try w.flush();
    return worst;
}

const Cut = struct { from: u32, to: u32, insert: u32 = 0 };

/// `FROM..TO=TEXT`, with the offsets checked against the file they address.
/// Null means the spelling was wrong and the reason is already on stderr.
fn lex(e: *std.Io.Writer, spell: []const u8, wide: usize) !?Cut {
    const eq = std.mem.indexOfScalar(u8, spell, '=') orelse {
        try e.print("outliner: {s} is not FROM..TO=TEXT\n", .{spell});
        return null;
    };
    const dots = std.mem.indexOf(u8, spell[0..eq], "..") orelse {
        try e.print("outliner: {s} is not FROM..TO=TEXT\n", .{spell});
        return null;
    };
    const from = std.fmt.parseInt(u32, spell[0..dots], 10) catch null;
    const to = std.fmt.parseInt(u32, spell[dots + 2 .. eq], 10) catch null;
    if (from == null or to == null or from.? > to.? or to.? > wide) {
        try e.print("outliner: {s} does not address a span of {d} bytes\n", .{ spell, wide });
        return null;
    }
    return .{ .from = from.?, .to = to.? };
}

fn unescape(gpa: std.mem.Allocator, out: *std.ArrayList(u8), raw: []const u8) !void {
    var i: usize = 0;
    while (i < raw.len) : (i += 1) {
        if (raw[i] != '\\' or i + 1 == raw.len) {
            try out.append(gpa, raw[i]);
            continue;
        }
        i += 1;
        try out.append(gpa, switch (raw[i]) {
            'n' => '\n',
            't' => '\t',
            else => raw[i],
        });
    }
}

fn since(io: std.Io, from: std.Io.Timestamp) i64 {
    return @intCast(@divTrunc(
        from.durationTo(std.Io.Clock.awake.now(io)).nanoseconds,
        std.time.ns_per_us,
    ));
}

/// What the edit cost, in the terms the claim is stated in.
///
/// The re-mint window over the leaf count is the claim itself: an edit that
/// re-derives five leaves of two hundred and seventy is the thing tree-sitter's
/// directional reuse cannot do, and one that re-derives all of them is the
/// claim not holding for that edit and worth seeing rather than averaging away.
/// The height beside it is what one spliced leaf costs in compositions.
fn report(
    e: *std.Io.Writer,
    gr: *const outliner.press.grammar.Grammar,
    path: []const u8,
    it: *const weave.Weave,
    cut: ?Cut,
    us: i64,
) !void {
    if (cut) |c| {
        try e.print("outliner: {s}: {d}..{d} +{d}: ", .{ path, c.from, c.to, c.insert });
    } else try e.print("outliner: {s}: opened: ", .{path});

    const q = &it.tree.?;
    switch (q.stop) {
        .accepted => try e.writeAll("accepted"),
        .stray => |off| try e.print("stray byte at {d}", .{off}),
        .unexpected => |u| try e.print("unexpected {s} at {d} in state {d}", .{
            gr.nameOf(u.symbol), u.at, u.state,
        }),
        .truncated => try e.writeAll("truncated"),
    }
    const c = it.cost;
    // A parse that stopped early has no spine to speak of - the file has no
    // product - so the numbers that describe one are left off rather than
    // printed as zeroes.
    if (it.spun) {
        try e.print(", {d}/{d} leaves reminted at {d}, height {d}", .{
            c.minted, c.leaves, c.at, c.height,
        });
    }
    try e.print(", {d} lifts over {d} bytes, {d} tokens read, {d} us\n", .{
        c.lifts, c.skipped, c.read, us,
    });
}
