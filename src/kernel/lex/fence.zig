//! Delimited spans: read an opener, remember what closes it, hunt the match.
//!
//! The second thing an external scanner is for, and the one that repeats
//! across languages. Python's `"""`, Ruby's `%w[]`, Rust's `r##"..."##`, C++'s
//! `R"tag(...)tag"`, a shell heredoc - every one of them is the same three
//! moves. Read an opening mark and *derive the closing mark from it*. Read
//! bytes until that mark. Consume the mark. Only the first move is per
//! language; the other two are one driver over whatever the first remembered,
//! which is why they are written once here.
//!
//! That is the honest boundary, and it is worth stating rather than reaching
//! past. There is no monoid over these: an opener is a small hand-written
//! reader of a spelling nobody else uses, and pretending otherwise would buy a
//! table that every language needs an escape hatch out of. What generalises is
//! the *memory* - a stack of marks - and the two moves that read against it.
//! So `Dialect` is a closed set of openers, `Span` is the mark they all
//! produce, and `body`/`close` are shared.
//!
//! A stack rather than a single mark, because a span can open inside a span:
//! `f"{ 'inner' }"` puts a plain string inside a format string, and Ruby's
//! `#{}` does the same. The stack depth is also what makes zero-width safe -
//! see `offside.zig` for why that matters.
//!
//! Every dialect here is derived from the pinned grammar's own `scanner.c`
//! read as a specification. Nothing is linked.

const std = @import("std");

/// The languages whose opener spelling this file can read. Adding one is a new
/// case in `open` plus a row in `outside.troupes`; nothing else moves.
pub const Dialect = enum { python, ruby, rust_raw, heredoc };

/// Which member of a fence family a token is. A grammar spells these under
/// its own names - Python says `string_start`, Ruby says `_string_start` -
/// and `outside.troupes` is the map from a name to a part.
pub const Part = enum { open, body, close, escape };

/// One open span, and everything needed to end it.
pub const Span = struct {
    dialect: Dialect,
    /// The bytes that close it. Three quotes for a Python triple, `"##` for a
    /// Rust raw string with two hashes, `)tag"` for a C++ raw string.
    mark: [34]u8 = undefined,
    mark_len: u8 = 0,
    /// The opening delimiter, when it nests: Ruby's `%w[a [b] c]` counts
    /// brackets, and zero means the delimiter does not pair.
    nest_open: u8 = 0,
    depth: u16 = 0,
    /// Which of the family's `open` terminals started it. Ruby has six of them
    /// sharing one `_string_end`, so the closer has to be told nothing and the
    /// opener has to be remembered.
    tag: u8 = 0,
    raw: bool = false,
    format: bool = false,
    bytes_only: bool = false,
    triple: bool = false,
    interpolates: bool = false,
    /// A whitespace run ends the element: Ruby's `%w[]` word arrays.
    space_ends: bool = false,
    /// The mark closes the span only at the start of a line. A bash heredoc
    /// ends at its delimiter written alone in column zero, and the same word
    /// in the middle of a body line is body.
    line_anchored: bool = false,

    pub fn closing(s: *const Span) []const u8 {
        return s.mark[0..s.mark_len];
    }

    fn remember(s: *Span, mark: []const u8) void {
        s.mark_len = @intCast(@min(mark.len, s.mark.len));
        @memcpy(s.mark[0..s.mark_len], mark[0..s.mark_len]);
    }
};

/// The stack of open spans. Fixed capacity for the same reason `Columns` is -
/// see `offside.zig`; sixteen nested literals is far past anything written on
/// purpose, and a seventeenth declines to open rather than reallocating a hot
/// path or pretending it opened.
pub const Spans = struct {
    open: [max]Span = undefined,
    len: u8 = 0,

    pub const max = 16;

    pub fn reset(s: *Spans) void {
        s.len = 0;
    }

    /// Whether two stacks are the same lexical state. See `Columns.same` for
    /// why a bare `std.meta.eql` on either stack is a trap: `open` past `len`
    /// is `undefined`, and so is each live `Span`'s `mark` past `mark_len`.
    pub fn same(a: *const Spans, b: *const Spans) bool {
        return std.meta.eql(a.flat(), b.flat());
    }

    fn flat(s: *const Spans) Spans {
        var out = s.*;
        for (out.open[0..out.len]) |*span| @memset(span.mark[span.mark_len..], 0);
        // Any one value will do for the dead entries as long as both sides get
        // the same one; python is the first dialect and carries no marks.
        for (out.open[out.len..]) |*span| span.* = .{ .dialect = .python };
        return out;
    }

    pub fn depth(s: *const Spans) u32 {
        return s.len;
    }

    pub fn innermost(s: *Spans) ?*Span {
        return if (s.len == 0) null else &s.open[s.len - 1];
    }

    pub fn push(s: *Spans, one: Span) bool {
        if (s.len == max) return false;
        s.open[s.len] = one;
        s.len += 1;
        return true;
    }

    pub fn pop(s: *Spans) void {
        if (s.len > 0) s.len -= 1;
    }
};

/// What an opener came to: how many bytes it spans, and the span it declares.
pub const Opened = struct { len: u32, span: Span };

/// How many openers one dialect may have. Ruby's six is the ceiling.
pub const tags = 6;

/// Which of a family's open terminals the state will accept, by tag.
///
/// Passed as data rather than asked back through a callback, because the whole
/// question is one bit per opener and a dialect has no business knowing what a
/// grammar symbol is. Ruby is why it exists at all: `/` opens a regex only
/// where a regex is legal, and is a division sign everywhere else.
pub const Admits = [tags]bool;

/// Read an opening mark at `at`, in one dialect's spelling.
pub fn open(dialect: Dialect, bytes: []const u8, at: u32, admits: Admits) ?Opened {
    return switch (dialect) {
        .python => openPython(bytes, at),
        .ruby => openRuby(bytes, at, admits),
        .rust_raw => openRustRaw(bytes, at),
        .heredoc => openHeredoc(bytes, at),
    };
}

/// Bash: the quoted delimiter of a heredoc, which closes it a line at a time.
///
/// Only the quoted spelling. An unquoted `<<EOF` expands `$x` inside the body,
/// which splits it into three terminals this row does not name, so it declines
/// and the grammar keeps the silence it has today rather than being handed a
/// body that swallowed an expansion. `<<-` declines for the same reason: it
/// strips leading tabs from both the body and the closer, and a span that
/// closed on an indented delimiter it did not know to expect would end in the
/// wrong place.
///
/// The delimiter is captured here and the body begins a line later, with the
/// rest of the redirect in between. Nothing has to hold that interval: the
/// grammar spells the newline inside `heredoc_redirect`, so the parser does
/// not ask for a body until it is past, and every fence hand answers only what
/// the parse table wants.
fn openHeredoc(bytes: []const u8, at: u32) ?Opened {
    var back = at;
    while (back > 0 and (bytes[back - 1] == ' ' or bytes[back - 1] == '\t')) back -= 1;
    if (back < 2 or !std.mem.eql(u8, bytes[back - 2 .. back], "<<")) return null;

    const quote = if (at < bytes.len) bytes[at] else return null;
    if (quote != '\'' and quote != '"') return null;
    const shut = std.mem.indexOfScalarPos(u8, bytes, at + 1, quote) orelse return null;
    const word = bytes[at + 1 .. shut];
    if (word.len == 0) return null;

    var span: Span = .{ .dialect = .heredoc, .raw = true, .line_anchored = true };
    if (word.len > span.mark.len) return null;
    span.remember(word);
    return .{ .len = @intCast(shut + 1 - at), .span = span };
}

/// Python: `rb`-style flags, then a quote, singly or tripled.
///
/// The flag letters and their meanings are the spec's: `f`/`t` format,
/// `r` raw, `b` bytes, `u` accepted and inert. A flag run with no quote after
/// it is not a string at all, which is what keeps the bare name `rb` from
/// opening one.
fn openPython(bytes: []const u8, at: u32) ?Opened {
    var i = at;
    var span: Span = .{ .dialect = .python };
    while (i < bytes.len) : (i += 1) switch (bytes[i]) {
        'f', 'F', 't', 'T' => span.format = true,
        'r', 'R' => span.raw = true,
        'b', 'B' => span.bytes_only = true,
        'u', 'U' => {},
        else => break,
    };
    if (i >= bytes.len) return null;
    const quote = bytes[i];
    if (quote != '"' and quote != '\'' and quote != '`') return null;
    i += 1;
    // A backquote is never tripled; the other two are, and only a run of
    // exactly three opens a triple - `''` is an empty string, not an opener.
    if (quote != '`' and i + 1 < bytes.len and bytes[i] == quote and bytes[i + 1] == quote) {
        i += 2;
        span.triple = true;
    }
    span.remember(if (span.triple) &[_]u8{ quote, quote, quote } else &[_]u8{quote});
    span.interpolates = span.format;
    return .{ .len = i - at, .span = span };
}

/// Ruby's open-delimiter table, by the part each spelling starts.
///
/// `tag` carries which part opened the span so the shared closer can name the
/// right terminal on the way out; the six openers share one `_string_end`.
fn openRuby(bytes: []const u8, at: u32, admits: Admits) ?Opened {
    if (at >= bytes.len) return null;
    var span: Span = .{ .dialect = .ruby, .tag = @intFromEnum(RubyStart.string) };
    switch (bytes[at]) {
        '"' => {
            span.interpolates = true;
            span.remember("\"");
            return .{ .len = 1, .span = span };
        },
        '\'' => {
            span.remember("'");
            return .{ .len = 1, .span = span };
        },
        '`' => {
            if (!admits[@intFromEnum(RubyStart.subshell)]) return null;
            span.tag = @intFromEnum(RubyStart.subshell);
            span.interpolates = true;
            span.remember("`");
            return .{ .len = 1, .span = span };
        },
        '/' => {
            if (!admits[@intFromEnum(RubyStart.regex)]) return null;
            span.tag = @intFromEnum(RubyStart.regex);
            span.interpolates = true;
            span.remember("/");
            return .{ .len = 1, .span = span };
        },
        '%' => return openRubyPercent(bytes, at, admits),
        else => return null,
    }
}

/// Which of Ruby's six literal openers a span was started by.
pub const RubyStart = enum(u8) { string, symbol, subshell, regex, string_array, symbol_array };

/// Ruby's `%`-literals. The letter picks the part, the byte after it is the
/// opening delimiter, and a paired delimiter nests.
fn openRubyPercent(bytes: []const u8, at: u32, admits: Admits) ?Opened {
    if (at + 1 >= bytes.len) return null;
    var i = at + 1;
    var span: Span = .{ .dialect = .ruby, .tag = @intFromEnum(RubyStart.string) };
    var interpolates = true;
    switch (bytes[i]) {
        's' => {
            span.tag = @intFromEnum(RubyStart.symbol);
            interpolates = false;
            i += 1;
        },
        'r' => {
            span.tag = @intFromEnum(RubyStart.regex);
            i += 1;
        },
        'x' => {
            span.tag = @intFromEnum(RubyStart.subshell);
            i += 1;
        },
        'q' => {
            interpolates = false;
            i += 1;
        },
        'Q' => i += 1,
        'w' => {
            span.tag = @intFromEnum(RubyStart.string_array);
            span.space_ends = true;
            interpolates = false;
            i += 1;
        },
        'W' => {
            span.tag = @intFromEnum(RubyStart.string_array);
            span.space_ends = true;
            i += 1;
        },
        'i' => {
            span.tag = @intFromEnum(RubyStart.symbol_array);
            span.space_ends = true;
            interpolates = false;
            i += 1;
        },
        'I' => {
            span.tag = @intFromEnum(RubyStart.symbol_array);
            span.space_ends = true;
            i += 1;
        },
        // A bare `%(` is a double-quoted string; anything else after `%` is
        // the modulo operator, which the slate owns.
        '(', '[', '{', '<', '|', '!' => {},
        else => return null,
    }
    if (i >= bytes.len) return null;
    if (!admits[span.tag]) return null;
    const opener = bytes[i];
    const closer: u8 = switch (opener) {
        '(' => ')',
        '[' => ']',
        '{' => '}',
        '<' => '>',
        // A non-paired delimiter closes with itself and never nests.
        '|', '!', '/', '"', '\'', '~', '^', '#', '*', '+', '-', '=', ',', '.', ':', ';', '?', '@', '_' => opener,
        else => return null,
    };
    if (closer != opener) span.nest_open = opener;
    span.interpolates = interpolates;
    span.remember(&[_]u8{closer});
    return .{ .len = i + 1 - at, .span = span };
}

/// Rust: `r`, a run of hashes, a quote. The close is the quote and the same
/// run, which is the whole point of the spelling.
fn openRustRaw(bytes: []const u8, at: u32) ?Opened {
    var i = at;
    if (i < bytes.len and (bytes[i] == 'b' or bytes[i] == 'c')) i += 1;
    if (i >= bytes.len or bytes[i] != 'r') return null;
    i += 1;
    const first_hash = i;
    while (i < bytes.len and bytes[i] == '#') i += 1;
    const hashes = i - first_hash;
    if (i >= bytes.len or bytes[i] != '"') return null;
    i += 1;
    var span: Span = .{ .dialect = .rust_raw, .raw = true };
    var mark: [34]u8 = undefined;
    mark[0] = '"';
    const kept = @min(hashes, mark.len - 1);
    @memset(mark[1 .. 1 + kept], '#');
    span.remember(mark[0 .. 1 + kept]);
    return .{ .len = i - at, .span = span };
}

/// What reading inside a span came to.
pub const Read = union(enum) {
    /// Bytes of content, none of which end the span.
    body: u32,
    /// The closing mark, this long. The caller pops.
    close: u32,
    /// An escaped brace in a Python format string: two bytes that mean one.
    escape: u32,
    /// Nothing this span can account for here - an interpolation opening, a
    /// bare newline in a single-quoted string. The slate takes over.
    none,
};

/// Read forward from `at` inside `span`, stopping at whatever ends the run.
///
/// One driver for every dialect, because after the opener they only differ in
/// which bytes interrupt: an interpolation, an escape, a newline, a space.
/// Content is greedy up to the first interruption and never past the mark, so
/// a caller that emits `body` and resumes always lands on the interruption
/// itself and never inside it.
pub fn read(span: *const Span, bytes: []const u8, at: u32) Read {
    const mark = span.closing();
    var i = at;
    // A line-anchored mark is only a close where a line begins; anywhere else
    // it is body, and the driver must not see it at all.
    const shuts = struct {
        fn here(sp: *const Span, b: []const u8, m: []const u8, k: u32) bool {
            if (!std.mem.startsWith(u8, b[k..], m)) return false;
            if (!sp.line_anchored) return true;
            return k == 0 or b[k - 1] == '\n';
        }
    }.here;
    // A span sitting on its own closing mark yields the close, not an empty
    // body: an empty `body` would be a zero-width token with nothing to show
    // for it, and the scan would never move.
    if (shuts(span, bytes, mark, i)) return .{ .close = @intCast(mark.len) };
    if (span.format and i < bytes.len and (bytes[i] == '{' or bytes[i] == '}')) {
        // `{{` and `}}` are one literal brace; a lone brace opens or closes an
        // interpolation, which is the parser's business rather than ours.
        if (i + 1 < bytes.len and bytes[i + 1] == bytes[i]) return .{ .escape = 2 };
        return .none;
    }
    if (span.interpolates and std.mem.startsWith(u8, bytes[i..], "#{")) return .none;
    while (i < bytes.len) {
        if (shuts(span, bytes, mark, i)) break;
        const c = bytes[i];
        if (c == '\\') {
            // A raw span keeps the backslash and whatever follows it; every
            // other span hands the escape to the grammar's own terminal, which
            // is immediate and so wins the offset back.
            if (span.raw) {
                i += if (i + 1 < bytes.len) 2 else 1;
                continue;
            }
            break;
        }
        if (span.format and (c == '{' or c == '}')) break;
        if (span.interpolates and std.mem.startsWith(u8, bytes[i..], "#{")) break;
        if (span.space_ends and std.ascii.isWhitespace(c)) break;
        if (c == '\n' and !span.triple and span.dialect == .python) break;
        if (span.nest_open != 0) {
            if (c == span.nest_open) {
                // Counted, not returned: a nested pair is content, and only the
                // unmatched close ends the span.
                var deeper = span.*;
                deeper.depth += 1;
                i += 1;
                return .{ .body = readNested(&deeper, bytes, i) - at };
            }
        }
        i += 1;
    }
    if (i == at) return .none;
    return .{ .body = i - at };
}

/// The tail of a nested run, once one opening bracket has been counted. Split
/// out so `read`'s common path carries no depth arithmetic at all.
fn readNested(span: *const Span, bytes: []const u8, from: u32) u32 {
    var depth = span.depth;
    var i = from;
    const closer = span.closing()[0];
    while (i < bytes.len and depth > 0) : (i += 1) {
        if (bytes[i] == '\\' and i + 1 < bytes.len) {
            i += 1;
            continue;
        }
        if (bytes[i] == span.nest_open) depth += 1;
        if (bytes[i] == closer) depth -= 1;
    }
    return i;
}

test "fence: a python triple opens on three quotes and one on one" {
    const three = openPython("\"\"\"body\"\"\"", 0).?;
    try std.testing.expectEqual(@as(u32, 3), three.len);
    try std.testing.expect(three.span.triple);
    try std.testing.expectEqualStrings("\"\"\"", three.span.closing());

    // `''` is the empty string, so the opener is one quote and the second is
    // already the close.
    const empty = openPython("''", 0).?;
    try std.testing.expectEqual(@as(u32, 1), empty.len);
    try std.testing.expect(!empty.span.triple);
}

test "fence: python flags set the span's temperament" {
    const f = openPython("f\"x\"", 0).?;
    try std.testing.expect(f.span.format and f.span.interpolates);
    try std.testing.expectEqual(@as(u32, 2), f.len);
    const rb = openPython("rb'x'", 0).?;
    try std.testing.expect(rb.span.raw and rb.span.bytes_only);
    // A flag run with no quote is a name, not a string.
    try std.testing.expect(openPython("rb", 0) == null);
}

test "fence: a rust raw string closes on the hashes it opened with" {
    const two = openRustRaw("r##\"x\"##", 0).?;
    try std.testing.expectEqual(@as(u32, 4), two.len);
    try std.testing.expectEqualStrings("\"##", two.span.closing());
    const bare = openRustRaw("r\"x\"", 0).?;
    try std.testing.expectEqualStrings("\"", bare.span.closing());
    try std.testing.expect(openRustRaw("rx", 0) == null);
}

test "fence: reading stops at the mark and yields the close on it" {
    const span = openPython("'abc'", 0).?.span;
    try std.testing.expectEqual(Read{ .body = 3 }, read(&span, "'abc'", 1));
    try std.testing.expectEqual(Read{ .close = 1 }, read(&span, "'abc'", 4));
}

test "fence: a format span stops at a brace and doubles it as an escape" {
    const span = openPython("f\"a{b}\"", 0).?.span;
    try std.testing.expectEqual(Read{ .body = 1 }, read(&span, "f\"a{b}\"", 2));
    try std.testing.expectEqual(Read.none, read(&span, "f\"a{b}\"", 3));
    try std.testing.expectEqual(Read{ .escape = 2 }, read(&span, "f\"a{{b\"", 3));
}

test "fence: a raw span keeps its backslashes and a cooked one hands them over" {
    const raw = openPython("r'a\\nb'", 0).?.span;
    try std.testing.expectEqual(Read{ .body = 4 }, read(&raw, "r'a\\nb'", 2));
    const cooked = openPython("'a\\nb'", 0).?.span;
    try std.testing.expectEqual(Read{ .body = 1 }, read(&cooked, "'a\\nb'", 1));
}
