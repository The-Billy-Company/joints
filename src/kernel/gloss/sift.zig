//! The predicate policy, and the four filters we run ourselves.
//!
//! **The policy, because the vocabulary is not closed and pretending otherwise
//! would refuse real files.** Three populations, decided by the spelling rather
//! than by a list, so a predicate nobody has met yet still lands somewhere:
//!
//!   1. **Core filters** - `#eq?`, `#not-eq?`, `#any-of?`, `#not-any-of?`,
//!      `#match?`, `#not-match?`. Compiled here, evaluated in the engine.
//!   2. **Directives** - anything ending in `!`. Metadata for the host; they do
//!      not filter anything, so they are carried verbatim and never evaluated.
//!      `#set!` is the most common `#` form in the corpus at eighty uses, and
//!      four of the corpus's spellings (`#strip!`, `#offset!`,
//!      `#select-adjacent!`, `#set-adjacent!`) are only ever read by an editor.
//!   3. **Foreign filters** - anything else ending in `?`. `#lua-match?`,
//!      `#is-not?`, `#has-ancestor?` and `#not-kind-eq?` are in the corpus and
//!      none of them is tree-sitter core; their semantics live in Neovim. They
//!      are carried opaque, and the refusal is deferred to whoever asks the
//!      engine to EVALUATE one.
//!
//! Carrying beats refusing here for one reason: a `highlights.scm` is worth
//! loading for its two thousand captures even when four lines of it are asking
//! for a Lua function we do not have. Refusing the file loses the two thousand
//! to save the four.
//!
//! **Why the core four are the lane's headline.** tree-sitter runs `#match?` in
//! the HOST BINDING - a callback per candidate match, across the FFI edge, with
//! the host's own regex engine. `#match?` is the second most common predicate
//! in the corpus at fifty-five uses. We already link a linear regex engine, so
//! the pattern is compiled once when the query is and evaluated in the core.
//! What the engine cannot do is hand back a *serialized* program, so the
//! compiled form is thrown away here and rebuilt once at folio load; the
//! saving is per candidate match, not per program.

const std = @import("std");
const irregex = @import("irregex");
const rubric = @import("rubric.zig");

/// What the engine will do with a predicate. `opaque_meta` is both directives
/// and foreign filters: the difference between them is whether anyone will ever
/// ask, and that question belongs to the matcher.
pub const Op = enum(u32) {
    /// The capture's text equals the other capture's text.
    eq_capture,
    not_eq_capture,
    /// The capture's text equals this string.
    eq_text,
    not_eq_text,
    /// The capture's text is one of these strings.
    any_of,
    not_any_of,
    /// The capture's text matches this regex.
    match,
    not_match,
    /// Carried, never run. See the header.
    opaque_meta,

    /// Does the engine evaluate this one itself?
    pub fn core(op: Op) bool {
        return op != .opaque_meta;
    }
};

pub const Error = error{
    /// A core predicate given the wrong NUMBER of arguments - `(#eq? @a)`.
    QueryPredicateArity,
    /// A core predicate given the right number of arguments of the wrong SORT -
    /// `(#match? "a" "b")`, which names no capture and so constrains nothing,
    /// or `(#match? @a @b)`, where the pattern is not known until the match and
    /// so cannot be compiled here at all.
    ///
    /// Two errors rather than one because they are two mistakes: an arity fault
    /// is a miscount and a shape fault is a misunderstanding of what the
    /// predicate is for, and a reader who is told "arity" about `(#match? "a"
    /// "b")` goes and counts the arguments, which are correct.
    QueryPredicateShape,
    /// A `#match?` whose pattern the regex engine will not compile. Refused
    /// here rather than at load, because a program that cannot be run is not a
    /// program.
    QueryBadRegex,
} || std.mem.Allocator.Error;

/// A predicate, classified and checked. The arguments stay `rubric`'s, so
/// nothing is copied until the program is laid out.
pub const Reading = struct {
    op: Op,
    name: []const u8,
    args: []const rubric.Arg,
    at: u32,
};

/// A trailing `!` is a directive. tree-sitter's own convention, and using the
/// spelling rather than a list is what lets a directive nobody has met yet
/// still load.
pub fn directive(name: []const u8) bool {
    return name.len > 0 and name[name.len - 1] == '!';
}

/// Classify one predicate and prove its arguments fit. Anything outside the
/// core four is `opaque_meta` and is never inspected further, which is the
/// policy: we do not get to have an opinion about `#lua-match?`'s arity.
pub fn read(gpa: std.mem.Allocator, p: rubric.Predicate) Error!Reading {
    const named = classify(p.name) orelse
        return .{ .op = .opaque_meta, .name = p.name, .args = p.args, .at = p.at };
    try shaped(named, p.args);
    if (named == .match or named == .not_match) try compiles(gpa, p.args[1].text);
    return .{ .op = resolve(named, p.args), .name = p.name, .args = p.args, .at = p.at };
}

fn classify(name: []const u8) ?Op {
    // `eq?` and `any-of?` each name two ops, and which one depends on the
    // second argument rather than the spelling, so the pair is resolved in
    // `shaped` where the arguments are in hand.
    const table = .{
        .{ "eq?", Op.eq_text },
        .{ "not-eq?", Op.not_eq_text },
        .{ "any-of?", Op.any_of },
        .{ "not-any-of?", Op.not_any_of },
        .{ "match?", Op.match },
        .{ "not-match?", Op.not_match },
    };
    inline for (table) |row| {
        if (std.mem.eql(u8, name, row[0])) return row[1];
    }
    return null;
}

/// The arity and argument sorts each core op takes. Every core predicate reads
/// a capture's text, so the first argument is a capture in all six; what varies
/// is how many follow and whether they may be captures too.
fn shaped(op: Op, args: []const rubric.Arg) Error!void {
    if (args.len == 0) return Error.QueryPredicateArity;
    if (args[0] != .capture) return Error.QueryPredicateShape;
    switch (op) {
        // The one pair where the second argument may be either, because that
        // choice IS the two readings `resolve` picks between.
        .eq_text, .not_eq_text => {
            if (args.len != 2) return Error.QueryPredicateArity;
        },
        .match, .not_match => {
            if (args.len != 2) return Error.QueryPredicateArity;
            if (args[1] != .text) return Error.QueryPredicateShape;
        },
        .any_of, .not_any_of => {
            if (args.len < 2) return Error.QueryPredicateArity;
            for (args[1..]) |a| if (a != .text) return Error.QueryPredicateShape;
        },
        else => unreachable,
    }
}

/// Which of the two `eq?` readings this argument list is. `#eq?` is one
/// spelling over two comparisons, and the program's op word has to say which.
fn resolve(op: Op, args: []const rubric.Arg) Op {
    return switch (op) {
        .eq_text => if (args[1] == .capture) .eq_capture else .eq_text,
        .not_eq_text => if (args[1] == .capture) .not_eq_capture else .not_eq_text,
        else => op,
    };
}

/// Prove the engine takes this pattern, then throw the program away. The
/// engine has no serialized form, so this buys a refusal at compile time
/// rather than a failure at load - which is the whole difference between a
/// program and a hope.
fn compiles(gpa: std.mem.Allocator, src: []const u8) Error!void {
    var p = irregex.Pattern.compile(gpa, src) catch return Error.QueryBadRegex;
    p.deinit();
}
