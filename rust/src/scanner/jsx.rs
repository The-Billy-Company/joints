//! JSX text from the pinned TypeScript external scanner's complete protocol.
//! Text has no mutable carry; actual parser permissions select each read.

use super::{ScanHit, ScannerError, charge_work};
use crate::{SymbolId, compiler::Automaton};

pub(super) const COHORT: [&str; 10] = [
    "_automatic_semicolon",
    "_template_chars",
    "_ternary_qmark",
    "html_comment",
    "||",
    "escape_sequence",
    "regex_pattern",
    "jsx_text",
    "_function_signature_automatic_semicolon",
    "__error_recovery",
];

pub(super) struct Jsx {
    text: SymbolId,
    template: SymbolId,
    enabled: bool,
}

impl Jsx {
    pub fn bind(grammar: &Automaton) -> Option<Self> {
        if grammar.external_ids().len() != COHORT.len() {
            return None;
        }
        let ids: Vec<_> = COHORT
            .iter()
            .map(|name| grammar.external_by_name(name))
            .collect::<Option<_>>()?;
        Some(Self {
            text: ids[7],
            template: ids[1],
            enabled: true,
        })
    }

    pub fn remove_claimed(&mut self, claimed: &[SymbolId]) {
        self.enabled &= !claimed.contains(&self.text);
    }

    pub fn claims(&self, symbol: SymbolId) -> bool {
        self.enabled && symbol == self.text
    }

    pub fn step(
        &self,
        source: &[u8],
        at: usize,
        fresh: bool,
        wanted: &[SymbolId],
        remaining: &mut usize,
    ) -> Result<Option<ScanHit>, ScannerError> {
        if at > source.len() {
            return Err(ScannerError::Program(
                "JSX scanner offset exceeds source".into(),
            ));
        }
        charge_work(remaining, wanted.len().saturating_mul(2))?;
        // The pinned scanner commits to template handling before JSX text,
        // even when that template read subsequently declines.
        if !self.enabled || !wanted.contains(&self.text) || wanted.contains(&self.template) {
            return Ok(None);
        }
        let mut end = at;
        let mut saw_text = false;
        // A declined LF/indentation read can be retried after the native
        // lexer consumes only part of those extras. Preserve that read's
        // indentation decision without adding mutable scanner state.
        let mut at_newline = !fresh;
        loop {
            charge_work(remaining, 1)?;
            let Some(&byte) = source.get(end) else {
                break;
            };
            if matches!(byte, 0 | b'<' | b'>' | b'{' | b'}' | b'&') {
                break;
            }
            if byte == b'\n' {
                at_newline = true;
            } else {
                // The actual pinned C scanner runs in the C locale: its
                // iswspace class is ASCII, including vertical tab. Non-ASCII
                // scalars therefore all take the text path. A byte walk has
                // the same extents for UTF-8 and invalid byte sequences and
                // never validates or copies an unbounded suffix.
                at_newline &= matches!(byte, b' ' | b'\t' | b'\r' | 0x0b | 0x0c);
                saw_text |= !at_newline;
            }
            end += 1;
        }
        Ok(saw_text.then_some(ScanHit {
            symbol: self.text,
            start: at,
            end,
        }))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn graph() -> Automaton {
        let externals = COHORT
            .iter()
            .map(|name| {
                if *name == "||" {
                    json!({"type":"STRING","value":name})
                } else {
                    json!({"type":"SYMBOL","name":name})
                }
            })
            .collect::<Vec<_>>();
        Automaton::from_tree_sitter(
            &serde_json::to_vec(&json!({
                "name":"protocol_without_a_language_title",
                "rules":{"doc":{"type":"SYMBOL","name":"jsx_text"}},
                "externals":externals,"extras":[]
            }))
            .unwrap(),
        )
        .unwrap()
    }

    #[test]
    fn complete_protocol_permissions_and_book_claims_are_required() {
        let graph = graph();
        let mut hand = Jsx::bind(&graph).unwrap();
        assert!(hand.claims(hand.text));
        assert!(!hand.claims(hand.template));
        assert!(
            hand.step(b"text", 0, true, &[], &mut 100)
                .unwrap()
                .is_none()
        );
        assert!(
            hand.step(b"text", 0, true, &[hand.text, hand.template], &mut 100)
                .unwrap()
                .is_none()
        );
        hand.remove_claimed(&[hand.text]);
        assert!(!hand.claims(hand.text));
        assert!(
            hand.step(b"text", 0, true, &[hand.text], &mut 100)
                .unwrap()
                .is_none()
        );
        let incomplete = Automaton::from_tree_sitter(
            br#"{"rules":{"doc":{"type":"SYMBOL","name":"jsx_text"}},"externals":[{"type":"SYMBOL","name":"jsx_text"}]}"#,
        )
        .unwrap();
        assert!(Jsx::bind(&incomplete).is_none());
    }

    #[test]
    fn delimiters_empty_reads_and_newline_indentation_do_not_emit() {
        let graph = graph();
        let hand = Jsx::bind(&graph).unwrap();
        for source in [
            b"".as_slice(),
            b"{tail",
            b"<tail",
            b">tail",
            b"}tail",
            b"&entity;",
            b"\0tail",
            b"\n \t\x0b\x0c\r",
        ] {
            assert!(
                hand.step(source, 0, true, &[hand.text], &mut 100)
                    .unwrap()
                    .is_none(),
                "{source:?}"
            );
        }
        for tail in [b'{', b'<', b'>', b'}', b'&', 0] {
            let source = [b'a', b'b', tail, b'z'];
            let hit = hand
                .step(&source, 0, true, &[hand.text], &mut 100)
                .unwrap()
                .unwrap();
            assert_eq!((hit.start, hit.end), (0, 2));
        }
        let hit = hand
            .step(b"!!text", 2, true, &[hand.text], &mut 100)
            .unwrap()
            .unwrap();
        assert_eq!((hit.start, hit.end), (2, 6));
    }

    #[test]
    fn c_whitespace_utf8_and_invalid_bytes_preserve_actual_extents() {
        let graph = graph();
        let hand = Jsx::bind(&graph).unwrap();
        for source in [
            b"\r".as_slice(),
            b" \n ",
            "\n\u{0085}".as_bytes(),
            "\n\u{00a0}".as_bytes(),
            "\n\u{2003}".as_bytes(),
            "\n\u{3000}".as_bytes(),
            "é中😀".as_bytes(),
            &[b'\n', 0xff, 0xc2],
        ] {
            let hit = hand
                .step(source, 0, true, &[hand.text], &mut 100)
                .unwrap()
                .unwrap();
            assert_eq!((hit.start, hit.end), (0, source.len()));
        }
    }

    #[test]
    fn skipped_extra_retries_preserve_indentation_without_suppressing_text() {
        let graph = graph();
        let hand = Jsx::bind(&graph).unwrap();
        for source in [b" \t{".as_slice(), b"\r \t{"] {
            let fresh = hand
                .step(source, 0, true, &[hand.text], &mut 100)
                .unwrap()
                .unwrap();
            assert_eq!(fresh.end, source.len() - 1);
            assert!(
                hand.step(source, 0, false, &[hand.text], &mut 100)
                    .unwrap()
                    .is_none()
            );
        }
        for source in [
            b"\n \t\n \t{".as_slice(),
            b"\n \t\r\n \t{",
            b"\n \t\x0b\x0c\r{",
        ] {
            for fresh in [true, false] {
                assert!(
                    hand.step(source, 0, fresh, &[hand.text], &mut 100)
                        .unwrap()
                        .is_none(),
                    "{source:?}, fresh={fresh}"
                );
            }
        }
        for source in [
            b"  text{".as_slice(),
            b"\n \ttext{",
            "\n\u{2003}{".as_bytes(),
            "\u{00a0}{".as_bytes(),
        ] {
            for fresh in [true, false] {
                let hit = hand
                    .step(source, 0, fresh, &[hand.text], &mut 100)
                    .unwrap()
                    .unwrap();
                assert_eq!((hit.start, hit.end), (0, source.len() - 1));
            }
        }
    }

    #[test]
    fn permission_and_every_byte_or_eof_observation_are_precharged() {
        let graph = graph();
        let hand = Jsx::bind(&graph).unwrap();
        for mut remaining in 0..4 {
            assert!(matches!(
                hand.step(b"a", 0, true, &[hand.text], &mut remaining),
                Err(ScannerError::Limit("program work"))
            ));
        }
        let mut remaining = 4;
        let hit = hand
            .step(b"a", 0, true, &[hand.text], &mut remaining)
            .unwrap()
            .unwrap();
        assert_eq!(hit.end, 1);
        assert_eq!(remaining, 0);
        assert!(matches!(
            hand.step(b"a", 2, true, &[hand.text], &mut 100),
            Err(ScannerError::Program(_))
        ));
    }
}
