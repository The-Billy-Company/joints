//! Non-SYMBOL extras use the native separate-read lexical contract.
//! TS0.26.11's prefix-separator closure can widen a colliding structural token;
//! that inherited difference is pinned explicitly below, not normalized away.
use joints_engine::{CompileError, CompiledGrammar, Error, ForeignPolicy, Query, QueryError};
use serde_json::{Value, json};

fn grammar(extra: Value) -> Vec<u8> {
    serde_json::to_vec(&json!({"name":"lexical_extra","rules":{"doc":{"type":"SEQ","members":[{"type":"STRING","value":"x"},{"type":"STRING","value":"y"}]}},"extras":[extra,{"type":"PATTERN","value":"[ ]+"}]})).unwrap()
}
fn token(value: &str) -> Value {
    json!({"type":"TOKEN","content":{"type":"STRING","value":value}})
}
fn alias(content: Value, named: bool) -> Value {
    json!({"type":"ALIAS","value":"ignored_extra_name","named":named,"content":content})
}
fn leaves(
    graph: &std::sync::Arc<CompiledGrammar>,
    source: &[u8],
) -> Vec<(String, std::ops::Range<usize>, bool)> {
    let tree = graph.session().parse(source).unwrap();
    assert!(tree.confidence().is_strict());
    tree.root()
        .unwrap()
        .children()
        .map(|n| {
            assert_eq!(n.children().len(), 0);
            (n.name().to_owned(), n.span().range(), n.is_extra())
        })
        .collect()
}

#[test]
fn atomic_literal_separators_are_invisible_and_keep_their_own_identity() {
    for extra in [
        token("x"),
        alias(token("x"), true),
        alias(token("x"), false),
        json!({"type":"TOKEN","content":alias(json!({"type":"STRING","value":"x"}),true)}),
    ] {
        let graph = CompiledGrammar::compile(&grammar(extra)).unwrap();
        let bytes = graph.artifact().unwrap();
        let loaded = CompiledGrammar::from_artifact(&bytes).unwrap();
        assert_eq!(bytes, loaded.artifact().unwrap());
        for graph in [graph, loaded] {
            assert_eq!(
                leaves(&graph, b"xy"),
                [("x".into(), 0..1, false), ("y".into(), 1..2, false)]
            );
            // Native extras are separate lexical reads. TS0.26.11 reports its
            // one structural x at0..3 for this source; native retains0..1 and
            // omits the two separator reads. Both require a structural x.
            assert_eq!(
                leaves(&graph, b"xxxy"),
                [("x".into(), 0..1, false), ("y".into(), 3..4, false)]
            );
            assert!(graph.session().parse(b"y").is_err());
            assert!(matches!(
                Query::compile(graph.clone(), b"(ignored_extra_name) @extra"),
                Err(QueryError::UnknownName { .. })
            ));
            let question = Query::compile(graph.clone(), b"(doc \"x\" @value)").unwrap();
            assert!(question.dead_patterns().is_empty());
            let tree = graph.session().parse(b"xxxy").unwrap();
            assert_eq!(
                question
                    .execute(&tree, ForeignPolicy::Refuse)
                    .unwrap()
                    .len(),
                1
            );
        }
    }
    let bare = CompiledGrammar::compile(&grammar(json!({"type":"STRING","value":"x"}))).unwrap();
    assert_eq!(
        leaves(&bare, b"xxxy"),
        [
            ("x".into(), 0..1, false),
            ("x".into(), 1..2, true),
            ("x".into(), 2..3, true),
            ("y".into(), 3..4, false)
        ]
    );
    assert!(bare.session().parse(b"y").is_err());
}

#[test]
fn a_private_separator_does_not_turn_an_owned_named_literal_into_a_wrapper() {
    let bytes=serde_json::to_vec(&json!({"name":"owned_extra_literal","rules":{"doc":{"type":"SYMBOL","name":"item"},"item":token("x")},"extras":[alias(token("x"),true)]})).unwrap();
    let graph = CompiledGrammar::compile(&bytes).unwrap();
    let loaded = CompiledGrammar::from_artifact(&graph.artifact().unwrap()).unwrap();
    for graph in [graph, loaded] {
        let tree = graph.session().parse(b"xxx").unwrap();
        let item = tree.root().unwrap().children().next().unwrap();
        assert_eq!(
            (item.name(), item.span().range(), item.children().len()),
            ("item", 0..1, 0)
        );
    }
}

#[test]
fn regex_alias_separators_stay_invisible_but_symbol_extras_keep_their_nodes() {
    for named in [false, true] {
        let bytes=serde_json::to_vec(&json!({"name":"regex_extra","rules":{"doc":{"type":"SEQ","members":[{"type":"STRING","value":"("},{"type":"STRING","value":"x"},{"type":"STRING","value":")"}]}},"extras":[alias(json!({"type":"TOKEN","content":{"type":"PATTERN","value":"#[a-z]+"}}),named),{"type":"PATTERN","value":"[ ]+"}]})).unwrap();
        let graph = CompiledGrammar::compile(&bytes).unwrap();
        let loaded = CompiledGrammar::from_artifact(&graph.artifact().unwrap()).unwrap();
        for graph in [graph, loaded] {
            assert_eq!(
                leaves(&graph, b"(#first x#last)"),
                [
                    ("(".into(), 0..1, false),
                    ("x".into(), 8..9, false),
                    (")".into(), 14..15, false)
                ]
            );
        }
    }
    let graph=CompiledGrammar::compile(br##"{"rules":{"doc":{"type":"SEQ","members":[{"type":"STRING","value":"x"},{"type":"STRING","value":"y"}]},"comment":{"type":"TOKEN","content":{"type":"PATTERN","value":"#[a-z]+"}}},"extras":[{"type":"SYMBOL","name":"comment"},{"type":"PATTERN","value":"[ ]+"}]}"##).unwrap();
    assert_eq!(
        leaves(&graph, b"#a xy#b"),
        [
            ("comment".into(), 0..2, true),
            ("x".into(), 3..4, false),
            ("y".into(), 4..5, false),
            ("comment".into(), 5..7, true),
        ]
    );
}

#[test]
fn separator_precedence_immediacy_and_malformed_metadata_remain_checked() {
    for (precedence, accepted) in [(-1, true), (1, false)] {
        let extra = alias(
            json!({"type":"TOKEN","content":{"type":"PREC","value":precedence,"content":{"type":"STRING","value":"x"}}}),
            true,
        );
        let graph = CompiledGrammar::compile(&grammar(extra)).unwrap();
        assert_eq!(graph.session().parse(b"xy").is_ok(), accepted);
    }
    let immediate = CompiledGrammar::compile(&grammar(
        json!({"type":"IMMEDIATE_TOKEN","content":{"type":"STRING","value":"x"}}),
    ))
    .unwrap();
    assert!(immediate.session().parse(b"x x y").is_err());
    assert!(immediate.session().parse(b"xx y").is_ok());
    let plain = CompiledGrammar::compile(&grammar(token("x"))).unwrap();
    assert!(plain.session().parse(b"x x y").is_ok());
    for extra in [
        json!({"type":"ALIAS","content":token("x"),"named":true}),
        json!({"type":"ALIAS","value":"extra","content":token("x"),"named":"true"}),
    ] {
        assert!(matches!(
            CompiledGrammar::compile(&grammar(extra)),
            Err(Error::Compile(CompileError::Malformed(_)))
        ));
    }
    let symbol_alias=br##"{"rules":{"doc":{"type":"STRING","value":"x"},"comment":{"type":"TOKEN","content":{"type":"PATTERN","value":"#[a-z]+"}}},"extras":[{"type":"ALIAS","named":true,"value":"renamed","content":{"type":"SYMBOL","name":"comment"}}]}"##;
    assert!(matches!(
        CompiledGrammar::compile(symbol_alias),
        Err(Error::Compile(CompileError::Unsupported(_)))
    ));
}
