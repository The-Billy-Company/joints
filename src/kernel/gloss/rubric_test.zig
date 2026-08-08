//! What the reader has to get right, ordered by how often the corpus says it.
//!
//! Every literal in this file that looks strange is a real line from
//! `.local/glossprobe/queries/`, kept verbatim: `_ * @name` is swift's
//! `outline.scm`, the parenthesized group is swift's `highlights.scm`, and the
//! `#offset!` with a negative argument is python's `injections.scm`. A
//! hand-invented query would have agreed with the documentation and missed all
//! three.

const std = @import("std");
const rubric = @import("rubric.zig");

const gpa = std.testing.allocator;

fn read(src: []const u8) !rubric.Rubric {
    return rubric.read(gpa, src, null);
}

/// The one pattern's root, for the common case of a single-pattern source.
fn only(r: rubric.Rubric) rubric.Item {
    return r.patterns[0].root;
}

test "rubric: a named node with a capture" {
    var r = try read("(identifier) @variable");
    defer r.deinit();

    try std.testing.expectEqual(1, r.patterns.len);
    const root = only(r);
    try std.testing.expectEqualStrings("identifier", root.shape.node.kind);
    try std.testing.expectEqual(1, root.captures.len);
    try std.testing.expectEqualStrings("variable", root.captures[0]);
}

test "rubric: children, fields and anonymous literals" {
    var r = try read(
        \\(call_expression
        \\  function: (identifier) @fn
        \\  "(" @open)
    );
    defer r.deinit();

    const kids = only(r).shape.node.children;
    try std.testing.expectEqual(2, kids.len);
    try std.testing.expectEqualStrings("function", kids[0].field.?);
    try std.testing.expectEqualStrings("identifier", kids[0].shape.node.kind);
    try std.testing.expectEqualStrings("(", kids[1].shape.literal);
    try std.testing.expectEqualStrings("open", kids[1].captures[0]);
}

test "rubric: several patterns in one file" {
    var r = try read(
        \\; a comment, which runs to the end of the line
        \\(a) @one
        \\(b) @two
        \\"c" @three
    );
    defer r.deinit();

    try std.testing.expectEqual(3, r.patterns.len);
    try std.testing.expectEqualStrings("c", r.patterns[2].root.shape.literal);
}

test "rubric: alternation" {
    var r = try read(
        \\[ "if" "else" (identifier) ] @keyword
    );
    defer r.deinit();

    const root = only(r);
    try std.testing.expectEqual(3, root.shape.choice.len);
    try std.testing.expectEqualStrings("keyword", root.captures[0]);
}

test "rubric: quantifiers, including the whitespace the docs forbid" {
    // swift/outline.scm writes exactly this, and `ts_query_new` takes it.
    var r = try read("(x (comment) _ * @name)");
    defer r.deinit();

    const kids = only(r).shape.node.children;
    try std.testing.expectEqual(2, kids.len);
    try std.testing.expectEqual(rubric.Quantifier.star, kids[1].quantifier);
    try std.testing.expect(kids[1].shape == .wildcard);
    try std.testing.expectEqualStrings("name", kids[1].captures[0]);
}

test "rubric: a quantifier and a capture in either order" {
    var a = try read("(x (y)? @c)");
    defer a.deinit();
    var b = try read("(x (y) @c ?)");
    defer b.deinit();

    for ([_]rubric.Rubric{ a, b }) |r| {
        const kid = only(r).shape.node.children[0];
        try std.testing.expectEqual(rubric.Quantifier.optional, kid.quantifier);
        try std.testing.expectEqualStrings("c", kid.captures[0]);
    }
}

test "rubric: anchors before, between and after" {
    var r = try read("(block . (a) . (b) .)");
    defer r.deinit();

    const node = only(r).shape.node;
    try std.testing.expect(node.children[0].anchored);
    try std.testing.expect(node.children[1].anchored);
    try std.testing.expect(node.closed);
}

test "rubric: a bare wildcard and a parenthesized one are different shapes" {
    var r = try read("(x _ (_) (_ (y)))");
    defer r.deinit();

    const kids = only(r).shape.node.children;
    try std.testing.expect(kids[0].shape == .wildcard);
    try std.testing.expectEqualStrings("_", kids[1].shape.node.kind);
    // The point of keeping them apart: `(_)` carries children and `_` cannot.
    try std.testing.expectEqual(1, kids[2].shape.node.children.len);
}

test "rubric: a supertype constrains a concrete kind" {
    var r = try read("(expression/binary_expression) @e");
    defer r.deinit();

    const node = only(r).shape.node;
    try std.testing.expectEqualStrings("expression", node.supertype.?);
    try std.testing.expectEqualStrings("binary_expression", node.kind);
}

test "rubric: a negated field" {
    var r = try read("(class_declaration !type_parameters) @c");
    defer r.deinit();

    const node = only(r).shape.node;
    try std.testing.expectEqual(1, node.absent.len);
    try std.testing.expectEqualStrings("type_parameters", node.absent[0]);
}

test "rubric: a parenthesized group is a sequence, not a rule name" {
    // swift/highlights.scm. `(` followed by `[` cannot be a node.
    var r = try read(
        \\(call (simple_identifier) declaration_kind: ( [ "actor" "class" ] ) @kind)
    );
    defer r.deinit();

    const kids = only(r).shape.node.children;
    try std.testing.expectEqual(2, kids.len);
    try std.testing.expectEqualStrings("declaration_kind", kids[1].field.?);
    try std.testing.expectEqual(1, kids[1].shape.group.len);
    try std.testing.expect(kids[1].shape.group[0].shape == .choice);
}

test "rubric: a predicate belongs to the pattern, however deep it is written" {
    var r = try read(
        \\((identifier) @const (#match? @const "^[A-Z]+$"))
        \\(call (a (b) (#eq? @x "y")) @outer)
    );
    defer r.deinit();

    try std.testing.expectEqual(2, r.patterns.len);
    const shallow = r.patterns[0].predicates;
    try std.testing.expectEqual(1, shallow.len);
    try std.testing.expectEqualStrings("match?", shallow[0].name);
    try std.testing.expectEqualStrings("const", shallow[0].args[0].capture);
    try std.testing.expectEqualStrings("^[A-Z]+$", shallow[0].args[1].text);

    // Written three nodes down and still the whole pattern's constraint.
    try std.testing.expectEqual(1, r.patterns[1].predicates.len);
    try std.testing.expectEqualStrings("eq?", r.patterns[1].predicates[0].name);
}

test "rubric: a predicate occupies no position" {
    var r = try read("((a) (#set! x y) (b))");
    defer r.deinit();

    // Three written positions, two of them pattern items.
    try std.testing.expectEqual(2, only(r).shape.group.len);
    try std.testing.expectEqual(1, r.patterns[0].predicates.len);
}

test "rubric: a bare predicate argument is a string" {
    // python/injections.scm and a neovim extension, both verbatim.
    var r = try read(
        \\((c) @x (#offset! @x 0 1 0 -1) (#is-not? local))
    );
    defer r.deinit();

    const preds = r.patterns[0].predicates;
    try std.testing.expectEqual(2, preds.len);
    try std.testing.expectEqualStrings("offset!", preds[0].name);
    try std.testing.expectEqualStrings("-1", preds[0].args[4].text);
    try std.testing.expectEqualStrings("is-not?", preds[1].name);
    try std.testing.expectEqualStrings("local", preds[1].args[0].text);
}

test "rubric: escapes reach the consumer decoded" {
    var r = try read(
        \\((c) @x (#match? @x "^\\(\\*") (#eq? @x "a\"b\n"))
    );
    defer r.deinit();

    const preds = r.patterns[0].predicates;
    try std.testing.expectEqualStrings("^\\(\\*", preds[0].args[1].text);
    try std.testing.expectEqualStrings("a\"b\n", preds[1].args[1].text);
}

test "rubric: a capture name may carry dots" {
    var r = try read("(a) @comment.documentation");
    defer r.deinit();

    try std.testing.expectEqualStrings("comment.documentation", only(r).captures[0]);
}

test "rubric: several captures on one position" {
    var r = try read("(a) @one @two");
    defer r.deinit();

    try std.testing.expectEqual(2, only(r).captures.len);
    try std.testing.expectEqualStrings("two", only(r).captures[1]);
}

test "rubric: refusals name where they happened" {
    const cases = [_]struct { src: []const u8, want: anyerror }{
        .{ .src = "(a", .want = rubric.Error.QueryUnbalanced },
        .{ .src = "(a))", .want = rubric.Error.QueryUnbalanced },
        .{ .src = "[a]", .want = rubric.Error.QueryUnexpected },
        .{ .src = "(a) @", .want = rubric.Error.QueryBadName },
        .{ .src = "(a \"b)", .want = rubric.Error.QueryBadString },
        .{ .src = "(a) ?", .want = rubric.Error.QueryDangling },
        .{ .src = "(a !)", .want = rubric.Error.QueryBadName },
        .{ .src = "(#set! a b)", .want = rubric.Error.QueryDangling },
    };
    for (cases) |c| {
        var fault: rubric.Fault = .{};
        try std.testing.expectError(c.want, rubric.read(gpa, c.src, &fault));
        try std.testing.expect(fault.at <= c.src.len);
    }
}

test "rubric: a fault points at a line and a column" {
    const src = "(ok)\n(also_ok)\n(broken";
    var fault: rubric.Fault = .{};
    try std.testing.expectError(rubric.Error.QueryUnbalanced, rubric.read(gpa, src, &fault));

    const at = fault.where(src);
    try std.testing.expectEqual(3, at.line);
}

test "rubric: nesting is bounded rather than fatal" {
    var deep: std.ArrayList(u8) = .empty;
    defer deep.deinit(gpa);
    for (0..rubric.depth_limit + 4) |_| try deep.appendSlice(gpa, "(a ");
    for (0..rubric.depth_limit + 4) |_| try deep.append(gpa, ')');

    try std.testing.expectError(rubric.Error.QueryTooDeep, rubric.read(gpa, deep.items, null));
}

test "rubric: weigh counts positions" {
    var r = try read("(a (b) (c (d)) [ (e) (f) ])");
    defer r.deinit();

    // a, b, c, d, the choice, e, f.
    try std.testing.expectEqual(7, rubric.weigh(only(r)));
}
