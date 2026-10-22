use joints_engine::{CompiledGrammar, Node};
use serde_json::json;

fn symbol(name: &str) -> serde_json::Value {
    json!({"type":"SYMBOL","name":name})
}
fn seq(names: &[&str]) -> serde_json::Value {
    json!({"type":"SEQ","members":names.iter().map(|n|symbol(n)).collect::<Vec<_>>()})
}
fn names(node: Node<'_>) -> Vec<String> {
    let mut pending = vec![node];
    let mut names = vec![];
    while let Some(node) = pending.pop() {
        names.push(node.name().to_owned());
        pending.extend(node.children());
    }
    names
}

#[test]
fn commanded_layout_executes_against_the_actual_runtime_stack() {
    let cohort = [
        "_cmd_layout_start",
        "_cmd_layout_start_do",
        "_cmd_layout_start_case",
        "_cmd_layout_start_if",
        "_cmd_layout_start_let",
        "_cmd_layout_start_quote",
        "_cmd_layout_start_explicit",
        "_cond_layout_semicolon",
        "_cond_layout_end",
        "_cond_layout_end_explicit",
        "_cmd_texp_start",
        "_cmd_texp_end",
        "_cmd_brace_open",
        "_cmd_brace_close",
    ];
    let grammar = json!({"name":"commanded_test","rules":{
        "doc":seq(&["_cmd_layout_start","word","_cond_layout_semicolon","word","_cond_layout_end"]),
        "word":{"type":"PATTERN","value":"[a-z]+"}},
        "extras":[{"type":"PATTERN","value":"[ \\t\\n]+"}],"externals":cohort.iter().map(|n|symbol(n)).collect::<Vec<_>>()});
    let grammar = CompiledGrammar::compile(&serde_json::to_vec(&grammar).unwrap()).unwrap();
    assert_eq!(grammar.unsupported_externals().count(), 0);
    let mut session = grammar.session();
    let tree = session.parse(b"alpha\nbeta\n").unwrap();
    assert!(tree.survey().is_sound());
    assert_eq!(
        names(tree.root().unwrap())
            .iter()
            .filter(|n| n.as_str() == "word")
            .count(),
        2
    );
    assert!(
        !session
            .product(&mut grammar.effect_store())
            .unwrap()
            .is_zero()
    );
    // The same session must start with a fresh context stack on its next input.
    assert!(session.parse(b"one\ntwo").is_ok());
}

#[test]
fn raw_delimiter_memory_preserves_empty_and_escaped_quote_content() {
    let cohort = [
        "_raw_string_literal_start",
        "raw_string_literal_content",
        "_raw_string_literal_end",
    ];
    let grammar = json!({"name":"raw_test","rules":{"doc":seq(&cohort)},"externals":cohort.iter().map(|n|symbol(n)).collect::<Vec<_>>()});
    let grammar = CompiledGrammar::compile(&serde_json::to_vec(&grammar).unwrap()).unwrap();
    let mut session = grammar.session();
    for (source, content) in [
        (b"r\"\"" as &[u8], b"" as &[u8]),
        (b"r#\"x\\\"y\"#", b"x\\\"y"),
    ] {
        let tree = session.parse(source).unwrap();
        assert!(tree.survey().is_sound());
        let content_node = tree
            .root()
            .unwrap()
            .children()
            .find(|n| n.name() == "raw_string_literal_content")
            .unwrap();
        assert_eq!(content_node.text(), content);
    }
}

#[test]
fn rule_extras_reduce_nested_recipes_fields_and_aliases_outside_structural_moves() {
    let grammar = json!({"name":"rule_extras","rules":{
        "doc":{"type":"SEQ","members":[{"type":"STRING","value":"x"},{"type":"STRING","value":"y"}]},
        "note":{"type":"SEQ","members":[{"type":"STRING","value":"<"},
          {"type":"FIELD","name":"body","content":{"type":"ALIAS","named":true,"value":"comment_text","content":symbol("_body")}},
          {"type":"STRING","value":">"}]},
        "_body":{"type":"CHOICE","members":[{"type":"PATTERN","value":"[a-z]+"},
          {"type":"SEQ","members":[{"type":"STRING","value":"("},symbol("_body"),{"type":"STRING","value":")"}]}]}},
        "extras":[{"type":"PATTERN","value":"[ \\t\\n]+"},symbol("note")]});
    let grammar = CompiledGrammar::compile(&serde_json::to_vec(&grammar).unwrap()).unwrap();
    let mut session = grammar.session();
    let mut effects = grammar.effect_store();
    let tree = session.parse(b"<(a)>x<b>y<c>").unwrap();
    let comments: Vec<_> = tree
        .root()
        .unwrap()
        .children()
        .filter(|n| n.name() == "note")
        .collect();
    assert_eq!(comments.len(), 3);
    assert!(tree.survey().is_sound());
    for (comment, text) in comments.iter().zip([b"(a)" as &[u8], b"b", b"c"]) {
        assert!(comment.is_extra());
        let body = comment.child_by_field("body").unwrap();
        assert_eq!(body.name(), "comment_text");
        assert_eq!(body.text(), text);
        assert_eq!(body.parent().unwrap().name(), "note");
    }
    let commented = session.product(&mut effects).unwrap();
    session.parse(b"xy").unwrap();
    assert_eq!(session.product(&mut effects).unwrap(), commented);
    let refused = session.parse_partial(b"<(a)").unwrap();
    assert!(!refused.confidence().is_strict());
    assert!(refused.roots().all(|n| !names(n).contains(&"note".into())));
    assert!(session.parse(b"xy").is_ok());
    assert_eq!(comments[0].text(), b"<(a)>");
}

#[test]
fn rule_extra_scanner_context_reads_nested_rust_comment_bodies() {
    let externals = [
        "_block_comment_content",
        "_outer_block_doc_comment_marker",
        "_inner_block_doc_comment_marker",
    ];
    let grammar = json!({"name":"rust_comment_test","rules":{
        "doc":{"type":"STRING","value":"x"},
        "block_comment":{"type":"SEQ","members":[{"type":"STRING","value":"/*"},
          {"type":"CHOICE","members":[symbol("_block_comment_content"),{"type":"BLANK"}]},
          {"type":"STRING","value":"*/"}]}},
        "externals":externals.iter().map(|n|symbol(n)).collect::<Vec<_>>(),
        "extras":[symbol("block_comment")]});
    let grammar = CompiledGrammar::compile(&serde_json::to_vec(&grammar).unwrap()).unwrap();
    let source = b"/* a /* nested */ b */x/* tail */";
    let tree = grammar.session().parse(source).unwrap();
    assert!(tree.survey().is_sound());
    let comments: Vec<_> = tree
        .root()
        .unwrap()
        .children()
        .filter(|n| n.name() == "block_comment")
        .collect();
    assert_eq!(comments.len(), 2);
    assert_eq!(comments[0].text(), b"/* a /* nested */ b */");
    assert_eq!(comments[1].text(), b"/* tail */");
    assert!(comments.iter().all(|n| n.is_extra()));
    assert_eq!(
        comments[0].children().map(|n| n.text()).collect::<Vec<_>>(),
        vec![b"/*" as &[u8], b"*/"]
    );
}

#[test]
fn external_first_rule_extras_commit_whole_recipes_and_roll_back_rejected_openers() {
    let cohort = [
        "_raw_string_literal_start",
        "raw_string_literal_content",
        "_raw_string_literal_end",
    ];
    let raw = seq(&cohort);
    let grammar = json!({"name":"external_first_extra","rules":{
        "doc":{"type":"CHOICE","members":[{"type":"STRING","value":"x"},
          {"type":"SEQ","members":[{"type":"STRING","value":"r#\"a\"#x"},raw.clone()]}]},
        "note":{"type":"SEQ","members":[raw,{"type":"STRING","value":"!"}]}},
        "externals":cohort.iter().map(|n|symbol(n)).collect::<Vec<_>>(),
        "extras":[symbol("note")]});
    let grammar = CompiledGrammar::compile(&serde_json::to_vec(&grammar).unwrap()).unwrap();
    let mut session = grammar.session();
    let accepted = session.parse(b"r#\"ignored\"#!x").unwrap();
    let note = accepted
        .root()
        .unwrap()
        .children()
        .find(|n| n.name() == "note")
        .unwrap();
    assert!(note.is_extra());
    assert_eq!(note.text(), b"r#\"ignored\"#!");
    assert_eq!(
        note.children()
            .find(|n| n.name() == "raw_string_literal_content")
            .unwrap()
            .text(),
        b"ignored"
    );
    let mut effects = grammar.effect_store();
    let extra_product = session.product(&mut effects).unwrap();
    session.parse(b"x").unwrap();
    assert_eq!(session.product(&mut effects).unwrap(), extra_product);
    // The external extra opener wins the first scan, but its mandatory ! is
    // absent. Restoring its checkpoint lets the document read its own longer
    // literal and then open a second raw string with a different delimiter.
    let fallback = session.parse(b"r#\"a\"#xr##\"tail\"##").unwrap();
    assert!(fallback.survey().is_sound());
    assert!(
        fallback
            .root()
            .unwrap()
            .children()
            .all(|n| n.name() != "note")
    );
    assert_eq!(
        fallback
            .root()
            .unwrap()
            .children()
            .find(|n| n.name() == "raw_string_literal_content")
            .unwrap()
            .text(),
        b"tail"
    );
    assert!(accepted.survey().is_sound());
    assert_eq!(note.text(), b"r#\"ignored\"#!");
}
