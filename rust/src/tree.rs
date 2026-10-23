use std::{num::NonZeroU32, ops::Range, sync::Arc};

use crate::{CompiledGrammar, FieldId, ProductionId, StateId, SymbolId};

/// A validated half-open range of source bytes.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ByteSpan {
    start: u32,
    end: u32,
}

impl ByteSpan {
    pub fn new(start: usize, end: usize) -> Option<Self> {
        if start > end {
            return None;
        }
        Some(Self {
            start: u32::try_from(start).ok()?,
            end: u32::try_from(end).ok()?,
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
    alias_production: Option<NonZeroU32>,
    alias_step: u32,
    pub span: ByteSpan,
    field: Option<NonZeroU32>,
    parent: Option<NonZeroU32>,
    children: Range<u32>,
    pub extra: bool,
}

impl NodeData {
    pub(crate) fn new(
        symbol: SymbolId,
        alias: Option<(ProductionId, usize)>,
        span: ByteSpan,
        field: Option<FieldId>,
        parent: Option<NodeId>,
        children: Range<usize>,
        extra: bool,
    ) -> Result<Self, crate::Error> {
        let index = |value: usize| {
            u32::try_from(value)
                .map_err(|_| crate::Error::InvalidTable("tree index exceeds its integer range"))
        };
        let optional = |value: Option<usize>| {
            value
                .map(|value| {
                    index(value)?
                        .checked_add(1)
                        .and_then(NonZeroU32::new)
                        .ok_or(crate::Error::InvalidTable(
                            "tree index exceeds its integer range",
                        ))
                })
                .transpose()
        };
        if children.start > children.end {
            return Err(crate::Error::InvalidTable("invalid tree child range"));
        }
        Ok(Self {
            symbol,
            alias_production: optional(alias.map(|(production, _)| production.index()))?,
            alias_step: index(alias.map_or(0, |(_, step)| step))?,
            span,
            field: optional(field.map(FieldId::index))?,
            parent: optional(parent.map(NodeId::index))?,
            children: index(children.start)?..index(children.end)?,
            extra,
        })
    }

    fn alias(&self) -> Option<(ProductionId, usize)> {
        self.alias_production.map(|production| {
            (
                ProductionId::from_index((production.get() - 1) as usize),
                self.alias_step as usize,
            )
        })
    }

    pub(crate) fn field(&self) -> Option<FieldId> {
        self.field
            .map(|field| FieldId::from_index((field.get() - 1) as usize))
    }

    fn parent(&self) -> Option<NodeId> {
        self.parent.map(|parent| NodeId(parent.get() - 1))
    }

    pub(crate) fn child_range(&self) -> Range<usize> {
        self.children.start as usize..self.children.end as usize
    }
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
        let id = NodeId(u32::try_from(index).ok()?);
        (index < self.nodes.len()).then_some(Node { tree: self, id })
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
            run = &self.children[self.nodes[id.index()].child_range()];
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
        // Published forests have ordered, uniquely owned edges. Prove that
        // directly in arena order, without a visited bitmap or a frontier
        // proportional to the width of the tree. Keep the diagnostic walk for
        // malformed storage so its exact evidence remains unchanged.
        if self.sound_edges() {
            return Survey {
                walked: self.nodes.len(),
                held: self.nodes.len(),
                ..Survey::default()
            };
        }
        self.measure_full()
    }

    fn sound_edges(&self) -> bool {
        let mut edges = self.roots.len();
        let mut previous_root = None;
        let mut root_end = 0;
        for &id in &self.roots {
            let Some(node) = self.nodes.get(id.index()) else {
                return false;
            };
            if node.span.end() > self.source.len()
                || node.parent().is_some()
                || previous_root.is_some_and(|previous| previous >= id.index())
                || node.span.start() < root_end
            {
                return false;
            }
            previous_root = Some(id.index());
            root_end = node.span.end();
        }
        for (index, node) in self.nodes.iter().enumerate() {
            let Some(children) = self.children.get(node.child_range()) else {
                return false;
            };
            let Some(total) = edges.checked_add(children.len()) else {
                return false;
            };
            if total > self.nodes.len() {
                return false;
            }
            edges = total;
            let mut previous_id = index;
            let mut previous_end = node.span.start();
            for &id in children {
                let Some(child) = self.nodes.get(id.index()) else {
                    return false;
                };
                if id.index() <= previous_id
                    || child.parent().map(NodeId::index) != Some(index)
                    || child.span.start() < previous_end
                    || child.span.end() > node.span.end()
                {
                    return false;
                }
                previous_id = id.index();
                previous_end = child.span.end();
            }
        }
        // Roots have no parent; matching child parent links and strictly
        // increasing child IDs make all counted incoming edges unique. Equal
        // edge/node counts cover the arena. Parent IDs decrease toward a root,
        // so there are no cycles or unreachable nodes. Child bounds are nested
        // within their parents, and every root is bounded by the source.
        edges == self.nodes.len()
    }

    fn measure_full(&self) -> Survey {
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
            if node.parent() != parent {
                out.torn += 1;
            }
            if node.span.end() > self.source.len() {
                out.loose += 1;
            }
            let Some(children) = self.children.get(node.child_range()) else {
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
            row: u32::try_from(row).expect("rows bounded by validated source length"),
            column: u32::try_from(at - self.lines[row])
                .expect("column bounded by validated source length"),
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
        let (production, step) = self.data().alias()?;
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
            .field()
            .map(|id| self.tree.grammar.automaton.field_name(id))
    }

    pub fn parent(self) -> Option<Self> {
        self.data().parent().map(|id| Self {
            tree: self.tree,
            id,
        })
    }

    pub fn children(self) -> impl ExactSizeIterator<Item = Self> + DoubleEndedIterator + 'tree {
        self.tree.children[self.data().child_range()]
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
            .parent()
            .map_or(self.tree.roots.as_slice(), |parent| {
                &self.tree.children[self.tree.nodes[parent.index()].child_range()]
            })
    }

    fn neighbor<const FORWARD: bool, const NAMED: bool>(self) -> Option<Self> {
        let run = self.sibling_run();
        let mut from = self;
        if run.len() > 16 {
            // Adjacent leaves are adjacent arena entries. Wide token lists
            // can step directly over those leaves instead of searching the
            // sibling directory again for every punctuation/name hop. When a
            // subtree intervenes, retain the ordered-directory lookup below.
            loop {
                let id = if FORWARD {
                    if run.last() == Some(&from.id) {
                        return None;
                    }
                    if !from.data().child_range().is_empty() {
                        break;
                    }
                    NodeId(from.id.0 + 1)
                } else {
                    if run.first() == Some(&from.id) {
                        return None;
                    }
                    let previous = NodeId(from.id.0 - 1);
                    if self.tree.nodes[previous.index()].parent() != from.data().parent() {
                        break;
                    }
                    previous
                };
                from = Self {
                    tree: self.tree,
                    id,
                };
                if !NAMED || from.is_named() {
                    return Some(from);
                }
            }
        }
        // Materialization assigns IDs in source-ordered preorder, so each
        // sibling run is strictly increasing even when spans are empty or
        // several nodes start at the same byte. Avoid rescanning wide lists
        // from the beginning for each step of a sibling traversal.
        let at = if run.len() <= 16 {
            run.iter().position(|&id| id == from.id)?
        } else {
            run.binary_search_by_key(&from.id.index(), |id| id.index())
                .ok()?
        };
        let make = |id| Self {
            tree: self.tree,
            id,
        };
        if FORWARD {
            run[at + 1..]
                .iter()
                .copied()
                .map(make)
                .find(|node| !NAMED || node.is_named())
        } else {
            run[..at]
                .iter()
                .rev()
                .copied()
                .map(make)
                .find(|node| !NAMED || node.is_named())
        }
    }

    pub fn next_sibling(self) -> Option<Self> {
        self.neighbor::<true, false>()
    }
    pub fn prev_sibling(self) -> Option<Self> {
        self.neighbor::<false, false>()
    }
    pub fn next_named_sibling(self) -> Option<Self> {
        self.neighbor::<true, true>()
    }
    pub fn prev_named_sibling(self) -> Option<Self> {
        self.neighbor::<false, true>()
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

    /// Count from the final descendant in the immutable preorder arena.
    /// No recursive host-stack use or temporary allocation is needed. The
    /// fallible return type is retained for compatibility with existing callers.
    pub fn subtree_size(self) -> Result<usize, std::collections::TryReserveError> {
        let mut last = self;
        while let Some(child) = last.children().next_back() {
            last = child;
        }
        // Every subtree occupies one contiguous preorder interval. IDs are
        // bounded by the source tree's validated u32-sized node arena.
        Ok(last.index() - self.index() + 1)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compact_node_metadata_preserves_boundary_ids_and_rejects_overflow() {
        let maximum = u32::MAX as usize;
        let symbol = SymbolId::from_index(0);
        let alias = Some((ProductionId::from_index(maximum - 1), maximum));
        let field = Some(FieldId::from_index(maximum - 1));
        let parent = Some(NodeId(u32::MAX - 1));
        let span = ByteSpan::new(0, maximum).unwrap();
        let node = NodeData::new(symbol, alias, span, field, parent, 0..maximum, true).unwrap();
        assert_eq!(node.alias(), alias);
        assert_eq!(node.field(), field);
        assert_eq!(node.parent(), parent);
        assert_eq!(node.child_range(), 0..maximum);
        assert_eq!(node.span, span);
        assert!(node.extra);
        assert!(
            NodeData::new(
                symbol,
                None,
                span,
                None,
                Some(NodeId(u32::MAX)),
                0..0,
                false
            )
            .is_err()
        );
        assert!(
            NodeData::new(
                symbol,
                None,
                span,
                Some(FieldId::from_index(maximum)),
                None,
                0..0,
                false
            )
            .is_err()
        );
        assert!(
            NodeData::new(
                symbol,
                Some((ProductionId::from_index(maximum), 0)),
                span,
                None,
                None,
                0..0,
                false
            )
            .is_err()
        );
        if let Some(oversized) = maximum.checked_add(1) {
            assert!(NodeData::new(symbol, None, span, None, None, 0..oversized, false).is_err());
            assert!(
                NodeData::new(
                    symbol,
                    Some((ProductionId::from_index(0), oversized)),
                    span,
                    None,
                    None,
                    0..0,
                    false
                )
                .is_err()
            );
        }
    }

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
    fn sibling_search_matches_linear_navigation_for_every_published_node() {
        let grammar =
            CompiledGrammar::compile(include_bytes!("../../test/grammar/json.json")).unwrap();
        for width in [1, 7, 8, 16, 17, 64, 257] {
            for element in ["1", "[1,2]", "{\"a\":[],\"b\":true}"] {
                let source = format!("[{}]", vec![element; width].join(","));
                for source in [source.as_bytes(), &source.as_bytes()[..source.len() - 1]] {
                    let tree = grammar.session().parse_partial(source).unwrap();
                    for index in 0..tree.nodes.len() {
                        let node = tree.node_at(index).unwrap();
                        let mut pending = vec![node];
                        let mut expected_count = 0;
                        while let Some(descendant) = pending.pop() {
                            expected_count += 1;
                            pending.extend(descendant.children());
                        }
                        assert_eq!(node.subtree_size().unwrap(), expected_count);
                        let siblings: Vec<_> = node.sibling_run().to_vec();
                        assert!(siblings.windows(2).all(|w| w[0].index() < w[1].index()));
                        let at = siblings.iter().position(|&id| id == node.id).unwrap();
                        for named in [false, true] {
                            let next = if named {
                                node.next_named_sibling()
                            } else {
                                node.next_sibling()
                            };
                            let previous = if named {
                                node.prev_named_sibling()
                            } else {
                                node.prev_sibling()
                            };
                            let expected = |id| {
                                let sibling = Node { tree: &tree, id };
                                (!named || sibling.is_named()).then_some(id.index())
                            };
                            assert_eq!(
                                next.map(Node::index),
                                siblings[at + 1..].iter().copied().find_map(expected)
                            );
                            assert_eq!(
                                previous.map(Node::index),
                                siblings[..at].iter().rev().copied().find_map(expected)
                            );
                        }
                    }
                }
            }
        }
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

    #[test]
    fn direct_edge_proof_preserves_the_full_walk_and_malformed_diagnostics() {
        let grammar =
            CompiledGrammar::compile(include_bytes!("../../test/grammar/json.json")).unwrap();
        for source in [
            b"[]".as_slice(),
            b"[1,{\"x\":[true,false]},2]",
            b"[1,{\"x\":[true,false]},",
            b"@",
        ] {
            let mut tree = grammar.session().parse_partial(source).unwrap();
            assert!(tree.sound_edges());
            assert_eq!(tree.measure(), tree.measure_full());
            for index in 0..tree.children.len() {
                let original = tree.children[index];
                for replacement in [NodeId(0), NodeId(u32::MAX)] {
                    tree.children[index] = replacement;
                    assert_eq!(tree.measure(), tree.measure_full());
                }
                tree.children[index] = original;
            }
            for index in 0..tree.nodes.len() {
                let parent = tree.nodes[index].parent;
                tree.nodes[index].parent = None;
                assert_eq!(tree.measure(), tree.measure_full());
                tree.nodes[index].parent = parent;
                let children = tree.nodes[index].children.clone();
                tree.nodes[index].children = 0..u32::MAX;
                assert_eq!(tree.measure(), tree.measure_full());
                tree.nodes[index].children = children;
            }
            if let Some(&root) = tree.roots.first() {
                tree.roots.push(root);
                assert_eq!(tree.measure(), tree.measure_full());
            }
        }
    }

    #[test]
    fn edge_coverage_and_ancestor_bounds_preserve_malformed_surveys() {
        let grammar =
            CompiledGrammar::compile(include_bytes!("../../test/grammar/json.json")).unwrap();
        let mut tree = grammar.session().parse(b"[]").unwrap();
        let node = |parent, children| {
            NodeData::new(
                SymbolId::from_index(0),
                None,
                ByteSpan::new(0, 2).unwrap(),
                None,
                parent,
                children,
                false,
            )
            .unwrap()
        };
        let fallback = |tree: &TreeSnapshot| {
            assert!(!tree.sound_edges());
            let expected = tree.measure_full();
            assert!(!expected.is_sound());
            assert_eq!(tree.measure(), expected);
            expected
        };
        tree.roots = vec![NodeId(0)];

        // An uncovered self-parented node has no counted incoming edge.
        tree.nodes = vec![
            node(None, 0..1),
            node(Some(NodeId(0)), 1..1),
            node(Some(NodeId(2)), 1..1),
        ];
        tree.children = vec![NodeId(1)];
        let survey = fallback(&tree);
        assert_eq!((survey.walked, survey.held, survey.torn), (2, 3, 0));

        // A duplicate incoming edge can hide an orphan in the edge count;
        // exact child-parent equality must reject the unreachable owner's edge.
        tree.nodes = vec![
            node(None, 0..1),
            node(Some(NodeId(0)), 1..2),
            node(Some(NodeId(0)), 2..2),
        ];
        tree.children = vec![NodeId(2), NodeId(2)];
        let survey = fallback(&tree);
        assert_eq!((survey.walked, survey.held, survey.torn), (2, 3, 0));

        tree.nodes = vec![
            node(None, 0..1),
            node(Some(NodeId(0)), 1..2),
            node(Some(NodeId(1)), 2..2),
        ];
        tree.children = vec![NodeId(1), NodeId(2)];
        assert!(tree.sound_edges());
        assert_eq!(tree.measure(), tree.measure_full());
        tree.nodes[0].span = ByteSpan::new(0, 3).unwrap();
        assert_eq!(fallback(&tree).loose, 1);
        tree.nodes[0].span = ByteSpan::new(0, 2).unwrap();
        tree.nodes[2].span = ByteSpan::new(0, 3).unwrap();
        assert_eq!(fallback(&tree).loose, 2);
    }
}
