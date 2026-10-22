use std::{ops::Range, sync::Arc};

use crate::{CompiledGrammar, FieldId, ProductionId, StateId, SymbolId};

/// A validated half-open range of source bytes.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ByteSpan {
    start: u32,
    end: u32,
}

impl ByteSpan {
    pub fn new(start: usize, end: usize) -> Option<Self> {
        (start <= end && end <= u32::MAX as usize).then_some(Self {
            start: start as u32,
            end: end as u32,
        })
    }

    pub fn start(self) -> usize {
        self.start as usize
    }

    pub fn end(self) -> usize {
        self.end as usize
    }

    pub fn range(self) -> Range<usize> {
        self.start()..self.end()
    }

    pub fn is_empty(self) -> bool {
        self.start == self.end
    }

    pub(crate) fn covering(self, other: Self) -> Self {
        Self {
            start: self.start.min(other.start),
            end: self.end.max(other.end),
        }
    }
}

/// Positions use zero-based rows and byte columns, including non-UTF-8 input.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Point {
    pub row: u32,
    pub column: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct NodeId(pub(crate) u32);

impl NodeId {
    pub(crate) fn index(self) -> usize {
        self.0 as usize
    }
}

#[derive(Debug)]
pub(crate) struct NodeData {
    pub symbol: SymbolId,
    // The alias itself remains in immutable grammar metadata.
    pub alias: Option<(ProductionId, usize)>,
    pub span: ByteSpan,
    pub field: Option<FieldId>,
    pub parent: Option<NodeId>,
    pub children: Range<usize>,
    pub extra: bool,
}

/// A stop describes parse evidence rather than an operational failure.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Stop {
    Accepted,
    Stray {
        at: usize,
    },
    Unexpected {
        symbol: SymbolId,
        at: usize,
        state: StateId,
    },
    Truncated,
}

impl std::fmt::Display for Stop {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Accepted => f.write_str("accepted"),
            Self::Stray { at } => write!(f, "stray byte at {at}"),
            Self::Unexpected { at, .. } => write!(f, "unexpected token at {at}"),
            Self::Truncated => f.write_str("truncated input"),
        }
    }
}

/// Results of an executed structural walk over the complete node arena.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Survey {
    pub walked: usize,
    pub held: usize,
    pub loose: usize,
    pub disorder: usize,
    pub torn: usize,
}

impl Survey {
    pub fn is_sound(self) -> bool {
        self.walked == self.held && self.loose == 0 && self.disorder == 0 && self.torn == 0
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Confidence {
    pub accepted: bool,
    pub sound: bool,
    pub roots: usize,
    pub repairs: usize,
}

/// A repair describes missing source separately from syntax that was derived.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RepairKind {
    Deleted { felled: bool },
    Supplied { symbol: SymbolId },
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Repair {
    pub span: ByteSpan,
    pub kind: RepairKind,
    pub context: Stop,
    pub heads: usize,
    pub shifted: usize,
}

impl Confidence {
    pub fn is_strict(self) -> bool {
        self.accepted && self.sound && self.roots == 1 && self.repairs == 0
    }
}

/// A completed immutable forest, retaining its grammar and original source.
#[derive(Debug)]
pub struct TreeSnapshot {
    pub(crate) grammar: Arc<CompiledGrammar>,
    pub(crate) source: Arc<[u8]>,
    pub(crate) nodes: Vec<NodeData>,
    pub(crate) children: Vec<NodeId>,
    pub(crate) roots: Vec<NodeId>,
    pub(crate) stop: Stop,
    pub(crate) lines: Vec<usize>,
    pub(crate) survey: Survey,
    pub(crate) repairs: Vec<Repair>,
    pub(crate) spurned: usize,
}

impl TreeSnapshot {
    /// Resolve a bounds-checked arena position in this particular snapshot.
    pub fn node_at(&self, index: usize) -> Option<Node<'_>> {
        (index < self.nodes.len()).then_some(Node {
            tree: self,
            id: NodeId(index as u32),
        })
    }

    pub fn grammar(&self) -> &Arc<CompiledGrammar> {
        &self.grammar
    }

    pub fn source(&self) -> &[u8] {
        &self.source
    }

    /// Retained payload bytes, excluding shared grammar and allocator overhead.
    /// Source storage is shared when snapshots refer to the same source Arc.
    pub fn storage_bytes(&self) -> usize {
        [
            self.source.len(),
            self.nodes.capacity().saturating_mul(size_of::<NodeData>()),
            self.children.capacity().saturating_mul(size_of::<NodeId>()),
            self.roots.capacity().saturating_mul(size_of::<NodeId>()),
            self.lines.capacity().saturating_mul(size_of::<usize>()),
            self.repairs.capacity().saturating_mul(size_of::<Repair>()),
        ]
        .into_iter()
        .fold(0, usize::saturating_add)
    }

    pub fn stop(&self) -> Stop {
        self.stop
    }

    pub fn stop_symbol(&self) -> Option<&str> {
        match self.stop {
            Stop::Unexpected { symbol, .. } => Some(&self.grammar.automaton.symbol(symbol).name),
            _ => None,
        }
    }

    pub fn confidence(&self) -> Confidence {
        Confidence {
            accepted: self.stop == Stop::Accepted,
            sound: self.survey.is_sound(),
            roots: self.roots.len(),
            repairs: self.repairs.len(),
        }
    }

    pub fn survey(&self) -> Survey {
        self.survey
    }

    pub fn repairs(&self) -> &[Repair] {
        &self.repairs
    }
    pub fn mends(&self) -> usize {
        self.repairs
            .iter()
            .filter(|r| matches!(r.kind, RepairKind::Deleted { .. }))
            .count()
    }
    pub fn skipped(&self) -> usize {
        self.repairs
            .iter()
            .filter(|r| matches!(r.kind, RepairKind::Deleted { .. }))
            .map(|r| r.span.end() - r.span.start())
            .sum()
    }
    pub fn supplied(&self) -> usize {
        self.repairs
            .iter()
            .filter(|r| matches!(r.kind, RepairKind::Supplied { .. }))
            .count()
    }
    pub fn spurned(&self) -> usize {
        self.spurned
    }
    pub fn repair_symbol(&self, repair: &Repair) -> Option<&str> {
        match repair.kind {
            RepairKind::Supplied { symbol }
                if symbol.index() < self.grammar.automaton.symbol_count() =>
            {
                Some(&self.grammar.automaton.symbol(symbol).name)
            }
            _ => None,
        }
    }

    pub fn roots(&self) -> impl ExactSizeIterator<Item = Node<'_>> + DoubleEndedIterator + '_ {
        self.roots.iter().map(|&id| Node { tree: self, id })
    }

    pub fn root(&self) -> Option<Node<'_>> {
        (self.roots.len() == 1).then(|| Node {
            tree: self,
            id: self.roots[0],
        })
    }

    /// Deepest covering node, including the first source-ordered boundary
    /// match for an empty span. Deleted gaps in a forest remain uncovered.
    pub fn covering(&self, span: ByteSpan) -> Option<Node<'_>> {
        if span.end() > self.source.len() {
            return None;
        }
        let mut run = self.roots.as_slice();
        let mut found = None;
        while let Some(id) = self.covering_in(run, span) {
            found = Some(Node { tree: self, id });
            run = &self.children[self.nodes[id.index()].children.clone()];
        }
        found
    }

    fn covering_in(&self, run: &[NodeId], span: ByteSpan) -> Option<NodeId> {
        let covers = |id: NodeId| {
            let own = self.nodes[id.index()].span;
            own.start() <= span.start() && span.end() <= own.end()
        };
        if run.len() <= 48 {
            return run.iter().copied().find(|&id| covers(id));
        }
        let mut at = run
            .partition_point(|id| self.nodes[id.index()].span.start() <= span.start())
            .checked_sub(1)?;
        if !covers(run[at]) {
            return None;
        }
        while at > 0 && covers(run[at - 1]) {
            at -= 1;
        }
        Some(run[at])
    }

    pub(crate) fn measure(&self) -> Survey {
        let mut out = Survey {
            held: self.nodes.len(),
            ..Survey::default()
        };
        let mut root_end = 0;
        for &root in &self.roots {
            if let Some(node) = self.nodes.get(root.index()) {
                if node.span.start() < root_end {
                    out.disorder += 1;
                }
                root_end = node.span.end();
            }
        }
        let mut visited = vec![false; self.nodes.len()];
        let mut pending: Vec<_> = self.roots.iter().copied().map(|id| (id, None)).collect();
        while let Some((id, parent)) = pending.pop() {
            let Some(node) = self.nodes.get(id.index()) else {
                out.torn += 1;
                continue;
            };
            if std::mem::replace(&mut visited[id.index()], true) {
                out.torn += 1;
                continue;
            }
            out.walked += 1;
            if node.parent != parent {
                out.torn += 1;
            }
            if node.span.end() > self.source.len() {
                out.loose += 1;
            }
            let Some(children) = self.children.get(node.children.clone()) else {
                out.torn += 1;
                continue;
            };
            let mut previous = node.span.start();
            for &child in children {
                let Some(data) = self.nodes.get(child.index()) else {
                    out.torn += 1;
                    continue;
                };
                if data.span.start() < node.span.start() || data.span.end() > node.span.end() {
                    out.loose += 1;
                }
                if data.span.start() < previous {
                    out.disorder += 1;
                }
                previous = data.span.end();
                pending.push((child, Some(id)));
            }
        }
        out
    }

    fn point(&self, at: usize) -> Point {
        let row = self
            .lines
            .partition_point(|&line| line <= at)
            .saturating_sub(1);
        Point {
            row: row as u32,
            column: (at - self.lines[row]) as u32,
        }
    }
}

/// A node is a checked borrow of one snapshot; it cannot address another tree.
#[derive(Clone, Copy, Debug)]
pub struct Node<'tree> {
    tree: &'tree TreeSnapshot,
    id: NodeId,
}

impl<'tree> Node<'tree> {
    /// Arena position, meaningful only together with this node's snapshot.
    pub fn index(self) -> usize {
        self.id.index()
    }

    fn data(self) -> &'tree NodeData {
        &self.tree.nodes[self.id.index()]
    }

    fn alias(self) -> Option<&'tree crate::compiler::Alias> {
        let (production, step) = self.data().alias?;
        self.tree.grammar.automaton.production(production).steps[step]
            .alias
            .as_ref()
    }

    pub fn name(self) -> &'tree str {
        self.alias().map_or_else(
            || {
                self.tree
                    .grammar
                    .automaton
                    .symbol(self.data().symbol)
                    .name
                    .as_str()
            },
            |alias| alias.name.as_ref(),
        )
    }

    pub fn is_named(self) -> bool {
        self.alias().map_or_else(
            || {
                self.tree
                    .grammar
                    .automaton
                    .symbol(self.data().symbol)
                    .shape
                    .named()
            },
            |alias| alias.named,
        )
    }

    pub fn is_extra(self) -> bool {
        self.data().extra
    }

    pub fn span(self) -> ByteSpan {
        self.data().span
    }

    pub fn text(self) -> &'tree [u8] {
        &self.tree.source[self.span().range()]
    }

    pub fn start_point(self) -> Point {
        self.tree.point(self.span().start())
    }

    pub fn end_point(self) -> Point {
        self.tree.point(self.span().end())
    }

    pub fn field(self) -> Option<&'tree str> {
        self.data()
            .field
            .map(|id| self.tree.grammar.automaton.field_name(id))
    }

    pub fn parent(self) -> Option<Self> {
        self.data().parent.map(|id| Self {
            tree: self.tree,
            id,
        })
    }

    pub fn children(self) -> impl ExactSizeIterator<Item = Self> + DoubleEndedIterator + 'tree {
        self.tree.children[self.data().children.clone()]
            .iter()
            .map(move |&id| Self {
                tree: self.tree,
                id,
            })
    }

    pub fn child_by_field(self, field: &str) -> Option<Self> {
        self.children().find(|node| node.field() == Some(field))
    }

    fn sibling_run(self) -> &'tree [NodeId] {
        self.data()
            .parent
            .map_or(self.tree.roots.as_slice(), |parent| {
                &self.tree.children[self.tree.nodes[parent.index()].children.clone()]
            })
    }

    fn neighbor(self, forward: bool, named: bool) -> Option<Self> {
        let run = self.sibling_run();
        let at = run.iter().position(|&id| id == self.id)?;
        let make = |id| Self {
            tree: self.tree,
            id,
        };
        if forward {
            run[at + 1..]
                .iter()
                .copied()
                .map(make)
                .find(|node| !named || node.is_named())
        } else {
            run[..at]
                .iter()
                .rev()
                .copied()
                .map(make)
                .find(|node| !named || node.is_named())
        }
    }

    pub fn next_sibling(self) -> Option<Self> {
        self.neighbor(true, false)
    }
    pub fn prev_sibling(self) -> Option<Self> {
        self.neighbor(false, false)
    }
    pub fn next_named_sibling(self) -> Option<Self> {
        self.neighbor(true, true)
    }
    pub fn prev_named_sibling(self) -> Option<Self> {
        self.neighbor(false, true)
    }

    pub fn depth(self) -> usize {
        let mut depth = 0;
        let mut at = self.parent();
        while let Some(parent) = at {
            depth += 1;
            at = parent.parent();
        }
        depth
    }

    /// Count without recursive host-stack use; allocation refusal stays explicit.
    pub fn subtree_size(self) -> Result<usize, std::collections::TryReserveError> {
        let mut pending = Vec::new();
        pending.try_reserve(1)?;
        pending.push(self.id);
        let mut count = 0;
        while let Some(id) = pending.pop() {
            count += 1;
            let children = &self.tree.children[self.tree.nodes[id.index()].children.clone()];
            pending.try_reserve(children.len())?;
            pending.extend_from_slice(children);
        }
        Ok(count)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn navigation_preserves_wide_boundaries_named_extras_and_forest_gaps() {
        let grammar =
            CompiledGrammar::compile(include_bytes!("../../test/grammar/json.json")).unwrap();
        let source = format!("[{}]", vec!["1"; 256].join(","));
        let tree = grammar.session().parse(source.as_bytes()).unwrap();
        assert_eq!(
            tree.root().unwrap().subtree_size().unwrap(),
            tree.survey().walked
        );
        let first = tree.covering(ByteSpan::new(1, 2).unwrap()).unwrap();
        assert_eq!(first.text(), b"1");
        assert_eq!(
            tree.covering(ByteSpan::new(2, 2).unwrap()).unwrap().index(),
            first.index()
        );
        let comma = first.next_sibling().unwrap();
        assert_eq!(comma.name(), ",");
        assert_eq!(comma.prev_sibling().unwrap().index(), first.index());
        let next = first.next_named_sibling().unwrap();
        assert_eq!(next.span().start(), 3);
        assert_eq!(next.prev_named_sibling().unwrap().index(), first.index());
        for at in 0..source.len() {
            let span = ByteSpan::new(at, at + 1).unwrap();
            let mut slow = tree
                .roots()
                .find(|n| n.span().start() <= at && at < n.span().end());
            while let Some(parent) = slow {
                match parent
                    .children()
                    .find(|n| n.span().start() <= at && at < n.span().end())
                {
                    Some(child) => slow = Some(child),
                    None => break,
                }
            }
            assert_eq!(tree.covering(span).map(Node::index), slow.map(Node::index));
        }
        let partial = grammar.session().parse_partial(b"[1,@").unwrap();
        assert!(partial.root().is_none());
        assert!(partial.covering(ByteSpan::new(3, 4).unwrap()).is_none());
        let roots: Vec<_> = partial.roots().collect();
        for (i, root) in roots.iter().copied().enumerate() {
            assert_eq!(root.depth(), 0);
            assert!(root.parent().is_none());
            assert_eq!(
                root.prev_sibling().map(Node::index),
                i.checked_sub(1).map(|i| roots[i].index())
            );
            assert_eq!(
                root.next_sibling().map(Node::index),
                roots.get(i + 1).map(|n| n.index())
            );
        }
        let grammar = CompiledGrammar::compile(br##"{"name":"extras","rules":{
            "document":{"type":"SEQ","members":[{"type":"STRING","value":"a"},{"type":"STRING","value":"b"}]},
            "comment":{"type":"PATTERN","value":"#[^\\n]*"}},
            "extras":[{"type":"SYMBOL","name":"comment"},{"type":"PATTERN","value":"\\s+"}]}"##).unwrap();
        let tree = grammar.session().parse(b"a# note\nb").unwrap();
        let root = tree.root().unwrap();
        let children: Vec<_> = root.children().collect();
        let comment = children[0].next_named_sibling().unwrap();
        assert!(comment.is_extra());
        assert_eq!(comment.name(), "comment");
        assert!(comment.field().is_none());
        assert_eq!(
            children
                .last()
                .unwrap()
                .prev_named_sibling()
                .unwrap()
                .index(),
            comment.index()
        );
    }

    #[test]
    fn survey_detects_reordered_overlapping_and_duplicated_forest_roots() {
        let grammar =
            CompiledGrammar::compile(include_bytes!("../../test/grammar/json.json")).unwrap();
        let mut tree = grammar.session().parse_partial(b"[1,2").unwrap();
        assert!(tree.survey().is_sound());
        assert!(tree.roots.len() > 2);
        tree.roots.swap(0, 2);
        assert!(!tree.measure().is_sound());
        tree.roots.swap(0, 2);
        let second = tree.roots[1];
        let original = tree.nodes[second.index()].span;
        tree.nodes[second.index()].span = ByteSpan::new(0, 2).unwrap();
        assert!(!tree.measure().is_sound());
        tree.nodes[second.index()].span = original;
        tree.roots.push(tree.roots[0]);
        assert!(!tree.measure().is_sound());
    }
}
