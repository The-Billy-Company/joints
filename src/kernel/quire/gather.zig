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
//! The loop itself is the textbook one and is deliberately identical to the
//! oracle's, down to the order the stack is shrunk in. What is new is a second
//! stack running beside the state stack: one **frame** per stack symbol,
//! holding the bytes that symbol consumed and the nodes it contributed. A
//! reduction pops n frames, and because frames are pushed left to right and
//! each one appended its nodes when it was pushed, the popped nodes are
//! exactly the top of one flat array. So a reduction reads a contiguous run
//! and writes a shorter one.
//!
//! **Lexing is state-directed and this is not optional.** Before every token
//! the terminals the current state has any non-error action for are read
//! straight off its action row and handed to the scanner, which restricts the
//! regex walk rather than filtering its answer. The reduce entries are what
//! make that right: a state that would fold before shifting still offers
//! everything the fold leads to. Offer the whole slate instead and JSON's
//! `string_content` eats the rest of the line.
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
//! ## Spans
//!
//! A node spans from the first byte of its first token to the last byte of its
//! last, taken from the frames rather than from the child nodes. The
//! difference shows up exactly where it matters: a token that produced no node
//! (an inline regex is `.invented`) still consumed bytes, and the rule
//! containing it covers them.

const std = @import("std");
const g = @import("../../press/grammar.zig");
const lr0 = @import("../../press/lr0.zig");
const lalr = @import("../../press/lalr.zig");
const lex = @import("../lex/scanner.zig");
const quire = @import("quire.zig");

pub const Quire = quire.Quire;
pub const Stop = quire.Stop;
pub const Token = lex.Token;

/// One symbol on the parse stack, seen from the tree's side.
const Frame = struct {
    /// Where this symbol's nodes begin in `Gather.pending`. Its nodes run to
    /// the next frame's base, or to the end.
    base: u32,
    /// The bytes this symbol consumed. Equal offsets mean it consumed none,
    /// which a nullable rule does and which has to be told from a real span
    /// so an empty first child does not drag its parent back over the
    /// whitespace in front of it.
    start: u32,
    end: u32,
};

pub const Gather = struct {
    gpa: std.mem.Allocator,
    gr: *const g.Grammar,
    c: *const lr0.Collection,
    t: *const lalr.Tables,
    scanner: *lex.Scanner,

    /// The LR state stack, exactly as the oracle keeps it. One deeper than
    /// `frames`: state 0 stands under no symbol.
    states: std.ArrayList(u32),
    frames: std.ArrayList(Frame),
    /// Every node the frames are holding, in source order.
    pending: std.ArrayList(quire.Ref),
    /// The tree under construction. Moved out whole by `finish`.
    nodes: std.ArrayList(quire.Node),
    kids: std.ArrayList(quire.Ref),
    /// One reduction's finished child list. A field rather than a local so a
    /// file's worth of reductions allocates once.
    born: std.ArrayList(quire.Ref),
    /// Refilled once per token from the current state's action row.
    expected: lex.Scanner.Expected,

    /// The token stream this run consumed, and the state it stood in when it
    /// read each one - before the folds that token triggered. Kept because
    /// this is the only place the stream exists: real terminals are
    /// context-dependent, so a token stream is a thing a parser produces
    /// rather than a thing it is handed. Borrowed, and valid until the next
    /// run.
    tokens: std.ArrayList(Token),
    enter: std.ArrayList(u32),

    /// Where the last token ended. Where a rule that consumed nothing sits.
    at: u32,

    pub fn init(
        gpa: std.mem.Allocator,
        gr: *const g.Grammar,
        c: *const lr0.Collection,
        t: *const lalr.Tables,
        scanner: *lex.Scanner,
    ) !Gather {
        return .{
            .gpa = gpa,
            .gr = gr,
            .c = c,
            .t = t,
            .scanner = scanner,
            .states = .empty,
            .frames = .empty,
            .pending = .empty,
            .nodes = .empty,
            .kids = .empty,
            .born = .empty,
            .expected = try scanner.expecting(gpa),
            .tokens = .empty,
            .enter = .empty,
            .at = 0,
        };
    }

    pub fn deinit(x: *Gather) void {
        x.states.deinit(x.gpa);
        x.frames.deinit(x.gpa);
        x.pending.deinit(x.gpa);
        x.nodes.deinit(x.gpa);
        x.kids.deinit(x.gpa);
        x.born.deinit(x.gpa);
        x.expected.deinit(x.gpa);
        x.tokens.deinit(x.gpa);
        x.enter.deinit(x.gpa);
        x.* = undefined;
    }

    /// Parse `bytes` into a tree. A parse that stopped early still hands back
    /// everything it had completed, as a forest, with `Quire.stop` saying
    /// where it stopped and why.
    pub fn run(x: *Gather, bytes: []const u8) !Quire {
        x.states.clearRetainingCapacity();
        x.frames.clearRetainingCapacity();
        x.pending.clearRetainingCapacity();
        x.nodes.clearRetainingCapacity();
        x.kids.clearRetainingCapacity();
        x.tokens.clearRetainingCapacity();
        x.enter.clearRetainingCapacity();
        x.at = 0;
        try x.states.append(x.gpa, 0);

        while (true) {
            x.offer();
            const here = x.states.getLast();
            switch (x.scanner.next(bytes, x.at, &x.expected)) {
                .end => return x.finish(if (try x.close()) .accepted else .truncated),
                .stray => |off| return x.finish(.{ .stray = off }),
                .token => |tok| {
                    if (!try x.absorb(tok)) return x.finish(.{ .unexpected = .{
                        .symbol = tok.symbol,
                        .at = tok.start,
                        // The state that refused it, which is where the folds
                        // ran out - not `here`, which is where they started.
                        .state = x.states.getLast(),
                    } });
                    try x.tokens.append(x.gpa, tok);
                    try x.enter.append(x.gpa, here);
                    x.at = tok.end();
                },
            }
        }
    }

    fn finish(x: *Gather, why: Stop) !Quire {
        const roots = try x.gpa.dupe(quire.Ref, x.pending.items);
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
        };
    }

    /// The terminals this state has any action for - tree-sitter's
    /// valid-symbol set, read off the table rather than maintained beside it.
    fn offer(x: *Gather) void {
        x.expected.clear(x.scanner);
        const here = x.states.getLast();
        for (0..x.gr.terminal_count) |sym| {
            if (x.t.at(here, @intCast(sym)).kind != .err) x.expected.admit(x.scanner, @intCast(sym));
        }
    }

    /// Fold until the token can be shifted, then shift it. False means no
    /// sequence of folds makes this token legal here.
    fn absorb(x: *Gather, tok: Token) !bool {
        while (true) {
            const act = x.t.at(x.states.getLast(), tok.symbol);
            switch (act.kind) {
                .err => return false,
                .shift => {
                    try x.states.append(x.gpa, act.value);
                    try x.shift(tok);
                    return true;
                },
                .reduce => if (!try x.fold(act.value)) return false,
                // Accept is only in the end column, which `absorb` is never
                // called with; treat it as "nothing further to shift".
                .accept => return true,
            }
        }
    }

    /// A token's own frame. It carries a leaf only when the terminal is
    /// visible: an inline `/regex/` is `.invented`, so it consumes bytes and
    /// contributes no node, and its frame says exactly that.
    fn shift(x: *Gather, tok: Token) !void {
        const base: u32 = @intCast(x.pending.items.len);
        if (x.gr.shapeOf(tok.symbol).visible()) {
            const leaf = try x.mint(.of(tok.symbol), tok.start, tok.len, &.{});
            try x.pending.append(x.gpa, leaf);
        }
        try x.frames.append(x.gpa, .{ .base = base, .start = tok.start, .end = tok.end() });
    }

    fn fold(x: *Gather, prod: u32) !bool {
        const p = x.gr.productions[prod];
        if (x.states.items.len <= p.rhs.len) return false;
        try x.reduce(p);
        x.states.shrinkRetainingCapacity(x.states.items.len - p.rhs.len);
        const to = x.c.goto(x.states.getLast(), p.lhs) orelse return false;
        try x.states.append(x.gpa, to);
        return true;
    }

    /// One reduction's worth of tree: apply the recipe to each child, then
    /// either mint a node for the left-hand side or leave the children to
    /// splice into whatever reduces next.
    fn reduce(x: *Gather, p: g.Production) !void {
        const k = x.frames.items.len - p.rhs.len;
        const mine = x.frames.items[k..];
        const base: u32 = if (mine.len == 0)
            @intCast(x.pending.items.len)
        else
            mine[0].base;

        // The span, from the frames that actually consumed something. A
        // nullable child sits at the offset the previous token ended, and
        // letting it set the start would pull the node back over the
        // whitespace in front of the first real one.
        var start = x.at;
        var end = x.at;
        var seen = false;
        for (mine) |f| {
            if (f.start == f.end) continue;
            if (!seen) start = f.start;
            seen = true;
            end = f.end;
        }
        if (!seen) end = start;

        x.born.clearRetainingCapacity();
        for (p.rhs, p.steps, 0..) |sym, step, i| {
            const from = mine[i].base;
            const upto = if (i + 1 < mine.len) mine[i + 1].base else x.pending.items.len;
            const kids = x.pending.items[from..upto];

            // Case 1 is the rename, which outranks the symbol's own shape. A
            // visible symbol already has its node, so the alias renames it
            // rather than wrapping it; an invisible one has none, so the alias
            // is the node its splice hangs under. Case 2 is an invisible
            // symbol, which emits nothing and leaves `kids` to be spliced.
            // Case 3 is the symbol's own name, on the node it already made.
            var made: ?quire.Ref = null;
            if (step.alias) |a| {
                if (x.gr.shapeOf(sym).visible()) {
                    std.debug.assert(kids.len == 1);
                    x.nodes.items[kids[0]].kind = .alias(a);
                    made = kids[0];
                } else {
                    made = try x.mint(.alias(a), mine[i].start, mine[i].end - mine[i].start, kids);
                }
            } else if (x.gr.shapeOf(sym).visible()) {
                std.debug.assert(kids.len == 1);
                made = kids[0];
            }

            if (made) |ref| try x.born.append(x.gpa, ref) else try x.born.appendSlice(x.gpa, kids);

            // The field, orthogonal to all three. A step that spliced files
            // every child it spliced in, which is how a field written inside a
            // repeat reaches the elements rather than the list.
            if (step.field) |f| {
                if (made) |ref| x.nodes.items[ref].field = f else for (kids) |c| {
                    x.nodes.items[c].field = f;
                }
            }
        }

        x.pending.shrinkRetainingCapacity(base);
        if (x.gr.shapeOf(p.lhs).visible()) {
            const up = try x.mint(.of(p.lhs), start, end - start, x.born.items);
            try x.pending.append(x.gpa, up);
        } else {
            try x.pending.appendSlice(x.gpa, x.born.items);
        }
        x.frames.shrinkRetainingCapacity(k);
        try x.frames.append(x.gpa, .{ .base = base, .start = start, .end = end });
    }

    fn mint(
        x: *Gather,
        kind: quire.Kind,
        start: u32,
        len: u32,
        kids: []const quire.Ref,
    ) !quire.Ref {
        const ref: quire.Ref = @intCast(x.nodes.items.len);
        const at: u32 = @intCast(x.kids.items.len);
        try x.kids.appendSlice(x.gpa, kids);
        for (kids) |c| x.nodes.items[c].parent = ref;
        try x.nodes.append(x.gpa, .{
            .kind = kind,
            .start = start,
            .len = len,
            .kids_at = at,
            .kids_len = @intCast(kids.len),
        });
        return ref;
    }

    /// Drive the end-of-input column until the automaton accepts or refuses.
    /// The start production is never reduced - accept fires in its place - so
    /// what stands at the end is the start symbol's own frame, which is either
    /// one root or, for a hidden start rule, the forest it spliced.
    fn close(x: *Gather) !bool {
        while (true) {
            const act = x.t.at(x.states.getLast(), x.t.end);
            switch (act.kind) {
                .accept => return true,
                .reduce => if (!try x.fold(act.value)) return false,
                .err, .shift => return false,
            }
        }
    }
};
