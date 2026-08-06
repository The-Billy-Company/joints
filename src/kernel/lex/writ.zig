//! Layout the parser *commands*, where the offside rule is layout a scanner
//! detects. Haskell's, and the inversion is the whole module.
//!
//! Python's scanner owns its block structure outright: it measures a line, it
//! compares against a stack it built itself, and the comparison is the token.
//! Nobody tells it when a block opens. Haskell's grammar spells the same
//! structure the other way round - `_body`, `_statements`, `alternatives` and
//! six more all read
//!
//!     SEQ( CHOICE(_cmd_layout_start_X | alias(_cmd_layout_start_explicit,"{")),
//!          item (CHOICE(";" | _cond_layout_semicolon) item)*,
//!          CHOICE(_cond_layout_end | alias(_cond_layout_end_explicit,"}")) )
//!
//! so the *parser* reaching a grammar position is what opens the block, and the
//! scanner's job is to execute that command and then answer questions against
//! the stack the command filled. A `_cmd_*` is not a measurement; it is an
//! order. That is why this cannot be `.offside` wearing other names, and it is
//! the exact unsoundness `outside.zig`'s header is about: the memory a hand
//! mutates is shared across the union of live readings, so an order issued on
//! one reading's behalf is executed in a stack every other reading also reads.
//!
//! ## The warrant
//!
//! `Gather` holds `scanner: *lex.Scanner` - one pointer, one `Carry` - and the
//! expected set it hands down is the *union* over `live.items`. So the rule a
//! hand has to clear is:
//!
//! > its answer and its mutation must be functions of the bytes and the memory
//! > alone, never of which reading admitted the terminal.
//!
//! The two halves of this protocol clear it by two different arguments, and
//! both are checked at runtime rather than asserted here.
//!
//! **The pops and the separator** are three arms of one comparison between the
//! measured column and the stack top - shallower ends the block, equal ends an
//! item, deeper is ordinary code - so at most one arm can hold and every reading
//! gets the same answer. That is Landin's argument and `.offside` already rests
//! on it. Co-admission with forty-five ordinary tokens is harmless because the
//! comparison partitions.
//!
//! **The pushes** cannot ride that argument, because a command carries no
//! measurement to compare. Instead a push is granted only when the command is
//! the *sole* terminal the union admits by shift - which means every live
//! reading issued the same order, so executing it once in the shared stack is
//! right for all of them. Where a rival stands, this hand declines and the parse
//! proceeds exactly as it did before the seat existed. `unanimous` is that test,
//! and it is why the type is named for a warrant: an order carried out on the
//! authority of the whole bench, or not at all.
//!
//! Measured over haskell's 3543 states: 56 admit a `_cmd_*` by shift, 51 admit
//! nothing else, and **no state admits two implicit variants at once** - so
//! nothing here ever asks the bytes to tell `do` from `case`. The five it
//! declines are a headerless module, `let … in`, an empty quotation, and
//! multi-way `if`.
//!
//! ## What is deliberately not here
//!
//! The Report's `parse-error(t)` rule, which the grammar enumerates as five
//! `_phantom_*` terminals. Every state admitting one also admits the keyword it
//! stands before - `_phantom_where` beside `where`, `_phantom_in` beside `in` -
//! so no function of the bytes can separate them; deciding needs to know whether
//! the parse would fail, which is the parser's knowledge. They are optional in
//! every rule they appear in (`CHOICE(_phantom_X | BLANK)`), so declining them
//! costs constructs and not the protocol.
//!
//! Derived from the Haskell 2010 Report §10.3 (the `L` function) and from
//! tree-sitter-haskell's `scanner.c` read as a specification for which of the
//! Report's cases its grammar actually spells. Nothing is linked; those two are
//! the spec and this is the implementation.

const std = @import("std");

const offside = @import("offside.zig");

/// The column an explicit `{ … }` frame is stored at.
///
/// A brace-opened block is closed by `}` and by nothing else - the Report is
/// explicit that the offside rule does not apply inside one - so its frame has
/// to be tellable from a measured column, and one stack is much better than two
/// parallel ones that can disagree. `maxInt` is the choice because a column only
/// reaches it through `+|=` saturating on a line of 65,535 leading spaces, and a
/// frame that wide read as explicit is *refused* a column-driven close rather
/// than given a wrong one. The failure direction is silence.
pub const sealed: u16 = std.math.maxInt(u16);

/// Haskell's symbol class, which is what decides whether `--` opens a comment.
///
/// The Report's `dashes` lexeme is two or more dashes **not** followed by a
/// symbol, so `-->` and `--|` are operators and only `--` and `-- x` are
/// comments. Getting this wrong swallows the rest of a line of real code, which
/// is the one mistake here that would move bytes into a plausible tree.
fn symbolic(b: u8) bool {
    return switch (b) {
        '!', '#', '$', '%', '&', '*', '+', '.', '/', '<' => true,
        '=', '>', '?', '@', '\\', '^', '|', '-', '~', ':' => true,
        else => false,
    };
}

/// What the next lexeme's position came to, and whether a line ended first.
pub const Lead = struct {
    /// The offset of the next significant byte.
    at: u32,
    /// Its column, tabs expanded to the next stop.
    column: u16,
    /// Whether a line ending (or the end of input) was crossed getting here.
    /// Layout is only ever measured across one, which is what keeps `f x` on a
    /// continuation line from being read as a new item.
    fresh: bool,
};

/// Measure the next lexeme, skipping whitespace and both comment forms.
///
/// Comments are skipped rather than reported, unlike `offside.lead`, because
/// Haskell has no clause deferring a close to a comment's own indentation: the
/// Report's `L` runs over a token stream a comment never enters. A comment is
/// therefore invisible here rather than a special case, and a `{-` is consumed
/// as a comment before any `{` can be read as a layout brace.
pub fn ahead(bytes: []const u8, at: u32) Lead {
    var i = at;
    var column: u16 = 0;
    var fresh = false;
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
            column = (column / offside.tab_stop +| 1) *| offside.tab_stop;
            i += 1;
        },
        '-' => {
            // Two or more dashes, then anything that is not a symbol. One dash
            // is subtraction and three is still a comment.
            var j = i;
            while (j < bytes.len and bytes[j] == '-') j += 1;
            if (j - i < 2 or (j < bytes.len and symbolic(bytes[j]))) break;
            while (j < bytes.len and bytes[j] != '\n') j += 1;
            i = j;
        },
        '{' => {
            if (i + 1 >= bytes.len or bytes[i + 1] != '-') break;
            // Nested, per the Report: `{- {- -} -}` is one comment. An unclosed
            // one runs to the end of input, which is what the bytes say.
            var j = i + 2;
            var deep: u32 = 1;
            while (j < bytes.len and deep > 0) {
                if (j + 1 < bytes.len and bytes[j] == '{' and bytes[j + 1] == '-') {
                    deep += 1;
                    j += 2;
                } else if (j + 1 < bytes.len and bytes[j] == '-' and bytes[j + 1] == '}') {
                    deep -= 1;
                    j += 2;
                } else {
                    if (bytes[j] == '\n') {
                        fresh = true;
                        column = 0;
                    }
                    j += 1;
                }
            }
            i = j;
        },
        else => break,
    };
    if (i >= bytes.len) return .{ .at = @intCast(bytes.len), .column = 0, .fresh = true };
    return .{ .at = i, .column = column, .fresh = fresh };
}

/// Where a measured column stands against the innermost open block.
pub const Standing = enum {
    /// Shallower than the block opened: the block is over.
    left,
    /// Level with it: this line begins a new item in the same block.
    level,
    /// Deeper, or inside an explicit frame, or no block open at all. Ordinary
    /// code, and this hand has nothing to say.
    inside,
};

/// Read a column against the stack top. The whole of the pop-and-separate half
/// of the protocol, and a total function of the column and the memory - which is
/// what lets it answer under a shared carry no matter how many readings are live.
pub fn standing(columns: *const offside.Columns, column: u16, fresh: bool) Standing {
    if (columns.len == 0) return .inside;
    const top = columns.top();
    // Inside `{ … }` the offside rule is suspended outright, so no measurement
    // of any line can end the frame - only its `}`.
    if (top == sealed) return .inside;
    // Without a line ending there is no new line to measure. A `where` sharing
    // a line with the declaration it follows says nothing about layout.
    if (!fresh) return .inside;
    if (column < top) return .left;
    return if (column == top) .level else .inside;
}

test "writ: a sealed frame is never closed by a column" {
    var columns: offside.Columns = .{};
    try std.testing.expect(columns.open(sealed));
    // Column zero is as far left as a line can be, and it still may not end an
    // explicit block. The Report suspends the offside rule inside braces.
    try std.testing.expectEqual(Standing.inside, standing(&columns, 0, true));
}

test "writ: the three arms partition, so at most one can hold" {
    var columns: offside.Columns = .{};
    try std.testing.expect(columns.open(4));
    try std.testing.expectEqual(Standing.left, standing(&columns, 2, true));
    try std.testing.expectEqual(Standing.level, standing(&columns, 4, true));
    try std.testing.expectEqual(Standing.inside, standing(&columns, 6, true));
    // No line ending crossed: a continuation, not a new item, whatever the
    // column says.
    try std.testing.expectEqual(Standing.inside, standing(&columns, 4, false));
}

test "writ: an empty stack has nothing to say" {
    const columns: offside.Columns = .{};
    try std.testing.expectEqual(Standing.inside, standing(&columns, 0, true));
}

test "writ: dashes are a comment only when no symbol follows" {
    // `-->` is an operator, so the lexeme starts at the first dash.
    try std.testing.expectEqual(@as(u32, 0), ahead("-->x", 0).at);
    try std.testing.expectEqual(@as(u32, 0), ahead("--|x", 0).at);
    // One dash is subtraction.
    try std.testing.expectEqual(@as(u32, 0), ahead("- x", 0).at);
    // Two or more with a non-symbol after is a comment to end of line.
    const past = ahead("-- note\n  x", 0);
    try std.testing.expectEqual(@as(u16, 2), past.column);
    try std.testing.expect(past.fresh);
    try std.testing.expectEqual(@as(u32, 10), past.at);
    // Three dashes is still a comment, which is how `--- x` is written.
    try std.testing.expectEqual(@as(u32, 9), ahead("--- note\nx", 0).at);
}

test "writ: a block comment nests and does not open a layout frame" {
    // The `{` here belongs to a comment, so the lexeme after it is `x` - not a
    // brace this hand could mistake for an explicit block.
    const past = ahead("{- {- deep -} -} x", 0);
    try std.testing.expectEqual(@as(u32, 17), past.at);
    try std.testing.expect(!past.fresh);
    // A real brace is left alone for the caller to read.
    try std.testing.expectEqual(@as(u32, 0), ahead("{ x", 0).at);
    // Unclosed runs to the end of input rather than guessing a close.
    try std.testing.expectEqual(@as(u32, 8), ahead("{- open ", 0).at);
}

test "writ: a newline inside a block comment still ends the line" {
    // The Report's `L` sees a token stream, so a comment spanning lines leaves
    // the *next* token measurable against the block it may be leaving.
    const past = ahead("{- a\n b -}\nx", 0);
    try std.testing.expect(past.fresh);
    try std.testing.expectEqual(@as(u16, 0), past.column);
    try std.testing.expectEqual(@as(u32, 11), past.at);
}

test "writ: end of input is column zero on a fresh line" {
    // Which is what unwinds every block a file left open before it can accept.
    const past = ahead("   ", 0);
    try std.testing.expect(past.fresh);
    try std.testing.expectEqual(@as(u16, 0), past.column);
}

test "writ: a tab reaches the next stop, as the offside rule counts it" {
    // Shared with `offside` on purpose: the Report leaves tab width to the
    // implementation and both scanners we read as specs use eight.
    try std.testing.expectEqual(@as(u16, 8), ahead("\n\tx", 0).column);
}
