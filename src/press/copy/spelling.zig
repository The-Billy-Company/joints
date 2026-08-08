//! What a node spells as a token, and the standing it spells it at.
//!
//! A terminal's identity is two facts rather than one: the bytes it matches,
//! and the lexical standing it matches them under. `atomPattern` answers the
//! first and draws tree-sitter's own boundary between one token and two;
//! `lexis` answers the second by reading the wrapper chain the author wrote,
//! which is where immediacy and a token's own rank are declared. `terminalKey`
//! puts the pair together, and that key is the judgement the rest of the front
//! end rests on: it decides whether two spellings are one terminal or two, and
//! `muster` and `spread` both have to ask it the same question and get the same
//! answer or a rule and an inline literal come apart.

const std = @import("std");
const json = std.json;
const g = @import("grammar.zig");
const lexeme = @import("lexeme.zig");
const galley = @import("galley.zig");

const Import = galley.Import;
const Error = galley.Error;
const obj = galley.obj;
const str = galley.str;

/// The lexical facts a token node's wrapper chain declares: `token.immediate`
/// anywhere in it, and the `prec` it carries once inside a `token`.
///
/// Read from the wrappers rather than from the body because that is where
/// the author wrote them, and both say something about the token's standing
/// against the rest of the slate rather than about the bytes it matches.
/// A `prec` *outside* a token wraps the rule, not the lexer, and so is not
/// this function's to report; the walk keeps descending for the sake of the
/// `token` that may still be under it, but declines to read a rank until it
/// is through one.
pub fn lexis(self: *Import, node: json.Value) g.Lexis {
    var out: g.Lexis = .{};
    var ranked: ?i32 = null;
    var lexical = false;
    var cur = node;
    while (true) {
        const o = obj(cur) orelse break;
        const kind = str(o.get("type")) orelse break;
        if (std.mem.eql(u8, kind, "TOKEN") or std.mem.eql(u8, kind, "IMMEDIATE_TOKEN")) {
            lexical = true;
            if (kind[0] == 'I') out.immediate = true;
        }
        // Only a number ranks a token, and only from inside one. A named
        // precedence orders rules against each other and the lexer has no
        // rules to order; a numeric one met *before* any `token` ranks the
        // rule the same way and leaves the token itself unranked, which is
        // why `x: prec(-1, ';')` shares the anonymous `';'` where
        // `x: token(prec(-1, ';'))` mints a second terminal beside it.
        if (lexical and ranked == null and std.mem.startsWith(u8, kind, "PREC")) {
            if (precValue(self, o.get("value")) == .level) {
                ranked = precValue(self, o.get("value")).level;
            }
        }
        if (!lexeme.isWrapper(kind)) break;
        cur = o.get("content") orelse break;
    }
    // Held unset until here rather than accumulated from zero. A rank is
    // signed, and `@max` against an unset zero reads every negative one as
    // no rank at all - which is how ruby's `comment` at -2, written so that
    // `#{` would outrank it, came to outrank nothing. `Lexis` spells
    // absence as zero, so the coercion happens once, here, where the two
    // meanings are still distinguishable.
    out.prec = ranked orelse 0;
    return out;
}

/// The pattern a node lexes as, when the node is a *single* lexical atom.
/// Null means the node is structure. This is tree-sitter's own boundary:
/// `choice('a','b')` is two tokens under one nonterminal, not one token.
pub fn atomPattern(self: *Import, node: json.Value) Error!?g.Pattern {
    const o = obj(node) orelse return null;
    const kind = str(o.get("type")) orelse return null;

    if (std.mem.eql(u8, kind, "STRING")) {
        const v = str(o.get("value")) orelse return null;
        return .{ .literal = try self.b.dupe(v) };
    }
    if (std.mem.eql(u8, kind, "PATTERN")) {
        return if (try renderPattern(self, node)) |rx| .{ .regex = rx } else null;
    }
    // A wrapper that only names or prioritizes still wraps a single atom,
    // so ask what is inside before deciding what this is. `token(...)` and
    // `token.immediate(...)` say when the lexer may fire and how it ranks,
    // never what the tree calls the result: `token(")")` is the same
    // anonymous `")"` node a bare `")"` is, and rendering the wrapper first
    // filed it as a regex, which reads as auxiliary and splices the node
    // away. Nine of the eleven pinned grammars spell at least one node that
    // way, bash 27 of them, and every one was invisible.
    if (lexeme.isWrapper(kind)) {
        const content = o.get("content") orelse return null;
        if (try atomPattern(self, content)) |inner| return inner;
        // Only a token wrapper may still be one atom when its content is
        // not: `token(seq('//', /[^\n]*/))` is a single terminal spelled in
        // pieces, where `prec(1, seq(a, b))` is two symbols sharing a rank.
        const lexical = std.mem.eql(u8, kind, "TOKEN") or
            std.mem.eql(u8, kind, "IMMEDIATE_TOKEN");
        if (!lexical) return null;
        return if (try renderPattern(self, node)) |rx| .{ .regex = rx } else null;
    }
    return null;
}

/// The intern key for an anonymous terminal: what it matches, and the
/// lexical standing it matches under. Both halves, and the second one is
/// the whole judgement.
///
/// Spelling alone is what makes `token(")")` and a bare `")"` one terminal,
/// and that is right; tree-sitter's own `extract_tokens` unwraps a bare
/// `token(...)` before it deduplicates, so its generated parser holds one
/// `anon_sym_RPAREN` for both. Take it further and it stops being right.
/// Ask the same oracle about `")"` beside `token(prec(2, ")"))`, or about
/// `"|"` beside `token.immediate("|")`, and it emits *two* terminals with
/// the same name, `anon_sym_RPAREN` and `anon_sym_RPAREN2`, and collapses
/// them onto one public symbol in `ts_symbol_map`. So the node name is
/// shared and the terminal is not, which is exactly the distinction this
/// key draws: `display` stays the spelling, so both wear `")"` in the tree,
/// and the standing keeps them apart in the slate.
///
/// Merging them instead would union the two `Lexis` records, and `describe`
/// accumulates; `immediate` by `or`, `prec` by `@max`. Precedence would
/// only over-claim: a rank the author declared at one site would speak for
/// every site. Immediacy is worse than that, because it is a restriction
/// rather than a rank. C writes a bare `(` everywhere and
/// `token.immediate('(')` in one macro rule; union them and the bare `(`
/// becomes legal only where the previous token ended, so `if (x)` no longer
/// lexes its own paren. Twenty-four literals across the eleven pinned
/// grammars are reached with two standings, and nineteen of them differ in
/// immediacy.
///
/// Keyed on the standing rather than on the wrapper chain that produced it,
/// which is the one place this parts company with tree-sitter: it would
/// read `token(prec(2, prec(1, ")")))` as a third terminal where this reads
/// the rank it settles at. Two spellings that lex identically are one
/// terminal, and nothing downstream can tell the difference.
pub fn terminalKey(self: *Import, pattern: g.Pattern, lx: g.Lexis) Error![]const u8 {
    const a = self.scratch.allocator();
    const mark = if (lx.immediate) "i" else "";
    return switch (pattern) {
        .literal => |l| try std.fmt.allocPrint(a, "str:{s}:{d}{s}", .{ l, lx.prec, mark }),
        .regex => |rx| try std.fmt.allocPrint(a, "rx:{s}:{d}{s}", .{ rx, lx.prec, mark }),
        .external => unreachable, // an inline node never names a scanner
    };
}

/// What an anonymous terminal is called in the tree: the bytes it matches,
/// which is the only name it has. Two terminals that differ only in lexical
/// standing share it deliberately; see `terminalKey`.
pub fn terminalName(pattern: g.Pattern) []const u8 {
    return switch (pattern) {
        .literal => |l| l,
        .regex => |rx| rx,
        .external => unreachable,
    };
}

pub fn renderPattern(self: *Import, node: json.Value) Error!?[]const u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(self.gpa);
    const r: lexeme.Resolver = .{ .ctx = self, .lookup = lookupRule };
    if (!try lexeme.render(&out, self.gpa, node, r, 0)) return null;
    return try self.b.dupe(out.items);
}

/// What a whole *rule body* lexes as, which is one boundary further out than
/// `atomPattern` draws - and only for a rule the grammar declared an extra.
///
/// An extra has to be steppable, and only a *terminal* can be stepped over: the
/// scanner's skip is a bitset of terminals, and nothing in the automaton hosts a
/// nonterminal, because an extra is reachable from `$start` through nothing by
/// definition. So an extra reaching no other rule has no structure to host and
/// no reading but bytes, and `line_comment: seq('#', /.*/)` is one token spelled
/// in two pieces exactly as `token(seq('#', /.*/))` is.
///
/// **Extras only, and the census is why.** Lowering every rule that reaches
/// nothing is tree-sitter's `extract_tokens` as it is usually described, and it
/// is wrong here: run over the whole corpus it moved twenty-six of thirty
/// automata and cost typescript a parse that had been whole, because a rule like
/// `x: choice('a','b')` is a node with an anonymous child and welding it into one
/// token deletes the child. An extra is the one place where the argument holds on
/// its own, which is the narrowing this keeps.
///
/// The symbol test runs before the render and not inside it: `renderPattern`
/// *inlines* the rules it finds, which is right under a `token(...)` the author
/// asked for and wrong here, where a reference is the evidence that this rule has
/// structure the automaton would have to host. julia's `line_comment` is the
/// whole of what this moves - it and eight other extras are the corpus's
/// structural extras, and it is the only one of the nine reaching nothing.
pub fn bodyPattern(self: *Import, name: []const u8, node: json.Value) Error!?g.Pattern {
    if (try atomPattern(self, node)) |atom| return atom;
    if (!self.lexical.contains(name)) return null;
    return if (try renderPattern(self, node)) |rx| .{ .regex = rx } else null;
}

/// Whether a subtree names no rule. A `SYMBOL` anywhere in it - an external's
/// name included, since an external is a rule we cannot render - means the
/// node derives something and is not a token.
pub fn bare(node: json.Value) bool {
    const o = obj(node) orelse return true;
    const kind = str(o.get("type")) orelse return true;
    if (std.mem.eql(u8, kind, "SYMBOL")) return false;
    if (o.get("members")) |m| if (m == .array) {
        for (m.array.items) |item| if (!bare(item)) return false;
    };
    if (o.get("content")) |content| if (!bare(content)) return false;
    return true;
}

/// A `SYMBOL` inside a token inlines the named rule's body. Returning it
/// unconditionally is safe: the renderer fails on whatever it cannot
/// flatten, and its depth limit ends a cycle.
/// An external's name resolves to no body, so a token that reaches a
/// scanner fails to render — which is the honest answer.
pub fn lookupRule(ctx: *const anyopaque, name: []const u8) ?json.Value {
    const self: *const Import = @ptrCast(@alignCast(ctx));
    return self.rules.get(name);
}

/// A `prec` argument: a number, or a name the orderings rank.
pub fn precValue(self: *Import, node: ?json.Value) g.Prec {
    const v = node orelse return .none;
    return switch (v) {
        .integer => |i| .{ .level = @intCast(i) },
        .float => |f| .{ .level = @intFromFloat(f) },
        .string => |s| .{ .name = self.b.internPrec(s) catch return .none },
        else => .none,
    };
}
