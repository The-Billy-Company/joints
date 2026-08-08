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
//!
//! # Three tongues, and what they do not share
//!
//! Three languages on the board hand their statement separator to a scanner,
//! and it was tempting to read that as one rule with three spellings. It is
//! not, and the differences are the substance rather than the trim:
//!
//!   * **ecma** suppresses the break before a line that *resumes* with an
//!     operator, because JavaScript permits `x\n + y`.
//!   * **swift** does the opposite. Swift requires a binary operator to sit on
//!     the line it continues, so its scanner suppresses on a *trailing*
//!     operator and inserts a semicolon before a leading `+` quite happily. Its
//!     only leading suppressors are `?`, `:` and `{`, listed in the scanner as
//!     `NON_CONSUMING_CROSS_SEMI_CHARS`.
//!   * **kotlin** suppresses on a leading operator like ecma, but on a
//!     different set - `{`, `[` and `(` unconditionally, where ecma asks the
//!     parser - and it alone inserts a break *without* a newline, before an
//!     `import`.
//!   * **elixir** is not a semicolon at all. Its three terminals mark a line
//!     break the *next* line continues - before a comment, before a `do`,
//!     before a binary operator - and the arm is chosen by peeking one byte past
//!     the break. It is the only tongue here whose answer is more than one
//!     terminal, and the only one that claims bytes as a matter of course.
//!
//! So `Tongue` selects a rule rather than parameterising one, and the ecma arm
//! is left byte-for-byte as it was.
//!
//! # A caesura is not the zero-width hand
//!
//! Three of the four claim no bytes in the ordinary case, and it was tempting to
//! read zero extent as the mechanism. It is not. elixir's `scan_newline` calls
//! `mark_end` *after* the newline and after every whitespace byte behind it -
//! its own comment says why, "so that the parser doesn't have to go through it
//! again" - so the token is routinely seven bytes wide. What makes all four one
//! mechanism is that the answer is decided by **what the parser would accept
//! next**, which no amount of reading bytes can supply; the width is incidental,
//! and `Break` has carried one since swift's spelled `;`.
//!
//! All three also treat a **spelled** separator as their own business. Swift's
//! scanner reads `;` as whitespace and emits `_explicit_semi` for it, kotlin's
//! consumes it and emits `_automatic_semicolon`. That is why a break carries a
//! width: the same hand answers "the line ended" with nothing and "the file
//! said so" with one byte, and the parser needs a different terminal for each.
//! It is also why swift cannot read even an explicit `;` without this hand -
//! there is no other spelling of a separator in the grammar's member rules.

const std = @import("std");

/// Which language's separator rule to run.
///
/// Named for the convention rather than the grammar, because javascript and
/// typescript share one scanner and both arrive here as `.ecma`.
pub const Tongue = enum { ecma, swift, kotlin, elixir };

/// Which of a tongue's several terminals a break is, where it has several.
///
/// Three of the four tongues answer one terminal (plus, for two of them, a
/// spelled variant of that same decision), so their breaks leave this `.only`.
/// elixir's `scan_newline` answers three genuinely different terminals from one
/// pass, chosen by one byte past the mark, and the names are the grammar's:
/// `_newline_before_comment`, `_newline_before_do`,
/// `_newline_before_binary_operator`.
///
/// An enum rather than an index, so a hand cannot read the wrong seat of a list
/// and a tongue cannot invent a fourth arm the roster has no room for. The order
/// is the specification's dispatch order, which is also the order it resolves a
/// tie in: `#` is tested before `d`, and `d` before the operator table.
pub const Seam = enum { only, comment, block, operator };

/// A separator the line demands, and how much of the file it occupies.
///
/// Zero width is the ordinary case - the parser is owed a terminal nobody
/// wrote. A spelled one is the same decision reached through a `;` the file
/// does contain, which the grammar names with a different terminal and which
/// must be consumed or the next call meets it again. elixir's is neither: the
/// break itself claims the line ending and the indent behind it, because its
/// scanner marks the end past both.
pub const Break = struct {
    /// Whether the file spelled the separator, selecting the grammar's
    /// explicit terminal over the implied one.
    spelled: bool = false,
    /// Which terminal, for a tongue that answers more than one.
    seam: Seam = .only,
    /// Bytes stepped over without claiming them, ahead of the match.
    skip: u32 = 0,
    /// Bytes the separator itself occupies.
    len: u32 = 0,
};

/// The questions this hand puts to the parser, resolved by the caller because
/// only the caller holds the expected set.
///
/// None is about the bytes at hand. `binary` is the whole distinction between an
/// expression and a type, and `signature` between a function body and a
/// declaration, and a scanner reading bytes alone cannot tell either. `block`
/// and `operator` are elixir's two gated arms, which its specification reads
/// straight out of `valid_symbols` before it will commit to either.
pub const Asks = struct {
    /// Whether the language's binary-or is acceptable here, which is what
    /// makes this an expression rather than a type annotation.
    binary: bool = false,
    /// Whether a function signature could end here, which suppresses the
    /// break before the `{` that would otherwise be its body.
    signature: bool = false,
    /// Whether a comment could stand after this break. The one ask the
    /// specification does not make of its own arm; see `elixir`.
    comment: bool = false,
    /// Whether a block opener could stand after this break.
    block: bool = false,
    /// Whether a binary operator could continue the expression across it.
    operator: bool = false,
};

/// Whether a statement ends at `at`, reading forward from it.
///
/// Null means no separator is owed here. A `Break` means one is, and says
/// whether the file spelled it and which terminal it is.
pub fn breaks(tongue: Tongue, bytes: []const u8, at: u32, ask: Asks) ?Break {
    return switch (tongue) {
        .ecma => if (ecma(bytes, at, ask)) .{} else null,
        .swift => swift(bytes, at),
        .kotlin => kotlin(bytes, at),
        .elixir => elixir(bytes, at, ask),
    };
}

/// JavaScript and TypeScript, whose scanner is one file they share.
fn ecma(bytes: []const u8, at: u32, ask: Asks) bool {
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

/// Swift, transcribed from `eat_whitespace` in tree-sitter-swift's `scanner.c`.
///
/// The shape is inverted from ecma's and that inversion is the whole rule.
/// Swift's grammar makes a binary operator external precisely so the scanner
/// can require it to *end* a line - `_plus_then_ws` is `+` followed by
/// whitespace - so a line beginning with an operator is a new statement rather
/// than a continuation, and the scanner inserts a separator in front of it.
/// Only three bytes suppress a break, and the scanner names them:
/// `NON_CONSUMING_CROSS_SEMI_CHARS` is `?`, `:`, `{`.
///
/// `should_treat_as_wspace` counts `;` as whitespace, which is how one loop
/// answers both terminals: a `;` reached while skipping is the explicit one and
/// is consumed, and a newline reached without one is the implied one.
///
/// Two divergences, both toward silence. The scanner consults `valid_symbols`
/// to decide whether an operator after a comment suppresses the break; we test
/// the byte instead, so we suppress in a few places it would not - and a
/// suppressed break costs a parse where a wrong one costs a tree. And the
/// scanner marks the implied separator's end past the whitespace it crossed,
/// where we leave it zero-width at `at`, which moves a span and no structure.
fn swift(bytes: []const u8, at: u32) ?Break {
    var i: usize = at;
    var crossed = false;
    while (i < bytes.len) : (i += 1) {
        const ch = bytes[i];
        // A spelled separator, reached as whitespace and claimed as a token.
        if (ch == ';') return .{ .spelled = true, .skip = @intCast(i - at), .len = 1 };
        if (!space(ch)) break;
        if (ch == '\n' or ch == '\r') crossed = true;
    }
    // No line ended, so nothing is owed: swift has no end-of-file separator
    // that a newline did not already earn.
    if (!crossed) return null;
    // A comment resuming the line is stepped over, and what follows it decides.
    // `pass` returns null on a bare `/`, which is division and a continuation.
    if (byte(bytes, i) == '/') {
        const j = pass(bytes, i) orelse return null;
        if (operative(byte(bytes, j))) return null;
        return .{};
    }
    // `byte` answers zero past the end, and zero is not a suppressor, so a file
    // ending after a newline gets its separator without a special case.
    //
    // The width divergence the header above calls "a span and no structure" is
    // measured now and it is not that: `statements` ends where its last child
    // does, the oracle's last child is a trailing `_semi` sitting past the
    // whitespace, and ours is the last statement - so every function body in
    // `Chunked.swift` closes three bytes short of the oracle's and every byte
    // under that rung reads crooked. Answering `.{ .skip = i - at }` here,
    // which is `eat_whitespace`'s own placement, moves nothing: an explicit `;`
    // in the same position *is* shifted and does square the rung, so the state
    // admits `_semi` before `}` and the implied one is being declined
    // downstream of this hand. Left as it was, and named in the lane report
    // rather than papered over with an inert edit.
    return switch (byte(bytes, i)) {
        '?', ':', '{' => null,
        else => .{},
    };
}

/// A byte that could begin a swift operator, and so suppress a break after a
/// comment. The symbolic set from the scanner's `OPERATORS` table; its
/// word-spelled operators (`where`, `throws`, `as`) are left out because the
/// scanner reaches them only when the state admits them, and a state expecting
/// a member separator does not.
fn operative(ch: u8) bool {
    return switch (ch) {
        '/', '=', '-', '+', '!', '*', '%', '<', '>', '&', '|', '^', '?', '~', '.' => true,
        else => false,
    };
}

/// Kotlin, transcribed from `scan_automatic_semicolon` in
/// tree-sitter-kotlin's `scanner.c`.
///
/// Suppresses on a leading operator the way ecma does, but from its own list -
/// `{`, `[` and `(` are unconditional here where ecma asks the parser about
/// them, and `+`, `-` and `!` are absent, so kotlin breaks before a leading
/// `+`. It is also the only one of the three that inserts a separator with no
/// newline at all: `import` after a statement on the same line gets one, and
/// the check is the spec's own prefix test with no trailing boundary.
fn kotlin(bytes: []const u8, at: u32) ?Break {
    var i: usize = at;
    var sameline = true;
    while (i < bytes.len) : (i += 1) {
        const ch = bytes[i];
        if (ch == ';') return .{ .spelled = true, .skip = @intCast(i - at), .len = 1 };
        if (!space(ch)) break;
        if (ch == '\n' or ch == '\r') {
            sameline = false;
            i += 1;
            break;
        }
    }
    if (i >= bytes.len) return .{}; // the file ends, so the statement does
    const j = pass(bytes, i) orelse return null;
    if (sameline) return switch (byte(bytes, j)) {
        'i' => if (std.mem.startsWith(u8, bytes[@min(j, bytes.len)..], "import")) Break{} else null,
        ';' => .{ .spelled = true, .skip = @intCast(j - at), .len = 1 },
        else => null,
    };
    return switch (byte(bytes, j)) {
        ',', '.', ':', '*', '%', '>', '<', '=', '{', '[', '(', '?', '|', '&' => null,
        else => .{},
    };
}

/// elixir, transcribed from `scan_newline` in tree-sitter-elixir's `scanner.c`
/// and from the guard in `scan` that reaches it.
///
/// Not a semicolon. elixir's three terminals say that a line break is *not* the
/// end of anything, because what stands past it continues the expression: a
/// comment, a `do` opening a block, or a binary operator. So the arms are chosen
/// by looking one byte past the break, and two of the three are also gated on
/// the parse table, which is what makes this a caesura rather than a pattern.
///
/// Five details are the specification's and none reads off the shape:
///
///   * **The inline whitespace ahead of the break is skipped, not claimed.**
///     `scan` runs `skip(lexer)` over spaces and tabs before it will even look
///     for a newline, which is `Break.skip`.
///   * **The break claims the newline and every whitespace byte behind it**,
///     including further newlines, because `mark_end` comes after that loop. Its
///     own comment says why: so the parser does not walk the indent again.
///   * **elixir's whitespace is four bytes**, space tab CR LF, where this file's
///     `space` also counts the two vertical ones. A form feed inside an indent is
///     matter to elixir's scanner and so ends the run here.
///   * **The comment arm consults no permission set**, where the other two read
///     theirs by name. It does not have to: tree-sitter discards a symbol its
///     state cannot shift, so the runtime does for `#` what the C does for itself
///     on `do`. `ask.comment` states that filter here rather than leaning on it,
///     and an ungated `#` refuses instead of falling through to the operator arm
///     the specification would never have reached.
///   * **`do` needs a token end after it and end of input is not one.** The
///     specification's `is_token_end` reads `lexer->lookahead`, which is zero at
///     the end of a file, and zero is neither a terminator nor whitespace. So a
///     file ending in `\ndo` gets no break. Transcribed, not corrected.
fn elixir(bytes: []const u8, at: u32, ask: Asks) ?Break {
    if (!ask.comment and !ask.block and !ask.operator) return null;
    var i: usize = at;
    while (i < bytes.len and blank(bytes[i])) i += 1;
    if (i >= bytes.len or !line(bytes[i])) return null;
    const from = i;
    i += 1;
    while (i < bytes.len and (blank(bytes[i]) or line(bytes[i]))) i += 1;
    const mark: u32 = @intCast(i);
    const seam: Seam = switch (byte(bytes, mark)) {
        '#' => if (ask.comment) .comment else return null,
        'd' => if (ask.block and spells(bytes, mark, "do") != null) .block else return null,
        else => if (ask.operator and continues(bytes, mark)) .operator else return null,
    };
    return .{ .seam = seam, .skip = @intCast(from - at), .len = @intCast(mark - from) };
}

/// elixir's binary operators, as the trie its scanner spells them with.
///
/// Prefix-closed and matched by maximal munch, with one rule that is not the
/// usual one: **descending past an accepting node and finding nothing is a
/// refusal, never a fallback to the shorter reading.** The specification is a
/// hand-written nest of `if (lookahead == …) advance(…)`, and once it has taken
/// a second `<` it is inside the `<<<`/`<<~` branch and cannot go back to bare
/// `<`. So `<<` is not an operator and `<` is, and a table matched with
/// backtracking would have got that pair backwards.
const operators = [_][]const u8{
    "&&",  "&&&", "=",  "==",  "===", "=~", "=>",  "::", "++", "+++", "--",
    "---", "->",  "<",  "<=",  "<-",  "<>", "<~",  "<~>", "<|>", "<<<", "<<~",
    ">",   ">=",  ">>>", "^^^", "!=", "!==", "~>", "~>>", "|",  "||",  "|||",
    "|>",  "*",   "**", "/",   "//",  ".",  "..",  "\\\\",
};

/// The two spellings whose own byte, one more time, is not the longer operator
/// it looks like. `:::` is `::` in front of an atom and `...` is an identifier,
/// and the specification refuses both by name rather than by the trie.
const overrun = [_][]const u8{ "::", ".." };

/// elixir's word operators, each needing a token boundary behind it where the
/// symbolic ones need none. `not in` carries its own inline whitespace, which is
/// why it is spelled here and matched apart.
const words = [_][]const u8{ "when", "and", "or", "in" };

/// Whether the bytes at `at` are an operator the next line continues with.
fn continues(bytes: []const u8, at: u32) bool {
    if (munch(bytes, at)) |n| {
        for (overrun) |op| {
            if (n == op.len and std.mem.eql(u8, bytes[at..][0..n], op) and byte(bytes, at + n) == op[0]) {
                return false;
            }
        }
        return settled(bytes, at + @as(u32, @intCast(n)));
    }
    for (words) |w| {
        const end = spells(bytes, at, w) orelse continue;
        return settled(bytes, end);
    }
    // `not in`, whose two halves may be any distance apart on one line - and
    // whose first half needs no boundary, where all five other words do. The
    // specification checks `is_token_end` after `in` alone, so `notin` at the end
    // of a line is an operator to it. Transcribed rather than tidied: refusing it
    // would be a divergence nobody asked for, and a rule that reads the C is
    // worth more than one that reads better.
    if (!std.mem.startsWith(u8, bytes[@min(at, bytes.len)..], "not")) return false;
    var j: usize = at + 3;
    while (j < bytes.len and blank(bytes[j])) j += 1;
    const end = spells(bytes, @intCast(j), "in") orelse return false;
    return settled(bytes, end);
}

/// The longest operator the trie reaches without backing off, or null where it
/// descended into a branch nothing completed.
fn munch(bytes: []const u8, at: u32) ?usize {
    const run = bytes[@min(at, bytes.len)..];
    var n: usize = 0;
    var got: ?usize = null;
    while (true) {
        var accepts = false;
        var deeper = false;
        for (operators) |op| {
            if (op.len <= n or !std.mem.startsWith(u8, run, op[0 .. n + 1])) continue;
            if (op.len == n + 1) accepts = true else deeper = true;
        }
        // `startsWith` already demanded byte `n` be present and match, so
        // neither arm below can be reached past the end of input.
        if (!accepts and !deeper) return got;
        n += 1;
        got = if (accepts) n else null;
        if (!deeper) return got;
    }
}

/// `check_operator_end`: whether what follows an operator leaves it an operator.
///
/// Two ways it does not. A `:` behind it makes the whole run a keyword -
/// `foo:` - unless the `:` is not followed by whitespace, which is the
/// specification's double negative kept as one. And a `/` with a digit past it
/// makes the run an operator identifier with an arity, `&Enum.map/2`, which is a
/// name rather than an operation.
fn settled(bytes: []const u8, at: u32) bool {
    if (byte(bytes, at) == ':') return !(blank(byte(bytes, at + 1)) or line(byte(bytes, at + 1)));
    var i: usize = at;
    while (i < bytes.len and blank(bytes[i])) i += 1;
    if (byte(bytes, i) != '/') return true;
    i += 1;
    while (i < bytes.len and (blank(bytes[i]) or line(bytes[i]))) i += 1;
    return !std.ascii.isDigit(byte(bytes, i));
}

/// Where a word ends when the bytes at `at` spell it and a token boundary
/// follows, or null. The boundary is `is_token_end`, which is elixir's
/// heuristic and not a Unicode class - its own comment says so.
fn spells(bytes: []const u8, at: u32, word: []const u8) ?u32 {
    if (!std.mem.startsWith(u8, bytes[@min(at, bytes.len)..], word)) return null;
    const end: u32 = at + @as(u32, @intCast(word.len));
    return if (terminates(byte(bytes, end))) end else null;
}

/// `is_token_end`: an operator start, a delimiter, a separator, a `#`, or
/// whitespace. Zero - the specification's lookahead at end of input - is none of
/// them, so a word operator at the end of a file does not end.
fn terminates(ch: u8) bool {
    return switch (ch) {
        '@', '.', '+', '-', '^', '*', '/', '<', '>', '|', '~', '=', '&', '\\', '%' => true,
        '{', '}', '[', ']', '(', ')', '"', '\'', ',', ';', '#' => true,
        else => blank(ch) or line(ch),
    };
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

/// Whitespace that does not end a line. elixir's `is_inline_whitespace`, and
/// narrower than `space` on purpose: its scanner counts four bytes as whitespace
/// where the ecma one counts six.
fn blank(ch: u8) bool {
    return ch == ' ' or ch == '\t';
}

/// Whitespace that does. `is_newline`, which reads `\r\n` as two breaks and says
/// in its own comment that this is fine because several breaks mean one.
fn line(ch: u8) bool {
    return ch == '\n' or ch == '\r';
}

fn alpha(ch: u8) bool {
    return std.ascii.isAlphabetic(ch);
}

// ─────────────────────────────── tests ───────────────────────────────

const t = std.testing;

/// Every case is the spec's, read forward from offset zero as though a token
/// had just ended there.
fn asks(src: []const u8, ask: Asks) bool {
    return breaks(.ecma, src, 0, ask) != null;
}

/// The same for a tongue with no questions to put to the parser.
fn says(comptime which: Tongue, src: []const u8) ?Break {
    return breaks(which, src, 0, .{});
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

test "caesura: swift claims a spelled semicolon and skips the space before it" {
    // `should_treat_as_wspace` counts `;`, so one loop reaches both terminals.
    try t.expectEqual(Break{ .spelled = true, .skip = 0, .len = 1 }, says(.swift, ";").?);
    try t.expectEqual(Break{ .spelled = true, .skip = 2, .len = 1 }, says(.swift, "  ; let").?);
    // A newline first still yields the spelled one - the loop keeps going.
    try t.expectEqual(Break{ .spelled = true, .skip = 1, .len = 1 }, says(.swift, "\n;").?);
}

test "caesura: swift needs a line to end and end of file is not one" {
    try t.expectEqual(Break{}, says(.swift, "\nlet a = 1").?);
    try t.expect(says(.swift, " let") == null); // same line, nothing owed
    try t.expect(says(.swift, "") == null); // no newline was crossed
    try t.expectEqual(Break{}, says(.swift, "\n").?); // a file ending after one
}

test "caesura: swift breaks before a leading operator where ecma would not" {
    // The inversion. Swift requires a binary operator to end the line it
    // continues, so a line starting with one is a new statement.
    try t.expectEqual(Break{}, says(.swift, "\n+ 2").?);
    try t.expectEqual(Break{}, says(.swift, "\n= 2").?);
    try t.expectEqual(Break{}, says(.swift, "\n. foo").?);
    try t.expect(!asks("\n+ 2", .{})); // ecma, for contrast
    try t.expect(!asks("\n= 2", .{}));
}

test "caesura: swift suppresses on exactly the three the scanner names" {
    for ([_][]const u8{ "\n? x", "\n: x", "\n{ x" }) |src| {
        try t.expect(says(.swift, src) == null);
    }
    // And on nothing else - `[` and `(` open a statement in swift.
    for ([_][]const u8{ "\n[x]", "\n(x)", "\n<x>" }) |src| {
        try t.expectEqual(Break{}, says(.swift, src).?);
    }
}

test "caesura: swift steps over a comment and reads what follows it" {
    try t.expectEqual(Break{}, says(.swift, "\n// note\nlet a = 1").?);
    try t.expectEqual(Break{}, says(.swift, "\n/* note */ let a = 1").?);
    try t.expect(says(.swift, "\n/* note */ + 2") == null); // operator suppresses
    try t.expect(says(.swift, "\n/ 2") == null); // division continues the line
}

test "caesura: kotlin suppresses on its own list, not ecma's and not swift's" {
    // Unconditional where ecma asks the parser.
    for ([_][]const u8{ "\n{ x", "\n[x]", "\n(x)", "\n. foo", "\n= 2" }) |src| {
        try t.expect(says(.kotlin, src) == null);
    }
    // Absent from kotlin's list, so a leading `+` gets a separator.
    try t.expectEqual(Break{}, says(.kotlin, "\n+ 2").?);
    try t.expectEqual(Break{}, says(.kotlin, "\n!x").?);
    try t.expectEqual(Break{}, says(.kotlin, "\nval a = 1").?);
}

test "caesura: kotlin alone breaks with no newline, and only before import" {
    try t.expectEqual(Break{}, says(.kotlin, " import a.b").?);
    try t.expect(says(.kotlin, " index") == null);
    try t.expect(says(.kotlin, " val a = 1") == null);
    // A spelled one is claimed on either side of a newline.
    try t.expectEqual(Break{ .spelled = true, .skip = 0, .len = 1 }, says(.kotlin, ";").?);
    try t.expectEqual(Break{ .spelled = true, .skip = 1, .len = 1 }, says(.kotlin, " ; val").?);
    try t.expectEqual(Break{}, says(.kotlin, "").?); // the file ends
}
