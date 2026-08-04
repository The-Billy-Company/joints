//! Content bounded by marks the parser itself lexes.
//!
//! The third shape an external scanner comes in, after `offside`'s column stack
//! and `fence`'s span stack, and the one that needs no stack at all.
//!
//! `offside` and `fence` both answer tokens that *are* the boundary: an indent,
//! a string opener, a closer. This file answers the opposite - the run in
//! between, where the boundary on each side is an ordinary terminal the grammar
//! already spells for itself. Rust writes `SEQ("/*", _block_comment_content,
//! "*/")` and C++ writes `SEQ("R\"", raw_string_delimiter, "(",
//! raw_string_content, ")", raw_string_delimiter, "\"")`; in both, only the
//! middle is external, because only the middle needs to know where it ends.
//!
//! What makes it a mechanism rather than two special cases is that both ends
//! are computed from position and nothing else:
//!
//! - Rust's close is fixed at `*/`, but nests, so the run is bounded by the
//!   `*/` that brings a depth counter back to zero rather than by the first one.
//! - C++'s close is whatever spelling the open captured, so the run is bounded
//!   by `)` + that spelling + `"`.
//!
//! A captured close usually implies carried state, and `fence` is exactly that
//! - but only because a fence's opener is itself an external, so the capture
//! happens in one token and is spent in another. Here the open is a terminal
//! the parser lexed, which means it is still there in the bytes: at a content
//! offset the delimiter is a fixed walk backwards from `(`. So this file reads
//! only its arguments, carries nothing between tokens, and cannot leave a run
//! contaminated by the last one.
//!
//! Both dialects decline on an empty run rather than answering zero width. An
//! empty comment or an empty raw string is spelled by the grammar's own BLANK
//! branch, so silence here is the right answer and not a gap; it also keeps
//! this file out of the zero-width progress argument `outside.step` has to make
//! for the hands that do answer at width zero.
//!
//! Every dialect here is derived from the pinned grammar's own `scanner.c` read
//! as a specification. Nothing is linked.

const std = @import("std");

/// The languages whose bounding spelling this file can read. Adding one is a
/// new case in `reach` plus a row in `outside.troupes`; nothing else moves.
pub const Dialect = enum {
    rust_block,
    cpp_raw,
    kotlin_block,
    html_comment,
    rust_string,
    julia_block,
    lua_string,
    lua_comment,
};

/// The longest delimiter C++ allows between `R"` and `(`. The standard's own
/// cap, and it is what keeps the backwards walk from scanning a whole file when
/// the bytes at hand are not a raw string at all.
const cpp_tag_max = 16;

/// How far the content at `at` runs before the mark that ends it, or null if
/// this is not content or the run would be empty.
pub fn reach(dialect: Dialect, bytes: []const u8, at: u32) ?u32 {
    if (at > bytes.len) return null;
    return switch (dialect) {
        .rust_block => rustBlock(bytes, at),
        .cpp_raw => cppRaw(bytes, at),
        .kotlin_block => kotlinBlock(bytes, at),
        .html_comment => htmlComment(bytes, at),
        .rust_string => rustString(bytes, at),
        .julia_block => juliaBlock(bytes, at),
        .lua_string, .lua_comment => luaContent(bytes, at),
    };
}

/// Kotlin: a whole nesting block comment, delimiters included.
///
/// The first vein whose run *is* the token rather than the middle of one.
/// Kotlin declares `multiline_comment` as a terminal extra with no rule, so
/// there is no `/*` for the parser to lex and nothing to walk back to; the hand
/// is handed the opener as well. That costs no state - the run is still
/// computed from position alone, which is what puts it in this file rather than
/// in `fence`.
///
/// Transcribed from the pinned `scan_multiline_comment`, including the two
/// decisions a reading of the language would have got wrong: a `/` that was not
/// preceded by `*` opens a nested comment when a `*` follows it, and an
/// unterminated comment is accepted at end of input rather than refused.
fn kotlinBlock(bytes: []const u8, at: u32) ?u32 {
    var i = at;
    if (i + 1 >= bytes.len or bytes[i] != '/' or bytes[i + 1] != '*') return null;
    i += 2;

    var after_star = false;
    var depth: u32 = 1;
    while (i < bytes.len) {
        switch (bytes[i]) {
            '*' => {
                i += 1;
                after_star = true;
            },
            '/' => {
                i += 1;
                if (after_star) {
                    after_star = false;
                    depth -= 1;
                    if (depth == 0) return i - at;
                } else if (i < bytes.len and bytes[i] == '*') {
                    depth += 1;
                    i += 1;
                }
            },
            else => {
                i += 1;
                after_star = false;
            },
        }
    }
    // The spec accepts an unterminated comment at end of input, on the ground
    // that the alternative is the delimiters being read as operators.
    return i - at;
}

/// Rust: to the `*/` that closes the comment we are already inside, which is
/// the one that returns depth to zero and not the first one seen.
///
/// Depth starts at one because the `/*` that opened it is behind us; the parser
/// lexed it as its own terminal, which is the whole reason this run needs an
/// external at all - a fixed pattern cannot count.
fn rustBlock(bytes: []const u8, at: u32) ?u32 {
    if (!std.mem.endsWith(u8, bytes[0..at], "/*")) return null;
    var depth: u32 = 1;
    var i = at;
    while (i < bytes.len) {
        if (std.mem.startsWith(u8, bytes[i..], "/*")) {
            depth += 1;
            i += 2;
        } else if (std.mem.startsWith(u8, bytes[i..], "*/")) {
            // The one that closes us is the grammar's own terminal, so the run
            // stops in front of it rather than consuming it.
            if (depth == 1) break;
            depth -= 1;
            i += 2;
        } else i += 1;
    }
    return if (i == at) null else i - at;
}

/// C++: to `)` plus the delimiter this literal opened with plus `"`.
///
/// The delimiter is read back out of the bytes rather than remembered, which is
/// what lets the whole file be stateless. `(` is immediately behind a content
/// offset by construction, and the delimiter is the run between it and the `"`
/// of the opener.
fn cppRaw(bytes: []const u8, at: u32) ?u32 {
    const delim = openedWith(bytes, at) orelse return null;
    var mark: [cpp_tag_max + 2]u8 = undefined;
    mark[0] = ')';
    @memcpy(mark[1 .. 1 + delim.len], delim);
    mark[1 + delim.len] = '"';
    const close = std.mem.indexOf(u8, bytes[at..], mark[0 .. delim.len + 2]) orelse return null;
    return if (close == 0) null else @intCast(close);
}

/// How long the mark that ends this vein's run is, for the veins whose cast
/// names a `close` of its own.
///
/// `reach` stops in front of the closing mark because the grammar usually spells
/// it as an ordinary terminal; where the grammar makes the closer external too,
/// this answers it. Same discipline as `reach`: position in, length out.
pub fn shut(dialect: Dialect, bytes: []const u8, at: u32) ?u32 {
    if (at >= bytes.len) return null;
    return switch (dialect) {
        .rust_string => if (bytes[at] == '"') 1 else null,
        .lua_string, .lua_comment => luaBracket(bytes, at, ']'),
        else => null,
    };
}

/// How long the mark that opens this vein's run is, for the veins whose cast
/// names an `opens` the grammar left external.
///
/// The mirror of `shut`, and the reason both exist: a vein is up to three
/// answers over one region, and which of them the grammar spells for itself
/// differs per language rather than per mechanism.
pub fn open(dialect: Dialect, bytes: []const u8, at: u32) ?u32 {
    return switch (dialect) {
        .lua_string => luaBracket(bytes, at, '['),
        .lua_comment => blk: {
            if (!std.mem.startsWith(u8, bytes[at..], "--")) break :blk null;
            const n = luaBracket(bytes, at + 2, '[') orelse break :blk null;
            break :blk n + 2;
        },
        else => null,
    };
}

/// Rust: an ordinary string's content, up to the quote or backslash that ends
/// it.
///
/// The vein where neither end is external and yet the middle is: rust spells
/// its opener as the pattern `/[bc]?"/` and its escapes as their own rule, so
/// the run is simply everything that is neither. Empty runs are refused, which
/// is what lets `string_close` answer the quote a zero-length content would
/// otherwise sit in front of forever; the pinned scanner leans on the same
/// fallthrough.
fn rustString(bytes: []const u8, at: u32) ?u32 {
    var i = at;
    while (i < bytes.len and bytes[i] != '"' and bytes[i] != '\\') i += 1;
    // Reaching the end without a closer is not a string, and the spec refuses
    // it rather than handing back the rest of the file.
    if (i == bytes.len) return null;
    return if (i == at) null else i - at;
}

/// The delimiter of the raw string whose content starts at `at`, by walking
/// back over `(` and the delimiter to the opener's quote.
fn openedWith(bytes: []const u8, at: u32) ?[]const u8 {
    if (at == 0 or bytes[at - 1] != '(') return null;
    var j = at - 1;
    while (j > 0 and at - j <= cpp_tag_max + 1) : (j -= 1) {
        if (bytes[j - 1] == '"') return bytes[j .. at - 1];
        if (!isTagByte(bytes[j - 1])) return null;
    }
    return null;
}

/// How far the delimiter at `at` runs, or null if this is not one.
///
/// It appears twice in a literal, so both sides are read here: after the
/// opener's `R"` it is terminated by `(`, and after the content's `)` it is
/// terminated by `"`. Requiring one of those two on each side is what stops an
/// ordinary `name(` from reading as a delimiter, since by itself a delimiter is
/// just a run of identifier bytes.
pub fn tag(bytes: []const u8, at: u32) ?u32 {
    if (at == 0 or at > bytes.len) return null;
    const opening = bytes[at - 1] == '"';
    if (!opening and bytes[at - 1] != ')') return null;
    var i = at;
    while (i < bytes.len and i - at < cpp_tag_max and isTagByte(bytes[i])) i += 1;
    if (i == at or i == bytes.len) return null;
    if (bytes[i] != (if (opening) @as(u8, '(') else @as(u8, '"'))) return null;
    return i - at;
}

/// The standard's d-char: anything but a space, a control, and the six that
/// would make the close ambiguous.
fn isTagByte(c: u8) bool {
    return switch (c) {
        ' ', '(', ')', '\\', '"', '\t'...'\r' => false,
        else => c > 0x20,
    };
}

const t = std.testing;

test "marrow: a rust block comment ends on the close that balances it" {
    const src = "/* one /* two */ three */ after";
    // Content starts past the opening `/*`, and runs to the last `*/`.
    try t.expectEqual(@as(?u32, 21), reach(.rust_block, src, 2));
    try t.expectEqualStrings(" one /* two */ three ", src[2 .. 2 + 21]);
}

test "marrow: a rust block comment with no nesting stops at the first close" {
    try t.expectEqual(@as(?u32, 5), reach(.rust_block, "/*hello*/", 2));
}

test "marrow: an empty rust block comment declines rather than answering zero" {
    try t.expectEqual(@as(?u32, null), reach(.rust_block, "/**/", 2));
}

test "marrow: content not behind an opener is not content" {
    // The same bytes, asked at an offset no `/*` precedes.
    try t.expectEqual(@as(?u32, null), reach(.rust_block, "hello */", 0));
}

test "marrow: a cpp raw string ends on its own captured delimiter" {
    const src = "R\"tag(body )x\" more)tag\";";
    // `)x"` is not the close, because the delimiter captured at the open is `tag`.
    try t.expectEqual(@as(?u32, 13), reach(.cpp_raw, src, 6));
    try t.expectEqualStrings("body )x\" more", src[6 .. 6 + 13]);
}

test "marrow: a cpp raw string with an empty delimiter still closes" {
    try t.expectEqual(@as(?u32, 4), reach(.cpp_raw, "R\"(body)\";", 3));
}

test "marrow: an ordinary call is not a raw string delimiter" {
    // `name(` has the shape of a delimiter and none of the context.
    try t.expectEqual(@as(?u32, null), tag("name(x);", 0));
    try t.expectEqual(@as(?u32, null), reach(.cpp_raw, "name(x);", 5));
}

test "marrow: a delimiter reads on both sides of the content" {
    try t.expectEqual(@as(?u32, 3), tag("R\"tag(body)tag\";", 2));
    try t.expectEqual(@as(?u32, 3), tag("R\"tag(body)tag\";", 11));
}

test "marrow: an unterminated raw string declines rather than running to the end" {
    try t.expectEqual(@as(?u32, null), reach(.cpp_raw, "R\"tag(body", 6));
}

/// HTML: a whole comment, `<!--` through `-->`.
///
/// The same self-contained shape as kotlin's, and the reason there are two of
/// them rather than one parameterised row: the two languages disagree about
/// every decision that is not the spelling. HTML's close does not nest and its
/// run of dashes is greedy, so `--->` closes; an unterminated comment is
/// refused outright rather than accepted at end of input.
fn htmlComment(bytes: []const u8, at: u32) ?u32 {
    if (!std.mem.startsWith(u8, bytes[at..], "<!--")) return null;
    var dashes: u32 = 0;
    var i = at + 4;
    while (i < bytes.len) : (i += 1) {
        switch (bytes[i]) {
            '-' => dashes += 1,
            '>' => if (dashes >= 2) return i + 1 - at else {
                dashes = 0;
            },
            else => dashes = 0,
        }
    }
    return null;
}

/// Julia: the rest of a nesting block comment, closing `=#` included.
///
/// kotlin's function with `=` and `#` in place of `*` and `/`, and two
/// deliberate differences the pinned scanner settles: the run *includes* its
/// closer, which is why the grammar calls it a rest rather than a content, and
/// an unterminated comment is refused where kotlin accepts one.
fn juliaBlock(bytes: []const u8, at: u32) ?u32 {
    var after_eq = false;
    var depth: u32 = 1;
    var i = at;
    while (i < bytes.len) {
        switch (bytes[i]) {
            '=' => {
                i += 1;
                after_eq = true;
            },
            '#' => {
                i += 1;
                if (after_eq) {
                    after_eq = false;
                    depth -= 1;
                    if (depth == 0) return i - at;
                } else if (i < bytes.len and bytes[i] == '=') {
                    depth += 1;
                    i += 1;
                }
            },
            else => {
                i += 1;
                after_eq = false;
            },
        }
    }
    return null;
}

/// Lua: a long bracket of either polarity - `[==[` to open, `]==]` to close.
///
/// The level is however many `=` sit between the two brackets, and a close only
/// closes an open of the same level, which is what lets a Lua long string hold
/// a `]]`.
fn luaBracket(bytes: []const u8, at: u32, side: u8) ?u32 {
    if (at >= bytes.len or bytes[at] != side) return null;
    var i = at + 1;
    while (i < bytes.len and bytes[i] == '=') i += 1;
    if (i >= bytes.len or bytes[i] != side) return null;
    return i + 1 - at;
}

/// Lua: a long bracket's content, up to the close that matches the level the
/// open declared.
///
/// The level is not carried; it is read back out of the bytes, since the open
/// is a bracket run ending immediately before `at`. That is the same walk
/// `cppRaw` does, and the same reason this file needs no state.
///
/// An empty long string answers at zero width, which `[[]]` needs and the
/// pinned scanner also gives. Nothing here remembers that it did; the memory is
/// `Carry.pinned`, which pins any hand, and the caller consults it so that the
/// close sharing this offset is reached on the second ask. An unterminated run
/// is still refused, because the level never closed at all.
fn luaContent(bytes: []const u8, at: u32) ?u32 {
    const level = luaLevel(bytes, at) orelse return null;
    var i = at;
    while (i < bytes.len) : (i += 1) {
        if (bytes[i] != ']') continue;
        if (luaBracket(bytes, i, ']')) |n| if (n == level) break;
    }
    return if (i >= bytes.len) null else i - at;
}

/// How many bytes the long bracket that opened the run at `at` spans, by
/// walking back over its `=` run to the bracket that started it.
fn luaLevel(bytes: []const u8, at: u32) ?u32 {
    if (at == 0 or bytes[at - 1] != '[') return null;
    var j = at - 1;
    while (j > 0 and bytes[j - 1] == '=') j -= 1;
    if (j == 0 or bytes[j - 1] != '[') return null;
    return at - j + 1;
}
