//! The bodies behind `libotl`'s exports: open a bank of languages, lend a
//! parser out of it, hand trees back.
//!
//! In `exports.zig`'s module rather than the library's, the same split the
//! sibling packages keep: the artifact root is a *consumer* of `outliner`, so
//! nothing a CLI needs can quietly become something an embedder must link,
//! and the bodies stay testable without going through C.
//!
//! Three handles, in a strict lifetime order a host has to keep: a `Tree`
//! borrows its `Parser` (for the grammar the node names live in), a `Parser`
//! borrows its `Bank` (for the mapped bytes those names are views into). Free
//! them in reverse. Nothing here is thread-safe except reading two different
//! handles from two different threads: a parser owns the scratch its parses
//! run in, so compile one per thread rather than sharing one under a lock.
//!
//! Strings cross the boundary two ways, on purpose. Titles, node names, and
//! renders are **pointer + length views** borrowed from the handle that
//! answered - a folio's names are mmap-ed bytes and a copy per call would be
//! the allocation this format exists to avoid. Only `otl_version` and
//! `otl_last_error` are NUL-terminated, because those are for logs.
//!
//! Every entry returns a status instead of aborting, so a malformed file or a
//! wrong language can never terminate the host. On a negative status,
//! `otl_last_error()` holds the sentence the CLI would have printed - per
//! thread, valid until that thread's next `otl_*` call.

const std = @import("std");
const outliner = @import("outliner");

const folio = outliner.folio;
const press = outliner.press;
const import = outliner.press.import;
const g = outliner.press.grammar;
const scanner = outliner.kernel.lex.scanner;
const quire = outliner.kernel.quire;

const gpa = std.heap.c_allocator;

/// The status vocabulary. Non-negative is success; each negative names whose
/// fault the refusal is, because a host retries an `io` and never a `format`.
pub const Status = enum(c_int) {
    ok = 0,
    /// A NULL argument, or a handle used against its lifetime contract.
    invalid = -1,
    /// The file could not be read at all.
    io = -2,
    /// The file was read and is not a folio, codex, or grammar.json this
    /// build can load - corrupt, sealed wrong, or minted by another version.
    format = -3,
    /// The language asked for is not in the bank, or several are and none
    /// was named. `otl_last_error` carries the roster.
    language = -4,
    /// The grammar was read whole and refused by the importer or the press.
    grammar = -5,
    out_of_memory = -6,
};

/// How a parse ended, mirroring `quire.Stop` one to one. `accepted` is the
/// only whole tree; the rest name where reading got hard, and the tree is
/// still handed back, because a partial tree plus the reason beats an error
/// with no prefix.
pub const StopKind = enum(c_int) { accepted = 0, stray = 1, unexpected = 2, truncated = 3 };

/// The ref that is not a node - `otl_node_kid` past the end, `otl_node_field`
/// on nothing. Same value the kernel uses, re-exported so the header can name
/// it.
pub const none: u32 = quire.none;

// ── the per-thread fault sentence ────────────────────────────────────────────

threadlocal var fault_buf: [512:0]u8 = undefined;
threadlocal var fault_len: usize = 0;

fn clear() void {
    fault_len = 0;
    fault_buf[0] = 0;
}

fn fail(status: Status, comptime fmt: []const u8, args: anytype) Status {
    const written = std.fmt.bufPrintZ(&fault_buf, fmt, args) catch blk: {
        // The detail outgrew the slot; the head of it still names the fault.
        fault_buf[fault_buf.len - 1] = 0;
        break :blk fault_buf[0 .. fault_buf.len - 1 :0];
    };
    fault_len = written.len;
    return status;
}

/// The sentence behind the last failing call on this thread, or "" after a
/// call that succeeded. Reading does not consume.
pub fn lastError() [*:0]const u8 {
    return if (fault_len > 0) &fault_buf else "";
}

// ── the bank ─────────────────────────────────────────────────────────────────

/// An opened source of languages: a folio, a codex, or a grammar.json that
/// was imported and pressed on open. Which one it was decides what the open
/// cost - single-digit milliseconds for the mapped two, a real press for the
/// JSON - and nothing downstream can tell the difference, which is the point.
pub const Bank = struct {
    source: union(enum) {
        mapped: folio.MappedVolume,
        pressed: struct { gr: g.Grammar, built: press.Result },
    },

    pub fn count(bk: *const Bank) u32 {
        return switch (bk.source) {
            .mapped => |*m| m.volume.count(),
            .pressed => 1,
        };
    }

    pub fn title(bk: *const Bank, i: u32) ?[]const u8 {
        if (i >= bk.count()) return null;
        return switch (bk.source) {
            .mapped => |*m| m.volume.titleAt(i),
            .pressed => |*x| x.gr.name,
        };
    }
};

/// `otl_open`. The same first-eight-bytes sniff as the CLI: a folio or codex
/// is mapped, anything else is a grammar.json until the importer says
/// otherwise, and a *real* folio failing is reported as that folio failing
/// rather than retried as JSON.
pub fn open(path_z: ?[*:0]const u8, out: ?**Bank) Status {
    clear();
    const slot = out orelse return fail(.invalid, "otl_open: out is NULL", .{});
    const path = std.mem.span(path_z orelse return fail(.invalid, "otl_open: path is NULL", .{}));

    var threaded = std.Io.Threaded.init(gpa, .{});
    defer threaded.deinit();
    const io = threaded.io();

    if (folio.mapVolume(io, std.Io.Dir.cwd(), path)) |mapped| {
        const bank = gpa.create(Bank) catch {
            var m = mapped;
            m.close();
            return fail(.out_of_memory, "out of memory", .{});
        };
        bank.* = .{ .source = .{ .mapped = mapped } };
        slot.* = bank;
        return .ok;
    } else |err| switch (err) {
        error.FolioBadMagic, error.FolioTooSmall => {},
        error.FileNotFound => return fail(.io, "{s}: file not found", .{path}),
        else => return fail(.format, "{s} does not load: {s}", .{ path, @errorName(err) }),
    }

    const source = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64 << 20)) catch |err| {
        return fail(.io, "cannot read {s}: {s}", .{ path, @errorName(err) });
    };
    defer gpa.free(source);
    var gr = import.treeSitter(gpa, source) catch |err| {
        return fail(.grammar, "cannot import {s}: {s}", .{ path, @errorName(err) });
    };
    var built = press.tables(gpa, &gr) catch |err| {
        gr.deinit();
        return fail(.grammar, "cannot press {s}: {s}", .{ gr.name, @errorName(err) });
    };
    const bank = gpa.create(Bank) catch {
        built.deinit();
        gr.deinit();
        return fail(.out_of_memory, "out of memory", .{});
    };
    bank.* = .{ .source = .{ .pressed = .{ .gr = gr, .built = built } } };
    slot.* = bank;
    return .ok;
}

/// `otl_close`. Every parser lent from the bank must be freed first.
pub fn close(bank: *Bank) void {
    switch (bank.source) {
        .mapped => |*m| m.close(),
        .pressed => |*x| {
            x.built.deinit();
            x.gr.deinit();
        },
    }
    gpa.destroy(bank);
}

// ── the parser ───────────────────────────────────────────────────────────────

/// One language, ready to parse: the tables bound, the terminal scanner
/// compiled, the gather standing. Owns its scratch, so one per thread.
pub const Parser = struct {
    bank: *Bank,
    /// Set when the bank is mapped; a pressed bank's tables are borrowed from
    /// the bank itself.
    bound: ?folio.Bound,
    sc: scanner.Scanner,
    gather: quire.Gather,

    pub fn grammar(p: *const Parser) *const g.Grammar {
        return if (p.bound) |*b| &b.grammar else &p.bank.source.pressed.gr;
    }
};

/// `otl_parser_new`. `language` null means "the obvious one", which exists
/// only when the bank holds exactly one - a codex of several is refused with
/// its roster in `otl_last_error`, never guessed at, because a python file
/// parsed with the rust tables hands back a tree that looks fine and is wrong.
pub fn parserNew(bank: ?*Bank, language_z: ?[*:0]const u8, out: ?**Parser) Status {
    clear();
    const slot = out orelse return fail(.invalid, "otl_parser_new: out is NULL", .{});
    const bk = bank orelse return fail(.invalid, "otl_parser_new: bank is NULL", .{});
    const language: ?[]const u8 = if (language_z) |z| std.mem.span(z) else null;

    const p = gpa.create(Parser) catch return fail(.out_of_memory, "out of memory", .{});
    p.bank = bk;
    p.bound = null;
    switch (bk.source) {
        .mapped => |*m| {
            var f = m.volume.pick(language) catch |err| {
                gpa.destroy(p);
                return switch (err) {
                    error.TitleUnknown => roster(bk, .language, "no language named {s}; the bank holds", .{language.?}),
                    error.TitleAmbiguous => roster(bk, .language, "{d} languages and none named; the bank holds", .{m.volume.count()}),
                    else => |e| fail(.format, "cannot open the member: {s}", .{@errorName(e)}),
                };
            };
            p.bound = folio.bind(gpa, &f) catch |err| {
                gpa.destroy(p);
                return fail(.format, "cannot bind {s}: {s}", .{ f.title(), @errorName(err) });
            };
        },
        .pressed => |*x| {
            if (language) |want| {
                if (!std.mem.eql(u8, x.gr.name, want)) {
                    gpa.destroy(p);
                    return fail(.language, "this bank holds {s}, not {s}", .{ x.gr.name, want });
                }
            }
        },
    }

    const gr = p.grammar();
    p.sc = (scanner.Scanner.compile(gpa, gr) catch |err| {
        unbind(p);
        return fail(.grammar, "cannot compile {s}'s scanner: {s}", .{ gr.name, @errorName(err) });
    }) orelse {
        unbind(p);
        return fail(.grammar, "{s} has no lexable terminal at all", .{gr.name});
    };
    const collection = if (p.bound) |*b| &b.collection else &p.bank.source.pressed.built.collection;
    const tables = if (p.bound) |*b| &b.tables else &p.bank.source.pressed.built.tables;
    p.gather = quire.Gather.init(gpa, gr, collection, tables, &p.sc) catch {
        p.sc.deinit();
        unbind(p);
        return fail(.out_of_memory, "out of memory", .{});
    };
    slot.* = p;
    return .ok;
}

fn unbind(p: *Parser) void {
    if (p.bound) |*b| b.deinit();
    gpa.destroy(p);
}

/// The refusal that lists what the bank actually holds, so the retry can be
/// typed off the message instead of discovered by a second probe.
fn roster(bk: *const Bank, status: Status, comptime fmt: []const u8, args: anytype) Status {
    _ = fail(status, fmt, args);
    var at = fault_len;
    for (0..bk.count()) |i| {
        const t = bk.title(@intCast(i)).?;
        if (at + t.len + 2 >= fault_buf.len) break;
        fault_buf[at] = ' ';
        @memcpy(fault_buf[at + 1 ..][0..t.len], t);
        at += t.len + 1;
    }
    fault_buf[at] = 0;
    fault_len = at;
    return status;
}

/// `otl_parser_free`. Trees lent from this parser must be freed first.
pub fn parserFree(p: *Parser) void {
    p.gather.deinit();
    p.sc.deinit();
    unbind(p);
}

/// `otl_parser_language`: the name of the grammar this parser parses.
pub fn parserLanguage(p: *const Parser) []const u8 {
    return p.grammar().name;
}

/// `otl_parser_blind`: how many externally scanned terminals this grammar has
/// that no lexer rule can produce - the honesty number the CLI prints before
/// any tree, surfaced so an embedder can decide whether a stop is a wall or
/// a known blindness.
pub fn parserBlind(p: *const Parser) u32 {
    return @intCast(p.sc.blind.len);
}

// ── the tree ─────────────────────────────────────────────────────────────────

/// One parse: the quire, its survey, and the renders it has been asked for.
pub const Tree = struct {
    parser: *Parser,
    q: quire.Quire,
    found: quire.Quire.Survey,
    /// The s-expression render, cached per `Show` - a tree does not change
    /// under a handle, so the second ask is a pointer return.
    rendered: [2]?[:0]u8 = .{ null, null },
};

/// `otl_parse`. The tree comes back on every status `.ok`, accepted or not;
/// `otl_tree_stop` says which, exactly as the CLI splits stdout and stderr.
pub fn parse(parser: ?*Parser, text: ?[*]const u8, len: usize, out: ?**Tree) Status {
    clear();
    const slot = out orelse return fail(.invalid, "otl_parse: out is NULL", .{});
    const p = parser orelse return fail(.invalid, "otl_parse: parser is NULL", .{});
    const bytes: []const u8 = if (len == 0) &.{} else b: {
        const t = text orelse return fail(.invalid, "otl_parse: text is NULL with len {d}", .{len});
        break :b t[0..len];
    };

    var q = p.gather.run(bytes) catch |err| {
        return fail(.out_of_memory, "parse failed: {s}", .{@errorName(err)});
    };
    // Surveyed on every parse, not on request - the same contract the CLI
    // keeps. A tree that is not a tree must say so from the first question.
    const found = q.survey(gpa) catch |err| {
        q.deinit();
        return fail(.out_of_memory, "survey failed: {s}", .{@errorName(err)});
    };
    const t = gpa.create(Tree) catch {
        q.deinit();
        return fail(.out_of_memory, "out of memory", .{});
    };
    t.* = .{ .parser = p, .q = q, .found = found };
    slot.* = t;
    return .ok;
}

pub fn treeFree(t: *Tree) void {
    for (t.rendered) |r| if (r) |s| gpa.free(s);
    t.q.deinit();
    gpa.destroy(t);
}

pub fn stopKind(t: *const Tree) StopKind {
    return switch (t.q.stop) {
        .accepted => .accepted,
        .stray => .stray,
        .unexpected => .unexpected,
        .truncated => .truncated,
    };
}

/// The byte the stop names, for the two stops that name one; 0 otherwise.
pub fn stopAt(t: *const Tree) u32 {
    return switch (t.q.stop) {
        .stray => |off| off,
        .unexpected => |u| u.at,
        .accepted, .truncated => 0,
    };
}

/// The terminal an `unexpected` stop refused, or null for the other three.
pub fn stopWord(t: *const Tree) ?[]const u8 {
    return switch (t.q.stop) {
        .unexpected => |u| t.parser.grammar().nameOf(u.symbol),
        else => null,
    };
}

/// The whole forest as the s-expression the CLI prints, one root per line.
/// Borrowed from the tree, rendered once per `Show`, NUL-terminated as a
/// convenience the node names cannot give. Null only on out of memory.
pub fn sexp(t: *Tree, all: bool, len: ?*usize) ?[*:0]const u8 {
    const slot = &t.rendered[@intFromBool(all)];
    if (slot.* == null) {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        const show: quire.Show = if (all) .all else .named;
        for (t.q.roots) |r| {
            const one = t.q.sexp(gpa, r, show) catch return null;
            defer gpa.free(one);
            out.appendSlice(gpa, one) catch return null;
            out.append(gpa, '\n') catch return null;
        }
        slot.* = out.toOwnedSliceSentinel(gpa, 0) catch return null;
    }
    if (len) |l| l.* = slot.*.?.len;
    return slot.*.?.ptr;
}

// ── the nodes ────────────────────────────────────────────────────────────────
// Refs, not pointers: a node is an index into the tree's arena, `none` is the
// answer that is not a node, and every accessor bounds-checks rather than
// trusting the host - the kernel's own accessors are allowed to assume what
// a C caller must not be.

pub fn rootCount(t: *const Tree) u32 {
    return @intCast(t.q.roots.len);
}

pub fn rootAt(t: *const Tree, i: u32) u32 {
    return if (i < t.q.roots.len) t.q.roots[i] else none;
}

fn held(t: *const Tree, ref: u32) bool {
    return ref < t.q.nodes.len;
}

pub fn nodeName(t: *const Tree, ref: u32) ?[]const u8 {
    return if (held(t, ref)) t.q.name(ref) else null;
}

pub fn nodeNamed(t: *const Tree, ref: u32) bool {
    return held(t, ref) and t.q.isNamed(ref);
}

pub fn nodeStart(t: *const Tree, ref: u32) u32 {
    return if (held(t, ref)) t.q.nodes[ref].start else 0;
}

pub fn nodeEnd(t: *const Tree, ref: u32) u32 {
    return if (held(t, ref)) t.q.nodes[ref].end() else 0;
}

pub fn nodeKids(t: *const Tree, ref: u32) u32 {
    return if (held(t, ref)) t.q.nodes[ref].kids_len else 0;
}

pub fn nodeKid(t: *const Tree, ref: u32, i: u32) u32 {
    if (!held(t, ref)) return none;
    const kids = t.q.children(ref);
    return if (i < kids.len) kids[i] else none;
}

pub fn nodeField(t: *const Tree, ref: u32) ?[]const u8 {
    return if (held(t, ref)) t.q.field(ref) else null;
}

// -------------------------------------------------------- the wiring, asserted

const testing = std.testing;

/// The committed 13 KB json grammar, same fixture the library tests press.
const json_grammar = @embedFile("json_grammar");

fn pressedBank() !*Bank {
    // Through the C door, not around it: write the grammar to a temp file and
    // open it by path, because the path arm is the contract being tested.
    // The tmp dir lives under `.zig-cache/tmp/` relative to the test's cwd,
    // which is the same cwd `open` resolves against - so the relative path is
    // the honest one, and no realpath is needed.
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "g.json", .data = json_grammar });
    const path = try std.fmt.allocPrintSentinel(testing.allocator, ".zig-cache/tmp/{s}/g.json", .{tmp.sub_path}, 0);
    defer testing.allocator.free(path);
    var bank: *Bank = undefined;
    try testing.expectEqual(Status.ok, open(path.ptr, &bank));
    return bank;
}

test "a grammar.json opens as a bank of one and parses through the ABI" {
    const bank = try pressedBank();
    defer close(bank);
    try testing.expectEqual(@as(u32, 1), bank.count());
    try testing.expectEqualStrings("json", bank.title(0).?);

    var p: *Parser = undefined;
    try testing.expectEqual(Status.ok, parserNew(bank, null, &p));
    defer parserFree(p);
    try testing.expectEqualStrings("json", parserLanguage(p));

    const text = "{\"a\": [1, 2]}";
    var t: *Tree = undefined;
    try testing.expectEqual(Status.ok, parse(p, text.ptr, text.len, &t));
    defer treeFree(t);
    try testing.expectEqual(StopKind.accepted, stopKind(t));
    try testing.expectEqual(@as(u32, 1), rootCount(t));

    const root = rootAt(t, 0);
    try testing.expectEqualStrings("document", nodeName(t, root).?);
    try testing.expectEqual(@as(u32, 0), nodeStart(t, root));
    try testing.expectEqual(@as(u32, @intCast(text.len)), nodeEnd(t, root));

    var n: usize = 0;
    const s = sexp(t, false, &n).?;
    try testing.expect(std.mem.startsWith(u8, s[0..n], "(document"));
    // The second ask is the cached pointer, not a second render.
    try testing.expectEqual(s, sexp(t, false, null).?);
}

test "the wrong language is refused with the roster, not guessed at" {
    const bank = try pressedBank();
    defer close(bank);
    var p: *Parser = undefined;
    try testing.expectEqual(Status.language, parserNew(bank, "python", &p));
    const said = std.mem.span(lastError());
    try testing.expect(std.mem.indexOf(u8, said, "json") != null);
}

test "a ref past the arena answers none, never a read" {
    const bank = try pressedBank();
    defer close(bank);
    var p: *Parser = undefined;
    try testing.expectEqual(Status.ok, parserNew(bank, null, &p));
    defer parserFree(p);
    var t: *Tree = undefined;
    try testing.expectEqual(Status.ok, parse(p, "1", 1, &t));
    defer treeFree(t);
    try testing.expectEqual(none, nodeKid(t, rootAt(t, 0), 999));
    try testing.expectEqual(none, rootAt(t, 999));
    try testing.expect(nodeName(t, none) == null);
    try testing.expectEqual(@as(u32, 0), nodeKids(t, none));
}

test "null arguments are refused rather than dereferenced" {
    try testing.expectEqual(Status.invalid, open(null, null));
    try testing.expectEqual(Status.invalid, parserNew(null, null, null));
    var t: *Tree = undefined;
    try testing.expectEqual(Status.invalid, parse(null, null, 0, &t));
}
