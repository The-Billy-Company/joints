//! Gloss — can we compile the queries people actually wrote, and what does
//! pressing them buy?
//!
//! The premise of the whole lane is a claim about a corpus: every `.scm` file
//! the pinned grammars ship compiles against its own grammar. That is an
//! acceptance question rather than an invariant, so it is a rung and not a
//! test — it needs `upstream/grammars/` fetched and the query corpus underfoot,
//! and a suite that reddens in a fresh clone is a suite people stop reading.
//!
//! Four sections, and two of them can embarrass the design:
//!
//!   1. **accept** — one row per grammar: files taken, files refused with the
//!      construct that did it, patterns, program bytes, and microseconds. The
//!      last two are the point of pressing a query at all: tree-sitter re-parses
//!      its `.scm` on every process start, so the honest comparison is our
//!      compile time against the bytes a folio then carries instead.
//!   2. **dead** — how many patterns in real files can never match. Interesting
//!      either way. A few means the check earns its place; zero means the corpus
//!      is clean and the check is for the query somebody writes tomorrow.
//!   3. **lookup** — a built-once `StringHashMap` against `press.dafsa.rank`,
//!      which is a minimal perfect hash over the same sorted keys. The DAFSA
//!      lost 2.85x–4.33x as a STORAGE format last wave, and that is a different
//!      question from whether it is the right LOOKUP, so both are built and
//!      probed here rather than inherited.
//!   4. **regex** — the lane's headline, priced. tree-sitter evaluates `#match?`
//!      in the host binding, once per candidate match. We compile it when the
//!      query is compiled. Both arms are timed against the corpus's own
//!      patterns, so the number is the real one rather than a microbenchmark's.
//!
//! No timing floors. Every arm here runs on a laptop that is also running nine
//! other agents; the assertions are the deterministic ones — a refused file is
//! reported and not swallowed, `rank` must answer for every key it was given,
//! and a program the writer just wrote must read back.

const std = @import("std");
const joints = @import("joints");
const irregex = @import("irregex");

const press = joints.press;
const folio = joints.folio;
const gloss = joints.kernel.gloss;
/// The package's own stopwatch, on the awake clock, so a suspend never turns
/// into a measurement. Same instrument every other rung here reads.
const Span = joints.assay.Span;

const queries = ".local/glossprobe/queries";
const grammars = "upstream/grammars";

/// One `.scm` file, compiled. `refusal` null means it was taken.
const Row = struct {
    file: []const u8,
    refusal: ?[]const u8 = null,
    /// Byte offset the refusal points at, so a report can name a line.
    at: u32 = 0,
    /// The name that did not resolve, when the refusal was about a name. It
    /// borrows the file's own bytes, which outlive the run.
    name: []const u8 = "",
    patterns: u32 = 0,
    steps: u32 = 0,
    bytes: usize = 0,
    source: usize = 0,
    nanos: u64 = 0,
    dead: u32 = 0,
    /// Dead patterns by cause, so the section below can say WHICH check earned
    /// its place rather than that some check fired.
    causes: std.EnumArray(gloss.Cause, u32) = .initFill(0),
    /// Where the first one is, so a reader can go look at the line.
    first: u32 = 0,
    core: u32 = 0,
    carried: u32 = 0,
};

/// Everything one grammar's files add up to.
const Tally = struct {
    tag: []const u8,
    files: u32 = 0,
    taken: u32 = 0,
    patterns: u32 = 0,
    bytes: usize = 0,
    source: usize = 0,
    nanos: u64 = 0,
    dead: u32 = 0,
    dead_files: u32 = 0,
    core: u32 = 0,
    carried: u32 = 0,
    /// Wall time to press the grammar and index it, which is what a query
    /// compile is dwarfed by and worth saying so.
    setup_nanos: u64 = 0,
    symbols: u32 = 0,
    passes: u32 = 0,
};

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const gpa = arena.allocator();

    var buf: [1 << 16]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &buf);
    const out = &stdout.interface;
    defer out.flush() catch {};

    var threaded = std.Io.Threaded.init(init.gpa, .{});
    defer threaded.deinit();
    const io = threaded.io();

    try out.print("\ngloss — every query the pinned grammars ship, compiled\n\n", .{});

    const slate = corpus(gpa, io) catch |e| {
        try out.print("  no query corpus underfoot ({s}); see `.local/glossprobe/`\n", .{@errorName(e)});
        return;
    };
    if (slate.len == 0) {
        try out.print("  no query corpus underfoot; see `.local/glossprobe/`\n", .{});
        return;
    }

    var rows: std.ArrayList(Row) = .empty;
    var tallies: std.ArrayList(Tally) = .empty;
    var lookups: std.ArrayList(Lookup) = .empty;
    var missing: u32 = 0;

    for (slate) |g| {
        var t: Tally = .{ .tag = g.tag };
        const before = rows.items.len;
        const measured = run(gpa, io, g, &rows, &t) catch |e| {
            if (e == error.FileNotFound) {
                missing += 1;
                rows.shrinkRetainingCapacity(before);
                continue;
            }
            return e;
        };
        try tallies.append(gpa, t);
        try lookups.append(gpa, measured);
    }

    try accept(out, tallies.items, rows.items);
    try refused(out, rows.items);
    try dead(out, tallies.items, rows.items);
    try lookup(out, lookups.items);
    try regex(gpa, io, out, slate);

    if (missing != 0) {
        try out.print("\n  {d} grammar(s) had queries but no pressed grammar underfoot; " ++
            "run `python3 tool/grammars.py fetch`\n", .{missing});
    }
}

// ── the corpus ──

const Grammar = struct {
    tag: []const u8,
    path: []const u8,
    files: []const []const u8,
};

/// Every grammar that ships a query file, with its files, discovered rather
/// than listed. A hardcoded slate would go stale the day the corpus is refetched
/// and would quietly under-report instead of failing.
fn corpus(gpa: std.mem.Allocator, io: std.Io) ![]const Grammar {
    var dir = try std.Io.Dir.cwd().openDir(io, queries, .{ .iterate = true });
    defer dir.close(io);

    // Grouped by the prefix before `__`, which is how the fetcher flattened
    // `<grammar>/queries/<file>.scm` into one directory.
    var by_tag: std.StringArrayHashMapUnmanaged(std.ArrayList([]const u8)) = .empty;
    var walk = dir.iterate();
    while (try walk.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".scm")) continue;
        const name = try gpa.dupe(u8, entry.name);
        const cut = std.mem.indexOf(u8, name, "__") orelse continue;
        const slot = try by_tag.getOrPut(gpa, name[0..cut]);
        if (!slot.found_existing) slot.value_ptr.* = .empty;
        try slot.value_ptr.append(gpa, name);
    }

    var out: std.ArrayList(Grammar) = .empty;
    for (by_tag.keys(), by_tag.values()) |tag, files| {
        std.mem.sort([]const u8, files.items, {}, less);
        try out.append(gpa, .{
            .tag = tag,
            .path = try std.fmt.allocPrint(gpa, "{s}/{s}.json", .{ grammars, tag }),
            .files = files.items,
        });
    }
    std.mem.sort(Grammar, out.items, {}, byTag);
    return out.items;
}

fn less(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

fn byTag(_: void, a: Grammar, b: Grammar) bool {
    return std.mem.lessThan(u8, a.tag, b.tag);
}

/// One grammar: press it, index it, compile every query it ships.
fn run(
    gpa: std.mem.Allocator,
    io: std.Io,
    g: Grammar,
    rows: *std.ArrayList(Row),
    t: *Tally,
) !Lookup {
    const src = try std.Io.Dir.cwd().readFileAlloc(io, g.path, gpa, .limited(64 << 20));
    var sp = Span.open(io);
    var gr = try press.treeSitter(gpa, src);
    defer gr.deinit();
    var built = try press.tables(gpa, &gr);
    defer built.deinit();
    const bytes = try folio.pack(gpa, &gr, &built);
    var f = try folio.open(bytes);
    var l = try gloss.index(gpa, &f);
    defer l.deinit();
    t.setup_nanos = nanos(sp.read(io));
    t.symbols = f.symbolCount();
    t.passes = l.passes;

    for (g.files) |name| {
        const path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ queries, name });
        const text = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(16 << 20));
        var row: Row = .{ .file = name, .source = text.len };
        t.files += 1;

        var fault: gloss.Fault = .{};
        sp = Span.open(io);
        var c = gloss.compile(gpa, &l, text, &fault) catch |e| {
            row.nanos = nanos(sp.read(io));
            row.refusal = @errorName(e);
            row.at = fault.at;
            row.name = fault.name;
            try rows.append(gpa, row);
            continue;
        };
        row.nanos = nanos(sp.read(io));
        defer c.deinit();

        // The claim the whole section exists for: what the writer just wrote,
        // a reader that has only bytes can read. Checked per file rather than
        // once, because a program that fails to read back is a program that
        // would have been written into a folio.
        const p = c.view() orelse return error.ProgramDidNotReadBack;
        row.patterns = p.patternCount();
        row.steps = p.stepCount();
        row.bytes = c.bytes.len;
        row.dead = @intCast(c.dead.len);
        for (c.dead) |d| row.causes.getPtr(d.cause).* += 1;
        if (c.dead.len != 0) row.first = c.dead[0].at;
        row.carried = c.opaque_predicates;
        row.core = p.predicateCount() - c.opaque_predicates;

        t.taken += 1;
        t.patterns += row.patterns;
        // Source is tallied here rather than on the way in, so `src B` and
        // `prog B` describe the same files and the ratio between them means
        // something. A refused file's bytes in the numerator's denominator
        // read as compression that did not happen.
        t.source += text.len;
        t.bytes += row.bytes;
        t.nanos += row.nanos;
        t.dead += row.dead;
        t.core += row.core;
        t.carried += row.carried;
        if (row.dead != 0) t.dead_files += 1;
        try rows.append(gpa, row);
    }
    return try probe(gpa, io, &gr, &f);
}

// ── section 1: acceptance ──

fn accept(out: *std.Io.Writer, tallies: []const Tally, rows: []const Row) !void {
    try out.print(
        "  {s:<18} {s:>5} {s:>5} {s:>7} {s:>8} {s:>8} {s:>6} {s:>8} {s:>6} {s:>7}\n",
        .{ "grammar", "files", "took", "pats", "src B", "prog B", "x", "µs", "core", "carried" },
    );
    var files: u32 = 0;
    var taken: u32 = 0;
    var patterns: u32 = 0;
    var prog: usize = 0;
    var source: usize = 0;
    var elapsed: u64 = 0;
    var core: u32 = 0;
    var carried: u32 = 0;
    for (tallies) |t| {
        files += t.files;
        taken += t.taken;
        patterns += t.patterns;
        prog += t.bytes;
        source += t.source;
        elapsed += t.nanos;
        core += t.core;
        carried += t.carried;
        try out.print(
            "  {s:<18} {d:>5} {d:>5} {d:>7} {d:>8} {d:>8} {d:>5.2}x {d:>8.0} {d:>6} {d:>7}\n",
            .{
                t.tag,                    t.files,       t.taken,
                t.patterns,               t.source,      t.bytes,
                ratio(t.bytes, t.source), micros(t.nanos),
                t.core,                   t.carried,
            },
        );
    }
    try out.print(
        "  {s:<18} {d:>5} {d:>5} {d:>7} {d:>8} {d:>8} {d:>5.2}x {d:>8.0} {d:>6} {d:>7}\n",
        .{
            "TOTAL",              files, taken,
            patterns,             source, prog,
            ratio(prog, source),  micros(elapsed),
            core,                 carried,
        },
    );
    if (taken != files) {
        try out.print("\n  {d} of {d} refused — see below\n", .{ files - taken, files });
    }
    // The rung's own premise, and it fails loud rather than printing a low
    // number in a table nobody reads twice.
    if (rows.len != files) return error.RowsDoNotMatchFiles;
}

fn refused(out: *std.Io.Writer, rows: []const Row) !void {
    var any = false;
    for (rows) |r| {
        const why = r.refusal orelse continue;
        if (!any) try out.print("\n  refused, with the construct that did it:\n", .{});
        any = true;
        if (r.name.len == 0) {
            try out.print("    {s:<44} {s} at byte {d}\n", .{ r.file, why, r.at });
        } else {
            try out.print(
                "    {s:<44} {s} {s} at byte {d}\n",
                .{ r.file, why, r.name, r.at },
            );
        }
    }
}

// ── section 2: static reachability ──

fn dead(out: *std.Io.Writer, tallies: []const Tally, rows: []const Row) !void {
    var total: u32 = 0;
    var files: u32 = 0;
    for (tallies) |t| {
        total += t.dead;
        files += t.dead_files;
    }
    try out.print(
        "\n  statically dead: {d} pattern(s) across {d} file(s) — patterns that " ++
            "name only real\n  kinds and fields and still cannot match\n",
        .{ total, files },
    );
    if (total == 0) return;
    var by_cause: std.EnumArray(gloss.Cause, u32) = .initFill(0);
    for (rows) |r| {
        if (r.dead == 0) continue;
        for (std.enums.values(gloss.Cause)) |c| by_cause.getPtr(c).* += r.causes.get(c);
        try out.print(
            "    {s:<44} {d:>3} of {d:<4} first at byte {d}\n",
            .{ r.file, r.dead, r.patterns, r.first },
        );
    }
    try out.print("\n  by cause:\n", .{});
    var it = by_cause.iterator();
    while (it.next()) |e| {
        if (e.value.* == 0) continue;
        try out.print("    {s:<24} {d}\n", .{ @tagName(e.key), e.value.* });
    }
}

// ── section 3: name lookup ──

const Lookup = struct {
    tag: []const u8,
    keys: u32,
    /// Build once, then probe every key.
    map_build: u64,
    map_probe: u64,
    rank_build: u64,
    rank_probe: u64,
    /// Symbols that share a spelling with an earlier symbol. A query name is a
    /// SET, not an id, exactly as far as this number is above zero.
    shared: u32,
};

/// Both indexes over the same keys, built and probed the same way. The probe is
/// every name in the grammar, in the order the folio wrote them, which is the
/// order a query does NOT ask in — so neither arm gets a cache-friendly walk
/// the other does not.
fn probe(
    gpa: std.mem.Allocator,
    io: std.Io,
    gr: *const press.Grammar,
    f: *const folio.Folio,
) !Lookup {
    const n = f.symbolCount();
    var sp = Span.open(io);

    var map: std.StringHashMapUnmanaged(u32) = .empty;
    defer map.deinit(gpa);
    try map.ensureTotalCapacity(gpa, n);
    var shared: u32 = 0;
    for (0..n) |i| {
        const slot = map.getOrPutAssumeCapacity(f.nameOf(@intCast(i)));
        if (slot.found_existing) shared += 1;
        slot.value_ptr.* = @intCast(i);
    }
    const map_build = nanos(sp.lap(io));

    var sink: u64 = 0;
    for (0..n) |i| sink +%= map.get(f.nameOf(@intCast(i))) orelse return error.MapMissedItsOwnKey;
    const map_probe = nanos(sp.lap(io));

    var names = try press.dafsa.names(gpa, gr);
    defer names.deinit();
    const rank_build = nanos(sp.lap(io));

    for (names.keys) |k| sink +%= names.ordinalOf(k) orelse return error.RankMissedItsOwnKey;
    const rank_probe = nanos(sp.lap(io));

    // The DAFSA answers an ordinal over its own sorted key set, so it needs a
    // second array to get from ordinal to symbol id. Not timed - the point is
    // that it is not free, and the table below says so in a footnote rather
    // than pretending the two arms answer the same question.
    std.mem.doNotOptimizeAway(sink);
    return .{
        .tag = gr.name,
        .keys = @intCast(names.keys.len),
        .map_build = map_build,
        .map_probe = map_probe,
        .rank_build = rank_build,
        .rank_probe = rank_probe,
        .shared = shared,
    };
}

fn lookup(out: *std.Io.Writer, all: []const Lookup) !void {
    try out.print(
        "\n  name lookup — hash map against dafsa rank, over the same keys\n\n" ++
            "  {s:<18} {s:>6} {s:>9} {s:>9} {s:>7} {s:>9} {s:>9} {s:>7} {s:>7}\n",
        .{ "grammar", "keys", "map µs", "rank µs", "build", "map ns/k", "rank ns/k", "probe", "shared" },
    );
    var keys: u64 = 0;
    var mb: u64 = 0;
    var rb: u64 = 0;
    var mp: u64 = 0;
    var rp: u64 = 0;
    for (all) |x| {
        keys += x.keys;
        mb += x.map_build;
        rb += x.rank_build;
        mp += x.map_probe;
        rp += x.rank_probe;
        try out.print(
            "  {s:<18} {d:>6} {d:>9.0} {d:>9.0} {d:>6.2}x {d:>9.1} {d:>9.1} {d:>6.2}x {d:>7}\n",
            .{
                x.tag,                        x.keys,
                micros(x.map_build),          micros(x.rank_build),
                ratio(x.rank_build, x.map_build),
                per(x.map_probe, x.keys),     per(x.rank_probe, x.keys),
                ratio(x.rank_probe, x.map_probe),
                x.shared,
            },
        );
    }
    try out.print(
        "  {s:<18} {d:>6} {d:>9.0} {d:>9.0} {d:>6.2}x {d:>9.1} {d:>9.1} {d:>6.2}x\n",
        .{
            "TOTAL",              keys,
            micros(mb),           micros(rb),
            ratio(rb, mb),        per(mp, keys),
            per(rp, keys),        ratio(rp, mp),
        },
    );
    try out.print(
        \\
        \\  Over 1.00x the DAFSA loses. It also answers a different question: an
        \\  ordinal over its own sorted keys, which needs a second array to reach
        \\  a symbol id, and it cannot hold the three sorts a query distinguishes
        \\  (kind, literal, category) without one map per sort. The map is what
        \\  `lemma` uses.
        \\
    , .{});
}

// ── section 4: the predicate headline ──

/// Every `#match?` pattern the corpus writes, in the order it writes them.
/// Extracted by compiling — the strings that reach `sift` are the strings a
/// matcher would have to run, and taking them from the parse rather than from a
/// grep is what makes this the real slate.
fn regex(gpa: std.mem.Allocator, io: std.Io, out: *std.Io.Writer, slate: []const Grammar) !void {
    var pats: std.ArrayList([]const u8) = .empty;
    for (slate) |g| {
        for (g.files) |name| {
            const path = std.fmt.allocPrint(gpa, "{s}/{s}", .{ queries, name }) catch continue;
            const text = std.Io.Dir.cwd().readFileAlloc(
                io,
                path,
                gpa,
                .limited(16 << 20),
            ) catch continue;
            try harvest(gpa, text, &pats);
        }
    }
    if (pats.items.len == 0) return;

    // The subject strings a highlighter actually tests: identifiers, keywords,
    // and punctuation, which is what a capture's text is in nearly every rule.
    const subjects = [_][]const u8{
        "self",       "Self",         "SCREAMING_CASE", "lowerCamel",
        "UpperCamel", "snake_case",   "__dunder__",     "x",
        "return",     "0xdeadbeef",   "\"a string\"",   "->",
    };

    var hits: u64 = 0;

    // Arm A — ours. Compile once when the query is compiled, then run.
    var sp = Span.open(io);
    var compiled: std.ArrayList(irregex.Pattern) = .empty;
    defer for (compiled.items) |*p| p.deinit();
    for (pats.items) |src| {
        try compiled.append(gpa, irregex.Pattern.compile(gpa, src) catch continue);
    }
    const ours_compile = nanos(sp.lap(io));

    for (compiled.items) |*p| {
        for (subjects) |s| hits += @intFromBool(p.isMatch(s) catch false);
    }
    const ours_run = nanos(sp.lap(io));

    // Arm B — the host-binding shape. tree-sitter hands the pattern and the
    // candidate's text across the FFI edge per match; a host that does not
    // memoize pays the compile every time, and a host that does still pays a
    // lookup and a callback. This is the un-memoized arm, which is what the
    // documented weakness describes.
    _ = sp.lap(io);
    for (pats.items) |src| {
        for (subjects) |s| {
            var p = irregex.Pattern.compile(gpa, src) catch continue;
            defer p.deinit();
            hits += @intFromBool(p.isMatch(s) catch false);
        }
    }
    const theirs = nanos(sp.lap(io));
    std.mem.doNotOptimizeAway(hits);

    const candidates = pats.items.len * subjects.len;
    try out.print(
        \\
        \\  #match? — compiled with the query against compiled per candidate
        \\
        \\    patterns in the corpus     {d}
        \\    candidate matches simulated {d}
        \\    compile once, at query compile time   {d:>10.0} µs
        \\    then run over every candidate         {d:>10.0} µs   ({d:.1} ns each)
        \\    total, ours                           {d:>10.0} µs
        \\    compile per candidate (host binding)  {d:>10.0} µs   ({d:.1} ns each)
        \\    speedup                               {d:>10.1}x
        \\
        \\  The compile is paid once per query PROGRAM either way; what the corpus
        \\  decides is how many candidates amortize it. A `highlights.scm` run over
        \\  one file is thousands, so the ratio above is the floor rather than the
        \\  claim.
        \\
    , .{
        pats.items.len,
        candidates,
        micros(ours_compile),
        micros(ours_run),
        per(ours_run, candidates),
        micros(ours_compile + ours_run),
        micros(theirs),
        per(theirs, candidates),
        ratio(theirs, ours_compile + ours_run),
    });
}

/// Pull the second argument of every `#match?` / `#not-match?` out of a query
/// file. A reader would be tidier, but this arm has to price the PATTERNS and
/// not the parse, and a file that fails to compile still has patterns in it.
fn harvest(gpa: std.mem.Allocator, text: []const u8, into: *std.ArrayList([]const u8)) !void {
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, text, at, "match? ")) |i| {
        at = i + "match? ".len;
        const open = std.mem.indexOfPos(u8, text, at, "\"") orelse break;
        // No unescaping: the engine takes the source bytes, and a `\"` inside
        // the pattern would only end this scan early - which loses a pattern
        // rather than inventing one.
        const close = std.mem.indexOfPos(u8, text, open + 1, "\"") orelse break;
        if (close > open + 1) try into.append(gpa, text[open + 1 .. close]);
        at = close + 1;
    }
}

// ── arithmetic ──

/// A `Duration` as the `u64` the tallies add up. Negative is impossible on the
/// awake clock and would be a bug in the clock rather than in the arm, so it
/// saturates rather than carrying a signed zero through every sum.
fn nanos(d: joints.assay.Duration) u64 {
    return @intCast(@max(0, d.ns()));
}

fn micros(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / 1000.0;
}

fn per(ns: u64, n: usize) f64 {
    return @as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(@max(1, n)));
}

fn ratio(a: anytype, b: anytype) f64 {
    return @as(f64, @floatFromInt(a)) / @as(f64, @floatFromInt(@max(1, b)));
}
