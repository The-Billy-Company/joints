use std::sync::{Arc, OnceLock};

use joints_engine::{
    CompiledGrammar, DeadCause, ForeignPolicy, Query, QueryArgument, QueryError, QueryLimits,
};

fn json() -> Arc<CompiledGrammar> {
    static GRAMMAR: OnceLock<Arc<CompiledGrammar>> = OnceLock::new();
    GRAMMAR
        .get_or_init(|| {
            CompiledGrammar::compile(include_bytes!("../../test/grammar/json.json")).unwrap()
        })
        .clone()
}

fn captures(source: &[u8], query: &str) -> Vec<Vec<(String, Vec<u8>)>> {
    let grammar = json();
    let tree = grammar.session().parse(source).unwrap();
    let query = Query::compile(grammar, query.as_bytes()).unwrap();
    query
        .execute(&tree, ForeignPolicy::Refuse)
        .unwrap()
        .into_iter()
        .map(|m| {
            m.captures
                .into_iter()
                .map(|c| {
                    (
                        query.capture_name(c.id).unwrap().to_owned(),
                        c.node.text().to_vec(),
                    )
                })
                .collect()
        })
        .collect()
}

fn texts(source: &[u8], query: &str) -> Vec<Vec<String>> {
    captures(source, query)
        .into_iter()
        .map(|m| {
            m.into_iter()
                .map(|(_, text)| String::from_utf8(text).unwrap())
                .collect()
        })
        .collect()
}

#[test]
fn binding_queries_preserve_counts_names_order_predicates_and_empty_answers() {
    let grammar = json();
    let tree = grammar.session().parse(b"[1,2,3]").unwrap();
    let query = Query::compile(grammar.clone(), b"(number) @n").unwrap();
    assert_eq!(query.capture_names(), ["n"]);
    let matches = query.execute(&tree, ForeignPolicy::Refuse).unwrap();
    assert_eq!(matches.len(), 3);
    assert_eq!(
        matches
            .iter()
            .map(|m| m.captures[0].node.text())
            .collect::<Vec<_>>(),
        [b"1", b"2", b"3"]
    );
    assert_eq!(texts(b"[1,2,3]", "((number) @n (#eq? @n \"2\"))"), [["2"]]);
    assert!(texts(b"[1,2,3]", "(object) @object").is_empty());
    assert!(matches!(
        Query::compile(grammar, b"(unrecognized_kind) @n"),
        Err(QueryError::UnknownName { .. })
    ));
    assert_eq!(
        texts(
            br#"{"x":[1,2,3]}"#,
            "(document (object (pair value: (array (number) @n))))"
        ),
        [["1"], ["2"], ["3"]]
    );
}

#[test]
fn wildcard_sort_literals_fields_and_supertype_membership_are_distinct() {
    let source = br#"{"a": 1, "b": true}"#;
    assert_eq!(texts(source, "(_) @a").len(), 10);
    assert_eq!(texts(source, "_ @a").len(), 19);
    assert_eq!(texts(source, "\",\" @comma"), [[","]]);
    assert_eq!(texts(source, "\":\" @colon"), [[":"], [":"]]);
    assert_eq!(texts(source, "(_value) @v").len(), 5);
    assert_eq!(texts(source, "(_value/_) @v").len(), 5);
    let duplicate = captures(b"1", "(number) @n @n");
    assert_eq!(
        duplicate,
        [vec![
            ("n".into(), b"1".to_vec()),
            ("n".into(), b"1".to_vec())
        ]]
    );
    assert_eq!(texts(source, "(_value/number) @v"), [["1"]]);
    assert_eq!(
        texts(source, "(pair key: (string) @k)"),
        [["\"a\""], ["\"b\""]]
    );
    assert!(texts(source, "(pair value: (string) @v)").is_empty());
}

#[test]
fn absent_fields_and_dead_patterns_preserve_source_indices() {
    let grammar = json();
    assert!(matches!(
        Query::compile(grammar.clone(), b"(pair !missing) @p"),
        Err(QueryError::UnknownName { sort: "field", .. })
    ));
    assert_eq!(texts(br#"{"a":1}"#, "(object !value) @o").len(), 1);
    assert!(texts(br#"{"a":1}"#, "(pair !value) @p").is_empty());
    let source = b"; first impossible\n(string key: (string_content)) @dead\n(number) @n";
    let query = Query::compile(grammar.clone(), source).unwrap();
    assert_eq!(query.pattern_count(), 2);
    assert_eq!(query.dead_patterns().len(), 1);
    assert_eq!(query.dead_patterns()[0].cause, DeadCause::FieldNotCarried);
    assert_eq!(query.dead_patterns()[0].pattern.index(), 0);
    assert_eq!(query.pattern_start(query.pattern_id(1).unwrap()), Some(56));
    let tree = grammar.session().parse(b"1").unwrap();
    assert_eq!(
        query.execute(&tree, ForeignPolicy::Refuse).unwrap()[0]
            .pattern
            .index(),
        1
    );
    let dead = Query::compile(grammar, b"(_value/pair) @p").unwrap();
    assert_eq!(dead.dead_patterns()[0].cause, DeadCause::CategoryNotMember);
}

#[test]
fn anchors_quantifiers_choices_and_groups_observe_named_siblings() {
    let source = br#"{"a":1,"b":true}"#;
    assert_eq!(texts(source, "(object . (pair) @p)"), [["\"a\":1"]]);
    assert_eq!(texts(source, "(object (pair) @p .)"), [["\"b\":true"]]);
    assert!(texts(source, "(object . (pair) @p .)").is_empty());
    assert_eq!(
        texts(source, "(object (pair)+ @p)"),
        [["\"a\":1", "\"b\":true"]]
    );
    assert_eq!(texts(b"{}", "(object (pair)* @p)"), [Vec::<String>::new()]);
    assert_eq!(texts(source, "[(number) (true)] @lit"), [["1"], ["true"]]);
    assert_eq!(texts(b"1", "[(number) (number)] @n"), [["1"]]);
    assert_eq!(
        texts(source, "((pair) @x (pair) @y)"),
        [["\"a\":1", "\"b\":true"]]
    );
    assert_eq!(
        texts(b"[1,true,2,true]", "(array ((number) @a (true) @b)+)"),
        [["1", "true", "2", "true"]]
    );
    assert_eq!(
        texts(b"[[1,2],[3,4]]", "(array ((array (number) @n))+)"),
        [["1", "3"]]
    );
    assert_eq!(
        texts(b"[1,2,3]", "(array ((number) @a (number) @b))"),
        [["1", "2"], ["1", "3"], ["2", "3"]]
    );
}

#[test]
fn nested_continuations_enumerate_all_complete_sibling_assignments() {
    assert_eq!(
        texts(
            b"[[1,2],[3,4]]",
            "(array (array (number) @a) (array (number) @b))"
        ),
        [["1", "3"], ["2", "3"], ["1", "4"], ["2", "4"]]
    );
    assert_eq!(
        texts(
            br#"{"a":[1,2,3]}"#,
            "(pair key: (string) @k value: (array (number) @n))"
        ),
        [["\"a\"", "1"], ["\"a\"", "2"], ["\"a\"", "3"]]
    );
    assert_eq!(
        texts(
            br#"{"a":[1],"b":[]}"#,
            "(pair key: (string) @k value: (array (number)* @n))"
        ),
        vec![vec!["\"a\"", "1"], vec!["\"b\""]]
    );
    let grammar = json();
    let tree = grammar.session().parse(b"[1,2]").unwrap();
    let query = Query::compile(grammar, b"(number) @n\n(array (number) @v)").unwrap();
    let matches = query.execute(&tree, ForeignPolicy::Refuse).unwrap();
    assert_eq!(
        matches
            .iter()
            .map(|m| m.pattern.index())
            .collect::<Vec<_>>(),
        [1, 0, 1, 0]
    );
    assert_eq!(
        matches[0].captures[0].node.index(),
        matches[1].captures[0].node.index()
    );
}

#[test]
fn six_predicates_and_optional_unbound_captures_follow_byte_semantics() {
    let source = br#"{"a":1,"b":true}"#;
    for (predicate, expected) in [
        ("#eq? @c \"a\"", vec![vec!["a"]]),
        ("#not-eq? @c \"b\"", vec![vec!["a"]]),
        ("#any-of? @c \"b\" \"z\"", vec![vec!["b"]]),
        ("#not-any-of? @c \"b\" \"z\"", vec![vec!["a"]]),
        ("#match? @c \"^[ab]$\"", vec![vec!["a"], vec!["b"]]),
        ("#not-match? @c \"^a$\"", vec![vec!["b"]]),
    ] {
        assert_eq!(
            texts(source, &format!("((string_content) @c ({predicate}))")),
            expected,
            "{predicate}"
        );
    }
    assert_eq!(
        texts(
            br#"{"a":"a","b":"c"}"#,
            "((pair key: (string (string_content) @a) value: (string (string_content) @b)) (#eq? @a @b))"
        ),
        [["a", "a"]]
    );
    assert_eq!(
        texts(b"[]", "((array (number)? @n) (#eq? @n \"anything\"))"),
        [Vec::<String>::new()]
    );
    // Filtering a greedy assignment never shortens it to satisfy its predicate.
    assert!(texts(b"[1,2]", "((array (number)+ @n) (#eq? @n \"2\"))").is_empty());
}

#[test]
fn directives_and_foreign_filters_are_eager_and_never_publish_partial_results() {
    let grammar = json();
    let tree = grammar.session().parse(b"[1,2]").unwrap();
    let source = b"(number) @plain\n((number) @n (#host-filter? @n))";
    let query = Query::compile(grammar.clone(), source).unwrap();
    assert!(matches!(
        query.execute(&tree, ForeignPolicy::Refuse),
        Err(QueryError::ForeignPredicate { .. })
    ));
    assert_eq!(query.execute(&tree, ForeignPolicy::Admit).unwrap().len(), 4);
    assert_eq!(query.execute(&tree, ForeignPolicy::Deny).unwrap().len(), 2);
    let query = Query::compile(
        grammar.clone(),
        b"((number) @n (#set! injection.language \"json\"))",
    )
    .unwrap();
    assert_eq!(query.execute(&tree, ForeignPolicy::Deny).unwrap().len(), 2);
    let predicate = &query.predicates(query.pattern_id(0).unwrap()).unwrap()[0];
    assert_eq!(predicate.name, "set!");
    assert_eq!(
        predicate.arguments,
        [
            QueryArgument::Text(b"injection.language".to_vec()),
            QueryArgument::Text(b"json".to_vec())
        ]
    );
    let query = Query::compile(grammar, b"(number) @n\n[((number)) (true)] @x").unwrap();
    assert!(matches!(
        query.execute(&tree, ForeignPolicy::Admit),
        Err(QueryError::UnsupportedChoiceGroup { .. })
    ));
}

#[test]
fn syntax_predicate_sort_and_pattern_local_capture_errors_are_compilation_errors() {
    let grammar = json();
    for source in [
        "(",
        "[",
        "(number",
        "(number))",
        "(number) @",
        "(number) +",
        ". (number)",
        "_foo",
        "(#eq? @n \"x\")",
        "(array . . (number))",
    ] {
        assert!(
            Query::compile(grammar.clone(), source.as_bytes()).is_err(),
            "{source}"
        );
    }
    for source in [
        "((number) @n (#eq? @n))",
        "((number) @n (#eq? \"1\" @n))",
        "((number) @n (#match? @n @n))",
        "((number) @n (#any-of? @n @n))",
        "(number) @n\n((true) @b (#eq? @n \"1\"))",
        "((number) @n (#match? @n \"[\"))",
    ] {
        assert!(
            Query::compile(grammar.clone(), source.as_bytes()).is_err(),
            "{source}"
        );
    }
    let query = Query::compile(grammar.clone(), b"(number) @n").unwrap();
    let other = CompiledGrammar::compile(include_bytes!("../../test/grammar/json.json")).unwrap();
    let tree = other.session().parse(b"1").unwrap();
    assert!(matches!(
        query.execute(&tree, ForeignPolicy::Refuse),
        Err(QueryError::ForeignGrammar)
    ));
}

#[test]
fn all_search_and_regex_limits_fail_without_partial_publication() {
    let grammar = json();
    let tree = grammar.session().parse(b"[1,2,3]").unwrap();
    let query = Query::compile(grammar.clone(), b"(number) @n").unwrap();
    for limits in [
        QueryLimits {
            work: 1,
            ..QueryLimits::default()
        },
        QueryLimits {
            matches: 1,
            ..QueryLimits::default()
        },
        QueryLimits {
            captures: 1,
            ..QueryLimits::default()
        },
        QueryLimits {
            depth: 1,
            ..QueryLimits::default()
        },
    ] {
        assert!(matches!(
            query.execute_with_limits(&tree, ForeignPolicy::Refuse, limits),
            Err(QueryError::Limit(_))
        ));
    }
    assert!(matches!(
        Query::compile_with_limits(
            grammar.clone(),
            b"(number)",
            QueryLimits {
                work: 0,
                ..QueryLimits::default()
            }
        ),
        Err(QueryError::Limit(_))
    ));
    let mut limits = QueryLimits::default();
    limits.regex.match_steps = 1;
    for name in ["match?", "not-match?"] {
        let query = Query::compile_with_limits(
            grammar.clone(),
            format!("((number) @n (#{name} @n \"(?:1+)+$\"))").as_bytes(),
            limits,
        )
        .unwrap();
        assert!(matches!(
            query.execute(&tree, ForeignPolicy::Refuse),
            Err(QueryError::Regex { .. })
        ));
    }
    // A repeated nullable group has an explicit zero-progress stop.
    assert!(
        Query::compile(grammar, b"(array ((number)?)*)")
            .unwrap()
            .execute(&tree, ForeignPolicy::Refuse)
            .is_ok()
    );
}

#[test]
fn aliases_sorts_hidden_fields_and_named_extra_anchors_are_generic() {
    let grammar = CompiledGrammar::compile(br##"{"name":"query_aliases","rules":{
      "doc":{"type":"SEQ","members":[{"type":"FIELD","name":"left","content":{"type":"ALIAS","named":true,"value":"renamed","content":{"type":"SYMBOL","name":"item"}}},{"type":"STRING","value":":"},{"type":"SYMBOL","name":"item"}]},
      "item":{"type":"PATTERN","value":"[a-z]+"},"comment":{"type":"PATTERN","value":"#[^\\n]*"}},
      "extras":[{"type":"PATTERN","value":"\\s"},{"type":"SYMBOL","name":"comment"}]}"##).unwrap();
    let tree = grammar.session().parse(b"a: #between\nb").unwrap();
    let run = |source: &[u8]| {
        Query::compile(grammar.clone(), source)
            .unwrap()
            .execute(&tree, ForeignPolicy::Refuse)
            .unwrap()
    };
    assert_eq!(run(b"(renamed) @r").len(), 1);
    assert_eq!(run(b"(item) @i").len(), 1);
    assert_eq!(run(b"(doc left: (renamed) @r)").len(), 1);
    assert_eq!(run(b"(doc (renamed) @r . (item) @i)").len(), 0);
    assert_eq!(run(b"(doc (renamed) @r (item) @i)").len(), 1);
    assert_eq!(run(b"(comment) @c")[0].captures[0].node.text(), b"#between");
}

#[test]
fn pinned_tree_sitter_matrix_has_45_exact_questions_and_four_named_contract_differences() {
    use sha2::{Digest, Sha256};
    let hash = |bytes: &[u8]| {
        Sha256::digest(bytes)
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect::<String>()
    };
    let fixture: serde_json::Value =
        serde_json::from_slice(include_bytes!("fixtures/query-oracle.json")).unwrap();
    let differences: serde_json::Value =
        serde_json::from_slice(include_bytes!("fixtures/query-contract-differences.json")).unwrap();
    assert_eq!(fixture["schema"], 1);
    assert_eq!(differences["schema"], 1);
    assert!(
        fixture["oracle"]
            .as_str()
            .unwrap()
            .starts_with("tree-sitter 0.26.11")
    );
    assert_eq!(
        fixture["grammar_sha256"],
        hash(include_bytes!("../../test/grammar/json.json"))
    );
    assert_eq!(differences["grammar_sha256"], fixture["grammar_sha256"]);
    let cases = fixture["cases"].as_array().unwrap();
    let known = differences["cases"].as_array().unwrap();
    assert_eq!((cases.len(), known.len()), (49, 4));
    let grammar = json();
    let mut exact = 0;
    let mut named = 0;
    let mut match_count = 0;
    let mut capture_count = 0;
    for case in cases {
        let source = case["source"].as_str().unwrap().as_bytes();
        let query_source = case["query"].as_str().unwrap().as_bytes();
        let tree = grammar.session().parse(source).unwrap();
        assert!(tree.confidence().is_strict(), "{}", case["case"]);
        let query = Query::compile(grammar.clone(), query_source).unwrap();
        let matches = query.execute(&tree, ForeignPolicy::Admit).unwrap();
        match_count += matches.len();
        let actual: Vec<_> = matches.iter().map(|m| {
            capture_count += m.captures.len();
            serde_json::json!({"pattern":m.pattern.index(),"captures":m.captures.iter().map(|c| serde_json::json!({"name":query.capture_name(c.id).unwrap(),"start":c.node.span().start(),"end":c.node.span().end()})).collect::<Vec<_>>()})
        }).collect();
        let actual = serde_json::Value::Array(actual);
        if let Some(contract) = known.iter().find(|d| d["case"] == case["case"]) {
            named += 1;
            assert_eq!(contract["source_sha256"], hash(source));
            assert_eq!(contract["query_sha256"], hash(query_source));
            assert_eq!(contract["oracle_stdout_sha256"], case["raw_stdout_sha256"]);
            assert_ne!(contract["native_matches"], case["matches"]);
            assert_eq!(actual, contract["native_matches"], "{}", case["case"]);
        } else {
            exact += 1;
            assert_eq!(
                actual, case["matches"],
                "{}: {}",
                case["case"], case["query"]
            );
        }
    }
    assert_eq!((exact, named, match_count, capture_count), (45, 4, 98, 125));
}

#[test]
fn dead_patterns_and_empty_predicate_candidates_consume_execution_work() {
    let grammar = json();
    let tree = grammar.session().parse(b"[1,2,3]").unwrap();
    let source = "(number key: (number)) ".repeat(256);
    let query = Query::compile(grammar.clone(), source.as_bytes()).unwrap();
    assert_eq!(query.dead_patterns().len(), 256);
    assert!(
        query
            .execute(&tree, ForeignPolicy::Refuse)
            .unwrap()
            .is_empty()
    );
    assert!(matches!(
        query.execute_with_limits(
            &tree,
            ForeignPolicy::Refuse,
            QueryLimits {
                work: 200,
                ..QueryLimits::default()
            }
        ),
        Err(QueryError::Limit("work"))
    ));
    for name in ["any-of?", "not-any-of?"] {
        let source = format!("((number) @n (#{name} @n {}))", "\"\" ".repeat(256));
        let query = Query::compile(grammar.clone(), source.as_bytes()).unwrap();
        assert!(query.execute(&tree, ForeignPolicy::Refuse).is_ok());
        assert!(matches!(
            query.execute_with_limits(
                &tree,
                ForeignPolicy::Refuse,
                QueryLimits {
                    work: 200,
                    ..QueryLimits::default()
                }
            ),
            Err(QueryError::Limit("work"))
        ));
    }
}

#[test]
fn resolved_alias_sets_are_charged_before_every_owned_copy() {
    let mut rules = serde_json::Map::new();
    let members: Vec<_> = (0..400).map(|i| serde_json::json!({"type":"ALIAS","named":true,"value":"shared","content":{"type":"SYMBOL","name":format!("leaf_{i}")}})).collect();
    rules.insert(
        "doc".into(),
        serde_json::json!({"type":"CHOICE","members":members}),
    );
    for i in 0..400 {
        rules.insert(
            format!("leaf_{i}"),
            serde_json::json!({"type":"STRING","value":format!("a{i}")}),
        );
    }
    let bytes =
        serde_json::to_vec(&serde_json::json!({"name":"alias_budget","rules":rules})).unwrap();
    let grammar = CompiledGrammar::compile(&bytes).unwrap();
    let limits = QueryLimits {
        work: 20_000,
        ..QueryLimits::default()
    };
    Query::compile_with_limits(grammar.clone(), b"(shared)", limits).unwrap();
    let source = "(shared) ".repeat(200);
    assert!(matches!(
        Query::compile_with_limits(grammar.clone(), source.as_bytes(), limits),
        Err(QueryError::Limit("work"))
    ));
    assert_eq!(
        Query::compile(grammar, source.as_bytes())
            .unwrap()
            .pattern_count(),
        200
    );
}

#[test]
fn named_and_anonymous_aliases_share_spelling_without_sharing_sort_or_original_name() {
    let grammar = CompiledGrammar::compile(br#"{"name":"sorts","rules":{
      "doc":{"type":"SEQ","members":[{"type":"SYMBOL","name":"word"},{"type":"STRING","value":":"},{"type":"STRING","value":"word"},{"type":"STRING","value":";"},{"type":"ALIAS","named":true,"value":"both","content":{"type":"SYMBOL","name":"atom"}},{"type":"STRING","value":","},{"type":"ALIAS","named":false,"value":"both","content":{"type":"SYMBOL","name":"atom"}}]},
      "word":{"type":"STRING","value":"if"},"atom":{"type":"PATTERN","value":"[a-z]+"}}}"#).unwrap();
    let tree = grammar.session().parse(b"if:word;a,b").unwrap();
    for (source, text, named) in [
        ("(word) @x", b"if".as_slice(), true),
        ("\"word\" @x", b"word".as_slice(), false),
        ("(both) @x", b"a".as_slice(), true),
        ("\"both\" @x", b"b".as_slice(), false),
    ] {
        let query = Query::compile(grammar.clone(), source.as_bytes()).unwrap();
        let matches = query.execute(&tree, ForeignPolicy::Refuse).unwrap();
        assert_eq!(matches.len(), 1, "{source}");
        assert_eq!(matches[0].captures[0].node.text(), text);
        assert_eq!(matches[0].captures[0].node.is_named(), named);
    }
    let query = Query::compile(grammar, b"(atom) @x").unwrap();
    assert!(
        query
            .execute(&tree, ForeignPolicy::Refuse)
            .unwrap()
            .is_empty()
    );
}

#[test]
fn fixed_point_and_dead_checks_preserve_optional_choices_and_extra_children() {
    let grammar = json();
    let tree = grammar.session().parse(b"[1,/*comment*/2]").unwrap();
    for source in [
        "(array (comment) @c)",
        "(array [(pair) (number)] @n)",
        "(array (pair)? @p (number) @n)",
        "(array (pair)* @p (number) @n)",
        "(array ((number) @n))",
    ] {
        let query = Query::compile(grammar.clone(), source.as_bytes()).unwrap();
        assert!(query.dead_patterns().is_empty(), "{source}");
        assert!(
            !query
                .execute(&tree, ForeignPolicy::Refuse)
                .unwrap()
                .is_empty(),
            "{source}"
        );
    }
    let query = Query::compile(grammar.clone(), b"(string (number))").unwrap();
    assert_eq!(query.dead_patterns()[0].cause, DeadCause::ChildNotAdmitted);
    let query = Query::compile(
        grammar,
        b"((number) @n (#host? @elsewhere) (#set! @also_elsewhere))",
    )
    .unwrap();
    assert_eq!(query.capture_names(), ["n", "elsewhere", "also_elsewhere"]);
    assert_eq!(query.execute(&tree, ForeignPolicy::Admit).unwrap().len(), 2);
}

#[test]
fn queries_read_retained_bytes_and_are_shareable_between_workers() {
    fn send_sync<T: Send + Sync>() {}
    send_sync::<Query>();
    let grammar = json();
    let tree = grammar.session().parse("\"é\"".as_bytes()).unwrap();
    let query = Query::compile(
        grammar.clone(),
        br#"((string_content) @c (#match? @c "\\xC3\\xA9"))"#,
    )
    .unwrap();
    let matches = query.execute(&tree, ForeignPolicy::Refuse).unwrap();
    assert_eq!(matches[0].captures[0].node.text(), "é".as_bytes());
    let partial = grammar
        .session()
        .parse_partial(&[b'[', b'1', b']', 0xff])
        .unwrap();
    let numeric = Query::compile(grammar, br#"((number) @n (#match? @n "1"))"#).unwrap();
    assert_eq!(partial.source(), &[b'[', b'1', b']', 0xff]);
    // A diagnostic forest still retains arbitrary bytes; query execution does
    // not require converting the complete source to a UTF-8 string.
    numeric.execute(&partial, ForeignPolicy::Refuse).unwrap();
    let query = Arc::new(query);
    let tree = Arc::new(tree);
    let workers: Vec<_> = (0..4)
        .map(|_| {
            let query = query.clone();
            let tree = tree.clone();
            std::thread::spawn(move || {
                for _ in 0..16 {
                    assert_eq!(
                        query.execute(&tree, ForeignPolicy::Refuse).unwrap().len(),
                        1
                    );
                }
            })
        })
        .collect();
    for worker in workers {
        worker.join().unwrap();
    }
}
