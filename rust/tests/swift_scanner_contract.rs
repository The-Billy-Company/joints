//! Explicit full-profile witness; fetch the pinned working grammar before running.

use joints_engine::{CompiledGrammar, Node, Recovery, Supply, TreeSnapshot};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{fs, path::Path};

const EVIDENCE: &str =
    include_str!("../../test/migration/regulator/evidence/swift-directive-protocol.json");

fn digest(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect::<String>()
}

fn image(node: Node<'_>) -> Value {
    let mut value = json!({
        "name": node.name(),
        "named": node.is_named(),
        "start": node.span().start(),
        "end": node.span().end(),
        "kids": node.children().map(image).collect::<Vec<_>>(),
    });
    if let Some(field) = node.field() {
        value["field"] = json!(field);
    }
    value
}

fn tree_image(tree: &TreeSnapshot) -> Value {
    Value::Array(tree.roots().map(image).collect())
}

fn prepared_profile(evidence: &Value) -> Vec<u8> {
    let profile = &evidence["profile"];
    let base = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .join("upstream/grammars/swift.json");
    let bytes = fs::read(&base).unwrap_or_else(|error| {
        panic!(
            "fetch the explicitly pinned Swift working grammar before this gate: {}: {error}",
            base.display()
        )
    });
    assert_eq!(digest(&bytes), profile["base_sha256"].as_str().unwrap());
    let mut grammar: Value = serde_json::from_slice(&bytes).unwrap();
    let recipe = &profile["recipe"];
    grammar["rules"]
        .as_object_mut()
        .unwrap()
        .extend(recipe["rules"].as_object().unwrap().clone());
    grammar["conflicts"]
        .as_array_mut()
        .unwrap()
        .extend(recipe["added_conflicts"].as_array().unwrap().clone());
    if let Some(externals) = recipe.get("added_externals") {
        grammar["externals"]
            .as_array_mut()
            .unwrap()
            .extend(externals.as_array().unwrap().clone());
    }
    if let Some(extras) = recipe.get("extras") {
        grammar["extras"] = extras.clone();
    }
    let prepared = serde_json::to_vec(&grammar).unwrap();
    assert_eq!(
        digest(&prepared),
        profile["derived_semantic_sha256"].as_str().unwrap(),
        "authored profile values changed"
    );
    prepared
}

#[test]
#[ignore = "explicit pinned Swift profile and independent external-scanner oracle"]
fn directives_hashes_and_raw_strings_preserve_all_independent_positive_trees() {
    let evidence: Value = serde_json::from_str(EVIDENCE).unwrap();
    let cases = evidence["cases"].as_array().unwrap();
    assert_eq!(cases.len(), 19);
    let positive: Vec<_> = cases
        .iter()
        .filter(|case| case["oracle"]["strict"] == true)
        .collect();
    assert_eq!(positive.len(), 14, "an empty or reduced oracle is no proof");
    let mut names: Vec<_> = positive
        .iter()
        .map(|case| case["case"].as_str().unwrap())
        .collect();
    names.sort_unstable();
    assert_eq!(
        names,
        [
            "consumer-conditional",
            "elseif",
            "hash-literals",
            "macro-call",
            "nested",
            "ordinary-string",
            "prefix-elseif",
            "prefix-no-boundary",
            "raw-multiline",
            "raw-string",
            "raw-within-conditional",
            "two-hash-raw",
            "unmatched-else",
            "unterminated-if",
        ]
    );
    let grammar = CompiledGrammar::compile(&prepared_profile(&evidence)).unwrap();
    for (recovery, supply) in [
        (Recovery::None, Supply::Disabled),
        (Recovery::Fell, Supply::UniqueLiteral),
    ] {
        let mut session = grammar.session();
        session.set_recovery(recovery);
        session.set_supply(supply);
        for case in &positive {
            let source = case["source"].as_str().unwrap().as_bytes();
            assert_eq!(digest(source), case["source_sha256"].as_str().unwrap());
            let tree = session.parse(source).unwrap();
            assert!(tree.confidence().is_strict(), "{}", case["case"]);
            assert_eq!(
                tree_image(&tree),
                case["oracle"]["tree"],
                "{} under {recovery:?}/{supply:?}",
                case["case"]
            );
        }

        for name in [
            "missing-if-condition",
            "incomplete-elseif",
            "incomplete-hash",
            "unterminated-raw",
        ] {
            let case = cases.iter().find(|case| case["case"] == name).unwrap();
            assert_eq!(case["oracle"]["strict"], false);
            let source = case["source"].as_str().unwrap().as_bytes();
            assert_eq!(digest(source), case["source_sha256"].as_str().unwrap());
            if let Ok(tree) = session.parse(source) {
                assert!(
                    !tree.confidence().is_strict(),
                    "{name} became a strict success"
                );
            }
        }

        // The grammar admits named line/block-comment extras and named
        // directives. Swift's compiler accepts this exact source in either
        // FLAG branch; the pinned TS scanner instead wraps #if in ERROR.
        // Assert the grammar's direct structure, never its recovered TS tree.
        let comments = cases
            .iter()
            .find(|case| case["case"] == "comments")
            .unwrap();
        assert_eq!(comments["oracle"]["strict"], false);
        let source = b"// leading\n#if FLAG\n/* branch */ let value = 1\n#endif\n";
        assert_eq!(comments["source"].as_str().unwrap().as_bytes(), source);
        let tree = session.parse(source).unwrap();
        assert!(tree.confidence().is_strict());
        let root = tree.root().unwrap();
        assert_eq!(root.name(), "source_file");
        let children: Vec<_> = root.children().collect();
        assert_eq!(
            children.iter().map(|node| node.name()).collect::<Vec<_>>(),
            [
                "comment",
                "directive",
                "multiline_comment",
                "property_declaration",
                "directive"
            ]
        );
        assert!(children[0].is_extra());
        assert!(children[2].is_extra());
        assert_eq!(children[0].text(), b"// leading");
        assert_eq!(children[1].text(), b"#if FLAG");
        assert_eq!(children[2].text(), b"/* branch */");
        assert_eq!(children[4].text(), b"#endif");
    }
}
