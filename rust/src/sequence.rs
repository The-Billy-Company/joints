//! A persistent, measured AVL sequence of actual parse-move effects.
//!
//! Leaves are ordered by index even when their byte weight is zero. Effects
//! are never split by a byte cut: the document chooses replacement segments.
//! All versions use the same live effect store. Immutable nodes share prior
//! subtrees; the store remains append-only and owns the canonical handles.

use std::{ops::Range, sync::Arc};

use crate::effects::{Effect, EffectError, EffectStore};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct Segment {
    pub bytes: usize,
    pub effect: Effect,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) struct SequenceCost {
    pub compositions: usize,
    pub nodes_created: usize,
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum SequenceError {
    #[error(transparent)]
    Effect(#[from] EffectError),
    #[error("invalid leaf range {start}..{end} for {len} segments")]
    InvalidRange {
        start: usize,
        end: usize,
        len: usize,
    },
    #[error("leaf boundary {index} is outside 0..={len}")]
    InvalidBoundary { index: usize, len: usize },
    #[error("byte offset {offset} is outside 0..={len}")]
    InvalidByte { offset: usize, len: usize },
    #[error("sequence measure exceeds its integer range")]
    Overflow,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg(test)]
pub(crate) enum ByteLocation {
    Inside {
        index: usize,
        start: usize,
        end: usize,
    },
    /// Inclusive boundary indices whose prefix byte measures equal the offset.
    /// A run of zero-byte segments therefore has first < last.
    Boundary { first: usize, last: usize },
}

type Link = Option<Arc<Node>>;

struct Node {
    bytes: usize,
    len: usize,
    height: u32,
    product: Effect,
    kind: Kind,
}

enum Kind {
    Leaf(Segment),
    Branch(Arc<Node>, Arc<Node>),
}

#[derive(Clone)]
pub(crate) struct Sequence {
    owner: u64,
    root: Link,
    cost: SequenceCost,
}

struct Build<'a> {
    store: &'a mut EffectStore,
    cost: SequenceCost,
}

impl Build<'_> {
    fn compose(&mut self, a: Effect, b: Effect) -> Result<Effect, SequenceError> {
        self.cost.compositions = self
            .cost
            .compositions
            .checked_add(1)
            .ok_or(SequenceError::Overflow)?;
        Ok(self.store.compose(a, b)?)
    }

    fn leaf(&mut self, segment: Segment) -> Result<Arc<Node>, SequenceError> {
        self.cost.nodes_created = self
            .cost
            .nodes_created
            .checked_add(1)
            .ok_or(SequenceError::Overflow)?;
        Ok(Arc::new(Node {
            bytes: segment.bytes,
            len: 1,
            height: 1,
            product: segment.effect,
            kind: Kind::Leaf(segment),
        }))
    }

    fn branch(&mut self, left: Arc<Node>, right: Arc<Node>) -> Result<Arc<Node>, SequenceError> {
        let bytes = left
            .bytes
            .checked_add(right.bytes)
            .ok_or(SequenceError::Overflow)?;
        let len = left
            .len
            .checked_add(right.len)
            .ok_or(SequenceError::Overflow)?;
        let height = left
            .height
            .max(right.height)
            .checked_add(1)
            .ok_or(SequenceError::Overflow)?;
        let product = self.compose(left.product, right.product)?;
        self.cost.nodes_created = self
            .cost
            .nodes_created
            .checked_add(1)
            .ok_or(SequenceError::Overflow)?;
        Ok(Arc::new(Node {
            bytes,
            len,
            height,
            product,
            kind: Kind::Branch(left, right),
        }))
    }

    fn bulk(&mut self, leaves: &[Segment]) -> Result<Link, SequenceError> {
        match leaves.len() {
            0 => Ok(None),
            1 => Ok(Some(self.leaf(leaves[0])?)),
            n => {
                let middle = n / 2;
                let left = self.bulk(&leaves[..middle])?.expect("nonempty half");
                let right = self.bulk(&leaves[middle..])?.expect("nonempty half");
                Ok(Some(self.branch(left, right)?))
            }
        }
    }

    fn balance(&mut self, left: Arc<Node>, right: Arc<Node>) -> Result<Arc<Node>, SequenceError> {
        if left.height > right.height + 1 {
            let Kind::Branch(a, b) = &left.kind else {
                unreachable!("an imbalanced side is a branch")
            };
            if a.height >= b.height {
                let next = self.branch(Arc::clone(b), right)?;
                self.branch(Arc::clone(a), next)
            } else {
                let Kind::Branch(b1, b2) = &b.kind else {
                    unreachable!("a taller inner child is a branch")
                };
                let l = self.branch(Arc::clone(a), Arc::clone(b1))?;
                let r = self.branch(Arc::clone(b2), right)?;
                self.branch(l, r)
            }
        } else if right.height > left.height + 1 {
            let Kind::Branch(a, b) = &right.kind else {
                unreachable!("an imbalanced side is a branch")
            };
            if b.height >= a.height {
                let next = self.branch(left, Arc::clone(a))?;
                self.branch(next, Arc::clone(b))
            } else {
                let Kind::Branch(a1, a2) = &a.kind else {
                    unreachable!("a taller inner child is a branch")
                };
                let l = self.branch(left, Arc::clone(a1))?;
                let r = self.branch(Arc::clone(a2), Arc::clone(b))?;
                self.branch(l, r)
            }
        } else {
            self.branch(left, right)
        }
    }

    fn join(&mut self, left: Link, right: Link) -> Result<Link, SequenceError> {
        let (left, right) = match (left, right) {
            (None, r) => return Ok(r),
            (l, None) => return Ok(l),
            (Some(l), Some(r)) => (l, r),
        };
        let joined = if left.height > right.height + 1 {
            let Kind::Branch(a, b) = &left.kind else {
                unreachable!("tall side is a branch")
            };
            let tail = self
                .join(Some(Arc::clone(b)), Some(right))?
                .expect("nonempty join");
            self.balance(Arc::clone(a), tail)?
        } else if right.height > left.height + 1 {
            let Kind::Branch(a, b) = &right.kind else {
                unreachable!("tall side is a branch")
            };
            let head = self
                .join(Some(left), Some(Arc::clone(a)))?
                .expect("nonempty join");
            self.balance(head, Arc::clone(b))?
        } else {
            self.branch(left, right)?
        };
        Ok(Some(joined))
    }

    fn split(&mut self, root: Link, at: usize) -> Result<(Link, Link), SequenceError> {
        let Some(node) = root else {
            return Ok((None, None));
        };
        if at == 0 {
            return Ok((None, Some(node)));
        }
        if at == node.len {
            return Ok((Some(node), None));
        }
        let Kind::Branch(left, right) = &node.kind else {
            unreachable!("an interior leaf index is a branch")
        };
        if at < left.len {
            let (a, b) = self.split(Some(Arc::clone(left)), at)?;
            Ok((a, self.join(b, Some(Arc::clone(right)))?))
        } else if at == left.len {
            Ok((Some(Arc::clone(left)), Some(Arc::clone(right))))
        } else {
            let (a, b) = self.split(Some(Arc::clone(right)), at - left.len)?;
            Ok((self.join(Some(Arc::clone(left)), a)?, b))
        }
    }

    #[cfg(test)]
    fn range(&mut self, node: &Node, from: usize, to: usize) -> Result<Effect, SequenceError> {
        if from == 0 && to == node.len {
            return Ok(node.product);
        }
        let Kind::Branch(left, right) = &node.kind else {
            unreachable!("a partial nonempty range spans a branch")
        };
        if to <= left.len {
            self.range(left, from, to)
        } else if from >= left.len {
            self.range(right, from - left.len, to - left.len)
        } else {
            let a = self.range(left, from, left.len)?;
            let b = self.range(right, 0, to - left.len)?;
            self.compose(a, b)
        }
    }
}

impl Sequence {
    pub(crate) fn from_segments(
        store: &mut EffectStore,
        segments: &[Segment],
    ) -> Result<Self, SequenceError> {
        validate_segments(store, segments)?;
        let owner = store.owner_id();
        let mut build = Build {
            store,
            cost: SequenceCost::default(),
        };
        let root = build.bulk(segments)?;
        Ok(Self {
            owner,
            root,
            cost: build.cost,
        })
    }

    pub(crate) fn len(&self) -> usize {
        self.root.as_ref().map_or(0, |n| n.len)
    }
    pub(crate) fn byte_len(&self) -> usize {
        self.root.as_ref().map_or(0, |n| n.bytes)
    }
    pub(crate) fn height(&self) -> u32 {
        self.root.as_ref().map_or(0, |n| n.height)
    }
    pub(crate) fn product(&self) -> Effect {
        self.root.as_ref().map_or(Effect::IDENTITY, |n| n.product)
    }
    pub(crate) fn cost(&self) -> SequenceCost {
        self.cost
    }

    fn check_store(&self, store: &EffectStore) -> Result<(), SequenceError> {
        if self.owner != store.owner_id() {
            Err(EffectError::ForeignStore.into())
        } else {
            Ok(())
        }
    }
    fn check_range(&self, range: &Range<usize>) -> Result<(), SequenceError> {
        if range.start > range.end || range.end > self.len() {
            Err(SequenceError::InvalidRange {
                start: range.start,
                end: range.end,
                len: self.len(),
            })
        } else {
            Ok(())
        }
    }

    #[cfg(test)]
    pub(crate) fn get(&self, mut index: usize) -> Option<Segment> {
        let mut node = self.root.as_deref()?;
        if index >= node.len {
            return None;
        }
        loop {
            match &node.kind {
                Kind::Leaf(segment) => return Some(*segment),
                Kind::Branch(left, right) => {
                    if index < left.len {
                        node = left;
                    } else {
                        index -= left.len;
                        node = right;
                    }
                }
            }
        }
    }

    pub(crate) fn offset(&self, mut index: usize) -> Result<usize, SequenceError> {
        if index > self.len() {
            return Err(SequenceError::InvalidBoundary {
                index,
                len: self.len(),
            });
        }
        let mut bytes = 0usize;
        let mut node = self.root.as_deref();
        while let Some(n) = node {
            if index == n.len {
                return bytes.checked_add(n.bytes).ok_or(SequenceError::Overflow);
            }
            match &n.kind {
                Kind::Leaf(_) => return Ok(bytes),
                Kind::Branch(left, right) => {
                    if index < left.len {
                        node = Some(left);
                    } else {
                        index -= left.len;
                        bytes = bytes
                            .checked_add(left.bytes)
                            .ok_or(SequenceError::Overflow)?;
                        node = Some(right);
                    }
                }
            }
        }
        Ok(bytes)
    }

    #[cfg(test)]
    pub(crate) fn range_product(
        &self,
        range: Range<usize>,
        store: &mut EffectStore,
    ) -> Result<Effect, SequenceError> {
        Ok(self.range_measured(range, store)?.0)
    }

    #[cfg(test)]
    fn range_measured(
        &self,
        range: Range<usize>,
        store: &mut EffectStore,
    ) -> Result<(Effect, SequenceCost), SequenceError> {
        self.check_store(store)?;
        self.check_range(&range)?;
        let mut build = Build {
            store,
            cost: SequenceCost::default(),
        };
        let effect = if range.start == range.end {
            Effect::IDENTITY
        } else {
            build.range(
                self.root.as_deref().expect("nonempty range"),
                range.start,
                range.end,
            )?
        };
        Ok((effect, build.cost))
    }

    pub(crate) fn splice(
        &self,
        range: Range<usize>,
        fresh: &[Segment],
        store: &mut EffectStore,
    ) -> Result<Self, SequenceError> {
        self.check_store(store)?;
        self.check_range(&range)?;
        validate_segments(store, fresh)?;
        let kept = self.len() - (range.end - range.start);
        kept.checked_add(fresh.len())
            .ok_or(SequenceError::Overflow)?;
        // Check the final byte measure before allocating paths or composing.
        let removed = self.offset(range.end)? - self.offset(range.start)?;
        let added = fresh.iter().try_fold(0usize, |n, s| {
            n.checked_add(s.bytes).ok_or(SequenceError::Overflow)
        })?;
        (self.byte_len() - removed)
            .checked_add(added)
            .ok_or(SequenceError::Overflow)?;
        if range.start == range.end && fresh.is_empty() {
            return Ok(Self {
                owner: self.owner,
                root: self.root.clone(),
                cost: SequenceCost::default(),
            });
        }
        let mut build = Build {
            store,
            cost: SequenceCost::default(),
        };
        let (left, rest) = build.split(self.root.clone(), range.start)?;
        let (_, right) = build.split(rest, range.end - range.start)?;
        let middle = build.bulk(fresh)?;
        let head = build.join(left, middle)?;
        let root = build.join(head, right)?;
        Ok(Self {
            owner: self.owner,
            root,
            cost: build.cost,
        })
    }

    /// Resolve byte coordinates without choosing an arbitrary side of zero-
    /// byte effects. For a boundary, first..=last are all equal prefix offsets.
    #[cfg(test)]
    pub(crate) fn locate_byte(&self, offset: usize) -> Result<ByteLocation, SequenceError> {
        if offset > self.byte_len() {
            return Err(SequenceError::InvalidByte {
                offset,
                len: self.byte_len(),
            });
        }
        fn lower(node: &Node, at: usize) -> usize {
            if at == 0 {
                return 0;
            }
            match &node.kind {
                Kind::Leaf(_) => 1,
                Kind::Branch(l, r) => {
                    if at <= l.bytes {
                        lower(l, at)
                    } else {
                        l.len + lower(r, at - l.bytes)
                    }
                }
            }
        }
        fn upper(node: &Node, at: usize) -> usize {
            if at >= node.bytes {
                return node.len;
            }
            match &node.kind {
                Kind::Leaf(_) => 0,
                Kind::Branch(l, r) => {
                    if at < l.bytes {
                        upper(l, at)
                    } else {
                        l.len + upper(r, at - l.bytes)
                    }
                }
            }
        }
        let (first, last) = self
            .root
            .as_deref()
            .map_or((0, 0), |n| (lower(n, offset), upper(n, offset)));
        if first <= last {
            Ok(ByteLocation::Boundary { first, last })
        } else {
            Ok(ByteLocation::Inside {
                index: last,
                start: self.offset(last)?,
                end: self.offset(first)?,
            })
        }
    }

    pub(crate) fn iter(&self) -> Segments<'_> {
        let first = self.root.as_deref().into_iter().collect::<Vec<_>>();
        Segments {
            front: first.clone(),
            back: first,
            remaining: self.len(),
        }
    }
}

fn validate_segments(store: &EffectStore, segments: &[Segment]) -> Result<(), SequenceError> {
    let mut bytes = 0usize;
    for segment in segments {
        store.validate_effect(segment.effect)?;
        bytes = bytes
            .checked_add(segment.bytes)
            .ok_or(SequenceError::Overflow)?;
    }
    Ok(())
}

pub(crate) struct Segments<'a> {
    front: Vec<&'a Node>,
    back: Vec<&'a Node>,
    remaining: usize,
}
impl Iterator for Segments<'_> {
    type Item = Segment;
    fn next(&mut self) -> Option<Self::Item> {
        if self.remaining == 0 {
            return None;
        }
        while let Some(node) = self.front.pop() {
            match &node.kind {
                Kind::Leaf(segment) => {
                    self.remaining -= 1;
                    return Some(*segment);
                }
                Kind::Branch(left, right) => {
                    self.front.push(right);
                    self.front.push(left);
                }
            }
        }
        None
    }
    fn size_hint(&self) -> (usize, Option<usize>) {
        (self.remaining, Some(self.remaining))
    }
}
impl DoubleEndedIterator for Segments<'_> {
    fn next_back(&mut self) -> Option<Self::Item> {
        if self.remaining == 0 {
            return None;
        }
        while let Some(node) = self.back.pop() {
            match &node.kind {
                Kind::Leaf(segment) => {
                    self.remaining -= 1;
                    return Some(*segment);
                }
                Kind::Branch(left, right) => {
                    self.back.push(left);
                    self.back.push(right);
                }
            }
        }
        None
    }
}
impl ExactSizeIterator for Segments<'_> {}
impl std::iter::FusedIterator for Segments<'_> {}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{compiler::Automaton, ids::ProductionId};
    use std::collections::VecDeque;

    fn fixture() -> (EffectStore, Vec<Effect>) {
        let graph=Arc::new(Automaton::from_tree_sitter(br#"{"rules":{"doc":{"type":"SEQ","members":[{"type":"SYMBOL","name":"A"},{"type":"SYMBOL","name":"B"}]},"A":{"type":"STRING","value":"a"},"B":{"type":"STRING","value":"b"}}}"#).unwrap());
        let mut store = EffectStore::new(Arc::clone(&graph));
        let mut states = vec![graph.start_state()];
        let mut trace = Vec::new();
        for name in ["A", "B"] {
            let symbol = graph.symbol_by_name(name).unwrap();
            // A and B own distinct literal tokens in this grammar.
            trace.push(store.shift(*states.last().unwrap(), symbol).unwrap());
            states.push(graph.transition(*states.last().unwrap(), symbol).unwrap());
        }
        let doc = graph.start_symbol();
        let p = (0..graph.production_count())
            .map(ProductionId::from_index)
            .find(|&p| graph.production(p).lhs == doc)
            .unwrap();
        trace.push(store.reduce(graph.start_state(), p).unwrap());
        assert!(!store.fold(trace.iter().copied()).unwrap().is_zero());
        (store, trace)
    }

    fn linear(store: &mut EffectStore, leaves: &[Segment]) -> Effect {
        store.fold(leaves.iter().map(|s| s.effect)).unwrap()
    }

    fn check(store: &mut EffectStore, sequence: &Sequence, leaves: &[Segment]) {
        assert_eq!(sequence.len(), leaves.len());
        assert_eq!(sequence.iter().collect::<Vec<_>>(), leaves);
        assert_eq!(
            sequence.iter().rev().collect::<Vec<_>>(),
            leaves.iter().rev().copied().collect::<Vec<_>>()
        );
        assert_eq!(
            sequence.byte_len(),
            leaves.iter().map(|s| s.bytes).sum::<usize>()
        );
        assert_eq!(sequence.product(), linear(store, leaves));
        let mut at = 0;
        for (i, leaf) in leaves.iter().enumerate() {
            assert_eq!(sequence.get(i), Some(*leaf));
            assert_eq!(sequence.offset(i).unwrap(), at);
            at += leaf.bytes;
        }
        assert_eq!(sequence.offset(leaves.len()).unwrap(), at);
        assert_eq!(sequence.get(leaves.len()), None);
        let h = if leaves.is_empty() {
            0
        } else {
            2 * (leaves.len() + 1).ilog2() + 2
        };
        assert!(
            sequence.height() <= h,
            "{} leaves, height {}",
            leaves.len(),
            sequence.height()
        );
    }

    fn random(seed: &mut u64) -> usize {
        *seed ^= *seed << 13;
        *seed ^= *seed >> 7;
        *seed ^= *seed << 17;
        *seed as usize
    }

    #[test]
    fn zero_byte_effects_and_every_byte_boundary_have_explicit_positions() {
        let (mut store, trace) = fixture();
        for weights in [
            vec![],
            vec![0],
            vec![0, 0, 0],
            vec![0, 2, 0, 0, 3, 0],
            vec![1, 1],
        ] {
            let leaves: Vec<_> = weights
                .iter()
                .enumerate()
                .map(|(i, &bytes)| Segment {
                    bytes,
                    effect: trace[i % trace.len()],
                })
                .collect();
            let seq = Sequence::from_segments(&mut store, &leaves).unwrap();
            check(&mut store, &seq, &leaves);
            let mut boundaries = vec![0usize];
            for w in weights {
                boundaries.push(boundaries.last().unwrap() + w);
            }
            for byte in 0..=seq.byte_len() {
                let expected = if let Some(first) = boundaries.iter().position(|&n| n == byte) {
                    ByteLocation::Boundary {
                        first,
                        last: boundaries.iter().rposition(|&n| n == byte).unwrap(),
                    }
                } else {
                    let index = boundaries
                        .windows(2)
                        .position(|w| w[0] < byte && byte < w[1])
                        .unwrap();
                    ByteLocation::Inside {
                        index,
                        start: boundaries[index],
                        end: boundaries[index + 1],
                    }
                };
                assert_eq!(seq.locate_byte(byte).unwrap(), expected);
            }
            assert!(seq.locate_byte(seq.byte_len() + 1).is_err());
        }
    }

    #[test]
    fn ordered_ranges_and_persistent_splices_match_independent_linear_folds() {
        let (mut store, trace) = fixture();
        assert_ne!(
            store.fold([trace[0], trace[1]]).unwrap(),
            store.fold([trace[1], trace[0]]).unwrap()
        );
        let leaves: Vec<_> = trace
            .iter()
            .enumerate()
            .map(|(i, &effect)| Segment {
                bytes: usize::from(i < 2),
                effect,
            })
            .collect();
        let original = Sequence::from_segments(&mut store, &leaves).unwrap();
        for from in 0..=leaves.len() {
            for to in from..=leaves.len() {
                assert_eq!(
                    original.range_product(from..to, &mut store).unwrap(),
                    linear(&mut store, &leaves[from..to])
                );
                for fresh in [
                    vec![],
                    vec![Segment {
                        bytes: 0,
                        effect: Effect::IDENTITY,
                    }],
                    vec![
                        Segment {
                            bytes: 3,
                            effect: Effect::ZERO,
                        },
                        leaves[0],
                    ],
                ] {
                    let mut expected = leaves.clone();
                    expected.splice(from..to, fresh.iter().copied());
                    let changed = original.splice(from..to, &fresh, &mut store).unwrap();
                    check(&mut store, &changed, &expected);
                    check(&mut store, &original, &leaves);
                }
            }
        }
    }

    #[test]
    fn random_edits_preserve_prior_versions_order_and_range_products() {
        let (mut store, trace) = fixture();
        let choices = [Effect::IDENTITY, Effect::ZERO, trace[0], trace[1], trace[2]];
        let mut leaves = Vec::new();
        let mut seq = Sequence::from_segments(&mut store, &leaves).unwrap();
        let mut seed = 0x1eaf_4096_9123u64;
        let (mut defined, mut refused) = (0, 0);
        for _ in 0..1500 {
            let before = seq.clone();
            let old = leaves.clone();
            let from = random(&mut seed) % (leaves.len() + 1);
            let to = from + random(&mut seed) % (leaves.len() - from + 1);
            let count = random(&mut seed) % 8;
            let fresh: Vec<_> = (0..count)
                .map(|_| Segment {
                    bytes: random(&mut seed) % 5,
                    effect: choices[random(&mut seed) % choices.len()],
                })
                .collect();
            seq = seq.splice(from..to, &fresh, &mut store).unwrap();
            leaves.splice(from..to, fresh);
            check(&mut store, &seq, &leaves);
            check(&mut store, &before, &old);
            for _ in 0..8 {
                let a = random(&mut seed) % (leaves.len() + 1);
                let b = a + random(&mut seed) % (leaves.len() - a + 1);
                let expected = linear(&mut store, &leaves[a..b]);
                assert_eq!(seq.range_product(a..b, &mut store).unwrap(), expected);
                if expected.is_zero() {
                    refused += 1
                } else {
                    defined += 1
                }
            }
            let mut expected: VecDeque<_> = leaves.iter().copied().collect();
            let mut iter = seq.iter();
            while !expected.is_empty() {
                assert_eq!(iter.len(), expected.len());
                if random(&mut seed) & 1 == 0 {
                    assert_eq!(iter.next(), expected.pop_front())
                } else {
                    assert_eq!(iter.next_back(), expected.pop_back())
                }
            }
            assert_eq!(iter.next(), None);
            assert_eq!(iter.next_back(), None);
        }
        assert!(defined > 1000 && refused > 1000);
    }

    #[test]
    fn foreign_handles_and_invalid_measures_never_hide_beside_zero() {
        let (mut store, trace) = fixture();
        let graph = Arc::clone(store.automaton());
        let mut other = EffectStore::new(graph);
        let foreign = trace[0];
        for effects in [
            vec![foreign],
            vec![Effect::ZERO, foreign],
            vec![foreign, Effect::ZERO],
        ] {
            let leaves: Vec<_> = effects
                .into_iter()
                .map(|effect| Segment { bytes: 0, effect })
                .collect();
            assert!(matches!(
                Sequence::from_segments(&mut other, &leaves),
                Err(SequenceError::Effect(EffectError::ForeignStore))
            ));
        }
        let seq = Sequence::from_segments(
            &mut store,
            &[Segment {
                bytes: 0,
                effect: Effect::ZERO,
            }],
        )
        .unwrap();
        assert!(matches!(
            seq.range_product(0..0, &mut other),
            Err(SequenceError::Effect(EffectError::ForeignStore))
        ));
        assert!(matches!(
            seq.splice(0..0, &[], &mut other),
            Err(SequenceError::Effect(EffectError::ForeignStore))
        ));
        let old = seq.iter().collect::<Vec<_>>();
        assert!(
            seq.splice(Range { start: 2, end: 1 }, &[], &mut store)
                .is_err()
        );
        assert!(seq.splice(0..2, &[], &mut store).is_err());
        assert!(seq.range_product(0..2, &mut store).is_err());
        assert!(seq.offset(2).is_err());
        assert_eq!(seq.iter().collect::<Vec<_>>(), old);
        let enormous = Sequence::from_segments(
            &mut store,
            &[Segment {
                bytes: usize::MAX,
                effect: Effect::IDENTITY,
            }],
        )
        .unwrap();
        assert_eq!(enormous.offset(1).unwrap(), usize::MAX);
        assert!(matches!(
            enormous.splice(
                1..1,
                &[Segment {
                    bytes: 1,
                    effect: Effect::IDENTITY
                }],
                &mut store
            ),
            Err(SequenceError::Overflow)
        ));
        assert!(matches!(
            Sequence::from_segments(
                &mut store,
                &[
                    Segment {
                        bytes: usize::MAX,
                        effect: Effect::ZERO
                    },
                    Segment {
                        bytes: 1,
                        effect: Effect::IDENTITY
                    }
                ]
            ),
            Err(SequenceError::Overflow)
        ));
        assert_eq!(enormous.byte_len(), usize::MAX);
    }

    #[test]
    fn large_replacements_and_rotations_keep_a_nonzero_actual_trace_product() {
        let (mut store, trace) = fixture();
        let mut leaves = vec![
            Segment {
                bytes: 1,
                effect: Effect::IDENTITY
            };
            4096
        ];
        for (at, effect) in [17, 1000, 4000].into_iter().zip(trace) {
            leaves[at].effect = effect;
        }
        let original = Sequence::from_segments(&mut store, &leaves).unwrap();
        assert!(!original.product().is_zero());
        for (from, to, count) in [
            (0, 8, 0),
            (19, 999, 1),
            (1001, 3999, 31),
            (4096, 4096, 8192),
            (0, 4096, 65537),
        ] {
            let fresh = vec![
                Segment {
                    bytes: 0,
                    effect: Effect::IDENTITY
                };
                count
            ];
            let changed = original.splice(from..to, &fresh, &mut store).unwrap();
            let mut expected = leaves.clone();
            expected.splice(from..to, fresh);
            check(&mut store, &changed, &expected);
            check(&mut store, &original, &leaves);
            assert!(
                changed.cost().compositions
                    <= count.saturating_sub(1) + 64 * (original.height() as usize + 1)
            );
            for cut in [0, changed.len() / 3, changed.len() / 2, changed.len()] {
                assert_eq!(
                    changed
                        .range_product(cut..changed.len(), &mut store)
                        .unwrap(),
                    linear(&mut store, &expected[cut..])
                );
            }
        }
    }

    #[test]
    fn balancing_and_compositions_grow_with_height_not_untouched_leaf_count() {
        let (mut store, _) = fixture();
        let mut averages = Vec::new();
        for n in [256usize, 4096, 65536] {
            let leaves = vec![
                Segment {
                    bytes: 1,
                    effect: Effect::IDENTITY
                };
                n
            ];
            let mut sequence = Sequence::from_segments(&mut store, &leaves).unwrap();
            assert_eq!(sequence.cost().compositions, n - 1);
            let mut seed = 0x6a09_e667u64;
            let mut total = 0;
            for _ in 0..100 {
                let at = random(&mut seed) % n;
                let prior = sequence.clone();
                sequence = sequence
                    .splice(
                        at..at + 1,
                        &[Segment {
                            bytes: 2,
                            effect: Effect::IDENTITY,
                        }],
                        &mut store,
                    )
                    .unwrap();
                assert_eq!(prior.len(), n);
                assert!(sequence.height() <= 2 * (n + 1).ilog2() + 2);
                assert!(sequence.cost().compositions <= 32 * (sequence.height() as usize + 1));
                assert!(sequence.cost().nodes_created <= 40 * (sequence.height() as usize + 1));
                total += sequence.cost().compositions;
                let (_, cost) = sequence
                    .range_measured(n / 4 + 1..3 * n / 4 - 1, &mut store)
                    .unwrap();
                assert!(cost.compositions <= 2 * sequence.height() as usize);
                assert_eq!(
                    sequence
                        .range_measured(0..n, &mut store)
                        .unwrap()
                        .1
                        .compositions,
                    0
                );
            }
            eprintln!(
                "sequence {n} leaves: height {}, mean splice compositions {:.2}",
                sequence.height(),
                total as f64 / 100.0
            );
            averages.push(total);
        }
        assert!(
            averages[2] < 4 * averages[0],
            "composition totals at 256/4096/65536 leaves: {averages:?}"
        );
    }
}
