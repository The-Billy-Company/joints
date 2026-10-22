//! Guarded stack effects behind one store-owned interning boundary.
//!
//! A run describes what it removed below its entry stack and what it pushed.
//! The ledger retains constraints at every removed depth: keeping only its
//! deepest state loses interior constraints when products are reassociated.

use std::collections::HashMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};

use crate::compiler::Automaton;
use crate::ids::{ProductionId, StateId, SymbolId};

static NEXT_STORE: AtomicU64 = AtomicU64::new(1);

/// An opaque product. Runs belong to one store; identity and zero are universal.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct Effect(Repr);

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
enum Repr {
    Identity,
    Zero,
    Run { owner: u64, index: u32 },
}

impl Effect {
    pub const IDENTITY: Self = Self(Repr::Identity);
    pub const ZERO: Self = Self(Repr::Zero);

    pub fn is_zero(self) -> bool {
        matches!(self.0, Repr::Zero)
    }
}

/// Any is unconstrained; a finite empty set admits nothing.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum Constraint<T> {
    Any,
    Finite(Vec<T>),
}

impl<T: Ord> Constraint<T> {
    fn finite(mut values: Vec<T>) -> Self {
        values.sort_unstable();
        values.dedup();
        Self::Finite(values)
    }

    fn admits(&self, value: &T) -> bool {
        match self {
            Self::Any => true,
            Self::Finite(values) => values.binary_search(value).is_ok(),
        }
    }

    fn is_empty(&self) -> bool {
        matches!(self, Self::Finite(values) if values.is_empty())
    }
}

/// One popped symbol and the automaton state immediately underneath it.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct Claim {
    pub states: Constraint<StateId>,
    pub symbols: Constraint<SymbolId>,
}

/// Canonical values for inspection; no interning IDs escape through this view.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum EffectDescription {
    Identity,
    Zero,
    Run {
        entry: StateId,
        /// Nearest popped symbol first: element zero is depth one.
        ledger: Vec<Claim>,
        /// Symbols left standing, from the bottom of the stack to the top.
        push: Vec<SymbolId>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum EffectError {
    #[error("effect belongs to another store")]
    ForeignStore,
    #[error("move trace belongs to another automaton")]
    ForeignAutomaton,
    #[error("no completed parse move trace is available")]
    UnfinishedRun,
    #[error("move range is outside the completed trace")]
    InvalidTraceRange,
    #[error("move-range product exceeded its work limit")]
    TraceWorkLimit,
    #[error("effect handle is invalid")]
    InvalidHandle,
    #[error("automaton state {0:?} is invalid")]
    InvalidState(StateId),
    #[error("grammar symbol {0:?} is invalid")]
    InvalidSymbol(SymbolId),
    #[error("production {0:?} is invalid")]
    InvalidProduction(ProductionId),
    #[error("the right-hand side has no path from the supplied state")]
    NoSuchParse,
    #[error("invalid speculative effect guard: {0}")]
    InvalidGuard(&'static str),
    #[error("effect storage exceeds its index range")]
    CapacityExceeded,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
struct Run {
    entry: StateId,
    ledger: Vec<Claim>,
    push: Vec<SymbolId>,
}

/// Owns all canonical effects and working storage for one document or worker.
///
/// Whole runs are interned initially. A handle comparison stays constant time;
/// hashing and constructing a new product may walk its sequences. This avoids
/// introducing persistent prefix machinery before its cost has been measured.
pub struct EffectStore {
    owner: u64,
    graph: Arc<Automaton>,
    runs: Vec<Arc<Run>>,
    interned: HashMap<Arc<Run>, u32>,
}

impl EffectStore {
    pub(crate) fn new(graph: Arc<Automaton>) -> Self {
        let owner = NEXT_STORE
            .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |n| n.checked_add(1))
            .expect("effect-store identifiers exhausted");
        Self {
            owner,
            graph,
            runs: Vec::new(),
            interned: HashMap::new(),
        }
    }

    pub(crate) fn automaton(&self) -> &Arc<Automaton> {
        &self.graph
    }

    pub(crate) fn owner_id(&self) -> u64 {
        self.owner
    }

    pub(crate) fn validate_effect(&self, effect: Effect) -> Result<(), EffectError> {
        self.validate(effect)
    }

    /// Import a computed speculative yield without exposing raw interned handles.
    /// Every debt retains a symbol guard; a finite deepest floor is required by
    /// composition. Validate all domains before an empty constraint absorbs them.
    pub(crate) fn exploratory(
        &mut self,
        entry: StateId,
        mut ledger: Vec<Claim>,
        push: Vec<SymbolId>,
    ) -> Result<Effect, EffectError> {
        self.check_state(entry)?;
        for claim in &mut ledger {
            if let Constraint::Finite(states) = &mut claim.states {
                for &state in states.iter() {
                    self.check_state(state)?;
                }
                states.sort_unstable();
                states.dedup();
            }
            if let Constraint::Finite(symbols) = &mut claim.symbols {
                for &symbol in symbols.iter() {
                    self.check_symbol(symbol)?;
                }
                symbols.sort_unstable();
                symbols.dedup();
            }
        }
        for &symbol in &push {
            self.check_symbol(symbol)?;
        }
        if ledger
            .last()
            .is_some_and(|claim| matches!(claim.states, Constraint::Any))
        {
            return Err(EffectError::InvalidGuard(
                "a nonempty ledger needs a finite deepest floor",
            ));
        }
        self.intern(Run {
            entry,
            ledger,
            push,
        })
    }

    /// A shift may read a terminal or lift a completed nonterminal.
    pub fn shift(&mut self, at: StateId, symbol: SymbolId) -> Result<Effect, EffectError> {
        self.check_state(at)?;
        self.check_symbol(symbol)?;
        self.intern(Run {
            entry: at,
            ledger: Vec::new(),
            push: vec![symbol],
        })
    }

    pub fn reduce(
        &mut self,
        under: StateId,
        production: ProductionId,
    ) -> Result<Effect, EffectError> {
        self.check_state(under)?;
        if production.index() >= self.graph.production_count() {
            return Err(EffectError::InvalidProduction(production));
        }
        let rule = self.graph.production(production);
        let mut entry = under;
        let mut ledger = Vec::with_capacity(rule.steps.len());
        for step in &rule.steps {
            entry = self
                .graph
                .transition(entry, step.symbol)
                .ok_or(EffectError::NoSuchParse)?;
            ledger.push(Claim {
                states: Constraint::Any,
                symbols: Constraint::finite(vec![step.symbol]),
            });
        }
        // The reduction consulted only the state under its complete RHS.
        if let Some(deepest) = ledger.first_mut() {
            deepest.states = Constraint::finite(vec![under]);
        }
        ledger.reverse();
        self.intern(Run {
            entry,
            ledger,
            push: vec![rule.lhs],
        })
    }

    /// Compose in source order. An impossible pairing produces absorbing zero.
    pub fn compose(&mut self, left: Effect, right: Effect) -> Result<Effect, EffectError> {
        // Validate both operands even when zero could otherwise hide misuse.
        self.validate(left)?;
        self.validate(right)?;
        match (left.0, right.0) {
            (Repr::Zero, _) | (_, Repr::Zero) => return Ok(Effect::ZERO),
            (Repr::Identity, _) => return Ok(right),
            (_, Repr::Identity) => return Ok(left),
            _ => {}
        }
        let a = Arc::clone(self.run(left)?);
        let b = Arc::clone(self.run(right)?);
        let mut ledger = a.ledger.clone();
        if let Some(deepest) = ledger.last_mut() {
            let Constraint::Finite(floors) = &deepest.states else {
                // All constructors retain a finite, nonempty live floor.
                return Err(EffectError::InvalidHandle);
            };
            let survivors: Vec<_> = floors
                .iter()
                .copied()
                .filter(|&from| self.survives(&a.push, &b, from))
                .collect();
            if survivors.is_empty() {
                return Ok(Effect::ZERO);
            }
            deepest.states = Constraint::Finite(survivors);
        } else if !self.survives(&a.push, &b, a.entry) {
            return Ok(Effect::ZERO);
        }

        let left_depth = a.push.len();
        let eaten = b.ledger.len();
        let push = if left_depth >= eaten {
            let mut kept = a.push[..left_depth - eaten].to_vec();
            kept.extend_from_slice(&b.push);
            kept
        } else {
            // Debts below the left run's visible push lie below its own
            // ledger, not in place of it. Never discard the interior claims.
            ledger.extend_from_slice(&b.ledger[left_depth..]);
            b.push.clone()
        };
        self.intern(Run {
            entry: a.entry,
            ledger,
            push,
        })
    }

    pub fn fold(
        &mut self,
        effects: impl IntoIterator<Item = Effect>,
    ) -> Result<Effect, EffectError> {
        let mut product = Effect::IDENTITY;
        for effect in effects {
            product = self.compose(product, effect)?;
        }
        Ok(product)
    }

    pub fn grounded(&self, effect: Effect) -> Result<bool, EffectError> {
        self.validate(effect)?;
        match effect.0 {
            Repr::Identity => Ok(true),
            Repr::Zero => Ok(false),
            Repr::Run { .. } => Ok(self.run(effect)?.ledger.is_empty()),
        }
    }

    pub fn describe(&self, effect: Effect) -> Result<EffectDescription, EffectError> {
        self.validate(effect)?;
        Ok(match effect.0 {
            Repr::Identity => EffectDescription::Identity,
            Repr::Zero => EffectDescription::Zero,
            Repr::Run { .. } => {
                let run = self.run(effect)?;
                EffectDescription::Run {
                    entry: run.entry,
                    ledger: run.ledger.clone(),
                    push: run.push.clone(),
                }
            }
        })
    }

    fn survives(&self, push: &[SymbolId], right: &Run, from: StateId) -> bool {
        let mut state = from;
        for (i, &symbol) in push.iter().enumerate() {
            let depth = push.len() - i;
            if let Some(claim) = right.ledger.get(depth - 1) {
                if !claim.states.admits(&state) || !claim.symbols.admits(&symbol) {
                    return false;
                }
            }
            let Some(next) = self.graph.transition(state, symbol) else {
                return false;
            };
            state = next;
        }
        state == right.entry
    }

    fn intern(&mut self, run: Run) -> Result<Effect, EffectError> {
        if run
            .ledger
            .iter()
            .any(|claim| claim.states.is_empty() || claim.symbols.is_empty())
        {
            return Ok(Effect::ZERO);
        }
        let index = if let Some(&index) = self.interned.get(&run) {
            index
        } else {
            let index =
                u32::try_from(self.runs.len()).map_err(|_| EffectError::CapacityExceeded)?;
            let run = Arc::new(run);
            self.interned.insert(Arc::clone(&run), index);
            self.runs.push(run);
            index
        };
        Ok(Effect(Repr::Run {
            owner: self.owner,
            index,
        }))
    }

    fn validate(&self, effect: Effect) -> Result<(), EffectError> {
        if let Repr::Run { owner, index } = effect.0 {
            if owner != self.owner {
                return Err(EffectError::ForeignStore);
            }
            if index as usize >= self.runs.len() {
                return Err(EffectError::InvalidHandle);
            }
        }
        Ok(())
    }

    fn run(&self, effect: Effect) -> Result<&Arc<Run>, EffectError> {
        self.validate(effect)?;
        match effect.0 {
            Repr::Run { index, .. } => Ok(&self.runs[index as usize]),
            _ => Err(EffectError::InvalidHandle),
        }
    }

    fn check_state(&self, state: StateId) -> Result<(), EffectError> {
        if state.index() >= self.graph.state_count() {
            Err(EffectError::InvalidState(state))
        } else {
            Ok(())
        }
    }

    fn check_symbol(&self, symbol: SymbolId) -> Result<(), EffectError> {
        if symbol.index() >= self.graph.symbol_count() {
            Err(EffectError::InvalidSymbol(symbol))
        } else {
            Ok(())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const PARENS: &[u8] = br#"{"name":"parens","rules":{
        "document":{"type":"SYMBOL","name":"S"},
        "S":{"type":"CHOICE","members":[
            {"type":"SEQ","members":[{"type":"STRING","value":"("},
                {"type":"SYMBOL","name":"S"},{"type":"STRING","value":")"}]},
            {"type":"STRING","value":"x"}]}
        },"extras":[]}"#;

    struct Fixture {
        graph: Arc<Automaton>,
        store: EffectStore,
        lp: SymbolId,
        rp: SymbolId,
        x: SymbolId,
        s: SymbolId,
        atom: ProductionId,
        nested: ProductionId,
    }

    impl Fixture {
        fn new() -> Self {
            let graph = Arc::new(Automaton::from_tree_sitter(PARENS).unwrap());
            let symbol = |name| graph.symbol_by_name(name).unwrap();
            let (lp, rp, x, s) = (symbol("("), symbol(")"), symbol("x"), symbol("S"));
            let rule = |rhs: &[SymbolId]| {
                (0..graph.production_count())
                    .map(ProductionId::from_index)
                    .find(|&id| {
                        let p = graph.production(id);
                        p.lhs == s && p.steps.iter().map(|s| s.symbol).eq(rhs.iter().copied())
                    })
                    .unwrap()
            };
            let (atom, nested) = (rule(&[x]), rule(&[lp, s, rp]));
            Self {
                store: EffectStore::new(Arc::clone(&graph)),
                graph,
                lp,
                rp,
                x,
                s,
                atom,
                nested,
            }
        }

        fn took(
            &mut self,
            entry: StateId,
            pop: &[SymbolId],
            under: &[StateId],
            push: &[SymbolId],
        ) -> Effect {
            let mut ledger: Vec<_> = pop
                .iter()
                .rev()
                .map(|&symbol| Claim {
                    states: Constraint::Any,
                    symbols: Constraint::Finite(vec![symbol]),
                })
                .collect();
            if let Some(deepest) = ledger.last_mut() {
                deepest.states = Constraint::finite(under.to_vec());
            }
            self.store
                .intern(Run {
                    entry,
                    ledger,
                    push: push.to_vec(),
                })
                .unwrap()
        }

        fn inside(&self) -> StateId {
            self.graph
                .transition(self.graph.start_state(), self.lp)
                .unwrap()
        }

        fn walk(&self, from: StateId, symbols: &[SymbolId]) -> StateId {
            symbols
                .iter()
                .fold(from, |s, &symbol| self.graph.transition(s, symbol).unwrap())
        }
    }

    #[test]
    fn speculative_yields_validate_every_domain_and_preserve_canonical_guards() {
        let mut f = Fixture::new();
        let start = f.graph.start_state();
        let entry = f.walk(start, &[f.x]);
        let expected = f.store.reduce(start, f.atom).unwrap();
        let ledger = vec![Claim {
            states: Constraint::Finite(vec![start, start]),
            symbols: Constraint::Finite(vec![f.x, f.x]),
        }];
        assert_eq!(
            f.store.exploratory(entry, ledger, vec![f.s]).unwrap(),
            expected
        );
        assert!(matches!(
            f.store.exploratory(
                entry,
                vec![Claim {
                    states: Constraint::Any,
                    symbols: Constraint::Any
                }],
                vec![]
            ),
            Err(EffectError::InvalidGuard(_))
        ));
        let invalid_state = StateId::from_index(f.graph.state_count());
        let invalid_symbol = SymbolId::from_index(f.graph.symbol_count());
        assert_eq!(
            f.store.exploratory(invalid_state, vec![], vec![]),
            Err(EffectError::InvalidState(invalid_state))
        );
        // ZERO must not hide a bad symbol or a bad state in another constraint.
        let empty = Claim {
            states: Constraint::Finite(vec![]),
            symbols: Constraint::Any,
        };
        assert_eq!(
            f.store
                .exploratory(entry, vec![empty.clone()], vec![invalid_symbol]),
            Err(EffectError::InvalidSymbol(invalid_symbol))
        );
        assert_eq!(
            f.store.exploratory(
                entry,
                vec![
                    Claim {
                        states: Constraint::Finite(vec![invalid_state]),
                        symbols: Constraint::Any
                    },
                    empty.clone()
                ],
                vec![]
            ),
            Err(EffectError::InvalidState(invalid_state))
        );
        assert_eq!(
            f.store.exploratory(
                entry,
                vec![
                    Claim {
                        states: Constraint::Finite(vec![start]),
                        symbols: Constraint::Finite(vec![invalid_symbol])
                    },
                    empty.clone()
                ],
                vec![]
            ),
            Err(EffectError::InvalidSymbol(invalid_symbol))
        );
        assert_eq!(
            f.store.exploratory(entry, vec![empty], vec![]).unwrap(),
            Effect::ZERO
        );
        let scoped_empty = f.store.exploratory(start, vec![], vec![]).unwrap();
        assert_eq!(
            f.store.describe(scoped_empty).unwrap(),
            EffectDescription::Run {
                entry: start,
                ledger: vec![],
                push: vec![]
            }
        );
    }

    #[test]
    fn identity_zero_and_canonical_handles_are_distinct() {
        let mut f = Fixture::new();
        let effect = f.store.shift(f.graph.start_state(), f.x).unwrap();
        assert_eq!(effect, f.store.shift(f.graph.start_state(), f.x).unwrap());
        assert_eq!(effect, f.store.compose(Effect::IDENTITY, effect).unwrap());
        assert_eq!(effect, f.store.compose(effect, Effect::IDENTITY).unwrap());
        for neighbor in [Effect::IDENTITY, Effect::ZERO, effect] {
            assert_eq!(
                Effect::ZERO,
                f.store.compose(Effect::ZERO, neighbor).unwrap()
            );
            assert_eq!(
                Effect::ZERO,
                f.store.compose(neighbor, Effect::ZERO).unwrap()
            );
        }
        assert!(f.store.grounded(Effect::IDENTITY).unwrap());
        assert!(!f.store.grounded(Effect::ZERO).unwrap());
        assert!(Constraint::<StateId>::Any.admits(&f.graph.start_state()));
        assert!(!Constraint::<StateId>::Finite(vec![]).admits(&f.graph.start_state()));
    }

    #[test]
    fn every_sample_triple_associates_with_both_defined_and_refused_cases() {
        let mut f = Fixture::new();
        let (start, inside) = (f.graph.start_state(), f.inside());
        let pushes = [vec![], vec![f.x], vec![f.lp, f.s]];
        let pops = [vec![f.x], vec![f.s, f.rp]];
        let floors = [vec![start], vec![start, inside]];
        let mut sample = vec![Effect::IDENTITY, Effect::ZERO];
        for i in 0..f.graph.state_count().min(3) {
            let entry = StateId::from_index(i);
            for push in &pushes {
                sample.push(f.took(entry, &[], &[], push));
                for pop in &pops {
                    for under in &floors {
                        sample.push(f.took(entry, pop, under, push));
                    }
                }
            }
        }
        let mut defined = 0;
        let mut refused = 0;
        for &a in &sample {
            for &b in &sample {
                for &c in &sample {
                    let ab = f.store.compose(a, b).unwrap();
                    let bc = f.store.compose(b, c).unwrap();
                    let left = f.store.compose(ab, c).unwrap();
                    let right = f.store.compose(a, bc).unwrap();
                    assert_eq!(left, right, "triple {a:?}, {b:?}, {c:?}");
                    if left.is_zero() {
                        refused += 1;
                    } else {
                        defined += 1;
                    }
                }
            }
        }
        assert!(defined > 0 && refused > 0);
    }

    #[test]
    fn interior_states_and_symbols_survive_a_pop_beyond_the_left_push() {
        let mut f = Fixture::new();
        let start = f.graph.start_state();
        let opened = f.walk(start, &[f.lp, f.s]);
        let closed = f.walk(start, &[f.lp, f.s, f.rp]);
        let shallow = f.took(closed, &[f.rp], &[opened], &[f.rp]);
        let deep = f.store.reduce(start, f.nested).unwrap();
        let owing = f.store.compose(shallow, deep).unwrap();
        let EffectDescription::Run {
            entry,
            ledger,
            push,
        } = f.store.describe(owing).unwrap()
        else {
            panic!("a real debt must remain a run");
        };
        assert_eq!(entry, closed);
        assert_eq!(push, [f.s]);
        assert_eq!(ledger.len(), 3);
        for (claim, symbol) in ledger.iter().zip([f.rp, f.s, f.lp]) {
            assert_eq!(claim.symbols, Constraint::Finite(vec![symbol]));
        }
        assert_eq!(ledger[0].states, Constraint::Finite(vec![opened]));
        assert_eq!(ledger[1].states, Constraint::Any);
        assert_eq!(ledger[2].states, Constraint::Finite(vec![start]));
        assert!(!f.store.grounded(owing).unwrap());

        let covering = f.took(start, &[], &[], &[f.lp, f.s, f.rp]);
        let joined = f.store.compose(covering, owing).unwrap();
        assert!(!joined.is_zero());
        assert!(f.store.grounded(joined).unwrap());
    }

    #[test]
    fn symbol_constraints_floor_constraints_and_entry_state_all_matter() {
        let mut f = Fixture::new();
        let (start, inside) = (f.graph.start_state(), f.inside());
        let after_x = f.walk(start, &[f.x]);
        let left = f.store.shift(start, f.x).unwrap();
        let right = f.store.reduce(start, f.atom).unwrap();
        assert!(!f.store.compose(left, right).unwrap().is_zero());
        let wrong_symbol = f.took(after_x, &[f.lp], &[start], &[f.s]);
        assert!(f.store.compose(left, wrong_symbol).unwrap().is_zero());
        let wrong_floor = f.took(after_x, &[f.x], &[inside], &[f.s]);
        assert!(f.store.compose(left, wrong_floor).unwrap().is_zero());
        let wrong_entry = f.took(start, &[f.x], &[start], &[f.s]);
        assert!(f.store.compose(left, wrong_entry).unwrap().is_zero());

        let held = f.took(after_x, &[f.x], &[inside, start, inside], &[f.s]);
        let close_at = f.walk(inside, &[f.s]);
        let close = f.store.shift(close_at, f.rp).unwrap();
        let settled = f.store.compose(held, close).unwrap();
        let EffectDescription::Run { ledger, .. } = f.store.describe(settled).unwrap() else {
            panic!("one floor must survive");
        };
        assert_eq!(ledger[0].states, Constraint::Finite(vec![inside]));
    }

    /// Apply the inspected summary to a concrete stack without using compose.
    /// States are reconstructed independently from the complete stack prefix.
    fn apply(f: &Fixture, effect: Effect, input: &[SymbolId]) -> Option<Vec<SymbolId>> {
        let mut states = vec![f.graph.start_state()];
        for &symbol in input {
            states.push(f.graph.transition(*states.last()?, symbol)?);
        }
        match f.store.describe(effect).unwrap() {
            EffectDescription::Zero => None,
            EffectDescription::Identity => Some(input.to_vec()),
            EffectDescription::Run {
                entry,
                ledger,
                push,
            } => {
                if states.last()? != &entry || ledger.len() > input.len() {
                    return None;
                }
                for (i, claim) in ledger.iter().enumerate() {
                    let at = input.len() - i - 1;
                    if !claim.states.admits(&states[at]) || !claim.symbols.admits(&input[at]) {
                        return None;
                    }
                }
                let mut out = input[..input.len() - ledger.len()].to_vec();
                let mut state = states[out.len()];
                for symbol in push {
                    state = f.graph.transition(state, symbol)?;
                    out.push(symbol);
                }
                Some(out)
            }
        }
    }

    fn trace(
        f: &mut Fixture,
        depth: usize,
        stack: &mut Vec<SymbolId>,
        states: &mut Vec<StateId>,
        effects: &mut Vec<Effect>,
        snapshots: &mut Vec<Vec<SymbolId>>,
    ) {
        fn read(
            f: &mut Fixture,
            symbol: SymbolId,
            stack: &mut Vec<SymbolId>,
            states: &mut Vec<StateId>,
            effects: &mut Vec<Effect>,
            snapshots: &mut Vec<Vec<SymbolId>>,
        ) {
            let from = *states.last().unwrap();
            effects.push(f.store.shift(from, symbol).unwrap());
            states.push(f.graph.transition(from, symbol).unwrap());
            stack.push(symbol);
            snapshots.push(stack.clone());
        }
        if depth == 0 {
            let symbol = f.x;
            read(f, symbol, stack, states, effects, snapshots);
        } else {
            let symbol = f.lp;
            read(f, symbol, stack, states, effects, snapshots);
            trace(f, depth - 1, stack, states, effects, snapshots);
            let symbol = f.rp;
            read(f, symbol, stack, states, effects, snapshots);
        }
        let production = if depth == 0 { f.atom } else { f.nested };
        let rule = f.graph.production(production);
        let remaining = stack.len() - rule.steps.len();
        assert!(
            stack[remaining..]
                .iter()
                .copied()
                .eq(rule.steps.iter().map(|s| s.symbol))
        );
        let under = states[remaining];
        let lhs = rule.lhs;
        effects.push(f.store.reduce(under, production).unwrap());
        stack.truncate(remaining);
        states.truncate(remaining + 1);
        states.push(f.graph.transition(under, lhs).unwrap());
        stack.push(lhs);
        snapshots.push(stack.clone());
    }

    #[test]
    fn every_real_trace_segment_agrees_with_a_concrete_stack_and_every_split() {
        for depth in 0..=4 {
            let mut f = Fixture::new();
            let (mut stack, mut states) = (vec![], vec![f.graph.start_state()]);
            let (mut effects, mut snapshots) = (vec![], vec![vec![]]);
            trace(
                &mut f,
                depth,
                &mut stack,
                &mut states,
                &mut effects,
                &mut snapshots,
            );
            let whole = f.store.fold(effects.iter().copied()).unwrap();
            assert_eq!(apply(&f, whole, &[]), Some(vec![f.s]));
            for cut in 0..=effects.len() {
                let left = f.store.fold(effects[..cut].iter().copied()).unwrap();
                let right = f.store.fold(effects[cut..].iter().copied()).unwrap();
                assert_eq!(whole, f.store.compose(left, right).unwrap());
            }
            for from in 0..=effects.len() {
                for to in from..=effects.len() {
                    let segment = f.store.fold(effects[from..to].iter().copied()).unwrap();
                    assert_eq!(
                        apply(&f, segment, &snapshots[from]),
                        Some(snapshots[to].clone())
                    );
                }
            }
        }
    }

    #[test]
    fn foreign_handles_and_invalid_grammar_ids_are_errors_even_beside_zero() {
        let mut f = Fixture::new();
        let effect = f.store.shift(f.graph.start_state(), f.x).unwrap();
        let mut other = EffectStore::new(Arc::clone(&f.graph));
        assert_eq!(
            other.compose(Effect::ZERO, effect),
            Err(EffectError::ForeignStore)
        );
        assert_eq!(other.describe(effect), Err(EffectError::ForeignStore));
        assert_eq!(other.grounded(effect), Err(EffectError::ForeignStore));
        assert_eq!(other.fold([effect]), Err(EffectError::ForeignStore));
        let invalid = StateId::from_index(f.graph.state_count());
        assert_eq!(
            f.store.shift(invalid, f.x),
            Err(EffectError::InvalidState(invalid))
        );
        let invalid = SymbolId::from_index(f.graph.symbol_count());
        assert_eq!(
            f.store.shift(f.graph.start_state(), invalid),
            Err(EffectError::InvalidSymbol(invalid))
        );
        let invalid = ProductionId::from_index(f.graph.production_count());
        assert_eq!(
            f.store.reduce(f.graph.start_state(), invalid),
            Err(EffectError::InvalidProduction(invalid))
        );
    }
}
