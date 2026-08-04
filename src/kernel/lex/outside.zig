//! What a grammar's external scanner would have produced, declared as data.
//!
//! tree-sitter lets a grammar name terminals no regex in the file can
//! recognize and hand them to a C function it links: `externals`. Ten of the
//! eleven grammars in `upstream/` use one, four of them for the token that
//! starts the file, so a lexer with no answer here is a lexer that cannot read
//! Python at all. outliner links no tree-sitter runtime, so the C function is
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
//!     (nothing in a regex promises the next call differs), a hand need not:
//!     every `_dedent` pops a column, so the memory is the proof of progress.
//!     `step` checks that proof rather than trusting it - see `Carry.pinned`.
//!
//! What generalises across the hands is the *memory*, not the scanners: a
//! stack of columns (`offside.zig`) and a stack of open marks (`fence.zig`).
//! An opener's spelling never generalises and this file does not pretend it
//! does - `troupes` is a map from one language's terminal names onto the parts
//! of a shape, which is the most that is true.

const std = @import("std");
const g = @import("../../press/grammar.zig");
const offside = @import("offside.zig");
const fence = @import("fence.zig");
const marrow = @import("marrow.zig");
const caesura = @import("caesura.zig");
const scry = @import("scry.zig");
const lineage = @import("lineage.zig");

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
    lexis: g.Lexis = .{},
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

/// The roll. Ordered by the grammar that motivated each row, which is a
/// comment about provenance and nothing the lookup depends on.
pub const roll = [_]Provision{
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
};

/// The spelling declared for an external terminal, if this lexer has one *and*
/// this grammar is the kind of grammar the row was read from.
///
/// The cohort is what makes the second half true. Without it the name alone
/// decided, and a name is shared by languages that mean different bytes by it;
/// with it, a row fires only where the whole scanner's output is present.
pub fn provisionFor(gr: *const g.Grammar, name: []const u8) ?*const Provision {
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
fn declaresExternal(gr: *const g.Grammar, name: []const u8) bool {
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
    /// The terminal whose presence says this language uses this shape.
    anchor: []const u8,
    kind: enum { offside, fence, marrow, caesura, scry, lineage },
    dialect: fence.Dialect = .python,
    /// The bounding spelling, when `kind` is `.marrow`. Kept beside `dialect`
    /// rather than folded into it because the two answer different questions -
    /// one names an opener, the other names a close - and a row uses exactly
    /// one of them.
    vein: marrow.Dialect = .rust_block,
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
    /// The openers, when `kind` is `.fence`. Ordered to match the dialect's
    /// own tag numbering, because a dialect with six openers and one closer
    /// has to say on the way out which one it was.
    opens: []const []const u8 = &.{},
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
    c.close = names.external(t.close);
    c.escape = names.external(t.escape);
    c.stray = names.external(t.stray);
    c.implied = names.external(t.implied);
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
    const named = [_]struct { name: []const u8, got: ?g.Symbol }{
        .{ .name = t.newline, .got = c.newline },
        .{ .name = t.indent, .got = c.indent },
        .{ .name = t.dedent, .got = c.dedent },
        .{ .name = t.body, .got = c.body },
        .{ .name = t.close, .got = c.close },
        .{ .name = t.escape, .got = c.escape },
        .{ .name = t.kin, .got = c.kin },
        .{ .name = t.stray, .got = c.stray },
        .{ .name = t.implied, .got = c.implied },
        .{ .name = t.shut, .got = c.shut },
    };
    for (named) |p| if (p.name.len > 0 and p.got == null) return false;
    for (t.opens, 0..) |o, tag| if (o.len > 0 and c.opens[tag] == null) return false;
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
        t.newline, t.indent, t.dedent, t.body, t.close, t.escape,
        t.stray,   t.implied, t.shut,
    };
    for (named) |n| if (n.len > 0 and std.mem.eql(u8, n, name)) return true;
    for (t.opens) |n| if (std.mem.eql(u8, n, name)) return true;
    return false;
}

/// A troupe with its terminal names resolved to this grammar's symbols. Built
/// once at compile so the scan never compares a string.
pub const Cast = struct {
    troupe: *const Troupe,
    newline: ?g.Symbol = null,
    indent: ?g.Symbol = null,
    dedent: ?g.Symbol = null,
    hushed: [4]?g.Symbol = @splat(null),
    kin: ?g.Symbol = null,
    gate: ?g.Symbol = null,
    sign: ?g.Symbol = null,
    opens: [fence.tags]?g.Symbol = @splat(null),
    body: ?g.Symbol = null,
    close: ?g.Symbol = null,
    escape: ?g.Symbol = null,
    stray: ?g.Symbol = null,
    implied: ?g.Symbol = null,
    shut: ?g.Symbol = null,
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
    /// The last zero-width answer, and the shape of the memory when it was
    /// given. A hand that answers the same terminal at the same offset with
    /// the memory unmoved has not made progress, and is refused - which is the
    /// proof that lets a hand do what the slate may not. A run of `_dedent`s
    /// passes it because each one pops a column.
    pinned: ?struct { at: u32, sym: g.Symbol, shape: u64 } = null,

    /// Begin a file.
    pub fn rewind(c: *Carry) void {
        c.columns.reset();
        c.spans.reset();
        c.tags.reset();
        c.pinned = null;
    }

    /// Whether two carries are the same lexical state.
    ///
    /// Use this and never `std.meta.eql` on a `Carry`: every stack is a
    /// fixed-capacity array with a live prefix, and everything past that
    /// prefix is `undefined`. The stacks answer for their own dead bytes; the
    /// guard has none.
    pub fn same(a: *const Carry, b: *const Carry) bool {
        return a.columns.same(&b.columns) and
            a.spans.same(&b.spans) and
            a.tags.same(&b.tags) and
            std.meta.eql(a.pinned, b.pinned);
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
    pub fn answered(c: *const Carry, at: u32, sym: g.Symbol) bool {
        const was = c.pinned orelse return false;
        return was.at == at and was.sym == sym and was.shape == c.shape();
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
pub const Hit = struct { symbol: g.Symbol, len: u32, skip: u32 = 0 };

/// Ask every bound hand, in the order the specifications imply, for a token at
/// `at`. Null means none of them claims this offset and the slate should try.
///
/// The order is three phases and is not per-language: what is inside an open
/// span first (its body owns those bytes until it says otherwise), then the
/// line's layout, then a new span opening. Python's own scanner is written in
/// exactly that order, and Ruby, which has no layout, skips the middle.
///
/// `fresh` says no extra has been stepped over since the last token ended, and
/// only the layout phase reads it. That split is the specifications': Python's
/// scanner measures the whitespace itself and so must be asked before anything
/// eats it, while Ruby's and Rust's begin by skipping whitespace, so their
/// openers have to be reachable at an offset the extras already moved to. A
/// hand asked only at fresh offsets would never see `let s = r#"..."#`.
pub fn step(
    casts: []const Cast,
    carry: *Carry,
    bytes: []const u8,
    at: u32,
    fresh: bool,
    wanted: *const std.DynamicBitSetUnmanaged,
) ?Hit {
    const hit = offer(casts, carry, bytes, at, fresh, wanted) orelse return null;
    if (hit.skip + hit.len > 0) return hit;
    // No progress, so the memory has to have moved. `pinned` is written only
    // here, which keeps every hand free of the bookkeeping. Skipped bytes
    // count as progress for the same reason consumed ones do: the cursor ends
    // past where it started, so the next ask is a different question.
    const now = carry.shape();
    if (carry.pinned) |was| {
        if (was.at == at and was.sym == hit.symbol and was.shape == now) return null;
    }
    carry.pinned = .{ .at = at, .sym = hit.symbol, .shape = now };
    return hit;
}

fn offer(
    casts: []const Cast,
    carry: *Carry,
    bytes: []const u8,
    at: u32,
    fresh: bool,
    wanted: *const std.DynamicBitSetUnmanaged,
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
    return null;
}

/// A terminator the line implies and the file never spells.
///
/// Asked only at a fresh offset, because the decision is about the whitespace
/// between two tokens and an offset the extras have already moved past has
/// none left to read. `caesura.zig` holds the rules; everything here is the
/// translation between the parser's expected set and the two questions those
/// rules put to it.
fn unwritten(
    c: *const Cast,
    bytes: []const u8,
    at: u32,
    wanted: *const std.DynamicBitSetUnmanaged,
) ?Hit {
    const sym = c.body orelse return null;
    if (!wanted.isSet(sym)) return null;
    if (hushed(c, wanted)) return null;
    const ask: caesura.Asks = .{ .binary = want(wanted, c.gate), .signature = want(wanted, c.sign) };
    if (!caesura.breaks(bytes, at, ask)) return null;
    return .{ .symbol = sym, .len = 0 };
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
/// Carries nothing and mutates nothing, which is why it takes neither `carry`
/// nor a span - see `marrow.zig` for why the captured close does not need to be
/// remembered. Both answers are non-empty by construction, so this hand never
/// reaches `step`'s zero-width guard.
fn bounded(
    c: *const Cast,
    carry: *const Carry,
    bytes: []const u8,
    at: u32,
    wanted: *const std.DynamicBitSetUnmanaged,
) ?Hit {
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
    const lead = offside.lead(bytes, at);
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

fn want(wanted: *const std.DynamicBitSetUnmanaged, sym: ?g.Symbol) bool {
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
        var next: g.Symbol = 0;
        if (t.newline.len > 0) {
            c.newline = next;
            next += 1;
        }
        if (t.indent.len > 0) {
            c.indent = next;
            next += 1;
        }
        if (t.dedent.len > 0) {
            c.dedent = next;
            next += 1;
        }
        if (t.body.len > 0) {
            c.body = next;
            next += 1;
        }
        if (t.close.len > 0) {
            c.close = next;
            next += 1;
        }
        if (t.escape.len > 0) {
            c.escape = next;
            next += 1;
        }
        if (t.kin.len > 0) {
            c.kin = next;
            next += 1;
        }
        for (t.opens, 0..) |o, tag| if (o.len > 0) {
            c.opens[tag] = next;
            next += 1;
        };
        try std.testing.expect(seated(t, &c));
    }
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
