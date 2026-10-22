//! Immutable parser rows, published once and shared by every worker.
//!
//! Construction keeps its mutable maps. Publication and artifact decoding own
//! flat columns; terminal keys double as each row's lexical admission slate.

use std::{num::NonZeroU32, ops::Range};

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
    action_ranges: FrozenCells,
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
            let cell_start = columns.action_ranges.len();
            for (at, cell) in row {
                if let Lookahead::Terminal(symbol) = at {
                    columns.terminals.push(symbol);
                }
                let start = columns.actions.len();
                columns.actions.extend(cell);
                columns
                    .finish_cell(start)
                    .map_err(|_| CompileError::Limit("frozen table action allocation"))?;
            }
            let terminals = terminal_start..columns.terminals.len();
            if columns.terminals[terminals.clone()] != admission {
                return Err(CompileError::Malformed(
                    "frozen table admissions differ".into(),
                ));
            }
            columns.rows[index].terminals = terminals;
            columns.rows[index].cells = cell_start..columns.action_ranges.len();
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
            columns.action_ranges.reserve(n)?;
            let terminal_start = columns.terminals.len();
            let cell_start = columns.action_ranges.len();
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
                let start = columns.actions.len();
                super::read_actions_into(r, action_count, &mut columns.actions)?;
                columns.finish_cell(start)?;
            }
            columns.rows[index].terminals = terminal_start..columns.terminals.len();
            columns.rows[index].cells = cell_start..columns.action_ranges.len();
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
        let range = self.action_ranges.range(index);
        &self.actions[range.start as usize..range.end as usize]
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

const INDIRECT: u32 = 1 << 31;
// Eight side ranges permit at most 64 bytes of prefix overhead. Beyond that,
// side capacity must fit the four bytes saved by every visited descriptor.
const SIDE_PREFIX_RANGES: usize = 8;

fn side_capacity_limit(cells: usize) -> usize {
    cells / 2 + SIDE_PREFIX_RANGES
}

fn next_side_capacity(len: usize, capacity: usize, cells: usize) -> Option<usize> {
    let needed = len.checked_add(1)?;
    let target = if needed <= capacity {
        capacity
    } else {
        capacity.checked_mul(2)?.max(needed).max(4)
    };
    (target <= side_capacity_limit(cells)).then_some(target)
}

#[derive(Debug, Eq, PartialEq)]
enum CellIndexes<C, R> {
    Packed { cells: C, ranges: R },
    Wide(R),
}

type CellColumns = CellIndexes<Vec<u32>, Vec<Range<u32>>>;
type FrozenCells = CellIndexes<Box<[u32]>, Box<[Range<u32>]>>;

fn indirect_index(index: usize) -> Option<u32> {
    u32::try_from(index).ok().filter(|&id| id < INDIRECT)
}

fn packed_range(cell: u32, ranges: &[Range<u32>]) -> Range<u32> {
    if cell == 0 {
        0..0
    } else if cell < INDIRECT {
        cell - 1..cell
    } else {
        ranges[(cell & !INDIRECT) as usize].clone()
    }
}

impl FrozenCells {
    fn range(&self, index: usize) -> Range<u32> {
        match self {
            Self::Packed { cells, ranges } => packed_range(cells[index], ranges),
            Self::Wide(ranges) => ranges[index].clone(),
        }
    }
}

impl CellColumns {
    fn new() -> Self {
        Self::Packed {
            cells: Vec::new(),
            ranges: Vec::new(),
        }
    }

    fn len(&self) -> usize {
        match self {
            Self::Packed { cells, .. } => cells.len(),
            Self::Wide(ranges) => ranges.len(),
        }
    }

    fn reserve(&mut self, additional: usize) -> Result<(), ArtifactError> {
        match self {
            Self::Packed { cells, .. } => reserve(cells, additional),
            Self::Wide(ranges) => reserve(ranges, additional),
        }
    }

    // Every original range remains representable. Large payload indexes,
    // side indexes, or a side capacity that would erase the saving promote
    // transactionally, once, to the original wide form. finish_cell has
    // reserved one descriptor before forming or reusing its range.
    fn push(&mut self, range: Range<u32>) -> Result<(), ArtifactError> {
        if let Self::Packed { cells, ranges } = self {
            let next_len = cells.len().checked_add(1).ok_or(ArtifactError::Length)?;
            let descriptor = if range.start == range.end {
                Some(0)
            } else if range.end - range.start == 1 && range.end < INDIRECT {
                Some(range.end)
            } else if range.end - range.start > 1 {
                indirect_index(ranges.len()).map(|index| index | INDIRECT)
            } else {
                None
            };
            if let Some(descriptor) = descriptor {
                if descriptor & INDIRECT == 0 {
                    cells.push(descriptor);
                    return Ok(());
                }
                // Predict growth before allocating it. A new owned buffer
                // keeps the previous binding intact on allocation failure.
                if let Some(target) = next_side_capacity(ranges.len(), ranges.capacity(), next_len)
                {
                    if target > ranges.capacity() {
                        let mut grown = Vec::new();
                        grown
                            .try_reserve_exact(target)
                            .map_err(|_| ArtifactError::Allocation("parser tables"))?;
                        if grown.capacity() <= side_capacity_limit(next_len) {
                            grown.extend(ranges.iter().cloned());
                            *ranges = grown;
                        }
                    }
                    if ranges.capacity() > ranges.len()
                        && ranges.capacity() <= side_capacity_limit(next_len)
                    {
                        ranges.push(range);
                        cells.push(descriptor);
                        return Ok(());
                    }
                }
            }
            let mut wide = Vec::new();
            // Match the descriptor's existing row reservation rather than
            // repeatedly growing from a short prefix of that same row.
            wide.try_reserve_exact(cells.capacity())
                .map_err(|_| ArtifactError::Allocation("parser tables"))?;
            wide.extend(cells.iter().map(|&cell| packed_range(cell, ranges)));
            *self = Self::Wide(wide);
        }
        if let Self::Wide(ranges) = self {
            reserve(ranges, 1)?;
            ranges.push(range);
        }
        Ok(())
    }

    fn finish(self) -> FrozenCells {
        match self {
            Self::Packed { cells, ranges } => FrozenCells::Packed {
                cells: cells.into_boxed_slice(),
                ranges: ranges.into_boxed_slice(),
            },
            Self::Wide(ranges) => FrozenCells::Wide(ranges.into_boxed_slice()),
        }
    }
}

struct Columns {
    rows: Vec<StateRow>,
    terminals: Vec<SymbolId>,
    action_ranges: CellColumns,
    singletons: Vec<[Option<NonZeroU32>; 2]>,
    accept: Option<NonZeroU32>,
    actions: Vec<Action>,
    transition_symbols: Vec<SymbolId>,
    transition_states: Vec<StateId>,
}

impl Columns {
    fn new(states: usize) -> Self {
        Self {
            rows: Vec::with_capacity(states),
            terminals: Vec::new(),
            action_ranges: CellColumns::new(),
            singletons: vec![[None; 2]; states],
            accept: None,
            actions: Vec::new(),
            transition_symbols: Vec::new(),
            transition_states: Vec::new(),
        }
    }

    // Deduplicate only singletons through bounded construction scratch.
    // Decoding appends directly, so a large ordered conflict needs no second
    // complete payload allocation. All encoded actions retain their debits.
    fn finish_cell(&mut self, start: usize) -> Result<(), ArtifactError> {
        self.action_ranges.reserve(1)?;
        let width = self.actions.len() - start;
        if width == 0 {
            self.action_ranges.push(0..0)?;
            return Ok(());
        }
        let singleton = if width == 1 {
            match self.actions[start] {
                Action::Accept => Some(&mut self.accept),
                Action::Shift(state) => self
                    .singletons
                    .get_mut(state.index())
                    .map(|ids| &mut ids[0]),
                Action::Reduce(reduction) => self
                    .singletons
                    .get_mut(reduction.index())
                    .map(|ids| &mut ids[1]),
            }
        } else {
            None
        };
        if let Some(end) = singleton.as_ref().and_then(|id| **id) {
            self.actions.truncate(start);
            self.action_ranges.push(end.get() - 1..end.get())?;
            return Ok(());
        }
        let range = u32::try_from(start).map_err(|_| ArtifactError::Length)?
            ..u32::try_from(self.actions.len()).map_err(|_| ArtifactError::Length)?;
        if let Some(slot) = singleton {
            // A singleton's nonzero end is exactly its start plus one.
            *slot = NonZeroU32::new(range.end);
        }
        self.action_ranges.push(range)?;
        Ok(())
    }

    fn finish(self) -> FrozenTables {
        FrozenTables {
            rows: self.rows.into_boxed_slice(),
            terminals: self.terminals.into_boxed_slice(),
            action_ranges: self.action_ranges.finish(),
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

    #[test]
    fn packed_cells_preserve_empty_singleton_and_ordered_side_ranges() {
        let expected = [0..0, 2..3, 3..6, INDIRECT - 2..INDIRECT - 1];
        let mut columns = CellColumns::new();
        columns.reserve(expected.len()).unwrap();
        for range in &expected {
            columns.push(range.clone()).unwrap();
        }
        assert!(matches!(columns, CellColumns::Packed { .. }));
        let frozen = columns.finish();
        for (index, range) in expected.into_iter().enumerate() {
            assert_eq!(frozen.range(index), range);
        }
    }

    #[test]
    fn packed_cells_promote_to_wide_without_limiting_original_u32_ranges() {
        let expected = [
            0..0,
            2..3,
            3..6,
            INDIRECT - 1..INDIRECT,
            u32::MAX - 1..u32::MAX,
            5..8,
        ];
        let mut columns = CellColumns::new();
        for range in &expected {
            columns.reserve(1).unwrap();
            columns.push(range.clone()).unwrap();
        }
        assert!(matches!(columns, CellColumns::Wide(_)));
        let frozen = columns.finish();
        for (index, range) in expected.into_iter().enumerate() {
            assert_eq!(frozen.range(index), range);
        }
        assert_eq!(
            indirect_index(usize::try_from(INDIRECT - 1).unwrap()),
            Some(INDIRECT - 1)
        );
        assert_eq!(indirect_index(usize::try_from(INDIRECT).unwrap()), None);
        assert_eq!(indirect_index(usize::MAX), None);
    }

    #[test]
    fn adaptive_side_storage_obeys_fixed_prefix_bound_and_promotes_only_once() {
        assert_eq!(size_of::<Range<u32>>(), 2 * size_of::<u32>());
        let n = 65536;
        for shape in 0..4 {
            let range_at = |index| {
                let multi = match shape {
                    0 => true,
                    1 => index >= n / 3,
                    2 => index % 5 != 0,
                    _ => index % 100 == 0,
                };
                let start = u32::try_from(index * 3).unwrap();
                start..start + if multi { 2 } else { 1 }
            };
            let mut columns = CellColumns::new();
            let mut wide_seen = false;
            for index in 0..n {
                if index % 256 == 0 {
                    columns.reserve(256).unwrap();
                }
                columns.reserve(1).unwrap();
                columns.push(range_at(index)).unwrap();
                match &columns {
                    CellColumns::Packed { cells, ranges } => {
                        assert!(!wide_seen);
                        assert!(ranges.capacity() <= side_capacity_limit(cells.len()));
                        assert!(ranges.len() <= side_capacity_limit(cells.len()));
                    }
                    CellColumns::Wide(_) => wide_seen = true,
                }
            }
            assert_eq!(wide_seen, shape != 3);
            let frozen = columns.finish();
            for index in 0..n {
                assert_eq!(frozen.range(index), range_at(index));
            }
        }
        assert_eq!(next_side_capacity(16, 16, 17), None);
        assert_eq!(next_side_capacity(15, 16, 16), Some(16));
        assert_eq!(next_side_capacity(usize::MAX, usize::MAX, usize::MAX), None);
    }

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
    fn singleton_payloads_share_ranges_and_ordered_conflicts_stay_complete() {
        let (graph, rows) = example();
        let graph: Graph = graph.into_iter().cycle().take(64).collect();
        let rows: Rows = rows.into_iter().cycle().take(64).collect();
        let expected = (graph.clone(), rows.clone());
        let tables = FrozenTables::from_maps(graph, rows.clone(), admissions(&rows)).unwrap();
        assert_eq!(tables.maps(), expected);
        assert_eq!(
            tables.rows.iter().map(|row| row.cells.len()).sum::<usize>(),
            80
        );
        assert_eq!(tables.actions.len(), 35);
        assert_eq!(tables.action_ranges.range(0), tables.action_ranges.range(5));
        assert_ne!(tables.action_ranges.range(1), tables.action_ranges.range(6));
        assert_eq!(tables.cell(1), tables.cell(6));
        assert!(
            tables
                .actions(state(2), Lookahead::Terminal(symbol(400)))
                .is_empty()
        );
    }

    #[test]
    fn singleton_ids_outside_scratch_bounds_preserve_the_original_payload_and_reads() {
        let graph: Graph = vec![Default::default()];
        let rows: Rows = vec![
            [
                (
                    Lookahead::Terminal(symbol(0)),
                    vec![Action::Shift(state(u32::MAX as usize))],
                ),
                (
                    Lookahead::Terminal(symbol(1)),
                    vec![Action::Reduce(ReductionId::from_index(u32::MAX as usize))],
                ),
                (
                    Lookahead::End,
                    vec![Action::Reduce(ReductionId::from_index(9))],
                ),
            ]
            .into(),
        ];
        let tables =
            FrozenTables::from_maps(graph.clone(), rows.clone(), admissions(&rows)).unwrap();
        assert_eq!(tables.maps(), (graph.clone(), rows.clone()));
        assert_eq!(tables.actions.len(), 3);
        let bytes = wire(&graph, &rows);
        for work in 0..100 {
            compare_decode(
                &bytes,
                ArtifactLimits {
                    work,
                    ..Default::default()
                },
            );
        }
        compare_decode(&bytes, ArtifactLimits::default());
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
