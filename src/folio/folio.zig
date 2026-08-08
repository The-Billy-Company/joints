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
//! Seven moving parts. `leaf` is the on-disk vocabulary both sides speak,
//! `forme` locks the parse table into the interned shape that makes a folio
//! small, `impose` writes, `collate` reads and validates the layout, `audit`
//! validates what is inside it, `binding` hands the result back as the three
//! types a parse takes, and `codex` binds several folios into the one file the
//! "N languages" claim is about. The seam is here so the lane building it
//! never has to touch `src/root.zig`.
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
// The file is `binding.zig` and not `bind.zig` because `bind` is the operation
// this facade exports, and a module of that name would have taken it - which is
// how it came to be imported here under `rebind`, a second name for it that
// nothing else in the tree ever used. A binding is also the right noun: it is
// the thing that makes loose sheets a book you can read.
pub const binding = @import("binding.zig");
pub const codex = @import("codex.zig");

pub const Folio = collate.Folio;
pub const Codex = codex.Codex;
pub const Error = leaf.Error;
pub const WriteError = impose.Error;
pub const Action = leaf.Action;
pub const Pattern = collate.Pattern;
pub const Alias = collate.Alias;
pub const Bound = binding.Bound;
pub const version = leaf.version;
pub const magic = leaf.magic;
pub const align_bytes = leaf.section_align;

pub const pack = impose.pack;
pub const open = collate.open;
pub const bind = binding.bind;

// Loading is one operation over two axes, and the four names below are that 2×2
// rather than four spellings of the same thing. The axes: what the file is
// allowed to hold - one grammar (`open`, `map`) or either artifact (`openVolume`,
// `mapVolume`) - and where its bytes come from - already in hand (`open*`) or
// still on disk (`map*`).
//
// `map` is not a politer `open`. `open` proves bytes the caller owns and hands
// back a value that borrows them; `map` acquires pages and hands back a handle
// you must `close`. A shared verb would have hidden exactly the difference that
// decides whether you leak. Which is also why the narrow name is the unmarked
// one even though most callers with a path want `mapVolume`: a caller that knows
// it wrote a lone folio should be refused by a codex, and `open`/`map` are how
// it says so.
//
// Three of the four are below, each beside the type it returns.

/// What picking a language out of a volume can refuse on, beyond the member
/// folio's own failures. Two names because they demand different sentences: an
/// unknown title wants the roster printed, an ambiguous one wants the flag.
pub const PickError = error{
    /// The named language is not in this file.
    TitleUnknown,
    /// Several languages, and nothing said which. Never raised by a volume of
    /// one, which is its own default.
    TitleAmbiguous,
};

/// Whichever of the two artifacts a `.folio` path holds: one grammar, or a
/// codex binding several. Every consumer opens through this rather than
/// sniffing magics itself, so the two spellings cannot drift apart.
pub const Volume = union(enum) {
    one: Folio,
    many: codex.Codex,

    pub fn count(v: *const Volume) u32 {
        return switch (v.*) {
            .one => 1,
            .many => |*c| c.count,
        };
    }

    pub fn titleAt(v: *const Volume, i: u32) []const u8 {
        return switch (v.*) {
            .one => |*f| f.title(),
            .many => |*c| c.titleAt(i),
        };
    }

    /// The one folio a parse should use. `language` null means "the obvious
    /// one", which exists only when the volume holds exactly one; a codex of
    /// several refuses rather than guessing, because a guess that parses
    /// python with the rust tables produces a tree that looks fine and is
    /// wrong - which is the failure this whole format refuses everywhere else.
    pub fn pick(v: *const Volume, language: ?[]const u8) (Error || PickError)!Folio {
        switch (v.*) {
            .one => |f| {
                if (language) |want| {
                    if (!std.mem.eql(u8, f.title(), want)) return PickError.TitleUnknown;
                }
                return f;
            },
            .many => |*c| {
                if (language) |want| {
                    return c.openAt(c.find(want) orelse return PickError.TitleUnknown);
                }
                if (c.count == 1) return c.openAt(0);
                return PickError.TitleAmbiguous;
            },
        }
    }
};

/// Prove whichever artifact these bytes are. The first eight bytes decide
/// which reader judges the rest; anything wearing neither magic is refused in
/// the folio's own vocabulary.
pub fn openVolume(bytes: []align(leaf.section_align) const u8) Error!Volume {
    if (bytes.len >= codex.magic.len and std.mem.eql(u8, bytes[0..codex.magic.len], codex.magic)) {
        return .{ .many = try codex.open(bytes) };
    }
    return .{ .one = try open(bytes) };
}

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

/// A mapped volume - `Mapped`'s twin for the path that does not yet know
/// whether the file holds one language or several.
pub const MappedVolume = struct {
    volume: Volume,
    bytes: []align(std.heap.page_size_min) const u8,

    pub fn close(m: *MappedVolume) void {
        irregex.portal.unmap(m.bytes);
        m.* = undefined;
    }
};

/// Map whichever artifact `path` holds and prove it - the directory of a
/// codex, the whole of a lone folio. Members of a codex are proven as they
/// are picked, so the cost of this stays proportional to what gets used.
pub fn mapVolume(io: std.Io, dir: std.Io.Dir, path: []const u8) !MappedVolume {
    const file = try dir.openFile(io, path, .{});
    defer file.close(io);
    const size: usize = @intCast((try file.stat(io)).size);
    if (size == 0) return Error.FolioTooSmall;
    const bytes = try irregex.portal.map(file.handle, size);
    errdefer irregex.portal.unmap(bytes);
    return .{ .volume = try openVolume(bytes), .bytes = bytes };
}

test {
    std.testing.refAllDecls(@This());
    _ = leaf;
    _ = forme;
    _ = impose;
    _ = collate;
    _ = audit;
    _ = binding;
    _ = codex;
}
