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

const std = @import("std");
const joints = @import("joints");

const press = joints.press;
const lex = joints.kernel.lex.scanner;

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
