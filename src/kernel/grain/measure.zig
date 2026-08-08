//! What the leading run of a line came to - the one measurement every
//! layout-sensitive grammar is built on.
//!
//! Landin's offside rule compares a line's leading width against the column
//! the enclosing block opened at, and the comparison - not any byte - is the
//! token. The *stack* of those columns is lexical memory and lives up in
//! `kernel/lex/hand/offside.zig` with the hand that pushes it. What is here is
//! the half that is a fact about the bytes: how wide the run is, where the
//! line's content actually starts, and whether a comment got skipped on the
//! way. That half has no memory at all, which is exactly why it belongs down
//! here where a vectorized pass can answer it.
//!
//! ## One walk, two speeds
//!
//! There is a single implementation and it takes an optional `Ruling`. With
//! one it steps line to line; without one it steps byte to byte. That is
//! deliberate and it is not a fallback in the apologetic sense - it is the
//! only arrangement in which the two answers **cannot** drift, because there
//! is no second body to drift from. The shortcut is four lines inside the loop
//! and every one of them is a case the record was built to state; anything
//! else falls through to the byte arms below it, ruling or no ruling.
//!
//! Derived from tree-sitter-python's own `scanner.c` read as a specification -
//! the column arithmetic (a tab is worth eight, a carriage return and a form
//! feed reset to zero), the rule that a comment line defers a dedent until its
//! indentation drops below the current block, and the guard that a trailing
//! comment on an expression line emits nothing at all. Nothing is linked; the
//! C file is the spec and this is the implementation.

const std = @import("std");
const sweep = @import("sweep.zig");
const ruling = @import("ruling.zig");

pub const Note = ruling.Note;
pub const Ruling = ruling.Ruling;
pub const tab_stop = ruling.tab_stop;

/// What the leading run of a line came to, and what kind of line it was.
pub const Lead = struct {
    /// The offset the line's first significant byte sits at.
    at: u32,
    /// Its column, tabs expanded.
    column: u16,
    /// Whether a line ending (or the end of input) was crossed getting here.
    /// Without one there is no new line to measure, which is what keeps
    /// `foo = bar  # note` from opening a block.
    fresh: bool,
    /// The column of the first comment skipped on the way, when there was one.
    /// A dedent waits for a comment indented with the block it follows, so
    /// that a comment trailing a block is not read as leaving it.
    comment: ?u16,
    /// True when the walk stopped because a backslash continued a line into
    /// something that was not a newline - a malformed continuation, which the
    /// spec answers by declining rather than by guessing.
    broken: bool,
};

/// Measure the line `bytes[at..]` begins, skipping blank lines and whole-line
/// comments the way Python's tokenizer does.
///
/// `ruled` is consulted only when it describes these exact bytes; anything
/// else and it is ignored rather than trusted, which is the difference between
/// an index and a guess. One scanner reads many files, so a ruling left over
/// from the last one has to be refused by construction and not by discipline -
/// and the caller that installs one is then free to leave it installed, since
/// a ruling that stops describing the material stops being consulted.
pub fn lead(bytes: []const u8, at: u32, note: Note, ruled: ?*Ruling) Lead {
    if (ruled) |it| if (it.covers(bytes)) return walk(true, bytes, at, note, it);
    return walk(false, bytes, at, note, undefined);
}

/// The one body, specialized at comptime on whether a ruling is in hand.
///
/// The test is loop-invariant and the loop runs once a byte, so carrying it as
/// a runtime branch cost the arm *without* a ruling a fifth of its time for a
/// branch that could never be taken - the bench's `sweep` row sat behind the
/// byte walk it replaced, on every shape, until this split. Two specializations
/// of one body is still one body: there is nothing here for the two to drift
/// apart on, which is what a second implementation would have offered.
fn walk(comptime ruled: bool, bytes: []const u8, at: u32, note: Note, r: *Ruling) Lead {
    var k: u32 = if (ruled) r.at(at) else 0;
    var i = at;
    var column: u16 = 0;
    var fresh = false;
    var comment: ?u16 = null;
    while (i < bytes.len) {
        if (ruled) {
            const it = r;
            while (k + 1 < it.lines.items.len and it.lines.items[k + 1].start <= i) k += 1;
            const line = it.lines.items[k];
            if (i == line.start) switch (line.shape(note)) {
                .blank => {
                    i = it.after(k);
                    column = 0;
                    fresh = true;
                    continue;
                },
                .note => {
                    // A comment before any line ending is a trailing comment on
                    // the line we are already inside, and says nothing about
                    // indentation.
                    if (!fresh) return .{
                        .at = line.body,
                        .column = line.column,
                        .fresh = false,
                        .comment = null,
                        .broken = false,
                    };
                    if (comment == null) comment = line.column;
                    i = it.after(k);
                    column = 0;
                    continue;
                },
                .code => return .{
                    .at = line.body,
                    .column = line.column,
                    .fresh = fresh,
                    .comment = comment,
                    .broken = false,
                },
                .rough => {},
            };
        }
        switch (bytes[i]) {
            '\n' => {
                fresh = true;
                column = 0;
                i += 1;
            },
            ' ' => {
                // The one run in a leading region long enough to be worth a
                // block compare, and the only place the column arithmetic is
                // linear: a space is worth exactly one, so a run of them is
                // worth its length and there is nothing to iterate. A tab is
                // not folded in here because its stop is not additive - a run
                // of tabs and spaces would have to be walked anyway.
                const stop = sweep.past(bytes, i, " ");
                column +|= @intCast(@min(stop - i, std.math.maxInt(u16)));
                i = stop;
            },
            '\r', 0x0c => {
                column = 0;
                i += 1;
            },
            '\t' => {
                column = (column / tab_stop +| 1) *| tab_stop;
                i += 1;
            },
            '#', '/' => {
                const open = note.opens(bytes, i) orelse
                    return .{ .at = i, .column = column, .fresh = fresh, .comment = comment, .broken = false };
                if (!fresh) return .{ .at = i, .column = column, .fresh = false, .comment = null, .broken = false };
                if (comment == null) comment = column;
                const wide, const bounded = open;
                if (bounded) {
                    // A bounded comment can end mid-line, and then the code
                    // after it is the line's real content at its real column -
                    // what tree-sitter-scala calls the effective indentation.
                    // So the column is carried through the comment rather than
                    // reset, opener included: the `/*` is two columns the code
                    // sits after.
                    column +|= @intCast(wide);
                    i = through(bytes, i + wide, &column);
                } else {
                    i = sweep.find(bytes, i, "\n");
                    if (i < bytes.len) i += 1;
                    column = 0;
                }
            },
            '\\' => {
                // An explicit line join. The newline it swallows is not a line
                // ending for indentation purposes, so `fresh` deliberately
                // stays where it was.
                var j = i + 1;
                if (j < bytes.len and bytes[j] == '\r') j += 1;
                if (j >= bytes.len) return .{ .at = j, .column = column, .fresh = fresh, .comment = comment, .broken = false };
                if (bytes[j] != '\n') return .{ .at = i, .column = column, .fresh = fresh, .comment = comment, .broken = true };
                i = j + 1;
                column = 0;
            },
            else => return .{ .at = i, .column = column, .fresh = fresh, .comment = comment, .broken = false },
        }
    }
    // End of input is a line ending, and it is at column zero - which is what
    // unwinds every open block before the parse can accept.
    return .{ .at = i, .column = 0, .fresh = true, .comment = comment, .broken = false };
}

/// Walk past a bounded comment opened just before `i`, keeping `column` true.
///
/// Nesting is counted rather than assumed absent: scala's block comment nests,
/// so `/* /* */ */` ends at the second close and not the first. An unterminated
/// one runs to the end of input, which is the same answer the parse will reach
/// by another route and is better than pretending the file ended a line early.
///
/// The jump is to the next byte that can change something - a line ending, a
/// tab, or half of either delimiter - and everything between is plain text
/// worth one column apiece. A ruling cannot help here and deliberately holds
/// no comment spans: a block comment crosses lines, so a span table for it is
/// not locally spliceable and typing `/*` would re-derive the tail of the file.
pub fn through(bytes: []const u8, from: u32, column: *u16) u32 {
    var i = from;
    var depth: u32 = 1;
    while (i < bytes.len) {
        const stop = sweep.find(bytes, i, "\n\t/*");
        column.* +|= @intCast(@min(stop - i, std.math.maxInt(u16)));
        i = stop;
        if (i >= bytes.len) break;
        switch (bytes[i]) {
            '\n' => {
                column.* = 0;
                i += 1;
            },
            '\t' => {
                column.* = (column.* / tab_stop +| 1) *| tab_stop;
                i += 1;
            },
            '/' => {
                const nested = i + 1 < bytes.len and bytes[i + 1] == '*';
                column.* +|= if (nested) 2 else 1;
                i += if (nested) 2 else 1;
                if (nested) depth += 1;
            },
            // `*`, and only `*` - the jump above stops on nothing else.
            else => {
                const closing = i + 1 < bytes.len and bytes[i + 1] == '/';
                column.* +|= if (closing) 2 else 1;
                i += if (closing) 2 else 1;
                if (closing) {
                    depth -= 1;
                    if (depth == 0) return i;
                }
            },
        }
    }
    return i;
}

/// Both arms of one measurement, held to each other. Every fixture below goes
/// through this rather than through `lead` directly, so a shortcut that
/// diverges from the byte walk fails the test that was checking the byte walk.
fn both(src: []const u8, at: u32, note: Note) !Lead {
    const gpa = std.testing.allocator;
    var r = try Ruling.of(gpa, src);
    defer r.deinit(gpa);
    const cold = lead(src, at, note, null);
    try std.testing.expectEqual(cold, lead(src, at, note, &r));
    return cold;
}

test "measure: a tab reaches the next stop rather than adding one" {
    // The spec's arithmetic, not ours: tree-sitter-python's scanner adds eight
    // per tab, and CPython's tokenizer rounds up to the next multiple of eight.
    // Both agree on a tab at column zero and on a tab after four spaces.
    try std.testing.expectEqual(@as(u16, 8), (try both("\tx", 0, .hash)).column);
    try std.testing.expectEqual(@as(u16, 8), (try both("    \tx", 0, .hash)).column);
    try std.testing.expectEqual(@as(u16, 16), (try both("\t\tx", 0, .hash)).column);
}

test "measure: a blank line and a comment line do not end the measurement" {
    const src = "\n\n    # note\n        x";
    const got = try both(src, 0, .hash);
    try std.testing.expectEqual(@as(u16, 8), got.column);
    try std.testing.expectEqual(@as(?u16, 4), got.comment);
    try std.testing.expect(got.fresh);
    try std.testing.expectEqual(@as(u32, src.len - 1), got.at);
}

test "measure: a comment before any line ending is trailing, not leading" {
    // `foo = bar # note` must not open or close a block, which the spec spells
    // as returning early when no end of line has been crossed.
    const got = try both(" # note\nx", 0, .hash);
    try std.testing.expect(!got.fresh);
    try std.testing.expectEqual(@as(?u16, null), got.comment);
}

test "measure: a backslash joins the next line and keeps the column" {
    // The joined line's own indentation is not a block boundary.
    const got = try both("\n a \\\n        b", 0, .hash);
    try std.testing.expectEqual(@as(u16, 1), got.column);
    try std.testing.expect(!got.broken);
}

test "measure: a slashes measurement sees past a comment a hash one reads as code" {
    // The whole difference the `Note` field buys, pinned here because the
    // corpus cannot pin it: `Option.scala` opens 499 of its 628 lines with a
    // comment and still measures identically under both rules, because that
    // fixture has almost no indentation region for a column to be wrong about.
    // A field no measurement can falsify is a field that will be cited in a doc
    // comment as working, so it is falsified here instead.
    const src = "\n  /** doc */\n    body";
    const blind = try both(src, 0, .hash);
    try std.testing.expectEqual(@as(u16, 2), blind.column); // the comment's own column
    try std.testing.expectEqual(@as(?u16, null), blind.comment);

    const seeing = try both(src, 0, .slashes);
    try std.testing.expectEqual(@as(u16, 4), seeing.column); // the code's
    try std.testing.expectEqual(@as(?u16, 2), seeing.comment);
}

test "measure: a bounded comment ending mid-line yields the code's column" {
    // tree-sitter-scala's COMMENT_SAME_LINE_CODE branch: the line's content
    // starts after the comment, so its column is the effective indentation.
    const got = try both("\n  /* c */ body", 0, .slashes);
    try std.testing.expectEqual(@as(u16, 10), got.column);
    try std.testing.expect(got.fresh);
}

test "measure: a bounded comment nests, so the first close does not end it" {
    // C's does not and scala's does. Closing at the first `*/` would hand
    // ` still comment */` to the parser as code at a column it never had.
    const got = try both("\n/* /* x */ */ y", 0, .slashes);
    try std.testing.expectEqual(@as(u16, 14), got.column);
}

test "measure: a lone slash is division, not a comment" {
    // The `/` arm must not swallow an operator. `opens` returning null has to
    // leave the measurement exactly where the default arm would have.
    const got = try both("\n  a / b", 0, .slashes);
    try std.testing.expectEqual(@as(u16, 2), got.column);
    try std.testing.expectEqual(@as(?u16, null), got.comment);
}

test "measure: end of input is a line ending at column zero" {
    const got = try both("\n   ", 0, .hash);
    try std.testing.expect(got.fresh);
    try std.testing.expectEqual(@as(u16, 0), got.column);
}

test "measure: the two arms agree at every offset of an awkward file" {
    // Everything the record declines to state, in one file, at every offset -
    // carriage returns and form feeds inside a leading run, a continuation, a
    // block comment across lines, a file that ends mid-indent.
    const src =
        "def f():\r\n\t x = 1\n\n  # note\n" ++
        "  /* open\n   still open */ y\n" ++
        "  a \\\n      b\n\x0c  z\n  q \\ bad\n   ";
    for ([_]Note{ .hash, .slashes }) |note| {
        for (0..src.len + 1) |at| _ = try both(src, @intCast(at), note);
    }
}
