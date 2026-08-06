//! The writer: a pressed grammar in, one sealed buffer of folio bytes out.
//!
//! Two passes, because the header has to say how long the file is before the
//! file exists. The first runs every string into one arena and counts every
//! section; the second lays the sections out at eight-aligned offsets, fills
//! them, and seals the lot. Nothing is appended and nothing is patched
//! afterwards, so there is no window in which a half-built folio carries a valid
//! seal.
//!
//! Every press-side value is converted explicitly - a `switch` over the press's
//! action verbs, a `switch` over its shapes, a field-by-field copy of every
//! record. That is deliberately more code than memcpy'ing the structs. Somebody
//! else is editing the press right now, and the whole point of having a format
//! is that a change over there stops here as a compile error instead of
//! arriving in a stranger's file as a number that used to mean something.

const std = @import("std");
const forme = @import("forme.zig");
const leaf = @import("leaf.zig");
const g = @import("../press/grammar.zig");
const lalr = @import("../press/lalr.zig");
const lr0 = @import("../press/lr0.zig");
const press = @import("../press/press.zig");
const settle = @import("../press/settle.zig");
const lex = @import("../kernel/lex/scanner.zig");

const cell = forme.cell;

// ── the ledger: which press-side fields this writer is answerable for ──
//
// A `switch` stops here as a compile error when the press *renames* something.
// It says nothing when the press *adds* something, and the added field is the
// worse failure of the two, because it is silent on both sides. The new field
// is simply not written; `bind` fills it with its default; every check anyone
// owns still passes, and a measurement across the corpus comes back "30
// grammars byte-identical, 0 moved". That is a lie in the direction of "your
// change did nothing", and the correct response to it is to abandon a change
// that works. It cost this fix a day and very nearly cost it entirely.
//
// So the roster is written down, and every field of a carried record must
// appear on it. Adding `merged: bool` to `Conflict` now fails the build with
// the name of the field and the two things that may be done about it, which is
// the whole intent: not to forbid a field, but to make its absence from the
// file a decision somebody made rather than one nobody noticed.
const ledger = struct {
    const conflict: []const []const u8 = &.{
        "state",  "terminal", "kind", "class",
        "chosen", "other",    "rest", "party",
    };
    const frayed: []const []const u8 = &.{ "state", "terminal", "harm" };
    /// `alias` and `field` are written; `prec`, `assoc` and `spliced` are not,
    /// and that is the answer rather than an omission.
    ///
    /// A folio carries the table and not the argument that produced it. Static
    /// precedence is spent while the cells are being decided — the loser is
    /// gone before a parse begins — so there is nothing left for a reader to
    /// do with it, and `bind` says so where it rebuilds a step. `spliced` is a
    /// fact *about* those two: whether the rank on this step was absorbed from
    /// a rule the press folded away or written where it sits. It reaches
    /// exactly one reader, `Ladder.purely`, which runs during the press, so it
    /// travels no further than they do.
    ///
    /// Named here anyway, and this is the whole point of the roster: the
    /// previous lane read `Step` as `leaf.StepRecord` and stopped at a format
    /// change that does not exist. Nothing on either side of the build could
    /// have corrected it, because `accounts` was never called on this type -
    /// so a fourth press-only field could have been added tomorrow with the
    /// same silence that once reported "30 grammars byte-identical, 0 moved".
    /// Now it cannot: the question gets asked, and the answer is on the record.
    const step: []const []const u8 = &.{ "prec", "assoc", "spliced", "alias", "field" };
    /// `arena` is who owns the memory rather than part of the table, and
    /// `seams` is the unfolding search's *input* - a folio carries the cells
    /// the search decided, not the search. Both are deliberate, and a folio is
    /// still expected to reproduce them as empty rather than as wrong.
    const tables: []const []const u8 = &.{
        "arena", "seams", "end", "width", "action", "conflicts", "frayed",
    };
};

comptime {
    accounts(lalr.Conflict, ledger.conflict);
    accounts(settle.Frayed, ledger.frayed);
    accounts(lalr.Tables, ledger.tables);
    accounts(g.Step, ledger.step);
    // The stored tag is an ordinal, so these three enums *are* the file format
    // for their column. Same names in the same order on both sides, or a folio
    // written today says something else to a reader built tomorrow.
    concurs(settle.Conflict.Class, leaf.ConflictClass);
    concurs(settle.Conflict.Kind, leaf.ConflictKind);
    concurs(settle.Frayed.Harm, leaf.Harm);
}

/// Every field of `T` is named in `roll`, and every name in `roll` is a field
/// of `T`. The second half matters as much as the first: a roll that outlives
/// the field it names is a roll nobody is reading.
fn accounts(comptime T: type, comptime roll: []const []const u8) void {
    const fields = std.meta.fields(T);
    for (fields) |f| {
        for (roll) |name| {
            if (std.mem.eql(u8, name, f.name)) break;
        } else @compileError(@typeName(T) ++ "." ++ f.name ++
            " is new to the press and unaccounted for in the folio. Give it a" ++
            " slot in its `leaf` record and write it below, or name it in" ++
            " `ledger` with a comment saying why the file does not need it." ++
            " Silence here reads downstream as `your change did nothing`.");
    }
    for (roll) |name| {
        for (fields) |f| {
            if (std.mem.eql(u8, name, f.name)) break;
        } else @compileError(@typeName(T) ++ " has no field `" ++ name ++
            "`; `ledger` is stale, delete the entry.");
    }
}

/// Two enums with the same names on the same ordinals.
fn concurs(comptime Press: type, comptime Leaf: type) void {
    const here = std.meta.fields(Press);
    const disk = std.meta.fields(Leaf);
    if (here.len != disk.len) @compileError(@typeName(Press) ++ " and " ++
        @typeName(Leaf) ++ " differ in length; a class the press can produce" ++
        " and the format cannot spell is a class that round-trips as another one." ++
        " Append the missing member - never insert one.");
    for (here, disk) |a, b| {
        if (!std.mem.eql(u8, a.name, b.name) or a.value != b.value) {
            @compileError(@typeName(Press) ++ "." ++ a.name ++ " sits where " ++
                @typeName(Leaf) ++ "." ++ b.name ++ " does. The ordinal is what" ++
                " is on disk, so reordering renames every folio already written.");
        }
    }
}

/// What packing can refuse on. Two of them are this file's own; the rest are
/// the scanner's, unioned rather than translated because building the lexicon
/// section is the one place the writer does work of its own and the work can
/// fail on its own terms. Naming them here rather than folding them into a
/// `CannotWriteThisDown` is deliberate: a caller that sees
/// `TerminalWithoutPattern` is looking at a press bug, and one that sees
/// `OutOfMemory` is looking at a machine, and a single name for both is how
/// `slate` came to swallow three faults for a year. See `slate`.
pub const Error = error{
    /// Some count does not fit in the `u32` the format spends on it. A grammar
    /// that size is not a problem to solve quietly.
    GrammarTooLarge,
    /// A production's steps are not parallel to its right-hand side, which the
    /// press promises they are. Loud, because the alternative is writing a
    /// rename onto the wrong child.
    StepsNotParallel,
} || std.mem.Allocator.Error || lex.CompileError || lex.FreezeError;

/// The bytes of a folio for this grammar and this pressing.
///
/// Eight-aligned, because the reader views records where they lie and a
/// misaligned buffer would make that undefined rather than merely slow. Free it
/// with `gpa.free`.
pub fn pack(
    gpa: std.mem.Allocator,
    gr: *const g.Grammar,
    result: *const press.Result,
) Error![]align(leaf.section_align) u8 {
    var plan = try Plan.of(gpa, gr, result);
    defer plan.deinit(gpa);
    return plan.emit(gpa, gr, result);
}

/// This grammar's terminal slate, determinized here so that nobody has to do it
/// at load. Empty for a grammar with nothing lexable, and empty rather than
/// fatal for an automaton the format cannot write down: that section is an
/// answer we can always work out again, so declining to publish one is a slower
/// folio and never a wrong one.
///
/// Empty for those two and nothing else. Both arrive as `null` from the
/// scanner, which is what lets everything on the error path be a fault and be
/// raised; see the note in the body for what that arm used to do instead.
///
/// This is the one place the writer does real work rather than laying out work
/// already done. It is worth it here for the same reason it is not worth it at
/// load: a folio is written once and read every time a parse starts.
fn slate(gpa: std.mem.Allocator, gr: *const g.Grammar) Error![]const u8 {
    // Both degradations this function exists to make are on the `orelse`s, and
    // that is the whole finding. A grammar with nothing lexable is real and
    // common - yaml declares 113 externals and not one pattern - and `compile`
    // spells it `null`. An automaton the format will not carry is real too, and
    // `freeze` spells that `null` as well. So the error path never once meant
    // "degrade", and the arm that read it that way was catching four faults and
    // three of them by accident.
    //
    // What made it invisible was the width rather than the intent: both callees
    // inferred their error sets, so `else` absorbed whatever they grew into, and
    // a logic fault added downstream would have arrived here dressed as "this
    // grammar has nothing lexable". Nothing catches that at mint, because an
    // empty slate is a valid folio and the writer reports success. It was never
    // silent outright - the refusal is not cached, so load compiles the scanner
    // again and fails there - but a deferred report attributed to the wrong
    // cause is most of the way to a lost one.
    //
    // Now the sets are named, so this is a `try` and the enumeration lives in
    // `Error`. The property worth keeping is not that these five propagate; it
    // is that a sixth cannot arrive quietly. `CompileError` and `FreezeError`
    // are closed, so growing one breaks this file at the moment it grows, which
    // is when somebody still knows what the new failure means.
    var sc = try lex.Scanner.compile(gpa, gr) orelse return &.{};
    defer sc.deinit();
    return try sc.freeze(gpa) orelse &.{};
}

/// Everything the layout needs before a single section byte is written: where
/// each string landed, and how many records each section holds.
const Plan = struct {
    text: std.ArrayList(u8) = .empty,
    title: leaf.Span = .{ .off = 0, .len = 0 },
    names: []leaf.Span = &.{},
    patterns: []leaf.PatternRecord = &.{},
    aliases: []leaf.AliasRecord = &.{},
    fields: []leaf.Span = &.{},
    /// Every distinct step, and one id per body position pointing into it.
    /// A grammar has a few dozen things to say about its children and tens of
    /// thousands of places to say them, nearly all of which say nothing.
    steps: std.ArrayList(leaf.StepRecord) = .empty,
    stepref: std.ArrayList(u32) = .empty,
    body_len: u32 = 0,
    complete_len: u32 = 0,
    party_len: u32 = 0,
    rival_len: u32 = 0,
    /// The table, already interned. Built here rather than while filling,
    /// because the directory has to know how many groups there are before a
    /// group is written.
    table: forme.Forme = undefined,
    locked: bool = false,
    /// This grammar's slate, already determinized. Empty when the grammar has
    /// no lexable terminal at all, or when the slate holds an automaton the
    /// format refuses - a folio without one costs startup, never correctness.
    lexicon: []const u8 = &.{},

    fn of(gpa: std.mem.Allocator, gr: *const g.Grammar, result: *const press.Result) Error!Plan {
        var p: Plan = .{};
        errdefer p.deinit(gpa);
        p.table = try forme.lock(gpa, gr, result);
        p.locked = true;
        p.lexicon = try slate(gpa, gr);
        p.names = try gpa.alloc(leaf.Span, gr.names.len);
        p.patterns = try gpa.alloc(leaf.PatternRecord, gr.patterns.len);
        p.aliases = try gpa.alloc(leaf.AliasRecord, gr.aliases.len);
        p.fields = try gpa.alloc(leaf.Span, gr.field_names.len);

        p.title = try p.intern(gpa, gr.name);
        for (gr.names, 0..) |name, i| p.names[i] = try p.intern(gpa, name);
        for (gr.patterns, 0..) |pat, i| p.patterns[i] = try p.pattern(gpa, pat);
        for (gr.aliases, 0..) |alias, i| {
            const at = try p.intern(gpa, alias.name);
            p.aliases[i] = .{ .off = at.off, .len = at.len, .named = @intFromBool(alias.named) };
        }
        for (gr.field_names, 0..) |name, i| p.fields[i] = try p.intern(gpa, name);

        var seen: std.AutoHashMapUnmanaged(u64, u32) = .empty;
        defer seen.deinit(gpa);
        for (gr.productions) |prod| {
            if (prod.steps.len != prod.rhs.len) return Error.StepsNotParallel;
            p.body_len = try add(p.body_len, prod.rhs.len);
            for (prod.steps) |st| {
                const rec: leaf.StepRecord = .{
                    .alias = st.alias orelse leaf.none,
                    .field = st.field orelse leaf.none,
                };
                const slot = try seen.getOrPut(gpa, @as(u64, rec.alias) << 32 | rec.field);
                if (!slot.found_existing) {
                    slot.value_ptr.* = try fits(p.steps.items.len);
                    try p.steps.append(gpa, rec);
                }
                try p.stepref.append(gpa, slot.value_ptr.*);
            }
        }
        for (result.collection.states) |st| {
            p.complete_len = try add(p.complete_len, st.complete.len);
        }
        for (result.tables.conflicts) |k| {
            p.party_len = try add(p.party_len, k.party.len);
            p.rival_len = try add(p.rival_len, k.rest.len);
        }
        return p;
    }

    /// A nonterminal has no pattern at all, which is not the same fact as
    /// `.external` - that one is a scanner we do not have, and a consumer has
    /// to be able to refuse over it.
    fn pattern(p: *Plan, gpa: std.mem.Allocator, pat: ?g.Pattern) Error!leaf.PatternRecord {
        const spelling: []const u8, const kind: leaf.PatternKind = switch (pat orelse
            return .{ .kind = @intFromEnum(leaf.PatternKind.none), .off = 0, .len = 0 }) {
            .literal => |s| .{ s, .literal },
            .regex => |s| .{ s, .regex },
            .external => return .{ .kind = @intFromEnum(leaf.PatternKind.external), .off = 0, .len = 0 },
        };
        const at = try p.intern(gpa, spelling);
        return .{ .kind = @intFromEnum(kind), .off = at.off, .len = at.len };
    }

    fn intern(p: *Plan, gpa: std.mem.Allocator, s: []const u8) Error!leaf.Span {
        const off = try fits(p.text.items.len);
        try p.text.appendSlice(gpa, s);
        _ = try fits(p.text.items.len);
        return .{ .off = off, .len = try fits(s.len) };
    }

    fn deinit(p: *Plan, gpa: std.mem.Allocator) void {
        p.text.deinit(gpa);
        gpa.free(p.names);
        gpa.free(p.patterns);
        gpa.free(p.aliases);
        gpa.free(p.fields);
        p.steps.deinit(gpa);
        p.stepref.deinit(gpa);
        gpa.free(p.lexicon);
        if (p.locked) p.table.deinit();
    }

    fn count(p: *const Plan, k: leaf.Kind, gr: *const g.Grammar, result: *const press.Result) u32 {
        const states: u32 = @intCast(result.collection.states.len);
        return switch (k) {
            .text => @intCast(p.text.items.len),
            .name, .pattern, .lexis, .shape, .owner => @intCast(gr.names.len),
            .supertype => @intCast(gr.supertypes.len),
            .extra => @intCast(gr.extras.len),
            .alias => @intCast(gr.aliases.len),
            .field => @intCast(gr.field_names.len),
            .production => @intCast(gr.productions.len),
            .rhs, .stepref => p.body_len,
            .step => @intCast(p.steps.items.len),
            .row => states,
            .row_span => @intCast(p.table.row_span.len),
            .groupref => @intCast(p.table.groupref.len),
            .group => @intCast(p.table.group.len),
            .set_span => @intCast(p.table.set_span.len),
            .setsym => @intCast(p.table.setsym.len),
            .odd => @intCast(p.table.odd.len),
            .complete_span => states + 1,
            .complete => p.complete_len,
            .conflict => @intCast(result.tables.conflicts.len),
            .party => p.party_len,
            .frayed => @intCast(result.tables.frayed.len),
            .lexicon => @intCast(p.lexicon.len),
            .rival => p.rival_len,
        };
    }

    /// How wide a section's records are. Only the narrow ones have a choice,
    /// and each is measured against what its ids point at rather than against
    /// how many of them there are.
    fn stride(p: *const Plan, k: leaf.Kind, gr: *const g.Grammar, result: *const press.Result) u16 {
        return leaf.strideFor(k, switch (k) {
            .groupref => @intCast(p.table.group.len),
            .setsym => result.tables.width + (@as(u32, @intCast(gr.names.len)) - gr.terminal_count),
            .stepref => @intCast(p.steps.items.len),
            else => 0,
        });
    }

    fn emit(
        p: *const Plan,
        gpa: std.mem.Allocator,
        gr: *const g.Grammar,
        result: *const press.Result,
    ) Error![]align(leaf.section_align) u8 {
        var dir: [leaf.kind_count]leaf.Entry = undefined;
        var at: u64 = leaf.align8(leaf.header_len + leaf.kind_count * leaf.entry_len);
        for (std.enums.values(leaf.Kind)) |k| {
            const n = p.count(k, gr, result);
            const wide = p.stride(k, gr, result);
            dir[@intFromEnum(k)] = .{ .kind = k, .stride = wide, .count = n, .offset = at };
            at = leaf.align8(at + @as(u64, n) * wide);
        }
        const file_len = try fitsUsize(at + leaf.signet.len);

        // Zeroed, so the padding between sections is a fact rather than
        // whatever the allocator last left there. Pressing the same grammar
        // twice has to produce the same bytes, or the seal is the only thing
        // in the file that ever changes.
        const buf = try gpa.alignedAlloc(u8, comptime .fromByteUnits(leaf.section_align), file_len);
        errdefer gpa.free(buf);
        @memset(buf, 0);

        const head: leaf.Head = .{
            .version = leaf.version,
            .section_count = leaf.kind_count,
            .symbol_count = @intCast(gr.names.len),
            .terminal_count = gr.terminal_count,
            .state_count = @intCast(result.collection.states.len),
            .width = result.tables.width,
            .end = result.tables.end,
            .production_count = @intCast(gr.productions.len),
            .start = gr.start,
            .word = gr.word orelse leaf.none,
            .unfolded = result.unfolded,
            .title = p.title,
            .schema = leaf.schema(),
            .file_len = file_len,
        };
        head.write(buf[0..leaf.header_len]);
        for (dir, 0..) |e, i| e.write(buf[leaf.header_len + i * leaf.entry_len ..][0..leaf.entry_len]);

        for (dir) |e| {
            const off: usize = @intCast(e.offset);
            p.fill(e, buf[off..][0 .. @as(usize, e.count) * e.stride], gr, result);
        }
        leaf.signet.sealAt(buf, file_len - leaf.signet.len);
        return buf;
    }

    fn fill(
        p: *const Plan,
        e: leaf.Entry,
        out: []u8,
        gr: *const g.Grammar,
        result: *const press.Result,
    ) void {
        var w: Writer = .{ .out = out, .narrow = e.stride == 2 };
        switch (e.kind) {
            .text => @memcpy(out, p.text.items),
            .lexicon => @memcpy(out, p.lexicon),
            .name => for (p.names) |s| w.span(s),
            .pattern => for (p.patterns) |r| {
                w.put(r.kind);
                w.put(r.off);
                w.put(r.len);
            },
            .lexis => for (gr.lexis) |lx| {
                w.put(if (lx.immediate) leaf.LexisRecord.immediate else 0);
                w.putSigned(lx.prec);
            },
            .shape => for (gr.shapes) |s| w.put(@intFromEnum(shapeOf(s))),
            .owner => for (gr.owner) |s| w.put(s),
            .supertype => for (gr.supertypes) |s| w.put(s),
            .extra => for (gr.extras) |s| w.put(s),
            .alias => for (p.aliases) |r| {
                w.put(r.off);
                w.put(r.len);
                w.put(r.named);
            },
            .field => for (p.fields) |s| w.span(s),
            .production => {
                var off: u32 = 0;
                for (gr.productions) |prod| {
                    w.put(prod.lhs);
                    w.put(off);
                    w.put(@intCast(prod.rhs.len));
                    w.putSigned(prod.dynamic);
                    off += @intCast(prod.rhs.len);
                }
            },
            .rhs => for (gr.productions) |prod| {
                for (prod.rhs) |s| w.put(s);
            },
            .stepref => for (p.stepref.items) |id| w.id(id),
            .step => for (p.steps.items) |st| {
                w.put(st.alias);
                w.put(st.field);
            },
            .row => for (p.table.row) |r| w.put(r),
            .row_span => for (p.table.row_span) |n| w.put(n),
            .groupref => for (p.table.groupref) |id| w.id(id),
            .group => for (p.table.group) |rec| {
                w.put(rec.cell);
                w.put(rec.set);
            },
            .set_span => for (p.table.set_span) |n| w.put(n),
            .setsym => for (p.table.setsym) |col| w.id(col),
            .odd => for (p.table.odd) |rec| {
                w.put(rec.state);
                w.put(rec.symbol);
                w.put(rec.target);
            },
            .complete_span => w.spans(result.collection.states, completeCount),
            .complete => for (result.collection.states) |st| {
                for (st.complete) |prod| w.put(prod);
            },
            .conflict => {
                var off: u32 = 0;
                var rest: u32 = 0;
                for (result.tables.conflicts) |x| {
                    w.put(x.state);
                    w.put(x.terminal);
                    w.put(@intFromEnum(switch (x.kind) {
                        .shift_reduce => leaf.ConflictKind.shift_reduce,
                        .reduce_reduce => leaf.ConflictKind.reduce_reduce,
                    }));
                    w.put(@intFromEnum(switch (x.class) {
                        .repetition => leaf.ConflictClass.repetition,
                        .declared => leaf.ConflictClass.declared,
                        .residual => leaf.ConflictClass.residual,
                        .unwritten => leaf.ConflictClass.unwritten,
                    }));
                    w.put(cell(x.chosen));
                    w.put(cell(x.other));
                    w.put(off);
                    w.put(@intCast(x.party.len));
                    w.put(rest);
                    w.put(@intCast(x.rest.len));
                    off += @intCast(x.party.len);
                    rest += @intCast(x.rest.len);
                }
            },
            .party => for (result.tables.conflicts) |x| {
                for (x.party) |s| w.put(s);
            },
            .rival => for (result.tables.conflicts) |x| {
                for (x.rest) |a| w.put(cell(a));
            },
            .frayed => for (result.tables.frayed) |x| {
                w.put(x.state);
                w.put(x.terminal);
                w.put(@intFromEnum(switch (x.harm) {
                    .read_dropped => leaf.Harm.read_dropped,
                    .fold_dropped => leaf.Harm.fold_dropped,
                }));
            },
        }
    }
};

fn shapeOf(s: g.Shape) leaf.ShapeKind {
    return switch (s) {
        .named => .named,
        .anonymous => .anonymous,
        .hidden => .hidden,
        .invented => .invented,
    };
}

fn completeCount(st: lr0.State) usize {
    return st.complete.len;
}

/// A cursor over one section. Little-endian on every host, which is the only
/// reason a folio written on one machine reads on another.
const Writer = struct {
    out: []u8,
    /// Set for a narrow section, where every record is one id at half width.
    narrow: bool = false,
    at: usize = 0,

    fn put(w: *Writer, v: u32) void {
        std.mem.writeInt(u32, w.out[w.at..][0..4], v, .little);
        w.at += 4;
    }

    /// A bare id, at whatever width the directory promised for this section.
    fn id(w: *Writer, v: u32) void {
        if (!w.narrow) return w.put(v);
        std.mem.writeInt(u16, w.out[w.at..][0..2], @intCast(v), .little);
        w.at += 2;
    }

    fn putSigned(w: *Writer, v: i32) void {
        std.mem.writeInt(i32, w.out[w.at..][0..4], v, .little);
        w.at += 4;
    }

    fn span(w: *Writer, s: leaf.Span) void {
        w.put(s.off);
        w.put(s.len);
    }

    /// A prefix-sum span table: `n + 1` entries whose last is the total, so a
    /// state's slice is two loads and never a bounds question.
    fn spans(w: *Writer, states: []const lr0.State, comptime lenOf: fn (lr0.State) usize) void {
        var total: u32 = 0;
        w.put(total);
        for (states) |st| {
            total += @intCast(lenOf(st));
            w.put(total);
        }
    }
};

fn add(base: u32, n: usize) Error!u32 {
    return fits(@as(u64, base) + n);
}

fn fits(n: u64) Error!u32 {
    if (n > std.math.maxInt(u32)) return Error.GrammarTooLarge;
    return @intCast(n);
}

fn fitsUsize(n: u64) Error!usize {
    if (n > std.math.maxInt(usize)) return Error.GrammarTooLarge;
    return @intCast(n);
}
