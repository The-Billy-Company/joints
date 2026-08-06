//! M1 - the terminal scanner: bytes in, tokens out.
//!
//! Every terminal a grammar declares is a regex (a literal is the degenerate
//! case), so the whole lexer is one anchored longest-match question asked once
//! per token. irregex answers exactly that question - `regex.munch` - which is
//! why this file is short and contains no automaton of its own. What lives here
//! is the part that is a property of *this grammar* rather than of automata:
//!
//!   * **Which terminals form the slate**, and the map back from a match's
//!     pattern ordinal to the grammar symbol that owns it.
//!   * **The tie-break.** Longest is not the whole rule. `if` and `[a-z]+` both
//!     reach two bytes, and which one a language means is a fact about the
//!     language. tree-sitter's rule - a string beats a pattern of equal length,
//!     and otherwise the earlier declaration wins - is the rule here, and it is
//!     expressible exactly because the IR kept `.literal` and `.regex` apart.
//!   * **Where a terminal may begin.** `token.immediate` says a terminal is
//!     legal only at the offset the last token ended - no extra in between.
//!   * **Who wins when both match.** Lexical precedence outranks length: the
//!     slate is partitioned into tiers and asked highest-first, so a terminal
//!     the author ranked up takes the token even when a lower one reaches
//!     further. Losing either of these is not cosmetic - tree-sitter-json's
//!     `string_content` is immediate *and* `prec(1)*, and its `//` comment
//!     extra is neither, so a `"//"` string value otherwise opens a comment
//!     that eats the rest of the line.
//!   * **The keyword rule.** `Grammar.word` names the terminal a keyword is
//!     spelled as before anybody knows it is a keyword. When both reach the
//!     same bytes the language means the keyword, and nothing about either
//!     pattern says so - see `choose`.
//!   * **What the skip threw away.** An extra is stepped over, but a comment
//!     is a node on the tree, and after the skip nobody can tell where it
//!     was. `nextKeeping` is the same walk handing them back - see `read`.
//!   * **What we are blind to.** A grammar with an external scanner (Python's
//!     indent/dedent) or a token body outside the linear syntax has terminals
//!     no slate can recognize. Where the external is really just a spelling,
//!     `outside.zig` declares it and it joins the slate like anything else;
//!     the rest are named in `blind`, once, at compile - never discovered
//!     halfway through a file as a mysterious stray byte. `unskippable` is the
//!     other half of that answer: an extra spelled as a rule rather than a
//!     terminal, which no seat can step over. Between them a caller can ask what
//!     this scanner cannot do for a grammar and get the whole truth, which is
//!     the point - a partial answer is what let a dropped extra strand two
//!     grammars at byte zero without any instrument noticing.
//!
//! **Lexing is state-directed, and this is not optional.** The naive reading -
//! offer every terminal at every offset - does not survive contact with a real
//! grammar. tree-sitter-json declares `string_content` as `[^\\"\n]+`, which is
//! legal only between quotes but, asked unconditionally, eats `: [1, true,
//! null], ` in one bite and hides every structural token behind it. So `next`
//! takes the set of terminals the parse state will accept, and the restriction
//! rides irregex's walk rather than filtering its answer - filtering afterward
//! recovers nothing, because the long illegal match already suppressed the
//! short legal one. Passing `null` asks the unconditional question, which is
//! honest only for a grammar with no context-dependent terminal.
//!
//! The permission set and the two slate cuts it mirrors - precedence tiers and
//! immediacy - live in `admit.zig`, because they are one subject: everything
//! here that narrows the walk before it starts, as against everything in this
//! file that settles what the walk came back with.

const std = @import("std");
const irregex = @import("irregex");
const g = @import("../../press/grammar.zig");
const lexeme = @import("../../press/lexeme.zig");
const admit = @import("admit.zig");
const outside = @import("outside.zig");
pub const lexicon = @import("lexicon.zig");

const Munch = irregex.Munch;

/// How every terminal pattern is compiled, named once because two things have
/// to agree on it: the automata, and the stamp a folio carries them under.
///
/// Source files are UTF-8 and tree-sitter grammars are written in JavaScript's
/// regex dialect, so `unicode` is on - `\w`, `.`, and `\p{…}` are codepoint-wise,
/// and a byte-wise reading would split `café` mid-character.
///
/// `multiline` without `dotall` is one decision rather than two, and it is the
/// asymmetry JS has without the `s` flag: a negated class admits a newline, `.`
/// does not. Asked of tree-sitter 0.26.11 directly rather than assumed -
/// `/a[^x]b/` accepts `a\nb`, `/a.b/` rejects it. irregex gates the two apart,
/// `complement` on `multiline` alone and `.` on `dotall and multiline`, so this
/// pair reproduces both halves and neither construct needs compiling separately.
/// A terminal is still matched anchored at one offset; `multiline` buys the
/// buffer as the universe, not a second place to start.
///
/// Without it a terminal spelled "content up to a delimiter" - the usual
/// `[^x]+` - cannot cross a line, which is most of what a block comment, a raw
/// string, or a template body is.
const how: Munch.Options = .{ .unicode = true, .multiline = true };

/// What building a scanner can fail on, and it is worth saying what is *not*
/// here: "this grammar has nothing to lex" and "the format will not carry this
/// automaton". Both are real, both are common, and both are spelled `null` by
/// the functions below rather than raised. So every member of these two sets is
/// a fault, which is the fact a caller deciding whether to degrade needs and
/// could not get while the sets were inferred.
///
/// Named rather than inferred for the same reason `Decline` is named next door:
/// an inferred set is one a caller can only handle with an `else`, and an `else`
/// silently adopts whatever a callee grows into later. Spelled here, a new
/// failure mode breaks every switch that has to have an opinion about it, at the
/// moment it is introduced. `impose.slate` is the switch that wanted this.
pub const CompileError = error{
    /// A terminal the IR carries no pattern for. Not a grammar the author can
    /// have written - every terminal is a regex or a literal - so it means the
    /// press dropped one, and the scanner refuses by name rather than panicking
    /// because this is a library whose job is to accept grammars nobody has
    /// looked at.
    TerminalWithoutPattern,
    /// A lexicon section that does not read back. The bytes arrived under a
    /// seal that already matched, so this is not disk corruption; it is the
    /// writer and the reader disagreeing, which is a logic fault in one of them.
    LexiconUnreadable,
    /// irregex cannot parse a pattern on the slate. Distinct from a pattern it
    /// merely cannot *run*: that one is declined per pattern and lands in
    /// `blind`, leaving the rest of the slate intact. This one is the whole
    /// compile refusing, so there is no partial scanner to fall back to.
    BadPattern,
} || std.mem.Allocator.Error;

/// What writing a slate down can fail on. `WriteFailed` is the allocating
/// writer's name for running out of memory - it has no other failure mode, and
/// no file is involved - so both members are the machine rather than the
/// grammar. Kept as two because narrowing it to `OutOfMemory` here would be
/// this file asserting something about `std.Io.Writer.Allocating` that only
/// happens to be true today.
pub const FreezeError = error{WriteFailed} || std.mem.Allocator.Error;

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
    /// Nothing in the slate starts at this offset. The caller owns the policy -
    /// resynchronize by a byte, or stop and report - because a lexer that
    /// silently skipped would turn a syntax error into a wrong parse.
    stray: u32,
    end,
};

pub const Scanner = struct {
    gpa: std.mem.Allocator,
    munch: Munch,
    /// The one buffer a read-back slate's automata live in, empty when they
    /// were determinized here. It is the slate's backing store rather than
    /// anything the scan consults, and it is held for exactly as long as the
    /// automata pointing into it.
    image: []align(@alignOf(u64)) u8,
    /// Which slate this scanner was built over. A folio and its grammar travel
    /// together, so this only ever differs after somebody rebuilt one of them
    /// alone - and then the carried automata name terminals that have moved.
    stamp: u64,
    /// Pattern ordinal -> the terminal it stands for.
    owners: []const g.Symbol,
    /// Terminal -> is it skipped between tokens (whitespace, comments)?
    skipped: std.DynamicBitSetUnmanaged,
    /// Terminal -> is it an extra the grammar also spells inside a rule?
    ///
    /// Almost never. Whitespace and comments are declared once, in `extras`,
    /// and appear in no production, so they can only ever be bytes to step
    /// over. The exception carries real weight: elixir declares `\r?\n` as an
    /// extra and builds `_terminator` out of the same pattern, so one symbol is
    /// both the whitespace between two tokens and the boundary between two
    /// statements, and only the state standing there knows which.
    ///
    /// Consulted only where `skipped` is set, and it is what keeps a caller
    /// that admits the whole slate - `blame`, and the tests - from resurrecting
    /// a pure extra as a token. Admitting everything is the absence of a
    /// narrowing rather than a claim that whitespace was meant.
    meant: std.DynamicBitSetUnmanaged,
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
    /// Terminal -> the provision that seated it, when that provision states a
    /// trailing context. Null for every other terminal, which is nearly all of
    /// them.
    guard: []const ?*const outside.Provision,
    /// Those terminals as a slate cut, or null when the grammar has none. The
    /// pass that reads it runs before the ordinary search - see `refusing`.
    guarded: ?Munch.Allow,
    /// The terminal a keyword is spelled as, when the grammar named one.
    word: ?g.Symbol,
    /// Terminals no slate can recognize because they are externally scanned and
    /// no hand answers them. Ascending. Non-empty means any token stream from
    /// this scanner is incomplete, and every consumer is required to say so
    /// rather than present a partial lex as a whole one.
    blind: []const g.Symbol,
    /// Terminals whose pattern the regex engine would not build: a syntax it
    /// does not parse, the powerset safety bound, or a word-boundary assertion
    /// reached through the body. Ascending, and the same incompleteness as
    /// `blind` from a reader's point of view.
    ///
    /// Separate because the two have different owners. A blind terminal is
    /// someone else's C to reimplement; a declined one is our own engine
    /// refusing a pattern, which is ours to fix - and it is far more common
    /// than anyone assumed while the two were one number.
    declined: []const g.Symbol,
    /// Extras this scanner cannot step over: the grammar declared them, but they
    /// are rules rather than terminals, so there is no token to skip and no seat
    /// to skip it with. lua spells `comment` as a rule around `--`, julia spells
    /// `line_comment` as one around `#`, and each strays on the first one in the
    /// file rather than skipping it.
    ///
    /// Separate from `blind` because the consequence is different - blind is a
    /// token we cannot produce where one is wanted, this is a token we can
    /// produce and then cannot get out of the way of - and because folding it in
    /// would make every existing reader of `blind` describe a nonterminal as an
    /// externally scanned terminal. Being outside `blind` is also exactly how it
    /// stayed invisible: `blind` is the honesty surface, and a fact that is not a
    /// terminal had nowhere in it to sit.
    unskippable: []const g.Symbol,
    /// The hand-written scanners this grammar binds, with their terminal names
    /// already resolved to symbols. Empty for a grammar whose externals are all
    /// spellings, which is most of them.
    casts: []const outside.Cast,
    /// What those hands remember between tokens. It is per *file*, not per
    /// grammar, which is why `rewind` exists and why the two entry points below
    /// notice a restart on their own: a column stack left over from the last
    /// file would open every block in the next one.
    carry: outside.Carry,
    /// The furthest offset a hand has been asked at since the last rewind. Only
    /// ever read to tell a fresh file from a zero-width token that left the
    /// offset where it was.
    reached: u32,
    /// Terminal -> its pattern ordinal, or `no_seat`. The bridge between the
    /// grammar's numbering and the slate's.
    seat: []const u32,
    /// Terminal -> which rank it lexes in.
    tier: []const u8,
    /// The slate cut into lexical-precedence tiers, strongest first. Asking
    /// them in order is what makes precedence outrank length: a tier that
    /// matches at all ends the search, however short its match.
    ranks: []Rank,
    /// The same slate with the tiers collapsed - every seated terminal in one
    /// cut, for `spot`, which is the one caller that must not let precedence
    /// pick for it. `whole_after` drops the immediate terminals, exactly as
    /// `Rank.after` does.
    whole: Munch.Allow,
    whole_after: Munch.Allow,

    pub const no_seat = std.math.maxInt(u32);

    /// The two cuts of the slate that are not "does this pattern match", and
    /// the per-state permission set shaped like them - see `admit.zig`.
    pub const Rank = admit.Rank;
    pub const Expected = admit.Expected;

    /// A permission set sized to this scanner, holding only the extras.
    pub fn expecting(s: *const Scanner, gpa: std.mem.Allocator) !Expected {
        return Expected.of(s, gpa);
    }

    /// Null when the grammar has no lexable terminal at all - a grammar that is
    /// entirely external scanners, which is a thing we cannot lex rather than a
    /// thing we lex to nothing.
    ///
    /// A grammar that arrived from a folio carries its slate already
    /// determinized, and this reads it rather than rebuilding it - which is the
    /// difference between two milliseconds of startup and eighty. Everything
    /// else about the scanner is derived here either way, because everything
    /// else is cheap; only the automata are worth carrying.
    pub fn compile(gpa: std.mem.Allocator, gr: *const g.Grammar) CompileError!?Scanner {
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
        const guard = try gpa.alloc(?*const outside.Provision, gr.terminal_count);
        errdefer gpa.free(guard);
        @memset(guard, null);

        // The hands, resolved before the slate is cut. A terminal a hand
        // answers must not also be seated as a pattern: the slate is asked at
        // every offset and knows nothing of the memory, so a seat for
        // `string_content` would answer it with Rust's spelling in the middle
        // of a Ruby `%w[]`.
        var casts: std.ArrayList(outside.Cast) = .empty;
        errdefer casts.deinit(gpa);
        const names: struct {
            gr: *const g.Grammar,
            pub fn external(n: @This(), name: []const u8) ?g.Symbol {
                return externalNamed(n.gr, name);
            }
            pub fn terminal(n: @This(), name: []const u8) ?g.Symbol {
                return terminalNamed(n.gr, name);
            }
        } = .{ .gr = gr };
        for (&outside.troupes) |*t| {
            const cast = outside.provision(t, names) orelse continue;
            try casts.append(gpa, cast);
        }

        // The lexical standing of every terminal, resolved once. A provisioned
        // external's standing comes from its declaration rather than from the
        // IR, which has no wrapper on an external to read it off - and the
        // tiers below need the same answer this loop used, or a terminal lexes
        // in one rank and is admitted in another.
        const lexis = try arena.alloc(g.Lexis, gr.terminal_count);
        for (0..gr.terminal_count) |i| {
            const sym: g.Symbol = @intCast(i);
            lexis[i] = gr.lexisOf(sym);
            // `patterns` is optional per symbol because nonterminals have none,
            // so nothing in the type says a terminal has one. Panicking here is
            // not the safer answer: this is a library whose whole job is to
            // accept grammars nobody has looked at, and the press has dropped a
            // terminal's pattern before. Refuse by name instead.
            var pattern = gr.patterns[i] orelse return error.TerminalWithoutPattern;
            var handed = false;
            if (pattern == .external) {
                const name = gr.nameOf(sym);
                for (casts.items) |*c| {
                    if (outside.claimed(c.troupe, name)) handed = true;
                }
                if (!handed) if (outside.provisionFor(gr, name)) |p| {
                    pattern = .{ .regex = p.pattern };
                    lexis[i] = p.lexis;
                    provided.set(i);
                    if (outside.guards(p)) guard[i] = p;
                };
            }
            if (lexis[i].immediate) immediate.set(i);
            switch (pattern) {
                // A hand answers this one, so it is neither seated nor blind.
                .external => if (!handed) try blind.append(gpa, sym),
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

        const stamp = lexicon.digest(slate.items, how);
        var image: []align(@alignOf(u64)) u8 = &.{};
        errdefer if (image.len != 0) gpa.free(image);
        var munch = blk: {
            if (try lexicon.thaw(gpa, gr.lexicon, slate.items.len, stamp)) |carried| {
                image = carried.image;
                break :blk carried.munch;
            }
            break :blk (try Munch.compile(gpa, slate.items, how)) orelse {
                owners.deinit(gpa);
                blind.deinit(gpa);
                casts.deinit(gpa);
                literal.deinit(gpa);
                immediate.deinit(gpa);
                provided.deinit(gpa);
                gpa.free(guard);
                return null;
            };
        };
        errdefer munch.deinit();

        // A pattern irregex refused is a terminal we cannot see, exactly like an
        // external - the reason differs, the consequence does not. Merging them
        // here is what lets `blind` stay one list a caller checks once.
        //
        // `owners` is NOT compacted to remove them. A munch reports matches in
        // the ordinals it was handed and never renumbers around a refusal, so
        // closing the gaps here would shift every terminal after the first
        // refused one onto its neighbor's name - which is not a crash, just a
        // lexer quietly reporting the wrong token forever.
        // Kept apart from `blind`, and the reason is that folding them together
        // was actively misleading: three readers print `blind` as "externally
        // scanned terminal(s)", and php declares twelve externals against
        // ninety-nine blind, of which eighty-seven are patterns the engine
        // would not build. A reader of this lane believed that number was
        // externals and reported it. Two populations, two fields, and the
        // sentence each reader already prints becomes true.
        var declined: std.ArrayList(g.Symbol) = .empty;
        errdefer declined.deinit(gpa);
        for (munch.declined) |ordinal| try declined.append(gpa, owners.items[ordinal]);
        std.mem.sort(g.Symbol, blind.items, {}, std.sort.asc(g.Symbol));
        std.mem.sort(g.Symbol, declined.items, {}, std.sort.asc(g.Symbol));

        var skipped: std.DynamicBitSetUnmanaged = try .initEmpty(gpa, gr.terminal_count);
        errdefer skipped.deinit(gpa);
        var kept: std.DynamicBitSetUnmanaged = try .initEmpty(gpa, gr.terminal_count);
        errdefer kept.deinit(gpa);
        var unskippable: std.ArrayList(g.Symbol) = .empty;
        errdefer unskippable.deinit(gpa);
        for (gr.extras) |e| {
            // A nonterminal extra is a subtree the parser has to reduce, which is
            // not something a seat can do. Recording it rather than passing over
            // it is the difference between a caller that knows the skip is
            // incomplete and one that reads a stray at the first comment.
            if (!gr.isTerminal(e)) {
                try unskippable.append(gpa, e);
                continue;
            }
            skipped.set(e);
            if (gr.shapeOf(e).visible()) kept.set(e);
        }

        // An extra that some rule also spells. One pass over every right-hand
        // side rather than a lookup per skip, because the answer is a fact
        // about the grammar and the skip runs per token.
        var meant: std.DynamicBitSetUnmanaged = try .initEmpty(gpa, gr.terminal_count);
        errdefer meant.deinit(gpa);
        if (skipped.count() > 0) for (gr.productions) |p| {
            for (p.rhs) |sym| if (sym < gr.terminal_count and skipped.isSet(sym)) meant.set(sym);
        };

        // Terminals that live only inside an extra the parser never reduces, and
        // which therefore no parse state can ever name.
        //
        // `unskippable` says a nonterminal extra has no seat to step over it.
        // This is the other end of the same fact: the automaton builds no items
        // for that extra's productions either, so every terminal reachable only
        // through them is absent from every state's permission set. On the
        // state-directed path that costs nothing, because the set they are
        // absent from is the set being consulted. On the state-free path there
        // is no set, the whole slate is offered, and they win - rust's
        // `line_comment` carries a bare `.*`, so `outliner lex` hands back the
        // first line of any rust file as one token and never sees `fn`.
        //
        // Excluded from the two unconditional cuts below and nowhere else. It is
        // the one narrowing available to a path whose whole problem is having
        // nothing to narrow with, and it is available because it is not a guess:
        // these are not terminals a state is unlikely to want, they are
        // terminals no state can express wanting.
        //
        // Conservative on purpose. A terminal reachable from an ordinary rule
        // *as well* stays, because then some state does name it, and the fix for
        // that one is a state rather than a filter. So this strictly removes
        // answers that are always wrong and never removes one that is sometimes
        // right; what it cannot do is make the path honest, which is a property
        // of asking without a state and is what the module header warns about.
        var orphan: std.DynamicBitSetUnmanaged = try .initEmpty(arena, gr.terminal_count);
        if (unskippable.items.len > 0) {
            var within: std.DynamicBitSetUnmanaged = try .initEmpty(arena, gr.symbolCount());
            var stack: std.ArrayList(g.Symbol) = .empty;
            for (unskippable.items) |e| {
                within.set(e);
                try stack.append(arena, e);
            }
            while (stack.pop()) |lhs| for (gr.productionsOf(lhs)) |pi| {
                for (gr.productions[pi].rhs) |sym| {
                    if (sym < gr.terminal_count or within.isSet(sym)) continue;
                    within.set(sym);
                    try stack.append(arena, sym);
                }
            };
            var elsewhere: std.DynamicBitSetUnmanaged = try .initEmpty(arena, gr.terminal_count);
            for (gr.productions) |p| {
                const inside = within.isSet(p.lhs);
                for (p.rhs) |sym| {
                    if (sym >= gr.terminal_count) continue;
                    if (inside) orphan.set(sym) else elsewhere.set(sym);
                }
            }
            // Reachable from an ordinary rule too, so some state names it.
            var out = elsewhere.iterator(.{});
            while (out.next()) |i| orphan.unset(i);
            // And an extra is admitted by every state without being named by
            // any, so orphaning one would leave the skip nothing to step with.
            var extra = skipped.iterator(.{});
            while (extra.next()) |i| orphan.unset(i);
        }

        const seat = try gpa.alloc(u32, gr.terminal_count);
        errdefer gpa.free(seat);
        @memset(seat, no_seat);
        for (owners.items, 0..) |sym, ordinal| seat[sym] = @intCast(ordinal);
        for (munch.declined) |ordinal| seat[owners.items[ordinal]] = no_seat;

        // The tiers, strongest first. Only precedences a seated terminal
        // actually carries become a tier, so the common grammar - every token
        // at rank zero - asks exactly one question per token, as it should.
        var levels: std.ArrayList(i32) = .empty;
        defer levels.deinit(arena);
        for (0..gr.terminal_count) |i| {
            if (seat[i] == no_seat) continue;
            const p = lexis[i].prec;
            if (std.mem.indexOfScalar(i32, levels.items, p) == null) try levels.append(arena, p);
        }
        std.mem.sort(i32, levels.items, {}, std.sort.desc(i32));

        // The guarded stand-ins, as one cut of the slate. Built here rather
        // than per call because it never changes, and left null when nothing
        // is guarded so the common grammar pays no probe at all.
        var guarded: ?Munch.Allow = null;
        errdefer if (guarded) |*a| a.deinit(gpa);
        for (0..gr.terminal_count) |i| {
            if (guard[i] == null or seat[i] == no_seat) continue;
            if (guarded == null) guarded = try munch.allowNone(gpa);
            guarded.?.admit(&munch, seat[i]);
        }

        var whole = try munch.allowNone(gpa);
        errdefer whole.deinit(gpa);
        var whole_after = try munch.allowNone(gpa);
        errdefer whole_after.deinit(gpa);

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
            // Total only because this loop and the one that filled `levels`
            // share the `seat[i] == no_seat` filter twenty-five lines apart.
            // Nothing in the types says so, so it is asserted rather than left
            // to hold by luck; if a later reader widens one filter and not the
            // other, this names the coupling instead of unwrapping a null.
            const found = std.mem.indexOfScalar(i32, levels.items, lx.prec);
            std.debug.assert(found != null); // every seated prec was levelled
            const at: u8 = @intCast(found.?);
            tier[i] = at;
            // `tier` is set either way: it is the state-directed path's index,
            // and that path is narrowed by a real permission set rather than by
            // this. Only the two unconditional cuts skip an orphan - see where
            // it is built.
            if (orphan.isSet(i)) continue;
            ranks[at].all.admit(&munch, seat[i]);
            if (!lx.immediate) ranks[at].after.admit(&munch, seat[i]);
            whole.admit(&munch, seat[i]);
            if (!lx.immediate) whole_after.admit(&munch, seat[i]);
        }

        return .{
            .gpa = gpa,
            .munch = munch,
            .image = image,
            .stamp = stamp,
            .owners = try owners.toOwnedSlice(gpa),
            .skipped = skipped,
            .meant = meant,
            .kept = kept,
            .literal = literal,
            .immediate = immediate,
            .provided = provided,
            .guard = guard,
            .guarded = guarded,
            .word = if (gr.word) |w| (if (seat[w] == no_seat) null else w) else null,
            .blind = try blind.toOwnedSlice(gpa),
            .declined = try declined.toOwnedSlice(gpa),
            .unskippable = try unskippable.toOwnedSlice(gpa),
            .casts = try casts.toOwnedSlice(gpa),
            .carry = .{},
            .reached = 0,
            .seat = seat,
            .tier = tier,
            .ranks = ranks,
            .whole = whole,
            .whole_after = whole_after,
        };
    }

    /// The terminal spelled `name`, if the grammar has one. Linear, and asked
    /// once per troupe member at compile; a map would cost more to build than
    /// the twenty scans it would save.
    fn terminalNamed(gr: *const g.Grammar, name: []const u8) ?g.Symbol {
        if (name.len == 0) return null;
        for (0..gr.terminal_count) |i| {
            const sym: g.Symbol = @intCast(i);
            if (std.mem.eql(u8, gr.nameOf(sym), name)) return sym;
        }
        return null;
    }

    /// The same, restricted to terminals the grammar declared external. A
    /// grammar that happens to spell an ordinary token `string_start` means its
    /// own token by it, and binding a hand to that would be us renaming it.
    fn externalNamed(gr: *const g.Grammar, name: []const u8) ?g.Symbol {
        const sym = terminalNamed(gr, name) orelse return null;
        const pattern = gr.patterns[sym] orelse return null;
        return if (pattern == .external) sym else null;
    }

    /// This scanner's slate, written down for a folio to carry. Null when the
    /// slate was read back rather than determinized - re-deflating what we just
    /// inflated would only prove we can - and when it holds an automaton the
    /// format refuses.
    ///
    /// The bytes are opaque: nothing outside `lexicon.zig` reads them, and the
    /// only thing a caller has to know is that `compile` will find them again
    /// on `Grammar.lexicon`.
    pub fn freeze(s: *const Scanner, gpa: std.mem.Allocator) FreezeError!?[]u8 {
        if (s.image.len != 0) return null;
        return lexicon.freeze(gpa, &s.munch, s.stamp);
    }

    pub fn deinit(s: *Scanner) void {
        s.munch.deinit();
        if (s.image.len != 0) s.gpa.free(s.image);
        s.gpa.free(s.owners);
        s.gpa.free(s.casts);
        s.skipped.deinit(s.gpa);
        s.meant.deinit(s.gpa);
        s.kept.deinit(s.gpa);
        s.literal.deinit(s.gpa);
        s.immediate.deinit(s.gpa);
        s.provided.deinit(s.gpa);
        s.gpa.free(s.guard);
        if (s.guarded) |*a| a.deinit(s.gpa);
        s.gpa.free(s.blind);
        s.gpa.free(s.declined);
        s.gpa.free(s.unskippable);
        s.gpa.free(s.seat);
        s.gpa.free(s.tier);
        s.whole.deinit(s.gpa);
        s.whole_after.deinit(s.gpa);
        for (s.ranks) |*r| r.deinit(s.gpa);
        s.gpa.free(s.ranks);
        s.* = undefined;
    }

    /// The next significant token at or after `at`, with extras skipped.
    ///
    /// `expected` is the set of terminals the parse state will accept; `null`
    /// offers the whole slate, which is only honest for a grammar with no
    /// context-dependent terminal (see the module header - JSON is already not
    /// one of those).
    ///
    /// Resume from `tok.end()`.
    pub fn next(s: *Scanner, bytes: []const u8, at: u32, expected: ?*const Expected) Step {
        s.restarting(at);
        var i = at;
        while (true) switch (s.read(bytes, i, i == at, expected)) {
            .token => |tok| {
                if (!s.stepping(tok.symbol, expected)) return .{ .token = tok };
                i = tok.end();
            },
            .stray => |off| return .{ .stray = off },
            .end => return .end,
        };
    }

    /// What is at `at`, for a caller with no state behind the question.
    ///
    /// `next` resolves by reach, which is right when a parse state named the
    /// set: the state vouched for every member, so the longest of them is the
    /// token. A caller that admits the whole grammar has vouched for nothing,
    /// and every grammar in the corpus holds a run-of-anything-but-a-delimiter
    /// that out-reaches every real token at every byte. Asked that way, maximal
    /// munch reports the widest regex the grammar has, at whatever length the
    /// next delimiter allows - `xml_text` over 1,777 bytes of a scala file with
    /// no XML in it, `(?:[^\\"]+)` over every wall swift has.
    ///
    /// So this asks for the least the slate can commit to instead. The name is
    /// then a fact about the bytes rather than about the grammar's widest
    /// member, and - because a caller that mints a token here goes on to step
    /// past it - a wrong guess costs one token rather than a kilobyte of source
    /// that was never read.
    ///
    /// Extras are still stepped over, on the same rule and for the same reason
    /// as in `next`.
    /// Precedence is dropped here as well as reach, and for the same reason.
    /// A lexical precedence is the author saying which terminal owns a byte
    /// *when both were asked for*; over the whole grammar it elects the same
    /// wide member that reach did, since a body pattern is exactly the kind of
    /// terminal an author gives precedence to. So the slate is flat, the
    /// shortest reading wins, and `choose` settles the tie the ordinary way -
    /// which is where a literal `,` finally outranks the string body that also
    /// matches that one byte.
    pub fn spot(s: *Scanner, bytes: []const u8, at: u32) Step {
        s.restarting(at);
        var i = at;
        while (true) {
            if (i >= bytes.len) return .end;
            const allow = if (i == at) &s.whole else &s.whole_after;
            const hit = s.munch.shortestAmong(bytes, i, allow) orelse return .{ .stray = i };
            if (hit.len == 0) return .{ .stray = i };
            const tok: Token = .{
                .symbol = s.choose(hit.patterns, null),
                .start = i,
                .len = @intCast(hit.len),
            };
            if (!s.stepping(tok.symbol, null)) return .{ .token = tok };
            i = tok.end();
        }
    }

    /// Whether this token is bytes to step over rather than the answer.
    ///
    /// Being an extra is not enough, because a symbol can be an extra and also
    /// be named by the state it arrived in - and then it is both, with the
    /// state deciding which. tree-sitter lowers the same rule into its tables:
    /// a shift-extra action is emitted for a state only where that state has no
    /// action of its own for the symbol, so a real action always wins.
    ///
    /// `meant` gates the question rather than decorating it. An extra no rule
    /// spells has no reading but whitespace, so it is stepped over whatever a
    /// caller admitted - and callers that admit the whole slate are real, both
    /// in `blame` and in every fixture here, where admitting everything means
    /// "no narrowing" rather than "the state named whitespace".
    ///
    /// With no state to consult every extra is stepped over, which is the only
    /// honest reading of the whole slate.
    fn stepping(s: *const Scanner, sym: g.Symbol, expected: ?*const Expected) bool {
        if (!s.skipped.isSet(sym)) return false;
        if (!s.meant.isSet(sym)) return true;
        return if (expected) |e| !e.named.isSet(sym) else true;
    }

    /// The same walk, appending the extras it steps over to `keep` rather than
    /// dropping them. A tree that means to be tree-sitter-identical carries
    /// `(comment)` nodes, and the skip is the only place a comment is ever
    /// seen. Extras that emit no node - a bare `\s` is a symbol the author
    /// never wrote - are dropped as they always were, so a caller appends what
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
        s.restarting(at);
        var i = at;
        while (true) switch (s.read(bytes, i, i == at, expected)) {
            .token => |tok| {
                if (!s.stepping(tok.symbol, expected)) return .{ .token = tok };
                if (s.kept.isSet(tok.symbol)) try keep.append(gpa, tok);
                i = tok.end();
            },
            .stray => |off| return .{ .stray = off },
            .end => return .end,
        };
    }

    /// Forget everything the hands remember. A file's worth of state, so the
    /// caller that starts a new file says so.
    pub fn rewind(s: *Scanner) void {
        s.carry.rewind();
        s.reached = 0;
    }

    /// Where a scan had got to, so it can be put back there.
    ///
    /// Opaque: produced by `save`, consumed by `restore`, and compared with
    /// `same`. Nothing else should read a field of it, and in particular
    /// nothing should compare two of them with `std.meta.eql` - the stacks
    /// inside are fixed-capacity arrays whose bytes past the live prefix are
    /// `undefined`, so a structural comparison of two identical states can
    /// answer no, and answers differently in a release build than in a debug
    /// one. `same` flattens the dead bytes first.
    ///
    /// It is a plain value: no pointers, no allocation, ~1 KB, and copying it
    /// is copying the state. That is a property of the two stacks being
    /// fixed-capacity, which they are for the same reason a hand cannot fail -
    /// see `offside.Columns` and `fence.Spans`.
    pub const Save = struct {
        carry: outside.Carry,
        /// The furthest offset asked for. It travels, and it has to: it is not
        /// part of `Carry`, and a carry put back without it leaves the scanner
        /// thinking a resumed offset of zero is a new file.
        reached: u32,

        pub fn same(a: *const Save, b: *const Save) bool {
            return a.reached == b.reached and a.carry.same(&b.carry);
        }
    };

    /// Everything a resumed scan has to be told. Every hand's memory is in
    /// `Carry` - the offside column stack, the fence mark stack, the
    /// zero-width progress guard - and the marrow and caesura hands hold
    /// nothing at all. Nothing else on `Scanner` moves while a file is being
    /// read; the rest is the compiled grammar, which is per grammar and not
    /// per file.
    pub fn save(s: *const Scanner) Save {
        return .{ .carry = s.carry, .reached = s.reached };
    }

    pub fn restore(s: *Scanner, to: Save) void {
        s.carry = to.carry;
        s.reached = to.reached;
    }

    /// Notice a new file without being told. A parse that got anywhere left
    /// `reached` past zero, so an offset of zero after that is a restart; a
    /// zero-width token at the top of a file leaves the offset at zero but has
    /// not moved `reached` either, so it is not mistaken for one.
    fn restarting(s: *Scanner, at: u32) void {
        if (at == 0 and s.reached > 0) s.rewind();
        if (at > s.reached) s.reached = at;
    }

    /// One token at `i`, extra or not: the whole answer at one offset, with
    /// what to do about an extra left to the two loops above. `fresh` is
    /// theirs to pass - immediacy is a fact about the walk rather than about
    /// this offset (see `reach`).
    ///
    /// A hand is asked first, and asked even at the end of the input. Both are
    /// tree-sitter's order and both are load-bearing: the whitespace in front
    /// of a Python line *is* its indentation, so an extra must not eat it
    /// before the offside rule sees it, and end of input still owes a dedent
    /// for every block left open. `fresh` goes through rather than gating the
    /// call, because only the layout hand needs it - see `outside.step`.
    ///
    /// Asked only when there is a state to ask on behalf of. A hand answers out
    /// of the permission set and has no reading of "everything is admitted": a
    /// synthesized full set would have python's layout hand and ruby's opener
    /// both claiming every offset they can reach. So `expected` of null is the
    /// slate alone, which is the same silence `next`'s header already warns a
    /// context-dependent grammar to expect - a grammar with hands is exactly
    /// one of those.
    fn read(s: *Scanner, bytes: []const u8, i: u32, fresh: bool, expected: ?*const Expected) Step {
        if (s.casts.len > 0) if (expected) |e| {
            if (outside.step(s.casts, &s.carry, bytes, i, fresh, &e.wanted, &e.named)) |h| {
                return .{ .token = .{ .symbol = h.symbol, .start = i + h.skip, .len = h.len } };
            }
        };
        if (i >= bytes.len) return .end;
        if (s.guarded) |*allow| if (expected) |e| {
            if (s.refusing(allow, bytes, i, e)) |tok| return .{ .token = tok };
        };
        const hit = s.reach(bytes, i, fresh, expected) orelse {
            // The slate has nothing for these bytes, which is exactly the
            // position a commanded layout open answers: a `.writ` order is
            // licensed by the parse having no other move, so it is asked here
            // rather than above and never competes with a token that would have
            // lexed. See `outside.ordered`.
            if (s.casts.len > 0) if (expected) |e| {
                if (outside.ordered(s.casts, &s.carry, bytes, i, &e.wanted, &e.named)) |h| {
                    return .{ .token = .{ .symbol = h.symbol, .start = i + h.skip, .len = h.len } };
                }
            };
            return .{ .stray = i };
        };
        return .{ .token = .{
            .symbol = s.choose(hit.patterns, expected),
            .start = i,
            .len = @intCast(hit.len),
        } };
    }

    /// A stand-in that states the refusal its scanner makes, asked before the
    /// slate the way tree-sitter asks the external scanner before the internal
    /// lexer - and losing the position outright when its trailing context does
    /// not hold, which is what "the scanner returned false" means.
    ///
    /// Going first is the whole point, and a tie-break could not have done it.
    /// bash is the case: `word` matches `rows=` and `variable_name` matches
    /// `rows`, so longest-match hands the assignment target to `word` before
    /// any tie is reached, and `declare -a rows=()` strays on the bracket.
    /// tree-sitter never runs that comparison, because its scanner already
    /// answered.
    ///
    /// Narrow on purpose. Only a guarded row is asked here, because only a
    /// guarded row has said what it refuses; an unguarded stand-in is still
    /// our approximation of a C function and still defers to the slate. No
    /// guarded row is immediate or precedence-ranked, so this pass reads
    /// neither - see the test that holds the roll to it.
    fn refusing(
        s: *Scanner,
        allow: *const Munch.Allow,
        bytes: []const u8,
        i: u32,
        expected: *const Expected,
    ) ?Token {
        const hit = s.munch.longestAmong(bytes, i, allow) orelse return null;
        if (hit.len == 0) return null;
        const end = i + @as(u32, @intCast(hit.len));
        var best: ?g.Symbol = null;
        for (hit.patterns) |ordinal| {
            const sym = s.owners[ordinal];
            if (!expected.wanted.isSet(sym)) continue;
            const p = s.guard[sym] orelse continue;
            if (!outside.holds(p, bytes, end)) continue;
            // Ordinals arrive ascending, so the earliest declaration stands.
            if (best == null) best = sym;
        }
        const sym = best orelse return null;
        return .{ .symbol = sym, .start = i, .len = @intCast(hit.len) };
    }

    /// The match at `i`: the strongest tier that answers at all, and the
    /// longest match inside it. `fresh` says no extra has been skipped since
    /// the last token ended, which is the only place an immediate terminal may
    /// begin.
    ///
    /// A zero-length match is not an answer - a terminal that accepts the empty
    /// string would pin the scan at one offset forever - so the search passes
    /// over it and lets a weaker tier, or the stray, have the position.
    fn reach(
        s: *Scanner,
        bytes: []const u8,
        i: u32,
        fresh: bool,
        expected: ?*const Expected,
    ) ?irregex.regex.munch.Match {
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
    /// A string beats a pattern - `if` over `[a-z]+` - and among equals the
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
    fn choose(s: *const Scanner, tied: []const u32, expected: ?*const Expected) g.Symbol {
        const plain = s.pick(tied, false, expected).?;
        if (s.word) |w| if (plain == w) return s.pick(tied, true, expected) orelse plain;
        return plain;
    }

    /// The strongest of the patterns that reached the same length. `keywords`
    /// drops the word terminal and every stand-in, which is the keyword pass.
    fn pick(
        s: *const Scanner,
        tied: []const u32,
        keywords: bool,
        expected: ?*const Expected,
    ) ?g.Symbol {
        var best: ?g.Symbol = null;
        var strength: u3 = 0;
        for (tied) |ordinal| {
            const sym = s.owners[ordinal];
            if (keywords and (sym == s.word.? or s.provided.isSet(sym))) continue;
            const of = s.standing(sym, expected);
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
    ///
    /// An extra the state named is not on that floor, and the floor's own
    /// reason says why: it is there because an extra steps over bytes nobody
    /// asked for, and a state that named the symbol asked for it. Two extras
    /// can reach the same byte with only one of them meant - elixir's `\r?\n`
    /// beside its `[ \t]|\r?\n|\\\r?\n` - and without this the coin flip
    /// between them decides whether the file has statement boundaries.
    ///
    /// **Immediacy refines each class, and never crosses one.** `terminalKey`
    /// keeps `(` and `token.immediate('(')` apart as two terminals wearing one
    /// name, so a state that admits both hands the walk two patterns that reach
    /// the same byte. They tie on length and on class, and before this the
    /// tie fell through to declaration order - which is a coincidence, not an
    /// answer, and it picked wrong: elixir's plain `(` is declared inside
    /// `block` well before `_call_arguments_with_parentheses_immediate`, so
    /// every `b(c, d)` was read as a paren-*less* call whose one argument is a
    /// parenthesised block, and a block has no comma form. Immediacy is a
    /// restriction rather than a rank, so the spelling legal only *here* is the
    /// narrower claim and wins it - the same reason a literal beats a pattern.
    /// It sits under the class so a literal never loses to an immediate
    /// pattern, which is tree-sitter's ordering and not ours to move.
    ///
    /// Measured 2026-08-05, one build apart with nothing else changed: corpus
    /// rubble 37,023 -> 30,374, of which elixir is 6,984 -> 452. Twenty-four of
    /// thirty grammars byte-identical; the six that move all improve, and none
    /// regress. Confining the refinement to the literal class scores the same
    /// (30,377), so the pattern half is carried on the argument rather than on
    /// the corpus - julia is the only grammar that reads it, at three bytes.
    fn standing(s: *const Scanner, sym: g.Symbol, expected: ?*const Expected) u3 {
        if (s.skipped.isSet(sym) and s.stepping(sym, expected)) return 0;
        const narrow: u3 = @intFromBool(s.immediate.isSet(sym));
        if (s.provided.isSet(sym)) return 1 + narrow;
        const class: u3 = if (s.literal.isSet(sym)) 5 else 3;
        return class + narrow;
    }

    /// How many terminals this scanner can actually recognize.
    pub fn recognized(s: *const Scanner) usize {
        return s.owners.len - s.munch.declined.len;
    }
};

/// Every token in `bytes`, extras already dropped. Stops at the first stray and
/// reports where - a partial stream plus the offset that ended it is strictly
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
