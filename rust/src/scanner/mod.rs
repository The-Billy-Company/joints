//! Stateful scanner programs are immutable; a parse owns every mutable organ.

mod bounded;
mod cohort;
mod commanded;
mod engine;
mod fences;
mod jsx;
mod lookahead;
mod probe;
mod program;
mod provisions;
mod rust;
mod swift;

use crate::{compiler::Automaton, ids::SymbolId};
use thiserror::Error;

pub use probe::ProbeLimits;

#[derive(Debug, Error)]
pub enum ScannerError {
    #[error("invalid scanner probe limits: {0}")]
    InvalidLimits(&'static str),
    #[error("invalid scanner program: {0}")]
    Program(String),
    #[error("scanner probe failed: {0}")]
    Probe(String),
    #[error("scanner exceeded its {0} limit")]
    Limit(&'static str),
}

#[derive(Clone, Debug, Default)]
pub(crate) struct ScannerState {
    frames: Vec<Frame>,
    marks: Vec<Mark>,
    registers: [u32; 8],
    since: usize,
    columns: Vec<u32>,
    quotes: Vec<cohort::Fence>,
    fences: fences::FenceState,
    commanded: commanded::CommandedState,
    spent: Spent,
    index: Option<std::sync::Arc<engine::SourceIndex>>,
}

impl PartialEq for ScannerState {
    fn eq(&self, other: &Self) -> bool {
        self.frames == other.frames
            && self.marks == other.marks
            && self.registers == other.registers
            && self.columns == other.columns
            && self.quotes == other.quotes
            && self.fences == other.fences
            && self.commanded == other.commanded
            && self.since == other.since
            && self.spent == other.spent
    }
}
impl Eq for ScannerState {}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) struct Frame {
    pub width: u32,
    pub kind: u8,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) struct Mark {
    pub kind: u8,
    pub count: u32,
    pub tag: Vec<u8>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct ScanHit {
    pub symbol: SymbolId,
    pub start: usize,
    pub end: usize,
}

pub(crate) fn charge(remaining: &mut usize) -> Result<(), ScannerError> {
    charge_work(remaining, 1)
}

fn charge_work(remaining: &mut usize, amount: usize) -> Result<(), ScannerError> {
    *remaining = remaining
        .checked_sub(amount)
        .ok_or(ScannerError::Limit("program work"))?;
    Ok(())
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
struct Shape {
    frames: Vec<Frame>,
    marks: Vec<Mark>,
    registers: [u32; 8],
    columns: Vec<u32>,
    quotes: Vec<cohort::Fence>,
    fences: fences::FenceState,
    commanded: commanded::CommandedState,
}
impl Shape {
    fn clone_work(&self) -> usize {
        organs_clone_work(
            &self.frames,
            &self.marks,
            &self.columns,
            &self.quotes,
            &self.fences,
            &self.commanded,
        )
    }
}

fn organs_clone_work(
    frames: &[Frame],
    marks: &[Mark],
    columns: &[u32],
    quotes: &[cohort::Fence],
    fences: &fences::FenceState,
    commanded: &commanded::CommandedState,
) -> usize {
    let fixed = 1usize
        .saturating_add(frames.len())
        .saturating_add(columns.len())
        .saturating_add(fences.clone_work())
        .saturating_add(commanded.clone_work());
    let marks = marks.iter().fold(fixed, |work, mark| {
        work.saturating_add(1).saturating_add(mark.tag.len())
    });
    quotes
        .iter()
        .fold(marks, |work, quote| work.saturating_add(quote.clone_work()))
}

impl ScannerState {
    /// Replay shares the current version's immutable index across saved
    /// semantic entry states; scanner organs remain those of the recipient.
    pub(crate) fn copy_source_index_from(&mut self, other: &Self) {
        self.index = other.index.clone();
    }

    /// Owned entries and delimiter bytes copied by Clone. The source index is
    /// immutable shared input data; cloning its Arc copies only one reference.
    pub(crate) fn clone_work(&self) -> usize {
        self.shape_clone_work()
            .saturating_add(self.spent.symbols.len())
            .saturating_add(self.spent.shape.as_ref().map_or(0, Shape::clone_work))
            .saturating_add(usize::from(self.index.is_some()))
    }
    fn shape_clone_work(&self) -> usize {
        organs_clone_work(
            &self.frames,
            &self.marks,
            &self.columns,
            &self.quotes,
            &self.fences,
            &self.commanded,
        )
    }
    pub(crate) fn reset(&mut self) {
        // The source index is immutable derived data, not scanner memory.
        let index = self.index.take();
        *self = Self::default();
        self.index = index;
    }
    fn shape(&self) -> Shape {
        Shape {
            frames: self.frames.clone(),
            marks: self.marks.clone(),
            registers: self.registers,
            columns: self.columns.clone(),
            quotes: self.quotes.clone(),
            fences: self.fences.clone(),
            commanded: self.commanded.clone(),
        }
    }
}
#[derive(Clone, Debug, Default, PartialEq, Eq)]
struct Spent {
    at: Option<usize>,
    shape: Option<Shape>,
    symbols: Vec<SymbolId>,
    total: usize,
}
impl Spent {
    fn standing(&self, at: usize, shape: &Shape) -> &[SymbolId] {
        if self.at == Some(at) && self.shape.as_ref() == Some(shape) {
            &self.symbols
        } else {
            &[]
        }
    }
    fn record(&mut self, at: usize, shape: Shape, symbol: SymbolId) -> Result<(), ScannerError> {
        if self.at != Some(at) {
            self.at = Some(at);
            self.total = 0;
            self.symbols.clear();
            self.shape = None;
        }
        if self.total >= 256 {
            return Err(ScannerError::Limit("zero-width answers"));
        }
        if self.shape.as_ref() != Some(&shape) {
            self.shape = Some(shape);
            self.symbols.clear();
        }
        if self.symbols.contains(&symbol) {
            return Err(ScannerError::Program(
                "repeated zero-width scanner answer".into(),
            ));
        }
        if self.symbols.len() == 8 {
            return Err(ScannerError::Limit("zero-width symbol cohort"));
        }
        self.symbols.push(symbol);
        self.total += 1;
        Ok(())
    }
}

pub(crate) struct ScannerProgram {
    book: Option<program::Book>,
    cohorts: cohort::Cohorts,
    bounded: bounded::Bounded,
    rust: Option<rust::Rust>,
    swift: Option<swift::Swift>,
    jsx: Option<jsx::Jsx>,
    lookahead: lookahead::Lookahead,
    fences: Option<fences::FenceProgram>,
    commanded: Option<commanded::Commanded>,
    provisions: provisions::Provisions,
    blind: Vec<SymbolId>,
}
impl ScannerProgram {
    pub(crate) fn artifact_sources() -> &'static [&'static str] {
        &program::BOOKS
    }
    #[cfg(test)]
    pub(crate) fn bind(grammar: &Automaton) -> Result<Option<Self>, ScannerError> {
        Self::bind_with_limits(grammar, ProbeLimits::default())
    }
    #[cfg(test)]
    pub(crate) fn bind_with_limits(
        grammar: &Automaton,
        limits: ProbeLimits,
    ) -> Result<Option<Self>, ScannerError> {
        Self::bind_with_customary(grammar, None, limits)
    }
    pub(crate) fn bind_with_customary(
        grammar: &Automaton,
        customary: Option<&[u8]>,
        limits: ProbeLimits,
    ) -> Result<Option<Self>, ScannerError> {
        limits.validate()?;
        if grammar.external_ids().is_empty() && customary.is_none() {
            return Ok(None);
        }
        let mut book = None;
        if let Some(bytes) = customary {
            if bytes.len() > 1 << 20 {
                return Err(ScannerError::Limit("book bytes"));
            }
            let source = std::str::from_utf8(bytes)
                .map_err(|_| ScannerError::Program("scanner book is not UTF-8 JSON".into()))?;
            if !program::Book::matches(source, grammar)? {
                return Err(ScannerError::Program(
                    "explicit scanner book cohort does not match the grammar's external terminals"
                        .into(),
                ));
            }
            book = Some(program::Book::compile_with_limits(source, grammar, limits)?);
        } else {
            for source in program::BOOKS {
                if program::Book::matches(source, grammar)? {
                    if book.is_some() {
                        return Err(ScannerError::Program(
                            "multiple scanner books bind one cohort".into(),
                        ));
                    }
                    book = Some(program::Book::compile_with_limits(source, grammar, limits)?);
                }
            }
        }
        let cohorts = cohort::Cohorts::bind(grammar);
        let fences = fences::FenceProgram::bind(grammar)?;
        let mut bounded = bounded::Bounded::bind(grammar);
        let book_claimed = grammar
            .external_ids()
            .iter()
            .copied()
            .filter(|s| book.as_ref().is_some_and(|b| b.claims(*s)))
            .collect::<Vec<_>>();
        let commanded = commanded::Commanded::bind(grammar)
            .filter(|c| !book_claimed.iter().any(|&s| c.claims(s)));
        bounded.remove_claimed(&book_claimed);
        let mut rust = rust::Rust::bind(grammar);
        if let Some(rust) = &mut rust {
            rust.remove_claimed(&book_claimed);
        }
        // This hand reads the embedded Swift book's raw-string mark protocol.
        // A byte-identical explicit copy has the same protocol. Arbitrary
        // replacement books retain full ownership of their own organs.
        let mut swift = if customary.is_none_or(|bytes| bytes == program::SWIFT_BOOK.as_bytes()) {
            swift::Swift::bind(grammar)
        } else {
            None
        };
        if let Some(swift) = &mut swift {
            swift.remove_claimed(&book_claimed);
        }
        let mut jsx = jsx::Jsx::bind(grammar);
        if let Some(jsx) = &mut jsx {
            jsx.remove_claimed(&book_claimed);
        }
        let mut lookahead = lookahead::Lookahead::bind(grammar)?;
        lookahead.remove_claimed(&book_claimed);
        let mut provisions = provisions::Provisions::bind_with_limits(grammar, limits)?;
        let claimed = grammar
            .external_ids()
            .iter()
            .copied()
            .filter(|s| {
                book.as_ref().is_some_and(|b| b.claims(*s))
                    || cohorts.claims(*s)
                    || commanded.as_ref().is_some_and(|c| c.claims(*s))
                    || bounded.claims(*s)
                    || rust
                        .as_ref()
                        .is_some_and(|hand| hand.claims(*s) || hand.controls(*s))
                    || swift
                        .as_ref()
                        .is_some_and(|hand| hand.claims(*s) || hand.controls(*s))
                    || jsx.as_ref().is_some_and(|hand| hand.claims(*s))
                    || lookahead.claims(*s)
                    || fences.as_ref().is_some_and(|f| f.claims(*s))
            })
            .collect::<Vec<_>>();
        provisions.remove_claimed(&claimed);
        let blind = grammar
            .external_ids()
            .iter()
            .copied()
            .filter(|s| {
                grammar
                    .symbol(*s)
                    .lexis
                    .as_ref()
                    .is_some_and(|l| l.pattern == crate::compiler::Pattern::External)
                    && !book.as_ref().is_some_and(|b| b.claims(*s))
                    && !cohorts.claims(*s)
                    && !commanded.as_ref().is_some_and(|c| c.claims(*s))
                    && !bounded.claims(*s)
                    && !rust
                        .as_ref()
                        .is_some_and(|hand| hand.claims(*s) || hand.controls(*s))
                    && !swift
                        .as_ref()
                        .is_some_and(|hand| hand.claims(*s) || hand.controls(*s))
                    && !jsx.as_ref().is_some_and(|hand| hand.claims(*s))
                    && !lookahead.claims(*s)
                    && !fences.as_ref().is_some_and(|f| f.claims(*s))
                    && !provisions.claims(*s)
            })
            .collect();
        Ok(Some(Self {
            book,
            cohorts,
            bounded,
            rust,
            swift,
            jsx,
            lookahead,
            fences,
            commanded,
            provisions,
            blind,
        }))
    }
    pub(crate) fn lexical_rules(
        &self,
    ) -> impl Iterator<Item = (SymbolId, &crate::compiler::Lexis)> {
        self.provisions.rules()
    }
    pub(crate) fn blind(&self) -> &[SymbolId] {
        &self.blind
    }
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn step(
        &self,
        state: &mut ScannerState,
        source: &[u8],
        at: usize,
        fresh: bool,
        after_node: bool,
        wanted: &[SymbolId],
        named: &[SymbolId],
        remaining: &mut usize,
    ) -> Result<Option<ScanHit>, ScannerError> {
        charge_work(remaining, state.shape_clone_work())?;
        let shape = state.shape();
        let already = state.spent.standing(at, &shape);
        charge_work(remaining, already.len())?;
        let already = already.to_vec();
        let written = if let Some(book) = &self.book {
            book.step(state, source, at, fresh, wanted, named, &already, remaining)?
        } else {
            None
        };
        let written = if written.is_some() {
            written
        } else if let Some(rust) = &self.rust {
            let permission = rust.permissions(wanted, remaining)?;
            if permission.blocked {
                return Ok(None);
            }
            // Rust's bounded comment/string branch precedes doc/numeric/raw
            // tokens in its pinned scanner. It remains the existing hand.
            let bounded = self.bounded.step(source, at, wanted, &already, remaining)?;
            if bounded.is_some() {
                bounded
            } else if permission.block {
                return Ok(None);
            } else {
                rust.step(source, at, &permission, &already, remaining)?
            }
        } else {
            None
        };
        let written = if written.is_some() {
            written
        } else if let Some(swift) = &self.swift {
            swift.step(state, source, at, wanted, remaining)?
        } else {
            None
        };
        let written = if written.is_some() {
            written
        } else if let Some(jsx) = &self.jsx {
            jsx.step(source, at, fresh, wanted, remaining)?
        } else {
            None
        };
        let written = if written.is_some() {
            written
        } else if let Some(fences) = &self.fences {
            fences.step(&mut state.fences, source, at, fresh, wanted, remaining)?
        } else {
            None
        };
        let hit = if written.is_some() {
            written
        } else {
            self.cohorts.step(
                state, source, at, fresh, after_node, wanted, &already, remaining,
            )?
        };
        let hit = if hit.is_some() {
            hit
        } else if let Some(commanded) = &self.commanded {
            commanded.step(
                &mut state.commanded,
                source,
                at,
                wanted,
                named,
                &already,
                remaining,
            )?
        } else {
            None
        };
        let hit = if hit.is_some() {
            hit
        } else if self.rust.is_none() {
            self.bounded.step(source, at, wanted, &already, remaining)?
        } else {
            None
        };
        let hit = if hit.is_some() {
            hit
        } else {
            self.lookahead.step(
                source,
                at,
                fresh,
                !state.quotes.is_empty() || !state.fences.is_empty(),
                wanted,
                &already,
                remaining,
            )?
        };
        let hit = if hit.is_some() {
            hit
        } else {
            self.provisions
                .guarded(source, at, fresh, wanted, remaining)?
        };
        if let Some(hit) = hit {
            if hit.end == at {
                state.spent.record(at, shape, hit.symbol)?;
            }
        }
        Ok(hit)
    }
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn ordered(
        &self,
        state: &mut ScannerState,
        source: &[u8],
        at: usize,
        _fresh: bool,
        _after_node: bool,
        wanted: &[SymbolId],
        named: &[SymbolId],
        remaining: &mut usize,
    ) -> Result<Option<ScanHit>, ScannerError> {
        charge_work(remaining, state.shape_clone_work())?;
        let shape = state.shape();
        let already = state.spent.standing(at, &shape);
        charge_work(remaining, already.len())?;
        let already = already.to_vec();
        let hit = if let Some(commanded) = &self.commanded {
            commanded.ordered(
                &mut state.commanded,
                source,
                at,
                wanted,
                named,
                &already,
                remaining,
            )?
        } else {
            None
        };
        if let Some(hit) = hit {
            if hit.end == at {
                state.spent.record(at, shape, hit.symbol)?;
            }
        }
        Ok(hit)
    }
}

/// How an authored external terminal is answered by this immutable grammar.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ScannerBinding {
    Customary,
    Hand,
    Provision,
    /// An unproducible scanner-protocol control, rather than a token spelling.
    Control,
    Lexical,
    Blind,
}

impl ScannerBinding {
    pub fn label(self) -> &'static str {
        match self {
            Self::Customary => "customary",
            Self::Hand => "hand",
            Self::Provision => "provision",
            Self::Control => "control",
            Self::Lexical => "ordinary lexical rule",
            Self::Blind => "blind",
        }
    }
}

impl crate::CompiledGrammar {
    /// Report the bound implementation, not a guess from a terminal's spelling.
    pub fn external_bindings(
        &self,
    ) -> impl ExactSizeIterator<Item = (SymbolId, ScannerBinding)> + '_ {
        self.automaton.external_ids().iter().copied().map(|symbol| {
            let binding = if self
                .automaton
                .symbol(symbol)
                .lexis
                .as_ref()
                .is_some_and(|l| l.pattern != crate::compiler::Pattern::External)
            {
                ScannerBinding::Lexical
            } else if let Some(program) = &self.program {
                if program.blind.contains(&symbol) {
                    ScannerBinding::Blind
                } else if program
                    .book
                    .as_ref()
                    .is_some_and(|book| book.claims(symbol))
                {
                    ScannerBinding::Customary
                } else if program
                    .rust
                    .as_ref()
                    .is_some_and(|hand| hand.controls(symbol))
                    || program
                        .swift
                        .as_ref()
                        .is_some_and(|hand| hand.controls(symbol))
                {
                    ScannerBinding::Control
                } else if program.provisions.claims(symbol) {
                    ScannerBinding::Provision
                } else {
                    ScannerBinding::Hand
                }
            } else {
                ScannerBinding::Blind
            };
            (symbol, binding)
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn explicit_books_claim_only_their_checked_cohort_and_execute_its_program() {
        let grammar = Automaton::from_tree_sitter(br#"{"externals":[{"type":"SYMBOL","name":"answer"}],"rules":{"doc":{"type":"SYMBOL","name":"answer"}}}"#).unwrap();
        let answer = grammar.external_by_name("answer").unwrap();
        let source = br#"{"cohort":["answer"],"probes":{"body":"x+"},"rules":[{"phase":"bounded","when":[["wanted","answer"],["probe","body"]],"then":[["emit","answer"]]}]}"#;
        let program =
            ScannerProgram::bind_with_customary(&grammar, Some(source), ProbeLimits::default())
                .unwrap()
                .unwrap();
        assert!(program.blind().is_empty());
        let hit = program
            .step(
                &mut ScannerState::default(),
                b"xxx",
                0,
                true,
                false,
                &[answer],
                &[answer],
                &mut 1000,
            )
            .unwrap()
            .unwrap();
        assert_eq!((hit.symbol, hit.start, hit.end), (answer, 0, 3));
        assert!(
            program
                .step(
                    &mut ScannerState::default(),
                    b"xxx",
                    0,
                    true,
                    false,
                    &[],
                    &[],
                    &mut 1000
                )
                .unwrap()
                .is_none()
        );
    }

    #[test]
    fn explicit_book_replaces_the_embedded_book_without_an_implicit_fallback() {
        let grammar = Automaton::from_tree_sitter(br#"{"externals":[{"type":"SYMBOL","name":"_control_tail_gate"},{"type":"SYMBOL","name":"error_sentinel"}],"rules":{"doc":{"type":"STRING","value":"x"}}}"#).unwrap();
        let gate = grammar.external_by_name("_control_tail_gate").unwrap();
        let default = ScannerProgram::bind(&grammar).unwrap().unwrap();
        assert!(
            default
                .step(
                    &mut ScannerState::default(),
                    b"else",
                    0,
                    true,
                    false,
                    &[gate],
                    &[gate],
                    &mut 10000
                )
                .unwrap()
                .is_some()
        );
        let override_ = br#"{"cohort":["_control_tail_gate"],"probes":{"gate":"never"},"rules":[{"phase":"bounded","when":[["wanted","_control_tail_gate"],["probe","gate"]],"then":[["emit","_control_tail_gate",0]]}]}"#;
        let program =
            ScannerProgram::bind_with_customary(&grammar, Some(override_), ProbeLimits::default())
                .unwrap()
                .unwrap();
        assert!(
            program
                .step(
                    &mut ScannerState::default(),
                    b"else",
                    0,
                    true,
                    false,
                    &[gate],
                    &[gate],
                    &mut 10000
                )
                .unwrap()
                .is_none()
        );
        for refused in [
            b"not JSON".as_slice(),
            b"\xff",
            br#"{"cohort":["_control_tail_gate"],"cohort":["_control_tail_gate"],"rules":[]}"#,
            br#"{"cohort":["missing"],"rules":[]}"#,
            br#"{"cohort":["_control_tail_gate"],"rules":[{"phase":"typo"}]}"#,
        ] {
            assert!(
                ScannerProgram::bind_with_customary(
                    &grammar,
                    Some(refused),
                    ProbeLimits::default()
                )
                .is_err()
            );
        }
        assert!(
            ScannerProgram::bind_with_customary(
                &grammar,
                Some(&vec![b' '; (1 << 20) + 1]),
                ProbeLimits::default()
            )
            .is_err()
        );
    }

    #[test]
    fn custom_book_native_probe_budget_is_checked_before_compilation() {
        let grammar=Automaton::from_tree_sitter(br#"{"externals":[{"type":"SYMBOL","name":"answer"}],"rules":{"doc":{"type":"SYMBOL","name":"answer"}}}"#).unwrap();
        let probes = (0..1025)
            .map(|i| (format!("p{i}"), serde_json::json!("[")))
            .collect::<serde_json::Map<_, _>>();
        let named = serde_json::json!({"cohort":["answer"],"probes":probes,"rules":[]});
        let classes = serde_json::json!({"cohort":["answer"],"classes":{"many":vec![serde_json::json!(["[","answer"]);1025]},"rules":[]});
        for source in [named, classes] {
            let bytes = serde_json::to_vec(&source).unwrap();
            assert!(bytes.len() < 1 << 20);
            assert!(matches!(
                ScannerProgram::bind_with_customary(&grammar, Some(&bytes), ProbeLimits::default()),
                Err(ScannerError::Limit("book instructions"))
            ));
        }
    }

    #[test]
    fn clone_work_counts_owned_marks_and_the_independent_spent_snapshot() {
        let mut state = ScannerState::default();
        state.frames.push(Frame { width: 4, kind: 1 });
        state.marks.push(Mark {
            kind: 2,
            count: 8,
            tag: vec![b'a'; 8],
        });
        state.columns.extend([4, 8]);
        assert_eq!(state.clone_work(), 13);
        state
            .spent
            .record(0, state.shape(), SymbolId::from_index(1))
            .unwrap();
        assert_eq!(state.clone_work(), 27);
        state.marks[0].tag.extend([b'b'; 5]);
        assert_eq!(state.clone_work(), 32);
        assert_eq!(state.spent.shape.as_ref().unwrap().marks[0].tag.len(), 8);
    }
    #[test]
    fn scanner_snapshot_work_refuses_before_copying_or_mutating_organs() {
        let grammar = Automaton::from_tree_sitter(br#"{"externals":[{"type":"SYMBOL","name":"unknown"}],"rules":{"doc":{"type":"STRING","value":"x"}}}"#).unwrap();
        let program = ScannerProgram::bind(&grammar).unwrap().unwrap();
        let mut state = ScannerState::default();
        state.marks.push(Mark {
            kind: 1,
            count: 16,
            tag: vec![b'a'; 16],
        });
        let saved = state.clone();
        let cost = state.shape_clone_work();
        assert_eq!(cost, 18);
        assert!(matches!(
            program.step(&mut state, b"x", 0, true, false, &[], &[], &mut (cost - 1)),
            Err(ScannerError::Limit("program work"))
        ));
        assert_eq!(state, saved);
        let mut exact = cost;
        assert_eq!(
            program
                .step(&mut state, b"x", 0, true, false, &[], &[], &mut exact)
                .unwrap(),
            None
        );
        assert_eq!(exact, 0);
        assert_eq!(state, saved);
        assert!(matches!(
            charge_work(&mut (usize::MAX - 1), usize::MAX),
            Err(ScannerError::Limit("program work"))
        ));
    }
    #[test]
    fn only_unrecognized_named_externals_are_blind() {
        let grammar=Automaton::from_tree_sitter(br#"{"name":"unknown","externals":[{"type":"SYMBOL","name":"mystery"},{"type":"STRING","value":"]"}],"rules":{"doc":{"type":"STRING","value":"x"}}}"#).unwrap();
        let program = ScannerProgram::bind(&grammar).unwrap().unwrap();
        assert_eq!(
            program.blind(),
            [grammar.external_by_name("mystery").unwrap()]
        );
    }
    #[test]
    fn zero_width_progress_tracks_pre_answer_memory_and_a_total_ceiling() {
        let symbol = SymbolId::from_index(1);
        let mut state = ScannerState::default();
        let mut spent = Spent::default();
        for n in 0..256 {
            state.registers[0] = n;
            let shape = state.shape();
            assert!(spent.standing(0, &shape).is_empty());
            spent.record(0, shape.clone(), symbol).unwrap();
            assert_eq!(spent.standing(0, &shape), [symbol]);
        }
        state.registers[0] = 256;
        assert!(matches!(
            spent.record(0, state.shape(), symbol),
            Err(ScannerError::Limit("zero-width answers"))
        ));
        spent.record(1, state.shape(), symbol).unwrap();
        assert_eq!(spent.total, 1);
    }
}
