//! What a rule does once its guard held: the actions, in the order they are
//! written.
//!
//! Order is semantics here, not style. `skip` before `emit` is a token that
//! starts past the offset the scanner was asked at - tree-sitter's
//! `advance(lexer, true)` - and the same two the other way round is a token at
//! the offset with trailing bytes nobody claims. A `push` after an `emit` is a
//! region the answer opens; before it, one the answer is already inside. So the
//! list is walked once, left to right, and every action sees what the ones in
//! front of it did.
//!
//! Two actions end the rule where they stand. `refuse` withdraws this rule and
//! lets the one behind it answer; `abstain` withdraws the whole ask. Both are
//! `return false` after a state write, which every one of the eight does
//! somewhere, and both keep the organ writes already made - that is the point of
//! them: a scanner that remembers something about bytes it does not claim needs a
//! way to say exactly that.
//!
//! Nothing here can fail. Every organ is fixed-capacity and refuses its own
//! overflow (`organs.zig`), every index was proven at load (`book.zig`), and
//! every value is total (`guard.zig`) - so applying a rule is a sequence of
//! writes with no error path, which is what keeps `outside.step`'s contract
//! intact.

const std = @import("std");
const book = @import("book.zig");
const organs = @import("organs.zig");
const engine = @import("engine.zig");
const guard = @import("guard.zig");

const Ask = engine.Ask;
const Hit = engine.Hit;
const Bound = guard.Bound;

/// Run a rule's actions, and return what it answered with.
///
/// Null is an effect-only rule (or a refusal), and it is not the same as a rule
/// that did not hold: the organ writes stand either way, and the caller reads
/// `b.abstain` to tell "carry on to the rule behind this one" from "this ask is
/// over".
pub fn apply(
    a: *Ask,
    r: *const book.RuleRow,
    o: *organs.Organs,
    at: u32,
    _: organs.Facts,
    b: *Bound,
) ?Hit {
    // Measured here rather than taken from the guard's: the guard for a `layout`
    // rule stood past the line's blanks with a `lead` that folded in the carried
    // budget, and an action asking for the `column` wants the offset it is
    // actually writing at. `lead` is the exception and stays bound, because a
    // soak in the guard is the only reading of it an action ever wants.
    const f = organs.facts(a.bytes, at, a.e.tab(), 0);
    var hit: ?Hit = null;
    var skip: u32 = 0;
    for (a.e.program.thenOf(r), r.act_at..) |act, i| switch (@as(book.Action, @enumFromInt(act.op))) {
        .refuse => return null,
        .abstain => {
            b.abstain = true;
            return null;
        },
        .emit => {
            // The width a guard read, unless the rule states another - a
            // zero-width close states `0`, and a rule that probes look-ahead it
            // does not claim states what it does.
            var width: i64 = b.eaten orelse 0;
            var sym = a.e.emits[i];
            if (act.class >= 0) {
                sym = classify(a, act, i, @intCast(@max(width, 0)), at);
            } else if (act.v0 != book.none) {
                width = guard.value(a, act.v0, o, f, b);
            }
            hit = .{ .symbol = sym, .len = @intCast(@max(width, 0)), .skip = skip };
        },
        .skip => skip += @intCast(@max(guard.value(a, act.v0, o, f, b), 0)),
        .push => switch (@as(book.Stack, @enumFromInt(act.stack))) {
            .frames => o.pushFrame(
                @intCast(@max(guard.value(a, act.v0, o, f, b), 0)),
                @intCast(act.kind),
            ),
            .marks => o.pushMark(
                @intCast(act.kind),
                @intCast(@max(guard.value(a, act.v0, o, f, b), 0)),
                slice(a, act, b),
            ),
        },
        .pop => switch (@as(book.Stack, @enumFromInt(act.stack))) {
            .frames => if (act.kind < 0) o.popFrame() else o.popFrameUntil(@intCast(act.kind)),
            .marks => if (act.kind < 0) o.popMark() else o.popMarkUntil(@intCast(act.kind)),
        },
        .set => o.regs[act.reg] = @intCast(@max(guard.value(a, act.v0, o, f, b), 0)),
    };
    return hit;
}

/// The one action a pattern roll structurally cannot have: a second pressed
/// table over the text just matched, renaming the answer.
///
/// yaml's schema resolver, and the reason it is an action rather than an input -
/// `_r_sgl_pln_str_blk` and `_r_sgl_pln_int_blk` are the *same* scan of the same
/// bytes, differing only in what the bytes turned out to say. Each arm must match
/// the text end to end (`Engine.compileProbe` anchors both ends), because a
/// classifier that matched a prefix would call every number a string.
pub fn classify(a: *Ask, act: book.ActRow, at_act: usize, width: u32, at: u32) organs.Symbol {
    const end: u32 = @intCast(a.bytes.len);
    const lo = @min(at, end);
    const got = a.bytes[lo..@min(lo + width, end)];
    const c = a.e.program.classes[@intCast(act.class)];
    var slots: [guard.slots_max]isize = undefined;
    for (c.at..c.at + c.len) |arm| {
        var caps = &a.e.arms[arm];
        if (caps.matchAt(got, 0, slots[0..caps.nslots()])) return a.e.renames[arm];
    }
    return a.e.emits[at_act];
}

/// The bytes a `push marks` remembers as its tag.
///
/// A heredoc's word comes off the match that opened it, so `match` and `group k`
/// read the guard's own capture; a fence's is a literal the book states. Empty
/// where the guard captured nothing, which is a mark that closes on the next
/// probe rather than one that never closes.
fn slice(a: *Ask, act: book.ActRow, b: *const Bound) []const u8 {
    return switch (@as(book.Slice, @enumFromInt(act.slice))) {
        .none => "",
        .match => b.group(a.bytes, 0),
        .group => b.group(a.bytes, act.slice_group),
        .literal => a.e.program.str(act.name),
    };
}
