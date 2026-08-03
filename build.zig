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

    // The library module and the face are separate modules on purpose: the face
    // is one consumer of the package, not its root, so nothing a CLI needs can
    // quietly become something an embedder must link.
    const lib = b.addModule("outliner", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
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

    // Debug regardless of the CLI's ReleaseFast posture, since a release build
    // elides the safety checks a test is partly there to trip.
    const test_lib = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = .Debug,
    });
    const test_face = b.createModule(.{
        .root_source_file = root,
        .target = target,
        .optimize = .Debug,
        .imports = &.{.{ .name = "outliner", .module = test_lib }},
    });
    test_face.addOptions("build_options", version);
    const bg = brigade.init(b, .{});
    const test_step = b.step("test", "Run unit tests");
    // A test build only collects the tests in its own root module's files, so
    // the library needs its own compilation. Naming it from the face's test
    // block silently collects nothing, which reads exactly like a green run.
    for ([_]*std.Build.Module{ test_lib, test_face }) |m| {
        bg.shard(test_step, b.addTest(.{ .root_module = m, .test_runner = bg.runner() }), .{});
    }

    b.step("check", "Compile the outliner binary without installing").dependOn(&exe.step);
}
