"""Keep the independent oracle's field recovery tied to actual node identity."""

import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import differential as d


def node(name, *kids, named=True, field=None):
    value = d.Node(name, named, field, 0, 1)
    value.kids = list(kids)
    return value


def description(name, **fields):
    return {"type": name, "named": True, "fields": {
        field: {"types": [{"type": kind, "named": named} for kind, named in kinds]}
        for field, kinds in fields.items()}}


def capture(pattern):
    return (f"  pattern: {pattern}\n"
            "    capture: 1 - parent, start: (0, 0), end: (0, 1), text: `x`\n"
            "    capture: 0 - child, start: (0, 0), end: (0, 1), text: `x`\n")


class OracleFields(unittest.TestCase):
    def graft(self, root, metadata, stdout, names):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            (home / "src").mkdir()
            (home / "src/node-types.json").write_text(json.dumps(metadata))
            def response(*args):
                text = stdout((home / "seat/query.scm").read_text()) if callable(stdout) else stdout
                return text if isinstance(text, subprocess.CompletedProcess) else subprocess.CompletedProcess([], 0, text, "")
            with patch.object(d, "SEAT", home / "seat"), patch.object(d, "cli", side_effect=response) as cli:
                d.graft_fields(root, home, home / "source", names, d.Lines(b"x"))
                query = (home / "seat/query.scm").read_text() if cli.called else ""
                return query

    def test_equal_span_wrappers_do_not_inherit_their_parents_field(self):
        leaf = node("type_identifier")
        user = node("user_type", leaf, field="inherits_from")
        root = node("inheritance_specifier", user)
        query = self.graft(root, [description("inheritance_specifier", inherits_from=[("user_type", True)]),
                                  description("user_type")], capture(0), ["inherits_from"])
        self.assertEqual(user.field, "inherits_from")
        self.assertIsNone(leaf.field)
        self.assertIn("(_ inherits_from: (user_type)", query)

    def test_anonymous_field_is_queried_as_a_literal(self):
        token = node("+", named=False)
        root = node("operator", token)
        query = self.graft(root, [description("operator", operator=[("+", False)])],
                           capture(0), ["operator"])
        self.assertEqual(token.field, "operator")
        self.assertIn('operator: "+" @child', query)

    def test_namedness_distinguishes_equal_type_spellings_and_spans(self):
        named, anonymous = node("x"), node("x", named=False)
        root = node("doc", named, anonymous)
        self.graft(root, [description("doc", literal=[("x", False)])], capture(0), ["literal"])
        self.assertIsNone(named.field)
        self.assertEqual(anonymous.field, "literal")

    def test_equal_kind_parent_ranges_are_disambiguated_by_child_kind(self):
        token = node("+", named=False)
        inner = node("wrap", token, field="item")
        root = node("wrap", inner)
        self.graft(root, [description("wrap", item=[("wrap", True), ("+", False)])],
                   capture(0) + capture(1), ["item"])
        self.assertEqual(inner.field, "item")
        self.assertEqual(token.field, "item")

    def test_duplicate_typed_span_siblings_refuse_without_mutating_the_tree(self):
        left, right = node("+", named=False), node("+", named=False)
        root = node("doc", left, right)
        with self.assertRaisesRegex(ValueError, "ambiguous or absent typed edge"):
            self.graft(root, [description("doc", operator=[("+", False)])], capture(0), ["operator"])
        self.assertIsNone(left.field)
        self.assertIsNone(right.field)

    def test_repeated_identical_parent_child_edges_refuse_without_guessing(self):
        left, right = node("+", named=False), node("+", named=False)
        root = node("doc", node("wrap", left), node("wrap", right))
        with self.assertRaisesRegex(ValueError, "ambiguous or absent typed edge"):
            self.graft(root, [description("wrap", operator=[("+", False)])], capture(0), ["operator"])
        self.assertIsNone(left.field)
        self.assertIsNone(right.field)

    def test_supertype_metadata_expands_to_the_actual_child_kind(self):
        child = node("identifier", field="value")
        root = node("doc", child)
        query = self.graft(root, [description("doc", value=[("expression", True)]),
                                  {"type": "expression", "named": True,
                                   "subtypes": [{"type": "identifier", "named": True}]}],
                           capture(0), ["value"])
        self.assertEqual(child.field, "value")
        self.assertIn("value: (identifier)", query)

    def test_printer_query_disagreement_refuses_before_any_assignment(self):
        good, bad = node("+", named=False), node("right", field="different")
        root = node("doc", good, bad)
        with self.assertRaisesRegex(ValueError, "printer says different"):
            self.graft(root, [description("doc", first=[("+", False)], second=[("right", True)])],
                       lambda q: capture(0) + capture(q.splitlines().index(
                           "((_ second: (right) @child) @parent)")), ["first", "second"])
        self.assertIsNone(good.field)
        self.assertEqual(bad.field, "different")

    def test_a_query_cannot_invent_a_field_on_a_named_node(self):
        child = node("identifier")
        with self.assertRaisesRegex(ValueError, "printer says None"):
            self.graft(node("doc", child), [description("doc", item=[("identifier", True)])],
                       capture(0), ["item"])
        self.assertIsNone(child.field)

    def test_named_inherited_fields_survive_missing_metadata(self):
        child = node("variable", field="bind")
        self.graft(node("quantified_variables", child), [description("quantified_variables")],
                   capture(0), ["bind"])
        self.assertEqual(child.field, "bind")

    def test_ambiguous_named_cross_checks_preserve_the_printers_fields(self):
        left, right = node("variable", field="bind"), node("variable")
        root = node("doc", node("wrap", left), node("wrap", right))
        self.graft(root, [description("wrap", bind=[("variable", True)])], capture(0), ["bind"])
        self.assertEqual(left.field, "bind")
        self.assertIsNone(right.field)

    def test_incomplete_query_identity_is_a_refusal(self):
        root = node("doc", node("x"))
        with self.assertRaisesRegex(ValueError, "incomplete parent/child identity"):
            self.graft(root, [description("doc", item=[("x", True)])],
                       "  pattern: 0\n    capture: child, start: (0, 0), end: (0, 1)\n", ["item"])

    def test_pruned_authored_field_rebuilds_the_pattern_identity_map(self):
        token = node("+", named=False)
        def response(query):
            return (subprocess.CompletedProcess([], 1, "", 'Invalid field name "gone"')
                    if "gone:" in query else capture(0))
        self.graft(node("doc", token), [description("doc", kept=[("+", False)])],
                   response, ["gone", "kept"])
        self.assertEqual(token.field, "kept")

    def test_a_field_in_the_printer_cannot_be_pruned_by_the_query(self):
        child = node("identifier", field="gone")
        with self.assertRaisesRegex(ValueError, "reported by its printer"):
            self.graft(node("doc", child), [description("doc")],
                       lambda q: subprocess.CompletedProcess([], 1, "", 'Invalid field name "gone"'), ["gone"])


if __name__ == "__main__":
    unittest.main()
