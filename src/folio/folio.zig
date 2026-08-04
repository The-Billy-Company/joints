//! The folio: the artifact. N languages, one mmap-able file.
//!
//! This is the claim the whole package is named for. In tree-sitter a grammar
//! becomes a C program, and every painful thing downstream - a 30 MB
//! `parser.c`, a shared library per language, an ABI window, 25 MB of WASM
//! before a browser can highlight ten languages - follows from that one choice.
//! Here a grammar becomes data, so a grammar is a file, and one binary plus one
//! folio is every language.
//!
//! An artifact format is a promise about bytes, so the rule is fail-closed: a
//! folio a future version could silently misread is worse than one it refuses
//! to load. Version, seal, and a named refusal per malformed field.
//!
//! Six moving parts. `leaf` is the on-disk vocabulary both sides speak, `forme`
//! locks the parse table into the interned shape that makes a folio small,
//! `impose` writes, `collate` reads and validates the layout, `audit` validates
//! what is inside it, and `bind` hands the result back as the three types a
//! parse takes. The seam is here so the lane building it never has to touch
//! `src/root.zig`.
//!
//! ```
//! var pressed = try press.tables(gpa, &grammar);
//! defer pressed.deinit();
//! const bytes = try folio.pack(gpa, &grammar, &pressed);   // or writeTo(dir, …)
//! defer gpa.free(bytes);
//! var m = try folio.map(io, dir, "x.folio");               // or open(bytes)
//! defer m.close();
//! var parser = try folio.bind(gpa, &m.folio);              // and parse from it
//! defer parser.deinit();
//! ```

const std = @import("std");
const irregex = @import("irregex");

pub const leaf = @import("leaf.zig");
pub const forme = @import("forme.zig");
pub const impose = @import("impose.zig");
pub const collate = @import("collate.zig");
pub const audit = @import("audit.zig");
pub const rebind = @import("bind.zig");

pub const Folio = collate.Folio;
pub const Error = leaf.Error;
pub const WriteError = impose.Error;
pub const Action = leaf.Action;
pub const Pattern = collate.Pattern;
pub const Alias = collate.Alias;
pub const Bound = rebind.Bound;
pub const version = leaf.version;
pub const magic = leaf.magic;
pub const align_bytes = leaf.section_align;

pub const pack = impose.pack;
pub const open = collate.open;
pub const bind = rebind.bind;

/// Publish a folio at `path`, atomically: written whole to a neighbouring
/// temporary and renamed over the target, so a reader sees the old file or the
/// new one and never half of either. Borrowed from the way irregex publishes an
/// index, for the same reason - the readers are other processes and they do not
/// stop while you write.
pub fn writeTo(io: std.Io, dir: std.Io.Dir, path: []const u8, bytes: []const u8) !void {
    var out = try dir.createFileAtomic(io, path, .{ .make_path = true, .replace = true });
    defer out.deinit(io);
    try out.file.writeStreamingAll(io, bytes);
    try out.replace(io);
}

/// A mapped folio. Nothing in it is copied - that is the entire point of the
/// format, and it is why this is a handle you close rather than a value you own.
pub const Mapped = struct {
    folio: Folio,
    bytes: []align(std.heap.page_size_min) const u8,

    pub fn close(m: *Mapped) void {
        irregex.portal.unmap(m.bytes);
        m.* = undefined;
    }
};

/// Map a folio and prove it. A page is a multiple of eight, so the mapping is
/// always aligned enough for the section offsets the reader is about to trust.
pub fn map(io: std.Io, dir: std.Io.Dir, path: []const u8) !Mapped {
    const file = try dir.openFile(io, path, .{});
    defer file.close(io);
    const size: usize = @intCast((try file.stat(io)).size);
    // Only what `mmap` itself refuses. Everything else is `open`'s judgement,
    // which distinguishes "too short" from "not a folio" and should be the one
    // making it.
    if (size == 0) return Error.FolioTooSmall;
    const bytes = try irregex.portal.map(file.handle, size);
    errdefer irregex.portal.unmap(bytes);
    return .{ .folio = try open(bytes), .bytes = bytes };
}

test {
    std.testing.refAllDecls(@This());
    _ = leaf;
    _ = forme;
    _ = impose;
    _ = collate;
    _ = audit;
    _ = rebind;
    _ = @import("folio_test.zig");
}
