//! A customary as bytes: the pressed program, and the reader that proves one.
//!
//! The claim this whole area rests on is that a scanner can be **data**, and
//! data means a layout somebody can point at. So a book is a header, eight
//! arrays of fixed-width rows, and one text arena - the same shape the folio
//! itself has, for the same reason: it is read where it lies, and a reader
//! either proves the whole layout or refuses the file.
//!
//! Every index in a row is checked against the array it points into *before* the
//! interpreter can reach it (`read`), which is what lets `engine.zig` be written
//! with no bounds checks and no error set: a step over a proven book cannot
//! address anything that is not there. `scribe.zig` is the only writer.
//!
//! Fail closed, never fail quiet. A misspelled probe name would silently never
//! match, which is worse than a refusal, so the encoder resolves every name to
//! an index and this reader refuses an index it cannot honour. An unknown opcode
//! is the same judgement: a book written by a newer press is refused whole,
//! rather than run with the rules this binary happens to recognize.

const std = @import("std");
const organs = @import("organs.zig");

pub const magic: u32 = 0x54_53_55_43; // "CUST", little-endian
pub const version: u32 = 2;

/// A sentinel for "this row does not use that slot". Not zero: zero is a
/// perfectly good register, probe, kind and value index.
pub const none: u32 = std.math.maxInt(u32);

/// A slice of the text arena.
pub const Span = extern struct {
    off: u32,
    len: u32,

    pub const empty: Span = .{ .off = 0, .len = 0 };
};

/// The phases a sweep walks, in order.
///
/// The order is the eight scanners' own: what is inside an open region first
/// (its body owns those bytes until it says otherwise), then the line's layout,
/// then a region opening, then everything a line ending decides. `matched` is
/// never entered by the sweep - a rule in it is reached only through the `pass`
/// test, which selects one by the kind of the frame under its cursor.
pub const Phase = enum(u32) {
    inside,
    matched,
    layout,
    commanded,
    opening,
    enclosing,
    bounded,
    ordered,

    /// Phases the sweep never enters on its own.
    pub fn called(p: Phase) bool {
        return p == .matched;
    }
};

pub const Cmp = enum(u32) {
    none,
    eq,
    ne,
    lt,
    le,
    gt,
    ge,
    /// A kind test's `in`: the row's `kinds` bitset holds the admissible ones.
    in,

    pub fn holds(c: Cmp, a: i64, b: i64) bool {
        return switch (c) {
            .eq => a == b,
            .ne => a != b,
            .lt => a < b,
            .le => a <= b,
            .gt => a > b,
            .ge => a >= b,
            .none, .in => true,
        };
    }
};

/// The closed set of tests. A book naming anything else is refused at `read`.
pub const Test = enum(u32) {
    /// An anchored pattern at where the guard has read to. Binds `width`.
    probe,
    /// The same pattern, refused. Binds nothing.
    no_probe,
    /// A balanced run between two patterns, the opener counted as depth one.
    /// The one guard no regex can spell, and the one the nested block comments
    /// of swift, kotlin and scala all need.
    nest,
    /// Blanks, up to a column target an organ entry may name. A guard rather
    /// than an action because what follows it is a test on how far it got.
    soak,
    /// One bounded pass of the `matched` rules over the open frames.
    pass,
    bol,
    not_bol,
    blank,
    not_blank,
    lull,
    not_lull,
    eof,
    not_eof,
    /// Whether no extra has been stepped over since the last token ended.
    fresh,
    /// The permission set: is this terminal one the parse state will accept?
    /// The one input rung 1 could not model and the engine has for free.
    wanted,
    not_wanted,
    named,
    not_named,
    /// This terminal stands alone among the state's shiftable admissions, so
    /// nothing competes with it at all.
    sole,
    lead,
    frames_depth,
    marks_depth,
    frames_top_kind,
    marks_top_kind,
    frames_at_kind,
    frames_at_width,
    frames_top_width,
    marks_top_count,
    /// The bytes at the offset against the innermost mark's remembered tag,
    /// exactly or case-folded. A heredoc's close, and nothing else.
    marks_top_tag,
    frames_has,
    marks_has,
    reg,
    /// Whether any rule of a named group would hold here, guard only, on a
    /// frozen copy of the organs.
    fires,
    no_fires,
};

/// The closed set of actions.
pub const Action = enum(u32) {
    /// Answer with a terminal. `class` renames the answer by running a second
    /// pressed table over the text just matched - the one action a pattern roll
    /// structurally cannot have.
    emit,
    /// Bytes stepped over without being claimed: tree-sitter's
    /// `advance(lexer, true)`.
    skip,
    push,
    pop,
    set,
    /// Withdraw this rule and let the one behind it answer.
    refuse,
    /// Withdraw the whole ask. The difference between "not me" and "nothing
    /// here", and a customary that could only say the first would let the rule
    /// behind it answer at an offset the rule in front had just accounted for.
    abstain,
};

pub const Stack = enum(u32) { frames, marks };

/// Where the bytes a `push marks` remembers as its tag come from.
pub const Slice = enum(u32) { none, match, group, literal };

/// Which number a `pass` reported.
pub const Pass = enum(u32) { ran, cursor, budget, eaten, at, more };

/// One guarded arm of a scanner, read off the C and written down.
///
/// A rule with no `emit` among its actions is **effect-only**: its guard held,
/// its organ writes stand, and the ask carries on to the rule behind it. The C
/// has these too - every path that updates a delimiter stack or a register and
/// then returns false - and they are how a customary remembers something about
/// bytes it does not claim.
pub const RuleRow = extern struct {
    name: Span,
    phase: u32,
    /// For a `matched` rule, the organ kind it answers for. -1 everywhere else,
    /// and the two are checked against each other at `read`.
    kind: i32,
    /// The organ kind this rule ends. Only meaningful for an opaque kind, where
    /// it is the one thing still askable inside the region.
    closes: i32,
    /// Groups this rule answers for, as a bitset, so another rule's `fires`
    /// test can score it without committing.
    groups: u32,
    test_at: u32,
    test_len: u32,
    act_at: u32,
    act_len: u32,
};

pub const TestRow = extern struct {
    op: u32,
    cmp: u32,
    /// Modifier bits, read per op: `soak` (`to`/`one`/`from`), `pass`
    /// (`after`/`until`), `fires` (`after`/`from`), `marks.top.tag` (folded).
    flags: u32,
    probe_a: u32,
    probe_b: u32,
    /// Admissible organ kinds, for a kind or `has` test.
    kinds: u32,
    group: u32,
    reg: u32,
    v0: u32,
    v1: u32,
    v2: u32,
    /// The terminal a permission test asks about.
    name: Span,

    pub const to: u32 = 1 << 0;
    pub const one: u32 = 1 << 1;
    pub const from: u32 = 1 << 2;
    pub const after: u32 = 1 << 3;
    pub const until: u32 = 1 << 4;
    pub const folded: u32 = 1 << 5;
    pub const known: u32 = to | one | from | after | until | folded;
};

pub const ActRow = extern struct {
    op: u32,
    stack: u32,
    /// The organ kind pushed, or the one `pop until` stops at. -1 for neither.
    kind: i32,
    /// The classifier table that may rename an `emit`. -1 for none.
    class: i32,
    reg: u32,
    slice: u32,
    slice_group: u32,
    v0: u32,
    v1: u32,
    /// The terminal emitted, or a literal tag.
    name: Span,
};

/// One node of the value expression pool. `a` and `b` are child indices for the
/// four arithmetic tags and literals for the rest.
pub const ValRow = extern struct {
    tag: u32,
    a: i32,
    b: i32,
};

pub const Val = enum(u32) {
    constant,
    /// What a soak in this same guard arrived at, else the line's own.
    lead,
    column,
    /// How wide this guard's probe matched.
    width,
    /// Which frame a `pass` has its cursor on.
    cursor,
    /// How wide one capture group of the guard's match was. The count a scanner
    /// keeps is nearly always the length of a run it just read.
    span,
    /// One of the six numbers a `pass` reported; `a` says which.
    pass,
    reg,
    frames_top_width,
    frames_depth,
    marks_depth,
    marks_top_count,
    frames_at_width,
    add,
    sub,
    max,
    min,
};

pub const ProbeRow = extern struct {
    pattern: Span,
};

pub const ClassRow = extern struct {
    at: u32,
    len: u32,
};

pub const ArmRow = extern struct {
    pattern: Span,
    name: Span,
};

/// The fixed part. Counts first because the whole layout is derived from them.
pub const Head = extern struct {
    magic: u32,
    version: u32,
    flags: u32,
    /// How wide a tab is for this grammar. markdown says four (GFM's tab stop);
    /// python and haskell say eight. A per-grammar fact, so it is here and not a
    /// constant in the engine.
    tab: u32,
    /// The register this grammar carries consumed-but-unspent indentation in,
    /// or -1. Where it is set, `lead` in the `layout` phase means that register
    /// plus the whitespace at the offset, which is `s->indentation` exactly.
    budget: i32,
    /// Organ kinds whose inside is opaque, as a bitset: while one is the
    /// innermost frame, the only layout answer available is the rule that ends
    /// it. A fenced code block, a heredoc and a raw string all have this shape.
    opaque_kinds: u32,
    /// The probe matching what lies BETWEEN two tokens, or -1 when the caller's
    /// extras already move over it.
    ///
    /// A grammar whose every terminal is external declares no whitespace extra,
    /// because in its C the scanner soaks its own: tree-sitter-yaml opens every
    /// `scan` with a loop over spaces, tabs and line breaks before it looks at
    /// anything. That loop is one fact about the grammar, not a clause in each
    /// of its arms, so it is declared once here and the sweep advances over it
    /// before any rule is scored. The bytes it covers are the hit's `skip` -
    /// stepped over, never claimed - so a token's extent is still only the
    /// token. Facts are measured at the offset the skip arrives at, which is
    /// what makes `lead` and `column` comparable: both then describe the same
    /// line.
    trivia: i32,
    rules: u32,
    tests: u32,
    acts: u32,
    vals: u32,
    probes: u32,
    classes: u32,
    arms: u32,
    text: u32,

    /// Set when the grammar's caller asks at every offset rather than only at a
    /// line start or a line ending. A property of the caller, recorded so the
    /// bench and the offline simulator agree with the engine about it.
    pub const asks_token: u32 = 1 << 0;
    pub const known_flags: u32 = asks_token;
};

/// Every way a book can be refused.
pub const Error = error{
    CustomaryTooSmall,
    CustomaryBadMagic,
    CustomaryBadVersion,
    CustomaryBadLength,
    CustomaryMisaligned,
    /// An opcode, phase, comparison or flag bit this binary does not define.
    CustomaryBadTag,
    /// An index past the end of the array it points into.
    CustomaryBadIndex,
    /// A text span running past the arena.
    CustomaryBadText,
    /// A `matched` rule without a kind, or a kind on a rule in another phase.
    CustomaryBadRule,
    /// A value expression that is not a tree: a child index at or past its own
    /// parent, so evaluation could not terminate.
    CustomaryBadValue,
    /// An organ capacity the engine does not have room for.
    CustomaryTooWide,
};

/// A book proven against its own bytes. Every slice points into the buffer the
/// caller handed `read`, which therefore has to outlive it.
pub const Book = struct {
    head: Head,
    rules: []const RuleRow,
    tests: []const TestRow,
    acts: []const ActRow,
    vals: []const ValRow,
    probes: []const ProbeRow,
    classes: []const ClassRow,
    arms: []const ArmRow,
    text: []const u8,

    pub fn tab(b: *const Book) u32 {
        return b.head.tab;
    }

    /// The register the budget lives in, or null for a grammar with none.
    pub fn budget(b: *const Book) ?u32 {
        return if (b.head.budget < 0) null else @intCast(b.head.budget);
    }

    pub fn asksEveryOffset(b: *const Book) bool {
        return b.head.flags & Head.asks_token != 0;
    }

    pub fn opaqueKind(b: *const Book, kind: u8) bool {
        return kind < 32 and b.head.opaque_kinds & (@as(u32, 1) << @intCast(kind)) != 0;
    }

    pub fn str(b: *const Book, s: Span) []const u8 {
        return b.text[s.off..][0..s.len];
    }

    pub fn ruleName(b: *const Book, i: usize) []const u8 {
        return b.str(b.rules[i].name);
    }

    pub fn whenOf(b: *const Book, r: *const RuleRow) []const TestRow {
        return b.tests[r.test_at..][0..r.test_len];
    }

    pub fn thenOf(b: *const Book, r: *const RuleRow) []const ActRow {
        return b.acts[r.act_at..][0..r.act_len];
    }

    pub fn armsOf(b: *const Book, class: u32) []const ArmRow {
        const c = b.classes[class];
        return b.arms[c.at..][0..c.len];
    }
};

fn rowsOf(comptime T: type, bytes: []const u8, at: *usize, count: u32) Error![]const T {
    const want = @as(usize, count) * @sizeOf(T);
    if (bytes.len - at.* < want) return Error.CustomaryBadLength;
    const raw = bytes[at.*..][0..want];
    at.* += want;
    return std.mem.bytesAsSlice(T, @as([]align(@alignOf(T)) const u8, @alignCast(raw)));
}

/// Prove a book, or name the field that stopped it.
///
/// Everything the interpreter will address is checked here exactly once, which
/// is the trade this layout is for: one pass at scanner-compile time buys a hot
/// loop with no index checks at all.
pub fn read(bytes: []const u8) Error!Book {
    if (bytes.len < @sizeOf(Head)) return Error.CustomaryTooSmall;
    if (@intFromPtr(bytes.ptr) % @alignOf(Head) != 0) return Error.CustomaryMisaligned;
    const head: Head = @as(*const Head, @ptrCast(@alignCast(bytes.ptr))).*;
    if (head.magic != magic) return Error.CustomaryBadMagic;
    if (head.version != version) return Error.CustomaryBadVersion;
    if (head.flags & ~Head.known_flags != 0) return Error.CustomaryBadTag;
    if (head.tab == 0 or head.tab > 64) return Error.CustomaryBadTag;

    var at: usize = @sizeOf(Head);
    var b: Book = .{
        .head = head,
        .rules = try rowsOf(RuleRow, bytes, &at, head.rules),
        .tests = try rowsOf(TestRow, bytes, &at, head.tests),
        .acts = try rowsOf(ActRow, bytes, &at, head.acts),
        .vals = try rowsOf(ValRow, bytes, &at, head.vals),
        .probes = try rowsOf(ProbeRow, bytes, &at, head.probes),
        .classes = try rowsOf(ClassRow, bytes, &at, head.classes),
        .arms = try rowsOf(ArmRow, bytes, &at, head.arms),
        .text = undefined,
    };
    if (bytes.len - at < head.text) return Error.CustomaryBadLength;
    b.text = bytes[at..][0..head.text];
    at += head.text;
    // Trailing slack is refused rather than ignored: a section holding more than
    // the header accounts for is a file somebody wrote more into than this
    // binary can read, which is the one thing the folio's own reader refuses too.
    // Up to seven bytes of it is the writer's alignment padding, so the bound is
    // the folio's section alignment and not zero.
    if (bytes.len - at >= 8) return Error.CustomaryBadLength;
    if (head.budget >= @as(i32, organs.regs_max)) return Error.CustomaryBadIndex;
    if (head.trivia >= 0 and @as(u32, @intCast(head.trivia)) >= head.probes) {
        return Error.CustomaryBadIndex;
    }

    for (b.vals, 0..) |v, i| try proveValue(v, i);
    for (b.probes) |p| try proveText(&b, p.pattern);
    for (b.classes) |c| {
        if (@as(usize, c.at) + c.len > b.arms.len) return Error.CustomaryBadIndex;
    }
    for (b.arms) |a| {
        try proveText(&b, a.pattern);
        try proveText(&b, a.name);
    }
    for (b.rules) |*r| try proveRule(&b, r);
    return b;
}

fn proveText(b: *const Book, s: Span) Error!void {
    if (@as(usize, s.off) + s.len > b.text.len) return Error.CustomaryBadText;
}

/// `i` is this value's own index, which is what the child bound below is against.
/// No `Book`, unlike its siblings: a value names no text and no other section, so
/// it is the one row that can be judged entirely on itself.
fn proveValue(v: ValRow, i: usize) Error!void {
    if (v.tag > @intFromEnum(Val.min)) return Error.CustomaryBadTag;
    // A child index must be strictly below its parent's, which makes the pool a
    // topologically sorted DAG and evaluation a walk that cannot revisit. The
    // encoder emits children first, so this is free to hold and it is the whole
    // termination argument for `engine.value`.
    const kid = struct {
        fn ok(at: i32, ceiling: usize) bool {
            return at >= 0 and @as(usize, @intCast(at)) < ceiling;
        }
    };
    switch (@as(Val, @enumFromInt(v.tag))) {
        .add, .sub, .max, .min => {
            if (!kid.ok(v.a, i) or !kid.ok(v.b, i)) return Error.CustomaryBadValue;
        },
        .frames_at_width => if (!kid.ok(v.a, i)) return Error.CustomaryBadValue,
        .reg => if (v.a < 0 or v.a >= organs.regs_max) return Error.CustomaryBadIndex,
        .pass => if (v.a < 0 or v.a > @intFromEnum(Pass.more)) return Error.CustomaryBadTag,
        .span => if (v.a < 0 or v.a > 9) return Error.CustomaryBadIndex,
        else => {},
    }
}

fn proveRule(b: *const Book, r: *const RuleRow) Error!void {
    try proveText(b, r.name);
    if (r.phase > @intFromEnum(Phase.ordered)) return Error.CustomaryBadTag;
    const phase: Phase = @enumFromInt(r.phase);
    // A `matched` rule is selected by the kind of the frame under a pass's
    // cursor, so it needs one; a rule in any other phase is reached by the sweep
    // and a kind on it would never be consulted. Refusing both directions is
    // what makes the field mean something.
    if ((phase == .matched) != (r.kind >= 0)) return Error.CustomaryBadRule;
    if (@as(usize, r.test_at) + r.test_len > b.tests.len) return Error.CustomaryBadIndex;
    if (@as(usize, r.act_at) + r.act_len > b.acts.len) return Error.CustomaryBadIndex;
    for (b.whenOf(r)) |t| try proveTest(b, t);
    for (b.thenOf(r)) |a| try proveAct(b, a);
}

fn proveTest(b: *const Book, t: TestRow) Error!void {
    if (t.op > @intFromEnum(Test.no_fires)) return Error.CustomaryBadTag;
    if (t.cmp > @intFromEnum(Cmp.in)) return Error.CustomaryBadTag;
    if (t.flags & ~TestRow.known != 0) return Error.CustomaryBadTag;
    try proveText(b, t.name);
    if (t.reg != none and t.reg >= organs.regs_max) return Error.CustomaryBadIndex;
    for ([_]u32{ t.probe_a, t.probe_b }) |p| {
        if (p != none and p >= b.probes.len) return Error.CustomaryBadIndex;
    }
    for ([_]u32{ t.v0, t.v1, t.v2 }) |v| {
        if (v != none and v >= b.vals.len) return Error.CustomaryBadIndex;
    }
    if (t.group != none and t.group >= 32) return Error.CustomaryBadIndex;
    switch (@as(Test, @enumFromInt(t.op))) {
        .probe, .no_probe => if (t.probe_a == none) return Error.CustomaryBadIndex,
        .nest => if (t.probe_a == none or t.probe_b == none) return Error.CustomaryBadIndex,
        .fires, .no_fires => if (t.group == none) return Error.CustomaryBadIndex,
        .reg => if (t.reg == none or t.v0 == none) return Error.CustomaryBadIndex,
        .lead, .frames_depth, .marks_depth, .frames_top_width, .marks_top_count => {
            if (t.v0 == none or t.cmp == @intFromEnum(Cmp.none)) return Error.CustomaryBadIndex;
        },
        .frames_at_width => if (t.v0 == none or t.v1 == none) return Error.CustomaryBadIndex,
        .frames_at_kind => if (t.v0 == none) return Error.CustomaryBadIndex,
        .wanted, .not_wanted, .named, .not_named, .sole => {
            if (t.name.len == 0) return Error.CustomaryBadText;
        },
        else => {},
    }
}

fn proveAct(b: *const Book, a: ActRow) Error!void {
    if (a.op > @intFromEnum(Action.abstain)) return Error.CustomaryBadTag;
    if (a.stack > @intFromEnum(Stack.marks)) return Error.CustomaryBadTag;
    if (a.slice > @intFromEnum(Slice.literal)) return Error.CustomaryBadTag;
    try proveText(b, a.name);
    if (a.reg != none and a.reg >= organs.regs_max) return Error.CustomaryBadIndex;
    if (a.class >= 0 and @as(usize, @intCast(a.class)) >= b.classes.len) return Error.CustomaryBadIndex;
    if (a.kind > @as(i32, std.math.maxInt(u8))) return Error.CustomaryBadIndex;
    for ([_]u32{ a.v0, a.v1 }) |v| {
        if (v != none and v >= b.vals.len) return Error.CustomaryBadIndex;
    }
    switch (@as(Action, @enumFromInt(a.op))) {
        .emit => if (a.name.len == 0) return Error.CustomaryBadText,
        .set => if (a.reg == none or a.v0 == none) return Error.CustomaryBadIndex,
        .skip => if (a.v0 == none) return Error.CustomaryBadIndex,
        .push => if (a.kind < 0) return Error.CustomaryBadIndex,
        else => {},
    }
}

comptime {
    // Every row is a whole number of words, so the arrays tile the section and a
    // reader can view them where they lie. Same property `folio/leaf.zig` holds
    // its records to, and it is checked here for the same reason: a short field
    // added after an odd number of `u32`s opens a hole the writer does not skip.
    for ([_]type{ Head, RuleRow, TestRow, ActRow, ValRow, ProbeRow, ClassRow, ArmRow }) |T| {
        if (!std.meta.hasUniqueRepresentation(T)) @compileError(
            @typeName(T) ++ " has bytes no field owns, so a section of them" ++
                " cannot be read where it lies. Widen the short field.",
        );
        if (@alignOf(T) != 4) @compileError(@typeName(T) ++ " does not align to a word");
    }
}

test "an empty book is refused rather than read as a program with no rules" {
    try std.testing.expectError(Error.CustomaryTooSmall, read(&.{}));
}

test "a bad magic is named" {
    var buf: [@sizeOf(Head)]u8 align(@alignOf(Head)) = @splat(0);
    try std.testing.expectError(Error.CustomaryBadMagic, read(&buf));
}
