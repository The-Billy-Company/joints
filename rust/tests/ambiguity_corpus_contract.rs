//! Small real-grammar regressions captured from the independent pinned oracle.

#![forbid(unsafe_code)]

use joints_engine::{CompiledGrammar, Node, Recovery, Supply, TreeSnapshot};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{collections::BTreeSet, fs, path::Path};

const EVIDENCE: &str = include_str!("../../test/migration/ambiguity/real-cases.json");

fn digest(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .fold(String::new(), |mut text, byte| {
            use std::fmt::Write as _;
            write!(text, "{byte:02x}").expect("writing to a String cannot fail");
            text
        })
}

fn image(node: Node<'_>) -> Value {
    json!({
        "name": node.name(),
        "named": node.is_named(),
        "field": node.field(),
        "start": node.span().start(),
        "end": node.span().end(),
        "kids": node.children().map(image).collect::<Vec<_>>(),
    })
}

fn tree_image(tree: &TreeSnapshot) -> Value {
    Value::Array(tree.roots().map(image).collect())
}

fn pinned_grammar(pin: &Value) -> Vec<u8> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap();
    let path = root.join(pin["path"].as_str().unwrap());
    let bytes = fs::read(&path).unwrap_or_else(|error| {
        panic!(
            "fetch the explicitly pinned working grammar before this gate: {}: {error}",
            path.display()
        )
    });
    assert_eq!(
        digest(&bytes),
        pin["sha256"].as_str().unwrap(),
        "pinned grammar changed: {}",
        path.display()
    );
    assert!(
        pin["recipe"].is_null(),
        "this oracle uses the original grammar"
    );
    bytes
}

#[test]
#[ignore = "explicit pinned PHP/Swift grammars and independent complete CST oracle"]
fn real_grammar_ambiguities_preserve_all_independent_trees() {
    let evidence: Value = serde_json::from_str(EVIDENCE).unwrap();
    assert_eq!(evidence["schema"], 1);
    assert_eq!(evidence["oracle"]["version"], "tree-sitter 0.26.11");
    assert_eq!(evidence["capture"]["input_bracket_stable"], true);
    let cases = evidence["cases"].as_array().unwrap();
    assert_eq!(cases.len(), 14, "a reduced oracle roster is no proof");
    let ids: BTreeSet<_> = cases
        .iter()
        .map(|case| case["id"].as_str().unwrap())
        .collect();
    assert_eq!(ids.len(), cases.len(), "duplicate case IDs");
    assert_eq!(
        ids,
        BTreeSet::from([
            "php/class-primitive",
            "php/nullable-int",
            "php/primitive-int",
            "php/primitive-string",
            "php/return-int",
            "php/true-union",
            "swift/call-navigation",
            "swift/function-equality",
            "swift/nested-equality",
            "swift/one-navigation",
            "swift/return-equality",
            "swift/triple-navigation",
            "swift/two-navigation",
            "swift/typed-let",
        ])
    );
    let pins = evidence["grammars"].as_object().unwrap();
    assert_eq!(
        pins.keys().map(String::as_str).collect::<BTreeSet<_>>(),
        BTreeSet::from(["php", "swift"])
    );
    assert_eq!(
        cases
            .iter()
            .map(|case| case["language"].as_str().unwrap())
            .collect::<BTreeSet<_>>(),
        BTreeSet::from(["php", "swift"])
    );

    let mut executed = 0;
    let mut results = Vec::new();
    let mut failures = Vec::new();
    for (language, expected_count) in [("php", 6), ("swift", 8)] {
        let selected: Vec<_> = cases
            .iter()
            .filter(|case| case["language"] == language)
            .collect();
        assert_eq!(selected.len(), expected_count);
        let grammar = CompiledGrammar::compile(&pinned_grammar(&pins[language])).unwrap();
        for (recovery, supply) in [
            (Recovery::None, Supply::Disabled),
            (Recovery::Fell, Supply::UniqueLiteral),
        ] {
            let mut session = grammar.session();
            session.set_recovery(recovery);
            session.set_supply(supply);
            for case in &selected {
                let source = case["source"].as_str().unwrap().as_bytes();
                assert_eq!(digest(source), case["source_sha256"].as_str().unwrap());
                assert_eq!(case["oracle"]["strict"], true);
                for face in ["xml", "cst", "query-0"] {
                    let raw = &case["raw"][face];
                    assert_eq!(raw["exit"], 0);
                    for stream in ["stdout", "stderr"] {
                        assert_eq!(
                            digest(raw[stream].as_str().unwrap().as_bytes()),
                            raw[format!("{stream}_sha256")].as_str().unwrap()
                        );
                    }
                }
                let query = &case["raw"]["query-0"];
                assert_eq!(
                    digest(query["source"].as_str().unwrap().as_bytes()),
                    query["source_sha256"].as_str().unwrap()
                );
                executed += 1;
                let mut result = json!({
                    "case": case["id"],
                    "policy": format!("{recovery:?}/{supply:?}"),
                });
                match session.parse(source) {
                    Err(error) => {
                        result["error"] = json!(error.to_string());
                        failures.push(result.clone());
                    }
                    Ok(tree) => {
                        let actual = tree_image(&tree);
                        let strict = tree.confidence().is_strict();
                        let expected_nodes =
                            usize::try_from(case["oracle"]["nodes"].as_u64().unwrap())
                                .expect("fixture count fits usize");
                        let nodes = tree.survey().walked;
                        let equal = actual == case["oracle"]["tree"];
                        result["strict"] = json!(strict);
                        result["nodes"] = json!(nodes);
                        result["expected_nodes"] = json!(expected_nodes);
                        result["tree_equal"] = json!(equal);
                        if !strict || nodes != expected_nodes || !equal {
                            result["actual_tree"] = actual;
                            failures.push(result.clone());
                        }
                    }
                }
                results.push(result);
            }
        }
    }
    assert_eq!(executed, 28, "every case must run under both policies");
    println!("AMBIGUITY_CASE_RESULTS {}", json!(results));
    assert!(
        failures.is_empty(),
        "{} of {executed} complete independent tree comparisons failed:\n{}",
        failures.len(),
        serde_json::to_string_pretty(&failures).unwrap()
    );
}
