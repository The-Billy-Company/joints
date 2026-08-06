//! The test that matters: a random edit stream over a real grammar and a real
//! file, checked after every edit against a parse from scratch.
//!
//! An incremental parser that is right at the end and wrong in the middle is
//! wrong, and every way of being wrong here is silent. A lifted subtree whose
//! offsets were shifted by the wrong delta is a perfectly well-formed tree of
//! the wrong file. A kept spine suffix whose entry state moved is a perfectly
//! well-formed product of a parse nobody made. Nothing crashes. So the check is
//! after every single edit, and it is four things:
//!
//!   1. the incremental tree's s-expression equals the cold parse's;
//!   2. every node's span equals the cold parse's, which the s-expression
//!      cannot see and which is exactly what a bad delta breaks;
//!   3. the maintained product equals the left-to-right fold of the leaves;
//!   4. and the leaves themselves equal the ones a cold parse derives, which is
//!      what says a kept suffix was keepable.
//!
//! Plus one thing a correctness check cannot say: that reuse *fired*. A
//! transplanting parser with transplanting switched off passes 1 to 4 by
//! construction, so the run asserts a floor on lifts as well - a fuzz that
//! cannot fail is not evidence, and neither is a fuzz of nothing.
//!
//! The negative control is at the bottom: three deliberate breaks, each one a
//! real bug somebody could write, and each one caught and shrunk to a handful
//! of edits.

const std = @import("std");
const t = std.testing;
const weave = @import("weave.zig");
const quire = @import("../quire/quire.zig");
const scanner = @import("../lex/scanner.zig");
const press = @import("../../press/press.zig");
const import = @import("../../press/import.zig");
const g = @import("../../press/grammar.zig");
const effect = @import("../joint/effect.zig");

/// One edit, recorded as magnitudes rather than as byte offsets, which is the
/// whole reason a script can be shrunk: an offset recorded against a file that
/// no longer exists is meaningless once an earlier edit is removed, where a
/// magnitude folds onto whatever file it lands on.
const Step = struct { kind: Kind, from: u32, span: u32, seed: u64 };

/// What an edit is shaped like. A stream of pure noise is a bad fuzz of an
/// incremental parser and not because it is too harsh: the second wild splice
/// lands on a file that stopped parsing after the first, so a run of a thousand
/// of them measures the recovery path a thousand times and reuse never once.
/// Real editing is mostly benign and occasionally not, so this is too.
const Kind = enum {
    /// Whitespace. The bytes move and not one token does, which is both the
    /// commonest keystroke there is and the case that should reuse everything.
    space,
    /// Bytes typed into a run of them: a name being extended, a number being
    /// mistyped. One token's text moves and usually its kind does not.
    inside,
    /// Anything, anywhere. Mostly refuted, which is the point - and undone on
    /// the next beat, because a broken file is a state to pass through rather
    /// than one to spend the rest of the script in.
    wild,
};

/// A grammar, pressed once and shared by every run over it. Pressing rust takes
/// long enough that doing it per script would make the shrinker unusable.
///
/// It owns the loom, so the run and its oracle weave on the same one. That is
/// not thrift: an effect is a triple of pool indices, so two looms would make
/// the two halves of every comparison incomparable and the fuzz would be
/// checking that two hash tables happened to fill in the same order.
const Bolt = struct {
    gpa: std.mem.Allocator,
    gr: g.Grammar,
    built: press.Result,
    sc: scanner.Scanner,
    loom: weave.Loom = undefined,

    fn of(gpa: std.mem.Allocator, source: []const u8) !*Bolt {
        const b = try gpa.create(Bolt);
        errdefer gpa.destroy(b);
        b.* = .{ .gpa = gpa, .gr = undefined, .built = undefined, .sc = undefined };
        b.gr = try import.treeSitter(gpa, source);
        errdefer b.gr.deinit();
        b.built = try press.tables(gpa, &b.gr);
        errdefer b.built.deinit();
        b.sc = (try scanner.Scanner.compile(gpa, &b.gr)) orelse return error.NoTerminals;
        b.loom = .init(gpa, &b.gr, &b.built.collection, &b.built.tables, &b.sc);
        return b;
    }

    fn deinit(b: *Bolt) void {
        const gpa = b.gpa;
        b.loom.deinit();
        b.sc.deinit();
        b.built.deinit();
        b.gr.deinit();
        gpa.destroy(b);
    }

    fn open(b: *Bolt) !weave.Weave {
        return weave.Weave.init(b.gpa, &b.loom);
    }
};

/// What the fuzz found, so a run can say something rather than only not fail.
const Tally = struct {
    edits: u32 = 0,
    /// Edits after which the file still parsed whole. Only those can be checked
    /// against a spine, since a stopped parse has no product.
    whole: u32 = 0,
    lifts: u32 = 0,
    /// Forks created and forks collapsed, summed over the stream. A floor on
    /// these is what stops this suite passing without ever running the strand
    /// machinery: json and rust both fire zero forks, so before java was added
    /// nothing here had exercised a per-limb trail at all.
    rifts: u64 = 0,
    roosts: u64 = 0,
    /// Bytes that arrived as a whole subtree, over the bytes of the files they
    /// arrived into. Lift *coverage*, which is the thing every other column
    /// here can look healthy without: a run may lift constantly and still
    /// re-read most of the file if each lift is a fragment. java lifted 3449
    /// times over less of the file than it now covers in 2078.
    skipped: u64 = 0,
    bytes: u64 = 0,
    /// Nodes lifted, over nodes built. The share of the tree that was reused.
    carried: u64 = 0,
    nodes: u64 = 0,
    /// Leaves re-derived, over leaves held. The re-mint window.
    minted: u64 = 0,
    leaves: u64 = 0,
    widest: u32 = 0,
    /// Tokens the scanner read, over tokens a cold parse would have.
    read: u64 = 0,
    cold: u64 = 0,
    /// Edits whose parse stood back up on a kept stack rather than on the
    /// ground, and the bytes those stacks stood past. A run that resumed
    /// nothing would pass every assertion here by re-parsing everything.
    stood: u32 = 0,
    passed: u64 = 0,
    /// Edits that left the file needing recovery, and the mends they cost. An
    /// edit stream wanders out of the language constantly, so these are not
    /// rare; counting them is what turns "the fuzz did not catch recovery
    /// breaking reuse" into "the fuzz reused across mended files this many
    /// times and the tree still matched".
    mended: u32 = 0,
    mends: u64 = 0,
    /// Edits that stood back up on a tiling with a hole in it - the previous
    /// parse mended, and this one resumed above the break anyway.
    ///
    /// This is the only column that reaches the machinery round 19 added, and
    /// none of the others can stand in for it: `stood` counts resumes on clean
    /// tilings, `mended` counts breaks nobody resumed over, and a corpus of
    /// files that parse whole never reaches the line at all. Before the repair
    /// this was structurally zero - one mend anywhere stopped every later ring
    /// being taken, and `w.frail` floored the resume below the first wall - so
    /// a floor here is a threshold with a demonstrated failing case rather than
    /// today's number written down.
    healed: u32 = 0,
    /// Tilings cleared, split by which site cleared them: a resume that landed
    /// inside a leaf, a prefix product that refused the resume's first leaf,
    /// and the window finding no right edge. Summing them into one "not spun"
    /// number is what hid, for four rounds, that these are different defects -
    /// and the split is what named the third one, since `win` read 293 of 293
    /// mended json edits while the other two read zero.
    ///
    /// All three read zero now. `win` in particular no longer means "the file
    /// has a hole in it": a hole ends the window's search without declining,
    /// so anything counted here is a seam inside the window rather than a
    /// break in the text.
    off: u32 = 0,
    seam: u32 = 0,
    win: u32 = 0,
    /// The fourth, and the one this corpus cannot reach: a resumed parse that
    /// walls before laying a leaf of its own, so its folds are charged across
    /// the resume onto the previous parse's last leaf. It was a fatal until the
    /// resume was made to decline instead, and it reads zero here because every
    /// resume on this corpus lays a leaf first.
    charge: u32 = 0,
};

const Run = struct {
    gpa: std.mem.Allocator,
    bolt: *Bolt,
    w: weave.Weave,
    /// The same policy with the subtree reuse declined. It re-reads every byte,
    /// so its leaves are the cold parse's leaf for leaf, which is what makes a
    /// held suffix checkable one element at a time. `w` cannot be held to that
    /// and should not be: a lift is a coarser tiling on purpose.
    plain: weave.Weave,
    /// The oracle: a weave that reuses nothing and re-mints everything after
    /// every edit. Held open rather than made per edit so its arena is reused.
    cold: weave.Weave,
    text: std.ArrayList(u8),
    tally: Tally = .{},
    bend: weave.Bend = .none,
    /// Whether the spine is held to the cold parse's spine as well as its tree.
    /// True in the fuzz. False in exactly one test - the one that shows `snap`
    /// losing the spine while keeping the tree, which is the whole claim that a
    /// bad window costs money rather than trust.
    algebra: bool = true,
    /// Scratch for the bytes an edit inserts.
    put: [16]u8 = undefined,
    /// The prefix-continuity instrument. `seen` counts the edits it examined
    /// so it can say it found nothing; `told` stops it after the first report,
    /// because the interesting edit is the one where a discontinuity is *born*
    /// and every edit after it inherits the same pair.
    seen: u32 = 0,
    told: bool = false,
    /// Whether the parse that laid the tiling now on offer had a break in it.
    holed: bool = false,

    fn init(bolt: *Bolt, seed0: []const u8, policy: weave.Policy, bend: weave.Bend) !Run {
        var r: Run = .{
            .gpa = bolt.gpa,
            .bolt = bolt,
            .w = try bolt.open(),
            .plain = try bolt.open(),
            .cold = try bolt.open(),
            .text = .empty,
            .bend = bend,
        };
        errdefer r.deinit();
        r.w.policy = policy;
        r.w.bend = bend;
        r.plain.policy = policy;
        r.plain.bend = bend;
        r.plain.reusing = false;
        r.cold.policy = .whole;
        r.cold.reusing = false;
        try r.text.appendSlice(r.gpa, seed0);
        try r.w.open(seed0);
        try r.plain.open(seed0);
        return r;
    }

    fn deinit(r: *Run) void {
        r.text.deinit(r.gpa);
        r.cold.deinit();
        r.plain.deinit();
        r.w.deinit();
    }

    /// Play one recorded magnitude against whatever file it lands on, checking
    /// after it - and, if it broke the file, take it back and check that too.
    ///
    /// The undo is not politeness. A random generator wanders out of the
    /// language on its second or third edit and has no way back, so a script
    /// without one spends its whole length re-measuring the recovery path and
    /// never once measures reuse. Taking a bad edit back is what a person does
    /// with it, and both halves are ordinary edits that get checked like any.
    fn play(r: *Run, st: Step) !void {
        var held: [16]u8 = undefined;
        const e = r.draw(st);
        const gone = held[0 .. e.to - e.from];
        @memcpy(gone, r.text.items[e.from..e.to]);
        try r.apply(e);
        try r.check();
        if (r.w.tree.?.stop == .accepted) return;
        try r.apply(.{ .from = e.from, .to = e.from + @as(u32, @intCast(e.put.len)), .put = gone });
        try r.check();
    }

    const Edit = struct { from: u32, to: u32, put: []const u8 };

    /// Fold a magnitude onto the file: which bytes to lift out, and what to put
    /// in their place. The inserted bytes live in the run so the caller can
    /// hold the removed ones somewhere else and swap the two back.
    fn draw(r: *Run, st: Step) Edit {
        const n: u32 = @intCast(r.text.items.len);
        var prng = std.Random.DefaultPrng.init(st.seed);
        const rng = prng.random();
        var from = if (n == 0) 0 else st.from % n;
        var to = from;
        var wide: u32 = 0;

        var kind = st.kind;
        // A file with no word bytes left has nothing to type into; the edit
        // falls back rather than being dropped, so the script stays playable.
        if (kind == .inside) {
            while (from < n and !word(r.text.items[from])) from += 1;
            if (from == n) {
                from = if (n == 0) 0 else st.from % n;
                kind = .space;
            }
        }
        switch (kind) {
            .space => {
                // Half the time widen over the whitespace already there, so
                // the stream sees deletions and not only a file growing.
                if (st.span % 2 == 0) while (to < n and to - from < 8 and ws(r.text.items[to])) {
                    to += 1;
                };
                wide = rng.uintLessThan(u32, 4);
                for (r.put[0..wide]) |*b| b.* = " \n\t "[rng.uintLessThan(u32, 4)];
            },
            .inside => {
                to = from + 1 + st.span % @min(n - from, 3);
                wide = 1 + rng.uintLessThan(u32, 3);
                for (r.put[0..wide]) |*b| {
                    b.* = "abcdefghijklmnopqrstuvwxyz0123456789_"[rng.uintLessThan(u32, 37)];
                }
            },
            .wild => {
                to = from + st.span % (@min(n - from, 12) + 1);
                wide = rng.uintLessThan(u32, 9);
                for (r.put[0..wide]) |*b| {
                    b.* = if (n == 0) ' ' else r.text.items[rng.uintLessThan(u32, n)];
                }
            },
        }
        return .{ .from = from, .to = to, .put = r.put[0..wide] };
    }

    fn apply(r: *Run, e: Edit) !void {
        const wide: u32 = @intCast(e.put.len);
        try r.text.replaceRange(r.gpa, e.from, e.to - e.from, e.put);
        try r.w.amend(.{ .from = e.from, .to = e.to, .insert = wide }, e.put);
        try r.plain.amend(.{ .from = e.from, .to = e.to, .insert = wide }, e.put);
        try r.cold.open(r.text.items);
        r.tally.edits += 1;
    }

    fn check(r: *Run) !void {
        try r.continuous();
        const cold = r.cold.tree.?;
        try r.same(&r.w, cold);
        try r.same(&r.plain, cold);

        r.tally.skipped += r.w.cost.skipped;
        r.tally.bytes += r.text.items.len;
        r.tally.carried += r.w.cost.carried;
        r.tally.nodes += r.w.cost.nodes;
        r.tally.lifts += r.w.cost.lifts;
        r.tally.rifts += r.w.gather.rifts;
        r.tally.roosts += r.w.gather.roosts;
        r.tally.read += r.w.cost.read;
        r.tally.cold += r.cold.cost.read;
        if (r.w.cost.stood > 0) {
            r.tally.stood += 1;
            r.tally.passed += r.w.cost.stood;
            // The tiling this stack stood on is the one the *previous* parse
            // laid, so that is the parse whose breaks decide whether this was
            // a resume over a hole.
            if (r.holed) r.tally.healed += 1;
        }
        if (cold.mends > 0) {
            r.tally.mended += 1;
            r.tally.mends += cold.mends;
        }
        r.holed = if (r.w.tree) |q| q.mends > 0 else false;
        switch (r.w.unspun) {
            .none => {},
            .off => r.tally.off += 1,
            .seam => r.tally.seam += 1,
            .charge => r.tally.charge += 1,
            .win => r.tally.win += 1,
        }
        if (!r.w.spun) return;

        r.tally.whole += 1;
        r.tally.minted += r.plain.cost.minted;
        r.tally.leaves += r.plain.cost.leaves;
        r.tally.widest = @max(r.tally.widest, @as(u32, @intCast(r.w.leaves.items.len)));
        if (r.algebra) try r.derives();
    }

    /// Every adjacent pair in the tiling, asked locally rather than as a fold.
    ///
    /// `product()` refusing says only that *some* pairing failed, and the
    /// left-to-right fold that finds it reports where the accumulation gave
    /// out, which is not where the two runs stopped being adjacent. This asks
    /// the pairwise question - does leaf i compose with leaf i+1, on their own,
    /// with nothing else in hand - so the answer is a seam and not an index.
    ///
    /// The two generations are the whole point. A pair minted by the same parse
    /// was derived side by side, so a refusal between them is the derivation's:
    /// a lifted leaf whose exit is not a legal left operand for an unlifted
    /// right. A pair whose generations differ was never derived together; one
    /// side was retained past a re-parse of the other, and a refusal between
    /// them is the retention's.
    ///
    /// Holes are skipped on both sides. `compose` refuses beside the zero by
    /// design and that refusal is the mend doing its job, not a seam coming
    /// apart.
    fn continuous(r: *Run) !void {
        if (r.bend != .none or !r.w.spun or r.told) return;
        r.seen += 1;
        const x = r.w.arena();
        const leaves = r.w.leaves.items;
        for (1..leaves.len) |i| {
            const l = leaves[i - 1];
            const n = leaves[i];
            if (l.element.entry == effect.Effect.broken) continue;
            if (n.element.entry == effect.Effect.broken) continue;
            if (try effect.compose(x, l.element, n.element) != null) continue;

            const at = r.w.starts.items[i];
            // Coarser than the cold parse over the same bytes is what a lift
            // leaves behind, and it is visible without a flag: count how many
            // leaves a parse that lifted nothing put inside this one's span.
            var under: u32 = 0;
            for (r.cold.starts.items) |c| {
                if (c >= r.w.starts.items[i - 1] and c < at) under += 1;
            }
            std.debug.print(
                "SEAM edit {d}: leaves {d}|{d} part at byte {d} (floor {d}, window {d}..{d} was {d})\n" ++
                    "  left  ends {d}  entry {d} guard {d} push {d}  gen {d}  cold leaves under it {d}\n" ++
                    "  right start {d}  entry {d} guard {d} push {d}  gen {d}\n" ++
                    "  minted {s}\n",
                .{
                    r.seen,                        i - 1,
                    i,                             at,
                    r.w.lastfloor,                 r.w.lastfrom,
                    r.w.lastto,                    r.w.lastwas,
                    at,                            l.element.entry,
                    @intFromEnum(l.element.guard), @intFromEnum(l.element.push),
                    r.w.gens.items[i - 1],         under,
                    at,                            n.element.entry,
                    @intFromEnum(n.element.guard), @intFromEnum(n.element.push),
                    r.w.gens.items[i],
                    if (r.w.gens.items[i - 1] == r.w.gens.items[i])
                        "together - the derivation's"
                    else
                        "apart - the retention's",
                },
            );
            r.told = true;
            // Reported, not asserted, and the difference is the algebra's.
            // The spine folds ranges rather than neighbours, so a node joining
            // a range that ends here to one that starts there composes with the
            // whole left context in hand, and a guard the single leaf cannot
            // satisfy the prefix often can. A refusing pair is therefore a
            // place to look and not a defect on its own; the defect is the
            // product, which is what the caller checks. Both were true at once
            // in round 14, which is what made this a locator.
            return;
        }
        // The other way the answer can be no: the fold gave out but no two
        // neighbours did. Then the discontinuity is not at any seam and the
        // pairwise question is the wrong one, which is worth one line.
        if (r.algebra and !weave.Joint.same(r.w.product(), r.cold.product())) {
            std.debug.print(
                "edit {d}: the product refuses and every adjacent pair composes\n",
                .{r.seen},
            );
            r.told = true;
        }
    }

    /// The path where the answer is no. Absence of a SEAM line has meant
    /// nothing twice this project; this makes it mean something.
    fn verdict(r: *Run) void {
        if (r.bend != .none) return;
        if (!r.told) std.debug.print(
            "every adjacent pair in the prefix agrees on state, all {d} edits\n",
            .{r.seen},
        );
    }

    /// Whether the maintained spine still says what a cold one does, as one
    /// answer rather than as a located failure. The fuzz wants the location and
    /// asks `same` and `derives` directly; a policy measurement only wants to
    /// know that the policy lost it.
    fn agrees(r: *Run) bool {
        return weave.Joint.same(r.w.product(), r.cold.product()) and r.parted() == null;
    }

    /// One weave's tree, spine and tiling against a cold parse of the same
    /// text.
    ///
    /// The tree is compared twice on purpose: as an s-expression, which is what
    /// a reader of a failure wants, and node for node, which catches the spans
    /// an s-expression prints the same way.
    fn same(r: *Run, it: *weave.Weave, cold: quire.Quire) !void {
        const got = it.tree.?;
        // Before the comparison, not after it, and not instead of it. A tree
        // can equal a cold parse and still be a structure no parse could have
        // made, and the kept stack beside it is not in the comparison at all -
        // round 20's defect was a ring that carried one node twice, shipped
        // two hundred edits before the tree it eventually corrupted. Asking
        // here means the edit that *makes* a bad snapshot is the edit that
        // reports it.
        try got.verify(r.gpa);
        try it.bough.verify(r.gpa, &got);
        try t.expectEqual(std.meta.activeTag(cold.stop), std.meta.activeTag(got.stop));
        // Two parses can agree on every root and still have got there by
        // different routes; a reuse that skipped a wall the cold parse had to
        // mend past is exactly the shape of a wrong tree that prints right.
        try t.expectEqual(cold.mends, got.mends);
        try t.expectEqual(cold.roots.len, got.roots.len);
        for (cold.roots, got.roots) |a, b| {
            const one = try cold.sexp(r.gpa, a, .all);
            defer r.gpa.free(one);
            const two = try got.sexp(r.gpa, b, .all);
            defer r.gpa.free(two);
            try t.expectEqualStrings(one, two);
            try spans(&cold, a, &got, b);
        }
        if (!it.spun) return;

        // The leaves cover the file, once, in order. A spine that has stopped
        // addressing the whole text is answering about a file nobody has, and a
        // dropped span is silent: the product is still an element, just the
        // wrong one over the wrong bytes.
        var at: u32 = 0;
        for (it.leaves.items, it.starts.items) |l, from| {
            try t.expectEqual(at, from);
            at += l.bytes;
        }
        try t.expectEqual(@as(u32, @intCast(r.text.items.len)), at);

        try it.spine.verify(it.arena());
        try t.expect(weave.Joint.same(it.product(), try it.scratch()));
        if (r.algebra) try t.expect(weave.Joint.same(it.product(), r.cold.product()));
    }

    /// The leaves a cold parse derives are the leaves this text has - element
    /// for element, entry state for entry state.
    ///
    /// This is the check the re-mint window exists to pass, and it is stronger
    /// than comparing whole-file products: an accepted json file has much the
    /// same product as any other, so a run that only checked the root would
    /// pass with the middle of the spine still describing yesterday's text. A
    /// suffix the policy held onto that a cold parse would not derive is
    /// exactly the one way the policy question has a wrong answer, and it
    /// shows up here as one element out of two hundred.
    ///
    /// It is asked of the weave that declines lifts, because a lift is
    /// deliberately a coarser tiling: it lands a whole subtree in one move, so
    /// the reduce that completes the subtree falls on the far side of a leaf
    /// boundary from where a cold parse puts it. Both are the same product over
    /// the file and the same tree; only the seams differ, and holding a lift to
    /// a cold parse's seams would be holding it to a fold order nothing
    /// promised. What is not a degree of freedom - that the tree and the
    /// product match - `same` has already asked of both weaves.
    fn derives(r: *Run) !void {
        const rift = r.parted() orelse return;
        std.debug.print(
            "tiling parts from cold at leaf {d} of {d}: {s} - cold {d}, warm {d}\n",
            .{ rift.leaf, r.cold.leaves.items.len, rift.why, rift.cold, rift.warm },
        );
        return error.TilingParted;
    }

    /// The first place the maintained tiling and a cold parse of the same text
    /// part company, or null when they agree everywhere.
    ///
    /// A predicate, and that is the whole of round 22's repair here. `agrees`
    /// *scores* this comparison - how often a policy loses the spine is the
    /// number that test is for - and `derives` *asserts* it. When both went
    /// through one body written in `expectEqual`, the scored call printed
    /// `expected 289, found 0` from inside a **passing** test, because
    /// `expectEqual` prints before it returns and `agrees` swallowed the
    /// error. That is the same shape as `same()` comparing only the rendered
    /// tree: a check whose failure path is indistinguishable from its success
    /// path, occupying the seat a real comparison would take.
    ///
    /// So the comparison answers, the callers decide what an answer means, and
    /// only the one that fails a test prints - with a located rift rather than
    /// two bare integers, which is more than the swallowed version ever gave
    /// the reader it was printing at.
    fn parted(r: *const Run) ?Rift {
        const cold = r.cold.leaves.items;
        const warm = r.plain.leaves.items;
        if (cold.len != warm.len) {
            return .{ .leaf = @min(cold.len, warm.len), .why = "leaf count", .cold = cold.len, .warm = warm.len };
        }
        for (
            warm,
            r.plain.starts.items,
            r.plain.entries.items,
            cold,
            r.cold.starts.items,
            r.cold.entries.items,
            0..,
        ) |l, from, entry, want, at, was, i| {
            if (from != at) return .{ .leaf = i, .why = "start", .cold = at, .warm = from };
            if (entry != was) return .{ .leaf = i, .why = "entry state", .cold = was, .warm = entry };
            if (l.bytes != want.bytes) return .{ .leaf = i, .why = "bytes", .cold = want.bytes, .warm = l.bytes };
            if (!weave.Joint.same(want.element, l.element)) {
                return .{ .leaf = i, .why = "element", .cold = want.element.entry, .warm = l.element.entry };
            }
        }
        return null;
    }
};

/// Where a maintained tiling stops matching a cold one, and on which of the
/// four facts. Named rather than returned as a bool so a scored caller and an
/// asserting one can share one comparison without sharing one verdict.
const Rift = struct {
    leaf: usize,
    why: []const u8,
    cold: u64,
    warm: u64,
};

/// Every node's span, in lockstep down two trees. The s-expression is blind to
/// offsets, so this is the only check that can see a subtree lifted onto the
/// wrong bytes.
fn spans(a: *const quire.Quire, x: quire.Ref, b: *const quire.Quire, y: quire.Ref) !void {
    try t.expectEqual(a.nodes[x].start, b.nodes[y].start);
    try t.expectEqual(a.nodes[x].len, b.nodes[y].len);
    try t.expectEqual(a.nodes[x].kind.extra, b.nodes[y].kind.extra);
    const one = a.children(x);
    const two = b.children(y);
    try t.expectEqual(one.len, two.len);
    for (one, two) |p, q| try spans(a, p, b, q);
}

fn breaks(
    bolt: *Bolt,
    seed0: []const u8,
    policy: weave.Policy,
    bend: weave.Bend,
    script: []const Step,
) anyerror!bool {
    var r = Run.init(bolt, seed0, policy, bend) catch |e| {
        if (e == error.OutOfMemory) return e;
        return true;
    };
    defer r.deinit();
    for (script) |st| {
        r.play(st) catch |e| {
            if (e == error.OutOfMemory) return e;
            return true;
        };
    }
    return false;
}

/// Cut the script down to the edits the failure needs, largest bites first.
///
/// One-at-a-time removal is the obvious shape and it is unusable here: a
/// six-hundred-edit script would replay six hundred scripts of six hundred
/// edits, and every one of those edits is two parses. Halving spans finds the
/// same fixpoint after a handful of passes, because a failure that needs six
/// edits out of six hundred is mostly one long removable stretch.
fn shrink(
    bolt: *Bolt,
    seed0: []const u8,
    policy: weave.Policy,
    bend: weave.Bend,
    script: *std.ArrayList(Step),
) anyerror!void {
    const gpa = bolt.gpa;
    var held: std.ArrayList(Step) = .empty;
    defer held.deinit(gpa);

    var span = @max(script.items.len / 2, 1);
    while (span > 0) : (span /= 2) {
        var i: usize = 0;
        while (i + span <= script.items.len) {
            held.clearRetainingCapacity();
            try held.appendSlice(gpa, script.items[i..][0..span]);
            try script.replaceRange(gpa, i, span, &.{});
            if (try breaks(bolt, seed0, policy, bend, script.items)) continue;
            try script.insertSlice(gpa, i, held.items);
            i += 1;
        }
    }
}

fn drive(
    bolt: *Bolt,
    name: []const u8,
    seed0: []const u8,
    policy: weave.Policy,
    seed: u64,
    edits: u32,
) anyerror!Tally {
    const gpa = bolt.gpa;
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var script: std.ArrayList(Step) = .empty;
    defer script.deinit(gpa);

    var r = try Run.init(bolt, seed0, policy, .none);
    defer r.deinit();

    for (0..edits) |_| {
        const st: Step = .{
            .kind = deal(rng),
            .from = rng.int(u32),
            .span = rng.int(u32),
            .seed = rng.int(u64),
        };
        try script.append(gpa, st);
        r.play(st) catch |e| return confess(bolt, name, seed0, policy, seed, &script, e);
    }
    const q = r.tally;
    r.verdict();
    std.debug.print(
        "  {s:<12} {s:<5} {d:>5} edits  {d:>4} whole  {d:>5} lifts  " ++
            "window {d:>5.1}/{d:<5.1}  nodes reused {d:>4.0}%  tokens read {d:>4.0}%  " ++
            "bytes lifted {d:>4.0}%  resumed {d:>4} past {d:>5.0}B  " ++
            "mended {d:>4} ({d} mends)  over a hole {d:>4}  cleared {d}off/{d}seam/{d}win\n",
        .{
            name,                                                 @tagName(policy),
            q.edits,                                              q.whole,
            q.lifts,                                              ratio(q.minted, q.whole),
            ratio(q.leaves, q.whole),                             100 * ratio(q.carried, 1) / @max(1.0, ratio(q.nodes, 1)),
            100 * ratio(q.read, 1) / @max(1.0, ratio(q.cold, 1)), 100 * ratio(q.skipped, 1) / @max(1.0, ratio(q.bytes, 1)),
            q.stood,                                              ratio(q.passed, q.stood),
            q.mended,                                             q.mends,
            q.healed,                                             q.off,
            q.seam,                                               q.win,
        },
    );
    return q;
}

/// The mix. Weighted towards the edits a person actually makes, because those
/// are the ones a reuse path has to be good at and the ones that leave a file
/// worth reusing.
fn deal(rng: std.Random) Kind {
    return switch (rng.uintLessThan(u32, 10)) {
        0, 1, 2, 3, 4 => .space,
        5, 6, 7 => .inside,
        else => .wild,
    };
}

fn ws(b: u8) bool {
    return b == ' ' or b == '\n' or b == '\t' or b == '\r';
}

fn word(b: u8) bool {
    return std.ascii.isAlphanumeric(b) or b == '_';
}

fn ratio(a: u64, b: u64) f64 {
    return @as(f64, @floatFromInt(a)) / @as(f64, @floatFromInt(@max(b, 1)));
}

fn confess(
    bolt: *Bolt,
    name: []const u8,
    seed0: []const u8,
    policy: weave.Policy,
    seed: u64,
    script: *std.ArrayList(Step),
    e: anyerror,
) anyerror {
    std.debug.print("\nweave: {s} broke at edit {d} with {s} (seed 0x{X:0>16}, {s})\n", .{
        name, script.items.len - 1, @errorName(e), seed, @tagName(policy),
    });
    shrink(bolt, seed0, policy, .none, script) catch {};
    std.debug.print("  minimal reproducer, {d} edit(s):\n", .{script.items.len});
    for (script.items, 0..) |st, i| std.debug.print(
        "    [{d}] {s} from={d} span={d} seed=0x{X:0>16}\n",
        .{ i, @tagName(st.kind), st.from, st.span, st.seed },
    );
    return e;
}

/// The committed json grammar the rest of the quire's tests are written
/// against, so a failure here is about the weave rather than about a fiction.
const json_src = @embedFile("json_grammar");

/// A file off the shelf, or `error.FileNotFound` when the tree is not
/// underfoot. Fixtures, not build inputs, so a run that cannot see them skips.
fn shelf(gpa: std.mem.Allocator, path: []const u8) ![]u8 {
    var threaded = std.Io.Threaded.init(gpa, .{});
    defer threaded.deinit();
    return std.Io.Dir.cwd().readFileAlloc(threaded.io(), path, gpa, .limited(64 << 20));
}

test "weave: the incremental tree equals a cold parse after every edit" {
    const gpa = t.allocator;
    const bolt = try Bolt.of(gpa, json_src);
    defer bolt.deinit();
    const seed0 = shelf(gpa, "research/joinery/corpus/ledger.json") catch |e| {
        if (e == error.FileNotFound) return error.SkipZigTest;
        return e;
    };
    defer gpa.free(seed0);

    std.debug.print("\nweave: edit streams against a cold parse\n", .{});
    const p = try drive(bolt, "json", seed0, .prove, 0xA31E_5EED_0F10_0001, 1500);
    // A reuse test that never reused anything passes every assertion above by
    // doing nothing, so the floor is part of the claim.
    try t.expect(p.lifts > 200);
    try t.expect(p.whole > 100);
    try t.expect(p.widest > 32);
    // And the same floor for the other half of reuse. A stream that never
    // stood back up would be checking a cold parse against a cold parse.
    try t.expect(p.stood > 200);
    try t.expect(ratio(p.passed, p.stood) > 128);
    // The third floor, and the one this round added: an edit stream spends
    // most of its length out of the language, so a run that never reused
    // across a recovered file would be evidence about clean input only.
    try t.expect(p.mended > 200);
    try t.expect(p.mends > p.mended);
    // The three floors above are all satisfied by a stream that reuses on its
    // clean edits and re-parses every broken one, which is exactly what this
    // suite did until round 21: 293 mended edits, and `healed` said not one of
    // them stood back up on a tiling a break had shaped. `mended` cannot see
    // that - a break the run never reused across still counts - which is why
    // round 19 added the column rather than another floor. It read 0 against
    // `win` 293, because the window declined on a hole and took the whole
    // tiling with it, prefix and all, so the *next* keystroke was cold too.
    //
    // That pair was pinned as an equality on purpose, as today's defect
    // written down rather than left unstated, and this is the repair that
    // earns the floor: a hole ends the search for a right edge without
    // declining the tiling. Calibrated the same way `b.healed` below is -
    // against the structural zero it replaces, not against today's 37.
    try t.expect(p.healed > 20);
    try t.expectEqual(@as(u32, 0), p.win);

    const b = try drive(bolt, "json", seed0, .whole, 0xA31E_5EED_0F10_0001, 1500);
    // Re-minting everything past the cut is trivially right and costs the file;
    // the point of a right edge is that it does not.
    try t.expectEqual(p.lifts, b.lifts);
    // And the floor round 19 does earn today. `.whole` never declines a window,
    // so it is the one policy here that reaches a resume standing above a break
    // - and every one of those trees was checked against a cold parse, which is
    // what makes the ring-past-a-mend repair a claim rather than a hope. Before
    // it this was structurally zero: one mend anywhere stopped every later ring
    // being taken, so there was nothing above a break to stand on. Calibrated
    // against that, not written down from today's 37.
    try t.expect(b.healed > 20);
    // And the shape of round 21's repair, stated as the inequality it really
    // is rather than as the equality both sides happen to read today. `.whole`
    // never declines a window, so it is the ceiling on how often any policy
    // can stand back up over a hole, and `prove` can only fall short of it by
    // declining one. It no longer does on this stream.
    //
    // A future failure here is not a number to lower. It says a window
    // declined, and since a hole returns before that line the only thing left
    // is a *seam* - two runs the parse never put side by side - which is round
    // 14's real hazard and worth going to look at.
    try t.expect(p.healed >= b.healed);
    // Measured, not aspired to: re-minting to the end of the file costs about
    // twice what stopping at the first rejoin does on this stream.
    try t.expect(ratio(b.minted, p.minted) > 1.8);
}

test "weave: what each re-mint policy costs, and what the cheap one loses" {
    const gpa = t.allocator;
    const bolt = try Bolt.of(gpa, json_src);
    defer bolt.deinit();
    const seed0 = shelf(gpa, "research/joinery/corpus/ledger.json") catch |e| {
        if (e == error.FileNotFound) return error.SkipZigTest;
        return e;
    };
    defer gpa.free(seed0);

    std.debug.print("\nweave: re-mint policies over one stream\n", .{});
    var minted: [3]f64 = undefined;
    for ([_]weave.Policy{ .snap, .prove, .whole }, 0..) |policy, k| {
        var prng = std.Random.DefaultPrng.init(0xA31E_5EED_0F10_0001);
        const rng = prng.random();
        var r = try Run.init(bolt, seed0, policy, .none);
        defer r.deinit();
        // The spine comparison is scored rather than asserted, because how
        // often a policy loses the spine is the number this test is for. The
        // tree comparison stays an assertion throughout, which is the claim
        // that a wrong window costs money and never trust.
        r.algebra = false;

        var lost: u32 = 0;
        for (0..1200) |_| {
            try r.play(.{
                .kind = deal(rng),
                .from = rng.int(u32),
                .span = rng.int(u32),
                .seed = rng.int(u64),
            });
            if (!r.agrees()) lost += 1;
        }
        minted[k] = ratio(r.tally.minted, r.tally.whole);
        std.debug.print("  {s:<5} window {d:>5.1}/{d:<5.1} leaves   spine lost after {d} of {d} edits\n", .{
            @tagName(policy), minted[k],     ratio(r.tally.leaves, r.tally.whole),
            lost,             r.tally.edits,
        });
        // `prove` is `snap` and then a composition, so it can only ever widen
        // further; the one that asks nothing can only ever be the narrowest.
        // A run where that ordering broke would mean the window is not a
        // function of the policy at all.
        if (policy == .prove) try t.expect(minted[1] >= minted[0]);
        if (policy == .whole) try t.expect(minted[2] > minted[1] * 1.8);
        // The two sound ones never lose it. `snap` is not asserted either way:
        // it lost the spine 642 edits into this same stream against the tables
        // the press emitted earlier today, and holds against the ones it emits
        // now, which is the entire reason it is not the policy in force.
        if (policy != .snap) try t.expectEqual(@as(u32, 0), lost);
    }
}

test "weave: what a keystroke costs as the file grows" {
    const gpa = t.allocator;
    const bolt = try Bolt.of(gpa, json_src);
    defer bolt.deinit();
    const one = shelf(gpa, "research/joinery/corpus/ledger.json") catch |e| {
        if (e == error.FileNotFound) return error.SkipZigTest;
        return e;
    };
    defer gpa.free(one);

    std.debug.print("\nweave: one keystroke, against 4x the file each time\n", .{});
    for ([_]u32{ 1, 4, 16, 64 }) |copies| {
        // The same file over and over inside an array, which is a bigger file
        // of the same shape: the point is what the *height* does, and a
        // different corpus at each size would confound it with the grammar.
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(gpa);
        try text.append(gpa, '[');
        for (0..copies) |k| {
            if (k > 0) try text.append(gpa, ',');
            try text.appendSlice(gpa, one);
        }
        try text.append(gpa, ']');

        var w = try bolt.open();
        defer w.deinit();
        w.policy = .prove;
        try w.open(text.items);
        const cold = w.cost;

        // A space typed at evenly spaced points, which is the keystroke the
        // claim is about. Deletions of the same space follow, so the file the
        // next edit lands on is the one this one started from.
        const beats: u32 = 48;
        var window: [48]u32 = undefined;
        var height: u64 = 0;
        var read: u64 = 0;
        for (0..beats) |k| {
            const at: u32 = @intCast((text.items.len - 1) * (k + 1) / (beats + 1));
            try w.amend(.{ .from = at, .to = at, .insert = 1 }, " ");
            window[k] = w.cost.minted;
            height += w.cost.height;
            read += w.cost.read;
            try w.amend(.{ .from = at, .to = at + 1, .insert = 0 }, "");
        }
        // Reported as a distribution rather than a mean, because the mean is
        // the wrong statistic here and hides the finding: nearly every
        // keystroke re-mints one leaf whatever the file weighs, and a small
        // minority land somewhere the parse does not rejoin for a while and
        // cost the tail of the file. An average of those two populations
        // describes neither.
        std.mem.sort(u32, &window, {}, std.sort.asc(u32));
        std.debug.print(
            "  {d:>3}x  {d:>6} leaves  height {d:>4.1}  reminted p50 {d:>3} p90 {d:>4} max {d:>5}" ++
                "   read {d:>5.1}% of {d}\n",
            .{
                copies,                                         cold.leaves,
                ratio(height, beats),                           window[beats / 2],
                window[beats * 9 / 10],                         window[beats - 1],
                100 * ratio(read, beats) / ratio(cold.read, 1), cold.read,
            },
        );
        // The claim, as a number that cannot be met by luck: sixty-four times
        // the leaves and the median keystroke still re-mints a fixed handful.
        // The height beside it is what those leaves cost to splice back in.
        try t.expect(window[beats / 2] <= 4);
        try t.expect(w.cost.height < 24);
    }
}

test "weave: the same, on rust, which is the grammar that forks" {
    const gpa = t.allocator;
    const src = shelf(gpa, "upstream/grammars/rust.json") catch |e| {
        if (e == error.FileNotFound) return error.SkipZigTest;
        return e;
    };
    defer gpa.free(src);
    const bolt = try Bolt.of(gpa, src);
    defer bolt.deinit();
    const seed0 = shelf(gpa, "research/joinery/corpus/ledger.rs") catch |e| {
        if (e == error.FileNotFound) return error.SkipZigTest;
        return e;
    };
    defer gpa.free(seed0);

    // A fixture the scanner cannot start on measures nothing, and the floors
    // below would then be reporting the lexer rather than the weave. Skipping
    // is the honest answer; a rust that stops at byte 0 is somebody else's red.
    {
        var probe = try bolt.open();
        defer probe.deinit();
        try probe.open(seed0);
        if (probe.tree.?.stop != .accepted) return error.SkipZigTest;
    }

    const q = try drive(bolt, "rust", seed0, .prove, 0x2057_5EED_0F11_0002, 400);
    // Lift *coverage*, not lift count, and the two move in opposite directions:
    // admitting a lift after the lookahead's folds have run makes each one span
    // a whole item, so rust went from 4486 lifts covering 24% of the bytes to
    // 2566 covering 30%. A count floor would have read that as a regression.
    // Pinned between the two, so the admission set this replaced fails it.
    try t.expect(q.skipped * 100 / @max(1, q.bytes) >= 27);
    try t.expect(q.lifts > 20);
    try t.expect(q.whole > 20);
}

test "weave: the same, on java, whose forks used to forfeit the file" {
    const gpa = t.allocator;
    const src = shelf(gpa, "upstream/grammars/java.json") catch |e| {
        if (e == error.FileNotFound) return error.SkipZigTest;
        return e;
    };
    defer gpa.free(src);
    const bolt = try Bolt.of(gpa, src);
    defer bolt.deinit();
    const seed0 = shelf(gpa, "research/joinery/corpus/Ledger.java") catch |e| {
        if (e == error.FileNotFound) return error.SkipZigTest;
        return e;
    };
    defer gpa.free(seed0);

    {
        var probe = try bolt.open();
        defer probe.deinit();
        try probe.open(seed0);
        if (probe.tree.?.stop != .accepted) return error.SkipZigTest;
    }

    const q = try drive(bolt, "java", seed0, .prove, 0x2057_5EED_0F11_0003, 400);
    // The floor that matters is not the reuse - it is that a fork was created
    // and collapsed while the trail was being written, because that is the only
    // path on which a strand exists to be welded in. rust and json fire zero
    // forks, so without this the suite is green over machinery it never ran.
    try t.expect(q.rifts > 100);
    try t.expect(q.roosts > 50);
    // 18% under the admission set that refused a lift once a fold had run, 28%
    // now. See the rust test above for why this is bytes and not lifts.
    try t.expect(q.skipped * 100 / @max(1, q.bytes) >= 23);
    try t.expect(q.lifts > 20);
    try t.expect(q.whole > 20);

    // The same stream under the policy that never declines a window, which is
    // the only way this corpus can ask whether a resume standing above a break
    // is sound on a *forking* grammar: rust fires zero forks, so its 91 heals
    // never touch the path, and json never forks at all. Round 19 tried twice
    // to let `prove` keep its tiling across a hole and java refused both,
    // returning a tree with a leading `(block_comment)` twice - so the question
    // is whether that duplication belongs to the window policy or to the resume
    // underneath it, and `.whole` answers it by exercising the resume with the
    // window taken out of the picture.
    const a = try drive(bolt, "java", seed0, .whole, 0x2057_5EED_0F11_0003, 400);
    // 75 today. The floor is on `healed` rather than on reuse because a stream
    // of clean edits cannot reach this path at all: it counts the edits that
    // resumed onto a tiling with a hole in it, so a run that stopped mending,
    // or stopped keeping the tiling across a mend, goes red here instead of
    // going green over machinery it never ran.
    try t.expect(a.healed > 40);
}

// The ten edits that separated a ring from a probe.
//
// A ring probe re-lexes a stretch of the file to ask whether the kept token
// stream still reads out of the new bytes, and it borrowed the parse's own
// extras list to do it. Whatever stood in front of the last token it read was
// still sitting there afterwards, and the first `stow` of the parse that
// followed minted it a second time - so the tree came back with its leading
// `(block_comment)` twice. It did not need the resume to succeed: the tenth
// edit here declines every ring and falls through to a cold parse standing on
// the residue, which is why the failing parse resumes nothing and lifts
// nothing and was read for a round as a corruption some earlier edit had left
// behind.
//
// Kept as a fixed script rather than a seed because the seed is a 520-edit
// stream and this is ten edits and five seconds. The floors in the java fuzz
// above are what says the machinery still runs; this is what says this defect
// stays fixed, and it fails on the exact node - `Quire.verify` reports two
// siblings overlapping without needing a cold parse to compare against.
test "weave: a ring probe leaves no extras behind for the next parse to mint" {
    const gpa = t.allocator;
    const src = shelf(gpa, "upstream/grammars/java.json") catch |e| {
        if (e == error.FileNotFound) return error.SkipZigTest;
        return e;
    };
    defer gpa.free(src);
    const bolt = try Bolt.of(gpa, src);
    defer bolt.deinit();
    const seed0 = shelf(gpa, "research/joinery/corpus/Ledger.java") catch |e| {
        if (e == error.FileNotFound) return error.SkipZigTest;
        return e;
    };
    defer gpa.free(seed0);

    const script = [_]Step{
        .{ .kind = .wild, .from = 4112758893, .span = 1595090134, .seed = 0x20AE71DE1169F413 },
        .{ .kind = .space, .from = 2547040469, .span = 1644871271, .seed = 0xD3BA1BA22236A44B },
        .{ .kind = .inside, .from = 3273770982, .span = 2556981051, .seed = 0xB6B907D417BD5289 },
        .{ .kind = .inside, .from = 2429498641, .span = 62688543, .seed = 0xF17F75A3EAF71DEC },
        .{ .kind = .wild, .from = 4208132367, .span = 2211242609, .seed = 0xD9382D326BA00750 },
        .{ .kind = .wild, .from = 1493988254, .span = 2339332807, .seed = 0x2F2A963949DAFD1E },
        .{ .kind = .inside, .from = 2612214075, .span = 1152012614, .seed = 0x0B5C37B25FAE2D12 },
        .{ .kind = .wild, .from = 2163217391, .span = 2986024492, .seed = 0x4D6AC0DDC883D21A },
        .{ .kind = .space, .from = 4207039471, .span = 4165181718, .seed = 0x6AE7817E88A3F763 },
        .{ .kind = .wild, .from = 937366441, .span = 3406869344, .seed = 0x23423E129592F46E },
    };
    var r = try Run.init(bolt, seed0, .whole, .none);
    defer r.deinit();
    for (script) |st| try r.play(st);
    // The last edit is the one that declines every ring, and a run that
    // stopped reaching it would pass this test by not exercising it.
    try t.expect(r.tally.mended > 0);
    try t.expect(r.tally.stood > 0);
}

test "weave: a deliberately broken reuse is caught and shrinks to a few edits" {
    const gpa = t.allocator;
    const bolt = try Bolt.of(gpa, json_src);
    defer bolt.deinit();
    const json_seed = shelf(gpa, "research/joinery/corpus/ledger.json") catch |e| {
        if (e == error.FileNotFound) return error.SkipZigTest;
        return e;
    };
    defer gpa.free(json_seed);

    std.debug.print("\nweave: negative control\n", .{});

    // A stream long enough to reach the flaw, and no longer: the shrinker
    // replays the whole script once per bite, so a hundred spare edits are a
    // hundred spare parses every pass.
    const trials = [_]struct { bend: weave.Bend, seed: u64, raw: u32 }{
        .{ .bend = .skew, .seed = 0xBADA_31EB_ADA3_1EEE, .raw = 96 },
        .{ .bend = .deaf, .seed = 0xBADA_31EB_ADA3_1EEE, .raw = 96 },
        .{ .bend = .adrift, .seed = 0xBADA_31EB_ADA3_1EEE, .raw = 96 },
        .{ .bend = .trusting, .seed = 0xBADA_31EB_ADA3_1EEE, .raw = 96 },
    };
    for (trials) |trial| {
        const bend = trial.bend;
        const raw = trial.raw;
        var prng = std.Random.DefaultPrng.init(trial.seed);
        const rng = prng.random();
        var script: std.ArrayList(Step) = .empty;
        defer script.deinit(gpa);
        for (0..raw) |_| try script.append(gpa, .{
            .kind = deal(rng),
            .from = rng.int(u32),
            .span = rng.int(u32),
            .seed = rng.int(u64),
        });

        try t.expect(try breaks(bolt, json_seed, .prove, bend, script.items));
        try shrink(bolt, json_seed, .prove, bend, &script);
        try t.expect(try breaks(bolt, json_seed, .prove, bend, script.items));
        try t.expect(script.items.len < raw);
        // Every edit left is load-bearing, which is what makes the printed
        // reproducer something a reader can act on.
        for (0..script.items.len) |i| {
            const held = script.orderedRemove(i);
            try t.expect(!try breaks(bolt, json_seed, .prove, bend, script.items));
            try script.insert(gpa, i, held);
        }
        std.debug.print("  {s:<6} broke a {d}-edit stream; shrank to {d}\n", .{
            @tagName(bend), raw, script.items.len,
        });
        // And the same script with the flaw stood down is not a failure at all,
        // which is what says the harness found the break rather than the seed.
        try t.expect(!try breaks(bolt, json_seed, .prove, .none, script.items));
    }
}
