//! The tree-sitter front end: `grammar.json` in, grammar IR out.
//!
//! This is the whole go-to-market in one file. Three hundred maintained
//! grammars with their highlight queries are person-decades of work that cannot
//! be out-engineered, and `grammar.json` is the declarative data file most of
//! those repositories already commit. So outliner does not ask anyone to
//! rewrite a grammar; it reads the one they have.
//!
//! Three things happen here, and nothing else:
//!
//!   1. **Terminals are separated from nonterminals.** A rule is a terminal
//!      when its body is a single lexical atom — a string, a pattern, or a
//!      `token(...)` — which is tree-sitter's own rule. Anything else is
//!      structure.
//!   2. **EBNF is normalized to BNF.** `repeat(x)` becomes a left-recursive
//!      auxiliary nonterminal, because left recursion is what keeps an LR
//!      stack bounded. A nested `choice` is distributed into the product when
//!      that is small and hoisted into an auxiliary when it is not.
//!   3. **Tree shaping is dropped.** `alias`, `field`, and `supertypes` decide
//!      what a node is *called*. They never decide what the parser *does*, so
//!      they do not survive into the IR.
//!
//! Two known approximations, both deliberate and both visible in the output
//! rather than hidden: precedence propagates by magnitude rather than by
//! tree-sitter's exact rule (it changes which conflicts resolve, never which
//! strings parse), and a grammar with external scanners keeps those terminals
//! as `.external`, which every consumer must refuse to lex rather than guess.

const std = @import("std");
const json = std.json;
const g = @import("grammar.zig");
const lexeme = @import("lexeme.zig");

pub const Error = error{ OutOfMemory, MalformedGrammar };

/// How many alternatives a `SEQ` may distribute into before its choices are
/// hoisted into auxiliary nonterminals instead. Distribution keeps the
/// automaton smaller and the stack effects tighter; unbounded distribution is
/// exponential. Sixty-four is above every product real grammars produce and
/// far below anything that hurts.
const seq_budget = 64;

const Prec = struct { value: i32 = 0, assoc: g.Assoc = .none };

/// One right-hand side under construction, with the precedence it inherited.
const Alt = struct { rhs: []const u32, prec: Prec };

pub fn treeSitter(gpa: std.mem.Allocator, source: []const u8) Error!g.Grammar {
    const parsed = json.parseFromSlice(json.Value, gpa, source, .{}) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.MalformedGrammar,
    };
    defer parsed.deinit();
    if (parsed.value != .object) return error.MalformedGrammar;
    const root = parsed.value.object;

    const rules = obj(root.get("rules")) orelse return error.MalformedGrammar;
    if (rules.count() == 0) return error.MalformedGrammar;
    const name = str(root.get("name")) orelse "grammar";

    var builder = g.Builder.init(gpa);
    errdefer builder.deinit();

    var imp: Import = .{
        .gpa = gpa,
        .b = &builder,
        .rules = &rules,
        .scratch = std.heap.ArenaAllocator.init(gpa),
        .prec_names = std.StringHashMap(i32).init(gpa),
        .symbols = std.StringHashMap(u32).init(gpa),
    };
    defer imp.deinit();

    try imp.readPrecedences(root.get("precedences"));
    try imp.internExternals(root.get("externals"));
    try imp.internRules();

    // The augmented production must be index 0, so that "accept" is a single
    // integer comparison for the rest of the system's life.
    const start = try imp.b.intern("aux:$start", "$start", null);
    const first = imp.symbols.get(rules.keys()[0]).?;
    try imp.b.addProduction(start, &.{first}, 0, .none);

    for (rules.keys(), rules.values()) |rule_name, body| {
        const sym = imp.symbols.get(rule_name).?;
        // A rule that resolved to a terminal contributes a token, not
        // structure; its body was already folded into the pattern.
        if (g.Builder.isTerminalRaw(sym)) continue;
        _ = imp.scratch.reset(.retain_capacity);
        for (try imp.alts(body, .{}, rule_name)) |alt| {
            try imp.b.addProduction(sym, alt.rhs, alt.prec.value, alt.prec.assoc);
        }
    }

    const extras = try imp.readExtras(root.get("extras"));
    const conflicts = try imp.readConflicts(root.get("conflicts"));
    return builder.finish(name, start, extras, conflicts);
}

const Import = struct {
    gpa: std.mem.Allocator,
    b: *g.Builder,
    rules: *const json.ObjectMap,
    scratch: std.heap.ArenaAllocator,
    prec_names: std.StringHashMap(i32),
    /// Rule name -> its symbol, whichever space it landed in.
    symbols: std.StringHashMap(u32),
    aux: u32 = 0,

    fn deinit(self: *Import) void {
        self.scratch.deinit();
        self.prec_names.deinit();
        self.symbols.deinit();
    }

    /// Named precedence orderings. Earlier in the list binds tighter, which is
    /// tree-sitter's convention, so rank descends with the index.
    fn readPrecedences(self: *Import, node: ?json.Value) Error!void {
        const outer = arr(node) orelse return;
        for (outer.items) |ordering| {
            const list = arr(ordering) orelse continue;
            for (list.items, 0..) |entry, i| {
                const label = switch (entry) {
                    .string => |s| s,
                    .object => str(entry.object.get("value")) orelse continue,
                    else => continue,
                };
                const rank: i32 = @intCast(list.items.len - i);
                try self.prec_names.put(label, rank);
            }
        }
    }

    /// External scanner tokens, interned before the rules so a rule of the same
    /// name resolves to the scanner's terminal rather than to its own body —
    /// which is exactly tree-sitter's precedence.
    fn internExternals(self: *Import, node: ?json.Value) Error!void {
        const list = arr(node) orelse return;
        for (list.items) |entry| {
            const n = str(obj(entry).?.get("name")) orelse continue;
            const sym = try self.b.intern(n, n, .external);
            try self.symbols.put(n, sym);
        }
    }

    fn internRules(self: *Import) Error!void {
        for (self.rules.keys(), self.rules.values()) |name, body| {
            if (self.symbols.get(name) != null) continue; // an external already claimed it
            // Both spaces share the rule-name key: a `SYMBOL` reference has to
            // find the rule under the name it used, whichever space it landed
            // in. Anonymous terminals are namespaced away under `str:`/`rx:`.
            const sym = try self.b.intern(name, name, try self.atomPattern(body));
            try self.symbols.put(name, sym);
        }
    }

    /// The pattern a node lexes as, when the node is a *single* lexical atom.
    /// Null means the node is structure. This is tree-sitter's own boundary:
    /// `choice('a','b')` is two tokens under one nonterminal, not one token.
    fn atomPattern(self: *Import, node: json.Value) Error!?g.Pattern {
        const o = obj(node) orelse return null;
        const kind = str(o.get("type")) orelse return null;

        if (std.mem.eql(u8, kind, "STRING")) {
            const v = str(o.get("value")) orelse return null;
            return .{ .literal = try self.b.dupe(v) };
        }
        if (std.mem.eql(u8, kind, "PATTERN") or
            std.mem.eql(u8, kind, "TOKEN") or
            std.mem.eql(u8, kind, "IMMEDIATE_TOKEN"))
        {
            return if (try self.renderPattern(node)) |rx| .{ .regex = rx } else null;
        }
        // A wrapper that only names or prioritizes still wraps a single atom.
        if (lexeme.isWrapper(kind)) {
            const content = o.get("content") orelse return null;
            return self.atomPattern(content);
        }
        return null;
    }

    fn renderPattern(self: *Import, node: json.Value) Error!?[]const u8 {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(self.gpa);
        const r: lexeme.Resolver = .{ .ctx = self, .lookup = lookupRule };
        if (!try lexeme.render(&out, self.gpa, node, r, 0)) return null;
        return try self.b.dupe(out.items);
    }

    /// A `SYMBOL` inside a token inlines the named rule's body. Returning it
    /// unconditionally is safe: the renderer fails on whatever it cannot
    /// flatten, and its depth limit ends a cycle.
    /// An external's name resolves to no body, so a token that reaches a
    /// scanner fails to render — which is the honest answer.
    fn lookupRule(ctx: *const anyopaque, name: []const u8) ?json.Value {
        const self: *const Import = @ptrCast(@alignCast(ctx));
        return self.rules.get(name);
    }

    /// Expand one rule body into the alternatives it contributes.
    fn alts(self: *Import, node: json.Value, ctx: Prec, owner: []const u8) Error![]Alt {
        const a = self.scratch.allocator();
        const o = obj(node) orelse return error.MalformedGrammar;
        const kind = str(o.get("type")) orelse return error.MalformedGrammar;

        if (std.mem.eql(u8, kind, "BLANK")) return try one(a, &.{}, ctx);

        if (std.mem.eql(u8, kind, "SYMBOL")) {
            const n = str(o.get("name")) orelse return error.MalformedGrammar;
            const sym = self.symbols.get(n) orelse return error.MalformedGrammar;
            return try one(a, &.{sym}, ctx);
        }

        if (std.mem.eql(u8, kind, "STRING") or
            std.mem.eql(u8, kind, "PATTERN") or
            std.mem.eql(u8, kind, "TOKEN") or
            std.mem.eql(u8, kind, "IMMEDIATE_TOKEN"))
        {
            const pattern = (try self.atomPattern(node)) orelse return error.MalformedGrammar;
            const key = switch (pattern) {
                .literal => |l| try std.fmt.allocPrint(a, "str:{s}", .{l}),
                .regex => |rx| try std.fmt.allocPrint(a, "rx:{s}", .{rx}),
                .external => unreachable, // an inline node never names a scanner
            };
            const display = switch (pattern) {
                .literal => |l| l,
                .regex => |rx| rx,
                .external => unreachable,
            };
            return try one(a, &.{try self.b.intern(key, display, pattern)}, ctx);
        }

        if (std.mem.eql(u8, kind, "ALIAS") or std.mem.eql(u8, kind, "FIELD")) {
            return self.alts(o.get("content") orelse return error.MalformedGrammar, ctx, owner);
        }

        if (std.mem.startsWith(u8, kind, "PREC")) {
            const inner = o.get("content") orelse return error.MalformedGrammar;
            // PREC_DYNAMIC steers GLR tie-breaking at runtime rather than table
            // construction, so it carries no static precedence.
            if (std.mem.eql(u8, kind, "PREC_DYNAMIC")) return self.alts(inner, ctx, owner);
            const next: Prec = .{
                .value = self.precValue(o.get("value")),
                .assoc = if (std.mem.eql(u8, kind, "PREC_LEFT"))
                    .left
                else if (std.mem.eql(u8, kind, "PREC_RIGHT"))
                    .right
                else
                    .none,
            };
            return self.alts(inner, next, owner);
        }

        if (std.mem.eql(u8, kind, "CHOICE")) {
            const members = arr(o.get("members")) orelse return error.MalformedGrammar;
            var out: std.ArrayList(Alt) = .empty;
            for (members.items) |m| try out.appendSlice(a, try self.alts(m, ctx, owner));
            return out.toOwnedSlice(a);
        }

        if (std.mem.eql(u8, kind, "SEQ")) {
            const members = arr(o.get("members")) orelse return error.MalformedGrammar;
            var acc = try one(a, &.{}, ctx);
            for (members.items) |m| {
                var next = try self.alts(m, ctx, owner);
                if (acc.len * next.len > seq_budget) next = try self.hoist(next, owner);
                acc = try product(a, acc, next);
            }
            return acc;
        }

        if (std.mem.eql(u8, kind, "REPEAT") or std.mem.eql(u8, kind, "REPEAT1")) {
            const content = o.get("content") orelse return error.MalformedGrammar;
            const body = try self.alts(content, .{}, owner);
            const aux = try self.auxSymbol(owner, "repeat");
            // Left recursion on purpose: `A -> A x` keeps the LR stack at
            // constant depth across a list, where right recursion grows it by
            // one frame per element.
            for (body) |alt| {
                if (std.mem.eql(u8, kind, "REPEAT1")) try self.b.addProduction(aux, alt.rhs, 0, .none);
                const looped = try a.alloc(u32, alt.rhs.len + 1);
                looped[0] = aux;
                @memcpy(looped[1..], alt.rhs);
                try self.b.addProduction(aux, looped, 0, .none);
            }
            if (!std.mem.eql(u8, kind, "REPEAT1")) try self.b.addProduction(aux, &.{}, 0, .none);
            return try one(a, &.{aux}, ctx);
        }

        return error.MalformedGrammar;
    }

    /// Give a set of alternatives its own nonterminal, so a `SEQ` can reference
    /// it once instead of distributing over it.
    fn hoist(self: *Import, set: []Alt, owner: []const u8) Error![]Alt {
        const aux = try self.auxSymbol(owner, "choice");
        for (set) |alt| try self.b.addProduction(aux, alt.rhs, alt.prec.value, alt.prec.assoc);
        return one(self.scratch.allocator(), &.{aux}, .{});
    }

    fn auxSymbol(self: *Import, owner: []const u8, tag: []const u8) Error!u32 {
        self.aux += 1;
        const name = try std.fmt.allocPrint(
            self.scratch.allocator(),
            "{s}_{s}{d}",
            .{ owner, tag, self.aux },
        );
        const key = try std.fmt.allocPrint(self.scratch.allocator(), "aux:{s}", .{name});
        return self.b.intern(key, name, null);
    }

    fn precValue(self: *const Import, node: ?json.Value) i32 {
        const v = node orelse return 0;
        return switch (v) {
            .integer => |i| @intCast(i),
            .float => |f| @intFromFloat(f),
            .string => |s| self.prec_names.get(s) orelse 0,
            else => 0,
        };
    }

    /// Terminals the lexer skips between tokens. A grammar may name a rule that
    /// turned out to be structure (a `comment` built from several tokens); it
    /// is recorded as it resolved, and it is the lexer's job to refuse what it
    /// cannot skip rather than this function's job to hide it.
    fn readExtras(self: *Import, node: ?json.Value) Error![]const u32 {
        const list = arr(node) orelse return &.{};
        var out: std.ArrayList(u32) = .empty;
        for (list.items) |entry| {
            const o = obj(entry) orelse continue;
            const kind = str(o.get("type")) orelse continue;
            if (std.mem.eql(u8, kind, "SYMBOL")) {
                const n = str(o.get("name")) orelse continue;
                if (self.symbols.get(n)) |s| try out.append(self.scratch.allocator(), s);
                continue;
            }
            const pattern = (try self.atomPattern(entry)) orelse continue;
            const key = switch (pattern) {
                .literal => |l| try std.fmt.allocPrint(self.scratch.allocator(), "str:{s}", .{l}),
                .regex => |rx| try std.fmt.allocPrint(self.scratch.allocator(), "rx:{s}", .{rx}),
                .external => continue,
            };
            const display = switch (pattern) {
                .literal => |l| l,
                .regex => |rx| rx,
                .external => unreachable,
            };
            try out.append(self.scratch.allocator(), try self.b.intern(key, display, pattern));
        }
        return out.items;
    }

    fn readConflicts(self: *Import, node: ?json.Value) Error![]const []const u32 {
        const a = self.scratch.allocator();
        const list = arr(node) orelse return &.{};
        var out: std.ArrayList([]const u32) = .empty;
        for (list.items) |group| {
            const names = arr(group) orelse continue;
            var syms: std.ArrayList(u32) = .empty;
            for (names.items) |n| {
                const s = str(n) orelse continue;
                if (self.symbols.get(s)) |sym| try syms.append(a, sym);
            }
            if (syms.items.len > 0) try out.append(a, syms.items);
        }
        return out.items;
    }
};

// ── small helpers over the dynamic JSON shape ──

fn obj(v: ?json.Value) ?json.ObjectMap {
    const x = v orelse return null;
    return if (x == .object) x.object else null;
}

fn arr(v: ?json.Value) ?json.Array {
    const x = v orelse return null;
    return if (x == .array) x.array else null;
}

fn str(v: ?json.Value) ?[]const u8 {
    const x = v orelse return null;
    return if (x == .string) x.string else null;
}

fn one(a: std.mem.Allocator, rhs: []const u32, prec: Prec) Error![]Alt {
    const out = try a.alloc(Alt, 1);
    out[0] = .{ .rhs = try a.dupe(u32, rhs), .prec = prec };
    return out;
}

/// The cartesian product of two alternative sets. Precedence follows the
/// largest magnitude present, which is an approximation of tree-sitter's
/// propagation: it can change which conflicts resolve, never which strings the
/// grammar accepts.
fn product(a: std.mem.Allocator, left: []Alt, right: []Alt) Error![]Alt {
    const out = try a.alloc(Alt, left.len * right.len);
    var i: usize = 0;
    for (left) |l| for (right) |r| {
        const rhs = try a.alloc(u32, l.rhs.len + r.rhs.len);
        @memcpy(rhs[0..l.rhs.len], l.rhs);
        @memcpy(rhs[l.rhs.len..], r.rhs);
        const prec = if (@abs(r.prec.value) > @abs(l.prec.value)) r.prec else l.prec;
        out[i] = .{ .rhs = rhs, .prec = prec };
        i += 1;
    };
    return out;
}

const testing = std.testing;

test "a rule whose body is one atom becomes a terminal, not a nonterminal" {
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"SYMBOL","name":"word"},
        \\ "word":{"type":"PATTERN","value":"[a-z]+"}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();
    try testing.expectEqual(@as(u32, 1), gr.terminal_count);
    try testing.expectEqualStrings("word", gr.nameOf(0));
    try testing.expect(gr.isTerminal(0));
}

test "repeat becomes a left-recursive auxiliary with an epsilon base" {
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"REPEAT","content":{"type":"STRING","value":"a"}}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    const doc = for (0..gr.symbolCount()) |i| {
        if (std.mem.eql(u8, gr.nameOf(@intCast(i)), "doc")) break @as(g.Symbol, @intCast(i));
    } else unreachable;
    const aux = gr.productions[gr.productionsOf(doc)[0]].rhs[0];

    var saw_epsilon = false;
    var saw_loop = false;
    for (gr.productionsOf(aux)) |p| {
        const rhs = gr.productions[p].rhs;
        if (rhs.len == 0) saw_epsilon = true;
        if (rhs.len == 2 and rhs[0] == aux) saw_loop = true;
    }
    try testing.expect(saw_epsilon);
    try testing.expect(saw_loop);
}

test "choice distributes inside a sequence while the product stays small" {
    const src =
        \\{"name":"t","rules":{"doc":{"type":"SEQ","members":[
        \\ {"type":"CHOICE","members":[{"type":"STRING","value":"a"},{"type":"STRING","value":"b"}]},
        \\ {"type":"STRING","value":"!"}]}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();
    // `$start -> doc` plus the two distributed alternatives, and no auxiliary.
    try testing.expectEqual(@as(usize, 3), gr.productions.len);
    try testing.expectEqual(@as(u32, 3), gr.terminal_count);
}

test "an external scanner token survives as unlexable rather than as a guess" {
    const src =
        \\{"name":"t","rules":{"doc":{"type":"SYMBOL","name":"indent"}},
        \\ "externals":[{"type":"SYMBOL","name":"indent"}]}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();
    try testing.expectEqual(@as(usize, 1), gr.externals.len);
    try testing.expectEqualStrings("indent", gr.nameOf(gr.externals[0]));
}
