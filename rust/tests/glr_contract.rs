use joints_engine::{CompiledGrammar, Error, Node, ParseLimits, ParseSession, Resource};

fn named(node: Node<'_>) -> String {
    let children: Vec<_> = node
        .children()
        .filter(|n| n.is_named())
        .map(named)
        .collect();
    if children.is_empty() {
        format!("({})", node.name())
    } else {
        format!("({} {})", node.name(), children.join(" "))
    }
}

fn alternatives() -> std::sync::Arc<CompiledGrammar> {
    CompiledGrammar::compile(br#"{"name":"branch","rules":{
      "doc":{"type":"CHOICE","members":[
        {"type":"SEQ","members":[{"type":"SYMBOL","name":"a"},{"type":"STRING","value":"y"}]},
        {"type":"SEQ","members":[{"type":"SYMBOL","name":"b"},{"type":"STRING","value":"y"},{"type":"STRING","value":"z"}]}]},
      "a":{"type":"ALIAS","named":true,"value":"kept","content":{"type":"SYMBOL","name":"item"}},
      "b":{"type":"ALIAS","named":true,"value":"lost","content":{"type":"SYMBOL","name":"item"}},
      "item":{"type":"PATTERN","value":"x"}},"conflicts":[["a","b"]]}"#).unwrap()
}

#[test]
fn later_input_refutes_branches_without_leaking_aliases_or_parent_writes() {
    let grammar = alternatives();
    let mut session = grammar.session();
    let first = session.parse(b"xy").unwrap();
    assert_eq!(named(first.root().unwrap()), "(doc (a (kept)))");
    let second = session.parse(b"xyz").unwrap();
    assert_eq!(named(second.root().unwrap()), "(doc (b (lost)))");
    assert_eq!(named(first.root().unwrap()), "(doc (a (kept)))");
    for tree in [&first, &second] {
        assert!(tree.survey().is_sound());
        assert_eq!(tree.survey().held, tree.survey().walked);
        for branch in tree.root().unwrap().children().filter(|n| n.is_named()) {
            assert_eq!(branch.parent().unwrap().name(), "doc");
            assert_eq!(
                branch.children().next().unwrap().parent().unwrap().name(),
                branch.name()
            );
        }
    }
    assert!(
        !session
            .product(&mut grammar.effect_store())
            .unwrap()
            .is_zero()
    );
}

#[test]
fn dynamic_precedence_in_eof_reductions_outranks_birth_order() {
    let grammar = CompiledGrammar::compile(
        br#"{"name":"dynamic","rules":{
      "doc":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"a"},{"type":"SYMBOL","name":"b"}]},
      "a":{"type":"PREC_DYNAMIC","value":1,"content":{"type":"SYMBOL","name":"item"}},
      "b":{"type":"PREC_DYNAMIC","value":7,"content":{"type":"SYMBOL","name":"item"}},
      "item":{"type":"PATTERN","value":"x"}},"conflicts":[["a","b"]]}"#,
    )
    .unwrap();
    let tree = grammar.session().parse(b"x").unwrap();
    assert_eq!(named(tree.root().unwrap()), "(doc (b (item)))");
}

#[test]
fn heads_lex_their_own_permission_subsets_and_can_advance_different_lengths() {
    let grammar = CompiledGrammar::compile(br#"{"name":"lexical_heads","rules":{
      "doc":{"type":"CHOICE","members":[
        {"type":"SEQ","members":[{"type":"SYMBOL","name":"a"},{"type":"STRING","value":":"},{"type":"STRING","value":"a"},{"type":"STRING","value":"b"},{"type":"CHOICE","members":[{"type":"STRING","value":"x"},{"type":"BLANK"}]}]},
        {"type":"SEQ","members":[{"type":"SYMBOL","name":"b"},{"type":"STRING","value":":"},{"type":"PATTERN","value":"ab"}]}]},
      "a":{"type":"SYMBOL","name":"item"},"b":{"type":"SYMBOL","name":"item"},
      "item":{"type":"STRING","value":"q"}},"conflicts":[["a","b"]]}"#).unwrap();
    let mut session = grammar.session();
    session.set_trace_enabled(true);
    let tree = session.parse(b"q:ab").unwrap();
    // Independent TS 0.26.11 chooses this three-child derivation before
    // comparing the first child's symbol. The former birth policy chose a.
    assert_eq!(named(tree.root().unwrap()), "(doc (b (item)))");
    let children: Vec<_> = tree.root().unwrap().children().map(|n| n.name()).collect();
    assert_eq!(children, ["b", ":"]);
    let spans: Vec<_> = session
        .selected_tokens()
        .unwrap()
        .iter()
        .map(|t| t.span.range())
        .collect();
    assert_eq!(spans, [0..1, 1..2, 2..4]);

    // Here b's longer lexical token cannot finish. Retaining a proves that
    // each reading scans its own subset rather than sharing a global winner.
    let tree = session.parse(b"q:abx").unwrap();
    assert_eq!(named(tree.root().unwrap()), "(doc (a (item)))");
    let children: Vec<_> = tree.root().unwrap().children().map(|n| n.name()).collect();
    assert_eq!(children, ["a", ":", "a", "b", "x"]);
    let spans: Vec<_> = session
        .selected_tokens()
        .unwrap()
        .iter()
        .map(|t| t.span.range())
        .collect();
    assert_eq!(spans, [0..1, 1..2, 2..3, 3..4, 4..5]);
}

#[test]
fn reaching_a_head_limit_is_an_operational_error_even_if_one_branch_could_accept() {
    let grammar = alternatives();
    let mut session = ParseSession::with_limits(
        grammar.clone(),
        ParseLimits {
            heads: 1,
            ..ParseLimits::default()
        },
    );
    assert!(matches!(
        session.parse(b"xy"),
        Err(Error::LimitExceeded(Resource::Heads))
    ));
    assert!(session.product(&mut grammar.effect_store()).is_err());
}

#[test]
fn a_live_reading_budget_counts_coalesced_results_instead_of_duplicate_completions() {
    let grammar = CompiledGrammar::compile(
        br#"{"name":"merge_budget","rules":{
      "doc":{"type":"SEQ","members":[
        {"type":"CHOICE","members":[{"type":"SYMBOL","name":"a"},{"type":"SYMBOL","name":"b"}]},
        {"type":"CHOICE","members":[{"type":"SYMBOL","name":"c"},{"type":"SYMBOL","name":"d"}]}]},
      "a":{"type":"SYMBOL","name":"item"},"b":{"type":"SYMBOL","name":"item"},
      "c":{"type":"SYMBOL","name":"item"},"d":{"type":"SYMBOL","name":"item"},
      "item":{"type":"PATTERN","value":"x"}},"conflicts":[["a","b"],["c","d"]]}"#,
    )
    .unwrap();
    let mut session = ParseSession::with_limits(
        grammar,
        ParseLimits {
            heads: 3,
            ..ParseLimits::default()
        },
    );
    assert!(session.parse(b"xx").unwrap().survey().is_sound());
}

#[test]
fn families_rank_the_actual_production_history_and_dynamic_rank_still_leads() {
    let mut source: serde_json::Value =
        serde_json::from_slice(include_bytes!("fixtures/family-source-order.json")).unwrap();
    let grammar = CompiledGrammar::compile(&serde_json::to_vec(&source).unwrap()).unwrap();
    let mut session = grammar.session();
    let first = session.parse(b"ax").unwrap();
    let call = first.root().unwrap().children().next().unwrap();
    assert_eq!(call.child_by_field("target").unwrap().name(), "A");
    let later = session.parse(b"bx").unwrap();
    let call = later.root().unwrap().children().next().unwrap();
    assert_eq!(
        call.children().map(|n| n.name()).collect::<Vec<_>>(),
        ["B", "tail"]
    );
    assert!(call.children().all(|n| n.field().is_none()));
    let mut effects = grammar.effect_store();
    let product = session.product(&mut effects).unwrap();
    assert!(!product.is_zero());
    assert!(effects.grounded(product).unwrap());
    // Both concrete members of the first family receive the same authored
    // dynamic weight. It must outrank the earlier unweighted actual production.
    for index in [0, 2] {
        let member = source["rules"]["call"]["members"][index].take();
        source["rules"]["call"]["members"][index] =
            serde_json::json!({"type":"PREC_DYNAMIC","value":1,"content":member});
    }
    let ranked = CompiledGrammar::compile(&serde_json::to_vec(&source).unwrap()).unwrap();
    let tree = ranked.session().parse(b"bx").unwrap();
    let call = tree.root().unwrap().children().next().unwrap();
    assert_eq!(call.child_by_field("target").unwrap().name(), "B");
    assert_eq!(call.child_by_field("arg").unwrap().name(), "tail");
    assert_eq!(
        first
            .root()
            .unwrap()
            .children()
            .next()
            .unwrap()
            .child_by_field("target")
            .unwrap()
            .name(),
        "A"
    );
}
