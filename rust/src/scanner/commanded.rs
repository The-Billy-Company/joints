//! Parser-commanded Haskell layout. A session owns its typed context stack;
//! commands are emitted only under actual admissions and explicit warrants.

use super::{ScanHit, ScannerError, charge};
use crate::{
    SymbolId,
    compiler::{Automaton, Pattern},
};

const MAX_CONTEXTS: usize = 96;
const STARTS: usize = 6;
const BRACE: usize = 6;
const SEMI: usize = 7;
const END: usize = 8;
const UNBRACE: usize = 9;
const TUPLE_OPEN: usize = 10;
const TUPLE_CLOSE: usize = 11;
const RECORD_OPEN: usize = 12;
const RECORD_CLOSE: usize = 13;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Frame {
    Layout(u32),
    Record,
    Tuple,
    Explicit,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub(super) struct CommandedState {
    frames: Vec<Frame>,
}
impl CommandedState {
    pub(super) fn clone_work(&self) -> usize {
        self.frames.len()
    }
    fn push(&mut self, frame: Frame) -> Result<(), ScannerError> {
        if self.frames.len() == MAX_CONTEXTS {
            return Err(ScannerError::Limit("commanded layout contexts"));
        }
        self.frames.push(frame);
        Ok(())
    }
    fn bracketed(&self) -> bool {
        if !matches!(self.frames.last(), Some(Frame::Layout(_))) {
            return false;
        }
        for frame in self.frames.iter().rev().skip(1) {
            match frame {
                Frame::Tuple | Frame::Record => return true,
                Frame::Explicit => return false,
                _ => {}
            }
        }
        false
    }
}
pub(super) struct Commanded {
    symbols: [SymbolId; 14],
    keywords: Vec<(SymbolId, Vec<u8>)>,
}
impl Commanded {
    pub(super) fn bind(graph: &Automaton) -> Option<Self> {
        let names = [
            "_cmd_layout_start",
            "_cmd_layout_start_do",
            "_cmd_layout_start_case",
            "_cmd_layout_start_if",
            "_cmd_layout_start_let",
            "_cmd_layout_start_quote",
            "_cmd_layout_start_explicit",
            "_cond_layout_semicolon",
            "_cond_layout_end",
            "_cond_layout_end_explicit",
            "_cmd_texp_start",
            "_cmd_texp_end",
            "_cmd_brace_open",
            "_cmd_brace_close",
        ];
        let symbols = names
            .map(|n| graph.external_by_name(n))
            .into_iter()
            .collect::<Option<Vec<_>>>()?
            .try_into()
            .ok()?;
        let keywords = graph
            .lexical_rules()
            .filter_map(|(id, rule)| {
                let Pattern::Literal(word) = &rule.pattern else {
                    return None;
                };
                keyworded(word).then(|| (id, word.clone()))
            })
            .collect();
        Some(Self { symbols, keywords })
    }
    pub(super) fn claims(&self, symbol: SymbolId) -> bool {
        self.symbols.contains(&symbol)
    }
    fn sole(&self, wanted: &[SymbolId]) -> Option<SymbolId> {
        let mut starts = self.symbols[..STARTS]
            .iter()
            .copied()
            .filter(|s| wanted.contains(s));
        let only = starts.next()?;
        starts.next().is_none().then_some(only)
    }
    fn unrivalled(&self, named: &[SymbolId]) -> bool {
        named.iter().all(|s| self.claims(*s))
    }
    fn hit(&self, slot: usize, start: usize, end: usize) -> ScanHit {
        ScanHit {
            symbol: self.symbols[slot],
            start,
            end,
        }
    }
    fn raise(
        &self,
        state: &mut CommandedState,
        source: &[u8],
        at: usize,
        remaining: &mut usize,
    ) -> Result<bool, ScannerError> {
        let lead = ahead(source, at, remaining)?;
        if lead.at == source.len() {
            return Ok(false);
        }
        state.push(Frame::Layout(lead.column))?;
        Ok(true)
    }

    #[allow(clippy::too_many_arguments)]
    pub(super) fn step(
        &self,
        state: &mut CommandedState,
        source: &[u8],
        at: usize,
        wanted: &[SymbolId],
        named: &[SymbolId],
        already: &[SymbolId],
        remaining: &mut usize,
    ) -> Result<Option<ScanHit>, ScannerError> {
        let lead = ahead(source, at, remaining)?;
        let asks = |slot: usize| {
            wanted.contains(&self.symbols[slot]) && !already.contains(&self.symbols[slot])
        };
        if asks(UNBRACE)
            && state.frames.last() == Some(&Frame::Explicit)
            && byte(source, lead.at) == b'}'
        {
            state.frames.pop();
            return Ok(Some(self.hit(UNBRACE, lead.at, lead.at + 1)));
        }
        for (slot, frame) in [(TUPLE_CLOSE, Frame::Tuple), (RECORD_CLOSE, Frame::Record)] {
            if asks(slot) && state.frames.last() == Some(&frame) {
                state.frames.pop();
                return Ok(Some(self.hit(slot, at, at)));
            }
        }
        if let Some(Frame::Layout(column)) = state.frames.last().copied() {
            let left = lead.at == source.len()
                || state.bracketed()
                || (lead.fresh && lead.column < column);
            if left && asks(END) {
                state.frames.pop();
                return Ok(Some(self.hit(END, at, at)));
            }
            // The grammar's own word-shaped literal set supplies parse-error(t).
            if asks(END) {
                for (symbol, word) in &self.keywords {
                    charge(remaining)?;
                    if whole_word(source, lead.at, word) && !wanted.contains(symbol) {
                        state.frames.pop();
                        return Ok(Some(self.hit(END, at, at)));
                    }
                }
            }
            if lead.fresh && lead.column == column && asks(SEMI) {
                return Ok(Some(self.hit(SEMI, at, at)));
            }
        }
        if asks(BRACE) && byte(source, lead.at) == b'{' {
            state.push(Frame::Explicit)?;
            return Ok(Some(self.hit(BRACE, lead.at, lead.at + 1)));
        }
        if self.unrivalled(named) {
            if let Some(symbol) = self.sole(wanted) {
                if !already.contains(&symbol) && self.raise(state, source, at, remaining)? {
                    return Ok(Some(ScanHit {
                        symbol,
                        start: at,
                        end: at,
                    }));
                }
            }
        }
        Ok(None)
    }

    /// A start that has ordinary rivals may execute after all admitted DFA
    /// spellings decline. Bracket commands still require their sole warrant.
    #[allow(clippy::too_many_arguments)]
    pub(super) fn ordered(
        &self,
        state: &mut CommandedState,
        source: &[u8],
        at: usize,
        wanted: &[SymbolId],
        named: &[SymbolId],
        already: &[SymbolId],
        remaining: &mut usize,
    ) -> Result<Option<ScanHit>, ScannerError> {
        if at > source.len() {
            return Err(ScannerError::Program(
                "commanded offset exceeds source".into(),
            ));
        }
        if self.unrivalled(named) {
            for (slot, frame) in [(TUPLE_OPEN, Frame::Tuple), (RECORD_OPEN, Frame::Record)] {
                if wanted.contains(&self.symbols[slot]) && !already.contains(&self.symbols[slot]) {
                    state.push(frame)?;
                    return Ok(Some(self.hit(slot, at, at)));
                }
            }
        }
        if let Some(symbol) = self.sole(wanted) {
            if !already.contains(&symbol) && self.raise(state, source, at, remaining)? {
                return Ok(Some(ScanHit {
                    symbol,
                    start: at,
                    end: at,
                }));
            }
        }
        Ok(None)
    }
}

#[derive(Debug, PartialEq, Eq)]
struct Lead {
    at: usize,
    column: u32,
    fresh: bool,
}
fn byte(s: &[u8], at: usize) -> u8 {
    s.get(at).copied().unwrap_or(0)
}
fn prefix(s: &[u8], at: usize, mark: &[u8]) -> bool {
    s.get(at..).is_some_and(|s| s.starts_with(mark))
}
fn symbolic(b: u8) -> bool {
    b"!#$%&*+./<=>?@\\^|-~:".contains(&b)
}
fn keyworded(word: &[u8]) -> bool {
    !word.is_empty()
        && word.iter().enumerate().all(|(i, b)| {
            b.is_ascii_alphabetic() || *b == b'_' || (i > 0 && (b.is_ascii_digit() || *b == b'\''))
        })
}
fn whole_word(s: &[u8], at: usize, word: &[u8]) -> bool {
    prefix(s, at, word)
        && !matches!(byte(s,at+word.len()),b'a'..=b'z'|b'A'..=b'Z'|b'0'..=b'9'|b'_'|b'\'')
}
fn ahead(s: &[u8], at: usize, remaining: &mut usize) -> Result<Lead, ScannerError> {
    if at > s.len() {
        return Err(ScannerError::Program(
            "commanded offset exceeds source".into(),
        ));
    }
    let mut i = at;
    let mut column = 0u32;
    let mut fresh = false;
    while i < s.len() {
        charge(remaining)?;
        match s[i] {
            b'\n' => {
                fresh = true;
                column = 0;
                i += 1;
            }
            b' ' => {
                column = column.saturating_add(1);
                i += 1;
            }
            b'\r' | 0x0c => {
                column = 0;
                i += 1;
            }
            b'\t' => {
                column = (column / 8).saturating_add(1).saturating_mul(8);
                i += 1;
            }
            b'-' => {
                let mut j = i;
                while byte(s, j) == b'-' {
                    charge(remaining)?;
                    j += 1;
                }
                // Unknown Unicode symbol classes decline a comment guess.
                if j - i < 2 || byte(s, j) >= 0x80 || symbolic(byte(s, j)) {
                    break;
                }
                while j < s.len() && s[j] != b'\n' {
                    charge(remaining)?;
                    j += 1;
                }
                i = j;
            }
            b'{' if prefix(s, i, b"{-") => {
                let mut deep = 1usize;
                i += 2;
                while i < s.len() && deep > 0 {
                    charge(remaining)?;
                    if prefix(s, i, b"{-") {
                        deep = deep
                            .checked_add(1)
                            .ok_or(ScannerError::Limit("nested layout comments"))?;
                        i += 2;
                    } else if prefix(s, i, b"-}") {
                        deep -= 1;
                        i += 2;
                    } else {
                        if s[i] == b'\n' {
                            fresh = true;
                            column = 0;
                        }
                        i += 1;
                    }
                }
            }
            _ => break,
        }
    }
    if i == s.len() {
        Ok(Lead {
            at: i,
            column: 0,
            fresh: true,
        })
    } else {
        Ok(Lead {
            at: i,
            column,
            fresh,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn program() -> Commanded {
        Commanded {
            symbols: std::array::from_fn(SymbolId::from_index),
            keywords: vec![(SymbolId::from_index(20), b"where".to_vec())],
        }
    }
    #[test]
    fn measurement_sees_through_comments_and_expands_tabs() {
        let lead = ahead(b" {- a {- b -}\n -}\n\t  x", 0, &mut 1000).unwrap();
        assert_eq!(
            lead,
            Lead {
                at: 21,
                column: 10,
                fresh: true
            }
        );
        assert_eq!(ahead(b"--x\n\tfoo", 0, &mut 1000).unwrap().column, 8);
        assert_eq!(ahead(b"-->x", 0, &mut 1000).unwrap().at, 0);
    }
    #[test]
    fn frames_keep_layout_brackets_and_explicit_blocks_distinct() {
        let mut state = CommandedState::default();
        assert_eq!(state.clone_work(), 0);
        state.push(Frame::Tuple).unwrap();
        state.push(Frame::Layout(4)).unwrap();
        assert!(state.bracketed());
        state.push(Frame::Explicit).unwrap();
        state.push(Frame::Layout(9)).unwrap();
        assert!(!state.bracketed());
        assert_eq!(state.clone_work(), 4);
    }
    #[test]
    fn command_pushes_need_a_warrant_or_post_dfa_refusal() {
        let program = program();
        let mut state = CommandedState::default();
        let order = program.symbols[0];
        let rival = SymbolId::from_index(30);
        assert!(
            program
                .step(
                    &mut state,
                    b"x",
                    0,
                    &[order, rival],
                    &[order, rival],
                    &[],
                    &mut 1000
                )
                .unwrap()
                .is_none()
        );
        assert!(state.frames.is_empty());
        assert!(
            program
                .ordered(
                    &mut state,
                    b"x",
                    0,
                    &[order, rival],
                    &[order, rival],
                    &[],
                    &mut 1000
                )
                .unwrap()
                .is_some()
        );
        assert_eq!(state.frames, [Frame::Layout(0)]);
        assert!(
            program
                .ordered(&mut state, b"", 0, &[order], &[order], &[], &mut 1000)
                .unwrap()
                .is_none()
        );
    }
    #[test]
    fn column_eof_and_refused_keywords_close_one_actual_layout() {
        let program = program();
        let end = program.symbols[END];
        let semi = program.symbols[SEMI];
        let mut state = CommandedState {
            frames: vec![Frame::Layout(0), Frame::Layout(4)],
        };
        assert_eq!(
            program
                .step(&mut state, b"\nx", 0, &[end, semi], &[], &[], &mut 1000)
                .unwrap()
                .unwrap()
                .symbol,
            end
        );
        assert_eq!(state.frames.len(), 1);
        assert_eq!(
            program
                .step(&mut state, b"where x", 0, &[end], &[], &[], &mut 1000)
                .unwrap()
                .unwrap()
                .symbol,
            end
        );
        assert!(state.frames.is_empty());
        state.push(Frame::Explicit).unwrap();
        assert!(
            program
                .step(&mut state, b"", 0, &[end], &[], &[], &mut 1000)
                .unwrap()
                .is_none()
        );
    }
    #[test]
    fn keyword_boundaries_and_limits_are_explicit() {
        for word in [b"where".as_slice(), b"in", b"_hole", b"r2"] {
            assert!(keyworded(word));
        }
        for word in [b"".as_slice(), b"->", b"2nd", b"'a"] {
            assert!(!keyworded(word));
        }
        assert!(!whole_word(b"where'", 0, b"where"));
        assert!(whole_word(b"where", 0, b"where"));
        assert!(matches!(
            ahead(&[b' '; 20], 0, &mut 1),
            Err(ScannerError::Limit(_))
        ));
        let mut state = CommandedState {
            frames: vec![Frame::Tuple; MAX_CONTEXTS],
        };
        assert!(matches!(
            state.push(Frame::Tuple),
            Err(ScannerError::Limit(_))
        ));
    }
}
