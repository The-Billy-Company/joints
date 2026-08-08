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
//! ## Where the measurement went
//!
//! The other half of this file used to be the byte walk that reads a line's
//! leading run, and it is now `kernel/grain/measure.zig`. That is not a move
//! for tidiness: the walk has no memory at all - it is a function of the bytes
//! at an offset and nothing else - and it was the one thing here a vectorized
//! pass over the raw material could answer whole. What is left is the half that
//! genuinely cannot be: the stack, which every previous line built.
//!
//! `Note` and `tab_stop` are re-exported below because the hands next door
//! spell them that way and the rule they describe is this one's - a tab stop is
//! a fact about the offside rule that grain happens to be the one measuring.
//! `lead`, `through` and `Lead` are *not* re-exported: nothing outside grain
//! calls them any more, and an alias nobody writes is a second name to keep in
//! step for no reader's benefit.
//!
//! Derived from tree-sitter-python's own `scanner.c` read as a specification -
//! the column arithmetic (a tab is worth eight, a carriage return and a form
//! feed reset to zero), the rule that a comment line defers a dedent until its
//! indentation drops below the current block, and the guard that a trailing
//! comment on an expression line emits nothing at all. Nothing is linked; the
//! C file is the spec and this is the implementation.

const std = @import("std");
const grain = @import("../../grain/grain.zig");

pub const tab_stop = grain.tab_stop;
pub const Note = grain.Note;

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
