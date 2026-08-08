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
//! to drop. `press.Forks` turns that record into a bit per cell. On every
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
const assay = @import("irregex").assay;
const press = @import("../../press/press.zig");
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
    read: struct { at: u32, symbol: press.Symbol, from: u32, end: u32 },
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
    /// Which strand this reading's moves are being written to while a fork
    /// stands, or `sole` when none does. See `Gather.strands`.
    seg: u32 = sole,
    /// How many declared conflicts this reading took the losing side of. Zero
    /// is the deterministic LR answer, and it breaks every tie `heft` leaves.
    rank: u32 = 0,
    /// What the author's `prec.dynamic` comes to over everything this reading
    /// has folded. The one number in the grammar written *for* this comparison
    /// and nothing else — see `Reading.beats`.
    heft: i32 = 0,
    /// Identity of the `sided` speculation this reading descends from, or
    /// `sole` for a reading that is nobody's. Keyed on identity and not on
    /// offset: haskell's 128 supplies produce 255 zero-width nodes, so an
    /// offset join double-counts there even though verilog's is exact.
    /// Instrumentation only — `beats` never reads it.
    from: u32 = sole,

    /// Which of two readings the parse should keep, wherever both are standing
    /// and only one tree can be handed back.
    ///
    /// The author's declaration first. `prec.dynamic` is the *only* rank a
    /// grammar writes that the press deliberately cannot spend: a static rank
    /// deletes an action while the table is being built, and a dynamic one is
    /// left for exactly this moment, when the two derivations it orders both
    /// exist. Summed over the fold, because the author ranks a *production* and
    /// the thing being compared is a derivation made of many - which is also
    /// how upstream reads it: a tree-sitter subtree's rank is the sum over its
    /// children plus its own production's, so a stack version's rank moves by
    /// the folded production's declaration and by nothing else
    /// (`subtree.c:353,407`, `parser.c:1030`, `stack.c:164,171`), and versions
    /// are ordered by it in `parser.c:284`.
    ///
    /// Speculation depth second, unchanged. It is a fact about the parse loop
    /// rather than about the language, so it is the right thing to decide a
    /// cell the author left arbitrary *and* the wrong thing to let overrule one
    /// they did not. A grammar that declares no `prec.dynamic` never reaches
    /// the first line, which is why this cannot move a table that has no
    /// opinion to spend.
    ///
    /// **There is no third rung, and that was measured rather than assumed on
    /// 2026-08-06.** The obvious candidate is the size of the derivation, on
    /// the reading that upstream compares structure once its own keys tie. It
    /// does not port, for three separate reasons, and it does not pay in either
    /// direction: `research/joinery/arity/RESULT-3-structure.md` has both
    /// boards and the citation. In short - `ts_parser__condense_stack`
    /// (`parser.c:1772`) compares error cost and dynamic precedence and nothing
    /// else, and when they tie it does not choose at all, it merges and keeps
    /// both derivations as links on one node (`parser.c:1806`, `stack.c:712`).
    /// The structural comparison is a layer down in `ts_parser__select_tree`
    /// (`parser.c:872` into `subtree.c:605-619`), it is lexicographic and
    /// first-difference, and upstream's own name for its outcome is
    /// `select_earlier` (`parser.c:875`) - a rule for picking a determinate
    /// representative, which `rank` already is here. Of the two aggregate
    /// readings it admits, preferring the smaller derivation costs python 15
    /// square bytes and verilog 31, and preferring the larger costs elixir 651
    /// and drops markdown to no tree at all.
    fn beats(a: Reading, b: Reading) bool {
        return if (a.heft != b.heft) a.heft > b.heft else a.rank < b.rank;
    }
};

/// A reading waiting to move, and the action it was split into taking. `act` is
/// null for the ordinary case of asking the table.
const Turn = struct {
    top: u32,
    rank: u32,
    seg: u32 = sole,
    heft: i32 = 0,
    act: ?press.Action = null,
    /// The work item that cast this one off a `sided` cell, and whether that
    /// caster survived the token. Instrumentation for the question of whether
    /// an orphaned speculation is ever *confirmed* by what follows it, which
    /// is the one thing about these cells no table cell can carry.
    cast_by: ?u32 = null,
    dead: bool = false,
    /// Identity of the `sided` speculation this reading is or descends from.
    from: u32 = sole,
};

/// No strand: the reading is the only one, so its moves are the file's and go
/// straight into the trail.
const sole = std.math.maxInt(u32);
/// What one token's worth of movement did. `lifted` is the one the driver
/// could not read off a bool: the token was never absorbed, because a whole
/// subtree arrived in its place and the offset is already past it.
const Moved = enum { took, lifted, refused };

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
    first: press.Symbol,

    /// Every spelling of every rule-shaped extra this grammar has.
    ///
    /// All-terminal right-hand sides only. A rule extra that contains another
    /// rule needs a stack to read, and a stack is a parser; nothing in the
    /// corpus asks for one - lua's is `-- content` and `[[ content ]]`,
    /// julia's are `# .*` and `#= rest` - so the ones that would are declined
    /// here rather than half-read somewhere further in.
    fn all(gpa: std.mem.Allocator, gr: *const press.Grammar) ![]const Sprig {
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

/// One table action, spelled the way `joints state` spells it, so a trace line
/// and a table row can be read against each other without translation. A fold
/// carries its production index because the rule is the limb - two rules with
/// the same left-hand side are two different answers.
const Limb = struct {
    gr: *const press.Grammar,
    act: press.Action,

    pub fn format(l: Limb, w: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (l.act.kind) {
            .err => try w.writeAll("nothing"),
            .accept => try w.writeAll("accept"),
            .shift => try w.print("read on -> {d}", .{l.act.value}),
            .reduce => try w.print("fold {s} #{d}", .{
                l.gr.nameOf(l.gr.productions[l.act.value].lhs),
                l.act.value,
            }),
        }
    }
};

/// The most readings held at once.
///
/// Not a tuning knob so much as a fuse. Refutation is what keeps the count
/// down: a losing reading is usually dead within a token or two, and this only
/// decides what happens where several conflicts overlap before any of them are
/// settled. When it does bind, the reading that is *not* forked is the most
/// speculative one, so the table's own answer is never the thing that gets
/// dropped.
///
/// It used to be recorded here that sixteen reaches no further than eight
/// anywhere, so the fuse sat above the corpus's high-water mark rather than at
/// it, and then that "8 stays because the cap is cheap". Both readings were
/// taken with this knob moved alone and neither survives; the paragraph below
/// says why, and the denial counts they quoted (46 in verilog, 4 in swift) are
/// no longer the tree's. At 64/512 the whole corpus is re-censused: **twenty-
/// nine of thirty grammars deny nothing at all**, and swift denies 80 of 987 -
/// all of them the same state on the same token at byte 24283, one fold storm
/// rather than a starved parse.
///
/// That distinction only became measurable once `collapse` stopped spending the
/// budget on copies. Before it, verilog filled the cap with eight spellings of
/// one derivation and the same knob was worth 51 bytes at ~4% - a number that
/// was measuring the twins, not the ambiguity.
///
/// **And "the cap is cheap" was true only of the fork population that existed
/// when it was measured.** That sweep moved this number alone against tables
/// that were resolving the author's declared ties away before the parse ever
/// saw them. Once `workbench.decide` spares an associativity-decided cell, the
/// population changes and 8 is far under the mark: swift alone is 4,006 square
/// bytes, and it is 4,006 with no press change at all, so the old sweep was
/// leaving them on the floor already. The reason it read as saturated is that
/// **this fuse and `skeins` are in series** - raising either one alone just
/// moves which of the two blows. Measured with the side-rung cell spared:
/// 8/64 and 8/512 both leave elixir at 1 square byte, 64/64 leaves it at 1, and
/// 64/512 restores all 23,879. A sweep over one knob cannot see that.
///
/// **And 64 is the knee, not a waypoint - the corner above it was priced and is
/// empty.** The same four-corner method run upward from here, each arm its own
/// binary and all seven boards against one frozen oracle: 512/512, 64/4096 and
/// 512/4096 are byte-identical to 64/512 on all thirty grammars, 309,356 square
/// without verilog. 512 is not inert - it clears every one of swift's 80
/// denials and opens 96 more splits - and those 96 readings are worth **zero
/// square**, which is the cleanest statement of saturation this fuse can make.
/// The trade below is as sharp as the one above is flat: 4/4 costs 110,337.
/// Time and peak RSS across the corpus are 1.02x and 1.00x at 512/4096, so what
/// stops this rising further is that there is nothing above it, not the cost.
const crowd = 64;

/// How many strands may stand between two collapses.
///
/// A strand is one live reading's unrecorded moves, so the memory a standing
/// fork costs is this times the moves since it opened. Forks that never
/// collapse are the only way to reach it, and the answer when it binds is the
/// same as `crowd`'s: decline to split. Declining costs one speculative
/// reading; tearing the trail costs the file's whole tiling.
///
/// In series with `crowd`, and that is the whole reason this number moved:
/// a fork needs a slot *and* a strand, so whichever fuse is lower is the only
/// one a single-knob sweep can observe. See `crowd` for the four-corner
/// measurement. Raising it costs nothing measurable - a strand is allocated
/// when a fork opens, not reserved - and the elixir parse, the only case on the
/// board big enough to time honestly, is 1.00x either side.
///
/// Which of the pair is live is now separated rather than inferred, and it is
/// not this one. Swift is the corpus's only denier at 64/512; `skeins` at 4096
/// with `crowd` held leaves **all 80 of its denials standing**, while `crowd`
/// at 512 with `skeins` held clears them all. So on today's board this fuse is
/// slack everywhere and 512 is headroom, not a limit - it earns its number by
/// being the thing that must not be lower than `crowd` needs, which is why it
/// still has to move whenever `crowd` does.
const skeins = 512;

/// How much of one file recovery may walk past before the parse stops calling
/// it a file in this language, as a numerator over `whole`.
///
/// Every mend costs an `offer` over every terminal, so a byte-by-byte walk
/// through a megabyte of the wrong language is the one shape recovery makes
/// slow, and it is also the shape where the answer was never going to be a
/// tree. That shape is "the file was skipped", and the honest way to say it is
/// in bytes: this was a cap on the mend *count* until round 22, which is the
/// wrong unit twice over. A count says nothing about how much of the file
/// survived - a mend deletes a byte where it used to delete a kilobyte - and
/// it was not load-bearing anyway, since `over` is always past `x.at` and so
/// the count is already bounded by the file length.
///
/// Three quarters, because that is where the measurement separates. Every
/// grammar in the corpus is under it on a file of its own language, the worst
/// real rows being julia and haskell; a walk through the wrong language runs
/// away toward the whole file. The same shape as `covered` replacing `reach`:
/// count the bytes, not the events.
const fuse = 3;
const whole = 4;

/// How far a lookahead walk may follow the table before it stops guessing:
/// pretend-perches it may stack up, and steps it may take doing it.
///
/// Hoisted out of `shiftable`, where they were two locals, because there are
/// now two walks over the same table and a second copy of a bound is a third
/// bound - which is the shape a sibling lane is auditing the whole tree for.
/// Same values, same reason, one home beside the other fuses.
///
/// **What a walk does when it runs out is not shared, and must not be.** A
/// production that consumes nothing can push forever, so both walks stop; but
/// `shiftable` is asking whether to hand a terminal to the scanner, where
/// admitting one the parse then refuses is the old behaviour and losing one it
/// could have shifted is a wrong tree - so it answers yes. `follows` is asking
/// whether to write a token the author did not, where a yes on a walk that gave
/// up is a node over text nobody wrote - so it answers no. Two questions, two
/// safe defaults, one budget.
///
/// **These two are in series and neither had ever been swept.** `climb` bounds
/// the pretend-perches and `chase` bounds the steps, and a step is what stacks
/// a perch, so `chase` under `climb` makes `climb` unreachable and the pair has
/// one effective bound. That is `crowd`/`skeins`' wiring, and the danger runs
/// the other way here: **running out is an answer, not a pause.** `shiftable`
/// answers yes when it gives up, so a *wider* budget is a stricter walk - it
/// has more chances to reach one of the three `return false` arms before the
/// permissive exit. Raising one of these is not obviously safe.
///
/// Swept jointly, seven arms on one tree against one frozen oracle, scored on
/// square without verilog: 1/2 loses **143,879** - php, scala, kotlin, swift,
/// typescript and julia all collapse - 2/8 loses 23,878, and 4/16, 8/32, 32/32,
/// 8/128 and 32/128 are byte-identical at 309,356 on all thirty grammars. So
/// the answer saturates at 4/16, 8/32 is one doubling of margin above the knee,
/// and 32/128 costs 0.995x the corpus's parse time for nothing. The margin is
/// what these are for; the numbers are now measured rather than inherited.
const climb = 8;
const chase = 32;

/// One lookahead walk over the table, standing on a real stack it never
/// touches.
///
/// Folds are forced moves, so replaying them costs a few table reads and
/// answers exactly; nothing is minted and no perch is pushed. States the walk's
/// own folds arrive in live in `up`, and only those are popped before the real
/// chain beneath `base` is walked down.
const Ahead = struct {
    x: *const Gather,
    /// The deepest real perch the walk has descended to.
    base: u32,
    /// States pushed by folds this walk performed, standing on `base`.
    up: [climb]u32,
    ups: usize,
    /// Why the last `unsure` this walk returned was unsure. Meaningless
    /// unless a `Step.unsure` was actually handed back.
    hazy: Hazy,

    fn on(x: *const Gather, top: u32) Ahead {
        return .{ .x = x, .base = top, .up = undefined, .ups = 0, .hazy = .clear };
    }

    fn state(a: *const Ahead) u32 {
        return if (a.ups > 0) a.up[a.ups - 1] else a.x.perches.items[a.base].state;
    }

    /// Why a walk declined to answer, recorded beside the `unsure` that
    /// carries it.
    ///
    /// Diagnostic only: no arm of the parse branches on this, and every
    /// `unsure` remains a no to `follows` and a yes to `shiftable` exactly as
    /// before. It exists because *the caller cannot otherwise tell a table
    /// fact from a spent budget*, and a bucket that cannot tell them apart is
    /// a residual wearing a positive name - `residue.py`'s `none` read 1,288
    /// on this corpus with no way to say how many were real.
    const Hazy = enum {
        /// Nothing declined; the walk answered.
        clear,
        /// A cell the author declared ambiguous, which `absorb` would split
        /// rather than choose. A property of the grammar, not of the budget.
        forked,
        /// `climb` overlay full - more folds stacked than the walk can stand
        /// on. A budget.
        climbed,
        /// `chase` steps taken without reaching a shift. A budget.
        chased,
    };

    /// What one lookahead comes to, once the folds it forces have run.
    const Step = union(enum) {
        /// A shift is on the other side of them, landing here.
        reads: u32,
        /// The end column accepting, which has no state to land in.
        done,
        /// The table has nothing for this symbol from here.
        stops,
        /// The walk cannot say: a cell the author declared ambiguous, which
        /// `absorb` would split rather than choose, or a budget it ran out of.
        /// The two callers want opposite defaults, so neither is taken here.
        /// Which of the three it was is left in `hazy`.
        unsure,
    };

    fn take(a: *Ahead, sym: press.Symbol) Step {
        for (0..chase) |_| {
            const here = a.state();
            if (a.x.forking) if (a.x.forks.at(here, sym).len != 0) return a.gave(.forked);
            const act = a.x.t.at(here, sym);
            switch (act.kind) {
                .err => return .stops,
                .shift => return .{ .reads = act.value },
                .accept => return .done,
                .reduce => {
                    const p = a.x.gr.productions[act.value];
                    var n = p.rhs.len;
                    const virtual = @min(a.ups, n);
                    a.ups -= virtual;
                    n -= virtual;
                    if (n > 0) {
                        if (a.x.deep(a.base) < n) return .stops;
                        for (0..n) |_| a.base = a.x.below(a.base);
                    }
                    const under = a.state();
                    const to = a.x.c.goto(under, p.lhs) orelse return .stops;
                    if (!a.push(to)) return a.gave(.climbed);
                },
            }
        }
        return a.gave(.chased);
    }

    /// Record why this walk is about to decline, and decline.
    fn gave(a: *Ahead, why: Hazy) Step {
        a.hazy = why;
        return .unsure;
    }

    /// What a whole `follows` question came to. `no` is a table fact - the
    /// walk reached an `err` cell or an accept and knows the answer. The other
    /// three are the walk declining, and they are kept apart from `no` so a
    /// bucket built on "every candidate said no" can assert that rather than
    /// inherit it.
    const Says = enum {
        yes,
        no,
        forked,
        climbed,
        chased,

        fn from(h: Hazy) Says {
            return switch (h) {
                // `take` sets `hazy` at every arm that returns `unsure`, so a
                // `clear` here is that invariant broken rather than a state to
                // paper over. `chased` is the conservative read - it says the
                // walk could not tell, which is the whole point of the split.
                .clear => .chased,
                .forked => .forked,
                .climbed => .climbed,
                .chased => .chased,
            };
        }

        /// The wire name `declined` reports and `residue.py` buckets on.
        fn word(s: Says) []const u8 {
            return switch (s) {
                .yes => "yes",
                .no => "none",
                .forked => "forked",
                .climbed => "climbed",
                .chased => "chased",
            };
        }
    };

    /// Stand on a state the walk decided to arrive in, so it can carry on
    /// above it. False is the overlay full, which is the walk giving up.
    fn push(a: *Ahead, to: u32) bool {
        if (a.ups == climb) return false;
        a.up[a.ups] = to;
        a.ups += 1;
        return true;
    }
};

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
    gr: *const press.Grammar,
    c: *const press.Collection,
    t: *const press.Tables,
    scanner: *lex.Scanner,

    /// Which cells the author declared ambiguous, and what the table dropped
    /// there. Empty for a grammar that declares nothing.
    forks: press.Forks,
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
    /// Whether the trail holds two readings' moves interleaved, which is a
    /// record neither of them made and cannot be repaired, only refused.
    ///
    /// Nothing sets it any more, and that is the point rather than an
    /// oversight: `strands` keeps each live reading's moves apart and welds the
    /// survivor's in, so the interleaving this guarded against no longer
    /// happens. It stood for two years and cost every forking grammar its whole
    /// incremental path - one fork anywhere forfeited the tiling for the file,
    /// including every token before the fork opened - while eleven lines below
    /// where it was set the parse already knew when the fork ended. Kept as the
    /// name of the hazard and as the flag a future writer into the trail has to
    /// either honour or re-raise. Round 15.
    torn: bool,
    /// How many times a fork was created, and how many of those the parse
    /// later collapsed back to one reading. `torn` says a fork happened; these
    /// say how often and whether it stayed. A grammar whose table can fork and
    /// whose input never makes it is a different animal from one that forks
    /// forty times and resolves every one, and only the second is worth
    /// recording a trail per limb for.
    rifts: u32,
    /// How many `sided` speculations this parse has orphaned - cast off a cell
    /// an authored side ordered, and then had their caster refuted by the same
    /// token. Mints the identity each one is tracked by. Instrumentation.
    orphans: u32 = 0,
    roosts: u32,
    /// How many readings were dropped for standing on a stack another reading
    /// was already standing on. A fork that folds back to the same states is
    /// not a second reading of anything - see `twinned` - and counting the
    /// collapses is what distinguishes a grammar whose conflicts really do
    /// carry two derivations from one that was paying 2^n for one derivation
    /// written n ways.
    merges: u32,
    /// How many declared conflicts went unforked because `crowd` or `skeins` had
    /// no room. This is the number that says whether either cap is a live limit,
    /// and it only became answerable once `collapse` stopped filling the budget
    /// with copies: a denial now means the loop ran out of room for a *genuine*
    /// alternative, which is a different and worse thing than running out of
    /// room for the eighth spelling of one derivation.
    denied: u32,
    /// One move list per live reading while a fork stands. A fork is the only
    /// thing that makes the flat trail a lie - two readings appending into it
    /// interleave a record neither of them made - so each reading writes its
    /// own moves here instead, and the survivor's are spliced into the trail
    /// when the fork collapses. Pooled: the lists are cleared and reused, so a
    /// file that forks ten times allocates for the widest fork, not for ten.
    strands: std.ArrayList(std.ArrayList(Move)),
    /// How many of `strands` are handed out right now. The pool itself only
    /// grows, so a file that forks ten times pays one allocation per strand of
    /// the widest fork and none after that.
    spun: u32,
    /// Where a move goes right now - `sole` for the trail, otherwise an index
    /// into `strands`. Set by `absorb` as it takes each reading in turn.
    pen: u32,

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
    /// The reduces the token in hand drove before it was refused, in the order
    /// it drove them. Cleared as each token enters the absorb loops and appended
    /// only for the table's own reading, so it describes the same stack
    /// `refused` and `spent` do rather than a speculation's.
    ///
    /// Kept because a wall's state is where the folds ran out, not where the
    /// reading stood: `press/inquest.zig` can name the cell that killed a parse
    /// and its `press.Floor` bucket, but only over this path. Without it every
    /// verdict on a table with any damage on that terminal degrades to "cannot
    /// rule the press out".
    folded: std.ArrayList(quire.Fold),
    /// The chain as it stood at the stop this parse will report, which is not
    /// the same list. `folded` is cleared by the next token, and a mended parse
    /// reports its *first* refusal while absorbing many more after it - so a
    /// chain read at the end describes a token the reported stop never names.
    /// Sealed once, at the moment a stop becomes the one that will be reported.
    wall: std.ArrayList(quire.Fold),

    /// What to do about a token the parse cannot read. Off is the answer this
    /// loop gave before recovery existed, and is still the answer for anyone
    /// who has not asked for another.
    mend: Mend,
    /// How many times it has done it, and the stop it would have reported the
    /// first time. A file that needed no mending reports and behaves exactly
    /// as it did.
    mends: u32,
    /// Bytes those mends walked past, and the length of the file they are a
    /// share of. The pair the fuse is asked of - a count of mends cannot tell
    /// a file with sixty small holes from a file that was skipped whole, and
    /// telling those apart is the entire job of the fuse.
    skipped: u32,
    /// Where each of those mends was, in order. The counts above are this list
    /// folded; a reader that wants to know which bytes were repaired rather
    /// than how many needs the sites, and nothing else in the runtime keeps
    /// them. Handed to the `Quire` by `finish`.
    scars: std.ArrayList(quire.Scar),
    /// Whether the second move is available at all.
    ///
    /// A vocabulary switch, not a tuning knob: on, a refusal may be repaired by
    /// supplying a terminal as well as by deleting one; off, this loop has the
    /// one move it had before `supply` existed. It is here because **the
    /// control for measuring what the second move bought has to be the same
    /// binary over the same tree** - ten agents edit this checkout at once, so
    /// a control built from another commit is a control that differs in more
    /// than the thing under test. Any board can now price both arms of that
    /// comparison without a second pin, and can keep doing it after this lane.
    ///
    /// ## Why `init` leaves it off and only the CLI turns it on
    ///
    /// The one caller that was measured is `joints parse`, and it is also the
    /// only one that reads a file once. The **incremental** path does not: an
    /// amend replays a recorded trail, and the trail's alignment marks are one
    /// per `read`, indexed by token count, offered to a later parse as "resume
    /// here in this state". A supply scribes a `read` that keeps that index
    /// 1:1 - which is the whole reason `plant` lays its own leaf rather than
    /// reusing `perch` - but the mark it adds points at a byte where re-lexing
    /// yields the *real* token and not the ghost, and no test in this tree has
    /// ever offered a graft a zero-width token to land on.
    ///
    /// So the default is the behaviour every existing caller already has, and
    /// the surface that measured the change is the surface that asks for it.
    /// This is scoping, not gating: the argument for the second move is a
    /// measurement of `square` against a tree-sitter oracle over whole files,
    /// and that measurement says nothing about resume. Turning it on for
    /// `weave` wants its own evidence and is the next lane's third brief.
    supplying: bool,
    /// Terminals supplied, and refusals where more than one would have done.
    /// See `supply`, and `Quire.supplied` for why neither is `mends`.
    supplies: u32,
    spurned: u32,
    /// Every anonymous terminal this grammar has, gathered once. The candidate
    /// set a supply chooses from, and the whole reason `supply` is a loop over
    /// a short list rather than over `terminal_count` with a shape test inside
    /// it - most grammars spell far more patterns than literals.
    literals: []const press.Symbol,
    wide: u32,
    why: ?quire.Stop,
    /// Whether the last mend kept the stack rather than felling it. Read only
    /// by `relent`, and cleared by any token that shifts, so the benefit of
    /// the doubt is per refusal rather than per file.
    kept: bool,

    pub fn init(
        gpa: std.mem.Allocator,
        gr: *const press.Grammar,
        c: *const press.Collection,
        t: *const press.Tables,
        scanner: *lex.Scanner,
    ) !Gather {
        std.debug.assert(gr.field_names.len < Mark.none);
        std.debug.assert(gr.aliases.len < Mark.none);
        var forks = try press.Forks.of(gpa, t.conflicts, c.states.len, t.width);
        errdefer forks.deinit(gpa);
        const sprigs = try Sprig.all(gpa, gr);
        errdefer gpa.free(sprigs);
        var literals: std.ArrayList(press.Symbol) = .empty;
        errdefer literals.deinit(gpa);
        for (0..gr.terminal_count) |sym| {
            if (gr.shapeOf(@intCast(sym)) == .anonymous) try literals.append(gpa, @intCast(sym));
        }
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
            .rifts = 0,
            .roosts = 0,
            .merges = 0,
            .denied = 0,
            .strands = .empty,
            .spun = 0,
            .pen = sole,
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
            .folded = .empty,
            .wall = .empty,
            .mend = .fell,
            .mends = 0,
            .skipped = 0,
            .scars = .empty,
            .supplying = false,
            .supplies = 0,
            .spurned = 0,
            .literals = try literals.toOwnedSlice(gpa),
            .wide = 0,
            .why = null,
            .kept = false,
        };
    }

    pub fn deinit(x: *Gather) void {
        x.forks.deinit(x.gpa);
        for (x.strands.items) |*st| st.deinit(x.gpa);
        x.strands.deinit(x.gpa);
        x.perches.deinit(x.gpa);
        x.folded.deinit(x.gpa);
        x.wall.deinit(x.gpa);
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
        x.gpa.free(x.literals);
        x.grown.deinit(x.gpa);
        x.tokens.deinit(x.gpa);
        x.enter.deinit(x.gpa);
        x.scars.deinit(x.gpa);
        x.* = undefined;
    }

    /// Parse `bytes` into a tree. A parse that stopped early still hands back
    /// everything it had completed, as a forest, with `Quire.stop` saying
    /// where it stopped and why.
    pub fn run(x: *Gather, bytes: []const u8) !Quire {
        x.bare();
        x.roots.clear();
        x.mends = 0;
        x.skipped = 0;
        x.scars.clearRetainingCapacity();
        x.supplies = 0;
        x.spurned = 0;
        x.wide = @intCast(bytes.len);
        x.why = null;
        x.kept = false;
        x.torn = false;
        x.rifts = 0;
        x.roosts = 0;
        x.merges = 0;
        x.denied = 0;
        x.unstrand();
        x.lone = true;
        x.grafted = false;
        x.lead = 0;
        x.leads = 0;
        x.refused = 0;
        x.spent = 0;
        x.folded.clearRetainingCapacity();
        x.wall.clearRetainingCapacity();
        x.stood = null;
        if (x.bough) |b| {
            if (try x.alight(b, bytes)) |i| x.stood = try x.remount(b, i);
        }
        if (x.stood == null) try x.ground();

        while (true) {
            x.offer();
            var here = x.perches.items[x.first().top].state;
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
                .stray => |off| x.blame(bytes, off) orelse {
                    // No terminal begins here under any state, so there is no
                    // token to delete. A word is stepped over whole even so:
                    // resuming inside `return` reads `eturn` as an identifier,
                    // and a node over half a word is worse than no node.
                    const stop: quire.Stop = .{ .stray = off };
                    if (try x.mended(stop, x.first().top, off, word(bytes, off))) continue;
                    try x.stow(null);
                    try x.unwind(x.first().top);
                    return x.finish(x.why orelse stop);
                },
                .token => |t| t,
            };

            if (try x.sprout(tok, bytes)) continue;
            var moved = try x.absorb(tok);
            // The refused token is the first of two hypotheses, not the
            // verdict: it may be that nothing is wrong with it and something
            // in front of it is missing. `supply` asks the table, and a yes
            // leaves a zero-width terminal shifted and this same token still
            // to read - so it is re-offered here rather than re-lexed, which
            // is what makes the retry provably the token we proved readable.
            //
            // A second refusal falls straight through to the deletion that
            // would have happened anyway. `shiftable`'s walk gives up rather
            // than guessing, so a supply can be admitted on a walk that never
            // reached the shift; when that happens the cost is one zero-width
            // node and the ordinary repair, not a loop.
            if (moved == .refused) if (try x.supply(tok)) {
                here = x.perches.items[x.first().top].state;
                moved = try x.absorb(tok);
            };
            switch (moved) {
                .lifted => continue,
                .took => {},
                .refused => {
                    const stop: quire.Stop = .{
                        .unexpected = .{
                            .symbol = tok.symbol,
                            .at = tok.start,
                            // The state that refused it, which is where the folds ran
                            // out - not `here`, where they started.
                            .state = x.refused,
                            .folded = try x.seal(),
                        },
                    };
                    if (try x.mended(stop, x.spent, tok.start, tok.end())) continue;
                    // The token was refused, so nothing shifted and its leaf is
                    // never made - but the extras read on the way to it were
                    // read, and they are the forest's as much as a trailing
                    // comment is.
                    try x.stow(null);
                    try x.unwind(x.spent);
                    return x.finish(x.why orelse stop);
                },
            }
            try x.tokens.append(x.gpa, tok);
            try x.enter.append(x.gpa, here);
            x.kept = false;
            const was = x.at;
            x.at = tok.end();
            // A ring is a promise that a later parse can stand up where this
            // one stood. Past a mend the chain is no longer the whole tree -
            // a `fell` carries what completed before the break off into the
            // roots - so the promise needs the roots watermark beside it, and
            // for want of that field the ring used simply not to be taken.
            //
            // Not taking it is the same "possible somewhere for standing right
            // now" shape as `torn` and `x.forking`: one mend anywhere ended
            // ring-taking for the rest of the file, so every later keystroke
            // on that file resumed below the first wall or not at all. On the
            // corpus that is fourteen grammars mending in the thousands, and
            // in an editor it is the median keystroke, since a file being
            // typed into is momentarily invalid almost continuously. Round 19.
            if (x.bough) |b| if (b.tick()) try x.limb(b, was);
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
    fn mended(x: *Gather, stop: quire.Stop, top: u32, from: u32, over: u32) !bool {
        if (x.mend == .none) return false;
        // The fuse, in bytes. `from` rather than `x.at` is the honest left
        // edge: the bytes between them were read as extras on the way to the
        // refusal and are in the forest, so charging them to recovery would
        // meter a heavily commented file as a skipped one. Same distinction
        // `covered` drew against `reach` - what is under a root, not what a
        // watermark reached.
        //
        // Asked of what recovery has walked *already*, so the mend in hand is
        // never the one refused. A file smaller than the fuse would otherwise
        // get no recovery at all from a single wide mend, and one mend is
        // exactly the case the broken corpus is made of. Termination is
        // unchanged and does not rest on this: `over` is always past `x.at`.
        if (x.skipped > @as(u64, x.wide) * fuse / whole) return false;
        // Read before either branch below, because both clear `live`: the
        // question is how many readings stood at the *refusal*, and after the
        // branch the only honest answer is one.
        const heads: u32 = @intCast(x.live.items.len);
        if (x.why == null) x.why = stop;
        x.mends += 1;
        x.skipped += over - from;

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
        try x.scribe(.{ .mend = .{ .at = over } });
        // The site, for anyone downstream who needs to tell a stretch this
        // parse read from one it walked past. Appended after the unwind so the
        // list orders with the trail, but every field it carries about the
        // break itself was read before it - see `heads`.
        try x.scars.append(x.gpa, .{
            .at = from,
            .over = over,
            .heads = heads,
            .shifted = @intCast(x.tokens.items.len),
            .felled = fell,
            .why = stop,
        });
        x.at = over;
        return true;
    }

    /// The other hypothesis about a refusal: nothing is wrong with this token
    /// and a terminal in front of it is missing.
    ///
    /// True means one was supplied, the stack read it, and the caller should
    /// offer the same token again. False means the parse should repair the way
    /// it always did.
    ///
    /// ## Why this is a rule and not a heuristic
    ///
    /// The tables already know what each state wants, and most states want
    /// several things, so "a terminal is legal here" justifies nothing. What
    /// justifies a supply is the *pair*: a terminal that, once read, makes the
    /// token the file actually holds readable again. That is the grammar
    /// naming the omission rather than the parser guessing at one, and it is
    /// asked of the stack that is standing rather than of a state in the
    /// abstract - `follows` walks the real chain down.
    ///
    /// Three clauses, and each one is a claim that can be wrong on its own:
    ///
    ///   1. **Anonymous only.** An anonymous terminal is a literal the grammar
    ///      spells itself, so "a `}` is missing" is a complete statement. A
    ///      named terminal is a pattern; a zero-width instance of one is a
    ///      token no lexer could produce, and supplying it would assert text is
    ///      missing while declining to say which text. The layout terminals
    ///      that legitimately *are* zero-width - swift's `_implicit_semi`,
    ///      haskell's layout hand - are named, and they are the scanner's to
    ///      produce, not recovery's to invent.
    ///   2. **The refused token must resume.** Not "the supply is shiftable".
    ///      This is what stops an insertion letting the parse limp on through
    ///      nonsense, and it is also the termination proof: a supply is always
    ///      immediately followed by a real shift, so the offset advances and no
    ///      byte can be supplied into twice.
    ///   3. **Exactly one candidate.** Two terminals that would each resume the
    ///      parse is the table declining to say which, and choosing there is
    ///      worse than not choosing: a wrong delimiter builds a real subtree
    ///      over bytes the author grouped differently. Counted as `spurned`
    ///      rather than resolved, because a ranking rule is a different claim
    ///      than this one and wants its own evidence.
    ///
    /// No constant is introduced. The two bounds are `climb` and `chase`, which
    /// `shiftable` was already spending on every token of every parse.
    ///
    /// ## Where it is asked from
    ///
    /// `x.spent` - the perch the table's own reading died on, after the folds
    /// this token forced. Those folds are already committed to the stack, so
    /// this is the configuration the refusal is genuinely standing in and the
    /// one `mended`'s `keep` would re-seat on. Not `x.live`: a fold under
    /// `x.lone` shrinks the perch array, so a reading's recorded top can be an
    /// index that no longer exists by the time the refusal is reported.
    fn supply(x: *Gather, tok: Token) !bool {
        if (!x.supplying or x.mend == .none) return false;
        // The same fuse `mended` is held to. A supply walks past no bytes so it
        // cannot move the numerator, but a file this far gone is one recovery
        // has already declined to keep reading, and paying a candidate search
        // per token to keep saying so is the one shape this is slow in.
        if (x.skipped > @as(u64, x.wide) * fuse / whole) {
            return x.declined("fuse", tok);
        }
        // The perch the refusal stood on is gone: a fold under `x.lone` shrinks
        // the array, so the recorded top can outlive the thing it indexed.
        // There is no configuration left to ask a question of.
        if (x.spent >= x.perches.items.len) return x.declined("unseated", tok);
        // A supply repairs an *omission*, and an omission is only a thing
        // relative to something the author began. On the ground there is no
        // such thing: nothing has been read, so a terminal refused here is
        // simply not a legal start, and writing a prefix that makes it legal
        // manufactures a construct rather than completing one.
        //
        // This is not a nicety. Without it the two moves eat each other: a
        // `fell` stands the parse up in state zero at the byte after the token
        // it deleted, and the very next thing the ground refuses is whatever
        // that token was *part* of - so the parse deletes a `"` and then
        // supplies a `"` so the string body it left behind can be read. Both
        // repairs are individually table-justified and together they are a
        // no-op with two scars.
        if (x.deep(x.spent) == 0) return x.declined("ground", tok);
        // Both read before anything moves. `heads` taken after the plant would
        // be one on every scar of every grammar - the constant-field trap this
        // channel already fell into once - and `shifted` would count the
        // supplied token as a token this parse had read when it refused.
        const heads: u32 = @intCast(x.live.items.len);
        const shifted: u32 = @intCast(x.tokens.items.len);

        var give: ?press.Symbol = null;
        // The positive test. `none` claims *no literal terminal could stand
        // for the refused external* - a claim about the table. A walk that ran
        // out of `climb` or `chase`, or hit a declared fork, did not establish
        // it: that candidate might have resumed the parse with one more step.
        // Counted rather than flagged, because one hazy walk out of two
        // hundred is an instrument nit and two hundred out of two hundred is a
        // walk that never worked, and the two need different repairs.
        var hazy: Ahead.Says = .no;
        var hazes: u32 = 0;
        for (x.literals) |sym| {
            const says = x.follows(x.spent, sym, tok.symbol);
            if (says != .yes) {
                if (says != .no) {
                    hazes += 1;
                    if (hazy == .no) hazy = says;
                }
                continue;
            }
            if (give != null) {
                // Two answers is no answer. Recorded here rather than inferred
                // downstream, because "no repair exists" and "several do" are
                // the two halves of the residue and only the parse can tell
                // them apart.
                x.spurned += 1;
                assay.trace(.quire, "spurned: {s} and {s} both resume {s} at {d} in state {d}\n", .{
                    x.gr.nameOf(give.?), x.gr.nameOf(sym), x.gr.nameOf(tok.symbol), tok.start, x.refused,
                });
                return false;
            }
            give = sym;
        }
        // Said on its own line rather than folded into the `stood down` word,
        // so the shape downstream already parses does not move and the
        // severity is readable: how many of how many candidates the walk could
        // not tell about. A grammar with no anonymous symbols at all reads
        // `0 of 0`, which is a vacuous `none` and the third way this bucket
        // could have been lying.
        //
        // Emitted whatever the outcome, because a *supply* made while some
        // other candidate was untellable is the same weakness pointing the
        // other way: `give` is the only literal that said yes, but it is not
        // established that it is the only one that would have. The `spurned`
        // arm above returns mid-loop and so has no count - that is a real hole
        // and saying nothing is the honest form of it.
        if (hazes != 0) assay.trace(.quire, "unsure ({s}): {d} of {d} literals at {d} in state {d}\n", .{
            hazy.word(), hazes, x.literals.len, tok.start, x.refused,
        });
        const sym = give orelse return x.declined(hazy.word(), tok);

        // Against the last byte the stack consumed, not against the refused
        // token. See `plant`: this is where the omission is, and it is the
        // only offset at which a zero-width child is inside its parent.
        const anchor = x.perches.items[x.spent].end;
        const grown = try x.plant(x.spent, sym, anchor) orelse return false;
        assay.trace(.quire, "supplied: {s} at {d} so state {d} can read {s}\n", .{
            x.gr.nameOf(sym), anchor, x.refused, x.gr.nameOf(tok.symbol),
        });
        // Every other reading died with this one; the parse stands where the
        // repair left it, exactly as `mended`'s `keep` leaves it.
        x.live.clearRetainingCapacity();
        try x.live.append(x.gpa, .{ .top = grown });
        x.lone = true;

        if (x.why == null) {
            // Sealed into a name first, because the literal below is built *in
            // place* in `x.why` - so the tag lands before the field expression
            // runs, and a `seal` called inside it would find the stop it is
            // being called for already remembered and decline. That read as a
            // supply-only null chain, on exactly the grammars whose first
            // refusal is a supply.
            const chain = try x.seal();
            x.why = .{
                .unexpected = .{
                    .symbol = tok.symbol,
                    .at = tok.start,
                    .state = x.refused,
                    .folded = chain,
                },
            };
        }
        x.supplies += 1;
        try x.scars.append(x.gpa, .{
            .at = anchor,
            .over = anchor,
            .gave = sym,
            .heads = heads,
            .shifted = shifted,
            .felled = false,
            .why = .{
                .unexpected = .{ .symbol = tok.symbol, .at = tok.start, .state = x.refused },
            },
        });
        return true;
    }

    /// Why the second move stood down here, said once and always false.
    ///
    /// The residue is the point. A refusal insertion declined is one of six
    /// different things - `fuse` (recovery had already given up on the file),
    /// `unseated` (the perch the refusal stood on was folded away), `ground`
    /// (nothing standing to have omitted anything from), `none` (every literal
    /// reached a *table* no), and `forked`/`climbed`/`chased` (the walk
    /// declined to say, at a declared ambiguity or at one of the two budgets)
    /// - plus the `spurned` counter, which is the only one a *ranking* rule
    /// could close.
    ///
    /// The last three used to be spelled `none` as well, and that is what made
    /// `none` a residual: it was whatever fell through, so a spent budget and
    /// an honest miss produced the same word and no downstream instrument
    /// could separate them. They are named here because naming them is the
    /// only place the distinction still exists - by the time `supply` returns,
    /// every one of them is the same `false`. Compiles out unless
    /// `JOINTS_TRACE=quire` is set.
    fn declined(x: *const Gather, why: []const u8, tok: Token) bool {
        assay.trace(.quire, "stood down ({s}): {s} at {d} in state {d}\n", .{
            why, x.gr.nameOf(tok.symbol), tok.start, x.refused,
        });
        return false;
    }

    /// Read a terminal that is not in the file: fold to the state that shifts
    /// it, then shift it over no bytes at all.
    ///
    /// The shift path, but not `perch`'s, and the difference is the two things
    /// a token nobody wrote must not take from the token that comes after it.
    ///
    /// **Its offset.** A supply goes at `at` - the end of the last byte the
    /// stack consumed - and not at the refused token's start. The parse is
    /// asserting the author finished a construct and omitted its end, so the
    /// end belongs against the last thing they did write; and the whitespace
    /// and comments between belong to the token they were read in front of.
    /// This is also a soundness requirement rather than a taste: `reduce`
    /// spans a node over the children that consumed something, so a zero-width
    /// child past the last real one is a child outside its parent, which is
    /// the `loose` half of what `--sound` counts. Measured: with the ghost at
    /// the refused token's start, `int x = 1 \n return x;` yields the right
    /// tree with `; [31,31) in declaration [19,28)` hanging off the end of it.
    ///
    /// **Its extras.** `stow` merges everything read since the last token into
    /// the run in front of the token in hand, and it runs once. Spending it
    /// here would put the newline and the comment before the missing `;` in
    /// front of the *supply*, out of offset order with a leaf that now sits
    /// behind them. So this lays down the ghost's own leaf and leaves `stow`
    /// unspent for the real token, which is what puts a comment written before
    /// a supplied `}` inside the block it closes.
    ///
    /// `absorb` is not reused either: it would offer the graft a lift at a
    /// zero-width position and split on a declared conflict, and neither is a
    /// thing to do with a token nobody wrote.
    ///
    /// The token stream gets it. `weave` builds one alignment mark per `read`
    /// in the trail and a ring indexes them by token count, so a move with no
    /// token behind it would slide every mark past it by one. The cost is that
    /// a later parse re-lexing the recorded stream finds no zero-width literal
    /// there and declines the ring - a cold resume on a file that was
    /// repaired, which is the conservative half of the trade.
    fn plant(x: *Gather, top: u32, sym: press.Symbol, at: u32) !?u32 {
        const ghost: Token = .{ .symbol = sym, .start = at, .len = 0 };
        var t = top;
        for (0..chase) |_| {
            const state = x.perches.items[t].state;
            const act = x.t.at(state, sym);
            switch (act.kind) {
                .shift => {
                    const own: u32 = @intCast(x.borne.len());
                    var owns: u32 = 0;
                    if (x.gr.shapeOf(sym).visible()) {
                        try x.bear(&x.borne, try x.mint(.of(sym), at, 0, .{}), .{});
                        owns = 1;
                    }
                    try x.scribe(.{ .read = .{
                        .at = state,
                        .symbol = sym,
                        .from = at,
                        .end = at,
                    } });
                    const grown = try x.push(t, .{
                        .state = act.value,
                        .own = own,
                        .owns = owns,
                        // No extras of its own, and none borrowed: the run in
                        // front of the real token is still unspent.
                        .lead = own,
                        .leads = 0,
                        .start = at,
                        .end = at,
                    });
                    try x.tokens.append(x.gpa, ghost);
                    try x.enter.append(x.gpa, state);
                    return grown;
                },
                .reduce => t = try x.fold(t, act.value) orelse return null,
                .err, .accept => return null,
            }
        }
        return null;
    }

    /// Put the parse on the ground: one perch holding nothing, in state zero.
    ///
    /// Reached either because no ring was on offer or because every ring tried
    /// was declined, and the second of those has been somewhere: `holds` drove
    /// the scanner over a stretch of the file to ask its question. A file
    /// begins at byte zero with a scanner that remembers nothing, the same
    /// thing `mended`'s `fell` says to both halves, so the memory is rewound
    /// here rather than left wherever the last probe stopped.
    fn ground(x: *Gather) !void {
        x.scanner.rewind();
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
    ///
    /// ## Descending past a decline is not free, and the reason is measured
    ///
    /// It reads like it should be. `holds` declining says the stretch between
    /// two rings cannot be shown to lex the way it was recorded - and that is
    /// exactly the stretch the ordinary loop re-reads if the parse stands on the
    /// ring *below* it. So a decline looks like an answer to *which* ring to
    /// mount rather than whether to mount one, resting on the assumption `holds`
    /// already states for the hundreds of tokens under its own stretch: that no
    /// token's scan reaches beyond a whole ring's worth of text.
    ///
    /// That is worth a lot. verilog's keystroke fell from 8,951 tokens to 1,333
    /// and 59,481us to 8,138us on the deep edits; scala, lua, haskell and
    /// markdown all resumed where they had been re-reading the file.
    ///
    /// `abide` refuses it, and the witness is one keystroke:
    ///
    ///     joints amend haskell.folio Shared.hs '23548..23548=x'
    ///
    /// against a cold parse of the same bytes. Baseline agrees; descending past
    /// the decline diverges, and diverges *above* the resume - `(wildcard)`
    /// where the cold parse reads `(variable)`, three `"="` tokens that are not
    /// in the cold tree. The mount was ring 112 at 23,184, after ring 113
    /// declined. haskell's layout hand is the reason it is the grammar that
    /// catches this: `_cmd_layout_start` is recorded at 23,187 and the walk
    /// answers 23,185, so the two rings disagree about where a zero-width token
    /// standing between them belongs, and the resumed hand carries that
    /// disagreement forward into every token after it.
    ///
    /// Two narrowings of `holds` were measured beside it and are refused for the
    /// same reason, which is worth writing down because both look obviously
    /// safe. Accepting a zero-width token's *offset* (nothing covers no bytes,
    /// so there is nothing for an edit to have changed) costs `abide` five
    /// haskell keystrokes: those tokens are in the tree, so an offset is a leaf
    /// boundary. And refusing a zero-width terminal the walk volunteers in front
    /// of the recorded token - swift's `_implicit_semi` at 13,246 where the parse
    /// read `public` at 13,249 - hides the case where the *bytes* now produce
    /// one, which is the case the walk exists to catch. The walk cannot tell a
    /// slate artefact from a changed byte, and every narrowing of it is a guess
    /// about which it is looking at.
    ///
    /// See `research/keystroke/RESULT-3-slate.md`. What would settle it is
    /// `offer`'s own slate, and that needs the stack: `shiftable` follows folds
    /// down the one that is standing, and nothing is mounted here yet.
    fn alight(x: *Gather, b: *const Bough, bytes: []const u8) !?u32 {
        const gr = x.graft orelse return null;
        if (gr.firm == 0 or b.rings.items.len == 0) {
            assay.trace(.weave, "alight: none - firm={d} rings={d}\n", .{ gr.firm, b.rings.items.len });
            return null;
        }
        // A resume that believes a snapshot because it exists: no `firm`, no
        // re-lex, just the newest stack there is. The control for both checks.
        if (gr.trusting) {
            const last: u32 = @intCast(b.rings.items.len - 1);
            return if (x.fits(b.rings.items[last])) last else null;
        }

        var i = b.before(gr.firm) orelse {
            assay.trace(.weave, "alight: no ring at or below firm={d} of {d} rings (first at {d})\n", .{
                gr.firm, b.rings.items.len, b.rings.items[0].at,
            });
            return null;
        };
        // Which of the three questions turned each candidate away. A resume
        // that does not happen is indistinguishable in the cost line from one
        // that happened and saved nothing, and the three want different
        // repairs: `seam` is the old tiling having no boundary here, `fits` is
        // a watermark past the tree on offer, `holds` is the stretch re-lexing
        // differently. Counted rather than printed per candidate because
        // `tries` is four and the interesting number is which one is always
        // the answer.
        var unseamed: u32 = 0;
        var unfit: u32 = 0;
        var unheld: u32 = 0;
        var tries: u32 = 4;
        while (tries > 0) : (tries -= 1) {
            const at = b.rings.items[i].at;
            if (!gr.seamed(at)) {
                unseamed += 1;
            } else if (!x.fits(b.rings.items[i])) {
                unfit += 1;
            } else if (!try x.holds(b, i, bytes)) {
                unheld += 1;
            } else return i;
            if (i == 0) break;
            i -= 1;
        }
        assay.trace(.weave, "alight: declined - firm={d} unseamed={d} unfit={d} unheld={d} lowest={d}\n", .{
            gr.firm, unseamed, unfit, unheld, b.rings.items[i].at,
        });
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
            r.roots <= old.roots.len and
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
        // The probe borrows the loop's own extras list, and it is a question
        // rather than a move, so it leaves nothing in it. `nextKeeping`
        // appends, and this walks tens of tokens: whatever stood in front of
        // the last one it read would otherwise still be sitting there when the
        // first real `stow` runs, and get minted a second time as leaves at
        // offsets this parse has already accounted for. That is a duplicated
        // leading comment in the tree, and it does not need the resume to
        // succeed - a *declined* ring falls through to `ground`, which starts
        // a whole cold parse on top of the residue. Round 21.
        defer x.keep.clearRetainingCapacity();
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
                        assay.trace(.weave, "holds: ring {d} at {d} wanted {s} {d}..{d} got {s} {d}..{d} from state {d}\n", .{
                            i,                        at,
                            x.gr.nameOf(want.symbol), want.start,
                            want.end(),               x.gr.nameOf(got.symbol),
                            got.start,                got.end(),
                            state,
                        });
                        return false;
                    }
                    at = got.end();
                },
                else => |no| {
                    assay.trace(.weave, "holds: ring {d} at {d} wanted {s} {d}..{d} got {s} from state {d}\n", .{
                        i,          at,         x.gr.nameOf(want.symbol),
                        want.start, want.end(), @tagName(no),
                        state,
                    });
                    return false;
                },
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
        // What the break already closed over. These are roots of the tree this
        // resume is continuing, not of the prefix it is standing on, so they
        // are adopted rather than re-derived - the same move as the nodes above
        // and sound for the same reason: they were raised out of bytes below
        // the resume that the edit did not touch. Their marks were spent into
        // those nodes by the parse that made them, so blanks here say nothing
        // and change nothing, exactly as for the kids.
        try x.roots.ref.appendSlice(x.gpa, old.roots[0..r.roots]);
        if (x.forking) try x.roots.mark.appendNTimes(x.gpa, .{}, r.roots);
        x.mends = r.mends;
        x.skipped = r.skipped;
        // The sites behind the resume are the old parse's, and they are still
        // true of the bytes below it - the same adoption as the roots above,
        // sound for the same reason. Restored rather than re-derived because
        // this resume will never visit those bytes to derive them again, and a
        // scar list one mend short of `mends` is a list nobody can trust.
        std.debug.assert(r.mends <= old.scars.len);
        try x.scars.appendSlice(x.gpa, old.scars[0..r.mends]);
        if (r.mends > 0) x.why = old.stop;

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
        // A ring standing above a break used to be declined here whenever the
        // grammar could fork, over java returning a `program` with its leading
        // `(block_comment)` twice at edit 215 of seed 0x20575EED0F110003. The
        // decline is gone, and the negative result is the part worth keeping:
        // the duplication was never the ring's. `holds` left the extras of its
        // last probe token sitting in `x.keep`, and the first `stow` after it
        // minted them a second time - so the failing edit resumed nothing and
        // lifted nothing, and no ring-past-a-mend machinery ran in it at all.
        // Taking rings past mends only made the probe run more often, which is
        // why the two looked like one defect. With the probe cleaning up after
        // itself the same stream is green under `.whole`, 75 of its resumes
        // stand over a hole, and `Bough.verify` finds no ring in it carrying a
        // node twice.
        //
        // So there is nothing here to narrow to "did a fork stand between this
        // ring and the mend below it". `x.forking` was standing in for a
        // defect one function away. Round 21.
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
            .roots = @intCast(x.roots.ref.items.len),
            .mends = x.mends,
            .skipped = x.skipped,
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
            if (v.beats(best)) best = v;
        }
        return best;
    }

    /// One line per fork, under `JOINTS_TRACE=quire`: which limb the reading
    /// in hand kept, which one it left standing beside it, and where.
    ///
    /// `rifts`, `denied` and `merges` say how *often* the parse split. None of
    /// them can say whether the tree that came back is the one the split was
    /// for, and that is the only question a wrong-limb defect asks. Verilog's
    /// cost the corpus a full afternoon of bisecting three-line modules against
    /// `joints state`, because the cell that chose was invisible from both
    /// ends: the table prints two actions and the tree prints one shape, with
    /// nothing in between saying which action produced it.
    fn said(
        x: *const Gather,
        what: []const u8,
        state: u32,
        tok: Token,
        rank: u32,
        keep: press.Action,
        cast: press.Action,
    ) void {
        if (!assay.lit(.quire)) return;
        assay.trace(.quire, "{s}: state {d} on {s} at {d} rank {d} - keeps {f}, casts {f}\n", .{
            what,
            state,
            x.gr.nameOf(tok.symbol),
            tok.start,
            rank,
            Limb{ .gr = x.gr, .act = keep },
            Limb{ .gr = x.gr, .act = cast },
        });
    }

    /// Every reading still standing descends from one orphaned speculation.
    /// Named apart from `said` because there is no pair of actions to print:
    /// the whole content is that nothing the table chose is left to disagree.
    fn orphaned(x: *const Gather, tok: Token) void {
        if (!assay.lit(.quire)) return;
        var who: u32 = sole;
        for (x.next.items) |v| who = v.from;
        assay.trace(.quire, "orphaned: every reading from #{d} at {d} on {s}\n", .{
            who,
            tok.start,
            x.gr.nameOf(tok.symbol),
        });
    }

    fn finish(x: *Gather, why: Stop) !Quire {
        // A fork that never collapsed still has a survivor - the reading whose
        // tree this is - so the trail gets its moves rather than nothing. The
        // alternative is forfeiting a whole file's tiling over a conflict that
        // was still open when the bytes ran out.
        if (x.spun > 0 and x.live.items.len > 0) try x.weld(x.first().seg);
        if (x.forking) try x.bind();
        const roots = try x.gpa.dupe(quire.Ref, x.roots.ref.items);
        errdefer x.gpa.free(roots);
        const scars = try x.gpa.dupe(quire.Scar, x.scars.items);
        errdefer x.gpa.free(scars);
        const nodes = try x.nodes.toOwnedSlice(x.gpa);
        errdefer x.gpa.free(nodes);
        // The chain is borrowed until here and owned after: `seal` parked it on
        // the gather, which does not outlive the answer. Duped from wherever the
        // reported stop points rather than from `x.wall`, because a resumed
        // parse adopts the previous one's stop and that chain is the old quire's.
        var stop = why;
        if (stop == .unexpected) if (stop.unexpected.folded) |f| {
            stop.unexpected.folded = try x.gpa.dupe(quire.Fold, f);
        };
        errdefer if (stop == .unexpected) if (stop.unexpected.folded) |f| x.gpa.free(f);
        return .{
            .gpa = x.gpa,
            .gr = x.gr,
            .nodes = nodes,
            .kids = try x.kids.toOwnedSlice(x.gpa),
            .roots = roots,
            .stop = stop,
            .mends = x.mends,
            .skipped = x.skipped,
            .supplied = x.supplies,
            .spurned = x.spurned,
            .scars = scars,
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
    ///
    /// Asked at the offset the narrowed attempt failed at rather than at the
    /// parse's own, because those are not the same byte: the scanner passes
    /// over the layout between them, and a wide slate handed the earlier offset
    /// lets whichever terminal reaches furthest name the layout instead of the
    /// token that is really there. Naming the wrong byte is how a sharper
    /// verdict becomes a worse one.
    fn blame(x: *Gather, bytes: []const u8, at: u32) ?Token {
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
            switch (x.scanner.next(bytes, at, &x.expected)) {
                .token => |tok| return tok,
                else => {},
            }
        }

        // Named, not lexed. This slate is every terminal the grammar has, which
        // is a set no state asked for, so the longest member of it is a fact
        // about the grammar rather than about `at` - see `Scanner.spot`.
        return switch (x.scanner.spot(bytes, at)) {
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
    fn shiftable(x: *const Gather, top: u32, sym: press.Symbol) bool {
        var a: Ahead = .on(x, top);
        // A fork is a yes without looking: one branch reaching a shift is
        // enough to make the terminal real. So is a walk that gave up - see
        // `climb`.
        return switch (a.take(sym)) {
            .stops => false,
            .reads, .done, .unsure => true,
        };
    }

    /// Whether supplying `give` here would let `want` be read.
    ///
    /// The insertion hypothesis, asked of the table and nothing else: run the
    /// folds `give` forces, shift it, and from there run the folds `want`
    /// forces and see whether a shift is on the other side of *those*. Two legs
    /// of the same walk, over one stack neither of them touches.
    ///
    /// The second leg is the whole rule. A terminal that is merely legal here
    /// is not evidence of anything - most states admit several - and supplying
    /// one on that basis is the parse guessing. A terminal that makes **the
    /// token the file actually holds** readable again is the grammar saying
    /// what is missing, and it is also the termination proof: the supply is
    /// always followed immediately by a real shift, so the offset advances and
    /// no position can be supplied into twice.
    ///
    /// ## The clause that is not here, and the measurement that removed it
    ///
    /// This walk used to carry a third demand: that folds run on **both** legs,
    /// which is the table's way of saying the supply closes something already
    /// standing rather than opening something new. The argument was that a
    /// terminal shifting straight out of the standing state is one the state
    /// was merely willing to admit, so writing it manufactures a construct -
    /// and c did exactly that, supplying a `{` in front of a file's last `}`
    /// to build a compound statement neither byte is inside.
    ///
    /// It is a good story and the corpus refuted it. Over thirty grammars under
    /// `--mend=keep`, against the same pinned oracle: with the clause, `square`
    /// moves **+0** and the parse supplies ten terminals; without it, it moves
    /// **+3,124**. Half the clause is worse than either whole - requiring the
    /// fold on the first leg only costs **4,995** `square`, because verilog's
    /// 48,339 deletions become 15,953 when every supply lands and stay 48,339
    /// when only some of them do. (Those three are one sweep on the tree of
    /// the day; the clause has not been re-measured since. The corpus figure
    /// for *this* rule, re-pinned on `83cf2f249d8b` with both arms in one run,
    /// is **+2,592** `square`, **-5,308** `crooked`, **-2,540** built.)
    ///
    /// That last number is the finding, and it is why no cleverer clause was
    /// substituted here. What a supply is worth on this corpus is not whether
    /// its node is right - it is whether the parse stays synchronised, and a
    /// parse that resynchronises at some walls and not others follows a worse
    /// trajectory than one that never tries. Repairs are not independently
    /// scorable, so a rule admitting a *subset* has to earn that subset by
    /// measurement rather than by argument.
    ///
    /// The openers this admits **do** cost, and the charge is live: on tree
    /// `83cf2f249d8b`, both arms of one sweep, c pays **396** `square` and cpp
    /// **134** for exactly the `{`-before-the-last-`}` case above. It went away
    /// for about a day when a press change from another lane stopped both
    /// grammars refusing under `keep` at all - no refusal, no supply, no charge
    /// - and it came back when that stopped being true. Believing it gone was
    /// the flattering reading and it did not survive a re-pin.
    ///
    /// So this clause is the wrong answer for the reason measured above, and
    /// the case it was aimed at is a **standing** defect rather than a
    /// hypothetical. It is most of the headline: swift gains 1,172 `square` on
    /// the twelve grammars this was aimed at, c and cpp give back 530 of it,
    /// and the twelve net **+642**. What is owed is a *ranking* rule that can
    /// prefer a closer over an opener when both are unique - not this clause,
    /// which refuses the openers by refusing nearly every supply. `spurned` is
    /// where the rest of that brief is.
    ///
    /// Every uncertainty is a no, which is the opposite of `shiftable`'s
    /// default and deliberately so. A declared fork means `absorb` would carry
    /// two readings and this walk followed one; a full overlay or a spent
    /// budget means the walk stopped early. Either way the answer would be a
    /// guess, and the cost of a wrong yes here is a node over bytes the author
    /// never wrote that way.
    ///
    /// **Three states, not two, and the third is why this returns an enum.**
    /// Every non-`yes` is still a no at the call site - the paragraph above is
    /// unchanged and no repair decision moved. But a caller that folds `no`
    /// and `cannot tell` together before recording anything can never afterwards
    /// say which it had, and `supply`'s `none` is precisely a claim that every
    /// literal was a *table* no. A spent budget masquerading as that claim is
    /// the residual `residue.py` could not see into.
    fn follows(x: *const Gather, top: u32, give: press.Symbol, want: press.Symbol) Ahead.Says {
        var a: Ahead = .on(x, top);
        const to = switch (a.take(give)) {
            .reads => |s| s,
            // Accepting is a table fact: there is no `want` after the end.
            .done, .stops => return .no,
            .unsure => return .from(a.hazy),
        };
        if (!a.push(to)) return .climbed;
        return switch (a.take(want)) {
            .reads, .done => .yes,
            .stops => .no,
            .unsure => .from(a.hazy),
        };
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
    /// Keep the chain in hand for a stop being built, where the tokens after it
    /// cannot reach it.
    ///
    /// Null once a stop is already remembered, because that earlier one is what
    /// the parse will report and this one is about to be recovered from and
    /// discarded. So the test is not an optimisation: sealing every refusal
    /// would leave the *last* one's folds under the *first* one's stop, which is
    /// a chain that describes a different token and would attribute a wall to a
    /// cell no part of it ever stood in.
    fn seal(x: *Gather) !?[]const quire.Fold {
        if (x.why != null) return null;
        x.wall.clearRetainingCapacity();
        try x.wall.appendSlice(x.gpa, x.folded.items);
        return x.wall.items;
    }

    fn absorb(x: *Gather, tok: Token) !Moved {
        // Per token, not per parse: the chain describes how *this* token reached
        // the state that refused it, and a token that shifts leaves no wall to
        // explain. Both loops below clear through here, including the `alone`
        // fast path, so neither can inherit the previous token's folds.
        x.folded.clearRetainingCapacity();
        if (!x.forking) return x.alone(tok);
        x.work.clearRetainingCapacity();
        x.next.clearRetainingCapacity();
        for (x.live.items) |v| try x.work.append(x.gpa, .{
            .top = v.top,
            .rank = v.rank,
            .seg = v.seg,
            .heft = v.heft,
            .from = v.from,
        });
        x.lone = x.work.items.len == 1 and !x.grafted;

        var i: usize = 0;
        while (i < x.work.items.len) : (i += 1) {
            // A reading an authored side ordered second, whose caster this same
            // token then refuted. Ordering the pair was the whole of what the
            // author said; it was never a claim that the reading they ordered
            // first is unusable and this one is the answer. Letting it stand
            // alone promotes it to exactly that, and — because a reading
            // survived — suppresses the mend that would otherwise rebuild the
            // span. Verilog's `parameter [31:0] P = …` inside a parameter port
            // list is the case: `list_of_param_assignments` carries
            // `prec.left(0)`, the comma folds, the fold is refuted on that same
            // comma, and the surviving cast read shifts into a state whose
            // entire slate is `simple_identifier` and `\` — so the next
            // keyword is lexed as a name. Casters are always processed before
            // the readings they cast, so this is settled by the time it is
            // asked.
            // An orphan is a `sided` speculation whose caster this same token
            // refuted. Identity is minted here rather than at the split,
            // because at the split the caster's fate is not yet known.
            if (x.work.items[i].cast_by) |by| if (x.work.items[by].dead) {
                if (x.work.items[i].from == sole) {
                    x.work.items[i].from = x.orphans;
                    x.orphans += 1;
                }
            };
            const from = x.work.items[i].from;
            var top = x.work.items[i].top;
            const rank = x.work.items[i].rank;
            var heft = x.work.items[i].heft;
            var forced = x.work.items[i].act;
            x.pen = x.work.items[i].seg;
            while (true) {
                const state = x.perches.items[top].state;
                const act = forced orelse take: {
                    // The conflict is looked up before the budget is consulted,
                    // so a cap that binds can say so. The other order cannot
                    // tell "no author declared a choice here" from "one did and
                    // there was no room for it", and those are the two halves of
                    // whether `crowd` is a live limit or a dead knob.
                    // A cell may have dropped more than one reading, so this is
                    // a loop and not an `if`: each rival gets its own strand,
                    // and the budget is re-consulted per rival rather than per
                    // cell, so a wide ambiguity spends the cap the same way two
                    // narrow ones would.
                    if (x.forking) for (x.forks.at(state, tok.symbol), 1..) |split, born| {
                        const other = split.other;
                        if (x.next.items.len + x.work.items.len - i < crowd and
                            x.spun < skeins)
                        {
                            x.said("split", state, tok, rank, x.t.at(state, tok.symbol), other);
                            // Both readings get a strand before either writes
                            // another move: the one in hand keeps its history
                            // and the new one is handed a copy, because up to
                            // this cell they are the same derivation.
                            if (x.pen == sole) {
                                x.pen = try x.strand(sole);
                                x.work.items[i].seg = x.pen;
                            }
                            try x.work.append(x.gpa, .{
                                .top = top,
                                .rank = rank + @as(u32, @intCast(born)),
                                .seg = try x.strand(x.pen),
                                // The two readings are one derivation up to
                                // this cell, so they start level and only the
                                // folds each takes from here can part them.
                                .heft = heft,
                                .act = other,
                                .cast_by = if (split.sided) @intCast(i) else null,
                            });
                            // The perch just handed to the new reading has to
                            // still be there when its turn comes, so nothing
                            // may be taken back from here on.
                            x.lone = false;
                            x.grafted = true;
                            x.rifts += 1;
                        } else {
                            x.said("denied", state, tok, rank, x.t.at(state, tok.symbol), other);
                            x.denied += 1;
                        }
                    };
                    break :take x.t.at(state, tok.symbol);
                };
                forced = null;
                switch (act.kind) {
                    .err => {
                        x.said("refuted", state, tok, rank, act, act);
                        // Refuted. Only the table's own reading is worth
                        // reporting from, and only if it is the one that died.
                        if (rank == 0) {
                            x.refused = state;
                            x.spent = top;
                        }
                        x.work.items[i].dead = true;
                        break;
                    },
                    .shift => {
                        // The only sound place to offer a lift. Every fold this
                        // lookahead calls for has run, `state` is the state the
                        // shift would happen from, and `x.lone` says one reading
                        // stands on a stack that is still a stack. Nothing was
                        // folded early to arrive here, because these are
                        // absorb's own folds - which is the whole reason the
                        // offer moved in from the driver.
                        if (x.lone) {
                            if (try x.lift(top, state, tok)) |grown| {
                                x.pen = sole;
                                x.live.items[0] = .{ .top = grown, .rank = rank, .heft = heft, .from = from };
                                return .lifted;
                            }
                        } else if (x.graft) |gr| {
                            gr.asked += 1;
                            gr.turned_fork += 1;
                        }
                        try x.next.append(x.gpa, .{
                            .top = try x.perch(top, act.value, tok),
                            .rank = rank,
                            .seg = x.pen,
                            .heft = heft,
                            .from = from,
                        });
                        break;
                    },
                    .reduce => {
                        // The whole of what upstream's stack rank does, in one
                        // add: the children's ranks are already in this total
                        // and the parent re-counts them, so the net move is the
                        // folded production's own declaration. See
                        // `Reading.beats`.
                        heft += x.gr.productions[act.value].dynamic;
                        // Only rank 0, on the same principle `x.refused` is: a
                        // stack that took the losing side of a conflict explains
                        // the file worse than the one that did not, and a chain
                        // mixing both explains nothing.
                        if (rank == 0) try x.folded.append(x.gpa, .{ .state = state, .prod = act.value });
                        top = try x.fold(top, act.value) orelse {
                            if (rank == 0) {
                                x.refused = state;
                                x.spent = top;
                            }
                            x.work.items[i].dead = true;
                            break;
                        };
                    },
                    // Accept is only in the end column, which `absorb` is never
                    // called with; treat it as "nothing further to shift".
                    .accept => {
                        try x.next.append(x.gpa, .{
                            .top = top,
                            .rank = rank,
                            .seg = x.pen,
                            .heft = heft,
                            .from = from,
                        });
                        break;
                    },
                }
            }
        }
        x.pen = sole;
        // The moment the hypothesis becomes the authority. Every reading still
        // standing descends from a `sided` speculation whose caster this token
        // refuted, so the slate the next scanner call is handed is one no
        // reading the table chose had any part in. Traced rather than acted
        // on: whether that is the defect depends on what confirms it later.
        // The moment a speculation becomes the authority. Every reading still
        // standing descends from a `sided` cast whose caster this same token
        // refused, so the slate handed to the next scanner call is one no
        // reading the table chose had any part in. Traced and not acted on:
        // whether that is the defect turns on what confirms it afterwards,
        // and this is the last point at which the question can still be put.
        if (x.next.items.len > 0) {
            for (x.next.items) |v| {
                if (v.from == sole) break;
            } else x.orphaned(tok);
        }
        if (x.next.items.len == 0) return .refused;
        x.collapse();
        x.live.clearRetainingCapacity();
        try x.live.appendSlice(x.gpa, x.next.items);
        if (x.grafted and x.live.items.len == 1) try x.roost();
        return .took;
    }

    /// Keep one of each reading that survived the token, and drop the copies.
    ///
    /// Two declared conflicts can each be a real choice and still fold back to
    /// the same states, and once they have there is nothing left to choose: see
    /// `twinned`. Carrying both anyway is what makes the reading count double
    /// per construct instead of returning to one, and the cost is not the memory
    /// - it is that `absorb` declines to fork once `crowd` readings are standing,
    /// so a *later* conflict that really does need two readings is answered by
    /// the table alone. verilog's port list is the worked example: three
    /// consecutive typed ports fill the budget with eight copies of one
    /// derivation, and the untyped port that follows then never gets the fork
    /// that would have read its identifier as the port's name.
    ///
    /// `Reading.beats` picks, which is the tie-break `first` already applies at
    /// the end of the parse - so the tree this yields is the tree the parse would
    /// have handed back had every copy survived to the last byte, and the
    /// collapse only decides it sooner. That is a property of the two keys
    /// agreeing and not of either one, so the three sites move together or the
    /// sentence stops being true.
    ///
    /// That last sentence was tested rather than trusted, on 2026-08-06, and it
    /// holds: **declining the merge outright for differing-rank twins hands back
    /// the same trees.** The verilog witness table is byte-identical either way,
    /// because `first` reaches the same tie-break at the last byte. What it is
    /// not is free - keeping both costs **57,627 bytes** over five grammars
    /// (kotlin +24,393, julia +17,820, elixir +7,737, swift +5,102, verilog
    /// +2,550), because the extra readings fill `crowd` and the later forks that
    /// mattered are then denied. So this merge is load-bearing rather than an
    /// optimisation, and it is the *tie-break* and not the merge that decides a
    /// limb.
    ///
    /// Flipping that tie-break to keep the *higher* rank was measured too, and
    /// it is a coin toss that lands slightly worse: two more verilog witness
    /// rows seat correctly and verilog describes 846 more nodes, against
    /// **+677 bytes** of corpus damage (elixir +583, verilog +94) and 160 bytes
    /// of a php row that was 100% square against tree-sitter. Both arms are
    /// pinned either side with identical folio shas.
    /// `research/joinery/verilog/RESULT-5-merge.md` has both boards, and the
    /// stale-baseline mistake that first read this as a win.
    ///
    /// Both of those arms flipped or removed a comparison over *rank*, which is
    /// the parse loop's own bookkeeping - so both were coin tosses, and both
    /// landed like one. What was missing is a key the grammar wrote:
    /// `prec.dynamic`, summed over the fold, which upstream orders its stack
    /// versions by and which nothing here read until `Reading.heft`. It leads
    /// the comparison and rank breaks its ties, so a grammar that declared no
    /// dynamic rank gets the arm measured above and nothing else.
    /// `research/joinery/limb/` has that board.
    ///
    /// A key the grammar wrote is no use to a grammar that wrote none, and two
    /// of the three grammars holding the corpus's ambiguity declare zero
    /// `prec.dynamic`: all 2,708 of verilog's merges and all 536 of haskell's
    /// read `heft 0 and heft 0`, so rank decides them, and rank at a merge is
    /// which reading was born first.
    /// `research/joinery/arity/RESULT-2-reach.md` priced what that costs -
    /// verilog's 891 entered wide cells opened +1,808 forks and every one
    /// died, +1,674 of them merged away one step later. A third rung was built
    /// for that hole and declined on measurement: see `Reading.beats` and
    /// `research/joinery/arity/RESULT-3-structure.md`. The information is not
    /// at the merge to be read.
    ///
    /// Quadratic in the readings standing, which `crowd` bounds at eight, and
    /// skipped outright for the one reading that is the common case.
    fn collapse(x: *Gather) void {
        if (x.next.items.len < 2) return;
        var kept: usize = 0;
        each: for (x.next.items) |v| {
            for (x.next.items[0..kept]) |*k| {
                if (!x.twinned(v.top, k.top)) continue;
                // Neither authored key separates these two. `heft` is the
                // one number the grammar wrote for this comparison and it
                // tied; `rank` is birth order and it tied as well, which means
                // the fork was cast and folded back inside one token and the
                // limbs are the same age. So the pick was being made by
                // position in `next` - the driver's own enqueue order, a
                // property of neither reading - and it always kept the
                // incumbent, which is the action the table would have taken
                // had it never forked at all.
                //
                // Keeping the challenger is the other face of the same coin,
                // and it is the one that pays: it hands elixir's `do` to the
                // enclosing call instead of to the inner call's argument list.
                // Both faces were measured over the whole board, because the
                // control arm *is* the other face -
                // `research/joinery/elixir/RESULT-2-do-block.md`.
                //
                // This is not the third rung `Reading.beats` declines. That
                // rung reordered readings wherever `heft` alone tied; this
                // fires only where `heft` and `rank` are both equal, a case
                // `beats` resolves with `<` and therefore never separates.
                const tied = v.heft == k.heft and v.rank == k.rank;
                const won = if (v.beats(k.*) or tied) v else k.*;
                assay.trace(.quire, "merged: rank {d} heft {d} and rank {d} heft {d} stand on the same states; rank {d} heft {d} keeps the nodes\n", .{
                    k.rank, k.heft, v.rank, v.heft, won.rank, won.heft,
                });
                k.* = won;
                x.merges += 1;
                continue :each;
            }
            x.next.items[kept] = v;
            kept += 1;
        }
        x.next.shrinkRetainingCapacity(kept);
    }

    /// The same move over a grammar whose tables cannot fork, where there is
    /// one reading and there can never be a second.
    ///
    /// Not an optimisation of the loop above so much as the absence of it: no
    /// worklist, because nothing can be added to one; no rank, because there
    /// is nothing to be more speculative than; no set of survivors, because
    /// the survivor is the reading. What is left is the textbook LR drive,
    /// which is what json runs and what it ran before any of this existed.
    inline fn alone(x: *Gather, tok: Token) !Moved {
        var top = x.live.items[0].top;
        while (true) {
            const state = x.perches.items[top].state;
            const act = x.t.at(state, tok.symbol);
            switch (act.kind) {
                .err => {
                    x.refused = state;
                    x.spent = top;
                    return .refused;
                },
                .shift => {
                    // Same offer as the forking loop makes, at the same moment:
                    // folds done, about to shift, one reading. Here there can
                    // never be a second, so there is no condition to check.
                    if (try x.lift(top, state, tok)) |grown| {
                        x.live.items[0].top = grown;
                        return .lifted;
                    }
                    top = try x.perch(top, act.value, tok);
                },
                // Accept is only in the end column, which `absorb` is never
                // called with; treat it as "nothing further to shift".
                .accept => {},
                .reduce => {
                    // One reading, so it is the table's own by construction and
                    // the `rank == 0` test the forking loop makes is already
                    // answered here.
                    try x.folded.append(x.gpa, .{ .state = state, .prod = act.value });
                    top = try x.fold(top, act.value) orelse {
                        // A fold the table names but the stack cannot make is
                        // a refusal too, and `unwind` needs a perch that is
                        // still standing to report it from.
                        x.refused = state;
                        x.spent = top;
                        return .refused;
                    };
                    continue;
                },
            }
            x.live.items[0].top = top;
            return .took;
        }
    }

    /// Take a whole subtree from the previous parse instead of reading the
    /// bytes under it. A new stack top means the offset moved and this token
    /// was never absorbed at all.
    ///
    /// Called from inside the absorb loops, at the shift, and nowhere else.
    /// It used to be offered from the driver, which meant it had to run the
    /// lookahead's folds itself to find the state a shift would happen from -
    /// and a fold run out there, before the loop that owns the worklist, is
    /// unsound on any grammar that can fork. Four sharper and sharper
    /// predicates were refused by the fuzz before the A/B that settled it:
    /// with every candidate declined, so no graft ever ran, java still
    /// diverged from a cold parse on one edit. No predicate over a corrupt
    /// stack can be right, so the folds moved rather than the question.
    ///
    /// The refusals are all cheap and all silent, because a lift is an
    /// optimisation and a declined one costs an ordinary parse: no graft, a
    /// fork standing, an offset the old parse did not read from this state, no
    /// node beginning there, a symbol this state has no goto for. Only the
    /// last of those is about the grammar, and it is the table saying the
    /// old derivation is not one this parse could have made - which is the
    /// answer, not an error.
    fn lift(x: *Gather, top: u32, here: u32, tok: Token) !?u32 {
        const gr = x.graft orelse return null;
        if (!gr.lifting) return null;
        gr.asked += 1;
        if (!gr.aligned(tok.start, here)) {
            gr.turned_align += 1;
            return null;
        }
        gr.probes += 1;

        const chain = try gr.stoop(tok.start);
        gr.offered += chain.len;
        // Why the walk passed over everything wider than what it takes, counted
        // before the take so a probe that lifts nothing still reports. The
        // chain is ordered widest first, so every candidate seen before the one
        // taken *is* a wider one that something refused.
        var missed: u64 = 0;
        var by_shape: u64 = 0;
        var by_goto: u64 = 0;
        var by_break: u64 = 0;
        if (chain.len > 0) gr.widest += gr.old.nodes[chain[0]].len;
        for (chain) |ref| {
            const sym = gr.liftable(ref) orelse {
                missed += 1;
                by_shape += 1;
                continue;
            };
            const wide = gr.old.nodes[ref].len;
            // One token's worth is a copy with extra steps, and the chain is
            // ordered widest first, so nothing further in is worth trying.
            if (wide <= tok.len) {
                missed += 1;
                by_break += 1;
                break;
            }
            const to = x.c.goto(here, sym) orelse {
                missed += 1;
                by_goto += 1;
                continue;
            };

            try x.stow(null);
            const root = try x.transcribe(gr, ref);
            const own = x.borne.len();
            try x.bear(&x.borne, root, .{});
            const end = tok.start + wide;
            const grown = try x.push(top, .{
                .state = to,
                .own = own,
                .owns = 1,
                .lead = x.lead,
                .leads = x.leads,
                .start = tok.start,
                .end = end,
            });
            try x.scribe(.{
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
            gr.passed += missed;
            gr.passed_shape += by_shape;
            gr.passed_goto += by_goto;
            gr.passed_break += by_break;
            gr.taken += wide;
            return grown;
        }
        return null;
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
        x.roosts += 1;
        try x.weld(x.live.items[0].seg);
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
            // An extra was read on the way to the token in hand, so it cannot
            // begin behind where the parse is standing. The one thing that
            // ever put one there was a ring probe leaving its own scan in this
            // list; the tripwire is here rather than in `holds` because this
            // is where the damage is done - a leaf minted over bytes the parse
            // has already accounted for - and any future borrower of `keep`
            // trips it too. Free in release. Round 21.
            std.debug.assert(e.start >= x.at);
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

    /// Record one move where the current reading's moves go.
    ///
    /// While no fork stands this is the trail, unchanged. While one does, it is
    /// the reading's own strand, because the trail is a single sequence and two
    /// readings writing into it produce a record neither of them made - the
    /// thing `torn` used to forfeit the whole file over.
    inline fn scribe(x: *Gather, mv: Move) !void {
        if (x.pen != sole) return x.strands.items[x.pen].append(x.gpa, mv);
        if (x.trail) |tr| try tr.append(x.gpa, mv);
    }

    /// Hand a reading a strand of its own, copying what it has written so far -
    /// which is its parent's, since up to the split the two readings *are* the
    /// same derivation and share every move.
    fn strand(x: *Gather, from: u32) !u32 {
        const at = x.spun;
        if (at == x.strands.items.len) try x.strands.append(x.gpa, .empty);
        x.spun += 1;
        x.strands.items[at].clearRetainingCapacity();
        if (from != sole) {
            try x.strands.items[at].appendSlice(x.gpa, x.strands.items[from].items);
        }
        return at;
    }

    /// The fork is over: the survivor's moves are the file's moves, so they
    /// join the trail and the strands go back in the pool.
    fn weld(x: *Gather, seg: u32) !void {
        if (seg != sole) if (x.trail) |tr| {
            try tr.appendSlice(x.gpa, x.strands.items[seg].items);
        };
        x.unstrand();
    }

    fn unstrand(x: *Gather) void {
        for (x.strands.items[0..x.spun]) |*st| st.clearRetainingCapacity();
        x.spun = 0;
        x.pen = sole;
    }

    /// A token's own perch, standing on the run `stow` laid down for it.
    inline fn perch(x: *Gather, top: u32, to: u32, tok: Token) !u32 {
        try x.stow(tok);
        try x.scribe(.{ .read = .{
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

    /// Whether two readings are standing on the same states, top to ground.
    ///
    /// Every decision either reading can still make is a function of its state
    /// chain and the bytes left: `offer` and `shiftable` read states, `fold`
    /// reads the depth and the goto, and the table is indexed by state. So two
    /// readings with the same chain are not two readings - they are one
    /// derivation the loop is carrying twice, and they will agree on every token
    /// to the end of the file. What differs is the tree already built beneath
    /// them, and `first` was going to hand the finished parse the lowest-ranked
    /// of them anyway.
    ///
    /// Cheap because a fork *shares* the perches below where it came apart, so
    /// two readings that fold back to the same shape meet at a common perch
    /// index and the walk stops there. The cost is the divergent suffix - a few
    /// perches, the ones minted since the conflict - and never the stack.
    fn twinned(x: *const Gather, a: u32, b: u32) bool {
        if (a == b) return true;
        if (x.stand.items[a].depth != x.stand.items[b].depth) return false;
        var p = a;
        var q = b;
        while (p != q) {
            if (x.perches.items[p].state != x.perches.items[q].state) return false;
            p = x.stand.items[p].down;
            q = x.stand.items[q].down;
        }
        return true;
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
        try x.scribe(.{ .fold = .{ .under = under, .prod = prod } });
        return try x.reduce(p, mine, at, to);
    }

    /// One reduction's worth of tree: apply the recipe to each child, then
    /// either mint a node for the left-hand side or leave the children to
    /// splice into whatever reduces next.
    fn reduce(x: *Gather, p: press.Production, mine: []const Perch, under: u32, to: u32) !u32 {
        // The span, from the perches that actually consumed something. A
        // nullable child sits at the offset the previous token ended, and
        // letting it set the start would pull the node back over the
        // whitespace in front of the first real one.
        //
        // Unless it is a **terminal** that consumed nothing and has a node
        // anyway - a supplied one, or a visible zero-width one the scanner
        // handed back. That is a different animal from a nullable child: an
        // absence derived nothing and the span rule is right to ignore it, but
        // a zero-width token is a place the parse stood and a node a reader
        // can hold, and a node the span does not reach is a child outside its
        // parent - the `loose` half of what `--sound` counts, and a real one:
        // supplying a `{` in front of a file's last `}` built the compound
        // statement `[41, 42)` around a `{` at `[40, 40)` until this clause
        // existed.
        //
        // Terminal, not merely node-owning, and the difference is 3,561
        // `square`: a nullable *nonterminal* can own extras - a comment read
        // in front of it and claimed by nobody else - so keying on `owns`
        // alone lets a swallowed comment set an edge and pulls thirty
        // grammars' nodes over their own whitespace.
        var start = x.at;
        var end = x.at;
        var seen = false;
        for (p.rhs, mine) |sym, *f| {
            if (f.start == f.end and !(f.owns > 0 and sym < x.gr.terminal_count)) continue;
            // `end` starts at `x.at`, which is ahead of every child, so the
            // first one assigns and the rest may only widen. Folding that into
            // one `@max` costs 3,561 `square` corpus-wide, because it is the
            // seed rather than a child that wins the comparison.
            end = if (seen) @max(end, f.end) else f.end;
            if (!seen) start = f.start;
            seen = true;
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

        // The span again, and this time over the children that were actually
        // minted rather than over the symbols the recipe named. The loop at
        // the top can only see the right-hand side; Rule 2 hands this node
        // extras that no symbol on that side covers - a comment sitting in the
        // next perch's lead rides in as a child of the node being made, and
        // nothing between here and there reconciles the two. `pair` in
        // `b = "2"  # c` was minted [8, 15) holding `comment [17, 20)`: a child
        // wholly outside its parent, which is precisely the `loose` that
        // `Quire.survey` counts, and the one row on the board that read
        // `100% standing, 0 damage` while not handing back a tree.
        //
        // Over child *nodes*, not over perches, and that is the whole
        // difference from the rule the loop above had to refuse: a nullable
        // child's perch carries a bare offset sitting ahead of the whitespace,
        // which is a position and not a span, and letting one set an edge
        // costs thirty grammars their own leading trivia. A minted node's
        // start is a span. Widening to cover the children it already holds
        // gains 29 `square` and drops 16 `crooked` and 13 `soft` corpus-wide,
        // and moves no other row.
        for (x.born.ref.items) |c| {
            const kid = x.nodes.items[c];
            const from, const upto = .{ kid.start, kid.start + kid.len };
            if (seen) {
                start = @min(start, from);
                end = @max(end, upto);
            } else {
                start, end, seen = .{ from, upto, true };
            }
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
    /// it spliced. Where several readings accept, `Reading.beats` picks: the
    /// author's `prec.dynamic` over each derivation first, and the least
    /// speculative reading where the author ranked nothing - so preferring the
    /// table's own answer still makes forking a strict addition rather than a
    /// change of mind about files that already parsed, for every grammar that
    /// declared no dynamic rank to spend.
    ///
    /// The end column folds like any other, so its reductions carry their own
    /// declarations too. A reading that accepts after three folds is three
    /// productions richer than the perch it started this function on, and
    /// comparing it on the total it *arrived* with would be scoring two
    /// derivations at different points.
    fn close(x: *Gather) !struct { top: u32, ok: bool } {
        x.lone = x.live.items.len == 1 and !x.grafted;
        var won: ?Reading = null;
        var tried: ?Reading = null;
        for (x.live.items) |v| {
            var top = v.top;
            var heft = v.heft;
            const ok = done: while (true) {
                const act = x.t.at(x.perches.items[top].state, x.t.end);
                switch (act.kind) {
                    .accept => break :done true,
                    .reduce => {
                        heft += x.gr.productions[act.value].dynamic;
                        top = try x.fold(top, act.value) orelse break :done false;
                    },
                    .err, .shift => break :done false,
                }
            };
            const r: Reading = .{ .top = top, .rank = v.rank, .heft = heft };
            if (ok) {
                if (won == null or r.beats(won.?)) won = r;
            } else if (tried == null or r.beats(tried.?)) tried = r;
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

        // Where the chain stops being a derivation. `supply` writes a terminal
        // in on the strength of clause 2, which justifies it for exactly one
        // token: the refused token shifts next, and what happens after that is
        // the parse's answer about whether the omission was real. A fold taking
        // the ghost as a child is that answer arriving - and a second refusal
        // reaching here first is the answer never arriving. Publishing from
        // there up asserts a construct whose closing terminal nobody wrote, and
        // at the top of a forest it asserts a node covering no bytes and
        // standing under no parent, which is not the derivation of anything.
        //
        // Only the `own` runs are withheld. A perch's `lead` is the extras read
        // in front of it - comments the file really holds - and those are the
        // forest's whatever the parse decided about the structure over them.
        var held: usize = x.spine.items.len;
        for (x.spine.items, 0..) |f, i| {
            if (x.unproven(f)) {
                held = i;
                break;
            }
        }
        for (x.spine.items, 0..) |f, i| {
            try x.carry(&x.roots, x.borne.at(f.lead, f.leads));
            if (i < held) try x.carry(&x.roots, x.borne.at(f.own, f.owns));
        }
        try x.carry(&x.roots, x.borne.at(x.lead, x.leads));
    }

    /// Whether this perch is a supply no fold ever took as a child.
    ///
    /// `plant` pushes a zero-width perch holding one anonymous node, and
    /// clause 1 is what makes reading that back off the perch exact rather than
    /// a guess: a supply is *always* anonymous, and the terminals that are
    /// legitimately zero-width - swift's `_implicit_semi`, haskell's layout
    /// hand - are named and the scanner's to produce. So a zero-width perch
    /// holding an anonymous node is one this runtime wrote in, and one still
    /// standing on the chain is one nothing has reduced over.
    ///
    /// Measured rather than assumed: across the corpus the arm without the
    /// second move builds **no** zero-width node at all, and under `--mend=keep`
    /// every one of verilog's 59 supplies is inside a parent by the time the
    /// parse ends. Under `--mend=fell` 127 are not.
    fn unproven(x: *const Gather, f: Perch) bool {
        if (f.start != f.end or f.owns == 0) return false;
        for (x.borne.at(f.own, f.owns).ref) |r| {
            const kind = x.nodes.items[r].kind;
            if (!kind.renamed and x.gr.shapeOf(kind.index) != .named) return true;
        }
        return false;
    }
};
