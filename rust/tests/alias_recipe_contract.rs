//! Independently checked tree-sitter 0.26.11 alias/hidden-token distinctions.
#![forbid(unsafe_code)]

use joints_engine::{CompiledGrammar, ForeignPolicy, Node, Query};
use serde_json::{Value, json};
use std::sync::Arc;

fn view(node: Node<'_>) -> Value {
    json!({"name":node.name(),"named":node.is_named(),"field":node.field(),
        "start":node.span().start(),"end":node.span().end(),
        "kids":node.children().map(view).collect::<Vec<_>>()})
}
fn leaf(name: &str, named: bool, field: Option<&str>, end: usize, kids: Vec<Value>) -> Value {
    json!({"name":name,"named":named,"field":field,"start":0,"end":end,"kids":kids})
}
fn source(body: Value, alias_content: Value, named: bool, field: bool) -> Vec<u8> {
    let alias = json!({"type":"ALIAS","value":"renamed","named":named,"content":alias_content});
    let doc = if field {
        json!({"type":"FIELD","name":"part","content":alias})
    } else {
        alias
    };
    serde_json::to_vec(
        &json!({"name":"alias_recipes","extras":[],"rules":{"doc":doc,"_atom":body}}),
    )
    .unwrap()
}

#[test]
fn hidden_literal_aliases_keep_their_child_through_tokens_fields_and_artifacts() {
    for body in [
        json!({"type":"STRING","value":"x"}),
        json!({"type":"TOKEN","content":{"type":"STRING","value":"x"}}),
        json!({"type":"TOKEN","content":{"type":"ALIAS","content":{"type":"STRING","value":"x"},"named":true,"value":"ignored_inside_token"}}),
        json!({"type":"IMMEDIATE_TOKEN","content":{"type":"PREC","value":2,"content":{"type":"STRING","value":"x"}}}),
    ] {
        for named in [false, true] {
            for field in [false, true] {
                let bytes = source(
                    body.clone(),
                    json!({"type":"SYMBOL","name":"_atom"}),
                    named,
                    field,
                );
                let grammar = CompiledGrammar::compile(&bytes).unwrap();
                let artifact = grammar.artifact().unwrap();
                let loaded = CompiledGrammar::from_artifact(&artifact).unwrap();
                assert_eq!(artifact, loaded.artifact().unwrap());
                for graph in [grammar, loaded] {
                    let tree = graph.session().parse(b"x").unwrap();
                    let expected = leaf(
                        "doc",
                        true,
                        None,
                        1,
                        vec![leaf(
                            "renamed",
                            named,
                            field.then_some("part"),
                            1,
                            vec![leaf("x", false, None, 1, vec![])],
                        )],
                    );
                    assert_eq!(view(tree.root().unwrap()), expected);
                    let question = if named {
                        if field {
                            "(doc part: (renamed \"x\" @literal))"
                        } else {
                            "(renamed \"x\" @literal)"
                        }
                    } else {
                        "\"x\" @literal"
                    };
                    let query = Query::compile(Arc::clone(&graph), question.as_bytes()).unwrap();
                    assert!(query.dead_patterns().is_empty());
                    let matches = query.execute(&tree, ForeignPolicy::Refuse).unwrap();
                    assert_eq!(matches.len(), 1);
                    assert_eq!(matches[0].captures[0].node.name(), "x");
                    assert!(!matches[0].captures[0].node.is_named());
                    assert!(matches[0].captures[0].node.field().is_none());
                    if named && field {
                        let wrong =
                            Query::compile(Arc::clone(&graph), b"(renamed part: \"x\" @literal)")
                                .unwrap();
                        assert_eq!(
                            wrong.dead_patterns().len(),
                            1,
                            "outer field belongs to wrapper"
                        );
                    }
                }
            }
        }
    }
}

#[test]
fn direct_aliases_and_named_or_pattern_tokens_remain_leaves() {
    for (name, body, target) in [
        (
            "_atom",
            json!({"type":"PATTERN","value":"x"}),
            json!({"type":"SYMBOL","name":"_atom"}),
        ),
        (
            "_atom",
            json!({"type":"TOKEN","content":{"type":"SEQ","members":[{"type":"STRING","value":"x"}]}}),
            json!({"type":"SYMBOL","name":"_atom"}),
        ),
        (
            "atom",
            json!({"type":"STRING","value":"x"}),
            json!({"type":"SYMBOL","name":"atom"}),
        ),
        (
            "atom",
            json!({"type":"PATTERN","value":"x"}),
            json!({"type":"SYMBOL","name":"atom"}),
        ),
        (
            "unused",
            json!({"type":"STRING","value":"z"}),
            json!({"type":"STRING","value":"x"}),
        ),
        (
            "unused",
            json!({"type":"STRING","value":"z"}),
            json!({"type":"PATTERN","value":"x"}),
        ),
    ] {
        let mut rules = serde_json::Map::new();
        rules.insert(
            "doc".into(),
            json!({"type":"ALIAS","value":"renamed","named":true,"content":target}),
        );
        rules.insert(name.into(), body);
        let bytes =
            serde_json::to_vec(&json!({"name":"alias_leaf","rules":rules,"extras":[]})).unwrap();
        let grammar = CompiledGrammar::compile(&bytes).unwrap();
        let loaded = CompiledGrammar::from_artifact(&grammar.artifact().unwrap()).unwrap();
        for graph in [grammar, loaded] {
            let tree = graph.session().parse(b"x").unwrap();
            assert_eq!(
                view(tree.root().unwrap()),
                leaf(
                    "doc",
                    true,
                    None,
                    1,
                    vec![leaf("renamed", true, None, 1, vec![])]
                )
            );
        }
    }
}

#[test]
fn alias_recipes_reach_sequence_symbols_but_repetition_owns_its_wrapper() {
    for (content, input, expected) in [
        (
            json!({"type":"FIELD","name":"part","content":{"type":"SYMBOL","name":"_atom"}}),
            b"x".as_slice(),
            leaf(
                "doc",
                true,
                None,
                1,
                vec![leaf(
                    "renamed",
                    true,
                    Some("part"),
                    1,
                    vec![leaf("x", false, None, 1, vec![])],
                )],
            ),
        ),
        (
            json!({"type":"SEQ","members":[{"type":"SYMBOL","name":"_atom"},{"type":"STRING","value":"y"}]}),
            b"xy".as_slice(),
            json!({"name":"doc","named":true,"field":null,"start":0,"end":2,"kids":[leaf("renamed",true,None,1,vec![leaf("x",false,None,1,vec![])]),{"name":"renamed","named":true,"field":null,"start":1,"end":2,"kids":[]}]}),
        ),
        (
            json!({"type":"REPEAT1","content":{"type":"SYMBOL","name":"_atom"}}),
            b"xx".as_slice(),
            leaf(
                "doc",
                true,
                None,
                2,
                vec![leaf(
                    "renamed",
                    true,
                    None,
                    2,
                    vec![
                        leaf("x", false, None, 1, vec![]),
                        json!({"name":"x","named":false,"field":null,"start":1,"end":2,"kids":[]}),
                    ],
                )],
            ),
        ),
    ] {
        let grammar = CompiledGrammar::compile(&source(
            json!({"type":"STRING","value":"x"}),
            content,
            true,
            false,
        ))
        .unwrap();
        let tree = grammar.session().parse(input).unwrap();
        assert_eq!(view(tree.root().unwrap()), expected);
    }
}

#[test]
fn precedence_transmits_an_alias_while_explicit_inline_erases_the_hidden_wrapper() {
    let bytes = source(
        json!({"type":"STRING","value":"x"}),
        json!({"type":"PREC","value":2,"content":{"type":"SYMBOL","name":"_atom"}}),
        true,
        false,
    );
    let graph = CompiledGrammar::compile(&bytes).unwrap();
    let tree = graph.session().parse(b"x").unwrap();
    assert_eq!(
        view(tree.root().unwrap()),
        leaf(
            "doc",
            true,
            None,
            1,
            vec![leaf(
                "renamed",
                true,
                None,
                1,
                vec![leaf("x", false, None, 1, vec![])]
            )]
        )
    );
    let mut inline: Value = serde_json::from_slice(&bytes).unwrap();
    inline["inline"] = json!(["_atom"]);
    let graph = CompiledGrammar::compile(&serde_json::to_vec(&inline).unwrap()).unwrap();
    let tree = graph.session().parse(b"x").unwrap();
    assert_eq!(
        view(tree.root().unwrap()),
        leaf(
            "doc",
            true,
            None,
            1,
            vec![leaf("renamed", true, None, 1, vec![])]
        )
    );
}
