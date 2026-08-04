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
//! — bash's `variable_name` is `[a-zA-Z_]\w*`, ruby's `simple_symbol` is a
//! colon and a method name, Python's `comment` is a hash to end of line. The
//! author wrote C not because the bytes are exotic but because the terminal is
//! only legal *somewhere*, and a tree-sitter grammar has no way to say where.
//! We do: lexing here is state-directed, so the parse state's own permission
//! set is exactly the context those scanners were reaching for. Give the
//! terminal its spelling and the state decides where it may appear.
//!
//! So a row here is a **spelling plus its lexical standing**, keyed by the
//! terminal's own name — never by the language's. The same row serves every
//! grammar that uses the convention, which is why `string_content` appears
//! once rather than three times; and a grammar that means something different
//! by a name in this table is a bug report, not a special case to add.
//!
//! What is deliberately NOT here: a terminal that needs to remember something
//! about the bytes before it. A heredoc body needs the tag from the opener, a
//! Python string body needs which fence opened it, `_indent` needs the column
//! stack. Those are a different mechanism (run state, not a slate pattern) and
//! this table would be lying if it claimed them. Zero-width terminals are out
//! for a harder reason: the scan advances by the match, so a terminal that
//! accepts the empty string pins it at one offset forever.

const std = @import("std");
const g = @import("../../press/grammar.zig");

/// One external terminal this lexer can stand in for.
pub const Provision = struct {
    /// The name the grammar gave the terminal. Node identity rides on this
    /// being the grammar's own spelling of it, never ours.
    name: []const u8,
    /// The bytes it stands for, in the same dialect every other terminal's
    /// pattern is written in.
    pattern: []const u8,
    /// Its standing against the rest of the slate. An external carries no
    /// `token.immediate` and no `prec` in the IR — there is no wrapper to read
    /// them off — so the ones that need them declare them here. A string body
    /// that is not immediate is a body whose leading space the extras ate.
    lexis: g.Lexis = .{},
};

/// The roll. Ordered by the grammar that motivated each row, which is a
/// comment about provenance and nothing the lookup depends on.
pub const roll = [_]Provision{
    // Rust. `string_content` stops at a backslash rather than consuming it, so
    // the grammar's own `escape_sequence` — immediate, and longer at that
    // offset — still takes the escape. Stopping at the quote is what leaves
    // `string_close` a token to be.
    .{ .name = "string_content", .pattern = "[^\"\\\\]+", .lexis = .{ .immediate = true } },
    .{ .name = "string_close", .pattern = "\"", .lexis = .{ .immediate = true } },

    // Python. `comment` is an extra as well as an external, so once it can be
    // recognized the ordinary skip handles it.
    .{ .name = "comment", .pattern = "#[^\\n]*" },

    // Bash. The assignment left-hand side, a redirect's fd, and `test`'s flag
    // family. All three are plain spellings the state tells apart from a bare
    // `word`: only an assignment admits `variable_name`, only a redirect
    // admits `file_descriptor`.
    .{ .name = "variable_name", .pattern = "[a-zA-Z_][a-zA-Z0-9_]*" },
    .{ .name = "file_descriptor", .pattern = "[0-9]+" },
    .{ .name = "test_operator", .pattern = "-[a-zA-Z]+" },

    // Ruby. A symbol is a colon and a name, an operator, or `[]`; a hash key
    // is the same name with the colon on the other side. Ruby's newline is
    // significant rather than an extra, and the state is what knows whether a
    // statement may end here — which is the whole reason its scanner is C.
    .{
        .name = "simple_symbol",
        .pattern = ":(?:[a-zA-Z_][a-zA-Z0-9_]*[?!=]?|\\[\\]=?|<=>|===?|=~|![=~]?|<<?=?|>>?=?|\\*\\*|[+\\-*/%~^&|])",
    },
    .{ .name = "hash_key_symbol", .pattern = "[a-zA-Z_][a-zA-Z0-9_]*[?!]?" },
    .{ .name = "_line_break", .pattern = "\\n" },

    // JavaScript and TypeScript share their scanner. The ternary `?` is
    // external only to keep it away from optional chaining and optional
    // parameters, both of which the state already separates.
    .{ .name = "_ternary_qmark", .pattern = "\\?" },
    .{ .name = "_template_chars", .pattern = "[^`$\\\\]+", .lexis = .{ .immediate = true } },
    .{
        .name = "escape_sequence",
        .pattern = "\\\\(?:x[0-9a-fA-F]{2}|u\\{[0-9a-fA-F]+\\}|u[0-9a-fA-F]{4}|[0-7]{1,3}|[^0-9xu])",
        .lexis = .{ .immediate = true },
    },
    .{
        .name = "regex_pattern",
        .pattern = "(?:[^/\\\\\\[\\n]|\\\\.|\\[(?:[^\\]\\\\\\n]|\\\\.)*\\])+",
        .lexis = .{ .immediate = true },
    },
};

/// The spelling declared for an external terminal, if this lexer has one.
pub fn provisionFor(name: []const u8) ?*const Provision {
    for (&roll) |*p| if (std.mem.eql(u8, p.name, name)) return p;
    return null;
}

test "outside: every row is a distinct name with a non-empty pattern" {
    for (&roll, 0..) |*p, i| {
        try std.testing.expect(p.name.len > 0);
        try std.testing.expect(p.pattern.len > 0);
        for (roll[i + 1 ..]) |*q| try std.testing.expect(!std.mem.eql(u8, p.name, q.name));
    }
}

test "outside: a name nobody declared has no provision" {
    try std.testing.expect(provisionFor("_indent") == null);
    try std.testing.expect(provisionFor("string_content") != null);
}
