//! The grammar IR — what every front end lowers to, and the only thing the LR
//! builder reads.
//!
//! Deliberately smaller than a tree-sitter grammar. EBNF is already normalized
//! away (a `REPEAT` is an auxiliary nonterminal, a nested `CHOICE` is either
//! distributed or hoisted) and every symbol is an integer. What survives is the
//! part an LR construction can consume: a symbol table, a flat production list,
//! and the precedence needed to break a shift/reduce tie.
//!
//! Two things ride along that the LR construction never reads, and they are
//! here because *nothing downstream can recover them*. A parse is a sequence of
//! folds; a tree is what those folds are called. `Shape` says whether a symbol
//! appears in the tree at all and whether it counts as named, and a `Step`'s
//! `alias` and `field` say what one particular child is called at one
//! particular use site. Every `highlights.scm` in the world is keyed on those
//! names, so getting them byte-identical to tree-sitter is the whole point of
//! reading tree-sitter's grammars in the first place.
//!
//! Symbols are one id space with terminals first. That ordering is not
//! cosmetic: an LR action table is indexed by terminal, a goto table by
//! nonterminal, and keeping each contiguous means both are dense slices rather
//! than maps.

const std = @import("std");

/// An index into `Grammar.names`. Terminals occupy `[0, terminal_count)` and
/// nonterminals the rest, so `isTerminal` is a comparison rather than a lookup.
///
/// It is also hashed by its bytes - `dedup` below over a right-hand side, and
/// `joint/cursor.zig`'s tread check over the symbols standing above a limb -
/// while being compared field-wise, so it owes every byte of itself to a field.
/// A bare integer does, which is why the assertion reads as trivial today; it
/// is here because widening this to a struct is a two-line edit that would make
/// two identical right-hand sides hash differently and stop deduplicating.
pub const Symbol = u32;

comptime {
    if (!std.meta.hasUniqueRepresentation(Symbol)) @compileError(
        "grammar.Symbol is hashed by its bytes, so every byte of it has to" ++
            " belong to a field. See `folio/leaf.zig`'s `seamless` for the" ++
            " same law over the records that reach disk.",
    );
}

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

/// The lexical facts about a terminal that are not its pattern: *where* it may
/// begin and *who wins* when two terminals both match here. Both are decisions
/// the grammar author made and neither is recoverable from the pattern.
pub const Lexis = struct {
    /// `token.immediate`: legal only at the offset the previous token ended,
    /// with no extra in between. Dropping this is not a cosmetic loss —
    /// tree-sitter-json's string body is immediate, and without the constraint
    /// the grammar's own `//` comment extra starts inside a string literal.
    immediate: bool = false,
    /// `token(prec(n, …))`. Ranks the slate rather than one production: a
    /// higher-precedence terminal that matches here wins over a lower one *even
    /// when the lower one reaches further*, which is the only way a two-byte
    /// string body beats a comment that runs to end of line.
    prec: i32 = 0,
};

/// How strongly a step binds. Three cases, not one number, because the third is
/// not reducible to the first two: a *name* is ordered against other names and
/// against whole rules by a table the author wrote, and that order is partial.
/// JavaScript ranks `update_expression` above `arrow_function` and says nothing
/// about either against `declaration`; flattening those into integers invents
/// comparisons the author refused to make.
pub const Prec = union(enum) {
    /// Nothing declared. Distinct from `level = 0`, which is a rank: a declared
    /// zero outranks nothing but still *ties* deliberately, and the difference
    /// decides whether associativity gets consulted at all.
    none,
    level: i32,
    /// An index into `Grammar.prec_names`.
    name: u32,

    pub fn eql(a: Prec, b: Prec) bool {
        return switch (a) {
            .none => b == .none,
            .level => |x| b == .level and b.level == x,
            .name => |x| b == .name and b.name == x,
        };
    }
};

/// One entry in a declared precedence ordering: either a named precedence or a
/// rule. Rules appear because an author's real question is often "does a
/// `member_expression` bind tighter than an `arrow_function`", and neither of
/// those is a `prec` name.
pub const Rank = union(enum) { name: u32, symbol: Symbol };

/// Where a symbol stands in the tree the parse is *for*. Four cases and not two
/// booleans, because the pair that reads "invisible" has to say which kind of
/// invisible it is: a rule the author hid is a name somebody can still write a
/// query against and reason about, and a nonterminal the front end invented to
/// normalize EBNF is a name nobody outside this package has ever seen.
///
/// These are tree-sitter's `Named` / `Anonymous` / `Hidden` / `Auxiliary`, and
/// they have to stay that way: the flags it renders into `ts_symbol_metadata`
/// are `visible = named or anonymous` and `named = named or hidden`.
pub const Shape = enum {
    /// A rule the author wrote and did not hide: `(binary_expression …)`.
    named,
    /// A bare string in a rule body. It appears in the tree, spelled as itself
    /// — `("+")` — and no query can match it by rule name because it has none.
    anonymous,
    /// The author hid it: a leading underscore, or a `supertypes` entry. It
    /// does not appear, and its children splice into its parent.
    hidden,
    /// We invented it — a repeat helper, a hoisted choice, the augmented start.
    /// Also spliced, and distinct from `hidden` because the author never wrote
    /// the name, so nothing outside this package may be keyed on it.
    invented,

    /// Whether a node is emitted for this symbol at all. The complement splices
    /// its children into its parent instead.
    pub fn visible(s: Shape) bool {
        return s == .named or s == .anonymous;
    }
};

/// One `alias(rule, name)`: the node name a child wears at the one use site
/// that renamed it, plus whether that name counts as named.
///
/// A rename is a property of the *use site*, never of the symbol. C aliases
/// `_old_style_function_definition` to `function_definition` where it appears
/// and leaves it hidden everywhere else, and TypeScript spells `identifier`
/// three different ways depending on which rule reached it. Hang the rename on
/// the symbol and every one of those collapses into whichever site was read
/// last.
pub const Alias = struct { name: []const u8, named: bool };

/// One symbol of a right-hand side, with everything that is true of it *here*
/// rather than of the symbol generally: how strongly it binds, and what the
/// child it produces is called and filed under.
pub const Step = struct {
    prec: Prec = .none,
    assoc: Assoc = .none,
    /// Whether the rank above was **absorbed** rather than written here: it
    /// arrived inside a rule the press folded away, and it was authored for
    /// that rule's reading rather than for this production's.
    ///
    /// Provenance and not a rank, because the two questions have different
    /// answers and only one of them is on the step today. `variable_lvalue` is
    /// `prec.left(37, …)` and reaches `_identifier` through
    /// `hierarchical_identifier`, itself `prec.left(0, …)`; after the fold both
    /// it and `clockvar` carry `left(0)` on that step and nothing distinguishes
    /// the rank `clockvar` inherited from one its author chose. Rung 3 then
    /// folds on a side nobody wrote for this reading and deletes the `[`.
    ///
    /// Set only by `fold.zig::expand`, which is the only place two authors ever
    /// meet on one step - a body the author wrote is authored by definition -
    /// and only when `region` says the fold had a region to break. A rank whose
    /// author drew it around exactly this one step arrives intact however many
    /// rules it travels through, so absorbing it would refuse a statement that
    /// is still true here; `region` is what tells those two apart.
    ///
    /// **Press-only, like the two ranks it describes.** `leaf.StepRecord`
    /// carries `alias` and `field` and nothing else, because a folio holds the
    /// table rather than the argument that built it; see `bind.zig`. `impose`'s
    /// ledger names this field anyway, so its absence from the file is a
    /// decision on the record instead of one nobody noticed.
    spliced: bool = false,
    /// How many steps the author drew `prec`/`assoc` around, counted where they
    /// wrote it and never recounted after. `0` means nobody measured it.
    ///
    /// The number a fold needs and the only one it cannot work out for itself. A
    /// rank is a statement about a *region* of a body, and what a fold costs is
    /// the region: the steps that shared it end up spread across a host that
    /// never made the statement, so the rank arrives ordering pairs its author
    /// was not talking about. A region of exactly one step has nothing to lose,
    /// and rust's `_non_special_token` is that case - one of its alternatives is
    /// the whole of `prec.right(0, repeat1(punct))`, so the step carrying the
    /// rank *is* the thing ranked and inlining moves the statement intact.
    ///
    /// Recorded at import because it cannot be recovered later. Normalization
    /// runs to a fixpoint, so by the round that folds a rule away, a region of
    /// three steps may have been collapsed into one by earlier rounds - and a
    /// fold reading the body in front of it then cannot tell rust's genuinely
    /// single-step region from the residue of verilog's `prec.left(0, seq(…))`.
    /// Measured on 2026-08-07: deciding this at fold time from the live body
    /// takes rust and scala to zero residual and reads verilog's `c[i] <= 0;` as
    /// a `clocking_drive`, which is the whole defect `spliced` exists to avoid.
    /// `research/press/RESULT-2-splice.md` has that measurement.
    ///
    /// **Press-only**, like the two ranks it measures and the provenance above
    /// it; see `impose.zig`'s roster. Unmeasured reads as wide rather than
    /// narrow everywhere it is consulted, so a step this never reached keeps the
    /// conservative answer instead of inheriting a claim nobody made.
    ///
    /// The one field of this type that is **not** part of a production's
    /// identity, in either `dedup`'s key or `spread.bodyKey`, because it is spent
    /// inside the round that reads it and describes the author's syntax rather
    /// than the language the body derives. Both of those say why where they
    /// decline it.
    region: u32 = 0,
    /// Which `Grammar.aliases` entry renames this step's child, if any.
    alias: ?u32 = null,
    /// Which `Grammar.field_names` entry this step's child is filed under, if
    /// any. `field` and `alias` are independent: `field('name', alias($.x,
    /// 'y'))` sets both, and either alone is common.
    field: ?u32 = null,
};

pub const Production = struct {
    lhs: Symbol,
    rhs: []const Symbol,
    /// Parallel to `rhs`, one entry per symbol.
    ///
    /// Per *step*, not per production, because that is where an author puts it
    /// and because nothing coarser survives normalization. `prec.left(2, seq(a,
    /// b))` inside a longer body ranks only the part it wraps, and a production
    /// with one precedence has to pick a winner between the wrapped part and the
    /// rest — which is how `_non_special_token`'s `prec.right(0, repeat1(punct))`
    /// lost its associativity the moment the rule was inlined into its users,
    /// and took 176 of Rust's cells with it.
    steps: []const Step,
    /// What `prec.dynamic` declared, and the one rank that is per *production*
    /// rather than per step.
    ///
    /// It answers a different question from `Step.prec` and must never be
    /// confused with it. A static rank resolves a cell while the table is being
    /// built, so the loser is gone before a parse begins. A dynamic one
    /// resolves nothing: the cell keeps both actions, the parse forks, and this
    /// is the tie-break between readings that are all still alive at the end.
    ///
    /// So `settle` may *order* by it and must never resolve by it. It does the
    /// first - a declared tie names the higher-ranked reading as the fork's
    /// primary, since the parse tries the primary first - and an earlier attempt
    /// at the second cost 7221 residual conflicts on c. The rest of the job is
    /// the fork's: tree-sitter compares the *sum* over each candidate subtree,
    /// which no table can know because the subtrees do not exist yet.
    dynamic: i16 = 0,

    pub fn isEpsilon(p: Production) bool {
        return p.rhs.len == 0;
    }

    /// The step a dot has just consumed — whose precedence is the reading's
    /// precedence, for a fold at the end and for a shift in the middle alike. A
    /// dot that has consumed nothing is not an interpretation of anything and
    /// carries nothing.
    pub fn consumed(p: Production, dot: usize) Step {
        return if (dot == 0) .{} else p.steps[dot - 1];
    }
};

/// A parsed, normalized grammar. Owns every slice it hands out through an
/// arena, so a caller may drop the source JSON the instant this returns.
pub const Grammar = struct {
    arena: std.heap.ArenaAllocator,
    name: []const u8,

    names: []const []const u8,
    patterns: []const ?Pattern,
    /// Per terminal, the lexical facts that are not its pattern. Nonterminals
    /// carry the default, which says nothing.
    lexis: []const Lexis,
    /// Per symbol, where it stands in the tree. Total over the symbol space,
    /// so a tree builder sweeping a right-hand side never branches on which
    /// half of the id space it is looking at.
    shapes: []const Shape,
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
    /// For a nonterminal the front end *synthesized* — a repeat helper, a
    /// hoisted choice — the rule it was synthesized for. Every other symbol
    /// owns itself.
    ///
    /// This is what makes a conflict attributable. Two helpers of one rule
    /// disagreeing is that rule's own ambiguity and usually its intended one; a
    /// helper disagreeing with a different rule is a real conflict wearing a
    /// generated name. Without the attribution both look identical, and the
    /// first class is large enough to bury the second.
    owner: []const Symbol,
    /// Rule-name groups the grammar author declared ambiguous, each sorted so
    /// a measured group can be compared against them by bytes.
    declared_conflicts: []const []const Symbol,
    /// The `supertypes` block: hidden rules the author declared to be the
    /// abstract category their alternatives belong to — `expression`,
    /// `statement`, `_declarator`. Sorted, so membership is a binary search.
    ///
    /// Being listed here is *why* several of them are hidden at all: C names
    /// `expression` without a leading underscore and it still never appears in
    /// a tree, because tree-sitter hides every supertype on the way in. What
    /// the list adds beyond that is the grouping, which is what lets a consumer
    /// answer "is this node some kind of expression" without enumerating the
    /// eighty rules that are.
    supertypes: []const Symbol,
    /// Every distinct `alias(rule, name)` in the grammar. A `Step.alias` is an
    /// index in here rather than a string, so comparing two steps — which the
    /// production deduplicator and the auxiliary-sharing cache both do on every
    /// production — stays an integer compare.
    aliases: []const Alias,
    /// Every distinct `field(name, rule)` name, indexed by `Step.field`.
    field_names: []const []const u8,
    /// The names a `Prec.name` indexes.
    prec_names: []const []const u8,
    /// Declared orderings, each a list running from weakest to strongest. Two
    /// entries compare only when one list holds both; the relation is
    /// deliberately partial, and a grammar with no `precedences` block has none
    /// at all.
    orderings: []const []const Rank,
    /// Terminals whose pattern we could not render. A non-empty list means any
    /// lexing result over this grammar is incomplete, and every consumer is
    /// required to surface that rather than quietly mis-tokenize.
    externals: []const Symbol,
    /// The terminal a keyword is spelled as before anyone knows it is a keyword
    /// — tree-sitter's `word`, almost always `identifier`.
    ///
    /// It exists because longest-match cannot decide `int` in C. Both
    /// `primitive_type` and `identifier` match those three bytes at that offset,
    /// and no fact about either pattern breaks the tie. The author's answer is
    /// this rule: scan the word, then look the bytes up among the terminals that
    /// are literals, and prefer the keyword when one matches exactly. Without it
    /// a lexer either mis-tokenizes every keyword or needs one hand-written
    /// tie-break per language.
    word: ?Symbol,
    /// This grammar's terminal slate, already determinized, when it arrived
    /// from an artifact that carried one. Opaque here and everywhere but
    /// `kernel/lex/lexicon.zig`, which is the only thing that reads it.
    ///
    /// A grammar imported from source has none, and a scanner built over one
    /// determinizes as it always did - so this is a shortcut a grammar may
    /// carry, never a thing a grammar needs.
    lexicon: []const u8 = &.{},

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

    /// How a terminal lexes beyond its pattern. Total over the symbol space so
    /// a caller sweeping every symbol never has to branch on which half it is.
    pub fn lexisOf(g: *const Grammar, s: Symbol) Lexis {
        return g.lexis[s];
    }

    pub fn nameOf(g: *const Grammar, s: Symbol) []const u8 {
        return g.names[s];
    }

    /// Where a symbol stands in the tree, before any use site renames it.
    pub fn shapeOf(g: *const Grammar, s: Symbol) Shape {
        return g.shapes[s];
    }

    /// The rename in force at one step, if it has one. An aliased step outranks
    /// its symbol's own shape: `alias($._hidden, 'name')` emits a node even
    /// though the symbol is spliced everywhere else.
    pub fn aliasOf(g: *const Grammar, step: Step) ?Alias {
        return if (step.alias) |i| g.aliases[i] else null;
    }

    /// The field one step's child is filed under, if any.
    pub fn fieldOf(g: *const Grammar, step: Step) ?[]const u8 {
        return if (step.field) |i| g.field_names[i] else null;
    }

    /// Whether the author declared this symbol an abstract category over its
    /// own alternatives.
    pub fn isSupertype(g: *const Grammar, s: Symbol) bool {
        return std.sort.binarySearch(Symbol, g.supertypes, s, order) != null;
    }

    fn order(needle: Symbol, item: Symbol) std.math.Order {
        return std.math.order(needle, item);
    }

    /// The productions of a nonterminal. Empty for a terminal, which is what a
    /// closure over a mixed symbol wants rather than an error.
    pub fn productionsOf(g: *const Grammar, s: Symbol) []const u32 {
        if (g.isTerminal(s)) return &.{};
        return g.by_lhs[s - g.terminal_count];
    }

    /// Whether the front end invented this symbol *on some rule's behalf*.
    /// Narrower than `shapeOf(s) == .invented`, and deliberately: this asks
    /// who to blame for a conflict, so it is false for machinery nobody can be
    /// blamed for — the augmented start, or a helper shared so widely that no
    /// one rule owns it.
    pub fn isSynthetic(g: *const Grammar, s: Symbol) bool {
        return g.owner[s] != s;
    }

    /// Which of two readings binds tighter, given the rules each speaks for.
    ///
    /// Two ranks and one relation, and they do not mix. Numbers compare as
    /// numbers, against each other and against the absent precedence, which
    /// counts as zero — but only when one of them is non-zero, so a declared
    /// `prec(0, …)` and an undeclared step stay *equal* and fall through to
    /// associativity rather than being ordered by a difference nobody wrote.
    ///
    /// Everything else is settled by the author's own lists, and only by them.
    /// A list ranks its entries strongest-first, an entry is either a
    /// precedence name or a rule, and two readings compare exactly when one
    /// list holds both — the first such list decides. No list, or no list
    /// holding both: equal, which is the honest answer. The relation is
    /// deliberately partial, and inventing a total order over it (by interning
    /// names to integers, say) manufactures verdicts the author declined to
    /// give, which is how a shift/reduce cell gets resolved the wrong way and
    /// the grammar quietly parses a different language.
    ///
    /// `l_rules` and `r_rules` are the nonterminals each side is building: one
    /// for a read, the set of surviving folds for a fold. They are what a
    /// `Rank.symbol` entry matches against.
    pub fn compare(
        g: *const Grammar,
        l: Prec,
        l_rules: []const Symbol,
        r: Prec,
        r_rules: []const Symbol,
    ) std.math.Order {
        switch (l) {
            .level => |x| switch (r) {
                .level => |y| if (x != 0 or y != 0) return std.math.order(x, y),
                .none => if (x != 0) return std.math.order(x, 0),
                else => {},
            },
            .none => if (r == .level and r.level != 0) return std.math.order(0, r.level),
            else => {},
        }

        for (g.orderings) |list| {
            var saw_l = false;
            var saw_r = false;
            for (list) |entry| {
                if (g.ranks(entry, l, l_rules)) {
                    saw_l = true;
                    if (saw_r) return .lt;
                } else if (g.ranks(entry, r, r_rules)) {
                    saw_r = true;
                    if (saw_l) return .gt;
                }
            }
        }
        return .eq;
    }

    /// Whether an ordering entry is talking about this reading.
    fn ranks(_: *const Grammar, entry: Rank, p: Prec, rules: []const Symbol) bool {
        return switch (entry) {
            .name => |n| p == .name and p.name == n,
            .symbol => |s| std.mem.indexOfScalar(Symbol, rules, s) != null,
        };
    }

    /// Whether `group` is one of the ambiguities the grammar author declared.
    /// `group` must be sorted and deduplicated, as the declared groups are.
    pub fn declared(g: *const Grammar, group: []const Symbol) bool {
        for (g.declared_conflicts) |d| {
            if (std.mem.eql(Symbol, d, group)) return true;
        }
        return false;
    }

    /// Nonterminals that a right-hand side still names and that derive no
    /// terminal string. Every production mentioning one is weight the tables
    /// will carry and no input can ever reach, so in an imported grammar this
    /// is a report on the front end rather than on the language.
    ///
    /// Both halves of that sentence are load-bearing, and each is easy to drop:
    ///
    ///   - **Derives nothing** is not "has no productions". `loop -> loop x`
    ///     has a production and still never bottoms out, so the answer needs
    ///     the productivity fixpoint below rather than a length check. It is
    ///     also not "FIRST is empty" — see the header of `first.zig`, whose
    ///     FIRST is the optimistic one and stays inhabited here.
    ///   - **Referenced** is what separates a defect from the fold working. A
    ///     rule `fold.nonterminals` substituted away has no productions left
    ///     and nothing mentions it, which is success, not damage.
    ///
    /// Caller owns the returned slice.
    pub fn barren(g: *const Grammar, gpa: std.mem.Allocator) ![]Symbol {
        // A production makes its left-hand side productive once every symbol on
        // its right-hand side is, so the fixpoint only ever adds and settles in
        // at most as many rounds as there are nonterminals.
        const yields = try gpa.alloc(bool, g.symbolCount());
        defer gpa.free(yields);
        @memset(yields, false);
        @memset(yields[0..g.terminal_count], true);
        var changed = true;
        while (changed) {
            changed = false;
            for (g.productions) |p| {
                if (yields[p.lhs]) continue;
                for (p.rhs) |s| {
                    if (!yields[s]) break;
                } else {
                    yields[p.lhs] = true;
                    changed = true;
                }
            }
        }

        var out: std.ArrayList(Symbol) = .empty;
        errdefer out.deinit(gpa);
        var listed = try gpa.alloc(bool, g.symbolCount());
        defer gpa.free(listed);
        @memset(listed, false);
        for (g.productions) |p| for (p.rhs) |s| {
            if (yields[s] or listed[s]) continue;
            listed[s] = true;
            try out.append(gpa, s);
        };
        std.mem.sort(Symbol, out.items, {}, std.sort.asc(Symbol));
        return out.toOwnedSlice(gpa);
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
    prec_names: std.ArrayList([]const u8) = .empty,
    orderings: std.ArrayList([]const Rank) = .empty,
    aliases: std.ArrayList(Alias) = .empty,
    field_names: std.ArrayList([]const u8) = .empty,
    /// Still-biased symbols the front end declared supertypes.
    supertypes: std.ArrayList(u32) = .empty,
    /// Interning key -> the *unresolved* symbol. Terminals are stored as their
    /// own index; nonterminals as `nonterminal_bias + index`, because the final
    /// terminal count is not known until the walk finishes.
    interned: std.StringHashMap(u32),
    /// The word terminal, still biased. A field rather than a `finish` parameter
    /// because a front end learns it wherever it likes — the key is at the top of
    /// `grammar.json` and the symbol it names is interned much later.
    word: ?u32 = null,

    const nonterminal_bias: u32 = 1 << 31;

    const Entry = struct {
        name: []const u8,
        pattern: ?Pattern,
        lexis: Lexis = .{},
        /// The still-biased symbol this one was synthesized for, or null when
        /// the front end read it from the source.
        owner: ?u32 = null,
        /// Where the symbol stands in the tree. A front end that knows says so
        /// with `shape`; one that does not gets the symbol taken at face value
        /// — a literal terminal is a bare string somebody typed in a rule body,
        /// and anything else is a rule with a name on it.
        shape: ?Shape = null,
    };

    /// Whether an *unresolved* symbol — one still carrying the builder's bias —
    /// landed in the terminal space. A front end asks this to decide whether a
    /// rule it already interned still needs its body expanded into productions.
    pub fn isTerminalRaw(s: u32) bool {
        return s < nonterminal_bias;
    }

    /// What an *unresolved* symbol is called, for a diagnostic raised before
    /// `finish` has a `Grammar` to ask `nameOf`. The bias stays private: a
    /// caller that had to strip it itself would be one rename away from
    /// indexing the wrong table.
    pub fn nameRaw(b: *const Builder, s: u32) []const u8 {
        const list = if (isTerminalRaw(s)) b.terminals else b.nonterminals;
        return list.items[s & ~nonterminal_bias].name;
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
        b.prec_names.deinit(b.gpa);
        b.orderings.deinit(b.gpa);
        b.aliases.deinit(b.gpa);
        b.field_names.deinit(b.gpa);
        b.supertypes.deinit(b.gpa);
        b.interned.deinit();
        b.arena.deinit();
    }

    pub fn dupe(b: *Builder, bytes: []const u8) ![]const u8 {
        return b.arena.allocator().dupe(u8, bytes);
    }

    /// The symbol already interned under `key`, if any.
    ///
    /// For a front end that wants to *share* a synthesized rule rather than
    /// build a second one with the same body: asking first means it never has to
    /// invent a name, or a set of productions, for something it may turn out
    /// already to have. `intern` alone cannot answer this, because answering it
    /// requires naming the thing.
    pub fn lookup(b: *const Builder, key: []const u8) ?u32 {
        return b.interned.get(key);
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

    /// Record how a terminal lexes beyond its pattern. A no-op on a
    /// nonterminal.
    ///
    /// `immediate` accumulates because a rule may reach an already-known token
    /// and add nothing; `prec` assigns, because the front end folds the
    /// standing into the intern key. Two spellings that rank differently are
    /// two terminals, so every sighting of one terminal reports the same rank
    /// and there is nothing to reconcile.
    ///
    /// It used to take `@max` against a slot that starts at zero, which reads
    /// every negative rank as no rank at all. Ruby ranks `comment` at -2 so
    /// that `#{` outranks it; clamped to zero it outranked nothing and a
    /// comment ate every interpolated string. Zero is `Lexis`'s spelling for
    /// "unranked", so it cannot also be the floor of a comparison.
    pub fn describe(b: *Builder, raw: u32, lx: Lexis) void {
        if (!isTerminalRaw(raw)) return;
        const slot = &b.terminals.items[raw].lexis;
        slot.immediate = slot.immediate or lx.immediate;
        slot.prec = lx.prec;
    }

    /// Record that `raw` is machinery the front end invented while lowering
    /// `owner`, so a conflict involving it can be reported against the rule the
    /// author actually wrote. Ignored for a terminal, which is never synthesized
    /// on a rule's behalf.
    pub fn ascribe(b: *Builder, raw: u32, owner: u32) void {
        if (isTerminalRaw(raw)) return;
        b.nonterminals.items[raw - nonterminal_bias].owner = owner;
    }

    /// A still-biased symbol's own record, whichever space it landed in.
    fn record(b: *Builder, raw: u32) *Entry {
        return if (isTerminalRaw(raw))
            &b.terminals.items[raw]
        else
            &b.nonterminals.items[raw - nonterminal_bias];
    }

    /// Record where a symbol stands in the tree. Assigning rather than
    /// accumulating, unlike `describe`: the same anonymous literal reached
    /// through two rules is the same bare string both times, so a second
    /// sighting can only ever say what the first one did.
    pub fn shape(b: *Builder, raw: u32, s: Shape) void {
        b.record(raw).shape = s;
    }

    /// Declare a symbol an abstract category over its own alternatives, which
    /// is also what hides it. The front end still calls `shape` — the two facts
    /// travel together in `grammar.json` and are separate questions here,
    /// because a rule can be hidden without being anybody's supertype.
    pub fn elevate(b: *Builder, raw: u32) !void {
        try b.supertypes.append(b.gpa, raw);
    }

    /// Intern a precedence name, so a `Prec.name` is an integer everywhere
    /// downstream and the strings are compared once, here.
    pub fn internPrec(b: *Builder, name: []const u8) !u32 {
        for (b.prec_names.items, 0..) |n, i| {
            if (std.mem.eql(u8, n, name)) return @intCast(i);
        }
        try b.prec_names.append(b.gpa, try b.dupe(name));
        return @intCast(b.prec_names.items.len - 1);
    }

    /// Intern a rename, so a `Step.alias` is an integer. Linear, like
    /// `internPrec`, and for the same reason: a real grammar declares a couple
    /// of hundred of these against tens of thousands of steps, so the table is
    /// built once and read forever.
    pub fn internAlias(b: *Builder, name: []const u8, is_named: bool) !u32 {
        for (b.aliases.items, 0..) |a, i| {
            if (a.named == is_named and std.mem.eql(u8, a.name, name)) return @intCast(i);
        }
        try b.aliases.append(b.gpa, .{ .name = try b.dupe(name), .named = is_named });
        return @intCast(b.aliases.items.len - 1);
    }

    /// Intern a field name, so a `Step.field` is an integer.
    pub fn internField(b: *Builder, name: []const u8) !u32 {
        for (b.field_names.items, 0..) |n, i| {
            if (std.mem.eql(u8, n, name)) return @intCast(i);
        }
        try b.field_names.append(b.gpa, try b.dupe(name));
        return @intCast(b.field_names.items.len - 1);
    }

    /// Declare one ordering, strongest first. Entries naming a rule still carry
    /// the builder's bias and are resolved in `finish`.
    pub fn addOrdering(b: *Builder, list: []const Rank) !void {
        try b.orderings.append(b.gpa, try b.arena.allocator().dupe(Rank, list));
    }

    /// `steps` is parallel to `rhs`; an empty slice means every step is plain,
    /// which is what most productions are and what every test wants to write.
    pub fn addProduction(b: *Builder, lhs: u32, rhs: []const u32, steps: []const Step) !void {
        return b.addProductionDynamic(lhs, rhs, steps, 0);
    }

    /// `addProduction` for a body the author gave a runtime tie-break with
    /// `prec.dynamic`. A separate entry point rather than a fourth parameter
    /// because only the front end has one to declare, and every other caller
    /// would have to write the zero.
    pub fn addProductionDynamic(
        b: *Builder,
        lhs: u32,
        rhs: []const u32,
        steps: []const Step,
        dynamic: i16,
    ) !void {
        const a = b.arena.allocator();
        std.debug.assert(steps.len == 0 or steps.len == rhs.len);
        const owned = if (steps.len == rhs.len)
            try a.dupe(Step, steps)
        else blk: {
            const flat = try a.alloc(Step, rhs.len);
            @memset(flat, .{});
            break :blk flat;
        };
        try b.productions.append(b.gpa, .{
            .lhs = lhs,
            .rhs = try a.dupe(u32, rhs),
            .steps = owned,
            .dynamic = dynamic,
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
        const lexis = try a.alloc(Lexis, total);
        const shapes = try a.alloc(Shape, total);
        @memset(lexis, .{});
        for (b.terminals.items, 0..) |e, i| {
            names[i] = e.name;
            patterns[i] = e.pattern;
            lexis[i] = e.lexis;
            shapes[i] = e.shape orelse
                if (e.pattern != null and e.pattern.? == .literal) .anonymous else .named;
        }
        for (b.nonterminals.items, 0..) |e, i| {
            names[tcount + i] = e.name;
            patterns[tcount + i] = null;
            shapes[tcount + i] = e.shape orelse .named;
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
        try dedup(b);

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
            // Sorted here rather than at every comparison: a declared group is
            // a set, it is compared against a measured set thousands of times,
            // and both being sorted makes that comparison a memcmp.
            std.mem.sort(Symbol, g, {}, std.sort.asc(Symbol));
            slot.* = g;
        }

        const supertypes = try a.alloc(Symbol, b.supertypes.items.len);
        for (supertypes, b.supertypes.items) |*slot, raw| slot.* = resolve(raw, tcount);
        std.mem.sort(Symbol, supertypes, {}, std.sort.asc(Symbol));

        const orderings = try a.alloc([]const Rank, b.orderings.items.len);
        for (orderings, b.orderings.items) |*slot, list| {
            const cut = try a.alloc(Rank, list.len);
            for (cut, list) |*r, entry| {
                r.* = switch (entry) {
                    .name => entry,
                    .symbol => |s| .{ .symbol = resolve(s, tcount) },
                };
            }
            slot.* = cut;
        }

        const owner = try a.alloc(Symbol, total);
        for (owner, 0..) |*slot, i| slot.* = @intCast(i);
        for (b.nonterminals.items, 0..) |e, i| {
            if (e.owner) |raw| owner[tcount + i] = resolve(raw, tcount);
        }
        // Flatten, so machinery synthesized while lowering other machinery still
        // reports against the rule at the end of the chain. Bounded rather than
        // recursive because nothing here guarantees a front end kept it acyclic.
        for (owner) |*slot| {
            var hops: usize = 0;
            while (owner[slot.*] != slot.* and hops <= total) : (hops += 1) slot.* = owner[slot.*];
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
            .lexis = lexis,
            .shapes = shapes,
            .terminal_count = tcount,
            .productions = try a.dupe(Production, b.productions.items),
            .by_lhs = by_lhs,
            .start = resolve(start, tcount),
            .extras = resolved_extras,
            .owner = owner,
            .declared_conflicts = resolved_conflicts,
            .supertypes = supertypes,
            .aliases = try a.dupe(Alias, b.aliases.items),
            .field_names = try a.dupe([]const u8, b.field_names.items),
            .prec_names = try a.dupe([]const u8, b.prec_names.items),
            .orderings = orderings,
            .externals = try externals.toOwnedSlice(a),
            // A word rule that resolved into the nonterminal space is not a
            // word rule; the key named something that is not a token, and
            // keyword extraction over it would be nonsense rather than an
            // approximation.
            .word = if (b.word) |raw| blk: {
                const s = resolve(raw, tcount);
                break :blk if (s < tcount) s else null;
            } else null,
        };
        g.arena = b.arena;
        b.arena = std.heap.ArenaAllocator.init(b.gpa);
        b.terminals.clearAndFree(b.gpa);
        b.nonterminals.clearAndFree(b.gpa);
        b.productions.clearAndFree(b.gpa);
        b.prec_names.clearAndFree(b.gpa);
        b.orderings.clearAndFree(b.gpa);
        b.aliases.clearAndFree(b.gpa);
        b.field_names.clearAndFree(b.gpa);
        b.supertypes.clearAndFree(b.gpa);
        b.interned.clearAndFree();
        b.word = null;
        return g;
    }
};

/// Drop every production a nonterminal already has, keeping the first.
///
/// Not an optimization — a correctness fix, and one that only shows up on real
/// grammars. Normalizing EBNF reaches the same body down two different paths
/// whenever optionals nest: Go's `parameter_list` wraps an optional list and an
/// optional trailing comma inside one outer optional, so "no list, no comma"
/// and "outer absent" both flatten to `( )`. Two identical productions are
/// indistinguishable to *any* parser — same body, same tree, nothing a
/// lookahead could ever separate — so every state where both complete is a
/// reduce/reduce conflict that no precedence can settle and that describes
/// nothing about the language. Fifty of Go's seventy-seven were this.
///
/// Order is preserved and the first copy wins, because production order is
/// load-bearing downstream: a tie on precedence is broken by taking the earlier
/// rule, which is the order the author wrote them in.
///
/// Precedence, associativity and shaping are all part of the identity. Two
/// same-bodied productions ranked differently are a statement about resolution,
/// not a duplicate, and collapsing them would silently pick one of the author's
/// two answers. Two ranked identically but naming different fields are two
/// different trees over one parse, and collapsing *those* silently picks one of
/// the author's two node shapes — which nothing downstream could ever notice,
/// because both parse the same sentences.
fn dedup(b: *Builder) !void {
    // `dynamic` is in the key because it is a statement about the reading, the
    // same as a step's precedence is: two identical bodies ranked differently are
    // two answers to which one a fork should prefer, and collapsing them keeps
    // whichever the author happened to write first. It fires on none of the
    // thirty pinned grammars - measured at zero collisions where the ranks
    // differ - so this changes no table anyone has pressed. It is here so that
    // the key stays a full account of what makes a production distinct, which is
    // the only property that keeps a deduplicator honest as the type grows.
    const Key = struct { lhs: Symbol, rhs: []const Symbol, steps: []const Step, dynamic: i16 };
    const Ctx = struct {
        pub fn hash(_: @This(), k: Key) u64 {
            var h = std.hash.Wyhash.init(k.lhs);
            h.update(std.mem.sliceAsBytes(k.rhs));
            h.update(std.mem.asBytes(&k.dynamic));
            for (k.steps) |s| {
                h.update(std.mem.asBytes(&std.meta.activeTag(s.prec)));
                h.update(std.mem.asBytes(&s.assoc));
                // Provenance is part of what makes two bodies distinct for the
                // same reason the rank is: one of them was ranked by its own
                // author and the other absorbed a rank on the way through a
                // fold, and rung 3 now answers them differently. `dedup` runs
                // *after* `fold`, so this is the round where the difference
                // exists to be collapsed.
                h.update(std.mem.asBytes(&s.spliced));
                // `region` is deliberately *not* here, and it is the one field of
                // `Step` that is not. It is read by exactly one caller, the fold
                // that sets the flag above, and `dedup` runs after that fold - so
                // by this point the only thing region decides has been decided and
                // recorded, and two bodies differing only in it are two bodies
                // nothing downstream can tell apart. See `spread.drawn`.
                // Flattened rather than hashed as optionals: an absent `?u32`
                // leaves its payload bytes undefined, and feeding those to a
                // hash is how a deduplicator starts giving different answers on
                // different runs.
                inline for (.{ s.alias, s.field }) |slot| {
                    const flat: u32 = slot orelse std.math.maxInt(u32);
                    h.update(std.mem.asBytes(&flat));
                }
                switch (s.prec) {
                    .none => {},
                    .level => |v| h.update(std.mem.asBytes(&v)),
                    .name => |v| h.update(std.mem.asBytes(&v)),
                }
            }
            return h.final();
        }
        pub fn eql(_: @This(), x: Key, y: Key) bool {
            if (x.lhs != y.lhs or x.dynamic != y.dynamic) return false;
            if (!std.mem.eql(Symbol, x.rhs, y.rhs)) return false;
            for (x.steps, y.steps) |a, c| {
                if (a.assoc != c.assoc or !a.prec.eql(c.prec)) return false;
                if (a.spliced != c.spliced) return false;
                if (a.alias != c.alias or a.field != c.field) return false;
            }
            return true;
        }
    };

    var seen: std.HashMapUnmanaged(Key, void, Ctx, std.hash_map.default_max_load_percentage) = .empty;
    defer seen.deinit(b.gpa);
    try seen.ensureTotalCapacity(b.gpa, @intCast(b.productions.items.len));

    var kept: usize = 0;
    for (b.productions.items) |p| {
        const key: Key = .{ .lhs = p.lhs, .rhs = p.rhs, .steps = p.steps, .dynamic = p.dynamic };
        if (seen.getOrPutAssumeCapacity(key).found_existing) continue;
        b.productions.items[kept] = p;
        kept += 1;
    }
    b.productions.shrinkRetainingCapacity(kept);
}

/// Finished-grammar symbol for a rule name. The builder hands back its own
/// unresolved ids, which do not survive `finish` — a test that holds one and
/// indexes with it reads a neighbouring symbol or panics.
fn named(g: *const Grammar, name: []const u8) Symbol {
    for (0..g.symbolCount()) |s| {
        if (std.mem.eql(u8, g.nameOf(@intCast(s)), name)) return @intCast(s);
    }
    unreachable;
}

test "the same body twice is one production, and a differently ranked one is not" {
    var b = Builder.init(std.testing.allocator);
    defer b.deinit();
    const x = try b.intern("x", "x", .{ .literal = "x" });
    const start = try b.intern("$start", "$start", null);
    const s = try b.intern("S", "S", null);
    try b.addProduction(start, &.{s}, &.{});
    // Two paths through nested optionals reaching the same body, as `optional`
    // normalization does on every real grammar.
    try b.addProduction(s, &.{x}, &.{});
    try b.addProduction(s, &.{x}, &.{});
    // Same body, different rank: a statement about resolution, not a copy.
    try b.addProduction(s, &.{x}, &.{.{ .prec = .{ .level = 3 } }});
    // Same body and rank, different side: likewise.
    try b.addProduction(s, &.{x}, &.{.{ .prec = .{ .level = 3 }, .assoc = .left }});

    var g = try b.finish("t", start, &.{}, &.{});
    defer g.deinit();

    const rules = g.productionsOf(named(&g, "S"));
    try std.testing.expectEqual(@as(usize, 3), rules.len);
    try std.testing.expect(g.productions[rules[0]].consumed(1).prec == .none);
    try std.testing.expectEqual(@as(i32, 3), g.productions[rules[1]].consumed(1).prec.level);
    try std.testing.expectEqual(Assoc.left, g.productions[rules[2]].consumed(1).assoc);
}

test "deduplication keeps the earlier copy, because production order breaks ties" {
    var b = Builder.init(std.testing.allocator);
    defer b.deinit();
    const x = try b.intern("x", "x", .{ .literal = "x" });
    const y = try b.intern("y", "y", .{ .literal = "y" });
    const start = try b.intern("$start", "$start", null);
    const s = try b.intern("S", "S", null);
    try b.addProduction(start, &.{s}, &.{});
    try b.addProduction(s, &.{ x, y }, &.{});
    try b.addProduction(s, &.{x}, &.{});
    try b.addProduction(s, &.{ x, y }, &.{});

    var g = try b.finish("t", start, &.{}, &.{});
    defer g.deinit();

    // The survivor sits where the *first* copy sat, so anything downstream that
    // reads "the earlier rule wins" still means the rule the author wrote first.
    const rules = g.productionsOf(named(&g, "S"));
    try std.testing.expectEqual(@as(usize, 2), rules.len);
    try std.testing.expectEqual(@as(usize, 2), g.productions[rules[0]].rhs.len);
    try std.testing.expectEqual(@as(usize, 1), g.productions[rules[1]].rhs.len);
}

test "deriving nothing is not the same as having no productions" {
    var b = Builder.init(std.testing.allocator);
    defer b.deinit();
    const x = try b.intern("x", "x", .{ .literal = "x" });
    const start = try b.intern("$start", "$start", null);
    const s = try b.intern("S", "S", null);
    const live = try b.intern("live", "live", null);
    const loop = try b.intern("loop", "loop", null);
    const gone = try b.intern("gone", "gone", null);
    try b.addProduction(start, &.{s}, &.{});
    try b.addProduction(s, &.{ live, loop }, &.{});
    try b.addProduction(live, &.{x}, &.{});
    // Productions, but no way out of them: `loop` only ever grows.
    try b.addProduction(loop, &.{ loop, x }, &.{});
    // Productive, and mentioned by nobody.
    try b.addProduction(gone, &.{x}, &.{});

    var g = try b.finish("t", start, &.{}, &.{});
    defer g.deinit();
    const dead = try g.barren(std.testing.allocator);
    defer std.testing.allocator.free(dead);

    // `loop` cannot bottom out, and it poisons `S`, whose only alternative
    // needs it. Both are named by a body, so both are on the report.
    try std.testing.expectEqualSlices(Symbol, &.{ named(&g, "S"), named(&g, "loop") }, dead);
    // `live` derives `x`. `gone` does too and nothing names it — neither half
    // of the question puts either on the list.
    for (dead) |d| try std.testing.expect(d != named(&g, "live") and d != named(&g, "gone"));
}

test "a folded rule is swept, not indicted" {
    var b = Builder.init(std.testing.allocator);
    defer b.deinit();
    const x = try b.intern("x", "x", .{ .literal = "x" });
    const start = try b.intern("$start", "$start", null);
    const top = try b.intern("top", "top", null);
    const alias = try b.intern("alias", "alias", null);
    try b.addProduction(start, &.{top}, &.{});
    try b.addProduction(top, &.{alias}, &.{});
    try b.addProduction(alias, &.{x}, &.{});
    _ = try @import("fold.zig").nonterminals(std.testing.allocator, &b, &.{start}, &.{alias});

    var g = try b.finish("t", start, &.{}, &.{});
    defer g.deinit();
    const dead = try g.barren(std.testing.allocator);
    defer std.testing.allocator.free(dead);

    // `alias` now has no productions at all — the naive test for a defect —
    // and is not one, because the fold is why it has none.
    try std.testing.expectEqual(@as(usize, 0), g.productionsOf(named(&g, "alias")).len);
    try std.testing.expectEqual(@as(usize, 0), dead.len);
}

test "builder interns each key once and separates the two symbol spaces" {
    var b = Builder.init(std.testing.allocator);
    defer b.deinit();

    const lit = try b.intern("str:if", "if", .{ .literal = "if" });
    const lit_again = try b.intern("str:if", "if", .{ .literal = "if" });
    const rule = try b.intern("rule:if", "if_statement", null);
    try std.testing.expectEqual(lit, lit_again);
    try std.testing.expect(lit != rule);

    const start = try b.intern("rule:$start", "$start", null);
    try b.addProduction(start, &.{rule}, &.{});
    try b.addProduction(rule, &.{lit}, &.{});

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
