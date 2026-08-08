//! The reader: `.scm` bytes in, one query's patterns out, and nothing about
//! any grammar.
//!
//! A rubric is the instruction written beside the text rather than the text
//! itself, which is what a query file is. This layer is deliberately ignorant:
//! it knows the shape of the notation and refuses a malformed one, and it has
//! no opinion on whether `binary_expression` is a rule anybody declared. That
//! separation is what lets the same reader serve thirty grammars and lets a
//! resolution failure name a grammar rather than a syntax error.
//!
//! **The corpus is the spec here and it disagrees with the documentation in
//! three places**, each of which cost a read of tree-sitter's own `query.c`:
//!
//!   1. Whitespace may sit between a pattern and its quantifier. Swift's
//!      `outline.scm` writes `_ * @name`, which the documented grammar does not
//!      admit and `ts_query_new` accepts, because it skips whitespace before
//!      looking for a suffix. Quantifiers and captures then interleave in one
//!      loop, so `(x)? @a` and `(x) @a ?` are the same pattern.
//!   2. `(` does not always open a node. Swift writes
//!      `declaration_kind: ( [ "actor" "class" ] ) @name` - a parenthesized
//!      *group*, which is a sequence and not a rule name. What decides is the
//!      first byte after the paren: a word starts a node, `#` starts a
//!      predicate, anything else starts a group.
//!   3. A predicate is written inside the pattern it constrains and belongs to
//!      the whole top-level pattern regardless of how deep it sits. Ocaml's
//!      `tags.scm` puts `#strip!` at group level; zig's `highlights.scm` puts
//!      `#any-of?` three nodes down. Both mean the same thing.
//!
//! Bare words are a fourth. `(#is-not? local)` and `(#offset! @g 0 1 0 -1)` are
//! real corpus lines, and tree-sitter reads an unquoted argument as a string,
//! so `-1` here is the two bytes and not a number. Nothing in this package ever
//! needs it to be a number, and inventing an integer case would be inventing a
//! type the notation does not have.

const std = @import("std");

/// How many of a thing may stand where one could. `one` is the unmarked case
/// and the only one that says nothing.
pub const Quantifier = enum { one, optional, star, plus };

/// What a query names at one position.
///
/// The two wildcards are deliberately *not* one case. Bare `_` is its own shape
/// and matches any node at all; `(_)` is a node whose kind happens to be `_`,
/// matches only a named one, and may carry children and fields like any other
/// node - `(field_expression (_) member: (identifier))` is a real corpus line.
/// Folding them together would have to drop the children.
pub const Shape = union(enum) {
    /// `(kind …)`, `(_ …)`, and `(super/kind …)` when the author constrained it
    /// by a category as well.
    node: Node,
    /// `"lit"` - an anonymous node, matched by the bytes it is spelled as.
    literal: []const u8,
    /// A bare `_`: any node, named or anonymous.
    wildcard,
    /// `( a b c )` - a sequence, which is what a bare paren opens when what
    /// follows it is not a word.
    group: []const Item,
    /// `[ a b c ]`
    choice: []const Item,
};

/// One position in a pattern, with everything true of it *here*: the field it
/// has to be filed under, how many of it there may be, what it is captured as,
/// and whether a `.` stood in front of it.
pub const Item = struct {
    shape: Shape,
    /// `field: pattern`.
    field: ?[]const u8 = null,
    quantifier: Quantifier = .one,
    /// `@name`, and a position may carry several.
    captures: []const []const u8 = &.{},
    /// A `.` immediately before this position. Inside a node it means "no
    /// sibling before this one"; between two positions it means "adjacent".
    anchored: bool = false,
    /// Byte offset in the source, for a diagnostic that can point.
    at: u32 = 0,
};

pub const Node = struct {
    /// The category in `(supertype/subtype)`, which constrains a concrete node
    /// by a name that never appears in the tree.
    supertype: ?[]const u8 = null,
    /// The rule name, or `_` for `(_)` - any named node.
    kind: []const u8,
    children: []const Item = &.{},
    /// `!field` - a field this node must NOT carry. One occurrence in eighty-two
    /// real files, and it is still a distinct fact from an absent constraint.
    absent: []const []const u8 = &.{},
    /// A trailing `.` before the closing paren: no sibling after the last child.
    closed: bool = false,
};

/// One argument to a predicate. A bare word is a string, which is tree-sitter's
/// own reading - `(#is-not? local)` passes the five bytes.
pub const Arg = union(enum) {
    capture: []const u8,
    text: []const u8,
};

/// `(#name? …)` or `(#name! …)`, verbatim. Nothing here decides whether the
/// name means anything; see `sift.zig` for the policy.
pub const Predicate = struct {
    name: []const u8,
    args: []const Arg,
    at: u32,
};

/// One top-level pattern and every predicate written anywhere inside it.
pub const Pattern = struct {
    root: Item,
    predicates: []const Predicate = &.{},
    at: u32 = 0,
};

/// A whole query file, read. Owns its arena, so the source bytes may go.
pub const Rubric = struct {
    arena: std.heap.ArenaAllocator,
    patterns: []const Pattern,

    pub fn deinit(r: *Rubric) void {
        r.arena.deinit();
        r.* = undefined;
    }
};

/// Every way the notation itself can be wrong. Resolution failures are not
/// here: `binary_expresion` is spelled fine and simply is not a rule.
pub const Error = error{
    /// A `(` or `[` with no partner, or a `)` closing nothing.
    QueryUnbalanced,
    /// A byte that starts nothing the notation admits.
    QueryUnexpected,
    /// A string that runs to the end of the file, or an escape the notation
    /// does not define.
    QueryBadString,
    /// `@` with no name after it, or `!` with no field.
    QueryBadName,
    /// A quantifier or an anchor with nothing to apply to.
    QueryDangling,
    /// Nesting deeper than `depth_limit`. A bound rather than a stack overflow.
    QueryTooDeep,
} || std.mem.Allocator.Error;

/// Where a refusal happened, which a query file needs far more than a table
/// does: eighty-two files and a byte offset is the difference between a fix and
/// a hunt.
pub const Fault = struct {
    at: u32 = 0,
    byte: u8 = 0,
    /// The name that could not be resolved, when that is what went wrong.
    /// Empty for a syntax refusal, where the byte says it. Borrowed from the
    /// source the caller handed in, so it lives exactly as long as that does -
    /// which is the whole reason it is a slice and not a copy: the caller is
    /// about to print it and move on.
    name: []const u8 = "",

    /// One-based line and column, counted on demand. Nothing pays for this
    /// until something has already failed.
    pub fn where(f: Fault, src: []const u8) struct { line: u32, column: u32 } {
        var line: u32 = 1;
        var column: u32 = 1;
        for (src[0..@min(f.at, src.len)]) |c| {
            if (c == '\n') {
                line += 1;
                column = 1;
            } else column += 1;
        }
        return .{ .line = line, .column = column };
    }
};

/// Deep enough for every real query and shallow enough that the recursion
/// cannot outrun a thread stack. The corpus's deepest pattern is eleven.
pub const depth_limit = 64;

/// Read a query file. `fault` is filled on every refusal and left alone on
/// success, so a caller may hand the same one to eighty-two files in a row.
pub fn read(gpa: std.mem.Allocator, src: []const u8, fault: ?*Fault) Error!Rubric {
    var out: Rubric = .{ .arena = .init(gpa), .patterns = &.{} };
    errdefer out.arena.deinit();

    var p: Reader = .{ .src = src, .arena = out.arena.allocator(), .gpa = gpa };
    defer p.deinit();
    errdefer {
        if (fault) |f| f.* = .{ .at = p.at, .byte = p.peek() orelse 0 };
    }

    var patterns: std.ArrayList(Pattern) = .empty;
    defer patterns.deinit(gpa);
    while (true) {
        p.skip();
        if (p.at >= src.len) break;
        const start = p.at;
        p.predicates.clearRetainingCapacity();
        // A bare predicate at top level constrains no pattern, so it is a
        // dangling constraint rather than a pattern of its own.
        const root = try p.item(0) orelse return Error.QueryDangling;
        // A quantifier at top level applies to nothing a match could repeat.
        if (root.quantifier != .one) return Error.QueryDangling;
        try patterns.append(gpa, .{
            .root = root,
            .predicates = try p.arena.dupe(Predicate, p.predicates.items),
            .at = start,
        });
    }
    out.patterns = try out.arena.allocator().dupe(Pattern, patterns.items);
    return out;
}

const Reader = struct {
    src: []const u8,
    arena: std.mem.Allocator,
    gpa: std.mem.Allocator,
    at: u32 = 0,
    /// The predicates of the pattern being read. Flat rather than per-node
    /// because that is where they belong: a predicate written three nodes deep
    /// constrains the whole pattern.
    predicates: std.ArrayList(Predicate) = .empty,
    scratch: Scratch = .{},

    /// Reusable child and capture buffers, one stack deep per nesting level.
    /// A query file is thousands of tiny lists and the arena would keep every
    /// intermediate; these are handed back and the arena only ever sees the
    /// exact-sized copy.
    const Scratch = struct {
        items: std.ArrayList(Item) = .empty,
        names: std.ArrayList([]const u8) = .empty,
        args: std.ArrayList(Arg) = .empty,

        fn deinit(s: *Scratch, gpa: std.mem.Allocator) void {
            s.items.deinit(gpa);
            s.names.deinit(gpa);
            s.args.deinit(gpa);
        }
    };

    fn deinit(r: *Reader) void {
        r.predicates.deinit(r.gpa);
        r.scratch.deinit(r.gpa);
        r.* = undefined;
    }

    fn peek(r: *const Reader) ?u8 {
        return if (r.at < r.src.len) r.src[r.at] else null;
    }

    fn at1(r: *const Reader, ahead: u32) ?u8 {
        const i = r.at + ahead;
        return if (i < r.src.len) r.src[i] else null;
    }

    /// Whitespace and `;` comments, which run to end of line.
    fn skip(r: *Reader) void {
        while (r.at < r.src.len) {
            const c = r.src[r.at];
            if (c == ';') {
                while (r.at < r.src.len and r.src[r.at] != '\n') r.at += 1;
            } else if (std.ascii.isWhitespace(c)) {
                r.at += 1;
            } else return;
        }
    }

    /// One position, suffixes and all, or null when what stood there was a
    /// predicate - which is written like a position and occupies none.
    /// `depth` is the recursion bound and not a fact about the pattern.
    fn item(r: *Reader, depth: u32) Error!?Item {
        if (depth >= depth_limit) return Error.QueryTooDeep;
        r.skip();
        const start = r.at;
        var out: Item = .{ .shape = undefined, .at = start };

        // A field prefix is a word glued to a colon. Nothing else in the
        // notation is a bare word at a position, so the lookahead is exact and
        // never has to be undone.
        if (r.wordAhead()) |n| {
            if (r.at1(n) == ':') {
                out.field = r.src[r.at..][0..n];
                r.at += n + 1;
                r.skip();
            }
        }

        out.shape = try r.shape(depth) orelse return null;
        try r.suffixes(&out);
        return out;
    }

    fn shape(r: *Reader, depth: u32) Error!?Shape {
        const c = r.peek() orelse return Error.QueryUnexpected;
        switch (c) {
            '"' => return .{ .literal = try r.string() },
            '[' => {
                r.at += 1;
                return .{ .choice = try r.list(depth + 1, ']') };
            },
            '(' => {
                r.at += 1;
                r.skip();
                // What follows the paren decides what it opened. See the header.
                if (r.peek() == '#') {
                    try r.predicate();
                    return null;
                }
                if (r.wordAhead()) |n| return .{ .node = try r.node(depth, n) };
                return .{ .group = try r.list(depth + 1, ')') };
            },
            '_' => {
                // A bare `_` outside parens: any node, named or not. A word
                // starting with `_` is a rule name and is not this.
                if (r.wordAhead().? > 1) return Error.QueryUnexpected;
                r.at += 1;
                return .wildcard;
            },
            // A closer where a pattern was expected is a closer with nothing
            // open, and saying so is worth the arm: `QueryUnexpected` would
            // report the byte and leave you to work out that the byte is fine
            // and the nesting is not. `list` handles the closers it is looking
            // for, so anything reaching here is genuinely surplus.
            ')', ']' => return Error.QueryUnbalanced,
            else => return Error.QueryUnexpected,
        }
    }

    /// `(kind …)` with the opening paren and the kind's length already known.
    fn node(r: *Reader, depth: u32, first: u32) Error!Node {
        var out: Node = .{ .kind = r.src[r.at..][0..first] };
        r.at += first;
        // `(super/sub …)`: the category, then the concrete kind.
        if (r.peek() == '/') {
            r.at += 1;
            const n = r.wordAhead() orelse return Error.QueryBadName;
            out.supertype = out.kind;
            out.kind = r.src[r.at..][0..n];
            r.at += n;
        }

        const mark = r.scratch.items.items.len;
        const named = r.scratch.names.items.len;
        defer r.scratch.items.shrinkRetainingCapacity(mark);
        defer r.scratch.names.shrinkRetainingCapacity(named);

        var anchored = false;
        while (true) {
            r.skip();
            switch (r.peek() orelse return Error.QueryUnbalanced) {
                ')' => {
                    r.at += 1;
                    break;
                },
                '.' => {
                    if (anchored) return Error.QueryDangling;
                    anchored = true;
                    r.at += 1;
                },
                '!' => {
                    r.at += 1;
                    const n = r.wordAhead() orelse return Error.QueryBadName;
                    try r.scratch.names.append(r.gpa, r.src[r.at..][0..n]);
                    r.at += n;
                },
                else => {
                    var child = try r.item(depth + 1) orelse continue;
                    child.anchored = anchored;
                    anchored = false;
                    try r.scratch.items.append(r.gpa, child);
                },
            }
        }
        // A `.` with nothing after it inside a node closes the child list.
        out.closed = anchored;
        out.children = try r.arena.dupe(Item, r.scratch.items.items[mark..]);
        out.absent = try r.arena.dupe([]const u8, r.scratch.names.items[named..]);
        return out;
    }

    /// A `[…]` or a `(…)` group: positions until the closer, anchors carried
    /// onto the position that follows them.
    fn list(r: *Reader, depth: u32, close: u8) Error![]const Item {
        const mark = r.scratch.items.items.len;
        defer r.scratch.items.shrinkRetainingCapacity(mark);
        var anchored = false;
        while (true) {
            r.skip();
            const c = r.peek() orelse return Error.QueryUnbalanced;
            if (c == close) {
                r.at += 1;
                break;
            }
            if (c == ')' or c == ']') return Error.QueryUnbalanced;
            if (c == '.') {
                if (anchored) return Error.QueryDangling;
                anchored = true;
                r.at += 1;
                continue;
            }
            var next = try r.item(depth + 1) orelse continue;
            next.anchored = anchored;
            anchored = false;
            try r.scratch.items.append(r.gpa, next);
        }
        return r.arena.dupe(Item, r.scratch.items.items[mark..]);
    }

    /// Quantifiers and captures, in one loop because the notation interleaves
    /// them and whitespace separates neither. See the header.
    fn suffixes(r: *Reader, out: *Item) Error!void {
        const mark = r.scratch.names.items.len;
        defer r.scratch.names.shrinkRetainingCapacity(mark);
        while (true) {
            r.skip();
            switch (r.peek() orelse break) {
                '?' => out.quantifier = .optional,
                '*' => out.quantifier = .star,
                '+' => out.quantifier = .plus,
                '@' => {
                    r.at += 1;
                    const n = r.wordAhead() orelse return Error.QueryBadName;
                    try r.scratch.names.append(r.gpa, r.src[r.at..][0..n]);
                    r.at += n;
                    continue;
                },
                else => break,
            }
            r.at += 1;
        }
        if (r.scratch.names.items.len > mark) {
            out.captures = try r.arena.dupe([]const u8, r.scratch.names.items[mark..]);
        }
    }

    /// `(#name …)`, with the `#` under the cursor and the paren already eaten.
    fn predicate(r: *Reader) Error!void {
        const start = r.at;
        r.at += 1;
        var n = r.wordAhead() orelse return Error.QueryBadName;
        // The trailing `?` or `!` is part of the name and not a quantifier.
        if (r.at1(n) == '?' or r.at1(n) == '!') n += 1;
        const name = r.src[r.at..][0..n];
        r.at += n;

        const mark = r.scratch.args.items.len;
        defer r.scratch.args.shrinkRetainingCapacity(mark);
        while (true) {
            r.skip();
            switch (r.peek() orelse return Error.QueryUnbalanced) {
                ')' => {
                    r.at += 1;
                    break;
                },
                '"' => try r.scratch.args.append(r.gpa, .{ .text = try r.string() }),
                '@' => {
                    r.at += 1;
                    const w = r.wordAhead() orelse return Error.QueryBadName;
                    try r.scratch.args.append(r.gpa, .{ .capture = r.src[r.at..][0..w] });
                    r.at += w;
                },
                else => {
                    const w = r.wordAhead() orelse return Error.QueryUnexpected;
                    try r.scratch.args.append(r.gpa, .{ .text = r.src[r.at..][0..w] });
                    r.at += w;
                },
            }
        }
        try r.predicates.append(r.gpa, .{
            .name = name,
            .args = try r.arena.dupe(Arg, r.scratch.args.items[mark..]),
            .at = start,
        });
    }

    /// A quoted string, unescaped into the arena. Unescaped rather than kept
    /// verbatim because every consumer wants the value: a `#match?` pattern is
    /// written `"^\\(\\*"` in the file and the regex engine has to be handed
    /// `^\(\*`.
    fn string(r: *Reader) Error![]const u8 {
        r.at += 1;
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(r.gpa);
        while (true) {
            const c = r.peek() orelse return Error.QueryBadString;
            r.at += 1;
            switch (c) {
                '"' => return r.arena.dupe(u8, out.items),
                '\\' => {
                    const e = r.peek() orelse return Error.QueryBadString;
                    r.at += 1;
                    try out.append(r.gpa, switch (e) {
                        'n' => '\n',
                        'r' => '\r',
                        't' => '\t',
                        '0' => 0,
                        // Everything else stands for itself, which is what
                        // makes `\\(` reach a regex as `\(` and `\"` as `"`.
                        else => e,
                    });
                },
                else => try out.append(r.gpa, c),
            }
        }
    }

    /// How many bytes of word start here, or null for none.
    ///
    /// One character class for kinds, fields, captures, predicate names and
    /// bare arguments, because the notation does not separate them and a
    /// narrower class per role would refuse real corpus lines: capture names
    /// carry `.` (`@comment.doc`), predicate arguments carry `-` (`-1`), and
    /// injection keys carry both (`injection.language`).
    fn wordAhead(r: *const Reader) ?u32 {
        var n: u32 = 0;
        while (r.at1(n)) |c| : (n += 1) {
            if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '-' and c != '.') break;
        }
        return if (n == 0) null else n;
    }
};

/// How many positions a pattern holds, itself included. The size a caller has
/// to budget before lowering one.
pub fn weigh(it: Item) u32 {
    return 1 + switch (it.shape) {
        .node => |n| blk: {
            var sum: u32 = 0;
            for (n.children) |c| sum += weigh(c);
            break :blk sum;
        },
        .group, .choice => |xs| blk: {
            var sum: u32 = 0;
            for (xs) |c| sum += weigh(c);
            break :blk sum;
        },
        .literal, .wildcard => 0,
    };
}
