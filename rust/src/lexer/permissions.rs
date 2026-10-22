//! Bounded exact-key reuse of source-independent native permission ordinals.
use super::{SymbolId, Tier};
use std::sync::{Arc, Weak};

const WAYS: usize = 4;
const SLOTS: usize = 64;
const BYTES: usize = 64 << 10;

struct Entry {
    hash: usize,
    tier: usize,
    fresh: bool,
    admitted: Vec<SymbolId>,
    allow: Vec<u32>,
}
impl Entry {
    fn bytes(&self) -> usize {
        self.admitted.capacity() * size_of::<SymbolId>() + self.allow.capacity() * size_of::<u32>()
    }
}

#[derive(Default)]
pub(super) struct Cache {
    // A weak identity keeps its allocation unique without changing the native
    // worker's strong-owner hint or retaining the lexer itself.
    owner: Weak<()>,
    entries: Vec<Option<Entry>>,
    bytes: usize,
    eviction: usize,
    #[cfg(test)]
    pub(super) disabled: bool,
}

impl Cache {
    pub(super) fn bind(&mut self, owner: &Arc<()>) {
        if self.owner.as_ptr() != Arc::as_ptr(owner) {
            self.entries.clear();
            self.bytes = self.entries.capacity() * size_of::<Option<Entry>>();
            self.eviction = 0;
            self.owner = Arc::downgrade(owner);
        }
    }

    pub(super) fn key(ids: &[SymbolId], fresh: bool) -> usize {
        ids.iter().fold(usize::from(fresh), |key, id| {
            key.wrapping_mul(0x517c_c1b7)
                .wrapping_add(id.index())
                .wrapping_add(1)
        })
    }

    fn bucket(hash: usize, tier: usize) -> usize {
        (hash.wrapping_add(tier.wrapping_mul(0x9e37_79b9)) % (SLOTS / WAYS)) * WAYS
    }

    fn publish_directory(&mut self, mut entries: Vec<Option<Entry>>, pending: usize) -> bool {
        let Some(directory) = entries.capacity().checked_mul(size_of::<Option<Entry>>()) else {
            return false;
        };
        // The old directory remains live until publication. Reconcile both
        // directories and the pending entry before changing any cache state.
        if !self.entries.is_empty()
            || !entries.is_empty()
            || entries.capacity() < SLOTS
            || self
                .bytes
                .checked_add(directory)
                .and_then(|bytes| bytes.checked_add(pending))
                .is_none_or(|bytes| bytes > BYTES)
        {
            return false;
        }
        entries.resize_with(SLOTS, || None);
        self.entries = entries;
        self.bytes = directory;
        true
    }

    pub(super) fn get(
        &self,
        hash: usize,
        ids: &[SymbolId],
        fresh: bool,
        tier: usize,
    ) -> Option<&[u32]> {
        #[cfg(test)]
        if self.disabled {
            return None;
        }
        let bucket = Self::bucket(hash, tier);
        self.entries
            .get(bucket..bucket + WAYS)?
            .iter()
            .find_map(|entry| {
                let entry = entry.as_ref()?;
                (entry.hash == hash
                    && entry.tier == tier
                    && entry.fresh == fresh
                    && entry.admitted == ids)
                    .then_some(entry.allow.as_slice())
            })
    }

    // Optional acceleration stands down before allocating an oversized key.
    // Preflight old plus new buffers while preparing a replacement, and check
    // allocator-delivered capacities before retaining optional acceleration.
    pub(super) fn insert(
        &mut self,
        hash: usize,
        ids: &[SymbolId],
        fresh: bool,
        tier: usize,
        allow: &[u32],
    ) {
        #[cfg(test)]
        if self.disabled {
            return;
        }
        let Some(payload) = ids
            .len()
            .checked_mul(size_of::<SymbolId>())
            .and_then(|bytes| bytes.checked_add(allow.len().checked_mul(size_of::<u32>())?))
        else {
            return;
        };
        let directory = if self.entries.capacity() < SLOTS {
            SLOTS * size_of::<Option<Entry>>()
        } else {
            0
        };
        let Some(used) = self
            .bytes
            .checked_add(directory)
            .filter(|&bytes| bytes <= BYTES)
        else {
            return;
        };
        if payload > BYTES - used {
            return;
        }
        let mut admitted = Vec::new();
        let mut ordinals = Vec::new();
        if admitted.try_reserve_exact(ids.len()).is_err()
            || ordinals.try_reserve_exact(allow.len()).is_err()
        {
            return;
        }
        let entry = Entry {
            hash,
            tier,
            fresh,
            admitted,
            allow: ordinals,
        };
        if entry.bytes() > BYTES - used {
            return;
        }
        if self.entries.is_empty() {
            if self.entries.capacity() < SLOTS {
                let mut entries = Vec::new();
                if entries.try_reserve_exact(SLOTS).is_err()
                    || !self.publish_directory(entries, entry.bytes())
                {
                    return;
                }
            } else {
                // bind cleared the values but retained this already checked
                // allocation. No new directory is needed for another lexer.
                self.entries.resize_with(SLOTS, || None);
            }
        }
        let mut entry = entry;
        entry.admitted.extend_from_slice(ids);
        entry.allow.extend_from_slice(allow);
        let bucket = Self::bucket(hash, tier);
        let at = self.entries[bucket..bucket + WAYS]
            .iter()
            .position(Option::is_none)
            .map_or(bucket + self.eviction % WAYS, |at| bucket + at);
        let old = self.entries[at].as_ref().map_or(0, Entry::bytes);
        self.bytes = self.bytes - old + entry.bytes();
        self.entries[at] = Some(entry);
        self.eviction = self.eviction.wrapping_add(1);
    }

    pub(super) fn worthwhile(tiers: &[Tier]) -> bool {
        tiers.iter().any(|tier| tier.entries.len() >= 32)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn oversized_prepared_directories_preserve_the_original_cache_and_charge_both_buffers() {
        let mut cache = Cache {
            entries: Vec::with_capacity(8),
            ..Cache::default()
        };
        cache.bytes = cache.entries.capacity() * size_of::<Option<Entry>>();
        let before = (
            cache.entries.as_ptr(),
            cache.entries.capacity(),
            cache.bytes,
        );
        let oversized = Vec::with_capacity(BYTES / size_of::<Option<Entry>>() + 1);
        assert!(!cache.publish_directory(oversized, 0));
        assert_eq!(
            (
                cache.entries.as_ptr(),
                cache.entries.capacity(),
                cache.bytes
            ),
            before
        );
        assert!(cache.entries.is_empty());

        let prepared = Vec::with_capacity(SLOTS);
        let directory = prepared.capacity() * size_of::<Option<Entry>>();
        let pending = BYTES - directory - cache.bytes + 1;
        assert!(!cache.publish_directory(prepared, pending));
        assert_eq!(
            (
                cache.entries.as_ptr(),
                cache.entries.capacity(),
                cache.bytes
            ),
            before
        );

        assert!(cache.publish_directory(Vec::with_capacity(SLOTS), 1));
        let checked = cache.entries.as_ptr();
        let next = Arc::new(());
        cache.bind(&next);
        cache.insert(0, &[], false, 0, &[]);
        assert_eq!(cache.entries.as_ptr(), checked);
        assert_eq!(cache.entries.len(), SLOTS);
        assert_eq!(
            cache.bytes,
            cache.entries.capacity() * size_of::<Option<Entry>>()
        );
    }

    #[test]
    fn collisions_keep_complete_keys_freshness_tiers_and_lexer_identity() {
        let first = Arc::new(());
        let mut cache = Cache::default();
        cache.bind(&first);
        let a = [SymbolId::from_index(3)];
        let b = [SymbolId::from_index(u32::MAX as usize)];
        // Deliberate equal hashes cannot identify a permission question.
        cache.insert(0, &a, true, 0, &[2, 7]);
        cache.insert(0, &b, true, 0, &[1, 4]);
        assert_eq!(cache.get(0, &a, true, 0), Some([2, 7].as_slice()));
        assert_eq!(cache.get(0, &b, true, 0), Some([1, 4].as_slice()));
        assert_eq!(cache.get(0, &a, false, 0), None);
        assert_eq!(cache.get(0, &a, true, SLOTS), None);
        assert_eq!(Arc::strong_count(&first), 1);
        drop(first);
        cache.bind(&Arc::new(()));
        assert_eq!(cache.get(0, &a, true, 0), None);
    }

    #[test]
    fn large_keys_and_replacements_stay_inside_the_fixed_payload_ceiling() {
        let owner = Arc::new(());
        let mut cache = Cache::default();
        cache.bind(&owner);
        for count in [0, 1, 32, 1024, BYTES] {
            let ids: Vec<_> = (0..count).map(SymbolId::from_index).collect();
            let allow: Vec<_> = (0..count).map(|i| u32::try_from(i).unwrap()).collect();
            for hash in 0..SLOTS * 4 {
                cache.insert(hash, &ids, false, 0, &allow);
                let retained = cache.entries.capacity() * size_of::<Option<Entry>>()
                    + cache
                        .entries
                        .iter()
                        .filter_map(Option::as_ref)
                        .map(Entry::bytes)
                        .sum::<usize>();
                assert_eq!(cache.bytes, retained);
                assert!(retained <= BYTES);
            }
        }
    }
}
