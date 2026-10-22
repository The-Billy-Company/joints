//! Every published edit is checked against an independent cold session.
use std::sync::Arc;

use joints_engine::{
    ByteSpan, CompiledGrammar, Confidence, Document, DocumentError, DocumentOptions, Error,
    LexError, Node, ParseLimits, ParseSession, Point, Recovery, Repair, Reuse, Stop, Supply,
    Survey, TreeSnapshot,
};
use serde_json::{Value, json};

#[derive(Debug, PartialEq, Eq)]
struct NodeImage {
    name: String,
    named: bool,
    extra: bool,
    span: ByteSpan,
    field: Option<String>,
    text: Vec<u8>,
    start: Point,
    end: Point,
    parent: Option<(String, ByteSpan)>,
    children: Vec<NodeImage>,
}

fn point(source: &[u8], at: usize) -> Point {
    let prefix = &source[..at];
    Point {
        row: prefix.iter().filter(|&&b| b == b'\n').count() as u32,
        column: prefix
            .iter()
            .rposition(|&b| b == b'\n')
            .map_or(at, |last| at - last - 1) as u32,
    }
}

fn image(node: Node<'_>, source: &[u8]) -> NodeImage {
    let span = node.span();
    assert!(span.end() <= source.len());
    assert_eq!(node.text(), &source[span.range()]);
    assert_eq!(node.start_point(), point(source, span.start()));
    assert_eq!(node.end_point(), point(source, span.end()));
    let children: Vec<_> = node.children().collect();
    for child in &children {
        let parent = child.parent().expect("published child has a parent");
        assert_eq!((parent.name(), parent.span()), (node.name(), span));
        if let Some(field) = child.field() {
            let first = children.iter().find(|n| n.field() == Some(field)).unwrap();
            let found = node.child_by_field(field).unwrap();
            assert_eq!((found.name(), found.span()), (first.name(), first.span()));
        }
    }
    NodeImage {
        name: node.name().into(),
        named: node.is_named(),
        extra: node.is_extra(),
        span,
        field: node.field().map(str::to_owned),
        text: node.text().to_vec(),
        start: node.start_point(),
        end: node.end_point(),
        parent: node.parent().map(|p| (p.name().into(), p.span())),
        children: children.into_iter().map(|n| image(n, source)).collect(),
    }
}

#[derive(Debug, PartialEq, Eq)]
struct TreeImage {
    source: Vec<u8>,
    stop: Stop,
    confidence: Confidence,
    survey: Survey,
    repairs: Vec<Repair>,
    spurned: usize,
    tree: Vec<NodeImage>,
}

fn tree_image(tree: &TreeSnapshot) -> TreeImage {
    assert!(tree.survey().is_sound());
    assert_eq!(tree.survey().held, tree.survey().walked);
    TreeImage {
        source: tree.source().to_vec(),
        stop: tree.stop(),
        confidence: tree.confidence(),
        survey: tree.survey(),
        repairs: tree.repairs().to_vec(),
        spurned: tree.spurned(),
        tree: tree.roots().map(|n| image(n, tree.source())).collect(),
    }
}

fn compile(source: Value) -> Arc<CompiledGrammar> {
    CompiledGrammar::compile(&serde_json::to_vec(&source).unwrap()).unwrap()
}

fn sym(name: &str) -> Value {
    json!({"type":"SYMBOL","name":name})
}

fn sequence(names: &[&str]) -> Value {
    json!({"type":"SEQ","members":names.iter().map(|n|sym(n)).collect::<Vec<_>>()})
}

fn assert_cold(document: &Document, grammar: &Arc<CompiledGrammar>, options: DocumentOptions) {
    let mut cold = ParseSession::with_limits(Arc::clone(grammar), options.limits);
    cold.set_recovery(options.recovery);
    cold.set_supply(options.supply);
    let tree = cold.parse_partial(document.source()).unwrap();
    assert_eq!(tree_image(document.snapshot()), tree_image(&tree));
    // Handles are local to their interning spaces; canonical descriptions are not.
    let mut independent = grammar.effect_store();
    let product = cold.product(&mut independent).unwrap();
    assert_eq!(
        document.product().unwrap(),
        independent.describe(product).unwrap()
    );
}

fn edit(
    document: &mut Document,
    grammar: &Arc<CompiledGrammar>,
    options: DocumentOptions,
    start: usize,
    end: usize,
    replacement: &[u8],
) {
    let mut expected = document.source()[..start].to_vec();
    expected.extend_from_slice(replacement);
    expected.extend_from_slice(&document.source()[end..]);
    document
        .edit(ByteSpan::new(start, end).unwrap(), replacement)
        .unwrap();
    assert_eq!(document.source(), expected);
    assert_eq!(document.snapshot().source(), expected);
    assert_cold(document, grammar, options);
}

fn json_grammar() -> Arc<CompiledGrammar> {
    CompiledGrammar::compile(include_bytes!("../../test/grammar/json.json")).unwrap()
}

fn long_json() -> Vec<u8> {
    format!(
        "[{}]",
        (0..96)
            .map(|i| format!("{{\"key\":{i},\"text\":\"item\"}}"))
            .collect::<Vec<_>>()
            .join(",\n")
    )
    .into_bytes()
}

#[test]
fn a_real_prefix_resume_preserves_snapshots_fields_spans_and_products() {
    let grammar = json_grammar();
    let options = DocumentOptions::default();
    let mut document = Document::new(Arc::clone(&grammar), &long_json()).unwrap();
    assert_cold(&document, &grammar, options);
    let retained = Arc::clone(document.snapshot());
    let retained_image = tree_image(&retained);
    let last = document.source().len() - 7;
    edit(&mut document, &grammar, options, last, last + 1, b"I");
    assert!(
        matches!(document.cost().reuse, Reuse::Prefix { bytes, validated_events }
        if bytes > 0 && bytes <= last && validated_events > 0)
    );
    assert!(document.cost().sequence_leaves_kept > 0);
    assert_eq!(tree_image(&retained), retained_image);
    assert!(!Arc::ptr_eq(&retained, document.snapshot()));
    edit(&mut document, &grammar, options, 0, 0, b"\n ");
    assert_eq!(document.cost().reuse, Reuse::Cold);
    let len = document.source().len();
    edit(&mut document, &grammar, options, len, len, b"\r\n");
    assert_eq!(tree_image(&retained), retained_image);
}

#[test]
fn distant_maximal_munch_can_invalidate_the_first_token_beyond_many_checkpoints() {
    let grammar = compile(json!({"name":"distant_lookahead","rules":{
        "doc":{"type":"REPEAT","content":{"type":"CHOICE","members":[sym("wide"),sym("unit")]}},
        "wide":{"type":"PATTERN","value":"a.*z|a"},
        "unit":{"type":"PATTERN","value":"x|z"}},
        "extras":[{"type":"PATTERN","value":"[ ]+"}]}));
    let mut source = b"a ".to_vec();
    source.extend_from_slice("x ".repeat(256).as_bytes());
    let options = DocumentOptions::default();
    let mut document = Document::new(Arc::clone(&grammar), &source).unwrap();
    assert!(document.snapshot().survey().walked > 200);
    let end = source.len();
    edit(&mut document, &grammar, options, end, end, b"z");
    assert!(document.snapshot().confidence().is_strict());
    assert_eq!(document.snapshot().survey().walked, 2);
    assert_eq!(document.cost().reuse, Reuse::Cold);
    assert_eq!(
        document
            .snapshot()
            .root()
            .unwrap()
            .children()
            .next()
            .unwrap()
            .span()
            .end(),
        end + 1
    );
}

#[test]
fn appending_to_a_word_revalidates_the_old_token_boundary() {
    let grammar = compile(json!({"name":"word_boundary","rules":{
        "doc":{"type":"REPEAT","content":sym("word")},
        "word":{"type":"PATTERN","value":"[a-z]+"}},
        "extras":[{"type":"PATTERN","value":"[ \\n]+"}]}));
    let source = format!("{}tail", "word ".repeat(128));
    let options = DocumentOptions::default();
    let mut document = Document::new(Arc::clone(&grammar), source.as_bytes()).unwrap();
    let end = source.len();
    edit(&mut document, &grammar, options, end, end, b"piece");
    assert_eq!(
        document
            .snapshot()
            .root()
            .unwrap()
            .children()
            .last()
            .unwrap()
            .text(),
        b"tailpiece"
    );
    assert!(matches!(document.cost().reuse, Reuse::Prefix { bytes, .. } if bytes > 0));
}

#[test]
fn rule_extra_trials_preserve_scanner_rollback_and_external_delimiter_memory() {
    let names = [
        "_raw_string_literal_start",
        "raw_string_literal_content",
        "_raw_string_literal_end",
    ];
    let raw = sequence(&names);
    let grammar = compile(json!({"name":"extra_rollback_edits","rules":{
        "doc":{"type":"SEQ","members":[{"type":"REPEAT","content":{"type":"STRING","value":"p"}},
          {"type":"CHOICE","members":[{"type":"STRING","value":"x"},
            {"type":"SEQ","members":[{"type":"STRING","value":"r#\"a\"#x"},raw.clone()]}]}]},
        "note":{"type":"SEQ","members":[raw,{"type":"STRING","value":"!"}]}},
        "externals":names.iter().map(|n|sym(n)).collect::<Vec<_>>(),
        "extras":[{"type":"PATTERN","value":"[ ]+"},sym("note")]}));
    let source = format!("{}r#\"a\"#xr##\"tail\"##", "p ".repeat(96));
    let options = DocumentOptions::default();
    let mut document = Document::new(Arc::clone(&grammar), source.as_bytes()).unwrap();
    assert!(document.snapshot().confidence().is_strict());
    let at = source.find("tail").unwrap();
    edit(&mut document, &grammar, options, at, at + 4, b"body");
    assert!(matches!(document.cost().reuse, Reuse::Prefix { bytes, .. } if bytes > 0));
    edit(&mut document, &grammar, options, at, at + 4, b"new\nbody");
    let end = document.source().len();
    edit(&mut document, &grammar, options, end - 2, end, b"#");
    edit(&mut document, &grammar, options, end - 2, end - 1, b"##");
}

#[test]
fn recursive_named_extras_keep_aliases_fields_and_parent_ownership_across_edits() {
    let grammar = compile(json!({"name":"extra_tree_edits","rules":{
        "doc":{"type":"REPEAT","content":{"type":"STRING","value":"x"}},
        "note":{"type":"SEQ","members":[{"type":"STRING","value":"<"},
          {"type":"FIELD","name":"body","content":{"type":"ALIAS","named":true,"value":"comment_text","content":sym("_body")}},
          {"type":"STRING","value":">"}]},
        "_body":{"type":"CHOICE","members":[{"type":"PATTERN","value":"[a-z]+"},
          {"type":"SEQ","members":[{"type":"STRING","value":"("},sym("_body"),{"type":"STRING","value":")"}]}]}},
        "extras":[{"type":"PATTERN","value":"[ \\n]+"},sym("note")]}));
    let source = format!("{}<(body)>x<tail>", "x ".repeat(96));
    let options = DocumentOptions::default();
    let mut document = Document::new(Arc::clone(&grammar), source.as_bytes()).unwrap();
    let at = source.find("body").unwrap();
    edit(&mut document, &grammar, options, at, at + 4, b"nested");
    assert!(matches!(document.cost().reuse, Reuse::Prefix { bytes, .. } if bytes > 0));
    edit(&mut document, &grammar, options, at - 1, at - 1, b"(");
    edit(&mut document, &grammar, options, at + 7, at + 7, b")");
}

#[test]
fn changed_future_can_select_a_different_declared_glr_winner() {
    let grammar = compile(json!({"name":"glr_edit","rules":{
        "doc":{"type":"SEQ","members":[{"type":"REPEAT","content":{"type":"STRING","value":"p"}},
          {"type":"CHOICE","members":[
            {"type":"SEQ","members":[sym("a"),{"type":"STRING","value":"y"}]},
            {"type":"SEQ","members":[sym("b"),{"type":"STRING","value":"y"},{"type":"STRING","value":"z"}]}]}]},
        "a":{"type":"ALIAS","named":true,"value":"first","content":sym("item")},
        "b":{"type":"ALIAS","named":true,"value":"second","content":sym("item")},
        "item":{"type":"STRING","value":"x"}},"conflicts":[["a","b"]],
        "extras":[{"type":"PATTERN","value":"[ ]+"}]}));
    let source = format!("{}xy", "p ".repeat(96));
    let options = DocumentOptions::default();
    let mut document = Document::new(Arc::clone(&grammar), source.as_bytes()).unwrap();
    let before = tree_image(document.snapshot());
    edit(
        &mut document,
        &grammar,
        options,
        source.len(),
        source.len(),
        b"z",
    );
    assert_ne!(tree_image(document.snapshot()), before);
    assert_eq!(document.cost().reuse, Reuse::Cold);
}

#[test]
fn repaired_inputs_decline_prefix_reuse_and_preserve_every_scar() {
    let grammar = json_grammar();
    for recovery in [Recovery::Keep, Recovery::Fell, Recovery::Relent] {
        let options = DocumentOptions {
            recovery,
            supply: Supply::UniqueLiteral,
            ..DocumentOptions::default()
        };
        let source = format!("[{}??2]", "1,".repeat(96));
        let mut document =
            Document::with_options(Arc::clone(&grammar), source.as_bytes(), options).unwrap();
        assert!(!document.snapshot().repairs().is_empty());
        assert_cold(&document, &grammar, options);
        let end = document.source().len();
        edit(&mut document, &grammar, options, end, end, b"\n");
        assert_eq!(document.cost().reuse, Reuse::Cold);
        edit(&mut document, &grammar, options, 0, 0, b" ");
        assert_eq!(document.cost().reuse, Reuse::Cold);
    }
}

#[test]
fn invalid_spans_and_operational_failure_leave_a_publishable_previous_version() {
    let grammar = compile(json!({"name":"bounded_document","rules":{
        "doc":{"type":"REPEAT","content":{"type":"STRING","value":"x"}}}}));
    let options = DocumentOptions {
        limits: ParseLimits {
            nodes: 64,
            source_bytes: 256,
            ..ParseLimits::default()
        },
        ..DocumentOptions::default()
    };
    let mut document = Document::with_options(Arc::clone(&grammar), b"xxxxxxxx", options).unwrap();
    let before = Arc::clone(document.snapshot());
    let product = document.product().unwrap();
    let cost = document.cost();
    for (range, bytes) in [
        (8..9, b"".as_slice()),
        (8..8, &[b'x'; 300][..]),
        (8..8, &[b'x'; 128][..]),
    ] {
        assert!(
            document
                .edit(ByteSpan::new(range.start, range.end).unwrap(), bytes)
                .is_err()
        );
        assert!(Arc::ptr_eq(&before, document.snapshot()));
        assert_eq!(document.source(), b"xxxxxxxx");
        assert_eq!(document.product().unwrap(), product);
        assert_eq!(document.cost(), cost);
    }
    assert!(matches!(
        document.edit(ByteSpan::new(8, 9).unwrap(), b""),
        Err(DocumentError::InvalidSpan { .. })
    ));
    // A failed attempt may clear optimization scratch; the next edit must still
    // start from the last published source rather than the failed candidate.
    edit(&mut document, &grammar, options, 7, 8, b"");
    assert_eq!(document.source(), b"xxxxxxx");
    assert_eq!(tree_image(&before).source, b"xxxxxxxx");
}

#[test]
fn equal_byte_replacements_keep_the_same_snapshot_and_do_no_parse_work() {
    let grammar = json_grammar();
    let mut document = Document::new(Arc::clone(&grammar), b"[1,2]").unwrap();
    let before = Arc::clone(document.snapshot());
    let product = document.product().unwrap();
    document.edit(ByteSpan::new(1, 4).unwrap(), b"1,2").unwrap();
    assert!(Arc::ptr_eq(&before, document.snapshot()));
    assert_eq!(document.cost().reuse, Reuse::Unchanged);
    assert_eq!(document.cost().parser_work, 0);
    assert_eq!(document.cost().lexical_work, 0);
    assert_eq!(document.cost().sequence_nodes_created, 0);
    assert_eq!(document.product().unwrap(), product);
}

#[test]
fn bounded_prefix_validation_cannot_publish_a_partial_operation() {
    let grammar = compile(json!({"name":"bounded_validation","rules":{
        "doc":{"type":"REPEAT","content":{"type":"CHOICE","members":[sym("wide"),sym("unit")]}},
        "wide":{"type":"PATTERN","value":"a.*z|a"},
        "unit":{"type":"STRING","value":"x"}}}));
    let options = DocumentOptions {
        limits: ParseLimits {
            lexical_steps: 1000,
            source_bytes: 4096,
            ..ParseLimits::default()
        },
        ..DocumentOptions::default()
    };
    let source = format!("a{}", "x".repeat(128));
    let mut document =
        Document::with_options(Arc::clone(&grammar), source.as_bytes(), options).unwrap();
    let retained = Arc::clone(document.snapshot());
    let product = document.product().unwrap();
    let end = source.len();
    assert!(matches!(
        document.edit(ByteSpan::new(end, end).unwrap(), &[b'x'; 2048]),
        Err(DocumentError::Parse(Error::Lex(LexError::WorkLimit { .. })))
    ));
    assert!(Arc::ptr_eq(&retained, document.snapshot()));
    assert_eq!(document.source(), source.as_bytes());
    assert_eq!(document.product().unwrap(), product);
    edit(&mut document, &grammar, options, end - 1, end, b"z");
    assert!(document.snapshot().confidence().is_strict());
}

#[test]
fn deterministic_edit_stream_checks_every_intermediate_forest_and_byte_position() {
    let grammar = json_grammar();
    let options = DocumentOptions {
        recovery: Recovery::Relent,
        supply: Supply::UniqueLiteral,
        ..DocumentOptions::default()
    };
    let mut document = Document::with_options(Arc::clone(&grammar), &long_json(), options).unwrap();
    let mut state = 0x8e2f_d691_9b74_231du64;
    let insertions: &[&[u8]] = &[
        b"",
        b"x",
        b"\n",
        b"\r\n",
        b" ",
        b"0",
        b"\"",
        b"\\",
        b",",
        b"[]",
        b"\xff",
        "\u{03bb}".as_bytes(),
    ];
    for step in 0..120 {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        let len = document.source().len();
        let at = match step % 4 {
            0 => 0,
            1 => len / 2,
            2 => len,
            _ => state as usize % (len + 1),
        };
        let over = (at + ((state >> 17) as usize % 4)).min(len);
        let replacement = insertions[(state >> 33) as usize % insertions.len()];
        edit(&mut document, &grammar, options, at, over, replacement);
    }
}

#[test]
fn frozen_json_corpus_edits_cover_every_portable_case_without_skipping_refusals() {
    let home = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../test/migration/reference");
    let manifest: Value =
        serde_json::from_slice(&std::fs::read(home.join("manifest.json")).unwrap()).unwrap();
    let cases = manifest["cases"].as_array().unwrap();
    assert_eq!(cases.len(), 25);
    let grammar = json_grammar();
    let mut executed = 0;
    for case in cases {
        let default = case["id"].as_str().unwrap().ends_with("-default");
        let options = DocumentOptions {
            recovery: if default {
                Recovery::Fell
            } else {
                Recovery::None
            },
            supply: if default {
                Supply::UniqueLiteral
            } else {
                Supply::Disabled
            },
            ..DocumentOptions::default()
        };
        let source = std::fs::read(home.join(case["argv"][2].as_str().unwrap())).unwrap();
        let mut document = Document::with_options(Arc::clone(&grammar), &source, options).unwrap();
        assert_cold(&document, &grammar, options);
        for position in 0..3 {
            let len = document.source().len();
            let at = match position {
                0 => 0,
                1 => len / 2,
                _ => len,
            };
            let replacement: &[u8] = if position == 1 { b"\xff" } else { b"\n" };
            edit(&mut document, &grammar, options, at, at, replacement);
            executed += 1;
        }
    }
    assert_eq!(executed, 75);
}

#[test]
fn same_length_line_edits_rebuild_book_indexes_and_zero_width_memory() {
    // The authored grammar binds the generic YAML scanner book by its complete
    // protocol roster. This isolates source-index and scalar-frame behavior
    // without depending on a full upstream grammar's unrelated parse choices.
    let book: Value = serde_json::from_str(include_str!("../../customary/yaml.json")).unwrap();
    let mut names = std::collections::BTreeSet::new();
    for name in book["cohort"].as_array().unwrap() {
        names.insert(name.as_str().unwrap().to_owned());
    }
    for arms in book["classes"].as_object().unwrap().values() {
        for arm in arms.as_array().unwrap() {
            names.insert(arm[1].as_str().unwrap().to_owned());
        }
    }
    for rule in book["rules"].as_array().unwrap() {
        for guard in rule["when"].as_array().map(Vec::as_slice).unwrap_or(&[]) {
            if ["wanted", "not_wanted", "named", "not_named", "sole"]
                .contains(&guard[0].as_str().unwrap())
            {
                names.insert(guard[1].as_str().unwrap().to_owned());
            }
        }
        for action in rule["then"].as_array().map(Vec::as_slice).unwrap_or(&[]) {
            if action[0] == "emit" {
                names.insert(action[1].as_str().unwrap().to_owned());
            }
        }
    }
    let grammar = compile(json!({"name":"book_index_edit","rules":{
        "doc":{"type":"SEQ","members":[
          {"type":"REPEAT","content":{"type":"STRING","value":"x"}},
          sym("_r_blk_lit_bgn"),
          {"type":"REPEAT1","content":{"type":"ALIAS","named":true,"value":"content","content":sym("_br_blk_str_ctn")}},
          sym("_bl"),sym("_eof")]}},
        "externals":names.iter().map(|n|sym(n)).collect::<Vec<_>>(),
        "extras":[{"type":"PATTERN","value":"[ \\n]+"}]}));
    let source = format!("{}|\n  alpha\n  beta\n", "x ".repeat(96));
    let options = DocumentOptions::default();
    let mut document = Document::new(Arc::clone(&grammar), source.as_bytes()).unwrap();
    assert!(document.snapshot().confidence().is_strict());
    let at = source.find("alpha\n").unwrap() + 5;
    for (step, replacement) in [b" ".as_slice(), b"\n", b"\r", b"\n"]
        .into_iter()
        .enumerate()
    {
        edit(&mut document, &grammar, options, at, at + 1, replacement);
        if step < 2 {
            assert!(matches!(document.cost().reuse, Reuse::Prefix { bytes, .. } if bytes > 0));
            assert!(document.snapshot().confidence().is_strict());
        } else if step == 2 {
            // A CR is a break but not a LF line start. This changes the book's
            // scalar-header lookahead, and the diagnostic tree remains exact.
            assert!(!document.snapshot().confidence().is_strict());
        } else {
            assert_eq!(document.cost().reuse, Reuse::Cold);
            assert!(document.snapshot().confidence().is_strict());
        }
    }
}
