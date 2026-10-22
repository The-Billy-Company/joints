//! A native parser runtime: compile a grammar once, parse with worker-owned
//! sessions, and retain immutable trees independently of those sessions.
#![forbid(unsafe_code)]

mod artifact;
mod compiler;
mod document;
pub mod effects;
mod ids;
mod lexer;
mod parser;
mod query;
mod recovery;
mod scanner;
mod sequence;
mod survey;
mod tree;

use std::sync::Arc;

pub use artifact::{ArtifactError, ArtifactLimits, Bank};
pub use compiler::{
    Action, Alias, AliasRecipe, Assoc, CompileError, CompileLimitation, CompileLimits,
    CompileReport, CompileRound, CompileStage, ConflictClass, ConflictRecord, Lexis, Lookahead,
    Pattern, Prec, Production, Reduction, Shape, StateItem, Step, Symbol,
};
pub use document::{Document, DocumentCost, DocumentError, DocumentOptions, DocumentPolicy, Reuse};
pub use ids::{CaptureId, FieldId, PatternId, ProductionId, ReductionId, StateId, SymbolId};
pub use lexer::{LexError, Lexeme, LexerLimits, LexicalWalk, LexicalWalkLimits};
pub use parser::{ParseLimits, ParseSession, ParsedToken, Recovery, Supply};
pub use query::{
    DeadCause, DeadPattern, ForeignPolicy, Query, QueryArgument, QueryCapture, QueryError,
    QueryLimits, QueryMatch, QueryPredicate,
};
pub use scanner::{ProbeLimits, ScannerBinding, ScannerError};
pub use sequence::SequenceError;
pub use survey::{
    SegmentSurvey, SurveyCursor, SurveyError, SurveyFusion, SurveyLimb, SurveyLimits,
    SurveyOutcome, SurveyProduct, SurveyRefusal, SurveyYield,
};
pub use tree::{ByteSpan, Confidence, Node, Point, Repair, RepairKind, Stop, Survey, TreeSnapshot};

/// Finite construction and matching budgets retained by an immutable grammar.
/// Each worker additionally supplies its own [`ParseLimits`].
#[derive(Clone, Copy, Debug, Default)]
pub struct CompileOptions {
    pub tables: CompileLimits,
    pub lexer: LexerLimits,
    pub probes: ProbeLimits,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Resource {
    Work,
    Stack,
    Nodes,
    Heads,
}

impl std::fmt::Display for Resource {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Self::Work => "work",
            Self::Stack => "stack",
            Self::Nodes => "node",
            Self::Heads => "live reading",
        })
    }
}

/// An operational failure or an explicitly refused strict parse.
#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Compile(#[from] CompileError),
    #[error(transparent)]
    Lex(#[from] LexError),
    #[error(transparent)]
    Scanner(#[from] ScannerError),
    #[error(transparent)]
    Effect(#[from] effects::EffectError),
    #[error("source has {actual} bytes; limit is {limit}")]
    SourceTooLarge { actual: usize, limit: usize },
    #[error("parser exceeded its {0} limit")]
    LimitExceeded(Resource),
    #[error("invalid parser table: {0}")]
    InvalidTable(&'static str),
    #[error("strict parse refused: {stop}", stop = .0.stop())]
    Refused(Box<TreeSnapshot>),
}

impl Error {
    /// A strict refusal retains its diagnostic tree and original bytes.
    pub fn partial_tree(&self) -> Option<&TreeSnapshot> {
        match self {
            Self::Refused(tree) => Some(tree),
            _ => None,
        }
    }
}

/// Immutable grammar tables and lexer data, safe to share between workers.
pub struct CompiledGrammar {
    pub(crate) automaton: Arc<compiler::Automaton>,
    pub(crate) lexer: lexer::Lexer,
    pub(crate) program: Option<Arc<scanner::ScannerProgram>>,
    pub(crate) options: CompileOptions,
    pub(crate) customary: Option<Arc<[u8]>>,
}

impl CompiledGrammar {
    /// Import tree-sitter grammar data and build native tables and a lexer.
    pub fn compile(source: &[u8]) -> Result<Arc<Self>, Error> {
        Self::compile_with_limits(source, CompileLimits::default())
    }

    /// Import under explicit finite construction limits for larger grammars.
    pub fn compile_with_limits(source: &[u8], limits: CompileLimits) -> Result<Arc<Self>, Error> {
        Self::compile_with_options(
            source,
            CompileOptions {
                tables: limits,
                ..CompileOptions::default()
            },
        )
    }

    /// Configure table construction, ordinary token scans, and scanner probes.
    /// Matching limits belong to the grammar and are shared by its workers.
    pub fn compile_with_options(
        source: &[u8],
        options: CompileOptions,
    ) -> Result<Arc<Self>, Error> {
        Self::compile_with_book(source, options, None)
    }

    /// Bind an explicit checked scanner book instead of the embedded registry.
    /// Malformed or incompatible books are refused, never silently ignored.
    pub fn compile_with_customary(
        source: &[u8],
        book: &[u8],
        options: CompileOptions,
    ) -> Result<Arc<Self>, Error> {
        Self::compile_with_book(source, options, Some(book))
    }

    /// Report actual construction passes under the same finite matching policy.
    /// An explicit growth factor further bounds passes after the first one;
    /// omitting it preserves the normal construction policy. The bounded report
    /// is cleared at entry and remains available when construction refuses.
    pub fn compile_with_diagnostics(
        source: &[u8],
        customary: Option<&[u8]>,
        options: CompileOptions,
        growth: Option<u32>,
        report: &mut CompileReport,
    ) -> Result<Arc<Self>, Error> {
        *report = CompileReport::default();
        Self::check_customary(customary)?;
        let automaton = compiler::Automaton::from_tree_sitter_with_diagnostics(
            source,
            options.tables,
            growth,
            report,
        )?;
        Self::with_automaton(automaton, options, customary)
    }

    fn compile_with_book(
        source: &[u8],
        options: CompileOptions,
        customary: Option<&[u8]>,
    ) -> Result<Arc<Self>, Error> {
        Self::check_customary(customary)?;
        let automaton = compiler::Automaton::from_tree_sitter_with_limits(source, options.tables)?;
        Self::with_automaton(automaton, options, customary)
    }

    fn check_customary(customary: Option<&[u8]>) -> Result<(), Error> {
        if customary.is_some_and(|book| book.len() > 1024 * 1024) {
            return Err(ScannerError::Limit("customary source bytes").into());
        }
        Ok(())
    }

    fn with_automaton(
        automaton: compiler::Automaton,
        options: CompileOptions,
        customary: Option<&[u8]>,
    ) -> Result<Arc<Self>, Error> {
        let automaton = Arc::new(automaton);
        let program =
            scanner::ScannerProgram::bind_with_customary(&automaton, customary, options.probes)?
                .map(Arc::new);
        let lexer =
            lexer::Lexer::compile_with_program(&automaton, program.as_deref(), options.lexer)?;
        Ok(Arc::new(Self {
            automaton,
            lexer,
            program,
            options,
            customary: customary.map(Arc::from),
        }))
    }

    pub fn name(&self) -> &str {
        self.automaton.name()
    }

    pub fn state_count(&self) -> usize {
        self.automaton.state_count()
    }

    pub fn symbol_count(&self) -> usize {
        self.automaton.symbol_count()
    }

    /// Classified LR alternatives and their resolution evidence. Every ID is
    /// local to this grammar. Runtime reduction ties use the concrete matching
    /// production's authored order, preserving the table's shift positions.
    pub fn conflict_diagnostics(&self) -> &[ConflictRecord] {
        self.automaton.conflicts()
    }

    /// A completed cursor's common recipe and concrete production histories.
    /// IDs from diagnostics are local to this grammar, as are their members.
    pub fn reduction(&self, id: ReductionId) -> Option<&Reduction> {
        (id.index() < self.automaton.reduction_count()).then(|| self.automaton.reduction(id))
    }

    /// Authored constraints retained in metadata but not yet enforced. Inspect
    /// these before treating runtime acceptance as full language conformance.
    pub fn limitations(&self) -> &[CompileLimitation] {
        self.automaton.limitations()
    }

    /// Resolve a grammar-local symbol for diagnostics or effect inspection.
    pub fn symbol_id(&self, name: &str) -> Option<SymbolId> {
        self.automaton.symbol_by_name(name)
    }

    pub fn symbol_name(&self, id: SymbolId) -> Option<&str> {
        (id.index() < self.symbol_count()).then(|| self.automaton.symbol(id).name.as_str())
    }

    /// External terminals for which no complete scanner cohort is implemented.
    /// They remain unavailable; a shared spelling never supplies a guess.
    pub fn unsupported_externals(&self) -> impl Iterator<Item = &str> {
        self.program
            .iter()
            .flat_map(|program| program.blind())
            .map(|&id| self.automaton.symbol(id).name.as_str())
    }

    /// Allocate a worker's mutable parsing state without recompiling grammar data.
    pub fn session(self: &Arc<Self>) -> ParseSession {
        ParseSession::new(Arc::clone(self))
    }

    /// Create an independent interning space over this grammar's automaton.
    pub fn effect_store(&self) -> effects::EffectStore {
        effects::EffectStore::new(Arc::clone(&self.automaton))
    }
}

impl std::fmt::Debug for CompiledGrammar {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("CompiledGrammar")
            .field("name", &self.name())
            .field("states", &self.state_count())
            .field("symbols", &self.symbol_count())
            .finish_non_exhaustive()
    }
}
