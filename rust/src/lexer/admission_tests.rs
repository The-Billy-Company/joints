use super::*;

#[test]
fn prepared_permissions_preserve_exact_answers_and_refusals_across_repeated_questions() {
    let rules: Vec<_> = ["a*", "[a-z]+", "if", "[ ]+", "β+", "b", "[0-9]+"]
        .into_iter()
        .cycle()
        .take(65)
        .enumerate()
        .map(|(i, text)| Lexis {
            pattern: if i % 7 == 2 {
                Pattern::Literal(text.as_bytes().to_vec())
            } else {
                Pattern::Regex(text.into())
            },
            immediate: i % 7 == 5,
            precedence: if i % 11 == 0 { 1 } else { 0 },
            declaration_order: u32::try_from(i).unwrap(),
        })
        .collect();
    let id = |i| SymbolId::from_index(if i == 64 { u32::MAX as usize } else { i });
    let wide = Lexer::rules(
        rules.iter().enumerate().map(|(i, rule)| (id(i), rule)),
        &[id(3)],
        Some(id(1)),
        LexerLimits::default(),
    )
    .unwrap();
    let small = fixture(false);
    let all: Vec<_> = (0..65).map(id).collect();
    let duplicate = [id(64), id(0), id(5), id(0), id(1), id(2)];
    let empty = [id(0)];
    let mut cached = ScanScratch::default();
    let mut direct = ScanScratch::default();
    direct.permissions.disabled = true;
    for _ in 0..3 {
        for lexer in [&wide, &small, &wide] {
            for admitted in [&[][..], all.as_slice(), &duplicate[..]] {
                for fresh in [false, true] {
                    for body in [b"if12".as_slice(), b"aa", b"b", b"!", b"\xff"] {
                        for pick in [Pick::Longest, Pick::Shortest] {
                            for budget in [0, 1, 2, 8, 1024] {
                                let question = LexicalQuestion {
                                    admitted: Some(admitted),
                                    empty_permit: &empty,
                                    provisional_empty: &[],
                                    eof: false,
                                };
                                assert_eq!(
                                    observe(
                                        lexer,
                                        body,
                                        0,
                                        (question, fresh, pick, budget),
                                        &mut cached
                                    ),
                                    observe(
                                        lexer,
                                        body,
                                        0,
                                        (question, fresh, pick, budget),
                                        &mut direct
                                    )
                                );
                            }
                        }
                    }
                }
            }
        }
    }
}

#[test]
fn full_native_permissions_preserve_winners_errors_and_exact_transition_work() {
    let spellings = ["a*", "a+", "ab", "if", "[a-z]+", "β+", "[0-9]+", "[ ]+"];
    // Repeated spellings exercise tied winners across native mask words.
    for count in [8, 64, 65, 128] {
        let patterns: Vec<_> = spellings.into_iter().cycle().take(count).collect();
        let slate = Munch::new(patterns).unwrap();
        assert!(slate.declined().is_empty());
        let ordinals: Vec<_> = (0..count).map(|i| u32::try_from(i).unwrap()).collect();
        let draw = |body: &[u8], at, allow, pick, mut remaining| {
            let mut winners = Vec::new();
            let result = slate
                .scan_bytes_metered_into(body, at, allow, pick, &mut remaining, &mut winners)
                .map_err(|error| error.to_string());
            (result, winners, remaining)
        };
        for body in [
            b"".as_slice(),
            b"a",
            b"ab12",
            b"if aa",
            b"\xff",
            "ββ".as_bytes(),
        ] {
            for at in 0..=body.len() + 1 {
                for pick in [Pick::Longest, Pick::Shortest] {
                    for remaining in [0, 1, 2, 3, 8, 64, 1024] {
                        assert_eq!(
                            draw(body, at, None, pick, remaining),
                            draw(body, at, Some(ordinals.as_slice()), pick, remaining)
                        );
                    }
                }
            }
        }
    }
}

fn fixture(sparse: bool) -> Lexer {
    let rules: Vec<_> = ["[a-z]+", "if", "[ ]+", "a*", "b", "β+", "z+"]
        .iter()
        .enumerate()
        .map(|(i, pattern)| Lexis {
            pattern: if i == 1 {
                Pattern::Literal(pattern.as_bytes().to_vec())
            } else {
                Pattern::Regex((*pattern).into())
            },
            immediate: i == 4,
            precedence: if i == 4 { 1 } else { 0 },
            declaration_order: u32::try_from(i).unwrap(),
        })
        .collect();
    let id = |i| {
        if sparse && i == 6 {
            SymbolId::from_index(usize::try_from(u32::MAX).unwrap())
        } else {
            SymbolId::from_index(i)
        }
    };
    Lexer::rules(
        rules.iter().enumerate().map(|(i, rule)| (id(i), rule)),
        &[id(2)],
        Some(id(0)),
        LexerLimits::default(),
    )
    .unwrap()
}
#[derive(Debug, PartialEq, Eq)]
struct Observation {
    result: Result<Scan, String>,
    transitions: usize,
    selection: usize,
    allow: Vec<u32>,
    winners: Vec<u32>,
}
fn observe(
    lexer: &Lexer,
    body: &[u8],
    at: usize,
    request: (LexicalQuestion<'_>, bool, Pick, usize),
    scratch: &mut ScanScratch,
) -> Observation {
    let (question, fresh, pick, budget) = request;
    let mut transitions = budget;
    let mut selection = budget;
    let result = lexer
        .scan(
            body,
            at,
            question,
            fresh,
            ScanBudget {
                transitions: &mut transitions,
                selection: &mut selection,
            },
            pick,
            scratch,
        )
        .map_err(|error| error.to_string());
    Observation {
        result,
        transitions,
        selection,
        allow: scratch.allow.clone(),
        winners: scratch.winners.clone(),
    }
}
#[test]
fn bounded_marks_preserve_linear_questions_allow_order_errors_and_work() {
    let fast = fixture(true);
    let mut linear = fixture(true);
    linear.admission_slots = 0;
    let high = SymbolId::from_index(usize::try_from(u32::MAX).unwrap());
    let missing = SymbolId::from_index(usize::try_from(u32::MAX - 1).unwrap());
    let all: Vec<_> = (0..6).map(SymbolId::from_index).chain([high]).collect();
    let unsorted = [
        high,
        SymbolId::from_index(3),
        SymbolId::from_index(0),
        missing,
        SymbolId::from_index(3),
    ];
    let extra = [SymbolId::from_index(2)];
    let empty = [SymbolId::from_index(3)];
    let mut fast_scratch = ScanScratch::default();
    let mut linear_scratch = ScanScratch::default();
    for body in [
        b"".as_slice(),
        b"if aa",
        b"aa",
        b"b",
        b"zzz",
        b"\xff",
        "ββ".as_bytes(),
    ] {
        for admitted in [
            None,
            Some([].as_slice()),
            Some(all.as_slice()),
            Some(unsorted.as_slice()),
            Some(extra.as_slice()),
            Some(empty.as_slice()),
            Some([missing].as_slice()),
        ] {
            for role in [0, 1, 2] {
                let question = LexicalQuestion {
                    admitted,
                    empty_permit: if role == 1 { &empty } else { &[] },
                    provisional_empty: if role == 2 { &empty } else { &[] },
                    eof: role == 0,
                };
                for at in [0, body.len(), body.len() + 1] {
                    for fresh in [false, true] {
                        for pick in [Pick::Longest, Pick::Shortest] {
                            for budget in [0, 1, 2, 8, 64, 1024] {
                                assert_eq!(
                                    observe(
                                        &fast,
                                        body,
                                        at,
                                        (question, fresh, pick, budget),
                                        &mut fast_scratch
                                    ),
                                    observe(
                                        &linear,
                                        body,
                                        at,
                                        (question, fresh, pick, budget),
                                        &mut linear_scratch
                                    )
                                );
                            }
                        }
                    }
                }
            }
        }
    }
    assert!(
        fast.admission_slots
            <= 8 * fast
                .tiers
                .iter()
                .map(|tier| tier.entries.len())
                .sum::<usize>()
    );
    assert_eq!(fast_scratch.admitted.len(), fast.admission_slots);
    assert!(linear_scratch.admitted.is_empty());
}
#[test]
fn marks_rebuild_across_questions_and_grammars_without_unbounded_ids() {
    let first = fixture(false);
    let second = fixture(true);
    let ids: Vec<_> = (0..7).map(SymbolId::from_index).collect();
    let high = SymbolId::from_index(usize::try_from(u32::MAX).unwrap());
    let mut scratch = ScanScratch::default();
    observe(
        &first,
        b"aa",
        0,
        (LexicalQuestion::positive(None), true, Pick::Longest, 1024),
        &mut scratch,
    );
    assert!(scratch.admitted.is_empty());
    assert_eq!(scratch.admitted.capacity(), 0);
    observe(
        &first,
        b"aa",
        0,
        (
            LexicalQuestion::positive(Some(&ids)),
            true,
            Pick::Longest,
            1024,
        ),
        &mut scratch,
    );
    assert_eq!(scratch.admitted.len(), 7);
    assert!(scratch.admitted.iter().all(|mark| *mark));
    let first_capacity = scratch.admitted.capacity();
    drop(first);
    let result = observe(
        &second,
        b"zzz",
        0,
        (
            LexicalQuestion::positive(Some(&[high])),
            true,
            Pick::Longest,
            1024,
        ),
        &mut scratch,
    );
    assert_eq!(
        result.result,
        Ok(Scan::Token(Lexeme {
            symbol: high,
            start: 0,
            end: 3,
            extra: false
        }))
    );
    assert_eq!(scratch.admitted.len(), 56);
    assert!(!scratch.admitted.iter().any(|mark| *mark));
    let second_capacity = scratch.admitted.capacity();
    observe(
        &second,
        b"aa",
        0,
        (
            LexicalQuestion::positive(Some(&[])),
            true,
            Pick::Longest,
            1024,
        ),
        &mut scratch,
    );
    assert!(!scratch.admitted.iter().any(|mark| *mark));
    assert_eq!(scratch.admitted.capacity(), second_capacity);
    assert!(second_capacity >= first_capacity);
    assert!(second_capacity >= second.admission_slots);
}
