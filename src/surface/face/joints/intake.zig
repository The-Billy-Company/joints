//! The one door every verb turns a path into a parser through.
//!
//! Four steps, in this order, and every verb here walks a prefix of them:
//! bytes (`slurp`), a grammar (`grammar`), its LALR tables (`tables`), its
//! terminal scanner (`scanner`). Nothing in this folder does any of the four
//! any other way.
//!
//! Five verbs used to read a file five ways: two copies of the same block
//! inside `main.zig`, a third pasted into `parse.zig` and re-exported for
//! `amend.zig` to borrow, a fourth and fifth inlined in `survey.zig` and
//! `mint.zig`. All five said the same thing - `joints: cannot read <path>:
//! <errName>` - which is exactly the danger: five copies of one sentence drift
//! the moment one of them is edited and the other four are not. That argument
//! was never about reading files, and the other three steps were pasted just
//! as widely: seven copies of the import block, six of the press, four of the
//! scanner compile. The drift the argument predicts had already happened in
//! the fourth: `parse` and `amend` exit `2` where `lex` and `survey` exit `1`
//! on the same condition. That one turned out not to be drift - see `scanner`
//! below - but finding out took reading four copies of the block to notice they
//! disagreed, which is the cost even when the answer is that they should.
//!
//! None of the four propagate. A grammar tree-sitter rejects is not this
//! process's fault and not the caller's either, so the caller does not `try`
//! it - the diagnostic is printed here, on the writer the caller already owns,
//! and `null` is the whole of what comes back. That also means a diagnostic
//! write cannot abort a run: a verb walking several files (`parse`, `survey`)
//! must reach the rest of them even if one path's error line loses a race with
//! a closed pipe, and a verb reading exactly one file has no "rest" to protect
//! but should not behave differently on that account.
//!
//! `scanner` is the exception to the `null`, because it is the one step whose
//! two failures are not the same kind of failure and whose exit code is not
//! this file's to decide. It hands back which one happened; the verb says what
//! that is worth.
//!
//! `choice` and `default` at the bottom are not one of the four. They are the
//! same argument aimed one level lower: at a flag whose values are an enum's
//! members, where the set of spellings had been written out by hand beside the
//! lookup that already knew them.

const std = @import("std");
const joints = @import("joints");

const press = joints.press;
const lex = joints.kernel.lex.scanner;
const quire = joints.kernel.quire;
const weave = joints.kernel.weave;

/// `path`'s whole contents, or `null` after printing why not to `w`.
///
/// `-` is standard input, spelled the way every other Unix filter spells it,
/// so `fmt something | joints parse g.folio -` works without a temp file.
/// A named file called `-` is reachable as `./-`, which is also the answer
/// every other filter gives.
///
/// Capped at 64 MiB either way: a grammar or a source file past that is not a
/// file this verb was built to hold in one arena, and refusing loudly here
/// beats an allocator refusing less legibly three calls further in.
pub fn slurp(gpa: std.mem.Allocator, io: std.Io, w: *std.Io.Writer, path: []const u8) ?[]u8 {
    if (std.mem.eql(u8, path, "-")) {
        var buf: [4096]u8 = undefined;
        var reader = std.Io.File.stdin().readerStreaming(io, &buf);
        return reader.interface.allocRemaining(gpa, .limited(64 << 20)) catch |err| {
            w.print("joints: cannot read stdin: {s}\n", .{@errorName(err)}) catch {};
            return null;
        };
    }
    return std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64 << 20)) catch |err| {
        w.print("joints: cannot read {s}: {s}\n", .{ path, @errorName(err) }) catch {};
        return null;
    };
}

/// `source` read as a tree-sitter `grammar.json`, or `null` after printing why
/// not to `w`.
///
/// `path` is named in the diagnostic and nowhere else - the bytes are already
/// in hand, and a verb that got them from `-` still wants the name it typed.
pub fn grammar(
    gpa: std.mem.Allocator,
    w: *std.Io.Writer,
    path: []const u8,
    source: []const u8,
) ?press.Grammar {
    return press.treeSitter(gpa, source) catch |err| {
        w.print("joints: cannot import {s}: {s}\n", .{ path, @errorName(err) }) catch {};
        return null;
    };
}

/// `gr`'s LALR tables, or `null` after printing why not to `w`.
///
/// The caller still owns `gr` on both paths. A press that fails leaves nothing
/// behind to free, so there is no half-built `Result` here to reason about -
/// which is why the four sites that hold a grammar across this call keep their
/// own `deinit` rather than handing ownership over.
pub fn tables(
    gpa: std.mem.Allocator,
    w: *std.Io.Writer,
    gr: *const press.Grammar,
) ?press.Result {
    return press.tables(gpa, gr) catch |err| {
        w.print("joints: cannot press {s}: {s}\n", .{ gr.name, @errorName(err) }) catch {};
        return null;
    };
}

/// Why `scanner` came back with nothing.
///
/// `WontCompile` is exit `2` at every call site - the press failed at something
/// it should have managed. `NothingLexable` is the one the verb has to judge,
/// and the two answers in this folder are both right. `lex` and `survey` exit
/// `1`: they were asked what a grammar tokenizes to and "nothing" is that
/// question's answer. `parse` and `amend` exit `2`: they were asked for a tree,
/// and a grammar with no lexable terminal is not a tree they built and rejected
/// but a tree they could not attempt. `README.md` states the rule those both
/// follow from - `1` is a clean negative answer, `2` is a thing that could not
/// be attempted - and names `lex` specifically, which is why it reads at first
/// like `parse` is wrong. Watch that this stays deliberate: `tool/sound.py`
/// tells a yaml SKIP from a wiring failure by this exact code.
pub const Unlexable = error{
    /// The grammar has no lexable terminal at all - true about the grammar.
    NothingLexable,
    /// The press could not build a scanner for terminals it has - our defect.
    WontCompile,
};

/// `gr`'s terminal scanner, or an `Unlexable` after printing why not to `w`.
pub fn scanner(
    gpa: std.mem.Allocator,
    w: *std.Io.Writer,
    gr: *const press.Grammar,
) Unlexable!lex.Scanner {
    const sc = lex.Scanner.compile(gpa, gr) catch |err| {
        w.print("joints: cannot compile {s}'s scanner: {s}\n", .{
            gr.name, @errorName(err),
        }) catch {};
        return error.WontCompile;
    };
    return sc orelse {
        w.print("joints: {s} has no lexable terminal at all\n", .{gr.name}) catch {};
        return error.NothingLexable;
    };
}

/// `Unlexable` for a verb that was asked what a grammar tokenizes to, where
/// "nothing" is an answer and not a refusal. `parse` and `amend` do not call
/// this - see `Unlexable`.
pub fn tokenless(err: Unlexable) u8 {
    return switch (err) {
        error.NothingLexable => 1,
        error.WontCompile => 2,
    };
}

/// What the face's two enum-valued flags mean when unspoken.
///
/// Here rather than in the verb that reads them because the usage block in
/// `main.zig` has to name the same member the parser applies, and it named it as
/// a word inside a sentence - so the two were free to disagree, and nothing
/// would have said which one was the CLI's actual behaviour.
pub const default = struct {
    /// `parse --mend=`.
    pub const mend: quire.Mend = .fell;
    /// `amend --policy=`.
    pub const remint: weave.Policy = .prove;
};

/// `E`'s members as a sentence: `"fell (default), none, keep, relent"` with a
/// `dflt`, and `"none, keep, fell or relent"` without one.
///
/// Comptime, so the usage block can carry the result and a member that does not
/// exist cannot be named.
pub fn spellings(comptime E: type, comptime dflt: ?E) []const u8 {
    const fields = @typeInfo(E).@"enum".fields;
    comptime var out: []const u8 = if (dflt) |d| @tagName(d) ++ " (default)" else "";
    inline for (fields, 0..) |f, i| {
        if (dflt) |d| {
            if (comptime std.mem.eql(u8, f.name, @tagName(d))) continue;
            out = out ++ ", " ++ f.name;
        } else {
            // No default to lead with, so the last member gets the `or` an
            // English list ends on. `i` counts fields, not appends, which is
            // only correct on this arm - the other one skipped one.
            out = out ++ if (i == 0) "" else if (i == fields.len - 1) " or " else ", ";
            out = out ++ f.name;
        }
    }
    return out;
}

/// `text` as one of `E`'s members, or `null` after naming the whole vocabulary
/// on `w`.
///
/// The spellings in the refusal are `E`'s own fields, which is the point rather
/// than a tidiness: `--mend` carried "none, keep, fell or relent" as a string
/// beside the lookup that already accepted exactly those, so a policy added to
/// `quire.Mend` would have been taken by a CLI that denied it existed. And
/// `--policy` had the mirrored half of the same fault - it refused without ever
/// saying what it would have taken. Both are the enum now, so widening either
/// vocabulary touches neither this file nor the usage block.
pub fn choice(
    comptime E: type,
    w: *std.Io.Writer,
    flag: []const u8,
    text: []const u8,
) ?E {
    return std.meta.stringToEnum(E, text) orelse {
        w.print("joints: {s} wants {s}, not '{s}'\n", .{
            flag, comptime spellings(E, null), text,
        }) catch {};
        return null;
    };
}

test "a vocabulary names every member it accepts" {
    // A local enum and not `quire.Mend`, deliberately: the property is that no
    // member goes unnamed, and asserting it against the live enum would pin the
    // policies that exist today and fail the day one is legitimately added -
    // which is the exact change this helper exists to make free.
    const E = enum { alpha, beta, gamma };
    inline for (@typeInfo(E).@"enum".fields) |f| {
        try std.testing.expect(std.mem.indexOf(u8, spellings(E, null), f.name) != null);
        try std.testing.expect(std.mem.indexOf(u8, spellings(E, .beta), f.name) != null);
    }
    // Both renderings exactly, on a fixture where pinning them is the point.
    try std.testing.expectEqualStrings("alpha, beta or gamma", spellings(E, null));
    try std.testing.expectEqualStrings("beta (default), alpha, gamma", spellings(E, .beta));
    // A one-member vocabulary has no conjunction to place and no comma to trail.
    const One = enum { sole };
    try std.testing.expectEqualStrings("sole", spellings(One, null));
    try std.testing.expectEqualStrings("sole (default)", spellings(One, .sole));
}
