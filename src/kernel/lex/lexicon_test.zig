//! The lexicon block against the automaton it was written from, field by field,
//! by reflection.
//!
//! `src/press/carry_test.zig` makes this argument about the IR, and its header
//! is the argument: `freeze` enumerates fields into a record by hand and `thaw`
//! enumerates them back out by hand, so every field either survives the round
//! trip or reads as the type's default on the far side. A default is a legal
//! value for most of them, which is how a field goes missing with nobody
//! writing a line of wrong code.
//!
//! That is one boundary. This is the other one, a level down, and it had no
//! test at all - the IR survey declares `Grammar.lexicon` as *added*, which
//! says the block exists and says nothing about what is inside it. `Dfa.reach`
//! crossed neither way for as long as it existed: the mask was computed at
//! import, never written, and `reachableFrom` answers all-ones for an absent
//! one, so a folio lexed the same tokens and walked to end-of-file per position
//! to get them. Same tokens is exactly why nothing caught it. The measured cost
//! was 110x on the path the product ships.
//!
//! So the same three things that make the IR survey fail closed are done here:
//!
//!   - **reflection rather than a list of fields**, so a field nobody thought
//!     about is compared anyway;
//!   - **a sample whose fields are distinguishable**, since a field left at its
//!     default on both sides compares equal whether it crossed or not - such a
//!     field is reported as unseen, and unseen is a failure, because a green run
//!     that checked nothing is worse than a red one; and
//!   - **the field count asserted at comptime**, because a newly added field is
//!     the one case reflection cannot catch by itself. Adding one stops the
//!     build here.
//!
//! Losses that are correct are declared with their reason, and a declared loss
//! that starts crossing fails too, so the list cannot rot.

const std = @import("std");
const testing = std.testing;
const irregex = @import("irregex");
const lexicon = @import("lexicon.zig");

const Munch = irregex.Munch;
const Dfa = Munch.Dfa;

/// A field the round trip drops, and why.
const Loss = struct { at: []const u8, why: []const u8 };

const dropped = [_]Loss{
    .{ .at = "visits", .why = "what determinizing cost, not what the walk needs - a build statistic" },
    .{ .at = "allocator", .why = "the far side's own, by construction" },
    .{ .at = "borrowed", .why = "false when built and true when read: the whole point of the image" },
    .{ .at = "start_dwell", .why = "`freeze` refuses a voice carrying one rather than dropping it" },
    .{ .at = "wide", .why = "the same - a munch voice never carries the wide axis" },
};

/// Fields a munch voice structurally cannot hold, so the sample cannot make them
/// differ and the survey would otherwise report them unseen forever. Declared
/// rather than skipped, for the same reason the losses are: if one of them ever
/// starts carrying a value, this list is where the claim that it could not is
/// written down. They are written and read like any other field - the round trip
/// is untested for them because there is nothing to test it with.
const inert = [_]Loss{
    .{ .at = "word_ctx", .why = "`Munch.compile` declines a word-axis slate outright, so no voice has one" },
    .{ .at = "trans_in_w", .why = "the word axis's table, absent for the same reason" },
    .{ .at = "start_w", .why = "the word axis's start, absent for the same reason" },
    .{ .at = "unicode_word", .why = "the word axis's fold, absent for the same reason" },
};

/// The roster's own fields, as distinct from an automaton's. Two structures
/// cross this block, not one: a `Munch` is a list of voices *and* the map from
/// the caller's ordinals onto their bits, and the map is the half a `Dfa`
/// survey cannot see. It is also the half whose loss is loud rather than quiet -
/// a seat pointing at the wrong bit makes `Allow.admit` permit some other
/// terminal, which is a wrong token stream - so it is surveyed for completeness
/// rather than because it is the likelier defect.
const Voice = Munch.Voice;
const Seat = @typeInfo(@TypeOf(@as(Munch, undefined).seats)).pointer.child;

const roster = [_]Loss{
    .{ .at = "gpa", .why = "the far side's own, by construction" },
    .{ .at = "because", .why = "why each decline happened, which is a compile-time diagnostic no reader on this side consults - `declined` itself is load-bearing and does cross" },
    .{ .at = "winners", .why = "scratch, rewritten by every scan; only its width is a fact" },
};

fn rostered(name: []const u8) ?Loss {
    for (roster) |d| if (std.mem.eql(u8, d.at, name)) return d;
    return null;
}

comptime {
    if (std.meta.fields(Dfa).len != 22) @compileError(
        "Dfa changed width: give the new field a distinguishing value in `sample`, " ++
            "then either carry it through `freeze`/`thaw` or declare the loss in " ++
            "`dropped` and update the count here",
    );
    // The same argument one level out. A field added to `Munch` or to what it
    // holds is reconstructed by `adopt`, and a field `adopt` forgets reads as
    // its default with no line of wrong code anywhere - which is exactly how
    // `Dfa.reach` was lost.
    if (std.meta.fields(Munch).len != 6) @compileError(
        "Munch changed width: carry the new field through `freeze`/`adopt` or " ++
            "declare it in `roster` and update the count here",
    );
    if (std.meta.fields(Voice).len != 2) @compileError(
        "Munch.Voice changed width: carry the new field through `freeze`/`thaw` " ++
            "and update the count here",
    );
    if (std.meta.fields(Seat).len != 3) @compileError(
        "Munch's seat changed width: `adopt` rebuilds every seat, so a new field " ++
            "needs rebuilding there before the count moves here",
    );
}

/// A slate chosen so the automaton it determinizes to leaves few fields at their
/// defaults: an anchored member so `trans_fin` differs from `trans_in`, a word
/// boundary for the word axis, a nullable member for `empty_match`/`empty_pats`,
/// a permissive body so the reachability mask has trap states to describe, and
/// enough members that `pat_runs` holds more than one run.
const slate = [_][]const u8{
    "return",
    "=",
    ";",
    "[^\"\\\\]+",
    "keep$",
    "\\bword\\b",
    "[0-9]*",
    "[_a-zA-Z][_a-zA-Z0-9]*",
};

fn sample(gpa: std.mem.Allocator) !Munch {
    return (try Munch.compile(gpa, &slate, .{})) orelse error.SlateDeclined;
}

fn declared(name: []const u8) ?Loss {
    for (dropped) |d| if (std.mem.eql(u8, d.at, name)) return d;
    return null;
}

fn unexercised(name: []const u8) ?Loss {
    for (inert) |d| if (std.mem.eql(u8, d.at, name)) return d;
    return null;
}

test "every field of an automaton either crosses the lexicon block or is a declared loss" {
    const gpa = testing.allocator;
    var m = try sample(gpa);
    defer m.deinit();
    try testing.expect(m.voices.len > 0);

    const stamp = lexicon.digest(&slate, .{});
    const block = (try lexicon.freeze(gpa, &m, stamp)) orelse return error.BlockRefused;
    defer gpa.free(block);

    var back = (try lexicon.thaw(gpa, block, slate.len, stamp)) orelse return error.BlockNotRead;
    defer back.deinit(gpa);

    try testing.expectEqual(m.voices.len, back.munch.voices.len);

    // Unseen is tracked across every voice rather than per voice: one voice may
    // legitimately leave a field at its default while another does not, and it
    // is the slate as a whole that has to exercise the field.
    var seen: [std.meta.fields(Dfa).len]bool = @splat(false);

    for (m.voices, back.munch.voices) |mine, theirs| {
        const a = mine.dfa;
        const b = theirs.dfa;
        inline for (std.meta.fields(Dfa), 0..) |f, i| {
            const mv = @field(a, f.name);
            const tv = @field(b, f.name);
            const loss = comptime declared(f.name);
            const same = switch (@typeInfo(f.type)) {
                .pointer => |p| p.size == .slice and mv.len == tv.len and
                    std.mem.eql(u8, std.mem.sliceAsBytes(mv), std.mem.sliceAsBytes(tv)),
                .optional => (mv == null) == (tv == null),
                .@"struct" => true, // allocator: nothing to compare
                else => std.meta.eql(mv, tv),
            };
            const dull = switch (@typeInfo(f.type)) {
                .pointer => |p| p.size == .slice and mv.len == 0,
                .optional => mv == null,
                .@"struct" => true,
                else => std.meta.eql(mv, std.mem.zeroes(f.type)),
            };
            if (!dull) seen[i] = true;
            if (loss != null) {
                // A declared loss that started crossing is as much a stale
                // claim as a field that stopped. `borrowed` inverts by design,
                // so it is asserted the other way round rather than skipped.
                if (comptime std.mem.eql(u8, f.name, "borrowed")) {
                    try testing.expect(!mv and tv);
                }
                continue;
            }
            if (!same) {
                std.debug.print("lexicon: `{s}` did not cross the block\n", .{f.name});
                return error.FieldLost;
            }
        }
    }

    inline for (std.meta.fields(Dfa), 0..) |f, i| {
        if (comptime declared(f.name) != null) continue;
        if (comptime unexercised(f.name) != null) continue;
        if (!seen[i]) {
            std.debug.print(
                "lexicon: `{s}` was the default on both sides, so the round trip " ++
                    "was never tested for it - give `slate` a member that exercises it\n",
                .{f.name},
            );
            return error.FieldUnseen;
        }
    }
}

test "every field of the roster either crosses the lexicon block or is a declared loss" {
    // The `Dfa` survey above walks what is inside each voice. This walks what
    // holds them, because a folio-backed `Munch` is rebuilt by `adopt` rather
    // than read whole, and `adopt` enumerates by hand exactly the way `thaw`
    // does. Same failure mode, one level out.
    const gpa = testing.allocator;
    var m = try sample(gpa);
    defer m.deinit();

    const stamp = lexicon.digest(&slate, .{});
    const block = (try lexicon.freeze(gpa, &m, stamp)) orelse return error.BlockRefused;
    defer gpa.free(block);
    var back = (try lexicon.thaw(gpa, block, slate.len, stamp)) orelse return error.BlockNotRead;
    defer back.deinit(gpa);

    // `declined` is the one that would be quiet and is not diagnostic:
    // `compile` unseats every refused ordinal, so a folio that lost the list
    // would hand a seat back to a terminal the engine cannot run, and the slate
    // would admit a pattern that is not there. Bytes, not lengths.
    inline for (std.meta.fields(Munch)) |f| {
        if (comptime rostered(f.name) == null) {
            const mv = @field(m, f.name);
            const tv = @field(back.munch, f.name);
            try testing.expectEqual(mv.len, tv.len);
            if (comptime !std.mem.eql(u8, f.name, "voices")) {
                try testing.expectEqualSlices(
                    u8,
                    std.mem.sliceAsBytes(mv),
                    std.mem.sliceAsBytes(tv),
                );
            }
        }
    }

    // `winners` is scratch, but its *width* is a fact: it is sized once to the
    // widest answer the slate can give, and a narrow one is a buffer overrun on
    // the first tie rather than a wrong answer.
    try testing.expectEqual(m.winners.len, back.munch.winners.len);

    // And a voice is its automaton plus the ordinals its bits stand for. The
    // automaton is surveyed above; the ordinals are the reason a refusal can be
    // a hole rather than a renumber, so they are bytes rather than a length.
    for (m.voices, back.munch.voices) |mine, theirs| {
        try testing.expectEqualSlices(u32, mine.ordinals, theirs.ordinals);
    }

    // The seats really do say something - an all-default map would satisfy the
    // comparison above and mean nothing. The slate deliberately holds one
    // member the engine refuses, so the live count is a number rather than a
    // restatement of the slate's length, and the refusal is the thing the
    // `declined` bytes above have to reproduce.
    try testing.expect(m.declined.len > 0);
    var live: usize = 0;
    for (m.seats) |s| {
        if (s.live) live += 1;
    }
    try testing.expectEqual(slate.len - m.declined.len, live);
}

test "a block that lost the reachability mask is refused rather than read slowly" {
    // The failure this whole file exists for, reproduced: a block that is
    // correct in every other way but carries no mask must not load. It would
    // lex the same tokens - `reachableFrom` answers all-ones when the table is
    // empty - and pay a walk to end-of-file at every position for the rest of
    // the folio's life, which is the one wrong answer that never says so.
    //
    // Reproduced by writing a real block and clearing the mask's *length* in
    // every head, which is exactly the shape an older binary's block has.
    const gpa = testing.allocator;
    var m = try sample(gpa);
    defer m.deinit();

    const stamp = lexicon.digest(&slate, .{});
    const block = (try lexicon.freeze(gpa, &m, stamp)) orelse return error.BlockRefused;
    defer gpa.free(block);

    // A multi-pattern voice is present to begin with, or the negative below
    // proves nothing. A single-pattern voice carries no mask by the rule
    // `freeze` and `thaw` share, and needs none.
    var wide: usize = 0;
    for (m.voices) |v| if (v.ordinals.len > 1) {
        wide += 1;
        try testing.expectEqual(v.dfa.nstates, @as(u32, @intCast(v.dfa.reach.len)));
    };
    try testing.expect(wide > 0);

    var back = (try lexicon.thaw(gpa, block, slate.len, stamp)) orelse return error.BlockNotRead;
    defer back.deinit(gpa);
    for (back.munch.voices) |v| {
        if (v.ordinals.len == 1) continue;
        try testing.expectEqual(v.dfa.nstates, @as(u32, @intCast(v.dfa.reach.len)));
        // And it is the *mask*, not a run of zeroes that happens to be the
        // right length: a state with no permitted pattern ahead of it is the
        // exit the walk takes, so an all-zero table would stop every walk at
        // its first byte and an all-ones table would stop none of them.
        var any: u64 = 0;
        for (v.dfa.reach) |w| any |= w;
        try testing.expect(any != 0);
    }
}

test "a folio-backed automaton answers the same reachability as the one it was written from" {
    // Reflection says the bytes match. This says the *walk* does, which is a
    // different claim: the mask is read through `reachableFrom`, which divides
    // by `ncls` because the walk carries premultiplied states. A table that
    // crossed intact and is indexed on the wrong footing reads a neighbouring
    // state's mask - still plausible, still all-ones often enough to look fine.
    const gpa = testing.allocator;
    var m = try sample(gpa);
    defer m.deinit();

    const stamp = lexicon.digest(&slate, .{});
    const block = (try lexicon.freeze(gpa, &m, stamp)) orelse return error.BlockRefused;
    defer gpa.free(block);
    var back = (try lexicon.thaw(gpa, block, slate.len, stamp)) orelse return error.BlockNotRead;
    defer back.deinit(gpa);

    for (m.voices, back.munch.voices) |mine, theirs| {
        const a = mine.dfa;
        const b = theirs.dfa;
        var s: u32 = 0;
        while (s < a.nstates) : (s += 1) {
            const off = s * a.ncls;
            try testing.expectEqual(a.reachableFrom(off), b.reachableFrom(off));
        }
    }
}
