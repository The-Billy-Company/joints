#![forbid(unsafe_code)]

use joints_engine::{
    ArtifactError, ArtifactLimits, Bank, CompiledGrammar, ForeignPolicy, ParseLimits, ParseSession,
    Query, QueryLimits,
};
use sha2::{Digest, Sha256};
use std::sync::Arc;

const GRAMMAR: &[u8] = br#"{"name":"safety","rules":{"doc":{"type":"REPEAT","content":{"type":"SYMBOL","name":"number"}},"number":{"type":"PATTERN","value":"[0-9]+"}},"extras":[{"type":"PATTERN","value":"\\s"}]}"#;

fn parse_limits() -> ParseLimits {
    ParseLimits {
        source_bytes: 256,
        steps: 20_000,
        lexical_steps: 20_000,
        stack: 1024,
        nodes: 1024,
        heads: 32,
    }
}

#[test]
fn resealed_artifact_mutations_remain_bounded_checked_and_owned() {
    let compiled = CompiledGrammar::compile(GRAMMAR).unwrap();
    let artifact = compiled.artifact().unwrap();
    let limits = ArtifactLimits {
        bytes: 1 << 20,
        symbols: 128,
        productions: 256,
        steps: 4096,
        states: 1024,
        items: 100_000,
        table_entries: 100_000,
        actions: 100_000,
        text_bytes: 1 << 16,
        work: 1_000_000,
        image_allocation: 16 << 20,
        ..ArtifactLimits::default()
    };
    assert!(CompiledGrammar::from_artifact_with_limits(&artifact, limits).is_ok());
    let end = artifact.len() - 32;
    let mut accepted = 0;
    let mut refused = 0;
    for case in 0..256 {
        let mut mutated = artifact.clone();
        // Include a valid title-only change alongside malformed table/image
        // changes, so successful publication and ownership are exercised too.
        let at = if case == 0 {
            28
        } else {
            24 + (case * 7919) % (end - 24)
        };
        mutated[at] ^= 1 << (case % 8);
        // Recompute the envelope seal so the checked payload reader and native
        // image loader see the mutation instead of stopping at SHA verification.
        let digest = Sha256::digest(&mutated[..end]);
        mutated[end..].copy_from_slice(&digest);
        let bank = match Bank::from_bytes_with_limits(&mutated, limits) {
            Ok(bank) => bank,
            Err(ArtifactError::Seal) => panic!("mutation did not reach payload validation"),
            Err(_) => {
                refused += 1;
                continue;
            }
        };
        let title = bank.languages().next().unwrap().to_owned();
        let grammar = match bank.get(&title) {
            Ok(Some(grammar)) => grammar,
            Err(_) => {
                // A failed lazy decode must retain its immutable proof for an
                // equally clean retry, rather than publishing a partial grammar.
                assert!(bank.get(&title).is_err());
                refused += 1;
                continue;
            }
            Ok(None) => panic!("directory member vanished"),
        };
        accepted += 1;
        drop(bank);
        mutated.fill(0);
        let mut session = ParseSession::with_limits(grammar, parse_limits());
        for source in [
            b"".as_slice(),
            b"1 22 333",
            b"\x00\xff\x80",
            b"1\r\n2",
            b"999x",
        ] {
            let parsed = session.parse_partial(source);
            if case == 0 {
                let baseline = compiled.session().parse_partial(source).unwrap();
                assert_eq!(parsed.as_ref().unwrap().stop(), baseline.stop());
            }
            if let Ok(tree) = parsed {
                assert_eq!(tree.source(), source);
                assert!(tree.survey().is_sound(), "mutation {case}");
            }
        }
    }
    assert!(
        accepted > 0,
        "valid-but-different payloads must also be exercised"
    );
    assert!(refused > 0);
}

#[test]
fn malformed_queries_cannot_poison_later_compilation_or_execution() {
    let grammar = CompiledGrammar::compile(GRAMMAR).unwrap();
    let tree = grammar.session().parse_partial(b"1 22 333").unwrap();
    let limits = QueryLimits {
        source_bytes: 256,
        work: 100_000,
        depth: 32,
        matches: 128,
        captures: 256,
        ..QueryLimits::default()
    };
    let original = b"((number) @n (#match? @n \"^[0-9]+$\"))";
    for case in 0..256 {
        let mut query = original.to_vec();
        if case < original.len() {
            query.truncate(case);
        } else {
            query[case % original.len()] ^= u8::try_from(case).expect("mutation cases fit u8");
        }
        if let Ok(compiled) = Query::compile_with_limits(Arc::clone(&grammar), &query, limits) {
            query.fill(0xff);
            if let Ok(matches) = compiled.execute(&tree, ForeignPolicy::Refuse) {
                for capture in matches.iter().flat_map(|m| &m.captures) {
                    assert!(capture.node.span().end() <= tree.source().len());
                }
            }
        }
        let clean =
            Query::compile_with_limits(Arc::clone(&grammar), b"(number) @n", limits).unwrap();
        assert_eq!(
            clean.execute(&tree, ForeignPolicy::Refuse).unwrap().len(),
            3
        );
    }
}
