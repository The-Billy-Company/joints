//! Required ordinary empty tokens are real shifts, not repairs or scanner answers.
#![forbid(unsafe_code)]

use joints_engine::{
    ByteSpan, CompiledGrammar, Document, DocumentError, DocumentOptions, Error, ForeignPolicy,
    ParseLimits, ParseSession, Query, Resource, Reuse, TreeSnapshot,
};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::sync::Arc;

fn cases() -> Vec<Value> {
    serde_json::from_str(include_str!("fixtures/nullable-token.json")).unwrap()
}
fn case(name: &str) -> Value {
    cases().into_iter().find(|c| c["name"] == name).unwrap()
}
fn compile(name: &str) -> Arc<CompiledGrammar> {
    CompiledGrammar::compile(case(name)["grammar"].as_str().unwrap().as_bytes()).unwrap()
}
fn ledger(tree: &TreeSnapshot) -> Value {
    let mut pending: Vec<_> = tree.roots().rev().map(|n| (n, 0)).collect();
    let mut rows = vec![];
    while let Some((n, depth)) = pending.pop() {
        rows.push(json!([
            depth,
            n.name(),
            n.is_named(),
            n.field(),
            n.span().start(),
            n.span().end()
        ]));
        pending.extend(n.children().rev().map(|k| (k, depth + 1)));
    }
    Value::Array(rows)
}

#[test]
fn independent_nullable_alias_field_eof_and_priority_trees_survive_artifacts() {
    let cases = cases();
    let expected: std::collections::BTreeSet<_> = [
        "interior",
        "eof",
        "consecutive",
        "extra",
        "loop",
        "positive",
        "positive_competition",
        "eof_optional",
        "same_tier_positive",
        "higher_empty",
        "higher_positive",
        "global_extra_structural",
        "global_extra_automatic",
        "rule_extra_interior",
    ]
    .into();
    assert_eq!(cases.len(), 14);
    assert_eq!(
        cases
            .iter()
            .map(|c| c["name"].as_str().unwrap())
            .collect::<std::collections::BTreeSet<_>>(),
        expected
    );
    for case in cases {
        let bytes = case["grammar"].as_str().unwrap().as_bytes();
        let source = case["source"].as_str().unwrap().as_bytes();
        assert_eq!(
            Sha256::digest(bytes)
                .iter()
                .fold(String::new(), |mut text, byte| {
                    use std::fmt::Write as _;
                    write!(text, "{byte:02x}").expect("writing to a String cannot fail");
                    text
                }),
            case["oracle"]["grammar_sha256"]
        );
        assert_eq!(
            Sha256::digest(source)
                .iter()
                .fold(String::new(), |mut text, byte| {
                    use std::fmt::Write as _;
                    write!(text, "{byte:02x}").expect("writing to a String cannot fail");
                    text
                }),
            case["oracle"]["source_sha256"]
        );
        let grammar = CompiledGrammar::compile(bytes).unwrap();
        let loaded = CompiledGrammar::from_artifact(&grammar.artifact().unwrap()).unwrap();
        for grammar in [grammar, loaded] {
            let mut session = grammar.session();
            session.set_trace_enabled(true);
            let tree = session.parse(source).unwrap();
            assert!(
                tree.confidence().is_strict(),
                "{}: {:?}",
                case["name"],
                tree.confidence()
            );
            assert!(tree.repairs().is_empty());
            assert_eq!(ledger(&tree), case["expected"], "{}", case["name"]);
            assert!(
                !session
                    .product(&mut grammar.effect_store())
                    .unwrap()
                    .is_zero()
            );
            assert!(
                session
                    .selected_tokens()
                    .unwrap()
                    .iter()
                    .all(|t| !t.supplied)
            );
            if matches!(
                case["name"].as_str(),
                Some("interior" | "global_extra_structural")
            ) {
                let query_source: &[u8] = if case["name"] == "interior" {
                    b"(doc value: (empty) @empty)"
                } else {
                    b"(doc value: (content) @empty)"
                };
                let query = Query::compile(Arc::clone(&grammar), query_source).unwrap();
                assert!(query.dead_patterns().is_empty());
                let found = query.execute(&tree, ForeignPolicy::Refuse).unwrap();
                assert_eq!(found.len(), 1);
                let capture = &found[0].captures[0];
                assert_eq!(capture.node.span(), ByteSpan::new(1, 1).unwrap());
                assert!(!capture.node.is_extra());
            }
        }
    }
}

#[test]
fn real_go_empty_raw_strings_keep_a_zero_span_content_leaf_and_move() {
    let bytes = include_bytes!("../../upstream/grammars/go.json");
    assert_eq!(
        Sha256::digest(bytes)
            .iter()
            .fold(String::new(), |mut text, byte| {
                use std::fmt::Write as _;
                write!(text, "{byte:02x}").expect("writing to a String cannot fail");
                text
            }),
        "0dcc665aa521a1b73a200be13b4e376780cca037d764a165f12864babfe28000"
    );
    let grammar = CompiledGrammar::compile(bytes).unwrap();
    for source in [
        "package p\nvar x = ``\n",
        "package p\nfunc f() { use(``) }\n",
        "package p\nvar x = []string{`a`, ``, `b`}\n",
        "package p\nvar x = `` + ``\n",
    ] {
        let mut session = grammar.session();
        session.set_trace_enabled(true);
        let tree = session.parse(source.as_bytes()).unwrap();
        assert!(
            tree.confidence().is_strict(),
            "{source}: {:?}",
            tree.confidence()
        );
        assert!(tree.repairs().is_empty());
        let mut pending: Vec<_> = tree.roots().collect();
        let mut empty = vec![];
        while let Some(n) = pending.pop() {
            if n.name() == "raw_string_literal_content" && n.span().is_empty() {
                assert_eq!(n.text(), b"");
                assert!(!n.is_extra());
                empty.push(n.span());
            }
            pending.extend(n.children());
        }
        assert!(!empty.is_empty());
        let tokens = session.selected_tokens().unwrap();
        assert_eq!(
            tokens
                .iter()
                .filter(|t| t.span.is_empty() && !t.supplied)
                .count(),
            empty.len()
        );
        assert!(
            !session
                .product(&mut grammar.effect_store())
                .unwrap()
                .is_zero()
        );
    }
}

fn cycle_grammar() -> Arc<CompiledGrammar> {
    CompiledGrammar::compile(br#"{"rules":{
      "doc":{"type":"SEQ","members":[{"type":"STRING","value":"("},{"type":"SYMBOL","name":"chain"},{"type":"STRING","value":")"}]},
      "chain":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"SYMBOL","name":"zero"},{"type":"SYMBOL","name":"chain"}]},{"type":"SYMBOL","name":"zero"}]},
      "zero":{"type":"TOKEN","content":{"type":"PATTERN","value":"a*"}}},"extras":[]}"#).unwrap()
}

#[test]
fn zero_cycles_refuse_typed_work_node_and_stack_budgets() {
    let grammar = cycle_grammar();
    for (limits, wanted) in [
        (
            ParseLimits {
                steps: 32,
                ..ParseLimits::default()
            },
            Resource::Work,
        ),
        (
            ParseLimits {
                nodes: 8,
                steps: 100_000,
                ..ParseLimits::default()
            },
            Resource::Nodes,
        ),
        (
            ParseLimits {
                stack: 8,
                steps: 100_000,
                ..ParseLimits::default()
            },
            Resource::Stack,
        ),
    ] {
        let mut session = ParseSession::with_limits(Arc::clone(&grammar), limits);
        session.set_trace_enabled(true);
        assert!(
            matches!(session.parse(b"(!)"), Err(Error::LimitExceeded(resource)) if resource == wanted)
        );
        assert!(session.selected_tokens().is_none());
    }
}

#[test]
fn a_zero_cycle_refusal_preserves_the_published_document() {
    let grammar = cycle_grammar();
    let mut document = Document::with_options(
        grammar,
        b"()",
        DocumentOptions {
            limits: ParseLimits {
                steps: 2000,
                ..ParseLimits::default()
            },
            ..DocumentOptions::default()
        },
    )
    .unwrap();
    assert!(document.snapshot().confidence().is_strict());
    let snapshot = Arc::clone(document.snapshot());
    let product = document.product().unwrap();
    let cost = document.cost();
    assert!(matches!(
        document.edit(ByteSpan::new(1, 1).unwrap(), b"!"),
        Err(DocumentError::Parse(Error::LimitExceeded(Resource::Work)))
    ));
    assert!(Arc::ptr_eq(document.snapshot(), &snapshot));
    assert_eq!(document.source(), b"()");
    assert_eq!(document.product().unwrap(), product);
    assert_eq!(document.cost(), cost);
    document.edit(ByteSpan::new(1, 1).unwrap(), b"aaa").unwrap();
    assert_eq!(document.source(), b"(aaa)");
    assert!(document.snapshot().confidence().is_strict());
}

#[test]
fn empty_positive_and_optional_eof_edits_equal_cold_parsing() {
    for (name, source, at) in [
        ("interior", b"()".as_slice(), 1),
        ("eof", b"x", 1),
        ("eof_optional", b"x", 1),
    ] {
        let grammar = compile(name);
        let mut document = Document::new(Arc::clone(&grammar), source).unwrap();
        let previous = Arc::clone(document.snapshot());
        document
            .edit(ByteSpan::new(at, at).unwrap(), b"aaa")
            .unwrap();
        let mut expected = source.to_vec();
        expected.splice(at..at, b"aaa".iter().copied());
        assert_eq!(document.source(), expected);
        let cold = Document::new(Arc::clone(&grammar), document.source()).unwrap();
        assert_eq!(
            ledger(document.snapshot()),
            ledger(cold.snapshot()),
            "{name}"
        );
        assert_eq!(document.product().unwrap(), cold.product().unwrap());
        document
            .edit(ByteSpan::new(at, at + 3).unwrap(), b"")
            .unwrap();
        assert_eq!(document.source(), source);
        assert_eq!(ledger(document.snapshot()), ledger(&previous), "{name}");
        assert_eq!(previous.source(), source);
        assert!(document.snapshot().confidence().is_strict());
        assert!(document.snapshot().repairs().is_empty());
    }
    let mut value: Value =
        serde_json::from_str(case("interior")["grammar"].as_str().unwrap()).unwrap();
    let item = value["rules"]["doc"].clone();
    value["rules"]["doc"] = json!({"type":"REPEAT1","content":{"type":"SYMBOL","name":"item"}});
    value["rules"]["item"] = item;
    let grammar = CompiledGrammar::compile(&serde_json::to_vec(&value).unwrap()).unwrap();
    let source = "()".repeat(80);
    let mut document = Document::new(Arc::clone(&grammar), source.as_bytes()).unwrap();
    let at = source.len() - 1;
    document
        .edit(ByteSpan::new(at, at).unwrap(), b"aaa")
        .unwrap();
    assert_eq!(
        document.source(),
        format!("{}aaa{}", &source[..at], &source[at..]).as_bytes()
    );
    assert!(matches!(document.cost().reuse, Reuse::Prefix { bytes, .. } if bytes > 0));
    let cold = Document::new(grammar, document.source()).unwrap();
    assert_eq!(ledger(document.snapshot()), ledger(cold.snapshot()));
    assert_eq!(document.product().unwrap(), cold.product().unwrap());
    assert!(document.snapshot().repairs().is_empty());
}

#[test]
fn context_free_and_donated_extra_permissions_never_create_empty_progress() {
    let grammar = compile("extra");
    let walk = grammar.lexical_walk(b"?", 1000).unwrap();
    assert_eq!(walk.stray, Some(0));
    assert_eq!(walk.skipped, 0);
    assert!(walk.tokens.is_empty());
    let grammar = CompiledGrammar::compile(br##"{"rules":{
      "doc":{"type":"STRING","value":"x"},
      "comment":{"type":"SEQ","members":[{"type":"SYMBOL","name":"zero"},{"type":"STRING","value":"#"}]},
      "zero":{"type":"TOKEN","content":{"type":"PATTERN","value":"a*"}}},"extras":[{"type":"SYMBOL","name":"comment"}]}"##).unwrap();
    assert!(
        grammar
            .session()
            .parse(b"x")
            .unwrap()
            .confidence()
            .is_strict()
    );
    // Zero-leading independent extras remain an explicit conservative native
    // limitation: FIRST donation alone cannot fabricate a structural witness.
    assert!(
        !grammar
            .session()
            .parse_partial(b"#x")
            .unwrap()
            .confidence()
            .is_strict()
    );
}

#[test]
fn zero_byte_source_preserves_the_independent_conservative_refusal() {
    let cases: Vec<Value> =
        serde_json::from_str(include_str!("fixtures/nullable-token-refusals.json")).unwrap();
    assert_eq!(cases.len(), 1);
    let case = &cases[0];
    assert_eq!(case["name"], "zero_byte_source");
    let bytes = case["grammar"].as_str().unwrap().as_bytes();
    assert_eq!(
        Sha256::digest(bytes)
            .iter()
            .fold(String::new(), |mut text, byte| {
                use std::fmt::Write as _;
                write!(text, "{byte:02x}").expect("writing to a String cannot fail");
                text
            }),
        case["oracle"]["grammar_sha256"]
    );
    assert_eq!(case["source"], "");
    assert_eq!(case["oracle"]["generator_exit"], 0);
    assert_eq!(case["oracle"]["parse_exit"], 1);
    for key in ["xml", "cst"] {
        let raw = case["oracle"][key].as_str().unwrap();
        assert_eq!(
            Sha256::digest(raw.as_bytes())
                .iter()
                .fold(String::new(), |mut text, byte| {
                    use std::fmt::Write as _;
                    write!(text, "{byte:02x}").expect("writing to a String cannot fail");
                    text
                }),
            case["oracle"][format!("{key}_sha256")]
        );
        assert!(raw.contains("ERROR"));
    }
    let grammar = CompiledGrammar::compile(bytes).unwrap();
    let loaded = CompiledGrammar::from_artifact(&grammar.artifact().unwrap()).unwrap();
    for grammar in [grammar, loaded] {
        assert!(
            matches!(grammar.session().parse(b""), Err(Error::Refused(tree)) if !tree.confidence().is_strict())
        );
    }
}

#[test]
fn an_empty_tokens_distant_lookahead_invalidates_later_checkpoints() {
    let grammar = CompiledGrammar::compile(br#"{"rules":{"doc":{"type":"SEQ","members":[
      {"type":"STRING","value":"("},
      {"type":"ALIAS","named":true,"value":"maybe","content":{"type":"TOKEN","content":{"type":"PREC","value":1,"content":{"type":"PATTERN","value":".*z|a?"}}}},
      {"type":"REPEAT1","content":{"type":"CHOICE","members":[{"type":"STRING","value":"x"},{"type":"STRING","value":"z"}]}},
      {"type":"STRING","value":")"}]}},"extras":[]}"#).unwrap();
    let source = format!("({})", "x".repeat(80));
    let mut document = Document::new(Arc::clone(&grammar), source.as_bytes()).unwrap();
    let old = Arc::clone(document.snapshot());
    assert_eq!(
        old.root()
            .unwrap()
            .children()
            .find(|n| n.name() == "maybe")
            .unwrap()
            .span(),
        ByteSpan::new(1, 1).unwrap()
    );
    document.edit(ByteSpan::new(61, 62).unwrap(), b"z").unwrap();
    let mut expected = source.into_bytes();
    expected[61] = b'z';
    assert_eq!(document.source(), expected);
    let cold = Document::new(grammar, &expected).unwrap();
    assert!(document.snapshot().confidence().is_strict());
    assert_eq!(ledger(document.snapshot()), ledger(cold.snapshot()));
    assert_eq!(document.product().unwrap(), cold.product().unwrap());
    assert_eq!(
        document
            .snapshot()
            .root()
            .unwrap()
            .children()
            .find(|n| n.name() == "maybe")
            .unwrap()
            .span(),
        ByteSpan::new(1, 62).unwrap()
    );
    assert!(matches!(
        document.cost().reuse,
        Reuse::Cold | Reuse::Prefix { bytes: 1, .. }
    ));
    assert_eq!(
        old.root()
            .unwrap()
            .children()
            .find(|n| n.name() == "maybe")
            .unwrap()
            .span(),
        ByteSpan::new(1, 1).unwrap()
    );
}
