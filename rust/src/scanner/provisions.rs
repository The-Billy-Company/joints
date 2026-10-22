//! Stateless external spellings, bound by the scanner's complete token cohort.
//!
//! Transcribed from `src/kernel/lex/outside.zig::roll`. A shared token name
//! alone never establishes which external scanner a grammar expects.

use super::{ScanHit, ScannerError, probe::Probe};
use crate::{
    SymbolId,
    compiler::{Automaton, Lexis, Pattern},
};

struct Spelling {
    name: &'static str,
    pattern: &'static str,
    immediate: bool,
    cohort: &'static [&'static str],
    after: &'static [&'static [u8]],
    never: &'static [&'static [u8]],
}

impl Spelling {
    const fn plain(
        name: &'static str,
        pattern: &'static str,
        immediate: bool,
        cohort: &'static [&'static str],
    ) -> Self {
        Self {
            name,
            pattern,
            immediate,
            cohort,
            after: &[],
            never: &[],
        }
    }
    fn guarded(&self) -> bool {
        !self.after.is_empty() || !self.never.is_empty()
    }
    fn holds(&self, rest: &[u8]) -> bool {
        !self.never.iter().any(|prefix| rest.starts_with(prefix))
            && (self.after.is_empty() || self.after.iter().any(|prefix| rest.starts_with(prefix)))
    }
}

const ROLL: &[Spelling] = &[
    Spelling::plain("string_content", r#"[^"\\]+"#, true, &["string_close"]),
    Spelling::plain("string_close", "\"", true, &["string_content"]),
    Spelling::plain(
        "comment",
        r"#[^\n]*",
        false,
        &["_indent", "_dedent", "_newline"],
    ),
    Spelling {
        after: &[b"=", b"[", b"+=", b"%", b"#", b"@", b"?"],
        ..Spelling::plain(
            "variable_name",
            "[a-zA-Z_][a-zA-Z0-9_]*",
            false,
            &["file_descriptor", "test_operator"],
        )
    },
    Spelling {
        after: &[b">", b"<"],
        ..Spelling::plain(
            "file_descriptor",
            "[0-9]+",
            false,
            &["variable_name", "test_operator"],
        )
    },
    Spelling {
        after: &[b" ", b"\t", b"\n", b"\r"],
        ..Spelling::plain(
            "test_operator",
            "-[a-zA-Z]+",
            false,
            &["variable_name", "file_descriptor"],
        )
    },
    Spelling::plain(
        "simple_symbol",
        r":(?:[a-zA-Z_][a-zA-Z0-9_]*[?!=]?|\[\]=?|<=>|===?|=~|![=~]?|<<?=?|>>?=?|\*\*|[+\-*/%~^&|])",
        false,
        &["hash_key_symbol", "_line_break"],
    ),
    Spelling {
        after: &[b":"],
        never: &[b"::"],
        ..Spelling::plain(
            "hash_key_symbol",
            "[a-zA-Z_][a-zA-Z0-9_]*",
            false,
            &["simple_symbol", "_line_break"],
        )
    },
    Spelling::plain(
        "_line_break",
        r"\n",
        false,
        &["simple_symbol", "hash_key_symbol"],
    ),
    Spelling::plain(
        "_ternary_qmark",
        r"\?",
        false,
        &["_template_chars", "regex_pattern"],
    ),
    Spelling::plain(
        "_template_chars",
        r"[^`$\\]+",
        true,
        &["_ternary_qmark", "regex_pattern"],
    ),
    Spelling::plain(
        "escape_sequence",
        r"\\(?:x[0-9a-fA-F]{2}|u\{[0-9a-fA-F]+\}|u[0-9a-fA-F]{4}|[0-7]{1,3}|[^0-9xu])",
        true,
        &["_template_chars", "regex_pattern"],
    ),
    Spelling::plain(
        "regex_pattern",
        r"(?:[^/\\\[\n]|\\.|\[(?:[^\]\\\n]|\\.)*\])+",
        true,
        &["_template_chars", "_ternary_qmark"],
    ),
    Spelling::plain(
        "_simple_string_start",
        "\"",
        false,
        &[
            "_simple_string_middle",
            "_single_line_string_end",
            "_simple_multiline_string_start",
        ],
    ),
    Spelling::plain(
        "_simple_multiline_string_start",
        "\"\"\"",
        false,
        &[
            "_simple_string_start",
            "_simple_string_middle",
            "_single_line_string_end",
        ],
    ),
    Spelling::plain(
        "_simple_string_middle",
        r#"[^"\\\n]+"#,
        true,
        &[
            "_simple_string_start",
            "_single_line_string_end",
            "_simple_multiline_string_start",
        ],
    ),
    Spelling::plain(
        "_single_line_string_end",
        r#"[^"\\\n]*""#,
        true,
        &[
            "_simple_string_start",
            "_simple_string_middle",
            "_simple_multiline_string_start",
        ],
    ),
];

struct Bound {
    symbol: SymbolId,
    spelling: &'static Spelling,
    lexis: Lexis,
    probe: Option<Probe>,
}

pub(super) struct Provisions {
    bound: Vec<Bound>,
}

impl Provisions {
    #[cfg(test)]
    pub(super) fn bind(grammar: &Automaton) -> Result<Self, ScannerError> {
        Self::bind_with_limits(grammar, super::ProbeLimits::default())
    }
    pub(super) fn bind_with_limits(
        grammar: &Automaton,
        limits: super::ProbeLimits,
    ) -> Result<Self, ScannerError> {
        limits.validate()?;
        let mut bound = vec![];
        for spelling in ROLL {
            let Some(symbol) = grammar.external_by_name(spelling.name) else {
                continue;
            };
            if !spelling
                .cohort
                .iter()
                .all(|name| grammar.external_by_name(name).is_some())
            {
                continue;
            }
            let declaration_order = grammar.symbol(symbol).lexis.as_ref().map_or_else(
                || u32::try_from(symbol.index()).expect("symbol IDs store u32"),
                |lexis| lexis.declaration_order,
            );
            bound.push(Bound {
                symbol,
                spelling,
                lexis: Lexis {
                    pattern: Pattern::Regex(spelling.pattern.into()),
                    immediate: spelling.immediate,
                    precedence: 0,
                    declaration_order,
                },
                probe: spelling
                    .guarded()
                    .then(|| Probe::compile_with_limits(spelling.pattern, false, limits))
                    .transpose()?,
            });
        }
        bound.sort_by_key(|entry| entry.lexis.declaration_order);
        Ok(Self { bound })
    }

    /// Stateful readers own their terminals even when the roll has a spelling.
    pub(super) fn remove_claimed(&mut self, claimed: &[SymbolId]) {
        self.bound.retain(|entry| !claimed.contains(&entry.symbol));
    }

    pub(super) fn claims(&self, symbol: SymbolId) -> bool {
        self.bound.iter().any(|entry| entry.symbol == symbol)
    }

    pub(super) fn rules(&self) -> impl Iterator<Item = (SymbolId, &Lexis)> {
        self.bound.iter().map(|entry| (entry.symbol, &entry.lexis))
    }

    /// Guarded stand-ins run before the ordinary slate. Their trailing context
    /// is inspected without consuming any of the grammar's following token.
    pub(super) fn guarded(
        &self,
        source: &[u8],
        at: usize,
        fresh: bool,
        wanted: &[SymbolId],
        remaining: &mut usize,
    ) -> Result<Option<ScanHit>, ScannerError> {
        let mut best: Option<ScanHit> = None;
        for entry in &self.bound {
            let Some(probe) = &entry.probe else {
                continue;
            };
            if !wanted.contains(&entry.symbol) || (entry.lexis.immediate && !fresh) {
                continue;
            }
            let Some(capture) = probe.capture(source, at, remaining)? else {
                continue;
            };
            let width = capture.width();
            let Some(end) = at.checked_add(width) else {
                return Err(ScannerError::Limit("source offset"));
            };
            if width == 0 || !entry.spelling.holds(source.get(end..).unwrap_or_default()) {
                continue;
            }
            if best.is_none_or(|old| end > old.end) {
                best = Some(ScanHit {
                    symbol: entry.symbol,
                    start: at,
                    end,
                });
            }
        }
        Ok(best)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn grammar(externals: &[&str]) -> Automaton {
        let body = json!({"name":"cohort", "externals": externals.iter()
            .map(|name|json!({"type":"SYMBOL","name":name})).collect::<Vec<_>>(),
            "rules":{"doc":{"type":"STRING","value":"x"}}});
        Automaton::from_tree_sitter(&serde_json::to_vec(&body).unwrap()).unwrap()
    }

    #[test]
    fn a_colliding_name_does_not_establish_its_scanner_cohort() {
        assert_eq!(ROLL.len(), 17);
        let unrelated = grammar(&["comment"]);
        assert_eq!(Provisions::bind(&unrelated).unwrap().rules().count(), 0);
        let python = grammar(&["comment", "_indent", "_dedent", "_newline"]);
        let mut provisions = Provisions::bind(&python).unwrap();
        let comment = python.external_by_name("comment").unwrap();
        assert!(provisions.claims(comment));
        provisions.remove_claimed(&[comment]);
        assert!(!provisions.claims(comment));
    }

    #[test]
    fn guarded_rows_leave_trailing_context_and_decline_scope_resolution() {
        let graph = grammar(&["simple_symbol", "hash_key_symbol", "_line_break"]);
        let provisions = Provisions::bind(&graph).unwrap();
        let symbol = graph.external_by_name("hash_key_symbol").unwrap();
        let wanted = [symbol];
        let hit = provisions
            .guarded(b"name: 1", 0, true, &wanted, &mut 100)
            .unwrap()
            .unwrap();
        assert_eq!((hit.symbol, hit.start, hit.end), (symbol, 0, 4));
        assert!(
            provisions
                .guarded(b"Name::x", 0, true, &wanted, &mut 100)
                .unwrap()
                .is_none()
        );
        assert!(
            provisions
                .guarded(b"name: 1", 0, true, &[], &mut 100)
                .unwrap()
                .is_none()
        );
        assert!(
            provisions
                .guarded(b"name x", 0, true, &wanted, &mut 100)
                .unwrap()
                .is_none()
        );
    }
}
