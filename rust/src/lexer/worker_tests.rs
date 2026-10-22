use super::*;

fn sample(pattern: &str) -> Lexer {
    let rule = Lexis {
        pattern: Pattern::Regex(pattern.into()),
        immediate: false,
        precedence: 0,
        declaration_order: 0,
    };
    Lexer::rules(
        [(SymbolId::from_index(0), &rule)].into_iter(),
        &[],
        None,
        LexerLimits::default(),
    )
    .unwrap()
}
fn draw(
    slate: &Munch,
    body: &[u8],
    at: usize,
    allow: Option<&[u32]>,
    pick: Pick,
    mut remaining: usize,
) -> (Result<Option<usize>, String>, Vec<u32>, usize) {
    let mut winners = Vec::new();
    let result = slate
        .scan_bytes_metered_into(body, at, allow, pick, &mut remaining, &mut winners)
        .map_err(|e| e.to_string());
    (result, winners, remaining)
}
#[test]
fn worker_binding_is_fallible_transactional_and_survives_source_drop() {
    let first = sample("a+");
    let second = sample("b+");
    let _other_second_owner = Arc::clone(&second.worker_identity);
    let identity = Arc::clone(&first.worker_identity);
    let mut workers = WorkerSlates::default();
    assert_eq!(
        draw(
            workers.slate(&first, 0).unwrap(),
            b"aaa",
            0,
            None,
            Pick::Longest,
            100
        )
        .0,
        Ok(Some(3))
    );
    drop(first);
    let error = workers
        .slate_with(&second, 0, |_| {
            Err(irgx::Error::OutOfMemory { detail: None })
        })
        .unwrap_err();
    assert!(matches!(error, irgx::Error::OutOfMemory { .. }));
    assert!(Arc::ptr_eq(workers.owner.as_ref().unwrap(), &identity));
    assert_eq!(
        draw(
            workers.slates[0].as_ref().unwrap(),
            b"aa",
            0,
            None,
            Pick::Longest,
            100
        )
        .0,
        Ok(Some(2))
    );
    assert_eq!(
        draw(
            workers.slate(&second, 0).unwrap(),
            b"bbb",
            0,
            None,
            Pick::Longest,
            100
        )
        .0,
        Ok(Some(3))
    );
    assert!(!Arc::ptr_eq(workers.owner.as_ref().unwrap(), &identity));
    let repeated = workers
        .slate_with(&second, 0, |_| panic!("a bound tier must not clone again"))
        .unwrap();
    assert_eq!(
        draw(repeated, b"b", 0, None, Pick::Longest, 100).0,
        Ok(Some(1))
    );
}
#[test]
fn local_slates_preserve_exact_winners_errors_and_transition_allowances() {
    let patterns = ["a*", "a+", "ab", "β+", "[0-9]+"];
    let rules: Vec<_> = patterns
        .iter()
        .enumerate()
        .map(|(i, p)| Lexis {
            pattern: Pattern::Regex((*p).into()),
            immediate: false,
            precedence: 0,
            declaration_order: u32::try_from(i).unwrap(),
        })
        .collect();
    let lexer = Lexer::rules(
        rules
            .iter()
            .enumerate()
            .map(|(i, r)| (SymbolId::from_index(i), r)),
        &[],
        None,
        LexerLimits::default(),
    )
    .unwrap();
    let _other_owner = Arc::clone(&lexer.worker_identity);
    let mut workers = WorkerSlates::default();
    let local = workers.slate(&lexer, 0).unwrap();
    for body in [b"".as_slice(), b"a", b"ab12", b"\xffa", "ββ".as_bytes()] {
        for at in [0, body.len()] {
            for allow in [
                None,
                Some([].as_slice()),
                Some([0, 2, 4].as_slice()),
                Some([999].as_slice()),
            ] {
                for pick in [Pick::Longest, Pick::Shortest] {
                    for remaining in [0, 1, 2, 8, 128, 1024] {
                        assert_eq!(
                            draw(&lexer.tiers[0].slate, body, at, allow, pick, remaining),
                            draw(local, body, at, allow, pick, remaining)
                        );
                    }
                }
            }
        }
    }
}

#[test]
fn missing_tier_clone_failure_preserves_existing_binding_and_worker() {
    let rules: Vec<_> = [("a+", 1), ("b+", 0)]
        .into_iter()
        .enumerate()
        .map(|(i, (pattern, precedence))| Lexis {
            pattern: Pattern::Regex(pattern.into()),
            immediate: false,
            precedence,
            declaration_order: u32::try_from(i).unwrap(),
        })
        .collect();
    let lexer = Lexer::rules(
        rules
            .iter()
            .enumerate()
            .map(|(i, rule)| (SymbolId::from_index(i), rule)),
        &[],
        None,
        LexerLimits::default(),
    )
    .unwrap();
    assert_eq!(lexer.tiers.len(), 2);
    let _other_owner = Arc::clone(&lexer.worker_identity);
    let mut workers = WorkerSlates::default();
    let first = std::ptr::from_ref(workers.slate(&lexer, 0).unwrap());
    let error = workers
        .slate_with(&lexer, 1, |_| {
            Err(irgx::Error::OutOfMemory { detail: None })
        })
        .unwrap_err();
    assert!(matches!(error, irgx::Error::OutOfMemory { .. }));
    assert!(Arc::ptr_eq(
        workers.owner.as_ref().unwrap(),
        &lexer.worker_identity
    ));
    assert!(workers.slates[1].is_none());
    assert_eq!(
        std::ptr::from_ref(
            workers
                .slate_with(&lexer, 0, |_| panic!(
                    "a published tier must survive a failed second clone"
                ))
                .unwrap()
        ),
        first
    );
    assert_eq!(
        draw(
            workers.slates[0].as_ref().unwrap(),
            b"aaa",
            0,
            None,
            Pick::Longest,
            100
        )
        .0,
        Ok(Some(3))
    );
    assert_eq!(
        draw(
            workers.slate(&lexer, 1).unwrap(),
            b"bbb",
            0,
            None,
            Pick::Longest,
            100
        )
        .0,
        Ok(Some(3))
    );
}

#[test]
fn lone_binding_uses_shared_pool_and_other_binding_triggers_transactional_isolation() {
    let lexer = sample("a+");
    let original = std::ptr::from_ref(&lexer.tiers[0].slate);
    let mut first = WorkerSlates::default();
    assert_eq!(
        std::ptr::from_ref(
            first
                .slate_with(&lexer, 0, |_| panic!("lone binding must not clone"))
                .unwrap()
        ),
        original
    );
    assert!(first.slates.is_empty());
    assert_eq!(Arc::strong_count(&lexer.worker_identity), 2);
    let mut second = WorkerSlates::default();
    assert!(
        second
            .slate_with(&lexer, 0, |_| Err(irgx::Error::OutOfMemory {
                detail: None
            }))
            .is_err()
    );
    assert!(second.owner.is_none());
    assert!(second.slates.is_empty());
    assert_eq!(Arc::strong_count(&lexer.worker_identity), 2);
    second.slate(&lexer, 0).unwrap();
    assert_eq!(Arc::strong_count(&lexer.worker_identity), 3);
    assert!(
        first
            .slate_with(&lexer, 0, |_| Err(irgx::Error::OutOfMemory {
                detail: None
            }))
            .is_err()
    );
    assert!(first.slates.is_empty());
    assert!(Arc::ptr_eq(
        first.owner.as_ref().unwrap(),
        &lexer.worker_identity
    ));
    let local = first.slate(&lexer, 0).unwrap();
    assert_ne!(std::ptr::from_ref(local), original);
    assert_eq!(
        draw(local, b"aaa", 0, None, Pick::Longest, 100).0,
        Ok(Some(3))
    );
    drop(second);
    assert_eq!(Arc::strong_count(&lexer.worker_identity), 2);
    assert_ne!(
        std::ptr::from_ref(
            first
                .slate_with(&lexer, 0, |_| panic!("cached local must remain local"))
                .unwrap()
        ),
        original
    );
}
