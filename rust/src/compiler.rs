//! Ordered tree-sitter grammar import and a bounded, immutable LALR automaton.
//!
//! Lowering retains the tree recipe independently of the parse table. The graph
//! also survives table resolution: effects ask about symbol transitions, not
//! merely the terminal action selected for a cell.

use std::cell::Cell;
use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::fmt;
use std::sync::Arc;

use serde::{Deserialize, Deserializer, de};
use serde_json::Value;
use thiserror::Error;

use crate::ids::{FieldId, ProductionId, ReductionId, StateId, SymbolId};

mod table;
use table::FrozenTables;

const MAX_SOURCE: usize = 16 * 1024 * 1024;
const MAX_DEPTH: usize = 96;
const MAX_SYMBOLS: usize = 4096;
const MAX_PRODUCTIONS: usize = 16384;
const MAX_STEPS: usize = 262144;
const MAX_ALTERNATIVES: usize = 16384;
const MAX_STATES: usize = 131_072;
const MAX_ITEMS: usize = 10_000_000;
const MAX_WORK: usize = 3_000_000_000;

#[derive(Clone, Copy, Debug)]
pub struct CompileLimits {
    pub source_bytes: usize,
    pub symbols: usize,
    pub productions: usize,
    pub production_steps: usize,
    pub alternatives: usize,
    pub states: usize,
    pub items: usize,
    pub work: usize,
}

impl Default for CompileLimits {
    fn default() -> Self {
        Self {
            source_bytes: MAX_SOURCE,
            symbols: MAX_SYMBOLS,
            productions: MAX_PRODUCTIONS,
            production_steps: MAX_STEPS,
            alternatives: MAX_ALTERNATIVES,
            states: MAX_STATES,
            items: MAX_ITEMS,
            work: MAX_WORK,
        }
    }
}

/// Actual construction strategy for one attempted table pass.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CompileStage {
    Lalr,
    RefinedLalr,
    Canonical,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CompileRound {
    pub pass: usize,
    pub stage: CompileStage,
    pub state_limit: usize,
    /// Absent when this pass did not return its collection.
    pub states: Option<usize>,
    /// Full construction items, before final diagnostic-kernel filtering.
    pub items: Option<usize>,
    pub work_before: usize,
    pub work_after: usize,
    pub contested: usize,
    pub residual: usize,
    pub priority_sensitive: bool,
    pub completed: bool,
}

/// Operation-local constructor observations, including failed attempts.
/// At most128 rounds are retained; `truncated` makes omitted events explicit.
/// Matching and artifact data do not retain this report or its growth request.
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct CompileReport {
    pub rounds: Vec<CompileRound>,
    pub truncated: bool,
    pub work: usize,
    pub growth_state_limit: Option<usize>,
    pub tables_complete: bool,
}
const MAX_COMPILE_ROUNDS: usize = 128;

struct CompileWork {
    used: Cell<usize>,
    limit: usize,
}

impl CompileWork {
    fn new(limit: usize) -> Self {
        Self {
            used: Cell::new(0),
            limit,
        }
    }
    fn charge(&self, amount: usize, label: &'static str) -> Result<(), CompileError> {
        let next = self
            .used
            .get()
            .checked_add(amount)
            .ok_or(CompileError::Limit(label))?;
        if next > self.limit {
            return Err(CompileError::Limit(label));
        }
        self.used.set(next);
        Ok(())
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Shape {
    Named,
    Anonymous,
    Hidden,
    Invented,
}

impl Shape {
    pub fn visible(self) -> bool {
        matches!(self, Self::Named | Self::Anonymous)
    }

    pub fn named(self) -> bool {
        matches!(self, Self::Named | Self::Hidden)
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd)]
pub enum Pattern {
    Literal(Vec<u8>),
    Regex(String),
    External,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Lexis {
    pub pattern: Pattern,
    pub immediate: bool,
    pub precedence: i32,
    pub declaration_order: u32,
}

#[derive(Clone, Debug)]
pub struct Symbol {
    pub name: String,
    pub shape: Shape,
    pub lexis: Option<Lexis>,
    /// Anonymous external entries can also have an ordinary lexical spelling.
    pub external: bool,
}

#[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd)]
pub struct Alias {
    /// Expansion copies the recipe, never the spelling's byte allocation.
    pub name: Arc<str>,
    pub named: bool,
}

/// Whether an authored alias remains in the local reduction recipe after
/// default-alias extraction, before explicit inline lowering loses its origin.
/// This does not change the alias used to render the actual syntax tree.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Ord, PartialOrd)]
pub enum AliasRecipe {
    #[default]
    Empty,
    Local,
}

#[derive(Clone, Debug, Default, Eq, PartialEq, Ord, PartialOrd)]
pub enum Prec {
    #[default]
    None,
    Level(i32),
    Named(Arc<str>),
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Ord, PartialOrd)]
pub enum Assoc {
    #[default]
    None,
    Left,
    Right,
}

#[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd)]
pub struct Step {
    pub symbol: SymbolId,
    pub field: Option<FieldId>,
    pub alias: Option<Alias>,
    pub alias_recipe: AliasRecipe,
    pub prec: Prec,
    pub assoc: Assoc,
    pub region: usize,
    pub spliced: bool,
    pub reserved: Option<Arc<str>>,
}

#[derive(Clone, Debug)]
pub struct Production {
    pub lhs: SymbolId,
    pub steps: Vec<Step>,
    pub dynamic_precedence: i32,
}

/// One completed cursor recipe with concrete RHS histories. The parser must
/// select a production matching its actual frame symbols before reducing.
#[derive(Clone, Debug)]
pub struct Reduction {
    pub lhs: SymbolId,
    pub width: usize,
    pub dynamic_precedence: i32,
    pub productions: Vec<ProductionId>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd)]
pub enum Lookahead {
    Terminal(SymbolId),
    End,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd)]
pub enum Action {
    Shift(StateId),
    Reduce(ReductionId),
    Accept,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ConflictClass {
    Declared,
    Repetition,
    Unwritten,
    Sided,
    /// An inline victim supplied a side over a wider authored region. It may
    /// order exploration, but cannot delete an interpretation of its caller.
    Absorbed,
    /// A completion introduced solely by bounded CFG factoring. Both paths
    /// remain until an authored production can be compared or attributed.
    Normalized,
    Residual,
}

#[derive(Clone, Debug)]
pub struct ConflictRecord {
    pub state: StateId,
    pub lookahead: Lookahead,
    pub class: ConflictClass,
    pub party: Vec<SymbolId>,
    pub actions: Vec<Action>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum CompileLimitation {
    /// Context names are retained, but keyword reservation is not yet enforced.
    ReservedWordContexts { contexts: Vec<String> },
}

#[derive(Clone, Debug)]
enum RankRef {
    Name(Arc<str>),
    Rule(SymbolId),
}

#[derive(Debug, Error)]
pub enum CompileError {
    #[error("malformed grammar: {0}")]
    Malformed(String),
    #[error("unsupported grammar feature: {0}")]
    Unsupported(String),
    #[error("grammar exceeds {0} limit")]
    Limit(&'static str),
    #[error("unresolved conflict in state {state} on {lookahead}: {actions:?}")]
    Conflict {
        state: usize,
        lookahead: String,
        actions: Vec<Action>,
    },
}

/// All indexes address this immutable grammar. Parser sessions own their scratch.
#[derive(Debug)]
pub(crate) struct Automaton {
    name: String,
    symbols: Vec<Symbol>,
    productions: Vec<Production>,
    reductions: Vec<Reduction>,
    fields: Vec<String>,
    supertypes: Vec<SymbolId>,
    names: BTreeMap<String, SymbolId>,
    start: SymbolId,
    extras: Vec<SymbolId>,
    extra_entries: Vec<(SymbolId, StateId)>,
    word: Option<SymbolId>,
    externals: Vec<SymbolId>,
    external_names: BTreeMap<String, SymbolId>,
    tables: FrozenTables,
    kernels: Vec<Vec<StateItem>>,
    cursor_histories: BTreeMap<StateItem, Vec<ProductionId>>,
    conflicts: Vec<ConflictRecord>,
    limitations: Vec<CompileLimitation>,
}

impl Automaton {
    #[cfg(test)]
    pub(crate) fn from_tree_sitter(bytes: &[u8]) -> Result<Self, CompileError> {
        Self::from_tree_sitter_with_limits(bytes, CompileLimits::default())
    }

    pub(crate) fn from_tree_sitter_with_limits(
        bytes: &[u8],
        limits: CompileLimits,
    ) -> Result<Self, CompileError> {
        Self::compile_tables(bytes, limits, None, None)
    }

    /// Record real table passes. Optional growth bounds only passes after the
    /// first, without raising any absolute state or shared work/item ceiling.
    pub(crate) fn from_tree_sitter_with_diagnostics(
        bytes: &[u8],
        limits: CompileLimits,
        growth: Option<u32>,
        report: &mut CompileReport,
    ) -> Result<Self, CompileError> {
        *report = CompileReport::default();
        Self::compile_tables(bytes, limits, growth, Some(report))
    }
    fn compile_tables(
        bytes: &[u8],
        limits: CompileLimits,
        growth: Option<u32>,
        mut report: Option<&mut CompileReport>,
    ) -> Result<Self, CompileError> {
        if bytes.len() > limits.source_bytes {
            return Err(CompileError::Limit("grammar bytes"));
        }
        let UniqueValue(root) =
            serde_json::from_slice(bytes).map_err(|e| CompileError::Malformed(e.to_string()))?;
        let mut builder = Builder::read(root, limits)?;
        let lowered = builder.lower();
        if let Some(report) = report.as_deref_mut() {
            report.work = builder.work.used.get();
        }
        lowered?;
        match report {
            Some(report) => builder.finish_with_controls(growth, Some(report)),
            None => builder.finish(),
        }
    }

    pub(crate) fn name(&self) -> &str {
        &self.name
    }
    pub(crate) fn symbol(&self, id: SymbolId) -> &Symbol {
        &self.symbols[id.index()]
    }
    pub(crate) fn production(&self, id: ProductionId) -> &Production {
        &self.productions[id.index()]
    }
    pub(crate) fn reduction(&self, id: ReductionId) -> &Reduction {
        &self.reductions[id.index()]
    }
    pub(crate) fn reduction_count(&self) -> usize {
        self.reductions.len()
    }
    pub(crate) fn field_name(&self, id: FieldId) -> &str {
        &self.fields[id.index()]
    }
    pub(crate) fn field_count(&self) -> usize {
        self.fields.len()
    }
    pub(crate) fn supertypes(&self) -> &[SymbolId] {
        &self.supertypes
    }
    pub(crate) fn start_state(&self) -> StateId {
        StateId::from_index(0)
    }
    pub(crate) fn start_symbol(&self) -> SymbolId {
        self.start
    }
    pub(crate) fn symbol_count(&self) -> usize {
        self.symbols.len()
    }
    pub(crate) fn production_count(&self) -> usize {
        self.productions.len()
    }
    pub(crate) fn state_count(&self) -> usize {
        self.tables.state_count()
    }
    /// Actual final construction kernels, with quotient representatives explicit.
    pub(crate) fn state_items(&self, state: StateId) -> &[StateItem] {
        &self.kernels[state.index()]
    }
    pub(crate) fn cursor_histories(&self, item: StateItem) -> Option<&[ProductionId]> {
        self.cursor_histories.get(&item).map(Vec::as_slice)
    }
    pub(crate) fn symbol_by_name(&self, name: &str) -> Option<SymbolId> {
        self.names.get(name).copied().or_else(|| {
            self.symbols
                .iter()
                .position(|s| s.name == name)
                .map(SymbolId::from_index)
        })
    }
    pub(crate) fn actions(&self, state: StateId, at: Lookahead) -> &[Action] {
        self.tables.actions(state, at)
    }
    pub(crate) fn transition(&self, state: StateId, symbol: SymbolId) -> Option<StateId> {
        self.tables.transition(state, symbol)
    }
    pub(crate) fn state_transitions(
        &self,
        state: StateId,
    ) -> impl ExactSizeIterator<Item = (SymbolId, StateId)> + '_ {
        self.tables.state_transitions(state)
    }
    pub(crate) fn action_row(
        &self,
        state: StateId,
    ) -> impl ExactSizeIterator<Item = (Lookahead, &[Action])> + '_ {
        self.tables.action_row(state)
    }
    pub(crate) fn row_admissions(&self, state: StateId) -> &[SymbolId] {
        self.tables.row_admissions(state)
    }
    pub(crate) fn lexical_rules(&self) -> impl Iterator<Item = (SymbolId, &Lexis)> {
        self.symbols
            .iter()
            .enumerate()
            .filter_map(|(i, s)| s.lexis.as_ref().map(|l| (SymbolId::from_index(i), l)))
    }
    pub(crate) fn extras(&self) -> &[SymbolId] {
        &self.extras
    }
    /// Rule-shaped extras use the same production graph through independent
    /// entry kernels. Accept leaves the completed extra as one stack frame.
    pub(crate) fn extra_entries(&self) -> &[(SymbolId, StateId)] {
        &self.extra_entries
    }
    pub(crate) fn word(&self) -> Option<SymbolId> {
        self.word
    }
    pub(crate) fn external_ids(&self) -> &[SymbolId] {
        &self.externals
    }
    pub(crate) fn external_by_name(&self, name: &str) -> Option<SymbolId> {
        self.external_names.get(name).copied()
    }
    pub(crate) fn terminal_by_name(&self, name: &str) -> Option<SymbolId> {
        self.names
            .get(name)
            .copied()
            .filter(|id| {
                self.symbol(*id)
                    .lexis
                    .as_ref()
                    .is_some_and(|l| l.pattern != Pattern::External)
            })
            .or_else(|| {
                self.lexical_rules()
                    .find(|(id, l)| self.symbol(*id).name == name && l.pattern != Pattern::External)
                    .map(|(id, _)| id)
            })
    }
    pub(crate) fn conflicts(&self) -> &[ConflictRecord] {
        &self.conflicts
    }
    pub(crate) fn limitations(&self) -> &[CompileLimitation] {
        &self.limitations
    }
}

/// Checked views over immutable compiled metadata. IDs are local to this grammar.
impl crate::CompiledGrammar {
    pub fn symbols(&self) -> impl ExactSizeIterator<Item = (SymbolId, &Symbol)> {
        self.automaton
            .symbols
            .iter()
            .enumerate()
            .map(|(i, s)| (SymbolId::from_index(i), s))
    }
    pub fn productions(&self) -> impl ExactSizeIterator<Item = (ProductionId, &Production)> {
        self.automaton
            .productions
            .iter()
            .enumerate()
            .map(|(i, p)| (ProductionId::from_index(i), p))
    }
    pub fn fields(&self) -> impl ExactSizeIterator<Item = (FieldId, &str)> {
        self.automaton
            .fields
            .iter()
            .enumerate()
            .map(|(i, name)| (FieldId::from_index(i), name.as_str()))
    }
    pub fn state_id(&self, index: usize) -> Option<StateId> {
        (index < self.state_count()).then(|| StateId::from_index(index))
    }
    pub fn start_state(&self) -> StateId {
        self.automaton.start_state()
    }
    pub fn start_symbol(&self) -> SymbolId {
        self.automaton.start_symbol()
    }
    pub fn state_items(&self, state: StateId) -> Option<&[StateItem]> {
        (state.index() < self.state_count()).then(|| self.automaton.state_items(state))
    }
    /// Histories represented by an actual normalized construction cursor.
    /// Expanding this list is necessary when inspecting authored rule names.
    pub fn cursor_histories(&self, item: StateItem) -> Option<&[ProductionId]> {
        self.automaton.cursor_histories(item)
    }
    pub fn state_transitions(
        &self,
        state: StateId,
    ) -> Option<impl ExactSizeIterator<Item = (SymbolId, StateId)> + '_> {
        (state.index() < self.state_count()).then(|| self.automaton.state_transitions(state))
    }
    pub fn action_row(
        &self,
        state: StateId,
    ) -> Option<impl ExactSizeIterator<Item = (Lookahead, &[Action])> + '_> {
        (state.index() < self.state_count()).then(|| self.automaton.action_row(state))
    }
    pub fn lexical_rules(&self) -> impl Iterator<Item = (SymbolId, &Lexis)> {
        self.automaton.lexical_rules()
    }
}

// The wire vocabulary is explicit, not a serialized memory layout. All IDs are
// decoded as inert values and checked before any grammar-indexed lookup.
impl Automaton {
    pub(crate) fn write_artifact(
        &self,
        w: &mut crate::artifact::Writer,
    ) -> Result<(), crate::artifact::ArtifactError> {
        w.number(self.symbols.len())?;
        for s in &self.symbols {
            w.text(&s.name)?;
            w.tag(match s.shape {
                Shape::Named => 0,
                Shape::Anonymous => 1,
                Shape::Hidden => 2,
                Shape::Invented => 3,
            });
            w.flag(s.external);
            w.flag(s.lexis.is_some());
            if let Some(l) = &s.lexis {
                match &l.pattern {
                    Pattern::Literal(b) => {
                        w.tag(0);
                        w.blob(b)?;
                    }
                    Pattern::Regex(s) => {
                        w.tag(1);
                        w.text(s)?;
                    }
                    Pattern::External => w.tag(2),
                }
                w.flag(l.immediate);
                w.signed(l.precedence);
                w.number(l.declaration_order as usize)?;
            }
        }
        w.number(self.fields.len())?;
        for s in &self.fields {
            w.text(s)?;
        }
        write_symbols(w, &self.supertypes)?;
        write_names(w, &self.names)?;
        w.number(self.start.index())?;
        write_symbols(w, &self.extras)?;
        w.number(self.extra_entries.len())?;
        for &(s, q) in &self.extra_entries {
            w.number(s.index())?;
            w.number(q.index())?;
        }
        w.optional(self.word.map(SymbolId::index))?;
        write_symbols(w, &self.externals)?;
        write_names(w, &self.external_names)?;
        // Expanded steps retain shared immutable spellings in memory; keep
        // that sharing on disk instead of amplifying long aliases/rank names.
        let mut spellings = BTreeSet::new();
        for production in &self.productions {
            for step in &production.steps {
                if let Some(alias) = &step.alias {
                    spellings.insert(alias.name.as_ref());
                }
                if let Prec::Named(name) = &step.prec {
                    spellings.insert(name.as_ref());
                }
                if let Some(name) = &step.reserved {
                    spellings.insert(name.as_ref());
                }
            }
        }
        w.number(spellings.len())?;
        let mut recipe_names = BTreeMap::new();
        for (id, name) in spellings.into_iter().enumerate() {
            w.text(name)?;
            recipe_names.insert(name, id);
        }
        w.number(self.productions.len())?;
        for p in &self.productions {
            w.number(p.lhs.index())?;
            w.signed(p.dynamic_precedence);
            w.number(p.steps.len())?;
            for s in &p.steps {
                w.number(s.symbol.index())?;
                w.optional(s.field.map(FieldId::index))?;
                w.flag(s.alias.is_some());
                if let Some(a) = &s.alias {
                    write_recipe(w, &recipe_names, &a.name)?;
                    w.flag(a.named);
                }
                w.tag(match s.alias_recipe {
                    AliasRecipe::Empty => 0,
                    AliasRecipe::Local => 1,
                });
                match &s.prec {
                    Prec::None => w.tag(0),
                    Prec::Level(n) => {
                        w.tag(1);
                        w.signed(*n);
                    }
                    Prec::Named(n) => {
                        w.tag(2);
                        write_recipe(w, &recipe_names, n)?;
                    }
                }
                w.tag(match s.assoc {
                    Assoc::None => 0,
                    Assoc::Left => 1,
                    Assoc::Right => 2,
                });
                w.number(s.region)?;
                w.flag(s.spliced);
                w.flag(s.reserved.is_some());
                if let Some(n) = &s.reserved {
                    write_recipe(w, &recipe_names, n)?;
                }
            }
        }
        w.number(self.reductions.len())?;
        for f in &self.reductions {
            w.number(f.lhs.index())?;
            w.number(f.width)?;
            w.signed(f.dynamic_precedence);
            w.number(f.productions.len())?;
            for p in &f.productions {
                w.number(p.index())?;
            }
        }
        w.number(self.state_count())?;
        for state in 0..self.state_count() {
            let row = self.state_transitions(StateId::from_index(state));
            w.number(row.len())?;
            for (s, q) in row {
                w.number(s.index())?;
                w.number(q.index())?;
            }
        }
        for state in 0..self.state_count() {
            let row = self.action_row(StateId::from_index(state));
            w.number(row.len())?;
            for (at, actions) in row {
                write_lookahead(w, at)?;
                write_actions(w, actions)?;
            }
        }
        for row in &self.kernels {
            w.number(row.len())?;
            for item in row {
                w.number(item.production.index())?;
                w.number(item.dot)?;
            }
        }
        w.number(self.cursor_histories.len())?;
        for (item, histories) in &self.cursor_histories {
            w.number(item.production.index())?;
            w.number(item.dot)?;
            w.number(histories.len())?;
            for p in histories {
                w.number(p.index())?;
            }
        }
        w.number(self.conflicts.len())?;
        for c in &self.conflicts {
            w.number(c.state.index())?;
            write_lookahead(w, c.lookahead)?;
            w.tag(match c.class {
                ConflictClass::Declared => 0,
                ConflictClass::Repetition => 1,
                ConflictClass::Unwritten => 2,
                ConflictClass::Sided => 3,
                ConflictClass::Absorbed => 4,
                ConflictClass::Normalized => 5,
                ConflictClass::Residual => 6,
            });
            write_symbols(w, &c.party)?;
            write_actions(w, &c.actions)?;
        }
        w.number(self.limitations.len())?;
        for limitation in &self.limitations {
            match limitation {
                CompileLimitation::ReservedWordContexts { contexts } => {
                    w.tag(0);
                    w.number(contexts.len())?;
                    for s in contexts {
                        w.text(s)?;
                    }
                }
            }
        }
        Ok(())
    }

    pub(crate) fn read_artifact(
        name: String,
        r: &mut crate::artifact::Reader<'_>,
    ) -> Result<Self, crate::artifact::ArtifactError> {
        use crate::artifact::ArtifactError as E;
        let limits = r.limits;
        let n = r.count(limits.symbols, 7, "symbols")?;
        let mut symbols = Vec::with_capacity(n);
        for _ in 0..n {
            let name = r.text()?;
            let shape = match r.tag()? {
                0 => Shape::Named,
                1 => Shape::Anonymous,
                2 => Shape::Hidden,
                3 => Shape::Invented,
                _ => return Err(E::Invalid("symbol shape")),
            };
            let external = r.flag()?;
            let lexis = if r.flag()? {
                let pattern = match r.tag()? {
                    0 => Pattern::Literal(r.blob()?.to_vec()),
                    1 => Pattern::Regex(r.text()?),
                    2 => Pattern::External,
                    _ => return Err(E::Invalid("lexical pattern tag")),
                };
                Some(Lexis {
                    pattern,
                    immediate: r.flag()?,
                    precedence: r.signed()?,
                    declaration_order: u32::try_from(r.number()?).map_err(|_| E::Length)?,
                })
            } else {
                None
            };
            symbols.push(Symbol {
                name,
                shape,
                external,
                lexis,
            });
        }
        let n = r.count(limits.steps, 4, "fields")?;
        let mut fields = Vec::with_capacity(n);
        for _ in 0..n {
            fields.push(r.text()?);
        }
        let supertypes = read_symbols(r, limits.symbols)?;
        let names = read_names(r, limits.symbols)?;
        let start = read_symbol(r)?;
        let extras = read_symbols(r, limits.symbols)?;
        let n = r.count(limits.symbols, 8, "extra entries")?;
        let mut extra_entries = Vec::with_capacity(n);
        for _ in 0..n {
            extra_entries.push((read_symbol(r)?, read_state(r)?));
        }
        let word = r.optional()?.map(SymbolId::from_index);
        let externals = read_symbols(r, limits.symbols)?;
        let external_names = read_names(r, limits.symbols)?;
        let n = r.count(limits.steps.saturating_mul(3), 4, "recipe spellings")?;
        let mut recipe_names = Vec::<Arc<str>>::with_capacity(n);
        for _ in 0..n {
            let name: Arc<str> = r.text()?.into();
            if recipe_names
                .last()
                .is_some_and(|previous| previous >= &name)
            {
                return Err(E::Invalid("recipe spelling order"));
            }
            recipe_names.push(name);
        }
        let n = r.count(limits.productions, 12, "productions")?;
        let mut productions = Vec::with_capacity(n);
        let mut total_steps = 0;
        for _ in 0..n {
            let lhs = read_symbol(r)?;
            let dynamic_precedence = r.signed()?;
            let n = r.count(limits.steps, 15, "production steps")?;
            artifact_budget(&mut total_steps, n, limits.steps, "production steps")?;
            let mut steps = Vec::with_capacity(n);
            for _ in 0..n {
                let symbol = read_symbol(r)?;
                let field = r.optional()?.map(FieldId::from_index);
                let alias = if r.flag()? {
                    Some(Alias {
                        name: read_recipe(r, &recipe_names)?,
                        named: r.flag()?,
                    })
                } else {
                    None
                };
                let alias_recipe = match r.tag()? {
                    0 => AliasRecipe::Empty,
                    1 if alias.is_some() => AliasRecipe::Local,
                    1 => return Err(E::Invalid("local alias recipe without alias")),
                    _ => return Err(E::Invalid("alias recipe tag")),
                };
                let prec = match r.tag()? {
                    0 => Prec::None,
                    1 => Prec::Level(r.signed()?),
                    2 => Prec::Named(read_recipe(r, &recipe_names)?),
                    _ => return Err(E::Invalid("precedence tag")),
                };
                let assoc = match r.tag()? {
                    0 => Assoc::None,
                    1 => Assoc::Left,
                    2 => Assoc::Right,
                    _ => return Err(E::Invalid("associativity tag")),
                };
                let region = r.number()?;
                let spliced = r.flag()?;
                let reserved = if r.flag()? {
                    Some(read_recipe(r, &recipe_names)?)
                } else {
                    None
                };
                steps.push(Step {
                    symbol,
                    field,
                    alias,
                    alias_recipe,
                    prec,
                    assoc,
                    region,
                    spliced,
                    reserved,
                });
            }
            productions.push(Production {
                lhs,
                steps,
                dynamic_precedence,
            });
        }
        let n = r.count(limits.productions, 16, "reduction families")?;
        let mut reductions = Vec::with_capacity(n);
        let mut histories = 0;
        for _ in 0..n {
            let lhs = read_symbol(r)?;
            let width = r.number()?;
            let dynamic_precedence = r.signed()?;
            let n = r.count(limits.productions, 4, "concrete reduction histories")?;
            artifact_budget(
                &mut histories,
                n,
                limits.productions,
                "concrete reduction histories",
            )?;
            let mut members = Vec::with_capacity(n);
            for _ in 0..n {
                members.push(ProductionId::from_index(r.number()?));
            }
            reductions.push(Reduction {
                lhs,
                width,
                dynamic_precedence,
                productions: members,
            });
        }
        let mut table_entries = 0;
        let mut action_count = 0;
        let tables = FrozenTables::read(r, &mut table_entries, &mut action_count)?;
        let mut kernels = Vec::with_capacity(tables.state_count());
        let mut retained_items = 0;
        for _ in 0..tables.state_count() {
            let n = r.count(limits.items, 8, "kernel items")?;
            artifact_budget(&mut retained_items, n, limits.items, "kernel items")?;
            let mut row = Vec::with_capacity(n);
            for _ in 0..n {
                row.push(StateItem {
                    production: ProductionId::from_index(r.number()?),
                    dot: r.number()?,
                });
            }
            kernels.push(row);
        }
        let max_cursors = limits
            .steps
            .saturating_add(limits.productions)
            .min(limits.items);
        let n = r.count(max_cursors, 12, "cursor histories")?;
        let mut cursor_histories = BTreeMap::new();
        let mut history_count = 0;
        let mut prior = None;
        for _ in 0..n {
            let item = StateItem {
                production: ProductionId::from_index(r.number()?),
                dot: r.number()?,
            };
            if prior.is_some_and(|p| p >= item) {
                return Err(E::Invalid("cursor history order"));
            }
            prior = Some(item);
            let n = r.count(limits.productions, 4, "cursor history members")?;
            artifact_budget(&mut history_count, n, max_cursors, "cursor history members")?;
            let mut members = Vec::with_capacity(n);
            for _ in 0..n {
                members.push(ProductionId::from_index(r.number()?));
            }
            cursor_histories.insert(item, members);
        }
        let n = r.count(limits.table_entries, 11, "conflict diagnostics")?;
        let mut conflicts = Vec::with_capacity(n);
        for _ in 0..n {
            let state = read_state(r)?;
            let lookahead = read_lookahead(r)?;
            let class = match r.tag()? {
                0 => ConflictClass::Declared,
                1 => ConflictClass::Repetition,
                2 => ConflictClass::Unwritten,
                3 => ConflictClass::Sided,
                4 => ConflictClass::Absorbed,
                5 => ConflictClass::Normalized,
                6 => ConflictClass::Residual,
                _ => return Err(E::Invalid("conflict class")),
            };
            let party = read_symbols(r, limits.symbols)?;
            let cell = read_actions(r, &mut action_count)?;
            conflicts.push(ConflictRecord {
                state,
                lookahead,
                class,
                party,
                actions: cell,
            });
        }
        let n = r.count(limits.symbols, 5, "limitations")?;
        let mut limitations = Vec::with_capacity(n);
        for _ in 0..n {
            match r.tag()? {
                0 => {
                    let n = r.count(limits.symbols, 4, "reserved contexts")?;
                    let mut contexts = Vec::with_capacity(n);
                    for _ in 0..n {
                        contexts.push(r.text()?);
                    }
                    limitations.push(CompileLimitation::ReservedWordContexts { contexts });
                }
                _ => return Err(E::Invalid("limitation tag")),
            }
        }
        let result = Self {
            name,
            symbols,
            productions,
            reductions,
            fields,
            supertypes,
            names,
            start,
            extras,
            extra_entries,
            word,
            externals,
            external_names,
            tables,
            kernels,
            cursor_histories,
            conflicts,
            limitations,
        };
        result.validate_artifact(r)?;
        Ok(result)
    }

    fn validate_cursor_histories(
        &self,
        r: &mut crate::artifact::Reader<'_>,
    ) -> Result<(), crate::artifact::ArtifactError> {
        use crate::artifact::ArtifactError as E;
        // Intern suffix and whole-tree recipes once, avoiding a quadratic scan
        // of every long production for every cursor position in that production.
        let mut shaping = BTreeMap::<ShapingRecipe, usize>::new();
        let mut shape_ids = Vec::with_capacity(self.productions.len());
        let mut tails = BTreeMap::<(Step, usize), usize>::new();
        let mut suffixes = Vec::with_capacity(self.productions.len());
        for p in &self.productions {
            r.charge(p.steps.len().saturating_add(1))?;
            let key = (
                p.lhs,
                p.dynamic_precedence,
                p.steps
                    .iter()
                    .map(|s| (s.field, s.alias.clone(), s.alias_recipe, s.reserved.clone()))
                    .collect(),
            );
            let next = shaping.len();
            shape_ids.push(*shaping.entry(key).or_insert(next));
            let mut ids = vec![0; p.steps.len() + 1];
            for dot in (0..p.steps.len()).rev() {
                let next = tails.len() + 1;
                ids[dot] = *tails
                    .entry((p.steps[dot].clone(), ids[dot + 1]))
                    .or_insert(next);
            }
            suffixes.push(ids);
        }
        let mut membership = BTreeMap::new();
        for (&item, members) in &self.cursor_histories {
            if item.production.index() >= self.productions.len() {
                return Err(E::Invalid("cursor production ID"));
            }
            let p = self.production(item.production);
            if item.dot > p.steps.len() {
                return Err(E::Invalid("cursor dot"));
            }
            if members.first() != Some(&item.production) {
                return Err(E::Invalid("cursor representative"));
            }
            let vote = |p: &Production| {
                p.steps
                    .get(item.dot.wrapping_sub(1))
                    .map(|s| (s.prec.clone(), s.assoc, s.region, s.spliced))
            };
            let expected_vote = vote(p);
            let mut previous = None;
            for &id in members {
                r.charge(1)?;
                if id.index() >= self.productions.len() {
                    return Err(E::Invalid("cursor history production ID"));
                }
                if previous.is_some_and(|p| p >= id) {
                    return Err(E::Invalid("cursor member order"));
                }
                previous = Some(id);
                let q = self.production(id);
                if item.dot > q.steps.len()
                    || shape_ids[id.index()] != shape_ids[item.production.index()]
                    || suffixes[id.index()][item.dot] != suffixes[item.production.index()][item.dot]
                    || vote(q) != expected_vote
                {
                    return Err(E::Invalid("cursor history recipe"));
                }
                if membership.insert((id, item.dot), item).is_some() {
                    return Err(E::Invalid("duplicate concrete cursor"));
                }
            }
        }
        let expected = self
            .productions
            .iter()
            .try_fold(0usize, |n, p| n.checked_add(p.steps.len() + 1))
            .ok_or(E::Invalid("cursor count overflow"))?;
        if membership.len() != expected {
            return Err(E::Invalid("missing concrete cursor"));
        }
        for (&item, members) in &self.cursor_histories {
            if item.dot == self.production(item.production).steps.len() {
                continue;
            }
            let next = membership
                .get(&(item.production, item.dot + 1))
                .ok_or(E::Invalid("missing next cursor"))?;
            for &id in members {
                r.charge(1)?;
                if membership.get(&(id, item.dot + 1)) != Some(next) {
                    return Err(E::Invalid("cursor forward congruence"));
                }
            }
        }
        for f in &self.reductions {
            let first = f.productions[0];
            let item = membership
                .get(&(first, f.width))
                .ok_or(E::Invalid("missing completed cursor"))?;
            if self.cursor_histories.get(item) != Some(&f.productions) {
                return Err(E::Invalid("reduction cursor histories"));
            }
        }
        for row in &self.kernels {
            if row.is_empty() {
                return Err(E::Invalid("empty state kernel"));
            }
            let mut previous = None;
            for &item in row {
                r.charge(1)?;
                if previous.is_some_and(|p| p >= item) {
                    return Err(E::Invalid("kernel item order"));
                }
                previous = Some(item);
                if !self.cursor_histories.contains_key(&item) {
                    return Err(E::Invalid("kernel cursor ID"));
                }
            }
        }
        if !self.kernels[0].contains(&StateItem {
            production: ProductionId::from_index(0),
            dot: 0,
        }) {
            return Err(E::Invalid("start kernel"));
        }
        Ok(())
    }

    fn validate_artifact(
        &self,
        r: &mut crate::artifact::Reader<'_>,
    ) -> Result<(), crate::artifact::ArtifactError> {
        use crate::artifact::ArtifactError as E;
        let symbol = |s: SymbolId| {
            if s.index() < self.symbols.len() {
                Ok(())
            } else {
                Err(E::Invalid("symbol ID"))
            }
        };
        let state = |q: StateId| {
            if q.index() < self.state_count() {
                Ok(())
            } else {
                Err(E::Invalid("state ID"))
            }
        };
        if self.symbols.is_empty() || self.productions.is_empty() || self.state_count() == 0 {
            return Err(E::Invalid("empty compiled grammar"));
        }
        symbol(self.start)?;
        if let Some(word) = self.word {
            symbol(word)?;
            if self
                .symbol(word)
                .lexis
                .as_ref()
                .is_none_or(|l| l.pattern == Pattern::External)
            {
                return Err(E::Invalid("word lexical rule"));
            }
        }
        for names in [&self.names, &self.external_names] {
            for &s in names.values() {
                r.charge(1)?;
                symbol(s)?;
            }
        }
        let mut fields = BTreeSet::new();
        for field in &self.fields {
            if !fields.insert(field) {
                return Err(E::Invalid("duplicate field"));
            }
        }
        for list in [&self.extras, &self.externals, &self.supertypes] {
            let mut seen = BTreeSet::new();
            for &s in list {
                r.charge(1)?;
                symbol(s)?;
                if !seen.insert(s) {
                    return Err(E::Invalid("duplicate symbol roster"));
                }
            }
        }
        let external_set = self.externals.iter().copied().collect::<BTreeSet<_>>();
        for (i, s) in self.symbols.iter().enumerate() {
            if s.external != external_set.contains(&SymbolId::from_index(i)) {
                return Err(E::Invalid("external roster"));
            }
            if s.lexis
                .as_ref()
                .is_some_and(|l| l.pattern == Pattern::External)
                && !s.external
            {
                return Err(E::Invalid("external pattern ownership"));
            }
            if s.external && s.lexis.is_none() {
                return Err(E::Invalid("external lexical metadata"));
            }
            if let Some(Lexis {
                pattern: Pattern::Literal(bytes),
                ..
            }) = &s.lexis
            {
                std::str::from_utf8(bytes).map_err(|_| E::Invalid("literal UTF-8"))?;
            }
        }
        for &s in self.external_names.values() {
            if !external_set.contains(&s) {
                return Err(E::Invalid("external name ID"));
            }
        }
        for p in &self.productions {
            r.charge(1)?;
            symbol(p.lhs)?;
            if self.symbol(p.lhs).lexis.is_some() {
                return Err(E::Invalid("terminal production lhs"));
            }
            for s in &p.steps {
                r.charge(1)?;
                symbol(s.symbol)?;
                if s.field.is_some_and(|f| f.index() >= self.fields.len()) {
                    return Err(E::Invalid("field ID"));
                }
                if s.alias.is_none() && s.alias_recipe != AliasRecipe::Empty {
                    return Err(E::Invalid("local alias recipe without alias"));
                }
            }
        }
        let mut histories = BTreeSet::new();
        for f in &self.reductions {
            symbol(f.lhs)?;
            if f.productions.is_empty() {
                return Err(E::Invalid("empty reduction family"));
            }
            let mut previous = None;
            let mut recipe = None;
            let mut vote = None;
            for &id in &f.productions {
                r.charge(1)?;
                if id.index() >= self.productions.len() {
                    return Err(E::Invalid("production ID"));
                }
                if previous.is_some_and(|p| p >= id) || !histories.insert(id) {
                    return Err(E::Invalid("reduction history order or ownership"));
                }
                previous = Some(id);
                let p = self.production(id);
                if p.lhs != f.lhs
                    || p.steps.len() != f.width
                    || p.dynamic_precedence != f.dynamic_precedence
                {
                    return Err(E::Invalid("reduction family common metadata"));
                }
                r.charge(p.steps.len())?;
                let current = p
                    .steps
                    .iter()
                    .map(|s| (&s.field, &s.alias, s.alias_recipe, &s.reserved))
                    .collect::<Vec<_>>();
                if recipe.as_ref().is_some_and(|old| old != &current) {
                    return Err(E::Invalid("reduction family tree recipe"));
                }
                recipe = Some(current);
                let current_vote = p
                    .steps
                    .last()
                    .map(|s| (&s.prec, s.assoc, s.region, s.spliced));
                if vote.as_ref().is_some_and(|old| old != &current_vote) {
                    return Err(E::Invalid("reduction family current rank"));
                }
                vote = Some(current_vote);
            }
        }
        if histories.len() != self.productions.len() {
            return Err(E::Invalid("missing concrete reduction history"));
        }
        self.validate_cursor_histories(r)?;
        let action = |q: StateId, at: Lookahead, a: Action| -> Result<(), E> {
            match a {
                Action::Shift(to) => {
                    state(to)?;
                    let Lookahead::Terminal(s) = at else {
                        return Err(E::Invalid("end shift"));
                    };
                    if self.transition(q, s) != Some(to) {
                        return Err(E::Invalid("shift transition"));
                    }
                }
                Action::Reduce(id) => {
                    if id.index() >= self.reductions.len() {
                        return Err(E::Invalid("reduction ID"));
                    }
                }
                Action::Accept => {
                    if at != Lookahead::End {
                        return Err(E::Invalid("accept lookahead"));
                    }
                }
            }
            Ok(())
        };
        for i in 0..self.state_count() {
            let q = StateId::from_index(i);
            for (s, to) in self.state_transitions(q) {
                r.charge(1)?;
                symbol(s)?;
                state(to)?;
            }
            for (at, cell) in self.action_row(q) {
                r.charge(1)?;
                if let Lookahead::Terminal(s) = at {
                    symbol(s)?;
                    if self.symbol(s).lexis.is_none() {
                        return Err(E::Invalid("nonterminal lookahead"));
                    }
                }
                if cell.is_empty() {
                    return Err(E::Invalid("empty action cell"));
                }
                if cell.len() > 1 && cell.contains(&Action::Accept) {
                    return Err(E::Invalid("accept alternatives"));
                }
                if let [only] = cell {
                    r.charge(1)?;
                    action(q, at, *only)?;
                } else {
                    let mut seen = BTreeSet::new();
                    for &a in cell {
                        r.charge(1)?;
                        if !seen.insert(a) {
                            return Err(E::Invalid("duplicate action"));
                        }
                        action(q, at, a)?;
                    }
                }
            }
        }
        let mut extra_seen = BTreeSet::new();
        for (index, &(s, q)) in self.extra_entries.iter().enumerate() {
            symbol(s)?;
            state(q)?;
            if !self.extras.contains(&s)
                || self.symbol(s).lexis.is_some()
                || !extra_seen.insert(s)
                || q.index() != index + 1
            {
                return Err(E::Invalid("extra entry"));
            }
        }
        if self
            .extras
            .iter()
            .any(|s| self.symbol(*s).lexis.is_none() && !extra_seen.contains(s))
        {
            return Err(E::Invalid("missing rule-shaped extra entry"));
        }
        for c in &self.conflicts {
            if c.class == ConflictClass::Residual {
                return Err(E::Invalid("unresolved conflict"));
            }
            state(c.state)?;
            if let Lookahead::Terminal(s) = c.lookahead {
                symbol(s)?;
                if self.symbol(s).lexis.is_none() {
                    return Err(E::Invalid("conflict lookahead"));
                }
            }
            let mut party = BTreeSet::new();
            for &s in &c.party {
                r.charge(1)?;
                symbol(s)?;
                if !party.insert(s) {
                    return Err(E::Invalid("duplicate conflict party"));
                }
            }
            for &a in &c.actions {
                r.charge(1)?;
                action(c.state, c.lookahead, a)?;
            }
        }
        Ok(())
    }
}
fn write_recipe(
    w: &mut crate::artifact::Writer,
    names: &BTreeMap<&str, usize>,
    name: &str,
) -> Result<(), crate::artifact::ArtifactError> {
    let id = names
        .get(name)
        .ok_or(crate::artifact::ArtifactError::Invalid(
            "missing recipe spelling",
        ))?;
    w.number(*id)
}
fn read_recipe(
    r: &mut crate::artifact::Reader<'_>,
    names: &[Arc<str>],
) -> Result<Arc<str>, crate::artifact::ArtifactError> {
    names
        .get(r.number()?)
        .cloned()
        .ok_or(crate::artifact::ArtifactError::Invalid(
            "recipe spelling ID",
        ))
}
fn artifact_budget(
    total: &mut usize,
    n: usize,
    max: usize,
    resource: &'static str,
) -> Result<(), crate::artifact::ArtifactError> {
    *total = total
        .checked_add(n)
        .ok_or(crate::artifact::ArtifactError::Invalid("count overflow"))?;
    if *total > max {
        return Err(crate::artifact::ArtifactError::Limit {
            resource,
            limit: max,
        });
    }
    Ok(())
}
fn write_symbols(
    w: &mut crate::artifact::Writer,
    ids: &[SymbolId],
) -> Result<(), crate::artifact::ArtifactError> {
    w.number(ids.len())?;
    for id in ids {
        w.number(id.index())?;
    }
    Ok(())
}
fn read_symbol(
    r: &mut crate::artifact::Reader<'_>,
) -> Result<SymbolId, crate::artifact::ArtifactError> {
    Ok(SymbolId::from_index(r.number()?))
}
fn read_state(
    r: &mut crate::artifact::Reader<'_>,
) -> Result<StateId, crate::artifact::ArtifactError> {
    Ok(StateId::from_index(r.number()?))
}
fn read_symbols(
    r: &mut crate::artifact::Reader<'_>,
    max: usize,
) -> Result<Vec<SymbolId>, crate::artifact::ArtifactError> {
    let n = r.count(max, 4, "symbol roster")?;
    let mut out = Vec::with_capacity(n);
    for _ in 0..n {
        out.push(read_symbol(r)?);
    }
    Ok(out)
}
fn write_names(
    w: &mut crate::artifact::Writer,
    names: &BTreeMap<String, SymbolId>,
) -> Result<(), crate::artifact::ArtifactError> {
    w.number(names.len())?;
    for (name, id) in names {
        w.text(name)?;
        w.number(id.index())?;
    }
    Ok(())
}
fn read_names(
    r: &mut crate::artifact::Reader<'_>,
    max: usize,
) -> Result<BTreeMap<String, SymbolId>, crate::artifact::ArtifactError> {
    let n = r.count(max, 8, "name map")?;
    let mut out = BTreeMap::new();
    let mut previous = None;
    for _ in 0..n {
        let name = r.text()?;
        if previous.as_ref().is_some_and(|p: &String| p >= &name) {
            return Err(crate::artifact::ArtifactError::Invalid("name map order"));
        }
        previous = Some(name.clone());
        out.insert(name, read_symbol(r)?);
    }
    Ok(out)
}
fn write_lookahead(
    w: &mut crate::artifact::Writer,
    at: Lookahead,
) -> Result<(), crate::artifact::ArtifactError> {
    match at {
        Lookahead::Terminal(s) => {
            w.tag(0);
            w.number(s.index())?;
        }
        Lookahead::End => w.tag(1),
    }
    Ok(())
}
fn read_lookahead(
    r: &mut crate::artifact::Reader<'_>,
) -> Result<Lookahead, crate::artifact::ArtifactError> {
    match r.tag()? {
        0 => Ok(Lookahead::Terminal(read_symbol(r)?)),
        1 => Ok(Lookahead::End),
        _ => Err(crate::artifact::ArtifactError::Invalid("lookahead tag")),
    }
}
fn write_actions(
    w: &mut crate::artifact::Writer,
    cell: &[Action],
) -> Result<(), crate::artifact::ArtifactError> {
    w.number(cell.len())?;
    for a in cell {
        match a {
            Action::Shift(q) => {
                w.tag(0);
                w.number(q.index())?;
            }
            Action::Reduce(p) => {
                w.tag(1);
                w.number(p.index())?;
            }
            Action::Accept => w.tag(2),
        }
    }
    Ok(())
}
fn read_actions(
    r: &mut crate::artifact::Reader<'_>,
    total: &mut usize,
) -> Result<Vec<Action>, crate::artifact::ArtifactError> {
    let n = r.count(r.limits.actions, 1, "actions")?;
    artifact_budget(total, n, r.limits.actions, "actions")?;
    let mut out = Vec::new();
    read_actions_into_counted(r, n, &mut out)?;
    Ok(out)
}
fn read_actions_into(
    r: &mut crate::artifact::Reader<'_>,
    total: &mut usize,
    out: &mut Vec<Action>,
) -> Result<(), crate::artifact::ArtifactError> {
    let n = r.count(r.limits.actions, 1, "actions")?;
    artifact_budget(total, n, r.limits.actions, "actions")?;
    read_actions_into_counted(r, n, out)
}
fn read_actions_into_counted(
    r: &mut crate::artifact::Reader<'_>,
    n: usize,
    out: &mut Vec<Action>,
) -> Result<(), crate::artifact::ArtifactError> {
    table::reserve(out, n)?;
    for _ in 0..n {
        out.push(match r.tag()? {
            0 => Action::Shift(read_state(r)?),
            1 => Action::Reduce(ReductionId::from_index(r.number()?)),
            2 => Action::Accept,
            _ => return Err(crate::artifact::ArtifactError::Invalid("action tag")),
        });
    }
    Ok(())
}

/// A grammar is authored data: replacing a repeated map entry would discard a
/// rule or wrapper before the compiler could diagnose it. Build the ordered
/// Value directly while checking each map, retaining serde_json's depth checks.
pub(crate) struct UniqueValue(pub(crate) Value);

impl<'de> Deserialize<'de> for UniqueValue {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        struct Visitor;
        impl<'de> de::Visitor<'de> for Visitor {
            type Value = UniqueValue;

            fn expecting(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
                f.write_str("JSON grammar data without duplicate object keys")
            }

            fn visit_unit<E: de::Error>(self) -> Result<Self::Value, E> {
                Ok(UniqueValue(Value::Null))
            }

            fn visit_bool<E: de::Error>(self, v: bool) -> Result<Self::Value, E> {
                Ok(UniqueValue(Value::Bool(v)))
            }

            fn visit_i64<E: de::Error>(self, v: i64) -> Result<Self::Value, E> {
                Ok(UniqueValue(Value::Number(v.into())))
            }

            fn visit_u64<E: de::Error>(self, v: u64) -> Result<Self::Value, E> {
                Ok(UniqueValue(Value::Number(v.into())))
            }

            fn visit_f64<E: de::Error>(self, v: f64) -> Result<Self::Value, E> {
                serde_json::Number::from_f64(v)
                    .map(|n| UniqueValue(Value::Number(n)))
                    .ok_or_else(|| E::custom("non-finite JSON number"))
            }

            fn visit_str<E: de::Error>(self, v: &str) -> Result<Self::Value, E> {
                Ok(UniqueValue(Value::String(v.into())))
            }

            fn visit_string<E: de::Error>(self, v: String) -> Result<Self::Value, E> {
                Ok(UniqueValue(Value::String(v)))
            }

            fn visit_seq<A: de::SeqAccess<'de>>(self, mut seq: A) -> Result<Self::Value, A::Error> {
                let mut values = Vec::new();
                while let Some(UniqueValue(v)) = seq.next_element()? {
                    values.push(v);
                }
                Ok(UniqueValue(Value::Array(values)))
            }

            fn visit_map<A: de::MapAccess<'de>>(self, mut map: A) -> Result<Self::Value, A::Error> {
                let mut values = serde_json::Map::new();
                while let Some(key) = map.next_key::<String>()? {
                    if values.contains_key(&key) {
                        let preview: String = key.chars().take(80).collect();
                        return Err(de::Error::custom(format!(
                            "duplicate object key {preview:?}"
                        )));
                    }
                    let UniqueValue(value) = map.next_value()?;
                    values.insert(key, value);
                }
                Ok(UniqueValue(Value::Object(values)))
            }
        }
        deserializer.deserialize_any(Visitor)
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd)]
struct Atom {
    pattern: Pattern,
    immediate: bool,
    precedence: i32,
}

#[derive(Clone, Default)]
struct Recipe {
    field: Option<FieldId>,
    alias: Option<Alias>,
    prec: Prec,
    assoc: Assoc,
    region: usize,
    spliced: bool,
    reserved: Option<Arc<str>>,
}

impl Recipe {
    fn step(&self, symbol: SymbolId) -> Step {
        Step {
            symbol,
            field: self.field,
            alias: self.alias.clone(),
            alias_recipe: if self.alias.is_some() {
                AliasRecipe::Local
            } else {
                AliasRecipe::Empty
            },
            prec: self.prec.clone(),
            assoc: self.assoc,
            region: self.region,
            spliced: self.spliced,
            reserved: self.reserved.clone(),
        }
    }
}

#[derive(Clone, Debug)]
struct Alt {
    steps: Vec<Step>,
    dynamic: i32,
}
type HelperBody = Vec<(Vec<Step>, i32)>;
type HelperKey = (bool, HelperBody);

struct Rule {
    name: String,
    body: Value,
    atom: Option<Atom>,
    owned_terminal: bool,
    external: bool,
}

struct Builder {
    name: String,
    rules: Vec<Rule>,
    symbols: Vec<Symbol>,
    names: BTreeMap<String, SymbolId>,
    atoms: BTreeMap<Atom, SymbolId>,
    separator_atoms: BTreeMap<Atom, SymbolId>,
    productions: Vec<Production>,
    fields: Vec<String>,
    extra_nodes: Vec<Value>,
    extras: Vec<SymbolId>,
    supertype_names: BTreeSet<String>,
    word_name: Option<String>,
    word: Option<SymbolId>,
    start: Option<SymbolId>,
    steps: usize,
    helper: usize,
    external_nodes: Vec<Value>,
    externals: Vec<SymbolId>,
    external_names: BTreeMap<String, SymbolId>,
    limits: CompileLimits,
    inline_names: Vec<String>,
    declared_names: Vec<Vec<String>>,
    ordering_nodes: Vec<Value>,
    declared: Vec<Vec<SymbolId>>,
    orderings: Vec<Vec<RankRef>>,
    helper_bodies: BTreeMap<HelperKey, SymbolId>,
    factored: BTreeSet<SymbolId>,
    reserved_contexts: BTreeSet<String>,
    owners: BTreeMap<SymbolId, BTreeSet<SymbolId>>,
    extra_roots: Vec<(SymbolId, ProductionId)>,
    cursors: CursorTable,
    reductions: Vec<Reduction>,
    reduction_ids: Vec<ReductionId>,
    work: CompileWork,
}

impl Builder {
    fn read(root: Value, limits: CompileLimits) -> Result<Self, CompileError> {
        let obj = root
            .as_object()
            .ok_or_else(|| malformed("root must be an object"))?;
        let rules = obj
            .get("rules")
            .and_then(Value::as_object)
            .ok_or_else(|| malformed("rules must be a nonempty object"))?;
        if rules.is_empty() {
            return Err(malformed("rules must be nonempty"));
        }
        for feature in ["inline", "conflicts", "precedences"] {
            if let Some(v) = obj.get(feature) {
                let a = v
                    .as_array()
                    .ok_or_else(|| malformed(format!("{feature} must be an array")))?;
                let _ = a;
            }
        }
        let mut out = Self {
            name: obj
                .get("name")
                .map(|v| string(v, "name"))
                .transpose()?
                .unwrap_or("grammar")
                .into(),
            rules: Vec::new(),
            symbols: Vec::new(),
            names: BTreeMap::new(),
            atoms: BTreeMap::new(),
            separator_atoms: BTreeMap::new(),
            productions: Vec::new(),
            fields: Vec::new(),
            extra_nodes: Vec::new(),
            extras: Vec::new(),
            supertype_names: BTreeSet::new(),
            word_name: obj
                .get("word")
                .filter(|v| !v.is_null())
                .map(|v| string(v, "word").map(str::to_owned))
                .transpose()?,
            word: None,
            start: None,
            steps: 0,
            helper: 0,
            external_nodes: obj
                .get("externals")
                .map(|v| array(v, "externals").cloned())
                .transpose()?
                .unwrap_or_default(),
            externals: Vec::new(),
            external_names: BTreeMap::new(),
            limits,
            inline_names: obj
                .get("inline")
                .map(|v| {
                    array(v, "inline").and_then(|a| {
                        a.iter()
                            .map(|v| string(v, "inline rule").map(str::to_owned))
                            .collect()
                    })
                })
                .transpose()?
                .unwrap_or_default(),
            declared_names: obj
                .get("conflicts")
                .map(|v| {
                    array(v, "conflicts").and_then(|a| {
                        a.iter()
                            .map(|v| {
                                array(v, "conflict group").and_then(|g| {
                                    g.iter()
                                        .map(|v| string(v, "conflict rule").map(str::to_owned))
                                        .collect()
                                })
                            })
                            .collect()
                    })
                })
                .transpose()?
                .unwrap_or_default(),
            ordering_nodes: obj
                .get("precedences")
                .map(|v| array(v, "precedences").cloned())
                .transpose()?
                .unwrap_or_default(),
            declared: Vec::new(),
            orderings: Vec::new(),
            helper_bodies: BTreeMap::new(),
            factored: BTreeSet::new(),
            reserved_contexts: obj
                .get("reserved")
                .map(|v| {
                    v.as_object()
                        .ok_or_else(|| malformed("reserved must be an object"))
                        .map(|o| o.keys().cloned().collect())
                })
                .transpose()?
                .unwrap_or_default(),
            owners: BTreeMap::new(),
            extra_roots: Vec::new(),
            cursors: CursorTable::default(),
            reductions: Vec::new(),
            reduction_ids: Vec::new(),
            work: CompileWork::new(limits.work),
        };
        if let Some(v) = obj.get("supertypes") {
            for n in array(v, "supertypes")? {
                out.supertype_names.insert(string(n, "supertype")?.into());
            }
        }
        if let Some(v) = obj.get("extras") {
            out.extra_nodes = array(v, "extras")?.clone();
        }
        let claimed: BTreeSet<_> = out
            .external_nodes
            .iter()
            .filter(|v| kind(v).ok() == Some("SYMBOL"))
            .map(|v| property_string(v, "name").map(str::to_owned))
            .collect::<Result<_, _>>()?;
        let lexical_extras: BTreeSet<_> = out
            .extra_nodes
            .iter()
            .filter(|v| kind(v).ok() == Some("SYMBOL"))
            .map(|v| property_string(v, "name").map(str::to_owned))
            .collect::<Result<_, _>>()?;
        for (name, body) in rules {
            let external = claimed.contains(name);
            let lexical = if external {
                None
            } else {
                match kind(body)? {
                    "STRING" | "PATTERN" | "TOKEN" | "IMMEDIATE_TOKEN" => Some(atom(body)?),
                    _ if lexical_extras.contains(name) && !contains_symbol(body) => {
                        Some(atom(&serde_json::json!({"type":"TOKEN","content":body}))?)
                    }
                    _ => None,
                }
            };
            out.rules.push(Rule {
                name: name.clone(),
                body: body.clone(),
                atom: lexical,
                owned_terminal: false,
                external,
            });
        }
        for name in &out.supertype_names {
            if !rules.contains_key(name) {
                return Err(malformed(format!("unknown supertype {name}")));
            }
        }

        // A named token that another site spells directly becomes a structural
        // wrapper of the shared token. Its authored name must not rename that
        // other site. Equal named tokens need their own wrappers for the same reason.
        let mut inline = BTreeSet::new();
        let mut counts = BTreeMap::<Atom, usize>::new();
        let mut aliased = BTreeSet::new();
        for body in rules.values() {
            collect_alias_targets(body, false, &mut aliased, &out.work, 0)?;
        }
        for rule in &out.rules {
            if rule.external {
                continue;
            }
            if let Some(a) = &rule.atom {
                *counts.entry(a.clone()).or_default() += 1;
            } else {
                collect_atoms(&rule.body, &mut inline, 0)?;
            }
        }
        for extra in &out.extra_nodes {
            if kind(extra)? != "SYMBOL" {
                let (a, private) = extra_atom(extra)?;
                if !private {
                    inline.insert(a);
                }
            }
        }
        for ext in &out.external_nodes {
            collect_atoms(ext, &mut inline, 0)?;
        }
        for rule in &mut out.rules {
            rule.owned_terminal = rule.atom.as_ref().is_some_and(|a| {
                !inline.contains(a)
                        && counts.get(a) == Some(&1)
                        // Aliasing a hidden literal rule names its structural
                        // wrapper, retaining the anonymous literal beneath it.
                        // Collapsing that rule to its atom loses the child.
                        && !(rule.name.starts_with('_')
                            && matches!(a.pattern, Pattern::Literal(_))
                            && aliased.contains(rule.name.as_str()))
            });
        }

        // Word tokens are hoisted, followed by one authored-order atom walk.
        if let Some(word) = out.word_name.clone() {
            let r = out
                .rules
                .iter()
                .find(|r| r.name == word)
                .ok_or_else(|| malformed(format!("unknown word rule {word}")))?;
            if !r.owned_terminal {
                return Err(CompileError::Unsupported(
                    "word must name an unshared lexical rule".into(),
                ));
            }
            let a = r.atom.clone().expect("owned lexical rule");
            out.add_atom(a, Some(&word))?;
        }
        for i in 0..out.rules.len() {
            if out.rules[i].external {
                continue;
            }
            let (name, body, owned, spec) = {
                let r = &out.rules[i];
                (
                    r.name.clone(),
                    r.body.clone(),
                    r.owned_terminal,
                    r.atom.clone(),
                )
            };
            if owned {
                out.add_atom(spec.expect("lexical rule"), Some(&name))?;
            } else {
                out.number_atoms(&body, 0)?;
            }
        }
        for e in out.extra_nodes.clone() {
            if kind(&e)? != "SYMBOL" {
                let (a, private) = extra_atom(&e)?;
                if private {
                    out.add_separator(a)?;
                } else {
                    out.add_atom(a, None)?;
                }
            }
        }
        for external in out.external_nodes.clone() {
            let id = if kind(&external)? == "SYMBOL" {
                let name = property_string(&external, "name")?;
                let lx = Lexis {
                    pattern: Pattern::External,
                    immediate: false,
                    precedence: 0,
                    declaration_order: u32::try_from(out.symbols.len())
                        .map_err(|_| CompileError::Limit("symbols"))?,
                };
                let id = out.add_symbol(name.into(), out.authored_shape(name), Some(lx))?;
                out.names.insert(name.into(), id);
                id
            } else {
                out.add_atom(atom(&external)?, None)?
            };
            out.symbols[id.index()].external = true;
            out.external_names
                .insert(out.symbols[id.index()].name.clone(), id);
            if !out.externals.contains(&id) {
                out.externals.push(id);
            }
        }
        for i in 0..out.rules.len() {
            if !out.rules[i].owned_terminal && !out.rules[i].external {
                let name = out.rules[i].name.clone();
                let shape = out.authored_shape(&name);
                let id = out.add_symbol(name.clone(), shape, None)?;
                out.names.insert(name, id);
            }
        }
        out.start = Some(out.names[&out.rules[0].name]);
        out.word = out.word_name.as_ref().map(|name| out.names[name]);
        for group in &out.declared_names {
            let mut ids = group
                .iter()
                .map(|n| {
                    out.names
                        .get(n)
                        .copied()
                        .ok_or_else(|| malformed(format!("unknown conflict rule {n}")))
                })
                .collect::<Result<Vec<_>, _>>()?;
            ids.sort_unstable();
            ids.dedup();
            out.declared.push(ids);
        }
        for name in &out.inline_names {
            if !out.names.contains_key(name) {
                return Err(malformed(format!("unknown inline rule {name}")));
            }
        }
        for list in &out.ordering_nodes {
            let mut order = Vec::new();
            for entry in array(list, "precedence ordering")? {
                let rank = if let Some(s) = entry.as_str() {
                    RankRef::Name(s.into())
                } else {
                    match kind(entry)? {
                        "STRING" => RankRef::Name(property_string(entry, "value")?.into()),
                        "SYMBOL" => {
                            let name = property_string(entry, "name")?;
                            RankRef::Rule(*out.names.get(name).ok_or_else(|| {
                                malformed(format!("unknown precedence rule {name}"))
                            })?)
                        }
                        _ => return Err(malformed("invalid precedence ordering entry")),
                    }
                };
                order.push(rank);
            }
            out.orderings.push(order);
        }
        Ok(out)
    }

    fn authored_shape(&self, name: &str) -> Shape {
        if name.starts_with('_') || self.supertype_names.contains(name) {
            Shape::Hidden
        } else {
            Shape::Named
        }
    }

    fn add_symbol(
        &mut self,
        name: String,
        shape: Shape,
        lexis: Option<Lexis>,
    ) -> Result<SymbolId, CompileError> {
        if self.symbols.len() >= self.limits.symbols.min(u32::MAX as usize) {
            return Err(CompileError::Limit("symbols"));
        }
        let id = SymbolId::from_index(self.symbols.len());
        self.symbols.push(Symbol {
            name,
            shape,
            lexis,
            external: false,
        });
        Ok(id)
    }

    fn add_atom(&mut self, a: Atom, named: Option<&str>) -> Result<SymbolId, CompileError> {
        if let Some(&id) = self.atoms.get(&a) {
            if let Some(name) = named {
                self.names.insert(name.into(), id);
            }
            return Ok(id);
        }
        let (name, shape) = match named {
            Some(n) => match (&a.pattern, self.authored_shape(n)) {
                // Hiding a lexical rule does not hide its literal spelling.
                // The authored lookup still resolves this ID, while its leaf
                // is the same anonymous atom as a directly written string.
                (Pattern::Literal(bytes), Shape::Hidden) => (
                    String::from_utf8(bytes.clone()).expect("JSON string"),
                    Shape::Anonymous,
                ),
                (_, shape) => (n.into(), shape),
            },
            None => match &a.pattern {
                Pattern::Literal(bytes) => (
                    String::from_utf8(bytes.clone()).expect("JSON string"),
                    Shape::Anonymous,
                ),
                Pattern::Regex(rx) => (rx.clone(), Shape::Invented),
                Pattern::External => {
                    return Err(CompileError::Unsupported("external scanner".into()));
                }
            },
        };
        let lexis = Lexis {
            pattern: a.pattern.clone(),
            immediate: a.immediate,
            precedence: a.precedence,
            declaration_order: u32::try_from(self.symbols.len())
                .map_err(|_| CompileError::Limit("symbols"))?,
        };
        let id = self.add_symbol(name, shape, Some(lexis))?;
        if let Some(name) = named {
            self.names.insert(name.into(), id);
        }
        self.atoms.insert(a, id);
        Ok(id)
    }

    fn add_separator(&mut self, a: Atom) -> Result<SymbolId, CompileError> {
        if let Some(&id) = self.separator_atoms.get(&a) {
            return Ok(id);
        }
        // A lexical separator has no structural name. A literal spelling can
        // also occur as an ordinary token, so its invisible identity must not
        // steal that token's name, shape, or explicit parser admissions.
        let lexis = Lexis {
            pattern: a.pattern.clone(),
            immediate: a.immediate,
            precedence: a.precedence,
            declaration_order: u32::try_from(self.symbols.len())
                .map_err(|_| CompileError::Limit("symbols"))?,
        };
        let id = self.add_symbol(
            format!("$joints:separator:{}", self.separator_atoms.len()),
            Shape::Invented,
            Some(lexis),
        )?;
        self.separator_atoms.insert(a, id);
        Ok(id)
    }

    fn number_atoms(&mut self, node: &Value, depth: usize) -> Result<(), CompileError> {
        depth_check(depth)?;
        match kind(node)? {
            "STRING" | "PATTERN" | "TOKEN" | "IMMEDIATE_TOKEN" => {
                self.add_atom(atom(node)?, None)?;
            }
            "SYMBOL" | "BLANK" => {}
            "SEQ" | "CHOICE" => {
                for child in members(node)? {
                    self.number_atoms(child, depth + 1)?;
                }
            }
            "REPEAT" | "REPEAT1" | "FIELD" | "ALIAS" | "PREC" | "PREC_LEFT" | "PREC_RIGHT"
            | "PREC_DYNAMIC" | "RESERVED" => self.number_atoms(content(node)?, depth + 1)?,
            other => return Err(CompileError::Unsupported(other.into())),
        }
        Ok(())
    }

    fn lower(&mut self) -> Result<(), CompileError> {
        let augmented = self.add_symbol("$joints:start".into(), Shape::Invented, None)?;
        self.add_production(
            augmented,
            vec![Recipe::default().step(self.start.expect("start rule"))],
            0,
        )?;
        for i in 0..self.rules.len() {
            if self.rules[i].owned_terminal || self.rules[i].external {
                continue;
            }
            let name = self.rules[i].name.clone();
            let body = self.rules[i].body.clone();
            let lhs = self.names[&name];
            for alt in self.alternatives(&body, &Recipe::default(), true, lhs, 0)? {
                self.add_production(lhs, alt.steps, alt.dynamic)?;
            }
        }
        for extra in self.extra_nodes.clone() {
            let sym = if kind(&extra)? == "SYMBOL" {
                let name = property_string(&extra, "name")?;
                *self
                    .names
                    .get(name)
                    .ok_or_else(|| malformed(format!("unknown extra {name}")))?
            } else {
                let (a, private) = extra_atom(&extra)?;
                let atoms = if private {
                    &self.separator_atoms
                } else {
                    &self.atoms
                };
                *atoms
                    .get(&a)
                    .ok_or_else(|| malformed("extra has no terminal"))?
            };
            self.extras.push(sym);
        }
        self.extras.sort_unstable();
        self.extras.dedup();
        self.mark_alias_recipes()?;
        self.inline()?;
        self.deduplicate();
        // Append after rewriting so these immutable production IDs remain
        // distinct from authored rules and can be accepted without a node.
        let (_, nullable) = first_sets(&self.symbols, &self.productions, &self.work)?;
        for sym in self.extras.clone() {
            if self.symbols[sym.index()].lexis.is_some() {
                continue;
            }
            if nullable[sym.index()] {
                return Err(CompileError::Unsupported(format!(
                    "nullable extra {}",
                    self.symbols[sym.index()].name
                )));
            }
            let root = self.add_symbol(
                format!("$joints:extra:{}", self.symbols[sym.index()].name),
                Shape::Invented,
                None,
            )?;
            let id = ProductionId::from_index(self.productions.len());
            self.add_production(root, vec![Recipe::default().step(sym)], 0)?;
            self.extra_roots.push((sym, id));
        }
        self.cursors = CursorTable::build(&self.productions, &self.work)?;
        let mut families = BTreeMap::new();
        for (i, p) in self.productions.iter().enumerate() {
            let production = ProductionId::from_index(i);
            let cursor = self.cursors.at(production, p.steps.len());
            let family = *families.entry(cursor).or_insert_with(|| {
                let id = ReductionId::from_index(self.reductions.len());
                self.reductions.push(Reduction {
                    lhs: p.lhs,
                    width: p.steps.len(),
                    dynamic_precedence: p.dynamic_precedence,
                    productions: self.cursors.variants(cursor).to_vec(),
                });
                id
            });
            self.reduction_ids.push(family);
        }
        Ok(())
    }

    fn entry_productions(&self) -> Vec<ProductionId> {
        std::iter::once(ProductionId::from_index(0))
            .chain(self.extra_roots.iter().map(|(_, p)| *p))
            .collect()
    }

    fn is_entry(&self, id: ProductionId) -> bool {
        id.index() == 0 || self.extra_roots.iter().any(|(_, p)| *p == id)
    }

    fn add_production(
        &mut self,
        lhs: SymbolId,
        steps: Vec<Step>,
        dynamic: i32,
    ) -> Result<(), CompileError> {
        if self.productions.len() >= self.limits.productions.min(u32::MAX as usize) {
            return Err(CompileError::Limit("productions"));
        }
        self.steps = self
            .steps
            .checked_add(steps.len())
            .ok_or(CompileError::Limit("production steps"))?;
        if self.steps > self.limits.production_steps {
            return Err(CompileError::Limit("production steps"));
        }
        self.productions.push(Production {
            lhs,
            steps,
            dynamic_precedence: dynamic,
        });
        Ok(())
    }

    fn alternatives(
        &mut self,
        node: &Value,
        recipe: &Recipe,
        at_end: bool,
        owner: SymbolId,
        depth: usize,
    ) -> Result<Vec<Alt>, CompileError> {
        depth_check(depth)?;
        let single = |steps| vec![Alt { steps, dynamic: 0 }];
        let result = match kind(node)? {
            "BLANK" => single(vec![]),
            "SYMBOL" => {
                let name = property_string(node, "name")?;
                let sym = *self
                    .names
                    .get(name)
                    .ok_or_else(|| malformed(format!("unknown symbol {name}")))?;
                single(vec![recipe.step(sym)])
            }
            "STRING" | "PATTERN" | "TOKEN" | "IMMEDIATE_TOKEN" => {
                let spec = atom(node)?;
                let sym = *self
                    .atoms
                    .get(&spec)
                    .ok_or_else(|| malformed("unregistered terminal"))?;
                single(vec![recipe.step(sym)])
            }
            "FIELD" => {
                let name = property_string(node, "name")?;
                let index = if let Some(i) = self.fields.iter().position(|f| f == name) {
                    i
                } else {
                    self.fields.push(name.into());
                    self.fields.len() - 1
                };
                let mut next = recipe.clone();
                next.field = Some(FieldId::from_index(index));
                self.alternatives(content(node)?, &next, at_end, owner, depth + 1)?
            }
            "ALIAS" => {
                let mut next = recipe.clone();
                next.alias = Some(Alias {
                    name: property_string(node, "value")?.into(),
                    named: node
                        .get("named")
                        .and_then(Value::as_bool)
                        .ok_or_else(|| malformed("alias named must be boolean"))?,
                });
                self.alternatives(content(node)?, &next, at_end, owner, depth + 1)?
            }
            "RESERVED" => {
                let mut next = recipe.clone();
                next.reserved = Some(property_string(node, "context_name")?.into());
                self.reserved_contexts
                    .insert(property_string(node, "context_name")?.into());
                self.alternatives(content(node)?, &next, at_end, owner, depth + 1)?
            }
            "PREC_DYNAMIC" => {
                let n = integer(node.get("value"), "dynamic precedence")?;
                let mut inside =
                    self.alternatives(content(node)?, recipe, at_end, owner, depth + 1)?;
                for alt in &mut inside {
                    alt.dynamic = louder(n, alt.dynamic);
                }
                inside
            }
            prec @ ("PREC" | "PREC_LEFT" | "PREC_RIGHT") => {
                let mut next = recipe.clone();
                next.prec = precedence(node.get("value"))?;
                if prec == "PREC_LEFT" {
                    next.assoc = Assoc::Left;
                }
                if prec == "PREC_RIGHT" {
                    next.assoc = Assoc::Right;
                }
                let mut inside =
                    self.alternatives(content(node)?, &next, at_end, owner, depth + 1)?;
                let widest = inside.iter().map(|a| a.steps.len()).max().unwrap_or(0);
                for alt in &mut inside {
                    for step in &mut alt.steps {
                        if step.region == 0
                            && (step.prec != Prec::None || step.assoc != Assoc::None)
                        {
                            step.region = widest;
                        }
                    }
                    if !at_end {
                        if let Some(last) = alt.steps.last_mut() {
                            last.prec = recipe.prec.clone();
                            last.assoc = recipe.assoc;
                            last.region = 0;
                        }
                    }
                }
                inside
            }
            "CHOICE" => self.choice_alternatives(node, recipe, at_end, owner, depth)?,
            "SEQ" => self.sequence_alternatives(node, recipe, at_end, owner, depth)?,
            repeat @ ("REPEAT" | "REPEAT1") => {
                self.repeat_alternatives(repeat, node, recipe, owner, depth)?
            }
            other => return Err(CompileError::Unsupported(other.into())),
        };
        if result.len() > self.limits.alternatives {
            return Err(CompileError::Limit("alternatives"));
        }
        Ok(result)
    }

    fn choice_alternatives(
        &mut self,
        node: &Value,
        recipe: &Recipe,
        at_end: bool,
        owner: SymbolId,
        depth: usize,
    ) -> Result<Vec<Alt>, CompileError> {
        let mut out = Vec::new();
        let mut width = 0usize;
        for child in members(node)? {
            let right = self.alternatives(child, recipe, at_end, owner, depth + 1)?;
            if out.len() + right.len() > self.limits.alternatives {
                return Err(CompileError::Limit("alternatives"));
            }
            width = right
                .iter()
                .try_fold(width, |n, a| n.checked_add(a.steps.len()))
                .ok_or(CompileError::Limit("expanded steps"))?;
            if width > self.limits.production_steps {
                return Err(CompileError::Limit("expanded steps"));
            }
            out.extend(right);
        }
        Ok(out)
    }

    fn sequence_alternatives(
        &mut self,
        node: &Value,
        recipe: &Recipe,
        at_end: bool,
        owner: SymbolId,
        depth: usize,
    ) -> Result<Vec<Alt>, CompileError> {
        let single = |steps| vec![Alt { steps, dynamic: 0 }];
        let mut out = single(vec![]);
        for (i, child) in members(node)?.iter().enumerate() {
            let last = at_end && i + 1 == members(node)?.len();
            let mut right = self.alternatives(child, recipe, last, owner, depth + 1)?;
            if out.len().saturating_mul(right.len()) > 64 {
                let shaping = Recipe {
                    field: recipe.field,
                    alias: recipe.alias.clone(),
                    reserved: recipe.reserved.clone(),
                    ..Recipe::default()
                };
                let body = self.alternatives(child, &shaping, true, owner, depth + 1)?;
                let empty = body.iter().any(|a| a.steps.is_empty());
                let filled: Vec<_> = body.into_iter().filter(|a| !a.steps.is_empty()).collect();
                right = if filled.is_empty() {
                    single(vec![])
                } else {
                    let helper = self.helper(&filled, owner, false)?;
                    let site = Recipe {
                        prec: recipe.prec.clone(),
                        assoc: recipe.assoc,
                        ..Recipe::default()
                    };
                    let mut result = single(vec![site.step(helper)]);
                    if empty {
                        result.push(Alt {
                            steps: vec![],
                            dynamic: 0,
                        });
                    }
                    result
                };
            }
            out = self.product(&out, &right)?;
        }
        Ok(out)
    }

    fn repeat_alternatives(
        &mut self,
        repeat: &str,
        node: &Value,
        recipe: &Recipe,
        owner: SymbolId,
        depth: usize,
    ) -> Result<Vec<Alt>, CompileError> {
        let single = |steps| vec![Alt { steps, dynamic: 0 }];
        Ok({
            let body =
                self.alternatives(content(node)?, &Recipe::default(), true, owner, depth + 1)?;
            let empty = body.iter().any(|a| a.steps.is_empty());
            let filled: Vec<_> = body.into_iter().filter(|a| !a.steps.is_empty()).collect();
            if filled.is_empty() {
                if repeat == "REPEAT" || empty {
                    single(vec![])
                } else {
                    Vec::new()
                }
            } else {
                let helper = self.helper(&filled, owner, true)?;
                let mut out = single(vec![recipe.step(helper)]);
                if repeat == "REPEAT" || empty {
                    out.push(Alt {
                        steps: vec![],
                        dynamic: 0,
                    });
                }
                out
            }
        })
    }

    fn product(&self, left: &[Alt], right: &[Alt]) -> Result<Vec<Alt>, CompileError> {
        if left.len().saturating_mul(right.len()) > self.limits.alternatives {
            return Err(CompileError::Limit("alternatives"));
        }
        let left_steps: usize = left.iter().map(|a| a.steps.len()).sum();
        let right_steps: usize = right.iter().map(|a| a.steps.len()).sum();
        let width = left_steps
            .checked_mul(right.len())
            .and_then(|n| {
                right_steps
                    .checked_mul(left.len())
                    .and_then(|r| n.checked_add(r))
            })
            .ok_or(CompileError::Limit("expanded steps"))?;
        if width > self.limits.production_steps {
            return Err(CompileError::Limit("expanded steps"));
        }
        let mut out = Vec::new();
        for a in left {
            for b in right {
                let mut steps = a.steps.clone();
                steps.extend_from_slice(&b.steps);
                out.push(Alt {
                    steps,
                    dynamic: louder(a.dynamic, b.dynamic),
                });
            }
        }
        Ok(out)
    }

    fn helper(
        &mut self,
        body: &[Alt],
        owner: SymbolId,
        repeat: bool,
    ) -> Result<SymbolId, CompileError> {
        let key = (
            repeat,
            body.iter()
                .map(|a| {
                    let mut steps = a.steps.clone();
                    for s in &mut steps {
                        s.region = 0;
                    }
                    (steps, a.dynamic)
                })
                .collect::<Vec<_>>(),
        );
        if let Some(&id) = self.helper_bodies.get(&key) {
            self.owners.entry(id).or_default().insert(owner);
            // Region provenance is conservative and not production identity.
            for p in self.productions.iter_mut().filter(|p| p.lhs == id) {
                for a in body {
                    let offset = usize::from(p.steps.len() == a.steps.len() + 1);
                    if p.steps.len() != a.steps.len() + offset {
                        continue;
                    }
                    if p.steps[offset..]
                        .iter()
                        .map(step_key)
                        .eq(a.steps.iter().map(step_key))
                    {
                        for (to, from) in p.steps[offset..].iter_mut().zip(&a.steps) {
                            to.region = to.region.max(from.region);
                        }
                    }
                }
            }
            return Ok(id);
        }
        let name = format!(
            "$joints:{}{}",
            if repeat { "repeat" } else { "choice" },
            self.helper
        );
        self.helper += 1;
        let id = self.add_symbol(name, Shape::Invented, None)?;
        if !repeat {
            self.factored.insert(id);
        }
        self.owners.entry(id).or_default().insert(owner);
        for a in body {
            self.add_production(id, a.steps.clone(), a.dynamic)?;
            if repeat {
                let mut recipe = Recipe::default();
                if let Some(first) = a.steps.first() {
                    recipe.prec = first.prec.clone();
                    recipe.assoc = first.assoc;
                    recipe.region = first.region;
                }
                let mut steps = vec![recipe.step(id)];
                steps.extend_from_slice(&a.steps);
                self.add_production(id, steps, a.dynamic)?;
            }
        }
        self.helper_bodies.insert(key, id);
        Ok(id)
    }

    fn mark_alias_recipes(&mut self) -> Result<(), CompileError> {
        const LABEL: &str = "alias recipe work";
        let count = self.symbols.len();
        self.work.charge(count.saturating_mul(5), LABEL)?;
        let mut inline = vec![false; count];
        for name in &self.inline_names {
            // Bound both duplicate authored entries and string-key lookup
            // comparisons before inspecting the name or allocating metadata.
            self.work.charge(
                name.len()
                    .saturating_add(1)
                    .saturating_mul(self.names.len().max(1)),
                LABEL,
            )?;
            inline[self.names[name].index()] = true;
        }
        let mut bare = vec![false; count];
        let mut counts: Vec<Vec<(&Alias, usize)>> = vec![vec![]; count];
        let mut defaults = vec![None; count];
        let mut siblings = vec![vec![]; count];
        let equal = |a: &Alias, b: &Alias| -> Result<bool, CompileError> {
            self.work.charge(
                a.name.len().saturating_add(b.name.len()).saturating_add(1),
                LABEL,
            )?;
            Ok(a == b)
        };
        for &extra in &self.extras {
            self.work.charge(1, LABEL)?;
            bare[extra.index()] = true;
        }
        for (i, p) in self.productions.iter().enumerate() {
            self.work.charge(2, LABEL)?;
            siblings[p.lhs.index()].push(i);
            for step in &p.steps {
                self.work.charge(1, LABEL)?;
                // Explicit inline symbols never acquire a default alias.
                if inline[step.symbol.index()] {
                    continue;
                }
                if let Some(alias) = &step.alias {
                    let mut found = false;
                    for (other, n) in &mut counts[step.symbol.index()] {
                        if equal(alias, other)? {
                            *n = n.checked_add(1).ok_or(CompileError::Limit(LABEL))?;
                            found = true;
                            break;
                        }
                    }
                    if !found {
                        self.work.charge(1, LABEL)?;
                        counts[step.symbol.index()].push((alias, 1));
                    }
                } else {
                    bare[step.symbol.index()] = true;
                }
            }
        }
        for (i, aliases) in counts.iter().enumerate() {
            self.work.charge(1, LABEL)?;
            if bare[i] {
                continue;
            }
            let mut highest = 0;
            for &(alias, n) in aliases {
                self.work.charge(1, LABEL)?;
                if n > highest {
                    highest = n;
                    defaults[i] = Some(alias);
                }
            }
        }
        self.work.charge(self.productions.len(), LABEL)?;
        let mut recipes = Vec::with_capacity(self.productions.len());
        for p in &self.productions {
            self.work.charge(p.steps.len().saturating_add(1), LABEL)?;
            let mut flags = Vec::with_capacity(p.steps.len());
            for (j, step) in p.steps.iter().enumerate() {
                let mut local = step.alias.is_some();
                if let (Some(alias), Some(default)) = (&step.alias, defaults[step.symbol.index()]) {
                    if equal(alias, default)? {
                        local = false;
                        for &other in &siblings[p.lhs.index()] {
                            self.work.charge(1, LABEL)?;
                            let Some(peer) = self.productions[other].steps.get(j) else {
                                continue;
                            };
                            if let Some(peer_alias) = &peer.alias {
                                if equal(alias, peer_alias)? {
                                    match defaults[peer.symbol.index()] {
                                        Some(peer_default) if equal(alias, peer_default)? => {}
                                        _ => {
                                            local = true;
                                            break;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                flags.push(if local {
                    AliasRecipe::Local
                } else {
                    AliasRecipe::Empty
                });
            }
            recipes.push(flags);
        }
        // Publish only after the complete pre-inline analysis succeeds. Raw
        // aliases stay present for native tree shaping; this marker records
        // whether the alias survives in the local reduction recipe.
        for (p, flags) in self.productions.iter_mut().zip(recipes) {
            self.work.charge(p.steps.len().saturating_add(1), LABEL)?;
            for (step, marker) in p.steps.iter_mut().zip(flags) {
                step.alias_recipe = marker;
            }
        }
        Ok(())
    }

    fn inline(&mut self) -> Result<(), CompileError> {
        let mut victims: BTreeSet<_> = self.inline_names.iter().map(|n| self.names[n]).collect();
        let by = by_lhs(&self.symbols, &self.productions);
        for (s, rules) in by.iter().enumerate() {
            if rules.len() != 1 || !matches!(self.symbols[s].shape, Shape::Hidden | Shape::Invented)
            {
                continue;
            }
            let p = &self.productions[rules[0].index()];
            if p.steps.len() == 1 && p.dynamic_precedence == 0 {
                let step = &p.steps[0];
                if self.symbols[step.symbol.index()].shape == Shape::Invented
                    && step.prec == Prec::None
                    && step.assoc == Assoc::None
                    && step.field.is_none()
                    && step.alias.is_none()
                    && step.reserved.is_none()
                {
                    victims.insert(SymbolId::from_index(s));
                }
            }
        }
        for round in 0..=victims.len() {
            let by = by_lhs(&self.symbols, &self.productions);
            let mut rewritten = Vec::new();
            let mut changed = false;
            let mut total = 0usize;
            for p in &self.productions {
                let mut out = vec![Alt {
                    steps: Vec::new(),
                    dynamic: p.dynamic_precedence,
                }];
                for host in &p.steps {
                    if victims.contains(&host.symbol) && !by[host.symbol.index()].is_empty() {
                        if round == victims.len() {
                            return Err(CompileError::Unsupported("cyclic inline rules".into()));
                        }
                        changed = true;
                        let mut arms = Vec::new();
                        for &rule in &by[host.symbol.index()] {
                            let mut steps = self.productions[rule.index()].steps.clone();
                            for step in &mut steps {
                                if host.alias.is_some() {
                                    step.alias = host.alias.clone();
                                    if host.alias_recipe == AliasRecipe::Local {
                                        step.alias_recipe = AliasRecipe::Local;
                                    }
                                }
                                if host.field.is_some() {
                                    step.field = host.field;
                                }
                                if (step.prec != Prec::None || step.assoc != Assoc::None)
                                    && step.region != 1
                                {
                                    step.spliced = true;
                                }
                            }
                            if let Some(last) = steps.last_mut() {
                                if last.prec == Prec::None || last.assoc == Assoc::None {
                                    last.spliced |= host.spliced;
                                }
                                if last.prec == Prec::None {
                                    last.prec = host.prec.clone();
                                    last.region = host.region;
                                }
                                if last.assoc == Assoc::None {
                                    last.assoc = host.assoc;
                                }
                            }
                            // The host production owns the reading after an inline rewrite.
                            arms.push(Alt {
                                steps,
                                dynamic: self.productions[rule.index()].dynamic_precedence,
                            });
                        }
                        out = self.product(&out, &arms)?;
                    } else {
                        out = self.product(
                            &out,
                            &[Alt {
                                steps: vec![host.clone()],
                                dynamic: 0,
                            }],
                        )?;
                    }
                }
                for a in out {
                    total = total
                        .checked_add(a.steps.len())
                        .ok_or(CompileError::Limit("production steps"))?;
                    if total > self.limits.production_steps
                        || rewritten.len() >= self.limits.productions
                    {
                        return Err(CompileError::Limit("inline expansion"));
                    }
                    rewritten.push(Production {
                        lhs: p.lhs,
                        steps: a.steps,
                        dynamic_precedence: a.dynamic,
                    });
                }
            }
            self.productions = rewritten;
            self.deduplicate();
            if !changed {
                break;
            }
        }
        let by = by_lhs(&self.symbols, &self.productions);
        let mut live = BTreeSet::new();
        let mut todo = vec![self.productions[0].lhs];
        todo.extend(self.extras.iter().copied());
        while let Some(sym) = todo.pop() {
            if !live.insert(sym) {
                continue;
            }
            for &id in &by[sym.index()] {
                todo.extend(self.productions[id.index()].steps.iter().map(|s| s.symbol));
            }
        }
        self.productions.retain(|p| live.contains(&p.lhs));
        Ok(())
    }

    fn deduplicate(&mut self) {
        let mut known = BTreeMap::new();
        let mut out: Vec<Production> = Vec::new();
        for p in self.productions.drain(..) {
            let key = (
                p.lhs,
                p.steps.iter().map(step_key).collect::<Vec<_>>(),
                p.dynamic_precedence,
            );
            if let Some(&i) = known.get(&key) {
                let prior: &mut Production = &mut out[i];
                for (to, from) in prior.steps.iter_mut().zip(p.steps) {
                    to.region = to.region.max(from.region);
                }
            } else {
                known.insert(key, out.len());
                out.push(p);
            }
        }
        self.productions = out;
    }

    fn construct_tables(
        &mut self,
        growth: Option<u32>,
        mut report: Option<&mut CompileReport>,
    ) -> Result<FinishedTables, CompileError> {
        let mut plan = SplitPlan::new();
        let mut round = 0usize;
        let absolute_states = self.limits.states;
        let mut baseline = false;
        #[cfg(not(test))]
        let mut canonical = false;
        #[cfg(test)]
        let mut canonical = std::env::var_os("JNT_CANONICAL").is_some();
        let mut partitions = BTreeSet::new();
        let mut history_items = 0usize;
        let (transitions, actions, admissions, conflicts, states) = loop {
            let observation = if let Some(report) = report.as_deref_mut() {
                if report.rounds.len() < MAX_COMPILE_ROUNDS {
                    self.work.charge(1, "compile diagnostic work")?;
                    let index = report.rounds.len();
                    report.rounds.push(CompileRound {
                        pass: round,
                        stage: if canonical {
                            CompileStage::Canonical
                        } else if round == 0 {
                            CompileStage::Lalr
                        } else {
                            CompileStage::RefinedLalr
                        },
                        state_limit: self.limits.states,
                        states: None,
                        items: None,
                        work_before: self.work.used.get(),
                        work_after: self.work.used.get(),
                        contested: 0,
                        residual: 0,
                        priority_sensitive: false,
                        completed: false,
                    });
                    Some(index)
                } else {
                    report.truncated = true;
                    None
                }
            } else {
                None
            };
            round += 1;
            if !canonical {
                let size = plan
                    .iter()
                    .try_fold(1usize, |n, (target, sources)| {
                        sources
                            .keys()
                            .try_fold(n.checked_add(target.len())?, |n, source| {
                                n.checked_add(source.0.len().checked_add(1)?)
                            })
                    })
                    .ok_or(CompileError::Limit("partition history items"))?;
                self.work.charge(size, "context partition work")?;
                history_items = history_items
                    .checked_add(size)
                    .ok_or(CompileError::Limit("partition history items"))?;
                if history_items > self.limits.items {
                    return Err(CompileError::Limit("partition history items"));
                }
                if !partitions.insert(plan.clone()) {
                    return Err(CompileError::Unsupported(
                        "repeated LR context partition".into(),
                    ));
                }
            }
            let (states, graph, marks, tables) = if canonical {
                let c = lr1(self)?;
                let tables = tabulate(self, &c.states, &c.graph, &c.looks, &c.first)?;
                (c.states, c.graph, Vec::new(), tables)
            } else {
                let (states, graph, marks) = lr0(self, &plan)?;
                let tables = lalr(self, &states, &graph)?;
                (states, graph, marks, tables)
            };
            if let Some(index) = observation {
                report.as_deref_mut().expect("observed report").rounds[index].states =
                    Some(states.len());
                // Vec lengths give the full item population without revisiting
                // every item; charge those row and conflict-record visits first.
                self.work.charge(
                    states.len().saturating_add(tables.conflicts.len()),
                    "compile diagnostic work",
                )?;
                let items = states
                    .iter()
                    .try_fold(0usize, |n, row| n.checked_add(row.len()))
                    .ok_or(CompileError::Limit("diagnostic items"))?;
                let event = &mut report.as_deref_mut().expect("observed report").rounds[index];
                event.states = Some(states.len());
                event.items = Some(items);
                event.work_after = self.work.used.get();
                event.contested = tables.conflicts.len();
                event.residual = tables
                    .conflicts
                    .iter()
                    .filter(|c| c.class == ConflictClass::Residual)
                    .count();
                event.priority_sensitive = tables.priority_sensitive;
                event.completed = true;
            }
            if !baseline {
                baseline = true;
                if let Some(growth) = growth {
                    // Overflow means the product exceeds every finite absolute
                    // ceiling; clamp it rather than wrap to a smaller policy.
                    let limit = states
                        .len()
                        .checked_mul(growth as usize)
                        .map_or(absolute_states, |n| n.max(4096).min(absolute_states));
                    self.limits.states = limit;
                    if let Some(report) = report.as_deref_mut() {
                        report.growth_state_limit = Some(limit);
                    }
                }
            }
            let residual = tables
                .conflicts
                .iter()
                .find(|c| c.class == ConflictClass::Residual);
            // A merge is harmless only while it leaves the static decision
            // unchanged. Exact contexts are required when withholding a
            // comparison or preferring a continuation changes that decision.
            if !canonical && tables.priority_sensitive {
                canonical = true;
                continue;
            }
            // Exact closure can diagnose authored RR before constructing its
            // unrelated successors. Going there directly avoids spending the
            // shared budget repeatedly partitioning a genuinely invalid RR.
            // Classification still belongs entirely to the exact collection.
            let pure_rr =
                residual.is_some_and(|c| c.actions.iter().all(|a| matches!(a, Action::Reduce(_))));
            if !canonical
                && residual.is_some()
                && !pure_rr
                && split_candidates(
                    self,
                    &states,
                    &marks,
                    &tables.candidates,
                    &tables.draws,
                    &mut plan,
                )?
            {
                continue;
            }
            if residual.is_some() && !canonical {
                #[cfg(test)]
                if std::env::var_os("JNT_CENSUS_DETAIL").is_some() {
                    eprintln!(
                        "{} precise fallback after {round} rounds, {} states: {:?}",
                        self.name,
                        states.len(),
                        residual
                    );
                }
                canonical = true;
                continue;
            }
            if let Some(c) = residual {
                #[cfg(test)]
                if std::env::var_os("JNT_CENSUS_DETAIL").is_some() {
                    eprintln!(
                        "{} residual after {round} partition rounds, {} states: {:?}",
                        self.name,
                        states.len(),
                        c
                    );
                    for item in &states[c.state.index()] {
                        let p = &self.productions[item.production.index()];
                        if c.party.contains(&p.lhs)
                            || c.actions.contains(&Action::Reduce(
                                self.reduction_ids[item.production.index()],
                            ))
                        {
                            eprintln!(
                                "  {}({}) dot{} / {} dynamic{} [{}]",
                                self.symbols[p.lhs.index()].name,
                                item.production.index(),
                                item.dot,
                                p.steps.len(),
                                p.dynamic_precedence,
                                p.steps
                                    .iter()
                                    .map(|s| format!(
                                        "{}:{:?}/{:?}@{}{}",
                                        self.symbols[s.symbol.index()].name,
                                        s.prec,
                                        s.assoc,
                                        s.region,
                                        if s.spliced { "~" } else { "" }
                                    ))
                                    .collect::<Vec<_>>()
                                    .join(" ")
                            );
                        }
                    }
                }
                let label = match c.lookahead {
                    Lookahead::Terminal(id) => self.symbols[id.index()].name.clone(),
                    Lookahead::End => "EOF".into(),
                };
                return Err(CompileError::Conflict {
                    state: c.state.index(),
                    lookahead: format!(
                        "{label} (party: {})",
                        c.party
                            .iter()
                            .map(|id| self.symbols[id.index()].name.as_str())
                            .collect::<Vec<_>>()
                            .join(", ")
                    ),
                    actions: c.actions.clone(),
                });
            }
            break (
                graph,
                tables.actions,
                tables.admissions,
                tables.conflicts,
                states,
            );
        };
        Ok(FinishedTables {
            transitions,
            actions,
            admissions,
            conflicts,
            states,
        })
    }
    fn finish(self) -> Result<Automaton, CompileError> {
        self.finish_with_controls(None, None)
    }
    fn finish_with_controls(
        mut self,
        growth: Option<u32>,
        mut report: Option<&mut CompileReport>,
    ) -> Result<Automaton, CompileError> {
        let constructed = self.construct_tables(growth, report.as_deref_mut());
        if let Some(report) = report.as_deref_mut() {
            report.work = self.work.used.get();
            if let Some(last) = report.rounds.last_mut().filter(|event| !event.completed) {
                last.work_after = report.work;
            }
        }
        let FinishedTables {
            transitions,
            actions,
            admissions,
            conflicts,
            mut states,
        } = constructed?;
        let retained_work = states
            .iter()
            .try_fold(0usize, |n, row| n.checked_add(row.len()))
            .ok_or(CompileError::Limit("diagnostic kernel items"))?;
        if retained_work > self.limits.items {
            return Err(CompileError::Limit("diagnostic kernel items"));
        }
        let retained = self.work.charge(retained_work, "diagnostic kernel work");
        if let Some(report) = report.as_deref_mut() {
            report.work = self.work.used.get();
        }
        retained?;
        for row in &mut states {
            row.retain(|item| item.dot > 0 || self.is_entry(item.production));
            row.shrink_to_fit();
        }
        #[cfg(test)]
        if std::env::var_os("JNT_CENSUS_DETAIL").is_some() {
            eprintln!("{} total compile work {}", self.name, self.work.used.get());
        }
        let publication = table::publication_work(&transitions, &actions)
            .and_then(|amount| self.work.charge(amount, "frozen table publication work"));
        if let Some(report) = report.as_deref_mut() {
            report.work = self.work.used.get();
        }
        publication?;
        let tables = FrozenTables::from_maps(transitions, actions, admissions)?;
        let supertypes = self
            .supertype_names
            .iter()
            .map(|name| self.names[name])
            .collect();
        if let Some(report) = report {
            report.tables_complete = true;
            report.work = self.work.used.get();
        }
        Ok(Automaton {
            name: self.name,
            symbols: self.symbols,
            productions: self.productions,
            reductions: self.reductions,
            fields: self.fields,
            supertypes,
            names: self.names,
            start: self.start.expect("start"),
            extra_entries: self
                .extra_roots
                .iter()
                .enumerate()
                .map(|(i, (symbol, _))| (*symbol, StateId::from_index(i + 1)))
                .collect(),
            extras: self.extras,
            word: self.word,
            externals: self.externals,
            external_names: self.external_names,
            tables,
            kernels: states,
            cursor_histories: self.cursors.classes,
            conflicts,
            limitations: if self.reserved_contexts.is_empty() {
                Vec::new()
            } else {
                vec![CompileLimitation::ReservedWordContexts {
                    contexts: self.reserved_contexts.into_iter().collect(),
                }]
            },
        })
    }
}

fn malformed(message: impl Into<String>) -> CompileError {
    CompileError::Malformed(message.into())
}
fn step_key(s: &Step) -> Step {
    let mut out = s.clone();
    out.region = 0;
    out
}
fn louder(first: i32, later: i32) -> i32 {
    if later.unsigned_abs() > first.unsigned_abs() {
        later
    } else {
        first
    }
}
fn integer(value: Option<&Value>, at: &str) -> Result<i32, CompileError> {
    value
        .and_then(Value::as_i64)
        .and_then(|n| i32::try_from(n).ok())
        .ok_or_else(|| malformed(format!("{at} must fit i32")))
}
fn precedence(value: Option<&Value>) -> Result<Prec, CompileError> {
    match value {
        Some(Value::String(s)) => Ok(Prec::Named(s.as_str().into())),
        _ => Ok(Prec::Level(integer(value, "precedence")?)),
    }
}
fn contains_symbol(node: &Value) -> bool {
    match node {
        Value::Object(o) => {
            o.get("type").and_then(Value::as_str) == Some("SYMBOL")
                || o.values().any(contains_symbol)
        }
        Value::Array(a) => a.iter().any(contains_symbol),
        _ => false,
    }
}
fn depth_check(depth: usize) -> Result<(), CompileError> {
    if depth > MAX_DEPTH {
        Err(CompileError::Limit("grammar nesting"))
    } else {
        Ok(())
    }
}

fn charge_work(
    work: &mut usize,
    amount: usize,
    shared: &CompileWork,
    label: &'static str,
) -> Result<(), CompileError> {
    shared.charge(amount, label)?;
    *work = work.checked_add(amount).ok_or(CompileError::Limit(label))?;
    Ok(())
}
fn string<'a>(v: &'a Value, at: &str) -> Result<&'a str, CompileError> {
    v.as_str()
        .ok_or_else(|| malformed(format!("{at} must be a string")))
}
fn array<'a>(v: &'a Value, at: &str) -> Result<&'a Vec<Value>, CompileError> {
    v.as_array()
        .ok_or_else(|| malformed(format!("{at} must be an array")))
}
fn property_string<'a>(node: &'a Value, key: &str) -> Result<&'a str, CompileError> {
    string(
        node.get(key)
            .ok_or_else(|| malformed(format!("missing {key}")))?,
        key,
    )
}
fn kind(node: &Value) -> Result<&str, CompileError> {
    property_string(node, "type")
}
fn content(node: &Value) -> Result<&Value, CompileError> {
    node.get("content")
        .ok_or_else(|| malformed("missing content"))
}
fn members(node: &Value) -> Result<&Vec<Value>, CompileError> {
    array(
        node.get("members")
            .ok_or_else(|| malformed("missing members"))?,
        "members",
    )
}

fn collect_atoms(node: &Value, out: &mut BTreeSet<Atom>, depth: usize) -> Result<(), CompileError> {
    depth_check(depth)?;
    match kind(node)? {
        "STRING" | "PATTERN" | "TOKEN" | "IMMEDIATE_TOKEN" => {
            out.insert(atom(node)?);
        }
        "SYMBOL" | "BLANK" => {}
        "SEQ" | "CHOICE" => {
            for child in members(node)? {
                collect_atoms(child, out, depth + 1)?;
            }
        }
        "FIELD" | "ALIAS" | "REPEAT" | "REPEAT1" | "PREC" | "PREC_LEFT" | "PREC_RIGHT"
        | "PREC_DYNAMIC" | "RESERVED" => collect_atoms(content(node)?, out, depth + 1)?,
        other => return Err(CompileError::Unsupported(other.into())),
    }
    Ok(())
}

fn collect_alias_targets<'a>(
    node: &'a Value,
    aliased: bool,
    out: &mut BTreeSet<&'a str>,
    work: &CompileWork,
    depth: usize,
) -> Result<(), CompileError> {
    depth_check(depth)?;
    work.charge(1, "grammar work")?;
    match kind(node)? {
        "ALIAS" => {
            collect_alias_targets(content(node)?, true, out, work, depth + 1)?;
        }
        "SYMBOL" if aliased => {
            out.insert(property_string(node, "name")?);
        }
        "SEQ" | "CHOICE" => {
            for child in members(node)? {
                collect_alias_targets(child, aliased, out, work, depth + 1)?;
            }
        }
        "FIELD" | "PREC" | "PREC_LEFT" | "PREC_RIGHT" | "PREC_DYNAMIC" | "RESERVED" => {
            collect_alias_targets(content(node)?, aliased, out, work, depth + 1)?;
        }
        "REPEAT" | "REPEAT1" => {
            // A repetition creates its own aliasable helper. Its body starts
            // a fresh recipe rather than inheriting the helper's alias.
            collect_alias_targets(content(node)?, false, out, work, depth + 1)?;
        }
        // Tokens own lexical recipes: aliases within them cannot designate a
        // structural rule wrapper.
        "STRING" | "PATTERN" | "TOKEN" | "IMMEDIATE_TOKEN" | "SYMBOL" | "BLANK" => {}
        other => return Err(CompileError::Unsupported(other.into())),
    }
    Ok(())
}

fn atom(node: &Value) -> Result<Atom, CompileError> {
    atom_in_context(node, false)
}

fn extra_atom(node: &Value) -> Result<(Atom, bool), CompileError> {
    let a = atom_in_context(node, true)?;
    // Bare strings deliberately share their visible terminal, just as SYMBOL
    // extras retain their authored identity. All other lexical extras are
    // invisible; regex atoms already have an invented identity when unowned.
    let private = kind(node)? != "STRING" && matches!(a.pattern, Pattern::Literal(_));
    Ok((a, private))
}

fn atom_in_context(node: &Value, mut lexical: bool) -> Result<Atom, CompileError> {
    let mut cursor = node;
    let mut immediate = false;
    let mut precedence = None;
    for _ in 0..=MAX_DEPTH {
        match kind(cursor)? {
            "TOKEN" | "IMMEDIATE_TOKEN" => {
                lexical = true;
                immediate |= kind(cursor)? == "IMMEDIATE_TOKEN";
                cursor = content(cursor)?;
            }
            "ALIAS" if lexical => {
                // Alias metadata beneath a token boundary cannot change a
                // literal into a regex or create a structural child.
                cursor = lexical_alias_content(cursor)?;
            }
            "PREC" | "PREC_LEFT" | "PREC_RIGHT" => {
                if !lexical {
                    return Err(CompileError::Unsupported("syntactic precedence".into()));
                }
                let n = cursor
                    .get("value")
                    .and_then(Value::as_i64)
                    .and_then(|n| i32::try_from(n).ok())
                    .ok_or_else(|| malformed("lexical precedence must fit i32"))?;
                if precedence.is_none() {
                    precedence = Some(n);
                }
                cursor = content(cursor)?;
            }
            "STRING" => {
                return Ok(Atom {
                    pattern: Pattern::Literal(
                        property_string(cursor, "value")?.as_bytes().to_vec(),
                    ),
                    immediate,
                    precedence: precedence.unwrap_or(0),
                });
            }
            "PATTERN" => {
                return Ok(Atom {
                    pattern: Pattern::Regex(render_regex(cursor, 0)?),
                    immediate,
                    precedence: precedence.unwrap_or(0),
                });
            }
            _ if lexical => {
                return Ok(Atom {
                    pattern: Pattern::Regex(render_regex(cursor, 0)?),
                    immediate,
                    precedence: precedence.unwrap_or(0),
                });
            }
            other => {
                return Err(CompileError::Unsupported(format!(
                    "nonlexical {other} used as token"
                )));
            }
        }
    }
    Err(CompileError::Limit("token nesting"))
}

fn render_regex(node: &Value, depth: usize) -> Result<String, CompileError> {
    depth_check(depth)?;
    Ok(match kind(node)? {
        "STRING" => escape_literal(property_string(node, "value")?),
        "PATTERN" => {
            let body = property_string(node, "value")?;
            let flags = node
                .get("flags")
                .map(|f| string(f, "regex flags"))
                .transpose()?
                .unwrap_or("");
            if flags.chars().any(|f| !matches!(f, 'i' | 'm' | 's' | 'u')) {
                return Err(CompileError::Unsupported(format!("regex flags {flags}")));
            }
            // JavaScript Unicode escapes are not copied into another regex
            // dialect on faith. A later transcription pass must handle them.
            let body = transcribe_regex(body)?;
            let flags = flags.replace('u', "");
            if flags.is_empty() {
                format!("(?:{body})")
            } else {
                format!("(?{flags}:{body})")
            }
        }
        "BLANK" => String::new(),
        "SEQ" => {
            let mut out = String::new();
            for child in members(node)? {
                out.push_str(&render_regex(child, depth + 1)?);
            }
            out
        }
        "CHOICE" => {
            let mut arms = Vec::new();
            for child in members(node)? {
                arms.push(render_regex(child, depth + 1)?);
            }
            format!("(?:{})", arms.join("|"))
        }
        "REPEAT" => format!("(?:{})*", render_regex(content(node)?, depth + 1)?),
        "REPEAT1" => format!("(?:{})+", render_regex(content(node)?, depth + 1)?),
        "TOKEN" | "IMMEDIATE_TOKEN" | "PREC" | "PREC_LEFT" | "PREC_RIGHT" => {
            render_regex(content(node)?, depth + 1)?
        }
        "ALIAS" => {
            // An enclosing TOKEN makes its contents one lexical leaf. Aliases
            // inside that boundary retain their match language, not a tree
            // recipe; an alias outside the token still names the whole leaf.
            render_regex(lexical_alias_content(node)?, depth + 1)?
        }
        other => return Err(CompileError::Unsupported(format!("{other} inside token"))),
    })
}

fn lexical_alias_content(node: &Value) -> Result<&Value, CompileError> {
    property_string(node, "value")?;
    if !node.get("named").is_some_and(Value::is_boolean) {
        return Err(malformed("alias named must be boolean"));
    }
    content(node)
}

fn transcribe_regex(body: &str) -> Result<String, CompileError> {
    let bytes = body.as_bytes();
    let mut out = String::new();
    let mut at = 0;
    while at < bytes.len() {
        if bytes[at] != b'\\' {
            let c = body[at..].chars().next().expect("UTF-8 regex");
            out.push(c);
            at += c.len_utf8();
            continue;
        }
        if bytes.get(at + 1) != Some(&b'u') {
            out.push('\\');
            at += 1;
            if at < bytes.len() {
                let c = body[at..].chars().next().expect("UTF-8 regex");
                out.push(c);
                at += c.len_utf8();
            }
            continue;
        }
        let start = at + 2;
        let (hex, end) = if bytes.get(start) == Some(&b'{') {
            let close = body[start + 1..]
                .find('}')
                .ok_or_else(|| malformed("unclosed Unicode regex escape"))?
                + start
                + 1;
            (&body[start + 1..close], close + 1)
        } else {
            let end = start + 4;
            (
                body.get(start..end)
                    .ok_or_else(|| malformed("short Unicode regex escape"))?,
                end,
            )
        };
        if hex.is_empty() || !hex.bytes().all(|b| b.is_ascii_hexdigit()) {
            return Err(malformed("invalid Unicode regex escape"));
        }
        out.push_str("\\x{");
        out.push_str(hex);
        out.push('}');
        at = end;
    }
    Ok(out)
}

fn escape_literal(text: &str) -> String {
    let mut out = String::new();
    for c in text.chars() {
        if matches!(
            c,
            '.' | '+'
                | '*'
                | '?'
                | '('
                | ')'
                | '|'
                | '['
                | ']'
                | '{'
                | '}'
                | '^'
                | '$'
                | '\\'
                | '#'
                | '&'
                | '-'
                | '~'
        ) {
            out.push('\\');
        }
        out.push(c);
    }
    out
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd)]
pub struct StateItem {
    pub production: ProductionId,
    pub dot: usize,
}

type Item = StateItem;

type ShapingStep = (
    Option<FieldId>,
    Option<Alias>,
    AliasRecipe,
    Option<Arc<str>>,
);
type ShapingRecipe = (SymbolId, i32, Vec<ShapingStep>);

/// Once consumed, an earlier precedence vote cannot affect a later cell. Keep
/// the current previous-step vote and every future step, plus the entire tree
/// recipe. Concrete consumed symbols remain in each cursor's provenance class;
/// runtime must resolve a completed family against its actual stack frames.
#[derive(Default)]
struct CursorTable {
    items: Vec<Vec<Item>>,
    classes: BTreeMap<Item, Vec<ProductionId>>,
}

impl CursorTable {
    fn build(productions: &[Production], shared: &CompileWork) -> Result<Self, CompileError> {
        let mut recipes = BTreeMap::<ShapingRecipe, Vec<usize>>::new();
        let mut table: Vec<Vec<Item>> = Vec::with_capacity(productions.len());
        let mut work = 0;
        for (id, p) in productions.iter().enumerate() {
            let mut row: Vec<_> = (0..=p.steps.len())
                .map(|dot| Item {
                    production: ProductionId::from_index(id),
                    dot,
                })
                .collect();
            let key = (
                p.lhs,
                p.dynamic_precedence,
                p.steps
                    .iter()
                    .map(|s| (s.field, s.alias.clone(), s.alias_recipe, s.reserved.clone()))
                    .collect(),
            );
            let prior = recipes.entry(key).or_default();
            for &other in prior.iter() {
                charge_work(&mut work, 1 + p.steps.len(), shared, "item cursor work")?;
                let last = p
                    .steps
                    .iter()
                    .zip(&productions[other].steps)
                    .rposition(|(a, b)| a != b);
                let rank = p
                    .steps
                    .iter()
                    .zip(&productions[other].steps)
                    .rposition(|(a, b)| {
                        a.prec != b.prec
                            || a.assoc != b.assoc
                            || a.region != b.region
                            || a.spliced != b.spliced
                    });
                let begin = last.map_or(0, |i| i + 1).max(rank.map_or(0, |i| i + 2));
                for (dot, item) in row.iter_mut().enumerate().skip(begin) {
                    *item = (*item).min(table[other][dot]);
                }
            }
            prior.push(id);
            table.push(row);
        }
        let mut classes = BTreeMap::<_, Vec<_>>::new();
        for (i, row) in table.iter().enumerate() {
            for &cursor in row {
                classes
                    .entry(cursor)
                    .or_default()
                    .push(ProductionId::from_index(i));
            }
        }
        Ok(Self {
            items: table,
            classes,
        })
    }

    fn at(&self, production: ProductionId, dot: usize) -> Item {
        self.items[production.index()][dot]
    }

    fn variants(&self, item: Item) -> &[ProductionId] {
        &self.classes[&item]
    }
}

type StateItems = Vec<Item>;
type Graph = Vec<BTreeMap<SymbolId, StateId>>;
type Rows = Vec<BTreeMap<Lookahead, Vec<Action>>>;
struct FinishedTables {
    transitions: Graph,
    actions: Rows,
    admissions: Vec<Vec<SymbolId>>,
    conflicts: Vec<ConflictRecord>,
    states: Vec<StateItems>,
}

// Split identities contain immutable kernels and already-frozen partition
// lanes. Each rebuild reads a finite plan; unknown source contexts use lane0.
// Deriving lanes from newly minted state IDs would make cycles copy forever.
type SourceIdentity = (StateItems, usize);
type SplitPlan = BTreeMap<StateItems, BTreeMap<SourceIdentity, usize>>;

fn kernel(items: &[Item]) -> StateItems {
    items
        .iter()
        .copied()
        .filter(|i| i.dot > 0 || i.production.index() == 0)
        .collect()
}

struct Retrace(Vec<BTreeMap<SymbolId, Vec<usize>>>);

impl Retrace {
    fn new(graph: &Graph) -> Self {
        let mut rev = vec![BTreeMap::<SymbolId, Vec<usize>>::new(); graph.len()];
        for (from, edges) in graph.iter().enumerate() {
            for (&symbol, &to) in edges {
                rev[to.index()].entry(symbol).or_default().push(from);
            }
        }
        Self(rev)
    }

    fn back(&self, state: usize, steps: &[Step]) -> BTreeSet<usize> {
        let mut set = BTreeSet::from([state]);
        for step in steps.iter().rev() {
            let mut previous = BTreeSet::new();
            for to in set {
                if let Some(from) = self.0[to].get(&step.symbol) {
                    previous.extend(from.iter().copied());
                }
            }
            set = previous;
        }
        set
    }
}

#[derive(Clone)]
struct Draw {
    under: usize,
    look: LookSet,
}
type Draws = Vec<BTreeMap<ProductionId, Vec<Draw>>>;

fn draws(
    gr: &Builder,
    states: &[StateItems],
    graph: &Graph,
    looks: &[Vec<LookSet>],
    rev: &Retrace,
) -> Result<Draws, CompileError> {
    let mut out = vec![BTreeMap::new(); states.len()];
    let mut work = 0;
    for (s, items) in states.iter().enumerate() {
        for item in items {
            let p = &gr.productions[item.production.index()];
            if gr.is_entry(item.production) || item.dot != p.steps.len() || p.steps.is_empty() {
                continue;
            }
            let mut mine = Vec::new();
            for &actual in gr.cursors.variants(*item) {
                let p = &gr.productions[actual.index()];
                for before in rev.back(s, &p.steps) {
                    charge_work(
                        &mut work,
                        1 + p.steps.len(),
                        &gr.work,
                        "lookahead context work",
                    )?;
                    let Ok(i) = states[before].binary_search(&gr.cursors.at(actual, 0)) else {
                        // A converged graph can have a reverse path from a
                        // different kernel. It is not this production's origin.
                        continue;
                    };
                    let look = &looks[before][i];
                    if look.is_empty() {
                        continue;
                    }
                    let mut under = before;
                    for step in &p.steps[..p.steps.len() - 1] {
                        under = graph[under][&step.symbol].index();
                    }
                    mine.push(Draw {
                        under,
                        look: Arc::clone(look),
                    });
                }
            }
            mine.sort_by(|a, b| (&a.under, &a.look).cmp(&(&b.under, &b.look)));
            mine.dedup_by(|a, b| a.under == b.under && a.look == b.look);
            out[s].insert(item.production, mine);
        }
    }
    Ok(out)
}

fn frays(draws: &Draws, state: usize, token: usize) -> bool {
    draws[state].values().any(|d| {
        d.iter().any(|x| x.look.contains(&token)) && d.iter().any(|x| !x.look.contains(&token))
    })
}

fn split_candidates(
    gr: &Builder,
    states: &[StateItems],
    marks: &[usize],
    candidates: &BTreeMap<usize, BTreeSet<usize>>,
    draws: &Draws,
    plan: &mut SplitPlan,
) -> Result<bool, CompileError> {
    let mut changed = false;
    for (&s, tokens) in candidates {
        gr.work
            .charge(1 + states[s].len(), "context partition work")?;
        let target = kernel(&states[s]);
        let mut profiles = BTreeMap::<usize, BTreeMap<ProductionId, BTreeSet<usize>>>::new();
        for (&p, origins) in &draws[s] {
            for d in origins {
                gr.work.charge(1 + d.look.len(), "context partition work")?;
                profiles
                    .entry(d.under)
                    .or_default()
                    .entry(p)
                    .or_default()
                    .extend(d.look.intersection(tokens).copied());
            }
        }
        let mut groups = BTreeMap::new();
        let mut lanes = BTreeMap::<SourceIdentity, usize>::new();
        for (from, profile) in profiles {
            gr.work
                .charge(1 + states[from].len(), "context partition work")?;
            let next = groups.len();
            let lane = *groups.entry(profile).or_insert(next);
            lanes
                .entry((kernel(&states[from]), marks[from]))
                .and_modify(|l| *l = (*l).min(lane))
                .or_insert(lane);
        }
        if let Some(prior) = plan.get(&target) {
            // A later lookahead can distinguish arrivals an earlier round put
            // together. Refine within each old lane; never join old lanes or
            // key copies by the IDs that refinement itself creates.
            let mut refined = prior.clone();
            let mut groups = BTreeMap::new();
            let mut first = BTreeSet::new();
            let mut next = prior.values().copied().max().unwrap_or(0) + 1;
            for (source, profile) in lanes {
                let old = prior.get(&source).copied().unwrap_or(0);
                let lane = *groups.entry((old, profile)).or_insert_with(|| {
                    if first.insert(old) {
                        old
                    } else {
                        let lane = next;
                        next += 1;
                        lane
                    }
                });
                refined.insert(source, lane);
            }
            if &refined != prior {
                plan.insert(target, refined);
                changed = true;
            }
        } else if lanes.values().copied().collect::<BTreeSet<_>>().len() > 1 {
            plan.insert(target, lanes);
            changed = true;
        }
    }
    Ok(changed)
}

fn by_lhs(symbols: &[Symbol], productions: &[Production]) -> Vec<Vec<ProductionId>> {
    let mut result = vec![Vec::new(); symbols.len()];
    for (i, p) in productions.iter().enumerate() {
        result[p.lhs.index()].push(ProductionId::from_index(i));
    }
    result
}

fn closure(
    kernel: BTreeSet<Item>,
    productions: &[Production],
    rules: &[Vec<ProductionId>],
    cursors: &CursorTable,
    work: &mut usize,
    limits: &CompileLimits,
    shared: &CompileWork,
) -> Result<StateItems, CompileError> {
    let mut items = kernel;
    let mut pending: VecDeque<_> = items.iter().copied().collect();
    let mut expanded = BTreeSet::new();
    while let Some(item) = pending.pop_front() {
        charge_work(work, 1, shared, "LR construction work")?;
        if let Some(step) = productions[item.production.index()].steps.get(item.dot) {
            if !expanded.insert(step.symbol) {
                continue;
            }
            for &rule in &rules[step.symbol.index()] {
                charge_work(work, 1, shared, "LR construction work")?;
                let next = cursors.at(rule, 0);
                if items.insert(next) {
                    if items.len() > limits.items {
                        return Err(CompileError::Limit("LR items"));
                    }
                    pending.push_back(next);
                }
            }
        }
    }
    Ok(items.into_iter().collect())
}

fn lr0(
    gr: &Builder,
    plan: &SplitPlan,
) -> Result<(Vec<StateItems>, Graph, Vec<usize>), CompileError> {
    let symbols = &gr.symbols;
    let productions = &gr.productions;
    let limits = &gr.limits;
    let rules = by_lhs(symbols, productions);
    let mut work = 0;
    let mut known = BTreeMap::new();
    let mut states = Vec::new();
    let mut marks = Vec::new();
    let mut graph = Vec::new();
    let mut count = 0usize;
    for production in gr.entry_productions() {
        if states.len() >= limits.states {
            return Err(CompileError::Limit("LR states"));
        }
        let initial = closure(
            BTreeSet::from([Item { production, dot: 0 }]),
            productions,
            &rules,
            &gr.cursors,
            &mut work,
            limits,
            &gr.work,
        )?;
        count = count
            .checked_add(initial.len())
            .ok_or(CompileError::Limit("LR items"))?;
        if count > limits.items {
            return Err(CompileError::Limit("LR items"));
        }
        known.insert((initial.clone(), 0usize), StateId::from_index(states.len()));
        states.push(initial);
        marks.push(0usize);
        graph.push(BTreeMap::new());
    }
    let mut at = 0;
    while at < states.len() {
        let mut kernels = BTreeMap::<SymbolId, BTreeSet<Item>>::new();
        for item in &states[at] {
            charge_work(&mut work, 1, &gr.work, "LR construction work")?;
            if let Some(step) = productions[item.production.index()].steps.get(item.dot) {
                kernels
                    .entry(step.symbol)
                    .or_default()
                    .insert(gr.cursors.at(item.production, item.dot + 1));
            }
        }
        for (symbol, kernel) in kernels {
            let target: StateItems = kernel.iter().copied().collect();
            let source = (crate::compiler::kernel(&states[at]), marks[at]);
            let lane = plan
                .get(&target)
                .and_then(|p| p.get(&source))
                .copied()
                .unwrap_or(0);
            let items = closure(
                kernel,
                productions,
                &rules,
                &gr.cursors,
                &mut work,
                limits,
                &gr.work,
            )?;
            let key = (items.clone(), lane);
            let id = if let Some(&id) = known.get(&key) {
                id
            } else {
                if states.len() >= limits.states {
                    return Err(CompileError::Limit("LR states"));
                }
                count += items.len();
                if count > limits.items {
                    return Err(CompileError::Limit("LR items"));
                }
                let id = StateId::from_index(states.len());
                known.insert(key, id);
                states.push(items);
                marks.push(lane);
                graph.push(BTreeMap::new());
                id
            };
            graph[at].insert(symbol, id);
        }
        at += 1;
    }
    Ok((states, graph, marks))
}

fn first_sets(
    symbols: &[Symbol],
    productions: &[Production],
    shared: &CompileWork,
) -> Result<(Vec<BTreeSet<usize>>, Vec<bool>), CompileError> {
    let mut first = vec![BTreeSet::new(); symbols.len()];
    let mut nullable = vec![false; symbols.len()];
    for (i, s) in symbols.iter().enumerate() {
        if s.lexis.is_some() {
            first[i].insert(i);
        }
    }
    let mut work = 0;
    loop {
        let mut changed = false;
        for p in productions {
            let mut empty = true;
            for step in &p.steps {
                charge_work(
                    &mut work,
                    1 + first[step.symbol.index()].len(),
                    shared,
                    "FIRST work",
                )?;
                let additions = first[step.symbol.index()].clone();
                let dst = &mut first[p.lhs.index()];
                let before = dst.len();
                dst.extend(additions);
                changed |= before != dst.len();
                if !nullable[step.symbol.index()] {
                    empty = false;
                    break;
                }
            }
            if empty && !nullable[p.lhs.index()] {
                nullable[p.lhs.index()] = true;
                changed = true;
            }
        }
        if !changed {
            break;
        }
    }
    Ok((first, nullable))
}

type LookSet = Arc<BTreeSet<usize>>;
type Lr1Kernel = Vec<(Item, LookSet)>;

struct CanonicalCollection {
    states: Vec<StateItems>,
    graph: Graph,
    looks: Vec<Vec<LookSet>>,
    first: Vec<BTreeSet<usize>>,
}

struct Lr1Builder<'a> {
    gr: &'a Builder,
    rules: Vec<Vec<ProductionId>>,
    first: Vec<BTreeSet<usize>>,
    nullable: Vec<bool>,
    work: usize,
    look_pool: BTreeSet<LookSet>,
}

impl Lr1Builder<'_> {
    fn closure(&mut self, seed: &Lr1Kernel) -> Result<Lr1Kernel, CompileError> {
        let mut items: BTreeMap<_, _> =
            seed.iter().map(|(i, l)| (*i, l.as_ref().clone())).collect();
        let mut pending: VecDeque<_> = items.keys().copied().collect();
        let mut queued: BTreeSet<_> = items.keys().copied().collect();
        while let Some(item) = pending.pop_front() {
            queued.remove(&item);
            let look = &items[&item];
            charge_work(
                &mut self.work,
                1 + look.len(),
                &self.gr.work,
                "LR(1) construction work",
            )?;
            let p = &self.gr.productions[item.production.index()];
            let Some(step) = p.steps.get(item.dot) else {
                continue;
            };
            let mut donated = BTreeSet::new();
            let mut empty = true;
            for suffix in &p.steps[item.dot + 1..] {
                charge_work(
                    &mut self.work,
                    1 + self.first[suffix.symbol.index()].len(),
                    &self.gr.work,
                    "LR(1) construction work",
                )?;
                donated.extend(self.first[suffix.symbol.index()].iter().copied());
                if !self.nullable[suffix.symbol.index()] {
                    empty = false;
                    break;
                }
            }
            if empty {
                donated.extend(look.iter().copied());
            }
            if donated.is_empty() {
                continue;
            }
            for &rule in &self.rules[step.symbol.index()] {
                charge_work(
                    &mut self.work,
                    1 + donated.len(),
                    &self.gr.work,
                    "LR(1) construction work",
                )?;
                let next = self.gr.cursors.at(rule, 0);
                let target = items.entry(next).or_default();
                let before = target.len();
                target.extend(donated.iter().copied());
                if target.len() != before && queued.insert(next) {
                    pending.push_back(next);
                }
            }
            if items.len() > self.gr.limits.items {
                return Err(CompileError::Limit("LR(1) items"));
            }
        }
        Ok(items
            .into_iter()
            .map(|(item, look)| (item, self.intern(look)))
            .collect())
    }

    fn intern(&mut self, look: BTreeSet<usize>) -> LookSet {
        if let Some(found) = self.look_pool.get(&look) {
            return Arc::clone(found);
        }
        let look = Arc::new(look);
        self.look_pool.insert(Arc::clone(&look));
        look
    }
}

// A precise fallback for the remaining merged contexts. Its identities include
// lookahead sets themselves, never transient state addresses. It spends the
// same explicit ceilings as LALR, so a grammar that needs too much refuses.
fn lr1(gr: &Builder) -> Result<CanonicalCollection, CompileError> {
    let (first, nullable) = first_sets(&gr.symbols, &gr.productions, &gr.work)?;
    let mut builder = Lr1Builder {
        gr,
        rules: by_lhs(&gr.symbols, &gr.productions),
        first,
        nullable,
        work: 0,
        look_pool: BTreeSet::new(),
    };
    let mut known = BTreeMap::new();
    let mut states = Vec::new();
    let mut graph = Vec::new();
    let mut count = 0usize;
    for production in gr.entry_productions() {
        if states.len() >= gr.limits.states {
            return Err(CompileError::Limit("LR(1) states"));
        }
        let seed = vec![(
            Item { production, dot: 0 },
            builder.intern(BTreeSet::from([gr.symbols.len()])),
        )];
        let initial = builder.closure(&seed)?;
        count = count
            .checked_add(initial.len())
            .ok_or(CompileError::Limit("LR(1) items"))?;
        if count > gr.limits.items {
            return Err(CompileError::Limit("LR(1) items"));
        }
        known.insert(seed, StateId::from_index(states.len()));
        states.push(initial);
        graph.push(BTreeMap::new());
    }
    let mut at = 0;
    while at < states.len() {
        preflight_rr(gr, at, &states[at])?;
        let mut kernels = BTreeMap::<SymbolId, BTreeMap<Item, BTreeSet<usize>>>::new();
        for (item, look) in &states[at] {
            charge_work(
                &mut builder.work,
                1 + look.len(),
                &gr.work,
                "LR(1) construction work",
            )?;
            if let Some(step) = gr.productions[item.production.index()].steps.get(item.dot) {
                kernels
                    .entry(step.symbol)
                    .or_default()
                    .entry(gr.cursors.at(item.production, item.dot + 1))
                    .or_default()
                    .extend(look.iter().copied());
            }
        }
        for (symbol, kernel) in kernels {
            let key: Lr1Kernel = kernel
                .into_iter()
                .map(|(item, look)| (item, builder.intern(look)))
                .collect();
            let to = if let Some(&id) = known.get(&key) {
                id
            } else {
                if states.len() >= gr.limits.states {
                    return Err(CompileError::Limit("LR(1) states"));
                }
                let closure = builder.closure(&key)?;
                count = count
                    .checked_add(closure.len())
                    .ok_or(CompileError::Limit("LR(1) items"))?;
                if count > gr.limits.items {
                    return Err(CompileError::Limit("LR(1) items"));
                }
                let id = StateId::from_index(states.len());
                known.insert(key, id);
                states.push(closure);
                graph.push(BTreeMap::new());
                id
            };
            graph[at].insert(symbol, to);
        }
        at += 1;
    }
    let (states, looks) = states
        .into_iter()
        .map(|state| state.into_iter().unzip())
        .unzip();
    #[cfg(test)]
    if std::env::var_os("JNT_CENSUS_DETAIL").is_some() {
        eprintln!(
            "{} canonical collection: {} states, {count} items, {} construction work",
            gr.name,
            graph.len(),
            builder.work
        );
    }
    Ok(CanonicalCollection {
        states,
        graph,
        looks,
        first: builder.first,
    })
}

struct LalrTables {
    actions: Rows,
    admissions: Vec<Vec<SymbolId>>,
    conflicts: Vec<ConflictRecord>,
    candidates: BTreeMap<usize, BTreeSet<usize>>,
    draws: Draws,
    priority_sensitive: bool,
}

fn lalr(gr: &Builder, states: &[StateItems], graph: &Graph) -> Result<LalrTables, CompileError> {
    let symbols = &gr.symbols;
    let productions = &gr.productions;
    let (first, nullable) = first_sets(symbols, productions, &gr.work)?;
    let rules = by_lhs(symbols, productions);
    let mut looks: Vec<Vec<LookSet>> = states
        .iter()
        .map(|s| vec![Arc::default(); s.len()])
        .collect();
    let mut queue = VecDeque::new();
    let mut queued: Vec<Vec<bool>> = states.iter().map(|s| vec![false; s.len()]).collect();
    for (s, production) in gr.entry_productions().into_iter().enumerate() {
        let initial = states[s]
            .binary_search(&Item { production, dot: 0 })
            .expect("augmented item");
        Arc::make_mut(&mut looks[s][initial]).insert(symbols.len());
        queue.push_back((s, initial));
        queued[s][initial] = true;
    }
    let mut work = 0;
    while let Some((s, i)) = queue.pop_front() {
        queued[s][i] = false;
        charge_work(&mut work, 1 + looks[s][i].len(), &gr.work, "lookahead work")?;
        let source = Arc::clone(&looks[s][i]);
        let item = states[s][i];
        let p = &productions[item.production.index()];
        if let Some(step) = p.steps.get(item.dot) {
            let to = graph[s][&step.symbol].index();
            let advanced = gr.cursors.at(item.production, item.dot + 1);
            let j = states[to]
                .binary_search(&advanced)
                .expect("LR transition carries item");
            let before = looks[to][j].len();
            Arc::make_mut(&mut looks[to][j]).extend(source.iter().copied());
            if looks[to][j].len() != before && !queued[to][j] {
                queued[to][j] = true;
                queue.push_back((to, j));
            }

            // Only queued, reachable LR(1) items can donate spontaneous FIRST.
            // An LR(0) closure can also contain unproductive paths with no LA.
            let mut donated = BTreeSet::new();
            let mut tail_empty = true;
            for suffix in &p.steps[item.dot + 1..] {
                charge_work(
                    &mut work,
                    1 + first[suffix.symbol.index()].len(),
                    &gr.work,
                    "lookahead work",
                )?;
                donated.extend(first[suffix.symbol.index()].iter().copied());
                if !nullable[suffix.symbol.index()] {
                    tail_empty = false;
                    break;
                }
            }
            if tail_empty {
                donated.extend(source.iter().copied());
            }
            for &rule in &rules[step.symbol.index()] {
                charge_work(&mut work, 1 + donated.len(), &gr.work, "lookahead work")?;
                let child = gr.cursors.at(rule, 0);
                let j = states[s]
                    .binary_search(&child)
                    .expect("LR closure carries production");
                let before = looks[s][j].len();
                Arc::make_mut(&mut looks[s][j]).extend(donated.iter().copied());
                if looks[s][j].len() != before && !queued[s][j] {
                    queued[s][j] = true;
                    queue.push_back((s, j));
                }
            }
        }
    }
    tabulate(gr, states, graph, &looks, &first)
}

fn tabulate(
    gr: &Builder,
    states: &[StateItems],
    graph: &Graph,
    looks: &[Vec<LookSet>],
    first: &[BTreeSet<usize>],
) -> Result<LalrTables, CompileError> {
    let symbols = &gr.symbols;
    let productions = &gr.productions;
    let mut rows = vec![BTreeMap::<Lookahead, Vec<Action>>::new(); states.len()];
    for (s, items) in states.iter().enumerate() {
        for (i, item) in items.iter().enumerate() {
            if looks[s][i].is_empty() {
                continue;
            }
            let p = &productions[item.production.index()];
            if let Some(step) = p.steps.get(item.dot) {
                if symbols[step.symbol.index()].lexis.is_some() {
                    rows[s]
                        .entry(Lookahead::Terminal(step.symbol))
                        .or_default()
                        .push(Action::Shift(graph[s][&step.symbol]));
                }
            } else {
                for &token in looks[s][i].iter() {
                    let at = if token == symbols.len() {
                        Lookahead::End
                    } else {
                        Lookahead::Terminal(SymbolId::from_index(token))
                    };
                    let action = if gr.is_entry(item.production) {
                        Action::Accept
                    } else {
                        Action::Reduce(gr.reduction_ids[item.production.index()])
                    };
                    rows[s].entry(at).or_default().push(action);
                }
            }
        }
    }
    for row in &mut rows {
        for actions in row.values_mut() {
            actions.sort_unstable();
            actions.dedup();
        }
    }
    let rev = Retrace::new(graph);
    let draws = draws(gr, states, graph, looks, &rev)?;
    let mut candidates = BTreeMap::new();
    let (conflicts, priority_sensitive) = resolve(
        Settlement {
            gr,
            states,
            looks,
            first,
            graph,
            rev: &rev,
            draws: &draws,
        },
        &mut rows,
        &mut candidates,
    )?;
    // A residue can inherit a union made before the contested state. Refine
    // only earlier seams whose per-arrival lookaheads actually disagree on a
    // terminal in that residue. This is measured permission damage, rather
    // than copying arbitrary predecessors in search of a different answer.
    let contested: BTreeSet<_> = conflicts
        .iter()
        .filter(|c| c.class == ConflictClass::Residual)
        .map(|c| match c.lookahead {
            Lookahead::Terminal(id) => id.index(),
            Lookahead::End => symbols.len(),
        })
        .collect();
    // Only unresolved contexts need another construction pass. Authored
    // alternatives and already settled cells must not spend the grammar's
    // remaining budget on finer partitions that cannot remove a residual.
    candidates.retain(|_, tokens| {
        tokens.retain(|token| contested.contains(token));
        !tokens.is_empty()
    });
    for s in 0..states.len() {
        for &token in &contested {
            if frays(&draws, s, token) {
                candidates.entry(s).or_default().insert(token);
            }
        }
    }
    let admissions = rows
        .iter()
        .map(|row| {
            row.keys()
                .filter_map(|at| match at {
                    Lookahead::Terminal(id) => Some(*id),
                    Lookahead::End => None,
                })
                .collect()
        })
        .collect();
    Ok(LalrTables {
        actions: rows,
        admissions,
        conflicts,
        candidates,
        draws,
        priority_sensitive,
    })
}

fn compare_rank(
    gr: &Builder,
    a: &Prec,
    a_rules: &[SymbolId],
    b: &Prec,
    b_rules: &[SymbolId],
) -> std::cmp::Ordering {
    use std::cmp::Ordering;
    let numeric = |p: &Prec| match p {
        Prec::None => Some(0),
        Prec::Level(n) => Some(*n),
        Prec::Named(_) => None,
    };
    if let (Some(x), Some(y)) = (numeric(a), numeric(b)) {
        if x != 0 || y != 0 {
            return x.cmp(&y);
        }
    }
    let matches = |entry: &RankRef, p: &Prec, rules: &[SymbolId]| match entry {
        RankRef::Name(n) => matches!(p,Prec::Named(p) if p == n),
        RankRef::Rule(id) => rules.contains(id),
    };
    for list in &gr.orderings {
        let mut left = false;
        let mut right = false;
        for e in list {
            if matches(e, a, a_rules) {
                if right {
                    return Ordering::Less;
                }
                left = true;
            } else if matches(e, b, b_rules) {
                if left {
                    return Ordering::Greater;
                }
                right = true;
            }
        }
    }
    Ordering::Equal
}

// Both complete-table settlement and the canonical-state preflight must apply
// the same authored precedence comparison before deciding whether RR remains.
fn strongest_folds(gr: &Builder, actions: &[Action]) -> (Vec<ProductionId>, Prec) {
    use std::cmp::Ordering;
    let mut folds: Vec<ProductionId> = Vec::new();
    let mut rank = Prec::None;
    for id in actions.iter().filter_map(|a| match a {
        Action::Reduce(p) => Some(gr.reductions[p.index()].productions[0]),
        _ => None,
    }) {
        let p = &gr.productions[id.index()];
        let prec = p.steps.last().map_or(Prec::None, |s| s.prec.clone());
        let speaking: Vec<_> = folds
            .iter()
            .map(|id| gr.productions[id.index()].lhs)
            .collect();
        let ordering = if folds.is_empty() {
            Ordering::Greater
        } else {
            compare_rank(gr, &prec, &[p.lhs], &rank, &speaking)
        };
        match ordering {
            Ordering::Greater => {
                folds.clear();
                folds.push(id);
                rank = prec;
            }
            Ordering::Equal => {
                folds.push(id);
                rank = prec;
            }
            Ordering::Less => {}
        }
    }
    folds.sort_by_key(|id| {
        (
            std::cmp::Reverse(gr.productions[id.index()].dynamic_precedence),
            id.index(),
        )
    });
    (folds, rank)
}

// A canonical closure already contains every reading and direct terminal
// shift in this exact context. Pure authored RR can therefore be refused now,
// before constructing unrelated successor states. Helpers require their full
// predecessor graph for attribution, and any shift/accept may erase the RR;
// those cells remain the complete-table resolver's responsibility.
fn preflight_rr(gr: &Builder, state: usize, items: &Lr1Kernel) -> Result<(), CompileError> {
    let mut shifts = BTreeSet::new();
    let mut completed: BTreeMap<usize, Vec<ProductionId>> = BTreeMap::new();
    for (item, look) in items {
        gr.work
            .charge(1 + look.len(), "LR(1) conflict preflight work")?;
        if look.is_empty() {
            continue;
        }
        let p = &gr.productions[item.production.index()];
        if let Some(step) = p.steps.get(item.dot) {
            if gr.symbols[step.symbol.index()].lexis.is_some() {
                shifts.insert(step.symbol.index());
            }
        } else {
            for &token in look.iter() {
                completed.entry(token).or_default().push(item.production);
            }
        }
    }
    for (token, productions) in completed {
        gr.work
            .charge(productions.len(), "LR(1) conflict preflight work")?;
        if shifts.contains(&token)
            || productions.iter().any(|id| {
                gr.is_entry(*id)
                    || gr.symbols[gr.productions[id.index()].lhs.index()].shape == Shape::Invented
            })
        {
            continue;
        }
        let mut actions: Vec<_> = productions
            .iter()
            .map(|p| Action::Reduce(gr.reduction_ids[p.index()]))
            .collect();
        actions.sort_unstable();
        actions.dedup();
        if actions.len() < 2 {
            continue;
        }
        let (folds, _) = strongest_folds(gr, &actions);
        if folds.len() < 2 {
            continue;
        }
        let party: BTreeSet<_> = productions
            .iter()
            .map(|id| gr.productions[id.index()].lhs)
            .collect();
        if gr
            .declared
            .iter()
            .any(|group| group.iter().copied().eq(party.iter().copied()))
        {
            continue;
        }
        let label = if token == gr.symbols.len() {
            "EOF"
        } else {
            &gr.symbols[token].name
        };
        return Err(CompileError::Conflict {
            state,
            lookahead: format!(
                "{label} (party: {})",
                party
                    .iter()
                    .map(|id| gr.symbols[id.index()].name.as_str())
                    .collect::<Vec<_>>()
                    .join(", ")
            ),
            actions: folds
                .iter()
                .map(|id| Action::Reduce(gr.reduction_ids[id.index()]))
                .collect(),
        });
    }
    Ok(())
}

fn expecting_owners(
    gr: &Builder,
    states: &[StateItems],
    state: usize,
    symbol: SymbolId,
) -> BTreeSet<SymbolId> {
    let mut out = BTreeSet::new();
    for item in &states[state] {
        let p = &gr.productions[item.production.index()];
        if p.steps.get(item.dot).is_none_or(|s| s.symbol != symbol) {
            continue;
        }
        if gr.symbols[p.lhs.index()].shape != Shape::Invented {
            out.insert(p.lhs);
        }
    }
    out
}

fn conflict_party(
    gr: &Builder,
    states: &[StateItems],
    rev: &Retrace,
    state: usize,
    items: &[Item],
) -> (Vec<SymbolId>, bool) {
    let mut named = BTreeSet::new();
    let mut helpers = Vec::new();
    let mut origins = BTreeSet::new();
    for item in items {
        let p = &gr.productions[item.production.index()];
        if gr.symbols[p.lhs.index()].shape == Shape::Invented {
            for &actual in gr.cursors.variants(*item) {
                origins.extend(rev.back(state, &gr.productions[actual.index()].steps[..item.dot]));
            }
            helpers.push(p.lhs);
        } else {
            named.insert(p.lhs);
        }
    }
    let exact = |s: &BTreeSet<SymbolId>| {
        gr.declared
            .iter()
            .any(|g| g.iter().copied().eq(s.iter().copied()))
    };
    if helpers.is_empty() {
        return (named.iter().copied().collect(), exact(&named));
    }
    let mut all = named.clone();
    for q in origins {
        let mut candidate = named.clone();
        for &helper in &helpers {
            candidate.extend(expecting_owners(gr, states, q, helper));
        }
        if exact(&candidate) {
            return (candidate.into_iter().collect(), true);
        }
        all.extend(candidate);
    }
    if all.is_empty() {
        for h in helpers {
            if let Some(owners) = gr.owners.get(&h) {
                all.extend(owners);
            }
        }
    }
    (all.into_iter().collect(), false)
}

// A continuing optional suffix can beat the completed prefix only where the
// merged lookahead invented the contest and folding strands the token. A token
// that an enclosing rule can read belongs to that outer rule instead.
fn strands(
    gr: &Builder,
    states: &[StateItems],
    looks: &[Vec<LookSet>],
    graph: &Graph,
    rev: &Retrace,
    state: usize,
    token: usize,
) -> Result<bool, CompileError> {
    let mut pending = vec![state];
    let mut seen = BTreeSet::from([state]);
    let mut work = 0;
    while let Some(s) = pending.pop() {
        for (i, item) in states[s].iter().enumerate() {
            charge_work(&mut work, 1, &gr.work, "reduction continuation work")?;
            let p = &gr.productions[item.production.index()];
            if gr.is_entry(item.production)
                || item.dot != p.steps.len()
                || !looks[s][i].contains(&token)
            {
                continue;
            }
            for &actual in gr.cursors.variants(*item) {
                let p = &gr.productions[actual.index()];
                for before in rev.back(s, &p.steps) {
                    let Ok(origin) = states[before].binary_search(&gr.cursors.at(actual, 0)) else {
                        continue;
                    };
                    if !looks[before][origin].contains(&token) {
                        continue;
                    }
                    let Some(to) = graph[before].get(&p.lhs) else {
                        continue;
                    };
                    if token < gr.symbols.len()
                        && graph[to.index()].contains_key(&SymbolId::from_index(token))
                    {
                        return Ok(false);
                    }
                    if seen.insert(to.index()) {
                        pending.push(to.index());
                    }
                }
            }
        }
    }
    Ok(true)
}

struct Settlement<'a> {
    gr: &'a Builder,
    states: &'a [StateItems],
    looks: &'a [Vec<LookSet>],
    first: &'a [BTreeSet<usize>],
    graph: &'a Graph,
    rev: &'a Retrace,
    draws: &'a Draws,
}

fn settle_sides(
    above: bool,
    below: bool,
    level: bool,
    left: bool,
    right: bool,
    stranded: bool,
) -> (bool, bool, bool) {
    if above && !below || below && !above && level && right || above == below && stranded {
        (true, false, false)
    } else if below && !above {
        (false, true, false)
    } else if left {
        (false, true, true)
    } else if right {
        (true, false, false)
    } else {
        (true, true, false)
    }
}

fn resolve(
    case: Settlement<'_>,
    rows: &mut Rows,
    candidates: &mut BTreeMap<usize, BTreeSet<usize>>,
) -> Result<(Vec<ConflictRecord>, bool), CompileError> {
    let Settlement {
        gr,
        states,
        looks,
        first,
        graph,
        rev,
        draws,
    } = case;
    use std::cmp::Ordering;
    let mut records = Vec::new();
    let mut priority_sensitive = false;
    let mut work = 0usize;
    for (state, row) in rows.iter_mut().enumerate() {
        for (&at, actions) in row.iter_mut() {
            if actions.len() <= 1 {
                continue;
            }
            let token = match at {
                Lookahead::Terminal(id) => id.index(),
                Lookahead::End => gr.symbols.len(),
            };
            let frayed = frays(draws, state, token);
            let shift = actions
                .iter()
                .copied()
                .find(|a| matches!(a, Action::Shift(_)));
            let (folds, rank) = strongest_folds(gr, actions);
            if folds.is_empty() {
                return Err(malformed("accept action conflicts with another action"));
            }
            let speaking: Vec<_> = folds
                .iter()
                .map(|id| gr.productions[id.index()].lhs)
                .collect();
            let mut left = false;
            let mut right = false;
            let mut loose = false;
            let mut authored = false;
            for id in &folds {
                if let Some(s) = gr.productions[id.index()].steps.last() {
                    match s.assoc {
                        Assoc::Left => left = true,
                        Assoc::Right => right = true,
                        Assoc::None => loose = true,
                    }
                    authored |= s.assoc != Assoc::None && !s.spliced;
                } else {
                    loose = true;
                }
            }
            let purely_left = left && !right && !loose && authored;
            let purely_right = right && !left && !loose && authored;
            let absorbed_left = left && !right && !loose && !authored;
            let absorbed_right = right && !left && !loose && !authored;
            let mut above = false;
            let mut below = false;
            let mut level = false;
            let mut unwritten = false;
            let mut grounded = false;
            let mut party_items = Vec::new();
            let mut ongoing = Vec::new();
            let mut continues = false;
            let mut max_dynamic = i32::MIN;
            for (i, item) in states[state].iter().enumerate() {
                charge_work(&mut work, 1, &gr.work, "conflict work")?;
                if gr.is_entry(item.production) || looks[state][i].is_empty() {
                    continue;
                }
                let p = &gr.productions[item.production.index()];
                if item.dot == p.steps.len() {
                    // Attribution names every completed interpretation of this
                    // prefix, including one removed by the earlier precedence
                    // comparison. Its declaration still explains the surviving
                    // ambiguity (the upstream generator and Zig poll do this).
                    if looks[state][i].contains(&token) {
                        party_items.push(*item);
                    }
                } else if shift.is_some()
                    && item.dot > 0
                    && first[p.steps[item.dot].symbol.index()].contains(&token)
                {
                    let consumed = &p.steps[item.dot - 1];
                    match compare_rank(gr, &consumed.prec, &[p.lhs], &rank, &speaking) {
                        Ordering::Greater => above = true,
                        Ordering::Less => {
                            if rank == Prec::None && matches!(consumed.prec, Prec::Level(_)) {
                                unwritten = true;
                                below |= !frayed;
                            } else {
                                grounded = true;
                                below = true;
                            }
                        }
                        Ordering::Equal => level = true,
                    }
                    max_dynamic = max_dynamic.max(p.dynamic_precedence);
                    continues |= folds.iter().any(|id| {
                        let fold = &gr.productions[id.index()];
                        fold.lhs == p.lhs
                            && fold.steps.len() == item.dot
                            && fold
                                .steps
                                .iter()
                                .map(|s| s.symbol)
                                .eq(p.steps[..item.dot].iter().map(|s| s.symbol))
                    });
                    party_items.push(*item);
                    ongoing.push(*item);
                }
            }
            let repetition = shift.is_some()
                && !party_items.is_empty()
                && party_items.iter().all(|i| {
                    gr.productions[i.production.index()].lhs
                        == gr.productions[party_items[0].production.index()].lhs
                })
                && gr.symbols[gr.productions[party_items[0].production.index()]
                    .lhs
                    .index()]
                .shape
                    == Shape::Invented;
            if repetition {
                if frayed {
                    candidates.entry(state).or_default().insert(token);
                }
                let (party, _) = conflict_party(gr, states, rev, state, &party_items);
                *actions = vec![shift.expect("shift")];
                records.push(ConflictRecord {
                    state: StateId::from_index(state),
                    lookahead: at,
                    class: ConflictClass::Repetition,
                    party,
                    actions: actions.clone(),
                });
                continue;
            }
            let (keep_shift, keep_folds, by_side) = if shift.is_some() {
                let stranded = above == below
                    && continues
                    && frayed
                    && strands(gr, states, looks, graph, rev, state, token)?;
                let settled =
                    settle_sides(above, below, level, purely_left, purely_right, stranded);
                // Frayed origins can withhold a numeric comparison or prefer
                // a continuation. If that changes this cell's static choice,
                // its merged table is insufficient to establish the priority.
                if frayed
                    && settled
                        != settle_sides(
                            above,
                            below || unwritten,
                            level,
                            purely_left,
                            purely_right,
                            false,
                        )
                {
                    priority_sensitive = true;
                }
                settled
            } else {
                (false, true, false)
            };
            // An explicit negative shift loses to the default zero fold in a
            // certain context. Preserve the spare only if donated lookahead
            // withheld that comparison, or another shift has equal rank.
            // Authored associativity remains an independently spared choice.
            let spare = shift.is_some()
                && !keep_shift
                && ((unwritten && !grounded && !above && (frayed || level)) || by_side);
            if !keep_folds {
                if frayed {
                    candidates.entry(state).or_default().insert(token);
                }
                *actions = shift.into_iter().collect();
                continue;
            }
            if !keep_shift {
                party_items.retain(|i| i.dot == gr.productions[i.production.index()].steps.len());
            }
            let (party, declared) = conflict_party(gr, states, rev, state, &party_items);
            let mut alive: Vec<_> = folds
                .iter()
                .map(|p| Action::Reduce(gr.reduction_ids[p.index()]))
                .collect();
            if keep_shift || spare {
                alive.push(shift.expect("kept shift"));
            }
            if alive.len() == 1 {
                if frayed {
                    candidates.entry(state).or_default().insert(token);
                }
                *actions = alive;
                continue;
            }
            let class = if declared {
                ConflictClass::Declared
            } else if folds.len() == 1
                && gr.factored.contains(&gr.productions[folds[0].index()].lhs)
            {
                ConflictClass::Normalized
            } else if shift.is_some() && (absorbed_left || absorbed_right) && !above && !below {
                ConflictClass::Absorbed
            } else if unwritten && !grounded && !above && !below {
                // A frayed merge donated the fold's implied zero. The ranked
                // read remains authored even though its comparison was withheld.
                ConflictClass::Unwritten
            } else if spare {
                if unwritten && !grounded && !above {
                    ConflictClass::Unwritten
                } else {
                    ConflictClass::Sided
                }
            } else {
                ConflictClass::Residual
            };
            #[cfg(test)]
            if class == ConflictClass::Residual
                && std::env::var("JNT_CENSUS_DETAIL").as_deref() == Ok("raw")
            {
                eprintln!(
                    "RAW {} state{state} on{}",
                    gr.name,
                    match at {
                        Lookahead::Terminal(id) => gr.symbols[id.index()].name.as_str(),
                        Lookahead::End => "EOF",
                    }
                );
                for (i, item) in states[state].iter().enumerate() {
                    let p = &gr.productions[item.production.index()];
                    if item.dot != p.steps.len() {
                        continue;
                    }
                    let origins = draws[state].get(&item.production);
                    eprintln!(
                        "  done {}({}) admitted{} rank{:?} origins(total,admitted,first8){:?}",
                        gr.symbols[p.lhs.index()].name,
                        item.production.index(),
                        looks[state][i].contains(&token),
                        p.steps
                            .last()
                            .map(|s| (&s.prec, s.assoc, s.region, s.spliced)),
                        origins.map(|d| (
                            d.len(),
                            d.iter().filter(|d| d.look.contains(&token)).count(),
                            d.iter()
                                .take(8)
                                .map(|d| (d.under, d.look.contains(&token)))
                                .collect::<Vec<_>>()
                        ))
                    );
                }
            }
            if class == ConflictClass::Residual || frayed {
                candidates.entry(state).or_default().insert(token);
            }
            let preferred = if class == ConflictClass::Absorbed && absorbed_left {
                Action::Reduce(gr.reduction_ids[folds[0].index()])
            } else if keep_shift
                && max_dynamic >= gr.productions[folds[0].index()].dynamic_precedence
            {
                shift.expect("shift")
            } else {
                Action::Reduce(gr.reduction_ids[folds[0].index()])
            };
            alive.retain(|a| *a != preferred);
            alive.insert(0, preferred);
            *actions = alive;
            records.push(ConflictRecord {
                state: StateId::from_index(state),
                lookahead: at,
                class,
                party,
                actions: actions.clone(),
            });
        }
    }
    Ok((records, priority_sensitive))
}

#[cfg(test)]
mod tests {
    use super::*;

    const JSON: &[u8] = include_bytes!("../../test/grammar/json.json");

    fn accepts(a: &Automaton, tokens: &[SymbolId]) -> bool {
        accepts_from(a, a.start_state(), tokens)
    }

    fn accepts_from(a: &Automaton, start: StateId, tokens: &[SymbolId]) -> bool {
        let mut stack = vec![start];
        let mut frames = vec![];
        let mut at = 0;
        for _ in 0..10000 {
            let look = tokens
                .get(at)
                .copied()
                .map_or(Lookahead::End, Lookahead::Terminal);
            match a.actions(*stack.last().unwrap(), look) {
                [Action::Shift(to)] => {
                    stack.push(*to);
                    frames.push(tokens[at]);
                    at += 1;
                }
                [Action::Reduce(rule)] => {
                    let family = a.reduction(*rule);
                    if frames.len() < family.width {
                        return false;
                    }
                    let tail = &frames[frames.len() - family.width..];
                    let Some(p) = family
                        .productions
                        .iter()
                        .map(|id| a.production(*id))
                        .find(|p| p.steps.iter().map(|s| s.symbol).eq(tail.iter().copied()))
                    else {
                        return false;
                    };
                    stack.truncate(stack.len() - p.steps.len());
                    frames.truncate(frames.len() - p.steps.len());
                    let Some(to) = a.transition(*stack.last().unwrap(), p.lhs) else {
                        return false;
                    };
                    stack.push(to);
                    frames.push(p.lhs);
                }
                [Action::Accept] => return at == tokens.len(),
                _ => return false,
            }
        }
        panic!("test grammar failed to progress");
    }

    #[test]
    fn rule_shaped_extras_have_independent_shared_graph_entry_states() {
        let src = br#"{"rules":{"doc":{"type":"STRING","value":"x"},"comment":{"type":"SEQ","members":[{"type":"STRING","value":"<"},{"type":"SYMBOL","name":"body"},{"type":"STRING","value":">"}]},"body":{"type":"PATTERN","value":"[a-z]+"}},"extras":[{"type":"SYMBOL","name":"comment"},{"type":"PATTERN","value":"\\s+"}]}"#;
        let a = Automaton::from_tree_sitter(src).unwrap();
        let comment = a.symbol_by_name("comment").unwrap();
        let &[(symbol, entry)] = a.extra_entries() else {
            panic!("one rule-shaped extra")
        };
        assert_eq!(symbol, comment);
        assert_ne!(entry, a.start_state());
        assert_eq!(
            a.actions(a.transition(entry, comment).unwrap(), Lookahead::End),
            &[Action::Accept]
        );
        let tokens: Vec<_> = ["<", "body", ">"]
            .map(|s| a.symbol_by_name(s).unwrap())
            .into();
        assert!(accepts_from(&a, entry, &tokens));
        assert!(!accepts(&a, &tokens));
        assert!(!accepts_from(&a, entry, &tokens[..2]));
        assert!(!accepts_from(&a, entry, &[]));
    }

    #[test]
    fn nullable_rule_shaped_extras_refuse_and_zero_table_limits_are_real() {
        let src = br#"{"rules":{"doc":{"type":"STRING","value":"x"},"comment":{"type":"CHOICE","members":[{"type":"BLANK"},{"type":"SYMBOL","name":"body"}]},"body":{"type":"STRING","value":"y"}},"extras":[{"type":"SYMBOL","name":"comment"}]}"#;
        assert!(
            matches!(Automaton::from_tree_sitter(src), Err(CompileError::Unsupported(s)) if s == "nullable extra comment")
        );
        for limits in [
            CompileLimits {
                states: 0,
                ..CompileLimits::default()
            },
            CompileLimits {
                items: 0,
                ..CompileLimits::default()
            },
        ] {
            assert!(matches!(
                Automaton::from_tree_sitter_with_limits(JSON, limits),
                Err(CompileError::Limit(_))
            ));
        }
    }

    #[test]
    fn pinned_json_is_a_generic_lalr_grammar_with_fields_and_repetition() {
        let a = Automaton::from_tree_sitter(JSON).unwrap();
        assert_eq!(a.name(), "json");
        assert_eq!(a.symbol(a.start_symbol()).name, "document");
        assert!(a.state_count() > 20);
        let n = a.symbol_by_name("number").unwrap();
        assert!(accepts(&a, &[]));
        assert!(accepts(&a, &[n, n, n]));
        let ids: Vec<_> = [
            "{",
            "\"",
            "string_content",
            "\"",
            ":",
            "[",
            "number",
            ",",
            "true",
            "]",
            "}",
        ]
        .iter()
        .map(|n| a.symbol_by_name(n).unwrap())
        .collect();
        assert!(accepts(&a, &ids));
        assert!(!accepts(&a, &ids[..ids.len() - 1]));
        let pair = a.symbol_by_name("pair").unwrap();
        let p = a.productions.iter().find(|p| p.lhs == pair).unwrap();
        assert_eq!(a.field_name(p.steps[0].field.unwrap()), "key");
        assert_eq!(a.field_name(p.steps[2].field.unwrap()), "value");
        assert_eq!(
            a.symbol(a.symbol_by_name("_value").unwrap()).shape,
            Shape::Hidden
        );
    }

    #[test]
    fn lookahead_propagation_is_lalr_not_slr() {
        // The classic assignment grammar has an SLR conflict at `L =`, but
        // LALR's item lookaheads keep the R -> L fold off that cell.
        let src = br#"{"name":"assign","rules":{
          "S":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"SYMBOL","name":"L"},{"type":"STRING","value":"="},{"type":"SYMBOL","name":"R"}]},{"type":"SYMBOL","name":"R"}]},
          "L":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"STRING","value":"*"},{"type":"SYMBOL","name":"R"}]},{"type":"SYMBOL","name":"id"}]},
          "R":{"type":"SYMBOL","name":"L"},"id":{"type":"PATTERN","value":"[a-z]+"}}}"#;
        let a = Automaton::from_tree_sitter(src).unwrap();
        let id = a.symbol_by_name("id").unwrap();
        let eq = a.symbol_by_name("=").unwrap();
        let star = a.symbol_by_name("*").unwrap();
        assert!(accepts(&a, &[id, eq, star, id]));
        assert!(accepts(&a, &[star, id]));
        assert!(!accepts(&a, &[eq, id]));
    }

    #[test]
    fn different_arrival_lookaheads_split_a_lalr_reduce_reduce_merge() {
        // Canonical LR(1), but not LALR(1): A/B complete together after `c`,
        // while their legal followers exchange places under `a` and `b`.
        let src = br#"{"rules":{"doc":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"STRING","value":"a"},{"type":"SYMBOL","name":"A"},{"type":"STRING","value":"d"}]},{"type":"SEQ","members":[{"type":"STRING","value":"b"},{"type":"SYMBOL","name":"A"},{"type":"STRING","value":"e"}]},{"type":"SEQ","members":[{"type":"STRING","value":"a"},{"type":"SYMBOL","name":"B"},{"type":"STRING","value":"e"}]},{"type":"SEQ","members":[{"type":"STRING","value":"b"},{"type":"SYMBOL","name":"B"},{"type":"STRING","value":"d"}]}]},"A":{"type":"STRING","value":"c"},"B":{"type":"STRING","value":"c"}}}"#;
        let a = Automaton::from_tree_sitter(src).unwrap();
        let UniqueValue(root) = serde_json::from_slice(src).unwrap();
        let mut gr = Builder::read(root, CompileLimits::default()).unwrap();
        gr.lower().unwrap();
        let (base, _, _) = lr0(&gr, &SplitPlan::new()).unwrap();
        assert!(a.state_count() > base.len());
        for words in [
            ["a", "c", "d"],
            ["b", "c", "e"],
            ["a", "c", "e"],
            ["b", "c", "d"],
        ] {
            let tokens: Vec<_> = words.iter().map(|w| a.symbol_by_name(w).unwrap()).collect();
            assert!(accepts(&a, &tokens), "{words:?}");
        }
        let mut limits = gr.limits;
        limits.states = base.len();
        assert!(matches!(
            Automaton::from_tree_sitter_with_limits(src, limits),
            Err(CompileError::Limit("LR(1) states"))
        ));
    }

    #[test]
    fn frozen_partition_lanes_stay_finite_on_a_cycle() {
        let src = br#"{"rules":{"doc":{"type":"SYMBOL","name":"s"},"s":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"STRING","value":"a"},{"type":"SYMBOL","name":"s"}]},{"type":"STRING","value":"x"}]}}}"#;
        let UniqueValue(root) = serde_json::from_slice(src).unwrap();
        let mut gr = Builder::read(root, CompileLimits::default()).unwrap();
        gr.lower().unwrap();
        let (base, graph, _) = lr0(&gr, &SplitPlan::new()).unwrap();
        let token = gr.atoms[&atom(&serde_json::json!({"type":"STRING","value":"a"})).unwrap()];
        let at = graph[0][&token].index();
        assert_eq!(graph[at][&token].index(), at);
        let k = kernel(&base[at]);
        let plan = SplitPlan::from([(k.clone(), BTreeMap::from([((k, 0usize), 1usize)]))]);
        let first = lr0(&gr, &plan).unwrap();
        let second = lr0(&gr, &plan).unwrap();
        assert_eq!(first, second);
        assert!(first.0.len() <= base.len() + 2);
        assert_eq!(first.2.iter().copied().max(), Some(1));
    }

    #[test]
    fn a_weaker_completed_reading_still_belongs_to_the_authored_conflict_party() {
        let symbol = |name: &str| serde_json::json!({"type":"SYMBOL","name":name});
        let ranked = |level| serde_json::json!({"type":"PREC","value":level,"content":{"type":"SEQ","members":[{"type":"STRING","value":"a"},{"type":"STRING","value":"b"}]}});
        let alternatives = ["A","B","C"].map(|name| serde_json::json!({"type":"SEQ","members":[symbol(name),{"type":"STRING","value":"x"}]}));
        let mut src = serde_json::json!({"rules":{
            "doc":{"type":"CHOICE","members":alternatives},
            "A":ranked(1),"B":ranked(1),"C":ranked(0),
            "D":{"type":"SEQ","members":[{"type":"STRING","value":"d"},{"type":"STRING","value":"e"}]}
        },"conflicts":[["A","B","C"]]});
        let a = Automaton::from_tree_sitter(&serde_json::to_vec(&src).unwrap()).unwrap();
        let mut expected: Vec<_> = ["A", "B", "C"].map(|n| a.symbol_by_name(n).unwrap()).into();
        expected.sort_unstable();
        let record = a.conflicts().iter().find(|c| c.party == expected).unwrap();
        assert_eq!(record.class, ConflictClass::Declared);
        assert_eq!(record.actions.len(), 2);
        let weaker = a.symbol_by_name("C").unwrap();
        assert!(record.actions.iter().all(|action| match action {
            Action::Reduce(id) => a.reduction(*id).lhs != weaker,
            _ => false,
        }));
        for declaration in [
            serde_json::json!([["A", "B"]]),
            serde_json::json!([["A", "B", "C", "D"]]),
        ] {
            src["conflicts"] = declaration;
            assert!(matches!(
                Automaton::from_tree_sitter(&serde_json::to_vec(&src).unwrap()),
                Err(CompileError::Conflict { .. })
            ));
        }
    }

    #[test]
    fn pair_declarations_do_not_license_the_profiles_three_party_completion() {
        let source = include_bytes!("../tests/fixtures/profile-conflicts.json");
        match Automaton::from_tree_sitter(source) {
            Err(CompileError::Conflict {
                lookahead, actions, ..
            }) => {
                assert!(lookahead.contains("primary_expression"));
                assert!(lookahead.contains("_default_primary_expression"));
                assert!(lookahead.contains("list_splat_pattern"));
                assert_eq!(actions.len(), 3);
            }
            other => {
                panic!("three simultaneous completions require their own declaration: {other:?}")
            }
        }
        let mut repaired: Value = serde_json::from_slice(source).unwrap();
        repaired["conflicts"]
            .as_array_mut()
            .unwrap()
            .push(serde_json::json!([
                "primary_expression",
                "_default_primary_expression",
                "list_splat_pattern"
            ]));
        let a = Automaton::from_tree_sitter(&serde_json::to_vec(&repaired).unwrap()).unwrap();
        assert!(
            a.conflicts()
                .iter()
                .any(|c| c.class == ConflictClass::Declared && c.actions.len() == 3)
        );
    }

    #[test]
    fn optional_word_accepts_omission_or_null_but_rejects_other_non_strings() {
        let mut source = serde_json::json!({"rules":{"doc":{"type":"STRING","value":"x"}}});
        let omitted = Automaton::from_tree_sitter(&serde_json::to_vec(&source).unwrap()).unwrap();
        source["word"] = Value::Null;
        let null = Automaton::from_tree_sitter(&serde_json::to_vec(&source).unwrap()).unwrap();
        assert_eq!(omitted.tables, null.tables);
        assert_eq!(null.word(), None);
        for invalid in [
            serde_json::json!(false),
            serde_json::json!(0),
            serde_json::json!([]),
            serde_json::json!({}),
        ] {
            source["word"] = invalid;
            assert!(matches!(
                Automaton::from_tree_sitter(&serde_json::to_vec(&source).unwrap()),
                Err(CompileError::Malformed(_))
            ));
        }
    }

    #[test]
    fn a_cursor_keeps_its_current_vote_until_the_next_symbol_is_consumed() {
        let UniqueValue(v) =
            serde_json::from_slice(include_bytes!("../tests/fixtures/cursor-ranks.json")).unwrap();
        let mut gr = Builder::read(v, CompileLimits::default()).unwrap();
        gr.lower().unwrap();
        let node = gr.names["node"];
        let ids: Vec<_> = gr
            .productions
            .iter()
            .enumerate()
            .filter(|(_, p)| p.lhs == node)
            .map(|(i, _)| ProductionId::from_index(i))
            .collect();
        assert_eq!(ids.len(), 2);
        assert_ne!(gr.cursors.at(ids[0], 0), gr.cursors.at(ids[1], 0));
        assert_ne!(gr.cursors.at(ids[0], 1), gr.cursors.at(ids[1], 1));
        assert_eq!(gr.cursors.at(ids[0], 2), gr.cursors.at(ids[1], 2));
    }

    #[test]
    fn a_reduction_family_retains_both_distinct_concrete_rhs_histories() {
        let a =
            Automaton::from_tree_sitter(include_bytes!("../tests/fixtures/cursor-histories.json"))
                .unwrap();
        let parent = a.symbol_by_name("parent").unwrap();
        let families: Vec<_> = a.reductions.iter().filter(|r| r.lhs == parent).collect();
        assert_eq!(families.len(), 1);
        let family = families[0];
        assert_eq!(family.width, 2);
        assert_eq!(family.productions.len(), 2);
        let concrete: Vec<_> = family
            .productions
            .iter()
            .map(|id| {
                a.production(*id)
                    .steps
                    .iter()
                    .map(|s| a.symbol(s.symbol).name.as_str())
                    .collect::<Vec<_>>()
            })
            .collect();
        assert_eq!(concrete, vec![vec!["A", "z"], vec!["B", "z"]]);
    }

    #[test]
    fn construction_passes_and_precise_fallback_share_one_work_budget() {
        let UniqueValue(v) = serde_json::from_slice(JSON).unwrap();
        let mut gr = Builder::read(v, CompileLimits::default()).unwrap();
        gr.lower().unwrap();
        let (states, graph, _) = lr0(&gr, &SplitPlan::new()).unwrap();
        lalr(&gr, &states, &graph).unwrap();
        let spent = gr.work.used.get();
        assert!(spent > 0);
        gr.work.limit = spent;
        assert!(matches!(
            lr0(&gr, &SplitPlan::new()),
            Err(CompileError::Limit(_))
        ));
        assert!(matches!(lr1(&gr), Err(CompileError::Limit(_))));
        assert_eq!(gr.work.used.get(), spent, "refuse before unpaid work");
    }

    #[test]
    fn declared_grammar_does_not_refine_already_settled_frayed_cells() {
        let src = br#"{"rules":{"doc":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"STRING","value":"a"},{"type":"SYMBOL","name":"A"},{"type":"STRING","value":"c"}]},{"type":"SEQ","members":[{"type":"STRING","value":"b"},{"type":"SYMBOL","name":"A"},{"type":"STRING","value":"d"}]},{"type":"SEQ","members":[{"type":"STRING","value":"k"},{"type":"SYMBOL","name":"C"}]},{"type":"SEQ","members":[{"type":"STRING","value":"k"},{"type":"SYMBOL","name":"D"}]}]},"A":{"type":"PREC_RIGHT","value":0,"content":{"type":"SEQ","members":[{"type":"STRING","value":"x"},{"type":"CHOICE","members":[{"type":"STRING","value":"c"},{"type":"BLANK"}]}]}},"C":{"type":"PREC","value":0,"content":{"type":"STRING","value":"y"}},"D":{"type":"PREC","value":0,"content":{"type":"STRING","value":"y"}}},"conflicts":[["A"],["C","D"]]}"#;
        let UniqueValue(v) = serde_json::from_slice(src).unwrap();
        let mut gr = Builder::read(v, CompileLimits::default()).unwrap();
        gr.lower().unwrap();
        let (states, graph, _) = lr0(&gr, &SplitPlan::new()).unwrap();
        let tables = lalr(&gr, &states, &graph).unwrap();
        let c = gr.symbols.iter().position(|s| s.name == "c").unwrap();
        assert!((0..states.len()).any(|s| frays(&tables.draws, s, c)));
        assert!(
            tables
                .conflicts
                .iter()
                .any(|c| c.class == ConflictClass::Declared)
        );
        assert!(
            !tables
                .conflicts
                .iter()
                .any(|c| c.class == ConflictClass::Residual)
        );
        assert!(
            !tables.priority_sensitive,
            "a harmless fray is not a precision trigger"
        );
        let limits = CompileLimits {
            // One construction plus the separately billed final diagnostic
            // kernel and frozen-publication passes fit; another LR/context
            // construction still does not. Publication is not free work.
            work: gr.work.used.get()
                + states.iter().map(Vec::len).sum::<usize>()
                + table::publication_work(&graph, &tables.actions).unwrap()
                + 1,
            ..CompileLimits::default()
        };
        let a = Automaton::from_tree_sitter_with_limits(src, limits).unwrap();
        assert_eq!(a.state_count(), states.len());
        // Diagnostic observation has its own explicit work charges. Keep it
        // separate from the original one-construction budget assertion.
        let mut report = CompileReport::default();
        let observed = Automaton::from_tree_sitter_with_diagnostics(
            src,
            CompileLimits::default(),
            None,
            &mut report,
        )
        .unwrap();
        assert_eq!(a.tables, observed.tables);
        assert_eq!(report.rounds.len(), 1);
        assert_eq!(report.rounds[0].stage, CompileStage::Lalr);
        assert!(report.rounds[0].completed);
        gr.work.limit = limits.work;
        assert!(matches!(lr1(&gr), Err(CompileError::Limit(_))));
    }

    #[test]
    fn a_frayed_static_decision_uses_exact_context_and_the_shared_policy() {
        let src = include_bytes!("../tests/fixtures/frayed-priority.json");
        let UniqueValue(root) = serde_json::from_slice(src).unwrap();
        let mut gr = Builder::read(root, CompileLimits::default()).unwrap();
        gr.lower().unwrap();
        let (states, graph, _) = lr0(&gr, &SplitPlan::new()).unwrap();
        let tables = lalr(&gr, &states, &graph).unwrap();
        assert!(tables.priority_sensitive);
        assert!(
            !tables
                .conflicts
                .iter()
                .any(|c| c.class == ConflictClass::Residual)
        );
        let spent = gr.work.used.get();
        let exact = lr1(&gr).unwrap();
        assert!(exact.states.len() > states.len());
        let a = Automaton::from_tree_sitter(src).unwrap();
        assert_eq!(a.state_count(), exact.states.len());
        assert!(
            matches!(
                Automaton::from_tree_sitter_with_limits(
                    src,
                    CompileLimits {
                        work: spent + 1,
                        ..CompileLimits::default()
                    }
                ),
                Err(CompileError::Limit(_))
            ),
            "precision cannot reset the already spent budget"
        );
    }

    #[test]
    fn canonical_rr_preflight_waits_for_all_shifts_and_static_winners() {
        let sym = |name: &str| serde_json::json!({"type":"SYMBOL","name":name});
        let lit = |value: &str| serde_json::json!({"type":"STRING","value":value});
        let seq = |members: Vec<Value>| serde_json::json!({"type":"SEQ","members":members});
        let rank =
            |level, content| serde_json::json!({"type":"PREC","value":level,"content":content});
        for shift in [true, false] {
            let c = if shift {
                rank(2, seq(vec![lit("a"), lit("b"), lit("x")]))
            } else {
                rank(2, seq(vec![lit("a"), lit("b")]))
            };
            let c_use = if shift {
                sym("C")
            } else {
                seq(vec![sym("C"), lit("x")])
            };
            let src = serde_json::json!({"rules":{
                "doc":{"type":"CHOICE","members":[seq(vec![sym("A"),lit("x")]),seq(vec![sym("B"),lit("x")]),c_use]},
                "A":rank(1,seq(vec![lit("a"),lit("b")])),
                "B":rank(1,seq(vec![lit("a"),lit("b")])),"C":c
            }});
            let mut gr = Builder::read(src, CompileLimits::default()).unwrap();
            gr.lower().unwrap();
            let canonical = lr1(&gr).expect("the fully closed cell has a static winner");
            let table = tabulate(
                &gr,
                &canonical.states,
                &canonical.graph,
                &canonical.looks,
                &canonical.first,
            )
            .unwrap();
            assert!(
                !table
                    .conflicts
                    .iter()
                    .any(|c| c.class == ConflictClass::Residual)
            );
        }
    }

    #[test]
    fn canonical_rr_preflight_attributes_weaker_completed_readings() {
        let sym = |name: &str| serde_json::json!({"type":"SYMBOL","name":name});
        let ranked = |level| serde_json::json!({"type":"PREC","value":level,"content":{"type":"SEQ","members":[{"type":"STRING","value":"a"},{"type":"STRING","value":"b"}]}});
        for party in [
            vec!["A", "B"],
            vec!["A", "B", "C"],
            vec!["A", "B", "C", "D"],
        ] {
            let alternatives = ["A","B","C"].map(|name| serde_json::json!({"type":"SEQ","members":[sym(name),{"type":"STRING","value":"x"}]}));
            let src = serde_json::json!({"rules":{
                "doc":{"type":"CHOICE","members":alternatives},
                "A":ranked(1),"B":ranked(1),"C":ranked(0),
                "D":{"type":"STRING","value":"d"}
            },"conflicts":[party]});
            let mut gr = Builder::read(src, CompileLimits::default()).unwrap();
            gr.lower().unwrap();
            match lr1(&gr) {
                Ok(_) => assert_eq!(party, ["A", "B", "C"]),
                Err(CompileError::Conflict {
                    lookahead, actions, ..
                }) => {
                    assert_ne!(party, ["A", "B", "C"]);
                    assert_eq!(lookahead, "x (party: A, B, C)");
                    assert_eq!(actions.len(), 2);
                }
                Err(e) => panic!("unexpected refusal: {e}"),
            }
        }
    }

    #[test]
    #[ignore = "explicit frozen consumer-construction gate; no facet-equivalence claim"]
    fn regulator_profile_has_an_exact_undeclared_three_party_conflict() {
        use sha2::{Digest, Sha256};
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join(
            "../.local/rust-migration/reference-verified/inputs/regulator/python314-derived.json",
        );
        let bytes = std::fs::read(path).expect("frozen reviewed consumer grammar exists");
        assert_eq!(
            Sha256::digest(&bytes)
                .iter()
                .fold(String::new(), |mut text, byte| {
                    use std::fmt::Write as _;
                    write!(text, "{byte:02x}").expect("writing to a String cannot fail");
                    text
                }),
            "04bbc228d1d1cd4977b73131338261d819227c2a236f015bb5835f049e22d300"
        );
        let start = std::time::Instant::now();
        // The official generator rejects these exact bytes too. Public
        // construction must reach that diagnostic under its finite policy.
        match Automaton::from_tree_sitter(&bytes) {
            Err(CompileError::Conflict {
                lookahead, actions, ..
            }) => {
                assert_eq!(
                    lookahead,
                    ". (party: list_splat_pattern, primary_expression, _default_primary_expression)"
                );
                assert_eq!(actions.len(), 3);
            }
            Err(e) => panic!("expected exact authored conflict, got {e}"),
            Ok(_) => panic!("the frozen profile is missing its three-party declaration"),
        }
        eprintln!("Regulator profile exact diagnostic: {:?}", start.elapsed());
    }

    #[test]
    fn nullable_suffix_propagates_eof_through_closure_and_edges() {
        let src = br#"{"rules":{"s":{"type":"SEQ","members":[{"type":"SYMBOL","name":"a"},{"type":"SYMBOL","name":"b"}]},"a":{"type":"REPEAT","content":{"type":"STRING","value":"x"}},"b":{"type":"REPEAT","content":{"type":"STRING","value":"y"}}}}"#;
        let a = Automaton::from_tree_sitter(src).unwrap();
        let x = a.symbol_by_name("x").unwrap();
        let y = a.symbol_by_name("y").unwrap();
        for tokens in [vec![], vec![x], vec![y], vec![x, x, y, y]] {
            assert!(accepts(&a, &tokens));
        }
        assert!(!accepts(&a, &[y, x]));
    }

    #[test]
    fn unresolved_ambiguity_is_a_diagnostic_never_a_default() {
        let src = br#"{"rules":{"s":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"SYMBOL","name":"s"},{"type":"SYMBOL","name":"s"}]},{"type":"STRING","value":"x"}]}}}"#;
        assert!(matches!(
            Automaton::from_tree_sitter(src),
            Err(CompileError::Conflict { .. })
        ));
    }

    #[test]
    fn order_lexical_standing_and_use_site_recipes_survive_lowering() {
        let src = br#"{"name":"t","rules":{"doc":{"type":"SEQ","members":[{"type":"STRING","value":"Z"},{"type":"ALIAS","named":true,"value":"renamed","content":{"type":"FIELD","name":"part","content":{"type":"SYMBOL","name":"tok"}}},{"type":"SYMBOL","name":"body"}]},"tok":{"type":"PATTERN","value":"t[a-z]*"},"body":{"type":"IMMEDIATE_TOKEN","content":{"type":"PREC","value":-2,"content":{"type":"PATTERN","value":"[^z]+"}}}}}"#;
        let a = Automaton::from_tree_sitter(src).unwrap();
        assert!(a.symbol_by_name("Z").unwrap() < a.symbol_by_name("tok").unwrap());
        let body = a
            .symbol(a.symbol_by_name("body").unwrap())
            .lexis
            .as_ref()
            .unwrap();
        assert!(body.immediate);
        assert_eq!(body.precedence, -2);
        let doc = a
            .productions
            .iter()
            .find(|p| p.lhs == a.start_symbol())
            .unwrap();
        assert_eq!(
            doc.steps[1].alias.as_ref().unwrap().name.as_ref(),
            "renamed"
        );
        assert_eq!(a.field_name(doc.steps[1].field.unwrap()), "part");
        assert_eq!(a.symbol(a.symbol_by_name("tok").unwrap()).name, "tok");
    }

    #[test]
    fn an_owned_hidden_literal_keeps_authored_lookup_and_anonymous_lexical_identity() {
        let src=br#"{"word":"_open","rules":{"doc":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_open"},{"type":"STRING","value":"x"}]},"_open":{"type":"STRING","value":"\""}}}"#;
        let a = Automaton::from_tree_sitter(src).unwrap();
        let id = a.symbol_by_name("_open").unwrap();
        assert_eq!(a.terminal_by_name("_open"), Some(id));
        assert_eq!(a.word(), Some(id));
        assert_eq!(a.symbol(id).name, "\"");
        assert_eq!(a.symbol(id).shape, Shape::Anonymous);
        assert_eq!(
            a.symbol(id).lexis.as_ref().unwrap().pattern,
            Pattern::Literal(b"\"".to_vec())
        );
    }

    #[test]
    fn shared_named_atom_wraps_the_anonymous_token_without_renaming_it() {
        let src = br#"{"rules":{"s":{"type":"SEQ","members":[{"type":"STRING","value":"x"},{"type":"SYMBOL","name":"word"}]},"word":{"type":"STRING","value":"x"}}}"#;
        let a = Automaton::from_tree_sitter(src).unwrap();
        let raw = a.symbol_by_name("x").unwrap();
        let word = a.symbol_by_name("word").unwrap();
        assert!(a.symbol(raw).lexis.is_some());
        assert!(a.symbol(word).lexis.is_none());
        assert!(accepts(&a, &[raw, raw]));
    }

    #[test]
    fn rule_names_are_not_shadowed_by_anonymous_terminal_spellings() {
        let src = br#"{"rules":{"doc":{"type":"SEQ","members":[{"type":"STRING","value":"doc"},{"type":"SYMBOL","name":"word"}]},"word":{"type":"PATTERN","value":"[a-z]+"}}}"#;
        let a = Automaton::from_tree_sitter(src).unwrap();
        assert_eq!(a.start_symbol(), a.symbol_by_name("doc").unwrap());
        assert!(a.symbol(a.start_symbol()).lexis.is_none());
        let literal = a
            .lexical_rules()
            .find(|(_, l)| l.pattern == Pattern::Literal(b"doc".to_vec()))
            .unwrap()
            .0;
        assert!(accepts(&a, &[literal, a.symbol_by_name("word").unwrap()]));
    }

    #[test]
    fn long_choices_are_hoisted_instead_of_allocating_their_cross_product() {
        let bit = serde_json::json!({"type":"CHOICE","members":[{"type":"STRING","value":"a"},{"type":"STRING","value":"b"}]});
        let src = serde_json::json!({"rules":{"doc":{"type":"SEQ","members":vec![bit;20]}}});
        let a = Automaton::from_tree_sitter(&serde_json::to_vec(&src).unwrap()).unwrap();
        assert!(a.production_count() < 100);
        let token = a.symbol_by_name("a").unwrap();
        assert!(accepts(&a, &[token; 20]));
        let limits = CompileLimits {
            production_steps: 10,
            ..CompileLimits::default()
        };
        assert!(matches!(
            Automaton::from_tree_sitter_with_limits(&serde_json::to_vec(&src).unwrap(), limits),
            Err(CompileError::Limit(_))
        ));
    }

    #[test]
    fn choice_aggregates_step_budgets_across_separately_bounded_products() {
        let branch = serde_json::json!({"type":"SEQ","members":vec![serde_json::json!({"type":"STRING","value":"x"});20]});
        let src = serde_json::json!({"rules":{"doc":{"type":"CHOICE","members":[branch.clone(),branch]}}});
        let limits = CompileLimits {
            production_steps: 30,
            ..CompileLimits::default()
        };
        assert!(matches!(
            Automaton::from_tree_sitter_with_limits(&serde_json::to_vec(&src).unwrap(), limits),
            Err(CompileError::Limit("expanded steps"))
        ));
    }

    #[test]
    fn repeated_inline_names_are_charged_before_alias_recipe_metadata() {
        let source = serde_json::json!({"name":"inline_budget","rules":{
            "doc":{"type":"SYMBOL","name":"_unit"},
            "_unit":{"type":"SYMBOL","name":"atom"},
            "atom":{"type":"STRING","value":"x"}},"inline":vec!["_unit";512]});
        let source = serde_json::to_vec(&source).unwrap();
        assert!(matches!(
            Automaton::from_tree_sitter_with_limits(
                &source,
                CompileLimits {
                    work: 1_000,
                    ..CompileLimits::default()
                }
            ),
            Err(CompileError::Limit("alias recipe work"))
        ));
        Automaton::from_tree_sitter(&source).unwrap();
    }

    #[test]
    fn expanded_alias_recipes_share_one_immutable_spelling() {
        let name = "long_alias".repeat(4096);
        let src = serde_json::json!({"rules":{"doc":{
            "type":"ALIAS","named":true,"value":name,
            "content":{"type":"SEQ","members":vec![serde_json::json!({"type":"STRING","value":"x"}); 16]}
        }}});
        let a = Automaton::from_tree_sitter(&serde_json::to_vec(&src).unwrap()).unwrap();
        let p = a
            .productions
            .iter()
            .find(|p| p.lhs == a.start_symbol())
            .unwrap();
        let first = &p.steps[0].alias.as_ref().unwrap().name;
        assert!(
            p.steps
                .iter()
                .all(|s| Arc::ptr_eq(first, &s.alias.as_ref().unwrap().name))
        );
        assert_eq!(first.as_ref(), name);
    }

    #[test]
    fn unsupported_features_and_unknown_names_do_not_disappear() {
        for src in [br#"{"rules":{"s":{"type":"SYMBOL","name":"missing"}}}"#.as_slice(),
            br#"{"rules":{"s":{"type":"STRING","value":"x"}},"externals":[{"type":"MYSTERY"}]}"#,
            br#"{"rules":{"s":{"type":"MYSTERY"}}}"#,
            br#"{"rules":{"s":{"type":"ALIAS","value":"x","content":{"type":"STRING","value":"x"}}}}"#] {
            assert!(Automaton::from_tree_sitter(src).is_err());
        }
    }

    #[test]
    fn duplicate_rules_or_wrapper_members_are_malformed_before_lowering() {
        for (src, key) in [
            (br#"{"rules":{"doc":{"type":"STRING","value":"x"},"doc":{"type":"STRING","value":"y"}}}"#.as_slice(), "doc"),
            (br#"{"rules":{"doc":{"type":"UNSUPPORTED","type":"STRING","value":"x"}}}"#, "type"),
            (br#"{"rules":{"doc":{"type":"STRING","value":"x"}},"rules":{"other":{"type":"STRING","value":"y"}}}"#, "rules"),
        ] {
            match Automaton::from_tree_sitter(src) {
                Err(CompileError::Malformed(message)) => {
                    assert!(message.contains("duplicate object key"));
                    assert!(message.contains(key));
                }
                other => panic!("expected duplicate {key} refusal, got {other:?}"),
            }
        }
    }

    #[test]
    fn diagnostics_observe_real_fallback_and_preserve_the_default_table() {
        for source in [
            JSON,
            include_bytes!("../tests/fixtures/frayed-priority.json").as_slice(),
        ] {
            let ordinary = Automaton::from_tree_sitter(source).unwrap();
            let mut report = CompileReport::default();
            let observed = Automaton::from_tree_sitter_with_diagnostics(
                source,
                CompileLimits::default(),
                None,
                &mut report,
            )
            .unwrap();
            assert_eq!(ordinary.tables, observed.tables);
            assert_eq!(ordinary.kernels, observed.kernels);
            assert!(report.tables_complete);
            assert!(!report.truncated);
            assert_eq!(report.rounds[0].stage, CompileStage::Lalr);
            assert_eq!(
                report.rounds.last().unwrap().states,
                Some(observed.state_count())
            );
            assert!(report.rounds.iter().all(|round| round.completed
                && round.items.is_some()
                && round.work_after >= round.work_before));
            assert!(
                report
                    .rounds
                    .windows(2)
                    .all(|rounds| rounds[1].pass == rounds[0].pass + 1
                        && rounds[1].work_before >= rounds[0].work_after)
            );
            assert!(report.work >= report.rounds.last().unwrap().work_after);
            if source != JSON {
                assert!(report.rounds[0].priority_sensitive);
                assert!(
                    report
                        .rounds
                        .iter()
                        .any(|round| round.stage == CompileStage::Canonical)
                );
            }
        }
    }

    fn wide_lr1_context_grammar() -> Vec<u8> {
        // Each prefix assigns A/B different followers. LALR joins them into an
        // RR cell, while exact contexts must retain the long shared handle for
        // each prefix. This makes a later pass exceed the4096 growth floor.
        let literal = |value: String| serde_json::json!({"type":"STRING","value":value});
        let mut alternatives = Vec::new();
        for index in 0..32 {
            for (name, tail) in [("A", index), ("B", (index + 1) % 32)] {
                alternatives.push(serde_json::json!({"type":"SEQ","members":[literal(format!("p{index}")),{"type":"SYMBOL","name":name},literal(format!("q{tail}"))]}));
            }
        }
        let handle = serde_json::json!({"type":"SEQ","members":vec![literal("t".into());140]});
        serde_json::to_vec(&serde_json::json!({"name":"wide_contexts","rules":{
            "doc":{"type":"CHOICE","members":alternatives},"A":handle,"B":handle
        }}))
        .unwrap()
    }

    #[test]
    fn explicit_growth_bounds_only_later_passes_without_raising_absolute_limits() {
        let source = wide_lr1_context_grammar();
        let mut report = CompileReport::default();
        let limits = CompileLimits {
            states: 6000,
            ..CompileLimits::default()
        };
        let complete =
            Automaton::from_tree_sitter_with_diagnostics(&source, limits, None, &mut report)
                .unwrap();
        assert!(complete.state_count() > 4096 && complete.state_count() < 6000);
        assert!(report.rounds[0].states.unwrap() < 4096);
        assert!(report.rounds[0].residual > 0);
        assert!(
            report
                .rounds
                .iter()
                .any(|round| round.stage == CompileStage::Canonical)
        );
        assert_eq!(report.growth_state_limit, None);
        let denied =
            Automaton::from_tree_sitter_with_diagnostics(&source, limits, Some(0), &mut report);
        assert!(matches!(denied, Err(CompileError::Limit("LR(1) states"))));
        assert_eq!(report.growth_state_limit, Some(4096));
        assert!(!report.tables_complete);
        let attempted = report.rounds.last().unwrap();
        assert_eq!(attempted.stage, CompileStage::Canonical);
        assert!(!attempted.completed);
        assert_eq!(attempted.state_limit, 4096);
        assert_eq!(attempted.states, None);
        assert!(attempted.work_after > attempted.work_before);
        let admitted = Automaton::from_tree_sitter_with_diagnostics(
            &source,
            limits,
            Some(u32::MAX),
            &mut report,
        )
        .unwrap();
        assert_eq!(report.growth_state_limit, Some(6000));
        assert_eq!(complete.tables, admitted.tables);
    }

    #[test]
    fn failed_diagnostics_keep_progress_and_clear_prior_results() {
        let mut report = CompileReport::default();
        Automaton::from_tree_sitter_with_diagnostics(
            JSON,
            CompileLimits::default(),
            Some(2),
            &mut report,
        )
        .unwrap();
        assert!(report.tables_complete);
        let result = Automaton::from_tree_sitter_with_diagnostics(
            JSON,
            CompileLimits {
                states: 0,
                ..CompileLimits::default()
            },
            None,
            &mut report,
        );
        assert!(matches!(result, Err(CompileError::Limit(_))));
        assert!(!report.tables_complete);
        assert_eq!(report.growth_state_limit, None);
        assert_eq!(report.rounds.len(), 1);
        assert!(!report.rounds[0].completed);
        assert_eq!(report.rounds[0].states, None);
        assert!(report.work > 0);
        let result = Automaton::from_tree_sitter_with_diagnostics(
            br#"{"rules":{}}"#,
            CompileLimits::default(),
            None,
            &mut report,
        );
        assert!(matches!(result, Err(CompileError::Malformed(_))));
        assert_eq!(report, CompileReport::default());
    }

    #[test]
    fn repeated_compilation_has_identical_numbering_graph_and_actions() {
        let a = Automaton::from_tree_sitter(JSON).unwrap();
        let b = Automaton::from_tree_sitter(JSON).unwrap();
        assert_eq!(a.tables, b.tables);
        assert_eq!(
            a.productions
                .iter()
                .map(|p| (&p.lhs, &p.steps))
                .collect::<Vec<_>>(),
            b.productions
                .iter()
                .map(|p| (&p.lhs, &p.steps))
                .collect::<Vec<_>>()
        );
    }

    #[test]
    fn a_dynamic_rank_is_production_metadata_and_keeps_declared_alternatives() {
        let src=br#"{"rules":{"doc":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"a"},{"type":"SYMBOL","name":"b"}]},"a":{"type":"PREC_DYNAMIC","value":2,"content":{"type":"SEQ","members":[{"type":"STRING","value":"x"},{"type":"PREC_DYNAMIC","value":-5,"content":{"type":"STRING","value":"y"}}]}},"b":{"type":"SEQ","members":[{"type":"STRING","value":"x"},{"type":"STRING","value":"y"}]}},"conflicts":[["a","b"]]}"#;
        let a = Automaton::from_tree_sitter(src).unwrap();
        let rule = a
            .productions
            .iter()
            .find(|p| p.lhs == a.symbol_by_name("a").unwrap())
            .unwrap();
        assert_eq!(rule.dynamic_precedence, -5);
        assert!(rule.steps.iter().all(|s| s.prec == Prec::None));
        let conflict = a
            .conflicts()
            .iter()
            .find(|c| c.class == ConflictClass::Declared)
            .unwrap();
        assert_eq!(conflict.lookahead, Lookahead::End);
        assert_eq!(conflict.actions.len(), 2);
        assert_eq!(
            a.actions(conflict.state, conflict.lookahead),
            conflict.actions
        );
        assert_eq!(
            conflict.party,
            vec![
                a.symbol_by_name("a").unwrap(),
                a.symbol_by_name("b").unwrap()
            ]
        );
    }

    #[test]
    fn rank_region_is_authored_across_the_widest_optional_reading_before_inline() {
        let src=br#"{"rules":{"doc":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"_narrow"},{"type":"SYMBOL","name":"_wide"}]},"_narrow":{"type":"PREC_RIGHT","value":0,"content":{"type":"REPEAT1","content":{"type":"STRING","value":"a"}}},"_wide":{"type":"PREC_LEFT","value":0,"content":{"type":"SEQ","members":[{"type":"CHOICE","members":[{"type":"STRING","value":"b"},{"type":"BLANK"}]},{"type":"STRING","value":"c"}]}}},"inline":["_narrow","_wide"]}"#;
        let a = Automaton::from_tree_sitter(src).unwrap();
        let mut narrow = 0;
        let mut wide = 0;
        for p in a.productions.iter().filter(|p| p.lhs == a.start_symbol()) {
            for step in &p.steps {
                match step.assoc {
                    Assoc::Right => {
                        narrow += 1;
                        assert_eq!(step.region, 1);
                        assert!(!step.spliced);
                    }
                    Assoc::Left => {
                        wide += 1;
                        assert!(step.region > 1);
                        assert!(step.spliced);
                    }
                    Assoc::None => {}
                }
            }
        }
        assert!(narrow > 0 && wide > 0);
    }

    #[test]
    fn anonymous_external_entries_reuse_the_ordinary_token_and_named_ones_override_rules() {
        let src=br#"{"rules":{"doc":{"type":"SEQ","members":[{"type":"STRING","value":"]"},{"type":"SYMBOL","name":"outside"}]},"outside":{"type":"PATTERN","value":"unused"}},"externals":[{"type":"STRING","value":"]"},{"type":"SYMBOL","name":"outside"}]}"#;
        let a = Automaton::from_tree_sitter(src).unwrap();
        let bracket = a.external_by_name("]").unwrap();
        let outside = a.external_by_name("outside").unwrap();
        assert_eq!(a.terminal_by_name("]"), Some(bracket));
        assert_eq!(a.terminal_by_name("outside"), None);
        assert!(a.symbol(bracket).external && a.symbol(outside).external);
        assert_eq!(
            a.symbol(outside).lexis.as_ref().unwrap().pattern,
            Pattern::External
        );
        assert!(
            a.lexical_rules()
                .all(|(_, l)| l.pattern != Pattern::Regex("(?:unused)".into()))
        );
    }

    #[test]
    fn unicode_regex_transcription_preserves_escaped_backslashes_and_unicode_mode() {
        assert_eq!(
            transcribe_regex(r"[\u00A2\u{1f642}]").unwrap(),
            r"[\x{00A2}\x{1f642}]"
        );
        assert_eq!(transcribe_regex(r"\\u00A2").unwrap(), r"\\u00A2");
        assert!(transcribe_regex(r"\u12").is_err());
        let a = atom(&serde_json::json!({"type":"PATTERN","value":"é","flags":"iu"})).unwrap();
        assert_eq!(a.pattern, Pattern::Regex("(?i:é)".into()));
    }

    #[test]
    fn named_precedence_entries_keep_string_ranks_distinct_from_rule_ranks() {
        let src = br#"{"rules":{"doc":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"a"},{"type":"SYMBOL","name":"b"}]},"a":{"type":"PREC","value":"rank","content":{"type":"STRING","value":"x"}},"b":{"type":"PREC","value":"low","content":{"type":"STRING","value":"x"}}},"precedences":[[{"type":"STRING","value":"rank"},{"type":"STRING","value":"low"}],[{"type":"SYMBOL","name":"a"},{"type":"SYMBOL","name":"b"}]]}"#;
        let a = Automaton::from_tree_sitter(src).unwrap();
        assert!(accepts(&a, &[a.symbol_by_name("x").unwrap()]));
        assert!(
            !a.conflicts()
                .iter()
                .any(|c| c.class == ConflictClass::Declared)
        );
    }

    #[test]
    fn an_empty_choice_is_the_empty_language_including_beneath_repeat_one() {
        let src = br#"{"rules":{"doc":{"type":"CHOICE","members":[{"type":"STRING","value":"x"},{"type":"REPEAT1","content":{"type":"CHOICE","members":[]}}]}}}"#;
        let a = Automaton::from_tree_sitter(src).unwrap();
        assert!(accepts(&a, &[a.symbol_by_name("x").unwrap()]));
        assert!(!accepts(&a, &[]));
    }

    #[test]
    #[ignore = "explicit compiler-policy probe over pinned grammar and caller-selected sources"]
    fn working_grammar_tree_probe() {
        fn shape(node: crate::Node<'_>) -> Value {
            let mut v = serde_json::json!({"name":node.name(),"named":node.is_named(),
                "start":node.span().start(),"end":node.span().end(),
                "kids":node.children().map(shape).collect::<Vec<_>>()});
            if let Some(field) = node.field() {
                v["field"] = serde_json::json!(field);
            }
            v
        }
        let grammar_path = std::env::var("JNT_TREE_GRAMMAR").expect("explicit grammar path");
        let grammar =
            crate::CompiledGrammar::compile(&std::fs::read(&grammar_path).unwrap()).unwrap();
        let mut session = grammar.session();
        let mut results = Vec::new();
        for path in std::env::var("JNT_TREE_SOURCES")
            .expect("explicit source paths")
            .split(';')
        {
            let source = std::fs::read(path).unwrap();
            let tree = session.parse_partial(&source).unwrap();
            results.push(
                serde_json::json!({"path":path,"stop":format!("{:?}",tree.stop()),
                "mends":tree.mends(),"tree":tree.roots().map(shape).collect::<Vec<_>>()}),
            );
        }
        std::fs::write(
            std::env::var("JNT_TREE_OUTPUT").expect("explicit output path"),
            serde_json::to_vec_pretty(&results).unwrap(),
        )
        .unwrap();
    }

    #[test]
    #[ignore = "requires all immutable working-set grammar inputs; reports every selected construction"]
    fn working_set_construction_census() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../upstream/grammars");
        let selected = std::env::var("JNT_CENSUS").ok();
        let mut failures = Vec::new();
        let mut count = 0;
        let limits = CompileLimits {
            states: std::env::var("JNT_CENSUS_STATES")
                .ok()
                .map(|s| s.parse().expect("numeric explicit census state policy"))
                .unwrap_or(MAX_STATES),
            items: std::env::var("JNT_CENSUS_ITEMS")
                .ok()
                .map(|s| s.parse().expect("numeric explicit census item policy"))
                .unwrap_or(MAX_ITEMS),
            work: std::env::var("JNT_CENSUS_WORK")
                .ok()
                .map(|s| s.parse().expect("numeric explicit census work policy"))
                .unwrap_or(MAX_WORK),
            ..CompileLimits::default()
        };
        for line in include_str!("../../grammars.toml").lines() {
            let Some(name) = line
                .strip_prefix("name = \"")
                .and_then(|v| v.strip_suffix('"'))
            else {
                continue;
            };
            if selected
                .as_ref()
                .is_some_and(|s| !s.split(',').any(|p| p == name))
            {
                continue;
            }
            count += 1;
            let bytes = std::fs::read(root.join(format!("{name}.json")))
                .expect("every selected pin must exist");
            let start = std::time::Instant::now();
            match Automaton::from_tree_sitter_with_limits(&bytes, limits) {
                Ok(a) => eprintln!(
                    "{name}: {} states, {} productions, {} classified cells, {:?}",
                    a.state_count(),
                    a.production_count(),
                    a.conflicts().len(),
                    start.elapsed()
                ),
                Err(e) => {
                    eprintln!("{name}: {e}, {:?}", start.elapsed());
                    failures.push((name.to_owned(), e.to_string()));
                }
            }
        }
        assert!(count > 0, "empty construction scope");
        assert!(
            failures.is_empty(),
            "{} of {count} construction failures: {failures:?}",
            failures.len()
        );
    }
}

#[cfg(test)]
mod artifact_contract {
    use super::*;
    use crate::artifact::{ArtifactError, ArtifactLimits, Reader, Writer};
    const SOURCE:&[u8]=br#"{"name":"checks","rules":{"doc":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"STRING","value":"a"},{"type":"STRING","value":"x"}]},{"type":"SEQ","members":[{"type":"STRING","value":"b"},{"type":"STRING","value":"x"}]}]}}}"#;
    fn prove_refusal(label: &str, change: impl FnOnce(&mut Automaton)) {
        let mut a = Automaton::from_tree_sitter(SOURCE).unwrap();
        change(&mut a);
        let mut w = Writer::new();
        a.write_artifact(&mut w).unwrap();
        let mut r = Reader::new(&w.bytes, ArtifactLimits::default());
        assert!(
            matches!(
                Automaton::read_artifact("checks".into(), &mut r),
                Err(ArtifactError::Invalid(_))
            ),
            "{label}"
        );
    }
    #[test]
    fn decoded_indexes_and_reduction_recipes_are_checked_before_runtime_use() {
        prove_refusal("symbol", |a| {
            a.productions
                .iter_mut()
                .find(|p| !p.steps.is_empty())
                .unwrap()
                .steps[0]
                .symbol = SymbolId::from_index(u32::MAX as usize)
        });
        prove_refusal("field", |a| {
            a.productions
                .iter_mut()
                .find(|p| !p.steps.is_empty())
                .unwrap()
                .steps[0]
                .field = Some(FieldId::from_index(999))
        });
        prove_refusal("name", |a| {
            a.names.insert("bad".into(), SymbolId::from_index(999));
        });
        prove_refusal("reduction width", |a| a.reductions[0].width += 1);
        prove_refusal("reduction production", |a| {
            a.reductions[0].productions[0] = ProductionId::from_index(999)
        });
        prove_refusal("reduction ID", |a| {
            a.tables.mutate(|_, rows| {
                *rows
                    .iter_mut()
                    .find_map(|row| row.values_mut().next())
                    .unwrap() = vec![Action::Reduce(ReductionId::from_index(999))];
            });
        });
        prove_refusal("state", |a| {
            a.tables.mutate(|graph, _| {
                *graph
                    .iter_mut()
                    .find_map(|row| row.values_mut().next())
                    .unwrap() = StateId::from_index(999);
            });
        });
        prove_refusal("extra entry", |a| {
            a.extra_entries.push((a.start, StateId::from_index(999)))
        });
        prove_refusal("external roster", |a| a.externals.push(a.start));
        prove_refusal("nonterminal lookahead", |a| {
            let symbol = a.productions[0].lhs;
            a.tables.mutate(|_, rows| {
                rows[0].insert(Lookahead::Terminal(symbol), vec![Action::Accept]);
            });
        });
        prove_refusal("family recipe", |a| {
            let f = a
                .reductions
                .iter()
                .find(|f| f.productions.len() > 1)
                .unwrap();
            let p = f.productions[1];
            a.productions[p.index()].steps[0].alias = Some(Alias {
                name: "changed".into(),
                named: true,
            });
        });
        prove_refusal("kernel ID", |a| {
            a.kernels[0][0].production = ProductionId::from_index(999)
        });
        prove_refusal("cursor dot", |a| {
            let (mut key, members) = a.cursor_histories.pop_last().unwrap();
            // The wire's u32 dot itself is checked; use its largest encodable value.
            key.dot = u32::MAX as usize;
            a.cursor_histories.insert(key, members);
        });
        prove_refusal("missing concrete cursor", |a| {
            a.cursor_histories.pop_last();
        });
        prove_refusal("cursor forward congruence", |a| {
            let (&item, members) = a
                .cursor_histories
                .iter()
                .find(|(item, members)| {
                    members.len() > 1 && item.dot < a.production(item.production).steps.len()
                })
                .unwrap();
            let other = members[1];
            let (&next, _) = a
                .cursor_histories
                .iter()
                .find(|(key, members)| key.dot == item.dot + 1 && members.contains(&other))
                .unwrap();
            a.cursor_histories
                .get_mut(&next)
                .unwrap()
                .retain(|p| *p != other);
            a.cursor_histories.insert(
                StateItem {
                    production: other,
                    dot: item.dot + 1,
                },
                vec![other],
            );
        });
    }
    #[test]
    fn lowered_publication_preserves_every_concrete_history() {
        let a = Automaton::from_tree_sitter(SOURCE).unwrap();
        let mut w = Writer::new();
        a.write_artifact(&mut w).unwrap();
        let mut r = Reader::new(&w.bytes, ArtifactLimits::default());
        let b = Automaton::read_artifact("checks".into(), &mut r).unwrap();
        r.finish().unwrap();
        assert_eq!(
            a.reductions
                .iter()
                .map(|f| f.productions.len())
                .sum::<usize>(),
            a.productions.len()
        );
        assert_eq!(format!("{:?}", a), format!("{:?}", b));
    }

    #[test]
    fn flat_table_validation_keeps_empty_duplicate_and_singleton_failure_order() {
        let refusal = |change: fn(&mut Automaton), expected: &str| {
            let mut a = Automaton::from_tree_sitter(SOURCE).unwrap();
            change(&mut a);
            let mut w = Writer::new();
            a.write_artifact(&mut w).unwrap();
            let mut r = Reader::new(&w.bytes, ArtifactLimits::default());
            let error = Automaton::read_artifact("checks".into(), &mut r).unwrap_err();
            assert_eq!(
                error.to_string(),
                format!("invalid native artifact: {expected}")
            );
        };
        refusal(
            |a| {
                a.tables.mutate(|_, rows| {
                    rows[0].insert(Lookahead::End, Vec::new());
                });
                a.extra_entries.push((a.start, StateId::from_index(999)));
            },
            "empty action cell",
        );
        refusal(
            |a| {
                a.tables.mutate(|_, rows| {
                    *rows
                        .iter_mut()
                        .find_map(|row| row.values_mut().next())
                        .unwrap() = vec![Action::Reduce(ReductionId::from_index(0)); 2];
                })
            },
            "duplicate action",
        );
        refusal(
            |a| {
                a.tables.mutate(|_, rows| {
                    *rows
                        .iter_mut()
                        .find_map(|row| row.values_mut().next())
                        .unwrap() = vec![Action::Reduce(ReductionId::from_index(999)); 2];
                })
            },
            "reduction ID",
        );
        refusal(
            |a| {
                a.tables.mutate(|_, rows| {
                    *rows
                        .iter_mut()
                        .find_map(|row| row.values_mut().next())
                        .unwrap() = vec![Action::Reduce(ReductionId::from_index(999))];
                })
            },
            "reduction ID",
        );
        refusal(
            |a| {
                a.tables.mutate(|_, rows| {
                    *rows
                        .iter_mut()
                        .find_map(|row| row.values_mut().next())
                        .unwrap() =
                        vec![Action::Reduce(ReductionId::from_index(999)), Action::Accept];
                })
            },
            "accept alternatives",
        );
    }

    #[test]
    fn frozen_publication_cost_is_reported_and_cannot_exceed_the_existing_budget() {
        let mut report = CompileReport::default();
        let a = Automaton::from_tree_sitter_with_diagnostics(
            SOURCE,
            CompileLimits::default(),
            None,
            &mut report,
        )
        .unwrap();
        let (graph, rows) = a.tables.maps();
        let publication = table::publication_work(&graph, &rows).unwrap();
        assert!(publication > 0);
        assert!(report.work > publication);
        let mut exact = CompileLimits {
            work: report.work,
            ..CompileLimits::default()
        };
        let mut repeated = CompileReport::default();
        assert!(
            Automaton::from_tree_sitter_with_diagnostics(SOURCE, exact, None, &mut repeated)
                .is_ok()
        );
        assert_eq!(repeated.work, report.work);
        exact.work -= 1;
        let mut failed = CompileReport::default();
        assert!(matches!(
            Automaton::from_tree_sitter_with_diagnostics(SOURCE, exact, None, &mut failed),
            Err(CompileError::Limit("frozen table publication work"))
        ));
        assert!(!failed.tables_complete);
        assert_eq!(failed.work, report.work - publication);
    }
}
