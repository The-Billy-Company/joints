//! A private persistent sequence for speculative parse histories.
//!
//! Callers must precharge each operation's work before calling it. Histories
//! share immutable full blocks; a fork copies only a bounded unsealed tail.
use std::sync::Arc;

const CHUNK: usize = 64;

struct Chunk<T: Copy> {
    previous: Option<Arc<Self>>,
    values: Vec<T>,
}

impl<T: Copy> Drop for Chunk<T> {
    fn drop(&mut self) {
        let mut link = self.previous.take();
        while let Some(previous) = link {
            match Arc::try_unwrap(previous) {
                Ok(mut unique) => link = unique.previous.take(),
                Err(_) => break,
            }
        }
    }
}

pub(super) struct History<T: Copy> {
    previous: Option<Arc<Chunk<T>>>,
    tail: Vec<T>,
    len: usize,
}

impl<T: Copy> Default for History<T> {
    fn default() -> Self {
        Self {
            previous: None,
            tail: Vec::new(),
            len: 0,
        }
    }
}

impl<T: Copy> Clone for History<T> {
    fn clone(&self) -> Self {
        Self {
            previous: self.previous.clone(),
            tail: self.tail.clone(),
            len: self.len,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct LengthOverflow;

impl<T: Copy> History<T> {
    pub(super) fn len(&self) -> usize {
        self.len
    }

    pub(super) fn is_empty(&self) -> bool {
        self.len == 0
    }

    pub(super) fn last(&self) -> Option<&T> {
        self.tail.last().or_else(|| {
            self.previous
                .as_deref()
                .and_then(|chunk| chunk.values.last())
        })
    }

    pub(super) fn clone_work(&self) -> usize {
        // One shared handle and a bounded owned allocation/copy.
        self.tail.len().saturating_mul(2).saturating_add(1)
    }

    pub(super) fn push_work(&self) -> usize {
        if self.tail.len() == CHUNK {
            // Seal one buffer, allocate its Arc and the new bounded tail.
            CHUNK + 6
        } else if self.tail.len() == self.tail.capacity() {
            self.tail
                .len()
                .saturating_add(self.next_capacity())
                .saturating_add(2)
        } else {
            1
        }
    }

    pub(super) fn push(&mut self, value: T) -> Result<(), LengthOverflow> {
        let len = self.len.checked_add(1).ok_or(LengthOverflow)?;
        if self.tail.len() == CHUNK {
            self.previous = Some(Arc::new(Chunk {
                previous: self.previous.take(),
                values: std::mem::take(&mut self.tail),
            }));
            // The sealing bill already includes one bounded CHUNK allocation.
            // Long histories avoid regrowing the next tail through five buffers.
            // Initial and short histories keep their small incremental storage.
            self.tail = Vec::with_capacity(CHUNK);
        }
        if self.tail.len() == self.tail.capacity() {
            let capacity = self.next_capacity();
            self.tail.reserve_exact(capacity - self.tail.len());
        }
        self.tail.push(value);
        self.len = len;
        Ok(())
    }

    fn next_capacity(&self) -> usize {
        self.tail.capacity().saturating_mul(2).clamp(4, CHUNK)
    }

    pub(super) fn from_vec_work(len: usize) -> usize {
        let blocks = len.saturating_sub(1) / CHUNK;
        len.saturating_mul(2)
            .saturating_add(blocks.saturating_mul(2))
            .saturating_add(1)
    }

    pub(super) fn from_vec(values: Vec<T>) -> Self {
        let len = values.len();
        let mut values = values.into_iter();
        let mut previous = None;
        while values.len() > CHUNK {
            let mut block = Vec::with_capacity(CHUNK);
            block.extend(values.by_ref().take(CHUNK));
            previous = Some(Arc::new(Chunk {
                previous,
                values: block,
            }));
        }
        // Do not collect the remaining IntoIter directly: Vec may reuse its
        // original unbounded allocation even though at most CHUNK remain.
        let mut tail = Vec::with_capacity(values.len());
        tail.extend(values);
        Self {
            previous,
            tail,
            len,
        }
    }

    pub(super) fn iter_work(&self) -> usize {
        // One pointer slot, one link visit and one reversal per sealed block.
        ((self.len - self.tail.len()) / CHUNK)
            .saturating_mul(3)
            .saturating_add(1)
    }

    pub(super) fn iter(&self) -> Iter<'_, T> {
        let mut chunks = Vec::with_capacity((self.len - self.tail.len()) / CHUNK);
        let mut previous = self.previous.as_deref();
        while let Some(chunk) = previous {
            chunks.push(chunk.values.as_slice());
            previous = chunk.previous.as_deref();
        }
        chunks.reverse();
        Iter {
            chunks: chunks.into_iter(),
            current: [].iter(),
            tail: self.tail.iter(),
        }
    }

    pub(super) fn materialize_work(&self) -> usize {
        self.len.saturating_mul(2).saturating_add(self.iter_work())
    }

    pub(super) fn into_vec(self) -> Vec<T> {
        if self.is_empty() {
            return Vec::new();
        }
        let mut values = Vec::with_capacity(self.len);
        values.extend(self.iter().copied());
        values
    }
}

pub(super) struct Iter<'a, T: Copy> {
    chunks: std::vec::IntoIter<&'a [T]>,
    current: std::slice::Iter<'a, T>,
    tail: std::slice::Iter<'a, T>,
}

impl<'a, T: Copy> Iterator for Iter<'a, T> {
    type Item = &'a T;

    fn next(&mut self) -> Option<Self::Item> {
        loop {
            if let Some(value) = self.current.next() {
                return Some(value);
            }
            match self.chunks.next() {
                Some(chunk) => self.current = chunk.iter(),
                None => return self.tail.next(),
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_and_vec_import_have_the_exact_original_order() {
        for len in [0, 1, 63, 64, 65, 127, 128, 129, 4096] {
            let expected: Vec<_> = (0..len).collect();
            let history = History::from_vec(expected.clone());
            assert!(history.tail.capacity() <= CHUNK);
            assert_eq!(history.len(), len);
            assert_eq!(history.is_empty(), len == 0);
            assert_eq!(history.last(), expected.last());
            assert_eq!(history.iter().copied().collect::<Vec<_>>(), expected);
            assert_eq!(history.into_vec(), expected);
        }
    }

    #[test]
    fn boundary_forks_diverge_without_mutating_any_retained_snapshot() {
        for len in [0, 1, 63, 64, 65, 127, 128, 129, 8192] {
            let mut history = History::default();
            for n in 0..len {
                history.push(n).unwrap();
            }
            let snapshot = history.clone();
            let mut fork = history.clone();
            history.push(len).unwrap();
            fork.push(usize::MAX).unwrap();
            fork.push(len + 1).unwrap();
            assert_eq!(snapshot.into_vec(), (0..len).collect::<Vec<_>>());
            assert_eq!(history.into_vec(), (0..=len).collect::<Vec<_>>());
            let mut expected: Vec<_> = (0..len).collect();
            expected.extend([usize::MAX, len + 1]);
            assert_eq!(fork.into_vec(), expected);
        }
    }

    #[test]
    fn sealed_tails_reserve_one_bounded_buffer_without_growing_short_histories() {
        let mut history = History::default();
        assert_eq!(history.tail.capacity(), 0);
        history.push(0usize).unwrap();
        assert_eq!(history.tail.capacity(), 4);
        for n in 1..CHUNK {
            history.push(n).unwrap();
        }
        let retained = history.clone();
        assert_eq!(history.push_work(), CHUNK + 6);
        history.push(CHUNK).unwrap();
        assert_eq!(history.tail.capacity(), CHUNK);
        for n in CHUNK + 1..2 * CHUNK {
            assert_eq!(history.push_work(), 1);
            history.push(n).unwrap();
            assert_eq!(history.tail.capacity(), CHUNK);
        }
        assert_eq!(retained.into_vec(), (0..CHUNK).collect::<Vec<_>>());
        assert_eq!(history.into_vec(), (0..2 * CHUNK).collect::<Vec<_>>());
    }

    #[test]
    fn clone_work_copies_only_the_bounded_tail_not_the_history() {
        for tail in [1, 17, 63, 64] {
            let small = History::from_vec((0..tail).collect::<Vec<_>>());
            let large = History::from_vec((0..64 * 1024 + tail).collect::<Vec<_>>());
            let fork = large.clone();
            assert!(Arc::ptr_eq(
                large.previous.as_ref().unwrap(),
                fork.previous.as_ref().unwrap()
            ));
            assert_ne!(large.tail.as_ptr(), fork.tail.as_ptr());
            assert_eq!(small.clone_work(), large.clone_work());
            assert!(large.clone_work() <= 2 * CHUNK + 1);
            assert!(large.push_work() <= 2 * CHUNK + 6);
            assert!(large.materialize_work() >= 2 * large.len());
            assert!(History::<usize>::from_vec_work(large.len()) >= 2 * large.len());
        }
        assert_eq!(History::<usize>::from_vec_work(usize::MAX), usize::MAX);
    }

    #[test]
    fn long_shared_and_unique_chains_drop_on_a_small_stack() {
        std::thread::Builder::new()
            .stack_size(128 * 1024)
            .spawn(|| {
                let history = History::from_vec((0..1024 * 1024).collect::<Vec<_>>());
                let older = history.clone();
                let mut newer = history.clone();
                for n in 0..1024 {
                    newer.push(n).unwrap();
                }
                drop(history);
                drop(older);
                drop(newer);
                drop(History::from_vec((0..1024 * 1024).collect::<Vec<_>>()));
            })
            .unwrap()
            .join()
            .unwrap();
    }

    #[test]
    fn checked_length_failure_does_not_mutate_a_history() {
        let mut history = History::default();
        history.push(7).unwrap();
        history.len = usize::MAX;
        assert_eq!(history.push(8), Err(LengthOverflow));
        assert_eq!(history.tail, [7]);
    }
}
