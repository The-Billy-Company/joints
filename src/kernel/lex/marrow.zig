//! Content bounded by marks the parser itself lexes.
//!
//! The third shape an external scanner comes in, after `offside`'s column stack
//! and `fence`'s span stack, and the one that needs no stack at all.
//!
//! `offside` and `fence` both answer tokens that *are* the boundary: an indent,
//! a string opener, a closer. This file answers the opposite - the run in
//! between, where the boundary on each side is an ordinary terminal the grammar
//! already spells for itself. Rust writes `SEQ("/*", _block_comment_content,
//! "*/")` and C++ writes `SEQ("R\"", raw_string_delimiter, "(",
//! raw_string_content, ")", raw_string_delimiter, "\"")`; in both, only the
//! middle is external, because only the middle needs to know where it ends.
//!
//! What makes it a mechanism rather than three special cases is that no end is
//! ever remembered from a previous token - each is worked out afresh, from the
//! position or from the terminal the state asked for:
//!
//! - Rust's close is fixed at `*/`, but nests, so the run is bounded by the
//!   `*/` that brings a depth counter back to zero rather than by the first one.
//! - C++'s close is whatever spelling the open captured, so the run is bounded
//!   by `)` + that spelling + `"`.
//!
//! - elixir's close is neither: it is whichever of twenty delimiters the parse
//!   state named by asking for one content terminal rather than another, so the
//!   run is bounded by a `Mark` and the walk backwards is zero bytes long.
//!
//! A captured close usually implies carried state, and `fence` is exactly that
//! - but only because a fence's opener is itself an external, so the capture
//! happens in one token and is spent in another. Here the open is a terminal
//! the parser lexed, which means it is still there in the bytes: at a content
//! offset the delimiter is a fixed walk backwards from `(`. So this file reads
//! only its arguments, carries nothing between tokens, and cannot leave a run
//! contaminated by the last one.
//!
//! Both dialects decline on an empty run rather than answering zero width. An
//! empty comment or an empty raw string is spelled by the grammar's own BLANK
//! branch, so silence here is the right answer and not a gap; it also keeps
//! this file out of the zero-width progress argument `outside.step` has to make
//! for the hands that do answer at width zero.
//!
//! Every dialect here is derived from the pinned grammar's own `scanner.c` read
//! as a specification. Nothing is linked.

const std = @import("std");

/// A close the parse state names instead of the bytes.
///
/// The mechanism above computes both ends from position, and for eight veins
/// that is the whole story. Three of the thirty spell it the other way round:
/// one content terminal per delimiter, so `_quoted_content_double` and
/// `_quoted_content_heredoc_single` are the *same run* differing only in what
/// ends it, and the parse state picks between them by naming one. The close is
/// still not carried - it is just read off the terminal rather than off the
/// bytes, which is a shorter walk backwards than c++'s and not a longer one.
///
/// So a mark is the parameters that make a close: the delimiter byte, how many
/// of it in a row, and whether the language interpolates inside this run.
/// `wide` is how many, and what that *means* belongs to the walk and not to
/// this record: elixir reads three as a heredoc, which is the same close plus
/// the rule that only a line may begin it, and julia reads three as three
/// quotes anywhere. Same field, two readings, and putting the reading in the
/// field would have forced julia's triple-quote to inherit a rule julia's
/// scanner does not have.
/// A close longer than a byte is spelled as `shut` plus a `tail`, rather than as
/// one string, and the split is the field's real job rather than a saving.
/// Everything that reads a mark reads `shut` as **the byte at which a close could
/// begin**: three walks compare it to one byte of the source, and `outside.shutOf`
/// keys the emitted close terminal by it. latex's walk asks the same question
/// first and only then whether the rest follows. So `shut` stays a `u8` that a
/// comparison can hold in a register, no existing walk gains a length or a
/// pointer dereference, and the one family with a long close carries the length
/// it needs beside it.
pub const Mark = struct {
    shut: u8,
    /// What must follow `shut` for the close to be whole. Empty for every family
    /// whose delimiter is one character repeated `wide` times; `\end{verbatim}`
    /// spells `shut = '\\'` and a thirteen-byte tail.
    tail: []const u8 = "",
    wide: u8 = 1,
    interpolates: bool = false,
    /// Whether this run resumes immediately behind a variable, which is php's
    /// fourth parameter and no other family's. It is a property of the
    /// terminal the state named and not of history: `"$a[0]"` and `"a[0]"`
    /// differ because the parser asked for a different member, so `[` and
    /// `->` end the first run and are content in the second. Nothing is
    /// carried - the distinction arrives with the question.
    after: bool = false,
    /// Whether the close is a command name rather than a delimiter, which is
    /// latex's `is_command_name` and only `\fi`'s. A command name does not end
    /// where it stops matching: `\fifoo` is one command called `\fifoo`, so a
    /// letter or a `:` `_` `@` behind the match makes the whole of it content and
    /// the walk keeps going.
    command: bool = false,
};

/// Which family a roster is, when a row's close is a `Mark`.
///
/// The sibling of `Dialect` and not a member of it: a dialect names a *walk*
/// this file knows how to do, and a family names a *table* the troupe carries.
/// Four of the thirty are shaped this way, and latex is the fourth: twelve
/// terminals - not the eleven this header used to claim, because `_trivia_raw_fi`
/// comes out of the same function and is one of them - whose close is
/// `\end{<name>}`, or `\fi` for the odd one.
///
/// **Julia is a family and not a row, and that correction is the finding.**
/// This header used to say julia's eight `_content_{str,cmd}_{1,3}[_raw]` were
/// "rows rather than code" - a table entry under elixir's walk. They are not,
/// and reusing `matter` for them would have silently changed elixir's answers
/// in three places: julia refuses at end of input where elixir hands back
/// matter to the end, julia's interpolation sigil is a bare `$` where elixir's
/// is `#{`, and julia's raw branch also stops on `\\` where elixir's stops
/// only on its own delimiter. Same table, different walk.
///
/// php is the third, and it is the family that proves the shape is not about
/// delimiters. Its four rows differ by two parameters rather than one - which
/// quote closes them, and whether a variable stands immediately behind - and
/// its walk is a third set of decisions again. The rule that keeps earning
/// itself: same table, different walk, and a family that reuses another's walk
/// is a language quietly inheriting a rule its scanner does not have.
/// latex is the fourth, and it is the one that made a close longer than a byte
/// necessary. It is also a fourth walk again rather than a reuse: it hands back
/// matter it never marked, it can refuse a run whose close it *found*, and its
/// close is a name rather than a delimiter. See `verbatim`.
pub const Family = enum { none, elixir_quoted, julia_quoted, php_encapsed, latex_verbatim };

/// What one pass over a family's run answers.
///
/// Three arms because two of these families emit their own closer. elixir's
/// quotes are ordinary terminals the press lexes, so its walk only ever
/// answers `matter`; julia declares `_end_str` and `_end_cmd` as externals and
/// its scanner emits one from *inside* the content scan, when the delimiter is
/// already there and there is no content in front of it. So the close is not a
/// second question asked at the same offset - it is the same question's other
/// answer, and modelling it as one is what keeps the width honest: the run
/// that decided the close is the run that knows how wide the delimiter was.
pub const Run = union(enum) { matter: u32, close: u32, none };

/// One pass over a family's run: how far the matter at `at` goes, or the close
/// standing in front of it, or neither.
pub fn walk(family: Family, mark: Mark, bytes: []const u8, at: u32) Run {
    return switch (family) {
        .none => .none,
        .elixir_quoted => if (matter(mark, bytes, at)) |n| .{ .matter = n } else .none,
        .julia_quoted => quoted(mark, bytes, at),
        .php_encapsed => if (encapsed(mark, bytes, at)) |n| .{ .matter = n } else .none,
        .latex_verbatim => if (verbatim(mark, bytes, at)) |n| .{ .matter = n } else .none,
    };
}

/// The widest family. elixir's twenty is it; latex asks for twelve, julia
/// eight and php four.
pub const widest = 20;

/// The languages whose bounding spelling this file can read. Adding one is a
/// new case in `reach` plus a row in `outside.troupes`; nothing else moves.
pub const Dialect = enum {
    rust_block,
    cpp_raw,
    kotlin_block,
    swift_block,
    ocaml_comment,
    html_comment,
    rust_string,
    julia_block,
    lua_string,
    lua_comment,
    swift_raw,
};

/// How far the matter at `at` runs before the mark that closes it, or null if
/// the run would be empty.
///
/// elixir's `scan_quoted_content` transcribed, and it is the whole family: the
/// twenty rows differ only in the `Mark` handed in. Four details of it are the
/// specification's and none is obvious from the shape:
///
///   * **A newline and the whitespace behind it are matter**, consumed before
///     the extent is taken, so the parser is never handed an indent it has to
///     walk again - and the newline is remembered, because a heredoc's close is
///     only a close where a line begins.
///   * **The extent is taken at the top of each pass**, before the delimiter is
///     probed. A probe that runs three bytes into a `"""` and fails leaves
///     those bytes as matter, which is why the extent cannot be the cursor.
///   * **An escape ends the run only where the grammar spells one.** An
///     interpolating run hands every `\` to its own `escape_sequence`; a raw one
///     hands over only the escape of its own delimiter and eats the rest.
///   * **Unterminated is not a refusal.** A file that ends mid-string is
///     matter to the end, because the alternative is a stall on the last line
///     of a file somebody is still typing.
///
/// An empty run refuses, as every vein here does; the grammar spells the empty
/// string with its own BLANK branch. That is also what keeps this out of
/// `outside.step`'s zero-width argument.
pub fn matter(mark: Mark, bytes: []const u8, at: u32) ?u32 {
    if (at > bytes.len) return null;
    const heredoc = mark.wide == 3;
    var i = at;
    var any = false;
    while (true) : (any = true) {
        var newline = false;
        if (i < bytes.len and breaks(bytes[i])) {
            i += 1;
            any = true;
            newline = true;
            while (i < bytes.len and blank(bytes[i])) i += 1;
        }
        const end = i;
        if (i < bytes.len and bytes[i] == mark.shut) {
            var run: u8 = 1;
            while (run < mark.wide) {
                i += 1;
                if (i < bytes.len and bytes[i] == mark.shut) run += 1 else break;
            }
            if (run == mark.wide and (!heredoc or newline)) return if (any) end - at else null;
        } else if (i >= bytes.len) {
            return if (any) end - at else null;
        } else if (bytes[i] == '#') {
            i += 1;
            if (mark.interpolates and i < bytes.len and bytes[i] == '{') {
                return if (any) end - at else null;
            }
        } else if (bytes[i] == '\\') {
            i += 1;
            const next: ?u8 = if (i < bytes.len) bytes[i] else null;
            // A heredoc keeps its escaped newline, and keeps it *as a newline*,
            // because the close behind it is only a close on a fresh line.
            if (heredoc and next == '\n') continue;
            if (mark.interpolates or next == mark.shut) return if (any) end - at else null;
        } else {
            i += 1;
        }
    }
}

/// julia's `scan_content` transcribed: the matter at `at`, or the delimiter
/// standing in front of it, or neither.
///
/// The same eight-row table shape as elixir and a different walk, because four
/// of julia's decisions are its own and three of them would have been wrong if
/// this had reused `matter`:
///
///   * **End of input refuses.** julia's loop is `while ((next = lookahead))`
///     and falls out of the bottom with no `result_symbol` set, so a file that
///     stops mid-string yields no content token at all. elixir hands back
///     matter to the end. Transcribing elixir's charity here would have had the
///     hand answer where the specification stays silent, which is the one
///     direction a seating may never err in.
///   * **The interpolating sigil is a bare `$`, and it shares its arm with
///     `\`.** One test, two triggers: an interpolating run stops at either, and
///     hands both to the grammar (`_immediate_paren`/`escape_sequence`).
///   * **The raw arm stops at `\\` as well as at an escaped delimiter.** A raw
///     string still spells `\\` for one backslash, so the pair is the grammar's
///     to own; every other `\x` is two bytes of matter.
///   * **The close is this walk's other answer, not a second question.** When
///     the delimiter is already at `at` there is no matter in front of it, and
///     julia emits `_end_str`/`_end_cmd` from inside the content scan. The
///     extent is the delimiter's own width, which is knowable here and nowhere
///     else.
///
/// The extent is taken at the top of each pass, as in `matter` and for the same
/// reason: a probe that runs two bytes into a `"""x` and fails leaves those two
/// quotes as matter, so the extent cannot be the cursor.
fn quoted(mark: Mark, bytes: []const u8, at: u32) Run {
    if (at > bytes.len) return .none;
    var i = at;
    var any = false;
    while (true) : (any = true) {
        // A zero byte reads as end of input to tree-sitter's lexer, and this
        // loop's condition is that lookahead, so it refuses on both.
        if (i >= bytes.len or bytes[i] == 0) return .none;
        const end = i;
        const next = bytes[i];
        if (mark.interpolates and (next == '$' or next == '\\')) {
            return if (any) .{ .matter = end - at } else .none;
        } else if (next == '\\') {
            i += 1;
            const after: ?u8 = if (i < bytes.len) bytes[i] else null;
            if (after == mark.shut or after == '\\') {
                return if (any) .{ .matter = end - at } else .none;
            }
        } else {
            var wide: u8 = 0;
            while (wide < mark.wide) : (wide += 1) {
                if (i < bytes.len and bytes[i] == mark.shut) i += 1 else break;
            }
            if (wide == mark.wide) {
                return if (any) .{ .matter = end - at } else .{ .close = mark.wide };
            }
        }
        if (i < bytes.len) i += 1;
    }
}

/// php's `scan_encapsed_part_string` transcribed, for the three of its five
/// arguments that are not carried.
///
/// The function serves six terminals and is the whole of php's string
/// interior. Four of the six are here; the two `_heredoc` ones are not, and
/// the line between them is exactly the line this file draws. With
/// `is_heredoc` true the first thing the scanner does is read
/// `scanner->heredocs`, a stack of tags pushed by one token and spent by
/// another - `fence`'s animal. With it false the entire body reads the bytes
/// at the cursor and two booleans, and the two booleans arrive with the
/// question: the parse state picks `encapsed_string_chars_after_variable` over
/// `encapsed_string_chars`, and `execution_` over `encapsed_`, by naming one.
/// So four of php's twelve externals need no memory at all, and this is them.
///
/// Five decisions are the specification's and none reads off the shape:
///
///   * **The delimiter that ends the run is the one this member opened
///     with**, and the *other* quote is ordinary content. `"a`b"` holds a
///     backtick and `` `a"b` `` holds a quote, so one comparison against
///     `mark.shut` is both of the scanner's two cases rather than a
///     simplification of them.
///   * **A `\x` is consumed before it is judged.** `is_escapable_sequence`
///     advances past the `x` and only then asks for a hex digit, so `\xZ`
///     leaves the cursor past both bytes and they are matter. Reading the
///     probe as non-destructive puts the extent one byte early on every
///     malformed hex escape.
///   * **`\{` is not an escape.** It is consumed as two ordinary bytes, ahead
///     of the escape test, so that the `{` cannot go on to be read as the
///     opener of a `{$…}` interpolation.
///   * **A `$` ends the run only in front of a name**, and a digit is not the
///     start of one - `"$1"` is two bytes of matter, which is what makes
///     `preg_replace`'s replacement strings text rather than variables.
///   * **End of input refuses outright**, however much was consumed. php's
///     loop reaches `lexer->eof` only through its default arm and returns
///     `false` there, so an unterminated string yields no content token at
///     all - julia's rule and not elixir's, arrived at independently.
///
/// An empty run refuses, as every vein here does. That is the same
/// `has_content` the scanner starts at `false` and it is what lets the closing
/// quote, an ordinary terminal php spells for itself, be reached at all.
fn encapsed(mark: Mark, bytes: []const u8, at: u32) ?u32 {
    if (at > bytes.len) return null;
    var i = at;
    var after = mark.after;
    var any = false;
    while (true) : (any = true) {
        // The extent is taken at the top of each pass, as in `matter` and
        // `quoted`: a probe that runs two bytes into a `\xZ` and fails leaves
        // those bytes as matter, so the extent cannot be the cursor.
        const end = i;
        if (i >= bytes.len) return null;
        // The scanner's first two cases: the quote that closes *this* member
        // ends the run, and the other one is ordinary content. Asked ahead of
        // the switch so a mark whose delimiter collided with a sigil below
        // could not be shadowed by it.
        if (bytes[i] == mark.shut) return if (any) end - at else null;
        switch (bytes[i]) {
            '\\' => {
                i += 1;
                const next: ?u8 = if (i < bytes.len) bytes[i] else null;
                if (next == '{') {
                    i += 1;
                } else if (mark.shut == '`' and next == '`') {
                    return if (any) end - at else null;
                } else if (escapes(bytes, &i)) {
                    return if (any) end - at else null;
                }
            },
            '$' => {
                i += 1;
                const next: u8 = if (i < bytes.len) bytes[i] else 0;
                if (next == '{' or (names(next) and !std.ascii.isDigit(next))) {
                    return if (any) end - at else null;
                }
            },
            // php's `-` case falls through to `[`'s when the run is not after
            // a variable, and `[`'s arm then consumes it - so outside that
            // context a dash is an ordinary byte.
            '-' => {
                i += 1;
                if (after and i < bytes.len and bytes[i] == '>') {
                    i += 1;
                    if (i < bytes.len and names(bytes[i])) return if (any) end - at else null;
                }
            },
            '[' => {
                if (after) return if (any) end - at else null;
                i += 1;
            },
            '{' => {
                i += 1;
                if (i < bytes.len and bytes[i] == '$') return if (any) end - at else null;
            },
            else => i += 1,
        }
        after = false;
    }
}

/// Whether the byte after a backslash makes an escape php's grammar spells,
/// advancing over the `x` of a hex escape the way the specification's own
/// probe does.
fn escapes(bytes: []const u8, i: *u32) bool {
    if (i.* >= bytes.len) return false;
    return switch (bytes[i.*]) {
        'n', 'r', 't', 'v', 'e', 'f', '\\', '$', '"' => true,
        // `\u` is true even where no `{…}` follows: the grammar handles
        // `"\u{$a}"` by spelling a bare `\u` as content itself.
        'u' => true,
        '0'...'7' => true,
        'x' => blk: {
            i.* += 1;
            break :blk i.* < bytes.len and std.ascii.isHex(bytes[i.*]);
        },
        else => false,
    };
}

/// php's `is_valid_name_char`. Every byte at or above 0x80 counts, so this is
/// the same predicate on a UTF-8 lead byte as the specification's on a
/// codepoint.
fn names(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c >= 0x80;
}

/// latex's `find_verbatim`, which is a raw region ending at a named close.
///
/// Twelve terminals differing in one string, and the walk that reads it is not
/// one of the three above. Four of its decisions are the specification's, and the
/// first two are why this could not be a row under someone else's walk:
///
///   * **The extent is the last byte the walk *marked*, not the cursor.** The
///     specification advances over a failed partial match of the close without
///     calling `mark_end`, so the cursor and the extent come apart and the extent
///     has to be carried. Every other walk here derives its extent from the
///     cursor at the top of a pass.
///   * **A run can be refused after its close has been found.** `has_marked` is
///     the return value, and a region whose every byte was eaten by partial
///     matches marked nothing - so `\end{verb\end{verbatim}` finds a whole close
///     and yields no token, because nothing in front of it was ever content. That
///     is a refusal none of the other three can express.
///   * **A command name does not end where it stops matching.** With `command`
///     set, a letter or a `:` `_` `@` behind the match makes the match itself
///     content: `\fifoo` is one command, so the walk marks past the `\fi` and
///     carries on looking. Only `_trivia_raw_fi` asks for this.
///   * **Running out of input mid-close hands back what was marked**, rather than
///     refusing - elixir's rule and not julia's. An unterminated `verbatim` is the
///     rest of the file, which is the reading somebody still typing needs.
fn verbatim(mark: Mark, bytes: []const u8, at: u32) ?u32 {
    if (at > bytes.len) return null;
    const whole: u32 = @intCast(1 + mark.tail.len);
    var i = at;
    // The last `mark_end`, and null while the specification's `has_marked` is
    // still false. Not a length, because the two diverge: a partial match moves
    // `i` and leaves this alone.
    var end: ?u32 = null;
    while (i < bytes.len) {
        const got = probe(mark, bytes, i) orelse break;
        if (got == 0) {
            // Not the close, so one byte of content - and the mark goes *past*
            // it, which is why an extent can be one byte longer than the last
            // content byte's offset.
            i += 1;
            end = i;
            continue;
        }
        if (got < whole) {
            // A proper prefix, consumed and deliberately unmarked.
            i += got;
            continue;
        }
        if (!mark.command) break;
        if (i + whole >= bytes.len) break;
        if (!nameish(bytes[i + whole])) break;
        i += whole;
        end = i;
    }
    const stop = end orelse return null;
    return stop - at;
}

/// How many bytes of the close stand at `from`, or null where the input ran out
/// before the close could be settled either way. `whole` bytes means the close;
/// fewer means a prefix that then diverged.
fn probe(mark: Mark, bytes: []const u8, from: u32) ?u32 {
    var k: u32 = 0;
    while (k <= mark.tail.len) : (k += 1) {
        if (from + k >= bytes.len) return null;
        const want = if (k == 0) mark.shut else mark.tail[k - 1];
        if (bytes[from + k] != want) return k;
    }
    return k;
}

/// A byte that keeps a latex command name going, so a close that is a command
/// name has not ended yet.
fn nameish(c: u8) bool {
    return c == ':' or c == '_' or c == '@' or std.ascii.isAlphabetic(c);
}

fn breaks(c: u8) bool {
    return c == '\n' or c == '\r';
}

fn blank(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

/// The longest delimiter C++ allows between `R"` and `(`. The standard's own
/// cap, and it is what keeps the backwards walk from scanning a whole file when
/// the bytes at hand are not a raw string at all.
const cpp_tag_max = 16;

/// How far the content at `at` runs before the mark that ends it, or null if
/// this is not content or the run would be empty.
pub fn reach(dialect: Dialect, bytes: []const u8, at: u32) ?u32 {
    if (at > bytes.len) return null;
    return switch (dialect) {
        .rust_block => rustBlock(bytes, at),
        .cpp_raw => cppRaw(bytes, at),
        .kotlin_block => slashStar(bytes, at, .keep),
        .swift_block => slashStar(bytes, at, .refuse),
        .ocaml_comment => ocamlComment(bytes, at),
        .html_comment => htmlComment(bytes, at),
        .rust_string => rustString(bytes, at),
        .julia_block => juliaBlock(bytes, at),
        .lua_string, .lua_comment => luaContent(bytes, at),
        // Swift's raw string answers only as a close; see `swiftRaw`, and the
        // header of its row in `outside.zig` for why the interpolating half is
        // declined rather than approximated.
        .swift_raw => null,
    };
}

/// What a `/* … ` that never closed comes to at end of input. The one place
/// Kotlin's specification and Swift's part company over the same walk.
const Unterminated = enum { keep, refuse };

/// Kotlin's and Swift's nesting block comment, delimiters included.
///
/// The first vein whose run *is* the token rather than the middle of one. Both
/// grammars declare `multiline_comment` as a terminal extra with no rule, so
/// there is no `/*` for the parser to lex and nothing to walk back to; the hand
/// is handed the opener as well. That costs no state - the run is still
/// computed from position alone, which is what puts it in this file rather than
/// in `fence`.
///
/// Transcribed from kotlin's pinned `scan_multiline_comment`, including the
/// decision a reading of the language would have got wrong: a `/` that was not
/// preceded by `*` opens a nested comment when a `*` follows it. Swift's
/// `eat_comment` is the same three cases over the same `after_star` flag, which
/// is why one walk serves two veins rather than two copies serving one each.
///
/// They differ in exactly one place and it is the last line. Kotlin accepts an
/// unterminated comment at end of input, on the ground that the alternative is
/// the delimiters being read as operators; Swift's returns
/// `STOP_PARSING_END_OF_FILE` and refuses, so its `/*` at the end of a truncated
/// file falls back to the operators rather than swallowing the tail. That is a
/// parameter and not a shared default, because guessing either way would have
/// been a wrong tree in one of the two languages.
fn slashStar(bytes: []const u8, at: u32, ending: Unterminated) ?u32 {
    var i = at;
    if (i + 1 >= bytes.len or bytes[i] != '/' or bytes[i + 1] != '*') return null;
    i += 2;

    var after_star = false;
    var depth: u32 = 1;
    while (i < bytes.len) {
        switch (bytes[i]) {
            '*' => {
                i += 1;
                after_star = true;
            },
            '/' => {
                i += 1;
                if (after_star) {
                    after_star = false;
                    depth -= 1;
                    if (depth == 0) return i - at;
                } else if (i < bytes.len and bytes[i] == '*') {
                    depth += 1;
                    i += 1;
                }
            },
            else => {
                i += 1;
                after_star = false;
            },
        }
    }
    return switch (ending) {
        .keep => i - at,
        .refuse => null,
    };
}

/// OCaml: a whole nesting `(* … *)` comment, delimiters included.
///
/// Kotlin's shape with different marks, and the same reason for being here
/// rather than in the roll: `comment` is a terminal extra with no rule, so
/// there is no `(*` for the parser to lex and a fixed pattern cannot count the
/// nesting the manual requires.
///
/// Two marks rather than one byte apiece, so the walk steps two on a match and
/// cannot read the middle `*` of `(*)` as both halves of a close.
///
/// **What this deliberately does not do.** The manual also says a `"…"` inside
/// a comment is a string, so `(* " *) " *)` is one comment rather than two -
/// and a scanner that honours it has to be willing to run to end of input
/// looking for a quote that a typo may have left unclosed. Nesting alone cannot
/// swallow a file, mis-reads only a comment holding an *odd* number of quotes
/// with a `*)` between them, and there are none in the corpus. The wrong
/// direction to be wrong in is the one that eats the rest of the file.
fn ocamlComment(bytes: []const u8, at: u32) ?u32 {
    if (!std.mem.startsWith(u8, bytes[@min(at, bytes.len)..], "(*")) return null;
    var depth: u32 = 1;
    var i = at + 2;
    while (i < bytes.len) {
        if (std.mem.startsWith(u8, bytes[i..], "(*")) {
            depth += 1;
            i += 2;
        } else if (std.mem.startsWith(u8, bytes[i..], "*)")) {
            i += 2;
            depth -= 1;
            if (depth == 0) return i - at;
        } else i += 1;
    }
    // Unterminated is accepted at end of input, as every vein here does: the
    // alternative is `(*` read as a paren and an operator on the last line of a
    // file somebody is still typing.
    return i - at;
}

/// Rust: to the `*/` that closes the comment we are already inside, which is
/// the one that returns depth to zero and not the first one seen.
///
/// Depth starts at one because the `/*` that opened it is behind us; the parser
/// lexed it as its own terminal, which is the whole reason this run needs an
/// external at all - a fixed pattern cannot count.
fn rustBlock(bytes: []const u8, at: u32) ?u32 {
    if (!std.mem.endsWith(u8, bytes[0..at], "/*")) return null;
    var depth: u32 = 1;
    var i = at;
    while (i < bytes.len) {
        if (std.mem.startsWith(u8, bytes[i..], "/*")) {
            depth += 1;
            i += 2;
        } else if (std.mem.startsWith(u8, bytes[i..], "*/")) {
            // The one that closes us is the grammar's own terminal, so the run
            // stops in front of it rather than consuming it.
            if (depth == 1) break;
            depth -= 1;
            i += 2;
        } else i += 1;
    }
    return if (i == at) null else i - at;
}

/// C++: to `)` plus the delimiter this literal opened with plus `"`.
///
/// The delimiter is read back out of the bytes rather than remembered, which is
/// what lets the whole file be stateless. `(` is immediately behind a content
/// offset by construction, and the delimiter is the run between it and the `"`
/// of the opener.
fn cppRaw(bytes: []const u8, at: u32) ?u32 {
    const delim = openedWith(bytes, at) orelse return null;
    var mark: [cpp_tag_max + 2]u8 = undefined;
    mark[0] = ')';
    @memcpy(mark[1 .. 1 + delim.len], delim);
    mark[1 + delim.len] = '"';
    const close = std.mem.indexOf(u8, bytes[at..], mark[0 .. delim.len + 2]) orelse return null;
    return if (close == 0) null else @intCast(close);
}

/// How long the mark that ends this vein's run is, for the veins whose cast
/// names a `close` of its own.
///
/// `reach` stops in front of the closing mark because the grammar usually spells
/// it as an ordinary terminal; where the grammar makes the closer external too,
/// this answers it. Same discipline as `reach`: position in, length out.
pub fn shut(dialect: Dialect, bytes: []const u8, at: u32) ?u32 {
    if (at >= bytes.len) return null;
    return switch (dialect) {
        .rust_string => if (bytes[at] == '"') 1 else null,
        .lua_string, .lua_comment => luaBracket(bytes, at, ']'),
        .swift_raw => swiftRaw(bytes, at),
        else => null,
    };
}

/// Swift: a raw string that never interpolates, opener and closer included.
///
/// `slashStar`'s shape - the run *is* the token - over a delimiter the bytes
/// name rather than a fixed one. `#*"` opens, and only `"` followed by exactly
/// that many hashes closes, which is what makes `##"a "# b"##` one literal and
/// not two: the `"#` at its middle is a hash short and is ordinary text.
///
/// Transcribed from tree-sitter-swift's `eat_raw_str_part` with its
/// `ongoing_raw_str_hash_count` pinned at zero, which is the whole of what this
/// vein can honestly answer. That scanner produces two terminals from this one
/// walk and only the second is stateless:
///
///   * **`raw_str_end_part`** - what this returns. The width is read off the
///     opener sitting at `at`, so position alone settles it, which is the bar
///     for living in this file at all.
///   * **`raw_str_part`** - declined. It ends *before* a `\#(` and hands the
///     interpolation to the grammar; the parser then resumes the literal after
///     the `)`, at an offset whose bytes say nothing about how wide the
///     delimiter was. C++'s `openedWith` recovers a delimiter by walking back
///     because the standard caps it at sixteen identifier bytes and the `(` is
///     immediately behind. Swift's resume point has an arbitrary expression
///     behind it - parens, strings and comments of its own - so there is no
///     bounded walk back to the opener, and the count would have to be
///     remembered. Remembering is `fence`'s job, and `fence` cannot hold this
///     either: its cast is `open`/`body`/`close` as three tokens and swift's
///     opener has no token of its own to push a span on.
///
/// So an interpolating raw string gets silence and today's parse, and a
/// non-interpolating one gets its extent. Answering the first `raw_str_part`
/// and then stalling at the resume would be the worse of the two, because the
/// bytes would be under a node built on a delimiter nothing checked.
fn swiftRaw(bytes: []const u8, at: u32) ?u32 {
    var i = at;
    var hashes: u32 = 0;
    while (i < bytes.len and bytes[i] == '#') : (i += 1) hashes += 1;
    // No hash is `line_string_literal`, whose interior the grammar spells for
    // itself; a hash not followed by a quote is a compiler directive, which is
    // a different external and not this row's to answer.
    if (hashes == 0 or i >= bytes.len or bytes[i] != '"') return null;
    i += 1;

    while (i < bytes.len) {
        var last: u8 = 0;
        while (i < bytes.len and bytes[i] != '#') : (i += 1) last = bytes[i];
        var seen: u32 = 0;
        while (i < bytes.len and bytes[i] == '#' and seen < hashes) : (i += 1) seen += 1;
        if (seen != hashes) continue;
        // A backslash before the matched hashes and a `(` after them is the
        // interpolation this vein declines; stopping here rather than reading
        // on is what keeps the refusal from swallowing the rest of the file.
        if (last == '\\' and i < bytes.len and bytes[i] == '(') return null;
        if (last == '"') return i - at;
    }
    // Unterminated refuses, as swift's own scanner does: it runs off the end
    // and returns false rather than handing back the tail of the file.
    return null;
}

/// How long the mark that opens this vein's run is, for the veins whose cast
/// names an `opens` the grammar left external.
///
/// The mirror of `shut`, and the reason both exist: a vein is up to three
/// answers over one region, and which of them the grammar spells for itself
/// differs per language rather than per mechanism.
pub fn open(dialect: Dialect, bytes: []const u8, at: u32) ?u32 {
    return switch (dialect) {
        .lua_string => luaBracket(bytes, at, '['),
        .lua_comment => blk: {
            if (!std.mem.startsWith(u8, bytes[at..], "--")) break :blk null;
            const n = luaBracket(bytes, at + 2, '[') orelse break :blk null;
            break :blk n + 2;
        },
        else => null,
    };
}

/// Rust: an ordinary string's content, up to the quote or backslash that ends
/// it.
///
/// The vein where neither end is external and yet the middle is: rust spells
/// its opener as the pattern `/[bc]?"/` and its escapes as their own rule, so
/// the run is simply everything that is neither. Empty runs are refused, which
/// is what lets `string_close` answer the quote a zero-length content would
/// otherwise sit in front of forever; the pinned scanner leans on the same
/// fallthrough.
fn rustString(bytes: []const u8, at: u32) ?u32 {
    var i = at;
    while (i < bytes.len and bytes[i] != '"' and bytes[i] != '\\') i += 1;
    // Reaching the end without a closer is not a string, and the spec refuses
    // it rather than handing back the rest of the file.
    if (i == bytes.len) return null;
    return if (i == at) null else i - at;
}

/// The delimiter of the raw string whose content starts at `at`, by walking
/// back over `(` and the delimiter to the opener's quote.
fn openedWith(bytes: []const u8, at: u32) ?[]const u8 {
    if (at == 0 or bytes[at - 1] != '(') return null;
    var j = at - 1;
    while (j > 0 and at - j <= cpp_tag_max + 1) : (j -= 1) {
        if (bytes[j - 1] == '"') return bytes[j .. at - 1];
        if (!isTagByte(bytes[j - 1])) return null;
    }
    return null;
}

/// How far the delimiter at `at` runs, or null if this is not one.
///
/// It appears twice in a literal, so both sides are read here: after the
/// opener's `R"` it is terminated by `(`, and after the content's `)` it is
/// terminated by `"`. Requiring one of those two on each side is what stops an
/// ordinary `name(` from reading as a delimiter, since by itself a delimiter is
/// just a run of identifier bytes.
pub fn tag(bytes: []const u8, at: u32) ?u32 {
    if (at == 0 or at > bytes.len) return null;
    const opening = bytes[at - 1] == '"';
    if (!opening and bytes[at - 1] != ')') return null;
    var i = at;
    while (i < bytes.len and i - at < cpp_tag_max and isTagByte(bytes[i])) i += 1;
    if (i == at or i == bytes.len) return null;
    if (bytes[i] != (if (opening) @as(u8, '(') else @as(u8, '"'))) return null;
    return i - at;
}

/// The standard's d-char: anything but a space, a control, and the six that
/// would make the close ambiguous.
fn isTagByte(c: u8) bool {
    return switch (c) {
        ' ', '(', ')', '\\', '"', '\t'...'\r' => false,
        else => c > 0x20,
    };
}

const t = std.testing;

const julia_str_3: Mark = .{ .shut = '"', .wide = 3, .interpolates = true };
const julia_str_1: Mark = .{ .shut = '"', .interpolates = true };
const julia_raw_1: Mark = .{ .shut = '"' };
const julia_cmd_1: Mark = .{ .shut = '`', .interpolates = true };

test "marrow: a julia triple-quote closes on three anywhere, not only at a line start" {
    // The rule elixir has and julia does not, and the two answers are as far
    // apart as they can be on the same bytes: julia stops in front of the
    // three quotes, and elixir - for which a heredoc close is only a close
    // where a line begins - walks straight past them and hands back the rest
    // of the file. That is the assertion that catches a future widening of
    // `matter` to cover both.
    const src = "abc\"\"\"rest";
    try t.expectEqual(Run{ .matter = 3 }, walk(.julia_quoted, julia_str_3, src, 0));
    try t.expectEqual(@as(?u32, 10), matter(julia_str_3, src, 0));
}

test "marrow: two of a triple delimiter are matter, not a close" {
    // The probe runs two bytes into `""x` and fails, and the extent is the top
    // of the pass rather than the cursor - so the two quotes stay matter and
    // are not lost.
    try t.expectEqual(Run{ .matter = 6 }, walk(.julia_quoted, julia_str_3, "ab\"\"cd\"\"\"", 0));
}

test "marrow: a julia delimiter with nothing in front of it is the close, at its own width" {
    try t.expectEqual(Run{ .close = 3 }, walk(.julia_quoted, julia_str_3, "\"\"\"tail", 0));
    try t.expectEqual(Run{ .close = 1 }, walk(.julia_quoted, julia_str_1, "\"tail", 0));
    try t.expectEqual(Run{ .close = 1 }, walk(.julia_quoted, julia_cmd_1, "`tail", 0));
}

test "marrow: julia refuses at end of input where elixir hands back matter" {
    // The difference that made this a walk and not a row. julia's loop falls
    // out of the bottom with no result symbol, so an unterminated string is no
    // token; elixir's runs to the end. Both spellings, side by side, so the
    // divergence is pinned rather than described.
    try t.expectEqual(Run.none, walk(.julia_quoted, julia_str_1, "unterminated", 0));
    try t.expectEqual(@as(?u32, 12), matter(julia_str_1, "unterminated", 0));
}

test "marrow: an interpolating julia run stops at a bare dollar and at a backslash" {
    try t.expectEqual(Run{ .matter = 3 }, walk(.julia_quoted, julia_str_1, "abc$(x)\"", 0));
    try t.expectEqual(Run{ .matter = 3 }, walk(.julia_quoted, julia_str_1, "abc\\n\"", 0));
    // And a `$` at the very front is an empty run, which refuses.
    try t.expectEqual(Run.none, walk(.julia_quoted, julia_str_1, "$(x)\"", 0));
}

test "marrow: a raw julia run keeps the dollar and stops only on an escape it owns" {
    // Raw does not interpolate, so `$` is matter; it yields on `\"` and on
    // `\\`, and eats every other escape whole. The yield is *at* the
    // backslash and not after it - the spec marks its extent at the top of the
    // pass - so the pair goes to the grammar whole.
    try t.expectEqual(Run{ .matter = 3 }, walk(.julia_quoted, julia_raw_1, "a$b\\\"c\"", 0));
    try t.expectEqual(Run{ .matter = 1 }, walk(.julia_quoted, julia_raw_1, "a\\\\b\"", 0));
    try t.expectEqual(Run{ .matter = 4 }, walk(.julia_quoted, julia_raw_1, "a\\nb\"", 0));
}

test "marrow: the family picks the walk, so elixir's rows cannot reach julia's" {
    // `walk` is the only door, and a family that is not julia's never runs
    // julia's decisions. The same bytes under elixir's family answer elixir's
    // way - matter to the end - which is the control for the whole seating.
    try t.expectEqual(Run{ .matter = 12 }, walk(.elixir_quoted, julia_str_1, "unterminated", 0));
    try t.expectEqual(Run.none, walk(.none, julia_str_1, "abc\"", 0));
}

const php_encapsed: Mark = .{ .shut = '"' };
const php_encapsed_after: Mark = .{ .shut = '"', .after = true };
const php_execution: Mark = .{ .shut = '`' };
const php_execution_after: Mark = .{ .shut = '`', .after = true };

test "marrow: a php run stops in front of its own quote and eats the other one" {
    // One comparison standing in for the scanner's two cases, so both
    // directions are pinned: a backtick inside a double-quoted string is
    // content, and a double quote inside a backtick string is too.
    try t.expectEqual(Run{ .matter = 3 }, walk(.php_encapsed, php_encapsed, "abc\"tail", 0));
    try t.expectEqual(Run{ .matter = 7 }, walk(.php_encapsed, php_encapsed, "a`b`c d\"", 0));
    try t.expectEqual(Run{ .matter = 3 }, walk(.php_encapsed, php_execution, "abc`tail", 0));
    try t.expectEqual(Run{ .matter = 5 }, walk(.php_encapsed, php_execution, "a\"b\"c`", 0));
}

test "marrow: a php run with the delimiter already in front of it refuses" {
    // The empty run every vein here declines, and the reason php needs it: the
    // closing quote is an ordinary terminal the grammar spells, and a
    // zero-width content token would sit in front of it forever.
    try t.expectEqual(Run.none, walk(.php_encapsed, php_encapsed, "\"tail", 0));
}

test "marrow: php refuses at end of input however much it consumed" {
    // The specification reaches `lexer->eof` only through its default arm and
    // returns false there, so an unterminated string is no token at all -
    // julia's rule rather than elixir's, and the two are side by side here so
    // a future widening of one cannot quietly take the other.
    try t.expectEqual(Run.none, walk(.php_encapsed, php_encapsed, "unterminated", 0));
    try t.expectEqual(@as(?u32, 12), matter(.{ .shut = '"' }, "unterminated", 0));
}

test "marrow: a php dollar ends the run only in front of a name" {
    try t.expectEqual(Run{ .matter = 3 }, walk(.php_encapsed, php_encapsed, "abc$x\"", 0));
    try t.expectEqual(Run{ .matter = 3 }, walk(.php_encapsed, php_encapsed, "abc${x}\"", 0));
    try t.expectEqual(Run{ .matter = 3 }, walk(.php_encapsed, php_encapsed, "abc$_x\"", 0));
    // A digit is not the start of a name, which is the whole reason
    // `preg_replace("…", '$1', …)` is text: `$1` is two bytes of matter.
    try t.expectEqual(Run{ .matter = 5 }, walk(.php_encapsed, php_encapsed, "ab$1c\"", 0));
    // And a dollar at the very front is an empty run, which refuses.
    try t.expectEqual(Run.none, walk(.php_encapsed, php_encapsed, "$x\"", 0));
}

test "marrow: a php escape ends the run and a malformed hex escape does not" {
    try t.expectEqual(Run{ .matter = 3 }, walk(.php_encapsed, php_encapsed, "abc\\n\"", 0));
    try t.expectEqual(Run{ .matter = 3 }, walk(.php_encapsed, php_encapsed, "abc\\x41\"", 0));
    // `is_escapable_sequence` advances past the `x` before it asks for a hex
    // digit, so a `\xZ` is matter and the extent is past BOTH bytes. Reading
    // the probe as non-destructive puts this one byte early.
    try t.expectEqual(Run{ .matter = 6 }, walk(.php_encapsed, php_encapsed, "abc\\xZ\"", 0));
    // `\s` is not a php escape, so `preg_replace`'s own pattern is one run.
    try t.expectEqual(Run{ .matter = 10 }, walk(.php_encapsed, php_encapsed, "/(.*)\\s.*/\"", 0));
    // `\{` is consumed ahead of the escape test, so its brace can never go on
    // to be read as the opener of an interpolation. The unescaped form beside
    // it is what the difference costs: one yields at the brace, the other
    // carries it and yields at the `$`.
    try t.expectEqual(Run{ .matter = 1 }, walk(.php_encapsed, php_encapsed, "a{$b\"", 0));
    try t.expectEqual(Run{ .matter = 3 }, walk(.php_encapsed, php_encapsed, "a\\{$b\"", 0));
}

test "marrow: an execution run yields its own escaped backtick and a plain one does not" {
    try t.expectEqual(Run{ .matter = 1 }, walk(.php_encapsed, php_execution, "a\\`b`", 0));
    // The same bytes under the encapsed mark: `\`` is not one of php's
    // escapes, so the pair is matter and the run continues.
    try t.expectEqual(Run{ .matter = 4 }, walk(.php_encapsed, php_encapsed, "a\\`b\"", 0));
}

test "marrow: a brace ends a php run only when a dollar follows it" {
    try t.expectEqual(Run{ .matter = 3 }, walk(.php_encapsed, php_encapsed, "abc{$x}\"", 0));
    try t.expectEqual(Run{ .matter = 6 }, walk(.php_encapsed, php_encapsed, "abc{x}\"", 0));
}

test "marrow: subscript and member access end a run only after a variable" {
    // The parameter that is not carried: the same bytes read two ways, and
    // which one the parse state meant is which member it asked for.
    try t.expectEqual(Run.none, walk(.php_encapsed, php_encapsed_after, "[0]\"", 0));
    try t.expectEqual(Run{ .matter = 3 }, walk(.php_encapsed, php_encapsed, "[0]\"", 0));
    try t.expectEqual(Run.none, walk(.php_encapsed, php_encapsed_after, "->b\"", 0));
    try t.expectEqual(Run{ .matter = 3 }, walk(.php_encapsed, php_encapsed, "->b\"", 0));
    // An arrow with no name behind it is not member access, so it is matter -
    // and the parameter is spent after the first pass, so a later `[` in the
    // same run is content.
    try t.expectEqual(Run{ .matter = 5 }, walk(.php_encapsed, php_encapsed_after, "-> a[\"", 0));
    try t.expectEqual(Run{ .matter = 4 }, walk(.php_encapsed, php_execution_after, "-x[y`", 0));
}

test "marrow: the family picks the walk, so php's rows cannot reach elixir's" {
    // The control for the whole seating, in the shape julia's already has.
    // php refuses an unterminated run; elixir's family over the identical mark
    // hands back matter to the end, and julia's stops at a bare dollar php
    // reads as text.
    try t.expectEqual(Run.none, walk(.php_encapsed, php_encapsed, "ab$1c", 0));
    try t.expectEqual(Run{ .matter = 5 }, walk(.elixir_quoted, php_encapsed, "ab$1c", 0));
    try t.expectEqual(Run{ .matter = 2 }, walk(.julia_quoted, .{ .shut = '"', .interpolates = true }, "ab$1c\"", 0));
    try t.expectEqual(Run.none, walk(.none, php_encapsed, "abc\"", 0));
}

test "marrow: a rust block comment ends on the close that balances it" {
    const src = "/* one /* two */ three */ after";
    // Content starts past the opening `/*`, and runs to the last `*/`.
    try t.expectEqual(@as(?u32, 21), reach(.rust_block, src, 2));
    try t.expectEqualStrings(" one /* two */ three ", src[2 .. 2 + 21]);
}

test "marrow: a rust block comment with no nesting stops at the first close" {
    try t.expectEqual(@as(?u32, 5), reach(.rust_block, "/*hello*/", 2));
}

test "marrow: an empty rust block comment declines rather than answering zero" {
    try t.expectEqual(@as(?u32, null), reach(.rust_block, "/**/", 2));
}

test "marrow: swift's block comment nests exactly as kotlin's does" {
    const nested = "/* x /* y */ z */ after";
    try t.expectEqual(@as(?u32, 17), reach(.swift_block, nested, 0));
    try t.expectEqual(reach(.kotlin_block, nested, 0), reach(.swift_block, nested, 0));

    // The decision a reading of either language would have got wrong: an
    // unescaped `/` with a `*` behind it opens a level.
    try t.expectEqual(@as(?u32, 9), reach(.swift_block, "/*/*x*/*/", 0));
}

test "marrow: an unterminated comment is kotlin's token and not swift's" {
    // The one line the two veins differ on. Kotlin takes the tail rather than
    // let `/*` be read as two operators; swift's scanner returns end-of-file
    // and refuses, and a shared default would have been wrong for one of them.
    const cut = "/* never closed";
    try t.expectEqual(@as(?u32, 15), reach(.kotlin_block, cut, 0));
    try t.expectEqual(@as(?u32, null), reach(.swift_block, cut, 0));
}

test "marrow: content not behind an opener is not content" {
    // The same bytes, asked at an offset no `/*` precedes.
    try t.expectEqual(@as(?u32, null), reach(.rust_block, "hello */", 0));
}

test "marrow: a cpp raw string ends on its own captured delimiter" {
    const src = "R\"tag(body )x\" more)tag\";";
    // `)x"` is not the close, because the delimiter captured at the open is `tag`.
    try t.expectEqual(@as(?u32, 13), reach(.cpp_raw, src, 6));
    try t.expectEqualStrings("body )x\" more", src[6 .. 6 + 13]);
}

test "marrow: a cpp raw string with an empty delimiter still closes" {
    try t.expectEqual(@as(?u32, 4), reach(.cpp_raw, "R\"(body)\";", 3));
}

test "marrow: an ordinary call is not a raw string delimiter" {
    // `name(` has the shape of a delimiter and none of the context.
    try t.expectEqual(@as(?u32, null), tag("name(x);", 0));
    try t.expectEqual(@as(?u32, null), reach(.cpp_raw, "name(x);", 5));
}

test "marrow: a delimiter reads on both sides of the content" {
    try t.expectEqual(@as(?u32, 3), tag("R\"tag(body)tag\";", 2));
    try t.expectEqual(@as(?u32, 3), tag("R\"tag(body)tag\";", 11));
}

test "marrow: an unterminated raw string declines rather than running to the end" {
    try t.expectEqual(@as(?u32, null), reach(.cpp_raw, "R\"tag(body", 6));
}

/// HTML: a whole comment, `<!--` through `-->`.
///
/// The same self-contained shape as kotlin's, and the reason there are two of
/// them rather than one parameterised row: the two languages disagree about
/// every decision that is not the spelling. HTML's close does not nest and its
/// run of dashes is greedy, so `--->` closes; an unterminated comment is
/// refused outright rather than accepted at end of input.
fn htmlComment(bytes: []const u8, at: u32) ?u32 {
    if (!std.mem.startsWith(u8, bytes[at..], "<!--")) return null;
    var dashes: u32 = 0;
    var i = at + 4;
    while (i < bytes.len) : (i += 1) {
        switch (bytes[i]) {
            '-' => dashes += 1,
            '>' => if (dashes >= 2) return i + 1 - at else {
                dashes = 0;
            },
            else => dashes = 0,
        }
    }
    return null;
}

/// Julia: the rest of a nesting block comment, closing `=#` included.
///
/// kotlin's function with `=` and `#` in place of `*` and `/`, and two
/// deliberate differences the pinned scanner settles: the run *includes* its
/// closer, which is why the grammar calls it a rest rather than a content, and
/// an unterminated comment is refused where kotlin accepts one.
fn juliaBlock(bytes: []const u8, at: u32) ?u32 {
    var after_eq = false;
    var depth: u32 = 1;
    var i = at;
    while (i < bytes.len) {
        switch (bytes[i]) {
            '=' => {
                i += 1;
                after_eq = true;
            },
            '#' => {
                i += 1;
                if (after_eq) {
                    after_eq = false;
                    depth -= 1;
                    if (depth == 0) return i - at;
                } else if (i < bytes.len and bytes[i] == '=') {
                    depth += 1;
                    i += 1;
                }
            },
            else => {
                i += 1;
                after_eq = false;
            },
        }
    }
    return null;
}

/// Lua: a long bracket of either polarity - `[==[` to open, `]==]` to close.
///
/// The level is however many `=` sit between the two brackets, and a close only
/// closes an open of the same level, which is what lets a Lua long string hold
/// a `]]`.
fn luaBracket(bytes: []const u8, at: u32, side: u8) ?u32 {
    if (at >= bytes.len or bytes[at] != side) return null;
    var i = at + 1;
    while (i < bytes.len and bytes[i] == '=') i += 1;
    if (i >= bytes.len or bytes[i] != side) return null;
    return i + 1 - at;
}

/// Lua: a long bracket's content, up to the close that matches the level the
/// open declared.
///
/// The level is not carried; it is read back out of the bytes, since the open
/// is a bracket run ending immediately before `at`. That is the same walk
/// `cppRaw` does, and the same reason this file needs no state.
///
/// An empty long string answers at zero width, which `[[]]` needs and the
/// pinned scanner also gives. Nothing here remembers that it did; the memory is
/// `Carry.pinned`, which pins any hand, and the caller consults it so that the
/// close sharing this offset is reached on the second ask. An unterminated run
/// is still refused, because the level never closed at all.
fn luaContent(bytes: []const u8, at: u32) ?u32 {
    const level = luaLevel(bytes, at) orelse return null;
    var i = at;
    while (i < bytes.len) : (i += 1) {
        if (bytes[i] != ']') continue;
        if (luaBracket(bytes, i, ']')) |n| if (n == level) break;
    }
    return if (i >= bytes.len) null else i - at;
}

/// How many bytes the long bracket that opened the run at `at` spans, by
/// walking back over its `=` run to the bracket that started it.
fn luaLevel(bytes: []const u8, at: u32) ?u32 {
    if (at == 0 or bytes[at - 1] != '[') return null;
    var j = at - 1;
    while (j > 0 and bytes[j - 1] == '=') j -= 1;
    if (j == 0 or bytes[j - 1] != '[') return null;
    return at - j + 1;
}
