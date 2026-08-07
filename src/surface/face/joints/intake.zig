//! The one door every verb reads a path through.
//!
//! Five verbs used to read a file five ways: two copies of the same block
//! inside `main.zig`, a third pasted into `parse.zig` and re-exported for
//! `amend.zig` to borrow, a fourth and fifth inlined in `survey.zig` and
//! `mint.zig`. All five said the same thing - `joints: cannot read <path>:
//! <errName>` - which is exactly the danger: five copies of one sentence drift
//! the moment one of them is edited and the other four are not. This is the
//! only place that sentence is spelled, and every verb that needs a file's
//! bytes calls through it.
//!
//! `slurp` never propagates. A read that fails is not this process's fault and
//! not the caller's either, so the caller does not `try` it - the diagnostic
//! is printed here, on the writer the caller already owns, and `null` is the
//! whole of what comes back. That also means the diagnostic write itself
//! cannot abort a run: a verb walking several files (`parse`, `survey`) must
//! reach the rest of them even if one path's error line loses a race with a
//! closed pipe, and a verb reading exactly one file has no "rest" to protect
//! but should not behave differently on that account. One signature, one
//! failure shape, everywhere.
//!
//! This is the file-read half of the CLI's error-handling contract; the rest
//! of it - exit codes, and how a failure that is not a read failure gets
//! reported - is written down in `README.md` beside this file.

const std = @import("std");

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
