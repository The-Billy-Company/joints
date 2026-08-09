//! Does the package speak its own idiom? One root, one question, its own step.
//!
//! `zig build idiom`. Not part of `test`, and not in `proof.zig`, for a measured
//! reason: a proof about the whole package has to reach every module's decls by
//! name, and reaching a decl is what makes Zig analyse it. That analysis is the
//! cost - 1.24 s to compile a test root against 4.68 s, three runs a side - and
//! `-Dtest-filter` does not defer it, because a filtered-out test body is still
//! analysed. Left in `proof.zig` it would have added three and a half seconds to
//! the loop whose whole purpose is answering in a tenth of one.
//!
//! So it is its own root and its own step, alongside `census` and for the same
//! reason that one is: it answers a question about the package rather than
//! checking an invariant of a function, and it should be asked when you want it
//! asked. CI asks on every push.
//!
//! One rule lives here today. It is the right home for the next one.

const std = @import("std");

// ── One lifecycle rule, and something that holds it ───────────────────────────
//
// `deinit` comes in two shapes here, and the surface map read that as one
// inconsistency to settle by converting the twelve two-argument sites to one
// argument. It is not an inconsistency. The two shapes sit on either side of a
// real line:
//
//   a type that HOLDS an allocator frees with `deinit(self)`
//   a type that holds none frees with `deinit(self, gpa)`
//
// which is std's own managed/unmanaged split — `ArrayList` and every
// `…Unmanaged` take the allocator at the call because storing it in a value that
// small is the wrong trade. `sets.Matrix` is `{words, stride, bits}`, twenty-four
// bytes, and the press builds one per symbol; an allocator field would grow it by
// two thirds so that its `deinit` could look like `Scanner`'s. Converting the
// twelve would have made the hot half of this package less idiomatic to make a
// table in a plan document tidier.
//
// What was actually missing is that nothing held the line, so a new type took
// whichever shape its author had seen last. This does, and it reads the fact
// rather than a naming convention: the predicate is whether a field's *type* is
// an allocator, so it cannot be defeated by a field called `out`, `keys`, `a` or
// `s` — all four exist in this tree — and it counts an owned `ArenaAllocator` as
// holding one, because for `Grammar`, `Bound` and `Tables` that arena *is* the
// allocator they free from.
//
// A third way of owning an allocator is the one thing this cannot see. When one
// arrives it fails here, naming the type, which is the direction a proof about a
// convention should fail in: widen the predicate on purpose, or fix the type.

/// Whether `T` carries the allocator it frees from, by the type of its fields
/// rather than their names — and transitively, because `spine.Tree` holds no
/// allocator of its own and is still right to free with one argument: its `Wood`
/// has one, and `deinit(self)` can reach it. What the rule is really asking is
/// whether the allocator is reachable from the value, so the walk answers that
/// and not the shallower question it looks like.
///
/// Recursion terminates without a guard: it descends only into fields held **by
/// value**, and a Zig type cannot contain itself by value. A `*Self` back-edge is
/// a pointer, so it is not a field this follows.
fn holds(comptime T: type) bool {
    inline for (std.meta.fields(T)) |f| {
        if (f.type == std.mem.Allocator or f.type == std.heap.ArenaAllocator) return true;
        switch (@typeInfo(f.type)) {
            .@"struct", .@"union" => if (holds(f.type)) return true,
            else => {},
        }
    }
    return false;
}

/// The public decls of a container, or nothing for a type that has none.
fn shelf(comptime T: type) []const std.builtin.Type.Declaration {
    return switch (@typeInfo(T)) {
        .@"struct" => |s| s.decls,
        .@"union" => |u| u.decls,
        .@"enum" => |e| e.decls,
        .@"opaque" => |o| o.decls,
        else => &.{},
    };
}

/// A type whose `deinit` is not a lifecycle, and why it is not.
const Loan = struct { at: []const u8, why: []const u8 };

/// The one type in the package that frees itself and is not an owner. It is a
/// two-value return that every production caller takes apart: `Scanner.compile`
/// lifts `thaw`'s `munch` and `image` into the scanner's own fields and never
/// calls this `deinit` at all — `Scanner.deinit` frees the image later, from the
/// allocator the *scanner* stores. The two-argument shape is what a struct in
/// that position should have: half its memory belongs to a member that owns its
/// own allocator, half to the caller, and it stores neither because it outlives
/// neither. Giving it a `gpa` field to satisfy the rule above would have made it
/// claim a lifecycle nothing uses.
const loaned = [_]Loan{
    .{
        .at = "kernel.lex.lexicon.Lexicon",
        .why = "a destructured return, not an owner: thaw's caller lifts both fields out",
    },
};

/// One type against the rule. Returns 1 if it was judged, 0 if it frees nothing
/// or is on the ledger.
fn frees(comptime T: type) usize {
    if (@typeInfo(T) != .@"struct" and @typeInfo(T) != .@"union") return 0;
    if (!@hasDecl(T, "deinit")) return 0;
    const info = @typeInfo(@TypeOf(@field(T, "deinit")));
    if (info != .@"fn") return 0;
    const takes = info.@"fn".params.len;
    const want: usize = if (holds(T)) 1 else 2;
    // The ledger fails closed both ways. An entry excuses a shape the rule would
    // refuse, so an entry naming a type that has since taken the right shape is a
    // description of an older tree and says nothing - the same reason
    // `carry_test.zig` reddens on a loss it declared that started crossing.
    inline for (loaned) |l| if (comptime std.mem.eql(u8, l.at, @typeName(T))) {
        if (takes == want) @compileError(@typeName(T) ++ " is on the `loaned` ledger as \"" ++
            l.why ++ "\", and it now takes the shape the rule asks for on its own. " ++
            "Delete the entry.");
        return 0;
    };
    if (takes != want) @compileError(std.fmt.comptimePrint(
        "{s}: a type that {s}, and this one takes {d}. Either give it the other " ++
            "shape, or put it on `loaned` in src/idiom.zig with why it is not an owner.",
        .{
            @typeName(T),
            if (holds(T)) "holds its allocator frees with `deinit(self)`" else "holds no allocator frees with `deinit(self, gpa)`",
            takes,
        },
    ));
    return 1;
}

/// Every type an area publishes, and every type those publish in turn. Two
/// levels reaches all of them today — `Scanner.Run` and `Bough.Run` are the
/// nested ones — and a third would need a cycle guard for nothing.
fn area(comptime M: type) usize {
    comptime var judged: usize = 0;
    inline for (shelf(M)) |d| {
        const outer = @field(M, d.name);
        if (@TypeOf(outer) != type) continue;
        judged += frees(outer);
        inline for (shelf(outer)) |e| {
            const inner = @field(outer, e.name);
            if (@TypeOf(inner) != type or inner == outer) continue;
            judged += frees(inner);
        }
    }
    return judged;
}

// A `test` and not a bare `comptime` block only so that `zig build idiom` has
// something to report having run. The work is all comptime either way.
test "idiom: every type that frees itself takes the shape its ownership calls for" {
    comptime {
        // Sized generously rather than tightly: a quota this file has to re-tune
        // every time an area grows a type is a quota that gets raised without
        // being read.
        @setEvalBranchQuota(200_000);
        var judged: usize = 0;
        // File by file, not facade by facade. A facade publishes the names that
        // cross its boundary and `press.zig` publishes twenty-five of a hundred
        // and seventy-five, so a walk over the doors would have judged the public
        // surface and called it the package - `sets.Matrix`, `cast.First` and
        // `lr0.Closure` are exactly the small unmanaged types the rule is most
        // load-bearing for, and all three are private. This list is the same
        // roster the two blocks above keep, for the same reason.
        //
        // Hand-kept, and it can no longer be silently short. Five waves running
        // ended with a line added here after the fact, and each of those lanes had
        // run this gate and been told 0 - a pass that was silence, because nothing
        // had read the new area. Zig cannot walk a directory at comptime, so the
        // completeness of this list is asked from outside it: `tool/roll.py` fails
        // when a file declaring a `deinit` is one this roster cannot reach, whether
        // named here or re-exported by something that is. Which leaves the count
        // below the job it is actually good at - noticing a departure.
        for (.{
            @import("kernel/lex/scanner.zig"),      @import("kernel/lex/lexicon.zig"),
            @import("kernel/lex/admit.zig"),        @import("kernel/joint/joint.zig"),
            @import("kernel/walk/drive.zig"),       @import("kernel/spine/spine.zig"),
            @import("kernel/spine/tree.zig"),       @import("kernel/spine/arbor.zig"),
            @import("kernel/quire/quire.zig"),      @import("kernel/quire/gather.zig"),
            @import("kernel/quire/bough.zig"),      @import("kernel/quire/graft.zig"),
            @import("kernel/weave/weave.zig"),      @import("folio/folio.zig"),
            @import("folio/binding.zig"),           @import("folio/forme.zig"),
            @import("press/press.zig"),             @import("press/lalr.zig"),
            @import("press/copy/grammar.zig"),      @import("press/copy/galley.zig"),
            @import("press/cast/lr0.zig"),          @import("press/cast/first.zig"),
            @import("press/cast/sets.zig"),         @import("press/cast/retrace.zig"),
            @import("press/quarrel/settle.zig"),    @import("press/quarrel/forks.zig"),
            @import("press/quarrel/workbench.zig"), @import("press/quarrel/attribution.zig"),
            // `press/quotient.zig` publishes nothing self-freeing - `Quotient`
            // lives in the table's arena on purpose - but `minterm.Alphabet` and
            // `dafsa.Set` own memory, so their files are here rather than the door.
            @import("press/quotient.zig"),          @import("press/minterm.zig"),
            @import("press/dafsa.zig"),
            // `vellum`'s two declaring files and not its `vellum.zig`: a facade
            // re-exporting `Sheet` would have it judged twice, and the count below
            // would then be describing a package with two of them in it.
                        @import("kernel/vellum/sheet.zig"),
            @import("kernel/vellum/word.zig"),      @import("kernel/grain/ruling.zig"),
            @import("kernel/gloss/rubric.zig"),     @import("kernel/gloss/lemma.zig"),
            @import("kernel/gloss/stencil.zig"),    @import("kernel/gloss/gloss.zig"),
            // The customary's facade and not `engine.zig`: its one owner is the
            // bound engine, and the book, the organs and the guard are plain
            // values over borrowed bytes - which is the property that lets a
            // save be a copy.
            @import("kernel/lex/customary/customary.zig"),
        }) |m| judged += area(m);
        // The count is the second half of the gate. Every violation is a compile
        // error on its own, but a type the walk never *reached* is silent, and an
        // area added to the facade and forgotten here would read as a clean run
        // over a smaller package.
        if (judged != lifecycles) @compileError(std.fmt.comptimePrint(
            "the lifecycle proof judged {d} types against a pinned {d}. A type " ++
                "you added or moved is welcome; one that went missing is the case " ++
                "this count exists for. Then update `lifecycles`.",
            .{ judged, lifecycles },
        ));
    }
}

/// How many types the walk above judged, last time anyone looked. Every type in
/// the library that frees itself, less the one on the `loaned` ledger.
///
/// `surface/` is not in the walk and cannot be: the CLI and the ABI are separate
/// compilations that reach this package through the module name `joints`, so this
/// file has no import path to them. Their one `deinit` is `parse.zig`'s, which
/// takes the shape the rule asks for.
///
/// 63 to 73 is one wave (`grain`, `vellum`, a quotient), 73 to 79 is `gloss`, and
/// 80 is the customary engine.
/// Thirteen of those sixteen arrived in files this roster had no line for, so they
/// were not judged against a stale pin - they were not judged at all. That is the
/// reading a count cannot give you, and it is `tool/roll.py`'s question now.
///
/// What this number is for is the other direction. A type that went missing leaves
/// no file behind to notice, so nothing walks up to it; the roster still names
/// every file it should and the answer is quietly smaller. That is the case worth
/// a pin, and the case a directory walk cannot see.
const lifecycles = 80;
