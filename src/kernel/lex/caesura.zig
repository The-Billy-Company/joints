//! A break the line demands but does not spell.
//!
//! Some languages end a statement with a token that occupies no bytes.
//! JavaScript's automatic semicolon insertion is the one everybody has met: a
//! newline ends `const a = 1` and no `;` was ever written, so the parser is
//! owed a terminal that consumes nothing.
//!
//! Zero width is not new here - python's dedents have always been zero-width,
//! and `outside.step` already holds the guard that keeps a token consuming
//! nothing from being offered forever. What is new is *how the answer is
//! decided*. The three hands before this one read bytes and a carried stack;
//! this one reads bytes and **what the parser would accept next**. The spec
//! says so in one line:
//!
//! ```c
//! if (lexer->lookahead == ':') return valid_symbols[LOGICAL_OR];
//! ```
//!
//! "Is there a semicolon here" is answered by "is `||` legal here" - because
//! `||` is legal in an expression and not in a type, and `}` followed by `:` is
//! an object pattern in a typed parameter list rather than the end of a block.
//! The scanner has no way to know which it is looking at, so it asks the parse
//! table, which does.
//!
//! Everything below is a transcription of `scan_automatic_semicolon` in
//! tree-sitter-typescript's `common/scanner.h`, including the parts that are
//! arguably wrong. `in_variable` gets no semicolon because the spec tests
//! `iswalpha` and `_` is not a letter; reproducing that is the difference
//! between matching tree-sitter and being right on our own.
//!
//! Where this transcription differs it differs toward silence. The spec reads
//! codepoints and tests `iswspace`/`iswalpha`, which are Unicode-wide; this
//! reads bytes and tests ASCII. A U+00A0 after a statement is whitespace to the
//! spec and not to us, so we answer "no break" where it would answer one - a
//! token we fail to insert costs a parse, where a token we insert wrongly costs
//! a tree that looks right.

const std = @import("std");

/// The two questions this hand puts to the parser, resolved by the caller
/// because only the caller holds the expected set.
///
/// Neither is about the bytes at hand. `binary` is the whole distinction
/// between an expression and a type, and `signature` between a function body
/// and a declaration, and a scanner reading bytes alone cannot tell either.
pub const Asks = struct {
    /// Whether the language's binary-or is acceptable here, which is what
    /// makes this an expression rather than a type annotation.
    binary: bool = false,
    /// Whether a function signature could end here, which suppresses the
    /// break before the `{` that would otherwise be its body.
    signature: bool = false,
};

/// Whether a statement ends at `at`, reading forward from it.
///
/// True means the parser is owed a zero-width terminator here. The scan never
/// moves the lexer: it is a question about the bytes ahead, and the answer
/// occupies none of them.
pub fn breaks(bytes: []const u8, at: u32, ask: Asks) bool {
    var i: usize = at;
    while (true) : (i += 1) {
        if (i == bytes.len) return true; // the file ends, so the statement does
        const ch = bytes[i];
        if (ch == '}') {
            // A closing brace ends the statement inside it - unless what
            // follows is `:`, which makes the brace an object pattern in a
            // typed parameter list. Only the parser can tell those apart.
            i += 1;
            while (i < bytes.len and space(bytes[i])) i += 1;
            if (i < bytes.len and bytes[i] == ':') return ask.binary;
            return true;
        }
        if (!space(ch)) return false; // the statement continues on this line
        if (ch == '\n') break;
    }

    i = pass(bytes, i + 1) orelse return false;
    if (i == bytes.len) return true;
    switch (bytes[i]) {
        // A line resuming with any of these is one expression across two
        // lines, and a semicolon would cut it in half.
        '`', ',', '.', ';', '*', '%', '>', '<', '=', '?', '^', '|', '&', '/', ':' => return false,
        // A brace opens a body when a signature could have ended here.
        '{' => if (ask.signature) return false,
        // A bracket or paren continues a call or an index in an expression,
        // and opens a type otherwise.
        '(', '[' => if (ask.binary) return false,
        // `++` and `--` are their own statement; binary `+` and `-` are not.
        '+' => return next(bytes, i) == '+',
        '-' => return next(bytes, i) == '-',
        // `!=` continues the expression; a unary `!` starts a statement.
        '!' => return next(bytes, i) != '=',
        // `in` and `instanceof` are operators; every other word starting with
        // `i` is a new statement.
        'i' => return !keyword(bytes, i),
        else => {},
    }
    return true;
}

/// Whether the word at `i` is `in` or `instanceof` rather than an identifier
/// that merely starts the same way.
fn keyword(bytes: []const u8, i: usize) bool {
    var j = i + 1;
    if (next(bytes, i) != 'n') return false;
    j += 1;
    if (!alpha(byte(bytes, j))) return true; // bare `in`
    for ("stanceof") |want| {
        if (byte(bytes, j) != want) return false;
        j += 1;
    }
    return !alpha(byte(bytes, j)); // `instanceof`, not `instanceofx`
}

/// Whitespace and comments, the way the spec skips them: a `/` that opens
/// neither a line nor a block comment is division, and division means the
/// expression continues, so the scan fails rather than stopping there.
fn pass(bytes: []const u8, from: usize) ?usize {
    var i = from;
    while (true) {
        while (i < bytes.len and space(bytes[i])) i += 1;
        if (i == bytes.len or bytes[i] != '/') return i;
        i += 1;
        if (byte(bytes, i) == '/') {
            while (i < bytes.len and bytes[i] != '\n') i += 1;
        } else if (byte(bytes, i) == '*') {
            i += 1;
            // A star that is not the close leaves the cursor on the next byte
            // rather than past it, so `**/` still closes; advancing twice here
            // would step over the slash.
            while (i < bytes.len) {
                if (bytes[i] != '*') {
                    i += 1;
                    continue;
                }
                i += 1;
                if (byte(bytes, i) == '/') {
                    i += 1;
                    break;
                }
            }
        } else return null;
    }
}

/// The byte at `i`, or zero past the end - which is the spec's own `lookahead`
/// at end of input, and several of its branches lean on that.
fn byte(bytes: []const u8, i: usize) u8 {
    return if (i < bytes.len) bytes[i] else 0;
}

fn next(bytes: []const u8, i: usize) u8 {
    return byte(bytes, i + 1);
}

fn space(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r' or ch == 0x0B or ch == 0x0C;
}

fn alpha(ch: u8) bool {
    return std.ascii.isAlphabetic(ch);
}

// ─────────────────────────────── tests ───────────────────────────────

const t = std.testing;

/// Every case is the spec's, read forward from offset zero as though a token
/// had just ended there.
fn asks(src: []const u8, ask: Asks) bool {
    return breaks(src, 0, ask);
}

test "caesura: a line ends a statement and a space does not" {
    try t.expect(asks("\nfoo", .{}));
    try t.expect(!asks(" foo", .{}));
    try t.expect(asks("", .{})); // end of file
    try t.expect(!asks("foo", .{})); // no gap at all
}

test "caesura: a brace ends the statement unless a colon makes it a pattern" {
    try t.expect(asks("}", .{}));
    try t.expect(asks(" \n }", .{}));
    // `({a}: {a: number}) => number` - the brace is a parameter pattern, and
    // only the parser knows, which is what `binary` carries.
    try t.expect(asks("} : x", .{ .binary = true }));
    try t.expect(!asks("} : x", .{ .binary = false }));
}

test "caesura: a line resuming with an operator is one expression" {
    for ([_][]const u8{ "\n, b", "\n. b", "\n* b", "\n= b", "\n| b", "\n? b", "\n/ b", "\n: b" }) |src| {
        try t.expect(!asks(src, .{}));
    }
    try t.expect(asks("\nfoo", .{}));
}

test "caesura: increment starts a statement where addition continues one" {
    try t.expect(asks("\n++x", .{}));
    try t.expect(!asks("\n+ x", .{}));
    try t.expect(asks("\n--x", .{}));
    try t.expect(!asks("\n- x", .{}));
    try t.expect(asks("\n!x", .{}));
    try t.expect(!asks("\n!= x", .{}));
}

test "caesura: in and instanceof are operators, other i-words are statements" {
    try t.expect(!asks("\nin x", .{}));
    try t.expect(!asks("\ninstanceof X", .{}));
    try t.expect(asks("\nindex", .{}));
    try t.expect(asks("\ninstanceofx", .{}));
    try t.expect(asks("\nif (x) {}", .{}));
    // The spec tests `iswalpha`, so an underscore reads as the end of `in`.
    // Transcribed rather than corrected; matching tree-sitter is the contract.
    try t.expect(!asks("\nin_variable", .{}));
}

test "caesura: brackets and braces read the parser's answer" {
    try t.expect(!asks("\n(x)", .{ .binary = true })); // a call continues
    try t.expect(asks("\n(x)", .{ .binary = false })); // a type begins
    try t.expect(!asks("\n{}", .{ .signature = true }));
    try t.expect(asks("\n{}", .{ .signature = false }));
}

test "caesura: comments are passed over and division is not" {
    try t.expect(asks("\n// note\nfoo", .{}));
    try t.expect(asks("\n/* note */ foo", .{}));
    try t.expect(!asks("\n/* note */ , foo", .{}));
    try t.expect(!asks("\n/ 2", .{})); // division, so the expression continues
    try t.expect(asks("\n/* unterminated", .{})); // runs to the end, which ends it
}
