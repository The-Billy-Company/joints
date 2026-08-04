//! M1 — the terminal scanner: bytes in, tokens out.
//!
//! Every terminal a grammar declares is a regex (a literal is the degenerate
//! case), so the whole lexer is one anchored longest-match question asked once
//! per token. irregex answers exactly that question — `regex_munch` — which is
//! why this file is short and contains no automaton of its own. What lives here
//! is the part that is a property of *this grammar* rather than of automata:
//!
//!   * **Which terminals form the slate**, and the map back from a match's
//!     pattern ordinal to the grammar symbol that owns it.
//!   * **The tie-break.** Longest is not the whole rule. `if` and `[a-z]+` both
//!     reach two bytes, and which one a language means is a fact about the
//!     language. tree-sitter's rule — a string beats a pattern of equal length,
//!     and otherwise the earlier declaration wins — is the rule here, and it is
//!     expressible exactly because the IR kept `.literal` and `.regex` apart.
//!   * **Where a terminal may begin.** `token.immediate` says a terminal is
//!     legal only at the offset the last token ended — no extra in between.
//!   * **Who wins when both match.** Lexical precedence outranks length: the
//!     slate is partitioned into tiers and asked highest-first, so a terminal
//!     the author ranked up takes the token even when a lower one reaches
//!     further. Losing either of these is not cosmetic — tree-sitter-json's
//!     `string_content` is immediate *and* `prec(1)*, and its `//` comment
//!     extra is neither, so a `"//"` string value otherwise opens a comment
//!     that eats the rest of the line.
//!   * **The keyword rule.** `Grammar.word` names the terminal a keyword is
//!     spelled as before anybody knows it is a keyword. When both reach the
//!     same bytes the language means the keyword, and nothing about either
//!     pattern says so — see `choose`.
//!   * **What the skip threw away.** An extra is stepped over, but a comment
//!     is a node on the tree, and after the skip nobody can tell where it
//!     was. `nextKeeping` is the same walk handing them back — see `read`.
//!   * **What we are blind to.** A grammar with an external scanner (Python's
//!     indent/dedent) or a token body outside the linear syntax has terminals
//!     no slate can recognize. Where the external is really just a spelling,
//!     `outside.zig` declares it and it joins the slate like anything else;
//!     the rest are named in `blind`, once, at compile — never discovered
//!     halfway through a file as a mysterious stray byte.
//!
//! **Lexing is state-directed, and this is not optional.** The naive reading —
//! offer every terminal at every offset — does not survive contact with a real
//! grammar. tree-sitter-json declares `string_content` as `[^\\"\n]+`, which is
//! legal only between quotes but, asked unconditionally, eats `: [1, true,
//! null], ` in one bite and hides every structural token behind it. So `next`
//! takes the set of terminals the parse state will accept, and the restriction
//! rides irregex's walk rather than filtering its answer — filtering afterward
//! recovers nothing, because the long illegal match already suppressed the
//! short legal one. Passing `null` asks the unconditional question, which is
//! honest only for a grammar with no context-dependent terminal.
//!
//! The permission set and the two slate cuts it mirrors — precedence tiers and
//! immediacy — live in `admit.zig`, because they are one subject: everything
//! here that narrows the walk before it starts, as against everything in this
//! file that settles what the walk came back with.

const std = @import("std");
const irregex = @import("irregex");
const g = @import("../../press/grammar.zig");
const lexeme = @import("../../press/lexeme.zig");
const admit = @import("admit.zig");
const outside = @import("outside.zig");

const Munch = irregex.regex_munch.Munch;

test {
    _ = outside;
}

pub const Token = struct {
    symbol: g.Symbol,
    start: u32,
    len: u32,

    pub fn end(t: Token) u32 {
        return t.start + t.len;
    }
};

/// What one step of the scan found. Three outcomes, because there are three:
/// a token, a byte no terminal can begin at, and the end of the input.
pub const Step = union(enum) {
    token: Token,
    /// Nothing in the slate starts at this offset. The caller owns the policy —
    /// resynchronize by a byte, or stop and report — because a lexer that
    /// silently skipped would turn a syntax error into a wrong parse.
    stray: u32,
    end,
};

pub const Scanner = struct {
    gpa: std.mem.Allocator,
    munch: Munch,
    /// Pattern ordinal -> the terminal it stands for.
    owners: []const g.Symbol,
    /// Terminal -> is it skipped between tokens (whitespace, comments)?
    skipped: std.DynamicBitSetUnmanaged,
    /// Terminal -> is it a skipped one the tree still keeps? Whitespace
    /// interns as a symbol the author never wrote and emits nothing; a
    /// `comment` rule emits a node. Consulted only where `skipped` is set.
    kept: std.DynamicBitSetUnmanaged,
    /// Terminal -> was it declared as an exact string? Half the tie-break.
    literal: std.DynamicBitSetUnmanaged,
    /// Terminal -> may it only begin where the previous token ended?
    immediate: std.DynamicBitSetUnmanaged,
    /// Terminal -> is it seated only because `outside.zig` declared a spelling
    /// for it? Such a terminal is a stand-in for a scanner the grammar expected
    /// us to link, and the keyword rule leaves it alone for the same reason
    /// tree-sitter's does: keyword extraction only ever sees tokens the grammar
    /// file itself defined.
    provided: std.DynamicBitSetUnmanaged,
    /// The terminal a keyword is spelled as, when the grammar named one.
    word: ?g.Symbol,
    /// Terminals no slate can recognize: external scanners, and token bodies
    /// irregex declined. Ascending. Non-empty means any token stream from this
    /// scanner is incomplete, and every consumer is required to say so rather
    /// than present a partial lex as a whole one.
    blind: []const g.Symbol,
    /// Terminal -> its pattern ordinal, or `no_seat`. The bridge between the
    /// grammar's numbering and the slate's.
    seat: []const u32,
    /// Terminal -> which rank it lexes in.
    tier: []const u8,
    /// The slate cut into lexical-precedence tiers, strongest first. Asking
    /// them in order is what makes precedence outrank length: a tier that
    /// matches at all ends the search, however short its match.
    ranks: []Rank,

    pub const no_seat = std.math.maxInt(u32);

    /// The two cuts of the slate that are not "does this pattern match", and
    /// the per-state permission set shaped like them — see `admit.zig`.
    pub const Rank = admit.Rank;
    pub const Expected = admit.Expected;

    /// A permission set sized to this scanner, holding only the extras.
    pub fn expecting(s: *const Scanner, gpa: std.mem.Allocator) !Expected {
        return Expected.of(s, gpa);
    }

    /// Null when the grammar has no lexable terminal at all — a grammar that is
    /// entirely external scanners, which is a thing we cannot lex rather than a
    /// thing we lex to nothing.
    pub fn compile(gpa: std.mem.Allocator, gr: *const g.Grammar) !?Scanner {
        var arena_state = std.heap.ArenaAllocator.init(gpa);
        defer arena_state.deinit();
        const arena = arena_state.allocator();

        var slate: std.ArrayList([]const u8) = .empty;
        var owners: std.ArrayList(g.Symbol) = .empty;
        var blind: std.ArrayList(g.Symbol) = .empty;

        var literal: std.DynamicBitSetUnmanaged = try .initEmpty(gpa, gr.terminal_count);
        errdefer literal.deinit(gpa);
        var immediate: std.DynamicBitSetUnmanaged = try .initEmpty(gpa, gr.terminal_count);
        errdefer immediate.deinit(gpa);
        var provided: std.DynamicBitSetUnmanaged = try .initEmpty(gpa, gr.terminal_count);
        errdefer provided.deinit(gpa);

        // The lexical standing of every terminal, resolved once. A provisioned
        // external's standing comes from its declaration rather than from the
        // IR, which has no wrapper on an external to read it off — and the
        // tiers below need the same answer this loop used, or a terminal lexes
        // in one rank and is admitted in another.
        const lexis = try arena.alloc(g.Lexis, gr.terminal_count);
        for (0..gr.terminal_count) |i| {
            const sym: g.Symbol = @intCast(i);
            lexis[i] = gr.lexisOf(sym);
            var pattern = gr.patterns[i].?;
            if (pattern == .external) {
                if (outside.provisionFor(gr.nameOf(sym))) |p| {
                    pattern = .{ .regex = p.pattern };
                    lexis[i] = p.lexis;
                    provided.set(i);
                }
            }
            if (lexis[i].immediate) immediate.set(i);
            switch (pattern) {
                .external => try blind.append(gpa, sym),
                .literal => |lit| {
                    literal.set(i);
                    var rx: std.ArrayList(u8) = .empty;
                    try lexeme.escape(&rx, arena, lit);
                    try slate.append(arena, rx.items);
                    try owners.append(gpa, sym);
                },
                .regex => |rx| {
                    try slate.append(arena, rx);
                    try owners.append(gpa, sym);
                },
            }
        }
        errdefer owners.deinit(gpa);
        errdefer blind.deinit(gpa);

        // Unicode on, and nothing else. Source files are UTF-8 and tree-sitter
        // grammars are written in JavaScript's regex dialect, where `\w`, `.`,
        // and `\p{…}` are all codepoint-wise — a byte-wise reading would split
        // `café` mid-character. `dotall` stays off for the same reason: JS `.`
        // does not match a newline, so a token written `.` must not swallow one.
        var munch = (try Munch.compile(gpa, slate.items, .{ .unicode = true })) orelse {
            owners.deinit(gpa);
            blind.deinit(gpa);
            literal.deinit(gpa);
            immediate.deinit(gpa);
            provided.deinit(gpa);
            return null;
        };
        errdefer munch.deinit();

        // A pattern irregex refused is a terminal we cannot see, exactly like an
        // external — the reason differs, the consequence does not. Merging them
        // here is what lets `blind` stay one list a caller checks once.
        //
        // `owners` is NOT compacted to remove them. A munch reports matches in
        // the ordinals it was handed and never renumbers around a refusal, so
        // closing the gaps here would shift every terminal after the first
        // refused one onto its neighbor's name — which is not a crash, just a
        // lexer quietly reporting the wrong token forever.
        for (munch.declined) |ordinal| try blind.append(gpa, owners.items[ordinal]);
        std.mem.sort(g.Symbol, blind.items, {}, std.sort.asc(g.Symbol));

        var skipped: std.DynamicBitSetUnmanaged = try .initEmpty(gpa, gr.terminal_count);
        errdefer skipped.deinit(gpa);
        var kept: std.DynamicBitSetUnmanaged = try .initEmpty(gpa, gr.terminal_count);
        errdefer kept.deinit(gpa);
        for (gr.extras) |e| if (gr.isTerminal(e)) {
            skipped.set(e);
            if (gr.shapeOf(e).visible()) kept.set(e);
        };

        const seat = try gpa.alloc(u32, gr.terminal_count);
        errdefer gpa.free(seat);
        @memset(seat, no_seat);
        for (owners.items, 0..) |sym, ordinal| seat[sym] = @intCast(ordinal);
        for (munch.declined) |ordinal| seat[owners.items[ordinal]] = no_seat;

        // The tiers, strongest first. Only precedences a seated terminal
        // actually carries become a tier, so the common grammar — every token
        // at rank zero — asks exactly one question per token, as it should.
        var levels: std.ArrayList(i32) = .empty;
        defer levels.deinit(arena);
        for (0..gr.terminal_count) |i| {
            if (seat[i] == no_seat) continue;
            const p = lexis[i].prec;
            if (std.mem.indexOfScalar(i32, levels.items, p) == null) try levels.append(arena, p);
        }
        std.mem.sort(i32, levels.items, {}, std.sort.desc(i32));

        const tier = try gpa.alloc(u8, gr.terminal_count);
        errdefer gpa.free(tier);
        @memset(tier, 0);
        const ranks = try gpa.alloc(Rank, levels.items.len);
        errdefer gpa.free(ranks);
        for (ranks, levels.items) |*r, p| r.* = .{
            .prec = p,
            .all = try munch.allowNone(gpa),
            .after = try munch.allowNone(gpa),
        };
        errdefer for (ranks) |*r| r.deinit(gpa);
        for (0..gr.terminal_count) |i| {
            if (seat[i] == no_seat) continue;
            const lx = lexis[i];
            const at: u8 = @intCast(std.mem.indexOfScalar(i32, levels.items, lx.prec).?);
            tier[i] = at;
            ranks[at].all.admit(&munch, seat[i]);
            if (!lx.immediate) ranks[at].after.admit(&munch, seat[i]);
        }

        return .{
            .gpa = gpa,
            .munch = munch,
            .owners = try owners.toOwnedSlice(gpa),
            .skipped = skipped,
            .kept = kept,
            .literal = literal,
            .immediate = immediate,
            .provided = provided,
            .word = if (gr.word) |w| (if (seat[w] == no_seat) null else w) else null,
            .blind = try blind.toOwnedSlice(gpa),
            .seat = seat,
            .tier = tier,
            .ranks = ranks,
        };
    }

    pub fn deinit(s: *Scanner) void {
        s.munch.deinit();
        s.gpa.free(s.owners);
        s.skipped.deinit(s.gpa);
        s.kept.deinit(s.gpa);
        s.literal.deinit(s.gpa);
        s.immediate.deinit(s.gpa);
        s.provided.deinit(s.gpa);
        s.gpa.free(s.blind);
        s.gpa.free(s.seat);
        s.gpa.free(s.tier);
        for (s.ranks) |*r| r.deinit(s.gpa);
        s.gpa.free(s.ranks);
        s.* = undefined;
    }

    /// The next significant token at or after `at`, with extras skipped.
    ///
    /// `expected` is the set of terminals the parse state will accept; `null`
    /// offers the whole slate, which is only honest for a grammar with no
    /// context-dependent terminal (see the module header — JSON is already not
    /// one of those).
    ///
    /// Resume from `tok.end()`.
    pub fn next(s: *Scanner, bytes: []const u8, at: u32, expected: ?*const Expected) Step {
        var i = at;
        while (true) switch (s.read(bytes, i, i == at, expected)) {
            .token => |tok| {
                if (!s.skipped.isSet(tok.symbol)) return .{ .token = tok };
                i = tok.end();
            },
            .stray => |off| return .{ .stray = off },
            .end => return .end,
        };
    }

    /// The same walk, appending the extras it steps over to `keep` rather than
    /// dropping them. A tree that means to be tree-sitter-identical carries
    /// `(comment)` nodes, and the skip is the only place a comment is ever
    /// seen. Extras that emit no node — a bare `\s` is a symbol the author
    /// never wrote — are dropped as they always were, so a caller appends what
    /// it receives without re-deciding what the tree keeps.
    ///
    /// A sibling rather than a flag on `next`, because the two differ by one
    /// line and `next` is infallible: appending can fail, and a parser driving
    /// the hot path should not have to handle an error it cannot cause.
    pub fn nextKeeping(
        s: *Scanner,
        gpa: std.mem.Allocator,
        bytes: []const u8,
        at: u32,
        expected: ?*const Expected,
        keep: *std.ArrayList(Token),
    ) !Step {
        var i = at;
        while (true) switch (s.read(bytes, i, i == at, expected)) {
            .token => |tok| {
                if (!s.skipped.isSet(tok.symbol)) return .{ .token = tok };
                if (s.kept.isSet(tok.symbol)) try keep.append(gpa, tok);
                i = tok.end();
            },
            .stray => |off| return .{ .stray = off },
            .end => return .end,
        };
    }

    /// One token at `i`, extra or not: the whole answer at one offset, with
    /// what to do about an extra left to the two loops above. `fresh` is
    /// theirs to pass — immediacy is a fact about the walk rather than about
    /// this offset (see `reach`).
    fn read(s: *Scanner, bytes: []const u8, i: u32, fresh: bool, expected: ?*const Expected) Step {
        if (i >= bytes.len) return .end;
        const hit = s.reach(bytes, i, fresh, expected) orelse return .{ .stray = i };
        return .{ .token = .{
            .symbol = s.choose(hit.patterns),
            .start = i,
            .len = @intCast(hit.len),
        } };
    }

    /// The match at `i`: the strongest tier that answers at all, and the
    /// longest match inside it. `fresh` says no extra has been skipped since
    /// the last token ended, which is the only place an immediate terminal may
    /// begin.
    ///
    /// A zero-length match is not an answer — a terminal that accepts the empty
    /// string would pin the scan at one offset forever — so the search passes
    /// over it and lets a weaker tier, or the stray, have the position.
    fn reach(
        s: *Scanner,
        bytes: []const u8,
        i: u32,
        fresh: bool,
        expected: ?*const Expected,
    ) ?irregex.regex_munch.Match {
        for (s.ranks, 0..) |*rank, t| {
            const allow = if (expected) |e| blk: {
                const tier = &e.tiers[t];
                if (fresh) {
                    if (!tier.live_here) continue;
                    break :blk &tier.here;
                }
                if (!tier.live_later) continue;
                break :blk &tier.later;
            } else if (fresh) &rank.all else &rank.after;
            if (s.munch.longestAmong(bytes, i, allow)) |hit| {
                if (hit.len > 0) return hit;
            }
        }
        return null;
    }

    /// Which of the patterns that tied deserves the token.
    ///
    /// Two rules, and the second only ever settles what the first left as a
    /// coin flip.
    ///
    /// A string beats a pattern — `if` over `[a-z]+` — and among equals the
    /// earlier declaration wins, which is exactly tree-sitter's rule and is
    /// also the only one a grammar author can predict. Below both sits a
    /// stand-in for an external scanner, because it is a guess about a C
    /// function we do not have and the grammar's own spelling of the same bytes
    /// is better evidence than our guess. bash is the case that proves it:
    /// `variable_name` stands in for a scanner that refuses unless an `=`
    /// follows, so a stand-in ranked level with `word` would call every bare
    /// word in the file an assignment target.
    ///
    /// Under all of them sits an extra, and that floor is load-bearing rather
    /// than tidy. An extra is what steps over bytes nobody asked for, so it can
    /// never be the better answer than a terminal this state named. ruby is the
    /// case: its newline ends a statement, spelled `_line_break`, while its
    /// `extras` still carry a bare `\s` that matches the same one byte. Rank
    /// them level and the extra eats every significant newline in the file and
    /// the next `def` arrives as a stray.
    ///
    /// Then the keyword rule. `Grammar.word` names the terminal a keyword is
    /// spelled as before anybody knows it is a keyword, and when that terminal
    /// wins a tie the language almost always meant the other one: C's `int`
    /// reaches three bytes as both `primitive_type` and `identifier`, and
    /// declaration order is a coincidence rather than an answer. tree-sitter
    /// re-lexes the matched bytes against a keyword automaton and prefers what
    /// it finds; the same answer here is to let anything the grammar spelled
    /// itself outrank the word it was spelled as.
    ///
    /// A provisioned external is not eligible, and that exclusion is the whole
    /// safety of the rule rather than a detail: tree-sitter's keyword pass only
    /// ever sees tokens the grammar file defined, and bash's `variable_name` is
    /// a subset of its `word` that is emphatically not a keyword of it. Without
    /// the exclusion every bare bash word would come back as an assignment.
    fn choose(s: *const Scanner, tied: []const u32) g.Symbol {
        const plain = s.pick(tied, false).?;
        if (s.word) |w| if (plain == w) return s.pick(tied, true) orelse plain;
        return plain;
    }

    /// The strongest of the patterns that reached the same length. `keywords`
    /// drops the word terminal and every stand-in, which is the keyword pass.
    fn pick(s: *const Scanner, tied: []const u32, keywords: bool) ?g.Symbol {
        var best: ?g.Symbol = null;
        var strength: u3 = 0;
        for (tied) |ordinal| {
            const sym = s.owners[ordinal];
            if (keywords and (sym == s.word.? or s.provided.isSet(sym))) continue;
            const of = s.standing(sym);
            // Ordinals arrive ascending, so `>` rather than `>=` on the class
            // and `<` on the symbol both hold the earliest declaration.
            if (best) |b| {
                if (of > strength or (of == strength and sym < b)) {
                    best = sym;
                    strength = of;
                }
            } else {
                best = sym;
                strength = of;
            }
        }
        return best;
    }

    /// How much a terminal's spelling is worth in a tie: an extra least, then a
    /// stand-in for an external scanner, and an exact string most.
    fn standing(s: *const Scanner, sym: g.Symbol) u3 {
        if (s.skipped.isSet(sym)) return 0;
        if (s.provided.isSet(sym)) return 1;
        return if (s.literal.isSet(sym)) 3 else 2;
    }

    /// How many terminals this scanner can actually recognize.
    pub fn recognized(s: *const Scanner) usize {
        return s.owners.len - s.munch.declined.len;
    }
};

/// Every token in `bytes`, extras already dropped. Stops at the first stray and
/// reports where — a partial stream plus the offset that ended it is strictly
/// more useful than an error with no prefix, and strictly more honest than a
/// stream that resynchronized without saying so.
pub const Run = struct {
    tokens: []const Token,
    /// Null when the whole input lexed.
    stray: ?u32,

    pub fn deinit(r: *Run, gpa: std.mem.Allocator) void {
        gpa.free(r.tokens);
        r.* = undefined;
    }
};

pub fn tokenize(
    s: *Scanner,
    gpa: std.mem.Allocator,
    bytes: []const u8,
    expected: ?*const Scanner.Expected,
) !Run {
    var out: std.ArrayList(Token) = .empty;
    errdefer out.deinit(gpa);
    var at: u32 = 0;
    while (true) switch (s.next(bytes, at, expected)) {
        .end => return .{ .tokens = try out.toOwnedSlice(gpa), .stray = null },
        .stray => |off| return .{ .tokens = try out.toOwnedSlice(gpa), .stray = off },
        .token => |tok| {
            try out.append(gpa, tok);
            at = tok.end();
        },
    };
}
