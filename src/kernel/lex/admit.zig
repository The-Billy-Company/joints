//! What the scan is allowed to consider, cut the two ways that are not "does
//! this pattern match".
//!
//! A slate answers one question - longest anchored match - and two facts about
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
//! row, and the restriction rides the walk instead of filtering its answer -
//! filtering afterward recovers nothing, because the long illegal match has
//! already suppressed every short legal one behind it.

const std = @import("std");
const irregex = @import("irregex");
const Scanner = @import("scanner.zig").Scanner;
const press = @import("../../press/press.zig");
const Munch = irregex.Munch;

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
    /// Every terminal the state admitted, seated or not.
    ///
    /// The tiers can only carry a terminal the slate has a pattern for, and a
    /// terminal produced by a hand-written scanner has none by definition. So
    /// the same admissions are also recorded flat, which is the `valid_symbols`
    /// array tree-sitter hands its external scanners - and the whole reason
    /// those scanners are written in C is that they need to read it.
    ///
    /// # Which half of the row this is, which depends on who filled it
    ///
    /// An LR row has two halves - shifts, where the state consumes the token,
    /// and reduce-lookaheads, where it only folds - and **the two walks fill
    /// this field with different ones**:
    ///
    ///   * `drive.offer` admits every terminal with any non-error action, so
    ///     `wanted` is the **union**. That is tree-sitter's `valid_symbols`
    ///     exactly, and it is what an oracle run hands a hand.
    ///   * `Gather.offer` admits `shiftable(top, sym)`: it *runs* the folds the
    ///     table names, down the stack actually standing, and asks whether a
    ///     shift is on the other side. So `wanted` is the **shift-reachable**
    ///     set - narrower than the union, and computed against this reading
    ///     rather than against the state in the abstract.
    ///
    /// Neither is wrong and the difference is not cosmetic. `_immediate_paren`
    /// is a shift in 20 of julia's states and a reduce-lookahead in 239, so a
    /// hand reading this field sees a set that differs by an order of magnitude
    /// depending on which walk asked it. The product parse is `Gather`'s, and
    /// the narrower answer is why julia's zero-width markers can read `wanted`
    /// at all without firing in the 239: by the time the hand is asked, the
    /// folds have already been run and the admission means a shift really is
    /// reachable.
    ///
    /// So a hand may rely on `wanted` being shift-reachable **in the product**
    /// and must not rely on it under `drive`, where it is the union. A hand
    /// that needs the strict shift half in either walk wants `named`, and one
    /// that needs the union wants this under `drive`.
    wanted: std.DynamicBitSetUnmanaged,
    /// The subset of `wanted` the state named for itself, extras excluded.
    ///
    /// `wanted` cannot answer this, because it auto-admits every extra so that
    /// an external scanner reading it sees what tree-sitter's `valid_symbols`
    /// would show. That conflation is fine for a hand and wrong for the skip:
    /// a terminal can be an extra *and* carry meaning, and then whether this
    /// position is whitespace or a token is exactly the question the state
    /// answers. elixir is the case - `\r?\n` is extras[0] and is also the whole
    /// of `_terminator`, one symbol in both roles - so skipping it wherever it
    /// matches loses every statement boundary in the file.
    named: std.DynamicBitSetUnmanaged,

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
        var e: Expected = .{
            .tiers = tiers,
            .wanted = try .initEmpty(gpa, s.seat.len),
            .named = try .initEmpty(gpa, s.seat.len),
        };
        e.clear(s);
        return e;
    }

    pub fn deinit(e: *Expected, gpa: std.mem.Allocator) void {
        for (e.tiers) |*t| {
            t.here.deinit(gpa);
            t.later.deinit(gpa);
        }
        gpa.free(e.tiers);
        e.wanted.deinit(gpa);
        e.named.deinit(gpa);
        e.* = undefined;
    }

    pub fn clear(e: *Expected, s: *const Scanner) void {
        for (e.tiers) |*t| {
            t.here.forbidAll();
            t.later.forbidAll();
            t.live_here = false;
            t.live_later = false;
        }
        e.wanted.unsetAll();
        e.named.unsetAll();
        var it = s.skipped.iterator(.{});
        while (it.next()) |i| e.open(s, @intCast(i));
    }

    pub fn admit(e: *Expected, s: *const Scanner, sym: press.Symbol) void {
        if (sym >= s.seat.len) return;
        e.named.set(sym);
        e.open(s, sym);
    }

    /// Admit without claiming the state named it, which is how the extras are
    /// seeded: they are lexable everywhere and meant by nobody.
    fn open(e: *Expected, s: *const Scanner, sym: press.Symbol) void {
        e.wanted.set(sym);
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
