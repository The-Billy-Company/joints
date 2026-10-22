//! A declared ambiguity has no preferred alternative. Compare its concrete
//! authored derivations only after dynamic and inferred preferences agree.
//! Generated helpers are transparent. A hidden unit is transparent only in a
//! pure unit-reduction state with no effective tree recipe or protected use.
use super::{Head, Move, ParseSession};
use crate::{
    Error, Resource, StateId, SymbolId,
    compiler::{Action, AliasRecipe, ConflictClass, Lookahead, Shape},
};
use std::{cmp::Ordering, sync::Arc};

#[derive(Default)]
pub(super) struct Policies {
    declared: Vec<((StateId, Lookahead), bool)>,
    units: Vec<((StateId, bool), Option<SymbolId>)>,
    recipes: Option<Recipes>,
}

struct Recipes {
    protected: Vec<bool>,
    empty_units: Vec<bool>,
    extra_firsts: Vec<SymbolId>,
}

#[derive(Clone, Copy)]
struct ChoiceFrame {
    node: usize,
    state: StateId,
}

struct Branch {
    // Transparent reductions retain their immediate RHS as a forest rather
    // than repeatedly copying an already flattened repetition prefix.
    symbol: Option<SymbolId>,
    children: Vec<usize>,
    arity: usize,
}

impl Branch {
    fn roots(&self) -> usize {
        if self.symbol.is_some() { 1 } else { self.arity }
    }
}

struct Derivation {
    prefix: Arc<Vec<Branch>>,
    nodes: Vec<Branch>,
    roots: Vec<usize>,
    arity: usize,
}

impl Derivation {
    fn node(&self, id: usize) -> Result<&Branch, Error> {
        if id < self.prefix.len() {
            self.prefix.get(id)
        } else {
            self.nodes.get(id - self.prefix.len())
        }
        .ok_or(Error::InvalidTable("choice node index"))
    }
}

struct Replay {
    entry: StateId,
    current: StateId,
    document: bool,
    stack: Vec<ChoiceFrame>,
}

impl ParseSession {
    pub(super) fn declared_choice(
        &mut self,
        state: StateId,
        lookahead: Lookahead,
    ) -> Result<bool, Error> {
        let key = (state, lookahead);
        let (mut lo, mut hi) = (0, self.choices.declared.len());
        while lo < hi {
            self.charge(1)?;
            let mid = lo + (hi - lo) / 2;
            let (found, declared) = self.choices.declared[mid];
            match found.cmp(&key) {
                Ordering::Less => lo = mid + 1,
                Ordering::Greater => hi = mid,
                Ordering::Equal => return Ok(declared),
            }
        }
        let declared = {
            let graph = Arc::clone(&self.grammar.automaton);
            let mut declared = false;
            for record in graph.conflicts() {
                self.charge(1)?;
                if record.state == state && record.lookahead == lookahead {
                    declared = record.class == ConflictClass::Declared;
                    break;
                }
            }
            // Vec insertion moves exactly the suffix after this search point.
            self.charge(
                self.choices
                    .declared
                    .len()
                    .saturating_sub(lo)
                    .saturating_add(1),
            )?;
            self.choices.declared.insert(lo, (key, declared));
            declared
        };
        Ok(declared)
    }

    fn prepare_unit_recipes(&mut self) -> Result<(), Error> {
        if self.choices.recipes.is_some() {
            return Ok(());
        }
        let graph = Arc::clone(&self.grammar.automaton);
        let count = graph.symbol_count();
        self.charge(
            count
                .saturating_mul(4)
                .saturating_add(graph.production_count()),
        )?;
        let mut protected = vec![false; count];
        let mut supertypes = vec![false; count];
        let mut fields = vec![false; count];
        let mut parents: Vec<Vec<usize>> = vec![vec![]; count];
        let mut empty_units = vec![false; graph.production_count()];
        let mut extra_firsts = vec![];

        // The parser's separate rule-extra entries stand for ordinary extra
        // starts at every document state, rather than ShiftExtra actions.
        // Their precomputed admissions include nullable-prefix closure.
        for &(_, entry) in graph.extra_entries() {
            let firsts = graph.row_admissions(entry);
            self.charge(firsts.len().saturating_add(1))?;
            extra_firsts.extend_from_slice(firsts);
        }
        let depth = usize::BITS - extra_firsts.len().leading_zeros();
        self.charge(extra_firsts.len().saturating_mul(depth as usize + 1))?;
        extra_firsts.sort_unstable();
        extra_firsts.dedup();

        for &symbol in graph.extras() {
            self.charge(1)?;
            protected[symbol.index()] = true;
        }
        for &symbol in graph.supertypes() {
            self.charge(1)?;
            protected[symbol.index()] = true;
            supertypes[symbol.index()] = true;
        }
        for i in 0..graph.production_count() {
            let id = crate::ProductionId::from_index(i);
            let rule = graph.production(id);
            self.charge(1)?;
            for step in &rule.steps {
                self.charge(1)?;
                fields[rule.lhs.index()] |= step.field.is_some();
                if step.alias.is_some() {
                    protected[step.symbol.index()] = true;
                }
            }
        }
        for i in 0..graph.production_count() {
            let rule = graph.production(crate::ProductionId::from_index(i));
            self.charge(1)?;
            for step in &rule.steps {
                self.charge(1)?;
                if matches!(
                    graph.symbol(step.symbol).shape,
                    Shape::Hidden | Shape::Invented
                ) && !supertypes[step.symbol.index()]
                    && step.alias.is_none()
                {
                    self.charge(1)?;
                    parents[step.symbol.index()].push(rule.lhs.index());
                }
            }
        }
        self.charge(count)?;
        let mut pending: Vec<_> = fields
            .iter()
            .enumerate()
            .filter_map(|(i, &has)| has.then_some(i))
            .collect();
        while let Some(child) = pending.pop() {
            self.charge(1)?;
            for &parent in &parents[child] {
                self.charge(1)?;
                if !fields[parent] {
                    self.charge(1)?;
                    fields[parent] = true;
                    pending.push(parent);
                }
            }
        }
        for i in 0..graph.production_count() {
            let id = crate::ProductionId::from_index(i);
            let rule = graph.production(id);
            self.charge(1)?;
            let [step] = rule.steps.as_slice() else {
                continue;
            };
            self.charge(1)?;
            // Recipe field inheritance uses the child's raw hidden/aux kind,
            // even if a default alias makes that child effectively visible.
            if step.field.is_some()
                || (matches!(
                    graph.symbol(step.symbol).shape,
                    Shape::Hidden | Shape::Invented
                ) && fields[step.symbol.index()])
            {
                continue;
            }
            if step.alias_recipe == AliasRecipe::Local {
                continue;
            }
            empty_units[id.index()] = true;
        }
        self.choices.recipes = Some(Recipes {
            protected,
            empty_units,
            extra_firsts,
        });
        Ok(())
    }

    fn transparent_unit(
        &mut self,
        state: StateId,
        lhs: SymbolId,
        document: bool,
    ) -> Result<bool, Error> {
        let key = (state, document);
        let (mut lo, mut hi) = (0, self.choices.units.len());
        while lo < hi {
            self.charge(1)?;
            let mid = lo + (hi - lo) / 2;
            let (found, unit) = self.choices.units[mid];
            match found.cmp(&key) {
                Ordering::Less => lo = mid + 1,
                Ordering::Greater => hi = mid,
                Ordering::Equal => return Ok(unit == Some(lhs)),
            }
        }
        self.prepare_unit_recipes()?;
        let graph = Arc::clone(&self.grammar.automaton);
        let mut ordinary_extra_start = false;
        if document {
            for i in 0..self.choices.recipes.as_ref().unwrap().extra_firsts.len() {
                self.charge(1)?;
                let first = self.choices.recipes.as_ref().unwrap().extra_firsts[i];
                if graph.actions(state, Lookahead::Terminal(first)).is_empty() {
                    ordinary_extra_start = true;
                    break;
                }
            }
        }
        let mut unit = None;
        'rows: for (_, actions) in graph.action_row(state) {
            self.charge(1)?;
            // Existing terminal actions win over automatic rule-extra starts.
            // Only a missing FIRST key adds an ordinary, purity-breaking Shift.
            if ordinary_extra_start {
                break;
            }
            for &action in actions {
                self.charge(1)?;
                let Action::Reduce(id) = action else {
                    unit = None;
                    break 'rows;
                };
                let reduction = graph.reduction(id);
                let eligible = graph.symbol(reduction.lhs).shape == Shape::Hidden
                    && !self.choices.recipes.as_ref().unwrap().protected[reduction.lhs.index()];
                if reduction.width != 1 || !eligible || unit.is_some_and(|s| s != reduction.lhs) {
                    unit = None;
                    break 'rows;
                }
                for &production in &reduction.productions {
                    self.charge(1)?;
                    if !self.choices.recipes.as_ref().unwrap().empty_units[production.index()] {
                        unit = None;
                        break 'rows;
                    }
                }
                unit = Some(reduction.lhs);
            }
        }
        self.charge(
            self.choices
                .units
                .len()
                .saturating_sub(lo)
                .saturating_add(1),
        )?;
        self.choices.units.insert(lo, (key, unit));
        Ok(unit == Some(lhs))
    }

    /// Greater means `a` is preferred. Failed/repaired histories retain the
    /// original dynamic-then-birth arbitration, even beside a clean history.
    pub(super) fn compare_heads(&mut self, a: &Head, b: &Head) -> Result<Ordering, Error> {
        self.charge(1)?;
        let dynamic = a.dynamic.cmp(&b.dynamic);
        if !dynamic.is_eq() {
            return Ok(dynamic);
        }
        if a.repaired || b.repaired || (!a.declared && !b.declared) {
            return Ok(b.birth.cmp(&a.birth));
        }
        let preference = b.rank.cmp(&a.rank);
        if !preference.is_eq() {
            return Ok(preference);
        }

        // Both temporary arenas share the remaining node allowance. Work is
        // charged before every payload allocation, including transparent RHSs.
        let mut nodes_left = self.limits.nodes.saturating_sub(self.drafts.len());
        let (left, right) = self.shared_derivations(a, b, &mut nodes_left)?;
        let structural = self.compare_derivations(&left, &right)?;
        if structural.is_eq() {
            Ok(b.birth.cmp(&a.birth))
        } else {
            Ok(structural.reverse())
        }
    }

    fn replay_start(&mut self, head: &Head) -> Result<Replay, Error> {
        self.charge(1)?;
        let entry = *head
            .states
            .first()
            .ok_or(Error::InvalidTable("choice entry state"))?;
        let graph = Arc::clone(&self.grammar.automaton);
        self.charge(graph.extra_entries().len())?;
        let document = !graph.extra_entries().iter().any(|&(_, q)| q == entry);
        Ok(Replay {
            entry,
            current: entry,
            document,
            stack: Vec::new(),
        })
    }

    fn shared_derivations(
        &mut self,
        a: &Head,
        b: &Head,
        nodes_left: &mut usize,
    ) -> Result<(Derivation, Derivation), Error> {
        let mut common = self.replay_start(a)?;
        self.charge(1)?;
        let b_entry = *b
            .states
            .first()
            .ok_or(Error::InvalidTable("choice entry state"))?;
        let same_entry = common.entry == b_entry;
        self.charge(
            a.trace
                .iter_work()
                .saturating_add(b.trace.iter_work())
                .saturating_add(1),
        )?;
        let (mut left_moves, mut right_moves) = (a.trace.iter(), b.trace.iter());
        // The prefix's initial empty Arc and the later shared Arc are metadata
        // allocations; neither copies the raw arena's Branch payloads.
        self.charge(1)?;
        let mut prefix = Derivation {
            prefix: Arc::new(Vec::new()),
            nodes: Vec::new(),
            roots: Vec::new(),
            arity: 0,
        };
        let (mut left_first, mut right_first) = (None, None);
        if same_entry {
            loop {
                // Two iterator advances and up to three Move-field comparisons.
                self.charge(5)?;
                match (left_moves.next(), right_moves.next()) {
                    (Some(left), Some(right)) if left == right => {
                        self.replay_move(&mut common, &mut prefix, *left, nodes_left)?
                    }
                    (left, right) => {
                        left_first = left.copied();
                        right_first = right.copied();
                        break;
                    }
                }
            }
        }
        self.charge(3)?;
        let shared = Arc::new(prefix.nodes);
        let (mut left_state, mut right_state) = if same_entry {
            self.charge(common.stack.len().saturating_mul(2).saturating_add(1))?;
            let left = Replay {
                entry: common.entry,
                current: common.current,
                document: common.document,
                stack: common.stack.clone(),
            };
            (left, common)
        } else {
            (common, self.replay_start(b)?)
        };
        let mut left = Derivation {
            prefix: Arc::clone(&shared),
            nodes: Vec::new(),
            roots: Vec::new(),
            arity: 0,
        };
        let mut right = Derivation {
            prefix: shared,
            nodes: Vec::new(),
            roots: Vec::new(),
            arity: 0,
        };
        for movement in left_first.into_iter().chain(left_moves.copied()) {
            self.replay_move(&mut left_state, &mut left, movement, nodes_left)?;
        }
        for movement in right_first.into_iter().chain(right_moves.copied()) {
            self.replay_move(&mut right_state, &mut right, movement, nodes_left)?;
        }
        self.finish_derivation(a, left_state, &mut left)?;
        self.finish_derivation(b, right_state, &mut right)?;
        Ok((left, right))
    }

    fn replay_move(
        &mut self,
        state: &mut Replay,
        tree: &mut Derivation,
        movement: Move,
        nodes_left: &mut usize,
    ) -> Result<(), Error> {
        let graph = Arc::clone(&self.grammar.automaton);
        self.charge(1)?;
        match movement {
            Move::Shift { from, symbol } => {
                if symbol.index() >= graph.symbol_count() {
                    return Err(Error::InvalidTable("choice shift symbol"));
                }
                if from != state.current {
                    return Err(Error::InvalidTable("choice shift state"));
                }
                self.charge(1)?;
                state.current = graph
                    .transition(from, symbol)
                    .ok_or(Error::InvalidTable("choice shift transition"))?;
                let id = self.choice_node(tree, nodes_left, Some(symbol), Vec::new(), 0)?;
                self.charge(1)?;
                state.stack.push(ChoiceFrame {
                    node: id,
                    state: state.current,
                });
            }
            Move::Reduce { under, production } => {
                if production.index() >= graph.production_count() {
                    return Err(Error::InvalidTable("choice production"));
                }
                let rule = graph.production(production);
                let width = rule.steps.len();
                self.charge(width)?;
                let start = state
                    .stack
                    .len()
                    .checked_sub(width)
                    .ok_or(Error::InvalidTable("choice trace underflow"))?;
                let predecessor = if start == 0 {
                    state.entry
                } else {
                    state.stack[start - 1].state
                };
                if predecessor != under {
                    return Err(Error::InvalidTable("choice reduction state"));
                }
                self.charge(width.saturating_mul(3))?;
                let arity = state.stack[start..].iter().try_fold(0usize, |n, frame| {
                    n.checked_add(tree.node(frame.node)?.roots())
                        .ok_or(Error::LimitExceeded(Resource::Work))
                })?;
                let mut body = Vec::with_capacity(width);
                for frame in state.stack.drain(start..) {
                    body.push(frame.node);
                }
                let shape = graph.symbol(rule.lhs).shape;
                let transparent_unit = shape == Shape::Hidden
                    && width == 1
                    && self.transparent_unit(state.current, rule.lhs, state.document)?;
                self.charge(1)?;
                state.current = graph
                    .transition(under, rule.lhs)
                    .ok_or(Error::InvalidTable("choice reduction transition"))?;
                let symbol = (!(shape == Shape::Invented || transparent_unit)).then_some(rule.lhs);
                let id = self.choice_node(tree, nodes_left, symbol, body, arity)?;
                self.charge(1)?;
                state.stack.push(ChoiceFrame {
                    node: id,
                    state: state.current,
                });
            }
            Move::Hole => return Err(Error::InvalidTable("unmarked repaired choice")),
        }
        Ok(())
    }

    fn finish_derivation(
        &mut self,
        head: &Head,
        state: Replay,
        tree: &mut Derivation,
    ) -> Result<(), Error> {
        if state.stack.len() != head.frames.len() {
            return Err(Error::InvalidTable("choice trace frame count"));
        }
        self.charge(state.stack.len().saturating_mul(2))?;
        tree.arity = state.stack.iter().try_fold(0usize, |n, frame| {
            n.checked_add(tree.node(frame.node)?.roots())
                .ok_or(Error::LimitExceeded(Resource::Work))
        })?;
        tree.roots = Vec::with_capacity(state.stack.len());
        for frame in state.stack {
            tree.roots.push(frame.node);
        }
        Ok(())
    }

    fn choice_node(
        &mut self,
        tree: &mut Derivation,
        nodes_left: &mut usize,
        symbol: Option<SymbolId>,
        children: Vec<usize>,
        arity: usize,
    ) -> Result<usize, Error> {
        if *nodes_left == 0 {
            return Err(Error::LimitExceeded(Resource::Nodes));
        }
        self.charge(1)?;
        let id = tree
            .prefix
            .len()
            .checked_add(tree.nodes.len())
            .ok_or(Error::LimitExceeded(Resource::Work))?;
        *nodes_left -= 1;
        tree.nodes.push(Branch {
            symbol,
            children,
            arity,
        });
        Ok(id)
    }

    fn compare_derivations(&mut self, a: &Derivation, b: &Derivation) -> Result<Ordering, Error> {
        self.charge(1)?;
        let arity = a.arity.cmp(&b.arity);
        if !arity.is_eq() {
            return Ok(arity);
        }
        self.charge(a.roots.len().saturating_add(b.roots.len()))?;
        let mut left: Vec<_> = a.roots.iter().rev().copied().collect();
        let mut right: Vec<_> = b.roots.iter().rev().copied().collect();
        loop {
            let pair = (
                self.next_choice(a, &mut left)?,
                self.next_choice(b, &mut right)?,
            );
            match pair {
                (Some(a), Some(b)) if a == b => {}
                (a, b) => return Ok(a.cmp(&b)),
            }
        }
    }

    fn next_choice(
        &mut self,
        tree: &Derivation,
        pending: &mut Vec<usize>,
    ) -> Result<Option<(SymbolId, usize)>, Error> {
        while let Some(id) = pending.pop() {
            self.charge(1)?;
            let node = tree.node(id)?;
            self.charge(node.children.len())?;
            pending.extend(node.children.iter().rev().copied());
            if let Some(symbol) = node.symbol {
                return Ok(Some((symbol, node.arity)));
            }
        }
        Ok(None)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::parser::Frame;
    use crate::{ByteSpan, CompiledGrammar};

    fn complete() -> (ParseSession, Head) {
        let grammar = CompiledGrammar::compile(br#"{"rules":{
          "doc":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"a"},{"type":"SYMBOL","name":"b"}]},
          "a":{"type":"SEQ","members":[{"type":"STRING","value":"x"},{"type":"STRING","value":"y"}]},
          "b":{"type":"SEQ","members":[{"type":"STRING","value":"x"},{"type":"STRING","value":"y"}]}},
          "conflicts":[["a","b"]]}"#).unwrap();
        let mut session = grammar.session();
        session.parse(b"xy").unwrap();
        let mut head = Head::new(grammar.start_state(), 2);
        head.trace = super::super::history::History::from_vec(session.trace.clone());
        head.frames.push(Frame {
            symbol: grammar.start_symbol(),
            span: ByteSpan::new(0, 2).unwrap(),
            lead: vec![],
            body: vec![],
            unproven: false,
        });
        head.declared = true;
        (session, head)
    }

    #[test]
    fn temporary_reconstruction_refuses_before_work_or_node_allowances_are_exceeded() {
        let (mut session, head) = complete();
        let drafts = session.drafts.len();
        let trace = head.trace.len();
        session.steps = 0;
        session.limits.steps = 1;
        assert!(matches!(
            session.compare_heads(&head, &head),
            Err(Error::LimitExceeded(Resource::Work))
        ));
        // charge() retains the attempted debit on refusal; no syntax or
        // retained history was changed by the failed reconstruction.
        assert!(session.steps > session.limits.steps);
        assert_eq!(session.drafts.len(), drafts);
        assert_eq!(head.trace.len(), trace);
        session.steps = 0;
        session.limits.steps = 10_000;
        session.limits.nodes = session.drafts.len();
        assert!(matches!(
            session.compare_heads(&head, &head),
            Err(Error::LimitExceeded(Resource::Nodes))
        ));
    }

    #[test]
    fn unit_metadata_refuses_before_allocating_or_publishing_a_partial_policy() {
        let (mut session, _) = complete();
        session.choices = Policies::default();
        session.steps = 0;
        session.limits.steps = 1;
        assert!(matches!(
            session.prepare_unit_recipes(),
            Err(Error::LimitExceeded(Resource::Work))
        ));
        assert!(session.choices.recipes.is_none());
        assert!(session.choices.units.is_empty());
        session.steps = 0;
        session.limits.steps = 10_000;
        session.prepare_unit_recipes().unwrap();
        session.steps = 0;
        session.limits.steps = 0;
        assert!(matches!(
            session.transparent_unit(
                session.grammar.start_state(),
                session.grammar.start_symbol(),
                true,
            ),
            Err(Error::LimitExceeded(Resource::Work))
        ));
        assert!(session.choices.units.is_empty());
    }

    #[test]
    fn ambiguous_rule_extras_replay_from_their_auxiliary_entry_state() {
        let grammar = CompiledGrammar::compile(br##"{"rules":{
          "doc":{"type":"STRING","value":"!"},
          "_comment":{"type":"SEQ","members":[{"type":"STRING","value":"#"},{"type":"CHOICE","members":[{"type":"SYMBOL","name":"a"},{"type":"SYMBOL","name":"b"}]},{"type":"STRING","value":"#"}]},
          "a":{"type":"SEQ","members":[{"type":"STRING","value":"x"},{"type":"STRING","value":"y"}]},
          "b":{"type":"SEQ","members":[{"type":"STRING","value":"x"},{"type":"STRING","value":"y"}]}},
          "extras":[{"type":"SYMBOL","name":"_comment"}],"conflicts":[["a","b"]]}"##).unwrap();
        assert_ne!(
            grammar.automaton.extra_entries()[0].1,
            grammar.start_state()
        );
        let mut session = grammar.session();
        let tree = session.parse(b"#xy#!").unwrap();
        assert!(tree.confidence().is_strict());
        assert!(!session.choices.declared.is_empty());
        assert!(
            !session
                .product(&mut grammar.effect_store())
                .unwrap()
                .is_zero()
        );
    }

    #[test]
    fn repaired_and_entirely_inferred_histories_keep_legacy_dynamic_then_birth_order() {
        let (mut session, mut a) = complete();
        let mut b = a.clone();
        a.birth = 2;
        b.birth = 1;
        a.rank = 0;
        b.rank = 99;
        session.limits.nodes = 0;
        for (repaired_a, repaired_b) in [(true, false), (false, true), (true, true)] {
            a.repaired = repaired_a;
            b.repaired = repaired_b;
            assert!(session.compare_heads(&a, &b).unwrap().is_lt());
            a.dynamic = 1;
            assert!(session.compare_heads(&a, &b).unwrap().is_gt());
            a.dynamic = 0;
        }
        a.repaired = false;
        b.repaired = false;
        a.declared = false;
        b.declared = false;
        assert!(session.compare_heads(&a, &b).unwrap().is_lt());
    }

    #[test]
    fn transparent_repetition_comparison_preserves_authored_children_with_linear_work() {
        let grammar = CompiledGrammar::compile(br#"{"rules":{
          "doc":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"a"},{"type":"SYMBOL","name":"b"}]},
          "a":{"type":"SEQ","members":[{"type":"REPEAT","content":{"type":"STRING","value":"x"}},{"type":"STRING","value":"!"}]},
          "b":{"type":"SEQ","members":[{"type":"REPEAT","content":{"type":"STRING","value":"x"}},{"type":"STRING","value":"!"}]}},
          "conflicts":[["a","b"]]}"#).unwrap();
        let mut session = grammar.session();
        let mut work = Vec::new();
        for count in [4096, 8192] {
            let mut source = vec![b'x'; count];
            source.push(b'!');
            let tree = session.parse(&source).unwrap();
            assert!(tree.confidence().is_strict());
            let root = tree.root().unwrap();
            assert_eq!(root.name(), "doc");
            let chosen = root.children().next().unwrap();
            assert_eq!(chosen.name(), "a");
            assert_eq!(chosen.children().len(), count + 1);
            for (index, child) in chosen.children().enumerate() {
                assert_eq!(child.name(), if index == count { "!" } else { "x" });
                assert_eq!(child.span(), ByteSpan::new(index, index + 1).unwrap());
            }
            assert!(!session.choices.declared.is_empty());
            work.push(session.steps);
        }
        assert!(work[1] <= work[0] * 21 / 10, "choice work: {work:?}");
    }
    #[test]
    fn identical_histories_spend_the_temporary_node_allowance_once() {
        let (mut session, head) = complete();
        session.steps = 0;
        session.limits.steps = 100_000;
        session.limits.nodes = session.drafts.len() + head.trace.len();
        assert!(session.compare_heads(&head, &head).unwrap().is_eq());
        session.steps = 0;
        session.limits.nodes -= 1;
        assert!(matches!(
            session.compare_heads(&head, &head),
            Err(Error::LimitExceeded(Resource::Nodes))
        ));
    }

    #[test]
    fn shared_history_still_checks_each_actual_head_frame_count() {
        let (mut session, a) = complete();
        let mut b = a.clone();
        b.frames.clear();
        session.steps = 0;
        session.limits.steps = 100_000;
        assert!(matches!(
            session.compare_heads(&a, &b),
            Err(Error::InvalidTable("choice trace frame count"))
        ));
        assert!(matches!(
            session.compare_heads(&b, &a),
            Err(Error::InvalidTable("choice trace frame count"))
        ));
    }

    #[test]
    fn unequal_auxiliary_entry_states_replay_separately() {
        let grammar=CompiledGrammar::compile(br##"{"rules":{
          "doc":{"type":"STRING","value":"!"},
          "first":{"type":"SEQ","members":[{"type":"STRING","value":"#"},{"type":"STRING","value":"x"},{"type":"STRING","value":"#"}]},
          "second":{"type":"SEQ","members":[{"type":"STRING","value":"#"},{"type":"STRING","value":"x"},{"type":"STRING","value":"#"}]}},
          "extras":[{"type":"SYMBOL","name":"first"},{"type":"SYMBOL","name":"second"}]}"##).unwrap();
        let entries = grammar.automaton.extra_entries().to_vec();
        assert_eq!(entries.len(), 2);
        assert_ne!(entries[0].1, entries[1].1);
        let first = crate::lexer::Lexeme {
            symbol: grammar.symbol_id("#").unwrap(),
            start: 0,
            end: 1,
            extra: false,
        };
        let mut session = grammar.session();
        session.reset_run();
        let mut a = session
            .extra_reading(b"#x#", Head::new(entries[0].1, 0), first)
            .unwrap()
            .unwrap();
        let mut b = session
            .extra_reading(b"#x#", Head::new(entries[1].1, 0), first)
            .unwrap()
            .unwrap();
        a.declared = true;
        b.declared = true;
        assert_eq!(grammar.symbol_name(a.frames[0].symbol), Some("first"));
        assert_eq!(grammar.symbol_name(b.frames[0].symbol), Some("second"));
        assert!(session.compare_heads(&a, &b).unwrap().is_gt());
        assert!(session.compare_heads(&b, &a).unwrap().is_lt());
    }
}
