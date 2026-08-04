//! The standing type of an import: the state a grammar accumulates as it is
//! read, and the narrowing that reads it.
//!
//! A galley holds type that has been set and not yet imposed into pages, which
//! is what this is. Every symbol the front end has minted so far, the orderings
//! it cannot resolve until the rules exist, the census verdict about which
//! rules only derive a token, and the arena the whole pass is torn down with.
//! `import.zig` opens and closes exactly one of these; `muster`, `spelling` and
//! `spread` all write into that same one, which is why the state is here rather
//! than in whichever of them happens to fill a field first.
//!
//! The three accessors below are the only place `grammar.json`'s dynamic shape
//! is narrowed. Each answers null rather than failing, because a key that is
//! absent and a key that is the wrong type are the same fact to a reader that
//! has a default; the callers that cannot proceed without one say so
//! themselves, at the point where they know what it was for.

const std = @import("std");
const json = std.json;
const g = @import("grammar.zig");

pub const Error = error{ OutOfMemory, MalformedGrammar };

pub const Import = struct {
    gpa: std.mem.Allocator,
    b: *g.Builder,
    rules: *const json.ObjectMap,
    scratch: std.heap.ArenaAllocator,
    /// Declared orderings, held until the rule names inside them can resolve.
    orderings: std.ArrayList([]g.Rank) = .empty,
    pending: std.ArrayList(Unresolved) = .empty,
    /// Rule name -> its symbol, whichever space it landed in.
    symbols: std.StringHashMap(u32),
    /// The `supertypes` block, by rule name, held until the rules exist.
    supertypes: std.StringHashMap(void),
    /// Rules that spell a token some other place in the grammar also spells,
    /// so the rule derives that token rather than being it. See `census`.
    wrapping: std.StringHashMap(void),
    aux: u32 = 0,

    /// A rule an ordering named before rules were interned.
    const Unresolved = struct { list: u32, at: u32, name: []const u8 };

    pub fn deinit(self: *Import) void {
        self.scratch.deinit();
        self.orderings.deinit(self.gpa);
        self.pending.deinit(self.gpa);
        self.symbols.deinit();
        self.supertypes.deinit();
        self.wrapping.deinit();
    }
};

// ── small helpers over the dynamic JSON shape ──

pub fn obj(v: ?json.Value) ?json.ObjectMap {
    const x = v orelse return null;
    return if (x == .object) x.object else null;
}

pub fn arr(v: ?json.Value) ?json.Array {
    const x = v orelse return null;
    return if (x == .array) x.array else null;
}

pub fn str(v: ?json.Value) ?[]const u8 {
    const x = v orelse return null;
    return if (x == .string) x.string else null;
}
