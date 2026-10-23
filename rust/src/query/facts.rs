//! Relations that query syntax asks of a grammar, including hidden splices.

use std::collections::{BTreeMap, BTreeSet};

use super::*;
use crate::compiler::Automaton;

pub(super) struct Facts {
    names: BTreeMap<(String, bool), Vec<SymbolId>>,
    fields: BTreeMap<String, FieldId>,
    categories: BTreeMap<String, Vec<SymbolId>>,
    carried: Vec<BTreeSet<FieldId>>,
    admitted: Vec<BTreeSet<SymbolId>>,
    extras: BTreeSet<SymbolId>,
}

impl Facts {
    pub(super) fn new(graph: &Automaton, budget: &mut Budget) -> Result<Self, QueryError> {
        budget.charge(graph.symbol_count() + graph.field_count())?;
        let mut names = BTreeMap::<(String, bool), Vec<SymbolId>>::new();
        let mut fields = BTreeMap::new();
        for index in 0..graph.symbol_count() {
            let id = SymbolId::from_index(index);
            let symbol = graph.symbol(id);
            if symbol.shape.visible() {
                budget.charge(symbol.name.len() + 1)?;
                names
                    .entry((symbol.name.clone(), symbol.shape.named()))
                    .or_default()
                    .push(id);
            }
        }
        for index in 0..graph.field_count() {
            let id = FieldId::from_index(index);
            let name = graph.field_name(id);
            budget.charge(name.len() + 1)?;
            fields.insert(name.to_owned(), id);
        }
        let mut visible = vec![BTreeSet::new(); graph.symbol_count()];
        let mut carried = vec![BTreeSet::new(); graph.symbol_count()];
        for index in 0..graph.production_count() {
            for step in &graph
                .production(crate::ProductionId::from_index(index))
                .steps
            {
                if let Some(alias) = &step.alias {
                    budget.charge(alias.name.len() + 1)?;
                    names
                        .entry((alias.name.to_string(), alias.named))
                        .or_default()
                        .push(step.symbol);
                }
            }
        }
        for ids in names.values_mut() {
            ids.sort_unstable();
            ids.dedup();
        }
        loop {
            let mut changed = false;
            for index in 0..graph.production_count() {
                let production = graph.production(crate::ProductionId::from_index(index));
                let lhs = production.lhs.index();
                for step in &production.steps {
                    budget.charge(1)?;
                    if let Some(field) = step.field {
                        changed |= carried[lhs].insert(field);
                    }
                    if step.alias.is_some() || graph.symbol(step.symbol).shape.visible() {
                        changed |= visible[lhs].insert(step.symbol);
                    } else {
                        let rhs = step.symbol.index();
                        budget.charge(visible[rhs].len() + carried[rhs].len())?;
                        // Distinct symbols borrow disjoint relation sets. A
                        // self-edge cannot add anything, so neither case needs
                        // a temporary snapshot on every fixed-point pass.
                        changed |= extend_relation(&mut visible, lhs, rhs);
                        changed |= extend_relation(&mut carried, lhs, rhs);
                    }
                }
            }
            if !changed {
                break;
            }
        }
        let mut categories = BTreeMap::new();
        for &symbol in graph.supertypes() {
            budget.charge(visible[symbol.index()].len() + graph.symbol(symbol).name.len())?;
            categories.insert(
                graph.symbol(symbol).name.clone(),
                visible[symbol.index()].iter().copied().collect(),
            );
        }
        let mut extras = BTreeSet::new();
        for &id in graph.extras() {
            budget.charge(1)?;
            if graph.symbol(id).shape.visible() {
                extras.insert(id);
            } else {
                budget.charge(visible[id.index()].len())?;
                extras.extend(visible[id.index()].iter().copied());
            }
        }
        Ok(Self {
            names,
            fields,
            categories,
            carried,
            admitted: visible,
            extras,
        })
    }

    pub(super) fn field(&self, name: &str, at: usize) -> Result<FieldId, QueryError> {
        self.fields
            .get(name)
            .copied()
            .ok_or_else(|| QueryError::UnknownName {
                at,
                sort: "field",
                name: name.to_owned(),
            })
    }

    pub(super) fn kind(
        &self,
        name: &str,
        named: bool,
        category: Option<&str>,
        at: usize,
        budget: &mut Budget,
    ) -> Result<Kind, QueryError> {
        budget.charge(name.len())?;
        if named && name == "_" {
            if let Some(category) = category {
                let members =
                    self.categories
                        .get(category)
                        .ok_or_else(|| QueryError::UnknownName {
                            at,
                            sort: "supertype",
                            name: category.to_owned(),
                        })?;
                budget.charge(members.len())?;
                return Ok(Kind::Category(members.clone()));
            }
            return Ok(Kind::Named);
        }
        if named && category.is_none() && !self.names.contains_key(&(name.to_owned(), true)) {
            if let Some(members) = self.categories.get(name) {
                budget.charge(members.len())?;
                return Ok(Kind::Category(members.clone()));
            }
        }
        let resolved =
            self.names
                .get(&(name.to_owned(), named))
                .ok_or_else(|| QueryError::UnknownName {
                    at,
                    sort: if named { "node" } else { "literal" },
                    name: name.to_owned(),
                })?;
        budget.charge(resolved.len())?;
        let mut under = resolved.clone();
        if let Some(category) = category {
            let members = self
                .categories
                .get(category)
                .ok_or_else(|| QueryError::UnknownName {
                    at,
                    sort: "supertype",
                    name: category.to_owned(),
                })?;
            budget.charge(under.len().saturating_mul(members.len()))?;
            under.retain(|id| members.contains(id));
        }
        Ok(Kind::Name {
            name: name.to_owned(),
            named,
            under,
        })
    }

    /// Only definite impossibility is reported. Optional positions can choose
    /// zero, a choice is dead only when every arm is dead, and aliases contribute
    /// all their possible underlying structures. Extras can occur under any node.
    pub(super) fn dead(
        &self,
        root: usize,
        steps: &[Step],
        budget: &mut Budget,
    ) -> Result<Option<(usize, DeadCause)>, QueryError> {
        self.dead_step(root, None, steps, budget)
    }

    fn dead_step(
        &self,
        id: usize,
        parent: Option<&[SymbolId]>,
        steps: &[Step],
        budget: &mut Budget,
    ) -> Result<Option<(usize, DeadCause)>, QueryError> {
        budget.charge(1)?;
        let step = &steps[id];
        if matches!(step.quantifier, Quantifier::Optional | Quantifier::Star) {
            return Ok(None);
        }
        let under = match &step.kind {
            Kind::Name { under, .. } | Kind::Category(under) => Some(under.as_slice()),
            _ => None,
        };
        if under.is_some_and(|u| u.is_empty()) {
            return Ok(Some((step.at, DeadCause::CategoryNotMember)));
        }
        if let (Some(parents), Some(field)) = (parent, step.field) {
            budget.charge(parents.len())?;
            if !parents.is_empty()
                && parents
                    .iter()
                    .all(|p| !self.carried[p.index()].contains(&field))
            {
                return Ok(Some((step.at, DeadCause::FieldNotCarried)));
            }
        }
        if let (Some(parents), Some(children)) = (parent, under) {
            budget.charge(
                parents
                    .len()
                    .saturating_mul(children.len())
                    .saturating_add(children.len()),
            )?;
            if !parents.is_empty()
                && !children.iter().any(|c| {
                    self.extras.contains(c)
                        || parents.iter().any(|p| self.admitted[p.index()].contains(c))
                })
            {
                return Ok(Some((step.at, DeadCause::ChildNotAdmitted)));
            }
        }
        if matches!(step.kind, Kind::Choice) {
            let mut first = None;
            for &child in &step.children {
                match self.dead_step(child, parent, steps, budget)? {
                    None => return Ok(None),
                    dead => {
                        if first.is_none() {
                            first = dead;
                        }
                    }
                }
            }
            return Ok(first);
        }
        let context = if matches!(step.kind, Kind::Group) {
            parent
        } else {
            under
        };
        for &child in &step.children {
            if let Some(dead) = self.dead_step(child, context, steps, budget)? {
                return Ok(Some(dead));
            }
        }
        Ok(None)
    }
}

fn extend_relation<T: Ord + Copy>(sets: &mut [BTreeSet<T>], lhs: usize, rhs: usize) -> bool {
    let (target, source) = match lhs.cmp(&rhs) {
        std::cmp::Ordering::Less => {
            let (left, right) = sets.split_at_mut(rhs);
            (&mut left[lhs], &right[0])
        }
        std::cmp::Ordering::Greater => {
            let (left, right) = sets.split_at_mut(lhs);
            (&mut right[0], &left[rhs])
        }
        std::cmp::Ordering::Equal => return false,
    };
    let mut changed = false;
    for &value in source {
        changed |= target.insert(value);
    }
    changed
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn disjoint_relation_unions_match_snapshots_in_both_directions_and_self_edges() {
        for left in 0..16u8 {
            for right in 0..16u8 {
                let set = |bits: u8| -> BTreeSet<u8> {
                    (0..4).filter(|bit| bits & (1 << bit) != 0).collect()
                };
                let initial = vec![set(left), set(right)];
                for (lhs, rhs) in [(0, 1), (1, 0), (0, 0), (1, 1)] {
                    let mut expected = initial.clone();
                    let source = expected[rhs].clone();
                    let mut changed = false;
                    for value in source {
                        changed |= expected[lhs].insert(value);
                    }
                    let mut actual = initial.clone();
                    assert_eq!(extend_relation(&mut actual, lhs, rhs), changed);
                    assert_eq!(actual, expected);
                }
            }
        }
    }
}
