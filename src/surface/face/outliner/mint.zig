//! `outliner mint` - press a grammar into a folio, and read one back.
//!
//! Minting is the act the vocabulary already had a word for, and it keeps the
//! verb from colliding with the noun: `mint` is what you do, a folio is what you
//! get. Pressing is slow and happens once; loading is fast and happens every
//! time an editor opens a file, so the two live behind one verb that can be
//! asked to do either and to compare the sizes.
//!
//! Hand it a grammar.json and it presses, writes the folio beside it, maps that
//! file back, and checks every cell of the reloaded table against the one still
//! in memory. That last step is the reason the verb is worth running at all: a
//! size claim about a file nobody has read back is not a claim about anything.
//! Hand it a folio and it skips straight to the reading, which is the half an
//! editor actually pays for.
//!
//! The sizes are printed and not editorialized. Tree-sitter's dense table is
//! 64% of a 30 MB `parser.c` at 24.3% density; the number here is the argument,
//! so it gets stated and left alone.

const std = @import("std");
const outliner = @import("outliner");

const folio = outliner.folio;
const leaf = folio.leaf;
const import = outliner.press.import;
const press = outliner.press;
const g = outliner.press.grammar;
const lr0 = outliner.press.lr0;

pub fn run(
    gpa: std.mem.Allocator,
    io: std.Io,
    w: *std.Io.Writer,
    args: []const []const u8,
) !u8 {
    var out: ?[]const u8 = null;
    var path: ?[]const u8 = null;
    var rest = args;
    while (rest.len > 0) : (rest = rest[1..]) {
        const a = rest[0];
        if (std.mem.eql(u8, a, "-o") or std.mem.eql(u8, a, "--out")) {
            if (rest.len < 2) {
                try w.writeAll("outliner: -o needs a path\n");
                return 2;
            }
            rest = rest[1..];
            out = rest[0];
        } else path = a;
    }
    if (path == null) {
        try w.writeAll("outliner: mint needs a grammar.json or a folio\n");
        return 2;
    }

    // Which of the two jobs this is gets answered by trying the cheap one. A
    // path that is not a folio says so in its first eight bytes and costs a
    // mapping to find out; anything else that goes wrong is a real folio
    // failing, and reporting *that* as "cannot import a grammar" would be the
    // wrong sentence about the right file.
    const at = std.Io.Clock.awake.now(io);
    if (folio.map(io, std.Io.Dir.cwd(), path.?)) |opened| {
        var mapped = opened;
        defer mapped.close();
        // Bound, not merely mapped. What an editor pays to open a language is
        // map plus verify plus the table laid back out, and timing the first
        // two would be quoting a number nothing can parse from.
        var bound = try folio.bind(gpa, &mapped.folio);
        defer bound.deinit();
        try report(w, &mapped.folio, &bound, .{
            .source = null,
            .folio = mapped.bytes.len,
            .memory = null,
            .path = path.?,
            .load_us = since(io, at),
        });
        return 0;
    } else |e| switch (e) {
        error.FolioBadMagic, error.FolioTooSmall, error.FileNotFound => {},
        else => {
            try w.print("outliner: {s} does not load: {s}\n", .{ path.?, @errorName(e) });
            return 1;
        },
    }
    return write(gpa, io, w, path.?, out);
}

fn write(
    gpa: std.mem.Allocator,
    io: std.Io,
    w: *std.Io.Writer,
    path: []const u8,
    out: ?[]const u8,
) !u8 {
    const source = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64 << 20)) catch |e| {
        try w.print("outliner: cannot read {s}: {s}\n", .{ path, @errorName(e) });
        return 2;
    };
    defer gpa.free(source);

    var gr = import.treeSitter(gpa, source) catch |e| {
        try w.print("outliner: cannot import {s}: {s}\n", .{ path, @errorName(e) });
        return 2;
    };
    defer gr.deinit();

    const pressed_at = std.Io.Clock.awake.now(io);
    var built = try press.tables(gpa, &gr);
    defer built.deinit();
    const press_us = since(io, pressed_at);

    const packed_at = std.Io.Clock.awake.now(io);
    const bytes = folio.pack(gpa, &gr, &built) catch |e| {
        try w.print("outliner: cannot pack {s}: {s}\n", .{ gr.name, @errorName(e) });
        return 2;
    };
    defer gpa.free(bytes);
    const pack_us = since(io, packed_at);

    const target = out orelse try swapExtension(gpa, path);
    defer if (out == null) gpa.free(target);
    folio.writeTo(io, std.Io.Dir.cwd(), target, bytes) catch |e| {
        try w.print("outliner: cannot write {s}: {s}\n", .{ target, @errorName(e) });
        return 2;
    };

    // Read back the file that was just published, not the buffer it came from.
    // A writer checking its own bytes proves nothing about what landed on disk.
    const loaded_at = std.Io.Clock.awake.now(io);
    var mapped = folio.map(io, std.Io.Dir.cwd(), target) catch |e| {
        try w.print("outliner: {s} does not load: {s}\n", .{ target, @errorName(e) });
        return 1;
    };
    defer mapped.close();
    var bound = try folio.bind(gpa, &mapped.folio);
    defer bound.deinit();
    const load_us = since(io, loaded_at);

    try report(w, &mapped.folio, &bound, .{
        .source = source.len,
        .folio = bytes.len,
        .memory = footprint(&gr, &built),
        .path = target,
        .press_us = press_us,
        .pack_us = pack_us,
        .load_us = load_us,
    });

    if (disagrees(&mapped.folio, &bound, &gr, &built)) |what| {
        try w.print("\n  MISMATCH: {s}\n", .{what});
        return 1;
    }
    try w.print("\n  reloaded from disk and identical to the pressed tables\n", .{});
    return 0;
}

const Sizes = struct {
    /// The grammar.json this came from, when there was one.
    source: ?usize,
    folio: usize,
    memory: ?Footprint,
    path: []const u8,
    press_us: i64 = 0,
    pack_us: i64 = 0,
    load_us: i64,
};

fn report(w: *std.Io.Writer, f: *const folio.Folio, b: *const folio.Bound, s: Sizes) !void {
    const h = f.head;
    try w.print("{s}\n", .{f.title()});
    if (s.source) |n| try w.print("  grammar.json   {d: >12} bytes\n", .{n});
    if (s.memory) |m| {
        try w.print("  pressed        {d: >12} bytes in memory ({d} grammar, {d} automaton, {d} table)\n", .{
            m.total(), m.grammar, m.automaton, m.table,
        });
    }
    try w.print("  folio          {d: >12} bytes  {s}\n", .{ s.folio, s.path });
    if (s.source) |n| {
        try w.print("                 {d:.2}x the grammar.json", .{ratio(s.folio, n)});
        if (s.memory) |m| try w.print(", {d:.2}x the pressed tables", .{ratio(s.folio, m.total())});
        try w.writeAll("\n");
    }

    try w.print("\n  symbols        {d} ({d} terminal, {d} nonterminal)\n", .{
        h.symbol_count, h.terminal_count, h.symbol_count - h.terminal_count,
    });
    try w.print("  productions    {d}\n", .{h.production_count});
    try w.print("  states         {d}\n", .{h.state_count});

    var live: usize = 0;
    for (b.tables.action) |a| {
        if (a.kind != .err) live += 1;
    }
    const cells = b.tables.action.len;
    try w.print("  table          {d} x {d} = {d} cells, {d}% dense\n", .{
        h.state_count, h.width, cells, live * 100 / @max(cells, 1),
    });
    // The three interning layers, and what the grid above would have cost
    // written out. This is the size argument, so it gets the numbers.
    try w.print("  interned       {d} rows, {d} groups, {d} column sets, {d} strays\n", .{
        f.rowCount(),
        f.dir[@intFromEnum(leaf.Kind.group)].count,
        f.dir[@intFromEnum(leaf.Kind.set_span)].count - 1,
        f.odds().len,
    });
    if (h.unfolded > 0) {
        try w.print("  unfolded       {d} round(s) to separate merged lookaheads\n", .{h.unfolded});
    }
    if (f.word()) |sym| try w.print("  word           {s}\n", .{f.nameOf(sym)});

    try w.print("\n  {s: <14} {s: >9} {s: >12}  {s}\n", .{ "section", "count", "bytes", "share" });
    for (std.enums.values(leaf.Kind)) |k| {
        const e = f.dir[@intFromEnum(k)];
        const n = @as(usize, e.count) * e.stride;
        if (n == 0) continue;
        try w.print("  {s: <14} {d: >9} {d: >12}  {d: >5.1}%\n", .{
            @tagName(k), e.count, n, 100.0 * ratio(n, s.folio),
        });
    }

    try w.print("\n  version {d}, schema {s}\n", .{ h.version, h.schema.hex()[0..16] });
    if (s.press_us > 0) {
        try w.print("  pressed in {d} us, packed in {d} us, loaded in {d} us\n", .{
            s.press_us, s.pack_us, s.load_us,
        });
    } else try w.print("  loaded in {d} us\n", .{s.load_us});
}

/// What the same data costs as live structures, so the folio's number has
/// something to be compared against that is not the JSON it came from. Slice
/// payloads only: the headers and the arenas' own slack are real but they are
/// an allocator's business, not the format's.
const Footprint = struct {
    grammar: usize,
    automaton: usize,
    table: usize,

    fn total(m: Footprint) usize {
        return m.grammar + m.automaton + m.table;
    }
};

/// `built` is taken generically because `press.Result` is not part of the
/// module root's public surface and adding it there is another lane's file.
fn footprint(gr: *const g.Grammar, built: anytype) Footprint {
    var m: Footprint = .{ .grammar = 0, .automaton = 0, .table = 0 };
    m.grammar += gr.name.len;
    for (gr.names) |n| m.grammar += n.len + @sizeOf([]const u8);
    for (gr.patterns) |p| {
        m.grammar += @sizeOf(?g.Pattern) + switch (p orelse continue) {
            .literal, .regex => |text| text.len,
            .external => 0,
        };
    }
    m.grammar += gr.lexis.len * @sizeOf(g.Lexis);
    m.grammar += gr.shapes.len * @sizeOf(g.Shape);
    m.grammar += gr.owner.len * @sizeOf(g.Symbol);
    m.grammar += (gr.extras.len + gr.supertypes.len) * @sizeOf(g.Symbol);
    for (gr.aliases) |a| m.grammar += a.name.len + @sizeOf(g.Alias);
    for (gr.field_names) |n| m.grammar += n.len + @sizeOf([]const u8);
    for (gr.productions) |p| {
        m.grammar += @sizeOf(g.Production) + p.rhs.len * @sizeOf(g.Symbol) + p.steps.len * @sizeOf(g.Step);
    }
    for (built.collection.states) |st| {
        m.automaton += @sizeOf(lr0.State) +
            st.kernel.len * @sizeOf(lr0.Item) +
            st.edges.len * @sizeOf(lr0.Edge) +
            st.complete.len * @sizeOf(u32);
    }
    m.table = built.tables.action.len * @sizeOf(outliner.press.lalr.Action);
    return m;
}

/// The first thing the reloaded folio gets wrong, if anything. Names first,
/// because a name that shifted is the failure that would still parse.
///
/// The table and the automaton are checked through `bind` rather than off the
/// file, and deliberately: what is on disk is interned three layers deep and
/// the transitions are half derived from it, so comparing the sections to the
/// press would only prove the writer agrees with itself. What has to match is
/// what a parse would actually read.
fn disagrees(
    f: *const folio.Folio,
    b: *const folio.Bound,
    gr: *const g.Grammar,
    built: anytype,
) ?[]const u8 {
    if (f.symbolCount() != gr.symbolCount()) return "symbol count";
    for (0..gr.symbolCount()) |i| {
        const s: u32 = @intCast(i);
        if (!std.mem.eql(u8, gr.nameOf(s), f.nameOf(s))) return "a symbol name";
        if (gr.owner[s] != f.ownerOf(s)) return "a symbol's owner";
        if (!std.mem.eql(u8, @tagName(gr.shapeOf(s)), @tagName(f.shapeOf(s)))) return "a symbol's shape";
    }
    if (f.head.production_count != gr.productions.len) return "production count";
    for (gr.productions, 0..) |p, i| {
        if (!std.mem.eql(g.Symbol, p.rhs, f.rhsOf(@intCast(i)))) return "a production body";
    }
    if (f.head.state_count != built.collection.states.len) return "state count";
    for (built.collection.states, b.collection.states) |st, back| {
        if (st.edges.len != back.edges.len) return "an edge list";
        for (st.edges, back.edges) |want, got| {
            if (want.symbol != got.symbol or want.target != got.target) return "an edge";
        }
        if (st.complete.len != back.complete.len) return "a completion list";
        for (st.complete, back.complete) |want, got| {
            if (want != got) return "a completion";
        }
    }
    if (b.tables.action.len != built.tables.action.len) return "table size";
    for (built.tables.action, b.tables.action) |want, back| {
        if (want.kind != back.kind or want.value != back.value) return "an action cell";
    }
    if (b.tables.conflicts.len != built.tables.conflicts.len) return "conflict count";
    for (built.tables.conflicts, b.tables.conflicts) |want, back| {
        if (want.state != back.state or want.terminal != back.terminal) return "a conflict cell";
        if (want.kind != back.kind or want.class != back.class) return "a conflict's kind";
        if (want.chosen.value != back.chosen.value) return "a conflict's verdict";
        if (want.party.len != back.party.len) return "a conflict's party";
    }
    return null;
}

fn swapExtension(gpa: std.mem.Allocator, path: []const u8) ![]const u8 {
    const stem = path[0 .. path.len - std.fs.path.extension(path).len];
    return std.fmt.allocPrint(gpa, "{s}.folio", .{stem});
}

fn ratio(a: usize, b: usize) f64 {
    return if (b == 0) 0 else @as(f64, @floatFromInt(a)) / @as(f64, @floatFromInt(b));
}

fn since(io: std.Io, from: std.Io.Timestamp) i64 {
    return @intCast(@divTrunc(
        from.durationTo(std.Io.Clock.awake.now(io)).nanoseconds,
        std.time.ns_per_us,
    ));
}
