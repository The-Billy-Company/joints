//! Gathering a quire: the parse loop that keeps what the reduction was for.
//!
//! `walk/drive.zig` walks the same automaton and says in its own comment that
//! symbols are not kept, because nothing it serves needs them. A tree needs
//! them, so this is a second loop rather than a flag on that one - and the
//! duplication is the point. Two independent implementations of the same walk
//! can be checked against each other on the same file, and when they disagree
//! about a token or a state one of them is wrong; with one implementation a
//! disagreement is unfindable. The differential is in `gather_test.zig`.
//!
//! The loop itself is the textbook one, except that the stack is a graph. One
//! **perch** per stack symbol holds the bytes that symbol consumed, the nodes
//! it contributed, and the perch beneath it; a stack is the walk down. A
//! reduction of n symbols walks down n perches, reads their node runs, and
//! pushes one perch onto whatever it landed on.
//!
//! ## Forking, and why it is nearly free
//!
//! A grammar author declares the ambiguities their language really has, and
//! `settle` records the cell where each one bites along with the reading it had
//! to drop. `settle.Forks` turns that record into a bit per cell. On every
//! action this loop asks it one masked load, and on a grammar that declares
//! nothing - json - the answer is always no and nothing else changes: one
//! reading, one perch pushed per symbol, the same walk a deterministic LR
//! parser makes. Where the answer is yes, the dropped reading becomes a second
//! **reading** carried beside the first, and the two share every perch below the
//! split. Nothing is speculated ahead of a declared conflict, which is the
//! difference between this and a GLR parser that is nondeterministic by
//! construction.
//!
//! Losing readings die by refutation: the next token has no action in the state
//! they walked themselves into, and a reading with nothing to do is dropped.
//! The table does that job within a token or two on every conflict in the
//! corpus, which is why a cap on live readings is a guard rather than a policy.
//! Ties among readings that all survive go to the least speculative one, so a
//! file that parses today parses identically tomorrow.
//!
//! **Lexing is state-directed and this is not optional.** Before every token
//! the terminals the live readings have any non-error action for are read
//! straight off their action rows and handed to the scanner, which restricts the
//! regex walk rather than filtering its answer. The reduce entries are what
//! make that right: a state that would fold before shifting still offers
//! everything the fold leads to. Offer the whole slate instead and JSON's
//! `string_content` eats the rest of the line. With several readings the slate
//! is their union, which is the one place a reading kept alive too long can
//! make the *lexer* worse rather than merely cost time.
//!
//! ## The recipe
//!
//! What a reduction does to the tree is entirely decided by three facts the
//! press carried here for this purpose: a symbol's `Shape`, and a step's
//! `alias` and `field`. For each child of the production, left to right:
//!
//!   1. **A rename wins over the symbol's own shape.** `alias($._hidden,
//!      'name')` puts a node on the tree at one site while the symbol stays
//!      spliced everywhere else, so the alias is checked first. When the
//!      symbol was visible the node already exists and is *renamed in place* -
//!      an alias replaces a node, it does not wrap one. When it was invisible
//!      there is no node yet, so one is minted over whatever it spliced.
//!   2. **An invisible symbol splices.** `.hidden` (the author's underscore or
//!      a supertype) and `.invented` (our repeat helper) both contribute their
//!      children to the parent's child list and no node of their own. The two
//!      stay distinct so a consumer can tell whose idea an invisible symbol
//!      was, not so they render differently.
//!   3. **Otherwise the symbol's own name.** Named or anonymous per its shape.
//!
//! Splicing is therefore recursive without any recursion here: a hidden
//! child's own reduction already spliced whatever it was hiding, so its frame
//! holds the finished list.
//!
//! The field is orthogonal to all three. It files the node the step produced,
//! or - when the step spliced - *every* child spliced in from it. That last
//! rule is load-bearing rather than an edge case:
//! `repeat(seq(',', field('init', $.expression)))` lowers to an invented list
//! symbol, and the children it splices in are the ones that have to carry
//! `init`.
//!
//! ## Where an extra lands
//!
//! A comment is a node on the tree, and which parent owns it is not a matter
//! of taste. The rule below was read off tree-sitter 0.26.11's own trees with
//! probe grammars written for the question (`.local/orchestrate/extras.report.md`),
//! not inferred from what looks natural:
//!
//!   1. An extra goes on the stack **where it was read**, before any fold the
//!      token after it triggers.
//!   2. A reduction takes every extra lying **between** its first and last
//!      symbol. Extras past its last symbol stay on the stack for whatever
//!      reduces next.
//!   3. So an extra belongs to the deepest node that still has a token of its
//!      own after it. A comment after a node's last token is its parent's,
//!      recursively - which is why `{ x # c\n} # d` puts `# c` inside the
//!      braces and `# d` outside them.
//!   4. An extra never carries a field, even spliced in from a step that has
//!      one; tree-sitter's field map is indexed by structural child, and an
//!      extra is not one.
//!   5. Acceptance is not a reduction: see `crown`.
//!
//! Rule 2 is the whole of it, and it falls out of the perches for free. Each
//! perch keeps the extras read *before* its own symbol, so the ones a reduction
//! owns are the leads of its second symbol onwards, and the ones it must leave
//! behind are the ones no symbol has claimed yet.
//!
//! ## Spans
//!
//! A node spans from the first byte of its first token to the last byte of its
//! last, taken from the frames rather than from the child nodes. The
//! difference shows up exactly where it matters: a token that produced no node
//! (an inline regex is `.invented`) still consumed bytes, and the rule
//! containing it covers them. The root is the one exception, and `crown` is
//! where it is made.

const std = @import("std");
const g = @import("../../press/grammar.zig");
const lr0 = @import("../../press/lr0.zig");
const lalr = @import("../../press/lalr.zig");
const settle = @import("../../press/settle.zig");
const lex = @import("../lex/scanner.zig");
const quire = @import("quire.zig");
const graft = @import("graft.zig");
const bough = @import("bough.zig");

pub const Quire = quire.Quire;
pub const Stop = quire.Stop;
pub const Token = lex.Token;
pub const Graft = graft.Graft;
pub const Bough = bough.Bough;

/// The stack, and its parts. Defined next door because keeping a stretch of it
/// across an edit is a job of its own; see `bough.zig`.
const Mark = bough.Mark;
const Run = bough.Run;
const Perch = bough.Perch;
const Stand = bough.Stand;

/// One thing the parse did to the stack, in the order it did it.
///
/// The parse is the only honest source of this. An effect can be *derived* from
/// a state and a token run, but only by re-exploring every reading the table
/// allows and hoping one of them is the one that happened; here the parse
/// simply says. That difference is the whole reason this is four bytes on a
/// hot path rather than a second automaton walk: a trail is exact, single
/// valued, and free.
///
/// Off unless a caller sets `Gather.trail`, and abandoned the moment a fork
/// stands, because moves from two readings interleaved are not a file's moves.
pub const Move = union(enum) {
    /// A reduction: the state the right-hand side was standing on, and the
    /// rule folded. Everything `effect.reduce` needs.
    fold: struct { under: u32, prod: u32 },
    /// A symbol put on the stack in `at`, and the bytes it covers. A lifted
    /// subtree is one of these too, carrying a nonterminal - which is exactly
    /// what it is, a symbol the parse acquired without deriving it. `from` is
    /// where the symbol's own bytes begin, which is past the whitespace the
    /// segment ending here also covers; only a lift needs to tell them apart.
    read: struct { at: u32, symbol: g.Symbol, from: u32, end: u32 },
    /// A wall, and the byte the parse began reading again at. Not a move the
    /// stack made - it is the parse declining to make one - but the trail is
    /// the record of what happened between two bytes, and what happened here
    /// is that the run to the left and the run to the right were never
    /// adjacent. Anything folding the trail has to be told, or it will compose
    /// across the break and be refused with nothing to say about why.
    mend: struct { at: u32 },
};


/// What a parse does with a token it cannot read.
///
/// A buffer under edit is broken most of the time - between `if (` and `if (x)`
/// every intermediate state is invalid - so stopping at the first refusal
/// throws away the whole suffix, which in an editor is everything below the
/// caret. These are the three answers, and none of them invents a node: the
/// difference is only what happens to the stack that was standing.
pub const Mend = enum {
    /// Report the stop and hand back what completed. What this loop did before
    /// recovery existed, and what a caller asks for when it wants the forest
    /// to end where the reason does.
    none,
    /// Drop the token and carry the standing stack on. One token deleted, the
    /// context kept - `fn f() {` is still open - so the suffix is read as what
    /// it is rather than as a fresh file. Cascades where the stack itself is
    /// what is wrong, since every later token is refused by the same frame.
    keep,
    /// Fell the standing stack into roots and begin again in state zero at the
    /// next byte. Cannot cascade, because there is no context left to be wrong;
    /// pays for it by reading the suffix out of context. The default, because
    /// over the thirty-grammar corpus it is the one that places the most and
    /// the only one with no shape of file it does badly on.
    fell,
    /// Keep once, and fell if the keep does not take. The stack is given the
    /// benefit of one token and no more.
    relent,
};

/// One reading of the file so far: its top perch, and how far it has strayed
/// from what the table alone would have said.
const Reading = struct {
    top: u32,
    /// How many declared conflicts this reading took the losing side of. Zero
    /// is the deterministic LR answer, and it wins every tie.
    rank: u32 = 0,
};

/// A reading waiting to move, and the action it was split into taking. `act` is
/// null for the ordinary case of asking the table.
const Turn = struct {
    top: u32,
    rank: u32,
    act: ?lalr.Action = null,
};

/// One way of spelling an extra the grammar declared as a rule rather than as
/// a terminal - lua's `comment`, julia's `line_comment` - held as the
/// production that spells it.
///
/// The scanner cannot skip one of these, because skipping is what a scanner
/// does to a *token* and this is a subtree; so before this existed the first
/// `--` or `#` in a file was a stray byte at that offset and both grammars
/// reached nothing at all. The rule is also unreachable from the start symbol,
/// so the automaton has no state for it and no state ever offers its
/// terminals. Reading it is therefore the parse loop's, which is where the
/// scanner lane left it.
const Sprig = struct {
    prod: u32,
    /// The terminal that can begin it, hoisted so `offer` can admit it without
    /// reaching back into the production table on every token.
    first: g.Symbol,

    /// Every spelling of every rule-shaped extra this grammar has.
    ///
    /// All-terminal right-hand sides only. A rule extra that contains another
    /// rule needs a stack to read, and a stack is a parser; nothing in the
    /// corpus asks for one - lua's is `-- content` and `[[ content ]]`,
    /// julia's are `# .*` and `#= rest` - so the ones that would are declined
    /// here rather than half-read somewhere further in.
    fn all(gpa: std.mem.Allocator, gr: *const g.Grammar) ![]const Sprig {
        var out: std.ArrayList(Sprig) = .empty;
        errdefer out.deinit(gpa);
        for (gr.extras) |e| {
            if (gr.isTerminal(e)) continue;
            for (gr.productions, 0..) |p, i| {
                if (p.lhs != e or p.rhs.len == 0) continue;
                const flat = for (p.rhs) |sym| {
                    if (!gr.isTerminal(sym)) break false;
                } else true;
                if (flat) try out.append(gpa, .{ .prod = @intCast(i), .first = p.rhs[0] });
            }
        }
        return out.toOwnedSlice(gpa);
    }
};

/// An extra that has been read and shaped but not yet claimed by a perch,
/// waiting beside `keep` for the shift that files them both.
const Grown = struct { ref: quire.Ref, start: u32 };

/// The most readings held at once.
///
/// Not a tuning knob so much as a fuse. Refutation is what keeps the count
/// down: a losing reading is usually dead within a token or two, and this only
/// decides what happens where several conflicts overlap before any of them are
/// settled. Measured on the corpus by rebuilding at 2, 4 and 16: c needs more
/// than two readings at its widest point and cpp more than four, while sixteen
/// reaches no further than eight anywhere. So the fuse sits above the corpus's
/// high-water mark rather than at it. When it does bind, the reading that is
/// *not* forked is the most speculative one, so the table's own answer is never
/// the thing that gets dropped.
const crowd = 8;

/// How many times one file may be mended before the parse stops calling it a
/// file in this language. Every mend costs an `offer` over every terminal, so
/// a byte-by-byte walk through a megabyte of the wrong language is the one
/// shape recovery makes slow, and it is also the shape where the answer was
/// never going to be a tree. Well above anything a buffer under edit reaches:
/// the broken corpus needs one.
const ceiling = 1 << 14;

/// The first offset past `at` worth trying again from, when nothing lexed
/// there at all. One byte, unless `at` is inside a word, in which case the
/// whole word - the rest of an identifier is not a place a parse begins.
fn word(bytes: []const u8, at: u32) u32 {
    if (at >= bytes.len or !ident(bytes[at])) return at + 1;
    var n = at;
    while (n < bytes.len and ident(bytes[n])) n += 1;
    return n;
}

fn ident(c: u8) bool {
    return c == '_' or std.ascii.isAlphanumeric(c);
}

pub const Gather = struct {
    gpa: std.mem.Allocator,
    gr: *const g.Grammar,
    c: *const lr0.Collection,
    t: *const lalr.Tables,
    scanner: *lex.Scanner,

    /// Which cells the author declared ambiguous, and what the table dropped
    /// there. Empty for a grammar that declares nothing.
    forks: settle.Forks,
    /// Whether `forks` has anything in it at all, so the common grammar pays a
    /// predicted branch on a field rather than a load from a bitset.
    forking: bool,

    /// Every perch any reading is standing on. Index 0 is the ground.
    perches: std.ArrayList(Perch),
    /// Parallel to `perches`, and only while a grammar can fork at all.
    stand: std.ArrayList(Stand),
    /// Every node the perches are holding. A run handed to a perch is read by
    /// every reading that walks through it, so it may only be taken back while
    /// there is one reading to take it back from: see `lone`.
    borne: Run,
    /// The readings alive right now, ordered as they were spawned.
    live: std.ArrayList(Reading),
    /// One token's worth of readings waiting to move, and the ones that moved.
    /// Both are fields so a file's worth of tokens allocates once.
    work: std.ArrayList(Turn),
    next: std.ArrayList(Reading),
    /// The perches one reduction is popping, deepest first; and, in `roost`,
    /// the whole of the surviving chain.
    spine: std.ArrayList(Perch),
    /// Where `roost` rebuilds the stack before swapping it in.
    nest: std.ArrayList(Perch),
    crop: Run,
    /// What the winning reading was holding when the parse ended, in source
    /// order. The tree's roots.
    roots: Run,
    /// The tree under construction. Moved out whole by `finish`.
    nodes: std.ArrayList(quire.Node),
    kids: std.ArrayList(quire.Ref),
    /// Parallel to `kids`: what each child's place says about it. Spent by
    /// `bind` and not handed out, because a finished tree has one reading and
    /// the marks have nowhere left to disagree.
    marks: std.ArrayList(Mark),
    /// One reduction's finished child list. A field rather than a local so a
    /// file's worth of reductions allocates once.
    born: Run,
    /// `bind`'s worklist. A tree deep enough to matter is deeper than the
    /// machine stack is willing to be.
    descent: std.ArrayList(quire.Ref),
    /// Refilled once per token from the live readings' action rows.
    expected: lex.Scanner.Expected,
    /// What the scanner stepped over on the way to the last token.
    keep: std.ArrayList(Token),
    /// The extras the grammar spells as rules, and their all-terminal
    /// productions. Empty for every grammar that spells its comments as
    /// terminals, which is most of them.
    sprigs: []const Sprig,
    /// The ones read since the last shift, waiting alongside `keep`.
    grown: std.ArrayList(Grown),

    /// The token stream this run consumed, and the state it stood in when it
    /// read each one - before the folds that token triggered. Kept because
    /// this is the only place the stream exists: real terminals are
    /// context-dependent, so a token stream is a thing a parser produces
    /// rather than a thing it is handed. Borrowed, and valid until the next
    /// run.
    tokens: std.ArrayList(Token),
    enter: std.ArrayList(u32),

    /// A previous parse of nearly these bytes, when a caller has one. Null is
    /// the cold parse, and is the only shape this loop had before.
    graft: ?*Graft,
    /// Where to keep the stack as it goes, so the *next* parse can start in
    /// the middle. Written whenever a caller offers one; read only when a
    /// graft says where the edit was. See `bough.zig`.
    bough: ?*Bough,
    /// The ring this run stood back up on, null for one that began on the
    /// ground. Everything a caller keeps alongside the parse - a trail, a
    /// leaf list, alignment marks - is prefixed by the run that took the
    /// snapshot, so this is where the caller picks its own arrays up again.
    stood: ?Bough.Ring,
    /// Where to record the moves, when a caller wants the parse's own account
    /// of what it did rather than a re-derivation of it.
    trail: ?*std.ArrayList(Move),
    /// Whether a fork stood while `trail` was being written, which makes the
    /// record one file's moves interleaved with a reading that is not the
    /// file's. Sticky: the trail cannot be repaired, only refused.
    torn: bool,

    /// Where the last token ended. Where a rule that consumed nothing sits.
    at: u32,
    /// Whether one reading is the only reading. While that holds the graph is
    /// a stack, the perches a reduction pops are the topmost ones, and their
    /// runs are the top of `borne` - so both can be taken back the way the
    /// flat arrays this loop used to keep were, and a grammar that declares no
    /// conflict never grows either. It stops holding for exactly as long as a
    /// fork is unrefuted.
    lone: bool,
    /// Whether the arrays hold anything but the one chain. A fork's loser
    /// leaves its perches and its runs scattered through them, so the survivor
    /// is no longer standing on the top of anything until `roost` says it is.
    grafted: bool,
    /// The extras read before the current token and claimed by nobody yet:
    /// `borne[lead..][0..leads]`. Read once and shared by every reading, which
    /// is safe precisely because Rule 4 keeps an extra out of every field map -
    /// nothing downstream ever writes to one.
    lead: u32,
    leads: u32,
    /// The token leaf of the token being absorbed, minted once and shared for
    /// the same reason.
    held: u32,
    helds: u32,
    /// Whether `stow` has already laid this token's run down.
    stowed: bool,
    /// Where the table's own reading died, and what it was holding. A refusal
    /// is reported from there rather than from a speculation, since a stack
    /// that took the losing side of a conflict is a worse explanation of the
    /// file than the one that did not.
    refused: u32,
    spent: u32,

    /// What to do about a token the parse cannot read. Off is the answer this
    /// loop gave before recovery existed, and is still the answer for anyone
    /// who has not asked for another.
    mend: Mend,
    /// How many times it has done it, and the stop it would have reported the
    /// first time. A file that needed no mending reports and behaves exactly
    /// as it did.
    mends: u32,
    why: ?quire.Stop,
    /// Whether the last mend kept the stack rather than felling it. Read only
    /// by `relent`, and cleared by any token that shifts, so the benefit of
    /// the doubt is per refusal rather than per file.
    kept: bool,

    pub fn init(
        gpa: std.mem.Allocator,
        gr: *const g.Grammar,
        c: *const lr0.Collection,
        t: *const lalr.Tables,
        scanner: *lex.Scanner,
    ) !Gather {
        std.debug.assert(gr.field_names.len < Mark.none);
        std.debug.assert(gr.aliases.len < Mark.none);
        var forks = try settle.Forks.of(gpa, t.conflicts, c.states.len, t.width);
        errdefer forks.deinit(gpa);
        const sprigs = try Sprig.all(gpa, gr);
        errdefer gpa.free(sprigs);
        return .{
            .gpa = gpa,
            .gr = gr,
            .c = c,
            .t = t,
            .scanner = scanner,
            .forks = forks,
            .forking = forks.count() > 0,
            .perches = .empty,
            .stand = .empty,
            .borne = .{},
            .live = .empty,
            .work = .empty,
            .next = .empty,
            .spine = .empty,
            .nest = .empty,
            .crop = .{},
            .roots = .{},
            .nodes = .empty,
            .kids = .empty,
            .marks = .empty,
            .born = .{},
            .descent = .empty,
            .expected = try scanner.expecting(gpa),
            .keep = .empty,
            .sprigs = sprigs,
            .grown = .empty,
            .tokens = .empty,
            .enter = .empty,
            .graft = null,
            .bough = null,
            .stood = null,
            .trail = null,
            .torn = false,
            .at = 0,
            .lone = true,
            .grafted = false,
            .lead = 0,
            .leads = 0,
            .held = 0,
            .helds = 0,
            .stowed = false,
            .refused = 0,
            .spent = 0,
            .mend = .fell,
            .mends = 0,
            .why = null,
            .kept = false,
        };
    }

    pub fn deinit(x: *Gather) void {
        x.forks.deinit(x.gpa);
        x.perches.deinit(x.gpa);
        x.stand.deinit(x.gpa);
        x.borne.deinit(x.gpa);
        x.live.deinit(x.gpa);
        x.work.deinit(x.gpa);
        x.next.deinit(x.gpa);
        x.spine.deinit(x.gpa);
        x.nest.deinit(x.gpa);
        x.crop.deinit(x.gpa);
        x.roots.deinit(x.gpa);
        x.born.deinit(x.gpa);
        x.nodes.deinit(x.gpa);
        x.kids.deinit(x.gpa);
        x.marks.deinit(x.gpa);
        x.descent.deinit(x.gpa);
        x.expected.deinit(x.gpa);
        x.keep.deinit(x.gpa);
        x.gpa.free(x.sprigs);
        x.grown.deinit(x.gpa);
        x.tokens.deinit(x.gpa);
        x.enter.deinit(x.gpa);
        x.* = undefined;
    }

    /// Parse `bytes` into a tree. A parse that stopped early still hands back
    /// everything it had completed, as a forest, with `Quire.stop` saying
    /// where it stopped and why.
    pub fn run(x: *Gather, bytes: []const u8) !Quire {
        x.bare();
        x.roots.clear();
        x.mends = 0;
        x.why = null;
        x.kept = false;
        x.torn = false;
        x.lone = true;
        x.grafted = false;
        x.lead = 0;
        x.leads = 0;
        x.refused = 0;
        x.spent = 0;
        x.stood = null;
        if (x.bough) |b| {
            if (try x.alight(b, bytes)) |i| x.stood = try x.remount(b, i);
        }
        if (x.stood == null) try x.ground();

        while (true) {
            x.offer();
            const here = x.perches.items[x.first().top].state;
            x.stowed = false;
            const step = try x.scanner.nextKeeping(x.gpa, bytes, x.at, &x.expected, &x.keep);
            const tok: Token = switch (step) {
                .end => {
                    const won = try x.close();
                    try x.stow(null);
                    try x.unwind(won.top);
                    // A file that needed mending was not accepted, whatever the
                    // last segment did, and its roots are the whole forest
                    // rather than one crown over the last of them.
                    if (won.ok and x.mends == 0) try x.crown(won.top, @intCast(bytes.len));
                    return x.finish(x.why orelse if (won.ok) .accepted else .truncated);
                },
                // Nothing this parse can use is here. Ask once more with the
                // narrowing stood down before calling it a stray byte: a
                // person wants to be told that 535 held a `{`, and the token
                // the wide slate names goes on to be refused through the same
                // path as any other, so a truncated parse salvages what it
                // always salvaged.
                .stray => |off| (if (x.blame(bytes)) |bt| both: {
                    var shifts: u32 = 0;
                    var acts: u32 = 0;
                    const n: u32 = @intCast(x.t.action.len / x.t.width);
                    for (0..n) |st| {
                        const c = x.t.at(@intCast(st), bt.symbol);
                        if (c.kind != .err) acts += 1;
                        if (c.kind == .shift) shifts += 1;
                    }
                    std.debug.print("PROBE blame at={d} named sym={d}; over {d} states sym has {d} actions, {d} shifts; 616 goto-in? {d}\n", .{ off, bt.symbol, n, acts, shifts, @intFromBool(x.t.at(616, bt.symbol).kind != .err) });
                    break :both bt;
                } else null) orelse {
                    // No terminal begins here under any state, so there is no
                    // token to delete. A word is stepped over whole even so:
                    // resuming inside `return` reads `eturn` as an identifier,
                    // and a node over half a word is worse than no node.
                    const stop: quire.Stop = .{ .stray = off };
                    if (try x.mended(stop, x.first().top, word(bytes, off))) continue;
                    try x.stow(null);
                    try x.unwind(x.first().top);
                    return x.finish(x.why orelse stop);
                },
                .token => |t| t,
            };

            if (try x.sprout(tok, bytes)) continue;
            if (try x.lift(here, tok)) continue;
            if (!try x.absorb(tok)) {
                const stop: quire.Stop = .{ .unexpected = .{
                    .symbol = tok.symbol,
                    .at = tok.start,
                    // The state that refused it, which is where the folds ran
                    // out - not `here`, where they started.
                    .state = x.refused,
                } };
                if (try x.mended(stop, x.spent, tok.end())) continue;
                // The token was refused, so nothing shifted and its leaf is
                // never made - but the extras read on the way to it were
                // read, and they are the forest's as much as a trailing
                // comment is.
                try x.stow(null);
                try x.unwind(x.spent);
                return x.finish(x.why orelse stop);
            }
            try x.tokens.append(x.gpa, tok);
            try x.enter.append(x.gpa, here);
            x.kept = false;
            const was = x.at;
            x.at = tok.end();
            // A ring is a promise that a later parse can stand up where this
            // one stood. Past a mend this run's own roots are no longer only
            // what the chain is holding, so it is not a promise to make.
            if (x.mends == 0) if (x.bough) |b| if (b.tick()) try x.limb(b, was);
        }
    }

    /// Take the standing stack away, leaving the tree it built alone.
    ///
    /// The four arrays a reading stands in, and nothing else. `run` opens with
    /// this because a `Gather` is reused across files; a mend calls the same
    /// four lines mid-file, which is the whole of what "begin again here"
    /// means once the roots have been carried off.
    fn bare(x: *Gather) void {
        x.perches.clearRetainingCapacity();
        x.stand.clearRetainingCapacity();
        x.borne.clear();
        x.live.clearRetainingCapacity();
    }

    /// Carry on past something the parse could not read, or say it will not.
    ///
    /// True means the offset moved and the loop should go round again; false
    /// means the caller reports its stop exactly as it did before recovery
    /// existed. `over` is the first byte after whatever is being stepped past,
    /// and it is always past `x.at`, so a file cannot be mended forever.
    ///
    /// Nothing is invented. `keep` re-seats the one reading on the perch the
    /// refusal left standing - which is the top of the array in either engine,
    /// since a fold pushes and a shift pushes - and reads on. `fell` carries
    /// the standing chain into the roots with the same `unwind` that ends any
    /// truncated parse, then bares the stack and stands one perch back up in
    /// state zero, which is `ground` minus the parts that belong to a file
    /// rather than to a segment. The forest afterwards is what completed
    /// before the break followed by what completes after it, and the bytes
    /// under no root are the bytes no reading could place - a gap being the
    /// absence of a root rather than a node claiming to be one.
    fn mended(x: *Gather, stop: quire.Stop, top: u32, over: u32) !bool {
        if (x.mend == .none or x.mends >= ceiling) return false;
        if (x.why == null) x.why = stop;
        x.mends += 1;

        const fell = switch (x.mend) {
            .none => unreachable,
            .keep => false,
            .fell => true,
            // The stack is given the benefit of one token. A second refusal
            // with nothing shifted in between is the stack saying it is the
            // thing that is wrong.
            .relent => x.kept,
        };
        x.kept = !fell;

        if (fell) {
            try x.stow(null);
            try x.unwind(top);
            x.bare();
            // State zero with a fence still open is half a reset: the fence
            // was opened by a token the stack that just went held, so a parse
            // that says "a file begins here" has to say it to both halves.
            // `keep` says the opposite and keeps both.
            x.scanner.rewind();
            x.lead = 0;
            x.leads = 0;
            _ = try x.push(0, .{
                .state = 0,
                .own = 0,
                .owns = 0,
                .lead = 0,
                .leads = 0,
                .start = over,
                .end = over,
            });
            try x.live.append(x.gpa, .{ .top = 0 });
            x.lone = true;
            x.grafted = false;
        } else {
            x.live.clearRetainingCapacity();
            try x.live.append(x.gpa, .{ .top = top });
            x.lone = true;
        }
        // A mend is not a move the stack made, but it is a thing that happened
        // at a byte, and the trail is what happened. Recorded rather than
        // tearing the record, so the fold over it can put a hole where the
        // parse put one instead of composing across it.
        //
        // After the unwind, not before: `fell` closes the standing stack with
        // real folds, and those belong to the run on the *left* of the break.
        // Recorded first, they land on the right of it and get composed into a
        // run whose base they pop straight through.
        if (x.trail) |tr| try tr.append(x.gpa, .{ .mend = .{ .at = over } });
        x.at = over;
        return true;
    }

    /// Put the parse on the ground: one perch holding nothing, in state zero.
    fn ground(x: *Gather) !void {
        x.nodes.clearRetainingCapacity();
        x.kids.clearRetainingCapacity();
        x.marks.clearRetainingCapacity();
        x.tokens.clearRetainingCapacity();
        x.enter.clearRetainingCapacity();
        if (x.trail) |tr| tr.clearRetainingCapacity();
        if (x.bough) |b| b.clear();
        x.at = 0;
        _ = try x.push(0, .{
            .state = 0,
            .own = 0,
            .owns = 0,
            .lead = 0,
            .leads = 0,
            .start = 0,
            .end = 0,
        });
        try x.live.append(x.gpa, .{ .top = 0 });
    }

    /// Which kept ring this parse may stand back up on, if any.
    ///
    /// A hand-written external scanner remembers things between tokens - a
    /// column stack, an open heredoc, rust's block-comment nesting depth,
    /// cpp's captured raw-string delimiter - so the byte offset alone does not
    /// say what it will read next, and standing up at an offset without that
    /// memory would lex the suffix wrongly. This used to refuse outright for
    /// any grammar with a cast, which was every layout-sensitive one. The
    /// scanner now hands its memory over as an opaque `Save`, so the ring
    /// carries it and `remount` puts it back; the refusal is gone and rust and
    /// cpp resume like json does.
    ///
    /// The rest is `holds`, and a ring that does not hold gives way to the one
    /// below it. Two attempts is nearly always enough, because the reason a
    /// ring fails is that the edit landed exactly on it.
    fn alight(x: *Gather, b: *const Bough, bytes: []const u8) !?u32 {
        const gr = x.graft orelse return null;
        if (gr.firm == 0 or b.rings.items.len == 0) return null;
        // A resume that believes a snapshot because it exists: no `firm`, no
        // re-lex, just the newest stack there is. The control for both checks.
        if (gr.trusting) {
            const last: u32 = @intCast(b.rings.items.len - 1);
            return if (x.fits(b.rings.items[last])) last else null;
        }

        var i = b.before(gr.firm) orelse return null;
        var tries: u32 = 4;
        while (tries > 0) : (tries -= 1) {
            if (x.fits(b.rings.items[i]) and try x.holds(b, i, bytes)) return i;
            if (i == 0) return null;
            i -= 1;
        }
        return null;
    }

    /// Whether this ring is a snapshot of the parse now on offer.
    ///
    /// It always is, and the check is here because "always" is a property of
    /// two modules agreeing rather than of one type: a ring is a set of
    /// high-water marks, and a mark taken over a different tree names memory
    /// that tree never had. Cheap enough to pay per resume, and the alternative
    /// to paying it is a wild write rather than a wrong tree.
    inline fn fits(x: *const Gather, r: Bough.Ring) bool {
        const old = x.graft.?.old;
        return r.nodes <= old.nodes.len and r.kids <= old.kids.len and
            r.token <= x.tokens.items.len and r.token <= x.enter.items.len and
            r.trail <= (if (x.trail) |tr| tr.items.len else 0);
    }

    /// Whether the kept stream still reads out of the new bytes the way it was
    /// recorded, over the stretch between this ring and the one below it.
    ///
    /// A token's extent is a function of the bytes *after* it as well as the
    /// ones under it: maximal munch stops where the automaton dies, so a byte
    /// typed at a boundary can lengthen the token that ended there. That is the
    /// ordinary edit - appending to a word - and it is why "the edit is past
    /// this offset" is not on its own a licence to keep what is below it.
    ///
    /// Exact lookahead per token would answer this outright and it lives in the
    /// scanner, which is not this module's. Re-reading is the answer that needs
    /// nothing from it: drive the recorded states over the new bytes and demand
    /// the same tokens back. What that leaves unproved is a token whose scan
    /// reaches beyond a whole ring's worth of text, which no tokenizer in the
    /// corpus does and none of them could do cheaply; the parse pays a stride's
    /// worth of lexing - tens of tokens, microseconds - to hold the rest.
    ///
    /// A lifted nonterminal in the stream is stepped over rather than re-read.
    /// There is nothing to lex: it stands over bytes that did not move, and the
    /// token in front of it is re-read like any other, which is what would
    /// catch it being reached into.
    fn holds(x: *Gather, b: *const Bough, i: u32, bytes: []const u8) !bool {
        const r = b.rings.items[i];
        const back: struct { at: u32, token: u32 } = if (i == 0)
            .{ .at = 0, .token = 0 }
        else
            .{ .at = b.rings.items[i - 1].at, .token = b.rings.items[i - 1].token };
        if (r.token > x.tokens.items.len or r.token > x.enter.items.len) return false;

        // The stretch is re-lexed from the ring below, so the scanner has to
        // be standing where *that* ring left it - not where the attempt this
        // one is replacing did. Only for a scanner that remembers anything;
        // the rest are untouched, and so is what they answer.
        if (x.scanner.casts.len > 0) {
            if (i == 0) x.scanner.rewind() else if (b.save(i - 1)) |sv| x.scanner.restore(sv);
        }

        var at = back.at;
        for (x.tokens.items[back.token..r.token], x.enter.items[back.token..r.token]) |want, state| {
            if (want.symbol >= x.gr.terminal_count) {
                if (want.start != at) return false;
                at = want.end();
                continue;
            }
            x.expected.clear(x.scanner);
            for (0..x.gr.terminal_count) |sym| {
                if (x.t.at(state, @intCast(sym)).kind != .err) x.expected.admit(x.scanner, @intCast(sym));
            }
            x.keep.clearRetainingCapacity();
            switch (try x.scanner.nextKeeping(x.gpa, bytes, at, &x.expected, &x.keep)) {
                .token => |got| {
                    if (got.symbol != want.symbol or got.start != want.start or got.len != want.len) {
                        return false;
                    }
                    at = got.end();
                },
                else => return false,
            }
        }
        return at == r.at;
    }

    /// Stand the parse back up on a kept ring, and say which one.
    ///
    /// Everything the loop appends to is an array that only grows, so restoring
    /// one is truncating it - except the tree's own arena, which belongs to the
    /// parse that is being replaced. That one is copied. It is the whole cost
    /// of the flat arena, the same tax `transcribe` pays per lift, and it is a
    /// `memcpy` where the alternative is a parse.
    fn remount(x: *Gather, b: *Bough, i: u32) !Bough.Ring {
        const r = b.rings.items[i];
        const old = x.graft.?.old;
        // `holds` left the scanner at this ring's offset by driving it there,
        // but only along the path it happened to take; the kept memory is the
        // authority, and putting it back makes the resume independent of how
        // many rings were tried on the way.
        if (b.save(i)) |sv| x.scanner.restore(sv);

        x.nodes.clearRetainingCapacity();
        try x.nodes.appendSlice(x.gpa, old.nodes[0..r.nodes]);
        x.kids.clearRetainingCapacity();
        try x.kids.appendSlice(x.gpa, old.kids[0..r.kids]);
        // The prefix's marks were spent into those nodes by the parse that
        // made them, and a mark that says nothing changes nothing, so the
        // places under the restored kids are blank rather than lost.
        x.marks.clearRetainingCapacity();
        if (x.forking) try x.marks.appendNTimes(x.gpa, .{}, r.kids);

        x.tokens.shrinkRetainingCapacity(r.token);
        x.enter.shrinkRetainingCapacity(r.token);
        if (x.trail) |tr| tr.shrinkRetainingCapacity(r.trail);

        try x.perches.appendSlice(x.gpa, b.chain(i));
        const stack = b.run(i);
        try x.borne.ref.appendSlice(x.gpa, stack.ref);
        // The stack's own nodes, as they stood before the reductions that came
        // after this ring wrote fields and renames into them. See `Bough.held`.
        for (stack.ref, b.borne(i)) |ref, n| x.nodes.items[ref] = n;
        if (x.forking) {
            try x.borne.mark.appendSlice(x.gpa, stack.mark);
            // The chain is the array, so the links are the indices - the same
            // shape `roost` leaves behind, and for the same reason.
            for (0..x.perches.items.len) |j| {
                try x.stand.append(x.gpa, .{ .down = @intCast(j -| 1), .depth = @intCast(j) });
            }
        }
        try x.live.append(x.gpa, .{ .top = @intCast(x.perches.items.len - 1) });

        x.at = @intCast(@as(i64, r.at) + x.graft.?.adrift);
        b.trim(i + 1);
        return r;
    }

    /// Keep this boundary, if the stack standing at it is one a later parse
    /// could be handed.
    ///
    /// Two conditions. The stack has to be settled - one reading, nothing
    /// scattered - which is the same `lone and not grafted` that lets a lift
    /// stand, and on a grammar that declares no conflict it is every boundary.
    /// And the token has to have covered a byte, so the ring sits on a seam
    /// between two of the caller's segments rather than inside one.
    fn limb(x: *Gather, b: *Bough, was: u32) !void {
        if (!x.lone or x.grafted or x.live.items.len != 1) return;
        if (x.at == was) return;
        try b.keep(.{
            .at = x.at,
            .token = @intCast(x.tokens.items.len),
            .trail = if (x.trail) |tr| @intCast(tr.items.len) else 0,
            .nodes = @intCast(x.nodes.items.len),
            .kids = @intCast(x.kids.items.len),
            .perch = 0,
            .perched = 0,
            .ref = 0,
            .refed = 0,
        }, x.perches.items, x.borne.all(), x.nodes.items, x.remembers());
    }

    /// The scanner's own memory here, for a scanner that has one. A scanner
    /// with no casts is a pure function of the offset it is asked at, so there
    /// is nothing to keep and keeping nothing is cheaper than keeping a
    /// kilobyte of zeroes per ring.
    inline fn remembers(x: *const Gather) ?lex.Scanner.Save {
        return if (x.scanner.casts.len > 0) x.scanner.save() else null;
    }

    /// The least speculative reading alive. Every tie in this file goes to it,
    /// so a grammar that declares no conflicts, and a file that never reaches
    /// one, are answered by exactly the walk they were answered by before.
    inline fn first(x: *const Gather) Reading {
        var best = x.live.items[0];
        for (x.live.items[1..]) |v| {
            if (v.rank < best.rank) best = v;
        }
        return best;
    }

    fn finish(x: *Gather, why: Stop) !Quire {
        if (x.forking) try x.bind();
        const roots = try x.gpa.dupe(quire.Ref, x.roots.ref.items);
        errdefer x.gpa.free(roots);
        const nodes = try x.nodes.toOwnedSlice(x.gpa);
        errdefer x.gpa.free(nodes);
        return .{
            .gpa = x.gpa,
            .gr = x.gr,
            .nodes = nodes,
            .kids = try x.kids.toOwnedSlice(x.gpa),
            .roots = roots,
            .stop = why,
            .mends = x.mends,
        };
    }

    /// Spend the marks: write each node's rename, field and parent, once the
    /// tree it stands in is the only tree it stands in.
    ///
    /// Nothing here is new work - it is the same three writes `mint` makes on
    /// the spot when it can, deferred to the end when it cannot. It has to be
    /// deferred rather than merely repeated, because a rename is a write with
    /// no inverse: a losing reading that aliased a node to `type_identifier`
    /// leaves no way for the winner to say "call it whatever you were called".
    /// So where two readings can reach one node, neither writes until one of
    /// them has won, and this walks the winner.
    ///
    /// Which is why it runs only for a grammar that declares a conflict. Where
    /// the tables are unambiguous no second reading can exist, `mint` writes
    /// as it goes, and this second pass over the whole tree never happens.
    fn bind(x: *Gather) !void {
        x.descent.clearRetainingCapacity();
        for (x.roots.ref.items, x.roots.mark.items) |r, m| {
            x.wear(r, m);
            try x.descent.append(x.gpa, r);
        }
        while (x.descent.pop()) |ref| {
            const n = x.nodes.items[ref];
            const kids = x.kids.items[n.kids_at..][0..n.kids_len];
            for (kids, x.marks.items[n.kids_at..][0..n.kids_len]) |c, m| {
                x.nodes.items[c].parent = ref;
                x.wear(c, m);
            }
            try x.descent.appendSlice(x.gpa, kids);
        }
    }

    inline fn wear(x: *Gather, ref: quire.Ref, m: Mark) void {
        const n = &x.nodes.items[ref];
        if (m.alias != Mark.none) n.kind = .alias(m.alias);
        if (m.field != Mark.none) n.field = m.field;
    }

    /// Put a child on the end of a run, in its place.
    ///
    /// Where the grammar declares a conflict the place is recorded beside the
    /// run for `bind` to spend on whichever reading wins. Where it declares
    /// none there is only ever one reading, so it is spent here and the mark
    /// array stays empty for the whole parse.
    inline fn bear(x: *Gather, r: *Run, ref: quire.Ref, mark: Mark) !void {
        try r.ref.append(x.gpa, ref);
        if (x.forking) try r.mark.append(x.gpa, mark) else x.wear(ref, mark);
    }

    /// Copy a run of children onward, marks and all. This is the splice, and
    /// the one loop whose width the whole parse feels.
    inline fn carry(x: *Gather, r: *Run, s: Run.Slice) !void {
        std.debug.assert(!x.forking or s.mark.len == s.ref.len);
        try r.ref.appendSlice(x.gpa, s.ref);
        if (x.forking) try r.mark.appendSlice(x.gpa, s.mark);
    }

    /// The terminals the live readings could actually shift - tree-sitter's
    /// valid-symbol set, read off the table rather than maintained beside it.
    /// The union, because the scanner reads one stream for all of them.
    ///
    /// "Could shift", not "has a cell for". A non-error cell is not a lexing
    /// permission: a reduce action says the fold happens, not that the
    /// terminal survives it, and a lookahead can be in a state's reduce row
    /// and refused by every state that fold can land in. LALR merging widens
    /// those rows, but the phenomenon is not merge damage - it is in the
    /// intersection over every context in ten of bash's fourteen `\s+` folds,
    /// where no amount of state splitting, up to and including canonical
    /// LR(1), removes it. See `.local/orchestrate/frayed.report.md`.
    ///
    /// Handing such a terminal to the scanner is how a greedy whitespace or
    /// content pattern out-matches the token that was really there, and the
    /// parse dies several states later on a token it was told to read. So the
    /// question asked here is the one the caller means: run the folds this
    /// terminal would cause, over the stack that is actually standing, and see
    /// whether a shift is on the other side of them.
    fn offer(x: *Gather) void {
        x.expected.clear(x.scanner);
        for (x.live.items) |v| {
            for (0..x.gr.terminal_count) |sym| {
                if (x.shiftable(v.top, @intCast(sym))) x.expected.admit(x.scanner, @intCast(sym));
            }
        }
        // An extra may begin anywhere, and no state will ever say so, because
        // the rule that spells it is unreachable from the start symbol.
        for (x.sprigs) |s| x.expected.admit(x.scanner, s.first);
    }

    /// Read a rule-shaped extra whole, if one begins here.
    ///
    /// True means the offset moved and the parse never saw a token: an extra
    /// is not a symbol any state has an action for, so there is nothing for
    /// `absorb` to do with it. The node joins `grown` and is filed by the
    /// same `stow` that files a comment the scanner skipped, in the same
    /// order, under the same rules - which is the point. An extra is an extra
    /// however the grammar chose to spell it.
    ///
    /// Backtracking is free because nothing is committed until the whole
    /// production has matched: the offset is a local, the leaves are minted
    /// into `born`, and a spelling that fails leaves both where it found
    /// them. What it costs is one gated re-scan per remaining symbol, on the
    /// two grammars that have a sprig at all.
    fn sprout(x: *Gather, tok: Token, bytes: []const u8) !bool {
        for (x.sprigs) |s| {
            if (s.first != tok.symbol) continue;
            if (try x.grow(s, tok, bytes)) return true;
        }
        return false;
    }

    fn grow(x: *Gather, s: Sprig, tok: Token, bytes: []const u8) !bool {
        const p = x.gr.productions[s.prod];
        x.born.clear();
        var at = tok.start;
        for (p.rhs, p.steps) |sym, step| {
            const span: Token = if (at == tok.start and sym == tok.symbol) tok else read: {
                // Exactly one terminal is wanted here, so exactly one is
                // offered; a slate that admitted more would let a greedy
                // neighbour take the comment's own body.
                x.expected.clear(x.scanner);
                x.expected.admit(x.scanner, sym);
                switch (x.scanner.next(bytes, at, &x.expected)) {
                    .token => |got| {
                        if (got.symbol != sym or got.start != at) return false;
                        break :read got;
                    },
                    else => return false,
                }
            };
            at = span.end();

            // The recipe, minus the two cases a flat production cannot reach:
            // no symbol here carries children, so nothing is ever spliced and
            // no field ever has to reach past a splice to find them.
            const visible = x.gr.shapeOf(sym).visible();
            var mark: Mark = .{};
            const ref: ?quire.Ref = if (step.alias) |a| ref: {
                if (!visible) break :ref try x.mint(.alias(a), span.start, span.len, .{});
                mark.alias = @intCast(a);
                break :ref try x.mint(.of(sym), span.start, span.len, .{});
            } else if (visible) try x.mint(.of(sym), span.start, span.len, .{}) else null;
            if (step.field) |f| mark.field = @intCast(f);
            if (ref) |r| try x.bear(&x.born, r, mark);
        }

        const node = try x.mint(.aside(p.lhs), tok.start, at - tok.start, x.born.all());
        try x.grown.append(x.gpa, .{ .ref = node, .start = tok.start });
        x.at = at;
        return true;
    }

    /// What is at `at` when the narrowed slate says nothing is.
    ///
    /// The set a parse offers is what it could shift, so a position holding a
    /// token this grammar can never use here reads back as an unreadable
    /// byte. That is true and it is useless. This asks the same question with
    /// only the table's permission - the old rule, exactly - and hands back
    /// whatever it names, for the loop to refuse in the ordinary way.
    ///
    /// It is the failure path and it runs once per parse, so the wide set is
    /// built here rather than kept beside the narrow one all file.
    ///
    /// Two tiers, and the second one is what makes `Stop.stray` mean what it
    /// says. Asking with the table's permission is asking a *narrowed* question:
    /// a `{` that lexes perfectly well but that no live state has a cell for is
    /// refused by the slate and never lexed, so the byte comes back unreadable
    /// and the parse files it as a stray. That conflates two different walls -
    /// *no terminal in this grammar lexes here*, and *a terminal lexes here and
    /// no reading can use it* - and reports the lexical one for both. Every wall
    /// census downstream then reads a lexer verdict where the truth is a state
    /// verdict.
    ///
    /// So the filter comes off for a second ask. A token the whole grammar can
    /// see goes on to be refused through the ordinary path, where `absorb`
    /// names the symbol and the state that had no cell for it, and the verdict
    /// separates itself: `unexpected` is an unshiftable reading, `stray` is a
    /// byte nothing in the grammar lexes. Tier one stays because it names a
    /// *better* token where it answers - the one a state was actually waiting
    /// for, rather than whichever greedy pattern reaches furthest.
    fn blame(x: *Gather, bytes: []const u8) ?Token {
        // Every reading, not just the first: a fork's other branch is as much a
        // place this parse is standing as the branch that happens to be first,
        // and a terminal one of them permits is not a stray byte.
        x.expected.clear(x.scanner);
        var asked = false;
        for (x.live.items) |v| {
            if (v.top >= x.perches.items.len) continue;
            const here = x.perches.items[v.top].state;
            asked = true;
            for (0..x.gr.terminal_count) |sym| {
                if (x.t.at(here, @intCast(sym)).kind != .err) x.expected.admit(x.scanner, @intCast(sym));
            }
        }
        if (asked) {
            switch (x.scanner.next(bytes, x.at, &x.expected)) {
                .token => |tok| return tok,
                else => {},
            }
        }

        // Named, not lexed. This slate is every terminal the grammar has, which
        // is a set no state asked for, so the longest member of it is a fact
        // about the grammar rather than about the offset - see `Scanner.spot`.
        return switch (x.scanner.spot(bytes, x.at)) {
            .token => |tok| tok,
            else => null,
        };
    }

    /// Whether this reading could ever shift `sym`, following the folds the
    /// table names for it down the stack it is standing on.
    ///
    /// The walk is the deterministic prefix of what `absorb` would do, with
    /// nothing minted: folds are forced moves, so replaying them costs a few
    /// table reads and answers exactly. Where the table forks the walk takes
    /// the table's own action, which is the reading a refusal is reported
    /// from anyway.
    ///
    /// It gives up rather than guessing. A production that consumes nothing
    /// can push forever, so past `climb` pretend-perches or `chase` steps the
    /// answer is yes: admitting a terminal the parse then refuses is the old
    /// behaviour, and losing one it could have shifted would be a wrong tree.
    fn shiftable(x: *const Gather, top: u32, sym: g.Symbol) bool {
        const climb = 8;
        const chase = 32;
        // States pushed by folds the walk performed, standing on `base`. Only
        // these are popped before the real stack is touched.
        var up: [climb]u32 = undefined;
        var ups: usize = 0;
        var base = top;

        for (0..chase) |_| {
            const here = if (ups > 0) up[ups - 1] else x.perches.items[base].state;
            // Where the author declared the cell ambiguous there is a second
            // action this walk is not following, and `absorb` would split
            // rather than choose. One branch reaching a shift is enough to
            // make the terminal real, so a fork is a yes without looking.
            if (x.forking) if (x.forks.at(here, sym) != null) return true;
            const act = x.t.at(here, sym);
            switch (act.kind) {
                .err => return false,
                .shift, .accept => return true,
                .reduce => {
                    const p = x.gr.productions[act.value];
                    var n = p.rhs.len;
                    const virtual = @min(ups, n);
                    ups -= virtual;
                    n -= virtual;
                    if (n > 0) {
                        if (x.deep(base) < n) return false;
                        for (0..n) |_| base = x.below(base);
                    }
                    const under = if (ups > 0) up[ups - 1] else x.perches.items[base].state;
                    const to = x.c.goto(under, p.lhs) orelse return false;
                    if (ups == climb) return true;
                    up[ups] = to;
                    ups += 1;
                },
            }
        }
        return true;
    }

    /// Move every live reading over one token: fold until the token can be
    /// shifted, then shift it, splitting wherever the author declared the cell
    /// ambiguous. False means the token refuted every reading at once, which is
    /// the only kind of refusal a parse can report.
    ///
    /// Readings are held on a worklist rather than iterated, because a split
    /// makes a new one *mid-fold* and it has to be driven over the same token
    /// before the loop can be done with it. The worklist is also where the cap
    /// is enforced, and it is enforced by declining to split rather than by
    /// evicting: the reading in hand always has at least as good a claim as the
    /// one being considered.
    fn absorb(x: *Gather, tok: Token) !bool {
        if (!x.forking) return x.alone(tok);
        x.work.clearRetainingCapacity();
        x.next.clearRetainingCapacity();
        for (x.live.items) |v| try x.work.append(x.gpa, .{ .top = v.top, .rank = v.rank });
        x.lone = x.work.items.len == 1 and !x.grafted;

        var i: usize = 0;
        while (i < x.work.items.len) : (i += 1) {
            var top = x.work.items[i].top;
            const rank = x.work.items[i].rank;
            var forced = x.work.items[i].act;
            while (true) {
                const state = x.perches.items[top].state;
                const act = forced orelse take: {
                    if (x.forking and x.next.items.len + x.work.items.len - i < crowd) {
                        if (x.forks.at(state, tok.symbol)) |other| {
                            try x.work.append(x.gpa, .{ .top = top, .rank = rank + 1, .act = other });
                            // The perch just handed to the new reading has to
                            // still be there when its turn comes, so nothing
                            // may be taken back from here on.
                            x.lone = false;
                            x.grafted = true;
                            // Two readings' moves interleaved are not the
                            // file's moves, and no later collapse makes the
                            // record retrospectively true.
                            x.torn = true;
                        }
                    }
                    break :take x.t.at(state, tok.symbol);
                };
                forced = null;
                if (rank == 0 and tok.symbol == 38) std.debug.print(
                    "PROBE chain state={d} act={s} fork={}\n",
                    .{ state, @tagName(act.kind), x.forks.at(state, tok.symbol) != null },
                );
                switch (act.kind) {
                    .err => {
                        // Refuted. Only the table's own reading is worth
                        // reporting from, and only if it is the one that died.
                        if (rank == 0) {
                            x.refused = state;
                            x.spent = top;
                        }
                        break;
                    },
                    .shift => {
                        try x.next.append(x.gpa, .{ .top = try x.perch(top, act.value, tok), .rank = rank });
                        break;
                    },
                    .reduce => top = try x.fold(top, act.value) orelse {
                        if (rank == 0) {
                            x.refused = state;
                            x.spent = top;
                        }
                        break;
                    },
                    // Accept is only in the end column, which `absorb` is never
                    // called with; treat it as "nothing further to shift".
                    .accept => {
                        try x.next.append(x.gpa, .{ .top = top, .rank = rank });
                        break;
                    },
                }
            }
        }
        if (x.next.items.len == 0) {
            var sprig = false;
            for (x.sprigs) |sp| {
                if (sp.first == tok.symbol) sprig = true;
            }
            for (x.live.items) |v| std.debug.print(
                "PROBE fork-refuse sym={d} at={d} refused={d} start_top={d} start_state={d} shiftable={} fork={} sprig={}\n",
                .{ tok.symbol, tok.start, x.refused, v.top, x.perches.items[v.top].state, x.shiftable(v.top, tok.symbol), x.forks.at(x.perches.items[v.top].state, tok.symbol) != null, sprig },
            );
            return false;
        }
        x.live.clearRetainingCapacity();
        try x.live.appendSlice(x.gpa, x.next.items);
        if (x.grafted and x.live.items.len == 1) try x.roost();
        return true;
    }

    /// The same move over a grammar whose tables cannot fork, where there is
    /// one reading and there can never be a second.
    ///
    /// Not an optimisation of the loop above so much as the absence of it: no
    /// worklist, because nothing can be added to one; no rank, because there
    /// is nothing to be more speculative than; no set of survivors, because
    /// the survivor is the reading. What is left is the textbook LR drive,
    /// which is what json runs and what it ran before any of this existed.
    inline fn alone(x: *Gather, tok: Token) !bool {
        var top = x.live.items[0].top;
        while (true) {
            const state = x.perches.items[top].state;
            const act = x.t.at(state, tok.symbol);
            switch (act.kind) {
                .err => {
                    x.refused = state;
                    x.spent = top;
                    return false;
                },
                .shift => top = try x.perch(top, act.value, tok),
                // Accept is only in the end column, which `absorb` is never
                // called with; treat it as "nothing further to shift".
                .accept => {},
                .reduce => {
                    top = try x.fold(top, act.value) orelse {
                        // A fold the table names but the stack cannot make is
                        // a refusal too, and `unwind` needs a perch that is
                        // still standing to report it from.
                        x.refused = state;
                        x.spent = top;
                        return false;
                    };
                    continue;
                },
            }
            x.live.items[0].top = top;
            return true;
        }
    }

    /// Take a whole subtree from the previous parse instead of reading the
    /// bytes under it. True means the offset moved and this token was never
    /// absorbed at all.
    ///
    /// The refusals are all cheap and all silent, because a lift is an
    /// optimisation and a declined one costs an ordinary parse: no graft, a
    /// fork standing, an offset the old parse did not read from this state, no
    /// node beginning there, a symbol this state has no goto for. Only the
    /// last of those is about the grammar, and it is the table saying the
    /// old derivation is not one this parse could have made - which is the
    /// answer, not an error.
    fn lift(x: *Gather, _: u32, tok: Token) !bool {
        const gr = x.graft orelse return false;
        if (!gr.lifting) return false;
        // A lift standing on one of several readings hands its nodes to a
        // reading that has not earned them, and `roost` has no way to take
        // them back. The settled stack is the only place this is sound, and on
        // a conflict-free grammar it is every place.
        if (x.live.items.len != 1 or x.grafted) return false;
        const here = try x.ready(tok) orelse return false;
        if (!gr.aligned(tok.start, here)) return false;
        gr.probes += 1;

        for (try gr.stoop(tok.start)) |ref| {
            const sym = gr.liftable(ref) orelse continue;
            const wide = gr.old.nodes[ref].len;
            // One token's worth is a copy with extra steps, and the chain is
            // ordered widest first, so nothing further in is worth trying.
            if (wide <= tok.len) break;
            const to = x.c.goto(here, sym) orelse continue;

            const top = x.live.items[0].top;
            try x.stow(null);
            const root = try x.transcribe(gr, ref);
            const own = x.borne.len();
            try x.bear(&x.borne, root, .{});
            const end = tok.start + wide;
            x.live.items[0].top = try x.push(top, .{
                .state = to,
                .own = own,
                .owns = 1,
                .lead = x.lead,
                .leads = x.leads,
                .start = tok.start,
                .end = end,
            });
            if (x.trail) |tr| try tr.append(x.gpa, .{
                .read = .{ .at = here, .symbol = sym, .from = tok.start, .end = end },
            });
            // The stream this parse consumed, with one symbol standing for the
            // tokens it did not read. Which is what happened: a symbol
            // acquired in one move, over exactly those bytes.
            try x.tokens.append(x.gpa, .{ .symbol = sym, .start = tok.start, .len = wide });
            try x.enter.append(x.gpa, here);
            x.at = end;
            gr.lifts += 1;
            gr.skipped += wide;
            return true;
        }
        return false;
    }

    /// Run the folds this lookahead calls for, and say what state that leaves
    /// on top.
    ///
    /// The state a token is *read* in is not the state it is *shifted* from:
    /// between them stand the reductions its lookahead forces. A subtree's
    /// derivation begins at the shift of its first token, and returns to the
    /// state right beneath it, so the goto that lands a lifted subtree has to
    /// start there too. Landing it at the read state instead puts the parse on
    /// a stack no reading of this file has, which the tree may survive and the
    /// states will not.
    ///
    /// The folds are the ones the ordinary path would run a moment later, so a
    /// declined lift has cost nothing and changed nothing.
    fn ready(x: *Gather, tok: Token) !?u32 {
        var top = x.live.items[0].top;
        while (true) {
            const state = x.perches.items[top].state;
            // A cell the grammar author called contested is where a second
            // reading is born, and it is born in `absorb` rather than here.
            if (x.forking and x.forks.at(state, tok.symbol) != null) return null;
            const act = x.t.at(state, tok.symbol);
            if (act.kind != .reduce) {
                x.live.items[0].top = top;
                return if (act.kind == .shift) state else null;
            }
            // Where a second reading can be born at all, a fold run early is a
            // fold run before the split that might have wanted it. The lift
            // gives up rather than reorder a forked parse's moves; on a
            // grammar with no declared conflicts, which is where nearly every
            // lift happens, there is nothing to give up.
            if (x.forking) return null;
            top = try x.fold(top, act.value) orelse {
                x.live.items[0].top = top;
                return null;
            };
        }
    }

    /// Copy one old subtree into this parse's arena, shifted onto its new
    /// offsets. Children before parents, on an explicit stack, because a tree
    /// deep enough to matter is deeper than the machine stack is willing to be.
    ///
    /// It is a copy and not a reference, and that is the cost of the flat
    /// arena: `Node.start` is an absolute offset, so a subtree that moved by
    /// one byte is a subtree every node of which has to be rewritten. A
    /// relative offset would make this `O(1)`, and it would change what every
    /// reader of a node has to do to learn where it is.
    fn transcribe(x: *Gather, gr: *Graft, from: quire.Ref) !quire.Ref {
        gr.walk.clearRetainingCapacity();
        gr.made.clearRetainingCapacity();
        try gr.walk.append(x.gpa, .{ .ref = from, .done = 0 });
        while (gr.walk.items.len > 0) {
            const f = &gr.walk.items[gr.walk.items.len - 1];
            const was = gr.old.nodes[f.ref];
            if (f.done < was.kids_len) {
                const kid = gr.old.kids[was.kids_at + f.done];
                f.done += 1;
                try gr.walk.append(x.gpa, .{ .ref = kid, .done = 0 });
                continue;
            }
            const base = gr.made.items.len - was.kids_len;
            const kids = gr.made.items[base..];
            const at: u32 = @intCast(x.kids.items.len);
            try x.kids.appendSlice(x.gpa, kids);
            const ref: quire.Ref = @intCast(x.nodes.items.len);
            // The marks are spent: these nodes already wear whatever the parse
            // that built them decided, so there is nothing left for `bind` to
            // write and it must not think there is.
            if (x.forking) {
                try x.marks.appendNTimes(x.gpa, .{}, was.kids_len);
            } else for (kids) |c| x.nodes.items[c].parent = ref;
            try x.nodes.append(x.gpa, .{
                .kind = was.kind,
                .start = @intCast(@as(i64, was.start) + gr.delta + gr.skew),
                .len = was.len,
                .kids_at = at,
                .kids_len = was.kids_len,
                .field = was.field,
            });
            gr.made.shrinkRetainingCapacity(base);
            try gr.made.append(x.gpa, ref);
            _ = gr.walk.pop();
            gr.carried += 1;
        }
        // Whoever adopts this decides what to file it under, so it arrives
        // wearing nothing. The children keep theirs: their parent is inside
        // the lift and already decided.
        const root = gr.made.items[0];
        x.nodes.items[root].field = quire.none;
        return root;
    }

    /// Collapse the graph back down into a stack, once the token that refuted
    /// the last surviving fork has been absorbed.
    ///
    /// This is what keeps a conflict from costing anything past the few tokens
    /// it is live for. While a fork stands, the winner is not on the top of
    /// either array - the loser's perches and runs are interleaved with its
    /// own - so reductions have to walk and copy, and nothing can be reclaimed.
    /// One walk up the survivor's chain rewrites both arrays to hold only what
    /// it holds, and the flat-array behaviour of a deterministic parse resumes.
    /// Paid once per refutation rather than once per token, and a file that
    /// declares conflicts but reaches none never pays it at all.
    fn roost(x: *Gather) !void {
        x.grafted = false;
        x.spine.clearRetainingCapacity();
        var at = x.live.items[0].top;
        while (at != 0) : (at = x.below(at)) try x.spine.append(x.gpa, x.perches.items[at]);
        std.mem.reverse(Perch, x.spine.items);

        x.nest.clearRetainingCapacity();
        x.crop.clear();
        try x.nest.append(x.gpa, x.perches.items[0]);
        for (x.spine.items) |p| {
            var moved = p;
            moved.lead = x.crop.len();
            try x.carry(&x.crop, x.borne.at(p.lead, p.leads));
            moved.leads = p.leads;
            moved.own = x.crop.len();
            try x.carry(&x.crop, x.borne.at(p.own, p.owns));
            try x.nest.append(x.gpa, moved);
        }
        std.mem.swap(std.ArrayList(Perch), &x.perches, &x.nest);
        std.mem.swap(Run, &x.borne, &x.crop);
        // The chain is the array again, so the links are the indices.
        x.stand.clearRetainingCapacity();
        for (0..x.perches.items.len) |i| {
            try x.stand.append(x.gpa, .{ .down = @intCast(i -| 1), .depth = @intCast(i) });
        }
        // Sole again, so it speaks for the table: a refusal from here is worth
        // reporting, which `absorb` only does for rank zero.
        x.live.items[0] = .{ .top = @intCast(x.perches.items.len - 1), .rank = 0 };
    }

    /// Rule 1: an extra lands on the stack where it was read, ahead of every
    /// fold the token after it triggers. The run is laid down once and every
    /// reading that shifts claims the same one, which is what keeps a fork
    /// from multiplying the comments in a file.
    ///
    /// Laid down at the shift rather than where the scanner read it, because a
    /// reduction takes back the top of `borne`, and a run written before the
    /// folds would be sitting on the very perches those folds pop. The token's
    /// own leaf rides along for the same two reasons.
    inline fn stow(x: *Gather, tok: ?Token) !void {
        if (x.stowed) return;
        x.stowed = true;
        x.lead = x.borne.len();
        // Two sources, one order. The scanner's own extras arrive as tokens
        // and a grown one arrives as a finished node, but the file put them
        // in one sequence and the tree has to say so, so they are merged on
        // the offset they were read at rather than concatenated.
        var g_i: usize = 0;
        for (x.keep.items) |e| {
            while (g_i < x.grown.items.len and x.grown.items[g_i].start < e.start) : (g_i += 1) {
                try x.bear(&x.borne, x.grown.items[g_i].ref, .{});
            }
            const leaf = try x.mint(.aside(e.symbol), e.start, e.len, .{});
            try x.bear(&x.borne, leaf, .{});
        }
        while (g_i < x.grown.items.len) : (g_i += 1) {
            try x.bear(&x.borne, x.grown.items[g_i].ref, .{});
        }
        x.keep.clearRetainingCapacity();
        x.grown.clearRetainingCapacity();
        x.leads = x.borne.len() - x.lead;
        x.held = x.borne.len();
        // A leaf only when the terminal is visible: an inline `/regex/` is
        // `.invented`, so it consumes bytes and contributes no node.
        if (tok) |t| if (x.gr.shapeOf(t.symbol).visible()) {
            const leaf = try x.mint(.of(t.symbol), t.start, t.len, .{});
            try x.bear(&x.borne, leaf, .{});
        };
        x.helds = x.borne.len() - x.held;
    }

    /// A token's own perch, standing on the run `stow` laid down for it.
    inline fn perch(x: *Gather, top: u32, to: u32, tok: Token) !u32 {
        try x.stow(tok);
        if (x.trail) |tr| try tr.append(x.gpa, .{ .read = .{
            .at = x.perches.items[top].state,
            .symbol = tok.symbol,
            .from = tok.start,
            .end = tok.end(),
        } });
        return x.push(top, .{
            .state = to,
            .own = x.held,
            .owns = x.helds,
            .lead = x.lead,
            .leads = x.leads,
            .start = tok.start,
            .end = tok.end(),
        });
    }

    /// Add a perch standing on `on`, and say where it landed.
    inline fn push(x: *Gather, on: u32, p: Perch) !u32 {
        const at: u32 = @intCast(x.perches.items.len);
        try x.perches.append(x.gpa, p);
        if (x.forking) try x.stand.append(x.gpa, .{
            .down = on,
            .depth = if (at == 0) 0 else x.deep(on) + 1,
        });
        return at;
    }

    /// The perch beneath, and how far up this one is. Both are the index while
    /// the perches are a stack, which is every perch of a grammar that
    /// declares no conflict and every perch again once `roost` has run.
    inline fn below(x: *const Gather, at: u32) u32 {
        return if (x.forking) x.stand.items[at].down else at -| 1;
    }

    inline fn deep(x: *const Gather, at: u32) u32 {
        return if (x.forking) x.stand.items[at].depth else at;
    }

    /// Pop this reading's top `p.rhs.len` perches and push what they reduce to.
    /// Null is a table that cannot be followed from here, which on a truncated
    /// file is where the parse stops.
    ///
    /// Popping into the shared prefix is ordinary traffic rather than an error:
    /// what used to be "shrink the stack" is now "walk down", and a reading
    /// walking past its own split point is reading perches another reading is
    /// still standing on.
    fn fold(x: *Gather, top: u32, prod: u32) !?u32 {
        const p = x.gr.productions[prod];
        if (x.deep(top) < p.rhs.len) return null;

        // While the graph is a stack the symbols being popped are already the
        // last `rhs.len` entries, in order, so the reduction can read them
        // where they lie. Only a reading standing above a split has to walk
        // its own way down and copy what it finds, and only until the fork it
        // is standing on is refuted.
        var at: u32 = undefined;
        var mine: []const Perch = undefined;
        if (x.lone) {
            at = top - @as(u32, @intCast(p.rhs.len));
            mine = x.perches.items[at + 1 ..][0..p.rhs.len];
        } else {
            x.spine.clearRetainingCapacity();
            at = top;
            for (0..p.rhs.len) |_| {
                try x.spine.append(x.gpa, x.perches.items[at]);
                at = x.below(at);
            }
            std.mem.reverse(Perch, x.spine.items);
            mine = x.spine.items;
        }
        const under = x.perches.items[at].state;
        const to = x.c.goto(under, p.lhs) orelse return null;
        if (x.trail) |tr| try tr.append(x.gpa, .{ .fold = .{ .under = under, .prod = prod } });
        return try x.reduce(p, mine, at, to);
    }

    /// One reduction's worth of tree: apply the recipe to each child, then
    /// either mint a node for the left-hand side or leave the children to
    /// splice into whatever reduces next.
    fn reduce(x: *Gather, p: g.Production, mine: []const Perch, under: u32, to: u32) !u32 {
        // The span, from the perches that actually consumed something. A
        // nullable child sits at the offset the previous token ended, and
        // letting it set the start would pull the node back over the
        // whitespace in front of the first real one.
        var start = x.at;
        var end = x.at;
        var seen = false;
        for (mine) |*f| {
            if (f.start == f.end) continue;
            if (!seen) start = f.start;
            seen = true;
            end = f.end;
        }
        if (!seen) end = start;

        x.born.clear();
        for (p.rhs, p.steps, 0..) |sym, step, i| {
            const kids = x.borne.at(mine[i].own, mine[i].owns);
            const from = x.born.len();

            // Case 1 is the rename, which outranks the symbol's own shape. A
            // visible symbol already has its node, so the alias renames it
            // rather than wrapping it; an invisible one has none, so the alias
            // is the node its splice hangs under. Case 2 is an invisible
            // symbol, which emits nothing and leaves `kids` to be spliced.
            // Case 3 is the symbol's own name, on the node it already made.
            const visible = x.gr.shapeOf(sym).visible();
            var spliced = false;
            if (step.alias) |a| {
                if (visible) {
                    std.debug.assert(kids.ref.len == 1);
                    try x.bear(&x.born, kids.ref[0], .{ .alias = @intCast(a) });
                } else {
                    const wrap = try x.mint(.alias(a), mine[i].start, mine[i].end - mine[i].start, kids);
                    try x.bear(&x.born, wrap, .{});
                }
            } else if (visible) {
                std.debug.assert(kids.ref.len == 1);
                try x.carry(&x.born, kids);
            } else {
                try x.carry(&x.born, kids);
                spliced = true;
            }

            // The field, orthogonal to all three, and written into this
            // reduction's own copy of the child list rather than into the
            // children. A step that spliced files every child it spliced in,
            // which is how a field written inside a repeat reaches the elements
            // rather than the list. Rule 4 is the one exception: an extra
            // riding along in that splice is not a structural child, so no
            // field reaches it.
            if (step.field) |f| {
                for (x.born.ref.items[from..], from..) |c, j| {
                    if (spliced and x.nodes.items[c].kind.extra) continue;
                    if (x.forking) x.born.mark.items[j].field = @intCast(f) else x.nodes.items[c].field = @intCast(f);
                }
            }

            // Rule 2: the extras between this symbol and the next are this
            // node's children, in source order, and belong to nobody deeper -
            // whatever reduced beneath them had them as trailing and let them
            // go. They are the next symbol's lead.
            if (i + 1 < mine.len) {
                const nx = mine[i + 1];
                try x.carry(&x.born, x.borne.at(nx.lead, nx.leads));
            }
        }

        // Rule 2's other half. The extras under the first symbol were read
        // before this reduction began, so no production it contains ever
        // popped them; they stay exactly where they were, which is now beneath
        // the node this made. That is the whole reason `# d` in `{ x } # d`
        // ends up outside the braces without anybody deciding it should - and
        // the trailing ones stay in the next symbol's lead, above.
        const lead = if (mine.len == 0) 0 else mine[0].lead;
        const leads = if (mine.len == 0) 0 else mine[0].leads;
        const floor = if (mine.len == 0) x.borne.len() else mine[0].own;

        // The children are copied out, so the space the popped perches held is
        // free - while there is one reading to free it from. This is the whole
        // of what forking costs a grammar that never forks: one predicted
        // branch per reduction, and then exactly the flat arrays that were
        // here before, shrinking on every reduce the way they always did.
        // `mine` may point into `perches`, so nothing may read it past here.
        if (x.lone) {
            x.borne.shrink(floor);
            x.perches.shrinkRetainingCapacity(under + 1);
            if (x.forking) x.stand.shrinkRetainingCapacity(under + 1);
        }

        const own = x.borne.len();
        if (x.gr.shapeOf(p.lhs).visible()) {
            const up = try x.mint(.of(p.lhs), start, end - start, x.born.all());
            try x.bear(&x.borne, up, .{});
        } else {
            try x.carry(&x.borne, x.born.all());
        }
        return x.push(under, .{
            .state = to,
            .own = own,
            .owns = x.borne.len() - own,
            .lead = lead,
            .leads = leads,
            .start = start,
            .end = end,
        });
    }

    fn mint(
        x: *Gather,
        kind: quire.Kind,
        start: u32,
        len: u32,
        kids: Run.Slice,
    ) !quire.Ref {
        const ref: quire.Ref = @intCast(x.nodes.items.len);
        const at = try x.lay(ref, kids);
        try x.nodes.append(x.gpa, .{
            .kind = kind,
            .start = start,
            .len = len,
            .kids_at = at,
            .kids_len = @intCast(kids.ref.len),
        });
        return ref;
    }

    /// Write a child list, and say who owns it.
    ///
    /// Parentage is the one fact a child cannot carry itself, since it is not
    /// known until the parent exists. Where the grammar declares a conflict it
    /// waits for `bind` alongside the marks, because two readings can mint two
    /// parents over one child; where it declares none it is written here, and
    /// `marks` and `bind` both stand down for the whole run.
    inline fn lay(x: *Gather, of: quire.Ref, kids: Run.Slice) !u32 {
        const at: u32 = @intCast(x.kids.items.len);
        try x.kids.appendSlice(x.gpa, kids.ref);
        if (x.forking) {
            try x.marks.appendSlice(x.gpa, kids.mark);
        } else for (kids.ref) |c| x.nodes.items[c].parent = of;
        return at;
    }

    /// Rule 5. Acceptance is not a reduction, and tree-sitter treats it as its
    /// own operation: the accepted node is re-formed over everything still on
    /// the stack, and stretched to end of input.
    ///
    /// Two things fall out of that, and both are observable. The extras before
    /// the first token and after the last one are the ones no production ever
    /// popped - a leading comment sits *below* every frame and a trailing one
    /// *above* the last, so no reduction could have reached either - and here
    /// they become the root's outermost children. And the root is the only
    /// node whose extent is a fact about the file rather than about its own
    /// tokens: it ends at end of input whether or not anything is out there,
    /// which is why a file ending in a newline has a root one byte longer than
    /// its last token. A file that is nothing but whitespace has an empty root
    /// sitting at the end of it rather than at the start, because the padding
    /// was never spent.
    fn crown(x: *Gather, top: u32, len: u32) !void {
        // A grammar whose start rule is invisible leaves a forest rather than
        // a root. There is nothing to re-form and nothing to stretch, and
        // guessing which of the roots is the real one would be worse than the
        // honest forest.
        const f = x.perches.items[top];
        if (x.deep(top) != 1 or f.owns != 1) return;
        const root = x.borne.ref.items[f.own];
        const above: u32 = x.leads;

        if (f.leads != 0 or above != 0) {
            const was = x.nodes.items[root];
            x.born.clear();
            try x.carry(&x.born, x.borne.at(f.lead, f.leads));
            for (x.kids.items[was.kids_at..][0..was.kids_len], was.kids_at..) |c, i| {
                // A mark already spent is not carried again; `bear` wrote it
                // into the child when it was born.
                try x.bear(&x.born, c, if (x.forking) x.marks.items[i] else .{});
            }
            try x.carry(&x.born, x.borne.at(x.lead, above));
            const at = try x.lay(root, x.born.all());
            x.nodes.items[root].kids_at = at;
            x.nodes.items[root].kids_len = @intCast(x.born.len());
        }

        const n = x.nodes.items[root];
        var start = if (f.start == f.end) len else f.start;
        if (n.kids_len > 0) start = @min(start, x.nodes.items[x.kids.items[n.kids_at]].start);
        x.nodes.items[root].start = start;
        x.nodes.items[root].len = len - start;

        x.roots.clear();
        try x.bear(&x.roots, root, .{});
    }

    /// Drive the end-of-input column on every live reading, and say which one
    /// the tree is made of.
    ///
    /// The start production is never reduced - accept fires in its place - so
    /// what stands at the end of an accepting reading is the start symbol's own
    /// perch, which is either one root or, for a hidden start rule, the forest
    /// it spliced. Where several readings accept, the least speculative wins:
    /// without dynamic precedence there is nothing better to compare them by,
    /// and preferring the table's own answer is what makes forking a strict
    /// addition rather than a change of mind about files that already parsed.
    fn close(x: *Gather) !struct { top: u32, ok: bool } {
        x.lone = x.live.items.len == 1 and !x.grafted;
        var won: ?Reading = null;
        var tried: ?Reading = null;
        for (x.live.items) |v| {
            var top = v.top;
            const ok = done: while (true) {
                const act = x.t.at(x.perches.items[top].state, x.t.end);
                switch (act.kind) {
                    .accept => break :done true,
                    .reduce => top = try x.fold(top, act.value) orelse break :done false,
                    .err, .shift => break :done false,
                }
            };
            const r: Reading = .{ .top = top, .rank = v.rank };
            if (ok) {
                if (won == null or r.rank < won.?.rank) won = r;
            } else if (tried == null or r.rank < tried.?.rank) tried = r;
        }
        if (won) |w| return .{ .top = w.top, .ok = true };
        return .{ .top = tried.?.top, .ok = false };
    }

    /// Everything one reading is holding, in source order: the walk down, read
    /// back up, with the extras nobody has reduced over yet on top. What the
    /// flat array of nodes used to be, recovered for exactly one reading at the
    /// one moment a tree needs it.
    ///
    /// It appends, because a mended parse unwinds once per segment and the
    /// forest is all of them in the order the file put them. `run` clears the
    /// roots on the way in, which for a parse that never mends is the same one
    /// call it always was.
    fn unwind(x: *Gather, top: u32) !void {
        x.spine.clearRetainingCapacity();
        var at = top;
        while (x.deep(at) > 0) {
            try x.spine.append(x.gpa, x.perches.items[at]);
            at = x.below(at);
        }
        std.mem.reverse(Perch, x.spine.items);

        for (x.spine.items) |f| {
            try x.carry(&x.roots, x.borne.at(f.lead, f.leads));
            try x.carry(&x.roots, x.borne.at(f.own, f.owns));
        }
        try x.carry(&x.roots, x.borne.at(x.lead, x.leads));
    }
};
