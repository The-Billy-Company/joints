//! The joints CLI.
//!
//! Seven verbs, in two groups. Four look at the machinery: `grammar` imports a
//! tree-sitter `grammar.json` and reports what the press made of it, `state`
//! prints one LR state, `lex` runs the terminal scanner over a real file, and
//! `survey` is rung 1 of `research/joinery/TESTING.md` — the measurement that
//! decided whether the whole package was a good idea. Two are the product:
//! `parse` returns a tree, `amend` returns the tree again after an edit without
//! re-reading the file, and `mint` turns a grammar into a folio. All three are
//! real now; the machinery verbs are why they could be written at all.
//!
//! Exit codes follow the family: 0 ran, 1 a clean negative answer, 2 an error.
//! `survey` uses that 1 for something specific: the kill condition tripped.
//!
//! This file is the dispatcher and nothing else. Each verb is one sibling with
//! one `run`, and `verbs` below is the only place the seven are enumerated, so
//! the usage text a reader is shown and the table a run is dispatched through
//! cannot describe different sets. They used to: dispatch was a chain of seven
//! `std.mem.eql` arms each with its own arity guard, and the synopsis was a
//! hand-kept block above it that nothing checked against them.

const std = @import("std");
const joints = @import("joints");

/// Who this binary is, and what it can be asked to trace. Both are declared on
/// the package and re-exported here because the engine reads them off the ROOT
/// module of whatever compilation it lands in, and there are two: this face is
/// the executable's root, `src/root.zig` is the library's and the test build's.
/// Restating them would be two copies of one identity, free to disagree.
pub const irgx_brand = joints.irgx_brand;
pub const irgx_lenses = joints.irgx_lenses;

/// One verb, and everything the dispatcher knows about it.
const Verb = struct {
    /// What the user types.
    name: []const u8,
    /// How many arguments after the verb it cannot work without. The guard runs
    /// once, here, so a `run` may index `args[0..min]` without checking.
    min: u8,
    /// The tail of `joints: <name> needs …`, printed when `min` is not met.
    needs: []const u8,
    /// Its line in the usage block, minus the leading `joints `.
    spell: []const u8,
    /// What it does, one clause, aligned into a column by `usage`.
    does: []const u8,
    /// Extra usage lines for a verb with more than one form. `state` has four.
    also: []const []const u8 = &.{},
    run: *const fn (std.mem.Allocator, std.Io, *std.Io.Writer, []const []const u8) anyerror!u8,
};

const verbs = [_]Verb{
    .{
        .name = "grammar",  .min = 1,  .run = &@import("grammar.zig").run,
        .needs = "a path to a grammar.json",
        .spell = "grammar <grammar.json>",
        .does = "import a tree-sitter grammar, report its shape",
    },
    .{
        .name = "lex",  .min = 2,  .run = &@import("lex.zig").run,
        .needs = "a grammar.json and a source file",
        .spell = "lex <grammar.json> <file>",
        .does = "tokenize a file, print the stream",
    },
    .{
        .name = "survey",  .min = 2,  .run = &@import("survey.zig").run,
        .needs = "a grammar.json and at least one source file",
        .spell = "survey <grammar.json> <file>...",
        .does = "measure segment effects (rung 1)",
    },
    .{
        .name = "state",  .min = 2,  .run = &@import("state.zig").run,
        .needs = "a grammar.json and a state number (or --census and a terminal)",
        .spell = "state <grammar.json> <n>",
        .does = "print one LR state: its items and its row",
        .also = &.{
            "  joints state <grammar.json> --census <terminal>...  count those terminals over every state",
            "  joints state <grammar.json> --holding <item>  name the states holding a reading",
            "  joints state <grammar.json> --chain <n>  how a parse reaches n, and where a fold there goes",
        },
    },
    .{
        .name = "parse",  .min = 2,  .run = &@import("parse.zig").run,
        .needs = "a grammar.json and at least one source file",
        .spell = "parse <grammar.json|folio> <file>...",
        .does = "parse a file, print the tree",
    },
    .{
        .name = "amend",  .min = 2,  .run = &@import("amend.zig").run,
        .needs = "a grammar.json, a source file and an edit",
        .spell = "amend <grammar.json|folio> <file> FROM..TO=TEXT...",
        .does = "re-parse across edits",
    },
    .{
        .name = "mint",  .min = 1,  .run = &@import("mint.zig").run,
        .needs = "a grammar.json or a folio",
        .spell = "mint <grammar.json|folio>... [-o P]",
        .does = "press grammars into a folio",
        .also = &.{"                (several press into one codex), or read one back"},
    },
};

/// The synopsis block, built from `verbs` at comptime so it cannot name a verb
/// that does not exist or miss one that does.
///
/// Only the synopsis. The flag sections below it are per-verb prose and stay
/// hand-written: deriving them would mean carrying the same prose in the table,
/// which relocates the words without checking anything.
const synopsis = blk: {
    var out: []const u8 = "";
    for (verbs) |v| {
        var pad: []const u8 = "";
        // Column 32 for a spell that fits, and two spaces for one that does not:
        // three of the seven are too long to align and pushing the whole column
        // out to reach them costs the other four more than it buys.
        for (0..if (v.spell.len < 32) 32 - v.spell.len else 2) |_| pad = pad ++ " ";
        out = out ++ "  joints " ++ v.spell ++ pad ++ v.does ++ "\n";
        for (v.also) |line| out = out ++ line ++ "\n";
    }
    break :blk out;
};

/// The two flag vocabularies, from the enums that define them. The prose around
/// them below stays hand-written for the reason `synopsis` gives; the lists do
/// not, because a list is the one part of that prose a reader checks against
/// behaviour, and it was checked against nothing.
const intake = @import("intake.zig");
const mend_policies = intake.spellings(joints.kernel.quire.Mend, intake.default.mend);
const remint_policies = intake.spellings(joints.kernel.weave.Policy, intake.default.remint);

const usage =
    \\joints - parsing as algebra
    \\
    \\usage:
    \\
++ synopsis ++
    \\  joints --version
    \\
    \\a <file> of - is stdin
    \\
    \\parse flags:
    \\  --all       keep the anonymous nodes in the tree
    \\  --ranges    one node per line with the bytes it covers
    \\  --scars     the repair sites instead of the tree
    \\  --json      the whole answer as one JSON object per file
    \\  --quiet     the verdict only, no stdout
    \\  --mend=P    what to do at a refusal: 
++ mend_policies ++
    \\
    \\  --no-supply delete-only repair, the control arm
    \\  --language=NAME  which grammar, when the folio holds several
    \\
    \\amend flags:
    \\  --cold      re-read the whole file per edit, for the comparison
    \\  --policy=P  how far the re-mint window widens: 
++ remint_policies ++
    \\
    \\  --language=NAME  which grammar, when the folio holds several
    \\
    \\survey flags:
    \\  --exact     fuse two limbs only on identical claims, never by depth
    \\  --dump      print the first many-valued joint in full
    \\  --confess   print the standing limbs wherever a run hits a ceiling
    \\  --entries N survey a segment from N entry states, 0 for every one
    \\  --limbs N   carry at most N parses at once
    \\  --fan N     admit at most N floors when a fold outruns the segment
    \\  --churn N   sprout at most N limbs while reading one token
    \\
    \\environment:
    \\  JOINTS_TRACE=press,lex,joint,weave,folio,quire  light one or more phase traces
    \\                 (or `all`, which adds the search engine's own beneath them)
    \\
;

pub fn main(init: std.process.Init) !u8 {
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    // Before dispatch, because a verb that traces its own setup would otherwise
    // run with the lens mask still zero. This is also the only read of
    // `JOINTS_TRACE`: a phase asks `assay.trace(.press, …)` and never the
    // environment, so lighting one is a decision made in one place.
    joints.assay.install(.{});

    var out_buf: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &out_buf);
    const w = &stdout.interface;
    defer w.flush() catch {};

    if (args.len < 2) {
        try w.writeAll(usage);
        return 2;
    }
    const verb = args[1];
    const rest = args[2..];

    if (std.mem.eql(u8, verb, "--version") or std.mem.eql(u8, verb, "-V")) {
        try w.print("joints {s}\n", .{@import("build_options").version});
        return 0;
    }

    for (verbs) |v| {
        if (!std.mem.eql(u8, verb, v.name)) continue;
        if (rest.len < v.min) {
            try w.print("joints: {s} needs {s}\n", .{ v.name, v.needs });
            return 2;
        }
        return v.run(gpa, init.io, w, rest);
    }

    try w.writeAll(usage);
    return 2;
}

test {
    std.testing.refAllDecls(@This());
    _ = joints;
    // Named rather than left to `refAllDecls`, which reaches public decls: the
    // face's siblings are reached here only through `verbs`, which is a table of
    // function pointers and not a set of declarations anything walks. The test
    // asserting the verdict still says `surveyed` is the wiring gate under
    // `tool/sound.py`, and a gate collected by accident is not collected.
    _ = @import("parse.zig");
    _ = @import("grammar.zig");
    _ = @import("lex.zig");
    _ = @import("intake.zig");
}
