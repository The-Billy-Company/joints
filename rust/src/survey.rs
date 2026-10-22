//! Bounded speculative segments over unknown prefixes, separate from parsing.
//!
//! A limb shares one pushed symbol string across several possible floors. Every
//! below-base reduction retains both symbol and state claims at every removed
//! depth. Depth fusion widens those claims; exact fusion never mixes histories.
//! All surviving declared actions are explored, including compatible concrete
//! histories of a reduction family. This is intentionally broader than the old
//! primary-action-only instrument, and never claims to choose the parser's rank.
use crate::{
    Action, CompiledGrammar, Lookahead, ProductionId, StateId, SymbolId,
    effects::{Claim, Constraint, Effect, EffectDescription, EffectError, EffectStore},
};
use std::{
    collections::{BTreeMap, BTreeSet, HashMap, HashSet, VecDeque},
    sync::Arc,
};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SurveyFusion {
    Depth,
    Exact,
}
#[derive(Clone, Copy, Debug)]
pub struct SurveyLimits {
    pub states: usize,
    pub graph_entries: usize,
    pub limbs: usize,
    /// Maximum newly uncovered floor, rather than an intermediate rewind set.
    pub floor: usize,
    pub births_per_token: usize,
    pub stack: usize,
    /// Charged per run or set product, including copies and proof searches.
    pub work: usize,
    /// Ledger/push words offered to the interner over this cursor's lifetime.
    /// This conservative quota bounds storage without claiming exact heap bytes.
    pub effect_words: usize,
    pub residue: usize,
    /// Separate copy allowance for optional diagnostics after a run has refused.
    pub diagnostic_words: usize,
}
impl Default for SurveyLimits {
    fn default() -> Self {
        Self {
            states: 131072,
            graph_entries: 16_000_000,
            limbs: 256,
            floor: 64,
            births_per_token: 4096,
            stack: 16384,
            work: 4_000_000,
            effect_words: 16_000_000,
            residue: 64,
            diagnostic_words: 65_536,
        }
    }
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SurveyRefusal {
    Limbs,
    Floor,
    Churn,
    Work,
    Stack,
    Storage,
    Residue,
}
#[derive(Debug, thiserror::Error)]
pub enum SurveyError {
    #[error("survey setup exceeds {resource} limit {limit}")]
    Limit {
        resource: &'static str,
        limit: usize,
    },
    #[error("survey entry state {0:?} is outside this grammar")]
    Entry(StateId),
    #[error("survey symbol {0:?} is not a terminal in this grammar")]
    Token(SymbolId),
    #[error("invalid survey table: {0}")]
    InvalidTable(&'static str),
    #[error(transparent)]
    Effect(#[from] EffectError),
}
#[derive(Clone, Debug)]
pub struct SurveyYield {
    pub effect: Effect,
    pub landings: usize,
}
#[derive(Debug)]
pub struct SurveyLimb {
    pub floors: Vec<StateId>,
    pub ledger: Vec<Claim>,
    pub pushed: Vec<SymbolId>,
    pub landings: Vec<StateId>,
    pub fed: bool,
}
#[derive(Debug)]
pub enum SurveyOutcome {
    Ran(Vec<SurveyYield>),
    Rejected {
        at: usize,
    },
    Refused {
        at: usize,
        reason: SurveyRefusal,
        limbs: usize,
        confession: Vec<SurveyLimb>,
        confession_complete: bool,
    },
}
impl SurveyOutcome {
    pub fn yields(&self) -> Option<&[SurveyYield]> {
        match self {
            Self::Ran(yields) => Some(yields),
            _ => None,
        }
    }
    pub fn rejected_at(&self) -> Option<usize> {
        match *self {
            Self::Rejected { at } => Some(at),
            _ => None,
        }
    }
    pub fn refusal(&self) -> Option<(usize, SurveyRefusal, usize)> {
        match *self {
            Self::Refused {
                at, reason, limbs, ..
            } => Some((at, reason, limbs)),
            _ => None,
        }
    }
    pub fn confession_complete(&self) -> bool {
        match self {
            Self::Refused {
                confession_complete,
                ..
            } => *confession_complete,
            _ => true,
        }
    }
    pub fn confession(&self) -> &[SurveyLimb] {
        match self {
            Self::Refused { confession, .. } => confession,
            _ => &[],
        }
    }
}
#[derive(Clone, Debug, Default)]
pub struct SegmentSurvey {
    pub rank: usize,
    pub domain: usize,
    pub plural: usize,
    pub fanned: usize,
    pub unmoored: usize,
    pub churned: usize,
    pub rejected: usize,
    pub widest: usize,
    pub work_refused: usize,
    pub stack_refused: usize,
    pub storage_refused: usize,
    pub work: usize,
}
#[derive(Debug)]
pub enum SurveyProduct {
    Product(Vec<Effect>),
    Refused { reason: SurveyRefusal, width: usize },
}

impl SurveyProduct {
    pub fn effects(&self) -> Option<&[Effect]> {
        match self {
            Self::Product(effects) => Some(effects),
            _ => None,
        }
    }
    pub fn refusal(&self) -> Option<(SurveyRefusal, usize)> {
        match *self {
            Self::Refused { reason, width } => Some((reason, width)),
            _ => None,
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Hash)]
struct Limb {
    floor: Vec<StateId>,
    above: Vec<SymbolId>,
    perch: Vec<Vec<StateId>>,
    owed: Vec<Claim>,
    fed: bool,
}
impl Limb {
    fn top(&self, k: usize) -> StateId {
        self.perch.last().map_or(self.floor[k], |row| row[k])
    }
    fn words(&self) -> usize {
        self.floor
            .len()
            .saturating_add(self.above.len())
            .saturating_add(
                self.perch
                    .iter()
                    .fold(0usize, |n, row| n.saturating_add(row.len())),
            )
            .saturating_add(ledger_words(&self.owed))
    }
    fn confession(mut self) -> SurveyLimb {
        let landings = self.perch.pop().unwrap_or_else(|| self.floor.clone());
        SurveyLimb {
            floors: self.floor,
            ledger: self.owed,
            pushed: self.above,
            landings,
            fed: self.fed,
        }
    }
}
#[derive(Eq, PartialEq, Hash)]
struct Twin {
    depth: usize,
    above: Vec<SymbolId>,
    owed: Option<Vec<Claim>>,
    fed: bool,
}
#[derive(Clone, Copy, Eq, PartialEq, Ord, PartialOrd)]
enum Verb {
    Shift,
    Reduce(ProductionId),
    Accept,
}
struct Budget {
    used: usize,
    limit: usize,
}
impl Budget {
    fn charge(&mut self, n: usize) -> Result<(), Fault> {
        let next = self
            .used
            .checked_add(n)
            .ok_or(Fault::Refused(SurveyRefusal::Work))?;
        if next > self.limit {
            return Err(Fault::Refused(SurveyRefusal::Work));
        }
        self.used = next;
        Ok(())
    }
}
enum Fault {
    Refused(SurveyRefusal),
    Invalid(SurveyError),
}
impl From<SurveyError> for Fault {
    fn from(e: SurveyError) -> Self {
        Self::Invalid(e)
    }
}
impl From<EffectError> for Fault {
    fn from(e: EffectError) -> Self {
        Self::Invalid(SurveyError::Effect(e))
    }
}

#[derive(Clone, Copy, Default)]
struct EffectMeasure {
    words: usize,
    floors: usize,
    push: usize,
}
impl EffectMeasure {
    fn of(description: &EffectDescription) -> Self {
        match description {
            EffectDescription::Identity | EffectDescription::Zero => Self::default(),
            EffectDescription::Run { ledger, push, .. } => Self {
                words: description_words(description),
                push: push.len(),
                floors: ledger.last().map_or(1, |claim| match &claim.states {
                    Constraint::Any => 1,
                    Constraint::Finite(states) => states.len(),
                }),
            },
        }
    }
}
pub struct SurveyCursor {
    grammar: Arc<CompiledGrammar>,
    store: EffectStore,
    reverse: Vec<BTreeMap<SymbolId, Vec<StateId>>>,
    limits: SurveyLimits,
    fusion: SurveyFusion,
    confess: bool,
    last_work: usize,
    effect_words: usize,
    weights: HashMap<Effect, EffectMeasure>,
}
impl CompiledGrammar {
    pub fn survey_cursor(self: &Arc<Self>) -> Result<SurveyCursor, SurveyError> {
        SurveyCursor::new(Arc::clone(self), SurveyLimits::default())
    }
    pub fn survey_cursor_with_limits(
        self: &Arc<Self>,
        limits: SurveyLimits,
    ) -> Result<SurveyCursor, SurveyError> {
        SurveyCursor::new(Arc::clone(self), limits)
    }
}
impl SurveyCursor {
    pub fn new(grammar: Arc<CompiledGrammar>, limits: SurveyLimits) -> Result<Self, SurveyError> {
        if grammar.state_count() > limits.states {
            return Err(SurveyError::Limit {
                resource: "states",
                limit: limits.states,
            });
        }
        let mut count = 0usize;
        for i in 0..grammar.state_count() {
            count = count
                .checked_add(
                    grammar
                        .automaton
                        .state_transitions(StateId::from_index(i))
                        .len(),
                )
                .ok_or(SurveyError::Limit {
                    resource: "reverse graph entries",
                    limit: limits.graph_entries,
                })?;
            if count > limits.graph_entries {
                return Err(SurveyError::Limit {
                    resource: "reverse graph entries",
                    limit: limits.graph_entries,
                });
            }
        }
        let mut reverse = vec![BTreeMap::<SymbolId, Vec<StateId>>::new(); grammar.state_count()];
        for i in 0..grammar.state_count() {
            let from = StateId::from_index(i);
            for (s, to) in grammar.automaton.state_transitions(from) {
                let active = grammar.automaton.symbol(s).lexis.is_none()
                    || grammar
                        .automaton
                        .actions(from, Lookahead::Terminal(s))
                        .contains(&Action::Shift(to));
                if active {
                    reverse[to.index()].entry(s).or_default().push(from);
                }
            }
        }
        let store = grammar.effect_store();
        Ok(Self {
            grammar,
            store,
            reverse,
            limits,
            fusion: SurveyFusion::Depth,
            confess: false,
            last_work: 0,
            effect_words: 0,
            weights: HashMap::new(),
        })
    }
    pub fn limits(&self) -> SurveyLimits {
        self.limits
    }
    /// Setup capacities cannot be reduced after their graph has been allocated.
    pub fn set_limits(&mut self, limits: SurveyLimits) -> Result<(), SurveyError> {
        if self.grammar.state_count() > limits.states {
            return Err(SurveyError::Limit {
                resource: "states",
                limit: limits.states,
            });
        }
        let edges = self
            .reverse
            .iter()
            .flat_map(BTreeMap::values)
            .map(Vec::len)
            .sum::<usize>();
        if edges > limits.graph_entries {
            return Err(SurveyError::Limit {
                resource: "reverse graph entries",
                limit: limits.graph_entries,
            });
        }
        self.limits = limits;
        Ok(())
    }
    pub fn set_exact(&mut self, exact: bool) {
        self.fusion = if exact {
            SurveyFusion::Exact
        } else {
            SurveyFusion::Depth
        };
    }
    pub fn set_confess(&mut self, confess: bool) {
        self.confess = confess;
    }
    pub fn fusion(&self) -> SurveyFusion {
        self.fusion
    }
    pub fn work(&self) -> usize {
        self.last_work
    }
    /// Update the next operation's allowance without rebuilding setup proofs.
    pub fn set_work_limit(&mut self, work: usize) {
        self.limits.work = work;
    }
    /// Words copied by an owned diagnostic description. Handle validation is
    /// constant time and precedes the size lookup, including zero/identity.
    pub fn description_work(&self, effect: Effect) -> Result<usize, SurveyError> {
        self.store.validate_effect(effect)?;
        Ok(self
            .weights
            .get(&effect)
            .map_or(0, |measure| measure.words)
            .saturating_add(1))
    }
    pub fn describe(&mut self, effect: Effect) -> Result<EffectDescription, SurveyError> {
        self.last_work = 0;
        let work = self.description_work(effect)?;
        if work > self.limits.work {
            return Err(SurveyError::Limit {
                resource: "description work",
                limit: self.limits.work,
            });
        }
        self.last_work = work;
        Ok(self.store.describe(effect)?)
    }
    pub fn identity(&self) -> Effect {
        Effect::IDENTITY
    }
    pub fn grounded(&self, effect: Effect) -> Result<bool, SurveyError> {
        Ok(self.store.grounded(effect)?)
    }
    /// Compare canonical sets from this cursor, validating even handles beside
    /// an empty set. This does not equate handles from independent stores.
    pub fn same_effects(&mut self, left: &[Effect], right: &[Effect]) -> Result<bool, SurveyError> {
        let mut budget = Budget {
            used: 0,
            limit: self.limits.work,
        };
        let result = (|| -> Result<bool, Fault> {
            budget.charge(left.len().saturating_add(right.len()))?;
            for &effect in left.iter().chain(right) {
                self.store.validate_effect(effect)?;
            }
            let a: HashSet<_> = left.iter().copied().collect();
            let b: HashSet<_> = right.iter().copied().collect();
            Ok(a == b)
        })();
        self.comparison_result(result, budget.used)
    }
    /// Membership against a separately owned actual-trace description. The
    /// speculative cursor computes its own effects; the description is an oracle.
    pub fn contains_actual(
        &mut self,
        effects: &[Effect],
        actual: &EffectDescription,
    ) -> Result<bool, SurveyError> {
        let mut budget = Budget {
            used: 0,
            limit: self.limits.work,
        };
        let result = (|| -> Result<bool, Fault> {
            budget.charge(effects.len())?;
            charge_description(&mut budget, actual)?;
            for &effect in effects {
                self.store.validate_effect(effect)?;
            }
            for &effect in effects {
                budget.charge(
                    self.weights
                        .get(&effect)
                        .map_or(0, |measure| measure.words)
                        .saturating_add(1),
                )?;
                if self.store.describe(effect)? == *actual {
                    return Ok(true);
                }
            }
            Ok(false)
        })();
        self.comparison_result(result, budget.used)
    }
    fn comparison_result(
        &mut self,
        result: Result<bool, Fault>,
        work: usize,
    ) -> Result<bool, SurveyError> {
        self.last_work = work;
        match result {
            Ok(v) => Ok(v),
            Err(Fault::Invalid(e)) => Err(e),
            Err(Fault::Refused(_)) => Err(SurveyError::Limit {
                resource: "comparison work",
                limit: self.limits.work,
            }),
        }
    }
    fn reserve_effect(&mut self, words: usize) -> Result<(), Fault> {
        let next = self
            .effect_words
            .checked_add(words)
            .ok_or(Fault::Refused(SurveyRefusal::Storage))?;
        if next > self.limits.effect_words {
            return Err(Fault::Refused(SurveyRefusal::Storage));
        }
        self.effect_words = next;
        Ok(())
    }
    pub fn run(
        &mut self,
        entry: StateId,
        tokens: &[SymbolId],
    ) -> Result<SurveyOutcome, SurveyError> {
        self.last_work = 0;
        if entry.index() >= self.grammar.state_count() {
            return Err(SurveyError::Entry(entry));
        }
        let mut budget = Budget {
            used: 0,
            limit: self.limits.work,
        };
        if budget.charge(tokens.len()).is_err() {
            return Ok(self.refused(0, SurveyRefusal::Work, vec![]));
        }
        self.last_work = budget.used;
        for &s in tokens {
            if s.index() >= self.grammar.symbol_count()
                || self.grammar.automaton.symbol(s).lexis.is_none()
            {
                return Err(SurveyError::Token(s));
            }
        }
        let outcome = self.run_inner(entry, tokens, &mut budget);
        self.last_work = budget.used;
        outcome
    }
    fn refused(&self, at: usize, reason: SurveyRefusal, limbs: Vec<Limb>) -> SurveyOutcome {
        let count = limbs.len();
        // Moving an existing last perch row is free of payload copies. Empty
        // pushes need a floor copy, bounded by a separate diagnostic allowance.
        let words = limbs.iter().fold(0usize, |n, limb| {
            n.saturating_add(1)
                .saturating_add(if limb.perch.is_empty() {
                    limb.floor.len()
                } else {
                    0
                })
        });
        let complete = self.confess && words <= self.limits.diagnostic_words;
        SurveyOutcome::Refused {
            at,
            reason,
            limbs: count,
            confession_complete: complete,
            confession: if complete {
                limbs.into_iter().map(Limb::confession).collect()
            } else {
                Vec::new()
            },
        }
    }
    fn run_inner(
        &mut self,
        entry: StateId,
        tokens: &[SymbolId],
        budget: &mut Budget,
    ) -> Result<SurveyOutcome, SurveyError> {
        let mut limbs = vec![Limb {
            floor: vec![entry],
            above: vec![],
            perch: vec![],
            owed: vec![],
            fed: false,
        }];
        if self.limits.limbs == 0 {
            return Ok(self.refused(0, SurveyRefusal::Limbs, limbs));
        }
        for (at, &token) in tokens.iter().enumerate() {
            for l in &mut limbs {
                l.fed = false;
            }
            let mut pending = VecDeque::from(limbs);
            let mut done = Vec::new();
            let mut seen = HashSet::new();
            let mut births = 0usize;
            while let Some(limb) = pending.pop_front() {
                let result = (|| -> Result<Vec<Limb>, Fault> {
                    budget.charge(limb.words().saturating_add(1))?;
                    if seen.contains(&limb) {
                        return Ok(Vec::new());
                    }
                    seen.insert(limb.clone());
                    self.advance(&limb, token, budget)
                })();
                let branches = match result {
                    Ok(v) => v,
                    Err(Fault::Invalid(e)) => return Err(e),
                    Err(Fault::Refused(reason)) => {
                        let mut all = vec![limb];
                        all.extend(pending);
                        all.extend(done);
                        return Ok(self.refused(at, reason, all));
                    }
                };
                births = births.saturating_add(branches.len().saturating_sub(1));
                if births > self.limits.births_per_token {
                    let mut all = branches;
                    all.extend(pending);
                    all.extend(done);
                    return Ok(self.refused(at, SurveyRefusal::Churn, all));
                }
                let mut all = branches;
                all.extend(pending);
                all.extend(done);
                let merged = match self.merge(all, budget) {
                    Ok(v) => v,
                    Err((Fault::Invalid(e), _)) => return Err(e),
                    Err((Fault::Refused(reason), standing)) => {
                        return Ok(self.refused(at, reason, standing));
                    }
                };
                if merged.len() > self.limits.limbs {
                    return Ok(self.refused(at, SurveyRefusal::Limbs, merged));
                }
                pending = VecDeque::new();
                done = Vec::new();
                for l in merged {
                    if l.fed {
                        done.push(l);
                    } else {
                        pending.push_back(l);
                    }
                }
            }
            if done.is_empty() {
                return Ok(SurveyOutcome::Rejected { at });
            }
            limbs = done;
        }
        match self.reap(entry, &limbs, budget) {
            Ok(yields) => Ok(SurveyOutcome::Ran(yields)),
            Err(Fault::Invalid(e)) => Err(e),
            Err(Fault::Refused(reason)) => Ok(self.refused(tokens.len(), reason, limbs)),
        }
    }
    fn subset(&self, l: &Limb, columns: &[usize], budget: &mut Budget) -> Result<Limb, Fault> {
        budget.charge(
            columns
                .len()
                .saturating_mul(l.perch.len().saturating_add(1))
                .saturating_add(l.above.len())
                .saturating_add(ledger_words(&l.owed)),
        )?;
        Ok(Limb {
            floor: columns.iter().map(|&k| l.floor[k]).collect(),
            above: l.above.clone(),
            perch: l
                .perch
                .iter()
                .map(|row| columns.iter().map(|&k| row[k]).collect())
                .collect(),
            owed: l.owed.clone(),
            fed: false,
        })
    }
    fn advance(&self, l: &Limb, token: SymbolId, budget: &mut Budget) -> Result<Vec<Limb>, Fault> {
        let a = &self.grammar.automaton;
        let mut groups = BTreeMap::<Verb, Vec<usize>>::new();
        for k in 0..l.floor.len() {
            budget.charge(1)?;
            for action in a.actions(l.top(k), Lookahead::Terminal(token)) {
                budget.charge(1)?;
                match *action {
                    Action::Shift(_) => groups.entry(Verb::Shift).or_default().push(k),
                    Action::Accept => groups.entry(Verb::Accept).or_default().push(k),
                    Action::Reduce(id) => {
                        for &p in &a.reduction(id).productions {
                            let rule = a.production(p);
                            let known = l.above.len().min(rule.steps.len());
                            budget.charge(known.saturating_add(1))?;
                            if l.above[l.above.len() - known..]
                                .iter()
                                .copied()
                                .eq(rule.steps[rule.steps.len() - known..]
                                    .iter()
                                    .map(|s| s.symbol))
                            {
                                groups.entry(Verb::Reduce(p)).or_default().push(k);
                            }
                        }
                    }
                }
            }
        }
        let mut out = Vec::new();
        for (verb, mut columns) in groups {
            columns.sort_unstable();
            columns.dedup();
            let mut next = self.subset(l, &columns, budget)?;
            match verb {
                Verb::Shift => {
                    if next.above.len().saturating_add(next.owed.len()) >= self.limits.stack {
                        return Err(Fault::Refused(SurveyRefusal::Stack));
                    }
                    budget.charge(next.floor.len())?;
                    let mut row = Vec::with_capacity(next.floor.len());
                    for k in 0..next.floor.len() {
                        row.push(
                            a.transition(next.top(k), token)
                                .ok_or(SurveyError::InvalidTable("shift has no transition"))?,
                        );
                    }
                    next.above.push(token);
                    next.perch.push(row);
                    next.fed = true;
                }
                Verb::Accept => next.fed = true,
                Verb::Reduce(p) => {
                    if !self.reduce(&mut next, p, budget)? {
                        continue;
                    }
                }
            }
            out.push(next);
        }
        Ok(out)
    }
    fn reduce(&self, l: &mut Limb, p: ProductionId, budget: &mut Budget) -> Result<bool, Fault> {
        let rule = self.grammar.automaton.production(p);
        let have = l.above.len();
        if rule.steps.len() <= have {
            l.above.truncate(have - rule.steps.len());
            l.perch.truncate(l.above.len());
        } else {
            let below = rule.steps.len() - have;
            if l.owed.len().saturating_add(below).saturating_add(1) > self.limits.stack {
                return Err(Fault::Refused(SurveyRefusal::Stack));
            }
            budget.charge(l.floor.len())?;
            let mut front = l.floor.clone();
            budget.charge(below)?;
            let mut trail = Vec::with_capacity(below);
            for step in rule.steps[..below].iter().rev() {
                let mut predecessors = BTreeSet::new();
                for &q in &front {
                    budget.charge(1)?;
                    if let Some(origins) = self.reverse[q.index()].get(&step.symbol) {
                        for &from in origins {
                            budget.charge(1)?;
                            predecessors.insert(from);
                        }
                    }
                }
                if predecessors.is_empty() {
                    return Ok(false);
                }
                budget.charge(predecessors.len().saturating_mul(2))?;
                front = predecessors.into_iter().collect();
                trail.push(front.clone());
            }
            if front.len() > self.limits.floor {
                return Err(Fault::Refused(SurveyRefusal::Floor));
            }
            budget.charge(ledger_words(&l.owed).saturating_add(l.floor.len()))?;
            if let Some(deepest) = l.owed.last_mut() {
                deepest.states = Constraint::Finite(l.floor.clone());
            }
            for d in 1..=below {
                budget.charge(trail[d - 1].len().saturating_add(2))?;
                l.owed.push(Claim {
                    states: if d == below {
                        Constraint::Any
                    } else {
                        Constraint::Finite(trail[d - 1].clone())
                    },
                    symbols: Constraint::Finite(vec![rule.steps[below - d].symbol]),
                });
            }
            l.floor = front;
            l.above.clear();
            l.perch.clear();
        }
        if l.above.len().saturating_add(l.owed.len()) >= self.limits.stack {
            return Err(Fault::Refused(SurveyRefusal::Stack));
        }
        let mut columns = Vec::new();
        let mut row = Vec::new();
        for k in 0..l.floor.len() {
            budget.charge(1)?;
            if let Some(to) = self.grammar.automaton.transition(l.top(k), rule.lhs) {
                columns.push(k);
                row.push(to);
            }
        }
        if columns.is_empty() {
            return Ok(false);
        }
        if columns.len() != l.floor.len() {
            *l = self.subset(l, &columns, budget)?;
        }
        l.above.push(rule.lhs);
        l.perch.push(row);
        Ok(true)
    }
    fn merge(
        &self,
        limbs: Vec<Limb>,
        budget: &mut Budget,
    ) -> Result<Vec<Limb>, (Fault, Vec<Limb>)> {
        let mut twins = HashMap::<Twin, usize>::new();
        let mut out: Vec<Limb> = Vec::new();
        let mut pending = limbs.into_iter();
        while let Some(limb) = pending.next() {
            let result = (|| -> Result<bool, Fault> {
                budget.charge(limb.words().saturating_add(1))?;
                let key = Twin {
                    depth: limb.owed.len(),
                    above: limb.above.clone(),
                    owed: if self.fusion == SurveyFusion::Exact {
                        Some(limb.owed.clone())
                    } else {
                        None
                    },
                    fed: limb.fed,
                };
                if let Some(&index) = twins.get(&key) {
                    self.fuse(&mut out[index], &limb, budget)?;
                } else {
                    twins.insert(key, out.len());
                    return Ok(true);
                }
                Ok(false)
            })();
            let is_new = match result {
                Ok(is_new) => is_new,
                Err(fault) => {
                    out.push(limb);
                    out.extend(pending);
                    return Err((fault, out));
                }
            };
            if is_new {
                out.push(limb);
            }
        }
        Ok(out)
    }
    fn fuse(&self, a: &mut Limb, b: &Limb, budget: &mut Budget) -> Result<(), Fault> {
        // Charge the complete merge before mutating either input. On a resource
        // refusal the caller can retain the exact pre-merge live limbs.
        budget.charge(
            a.words().saturating_add(b.words()).saturating_add(
                a.floor
                    .len()
                    .saturating_add(b.floor.len())
                    .saturating_mul(a.perch.len().saturating_add(1)),
            ),
        )?;
        let mut columns = BTreeMap::new();
        for (k, &q) in a.floor.iter().enumerate() {
            columns.insert(q, (false, k));
        }
        for (k, &q) in b.floor.iter().enumerate() {
            if let Some(&(false, i)) = columns.get(&q) {
                if a.perch
                    .iter()
                    .zip(&b.perch)
                    .any(|(left, right)| left[i] != right[k])
                {
                    return Err(SurveyError::InvalidTable(
                        "same floor and push have different states",
                    )
                    .into());
                }
            } else {
                columns.insert(q, (true, k));
            }
        }
        let floor = columns.keys().copied().collect();
        let perch = (0..a.perch.len())
            .map(|d| {
                columns
                    .values()
                    .map(
                        |&(from_b, k)| {
                            if from_b { b.perch[d][k] } else { a.perch[d][k] }
                        },
                    )
                    .collect()
            })
            .collect();
        if self.fusion == SurveyFusion::Depth {
            for (left, right) in a.owed.iter_mut().zip(&b.owed) {
                left.states = union(&left.states, &right.states);
                left.symbols = union(&left.symbols, &right.symbols);
            }
        }
        a.floor = floor;
        a.perch = perch;
        Ok(())
    }
    fn reap(
        &mut self,
        entry: StateId,
        limbs: &[Limb],
        budget: &mut Budget,
    ) -> Result<Vec<SurveyYield>, Fault> {
        let mut yielded = Vec::<SurveyYield>::new();
        let mut indexes = HashMap::new();
        let mut landed = Vec::<BTreeSet<StateId>>::new();
        for l in limbs {
            let words = l.words();
            budget.charge(words.saturating_add(1))?;
            let mut ledger = l.owed.clone();
            if let Some(deepest) = ledger.last_mut() {
                deepest.states = Constraint::Finite(l.floor.clone());
            }
            let effect_words = ledger_words(&ledger)
                .saturating_add(l.above.len())
                .saturating_add(1);
            self.reserve_effect(effect_words)?;
            let effect = self.store.exploratory(entry, ledger, l.above.clone())?;
            self.weights.insert(
                effect,
                EffectMeasure {
                    words: effect_words,
                    floors: if l.owed.is_empty() { 1 } else { l.floor.len() },
                    push: l.above.len(),
                },
            );
            let index = *indexes.entry(effect).or_insert_with(|| {
                let i = yielded.len();
                yielded.push(SurveyYield {
                    effect,
                    landings: 0,
                });
                landed.push(BTreeSet::new());
                i
            });
            for k in 0..l.floor.len() {
                budget.charge(1)?;
                landed[index].insert(l.top(k));
            }
        }
        for (i, set) in landed.into_iter().enumerate() {
            yielded[i].landings = set.len();
        }
        Ok(yielded)
    }
    /// Census entries under one shared allowance, including owned rank views.
    /// CLI adapters may instead call `run` to preserve partial per-entry reports.
    pub fn survey(
        &mut self,
        entries: &[StateId],
        tokens: &[SymbolId],
    ) -> Result<SegmentSurvey, SurveyError> {
        let allowance = self.limits.work;
        let mut remaining = allowance;
        let result = (|| -> Result<SegmentSurvey, SurveyError> {
            remaining = remaining
                .checked_sub(entries.len())
                .ok_or(SurveyError::Limit {
                    resource: "aggregate work",
                    limit: allowance,
                })?;
            let mut report = SegmentSurvey::default();
            let mut shapes = HashSet::new();
            for &entry in entries {
                self.limits.work = remaining;
                let outcome = self.run(entry, tokens);
                remaining -= self.work();
                match outcome? {
                    SurveyOutcome::Ran(ys) => {
                        report.domain += 1;
                        if ys.len() > 1 {
                            report.plural += 1;
                        }
                        for y in ys {
                            report.widest = report.widest.max(y.landings);
                            self.limits.work = remaining;
                            let description = self.describe(y.effect);
                            remaining -= self.work();
                            match description? {
                                EffectDescription::Run { ledger, push, .. } => {
                                    shapes.insert((ledger.len(), push));
                                }
                                EffectDescription::Identity => {
                                    shapes.insert((0, vec![]));
                                }
                                EffectDescription::Zero => {}
                            }
                        }
                    }
                    SurveyOutcome::Rejected { .. } => report.rejected += 1,
                    SurveyOutcome::Refused { reason, .. } => match reason {
                        SurveyRefusal::Limbs => report.fanned += 1,
                        SurveyRefusal::Floor => report.unmoored += 1,
                        SurveyRefusal::Churn => report.churned += 1,
                        SurveyRefusal::Work => report.work_refused += 1,
                        SurveyRefusal::Stack => report.stack_refused += 1,
                        SurveyRefusal::Storage => report.storage_refused += 1,
                        SurveyRefusal::Residue => unreachable!("run does not multiply sets"),
                    },
                }
            }
            report.rank = shapes.len();
            report.work = allowance - remaining;
            Ok(report)
        })();
        self.limits.work = allowance;
        self.last_work = allowance - remaining;
        result
    }
    /// Ordered guarded set product. Zero pairings are removed, identities and
    /// foreign handles are still validated by the owning interner.
    pub fn product(
        &mut self,
        left: &[Effect],
        right: &[Effect],
    ) -> Result<SurveyProduct, SurveyError> {
        self.product_inner(left, right, false)
    }
    /// Drop ungrounded products before checking the residue ceiling. This is
    /// the chained-segmentation oracle rooted at the document's initial stack.
    pub fn product_grounded(
        &mut self,
        left: &[Effect],
        right: &[Effect],
    ) -> Result<SurveyProduct, SurveyError> {
        self.product_inner(left, right, true)
    }
    fn product_inner(
        &mut self,
        left: &[Effect],
        right: &[Effect],
        grounded: bool,
    ) -> Result<SurveyProduct, SurveyError> {
        let mut budget = Budget {
            used: 0,
            limit: self.limits.work,
        };
        let mut width = 0;
        let result = (|| -> Result<SurveyProduct, Fault> {
            let mut out = Vec::new();
            let mut seen = HashSet::new();
            // Validate every handle before empty-set or zero shortcuts.
            budget.charge(left.len().saturating_add(right.len()))?;
            for &e in left.iter().chain(right) {
                self.store.validate_effect(e)?;
            }
            for &a in left {
                for &b in right {
                    let ma = self.weights.get(&a).copied().unwrap_or_default();
                    let mb = self.weights.get(&b).copied().unwrap_or_default();
                    let words = ma.words.saturating_add(mb.words);
                    // Composition checks the left push separately at each live
                    // floor, consulting finite state/symbol sets and graph maps.
                    let logs = usize::BITS as usize
                        - self.grammar.state_count().max(1).leading_zeros() as usize
                        + 2 * (usize::BITS as usize
                            - self.grammar.symbol_count().max(1).leading_zeros() as usize)
                        + 4;
                    let search = ma
                        .floors
                        .saturating_mul(ma.push.saturating_add(1))
                        .saturating_mul(logs);
                    // Include copied guards, interning and the later owned view
                    // before any of those allocations. Output never exceeds the
                    // two input payloads plus its fixed entry/header word.
                    budget
                        .charge(search.saturating_add(words.saturating_add(1).saturating_mul(8)))?;
                    self.reserve_effect(words.saturating_add(1))?;
                    let effect = self.store.compose(a, b)?;
                    if effect.is_zero() || (grounded && !self.store.grounded(effect)?) {
                        continue;
                    }
                    if seen.insert(effect) {
                        let desc = self.store.describe(effect)?;
                        self.weights.insert(effect, EffectMeasure::of(&desc));
                        out.push(effect);
                        width = out.len();
                        if out.len() > self.limits.residue {
                            return Ok(SurveyProduct::Refused {
                                reason: SurveyRefusal::Residue,
                                width: out.len(),
                            });
                        }
                    }
                }
            }
            Ok(SurveyProduct::Product(out))
        })();
        self.last_work = budget.used;
        match result {
            Ok(v) => Ok(v),
            Err(Fault::Invalid(e)) => Err(e),
            Err(Fault::Refused(reason)) => Ok(SurveyProduct::Refused { reason, width }),
        }
    }
}
fn constraint_words<T>(c: &Constraint<T>) -> usize {
    match c {
        Constraint::Any => 1,
        Constraint::Finite(v) => v.len().saturating_add(1),
    }
}
fn claim_words(c: &Claim) -> usize {
    constraint_words(&c.states).saturating_add(constraint_words(&c.symbols))
}
fn ledger_words(ledger: &[Claim]) -> usize {
    ledger
        .iter()
        .fold(0usize, |n, c| n.saturating_add(claim_words(c)))
}
fn charge_description(budget: &mut Budget, description: &EffectDescription) -> Result<(), Fault> {
    match description {
        EffectDescription::Identity | EffectDescription::Zero => budget.charge(1),
        EffectDescription::Run { ledger, push, .. } => {
            // The outer traversal is paid before looking at any claim payload.
            budget.charge(ledger.len().saturating_add(push.len()).saturating_add(1))?;
            for claim in ledger {
                budget.charge(claim_words(claim))?;
            }
            Ok(())
        }
    }
}
fn description_words(d: &EffectDescription) -> usize {
    match d {
        EffectDescription::Identity | EffectDescription::Zero => 0,
        EffectDescription::Run { ledger, push, .. } => ledger_words(ledger)
            .saturating_add(push.len())
            .saturating_add(1),
    }
}
fn union<T: Ord + Clone>(a: &Constraint<T>, b: &Constraint<T>) -> Constraint<T> {
    match (a, b) {
        (Constraint::Any, _) | (_, Constraint::Any) => Constraint::Any,
        (Constraint::Finite(a), Constraint::Finite(b)) => {
            let mut out = a.clone();
            out.extend_from_slice(b);
            out.sort_unstable();
            out.dedup();
            Constraint::Finite(out)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn grammar() -> Arc<CompiledGrammar> {
        CompiledGrammar::compile(br#"{"name":"survey","rules":{
          "doc":{"type":"SEQ","members":[{"type":"SYMBOL","name":"A"},{"type":"STRING","value":"z"}]},
          "A":{"type":"CHOICE","members":[
            {"type":"SEQ","members":[{"type":"STRING","value":"a"},{"type":"STRING","value":"x"}]},
            {"type":"SEQ","members":[{"type":"STRING","value":"d"},{"type":"STRING","value":"y"}]}]}}}"#).unwrap()
    }
    fn tokens(g: &CompiledGrammar, names: &[&str]) -> Vec<SymbolId> {
        names
            .iter()
            .map(|n| g.automaton.symbol_by_name(n).unwrap())
            .collect()
    }
    fn yielded(outcome: SurveyOutcome) -> Vec<Effect> {
        match outcome {
            SurveyOutcome::Ran(ys) => ys.into_iter().map(|y| y.effect).collect(),
            other => panic!("{other:?}"),
        }
    }
    fn product(outcome: SurveyProduct) -> Vec<Effect> {
        match outcome {
            SurveyProduct::Product(ys) => ys,
            other => panic!("{other:?}"),
        }
    }
    fn receipt(g: &Arc<CompiledGrammar>, source: &[u8]) -> Vec<crate::parser::ParsedToken> {
        let mut session = g.session();
        session.set_trace_enabled(true);
        session.parse(source).unwrap();
        session.selected_tokens().unwrap().to_vec()
    }
    #[test]
    fn empty_scoped_run_and_resource_refusal_are_distinct_from_rejection() {
        let g = grammar();
        let mut c = g.survey_cursor().unwrap();
        let start = g.start_state();
        let e = yielded(c.run(start, &[]).unwrap());
        assert_eq!(e.len(), 1);
        assert_eq!(
            c.describe(e[0]).unwrap(),
            EffectDescription::Run {
                entry: start,
                ledger: vec![],
                push: vec![]
            }
        );
        assert!(c.grounded(e[0]).unwrap());
        let z = tokens(&g, &["z"]);
        assert_eq!(c.run(start, &z).unwrap().rejected_at(), Some(0));
        c.set_limits(SurveyLimits {
            work: 0,
            ..c.limits()
        })
        .unwrap();
        assert_eq!(
            c.run(start, &z).unwrap().refusal(),
            Some((0, SurveyRefusal::Work, 0))
        );
        assert_eq!(c.work(), 0);
        assert!(matches!(
            c.run(StateId::from_index(g.state_count()), &[]),
            Err(SurveyError::Entry(_))
        ));
        c.set_limits(SurveyLimits::default()).unwrap();
        assert!(matches!(
            c.run(start, &[g.start_symbol()]),
            Err(SurveyError::Token(_))
        ));
    }
    #[test]
    fn every_actual_cut_rewinds_below_base_and_recomposes_the_selected_token_prefix() {
        let g = grammar();
        for source in [b"axz".as_slice(), b"dyz"] {
            let mut session = g.session();
            session.set_trace_enabled(true);
            session.parse(source).unwrap();
            let receipts = session.selected_tokens().unwrap();
            let input: Vec<_> = receipts.iter().map(|r| r.symbol).collect();
            let mut c = g.survey_cursor().unwrap();
            c.set_exact(true);
            let whole = yielded(c.run(g.start_state(), &input).unwrap());
            let mut actual = g.effect_store();
            let (selected, work) = session
                .product_range(0..receipts.last().unwrap().moves.end, &mut actual, 100_000)
                .unwrap();
            assert!(work > 0);
            assert!(
                c.contains_actual(&whole, &actual.describe(selected).unwrap())
                    .unwrap()
            );
            for cut in 0..=input.len() {
                let left = yielded(c.run(g.start_state(), &input[..cut]).unwrap());
                let entry = receipts.get(cut).map_or_else(
                    || {
                        let last = receipts.last().unwrap();
                        g.automaton.transition(last.from, last.symbol).unwrap()
                    },
                    |r| r.entry,
                );
                let right = yielded(c.run(entry, &input[cut..]).unwrap());
                let chain = product(c.product_grounded(&left, &right).unwrap());
                assert!(
                    c.same_effects(&whole, &chain).unwrap(),
                    "cut {cut}, {source:?}"
                );
            }
            let at = receipts[2].entry;
            assert_ne!(
                at, receipts[2].from,
                "z must cause the below-base A reduction"
            );
            let right = yielded(c.run(at, &input[2..]).unwrap());
            assert!(right.iter().any(|&e| matches!(c.describe(e).unwrap(), EffectDescription::Run {ledger,..} if ledger.len()==2)));
        }
    }
    #[test]
    fn exact_fusion_retains_correlated_histories_depth_fusion_admits_its_documented_widening() {
        let g = grammar();
        let ax = receipt(&g, b"axz");
        let dy = receipt(&g, b"dyz");
        assert_eq!(
            ax[2].entry, dy[2].entry,
            "the normalized completed histories share a state"
        );
        let mut c = g.survey_cursor().unwrap();
        c.set_exact(true);
        let exact = yielded(c.run(ax[2].entry, &[ax[2].symbol]).unwrap());
        assert_eq!(exact.len(), 2);
        let exact_desc: Vec<_> = exact.iter().map(|&e| c.describe(e).unwrap()).collect();
        assert!(
            exact_desc
                .iter()
                .all(|e| matches!(e,EffectDescription::Run{ledger,..} if ledger.len()==2))
        );
        let repeat = yielded(c.run(ax[2].entry, &[ax[2].symbol]).unwrap());
        assert!(c.same_effects(&exact, &repeat).unwrap());
        c.set_exact(false);
        let depth = yielded(c.run(ax[2].entry, &[ax[2].symbol]).unwrap());
        assert_eq!(depth.len(), 1);
        let EffectDescription::Run { ledger, .. } = c.describe(depth[0]).unwrap() else {
            panic!()
        };
        assert_eq!(
            ledger[0].symbols,
            Constraint::Finite(tokens(&g, &["x", "y"]))
        );
        assert_eq!(
            ledger[1].symbols,
            Constraint::Finite(tokens(&g, &["a", "d"]))
        );
    }
    #[test]
    fn handle_validation_precedes_zero_or_empty_shortcuts_and_grounding_precedes_residue() {
        let g = grammar();
        let mut c = g.survey_cursor().unwrap();
        let mut foreign = g.effect_store();
        let s = tokens(&g, &["a"])[0];
        let e = foreign.shift(g.start_state(), s).unwrap();
        assert!(matches!(
            c.product(&[Effect::ZERO], &[e]),
            Err(SurveyError::Effect(EffectError::ForeignStore))
        ));
        assert!(matches!(
            c.same_effects(&[], &[e]),
            Err(SurveyError::Effect(EffectError::ForeignStore))
        ));
        let r = receipt(&g, b"axz");
        c.set_exact(true);
        let unknown = yielded(c.run(r[2].entry, &[r[2].symbol]).unwrap());
        assert!(unknown.iter().all(|&e| !c.grounded(e).unwrap()));
        c.set_limits(SurveyLimits {
            residue: 0,
            ..c.limits()
        })
        .unwrap();
        assert!(matches!(
            c.product(&[Effect::IDENTITY], &unknown).unwrap(),
            SurveyProduct::Refused {
                reason: SurveyRefusal::Residue,
                ..
            }
        ));
        assert!(product(c.product_grounded(&[Effect::IDENTITY], &unknown).unwrap()).is_empty());
    }
    #[test]
    fn independent_limits_preserve_refusal_evidence_and_setup_is_bounded() {
        let g = grammar();
        let rs = receipt(&g, b"axz");
        assert!(matches!(
            g.survey_cursor_with_limits(SurveyLimits {
                states: 0,
                ..SurveyLimits::default()
            }),
            Err(SurveyError::Limit {
                resource: "states",
                ..
            })
        ));
        assert!(matches!(
            g.survey_cursor_with_limits(SurveyLimits {
                graph_entries: 0,
                ..SurveyLimits::default()
            }),
            Err(SurveyError::Limit {
                resource: "reverse graph entries",
                ..
            })
        ));
        for (limits, entry, input, reason) in [
            (
                SurveyLimits {
                    limbs: 0,
                    ..SurveyLimits::default()
                },
                g.start_state(),
                vec![],
                SurveyRefusal::Limbs,
            ),
            (
                SurveyLimits {
                    stack: 0,
                    ..SurveyLimits::default()
                },
                g.start_state(),
                vec![rs[0].symbol],
                SurveyRefusal::Stack,
            ),
            (
                SurveyLimits {
                    floor: 0,
                    ..SurveyLimits::default()
                },
                rs[2].entry,
                vec![rs[2].symbol],
                SurveyRefusal::Floor,
            ),
            (
                SurveyLimits {
                    births_per_token: 0,
                    ..SurveyLimits::default()
                },
                rs[2].entry,
                vec![rs[2].symbol],
                SurveyRefusal::Churn,
            ),
            (
                SurveyLimits {
                    effect_words: 0,
                    ..SurveyLimits::default()
                },
                g.start_state(),
                vec![],
                SurveyRefusal::Storage,
            ),
        ] {
            let mut c = g.survey_cursor_with_limits(limits).unwrap();
            c.set_confess(true);
            let out = c.run(entry, &input).unwrap();
            assert_eq!(out.refusal().unwrap().1, reason, "{out:?}");
            assert!(
                out.refusal().unwrap().2 > 0,
                "live limbs must survive refusal"
            );
            assert_eq!(out.confession().len(), out.refusal().unwrap().2);
        }
    }
    #[test]
    fn declared_reductions_are_all_explored_and_selected_actual_run_is_a_member() {
        let g = CompiledGrammar::compile(br#"{"name":"alternatives","rules":{
          "doc":{"type":"CHOICE","members":[
            {"type":"SEQ","members":[{"type":"SYMBOL","name":"A"},{"type":"STRING","value":"y"}]},
            {"type":"SEQ","members":[{"type":"SYMBOL","name":"B"},{"type":"STRING","value":"y"},{"type":"STRING","value":"z"}]}]},
          "A":{"type":"SYMBOL","name":"item"},"B":{"type":"SYMBOL","name":"item"},
          "item":{"type":"PATTERN","value":"x"}},"conflicts":[["A","B"]]}"#).unwrap();
        let mut session = g.session();
        session.set_trace_enabled(true);
        session.parse(b"xyz").unwrap();
        let rs = session.selected_tokens().unwrap();
        let mut c = g.survey_cursor().unwrap();
        c.set_exact(true);
        let prefix = yielded(
            c.run(
                g.start_state(),
                &rs[..2].iter().map(|r| r.symbol).collect::<Vec<_>>(),
            )
            .unwrap(),
        );
        assert_eq!(prefix.len(), 2, "RR alternatives both survive the y cut");
        let mut actual = g.effect_store();
        let (e, _) = session
            .product_range(0..rs[1].moves.end, &mut actual, 100_000)
            .unwrap();
        assert!(
            c.contains_actual(&prefix, &actual.describe(e).unwrap())
                .unwrap()
        );
        let suffix = yielded(c.run(rs[2].entry, &[rs[2].symbol]).unwrap());
        let chained = product(c.product_grounded(&prefix, &suffix).unwrap());
        let whole = yielded(
            c.run(
                g.start_state(),
                &rs.iter().map(|r| r.symbol).collect::<Vec<_>>(),
            )
            .unwrap(),
        );
        assert_eq!(
            whole.len(),
            1,
            "later token rejects the other speculative reading"
        );
        assert!(c.same_effects(&whole, &chained).unwrap());
    }
    #[test]
    fn reverse_rewinds_exclude_terminal_edges_that_static_precedence_removed() {
        let g=CompiledGrammar::compile(br#"{"name":"inactive","rules":{
          "doc":{"type":"CHOICE","members":[
            {"type":"SEQ","members":[{"type":"SYMBOL","name":"A"},{"type":"STRING","value":"x"}]},
            {"type":"SEQ","members":[{"type":"STRING","value":"a"},{"type":"STRING","value":"b"},{"type":"STRING","value":"x"},{"type":"STRING","value":"z"}]}]},
          "A":{"type":"PREC","value":1,"content":{"type":"SEQ","members":[{"type":"STRING","value":"a"},{"type":"STRING","value":"b"}]}}}}"#).unwrap();
        let c = g.survey_cursor().unwrap();
        let mut removed = 0;
        for raw in 0..g.state_count() {
            let from = StateId::from_index(raw);
            for (symbol, to) in g.automaton.state_transitions(from) {
                if g.automaton.symbol(symbol).lexis.is_some()
                    && !g
                        .automaton
                        .actions(from, Lookahead::Terminal(symbol))
                        .contains(&Action::Shift(to))
                {
                    removed += 1;
                    assert!(
                        !c.reverse[to.index()]
                            .get(&symbol)
                            .is_some_and(|qs| qs.contains(&from))
                    );
                }
            }
        }
        assert!(
            removed > 0,
            "fixture must retain a raw edge eliminated by a static winner"
        );
    }
    #[test]
    fn description_and_aggregate_census_share_finite_copy_work() {
        let g = grammar();
        let mut c = g.survey_cursor().unwrap();
        let e = yielded(c.run(g.start_state(), &tokens(&g, &["a", "x"])).unwrap())[0];
        let words = c.description_work(e).unwrap();
        assert!(words > 1);
        c.set_work_limit(words - 1);
        assert!(matches!(
            c.describe(e),
            Err(SurveyError::Limit {
                resource: "description work",
                ..
            })
        ));
        assert_eq!(c.work(), 0);
        c.set_work_limit(words);
        c.describe(e).unwrap();
        assert_eq!(c.work(), words);
        c.set_work_limit(2);
        assert!(matches!(
            c.survey(&[g.start_state(); 3], &[]),
            Err(SurveyError::Limit {
                resource: "aggregate work",
                ..
            })
        ));
        assert_eq!(c.limits().work, 2);
        c.set_work_limit(10_000);
        let report = c.survey(&[g.start_state()], &tokens(&g, &["a"])).unwrap();
        assert_eq!(report.domain, 1);
        assert_eq!(c.work(), report.work);
        assert!(report.work <= 10_000);
    }
    #[test]
    fn aggregate_refusal_retains_work_spent_validating_tokens() {
        let g = crate::CompiledGrammar::compile(
            br#"{"rules":{"doc":{"type":"REPEAT1","content":{"type":"STRING","value":"x"}}}}"#,
        )
        .unwrap();
        let mut input = vec![g.symbol_id("x").unwrap(); 10_000];
        input[9_999] = g.start_symbol();
        let mut cursor = g.survey_cursor().unwrap();
        assert!(matches!(
            cursor.run(g.start_state(), &input),
            Err(SurveyError::Token(_))
        ));
        let validation = cursor.work();
        assert_eq!(validation, input.len());
        let limit = cursor.limits().work;
        assert!(matches!(
            cursor.survey(&[g.start_state()], &input),
            Err(SurveyError::Token(_))
        ));
        assert_eq!(cursor.work(), 1 + validation);
        assert_eq!(cursor.limits().work, limit);
        assert!(cursor.survey(&[g.start_state()], &[]).is_ok());
    }
    #[test]
    fn exact_guards_reject_other_completed_history_and_three_segment_products_associate() {
        let g = grammar();
        let rs = receipt(&g, b"axz");
        let mut c = g.survey_cursor().unwrap();
        c.set_exact(true);
        let left = yielded(
            c.run(g.start_state(), &[rs[0].symbol, rs[1].symbol])
                .unwrap(),
        );
        let right = yielded(c.run(rs[2].entry, &[rs[2].symbol]).unwrap());
        assert_eq!(right.len(), 2);
        let y = tokens(&g, &["y"])[0];
        let other=*right.iter().find(|&&e|matches!(c.describe(e).unwrap(),EffectDescription::Run{ledger,..} if ledger[0].symbols==Constraint::Finite(vec![y]))).unwrap();
        assert!(
            product(c.product(&left, &[other]).unwrap()).is_empty(),
            "the other symbol history cannot survive composition"
        );
        let a = yielded(c.run(g.start_state(), &[rs[0].symbol]).unwrap());
        let x = yielded(c.run(rs[1].entry, &[rs[1].symbol]).unwrap());
        let z = yielded(c.run(rs[2].entry, &[rs[2].symbol]).unwrap());
        let ax = product(c.product(&a, &x).unwrap());
        let left_assoc = product(c.product(&ax, &z).unwrap());
        let xz = product(c.product(&x, &z).unwrap());
        let right_assoc = product(c.product(&a, &xz).unwrap());
        assert!(c.same_effects(&left_assoc, &right_assoc).unwrap());
        let whole = yielded(
            c.run(
                g.start_state(),
                &rs.iter().map(|r| r.symbol).collect::<Vec<_>>(),
            )
            .unwrap(),
        );
        assert!(c.same_effects(&left_assoc, &whole).unwrap());
    }
    #[test]
    fn work_refusal_during_fusion_keeps_a_truthful_nonempty_confession() {
        let g = grammar();
        let rs = receipt(&g, b"axz");
        let mut found = false;
        for allowance in 2..200 {
            let mut c = g
                .survey_cursor_with_limits(SurveyLimits {
                    work: allowance,
                    ..SurveyLimits::default()
                })
                .unwrap();
            c.set_confess(true);
            let outcome = c.run(rs[2].entry, &[rs[2].symbol]).unwrap();
            if let Some((_, SurveyRefusal::Work, limbs)) = outcome.refusal() {
                assert!(
                    limbs > 0,
                    "after token preflight, resource failure retains live readings"
                );
                assert_eq!(limbs, outcome.confession().len());
                found = true;
            }
            assert!(c.work() <= allowance);
        }
        assert!(found);
    }
    #[test]
    fn real_json_segments_preserve_the_selected_token_effect_across_every_width() {
        let g = CompiledGrammar::compile(include_bytes!("../../test/grammar/json.json")).unwrap();
        let mut session = g.session();
        session.set_trace_enabled(true);
        session
            .parse(br#" {"n":[true,false,null,1,"x"],"v":{"a":2}} "#)
            .unwrap();
        let rs = session.selected_tokens().unwrap();
        let input: Vec<_> = rs.iter().map(|r| r.symbol).collect();
        let mut actual = g.effect_store();
        let (effect, _) = session
            .product_range(0..rs.last().unwrap().moves.end, &mut actual, 1_000_000)
            .unwrap();
        let expected = actual.describe(effect).unwrap();
        let mut c = g.survey_cursor().unwrap();
        c.set_exact(true);
        let whole = yielded(c.run(g.start_state(), &input).unwrap());
        assert!(c.contains_actual(&whole, &expected).unwrap());
        for width in 1..=input.len() {
            let mut live = vec![c.identity()];
            for low in (0..input.len()).step_by(width) {
                let high = (low + width).min(input.len());
                let ways = yielded(c.run(rs[low].entry, &input[low..high]).unwrap());
                live = product(c.product_grounded(&live, &ways).unwrap());
                assert!(!live.is_empty(), "width {width}, token {low}");
            }
            assert!(c.same_effects(&whole, &live).unwrap(), "width {width}");
            assert!(
                c.contains_actual(&live, &expected).unwrap(),
                "width {width}"
            );
        }
    }
    #[test]
    fn multifloor_path_products_precharge_search_and_diagnostic_copies_have_a_separate_cap() {
        let g = grammar();
        let mut c = g.survey_cursor().unwrap();
        let symbol = tokens(&g, &["a"])[0];
        let states = (0..g.state_count())
            .map(StateId::from_index)
            .collect::<Vec<_>>();
        let description = EffectDescription::Run {
            entry: g.start_state(),
            ledger: vec![Claim {
                states: Constraint::Finite(states),
                symbols: Constraint::Any,
            }],
            push: vec![symbol; 100],
        };
        let EffectDescription::Run {
            entry,
            ref ledger,
            ref push,
        } = description
        else {
            panic!()
        };
        let e = c
            .store
            .exploratory(entry, ledger.clone(), push.clone())
            .unwrap();
        let measure = EffectMeasure::of(&description);
        c.weights.insert(e, measure);
        // This permits copying both payloads but cannot pay the multi-floor
        // transition search. Refusal occurs before compose/interner allocation.
        c.set_work_limit(measure.words * 16 + 100);
        let before = c.effect_words;
        assert_eq!(
            c.product(&[e], &[e]).unwrap().refusal().unwrap().0,
            SurveyRefusal::Work
        );
        assert_eq!(c.effect_words, before);
        assert_eq!(c.work(), 2, "only the handle roster was inspected");
        c.set_limits(SurveyLimits {
            limbs: 0,
            diagnostic_words: 0,
            ..SurveyLimits::default()
        })
        .unwrap();
        c.set_confess(true);
        let out = c.run(g.start_state(), &[]).unwrap();
        assert_eq!(out.refusal(), Some((0, SurveyRefusal::Limbs, 1)));
        assert!(!out.confession_complete());
        assert!(out.confession().is_empty());
    }
}
