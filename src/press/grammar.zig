//! The grammar IR — what every front end lowers to, and the only thing the LR
//! builder reads.
//!
//! Deliberately smaller than a tree-sitter grammar. EBNF is already normalized
//! away (a `REPEAT` is an auxiliary nonterminal, a nested `CHOICE` is either
//! distributed or hoisted), tree-shaping metadata is already dropped (`ALIAS`,
//! `FIELD`, and `supertypes` decide what a node is *called*, never what the
//! parser *does*), and every symbol is an integer. What survives is the part an
//! LR construction can consume: a symbol table, a flat production list, and the
//! precedence needed to break a shift/reduce tie.
//!
//! Symbols are one id space with terminals first. That ordering is not
//! cosmetic: an LR action table is indexed by terminal, a goto table by
//! nonterminal, and keeping each contiguous means both are dense slices rather
//! than maps.

const std = @import("std");

/// An index into `Grammar.names`. Terminals occupy `[0, terminal_count)` and
/// nonterminals the rest, so `isTerminal` is a comparison rather than a lookup.
pub const Symbol = u32;

/// Which way an equal-precedence shift/reduce tie falls. `none` leaves the
/// conflict unresolved, which is the honest answer and the thing rung 1 counts.
pub const Assoc = enum { none, left, right };

/// How a terminal recognizes itself in a byte stream. Nonterminals carry
/// `null`; a terminal whose pattern could not be rendered carries `.external`,
/// which is a promise the lexer cannot keep without a scanner we do not have.
pub const Pattern = union(enum) {
    /// An exact string, matched verbatim. Wins ties against a regex of equal
    /// length, the way every lexer generator resolves `if` against `[a-z]+`.
    literal: []const u8,
    /// A regex, matched longest-wins.
    regex: []const u8,
    /// Supplied by an external scanner. We have none, so a grammar that needs
    /// one is a grammar we cannot lex, and it must say so out loud.
    external,
};

pub const Production = struct {
    lhs: Symbol,
    rhs: []const Symbol,
    prec: i32 = 0,
    assoc: Assoc = .none,

    pub fn isEpsilon(p: Production) bool {
        return p.rhs.len == 0;
    }
};

/// A parsed, normalized grammar. Owns every slice it hands out through an
/// arena, so a caller may drop the source JSON the instant this returns.
pub const Grammar = struct {
    arena: std.heap.ArenaAllocator,
    name: []const u8,

    names: []const []const u8,
    patterns: []const ?Pattern,
    terminal_count: u32,

    productions: []const Production,
    /// `by_lhs[n]` are the indices into `productions` whose lhs is the
    /// nonterminal `terminal_count + n`. Built once because the LR closure
    /// asks for it on every item of every state.
    by_lhs: []const []const u32,

    /// The augmented start symbol. `productions[0]` is `start -> real_start`,
    /// and that single production is what "accept" means.
    start: Symbol,
    /// Terminals the lexer skips between tokens: whitespace, comments.
    extras: []const Symbol,
    /// Rule-name groups the grammar author declared ambiguous. Not acted on —
    /// recorded so a measured conflict can be checked against a declared one.
    declared_conflicts: []const []const Symbol,
    /// Terminals whose pattern we could not render. A non-empty list means any
    /// lexing result over this grammar is incomplete, and every consumer is
    /// required to surface that rather than quietly mis-tokenize.
    externals: []const Symbol,

    pub fn deinit(g: *Grammar) void {
        g.arena.deinit();
        g.* = undefined;
    }

    pub fn symbolCount(g: *const Grammar) u32 {
        return @intCast(g.names.len);
    }

    pub fn nonterminalCount(g: *const Grammar) u32 {
        return g.symbolCount() - g.terminal_count;
    }

    pub fn isTerminal(g: *const Grammar, s: Symbol) bool {
        return s < g.terminal_count;
    }

    pub fn nameOf(g: *const Grammar, s: Symbol) []const u8 {
        return g.names[s];
    }

    /// The productions of a nonterminal. Empty for a terminal, which is what a
    /// closure over a mixed symbol wants rather than an error.
    pub fn productionsOf(g: *const Grammar, s: Symbol) []const u32 {
        if (g.isTerminal(s)) return &.{};
        return g.by_lhs[s - g.terminal_count];
    }
};

/// Accumulates a grammar while a front end walks its source. Front ends differ
/// in what they read; none of them should differ in how a symbol gets interned
/// or how a production gets recorded.
pub const Builder = struct {
    gpa: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,

    terminals: std.ArrayList(Entry) = .empty,
    nonterminals: std.ArrayList(Entry) = .empty,
    productions: std.ArrayList(Production) = .empty,
    /// Interning key -> the *unresolved* symbol. Terminals are stored as their
    /// own index; nonterminals as `nonterminal_bias + index`, because the final
    /// terminal count is not known until the walk finishes.
    interned: std.StringHashMap(u32),

    const nonterminal_bias: u32 = 1 << 31;

    const Entry = struct { name: []const u8, pattern: ?Pattern };

    /// Whether an *unresolved* symbol — one still carrying the builder's bias —
    /// landed in the terminal space. A front end asks this to decide whether a
    /// rule it already interned still needs its body expanded into productions.
    pub fn isTerminalRaw(s: u32) bool {
        return s < nonterminal_bias;
    }

    pub fn init(gpa: std.mem.Allocator) Builder {
        return .{
            .gpa = gpa,
            .arena = std.heap.ArenaAllocator.init(gpa),
            .interned = std.StringHashMap(u32).init(gpa),
        };
    }

    pub fn deinit(b: *Builder) void {
        b.terminals.deinit(b.gpa);
        b.nonterminals.deinit(b.gpa);
        b.productions.deinit(b.gpa);
        b.interned.deinit();
        b.arena.deinit();
    }

    pub fn dupe(b: *Builder, bytes: []const u8) ![]const u8 {
        return b.arena.allocator().dupe(u8, bytes);
    }

    /// Intern a symbol under `key`, creating it with `pattern` if new. The key
    /// is the front end's namespacing problem: a rule named `string` and the
    /// anonymous literal `"string"` are different symbols and must not collide.
    pub fn intern(b: *Builder, key: []const u8, name: []const u8, pattern: ?Pattern) !u32 {
        const slot = try b.interned.getOrPut(key);
        if (slot.found_existing) return slot.value_ptr.*;
        slot.key_ptr.* = try b.dupe(key);
        const entry: Entry = .{ .name = try b.dupe(name), .pattern = pattern };
        if (pattern != null) {
            try b.terminals.append(b.gpa, entry);
            slot.value_ptr.* = @intCast(b.terminals.items.len - 1);
        } else {
            try b.nonterminals.append(b.gpa, entry);
            slot.value_ptr.* = nonterminal_bias + @as(u32, @intCast(b.nonterminals.items.len - 1));
        }
        return slot.value_ptr.*;
    }

    pub fn addProduction(b: *Builder, lhs: u32, rhs: []const u32, prec: i32, assoc: Assoc) !void {
        try b.productions.append(b.gpa, .{
            .lhs = lhs,
            .rhs = try b.arena.allocator().dupe(u32, rhs),
            .prec = prec,
            .assoc = assoc,
        });
    }

    /// Resolve the two-space symbol numbering into one contiguous space and
    /// hand back an owning grammar. The caller adds the augmented production
    /// before finishing, so that accept is always `productions[0]`.
    ///
    /// The builder is left empty rather than invalid, so the `defer b.deinit()`
    /// a caller needs for the error path stays correct after a success. An
    /// interface that leaks unless you notice which of two cleanup keywords
    /// applies is an interface that will leak.
    pub fn finish(
        b: *Builder,
        name: []const u8,
        start: u32,
        extras: []const u32,
        conflicts: []const []const u32,
    ) !Grammar {
        const a = b.arena.allocator();
        const tcount: u32 = @intCast(b.terminals.items.len);
        const total = tcount + @as(u32, @intCast(b.nonterminals.items.len));

        const names = try a.alloc([]const u8, total);
        const patterns = try a.alloc(?Pattern, total);
        for (b.terminals.items, 0..) |e, i| {
            names[i] = e.name;
            patterns[i] = e.pattern;
        }
        for (b.nonterminals.items, 0..) |e, i| {
            names[tcount + i] = e.name;
            patterns[tcount + i] = null;
        }

        // Rewrite every production in place: the biased nonterminal ids become
        // `tcount + index`, terminals keep theirs.
        const resolve = struct {
            fn one(s: u32, t: u32) Symbol {
                return if (s >= nonterminal_bias) t + (s - nonterminal_bias) else s;
            }
        }.one;
        for (b.productions.items) |*p| {
            p.lhs = resolve(p.lhs, tcount);
            const rhs = @constCast(p.rhs);
            for (rhs) |*s| s.* = resolve(s.*, tcount);
        }

        var counts = try a.alloc(u32, b.nonterminals.items.len);
        @memset(counts, 0);
        for (b.productions.items) |p| counts[p.lhs - tcount] += 1;
        const by_lhs = try a.alloc([]const u32, b.nonterminals.items.len);
        for (by_lhs, counts) |*slot, n| slot.* = try a.alloc(u32, n);
        @memset(counts, 0);
        for (b.productions.items, 0..) |p, i| {
            const n = p.lhs - tcount;
            @constCast(by_lhs[n])[counts[n]] = @intCast(i);
            counts[n] += 1;
        }

        const resolved_extras = try a.alloc(Symbol, extras.len);
        for (resolved_extras, extras) |*slot, s| slot.* = resolve(s, tcount);
        const resolved_conflicts = try a.alloc([]const Symbol, conflicts.len);
        for (resolved_conflicts, conflicts) |*slot, group| {
            const g = try a.alloc(Symbol, group.len);
            for (g, group) |*s, raw| s.* = resolve(raw, tcount);
            slot.* = g;
        }

        var externals: std.ArrayList(Symbol) = .empty;
        for (patterns, 0..) |p, i| {
            if (p) |pat| if (pat == .external) try externals.append(a, @intCast(i));
        }

        // The arena is moved *after* every allocation above, not as a field of
        // the same literal. A struct literal evaluates in source order, so an
        // arena captured first holds the buffer list as it was then — and every
        // buffer the later fields append is invisible to it, which frees
        // nothing and reads as a leak with no bad pointer anywhere.
        var g: Grammar = .{
            .arena = undefined,
            .name = try a.dupe(u8, name),
            .names = names,
            .patterns = patterns,
            .terminal_count = tcount,
            .productions = try a.dupe(Production, b.productions.items),
            .by_lhs = by_lhs,
            .start = resolve(start, tcount),
            .extras = resolved_extras,
            .declared_conflicts = resolved_conflicts,
            .externals = try externals.toOwnedSlice(a),
        };
        g.arena = b.arena;
        b.arena = std.heap.ArenaAllocator.init(b.gpa);
        b.terminals.clearAndFree(b.gpa);
        b.nonterminals.clearAndFree(b.gpa);
        b.productions.clearAndFree(b.gpa);
        b.interned.clearAndFree();
        return g;
    }
};

test "builder interns each key once and separates the two symbol spaces" {
    var b = Builder.init(std.testing.allocator);
    defer b.deinit();

    const lit = try b.intern("str:if", "if", .{ .literal = "if" });
    const lit_again = try b.intern("str:if", "if", .{ .literal = "if" });
    const rule = try b.intern("rule:if", "if_statement", null);
    try std.testing.expectEqual(lit, lit_again);
    try std.testing.expect(lit != rule);

    const start = try b.intern("rule:$start", "$start", null);
    try b.addProduction(start, &.{rule}, 0, .none);
    try b.addProduction(rule, &.{lit}, 0, .none);

    var g = try b.finish("t", start, &.{}, &.{});
    defer g.deinit();

    try std.testing.expectEqual(@as(u32, 1), g.terminal_count);
    try std.testing.expect(g.isTerminal(0));
    try std.testing.expect(!g.isTerminal(g.start));
    try std.testing.expectEqualStrings("if", g.nameOf(0));
    // Accept is productions[0], and the start symbol has exactly that one.
    try std.testing.expectEqual(@as(usize, 1), g.productionsOf(g.start).len);
    try std.testing.expectEqual(@as(u32, 0), g.productionsOf(g.start)[0]);
}
