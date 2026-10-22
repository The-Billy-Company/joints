//! Hash directives share Swift's raw-string scanner entry, but have no state.
//! The embedded book owns the raw-string marks; an open mark suppresses this
//! entry. Bind this extension only with that book's known protocol.

use super::{ScanHit, ScannerError, ScannerState, charge, charge_work};
use crate::{compiler::Automaton, ids::SymbolId};

const COHORT: &[&str] = &[
    "multiline_comment",
    "raw_str_part",
    "raw_str_continuing_indicator",
    "raw_str_end_part",
    "_implicit_semi",
    "_explicit_semi",
    "_arrow_operator_custom",
    "_dot_custom",
    "_conjunction_operator_custom",
    "_disjunction_operator_custom",
    "_nil_coalescing_operator_custom",
    "_eq_custom",
    "_eq_eq_custom",
    "_plus_then_ws",
    "_minus_then_ws",
    "_bang_custom",
    "_throws_keyword",
    "_rethrows_keyword",
    "default_keyword",
    "where_keyword",
    "else",
    "catch_keyword",
    "_as_custom",
    "_as_quest_custom",
    "_as_bang_custom",
    "_async_keyword_custom",
    "_custom_operator",
    "_hash_symbol_custom",
    "_directive_if",
    "_directive_elseif",
    "_directive_else",
    "_directive_endif",
    "_fake_try_bang",
];

#[derive(Debug)]
struct Directive {
    suffix: &'static [u8],
    symbol: Option<SymbolId>,
}

#[derive(Debug)]
pub(super) struct Swift {
    raw: SymbolId,
    controls: [SymbolId; 2],
    hash: Option<SymbolId>,
    directives: [Directive; 4],
}

impl Swift {
    pub fn bind(grammar: &Automaton) -> Option<Self> {
        if !COHORT
            .iter()
            .all(|name| grammar.external_by_name(name).is_some())
        {
            return None;
        }
        let id = |name| {
            grammar
                .external_by_name(name)
                .expect("checked Swift cohort")
        };
        let directive = |name, suffix| Directive {
            suffix,
            symbol: Some(id(name)),
        };
        Some(Self {
            raw: id("raw_str_part"),
            controls: [id("raw_str_continuing_indicator"), id("_fake_try_bang")],
            hash: Some(id("_hash_symbol_custom")),
            // The C scanner remembers the longest completed prefix. In
            // particular, #elseif cannot fall back to #else when unwanted.
            directives: [
                directive("_directive_elseif", b"elseif"),
                directive("_directive_endif", b"endif"),
                directive("_directive_else", b"else"),
                directive("_directive_if", b"if"),
            ],
        })
    }

    pub fn claims(&self, symbol: SymbolId) -> bool {
        self.hash == Some(symbol)
            || self
                .directives
                .iter()
                .any(|directive| directive.symbol == Some(symbol))
    }

    pub fn controls(&self, symbol: SymbolId) -> bool {
        self.controls.contains(&symbol)
    }

    pub fn remove_claimed(&mut self, claimed: &[SymbolId]) {
        for symbol in std::iter::once(&mut self.hash).chain(
            self.directives
                .iter_mut()
                .map(|directive| &mut directive.symbol),
        ) {
            if symbol.is_some_and(|id| claimed.contains(&id)) {
                *symbol = None;
            }
        }
    }

    pub fn step(
        &self,
        state: &ScannerState,
        source: &[u8],
        at: usize,
        wanted: &[SymbolId],
        remaining: &mut usize,
    ) -> Result<Option<ScanHit>, ScannerError> {
        // eat_raw_str_part first checks RAW_STR_PART, even for directives.
        // Swift's embedded book uses marks only for its ongoing raw string.
        charge_work(remaining, wanted.len().saturating_mul(2))?;
        if !state.marks.is_empty() || !wanted.contains(&self.raw) {
            return Ok(None);
        }
        charge(remaining)?;
        if source.get(at) != Some(&b'#') {
            return Ok(None);
        }
        charge(remaining)?;
        if matches!(source.get(at + 1), Some(b'#' | b'"')) {
            return Ok(None);
        }
        let mut selected = (self.hash, at + 1);
        for directive in &self.directives {
            let mut matched = true;
            for (offset, &byte) in directive.suffix.iter().enumerate() {
                charge(remaining)?;
                if source.get(at + 1 + offset) != Some(&byte) {
                    matched = false;
                    break;
                }
            }
            if matched {
                selected = (directive.symbol, at + 1 + directive.suffix.len());
                break;
            }
        }
        let (Some(symbol), end) = selected else {
            return Ok(None);
        };
        Ok(wanted.contains(&symbol).then_some(ScanHit {
            symbol,
            start: at,
            end,
        }))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn source() -> Vec<u8> {
        serde_json::to_vec(&json!({
            "rules":{"doc":{"type":"STRING","value":"x"}},
            "externals":COHORT.iter().map(|name| json!({"type":"SYMBOL","name":name})).collect::<Vec<_>>()
        })).unwrap()
    }

    fn setup() -> (Automaton, Swift) {
        let grammar = Automaton::from_tree_sitter(&source()).unwrap();
        let hand = Swift::bind(&grammar).unwrap();
        (grammar, hand)
    }

    #[test]
    fn hash_protocol_uses_longest_completed_prefix_without_a_word_boundary() {
        let (grammar, hand) = setup();
        let state = ScannerState::default();
        let wanted = grammar.external_ids();
        for (source, name, end) in [
            (b"#ifFLAG".as_slice(), "_directive_if", 3),
            (b"#elseifNEXT".as_slice(), "_directive_elseif", 7),
            (b"#elsei".as_slice(), "_directive_else", 5),
            (b"#endif".as_slice(), "_directive_endif", 6),
            (b"#macro".as_slice(), "_hash_symbol_custom", 1),
            (b"#".as_slice(), "_hash_symbol_custom", 1),
            (b"#\xff".as_slice(), "_hash_symbol_custom", 1),
        ] {
            let hit = hand
                .step(&state, source, 0, wanted, &mut 1_000)
                .unwrap()
                .unwrap();
            assert_eq!(
                (grammar.symbol(hit.symbol).name.as_str(), hit.start, hit.end),
                (name, 0, end)
            );
        }
        for source in [b"##x".as_slice(), b"#\"unclosed", b"", b"if FLAG"] {
            assert!(
                hand.step(&state, source, 0, wanted, &mut 1_000)
                    .unwrap()
                    .is_none()
            );
        }
    }

    #[test]
    fn permissions_raw_memory_and_explicit_claims_cannot_fall_back_to_shorter_tokens() {
        let (grammar, mut hand) = setup();
        let id = |name| grammar.external_by_name(name).unwrap();
        let state = ScannerState::default();
        assert!(
            hand.step(
                &state,
                b"#elseifNEXT",
                0,
                &[hand.raw, id("_directive_else"), id("_hash_symbol_custom")],
                &mut 1_000
            )
            .unwrap()
            .is_none()
        );
        assert!(
            hand.step(&state, b"#if FLAG", 0, &[id("_directive_if")], &mut 1_000)
                .unwrap()
                .is_none()
        );
        let mut raw = ScannerState::default();
        raw.marks.push(super::super::Mark {
            kind: 1,
            count: 2,
            tag: vec![],
        });
        assert!(
            hand.step(&raw, b"#if FLAG", 0, grammar.external_ids(), &mut 1_000)
                .unwrap()
                .is_none()
        );
        hand.remove_claimed(&[id("_directive_elseif")]);
        assert!(!hand.claims(id("_directive_elseif")));
        assert!(
            hand.step(
                &state,
                b"#elseifNEXT",
                0,
                grammar.external_ids(),
                &mut 1_000
            )
            .unwrap()
            .is_none()
        );
        assert!(hand.controls(id("_fake_try_bang")));
        assert!(hand.controls(id("raw_str_continuing_indicator")));
        assert!(matches!(
            hand.step(&state, b"#if FLAG", 0, grammar.external_ids(), &mut 0),
            Err(ScannerError::Limit(_))
        ));
    }

    #[test]
    fn identical_explicit_book_retains_the_default_protocol() {
        use crate::{CompileOptions, CompiledGrammar, ScannerBinding};
        let source = source();
        let default = CompiledGrammar::compile(&source).unwrap();
        let explicit = CompiledGrammar::compile_with_customary(
            &source,
            super::super::program::SWIFT_BOOK.as_bytes(),
            CompileOptions::default(),
        )
        .unwrap();
        let bindings = |grammar: &CompiledGrammar| {
            grammar
                .external_bindings()
                .map(|(id, binding)| (grammar.symbol_name(id).unwrap().to_owned(), binding))
                .collect::<std::collections::BTreeMap<_, _>>()
        };
        assert_eq!(bindings(&default), bindings(&explicit));
        let default = bindings(&default);
        for name in [
            "_hash_symbol_custom",
            "_directive_if",
            "_directive_elseif",
            "_directive_else",
            "_directive_endif",
        ] {
            assert_eq!(default[name], ScannerBinding::Hand);
        }
        for name in ["raw_str_continuing_indicator", "_fake_try_bang"] {
            assert_eq!(default[name], ScannerBinding::Control);
        }
        let written = br##"{"cohort":["_directive_if"],"probes":{"if":"#if"},"rules":[{"phase":"bounded","when":[["wanted","_directive_if"],["probe","if"]],"then":[["emit","_directive_if"]]}]}"##;
        let replacement =
            CompiledGrammar::compile_with_customary(&source, written, CompileOptions::default())
                .unwrap();
        let replacement = bindings(&replacement);
        assert_eq!(replacement["_directive_if"], ScannerBinding::Customary);
        assert_eq!(replacement["_hash_symbol_custom"], ScannerBinding::Blind);
    }
}
