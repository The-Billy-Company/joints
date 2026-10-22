//! TS0.26.11 XML/CST measured at both sides of an atomic token boundary.
//! The exact upstream Make grammar also contains this lexical alias pattern.
use joints_engine::{CompiledGrammar, ForeignPolicy, Query, QueryError};
use std::{ops::Range, sync::Arc};

struct Case {
    source: &'static [u8],
    span: Range<usize>,
    children: [Range<usize>; 5],
}

const GRAMMAR: &[u8] = include_bytes!("fixtures/token-inner-aliases.json");

#[test]
fn aliases_within_atomic_tokens_are_inert_and_outer_aliases_and_fields_remain() {
    let grammar = CompiledGrammar::compile(GRAMMAR).unwrap();
    let restored = CompiledGrammar::from_artifact(&grammar.artifact().unwrap()).unwrap();
    let cases = [
        Case {
            source: b"abc:abc:z",
            span: 0..9,
            children: [0..3, 3..4, 4..7, 7..8, 8..9],
        },
        Case {
            source: b" abc : abc : z ",
            span: 1..15,
            children: [1..4, 5..6, 7..10, 11..12, 13..14],
        },
        Case {
            source: b"a\\\nc:abc:z",
            span: 0..10,
            children: [0..4, 4..5, 5..8, 8..9, 9..10],
        },
    ];
    for grammar in [grammar, restored] {
        for Case {
            source,
            span,
            children,
        } in &cases
        {
            let tree = grammar.session().parse(source).unwrap();
            assert!(tree.confidence().is_strict());
            let root = tree.root().unwrap();
            assert_eq!((root.name(), root.span().range()), ("doc", span.clone()));
            let actual: Vec<_> = root.children().collect();
            assert_eq!(actual.len(), 5);
            for (i, node) in actual.iter().enumerate() {
                assert_eq!(node.name(), ["chunk", ":", "outside", ":", "direct"][i]);
                assert_eq!(node.span().range(), children[i]);
                assert_eq!(node.is_named(), i % 2 == 0);
                assert_eq!(node.field(), (i == 0).then_some("atomic"));
                assert_eq!(
                    node.children().len(),
                    0,
                    "an inner lexical alias is not a node"
                );
            }
            let query = Query::compile(Arc::clone(&grammar), b"(chunk) @plain\n(outside) @renamed")
                .unwrap();
            let found = query.execute(&tree, ForeignPolicy::Refuse).unwrap();
            assert_eq!(found.len(), 2);
            assert_eq!(found[0].captures[0].node.index(), actual[0].index());
            assert_eq!(found[1].captures[0].node.index(), actual[2].index());
        }
        for name in [b"(inside_b)".as_slice(), b"(inside_z)"] {
            assert!(matches!(
                Query::compile(Arc::clone(&grammar), name),
                Err(QueryError::UnknownName { .. })
            ));
        }
    }
}

#[test]
fn lexical_aliases_do_not_allow_split_or_truncated_atomic_tokens() {
    let grammar = CompiledGrammar::compile(GRAMMAR).unwrap();
    for source in [b"ab c:abc:z".as_slice(), b"abc:ab:z", b"abc:abc:y"] {
        let tree = grammar.session().parse_partial(source).unwrap();
        assert!(!tree.confidence().accepted, "{source:?}");
        assert_eq!((tree.mends(), tree.supplied()), (0, 0));
        assert!(grammar.session().parse(source).is_err());
    }
}
