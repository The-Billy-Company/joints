//! Whose wall is this? The question asked of the table rather than of a person.
//!
//! A parse stops somewhere. Four subsystems could be why: the scanner had no
//! terminal for the bytes, the table has no cell for the token, the resolution
//! took a cell the grammar wanted, or the parse loop was standing in a state
//! where the token was never legal. Every round of grammar work spends its first
//! hour deciding which, and the deciding has been done by hand - by someone who
//! reconstructs an argument about lookahead unions from memory, and who gets it
//! wrong in the direction of whichever subsystem they own.
//!
//! It does not need to be done by hand. Three of the four answers are *decidable
//! from the artifact*, by arguments about the whole automaton rather than by
//! sampling it:
//!
//!   1. **A byte nothing can tokenize is nobody's table's fault.** The scanner is
//!      driven by a state's action row, so a stray byte means *this row* offered
//!      no terminal that matched. Re-lex the same offset with the row's
//!      restriction lifted: if a terminal matches there, the bytes were lexable
//!      and the wall is about which cell a state holds. If nothing matches with
//!      the whole slate admitted, no table could have been consulted at all -
//!      the terminal that would cover those bytes is one the grammar hands to an
//!      external scanner we cannot run.
//!
//!   2. **An empty cell is empty under every split.** LALR lookaheads are
//!      supersets of the canonical LR(1) ones - merging states unions their
//!      contexts, and a union only ever adds. So a token absent from a merged
//!      row is absent from every canonical row the merge stood in for, and
//!      splitting the state cannot put it back. `err` here is `err` in LR(1),
//!      and the press has nothing to answer for.
//!
//!   3. **A read is only ever lost to a fold.** The one way this press removes a
//!      reading is `settle` preferring a reduce over a shift. So if no state
//!      anywhere folds on the token, no state anywhere dropped a read of it, and
//!      every state refusing it never had it to lose. This is the argument that
//!      retires a wall in one number: cpp's 112 states refusing `number_literal`
//!      after `(`, against 0 states folding on it.
//!
//!   4. **A terminal nothing reads was never in a parse to lose.** Fell out of
//!      writing 3 down, and it splits in two on one more scan. If no production
//!      spells it either, the front end dropped it and the grammar was imported
//!      wrongly. If a production *does* spell it, the front end kept it and the
//!      automaton has nowhere to put it - which is what a **structural extra**
//!      is: an extra is reachable from `$start` through nothing, by definition,
//!      so an extra owning real productions puts its terminals in the grammar
//!      and in no action row at all. Nine of them exist across the corpus and
//!      they are the named cause of every `at byte 0` stray in it.
//!
//!   5. **A token the scanner cannot make is not the table's to refuse.** The
//!      four above all read the table, and a classifier that reads only the
//!      table can only ever answer in the table's vocabulary - which is how six
//!      grammars whose walls are the *scanner's* came back `weave`. The
//!      scanner knows something no table does: which externals it has no stand-in
//!      for. Handed that list, two more arguments decide, and both are scans:
//!
//!        * **The wall's own row admits one.** The state was waiting for a token
//!          only the scanner could have produced, and it cannot. latex's 537 is
//!          the clean case - it accepts exactly one terminal of 409, and that
//!          terminal is `_trivia_raw_env_verbatim`.
//!        * **A blind terminal is a declared extra.** An extra is reachable from
//!          `$start` through nothing (argument 4's own observation), so it sits
//!          in no action row anywhere and no per-state test can ever see it.
//!          Unlexable and unadmitted, its bytes fall to whatever else matches -
//!          *everywhere in the file, before any state is consulted*. So no table
//!          fact about the wall is a proof while it holds: the token the row
//!          refused is not the token the file contains. scala's `block_comment`
//!          and ocaml's `comment` are this, and it is why scala's wall state 126
//!          looks perfectly innocent - four terminals, none of them a comment.
//!
//!      Both are caller-supplied evidence, exactly as `Lexable` is, and for the
//!      same reason: press cannot ask the scanner, and an answer nobody asked
//!      for must not print like one somebody did.
//!
//!      **They are not the same strength, and treating them alike misfiled three
//!      grammars.** `awaited` is a fact about the wall's own row, so it is about
//!      this wall. `blindExtra` is an existential over the grammar - *some*
//!      blind terminal is *some* declared extra - with nothing tying it to this
//!      wall, this file, or these bytes. It fires on a terminal the source may
//!      not contain a byte of: `ledger.js` and `ledger.ts` hold no `<!--`, so
//!      `html_comment` mis-lexed nothing in either, and `list.ml` holds no
//!      line-number directive. Run first, that existential outranked the
//!      path-anchored proof about javascript's `)` in 269 - the very case the
//!      `declared_fork` branch below was written for - and printed a loop's
//!      limit as the scanner's fault.
//!
//!      So it runs *after* the path, on the rule this file already applies to
//!      cells: a cell on the path is a proof and the same cell anywhere else is
//!      not. Blindness reads the same way. Absent path evidence the argument
//!      still stands, because a defeater with nothing to defeat is still the
//!      best available reading - but it is `proven = false`, the same epistemic
//!      shape as `dropped_elsewhere` and marked the same way. A second loop
//!      falsifies it for free where a reader wants one: a product loop that read
//!      the file **whole** was blind to nothing the file contained.
//!
//! What is left after those is press's, and it is not a judgement either:
//! `settle` records the cells a merge invented as `Frayed`, so the damage has an
//! address. If one sits on the path the refused token actually drove - the wall's
//! own cell, or any state the token folded through on its way there - the wall is
//! downstream of that cell and this says which one, with `lalr.Floor.Cause`
//! saying whether another arrival partition would remove it.
//!
//! The strength of the answer is part of the answer. A caller that cannot supply
//! the fold chain (the CLI prints a verdict, not a path) gets `proven = false`
//! when the table drops the terminal *somewhere* but nothing places the wall
//! downstream of it. That is a suspicion about a table, and it reads differently
//! from a proof about a parse. Conflating the two is how the census misrouted c
//! for three rounds.
//!
//! Nothing here allocates or walks the collection: it is four scans of the frayed
//! list, one of an action column, and - only when nothing reads the terminal -
//! one of the productions, so it costs less than printing the answer.

const std = @import("std");
const g = @import("copy/grammar.zig");
const lalr = @import("lalr.zig");
const settle = @import("quarrel/settle.zig");

/// One reduction the refused token drove, and the state it was taken in. A
/// structural mirror of `kernel/walk/drive.zig`'s `Fold`: press is the build
/// side and cannot import the run time, and the two fields are the whole type.
pub const Fold = struct { state: u32, prod: u32 };

/// Where a parse stopped, in the only terms a table can answer about.
pub const Wall = union(enum) {
    whole,
    /// Every byte lexed and no root ever closed.
    unclosed,
    /// No terminal the state offered begins at `at`. `lexable` is argument 1: the
    /// only thing separating a byte nothing can tokenize from a byte this state
    /// would not hear, and the answer is only a proof if somebody asked.
    ///
    /// `state` is optional because the verdict does not print it - the walk knows
    /// which state it stood in and reports only the offset. Absent, an invented
    /// cell *at* the wall cannot be checked and only the table-wide arguments run.
    stray: struct { at: u32, state: ?u32 = null, lexable: Lexable = .unasked },
    /// The token lexed and the row had nothing for it. `folded` is the chain of
    /// reductions the token drove before the table gave up, `null` when the
    /// caller has a verdict but not a path.
    refused: struct { terminal: u32, state: u32, folded: ?[]const Fold = null },

    /// A wall out of the words the CLI already prints for it, so a census is the
    /// parser's own verdict handed back to the press rather than a second
    /// vocabulary someone has to keep in step:
    ///
    ///     joints: f.c: unexpected , at 1354 in state 803, 2 roots
    ///     joints: x.rb: stray byte at 357, 4 roots
    ///
    /// A `stray` needs one fact the verdict does not carry - whether anything in
    /// the grammar lexes there at all - so `lexable` carries what the unrestricted
    /// scanner found, and whether anyone ran it.
    ///
    /// Keyword-directed rather than positional: the prefix is a path, and a
    /// parser that counts colons breaks on the first file with one in its name.
    pub fn read(gr: *const g.Grammar, line: []const u8, lexable: Lexable) ?Wall {
        if (std.mem.indexOf(u8, line, "unexpected ")) |i| {
            const tail = line[i + "unexpected ".len ..];
            const at = std.mem.indexOf(u8, tail, " at ") orelse return null;
            const in = std.mem.indexOf(u8, tail, " in state ") orelse return null;
            const terminal = terminalOf(gr, tail[0..at]) orelse return null;
            const state = std.fmt.parseInt(u32, upto(tail[in + " in state ".len ..], ','), 10) catch
                return null;
            return .{ .refused = .{ .terminal = terminal, .state = state } };
        }
        if (std.mem.indexOf(u8, line, "stray byte at ")) |i| {
            const at = std.fmt.parseInt(
                u32,
                upto(line[i + "stray byte at ".len ..], ','),
                10,
            ) catch return null;
            return .{ .stray = .{ .at = at, .lexable = lexable } };
        }
        if (std.mem.indexOf(u8, line, "truncated") != null) return .unclosed;
        if (std.mem.indexOf(u8, line, "accepted") != null) return .whole;
        return null;
    }
};

/// What the scanner finds at a stray offset with the action row's restriction
/// lifted. `unasked` is a third state on purpose: a census that did not look, or
/// looked only at the literals, has not proved the bytes unlexable - and an
/// unproven `lexer` must not print like a proven one.
pub const Lexable = union(enum) { unasked, nothing, terminal: u32 };

/// The longest literal terminal standing at `at`, if one does. Argument 1 in the
/// half a table can answer on its own: matching a regex is the run time's job and
/// needs the engine, but a literal is a string compare, and a hit is a *proof*
/// that the bytes are lexable - which is the whole question for a stray on `,` or
/// `"` in a grammar whose row simply did not offer it.
///
/// A miss proves nothing (a pattern terminal may still match), so the caller
/// answers `unasked` rather than `nothing`. Extras are skipped: a terminal the
/// lexer passes over between tokens never appears in an action row, so finding
/// one here would route a wall to `nowhere` on the strength of a comment.
pub fn literalAt(gr: *const g.Grammar, bytes: []const u8, at: u32) ?u32 {
    if (at >= bytes.len) return null;
    var best: ?u32 = null;
    var longest: usize = 0;
    for (gr.patterns[0..gr.terminal_count], 0..) |pat, sym| {
        const lit = switch (pat orelse continue) {
            .literal => |s| s,
            else => continue,
        };
        if (lit.len <= longest or !std.mem.startsWith(u8, bytes[at..], lit)) continue;
        if (std.mem.indexOfScalar(g.Symbol, gr.extras, @intCast(sym)) != null) continue;
        best = @intCast(sym);
        longest = lit.len;
    }
    return best;
}

/// The terminal of that name, or null. Terminals only: a nonterminal cannot be a
/// wall, and answering with one would put a column index past the table's width.
pub fn terminalOf(gr: *const g.Grammar, name: []const u8) ?u32 {
    for (gr.names[0..gr.terminal_count], 0..) |it, sym| {
        if (std.mem.eql(u8, it, name)) return @intCast(sym);
    }
    return null;
}

fn upto(s: []const u8, sentinel: u8) []const u8 {
    return s[0 .. std.mem.indexOfScalar(u8, s, sentinel) orelse s.len];
}

/// Who has to change something for this wall to move.
pub const Owner = enum {
    /// Nothing stopped.
    whole,
    /// The scanner: no terminal covers these bytes, usually because the grammar
    /// hands them to an external scanner that is not implemented here.
    lexer,
    /// The press: a cell a merge invented sits on the path the token drove.
    press,
    /// The parse loop: every cell on the path is what the grammar means, and the
    /// state the token came to rest in refuses it under every split of it.
    ///
    /// "Came to rest in", not "was standing in": the wall's state is where the
    /// folds ran out, which is many reduces downstream of where the reading
    /// stood. That is exactly why the verdict is taken over the whole chain and
    /// not over the wall cell - see `onPath`.
    weave,
    /// The front end: the token is readable in no state at all, so no parse
    /// could ever have used it. A grammar imported wrongly, not a table decided
    /// wrongly - and press's, since press is the front end.
    nowhere,
    /// Nobody. The cell the merge invented is one the *author declared*, so the
    /// table kept both readings and `Forks` offers the one it did not take; the
    /// only thing that refused is a single-stack loop that cannot walk a fork.
    /// Distinct from `press` because there is nothing to fix in the table, and
    /// distinct from `weave` because the recovery loop is not at fault either -
    /// it takes the fork and reads the file whole.
    oracle,
    /// Input ended first. Nothing refused anything.
    unclosed,
};

/// The argument, not the label. Every one of these is a sentence about the whole
/// automaton that can be checked; `why` spells it out.
pub const Because = enum {
    accepted,
    input_ended,
    /// Argument 1, negative half: the whole terminal slate matches nothing here.
    nothing_lexes,
    /// Argument 5, first half: the wall state's row admits a terminal the
    /// grammar hands to an external scanner this lexer has no stand-in for.
    awaited_external,
    /// Argument 5, second half: a terminal the scanner cannot produce is a
    /// declared extra, so it is in no action row anywhere and any bytes of it
    /// in this file were mis-lexed. Never proven - the grammar says the
    /// terminal is unreachable, and nothing here says the file holds one.
    blind_extra,
    /// The wall's own cell is one a merge invented.
    dropped_here,
    /// A state the token folded through holds a cell a merge invented.
    dropped_upstream,
    /// A merge damaged this terminal somewhere, and nothing places this wall
    /// downstream of it. The only unproven answer.
    dropped_elsewhere,
    /// Argument 3: no state folds on this terminal, so no state lost a read of
    /// it.
    never_folded,
    /// Argument 2: the cell is empty, and a merged row is a superset of every
    /// canonical row it stands for.
    empty_under_every_split,
    /// Argument 2 asked and answered the other way: the cell is *not* empty, so
    /// nothing about splitting is at issue. The row admits this terminal and the
    /// narrow offer did not produce it, which is the scanner's side of the same
    /// byte. Only a stray can reach this - a refused token's wall cell is empty
    /// by the parse loop's own control flow - and it is why the emptiness has to
    /// be measured rather than assumed.
    offer_withheld,
    /// No state reads this terminal, and no production spells it either.
    never_read,
    /// No state reads it, but a rule does spell it - and that rule is a
    /// declared extra with structure, which nothing in the automaton hosts.
    extra_unhosted,
    /// No state reads it, a rule spells it, and that rule is not an extra: it
    /// is simply unreachable from the start symbol.
    rule_unhosted,
    /// The cell on the path is invented *and* declared, so the reading it did
    /// not take is still offered as a fork. Nothing was lost, so this is not a
    /// dropped fold however much it looks like one from the harm alone.
    declared_fork,

    pub fn why(b: Because) []const u8 {
        return switch (b) {
            .accepted => "accepted",
            .input_ended => "input ended before the start symbol closed; nothing refused a token",
            .nothing_lexes => "no terminal in the grammar matches here even with the row's " ++
                "restriction lifted, so no table was consulted",
            .awaited_external => "this state admits a terminal the grammar hands to an external " ++
                "scanner we cannot run, so a token no lexer here can make was in its way; " ++
                "the stand-in says which half of the row admitted it, because a shift is a " ++
                "token this state would have consumed and a lookahead is one it only tolerates",
            .blind_extra => "a terminal the scanner cannot produce is a declared extra, so it is " ++
                "in no action row at all and any of its bytes in this file were read as " ++
                "something else; nothing here says the file holds one, so this is the best " ++
                "reading rather than a proof",
            .dropped_here => "this cell is one a state merge invented, and the read it removed " ++
                "was legal after some of the paths that arrive here",
            .dropped_upstream => "the token folded through a cell a state merge invented; the " ++
                "refusal here is that fold's downstream",
            .declared_fork => "the invented cell on the path is one the author declared, so the " ++
                "reading the table declined is still offered as a fork; a loop that can " ++
                "hold two reads past it and a single-stack loop cannot",
            .dropped_elsewhere => "a merge damaged this terminal's cell elsewhere, and no fold " ++
                "chain was supplied to say whether this wall is downstream of it",
            .never_folded => "no state anywhere folds on this terminal, and a read is only ever " ++
                "lost to a fold, so no state ever had it to lose",
            .empty_under_every_split => "the cell is empty, and a merged lookahead is a superset " ++
                "of every canonical one it stands for, so it is empty under every split",
            .offer_withheld => "this state's row admits this terminal and the byte matches its " ++
                "pattern, so the table would have shifted a token the narrow offer never " ++
                "produced; nothing here is a merge's doing",
            .never_read => "no state reads this terminal and no production spells it, so " ++
                "nothing could ever have read it",
            .extra_unhosted => "the only rule spelling this terminal is a declared extra with " ++
                "structure, and an extra is reachable from no state, so nothing hosts it",
            .rule_unhosted => "a rule spells this terminal and no state reads it, so that rule " ++
                "is unreachable from the start symbol",
        };
    }
};

/// What the table says about one wall, and how strongly.
pub const Finding = struct {
    owner: Owner,
    because: Because,
    /// False only for `dropped_elsewhere`: a suspicion about a table rather than
    /// a proof about a parse.
    proven: bool = true,
    /// The invented cell, when one is on the path.
    cell: ?settle.Frayed = null,
    /// Whether an arrival partition removes that cell. `open` is the only bucket
    /// another press round could reach; see `lalr.Floor`.
    cause: ?lalr.Floor.Cause = null,
    /// The terminal's column, table-wide. `folds == 0` is argument 3 and
    /// `reads == 0` is `never_read`; both are here so a reader can check the
    /// argument rather than take the label.
    reads: u32 = 0,
    folds: u32 = 0,
    /// States that dropped a read of this terminal to a fold a merge invented.
    dropped: u32 = 0,
    /// States where a merge instead picked the wrong *fold* on this terminal, so
    /// the refusal surfaces further along. Together with `dropped` this is all the
    /// merge damage the terminal carries anywhere: at zero, no upstream fold on
    /// this token can be the press's either, which is what makes an unreachable
    /// wall cell a *proof* about the whole path rather than about one cell.
    misfolded: u32 = 0,
    /// The rule that spells a terminal nothing reads, when one does. Set only
    /// for `extra_unhosted` and `rule_unhosted`, and it is the whole difference
    /// between "the front end dropped this" and "the front end kept it and the
    /// automaton has nowhere to put it".
    spelt: ?g.Symbol = null,
    /// The rule whose reading the table declined and `Forks` offers, for a
    /// `declared_fork`. It is the evidence: a fork with a loser still on offer is
    /// a cell that lost nothing.
    lost: ?g.Symbol = null,
    /// The terminal the scanner cannot produce, for argument 5. Named rather
    /// than counted because which one it is *is* the work order: `block_comment`
    /// says write a nesting-comment hand, and no amount of table work will do.
    unlexable: ?g.Symbol = null,
    /// Which half of the wall state's row admitted `unlexable`, and the reason
    /// this field exists at all.
    ///
    /// `awaited` has always computed it - the four-tier ranking is built out of
    /// it - and then dropped it on the floor, while the verdict it fed said the
    /// state "was waiting for" the token. That sentence is true of a shift and
    /// false of a fold, and 59 of the 60 swift states whose stand-in the tier
    /// fix moved were folds. So a reader was told a lexical work order in the
    /// majority case where the honest reading is "this state tolerates that
    /// token on the way somewhere else, and the wall is probably not its".
    ///
    /// Null when no stand-in was found, and never null beside `unlexable`.
    admitted: ?lalr.Half = null,
};

/// The externals a scanner has no stand-in for, or `null` when nobody asked.
///
/// The same three-state discipline `Lexable` uses, and for the same reason: an
/// empty list means "asked, and there are none", which is a proof, where `null`
/// means the caller had no scanner to ask and argument 5 must not run at all.
pub const Blind = ?[]const g.Symbol;

/// Argument 5, first half. Whether the wall's own row admits a terminal the
/// scanner cannot produce.
///
/// Two passes, because "admitted" is not one fact. A **shift** on a blind
/// terminal says the state would have consumed it and advanced; a **fold** says
/// it would have reduced on it as lookahead and then met the refused token
/// again in the next state. So the shift is the terminal the wall was waiting
/// for and the fold is a terminal it merely tolerates, and taking the first of
/// either in declaration order lets order decide which gets named.
///
/// haskell is the exhibit. State 7 of `module Text.Pandoc.Shared` admits twelve
/// folds and two shifts; the shifts are `_cond_qual_dot` and `_cond_tight_dot`,
/// the exact terminals that would have consumed the `.` at 681 the parse
/// refused. One pass named `_cond_layout_semicolon` - a fold, and second in the
/// grammar's `externals` list against the dot's twenty-eighth - which sent a
/// reader to build the layout scanner to fix a wall the dot guard owns.
///
/// It is a **preference and never a filter**: a reduce-only state has no shift
/// to prefer and its answer must not change. haskell's state 186 offers eight
/// lookaheads that are all folds, six of them external, and it still answers.
///
/// **A declared extra is ranked below both, because it discriminates nothing.**
/// An extra is admitted almost everywhere by construction - that is what being
/// an extra means - so learning that this state admits one tells a reader
/// nothing about *this* state, and the name reads as a finding rather than as
/// the background it is. Every swift wall printed `multiline_comment`, including
/// walls that were plainly `_implicit_semi`, and two lanes were sent to the
/// comment scanner by it. So the four tiers, high wins: a discriminating shift,
/// a discriminating fold, then those two again for an extra. Ranking an extra's
/// *shift* below a non-extra's *fold* is deliberate and is the one place this
/// trades against the shift preference above: the fold at least narrows to
/// something this state specifically tolerates, where the extra's shift is true
/// of nearly every state in the automaton.
///
/// Measured over a stride of swift's 3,416 states, the name moves in 60 of the
/// 156 states that answer at all, and `multiline_comment` - which won 60 of them
/// - wins none afterwards. It won **59 of those 60 as a fold and one as a
/// shift**, so a fix that deranked the extra in the shift pass alone would have
/// repaired one case in sixty and reported the win. kotlin and scala do not move
/// at all: their extra is not the lowest-numbered blind external, so order was
/// already answering correctly there by luck.
/// The stand-in and the half that admitted it, because the caller prints both
/// and the half was being recomputed nowhere and asserted anyway.
const Stand = struct { sym: g.Symbol, half: lalr.Half };

fn awaited(t: *const lalr.Tables, gr: *const g.Grammar, state: ?u32, blind: []const g.Symbol) ?Stand {
    const s = state orelse return null;
    var best: ?Stand = null;
    var rank: u3 = 0;
    for (blind) |sym| {
        if (sym >= t.width) continue;
        const half = lalr.Half.of(t.at(s, sym).kind) orelse continue;
        const shifts = half == .shift;
        const spare = std.mem.indexOfScalar(g.Symbol, gr.extras, sym) != null;
        // Strictly greater, so declaration order still breaks a tie within a
        // tier and a row of one kind answers exactly as it did before.
        const grade: u3 = if (spare) (if (shifts) 2 else 1) else (if (shifts) 4 else 3);
        if (grade > rank) best, rank = .{ .{ .sym = sym, .half = half }, grade };
    }
    return best;
}

/// Argument 5, second half. Whether any terminal the scanner cannot produce is
/// a declared extra - unlexable *and* unadmitted, so it can be found no other
/// way than by asking these two lists about each other.
fn blindExtra(gr: *const g.Grammar, blind: []const g.Symbol) ?g.Symbol {
    for (blind) |sym| {
        if (std.mem.indexOfScalar(g.Symbol, gr.extras, sym) != null) return sym;
    }
    return null;
}

/// Who, if anyone, spells a terminal no state reads.
///
/// `reads == 0` says the automaton never offers it; this says whether that is
/// because nothing in the grammar mentions it, or because the only rule that
/// does is one no state can be standing in. A declared extra is the second case
/// by construction - an extra is reachable from `$start` through nothing, which
/// is what makes it an extra - so a *structural* extra's terminals are in the
/// grammar and in no row, and the parse strays at its first comment.
///
/// One scan of the productions, no allocation, and it stops at the first rule
/// found: a terminal spelled by two rules where neither is read is one wall, not
/// two, and the extras are checked first so the answer names the interesting one.
fn spelling(gr: *const g.Grammar, terminal: u32) union(enum) { nobody, extra: g.Symbol, rule: g.Symbol } {
    var any: ?g.Symbol = null;
    for (gr.productions) |p| {
        if (std.mem.indexOfScalar(g.Symbol, p.rhs, @intCast(terminal)) == null) continue;
        if (std.mem.indexOfScalar(g.Symbol, gr.extras, p.lhs) != null) return .{ .extra = p.lhs };
        if (any == null) any = p.lhs;
    }
    return if (any) |lhs| .{ .rule = lhs } else .nobody;
}

/// The classifier. Reads the action column for the terminal and the frayed list;
/// touches nothing else.
pub fn over(t: *const lalr.Tables, gr: *const g.Grammar, wall: Wall, blind: Blind) Finding {
    return switch (wall) {
        .whole => .{ .owner = .whole, .because = .accepted },
        .unclosed => .{ .owner = .unclosed, .because = .input_ended },
        // A stray byte the whole slate cannot match never reached a table. One
        // it can match is a state that would not hear a terminal other states
        // read, which is the same question as a refused token whose fold chain
        // is empty - the scanner refuses before the row is consulted, so there
        // is no path to be downstream of.
        .stray => |s| switch (s.lexable) {
            .terminal => |sym| refused(t, gr, sym, s.state, &.{}, blind),
            .nothing => .{ .owner = .lexer, .because = .nothing_lexes },
            .unasked => .{ .owner = .lexer, .because = .nothing_lexes, .proven = false },
        },
        .refused => |r| refused(t, gr, r.terminal, r.state, r.folded, blind),
    };
}

fn refused(
    t: *const lalr.Tables,
    gr: *const g.Grammar,
    terminal: u32,
    state: ?u32,
    folded: ?[]const Fold,
    blind: Blind,
) Finding {
    var out: Finding = .{ .owner = .weave, .because = .empty_under_every_split };
    for (0..t.action.len / t.width) |at| switch (t.at(@intCast(at), terminal).kind) {
        .shift => out.reads += 1,
        .reduce => out.folds += 1,
        else => {},
    };
    for (t.frayed) |f| {
        if (f.terminal != terminal) continue;
        switch (f.harm) {
            .read_dropped => out.dropped += 1,
            .fold_dropped => out.misfolded += 1,
        }
    }

    // Argument 5's first half, and it runs before every table argument below
    // rather than after them, which is the whole correction. A table argument
    // reasons about *the token the row was handed*; when this state was waiting
    // for a terminal the scanner cannot make, that token is not the one the
    // file holds, so a sentence about splitting the state is true and
    // irrelevant. Nine of eleven census rows read `weave` because the
    // classifier could only reach for the table and the table always has
    // something to say.
    //
    // The state's own row is what earns it the position: a specific fact about
    // this wall beats a grammar-wide one, and it names a terminal the reader
    // can go look at. Argument 5's *second* half has neither property, so it
    // waits below the path - see `blindExtra`.
    if (blind) |cannot| if (awaited(t, gr, state, cannot)) |stand| {
        out.owner = .lexer;
        out.because = .awaited_external;
        out.unlexable = stand.sym;
        out.admitted = stand.half;
        return out;
    };

    // The path first, nearest end first: the wall's own cell, then every state
    // the token folded through. A cell on the path is a proof; the same cell
    // anywhere else is not.
    if (onPath(t, terminal, state, folded)) |hit| {
        out.cell = hit;
        out.cause = t.cause(hit);
        // An invented cell the author *declared* did not lose a reading: the
        // table answers with one side and `Forks` hands the other to any loop
        // that can hold two. So the harm alone cannot name the owner - a
        // `fold_dropped` cell reads identically whether the loser was dropped or
        // offered, and only the conflict's class tells them apart. javascript's
        // `)` in 269 is the whole reason this branch exists: `array` over
        // `array_pattern`, declared, offered, and quire reads the file whole
        // through it while the single-stack oracle stops. Calling that a press
        // defect attributed a loop's limit to the table.
        if (declared(t, gr, hit)) |lost| {
            out.owner = .oracle;
            out.because = .declared_fork;
            out.lost = lost;
            return out;
        }
        out.owner = .press;
        out.because = if (state != null and hit.state == state.?)
            .dropped_here
        else
            .dropped_upstream;
        return out;
    }

    // Argument 5's second half, and it belongs here rather than above the path
    // because it is not about this wall. It is an existential over the grammar
    // - some blind terminal is some declared extra - and it says nothing about
    // whether the file holds a byte of that terminal. Run above the path it
    // overrode javascript's `)` in 269, the case `declared` below exists for,
    // on the strength of an `html_comment` no ledger in the corpus contains.
    //
    // Unproven for exactly the reason `dropped_elsewhere` is: the damage is
    // real somewhere and nothing places this wall downstream of it.
    if (blind) |cannot| if (blindExtra(gr, cannot)) |sym| {
        out.owner = .lexer;
        out.because = .blind_extra;
        out.unlexable = sym;
        out.proven = false;
        return out;
    };

    // With the path known, an intact path is a proof. Without it, the table's own
    // damage on this terminal decides: none anywhere and no fold this token drove
    // could have been the press's either, so the wall cell being unreachable
    // settles the whole path. Any damage at all, and it cannot.
    if (folded == null and out.dropped + out.misfolded > 0) {
        out.owner = .press;
        out.because = .dropped_elsewhere;
        out.proven = false;
        return out;
    }
    if (out.reads == 0) {
        // Nothing offers it. Two very different reasons, and calling both the
        // front end's misfiled three grammars: a terminal no rule spells was
        // dropped on the way in, where one a *structural extra* spells was kept
        // and has nowhere to be read, because an extra is hosted by no state.
        switch (spelling(gr, terminal)) {
            .nobody => {
                out.owner = .nowhere;
                out.because = .never_read;
            },
            .extra => |lhs| {
                out.owner = .press;
                out.because = .extra_unhosted;
                out.spelt = lhs;
            },
            .rule => |lhs| {
                out.owner = .press;
                out.because = .rule_unhosted;
                out.spelt = lhs;
            },
        }
    } else if (out.folds == 0) {
        out.because = .never_folded;
    }

    // Measured, not assumed, and this is the only claim here that is about a
    // *cell* rather than about a column or a path. The two walls a parse can
    // raise arrive as the same shape: a token the loop could not shift ends on a
    // cell that is empty by `absorb`'s own control flow, so asking the table
    // there only confirms the loop; a stray byte re-lexed with the row's
    // restriction lifted names a terminal the state may perfectly well admit,
    // and there the parse died in the scanner while this sentence talked about
    // splitting. Same verdict either way until somebody asks, which is what
    // makes it worth two lines: a diagnostic that cannot print "no" is not a
    // measurement.
    if (out.because == .empty_under_every_split) {
        if (state) |s| if (t.at(s, terminal).kind != .err) {
            out.owner = .lexer;
            out.because = .offer_withheld;
        };
    }
    return out;
}

/// The invented cell nearest the wall on the path the token drove, if any. Both
/// harms count: a `read_dropped` cell the chain stood in took a reading away, and
/// a `fold_dropped` one sent the parse down a production the token cannot finish.
/// Which of the two it was is `Frayed.harm`, and the caller wants to know.
fn onPath(t: *const lalr.Tables, terminal: u32, state: ?u32, folded: ?[]const Fold) ?settle.Frayed {
    if (state) |s| if (t.frayedAt(s, terminal)) |f| return f;
    const chain = folded orelse return null;
    var i = chain.len;
    while (i > 0) {
        i -= 1;
        if (t.frayedAt(chain[i].state, terminal)) |f| return f;
    }
    return null;
}

/// The rule a declared cell decided against, when this cell is one the author
/// declared. `null` for a residual or repetition contest, which is the case where
/// the loser really is gone.
///
/// Read off `Tables.conflicts` rather than recomputed, because `class` is the
/// press's own attribution of the cell against the grammar's `conflicts` block,
/// and a second opinion here could disagree with the table it is describing.
fn declared(t: *const lalr.Tables, gr: *const g.Grammar, cell: settle.Frayed) ?g.Symbol {
    for (t.conflicts) |k| {
        if (k.state != cell.state or k.terminal != cell.terminal) continue;
        if (k.class != .declared) continue;
        if (k.other.kind != .reduce) continue;
        if (k.other.value >= gr.productions.len) return null;
        return gr.productions[k.other.value].lhs;
    }
    return null;
}

/// One row of a census: `<owner> <because>`, plus whichever counts carry the
/// argument. Written rather than returned as a string so nothing here allocates.
pub fn write(f: Finding, gr: *const g.Grammar, wall: Wall, w: *std.Io.Writer) !void {
    try w.print("{s}", .{@tagName(f.owner)});
    if (!f.proven) try w.writeAll("?");
    switch (wall) {
        .refused => |r| {
            try w.print(" on {s} in state {d}", .{ gr.nameOf(r.terminal), r.state });
            // The wall's state is where the folds ran out, not where the reading
            // stood, and a row that prints only the first invites the second to
            // be read into it - a wall attributed to a state seven reduces from
            // the cell that decided it. The chain's first entry *is* the standing
            // state, so say both and the distance between them.
            if (r.folded) |chain| if (chain.len > 0 and chain[0].state != r.state) {
                try w.print(", {d} fold(s) on from {d}", .{ chain.len, chain[0].state });
            };
        },
        .stray => |s| switch (s.lexable) {
            .terminal => |sym| try w.print(" on {s} at byte {d}", .{ gr.nameOf(sym), s.at }),
            .nothing => try w.print(" at byte {d}", .{s.at}),
            .unasked => try w.print(" at byte {d} (unlexed)", .{s.at}),
        },
        else => {},
    }
    if (f.cell) |c| try w.print(
        " [state {d}, {s}, {s}]",
        .{ c.state, @tagName(c.harm), @tagName(f.cause.?) },
    );
    // The half is printed inside the bracket rather than left to the sentence,
    // because the bracket is the part a reader copies into a work order. "no
    // stand-in for X" with nothing after it reads as "this state wanted X",
    // and for a lookahead that is the wrong instruction: the state tolerates X
    // on its way somewhere else, and the wall is very likely not X's.
    if (f.unlexable) |sym| {
        try w.print(" [no stand-in for {s}", .{gr.nameOf(sym)});
        if (f.admitted) |half| try w.print(", admitted by {s}", .{half.word()});
        try w.writeAll("]");
    }
    if (f.spelt) |lhs| try w.print(" [spelt only by {s}]", .{gr.nameOf(lhs)});
    if (f.lost) |lhs| try w.print(" [fork still offers {s}]", .{gr.nameOf(lhs)});
    switch (f.because) {
        .never_folded,
        .empty_under_every_split,
        .never_read,
        .extra_unhosted,
        .rule_unhosted,
        => try w.print(
            " ({d} read, {d} fold, {d} frayed)",
            .{ f.reads, f.folds, f.dropped + f.misfolded },
        ),
        .dropped_elsewhere => try w.print(
            " ({d} dropped, {d} misfolded)",
            .{ f.dropped, f.misfolded },
        ),
        else => {},
    }
    try w.print(": {s}", .{f.because.why()});
}

const testing = std.testing;

/// A table by hand. The classifier reads an action column and a frayed list and
/// nothing else, so a hand-built one is the whole input - and it is the only way
/// to test the buckets a real grammar happens not to be in this week.
const Bench = struct {
    arena: std.heap.ArenaAllocator,
    action: []lalr.Action,
    frayed: std.ArrayList(settle.Frayed) = .empty,
    seams: std.ArrayList(lalr.Seam) = .empty,
    width: u32,

    fn init(states: u32, width: u32) !Bench {
        const action = try testing.allocator.alloc(lalr.Action, states * width);
        @memset(action, lalr.Action.err);
        return .{
            .arena = std.heap.ArenaAllocator.init(testing.allocator),
            .action = action,
            .width = width,
        };
    }

    fn deinit(b: *Bench) void {
        testing.allocator.free(b.action);
        b.frayed.deinit(testing.allocator);
        b.seams.deinit(testing.allocator);
        b.arena.deinit();
    }

    fn put(b: *Bench, state: u32, terminal: u32, act: lalr.Action) void {
        b.action[state * b.width + terminal] = act;
    }

    fn fray(b: *Bench, state: u32, terminal: u32, harm: settle.Frayed.Harm) !void {
        try b.frayed.append(testing.allocator, .{ .state = state, .terminal = terminal, .harm = harm });
    }

    /// A seam that over-permits `terminal` through `arrivals` paths, which is
    /// what makes a frayed cell `open` rather than `alone`.
    fn seam(b: *Bench, state: u32, terminal: u32, arrivals: u32) !void {
        const over_set = try b.arena.allocator().dupe(u32, &.{terminal});
        try b.seams.append(testing.allocator, .{
            .state = state,
            .arrivals = arrivals,
            .over = over_set,
            .stubborn = &.{},
            .lanes = &.{},
        });
    }

    /// Three terminals and the rules that decide which case `spelling` is in.
    /// The classifier reads `productions`, `extras` and `nameOf` and nothing
    /// else, so this is the whole grammar side of its input: terminal 1 is the
    /// one every test asks about, and `spells` says who, if anyone, mentions it.
    /// `extra` wraps terminal 1 in a rule and declares the *rule* an extra,
    /// which is argument 4's shape. `terminal_extra` declares the *terminal*
    /// one, which is how every language spells a comment and is argument 5's.
    /// They read alike in prose and reach `gr.extras` as different symbols, so
    /// a test that means one and builds the other passes for the wrong reason.
    fn slate(spells: enum { nobody, rule, extra, terminal_extra }) !g.Grammar {
        var b = g.Builder.init(testing.allocator);
        defer b.deinit();
        const a = try b.intern("a", "a", .{ .literal = "a" });
        const one = try b.intern("b", "b", .{ .literal = "b" });
        _ = try b.intern("c", "c", .{ .literal = "c" });
        const start = try b.intern("$start", "$start", null);
        const s = try b.intern("S", "S", null);
        const note = try b.intern("note", "note", null);
        try b.addProduction(start, &.{s}, &.{});
        try b.addProduction(s, &.{a}, &.{});
        if (spells == .rule or spells == .extra) try b.addProduction(note, &.{one}, &.{});
        const extras: []const g.Symbol = switch (spells) {
            .extra => &.{note},
            .terminal_extra => &.{one},
            else => &.{},
        };
        return b.finish("t", start, extras, &.{});
    }

    fn tables(b: *const Bench) lalr.Tables {
        return .{
            .arena = std.heap.ArenaAllocator.init(testing.allocator),
            .end = b.width - 1,
            .width = b.width,
            .action = b.action,
            .conflicts = &.{},
            .frayed = b.frayed.items,
            .seams = b.seams.items,
        };
    }
};

test "a byte no terminal matches never reached the table, and not looking is not a proof" {
    var b = try Bench.init(2, 3);
    defer b.deinit();
    var tab = b.tables();
    defer tab.arena.deinit();
    var gr = try Bench.slate(.nobody);
    defer gr.deinit();

    const asked = over(&tab, &gr, .{ .stray = .{ .at = 41, .lexable = .nothing } }, null);
    try testing.expectEqual(Owner.lexer, asked.owner);
    try testing.expectEqual(Because.nothing_lexes, asked.because);
    try testing.expect(asked.proven);

    const not = over(&tab, &gr, .{ .stray = .{ .at = 41 } }, null);
    try testing.expectEqual(Owner.lexer, not.owner);
    try testing.expect(!not.proven);
}

test "a byte that does lex is a cell question, not a lexer one" {
    var b = try Bench.init(3, 3);
    defer b.deinit();
    // Two states read terminal 1; the one the parse stood in does not.
    b.put(1, 1, lalr.Action.shift(2));
    b.put(2, 1, lalr.Action.shift(1));
    var tab = b.tables();
    defer tab.arena.deinit();
    var gr = try Bench.slate(.nobody);
    defer gr.deinit();

    const f = over(&tab, &gr, .{ .stray = .{ .at = 41, .lexable = .{ .terminal = 1 } } }, null);
    try testing.expectEqual(Owner.weave, f.owner);
    // No state folds on it, so argument 3 applies and is the stronger sentence.
    try testing.expectEqual(Because.never_folded, f.because);
    try testing.expectEqual(@as(u32, 2), f.reads);
    try testing.expectEqual(@as(u32, 0), f.folds);
}

test "no state folds the token, so no state dropped a read of it" {
    var b = try Bench.init(4, 3);
    defer b.deinit();
    b.put(1, 1, lalr.Action.shift(2));
    // A fray on a *different* terminal must not be read as this one's.
    try b.fray(1, 2, .read_dropped);
    var tab = b.tables();
    defer tab.arena.deinit();
    var gr = try Bench.slate(.nobody);
    defer gr.deinit();

    const f = over(&tab, &gr, .{ .refused = .{ .terminal = 1, .state = 3, .folded = &.{} } }, null);
    try testing.expectEqual(Owner.weave, f.owner);
    try testing.expectEqual(Because.never_folded, f.because);
    try testing.expectEqual(@as(u32, 0), f.dropped);
}

test "a fold on the token elsewhere leaves the empty cell empty under every split" {
    var b = try Bench.init(4, 3);
    defer b.deinit();
    b.put(1, 1, lalr.Action.shift(2));
    b.put(2, 1, lalr.Action.reduce(7));
    var tab = b.tables();
    defer tab.arena.deinit();
    var gr = try Bench.slate(.nobody);
    defer gr.deinit();

    const f = over(&tab, &gr, .{ .refused = .{ .terminal = 1, .state = 3, .folded = &.{} } }, null);
    try testing.expectEqual(Owner.weave, f.owner);
    try testing.expectEqual(Because.empty_under_every_split, f.because);
    try testing.expectEqual(@as(u32, 1), f.folds);
}

test "the emptiness argument is measured, so it can answer no" {
    // The shape argument 2 cannot describe: the wall state's row *admits* the
    // terminal. Only a stray reaches it, because a refused token's wall cell is
    // empty by the parse loop's own control flow - `absorb` returns false exactly
    // on an empty cell - so the sentence "the cell is empty" is true there
    // whether or not anyone asks. It is not true here, and a diagnostic that
    // cannot print the negative answer is not a measurement.
    var b = try Bench.init(4, 3);
    defer b.deinit();
    b.put(3, 1, lalr.Action.shift(2)); // the wall state itself
    b.put(2, 1, lalr.Action.reduce(7)); // a fold elsewhere, so argument 3 stands down
    var tab = b.tables();
    defer tab.arena.deinit();
    var gr = try Bench.slate(.nobody);
    defer gr.deinit();

    const asked = over(&tab, &gr, .{ .stray = .{
        .at = 41,
        .state = 3,
        .lexable = .{ .terminal = 1 },
    } }, null);
    try testing.expectEqual(Owner.lexer, asked.owner);
    try testing.expectEqual(Because.offer_withheld, asked.because);
    try testing.expect(asked.proven);

    // The same table without the state, which is what the walk's stray verdict
    // carries today: the cell cannot be asked about, so only the table-wide
    // arguments run and the row must not claim a cell fact either way.
    const blind = over(&tab, &gr, .{ .stray = .{ .at = 41, .lexable = .{ .terminal = 1 } } }, null);
    try testing.expectEqual(Because.empty_under_every_split, blind.because);
}

test "a terminal nothing reads splits three ways on who spells it" {
    // The same table every time - nothing shifts terminal 1 anywhere - so the
    // only thing moving is the grammar, which is the point: `reads == 0` is one
    // observation about the automaton and three different defects, and calling
    // all three `nowhere` is what filed rust, julia and lua as the scanner's.
    var b = try Bench.init(4, 3);
    defer b.deinit();
    b.put(2, 1, lalr.Action.reduce(7));
    var tab = b.tables();
    defer tab.arena.deinit();
    const wall: Wall = .{ .refused = .{ .terminal = 1, .state = 3, .folded = &.{} } };

    // Nobody spells it: the front end dropped a terminal on the way in.
    var orphan = try Bench.slate(.nobody);
    defer orphan.deinit();
    const lost = over(&tab, &orphan, wall, null);
    try testing.expectEqual(Owner.nowhere, lost.owner);
    try testing.expectEqual(Because.never_read, lost.because);
    try testing.expectEqual(@as(?g.Symbol, null), lost.spelt);

    // A rule spells it and no state reads it: the rule is unreachable.
    var unreached = try Bench.slate(.rule);
    defer unreached.deinit();
    const stranded = over(&tab, &unreached, wall, null);
    try testing.expectEqual(Owner.press, stranded.owner);
    try testing.expectEqual(Because.rule_unhosted, stranded.because);
    try testing.expectEqualStrings("note", unreached.nameOf(stranded.spelt.?));

    // The same rule, declared an extra: unreachable *by construction*, which is
    // what an extra is, so the wall is a structural extra nothing hosts.
    var extra = try Bench.slate(.extra);
    defer extra.deinit();
    const unhosted = over(&tab, &extra, wall, null);
    try testing.expectEqual(Owner.press, unhosted.owner);
    try testing.expectEqual(Because.extra_unhosted, unhosted.because);
    try testing.expectEqualStrings("note", extra.nameOf(unhosted.spelt.?));
    // Still a proof: both halves of it are scans, not samples.
    try testing.expect(unhosted.proven);
}

test "an invented cell on the fold chain is the press's, and says which cell" {
    var b = try Bench.init(6, 3);
    defer b.deinit();
    b.put(1, 1, lalr.Action.shift(2));
    b.put(4, 1, lalr.Action.reduce(9));
    // State 4 folded on the token a merge let it fold on; the refusal surfaces
    // two states later, in 5, which holds nothing.
    try b.fray(4, 1, .read_dropped);
    try b.seam(4, 1, 3);
    var tab = b.tables();
    defer tab.arena.deinit();
    var gr = try Bench.slate(.nobody);
    defer gr.deinit();

    const chain: []const Fold = &.{.{ .state = 4, .prod = 9 }};
    const f = over(&tab, &gr, .{ .refused = .{ .terminal = 1, .state = 5, .folded = chain } }, null);
    try testing.expectEqual(Owner.press, f.owner);
    try testing.expectEqual(Because.dropped_upstream, f.because);
    try testing.expectEqual(@as(u32, 4), f.cell.?.state);
    // Three arrivals and not stubborn: an arrival partition removes it.
    try testing.expectEqual(lalr.Floor.Cause.open, f.cause.?);
    try testing.expect(f.proven);
}

test "the same cell off the path is a suspicion, and says so" {
    var b = try Bench.init(6, 3);
    defer b.deinit();
    b.put(1, 1, lalr.Action.shift(2));
    b.put(4, 1, lalr.Action.reduce(9));
    try b.fray(4, 1, .read_dropped);
    var tab = b.tables();
    defer tab.arena.deinit();
    var gr = try Bench.slate(.nobody);
    defer gr.deinit();

    // Chain supplied and it does not pass through state 4: proven weave.
    const elsewhere: []const Fold = &.{.{ .state = 2, .prod = 3 }};
    const known = over(&tab, &gr, .{ .refused = .{ .terminal = 1, .state = 5, .folded = elsewhere } }, null);
    try testing.expectEqual(Owner.weave, known.owner);
    try testing.expect(known.proven);

    // No chain at all: press, unproven. The distinction the census needs.
    const blind = over(&tab, &gr, .{ .refused = .{ .terminal = 1, .state = 5 } }, null);
    try testing.expectEqual(Owner.press, blind.owner);
    try testing.expectEqual(Because.dropped_elsewhere, blind.because);
    try testing.expect(!blind.proven);
}

test "a wall reads back out of the words the CLI prints for it" {
    var b = g.Builder.init(testing.allocator);
    defer b.deinit();
    const s = try b.intern("S", "S", null);
    const comma = try b.intern(",", ",", .{ .literal = "," });
    try b.addProduction(s, &.{comma}, &.{});
    var gr = try b.finish("t", s, &.{}, &.{});
    defer gr.deinit();

    // The whole line, path prefix and root count and all.
    const one = Wall.read(&gr, "joints: f.c: unexpected , at 1354 in state 803, 2 roots", .unasked);
    try testing.expectEqual(comma, one.?.refused.terminal);
    try testing.expectEqual(@as(u32, 803), one.?.refused.state);
    try testing.expectEqual(@as(?[]const Fold, null), one.?.refused.folded);

    const two = Wall.read(&gr, "joints: x.rb: stray byte at 357, 4 roots, mended 3", .nothing);
    try testing.expectEqual(@as(u32, 357), two.?.stray.at);
    try testing.expectEqual(Lexable.nothing, two.?.stray.lexable);

    try testing.expectEqual(Wall.whole, Wall.read(&gr, "joints: a.c: accepted, 1 root", .unasked).?);
    try testing.expectEqual(Wall.unclosed, Wall.read(&gr, "joints: a.c: truncated, 3 roots", .unasked).?);

    // A terminal this grammar does not have is not a wall in this grammar, and
    // guessing a column index would read some other terminal's table.
    try testing.expectEqual(
        @as(?Wall, null),
        Wall.read(&gr, "joints: f.c: unexpected ; at 3 in state 4", .unasked),
    );
    try testing.expectEqual(@as(?Wall, null), Wall.read(&gr, "joints: f.c: no source fetched", .unasked));
}

test "a state waiting for a terminal the scanner cannot make is the lexer's" {
    // latex's 537, reduced: a row that admits exactly one terminal, and that
    // terminal is one the grammar hands to an external scanner. Every table
    // argument below still holds - the cell for the token that *did* arrive is
    // empty under every split - and every one of them is beside the point.
    var b = try Bench.init(4, 3);
    defer b.deinit();
    b.put(3, 2, lalr.Action.reduce(5)); // the wall state admits terminal 2
    b.put(1, 1, lalr.Action.shift(2));
    b.put(2, 1, lalr.Action.reduce(7));
    var tab = b.tables();
    defer tab.arena.deinit();
    var gr = try Bench.slate(.nobody);
    defer gr.deinit();
    const wall: Wall = .{ .refused = .{ .terminal = 1, .state = 3, .folded = &.{} } };

    // Nobody asked the scanner: the old answer, and it is about the table.
    const unasked = over(&tab, &gr, wall, null);
    try testing.expectEqual(Owner.weave, unasked.owner);

    // Asked, and terminal 2 is one it cannot make.
    const asked = over(&tab, &gr, wall, &.{2});
    try testing.expectEqual(Owner.lexer, asked.owner);
    try testing.expectEqual(Because.awaited_external, asked.because);
    try testing.expectEqual(@as(?g.Symbol, 2), asked.unlexable);
    try testing.expect(asked.proven);

    // Asked, and the scanner can make everything: back to the table, and the
    // empty list has to answer differently from `null` or it is not evidence.
    const clean = over(&tab, &gr, wall, &.{});
    try testing.expectEqual(Owner.weave, clean.owner);
}

/// The stand-in's symbol alone, for the tests that are about which terminal
/// wins rather than about how it was admitted. Those two questions were one
/// return value until the half started riding along, which is the defect this
/// whole family of instruments had: the half was computed and discarded.
fn standIn(t: *const lalr.Tables, gr: *const g.Grammar, state: ?u32, blind: []const g.Symbol) ?g.Symbol {
    const s = awaited(t, gr, state, blind) orelse return null;
    return s.sym;
}

test "a shift on a blind terminal outranks a fold on one" {
    // haskell state 7's shape. The wall refuses `.`; the row admits two blind
    // terminals - one it would FOLD on and one it would SHIFT on - and the fold
    // is the one declared first. Only the shift would have consumed the refused
    // byte, so naming the fold sends a reader to the wrong scanner.
    var b = try Bench.init(4, 4);
    defer b.deinit();
    b.put(1, 1, lalr.Action.shift(2));
    b.put(2, 1, lalr.Action.reduce(7));
    // State 3 is the wall. Terminal 2 folds here (a lookahead it tolerates),
    // terminal 3 shifts (the one it is waiting for). Declaration order hands
    // `blind` the fold first, exactly as haskell hands over
    // `_cond_layout_semicolon` before `_cond_qual_dot`.
    b.put(3, 2, lalr.Action.reduce(7));
    b.put(3, 3, lalr.Action.shift(1));
    var tab = b.tables();
    defer tab.arena.deinit();
    // Nothing is an extra here, so this test asks only about shift against fold
    // and the ranking below it cannot reach in.
    var gr = try Bench.slate(.nobody);
    defer gr.deinit();

    // The shift wins regardless of the order the blind list arrives in, or the
    // answer is still order deciding and nothing was fixed.
    try testing.expectEqual(@as(?g.Symbol, 3), standIn(&tab, &gr, 3, &.{ 2, 3 }));
    try testing.expectEqual(@as(?g.Symbol, 3), standIn(&tab, &gr, 3, &.{ 3, 2 }));

    // A preference, never a filter: a fold-only row still answers with its
    // fold. This is haskell's state 186 - eight lookaheads, all reduces, six of
    // them external - and it must not go silent.
    try testing.expectEqual(@as(?g.Symbol, 2), standIn(&tab, &gr, 3, &.{2}));

    // And the verdict it feeds is unchanged in owner and in strength; only the
    // terminal named moves.
    const wall: Wall = .{ .refused = .{ .terminal = 1, .state = 3, .folded = &.{} } };
    const found = over(&tab, &gr, wall, &.{ 2, 3 });
    try testing.expectEqual(Owner.lexer, found.owner);
    try testing.expectEqual(Because.awaited_external, found.because);
    try testing.expectEqual(@as(?g.Symbol, 3), found.unlexable);
    try testing.expect(found.proven);

    // The half the ranking decided on reaches the finding, so the printed row
    // can say it. This is the whole of the admission-report repair here: the
    // ranking above has always known whether it picked a shift or a fold, and
    // the verdict it fed said "the state was waiting for this" either way.
    try testing.expectEqual(@as(?lalr.Half, .shift), found.admitted);
    const only_fold = over(&tab, &gr, wall, &.{2});
    try testing.expectEqual(@as(?g.Symbol, 2), only_fold.unlexable);
    try testing.expectEqual(@as(?lalr.Half, .fold), only_fold.admitted);
}

test "a finding that names a stand-in always names the half, and both halves occur" {
    // Two assertions, and the second is why the first is worth having.
    //
    // The first is the invariant: `unlexable` and `admitted` are set together
    // or not at all, so no reader can be handed a terminal name with the half
    // silently missing - which is the state every one of these instruments was
    // in before today.
    //
    // The second is the anti-vacuity. A gate that walks findings and checks
    // "each one names its half" passes perfectly over a population where the
    // half is always `shift`, and then the old sentence - "it was waiting for
    // a token no lexer here can make" - was never wrong and this change bought
    // nothing. So the population is required to contain **both** halves. If a
    // later change makes `awaited` shift-only, this reddens rather than
    // quietly turning the first assertion into a tautology.
    var b = try Bench.init(4, 4);
    defer b.deinit();
    b.put(1, 1, lalr.Action.shift(2));
    b.put(2, 1, lalr.Action.reduce(7));
    b.put(3, 2, lalr.Action.reduce(7)); // a fold on a blind terminal
    b.put(3, 3, lalr.Action.shift(1)); // a shift on a blind terminal
    var tab = b.tables();
    defer tab.arena.deinit();
    var gr = try Bench.slate(.nobody);
    defer gr.deinit();

    const wall: Wall = .{ .refused = .{ .terminal = 1, .state = 3, .folded = &.{} } };
    // Every blind list that can be drawn from the two, plus the empty one and
    // the one nobody asked - so the walk covers "no stand-in" as well.
    const lists = [_][]const g.Symbol{ &.{}, &.{2}, &.{3}, &.{ 2, 3 }, &.{ 3, 2 } };
    var seen_shift = false;
    var seen_fold = false;
    var seen_none = false;
    for (lists) |blind| {
        const f = over(&tab, &gr, wall, blind);
        // The invariant, both ways: neither field may stand without the other.
        try testing.expectEqual(f.unlexable == null, f.admitted == null);
        if (f.admitted) |half| switch (half) {
            .shift => seen_shift = true,
            .fold => seen_fold = true,
        } else seen_none = true;
    }
    try testing.expect(seen_shift);
    try testing.expect(seen_fold);
    try testing.expect(seen_none);
}

test "a declared extra is the last resort of the stand-in scan, not its first hit" {
    // swift's state 1226, reduced to its four cells. The item is
    // `_class_member_declarations -> _type_level_declaration . …`, so the token
    // the wall wanted is a statement separator; the row reads
    //
    //     }                  fold  _class_member_declarations -> …
    //     multiline_comment  read on
    //     _implicit_semi     read on
    //     _explicit_semi     read on
    //
    // and `multiline_comment` is swift's lowest-numbered external *and* a
    // declared extra. Under first-shift-wins it was named here and in every
    // other swift wall, which sent two lanes to the comment scanner for a defect
    // the semicolon guard owns.
    var b = try Bench.init(4, 4);
    defer b.deinit();
    b.put(1, 1, lalr.Action.shift(2));
    b.put(2, 1, lalr.Action.reduce(7));
    // The wall. Terminal 0 is the `}` it folds on, terminal 1 the extra it reads,
    // terminal 2 the separator it also reads. Terminal 1 is handed first, exactly
    // as swift's `externals` hands `multiline_comment` before `_implicit_semi`.
    b.put(3, 0, lalr.Action.reduce(7));
    b.put(3, 1, lalr.Action.shift(1));
    b.put(3, 2, lalr.Action.shift(1));
    var tab = b.tables();
    defer tab.arena.deinit();
    var gr = try Bench.slate(.terminal_extra);
    defer gr.deinit();

    // The separator wins, and it wins from either arrival order or order is
    // still deciding and nothing was fixed.
    try testing.expectEqual(@as(?g.Symbol, 2), standIn(&tab, &gr, 3, &.{ 1, 2 }));
    try testing.expectEqual(@as(?g.Symbol, 2), standIn(&tab, &gr, 3, &.{ 2, 1 }));

    // Last resort, never a filter. An extra-only row still answers with its
    // extra: naming background is worse than naming a terminal, but naming
    // nothing is worse than both, and this scan going silent would hand the wall
    // back to a table argument that cannot see the scanner at all.
    try testing.expectEqual(@as(?g.Symbol, 1), standIn(&tab, &gr, 3, &.{1}));

    // The one place this trades against the shift preference above: a non-extra
    // *fold* outranks the extra's *shift*, because the fold narrows to something
    // this state tolerates while the extra's shift is true of nearly every state
    // in the automaton. 59 of the 60 swift states whose name moves are this
    // case, not the case above - a fix that deranked the extra in the shift pass
    // alone would have repaired one wall in sixty and reported the win.
    var f = try Bench.init(4, 4);
    defer f.deinit();
    f.put(3, 1, lalr.Action.shift(1));
    f.put(3, 2, lalr.Action.reduce(7));
    var ftab = f.tables();
    defer ftab.arena.deinit();
    try testing.expectEqual(@as(?g.Symbol, 2), standIn(&ftab, &gr, 3, &.{ 1, 2 }));

    // And the verdict is unchanged in owner, in strength and in `because`; only
    // the terminal named moves, which is the whole claim of this change.
    const wall: Wall = .{ .refused = .{ .terminal = 0, .state = 3, .folded = &.{} } };
    const found = over(&tab, &gr, wall, &.{ 1, 2 });
    try testing.expectEqual(Owner.lexer, found.owner);
    try testing.expectEqual(Because.awaited_external, found.because);
    try testing.expectEqual(@as(?g.Symbol, 2), found.unlexable);
    try testing.expect(found.proven);
}

test "a blind extra is in no row at all, so no per-state test can see it" {
    // scala's shape, and the reason the per-state argument above is not enough.
    // `block_comment` is a declared extra, so it is admitted by no state - the
    // wall's row looks perfectly innocent - while its bytes are read as code
    // everywhere in the file.
    var b = try Bench.init(4, 3);
    defer b.deinit();
    b.put(1, 1, lalr.Action.shift(2));
    b.put(2, 1, lalr.Action.reduce(7));
    var tab = b.tables();
    defer tab.arena.deinit();
    // A *terminal* extra, which is what a comment is and what `Bench.slate`'s
    // `.extra` deliberately is not: that one wraps the terminal in a rule and
    // lists the rule, where scala and ocaml list the token itself. The two
    // shapes reach `gr.extras` differently and only this one is argument 5's.
    var gr = try Bench.slate(.terminal_extra);
    defer gr.deinit();
    const wall: Wall = .{ .refused = .{ .terminal = 0, .state = 3, .folded = &.{} } };

    // The extra's own terminal is blind, and it is admitted nowhere: state 3's
    // row is empty for it, so `awaited` cannot fire and only this argument can.
    try testing.expectEqual(@as(?g.Symbol, null), standIn(&tab, &gr, 3, &.{1}));
    const found = over(&tab, &gr, wall, &.{1});
    try testing.expectEqual(Owner.lexer, found.owner);
    try testing.expectEqual(Because.blind_extra, found.because);
    try testing.expectEqual(@as(?g.Symbol, 1), found.unlexable);
    // And never a proof. The grammar says the terminal is admitted nowhere; no
    // part of that says the file being parsed holds a byte of one.
    try testing.expect(!found.proven);

    // A blind terminal that is *not* an extra leaves this argument silent, so
    // the answer is the table's again. Without that, argument 5 would swallow
    // every wall in any grammar with an unimplemented scanner - which is most
    // of them - and trade a classifier that always says `weave` for one that
    // always says `lexer`.
    var plain = try Bench.slate(.rule);
    defer plain.deinit();
    try testing.expectEqual(Owner.press, over(&tab, &plain, wall, &.{1}).owner);
}

test "a blind extra is grammar-wide, so the path outranks it" {
    // javascript's shape, reduced, and the ordering bug it exposed. The wall's
    // own row admits no blind terminal - `awaited` is silent - but a cell the
    // author *declared* sits on the fold chain, and the grammar also happens to
    // carry a blind extra somewhere. One of those two facts is about this wall.
    //
    // Run first, the existential wins and the row reads `lexer [no stand-in for
    // b]`, which is how ledger.js came to be blamed on an `html_comment` it does
    // not contain a byte of. Run after the path, the proof wins.
    var b = try Bench.init(6, 3);
    defer b.deinit();
    b.put(4, 0, lalr.Action.reduce(1));
    try b.fray(4, 0, .fold_dropped);
    var tab = b.tables();
    defer tab.arena.deinit();
    // The declared conflict that makes state 4's cell a fork rather than a loss.
    tab.conflicts = &.{.{
        .state = 4,
        .terminal = 0,
        .kind = .shift_reduce,
        .class = .declared,
        .chosen = lalr.Action.reduce(1),
        .other = lalr.Action.reduce(1),
        .rest = &.{},
        .party = &.{},
    }};
    // Terminal 1 is the declared extra the scanner is blind to, exactly as in
    // the test above - so the only thing moving here is which argument runs.
    var gr = try Bench.slate(.terminal_extra);
    defer gr.deinit();

    const chain: []const Fold = &.{.{ .state = 4, .prod = 1 }};
    const wall: Wall = .{ .refused = .{ .terminal = 0, .state = 5, .folded = chain } };

    const f = over(&tab, &gr, wall, &.{1});
    try testing.expectEqual(Owner.oracle, f.owner);
    try testing.expectEqual(Because.declared_fork, f.because);
    try testing.expectEqual(@as(u32, 4), f.cell.?.state);
    try testing.expect(f.proven);

    // With no cell on the path there is nothing to outrank, so the argument
    // still answers - unproven, which is the whole difference.
    const bare: Wall = .{ .refused = .{ .terminal = 0, .state = 5, .folded = &.{} } };
    const fallback = over(&tab, &gr, bare, &.{1});
    try testing.expectEqual(Owner.lexer, fallback.owner);
    try testing.expectEqual(Because.blind_extra, fallback.because);
    try testing.expect(!fallback.proven);

    // And the *first* half of argument 5 keeps its place above the path: it is
    // a fact about this wall's own row, so it is a proof about this wall.
    b.put(5, 1, lalr.Action.shift(2));
    var admits = b.tables();
    defer admits.arena.deinit();
    admits.conflicts = tab.conflicts;
    const awaits = over(&admits, &gr, wall, &.{1});
    try testing.expectEqual(Owner.lexer, awaits.owner);
    try testing.expectEqual(Because.awaited_external, awaits.because);
    try testing.expect(awaits.proven);
}

test "an accepted parse and a truncated one are not walls" {
    var b = try Bench.init(2, 3);
    defer b.deinit();
    var tab = b.tables();
    defer tab.arena.deinit();
    var gr = try Bench.slate(.nobody);
    defer gr.deinit();

    try testing.expectEqual(Owner.whole, over(&tab, &gr, .whole, null).owner);
    try testing.expectEqual(Owner.unclosed, over(&tab, &gr, .unclosed, null).owner);
}
