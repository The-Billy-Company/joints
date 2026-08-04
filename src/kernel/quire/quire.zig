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
const g = @import("../../press/grammar.zig");

/// Building one: a parse loop that keeps what `walk/drive.zig` throws away.
pub const gather = @import("gather.zig");
pub const Gather = gather.Gather;

/// An index into `Quire.nodes`.
pub const Ref = u32;

/// A `Ref`, field index or parent naming nothing: the parent of a root, or a
/// node no field files.
pub const none: u32 = std.math.maxInt(u32);

/// Why a parse stopped where it did. Only `accepted` is a whole tree; the rest
/// each name the exact byte or token that ended it, and the tree is still
/// handed back, because a partial tree plus the reason is strictly more useful
/// than an error with no prefix.
pub const Stop = union(enum) {
    accepted,
    /// No terminal this state would accept begins at this offset.
    stray: u32,
    /// A token that lexed and that no sequence of folds makes legal here. The
    /// state comes with it, since "state 803 has no `=`" is a diagnosis where
    /// "unexpected `=`" is a complaint.
    unexpected: struct { symbol: g.Symbol, at: u32, state: u32 },
    /// Input ended before the start symbol did.
    truncated,
};

/// What a node is called, and where the name came from.
///
/// Two sources and not one, because a rename is a use-site fact: the same
/// symbol is `identifier` at one site and `type_identifier` at another, so a
/// node has to remember which answer applied to it. Packed into a word because
/// this rides every node of every file.
pub const Kind = packed struct(u32) {
    /// Whether `index` is an entry in `Grammar.aliases` rather than a symbol.
    renamed: bool,
    index: u31,

    pub fn of(symbol: g.Symbol) Kind {
        return .{ .renamed = false, .index = @intCast(symbol) };
    }

    pub fn alias(index: u32) Kind {
        return .{ .renamed = true, .index = @intCast(index) };
    }
};

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
    gr: *const g.Grammar,
    nodes: []const Node,
    kids: []const Ref,
    /// The nodes standing at the top when the parse stopped. One, for a whole
    /// parse of a grammar whose start rule is visible; a forest of everything
    /// that had been completed, for a parse that stopped early.
    roots: []const Ref,
    stop: Stop,

    pub fn deinit(q: *Quire) void {
        q.gpa.free(q.nodes);
        q.gpa.free(q.kids);
        q.gpa.free(q.roots);
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
        const k = q.nodes[ref].kind;
        return if (k.renamed) q.gr.aliases[k.index].name else q.gr.nameOf(k.index);
    }

    /// Whether a query can match this node by name. False for a node spelled
    /// as itself - `("+")` - which has no rule name to be matched by.
    pub fn isNamed(q: *const Quire, ref: Ref) bool {
        const k = q.nodes[ref].kind;
        return if (k.renamed) q.gr.aliases[k.index].named else q.gr.shapeOf(k.index) == .named;
    }

    pub fn field(q: *const Quire, ref: Ref) ?[]const u8 {
        const f = q.nodes[ref].field;
        return if (f == none) null else q.gr.field_names[f];
    }

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
        const named = q.isNamed(ref);
        const kids = q.children(ref);
        // The ordinary anonymous node is a token and has nothing under it.
        // One with children exists only through `alias(rule, 'x')` declared
        // unnamed, and a query can still reach inside it, so it keeps a body.
        if (!named and kids.len == 0) return q.quote(out, gpa, ref);

        try out.append(gpa, '(');
        if (named) try out.appendSlice(gpa, q.name(ref)) else try q.quote(out, gpa, ref);
        for (kids) |c| {
            if (show == .named and !q.isNamed(c)) continue;
            try out.append(gpa, ' ');
            try q.print(out, gpa, c, show);
        }
        try out.append(gpa, ')');
    }

    fn quote(q: *const Quire, out: *std.ArrayList(u8), gpa: std.mem.Allocator, ref: Ref) !void {
        try out.append(gpa, '"');
        for (q.name(ref)) |ch| {
            if (ch == '"' or ch == '\\') try out.append(gpa, '\\');
            try out.append(gpa, ch);
        }
        try out.append(gpa, '"');
    }
};

test {
    std.testing.refAllDecls(@This());
    _ = @import("gather.zig");
    _ = @import("gather_test.zig");
}
