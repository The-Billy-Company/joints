use joints_engine::{CompileOptions, CompiledGrammar, Error, LexError, ScannerError};

const GRAMMAR: &[u8] = br#"{
    "name":"budget_contract",
    "rules":{"document":{"type":"STRING","value":"x"}}
}"#;

#[test]
fn public_options_bound_construction_and_worker_lexing() {
    let mut options = CompileOptions::default();
    options.tables.source_bytes = 0;
    assert!(matches!(
        CompiledGrammar::compile_with_options(GRAMMAR, options),
        Err(Error::Compile(_))
    ));

    let mut options = CompileOptions::default();
    options.lexer.scan_transitions = 0;
    let grammar = CompiledGrammar::compile_with_options(GRAMMAR, options).unwrap();
    for _ in 0..2 {
        assert!(matches!(
            grammar.session().parse(b"x"),
            Err(Error::Lex(LexError::WorkLimit { at: 0 }))
        ));
    }
    assert!(
        CompiledGrammar::compile(GRAMMAR)
            .unwrap()
            .session()
            .parse(b"x")
            .unwrap()
            .confidence()
            .is_strict()
    );
}

#[test]
fn public_probe_policy_never_silently_narrows_or_selects_defaults() {
    let mut options = CompileOptions::default();
    options.probes.match_steps = u64::MAX;
    assert!(matches!(
        CompiledGrammar::compile_with_options(GRAMMAR, options),
        Err(Error::Scanner(ScannerError::InvalidLimits(_)))
    ));
    options.probes.match_steps = 0;
    options.probes.depth = 0;
    options.probes.heap_bytes = 0;
    // Zero is representable as an explicit budget, including for a grammar
    // that does not need a probe. It is never the native default sentinel.
    assert!(CompiledGrammar::compile_with_options(GRAMMAR, options).is_ok());
    options.probes.heap_bytes = 1;
    assert!(matches!(
        CompiledGrammar::compile_with_options(GRAMMAR, options),
        Err(Error::Scanner(ScannerError::InvalidLimits(_)))
    ));
}
