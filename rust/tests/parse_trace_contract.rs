use joints_engine::{
    CompileOptions, CompiledGrammar, Error, ParseLimits, ParseSession, Recovery, Supply,
    effects::{Effect, EffectDescription, EffectError},
};

#[test]
fn selected_token_receipts_keep_pre_lookahead_entries_and_exact_source_extents() {
    let grammar = CompiledGrammar::compile(include_bytes!("../../test/grammar/json.json")).unwrap();
    let mut session = grammar.session();
    session.parse(b"[1]").unwrap();
    assert!(session.selected_tokens().is_none());
    session.set_trace_enabled(true);
    let source = b" \n[1,2]";
    let tree = session.parse(source).unwrap();
    assert!(tree.confidence().is_strict());
    let tokens = session.selected_tokens().unwrap();
    assert_eq!(tokens.len(), 5);
    assert_eq!(
        tokens.iter().map(|t| t.span.range()).collect::<Vec<_>>(),
        [2..3, 3..4, 4..5, 5..6, 6..7]
    );
    assert!(tokens.iter().any(|t| t.entry != t.from));
    assert!(
        tokens
            .iter()
            .all(|t| !t.supplied && t.moves.start < t.moves.end)
    );
    assert!(
        tokens
            .windows(2)
            .all(|pair| pair[0].moves.end == pair[1].moves.start)
    );
    assert!(session.token_reads() >= tokens.len());
    let mut store = grammar.effect_store();
    let mut pieces = Vec::new();
    for token in tokens {
        let (product, work) = session
            .product_range(token.moves.clone(), &mut store, 100_000)
            .unwrap();
        assert!(work > 0);
        pieces.push(product);
        assert!(
            matches!(store.describe(product).unwrap(), EffectDescription::Run { entry, .. } if entry == token.entry)
        );
    }
    let (prefix, _) = session
        .product_range(0..tokens.last().unwrap().moves.end, &mut store, 100_000)
        .unwrap();
    assert_eq!(store.fold(pieces).unwrap(), prefix);
    let whole = session.product(&mut store).unwrap();
    assert_ne!(prefix, whole, "EOF reductions are outside the token stream");
    assert!(store.grounded(whole).unwrap());
}

#[test]
fn actual_move_range_checks_bounds_grammar_and_finite_work_before_shortcuts() {
    let grammar = CompiledGrammar::compile(include_bytes!("../../test/grammar/json.json")).unwrap();
    let mut session = grammar.session();
    let mut store = grammar.effect_store();
    assert_eq!(
        session.product_range(0..0, &mut store, 0),
        Err(EffectError::UnfinishedRun)
    );
    session.set_trace_enabled(true);
    session.parse(b"1").unwrap();
    assert_eq!(
        session.product_range(0..0, &mut store, 0).unwrap(),
        (Effect::IDENTITY, 0)
    );
    assert_eq!(
        session.product_range(0..usize::MAX, &mut store, usize::MAX),
        Err(EffectError::InvalidTraceRange)
    );
    let range = session.selected_tokens().unwrap()[0].moves.clone();
    assert_eq!(
        session.product_range(range, &mut store, 0),
        Err(EffectError::TraceWorkLimit)
    );
    let other = CompiledGrammar::compile(include_bytes!("../../test/grammar/json.json")).unwrap();
    assert_eq!(
        session.product_range(0..0, &mut other.effect_store(), 0),
        Err(EffectError::ForeignAutomaton)
    );
    let mut limited = ParseSession::with_limits(
        grammar,
        ParseLimits {
            source_bytes: 2,
            ..ParseLimits::default()
        },
    );
    limited.set_trace_enabled(true);
    limited.parse(b"1").unwrap();
    assert!(limited.selected_tokens().is_some());
    assert!(matches!(
        limited.parse(b"[1]"),
        Err(Error::SourceTooLarge { .. })
    ));
    assert!(limited.selected_tokens().is_none());
}

#[test]
fn selected_path_discards_losing_glr_histories_and_excludes_named_extras() {
    let grammar = CompiledGrammar::compile(br#"{"name":"trace_branch","rules":{
      "doc":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"SYMBOL","name":"a"},{"type":"STRING","value":"y"}]},{"type":"SEQ","members":[{"type":"SYMBOL","name":"b"},{"type":"STRING","value":"y"},{"type":"STRING","value":"z"}]}]},
      "a":{"type":"SYMBOL","name":"item"},"b":{"type":"SYMBOL","name":"item"},"item":{"type":"STRING","value":"x"},"comment":{"type":"PATTERN","value":"/\\*[^*]*\\*/"}},"conflicts":[["a","b"]],"extras":[{"type":"SYMBOL","name":"comment"}]}"#).unwrap();
    let mut session = grammar.session();
    session.set_trace_enabled(true);
    let source = b"x/*note*/yz";
    let tree = session.parse(source).unwrap();
    assert!(
        (0..tree.survey().walked)
            .filter_map(|i| tree.node_at(i))
            .any(|n| n.name() == "comment" && n.is_extra())
    );
    let tokens = session.selected_tokens().unwrap();
    assert_eq!(tokens.len(), 3);
    assert_eq!(
        tokens
            .iter()
            .map(|t| &source[t.span.range()])
            .collect::<Vec<_>>(),
        [b"x".as_slice(), b"y", b"z"]
    );
    assert!(session.token_reads() > tokens.len());
}

#[test]
fn zero_width_external_reads_are_kept_and_distinguished_from_supplied_literals() {
    let grammar = CompiledGrammar::compile_with_customary(
        br#"{"name":"zero_trace","externals":[{"type":"SYMBOL","name":"mark"}],"rules":{"doc":{"type":"SEQ","members":[{"type":"SYMBOL","name":"mark"},{"type":"STRING","value":"x"}]}}}"#,
        br#"{"cohort":["mark"],"rules":[{"phase":"bounded","when":[["wanted","mark"]],"then":[["emit","mark"]]}]}"#,
        CompileOptions::default(),
    ).unwrap();
    let mut session = grammar.session();
    session.set_trace_enabled(true);
    session.parse(b"x").unwrap();
    let tokens = session.selected_tokens().unwrap();
    assert_eq!(tokens.len(), 2);
    assert!(tokens[0].span.is_empty());
    assert!(!tokens[0].supplied);
    let grammar = CompiledGrammar::compile(include_bytes!("../../test/grammar/json.json")).unwrap();
    let mut session = grammar.session();
    session.set_trace_enabled(true);
    session.set_recovery(Recovery::Fell);
    session.set_supply(Supply::UniqueLiteral);
    session.parse_partial(br#"{"a"1}"#).unwrap();
    let supplied = session
        .selected_tokens()
        .unwrap()
        .iter()
        .find(|token| token.supplied)
        .unwrap();
    assert!(supplied.span.is_empty());
}
