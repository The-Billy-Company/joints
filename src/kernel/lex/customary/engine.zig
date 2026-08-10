//! One interpreter for every customary, which is the whole claim in one type:
//! the per-language part is the book, never the code that runs it.
//!
//! `Engine` is what a grammar's pressed program becomes once it is bound to that
//! grammar's numbering - probes compiled, terminal names resolved to symbols,
//! every index in the book already proven by `book.read`. It is per grammar, so
//! it lives on `Scanner` beside the slate and is asked at the seam
//! `outside.step` occupies.
//!
//! `Ask` is one question at one offset: the engine, the bytes, the permission
//! set, and how deep a nested guard has recursed. It carries no state of its own
//! - the organs are the caller's and travel by pointer - which is what lets a
//! scored guard run over a frozen copy without the engine knowing it is a copy.
//!
//! The phase order is the eight scanners' own, and it is not per-language: what
//! is inside an open region first (its body owns those bytes until it says
//! otherwise), then the line's layout, then a region opening, then everything a
//! line ending decides. It is the same order `outside.offer` asks the hands in,
//! for the same reason.
//!
//! Four things are the engine's structure rather than a rule's input, and each
//! is here because a book that had to spell it would be spelling mechanism:
//! where a phase starts reading (`stand`), scoring a guard without committing
//! (`attempt`), one bounded pass over an organ (`pass`), and the permission set
//! (`admits`) - which is the one input the offline simulator could not model and
//! this side has for free.

const std = @import("std");
const irregex = @import("irregex");
const book = @import("book.zig");
const organs = @import("organs.zig");
const guard = @import("guard.zig");
const deed = @import("deed.zig");

const Caps = irregex.regex.Caps;

/// What a customary answered with, shaped like `outside.Hit` because that is
/// what the seam returns. `skip` is bytes stepped over without being claimed -
/// tree-sitter's `advance(lexer, true)`.
pub const Hit = struct { symbol: organs.Symbol, len: u32, skip: u32 = 0 };

/// How deep a guard that runs other rules may nest before the engine calls it
/// off. `fires` scores a named group and `pass` sweeps the open frames, and each
/// can appear in a guard the other reaches - so the recursion is bounded here
/// rather than trusted to every book. One level is what the eight need (an
/// interrupt scan whose own rules probe); past it such a test is false, which is
/// fail-closed: a customary can lose an answer this way and cannot gain one.
pub const reach_max = 2;

pub const Error = book.Error || error{
    OutOfMemory,
    /// A probe irregex refused, or one with more capture groups than a slot
    /// vector holds.
    CustomaryBadPattern,
    /// A terminal the book names and the grammar does not declare. Refused
    /// rather than dropped: a rule that can never fire is a scanner arm nobody
    /// notices is missing, which is the failure this whole area exists to avoid.
    CustomaryUnknownTerminal,
};

/// A bound customary: the program, its compiled probes, and its symbols.
///
/// `names` is a duck-typed resolver rather than a `*press.Grammar` for the same
/// reason `outside.provision` takes one: name resolution belongs to whoever owns
/// the numbering, and this directory does not. `external` is asked first for a
/// terminal a customary *answers*, because a named external is what a scanner
/// owes; `terminal` is the fallback, and the fallback is not a courtesy - html
/// declares `/>` as an anonymous string, so the press keeps the ordinary token
/// it can lex and there is no external to find, yet only the tag stack knows
/// those two bytes end an element. `terminal` alone answers a test, which may
/// name any terminal at all: kotlin's semicolon insertion reads whether `else`
/// is admitted, and `else` is an ordinary keyword.
pub const Engine = struct {
    gpa: std.mem.Allocator,
    /// The section, owned and aligned so the book's views into it are legal.
    /// Copied rather than borrowed because a folio may be closed under a live
    /// scanner and the book is read on every ask.
    held: []align(section_align) u8,
    program: book.Book,
    probes: []Caps,
    /// One matcher per classifier arm, in `book.arms` order.
    arms: []Caps,
    /// Act index -> the terminal it emits, or `absent` for an act that emits
    /// nothing.
    emits: []organs.Symbol,
    /// Test index -> the terminal it asks the permission set about, or `absent`.
    asks: []organs.Symbol,
    /// Arm index -> the terminal that arm renames an answer to.
    renames: []organs.Symbol,
    /// Every terminal a rule could possibly answer with, flattened, and the
    /// offsets one rule's run sits at (`reach_at[i]..reach_at[i+1]`). An empty
    /// run means the rule emits nothing at all.
    ///
    /// This is the permission check a hand-written scanner does *first* -
    /// `if (valid_symbols[X])` is the opening line of every `scanner.c` in the
    /// held-out set - and doing it last is what made a customary cost 3.5x to 7x
    /// tree-sitter on the four grammars that reach a throughput row. `admits`
    /// asked the same question exactly one PCRE2 match too late.
    reach: []organs.Symbol,
    reach_at: []u32,
    /// Rule indices grouped by phase, in each phase's own rule order, and where
    /// one phase's run starts (`order_at[p]..order_at[p+1]`).
    ///
    /// The sweep used to walk every rule once per phase and skip the ones
    /// belonging to another, so html asked 8 x 33 questions an offset to reach
    /// 33 rules, and paid `stand` for phases holding no rule at all. Order
    /// inside a phase is preserved exactly, because it is load-bearing: a rule
    /// behind another must not answer at an offset the one in front accounted
    /// for.
    order: []u16,
    order_at: [phases_max + 1]u32,

    const phases_max = @typeInfo(book.Phase).@"enum".fields.len;

    pub const absent: organs.Symbol = std.math.maxInt(organs.Symbol);
    pub const section_align = @alignOf(book.Head);

    /// Read a section, compile its probes, and resolve its names. Everything
    /// that can fail about a customary fails here, once, so a step cannot.
    pub fn bind(gpa: std.mem.Allocator, section: []const u8, names: anytype) Error!Engine {
        const held = try gpa.alignedAlloc(u8, .fromByteUnits(section_align), section.len);
        errdefer gpa.free(held);
        @memcpy(held, section);
        const program = try book.read(held);

        const probes = try gpa.alloc(Caps, program.probes.len);
        errdefer gpa.free(probes);
        var lit: usize = 0;
        errdefer for (probes[0..lit]) |*p| p.deinit();
        for (program.probes, 0..) |p, i| {
            probes[i] = try compileProbe(gpa, program.str(p.pattern), false);
            lit = i + 1;
        }

        const arms = try gpa.alloc(Caps, program.arms.len);
        errdefer gpa.free(arms);
        var armed: usize = 0;
        errdefer for (arms[0..armed]) |*m| m.deinit();
        for (program.arms, 0..) |m, i| {
            arms[i] = try compileProbe(gpa, program.str(m.pattern), true);
            armed = i + 1;
        }

        const emits = try gpa.alloc(organs.Symbol, program.acts.len);
        errdefer gpa.free(emits);
        @memset(emits, absent);
        for (program.acts, 0..) |a, i| {
            if (@as(book.Action, @enumFromInt(a.op)) != .emit) continue;
            const name = program.str(a.name);
            emits[i] = names.external(name) orelse names.terminal(name) orelse
                return Error.CustomaryUnknownTerminal;
        }

        const asks = try gpa.alloc(organs.Symbol, program.tests.len);
        errdefer gpa.free(asks);
        @memset(asks, absent);
        for (program.tests, 0..) |t, i| {
            switch (@as(book.Test, @enumFromInt(t.op))) {
                .wanted, .not_wanted, .named, .not_named, .sole => {},
                else => continue,
            }
            asks[i] = names.terminal(program.str(t.name)) orelse
                return Error.CustomaryUnknownTerminal;
        }

        const renames = try gpa.alloc(organs.Symbol, program.arms.len);
        errdefer gpa.free(renames);
        for (program.arms, 0..) |m, i| {
            const name = program.str(m.name);
            renames[i] = names.external(name) orelse names.terminal(name) orelse
                return Error.CustomaryUnknownTerminal;
        }

        // The union over each rule's emits, taking a classified emit's whole arm
        // table plus the name it falls back to when no arm matches - `classify`
        // ends in `emits[at_act]`, so the fallback is reachable and belongs in
        // the set. An over-approximation is the right error here: the exact test
        // still runs in `admits`, so a symbol too many costs one wasted match
        // and a symbol too few would lose an answer.
        const reach_at = try gpa.alloc(u32, program.rules.len + 1);
        errdefer gpa.free(reach_at);
        var reach: std.ArrayList(organs.Symbol) = .empty;
        errdefer reach.deinit(gpa);
        for (program.rules, 0..) |*r, ri| {
            reach_at[ri] = @intCast(reach.items.len);
            for (program.thenOf(r), r.act_at..) |act, i| {
                if (@as(book.Action, @enumFromInt(act.op)) != .emit) continue;
                try reach.append(gpa, emits[i]);
                if (act.class < 0) continue;
                const c = program.classes[@intCast(act.class)];
                for (c.at..c.at + c.len) |arm| try reach.append(gpa, renames[arm]);
            }
        }
        reach_at[program.rules.len] = @intCast(reach.items.len);

        if (program.rules.len > std.math.maxInt(u16)) return Error.CustomaryBadIndex;
        const order = try gpa.alloc(u16, program.rules.len);
        errdefer gpa.free(order);
        var order_at: [phases_max + 1]u32 = @splat(0);
        var wrote: u32 = 0;
        for (0..phases_max) |p| {
            order_at[p] = wrote;
            for (program.rules, 0..) |*r, ri| {
                if (r.phase != p) continue;
                order[wrote] = @intCast(ri);
                wrote += 1;
            }
        }
        order_at[phases_max] = wrote;
        // A rule naming a phase outside the enum would be dropped silently here,
        // and a dropped rule is an answer that never comes.
        if (wrote != program.rules.len) return Error.CustomaryBadTag;

        return .{
            .gpa = gpa,
            .held = held,
            .program = program,
            .probes = probes,
            .arms = arms,
            .emits = emits,
            .asks = asks,
            .renames = renames,
            .reach = try reach.toOwnedSlice(gpa),
            .reach_at = reach_at,
            .order = order,
            .order_at = order_at,
        };
    }

    /// Every probe is a PCRE2 program, and deliberately: the eight's guards are
    /// written with lookahead (`#{1,6}(?=[ \t]|$)` - an atx marker is only a
    /// marker if a space follows it), inline case folding (`(?i:<pre)`), and
    /// capture groups a `span` value reads, and the linear engine expresses none
    /// of the three. Unicode semantics are off: a scanner reads bytes, and the
    /// offline simulator this is held to reads its corpus as one character per
    /// byte for exactly that reason.
    ///
    /// `whole` wraps a classifier arm so it must match the text end to end -
    /// python's `fullmatch`, which is what a classifier MEANS - rather than
    /// asking every book to remember an anchor.
    fn compileProbe(gpa: std.mem.Allocator, pattern: []const u8, whole: bool) Error!Caps {
        const src = if (!whole) pattern else std.fmt.allocPrint(gpa, "(?:{s})$", .{pattern}) catch
            return Error.OutOfMemory;
        defer if (whole) gpa.free(src);
        var c = Caps.compile(gpa, src, .{ .pcre = true, .unicode = false }) catch
            return Error.CustomaryBadPattern;
        if (c.nslots() > guard.slots_max) {
            c.deinit();
            return Error.CustomaryBadPattern;
        }
        return c;
    }

    pub fn deinit(e: *Engine) void {
        for (e.probes) |*p| p.deinit();
        e.gpa.free(e.probes);
        for (e.arms) |*a| a.deinit();
        e.gpa.free(e.arms);
        e.gpa.free(e.emits);
        e.gpa.free(e.asks);
        e.gpa.free(e.renames);
        e.gpa.free(e.reach);
        e.gpa.free(e.reach_at);
        e.gpa.free(e.order);
        e.gpa.free(e.held);
        e.* = undefined;
    }

    /// How wide a tab is for this grammar.
    pub fn tab(e: *const Engine) u32 {
        return e.program.tab();
    }

    /// Whether this customary answers for a terminal.
    ///
    /// What `outside.claimed` is for a hand, and it is asked for the same reason:
    /// a terminal a customary answers must not also be seated as a pattern. The
    /// slate is asked at every offset and knows nothing of the organs, so a seat
    /// for markdown's `_block_close` would answer it in the middle of a
    /// paragraph. It is also the line that tells "answered by customary" from
    /// "blind" - see `Scanner.compile`.
    pub fn claims(e: *const Engine, sym: organs.Symbol) bool {
        if (sym == absent) return false;
        return std.mem.indexOfScalar(organs.Symbol, e.emits, sym) != null or
            std.mem.indexOfScalar(organs.Symbol, e.renames, sym) != null;
    }

    /// How many rules the book carries, for a census that wants to say so.
    pub fn rules(e: *const Engine) usize {
        return e.program.rules.len;
    }

    /// The customary's answer at one offset, or null if it has none.
    ///
    /// `already` is the terminals answered at this exact offset under this exact
    /// organ state, and a rule whose every emit is among them is passed over. It
    /// is the seam's own zero-width ledger read as a permission set: the parser
    /// that already took a `_blank_line_start` here will ask for something else
    /// next, and without the suppression a zero-width answer wins its offset
    /// forever and every terminal ordered behind it is unreachable.
    pub fn step(
        e: *Engine,
        o: *organs.Organs,
        bytes: []const u8,
        at: u32,
        fresh: bool,
        wanted: *const std.DynamicBitSetUnmanaged,
        named: *const std.DynamicBitSetUnmanaged,
        already: []const organs.Symbol,
    ) ?Hit {
        var a: Ask = .{
            .e = e,
            .bytes = bytes,
            .wanted = wanted,
            .named = named,
            .fresh = fresh,
            .already = already,
        };
        return a.sweep(o, at);
    }
};

/// One question at one offset. Everything mutable about the run is behind a
/// pointer the caller owns, so an `Ask` is cheap to copy for a nested guard.
pub const Ask = struct {
    e: *Engine,
    bytes: []const u8,
    wanted: *const std.DynamicBitSetUnmanaged,
    named: *const std.DynamicBitSetUnmanaged,
    fresh: bool,
    /// See `Engine.step`. Empty inside any nested ask: a scored rule and a
    /// matcher are not answering at this offset, so nothing is spent for them.
    already: []const organs.Symbol = &.{},
    /// How many guards deep this ask already is. See `reach_max`.
    reach: u8 = 0,
    /// Set while a guard is being scored: a rule reached that way may read the
    /// organs and must never write them, and `attempt` enforces it by applying
    /// nothing.
    scoring: bool = false,
    /// See `Facts.broke`. Measured once per ask, from the organs' own mark, so
    /// every rule scored at this offset reads one answer.
    broke: bool = false,

    /// Walk the phases in order and return the first answer.
    ///
    /// A book that declares `trivia` is answering for a grammar whose extras do
    /// not cover the space between tokens, so the space is stepped over here -
    /// once, before any rule is scored, exactly where its C scanner does it -
    /// and handed back as the hit's `skip`. Everything downstream then sees an
    /// offset sitting on a real byte, which is what lets a rule compare `lead`
    /// against `column` and mean one line by both.
    pub fn sweep(a: *Ask, o: *organs.Organs, at: u32) ?Hit {
        if (at > a.bytes.len) return null;
        const trivial = a.e.program.head.trivia >= 0;
        const over: u32 = if (!trivial) 0 else blk: {
            const which: u32 = @intCast(a.e.program.head.trivia);
            break :blk guard.reach(a, which, at) orelse 0;
        };
        // Measured over the whole gap the mark opens, not over `over` alone: a
        // zero-width close already ate the newline this run is still behind.
        // Clamped from both ends because a rewind can put the mark ahead of the
        // offset, and a mark that outran its own file must not index past it.
        const mark = @min(o.since, at);
        a.broke = trivial and
            std.mem.indexOfAny(u8, a.bytes[mark..@min(at + over, a.bytes.len)], "\r\n") != null;
        // A skip that runs to the end of input leaves nothing to answer at, and
        // the end itself is an offset a customary still has answers for, so the
        // sweep happens at the arrival either way.
        var hit = a.phases(o, at + over) orelse return null;
        hit.skip += over;
        // The C's `flush` after a `mark_end`, and only after one: an answer with
        // no extent never marked an end, so the gap it stands in stays open.
        if (hit.len > 0) o.since = at + hit.skip + hit.len;
        return hit;
    }

    fn phases(a: *Ask, o: *organs.Organs, at: u32) ?Hit {
        // At the end of input a customary still has answers - markdown closes its
        // open blocks there, zero-width - so `at == bytes.len` is in bounds on
        // purpose and only past it is not.
        if (at > a.bytes.len) return null;
        // Every phase but `layout` stands at the offset it was handed and reads
        // the facts of that one offset, so the seven of them were deriving one
        // answer seven times. `layout` is the exception because it soaks the
        // whitespace first and therefore stands somewhere else.
        var plain = organs.facts(a.bytes, at, a.e.tab(), 0);
        plain.broke = a.broke;
        var shut: ?i32 = null;
        var asked_shut = false;
        for (std.enums.values(book.Phase)) |phase| {
            if (phase.called()) continue;
            const lo, const hi = .{ a.e.order_at[@intFromEnum(phase)], a.e.order_at[@intFromEnum(phase) + 1] };
            if (lo == hi) continue; // no rule wears this phase: nothing to stand for
            // The layout phase measures the whitespace in front of a line, so an
            // offset the extras have already moved past has none left to read.
            if (phase == .layout and !a.fresh) continue;
            const stood: Stood = if (phase == .layout)
                a.stand(phase, o, at)
            else
                .{ .at = at, .facts = plain };
            // Only the layout phase reads it, and only a book with layout rules
            // reaches this at all.
            if (phase == .layout and !asked_shut) {
                shut = a.sealed(o);
                asked_shut = true;
            }
            for (a.e.order[lo..hi]) |ri| {
                const r = &a.e.program.rules[ri];
                // Before the guard, not after it. A rule whose every answer the
                // state would refuse cannot answer here, and `attempt` was
                // proving that by running the rule's PCRE2 probe and then
                // throwing the match away in `admits`. Skipping it changes
                // nothing observable: a guard never writes an organ, `abstain`
                // is an action and actions run only past `admits`, so the rules
                // this passes over are exactly the ones that returned null.
                if (!a.reachable(ri)) continue;
                // Inside an opaque region the only layout answer is the rule that
                // ends it: a fenced code block's interior is bytes the grammar
                // reads, not layout the scanner decides, and without this a
                // deeply indented line inside a fence reads as indented code.
                if (phase == .layout) if (shut) |kind| {
                    if (r.closes != kind) continue;
                };
                if (a.stale(r)) continue;
                var b: guard.Bound = .{};
                if (a.attempt(r, o, stood.at, stood.facts, &b)) |hit| return hit;
                // `abstain` is the difference between "not me" and "nothing
                // here". A rule behind this one must not answer at an offset the
                // rule in front of it has just accounted for.
                if (b.abstain) return null;
            }
        }
        return null;
    }

    /// Could the state take anything this rule is able to answer with?
    ///
    /// The cheap half of `admits`, hoisted in front of the guard: a bitset test
    /// per candidate name against the same `wanted` set, with no bytes read. An
    /// effect-only rule is never gated, for the reason `admits` gives - the C has
    /// these too, and they are how a customary remembers something about bytes it
    /// does not claim.
    fn reachable(a: *const Ask, ri: usize) bool {
        const lo, const hi = .{ a.e.reach_at[ri], a.e.reach_at[ri + 1] };
        if (lo == hi) return true;
        for (a.e.reach[lo..hi]) |sym| {
            if (sym != Engine.absent and a.wanted.isSet(sym)) return true;
        }
        return false;
    }

    /// Whether every terminal this rule could answer with is already answered
    /// here. A rule that emits nothing is never stale - it is an effect, and an
    /// effect is not something an offset can have had enough of.
    fn stale(a: *const Ask, r: *const book.RuleRow) bool {
        if (a.already.len == 0) return false;
        var emits = false;
        for (a.e.program.thenOf(r), r.act_at..) |act, i| {
            if (@as(book.Action, @enumFromInt(act.op)) != .emit) continue;
            emits = true;
            if (!a.spent(a.e.emits[i])) return false;
            // A classified emit is stale only if every name it could take is.
            if (act.class >= 0) {
                const c = a.e.program.classes[@intCast(act.class)];
                for (c.at..c.at + c.len) |arm| if (!a.spent(a.e.renames[arm])) return false;
            }
        }
        return emits;
    }

    fn spent(a: *const Ask, sym: organs.Symbol) bool {
        return std.mem.indexOfScalar(organs.Symbol, a.already, sym) != null;
    }

    /// The opaque kind we are inside, if the innermost frame names one.
    fn sealed(a: *const Ask, o: *const organs.Organs) ?i32 {
        const top = o.frameTop() orelse return null;
        return if (a.e.program.opaqueKind(top.kind)) @as(i32, top.kind) else null;
    }

    const Stood = struct { at: u32, facts: organs.Facts };

    /// Where a phase starts reading, and what it knows about the line there.
    ///
    /// Everywhere but `layout` that is just the offset. In `layout` the blanks are
    /// already behind us: the C soaks them into `s->indentation` once, before the
    /// switch that decides anything, so every rule in that phase sees an offset
    /// past them and a `lead` that is the carried budget plus what was just
    /// soaked. Doing it here rather than in thirty rules is the difference between
    /// engine structure and copied data.
    fn stand(a: *const Ask, phase: book.Phase, o: *const organs.Organs, at: u32) Stood {
        if (phase != .layout) {
            var f = organs.facts(a.bytes, at, a.e.tab(), 0);
            f.broke = a.broke;
            return .{ .at = at, .facts = f };
        }
        const soaked = organs.soak(a.bytes, at, a.e.tab(), a.carried(o));
        var f = organs.facts(a.bytes, soaked[0], a.e.tab(), 0);
        f.lead = soaked[1];
        f.broke = a.broke;
        return .{ .at = soaked[0], .facts = f };
    }

    /// The consumed-but-unspent indentation this grammar is holding, or zero for
    /// one with no budget register.
    pub fn carried(a: *const Ask, o: *const organs.Organs) u32 {
        return if (a.e.program.budget()) |reg| o.regs[reg] else 0;
    }

    /// Whether every test in a rule's guard holds, binding what they read into
    /// `b`. markdown's `simulate` flag is exactly this, and it is the engine's
    /// structure rather than an input a rule reads.
    pub fn guarded(
        a: *Ask,
        r: *const book.RuleRow,
        o: *organs.Organs,
        at: u32,
        f: organs.Facts,
        b: *guard.Bound,
    ) bool {
        for (a.e.program.whenOf(r), r.test_at..) |t, i| {
            if (!guard.holds(a, t, i, o, at, f, b)) return false;
        }
        return true;
    }

    /// Score a rule's guard, check the permission set, then apply.
    pub fn attempt(
        a: *Ask,
        r: *const book.RuleRow,
        o: *organs.Organs,
        at: u32,
        f: organs.Facts,
        b: *guard.Bound,
    ) ?Hit {
        if (!a.guarded(r, o, at, f, b)) return null;
        // A rule that emits a terminal no parse state admits here has not
        // answered - it has over-generated, and the envelope that explained that
        // residue offline is this one line.
        if (!a.admits(r, at, b)) return null;
        if (a.scoring) return null;
        return deed.apply(a, r, o, at, f, b);
    }

    /// Whether the state would take anything this rule can answer with.
    fn admits(a: *Ask, r: *const book.RuleRow, at: u32, b: *const guard.Bound) bool {
        var emits = false;
        for (a.e.program.thenOf(r), r.act_at..) |act, i| {
            if (@as(book.Action, @enumFromInt(act.op)) != .emit) continue;
            emits = true;
            // A classified emit is judged by the name it will actually take, so
            // the classifier runs here rather than being approximated by the
            // union of its arms - an over-approximation would let an
            // `atx_h6_marker` answer in a state that admits only `atx_h1_marker`.
            const sym = if (act.class < 0)
                a.e.emits[i]
            else
                deed.classify(a, act, i, b.eaten orelse 0, at);
            if (a.wanted.isSet(sym)) return true;
        }
        // An effect-only rule is not gated: the C has these too - every path that
        // updates a delimiter stack or a register and then returns false - and
        // they are how a customary remembers something about bytes it does not
        // claim.
        return !emits;
    }

    /// One bounded pass of the open-organ matchers, on a scratch copy.
    ///
    /// This is the C's `while (s->matched < open_blocks.size) match(...)`, and it
    /// is the one control shape the census's tests and actions could not express:
    /// not a loop over bytes but a loop over **one organ**, bounded by that
    /// organ's own depth, whose body is selected by the entry's own kind. Bounded
    /// the way `pop until` is bounded - a frame stack is 96 deep - so it adds
    /// iteration without adding unboundedness.
    ///
    /// Nothing here commits. The pass reports how far it got, what the budget
    /// became, and how many bytes it ate; the calling rule's own actions are what
    /// write those back, so a guard stays a guard. `lead` seeds the budget the
    /// matchers spend, which is what lets the same pass run as a *simulation* on
    /// the next line from a stated cursor and a stated indentation, the way the C
    /// rewinds `s->matched` around its own look-ahead loop.
    ///
    /// `until` is the exclusive ceiling on the cursor and defaults to the whole
    /// stack. A grammar that can flag "close the innermost block" bounds the pass
    /// one short with it, reserving that frame for whichever rule actually closes
    /// it - the C's `if (matched == size - 1 && CLOSE_BLOCK) break`, said as
    /// arithmetic rather than as a second loop.
    ///
    /// The six numbers it reports are `book.Pass`, in that order.
    pub fn pass(a: *Ask, o: *const organs.Organs, at: u32, start: u32, lead: ?u32, until: ?u32) [6]u32 {
        // A matcher's own guard may ask for a pass, so the recursion is capped
        // here as well as in `scored`. A pass that does not run reports having
        // matched nothing, which closes every block it was asked about - the
        // fail-closed direction, and the same one an over-deep guard takes.
        if (a.reach >= reach_max) return .{ 0, start, 0, 0, at, @intFromBool(start < o.frameDepth()) };
        var scratch = o.*;
        if (lead) |seed| if (a.e.program.budget()) |reg| {
            scratch.regs[reg] = seed;
        };
        var deeper: Ask = a.*;
        deeper.reach += 1;
        deeper.already = &.{};
        var off = at;
        var ran: u32 = 0;
        var cursor = start;
        const ceiling = if (until) |u| @min(u, scratch.frameDepth()) else scratch.frameDepth();
        while (cursor < ceiling) : (cursor += 1) {
            var f = organs.facts(a.bytes, off, a.e.tab(), 0);
            f.lead = deeper.carried(&scratch);
            const kind = (scratch.frameAt(cursor) orelse break).kind;
            const took = deeper.match(kind, &scratch, off, f, cursor) orelse break;
            off += took;
            ran += 1;
        }
        return .{
            ran,
            cursor,
            if (a.e.program.budget()) |reg| scratch.regs[reg] else 0,
            off - at,
            off,
            @intFromBool(cursor < scratch.frameDepth()),
        };
    }

    /// The first `matched` rule for one frame kind whose guard holds, applied for
    /// its effects; the bytes it read, or null if none of them fits.
    ///
    /// Several rules may answer for one kind, because the C's arms have
    /// alternatives inside them - a list item matches on its own indentation *or*
    /// on a line that just ends - and an ordered list of guarded arms is how this
    /// algebra already spells a choice.
    ///
    /// Neither the permission set nor the answer is consulted: a matcher is
    /// interior machinery whose whole result is its effect on the scratch organs
    /// and how far it read. The C's `match` returns `bool` for the same reason.
    fn match(a: *Ask, kind: u8, o: *organs.Organs, at: u32, f: organs.Facts, cursor: u32) ?u32 {
        for (a.e.program.rules) |*r| {
            if (r.phase != @intFromEnum(book.Phase.matched) or r.kind != kind) continue;
            var b: guard.Bound = .{ .cursor = cursor };
            if (!a.guarded(r, o, at, f, &b)) continue;
            _ = deed.apply(a, r, o, at, f, &b);
            return b.eaten;
        }
        return null;
    }

    /// Whether any rule in a named group would hold here, guard only.
    ///
    /// A frozen copy of the organs goes in, so nothing a scored guard reads can be
    /// changed by scoring it - which is the whole difference between this and
    /// running the rule. The recursion is bounded twice over: `scoring` stops any
    /// rule reached this way from writing, and `reach` stops a group whose rules
    /// score each other from descending forever.
    pub fn scored(a: *Ask, group: u32, o: *const organs.Organs, at: u32, lead: u32) bool {
        if (a.reach >= reach_max) return false;
        var frozen = o.*;
        var f = organs.facts(a.bytes, at, a.e.tab(), 0);
        f.lead = lead;
        var deeper: Ask = a.*;
        deeper.reach += 1;
        deeper.scoring = true;
        deeper.already = &.{};
        const bit = @as(u32, 1) << @intCast(@min(group, 31));
        for (a.e.program.rules) |*r| {
            if (r.groups & bit == 0) continue;
            var b: guard.Bound = .{};
            var all = true;
            for (a.e.program.whenOf(r), r.test_at..) |t, i| {
                // A scored rule's own scoring tests are dropped rather than
                // followed, exactly as the offline simulator drops them: the
                // question is whether this rule's *bytes* fit here, and a rule
                // asking about a third group is asking about a line the caller
                // has already decided to look at.
                switch (@as(book.Test, @enumFromInt(t.op))) {
                    .fires, .no_fires => continue,
                    else => {},
                }
                if (!guard.holds(&deeper, t, i, &frozen, at, f, &b)) {
                    all = false;
                    break;
                }
            }
            if (all) return true;
        }
        return false;
    }
};

const nowhere = struct {
    pub fn external(_: @This(), _: []const u8) ?organs.Symbol {
        return null;
    }
    pub fn terminal(_: @This(), _: []const u8) ?organs.Symbol {
        return null;
    }
}{};

test "a section that is not a book is refused before anything is compiled" {
    const buf: [@sizeOf(book.Head)]u8 = @splat(0);
    try std.testing.expectError(
        book.Error.CustomaryBadMagic,
        Engine.bind(std.testing.allocator, &buf, nowhere),
    );
}
