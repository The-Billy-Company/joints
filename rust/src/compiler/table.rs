//! Immutable parser rows, published once and shared by every worker.
//!
//! Construction keeps its mutable maps. Publication and artifact decoding own
//! flat columns; terminal keys double as each row's lexical admission slate.

use std::ops::Range;

use super::{Action, CompileError, Graph, Lookahead, Rows, StateId, SymbolId};
use crate::artifact::{ArtifactError, Reader};

#[derive(Debug, Eq, PartialEq)]
struct StateRow {
    terminals: Range<usize>,
    cells: Range<usize>,
    transitions: Range<usize>,
}

#[derive(Debug, Eq, PartialEq)]
pub(super) struct FrozenTables {
    rows: Box<[StateRow]>,
    terminals: Box<[SymbolId]>,
    action_offsets: Box<[usize]>,
    actions: Box<[Action]>,
    transition_symbols: Box<[SymbolId]>,
    transition_states: Box<[StateId]>,
}

/// One unit per visited row/cell in the sizing and publication passes, one per
/// moved transition/action, and one per admission comparison and terminal key.
/// The caller charges this entire pass before allocating any frozen columns.
pub(super) fn publication_work(graph: &Graph, rows: &Rows) -> Result<usize, CompileError> {
    let mut work = graph
        .len()
        .checked_mul(2)
        .ok_or(CompileError::Limit("frozen table publication work"))?;
    for row in graph {
        work = work
            .checked_add(row.len())
            .ok_or(CompileError::Limit("frozen table publication work"))?;
    }
    for row in rows {
        for (at, cell) in row {
            work = work
                .checked_add(2)
                .and_then(|n| n.checked_add(cell.len()))
                .and_then(|n| n.checked_add(usize::from(matches!(at, Lookahead::Terminal(_))) * 2))
                .ok_or(CompileError::Limit("frozen table publication work"))?;
        }
    }
    Ok(work)
}

impl FrozenTables {
    pub(super) fn from_maps(
        graph: Graph,
        rows: Rows,
        admissions: Vec<Vec<SymbolId>>,
    ) -> Result<Self, CompileError> {
        if graph.len() != rows.len() || rows.len() != admissions.len() {
            return Err(CompileError::Malformed(
                "frozen table row counts differ".into(),
            ));
        }
        #[cfg(test)]
        let expected = (graph.clone(), rows.clone(), admissions.clone());
        let mut columns = Columns::new(graph.len());
        for row in graph {
            let start = columns.transition_symbols.len();
            for (symbol, state) in row {
                columns.transition_symbols.push(symbol);
                columns.transition_states.push(state);
            }
            columns.rows.push(StateRow {
                transitions: start..columns.transition_symbols.len(),
                terminals: 0..0,
                cells: 0..0,
            });
        }
        for (index, (row, admission)) in rows.into_iter().zip(admissions).enumerate() {
            let terminal_start = columns.terminals.len();
            let cell_start = columns.action_offsets.len() - 1;
            for (at, cell) in row {
                if let Lookahead::Terminal(symbol) = at {
                    columns.terminals.push(symbol);
                }
                columns.actions.extend(cell);
                columns.action_offsets.push(columns.actions.len());
            }
            let terminals = terminal_start..columns.terminals.len();
            if columns.terminals[terminals.clone()] != admission {
                return Err(CompileError::Malformed(
                    "frozen table admissions differ".into(),
                ));
            }
            columns.rows[index].terminals = terminals;
            columns.rows[index].cells = cell_start..columns.action_offsets.len() - 1;
        }
        let result = columns.finish();
        // Keep the old construction rows as an independent test-only oracle.
        // Pinned grammar construction exercises every state and ordered cell,
        // rather than deriving expected answers from the flat implementation.
        #[cfg(test)]
        {
            assert_eq!(result.maps(), (expected.0, expected.1));
            for (index, admissions) in expected.2.iter().enumerate() {
                assert_eq!(
                    result.row_admissions(StateId::from_index(index)),
                    admissions
                );
            }
        }
        Ok(result)
    }

    pub(super) fn read(
        r: &mut Reader<'_>,
        table_entries: &mut usize,
        action_count: &mut usize,
    ) -> Result<Self, ArtifactError> {
        let limits = r.limits;
        let states = r.count(limits.states, 4, "states")?;
        let mut columns = Columns::new(states);
        for _ in 0..states {
            let n = r.count(limits.symbols, 8, "transition row")?;
            super::artifact_budget(table_entries, n, limits.table_entries, "table entries")?;
            reserve(&mut columns.transition_symbols, n)?;
            reserve(&mut columns.transition_states, n)?;
            let start = columns.transition_symbols.len();
            let mut previous = None;
            for _ in 0..n {
                let symbol = super::read_symbol(r)?;
                if previous.is_some_and(|p| p >= symbol) {
                    return Err(ArtifactError::Invalid("transition order"));
                }
                previous = Some(symbol);
                columns.transition_symbols.push(symbol);
                columns.transition_states.push(super::read_state(r)?);
            }
            columns.rows.push(StateRow {
                transitions: start..columns.transition_symbols.len(),
                terminals: 0..0,
                cells: 0..0,
            });
        }
        for index in 0..states {
            let n = r.count(limits.symbols.saturating_add(1), 6, "action row")?;
            super::artifact_budget(table_entries, n, limits.table_entries, "table entries")?;
            reserve(&mut columns.terminals, n)?;
            reserve(&mut columns.action_offsets, n)?;
            let terminal_start = columns.terminals.len();
            let cell_start = columns.action_offsets.len() - 1;
            let mut previous = None;
            for _ in 0..n {
                let at = super::read_lookahead(r)?;
                if previous.is_some_and(|p| p >= at) {
                    return Err(ArtifactError::Invalid("lookahead order"));
                }
                previous = Some(at);
                if let Lookahead::Terminal(symbol) = at {
                    columns.terminals.push(symbol);
                }
                super::read_actions_into(r, action_count, &mut columns.actions)?;
                columns.action_offsets.push(columns.actions.len());
            }
            columns.rows[index].terminals = terminal_start..columns.terminals.len();
            columns.rows[index].cells = cell_start..columns.action_offsets.len() - 1;
        }
        Ok(columns.finish())
    }

    pub(super) fn state_count(&self) -> usize {
        self.rows.len()
    }

    pub(super) fn actions(&self, state: StateId, at: Lookahead) -> &[Action] {
        let row = &self.rows[state.index()];
        let terminal_count = row.terminals.len();
        let offset = match at {
            Lookahead::Terminal(symbol) => self.terminals[row.terminals.clone()]
                .binary_search(&symbol)
                .ok(),
            Lookahead::End => (row.cells.len() > terminal_count).then_some(terminal_count),
        };
        offset.map_or(&[], |offset| self.cell(row.cells.start + offset))
    }

    fn cell(&self, index: usize) -> &[Action] {
        &self.actions[self.action_offsets[index]..self.action_offsets[index + 1]]
    }

    pub(super) fn transition(&self, state: StateId, symbol: SymbolId) -> Option<StateId> {
        let row = &self.rows[state.index()];
        self.transition_symbols[row.transitions.clone()]
            .binary_search(&symbol)
            .ok()
            .map(|offset| self.transition_states[row.transitions.start + offset])
    }

    pub(super) fn state_transitions(
        &self,
        state: StateId,
    ) -> impl ExactSizeIterator<Item = (SymbolId, StateId)> + '_ {
        let range = self.rows[state.index()].transitions.clone();
        self.transition_symbols[range.clone()]
            .iter()
            .copied()
            .zip(self.transition_states[range].iter().copied())
    }

    pub(super) fn action_row(
        &self,
        state: StateId,
    ) -> impl ExactSizeIterator<Item = (Lookahead, &[Action])> + '_ {
        let row = &self.rows[state.index()];
        row.cells.clone().enumerate().map(move |(offset, cell)| {
            let at = self.terminals[row.terminals.clone()]
                .get(offset)
                .map_or(Lookahead::End, |&symbol| Lookahead::Terminal(symbol));
            (at, self.cell(cell))
        })
    }

    pub(super) fn row_admissions(&self, state: StateId) -> &[SymbolId] {
        &self.terminals[self.rows[state.index()].terminals.clone()]
    }

    #[cfg(test)]
    pub(super) fn maps(&self) -> (Graph, Rows) {
        let graph = (0..self.state_count())
            .map(|state| self.state_transitions(StateId::from_index(state)).collect())
            .collect();
        let rows = (0..self.state_count())
            .map(|state| {
                self.action_row(StateId::from_index(state))
                    .map(|(at, actions)| (at, actions.to_vec()))
                    .collect()
            })
            .collect();
        (graph, rows)
    }

    #[cfg(test)]
    pub(super) fn mutate(&mut self, change: impl FnOnce(&mut Graph, &mut Rows)) {
        let (mut graph, mut rows) = self.maps();
        change(&mut graph, &mut rows);
        let admissions = rows
            .iter()
            .map(|row| {
                row.keys()
                    .filter_map(|at| {
                        if let Lookahead::Terminal(symbol) = at {
                            Some(*symbol)
                        } else {
                            None
                        }
                    })
                    .collect()
            })
            .collect();
        *self = Self::from_maps(graph, rows, admissions).unwrap();
    }
}

struct Columns {
    rows: Vec<StateRow>,
    terminals: Vec<SymbolId>,
    action_offsets: Vec<usize>,
    actions: Vec<Action>,
    transition_symbols: Vec<SymbolId>,
    transition_states: Vec<StateId>,
}

impl Columns {
    fn new(states: usize) -> Self {
        Self {
            rows: Vec::with_capacity(states),
            terminals: Vec::new(),
            action_offsets: vec![0],
            actions: Vec::new(),
            transition_symbols: Vec::new(),
            transition_states: Vec::new(),
        }
    }

    fn finish(self) -> FrozenTables {
        FrozenTables {
            rows: self.rows.into_boxed_slice(),
            terminals: self.terminals.into_boxed_slice(),
            action_offsets: self.action_offsets.into_boxed_slice(),
            actions: self.actions.into_boxed_slice(),
            transition_symbols: self.transition_symbols.into_boxed_slice(),
            transition_states: self.transition_states.into_boxed_slice(),
        }
    }
}

pub(super) fn reserve<T>(values: &mut Vec<T>, additional: usize) -> Result<(), ArtifactError> {
    values
        .len()
        .checked_add(additional)
        .ok_or(ArtifactError::Length)?;
    values
        .try_reserve(additional)
        .map_err(|_| ArtifactError::Allocation("parser tables"))
}

#[cfg(test)]
mod tests {
    use super::super::{
        ReductionId, artifact_budget, read_actions, read_lookahead, read_state, read_symbol,
        write_actions, write_lookahead,
    };
    use super::*;
    use crate::artifact::{ArtifactLimits, Writer};

    fn symbol(index: usize) -> SymbolId {
        SymbolId::from_index(index)
    }
    fn state(index: usize) -> StateId {
        StateId::from_index(index)
    }

    fn example() -> (Graph, Rows) {
        let graph = vec![
            [(symbol(2), state(1)), (symbol(400), state(2))].into(),
            Default::default(),
            [(symbol(400), state(2))].into(),
            Default::default(),
        ];
        let rows = vec![
            [
                (
                    Lookahead::Terminal(symbol(2)),
                    vec![Action::Shift(state(1))],
                ),
                (
                    Lookahead::Terminal(symbol(400)),
                    vec![
                        Action::Reduce(ReductionId::from_index(9)),
                        Action::Shift(state(2)),
                    ],
                ),
                (
                    Lookahead::End,
                    vec![Action::Reduce(ReductionId::from_index(7))],
                ),
            ]
            .into(),
            [(Lookahead::End, vec![Action::Accept])].into(),
            [(Lookahead::Terminal(symbol(400)), vec![])].into(),
            Default::default(),
        ];
        (graph, rows)
    }

    fn admissions(rows: &Rows) -> Vec<Vec<SymbolId>> {
        rows.iter()
            .map(|row| {
                row.keys()
                    .filter_map(|at| match at {
                        Lookahead::Terminal(symbol) => Some(*symbol),
                        Lookahead::End => None,
                    })
                    .collect()
            })
            .collect()
    }

    fn wire(graph: &Graph, rows: &Rows) -> Vec<u8> {
        let mut w = Writer::new();
        w.number(graph.len()).unwrap();
        for row in graph {
            w.number(row.len()).unwrap();
            for (&symbol, &state) in row {
                w.number(symbol.index()).unwrap();
                w.number(state.index()).unwrap();
            }
        }
        for row in rows {
            w.number(row.len()).unwrap();
            for (&at, actions) in row {
                write_lookahead(&mut w, at).unwrap();
                write_actions(&mut w, actions).unwrap();
            }
        }
        w.bytes
    }

    /// The independently retained row reader, including the original ordering
    /// of counts, aggregate budgets, keys and action payload reads.
    fn legacy_read(r: &mut Reader<'_>) -> Result<(Graph, Rows), ArtifactError> {
        let limits = r.limits;
        let n = r.count(limits.states, 4, "states")?;
        let mut graph = Vec::with_capacity(n);
        let mut table_entries = 0;
        for _ in 0..n {
            let n = r.count(limits.symbols, 8, "transition row")?;
            artifact_budget(&mut table_entries, n, limits.table_entries, "table entries")?;
            let mut row = std::collections::BTreeMap::new();
            let mut previous = None;
            for _ in 0..n {
                let symbol = read_symbol(r)?;
                if previous.is_some_and(|p| p >= symbol) {
                    return Err(ArtifactError::Invalid("transition order"));
                }
                previous = Some(symbol);
                row.insert(symbol, read_state(r)?);
            }
            graph.push(row);
        }
        let mut rows = Vec::with_capacity(n);
        let mut action_count = 0;
        for _ in 0..n {
            let n = r.count(limits.symbols.saturating_add(1), 6, "action row")?;
            artifact_budget(&mut table_entries, n, limits.table_entries, "table entries")?;
            let mut row = std::collections::BTreeMap::new();
            let mut previous = None;
            for _ in 0..n {
                let at = read_lookahead(r)?;
                if previous.is_some_and(|p| p >= at) {
                    return Err(ArtifactError::Invalid("lookahead order"));
                }
                previous = Some(at);
                row.insert(at, read_actions(r, &mut action_count)?);
            }
            rows.push(row);
        }
        Ok((graph, rows))
    }

    fn compare_decode(bytes: &[u8], limits: ArtifactLimits) {
        let mut old = Reader::new(bytes, limits);
        let mut new = Reader::new(bytes, limits);
        let old = legacy_read(&mut old).and_then(|rows| old.finish().map(|()| rows));
        let new = FrozenTables::read(&mut new, &mut 0, &mut 0)
            .and_then(|tables| new.finish().map(|()| tables.maps()));
        match (old, new) {
            (Ok(old), Ok(new)) => assert_eq!(old, new),
            (Err(old), Err(new)) => assert_eq!(old.to_string(), new.to_string()),
            (old, new) => panic!("decode outcomes differ: old={old:?}, new={new:?}"),
        }
    }

    #[test]
    fn flat_columns_preserve_maps_order_admissions_empty_cells_and_exact_iterators() {
        let (graph, rows) = example();
        let expected_admissions = admissions(&rows);
        let expected_bytes = wire(&graph, &rows);
        let tables =
            FrozenTables::from_maps(graph.clone(), rows.clone(), expected_admissions.clone())
                .unwrap();
        assert_eq!(tables.maps(), (graph.clone(), rows.clone()));
        for index in 0..graph.len() {
            let q = state(index);
            let mut transitions = tables.state_transitions(q);
            assert_eq!(transitions.len(), graph[index].len());
            transitions.next();
            assert_eq!(transitions.len(), graph[index].len().saturating_sub(1));
            let mut cells = tables.action_row(q);
            assert_eq!(cells.len(), rows[index].len());
            cells.next();
            assert_eq!(cells.len(), rows[index].len().saturating_sub(1));
            assert_eq!(tables.row_admissions(q), expected_admissions[index]);
            for id in [0, 2, 3, 400, 1000] {
                assert_eq!(
                    tables.transition(q, symbol(id)),
                    graph[index].get(&symbol(id)).copied()
                );
                assert_eq!(
                    tables.actions(q, Lookahead::Terminal(symbol(id))),
                    rows[index]
                        .get(&Lookahead::Terminal(symbol(id)))
                        .map_or(&[][..], Vec::as_slice)
                );
            }
            assert_eq!(
                tables.actions(q, Lookahead::End),
                rows[index]
                    .get(&Lookahead::End)
                    .map_or(&[][..], Vec::as_slice)
            );
        }
        let (flat_graph, flat_rows) = tables.maps();
        assert_eq!(wire(&flat_graph, &flat_rows), expected_bytes);
        compare_decode(&expected_bytes, ArtifactLimits::default());
    }

    #[test]
    fn direct_decode_keeps_every_work_and_aggregate_limit_boundary() {
        let (graph, rows) = example();
        let bytes = wire(&graph, &rows);
        for work in 0..300 {
            compare_decode(
                &bytes,
                ArtifactLimits {
                    work,
                    ..Default::default()
                },
            );
        }
        for table_entries in 0..12 {
            compare_decode(
                &bytes,
                ArtifactLimits {
                    table_entries,
                    ..Default::default()
                },
            );
        }
        for actions in 0..12 {
            compare_decode(
                &bytes,
                ArtifactLimits {
                    actions,
                    ..Default::default()
                },
            );
        }
        for states in 0..6 {
            compare_decode(
                &bytes,
                ArtifactLimits {
                    states,
                    ..Default::default()
                },
            );
        }
        for end in 0..bytes.len() {
            compare_decode(&bytes[..end], ArtifactLimits::default());
        }
    }

    #[test]
    fn unsorted_and_duplicate_keys_fail_before_their_later_bad_payloads() {
        for second in [2, 1] {
            let mut w = Writer::new();
            w.number(1).unwrap();
            w.number(2).unwrap();
            w.number(2).unwrap();
            w.number(0).unwrap();
            w.number(second).unwrap();
            w.number(u32::MAX as usize).unwrap();
            w.number(0).unwrap();
            for work in 0..50 {
                compare_decode(
                    &w.bytes,
                    ArtifactLimits {
                        work,
                        ..Default::default()
                    },
                );
            }
        }
        for second in [
            Lookahead::Terminal(symbol(2)),
            Lookahead::Terminal(symbol(1)),
        ] {
            let mut w = Writer::new();
            w.number(1).unwrap();
            w.number(0).unwrap();
            w.number(2).unwrap();
            write_lookahead(&mut w, Lookahead::Terminal(symbol(2))).unwrap();
            write_actions(&mut w, &[Action::Reduce(ReductionId::from_index(0))]).unwrap();
            write_lookahead(&mut w, second).unwrap();
            w.number(1).unwrap();
            w.tag(255);
            for work in 0..50 {
                compare_decode(
                    &w.bytes,
                    ArtifactLimits {
                        work,
                        ..Default::default()
                    },
                );
            }
        }
    }

    #[test]
    fn publication_work_is_explicit_and_admission_mismatches_refuse() {
        let (graph, rows) = example();
        // 4 rows, 3 transitions, 5 cells, 5 actions and 3 terminal keys.
        assert_eq!(publication_work(&graph, &rows).unwrap(), 8 + 3 + 10 + 5 + 6);
        let mut admitted = admissions(&rows);
        admitted[0].reverse();
        assert!(FrozenTables::from_maps(graph.clone(), rows.clone(), admitted).is_err());
        let work = publication_work(&graph, &rows).unwrap();
        let budget = super::super::CompileWork::new(work - 1);
        assert!(
            budget
                .charge(work, "frozen table publication work")
                .is_err()
        );
        assert_eq!(budget.used.get(), 0);
        let budget = super::super::CompileWork::new(work);
        budget
            .charge(work, "frozen table publication work")
            .unwrap();
        assert_eq!(budget.used.get(), work);
        assert!(reserve(&mut vec![0u8], usize::MAX).is_err());
    }
}
