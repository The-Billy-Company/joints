#![forbid(unsafe_code)]

use joints_engine::{ByteSpan, CompiledGrammar, Document};
use serde_json::json;
use std::{sync::Arc, time::Instant};

#[test]
fn copying_materialization_and_retained_versions_are_accounted_separately() {
    let grammar = CompiledGrammar::compile(include_bytes!("../../test/grammar/json.json")).unwrap();
    let source = format!("[{}]", vec!["1"; 256].join(","));
    let mut document = Document::new(Arc::clone(&grammar), source.as_bytes()).unwrap();
    let mut retained = vec![];
    let mut records = vec![];
    for position in ["start", "middle", "end"] {
        let near = match position {
            "start" => 0,
            "middle" => document.source().len() / 2,
            _ => document.source().len() - 2,
        };
        let at = (near..document.source().len())
            .find(|&i| document.source()[i].is_ascii_digit())
            .unwrap();
        retained.push(Arc::clone(document.snapshot()));
        let begin = Instant::now();
        document
            .edit(ByteSpan::new(at, at + 1).unwrap(), b"22")
            .unwrap();
        let elapsed = begin.elapsed();
        let cost = document.cost();
        let mut cold = grammar.session();
        let tree = cold.parse(document.source()).unwrap();
        let mut store = grammar.effect_store();
        let product = cold.product(&mut store).unwrap();
        assert_eq!(
            document.product().unwrap(),
            store.describe(product).unwrap()
        );
        assert_eq!(cost.text_bytes_copied, 2 * document.source().len());
        assert_eq!(cost.snapshot_source_bytes, document.source().len());
        assert_eq!(cost.materialized_nodes, tree.survey().walked);
        for old in &retained {
            assert!(old.confidence().is_strict());
            assert_eq!(old.root().unwrap().text(), old.source());
        }
        let old_source_bytes: usize = retained.iter().map(|t| t.source().len()).sum();
        let old_payload_bytes: usize = retained.iter().map(|t| t.storage_bytes()).sum();
        assert!(old_payload_bytes > old_source_bytes);
        records.push(json!({
            "position": position,
            "elapsed_ns": elapsed.as_nanos(),
            "reuse": format!("{:?}", cost.reuse),
            "copied_source_bytes": cost.text_bytes_copied,
            "snapshot_source_bytes": cost.snapshot_source_bytes,
            "materialized_nodes": cost.materialized_nodes,
            "parser_work": cost.parser_work,
            "lexical_work": cost.lexical_work,
            "sequence_leaves": cost.sequence_leaves,
            "sequence_leaves_kept": cost.sequence_leaves_kept,
            "sequence_compositions": cost.sequence_compositions,
            "sequence_nodes_created": cost.sequence_nodes_created,
            "retained_old_versions": retained.len(),
            "retained_old_source_bytes": old_source_bytes,
            "retained_old_payload_bytes": old_payload_bytes,
            "current_payload_bytes": document.snapshot().storage_bytes(),
        }));
    }
    println!(
        "DOCUMENT_COST_REPORT={}",
        serde_json::to_string(&records).unwrap()
    );
}
