//! Running a segment: the thing that turns a run of tokens into one element of
//! the monoid.
//!
//! A parser walks from a known state. A *segment* does not have one — it starts
//! wherever the text before it happened to leave off, and the whole point of M2
//! is to describe what it does without being told. So the cursor runs the same
//! LR loop against a **candidate set** rather than a state, and everything
//! interesting follows from what happens to that set.
//!
//! Two things can happen to it.
//!
//! It **shrinks**, and this is the mechanism the design lives or dies by. An
//! empty action cell is not an error here: it is a proof that a candidate was
//! never the right one, because a parse that had started there would have
//! failed at this token. Real grammars have sparse action tables, so a few
//! tokens of context eliminate almost everything. That is the same convergence
//! a lexical DFA has, arrived at from the other side.
//!
//! It **reaches below the base**, when a reduction is longer than everything
//! the segment has pushed. The state underneath belongs to the unknown prefix,
//! but the *symbols* the pop removed are known — they are a tail of the
//! production's right-hand side — so `reverse.zig` names the states that string
//! could have come from, and the run continues over all of them at once.
//!
//! *All of them at once*, in one limb, and this is the correction the
//! measurement forced twice. Branching per exposed state is the obvious
//! representation and it is catastrophically wrong: popping a JSON value
//! uncovers the four places a value may be written, all four go on to push the
//! identical symbols, and the run multiplies on every close for no information
//! at all.
//!
//! So a limb is a **set of scenarios over one symbol stack**. The floor is a
//! roster; `above` is the symbols standing on it, shared by every scenario
//! because they are what the segment read; and `perch` is a state *per
//! scenario* per symbol, because where you stand after reading `}` is the one
//! thing the scenarios do disagree about. Feeding a token asks the table once
//! per scenario and then compares only *what it said to do* — a scenario whose
//! cell is empty is refuted and leaves the roster, and the limb splits only
//! when two live scenarios are told to do genuinely different things. Different
//! shift targets are not different things; a shift and a reduce are.
//!
//! What is the same for every limb that survives is the shape of the answer: a
//! depth taken, a claim about each of those depths, and a string pushed — never a
//! parser configuration. So a segment can know exactly what it did to the stack
//! while still being unsure where it is standing, and that asymmetry is what
//! makes the effect a monoid element.

const std = @import("std");
const assay = @import("irregex").assay;
const press = @import("../../press/press.zig");
const effect = @import("effect.zig");
const stack = @import("stack.zig");
const roster = @import("roster.zig");
const ledger = @import("ledger.zig");
const reverse = @import("reverse.zig");

pub const Effect = effect.Effect;
pub const Arena = effect.Arena;

/// One effect the segment could have had, and how sharply the limbs that
/// arrived at it know where they ended.
pub const Yield = struct {
    effect: Effect,
    /// Distinct states a limb with this effect landed in. One means the next
    /// segment composes by a pointer join; more means the join carries a set.
    landings: u32,
};

pub const Outcome = union(enum) {
    /// Every effect the segment could have had, deduplicated and never empty.
    /// One entry is the case the design is a bet on. Borrowed from the cursor
    /// and valid until the next run.
    ran: []const Yield,
    /// The branching outran `limb_ceiling`. A capacity answer rather than a
    /// grammatical one, and it is reported separately for exactly that reason.
    fanned: Fork,
    /// Every limb hit an empty cell at this token index: no parse that entered
    /// here reaches this far.
    rejected: u32,
};

pub const Fork = struct {
    /// Token index it happened at.
    at: u32,
    /// Limbs standing when it happened.
    limbs: u32,
    /// Which capacity ran out. Three very different diagnoses wearing one word
    /// until this existed: `limbs` means the segment is genuinely doing many
    /// things at once, `floor` means it is doing *one* thing and cannot say
    /// where that one thing started (a wide rewind rather than a wide parse),
    /// and `churn` means neither was ever wide — the token just forked and
    /// refuted its forks more times than a run is willing to pay for. On a
    /// conflict-rich table the last two are almost all of them, and a report
    /// that called all three "fanned, 1 way" was unreadable.
    why: enum { limbs, floor, churn },
};

/// How many parallel limbs a run will carry before it gives up and says so.
/// Generous, but not unbounded, and the difference is measured rather than
/// guessed: on a grammar whose table is deterministic no run gets near this,
/// and on one whose table is not the count runs away inside two tokens. There
/// is no grammar in between, so a ceiling ten times higher buys no answer and
/// costs the whole survey — raising it to 4096 turned an 800-state grammar's
/// segment from a second into ninety.
///
/// **That ninety was one knob's reading of a two-knob cost, and it understates
/// the corner by an order of magnitude.** This ceiling and `spawns` are in
/// series: `spawns × limb_ceiling` is the birth budget, so raising either alone
/// leaves the other holding the run down. Go's survey, timed per corner:
/// 256 limbs is 1.1 s at any churn from 4096 to 262144; 1024 limbs is 3.4 s at
/// churn 1024 and **99.5 s** at churn 65536; 4096 limbs is 251.6 s at churn
/// 4096 and was **killed unfinished at forty minutes** at churn 65536. Every
/// one of those corners reports the identical survey — worst p99 rank 18, one
/// residue, 4 of 8 chains held, 4 refused — so the whole curve is cost with no
/// answer behind it. `--fan` is a third axis and not in series with these two:
/// 256 costs 3x and moves worst rank 18 → 43 whatever the other two are.
///
/// The default rather than the law, because "the run gave up" and "the algebra
/// diverges" are different findings and only raising the ceiling tells them
/// apart. `Cursor.limbs_max` is the one in force.
pub const limb_ceiling = 256;

/// How many limbs a run carries before it starts collapsing them mid-token. Low
/// enough that a fold storm is searched for twins while it is cheap to search,
/// high enough that an ordinary token — where nothing forks at all — never pays
/// for a search that would find nothing.
const tidemark = 16;

/// How many times the ceiling's worth of limbs one token may sprout before the
/// run gives up, whatever the collapses did in between.
///
/// The ceiling is over the limbs *standing*, which is the number that means
/// something — a slot a refuted limb left behind is bookkeeping, and a run that
/// stopped because it had touched two hundred and fifty-six of them while
/// holding nine was reporting on itself. But a bound on what stands is not a
/// bound on what it cost to get there: a fold storm that sprouts a thousand
/// limbs and refutes all but nine is cheap to describe and expensive to run, and
/// C's survey spent forty-nine seconds on a nine-hundred-byte file proving it. So
/// the standing count decides what is *reported* and the birth count decides when
/// a run has done enough work to have earned the answer.
///
/// Sixteen because that is where the answer stops changing. Swept over the
/// corpus (`--churn`), C's worst p99 rank climbs 38 → 62 → 68 across 256 → 1024
/// → 4096 and then stays at 68 through 65536, at 0.3 s, 0.8 s, 4.4 s, 23 s and
/// 49 s; every other grammar's number is already final at 1024. So this buys the
/// last of the answer at the last point where it is cheap, and the flag is there
/// because a bound nobody can move is a bound nobody can check.
///
/// **Read that cost column as "at 256 limbs", because that is where it was
/// taken.** `--churn` was swept with `limb_ceiling` held, and this pair is in
/// series, so the seconds it quotes are the cheaper fuse's. Held at 256 limbs,
/// churn is nearly inert on go — 1.1 s at 4096, 1.32 s at 65536, 1.35 s at
/// 262144. Let the ceiling up first and the same knob bites: 1024 limbs is
/// 3.4 s at churn 1024 and 99.5 s at churn 65536, a 29x swing the one-knob
/// sweep could not see. Sixteen is still right, and now for a second reason —
/// the corner it keeps the survey out of is 90x, not 5x.
const spawns = 16;

pub const Cursor = struct {
    gpa: std.mem.Allocator,
    gr: *const press.Grammar,
    c: *const press.Collection,
    t: *const press.Tables,
    rev: *reverse.Reverse,
    pool: *stack.Pool,
    floors: *roster.Pool,
    guards: *ledger.Pool,

    /// The state this run was entered in, which is the effect's domain key.
    entry: u32,
    /// When two limbs are one answer. Settable by a caller measuring the trade;
    /// `.depth` is what a scan wants.
    fusion: Fusion = .depth,
    /// Print the standing limbs when a run hits the ceiling. Off, because a
    /// grammar that fans does it thousands of times and the interesting one is
    /// the first. `JOINTS_TRACE=joint` asks the same question without a field
    /// to set; `confess` resolves the two.
    confessing: bool = false,
    /// How many limbs this cursor will carry. `limb_ceiling` unless a caller is
    /// measuring where the ceiling actually binds.
    limbs_max: usize = limb_ceiling,
    /// How many limbs one token may sprout. `spawns` times the limb ceiling
    /// unless a caller is measuring where the work bound actually binds.
    born_max: usize = spawns * limb_ceiling,
    /// Every limb of the current run, live and spent. Never shrunk: a limb owns
    /// two lists, and a sweep over `|Q|` entry states reuses all of them.
    limbs: std.ArrayList(Limb),
    /// How many of `limbs` this run is using.
    used: usize,
    /// How many of those are still standing. The ceiling is over this and not
    /// over `used`: a slot a refuted limb left behind is bookkeeping, and a run
    /// that gave up because it had *touched* two hundred and fifty-six slots
    /// while holding nine live ones is measuring itself.
    alive: usize,
    /// How wide the limbs may get before they are collapsed again, doubling as
    /// the population survives each collapse. Per token: a storm's twins are
    /// made and retired inside one read.
    tide: usize,
    /// How many limbs this token has sprouted. The run's work bound: see
    /// `spawns`.
    born: usize,
    /// Per scenario, which verdict group it fell into, or `refuted`. Written by
    /// whatever asked the table, read by `carve` and `keep`.
    mark: std.ArrayList(u32),
    /// The distinct verdicts of the scenarios, in the order first seen.
    verdicts: std.ArrayList(u64),
    /// A row of states being built, one per surviving scenario.
    row: std.ArrayList(u32),
    /// Scratch for rebuilding a roster and a perch under a scenario filter.
    group: std.ArrayList(u32),
    slab: std.ArrayList(u32),
    /// Scratch for `fuse`: which limb each merged scenario's column comes from.
    pick: std.ArrayList(u64),
    /// The distinct effects of the current run, and where they landed.
    yields: std.ArrayList(Yield),
    /// Stack effect so far -> the limb already holding it, rebuilt each token.
    twins: std.AutoHashMapUnmanaged(Twin, u32),
    /// Effect key -> its index in `yields`, plus the states already counted
    /// against it, so `landings` is distinct states rather than limbs.
    seats: std.AutoHashMapUnmanaged(Effect.Key, u32),
    landed: std.AutoHashMapUnmanaged(u64, void),
    /// The configurations one limb has already been in while reading one token.
    /// See `treading`.
    trod: std.AutoHashMapUnmanaged(u64, void),

    /// A scenario the table refused. Not a number a group index can collide
    /// with, because a limb never has four billion scenarios.
    const refuted = std.math.maxInt(u32);

    /// What a limb did to the stack, which is all a limb is for: how far below
    /// the base it reached, and what it left standing above.
    ///
    /// Neither the floor nor the interior claims appear. Both are *sets*, so two
    /// limbs matching on this key are one answer whose floor is the union of
    /// their floors and whose interiors are the union of their interiors — which
    /// is why `fuse` widens rather than refusing. Keying on the exact interior
    /// column instead is correct and unaffordable: it makes a `}` reached through
    /// an object a different limb from a `}` reached through an array at the same
    /// depth, the two never reconverge, and the count doubles per nesting level.
    /// `fed` is here only so the collapse is safe to run *during* a token, when
    /// some limbs have taken the symbol and others have not. Two limbs on
    /// opposite sides of that line are at different points in the read and are
    /// not the same answer yet. At a token boundary every live limb has been
    /// fed, so it partitions nothing.
    const Twin = struct { owed: u64, above: stack.Pool.Id, fed: bool };

    /// What counts as two limbs being the same answer. The two poles of the one
    /// trade this design has left, and a caller measuring the trade needs both.
    pub const Fusion = enum {
        /// Same depth: the interior claims widen to either. Bounded limb count,
        /// at the price of admitting a path that mixes two histories.
        depth,
        /// Same claims, exactly. Nothing is ever admitted that no run performed,
        /// at the price of a limb per interior history.
        exact,
    };

    /// A set of parses that read the same symbols and disagree only about what
    /// was underneath. Limbs exist only because two scenarios can be *told
    /// different things by the table* — not merely because they stand in
    /// different states, which is the common case and costs nothing here.
    const Limb = struct {
        /// The scenarios: every state the segment's floor could be, in the
        /// roster's ascending order. Singleton until a pop reaches below it.
        floor: roster.Id,
        /// Symbols standing above the floor, bottom-to-top. Shared, because
        /// every scenario read the same tokens.
        above: std.ArrayList(press.Symbol),
        /// A `above.len` × `|floor|` matrix in row-major order: `perch[d * w + k]`
        /// is where scenario `k` stands having read `above[0..d + 1]`.
        perch: std.ArrayList(u32),
        /// What has been taken from below the segment's original base: one claim
        /// per symbol, deepest at the bottom. Not the symbols themselves — those
        /// would be this limb's *guess* at what the unseen left had written, and
        /// writing the guess down is what made a run enumerate every hypothetical
        /// prefix instead of tracking the states they lead to. See `effect.zig`.
        ///
        /// **Its deepest slot is always `anywhere`**, because that slot is the
        /// live floor and the live floor is `floor`. Materializing the guard is
        /// one `reseat` at the end; keeping the two apart is what lets `Twin`
        /// fuse limbs that differ only in which floors they still believe.
        owed: ledger.Id,
        dead: bool,
        /// Whether it has consumed the token being read.
        fed: bool,

        const fresh: Limb = .{
            .floor = .nowhere,
            .above = .empty,
            .perch = .empty,
            .owed = .empty,
            .dead = false,
            .fed = false,
        };
    };

    pub fn init(
        gpa: std.mem.Allocator,
        gr: *const press.Grammar,
        c: *const press.Collection,
        t: *const press.Tables,
        rev: *reverse.Reverse,
        pool: *stack.Pool,
        floors: *roster.Pool,
        guards: *ledger.Pool,
    ) Cursor {
        return .{
            .gpa = gpa,
            .gr = gr,
            .c = c,
            .t = t,
            .rev = rev,
            .pool = pool,
            .floors = floors,
            .guards = guards,
            .entry = Effect.nowhere,
            .limbs = .empty,
            .used = 0,
            .alive = 0,
            .tide = tidemark,
            .born = 0,
            .mark = .empty,
            .verdicts = .empty,
            .row = .empty,
            .group = .empty,
            .slab = .empty,
            .pick = .empty,
            .yields = .empty,
            .twins = .empty,
            .seats = .empty,
            .landed = .empty,
            .trod = .empty,
        };
    }

    pub fn deinit(x: *Cursor) void {
        for (x.limbs.items) |*l| {
            l.above.deinit(x.gpa);
            l.perch.deinit(x.gpa);
        }
        x.limbs.deinit(x.gpa);
        x.mark.deinit(x.gpa);
        x.verdicts.deinit(x.gpa);
        x.row.deinit(x.gpa);
        x.group.deinit(x.gpa);
        x.slab.deinit(x.gpa);
        x.pick.deinit(x.gpa);
        x.yields.deinit(x.gpa);
        x.twins.deinit(x.gpa);
        x.seats.deinit(x.gpa);
        x.landed.deinit(x.gpa);
        x.trod.deinit(x.gpa);
        x.* = undefined;
    }

    /// Everything the effects it produces are read against.
    pub fn arena(x: *const Cursor) Arena {
        return .{ .stacks = x.pool, .floors = x.floors, .guards = x.guards, .c = x.c };
    }

    /// Run `terminals` as one segment, entered in `entry`.
    pub fn run(x: *Cursor, entry: u32, terminals: []const press.Symbol) !Outcome {
        x.used = 0;
        x.alive = 0;
        x.entry = entry;
        const first = try x.sprout();
        x.limbs.items[first].floor = try x.floors.one(entry);

        for (terminals, 0..) |sym, i| {
            for (x.limbs.items[0..x.used]) |*l| l.fed = false;
            x.tide = tidemark;
            x.born = 0;
            var j: usize = 0;
            // Not a `for`: feeding a limb can sprout more, and the new ones are
            // standing at this same token, and a rescue moves them all.
            while (j < x.used) {
                if (x.limbs.items[j].dead or x.limbs.items[j].fed) {
                    j += 1;
                    continue;
                }
                switch (try x.feed(j, sym)) {
                    // Collapse on the way up rather than at the ceiling. Twins
                    // are made by the fold storm at a closing bracket, so the
                    // population to search for them in is smallest while the
                    // storm is still small — collapsing every time it doubles
                    // costs a total proportional to the limbs that survive it,
                    // where waiting for the ceiling pays for a search of two
                    // hundred and fifty-six every time it retires sixty.
                    .ok => if (x.alive >= x.tide) {
                        x.tide = @max(tidemark, try x.merge(null) * 2);
                        j = 0;
                    } else {
                        j += 1;
                    },
                    inline else => |s| {
                        // Reaching the ceiling part-way through a token is
                        // usually a count of copies rather than of answers: a
                        // reduce that forks and reconverges leaves twins
                        // standing, and nothing collapses them until asked.
                        // Measured on C, 512 limbs at a `preproc_directive`
                        // were 63 distinct effects wearing 449 duplicates. So
                        // collapse first, and call it a fan only if the
                        // survivors still fill the ceiling.
                        //
                        // Asked as often as it pays, which is the part that took
                        // a while to get right. Once per token is too rare — a
                        // fold storm at a closing bracket refills the ceiling
                        // several times over, and the first collapse only buys
                        // one round of it — and once per fork is what cost C's
                        // survey three hundred times its runtime. The condition
                        // is progress: a collapse that removed a quarter of the
                        // limbs earns another, so the collapses per token are
                        // bounded by a logarithm of the ceiling and each one
                        // pays for itself in the limbs it retired.
                        if (s == .limbs) {
                            var pinned = j;
                            const before = x.alive;
                            const after = try x.merge(&pinned);
                            if (after < x.limbs_max and after * 4 <= before * 3) {
                                // The limb was left holding every scenario it
                                // was about to cut apart, so re-feeding it
                                // redoes the split it did not finish.
                                j = pinned;
                                continue;
                            }
                        }
                        try x.confess(sym);
                        return .{ .fanned = .{
                            .at = @intCast(i),
                            .limbs = @intCast(x.alive),
                            .why = switch (s) {
                                .limbs => .limbs,
                                .floor => .floor,
                                .churn => .churn,
                                .ok => unreachable,
                            },
                        } };
                    },
                }
            }
            if (x.alive == 0) return .{ .rejected = @intCast(i) };
            // Before counting them, collapse the ones that are the same limb.
            // Branches reconverge constantly — two prefixes that differ only in
            // what they already folded reach identical configurations — and a
            // ceiling that counts copies is measuring its own bookkeeping.
            if (try x.merge(null) > x.limbs_max) {
                try x.confess(sym);
                return .{ .fanned = .{
                    .at = @intCast(i),
                    .limbs = @intCast(x.alive),
                    .why = .limbs,
                } };
            }
        }
        return .{ .ran = try x.reap() };
    }

    /// The joint: the same segment entered from every state in `entries`,
    /// summarized. Rung one is a histogram of these.
    pub fn survey(x: *Cursor, entries: []const u32, terminals: []const press.Symbol) !Survey {
        var seen: std.AutoHashMapUnmanaged(Effect.Shape, void) = .empty;
        defer seen.deinit(x.gpa);
        var s: Survey = .{};
        for (entries) |q| switch (try x.run(q, terminals)) {
            .ran => |ys| {
                s.domain += 1;
                if (ys.len > 1) s.plural += 1;
                for (ys) |y| {
                    s.widest = @max(s.widest, y.landings);
                    const slot = try seen.getOrPut(x.gpa, y.effect.shape(x.arena()));
                    if (!slot.found_existing) s.rank += 1;
                }
            },
            .fanned => |f| switch (f.why) {
                .limbs => s.fanned += 1,
                .floor => s.unmoored += 1,
                .churn => s.churned += 1,
            },
            .rejected => s.rejected += 1,
        };
        return s;
    }

    /// Fold every limb doing the same thing to the stack into one, and answer
    /// how many are left.
    ///
    /// Two limbs that owe the same string downward and are standing on the same
    /// symbols *are* one answer — the only thing left between them is which
    /// floors they still believe possible, and that is a set, so the honest
    /// representation is the union. Without this, a split that reconverges
    /// stays split forever and the run grows by a couple of limbs a token; with
    /// it, the limb count is the number of genuinely distinct effects in play,
    /// which is the number the whole design is a bet about.
    /// `pin`, if given, is a limb index the caller is holding across the call:
    /// fusing and packing both move limbs, and a mid-token collapse is only
    /// usable if the caller can still find the limb it was working on.
    fn merge(x: *Cursor, pin: ?*usize) !usize {
        x.twins.clearRetainingCapacity();
        var alive: usize = 0;
        for (0..x.used) |j| {
            if (x.limbs.items[j].dead) continue;
            var above: stack.Pool.Id = .empty;
            for (x.limbs.items[j].above.items) |s| above = try x.pool.push(above, s);
            const owed = x.limbs.items[j].owed;
            const slot = try x.twins.getOrPut(x.gpa, .{
                .owed = switch (x.fusion) {
                    .depth => x.guards.depth(owed),
                    .exact => @intFromEnum(owed),
                },
                .above = above,
                .fed = x.limbs.items[j].fed,
            });
            if (!slot.found_existing) {
                slot.value_ptr.* = @intCast(j);
                alive += 1;
                continue;
            }
            try x.fuse(slot.value_ptr.*, j);
            x.kill(j);
            if (pin) |p| if (p.* == j) {
                p.* = slot.value_ptr.*;
            };
        }

        // Pack the survivors to the front. Without this `used` is a count of
        // every slot the run ever touched, so a segment that forks and reburies
        // its forks a hundred times reads as a hundred live limbs — a ceiling
        // measuring its own bookkeeping, which is the one thing an instrument
        // may not do.
        var to: usize = 0;
        for (0..x.used) |from| {
            if (x.limbs.items[from].dead) continue;
            if (to != from) {
                std.mem.swap(Limb, &x.limbs.items[to], &x.limbs.items[from]);
                if (pin) |p| if (p.* == from) {
                    p.* = to;
                };
            }
            to += 1;
        }
        x.used = to;
        x.alive = to;
        return alive;
    }

    /// Absorb limb `b`'s scenarios into limb `a`. Both stand on the same
    /// symbols, so a floor state they share has the same perch column in both
    /// and the merge is over sorted rosters. The interior claims widen to what
    /// either believed, since the fused limb can no longer say which it was.
    fn fuse(x: *Cursor, a: usize, b: usize) !void {
        const ra = x.floors.members(x.limbs.items[a].floor);
        const rb = x.floors.members(x.limbs.items[b].floor);
        x.group.clearRetainingCapacity();
        x.pick.clearRetainingCapacity();
        var i: usize = 0;
        var k: usize = 0;
        while (i < ra.len or k < rb.len) {
            const from_a = k == rb.len or (i < ra.len and ra[i] <= rb[k]);
            const state = if (from_a) ra[i] else rb[k];
            try x.group.append(x.gpa, state);
            try x.pick.append(x.gpa, (@as(u64, @intFromBool(!from_a)) << 32) | (if (from_a) i else k));
            if (i < ra.len and ra[i] == state) i += 1;
            if (k < rb.len and rb[k] == state) k += 1;
        }

        x.slab.clearRetainingCapacity();
        const depth = x.limbs.items[a].above.items.len;
        for (0..depth) |d| {
            for (x.pick.items) |p| {
                const src = if (p >> 32 == 0) &x.limbs.items[a] else &x.limbs.items[b];
                const w = if (p >> 32 == 0) ra.len else rb.len;
                try x.slab.append(x.gpa, src.perch.items[d * w + @as(u32, @truncate(p))]);
            }
        }

        const widened = switch (x.fusion) {
            .depth => try ledger.join(
                x.guards,
                x.floors,
                x.limbs.items[a].owed,
                x.limbs.items[b].owed,
            ),
            // Keyed on the claims themselves, so there is nothing to widen.
            .exact => x.limbs.items[a].owed,
        };
        const l = &x.limbs.items[a];
        l.floor = try x.floors.of(x.group.items);
        l.owed = widened;
        l.perch.clearRetainingCapacity();
        try l.perch.appendSlice(x.gpa, x.slab.items);
    }

    /// Every surviving limb, spelled out. Only a debug aid, and only worth
    /// having because "256 ways" is not a diagnosis.
    ///
    /// Two ways to ask, one gate, and it lives here rather than at the call
    /// sites so the two of them cannot come to disagree about what turns this
    /// on: `--confess` is a caller who wants it for this run, `JOINTS_TRACE=
    /// joint` is the ambient way in for an embedder with no argv to set. The
    /// lines go through assay's channel rather than straight to stderr, so a
    /// host that scoped a dark sink stays quiet even here.
    fn confess(x: *Cursor, sym: press.Symbol) !void {
        if (!x.confessing and !assay.lit(.joint)) return;
        assay.diag("  ceiling on {s}, {d} limbs:\n", .{ x.gr.nameOf(sym), x.used });
        for (0..x.used) |j| {
            if (x.limbs.items[j].dead) continue;
            const l = &x.limbs.items[j];
            assay.diag("    floor x{d}  -{d} +[", .{ x.width(j), x.guards.depth(l.owed) });
            for (l.above.items, 0..) |s, n| {
                if (n != 0) assay.diag(" ", .{});
                assay.diag("{s}", .{x.gr.nameOf(s)});
            }
            assay.diag("]\n", .{});
        }
    }

    /// Refute limb `j`. The one way a limb dies, so `alive` cannot drift.
    fn kill(x: *Cursor, j: usize) void {
        if (x.limbs.items[j].dead) return;
        x.limbs.items[j].dead = true;
        x.alive -= 1;
    }

    /// A limb, reusing a spent one's buffers when there is one.
    fn sprout(x: *Cursor) !usize {
        if (x.used == x.limbs.items.len) try x.limbs.append(x.gpa, .fresh);
        const at = x.used;
        x.used += 1;
        x.alive += 1;
        x.born += 1;
        const l = &x.limbs.items[at];
        l.above.clearRetainingCapacity();
        l.perch.clearRetainingCapacity();
        l.floor = .nowhere;
        l.owed = .empty;
        l.dead = false;
        l.fed = false;
        return at;
    }

    /// What a limb's turn came to. The two failures are named apart because
    /// they are fixed apart: see `Fork.why`.
    const Step = enum { ok, limbs, floor, churn };

    /// How many scenarios limb `j` is carrying.
    fn width(x: *const Cursor, j: usize) u32 {
        return x.floors.size(x.limbs.items[j].floor);
    }

    /// Where scenario `k` of limb `j` stands.
    fn top(x: *const Cursor, j: usize, k: u32) u32 {
        const l = &x.limbs.items[j];
        if (l.above.items.len == 0) return x.floors.members(l.floor)[k];
        return l.perch.items[l.perch.items.len - x.width(j) + k];
    }

    /// Run limb `j` until it has shifted `sym`, died, or split.
    fn feed(x: *Cursor, j: usize, sym: press.Symbol) !Step {
        x.trod.clearRetainingCapacity();
        while (true) {
            if (try x.treading(j)) {
                x.kill(j);
                return .ok;
            }
            // One question per scenario, and then only *what it was told to
            // do* is compared. A scenario the table refuses is not a dead limb,
            // it is a refuted hypothesis about the unseen left: it leaves the
            // roster and the others carry on without it.
            const w = x.width(j);
            x.mark.clearRetainingCapacity();
            x.verdicts.clearRetainingCapacity();
            var live: u32 = 0;
            for (0..w) |k| {
                const act = x.t.at(x.top(j, @intCast(k)), sym);
                if (act.kind == .err) {
                    try x.mark.append(x.gpa, refuted);
                    continue;
                }
                try x.mark.append(x.gpa, try x.enrol(verdict(act)));
                live += 1;
            }
            if (live == 0) {
                x.kill(j);
                return .ok;
            }
            if (x.verdicts.items.len > 1) switch (try x.split(j)) {
                .ok => {},
                else => |s| return s,
            };
            if (x.verdicts.items.len > 1 or live != w) try x.keep(j, 0);

            const act = x.t.at(x.top(j, 0), sym);
            switch (act.kind) {
                .err => unreachable, // a refuted scenario is gone by now
                .shift => {
                    x.row.clearRetainingCapacity();
                    for (0..x.width(j)) |k| {
                        try x.row.append(x.gpa, x.t.at(x.top(j, @intCast(k)), sym).value);
                    }
                    const l = &x.limbs.items[j];
                    try l.above.append(x.gpa, sym);
                    try l.perch.appendSlice(x.gpa, x.row.items);
                    l.fed = true;
                    return .ok;
                },
                // Only ever in the end-of-input column, which a token stream
                // cannot name. Reachable if a caller hands one over anyway, and
                // the answer is the same: this limb is done reading.
                .accept => {
                    x.limbs.items[j].fed = true;
                    return .ok;
                },
                .reduce => switch (try x.fold(j, act.value)) {
                    .ok => {},
                    else => |s| return s,
                },
            }
        }
    }

    /// Whether limb `j` is standing exactly where it already stood while reading
    /// this token — in which case it will never read it.
    ///
    /// A fold that takes as much as it gives back leaves the stack the length it
    /// was: `A -> B` pops one and pushes one, so a grammar where `A` derives `B`
    /// derives `A` walks a limb in a circle, and an epsilon rule whose goto
    /// returns to the state that asked for it does the same. Neither is exotic
    /// once a table is built from an imported grammar: a hidden rule inlined into
    /// its own alternative is a cycle, and a merge artifact that answers a token
    /// with the wrong fold can close one that the grammar never had. Python spun
    /// here for minutes on a four-token file.
    ///
    /// This is not a ceiling. Between two visits to the same configuration a limb
    /// consumed nothing, and everything a limb does next is a function of the
    /// configuration it is in and the token it is reading — so the second visit
    /// proves the loop is closed, and the limb is refuted rather than given up
    /// on. What identifies the configuration is what that function reads: the
    /// floor roster, the debt below it, and the symbols and states standing above.
    fn treading(x: *Cursor, j: usize) !bool {
        const l = &x.limbs.items[j];
        var h = std.hash.Wyhash.init(@intFromEnum(l.floor));
        h.update(std.mem.asBytes(&l.owed));
        h.update(std.mem.sliceAsBytes(l.above.items));
        h.update(std.mem.sliceAsBytes(l.perch.items));
        return (try x.trod.getOrPut(x.gpa, h.final())).found_existing;
    }

    /// What the table said to do, with the part that is not a disagreement
    /// thrown away. Two scenarios told to shift are told the same thing even
    /// when they shift into different states — the symbol stack is what a limb
    /// is, and they both push `sym` onto it.
    fn verdict(act: press.Action) u64 {
        const tag: u64 = @intFromEnum(act.kind);
        return (tag << 32) | if (act.kind == .reduce) act.value else 0;
    }

    /// The group index of `v`, adding it if this is the first scenario to say
    /// it. Linear because a cell with three distinct verdicts is a grammar
    /// nobody has written.
    fn enrol(x: *Cursor, v: u64) !u32 {
        for (x.verdicts.items, 0..) |seen, i| if (seen == v) return @intCast(i);
        try x.verdicts.append(x.gpa, v);
        return @intCast(x.verdicts.items.len - 1);
    }

    /// Cut every verdict group but the first onto a limb of its own. The
    /// genuine fork, and the only one left: these scenarios were about to do
    /// different things to the stack.
    fn split(x: *Cursor, j: usize) !Step {
        for (1..x.verdicts.items.len) |group| {
            if (x.born >= x.born_max) return .churn;
            if (x.alive >= x.limbs_max) return .limbs;
            const k = try x.sprout();
            const src = &x.limbs.items[j];
            x.group.clearRetainingCapacity();
            x.slab.clearRetainingCapacity();
            try x.gather(src, @intCast(group));
            const dst = &x.limbs.items[k];
            dst.floor = try x.floors.of(x.group.items);
            dst.owed = src.owed;
            try dst.above.appendSlice(x.gpa, src.above.items);
            try dst.perch.appendSlice(x.gpa, x.slab.items);
        }
        return .ok;
    }

    /// Drop every scenario `x.mark` did not put in `group`.
    fn keep(x: *Cursor, j: usize, group: u32) !void {
        x.group.clearRetainingCapacity();
        x.slab.clearRetainingCapacity();
        try x.gather(&x.limbs.items[j], group);
        const l = &x.limbs.items[j];
        l.floor = try x.floors.of(x.group.items);
        l.perch.clearRetainingCapacity();
        try l.perch.appendSlice(x.gpa, x.slab.items);
    }

    /// The floor members and perch columns of one verdict group, into the
    /// scratch buffers. Both callers need exactly this and neither can do it
    /// while holding a live pointer into `limbs`.
    fn gather(x: *Cursor, l: *const Limb, group: u32) !void {
        const all = x.floors.members(l.floor);
        for (x.mark.items, 0..) |m, k| {
            if (m == group) try x.group.append(x.gpa, all[k]);
        }
        const w: usize = all.len;
        for (0..l.above.items.len) |d| {
            for (x.mark.items, 0..) |m, k| {
                if (m == group) try x.slab.append(x.gpa, l.perch.items[d * w + k]);
            }
        }
    }

    /// Apply one reduction to limb `j`. A pop that runs out of segment replaces
    /// the floor with every state the missing symbols could have come from —
    /// all of them in one limb, since they all owe the same string downward.
    fn fold(x: *Cursor, j: usize, prod: u32) !Step {
        const p = x.gr.productions[prod];
        const have = x.limbs.items[j].above.items.len;
        if (p.rhs.len <= have) {
            // The row that was under the popped symbols is already sitting in
            // the matrix; shortening it is the whole pop.
            const w = x.width(j);
            const l = &x.limbs.items[j];
            l.above.shrinkRetainingCapacity(have - p.rhs.len);
            l.perch.shrinkRetainingCapacity(l.above.items.len * w);
            return x.raise(j, p.lhs);
        }

        // The pop runs out of segment. What it removed below is known *here* —
        // the bottom of this right-hand side — so the floor becomes wherever
        // that string could have been walked from, every scenario at once. The
        // scenarios are replaced rather than narrowed: they were claims about
        // what stood under the old base, and the base has moved.
        //
        // The symbols are spent on the rewind and then dropped, which is the one
        // asymmetry worth reading twice. They are trustworthy for *this* step,
        // because within a scenario the production is decided. They are not
        // trustworthy as a record, because whether this scenario is the real one
        // is exactly what is unknown — so the states they lead to are kept and
        // the string that led there is not.
        //
        // Every depth, both halves, and that was learned the hard way. What the
        // pop *took* is `p.rhs[0..below]`, spelled out, and the left neighbour
        // pushed those symbols so it can check them exactly — that is what tells
        // two runs apart when they assumed different strings. What the pop
        // *consulted* is a state per depth, and that is what tells two runs apart
        // when they split on different table actions. Recording only the far end
        // leaves both blank in between, and blanks are what a wrong scenario
        // escapes through.
        //
        // The old floor stops being live here and becomes a claim about an
        // interior depth, so it is seated into the ledger on the way past.
        const below = p.rhs.len - have;
        const older = try ledger.seat(
            x.guards,
            x.limbs.items[j].owed,
            x.limbs.items[j].floor,
        );
        const trail = switch (try x.rev.rewind(
            x.floors.members(x.limbs.items[j].floor),
            p.rhs[0..below],
        )) {
            .exposed => |t| t,
            // A rewind wider than the ceiling is the same answer as too many
            // limbs, arrived at one step earlier.
            .fanned => return .floor,
            .impossible => {
                x.kill(j);
                return .ok;
            },
        };

        // `rhs[i]` stands at depth `below - i`, so the loop builds bottom-up and
        // the deepest slot's states are left blank: that slot is the new live
        // floor, and the ledger's invariant is that the live floor lives in
        // `floor` until something seats it.
        var owed: ledger.Id = .empty;
        for (p.rhs[0..below], 0..) |sym, i| {
            const d: u32 = @intCast(below - i);
            owed = try x.guards.push(owed, .{
                .states = if (i == 0) ledger.anywhere else try x.floors.of(trail.at(d)),
                .symbols = try x.floors.one(sym),
            });
        }

        const l = &x.limbs.items[j];
        l.floor = try x.floors.of(trail.floor());
        l.owed = try x.guards.concat(owed, older);
        l.above.clearRetainingCapacity();
        l.perch.clearRetainingCapacity();
        return x.raise(j, p.lhs);
    }

    /// Take the goto over the reduced nonterminal, once per scenario. Nothing
    /// splits here any more: a scenario with no goto is refuted and leaves, and
    /// the rest disagreeing about *where* they land is the whole reason `perch`
    /// has a column each.
    fn raise(x: *Cursor, j: usize, lhs: press.Symbol) !Step {
        const w = x.width(j);
        x.mark.clearRetainingCapacity();
        x.row.clearRetainingCapacity();
        for (0..w) |k| {
            if (x.c.goto(x.top(j, @intCast(k)), lhs)) |to| {
                try x.mark.append(x.gpa, 0);
                try x.row.append(x.gpa, to);
            } else try x.mark.append(x.gpa, refuted);
        }
        if (x.row.items.len == 0) {
            x.kill(j);
            return .ok;
        }
        // `keep` reuses `row`'s siblings, never `row` itself.
        if (x.row.items.len != w) try x.keep(j, 0);
        const l = &x.limbs.items[j];
        try l.above.append(x.gpa, lhs);
        try l.perch.appendSlice(x.gpa, x.row.items);
        return .ok;
    }

    /// The distinct effects the surviving limbs arrived at.
    fn reap(x: *Cursor) ![]const Yield {
        x.yields.clearRetainingCapacity();
        x.seats.clearRetainingCapacity();
        x.landed.clearRetainingCapacity();
        for (0..x.used) |j| {
            if (x.limbs.items[j].dead) continue;
            const l = &x.limbs.items[j];
            var id: stack.Pool.Id = .empty;
            for (l.above.items) |s| id = try x.pool.push(id, s);
            // The live floor is folded into the ledger here and nowhere earlier:
            // it is the claim about what stood under the pop, and it goes on
            // narrowing right up to the last token.
            const e: Effect = .{
                .entry = x.entry,
                .guard = try ledger.seat(x.guards, l.owed, l.floor),
                .push = id,
            };
            const seat = try x.seats.getOrPut(x.gpa, e.key());
            if (!seat.found_existing) {
                seat.value_ptr.* = @intCast(x.yields.items.len);
                try x.yields.append(x.gpa, .{ .effect = e, .landings = 0 });
            }
            // Two scenarios standing in the same state having done the same
            // thing are one answer, however they got there.
            for (0..x.width(j)) |k| {
                const both = (@as(u64, seat.value_ptr.*) << 32) | x.top(j, @intCast(k));
                if ((try x.landed.getOrPut(x.gpa, both)).found_existing) continue;
                x.yields.items[seat.value_ptr.*].landings += 1;
            }
        }
        return x.yields.items;
    }
};

/// One segment's joint, counted. `rank` is the number the design lives on.
pub const Survey = struct {
    /// Distinct *shapes* over every entry state and every limb — what the
    /// segment did to the stack, with the floor guard left out. A joint of rank
    /// one is a segment whose answer does not depend on its left context at all.
    rank: u32 = 0,
    /// Entry states that produced an effect at all.
    domain: u32 = 0,
    /// Entry states that produced more than one — where the segment's effect
    /// depends on a left context it cannot see.
    plural: u32 = 0,
    /// Entry states carrying more parses at once than `limb_ceiling` allows.
    fanned: u32 = 0,
    /// Entry states that ran out of `reverse.fan_ceiling` instead: one parse,
    /// too many places it could have started. A different complaint and a
    /// different fix, so a different column.
    unmoored: u32 = 0,
    /// Entry states that outran neither, and instead sprouted and buried more
    /// limbs on one token than `spawns` allows. Never wide, only busy.
    churned: u32 = 0,
    rejected: u32 = 0,
    /// The largest landing set any effect reported.
    widest: u32 = 0,
};

const testing = std.testing;

/// Everything a cursor borrows, kept alive together. Heap-allocated because the
/// cursor holds pointers into it and a struct that moves would dangle them.
const Fixture = struct {
    gpa: std.mem.Allocator,
    gr: press.Grammar,
    built: press.Result,
    rev: reverse.Reverse,
    pool: stack.Pool,
    floors: roster.Pool,
    guards: ledger.Pool,
    cur: Cursor,

    /// Takes ownership of `gr`.
    fn wrap(gpa: std.mem.Allocator, gr: press.Grammar) !*Fixture {
        const f = try gpa.create(Fixture);
        f.gpa = gpa;
        f.gr = gr;
        f.built = try press.tables(gpa, &f.gr);
        f.rev = try reverse.Reverse.build(gpa, &f.gr, &f.built.collection, &f.built.tables);
        f.pool = stack.Pool.init(gpa);
        f.floors = roster.Pool.init(gpa);
        f.guards = ledger.Pool.init(gpa);
        f.cur = Cursor.init(gpa, &f.gr, &f.built.collection, &f.built.tables, &f.rev, &f.pool, &f.floors, &f.guards);
        return f;
    }

    fn deinit(f: *Fixture) void {
        const gpa = f.gpa;
        f.cur.deinit();
        f.guards.deinit();
        f.floors.deinit();
        f.pool.deinit();
        f.rev.deinit();
        f.built.deinit();
        f.gr.deinit();
        gpa.destroy(f);
    }

    fn arena(f: *Fixture) effect.Arena {
        return f.cur.arena();
    }

    fn every(f: *Fixture, buf: []u32) []const u32 {
        for (0..f.built.collection.states.len) |i| buf[i] = @intCast(i);
        return buf[0..f.built.collection.states.len];
    }
};

/// `E -> E + E | E * E | ( E ) | id`, precedence-resolved. Ambiguous on paper
/// and deterministic in the table, which is the shape every real grammar has.
const Expr = struct {
    plus: press.Symbol = 0,
    star: press.Symbol = 1,
    lp: press.Symbol = 2,
    rp: press.Symbol = 3,
    id: press.Symbol = 4,
    e: press.Symbol = undefined,
    f: *Fixture = undefined,

    fn init(gpa: std.mem.Allocator) !Expr {
        var b = press.Builder.init(gpa);
        defer b.deinit();
        const plus = try b.intern("+", "+", .{ .literal = "+" });
        const star = try b.intern("*", "*", .{ .literal = "*" });
        const lp = try b.intern("(", "(", .{ .literal = "(" });
        const rp = try b.intern(")", ")", .{ .literal = ")" });
        const id = try b.intern("id", "id", .{ .regex = "[a-z]+" });
        const start = try b.intern("$start", "$start", null);
        const e = try b.intern("E", "E", null);
        try b.addProduction(start, &.{e}, &.{});
        try b.addProduction(e, &.{ e, plus, e }, &.{ .{ .prec = .{ .level = 1 }, .assoc = .left }, .{ .prec = .{ .level = 1 }, .assoc = .left }, .{ .prec = .{ .level = 1 }, .assoc = .left } });
        try b.addProduction(e, &.{ e, star, e }, &.{ .{ .prec = .{ .level = 2 }, .assoc = .left }, .{ .prec = .{ .level = 2 }, .assoc = .left }, .{ .prec = .{ .level = 2 }, .assoc = .left } });
        try b.addProduction(e, &.{ lp, e, rp }, &.{});
        try b.addProduction(e, &.{id}, &.{});
        const gr = try b.finish("expr", start, &.{}, &.{});
        const nonterminal_e = gr.start + 1;
        return .{ .e = nonterminal_e, .f = try Fixture.wrap(gpa, gr) };
    }

    fn deinit(x: *Expr) void {
        x.f.deinit();
    }
};

test "a segment entered where it really began pushes exactly what it read" {
    var x = try Expr.init(testing.allocator);
    defer x.deinit();

    // `+ id` after an E: two shifts, nothing folded, nothing owed downward.
    // The trailing reduce belongs to whichever token comes next, which is the
    // segment boundary being honest about where it stops.
    const after_e = x.f.built.collection.goto(0, x.e).?;
    const one = try only(&x.f.cur, after_e, &.{ x.plus, x.id });
    try testing.expectEqual(@as(u32, 0), one.effect.reaches(x.f.arena()));
    var buf: [4]press.Symbol = undefined;
    try testing.expectEqualSlices(press.Symbol, &.{ x.plus, x.id }, x.f.pool.read(one.effect.push, &buf));
}

test "a fold longer than the segment charges the difference to whoever comes before" {
    var x = try Expr.init(testing.allocator);
    defer x.deinit();

    // `+ id +`: the third token forces `E -> E + E`, whose left `E` is below
    // this segment entirely. The effect says so — pop one, and what is left
    // standing is the folded `E` and the operator after it.
    const after_e = x.f.built.collection.goto(0, x.e).?;
    const one = try only(&x.f.cur, after_e, &.{ x.plus, x.id, x.plus });
    try testing.expectEqual(@as(u32, 1), one.effect.reaches(x.f.arena()));
    var buf: [4]press.Symbol = undefined;
    try testing.expectEqualSlices(press.Symbol, &.{ x.e, x.plus }, x.f.pool.read(one.effect.push, &buf));
}

test "the effect is the same however the segment is cut" {
    var x = try Expr.init(testing.allocator);
    defer x.deinit();

    // The claim, run against a table: parse `( id + id * id )` from the start
    // state, then cut it in two at every position and compose the halves. The
    // second half is entered where the first one landed, which is what the
    // monoid says composition means.
    const whole_tokens = [_]press.Symbol{ x.lp, x.id, x.plus, x.id, x.star, x.id, x.rp };
    const whole = (try only(&x.f.cur, 0, &whole_tokens)).effect;

    var cuts: u32 = 0;
    for (1..whole_tokens.len) |cut| {
        const left = try only(&x.f.cur, 0, whole_tokens[0..cut]);
        if (left.landings != 1) continue;
        const landed = x.f.cur.top(0, 0);
        // The right half of a real cut is entered where the left half really
        // landed, so it is allowed to be plural only when the cut fell
        // somewhere the left context still matters — and then it is not this
        // claim's business. Composition is checked on the singleton answers.
        const right = switch (try x.f.cur.run(landed, whole_tokens[cut..])) {
            .ran => |ys| if (ys.len == 1) ys[0] else continue,
            else => continue,
        };
        cuts += 1;
        const joined = (try effect.compose(x.f.arena(), left.effect, right.effect)).?;
        try testing.expect(Effect.eql(whole, joined));
    }
    // Not a vacuous pass. The cuts that do not compose are the ones landing
    // mid-operand, where the right half cannot say what the left half meant —
    // pinned by the test below rather than skipped silently here.
    try testing.expect(cuts > 0);
}

test "a limb walking a grammar's cycle is refuted rather than walked forever" {
    // `A -> B` and `B -> A`, both live, so a fold that takes one symbol and gives
    // one back can be answered by the fold that undoes it. The table is built
    // from it without complaint — a cycle is a reduce/reduce contest only where
    // both folds are legal on the same token, and here they never are — so the
    // only thing standing between a survey and a spin is the cursor.
    var b = press.Builder.init(testing.allocator);
    defer b.deinit();
    const w = try b.intern("w", "w", .{ .literal = "w" });
    const z = try b.intern("z", "z", .{ .literal = "z" });
    const start = try b.intern("$start", "$start", null);
    const s = try b.intern("S", "S", null);
    const a = try b.intern("A", "A", null);
    const q = try b.intern("B", "B", null);
    try b.addProduction(start, &.{s}, &.{});
    try b.addProduction(s, &.{ a, z }, &.{});
    try b.addProduction(a, &.{q}, &.{});
    try b.addProduction(q, &.{a}, &.{});
    try b.addProduction(q, &.{w}, &.{});
    const f = try Fixture.wrap(testing.allocator, try b.finish("cyclic", start, &.{}, &.{}));
    defer f.deinit();

    // Every state, so the hypothetical entries — the ones a real parse never
    // stands in, and the only ones that can enter the cycle — are all included.
    var buf: [64]u32 = undefined;
    const every = f.every(&buf);
    const one = try f.cur.survey(every, &.{w});
    try testing.expect(one.domain > 0);
    // The token after the cycle: reachable only through it, from any entry that
    // has an `A` or a `B` underneath.
    const two = try f.cur.survey(every, &.{z});
    try testing.expect(two.domain > 0);
    // Nothing was given up on. A limb that came back to where it started is a
    // closed loop, which is a refutation, so the capacity counters stay at zero.
    for ([_]Survey{ one, two }) |x| {
        try testing.expectEqual(@as(u32, 0), x.fanned);
        try testing.expectEqual(@as(u32, 0), x.unmoored);
        try testing.expectEqual(x.domain + x.rejected, @as(u32, @intCast(every.len)));
    }
}

test "an empty cell refutes an entry state instead of guessing past it" {
    var x = try Expr.init(testing.allocator);
    defer x.deinit();

    // Most states cannot have preceded `+ id +` at all, and the table says so
    // by having nothing in the cell. A refutation is not a failure — it is how
    // the joint's domain gets small enough to be worth tabulating.
    var buf: [16]u32 = undefined;
    const s = try x.f.cur.survey(x.f.every(&buf), &.{ x.plus, x.id, x.plus });
    try testing.expect(s.rejected > 0);
    try testing.expect(s.domain > 0);
    try testing.expectEqual(s.domain + s.rejected + s.fanned, @as(u32, @intCast(x.f.built.collection.states.len)));
}

test "a segment that stays above its own base is rank one, however it was entered" {
    var x = try Expr.init(testing.allocator);
    defer x.deinit();

    // Rung one in miniature, and the sharpest form of the claim: a segment that
    // never pops through its own floor cannot be asking about the prefix, so
    // every entry state that admits it at all does the identical thing. Two
    // dozen states, one effect, and a pop of zero — which is also the condition
    // that lets it compose with anything on its left without consulting it.
    var buf: [16]u32 = undefined;
    const every = x.f.every(&buf);
    for ([_][]const press.Symbol{
        &.{ x.lp, x.id, x.rp },
        &.{ x.lp, x.lp, x.id, x.rp, x.rp },
        &.{ x.lp, x.id, x.plus, x.id, x.rp },
    }) |segment| {
        const s = try x.f.cur.survey(every, segment);
        try testing.expect(s.domain > 0);
        try testing.expectEqual(@as(u32, 1), s.rank);
        try testing.expectEqual(@as(u32, 0), s.plural);
        try testing.expectEqual(@as(u32, 1), s.widest);
    }
}

test "a segment that reaches below its base is multi-valued, and every value owes" {
    var x = try Expr.init(testing.allocator);
    defer x.deinit();

    // The complement, and the thing the instrument has to count rather than
    // hide: cut a file mid-operand and the segment's effect genuinely depends on
    // how much of the expression to its left is still unfolded. Each value owes a
    // different depth downward, and carrying what it assumed at each of those
    // depths is what lets the left neighbour pick the one that was true.
    var buf: [16]u32 = undefined;
    const s = try x.f.cur.survey(x.f.every(&buf), &.{ x.plus, x.id, x.plus });
    try testing.expect(s.rank > 1);
    try testing.expect(s.plural > 0);
    try testing.expectEqual(@as(u32, 0), s.fanned);
}

/// The one effect a segment had, failing the test if it had any other number.
/// Most claims here are about the singleton case, and unwrapping it by hand
/// each time reads as ceremony rather than as the claim.
fn only(x: *Cursor, entry: u32, terminals: []const press.Symbol) !Yield {
    const out = try x.run(entry, terminals);
    if (out != .ran or out.ran.len != 1) return error.NotSingleValued;
    return out.ran[0];
}

test "a segment beginning mid-operand is many-valued, and the neighbour picks one" {
    var x = try Expr.init(testing.allocator);
    defer x.deinit();

    // Entered right after an `id` that has not been folded yet. The first token
    // folds `E -> id`, popping a symbol the segment never pushed, so the run
    // branches over every state that `id` could have been read from — and they
    // do not agree about how much went below. Under `( id`, only the `id` did;
    // under `a + id` the sum folds first, so three did; under `a + b * id`
    // both fold, innermost first, and five did.
    //
    // Every answer is true of some file, which is the finding: the effect of
    // this segment is a function of a left context it cannot see. Borrowed
    // effects die at the next run, so they are copied before anything else
    // touches the cursor.
    const after_id = x.f.built.collection.goto(0, x.id).?;
    var ran: std.ArrayList(Yield) = .empty;
    defer ran.deinit(testing.allocator);
    switch (try x.f.cur.run(after_id, &.{ x.plus, x.id })) {
        .ran => |ys| try ran.appendSlice(testing.allocator, ys),
        else => return error.NotRan,
    }
    var buf: [8]press.Symbol = undefined;
    for (ran.items) |y| {
        try testing.expectEqualSlices(press.Symbol, &.{ x.e, x.plus, x.id }, x.f.pool.read(y.effect.push, &buf));
    }

    // One answer per depth, and the reason it is not one per interior history is
    // the trade the cursor makes deliberately. `a + b` folds a sum where `a * b`
    // folds a product; both take three symbols but were standing in different
    // places when they took the first, so they make different claims at that
    // interior depth. Kept apart they are two elements, and on a real file that
    // distinction compounds — a `}` reached through an object differs from one
    // reached through an array, forever, and the limb count doubles per level.
    // So limbs fuse on depth and the interior claims widen to either: still
    // sound, still associative, and the *deepest* claim — the one the neighbour
    // below actually consults — stays exact, which is what the next paragraph
    // proves. What none of them do is name the symbols they took, which is what
    // once made every hypothesis about the unseen left its own element and turned
    // 68 configurations into 1024 on four levels of nesting.
    try testing.expectEqual(@as(usize, 3), ran.items.len);
    for ([_]u32{ 1, 3, 5 }) |depth| {
        var found = false;
        for (ran.items) |y| found = found or y.effect.reaches(x.f.arena()) == depth;
        try testing.expect(found);
    }

    // And the payoff. Put a real left neighbour in front of it — `( a`, which
    // lands exactly where this segment was entered — and exactly one of the three
    // survives. The others describe prefixes that did not happen: they reach
    // deeper than `( a` is tall, and `( a` begins the file, so there is nothing
    // beneath it to have taken. That is the guard and the boundary between them
    // doing the work a fork would otherwise have to do.
    const left = try only(&x.f.cur, 0, &.{ x.lp, x.id });
    var fits: u32 = 0;
    var picked: Effect = undefined;
    for (ran.items) |y| {
        const joined = try effect.compose(x.f.arena(), left.effect, y.effect) orelse continue;
        if (!joined.grounded(x.f.arena())) continue;
        fits += 1;
        picked = y.effect;
    }
    try testing.expectEqual(@as(u32, 1), fits);
    try testing.expectEqual(@as(u32, 1), picked.reaches(x.f.arena()));

    // The same three tokens with the `id` inside the segment rather than behind
    // it never reaches below its own base at all, so nothing branches and the
    // pop is empty. Same push, different debt: the cut decides who owes it.
    const held = try only(&x.f.cur, 0, &.{ x.id, x.plus, x.id });
    try testing.expectEqual(@as(u32, 0), held.effect.reaches(x.f.arena()));
    try testing.expectEqualSlices(press.Symbol, &.{ x.e, x.plus, x.id }, x.f.pool.read(held.effect.push, &buf));
}
