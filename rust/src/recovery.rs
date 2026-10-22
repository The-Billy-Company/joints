//! Bounded proofs over a borrowed LR stack. No syntax or scanner state changes.

use crate::compiler::{Action, Automaton, Lookahead, Pattern, Shape};
use crate::ids::ReductionId;
use crate::{StateId, SymbolId};

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
    kept: usize,
    overlay: [StateId; 8],
    overlay_len: usize,
}

impl<'a> Stack<'a> {
    fn new(base: &'a [StateId]) -> Self {
        Self {
            base,
            kept: base.len(),
            overlay: [StateId::from_index(0); 8],
            overlay_len: 0,
        }
    }
    fn top(&self) -> Option<StateId> {
        self.overlay[..self.overlay_len]
            .last()
            .copied()
            .or_else(|| self.base.get(self.kept.checked_sub(1)?).copied())
    }
    fn push(&mut self, state: StateId) -> bool {
        let Some(slot) = self.overlay.get_mut(self.overlay_len) else {
            return false;
        };
        *slot = state;
        self.overlay_len += 1;
        true
    }
    fn state(&self, index: usize) -> Option<StateId> {
        if index < self.kept {
            self.base.get(index).copied()
        } else {
            self.overlay[..self.overlay_len]
                .get(index - self.kept)
                .copied()
        }
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
            return Err(Proof::Stops);
        };
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
    let mut stack = Stack::new(states);
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
