//! Rust's numeric/doc-token protocol, recognized by its complete external roster.
//! Existing bounded strings/comments and raw-fence memory remain separate hands.
//! The error sentinel is a control that declines native scanning, never a token.

use super::{ScanHit, ScannerError, charge_work};
use crate::{SymbolId, compiler::Automaton};

pub(super) const COHORT: [&str; 11] = [
    "string_content",
    "string_close",
    "_raw_string_literal_start",
    "raw_string_literal_content",
    "_raw_string_literal_end",
    "float_literal",
    "_outer_block_doc_comment_marker",
    "_inner_block_doc_comment_marker",
    "_block_comment_content",
    "_line_doc_content",
    "_error_sentinel",
];

pub(super) struct Rust {
    ids: [SymbolId; 11],
    float: bool,
    doc: bool,
    sentinel: bool,
}
pub(super) struct Permissions {
    pub blocked: bool,
    pub block: bool,
    float: bool,
    doc: bool,
}
impl Rust {
    pub(super) fn bind(grammar: &Automaton) -> Option<Self> {
        // A spelling or grammar title cannot establish this scanner protocol.
        if grammar.external_ids().len() != COHORT.len() {
            return None;
        }
        let ids: Vec<_> = COHORT
            .iter()
            .map(|name| grammar.external_by_name(name))
            .collect::<Option<_>>()?;
        let ids = ids.try_into().ok()?;
        Some(Self {
            ids,
            float: true,
            doc: true,
            sentinel: true,
        })
    }
    pub(super) fn remove_claimed(&mut self, claimed: &[SymbolId]) {
        self.float &= !claimed.contains(&self.ids[5]);
        self.doc &= !claimed.contains(&self.ids[9]);
        self.sentinel &= !claimed.contains(&self.ids[10]);
    }
    pub(super) fn claims(&self, symbol: SymbolId) -> bool {
        (self.float && symbol == self.ids[5]) || (self.doc && symbol == self.ids[9])
    }
    pub(super) fn controls(&self, symbol: SymbolId) -> bool {
        self.sentinel && symbol == self.ids[10]
    }
    pub(super) fn permissions(
        &self,
        wanted: &[SymbolId],
        remaining: &mut usize,
    ) -> Result<Permissions, ScannerError> {
        charge_work(remaining, wanted.len().saturating_mul(7))?;
        Ok(Permissions {
            blocked: self.sentinel && wanted.contains(&self.ids[10]),
            block: self.ids[6..=8].iter().any(|symbol| wanted.contains(symbol)),
            // The pinned protocol commits to raw content before considering
            // numeric tokens, even when that raw read subsequently declines.
            float: self.float && wanted.contains(&self.ids[5]) && !wanted.contains(&self.ids[3]),
            doc: self.doc && wanted.contains(&self.ids[9]),
        })
    }
    pub(super) fn step(
        &self,
        source: &[u8],
        at: usize,
        permission: &Permissions,
        already: &[SymbolId],
        remaining: &mut usize,
    ) -> Result<Option<ScanHit>, ScannerError> {
        if at > source.len() {
            return Err(ScannerError::Program(
                "Rust scanner offset exceeds source".into(),
            ));
        }
        if permission.blocked || permission.block {
            return Ok(None);
        }
        if permission.doc {
            let mut end = at;
            while let Some((ch, next)) = peek(source, end, remaining)? {
                end = next;
                if ch == '\n' {
                    break;
                }
            }
            if end > at || !already.contains(&self.ids[9]) {
                return Ok(Some(ScanHit {
                    symbol: self.ids[9],
                    start: at,
                    end,
                }));
            }
            return Ok(None);
        }
        if permission.float {
            let mut start = at;
            while let Some((ch, next)) = peek(source, start, remaining)? {
                if !ch.is_whitespace() {
                    break;
                }
                start = next;
            }
            if peek(source, start, remaining)?.is_some_and(|(ch, _)| ch.is_ascii_digit()) {
                if let Some(end) = float(source, start, remaining)? {
                    return Ok(Some(ScanHit {
                        symbol: self.ids[5],
                        start,
                        end,
                    }));
                }
            }
        }
        Ok(None)
    }
}

// Inspect at most one UTF-8 scalar, paying its bytes before decoding. Invalid
// bytes stay addressable: a replacement scalar advances one byte, as in the
// parser's byte-oriented source contract. No whole suffix is validated/copied.
fn peek(
    source: &[u8],
    at: usize,
    remaining: &mut usize,
) -> Result<Option<(char, usize)>, ScannerError> {
    charge_work(remaining, 1)?;
    let Some(&first) = source.get(at) else {
        return Ok(None);
    };
    let width = match first {
        0..=0x7f => 1,
        0xc2..=0xdf => 2,
        0xe0..=0xef => 3,
        0xf0..=0xf4 => 4,
        _ => 1,
    };
    charge_work(remaining, width - 1)?;
    let scalar = source
        .get(at..at + width)
        .and_then(|bytes| std::str::from_utf8(bytes).ok())
        .and_then(|text| text.chars().next());
    Ok(Some(
        scalar.map_or(('\u{fffd}', at + 1), |ch| (ch, at + width)),
    ))
}
fn number(ch: char) -> bool {
    ch.is_ascii_digit() || ch == '_'
}
fn float(
    source: &[u8],
    start: usize,
    remaining: &mut usize,
) -> Result<Option<usize>, ScannerError> {
    let mut at = start + 1; // caller established an ASCII decimal digit
    while let Some((ch, next)) = peek(source, at, remaining)? {
        if !number(ch) {
            break;
        }
        at = next;
    }
    let mut fraction = false;
    if peek(source, at, remaining)?.is_some_and(|(ch, _)| ch == '.') {
        fraction = true;
        at += 1;
        if peek(source, at, remaining)?.is_some_and(|(ch, _)| ch.is_alphabetic() || ch == '.') {
            return Ok(None);
        }
        while let Some((ch, next)) = peek(source, at, remaining)? {
            if !number(ch) {
                break;
            }
            at = next;
        }
    }
    let mut end = at;
    let exponent = peek(source, at, remaining)?.is_some_and(|(ch, _)| ch == 'e' || ch == 'E');
    if exponent {
        at += 1;
        if peek(source, at, remaining)?.is_some_and(|(ch, _)| ch == '+' || ch == '-') {
            at += 1;
        }
        if !peek(source, at, remaining)?.is_some_and(|(ch, _)| number(ch)) {
            return Ok(Some(end));
        }
        while let Some((ch, next)) = peek(source, at, remaining)? {
            if !number(ch) {
                break;
            }
            at = next;
        }
        end = at;
    }
    if !fraction && !exponent {
        return Ok(None);
    }
    if peek(source, at, remaining)?.is_some_and(|(ch, _)| matches!(ch, 'u' | 'i' | 'f')) {
        at += 1;
        if peek(source, at, remaining)?.is_some_and(|(ch, _)| ch.is_ascii_digit()) {
            while let Some((ch, next)) = peek(source, at, remaining)? {
                if !ch.is_ascii_digit() {
                    break;
                }
                at = next;
            }
            end = at;
        }
    }
    Ok(Some(end))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    fn grammar(names: &[&str]) -> Automaton {
        let source = json!({"name":"arbitrary_title","externals":names.iter().map(|name|json!({"type":"SYMBOL","name":name})).collect::<Vec<_>>(),"rules":{"doc":{"type":"STRING","value":"x"}}});
        Automaton::from_tree_sitter(&serde_json::to_vec(&source).unwrap()).unwrap()
    }
    fn scan(
        hand: &Rust,
        source: &[u8],
        name: &str,
        remaining: &mut usize,
    ) -> Result<Option<ScanHit>, ScannerError> {
        let wanted = [hand.ids[COHORT.iter().position(|n| *n == name).unwrap()]];
        let permission = hand.permissions(&wanted, remaining)?;
        hand.step(source, 0, &permission, &[], remaining)
    }
    #[test]
    fn complete_cohort_and_token_permissions_establish_numeric_ownership() {
        assert!(Rust::bind(&grammar(&["float_literal", "_line_doc_content"])).is_none());
        assert!(Rust::bind(&grammar(&COHORT[..10])).is_none());
        let hand = Rust::bind(&grammar(&COHORT)).unwrap();
        for (source, end) in [
            ("1.25e-3_f64", Some(11)),
            ("2E+1f32", Some(7)),
            ("3.", Some(2)),
            ("1.0..2.0", Some(3)),
            ("1..2", None),
            ("1.max(2)", None),
            ("1", None),
            ("1.25e+", Some(4)),
            ("1e-", Some(1)),
            ("1_000.25_f32", Some(12)),
            ("1.0foo", Some(3)),
            ("1.0u8", Some(5)),
            ("1.0u", Some(3)),
        ] {
            assert_eq!(
                scan(&hand, source.as_bytes(), "float_literal", &mut 10_000)
                    .unwrap()
                    .map(|hit| hit.end),
                end,
                "{source}"
            );
        }
        let permission = hand.permissions(&[], &mut 1000).unwrap();
        assert!(
            hand.step(b"1.25", 0, &permission, &[], &mut 1000)
                .unwrap()
                .is_none()
        );
        assert!(hand.claims(hand.ids[5]));
        assert!(!hand.claims(hand.ids[10]));
        assert!(hand.controls(hand.ids[10]));
    }
    #[test]
    fn doc_content_keeps_newline_and_utf8_bytes_and_empty_eof_is_spent_once() {
        let hand = Rust::bind(&grammar(&COHORT)).unwrap();
        for (source, end) in [(" αβ\nnext", 6), ("line\r\nnext", 6), ("final", 5), ("", 0)] {
            let hit = scan(&hand, source.as_bytes(), "_line_doc_content", &mut 1000)
                .unwrap()
                .unwrap();
            assert_eq!((hit.start, hit.end), (0, end));
        }
        let permission = hand.permissions(&[hand.ids[9]], &mut 100).unwrap();
        assert!(
            hand.step(b"", 0, &permission, &[hand.ids[9]], &mut 100)
                .unwrap()
                .is_none()
        );
        assert_eq!(
            scan(&hand, b"\xff\n", "_line_doc_content", &mut 100)
                .unwrap()
                .unwrap()
                .end,
            2
        );
    }
    #[test]
    fn failures_consume_bounded_work_and_books_remove_only_their_owned_tokens() {
        let mut hand = Rust::bind(&grammar(&COHORT)).unwrap();
        let mut remaining = 0;
        assert!(matches!(
            scan(&hand, b"1.25", "float_literal", &mut remaining),
            Err(ScannerError::Limit("program work"))
        ));
        let mut remaining = 20;
        assert!(matches!(
            scan(&hand, &vec![b'9'; 1000], "float_literal", &mut remaining),
            Err(ScannerError::Limit("program work"))
        ));
        assert_eq!(remaining, 0);
        let mut remaining = 10;
        assert!(matches!(
            scan(
                &hand,
                "αβγ\n".as_bytes(),
                "_line_doc_content",
                &mut remaining
            ),
            Err(ScannerError::Limit("program work"))
        ));
        hand.remove_claimed(&[hand.ids[5]]);
        assert!(!hand.claims(hand.ids[5]));
        assert!(hand.claims(hand.ids[9]));
        assert!(
            scan(&hand, b"1.25", "float_literal", &mut 100)
                .unwrap()
                .is_none()
        );
        let p = hand
            .permissions(&[hand.ids[5], hand.ids[10]], &mut 100)
            .unwrap();
        assert!(p.blocked);
        assert!(hand.step(b"1.25", 0, &p, &[], &mut 100).unwrap().is_none());
    }
    #[test]
    fn full_protocol_preserves_raw_and_string_close_priority_over_numbers() {
        use super::super::{ScannerProgram, ScannerState};
        let graph = grammar(&COHORT);
        let program = ScannerProgram::bind(&graph).unwrap().unwrap();
        let id = |name| graph.external_by_name(name).unwrap();
        let float = id("float_literal");
        let raw_start = id("_raw_string_literal_start");
        let raw_body = id("raw_string_literal_content");
        let raw_end = id("_raw_string_literal_end");
        let close = id("string_close");
        let sentinel = id("_error_sentinel");
        let mut state = ScannerState::default();
        let mut work = 10_000;
        let source = b"r\"1.2\"";
        let start = program
            .step(
                &mut state,
                source,
                0,
                true,
                false,
                &[raw_start],
                &[raw_start],
                &mut work,
            )
            .unwrap()
            .unwrap();
        assert_eq!((start.symbol, start.start, start.end), (raw_start, 0, 2));
        let body = program
            .step(
                &mut state,
                source,
                2,
                true,
                false,
                &[raw_body, float],
                &[raw_body, float],
                &mut work,
            )
            .unwrap()
            .unwrap();
        assert_eq!((body.symbol, body.start, body.end), (raw_body, 2, 5));
        let end = program
            .step(
                &mut state,
                source,
                5,
                true,
                false,
                &[raw_end, float],
                &[raw_end, float],
                &mut work,
            )
            .unwrap()
            .unwrap();
        assert_eq!((end.symbol, end.start, end.end), (raw_end, 5, 6));
        let closing = program
            .step(
                &mut ScannerState::default(),
                b"\"",
                0,
                true,
                false,
                &[close, float],
                &[close, float],
                &mut work,
            )
            .unwrap()
            .unwrap();
        assert_eq!((closing.symbol, closing.start, closing.end), (close, 0, 1));
        assert!(
            program
                .step(
                    &mut ScannerState::default(),
                    b"1.2",
                    0,
                    true,
                    false,
                    &[sentinel, float],
                    &[sentinel, float],
                    &mut work
                )
                .unwrap()
                .is_none()
        );
    }
}
