//! Running a pressed query against a tree: the half of the lane that needs one.
//!
//! `gloss.zig` is the compiler and touches no tree at all, which is why it could
//! be written first. This is the other side - a `stencil.Program` in one hand, a
//! `Quire` in the other, and a stream of matches out. Nothing here parses a
//! `.scm`, resolves a name, or compiles a regex, because the press already did:
//! a step arrives holding symbol ids where the file held words, so asking
//! whether a node satisfies it is a comparison of `u32`s and not a string
//! compare against the grammar's name table. That is the whole of what the
//! artifact bought, and this file is where it is spent.
//!
//! **A pattern is tried at a node, never at the file.** One pre-order pass, and
//! at each node only the patterns that could root there: `Sieve` keys the
//! pattern list on the node's kind, so a `highlights.scm` with four hundred
//! patterns costs a hash lookup per node rather than four hundred attempts. A
//! pattern whose root pins no kind - `(_)`, a bare `_`, a top-level group - goes
//! in the open list and is tried at every node, which is the honest price of
//! writing one. Candidates are merged back into ascending pattern order, so a
//! node's own answers arrive in the order the file wrote them whichever list
//! they came from.
//!
//! **Found is not the order handed over.** A pattern rooted on a
//! `declaration_list` has answered for every function inside it before the walk
//! has descended to the first one, and a pattern rooted on the function itself
//! arrives long after - so searching order is a fact about the search and not
//! about the file. A match is held until the walk reaches where it *finishes*,
//! ties going to the one that opened higher up and then to the earlier pattern.
//! That is what upstream emits, and it is not a matter of taste: a highlighter
//! resolves two captures on one byte by which came last, so the order is part
//! of the answer. The buffer holds only what the walk has passed the root of
//! and not yet the end of - the patterns open at an ancestor of where it
//! stands - and recycles its capture lists, so the reordering costs an
//! allocation per outstanding match rather than one per match.
//!
//! **Child matching is one recursion over frames, and every construct is one of
//! four moves.** A step either consumes one child (`node`, `literal`,
//! `wildcard`, `choice`), consumes a run of them (`group`), advances because it
//! has had what it needs (`?` and `*` at zero, `+` and a plain step after one),
//! or goes round again (`*` and `+`). Writing it as "advance, or consume once
//! more" rather than as a case per quantifier is what lets a quantified group
//! work at all: the group opens a frame whose exhaustion returns to the step
//! that opened it with `seen` set, and the same two moves then read as "leave
//! the group" and "repeat the group" without either being spelled out.
//!
//! **An anchor is about NAMED siblings.** tree-sitter's notation says `.` before
//! the first child constrains it to be *the first named node* in the parent, so
//! an anchored step may step over an anonymous token and may not step over a
//! named one. A comment is named - `reach.zig`'s header settles that for the
//! sibling walks and the same answer holds here - so an extra between two
//! anchored children breaks the anchor, exactly as it does upstream.
//!
//! **What this declines, and says so.** A `.group` written as an alternative of
//! a `[...]` choice consumes a run where the choice is asked about one node, and
//! is skipped rather than guessed at; `Cursor.declined` counts it, so a caller
//! reading zero matches can tell "no" from "not asked". Everything else in the
//! notation the compiler admits is run here.

const std = @import("std");
const irregex = @import("irregex");

const lemma = @import("lemma.zig");
const sift = @import("sift.zig");
const stencil = @import("stencil.zig");
const quire = @import("../quire/quire.zig");

const Quire = quire.Quire;
const Ref = quire.Ref;
const none = stencil.none;

/// One capture bound to one node. `id` indexes the program's capture table, so
/// the name is `Program.captureAt(id)` and never a string on this struct.
pub const Capture = struct { id: u32, node: Ref };

/// One pattern satisfied at one place.
pub const Match = struct {
    pattern: u32,
    /// Borrowed from the cursor and live only until the next `next`. The same
    /// contract tree-sitter's own match has, and for the same reason: a match
    /// that owned its captures would be an allocation per hit, and a
    /// highlighter takes thousands per file.
    captures: []const Capture,
};

/// A match generated but not yet due, waiting for the walk to reach its place.
/// See `place` for why the search cannot hand one out where it finds it.
const Held = struct {
    pattern: u32,
    /// Where this match *finishes* - its last capture's start, or the node it
    /// was rooted at when it captures nothing. The first and only key a release
    /// may be gated on.
    ///
    /// Not where it begins, which is the reading a stream sorted by position
    /// would want and is the wrong one. `["<" ">"] @punctuation.bracket` binds
    /// both brackets in one match and is not settled until the closing one, so
    /// a `(primitive_type) @type.builtin` between them is answered first even
    /// though it starts later. Upstream hands a match over when its last step
    /// matches, and that is the rule this reproduces.
    at: u32,
    /// Where it opened - the start of the node it was rooted at, which is not
    /// the same as its first capture and is the one that matters. Breaks a tie
    /// on `at`, and it takes a tie-break because two patterns routinely settle
    /// on the same node from different heights: `(class_declaration name:
    /// (identifier) @type)` and a bare `(identifier) @variable` both finish on
    /// that identifier and capture nothing before it, yet the first has been
    /// open since the `class` keyword and is handed over first however its
    /// pattern is numbered.
    beg: u32,
    /// Owned while held, lent out on release, and recycled through `Cursor.spare`
    /// the call after that.
    caps: std.ArrayList(Capture),
};

/// What to do with a predicate the engine carries but cannot run.
///
/// `sift` classifies these and deliberately leaves the verdict here, because
/// the difference between a directive and a foreign filter is whether anyone
/// ever asks. `#set!` and its kin filter nothing and always hold, whatever this
/// says; the policy is only ever about `#lua-match?` and the three other
/// spellings whose semantics live in Neovim.
pub const Foreign = enum {
    /// Refuse the run and name the predicate. The default, because an engine
    /// that quietly guesses at a filter it does not implement is worse than one
    /// that says it cannot.
    refuse,
    /// The match stands, unfiltered. What an editor wants: a `highlights.scm`
    /// is worth its two thousand captures even when four lines of it ask for a
    /// function we do not have.
    admit,
    /// The match is dropped.
    deny,
};

/// The tree to run against, and the two things a program cannot carry about it.
pub const Ask = struct {
    q: *const Quire,
    /// The bytes the tree was parsed from. Only a core predicate reads them; a
    /// query with none never touches this and may pass an empty slice.
    src: []const u8 = &.{},
    /// The grammar's index. Needed for exactly one shape - a pattern that names
    /// a bare supertype, `(expression)`, where the membership is the question
    /// and no id in the program answers it. Every other check is a `u32`
    /// compare against the step, so a caller with no supertype patterns may
    /// leave this null and a caller with one gets told rather than answered no.
    index: ?*const lemma.Lemma = null,
    foreign: Foreign = .refuse,
};

pub const Error = error{
    /// A pattern names a bare supertype and the ask came without an index.
    QueryNeedsIndex,
    /// `Foreign.refuse` met a filter this engine does not implement.
    QueryOpaquePredicate,
    /// A core predicate needs a capture's text and the source is shorter than
    /// the tree that was parsed from it. Refused at `open` rather than mid
    /// stream, so a caller cannot get half an answer.
    QuerySourceShort,
} || std.mem.Allocator.Error;

/// Open a run of one program over one tree.
///
/// Everything a match will need is built here and once: the regexes the
/// program's `#match?`s want, the sieve, and the walk's frontier. `next` after
/// this allocates only when a capture list outgrows what it has.
pub fn open(gpa: std.mem.Allocator, p: stencil.Program, a: Ask) Error!Cursor {
    var c: Cursor = .{ .gpa = gpa, .p = p, .a = a, .rx = &.{}, .sieve = .{} };
    errdefer c.deinit();

    c.rx = try gpa.alloc(?irregex.Pattern, p.predicateCount());
    @memset(c.rx, null);
    var wants_text = false;
    for (0..p.predicateCount()) |i| {
        const pr = p.predicateAt(@intCast(i));
        if (!pr.op.core()) continue;
        wants_text = true;
        if (pr.op != .match and pr.op != .not_match or pr.args.len < 2) continue;
        // Proved compilable when the query was pressed, so a refusal here is a
        // resource fault rather than a bad pattern; either way the predicate
        // has no regex and reads as unconstrained below.
        const src = switch (p.argAt(pr.args.off + 1)) {
            .text => |t| t,
            .capture => continue,
        };
        c.rx[i] = irregex.Pattern.compile(gpa, src) catch continue;
    }
    // A capture's text comes out of `src`, so a mismatched pair is a caller
    // error and not a match that happens to fail. Checked against the roots,
    // which cover every node a child-inside-its-parent tree can hold, and only
    // when some predicate is going to read a byte.
    if (wants_text) {
        for (a.q.roots) |r| {
            if (a.q.nodes[r].end() > a.src.len) return Error.QuerySourceShort;
        }
    }

    try c.sieve.of(gpa, p);
    // Pre-order, so the frontier is the roots reversed and every pop pushes its
    // children the same way.
    var i = a.q.roots.len;
    while (i > 0) {
        i -= 1;
        try c.stack.append(gpa, a.q.roots[i]);
    }
    return c;
}

pub const Cursor = struct {
    gpa: std.mem.Allocator,
    p: stencil.Program,
    a: Ask,
    /// One compiled regex per predicate that has one, indexed by predicate id.
    /// Null for the five core filters that are string compares and for every
    /// predicate we carry rather than run.
    rx: []?irregex.Pattern,
    sieve: Sieve,
    /// The pre-order frontier.
    stack: std.ArrayList(Ref) = .empty,
    /// The captures of the match being built. Truncated back to a mark on every
    /// failed branch, which is what makes backtracking free of bookkeeping
    /// anywhere else.
    found: std.ArrayList(Capture) = .empty,

    /// The node being tried, and how far through its candidates we are. Two
    /// cursors rather than one because the candidates arrive as two ascending
    /// lists - the ones this kind admits and the ones every kind does - and
    /// merging them is what keeps the stream in pattern order.
    here: ?Ref = null,
    kin: []const u32 = &.{},
    ka: usize = 0,
    oa: usize = 0,

    /// The candidate being asked, held across calls because one pattern at one
    /// node can have more than one answer and each is its own match.
    pat: ?u32 = null,
    /// Where the next assignment of `pat` may begin, and where the one being
    /// built began and ended. All three are child positions of `here`. See
    /// `take`.
    from: usize = 0,
    head: usize = 0,
    edge: usize = 0,
    /// How many frames deep the child matcher is. Only the outermost chain
    /// completing is a whole assignment; see `take`.
    deep: u32 = 0,

    /// Matches found but not yet due, ascending in `(at, pattern)`. Short: it
    /// holds only what the walk has passed the root of and not yet the start
    /// of, which is the set of patterns rooted at an ancestor of where the walk
    /// stands. See `place`.
    pend: std.ArrayList(Held) = .empty,
    /// Capture buffers a released match gave back, so holding costs an
    /// allocation per *outstanding* match rather than one per match.
    spare: std.ArrayList(std.ArrayList(Capture)) = .empty,
    /// The buffer the last `next` lent out, kept alive for exactly as long as
    /// `Match.captures` promises and recycled at the top of the call after.
    lent: ?std.ArrayList(Capture) = null,

    /// Alternatives skipped because they were groups inside a choice. See the
    /// header: the one shape this engine declines, counted so that declining is
    /// visible rather than silent.
    declined: u32 = 0,

    pub fn deinit(c: *Cursor) void {
        for (c.rx) |*slot| if (slot.*) |*pat| pat.deinit();
        c.gpa.free(c.rx);
        c.sieve.deinit(c.gpa);
        c.stack.deinit(c.gpa);
        c.found.deinit(c.gpa);
        for (c.pend.items) |*h| h.caps.deinit(c.gpa);
        c.pend.deinit(c.gpa);
        for (c.spare.items) |*b| b.deinit(c.gpa);
        c.spare.deinit(c.gpa);
        if (c.lent) |*l| l.deinit(c.gpa);
        c.* = undefined;
    }

    /// The next match, or absence when the tree is walked out.
    ///
    /// The stream is in document order: ascending in where a match begins, ties
    /// to the earlier pattern. That is not the order the search finds them in -
    /// see `place` - so a node is drained whole and the answer comes off `pend`.
    pub fn next(c: *Cursor) Error!?Match {
        if (c.lent) |l| {
            var buf = l;
            c.lent = null;
            c.spare.append(c.gpa, buf) catch buf.deinit(c.gpa);
        }
        while (true) {
            // Everything beginning before the node about to be visited is due:
            // the walk is pre-order, so no byte earlier than that node's start
            // is ever reached again.
            if (c.ripe(if (c.stack.getLastOrNull()) |n| c.a.q.nodes[n].start else null)) |m| return m;
            c.here = try c.descend() orelse break;
            const ref = c.here.?;
            c.kin = c.sieve.at(c.a.q.nodes[ref].kind);
            c.ka = 0;
            c.oa = 0;
            c.pat = null;
            while (true) {
                if (c.pat == null) {
                    c.pat = c.candidate() orelse break;
                    c.from = 0;
                }
                const i = c.pat.?;
                const pat = c.p.patternAt(i);
                c.found.clearRetainingCapacity();
                c.head = 0;
                c.edge = 0;
                if (!try c.root(pat, ref)) {
                    c.pat = null;
                    continue;
                }
                // The next assignment starts past this one, whether or not this
                // one survives its predicates. The `+ 1` is what guarantees the
                // ask terminates when the first step consumed nothing at all -
                // a `*` or `?` that took zero.
                c.from = @max(c.edge, c.head + 1);
                if (!try c.holds(pat)) continue;
                try c.place(i, ref);
            }
        }
        // Walked out, so the frontier can no longer beat anything: what is left
        // is due in the order it is already in.
        return c.ripe(null);
    }

    /// Hold a match until the walk reaches where it begins.
    ///
    /// The search finds matches rooted at a node, in ascending pattern order,
    /// which is not the order they occur in the file: a pattern rooted at a
    /// `declaration_list` yields every function inside it before the walk has
    /// descended to the first one, and a pattern rooted on the function itself
    /// arrives long after. Upstream emits by where a match *begins*, which is
    /// what a highlighter wants - later captures win, so their order is the
    /// answer - so the difference is not a matter of taste and this is where it
    /// is paid.
    fn place(c: *Cursor, pattern: u32, ref: Ref) Error!void {
        const caught = c.found.items;
        // A pattern may capture nothing at all and still be a match; then it
        // finishes where it was rooted, which is also where it opened.
        const nodes = c.a.q.nodes;
        const til = nodes[if (caught.len == 0) ref else caught[caught.len - 1].node].start;
        const off = nodes[ref].start;
        var caps: std.ArrayList(Capture) = c.spare.pop() orelse .empty;
        errdefer caps.deinit(c.gpa);
        caps.clearRetainingCapacity();
        try caps.appendSlice(c.gpa, caught);
        // From the back, so two matches alike on all three keep the order they
        // were found in, which is ascending pattern anyway.
        var i = c.pend.items.len;
        while (i > 0) : (i -= 1) {
            const h = c.pend.items[i - 1];
            if (h.at != til) {
                if (h.at < til) break;
            } else if (h.beg != off) {
                if (h.beg < off) break;
            } else if (h.pattern <= pattern) break;
        }
        try c.pend.insert(c.gpa, i, .{ .pattern = pattern, .at = til, .beg = off, .caps = caps });
    }

    /// The earliest held match, if the walk can no longer produce one before
    /// it. `before` is the byte the frontier stands at, or absence at the end.
    ///
    /// Sound because the walk is pre-order and so visits nodes in non-decreasing
    /// start order: a match not yet found will be rooted at or after the
    /// frontier and finish at or after that, so nothing still to come can key
    /// below `before`.
    fn ripe(c: *Cursor, before: ?u32) ?Match {
        if (c.pend.items.len == 0) return null;
        if (before) |b| if (c.pend.items[0].at >= b) return null;
        const h = c.pend.orderedRemove(0);
        c.lent = h.caps;
        return .{ .pattern = h.pattern, .captures = h.caps.items };
    }

    /// Pop the frontier and push what the popped node holds, so the order out
    /// is the order a reader reads the file in.
    fn descend(c: *Cursor) Error!?Ref {
        const ref = c.stack.pop() orelse return null;
        const kids = c.a.q.children(ref);
        var i = kids.len;
        while (i > 0) {
            i -= 1;
            try c.stack.append(c.gpa, kids[i]);
        }
        return ref;
    }

    /// The next pattern to try at the current node, merging the kind's list
    /// with the open one so the ids come out ascending.
    fn candidate(c: *Cursor) ?u32 {
        const a: ?u32 = if (c.ka < c.kin.len) c.kin[c.ka] else null;
        const b: ?u32 = if (c.oa < c.sieve.open.items.len) c.sieve.open.items[c.oa] else null;
        if (a) |x| {
            if (b == null or x < b.?) {
                c.ka += 1;
                return x;
            }
        }
        if (b) |y| {
            c.oa += 1;
            return y;
        }
        return null;
    }

    // ── matching ────────────────────────────────────────────────────────────

    /// One pattern at one node.
    ///
    /// A top-level group is the one root that is not a node matcher: it is a run
    /// of siblings and needs a parent to be a run *in*, so it is tried against
    /// each node's child list rather than against the node.
    fn root(c: *Cursor, pat: stencil.Pattern, ref: Ref) Error!bool {
        const s = c.p.stepAt(pat.root);
        const mark = c.found.items.len;
        const held = if (s.op != .group) try c.step(pat.root, ref) else held: {
            const f: Frame = .{ .steps = s.kids, .si = 0, .ki = 0 };
            c.deep += 1;
            defer c.deep -= 1;
            break :held try c.at(c.a.q.children(ref), f, false);
        };
        // A root that opened no frame at all - `(identifier) @x` - has exactly
        // one assignment and no `take` to gate it, so the ask for a second is
        // answered here rather than by running the same search again.
        if (held and c.head >= c.from) return true;
        c.found.shrinkRetainingCapacity(mark);
        return false;
    }

    /// One step against one node, with the captures it bound rolled back when
    /// it does not hold. Every failing path in `attempt` returns through here,
    /// which is why none of them has to unwind anything itself.
    fn step(c: *Cursor, sid: u32, ref: Ref) Error!bool {
        const mark = c.found.items.len;
        if (try c.attempt(sid, ref)) return true;
        c.found.shrinkRetainingCapacity(mark);
        return false;
    }

    fn attempt(c: *Cursor, sid: u32, ref: Ref) Error!bool {
        const s = c.p.stepAt(sid);
        // A field prefix is written at the position and constrains whatever
        // stands there, so it is asked before the shape is.
        if (s.field != none and c.a.q.nodes[ref].field != s.field) return false;

        switch (s.op) {
            // Spliced into the sibling run by `at`. It consumes a run rather
            // than a node, so the only way it reaches here is as an alternative
            // of a choice - the shape the header says is declined.
            .group => {
                c.declined += 1;
                return false;
            },
            .choice => {
                try c.bind(s, ref);
                for (0..s.kids.len) |i| {
                    if (try c.step(c.idAt(s.kids, @intCast(i)), ref)) return true;
                }
                return false;
            },
            // The bare `_`, which takes any node named or not. `(_)` is a
            // `node` that pins nothing and takes any NAMED one; the difference
            // is the parentheses and it is `fits` that keeps it.
            .wildcard => try c.bind(s, ref),
            .node, .literal => {
                if (!try c.fits(s, ref)) return false;
                if (!c.without(s, ref)) return false;
                // Bound BEFORE descending, so a match's captures come out in
                // the order the pattern wrote them: `(struct_item name: (…)
                // @name) @definition.class` reports the struct and then its
                // name, which is what an editor applying them in order expects
                // and what upstream emits. Binding on the way back up put the
                // innermost capture first and every outer one after it. Nothing
                // has to be unwound here - `step` truncates to its mark on
                // every failing path, including the two below.
                try c.bind(s, ref);
                if (s.kids.len != 0 or s.closed()) {
                    const f: Frame = .{ .steps = s.kids, .si = 0, .ki = 0 };
                    c.deep += 1;
                    defer c.deep -= 1;
                    if (!try c.at(c.a.q.children(ref), f, s.closed())) return false;
                }
            },
        }
        return true;
    }

    /// Is this node one of the things the step names?
    ///
    /// A rename is the name the tree WEARS and the only name a query can reach
    /// it by: `alias($.identifier, $.type_identifier)` leaves the symbol as
    /// `identifier`, and `(identifier)` must not match the node, because the
    /// node is called `type_identifier`. So a renamed node is answered out of
    /// the step's alias slot and never out of its symbol set.
    fn fits(c: *const Cursor, s: stencil.Step, ref: Ref) Error!bool {
        const k = c.a.q.nodes[ref].kind;
        if (k.renamed) return s.alias != none and s.alias == k.index;
        if (s.kinds.len != 0) {
            for (0..s.kinds.len) |i| {
                if (c.idAt(s.kinds, @intCast(i)) == k.index) return true;
            }
            return false;
        }
        // A spelling only a rename answers to, met by a node wearing no rename.
        if (s.alias != none) return false;
        if (s.category != none) {
            // A bare supertype. Membership is over the symbol the parse
            // REDUCED, because a rename is a name rather than a structure -
            // the same reading `gloss.Named.under` takes on the way in.
            const l = c.a.index orelse return Error.QueryNeedsIndex;
            return l.member(s.category, k.under);
        }
        return c.a.q.isNamed(ref);
    }

    /// `!field` - no child of this node is filed under any of them.
    fn without(c: *const Cursor, s: stencil.Step, ref: Ref) bool {
        if (s.absent.len == 0) return true;
        for (c.a.q.children(ref)) |kid| {
            const f = c.a.q.nodes[kid].field;
            if (f == none) continue;
            for (0..s.absent.len) |i| {
                if (c.idAt(s.absent, @intCast(i)) == f) return false;
            }
        }
        return true;
    }

    fn bind(c: *Cursor, s: stencil.Step, ref: Ref) Error!void {
        for (0..s.captures.len) |i| {
            try c.found.append(c.gpa, .{ .id = c.idAt(s.captures, @intCast(i)), .node = ref });
        }
    }

    fn idAt(c: *const Cursor, run: stencil.Run, i: u32) u32 {
        return c.p.refAt(run.off + i);
    }

    // ── the sibling run ─────────────────────────────────────────────────────

    /// One position in one step sequence, and where to go when it runs out.
    ///
    /// `up` is what makes a group work: the frame a group opens returns to the
    /// frame that opened it, at the same step, with `seen` set. The two moves
    /// below then read as "leave the group" and "go round again" without
    /// either being a case.
    const Frame = struct {
        steps: stencil.Run,
        si: u32,
        ki: usize,
        /// Has the step at `si` already matched once here?
        seen: bool = false,
        /// No named sibling may be stepped over before the next node this frame
        /// consumes. Carried rather than read off the step because an anchor
        /// written on a group has to reach the group's first element.
        pin: bool = false,
        /// The first child this assignment consumed, whichever step took it -
        /// null while it has taken none, which is what a leading `(comment)*`
        /// matching nothing leaves behind. Carried ON THE FRAME rather than on
        /// the cursor because a frame is copied along the path that succeeds
        /// and dropped with the one that does not, so it can never report a
        /// position from a branch that was abandoned.
        head: ?usize = null,
        up: ?*const Frame = null,
    };

    fn at(c: *Cursor, kids: []const Ref, f: Frame, closed: bool) Error!bool {
        if (f.si == f.steps.len) {
            const u = f.up orelse {
                if (!c.tail(kids, f.ki, closed)) return false;
                return c.take(f.head orelse f.ki, f.ki);
            };
            var back = u.*;
            back.ki = f.ki;
            back.seen = true;
            back.pin = false;
            back.head = f.head;
            return c.at(kids, back, closed);
        }

        const sid = c.idAt(f.steps, f.si);
        const s = c.p.stepAt(sid);
        const mark = c.found.items.len;
        // An anchor says "immediately after what came before", so it needs a
        // before. A leading `.` has one - the parent's own start, which is what
        // makes `(class_body . (method_definition))` mean FIRST named child. An
        // anchor sitting after a `(comment)*` that matched nothing has none, and
        // reading `ki` as the reference there would silently promote it into a
        // leading anchor and demand the next step be the parent's first child.
        // That is the shape every `tags.scm` opens with, and upstream puts no
        // constraint on it either.
        const pin = f.pin or (s.anchored() and (f.si == 0 or f.head != null));

        // Move one: consume one more occurrence. Only `*` and `+` may be asked
        // twice, and the try comes BEFORE the one below because a quantifier
        // that stopped at its first occurrence would bind one comment where the
        // file wrote a block of them - which is how every doc-comment rule in
        // the corpus is written, and the whole reason a capture is allowed
        // under a quantifier at all.
        if (!f.seen or s.quantifier == .star or s.quantifier == .plus) {
            if (s.op == .group) {
                // A stable address for the frames below to return to: the
                // group's own frame is what `up` names, so it has to outlive
                // the descent, and a parameter's address does not.
                const here = f;
                const sub: Frame = .{
                    .steps = s.kids,
                    .si = 0,
                    .ki = f.ki,
                    .pin = pin,
                    .head = f.head,
                    .up = &here,
                };
                if (try c.at(kids, sub, closed)) return true;
                c.found.shrinkRetainingCapacity(mark);
            } else {
                var p = f.ki;
                while (p < kids.len) : (p += 1) {
                    if (try c.step(sid, kids[p])) {
                        var on = f;
                        on.ki = p + 1;
                        on.seen = true;
                        on.pin = false;
                        if (on.head == null) on.head = p;
                        if (try c.at(kids, on, closed)) return true;
                        c.found.shrinkRetainingCapacity(mark);
                    }
                    // An anchored step may step over an anonymous token and may
                    // not step over a node a pattern could have named. See the
                    // header.
                    if (pin and c.a.q.isNamed(kids[p])) break;
                }
            }
        }
        // Move two: this step has had what it needs, so go on to the next. True
        // at zero occurrences for `?` and `*`, and after one for anything. The
        // pin rides along rather than being re-read, so an anchor written on a
        // group still reaches whichever element first consumes a node.
        if (f.seen or s.quantifier == .optional or s.quantifier == .star) {
            var on = f;
            on.si += 1;
            on.seen = false;
            if (try c.at(kids, on, closed)) return true;
            c.found.shrinkRetainingCapacity(mark);
        }
        return false;
    }

    /// A complete assignment of a pattern's children - and whether to take it.
    ///
    /// The search is a decision procedure: it stops at the first yes, which is
    /// the right answer to "does this pattern hold here" and the wrong one to
    /// "what does it hold as". One `declaration_list` holding three
    /// `function_item`s satisfies `(declaration_list (function_item) @m)` three
    /// times and owes three matches, which is how every `tags.scm` in the
    /// corpus counts methods and what the incumbent answers.
    ///
    /// So the way to ask for a SECOND yes is to make the same search walk past
    /// the one already reported. Rejecting HERE rather than at the root is what
    /// makes it a resumption and not a rerun-and-hope - the `false` lands in
    /// the sibling loop that made the last choice, which goes round again from
    /// exactly there and finds the next assignment in the same order.
    ///
    /// **What separates two assignments is where they START, not how they
    /// differ.** A quantifier is greedy and stays greedy: `(comment)+ @doc` over
    /// a block of three binds all three once, and the two shorter runs inside it
    /// are not three matches. So an assignment must begin at or after the end of
    /// the one before, which is the same thing as saying matches of one pattern
    /// do not overlap - and it is why the doc-comment run every `tags.scm` is
    /// built on comes out once here and once upstream.
    ///
    /// Only the outermost frame chain completing is a whole assignment. A frame
    /// opened for a grandchild is one decision inside one, and gating it would
    /// judge an interior choice as if it were a match.
    fn take(c: *Cursor, head: usize, edge: usize) bool {
        if (c.deep != 1) return true;
        if (head < c.from) return false;
        c.head = head;
        c.edge = edge;
        return true;
    }

    /// A trailing `.` inside a parent: nothing a pattern could name is left.
    fn tail(c: *const Cursor, kids: []const Ref, ki: usize, closed: bool) bool {
        if (!closed) return true;
        for (kids[ki..]) |kid| if (c.a.q.isNamed(kid)) return false;
        return true;
    }

    // ── predicates ──────────────────────────────────────────────────────────

    fn holds(c: *Cursor, pat: stencil.Pattern) Error!bool {
        for (0..pat.preds.len) |i| {
            if (!try c.weigh(pat.preds.off + @as(u32, @intCast(i)))) return false;
        }
        return true;
    }

    /// One predicate against the captures in hand.
    ///
    /// A capture this match never bound - one under an `?` that took the empty
    /// arm - leaves the predicate with nothing to constrain, and it holds. That
    /// is the same direction the compiler errs in for reachability: the claim on
    /// the other side is "this match is wrong", and a claim like that has to be
    /// earned rather than assumed from an absence.
    fn weigh(c: *Cursor, id: u32) Error!bool {
        const pr = c.p.predicateAt(id);
        if (pr.op == .opaque_meta) {
            // A directive is metadata for the host and filters nothing, so it
            // holds whatever the policy says. The policy is about the foreign
            // FILTERS - `#lua-match?` and its three neighbours.
            if (sift.directive(pr.name)) return true;
            return switch (c.a.foreign) {
                .refuse => Error.QueryOpaquePredicate,
                .admit => true,
                .deny => false,
            };
        }
        // Arity was proved when the query was pressed. A program that arrived
        // some other way is still only allowed to be useless, never to read
        // past the table `stencil.read` sized.
        if (pr.args.len == 0) return true;
        const subject = c.textOf(c.p.argAt(pr.args.off)) orelse return true;
        if (pr.args.len < 2) return true;
        return switch (pr.op) {
            .eq_capture, .not_eq_capture => blk: {
                const other = c.textOf(c.p.argAt(pr.args.off + 1)) orelse break :blk true;
                break :blk std.mem.eql(u8, subject, other) == (pr.op == .eq_capture);
            },
            .eq_text, .not_eq_text => blk: {
                const want = c.textOf(c.p.argAt(pr.args.off + 1)) orelse break :blk true;
                break :blk std.mem.eql(u8, subject, want) == (pr.op == .eq_text);
            },
            .any_of, .not_any_of => blk: {
                var hit = false;
                for (1..pr.args.len) |i| {
                    const want = c.textOf(c.p.argAt(pr.args.off + @as(u32, @intCast(i)))) orelse continue;
                    hit = hit or std.mem.eql(u8, subject, want);
                }
                break :blk hit == (pr.op == .any_of);
            },
            .match, .not_match => blk: {
                if (c.rx[id] == null) break :blk true;
                // The pattern compiled when the query was pressed, so a failure
                // here is the engine's scratch and not the file's regex; an
                // answer of "no match" is the one that cannot invent a hit.
                const hit = c.rx[id].?.isMatch(subject) catch false;
                break :blk hit == (pr.op == .match);
            },
            .opaque_meta => unreachable,
        };
    }

    /// What one predicate argument is, as bytes. Null for a capture this match
    /// never bound.
    fn textOf(c: *const Cursor, arg: stencil.Arg) ?[]const u8 {
        return switch (arg) {
            .text => |t| t,
            .capture => |id| {
                for (c.found.items) |got| {
                    if (got.id != id) continue;
                    const n = c.a.q.nodes[got.node];
                    return c.a.src[n.start..n.end()];
                }
                return null;
            },
        };
    }
};

/// Which patterns can root at which kind.
///
/// A `highlights.scm` is hundreds of patterns and a file is tens of thousands of
/// nodes, so the product is the number that matters. Nearly every pattern names
/// a concrete kind at its root, which makes the question a hash lookup: the rows
/// are windows onto one flat array, keyed on the node's kind word rather than on
/// its name, because the program holds ids and so does the tree.
const Sieve = struct {
    /// Keyed on `(renamed, index)` - the two id spaces a node's kind can live
    /// in, kept apart for the same reason `fits` keeps them apart.
    rows: std.AutoHashMapUnmanaged(u64, stencil.Run) = .empty,
    ids: std.ArrayList(u32) = .empty,
    /// Patterns whose root pins nothing, tried at every node.
    open: std.ArrayList(u32) = .empty,

    fn deinit(s: *Sieve, gpa: std.mem.Allocator) void {
        s.rows.deinit(gpa);
        s.ids.deinit(gpa);
        s.open.deinit(gpa);
        s.* = undefined;
    }

    fn key(renamed: bool, index: u32) u64 {
        return (@as(u64, @intFromBool(renamed)) << 32) | index;
    }

    fn at(s: *const Sieve, kind: quire.Kind) []const u32 {
        const run = s.rows.get(key(kind.renamed, kind.index)) orelse return &.{};
        return s.ids.items[run.off..][0..run.len];
    }

    /// Two passes rather than one, because a pattern that turns out to be open
    /// must not have left half its kinds in the rows: `pinned` is a pure
    /// question and `sow` only runs once the answer is yes.
    fn of(s: *Sieve, gpa: std.mem.Allocator, p: stencil.Program) Error!void {
        // Gathered per key first, then laid out flat, so a row is a window and
        // not a list per kind.
        var per: std.AutoHashMapUnmanaged(u64, std.ArrayList(u32)) = .empty;
        defer {
            var it = per.valueIterator();
            while (it.next()) |v| v.deinit(gpa);
            per.deinit(gpa);
        }

        for (0..p.patternCount()) |i| {
            const pat = p.patternAt(@intCast(i));
            // A dead pattern is carried so it can be reported, and never run:
            // the compiler proved it cannot match, so trying it is work with a
            // known answer.
            if (pat.dead()) continue;
            if (!pinned(p, pat.root)) {
                try s.open.append(gpa, @intCast(i));
                continue;
            }
            try sow(gpa, p, pat.root, @intCast(i), &per);
        }

        var it = per.iterator();
        while (it.next()) |e| {
            const off: u32 = @intCast(s.ids.items.len);
            try s.ids.appendSlice(gpa, e.value_ptr.items);
            try s.rows.put(gpa, e.key_ptr.*, .{ .off = off, .len = @intCast(e.value_ptr.items.len) });
        }
    }

    /// Does every node this step could match name a kind? False for a wildcard,
    /// a `(_)`, a bare supertype, a top-level group, and for a choice with any
    /// arm that is one of those.
    fn pinned(p: stencil.Program, sid: u32) bool {
        const s = p.stepAt(sid);
        return switch (s.op) {
            .node, .literal => s.pinned(),
            .wildcard, .group => false,
            .choice => blk: {
                if (s.kids.len == 0) break :blk false;
                for (0..s.kids.len) |i| {
                    if (!pinned(p, p.refAt(s.kids.off + @as(u32, @intCast(i))))) break :blk false;
                }
                break :blk true;
            },
        };
    }

    fn sow(
        gpa: std.mem.Allocator,
        p: stencil.Program,
        sid: u32,
        pattern: u32,
        per: *std.AutoHashMapUnmanaged(u64, std.ArrayList(u32)),
    ) Error!void {
        const s = p.stepAt(sid);
        if (s.op == .choice) {
            for (0..s.kids.len) |i| {
                try sow(gpa, p, p.refAt(s.kids.off + @as(u32, @intCast(i))), pattern, per);
            }
            return;
        }
        for (0..s.kinds.len) |i| {
            try file(gpa, per, key(false, p.refAt(s.kinds.off + @as(u32, @intCast(i)))), pattern);
        }
        if (s.alias != none) try file(gpa, per, key(true, s.alias), pattern);
    }

    /// One pattern under one key, ascending and without repeats - a choice can
    /// name the same kind twice and a caller must not see the match twice.
    fn file(
        gpa: std.mem.Allocator,
        per: *std.AutoHashMapUnmanaged(u64, std.ArrayList(u32)),
        k: u64,
        pattern: u32,
    ) Error!void {
        const slot = try per.getOrPut(gpa, k);
        if (!slot.found_existing) slot.value_ptr.* = .empty;
        const got = slot.value_ptr;
        if (got.items.len != 0 and got.items[got.items.len - 1] == pattern) return;
        try got.append(gpa, pattern);
    }
};
