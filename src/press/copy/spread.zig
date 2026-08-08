//! One rule body, spread into every straight run of symbols it admits.
//!
//! This is the EBNF-to-BNF half of the front end, and `Alt` is the only thing
//! that crosses back out of it: a right-hand side under construction, carrying
//! a step per symbol so that the rank in force where a symbol sits stays with
//! that symbol rather than being averaged into one verdict for the body.
//!
//! A choice distributes into the product, which invents no rule and so invents
//! no place to decide anything; a repeat becomes a left-recursive auxiliary,
//! which is what keeps an LR stack bounded across a list. Both kinds of
//! invented auxiliary are shared by content and emptied of their epsilon
//! alternative, and neither is optional: skip the sharing and two rules writing
//! the same body get two nonterminals deriving the same strings, which is a
//! reduce/reduce conflict with nobody's name on it, and keep the epsilon inside
//! and the parser has to decide whether the list is empty before it has seen
//! anything to decide with.

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
const Alt = struct { rhs: []const u32, steps: []const g.Step, dynamic: i16 = 0 };

comptime {
    // Everything a production says except which nonterminal says it has to have
    // a home here, because this is where a body becomes one. Give `Production` a
    // field and forget this type and there is no compile error to catch it: the
    // hop into `addProductionDynamic` passes the fields one at a time, so the new
    // one simply reads 0 for every grammar ever pressed. That is how `dynamic`
    // came to be dropped in the fold, and c parsed `long total;` the wrong way
    // for as long as it took to find it.
    if (std.meta.fields(Alt).len + 1 != std.meta.fields(g.Production).len)
        @compileError("Production gained a field: carry it on Alt, in `product`, and into `addProductionDynamic`");
}

/// Merge two `prec.dynamic` declarations that reach the same production. The
/// larger magnitude wins; an equal one does not displace what was met first,
/// where first is outside-in and then left to right.
///
/// Read out of tree-sitter rather than reasoned about. `prec.dynamic(2, seq(x,
/// prec.dynamic(-5, y)))` generates `REDUCE(sym_a, 2, -5, …)`, and so does the
/// same pair with the numbers swapped between the layers - so it is neither
/// innermost nor outermost nor a sum, but the loudest opinion anywhere in the
/// body. Which is precisely the rule `product` records having gotten *wrong*
/// for static precedence, and for a good reason: a static rank belongs to the
/// step it was written on, so speaking for the whole body robs the other
/// steps. A dynamic rank has no step to belong to. The reading is the thing
/// that wins or loses, so the whole body is the right scope for it.
fn louder(first: i16, later: i16) i16 {
    return if (@abs(later) > @abs(first)) later else first;
}

/// Expand one rule body into the alternatives it contributes.
///
/// `ctx` is the precedence and associativity in force here — the innermost
/// `prec` wrapper this node sits inside — and every symbol reached records
/// it. `at_end` says whether this node finishes the production it belongs
/// to, which is the one thing a precedence wrapper needs to know about its
/// surroundings; see `close`.
pub fn alts(self: *Import, node: json.Value, ctx: g.Step, at_end: bool, owner: []const u8) Error![]Alt {
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
        const pattern = (try spelling.atomPattern(self, node)) orelse return error.MalformedGrammar;
        const lx = spelling.lexis(self, node);
        const sym = try self.b.intern(try spelling.terminalKey(self, pattern, lx), spelling.terminalName(pattern), pattern);
        self.b.describe(sym, lx);
        // A bare string is a node you can see and cannot name: `("+")`
        // shows up in the tree spelled as itself, and so does every wrapper
        // over one, because a wrapper ranks the lexer rather than naming
        // the result. An inline regex is not even that; tree-sitter files
        // it as auxiliary, so `/\s+/` written mid-rule contributes no node.
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
        return alts(self, inner, next, at_end, owner);
    }

    // `RESERVED` scopes a reserved-word set over its content, which decides
    // how a token *lexes* in that region and nothing about the shape of the
    // parse or the tree; the shift the wrapper is transparent to is the only
    // thing this layer builds.
    if (std.mem.eql(u8, kind, "RESERVED")) {
        const inner = o.get("content") orelse return error.MalformedGrammar;
        return alts(self, inner, ctx, at_end, owner);
    }

    if (std.mem.startsWith(u8, kind, "PREC")) {
        const inner = o.get("content") orelse return error.MalformedGrammar;
        // PREC_DYNAMIC steers GLR tie-breaking at runtime rather than table
        // construction, so it carries no static precedence - and `ctx`,
        // which is the static rank in force, is handed down untouched. The
        // number rides beside it on the alternative instead, where nothing
        // that builds a cell can see it. Dropping it here is what left the
        // parse loop forking correctly on c's `long total;` with both
        // readings alive at the end and no declared basis to pick one.
        if (std.mem.eql(u8, kind, "PREC_DYNAMIC")) {
            const inside = try alts(self, inner, ctx, at_end, owner);
            const declared: i16 = switch (spelling.precValue(self, o.get("value"))) {
                .level => |n| @intCast(n),
                else => 0,
            };
            for (inside) |*alt| alt.dynamic = louder(declared, alt.dynamic);
            return inside;
        }
        var next = ctx;
        next.prec = spelling.precValue(self, o.get("value"));
        if (std.mem.eql(u8, kind, "PREC_LEFT")) next.assoc = .left;
        if (std.mem.eql(u8, kind, "PREC_RIGHT")) next.assoc = .right;
        const inside = try alts(self, inner, next, at_end, owner);
        return if (at_end) drawn(inside) else close(drawn(inside), ctx);
    }

    if (std.mem.eql(u8, kind, "CHOICE")) {
        const members = arr(o.get("members")) orelse return error.MalformedGrammar;
        var out: std.ArrayList(Alt) = .empty;
        for (members.items) |m| try out.appendSlice(a, try alts(self, m, ctx, at_end, owner));
        return out.toOwnedSlice(a);
    }

    if (std.mem.eql(u8, kind, "SEQ")) {
        const members = arr(o.get("members")) orelse return error.MalformedGrammar;
        var acc = try one(a, &.{}, ctx);
        for (members.items, 0..) |m, i| {
            const last = at_end and i == members.items.len - 1;
            var next = try alts(self, m, ctx, last, owner);
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
                next = try hoist(self, try alts(self, m, shaping, true, owner), ctx, owner);
            }
            acc = try product(a, acc, next);
        }
        return acc;
    }

    if (std.mem.eql(u8, kind, "REPEAT") or std.mem.eql(u8, kind, "REPEAT1")) {
        const content = o.get("content") orelse return error.MalformedGrammar;
        // The list is its own rule, so its body is at the end of *that*
        // rule and inherits nothing from the position of the reference.
        const body = try alts(self, content, .{}, true, owner);
        const aux = try listSymbol(self, owner, body);
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
pub fn listSymbol(self: *Import, owner: []const u8, body: []const Alt) Error!u32 {
    const a = self.scratch.allocator();
    const key = try bodyKey(self, "list", body);
    if (self.b.lookup(key)) |shared| return shared;

    self.aux += 1;
    const name = try std.fmt.allocPrint(a, "{s}_repeat{d}", .{ owner, self.aux });
    const aux = try self.b.intern(key, name, null);
    self.b.shape(aux, .invented);
    // The first host names it and owns it. Both are reports for a human;
    // the language the auxiliary denotes is the same either way.
    if (self.symbols.get(owner)) |rule| self.b.ascribe(aux, rule);
    for (body) |alt| {
        // Both the element and the step that goes round again, because a
        // `prec.dynamic` written around a list ranks reading the list -
        // and a reading that stops after two elements has taken the loop
        // as many times as it took the element.
        try self.b.addProductionDynamic(aux, alt.rhs, alt.steps, alt.dynamic);
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
            // With the region the element's rank was drawn around, since this
            // step carries that same rank: the loop is not a second statement
            // the author made, it is the one they made, read again.
            .{
                .prec = alt.steps[0].prec,
                .assoc = alt.steps[0].assoc,
                .region = alt.steps[0].region,
            }
        else
            .{};
        @memcpy(steps[1..], alt.steps);
        try self.b.addProductionDynamic(aux, looped, steps, alt.dynamic);
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
pub fn hoist(self: *Import, set: []Alt, at: g.Step, owner: []const u8) Error![]Alt {
    const a = self.scratch.allocator();
    var filled: std.ArrayList(Alt) = .empty;
    var empty = false;
    for (set) |alt| {
        if (alt.rhs.len == 0) empty = true else try filled.append(a, alt);
    }
    if (filled.items.len == 0) return one(a, &.{}, .{});

    const key = try bodyKey(self, "choice", filled.items);
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
        for (filled.items) |alt| {
            try self.b.addProductionDynamic(sym, alt.rhs, alt.steps, alt.dynamic);
        }
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
/// spell the same key, and every field of a step that says what the
/// production *is* is in it: a `prec.left` body and a bare one are different
/// rules, and an aliased body and a bare one are different trees.
///
/// `region` is the exception, and it is an exception on purpose. It measures the
/// syntax the author wrote around a rank rather than anything the body derives,
/// and two bodies alike in every other field derive the same strings, carry the
/// same ranks and build the same trees. Keying on it would split an auxiliary on
/// provenance: measured 2026-08-07 across the corpus of thirty, it moved 26
/// grammars, cost sql its unfolding round and 63 of its declared conflicts -
/// which stopped matching once the participating rule set changed - and took it
/// from 0 residual to 280 reduce/reduce.
///
/// The hazard it declines to chase: `seq(prec(1,a), prec(1,b))` and
/// `prec(1, seq(a,b))` reach here with the same rhs and the same ranks, regions
/// `1,1` against `2,2`, and share one auxiliary - so whichever is interned first
/// decides for both. No grammar in the corpus contains the pair, and the shared
/// answer is only ever one fold's provenance flag rather than a cell. If one
/// turns up, widen the merge to the larger region rather than splitting on it:
/// wide is the conservative answer everywhere `region` is read.
pub fn bodyKey(self: *Import, tag: []const u8, body: []const Alt) Error![]const u8 {
    const a = self.scratch.allocator();
    var words: std.ArrayList(u32) = .empty;
    for (body) |alt| {
        try words.append(a, @intCast(alt.rhs.len));
        try words.appendSlice(a, alt.rhs);
        // Two bodies that differ only in what `prec.dynamic` says about
        // them are two auxiliaries. Sharing one would let whichever
        // arrived first fix the rank for both, which is the same identity
        // mistake that let a rule-terminal shadow an anonymous one.
        try words.append(a, @bitCast(@as(i32, alt.dynamic)));
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
        // The rank is being replaced, so the region measured for the one leaving
        // does not describe the one arriving. Back to unmeasured, which is where
        // the enclosing group's own `drawn` will find it if there is one, and
        // which reads as wide rather than narrow if there is not.
        last.region = 0;
    }
    return set;
}

/// Record how many steps this precedence group was written around, on the steps
/// it is the group *for*.
///
/// Called once per `prec` node, on the way back up, because the width is a fact
/// about the node's content and the content is what was just built. A step is
/// this group's own when it carries a rank and nothing has measured it yet:
/// recursion is depth-first, so a nested group has already claimed everything
/// inside it, and the tightest enclosing `prec` is the one whose region decides
/// whether a fold can break it. A step with no rank at all is left alone - there
/// is no statement on it to have a width.
///
/// The **widest** reading of the group, not each reading's own width, and the
/// difference is the whole measurement. An `optional` or a `repeat` inside the
/// group gives it a reading with those members absent, so verilog's
/// `hierarchical_identifier` - `prec.left(0, seq(choice($root ., ε),
/// repeat(…), _identifier))` - has a reading that is bare `_identifier`, one
/// step wide. Measured per reading, that one alternative claims the author
/// ranked a single step and a fold may carry the rank into a host; measured
/// across the group, the author plainly drew it around a sequence, and the
/// narrow reading is a reading *of* that sequence rather than a second, narrower
/// statement. Taking the max is what makes this a question about what was
/// written instead of about which branch we are looking at.
fn drawn(set: []Alt) []Alt {
    var widest: usize = 0;
    for (set) |alt| widest = @max(widest, alt.steps.len);
    for (set) |alt| {
        for (@constCast(alt.steps)) |*step| {
            if (step.region != 0) continue;
            if (step.prec == .none and step.assoc == .none) continue;
            step.region = @intCast(widest);
        }
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
/// Static rank needs nothing reconciled: each side's steps already carry the
/// rank in force where they sit, so concatenating the bodies concatenates the
/// ranks. The version of this that kept one precedence per production had to
/// pick a winner here, and picked by magnitude — which is how a body's
/// strongest wrapper came to speak for every symbol in it.
///
/// Dynamic rank is the one thing that does have to be reconciled, and by that
/// same discredited rule, because a production really does get one of them.
/// Two thirds of the declarations in the pinned grammars sit at a rule's root,
/// but the rest are on a member of a sequence; go ranks `_simple_type` from
/// inside its body, and a member's declaration has to reach the production it
/// ends up in or it is lost at the join.
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
        out[i] = .{ .rhs = rhs, .steps = steps, .dynamic = louder(l.dynamic, r.dynamic) };
        i += 1;
    };
    return out;
}
