//! joints build graph — parsing as algebra.
//!
//! One binary, `joints`. Today it carries the rung-1 instrument: import a
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
        "optimize mode for the installed joints CLI (default ReleaseFast)",
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

    // The engine joints's lexer stands on. Named here rather than inside the
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
    const lib = b.addModule("joints", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .pic = true,
        .imports = &.{.{ .name = "irregex", .module = irregex_mod }},
    });

    const root = b.path("src/surface/face/joints/main.zig");
    const face = b.createModule(.{
        .root_source_file = root,
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "joints", .module = lib }},
    });
    face.addOptions("build_options", version);
    const exe = b.addExecutable(.{ .name = "joints", .root_module = face });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| run.addArgs(args);
    b.step("run", "Run the joints CLI").dependOn(&run.step);

    // ── libjnt: the C ABI (`jnt_*` + include/jnt.h) ──
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
        .imports = &.{.{ .name = "joints", .module = lib }},
    });
    abi.addOptions("build_options", version);

    // Dynamic (a Python cffi / dlopen consumer) owns the header install;
    // static is what Go cgo and a Rust build.rs link.
    const dynamic_lib = b.addLibrary(.{ .name = "jnt", .linkage = .dynamic, .root_module = abi });
    dynamic_lib.installHeader(b.path("include/jnt.h"), "jnt.h");
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
    // already owns the artifact name `jnt`, and a second registration
    // panicked dependents' `dep.artifact()` lookups over there.
    const repack = switch (target.result.ofmt) {
        .macho => b.addSystemCommand(&.{ "libtool", "-static", "-o" }),
        else => b.addSystemCommand(&.{ b.graph.zig_exe, "ar", "rcs" }),
    };
    const merged = repack.addOutputFileArg("libjnt.a");
    repack.addArtifactArg(b.addObject(.{ .name = "jnt", .root_module = abi }));
    b.getInstallStep().dependOn(&b.addInstallLibFile(merged, "libjnt.a").step);
    b.addNamedLazyPath("libjnt.a", merged);

    // Debug regardless of the CLI's ReleaseFast posture, since a release build
    // elides the safety checks a test is partly there to trip. Rooted at the
    // real facade because this is the library as the face and the ABI import
    // it: the library's own tests come from `proof` below, which is a second
    // module rather than a re-rooting of this one, since pointing this at
    // `src/proof.zig` would resolve every `@import("joints")` in the face to a
    // file that has no API — only a test block.
    const test_lib = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = .Debug,
        .imports = &.{.{ .name = "irregex", .module = irregex_mod }},
    });

    // The library's tests, rooted at the test-only root that names every module
    // and every `*_test.zig` by hand. `src/proof.zig` carries the reason
    // production files may not name a test, and `tool/roll.py` is the gate that
    // nothing went unnamed.
    const proof = b.createModule(.{
        .root_source_file = b.path("src/proof.zig"),
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
    proof.addAnonymousImport("json_grammar", .{
        .root_source_file = b.path("test/grammar/json.json"),
    });
    const test_face = b.createModule(.{
        .root_source_file = root,
        .target = target,
        .optimize = .Debug,
        .imports = &.{.{ .name = "joints", .module = test_lib }},
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
        .imports = &.{.{ .name = "joints", .module = test_lib }},
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
    bg.shard(test_step, b.addTest(.{ .root_module = proof, .test_runner = bg.runner() }), .{});

    // One step per root, and `test` folds the other two only when nothing
    // narrowed the run. Several roots under one step break `-Dtest-filter`:
    // brigade fails a shard whose filter matched none of *its* tests, which is
    // right for one binary (you typo'd it) and wrong across three, where a
    // library test's name simply does not live in the face's 8 or the ABI's 5.
    // So every filtered run exited 1 while passing - `zig build test
    // -Dtest-filter=folio` printed two fatals and a red summary over a green
    // suite - and a gate that cries wolf on the documented inner loop teaches
    // you to stop reading it, which is worse than not having it. The guard still
    // bites where it should: a real typo misses all 404 and fails.
    //
    // `Brigade.narrowed` exists for exactly this fold. Unfiltered `zig build
    // test` still runs all three; a filtered hunt names the binary it is hunting
    // in - `zig build face -Dtest-filter=…`, `zig build abi -Dtest-filter=…`.
    const face_step = b.step("face", "Run the CLI's tests (folded into `test` unfiltered)");
    bg.shard(face_step, b.addTest(.{ .root_module = test_face, .test_runner = bg.runner() }), .{});
    const abi_step = b.step("abi", "Run the C ABI's tests (folded into `test` unfiltered)");
    bg.shard(abi_step, b.addTest(.{ .root_module = test_abi, .test_runner = bg.runner() }), .{});
    if (!bg.narrowed()) {
        test_step.dependOn(face_step);
        test_step.dependOn(abi_step);
    }

    const check = b.step("check", "Compile the joints binary + libjnt without installing");
    check.dependOn(&exe.step);
    check.dependOn(&dynamic_lib.step);

    // The wall census. Not part of `test`: it answers "who owns each stop" over
    // whatever verdict list `.local/orchestrate/census.txt` holds, which is a
    // question about a corpus rather than an invariant of the code - and with no
    // request file it returns immediately, so wiring it into the suite would only
    // buy a no-op. ReleaseFast because the work is thirty presses and scala's is
    // eleven thousand states; the answer is identical either way.
    const census_lib = b.createModule(.{
        .root_source_file = b.path("src/proof.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .imports = &.{.{ .name = "irregex", .module = irregex_mod }},
    });
    census_lib.addAnonymousImport("json_grammar", .{
        .root_source_file = b.path("test/grammar/json.json"),
    });
    const census = b.addRunArtifact(b.addTest(.{
        .root_module = census_lib,
        .filters = &.{"census:"},
        .test_runner = bg.runner(),
    }));
    census.setCwd(b.path("."));
    b.step(
        "census",
        "Who owns each wall: classify a verdict list through press/inquest",
    ).dependOn(&census.step);

    // The idiom proof, and its own root for one measured reason: it reaches every
    // module's decls by name, and reaching a decl is what makes Zig analyse it.
    // That is 3.4 s of analysis `-Dtest-filter` cannot defer, so sharing
    // `proof.zig` would have charged it to `zig build test -Dtest-filter=<what you
    // touched>`. Debug, not ReleaseFast: every claim in it is settled at comptime
    // and there is nothing for the optimizer to do.
    const idiom = b.addRunArtifact(b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/idiom.zig"),
            .target = target,
            .optimize = .Debug,
            .imports = &.{.{ .name = "irregex", .module = irregex_mod }},
        }),
        // Reaching twenty-eight modules also collects their inline tests, and the
        // suite already runs those. `idiom:` narrows the run to the one test this
        // step exists for, exactly as `census:` does above - and the run still
        // reports 8, because a filter matches on a name and seven of the modules it
        // reaches are facades whose `test { _ = @import(…); }` block has none. They
        // reference decls and return, at 0 ms apiece, so the arithmetic is the only
        // thing about them worth knowing.
        .filters = &.{"idiom:"},
        .test_runner = bg.runner(),
    }));
    b.step(
        "idiom",
        "Does the package speak its own idiom: one lifecycle shape per kind of owner",
    ).dependOn(&idiom.step);

    // The bench rungs. Not part of `test` and not part of `check`: a rung
    // measures a trade rather than asserting an invariant, and the ones with a
    // floor in them say so by exiting nonzero. ReleaseFast unconditionally,
    // because a Debug timing table is a table of Zig's safety checks. Cwd at
    // the root so a rung can read the corpus by its committed path; a rung
    // whose fixtures are not underfoot skips the row rather than failing.
    const bench_vellum = b.addRunArtifact(b.addExecutable(.{
        .name = "bench-vellum",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/rungs/vellum/bench.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .imports = &.{
                .{ .name = "joints", .module = lib },
                .{ .name = "irregex", .module = irregex_mod },
            },
        }),
    }));
    bench_vellum.setCwd(b.path("."));
    b.step(
        "bench-vellum",
        "What a settled tree costs and buys: size a node and nanoseconds an op, both ways",
    ).dependOn(&bench_vellum.step);

    const bench_grain = b.addRunArtifact(b.addExecutable(.{
        .name = "bench-grain",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/rungs/grain/bench.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .imports = &.{
                .{ .name = "joints", .module = lib },
                .{ .name = "irregex", .module = irregex_mod },
            },
        }),
    }));
    bench_grain.setCwd(b.path("."));
    b.step(
        "bench-grain",
        "Is one pass over the material cheaper than the walk it replaces: three arms, four sections",
    ).dependOn(&bench_grain.step);

    const bench_quotient = b.addRunArtifact(b.addExecutable(.{
        .name = "bench-quotient",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/rungs/quotient/bench.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .imports = &.{
                .{ .name = "joints", .module = lib },
                .{ .name = "irregex", .module = irregex_mod },
            },
        }),
    }));
    bench_quotient.setCwd(b.path("."));
    b.step(
        "bench-quotient",
        "What the three quotients find: states merged, columns collapsed, payload as one automaton",
    ).dependOn(&bench_quotient.step);

    const bench_cursor = b.addRunArtifact(b.addExecutable(.{
        .name = "bench-cursor",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/rungs/cursor/bench.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .imports = &.{
                .{ .name = "joints", .module = lib },
                .{ .name = "irregex", .module = irregex_mod },
            },
        }),
    }));
    bench_cursor.setCwd(b.path("."));
    b.step(
        "bench-cursor",
        "What the neighbourhood accessors cost against the walks they were, and against the settled tree",
    ).dependOn(&bench_cursor.step);

    const bench_gloss = b.addRunArtifact(b.addExecutable(.{
        .name = "bench-gloss",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/rungs/gloss/bench.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .imports = &.{
                .{ .name = "joints", .module = lib },
                .{ .name = "irregex", .module = irregex_mod },
            },
        }),
    }));
    bench_gloss.setCwd(b.path("."));
    b.step(
        "bench-gloss",
        "Every query the pinned grammars ship, compiled: acceptance, dead patterns, lookup, #match?",
    ).dependOn(&bench_gloss.step);
}
