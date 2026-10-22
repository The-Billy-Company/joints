use joints_engine::{
    ByteSpan, CompiledGrammar, Document, DocumentError, DocumentOptions, Error, ForeignPolicy,
    Node, ParseLimits, Query, Resource, Reuse, TreeSnapshot,
};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::sync::Arc;

fn cases() -> Vec<Value> {
    serde_json::from_str(include_str!("fixtures/declared-choice.json")).unwrap()
}

fn ledger(tree: &TreeSnapshot) -> Value {
    let mut pending: Vec<_> = tree.roots().rev().map(|node| (node, 0)).collect();
    let mut rows = vec![];
    while let Some((node, depth)) = pending.pop() {
        rows.push(json!([
            depth,
            node.name(),
            node.is_named(),
            node.field(),
            node.span().start(),
            node.span().end()
        ]));
        pending.extend(node.children().rev().map(|child| (child, depth + 1)));
    }
    Value::Array(rows)
}

#[test]
fn declared_choices_match_independent_static_dynamic_hidden_and_metadata_controls() {
    assert_choices(
        cases(),
        &[
            "call_first",
            "binary_first",
            "static_binary",
            "dynamic_call",
            "dynamic_binary",
            "hidden_order",
            "hidden_order_two",
            "aliases_fields",
            "hidden_alias_fields",
            "unit_field",
            "unit_alias",
            "unit_alias_field",
            "unit_dynamic",
        ],
    );
}

#[test]
fn hidden_unit_eligibility_matches_independent_state_and_recipe_controls() {
    assert_choices(
        serde_json::from_str(include_str!("fixtures/declared-unit.json")).unwrap(),
        &[
            "unit_multiple_distinct",
            "unit_mixed_width",
            "unit_multiple_alias",
            "unit_contested_single",
            "unit_supertype",
            "unit_aliased_wrapper",
            "unit_inherited_field",
            "unit_local_alias_recipe",
            "unit_extra_nonterminal",
            "unit_extra_lexical",
            "unit_inline_host_alias",
            "unit_inline_body_alias",
            "unit_extra_existing_key",
        ],
    );
}

#[test]
fn pre_inline_alias_origin_survives_otherwise_identical_normalized_tables() {
    let cases: Vec<Value> =
        serde_json::from_str(include_str!("fixtures/declared-unit.json")).unwrap();
    let compile = |name| {
        let case = cases.iter().find(|c| c["name"] == name).unwrap();
        let mut grammar: Value = serde_json::from_str(case["grammar"].as_str().unwrap()).unwrap();
        grammar["name"] = json!("same_inline_alias");
        CompiledGrammar::compile(&serde_json::to_vec(&grammar).unwrap()).unwrap()
    };
    let host = compile("unit_inline_host_alias");
    let body = compile("unit_inline_body_alias");
    assert_eq!(host.state_count(), body.state_count());
    assert_eq!(host.productions().len(), body.productions().len());
    let markers = |g: &CompiledGrammar| {
        g.productions()
            .flat_map(|(_, p)| p.steps.iter())
            .filter(|s| s.alias.is_some())
            .map(|s| s.alias_recipe)
            .collect::<std::collections::BTreeSet<_>>()
    };
    assert_eq!(markers(&host), [joints_engine::AliasRecipe::Local].into());
    assert_eq!(markers(&body), [joints_engine::AliasRecipe::Empty].into());
    assert_ne!(host.artifact().unwrap(), body.artifact().unwrap());
}

fn assert_choices(cases: Vec<Value>, expected: &[&str]) {
    assert_eq!(cases.len(), expected.len());
    let names: std::collections::BTreeSet<_> =
        cases.iter().map(|c| c["name"].as_str().unwrap()).collect();
    assert_eq!(names.len(), expected.len());
    assert_eq!(names, expected.iter().copied().collect());
    for case in cases {
        let source = case["source"].as_str().unwrap().as_bytes();
        let bytes = case["grammar"].as_str().unwrap().as_bytes();
        assert_eq!(
            Sha256::digest(bytes)
                .iter()
                .map(|byte| format!("{byte:02x}"))
                .collect::<String>(),
            case["oracle"]["grammar_sha256"].as_str().unwrap()
        );
        let grammar = CompiledGrammar::compile(bytes).unwrap();
        let decoded = CompiledGrammar::from_artifact(&grammar.artifact().unwrap()).unwrap();
        for grammar in [grammar, decoded] {
            let mut session = grammar.session();
            let tree = session.parse(source).unwrap();
            assert_eq!(ledger(&tree), case["expected"], "{}", case["name"]);
            assert!(tree.confidence().is_strict());
            assert!(tree.repairs().is_empty());
            assert!(
                !session
                    .product(&mut grammar.effect_store())
                    .unwrap()
                    .is_zero()
            );
            if case["name"] == "aliases_fields" {
                let query = Query::compile(
                    grammar,
                    b"(call_expression function: (z_function) @function type_arguments: (type_arguments) @type arguments: (arguments) @args)",
                ).unwrap();
                assert!(query.dead_patterns().is_empty());
                let matches = query.execute(&tree, ForeignPolicy::Refuse).unwrap();
                assert_eq!(matches.len(), 1);
                assert_eq!(matches[0].captures.len(), 3);
            }
        }
    }
}

fn repeated_grammar() -> Arc<CompiledGrammar> {
    let case = cases()
        .into_iter()
        .find(|c| c["name"] == "call_first")
        .unwrap();
    let mut grammar: Value = serde_json::from_str(case["grammar"].as_str().unwrap()).unwrap();
    grammar["rules"]["program"] = json!({"type":"REPEAT1","content":{
        "type":"SEQ","members":[{"type":"SYMBOL","name":"_expr"},{"type":"STRING","value":";"}]}});
    CompiledGrammar::compile(&serde_json::to_vec(&grammar).unwrap()).unwrap()
}

#[test]
fn resumed_generic_call_selection_and_measurement_equal_a_cold_document() {
    let grammar = repeated_grammar();
    let source = format!("{}f(\"b\");", "f(\"a\");\n".repeat(48));
    let mut document = Document::new(grammar.clone(), source.as_bytes()).unwrap();
    let previous = Arc::clone(document.snapshot());
    let at = source.len() - "f(\"b\");".len() + 1;
    document
        .edit(ByteSpan::new(at, at).unwrap(), b"<T>")
        .unwrap();
    // Ambiguous resumed reads deliberately fall back to the cold contract;
    // both the attempted materialization and validation remain measured.
    assert_eq!(document.cost().reuse, Reuse::Cold);
    let cold = Document::new(grammar, document.source()).unwrap();
    assert!(document.cost().materialized_nodes > cold.cost().materialized_nodes);
    assert!(document.cost().read_events > cold.cost().read_events);
    assert_eq!(ledger(document.snapshot()), ledger(cold.snapshot()));
    assert_eq!(document.product().unwrap(), cold.product().unwrap());
    assert!(document.snapshot().confidence().is_strict());
    assert_eq!(previous.source(), source.as_bytes());
    let last = document
        .snapshot()
        .root()
        .unwrap()
        .children()
        .rfind(|n| n.is_named())
        .unwrap();
    assert_eq!(last.name(), "call_expression");
    assert!(last.child_by_field("type_arguments").is_some());
}

#[test]
fn a_work_refusal_keeps_the_published_document_snapshot_product_and_cost() {
    let grammar = repeated_grammar();
    let mut document = Document::with_options(
        grammar,
        b"f(\"a\");",
        DocumentOptions {
            limits: ParseLimits {
                steps: 2_000,
                ..ParseLimits::default()
            },
            ..DocumentOptions::default()
        },
    )
    .unwrap();
    let snapshot = Arc::clone(document.snapshot());
    let product = document.product().unwrap();
    let cost = document.cost();
    let larger = "f<T>(\"b\");\n".repeat(64);
    let result = document.edit(
        ByteSpan::new(0, document.source().len()).unwrap(),
        larger.as_bytes(),
    );
    assert!(matches!(
        result,
        Err(DocumentError::Parse(Error::LimitExceeded(Resource::Work)))
    ));
    assert!(Arc::ptr_eq(document.snapshot(), &snapshot));
    assert_eq!(document.source(), b"f(\"a\");");
    assert_eq!(document.product().unwrap(), product);
    assert_eq!(document.cost(), cost);
}

#[test]
fn real_typescript_generic_calls_keep_their_function_types_and_arguments() {
    let bytes = include_bytes!("../../upstream/grammars/typescript.json");
    assert_eq!(
        Sha256::digest(bytes)
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect::<String>(),
        "99dc4b95424dff47c89acb50d5d3f25b081b07eaff43994b7881dccd4186b214"
    );
    let grammar = CompiledGrammar::compile(bytes).unwrap();
    for source in [
        "fetchJson<Shape> (\"/path\");",
        "other<Shape>(\"/path\");",
        "other (\"/path\");",
    ] {
        let tree = grammar.session().parse(source.as_bytes()).unwrap();
        let query = Query::compile(
            grammar.clone(),
            b"(call_expression function: (_) @function arguments: (arguments) @args)",
        )
        .unwrap();
        let found = query.execute(&tree, ForeignPolicy::Refuse).unwrap();
        assert_eq!(found.len(), 1);
        assert_eq!(found[0].captures.len(), 2);
        let mut pending: Vec<Node<'_>> = tree.roots().collect();
        let mut calls = vec![];
        while let Some(node) = pending.pop() {
            assert_ne!(node.name(), "binary_expression");
            if node.name() == "call_expression" {
                calls.push(node);
            }
            pending.extend(node.children());
        }
        assert_eq!(calls.len(), 1);
        assert_eq!(
            calls[0].child_by_field("type_arguments").is_some(),
            source.contains('<')
        );
    }
}
