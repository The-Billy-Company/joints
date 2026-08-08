//! The quire: the live, editable tree a parse yields.
//!
//! A quire is the loose gathering of leaves before it is bound, which is
//! exactly this object's job - it is the tree while it is still being changed.
//! Its settled form is vellum, the succinct encoding, and the two are the same
//! tree under different measures rather than two subsystems.
//!
//! The hard constraint here is not shape, it is naming: every node kind name
//! must be byte-identical to tree-sitter's, because every `highlights.scm` in
//! the world is keyed on those names. That is the whole reason the importer
//! exists, and it is why a node's name is read out of the grammar at the
//! moment it is asked for rather than copied into the node. There is exactly
//! one spelling of `binary_expression` in this process, and it is the one the
//! press interned.
//!
//! **Nodes are indices, not pointers.** A tree of a large file is the data
//! structure everything downstream pays for, so the arena is what a consumer
//! maps, slices, hands across the C ABI, or hands to the spine to hold; a
//! pointer is none of those. `Ref` is a `u32` into `nodes`, a node's children
//! are a run inside one flat `kids` array, and a node's `field` and `parent`
//! are the same kind of index. Nothing here owns anything but two slices.
//!
//! Read-only on purpose. The parse builds the arrays and hands them over once
//! (`gather.zig`); a `Quire` you are holding is finished. Edits belong to the
//! spine, which is not built yet, and keeping construction out of this type is
//! what leaves the storage a decision that can still be revisited.

const std = @import("std");

/// Building one: a parse loop that keeps what `walk/drive.zig` throws away.
pub const gather = @import("gather.zig");
pub const Gather = gather.Gather;
pub const Mend = gather.Mend;

/// Keeping a stretch of one's stack, so the next parse of nearly the same
/// bytes can start in the middle of the file.
pub const bough = @import("bough.zig");
pub const Bough = bough.Bough;

/// The neighbourhood accessors a query asks for. `Quire` aliases every one, so
/// this name is here for the doc comments rather than for calling through.
pub const reach = @import("reach.zig");

/// An index into `Quire.nodes`.
pub const Ref = u32;

/// How one byte of an anonymous node's own text is spelled inside quotes.
///
/// The rule both printers need and neither owned. `sexp` escaped `"` and `\`,
/// `--ranges` escaped `"` and `\`, and a token whose literal body carries a
/// control byte therefore printed the byte raw - which breaks the one contract
/// the ranged render rests on, that **one node is one line**. Nine verilog
/// tokens in `picorv32.v` do exactly that, and every reader of that render has
/// had to carry a rejoin for them.
///
/// Two sites had to move together or the s-expression and the outline would
/// name the same node differently, which is why neither moved. So the rule
/// lives here once and the sites are loops over it.
///
/// Deliberately narrower than `std.zig.stringEscape`: bytes at or above 0x80
/// pass through untouched, because a node name is UTF-8 and several grammars
/// spell anonymous tokens with it (`⟧`, `→`). Escaping those would re-render
/// trees that were never broken. Only what cannot survive a line survives as an
/// escape.
pub fn escape(ch: u8, buf: *[4]u8) []const u8 {
    return switch (ch) {
        '"' => "\\\"",
        '\\' => "\\\\",
        '\n' => "\\n",
        '\r' => "\\r",
        '\t' => "\\t",
        0...8, 0x0b, 0x0c, 0x0e...0x1f, 0x7f => blk: {
            const hex = "0123456789abcdef";
            buf.* = .{ '\\', 'x', hex[ch >> 4], hex[ch & 0xf] };
            break :blk buf[0..];
        },
        else => blk: {
            buf[0] = ch;
            break :blk buf[0..1];
        },
    };
}

/// A `Ref`, field index or parent naming nothing: the parent of a root, or a
/// node no field files.
pub const none: u32 = std.math.maxInt(u32);

/// Why a parse stopped where it did. Only `accepted` is a whole tree; the rest
/// each name the exact byte or token that ended it, and the tree is still
/// handed back, because a partial tree plus the reason is strictly more useful
/// than an error with no prefix.
pub const Stop = union(enum) {
    accepted,
    /// No terminal *in this grammar* lexes at this offset, under any state. A
    /// byte a reading merely cannot shift is `unexpected` instead, and the
    /// difference is load-bearing: one is a lexer's wall and the other is a
    /// table's, and only the second can be moved by changing the parse.
    stray: u32,
    /// A token that lexed and that no sequence of folds makes legal here. The
    /// state comes with it, since "state 803 has no `=`" is a diagnosis where
    /// "unexpected `=`" is a complaint.
    ///
    /// `folded` is the rest of that diagnosis: the reduces this token drove on
    /// its way to `state`, in the order it drove them. Without it a verdict can
    /// only say the table is damaged on this terminal *somewhere*, which names a
    /// suspect and proves nothing - see `press/inquest.zig`'s `dropped_elsewhere`.
    ///
    /// Optional because empty already means something else. A token refused
    /// before it folded anything drove no reduces, and that is a fact about the
    /// wall; `null` is the absence of the record, which is what a stop carried
    /// over from a previous parse or hung on a `Scar` has. Only the stop the
    /// parse reports is recorded, and the `Quire` holding it owns the slice -
    /// the gather that walked the folds is gone by the time anyone asks.
    unexpected: struct {
        symbol: press.Symbol,
        at: u32,
        state: u32,
        folded: ?[]const Fold = null,
    },
    /// Input ended before the start symbol did.
    truncated,
};

/// One reduce a refused token drove, as the state it ran in and the production
/// it folded.
///
/// Press's declaration rather than a third mirror of it. `kernel/walk/drive.zig`
/// keeps its own because it predates the verdict having a caller; there is no
/// reason for the loop that *feeds* `inquest` to add another, and a copy here
/// would need converting at every hand-off - in a diagnostic print path that has
/// no allocator to convert with.
const press = @import("../../press/press.zig");
pub const Fold = press.inquest.Fold;

/// One repair: a stop the parse recovered from instead of ending on.
///
/// **A deletion is not a node, and not a flag on one.** It deletes bytes; the
/// tree's own claim about them is that nothing covers them, so a node here
/// would mean inventing a parent for text the parse explicitly refused - and
/// would move `built` on every instrument that prices bytes under nodes. Nor is
/// there a node to annotate: it sits *between* what was built before the
/// refusal and what was built after the restart, and those are two subtrees. So
/// it is a side channel - `Quire.scars`, sorted by `at`, parallel to `nodes`
/// and indexed by nothing.
///
/// **A supply is a node, and is also one of these.** The two halves of that are
/// separate arguments and both are worth stating, because the sentence above
/// reads like it settles the question and it does not.
///
/// It is a node because the parse is *claiming structure* rather than refusing
/// text: `fn f() {` with the brace supplied is a block, and the tokens after it
/// belong inside one. Refusing to build the node would be refusing the repair
/// while performing it. And the node it builds cannot flatter a single
/// instrument on the way in - it covers **zero bytes**, so `built` cannot move
/// by it, and no byte's spine contains it, so a byte-indexed comparison against
/// tree-sitter cannot see it either. The only way a supply reaches any number
/// here is by letting *real* bytes fall under a parent they were not under
/// before, which is exactly the claim being made and exactly what should be
/// judged. That asymmetry - a deleted span is bytes with no node, a supplied
/// token is a node with no bytes - is why one belongs in the tree and the other
/// does not.
///
/// It is *also* one of these because it is a repair, and a consumer asking
/// "which of this did the author write" needs one place to ask. tree-sitter
/// splits the answer - `ERROR` is a node kind, `MISSING` is a bit on a node -
/// so a reader has to know both spellings. Here the tree says what was built
/// and this channel says what was repaired, whichever move made it, and the
/// node a supply built is named by `gave` at `at` with zero width. Nothing is
/// duplicated: no bit on `Kind` says `supplied`, because the join is exact and
/// putting half the record on the node is what makes two records.
///
/// This is the field's whole reason for existing: a node covering a byte proves
/// the parse did not refuse *there*, not that the byte was read as the author
/// wrote it. Without this list nobody downstream - an editor colouring a
/// region, an outline, an instrument pricing a corpus - can tell a stretch the
/// parser understood from one it papered over. tree-sitter answers the same
/// question with `ERROR` and `MISSING` nodes in the tree.
pub const Scar = struct {
    /// The byte the parse refused at.
    at: u32,
    /// The first byte it read again. `over - at` is what the repair deleted,
    /// and summing it over the list is `Quire.skipped`. Equal to `at` for a
    /// supply, which deletes nothing - but `at == over` is not the test for
    /// one, because an external scanner can hand back a zero-width terminal and
    /// a deletion of that token deletes nothing either. `gave` is the test.
    over: u32,
    /// The terminal this repair supplied, or null for one that deleted.
    ///
    /// A supply asserts the author omitted a fixed string the grammar spells
    /// itself, so the terminal is always an anonymous one: a zero-width
    /// instance of a *named* terminal is a token no lexer could produce, and
    /// claiming one would be saying text is missing without being able to say
    /// which. See `Gather.supply`.
    gave: ?press.Symbol = null,
    /// Live readings standing when the token was refused - the GLR heads, not
    /// the tree's roots. A break met by one reading is a parse that knew where
    /// it was and could not go on; a break met by many is an ambiguity
    /// collapsing, and a consumer ranking repairs wants to tell those apart.
    ///
    /// The first spelling of this field recorded `x.roots.len()` *after* the
    /// unwind, on the argument that a break should report the structure that
    /// survived it. Under `--mend=keep` nothing is ever unwound, so it read
    /// **zero on every scar of every grammar in the corpus** - a field that
    /// passes every test because it is constant. Counted at the refusal, before
    /// either branch touches `live`, it cannot be constant again: `keep` and
    /// `fell` both clear the list, so a reading taken after the branch is a
    /// reading of the repair rather than of the break.
    heads: u32,
    /// Tokens this parse had shifted when it refused. Absolute rather than a
    /// delta so a resumed parse can restore a prefix of the list without
    /// carrying a watermark; the delta between neighbours is what a reader
    /// wants, and **zero means this refusal is the previous one re-reported
    /// against the next token** rather than a second wall.
    shifted: u32,
    /// Whether the standing chain was carried off into the roots and stood back
    /// up in state zero (`fell`), or re-seated where the refusal left it
    /// (`keep`). This is what "how confident is the structure around it" comes
    /// to in this runtime: a felled break admits it lost the context, a kept one
    /// claims it did not. Always false for a supply, which is neither: the
    /// stack was never put down and never re-seated, it was read on to.
    felled: bool,
    /// The stop that would have ended the parse here - the refused terminal and
    /// the state that refused it, for a table wall; the byte, for a lexer's.
    /// Never `accepted` or `truncated`.
    why: Stop,

    pub fn len(s: Scar) u32 {
        return s.over - s.at;
    }
};

/// What a node is called, where the name came from, and whether a production
/// asked for it at all.
///
/// Two name sources and not one, because a rename is a use-site fact: the same
/// symbol is `identifier` at one site and `type_identifier` at another, so a
/// node has to remember which answer applied to it. `extra` rides here rather
/// than in its own byte for the same reason the rest is packed: this word is on
/// every node of every file, and 31 bits was already more index than any
/// grammar will ever spend.
pub const Kind = packed struct(u32) {
    /// Whether `index` is an entry in `Grammar.aliases` rather than a symbol.
    renamed: bool,
    /// Whether the grammar's `extras` put this node here rather than a
    /// production asking for it. tree-sitter exposes the same bit, and a
    /// consumer needs it: an extra is skipped by the field map and by a
    /// query's structural child index, so a node that is one is not the
    /// second child of anything.
    extra: bool = false,
    index: u30,

    pub fn of(symbol: press.Symbol) Kind {
        return .{ .renamed = false, .index = @intCast(symbol) };
    }

    /// A terminal the parse stepped over on its way to the next token.
    pub fn aside(symbol: press.Symbol) Kind {
        return .{ .renamed = false, .extra = true, .index = @intCast(symbol) };
    }

    pub fn alias(index: u32) Kind {
        return .{ .renamed = true, .index = @intCast(index) };
    }
};

/// What a kind is called, in the grammar's own spelling.
///
/// A fact about a `Kind` and a `Grammar`, not about whichever tree is holding
/// it - which is why it is a free function and not a method. `Quire` and
/// `vellum.Sheet` both answer this question about the same packed word, and
/// while each resolved alias-against-symbol itself there were two spellings of
/// one rule: settle a tree, rename a node, and only one of them learns.
pub fn nameOf(gr: *const press.Grammar, kind: Kind) []const u8 {
    return if (kind.renamed) gr.aliases[kind.index].name else gr.nameOf(kind.index);
}

/// Whether a query can match this kind by name. False for a node spelled as
/// itself - `("+")` - which has no rule name to be matched by.
pub fn named(gr: *const press.Grammar, kind: Kind) bool {
    return if (kind.renamed) gr.aliases[kind.index].named else gr.shapeOf(kind.index) == .named;
}

/// The name of a `Grammar.field_names` index, or absence for `none`.
pub fn fieldName(gr: *const press.Grammar, field: u32) ?[]const u8 {
    return if (field == none) null else gr.field_names[field];
}

pub const Node = struct {
    kind: Kind,
    /// Byte offset of the first byte this node covers. A node spans from its
    /// first token to its last, so the extras between them are inside it and
    /// the ones around it are not.
    start: u32,
    len: u32,
    /// This node's children: `kids[kids_at..][0..kids_len]`.
    kids_at: u32,
    kids_len: u32,
    parent: Ref = none,
    /// Which `Grammar.field_names` entry files this node in its parent, or
    /// `none`. On the child rather than in the parent's child list because a
    /// node has exactly one parent, which makes this four bytes that answer
    /// both directions of the question.
    field: u32 = none,

    pub fn end(n: Node) u32 {
        return n.start + n.len;
    }
};

/// Which nodes an s-expression shows. `named` is what `tree-sitter parse`
/// prints and what a test corpus is written in; `all` is the tree as it really
/// is, anonymous nodes included, which is what a query sees.
pub const Show = enum { named, all };

pub const Quire = struct {
    gpa: std.mem.Allocator,
    /// Borrowed. Names live here and nowhere else.
    gr: *const press.Grammar,
    nodes: []const Node,
    kids: []const Ref,
    /// The nodes standing at the top when the parse stopped. One, for a whole
    /// parse of a grammar whose start rule is visible; a forest of everything
    /// that had been completed, for a parse that stopped early.
    roots: []const Ref,
    stop: Stop,
    /// How many times the parse resynchronised. Zero is a parse that reached
    /// `stop` and ended there; anything else is a parse that reached it, put
    /// the stack down, and kept reading - so `stop` names where the trouble
    /// began and not where the forest ends. A reader that treats a stop as an
    /// end has to see this, or a recovered parse reads as a parse that gave up
    /// at the first wall.
    mends: u32 = 0,
    /// Bytes the parse walked past rather than read: the spans the mends
    /// deleted, summed. The companion to `mends` and the one that says how much
    /// of the file survived, since a mend now deletes a byte where it used to
    /// delete a kilobyte and a count cannot tell those apart. This is what the
    /// recovery fuse is denominated in.
    skipped: u32 = 0,
    /// How many times the parse supplied a terminal the grammar wanted and the
    /// author did not write, instead of deleting the token it could not read.
    ///
    /// Deliberately **not** folded into `mends`. A supply resynchronises
    /// nothing - the stack stands, the offset does not move, no byte is walked
    /// past - so counting it there would move a number thirty boards already
    /// read, for a repair that is not the thing that number means. `mends` is
    /// deletions, exactly as it was; `scars.len` is `mends + supplied`.
    supplied: u32 = 0,
    /// How many refusals had *several* terminals that would each have resumed
    /// the parse, and were therefore deleted rather than guessed at.
    ///
    /// The residue, counted at the moment it is created rather than
    /// reconstructed afterwards. A refusal with no candidate at all wants a
    /// repair this runtime does not have; one with two wants a rule for
    /// ranking them, which is a different lane's brief. Without this the two
    /// are one undifferentiated pile of scars.
    spurned: u32 = 0,
    /// Where each of those repairs happened and what it cost. `scars.len` is
    /// `mends + supplied` and the spans sum to `skipped`, so the counts above
    /// are this list folded - kept beside it because a fuse asks for the totals
    /// on every parse and only a reader asks for the sites.
    scars: []const Scar = &.{},

    pub fn deinit(q: *Quire) void {
        q.gpa.free(q.nodes);
        q.gpa.free(q.kids);
        q.gpa.free(q.roots);
        q.gpa.free(q.scars);
        if (q.stop == .unexpected) if (q.stop.unexpected.folded) |f| q.gpa.free(f);
        q.* = undefined;
    }

    /// The single top node, when there is one. Null for a partial parse that
    /// left a forest, and for the rare grammar whose start rule is hidden and
    /// splices into several.
    pub fn root(q: *const Quire) ?Ref {
        return if (q.roots.len == 1) q.roots[0] else null;
    }

    pub fn children(q: *const Quire, ref: Ref) []const Ref {
        const n = q.nodes[ref];
        return q.kids[n.kids_at..][0..n.kids_len];
    }

    /// What this node is called. The grammar's own spelling, whichever of the
    /// two places it came from.
    pub fn name(q: *const Quire, ref: Ref) []const u8 {
        return nameOf(q.gr, q.nodes[ref].kind);
    }

    /// Whether a query can match this node by name. False for a node spelled
    /// as itself - `("+")` - which has no rule name to be matched by.
    pub fn isNamed(q: *const Quire, ref: Ref) bool {
        return named(q.gr, q.nodes[ref].kind);
    }

    /// Whether the grammar's `extras` put this node here. A comment is a child
    /// like any other to a walk and to a query's `(comment)` pattern, and is
    /// skipped by everything that counts children structurally - which is why
    /// the answer has to be askable rather than inferable from the name.
    pub fn isExtra(q: *const Quire, ref: Ref) bool {
        return q.nodes[ref].kind.extra;
    }

    pub fn field(q: *const Quire, ref: Ref) ?[]const u8 {
        return fieldName(q.gr, q.nodes[ref].field);
    }

    // ── the neighbourhood ───────────────────────────────────────────────────
    //
    // What a query matcher asks a tree, in `reach.zig`. Its header carries the
    // two rules that run through all of them - the top of the tree is a run
    // rather than a node, and an extra is a child that does not count
    // structurally - and each accessor carries what it does about them.

    pub const parent = reach.parent;
    pub const among = reach.among;
    pub const nextSibling = reach.nextSibling;
    pub const prevSibling = reach.prevSibling;
    pub const nextNamedSibling = reach.nextNamedSibling;
    pub const prevNamedSibling = reach.prevNamedSibling;
    pub const childByFieldName = reach.childByFieldName;
    pub const descendantForByteRange = reach.descendantForByteRange;
    pub const depth = reach.depth;
    pub const subtreeSize = reach.subtreeSize;

    /// One subtree as an s-expression, in tree-sitter's spelling: a named node
    /// is `(name …)`, an anonymous one is the quoted string it is spelled as,
    /// and a field prefixes the child it files. Caller owns the bytes.
    ///
    /// Under `.named`, an anonymous child is skipped whole rather than
    /// descended through, which is what `ts_node_named_child` does: only an
    /// *invisible* symbol lifts its children, and an anonymous node is visible.
    pub fn sexp(q: *const Quire, gpa: std.mem.Allocator, ref: Ref, show: Show) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(gpa);
        try q.print(&out, gpa, ref, show);
        return out.toOwnedSlice(gpa);
    }

    fn print(q: *const Quire, out: *std.ArrayList(u8), gpa: std.mem.Allocator, ref: Ref, show: Show) !void {
        if (q.field(ref)) |f| {
            try out.appendSlice(gpa, f);
            try out.appendSlice(gpa, ": ");
        }
        const is_named = q.isNamed(ref);
        const kids = q.children(ref);
        // The ordinary anonymous node is a token and has nothing under it.
        // One with children exists only through `alias(rule, 'x')` declared
        // unnamed, and a query can still reach inside it, so it keeps a body.
        if (!is_named and kids.len == 0) return q.quote(out, gpa, ref);

        try out.append(gpa, '(');
        if (is_named) try out.appendSlice(gpa, q.name(ref)) else try q.quote(out, gpa, ref);
        for (kids) |c| {
            if (show == .named and !q.isNamed(c)) continue;
            try out.append(gpa, ' ');
            try q.print(out, gpa, c, show);
        }
        try out.append(gpa, ')');
    }

    /// Whether this is a tree at all, asked of the arena rather than of the
    /// s-expression it prints.
    ///
    /// Two parses can render the same string out of different arenas, and one
    /// of them can still be a structure no walk of the file could have made -
    /// a node standing under two parents, a run of siblings that overlap, a
    /// child reaching outside the span of the thing holding it. Every one of
    /// those is silent to `sexp`, and every one of them is what a reuse path
    /// produces when it carries a node in twice.
    ///
    /// So this asks the three questions the printer cannot: is every node
    /// reached exactly once, are the children of each node in source order and
    /// disjoint, and does each child lie inside its parent. Zero-length nodes
    /// are legal and land where a nullable reduction put them, so the ordering
    /// is `end <= start` rather than a strict one.
    ///
    /// Caller pays one bit per node, and one walk. `survey` is the walk counted
    /// rather than thrown, which is what a parse and a census want; `blame` turns
    /// its first fault into the sentence a reader wants.
    ///
    /// There used to be a `verify` here that did all three - walked, printed the
    /// first fault to stderr, and raised. It printed unconditionally, and its one
    /// caller is a fuzz that runs a *negative control*: four deliberately wrong
    /// composes whose whole job is to provoke faults like these. So a green run
    /// narrated ten corrupt quires it had asked for, on the stream the build
    /// runner reserves for failures, and every passing shard was captioned
    /// `failed command:`. Deciding whether a fault is news is the caller's
    /// question and only the caller has the answer, so the walk hands the fault
    /// back and says nothing.
    ///
    /// Which is the shape `spine`'s own `verify` already had - named errors, no
    /// stream - and the one this package should have been consistent about.
    pub fn blame(q: *const Quire, f: Fault) Blame {
        return .{ .q = q, .f = f };
    }

    /// A fault bound to the quire it was found in, because the sentence needs
    /// both: the fault knows what is wrong, the quire knows what the node is
    /// called and where it sits. `{f}` renders it.
    pub const Blame = struct {
        q: *const Quire,
        f: Fault,

        pub fn format(b: Blame, w: *std.Io.Writer) std.Io.Writer.Error!void {
            // Half the faults reported here are "that ref is not a node", so the
            // sentence may not dereference the ref it is reporting on.
            if (b.f.ref >= b.q.nodes.len) return w.print(
                "quire: {s} - ref {d} past {d} nodes, {d} roots",
                .{ b.f.why, b.f.ref, b.q.nodes.len, b.q.roots.len },
            );
            const n = b.q.nodes[b.f.ref];
            try w.print("quire: {s} - node {d} ({s}) at {d}..{d}, {d} roots over {d} nodes", .{
                b.f.why, b.f.ref, b.q.name(b.f.ref), n.start, n.end(), b.q.roots.len, b.q.nodes.len,
            });
        }
    };

    /// One thing wrong, and enough to name it in the caller's own terms.
    pub const Fault = struct {
        why: []const u8,
        ref: Ref,
        /// Whoever held it, or `none` when the fault is a root's.
        under: Ref,
    };

    /// Every way this arena is not a tree, counted.
    ///
    /// Three questions, not one, because they fail for different reasons and a
    /// reader acts on them differently: `torn` is a reuse path carrying a node
    /// in twice and is always a defect here; `loose` and `disorder` are spans
    /// disagreeing with parentage, which a grammar's own extras can produce.
    /// Counted rather than short-circuited so "one node in one grammar" reads
    /// differently from "a class of bug" - the distinction the census was
    /// keeping a second copy of this walk in order to make.
    pub const Survey = struct {
        loose: u32 = 0,
        disorder: u32 = 0,
        torn: u32 = 0,
        /// The positive half of the answer: how many nodes the walk reached
        /// from a root, out of how many the arena holds.
        ///
        /// Three counts of nothing wrong is what a walk that ran reports AND
        /// what a walk that never ran reports, and a caller holding only
        /// `sound()` cannot tell the two apart - so a survey that stopped
        /// being called reads exactly like a corpus that is clean. That is the
        /// same silence `collate`'s `recall` and `shear`'s `cut_rubble` were
        /// each repaired for, and it is worse here because this is the only
        /// interior check anything runs on every parse.
        ///
        /// `walked` starts below `q.nodes.len` and cannot exceed it, so
        /// `walked == held` is a claim with a size in it: a caller can insist
        /// the survey covered the arena rather than merely declining to
        /// complain about it. A shortfall is NOT counted as a fault here -
        /// nodes the arena holds and no root reaches are a construction
        /// question, not a tree that contradicts itself - it is reported so
        /// whoever asks can see it.
        walked: u32 = 0,
        held: u32 = 0,
        first: ?Fault = null,

        pub fn sound(s: Survey) bool {
            return s.loose + s.disorder + s.torn == 0;
        }

        /// The first fault wins, because it is the one closest to the cause;
        /// the counts beside it say how far it spread.
        fn note(s: *Survey, ref: Ref, under: Ref, why: []const u8) void {
            if (s.first == null) s.first = .{ .why = why, .ref = ref, .under = under };
        }
    };

    /// Whether this is a tree at all, asked of the arena rather than of the
    /// s-expression it prints - and asked in full, so the answer is a count.
    pub fn survey(q: *const Quire, gpa: std.mem.Allocator) !Survey {
        var found: Survey = .{ .held = @intCast(q.nodes.len) };
        var seen = try std.DynamicBitSet.initEmpty(gpa, q.nodes.len);
        defer seen.deinit();
        var walk: std.ArrayList(Ref) = .empty;
        defer walk.deinit(gpa);

        order(q, q.roots, none, &found);
        for (q.roots) |r| {
            if (r >= q.nodes.len) {
                found.torn += 1;
                found.note(r, none, "root out of range");
                continue;
            }
            // Already seen means already walked, so it is never pushed twice
            // and the walk below terminates however tangled the arena is.
            if (seen.isSet(r)) {
                found.torn += 1;
                found.note(r, none, "node is a root twice");
                continue;
            }
            seen.set(r);
            try walk.append(gpa, r);
        }
        while (walk.pop()) |ref| {
            const n = q.nodes[ref];
            if (n.kids_at + n.kids_len > q.kids.len) {
                found.torn += 1;
                found.note(ref, none, "kids out of range");
                continue;
            }
            const kids = q.kids[n.kids_at..][0..n.kids_len];
            order(q, kids, ref, &found);
            for (kids) |c| {
                if (c >= q.nodes.len) {
                    found.torn += 1;
                    found.note(c, ref, "child out of range");
                    continue;
                }
                // The one that matters. A node reached twice is a node some
                // reuse path copied in twice, and it prints as two nodes.
                if (seen.isSet(c)) {
                    found.torn += 1;
                    found.note(c, ref, "node reached twice");
                    continue;
                }
                seen.set(c);
                try walk.append(gpa, c);
            }
        }
        // Off the bit set rather than a counter incremented beside every
        // `seen.set`: the set is what the walk actually marked, and a second
        // tally of the same event is a second thing to keep in step.
        found.walked = @intCast(seen.count());
        return found;
    }

    /// Siblings run left to right and do not overlap, and stay inside whoever
    /// holds them. `under` is `none` for the roots, which have no container.
    ///
    /// The only spelling of the containment predicate in this project. It was
    /// two until 2026-08-05 - this one, reached by nothing but the amend fuzz,
    /// and a second walk in `census_test.zig` that was the only reason anyone
    /// knew toml violates it.
    fn order(q: *const Quire, kids: []const Ref, under: Ref, found: *Survey) void {
        var at: u32 = 0;
        for (kids, 0..) |c, i| {
            if (c >= q.nodes.len) continue;
            const n = q.nodes[c];
            if (i > 0 and n.start < at) {
                found.disorder += 1;
                found.note(c, under, "sibling overlaps the one before it");
            }
            at = n.end();
            if (under == none) continue;
            const p = q.nodes[under];
            if (n.start < p.start or n.end() > p.end()) {
                found.loose += 1;
                found.note(c, under, "child outside its parent");
            }
        }
    }

    fn quote(q: *const Quire, out: *std.ArrayList(u8), gpa: std.mem.Allocator, ref: Ref) !void {
        try out.append(gpa, '"');
        var buf: [4]u8 = undefined;
        for (q.name(ref)) |ch| try out.appendSlice(gpa, escape(ch, &buf));
        try out.append(gpa, '"');
    }
};

test {
    std.testing.refAllDecls(@This());
    _ = @import("gather.zig");
}
