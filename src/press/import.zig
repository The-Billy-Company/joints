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
//!      that is small and hoisted into an auxiliary when it is not — and an
//!      invented auxiliary is a rule boundary the author did not write, so
//!      three things keep it from inventing conflicts too: it is shared by
//!      content, its ε alternative is lifted back out to the host, and the
//!      rank in force where it sat stays on the host's step rather than
//!      following the body inside. Skip any one of them and TypeScript alone
//!      grows several thousand conflicts nobody declared.
//!   3. **Tree shaping is carried, not applied.** `alias`, `field`,
//!      `supertypes` and the leading-underscore convention decide what a node
//!      is *called* and whether it shows up at all. None of them changes a
//!      single production, so none of them may change a single table cell —
//!      and none of them is recoverable downstream either, because a parse is
//!      folds and a tree is names. They ride along, on the part of the IR the
//!      fact is actually about.
//!
//! Where each one lands is the whole design, and "wherever is convenient" gets
//! it wrong in a way that only shows up as a mis-shaped tree:
//!
//!   - `alias` and `field` are **use-site** facts, so they sit on a `Step`
//!     beside precedence and travel exactly the way precedence does — pushed
//!     onto the context by their wrapper and stamped onto every symbol the
//!     wrapper encloses. `alias(seq('unique','symbol'), 'unique symbol')` in
//!     TypeScript stamps two steps, and that is not a rounding error: it is
//!     what tree-sitter emits. Hang either one on the *symbol* instead and C's
//!     `_old_style_function_definition`, aliased at two sites and hidden
//!     everywhere else, becomes visible everywhere.
//!   - Hiddenness is a **symbol** fact, so it sits in `Shape`. A leading
//!     underscore hides a rule and a `supertypes` entry hides one too, which is
//!     why C's `expression` never appears in a tree despite having no
//!     underscore. Both are the same answer, and the fourth `Shape` keeps them
//!     apart from the auxiliaries *we* invented in step 2 — nobody can write a
//!     query against `expression_repeat1`, so a consumer has to be able to tell
//!     which invisible symbols were the author's idea.
//!
//! `inherits` is the one key still ignored, and deliberately: see the test at
//! the bottom of this file, which proves the committed JSON is already
//! expanded.
//!
//! Precedence is exact rather than approximated. It rides each symbol rather
//! than each production, because that is where tree-sitter puts it: `prec.left(1,
//! seq(a, b))` ranks the step that finishes the group, and a rule folded into
//! another carries its own ranks with it. The version of this that kept one
//! number per production had to pick a winner when two wrappers met, picked by
//! magnitude, and got a different table on any grammar where the strongest
//! wrapper was not the innermost — which is most of them.
//!
//! Two lexical facts that are *not* structure come through anyway, because a
//! lexer cannot be correct without them: `word`, the terminal a keyword is
//! spelled as before anyone knows it is a keyword, and each token's own
//! immediacy and precedence.
//!
//! One deliberate approximation is left, visible in the output rather than
//! hidden: a grammar with external scanners keeps those terminals as
//! `.external`, which every consumer must refuse to lex rather than guess.

const std = @import("std");
const json = std.json;
const g = @import("grammar.zig");
const lexeme = @import("lexeme.zig");
const fold = @import("fold.zig");

pub const Error = error{ OutOfMemory, MalformedGrammar };

/// How many alternatives a `SEQ` may distribute into before its choices are
/// hoisted into auxiliary nonterminals instead.
///
/// Distributing is what tree-sitter does, unconditionally, and it is the
/// conflict-free option: it invents no rule, so it invents no place to decide
/// anything. Hoisting exists only because distribution is exponential in the
/// number of optional members and a pathological grammar should degrade rather
/// than hang.
///
/// The ceiling is set by measurement, not taste. TypeScript's
/// `public_field_definition` is seven optional members over a three-way choice
/// of modifier prefixes — 768 alternatives — and hoisting it put a fold between
/// `override` and the property name that its sibling `method_definition`, which
/// distributed, does not have. Eight hundred and forty cells, all one shape.
/// Above the product and below anything that hurts: TypeScript pays 3,100
/// productions and 3,000 states for it, and is the only grammar of eleven that
/// notices.
const seq_budget = 1024;

/// One right-hand side under construction. `steps` runs parallel to `rhs`, so
/// every symbol carries the precedence and associativity in force where it
/// sits rather than one verdict for the whole body.
const Alt = struct { rhs: []const u32, steps: []const g.Step };

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

    // Unconditional, not `errdefer`: `finish` moves only the arena out, so the
    // builder's own bookkeeping still has to be released on the way past.
    var builder = g.Builder.init(gpa);
    defer builder.deinit();

    var imp: Import = .{
        .gpa = gpa,
        .b = &builder,
        .rules = &rules,
        .scratch = std.heap.ArenaAllocator.init(gpa),
        .symbols = std.StringHashMap(u32).init(gpa),
        .supertypes = std.StringHashMap(void).init(gpa),
    };
    defer imp.deinit();

    // First, because it decides whether a rule is hidden and the rules are
    // about to be interned.
    try imp.readSupertypes(root.get("supertypes"));
    try imp.readPrecedences(root.get("precedences"));
    try imp.internExternals(root.get("externals"));
    try imp.internRules();
    try imp.placePrecedences();
    try imp.placeSupertypes();

    // The augmented production must be index 0, so that "accept" is a single
    // integer comparison for the rest of the system's life.
    const start = try imp.b.intern("aux:$start", "$start", null);
    imp.b.shape(start, .invented);
    const first = imp.symbols.get(rules.keys()[0]).?;
    try imp.b.addProduction(start, &.{first}, &.{});

    for (rules.keys(), rules.values()) |rule_name, body| {
        const sym = imp.symbols.get(rule_name).?;
        // A rule that resolved to a terminal contributes a token, not
        // structure; its body was already folded into the pattern.
        if (g.Builder.isTerminalRaw(sym)) continue;
        _ = imp.scratch.reset(.retain_capacity);
        for (try imp.alts(body, .{}, true, rule_name)) |alt| {
            try imp.b.addProduction(sym, alt.rhs, alt.steps);
        }
    }

    // Folded before the tables see the grammar: `inline` rules are names the
    // author wanted, and substituting them away is how tree-sitter keeps them
    // from costing conflicts the language does not actually have.
    _ = try fold.nonterminals(gpa, &builder, start, try imp.readInline(root.get("inline")));

    // After the fold, because folding renumbers nothing but can retire a rule:
    // a word that survived is a word the lexer can still ask about.
    if (str(root.get("word"))) |w| builder.word = imp.symbols.get(w);

    const extras = try imp.readExtras(root.get("extras"));
    const conflicts = try imp.readConflicts(root.get("conflicts"));
    return builder.finish(name, start, extras, conflicts);
}

const Import = struct {
    gpa: std.mem.Allocator,
    b: *g.Builder,
    rules: *const json.ObjectMap,
    scratch: std.heap.ArenaAllocator,
    /// Declared orderings, held until the rule names inside them can resolve.
    orderings: std.ArrayList([]g.Rank) = .empty,
    pending: std.ArrayList(Unresolved) = .empty,
    /// Rule name -> its symbol, whichever space it landed in.
    symbols: std.StringHashMap(u32),
    /// The `supertypes` block, by rule name, held until the rules exist.
    supertypes: std.StringHashMap(void),
    aux: u32 = 0,

    /// A rule an ordering named before rules were interned.
    const Unresolved = struct { list: u32, at: u32, name: []const u8 };

    fn deinit(self: *Import) void {
        self.scratch.deinit();
        self.orderings.deinit(self.gpa);
        self.pending.deinit(self.gpa);
        self.symbols.deinit();
        self.supertypes.deinit();
    }

    /// The abstract categories the author declared. Read before anything else
    /// because being in this list is what hides `expression`, and hiddenness is
    /// decided at the moment the rule is interned.
    fn readSupertypes(self: *Import, node: ?json.Value) Error!void {
        const list = arr(node) orelse return;
        for (list.items) |entry| {
            if (str(entry)) |n| try self.supertypes.put(n, {});
        }
    }

    /// Hand the resolved supertype symbols to the builder. A name the grammar
    /// does not define is dropped rather than invented, the same way an
    /// ordering entry naming a missing rule is.
    fn placeSupertypes(self: *Import) Error!void {
        var it = self.supertypes.keyIterator();
        while (it.next()) |name| {
            if (self.symbols.get(name.*)) |s| try self.b.elevate(s);
        }
    }

    /// Where a rule stands in the tree, from its name alone. Two ways to be
    /// hidden and they mean the same thing to a tree builder: tree-sitter reads
    /// a leading underscore as "do not emit a node for this", and marks every
    /// `supertypes` entry hidden on the way in whether or not it is spelled
    /// that way. C relies on the second for `expression`, `statement` and
    /// `type_specifier`, none of which carries an underscore and none of which
    /// has ever appeared in a C parse tree.
    fn shapeOfRule(self: *const Import, name: []const u8) g.Shape {
        const hidden = std.mem.startsWith(u8, name, "_") or self.supertypes.contains(name);
        return if (hidden) .hidden else .named;
    }

    /// The author's declared orderings, kept as orderings.
    ///
    /// Read once, before the rules, because a `SYMBOL` entry has to resolve
    /// against the same interning every rule body uses.
    ///
    /// An entry is a precedence name or a rule, and both belong: the question
    /// an author is usually answering is whether a `member_expression` binds
    /// tighter than an `arrow_function`, and neither of those is a `prec`
    /// name. Dropping the rules — which is what skipping non-string entries
    /// amounts to — silently deletes half of most orderings, and with them
    /// every cell they were written to settle.
    fn readPrecedences(self: *Import, node: ?json.Value) Error!void {
        const outer = arr(node) orelse return;
        const a = self.scratch.allocator();
        for (outer.items) |ordering| {
            const list = arr(ordering) orelse continue;
            var entries: std.ArrayList(g.Rank) = .empty;
            for (list.items) |entry| {
                const o = obj(entry) orelse {
                    if (entry != .string) continue;
                    try entries.append(a, .{ .name = try self.b.internPrec(entry.string) });
                    continue;
                };
                const kind = str(o.get("type")) orelse continue;
                if (std.mem.eql(u8, kind, "SYMBOL")) {
                    // A rule entry spells itself `name`, not `value`, and the
                    // rules do not exist yet — so the slot is filled on the
                    // second pass below.
                    const n = str(o.get("name")) orelse continue;
                    try entries.append(a, .{ .symbol = std.math.maxInt(u32) });
                    try self.pending.append(self.gpa, .{
                        .list = @intCast(self.orderings.items.len),
                        .at = @intCast(entries.items.len - 1),
                        .name = n,
                    });
                } else {
                    const value = str(o.get("value")) orelse continue;
                    try entries.append(a, .{ .name = try self.b.internPrec(value) });
                }
            }
            try self.orderings.append(self.gpa, try entries.toOwnedSlice(a));
        }
    }

    /// Resolve the rule names an ordering mentioned, now that rules exist, and
    /// hand the finished lists to the builder. An ordering naming a rule the
    /// grammar does not have is dropped rather than guessed at.
    fn placePrecedences(self: *Import) Error!void {
        for (self.pending.items) |p| {
            const list = @constCast(self.orderings.items[p.list]);
            list[p.at] = if (self.symbols.get(p.name)) |s|
                .{ .symbol = s }
            else
                .{ .name = try self.b.internPrec(p.name) };
        }
        for (self.orderings.items) |list| try self.b.addOrdering(list);
    }

    /// External scanner tokens, interned before the rules so a rule of the same
    /// name resolves to the scanner's terminal rather than to its own body —
    /// which is exactly tree-sitter's precedence.
    fn internExternals(self: *Import, node: ?json.Value) Error!void {
        const list = arr(node) orelse return;
        for (list.items) |entry| {
            const n = str(obj(entry).?.get("name")) orelse continue;
            const sym = try self.b.intern(n, n, .external);
            self.b.shape(sym, self.shapeOfRule(n));
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
            self.b.describe(sym, self.lexis(body));
            self.b.shape(sym, self.shapeOfRule(name));
            try self.symbols.put(name, sym);
        }
    }

    /// The lexical facts a token node's wrapper chain declares: `token.immediate`
    /// anywhere in it, and the strongest `prec` it passes through.
    ///
    /// Read from the wrappers rather than from the body because that is where
    /// the author wrote them, and both say something about the token's standing
    /// against the rest of the slate rather than about the bytes it matches.
    /// A `prec` *outside* a token wraps the rule, not the lexer, so the walk
    /// stops at whatever it can no longer see through.
    fn lexis(self: *Import, node: json.Value) g.Lexis {
        var out: g.Lexis = .{};
        var cur = node;
        while (true) {
            const o = obj(cur) orelse return out;
            const kind = str(o.get("type")) orelse return out;
            if (std.mem.eql(u8, kind, "IMMEDIATE_TOKEN")) out.immediate = true;
            // Only a number ranks a token. A named precedence orders rules
            // against each other, and the lexer has no rules to order.
            if (std.mem.startsWith(u8, kind, "PREC")) {
                if (self.precValue(o.get("value")) == .level) {
                    out.prec = @max(out.prec, self.precValue(o.get("value")).level);
                }
            }
            if (!lexeme.isWrapper(kind)) return out;
            cur = o.get("content") orelse return out;
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
    ///
    /// `ctx` is the precedence and associativity in force here — the innermost
    /// `prec` wrapper this node sits inside — and every symbol reached records
    /// it. `at_end` says whether this node finishes the production it belongs
    /// to, which is the one thing a precedence wrapper needs to know about its
    /// surroundings; see `close`.
    fn alts(self: *Import, node: json.Value, ctx: g.Step, at_end: bool, owner: []const u8) Error![]Alt {
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
            const sym = try self.b.intern(key, display, pattern);
            self.b.describe(sym, self.lexis(node));
            // A bare string is a node you can see and cannot name: `("+")`
            // shows up in the tree spelled as itself. An inline regex is not
            // even that — tree-sitter files it as auxiliary, so `/\s+/` written
            // mid-rule contributes no node at all.
            self.b.shape(sym, if (pattern == .literal) .anonymous else .invented);
            return try one(a, &.{sym}, ctx);
        }

        // Two wrappers that say what a child is *called* here without changing
        // what is derived. They ride the context down onto every symbol they
        // enclose and are never handed back out the way a precedence is,
        // because a rename applies to what is inside it and to nothing after.
        if (std.mem.eql(u8, kind, "ALIAS") or std.mem.eql(u8, kind, "FIELD")) {
            const inner = o.get("content") orelse return error.MalformedGrammar;
            var next = ctx;
            if (std.mem.eql(u8, kind, "ALIAS")) {
                const value = str(o.get("value")) orelse return error.MalformedGrammar;
                const named = o.get("named");
                next.alias = try self.b.internAlias(value, named != null and named.? == .bool and named.?.bool);
            } else {
                next.field = try self.b.internField(str(o.get("name")) orelse return error.MalformedGrammar);
            }
            return self.alts(inner, next, at_end, owner);
        }

        // `RESERVED` scopes a reserved-word set over its content, which decides
        // how a token *lexes* in that region and nothing about the shape of the
        // parse or the tree; the shift the wrapper is transparent to is the only
        // thing this layer builds.
        if (std.mem.eql(u8, kind, "RESERVED")) {
            const inner = o.get("content") orelse return error.MalformedGrammar;
            return self.alts(inner, ctx, at_end, owner);
        }

        if (std.mem.startsWith(u8, kind, "PREC")) {
            const inner = o.get("content") orelse return error.MalformedGrammar;
            // PREC_DYNAMIC steers GLR tie-breaking at runtime rather than table
            // construction, so it carries no static precedence.
            if (std.mem.eql(u8, kind, "PREC_DYNAMIC")) return self.alts(inner, ctx, at_end, owner);
            var next = ctx;
            next.prec = self.precValue(o.get("value"));
            if (std.mem.eql(u8, kind, "PREC_LEFT")) next.assoc = .left;
            if (std.mem.eql(u8, kind, "PREC_RIGHT")) next.assoc = .right;
            const inside = try self.alts(inner, next, at_end, owner);
            return if (at_end) inside else close(inside, ctx);
        }

        if (std.mem.eql(u8, kind, "CHOICE")) {
            const members = arr(o.get("members")) orelse return error.MalformedGrammar;
            var out: std.ArrayList(Alt) = .empty;
            for (members.items) |m| try out.appendSlice(a, try self.alts(m, ctx, at_end, owner));
            return out.toOwnedSlice(a);
        }

        if (std.mem.eql(u8, kind, "SEQ")) {
            const members = arr(o.get("members")) orelse return error.MalformedGrammar;
            var acc = try one(a, &.{}, ctx);
            for (members.items, 0..) |m, i| {
                const last = at_end and i == members.items.len - 1;
                var next = try self.alts(m, ctx, last, owner);
                if (acc.len * next.len > seq_budget) {
                    // Shaping goes *inside*, rank stays outside. Distributing —
                    // which is what this is standing in for — would have
                    // stamped the enclosing `alias`/`field` onto every symbol
                    // of every alternative, so that is where they have to land
                    // for the two paths to build the same tree.
                    // Re-expanded with no ambient rank, because the auxiliary
                    // about to be invented is a rule boundary the author did
                    // not write. What surrounds this member ranks the *step*
                    // the member occupies, which stays in the host; only what
                    // is written inside it belongs in the new rule. Keeping the
                    // ambient rank inside would also make two identical bodies
                    // hoisted under different wrappers into two nonterminals
                    // deriving the same strings, which is a reduce/reduce
                    // conflict with nobody's name on it.
                    const shaping: g.Step = .{ .alias = ctx.alias, .field = ctx.field };
                    next = try self.hoist(try self.alts(m, shaping, true, owner), ctx, owner);
                }
                acc = try product(a, acc, next);
            }
            return acc;
        }

        if (std.mem.eql(u8, kind, "REPEAT") or std.mem.eql(u8, kind, "REPEAT1")) {
            const content = o.get("content") orelse return error.MalformedGrammar;
            // The list is its own rule, so its body is at the end of *that*
            // rule and inherits nothing from the position of the reference.
            const body = try self.alts(content, .{}, true, owner);
            const aux = try self.listSymbol(owner, body);
            if (std.mem.eql(u8, kind, "REPEAT1")) return try one(a, &.{aux}, ctx);

            // `repeat` is `optional(repeat1)`, and *where* the optionality lives
            // decides how many conflicts the grammar appears to have. Give the
            // auxiliary an epsilon production and a parser must decide whether
            // the list is empty at the point the list begins — before it has
            // seen anything to decide with — so the ε-fold competes with every
            // token that could start an element, and with every token that could
            // follow the whole list. Every one of Java's residual conflicts was
            // a cell of that shape.
            //
            // Returning two alternatives instead pushes the choice up into the
            // host production, which then exists in a with-list and a
            // without-list form. The decision moves to where the evidence is:
            // shift the first element and the list is non-empty, and no cell
            // ever has to guess. It costs host productions — a body with n
            // repeats fans into 2^n — which is why deduplication has to land
            // first, since the fan reaches the same body twice as soon as two
            // repeats sit next to each other.
            const out = try a.alloc(Alt, 2);
            out[0] = (try one(a, &.{aux}, ctx))[0];
            out[1] = .{ .rhs = &.{}, .steps = &.{} };
            return out;
        }

        return error.MalformedGrammar;
    }

    /// The left-recursive auxiliary for one list body, shared by content across
    /// the whole grammar.
    ///
    /// Left recursion on purpose: `A -> A x` keeps the LR stack at constant
    /// depth across a list, where right recursion grows it by one frame per
    /// element.
    ///
    /// Sharing is the part that is easy to get wrong, and it is not an
    /// optimization. Two occurrences of `repeat(X)` denote the same list, so
    /// they have to be the same nonterminal: give each its own and they become
    /// distinguishable only by a name the language does not have, so after
    /// folding one element the parser must decide *which* list it is building
    /// with nothing to decide on. Java writes `repeat($.catch_clause)` in two
    /// alternatives of `try_statement` and `repeat($._annotation)` in a dozen
    /// rules; C repeats one pointer-modifier list in both the concrete and the
    /// abstract declarator. Every one of those pairs came back as a
    /// reduce/reduce conflict describing nothing.
    ///
    /// The cache is keyed on the body alone, so sharing crosses rules. The
    /// worry about going that wide is that merging the states which build a
    /// list could manufacture an ambiguity: `A -> L L` over one `L` cannot say
    /// where the first list stops. It does not happen, and the reason is that
    /// merging changes no language. Two auxiliaries with byte-identical bodies
    /// derive the same set of strings, so a sentential form that puts one after
    /// the other could already put either after itself — the adjacency, if it
    /// exists, was in the grammar before the merge, spelled with two names.
    ///
    /// Measured: grammar-wide sharing takes Java from 46 residual conflicts to
    /// 11 and C from 33 to 17, and leaves JSON, Python and Go at zero. An
    /// earlier reading of this had C regressing to 70, which was true of a
    /// grammar that still folded ε inside its lists and still carried
    /// duplicate productions; both are fixed, and the objection went with
    /// them.
    ///
    /// What sharing does *not* reach is two lists with different bodies that
    /// happen to overlap on one element. Java's `modifiers` list admits
    /// `public`, `array_creation_expression`'s admits only annotations, and
    /// after folding a single annotation the table cannot say which it was
    /// building — those are different languages and merging them would be
    /// wrong. That residue is a lookahead problem, not a naming one, and it is
    /// answered in `lr1`, not here.
    ///
    /// Precedence and shaping are part of the identity, since both are part of
    /// what the productions will say. A `repeat1(prec.left(...))` and a bare
    /// `repeat1(...)` over the same body are different rules, and collapsing
    /// them would throw away the side the author declared; a
    /// `repeat(field('x', $.a))` and a `repeat($.a)` are different trees, and
    /// collapsing those would throw away the field. tree-sitter keys its own
    /// repeat cache on the whole rule for exactly this reason.
    fn listSymbol(self: *Import, owner: []const u8, body: []const Alt) Error!u32 {
        const a = self.scratch.allocator();
        const key = try self.bodyKey("list", body);
        if (self.b.lookup(key)) |shared| return shared;

        self.aux += 1;
        const name = try std.fmt.allocPrint(a, "{s}_repeat{d}", .{ owner, self.aux });
        const aux = try self.b.intern(key, name, null);
        self.b.shape(aux, .invented);
        // The first host names it and owns it. Both are reports for a human;
        // the language the auxiliary denotes is the same either way.
        if (self.symbols.get(owner)) |rule| self.b.ascribe(aux, rule);
        for (body) |alt| {
            try self.b.addProduction(aux, alt.rhs, alt.steps);
            const looped = try a.alloc(u32, alt.rhs.len + 1);
            looped[0] = aux;
            @memcpy(looped[1..], alt.rhs);
            // The recursive step carries what the first element carries, so
            // going round again is ranked the same as arriving.
            const steps = try a.alloc(g.Step, looped.len);
            // Rank only. Going round again is ranked the same as arriving, but
            // the list itself is not a child anybody named: tree-sitter wraps a
            // repeat as a bare `choice(seq(aux, aux), body)` with no metadata
            // on it, and an alias here would emit a node for the whole tail.
            steps[0] = if (alt.steps.len > 0)
                .{ .prec = alt.steps[0].prec, .assoc = alt.steps[0].assoc }
            else
                .{};
            @memcpy(steps[1..], alt.steps);
            try self.b.addProduction(aux, looped, steps);
        }
        return aux;
    }

    /// Give a set of alternatives its own nonterminal, so a `SEQ` can reference
    /// it once instead of distributing over it.
    ///
    /// Shared by content and emptied of ε, for the same two reasons the list
    /// auxiliaries are, and they cost the same when ignored. TypeScript's
    /// `method_definition` and `method_signature` both hoist a body whose
    /// alternatives are `*`, `?`, or nothing; giving each rule a private copy
    /// left two nonterminals deriving the same strings, which is a
    /// reduce/reduce conflict spelled with two invented names, and keeping the
    /// ε alternative inside the copy made the parser choose whether the
    /// optional part was there before reading anything that could tell it.
    /// Between them they were 3,759 of TypeScript's cells.
    ///
    /// Lifting ε back out means the caller gets two alternatives — with and
    /// without — and the host fans, exactly as it does for `repeat`. The
    /// decision moves to where the evidence is.
    fn hoist(self: *Import, set: []Alt, at: g.Step, owner: []const u8) Error![]Alt {
        const a = self.scratch.allocator();
        var filled: std.ArrayList(Alt) = .empty;
        var empty = false;
        for (set) |alt| {
            if (alt.rhs.len == 0) empty = true else try filled.append(a, alt);
        }
        if (filled.items.len == 0) return one(a, &.{}, .{});

        const key = try self.bodyKey("choice", filled.items);
        const aux = self.b.lookup(key) orelse blk: {
            self.aux += 1;
            const name = try std.fmt.allocPrint(a, "{s}_choice{d}", .{ owner, self.aux });
            const sym = try self.b.intern(key, name, null);
            self.b.shape(sym, .invented);
            // Ascribed to the rule being lowered, not parsed back out of the
            // name later. The name is for a human reading a report; the
            // attribution is load-bearing, and a report is a bad place to keep
            // load-bearing facts.
            if (self.symbols.get(owner)) |rule| self.b.ascribe(sym, rule);
            for (filled.items) |alt| try self.b.addProduction(sym, alt.rhs, alt.steps);
            break :blk sym;
        };

        // The reference carries the rank in force where the member sat, and
        // nothing else: the body inside carries what was written inside it,
        // plus the renames the caller pushed in for us.
        const site: g.Step = .{ .prec = at.prec, .assoc = at.assoc };
        if (!empty) return one(a, &.{aux}, site);
        const out = try a.alloc(Alt, 2);
        out[0] = (try one(a, &.{aux}, site))[0];
        out[1] = .{ .rhs = &.{}, .steps = &.{} };
        return out;
    }

    /// A content key for an auxiliary, so two rules writing the same body get
    /// one nonterminal. Length-prefixed, so `seq(x,y)` and `choice(x,y)` cannot
    /// spell the same key, and every field of a step is in it, since every
    /// field of a step is part of what the productions will say: a `prec.left`
    /// body and a bare one are different rules, and an aliased body and a bare
    /// one are different trees.
    fn bodyKey(self: *Import, tag: []const u8, body: []const Alt) Error![]const u8 {
        const a = self.scratch.allocator();
        var words: std.ArrayList(u32) = .empty;
        for (body) |alt| {
            try words.append(a, @intCast(alt.rhs.len));
            try words.appendSlice(a, alt.rhs);
            for (alt.steps) |s| {
                try words.append(a, @intFromEnum(std.meta.activeTag(s.prec)));
                try words.append(a, switch (s.prec) {
                    .none => 0,
                    .level => |v| @bitCast(v),
                    .name => |v| v,
                });
                try words.append(a, @intFromEnum(s.assoc));
                try words.append(a, s.alias orelse std.math.maxInt(u32));
                try words.append(a, s.field orelse std.math.maxInt(u32));
            }
        }
        return std.mem.concat(a, u8, &.{ "aux:", tag, ":", std.mem.sliceAsBytes(words.items) });
    }

    /// A `prec` argument: a number, or a name the orderings rank.
    fn precValue(self: *Import, node: ?json.Value) g.Prec {
        const v = node orelse return .none;
        return switch (v) {
            .integer => |i| .{ .level = @intCast(i) },
            .float => |f| .{ .level = @intFromFloat(f) },
            .string => |s| .{ .name = self.b.internPrec(s) catch return .none },
            else => .none,
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
            const sym = try self.b.intern(key, display, pattern);
            self.b.shape(sym, if (pattern == .literal) .anonymous else .invented);
            try out.append(self.scratch.allocator(), sym);
        }
        return out.items;
    }

    /// Rules the grammar asks to be substituted away. A name that is already a
    /// terminal is not foldable — there is no body to substitute — and the
    /// start symbol must survive, so both are skipped.
    fn readInline(self: *Import, node: ?json.Value) Error![]const u32 {
        const list = arr(node) orelse return &.{};
        var out: std.ArrayList(u32) = .empty;
        for (list.items) |entry| {
            const n = str(entry) orelse continue;
            const sym = self.symbols.get(n) orelse continue;
            if (g.Builder.isTerminalRaw(sym)) continue;
            try out.append(self.scratch.allocator(), sym);
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

/// Hand the last step of each alternative back to the enclosing precedence.
///
/// A `prec` group that does not finish the production is *over* by the time
/// its last symbol has been consumed, so a reading standing there is no longer
/// inside it — it is standing in whatever contains it, at whatever rank that
/// carries. Leaving the inner rank on that step is how `seq(prec(2, x), y)`
/// comes to claim rank 2 while deciding what to do about `y`, which is a claim
/// the author did not make.
///
/// A group that *does* finish the production keeps its rank on the final step,
/// and that is the whole mechanism behind `prec.left(1, seq(e, '+', e))`: the
/// completed item's precedence is the last step's, so the fold carries 1 and
/// the ladder has something to compare.
///
/// Rank and side only. A rename is not something a reading can stand outside
/// of — `prec(1, alias($.x, 'foo'))` still produces a `foo`, whatever the
/// enclosing precedence is — so handing the whole step back would quietly drop
/// the alias of every aliased symbol that is not last in its production.
fn close(set: []Alt, outer: g.Step) []Alt {
    for (set) |*alt| {
        if (alt.steps.len == 0) continue;
        const last = &@constCast(alt.steps)[alt.steps.len - 1];
        last.prec = outer.prec;
        last.assoc = outer.assoc;
    }
    return set;
}

fn one(a: std.mem.Allocator, rhs: []const u32, step: g.Step) Error![]Alt {
    const steps = try a.alloc(g.Step, rhs.len);
    @memset(steps, step);
    const out = try a.alloc(Alt, 1);
    out[0] = .{ .rhs = try a.dupe(u32, rhs), .steps = steps };
    return out;
}

/// The cartesian product of two alternative sets.
///
/// Nothing has to be reconciled: each side's steps already carry the rank in
/// force where they sit, so concatenating the bodies concatenates the ranks.
/// The version of this that kept one precedence per production had to pick a
/// winner here, and picked by magnitude — which is how a body's strongest
/// wrapper came to speak for every symbol in it.
fn product(a: std.mem.Allocator, left: []Alt, right: []Alt) Error![]Alt {
    const out = try a.alloc(Alt, left.len * right.len);
    var i: usize = 0;
    for (left) |l| for (right) |r| {
        const rhs = try a.alloc(u32, l.rhs.len + r.rhs.len);
        @memcpy(rhs[0..l.rhs.len], l.rhs);
        @memcpy(rhs[l.rhs.len..], r.rhs);
        const steps = try a.alloc(g.Step, rhs.len);
        @memcpy(steps[0..l.steps.len], l.steps);
        @memcpy(steps[l.steps.len..], r.steps);
        out[i] = .{ .rhs = rhs, .steps = steps };
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

test "repeat is a left-recursive auxiliary and the emptiness lives in the host" {
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"REPEAT","content":{"type":"STRING","value":"a"}}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    const doc = for (0..gr.symbolCount()) |i| {
        if (std.mem.eql(u8, gr.nameOf(@intCast(i)), "doc")) break @as(g.Symbol, @intCast(i));
    } else unreachable;

    // The host carries the choice: one body with the list, one without.
    const host = gr.productionsOf(doc);
    try testing.expectEqual(@as(usize, 2), host.len);
    try testing.expectEqual(@as(usize, 1), gr.productions[host[0]].rhs.len);
    try testing.expectEqual(@as(usize, 0), gr.productions[host[1]].rhs.len);

    // The auxiliary is `repeat1` — one element, or itself and one more — and
    // crucially never ε, so no state has to decide whether a list is empty
    // before it has seen anything.
    const aux = gr.productions[host[0]].rhs[0];
    var saw_single = false;
    var saw_loop = false;
    for (gr.productionsOf(aux)) |p| {
        const rhs = gr.productions[p].rhs;
        try testing.expect(rhs.len != 0);
        if (rhs.len == 1) saw_single = true;
        if (rhs.len == 2 and rhs[0] == aux) saw_loop = true;
    }
    try testing.expect(saw_single);
    try testing.expect(saw_loop);
}

test "one rule writing the same list twice gets one auxiliary, not two" {
    // Java's `try_statement` writes `repeat($.catch_clause)` in two alternatives.
    // Two auxiliaries for it are distinguishable only by a name the language
    // does not have, so folding one element becomes a reduce/reduce conflict
    // over which list is being built.
    const src =
        \\{"name":"t","rules":{"doc":{"type":"CHOICE","members":[
        \\ {"type":"SEQ","members":[{"type":"STRING","value":"try"},
        \\   {"type":"REPEAT1","content":{"type":"STRING","value":"c"}}]},
        \\ {"type":"SEQ","members":[{"type":"STRING","value":"do"},
        \\   {"type":"REPEAT1","content":{"type":"STRING","value":"c"}}]}]}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    var lists: usize = 0;
    for (gr.terminal_count..gr.symbolCount()) |s| {
        const sym: g.Symbol = @intCast(s);
        if (gr.isSynthetic(sym)) lists += 1;
    }
    try testing.expectEqual(@as(usize, 1), lists);
}

test "two different rules writing the same list also get one auxiliary" {
    // Java writes `repeat($._annotation)` in a dozen rules and C repeats one
    // attribute list in three declarator shapes. Keeping the auxiliary per host
    // is the tidy boundary rather than the sound one: the merge cannot make the
    // grammar ambiguous, because two lists with identical bodies already derive
    // the same strings under two names.
    const src =
        \\{"name":"t","rules":{
        \\ "doc":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"a"},{"type":"SYMBOL","name":"b"}]},
        \\ "a":{"type":"SEQ","members":[{"type":"STRING","value":"try"},
        \\   {"type":"REPEAT1","content":{"type":"STRING","value":"c"}}]},
        \\ "b":{"type":"SEQ","members":[{"type":"STRING","value":"do"},
        \\   {"type":"REPEAT1","content":{"type":"STRING","value":"c"}}]}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    var lists: usize = 0;
    for (gr.terminal_count..gr.symbolCount()) |s| {
        const sym: g.Symbol = @intCast(s);
        if (gr.isSynthetic(sym)) lists += 1;
    }
    try testing.expectEqual(@as(usize, 1), lists);
}

test "a list declaring precedence keeps it, and does not share with one that does not" {
    // Python's `union_pattern` is `repeat1(prec.left(seq('|', pattern)))`. Drop
    // the `prec.left` on the way in and the ladder has nothing to settle the
    // list's own continue-or-stop with; keep it and the cell resolves.
    const src =
        \\{"name":"t","rules":{"doc":{"type":"SEQ","members":[
        \\ {"type":"REPEAT1","content":{"type":"PREC_LEFT","value":1,
        \\   "content":{"type":"STRING","value":"x"}}},
        \\ {"type":"REPEAT1","content":{"type":"STRING","value":"x"}}]}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    var ranked: usize = 0;
    var plain: usize = 0;
    for (gr.productions) |p| {
        if (!gr.isSynthetic(p.lhs)) continue;
        const last = p.consumed(p.rhs.len);
        if (last.prec.eql(.{ .level = 1 }) and last.assoc == .left) ranked += 1 else plain += 1;
    }
    // Two productions each (`L -> x` and `L -> L x`), and the ranked list is a
    // different rule from the unranked one because precedence is part of what
    // the productions say.
    try testing.expectEqual(@as(usize, 2), ranked);
    try testing.expectEqual(@as(usize, 2), plain);
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

test "the word rule survives, because longest match cannot decide a keyword" {
    // Both terminals match `int` at the same offset and nothing about either
    // pattern breaks the tie. `word` is the author saying which one is the
    // spelling and which one is the meaning.
    const src =
        \\{"name":"t","word":"identifier","rules":{
        \\ "doc":{"type":"CHOICE","members":[
        \\  {"type":"SYMBOL","name":"identifier"},{"type":"SYMBOL","name":"kw"}]},
        \\ "identifier":{"type":"PATTERN","value":"[a-z]+"},
        \\ "kw":{"type":"STRING","value":"int"}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();
    const word = gr.word orelse return error.WordDropped;
    try testing.expectEqualStrings("identifier", gr.nameOf(word));
    try testing.expect(gr.isTerminal(word));
}

test "a word naming something that is not a token is refused rather than trusted" {
    const src =
        \\{"name":"t","word":"doc","rules":{
        \\ "doc":{"type":"SEQ","members":[
        \\  {"type":"STRING","value":"a"},{"type":"STRING","value":"b"}]}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();
    try testing.expectEqual(@as(?g.Symbol, null), gr.word);
}

/// The finished-grammar symbol a rule name landed on.
fn symbolNamed(gr: *const g.Grammar, name: []const u8) g.Symbol {
    for (0..gr.symbolCount()) |s| {
        if (std.mem.eql(u8, gr.nameOf(@intCast(s)), name)) return @intCast(s);
    }
    unreachable;
}

/// The one production of a single-alternative rule, for the shaping tests.
fn onlyProduction(gr: *const g.Grammar, rule: []const u8) g.Production {
    const rules = gr.productionsOf(symbolNamed(gr, rule));
    std.debug.assert(rules.len == 1);
    return gr.productions[rules[0]];
}

test "an alias renames a child where it was renamed, and leaves the symbol alone" {
    // C aliases `_old_style_function_definition` to `function_definition` at
    // two sites and leaves it hidden everywhere else. Hang the rename on the
    // symbol and both readings collapse into whichever site was seen last.
    const src =
        \\{"name":"t","rules":{"doc":{"type":"CHOICE","members":[
        \\ {"type":"SEQ","members":[{"type":"STRING","value":"a"},{"type":"SYMBOL","name":"thing"}]},
        \\ {"type":"SEQ","members":[{"type":"STRING","value":"b"},
        \\   {"type":"ALIAS","named":true,"value":"other","content":{"type":"SYMBOL","name":"thing"}}]}]},
        \\ "thing":{"type":"PATTERN","value":"[a-z]+"}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    const thing = symbolNamed(&gr, "thing");
    const rules = gr.productionsOf(symbolNamed(&gr, "doc"));
    try testing.expectEqual(@as(usize, 2), rules.len);

    // One symbol, reached twice, wearing two different names.
    const plain = gr.productions[rules[0]];
    const renamed = gr.productions[rules[1]];
    try testing.expectEqual(thing, plain.rhs[1]);
    try testing.expectEqual(thing, renamed.rhs[1]);
    try testing.expectEqual(@as(?g.Alias, null), gr.aliasOf(plain.steps[1]));
    try testing.expectEqualStrings("other", gr.aliasOf(renamed.steps[1]).?.name);
    try testing.expect(gr.aliasOf(renamed.steps[1]).?.named);
    // And the symbol itself is untouched: it is still `thing`, still named.
    try testing.expectEqualStrings("thing", gr.nameOf(thing));
    try testing.expectEqual(g.Shape.named, gr.shapeOf(thing));
}

test "a field names a child at its use site, and composes with an alias" {
    const src =
        \\{"name":"t","rules":{"doc":{"type":"SEQ","members":[
        \\ {"type":"FIELD","name":"key","content":{"type":"SYMBOL","name":"word"}},
        \\ {"type":"FIELD","name":"value","content":
        \\   {"type":"ALIAS","named":false,"value":"lit","content":{"type":"SYMBOL","name":"word"}}}]},
        \\ "word":{"type":"PATTERN","value":"[a-z]+"}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    const doc = onlyProduction(&gr, "doc");
    try testing.expectEqualStrings("key", gr.fieldOf(doc.steps[0]).?);
    try testing.expectEqual(@as(?g.Alias, null), gr.aliasOf(doc.steps[0]));
    try testing.expectEqualStrings("value", gr.fieldOf(doc.steps[1]).?);
    try testing.expectEqualStrings("lit", gr.aliasOf(doc.steps[1]).?.name);
    // `named: false` is not a detail: it is the difference between a query
    // matching `(lit)` and one matching `"lit"`.
    try testing.expect(!gr.aliasOf(doc.steps[1]).?.named);
}

test "a rename inside a precedence group is not handed back with the rank" {
    // The `prec` group ends before the production does, so its rank is handed
    // back to the surroundings — but a node is still called what it is called.
    const src =
        \\{"name":"t","rules":{"doc":{"type":"SEQ","members":[
        \\ {"type":"PREC","value":1,"content":
        \\   {"type":"ALIAS","named":true,"value":"renamed","content":{"type":"SYMBOL","name":"word"}}},
        \\ {"type":"STRING","value":"!"}]},
        \\ "word":{"type":"PATTERN","value":"[a-z]+"}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    const doc = onlyProduction(&gr, "doc");
    try testing.expect(doc.steps[0].prec == .none);
    try testing.expectEqualStrings("renamed", gr.aliasOf(doc.steps[0]).?.name);
}

test "a leading underscore hides a rule, and so does being a supertype" {
    // C's `expression` carries no underscore and has never appeared in a C
    // parse tree, because tree-sitter hides every `supertypes` entry on the
    // way in. A tree builder that read only the name would emit a node the
    // world's highlight queries do not expect.
    const src =
        \\{"name":"t","supertypes":["expression"],"rules":{
        \\ "doc":{"type":"SYMBOL","name":"expression"},
        \\ "expression":{"type":"CHOICE","members":[
        \\   {"type":"SYMBOL","name":"_inner"},{"type":"STRING","value":"lit"}]},
        \\ "_inner":{"type":"PATTERN","value":"[0-9]+"}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    const expression = symbolNamed(&gr, "expression");
    try testing.expectEqual(g.Shape.hidden, gr.shapeOf(expression));
    try testing.expect(gr.isSupertype(expression));
    try testing.expectEqual(g.Shape.named, gr.shapeOf(symbolNamed(&gr, "doc")));
    try testing.expect(!gr.isSupertype(symbolNamed(&gr, "doc")));
    // Hiding by name reaches a rule that resolved into the terminal space too.
    try testing.expectEqual(g.Shape.hidden, gr.shapeOf(symbolNamed(&gr, "_inner")));
}

test "named, anonymous, and invented are three different answers" {
    const src =
        \\{"name":"t","rules":{"doc":{"type":"SEQ","members":[
        \\ {"type":"STRING","value":"+"},
        \\ {"type":"PATTERN","value":"[0-9]+"},
        \\ {"type":"REPEAT1","content":{"type":"STRING","value":"z"}},
        \\ {"type":"SYMBOL","name":"word"}]},
        \\ "word":{"type":"PATTERN","value":"[a-z]+"}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    // A bare string is a node you can see and cannot name; an inline pattern
    // is not a node at all; a rule is both. Read off the body rather than by
    // name, because the name of an inline pattern is the rendered regex.
    const doc = onlyProduction(&gr, "doc");
    try testing.expectEqual(g.Shape.anonymous, gr.shapeOf(doc.rhs[0]));
    try testing.expectEqualStrings("+", gr.nameOf(doc.rhs[0]));
    try testing.expectEqual(g.Shape.invented, gr.shapeOf(doc.rhs[1]));
    try testing.expectEqual(g.Shape.named, gr.shapeOf(doc.rhs[3]));
    try testing.expectEqualStrings("word", gr.nameOf(doc.rhs[3]));
    try testing.expectEqual(g.Shape.invented, gr.shapeOf(gr.start));

    // The repeat helper is invisible *and* nobody's rule, which is the whole
    // reason `invented` is not spelled the same way as `hidden`.
    try testing.expectEqual(g.Shape.invented, gr.shapeOf(doc.rhs[2]));
    try testing.expect(!gr.shapeOf(doc.rhs[2]).visible());
}

test "two bodies that differ only in what they call a child stay two bodies" {
    // Deduplication collapses two identical productions because no parser can
    // tell them apart. Two trees over one parse is exactly the case where that
    // reasoning stops applying.
    const src =
        \\{"name":"t","rules":{"doc":{"type":"CHOICE","members":[
        \\ {"type":"SYMBOL","name":"word"},
        \\ {"type":"ALIAS","named":true,"value":"other","content":{"type":"SYMBOL","name":"word"}}]},
        \\ "word":{"type":"PATTERN","value":"[a-z]+"}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    const rules = gr.productionsOf(symbolNamed(&gr, "doc"));
    try testing.expectEqual(@as(usize, 2), rules.len);
    try testing.expectEqual(@as(?g.Alias, null), gr.aliasOf(gr.productions[rules[0]].steps[0]));
    try testing.expectEqualStrings("other", gr.aliasOf(gr.productions[rules[1]].steps[0]).?.name);
}

test "two lists that differ only in a field are two auxiliaries" {
    // Sharing a repeat helper by content is what keeps a grammar's conflict
    // count honest, and the content includes what the elements are filed
    // under: merge these and one of the two fields is gone.
    const src =
        \\{"name":"t","rules":{"doc":{"type":"SEQ","members":[
        \\ {"type":"REPEAT1","content":
        \\   {"type":"FIELD","name":"a","content":{"type":"STRING","value":"x"}}},
        \\ {"type":"REPEAT1","content":{"type":"STRING","value":"x"}}]}}}
    ;
    var gr = try treeSitter(testing.allocator, src);
    defer gr.deinit();

    var filed: usize = 0;
    var bare: usize = 0;
    for (gr.productions) |p| {
        if (gr.shapeOf(p.lhs) != .invented or p.lhs == gr.start) continue;
        if (gr.fieldOf(p.steps[p.steps.len - 1]) != null) filed += 1 else bare += 1;
    }
    // Two productions each: `L -> x` and `L -> L x`.
    try testing.expectEqual(@as(usize, 2), filed);
    try testing.expectEqual(@as(usize, 2), bare);
}

/// One of the committed tree-sitter grammars, or `error.FileNotFound` when the
/// corpus is not underfoot. It is a fixture, not a build input, so a run that
/// cannot see it skips rather than fails.
fn corpus(gpa: std.mem.Allocator, name: []const u8) ![]u8 {
    const path = try std.fmt.allocPrint(gpa, "upstream/grammars/{s}.json", .{name});
    defer gpa.free(path);
    var threaded = std.Io.Threaded.init(gpa, .{});
    defer threaded.deinit();
    return std.Io.Dir.cwd().readFileAlloc(threaded.io(), path, gpa, .limited(64 << 20));
}

test "an inheriting grammar arrives already expanded, so `inherits` needs no code" {
    // cpp says `inherits: c` and typescript says `inherits: javascript`, and
    // this importer ignores both. It can, because `tree-sitter generate`
    // resolves inheritance in JavaScript, up in the DSL, and the grammar.json
    // a repository commits is the *result* of that — cpp's file already holds
    // all 182 of c's rule names, 53 of them overridden.
    //
    // Implementing it here would be worse than redundant. The committed
    // javascript.json defines `using_declaration` and typescript.json does
    // not, because the two files were generated at different times against
    // different upstreams; splicing today's parent into yesterday's child
    // would build a grammar neither project has ever shipped.
    //
    // The proof is that the import completes: `alts` refuses a `SYMBOL` naming
    // a rule the grammar does not define, so a single unresolved inherited
    // reference would come back as `error.MalformedGrammar` rather than as a
    // quietly smaller table.
    const inherited = .{ .{ "cpp", "sizeof_expression" }, .{ "typescript", "arrow_function" } };
    inline for (inherited) |pair| {
        const src = corpus(testing.allocator, pair[0]) catch |e| switch (e) {
            error.FileNotFound => return error.SkipZigTest,
            else => return e,
        };
        defer testing.allocator.free(src);
        var gr = try treeSitter(testing.allocator, src);
        defer gr.deinit();
        _ = symbolNamed(&gr, pair[1]); // a parent's rule, present in the child
    }
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
