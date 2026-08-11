//! `joints query` - a `.scm` and a file in, the matches out.
//!
//! The door on `gloss`. Half of that package - read the notation, resolve every
//! name against the grammar, prove the dead patterns dead, lower the whole thing
//! to a program the folio can carry - has existed for a while and could be
//! reached from Zig and from nothing else. So the compiler was tested against
//! its own output and against no tree, which is the strongest possible guarantee
//! that a query compiles and no guarantee at all that it finds anything.
//!
//! This verb is what makes that testable from outside, and the differential in
//! `tool/glance.py` is why it is shaped the way it is: `tree-sitter query` takes
//! the same two files and prints the same answer, so the two engines can be run
//! over the same corpus and diffed. **A verb whose output nothing else can
//! produce cannot be checked against anything**, which is the position `gloss`
//! was in this morning.
//!
//! The grammar argument is a `grammar.json` or a folio, decided by its first
//! eight bytes, exactly as `parse` decides it - this verb calls that verb's
//! `load`. Unlike `parse` it wants the *artifact* and not only the tables:
//! `gloss` indexes a grammar's supertypes, fields and renames off the folio's
//! own sections, so the `grammar.json` arm packs one in memory first. That is a
//! real cost on the JSON path and none at all on the minted one, which is the
//! same asymmetry `parse` documents and the same reason to mint.
//!
//! Flags, each after both positionals:
//!
//!   --captures  one line per capture, unGrouped, for a pipe. The default
//!               render groups a match and indents its captures, which reads
//!               better and diffs worse.
//!   --json      one object per file for a caller that is a program. Carries
//!               byte offsets and no text, because the caller has the file and
//!               a span is exact where an elided string is not.
//!   --dead      the patterns this grammar can never match, and why. Nothing
//!               else in the world prints this - it is the static reachability
//!               `gloss` does and tree-sitter does not - so it is a flag rather
//!               than a line of the verdict only because most runs do not care.
//!   --quiet     the verdict only, no stdout.
//!   --foreign=P what to do about a predicate we carry but cannot run:
//!               `refuse`, `admit` or `deny`.
//!   --language=NAME  which grammar, when the folio holds several.
//!
//! **`--foreign` defaults to `refuse` and that will stop a real
//! `highlights.scm`**, which is deliberate and is the one place this verb is
//! deliberately less convenient than tree-sitter. tree-sitter's own CLI hands an
//! unknown predicate back to its caller and matches anyway, so a query whose
//! correctness rests on `#is-not? local` silently returns the matches that
//! predicate existed to remove. We refuse and name it. `--foreign=admit` buys
//! tree-sitter's behaviour, is what an editor wants, and is what the
//! differential passes so that the two engines are being asked the same
//! question.
//!
//! Matches to stdout, verdict to stderr, same as `parse` and for the same
//! reason. Exit follows the family, with `1` meaning what it means in every
//! search tool: 0 something matched, 1 nothing did and that is a clean answer,
//! 2 a file could not be read, pressed or compiled.

const std = @import("std");
const joints = @import("joints");
const intake = @import("intake.zig");
const parse = @import("parse.zig");

const folio = joints.folio;
const gloss = joints.kernel.gloss;
const quire = joints.kernel.quire;

/// How much of a capture's text a grouped line carries before it is cut. A
/// capture is very often a whole function body, and the reason to print text at
/// all is recognising the hit rather than reading it.
const shown = 40;

pub fn run(
    gpa: std.mem.Allocator,
    io: std.Io,
    w: *std.Io.Writer,
    args: []const []const u8,
) !u8 {
    const grammar_path = args[0];
    const query_path = args[1];
    var flat = false;
    var json = false;
    var dead = false;
    var quiet = false;
    var language: ?[]const u8 = null;
    var foreign: gloss.Foreign = intake.default.foreign;
    var paths: std.ArrayList([]const u8) = .empty;
    defer paths.deinit(gpa);
    for (args[2..]) |a| {
        if (std.mem.eql(u8, a, "--captures")) flat = true //
        else if (std.mem.eql(u8, a, "--json")) json = true //
        else if (std.mem.eql(u8, a, "--dead")) dead = true //
        else if (std.mem.eql(u8, a, "--quiet")) quiet = true //
        else if (std.mem.startsWith(u8, a, "--language=")) language = a["--language=".len..] //
        else if (std.mem.startsWith(u8, a, "--foreign=")) {
            foreign = intake.choice(gloss.Foreign, w, "--foreign", a["--foreign=".len..]) orelse
                return 2;
        } else try paths.append(gpa, a);
    }
    if (paths.items.len == 0) {
        try w.writeAll("joints: query needs at least one source file\n");
        return 2;
    }
    // The same refusal `parse` makes, for the same reason: two shapes of one
    // stdout, and a caller that asked for both should learn now rather than
    // discover which one won.
    if (json and flat) {
        try w.writeAll("joints: --json is a whole answer; it does not combine with --captures\n");
        return 2;
    }

    var buf: [4096]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(io, &buf);
    const e = &stderr.interface;
    defer e.flush() catch {};

    var parser = (try parse.load(gpa, io, e, grammar_path, language)) orelse return 2;
    defer parser.deinit();
    const gr = parser.grammar();

    var facts: Facts = undefined;
    index(gpa, e, &parser, &facts) catch return 2;
    defer facts.deinit();

    const scm = intake.slurp(gpa, io, e, query_path) orelse return 2;
    defer gpa.free(scm);

    var fault: gloss.Fault = .{};
    var compiled = gloss.compile(gpa, &facts.l, scm, &fault) catch |err| {
        try refusal(e, query_path, gr.name, err, fault);
        return 2;
    };
    defer compiled.deinit();
    const program = compiled.view() orelse {
        // The reader refusing bytes this compiler just wrote is a fault in the
        // package rather than in the query, so it is worth its own sentence.
        try e.print("joints: {s}: compiled to bytes this binary cannot read back\n", .{query_path});
        return 2;
    };

    if (compiled.opaque_predicates > 0 and foreign == .refuse and !quiet) {
        // Said before the first refusal rather than after it, because the
        // refusal names one predicate and this names the size of the problem.
        try e.print("joints: {s}: {d} predicate(s) this engine carries but cannot run;" ++
            " --foreign=admit to match anyway\n", .{ query_path, compiled.opaque_predicates });
    }
    if (dead and !quiet) try obituary(w, &compiled, query_path);

    var sc = intake.scanner(gpa, e, gr) catch return 2;
    defer sc.deinit();
    var gather = try quire.Gather.init(gpa, gr, parser.collection(), parser.tables(), &sc);
    defer gather.deinit();

    var worst: u8 = 1;
    for (paths.items) |path| {
        const text = intake.slurp(gpa, io, e, path) orelse {
            worst = 2;
            continue;
        };
        defer gpa.free(text);

        var q = try gather.run(text);
        defer q.deinit();

        var cursor = gloss.open(gpa, program, .{
            .q = &q,
            .src = text,
            .index = &facts.l,
            .foreign = foreign,
        }) catch |err| {
            try trouble(e, path, err);
            worst = 2;
            continue;
        };
        defer cursor.deinit();

        var tally: Tally = .{};
        if (json) {
            try machine(&cursor, w, &q, program, gr.name, path, &tally);
        } else if (quiet) {
            try count(&cursor, &tally);
        } else {
            try human(&cursor, w, &q, program, text, flat, &tally);
        }
        if (tally.err) |err| {
            try trouble(e, path, err);
            worst = 2;
            continue;
        }
        try w.flush();
        try verdict(e, path, &q, program, &tally);
        if (tally.matches > 0 and worst == 1) worst = 0;
    }
    return worst;
}

/// What a run over one file came to. Carried rather than returned because the
/// three renders all produce it and the verdict wants it after stdout is done.
const Tally = struct {
    matches: u32 = 0,
    captures: u32 = 0,
    /// The first refusal the walk hit, if it hit one. A cursor stops at a
    /// predicate it cannot run, and the caller has to be able to tell that from
    /// a file with no matches in it.
    err: ?anyerror = null,
};

/// The grammar's facts, and the bytes they may have had to be packed into.
///
/// `gloss` indexes off a folio because a folio is where the supertype and
/// rename tables live in the shape a query asks about them. The minted arm has
/// one already; the pressed arm mints one here, in memory, which is exactly
/// what `mint -o` would have written and is thrown away at the end of the run.
const Facts = struct {
    gpa: std.mem.Allocator,
    /// Owned only on the pressed path. Null means the folio is a view over
    /// bytes the `Parser` has mapped and will close.
    bytes: ?[]align(folio.align_bytes) u8,
    f: folio.Folio,
    l: gloss.Lemma,

    fn deinit(x: *Facts) void {
        x.l.deinit();
        if (x.bytes) |b| x.gpa.free(b);
        x.* = undefined;
    }
};

/// Built into `out` rather than returned, because a `Lemma` keeps a pointer to
/// the folio it indexed and a `Facts` handed back by value would move that
/// folio out from under it.
fn index(gpa: std.mem.Allocator, e: *std.Io.Writer, p: *parse.Parser, out: *Facts) !void {
    out.* = switch (p.*) {
        .minted => |*m| .{ .gpa = gpa, .bytes = null, .f = m.folio, .l = undefined },
        .pressed => |*src| blk: {
            const bytes = folio.pack(gpa, &src.grammar, &src.built) catch |err| {
                try e.print("joints: cannot index {s}: {s}\n", .{ src.grammar.name, @errorName(err) });
                return err;
            };
            errdefer gpa.free(bytes);
            break :blk .{
                .gpa = gpa,
                .bytes = bytes,
                .f = try folio.open(bytes),
                .l = undefined,
            };
        },
    };
    errdefer if (out.bytes) |b| gpa.free(b);
    out.l = gloss.index(gpa, &out.f) catch |err| {
        try e.print("joints: cannot index the grammar: {s}\n", .{@errorName(err)});
        return err;
    };
}

/// Why a query would not compile, in the terms of the file it is in.
///
/// The two halves are worth keeping apart. A syntax refusal knows a byte and no
/// name; a resolution refusal knows a NAME and is the interesting one, because
/// "this grammar has no `type_identifier`" is a different day's work from "this
/// file is malformed somewhere around byte 412".
fn refusal(
    e: *std.Io.Writer,
    path: []const u8,
    language: []const u8,
    err: anyerror,
    fault: gloss.Fault,
) !void {
    try e.print("joints: {s}: {s}", .{ path, @errorName(err) });
    if (fault.name.len > 0) {
        try e.print(" - {s} is not a name {s} knows", .{ fault.name, language });
    }
    try e.print(" at byte {d}\n", .{fault.at});
}

/// A refusal from the matcher rather than the compiler, which is a much smaller
/// set and each member of it is actionable.
fn trouble(e: *std.Io.Writer, path: []const u8, err: anyerror) !void {
    try e.print("joints: {s}: {s}", .{ path, @errorName(err) });
    switch (err) {
        error.QueryOpaquePredicate => try e.writeAll(
            " - a filter this engine does not implement; --foreign=admit or =deny to go on",
        ),
        error.QueryNeedsIndex => try e.writeAll(" - a bare supertype needs the grammar's index"),
        error.QuerySourceShort => try e.writeAll(" - the tree does not come from these bytes"),
        else => {},
    }
    try e.writeAll("\n");
}

/// The patterns that cannot match, and the fact about the grammar that makes
/// each one dead. tree-sitter has no equivalent because it does not hold the
/// productions; a query naming a field its node never carries is simply a
/// pattern that finds nothing there.
fn obituary(w: *std.Io.Writer, c: *const gloss.Compiled, path: []const u8) !void {
    if (c.dead.len == 0) {
        try w.print("no dead patterns in {s}\n", .{path});
        return;
    }
    for (c.dead) |d| {
        try w.print("dead pattern {d} at byte {d}: {s}\n", .{
            d.pattern, d.at,
            switch (d.cause) {
                .field_not_carried => "that kind never carries that field",
                .not_a_member => "that kind is not in that category",
                .child_not_admitted => "that kind can never hold that child",
                .absent_field_vacuous => "the !field could not have been there anyway",
            },
        });
    }
}

/// Drain the cursor without rendering, for `--quiet`.
fn count(c: *gloss.Cursor, t: *Tally) !void {
    while (c.next() catch |err| {
        t.err = err;
        return;
    }) |m| {
        t.matches += 1;
        t.captures += @intCast(m.captures.len);
    }
}

/// The reading render. Grouped by default - a match, then its captures indented
/// under it - because a pattern with four captures is one finding and not four.
/// `--captures` flattens it, which is what a pipe wants.
fn human(
    c: *gloss.Cursor,
    w: *std.Io.Writer,
    q: *const quire.Quire,
    p: gloss.Program,
    src: []const u8,
    flat: bool,
    t: *Tally,
) !void {
    while (c.next() catch |err| {
        t.err = err;
        return;
    }) |m| {
        if (!flat) try w.print("match {d} pattern {d}\n", .{ t.matches, m.pattern });
        for (m.captures) |cap| {
            const n = q.nodes[cap.node];
            if (flat) try w.print("{d} ", .{m.pattern}) else try w.writeAll("  ");
            try w.print("@{s} [{d}, {d}) `", .{ p.captureAt(cap.id), n.start, n.end() });
            try excerpt(w, src[n.start..@min(n.end(), src.len)]);
            try w.writeAll("`\n");
        }
        t.matches += 1;
        t.captures += @intCast(m.captures.len);
    }
}

/// A capture's bytes, on one line and short enough to sit on it.
///
/// Both halves matter. A newline in the middle of a capture would break the
/// one-line-per-capture contract this render is greppable because of, and a
/// capture on a `function_definition` is the whole function.
fn excerpt(w: *std.Io.Writer, text: []const u8) !void {
    var wrote: usize = 0;
    var it = text;
    if (it.len > shown) it = it[0..shown];
    for (it) |ch| {
        switch (ch) {
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            '`' => try w.writeAll("\\`"),
            '\\' => try w.writeAll("\\\\"),
            else => if (ch < 0x20) try w.print("\\x{x:0>2}", .{ch}) else try w.writeByte(ch),
        }
        wrote += 1;
    }
    if (text.len > wrote) try w.writeAll("...");
}

/// One object per file, for a caller that is a program - which is the
/// differential, and the reason the shape carries spans and no text. A span is
/// exact and a text is elided, and the caller is holding the file anyway.
///
///   {"path":…,"language":…,"patterns":N,"matches":[
///     {"pattern":N,"captures":[{"name":…,"start":N,"end":N}]}]}
fn machine(
    c: *gloss.Cursor,
    w: *std.Io.Writer,
    q: *const quire.Quire,
    p: gloss.Program,
    language: []const u8,
    path: []const u8,
    t: *Tally,
) !void {
    try w.writeAll("{\"language\":");
    try jstring(w, language);
    try w.writeAll(",\"path\":");
    try jstring(w, path);
    // `sound` rides the answer because a query over a forest is a real answer
    // to the wrong tree, and a machine reading this has no other way to tell
    // that from a disagreement about matching. The human verdict says the same
    // thing on stderr.
    try w.print(",\"patterns\":{d},\"roots\":{d},\"sound\":{s},\"matches\":[", .{
        p.patternCount(),
        q.roots.len,
        if (q.stop == .accepted) "true" else "false",
    });
    // Spelled out rather than written as a `while (…catch…) |m|`, because the
    // refusal arm has to leave the loop and close the object: a caller reading
    // NDJSON gets a parseable line either way, and learns the trouble from the
    // exit code and stderr rather than from a truncated frame.
    while (true) {
        const got = c.next() catch |err| {
            t.err = err;
            break;
        };
        const m = got orelse break;
        if (t.matches > 0) try w.writeByte(',');
        try w.print("{{\"pattern\":{d},\"captures\":[", .{m.pattern});
        for (m.captures, 0..) |cap, i| {
            if (i > 0) try w.writeByte(',');
            const n = q.nodes[cap.node];
            try w.writeAll("{\"name\":");
            try jstring(w, p.captureAt(cap.id));
            try w.print(",\"start\":{d},\"end\":{d}}}", .{ n.start, n.end() });
        }
        try w.writeAll("]}");
        t.matches += 1;
        t.captures += @intCast(m.captures.len);
    }
    try w.writeAll("]}\n");
}

fn jstring(w: *std.Io.Writer, s: []const u8) !void {
    try w.writeByte('"');
    for (s) |ch| switch (ch) {
        '"' => try w.writeAll("\\\""),
        '\\' => try w.writeAll("\\\\"),
        '\n' => try w.writeAll("\\n"),
        '\r' => try w.writeAll("\\r"),
        '\t' => try w.writeAll("\\t"),
        else => if (ch < 0x20) try w.print("\\u{x:0>4}", .{ch}) else try w.writeByte(ch),
    };
    try w.writeByte('"');
}

/// What the run came to, in the terms of the file it ran over.
///
///   joints: <path>: 41 matches, 63 captures over 59 patterns
///   joints: <path>: 0 matches, 0 captures over 59 patterns, over 4 roots (stray byte at 41)
///
/// **The second clause is the one that matters and it is why this is not just a
/// count.** A query runs over the tree it was given, and a parse that stopped
/// early hands back a forest with holes in it. Zero matches against a whole
/// tree is a fact about the query; zero matches against four roots is very
/// often a fact about the parse, and a reader who cannot tell them apart will
/// go looking for the bug in the wrong package.
fn verdict(
    e: *std.Io.Writer,
    path: []const u8,
    q: *const quire.Quire,
    p: gloss.Program,
    t: *const Tally,
) !void {
    try e.print("joints: {s}: {d} match{s}, {d} capture{s} over {d} pattern{s}", .{
        path,
        t.matches,
        if (t.matches == 1) "" else "es",
        t.captures,
        if (t.captures == 1) "" else "s",
        p.patternCount(),
        if (p.patternCount() == 1) "" else "s",
    });
    if (q.stop != .accepted) {
        try e.print(", over {d} root{s} (", .{ q.roots.len, if (q.roots.len == 1) "" else "s" });
        switch (q.stop) {
            .accepted => unreachable,
            .stray => |off| try e.print("stray byte at {d}", .{off}),
            .unexpected => |u| try e.print("unexpected symbol at {d}", .{u.at}),
            .truncated => try e.writeAll("truncated"),
        }
        try e.writeAll(")");
    }
    try e.writeAll("\n");
}
