//! The stack of open elements: what encloses what, and when a close is implied.
//!
//! The fourth thing an external scanner is for, and html is the language that
//! needs it. `fence` remembers a mark so it can find the *one* byte run that
//! ends a span; this remembers a whole ancestry, because an element's closer is
//! legal only against the element on top and a mismatch is a different
//! terminal rather than an error. `</div>` where a `<p>` is open is neither the
//! close of the `p` nor a failure - it is html's `erroneous_end_tag_name`, and
//! a lexer that cannot tell the two apart cannot lex html at all.
//!
//! Three things ride on the ancestry and none of them is expressible without
//! it:
//!
//!   * **A close is one of two terminals** depending on whether it matches the
//!     top. That is the whole of `<p>hi</p>`, and without it `p` never lexes as
//!     a tag name and every byte between the brackets falls to `text`.
//!   * **A close can be implied.** `<p>a<p>b` closes the first paragraph at the
//!     second `<`, because html says a `p` may not contain a `p`. The token is
//!     zero-width and its whole content is a decision over the ancestry.
//!   * **Raw text is chosen by the ancestry.** `raw_text` runs to `</SCRIPT` or
//!     `</STYLE` according to which of the two is open, and nothing at the
//!     offset says which.
//!
//! The containment rules are the html specification's, transcribed from the
//! pinned grammar's `tag.h` as data. They are closed and small: 125 element
//! names, 23 of them void, 26 that a paragraph may not contain, and eleven
//! parents with a rule of their own. Nothing is linked.
//!
//! On comparison, and it is the one place this file diverges from a naive
//! reading. The specification compares two tags by an enum member, falling back
//! to the spelling only for an element it does not know. The name-to-member
//! table is a bijection - 125 names, 125 members, no two names sharing one - so
//! comparing the uppercased spellings is the same predicate and needs no table.
//! Where it is *not* the same predicate is the one place the specification
//! compares members without that fallback, in `implied`'s search past the top:
//! there two different unknown elements both read as the unknown member and so
//! match each other. That is upstream behaviour rather than a rounding error,
//! so `known` exists to reproduce it and is used for nothing else.

const std = @import("std");

/// The languages whose element rules this file can read.
pub const Dialect = enum { html };

/// Which member of the family a token is.
///
/// `open` is three terminals rather than one because html names the script and
/// style openers separately - the grammar needs to know at the open that a raw
/// body is coming - so the opener says on the way out which it was, exactly as
/// a fence with several openers does.
pub const Part = enum { open, close, stray, implied, raw, shut };

/// One open element.
pub const Tag = struct {
    /// The uppercased spelling, which is the identity. Truncated at 32 bytes
    /// with the true length kept beside it, so two names differing in length
    /// can never collide and only two same-length unknown elements agreeing on
    /// a 32-byte prefix can - which is past anything written on purpose, and
    /// the same bound `fence.Span.mark` already lives with.
    name: [32]u8 = undefined,
    name_len: u8 = 0,
    /// The bytes the spelling really ran to, for the length half of identity.
    span: u8 = 0,

    pub fn spelling(t: *const Tag) []const u8 {
        return t.name[0..t.name_len];
    }

    /// Whether two open elements are the same element, which is html's
    /// `tag_eq`. See this file's header for why a spelling comparison is that
    /// predicate exactly rather than an approximation of it.
    pub fn eq(a: *const Tag, b: *const Tag) bool {
        return a.span == b.span and std.mem.eql(u8, a.spelling(), b.spelling());
    }

    /// Whether two open elements share html's enum member, which is `eq`
    /// everywhere except that two *unknown* elements share one. Only
    /// `implied`'s search past the top asks this.
    fn member(a: *const Tag, b: *const Tag) bool {
        if (a.eq(b)) return true;
        return !known(a.spelling()) and !known(b.spelling());
    }

    fn of(spelt: []const u8) Tag {
        var t: Tag = .{ .span = @intCast(@min(spelt.len, 255)) };
        t.name_len = @intCast(@min(spelt.len, t.name.len));
        for (spelt[0..t.name_len], 0..) |c, i| t.name[i] = std.ascii.toUpper(c);
        return t;
    }
};

/// The ancestry of open elements.
///
/// Deeper than `fence.Spans` because html nests for structure rather than for
/// quoting: a document that opens sixteen literals is pathological, one that
/// opens sixteen elements is a navigation bar. A sixty-fifth declines to open
/// rather than reallocating a hot path, which loses the close of the deepest
/// element and nothing else.
pub const Tags = struct {
    open: [max]Tag = undefined,
    len: u8 = 0,

    pub const max = 64;

    pub fn reset(s: *Tags) void {
        s.len = 0;
    }

    /// Whether two ancestries are the same lexical state. Use this and never
    /// `std.meta.eql`: `open` past `len` is `undefined`, and so is each live
    /// `Tag`'s `name` past `name_len`.
    pub fn same(a: *const Tags, b: *const Tags) bool {
        if (a.len != b.len) return false;
        for (a.open[0..a.len], b.open[0..b.len]) |*x, *y| if (!x.eq(y)) return false;
        return true;
    }

    pub fn depth(s: *const Tags) u32 {
        return s.len;
    }

    pub fn innermost(s: *const Tags) ?*const Tag {
        return if (s.len == 0) null else &s.open[s.len - 1];
    }

    pub fn push(s: *Tags, one: Tag) bool {
        if (s.len == max) return false;
        s.open[s.len] = one;
        s.len += 1;
        return true;
    }

    pub fn pop(s: *Tags) void {
        if (s.len > 0) s.len -= 1;
    }
};

/// Which of the family's openers a name is, which is what the grammar needs at
/// the open so it can expect a raw body.
pub const Opener = enum(u8) { plain = 0, script = 1, style = 2 };

/// How many openers one dialect may have.
pub const tags = 3;

/// What an open came to.
pub const Opened = struct { len: u32, which: Opener, tag: Tag };

/// Read an element name at `at`, uppercased, and say which opener it is.
///
/// The specification's `scan_tag_name`: alphanumerics, `-` and `:`. A name of
/// no bytes is not a name, which is what makes `< >` fall through to the
/// slate rather than opening an element with an empty spelling.
pub fn open(dialect: Dialect, bytes: []const u8, at: u32) ?Opened {
    switch (dialect) {
        .html => {},
    }
    const n = name(bytes, at);
    if (n == 0) return null;
    const tag = Tag.of(bytes[at .. at + n]);
    const which: Opener = if (std.mem.eql(u8, tag.spelling(), "SCRIPT"))
        .script
    else if (std.mem.eql(u8, tag.spelling(), "STYLE"))
        .style
    else
        .plain;
    return .{ .len = n, .which = which, .tag = tag };
}

/// What a close came to. `matched` false is html's `erroneous_end_tag_name`,
/// which is a token rather than a refusal.
pub const Closed = struct { len: u32, matched: bool };

/// Read an element name at `at` and say whether it closes the innermost open
/// element. Null when there is no name.
pub fn close(stack: *const Tags, bytes: []const u8, at: u32) ?Closed {
    const n = name(bytes, at);
    if (n == 0) return null;
    const tag = Tag.of(bytes[at .. at + n]);
    const top = stack.innermost() orelse return .{ .len = n, .matched = false };
    return .{ .len = n, .matched = top.eq(&tag) };
}

/// Whether the ancestry owes a close at `at`, where `at` is the `<` of the next
/// tag or the end of input.
///
/// The token is zero-width by construction: html's scanner marks the end
/// before it advances over the `<`, so everything read here is lookahead. Four
/// arms, and they are the specification's in its order:
///
///   * an open void element - `<br>` has no close, so the next tag ends it;
///   * a closing tag that does not match the top, but does match something
///     deeper, which unwinds one level per ask until it does match;
///   * an opening tag its would-be parent may not contain, which is the
///     paragraph and list-item rule and the reason html is legible at all;
///   * end of input under an unclosed `html`, `head` or `body`.
pub fn implied(stack: *const Tags, bytes: []const u8, at: u32) bool {
    const top = stack.innermost() orelse return false;
    // `at` past the last byte is end of input, which the fourth arm answers.
    const eof = at >= bytes.len;
    const closing = !eof and bytes[at] == '<' and at + 1 < bytes.len and bytes[at + 1] == '/';
    // A void element ends at anything that is not its own close, and *including*
    // end of input: `<br>` alone is a whole document. Reading this arm as the
    // next tag's business rather than the void element's is what left `<br>`
    // truncated where `<br><p>` was exact, which is the shape of wrong that only
    // an unclosed file shows.
    if (!closing and voided(top.spelling())) return true;

    const from = at + if (closing) @as(u32, 2) else if (eof) @as(u32, 0) else @as(u32, 1);
    const n = if (eof) 0 else name(bytes, from);
    if (n == 0 and !eof) return false;
    const next = Tag.of(if (n == 0) "" else bytes[from .. from + n]);

    if (closing) {
        // Strict here and loose in the search, which is the specification's own
        // asymmetry rather than a slip: the early-out asks "does this close the
        // top exactly", and only the search past the top falls back to the enum
        // member. Using the loose predicate for both makes `<my-a><my-b>x</my-a>`
        // report a stray close instead of unwinding, because two unknown
        // elements share a member while differing in spelling.
        if (top.eq(&next)) return false;
        var i = stack.len;
        while (i > 0) : (i -= 1) if (stack.open[i - 1].member(&next)) return true;
        return false;
    }
    if (!contains(top.spelling(), next.spelling())) return true;
    return eof and roots(top.spelling());
}

/// The closing mark a raw body runs to, chosen by what is open. Null when
/// nothing is, which is the specification returning false rather than reading
/// to the end of the file.
pub fn raw(stack: *const Tags) ?[]const u8 {
    const top = stack.innermost() orelse return null;
    return if (std.mem.eql(u8, top.spelling(), "SCRIPT")) "</SCRIPT" else "</STYLE";
}

/// How far a raw body runs, case-insensitively, before its closing mark.
///
/// Always an answer, never a refusal: a script whose closer never arrives is
/// raw text to the end of the file, which is what the specification does and
/// which makes an unterminated `<script>` a parsed document rather than a
/// stall. Zero is legal too and means the body is empty - `<script></script>`.
///
/// Two details that a search for the mark gets wrong, both of them the
/// specification's own state machine rather than accidents of its C:
///
///   * **A failed partial match does not back up.** The extent is measured to
///     the last byte that *mismatched*, and the scan resumes from wherever the
///     failed attempt left the cursor, so a mark overlapping its own prefix is
///     missed. `</</SCRIPT` is the witness: a search finds the closer four
///     bytes in, the specification reads the whole line as body.
///   * **A partial match at end of input is not body.** `f()</SCRIP` is three
///     bytes of raw text, not ten, because the extent was last marked before
///     the run that went on to fail.
pub fn reach(shut: []const u8, bytes: []const u8, at: u32) u32 {
    var end = at;
    var seen: usize = 0;
    var i = at;
    while (i < bytes.len) {
        if (std.ascii.toUpper(bytes[i]) == shut[seen]) {
            seen += 1;
            if (seen == shut.len) break;
            i += 1;
        } else {
            seen = 0;
            i += 1;
            end = i;
        }
    }
    return end - at;
}

fn name(bytes: []const u8, at: u32) u32 {
    var i = at;
    while (i < bytes.len) : (i += 1) {
        const c = bytes[i];
        if (!std.ascii.isAlphanumeric(c) and c != '-' and c != ':') break;
    }
    return i - at;
}

/// Whether a parent may hold a child, which is html's `tag_can_contain`.
/// Eleven parents have a rule and everything else holds anything.
fn contains(parent: []const u8, child: []const u8) bool {
    const is = struct {
        fn one(a: []const u8, of: []const []const u8) bool {
            for (of) |b| if (std.mem.eql(u8, a, b)) return true;
            return false;
        }
    }.one;
    if (std.mem.eql(u8, parent, "LI")) return !std.mem.eql(u8, child, "LI");
    if (is(parent, &.{ "DT", "DD" })) return !is(child, &.{ "DT", "DD" });
    if (std.mem.eql(u8, parent, "P")) return !is(child, &paragraph_shuts);
    if (std.mem.eql(u8, parent, "COLGROUP")) return std.mem.eql(u8, child, "COL");
    if (is(parent, &.{ "RB", "RT", "RP" })) return !is(child, &.{ "RB", "RT", "RP" });
    if (std.mem.eql(u8, parent, "OPTGROUP")) return !std.mem.eql(u8, child, "OPTGROUP");
    if (std.mem.eql(u8, parent, "TR")) return !std.mem.eql(u8, child, "TR");
    if (is(parent, &.{ "TD", "TH" })) return !is(child, &.{ "TD", "TH", "TR" });
    return true;
}

/// The three elements an end of input closes, which is what lets a document
/// omit `</body></html>` as most do.
fn roots(tag: []const u8) bool {
    return std.mem.eql(u8, tag, "HTML") or
        std.mem.eql(u8, tag, "HEAD") or
        std.mem.eql(u8, tag, "BODY");
}

fn voided(tag: []const u8) bool {
    return in(tag, &voids);
}

/// Whether the specification's name table holds this spelling. See the header:
/// this exists only so that two *unknown* elements compare equal the way the
/// specification's enum makes them, and is asked nowhere else.
fn known(tag: []const u8) bool {
    return in(tag, &elements);
}

fn in(needle: []const u8, sorted: []const []const u8) bool {
    var lo: usize = 0;
    var hi: usize = sorted.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        switch (std.mem.order(u8, needle, sorted[mid])) {
            .eq => return true,
            .lt => hi = mid,
            .gt => lo = mid + 1,
        }
    }
    return false;
}

/// The elements that never hold content, so the next tag ends them.
const voids = [_][]const u8{
    "AREA",  "BASE",     "BASEFONT", "BGSOUND", "BR",     "COL",
    "COMMAND", "EMBED",  "FRAME",    "HR",      "IMAGE",  "IMG",
    "INPUT", "ISINDEX",  "KEYGEN",   "LINK",    "MENUITEM", "META",
    "NEXTID", "PARAM",   "SOURCE",   "TRACK",   "WBR",
};

/// The elements a paragraph may not contain, each of which therefore closes
/// one. This is why `<p>a<div>` is two siblings rather than a nesting.
const paragraph_shuts = [_][]const u8{
    "ADDRESS",    "ARTICLE", "ASIDE", "BLOCKQUOTE", "DETAILS", "DIV",
    "DL",         "FIELDSET", "FIGCAPTION", "FIGURE", "FOOTER", "FORM",
    "H1",         "H2",      "H3",    "H4",         "H5",      "H6",
    "HEADER",     "HR",      "MAIN",  "NAV",        "OL",      "P",
    "PRE",        "SECTION",
};

/// Every element the specification names, sorted for a binary search.
const elements = [_][]const u8{
    "A",       "ABBR",     "ADDRESS", "AREA",     "ARTICLE",  "ASIDE",
    "AUDIO",   "B",        "BASE",    "BASEFONT", "BDI",      "BDO",
    "BGSOUND", "BLOCKQUOTE", "BODY",  "BR",       "BUTTON",   "CANVAS",
    "CAPTION", "CITE",     "CODE",    "COL",      "COLGROUP", "COMMAND",
    "DATA",    "DATALIST", "DD",      "DEL",      "DETAILS",  "DFN",
    "DIALOG",  "DIV",      "DL",      "DT",       "EM",       "EMBED",
    "FIELDSET", "FIGCAPTION", "FIGURE", "FOOTER", "FORM",     "FRAME",
    "H1",      "H2",       "H3",      "H4",       "H5",       "H6",
    "HEAD",    "HEADER",   "HGROUP",  "HR",       "HTML",     "I",
    "IFRAME",  "IMAGE",    "IMG",     "INPUT",    "INS",      "ISINDEX",
    "KBD",     "KEYGEN",   "LABEL",   "LEGEND",   "LI",       "LINK",
    "MAIN",    "MAP",      "MARK",    "MATH",     "MENU",     "MENUITEM",
    "META",    "METER",    "NAV",     "NEXTID",   "NOSCRIPT", "OBJECT",
    "OL",      "OPTGROUP", "OPTION",  "OUTPUT",   "P",        "PARAM",
    "PICTURE", "PRE",      "PROGRESS", "Q",       "RB",       "RP",
    "RT",      "RTC",      "RUBY",    "S",        "SAMP",     "SCRIPT",
    "SECTION", "SELECT",   "SLOT",    "SMALL",    "SOURCE",   "SPAN",
    "STRONG",  "STYLE",    "SUB",     "SUMMARY",  "SUP",      "SVG",
    "TABLE",   "TBODY",    "TD",      "TEMPLATE", "TEXTAREA", "TFOOT",
    "TH",      "THEAD",    "TIME",    "TITLE",    "TR",       "TRACK",
    "U",       "UL",       "VAR",     "VIDEO",    "WBR",
};

test "tables are sorted, which the binary search assumes" {
    inline for (.{ elements, voids, paragraph_shuts }) |table| {
        var prev: []const u8 = "";
        for (table) |one| {
            try std.testing.expect(std.mem.order(u8, prev, one) == .lt);
            prev = one;
        }
    }
}

test "the spelling is the identity, uppercased and length-checked" {
    const a = Tag.of("div");
    const b = Tag.of("DIV");
    try std.testing.expect(a.eq(&b));
    try std.testing.expect(!a.eq(&Tag.of("dive")));
    // Two unknown elements are distinct by spelling but share html's member,
    // which only `implied`'s deep search reads.
    const x = Tag.of("my-a");
    const y = Tag.of("my-b");
    try std.testing.expect(!x.eq(&y));
    try std.testing.expect(x.member(&y));
    try std.testing.expect(!Tag.of("div").member(&Tag.of("span")));
}

test "a close matches the top or is the erroneous terminal" {
    var stack: Tags = .{};
    _ = stack.push(Tag.of("p"));
    try std.testing.expect(close(&stack, "p>", 0).?.matched);
    try std.testing.expect(!close(&stack, "div>", 0).?.matched);
    try std.testing.expectEqual(@as(u32, 3), close(&stack, "div>", 0).?.len);
    // No name is no token, which is what lets `</ >` reach the slate.
    try std.testing.expectEqual(@as(?Closed, null), close(&stack, ">", 0));
}

test "an unclosed paragraph is closed by what it may not contain" {
    var stack: Tags = .{};
    _ = stack.push(Tag.of("p"));
    try std.testing.expect(implied(&stack, "<p>", 0));
    try std.testing.expect(implied(&stack, "<div>", 0));
    // A paragraph may hold a span, so nothing is owed.
    try std.testing.expect(!implied(&stack, "<span>", 0));
    // Its own close is not implied; the close terminal takes it.
    try std.testing.expect(!implied(&stack, "</p>", 0));
}

test "a void element is closed by the next tag and by end of input" {
    var stack: Tags = .{};
    _ = stack.push(Tag.of("br"));
    try std.testing.expect(implied(&stack, "<p>", 0));
    // `<br>` alone is a whole document, so end of input closes it too. Only its
    // own close does not, because the close terminal takes that.
    try std.testing.expect(implied(&stack, "", 0));
    try std.testing.expect(!implied(&stack, "</br>", 0));
}

test "a close deeper than the top unwinds one level per ask" {
    var stack: Tags = .{};
    _ = stack.push(Tag.of("div"));
    _ = stack.push(Tag.of("span"));
    // `</div>` matches nothing on top but does match deeper, so the span is
    // owed a close first.
    try std.testing.expect(implied(&stack, "</div>", 0));
    // A close matching nothing at all owes nothing; it is erroneous instead.
    try std.testing.expect(!implied(&stack, "</table>", 0));
    // Its own close is not implied, and the predicate for that is strict: two
    // unknown elements share html's enum member, so `</my-a>` over an open
    // `my-b` unwinds rather than closing it.
    stack.reset();
    _ = stack.push(Tag.of("my-a"));
    _ = stack.push(Tag.of("my-b"));
    try std.testing.expect(implied(&stack, "</my-a>", 0));
    try std.testing.expect(!implied(&stack, "</my-b>", 0));
}

test "end of input closes an unclosed root" {
    var stack: Tags = .{};
    _ = stack.push(Tag.of("html"));
    try std.testing.expect(implied(&stack, "", 0));
    _ = stack.push(Tag.of("div"));
    // A div is not a root, so the file simply ends inside it.
    try std.testing.expect(!implied(&stack, "", 0));
}

test "raw text runs to its own closer, case-insensitively, and may be empty" {
    var stack: Tags = .{};
    _ = stack.push(Tag.of("script"));
    try std.testing.expectEqualStrings("</SCRIPT", raw(&stack).?);
    try std.testing.expectEqual(@as(u32, 0), reach("</SCRIPT", "</script>", 0));
    try std.testing.expectEqual(@as(u32, 4), reach("</SCRIPT", "f(1)</Script>", 0));
    // No closer is the whole file, not a refusal.
    try std.testing.expectEqual(@as(u32, 4), reach("</SCRIPT", "f(1)", 0));
    stack.pop();
    _ = stack.push(Tag.of("style"));
    try std.testing.expectEqualStrings("</STYLE", raw(&stack).?);
}

test "a raw body measures the spec's state machine, not a search for the mark" {
    // A failed partial match does not back up, so a mark overlapping its own
    // prefix is missed and the body swallows it. A search would answer 2.
    try std.testing.expectEqual(@as(u32, 10), reach("</SCRIPT", "</</SCRIPT", 0));
    // A partial match at end of input is not body: the extent was last marked
    // before the run that failed.
    try std.testing.expectEqual(@as(u32, 3), reach("</SCRIPT", "f()</SCRIP", 0));
    // And a complete mark right after one that failed is still found: the `<`
    // at 4 begins a match that `\n` breaks, and the real closer two bytes on
    // still ends the body.
    try std.testing.expectEqual(@as(u32, 2), reach("</SCRIPT", "</x <\n</script>", 4));
}

test "an opener names which of the three it is" {
    try std.testing.expectEqual(Opener.plain, open(.html, "p>", 0).?.which);
    try std.testing.expectEqual(Opener.script, open(.html, "script>", 0).?.which);
    try std.testing.expectEqual(Opener.style, open(.html, "STYLE>", 0).?.which);
    try std.testing.expectEqual(@as(u32, 6), open(.html, "my-tag>", 0).?.len);
    try std.testing.expectEqual(@as(?Opened, null), open(.html, ">", 0));
}

test "the ancestry answers for its own dead bytes" {
    var a: Tags = .{};
    var b: Tags = .{};
    try std.testing.expect(a.same(&b));
    _ = a.push(Tag.of("div"));
    try std.testing.expect(!a.same(&b));
    _ = b.push(Tag.of("DIV"));
    try std.testing.expect(a.same(&b));
    _ = b.push(Tag.of("p"));
    try std.testing.expect(!a.same(&b));
}
