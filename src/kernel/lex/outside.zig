//! What a grammar's external scanner would have produced, declared as data.
//!
//! tree-sitter lets a grammar name terminals no regex in the file can
//! recognize and hand them to a C function it links: `externals`. Ten of the
//! eleven grammars in `upstream/` use one, four of them for the token that
//! starts the file, so a lexer with no answer here is a lexer that cannot read
//! Python at all. joints links no tree-sitter runtime, so the C function is
//! not available to us and never will be.
//!
//! It is also, most of the time, not necessary. Read the scanners and the vast
//! majority of what they do is **recognize a spelling the DSL could not host**
//! - bash's `variable_name` is `[a-zA-Z_]\w*`, ruby's `simple_symbol` is a
//! colon and a method name, Python's `comment` is a hash to end of line. The
//! author wrote C not because the bytes are exotic but because the terminal is
//! only legal *somewhere*, and a tree-sitter grammar has no way to say where.
//! We do: lexing here is state-directed, so the parse state's own permission
//! set is exactly the context those scanners were reaching for. Give the
//! terminal its spelling and the state decides where it may appear.
//!
//! So a row here is a **spelling plus its lexical standing**, and it names the
//! company it was transcribed with. Keying on the terminal's name alone was
//! unsound and not theoretically: haskell, html and ocaml each declare an
//! external called `comment` and were each handed Python's `#[^\n]*`, for
//! languages whose comments are `--`, `<!-- -->` and `(* *)`. Nothing collided
//! by the table's own lights; the name was simply never evidence of anything.
//!
//! A row's evidence is its **cohort** - the other externals the scanner it was
//! read from produces alongside it. One C function emits the whole set, so a
//! grammar declaring all of it is following that scanner's convention, and a
//! grammar declaring one name out of it means something of its own that we have
//! no account of. `comment` seats for a grammar that also declares
//! `_indent`/`_dedent`/`_newline`, which is Python's scanner and not haskell's.
//! A row whose cohort is absent produces nothing, which is the only honest
//! answer available: the bytes an external stands for are not in `grammar.json`
//! at all, so there is nothing here to guess from.
//!
//! What the roll deliberately cannot hold: a terminal that needs to remember
//! something about the bytes before it. A heredoc body needs the tag from the
//! opener, a Python string body needs which fence opened it, `_indent` needs
//! the column stack. Those are a different mechanism, and it is the second
//! half of this file.
//!
//! # The second seam: a hand, not a spelling
//!
//! A row above is a *pattern*, and a pattern is a function of the bytes at one
//! offset. The rest of what an external scanner does is a function of the
//! bytes **and a memory built by every token before them** - which is a
//! different animal, so it gets a different seam rather than a cleverer table.
//! Two things follow from the difference and neither is optional:
//!
//!   * **It runs before the slate**, exactly as tree-sitter runs its external
//!     scanner before the internal lexer, and only at a fresh offset. A hand
//!     has to see the whitespace in front of it - that whitespace *is* Python's
//!     indentation - so it must be asked before an extra eats it.
//!   * **It may answer zero-width.** The slate must refuse a zero-length match
//!     (nothing in a regex promises the next call differs), a hand need not -
//!     but the licence is `step`'s to give and not the hand's to assume, and
//!     it is given by a bound rather than by a promise. Some hands make
//!     progress in memory (every `_dedent` pops a column) and some make none at
//!     all (julia's five `_immediate_*` markers), so the proof cannot be "the
//!     memory moved". See `Spent` for the one that covers both.
//!
//! What generalises across the hands is the *memory*, not the scanners: a
//! stack of columns (`offside.zig`) and a stack of open marks (`fence.zig`).
//! An opener's spelling never generalises and this file does not pretend it
//! does - `troupes` is a map from one language's terminal names onto the parts
//! of a shape, which is the most that is true.

const std = @import("std");
const offside = @import("hand/offside.zig");
const fence = @import("hand/fence.zig");
const marrow = @import("hand/marrow.zig");
const caesura = @import("hand/caesura.zig");
const scry = @import("hand/scry.zig");
const lineage = @import("hand/lineage.zig");
const writ = @import("hand/writ.zig");
const press = @import("../../press/press.zig");

test {
    _ = offside;
    _ = fence;
    _ = scry;
}

/// One external terminal this lexer can stand in for.
pub const Provision = struct {
    /// The name the grammar gave the terminal. Node identity rides on this
    /// being the grammar's own spelling of it, never ours.
    name: []const u8,
    /// The bytes it stands for, in the same dialect every other terminal's
    /// pattern is written in.
    pattern: []const u8,
    /// Its standing against the rest of the slate. An external carries no
    /// `token.immediate` and no `prec` in the IR - there is no wrapper to read
    /// them off - so the ones that need them declare them here. A string body
    /// that is not immediate is a body whose leading space the extras ate.
    lexis: press.Lexis = .{},
    /// Bytes that must follow the match for it to be this terminal, any one of
    /// them. Flex spells this trailing context and several of these scanners
    /// are doing exactly that: bash's `variable_name` is `word` plus "and the
    /// next byte is `=`". It cannot live in `pattern` because the linear engine
    /// has no lookahead, and it must not be *consumed*, because the `=` is the
    /// grammar's own token.
    after: []const []const u8 = &.{},
    /// Bytes that must not follow it, checked first. Ruby's hash key is a name
    /// before a `:` and emphatically not before a `::`, and one list cannot
    /// say both.
    never: []const []const u8 = &.{},
    /// The other externals the scanner this row was read from also produces.
    /// All of them must be declared, or this grammar means something else by
    /// the name and gets no spelling. Every row carries one, so the soundness
    /// is structural rather than a hope that no two languages pick the same
    /// word for different bytes.
    cohort: []const []const u8,
};

/// Whether a provision states any trailing context at all. A guarded row is a
/// faithful reading of its scanner's own refusal, so it may go first the way
/// tree-sitter's scanner does; an unguarded one is our approximation of a C
/// function and defers to anything the grammar spelled itself.
pub fn guards(p: *const Provision) bool {
    return p.after.len > 0 or p.never.len > 0;
}

/// Whether the trailing context holds for a match ending at `end`.
pub fn holds(p: *const Provision, bytes: []const u8, end: u32) bool {
    const rest = bytes[@min(end, bytes.len)..];
    for (p.never) |n| if (std.mem.startsWith(u8, rest, n)) return false;
    if (p.after.len == 0) return true;
    for (p.after) |a| if (std.mem.startsWith(u8, rest, a)) return true;
    return false;
}

/// What tree-sitter-swift's scanner refuses to let follow one of its operator
/// externals, named for the group in its `OP_ILLEGAL_TERMINATORS` table.
///
/// This is the whole reason those terminals are external, and it is trailing
/// context rather than memory: `=` is the assignment operator only where no
/// further operator byte follows it, because `=~` is a custom operator and
/// `==` is its own token. The scanner spells that as a refusal and so do we.
const Terminator = enum { alphanumeric, symbols, symbols_or_dot, non_whitespace };

/// The bytes the scanner's `switch (lexer->lookahead)` lists, in its order.
const op_bytes = [_][]const u8{ "/", "=", "-", "+", "!", "*", "%", "<", ">", "&", "|", "^", "?", "~" };

/// `iswalnum`, as bytes. The scanner reads codepoints, so a non-ASCII letter
/// after `where` is a refusal there and an acceptance here - which is the
/// direction that costs a wrong tree, so it is the one place in this table
/// worth naming as a known divergence rather than a transcription.
const op_alnum = blk: {
    const chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
    var list: [chars.len][]const u8 = undefined;
    // Sliced out of the literal rather than built from each byte, so every
    // element points into static data and the table can be a `const`.
    for (0..chars.len) |i| list[i] = chars[i .. i + 1];
    break :blk list;
};

/// Swift's operator and keyword externals, and this is the derivation rather
/// than a reading of the names.
///
/// tree-sitter-swift's scanner holds three parallel tables - `OPERATORS` for
/// the spelling, `OP_SYMBOLS` for the terminal, `OP_ILLEGAL_TERMINATORS` for
/// the refusal - and this is those three joined, in their order. So the
/// spelling of `where_keyword` is `where` because the scanner's own table says
/// so at that index, not because the name ends in `_keyword`.
///
/// Nineteen of the scanner's twenty rows. `_bang_custom` is the twentieth and
/// is declined: `OP_SYMBOL_SUPPRESSOR` conditions it on `FAKE_TRY_BANG` *not*
/// being wanted, which is a question about the parse table, and a `Provision`
/// is a function of bytes with no access to one. Seating it would mean lexing
/// the `!` of `try!` as a postfix operator - a plausible tree, which is the
/// thing this table exists to refuse.
const swift_roll = blk: {
    const Op = struct { []const u8, []const u8, Terminator };
    const ops = [_]Op{
        .{ "_arrow_operator_custom", "->", .symbols },
        .{ "_dot_custom", "\\.", .symbols_or_dot },
        .{ "_conjunction_operator_custom", "&&", .symbols },
        .{ "_disjunction_operator_custom", "\\|\\|", .symbols },
        .{ "_nil_coalescing_operator_custom", "\\?\\?", .symbols },
        .{ "_eq_custom", "=", .symbols },
        .{ "_eq_eq_custom", "==", .symbols },
        .{ "_plus_then_ws", "\\+", .non_whitespace },
        .{ "_minus_then_ws", "-", .non_whitespace },
        .{ "_throws_keyword", "throws", .alphanumeric },
        .{ "_rethrows_keyword", "rethrows", .alphanumeric },
        .{ "default_keyword", "default", .alphanumeric },
        .{ "where_keyword", "where", .alphanumeric },
        .{ "else", "else", .alphanumeric },
        .{ "catch_keyword", "catch", .alphanumeric },
        .{ "_as_custom", "as", .alphanumeric },
        .{ "_as_quest_custom", "as\\?", .symbols },
        .{ "_as_bang_custom", "as!", .symbols },
        .{ "_async_keyword_custom", "async", .alphanumeric },
    };
    var out: [ops.len]Provision = undefined;
    for (ops, 0..) |op, i| out[i] = .{
        .name = op[0],
        .pattern = op[1],
        // Trailing context only. `after` states what must follow and `never`
        // what may not, and the scanner's four groups are exactly three of the
        // first and one of the second.
        .never = switch (op[2]) {
            .alphanumeric => &op_alnum,
            .symbols => &op_bytes,
            .symbols_or_dot => &(op_bytes ++ [_][]const u8{"."}),
            .non_whitespace => &.{},
        },
        .after = switch (op[2]) {
            // `_plus_then_ws` is named for this: the scanner refuses `+` unless
            // whitespace follows, which is how `a + b` is an operator and
            // `a+b` a custom one. End of file has none, and refusing there is
            // the scanner's answer too - `iswspace('\0')` is false.
            .non_whitespace => &.{ " ", "\t", "\n", "\r", "\x0b", "\x0c" },
            else => &.{},
        },
        // Both swift's alone in the thirty, and both from this same scanner.
        .cohort = &.{ "_implicit_semi", "_fake_try_bang" },
    };
    break :blk out;
};

/// The roll. Ordered by the grammar that motivated each row, which is a
/// comment about provenance and nothing the lookup depends on.
pub const roll = swift_roll ++ [_]Provision{
    // Rust. `string_content` stops at a backslash rather than consuming it, so
    // the grammar's own `escape_sequence` - immediate, and longer at that
    // offset - still takes the escape. Stopping at the quote is what leaves
    // `string_close` a token to be.
    .{
        .name = "string_content",
        .pattern = "[^\"\\\\]+",
        .lexis = .{ .immediate = true },
        .cohort = &.{"string_close"},
    },
    .{
        .name = "string_close",
        .pattern = "\"",
        .lexis = .{ .immediate = true },
        .cohort = &.{"string_content"},
    },

    // Python. `comment` is an extra as well as an external, so once it can be
    // recognized the ordinary skip handles it. Its cohort is the offside
    // triple, because the same scanner emits both and no other grammar's
    // `comment` arrives with a column stack beside it.
    .{
        .name = "comment",
        .pattern = "#[^\\n]*",
        .cohort = &.{ "_indent", "_dedent", "_newline" },
    },

    // Bash. All three are a plain spelling plus the trailing byte its scanner
    // refuses without, and the guard is what makes them safe: `rows` is an
    // assignment target in `rows=()` and a bare `word` in `declare rows`, and
    // only the byte after it tells them apart. Both lists are the scanner's
    // own; the two cases it conditions on `CLOSING_BRACE`/`OPENING_PAREN`
    // being valid are left out rather than guessed at.
    .{
        .name = "variable_name",
        .pattern = "[a-zA-Z_][a-zA-Z0-9_]*",
        .after = &.{ "=", "[", "+=", "%", "#", "@", "?" },
        .cohort = &.{ "file_descriptor", "test_operator" },
    },
    .{
        .name = "file_descriptor",
        .pattern = "[0-9]+",
        .after = &.{ ">", "<" },
        .cohort = &.{ "variable_name", "test_operator" },
    },
    .{
        .name = "test_operator",
        .pattern = "-[a-zA-Z]+",
        .after = &.{ " ", "\t", "\n", "\r" },
        .cohort = &.{ "variable_name", "file_descriptor" },
    },

    // Ruby. A symbol is a colon and a name, an operator, or `[]`; a hash key
    // is the same name with the colon on the other side. Ruby's newline is
    // significant rather than an extra, and the state is what knows whether a
    // statement may end here - which is the whole reason its scanner is C.
    .{
        .name = "simple_symbol",
        .pattern = ":(?:[a-zA-Z_][a-zA-Z0-9_]*[?!=]?|\\[\\]=?|<=>|===?|=~|![=~]?|<<?=?|>>?=?|\\*\\*|[+\\-*/%~^&|])",
        .cohort = &.{ "hash_key_symbol", "_line_break" },
    },
    // A hash key is a bare name before a `:`, and `Foo::bar` is a scope
    // resolution rather than a key with an empty value - which is why the
    // scanner looks one byte past the colon before committing.
    .{
        .name = "hash_key_symbol",
        .pattern = "[a-zA-Z_][a-zA-Z0-9_]*",
        .after = &.{":"},
        .never = &.{"::"},
        .cohort = &.{ "simple_symbol", "_line_break" },
    },
    .{
        .name = "_line_break",
        .pattern = "\\n",
        .cohort = &.{ "simple_symbol", "hash_key_symbol" },
    },

    // Elixir. `:` before a quote, and nothing else - the scanner advances one
    // byte, marks the end, and then only *looks* at the delimiter, so the
    // quote is the grammar's own token and must not be eaten. It is external
    // for the same reason ruby's hash key is: `:"a"` is an atom and `: "a"` is
    // a colon before a string, and only the next byte tells them apart.
    .{
        .name = "_quoted_atom_start",
        .pattern = ":",
        .after = &.{ "\"", "'" },
        .cohort = &.{ "_not_in", "_before_unary_op" },
    },

    // JavaScript and TypeScript share their scanner. The ternary `?` is
    // external only to keep it away from optional chaining and optional
    // parameters, both of which the state already separates.
    .{
        .name = "_ternary_qmark",
        .pattern = "\\?",
        .cohort = &.{ "_template_chars", "regex_pattern" },
    },
    .{
        .name = "_template_chars",
        .pattern = "[^`$\\\\]+",
        .lexis = .{ .immediate = true },
        .cohort = &.{ "_ternary_qmark", "regex_pattern" },
    },
    .{
        .name = "escape_sequence",
        .pattern = "\\\\(?:x[0-9a-fA-F]{2}|u\\{[0-9a-fA-F]+\\}|u[0-9a-fA-F]{4}|[0-7]{1,3}|[^0-9xu])",
        .lexis = .{ .immediate = true },
        .cohort = &.{ "_template_chars", "regex_pattern" },
    },
    .{
        .name = "regex_pattern",
        .pattern = "(?:[^/\\\\\\[\\n]|\\\\.|\\[(?:[^\\]\\\\\\n]|\\\\.)*\\])+",
        .lexis = .{ .immediate = true },
        .cohort = &.{ "_template_chars", "_ternary_qmark" },
    },

    // Kotlin. Both are the preamble's own case: an ordinary spelling that is
    // only legal somewhere, written in C because the DSL cannot say where.
    // `_import_dot` appears in exactly two rules - `_import_identifier` and
    // the wildcard tail of `import_header` - so the dot between `kotlin` and
    // `contracts` is the only dot in the language a state admits it at, and
    // `constructor` likewise heads `primary_constructor` and nothing else.
    // Neither states trailing context, so both defer to anything the grammar
    // spelled itself: where a state admits the literal `.` or a
    // `simple_identifier` as well, the grammar's own terminal still wins and
    // these fire only where it has none. Kotlin's third external,
    // `_by_delegation_hint`, gets no row and needs no hand either: its own
    // scanner never emits it. It is declared so that it appears in
    // `valid_symbols`, where the automatic-semicolon branch reads it as a flag
    // for "we are in a delegation context" - so it is not a token at all, and
    // nothing here could stand in for one. Its absence costs no structure.
    .{
        .name = "_import_dot",
        .pattern = "\\.",
        .cohort = &.{ "_primary_constructor_keyword", "_by_delegation_hint" },
    },
    .{
        .name = "_primary_constructor_keyword",
        .pattern = "constructor",
        .cohort = &.{ "_import_dot", "_by_delegation_hint" },
    },

    // Scala's simple strings. Read off the scanner rather than inferred from
    // the rule, because the scanner the oracle builds is on disk and it settles
    // three things the grammar leaves open:
    //
    //   * the opener marks its end after the FIRST quote and only then looks
    //     for two more, so the start is exactly one byte and `"""` is a
    //     different terminal rather than a longer reading of this one;
    //   * in the body a `"` is consumed and ends the token, while a `\` ends it
    //     *before* itself - the escape is the grammar's own `escape_sequence`;
    //   * a newline or EOF returns false, so a simple string cannot span a
    //     line, and `$` is ordinary here because the interpolation branch is
    //     reached with a different mode.
    //
    // Three rows and one machine. The `string_mode` that C function carries is
    // the memory a hand would exist to keep, and here the state already has it:
    // `string -> _simple_string_start (_simple_string_middle escape_sequence)*
    // _single_line_string_end`, so the middle and the end are admitted only
    // after the start, and interpolation is a separate production the slate
    // already lexes through a literal `imm('"')`.
    //
    // The pair splits the body the way rust's does, and for the same reason: at
    // the offset after the opener both the middle and the end match, the end
    // reaches one byte further because it takes the closing quote, and longest
    // wins. Where a backslash stops the end from reaching a quote at all, the
    // middle is the only reading left.
    .{
        .name = "_simple_string_start",
        .pattern = "\"",
        .cohort = &.{ "_simple_string_middle", "_single_line_string_end", "_simple_multiline_string_start" },
    },
    // The opener the scanner reaches from the same branch, and the reason this
    // row exists rather than a guard on the one above. `"""` has to lose the
    // position to something, and a stand-in that merely refuses does not take
    // it away: a failed trailing context declines the priority pass and the
    // slate still answers, so a guarded `"` would match one quote of a triple
    // and hand the parse an empty string. Spelling the longer opener is what
    // makes longest-match settle it, the way the C settles it by looking for
    // two more quotes before it commits.
    //
    // Its own end gets no row and stays blind on purpose. `_multiline_string_end`
    // closes on three-or-more quotes not followed by a quote, and a
    // longest-match engine with no lazy repeat cannot spell a body that stops
    // at the first of them. So a multiline string refuses here - which is what
    // it did before any of these rows existed, and the outcome the board
    // charges least of the two available.
    .{
        .name = "_simple_multiline_string_start",
        .pattern = "\"\"\"",
        .cohort = &.{ "_simple_string_start", "_simple_string_middle", "_single_line_string_end" },
    },
    .{
        .name = "_simple_string_middle",
        .pattern = "[^\"\\\\\n]+",
        .lexis = .{ .immediate = true },
        .cohort = &.{ "_simple_string_start", "_single_line_string_end", "_simple_multiline_string_start" },
    },
    .{
        .name = "_single_line_string_end",
        .pattern = "[^\"\\\\\n]*\"",
        .lexis = .{ .immediate = true },
        .cohort = &.{ "_simple_string_start", "_simple_string_middle", "_simple_multiline_string_start" },
    },
};

/// The spelling declared for an external terminal, if this lexer has one *and*
/// this grammar is the kind of grammar the row was read from.
///
/// The cohort is what makes the second half true. Without it the name alone
/// decided, and a name is shared by languages that mean different bytes by it;
/// with it, a row fires only where the whole scanner's output is present.
pub fn provisionFor(gr: *const press.Grammar, name: []const u8) ?*const Provision {
    for (&roll) |*p| {
        if (!std.mem.eql(u8, p.name, name)) continue;
        for (p.cohort) |kin| if (!declaresExternal(gr, kin)) return null;
        return p;
    }
    return null;
}

/// Whether the grammar declares `name` as an external terminal. An ordinary
/// terminal of the same name is not the evidence a cohort asks for: the point
/// is what the scanner emitted, and a spelled token was never in the scanner.
fn declaresExternal(gr: *const press.Grammar, name: []const u8) bool {
    for (0..gr.terminal_count) |i| {
        // Not the same question `compile` asks. This one is a predicate, and a
        // terminal carrying no pattern is a true "not an external" rather than
        // something dropped - the site that needs the value is the site that
        // refuses over it.
        const pattern = gr.patterns[i] orelse continue;
        if (pattern != .external) continue;
        if (std.mem.eql(u8, gr.nameOf(@intCast(i)), name)) return true;
    }
    return false;
}

/// A family of externals that one hand-written scanner answers for, named the
/// way one language spells them.
///
/// Keyed by terminal name like the roll above, and for the same reason: node
/// identity is the grammar's spelling, never ours. A grammar is bound to a
/// troupe when it declares the troupe's `anchor` as an external, and binding
/// claims every other member too - which is how Ruby's `string_content` stops
/// being answered by the Rust-shaped row in the roll and starts being answered
/// by the fence that knows which quote opened it.
pub const Troupe = struct {
    /// One member of a family a grammar spells one terminal per delimiter of.
    ///
    /// The whole difference between elixir's twenty content terminals is the
    /// mark that closes each, so the twenty are twenty rows of data behind one
    /// arm rather than twenty veins. Order is the specification's own table
    /// order, because that is the order it resolves a tie in.
    pub const Part = struct { name: []const u8, mark: marrow.Mark };

    /// The terminal a family's walk emits when the delimiter is standing where
    /// its matter would have been, keyed by the character that closes.
    ///
    /// Keyed by the shut and not parallel to the roster because that is
    /// literally how the specification picks one: julia's `scan_content` opens
    /// with `end_symbol = (end_char == '"') ? END_STR : END_CMD`, so eight
    /// content terminals share two closes and the width they close over is the
    /// part's, not the close's.
    pub const Shut = struct { at: u8, name: []const u8 };

    /// A zero-width marker that means "the delimiter after me is touching the
    /// token before me", keyed by the delimiter.
    ///
    /// The character is the whole of the decision, which is why this is data
    /// and not five arms: julia's five differ only in which bracket or quote
    /// has to be glued on. Keyed by the character rather than parallel to a
    /// roster for the same reason `Shut` is - the hand reads a byte and needs
    /// the symbol that byte implies.
    pub const Glue = struct { at: u8, name: []const u8 };

    /// A pair of parser orders that bracket a region, and the frame they leave.
    ///
    /// The frame is named rather than positional because the close is keyed to
    /// it: `_cmd_texp_end` pops a `fenced` frame and a `_cmd_brace_close` pops a
    /// `braced` one, and a state admitting the wrong close over the right frame
    /// must decline rather than pop whatever is on top. That is the whole of the
    /// C scanner's `current_context(env) == TExp` guard, kept as data.
    pub const Bracket = struct { open: []const u8, shut: []const u8, frame: u16 };

    /// How many markers one language may glue. Julia declares five; the room
    /// above that is for the next language and not for a cohort to grow into
    /// silently, since `seated` refuses a troupe that overflows it.
    pub const glues = 6;

    /// How many terminals one caesura may answer: exactly the arms
    /// `caesura.Seam` names, so a row cannot spell a seam the rules cannot reach
    /// and the array cannot fall out of step with the enum.
    pub const seats = @typeInfo(caesura.Seam).@"enum".fields.len;

    /// The terminal whose presence says this language uses this shape.
    anchor: []const u8,
    kind: enum { offside, fence, marrow, caesura, scry, lineage, writ, abut },
    dialect: fence.Dialect = .python,
    /// Which separator rule to run, when `kind` is `.caesura`. A discriminator
    /// like `dialect` and `vein` rather than a set of knobs, because the three
    /// languages that hand their separator to a scanner do not share a rule -
    /// swift's suppressors are the inverse of ecma's. See `caesura.Tongue`.
    tongue: caesura.Tongue = .ecma,
    /// The bounding spelling, when `kind` is `.marrow`. Kept beside `dialect`
    /// rather than folded into it because the two answer different questions -
    /// one names an opener, the other names a close - and a row uses exactly
    /// one of them.
    vein: marrow.Dialect = .rust_block,
    /// The family, when the vein's close is a `Mark` rather than a walk. Every
    /// member must resolve for the cast to seat, which is the same whole-shape
    /// evidence `opens` demands and is worth more here: twenty names arriving
    /// together is not a collision anyone can have by accident.
    roster: []const Part = &.{},
    /// Which family that roster is, which is what tells two rosters apart
    /// where `vein` tells two walks apart.
    family: marrow.Family = .none,
    /// The closes that family emits itself, when it emits any. Empty for a
    /// family whose delimiters the press lexes - elixir's quotes are ordinary
    /// terminals, so its walk only ever answers matter.
    shuts: []const Shut = &.{},
    /// The glued markers, when `kind` is `.abut`. Every one must resolve, on
    /// the same whole-shape evidence a roster demands: a grammar declaring two
    /// of five means something else by the names.
    glued: []const Glue = &.{},
    /// The two members whose being admitted *at once* means the state is not
    /// inside the family at all.
    ///
    /// The members are mutually exclusive by construction, so two of them live
    /// together only in a state that would accept either - which is a state
    /// outside every quote, reading ordinary code that happens to be able to
    /// start one. elixir names the pair its own scanner names; a family with no
    /// such state leaves this empty and every member simply wins on its own.
    rival: [2][]const u8 = .{ "", "" },
    /// Whether *any* two members being admitted at once means the state is not
    /// inside the family - the whole-roster form of `rival`, and latex's own
    /// dispatcher rather than a generalisation of somebody else's:
    /// `external_scanner_scan` walks all twelve, and returns false the moment it
    /// finds a second live one. A row sets this or names a `rival` pair, never
    /// both: the pair is what a family with a legitimately ambiguous state needs,
    /// and this is what a family with none declares.
    lone: bool = false,
    /// Whose lookahead, when `kind` is `.scry`. Beside `dialect` and `vein`
    /// for the same reason they are beside each other: a row uses exactly one
    /// of the three, and which one is what `kind` already says.
    sight: scry.Dialect = .css,
    /// Whose element containment rules, when `kind` is `.lineage`.
    line: lineage.Dialect = .html,
    /// Layout, when `kind` is `.offside`.
    newline: []const u8 = "",
    indent: []const u8 = "",
    dedent: []const u8 = "",
    /// How this language spells the comment the measurement sees through, when
    /// `kind` is `.offside`. A discriminator like `dialect` and `vein`, and it
    /// earns the field the same way: python's `#` read over scala puts the
    /// wrong column on four lines in five of the fixture, because a scaladoc
    /// block is content to a `#` rule and whitespace to a `//` one.
    note: offside.Note = .hash,
    /// The orders that open a block, when `kind` is `.writ`. A list rather than
    /// a name because haskell spells one per construct - `_cmd_layout_start_do`,
    /// `_case`, `_if`, `_let`, `_quote` and a bare one for `where` and `of` - and
    /// all six mean the identical push. They differ only in which state admits
    /// them, which is the parser's business and not this hand's.
    ///
    /// Every entry that is spelled must resolve, on the same whole-shape evidence
    /// `opens` demands: a grammar declaring two of six does not mean this
    /// protocol by them.
    writs: []const []const u8 = &.{},
    /// The order that opens a block over an explicit `{`, when `kind` is `.writ`.
    /// Apart from `writs` because it consumes a byte and pushes a frame the
    /// offside rule may not close, where the others consume nothing.
    brace: []const u8 = "",
    /// The condition that ends one item and begins the next - a zero-width
    /// semicolon, answered when a fresh line lands level with the block.
    sever: []const u8 = "",
    /// The condition that ends the block, answered when a fresh line lands left
    /// of it. Zero-width, and the pop.
    seal: []const u8 = "",
    /// The condition that ends an explicit block, over its `}`.
    unbrace: []const u8 = "",
    /// The bracket orders, when `kind` is `.writ`: pairs of zero-width terminals
    /// the grammar spells immediately after a delimiter it also spells, which
    /// push and pop a frame the layout rule reads but no column may close.
    ///
    /// A separate field from `writs` because the mutation is different in kind.
    /// A `writ` opens a *block*, so it measures the next lexeme and stores its
    /// column; a bracket carries no measurement at all - `(` is a bracket
    /// wherever it stands - so its frame is a marker and its close is a stack
    /// test rather than a comparison. Haskell spells two pairs: `_cmd_texp_*`
    /// around `(`, `[` and a guard's `|`, and `_cmd_brace_*` around a record's
    /// `{`, and tree-sitter-haskell's scanner answers both in four lines that
    /// read no bytes whatever.
    ///
    /// Every pair that is spelled must resolve whole, on the same evidence
    /// `writs` demands and for a sharper reason: seating an open without its
    /// close strands a marker on the stack, and a marker on top silences the
    /// offside rule for the rest of the file. Half of this is worse than none.
    brackets: []const Bracket = &.{},
    /// Terminals whose being wanted stands this hand down. Python's are its
    /// brackets, because inside `(`, `[` or `{` a line break carries no
    /// meaning; JavaScript's are the template body and JSX text, because the
    /// spec's own dispatcher answers those before it reaches the semicolon.
    /// One shape, so one field: a terminal the parser would accept that says
    /// this is not the place.
    ///
    /// A refinement rather than a part, so an entry that does not resolve does
    /// not stop the cast from seating.
    hushed: []const []const u8 = &.{},
    /// Another external the same scanner function emits, required as evidence
    /// that this grammar follows the convention rather than reusing a name.
    ///
    /// The anchor alone is not enough here and it is not a hypothetical:
    /// kotlin, php and scala all declare `_automatic_semicolon`, and all three
    /// mean their own rule by it - php's is `?>`, scala's is its newline
    /// inference. Handing any of them JavaScript's continuation set would be
    /// the kotlin defect a fourth time. `_template_chars` is declared by
    /// javascript and typescript and by nothing else in the thirty.
    ///
    /// Evidence only, never emitted. A hand whose cohort it *does* answer says
    /// so by listing the whole cohort in `opens`, which is what `.scry` does.
    kin: []const u8 = "",
    /// The terminal whose being wanted the caesura hand reads as evidence
    /// rather than as a veto - the language's binary-or, whose acceptability
    /// is what separates an expression from a type.
    ///
    /// Not required, and looked up across the whole terminal set rather than
    /// the externals: what the hand needs is the parse table's answer about a
    /// spelling, not who lexes it. tree-sitter declares `||` external and also
    /// uses it as an ordinary operator, and the press keeps the ordinary one.
    /// A grammar without it would fall to the default branch rather than
    /// guessing, but no grammar seats this cast without one.
    gate: []const u8 = "",
    /// The zero-width terminator a function signature would take, which
    /// suppresses the break before what would otherwise be its body. Optional:
    /// TypeScript declares it and JavaScript has no such thing.
    sign: []const u8 = "",
    /// The terminal for a separator the file *did* spell, when the grammar
    /// names one apart from the implied one. Swift does - `_explicit_semi` for
    /// a `;` its scanner reads as whitespace - and that is why swift cannot
    /// read even a written semicolon without this hand: nothing else in its
    /// member rules spells a separator. Emitted with a width where `body` is
    /// emitted with none. Optional; kotlin folds both into one terminal.
    spelled: []const u8 = "",
    /// The terminals a caesura answers where its tongue answers more than one,
    /// indexed by `caesura.Seam` so the hand reads the arm the rule decided and
    /// never a position in a list.
    ///
    /// A part rather than a refinement, and required whole, on the same evidence
    /// a roster is: elixir's three arrive together out of one function, and a
    /// grammar declaring one of the three means something of its own by the name.
    /// Left empty by the three tongues whose whole answer is `body`, and `seated`
    /// asks only about the entries a row actually spells - a caesura naming both
    /// `body` and one seam would be a contradiction no row states.
    seams: [seats]([]const u8) = @splat(""),
    /// The openers, when `kind` is `.fence`. Ordered to match the dialect's
    /// own tag numbering, because a dialect with six openers and one closer
    /// has to say on the way out which one it was.
    opens: []const []const u8 = &.{},
    /// The interpolation openings, when the dialect spells its own rather than
    /// leaving the bracket to the grammar's ordinary terminal. Ordered to match
    /// `fence.Sigil`, so the hand reads the index the reader answered with.
    ///
    /// Kotlin is why this is a part and not a refinement: `${` reaches the
    /// ordinary lexer today, which sees a brace and returns a `lambda_literal`
    /// - a confidently wrong node in the middle of a string, which the contract
    /// above calls worse than an unanswered token.
    sigils: []const []const u8 = &.{},
    body: []const u8 = "",
    close: []const u8 = "",
    escape: []const u8 = "",
    /// The close that does not match what is open, when `kind` is `.lineage`.
    /// A part rather than a refinement: html's `erroneous_end_tag_name` is a
    /// real token over real bytes, and a hand that returned nothing instead
    /// would leave `</div>` inside a `<p>` unlexable rather than mismatched.
    stray: []const u8 = "",
    /// The close the language infers where the file spells none. Zero-width,
    /// and the part that needs the ancestry rather than the offset.
    implied: []const u8 = "",
    /// The delimiter that opens and closes in one mark: html's `/>`. Named
    /// apart from `close` because it ends the element it is *inside* rather
    /// than the one a matching name would end.
    shut: []const u8 = "",
};

/// Every shape this lexer can stand in for. One row per language convention.
pub const troupes = [_]Troupe{
    // Python's offside rule. The brackets guard is the spec's: inside `(`,
    // `[`, or `{` a newline is not a statement end, so no dedent may fire.
    .{
        .anchor = "_indent",
        .kind = .offside,
        .newline = "_newline",
        .indent = "_indent",
        .dedent = "_dedent",
        .hushed = &.{ ")", "]", "}" },
    },
    // Scala 3's optional braces, which are the offside rule again and not
    // haskell's inversion — a distinction worth stating because the two look
    // alike from the grammar and are opposite in the scanner.
    //
    // The evidence is where the push is: tree-sitter-scala emits INDENT only
    // when `newline_count > 0` and the measured width is greater than the
    // frame's, so the scanner *detects* the region and the parser only permits
    // it. Haskell's `_cmd_layout_start_do` is granted on the parser's say-so
    // with nothing measured, which is why that one needed `.writ`. Classified
    // off the scanner's structure, not off either name.
    //
    // `_outdent` rather than python's `_dedent`, and the separator spelled as
    // the newline: scala's three arms are tried in the order INDENT, OUTDENT,
    // AUTOMATIC_SEMICOLON, and `layout` already runs them in exactly that
    // order. The anchor is shared with python and the separator with kotlin,
    // php and javascript, so neither alone would identify this grammar — what
    // does is that all three resolve together, which no other grammar in the
    // thirty can say.
    .{
        .anchor = "_indent",
        .kind = .offside,
        .note = .slashes,
        .newline = "_automatic_semicolon",
        .indent = "_indent",
        .dedent = "_outdent",
        .hushed = &.{ ")", "]", "}" },
    },
    // Haskell's layout, which is the offside rule with the authority inverted:
    // the parser orders a block open and the scanner tests the stack it was told
    // to fill. `writ.zig`'s header is the argument for why that needs its own
    // kind rather than the row above.
    //
    // The cohort is ten names and all ten are haskell's alone across the thirty
    // - no other grammar declares even one - so this row cannot be picked up the
    // way kotlin picked up ruby's openers. `seated` requires all six orders and
    // all four conditions, so a grammar spelling a subset gets nothing.
    .{
        .anchor = "_cmd_layout_start",
        .kind = .writ,
        .writs = &.{
            "_cmd_layout_start",
            "_cmd_layout_start_do",
            "_cmd_layout_start_case",
            "_cmd_layout_start_if",
            "_cmd_layout_start_let",
            "_cmd_layout_start_quote",
        },
        .brace = "_cmd_layout_start_explicit",
        .sever = "_cond_layout_semicolon",
        .seal = "_cond_layout_end",
        .unbrace = "_cond_layout_end_explicit",
        // The two bracket orders, and the cleanest warrant on the board. Both
        // pairs are pure `valid()` tests in `pre_ws_commands` - four functions,
        // no byte read between them - and the table grants the warrant outright
        // rather than on the corpus: measured over haskell's 3543 states,
        // `_cmd_texp_start` shifts in 3 and is the *sole* shift in all 3,
        // `_cmd_texp_end` in 6 and sole in 6, `_cmd_brace_open` in 4 and sole in
        // 4, `_cmd_brace_close` in 13 and sole in 13. Zero rivals anywhere, and
        // zero co-admission with each other in either the shift or the
        // permission set. Nothing here ever asks the bytes a question, because
        // there is never a second answer for the bytes to choose between.
        .brackets = &.{
            .{ .open = "_cmd_texp_start", .shut = "_cmd_texp_end", .frame = writ.fenced },
            .{ .open = "_cmd_brace_open", .shut = "_cmd_brace_close", .frame = writ.braced },
        },
    },
    // Python's strings, which its scanner answers in the same C function as
    // the layout and for the same reason: `f"{x}"` puts an interpolation
    // inside a token, so the body has to know what opened it.
    .{
        .anchor = "string_start",
        .kind = .fence,
        .dialect = .python,
        .opens = &.{"string_start"},
        .body = "_string_content",
        .close = "string_end",
        .escape = "escape_interpolation",
    },
    // Ruby: six openers, one closer, one body. The order matches
    // `fence.RubyStart`, which is what the closer reads to name its terminal.
    .{
        .anchor = "_string_start",
        .kind = .fence,
        .dialect = .ruby,
        .opens = &.{
            "_string_start", "_symbol_start",       "_subshell_start",
            "_regex_start",  "_string_array_start", "_symbol_array_start",
        },
        .body = "string_content",
        .close = "_string_end",
    },
    // Rust's raw strings. The hash run in the opener is the close, which is
    // the entire reason the spelling exists and cannot be a fixed pattern.
    .{
        .anchor = "_raw_string_literal_start",
        .kind = .fence,
        .dialect = .rust_raw,
        .opens = &.{"_raw_string_literal_start"},
        .body = "raw_string_literal_content",
        .close = "_raw_string_literal_end",
    },
    // Kotlin's strings, and the largest blind cohort on the board: five of its
    // eight unanswered externals are this one row.
    //
    // It is a fence rather than a `marrow` family, and the reason is worth
    // stating because the two look alike from the grammar. A bounded run walks
    // backwards from its content offset to find the opener - which is how
    // C++'s `R"tag(` and Lua's `[==[` are read - and an interpolated interior
    // re-enters arbitrarily far from where it opened: `"a ${ f("b") } c"`
    // resumes after a `}` with a whole nested literal in between. Only a
    // remembered mark survives that, so the memory has to be a span.
    //
    // `_by_delegation_hint` is the cohort. Every other name here is a word
    // some other grammar could pick - kotlin was handed Ruby's six openers
    // once, on the strength of sharing `_string_start` alone (see `seated`) -
    // and the hint is kotlin's alone across the thirty. The interpolation
    // starts are parts rather than evidence, because today `${` reaches the
    // ordinary lexer, which sees a brace and returns a `lambda_literal`.
    .{
        .anchor = "_string_start",
        .kind = .fence,
        .dialect = .kotlin,
        .opens = &.{"_string_start"},
        .sigils = &.{ "_interpolation_expression_start", "_interpolation_identifier_start" },
        .body = "string_content",
        .close = "_string_end",
        .kin = "_by_delegation_hint",
    },
    // Rust's block comments, which nest. The cast is the content plus both doc
    // markers, because a grammar that declares all three is following Rust's
    // convention rather than reusing the words "block comment content" - and
    // the markers are evidence only. This hand never answers them: the rule's
    // own CHOICE reaches the content without them, so claiming them keeps the
    // roll from inventing a pattern while leaving the doc branch to the tables.
    .{
        .anchor = "_block_comment_content",
        .kind = .marrow,
        .vein = .rust_block,
        .opens = &.{ "_outer_block_doc_comment_marker", "_inner_block_doc_comment_marker" },
        .body = "_block_comment_content",
    },
    // C++'s raw strings. Two externals, one read at the open and one bounded by
    // it, which is the whole cast - so a grammar declaring only one of them
    // means something of its own and gets silence.
    .{
        .anchor = "raw_string_content",
        .kind = .marrow,
        .vein = .cpp_raw,
        .opens = &.{"raw_string_delimiter"},
        .body = "raw_string_content",
    },
    // JavaScript's automatic semicolon, and TypeScript's, which are the same
    // C function over the same enum. `||` is required rather than decorative:
    // it is what the spec consults to tell an expression from a type, so a
    // grammar that spells `_automatic_semicolon` without declaring an external
    // `||` is not this convention and gets silence.
    // Kotlin's block comments, which nest. It is a terminal extra with no rule
    // of its own, so the hand answers the whole token; `_by_delegation_hint` is
    // the cohort, because swift also declares a `multiline_comment` and means
    // its own thing by it.
    .{
        .anchor = "multiline_comment",
        .kind = .marrow,
        .vein = .kotlin_block,
        .body = "multiline_comment",
        .kin = "_by_delegation_hint",
    },
    // Swift's block comments, which nest. The same terminal name as kotlin's
    // row above and a different scanner behind it, which is the whole reason
    // both rows carry a cohort: `multiline_comment` is declared by exactly
    // these two grammars across the thirty, so the anchor alone cannot tell
    // them apart and `seated` would hand each the other's. `_fake_try_bang` is
    // swift's alone and comes off the same C file, the way
    // `_by_delegation_hint` does for kotlin.
    //
    // A separate vein rather than kotlin's, for the reason `slashStar`'s header
    // gives: the walk is shared and the end-of-input rule is not. It also keeps
    // the two rows' pinned permissions apart, which one shared vein could not -
    // the same key held by two rows is how `marrow/kotlin_block` once read
    // `{kotlin, scala}` and let either widen onto the other silently.
    //
    // What this corrects is not a refusal. `/* c\n d */` parses today as one
    // root with no mends - `custom_operator` `/*`, then `d * /` as a
    // multiplicative expression - so the bytes are counted `built` while being
    // read as arithmetic. Seating the comment moves them out of `built`; see
    // the result dossier, which prices that as a correction.
    .{
        .anchor = "multiline_comment",
        .kind = .marrow,
        .vein = .swift_block,
        .body = "multiline_comment",
        .kin = "_fake_try_bang",
    },
    // Swift's raw strings, `#"…"#` and `##"…"##`, where the closer must be as
    // wide as the opener. A captured close, and stateless the way C++'s is:
    // the width sits at `at`, so nothing has to be remembered between the two
    // ends of one literal.
    //
    // Seated as a `close` and not a `body`, which is the whole design of the
    // row rather than an omission. The grammar is
    //
    //     raw_string_literal := (raw_str_part raw_str_interpolation ...)*
    //                           raw_str_end_part
    //
    // so a literal with no `\#(` in it is *only* `raw_str_end_part`, opener and
    // closer included - one token over the whole extent, which is what
    // `marrow.shut` answers. `raw_str_part` and `raw_str_continuing_indicator`
    // stay blind because the parse resumes after an interpolation's `)` at an
    // offset whose bytes cannot name the delimiter's width; `swiftRaw`'s header
    // gives that argument in full, including why `fence` cannot hold it either.
    //
    // `raw_str_continuing_indicator` is the cohort. All three of these names
    // are swift's alone across the thirty, so the anchor could have vouched for
    // itself - the kin is here because it comes off the same C function
    // (`eat_raw_str_part`) and says which scanner this row claims to be, which
    // is the standard every other row in this file is held to.
    //
    // Both specimens are extent claims and neither can be made by presence:
    // `#"a \(n) b"#` builds a `raw_string_literal` either way, and only the
    // span says whether `\(n)` was read as six literal bytes or as an
    // interpolation that swift does not have at this width.
    .{
        .anchor = "raw_str_end_part",
        .kind = .marrow,
        .vein = .swift_raw,
        .close = "raw_str_end_part",
        .kin = "raw_str_continuing_indicator",
    },
    // Scala's block comments, which nest. Kotlin's shape exactly - a terminal
    // extra with no rule, so the hand answers the whole token including the
    // `/*` - and it reuses kotlin's vein rather than getting a spelling of its
    // own, because the bytes really are the same bytes.
    //
    // `_suppress_block_comment` is the cohort and it is doing the same work
    // `kin` does everywhere else in this file: `block_comment` is a name any
    // language could pick, and what says scala means *scala's* scanner by it is
    // that the same C function emits the suppression beside it. Both spellings
    // are scala's alone across the thirty.
    //
    // Until this row seated, `/* , */` refused at the comma: the comment was
    // never one token, so the parser read its contents as code and state 584
    // was offered a `,` no rule there admits.
    .{
        .anchor = "block_comment",
        .kind = .marrow,
        .vein = .kotlin_block,
        .body = "block_comment",
        .kin = "_suppress_block_comment",
    },
    // OCaml's comments, which nest. Also a terminal extra with no rule, so the
    // hand answers the whole `(* … *)`.
    //
    // `comment` is the most collided name in the population - haskell, html,
    // ocaml, python and yaml all declare one, and they mean `--`, `<!-- -->`,
    // `(* *)` and `#` by it. So the cohort carries the entire soundness of this
    // row: `_left_quoted_string_delimiter` is ocaml's `{|…|}` and no other
    // grammar in the thirty spells it. Keyed on the name alone this row would
    // hand python's comments to ocaml, which is the defect this file's header
    // was written about.
    .{
        .anchor = "comment",
        .kind = .marrow,
        .vein = .ocaml_comment,
        .body = "comment",
        .kin = "_left_quoted_string_delimiter",
    },
    // Julia's block comments, which nest. The `#=` is an ordinary pattern the
    // parser lexes, so only the rest is external - `rust_block` with a
    // different spelling, one grammar over.
    .{
        .anchor = "_block_comment_rest",
        .kind = .marrow,
        .vein = .julia_block,
        .body = "_block_comment_rest",
        .kin = "_immediate_paren",
    },
    // Elixir: one content terminal per delimiter, twenty of them, and the
    // delimiter is the only difference between any two. The `_i_` half
    // interpolates and the other half does not; a sigil's delimiter is its
    // *closing* bracket, which is why `_parenthesis` closes on `)`. Order is
    // the specification's table order, and its own rival pair is the two that
    // a state outside every quote can admit together.
    //
    // Both quotes are ordinary strings the press lexes, so the hand answers the
    // middle and nothing else - which is what `marrow` is for.
    .{
        .anchor = "_quoted_content_double",
        .kind = .marrow,
        .family = .elixir_quoted,
        .rival = .{ "_quoted_content_i_single", "_quoted_content_i_double" },
        .roster = &.{
            .{ .name = "_quoted_content_i_single", .mark = .{ .shut = '\'', .interpolates = true } },
            .{ .name = "_quoted_content_i_double", .mark = .{ .shut = '"', .interpolates = true } },
            .{ .name = "_quoted_content_i_heredoc_single", .mark = .{ .shut = '\'', .wide = 3, .interpolates = true } },
            .{ .name = "_quoted_content_i_heredoc_double", .mark = .{ .shut = '"', .wide = 3, .interpolates = true } },
            .{ .name = "_quoted_content_i_parenthesis", .mark = .{ .shut = ')', .interpolates = true } },
            .{ .name = "_quoted_content_i_curly", .mark = .{ .shut = '}', .interpolates = true } },
            .{ .name = "_quoted_content_i_square", .mark = .{ .shut = ']', .interpolates = true } },
            .{ .name = "_quoted_content_i_angle", .mark = .{ .shut = '>', .interpolates = true } },
            .{ .name = "_quoted_content_i_bar", .mark = .{ .shut = '|', .interpolates = true } },
            .{ .name = "_quoted_content_i_slash", .mark = .{ .shut = '/', .interpolates = true } },
            .{ .name = "_quoted_content_single", .mark = .{ .shut = '\'' } },
            .{ .name = "_quoted_content_double", .mark = .{ .shut = '"' } },
            .{ .name = "_quoted_content_heredoc_single", .mark = .{ .shut = '\'', .wide = 3 } },
            .{ .name = "_quoted_content_heredoc_double", .mark = .{ .shut = '"', .wide = 3 } },
            .{ .name = "_quoted_content_parenthesis", .mark = .{ .shut = ')' } },
            .{ .name = "_quoted_content_curly", .mark = .{ .shut = '}' } },
            .{ .name = "_quoted_content_square", .mark = .{ .shut = ']' } },
            .{ .name = "_quoted_content_angle", .mark = .{ .shut = '>' } },
            .{ .name = "_quoted_content_bar", .mark = .{ .shut = '|' } },
            .{ .name = "_quoted_content_slash", .mark = .{ .shut = '/' } },
        },
    },
    // Julia's eight string and command interiors, and the two closes its own
    // walk emits.
    //
    // Seated because its `serialize` writes nothing: `external_scanner_create`
    // returns NULL, `serialize` returns 0, `deserialize` has an empty body. A
    // scanner with no memory has no answer that depends on which reading asked,
    // which is the soundness bar met by construction rather than by argument.
    // The eight are `{str,cmd}` x `{1,3}` x `{plain,raw}` and differ only in
    // the mark, exactly as elixir's twenty do; order is the specification's own
    // dispatch order in `external_scanner_scan`, because that is the order it
    // resolves a tie in.
    //
    // The rival pair is what the census bought, and it bought it by
    // contradicting the first reading of itself. By shift, no two of the eight
    // are ever co-admitted, which reads as "no guard needed". But the
    // permission set a hand sees is `drive.offer`'s - every terminal with any
    // non-error action, shifts and reduce-lookaheads alike - and in *that*
    // column six of them sit together in three states, first at state 1, where
    // 103 terminals all fold `identifier -> _word_identifier`. A hand reading
    // the shift column would have answered string content over an identifier.
    // The pair below is admitted together in exactly those three loose states
    // and in none of the eight real interiors (state 44 is shift 4,
    // lookahead 0, and holds no command terminal at all), so it refuses where
    // the family is not and nowhere else.
    .{
        .anchor = "_content_str_1",
        .kind = .marrow,
        .family = .julia_quoted,
        .rival = .{ "_content_str_1", "_content_cmd_1" },
        .shuts = &.{
            .{ .at = '"', .name = "_end_str" },
            .{ .at = '`', .name = "_end_cmd" },
        },
        .roster = &.{
            .{ .name = "_content_str_1", .mark = .{ .shut = '"', .interpolates = true } },
            .{ .name = "_content_str_3", .mark = .{ .shut = '"', .wide = 3, .interpolates = true } },
            .{ .name = "_content_cmd_1", .mark = .{ .shut = '`', .interpolates = true } },
            .{ .name = "_content_cmd_3", .mark = .{ .shut = '`', .wide = 3, .interpolates = true } },
            .{ .name = "_content_str_1_raw", .mark = .{ .shut = '"' } },
            .{ .name = "_content_str_3_raw", .mark = .{ .shut = '"', .wide = 3 } },
            .{ .name = "_content_cmd_1_raw", .mark = .{ .shut = '`' } },
            .{ .name = "_content_cmd_3_raw", .mark = .{ .shut = '`', .wide = 3 } },
        },
    },
    // Julia's five glued delimiters, which are the other half of the same
    // scanner and the last of its blind terminals.
    //
    // Seated on the same evidence the interiors were: julia's
    // `external_scanner_create` returns NULL and its `serialize` writes
    // nothing, so no answer of its can depend on which reading asked. These
    // five carry that further than the eight do - they read one byte, move no
    // stack, and claim no width - which is why `step` needed a bound that
    // survives a hand making no progress at all. See `Spent`.
    //
    // The character in each row is not a convention, it is the rule the
    // grammar spells: `call_expression = _primary _immediate_paren
    // tuple_expression`, and `tuple_expression` opens with `(`. Order is the
    // grammar's own external declaration order, which is the order the C enum
    // is generated in.
    //
    // The census here is a near-miss worth keeping. By shift, no `_immediate_*`
    // is ever co-admitted with a `_content_*` or with either close: 28 pairs at
    // `shift 0`, which reads as a clearance. In the permission set every one of
    // them is co-admitted with every interior terminal, at state 1, and
    // `_immediate_string_start` shares the `"` that `_end_str` is keyed to - so
    // the shift column would have licensed a seating the set column condemns.
    // It was condemned and then measured, and the measurement declined to
    // convict: the parser never stands in state 1 at a quote, so the phase this
    // hand sits in changes nothing on the corpus or on any probe. The guard
    // doing the work is the permission-set test in `glued`.
    .{
        .anchor = "_immediate_paren",
        .kind = .abut,
        .glued = &.{
            .{ .at = '(', .name = "_immediate_paren" },
            .{ .at = '[', .name = "_immediate_bracket" },
            .{ .at = '{', .name = "_immediate_brace" },
            .{ .at = '"', .name = "_immediate_string_start" },
            .{ .at = '`', .name = "_immediate_command_start" },
        },
    },
    // php's string and backtick interiors: four terminals, one C function,
    // and no memory between them.
    //
    // `scan_encapsed_part_string` takes five arguments and only two of them
    // vary here - `is_after_variable` and `is_execution_string` - so the four
    // are four rows of data behind one walk, exactly as elixir's twenty and
    // julia's eight are. Neither argument is carried: the parse state supplies
    // both by naming one member rather than another, which is the definition
    // this file's `Part` was written for.
    //
    // **The other two members of the same function are deliberately absent.**
    // With `is_heredoc` true the first statement reads `scanner->heredocs`, a
    // stack of tags one token pushes and another spends, so
    // `encapsed_string_chars_heredoc` and its after-variable twin are a fence
    // and not a family. Seating them here would be the kotlin defect again:
    // one shape's walk quietly answering another shape's terminals.
    //
    // The roster is its own cohort. All four names are php's alone across the
    // thirty, and four arriving together is not a collision anyone can have by
    // accident; `sentinel_error` is `kin` anyway, because it is read at the
    // top of the same `scan()` and is php's alone too.
    //
    // Order is the specification's dispatch order in `scan()` - after-variable
    // before plain, encapsed before execution - and the census says that order
    // is load-bearing in one walk and decorative in the other. By shift no two
    // of the four are ever co-admitted (0 for all six pairs), so under
    // `Gather` the state names exactly one. In the permission set `drive`
    // hands a hand, `encapsed_string_chars` sits with its after-variable twin
    // in 3 states - state 386, `variable_name .` inside an interpolation,
    // where `->` and `[` are both live shifts and after-variable is the right
    // reading. So the order is what makes the union walk agree with the shift
    // walk instead of stopping a run one byte into a subscript.
    //
    // The rival pair is the same guard julia's row carries and it is needed
    // for the same reason. States 174 and 410 are bare folds -
    // `_simple_variable -> dynamic_variable_name .` and `variable_name -> $
    // name .` - whose lookahead row admits nearly every terminal in the
    // grammar, including all four of these, and they stand in ordinary code
    // after any `$foo`. A hand reading the union there would have answered
    // string content over the rest of the statement. You cannot be inside a
    // `"` string and a backtick string at once, so a state admitting both of
    // those is not inside either; the two real interiors keep their own pairs
    // apart (386 holds no execution terminal, 408 holds no encapsed one) and
    // are untouched by it.
    .{
        .anchor = "encapsed_string_chars",
        .kind = .marrow,
        .family = .php_encapsed,
        .rival = .{ "encapsed_string_chars", "execution_string_chars" },
        .roster = &.{
            .{ .name = "encapsed_string_chars_after_variable", .mark = .{ .shut = '"', .after = true } },
            .{ .name = "encapsed_string_chars", .mark = .{ .shut = '"' } },
            .{ .name = "execution_string_chars_after_variable", .mark = .{ .shut = '`', .after = true } },
            .{ .name = "execution_string_chars", .mark = .{ .shut = '`' } },
        },
        .kin = "sentinel_error",
    },
    // latex's raw regions: twelve terminals, one C function, and the close is a
    // string where every family before this one closed on a byte.
    //
    // `find_verbatim` takes a keyword and a boolean and reads nothing else, and
    // `external_scanner_create` returns NULL with an empty `serialize` - so the
    // twelve are twelve rows of data behind one walk on the same evidence php's
    // four were. The keyword arrives with the question: the state names
    // `_trivia_raw_env_minted` rather than `_trivia_raw_env_verbatim`, and that
    // *is* which `\end{…}` ends the run.
    //
    // `_trivia_raw_fi` is in the roster and not left out, which is the opposite
    // call from php's two heredoc members and made on the opposite evidence. The
    // heredoc pair's first statement reads a tag stack, so it is a fence wearing a
    // family's name; `\fi` reads the same keyword loop as the other eleven and
    // differs only in `is_command_name`, which is a parameter of that loop.
    //
    // `lone` rather than a `rival` pair, because latex's dispatcher is the
    // whole-roster rule outright: it counts live symbols across all twelve and
    // refuses on the second. Nothing here had to be inferred from a census.
    //
    // Order is the `TokenType` enum's, which is the grammar's own external
    // declaration order, because that is the order the dispatcher's `for` would
    // have resolved a tie in had it ever allowed one.
    .{
        .anchor = "_trivia_raw_env_verbatim",
        .kind = .marrow,
        .family = .latex_verbatim,
        .lone = true,
        .roster = &.{
            .{ .name = "_trivia_raw_fi", .mark = .{ .shut = '\\', .tail = "fi", .command = true } },
            .{ .name = "_trivia_raw_env_comment", .mark = .{ .shut = '\\', .tail = "end{comment}" } },
            .{ .name = "_trivia_raw_env_verbatim", .mark = .{ .shut = '\\', .tail = "end{verbatim}" } },
            .{ .name = "_trivia_raw_env_listing", .mark = .{ .shut = '\\', .tail = "end{lstlisting}" } },
            .{ .name = "_trivia_raw_env_minted", .mark = .{ .shut = '\\', .tail = "end{minted}" } },
            .{ .name = "_trivia_raw_env_asy", .mark = .{ .shut = '\\', .tail = "end{asy}" } },
            .{ .name = "_trivia_raw_env_asydef", .mark = .{ .shut = '\\', .tail = "end{asydef}" } },
            .{ .name = "_trivia_raw_env_pycode", .mark = .{ .shut = '\\', .tail = "end{pycode}" } },
            .{ .name = "_trivia_raw_env_luacode", .mark = .{ .shut = '\\', .tail = "end{luacode}" } },
            .{ .name = "_trivia_raw_env_luacode_star", .mark = .{ .shut = '\\', .tail = "end{luacode*}" } },
            .{ .name = "_trivia_raw_env_sagesilent", .mark = .{ .shut = '\\', .tail = "end{sagesilent}" } },
            .{ .name = "_trivia_raw_env_sageblock", .mark = .{ .shut = '\\', .tail = "end{sageblock}" } },
        },
    },
    // Lua's long strings and long comments. Both ends are external here, so
    // the hand answers all three parts; the level is read back out of the
    // bytes rather than carried.
    .{
        .anchor = "_block_string_start",
        .kind = .marrow,
        .vein = .lua_string,
        .opens = &.{"_block_string_start"},
        .body = "_block_string_content",
        .close = "_block_string_end",
        .kin = "_block_comment_start",
    },
    .{
        .anchor = "_block_comment_start",
        .kind = .marrow,
        .vein = .lua_comment,
        .opens = &.{"_block_comment_start"},
        .body = "_block_comment_content",
        .close = "_block_comment_end",
        .kin = "_block_string_start",
    },
    // Rust's ordinary string bodies. The opener is a pattern the parser lexes
    // and the escapes are the grammar's own rule, so only the run between them
    // is external; `float_literal` is the spec's own gate saying a bare quote
    // here is not a string at all.
    .{
        .anchor = "string_content",
        .kind = .marrow,
        .vein = .rust_string,
        .body = "string_content",
        .close = "string_close",
        .kin = "_line_doc_content",
        .hushed = &.{"float_literal"},
    },
    // HTML comments. `_implicit_end_tag` is the cohort; `comment` is the most
    // common external name in the population and means something different in
    // half of them.
    .{
        .anchor = "comment",
        .kind = .marrow,
        .vein = .html_comment,
        .body = "comment",
        .kin = "_implicit_end_tag",
    },
    // HTML's element ancestry, which is the rest of that same C function and
    // the whole of why `<p>hi</p>` did not parse: with `_start_tag_name`
    // unanswered, `p` is never a tag name and every byte between the brackets
    // falls to `text`.
    //
    // `opens` is ordered to match `lineage.Opener`, because the opener has to
    // say on the way out which of the three it was - html names the script and
    // style openers separately so the grammar can expect a raw body. The anchor
    // is `_implicit_end_tag` rather than one of the tag names: it is the one
    // spelling in this cohort that no other grammar in the population declares,
    // where `comment` is declared by half of them.
    .{
        .anchor = "_implicit_end_tag",
        .kind = .lineage,
        .line = .html,
        .opens = &.{ "_start_tag_name", "_script_start_tag_name", "_style_start_tag_name" },
        .body = "raw_text",
        .close = "_end_tag_name",
        .stray = "erroneous_end_tag_name",
        .implied = "_implicit_end_tag",
        .shut = "/>",
    },
    // Bash heredocs. The delimiter is read at the redirect and the body
    // begins a line later; `heredoc_redirect` spells the newline between them,
    // so the wait costs the carry nothing.
    .{
        .anchor = "heredoc_start",
        .kind = .fence,
        .dialect = .heredoc,
        .opens = &.{"heredoc_start"},
        .body = "_heredoc_body_beginning",
        .close = "heredoc_end",
    },
    .{
        .anchor = "_automatic_semicolon",
        .kind = .caesura,
        .body = "_automatic_semicolon",
        .kin = "_template_chars",
        .gate = "||",
        .sign = "_function_signature_automatic_semicolon",
        .hushed = &.{ "_template_chars", "jsx_text" },
    },
    // Swift, whose separator is two terminals for one decision: the line ended,
    // or the file said so. Nothing else in its member and statement rules
    // spells a separator, so without this row swift cannot read a second member
    // of anything - not even one written with a `;`.
    //
    // `_fake_try_bang` is the evidence. It is swift's alone in the thirty and
    // comes out of the same scanner function, where `_implicit_semi` alone
    // would be the anchor vouching for itself.
    .{
        .anchor = "_implicit_semi",
        .kind = .caesura,
        .tongue = .swift,
        .body = "_implicit_semi",
        .spelled = "_explicit_semi",
        .kin = "_fake_try_bang",
    },
    // Kotlin. One terminal for both, so `spelled` stays empty and the hand
    // answers `_automatic_semicolon` with a width where the file wrote a `;`.
    // `_by_delegation_hint` is kotlin's alone and comes from the same scanner;
    // the anchor is shared with javascript, php and scala, which is the whole
    // reason a caesura row needs kin.
    .{
        .anchor = "_automatic_semicolon",
        .kind = .caesura,
        .tongue = .kotlin,
        .body = "_automatic_semicolon",
        .kin = "_by_delegation_hint",
    },
    // elixir's line break, which is the opposite claim from the three above: not
    // that a statement ended, but that it *did not* - the next line resumes it
    // with a comment, a `do`, or a binary operator, and the grammar names one
    // terminal per reason.
    //
    // So there is no `body`. Three seams and no implied one, because a break
    // whose next line is none of the three is not a token at all here; the
    // grammar's extras eat it and nothing is owed. That is why this is the row
    // that made `seams` necessary rather than a fourth `Tongue` over `body`.
    //
    // Seated on the same soundness bar julia's family met: elixir's
    // `external_scanner_create` returns NULL, `serialize` returns 0, `deserialize`
    // is empty. A scanner with no memory cannot answer differently for having
    // been asked before.
    //
    // `_not_in` is the kin, and it is doing the same work `_fake_try_bang` does
    // for swift: the three seam names are elixir's alone in the thirty, but they
    // are also the entire cast, so the anchor would be vouching for itself. It
    // comes out of the same `scan` and stays blind, exactly as ecma's
    // `_template_chars` does.
    .{
        .anchor = "_newline_before_do",
        .kind = .caesura,
        .tongue = .elixir,
        .kin = "_not_in",
        .seams = brk: {
            var s: [Troupe.seats]([]const u8) = @splat("");
            s[@intFromEnum(caesura.Seam.comment)] = "_newline_before_comment";
            s[@intFromEnum(caesura.Seam.block)] = "_newline_before_do";
            s[@intFromEnum(caesura.Seam.operator)] = "_newline_before_binary_operator";
            break :brk s;
        },
    },
    // CSS's selector-versus-declaration colon, and the whitespace that is a
    // combinator. `__error_recovery` is the third name the same function
    // branches on and the spec refuses outright while it is wanted, which is
    // what `hushed` says.
    .{
        .anchor = "_pseudo_class_selector_colon",
        .kind = .scry,
        .sight = .css,
        .opens = &.{ "_descendant_operator", "_pseudo_class_selector_colon" },
        .hushed = &.{"__error_recovery"},
    },
    // TOML's line ending, which claims nothing, and its multiline strings,
    // whose closing run of quotes is told from their content by counting it.
    // One C function emits all five, so all five are the cast.
    .{
        .anchor = "_line_ending_or_eof",
        .kind = .scry,
        .sight = .toml,
        .opens = &.{
            "_line_ending_or_eof",
            "_multiline_basic_string_content",
            "_multiline_basic_string_end",
            "_multiline_literal_string_content",
            "_multiline_literal_string_end",
        },
    },
    // haskell's four extras, which are one region read four ways: a `--` run or
    // a `{-` opens the same span whether or not a `|` some spaces past the mark
    // makes it documentation, and `{-#` is a pragma rather than either.
    //
    // `kin` is doing real work here rather than decorating the row. These four
    // spellings are ordinary - three of the four are the commonest external
    // names in the population - so what says this grammar means *haskell's*
    // scanner by them is that it also declares haskell's layout algorithm,
    // which is read for its presence and never answered. The other forty-four
    // externals stay blind on purpose; see `scry`'s header for the measurement.
    .{
        .anchor = "haddock",
        .kind = .scry,
        .sight = .haskell,
        .kin = "_cmd_layout_start_do",
        .opens = &.{ "comment", "haddock", "cpp", "pragma" },
    },
};

/// Whether a resolved cast is the whole shape rather than a name collision.
///
/// Binding on the anchor alone is unsound, and it was not a theoretical worry:
/// kotlin declares `_string_start`, which is the anchor of the Ruby troupe, and
/// so was handed Ruby's six openers - `%w[`, `%i[`, a subshell - for a language
/// that has none of them. That is worse than an unanswered token, because it is
/// a confidently wrong one in a grammar nobody tested, and a name is all the
/// anchor test can ever look at.
///
/// A troupe is one language's convention taken whole, so the evidence that a
/// grammar follows it is that every part is present. A grammar declaring three
/// of Ruby's eight names does not mean Ruby by them; it means something of its
/// own that we have no account of, and the honest answer there is silence.
/// Requiring the full cast makes that structural rather than a hope that the
/// tables never collide.
/// The cast a grammar seats for one troupe, or null when it seats none.
///
/// `names` answers two questions about a spelling - `external` for the parts a
/// hand emits or requires as evidence, `terminal` for the ones it only reads
/// out of the permission set. Taking a resolver rather than a grammar is what
/// lets the binding test run this exact loop over the whole population: four
/// mis-bindings have now been caught by someone enumerating grammars by hand,
/// and an enumeration that runs the real code is the only kind that stays
/// caught.
pub fn provision(t: *const Troupe, names: anytype) ?Cast {
    if (names.external(t.anchor) == null) return null;
    var c: Cast = .{ .troupe = t };
    c.newline = names.external(t.newline);
    c.indent = names.external(t.indent);
    c.dedent = names.external(t.dedent);
    c.body = names.external(t.body);
    c.spelled = names.external(t.spelled);
    c.close = names.external(t.close);
    c.escape = names.external(t.escape);
    c.stray = names.external(t.stray);
    c.implied = names.external(t.implied);
    c.brace = names.external(t.brace);
    c.sever = names.external(t.sever);
    c.seal = names.external(t.seal);
    c.unbrace = names.external(t.unbrace);
    for (t.writs, 0..) |name, k| {
        if (k >= c.writs.len) break;
        c.writs[k] = names.external(name);
    }
    for (t.brackets, 0..) |b, k| {
        if (k >= c.brackets.len) break;
        c.brackets[k] = .{
            .open = names.external(b.open),
            .shut = names.external(b.shut),
        };
    }
    // html's is declared as the anonymous string `/>` rather than a named
    // terminal, so it is looked up across the whole set: the press keeps the
    // ordinary token for a spelling it can lex, and this hand has to answer for
    // it anyway because it is what pops the element.
    c.shut = names.terminal(t.shut);
    // Read from the whole terminal set rather than the externals, because what
    // the hand needs is the parse table's answer about a spelling and not who
    // lexes it. tree-sitter's `||` is declared external and is also an ordinary
    // operator token; the press keeps the ordinary one, and its being wanted is
    // the same fact the spec reads out of `valid_symbols[LOGICAL_OR]`.
    c.kin = names.external(t.kin);
    c.gate = names.terminal(t.gate);
    c.sign = names.terminal(t.sign);
    for (t.opens, 0..) |name, tag| c.opens[tag] = names.external(name);
    for (t.sigils, 0..) |name, k| {
        if (k >= c.sigils.len) break;
        c.sigils[k] = names.external(name);
    }
    for (t.roster, 0..) |part, k| c.roster[k] = names.external(part.name);
    for (t.shuts, 0..) |s, k| {
        if (k >= c.shuts.len) break;
        c.shuts[k] = names.external(s.name);
    }
    for (t.glued, 0..) |gl, k| {
        if (k >= c.glued.len) break;
        c.glued[k] = names.external(gl.name);
    }
    for (t.seams, 0..) |name, k| c.seams[k] = names.external(name);
    for (t.rival, 0..) |name, k| c.rival[k] = names.external(name);
    // A hushing terminal may be an ordinary anonymous token rather than an
    // external - python's are its brackets - so it is looked up in the whole
    // terminal set. It is read for its presence in the permission set and never
    // emitted, and it is a refinement rather than a part, so it is not required
    // for the cast to seat.
    for (t.hushed, 0..) |name, k| c.hushed[k] = names.terminal(name);
    // The anchor said this grammar might mean the troupe; the full cast is what
    // says it does. A partial match is a different language reusing a name, and
    // it gets nothing rather than someone else's shape.
    return if (seated(t, &c)) c else null;
}

pub fn seated(t: *const Troupe, c: *const Cast) bool {
    const named = [_]struct { name: []const u8, got: ?press.Symbol }{
        .{ .name = t.newline, .got = c.newline },
        .{ .name = t.indent, .got = c.indent },
        .{ .name = t.dedent, .got = c.dedent },
        .{ .name = t.body, .got = c.body },
        .{ .name = t.spelled, .got = c.spelled },
        .{ .name = t.close, .got = c.close },
        .{ .name = t.escape, .got = c.escape },
        .{ .name = t.kin, .got = c.kin },
        .{ .name = t.stray, .got = c.stray },
        .{ .name = t.implied, .got = c.implied },
        .{ .name = t.shut, .got = c.shut },
        .{ .name = t.brace, .got = c.brace },
        .{ .name = t.sever, .got = c.sever },
        .{ .name = t.seal, .got = c.seal },
        .{ .name = t.unbrace, .got = c.unbrace },
    };
    for (named) |p| if (p.name.len > 0 and p.got == null) return false;
    for (t.opens, 0..) |o, tag| if (o.len > 0 and c.opens[tag] == null) return false;
    // Half an interpolation is the worst outcome available: the marker that
    // resolved would open a span the one that did not could never be found
    // inside of.
    if (t.sigils.len > c.sigils.len) return false;
    for (t.sigils, 0..) |s, k| if (s.len > 0 and c.sigils[k] == null) return false;
    if (t.writs.len > c.writs.len) return false;
    for (t.writs, 0..) |w, k| if (w.len > 0 and c.writs[k] == null) return false;
    // Both halves of a bracket or neither. An open without its close pushes a
    // marker nothing can pop, and a marker on top of the stack suspends the
    // offside rule for every line after it - so a half-seated pair does not
    // lose one construct, it loses the file.
    if (t.brackets.len > c.brackets.len) return false;
    for (t.brackets, 0..) |b, k| {
        if (b.open.len == 0 and b.shut.len == 0) continue;
        const got = c.brackets[k];
        if (got.open == null or got.shut == null) return false;
    }
    if (t.roster.len > marrow.widest) return false;
    for (t.roster, 0..) |part, k| if (part.name.len > 0 and c.roster[k] == null) return false;
    // A family that emits its own close and cannot resolve one would answer
    // matter and then stall on the delimiter it just refused to eat, which is
    // a worse failure than not seating at all.
    if (t.shuts.len > c.shuts.len) return false;
    for (t.shuts, 0..) |s, k| if (s.name.len > 0 and c.shuts[k] == null) return false;
    // A marker cohort that seats partially is the worst of both: the members
    // that resolved would answer, and the constructs behind the members that
    // did not would wall in a state the resolved ones just changed.
    if (t.glued.len > c.glued.len) return false;
    for (t.glued, 0..) |gl, k| if (gl.name.len > 0 and c.glued[k] == null) return false;
    // A caesura seating some of its seams would answer the arms that resolved and
    // stay blind on the rest - and its arms are decided by the rule that asked,
    // so the ones left out are exactly the constructs nothing else can reach.
    for (t.seams, 0..) |name, k| if (name.len > 0 and c.seams[k] == null) return false;
    return true;
}

/// Whether any troupe claims this terminal name in a grammar that also
/// declares `anchor`. A claimed name is answered by a hand, so the roll must
/// not also seat a pattern for it.
pub fn claimed(t: *const Troupe, name: []const u8) bool {
    if (name.len == 0) return false;
    // `gate`, `sign`, `kin` and `hushed` are read from the permission set and
    // never emitted, so a hand does not answer them and must not claim them.
    const named = [_][]const u8{
        t.newline, t.indent,  t.dedent, t.body,  t.close, t.escape,
        t.stray,   t.implied, t.shut,   t.brace, t.sever, t.seal,
        t.unbrace, t.spelled,
    };
    for (named) |n| if (n.len > 0 and std.mem.eql(u8, n, name)) return true;
    for (t.opens) |n| if (std.mem.eql(u8, n, name)) return true;
    for (t.sigils) |n| if (n.len > 0 and std.mem.eql(u8, n, name)) return true;
    for (t.writs) |n| if (n.len > 0 and std.mem.eql(u8, n, name)) return true;
    for (t.brackets) |b| {
        if (b.open.len > 0 and std.mem.eql(u8, b.open, name)) return true;
        if (b.shut.len > 0 and std.mem.eql(u8, b.shut, name)) return true;
    }
    // `rival` is not here for the same reason `hushed` is not: it is read out
    // of the permission set and never answered.
    for (t.roster) |part| if (std.mem.eql(u8, part.name, name)) return true;
    for (t.shuts) |s| if (std.mem.eql(u8, s.name, name)) return true;
    for (t.glued) |gl| if (std.mem.eql(u8, gl.name, name)) return true;
    for (t.seams) |n| if (n.len > 0 and std.mem.eql(u8, n, name)) return true;
    return false;
}

/// A troupe with its terminal names resolved to this grammar's symbols. Built
/// once at compile so the scan never compares a string.
pub const Cast = struct {
    troupe: *const Troupe,
    newline: ?press.Symbol = null,
    indent: ?press.Symbol = null,
    dedent: ?press.Symbol = null,
    /// Parallel to `troupe.writs`, and read as a set: the hand asks how many of
    /// them the permission set admits, never which one by name.
    writs: [8]?press.Symbol = @splat(null),
    /// Parallel to `troupe.brackets`, holding only the two symbols. The frame
    /// each pair leaves is read back off `c.troupe.brackets[k]` at the offset a
    /// slot resolved at, exactly as `roster` reads its `mark` - a `Cast` field
    /// resolves spellings and nothing else, and duplicating the frame here gave
    /// one fact two homes that could disagree.
    brackets: [4]struct { open: ?press.Symbol = null, shut: ?press.Symbol = null } = @splat(.{}),
    brace: ?press.Symbol = null,
    sever: ?press.Symbol = null,
    seal: ?press.Symbol = null,
    unbrace: ?press.Symbol = null,
    hushed: [4]?press.Symbol = @splat(null),
    kin: ?press.Symbol = null,
    gate: ?press.Symbol = null,
    sign: ?press.Symbol = null,
    opens: [fence.tags]?press.Symbol = @splat(null),
    /// Parallel to `troupe.sigils`, and read by the index `fence.Sigil` gives.
    sigils: [fence.sigils]?press.Symbol = @splat(null),
    /// Parallel to `troupe.roster`, so the hand reads a mark by the index it
    /// found a symbol at and never compares a string. Named for the field it
    /// resolves, because the fixture that seats every troupe pairs the two
    /// structs by field name.
    roster: [marrow.widest]?press.Symbol = @splat(null),
    /// Parallel to `troupe.shuts`, found by the shut character rather than by
    /// the roster index, because two closes serve eight parts.
    shuts: [4]?press.Symbol = @splat(null),
    /// Parallel to `troupe.glued`, so the hand reads the byte at the offset and
    /// finds the marker by the index the character sat at.
    glued: [Troupe.glues]?press.Symbol = @splat(null),
    /// Parallel to `troupe.seams` and indexed by `caesura.Seam`, so the hand
    /// emits the arm the rule decided rather than the first one that resolved.
    seams: [Troupe.seats]?press.Symbol = @splat(null),
    rival: [2]?press.Symbol = @splat(null),
    body: ?press.Symbol = null,
    spelled: ?press.Symbol = null,
    close: ?press.Symbol = null,
    escape: ?press.Symbol = null,
    stray: ?press.Symbol = null,
    implied: ?press.Symbol = null,
    shut: ?press.Symbol = null,
};

/// The zero-width answers already given at one offset, and why that is a proof
/// rather than a heuristic.
///
/// # The problem
///
/// Every other token in this parser bounds its own repetition: it consumes a
/// byte, the cursor moves, and the next ask is a different question. A
/// zero-width token consumes nothing, so if the parser can ask the same
/// question twice it can ask it forever. That is not hypothetical - it is what
/// a hand answering unconditionally does on its second ask.
///
/// # What used to stand here, and the hole in it
///
/// A single slot holding the last `(offset, symbol, shape)`, refusing an exact
/// repeat of it. That refuses `A A` and it does not refuse `A B A`: the second
/// answer overwrote the slot that would have caught the third. Nothing in the
/// tree reached it, because every zero-width hand seated before now either
/// moves a stack - python's dedents pop a column, html's implied closes pop a
/// tag - or is the only member that can answer at its offset. A cohort of five
/// memoryless markers is the first arrival for which one slot is not enough,
/// and finding a spin by running one is not a proof either way.
///
/// # The termination argument
///
/// Three facts, and the conclusion is arithmetic:
///
///  1. **The offset never goes backwards.** The walk resumes each token from
///     the end of the last, so `at` is monotone and bounded by the file.
///  2. **A hit with extent advances it.** `step` returns those without
///     consulting this ledger at all, because the cursor moving *is* the proof.
///  3. **A hit without extent is counted, and the count has a ceiling.** Every
///     zero-width answer accepted at one offset adds one to `total`; at
///     `ceiling` the answer is refused whatever it is.
///
/// So the zero-width answers over a file of `n` bytes number at most
/// `ceiling * (n + 1)`, and the parse terminates. The bound does not depend on
/// any grammar, on which hands are seated, or on what a hand promises about
/// itself - which is the property the old slot could not offer.
///
/// # The second arm, which is quality rather than termination
///
/// A ceiling alone terminates by exhaustion: a two-cycle would emit 256 junk
/// tokens and then stop. So within one `(offset, shape)` the ledger also holds
/// the symbols already answered and refuses a repeat on sight. Memory moving
/// clears that arm, because a stack that pushed or popped has made the question
/// genuinely different - which is precisely what lets a run of dedents through
/// while `A B A` at one unmoved shape is refused.
///
/// # The sizes
///
/// `ceiling` clears every legitimate run: the longest is a file closing its
/// blocks at EOF, bounded by `offside.Columns.max` at 96, then
/// `lineage.Tags.max` at 64 and `fence.Spans.max` at 16. `cohort` bounds the
/// distinct symbols one *unmoved* shape may answer, where the real number is
/// one - the abut cohort keys on disjoint bytes, and every other zero-width
/// hand moves a stack per answer. A full `cohort` refuses, so the smaller
/// number is fail-closed rather than a silent overwrite.
pub const Spent = struct {
    pub const ceiling = 256;
    pub const cohort = 8;

    /// The offset these records belong to. A hit that moves the cursor retires
    /// them by moving this, which is why the bound above is per offset.
    at: u32 = 0,
    /// The memory shape `syms` was recorded under. A different shape is a
    /// different question at the same offset, so the symbols reset and the
    /// total does not.
    shape: u64 = 0,
    total: u16 = 0,
    len: u8 = 0,
    /// Past `len` this is `undefined`, like every other stack here, so `same`
    /// compares the live prefix and never the array.
    syms: [cohort]press.Symbol = undefined,

    /// Whether this exact zero-extent answer already stands at this offset.
    pub fn held(s: *const Spent, at: u32, shape: u64, sym: press.Symbol) bool {
        if (s.at != at or s.shape != shape) return false;
        for (s.syms[0..s.len]) |seen| if (seen == sym) return true;
        return false;
    }

    /// Record one zero-width answer, or refuse it. False means the loop has
    /// already been here and `step` must return null.
    fn admit(s: *Spent, at: u32, shape: u64, sym: press.Symbol) bool {
        if (s.at != at) s.* = .{ .at = at, .shape = shape };
        if (s.total == ceiling) return false;
        if (s.shape != shape) {
            s.shape = shape;
            s.len = 0;
        } else {
            for (s.syms[0..s.len]) |seen| if (seen == sym) return false;
        }
        if (s.len == cohort) return false;
        s.syms[s.len] = sym;
        s.len += 1;
        s.total += 1;
        return true;
    }

    fn same(a: *const Spent, b: *const Spent) bool {
        return a.at == b.at and a.shape == b.shape and a.total == b.total and
            a.len == b.len and std.mem.eql(press.Symbol, a.syms[0..a.len], b.syms[0..b.len]);
    }
};

/// The memory a scan carries between tokens.
///
/// Two stacks and a loop guard, all of fixed size, so the seam allocates
/// nothing and cannot fail. It belongs to the run rather than to the compiled
/// scanner: one scanner reads many files, and a stack left over from the last
/// one would open every block in the next.
pub const Carry = struct {
    columns: offside.Columns = .{},
    spans: fence.Spans = .{},
    tags: lineage.Tags = .{},
    /// The zero-width answers already given at one offset.
    ///
    /// A hand that consumes nothing has not moved the cursor, so the next ask
    /// is the same question and something other than the cursor has to bound
    /// the repeat. This is that bound, and it is the whole reason a hand may
    /// answer where the slate may not. See `Spent` for the termination
    /// argument; it is short and it is the point of the field.
    spent: Spent = .{},

    /// Begin a file.
    pub fn rewind(c: *Carry) void {
        c.columns.reset();
        c.spans.reset();
        c.tags.reset();
        c.spent = .{};
    }

    /// Whether two carries are the same lexical state.
    ///
    /// Use this and never `std.meta.eql` on a `Carry`: every stack is a
    /// fixed-capacity array with a live prefix, and everything past that
    /// prefix is `undefined`. The stacks answer for their own dead bytes; so
    /// does the ledger.
    pub fn same(a: *const Carry, b: *const Carry) bool {
        return a.columns.same(&b.columns) and
            a.spans.same(&b.spans) and
            a.tags.same(&b.tags) and
            a.spent.same(&b.spent);
    }

    /// Whether this exact zero-extent answer has already been given here.
    ///
    /// A hand that offers several members over one region has to ask before it
    /// offers a zero-extent one, because `step` will refuse the repeat and
    /// return null - and a null from the hand is not the same as a null from
    /// the *branch*, so the members behind it would never be reached. lua's
    /// `[[]]` is the case: an empty body answered once at the offset its close
    /// also starts at, and then the close waiting behind a branch that keeps
    /// winning. A hand offering one member per offset never needs this; for it
    /// `step`'s refusal is the whole rule.
    pub fn answered(c: *const Carry, at: u32, sym: press.Symbol) bool {
        return c.spent.held(at, c.shape(), sym);
    }

    /// Every stack's depth in one word, which is what `step` compares to decide
    /// whether a zero-width answer made progress. A stack absent from this is a
    /// stack whose pops cannot be told apart, so html's implied closes - all
    /// zero-width, one pop each - would be refused after the first.
    fn shape(c: *const Carry) u64 {
        return (@as(u64, c.columns.depth()) << 32) |
            (@as(u64, c.spans.depth()) << 16) |
            c.tags.depth();
    }
};

/// What a hand answered with.
///
/// `skip` is the bytes between the offset the hand was asked at and where the
/// token begins, which is tree-sitter's `advance(lexer, true)`: bytes the
/// scanner stepped over without claiming. A hand that consumes what it reads
/// leaves it zero, and every hand written before css did.
pub const Hit = struct { symbol: press.Symbol, len: u32, skip: u32 = 0 };

/// Ask every bound hand, in the order the specifications imply, for a token at
/// `at`. Null means none of them claims this offset and the slate should try.
///
/// The order is three phases and is not per-language: what is inside an open
/// span first (its body owns those bytes until it says otherwise), then the
/// line's layout, then a new span opening. Python's own scanner is written in
/// exactly that order, and Ruby, which has no layout, skips the middle.
///
/// `fresh` says no extra has been stepped over since the last token ended, and
/// two phases read it: the layout one and the caesura. That split is the
/// specifications': Python's scanner measures the whitespace itself and so must
/// be asked before anything eats it, and a caesura is a question about the
/// whitespace between two tokens, so an offset the extras already moved past
/// has none left to read. Ruby's and Rust's openers instead begin by skipping
/// whitespace, so they have to be reachable at an offset the extras moved to; a
/// hand asked only at fresh offsets would never see `let s = r#"..."#`.
pub fn step(
    casts: []const Cast,
    carry: *Carry,
    bytes: []const u8,
    at: u32,
    fresh: bool,
    wanted: *const std.DynamicBitSetUnmanaged,
    named: *const std.DynamicBitSetUnmanaged,
) ?Hit {
    const hit = offer(casts, carry, bytes, at, fresh, wanted, named) orelse return null;
    // Skipped bytes count as progress for the same reason consumed ones do:
    // the cursor ends past where it started, so the next ask is a different
    // question and the ledger below is not needed to say so.
    if (hit.skip + hit.len > 0) return hit;
    // No cursor movement, so the ledger is the only thing standing between
    // this answer and a spin. It is written only here, which keeps every hand
    // free of the bookkeeping.
    if (!carry.spent.admit(at, carry.shape(), hit.symbol)) return null;
    return hit;
}

fn offer(
    casts: []const Cast,
    carry: *Carry,
    bytes: []const u8,
    at: u32,
    fresh: bool,
    wanted: *const std.DynamicBitSetUnmanaged,
    named: *const std.DynamicBitSetUnmanaged,
) ?Hit {
    // At the end of input a hand still has answers - the dedents a file owes
    // for every block it left open - so `at == bytes.len` is in bounds here on
    // purpose, and only past it is not.
    if (at > bytes.len) return null;
    if (carry.spans.innermost()) |span| {
        for (casts) |*c| {
            if (c.troupe.kind != .fence or c.troupe.dialect != span.dialect) continue;
            if (inside(c, carry, span, bytes, at, wanted)) |h| return h;
        }
    }
    if (fresh) for (casts) |*c| {
        if (c.troupe.kind != .offside) continue;
        if (layout(c, casts, carry, bytes, at, wanted)) |h| return h;
    };
    // Not gated on `fresh`, unlike the offside rule: this hand measures the line
    // ending itself rather than being told about one, because a `}` and a `{` are
    // answers it owes anywhere.
    for (casts) |*c| {
        if (c.troupe.kind != .writ) continue;
        if (tested(c, carry, bytes, at, wanted)) |h| return h;
        // The forced half of the warrant. `named` is the state's own shiftable
        // admissions with the extras taken back out, so an order standing alone
        // in it is one no other terminal competes with at all - and `Gather.offer`
        // already ran the folds, so what is left is genuinely a shift. Asked
        // before the slate because there is nothing for the slate to say: this is
        // `do`'s block opening over the expression that follows it.
        if (sole(c, wanted, named)) |sym| {
            if (raise(carry, bytes, at)) return .{ .symbol = sym, .len = 0 };
        }
    }
    for (casts) |*c| {
        if (c.troupe.kind != .fence) continue;
        if (opening(c, carry, bytes, at, wanted)) |h| return h;
    }
    // Above `marrow` because html's raw body outranks html's comment at the
    // same offset, and that ordering is the spec's first line rather than a
    // preference: `<script><!--x--></script>` is four bytes of raw text and a
    // comment nobody lexed, because inside a script nothing is a comment.
    for (casts) |*c| {
        if (c.troupe.kind != .lineage) continue;
        if (enclosing(c, carry, bytes, at, wanted)) |h| return h;
    }
    // Last, because a bounded run is the only hand whose bytes the parser has
    // already walked into: it fires at an offset the grammar's own opening
    // terminal just left, so anything that could still be opening a span here
    // has the earlier claim.
    for (casts) |*c| {
        if (c.troupe.kind != .marrow) continue;
        if (bounded(c, carry, bytes, at, wanted)) |h| return h;
    }
    // A lookahead that claims at most one byte, so it sits below every hand
    // that claims a run and above the one that claims none. Not gated on
    // `fresh`: its whitespace branch tests the byte at `at` itself, so an
    // offset the extras already moved past declines it without being told.
    for (casts) |*c| {
        if (c.troupe.kind != .scry) continue;
        if (sighted(c, bytes, at, wanted)) |h| return h;
    }
    // Dead last, and the ordering is the spec's as well as the sensible one: a
    // token that consumes bytes has a claim on this offset that a token
    // consuming none cannot outrank. tree-sitter's own dispatcher answers the
    // template body and JSX text before it ever reaches the semicolon.
    if (fresh) for (casts) |*c| {
        if (c.troupe.kind != .caesura) continue;
        if (unwritten(c, bytes, at, wanted)) |h| return h;
    };
    // Below even the caesura, and the census is what put it here rather than a
    // preference. A caesura at least skips the whitespace it decided on; this
    // hand moves nothing at all, so every other claim on the offset outranks
    // it by the same rule that ranks a caesura last.
    if (fresh) for (casts) |*c| {
        if (c.troupe.kind != .abut) continue;
        if (glued(c, carry, bytes, at, wanted)) |h| return h;
    };
    return null;
}

/// A marker for a delimiter that is touching the token before it.
///
/// `f(x)` is a call and `f (x)` is not, and the only difference is a byte of
/// whitespace nobody consumes. Julia spells that difference as five zero-width
/// externals sitting between the callee and its bracket - `call_expression` is
/// literally `_primary _immediate_paren tuple_expression` - so the hand answers
/// a token of no width and lets the grammar's own terminal eat the bracket.
///
/// Three vetoes, each earning its line:
///
///   * **`fresh`**, applied by the caller, because adjacency *is* the claim.
///     An offset the extras have moved to had whitespace in front of it, which
///     is exactly the reading this marker denies.
///   * **`at > 0`**, because `fresh` is vacuously true at the start of a file
///     and a leading `(` has nothing to be glued to.
///   * **no open span**, because inside a fenced body every one of these bytes
///     is matter rather than syntax. It fires for no language seated today -
///     julia's interiors are a `marrow` family and push no span - so it is an
///     invariant stated for the next language rather than a measured guard.
///
/// The permission set is read as `wanted` and not as `named` on purpose. A
/// marker is a token like any other to the parser: where the state can only
/// fold on it, the folds run and a state that shifts it is on the other side.
/// `_immediate_paren` is a shift in 20 states and a reduce-lookahead in 239,
/// and reading only the first would refuse the marker in the states that reach
/// the call through a reduction.
///
/// **What actually keeps this hand off a string's closing quote is that test,
/// and not the phase.** The census reads like the phase matters -
/// `_immediate_string_start` and `_end_str` are keyed to the same `"` and are
/// co-admitted in the permission set at state 1, where 103 terminals fold to
/// `_word_identifier` - so the placement below was chosen against it. Running
/// the hand from the *first* phase instead was then measured, and julia's
/// board did not move by a byte, nor did any probe written to provoke it. The
/// parser never stands in state 1 at a quote. So the ordering is the rule this
/// file already applies (a hand that moves nothing outranks nothing) and a
/// defence against a table shape that exists, and it is honestly not what is
/// carrying julia today.
fn glued(
    c: *const Cast,
    carry: *const Carry,
    bytes: []const u8,
    at: u32,
    wanted: *const std.DynamicBitSetUnmanaged,
) ?Hit {
    if (at == 0 or at >= bytes.len) return null;
    if (carry.spans.depth() > 0) return null;
    for (c.troupe.glued, 0..) |gl, k| {
        if (gl.at != bytes[at]) continue;
        const sym = c.glued[k] orelse return null;
        return if (wanted.isSet(sym)) .{ .symbol = sym, .len = 0 } else null;
    }
    return null;
}

/// A terminator the line implies, and the one it spells.
///
/// Asked only at a fresh offset, because the decision is about the whitespace
/// between two tokens and an offset the extras have already moved past has
/// none left to read. `caesura.zig` holds the rules; everything here is the
/// translation between the parser's expected set and the questions those rules
/// put to it.
///
/// Both terminals must be wanted where the grammar names both, which is the
/// scanner's own `valid_symbols[IMPLICIT_SEMI] && valid_symbols[EXPLICIT_SEMI]`
/// and not a convenience: swift's two are one decision reached two ways, and a
/// state admitting only one of them is not the state that decision is for.
///
/// **A tongue that answers several terminals is gated per arm instead**, and the
/// asymmetry is the two shapes' own. swift's pair is one decision, so requiring
/// both is requiring the state. elixir's three are three decisions - a comment, a
/// block, an operator - and its own specification reads each out of
/// `valid_symbols` separately, three lines apart. Requiring all three would
/// refuse every state that expects only one, which is nearly all of them.
fn unwritten(
    c: *const Cast,
    bytes: []const u8,
    at: u32,
    wanted: *const std.DynamicBitSetUnmanaged,
) ?Hit {
    if (hushed(c, wanted)) return null;
    var ask: caesura.Asks = .{ .binary = want(wanted, c.gate), .signature = want(wanted, c.sign) };
    // A one-terminal tongue answers `body`, and its permission is the gate on
    // the whole hand. A several-terminal one has no `body` at all: each arm
    // carries its own permission into the rules and back out as a `Seam`.
    var body: ?press.Symbol = null;
    if (c.body) |sym| {
        if (!wanted.isSet(sym)) return null;
        if (c.spelled) |w| if (!wanted.isSet(w)) return null;
        body = sym;
    } else {
        ask.comment = want(wanted, c.seams[@intFromEnum(caesura.Seam.comment)]);
        ask.block = want(wanted, c.seams[@intFromEnum(caesura.Seam.block)]);
        ask.operator = want(wanted, c.seams[@intFromEnum(caesura.Seam.operator)]);
    }
    const b = caesura.breaks(c.troupe.tongue, bytes, at, ask) orelse return null;
    // A spelled separator is a different terminal where the grammar has one,
    // and the same one with a width where it does not. An arm the rules chose is
    // resolved rather than defaulted: the rules only reach an arm whose ask was
    // true, so a null here would be a binding fault and not a state.
    const which = switch (b.seam) {
        .only => if (b.spelled) (c.spelled orelse body.?) else body.?,
        else => c.seams[@intFromEnum(b.seam)] orelse return null,
    };
    return .{ .symbol = which, .len = b.len, .skip = b.skip };
}

/// html's element ancestry: six parts behind one dispatch.
///
/// One function rather than a phase per part, because the parts are not ranked
/// against each other - they are *arms of a single decision* the specification
/// makes by looking at one byte. A close and an implied close and a raw body
/// are all answers to "what is at this `<`", and splitting them into phases
/// would invent a precedence the specification does not have.
///
/// The order below is that dispatch, transcribed. Two details of it are load
/// bearing and neither is obvious:
///
///   * **The raw body is decided before whitespace is skipped**, so a script
///     body owns its own leading blanks, and it is decided by the *expected
///     set* rather than by the bytes: raw text is the answer exactly where
///     neither tag name is legal.
///   * **Everything past the `<` is lookahead.** The specification marks the
///     token's end at the `<` and then reads forward to decide, so an implied
///     close is zero-width there however many bytes it had to read - which is
///     `Hit`'s `skip + len` at its narrowest, both fields zero once the
///     whitespace is gone.
fn enclosing(
    c: *const Cast,
    carry: *Carry,
    bytes: []const u8,
    at: u32,
    wanted: *const std.DynamicBitSetUnmanaged,
) ?Hit {
    const opening_wanted = want(wanted, c.opens[0]);
    const closing_wanted = want(wanted, c.close);
    if (c.body) |sym| {
        if (wanted.isSet(sym) and !opening_wanted and !closing_wanted) {
            // Nothing open means nothing knows which mark ends the body, and
            // the specification refuses outright rather than falling through to
            // the arms below.
            const shut = lineage.raw(&carry.tags) orelse return null;
            return .{ .symbol = sym, .len = lineage.reach(shut, bytes, at) };
        }
    }
    var i = at;
    while (i < bytes.len and std.ascii.isWhitespace(bytes[i])) i += 1;
    const skip = i - at;
    // Past the last byte is the specification's `lookahead == '\0'` arm, which
    // exists so a document may omit `</body></html>` as most do.
    if (i >= bytes.len) return implies(c, carry, bytes, i, skip, wanted);
    switch (bytes[i]) {
        // A comment is the same `<` read by a different hand, and this one
        // declines rather than racing it: the specification routes `<!` away
        // before it ever consults the ancestry.
        '<' => {
            if (i + 1 < bytes.len and bytes[i + 1] == '!') return null;
            return implies(c, carry, bytes, i, skip, wanted);
        },
        '/' => {
            const sym = c.shut orelse return null;
            if (!wanted.isSet(sym)) return null;
            if (i + 1 >= bytes.len or bytes[i + 1] != '>') return null;
            // The specification answers here even with nothing to pop, without
            // saying which terminal it answered; that is a stale symbol rather
            // than a decision, so this declines instead of reproducing it.
            if (carry.tags.depth() == 0) return null;
            carry.tags.pop();
            return .{ .symbol = sym, .len = 2, .skip = skip };
        },
        else => {
            if (!opening_wanted and !closing_wanted) return null;
            if (c.body) |sym| if (wanted.isSet(sym)) return null;
            if (opening_wanted) return begins(c, carry, bytes, i, skip, wanted);
            return ends(c, carry, bytes, i, skip);
        },
    }
}

/// A tag name that opens an element, and which of the three openers it is.
fn begins(
    c: *const Cast,
    carry: *Carry,
    bytes: []const u8,
    at: u32,
    skip: u32,
    wanted: *const std.DynamicBitSetUnmanaged,
) ?Hit {
    const it = lineage.open(c.troupe.line, bytes, at) orelse return null;
    const sym = c.opens[@intFromEnum(it.which)] orelse return null;
    // The specification guards this arm on the plain opener alone and then
    // emits whichever of the three the name turned out to be. Requiring the one
    // it emits keeps a state that admits only some of them from being handed a
    // token it would reject; where all three are admitted together, as html's
    // grammar makes them, the guard costs nothing.
    if (!wanted.isSet(sym)) return null;
    if (!carry.tags.push(it.tag)) return null;
    return .{ .symbol = sym, .len = it.len, .skip = skip };
}

/// A tag name that closes an element, or fails to and is a different terminal
/// for it.
fn ends(c: *const Cast, carry: *Carry, bytes: []const u8, at: u32, skip: u32) ?Hit {
    const it = lineage.close(&carry.tags, bytes, at) orelse return null;
    if (it.matched) {
        const sym = c.close orelse return null;
        carry.tags.pop();
        return .{ .symbol = sym, .len = it.len, .skip = skip };
    }
    // A mismatch is a token over the same bytes and pops nothing: the element
    // it failed to close is still open, and the parser recovers around the
    // stray rather than around a hole.
    const sym = c.stray orelse return null;
    return .{ .symbol = sym, .len = it.len, .skip = skip };
}

/// The close the ancestry owes before the next tag can open.
fn implies(
    c: *const Cast,
    carry: *Carry,
    bytes: []const u8,
    at: u32,
    skip: u32,
    wanted: *const std.DynamicBitSetUnmanaged,
) ?Hit {
    const sym = c.implied orelse return null;
    if (!wanted.isSet(sym)) return null;
    if (!lineage.implied(&carry.tags, bytes, at)) return null;
    carry.tags.pop();
    return .{ .symbol = sym, .len = 0, .skip = skip };
}

/// A run of content whose end is computed from where it starts.
///
/// Mutates nothing and needs no span - see `marrow.zig` for why the captured
/// close does not have to be remembered. It reads `carry` all the same, for one
/// reason and only ever to ask a question: a body may be empty, and this is the
/// one hand that offers several members over a single offset, so it has to know
/// whether the zero-extent one has already been given before it offers it
/// again. `Carry.answered` states that case; lua's `[[]]` is it.
fn bounded(
    c: *const Cast,
    carry: *const Carry,
    bytes: []const u8,
    at: u32,
    wanted: *const std.DynamicBitSetUnmanaged,
) ?Hit {
    if (c.troupe.roster.len > 0) return spelt(c, bytes, at, wanted);
    if (c.body) |sym| {
        if (wanted.isSet(sym)) {
            // A body of zero bytes is legal - lua's `[[]]` has one - and the
            // close starts at the same offset, so the branch must fall through
            // once the body has been answered rather than keep winning.
            if (marrow.reach(c.troupe.vein, bytes, at)) |n| {
                if (n > 0 or !carry.answered(at, sym)) return .{ .symbol = sym, .len = n };
            }
        }
    }
    if (c.close) |sym| {
        if (wanted.isSet(sym)) {
            if (marrow.shut(c.troupe.vein, bytes, at)) |n| return .{ .symbol = sym, .len = n };
        }
    }
    if (c.opens[0]) |sym| {
        if (c.troupe.vein != .cpp_raw and wanted.isSet(sym)) {
            if (marrow.open(c.troupe.vein, bytes, at)) |n| return .{ .symbol = sym, .len = n };
        }
    }
    // C++'s delimiter appears on both sides of the content and is the only
    // member of a marrow cast this hand answers as well as requires.
    if (c.troupe.vein == .cpp_raw) {
        if (c.opens[0]) |sym| {
            if (wanted.isSet(sym)) {
                if (marrow.tag(bytes, at)) |n| return .{ .symbol = sym, .len = n };
            }
        }
    }
    return null;
}

/// A run whose close the parse state named, by asking for one member of a
/// family rather than another.
///
/// Two questions and no bytes read between them. First whether the state is
/// inside the family at all: the members are mutually exclusive, so a state
/// admitting `rival` - both of the two that can begin at the same offset - is
/// reading ordinary code that *could* open a quote and is not inside one. Then
/// which member, which is the first the state admits, in the specification's
/// own table order.
///
/// The mark that comes back is the whole of what distinguishes twenty terminals
/// from each other, so everything past this point is `marrow.walk` and is the
/// same code for all of them.
///
/// A family whose walk emits its own close answers it from the same pass, and
/// only when the state also admits the part that would have carried matter
/// there. That last clause is a deliberate narrowing of the specification,
/// which emits `_end_str` without consulting the permission set at all: the
/// census says the close is shiftable in exactly the eight states one content
/// terminal is shiftable in and in no other, so the narrowing costs nothing
/// measured and keeps the hand from handing back a token the state would have
/// to reject.
fn spelt(
    c: *const Cast,
    bytes: []const u8,
    at: u32,
    wanted: *const std.DynamicBitSetUnmanaged,
) ?Hit {
    var rivals: u8 = 0;
    for (c.rival) |maybe| {
        const sym = maybe orelse continue;
        if (wanted.isSet(sym)) rivals += 1;
    }
    if (rivals == c.rival.len) return null;
    // The whole-roster form of the same refusal. Counted rather than short-
    // circuited so the loop is the specification's own walk over all twelve.
    if (c.troupe.lone) {
        var live: u8 = 0;
        for (c.roster) |maybe| {
            const sym = maybe orelse continue;
            if (wanted.isSet(sym)) live += 1;
        }
        if (live > 1) return null;
    }

    for (c.roster, 0..) |maybe, k| {
        const sym = maybe orelse continue;
        if (!wanted.isSet(sym)) continue;
        const mark = c.troupe.roster[k].mark;
        switch (marrow.walk(c.troupe.family, mark, bytes, at)) {
            .matter => |n| return .{ .symbol = sym, .len = n },
            .close => |n| {
                const end = shutOf(c, mark.shut) orelse return null;
                if (!wanted.isSet(end)) return null;
                return .{ .symbol = end, .len = n };
            },
            .none => return null,
        }
    }
    return null;
}

/// The close a family spells for one shut character, or null where it spells
/// none. Two entries at most, so the scan is cheaper than the index would be.
fn shutOf(c: *const Cast, at: u8) ?press.Symbol {
    for (c.troupe.shuts, 0..) |s, k| {
        if (s.at == at and k < c.shuts.len) return c.shuts[k];
    }
    return null;
}

/// The bytes an open span accounts for: its escape, its body, or its close.
fn inside(
    c: *const Cast,
    carry: *Carry,
    span: *const fence.Span,
    bytes: []const u8,
    at: u32,
    wanted: *const std.DynamicBitSetUnmanaged,
) ?Hit {
    // The spec's error-recovery guard: a state that wants a string body *and*
    // an indent at once is the parser flailing, and the scanner stands down
    // rather than committing to either.
    if (c.indent) |i| if (want(wanted, c.body) and wanted.isSet(i)) return null;
    switch (fence.read(span, bytes, at)) {
        .escape => |n| if (c.escape) |sym| {
            if (wanted.isSet(sym)) return .{ .symbol = sym, .len = n };
        },
        .body => |n| if (c.body) |sym| {
            if (wanted.isSet(sym)) return .{ .symbol = sym, .len = n };
        },
        .enters => |e| if (c.sigils[@intFromEnum(e.which)]) |sym| {
            // No push and no pop: the span stays open underneath the
            // interpolation, which is the whole reason `"${"$n"}"` can be read
            // at all. The inner string pushes its own through `opening`, and
            // every offset in between finds this hand declining because the
            // state inside an expression wants neither a body nor a close.
            if (wanted.isSet(sym)) return .{ .symbol = sym, .len = e.len };
        },
        .close => |n| {
            // Ruby's six openers share one `_string_end`; a dialect that names
            // its closer per opener would read `span.tag` here too.
            const sym = c.close orelse c.opens[span.tag] orelse return null;
            if (!wanted.isSet(sym)) return null;
            carry.spans.pop();
            return .{ .symbol = sym, .len = n };
        },
        .none => {},
    }
    return null;
}

/// The offside rule, in the order tree-sitter-python's scanner applies it:
/// deeper opens a block, shallower closes one, and otherwise a fresh line ends
/// a statement.
fn layout(
    c: *const Cast,
    casts: []const Cast,
    carry: *Carry,
    bytes: []const u8,
    at: u32,
    wanted: *const std.DynamicBitSetUnmanaged,
) ?Hit {
    const lead = offside.lead(bytes, at, c.troupe.note);
    // A backslash that continued into something other than a line ending is
    // malformed, and the spec answers by declining rather than guessing.
    if (lead.broken or !lead.fresh) return null;

    const here = carry.columns.top();
    if (c.indent) |sym| {
        if (wanted.isSet(sym) and lead.column > here and carry.columns.open(lead.column)) {
            return .{ .symbol = sym, .len = 0 };
        }
    }
    if (c.dedent) |sym| dedent: {
        if (lead.column >= here or carry.columns.depth() <= 1) break :dedent;
        // Inside a format string an unindented line is the interpolation's, not
        // the block's, so no dedent is owed.
        if (carry.spans.innermost()) |span| if (span.format) break :dedent;
        // A comment indented with the block it follows defers the dedent, so
        // that a comment trailing a block is not read as leaving it.
        if (lead.comment) |col| if (col >= here) break :dedent;
        // Not wanted outright, but owed anyway when nothing else can end the
        // line: not a statement end, not a string about to open, not inside
        // brackets. This is the clause that unwinds a block before `else`.
        if (!wanted.isSet(sym)) {
            if (want(wanted, c.newline)) break :dedent;
            if (hushed(c, wanted)) break :dedent;
            if (lead.at < bytes.len and opensAString(casts, wanted, bytes[lead.at])) break :dedent;
        }
        carry.columns.close();
        return .{ .symbol = sym, .len = 0 };
    }
    if (c.newline) |sym| {
        if (wanted.isSet(sym)) return .{ .symbol = sym, .len = 0 };
    }
    return null;
}

/// Read the stack a `.writ` order filled: the pop, the separator, and the brace.
///
/// The half of the protocol that rests on Landin's argument. `standing` is three
/// arms of one comparison between the measured column and the frame's, so at most
/// one can hold and every live reading gets the same answer from the same memory
/// - which is exactly why co-admission with forty-five ordinary tokens is
/// harmless here and why this half is asked before the slate, like `.offside`.
///
/// The braces are in this pass rather than with the orders because both are
/// byte-determined outright: a `{` is present or it is not, and a frame it opened
/// is closed by its `}` and by no column. Neither needs the warrant.
fn tested(
    c: *const Cast,
    carry: *Carry,
    bytes: []const u8,
    at: u32,
    wanted: *const std.DynamicBitSetUnmanaged,
) ?Hit {
    const lead = writ.ahead(bytes, at);
    if (c.unbrace) |sym| {
        if (wanted.isSet(sym) and carry.columns.top() == writ.sealed and
            lead.at < bytes.len and bytes[lead.at] == '}')
        {
            carry.columns.close();
            return .{ .symbol = sym, .skip = lead.at - at, .len = 1 };
        }
    }
    // A bracket order's close: pop the frame its open pushed, if that frame is
    // what is standing on top. Byte-determined in the same sense the braces
    // below are - the delimiter it follows has already been consumed, so the
    // only question left is a stack identity - and it needs no warrant for the
    // same reason `standing` does not: the test is a function of the memory
    // alone, so every live reading gets the same answer from it.
    for (c.brackets, 0..) |b, k| {
        const sym = b.shut orelse continue;
        if (wanted.isSet(sym) and carry.columns.len > 0 and
            carry.columns.top() == c.troupe.brackets[k].frame)
        {
            carry.columns.close();
            return .{ .symbol = sym, .len = 0 };
        }
    }
    // End of input owes a close for every block still open, whatever column the
    // block sits at. Without this clause a block opened at column zero - which is
    // every module body - could never be closed, because no line can land left of
    // zero and the file would end inside it. A marker is not a block and owes
    // nothing at the end of input; its own order is what pops it.
    const over = lead.at >= bytes.len and carry.columns.len > 0 and
        carry.columns.top() < writ.marker;
    // A delimiter closes the layouts opened inside the bracket it ends, because
    // nothing else can: the `)` of `(do a; a)` shares a line with the block it
    // ends, so no column ever measures shallower. One layout per call, so a
    // bracket holding two of them is unwound over two reads and the bracket's
    // own close then finds its frame on top.
    const shed = writ.bracketed(&carry.columns);
    const how = if (over or shed) writ.Standing.left else writ.standing(&carry.columns, lead.column, lead.fresh);
    switch (how) {
        .left => if (c.seal) |sym| {
            if (wanted.isSet(sym)) {
                carry.columns.close();
                return .{ .symbol = sym, .len = 0 };
            }
        },
        .level => if (c.sever) |sym| {
            if (wanted.isSet(sym)) return .{ .symbol = sym, .len = 0 };
        },
        .inside => {},
    }
    if (c.brace) |sym| {
        if (wanted.isSet(sym) and lead.at < bytes.len and bytes[lead.at] == '{') {
            if (!carry.columns.open(writ.sealed)) return null;
            return .{ .symbol = sym, .skip = lead.at - at, .len = 1 };
        }
    }
    return null;
}

/// Whether a symbol is one of this cast's own protocol members.
///
/// Members are not rivals to each other, which is the point of asking. The family
/// is mutually exclusive by construction: a `{` is present or it is not, a `}`
/// closes only the frame its brace opened, and the pop, the separator and ordinary
/// code are three arms of one comparison. So a state offering an order beside its
/// brace - which is every `do`, `where` and `of` in the grammar - is offering one
/// question, not two answers in conflict.
fn mine(c: *const Cast, sym: press.Symbol) bool {
    for (c.writs) |w| if (w) |own| if (own == sym) return true;
    for (c.brackets) |b| {
        if (b.open) |own| if (own == sym) return true;
        if (b.shut) |own| if (own == sym) return true;
    }
    const named = [_]?press.Symbol{ c.brace, c.sever, c.seal, c.unbrace };
    for (named) |own| if (own) |it| if (it == sym) return true;
    return false;
}

/// The one order a state admits, or null if it admits none or several.
///
/// `only`, when given, additionally demands that nothing *outside* the family
/// stand beside it - the forced half of the warrant. Two orders at once would be a
/// state asking the bytes to tell `do` from `case`, which nothing in the bytes can
/// do; haskell's table holds no such state, and a grammar that did is declined
/// here rather than guessed.
fn sole(
    c: *const Cast,
    wanted: *const std.DynamicBitSetUnmanaged,
    named: ?*const std.DynamicBitSetUnmanaged,
) ?press.Symbol {
    var order: ?press.Symbol = null;
    for (c.writs) |w| if (w) |sym| {
        if (!wanted.isSet(sym)) continue;
        if (order != null) return null;
        order = sym;
    };
    const sym = order orelse return null;
    if (named) |only| {
        var it = only.iterator(.{});
        while (it.next()) |other| if (!mine(c, @intCast(other))) return null;
    }
    return sym;
}

/// Open a frame over the next lexeme. The mutation both halves of the warrant
/// share, so neither can drift from the other about where a block begins.
///
/// The Report's rule, and the reason an order is zero-width: the bytes it opens
/// over belong to the token *after* it, so the frame takes that token's column and
/// the order itself consumes nothing. Zero extent with the stack moved is exactly
/// the progress `step`'s pin demands, and the proof a hand may do what the slate
/// may not.
fn raise(carry: *Carry, bytes: []const u8, at: u32) bool {
    const lead = writ.ahead(bytes, at);
    if (lead.at >= bytes.len) return false;
    return carry.columns.open(lead.column);
}

/// Execute a `.writ` order the slate could not answer around.
///
/// The second half of the warrant, and the reason this kind is not `.offside` with
/// other names. An order carries no measurement to compare, so it cannot ride the
/// argument `tested` rides; the memory it mutates is shared across the union of
/// live readings, and a push made on one reading's behalf is read by all of them.
///
/// What licenses it is *where it is asked*. `Scanner.read` offers a hand first and
/// the slate second, and this pass runs only after the slate has failed - so the
/// order is emitted only when no terminal the state admits can consume the bytes
/// standing here. That is a function of the bytes and the memory alone, which is
/// the criterion, and it is the local shadow of the Report's own `parse-error(t)`:
/// the block opens because the parse has no other move, not because a reading was
/// guessed at.
///
/// It is what the five awkward states need, and it needs to know nothing about
/// which state it is in. Measured over haskell's 3543, 56 admit an order and 51
/// admit no other shift; of the five that do, four are settled by a literal the
/// slate lexes - `module` opening a file, `in` closing an empty `let`, `|]`
/// closing an empty quotation - and the fifth is multi-way `if`, where the slate
/// matches `variable` for `if x then` and matches nothing at all for `if | g`.
pub fn ordered(
    casts: []const Cast,
    carry: *Carry,
    bytes: []const u8,
    at: u32,
    wanted: *const std.DynamicBitSetUnmanaged,
    named: *const std.DynamicBitSetUnmanaged,
) ?Hit {
    if (at > bytes.len) return null;
    for (casts) |*c| {
        if (c.troupe.kind != .writ) continue;
        // A bracket order carries no measurement, so it does not need the next
        // lexeme to exist and it cannot be told from a rival by any byte. It
        // rides the same warrant the layout orders do and clears it by a wider
        // margin: haskell's four are the sole shift in every one of the 26
        // states that admit any of them, so `unrivalled` is a formality the
        // table grants rather than a corpus fact this seat is hoping for.
        for (c.brackets, 0..) |b, k| {
            const sym = b.open orelse continue;
            if (!wanted.isSet(sym) or !unrivalled(c, sym, named)) continue;
            if (!carry.columns.open(c.troupe.brackets[k].frame)) return null;
            return .{ .symbol = sym, .len = 0 };
        }
        const sym = sole(c, wanted, null) orelse continue;
        if (raise(carry, bytes, at)) return .{ .symbol = sym, .len = 0 };
    }
    return null;
}

/// Whether this order is the only terminal the union admits by shift.
///
/// The warrant, for an order that has no family to be exclusive within. A
/// `writ` earns it through `sole`, which asks whether two *orders* stand
/// together; a bracket has to ask the wider question, because the harm is the
/// same either way - a push executed in the shared stack on one reading's
/// behalf is read by every reading - and there is no measurement here to
/// partition the answer the way `standing` partitions a column's.
///
/// Asked of `named` rather than `wanted`, and the difference is the whole test.
/// `wanted` auto-admits every extra so a hand sees what tree-sitter's
/// `valid_symbols` would show, and haskell declares four of them - comment,
/// haddock, cpp, pragma - so a warrant read off `wanted` is refused in every
/// state in the grammar and this seat would be dead code that measured clean.
fn unrivalled(c: *const Cast, sym: press.Symbol, named: *const std.DynamicBitSetUnmanaged) bool {
    var it = named.iterator(.{});
    while (it.next()) |other| {
        if (@as(press.Symbol, @intCast(other)) == sym) continue;
        if (!mine(c, @intCast(other))) return false;
    }
    return true;
}

/// A new span, when the state will accept one of this dialect's openers.
fn opening(
    c: *const Cast,
    carry: *Carry,
    bytes: []const u8,
    at: u32,
    wanted: *const std.DynamicBitSetUnmanaged,
) ?Hit {
    var admits: fence.Admits = @splat(false);
    var any = false;
    for (c.opens, 0..) |o, tag| if (o) |sym| {
        if (wanted.isSet(sym)) {
            admits[tag] = true;
            any = true;
        }
    };
    if (!any) return null;
    const got = fence.open(c.troupe.dialect, bytes, at, admits) orelse return null;
    const sym = c.opens[got.span.tag] orelse return null;
    if (!wanted.isSet(sym)) return null;
    if (!carry.spans.push(got.span)) return null;
    return .{ .symbol = sym, .len = got.len };
}

/// A token settled by reading past it. Carries nothing and mutates nothing,
/// like `bounded` above - the difference is that the bytes it reads to decide
/// are not the bytes it claims, so the answer can be one byte wide, or none,
/// at an offset past a run it stepped over rather than took.
fn sighted(
    c: *const Cast,
    bytes: []const u8,
    at: u32,
    wanted: *const std.DynamicBitSetUnmanaged,
) ?Hit {
    // The cohort in the C enum's own order, which is the order the grammar
    // declares its externals in. Both facts are the same fact, and it is what
    // lets one hand answer two languages without either one's spellings
    // reaching it.
    var asks: u8 = 0;
    for (c.opens, 0..) |slot, i| if (want(wanted, slot)) {
        asks |= @as(u8, 1) << @intCast(i);
    };
    if (asks == 0) return null;
    const cut = scry.look(c.troupe.sight, bytes, at, asks, hushed(c, wanted)) orelse return null;
    const sym = c.opens[cut.slot] orelse return null;
    return .{ .symbol = sym, .len = cut.len, .skip = cut.skip };
}

fn want(wanted: *const std.DynamicBitSetUnmanaged, sym: ?press.Symbol) bool {
    return if (sym) |s| wanted.isSet(s) else false;
}

/// Whether the state wants a terminal that stands this hand down.
fn hushed(c: *const Cast, wanted: *const std.DynamicBitSetUnmanaged) bool {
    for (c.hushed) |b| if (b) |sym| {
        if (wanted.isSet(sym)) return true;
    };
    return false;
}

/// Whether the byte a fresh line starts with could open a span the state wants.
/// Python's spec defers a dedent in that case, because the string is a
/// continuation of the statement above rather than a new one.
fn opensAString(
    casts: []const Cast,
    wanted: *const std.DynamicBitSetUnmanaged,
    lookahead: u8,
) bool {
    if (lookahead != '"' and lookahead != '\'' and lookahead != '`') return false;
    for (casts) |*c| {
        if (c.troupe.kind != .fence) continue;
        for (c.opens) |o| if (o) |sym| {
            if (wanted.isSet(sym)) return true;
        };
    }
    return false;
}

test "outside: every row is a distinct name with a non-empty pattern" {
    for (&roll, 0..) |*p, i| {
        try std.testing.expect(p.name.len > 0);
        try std.testing.expect(p.pattern.len > 0);
        for (roll[i + 1 ..]) |*q| try std.testing.expect(!std.mem.eql(u8, p.name, q.name));
    }
}

test "outside: every row states the company it was read with" {
    // The invariant that replaced name matching. A row with no cohort would
    // fire on its name alone, which is how haskell's `comment` came to be
    // spelled `#[^\n]*`, so an empty one is the bug rather than a default.
    for (&roll) |*p| {
        try std.testing.expect(p.cohort.len > 0);
        for (p.cohort) |kin| {
            try std.testing.expect(!std.mem.eql(u8, kin, p.name));
            // A cohort names externals of the same scanner, so each one is
            // itself a row here or the pair could never both seat.
            var known = false;
            for (&roll) |*q| {
                if (std.mem.eql(u8, q.name, kin)) known = true;
            }
            if (!known) {
                // Python's offside triple is emitted by the same scanner as
                // `comment` but is answered by a hand, so it has no row.
                try std.testing.expect(kin[0] == '_');
            }
        }
    }
}

test "outside: a partial cast does not seat" {
    // Kotlin's case, which is the reason `seated` exists. It declares three of
    // the Ruby troupe's names and none of the other five, so the anchor test
    // alone handed it `%w[` and a subshell. The cast has to be whole.
    const ruby = for (&troupes) |*t| {
        if (t.dialect == .ruby) break t;
    } else unreachable;

    var partial: Cast = .{ .troupe = ruby, .body = 1, .close = 2 };
    partial.opens[0] = 0; // `_string_start`, the anchor and all kotlin shares
    try std.testing.expect(!seated(ruby, &partial));

    var whole: Cast = .{ .troupe = ruby, .body = 1, .close = 2 };
    for (ruby.opens, 0..) |o, tag| if (o.len > 0) {
        whole.opens[tag] = @intCast(tag + 3);
    };
    try std.testing.expect(seated(ruby, &whole));
}

test "outside: every troupe the eleven rely on can still seat" {
    // The guard must reject a collision without also rejecting the shapes it
    // was written for, so each troupe is seated from its own declared parts.
    for (&troupes) |*t| {
        var c: Cast = .{ .troupe = t };
        var next: press.Symbol = 0;
        // Every role a `Troupe` names and a `Cast` resolves, paired by field
        // name rather than by a list written out here. A hand-written list is
        // the thing this test exists to be, and the html row proved it can go
        // stale silently: three roles were added to both structs and to
        // `seated`, and the only thing that still enumerated them by hand was
        // this fixture, so the row could not seat and no other test noticed.
        //
        // Pairing on the name alone was still one list short, and elixir's
        // roster proved *that*: a role can arrive as a run of names rather
        // than one, and the first version of this loop only understood the
        // scalar. So the shape is read off the field too - a name, a list of
        // names, or a list of records carrying one - and the only thing a new
        // role has to do to be seated here is be spelled in both structs.
        //
        // It went stale a third time, the same way, and the third case is the
        // one that finishes the argument. Haskell's bracket orders are a run of
        // records carrying *two* names each - an open and its close, which have
        // to resolve together or the seat strands a frame nothing can pop - and
        // a loop that understood one name per record skipped the field
        // silently, left both halves null, and failed the row it was seating.
        // So the record is now paired by field name too, exactly as the outer
        // loop pairs the structs: every `?press.Symbol` in a seat slot is filled
        // from the spelling of the same name in the troupe's record. A role
        // carrying three names would need nothing here at all.
        inline for (@typeInfo(Troupe).@"struct".fields) |f| {
            if (@hasField(Cast, f.name)) {
                const Seat = @FieldType(Cast, f.name);
                if (Seat == ?press.Symbol) {
                    if (@field(t, f.name).len > 0) {
                        @field(c, f.name) = next;
                        next += 1;
                    }
                } else if (@typeInfo(Seat) == .array and
                    @typeInfo(Seat).array.child == ?press.Symbol)
                {
                    for (@field(t, f.name), 0..) |role, k| {
                        if (k >= @typeInfo(Seat).array.len) break;
                        const spelling = if (@TypeOf(role) == []const u8) role else role.name;
                        if (spelling.len > 0) {
                            @field(c, f.name)[k] = next;
                            next += 1;
                        }
                    }
                } else if (@typeInfo(Seat) == .array and
                    @typeInfo(@typeInfo(Seat).array.child) == .@"struct")
                {
                    const Slot = @typeInfo(Seat).array.child;
                    for (@field(t, f.name), 0..) |role, k| {
                        if (k >= @typeInfo(Seat).array.len) break;
                        inline for (@typeInfo(Slot).@"struct".fields) |sf| {
                            if (comptime @FieldType(Slot, sf.name) == ?press.Symbol) {
                                if (@field(role, sf.name).len > 0) {
                                    @field(@field(c, f.name)[k], sf.name) = next;
                                    next += 1;
                                }
                            }
                        }
                    }
                }
            }
        }
        try std.testing.expect(seated(t, &c));
    }
}

test "outside: the troupe fixture still refuses half a role" {
    // **Anti-vacuity for the loop above.** Teaching a fixture a new shape is
    // one keystroke away from teaching it to fill everything and assert what it
    // just filled, and this file has already been burned by a fixture that
    // could not fail. So the generalisation is held to the thing it must still
    // catch: a paired role with one half resolved and the other null is exactly
    // the half-seating `seated` exists to refuse, because an open with no close
    // pushes a frame nothing can pop and a marker on top of the stack silences
    // the offside rule for every line after it.
    const hs = for (&troupes) |*t| {
        if (t.brackets.len > 0) break t;
    } else unreachable;

    var half: Cast = .{ .troupe = hs };
    var next: press.Symbol = 0;
    // Everything the row spells except the closes, so the only thing missing is
    // the half whose absence is the hazard.
    for (hs.writs, 0..) |w, k| if (w.len > 0) {
        half.writs[k] = next;
        next += 1;
    };
    for ([_]*?press.Symbol{ &half.brace, &half.sever, &half.seal, &half.unbrace }) |slot| {
        slot.* = next;
        next += 1;
    }
    for (hs.brackets, 0..) |_, k| {
        half.brackets[k].open = next;
        next += 1;
    }
    try std.testing.expect(!seated(hs, &half));

    // And it is the missing close doing the refusing, not something else the
    // row needs - fill them and the same cast seats.
    var whole = half;
    for (hs.brackets, 0..) |_, k| {
        whole.brackets[k].shut = next;
        next += 1;
    }
    try std.testing.expect(seated(hs, &whole));
}

test "outside: the ledger refuses the two-cycle the old slot let through" {
    // The hole, stated as the sequence that walks through it. `A B A` at one
    // offset with nothing moving: the old single slot held `A`, was overwritten
    // by `B`, and had nothing left to refuse the second `A` with. Two hands
    // taking turns at one offset is a spin that never repeats a *consecutive*
    // pair, so the slot could not see it however long it ran.
    var s: Spent = .{};
    try std.testing.expect(s.admit(10, 0, 1));
    try std.testing.expect(s.admit(10, 0, 2));
    try std.testing.expect(!s.admit(10, 0, 1));
    try std.testing.expect(!s.admit(10, 0, 2));

    // And it is not refusing by offset alone, or a moved cursor would inherit
    // the refusal and a legitimate second answer would die with the spin.
    try std.testing.expect(s.admit(11, 0, 1));

    // Memory moving is what makes the same symbol a different question, which
    // is the whole reason a run of dedents is legal and `A B A` is not. `shape`
    // is depth-only, so this is the exact fact the hand changed.
    var run: Spent = .{};
    for (0..offside.Columns.max) |d| {
        try std.testing.expect(run.admit(7, @intCast(offside.Columns.max - d), 3));
    }

    // **Anti-vacuity, and it is the load-bearing half.** Everything above
    // passes just as well if the ceiling were 1 and every zero-width answer in
    // the parser were refused - a ledger that admits nothing terminates
    // beautifully and seats no cohort. So two claims the refusals cannot make:
    // the longest legitimate run the tree can produce fits *under* the ceiling
    // with room left, and a hand answering unconditionally is stopped *by* it.
    try std.testing.expect(offside.Columns.max < Spent.ceiling);
    try std.testing.expect(lineage.Tags.max < Spent.ceiling);
    try std.testing.expect(fence.Spans.max < Spent.ceiling);
    var spin: Spent = .{};
    var got: u32 = 0;
    // Every ask a different symbol and a different shape, which is the most
    // generous thing a hand could claim about itself. Only the total stops it.
    for (0..Spent.ceiling * 4) |i| {
        if (spin.admit(3, @intCast(i), @intCast(i % Spent.cohort))) got += 1;
    }
    try std.testing.expectEqual(@as(u32, Spent.ceiling), got);
}

test "outside: julia's glued markers are zero-width, byte-keyed and disjoint" {
    const abut = for (&troupes) |*t| {
        if (t.kind == .abut) break t;
    } else return error.NoAbutTroupe;

    // Disjoint bytes is what lets `cohort` be small and what makes the ledger's
    // second arm a refusal of a spin rather than of a legitimate sibling: two
    // markers keyed to one byte would be two answers at one unmoved shape, and
    // the second would be refused as a repeat. This is checked rather than
    // asserted in prose because a sixth marker is a one-line addition.
    try std.testing.expect(abut.glued.len > 1);
    for (abut.glued, 0..) |gl, i| {
        try std.testing.expect(gl.name.len > 0);
        for (abut.glued[i + 1 ..]) |other| try std.testing.expect(gl.at != other.at);
    }

    // The whole cohort or none. A partial seat would answer three of julia's
    // five markers and leave the parse asking for the other two at an offset
    // the hand just declined to move.
    var partial: Cast = .{ .troupe = abut };
    partial.glued[0] = 0;
    try std.testing.expect(!seated(abut, &partial));
    var whole: Cast = .{ .troupe = abut };
    for (abut.glued, 0..) |_, k| whole.glued[k] = @intCast(k);
    try std.testing.expect(seated(abut, &whole));
}

test "outside: the caesura needs the operator it consults, not just the token it emits" {
    const asi = for (&troupes) |*t| {
        if (t.kind == .caesura) break t;
    } else return error.NoCaesuraTroupe;
    // A grammar that declares the anchor and nothing else is some other
    // language reusing the name. It is `||` that says the parse table can
    // answer the question this hand has to ask, and without an answer the
    // hand would have to guess between an expression and a type.
    var alone: Cast = .{ .troupe = asi, .body = 0, .gate = 1 };
    try std.testing.expect(!seated(asi, &alone));
    var whole: Cast = .{ .troupe = asi, .body = 0, .gate = 1, .kin = 2 };
    try std.testing.expect(seated(asi, &whole));
    // The signature terminator is TypeScript's alone, so requiring it would
    // refuse JavaScript - the grammar the convention is named after.
    try std.testing.expect(whole.sign == null);
}
