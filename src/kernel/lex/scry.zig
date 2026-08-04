//! A token whose extent is not the bytes that decided it.
//!
//! The fourth shape, after `offside`'s column stack, `fence`'s span stack and
//! `marrow`'s bounded run - and like `marrow` it carries nothing. What is new
//! here is the *direction of the evidence*. Every other hand answers "how far
//! does this run go", reading forward until it finds its own end. This one
//! answers "which of my cohort is this, and how much of it do I claim", and to
//! do that it reads past bytes it will not take and then throws the reading
//! away. So an answer can be one byte wide, or none, at an offset past a run
//! the hand stepped over rather than consumed.
//!
//! Two languages, and they arrive at the shape from opposite ends.
//!
//! **css** cannot be a regex or a parse state. `a:hover { }` and `a: hover;`
//! differ in one place and it is nowhere near the colon: a declaration ends at
//! `;`, a rule opens at `{`, and until one of those arrives the two are the
//! same bytes. The deciding byte is unboundedly far away, and both readings
//! stay live for exactly as long as the ambiguity does. So the scanner looks
//! ahead, decides, and reports a one-byte token - or, for the whitespace that
//! is a descendant combinator, a *no*-byte token past the run it skipped.
//!
//! **toml** needs the same two liberties for a much plainer reason. Its
//! `_line_ending_or_eof` is a pure assertion - the grammar spells the newline
//! itself, in `REPEAT(pair | /\r?\n/)`, so the external claims nothing and
//! exists only to say a line may end here. And its multiline strings decide
//! *which* terminal a run of quotes is by counting the run: one or two are
//! content, three are the close, four or more are content again and only the
//! first is claimed. Same bytes, different symbol, chosen by a length the
//! grammar cannot express.
//!
//! What both need beyond the other hands is a `skip`, and it is the same field
//! for both: the bytes between the offset the hand was asked at and where its
//! token begins, which is tree-sitter's `advance(lexer, true)`.
//!
//! A hand may also answer at width zero, and needs no memory to do it, as long
//! as the *extent* - `skip + len` - is not also zero. `outside.step` is written
//! over the sum for exactly that reason. css's combinator and toml's line
//! ending are the two sides of it: the first claims nothing four bytes along,
//! the second claims nothing where it stands, and the second is safe only
//! because the parse state that wanted it stops wanting it once it is shifted.
//!
//! **haskell** arrives here from a third direction, and it is the one that says
//! the shape is not a two-language coincidence. Its four extras - `comment`,
//! `haddock`, `cpp`, `pragma` - are one region read four ways. A `--` run and a
//! `{-` open the same span whether the payload is documentation or not; what
//! decides is a `|` or a `^` some spaces past the mark, which the extent then
//! does not include. So the deciding bytes are inside the claim rather than past
//! it, and the answer is still "which of my cohort is this", which is this
//! hand's question and no other hand's.
//!
//! Those four are the whole of haskell this file answers, and the boundary is
//! sharp rather than a budget. The other forty-four are its layout algorithm,
//! and that is not an `offside` column stack with more fields on it: haskell's
//! `process_token_safe` switches on a thirty-eight member classification of the
//! *next* token, and `where`, `in`, `then`, `else`, `deriving`, `|`, `->` and
//! any symbolic operator each close a layout by their own rule. On a real
//! haskell file 35% of non-blank lines open with one of those classes, so a hand
//! that compared columns and nothing else would not fall silent on them - it
//! would nest them wrongly, which is the one kind of answer worth less than
//! none.
//!
//! Transcribed from the pinned `tree-sitter-css`, `tree-sitter-toml` and
//! `tree-sitter-haskell` `scanner.c`. The first two are a hundred lines or
//! fewer, neither has a struct, and both `create` return NULL. haskell's does
//! have a struct, and this file reads only the four functions that never touch
//! it. Nothing is linked.

const std = @import("std");

/// Which language's convention. Not a language check at the call site: the row
/// that names it was seated by its whole cohort being declared.
pub const Dialect = enum { css, toml, haskell };

/// Which member of the cohort the lookahead settled on, and where it lands.
///
/// `slot` indexes the row's cohort in the order the C file's own enum spells
/// it, which is the same order the grammar declares its externals in - the
/// correspondence is positional and exact, and it is what lets one hand answer
/// two languages without either one's names appearing here.
pub const Cut = struct {
    slot: u8,
    /// Bytes stepped over and not claimed.
    skip: u32,
    /// Bytes claimed. Zero is legal when `skip` is not.
    len: u32,
};

/// css slots, in `tree-sitter-css`'s enum order.
const css_descendant = 0;
const css_colon = 1;

/// haskell slots, in `tree-sitter-haskell`'s enum order.
const hs_comment = 0;
const hs_haddock = 1;
const hs_cpp = 2;
const hs_pragma = 3;

/// toml slots, in `tree-sitter-toml`'s enum order.
const toml_line_ending = 0;
const toml_basic_content = 1;
const toml_basic_end = 2;
const toml_literal_content = 3;
const toml_literal_end = 4;

/// The token at `at`, if one of this dialect's cohort is here.
///
/// `want` is a bitmask over the slots, which is the `valid_symbols` the C
/// function branches on; `veto` is css's error-recovery refusal, which the spec
/// applies before reading anything because a lookahead over broken bytes
/// settles nothing.
pub fn look(d: Dialect, bytes: []const u8, at: u32, want: u8, veto: bool) ?Cut {
    if (veto or at > bytes.len) return null;
    return switch (d) {
        .css => css(bytes, at, want),
        .toml => toml(bytes, at, want),
        .haskell => haskell(bytes, at, want),
    };
}

fn asked(want: u8, slot: u8) bool {
    return want & (@as(u8, 1) << @intCast(slot)) != 0;
}

/// css: the descendant combinator and the pseudo-class colon.
///
/// One function with three exits rather than two predicates a caller tries in
/// turn, because the spec's order is load-bearing in a way a caller could not
/// reproduce: the combinator goes first, and its own colon branch *fails the
/// whole call* rather than falling through, so the colon in `a :hover;` is
/// neither token.
fn css(bytes: []const u8, at: u32, want: u8) ?Cut {
    if (asked(want, css_descendant) and at < bytes.len and space(bytes[at])) {
        var i = at;
        while (i < bytes.len and space(bytes[i])) i += 1;
        const cut: Cut = .{ .slot = css_descendant, .skip = i - at, .len = 0 };
        if (i < bytes.len) switch (bytes[i]) {
            '#', '.', '[', '-', '*' => return cut,
            ':' => return if (combines(bytes, i + 1)) cut else null,
            else => if (std.ascii.isAlphanumeric(bytes[i])) return cut,
        };
    }

    if (asked(want, css_colon)) {
        var i = at;
        while (i < bytes.len and space(bytes[i])) i += 1;
        if (i >= bytes.len or bytes[i] != ':') return null;
        // `::before` is a pseudo-element, which the grammar spells itself.
        if (i + 1 < bytes.len and bytes[i + 1] == ':') return null;
        if (!selects(bytes, i + 1)) return null;
        return .{ .slot = css_colon, .skip = i - at, .len = 1 };
    }

    return null;
}

/// Whether the colon after a whitespace run still leaves a descendant
/// combinator in front of it: `a :hover { }` is two selectors, `a :hover;` is
/// nothing anyone meant.
///
/// End of input is *false* here, and true in `selects` twenty lines down. That
/// looks like an inconsistency and is the spec's: a combinator needs a second
/// selector to combine with, so a file that stops before the brace never had
/// one, while a bare pseudo-class is still the best reading of a truncated
/// selector. The two loops differ in three more ways, which is why they are
/// two loops.
fn combines(bytes: []const u8, from: u32) bool {
    if (from < bytes.len and space(bytes[from])) return false;
    var i = from;
    while (i < bytes.len) : (i += 1) switch (bytes[i]) {
        ';', '}' => return false,
        '{' => return true,
        else => {},
    };
    return false;
}

/// Whether what follows a selector's colon opens a rule rather than closing a
/// declaration: a `{` before any `;` or `}`.
///
/// A comment is stepped over rather than read, so the `{` in `a:hover /* { */`
/// does not open one. The flag guards only the brace, so a `}` inside a comment
/// *does* end the search - the spec's own asymmetry, kept because a lexer that
/// is more careful than the grammar it is standing in for is a lexer that
/// disagrees with it.
///
/// End of input is true. That is the spec's note as well as its code: a
/// truncated file reads better as an unfinished selector than as a malformed
/// property, because the selector is what the author was in the middle of.
fn selects(bytes: []const u8, from: u32) bool {
    var i = from;
    var commented = false;
    while (i < bytes.len and bytes[i] != ';' and bytes[i] != '}') {
        i += 1;
        if (i >= bytes.len) break;
        if (bytes[i] == '{' and !commented) return true;
        if (bytes[i] == '/' and !commented) {
            i += 1;
            if (i < bytes.len and bytes[i] == '*') commented = true;
        } else if (bytes[i] == '*' and commented) {
            i += 1;
            if (i < bytes.len and bytes[i] == '/') commented = false;
        }
    }
    return i >= bytes.len;
}

/// toml: a run of string delimiters, then the line ending.
///
/// The spec's order, and it matters: a `"""` closing a multiline string sits
/// where a line ending could also be asked for, and the string has to win or
/// the close is never read.
fn toml(bytes: []const u8, at: u32, want: u8) ?Cut {
    if (quotes(bytes, at, want, '"', toml_basic_content, toml_basic_end)) |cut| return cut;
    if (quotes(bytes, at, want, '\'', toml_literal_content, toml_literal_end)) |cut| return cut;

    if (asked(want, toml_line_ending)) {
        var i = at;
        while (i < bytes.len and (bytes[i] == ' ' or bytes[i] == '\t')) i += 1;
        const cut: Cut = .{ .slot = toml_line_ending, .skip = i - at, .len = 0 };
        // End of input is the "or_eof" half of the name, and it is why this
        // hand must answer at `at == bytes.len` rather than declining there.
        if (i >= bytes.len or bytes[i] == '\n') return cut;
        // A bare `\r` is not a line ending, so the run is stepped over only
        // when the `\n` behind it makes one.
        if (bytes[i] == '\r' and i + 1 < bytes.len and bytes[i + 1] == '\n') {
            return .{ .slot = toml_line_ending, .skip = i + 1 - at, .len = 0 };
        }
    }

    return null;
}

/// A run of `q` inside a multiline string, and which terminal it is.
///
/// The spec reads the run one delimiter at a time, marking the token's end
/// after the first and again after the second and third, so the lengths fall
/// out of where it last marked: one or two are content of that length, three
/// are the close, and four or more leave the mark back at one. The gate is the
/// *end* symbol being wanted, because that is what says a multiline string is
/// open; the content symbol is what the same bytes become when they are not
/// long enough to close it.
fn quotes(bytes: []const u8, at: u32, want: u8, q: u8, content: u8, end: u8) ?Cut {
    if (!asked(want, end)) return null;
    if (at >= bytes.len or bytes[at] != q) return null;
    var n: u32 = 0;
    while (at + n < bytes.len and bytes[at + n] == q) n += 1;
    return switch (n) {
        1, 2 => .{ .slot = content, .skip = 0, .len = n },
        3 => .{ .slot = end, .skip = 0, .len = 3 },
        else => .{ .slot = content, .skip = 0, .len = 1 },
    };
}

/// haskell: the four extras, which are one region read four ways.
///
/// The spec's order, and the first two rows are why it is an order rather than a
/// set: `{-#` is a pragma and `{-` is a comment, so the longer mark has to be
/// tried first or every pragma in the file reads as documentation.
fn haskell(bytes: []const u8, at: u32, want: u8) ?Cut {
    if (at >= bytes.len) return null;
    if (bytes[at] == '{' and at + 1 < bytes.len and bytes[at + 1] == '-') {
        if (at + 2 < bytes.len and bytes[at + 2] == '#') {
            if (!asked(want, hs_pragma)) return null;
            const n = fenced(bytes, at, "#-}") orelse return null;
            return .{ .slot = hs_pragma, .skip = 0, .len = n };
        }
        const slot = documents(bytes, at) orelse return null;
        if (!asked(want, slot)) return null;
        return .{ .slot = slot, .skip = 0, .len = nested(bytes, at) };
    }
    if (bytes[at] == '-') return dashes(bytes, at, want);
    if (bytes[at] == '#') return directive(bytes, at, want);
    return null;
}

/// A run of `-` that heralds a comment, and everything it takes.
///
/// The herald is not "two dashes": `-->` is an operator, and the spec's
/// `only_minus` settles it by requiring that whatever follows the run of
/// dashes is *not* a character an operator may be spelled with. Then the
/// comment extends over every consecutive line that heralds another one, which
/// is one token in the spec and so one token here.
fn dashes(bytes: []const u8, at: u32, want: u8) ?Cut {
    var i = at;
    while (i < bytes.len and bytes[i] == '-') i += 1;
    if (i - at < 2) return null;
    // The operator class is a Unicode bitmap in the pinned scanner, so a
    // non-ASCII byte here is a character this hand cannot classify. It declines
    // rather than guess, because guessing wrong turns an operator into a
    // comment and takes the rest of the line with it.
    if (i < bytes.len and (bytes[i] >= 0x80 or symop(bytes[i]))) return null;
    const slot = documents(bytes, at) orelse return null;
    if (!asked(want, slot)) return null;

    var end = i;
    while (true) {
        while (end < bytes.len and bytes[end] != '\n') end += 1;
        const next = herald(bytes, end) orelse return .{ .slot = slot, .skip = 0, .len = end - at };
        end = next;
    }
}

/// Where the line after `nl` starts, if it heralds another line comment.
fn herald(bytes: []const u8, nl: u32) ?u32 {
    if (nl >= bytes.len) return null;
    var i = nl + 1;
    while (i < bytes.len and (bytes[i] == ' ' or bytes[i] == '\t')) i += 1;
    var j = i;
    while (j < bytes.len and bytes[j] == '-') j += 1;
    if (j - i < 2) return null;
    if (j < bytes.len and (bytes[j] >= 0x80 or symop(bytes[j]))) return null;
    return j;
}

/// Whether the mark at `at` opens documentation rather than an ordinary comment.
///
/// The spec walks past the mark and its extra dashes, then past whitespace,
/// and calls it haddock on a `|` or a `^`. Any other character settles it as an
/// ordinary comment, which is why the loop breaks rather than continuing.
fn documents(bytes: []const u8, at: u32) ?u8 {
    var i = at + 2;
    while (i < bytes.len and bytes[i] == '-') i += 1;
    while (i < bytes.len) : (i += 1) {
        // Whitespace is a Unicode bitmap upstream as well, and the same refusal
        // applies: a byte this hand cannot classify is not a byte to decide on.
        if (bytes[i] >= 0x80) return null;
        if (bytes[i] == '|' or bytes[i] == '^') return hs_haddock;
        if (!space(bytes[i])) break;
    }
    return hs_comment;
}

/// haskell: a CPP directive, which owns its line.
///
/// `cpp_directive` refuses a bare `#`, so this requires a directive word after
/// it. A backslash continues the directive onto the next line, spaces between
/// the backslash and the newline included, which is `take_line_escaped_newline`.
fn directive(bytes: []const u8, at: u32, want: u8) ?Cut {
    if (!asked(want, hs_cpp)) return null;
    var i = at + 1;
    while (i < bytes.len and (bytes[i] == ' ' or bytes[i] == '\t')) i += 1;
    if (i >= bytes.len or !std.ascii.isAlphabetic(bytes[i])) return null;
    while (i < bytes.len and bytes[i] != '\n') {
        if (bytes[i] != '\\') {
            i += 1;
            continue;
        }
        i += 1;
        while (i < bytes.len and (bytes[i] == ' ' or bytes[i] == '\t')) i += 1;
        if (i < bytes.len and bytes[i] == '\n') i += 1;
    }
    return .{ .slot = hs_cpp, .skip = 0, .len = i - at };
}

/// A run from `at` to just past `shut`, or nothing when it never closes.
fn fenced(bytes: []const u8, at: u32, shut: []const u8) ?u32 {
    var i = at + 2;
    while (i + shut.len <= bytes.len) : (i += 1) {
        if (std.mem.startsWith(u8, bytes[i..], shut)) return i + @as(u32, @intCast(shut.len)) - at;
    }
    return null;
}

/// A `{- -}` run, counting the nesting the spec counts.
///
/// Unterminated is the whole remaining file rather than a refusal, which is the
/// spec's own answer: `consume_block_comment` returns at end of input.
fn nested(bytes: []const u8, at: u32) u32 {
    var i = at + 2;
    var level: u32 = 0;
    while (i < bytes.len) {
        if (bytes[i] == '{' and i + 1 < bytes.len and bytes[i + 1] == '-') {
            level += 1;
            i += 2;
        } else if (bytes[i] == '-' and i + 1 < bytes.len and bytes[i + 1] == '}') {
            i += 2;
            if (level == 0) return i - at;
            level -= 1;
        } else i += 1;
    }
    return i - at;
}

/// The ASCII half of haskell's operator class, less the characters it reserves.
fn symop(c: u8) bool {
    return switch (c) {
        '!', '#', '$', '%', '&', '*', '+', '.', '/', '<', '=', '>', '?', '@' => true,
        '\\', '^', '|', '~', ':', '-' => true,
        else => false,
    };
}

fn space(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == 0x0b or c == 0x0c;
}

const colon_only: u8 = 1 << css_colon;
const descendant_only: u8 = 1 << css_descendant;
const both_css: u8 = colon_only | descendant_only;

test "a colon before a brace is a pseudo-class" {
    const got = look(.css, "a:hover { }", 1, colon_only, false).?;
    try std.testing.expectEqual(@as(u32, 0), got.skip);
    try std.testing.expectEqual(@as(u32, 1), got.len);
    try std.testing.expectEqual(@as(u8, css_colon), got.slot);
}

test "a colon before a semicolon is a property" {
    try std.testing.expect(look(.css, "color: red;", 5, colon_only, false) == null);
}

test "a pseudo-element is the grammar's own" {
    try std.testing.expect(look(.css, "a::before { }", 1, colon_only, false) == null);
}

test "a brace inside a comment does not open a rule" {
    try std.testing.expect(look(.css, "a:hover /* { */;", 1, colon_only, false) == null);
}

test "the descendant operator lands past the whitespace it skips" {
    const got = look(.css, "div   p { }", 3, descendant_only, false).?;
    try std.testing.expectEqual(@as(u8, css_descendant), got.slot);
    try std.testing.expectEqual(@as(u32, 3), got.skip);
    try std.testing.expectEqual(@as(u32, 0), got.len);
}

test "whitespace before a doomed colon is neither token" {
    try std.testing.expect(look(.css, "a :hover;", 1, both_css, false) == null);
}

test "recovery vetoes both" {
    try std.testing.expect(look(.css, "a:hover { }", 1, both_css, true) == null);
}

const line_only: u8 = 1 << toml_line_ending;
const basic_end_only: u8 = 1 << toml_basic_end;

test "a line ending claims nothing where it stands" {
    const got = look(.toml, "[package]\nname = \"x\"\n", 9, line_only, false).?;
    try std.testing.expectEqual(@as(u8, toml_line_ending), got.slot);
    try std.testing.expectEqual(@as(u32, 0), got.skip);
    try std.testing.expectEqual(@as(u32, 0), got.len);
}

test "a line ending steps over the horizontal run before it" {
    const got = look(.toml, "a = 1  \t\nb = 2\n", 5, line_only, false).?;
    try std.testing.expectEqual(@as(u32, 3), got.skip);
    try std.testing.expectEqual(@as(u32, 0), got.len);
}

test "end of input is a line ending, and the hand is asked past the last byte" {
    const got = look(.toml, "a = 1", 5, line_only, false).?;
    try std.testing.expectEqual(@as(u8, toml_line_ending), got.slot);
    try std.testing.expectEqual(@as(u32, 0), got.skip + got.len);
}

test "a carriage return without its newline is not a line ending" {
    try std.testing.expect(look(.toml, "a = 1\rb", 5, line_only, false) == null);
}

test "a run of three quotes closes a multiline string and fewer do not" {
    const one = look(.toml, "\"x", 0, basic_end_only, false).?;
    try std.testing.expectEqual(@as(u8, toml_basic_content), one.slot);
    try std.testing.expectEqual(@as(u32, 1), one.len);

    const two = look(.toml, "\"\"x", 0, basic_end_only, false).?;
    try std.testing.expectEqual(@as(u8, toml_basic_content), two.slot);
    try std.testing.expectEqual(@as(u32, 2), two.len);

    const three = look(.toml, "\"\"\"", 0, basic_end_only, false).?;
    try std.testing.expectEqual(@as(u8, toml_basic_end), three.slot);
    try std.testing.expectEqual(@as(u32, 3), three.len);

    // Four or more leaves the spec's mark back at the first, so the extra
    // quotes are content of the string rather than part of its close.
    const four = look(.toml, "\"\"\"\"", 0, basic_end_only, false).?;
    try std.testing.expectEqual(@as(u8, toml_basic_content), four.slot);
    try std.testing.expectEqual(@as(u32, 1), four.len);
}

test "a quote run is nothing when no multiline string is open" {
    try std.testing.expect(look(.toml, "\"\"\"", 0, line_only, false) == null);
}

/// Every extra at once, which is what an extras position actually asks with.
const all_hs: u8 = (1 << hs_comment) | (1 << hs_haddock) | (1 << hs_cpp) | (1 << hs_pragma);

/// Each expectation below was read off `tree-sitter parse` against the pinned
/// `tree-sitter-haskell` before it was written here, so a change that breaks one
/// is a divergence from the oracle rather than from an opinion.
fn hs(bytes: []const u8, slot: u8, len: u32) !void {
    const got = look(.haskell, bytes, 0, all_hs, false) orelse return error.Declined;
    try std.testing.expectEqual(slot, got.slot);
    try std.testing.expectEqual(@as(u32, 0), got.skip);
    try std.testing.expectEqual(len, got.len);
}

test "haskell: a pragma is the longer mark and wins over the comment" {
    try hs("{-# LANGUAGE CPP #-}\nx = 1\n", hs_pragma, 20);
}

test "haskell: a block comment counts its own nesting" {
    try hs("{- a {- b -} c -}\nmodule M where\n", hs_comment, 17);
}

test "haskell: a bar or a caret past the mark makes it documentation" {
    try hs("{- | doc -}\n", hs_haddock, 11);
    try hs("-- | doc\n", hs_haddock, 8);
    try hs("-- ^ up\n", hs_haddock, 7);
    // The spec walks past the whole run of dashes first, so four is still a
    // herald and the `|` behind it still documents.
    try hs("---- | four dashes\n", hs_haddock, 18);
}

test "haskell: a line comment takes every consecutive line that heralds one" {
    // One token in the spec, because `inline_comment` loops on the herald.
    try hs("-- | doc\n-- more\nmodule M where\n", hs_haddock, 16);
    try hs("-- a\n-- b\n-- c\nx = 1\n", hs_comment, 14);
    // A line that does not herald one ends it, and the newline stays outside.
    try hs("-- a\nx = 1\n", hs_comment, 4);
}

test "haskell: a dash run followed by an operator character is not a comment" {
    // `-->` is an operator, and reading it as a comment would swallow the line.
    try std.testing.expect(look(.haskell, "--> not a comment\n", 0, all_hs, false) == null);
    try std.testing.expect(look(.haskell, "--|x\n", 0, all_hs, false) == null);
    // One dash is a minus, never a herald.
    try std.testing.expect(look(.haskell, "-x\n", 0, all_hs, false) == null);
}

test "haskell: a directive owns its line, and a bare hash is not one" {
    try hs("#if X\nmodule M where\n", hs_cpp, 5);
    // A backslash continues the directive, spaces before the newline included.
    try hs("#define A \\\n  B\nx = 1\n", hs_cpp, 15);
    try std.testing.expect(look(.haskell, "# 1\n", 0, all_hs, false) == null);
}

test "haskell: a byte the operator class cannot be read for declines" {
    // `symop_char` is a Unicode bitmap upstream, so a non-ASCII byte here is
    // one this hand cannot classify - and guessing turns an operator into a
    // comment that eats the rest of the line.
    try std.testing.expect(look(.haskell, "--\xe2\x86\x92 x\n", 0, all_hs, false) == null);
}

test "haskell: an extra not asked for is not answered" {
    try std.testing.expect(look(.haskell, "{-# LANGUAGE CPP #-}\n", 0, 1 << hs_comment, false) == null);
    try std.testing.expect(look(.haskell, "-- | doc\n", 0, 1 << hs_comment, false) == null);
}
