//! Rung one: do joints converge?
//!
//! The whole design is a bet that a segment of a real file, run from every
//! state it could have been entered in, does **the same thing to the stack**
//! almost every time. If it does, an element of the monoid is one pop count and
//! one interned symbol string, composition is a pointer join, and everything in
//! [`research/joinery/CLAIM.md`](../../../../research/joinery/CLAIM.md) follows.
//! If it does not, an element is `|Q|`-sized, composing two of them loses to
//! tree-sitter's O(1)-per-token walk by a wide margin, and the honest outcome is
//! a `CLOSED.md`.
//!
//! No parser of ours is needed to find out, which is why this measurement is
//! first. What is needed is a real grammar's LALR table, a true token stream
//! (which does need a walk — see `kernel/walk/`), and patience with `|Q|` runs
//! per segment.
//!
//! Four numbers, printed in this order, and the last one is the verdict:
//!
//!   * **rank** — distinct effects across entry states. Read as data, not as a
//!     grade. The rung's original kill condition was a median above one, and
//!     rank turned out to be the wrong quantity to have picked: it counts a
//!     segment's unrefuted *hypotheses* about the stack beneath it, not the
//!     size of anything a composition walks. See the rung 1 verdict in
//!     [`research/joinery/TESTING.md`](../../../../research/joinery/TESTING.md).
//!   * **domain** — how many entry states produce an effect at all. Small is
//!     good and is not the same as bad: an empty action cell is a *proof* that
//!     a state was never the one, and a sparse table is a lot of proof.
//!   * **fanned / adrift** — where a run gave up, and on which of its two
//!     capacities: too many parses at once, or one parse with too many places
//!     it could have started. Together, the fraction of the file where GLR is
//!     genuinely owed, to hold against ast-grep's measured 98.898% of stack
//!     nodes having exactly one predecessor.
//!   * **residue** — how wide the running product of unrefuted pairings ever
//!     got, and whether it multiplied back to the whole file. This is the real
//!     falsifier: bounded independently of how finely the file was cut is a
//!     fan, growing with the file is a graph-structured stack with extra steps,
//!     and not multiplying back at all is a bug in the algebra.

const std = @import("std");
const joints = @import("joints");
const assay = joints.assay;
const intake = @import("intake.zig");

const press = joints.press;
const drive = joints.kernel.walk;
const joint = joints.kernel.joint;

/// Segment lengths, in tokens and in bytes. `TESTING.md` asks for both: a byte
/// span is what an editor's viewport and a parallel split look like, a token
/// span is what a balanced tree over the stream would actually hold.
/// Leaf sizes, and the slate straddles the answer on purpose: what a joint costs
/// turns out to depend on how long a segment is, because interior history is what
/// accumulates. A balanced tree over the stream gets to choose this number, so
/// the measurement has to say which choices work.
const token_spans = [_]u32{ 4, 8, 16, 32, 128 };
const byte_spans = [_]u32{ 1 << 10, 1 << 12, 1 << 14 };

/// How wide the chain's surviving set may get before the run gives up. A
/// runaway detector rather than a quality bar, and the distinction is the whole
/// point: what decides the design is whether the residue *grows with the file*,
/// and a ceiling low enough to be a quality bar stops the run before it can
/// say. Measured on json over 27k tokens it tops out in the low thirties and is
/// no wider at 6929 segments than at 217, which is a bounded fan; the number
/// printed on each line is the one to read.
const residue_ceiling = 64;

/// How many entry states the survey runs each segment from.
///
/// The survey asks a statistical question — across the states this segment
/// could have been entered in, how many produce an effect, and how many
/// distinct effects are there — and the honest way to answer it is every state.
/// That is `|Q|` runs per segment, and `|Q|` is 44 for json and 8851 for
/// TypeScript, so the instrument's cost is quadratic in exactly the direction
/// the interesting grammars grow. Python spent five minutes on a four-token
/// file before this existed.
///
/// A sample answers the same question. The states are taken evenly across the
/// collection's own order, which is breadth-first from the start state, so the
/// spread covers the automaton's depth rather than clustering in whatever
/// region happens to be numbered low — and it is deterministic, so two runs of
/// the same command are the same measurement.
///
/// What is *not* sampled is the oracle. That one asks whether the algebra is
/// correct, its answer is a proof rather than a proportion, and it runs from
/// the state the walk really was in. `--entries 0` surveys everything, which is
/// what to do when a sampled number looks wrong.
const entry_sample = 256;

pub fn run(
    gpa: std.mem.Allocator,
    io: std.Io,
    w: *std.Io.Writer,
    args: []const []const u8,
) !u8 {
    const grammar_path = args[0];
    const argv = args[1..];
    var dump = false;
    var confess = false;
    var sample: u32 = entry_sample;
    var limbs: u32 = joint.limb_ceiling;
    var fan: u32 = joint.fan_ceiling;
    var churn: u32 = 0;
    var fusion: joint.Cursor.Fusion = .depth;
    var paths: std.ArrayList([]const u8) = .empty;
    defer paths.deinit(gpa);
    var rest = argv;
    while (rest.len > 0) : (rest = rest[1..]) {
        const a = rest[0];
        if (std.mem.eql(u8, a, "--dump")) {
            dump = true;
        } else if (std.mem.eql(u8, a, "--exact")) {
            // The one trade left in M2, exposed because measuring both poles is
            // the only way to say what it costs. See `Cursor.Fusion`.
            fusion = .exact;
        } else if (std.mem.eql(u8, a, "--confess")) {
            confess = true;
        } else if (std.mem.eql(u8, a, "--entries")) {
            sample = counted(w, &rest) catch return 2;
        } else if (std.mem.eql(u8, a, "--limbs")) {
            limbs = counted(w, &rest) catch return 2;
        } else if (std.mem.eql(u8, a, "--fan")) {
            fan = counted(w, &rest) catch return 2;
        } else if (std.mem.eql(u8, a, "--churn")) {
            churn = counted(w, &rest) catch return 2;
        } else try paths.append(gpa, a);
    }
    const files = paths.items;
    if (files.len == 0) {
        try w.writeAll("joints: survey needs at least one source file\n");
        return 2;
    }

    const source = intake.slurp(gpa, io, w, grammar_path) orelse return 2;
    defer gpa.free(source);

    var gr = intake.grammar(gpa, w, grammar_path, source) orelse return 2;
    defer gr.deinit();

    var built = intake.tables(gpa, w, &gr) orelse return 2;
    defer built.deinit();
    const c = &built.collection;
    const t = &built.tables;
    var rev = try joint.Reverse.build(gpa, &gr, c, t);
    defer rev.deinit();
    rev.fan = fan;
    var pool = joint.stack.Pool.init(gpa);
    defer pool.deinit();
    var floors = joint.roster.Pool.init(gpa);
    defer floors.deinit();
    var guards = joint.ledger.Pool.init(gpa);
    defer guards.deinit();
    var cur = joint.Cursor.init(gpa, &gr, c, t, &rev, &pool, &floors, &guards);
    defer cur.deinit();
    cur.fusion = fusion;
    cur.confessing = confess;
    cur.limbs_max = limbs;
    if (churn != 0) cur.born_max = churn;

    var sc = intake.scanner(gpa, w, &gr) catch |r| return intake.tokenless(r);
    defer sc.deinit();
    var walk = try drive.Drive.init(gpa, &gr, c, t, &sc);
    defer walk.deinit();

    const entries = try spread(gpa, @intCast(c.states.len), sample);
    defer gpa.free(entries);

    // Contested and residual are different numbers and only the second is a
    // defect: a cell the author declared ambiguous is a fork a GLR parser is
    // *for*, and reporting the total as "unresolved" reads as a broken press on
    // a grammar whose press is fine. Go is the case in point — 23 contested
    // cells, every one declared, none residual.
    const cells = t.tally();
    try w.print("{s}  {d} states, {d} terminals, {d} contested ({d} declared, {d} residual)\n", .{
        gr.name,         c.states.len,   gr.terminal_count,
        t.conflicts.len, cells.declared, cells.residual.total(),
    });
    if (entries.len < c.states.len) {
        try w.print("  surveyed from {d} of {d} entry states — percentages are a sample\n", .{
            entries.len, c.states.len,
        });
    }
    if (sc.blind.len > 0) {
        try w.print("  blind to {d} terminal(s) — every stream below is incomplete\n", .{sc.blind.len});
    }

    var tally: Tally = .{};
    for (files) |path| {
        const text = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64 << 20)) catch |e| {
            try w.print("\n  {s}: cannot read ({s})\n", .{ path, @errorName(e) });
            continue;
        };
        defer gpa.free(text);

        var trace = try walk.run(text);
        defer trace.deinit(gpa);

        try w.print("\n  {s}  {d} bytes -> {d} tokens, {s}\n", .{
            path, text.len, trace.tokens.len, ending(trace.ending),
        });
        switch (trace.ending) {
            .accepted => {},
            // A partial stream still measures something, but say so: a segment
            // survey over tokens the grammar never accepted is a survey of a
            // language nobody wrote. The tail is printed because a lexer this
            // state-directed fails at the token *after* the one that was wrong.
            .stray => |off| {
                try w.print("    stray byte at {d}, after:", .{off});
                try tail(w, &gr, trace.tokens);
            },
            .unexpected => |u| {
                try w.print("    {s} at {d} has no action in state {d}, after:", .{
                    gr.nameOf(u.tok.symbol), u.tok.start, u.state,
                });
                try tail(w, &gr, trace.tokens);
                for (u.folded) |f| {
                    try w.print("      state {d: <5} folded  ", .{f.state});
                    try shape(w, &gr, f.prod);
                    try w.writeAll("\n");
                }
                try legal(w, &gr, t, u.state);
            },
            .truncated => {},
        }
        if (trace.tokens.len == 0) continue;

        const symbols = try gpa.alloc(press.Symbol, trace.tokens.len);
        defer gpa.free(symbols);
        for (symbols, trace.tokens) |*s, tok| s.* = tok.symbol;

        // The states this file was really in are always surveyed, sample or
        // not. Without that, "no entry state could produce this segment" can be
        // a statement about the sample rather than about the grammar — and that
        // line is one of the few here that reads as a defect.
        const surveyed = try witnessed(gpa, entries, trace.enter);
        defer gpa.free(surveyed);

        var edges: std.ArrayList(u32) = .empty;
        defer edges.deinit(gpa);

        var probe: Probe = .{
            .gpa = gpa,
            .io = io,
            .w = w,
            .gr = &gr,
            .x = cur.arena(),
            .cur = &cur,
            .pool = &pool,
            .entries = surveyed,
            .symbols = symbols,
            .enter = trace.enter,
            .dump = dump,
        };
        defer probe.deinit();
        for (token_spans) |span| {
            try byTokens(gpa, &edges, @intCast(symbols.len), span);
            try tally.take(&probe, w, "tok", span, edges.items);
        }
        for (byte_spans) |span| {
            try byBytes(gpa, &edges, trace.tokens, span);
            try tally.take(&probe, w, "byte", span, edges.items);
        }
    }
    return tally.verdict(w);
}

/// What every segmentation of every file came to, and the exit code.
const Tally = struct {
    rank: u32 = 0,
    residue: u32 = 0,
    /// Segmentations measured, and how each one ended. Kept apart because they
    /// are three different verdicts wearing one word: a product that came back
    /// out, a product that came back *wrong*, and a segment the cursor would not
    /// run at all. Only the middle one indicts the algebra, and a run that
    /// measured nothing indicts the invocation.
    agreed: u32 = 0,
    disagreed: u32 = 0,
    refused: u32 = 0,

    /// Measure one segmentation, print its line, and fold it in.
    fn take(
        t: *Tally,
        p: *Probe,
        w: *std.Io.Writer,
        unit: []const u8,
        span: u32,
        edges: []const u32,
    ) !void {
        const r = try p.measure(edges);
        defer r.deinit(p.gpa);
        try r.print(w, unit, span);
        if (r.broke()) |b| try p.blame(w, b);
        t.rank = @max(t.rank, r.rank99());
        switch (r.chain) {
            .agreed => |wide| {
                t.agreed += 1;
                t.residue = @max(t.residue, wide);
            },
            .disagreed => t.disagreed += 1,
            .broken => t.refused += 1,
        }
    }

    /// The kill condition, applied rather than described - and not the one this
    /// rung was written with. Rank is reported because it is the number the
    /// claim was originally staked on, but it decides nothing: a segment holds
    /// several effects because it cannot see its own stack, which is a fact
    /// about segments rather than a cost. What decides is whether the product
    /// came back out and how wide it had to get to do it.
    fn verdict(t: Tally, w: *std.Io.Writer) !u8 {
        const total = t.agreed + t.disagreed + t.refused;
        try w.print("\nworst p99 rank {d} · widest residue {d} · ", .{ t.rank, t.residue });
        if (total == 0) {
            try w.writeAll("nothing measured\n");
            return 1;
        }
        try w.print("{d}/{d} chains held", .{ t.agreed, total });
        // A product that came back wrong is the kill condition. A segment the
        // cursor refused is the instrument saying it cannot answer, which is a
        // finding about how much left context that cut owes — not the same
        // thing, and printing both as BROKE hid which one had happened.
        if (t.disagreed > 0) try w.print(" · {d} DISAGREED", .{t.disagreed});
        if (t.refused > 0) try w.print(" · {d} refused at a ceiling", .{t.refused});
        try w.writeAll("\n");
        return @intFromBool(t.agreed != total);
    }
};

/// `sample`, plus every state the walk actually entered, sorted and unique.
fn witnessed(gpa: std.mem.Allocator, sample: []const u32, enter: []const u32) ![]u32 {
    var out = try std.ArrayList(u32).initCapacity(gpa, sample.len + enter.len);
    errdefer out.deinit(gpa);
    out.appendSliceAssumeCapacity(sample);
    out.appendSliceAssumeCapacity(enter);
    std.mem.sort(u32, out.items, {}, std.sort.asc(u32));
    var kept: usize = 0;
    for (out.items, 0..) |e, i| {
        if (i > 0 and e == out.items[kept - 1]) continue;
        out.items[kept] = e;
        kept += 1;
    }
    out.shrinkRetainingCapacity(kept);
    return out.toOwnedSlice(gpa);
}

/// The count after a flag, advancing the argument cursor past it.
fn counted(w: *std.Io.Writer, rest: *[]const []const u8) !u32 {
    const flag = rest.*[0];
    if (rest.len < 2) {
        try w.print("joints: {s} wants a count\n", .{flag});
        return error.Usage;
    }
    rest.* = rest.*[1..];
    return std.fmt.parseInt(u32, rest.*[0], 10) catch {
        try w.print("joints: {s} {s} is not a count\n", .{ flag, rest.*[0] });
        return error.Usage;
    };
}

/// `want` state ids spread evenly over `total`, or every one of them when the
/// collection is small enough to survey whole (`want` of zero says so outright).
///
/// Evenly rather than randomly, because the ids are breadth-first from the
/// start state: a stride walks outward through the automaton, where a random
/// draw would over-sample whatever the grammar happens to have a lot of. The
/// first and last are always in, so the sample spans the collection.
fn spread(gpa: std.mem.Allocator, total: u32, want: u32) ![]u32 {
    if (want == 0 or want >= total) {
        const all = try gpa.alloc(u32, total);
        for (all, 0..) |*e, i| e.* = @intCast(i);
        return all;
    }
    const out = try gpa.alloc(u32, want);
    for (out, 0..) |*e, i| e.* = @intCast(i * total / want);
    return out;
}

/// One production, in the grammar's own vocabulary.
fn shape(w: *std.Io.Writer, gr: *const press.Grammar, prod: u32) !void {
    const p = gr.productions[prod];
    try w.print("{s} ->", .{gr.nameOf(p.lhs)});
    if (p.rhs.len == 0) try w.writeAll(" \u{3b5}");
    for (p.rhs) |s| try w.print(" {s}", .{gr.nameOf(s)});
}

/// What the stuck state does accept. A missing action is nearly always a
/// missing *fold* — the token is legal one reduction away — so the terminals
/// the state does have are the shape of the hole.
///
/// **In two halves, because the sentence above is about one of them.** This
/// printed a single flat list of every terminal with a non-error action, cut
/// off at twelve by symbol number. In a state with three shifts and two hundred
/// lookaheads that is a dozen mixed names, and a reader counting them reads a
/// state that consumes three tokens as one that consumes twelve. The same
/// conflation cost a lane a night in `state --census` and named the wrong
/// scanner in `inquest`; the split is `press.Half` in all three, so none of them
/// can drift from the others.
fn legal(w: *std.Io.Writer, gr: *const press.Grammar, t: *const press.Tables, state: u32) !void {
    const shift = try side(w, gr, t, state, .shift);
    const fold = try side(w, gr, t, state, .fold);
    if (shift + fold == 0) try w.writeAll("      it accepts: nothing\n");
}

/// One half of the row, named and counted. Silent when empty unless the whole
/// row is, because an absent half is itself the answer a stuck state usually
/// has: no shift at all means no token could have been read here whatever the
/// scanner did.
fn side(
    w: *std.Io.Writer,
    gr: *const press.Grammar,
    t: *const press.Tables,
    state: u32,
    half: press.Half,
) !u32 {
    var shown: u32 = 0;
    for (0..gr.terminal_count) |sym| {
        if (press.Half.of(t.at(state, @intCast(sym)).kind) != half) continue;
        shown += 1;
        if (shown > 12) continue;
        if (shown == 1) try w.print("      it {s}:", .{
            if (half == .shift) "reads" else "folds on",
        });
        try w.print(" {s}", .{gr.nameOf(@intCast(sym))});
    }
    if (shown > 12) try w.print(" (+{d} more)", .{shown - 12});
    if (shown > 0) try w.print("  [{d} {s}]\n", .{ shown, half.word() });
    return shown;
}

/// The last few tokens that did parse. Where a walk stopped is rarely where it
/// went wrong, and this is the cheapest thing that shows the difference.
fn tail(w: *std.Io.Writer, gr: *const press.Grammar, tokens: []const drive.Token) !void {
    const from = tokens.len -| 6;
    for (tokens[from..]) |tok| try w.print(" {s}@{d}", .{ gr.nameOf(tok.symbol), tok.start });
    try w.writeAll("\n");
}

fn ending(e: drive.Ending) []const u8 {
    return switch (e) {
        .accepted => "accepted",
        .stray => "stopped at a stray byte",
        .unexpected => "stopped at an unusable token",
        .truncated => "truncated",
    };
}

/// Segment boundaries as token indices: `edges[i] .. edges[i + 1]`.
fn byTokens(gpa: std.mem.Allocator, edges: *std.ArrayList(u32), count: u32, span: u32) !void {
    edges.clearRetainingCapacity();
    var at: u32 = 0;
    while (at < count) : (at += span) try edges.append(gpa, at);
    try edges.append(gpa, count);
}

/// The same, cut at byte offsets and rounded to the token that contains them —
/// a segment has to be a whole number of tokens whatever the reason for the cut.
fn byBytes(
    gpa: std.mem.Allocator,
    edges: *std.ArrayList(u32),
    tokens: []const drive.Token,
    span: u32,
) !void {
    edges.clearRetainingCapacity();
    try edges.append(gpa, 0);
    var mark: u32 = span;
    for (tokens, 0..) |tok, i| {
        if (tok.start < mark) continue;
        if (i != edges.getLast()) try edges.append(gpa, @intCast(i));
        while (mark <= tok.start) mark += span;
    }
    if (edges.getLast() != tokens.len) try edges.append(gpa, @intCast(tokens.len));
}

/// Everything one file's worth of segmentations needs, so a segmentation is a
/// single call and the oracle rides along with the histogram instead of being
/// a second pass over the same work.
const Probe = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    w: *std.Io.Writer,
    gr: *const press.Grammar,
    /// Composition consults the goto graph and both intern pools: a right
    /// neighbour's floor is a claim about where the left one landed, and only
    /// the automaton settles it.
    x: joint.Arena,
    cur: *joint.Cursor,
    pool: *joint.stack.Pool,
    entries: []const u32,
    symbols: []const press.Symbol,
    /// The state the walk really was in at each token.
    enter: []const u32,
    dump: bool,
    /// The chain's running product: every pairing not yet refuted. Two buffers
    /// because a step reads one and writes the other.
    live: std.ArrayList(joint.Effect) = .empty,
    next: std.ArrayList(joint.Effect) = .empty,

    fn deinit(p: *Probe) void {
        p.live.deinit(p.gpa);
        p.next.deinit(p.gpa);
    }

    fn measure(p: *Probe, edges: []const u32) !Report {
        var r: Report = .{};
        var shown = !p.dump;
        const surveying = assay.Span.open(p.io);
        for (edges[0 .. edges.len - 1], edges[1..]) |lo, hi| {
            const s = try p.cur.survey(p.entries, p.symbols[lo..hi]);
            r.pairs += p.entries.len;
            r.defined += s.domain;
            r.refuted += s.rejected;
            r.plural += s.plural;
            r.forked += s.fanned;
            r.adrift += s.unmoored;
            r.churned += s.churned;
            r.widest = @max(r.widest, s.widest);
            try r.ranks.append(p.gpa, s.rank);
            try r.domains.append(p.gpa, s.domain);
            if (!shown and s.rank > 1) {
                shown = true;
                try p.expose(lo, hi);
            }
        }
        // Read before the oracle runs: this is the cursor's cost, and the
        // reference walk that checks it is not part of what is being measured.
        r.us = @intCast(surveying.read(p.io).us());
        r.chain = try p.oracle(edges);
        std.mem.sort(u32, r.ranks.items, {}, std.sort.asc(u32));
        std.mem.sort(u32, r.domains.items, {}, std.sort.asc(u32));
        return r;
    }

    /// The instrument's own correctness check, and the only one that matters:
    /// entered where the walk really was, the product of the segment effects
    /// must be the effect of the whole file. A disagreement is a bug in the
    /// algebra, not a finding about the grammar, and it invalidates every number
    /// on the line it prints beside.
    ///
    /// The product is over a *set*, and asking for less was this instrument's own
    /// mistake for a while. Demanding that exactly one branch survive each step
    /// is stronger than a monoid owes: composition is partial, so a running
    /// product is the set of pairings not yet refuted, and a scan is entitled to
    /// carry it as long as it stays small. It is also a demand no guard over
    /// *states* can meet, because a periodic stack makes it unmeetable — JSON's
    /// object nesting is a six-state cycle, so a branch that pops 27 and one that
    /// pops 33 walk through identical states and are separated by nothing this
    /// algebra can see. Refuting one needs a later segment, and the later segment
    /// does refute it. So what is measured is the **residue**: how wide the
    /// surviving set ever gets, and whether the whole-file effect is in it at the
    /// end. A residue that stays at two and collapses is GLR with a fan of two;
    /// a residue that grows with the file is the design failing.
    fn oracle(p: *Probe, edges: []const u32) !Chain {
        p.live.clearRetainingCapacity();
        p.next.clearRetainingCapacity();
        try p.live.append(p.gpa, .identity);
        var widest: u32 = 1;
        for (edges[0 .. edges.len - 1], edges[1..]) |lo, hi| {
            const ways = switch (try p.cur.run(p.enter[lo], p.symbols[lo..hi])) {
                .ran => |ys| ys,
                .fanned => |f| return .{ .broken = .{
                    .lo = lo,
                    .hi = hi,
                    .at = lo + f.at,
                    .why = switch (f.why) {
                        .limbs => .ceiling,
                        .floor => .unmoored,
                        .churn => .churn,
                    },
                    .ways = f.limbs,
                } },
                .rejected => |k| return .{
                    .broken = .{ .lo = lo, .hi = hi, .at = lo + k, .why = .refuted },
                },
            };
            // `grounded` is the other half of the sieve, and the file's left edge
            // is the only place it can be applied: an accumulation that starts at
            // the first byte has nothing under it, so a branch claiming to have
            // popped below the bottom describes a prefix that does not exist.
            // Composition itself never asks — see `Effect.grounded`.
            p.next.clearRetainingCapacity();
            for (p.live.items) |acc| for (ways) |y| {
                const joined = try joint.compose(p.x, acc, y.effect) orelse continue;
                if (!joined.grounded(p.x)) continue;
                for (p.next.items) |seen| {
                    if (seen.eql(joined)) break;
                } else try p.next.append(p.gpa, joined);
            };
            if (p.next.items.len == 0) return .{
                .broken = .{ .lo = lo, .hi = hi, .at = lo, .why = .unguarded, .ways = 0 },
            };
            if (p.next.items.len > residue_ceiling) return .{
                .broken = .{
                    .lo = lo,
                    .hi = hi,
                    .at = lo,
                    .why = .unguarded,
                    .ways = @intCast(p.next.items.len),
                },
            };
            widest = @max(widest, @as(u32, @intCast(p.next.items.len)));
            std.mem.swap(std.ArrayList(joint.Effect), &p.live, &p.next);
        }
        const last: u32 = @intCast(p.symbols.len);
        const whole = switch (try p.cur.run(p.enter[0], p.symbols)) {
            .ran => |ys| ys,
            .fanned => |f| return .{ .broken = .{
                .lo = 0,
                .hi = last,
                .at = f.at,
                .why = switch (f.why) {
                    .limbs => .ceiling,
                    .floor => .unmoored,
                    .churn => .churn,
                },
                .ways = f.limbs,
            } },
            .rejected => |k| return .{
                .broken = .{ .lo = 0, .hi = last, .at = k, .why = .refuted },
            },
        };
        // The unsegmented run of the same tokens is itself a set, for the same
        // reason: run over a whole file it is a singleton, but a "file" here can
        // be any span. Agreement is that the two sets describe the same parse —
        // every grounded whole-file answer is one the segmented product also
        // reached.
        for (whole) |y| {
            if (!y.effect.grounded(p.x)) continue;
            for (p.live.items) |acc| {
                if (acc.eql(y.effect)) break;
            } else return .disagreed;
        }
        return .{ .agreed = widest };
    }

    /// Why the oracle could not run, in the terms of the token stream it was
    /// handed. A `broken` line with no location is a line nobody can act on.
    fn blame(p: *Probe, w: *std.Io.Writer, b: Chain.Break) !void {
        try w.print("         oracle broke: [{d}, {d}) from state {d} — {s} on {s}@{d}, " ++
            "{d} way(s)\n", .{
            b.lo,
            b.hi,
            p.enter[b.lo],
            @tagName(b.why),
            p.gr.nameOf(p.symbols[b.at]),
            b.at,
            b.ways,
        });
        if (b.why == .unguarded) try p.witness(w, b);
    }

    /// The branches a guard failed to tell apart, spelled out with the claims
    /// each one made. "2 way(s)" says the sieve leaked; this says through which
    /// hole, which is the difference between a number and a lead.
    fn witness(p: *Probe, w: *std.Io.Writer, b: Chain.Break) !void {
        var acc: joint.Effect = .identity;
        var at: u32 = 0;
        while (at < b.lo) {
            // Re-walk the prefix the same way the oracle did. It cannot break
            // before `lo`, or `lo` would not be where it broke.
            const upto = @min(b.lo, at + (b.hi - b.lo));
            const ways = switch (try p.cur.run(p.enter[at], p.symbols[at..upto])) {
                .ran => |ys| ys,
                else => return,
            };
            var next: ?joint.Effect = null;
            for (ways) |y| if (try joint.compose(p.x, acc, y.effect)) |j| {
                if (j.grounded(p.x)) next = j;
            };
            acc = next orelse return;
            at = upto;
        }
        try p.w.writeAll("           left: ");
        try p.tell(acc);
        const ways = switch (try p.cur.run(p.enter[b.lo], p.symbols[b.lo..b.hi])) {
            .ran => |ys| ys,
            else => return,
        };
        for (ways) |y| {
            const joined = try joint.compose(p.x, acc, y.effect) orelse continue;
            if (!joined.grounded(p.x)) continue;
            try w.writeAll("           kept: ");
            try p.tell(y.effect);
            try w.writeAll("              -> ");
            try p.tell(joined);
        }
    }

    /// One effect: where it began, how deep it reached, and what it claimed at
    /// every depth on the way down.
    fn tell(p: *Probe, e: joint.Effect) !void {
        try p.w.print("from {d} -{d} +{d}  claims", .{
            e.entry,
            e.reaches(p.x),
            p.pool.depth(e.push),
        });
        var d: u32 = 1;
        const deep = p.x.guards.depth(e.guard);
        while (d <= deep) : (d += 1) {
            const claim = joint.ledger.at(p.x.guards, e.guard, d);
            try p.w.writeAll(" ");
            try p.name(claim.symbols, true);
            try p.w.writeAll("@");
            try p.name(claim.states, false);
        }
        try p.w.writeAll("\n");
    }

    /// One half of a claim: symbol names or state numbers, `*` for a belief
    /// nobody ever narrowed.
    fn name(p: *Probe, set: joint.roster.Id, symbols: bool) !void {
        if (set == joint.ledger.anywhere) return p.w.writeAll("*");
        const members = p.x.floors.members(set);
        if (members.len != 1) try p.w.writeAll("{");
        for (members, 0..) |m, i| {
            if (i != 0) try p.w.writeAll(",");
            if (symbols) try p.w.print("{s}", .{p.gr.nameOf(m)}) else try p.w.print("{d}", .{m});
        }
        if (members.len != 1) try p.w.writeAll("}");
    }

    /// One segment's joint, spelled out. Reading a rank number is guessing;
    /// reading the table is not.
    fn expose(p: *Probe, lo: u32, hi: u32) !void {
        try p.w.print("      joint of tokens [{d}, {d}) —", .{ lo, hi });
        for (p.symbols[lo..@min(hi, lo + 8)]) |s| try p.w.print(" {s}", .{p.gr.nameOf(s)});
        if (hi - lo > 8) try p.w.print(" +{d}", .{hi - lo - 8});
        try p.w.writeAll("\n");
        for (p.entries) |q| switch (try p.cur.run(q, p.symbols[lo..hi])) {
            .ran => |ys| for (ys) |y| {
                try p.w.print("        {d: >4}  -{d} +[", .{ q, y.effect.reaches(p.x) });
                var buf: [64]press.Symbol = undefined;
                const depth = p.pool.depth(y.effect.push);
                if (depth <= buf.len) {
                    for (p.pool.read(y.effect.push, &buf), 0..) |s, i| {
                        if (i != 0) try p.w.writeAll(" ");
                        try p.w.print("{s}", .{p.gr.nameOf(s)});
                    }
                } else try p.w.print("{d} symbols", .{depth});
                try p.w.print("]  landing {d}\n", .{y.landings});
            },
            .fanned => try p.w.print("        {d: >4}  fanned\n", .{q}),
            .rejected => {},
        };
    }
};

/// Whether the segments multiplied back to the whole.
const Chain = union(enum) {
    /// Agreed, carrying the widest the surviving set ever got — 1 when
    /// composition alone singled out a branch at every step.
    agreed: u32,
    disagreed,
    /// A segment entered where the walk really was did not produce an effect at
    /// all, so there was nothing to multiply. Always a bug here rather than a
    /// finding: the true entry state is by construction one a parse reached.
    broken: Break,

    const Break = struct {
        lo: u32,
        hi: u32,
        /// The token it ended on.
        at: u32,
        /// `unguarded` is the interesting one: the guards refuted every pairing
        /// (a bug — the true one was among them) or left more than
        /// `residue_ceiling` standing, so the algebra is not narrowing the way
        /// the design says it does. `ceiling`, `unmoored` and `churn` are the
        /// cursor's three capacity limits, kept apart because they indict
        /// different things — see `joint.Fork.why`.
        why: enum { unguarded, ceiling, unmoored, churn, refuted },
        ways: u32 = 1,
    };
};

const Report = struct {
    pairs: u64 = 0,
    defined: u64 = 0,
    refuted: u64 = 0,
    /// Entry states whose answer was more than one effect.
    plural: u64 = 0,
    /// Entry states that outran the limb ceiling.
    forked: u64 = 0,
    /// Entry states that outran the rewind's fan instead — see `Survey`.
    adrift: u64 = 0,
    /// Entry states that outran neither and were merely busy — see `Survey`.
    churned: u64 = 0,
    widest: u32 = 0,
    us: i64 = 0,
    chain: Chain = .disagreed,
    /// Sorted after `measure` returns.
    ranks: std.ArrayList(u32) = .empty,
    domains: std.ArrayList(u32) = .empty,

    fn deinit(r: *const Report, gpa: std.mem.Allocator) void {
        var m = r.*;
        m.ranks.deinit(gpa);
        m.domains.deinit(gpa);
    }

    fn rank99(r: *const Report) u32 {
        return quantile(r.ranks.items, 0.99);
    }

    fn print(r: *const Report, w: *std.Io.Writer, unit: []const u8, span: u32) !void {
        var dead: u32 = 0;
        for (r.ranks.items) |n| {
            if (n != 0) break;
            dead += 1;
        }
        var chain: [24]u8 = undefined;
        const verdict = switch (r.chain) {
            .agreed => |wide| try std.fmt.bufPrint(&chain, "agreed residue<={d}", .{wide}),
            else => @tagName(r.chain),
        };
        try w.print("    {s: >4} {d: <6} {d: >5} segments · rank med {d} p99 {d} · " ++
            "domain med {d} p99 {d} · defined {d: >5.2}% plural {d: >5.2}% " ++
            "fanned {d: >5.2}% adrift {d: >5.2}% churn {d: >5.2}% · landing<={d} · {s} · {d} ms\n", .{
            unit,
            span,
            r.ranks.items.len,
            quantile(r.ranks.items, 0.5),
            r.rank99(),
            quantile(r.domains.items, 0.5),
            quantile(r.domains.items, 0.99),
            share(r.defined, r.pairs),
            share(r.plural, r.pairs),
            share(r.forked, r.pairs),
            share(r.adrift, r.pairs),
            share(r.churned, r.pairs),
            r.widest,
            verdict,
            @divTrunc(r.us, 1000),
        });
        if (dead > 0) {
            try w.print("         {d} segment(s) no entry state could produce\n", .{dead});
        }
    }

    fn broke(r: *const Report) ?Chain.Break {
        return switch (r.chain) {
            .broken => |b| b,
            else => null,
        };
    }
};

fn share(n: u64, of: u64) f64 {
    if (of == 0) return 0;
    return 100.0 * @as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(of));
}

fn quantile(sorted: []const u32, q: f64) u32 {
    if (sorted.len == 0) return 0;
    const i: usize = @intFromFloat(q * @as(f64, @floatFromInt(sorted.len)));
    return sorted[@min(sorted.len - 1, i)];
}

const testing = std.testing;

test "an entry sample spans the collection and never repeats a state" {
    const gpa = testing.allocator;

    // Small enough to survey whole: the sample is the collection.
    for ([_]u32{ 0, 44, 256, 1000 }) |want| {
        const all = try spread(gpa, 44, want);
        defer gpa.free(all);
        if (want != 0 and want < 44) continue;
        try testing.expectEqual(@as(usize, 44), all.len);
        for (all, 0..) |e, i| try testing.expectEqual(@as(u32, @intCast(i)), e);
    }

    // Large enough to sample: `want` states, strictly ascending, starting at
    // the start state and reaching the far end of the automaton.
    const some = try spread(gpa, 8851, 256);
    defer gpa.free(some);
    try testing.expectEqual(@as(usize, 256), some.len);
    try testing.expectEqual(@as(u32, 0), some[0]);
    for (some[1..], some[0 .. some.len - 1]) |now, prev| try testing.expect(now > prev);
    // No further from the last state than one stride, so the sample spans the
    // collection rather than stopping short of the states numbered highest.
    try testing.expect(8851 - 1 - some[some.len - 1] <= 8851 / 256);
}
