//! outliner build graph — parsing as algebra.
//!
//! One binary, `outliner`. Today it carries the rung-1 instrument: import a
//! tree-sitter `grammar.json`, build the LR automaton, and measure whether the
//! stack effects real files induce actually collapse toward rank one. That
//! measurement is the falsifier for the whole design
//! (`research/joinery/TESTING.md`), so it is the first thing the graph builds
//! and the only thing it builds until the answer is in.

const std = @import("std");
const builtin = @import("builtin");
const brigade = @import("brigade");

pub fn build(b: *std.Build) void {
    // macOS deployment floor: below any plausible consumer link target,
    // matching the sibling packages.
    const default_target: std.Target.Query = if (builtin.target.os.tag == .macos)
        .{ .os_version_min = .{ .semver = .{ .major = 13, .minor = 0, .patch = 0 } } }
    else
        .{};
    const target = b.standardTargetOptions(.{ .default_target = default_target });

    // ReleaseFast regardless of the build-wide `-Doptimize`, the same product
    // posture the siblings keep: a bare `zig build` must never install a slow
    // debug binary. `-Dcli-optimize=Debug` still yields one.
    const optimize = b.option(
        std.builtin.OptimizeMode,
        "cli-optimize",
        "optimize mode for the installed outliner CLI (default ReleaseFast)",
    ) orelse .ReleaseFast;

    // `build.zig.zon`'s `.version` is the single authority; the face reads it
    // through this option rather than restating it. The package name rides
    // along so this generated file differs from the ones the siblings generate
    // — Zig content-addresses it, and two packages whose only option was an
    // identical version string produce the same file, which it then refuses as
    // the root of two modules.
    const zon = @import("build.zig.zon");
    const version = b.addOptions();
    version.addOption([:0]const u8, "version", zon.version);
    version.addOption([:0]const u8, "package", @tagName(zon.name));

    // The engine outliner's lexer stands on. Named here rather than inside the
    // module list twice, because the test build needs the identical dependency
    // and a second `b.dependency` call for a different optimize mode would
    // build irregex twice.
    const irregex = b.dependency("irregex", .{ .target = target, .optimize = optimize });
    const irregex_mod = irregex.module("irregex");

    // The library module and the face are separate modules on purpose: the face
    // is one consumer of the package, not its root, so nothing a CLI needs can
    // quietly become something an embedder must link. PIC for the same reason
    // irregex's public module is: the module underneath a shared C-ABI object
    // has to be relocatable, and macOS was building it that way regardless.
    const lib = b.addModule("outliner", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .pic = true,
        .imports = &.{.{ .name = "irregex", .module = irregex_mod }},
    });

    const root = b.path("src/surface/face/outliner/main.zig");
    const face = b.createModule(.{
        .root_source_file = root,
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "outliner", .module = lib }},
    });
    face.addOptions("build_options", version);
    const exe = b.addExecutable(.{ .name = "outliner", .root_module = face });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| run.addArgs(args);
    b.step("run", "Run the outliner CLI").dependOn(&run.step);

    // ── libotl: the C ABI (`otl_*` + include/otl.h) ──
    // Rooted at the export shims, NOT at `src/root.zig` — a Zig `export fn` is
    // emitted by every compilation that reaches it, so shims living in the
    // library module would be duplicated into every downstream artifact that
    // imports the package. Same split every sibling package keeps.
    const abi = b.createModule(.{
        .root_source_file = b.path("src/surface/abi/exports.zig"),
        .target = target,
        .optimize = optimize,
        .pic = true,
        .link_libc = true,
        .imports = &.{.{ .name = "outliner", .module = lib }},
    });
    abi.addOptions("build_options", version);

    // Dynamic (a Python cffi / dlopen consumer) owns the header install;
    // static is what Go cgo and a Rust build.rs link.
    const dynamic_lib = b.addLibrary(.{ .name = "otl", .linkage = .dynamic, .root_module = abi });
    dynamic_lib.installHeader(b.path("include/otl.h"), "otl.h");
    b.installArtifact(dynamic_lib);

    // The archive must stand alone. `addLibrary(.static)` would archive only
    // this compilation's own objects and leave irregex's C floor (PCRE2 +
    // libsais, `linkLibrary` on the engine module) as an instruction for
    // whoever links next — undefined symbols in a consumer that was never
    // told. Routing through a partial-linked OBJECT pulls the floor in, and
    // the repack is `libtool -static` on Mach-O (Zig's archiver leaves
    // members non-8-byte-aligned, which ld64 rejects) and `zig ar` elsewhere
    // — the exact lesson irregex's build carries, inherited rather than
    // relearned. Installed as a plain file because the shared library above
    // already owns the artifact name `otl`, and a second registration
    // panicked dependents' `dep.artifact()` lookups over there.
    const repack = switch (target.result.ofmt) {
        .macho => b.addSystemCommand(&.{ "libtool", "-static", "-o" }),
        else => b.addSystemCommand(&.{ b.graph.zig_exe, "ar", "rcs" }),
    };
    const merged = repack.addOutputFileArg("libotl.a");
    repack.addArtifactArg(b.addObject(.{ .name = "otl", .root_module = abi }));
    b.getInstallStep().dependOn(&b.addInstallLibFile(merged, "libotl.a").step);
    b.addNamedLazyPath("libotl.a", merged);

    // Debug regardless of the CLI's ReleaseFast posture, since a release build
    // elides the safety checks a test is partly there to trip.
    const test_lib = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = .Debug,
        .imports = &.{.{ .name = "irregex", .module = irregex_mod }},
    });
    // A real grammar, for the tests that would otherwise be checking a fiction:
    // a hand-built symbol table cannot tell you whether the importer and the
    // scanner agree about what tree-sitter actually writes. On the test module
    // only, and read from the committed fixture rather than the gitignored
    // `upstream/` corpus: Zig resolves this path while it builds the graph, so
    // naming a fetched file fails a fresh clone with `failed to check cache:
    // … file_hash FileNotFound` before it compiles a line. `test/grammar/`
    // says where the 13 KB came from; `tool/grammars.py verify` proves it still
    // hashes to the `json` pin.
    test_lib.addAnonymousImport("json_grammar", .{
        .root_source_file = b.path("test/grammar/json.json"),
    });
    const test_face = b.createModule(.{
        .root_source_file = root,
        .target = target,
        .optimize = .Debug,
        .imports = &.{.{ .name = "outliner", .module = test_lib }},
    });
    test_face.addOptions("build_options", version);
    // The ABI's bodies (`bank.zig`) are plain Zig and tested as plain Zig —
    // the C boundary is one-line shims over them, so what this compilation
    // adds is the proof the shims still compile as C-callable signatures.
    const test_abi = b.createModule(.{
        .root_source_file = b.path("src/surface/abi/exports.zig"),
        .target = target,
        .optimize = .Debug,
        .link_libc = true,
        .imports = &.{.{ .name = "outliner", .module = test_lib }},
    });
    test_abi.addOptions("build_options", version);
    // The same committed fixture the library tests press, for the same
    // reason: an ABI test against a hand-built grammar checks a fiction.
    test_abi.addAnonymousImport("json_grammar", .{
        .root_source_file = b.path("test/grammar/json.json"),
    });
    const bg = brigade.init(b, .{});
    const test_step = b.step("test", "Run unit tests");
    // A test build only collects the tests in its own root module's files, so
    // the library needs its own compilation. Naming it from the face's test
    // block silently collects nothing, which reads exactly like a green run.
    for ([_]*std.Build.Module{ test_lib, test_face, test_abi }) |m| {
        bg.shard(test_step, b.addTest(.{ .root_module = m, .test_runner = bg.runner() }), .{});
    }

    const check = b.step("check", "Compile the outliner binary + libotl without installing");
    check.dependOn(&exe.step);
    check.dependOn(&dynamic_lib.step);

    // The wall census. Not part of `test`: it answers "who owns each stop" over
    // whatever verdict list `.local/orchestrate/census.txt` holds, which is a
    // question about a corpus rather than an invariant of the code - and with no
    // request file it returns immediately, so wiring it into the suite would only
    // buy a no-op. ReleaseFast because the work is thirty presses and scala's is
    // eleven thousand states; the answer is identical either way.
    const survey = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .imports = &.{.{ .name = "irregex", .module = irregex_mod }},
    });
    survey.addAnonymousImport("json_grammar", .{
        .root_source_file = b.path("test/grammar/json.json"),
    });
    const census = b.addRunArtifact(b.addTest(.{
        .root_module = survey,
        .filters = &.{"census:"},
        .test_runner = bg.runner(),
    }));
    census.setCwd(b.path("."));
    b.step(
        "census",
        "Who owns each wall: classify a verdict list through press/inquest",
    ).dependOn(&census.step);
}
