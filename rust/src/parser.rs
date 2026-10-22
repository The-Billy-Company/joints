//! One LR executor serves deterministic parsing, declared branches, and repairs.
use crate::{
    ByteSpan, CompiledGrammar, Error, FieldId, ProductionId, Resource, StateId, Stop, Survey,
    SymbolId, TreeSnapshot,
    compiler::{Action, Lookahead},
    effects::{Effect, EffectError, EffectStore},
    ids::ReductionId,
    lexer::{Lexeme, Scan},
    recovery::{self, Insertion, Proof},
    scanner::ScannerState,
    tree::{NodeData, NodeId, Repair, RepairKind},
};
use std::{borrow::Cow, collections::VecDeque, sync::Arc};

mod admissions;
mod cache;
mod choice;
mod history;

use admissions::AdmissionSlate;
use history::History;

#[derive(Clone, Copy, PartialEq, Eq)]
enum ScanScope {
    Document,
    Structural,
    Extra,
}

/// Role-specific exclusions belong to one unchanged source/head question.
#[derive(Default)]
struct Exclusions {
    ordinary: Vec<SymbolId>,
    auxiliary: Vec<SymbolId>,
    end: bool,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Scanned {
    scan: Scan,
    provisional: bool,
}
#[derive(Clone, Copy)]
enum Boundary {
    Unprobed,
    Extra { accepted: bool },
}
enum Reading {
    Aside(Head),
    Extra(Head, Lexeme),
    Advanced(Advanced),
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Recovery {
    #[default]
    None,
    Keep,
    Fell,
    Relent,
}
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Supply {
    #[default]
    Disabled,
    UniqueLiteral,
}

/// Work limits count speculative reads and syntax construction as well as LR moves.
#[derive(Clone, Copy, Debug)]
pub struct ParseLimits {
    pub source_bytes: usize,
    pub steps: usize,
    pub lexical_steps: usize,
    pub stack: usize,
    pub nodes: usize,
    pub heads: usize,
}
impl Default for ParseLimits {
    fn default() -> Self {
        Self {
            source_bytes: 64 << 20,
            steps: 160_000_000,
            lexical_steps: 100_000_000,
            stack: 1_000_000,
            nodes: 2_000_000,
            heads: 8192,
        }
    }
}

/// One structural token on the final selected path. Skipped extras and EOF
/// folds are outside this stream. Move indices address this session's actual
/// trace; the token's entry precedes reductions caused by its lookahead.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ParsedToken {
    pub symbol: SymbolId,
    pub span: ByteSpan,
    pub entry: StateId,
    pub from: StateId,
    pub supplied: bool,
    pub moves: std::ops::Range<usize>,
}

/// Alias and field are use-site facts. Branches never mutate shared draft nodes.
#[derive(Clone, Copy, Debug)]
struct Use {
    draft: usize,
    alias: Option<(ProductionId, usize)>,
    field: Option<FieldId>,
}
#[derive(Debug)]
struct Draft {
    symbol: SymbolId,
    span: ByteSpan,
    children: Vec<Use>,
    extra: bool,
}
#[derive(Clone, Debug)]
struct Frame {
    symbol: SymbolId,
    span: ByteSpan,
    lead: Vec<Use>,
    body: Vec<Use>,
    unproven: bool,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Move {
    Shift {
        from: StateId,
        symbol: SymbolId,
    },
    Reduce {
        under: StateId,
        production: ProductionId,
    },
    Hole,
}
#[derive(Clone)]
struct Head {
    slate: Option<Arc<AdmissionSlate>>,
    states: Vec<StateId>,
    frames: Vec<Frame>,
    pending: Vec<Use>,
    trace: History<Move>,
    ends: Option<History<usize>>,
    tokens: Option<Vec<ParsedToken>>,
    at: usize,
    last_end: usize,
    fresh: bool,
    after_node: bool,
    scanner: ScannerState,
    dynamic: i64,
    rank: u64,
    birth: u64,
    repaired: bool,
    declared: bool,
    shifted: usize,
    kept: bool,
}
impl Head {
    fn new(start: StateId, at: usize) -> Self {
        Self {
            slate: None,
            states: vec![start],
            frames: vec![],
            pending: vec![],
            trace: History::default(),
            ends: None,
            tokens: None,
            at,
            last_end: at,
            fresh: true,
            after_node: false,
            scanner: ScannerState::default(),
            dynamic: 0,
            rank: 0,
            birth: 0,
            repaired: false,
            declared: false,
            shifted: 0,
            kept: false,
        }
    }
    fn record_work(&self) -> usize {
        self.trace
            .push_work()
            .saturating_add(self.ends.as_ref().map_or(0, History::push_work))
    }
    fn record(&mut self, movement: Move, end: usize) -> Result<(), Error> {
        self.repaired |= matches!(movement, Move::Hole);
        if let Some(ends) = &mut self.ends {
            ends.push(ends.last().copied().unwrap_or(0).max(end))
                .map_err(|_| Error::LimitExceeded(Resource::Work))?;
        }
        self.trace
            .push(movement)
            .map_err(|_| Error::LimitExceeded(Resource::Work))
    }
    fn clone_work(&self) -> usize {
        self.clone_without_history_work()
            .saturating_add(self.trace.clone_work())
            .saturating_add(self.ends.as_ref().map_or(0, History::clone_work))
            .saturating_add(usize::from(self.slate.is_some()))
    }
    /// Checkpoints omit derived slates and both histories, copying these fields.
    fn clone_without_history_work(&self) -> usize {
        self.frames.iter().fold(
            self.states
                .len()
                .saturating_add(self.tokens.as_ref().map_or(0, Vec::len))
                .saturating_add(self.pending.len())
                .saturating_add(self.scanner.clone_work()),
            |work, frame| {
                work.saturating_add(1)
                    .saturating_add(frame.lead.len())
                    .saturating_add(frame.body.len())
            },
        )
    }
    fn twins(&self, other: &Self) -> bool {
        self.at == other.at
            && self.last_end == other.last_end
            && self.fresh == other.fresh
            && self.after_node == other.after_node
            && self.scanner == other.scanner
            && self.kept == other.kept
            && self.states == other.states
            && self
                .frames
                .iter()
                .map(|f| f.symbol)
                .eq(other.frames.iter().map(|f| f.symbol))
    }
}
struct Failure {
    head: Head,
    stop: Stop,
    token: Option<Lexeme>,
}
fn failure_order(a: &Failure, b: &Failure) -> std::cmp::Ordering {
    b.head
        .dynamic
        .cmp(&a.head.dynamic)
        .then(a.head.birth.cmp(&b.head.birth))
        .then(b.head.at.cmp(&a.head.at))
}

struct Advanced {
    shifted: Vec<Head>,
    accepted: Vec<Head>,
    failures: Vec<Failure>,
}
struct Materialized {
    nodes: Vec<NodeData>,
    children: Vec<NodeId>,
    roots: Vec<NodeId>,
}
enum RunState {
    Empty,
    Parsing,
    Complete,
}

/// Sessions own mutable work; snapshots own their selected syntax and source.
pub struct ParseSession {
    grammar: Arc<CompiledGrammar>,
    limits: ParseLimits,
    choices: choice::Policies,
    slates: admissions::SlatePool,
    lexer_scratch: crate::lexer::ScanScratch,
    shifted_scratch: Vec<Head>,
    recovery: Recovery,
    supply: Supply,
    drafts: Vec<Draft>,
    trace: Vec<Move>,
    ends: Vec<usize>,
    tokens: Option<Vec<ParsedToken>>,
    trace_enabled: bool,
    token_reads: usize,
    document_source: Option<Arc<[u8]>>,
    cache: Option<cache::ParseCache>,
    recording: Option<cache::Recording>,
    document_reuse: bool,
    resume: Option<Head>,
    steps: usize,
    lexical_remaining: usize,
    run: RunState,
    #[cfg(test)]
    slate_stats: admissions::Stats,
    #[cfg(test)]
    slate_cache_disabled: bool,
}
impl ParseSession {
    pub fn new(grammar: Arc<CompiledGrammar>) -> Self {
        Self {
            grammar,
            limits: ParseLimits::default(),
            choices: choice::Policies::default(),
            slates: admissions::SlatePool::default(),
            lexer_scratch: crate::lexer::ScanScratch::default(),
            shifted_scratch: Vec::new(),
            recovery: Recovery::None,
            supply: Supply::Disabled,
            drafts: vec![],
            trace: vec![],
            ends: vec![],
            tokens: None,
            trace_enabled: false,
            token_reads: 0,
            document_source: None,
            cache: None,
            recording: None,
            document_reuse: true,
            resume: None,
            steps: 0,
            lexical_remaining: 0,
            run: RunState::Empty,
            #[cfg(test)]
            slate_stats: admissions::Stats::default(),
            #[cfg(test)]
            slate_cache_disabled: false,
        }
    }
    pub fn with_limits(grammar: Arc<CompiledGrammar>, limits: ParseLimits) -> Self {
        Self {
            limits,
            ..Self::new(grammar)
        }
    }
    /// Opt into selected-path receipts for subsequent parses. Normal sessions
    /// allocate no receipt vector. Changing this setting invalidates old receipts.
    pub fn set_trace_enabled(&mut self, enabled: bool) {
        self.trace_enabled = enabled;
        self.tokens = None;
        // Checkpoints intentionally omit selected-token histories. Starting an
        // observer therefore begins from the source's actual initial context.
        self.cache = None;
        self.resume = None;
    }

    /// Available after a completed parse, including a diagnostic partial forest.
    /// An operational failure and a disabled observer both return `None`.
    pub fn selected_tokens(&self) -> Option<&[ParsedToken]> {
        if matches!(self.run, RunState::Complete) {
            self.tokens.as_deref()
        } else {
            None
        }
    }

    /// Actual token-returning scan calls in the latest operation. Includes
    /// speculative extra trials and prefix-validation replay, even on failure.
    pub fn token_reads(&self) -> usize {
        self.token_reads
    }

    pub fn set_recovery(&mut self, recovery: Recovery) {
        self.recovery = recovery;
    }
    pub fn set_supply(&mut self, supply: Supply) {
        self.supply = supply;
    }
    pub fn parse(&mut self, source: &[u8]) -> Result<TreeSnapshot, Error> {
        let tree = self.parse_partial(source)?;
        if tree.confidence().is_strict() {
            Ok(tree)
        } else {
            Err(Error::Refused(Box::new(tree)))
        }
    }

    pub fn parse_partial(&mut self, source: &[u8]) -> Result<TreeSnapshot, Error> {
        self.cache = None;
        self.recording = None;
        self.document_source = None;
        self.resume = None;
        self.reset_run();
        self.parse_inner(source)
    }
    fn reset_run(&mut self) {
        self.slates.clear();
        #[cfg(test)]
        {
            self.slate_stats = admissions::Stats::default();
        }
        self.run = RunState::Parsing;
        self.trace.clear();
        self.tokens = None;
        self.token_reads = 0;
        self.drafts.clear();
        self.steps = 0;
        self.lexical_remaining = self.limits.lexical_steps;
        self.ends.clear();
    }
    fn parse_inner(&mut self, source: &[u8]) -> Result<TreeSnapshot, Error> {
        let max = self.limits.source_bytes.min(u32::MAX as usize);
        if source.len() > max {
            return Err(Error::SourceTooLarge {
                actual: source.len(),
                limit: max,
            });
        }
        if self.limits.heads == 0 {
            return Err(Error::LimitExceeded(Resource::Heads));
        }
        let mut first = self
            .resume
            .take()
            .unwrap_or_else(|| Head::new(self.grammar.automaton.start_state(), 0));
        if self.trace_enabled {
            first.tokens = Some(vec![]);
            // The research observer is independent of document prefix caching.
            // A cached checkpoint intentionally omits full selected histories.
            self.disable_recording();
        }
        if self.document_source.is_some() && first.ends.is_none() {
            first.ends = Some(History::default());
        }
        let mut active = vec![first];
        let mut accepted: Vec<Head> = vec![];
        let mut failures: Vec<Failure> = vec![];
        let mut forest = vec![];
        let mut repairs: Vec<Repair> = vec![];
        let mut first_stop = None;
        let mut skipped = 0;
        let mut spurned = 0;
        let mut next = Vec::new();
        loop {
            next.clear();
            let heads = active.len();
            for head in active.drain(..) {
                self.charge(1)?;
                match self.read_and_advance(
                    source,
                    head,
                    ScanScope::Document,
                    Boundary::Unprobed,
                )? {
                    Reading::Aside(head) => next.push(head),
                    Reading::Extra(mut head, token) => {
                        self.skip_extra(&mut head, token)?;
                        next.push(head);
                    }
                    Reading::Advanced(Advanced {
                        mut shifted,
                        accepted: won,
                        failures: refused,
                    }) => {
                        next.append(&mut shifted);
                        // Return only empty, small frontier storage. A large
                        // ambiguous frontier must not become retained scratch.
                        if shifted.capacity() <= 4 {
                            debug_assert!(self.shifted_scratch.is_empty());
                            self.shifted_scratch = shifted;
                        }
                        accepted.extend(won);
                        failures.extend(refused);
                    }
                }
                if next.len() + accepted.len() > self.limits.heads {
                    self.collapse(&mut next)?;
                    self.retain_acceptance(&mut accepted)?;
                    if next.len() + accepted.len() > self.limits.heads {
                        return Err(Error::LimitExceeded(Resource::Heads));
                    }
                }
            }
            self.collapse(&mut next)?;
            if next.len() + accepted.len() > self.limits.heads {
                self.retain_acceptance(&mut accepted)?;
                if next.len() + accepted.len() > self.limits.heads {
                    return Err(Error::LimitExceeded(Resource::Heads));
                }
            }
            if !next.is_empty() {
                // These heads were refuted; a later refusal concerns the
                // surviving configurations rather than an obsolete prefix.
                failures.clear();
                if next.len() == 1 && accepted.is_empty() && first_stop.is_none() {
                    self.checkpoint(&next[0])?;
                }
                std::mem::swap(&mut active, &mut next);
                continue;
            }
            if !accepted.is_empty() {
                let mut winner = accepted.remove(0);
                for other in accepted {
                    if self.compare_heads(&other, &winner)?.is_gt() {
                        winner = other;
                    }
                }
                let stop = first_stop.unwrap_or(Stop::Accepted);
                let tree = self.finish(source, winner, forest, stop, true, repairs, spurned)?;
                self.run = RunState::Complete;
                return Ok(tree);
            }
            let mut failed = failures
                .drain(..)
                .min_by(failure_order)
                .ok_or(Error::InvalidTable("no live or refused reading"))?;
            let fuse = skipped as u64 > source.len() as u64 * 3 / 4;
            if self.recovery != Recovery::None
                && !fuse
                && self.supply == Supply::UniqueLiteral
                && !failed.head.frames.is_empty()
            {
                if let Some(token) = failed.token {
                    let (choice, work) = recovery::insertion(
                        &self.grammar.automaton,
                        &failed.head.states,
                        token.symbol,
                    );
                    self.charge(work)?;
                    match choice {
                        Insertion::Unique(symbol) => {
                            let anchor = failed.head.last_end;
                            let shifted = failed.head.shifted;
                            let ghost = Lexeme {
                                symbol,
                                start: anchor,
                                end: anchor,
                                extra: false,
                            };
                            let Advanced {
                                shifted: mut planted,
                                accepted: won,
                                failures: refused,
                            } = self.advance(failed.head, Some(ghost), true)?;
                            if planted.len() != 1 || !won.is_empty() || !refused.is_empty() {
                                return Err(Error::InvalidTable("proved insertion did not shift"));
                            }
                            self.disable_recording();
                            first_stop.get_or_insert(failed.stop);
                            repairs.push(Repair {
                                span: span(anchor, anchor)?,
                                kind: RepairKind::Supplied { symbol },
                                context: failed.stop,
                                heads,
                                shifted,
                            });
                            let Advanced {
                                shifted: moved,
                                accepted: won,
                                failures: refused,
                            } = self.advance(planted.remove(0), Some(token), false)?;
                            active = moved;
                            accepted = won;
                            failures = refused;
                            if !active.is_empty() {
                                continue;
                            }
                            if !accepted.is_empty() {
                                continue;
                            }
                            // A proof/execution disagreement must never become a successful repair.
                            return Err(Error::InvalidTable(
                                "proved insertion did not resume the real token",
                            ));
                        }
                        Insertion::Ambiguous => spurned += 1,
                        Insertion::None | Insertion::Unknown(_) => {}
                    }
                }
            }
            let stop = first_stop.unwrap_or(failed.stop);
            let (from, over) = match failed.token {
                Some(token) => (token.start, token.end),
                None => match failed.stop {
                    Stop::Stray { at } => (at, word_end(source, at)),
                    _ => (failed.head.at, failed.head.at),
                },
            };
            if self.recovery == Recovery::None || fuse || over <= failed.head.at {
                let tree =
                    self.finish(source, failed.head, forest, stop, false, repairs, spurned)?;
                self.run = RunState::Complete;
                return Ok(tree);
            }
            let fell = self.recovery == Recovery::Fell
                || (self.recovery == Recovery::Relent && failed.head.kept);
            failed.head.slate = None;
            self.disable_recording();
            first_stop.get_or_insert(failed.stop);
            repairs.push(Repair {
                span: span(from, over)?,
                kind: RepairKind::Deleted { felled: fell },
                context: failed.stop,
                heads,
                shifted: failed.head.shifted,
            });
            skipped += over - from;
            if fell {
                forest.extend(self.unwind(&failed.head)?);
                let trace = std::mem::take(&mut failed.head.trace);
                let ends = failed.head.ends.take();
                let tokens = failed.head.tokens.take();
                let mut scanner = std::mem::take(&mut failed.head.scanner);
                scanner.reset();
                let shifted = failed.head.shifted;
                failed.head = Head::new(self.grammar.automaton.start_state(), over);
                failed.head.trace = trace;
                failed.head.ends = ends;
                failed.head.tokens = tokens;
                failed.head.scanner = scanner;
                failed.head.shifted = shifted;
            } else {
                failed.head.at = over;
                failed.head.kept = true;
            }
            self.charge(failed.head.record_work())?;
            failed.head.record(Move::Hole, over)?;
            active.push(failed.head);
        }
    }

    pub fn product(&self, store: &mut EffectStore) -> Result<Effect, EffectError> {
        if !matches!(self.run, RunState::Complete) {
            return Err(EffectError::UnfinishedRun);
        }
        if !Arc::ptr_eq(&self.grammar.automaton, store.automaton()) {
            return Err(EffectError::ForeignAutomaton);
        }
        let mut product = Effect::IDENTITY;
        for movement in &self.trace {
            let effect = match *movement {
                Move::Shift { from, symbol } => store.shift(from, symbol)?,
                Move::Reduce { under, production } => store.reduce(under, production)?,
                Move::Hole => Effect::ZERO,
            };
            product = store.compose(product, effect)?;
        }
        Ok(product)
    }

    /// Fold a checked range of the selected actual moves, excluding any moves
    /// outside it (notably EOF folds). The returned work is a conservative bill
    /// for construction, copied guards, path checks and interning, not a timer.
    /// Unlike an abstract survey yield, every generator here has singleton guards
    /// and a singleton live floor, which keeps this bill available without copies.
    pub fn product_range(
        &self,
        range: std::ops::Range<usize>,
        store: &mut EffectStore,
        work_limit: usize,
    ) -> Result<(Effect, usize), EffectError> {
        if !matches!(self.run, RunState::Complete) {
            return Err(EffectError::UnfinishedRun);
        }
        if !Arc::ptr_eq(&self.grammar.automaton, store.automaton()) {
            return Err(EffectError::ForeignAutomaton);
        }
        let moves = self
            .trace
            .get(range)
            .ok_or(EffectError::InvalidTraceRange)?;
        let mut remaining = work_limit;
        let mut bill = |work: usize| -> Result<(), EffectError> {
            remaining = remaining
                .checked_sub(work)
                .ok_or(EffectError::TraceWorkLimit)?;
            Ok(())
        };
        let log_symbols =
            (usize::BITS - self.grammar.automaton.symbol_count().max(1).leading_zeros()) as usize;
        let mut product = Effect::IDENTITY;
        let (mut debt, mut push) = (0usize, 0usize);
        for movement in moves {
            let pop = match movement {
                Move::Reduce { production, .. } => {
                    self.grammar.automaton.production(*production).steps.len()
                }
                _ => 0,
            };
            // Three payload entries cover a claim and its two singleton sets.
            // The factor covers owned copies plus both interning hash passes;
            // transition checks add a logarithmic grammar-map bound.
            let work = debt
                .saturating_add(push)
                .saturating_add(pop)
                .saturating_add(1)
                .saturating_mul(32)
                .saturating_add(
                    push.saturating_add(pop)
                        .saturating_mul(log_symbols.saturating_add(4)),
                );
            bill(work)?;
            let effect = match *movement {
                Move::Shift { from, symbol } => store.shift(from, symbol)?,
                Move::Reduce { under, production } => store.reduce(under, production)?,
                Move::Hole => Effect::ZERO,
            };
            product = store.compose(product, effect)?;
            if product.is_zero() {
                debt = 0;
                push = 0;
            } else {
                debt = debt.saturating_add(pop.saturating_sub(push));
                push = push.saturating_sub(pop).saturating_add(1);
            }
        }
        Ok((product, work_limit - remaining))
    }

    fn document_scan_inner(
        &mut self,
        source: &[u8],
        head: &mut Head,
        excluded: &Exclusions,
        prebuilt: Option<&AdmissionSlate>,
    ) -> Result<Option<Scanned>, Error> {
        let graph = Arc::clone(&self.grammar.automaton);
        let before = if graph.extra_entries().is_empty() {
            None
        } else {
            self.charge(head.scanner.clone_work())?;
            Some(head.scanner.clone())
        };
        let mut scanned = self.scan(source, head, ScanScope::Document, excluded, prebuilt)?;
        if let Scan::Token(first) = scanned.scan {
            if !first.extra && self.rule_extra(source, head, first)? {
                return Ok(None);
            }
            let auxiliary_start = graph.extra_entries().iter().any(|&(_, entry)| {
                !graph
                    .actions(entry, Lookahead::Terminal(first.symbol))
                    .is_empty()
            });
            if !first.extra && auxiliary_start {
                let (proof, work) = recovery::admission(&graph, &head.states, first.symbol);
                self.charge(work)?;
                self.charge(admissions::search_work(excluded.ordinary.len()))?;
                if matches!(proof, Proof::Stops)
                    || excluded.ordinary.binary_search(&first.symbol).is_ok()
                {
                    // A rejected extra may have opened scanner state. Retry the
                    // document's own slate from its exact pre-scan context.
                    head.scanner =
                        before.ok_or(Error::InvalidTable("missing scanner checkpoint"))?;
                    scanned = self.scan(source, head, ScanScope::Structural, excluded, prebuilt)?;
                    if let Scan::Token(token) = scanned.scan {
                        if !token.extra && self.rule_extra(source, head, token)? {
                            return Ok(None);
                        }
                    }
                }
            }
        }
        Ok(Some(scanned))
    }

    /// A rule extra is a separate LR reading over the same immutable grammar.
    /// Its scanner state commits only with a whole derivation; its moves never
    /// become structural parse moves or alter the document's stack.
    fn rule_extra(&mut self, source: &[u8], head: &mut Head, first: Lexeme) -> Result<bool, Error> {
        let graph = Arc::clone(&self.grammar.automaton);
        for &(symbol, entry) in graph.extra_entries() {
            if graph
                .actions(entry, Lookahead::Terminal(first.symbol))
                .is_empty()
            {
                continue;
            }
            let mut extra = Head::new(entry, first.start);
            self.charge(head.scanner.clone_work())?;
            extra.scanner = head.scanner.clone();
            extra.repaired = head.repaired;
            extra.fresh = head.fresh;
            extra.after_node = head.after_node;
            let Some(mut complete) = self.extra_reading(source, extra, first)? else {
                continue;
            };
            if complete.at <= head.at {
                return Err(Error::InvalidTable("rule extra did not advance source"));
            }
            if complete.frames.len() != 1 || complete.frames[0].symbol != symbol {
                return Err(Error::InvalidTable(
                    "extra entry accepted a different syntax root",
                ));
            }
            let frame = complete.frames.pop().unwrap();
            let visible = !frame.body.is_empty();
            for use_ in frame.body {
                let draft = &self.drafts[use_.draft];
                let (symbol, extent, count) = (draft.symbol, draft.span, draft.children.len());
                self.charge(count)?;
                let children = self.drafts[use_.draft].children.clone();
                let mut aside = self.mint(symbol, extent, children, true)?;
                aside.alias = use_.alias;
                aside.field = use_.field;
                head.pending.push(aside);
            }
            head.scanner = complete.scanner;
            head.at = complete.at;
            head.fresh = false;
            head.after_node = visible;
            return Ok(true);
        }
        Ok(false)
    }

    fn extra_reading(
        &mut self,
        source: &[u8],
        head: Head,
        first: Lexeme,
    ) -> Result<Option<Head>, Error> {
        let Advanced {
            shifted: mut active,
            ..
        } = self.advance(head, Some(first), false)?;
        let mut best: Option<Head> = None;
        while !active.is_empty() {
            let mut next = Vec::new();
            for head in active {
                self.charge(head.clone_work().saturating_add(1))?;
                let Advanced { accepted, .. } = self.advance(head.clone(), None, false)?;
                let completed = !accepted.is_empty();
                for accepted in accepted {
                    let replace = match &best {
                        None => true,
                        Some(old) => {
                            accepted.at > old.at
                                || (accepted.at == old.at
                                    && self.compare_heads(&accepted, old)?.is_gt())
                        }
                    };
                    if replace {
                        best = Some(accepted);
                    }
                }
                match self.read_and_advance(
                    source,
                    head,
                    ScanScope::Extra,
                    Boundary::Extra {
                        accepted: completed,
                    },
                )? {
                    Reading::Extra(mut head, token) => {
                        // Whitespace after a completed extra belongs to the
                        // surrounding document, never to the extra's extent.
                        if !completed {
                            self.skip_extra(&mut head, token)?;
                            next.push(head);
                        }
                    }
                    Reading::Advanced(Advanced { shifted, .. }) => next.extend(shifted),
                    Reading::Aside(_) => return Err(Error::InvalidTable("nested document extra")),
                }
                if next.len() > self.limits.heads {
                    self.collapse(&mut next)?;
                    if next.len() > self.limits.heads {
                        return Err(Error::LimitExceeded(Resource::Heads));
                    }
                }
            }
            self.collapse(&mut next)?;
            active = next;
        }
        Ok(best)
    }

    fn skip_extra(&mut self, head: &mut Head, token: Lexeme) -> Result<(), Error> {
        if self.grammar.automaton.symbol(token.symbol).shape.visible() {
            let node = self.mint(token.symbol, span(token.start, token.end)?, vec![], true)?;
            head.pending.push(node);
            head.after_node = true;
        } else {
            head.after_node = false;
        }
        head.at = token.end;
        head.fresh = false;
        Ok(())
    }

    fn charge(&mut self, amount: usize) -> Result<(), Error> {
        self.steps = self
            .steps
            .checked_add(amount)
            .ok_or(Error::LimitExceeded(Resource::Work))?;
        if self.steps > self.limits.steps {
            Err(Error::LimitExceeded(Resource::Work))
        } else {
            Ok(())
        }
    }

    fn scan(
        &mut self,
        source: &[u8],
        head: &mut Head,
        scope: ScanScope,
        excluded: &Exclusions,
        prebuilt: Option<&AdmissionSlate>,
    ) -> Result<Scanned, Error> {
        // A reading transaction's full pre-scan and restored heads have the
        // same structural stack. Borrow its already paid slate; cache replay
        // has no such owner and obtains its own exact-stack slate normally.
        let owned;
        let slate: &AdmissionSlate = match prebuilt {
            Some(slate) => slate,
            None => {
                owned = self.admission_slate(head)?;
                &owned
            }
        };
        let scan = self.scan_inner(source, head, scope, slate, excluded)?;
        let provisional = match scan {
            Scan::Token(token) => {
                self.token_reads = self
                    .token_reads
                    .checked_add(1)
                    .ok_or(Error::LimitExceeded(Resource::Work))?;
                if token.start < head.at || token.end < token.start || token.end > source.len() {
                    return Err(Error::InvalidTable(
                        "scanner returned an invalid source extent",
                    ));
                }
                self.charge(
                    admissions::search_work(slate.uncertain.len())
                        .saturating_add(admissions::search_work(excluded.ordinary.len())),
                )?;
                if !token.extra && excluded.ordinary.binary_search(&token.symbol).is_ok() {
                    return Err(Error::InvalidTable(
                        "scanner returned a rejected ordinary role",
                    ));
                }
                !token.extra && slate.uncertain.binary_search(&token.symbol).is_ok()
            }
            Scan::End => {
                scope != ScanScope::Extra
                    && !source.is_empty()
                    && head.at == source.len()
                    && !excluded.end
                    && (!slate.empty.is_empty() || !slate.provisional_empty.is_empty())
            }
            Scan::Stray { .. } => false,
        };
        if provisional && matches!(scan, Scan::Token(_)) {
            // A changed Unknown token must invalidate replay before any real
            // advancement. End is checked by actual acceptance first; replay
            // invalidates either provisional result in restore_prefix.
            self.disable_recording();
        }
        Ok(Scanned { scan, provisional })
    }

    fn scan_inner(
        &mut self,
        source: &[u8],
        head: &mut Head,
        scope: ScanScope,
        slate: &AdmissionSlate,
        excluded: &Exclusions,
    ) -> Result<Scan, Error> {
        #[cfg(all(test, feature = "munch-image"))]
        let _image_context = crate::lexer::working_image_trial::context(serde_json::json!({
            "stack": head.states.iter().map(|s| s.index()).collect::<Vec<_>>(),
            "scope": match scope { ScanScope::Document => "document", ScanScope::Structural => "structural", ScanScope::Extra => "extra" },
            "at": head.at, "fresh": head.fresh,
            "ordinary_exclusions": excluded.ordinary.iter().map(|s| s.index()).collect::<Vec<_>>(),
            "auxiliary_exclusions": excluded.auxiliary.iter().map(|s| s.index()).collect::<Vec<_>>(),
            "end_excluded": excluded.end,
            "retry_filtered": excluded.end || !excluded.ordinary.is_empty() || !excluded.auxiliary.is_empty(),
            "parser_steps": self.steps, "lexical_remaining": self.lexical_remaining,
        }));
        let graph = Arc::clone(&self.grammar.automaton);
        let state = *head
            .states
            .last()
            .ok_or(Error::InvalidTable("empty state stack"))?;
        let filtered = self.filtered_admissions(slate, scope, excluded)?;
        let (base_lexical, base_wanted) = slate.view(scope);
        let (ordinary, lexical, wanted, empty, provisional_empty) = match &filtered {
            Some(view) => (
                &view.ordinary[..],
                &view.lexical[..],
                &view.wanted[..],
                &view.empty[..],
                &view.provisional_empty[..],
            ),
            None => (
                &slate.ordinary[..],
                base_lexical,
                base_wanted,
                &slate.empty[..],
                &slate.provisional_empty[..],
            ),
        };
        if self.grammar.program.is_some() {
            if let Some(hit) =
                self.program_scan(source, head, head.at, wanted, lexical, false, scope)?
            {
                self.charge(
                    admissions::search_work(slate.extras.len())
                        .saturating_add(admissions::search_work(slate.ordinary.len())),
                )?;
                return Ok(Scan::Token(Lexeme {
                    symbol: hit.symbol,
                    start: hit.start,
                    end: hit.end,
                    extra: slate.extras.binary_search(&hit.symbol).is_ok()
                        && ordinary.binary_search(&hit.symbol).is_err(),
                }));
            }
        }
        #[cfg(all(test, feature = "munch-image"))]
        let _image_filtered = crate::lexer::working_image_trial::call_site("filtered");
        let scanned = self.lexical_scan(
            source,
            head.at,
            crate::lexer::LexicalQuestion {
                admitted: Some(lexical),
                empty_permit: empty,
                provisional_empty,
                // End wins the first ordinary election. A provisional End
                // must actually accept; a failed one leaves zero candidates
                // eligible on the restored head, without inventing permission.
                eof: slate.eof && !excluded.end,
            },
            head.fresh,
            scope,
        )?;
        if let Scan::Stray { at } = scanned {
            if self.grammar.program.is_some() {
                if let Some(hit) =
                    self.program_scan(source, head, at, wanted, lexical, true, scope)?
                {
                    self.charge(
                        admissions::search_work(slate.extras.len())
                            .saturating_add(admissions::search_work(slate.ordinary.len())),
                    )?;
                    return Ok(Scan::Token(Lexeme {
                        symbol: hit.symbol,
                        start: hit.start,
                        end: hit.end,
                        extra: slate.extras.binary_search(&hit.symbol).is_ok()
                            && ordinary.binary_search(&hit.symbol).is_err(),
                    }));
                }
            }
            if scope == ScanScope::Extra {
                return Ok(scanned);
            }
            let raw_ids = if excluded.ordinary.is_empty() {
                Cow::Borrowed(graph.row_admissions(state))
            } else {
                Cow::Owned(self.slate_without(graph.row_admissions(state), &excluded.ordinary)?)
            };
            #[cfg(all(test, feature = "munch-image"))]
            let _image_raw = crate::lexer::working_image_trial::call_site("raw-row-diagnostic");
            let raw = self.lexical_scan(
                source,
                at,
                crate::lexer::LexicalQuestion::positive(Some(&raw_ids)),
                head.fresh,
                scope,
            )?;
            if matches!(raw, Scan::Token(_)) {
                return Ok(raw);
            }
            #[cfg(all(test, feature = "munch-image"))]
            let _image_diagnostic =
                crate::lexer::working_image_trial::call_site("unrestricted-diagnostic");
            let diagnostic = self.lexical_scan(
                source,
                at,
                crate::lexer::LexicalQuestion::positive(None),
                head.fresh,
                scope,
            )?;
            self.charge(admissions::search_work(excluded.ordinary.len()))?;
            return Ok(match diagnostic {
                Scan::Token(token)
                    if !token.extra && excluded.ordinary.binary_search(&token.symbol).is_ok() =>
                {
                    Scan::Stray { at }
                }
                other => other,
            });
        }
        Ok(scanned)
    }

    fn read_and_advance(
        &mut self,
        source: &[u8],
        mut head: Head,
        scope: ScanScope,
        boundary: Boundary,
    ) -> Result<Reading, Error> {
        let slate = self.admission_slate(&mut head)?;
        let possible = !slate.uncertain.is_empty()
            || (!source.is_empty()
                && head.at == source.len()
                && (!slate.empty.is_empty() || !slate.provisional_empty.is_empty()));
        let original = if possible {
            self.charge(head.clone_work())?;
            Some(head.clone())
        } else {
            None
        };
        let mut excluded = Exclusions::default();
        // The auxiliary reader already executed End once on this actual head.
        // At EOF a failed boundary leaves ordinary zero eligible; non-EOF
        // completion never suppresses a farther ordinary token.
        if matches!(boundary, Boundary::Extra { accepted: false }) && head.at == source.len() {
            excluded.end = true;
        }
        let mut first_failure: Option<Failure> = None;
        loop {
            let scanned = if scope == ScanScope::Document {
                self.document_scan(source, &mut head, &excluded, Some(&slate))?
            } else {
                Some(self.scan(source, &mut head, scope, &excluded, Some(&slate))?)
            };
            let Some(scanned) = scanned else {
                return Ok(Reading::Aside(head));
            };
            match scanned.scan {
                Scan::Token(token) if token.extra => return Ok(Reading::Extra(head, token)),
                Scan::Stray { at } => {
                    let failed = first_failure.unwrap_or(Failure {
                        head,
                        stop: Stop::Stray { at },
                        token: None,
                    });
                    return Ok(Reading::Advanced(Advanced {
                        shifted: vec![],
                        accepted: vec![],
                        failures: vec![failed],
                    }));
                }
                Scan::End if matches!(boundary, Boundary::Extra { .. }) => {
                    // Existing best already owns the actual accepted boundary.
                    return Ok(Reading::Advanced(Advanced {
                        shifted: vec![],
                        accepted: vec![],
                        failures: vec![],
                    }));
                }
                Scan::End if excluded.end => {
                    let failed =
                        first_failure.ok_or(Error::InvalidTable("missing rejected End reading"))?;
                    return Ok(Reading::Advanced(Advanced {
                        shifted: vec![],
                        accepted: vec![],
                        failures: vec![failed],
                    }));
                }
                _ => {}
            }
            let token = match scanned.scan {
                Scan::Token(token) => Some(token),
                _ => None,
            };
            let advanced = self.advance(head, token, false)?;
            if !advanced.shifted.is_empty() || !advanced.accepted.is_empty() {
                // Use the actual branches, histories and token receipts once.
                return Ok(Reading::Advanced(advanced));
            }
            if !scanned.provisional {
                return Ok(Reading::Advanced(match first_failure {
                    None => advanced,
                    Some(failed) => Advanced {
                        shifted: vec![],
                        accepted: vec![],
                        failures: vec![failed],
                    },
                }));
            }
            let failed =
                advanced
                    .failures
                    .into_iter()
                    .min_by(failure_order)
                    .ok_or(Error::InvalidTable(
                        "no live or refused provisional reading",
                    ))?;
            if token.is_none() {
                // A real successful End preserves deterministic recording.
                // Only this failed End needs an unrecorded restored retry.
                self.disable_recording();
            }
            if first_failure.is_none() {
                first_failure = Some(failed);
            }
            if let Some(token) = token {
                self.reject_role(&mut excluded.ordinary, token.symbol)?;
                if scope == ScanScope::Document {
                    // document_scan tried every matching auxiliary entry and
                    // returned this token only after none accepted a whole extra.
                    self.reject_role(&mut excluded.auxiliary, token.symbol)?;
                }
            } else {
                excluded.end = true;
            }
            let original = original
                .as_ref()
                .ok_or(Error::InvalidTable("missing pre-scan head"))?;
            self.charge(original.clone_work())?;
            head = original.clone();
        }
    }

    fn reject_role(&mut self, ids: &mut Vec<SymbolId>, symbol: SymbolId) -> Result<(), Error> {
        self.charge(admissions::search_work(ids.len()))?;
        let at = ids
            .binary_search(&symbol)
            .err()
            .ok_or(Error::InvalidTable("repeated rejected ordinary role"))?;
        self.charge(ids.len().saturating_mul(2).saturating_add(1))?;
        ids.insert(at, symbol);
        Ok(())
    }

    fn advance(
        &mut self,
        head: Head,
        token: Option<Lexeme>,
        supplied: bool,
    ) -> Result<Advanced, Error> {
        let observation = if head.tokens.is_some() && token.is_some() {
            Some((
                *head
                    .states
                    .last()
                    .ok_or(Error::InvalidTable("empty observed state stack"))?,
                head.trace.len(),
            ))
        } else {
            None
        };
        let graph = Arc::clone(&self.grammar.automaton);
        let lookahead = token.map_or(Lookahead::End, |t| Lookahead::Terminal(t.symbol));
        // Forks retain birth order. Canonical derivations arbitrate declared
        // ties; only structurally equal final ties retain the later reading,
        // so a depth-first queue would still change that fallback.
        // Deterministic reads need no queue allocation. Alternatives still
        // enter the same FIFO after the first head has been removed.
        let mut first = Some((head, None));
        let mut queue = VecDeque::new();
        let mut moved = std::mem::take(&mut self.shifted_scratch);
        debug_assert!(moved.is_empty());
        let (mut accepted, mut failures) = (vec![], vec![]);
        while let Some((mut head, mut forced)) = first.take().or_else(|| queue.pop_front()) {
            loop {
                self.charge(1)?;
                let state = *head
                    .states
                    .last()
                    .ok_or(Error::InvalidTable("empty state stack"))?;
                let action = if let Some(action) = forced.take() {
                    Some(action)
                } else {
                    let actions = self.action_order(&head, graph.actions(state, lookahead))?;
                    let declared = actions.len() > 1 && self.declared_choice(state, lookahead)?;
                    if actions.len() > 1 {
                        self.disable_recording();
                    }
                    head.declared |= declared;
                    for (index, &action) in actions.iter().enumerate().skip(1) {
                        if supplied {
                            return Err(Error::InvalidTable(
                                "insertion reached an unresolved alternative",
                            ));
                        }
                        if queue.len() + moved.len() + accepted.len() + 1 >= self.limits.heads {
                            self.collapse(&mut moved)?;
                            self.retain_acceptance(&mut accepted)?;
                            if queue.len() + moved.len() + accepted.len() + 1 >= self.limits.heads {
                                return Err(Error::LimitExceeded(Resource::Heads));
                            }
                        }
                        let birth = u64::try_from(index)
                            .map_err(|_| Error::LimitExceeded(Resource::Heads))?;
                        self.charge(head.clone_work())?;
                        let mut branch = head.clone();
                        branch.rank = branch
                            .rank
                            .checked_add(if declared { 0 } else { birth })
                            .ok_or(Error::LimitExceeded(Resource::Heads))?;
                        branch.birth = branch
                            .birth
                            .checked_add(birth)
                            .ok_or(Error::LimitExceeded(Resource::Heads))?;
                        queue.push_back((branch, Some(action)));
                    }
                    actions.first().copied()
                };
                match action {
                    Some(Action::Shift(to)) => {
                        let token = token.ok_or(Error::InvalidTable("shift at EOF"))?;
                        self.shift(&mut head, token, state, to, supplied)?;
                        if let Some((entry, begin)) = observation {
                            self.charge(1)?;
                            let receipt = ParsedToken {
                                symbol: token.symbol,
                                span: span(token.start, token.end)?,
                                entry,
                                from: state,
                                supplied,
                                moves: begin..head.trace.len(),
                            };
                            head.tokens
                                .as_mut()
                                .ok_or(Error::InvalidTable("missing selected-token observer"))?
                                .push(receipt);
                        }
                        moved.push(head);
                        break;
                    }
                    Some(Action::Reduce(production)) => self.reduce(&mut head, production)?,
                    Some(Action::Accept) if token.is_none() => {
                        accepted.push(head);
                        break;
                    }
                    Some(Action::Accept) => return Err(Error::InvalidTable("accept before EOF")),
                    None => {
                        let stop = token.map_or(Stop::Truncated, |t| Stop::Unexpected {
                            symbol: t.symbol,
                            at: t.start,
                            state,
                        });
                        failures.push(Failure { head, stop, token });
                        break;
                    }
                }
            }
        }
        Ok(Advanced {
            shifted: moved,
            accepted,
            failures,
        })
    }

    fn collapse(&mut self, heads: &mut Vec<Head>) -> Result<(), Error> {
        if heads.len() < 2 {
            return Ok(());
        }
        let mut kept: Vec<Head> = vec![];
        for head in heads.drain(..) {
            if let Some(previous) = kept.iter_mut().find(|old| old.twins(&head)) {
                if !self.compare_heads(&head, previous)?.is_lt() {
                    *previous = head;
                }
            } else {
                kept.push(head);
            }
        }
        *heads = kept;
        Ok(())
    }

    // A completed reading has no future transitions. Preserve the same
    // representative the final comparison would choose, including its
    // incumbent-wins exact tie, while other readings are still progressing.
    fn retain_acceptance(&mut self, heads: &mut Vec<Head>) -> Result<(), Error> {
        if heads.len() < 2 {
            return Ok(());
        }
        let mut winner: Option<Head> = None;
        for head in heads.drain(..) {
            if let Some(old) = &winner {
                if !self.compare_heads(&head, old)?.is_gt() {
                    continue;
                }
            }
            winner = Some(head);
        }
        heads.push(winner.unwrap());
        Ok(())
    }

    fn shift(
        &mut self,
        head: &mut Head,
        token: Lexeme,
        from: StateId,
        to: StateId,
        supplied: bool,
    ) -> Result<(), Error> {
        head.repaired |= supplied;
        if head.frames.len() >= self.limits.stack {
            return Err(Error::LimitExceeded(Resource::Stack));
        }
        let extent = span(token.start, token.end)?;
        let body = if self.grammar.automaton.symbol(token.symbol).shape.visible() {
            vec![self.mint(token.symbol, extent, vec![], false)?]
        } else {
            vec![]
        };
        head.frames.push(Frame {
            symbol: token.symbol,
            span: extent,
            lead: if supplied {
                vec![]
            } else {
                std::mem::take(&mut head.pending)
            },
            body,
            unproven: supplied,
        });
        head.slate = None;
        head.states.push(to);
        self.charge(head.record_work())?;
        head.record(
            Move::Shift {
                from,
                symbol: token.symbol,
            },
            if supplied { head.last_end } else { token.end },
        )?;
        head.shifted += 1;
        if !supplied {
            head.at = token.end;
            head.last_end = token.end;
            head.fresh = true;
            head.after_node = false;
            head.kept = false;
        }
        Ok(())
    }

    fn concrete_production(
        &mut self,
        head: &Head,
        family: ReductionId,
    ) -> Result<ProductionId, Error> {
        let graph = Arc::clone(&self.grammar.automaton);
        if family.index() >= graph.reduction_count() {
            return Err(Error::InvalidTable("invalid reduction family"));
        }
        let reduction = graph.reduction(family);
        let count = reduction.width;
        let start = head
            .frames
            .len()
            .checked_sub(count)
            .ok_or(Error::InvalidTable("reduction underflow"))?;
        let mut selected = None;
        for &id in &reduction.productions {
            self.charge(count + 1)?;
            let production = graph.production(id);
            if production.steps.len() == count
                && production
                    .steps
                    .iter()
                    .zip(&head.frames[start..])
                    .all(|(step, frame)| step.symbol == frame.symbol)
            {
                selected = Some(id);
                break;
            }
        }
        let id = selected.ok_or(Error::InvalidTable(
            "no concrete reduction matches the actual stack",
        ))?;
        let rule = graph.production(id);
        if rule.lhs != reduction.lhs || rule.dynamic_precedence != reduction.dynamic_precedence {
            return Err(Error::InvalidTable("inconsistent concrete reduction"));
        }
        Ok(id)
    }

    fn action_order<'a>(
        &mut self,
        head: &Head,
        actions: &'a [Action],
    ) -> Result<Cow<'a, [Action]>, Error> {
        if actions
            .iter()
            .filter(|a| matches!(a, Action::Reduce(_)))
            .count()
            < 2
        {
            return Ok(Cow::Borrowed(actions));
        }
        let graph = Arc::clone(&self.grammar.automaton);
        let mut reductions = Vec::new();
        for &action in actions {
            if let Action::Reduce(family) = action {
                let production = self.concrete_production(head, family)?;
                reductions.push((
                    (
                        std::cmp::Reverse(graph.reduction(family).dynamic_precedence),
                        production,
                    ),
                    action,
                ));
            }
        }
        reductions.sort_by_key(|&(key, _)| key);
        let mut reductions = reductions.into_iter();
        let mut ordered = actions.to_vec();
        for action in &mut ordered {
            if matches!(action, Action::Reduce(_)) {
                *action = reductions.next().unwrap().1;
            }
        }
        Ok(Cow::Owned(ordered))
    }

    fn reduce(&mut self, head: &mut Head, family: ReductionId) -> Result<(), Error> {
        let graph = Arc::clone(&self.grammar.automaton);
        let id = self.concrete_production(head, family)?;
        let rule = graph.production(id);
        let count = rule.steps.len();
        self.charge(count)?;
        if head.states.len() <= count {
            return Err(Error::InvalidTable("reduction state underflow"));
        }
        let frames = head.frames.drain(head.frames.len() - count..);
        head.slate = None;
        head.states.truncate(head.states.len() - count);
        let under = *head
            .states
            .last()
            .ok_or(Error::InvalidTable("missing reduction floor"))?;
        let to = graph
            .transition(under, rule.lhs)
            .ok_or(Error::InvalidTable("missing reduction goto"))?;
        let mut extent: Option<ByteSpan> = None;
        let (mut body, mut lead) = (vec![], vec![]);
        for (index, (mut frame, step)) in frames.into_iter().zip(&rule.steps).enumerate() {
            if frame.symbol != step.symbol {
                return Err(Error::InvalidTable("reduction symbol mismatch"));
            }
            if !frame.span.is_empty() || graph.symbol(frame.symbol).lexis.is_some() {
                extent = Some(extent.map_or(frame.span, |old| old.covering(frame.span)));
            }
            if index == 0 {
                lead = frame.lead;
            } else {
                self.charge(frame.lead.len())?;
                body.extend(frame.lead);
            }
            if step.alias.is_some() {
                if graph.symbol(frame.symbol).shape.visible() && frame.body.len() == 1 {
                    frame.body[0].alias = Some((id, index));
                } else {
                    let mut wrapper = self.mint(step.symbol, frame.span, frame.body, false)?;
                    wrapper.alias = Some((id, index));
                    frame.body = vec![wrapper];
                }
            }
            if let Some(field) = step.field {
                self.charge(frame.body.len())?;
                for child in &mut frame.body {
                    if !self.drafts[child.draft].extra {
                        child.field.get_or_insert(field);
                    }
                }
            }
            if index == 0 {
                body = frame.body;
            } else {
                self.charge(frame.body.len())?;
                body.extend(frame.body);
            }
        }
        if let Some(first) = body.first() {
            let child = self.drafts[first.draft].span;
            extent = Some(extent.map_or(child, |old| old.covering(child)));
        }
        if let Some(last) = body.last() {
            let child = self.drafts[last.draft].span;
            extent = Some(extent.map_or(child, |old| old.covering(child)));
        }
        let extent = extent.unwrap_or(span(head.last_end, head.last_end)?);
        if graph.symbol(rule.lhs).shape.visible() {
            body = vec![self.mint(rule.lhs, extent, body, false)?];
        }
        if head.frames.len() >= self.limits.stack {
            return Err(Error::LimitExceeded(Resource::Stack));
        }
        head.frames.push(Frame {
            symbol: rule.lhs,
            span: extent,
            lead,
            body,
            unproven: false,
        });
        head.states.push(to);
        self.charge(head.record_work())?;
        head.record(
            Move::Reduce {
                under,
                production: id,
            },
            head.last_end,
        )?;
        head.dynamic = head
            .dynamic
            .checked_add(i64::from(rule.dynamic_precedence))
            .ok_or(Error::LimitExceeded(Resource::Work))?;
        Ok(())
    }

    fn mint(
        &mut self,
        symbol: SymbolId,
        extent: ByteSpan,
        children: Vec<Use>,
        extra: bool,
    ) -> Result<Use, Error> {
        if self.drafts.len() >= self.limits.nodes.min(u32::MAX as usize) {
            return Err(Error::LimitExceeded(Resource::Nodes));
        }
        self.charge(children.len() + 1)?;
        let draft = self.drafts.len();
        self.drafts.push(Draft {
            symbol,
            span: extent,
            children,
            extra,
        });
        Ok(Use {
            draft,
            alias: None,
            field: None,
        })
    }

    fn unwind(&mut self, head: &Head) -> Result<Vec<Use>, Error> {
        let mut roots = vec![];
        let mut proven = true;
        for frame in &head.frames {
            self.charge(frame.lead.len().saturating_add(1))?;
            roots.extend_from_slice(&frame.lead);
            proven &= !frame.unproven;
            if proven {
                self.charge(frame.body.len())?;
                roots.extend_from_slice(&frame.body);
            }
        }
        self.charge(head.pending.len())?;
        roots.extend_from_slice(&head.pending);
        Ok(roots)
    }

    #[allow(clippy::too_many_arguments)]
    fn finish(
        &mut self,
        source: &[u8],
        head: Head,
        mut forest: Vec<Use>,
        stop: Stop,
        accepted: bool,
        repairs: Vec<Repair>,
        spurned: usize,
    ) -> Result<TreeSnapshot, Error> {
        let mends = repairs
            .iter()
            .filter(|r| matches!(r.kind, RepairKind::Deleted { .. }))
            .count();
        if accepted
            && (head.frames.len() != 1
                || head.frames[0].symbol != self.grammar.automaton.start_symbol())
        {
            return Err(Error::InvalidTable(
                "accepted stack does not contain the start symbol",
            ));
        }
        if accepted
            && mends == 0
            && head.frames[0].body.len() == 1
            && self
                .grammar
                .automaton
                .symbol(head.frames[0].symbol)
                .shape
                .visible()
        {
            let frame = &head.frames[0];
            let root = frame.body[0];
            let draft = &self.drafts[root.draft];
            let symbol = draft.symbol;
            self.charge(
                frame
                    .lead
                    .len()
                    .saturating_add(draft.children.len())
                    .saturating_add(head.pending.len()),
            )?;
            let children: Vec<_> = frame
                .lead
                .iter()
                .chain(&self.drafts[root.draft].children)
                .chain(&head.pending)
                .copied()
                .collect();
            let mut from = if frame.span.is_empty() {
                source.len()
            } else {
                frame.span.start()
            };
            if let Some(first) = children.first() {
                from = from.min(self.drafts[first.draft].span.start());
            }
            forest.push(self.mint(symbol, span(from, source.len())?, children, false)?);
        } else {
            forest.extend(self.unwind(&head)?);
        }
        self.charge(
            head.trace
                .materialize_work()
                .saturating_add(head.ends.as_ref().map_or(0, History::materialize_work)),
        )?;
        self.ends = head.ends.map(History::into_vec).unwrap_or_default();
        self.tokens = head.tokens;
        self.trace = head.trace.into_vec();
        let Materialized {
            nodes,
            children,
            roots,
        } = self.materialize(&forest)?;
        let mut lines = vec![0];
        lines.extend(
            source
                .iter()
                .enumerate()
                .filter_map(|(i, &b)| (b == b'\n').then_some(i + 1)),
        );
        let mut tree = TreeSnapshot {
            grammar: Arc::clone(&self.grammar),
            source: self
                .document_source
                .as_ref()
                .cloned()
                .unwrap_or_else(|| Arc::from(source)),
            nodes,
            children,
            roots,
            stop,
            lines,
            survey: Survey::default(),
            repairs,
            spurned,
        };
        tree.survey = tree.measure();
        Ok(tree)
    }

    fn materialize(&mut self, forest: &[Use]) -> Result<Materialized, Error> {
        enum Slot {
            Root(usize),
            Child(usize),
        }
        let mut nodes = Vec::<NodeData>::new();
        let mut children = vec![];
        let mut roots = vec![NodeId(0); forest.len()];
        let mut pending: Vec<_> = forest
            .iter()
            .copied()
            .enumerate()
            .rev()
            .map(|(i, node)| (node, None, Slot::Root(i)))
            .collect();
        while let Some((node, parent, slot)) = pending.pop() {
            if nodes.len() >= self.limits.nodes.min(u32::MAX as usize) {
                return Err(Error::LimitExceeded(Resource::Nodes));
            }
            self.charge(1)?;
            let draft = &self.drafts[node.draft];
            let id = NodeId(nodes.len() as u32);
            match slot {
                Slot::Root(i) => roots[i] = id,
                Slot::Child(i) => children[i] = id,
            }
            let start = children.len();
            children.resize(start + draft.children.len(), NodeId(0));
            nodes.push(NodeData {
                symbol: draft.symbol,
                alias: node.alias,
                span: draft.span,
                field: node.field,
                parent,
                children: start..children.len(),
                extra: draft.extra,
            });
            for (i, child) in draft.children.iter().copied().enumerate().rev() {
                pending.push((child, Some(id), Slot::Child(start + i)));
            }
        }
        Ok(Materialized {
            nodes,
            children,
            roots,
        })
    }
}
fn span(start: usize, end: usize) -> Result<ByteSpan, Error> {
    ByteSpan::new(start, end).ok_or(Error::InvalidTable("invalid source span"))
}
fn word_end(source: &[u8], at: usize) -> usize {
    let ident = |b: u8| b == b'_' || b.is_ascii_alphanumeric();
    let mut end = at.saturating_add(1).min(source.len());
    if source.get(at).is_some_and(|&b| ident(b)) {
        while end < source.len() && ident(source[end]) {
            end += 1;
        }
    }
    end
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_fork_shares_both_history_prefixes_without_changing_their_move_ordinals() {
        let make = |len| {
            let mut head = Head::new(StateId::from_index(0), 0);
            head.trace = History::from_vec(vec![Move::Hole; len]);
            head.ends = Some(History::from_vec((0..len).collect()));
            head
        };
        let small = make(64);
        let original = make(64 * 1024);
        assert_eq!(small.clone_work(), original.clone_work());
        assert_eq!(
            original.clone_without_history_work(),
            small.clone_without_history_work()
        );
        let mut fork = original.clone();
        fork.record(Move::Hole, 64 * 1024 + 9).unwrap();
        fork.record(Move::Hole, 3).unwrap();
        assert_eq!(original.trace.len(), 64 * 1024);
        assert_eq!(
            original.ends.as_ref().unwrap().last(),
            Some(&(64 * 1024 - 1))
        );
        assert_eq!(fork.trace.len(), 64 * 1024 + 2);
        let ends = fork.ends.unwrap().into_vec();
        assert_eq!(ends.len(), fork.trace.len());
        assert_eq!(&ends[..64 * 1024], &(0..64 * 1024).collect::<Vec<_>>());
        assert_eq!(&ends[64 * 1024..], &[64 * 1024 + 9, 64 * 1024 + 9]);
    }

    #[test]
    fn named_extras_are_billed_when_a_fork_copies_their_pending_tree_uses() {
        let mut source: serde_json::Value = serde_json::from_str(
            r##"{"name":"extra_fork","rules":{
          "doc":{"type":"CHOICE","members":[
            {"type":"SEQ","members":[{"type":"SYMBOL","name":"a"},{"type":"STRING","value":"x"}]},
            {"type":"SEQ","members":[{"type":"SYMBOL","name":"b"},{"type":"STRING","value":"x"}]},
            {"type":"SEQ","members":[{"type":"SYMBOL","name":"c"},{"type":"STRING","value":"x"}]},
            {"type":"SEQ","members":[{"type":"SYMBOL","name":"d"},{"type":"STRING","value":"x"}]}]},
          "a":{"type":"SYMBOL","name":"item"},"b":{"type":"SYMBOL","name":"item"},
          "c":{"type":"SYMBOL","name":"item"},"d":{"type":"SYMBOL","name":"item"},
          "item":{"type":"PATTERN","value":"g"},"comment":{"type":"PATTERN","value":"#"}},
          "extras":[{"type":"SYMBOL","name":"comment"}],"conflicts":[["a","b","c","d"]]}"##,
        )
        .unwrap();
        let forked = CompiledGrammar::compile(&serde_json::to_vec(&source).unwrap()).unwrap();
        source["rules"]["doc"] = serde_json::json!({"type":"SEQ","members":[
            {"type":"SYMBOL","name":"a"},{"type":"STRING","value":"x"}]});
        source["conflicts"] = serde_json::json!([]);
        let control = CompiledGrammar::compile(&serde_json::to_vec(&source).unwrap()).unwrap();
        let count = 2048;
        let input = format!("{}gx", "#".repeat(count));
        let mut baseline = control.session();
        assert!(
            baseline
                .parse(input.as_bytes())
                .unwrap()
                .survey()
                .is_sound()
        );
        let budget = baseline.steps + count * 2;
        let mut limited = ParseSession::with_limits(
            forked.clone(),
            ParseLimits {
                steps: budget,
                ..ParseLimits::default()
            },
        );
        assert!(matches!(
            limited.parse(input.as_bytes()),
            Err(Error::LimitExceeded(Resource::Work))
        ));
        assert!(matches!(
            limited.product(&mut forked.effect_store()),
            Err(EffectError::UnfinishedRun)
        ));
        let full = forked.session().parse(input.as_bytes()).unwrap();
        assert!(full.survey().is_sound());
        assert_eq!(
            full.root()
                .unwrap()
                .children()
                .filter(|n| n.name() == "comment")
                .count(),
            count
        );
    }

    #[test]
    fn hidden_splices_keep_the_nearest_field_and_visible_wrappers_take_the_outer_field() {
        let grammar = CompiledGrammar::compile(
            br#"{"name":"nearest_field","rules":{
          "doc":{"type":"SEQ","members":[
            {"type":"FIELD","name":"outer","content":{"type":"SYMBOL","name":"_hidden"}},
            {"type":"STRING","value":"!"},
            {"type":"FIELD","name":"outside","content":{"type":"SYMBOL","name":"visible"}}]},
          "_hidden":{"type":"FIELD","name":"inner","content":{"type":"SYMBOL","name":"first"}},
          "visible":{"type":"FIELD","name":"inside","content":{"type":"SYMBOL","name":"second"}},
          "first":{"type":"PATTERN","value":"x"},"second":{"type":"PATTERN","value":"y"}}}"#,
        )
        .unwrap();
        let tree = grammar.session().parse(b"x!y").unwrap();
        let root = tree.root().unwrap();
        let first = root.child_by_field("inner").unwrap();
        assert_eq!(first.name(), "first");
        assert!(root.child_by_field("outer").is_none());
        let visible = root.child_by_field("outside").unwrap();
        assert_eq!(visible.name(), "visible");
        assert_eq!(visible.child_by_field("inside").unwrap().name(), "second");
        assert!(tree.survey().is_sound());
    }

    #[test]
    fn a_reduction_family_cannot_invent_a_consumed_symbol_history() {
        let grammar =
            CompiledGrammar::compile(include_bytes!("../tests/fixtures/cursor-histories.json"))
                .unwrap();
        let graph = &grammar.automaton;
        let impossible = graph.symbol_by_name("doc").unwrap();
        let family = (0..graph.reduction_count())
            .map(ReductionId::from_index)
            .find(|&id| {
                let family = graph.reduction(id);
                family.width > 0
                    && family.productions.iter().all(|&id| {
                        !graph
                            .production(id)
                            .steps
                            .iter()
                            .all(|step| step.symbol == impossible)
                    })
            })
            .unwrap();
        let width = graph.reduction(family).width;
        let mut head = Head::new(graph.start_state(), 0);
        for _ in 0..width {
            head.frames.push(Frame {
                symbol: impossible,
                span: span(0, 0).unwrap(),
                lead: vec![],
                body: vec![],
                unproven: false,
            });
            head.states.push(graph.start_state());
        }
        let mut session = grammar.session();
        assert!(matches!(
            session.reduce(&mut head, family),
            Err(Error::InvalidTable(
                "no concrete reduction matches the actual stack"
            ))
        ));
        assert!(head.trace.is_empty());
        assert_eq!(head.frames.len(), width);
        assert!(matches!(
            session.reduce(
                &mut head,
                ReductionId::from_index(grammar.automaton.reduction_count())
            ),
            Err(Error::InvalidTable("invalid reduction family"))
        ));
    }

    #[test]
    fn cursor_family_traces_use_the_concrete_guarded_production_at_every_cut() {
        let grammar =
            CompiledGrammar::compile(include_bytes!("../tests/fixtures/cursor-histories.json"))
                .unwrap();
        let parent = grammar.automaton.symbol_by_name("parent").unwrap();
        for (source, name) in [
            (b"aAz=".as_slice(), "A"),
            (b"aBz=", "B"),
            (b"bAz==", "A"),
            (b"bBz==", "B"),
        ] {
            let mut session = grammar.session();
            session.parse(source).unwrap();
            let expected = grammar.automaton.symbol_by_name(name).unwrap();
            assert!(session.trace.iter().any(|movement| {
                if let Move::Reduce { production, .. } = movement {
                    let rule = grammar.automaton.production(*production);
                    rule.lhs == parent && rule.steps[0].symbol == expected
                } else {
                    false
                }
            }));
            let mut store = grammar.effect_store();
            let effects: Vec<_> = session
                .trace
                .iter()
                .map(|movement| match *movement {
                    Move::Shift { from, symbol } => store.shift(from, symbol).unwrap(),
                    Move::Reduce { under, production } => store.reduce(under, production).unwrap(),
                    Move::Hole => panic!("strict parse has no deleted input"),
                })
                .collect();
            let whole = store.fold(effects.iter().copied()).unwrap();
            assert!(store.grounded(whole).unwrap());
            assert!(!whole.is_zero());
            for cut in 0..=effects.len() {
                let left = store.fold(effects[..cut].iter().copied()).unwrap();
                let right = store.fold(effects[cut..].iter().copied()).unwrap();
                assert_eq!(store.compose(left, right).unwrap(), whole);
            }
        }
    }

    #[test]
    fn flat_list_tree_work_scales_with_input_instead_of_accumulated_children() {
        let grammar =
            CompiledGrammar::compile(include_bytes!("../../test/grammar/json.json")).unwrap();
        let mut session = grammar.session();
        let mut work = Vec::new();
        for count in [4096, 8192] {
            let input = format!("[{}]", vec!["1"; count].join(","));
            let tree = session.parse(input.as_bytes()).unwrap();
            assert_eq!(
                tree.root()
                    .unwrap()
                    .children()
                    .next()
                    .unwrap()
                    .children()
                    .filter(|n| n.name() == "number")
                    .count(),
                count
            );
            work.push(session.steps);
        }
        assert!(
            work[1] <= work[0] * 21 / 10,
            "node construction work: {work:?}"
        );
    }

    #[test]
    fn every_cut_of_the_actual_json_move_trace_has_the_same_product() {
        let grammar =
            CompiledGrammar::compile(include_bytes!("../../test/grammar/json.json")).unwrap();
        let mut session = grammar.session();
        session.parse(b"{\"x\":[1,{\"y\":false}]}").unwrap();
        let mut store = grammar.effect_store();
        let mut effects = Vec::new();
        for movement in &session.trace {
            effects.push(match *movement {
                Move::Shift { from, symbol } => store.shift(from, symbol).unwrap(),
                Move::Reduce { under, production } => store.reduce(under, production).unwrap(),
                Move::Hole => Effect::ZERO,
            });
        }
        let whole = store.fold(effects.iter().copied()).unwrap();
        assert!(!whole.is_zero());
        for cut in 0..=effects.len() {
            let left = store.fold(effects[..cut].iter().copied()).unwrap();
            let right = store.fold(effects[cut..].iter().copied()).unwrap();
            assert_eq!(store.compose(left, right).unwrap(), whole, "cut {cut}");
        }
    }
    #[test]
    #[ignore = "explicit pinned Verilog grammar recovery-context witness"]
    fn pinned_verilog_recovery_diagnostic_respects_the_concrete_macro_context() {
        let grammar =
            CompiledGrammar::compile(include_bytes!("../../upstream/grammars/verilog.json"))
                .unwrap();
        let source =
            b"module m(input [31:0] irq,\n`ifdef RISCV_FORMAL\noutput reg valid);\nendmodule\n";
        let mut session = grammar.session();
        session.set_recovery(Recovery::Fell);
        session.set_supply(Supply::UniqueLiteral);
        let tree = session.parse_partial(source).unwrap();
        assert!(tree.survey().is_sound());
        assert!(matches!(
            tree.repairs()[0].kind,
            RepairKind::Supplied { .. }
        ));
        assert_eq!(tree.repairs()[0].span, span(26, 26).unwrap());
        assert_eq!(tree.repairs()[1].span, span(34, 35).unwrap());
        assert_eq!(tree.repairs()[1].shifted, 14);
        let graph = &grammar.automaton;
        let mut states = vec![graph.start_state()];
        let mut symbols = vec![];
        let mut reached_hole = false;
        for movement in &session.trace {
            match *movement {
                Move::Shift { from, symbol } => {
                    assert_eq!(states.last(), Some(&from));
                    states.push(graph.transition(from, symbol).unwrap());
                    symbols.push(symbol);
                }
                Move::Reduce { under, production } => {
                    let rule = graph.production(production);
                    let kept = symbols.len() - rule.steps.len();
                    assert!(
                        symbols[kept..]
                            .iter()
                            .copied()
                            .eq(rule.steps.iter().map(|s| s.symbol))
                    );
                    symbols.truncate(kept);
                    states.truncate(kept + 1);
                    assert_eq!(states.last(), Some(&under));
                    states.push(graph.transition(under, rule.lhs).unwrap());
                    symbols.push(rule.lhs);
                }
                Move::Hole => {
                    reached_hole = true;
                    break;
                }
            }
        }
        assert!(reached_hole);
        let names: Vec<_> = symbols
            .iter()
            .map(|&id| graph.symbol(id).name.as_str())
            .collect();
        assert!(names.ends_with(&["[", "`", "simple_identifier"]));
        let macro_text = graph.symbol_by_name("macro_text").unwrap();
        let row = graph.row_admissions(*states.last().unwrap());
        assert!(!row.contains(&macro_text));
        assert!(matches!(
            recovery::admission(graph, &states, macro_text).0,
            Proof::Stops
        ));
        assert!(matches!(
            grammar.lexer.scan_at(source, 34, row, false).unwrap(),
            Scan::Stray { at: 34 }
        ));
        let mut budget = 100_000;
        let Scan::Token(diagnostic) = grammar
            .lexer
            .spot_with_budget(source, 34, false, &mut budget)
            .unwrap()
        else {
            panic!("whole-grammar diagnostic did not name the refused byte");
        };
        assert_eq!(
            (diagnostic.symbol, diagnostic.start, diagnostic.end),
            (graph.symbol_by_name("default_text").unwrap(), 34, 35)
        );

        // A true definition still owns its complete macro body. The context
        // correction must not remove the terminal from the grammar or lexer.
        let definition = grammar
            .session()
            .parse(b"`define F RISCV_FORMAL\n")
            .unwrap();
        let mut pending: Vec<_> = definition.roots().collect();
        let mut bodies = vec![];
        while let Some(node) = pending.pop() {
            if node.name() == "macro_text" {
                bodies.push(node.text());
            }
            pending.extend(node.children());
        }
        assert_eq!(bodies, vec![b" RISCV_FORMAL".as_slice()]);
    }
}
