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
pub const Dialect = enum { python, ruby, rust_raw, heredoc, kotlin };

/// Which member of a fence family a token is. A grammar spells these under
/// its own names - Python says `string_start`, Ruby says `_string_start` -
/// and `outside.troupes` is the map from a name to a part.
pub const Part = enum { open, body, close, escape };

/// Which spelling of an interpolation opened, where a dialect has more than
/// one. Kotlin's `${expr}` and its `$name` are different terminals in its
/// grammar because only the first has a bracket to close on, so the reader has
/// to say which it found rather than just how wide it was.
pub const Sigil = enum { braced, bare };

/// How many spellings of an interpolation opening one dialect may have.
pub const sigils = @typeInfo(Sigil).@"enum".fields.len;

/// An interpolation opening: which spelling, and how wide the marker is.
pub const Enters = struct { which: Sigil, len: u32 };

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
    /// How many sigil bytes it takes to start an interpolation inside this
    /// span, when `interpolates`.
    ///
    /// Kotlin 2.1's multi-dollar strings are why this is on the span rather
    /// than in the reader: `$$"a $x b"` has no interpolation in it at all,
    /// because inside *that* literal it takes two `$` to begin one, and `$$$"`
    /// takes three. The width is a property of the opener, so the body cannot
    /// be read without the memory of how it opened - which is the same reason
    /// the pinned scanner writes it into `serialize` beside the delimiter.
    prefix_len: u8 = 0,

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

    /// `same` as a number, over the live prefix only - one flattened span at a
    /// time rather than `flat`'s whole-stack copy, because this runs once per
    /// token and the stack is empty for most of a file.
    pub fn digest(s: *const Spans, h: *std.hash.Wyhash) void {
        h.update(std.mem.asBytes(&s.len));
        for (s.open[0..s.len]) |span| {
            var one = span;
            @memset(one.mark[one.mark_len..], 0);
            h.update(std.mem.asBytes(&one));
        }
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
        .kotlin => openKotlin(bytes, at),
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

/// Kotlin: a run of `$` that fixes the interpolation sigil's width, then a
/// quote, singly or tripled.
///
/// The dollar run is the only part of this spelling that is not obvious, and it
/// is the reason `prefix_len` exists - see its header on `Span`. A bare `"`
/// still interpolates on one `$`, so a zero-length run means one and not none.
///
/// The count saturates rather than wrapping, because a file of ten thousand
/// dollar signs is not a string and the only thing that matters after 255 is
/// that no run in the body can ever reach the width; `>=` is what the reader
/// compares with, so a saturated width refuses every interpolation, which is
/// the safe direction for input nobody wrote on purpose.
fn openKotlin(bytes: []const u8, at: u32) ?Opened {
    var i = at;
    var prefix: u32 = 0;
    while (i < bytes.len and bytes[i] == '$') : (i += 1) prefix += 1;
    if (i >= bytes.len or bytes[i] != '"') return null;
    i += 1;
    var span: Span = .{
        .dialect = .kotlin,
        .interpolates = true,
        .prefix_len = @intCast(@max(1, @min(prefix, 255))),
    };
    // Exactly three opens a raw string; `""` is the empty one, and its second
    // quote is already the close.
    if (i + 1 < bytes.len and bytes[i] == '"' and bytes[i + 1] == '"') {
        i += 2;
        span.triple = true;
        span.raw = true;
    }
    span.remember(if (span.triple) "\"\"\"" else "\"");
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
    /// An interpolation opening the span itself spells, because its width is
    /// not a constant: Kotlin's sigil is a run whose length the opener fixed.
    /// The dialects whose interpolation is one fixed spelling - Python's `{`,
    /// Ruby's `#{` - answer `.none` here and let the grammar's own terminal
    /// take the bytes.
    enters: Enters,
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
    // Kotlin gets its own reader rather than four more flags on this one. All
    // three of its moves differ - the close is greedy where this driver closes
    // on first match, the sigil is a run rather than a fixed spelling, and a
    // backslash is matter inside a raw literal rather than a break - so folding
    // it in would have meant three conditionals on the path python, ruby,
    // rust_raw and heredoc walk, for no dialect that shares any of them.
    // Splitting is also what makes those four byte-identical by construction.
    if (span.dialect == .kotlin) return readKotlin(span, bytes, at);
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

/// Read inside a Kotlin literal, where three of the driver's four moves differ.
///
/// **The close is greedy.** `"""a""""` is the string `a"`, because a raw
/// literal terminates at the *last* `"""` in a run and not the first. Runs of
/// one and two quotes are matter outright, which is what lets `"""x "q" y"""`
/// hold a quoted word. This is the one place the hand parts company with the
/// pinned `scanner.c`, which swallows the whole run into its end token and
/// hands back `a` - correct as a parse and wrong as a value. The grammar's own
/// raw-string rule and the language reference both say `a"`, and `string_content`
/// is the node a reader would take the value from, so the language wins.
///
/// **A backslash is matter in a raw literal** and takes the byte after it
/// anywhere else. `string_literal` is `_string_start (string_content |
/// _interpolation)* _string_end` with no escape terminal in it at all, so an
/// escape is not handed over the way Python's is - `"a\"b"` is one content run
/// of four bytes, and a hand that broke on the backslash would close the
/// string on the quote it protects.
///
/// **A newline ends a line string.** Kotlin forbids one, and the cost of
/// reading past it is not a wrong node but a span that eats the rest of the
/// file; stopping leaves the bytes where the press's recovery can see them.
fn readKotlin(span: *const Span, bytes: []const u8, at: u32) Read {
    const shut = span.mark[0];
    var i = at;
    while (i < bytes.len) {
        const c = bytes[i];
        if (c == '$' and span.interpolates) switch (sigil(span, bytes, i)) {
            // Content first if any has accumulated, so the marker is always
            // emitted at the offset it sits on and never inside a run.
            .enters => |e| return if (i > at) .{ .body = i - at } else .{ .enters = e },
            .matter => |n| {
                i += n;
                continue;
            },
        };
        if (c == '\\' and !span.raw) {
            i += if (i + 1 < bytes.len) 2 else 1;
            continue;
        }
        if (c == '\n' and !span.triple) break;
        if (c == shut) {
            if (!span.triple) return if (i > at) .{ .body = i - at } else .{ .close = 1 };
            var run: u32 = 0;
            while (i + run < bytes.len and bytes[i + run] == shut) run += 1;
            if (run < 3) {
                // One or two quotes inside a raw literal are matter, and there
                // may be another run after them before the real close.
                i += run;
                continue;
            }
            // Every quote before the final three is still content.
            const keep = i + run - 3;
            return if (keep > at) .{ .body = keep - at } else .{ .close = 3 };
        }
        i += 1;
    }
    // A literal the file never closed, or a line string that met its newline.
    // Handing back what the bytes are is the difference between a file that is
    // unfinished and one that means something else - a blind reader calls
    // `"abc` at end of input three bytes of identifier.
    return if (i == at) .none else .{ .body = i - at };
}

/// What a `$` run inside a Kotlin literal comes to.
///
/// Three refusals, and each is a construct people write. Too few sigils for
/// the width the opener fixed is matter (`$x` inside `$$"..."`). A sigil with
/// nothing an identifier could start with after it is matter (`"$5.00"`), and
/// so is a sigil at end of input. An empty `${}` is matter as well, because
/// the grammar's `interpolated_expression` cannot be empty and answering the
/// bracket would leave the parser owing an expression the file does not have.
///
/// A run *longer* than the width yields one byte of content rather than the
/// excess, so the tail is asked again one byte along and the last `prefix_len`
/// sigils are the ones that count. That is the pinned scanner's arithmetic and
/// it is also the language's: in a single-dollar string `$$name` is a literal
/// dollar followed by an interpolation.
///
/// The name test is ASCII plus `_`, which is narrower than the specification's
/// `iswalpha` over a decoded codepoint. Kotlin allows Unicode identifiers, so
/// `"$名"` reads as content here where tree-sitter interpolates. Narrowing was
/// the deliberate direction: this file reads bytes, the corpus holds no such
/// literal, and a content run is recoverable where a wrongly opened
/// interpolation fells the statement around it.
fn sigil(span: *const Span, bytes: []const u8, at: u32) Sigilled {
    var j = at;
    while (j < bytes.len and bytes[j] == '$') j += 1;
    const run = j - at;
    if (run < span.prefix_len) return .{ .matter = run };
    if (run > span.prefix_len) return .{ .matter = 1 };
    if (j >= bytes.len) return .{ .matter = run };
    if (bytes[j] == '{') {
        if (j + 1 < bytes.len and bytes[j + 1] == '}') return .{ .matter = run };
        return .{ .enters = .{ .which = .braced, .len = run + 1 } };
    }
    if (bytes[j] == '_' or std.ascii.isAlphabetic(bytes[j])) {
        return .{ .enters = .{ .which = .bare, .len = run } };
    }
    return .{ .matter = run };
}

/// A sigil run's verdict. `matter` folds back into the content scan rather
/// than ending it, so `"$5.00 and $6"` is one content run and one marker
/// instead of five tokens split around every dollar the reader turned down.
const Sigilled = union(enum) { matter: u32, enters: Enters };

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

test "fence: a kotlin opener fixes the sigil width at the dollar run" {
    const one = openKotlin("\"a\"", 0).?;
    try std.testing.expectEqual(@as(u32, 1), one.len);
    try std.testing.expectEqual(@as(u8, 1), one.span.prefix_len);
    try std.testing.expect(!one.span.triple);

    const two = openKotlin("$$\"a\"", 0).?;
    try std.testing.expectEqual(@as(u32, 3), two.len);
    try std.testing.expectEqual(@as(u8, 2), two.span.prefix_len);

    const raw = openKotlin("\"\"\"a\"\"\"", 0).?;
    try std.testing.expectEqual(@as(u32, 3), raw.len);
    try std.testing.expect(raw.span.triple and raw.span.raw);
    try std.testing.expectEqualStrings("\"\"\"", raw.span.closing());

    // A dollar run with no quote after it is not a string at all.
    try std.testing.expect(openKotlin("$$x", 0) == null);
}

test "fence: a kotlin raw string closes on the last three quotes, not the first" {
    const src = "\"\"\"a\"\"\"\"";
    const span = openKotlin(src, 0).?.span;
    // `"""a""""` is the string `a"`: content takes the first quote of the run
    // of four, and the close is the final three.
    try std.testing.expectEqual(Read{ .body = 2 }, read(&span, src, 3));
    try std.testing.expectEqual(Read{ .close = 3 }, read(&span, src, 5));

    // One and two quotes inside the body are matter and do not end the run.
    const held = "\"\"\"x \"q\" y\"\"\"";
    const wide = openKotlin(held, 0).?.span;
    try std.testing.expectEqual(Read{ .body = 7 }, read(&wide, held, 3));
    try std.testing.expectEqual(Read{ .close = 3 }, read(&wide, held, 10));
}

test "fence: a kotlin line string carries its escapes and stops at a newline" {
    const src = "\"a\\\"b\"";
    const span = openKotlin(src, 0).?.span;
    // The escaped quote is inside the content run, because `string_literal`
    // has no escape terminal to hand it to.
    try std.testing.expectEqual(Read{ .body = 4 }, read(&span, src, 1));
    try std.testing.expectEqual(Read{ .close = 1 }, read(&span, src, 5));

    // A raw literal has no escapes, so the backslash is matter and the quote
    // behind it still closes.
    const raw = openKotlin("\"\"\"a\\\"\"\"", 0).?.span;
    try std.testing.expectEqual(Read{ .body = 2 }, read(&raw, "\"\"\"a\\\"\"\"", 3));

    // Kotlin forbids a newline in a line string; stopping is what keeps an
    // unterminated one from eating the rest of the file.
    try std.testing.expectEqual(Read{ .body = 3 }, read(&span, "\"abc\nx", 1));
}

test "fence: a kotlin sigil interpolates only at the width its opener fixed" {
    const one = openKotlin("\"\"", 0).?.span;
    try std.testing.expectEqual(
        Read{ .enters = .{ .which = .braced, .len = 2 } },
        read(&one, "\"${n}\"", 1),
    );
    try std.testing.expectEqual(
        Read{ .enters = .{ .which = .bare, .len = 1 } },
        read(&one, "\"$n\"", 1),
    );
    // A dollar nothing could name, and an empty expression, are both matter -
    // and matter folds back into the run rather than splitting it.
    try std.testing.expectEqual(Read{ .body = 5 }, read(&one, "\"$5.00\"", 1));
    try std.testing.expectEqual(Read{ .body = 3 }, read(&one, "\"${}\"", 1));

    // Two dollars fix the width at two: one is matter, two interpolate.
    const two = openKotlin("$$\"\"", 0).?.span;
    try std.testing.expectEqual(Read{ .body = 2 }, read(&two, "$$\"$n\"", 3));
    try std.testing.expectEqual(
        Read{ .enters = .{ .which = .bare, .len = 2 } },
        read(&two, "$$\"$$n\"", 3),
    );
    // A run longer than the width leaves the last `prefix_len` to interpolate.
    try std.testing.expectEqual(Read{ .body = 1 }, read(&one, "\"$$n\"", 1));
}

test "fence: a raw span keeps its backslashes and a cooked one hands them over" {
    const raw = openPython("r'a\\nb'", 0).?.span;
    try std.testing.expectEqual(Read{ .body = 4 }, read(&raw, "r'a\\nb'", 2));
    const cooked = openPython("'a\\nb'", 0).?.span;
    try std.testing.expectEqual(Read{ .body = 1 }, read(&cooked, "'a\\nb'", 1));
}
