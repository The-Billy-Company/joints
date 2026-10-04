"""Exercise the real shared library, including refusal and handle lifetimes."""

from pathlib import Path
import threading
import unittest

from joints import Bank, JointsError, ParseError

ROOT = Path(__file__).resolve().parents[3]
GRAMMAR = ROOT / "test" / "grammar" / "json.json"


class BindingTests(unittest.TestCase):
    def test_nodes_fields_utf8_and_parentage(self):
        with Bank(GRAMMAR) as bank, bank.parser() as parser:
            self.assertEqual(bank.languages, ("json",))
            self.assertEqual(parser.language, "json")
            with parser.parse('{\n "é": [1, 2]\n}') as tree:
                root = tree.root_node
                self.assertEqual(root.type, "document")
                self.assertTrue(tree.sound)
                pair = root.named_children[0].named_children[0]
                self.assertEqual(pair.type, "pair")
                key = pair.child_by_field_name("key")
                value = pair.child_by_field_name("value")
                self.assertEqual(key.text, '"é"'.encode())
                self.assertEqual(key.start_point, (1, 1))
                self.assertEqual(key.end_point, (1, 5))
                self.assertEqual(value.type, "array")
                self.assertEqual(value.parent, pair)
                self.assertEqual(pair.field_name_for_child(0), "key")
                self.assertIsNone(pair.child(999))
                self.assertIsNone(pair.child_by_field_name("absent"))
                self.assertIn("pair", tree.sexp())

    def test_multiple_trees_survive_parser_reuse(self):
        with Bank(GRAMMAR) as bank, bank.parser() as parser:
            with parser.parse("[1]") as first, parser.parse("[2,3]") as second:
                self.assertEqual(first.root_node.text, b"[1]")
                self.assertEqual(second.root_node.text, b"[2,3]")

    def test_repairs_never_clear_a_strict_parse(self):
        with Bank(GRAMMAR) as bank, bank.parser() as parser:
            for source in (b"[1,", b'{"a": @ 2}', b'{"a" 2}'):
                with self.subTest(source=source), self.assertRaises(ParseError):
                    parser.parse(source)
                with parser.parse(source, strict=False) as tree:
                    self.assertTrue(
                        tree.stop != "accepted" or tree.mends or tree.supplied
                    )
                    repairs = tree.repairs
                    self.assertEqual(sum(r.over - r.at for r in repairs), tree.skipped)
                    self.assertEqual(sum(r.supplied for r in repairs), tree.supplied)

    def test_close_order_and_stale_nodes_are_rejected(self):
        with Bank(GRAMMAR) as bank, bank.parser() as parser:
            tree = parser.parse("[1]")
            root = tree.root_node
            with self.assertRaises(JointsError):
                parser.close()
            with self.assertRaises(JointsError):
                bank.close()
            tree.close()
            tree.close()
            with self.assertRaises(JointsError):
                _ = root.text

    def test_query_predicate_empty_result_and_capture_order(self):
        with Bank(GRAMMAR) as bank, bank.parser() as parser:
            with parser.parse("[1,2,3]") as tree:
                with parser.query("(number) @n") as query:
                    self.assertEqual(query.capture_names, ("n",))
                    self.assertEqual(
                        [n.text for n in query.captures(tree)["n"]], [b"1", b"2", b"3"]
                    )
                    self.assertEqual(len(query.matches(tree)), 3)
                with parser.query('((number) @n (#eq? @n "2"))') as query:
                    self.assertEqual(
                        [n.text for n in query.captures(tree)["n"]], [b"2"]
                    )
                with parser.query("(object) @object") as query:
                    self.assertEqual(query.matches(tree), [])
                with self.assertRaises(JointsError):
                    parser.query("(unrecognized_kind) @n")

    def test_query_wrong_parser_and_unknown_predicate_fail_closed(self):
        with Bank(GRAMMAR) as bank, bank.parser() as parser, bank.parser() as other:
            with parser.parse("[1]") as tree, other.query("(number) @n") as query:
                with self.assertRaises(JointsError):
                    query.matches(tree)
            with parser.parse("[1]") as tree:
                with parser.query("((number) @n (#unrecognized? @n))") as query:
                    with self.assertRaises(JointsError):
                        query.matches(tree)
                    self.assertEqual(len(query.matches(tree, foreign="admit")), 1)
                    self.assertEqual(query.matches(tree, foreign="deny"), [])

    def test_parser_thread_affinity(self):
        with Bank(GRAMMAR) as bank, bank.parser() as parser:
            errors = []

            def wrong_thread():
                try:
                    parser.parse("[1]")
                except Exception as error:
                    errors.append(error)

            thread = threading.Thread(target=wrong_thread)
            thread.start()
            thread.join()
            self.assertEqual(len(errors), 1)
            self.assertIsInstance(errors[0], JointsError)
            with parser.parse("[1]") as tree:
                self.assertEqual(tree.root_node.text, b"[1]")

    def test_nested_query_enumerates_every_sibling(self):
        with Bank(GRAMMAR) as bank, bank.parser() as parser:
            with parser.parse('{"a": [1,2,3]}') as tree:
                with parser.query(
                    "(document (object (pair value: (array (number) @n))))"
                ) as query:
                    self.assertEqual(
                        [n.text for n in query.captures(tree)["n"]], [b"1", b"2", b"3"]
                    )

    def test_invalid_regex_never_becomes_an_unconstrained_match(self):
        with Bank(GRAMMAR) as bank, bank.parser() as parser:
            with parser.parse("[1]") as tree:
                with self.assertRaises(JointsError):
                    with parser.query('((number) @n (#match? @n "["))') as query:
                        query.matches(tree)

    def test_bank_operations_cannot_race_cross_thread_close(self):
        with Bank(GRAMMAR) as bank:
            errors = []

            def wrong_thread():
                for operation in (lambda: bank.languages, bank.parser, bank.close):
                    try:
                        operation()
                    except Exception as error:
                        errors.append(error)

            thread = threading.Thread(target=wrong_thread)
            thread.start()
            thread.join()
            self.assertEqual(len(errors), 3)
            self.assertTrue(all(isinstance(e, JointsError) for e in errors))
            self.assertEqual(bank.languages, ("json",))

    def test_paths_do_not_truncate_at_nul(self):
        with self.assertRaises(ValueError):
            Bank(str(GRAMMAR) + "\0ignored")


if __name__ == "__main__":
    unittest.main()
