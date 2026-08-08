//! The grammar's facts, indexed the way a query asks for them.
//!
//! A folio stores names the wrong way round for a query. It is id-indexed -
//! symbol 41 is `binary_expression` - and a `.scm` file only ever says
//! `binary_expression`. So this builds the reverse once per grammar and answers
//! every query compiled against it.
//!
//! Three relations here are not in the folio at all, and all three matter:
//!
//!   * **Supertype membership.** `Folio.supertypes()` says which rules ARE
//!     supertypes. It does not say which concrete kinds belong to one, and the
//!     forty-three `(supertype/subtype)` uses in the corpus need exactly that.
//!     A supertype presses as `hidden`, so it emits no node and splices its
//!     children - which means the membership is the splice, and falls straight
//!     out of the closure below.
//!   * **Which fields a kind can carry.** Same shape of problem: a field is
//!     written on a production's child position, so a kind's fields are the
//!     union over its productions - and over anything hidden those productions
//!     splice, because the field on a spliced child lands on whoever absorbed
//!     it.
//!   * **What a rename is called.** The folio stores aliases as an interned
//!     table beside the symbols, because the press CARRIES tree shaping rather
//!     than applying it. A query does not know that: `alias($.identifier,
//!     $.type_identifier)` means the tree says `type_identifier`, so that is
//!     what a query writes, and ten of the corpus's grammars write it. Names
//!     that no symbol owns are looked up here in a second, parallel space -
//!     see `rename`.
//!
//! One fixed point answers both. Walk every production; a visible right-hand
//! symbol is a child of the left-hand one, a hidden or invented one contributes
//! everything IT contributes. Iterate until nothing moves. `kids` restricted to
//! a supertype is its membership; `carries` is the field half of the same walk.
//!
//! Names are looked up through a hash map rather than through
//! `press.dafsa.rank`, which is a minimal perfect hash over the same keys and
//! would have been the tidier answer. `bench/rungs/gloss` builds both and
//! prints the ratio, because the last lane's DAFSA verdict was about STORAGE
//! and this is a different question. The measured answer is in the README.

const std = @import("std");
const folio = @import("../../folio/folio.zig");

const leaf = folio.leaf;

/// No such id. Same sentinel the folio spends on an absent field.
pub const none = leaf.none;

pub const Error = std.mem.Allocator.Error;

/// What a `.scm` name can turn out to be. `kind` and `literal` are both
/// symbols and are kept apart because the query notation keeps them apart:
/// `(identifier)` may not match the anonymous `"identifier"` and `"if"` may not
/// match a rule called `if`.
pub const Sort = enum { kind, literal, category };

/// What one spelling can mean. Empty on both counts means the grammar has never
/// heard of it.
///
/// `syms` is a SET and not an id, which is the fact this type exists to carry.
/// tree-sitter mints a fresh terminal for `token(prec(1, "<"))` beside the plain
/// `"<"` and both display as `<`, so Rust's `"<" @punctuation.bracket` names two
/// symbols; twenty-two of the corpus's twenty-eight grammars share a spelling
/// somewhere, Ruby thirty-one times. Answering with the first was a program that
/// highlighted some of the angle brackets.
pub const Reading = struct {
    syms: []const u32 = &.{},
    alias: u32 = none,

    pub fn known(r: Reading) bool {
        return r.syms.len != 0 or r.alias != none;
    }
};

pub const Lemma = struct {
    gpa: std.mem.Allocator,
    f: *const folio.Folio,
    /// Every visible symbol by name, and every hidden one too - one row per
    /// SPELLING, holding a slot per sort, because a name is genuinely ambiguous
    /// across sorts and the query notation is what disambiguates it. Ruby has a
    /// rule `alias` and a keyword `"alias"`; JavaScript, `class`; TypeScript,
    /// `module`; Python, `type`. A row per name that kept only the first symbol
    /// answered `(class)` with whichever id the importer happened to mint
    /// first, which is to say it refused eleven of the corpus's files for a
    /// question they had already answered by writing the parentheses.
    by_name: std.StringHashMapUnmanaged(Entry) = .empty,
    fields_by_name: std.StringHashMapUnmanaged(u32) = .empty,
    /// Renames by name, kept apart from `by_name` rather than merged into it
    /// because the two spaces genuinely collide: Ruby has a RULE called `alias`
    /// and grammars elsewhere rename a node to a word that is also somebody's
    /// rule. A symbol wins - it is the name the grammar's own author declared -
    /// and this is consulted only when that lookup came back empty.
    renames_by_name: std.StringHashMapUnmanaged(Rename) = .empty,
    /// Every entry's symbols, back to back. One allocation for the whole index
    /// rather than a list per name, and the runs above are windows onto it.
    members: []u32,
    /// Per alias, the sole symbol it renames, or `none` when no symbol or more
    /// than one does. A singleton is the common case and the useful one: it
    /// lets a renamed node's children and fields be checked against the real
    /// structure underneath. Ambiguity declines to check rather than guessing.
    renamed: []u32,
    /// Per symbol, the renames it can put in a tree. `kids` for the other space.
    renames: Bits,
    /// Per symbol, the visible symbols it can put in a tree. For a hidden
    /// symbol that is its splice; for a supertype, its membership.
    kids: Bits,
    /// Per symbol, the fields it can carry.
    fields: Bits,
    /// How many passes the closure took. Reported by the rung: a grammar whose
    /// hidden rules nest deeply is a different shape from one that settles in
    /// two.
    passes: u32,

    /// One spelling's symbols, per sort - a run each into `members`, since a
    /// spelling can be several symbols of the same sort as well as one symbol
    /// of each. Three runs rather than a list of them: `Sort` has three values
    /// and always will, being the query notation's own trichotomy.
    pub const Entry = struct {
        kind: Run = .{},
        literal: Run = .{},
        category: Run = .{},

        fn at(e: Entry, sort: Sort) Run {
            return switch (sort) {
                .kind => e.kind,
                .literal => e.literal,
                .category => e.category,
            };
        }

        fn slot(e: *Entry, sort: Sort) *Run {
            return switch (sort) {
                .kind => &e.kind,
                .literal => &e.literal,
                .category => &e.category,
            };
        }
    };

    /// One spelling's renames. `internAlias` keys the alias table on (name,
    /// named), so a spelling has at most one of each and neither needs a run.
    pub const Rename = struct {
        named: u32 = none,
        anonymous: u32 = none,

        fn at(r: Rename, sort: Sort) u32 {
            return switch (sort) {
                .kind => r.named,
                .literal => r.anonymous,
                // An alias table holds no hidden rules, so a rename is never a
                // category and this is not an oversight.
                .category => none,
            };
        }
    };

    /// A run of `members`. Ascending by symbol id, because the fill walks the
    /// symbols in order, so the author's own rule leads anything the importer
    /// minted later under the same spelling.
    pub const Run = struct { off: u32 = 0, len: u32 = 0 };

    pub fn deinit(l: *Lemma) void {
        l.gpa.free(l.members);
        l.by_name.deinit(l.gpa);
        l.fields_by_name.deinit(l.gpa);
        l.renames_by_name.deinit(l.gpa);
        l.gpa.free(l.renamed);
        l.kids.deinit(l.gpa);
        l.fields.deinit(l.gpa);
        l.renames.deinit(l.gpa);
        l.* = undefined;
    }

    /// The symbol a query means by this name, at this sort, or null.
    /// Every symbol this name means at this sort, in id order. Empty for a name
    /// the grammar does not have at that sort.
    pub fn every(l: *const Lemma, name: []const u8, sort: Sort) []const u32 {
        const run = (l.by_name.get(name) orelse return &.{}).at(sort);
        return l.members[run.off..][0..run.len];
    }

    /// The first symbol this name means at this sort. For the caller that wants
    /// one id and is entitled to one - a category, a test - and never for a
    /// match, where the whole set is the answer.
    pub fn lookup(l: *const Lemma, name: []const u8, sort: Sort) ?u32 {
        const all = l.every(name, sort);
        return if (all.len == 0) null else all[0];
    }

    /// The rename a query means by this name, at this sort, or null. Ask after
    /// `lookup` and not instead of it: a name both spaces know is the symbol's.
    ///
    /// `sort` discriminates the same way it does for a symbol, and for the same
    /// reason - `alias($.x, $.type_identifier)` is a named rename and answers
    /// `(type_identifier)`, while PHP's `alias(..., 'and')` is an anonymous one
    /// and answers `"and"`. A rename is never a category: an alias table holds
    /// no hidden rules.
    pub fn rename(l: *const Lemma, name: []const u8, sort: Sort) ?u32 {
        const a = (l.renames_by_name.get(name) orelse return null).at(sort);
        return if (a == none) null else a;
    }

    /// Both readings of one spelling, which is what a query name actually is.
    ///
    /// A word in a `.scm` names a node kind, and a node's kind is a symbol OR a
    /// rename applied to one. Usually only one of the two exists and the
    /// question does not arise. When both do - C++ has a rule
    /// `function_declarator` and also renames `_function_field_declarator` to
    /// that spelling - the file means whichever the node in hand turns out to
    /// be, so both come back and the program carries both. Answering with the
    /// symbol alone is what made this compiler call forty live C++ and Scala
    /// patterns dead.
    pub fn reading(l: *const Lemma, name: []const u8, sort: Sort) Reading {
        return .{
            .syms = l.every(name, sort),
            .alias = l.rename(name, sort) orelse none,
        };
    }

    /// The symbol a rename stands in for, when exactly one does. Null when the
    /// grammar renames several things to one name, where there is no single
    /// structure to check a child against.
    pub fn beneath(l: *const Lemma, alias: u32) ?u32 {
        if (alias >= l.renamed.len) return null;
        const sym = l.renamed[alias];
        return if (sym == none) null else sym;
    }

    /// Can a node of this kind ever hold a child wearing this rename?
    pub fn admitsRename(l: *const Lemma, parent: u32, alias: u32) bool {
        return l.renames.has(parent, alias);
    }

    /// What this name can be, at all. For the diagnostic that wants to say
    /// "`expression` is a supertype, not a node" rather than "unknown". A
    /// spelling can be more than one thing, so this answers with the whole set
    /// and the caller says which it wanted.
    pub fn sortsOf(l: *const Lemma, name: []const u8) std.EnumSet(Sort) {
        var out: std.EnumSet(Sort) = .initEmpty();
        const e = l.by_name.get(name) orelse return out;
        inline for (@typeInfo(Sort).@"enum".fields) |f| {
            const sort: Sort = @enumFromInt(f.value);
            if (e.at(sort) != none) out.insert(sort);
        }
        return out;
    }

    pub fn field(l: *const Lemma, name: []const u8) ?u32 {
        return l.fields_by_name.get(name);
    }

    /// Can a node of this kind carry this field? The reachability check that
    /// catches the most in practice, because a field is the one thing a query
    /// author writes from memory.
    pub fn carries(l: *const Lemma, kind: u32, id: u32) bool {
        return l.fields.has(kind, id);
    }

    /// Is this concrete kind a member of this category? The relation the folio
    /// does not store.
    pub fn member(l: *const Lemma, category: u32, kind: u32) bool {
        return l.kids.has(category, kind);
    }

    /// Can a node of this kind ever have a child of that kind? Anywhere in the
    /// subtree a splice can reach, which is the honest bound: a hidden rule
    /// puts its own children under whoever absorbed it.
    pub fn admits(l: *const Lemma, parent: u32, child: u32) bool {
        return l.kids.has(parent, child);
    }

    /// Every concrete kind in a category, ascending. Allocated; the caller
    /// frees. Only the diagnostic path wants this - a check uses `member`.
    pub fn membersOf(l: *const Lemma, gpa: std.mem.Allocator, category: u32) Error![]u32 {
        var out: std.ArrayList(u32) = .empty;
        errdefer out.deinit(gpa);
        for (0..l.kids.stride_bits) |s| {
            if (l.kids.has(category, @intCast(s))) try out.append(gpa, @intCast(s));
        }
        return out.toOwnedSlice(gpa);
    }
};

/// A rectangular bitset: one row per symbol, one column per whatever the row is
/// about. Flat rather than a slice of `DynamicBitSet`, because the closure below
/// ors whole rows together and a row has to be one contiguous run for that to
/// be a loop over words.
pub const Bits = struct {
    words: []usize,
    stride: usize,
    stride_bits: usize,

    const word_bits = @bitSizeOf(usize);

    fn init(gpa: std.mem.Allocator, rows: usize, cols: usize) Error!Bits {
        const stride = (cols + word_bits - 1) / word_bits;
        const words = try gpa.alloc(usize, rows * stride);
        @memset(words, 0);
        return .{ .words = words, .stride = stride, .stride_bits = cols };
    }

    fn deinit(b: *Bits, gpa: std.mem.Allocator) void {
        gpa.free(b.words);
        b.* = undefined;
    }

    fn row(b: Bits, i: u32) []usize {
        return b.words[@as(usize, i) * b.stride ..][0..b.stride];
    }

    pub fn has(b: Bits, i: u32, bit: u32) bool {
        if (bit >= b.stride_bits or b.stride == 0) return false;
        return b.row(i)[bit / word_bits] & (@as(usize, 1) << @intCast(bit % word_bits)) != 0;
    }

    fn set(b: Bits, i: u32, bit: u32) bool {
        const w = &b.row(i)[bit / word_bits];
        const mask = @as(usize, 1) << @intCast(bit % word_bits);
        const grew = w.* & mask == 0;
        w.* |= mask;
        return grew;
    }

    /// Row `dst` gains everything row `src` has. True when it gained anything,
    /// which is the whole fixed-point condition.
    fn absorb(b: Bits, dst: u32, src: u32) bool {
        if (dst == src) return false;
        var grew = false;
        const to = b.row(dst);
        const from = b.row(src);
        for (to, from) |*a, c| {
            const was = a.*;
            a.* |= c;
            grew = grew or a.* != was;
        }
        return grew;
    }
};

/// Index one folio. Costs one pass over the names and a handful over the
/// productions; a query compiled afterwards pays neither.
pub fn of(gpa: std.mem.Allocator, f: *const folio.Folio) Error!Lemma {
    const symbols = f.symbolCount();
    const aliases = f.aliasCount();
    const renamed = try gpa.alloc(u32, aliases);
    @memset(renamed, none);
    errdefer gpa.free(renamed);
    // Every symbol lands in exactly one entry's run, except the invented ones
    // the loop below skips - so this is an upper bound and the tail goes unused.
    const members = try gpa.alloc(u32, symbols);
    var l: Lemma = .{
        .gpa = gpa,
        .f = f,
        .members = members,
        .renamed = renamed,
        .kids = try .init(gpa, symbols, symbols),
        .fields = try .init(gpa, symbols, f.fieldCount()),
        .renames = try .init(gpa, symbols, aliases),
        .passes = 0,
    };
    errdefer l.deinit();

    // Count, then fill. Two passes over the symbols so the runs can be windows
    // onto one array: a list per name would be one allocation per spelling and
    // this is built once per grammar for every query compiled against it.
    try l.by_name.ensureTotalCapacity(gpa, symbols);
    for (0..symbols) |i| {
        const sym: u32 = @intCast(i);
        const sort = sortOfSymbol(f, sym) orelse continue;
        const slot = l.by_name.getOrPutAssumeCapacity(f.nameOf(sym));
        if (!slot.found_existing) slot.value_ptr.* = .{};
        slot.value_ptr.slot(sort).len += 1;
    }
    {
        var at: u32 = 0;
        var it = l.by_name.valueIterator();
        while (it.next()) |e| {
            inline for (@typeInfo(Sort).@"enum".fields) |fl| {
                const run = e.slot(@enumFromInt(fl.value));
                run.off = at;
                at += run.len;
                // Rewound so the fill below can use it as a cursor and land
                // back on the true length.
                run.len = 0;
            }
        }
    }
    for (0..symbols) |i| {
        const sym: u32 = @intCast(i);
        const sort = sortOfSymbol(f, sym) orelse continue;
        const run = l.by_name.getPtr(f.nameOf(sym)).?.slot(sort);
        l.members[run.off + run.len] = sym;
        run.len += 1;
    }

    try l.renames_by_name.ensureTotalCapacity(gpa, aliases);
    for (0..aliases) |i| {
        const a = f.aliasOf(@intCast(i));
        const slot = l.renames_by_name.getOrPutAssumeCapacity(a.name);
        if (!slot.found_existing) slot.value_ptr.* = .{};
        if (a.named) {
            if (slot.value_ptr.named == none) slot.value_ptr.named = @intCast(i);
        } else if (slot.value_ptr.anonymous == none) {
            slot.value_ptr.anonymous = @intCast(i);
        }
    }

    try l.fields_by_name.ensureTotalCapacity(gpa, f.fieldCount());
    for (0..f.fieldCount()) |i| {
        l.fields_by_name.putAssumeCapacity(f.fieldOf(@intCast(i)), @intCast(i));
    }

    l.passes = close(f, &l);
    return l;
}

/// Which population a symbol answers questions in, or null for one that answers
/// none. `invented` is the press's own bookkeeping and has no name an author
/// could have written.
fn sortOfSymbol(f: *const folio.Folio, sym: u32) ?Sort {
    return switch (f.shapeOf(sym)) {
        .named => .kind,
        .anonymous => .literal,
        // A supertype is hidden, and so is every rule the author started with
        // an underscore. Both are askable-about by name and neither appears in
        // a tree, which is one population as far as a query is concerned.
        .hidden => .category,
        .invented => null,
    };
}

/// The one fixed point: who can hold whom, and who can carry which field.
///
/// A visible right-hand symbol is a child. A hidden or invented one is a hole
/// the tree never shows, so whoever spliced it inherits everything it holds -
/// which is a self-referential definition wherever the grammar recurses, hence
/// the iteration rather than a single walk.
///
/// A renamed step contributes to BOTH spaces: the rename to `renames`, because
/// that is what the tree will say, and the symbol to `kids` anyway, because a
/// rename applies at one step and the same symbol usually appears unrenamed
/// elsewhere. Erring toward admitting is the right direction here - this feeds
/// a "can never match" claim, and a claim like that has to be certain.
fn close(f: *const folio.Folio, l: *Lemma) u32 {
    // Which symbol each rename stands for, and whether that is unambiguous.
    // One pass: it is a fact about the productions and not a fixed point.
    for (0..f.productions().len) |i| {
        const rhs = f.rhsOf(@intCast(i));
        const steps = f.stepsOf(@intCast(i));
        for (rhs, 0..) |sym, at| {
            const a = f.stepAt(steps.at(@intCast(at))).alias;
            if (a == none) continue;
            // `none` is "nothing yet"; a second, different symbol poisons it to
            // the symbol count, which `beneath` reads back as ambiguous because
            // it is not a symbol either.
            l.renamed[a] = if (l.renamed[a] == none or l.renamed[a] == sym)
                sym
            else
                f.symbolCount();
        }
    }
    for (l.renamed) |*slot| {
        if (slot.* == f.symbolCount()) slot.* = none;
    }

    var passes: u32 = 0;
    while (true) {
        passes += 1;
        var moved = false;
        for (f.productions(), 0..) |prod, i| {
            const rhs = f.rhsOf(@intCast(i));
            const steps = f.stepsOf(@intCast(i));
            for (rhs, 0..) |sym, at| {
                const step = f.stepAt(steps.at(@intCast(at)));
                if (step.field != none) moved = l.fields.set(prod.lhs, step.field) or moved;
                if (step.alias != none) moved = l.renames.set(prod.lhs, step.alias) or moved;
                switch (f.shapeOf(sym)) {
                    .named, .anonymous => moved = l.kids.set(prod.lhs, sym) or moved,
                    .hidden, .invented => {
                        moved = l.kids.absorb(prod.lhs, sym) or moved;
                        moved = l.fields.absorb(prod.lhs, sym) or moved;
                        moved = l.renames.absorb(prod.lhs, sym) or moved;
                    },
                }
            }
        }
        if (!moved) return passes;
    }
}
