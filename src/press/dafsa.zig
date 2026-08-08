//! The grammar's string payloads as one automaton, and an honest account of
//! whether that was worth doing.
//!
//! A pressed grammar carries two sets of strings: every symbol's name, which is
//! the entire tree-sitter compatibility story, and every terminal's pattern.
//! Both are sets — sorted, deduplicated, asked about by content — so both are
//! what `irregex.math.dafsa` is for.
//!
//! **The prize is `rank`, not compression.** A DAFSA's `rank` is a minimal
//! perfect hash: it hands back a contiguous `0..count-1` ordinal, so anything
//! keyed by name lives in a flat array with no per-key pointer and no probe.
//! That is worth having whatever the automaton costs, because the alternative
//! is a hash map whose buckets are a pointer each and whose iteration order is
//! not the sorted one.
//!
//! **The compression is a measurement and it does not always go our way.** The
//! irregex `partition` rung found a DAFSA *losing* to a plain sorted array at
//! 0.12x on keys with long unshared stems, because a DAFSA pays four bytes of
//! target and one of label per edge and only earns it back where suffixes
//! genuinely coincide. Grammar symbol names are a mixed corpus in exactly that
//! sense — `_expression_statement` and `expression_statement` share everything,
//! while `%w(` and `<<~` share nothing with anything — so `Weight` below reports
//! both arms rather than asserting one, and the bench rung prints the ratio per
//! grammar. Believe the number, not the structure.
//!
//! **Measured, and it loses.** `zig build bench-quotient` over the eleven pinned
//! grammars puts names at 2.85x–4.33x the sorted array and patterns at
//! 2.71x–9.69x, with mean key lengths of seven to sixteen bytes: a grammar's
//! names are long, mostly-unshared stems, which is the shape the irregex rung
//! already identified as the automaton's worst. So the folio keeps writing the
//! sorted array, this stays an ordinal source rather than a storage format, and
//! the rung prints the ratio every run so a future corpus that *does* share
//! suffixes is noticed rather than assumed.

const std = @import("std");
const dafsa = @import("irregex").math.dafsa;
const g = @import("copy/grammar.zig");

pub const Error = dafsa.Error || std.mem.Allocator.Error;

/// One string payload, as an automaton plus the order it hands out.
pub const Set = struct {
    gpa: std.mem.Allocator,
    d: dafsa.Dafsa,
    /// The keys themselves, ascending — the same order `rank` numbers in, so
    /// `keys[d.rank(k).?]` is `k` and the two are checkable against each other.
    /// Borrowed from the grammar; nothing here copies a byte of text.
    keys: []const []const u8,

    pub fn deinit(s: *Set) void {
        s.d.deinit(s.gpa);
        s.gpa.free(s.keys);
        s.* = undefined;
    }

    /// The contiguous ordinal for `key`, or null when it is not in the set.
    pub fn ordinalOf(s: Set, key: []const u8) ?u32 {
        return s.d.rank(key);
    }

    pub fn count(s: Set) u32 {
        return @intCast(s.keys.len);
    }

    pub fn weight(s: Set) Weight {
        var text: u64 = 0;
        for (s.keys) |k| text += k.len;
        return .{
            .keys = s.count(),
            .text = text,
            // What the automaton costs on disk if it were written down: the
            // accept flag and the reach count per state, the CSR bound per
            // state plus the terminator, and a label and a target per edge.
            .dafsa = @as(u64, s.d.states()) * (1 + 4 + 4) + 4 + @as(u64, s.d.edges()) * (1 + 4),
            // What the folio actually writes today: the bytes, plus an
            // offset/length pair per key. The arm to beat.
            .sorted = text + @as(u64, s.count()) * 8,
        };
    }
};

/// What the two encodings of one payload cost. Reported, never asserted on —
/// see the header.
pub const Weight = struct {
    keys: u32,
    text: u64,
    dafsa: u64,
    sorted: u64,

    /// Below one, the automaton is the smaller of the two.
    pub fn ratio(w: Weight) f64 {
        if (w.sorted == 0) return 0;
        return @as(f64, @floatFromInt(w.dafsa)) / @as(f64, @floatFromInt(w.sorted));
    }
};

/// The automaton over `keys`, which are sorted and deduplicated here rather
/// than demanded of the caller: a grammar's names arrive in symbol order and
/// its patterns repeat, and both are the caller's own arrays that it must not
/// have reordered under it.
pub fn over(gpa: std.mem.Allocator, keys: []const []const u8) Error!Set {
    const sorted = try gpa.dupe([]const u8, keys);
    errdefer gpa.free(sorted);
    std.mem.sortUnstable([]const u8, sorted, {}, before);

    var n: usize = 0;
    for (sorted) |k| {
        if (n > 0 and std.mem.eql(u8, sorted[n - 1], k)) continue;
        sorted[n] = k;
        n += 1;
    }
    const set = sorted[0..n];
    return .{ .gpa = gpa, .d = try dafsa.build(gpa, set), .keys = set };
}

fn before(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

/// Every symbol's name.
pub fn names(gpa: std.mem.Allocator, gr: *const g.Grammar) Error!Set {
    return over(gpa, gr.names);
}

/// Every terminal's pattern, as the bytes the lexer is handed. An external
/// scanner contributes nothing to spell, and a nonterminal has no pattern at
/// all, so both are absent rather than empty.
pub fn patterns(gpa: std.mem.Allocator, gr: *const g.Grammar) Error!Set {
    var out: std.ArrayList([]const u8) = .empty;
    defer out.deinit(gpa);
    for (gr.patterns) |p| switch (p orelse continue) {
        .literal, .regex => |s| try out.append(gpa, s),
        .external => {},
    };
    return over(gpa, out.items);
}
