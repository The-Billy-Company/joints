//! `joints mint` - press a grammar into a folio, and read one back.
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
//! Hand it **several** - grammar.jsons, minted folios, any mixture - with `-o`
//! and it binds them into one codex: the "N languages, one file" artifact.
//! Each grammar pressed here still gets the cell-by-cell read-back check; a
//! member that arrived as a folio is embedded as it stands. Hand it a codex
//! and it reads every member back, seal and bind, one line per language.
//!
//! The sizes are printed and not editorialized. Tree-sitter's dense table is
//! 64% of a 30 MB `parser.c` at 24.3% density; the number here is the argument,
//! so it gets stated and left alone.

const std = @import("std");
const joints = @import("joints");
const intake = @import("intake.zig");

const folio = joints.folio;
const leaf = folio.leaf;
const press = joints.press;

pub fn run(
    gpa: std.mem.Allocator,
    io: std.Io,
    w: *std.Io.Writer,
    args: []const []const u8,
) !u8 {
    var out: ?[]const u8 = null;
    var paths: std.ArrayList([]const u8) = .empty;
    defer paths.deinit(gpa);
    var rest = args;
    while (rest.len > 0) : (rest = rest[1..]) {
        const a = rest[0];
        if (std.mem.eql(u8, a, "-o") or std.mem.eql(u8, a, "--out")) {
            if (rest.len < 2) {
                try w.writeAll("joints: -o needs a path\n");
                return 2;
            }
            rest = rest[1..];
            out = rest[0];
        } else try paths.append(gpa, a);
    }
    if (paths.items.len == 0) {
        try w.writeAll("joints: mint needs a grammar.json or a folio\n");
        return 2;
    }
    // Several grammars are one codex, and that is the whole sentence: until
    // 2026-08-07 this loop kept the last path and pressed it alone, so
    // `mint python.json rust.json -o both.folio` reported success and wrote a
    // rust-only folio. A silent drop in the verb whose one job is publishing
    // the artifact is the worst bug this CLI has had.
    if (paths.items.len > 1) return gathering(gpa, io, w, paths.items, out);
    const path = paths.items[0];

    // Which of the two jobs this is gets answered by trying the cheap one. A
    // path that is not a folio says so in its first eight bytes and costs a
    // mapping to find out; anything else that goes wrong is a real folio
    // failing, and reporting *that* as "cannot import a grammar" would be the
    // wrong sentence about the right file.
    const at = std.Io.Clock.awake.now(io);
    if (folio.mapVolume(io, std.Io.Dir.cwd(), path)) |opened| {
        var mapped = opened;
        defer mapped.close();
        switch (mapped.volume) {
            .one => |f| {
                // Bound, not merely mapped. What an editor pays to open a
                // language is map plus verify plus the table laid back out,
                // and timing the first two would be quoting a number nothing
                // can parse from.
                var lone = f;
                var bound = folio.bind(gpa, &lone) catch |e| {
                    try w.print("joints: cannot bind {s}: {s}\n", .{ path, @errorName(e) });
                    return 2;
                };
                defer bound.deinit();
                try report(w, &lone, &bound, .{
                    .source = null,
                    .folio = mapped.bytes.len,
                    .memory = null,
                    .path = path,
                    .load_us = since(io, at),
                });
            },
            .many => |*c| return contents(gpa, io, w, c, mapped.bytes.len, path, at),
        }
        return 0;
    } else |e| switch (e) {
        error.FolioBadMagic, error.FolioTooSmall, error.FileNotFound => {},
        else => {
            try w.print("joints: {s} does not load: {s}\n", .{ path, @errorName(e) });
            return 1;
        },
    }
    return write(gpa, io, w, path, out);
}

/// Read a codex back: every member opened - which proves its seal - and bound,
/// because "read one back" means proving what an editor would pay for, not
/// admiring the directory. One line per language rather than the full folio
/// report per member; `mint <codex> --language=X` is not a verb, `mint` on the
/// member's own folio is how you get the long form.
fn contents(
    gpa: std.mem.Allocator,
    io: std.Io,
    w: *std.Io.Writer,
    c: *const folio.Codex,
    file_len: usize,
    path: []const u8,
    at: std.Io.Timestamp,
) !u8 {
    try w.print("codex of {d} languages, {d} bytes  {s}\n", .{ c.count, file_len, path });
    var worst: u8 = 0;
    for (0..c.count) |i| {
        const title = c.titleAt(@intCast(i));
        const slice = c.sliceAt(@intCast(i));
        var f = c.openAt(@intCast(i)) catch |e| {
            try w.print("  {s: <16} {d: >12} bytes  UNREADABLE: {s}\n", .{
                title, slice.len, @errorName(e),
            });
            worst = 1;
            continue;
        };
        var bound = folio.bind(gpa, &f) catch |e| {
            try w.print("  {s: <16} {d: >12} bytes  UNBINDABLE: {s}\n", .{
                title, slice.len, @errorName(e),
            });
            worst = 1;
            continue;
        };
        defer bound.deinit();
        try w.print("  {s: <16} {d: >12} bytes  {d} symbols, {d} productions, {d} states\n", .{
            title, slice.len, f.head.symbol_count, f.head.production_count, f.head.state_count,
        });
    }
    if (worst == 0) {
        try w.print("\n  every member sealed, opened and bound in {d} us\n", .{since(io, at)});
    }
    return worst;
}

/// Press several grammars - or take folios already minted, in any mixture -
/// and bind them into one codex at `-o`. Each member pressed here is checked
/// cell by cell against the read-back, same as the single-grammar mint; a
/// member that arrived as a folio was proven when it was packed and is proven
/// again by the read-back's open, so it is embedded as it stands rather than
/// re-pressed from a grammar.json this command was never handed.
fn gathering(
    gpa: std.mem.Allocator,
    io: std.Io,
    w: *std.Io.Writer,
    paths: []const []const u8,
    out: ?[]const u8,
) !u8 {
    const target = out orelse {
        try w.writeAll("joints: minting several grammars into one file needs -o <codex path>\n");
        return 2;
    };

    const Member = struct {
        path: []const u8,
        bytes: []align(leaf.section_align) const u8,
        /// Set when the member was pressed here, absent for one embedded as a
        /// ready folio - which is also the read-back check's dispatch: only a
        /// press leaves tables in memory to disagree with.
        gr: ?press.Grammar = null,
        built: ?press.Result = null,
        press_us: i64 = 0,
    };
    var members: std.ArrayList(Member) = .empty;
    defer {
        for (members.items) |*m| {
            gpa.free(m.bytes);
            if (m.built) |*b| b.deinit();
            if (m.gr) |*have| have.deinit();
        }
        members.deinit(gpa);
    }

    for (paths) |path| {
        // Same sniff as the single-path flow: the first eight bytes say what
        // this member is, and only a genuine folio failure is reported as one.
        if (folio.mapVolume(io, std.Io.Dir.cwd(), path)) |opened| {
            var mapped = opened;
            defer mapped.close();
            switch (mapped.volume) {
                .one => {
                    // Copied out of the mapping rather than kept mapped,
                    // because the codex packer wants every part in memory at
                    // once and a small aligned copy outlives the file handle.
                    const copy = try gpa.alignedAlloc(
                        u8,
                        comptime .fromByteUnits(leaf.section_align),
                        mapped.bytes.len,
                    );
                    @memcpy(copy, mapped.bytes);
                    try members.append(gpa, .{ .path = path, .bytes = copy });
                    continue;
                },
                .many => {
                    // Nesting would make `pick` a tree walk and give one
                    // language two spellings of its address. Flatten instead.
                    try w.print("joints: {s} is already a codex; mint its members' folios" ++
                        " or grammar.jsons directly\n", .{path});
                    return 2;
                },
            }
        } else |e| switch (e) {
            error.FolioBadMagic, error.FolioTooSmall, error.FileNotFound => {},
            else => {
                try w.print("joints: {s} does not load: {s}\n", .{ path, @errorName(e) });
                return 2;
            },
        }

        const source = intake.slurp(gpa, io, w, path) orelse return 2;
        defer gpa.free(source);
        var gr = press.treeSitter(gpa, source) catch |e| {
            try w.print("joints: cannot import {s}: {s}\n", .{ path, @errorName(e) });
            return 2;
        };
        const pressed_at = std.Io.Clock.awake.now(io);
        var built = press.tables(gpa, &gr) catch |e| {
            try w.print("joints: cannot press {s}: {s}\n", .{ gr.name, @errorName(e) });
            gr.deinit();
            return 2;
        };
        const bytes = folio.pack(gpa, &gr, &built) catch |e| {
            try w.print("joints: cannot pack {s}: {s}\n", .{ gr.name, @errorName(e) });
            built.deinit();
            gr.deinit();
            return 2;
        };
        try members.append(gpa, .{
            .path = path,
            .bytes = bytes,
            .gr = gr,
            .built = built,
            .press_us = since(io, pressed_at),
        });
    }

    var parts: std.ArrayList([]align(leaf.section_align) const u8) = .empty;
    defer parts.deinit(gpa);
    for (members.items) |m| try parts.append(gpa, m.bytes);

    const packed_at = std.Io.Clock.awake.now(io);
    const bytes = folio.codex.pack(gpa, parts.items) catch |e| switch (e) {
        error.TitleRepeated => {
            try w.writeAll("joints: two of those grammars share a name;" ++
                " a codex holds each language once\n");
            return 2;
        },
        else => {
            try w.print("joints: cannot bind the codex: {s}\n", .{@errorName(e)});
            return 2;
        },
    };
    defer gpa.free(bytes);
    const pack_us = since(io, packed_at);

    folio.writeTo(io, std.Io.Dir.cwd(), target, bytes) catch |e| {
        try w.print("joints: cannot write {s}: {s}\n", .{ target, @errorName(e) });
        return 2;
    };

    // Read back the file that was just published, not the buffer it came
    // from - the same rule as the single mint, for the same reason.
    const loaded_at = std.Io.Clock.awake.now(io);
    var mapped = folio.mapVolume(io, std.Io.Dir.cwd(), target) catch |e| {
        try w.print("joints: {s} does not load: {s}\n", .{ target, @errorName(e) });
        return 1;
    };
    defer mapped.close();
    const c: *const folio.Codex = switch (mapped.volume) {
        .many => |*x| x,
        .one => {
            try w.print("joints: {s} read back as a lone folio, not a codex\n", .{target});
            return 1;
        },
    };
    const load_us = since(io, loaded_at);

    try w.print("codex of {d} languages, {d} bytes  {s}\n", .{ c.count, bytes.len, target });
    var total_press: i64 = 0;
    for (members.items, 0..) |*m, i| {
        var f = c.openAt(@intCast(i)) catch |e| {
            try w.print("  MISMATCH: {s} does not open back: {s}\n", .{ m.path, @errorName(e) });
            return 1;
        };
        var bound = folio.bind(gpa, &f) catch |e| {
            try w.print("  MISMATCH: {s} does not bind back: {s}\n", .{ m.path, @errorName(e) });
            return 1;
        };
        defer bound.deinit();
        if (m.gr != null) {
            if (disagrees(&f, &bound, &m.gr.?, &m.built.?)) |what| {
                try w.print("  MISMATCH in {s}: {s}\n", .{ c.titleAt(@intCast(i)), what });
                return 1;
            }
        }
        try w.print("  {s: <16} {d: >12} bytes  {d} symbols, {d} states  {s}\n", .{
            c.titleAt(@intCast(i)),
            c.sliceAt(@intCast(i)).len,
            f.head.symbol_count,
            f.head.state_count,
            if (m.gr != null) "pressed, reloaded, identical" else "embedded as it was",
        });
        total_press += m.press_us;
    }
    try w.print("\n  pressed in {d} us, packed in {d} us, loaded in {d} us\n", .{
        total_press, pack_us, load_us,
    });
    return 0;
}

fn write(
    gpa: std.mem.Allocator,
    io: std.Io,
    w: *std.Io.Writer,
    path: []const u8,
    out: ?[]const u8,
) !u8 {
    const source = intake.slurp(gpa, io, w, path) orelse return 2;
    defer gpa.free(source);

    var gr = press.treeSitter(gpa, source) catch |e| {
        try w.print("joints: cannot import {s}: {s}\n", .{ path, @errorName(e) });
        return 2;
    };
    defer gr.deinit();

    const pressed_at = std.Io.Clock.awake.now(io);
    var built = press.tables(gpa, &gr) catch |e| {
        try w.print("joints: cannot press {s}: {s}\n", .{ gr.name, @errorName(e) });
        return 2;
    };
    defer built.deinit();
    const press_us = since(io, pressed_at);

    const packed_at = std.Io.Clock.awake.now(io);
    const bytes = folio.pack(gpa, &gr, &built) catch |e| {
        try w.print("joints: cannot pack {s}: {s}\n", .{ gr.name, @errorName(e) });
        return 2;
    };
    defer gpa.free(bytes);
    const pack_us = since(io, packed_at);

    const target = out orelse try swapExtension(gpa, path);
    defer if (out == null) gpa.free(target);
    folio.writeTo(io, std.Io.Dir.cwd(), target, bytes) catch |e| {
        try w.print("joints: cannot write {s}: {s}\n", .{ target, @errorName(e) });
        return 2;
    };

    // Read back the file that was just published, not the buffer it came from.
    // A writer checking its own bytes proves nothing about what landed on disk.
    const loaded_at = std.Io.Clock.awake.now(io);
    var mapped = folio.map(io, std.Io.Dir.cwd(), target) catch |e| {
        try w.print("joints: {s} does not load: {s}\n", .{ target, @errorName(e) });
        return 1;
    };
    defer mapped.close();
    var bound = folio.bind(gpa, &mapped.folio) catch |e| {
        try w.print("joints: cannot bind {s}: {s}\n", .{ target, @errorName(e) });
        return 2;
    };
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
fn footprint(gr: *const press.Grammar, built: anytype) Footprint {
    var m: Footprint = .{ .grammar = 0, .automaton = 0, .table = 0 };
    m.grammar += gr.name.len;
    for (gr.names) |n| m.grammar += n.len + @sizeOf([]const u8);
    for (gr.patterns) |p| {
        m.grammar += @sizeOf(?press.Pattern) + switch (p orelse continue) {
            .literal, .regex => |text| text.len,
            .external => 0,
        };
    }
    m.grammar += gr.lexis.len * @sizeOf(press.Lexis);
    m.grammar += gr.shapes.len * @sizeOf(press.Shape);
    m.grammar += gr.owner.len * @sizeOf(press.Symbol);
    m.grammar += (gr.extras.len + gr.supertypes.len) * @sizeOf(press.Symbol);
    for (gr.aliases) |a| m.grammar += a.name.len + @sizeOf(press.Alias);
    for (gr.field_names) |n| m.grammar += n.len + @sizeOf([]const u8);
    for (gr.productions) |p| {
        m.grammar += @sizeOf(press.Production) + p.rhs.len * @sizeOf(press.Symbol) + p.steps.len * @sizeOf(press.Step);
    }
    for (built.collection.states) |st| {
        m.automaton += @sizeOf(press.State) +
            st.kernel.len * @sizeOf(press.Item) +
            st.edges.len * @sizeOf(press.Edge) +
            st.complete.len * @sizeOf(u32);
    }
    m.table = built.tables.action.len * @sizeOf(joints.press.Action);
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
    gr: *const press.Grammar,
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
        if (!std.mem.eql(press.Symbol, p.rhs, f.rhsOf(@intCast(i)))) return "a production body";
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
        // Both actions, both halves of each. `other` is the reading the table
        // dropped and the only thing `Forks` reads out of this record, so a
        // conflict that round-trips its verdict and loses its rival is a cell
        // that stops forking without any count moving.
        if (!alike(want.chosen, back.chosen) or !alike(want.other, back.other)) {
            return "a conflict's verdict";
        }
        if (!std.mem.eql(press.Symbol, want.party, back.party)) return "a conflict's party";
    }
    return null;
}

fn alike(a: joints.press.Action, b: joints.press.Action) bool {
    return a.kind == b.kind and a.value == b.value;
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
