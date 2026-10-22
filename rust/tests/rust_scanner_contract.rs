#![forbid(unsafe_code)]

use joints_engine::{CompileOptions, CompiledGrammar, ScannerBinding};
use serde_json::json;

const COHORT: [&str; 11] = [
    "string_content",
    "string_close",
    "_raw_string_literal_start",
    "raw_string_literal_content",
    "_raw_string_literal_end",
    "float_literal",
    "_outer_block_doc_comment_marker",
    "_inner_block_doc_comment_marker",
    "_block_comment_content",
    "_line_doc_content",
    "_error_sentinel",
];
fn grammar() -> Vec<u8> {
    serde_json::to_vec(&json!({"name":"protocol_not_title","rules":{
        "doc":{"type":"REPEAT1","content":{"type":"SYMBOL","name":"float_literal"}},
        "line_comment":{"type":"SEQ","members":[{"type":"STRING","value":"//"},{"type":"CHOICE","members":[{"type":"STRING","value":"/"},{"type":"STRING","value":"!"}]},{"type":"FIELD","name":"doc","content":{"type":"ALIAS","named":true,"value":"doc_comment","content":{"type":"SYMBOL","name":"_line_doc_content"}}}]}},
        "externals":COHORT.iter().map(|name|json!({"type":"SYMBOL","name":name})).collect::<Vec<_>>(),
        "extras":[{"type":"PATTERN","value":"[ \\t\\r\\n]+"},{"type":"SYMBOL","name":"line_comment"}]})).unwrap()
}
#[test]
fn numeric_and_doc_tokens_execute_through_actual_parser_admissions_and_fields() {
    let grammar = CompiledGrammar::compile(&grammar()).unwrap();
    assert_eq!(grammar.unsupported_externals().count(), 0);
    let sentinel = grammar
        .external_bindings()
        .find(|(id, _)| grammar.symbol_name(*id) == Some("_error_sentinel"))
        .unwrap();
    assert_eq!(sentinel.1, ScannerBinding::Control);
    for source in ["/// αβ\n1.25e-3_f64 3.", "//! inner\n2E+1f32"] {
        let tree = grammar.session().parse(source.as_bytes()).unwrap();
        assert!(tree.confidence().is_strict());
        let nodes: Vec<_> = tree.root().unwrap().children().collect();
        let comment = nodes.iter().find(|n| n.name() == "line_comment").unwrap();
        assert!(comment.text().ends_with(b"\n"));
        let doc = comment.child_by_field("doc").unwrap();
        assert_eq!(doc.name(), "doc_comment");
        assert!(doc.text().ends_with(b"\n"));
        let floats: Vec<_> = nodes
            .iter()
            .filter(|n| n.name() == "float_literal")
            .map(|n| n.text())
            .collect();
        assert_eq!(
            floats,
            if source.starts_with("///") {
                vec![b"1.25e-3_f64".as_slice(), b"3."]
            } else {
                vec![b"2E+1f32".as_slice()]
            }
        );
    }
    assert!(grammar.session().parse(b"1.max").is_err());
}
#[test]
fn explicit_book_stays_exclusive_for_its_claimed_float_terminal() {
    let book=br#"{"cohort":["float_literal"],"probes":{"literal":"custom"},"rules":[{"phase":"bounded","when":[["wanted","float_literal"],["probe","literal"]],"then":[["emit","float_literal"]]}]}"#;
    let grammar =
        CompiledGrammar::compile_with_customary(&grammar(), book, CompileOptions::default())
            .unwrap();
    assert!(
        grammar
            .session()
            .parse(b"custom")
            .unwrap()
            .confidence()
            .is_strict()
    );
    assert!(
        grammar.session().parse(b"1.25").is_err(),
        "a declined custom book must not fall through to native Rust floats"
    );
}
#[test]
#[ignore = "explicit pinned Rust scanner consumer-source and source-boundary gate"]
fn pinned_rust_floats_docs_ranges_and_incomplete_sources() {
    let grammar =
        CompiledGrammar::compile(include_bytes!("../../upstream/grammars/rust.json")).unwrap();
    for source in [
        "/// A documented value.\npub fn value() -> f64 { 1.25e-3_f64 }\n",
        "fn range() { let _ = 1.0..2.0; let _ = 3.; }\n",
        "//! Crate documentation.\nfn value() -> f32 { 2E+1f32 }\n",
        "/// αβ\nfn f() { let _ = r#\"raw\"#; let _ = \"text\"; }\n",
    ] {
        let tree = grammar.session().parse(source.as_bytes()).unwrap();
        assert!(tree.confidence().is_strict(), "{source}");
        assert_eq!(tree.root().unwrap().text(), source.as_bytes());
    }
    for source in [
        "fn value() {",
        "fn value() { let _ = 1.0e+; }",
        "/// documentation\npub fn",
    ] {
        assert!(
            grammar.session().parse(source.as_bytes()).is_err(),
            "{source}"
        );
    }
}
