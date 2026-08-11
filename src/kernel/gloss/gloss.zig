//! The query front end: a `.scm` file in, a program in the folio out.
//!
//! tree-sitter ships a query as source and re-parses it in every process that
//! wants it. Here it is pressed once - names resolved to symbol ids, fields to
//! field ids, supertypes to a membership test, regexes proved compilable - and
//! carried in the artifact beside the tables it is about.
//!
//! Five layers, and each is ignorant of the one below on purpose:
//!
//!   `rubric`   syntax. Knows the notation, knows no grammar.
//!   `lemma`    the grammar's facts, indexed the way a query asks for them.
//!   `sift`     the predicate policy and the four filters we run ourselves.
//!   `stencil`  the program, and the bytes the folio carries it as.
//!   `scribe`   the program run against a tree, which is the only one of the
//!              five that needs one - and why the other four could be written
//!              before there was a tree to run them on.
//!
//! This file is the lowering that walks a rubric with a lemma in hand and
//! writes a stencil. It is also where **static reachability** lives, which is
//! the second thing tree-sitter does not do: tree-sitter checks that a node
//! name exists, and stops. We hold the grammar's productions, so we can also
//! prove that `(function_definition value: (x))` can never match because
//! `function_definition` carries no `value`, before anyone walks a tree with
//! it. A dead pattern is reported and carried with a flag rather than dropped -
//! the file said it, so the program says it.

const std = @import("std");
const rubric = @import("rubric.zig");
const lemma = @import("lemma.zig");
const sift = @import("sift.zig");
const stencil = @import("stencil.zig");
const scribe = @import("scribe.zig");

pub const Rubric = rubric.Rubric;
pub const Lemma = lemma.Lemma;
pub const Program = stencil.Program;
pub const Op = sift.Op;

/// Running one. `open` takes the program and the tree and hands back a cursor;
/// everything a match needs is built there and once.
pub const Ask = scribe.Ask;
pub const Cursor = scribe.Cursor;
pub const Match = scribe.Match;
pub const Capture = scribe.Capture;
pub const Foreign = scribe.Foreign;
pub const open = scribe.open;
/// Where a refusal happened, in the source the caller handed in. Re-exported
/// because a caller who compiles a file has to be able to say which byte of it
/// was wrong without importing the parser to name the type.
pub const Fault = rubric.Fault;

pub const read = rubric.read;
pub const index = lemma.of;
pub const program = stencil.read;

pub const Error = error{
    /// A name no rule in this grammar has. tree-sitter refuses here too, and
    /// so do we: a query naming a node that does not exist is a typo, not a
    /// pattern that happens to match nothing.
    QueryUnknownKind,
    /// A `"literal"` no anonymous terminal spells.
    QueryUnknownLiteral,
    QueryUnknownField,
    /// `(expression/binary_expression)` where `expression` is not a rule at
    /// all. Distinct from the membership failing, which is a dead pattern.
    QueryUnknownSupertype,
    /// A predicate argument naming a capture the pattern never binds.
    QueryUnknownCapture,
    /// Enough of a query to exceed what the program's `u32`s can address.
    QueryTooLarge,
} || rubric.Error || sift.Error || lemma.Error;

/// Why a pattern can never match. Each of these is a fact about the grammar
/// that a query author cannot see from the `.scm` alone, which is the whole
/// argument for checking it here.
pub const Cause = enum {
    /// This kind never carries this field.
    field_not_carried,
    /// This kind is not in that category.
    not_a_member,
    /// This kind can never hold that child, anywhere a splice could put it.
    child_not_admitted,
    /// A `!field` on a kind that could not have carried it anyway. Harmless,
    /// and worth saying: the constraint is doing nothing.
    absent_field_vacuous,
};

pub const Dead = struct {
    pattern: u32,
    cause: Cause,
    /// Byte offset of the position that made it dead.
    at: u32,
};

/// A compiled query, plus what the compiler noticed on the way through.
pub const Compiled = struct {
    gpa: std.mem.Allocator,
    /// The `gloss` section's bytes, ready for `folio.pack`.
    bytes: []u8,
    dead: []Dead,
    /// How many predicates landed outside the core four and are carried as
    /// metadata. Reported rather than refused; see `sift`'s header.
    opaque_predicates: u32,

    pub fn deinit(c: *Compiled) void {
        c.gpa.free(c.bytes);
        c.gpa.free(c.dead);
        c.* = undefined;
    }

    /// The program these bytes are. Never null for bytes this compiler wrote;
    /// the check is the same one `collate` runs, so a round trip proves the
    /// reader and the writer agree.
    pub fn view(c: *const Compiled) ?Program {
        return stencil.read(c.bytes);
    }
};

/// Compile one query file against one grammar.
///
/// `fault` is filled on every refusal and left alone on success, so a caller
/// may hand the same one to eighty-two files in a row. A syntax refusal fills
/// the byte; a resolution refusal fills the NAME, which is the difference
/// between "this file is wrong somewhere" and "this grammar has no
/// `type_identifier`".
pub fn compile(
    gpa: std.mem.Allocator,
    l: *const Lemma,
    src: []const u8,
    fault: ?*rubric.Fault,
) Error!Compiled {
    var r = try rubric.read(gpa, src, fault);
    defer r.deinit();
    return lower(gpa, l, &r, fault) catch |err| {
        // `Fault.name` is documented to borrow from `src`, and for every name
        // written as a bare word it does. A `"literal"` is the exception: the
        // reader unescapes it into the rubric's arena, so `"\\("` can reach a
        // regex as `\(`, and the `defer` above frees that arena on the way out
        // of this function. So the one refusal that named a literal handed back
        // a slice of memory this call had already released, and the caller
        // printed whatever was left there - blanks, in the case that found it.
        //
        // Re-cut from the source rather than copied, because a copy needs an
        // owner and a fault has none: it is a value the caller keeps on its own
        // stack. `at` is the start of the item, so the first quote at or after
        // it opens the literal - only an optional `field:` prefix and blanks
        // can stand between, and neither can hold a quote.
        if (fault) |f| if (!within(src, f.name)) {
            f.name = literalAt(src, f.at);
        };
        return err;
    };
}

/// Whether this slice points into those bytes.
///
/// Asked of the addresses and not of the contents, which is the difference
/// between the question and a plausible-looking answer to a different one: a
/// literal's unescaped text is very often a substring of the file that spelled
/// it - `"nil"` contains `nil` - so a content search would call the dangling
/// slice borrowed and leave the bug exactly where it was.
fn within(src: []const u8, name: []const u8) bool {
    if (name.len == 0) return true;
    const lo = @intFromPtr(src.ptr);
    const at = @intFromPtr(name.ptr);
    return at >= lo and at + name.len <= lo + src.len;
}

/// The literal that begins at or after `at`, quotes and all, as it stands in
/// the file. Empty when the source does not hold one - which cannot happen for
/// a refusal that named a literal, and is the right answer if it ever does.
///
/// Quotes included on purpose. `"fallthrough" is not a name go knows` says
/// which of the two namespaces was searched; `fallthrough is not a name go
/// knows` reads like a rule name and sends the reader looking in the other one.
fn literalAt(src: []const u8, at: u32) []const u8 {
    var i = @min(at, src.len);
    while (i < src.len and src[i] != '"') i += 1;
    if (i == src.len) return "";
    var j = i + 1;
    while (j < src.len) : (j += 1) {
        // The reader already accepted this string, so the closing quote is
        // there; the escape skip is what stops `"\""` from ending one byte early.
        if (src[j] == '\\') {
            j += 1;
            continue;
        }
        if (src[j] == '"') return src[i .. j + 1];
    }
    return "";
}

/// The same thing with the reading already done, for a caller measuring the
/// two halves apart.
pub fn lower(
    gpa: std.mem.Allocator,
    l: *const Lemma,
    r: *const Rubric,
    fault: ?*rubric.Fault,
) Error!Compiled {
    var w: Lowering = .{
        .gpa = gpa,
        .l = l,
        .draft = .{ .gpa = gpa },
        .fault = fault,
    };
    defer w.deinit();

    for (r.patterns, 0..) |pat, i| {
        w.pattern = @intCast(i);
        w.bound.clearRetainingCapacity();
        w.dead_here = null;
        const root = try w.item(pat.root, lemma.none);
        const preds = try w.predicates(pat.predicates);
        var flags: u32 = 0;
        if (w.dead_here) |d| {
            flags |= stencil.flag_dead;
            try w.dead.append(gpa, d);
        }
        try w.draft.pattern(root, preds, pat.at, flags);
    }

    const bytes = try w.draft.finish();
    errdefer gpa.free(bytes);
    return .{
        .gpa = gpa,
        .bytes = bytes,
        .dead = try w.dead.toOwnedSlice(gpa),
        .opaque_predicates = w.carried,
    };
}

const Lowering = struct {
    gpa: std.mem.Allocator,
    l: *const Lemma,
    draft: stencil.Draft,
    dead: std.ArrayList(Dead) = .empty,
    /// The captures this pattern binds, so a predicate naming one that was
    /// never written is refused rather than carried.
    bound: std.StringHashMapUnmanaged(u32) = .empty,
    /// Scratch for one level's children and captures. Depth-indexed by the
    /// mark/shrink pair, the same way `rubric`'s is.
    ids: std.ArrayList(u32) = .empty,
    pattern: u32 = 0,
    /// The first reason this pattern cannot match. First rather than all,
    /// because a pattern is dead once and the rest is noise.
    dead_here: ?Dead = null,
    /// Predicates outside the core four, carried rather than run.
    carried: u32 = 0,
    /// Where to write the name a refusal is about. Optional for the same reason
    /// the reader's is: a caller compiling one file already knows which.
    fault: ?*rubric.Fault = null,

    fn deinit(w: *Lowering) void {
        w.draft.deinit();
        w.dead.deinit(w.gpa);
        w.bound.deinit(w.gpa);
        w.ids.deinit(w.gpa);
        w.* = undefined;
    }

    fn kill(w: *Lowering, cause: Cause, at: u32) void {
        if (w.dead_here == null) w.dead_here = .{ .pattern = w.pattern, .cause = cause, .at = at };
    }

    /// Name the thing that did not resolve, then hand back the error that says
    /// what sort of thing it was. Written as a returner so every refusal site
    /// stays one expression - `orelse return w.blame(name, at, E.X)` - which is
    /// what stops the next one from forgetting the diagnostic half.
    fn blame(w: *Lowering, spelling: []const u8, at: u32, e: Error) Error {
        if (w.fault) |f| f.* = .{ .at = at, .name = spelling };
        return e;
    }

    /// One position. `parent` is the concrete kind this sits under, or
    /// `lemma.none` at the root and under anything whose kind is not pinned -
    /// a wildcard child of a wildcard admits everything, and saying so is
    /// cheaper than pretending otherwise.
    fn item(w: *Lowering, it: rubric.Item, parent: u32) Error!u32 {
        var s: stencil.Step = .{
            .op = .node,
            .kinds = .{ .off = 0, .len = 0 },
            .alias = lemma.none,
            .category = lemma.none,
            .field = lemma.none,
            .quantifier = @enumFromInt(@intFromEnum(it.quantifier)),
            .flags = if (it.anchored) stencil.flag_anchored else 0,
            .kids = .{ .off = 0, .len = 0 },
            .captures = .{ .off = 0, .len = 0 },
            .absent = .{ .off = 0, .len = 0 },
        };

        if (it.field) |spelling| {
            s.field = w.l.field(spelling) orelse
                return w.blame(spelling, it.at, Error.QueryUnknownField);
            if (parent != lemma.none and !w.l.carries(parent, s.field)) {
                w.kill(.field_not_carried, it.at);
            }
        }

        var kids: stencil.Run = .{ .off = 0, .len = 0 };
        var absent: stencil.Run = .{ .off = 0, .len = 0 };
        switch (it.shape) {
            .wildcard => s.op = .wildcard,
            .literal => |text| {
                s.op = .literal;
                // PHP writes `"and"` for a token the grammar spells as a
                // case-insensitive pattern and renames, so a literal is read in
                // both spaces exactly as a kind is.
                const r = w.l.reading(text, .literal);
                if (!r.known()) return w.blame(text, it.at, Error.QueryUnknownLiteral);
                s.kinds = try w.draft.run(r.syms);
                s.alias = r.alias;
                w.reachable(r, parent, it.at);
            },
            // A group is a sequence under the same parent and a choice is
            // several readings of one position, so neither pins a kind and both
            // pass the parent straight through.
            .group => |xs| {
                s.op = .group;
                kids = try w.children(xs, parent);
            },
            .choice => |xs| {
                s.op = .choice;
                kids = try w.children(xs, parent);
            },
            .node => |n| {
                const named = try w.name(n, it.at);
                s.kinds = try w.draft.run(named.read.syms);
                s.alias = named.read.alias;
                s.category = named.category;
                w.reachable(named.read, parent, it.at);
                absent = try w.absentFields(n, named.under(w.l), it.at);
                kids = try w.children(n.children, named.under(w.l));
                if (n.closed) s.flags |= stencil.flag_closed;
            },
        }

        const bound = try w.captures(it.captures);
        const id = try w.draft.step(s);
        w.draft.wire(id, kids, bound, absent);
        return id;
    }

    /// What a node's name resolved to.
    const Named = struct {
        read: lemma.Reading = .{},
        category: u32 = lemma.none,

        /// The symbol whose structure a child of this node should be checked
        /// against, or `none` for "ask nothing".
        ///
        /// A rename is a name, not a structure: what a `type_identifier` may
        /// hold is whatever `identifier` holds. So a spelling with one reading
        /// resolves to that reading's structure, and a spelling with two - or a
        /// rename over several symbols - resolves to nothing, because there is
        /// no single structure and a reachability claim has to be certain.
        fn under(n: Named, l: *const Lemma) u32 {
            if (n.read.syms.len == 1 and n.read.alias == lemma.none) return n.read.syms[0];
            if (n.read.syms.len == 0 and n.read.alias != lemma.none) {
                return l.beneath(n.read.alias) orelse lemma.none;
            }
            return lemma.none;
        }
    };

    /// Kill the pattern unless SOME reading of this name can sit under this
    /// parent. Both readings are live possibilities at match time, so one of
    /// them being admitted is enough to keep the pattern alive - which is the
    /// direction to err in, since the claim on the other side is "never".
    fn reachable(w: *Lowering, r: lemma.Reading, parent: u32, at: u32) void {
        if (parent == lemma.none or !r.known()) return;
        if (r.alias != lemma.none and w.l.admitsRename(parent, r.alias)) return;
        for (r.syms) |sym| if (w.l.admits(parent, sym)) return;
        w.kill(.child_not_admitted, at);
    }

    /// The kind and the category a node names.
    ///
    /// Three spaces, tried in the order a reader would: the grammar's own
    /// symbols, then renames (a name the tree wears that no symbol owns), then
    /// categories. `(_)` is a kind of `none`, and a bare category is the other
    /// way to have none - see below.
    fn name(w: *Lowering, n: rubric.Node, at: u32) Error!Named {
        var seen: lemma.Reading = .{};
        if (!std.mem.eql(u8, n.kind, "_")) {
            seen = w.l.reading(n.kind, .kind);
            if (!seen.known()) {
                // A bare supertype, written where a kind goes: Python's
                // `tags.scm` opens on `(expression_statement ...)` and Haskell
                // queries `(pattern)`. Both are hidden rules that emit no node,
                // so this is not a kind at all - it is the category, and what
                // the file is asking for is any member of it. Which is `(x/y)`
                // with the `y` left off, and lowers to exactly that.
                if (n.supertype == null) {
                    if (w.l.lookup(n.kind, .category)) |c| return .{ .category = c };
                }
                return w.blame(n.kind, at, Error.QueryUnknownKind);
            }
        }

        const super = n.supertype orelse return .{ .read = seen };
        const category = w.l.lookup(super, .category) orelse
            return w.blame(super, at, Error.QueryUnknownSupertype);
        // The membership is the whole reason a supertype is written down, and
        // it is the one reachability check the corpus was most likely to trip:
        // a grammar renames a rule and every `(expression/x)` naming the old
        // one silently matches nothing.
        // Membership is over symbols, and a rename is not one. A spelling that
        // has a rename reading at all could arrive as that rename, so the
        // membership question was never asked of it and cannot be answered no.
        if (seen.alias == lemma.none and seen.syms.len != 0) {
            var any = false;
            for (seen.syms) |sym| any = any or w.l.member(category, sym);
            if (!any) w.kill(.not_a_member, at);
        }
        return .{ .read = seen, .category = category };
    }

    fn absentFields(w: *Lowering, n: rubric.Node, kind: u32, at: u32) Error!stencil.Run {
        if (n.absent.len == 0) return .{ .off = 0, .len = 0 };
        const mark = w.ids.items.len;
        defer w.ids.shrinkRetainingCapacity(mark);
        for (n.absent) |f| {
            const id = w.l.field(f) orelse return w.blame(f, at, Error.QueryUnknownField);
            if (kind != lemma.none and !w.l.carries(kind, id)) w.kill(.absent_field_vacuous, at);
            try w.ids.append(w.gpa, id);
        }
        return w.draft.run(w.ids.items[mark..]);
    }

    fn children(w: *Lowering, xs: []const rubric.Item, parent: u32) Error!stencil.Run {
        if (xs.len == 0) return .{ .off = 0, .len = 0 };
        // The step ids have to exist before the run naming them does, and a
        // child's own lowering appends to the same list, so the ids are
        // collected into scratch first and handed over in one go.
        const mark = w.ids.items.len;
        defer w.ids.shrinkRetainingCapacity(mark);
        for (xs) |x| {
            const id = try w.item(x, parent);
            try w.ids.append(w.gpa, id);
        }
        return w.draft.run(w.ids.items[mark..]);
    }

    fn captures(w: *Lowering, names: []const []const u8) Error!stencil.Run {
        if (names.len == 0) return .{ .off = 0, .len = 0 };
        const mark = w.ids.items.len;
        defer w.ids.shrinkRetainingCapacity(mark);
        for (names) |n| {
            const id = try w.draft.capture(n);
            try w.bound.put(w.gpa, n, id);
            try w.ids.append(w.gpa, id);
        }
        return w.draft.run(w.ids.items[mark..]);
    }

    fn predicates(w: *Lowering, xs: []const rubric.Predicate) Error!stencil.Run {
        if (xs.len == 0) return .{ .off = 0, .len = 0 };
        const off = w.draft.predCount();
        for (xs) |p| {
            const got = try sift.read(w.gpa, p);
            if (!got.op.core()) w.carried += 1;
            const args_off = w.draft.argCount();
            for (got.args) |a| switch (a) {
                .capture => |c| {
                    // Only a core filter's captures are checked. An opaque
                    // predicate's arguments are somebody else's vocabulary and
                    // may not even be captures of ours.
                    const id = w.bound.get(c) orelse if (got.op.core())
                        return w.blame(c, p.at, Error.QueryUnknownCapture)
                    else
                        try w.draft.capture(c);
                    try w.draft.argCapture(id);
                },
                .text => |t| try w.draft.argText(t),
            };
            _ = try w.draft.predicate(got.op, got.name, .{
                .off = args_off,
                .len = w.draft.argCount() - args_off,
            });
        }
        return .{ .off = off, .len = w.draft.predCount() - off };
    }
};

test {
    _ = rubric;
    _ = lemma;
    _ = sift;
    _ = stencil;
    _ = scribe;
}
