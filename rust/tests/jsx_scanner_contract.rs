use joints_engine::{ByteSpan, CompileOptions, CompiledGrammar, Document, Node, ScannerBinding};
use serde_json::json;

const COHORT: [&str; 10] = [
    "_automatic_semicolon",
    "_template_chars",
    "_ternary_qmark",
    "html_comment",
    "||",
    "escape_sequence",
    "regex_pattern",
    "jsx_text",
    "_function_signature_automatic_semicolon",
    "__error_recovery",
];

fn grammar() -> Vec<u8> {
    let externals = COHORT
        .iter()
        .map(|name| {
            if *name == "||" {
                json!({"type":"STRING","value":name})
            } else {
                json!({"type":"SYMBOL","name":name})
            }
        })
        .collect::<Vec<_>>();
    serde_json::to_vec(&json!({
        "name":"protocol_without_a_language_title",
        "rules":{"doc":{"type":"SEQ","members":[
            {"type":"STRING","value":"<"},
            {"type":"FIELD","name":"body","content":{"type":"SYMBOL","name":"jsx_text"}},
            {"type":"STRING","value":">"}
        ]}},
        "externals":externals,"extras":[]
    }))
    .unwrap()
}

#[test]
fn jsx_text_has_exact_spans_fields_and_no_synthetic_empty_token() {
    let grammar = CompiledGrammar::compile(&grammar()).unwrap();
    let binding = grammar
        .external_bindings()
        .find(|(id, _)| grammar.symbol_name(*id) == Some("jsx_text"))
        .unwrap();
    assert_eq!(binding.1, ScannerBinding::Hand);
    for source in ["<alpha>", "<é中😀>", "<\n\u{2003}>", "<\r>"] {
        let tree = grammar.session().parse(source.as_bytes()).unwrap();
        assert!(tree.confidence().is_strict());
        let body = tree.root().unwrap().child_by_field("body").unwrap();
        assert_eq!(body.name(), "jsx_text");
        assert_eq!(body.span().range(), 1..source.len() - 1);
        assert_eq!(body.text(), &source.as_bytes()[1..source.len() - 1]);
    }
    for source in [b"<>".as_slice(), b"<{>", b"<&amp;>", b"<\n \t>", b"<text"] {
        assert!(grammar.session().parse(source).is_err(), "{source:?}");
    }
    let source = [b'<', b'\n', 0xff, 0xc2, b'>'];
    let tree = grammar.session().parse(&source).unwrap();
    assert_eq!(
        tree.root().unwrap().child_by_field("body").unwrap().text(),
        &source[1..4]
    );
}

#[test]
fn a_claimed_custom_jsx_terminal_never_falls_through_to_native_text() {
    let book = br#"{"cohort":["jsx_text"],"probes":{"literal":"written"},"rules":[{"phase":"bounded","when":[["wanted","jsx_text"],["probe","literal"]],"then":[["emit","jsx_text"]]}]}"#;
    let grammar =
        CompiledGrammar::compile_with_customary(&grammar(), book, CompileOptions::default())
            .unwrap();
    assert!(grammar.session().parse(b"<written>").is_ok());
    assert!(grammar.session().parse(b"<ordinary>").is_err());
    let binding = grammar
        .external_bindings()
        .find(|(id, _)| grammar.symbol_name(*id) == Some("jsx_text"))
        .unwrap();
    assert_eq!(binding.1, ScannerBinding::Customary);
}

#[test]
fn document_edits_revalidate_stateless_text_and_keep_old_snapshot_bytes() {
    let grammar = CompiledGrammar::compile(&grammar()).unwrap();
    let mut document = Document::new(grammar.clone(), b"<alpha>").unwrap();
    let old = document.snapshot().clone();
    for replacement in [b"bravo".as_slice(), "éé".as_bytes(), b"after"] {
        let end = document.source().len() - 1;
        document
            .edit(ByteSpan::new(1, end).unwrap(), replacement)
            .unwrap();
        let cold = grammar.session().parse(document.source()).unwrap();
        let warm = document.snapshot();
        assert_eq!(warm.confidence(), cold.confidence());
        assert_eq!(
            warm.root().unwrap().child_by_field("body").unwrap().text(),
            replacement
        );
        assert_eq!(
            warm.root().unwrap().child_by_field("body").unwrap().span(),
            cold.root().unwrap().child_by_field("body").unwrap().span()
        );
    }
    assert_eq!(old.source(), b"<alpha>");
}

#[test]
#[ignore = "explicit pinned TSX external-scanner consumer-source gate"]
fn pinned_tsx_eight_prose_expression_and_boundary_sources() {
    let grammar =
        CompiledGrammar::compile(include_bytes!("../../upstream/grammars/tsx.json")).unwrap();
    let fixture: serde_json::Value = serde_json::from_slice(include_bytes!(
        "../../test/migration/regulator/evidence/jsx-text-protocol.json"
    ))
    .unwrap();
    assert_eq!(fixture["cases"].as_array().unwrap().len(), 8);
    assert_eq!(fixture["whitespace_cases"].as_array().unwrap().len(), 7);
    for case in fixture["cases"]
        .as_array()
        .unwrap()
        .iter()
        .chain(fixture["whitespace_cases"].as_array().unwrap())
    {
        let source = case["source"].as_str().unwrap();
        let tree = grammar.session().parse(source.as_bytes()).unwrap();
        assert!(tree.confidence().is_strict(), "{source}");
        assert_eq!(tree.root().unwrap().text(), source.as_bytes());
        let actual: Vec<_> = tree.roots().map(oracle_node).collect();
        assert_eq!(json!(actual), case["oracle_tree"], "{source}");
    }
    for source in ["const view = <div>text", "const view = <div>{value"] {
        assert!(
            grammar.session().parse(source.as_bytes()).is_err(),
            "{source}"
        );
    }
}

fn oracle_node(node: Node<'_>) -> serde_json::Value {
    let mut value = json!({
        "name": node.name(),
        "named": node.is_named(),
        "start": node.span().start(),
        "end": node.span().end(),
        "kids": node.children().map(oracle_node).collect::<Vec<_>>(),
    });
    if let Some(field) = node.field() {
        value["field"] = json!(field);
    }
    value
}
