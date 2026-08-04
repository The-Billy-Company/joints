//! Two monoids to prove the spine against, neither of them the joint.
//!
//! That is on purpose. The joint needs a grammar, an automaton, and three
//! interning pools before it can produce a single element, so a spine tested
//! only through it would be testing the press as much as the tree - and a
//! failure would be a whole afternoon of deciding which layer lied. These two
//! need nothing, run in a microsecond, and between them exercise both halves of
//! what the tree has to get right.
//!
//! **`Tally` proves the order.** A polynomial hash of the leaf sequence is
//! associative and, unlike anything commutative, changes when two leaves swap or
//! one goes missing. It never refuses, so a long random edit stream stays
//! interesting instead of dying at the first refusal and comparing null to null
//! forever after.
//!
//! **`Sieve` proves the refusal.** Partial maps on eight points compose
//! partially - a composite defined nowhere is a genuine refusal, exactly as the
//! joint refuses a pairing no parse produced - and the refusal is associative in
//! the sense the tree needs: if `a·b` is defined nowhere then so is `(a·b)·c`,
//! and so is `a·(b·c)`, because both are defined at `x` only if `b(a(x))` is.
//! Sieve products die out on a long file, which is honest rather than awkward:
//! any monoid with a real refusal does, and so does the joint. It is run over
//! short files where both outcomes happen.
//!
//! Both take the meter as their `Ctx`, so the compositions an edit costs are
//! counted by the thing doing them rather than by an instrument bolted to the
//! tree. `fold` at the bottom is the third fixture: the from-scratch product,
//! computed the dumb way, which is what every claim about the tree is stated
//! against.

const std = @import("std");

/// How many compositions have been asked for. The measurement's whole
/// instrument, and it lives here because `Ctx` already threads to exactly the
/// one place `compose` is called from.
pub const Meter = struct {
    composes: u64 = 0,

    pub fn reset(m: *Meter) void {
        m.composes = 0;
    }
};

/// The free monoid on leaves, hashed. Associative, non-commutative, total.
pub const Tally = struct {
    pub const Ctx = *Meter;
    pub const Element = struct { hash: u64, span: u32 };
    pub const identity: Element = .{ .hash = 0, .span = 0 };

    /// Odd and large, so multiplying by it is a bijection on `u64` and no
    /// prefix of the file can collapse into another by accident.
    const radix: u64 = 0x9E3779B97F4A7C15;

    pub fn compose(m: Ctx, a: Element, b: Element) !?Element {
        m.composes += 1;
        return .{ .hash = a.hash *% raise(b.span) +% b.hash, .span = a.span + b.span };
    }

    pub fn eql(a: Element, b: Element) bool {
        return a.hash == b.hash and a.span == b.span;
    }

    pub fn draw(rng: std.Random) Element {
        return .{ .hash = rng.int(u64) | 1, .span = 1 };
    }

    fn raise(k: u32) u64 {
        var acc: u64 = 1;
        var base = radix;
        var n = k;
        while (n != 0) : (n >>= 1) {
            if (n & 1 != 0) acc *%= base;
            base *%= base;
        }
        return acc;
    }
};

/// Partial maps on a few points, under composition. Associative,
/// non-commutative, and partial in the way that matters: a composite defined
/// nowhere is a refusal rather than an element.
pub const Sieve = struct {
    pub const Ctx = *Meter;
    pub const points = 8;
    pub const nowhere: u8 = 0xFF;
    pub const Element = struct { to: [points]u8 };
    pub const identity: Element = .{ .to = .{ 0, 1, 2, 3, 4, 5, 6, 7 } };

    pub fn compose(m: Ctx, a: Element, b: Element) !?Element {
        m.composes += 1;
        var out: Element = .{ .to = @splat(nowhere) };
        var live = false;
        for (a.to, 0..) |mid, i| {
            if (mid == nowhere) continue;
            const end = b.to[mid];
            if (end == nowhere) continue;
            out.to[i] = end;
            live = true;
        }
        return if (live) out else null;
    }

    pub fn eql(a: Element, b: Element) bool {
        return std.mem.eql(u8, &a.to, &b.to);
    }

    /// A shuffle with holes punched in it. The hole rate is the whole tuning
    /// knob and it was measured, not guessed: at one hole in sixty-four a file
    /// of fifteen segments never once refused across 2500 edits, so the
    /// refusing half of this monoid was never being tested. Dropping each point
    /// with probability 1/8 leaves a chain of `L` segments about `8·(7/8)^L`
    /// points wide, which crosses zero right around the sizes the edit stream
    /// wanders through - so both answers really happen.
    pub fn draw(rng: std.Random) Element {
        var e: Element = identity;
        rng.shuffle(u8, &e.to);
        for (&e.to) |*p| {
            if (rng.uintLessThan(u8, points) == 0) p.* = nowhere;
        }
        return e;
    }
};

/// The product of a run of leaves, left to right, by hand. Deliberately not the
/// tree: an oracle that shared the tree's bracketing could not catch the tree
/// bracketing wrongly, which is the one bug that matters here and the one that
/// is silent.
pub fn fold(comptime M: type, x: M.Ctx, ls: anytype) !?M.Element {
    var acc: M.Element = M.identity;
    for (ls) |l| acc = try M.compose(x, acc, l.element) orelse return null;
    return acc;
}
