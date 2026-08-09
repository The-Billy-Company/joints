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
//! ## The third arm: a keyword ends a block
//!
//! Neither half above reaches a `where`. It is indented *deeper* than the block
//! it closes - which is how every Haskell file in the world writes one - so the
//! column rule reads `.inside`, the block stays open, `where` is never admitted
//! as a keyword, and the parser takes the only reading left to it: a variable.
//! That was 18 of the 26 remaining misread runs on the pandoc fixture, and no
//! measurement of any column reaches it, because no column licenses the close.
//!
//! The Report licenses it, as `parse-error(t)`: a layout ends when the next token
//! would be a parse error. A scanner cannot ask whether a parse would fail, but it
//! is handed the next best thing every time it is asked - the permission set. So
//! the arm is: the block's close is admissible, and the word at the next lexeme is
//! a keyword this grammar spells that the parse would **not** take. See
//! `outside.tailed`.
//!
//! This clears the same warrant the pushes do, from the other side. A close
//! happens only on a keyword *absent* from the union of live readings, so if any
//! reading would take it, none of them wants the block closed and the hand stands
//! down. Unanimity by absence. And it needs no per-language table: a keyword is a
//! literal terminal whose spelling is a word, which the grammar already says.
//!
//! ## What is deliberately not here
//!
//! The five `_phantom_*` terminals the grammar spells for the *other* half of
//! `parse-error(t)` - the phantom that stands beside the keyword rather than the
//! close that precedes it. Every state admitting one also admits the keyword it
//! stands before, so no function of the bytes can separate them. They are optional
//! in every rule they appear in (`CHOICE(_phantom_X | BLANK)`), so declining them
//! costs constructs and not the protocol.
//!
//! Derived from the Haskell 2010 Report §10.3 (the `L` function) and from
//! tree-sitter-haskell's `scanner.c` read as a specification for which of the
//! Report's cases its grammar actually spells. Nothing is linked; those two are
//! the spec and this is the implementation.

const std = @import("std");

const offside = @import("offside.zig");

/// The lowest frame value that is a marker rather than a measured column.
///
/// Three of the frames on this stack are not indentation at all - an explicit
/// `{ … }` layout block and the two bracket orders below - and none of them may
/// be closed by a line's indentation. Storing them as reserved columns keeps one
/// stack where the alternative is four parallel ones that can disagree about
/// nesting order, and nesting order is the whole question a bracket asks.
///
/// The top of the range is the choice because a column only reaches it through
/// `+|=` saturating on a line of 65,533 leading spaces, and a frame that wide
/// read as a marker is *refused* a column-driven close rather than given a wrong
/// one. The failure direction is silence.
pub const marker: u16 = std.math.maxInt(u16) - 2;

/// A record `{ … }` the parser ordered open: haskell's `Braces` context.
pub const braced: u16 = marker;

/// A tuple-expression bracket the parser ordered open: haskell's `TExp`.
///
/// The sort exists because `(`, `[` and a guard's `|` delimit their contents
/// unambiguously, which lets a layout inside one be closed by the delimiter
/// rather than by a column - see `bracketed`.
pub const fenced: u16 = marker + 1;

/// The column an explicit `{ … }` layout frame is stored at.
///
/// A brace-opened block is closed by `}` and by nothing else - the Report is
/// explicit that the offside rule does not apply inside one.
pub const sealed: u16 = marker + 2;

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

/// Whether `word` stands whole at `at` - the bytes match and no identifier
/// character follows.
///
/// The Report's `varid` continues over letters, digits, `_` and `'`, so `wheres`
/// and `where'` are one name and only `where` is the keyword. Reading the prefix
/// alone would close a block on every identifier that happens to start with one
/// of these four words, which on the pandoc corpus is `elsewhere` and `intern`.
///
/// A byte test rather than a lexeme one on purpose: this is asked at a position
/// `ahead` has already walked to, so the left boundary is established and only
/// the right one is in question.
pub fn word(bytes: []const u8, at: u32, it: []const u8) bool {
    if (at + it.len > bytes.len) return false;
    if (!std.mem.eql(u8, bytes[at .. at + it.len], it)) return false;
    const after = at + @as(u32, @intCast(it.len));
    if (after == bytes.len) return true;
    return switch (bytes[after]) {
        'a'...'z', 'A'...'Z', '0'...'9', '_', '\'' => false,
        else => true,
    };
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
    // of any line can end the frame - only its `}`. A bracket order is not a
    // block at all and has no column to be measured against, so the same
    // silence is the right answer for all three markers.
    if (top >= marker) return .inside;
    // Without a line ending there is no new line to measure. A `where` sharing
    // a line with the declaration it follows says nothing about layout.
    if (!fresh) return .inside;
    if (column < top) return .left;
    return if (column == top) .level else .inside;
}

/// Whether the open blocks stand inside a bracket the parser ordered.
///
/// The clause that makes a bracket order worth seating rather than merely
/// possible. `(case a of a -> a, do a; a)` opens two layouts inside one `(`,
/// and neither of them can be closed by a column: the `)` is on the same line
/// as the block it ends, so `standing` reads `.inside` forever and both frames
/// are stranded. A stranded marker is worse than an unseated one, because a
/// marker on top silences the offside rule for the rest of the file.
///
/// The Report has no clause for this; GHC gets it from `parse-error(t)`, and
/// tree-sitter-haskell encodes it as the `TExp` sort precisely so a delimiter
/// can end a layout. So the test is a *stack* test, not a column one: are the
/// frames above the innermost bracket all layouts? If they are, the delimiter
/// that closes the bracket closes them first, one per call.
///
/// Total over the memory alone, which is what lets it answer under a carry
/// shared by every live reading - the same argument `standing` rests on.
pub fn bracketed(columns: *const offside.Columns) bool {
    // The top has to be a layout, or there is nothing here to close.
    if (columns.len < 2 or columns.top() >= marker) return false;
    var i = columns.len - 1;
    while (i > 0) {
        i -= 1;
        switch (columns.deep[i]) {
            braced, fenced => return true,
            // An explicit block is a wall: its `}` owes the close, and a
            // delimiter outside it may not reach past one.
            sealed => return false,
            else => {},
        }
    }
    return false;
}

test "writ: a bracket closes the layouts opened inside it" {
    var columns: offside.Columns = .{};
    try std.testing.expect(columns.open(fenced));
    try std.testing.expect(columns.open(4)); // `do` inside the bracket
    try std.testing.expect(bracketed(&columns));
    // Two deep is still inside it - `(case a of a -> a, do a; a)`.
    try std.testing.expect(columns.open(9));
    try std.testing.expect(bracketed(&columns));
}

test "writ: a bracket with nothing open inside it closes nothing" {
    var columns: offside.Columns = .{};
    try std.testing.expect(columns.open(fenced));
    // The bracket is the top, so there is no layout for a delimiter to end -
    // the delimiter's own order pops the bracket instead.
    try std.testing.expect(!bracketed(&columns));
}

test "writ: an explicit block walls a delimiter off from the bracket" {
    var columns: offside.Columns = .{};
    try std.testing.expect(columns.open(fenced));
    try std.testing.expect(columns.open(sealed));
    try std.testing.expect(columns.open(4));
    // The `}` owes this close, not the `)`. Reaching past the wall would end a
    // block the file explicitly bracketed.
    try std.testing.expect(!bracketed(&columns));
}

test "writ: a layout with no bracket under it is the ordinary case" {
    var columns: offside.Columns = .{};
    try std.testing.expect(columns.open(0));
    try std.testing.expect(columns.open(4));
    try std.testing.expect(!bracketed(&columns));
}

test "writ: every marker suspends the column rule, not only the sealed one" {
    for ([_]u16{ braced, fenced, sealed }) |frame| {
        var columns: offside.Columns = .{};
        try std.testing.expect(columns.open(frame));
        try std.testing.expectEqual(Standing.inside, standing(&columns, 0, true));
    }
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

test "writ: a keyword is only a keyword whole" {
    try std.testing.expect(word("where x", 0, "where"));
    try std.testing.expect(word("where", 0, "where"));
    try std.testing.expect(word("where}", 0, "where"));
    // A longer identifier that begins with it is not it, in either direction.
    try std.testing.expect(!word("wheres", 0, "where"));
    try std.testing.expect(!word("where'", 0, "where"));
    try std.testing.expect(!word("where2", 0, "where"));
    try std.testing.expect(!word("where_", 0, "where"));
    try std.testing.expect(!word("wher", 0, "where"));
    // And a run of one of the shorter ones inside a longer name: `intern`.
    try std.testing.expect(!word("intern", 0, "in"));
    try std.testing.expect(word("in x", 0, "in"));
}

test "writ: a tab reaches the next stop, as the offside rule counts it" {
    // Shared with `offside` on purpose: the Report leaves tab width to the
    // implementation and both scanners we read as specs use eight.
    try std.testing.expectEqual(@as(u16, 8), ahead("\n\tx", 0).column);
}
