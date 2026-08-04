//! The offside rule: a stack of columns, and the three tokens it emits.
//!
//! Landin's name for it, and Python's whole block structure. A line's leading
//! width is compared against the column the enclosing block opened at, and the
//! comparison - not any byte - is the token: deeper opens a block, shallower
//! closes one, equal ends a statement. Two of the three consume nothing at all.
//!
//! This is the shape no slate can host and no table of spellings can stand in
//! for, and it is worth being exact about why rather than filing it under
//! "hard". A regex is a function of the bytes at an offset. `_indent` is a
//! function of the bytes at an offset *and a stack built by every line before
//! it* - the same four spaces open a block on one line and close two on the
//! next. So the memory has to outlive the token, which is what `Carry` is.
//!
//! Zero width is the second reason, and it is the one that decides the seam.
//! `scanner.reach` throws away a zero-length match on purpose: a slate terminal
//! that accepts the empty string pins the scan at one offset forever, because
//! nothing in a regex can promise the next call will answer differently. A hand
//! written scanner can promise it, because it holds the state that changes:
//! every `_dedent` pops a column, so a run of them is finite by construction
//! and the stack is the proof. `outside.step` is where that proof is checked.
//!
//! Derived from tree-sitter-python's own `scanner.c` read as a specification -
//! the column arithmetic (a tab is worth eight, a carriage return and a form
//! feed reset to zero), the rule that a comment line defers a dedent until its
//! indentation drops below the current block, and the guard that a trailing
//! comment on an expression line emits nothing at all. Nothing is linked; the
//! C file is the spec and this is the implementation.

const std = @import("std");

/// A tab advances to the next multiple of this. Python's own tokenizer and
/// tree-sitter's scanner both use eight, so a file mixing tabs and spaces
/// blocks the same way here as it does there.
pub const tab_stop = 8;

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
pub fn lead(bytes: []const u8, at: u32) Lead {
    var i = at;
    var column: u16 = 0;
    var fresh = false;
    var comment: ?u16 = null;
    while (i < bytes.len) switch (bytes[i]) {
        '\n' => {
            fresh = true;
            column = 0;
            i += 1;
        },
        ' ' => {
            column +|= 1;
            i += 1;
        },
        '\r', 0x0c => {
            column = 0;
            i += 1;
        },
        '\t' => {
            column = (column / tab_stop +| 1) *| tab_stop;
            i += 1;
        },
        '#' => {
            // A comment before any line ending is a trailing comment on the
            // line we are already inside, and says nothing about indentation.
            if (!fresh) return .{ .at = i, .column = column, .fresh = false, .comment = null, .broken = false };
            if (comment == null) comment = column;
            while (i < bytes.len and bytes[i] != '\n') i += 1;
            if (i < bytes.len) i += 1;
            column = 0;
        },
        '\\' => {
            // An explicit line join. The newline it swallows is not a line
            // ending for indentation purposes, so `fresh` deliberately stays
            // where it was.
            var j = i + 1;
            if (j < bytes.len and bytes[j] == '\r') j += 1;
            if (j >= bytes.len) return .{ .at = j, .column = column, .fresh = fresh, .comment = comment, .broken = false };
            if (bytes[j] != '\n') return .{ .at = i, .column = column, .fresh = fresh, .comment = comment, .broken = true };
            i = j + 1;
            column = 0;
        },
        else => return .{ .at = i, .column = column, .fresh = fresh, .comment = comment, .broken = false },
    };
    // End of input is a line ending, and it is at column zero - which is what
    // unwinds every open block before the parse can accept.
    return .{ .at = i, .column = 0, .fresh = true, .comment = comment, .broken = false };
}

/// The column stack.
///
/// The module's own column zero is the floor and is not stored: a `_dedent`
/// past it would be a block nobody opened, so `top` of an empty stack is zero
/// and `close` of an empty stack does nothing.
///
/// Fixed capacity, which is a decision rather than a shortcut. It keeps the
/// whole external seam infallible, so `Scanner.next` stays the infallible
/// function every caller already relies on, and no allocator has to be
/// threaded down a hot path to hold ninety-six numbers. Ninety-six is far past
/// any nesting a person writes and past what tree-sitter can serialize; a file
/// deeper than that declines to open further rather than lying about it.
pub const Columns = struct {
    deep: [max]u16 = undefined,
    len: u8 = 0,

    pub const max = 96;

    pub fn reset(c: *Columns) void {
        c.len = 0;
    }

    /// Whether two stacks are the same lexical state.
    ///
    /// `deep` past `len` is `undefined`, so a byte or field comparison of two
    /// stacks that are semantically identical can answer no - in a release
    /// build it compares whatever was on the stack. Flattening the dead tail
    /// first is what makes the answer about the state rather than about the
    /// memory, and doing it through `std.meta.eql` rather than by listing the
    /// live fields means a field added later is compared without anyone
    /// remembering to come back here.
    pub fn same(a: *const Columns, b: *const Columns) bool {
        return std.meta.eql(a.flat(), b.flat());
    }

    fn flat(c: *const Columns) Columns {
        var out = c.*;
        @memset(out.deep[out.len..], 0);
        return out;
    }

    pub fn top(c: *const Columns) u16 {
        return if (c.len == 0) 0 else c.deep[c.len - 1];
    }

    /// One more than the number of open blocks, counting the module's floor,
    /// so that a change in it is visible to the progress guard.
    pub fn depth(c: *const Columns) u32 {
        return @as(u32, c.len) + 1;
    }

    pub fn open(c: *Columns, column: u16) bool {
        if (c.len == max) return false;
        c.deep[c.len] = column;
        c.len += 1;
        return true;
    }

    pub fn close(c: *Columns) void {
        if (c.len > 0) c.len -= 1;
    }
};

test "offside: a tab reaches the next stop rather than adding one" {
    // The spec's arithmetic, not ours: tree-sitter-python's scanner adds eight
    // per tab, and CPython's tokenizer rounds up to the next multiple of eight.
    // Both agree on a tab at column zero and on a tab after four spaces.
    try std.testing.expectEqual(@as(u16, 8), lead("\tx", 0).column);
    try std.testing.expectEqual(@as(u16, 8), lead("    \tx", 0).column);
    try std.testing.expectEqual(@as(u16, 16), lead("\t\tx", 0).column);
}

test "offside: a blank line and a comment line do not end the measurement" {
    const src = "\n\n    # note\n        x";
    const got = lead(src, 0);
    try std.testing.expectEqual(@as(u16, 8), got.column);
    try std.testing.expectEqual(@as(?u16, 4), got.comment);
    try std.testing.expect(got.fresh);
    try std.testing.expectEqual(@as(u32, src.len - 1), got.at);
}

test "offside: a comment before any line ending is trailing, not leading" {
    // `foo = bar # note` must not open or close a block, which the spec spells
    // as returning early when no end of line has been crossed.
    const got = lead(" # note\nx", 0);
    try std.testing.expect(!got.fresh);
    try std.testing.expectEqual(@as(?u16, null), got.comment);
}

test "offside: a backslash joins the next line and keeps the column" {
    // The joined line's own indentation is not a block boundary.
    const got = lead("\n a \\\n        b", 0);
    try std.testing.expectEqual(@as(u16, 1), got.column);
    try std.testing.expect(!got.broken);
}

test "offside: end of input is a line ending at column zero" {
    const got = lead("\n   ", 0);
    try std.testing.expect(got.fresh);
    try std.testing.expectEqual(@as(u16, 0), got.column);
}
