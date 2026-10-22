//! Static numeric precedence resolves before dynamic ranking or declarations.
use std::collections::BTreeSet;

use joints_engine::{CompiledGrammar, ConflictClass, ForeignPolicy, Query, TreeSnapshot};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};

fn ledger(tree: &TreeSnapshot) -> Value {
    let mut pending: Vec<_> = tree.roots().rev().collect();
    let mut rows = Vec::new();
    while let Some(node) = pending.pop() {
        rows.push(json!({
            "name": node.name(), "named": node.is_named(), "field": node.field(),
            "start": node.span().start(), "end": node.span().end(),
            "children": node.children().len(),
        }));
        pending.extend(node.children().rev());
    }
    json!(rows)
}

#[test]
fn implicit_zero_and_explicit_static_ranks_match_independent_full_trees() {
    let fixture: Value =
        serde_json::from_slice(include_bytes!("fixtures/static-precedence.json")).unwrap();
    assert_eq!(fixture["oracle"]["version"], "0.26.11");
    assert_eq!(
        fixture["oracle"]["sha256"],
        "74694dbaff285e5c13b8d3fec3e77e21a9314e98d67e4bca651594d2f859dcc5"
    );
    let cases = fixture["cases"].as_array().unwrap();
    assert_eq!(cases.len(), 9);
    assert_eq!(
        cases
            .iter()
            .map(|c| c["name"].as_str().unwrap())
            .collect::<BTreeSet<_>>()
            .len(),
        9
    );
    let mut names = BTreeSet::new();
    let (mut positives, mut expected_nodes) = (0, 0);
    for case in cases {
        let name = case["name"].as_str().unwrap();
        assert_eq!(case["generation"]["exit"], 0);
        let grammar =
            CompiledGrammar::compile(&serde_json::to_vec(&case["grammar"]).unwrap()).unwrap();
        let bytes = grammar.artifact().unwrap();
        assert_eq!(grammar.artifact().unwrap(), bytes);
        let loaded = CompiledGrammar::from_artifact(&bytes).unwrap();
        for sample in case["sources"].as_array().unwrap() {
            let sample_name = sample["name"].as_str().unwrap();
            assert!(names.insert(sample_name));
            let source = sample["source"].as_str().unwrap().as_bytes();
            assert_eq!(
                Sha256::digest(source)
                    .iter()
                    .map(|byte| format!("{byte:02x}"))
                    .collect::<String>(),
                sample["source_sha256"].as_str().unwrap()
            );
            let accepted = sample["accepted"].as_bool().unwrap();
            if accepted {
                positives += 1;
                expected_nodes += sample["expected"].as_array().unwrap().len();
            }
            for (route, grammar) in [("JSON", &grammar), ("artifact", &loaded)] {
                let mut session = grammar.session();
                let tree = session.parse_partial(source).unwrap();
                assert_eq!(
                    tree.confidence().is_strict(),
                    accepted,
                    "{sample_name}/{route}"
                );
                if accepted {
                    assert!(tree.repairs().is_empty());
                    assert_eq!(ledger(&tree), sample["expected"], "{sample_name}/{route}");
                    assert!(
                        !session
                            .product(&mut grammar.effect_store())
                            .unwrap()
                            .is_zero()
                    );
                    if name == "recipe" {
                        let query =
                            Query::compile(grammar.clone(), b"(parameter name: (param) @p)")
                                .unwrap();
                        let found = query.execute(&tree, ForeignPolicy::Refuse).unwrap();
                        assert_eq!(found.len(), 1);
                        assert_eq!(found[0].captures[0].node.text(), b"a");
                        assert!(found[0].captures[0].node.is_named());
                        assert_eq!(found[0].captures[0].node.field(), Some("name"));
                    }
                }
            }
        }
        if name == "equal_declared" {
            assert!(
                grammar
                    .conflict_diagnostics()
                    .iter()
                    .any(|c| { c.class == ConflictClass::Declared && c.actions.len() > 1 })
            );
        }
    }
    assert_eq!(names.len(), 20);
    assert_eq!(positives, 12);
    assert_eq!(expected_nodes, 83);
}

#[test]
fn equal_precedence_authored_sides_keep_the_existing_secondary_reading() {
    let grammar = CompiledGrammar::compile(br#"{"name":"sided","rules":{
      "doc":{"type":"CHOICE","members":[
        {"type":"SEQ","members":[{"type":"SYMBOL","name":"A"},{"type":"STRING","value":"b"}]},
        {"type":"SEQ","members":[{"type":"SYMBOL","name":"B"},{"type":"STRING","value":"c"}]}]},
      "A":{"type":"PREC_LEFT","value":0,"content":{"type":"STRING","value":"a"}},
      "B":{"type":"SEQ","members":[{"type":"STRING","value":"a"},{"type":"STRING","value":"b"}]}}}"#).unwrap();
    assert!(
        grammar
            .conflict_diagnostics()
            .iter()
            .any(|c| { c.class == ConflictClass::Sided && c.actions.len() > 1 })
    );
    // This pins native secondary-reading availability. It does not claim that
    // upstream preserves an action it resolves by associativity.
    for (source, child) in [(b"ab".as_slice(), "A"), (b"abc".as_slice(), "B")] {
        let mut session = grammar.session();
        let tree = session.parse(source).unwrap();
        assert_eq!(
            tree.root().unwrap().children().next().unwrap().name(),
            child
        );
    }
}
