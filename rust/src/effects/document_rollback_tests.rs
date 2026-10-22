use super::*;

const GRAMMAR: &[u8] = br#"{"name":"rollback","rules":{"doc":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"STRING","value":"x"},{"type":"STRING","value":"y"}]},{"type":"SEQ","members":[{"type":"STRING","value":"x"},{"type":"STRING","value":"z"}]}]}},"extras":[]}"#;

fn fixture() -> (EffectStore, StateId, StateId, SymbolId, SymbolId, SymbolId) {
    let graph = Arc::new(Automaton::from_tree_sitter(GRAMMAR).unwrap());
    let start = graph.start_state();
    let x = graph.symbol_by_name("x").unwrap();
    let y = graph.symbol_by_name("y").unwrap();
    let z = graph.symbol_by_name("z").unwrap();
    let after_x = graph.transition(start, x).unwrap();
    (EffectStore::new(graph), start, after_x, x, y, z)
}

#[test]
fn document_suffix_discard_preserves_owner_old_ids_and_canonical_map() {
    let (mut store, start, after_x, x, y, _) = fixture();
    let old = store.shift(start, x).unwrap();
    let old_description = store.describe(old).unwrap();
    let owner = store.owner;
    let mut foreign = EffectStore::new(Arc::clone(&store.graph));
    assert_eq!(
        foreign.discard_document_suffix(store.document_mark()),
        Err(EffectError::ForeignStore)
    );
    assert!(foreign.runs.is_empty() && foreign.interned.is_empty());
    assert_eq!(
        store.discard_document_suffix(DocumentMark {
            owner,
            runs: store.runs.len() + 1
        }),
        Err(EffectError::InvalidHandle)
    );
    let mark = store.document_mark();
    let first_new = store.runs.len();
    let right = store.shift(after_x, y).unwrap();
    let product = store.compose(old, right).unwrap();
    assert!(store.grounded(product).unwrap());
    let witnesses: Vec<_> = store.runs[first_new..].iter().map(Arc::downgrade).collect();
    let removed = witnesses.len();
    assert!(removed > 0);
    assert_eq!(store.discard_document_suffix(mark), Ok(removed));
    assert!(witnesses.iter().all(|weak| weak.upgrade().is_none()));
    assert_eq!(store.owner, owner);
    assert_eq!(store.runs.len(), first_new);
    assert_eq!(store.interned.len(), first_new);
    assert_eq!(store.describe(old), Ok(old_description));
    assert_eq!(store.shift(start, x), Ok(old));
    for (index, run) in store.runs.iter().enumerate() {
        assert_eq!(
            store.interned.get(run.as_ref()).copied(),
            u32::try_from(index).ok()
        );
    }
}

#[test]
fn discarded_compose_keys_and_zero_answers_cannot_alias_reused_run_ids() {
    for cached_zero in [false, true] {
        let (mut store, start, after_x, x, y, z) = fixture();
        let left = store.shift(start, x).unwrap();
        for _ in 0..64 {
            assert_eq!(store.shift(start, x), Ok(left));
        }
        let mark = store.document_mark();
        let old_right = if cached_zero {
            store.shift(start, z).unwrap()
        } else {
            store.shift(after_x, y).unwrap()
        };
        let old_product = store.compose(left, old_right).unwrap();
        assert_eq!(old_product.is_zero(), cached_zero);
        let key = memo::Key::compose(left, old_right);
        assert_eq!(store.memo.get(key, store.owner), Some(old_product));
        assert!(store.discard_document_suffix(mark).unwrap() > 0);
        assert_eq!(store.memo.get(key, store.owner), None);
        let new_right = store
            .shift(after_x, if cached_zero { y } else { z })
            .unwrap();
        assert_eq!(old_right.0, new_right.0);
        if !cached_zero {
            // Reuse the old answer index as well; a stale answer would now be
            // a valid, incorrect singleton rather than merely an invalid ID.
            store.shift(start, y).unwrap();
        }
        let actual = store.compose(left, new_right).unwrap();
        assert!(!actual.is_zero());
        let EffectDescription::Run { push, ledger, .. } = store.describe(actual).unwrap() else {
            panic!("expected composed run")
        };
        assert_eq!(push, vec![x, if cached_zero { y } else { z }]);
        assert!(ledger.is_empty());
        assert_eq!(store.compose(left, new_right), Ok(actual));
        assert_eq!(store.shift(start, x), Ok(left));
    }
}
