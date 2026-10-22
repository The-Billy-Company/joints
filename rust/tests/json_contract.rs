//! Compare the native engine with frozen outputs from the pinned Zig executable.
#![forbid(unsafe_code)]

use std::{fs, path::PathBuf, sync::Arc};

use joints_engine::{
    CompiledGrammar, Error, Node, ParseLimits, ParseSession, Point, Resource, Stop, TreeSnapshot,
};
use serde_json::{Value, json};

fn json_grammar() -> Arc<CompiledGrammar> {
    CompiledGrammar::compile(include_bytes!("../../test/grammar/json.json")).unwrap()
}

fn shape(node: Node<'_>) -> Value {
    let mut value = json!({"name":node.name(), "named":node.is_named(),
        "start":node.span().start(), "end":node.span().end(),
        "kids":node.children().map(shape).collect::<Vec<_>>()});
    if let Some(field) = node.field() {
        value["field"] = json!(field);
    }
    value
}

fn stopped(tree: &TreeSnapshot) -> Value {
    match tree.stop() {
        Stop::Accepted => json!({"kind":"accepted"}),
        Stop::Truncated => json!({"kind":"truncated"}),
        Stop::Stray { at } => json!({"kind":"stray", "at":at}),
        Stop::Unexpected { at, .. } => {
            json!({"kind":"unexpected", "at":at, "symbol":tree.stop_symbol().unwrap()})
        }
    }
}

#[test]
fn every_frozen_no_recovery_case_matches_the_reference() {
    let bundle = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../test/migration/reference");
    let manifest: Value =
        serde_json::from_slice(&fs::read(bundle.join("manifest.json")).unwrap()).unwrap();
    let cases: Vec<_> = manifest["cases"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|case| {
            case["id"].as_str().unwrap().ends_with("-no-recovery") || case["id"] == "corpus-json"
        })
        .collect();
    assert_eq!(cases.len(), 13, "missing or changed reference roster");
    let grammar = json_grammar();
    let mut parser = grammar.session();
    for case in cases {
        let id = case["id"].as_str().unwrap();
        let source = fs::read(bundle.join(case["argv"][2].as_str().unwrap())).unwrap();
        let mut expected: Value =
            serde_json::from_slice(&fs::read(bundle.join(format!("outputs/{id}.json"))).unwrap())
                .unwrap();
        expected["stop"].as_object_mut().unwrap().remove("state");
        let tree = parser.parse_partial(&source).unwrap();
        assert_eq!(
            tree.roots().map(shape).collect::<Vec<_>>(),
            *expected["tree"].as_array().unwrap(),
            "{id}: syntax"
        );
        assert_eq!(stopped(&tree), expected["stop"], "{id}: stop");
        assert_eq!(
            tree.confidence().is_strict(),
            case["strict"].as_bool().unwrap(),
            "{id}: strict confidence"
        );
        assert_eq!(
            tree.survey().is_sound(),
            expected["survey"]["sound"].as_bool().unwrap(),
            "{id}: structure"
        );
        assert_eq!(
            tree.survey().walked,
            usize::try_from(expected["survey"]["walked"].as_u64().unwrap())
                .expect("fixture count fits usize"),
            "{id}: surveyed nodes"
        );
        assert_eq!(tree.source(), source, "{id}: original bytes");
        let strict = parser.parse(&source);
        assert_eq!(
            strict.is_ok(),
            tree.confidence().is_strict(),
            "{id}: strict API"
        );
        if let Err(error) = strict {
            assert_eq!(error.partial_tree().unwrap().source(), source);
        }
    }
}

#[test]
fn snapshots_and_borrowed_nodes_retain_source_grammar_fields_and_positions() {
    let grammar = json_grammar();
    let mut parser = grammar.session();
    let old = parser.parse(b"\n{\"caf\xc3\xa9\":42}\n").unwrap();
    let later = parser.parse(b"true").unwrap();
    drop(parser);
    drop(grammar);
    let object = old
        .root()
        .unwrap()
        .children()
        .find(|n| n.name() == "object")
        .unwrap();
    let pair = object.children().find(|n| n.name() == "pair").unwrap();
    let key = pair.child_by_field("key").unwrap();
    let value = pair.child_by_field("value").unwrap();
    assert_eq!(key.text(), b"\"caf\xc3\xa9\"");
    assert_eq!(value.text(), b"42");
    assert_eq!(value.start_point(), Point { row: 1, column: 9 });
    assert_eq!(value.end_point(), Point { row: 1, column: 11 });
    assert_eq!(value.parent().unwrap().name(), "pair");
    assert_eq!(
        later.root().unwrap().children().next().unwrap().name(),
        "true"
    );
}

#[test]
fn one_grammar_supports_independent_workers_and_reused_sessions() {
    fn shared<T: Send + Sync>() {}
    shared::<CompiledGrammar>();
    shared::<TreeSnapshot>();
    let grammar = json_grammar();
    let sources: Vec<_> = (0..80)
        .map(|n| format!("{{\"worker\":{n},\"items\":[true,null]}}\n").into_bytes())
        .collect();
    let mut sequential = grammar.session();
    let expected: Vec<_> = sources
        .iter()
        .map(|s| shape(sequential.parse(s).unwrap().root().unwrap()))
        .collect();
    let actual = std::thread::scope(|scope| {
        let handles: Vec<_> = sources
            .chunks(10)
            .map(|chunk| {
                let grammar = Arc::clone(&grammar);
                scope.spawn(move || {
                    let mut session = grammar.session();
                    chunk
                        .iter()
                        .map(|s| shape(session.parse(s).unwrap().root().unwrap()))
                        .collect::<Vec<_>>()
                })
            })
            .collect();
        handles
            .into_iter()
            .flat_map(|h| h.join().unwrap())
            .collect::<Vec<_>>()
    });
    assert_eq!(actual, expected);
}

#[test]
fn work_memory_and_source_limits_are_operational_errors_and_sessions_recover() {
    let grammar = json_grammar();
    for (limits, expected) in [
        (
            ParseLimits {
                steps: 0,
                ..ParseLimits::default()
            },
            Resource::Work,
        ),
        (
            ParseLimits {
                stack: 0,
                ..ParseLimits::default()
            },
            Resource::Stack,
        ),
        (
            ParseLimits {
                nodes: 0,
                ..ParseLimits::default()
            },
            Resource::Nodes,
        ),
    ] {
        let mut parser = ParseSession::with_limits(Arc::clone(&grammar), limits);
        assert!(
            matches!(parser.parse(b"1"), Err(Error::LimitExceeded(resource)) if resource == expected)
        );
        assert!(parser.product(&mut grammar.effect_store()).is_err());
    }
    let mut parser = ParseSession::with_limits(
        Arc::clone(&grammar),
        ParseLimits {
            source_bytes: 1,
            ..ParseLimits::default()
        },
    );
    assert!(matches!(
        parser.parse(b"42"),
        Err(Error::SourceTooLarge { .. })
    ));
    assert!(parser.product(&mut grammar.effect_store()).is_err());
    assert!(parser.parse(b"1").unwrap().confidence().is_strict());
}

#[test]
fn actual_parser_moves_form_a_grounded_nonzero_product() {
    let grammar = json_grammar();
    let mut parser = grammar.session();
    let mut effects = grammar.effect_store();
    assert!(parser.product(&mut effects).is_err());
    parser.parse(b"{\"x\":[1,2,{\"y\":null}]}").unwrap();
    let product = parser.product(&mut effects).unwrap();
    assert!(!product.is_zero());
    assert!(effects.grounded(product).unwrap());
    let other = json_grammar();
    assert!(parser.product(&mut other.effect_store()).is_err());
}
