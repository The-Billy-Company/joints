//! The tree-sitter front end: `grammar.json` in, grammar IR out.
//!
//! This is the whole go-to-market. Three hundred maintained grammars with their
//! highlight queries are person-decades of work that cannot be out-engineered,
//! and `grammar.json` is the declarative data file most of those repositories
//! already commit. So outliner does not ask anyone to rewrite a grammar; it
//! reads the one they have.
//!
//! This file is the door and the pass order; four siblings do the work, and the
//! seam between them is that one of them looks at a rule body and the rest look
//! at the grammar. `galley` holds the state all four write into and narrows the
//! JSON. `spelling` answers what a node lexes as and at what standing, which is
//! the one question both halves have to answer the same way. `muster` names and
//! numbers every symbol, over the whole rule set at once. `spread` lowers one
//! body into the alternatives it contributes, and `Alt` is the only type that
//! crosses back out.
//!
//! Three things happen across them, and nothing else:
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
//! `inherits` is the one key still ignored, and deliberately: see the test in
//! `import_test.zig`, which proves the committed JSON is already expanded.
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
const fold = @import("fold.zig");
const galley = @import("galley.zig");
const muster = @import("muster.zig");
const spread = @import("spread.zig");

const Import = galley.Import;
const obj = galley.obj;
const str = galley.str;

pub const Error = galley.Error;

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
        .wrapping = std.StringHashMap(void).init(gpa),
    };
    defer imp.deinit();

    // First, because it decides whether a rule is hidden and the rules are
    // about to be interned.
    try muster.readSupertypes(&imp, root.get("supertypes"));
    try muster.readPrecedences(&imp, root.get("precedences"));
    // Before the rules, because it decides which of them is a token at all.
    try muster.census(&imp, root.get("extras"), root.get("externals"));
    // Before anything else interns a symbol, because a terminal's number is
    // the last rung of the lexical tie-break rather than bookkeeping. The two
    // passes below keep their own order and find their symbols already made.
    try muster.numberTerminals(&imp, root.get("word"), root.get("externals"));
    try muster.internExternals(&imp, root.get("externals"));
    try muster.internRules(&imp);
    try muster.placePrecedences(&imp);
    try muster.placeSupertypes(&imp);

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
        for (try spread.alts(&imp, body, .{}, true, rule_name)) |alt| {
            try imp.b.addProductionDynamic(sym, alt.rhs, alt.steps, alt.dynamic);
        }
    }

    // Before the fold rather than beside `conflicts`, because the fold's sweep
    // needs them: an extra is reachable from nothing, so it is a root of the
    // grammar in its own right, and a sweep that does not know that deletes the
    // productions of every nonterminal extra it finds.
    const extras = try muster.readExtras(&imp, root.get("extras"));
    const roots = try imp.scratch.allocator().alloc(u32, extras.len + 1);
    roots[0] = start;
    @memcpy(roots[1..], extras);

    // Folded before the tables see the grammar: `inline` rules are names the
    // author wanted, and substituting them away is how tree-sitter keeps them
    // from costing conflicts the language does not actually have.
    _ = try fold.nonterminals(gpa, &builder, roots, try muster.readInline(&imp, root.get("inline")));

    // After the fold, because folding renumbers nothing but can retire a rule:
    // a word that survived is a word the lexer can still ask about.
    if (str(root.get("word"))) |w| builder.word = imp.symbols.get(w);

    const conflicts = try muster.readConflicts(&imp, root.get("conflicts"));
    return builder.finish(name, start, extras, conflicts);
}

test {
    _ = @import("import_test.zig");
}
