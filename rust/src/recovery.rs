//! Bounded proofs over a borrowed LR stack. No syntax or scanner state changes.

use crate::compiler::{Action, Automaton, Lookahead, Pattern, Shape};
use crate::ids::ReductionId;
use crate::{StateId, SymbolId};
use std::cell::Cell;

/// Reads from every explored proof branch share this dependency floor. An
/// underflow/floor-dependent refusal requires the complete original stack.
pub(crate) struct ProofDepth {
    lowest: Cell<usize>,
    anchored: Cell<bool>,
}
impl ProofDepth {
    /// Seed with the top-state index: row metadata also depends on that state.
    pub(crate) fn new(top: usize) -> Self {
        Self {
            lowest: Cell::new(top),
            anchored: Cell::new(false),
        }
    }
    fn observe(&self, at: usize) {
        self.lowest.set(self.lowest.get().min(at));
    }
    fn anchor(&self) {
        self.anchored.set(true);
        self.lowest.set(0);
    }
    pub(crate) fn start(&self) -> usize {
        self.lowest.get()
    }
    pub(crate) fn anchored(&self) -> bool {
        self.anchored.get()
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Uncertain {
    Branch,
    Depth,
    Work,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Proof {
    Reads(StateId),
    Stops,
    Unknown(Uncertain),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Insertion {
    Unique(SymbolId),
    None,
    Ambiguous,
    Unknown(Uncertain),
}

#[derive(Clone)]
struct Stack<'a> {
    base: &'a [StateId],
    dependencies: Option<&'a ProofDepth>,
    kept: usize,
    overlay: [StateId; 8],
    overlay_len: usize,
}

impl<'a> Stack<'a> {
    fn new(base: &'a [StateId]) -> Self {
        Self {
            base,
            dependencies: None,
            kept: base.len(),
            overlay: [StateId::from_index(0); 8],
            overlay_len: 0,
        }
    }
    fn tracked(base: &'a [StateId], dependencies: &'a ProofDepth) -> Self {
        Self {
            dependencies: Some(dependencies),
            ..Self::new(base)
        }
    }
    fn anchor(&self) {
        if let Some(dependencies) = self.dependencies {
            dependencies.anchor();
        }
    }
    fn top(&self) -> Option<StateId> {
        if let Some(&state) = self.overlay[..self.overlay_len].last() {
            return Some(state);
        }
        let Some(at) = self.kept.checked_sub(1) else {
            self.anchor();
            return None;
        };
        self.state(at)
    }
    fn push(&mut self, state: StateId) -> bool {
        if self.overlay_len >= self.overlay.len() {
            self.anchor();
            return false;
        }
        let slot = &mut self.overlay[self.overlay_len];
        *slot = state;
        self.overlay_len += 1;
        true
    }
    fn state(&self, index: usize) -> Option<StateId> {
        let state = if index < self.kept {
            if let Some(dependencies) = self.dependencies {
                dependencies.observe(index);
            }
            self.base.get(index).copied()
        } else {
            self.overlay[..self.overlay_len]
                .get(index - self.kept)
                .copied()
        };
        if state.is_none() {
            self.anchor();
        }
        state
    }
    fn reduce(
        &mut self,
        graph: &Automaton,
        id: ReductionId,
        work: &mut usize,
        limit: usize,
    ) -> Result<(), Proof> {
        let rule = graph.reduction(id);
        let depth = self.kept + self.overlay_len;
        let Some(start) = depth.checked_sub(rule.width + 1) else {
            self.anchor();
            return Err(Proof::Stops);
        };
        // Even an immediately exhausted proof depends on this successful
        // non-underflow check. Retain enough borrowed depth to repeat it.
        if start < self.kept {
            if let Some(dependencies) = self.dependencies {
                dependencies.observe(start);
            }
        }
        // Quotient states may forget consumed symbol identity. Require a
        // concrete RHS whose transitions witness this exact state path before
        // using the family's shared pop width in an admission proof.
        let mut witnessed = false;
        for &id in &rule.productions {
            if *work == limit {
                return Err(Proof::Unknown(Uncertain::Work));
            }
            *work += 1;
            let production = graph.production(id);
            let mut matches = production.steps.len() == rule.width;
            for (offset, step) in production.steps.iter().enumerate() {
                if !matches {
                    break;
                }
                if *work == limit {
                    return Err(Proof::Unknown(Uncertain::Work));
                }
                *work += 1;
                matches = self.state(start + offset).is_some_and(|from| {
                    graph.transition(from, step.symbol) == self.state(start + offset + 1)
                });
            }
            if matches {
                witnessed = true;
                break;
            }
        }
        if !witnessed {
            return Err(Proof::Stops);
        }
        let virtual_pop = rule.width.min(self.overlay_len);
        self.overlay_len -= virtual_pop;
        let real_pop = rule.width - virtual_pop;
        if real_pop >= self.kept {
            self.anchor();
            return Err(Proof::Stops);
        }
        self.kept -= real_pop;
        let to = graph
            .transition(self.top().ok_or(Proof::Stops)?, rule.lhs)
            .ok_or(Proof::Stops)?;
        if !self.push(to) {
            return Err(Proof::Unknown(Uncertain::Depth));
        }
        Ok(())
    }
}

fn take(graph: &Automaton, stack: &mut Stack<'_>, symbol: SymbolId, work: &mut usize) -> Proof {
    let limit = work.saturating_add(256);
    for _ in 0..32 {
        if *work == limit {
            return Proof::Unknown(Uncertain::Work);
        }
        *work += 1;
        let Some(state) = stack.top() else {
            return Proof::Stops;
        };
        let actions = graph.actions(state, Lookahead::Terminal(symbol));
        if actions.len() > 1 {
            return Proof::Unknown(Uncertain::Branch);
        }
        match actions.first().copied() {
            Some(Action::Shift(to)) => return Proof::Reads(to),
            Some(Action::Reduce(id)) => {
                if let Err(answer) = stack.reduce(graph, id, work, limit) {
                    return answer;
                }
            }
            _ => return Proof::Stops,
        }
    }
    Proof::Unknown(Uncertain::Work)
}

/// Insertion requires a unique concrete continuation. Unknown is never a No.
pub(crate) fn insertion(
    graph: &Automaton,
    states: &[StateId],
    wanted: SymbolId,
) -> (Insertion, usize) {
    let mut found = None;
    let mut uncertain = None;
    let mut work = 0;
    for (symbol, lexis) in graph.lexical_rules() {
        if graph.symbol(symbol).shape != Shape::Anonymous
            || !matches!(lexis.pattern, Pattern::Literal(_))
        {
            continue;
        }
        let mut stack = Stack::new(states);
        let first = take(graph, &mut stack, symbol, &mut work);
        let answer = match first {
            Proof::Reads(to) if stack.push(to) => take(graph, &mut stack, wanted, &mut work),
            Proof::Reads(_) => Proof::Unknown(Uncertain::Depth),
            other => other,
        };
        match answer {
            Proof::Reads(_) => {
                if found.is_some() {
                    return (Insertion::Ambiguous, work);
                }
                found = Some(symbol);
            }
            Proof::Unknown(reason) => {
                uncertain.get_or_insert(reason);
            }
            Proof::Stops => {}
        }
    }
    (
        match (found, uncertain) {
            (_, Some(reason)) => Insertion::Unknown(reason),
            (Some(symbol), None) => Insertion::Unique(symbol),
            _ => Insertion::None,
        },
        work,
    )
}

/// Lexical admission is existential: inspect every declared reading. Exhaustion
/// keeps the token possible rather than claiming a proof of impossibility.
pub(crate) fn admission(graph: &Automaton, states: &[StateId], symbol: SymbolId) -> (Proof, usize) {
    admission_inner(graph, Stack::new(states), symbol)
}

pub(crate) fn admission_tracked(
    graph: &Automaton,
    states: &[StateId],
    symbol: SymbolId,
    dependencies: &ProofDepth,
) -> (Proof, usize) {
    admission_inner(graph, Stack::tracked(states, dependencies), symbol)
}

fn admission_inner(graph: &Automaton, mut stack: Stack<'_>, symbol: SymbolId) -> (Proof, usize) {
    let mut pending = Vec::new();
    let mut spent = 0;
    let mut uncertainty = None;
    loop {
        loop {
            if spent == 256 {
                return (Proof::Unknown(Uncertain::Work), spent);
            }
            spent += 1;
            let Some(state) = stack.top() else {
                break;
            };
            let actions = graph.actions(state, Lookahead::Terminal(symbol));
            if let Some(to) = actions.iter().find_map(|a| {
                if let Action::Shift(to) = a {
                    Some(*to)
                } else {
                    None
                }
            }) {
                return (Proof::Reads(to), spent);
            }
            for &action in actions.iter().skip(1) {
                if spent == 256 {
                    return (Proof::Unknown(Uncertain::Work), spent);
                }
                spent += 1;
                let Action::Reduce(id) = action else {
                    continue;
                };
                let mut branch = stack.clone();
                match branch.reduce(graph, id, &mut spent, 256) {
                    Ok(()) => pending.push(branch),
                    Err(Proof::Unknown(reason)) => {
                        uncertainty.get_or_insert(reason);
                    }
                    _ => {}
                }
            }
            match actions.first().copied() {
                Some(Action::Reduce(id)) => match stack.reduce(graph, id, &mut spent, 256) {
                    Ok(()) => {}
                    Err(Proof::Unknown(reason)) => {
                        uncertainty.get_or_insert(reason);
                        break;
                    }
                    _ => break,
                },
                _ => break,
            }
        }
        let Some(next) = pending.pop() else {
            break;
        };
        stack = next;
    }
    (uncertainty.map_or(Proof::Stops, Proof::Unknown), spent)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn suffix_dependencies_repeat_every_answer_and_exact_work_on_other_prefixes() {
        let mut inputs = vec![
            include_bytes!("../../test/grammar/json.json").to_vec(),
            include_bytes!("../tests/fixtures/cursor-histories.json").to_vec(),
        ];
        for source in [
            include_str!("../tests/fixtures/declared-choice.json"),
            include_str!("../tests/fixtures/nullable-token.json"),
        ] {
            for case in serde_json::from_str::<Vec<serde_json::Value>>(source).unwrap() {
                inputs.push(case["grammar"].as_str().unwrap().as_bytes().to_vec());
            }
        }
        let (mut questions, mut shared, mut anchored) = (0, 0, 0);
        for input in &inputs {
            let graph = Automaton::from_tree_sitter(input).unwrap();
            let mut queue = std::collections::VecDeque::from([vec![graph.start_state()]]);
            let mut seen = 0;
            while let Some(states) = queue.pop_front() {
                seen += 1;
                if seen > 2048 {
                    break;
                }
                let state = *states.last().unwrap();
                for &symbol in graph.row_admissions(state) {
                    let dependencies = ProofDepth::new(states.len() - 1);
                    let expected = admission(&graph, &states, symbol);
                    assert_eq!(
                        admission_tracked(&graph, &states, symbol, &dependencies),
                        expected
                    );
                    questions += 1;
                    if dependencies.anchored() {
                        anchored += 1;
                        continue;
                    }
                    let suffix = &states[dependencies.start()..];
                    for prefix in [vec![], vec![graph.start_state()], vec![state; 9]] {
                        let mut changed = prefix;
                        changed.extend_from_slice(suffix);
                        assert_eq!(
                            admission(&graph, &changed, symbol),
                            expected,
                            "unobserved prefix changed {states:?} / {suffix:?} / {symbol:?}"
                        );
                        shared += 1;
                    }
                }
                if states.len() < 8 {
                    for (_, to) in graph.state_transitions(state).take(16) {
                        let mut next = states.clone();
                        next.push(to);
                        queue.push_back(next);
                    }
                }
            }
        }
        assert!(questions > 1000 && shared > 1000);
        // Explicit malformed shallow handles exercise bottom-sensitive stops.
        let graph = Automaton::from_tree_sitter(&inputs[1]).unwrap();
        for state in 0..graph.state_count() {
            let state = StateId::from_index(state);
            for &symbol in graph.row_admissions(state) {
                let dependencies = ProofDepth::new(0);
                let states = [state];
                assert_eq!(
                    admission_tracked(&graph, &states, symbol, &dependencies),
                    admission(&graph, &states, symbol)
                );
                anchored += usize::from(dependencies.anchored());
            }
        }
        assert!(anchored > 0);
    }

    #[test]
    fn suffix_dependencies_cover_long_handles_required_empties_and_unknowns() {
        use serde_json::json;
        let terminal = |value: &str| json!({"type":"STRING","value":value});
        let symbol = |name: &str| json!({"type":"SYMBOL","name":name});
        let sequence = |members: Vec<serde_json::Value>| json!({"type":"SEQ","members":members});
        for width in [2, 260] {
            let grammar = json!({"rules":{
                "doc":{"type":"CHOICE","members":[
                    sequence(vec![terminal("u"),symbol("handle"),symbol("tail")]),
                    sequence(vec![terminal("v"),symbol("handle"),terminal("dd")])]},
                "handle":sequence(vec![terminal("q"); width]),
                "tail":{"type":"TOKEN","content":{"type":"PATTERN","value":"d+"}}
            },"extras":[]});
            let graph =
                Automaton::from_tree_sitter(&serde_json::to_vec(&grammar).unwrap()).unwrap();
            let mut states = vec![graph.start_state()];
            for spelling in std::iter::once("u").chain(std::iter::repeat_n("q", width)) {
                let symbol = graph.terminal_by_name(spelling).unwrap();
                states.push(graph.transition(*states.last().unwrap(), symbol).unwrap());
            }
            let tail = graph.symbol_by_name("tail").unwrap();
            let depth = ProofDepth::new(states.len() - 1);
            let answer = admission(&graph, &states, tail);
            assert_eq!(admission_tracked(&graph, &states, tail, &depth), answer);
            if width == 260 {
                assert_eq!(answer, (Proof::Unknown(Uncertain::Work), 256));
            } else {
                assert!(matches!(answer.0, Proof::Reads(_)));
            }
            if !depth.anchored() {
                let suffix = &states[depth.start()..];
                let mut changed = vec![graph.start_state(); 5];
                changed.extend_from_slice(suffix);
                assert_eq!(admission(&graph, &changed, tail), answer);
                assert_eq!(admission(&graph, suffix, tail), answer);
            }
        }
        let grammar = json!({"rules":{
            "doc":{"type":"CHOICE","members":[
                sequence(vec![terminal("u"),symbol("handle"),symbol("zero")]),
                sequence(vec![terminal("v"),symbol("handle")])]},
            "handle":sequence(vec![terminal("q"),terminal("r")]),
            "zero":{"type":"TOKEN","content":{"type":"PATTERN","value":"a*"}}
        },"extras":[]});
        let compiled =
            crate::CompiledGrammar::compile(&serde_json::to_vec(&grammar).unwrap()).unwrap();
        for source in [b"uqr".as_slice(), b"vqr", b"uqraaa"] {
            assert!(
                compiled
                    .session()
                    .parse(source)
                    .unwrap()
                    .confidence()
                    .is_strict()
            );
        }
        let graph = &compiled.automaton;
        let mut states = vec![graph.start_state()];
        for spelling in ["u", "q", "r"] {
            states.push(
                graph
                    .transition(
                        *states.last().unwrap(),
                        graph.terminal_by_name(spelling).unwrap(),
                    )
                    .unwrap(),
            );
        }
        let zero = graph.symbol_by_name("zero").unwrap();
        let depth = ProofDepth::new(states.len() - 1);
        assert_eq!(
            admission_tracked(graph, &states, zero, &depth),
            admission(graph, &states, zero)
        );
        assert!(matches!(admission(graph, &states, zero).0, Proof::Reads(_)));
    }

    #[test]
    fn cursor_family_proofs_require_a_concrete_state_path_and_bound_its_search() {
        let graph =
            Automaton::from_tree_sitter(include_bytes!("../tests/fixtures/cursor-histories.json"))
                .unwrap();
        let parent = graph.symbol_by_name("parent").unwrap();
        let family = (0..graph.reduction_count())
            .map(ReductionId::from_index)
            .find(|&id| graph.reduction(id).lhs == parent)
            .unwrap();
        let rule = graph.reduction(family);
        let path = (0..graph.state_count())
            .find_map(|floor| {
                rule.productions.iter().find_map(|&id| {
                    let mut states = vec![StateId::from_index(floor)];
                    for step in &graph.production(id).steps {
                        states.push(graph.transition(*states.last()?, step.symbol)?);
                    }
                    graph.transition(states[0], parent).map(|_| states)
                })
            })
            .unwrap();
        let mut stack = Stack::new(&path);
        let mut work = 0;
        assert_eq!(stack.reduce(&graph, family, &mut work, 256), Ok(()));
        assert!(work > rule.width);
        assert_eq!(stack.top(), graph.transition(path[0], parent));
        let impossible = vec![graph.start_state(); rule.width + 1];
        let mut stack = Stack::new(&impossible);
        assert_eq!(stack.reduce(&graph, family, &mut 0, 256), Err(Proof::Stops));
        assert_eq!(stack.kept, impossible.len());
        assert_eq!(stack.overlay_len, 0);
        let mut stack = Stack::new(&path);
        assert_eq!(
            stack.reduce(&graph, family, &mut 0, 0),
            Err(Proof::Unknown(Uncertain::Work))
        );
        assert_eq!(stack.kept, path.len());
        assert_eq!(stack.overlay_len, 0);
    }
    #[test]
    fn hidden_literal_identity_is_a_supply_candidate_but_hidden_pattern_is_not() {
        for (kind, expect_literal) in [("STRING", true), ("PATTERN", false)] {
            let source = serde_json::json!({"name":"hidden_opener","rules": {
                "doc":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_open"},{"type":"STRING","value":"x"}]},
                "_open":{"type":kind,"value":"\""}
            }});
            let graph = Automaton::from_tree_sitter(&serde_json::to_vec(&source).unwrap()).unwrap();
            let wanted = graph.symbol_by_name("x").unwrap();
            let (result, _) = insertion(&graph, &[graph.start_state()], wanted);
            if expect_literal {
                assert_eq!(
                    result,
                    Insertion::Unique(graph.symbol_by_name("_open").unwrap())
                );
            } else {
                assert_eq!(result, Insertion::None);
            }
        }
    }
}

// Exact historical source is test-only; trial proofs and work totals are checked
// against its independently retained Vec-based algorithm.
#[cfg(test)]
#[path = "recovery_frozen_e.rs"]
mod frozen_e;

#[cfg(test)]
#[path = "recovery_trial_tests.rs"]
mod trial_tests;
