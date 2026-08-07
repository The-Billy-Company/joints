//! The codex: several folios bound as one file. This is where "N languages,
//! one mmap-able file" stops being a claim and becomes a layout.
//!
//! A folio carries one grammar, and that is the right shape for the thing an
//! editor opens - but the thing an editor *ships* is every language at once,
//! and shipping thirty files where one would do reinvents the shared-library-
//! per-language problem this package exists to end. So a codex is the binding:
//! a title directory, then each member folio laid in whole, byte-identical to
//! the file `mint` would have written alone. Nothing inside a member is
//! reinterpreted here; the codex knows titles and offsets and nothing else.
//!
//! Proportional cost is the design rule. The codex seals its OWN bytes - the
//! header, the directory, the titles - and each member keeps the seal it
//! already had, so opening one language out of thirty verifies the directory
//! plus that one member and never pages the other twenty-nine in. A rollup
//! seal over the whole file would spend the entire point of mmap re-proving
//! folios nobody asked for.
//!
//! Fail-closed, same as the member format: magic, version, length, seal, then
//! every directory row proven before a byte of it is trusted. A member is
//! proven by `collate.open` at the moment it is picked, which is the same
//! judgement a lone folio gets - a codex adds no second, weaker way in.
//!
//! ```
//! const bytes = try codex.pack(gpa, &.{ python_folio, rust_folio });
//! const c = try codex.open(bytes);
//! const f = try c.openAt(c.find("rust").?);   // a proven collate.Folio
//! ```

const std = @import("std");
const leaf = @import("leaf.zig");
const collate = @import("collate.zig");

const signet = leaf.signet;

pub const magic = "OTLCODEX";

/// Bumped whenever the layout below changes meaning. Independent of
/// `leaf.version`: a member carries its own version and refuses on its own
/// terms, so binding does not couple the two formats' histories.
pub const version: u16 = 1;

pub const header_len = 32;
pub const entry_len = 24;

/// The reader's refusals are the folio's own vocabulary - a codex that is
/// wrong is wrong in the same handful of ways a folio is, and inventing a
/// parallel error set would make every caller switch twice.
pub const Error = leaf.Error;

/// What packing can refuse on, beyond what proving each member already can.
pub const PackError = error{
    /// No members. A codex of nothing is not a file worth writing.
    CodexEmpty,
    /// Two members carry the same title, so `find` could never answer for
    /// either of them honestly.
    TitleRepeated,
    /// Some count or offset does not fit the width the format spends on it.
    CodexTooLarge,
} || Error || std.mem.Allocator.Error;

/// One member's place: where its title is in the arena, where its bytes are in
/// the file. Parsed on demand - a codex directory is a few dozen rows at most,
/// and caching them would be a second copy of the truth.
const Entry = struct {
    title_off: u32,
    title_len: u32,
    folio_off: u64,
    folio_len: u64,

    fn write(e: Entry, buf: *[entry_len]u8) void {
        std.mem.writeInt(u32, buf[0..4], e.title_off, .little);
        std.mem.writeInt(u32, buf[4..8], e.title_len, .little);
        std.mem.writeInt(u64, buf[8..16], e.folio_off, .little);
        std.mem.writeInt(u64, buf[16..24], e.folio_len, .little);
    }

    fn parse(buf: *const [entry_len]u8) Entry {
        return .{
            .title_off = std.mem.readInt(u32, buf[0..4], .little),
            .title_len = std.mem.readInt(u32, buf[4..8], .little),
            .folio_off = std.mem.readInt(u64, buf[8..16], .little),
            .folio_len = std.mem.readInt(u64, buf[16..24], .little),
        };
    }
};

/// A verified codex directory. The members are NOT verified yet - that is
/// `openAt`'s judgement, paid per member picked, which is what keeps opening
/// one language out of thirty proportional to one.
pub const Codex = struct {
    bytes: []align(leaf.section_align) const u8,
    count: u32,
    /// The title arena, already proven in bounds.
    arena: []const u8,

    pub fn titleAt(c: *const Codex, i: u32) []const u8 {
        const e = c.entry(i);
        return c.arena[e.title_off..][0..e.title_len];
    }

    /// The member's bytes, exactly as a lone `.folio` file would hold them.
    pub fn sliceAt(c: *const Codex, i: u32) []align(leaf.section_align) const u8 {
        const e = c.entry(i);
        const off: usize = @intCast(e.folio_off);
        return @alignCast(c.bytes[off..][0..@intCast(e.folio_len)]);
    }

    /// Prove one member and hand it over - the same judgement, by the same
    /// code, that a lone folio file gets.
    pub fn openAt(c: *const Codex, i: u32) Error!collate.Folio {
        return collate.open(c.sliceAt(i));
    }

    /// Byte-exact, same as every other name in the format: a `--language`
    /// that differs by case is a different language, not a near miss.
    pub fn find(c: *const Codex, title: []const u8) ?u32 {
        for (0..c.count) |i| {
            if (std.mem.eql(u8, c.titleAt(@intCast(i)), title)) return @intCast(i);
        }
        return null;
    }

    fn entry(c: *const Codex, i: u32) Entry {
        // usize math: a directory big enough to overflow a u32 here is a file
        // past 4 GB, and wrapping would read some other row as this one.
        return Entry.parse(c.bytes[header_len + @as(usize, i) * entry_len ..][0..entry_len]);
    }
};

/// How many bytes the directory occupies: header, entries, arena. The seal
/// sits immediately after and covers exactly this.
fn preamble(count: u32, arena_len: u32) u64 {
    return header_len + @as(u64, count) * entry_len + arena_len;
}

/// Prove these bytes are a codex directory, or name what stopped you. Members
/// stay unproven until picked; see `Codex`.
pub fn open(bytes: []align(leaf.section_align) const u8) Error!Codex {
    if (bytes.len < magic.len) return Error.FolioTooSmall;
    if (!std.mem.eql(u8, bytes[0..magic.len], magic)) return Error.FolioBadMagic;
    if (bytes.len < header_len + signet.len) return Error.FolioTooSmall;

    if (std.mem.readInt(u16, bytes[8..10], .little) != version) return Error.FolioBadVersion;
    const count = std.mem.readInt(u32, bytes[12..16], .little);
    const arena_len = std.mem.readInt(u32, bytes[16..20], .little);
    const file_len = std.mem.readInt(u64, bytes[24..32], .little);
    if (file_len != bytes.len) return Error.FolioBadLength;
    if (count == 0) return Error.FolioBadCount;

    const dir_len = preamble(count, arena_len);
    const sealed = dir_len + signet.len;
    if (sealed > bytes.len) return Error.FolioTooSmall;
    // The seal covers the directory only, on purpose: each member carries its
    // own, and re-hashing thirty languages to open one would spend the mmap.
    signet.verify(bytes[0..@intCast(sealed)]) catch return Error.FolioBadSeal;

    const c: Codex = .{
        .bytes = bytes,
        .count = count,
        .arena = bytes[header_len + @as(usize, count) * entry_len ..][0..arena_len],
    };
    // Every row proven before anyone slices by it: titles inside the arena,
    // members ascending, eight-aligned, past the seal and inside the file.
    var at = leaf.align8(sealed);
    for (0..count) |i| {
        const e = c.entry(@intCast(i));
        if (@as(u64, e.title_off) + e.title_len > arena_len) return Error.FolioBadText;
        if (e.folio_off % leaf.section_align != 0) return Error.FolioSectionMisaligned;
        if (e.folio_off < at) return Error.FolioSectionOutOfBounds;
        if (e.folio_len > file_len or e.folio_off > file_len - e.folio_len) {
            return Error.FolioSectionOutOfBounds;
        }
        at = leaf.align8(e.folio_off + e.folio_len);
        // A repeated title would make `find` answer for one member and stand
        // for two. Refused at read as well as at write, because a codex this
        // reader did not write is still a codex it must not half-answer for.
        for (0..i) |j| {
            if (std.mem.eql(u8, c.titleAt(@intCast(j)), c.titleAt(@intCast(i)))) {
                return Error.FolioBadDirectory;
            }
        }
    }
    return c;
}

/// Bind proven folios into one codex. Each part is the complete bytes of a
/// folio - what `impose.pack` returns or a lone `.folio` file holds - and each
/// is proven here first, so a codex can only ever be packed from members that
/// would have loaded on their own. Titles come from the members themselves;
/// there is no caller-supplied name to disagree with the file.
///
/// Eight-aligned, same contract as `impose.pack`. Free with `gpa.free`.
pub fn pack(
    gpa: std.mem.Allocator,
    parts: []const []align(leaf.section_align) const u8,
) PackError![]align(leaf.section_align) u8 {
    if (parts.len == 0) return PackError.CodexEmpty;
    const count = std.math.cast(u32, parts.len) orelse return PackError.CodexTooLarge;

    var arena_len: u64 = 0;
    for (parts, 0..) |part, i| {
        const f = try collate.open(part);
        arena_len += f.title().len;
        for (parts[0..i]) |before| {
            const b = try collate.open(before);
            if (std.mem.eql(u8, b.title(), f.title())) return PackError.TitleRepeated;
        }
    }
    const arena_fits = std.math.cast(u32, arena_len) orelse return PackError.CodexTooLarge;

    const dir_len = preamble(count, arena_fits);
    var at = leaf.align8(dir_len + signet.len);
    // The last member needs no padding after it, so the file ends where its
    // bytes do rather than at the next boundary.
    var total: u64 = at;
    for (parts, 0..) |part, i| {
        total += part.len;
        if (i + 1 < parts.len) total = leaf.align8(total);
    }
    const file_len = std.math.cast(usize, total) orelse return PackError.CodexTooLarge;

    const buf = try gpa.alignedAlloc(u8, comptime .fromByteUnits(leaf.section_align), file_len);
    errdefer gpa.free(buf);
    // Zeroed, so the padding between members is a fact rather than whatever
    // the allocator last held - the same reproducibility rule `impose` keeps.
    @memset(buf, 0);

    @memcpy(buf[0..magic.len], magic);
    std.mem.writeInt(u16, buf[8..10], version, .little);
    std.mem.writeInt(u32, buf[12..16], count, .little);
    std.mem.writeInt(u32, buf[16..20], arena_fits, .little);
    std.mem.writeInt(u64, buf[24..32], total, .little);

    const arena_at: usize = header_len + @as(usize, count) * entry_len;
    var title_off: u32 = 0;
    for (parts, 0..) |part, i| {
        // Proven above; reopened for the title rather than cached, because a
        // few directory reads cost less than carrying a parallel array whose
        // indices could drift from the loop writing entries.
        const f = collate.open(part) catch unreachable;
        const title = f.title();
        @memcpy(buf[arena_at + title_off ..][0..title.len], title);
        const e: Entry = .{
            .title_off = title_off,
            .title_len = @intCast(title.len),
            .folio_off = at,
            .folio_len = part.len,
        };
        e.write(buf[header_len + i * entry_len ..][0..entry_len]);
        @memcpy(buf[@intCast(at)..][0..part.len], part);
        title_off += @intCast(title.len);
        at = leaf.align8(at + part.len);
    }
    signet.sealAt(buf, @intCast(dir_len));
    return buf;
}
