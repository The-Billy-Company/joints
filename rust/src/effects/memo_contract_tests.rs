use super::*;
fn graph() -> Arc<Automaton> {
    Arc::new(Automaton::from_tree_sitter(br#"{"name":"memo","rules":{"doc":{"type":"CHOICE","members":[{"type":"STRING","value":"x"},{"type":"SEQ","members":[{"type":"STRING","value":"("},{"type":"SYMBOL","name":"doc"},{"type":"STRING","value":")"}]}]}},"extras":[]}"#).unwrap())
}
fn compare(
    left: &EffectStore,
    a: Result<Effect, EffectError>,
    right: &EffectStore,
    b: Result<Effect, EffectError>,
) {
    assert_eq!(
        a.as_ref().map(|&e| left.describe(e)),
        b.as_ref().map(|&e| right.describe(e))
    );
    if let (Ok(Effect(Repr::Run { index: a, .. })), Ok(Effect(Repr::Run { index: b, .. }))) = (a, b)
    {
        assert_eq!(a, b, "interning order");
    }
}
#[test]
fn memo_matches_original_primitive_and_compose_results_and_intern_order() {
    let graph = graph();
    let mut cached = EffectStore::new(Arc::clone(&graph));
    let mut plain = EffectStore::new(Arc::clone(&graph));
    plain.memo.disable();
    let mut pairs = vec![
        (Effect::ZERO, Effect::ZERO),
        (Effect::IDENTITY, Effect::IDENTITY),
    ];
    for state in 0..graph.state_count() {
        for symbol in 0..graph.symbol_count() {
            let a = cached.shift(StateId::from_index(state), SymbolId::from_index(symbol));
            let b = plain.shift(StateId::from_index(state), SymbolId::from_index(symbol));
            compare(&cached, a.clone(), &plain, b.clone());
            if let (Ok(a), Ok(b)) = (a, b) {
                pairs.push((a, b));
            }
        }
        for production in 0..graph.production_count() {
            let a = cached.reduce(
                StateId::from_index(state),
                ProductionId::from_index(production),
            );
            let b = plain.reduce(
                StateId::from_index(state),
                ProductionId::from_index(production),
            );
            compare(&cached, a.clone(), &plain, b.clone());
            if let (Ok(a), Ok(b)) = (a, b) {
                pairs.push((a, b));
            }
        }
    }
    for _ in 0..2 {
        for &(a, b) in &pairs {
            for &(c, d) in &pairs {
                let x = cached.compose(a, c);
                let y = plain.compose(b, d);
                compare(&cached, x, &plain, y);
            }
        }
    }
    assert_eq!(cached.runs.len(), plain.runs.len());
    assert!(cached.memo.report()["hits"].as_u64().unwrap() > 0);
}
#[test]
fn memo_never_hides_foreign_invalid_or_zero_identity_operand_errors() {
    let graph = graph();
    let mut store = EffectStore::new(Arc::clone(&graph));
    let mut foreign = EffectStore::new(Arc::clone(&graph));
    let symbol = graph.symbol_by_name("x").unwrap();
    let state = graph.start_state();
    let good = store.shift(state, symbol).unwrap();
    let alien = foreign.shift(state, symbol).unwrap();
    let malformed = Effect(Repr::Run {
        owner: store.owner,
        index: u32::MAX,
    });
    let owner_boundary = Effect(Repr::Run {
        owner: u64::MAX,
        index: 0,
    });
    let before = store.memo.report()["lookups"].as_u64().unwrap();
    for universal in [Effect::ZERO, Effect::IDENTITY, good] {
        assert_eq!(
            store.compose(universal, alien),
            Err(EffectError::ForeignStore)
        );
        assert_eq!(
            store.compose(alien, universal),
            Err(EffectError::ForeignStore)
        );
        assert_eq!(
            store.compose(universal, owner_boundary),
            Err(EffectError::ForeignStore)
        );
        assert_eq!(
            store.compose(universal, malformed),
            Err(EffectError::InvalidHandle)
        );
        assert_eq!(
            store.compose(malformed, universal),
            Err(EffectError::InvalidHandle)
        );
    }
    let high = usize::try_from(u32::MAX).unwrap();
    assert_eq!(
        store.shift(StateId::from_index(high), symbol),
        Err(EffectError::InvalidState(StateId::from_index(high)))
    );
    assert_eq!(
        store.shift(state, SymbolId::from_index(high)),
        Err(EffectError::InvalidSymbol(SymbolId::from_index(high)))
    );
    assert_eq!(
        store.reduce(state, ProductionId::from_index(high)),
        Err(EffectError::InvalidProduction(ProductionId::from_index(
            high
        )))
    );
    assert_eq!(store.memo.report()["lookups"].as_u64().unwrap(), before);
}
#[test]
fn only_successes_are_cached_and_failed_allocation_keeps_original_retry_behavior() {
    let graph = graph();
    let mut reference = EffectStore::new(Arc::clone(&graph));
    reference.memo.disable();
    let mut no_path = None;
    'find: for s in 0..graph.state_count() {
        for p in 0..graph.production_count() {
            if reference.reduce(StateId::from_index(s), ProductionId::from_index(p))
                == Err(EffectError::NoSuchParse)
            {
                no_path = Some((s, p));
                break 'find;
            }
        }
    }
    let (s, p) = no_path.unwrap();
    let mut store = EffectStore::new(Arc::clone(&graph));
    for _ in 0..2 {
        assert_eq!(
            store.reduce(StateId::from_index(s), ProductionId::from_index(p)),
            Err(EffectError::NoSuchParse)
        );
    }
    assert_eq!(store.memo.report()["slots"], 0);
    assert_eq!(store.memo.report()["hits"], 0);
    assert_eq!(store.memo.report()["warmup_successes"], 0);
    store.memo.force_failed_allocation();
    let state = graph.start_state();
    let symbol = graph.symbol_by_name("x").unwrap();
    let expected = reference.shift(state, symbol).unwrap();
    for _ in 0..33 {
        let got = store.shift(state, symbol).unwrap();
        assert_eq!(store.describe(got), reference.describe(expected));
    }
    assert_eq!(store.memo.report()["slots"], 0);
    assert_eq!(store.memo.report()["unavailable"], true);
    let mut later = EffectStore::new(graph);
    for _ in 0..33 {
        let got = later.shift(state, symbol).unwrap();
        assert_eq!(later.describe(got), reference.describe(expected));
    }
    assert!(later.memo.report()["slots"].as_u64().unwrap() > 0);
}

#[test]
fn first32_successful_misses_keep_small_stores_header_only_and33rd_warms_cache() {
    let graph = graph();
    let mut store = EffectStore::new(Arc::clone(&graph));
    let graph_owners = Arc::strong_count(&graph);
    let state = graph.start_state();
    let symbol = graph.symbol_by_name("x").unwrap();
    let first = store.shift(state, symbol).unwrap();
    for _ in 1..32 {
        assert_eq!(store.shift(state, symbol), Ok(first));
    }
    assert_eq!(store.runs.len(), 1);
    assert_eq!(store.memo.report()["slots"], 0);
    assert_eq!(store.memo.report()["capacity"], 0);
    assert_eq!(store.memo.report()["warmup_successes"], 32);
    assert!(matches!(
        store.reduce(
            state,
            ProductionId::from_index(usize::try_from(u32::MAX).unwrap())
        ),
        Err(EffectError::InvalidProduction(_))
    ));
    assert_eq!(store.memo.report()["warmup_successes"], 32);
    assert_eq!(store.memo.report()["slots"], 0);
    assert_eq!(store.shift(state, symbol), Ok(first));
    assert_eq!(store.memo.report()["slots"], 64);
    let hits = store.memo.report()["hits"].as_u64().unwrap();
    assert_eq!(store.shift(state, symbol), Ok(first));
    assert_eq!(store.memo.report()["hits"].as_u64().unwrap(), hits + 1);
    assert_eq!(store.runs.len(), 1);
    assert_eq!(Arc::strong_count(&graph), graph_owners);
}
