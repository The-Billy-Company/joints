//! Integration checks against the real linked native parser and query engine.

use std::path::PathBuf;

use joints::{Bank, ErrorKind, ForeignPolicy, Point, Stop};

fn grammar() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/json.json")
}

#[test]
fn traverses_fields_neighbours_original_bytes_and_byte_points() {
    let bank = Bank::open(grammar()).unwrap();
    assert_eq!(bank.languages(), vec![b"json".as_slice()]);
    let parser = bank.parser(Some("json")).unwrap();
    assert_eq!(parser.language(), b"json");
    assert_eq!(parser.blind_terminals(), 0);
    let source = b"{\n  \"caf\xc3\xa9\": [1, 2],\n  \"ok\": true\n}";
    let tree = parser.parse(source).unwrap();
    assert!(tree.confidence().is_strict());
    assert_eq!(tree.source(), source);
    assert!(tree.repairs().unwrap().is_empty());
    let root = tree.root(0).unwrap();
    assert_eq!(root.kind(), b"document");
    assert_eq!(root.byte_range(), 0..source.len() as u32);
    assert!(root.parent().is_none());
    let object = root.named_children().next().unwrap();
    let pairs: Vec<_> = object.named_children().collect();
    assert_eq!(pairs.len(), 2);
    let key = pairs[0].child_by_field("key").unwrap();
    let value = pairs[0].child_by_field(b"value").unwrap();
    assert_eq!(key.field(), Some(b"key".as_slice()));
    assert_eq!(key.text(), Some(b"\"caf\xc3\xa9\"".as_slice()));
    assert_eq!(key.start_point(), Some(Point { row: 1, column: 2 }));
    assert_eq!(key.end_point(), Some(Point { row: 1, column: 9 }));
    assert_eq!(key.parent(), Some(pairs[0]));
    assert_eq!(value.kind(), b"array");
    let numbers: Vec<_> = value.named_children().collect();
    assert_eq!(numbers[0].next_named_sibling(), Some(numbers[1]));
    assert_eq!(numbers[1].previous_named_sibling(), Some(numbers[0]));
    assert_eq!(numbers[0].next_sibling().unwrap().kind(), b",");
    assert_eq!(numbers[1].previous_sibling().unwrap().kind(), b",");
    assert_eq!(tree.covering(numbers[0].byte_range()), Some(numbers[0]));
    assert!(numbers[0].depth() > object.depth());
    assert!(tree.root(99).is_none());
    assert!(value.child(99).is_none());
    assert!(
        tree.covering(std::ops::Range { start: 9, end: 4 })
            .is_none()
    );
    assert!(tree.point_at(source.len() as u32 + 1).is_none());
    assert!(tree.sexp(false).unwrap().starts_with(b"(document"));
    assert!(tree.sexp(true).unwrap().starts_with(b"(document"));
}

#[test]
fn strict_refusal_retains_evidence_and_partial_mode_keeps_repairs() {
    let bank = Bank::open(grammar()).unwrap();
    let parser = bank.parser(None).unwrap();
    let source = b"{\"a\": [1, ??? 2]}";
    let error = parser.parse(source).err().unwrap();
    assert_eq!(error.kind, ErrorKind::ParseRefused);
    assert!(!error.confidence.unwrap().is_strict());
    let tree = parser.parse_partial(source).unwrap();
    let confidence = tree.confidence();
    let repairs = tree.repairs().unwrap();
    assert!(!repairs.is_empty());
    assert_eq!(repairs.len() as u32, confidence.mends + confidence.supplied);
    assert_eq!(
        repairs
            .iter()
            .filter(|r| !r.supplied)
            .map(|r| r.span.end - r.span.start)
            .sum::<u32>(),
        confidence.skipped
    );
    for repair in repairs {
        assert!(matches!(repair.stop, Stop::Stray | Stop::Unexpected));
        if repair.supplied {
            assert_eq!(repair.span.start, repair.span.end);
            assert!(repair.word.is_some());
        } else {
            assert!(repair.span.start < repair.span.end);
            assert!(repair.word.is_none());
            assert!(repair.span.end as usize <= source.len());
        }
    }
    let truncated = parser.parse_partial(b"{").unwrap();
    assert!(!truncated.confidence().is_strict());
}

#[test]
fn nested_queries_enumerate_all_values_and_keep_capture_order() {
    let bank = Bank::open(grammar()).unwrap();
    let parser = bank.parser(None).unwrap();
    let source = Vec::from(b"{\"a\": [1, 2, 3]}".as_slice());
    let tree = parser.parse(&source).unwrap();
    drop(source);
    let notation = String::from("(object (pair value: (array (number) @value)))");
    let query = parser.query(&notation).unwrap();
    drop(notation);
    assert_eq!(query.pattern_count(), 1);
    assert_eq!(query.capture_count(), 1);
    assert_eq!(query.capture_name(0), Some(b"value".as_slice()));
    assert!(query.capture_name(99).is_none());
    let matches = query.matches(&tree, ForeignPolicy::Refuse).unwrap();
    let captures: Vec<_> = matches.iter().flat_map(|m| &m.captures).collect();
    assert_eq!(captures.len(), 3);
    assert!(matches.iter().all(|m| m.pattern == 0));
    assert!(captures.iter().all(|c| c.id == 0 && c.name == b"value"));
    assert_eq!(
        captures
            .iter()
            .map(|c| c.node.text().unwrap())
            .collect::<Vec<_>>(),
        vec![b"1".as_slice(), b"2".as_slice(), b"3".as_slice()]
    );
}

#[test]
fn text_predicates_empty_runs_and_foreign_policy_are_explicit() {
    let bank = Bank::open(grammar()).unwrap();
    let parser = bank.parser(None).unwrap();
    let tree = parser.parse(b"[1, 22, 3]").unwrap();
    let query = parser.query("((number) @n (#match? @n \"^2+$\"))").unwrap();
    let matches = query.matches(&tree, ForeignPolicy::Refuse).unwrap();
    assert_eq!(matches.len(), 1);
    assert_eq!(matches[0].captures[0].node.text(), Some(b"22".as_slice()));
    let no_match = parser.query("((number) @n (#eq? @n \"99\"))").unwrap();
    assert!(
        no_match
            .matches(&tree, ForeignPolicy::Refuse)
            .unwrap()
            .is_empty()
    );
    let foreign = parser
        .query("((number) @n (#consumer-filter? @n))")
        .unwrap();
    assert_eq!(
        foreign
            .matches(&tree, ForeignPolicy::Refuse)
            .err()
            .unwrap()
            .kind,
        ErrorKind::Format
    );
    assert_eq!(
        foreign.matches(&tree, ForeignPolicy::Admit).unwrap().len(),
        3
    );
    assert!(
        foreign
            .matches(&tree, ForeignPolicy::Deny)
            .unwrap()
            .is_empty()
    );
}

#[test]
fn mismatched_parsers_and_bad_queries_cannot_publish_findings() {
    let bank = Bank::open(grammar()).unwrap();
    let parser = bank.parser(None).unwrap();
    let other = bank.parser(None).unwrap();
    let tree = other.parse(b"1").unwrap();
    let query = parser.query("(number) @n").unwrap();
    assert_eq!(
        query
            .matches(&tree, ForeignPolicy::Refuse)
            .err()
            .unwrap()
            .kind,
        ErrorKind::Invalid
    );
    assert_eq!(
        parser.query("(missing_node) @n").err().unwrap().kind,
        ErrorKind::Format
    );
    assert_eq!(
        parser
            .query("((number) @n (#match? @n \"[\"))")
            .err()
            .unwrap()
            .kind,
        ErrorKind::Format
    );
    assert_eq!(
        bank.parser(Some("python")).err().unwrap().kind,
        ErrorKind::Language
    );
    assert_eq!(
        bank.parser(Some("json\0python")).err().unwrap().kind,
        ErrorKind::Invalid
    );
}

#[test]
fn repeated_parses_and_queries_do_not_invalidate_earlier_trees() {
    let bank = Bank::open(grammar()).unwrap();
    let parser = bank.parser(None).unwrap();
    let first = parser.parse(b"[1, 2]").unwrap();
    let query = parser.query("(number) @n").unwrap();
    let matches = query.matches(&first, ForeignPolicy::Refuse).unwrap();
    let second = parser.parse(b"{\"b\": 3}").unwrap();
    assert_eq!(second.source(), b"{\"b\": 3}");
    assert_eq!(matches[0].captures[0].node.text(), Some(b"1".as_slice()));
    assert_eq!(
        query.matches(&first, ForeignPolicy::Refuse).unwrap().len(),
        2
    );
}

#[test]
fn workers_can_create_independent_thread_local_banks_and_parsers() {
    let workers: Vec<_> = (0..4)
        .map(|_| {
            std::thread::spawn(|| {
                let bank = Bank::open(grammar()).unwrap();
                let parser = bank.parser(None).unwrap();
                let tree = parser.parse(b"[1, 2]").unwrap();
                let query = parser.query("(number) @n").unwrap();
                query.matches(&tree, ForeignPolicy::Refuse).unwrap().len()
            })
        })
        .collect();
    for worker in workers {
        assert_eq!(worker.join().unwrap(), 2);
    }
}

fn owned_parser() -> joints::Parser<'static> {
    Bank::open(grammar())
        .unwrap()
        .into_parser(Some("json"))
        .unwrap()
}

#[test]
fn owned_parser_survives_factory_return_and_reuses_after_refusal() {
    let parser = owned_parser();
    assert_eq!(parser.language(), b"json");
    let query = parser.query("(number) @n").unwrap();
    let first = parser.parse(b"[1, 2]").unwrap();
    let captures = query.matches(&first, ForeignPolicy::Refuse).unwrap();

    let refused = parser.parse(b"{\"a\": [1, ??? 2]}").err().unwrap();
    assert_eq!(refused.kind, ErrorKind::ParseRefused);
    assert!(!refused.confidence.unwrap().is_strict());

    let second = parser.parse(b"{\"b\": 3}").unwrap();
    assert!(second.confidence().is_strict());
    assert!(second.repairs().unwrap().is_empty());
    assert_eq!(second.source(), b"{\"b\": 3}");
    assert_eq!(captures[0].captures[0].node.text(), Some(b"1".as_slice()));
    assert_eq!(captures[1].captures[0].node.text(), Some(b"2".as_slice()));
    assert_eq!(
        query.matches(&second, ForeignPolicy::Refuse).unwrap()[0].captures[0]
            .node
            .text(),
        Some(b"3".as_slice())
    );
}

#[test]
fn owned_parser_preserves_language_validation() {
    assert_eq!(
        Bank::open(grammar())
            .unwrap()
            .into_parser(Some("python"))
            .err()
            .unwrap()
            .kind,
        ErrorKind::Language
    );
    assert_eq!(
        Bank::open(grammar())
            .unwrap()
            .into_parser(Some("json\0python"))
            .err()
            .unwrap()
            .kind,
        ErrorKind::Invalid
    );
    assert_eq!(
        Bank::open(grammar())
            .unwrap()
            .into_parser(None)
            .unwrap()
            .language(),
        b"json"
    );
}

#[test]
fn workers_reuse_independently_owned_parsers() {
    let workers: Vec<_> = (0..4)
        .map(|_| {
            std::thread::spawn(|| {
                let parser = owned_parser();
                for _ in 0..3 {
                    assert!(parser.parse(b"[1, 2]").unwrap().confidence().is_strict());
                    assert_eq!(
                        parser.parse(b"{").err().unwrap().kind,
                        ErrorKind::ParseRefused
                    );
                    assert!(
                        parser
                            .parse(b"{\"b\": 3}")
                            .unwrap()
                            .confidence()
                            .is_strict()
                    );
                }
            })
        })
        .collect();
    for worker in workers {
        worker.join().unwrap();
    }
}
