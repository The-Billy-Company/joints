//! The roll call: every symbol the grammar has, named and numbered, before any
//! one body is lowered.
//!
//! Nothing here is about the shape of a rule. It is the grammar taken all at
//! once - which names are hidden, which orderings the author declared, which
//! rules only derive a token that another place also spells, and above all what
//! order the terminals are numbered in, because the lowest surviving symbol id
//! is the last rung of the lexical tie-break and so decides which of two tokens
//! matching the same bytes the lexer hands back.
//!
//! The passes run in an order `import.zig` fixes and none of them may assume
//! another has run, with one exception it states out loud: the census decides
//! `wrapping`, and both the numbering and the interning read it. Everything
//! else walks the whole rule set and looks inside a body only far enough to
//! find the atoms spelled in it.

const std = @import("std");
const json = std.json;
const g = @import("grammar.zig");
const galley = @import("galley.zig");
const spelling = @import("spelling.zig");

const Import = galley.Import;
const Error = galley.Error;
const obj = galley.obj;
const arr = galley.arr;
const str = galley.str;

/// The abstract categories the author declared. Read before anything else
/// because being in this list is what hides `expression`, and hiddenness is
/// decided at the moment the rule is interned.
pub fn readSupertypes(self: *Import, node: ?json.Value) Error!void {
    const list = arr(node) orelse return;
    for (list.items) |entry| {
        if (str(entry)) |n| try self.supertypes.put(n, {});
    }
}

/// Hand the resolved supertype symbols to the builder. A name the grammar
/// does not define is dropped rather than invented, the same way an
/// ordering entry naming a missing rule is.
pub fn placeSupertypes(self: *Import) Error!void {
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
pub fn shapeOfRule(self: *const Import, name: []const u8) g.Shape {
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
pub fn readPrecedences(self: *Import, node: ?json.Value) Error!void {
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
pub fn placePrecedences(self: *Import) Error!void {
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
///
/// An `externals` entry does not have to be a `SYMBOL`. bash, python, ruby,
/// javascript and typescript all declare entries the author spelled out
/// instead of naming, and those are not a second kind of external: they are
/// the ordinary token, with the scanner allowed to produce it too.
/// tree-sitter's `ts_external_scanner_symbol_map` maps such an entry
/// straight onto the symbol the same spelling gets inline - a probe
/// declaring `'}'` both ways yields one `anon_sym_RBRACE` that the map
/// points at and that `ts_lex` still has an `ACCEPT_TOKEN` for - where a
/// named external gets a symbol of its own and no lexer rule at all.
/// So it interns exactly as if written in a rule body, and the terminal
/// stays lexable rather than joining the blind set.
pub fn internExternals(self: *Import, node: ?json.Value) Error!void {
    const list = arr(node) orelse return;
    for (list.items) |entry| {
        const o = obj(entry) orelse continue;
        if (str(o.get("name"))) |n| {
            const sym = try self.b.intern(n, n, .external);
            self.b.shape(sym, shapeOfRule(self, n));
            try self.symbols.put(n, sym);
            continue;
        }
        const pattern = (try spelling.atomPattern(self, entry)) orelse continue;
        const lx = spelling.lexis(self, entry);
        const sym = try self.b.intern(try spelling.terminalKey(self, pattern, lx), spelling.terminalName(pattern), pattern);
        self.b.describe(sym, lx);
        self.b.shape(sym, if (pattern == .literal) .anonymous else .invented);
        // No `symbols` entry: there is no rule name for a `SYMBOL`
        // reference to reach it by, which is what makes it anonymous.
    }
}

/// Which rules name a token, and which only derive one.
///
/// A rule whose whole body is one atom usually *is* a terminal called after
/// the rule; that is how `identifier: /[a-z]+/` becomes a named token, and
/// it is right. It stops being right the moment a second place spells the
/// same token, because then the name is contested and only one symbol can
/// hold it.
///
/// tree-sitter resolves that by lifting every atom into one shared pool
/// (`extract_tokens`) keyed by what it matches and the standing it matches
/// under. A rule lends the pool its name only when it is that key's *sole*
/// claimant. Claimed twice and the pool keeps an anonymous terminal, and
/// every rule claiming it reduces from a one-symbol production instead. Its
/// generated parsers say so outright: javascript's `import`, typescript's
/// `override_modifier`, rust's `empty_statement`, go's `dot`, ruby's `nil`
/// and python's `wildcard_import` each carry `REDUCE(sym_…, 1)` and no
/// `ACCEPT_TOKEN` of their own. A probe with two rules and no inline
/// spelling at all settles that it is the count and not the anonymity that
/// decides: `kwa: token('go')` beside `kwb: token('go')` makes an
/// `anon_sym_go` neither rule is named after, and reduces both.
///
/// Naming both was never a tie a lexer could be taught to break. The two
/// terminals matched identical bytes, and every state that admitted one
/// admitted the other, because the grammar really does allow either there.
/// `outliner state` prints both on the row. Rules are interned before
/// inline atoms, so the rule always won, and javascript's `import` beat the
/// `'import'` its own `import_statement` needed.
pub fn census(self: *Import, extras: ?json.Value, externals: ?json.Value) Error!void {
    var claims = std.StringHashMap(u16).init(self.gpa);
    defer claims.deinit();

    // First, because every pass below asks what a rule spells and one of them
    // has to know that an extra reaching nothing spells a token. A declared
    // extra naming a rule that names no other rule is lexical however the author
    // spelled it; anything else stays structure it is not this pass's business
    // to flatten. See `spelling.bodyPattern`.
    if (arr(extras)) |list| for (list.items) |entry| {
        const o = obj(entry) orelse continue;
        if (!std.mem.eql(u8, str(o.get("type")) orelse continue, "SYMBOL")) continue;
        const n = str(o.get("name")) orelse continue;
        const body = self.rules.get(n) orelse continue;
        if (spelling.bare(body)) try self.lexical.put(n, {});
    };

    const into: Sink = .{ .count = &claims };
    for (self.rules.keys(), self.rules.values()) |name, body| {
        try walkAtoms(self, body, name, true, into);
    }
    if (arr(extras)) |list| for (list.items) |entry| try walkAtoms(self, entry, null, true, into);
    // A spelled-out external claims its token like any other sighting. The
    // probe grammar proves it: `term: /\n/` beside an external `PATTERN \n`
    // leaves tree-sitter reducing `sym_term` off an `aux_sym_term_token1`
    // no rule is named after, exactly as a second inline spelling would.
    if (arr(externals)) |list| for (list.items) |entry| try walkAtoms(self, entry, null, true, into);

    for (self.rules.keys(), self.rules.values()) |name, body| {
        const pattern = (try spelling.bodyPattern(self, name, body)) orelse continue;
        const key = try spelling.terminalKey(self, pattern, spelling.lexis(self, body));
        if ((claims.get(key) orelse 0) > 1) try self.wrapping.put(name, {});
    }
}

/// Rules nothing reaches, which spell a token nothing can read.
///
/// A grammar may carry a rule no other rule names and no block declares - an
/// author's leftover, and upstream markdown, cpp, sql, verilog and haskell each
/// ship one or more. Structure is already handled: `fold.sweep` deletes the
/// productions of a nonterminal no root reaches. A rule whose whole body is one
/// lexical atom is the case the sweep cannot reach, because it is not a
/// production at all by then - it is a *terminal in the slate*, and the lexer
/// offers it at every byte.
///
/// That is not a harmless extra column. markdown's `_newline_token` spells
/// `\n|\r\n?` and competes with the external `_line_ending` for the same bytes;
/// win or lose, no state reads it, so a parse that is handed one is over. The
/// terminal must not exist rather than not be read - which is why this runs
/// before `internRules` instead of pruning after the tables.
///
/// The condition is *mentioned nowhere*, not *unreachable*, and the difference
/// is load-bearing. Transitive reachability was tried first and it is too wide:
/// cpp's `variadic_parameter` and two verilog rules are named only by other dead
/// rules, so a transitive sweep condemns them - and then `spread` walks one of
/// those dead bodies anyway, finds no symbol, and the whole grammar stops
/// importing with `MalformedGrammar`. Death by reachability is only sound if
/// nothing walks the dead; here something does.
///
/// A rule whose name appears in no body and no block cannot be walked by
/// anything, so declining to intern it is safe by construction rather than by
/// argument. It also leaves upstream's own leftovers alone unless they are truly
/// orphaned, which is the conservative direction: the cost of keeping one is a
/// spurious slate entry, and the cost of removing one wrongly is a grammar that
/// will not load.
pub fn condemn(self: *Import, root: json.ObjectMap) Error!void {
    const s = self.scratch.allocator();
    var mentioned = std.StringHashMap(void).init(s);
    for (self.rules.values()) |body| try referenced(body, &mentioned);
    for ([_][]const u8{ "extras", "externals", "inline", "supertypes", "conflicts" }) |block| {
        if (root.get(block)) |b| try referenced(b, &mentioned);
    }
    if (str(root.get("word"))) |w| try mentioned.put(w, {});

    for (self.rules.keys(), self.rules.values()) |name, body| {
        if (mentioned.contains(name)) continue;
        if (self.rules.count() > 0 and std.mem.eql(u8, name, self.rules.keys()[0])) continue;
        // Structure nothing mentions is the sweep's, and leaving it there is what
        // keeps this pass from having an opinion about folding.
        if ((try spelling.bodyPattern(self, name, body)) == null) continue;
        try self.dead.put(name, {});
    }
}

/// Every rule name this subtree could reach a rule by: a `SYMBOL` reference, and
/// a bare string, since `conflicts`, `inline` and `supertypes` spell names
/// without wrapping them in a node.
fn referenced(node: json.Value, into: *std.StringHashMap(void)) Error!void {
    switch (node) {
        .object => |o| {
            if (str(o.get("type"))) |kind| if (std.mem.eql(u8, kind, "SYMBOL")) {
                if (str(o.get("name"))) |name| try into.put(name, {});
            };
            var it = o.iterator();
            while (it.next()) |kv| try referenced(kv.value_ptr.*, into);
        },
        .array => |a| for (a.items) |item| try referenced(item, into),
        .string => |v| try into.put(v, {}),
        else => {},
    }
}

/// What an atom sighting is worth to the caller: a claim, for the census
/// that decides which rules are contested, or a symbol, for the numbering
/// that decides which of two tokens spelling the same bytes comes back.
/// One walk serves both so the two can never come to disagree about what
/// counts as an atom.
const Sink = union(enum) { count: *std.StringHashMap(u16), number };

/// Tally or intern one claim per atom, and never look inside one.
///
/// `whole` marks a rule body, which `internRules` interns in one piece and
/// so reads the wrapper chain one layer further out than `alts` does for
/// the same bytes written inline. The two readings part company only for a
/// `prec` *outside* a `token`, which `lexis` declines to read as a rank at
/// all, so ruby's `prec(-1, ';')` and python's `prec.left(0, 'pass')` both
/// settle where a bare literal already is.
pub fn walkAtoms(
    self: *Import,
    node: json.Value,
    /// The rule this body belongs to, when it is one. Null for an inline node
    /// and for an `extras`/`externals` entry, neither of which is a rule that
    /// could be declared lexical.
    named: ?[]const u8,
    whole: bool,
    into: Sink,
) Error!void {
    const o = obj(node) orelse return;
    const kind = str(o.get("type")) orelse return;

    // The four `alts` interns directly. Anything else is structure, even
    // when a single atom is reachable through it.
    const spelled = whole or std.mem.eql(u8, kind, "STRING") or
        std.mem.eql(u8, kind, "PATTERN") or std.mem.eql(u8, kind, "TOKEN") or
        std.mem.eql(u8, kind, "IMMEDIATE_TOKEN");
    if (spelled) {
        // A body is asked the wider question, because a rule reaching no other
        // rule is a token however it is spelled; an inline `seq` is not.
        const found = if (whole and named != null)
            try spelling.bodyPattern(self, named.?, node)
        else
            try spelling.atomPattern(self, node);
        if (found) |pattern| {
            const key = try spelling.terminalKey(self, pattern, spelling.lexis(self, node));
            switch (into) {
                .count => |claims| {
                    const slot = try claims.getOrPut(key);
                    slot.value_ptr.* = if (slot.found_existing) slot.value_ptr.* +| 1 else 1;
                },
                .number => _ = try self.b.intern(key, spelling.terminalName(pattern), pattern),
            }
            return;
        }
    }
    if (arr(o.get("members"))) |list| {
        for (list.items) |item| try walkAtoms(self, item, null, false, into);
    }
    if (o.get("content")) |content| try walkAtoms(self, content, null, false, into);
}

/// Number the terminals the way tree-sitter numbers them, before any other
/// pass interns one.
///
/// The lowest surviving symbol id is the last rung of the lexical
/// tie-break, so this is not bookkeeping - it decides which of two tokens
/// matching the same bytes the lexer hands back. tree-sitter walks the
/// rules in *declaration* order and descends into each body as it reaches
/// it, so an earlier rule's inline pattern is numbered below a later rule's
/// name. Interning every named rule first reverses exactly that pair, which
/// is the whole of C's `preproc_include` losing to `preproc_directive`.
/// The `word` is hoisted to the front and the externals are numbered after
/// every rule-derived token. Read off generated parsers: `declorder` (the
/// declaration order decides, not the order of reference), `midbody` (a
/// rule's own atoms in the order its body spells them), `placement2` (the
/// word first, the externals last).
///
/// Idempotent by construction: `intern` hands back a key it already holds,
/// so every later pass still asks for its symbols in its own order and
/// simply finds them waiting.
pub fn numberTerminals(self: *Import, word: ?json.Value, externals: ?json.Value) Error!void {
    // A name an external claims is that external's, wherever a rule of the
    // same name is declared, and is numbered with the externals.
    var claimed = std.StringHashMap(void).init(self.gpa);
    defer claimed.deinit();
    if (arr(externals)) |list| for (list.items) |entry| {
        if (obj(entry)) |o| if (str(o.get("name"))) |n| try claimed.put(n, {});
    };

    if (str(word)) |w| if (self.rules.get(w)) |body| try numberRule(self, w, body, &claimed);
    for (self.rules.keys(), self.rules.values()) |name, body| {
        try numberRule(self, name, body, &claimed);
    }
}

/// One rule's contribution to the numbering: the token it *is*, or else the
/// tokens its body spells, in the order the body spells them.
pub fn numberRule(
    self: *Import,
    name: []const u8,
    body: json.Value,
    claimed: *const std.StringHashMap(void),
) Error!void {
    if (claimed.contains(name)) return;
    // The numbering pass is where a rule that spells a token gets its number, so
    // it is also where a token nothing can read has to be declined; skipping only
    // `internRules` would number it here and leave it in the slate anyway.
    if (self.dead.contains(name)) return;
    if (!self.wrapping.contains(name)) {
        if (try spelling.bodyPattern(self, name, body)) |pattern| {
            _ = try self.b.intern(name, name, pattern);
            return;
        }
    }
    try walkAtoms(self, body, name, true, .number);
}

pub fn internRules(self: *Import) Error!void {
    for (self.rules.keys(), self.rules.values()) |name, body| {
        if (self.symbols.get(name) != null) continue; // an external already claimed it
        if (self.dead.contains(name)) continue; // a token no state could read
        // A rule the census found sharing its spelling derives that token
        // rather than being it, so it is interned with no pattern and the
        // body walk gives it the one-symbol production tree-sitter reduces.
        const pattern = if (self.wrapping.contains(name)) null else try spelling.bodyPattern(self, name, body);
        // Both spaces share the rule-name key: a `SYMBOL` reference has to
        // find the rule under the name it used, whichever space it landed
        // in. Anonymous terminals are namespaced away under `str:`/`rx:`.
        const sym = try self.b.intern(name, name, pattern);
        self.b.describe(sym, spelling.lexis(self, body));
        self.b.shape(sym, shapeOfRule(self, name));
        try self.symbols.put(name, sym);
    }
}

/// Terminals the lexer skips between tokens. A grammar may name a rule that
/// turned out to be structure (a `comment` built from several tokens); it
/// is recorded as it resolved, and it is the lexer's job to refuse what it
/// cannot skip rather than this function's job to hide it.
pub fn readExtras(self: *Import, node: ?json.Value) Error![]const u32 {
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
        const pattern = (try spelling.atomPattern(self, entry)) orelse continue;
        // Described, not just interned: the key carries the standing, so a
        // terminal only an extra ever reaches would otherwise be filed
        // under a rank and an immediacy nothing recorded.
        const lx = spelling.lexis(self, entry);
        const sym = try self.b.intern(try spelling.terminalKey(self, pattern, lx), spelling.terminalName(pattern), pattern);
        self.b.describe(sym, lx);
        self.b.shape(sym, if (pattern == .literal) .anonymous else .invented);
        try out.append(self.scratch.allocator(), sym);
    }
    return out.items;
}

/// Rules the grammar asks to be substituted away. A name that is already a
/// terminal is not foldable — there is no body to substitute — and the
/// start symbol must survive, so both are skipped.
pub fn readInline(self: *Import, node: ?json.Value) Error![]const u32 {
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

pub fn readConflicts(self: *Import, node: ?json.Value) Error![]const []const u32 {
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
