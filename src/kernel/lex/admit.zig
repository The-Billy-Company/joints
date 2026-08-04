//! What the scan is allowed to consider, cut the two ways that are not "does
//! this pattern match".
//!
//! A slate answers one question — longest anchored match — and two facts about
//! a grammar sit outside that question entirely. **Lexical precedence** says a
//! terminal the author ranked up takes the token even when a lower one reaches
//! further, so the slate is cut into tiers and asked strongest-first.
//! **Immediacy** says a terminal may only begin where the last token ended, so
//! each tier is cut again into what may start here and what may start after an
//! extra moved past. Both cuts are `Munch.Allow` sets, which is why they live
//! in one file: the same bisection that narrows a walk narrows it for either
//! reason, and irregex only has to know it was narrowed.
//!
//! A parse state's permission set mirrors that shape rather than paralleling
//! it. `Expected` is one `Tier` per `Rank`, refilled per token from the LALR
//! row, and the restriction rides the walk instead of filtering its answer —
//! filtering afterward recovers nothing, because the long illegal match has
//! already suppressed every short legal one behind it.

const std = @import("std");
const irregex = @import("irregex");
const g = @import("../../press/grammar.zig");
const Scanner = @import("scanner.zig").Scanner;
const Munch = irregex.regex_munch.Munch;

/// One precedence tier: every terminal of that rank, and the same set without
/// the immediate ones for a position an extra already moved past.
pub const Rank = struct {
    prec: i32,
    all: Munch.Allow,
    after: Munch.Allow,

    pub fn deinit(r: *Rank, gpa: std.mem.Allocator) void {
        r.all.deinit(gpa);
        r.after.deinit(gpa);
    }
};

/// The terminals a parse state will accept, in the grammar's own numbering.
///
/// Reused across tokens: a parser refills one of these per state rather than
/// allocating a set per token. Extras are admitted automatically, so a caller
/// declares what its *grammar* allows and never has to remember that whitespace
/// is also a terminal.
pub const Expected = struct {
    tiers: []Tier,

    pub const Tier = struct {
        here: Munch.Allow,
        later: Munch.Allow,
        /// Whether anything at all was admitted. A state usually accepts a
        /// handful of terminals out of one tier, and an empty tier is a walk
        /// whose answer is known.
        live_here: bool = false,
        live_later: bool = false,
    };

    /// A permission set sized to this scanner, holding only its extras.
    pub fn of(s: *const Scanner, gpa: std.mem.Allocator) !Expected {
        const tiers = try gpa.alloc(Tier, s.ranks.len);
        errdefer gpa.free(tiers);
        for (tiers, 0..) |*t, i| {
            errdefer for (tiers[0..i]) |*done| {
                done.here.deinit(gpa);
                done.later.deinit(gpa);
            };
            t.* = .{
                .here = try s.munch.allowNone(gpa),
                .later = try s.munch.allowNone(gpa),
            };
        }
        var e: Expected = .{ .tiers = tiers };
        e.clear(s);
        return e;
    }

    pub fn deinit(e: *Expected, gpa: std.mem.Allocator) void {
        for (e.tiers) |*t| {
            t.here.deinit(gpa);
            t.later.deinit(gpa);
        }
        gpa.free(e.tiers);
        e.* = undefined;
    }

    pub fn clear(e: *Expected, s: *const Scanner) void {
        for (e.tiers) |*t| {
            t.here.forbidAll();
            t.later.forbidAll();
            t.live_here = false;
            t.live_later = false;
        }
        var it = s.skipped.iterator(.{});
        while (it.next()) |i| e.admit(s, @intCast(i));
    }

    pub fn admit(e: *Expected, s: *const Scanner, sym: g.Symbol) void {
        if (sym >= s.seat.len) return;
        const ordinal = s.seat[sym];
        if (ordinal == Scanner.no_seat) return;
        const t = &e.tiers[s.tier[sym]];
        t.here.admit(&s.munch, ordinal);
        t.live_here = true;
        if (!s.immediate.isSet(sym)) {
            t.later.admit(&s.munch, ordinal);
            t.live_later = true;
        }
    }
};
