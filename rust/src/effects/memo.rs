//! Bounded, optional storage of successful immutable effect operations.
//! Owners are checked by EffectStore before lookup. Every index keeps all32bits.
use super::{Effect, Repr};
use crate::ids::{ProductionId, StateId, SymbolId};

const SLOTS: usize = 8192;
const INITIAL_SLOTS: usize = 64;
const PROBES: usize = 8;
const RETAINED_BYTES: usize = 256 * 1024;
const WARMUP_SUCCESSES: u8 = 32;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum Key {
    Shift(u32, u32),
    Reduce(u32, u32),
    Compose(u32, u32),
}

impl Key {
    pub(super) fn shift(state: StateId, symbol: SymbolId) -> Self {
        Self::Shift(
            u32::try_from(state.index()).expect("typed u32 state"),
            u32::try_from(symbol.index()).expect("typed u32 symbol"),
        )
    }
    pub(super) fn reduce(state: StateId, production: ProductionId) -> Self {
        Self::Reduce(
            u32::try_from(state.index()).expect("typed u32 state"),
            u32::try_from(production.index()).expect("typed u32 production"),
        )
    }
    pub(super) fn compose(left: Effect, right: Effect) -> Self {
        let (Repr::Run { index: a, .. }, Repr::Run { index: b, .. }) = (left.0, right.0) else {
            unreachable!("only validated Run+Run operands enter the memo");
        };
        Self::Compose(a, b)
    }
    fn start(self) -> usize {
        let (kind, a, b) = match self {
            Self::Shift(a, b) => (1u64, a, b),
            Self::Reduce(a, b) => (2u64, a, b),
            Self::Compose(a, b) => (3u64, a, b),
        };
        let mut hash = (u64::from(a) << 32) | u64::from(b);
        hash ^= kind.wrapping_mul(0x9e3779b97f4a7c15);
        hash = (hash ^ (hash >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
        hash = (hash ^ (hash >> 27)).wrapping_mul(0x94d049bb133111eb);
        hash ^= hash >> 31;
        usize::try_from(hash & 8191).expect("bounded memo slot")
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Value {
    Zero,
    Run(u32),
}
impl Value {
    fn new(effect: Effect, owner: u64) -> Option<Self> {
        match effect.0 {
            Repr::Zero => Some(Self::Zero),
            Repr::Run {
                owner: actual,
                index,
            } if actual == owner => Some(Self::Run(index)),
            _ => None,
        }
    }
    fn effect(self, owner: u64) -> Effect {
        match self {
            Self::Zero => Effect::ZERO,
            Self::Run(index) => Effect(Repr::Run { owner, index }),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Entry {
    key: Key,
    value: Value,
}

#[derive(Default)]
pub(super) struct Memo {
    entries: Vec<Option<Entry>>,
    used: u16,
    unavailable: bool,
    growth_blocked: bool,
    warmup_successes: u8,
    #[cfg(test)]
    stats: Stats,
    #[cfg(test)]
    force_collisions: bool,
    #[cfg(test)]
    fail_allocation: bool,
}

#[cfg(test)]
#[derive(Default)]
struct Stats {
    lookups: u64,
    hits: u64,
    insertions: u64,
    full_windows: u64,
    max_probes: usize,
    growth_attempts: u64,
    growths: u64,
    peak_guarded_transient: usize,
    peak_attempted_transient: usize,
}

impl Memo {
    pub(super) fn discard_answers(&mut self) {
        self.entries.fill(None);
        self.used = 0;
    }

    fn start(&self, key: Key) -> usize {
        #[cfg(test)]
        if self.force_collisions {
            return 0;
        }
        key.start()
    }

    // Three hot callers already know the operation tag. Inlining lets them
    // specialize key comparison and owner reconstruction on warm cache hits.
    #[inline(always)]
    pub(super) fn get(&mut self, key: Key, owner: u64) -> Option<Effect> {
        #[cfg(test)]
        {
            self.stats.lookups = self.stats.lookups.saturating_add(1);
        }
        if self.unavailable || self.entries.is_empty() {
            return None;
        }
        let start = self.start(key);
        let mask = self.entries.len() - 1;
        for offset in 0..PROBES {
            #[cfg(test)]
            {
                self.stats.max_probes = self.stats.max_probes.max(offset + 1);
            }
            match self.entries[(start + offset) & mask] {
                Some(entry) if entry.key == key => {
                    #[cfg(test)]
                    {
                        self.stats.hits = self.stats.hits.saturating_add(1);
                    }
                    return Some(entry.value.effect(owner));
                }
                None => return None,
                _ => {}
            }
        }
        None
    }

    fn transient_bytes(old: usize, fresh: usize) -> Option<usize> {
        old.checked_add(fresh)?
            .checked_mul(size_of::<Option<Entry>>())?
            .checked_add(size_of::<Self>())?
            .checked_add(size_of::<Vec<Option<Entry>>>())
    }

    fn fits(&mut self, fresh: &Vec<Option<Entry>>, slots: usize) -> bool {
        let bytes = Self::transient_bytes(self.entries.capacity(), fresh.capacity());
        #[cfg(test)]
        if let Some(bytes) = bytes {
            self.stats.peak_attempted_transient = self.stats.peak_attempted_transient.max(bytes);
        }
        let fits = fresh.capacity() >= slots && bytes.is_some_and(|bytes| bytes <= RETAINED_BYTES);
        #[cfg(test)]
        if fits {
            self.stats.peak_guarded_transient = self
                .stats
                .peak_guarded_transient
                .max(bytes.expect("fit checked"));
        }
        fits
    }

    fn ensure_with(
        &mut self,
        allocate: impl FnOnce(&mut Vec<Option<Entry>>) -> Result<(), std::collections::TryReserveError>,
    ) -> bool {
        if self.unavailable {
            return false;
        }
        if !self.entries.is_empty() {
            return true;
        }
        if Self::transient_bytes(0, INITIAL_SLOTS).is_none_or(|bytes| bytes > RETAINED_BYTES) {
            self.unavailable = true;
            return false;
        }
        let mut entries = Vec::new();
        if allocate(&mut entries).is_err() || !self.fits(&entries, INITIAL_SLOTS) {
            self.unavailable = true;
            return false;
        }
        entries.resize(INITIAL_SLOTS, None);
        self.entries = entries;
        true
    }

    fn place(&self, entries: &mut [Option<Entry>], entry: Entry) -> bool {
        let mask = entries.len() - 1;
        let start = self.start(entry.key);
        for offset in 0..PROBES {
            match &mut entries[(start + offset) & mask] {
                Some(previous) if previous.key == entry.key => {
                    debug_assert_eq!(previous.value, entry.value);
                    return true;
                }
                slot @ None => {
                    *slot = Some(entry);
                    return true;
                }
                _ => {}
            }
        }
        false
    }

    fn grow_with(
        &mut self,
        entry: Entry,
        used: u16,
        allocate: impl FnOnce(
            &mut Vec<Option<Entry>>,
            usize,
        ) -> Result<(), std::collections::TryReserveError>,
    ) -> bool {
        if self.growth_blocked || self.entries.len() >= SLOTS {
            return false;
        }
        #[cfg(test)]
        {
            self.stats.growth_attempts = self.stats.growth_attempts.saturating_add(1);
        }
        let Some(next) =
            self.entries.len().checked_mul(2).filter(|&next| {
                next <= SLOTS && next.is_power_of_two() && usize::from(used) <= next
            })
        else {
            self.growth_blocked = true;
            return false;
        };
        if Self::transient_bytes(self.entries.capacity(), next)
            .is_none_or(|bytes| bytes > RETAINED_BYTES)
        {
            self.growth_blocked = true;
            return false;
        }
        let mut entries = Vec::new();
        if allocate(&mut entries, next).is_err() || !self.fits(&entries, next) {
            self.growth_blocked = true;
            return false;
        }
        entries.resize(next, None);
        // Include the candidate in this transaction. An irreducible collision
        // must not publish a larger directory that still cannot hold it.
        if !self
            .entries
            .iter()
            .flatten()
            .copied()
            .all(|old| self.place(&mut entries, old))
            || !self.place(&mut entries, entry)
        {
            self.growth_blocked = true;
            return false;
        }
        self.entries = entries;
        self.used = used;
        #[cfg(test)]
        {
            self.stats.growths = self.stats.growths.saturating_add(1);
            self.stats.insertions = self.stats.insertions.saturating_add(1);
        }
        true
    }

    /// Small stores do not allocate a table for their first32 successful misses.
    pub(super) fn remember_after_warmup(&mut self, key: Key, effect: Effect, owner: u64) {
        if self.warmup_successes < WARMUP_SUCCESSES {
            self.warmup_successes = self.warmup_successes.saturating_add(1);
            return;
        }
        self.insert(key, effect, owner);
    }

    pub(super) fn insert(&mut self, key: Key, effect: Effect, owner: u64) {
        let Some(value) = Value::new(effect, owner) else {
            return;
        };
        #[cfg(test)]
        if self.fail_allocation {
            self.ensure_with(|entries| entries.try_reserve_exact(usize::MAX));
            return;
        }
        if !self.ensure_with(|entries| entries.try_reserve_exact(INITIAL_SLOTS)) {
            return;
        }
        let start = self.start(key);
        let mask = self.entries.len() - 1;
        let mut empty = None;
        for offset in 0..PROBES {
            let index = (start + offset) & mask;
            match self.entries[index] {
                Some(previous) if previous.key == key => {
                    debug_assert_eq!(previous.value, value);
                    return;
                }
                None => {
                    empty = Some(index);
                    break;
                }
                _ => {}
            }
        }
        let Some(used) = self
            .used
            .checked_add(1)
            .filter(|&used| usize::from(used) <= SLOTS)
        else {
            return;
        };
        #[cfg(test)]
        if empty.is_none() {
            self.stats.full_windows = self.stats.full_windows.saturating_add(1);
        }
        let needs_growth = self.entries.len() < SLOTS && usize::from(used) > self.entries.len() / 2;
        if (needs_growth || empty.is_none()) && self.entries.len() < SLOTS && !self.growth_blocked {
            self.grow_with(Entry { key, value }, used, |entries, next| {
                entries.try_reserve_exact(next)
            });
            return;
        }
        if needs_growth {
            return;
        }
        if let Some(index) = empty {
            self.entries[index] = Some(Entry { key, value });
            self.used = used;
            #[cfg(test)]
            {
                self.stats.insertions = self.stats.insertions.saturating_add(1);
            }
        }
    }

    #[cfg(test)]
    pub(super) fn disable(&mut self) {
        self.unavailable = true;
    }
    #[cfg(test)]
    pub(super) fn force_failed_allocation(&mut self) {
        self.fail_allocation = true;
    }
    #[cfg(test)]
    pub(super) fn report(&self) -> serde_json::Value {
        let bytes = self.entries.capacity() * size_of::<Option<Entry>>() + size_of::<Self>();
        assert!(bytes <= RETAINED_BYTES);
        assert_eq!(
            usize::from(self.used),
            self.entries.iter().flatten().count()
        );
        serde_json::json!({"slots":self.entries.len(),"capacity":self.entries.capacity(),"entry_bytes":size_of::<Option<Entry>>(),
            "retained_bytes_including_header":bytes,"cap":RETAINED_BYTES,"entries":self.used,
            "lookups":self.stats.lookups,"hits":self.stats.hits,"insertions":self.stats.insertions,
            "full_windows":self.stats.full_windows,"max_probes":self.stats.max_probes,"probe_cap":PROBES,
            "growth_attempts":self.stats.growth_attempts,"growths":self.stats.growths,"growth_blocked":self.growth_blocked,
            "peak_guarded_transient_bytes":self.stats.peak_guarded_transient,"peak_attempted_transient_bytes":self.stats.peak_attempted_transient,
            "unavailable":self.unavailable,"warmup_successes":self.warmup_successes,"warmup_threshold":WARMUP_SUCCESSES,
            "owner_scope":"full owner validated before lookup; store-local owner reconstructed; fullu32 tagged keys/answers"})
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn full_u32_values_are_distinct_from_zero_and_owner_is_not_narrowed() {
        let owner = u64::MAX;
        let key = Key::Compose(u32::MAX, u32::MAX);
        let other = Key::Compose(u32::MAX, u32::MAX - 1);
        let mut memo = Memo::default();
        memo.insert(
            key,
            Effect(Repr::Run {
                owner,
                index: u32::MAX,
            }),
            owner,
        );
        memo.insert(other, Effect::ZERO, owner);
        assert_eq!(
            memo.get(key, owner),
            Some(Effect(Repr::Run {
                owner,
                index: u32::MAX
            }))
        );
        assert_eq!(memo.get(other, owner), Some(Effect::ZERO));
        assert!(
            memo.report()["retained_bytes_including_header"]
                .as_u64()
                .unwrap()
                <= u64::try_from(RETAINED_BYTES).unwrap()
        );
    }
    #[test]
    fn adversarial_windows_are_bounded_and_never_evict_or_alias() {
        let mut memo = Memo {
            force_collisions: true,
            ..Memo::default()
        };
        for index in 0..PROBES + 1 {
            memo.insert(
                Key::Shift(u32::try_from(index).unwrap(), u32::MAX),
                Effect::ZERO,
                1,
            );
        }
        for index in 0..PROBES {
            assert_eq!(
                memo.get(Key::Shift(u32::try_from(index).unwrap(), u32::MAX), 1),
                Some(Effect::ZERO)
            );
        }
        assert_eq!(
            memo.get(Key::Shift(u32::try_from(PROBES).unwrap(), u32::MAX), 1),
            None
        );
        assert_eq!(memo.stats.full_windows, 1);
        assert_eq!(memo.stats.max_probes, PROBES);
    }
    #[test]
    fn failed_and_oversized_allocation_leave_optional_cache_empty() {
        let mut failed = Memo::default();
        assert!(!failed.ensure_with(|entries| entries.try_reserve_exact(usize::MAX)));
        assert!(failed.entries.is_empty());
        assert!(failed.unavailable);
        failed.discard_answers();
        assert!(failed.unavailable);
        assert!(failed.entries.is_empty());
        let mut rounded = Memo::default();
        assert!(!rounded.ensure_with(|entries| {
            entries.try_reserve_exact(RETAINED_BYTES / size_of::<Option<Entry>>() + 1)
        }));
        assert!(rounded.entries.is_empty());
        assert!(rounded.unavailable);
    }
    fn ordered_growth_keys() -> Vec<Key> {
        let mut by_slot = vec![None; SLOTS];
        let mut found = 0usize;
        for value in 0..1_000_000u32 {
            let key = Key::Shift(value, u32::MAX);
            let slot = key.start();
            if slot <= SLOTS / 2 && by_slot[slot].is_none() {
                by_slot[slot] = Some(key);
                found += 1;
            }
            if found == SLOTS / 2 + 1 {
                break;
            }
        }
        assert_eq!(found, SLOTS / 2 + 1);
        by_slot
            .into_iter()
            .take(SLOTS / 2 + 1)
            .map(Option::unwrap)
            .collect()
    }

    #[test]
    fn every_growth_boundary_preserves_full_keys_and_guarded_transient_cap() {
        let keys = ordered_growth_keys();
        let mut memo = Memo::default();
        let mut capacities = Vec::new();
        for (index, &key) in keys.iter().enumerate() {
            let old = memo.entries.len();
            memo.insert(key, Effect::ZERO, u64::MAX);
            assert_eq!(usize::from(memo.used), index + 1);
            if old != memo.entries.len() {
                capacities.push(memo.entries.len());
                for &previous in &keys[..=index] {
                    assert_eq!(memo.get(previous, u64::MAX), Some(Effect::ZERO));
                }
            }
            assert!(memo.entries.len().is_power_of_two());
            assert!(memo.stats.peak_guarded_transient <= RETAINED_BYTES);
        }
        assert_eq!(capacities, vec![64, 128, 256, 512, 1024, 2048, 4096, 8192]);
        assert_eq!(memo.stats.growths, 7);
        assert!(!memo.growth_blocked);
        for key in keys {
            assert_eq!(memo.get(key, u64::MAX), Some(Effect::ZERO));
        }
    }

    #[test]
    fn growth_allocation_failure_preserves_old_answers_and_disables_retries() {
        let keys = ordered_growth_keys();
        let mut memo = Memo::default();
        for &key in &keys[..32] {
            memo.insert(key, Effect::ZERO, 1);
        }
        let pointer = memo.entries.as_ptr();
        let entry = Entry {
            key: keys[32],
            value: Value::Zero,
        };
        assert!(!memo.grow_with(entry, 33, |entries, _| {
            entries.try_reserve_exact(usize::MAX)
        }));
        assert_eq!(memo.entries.as_ptr(), pointer);
        assert_eq!(memo.entries.len(), 64);
        assert_eq!(memo.used, 32);
        assert!(memo.growth_blocked);
        for &key in &keys[..32] {
            assert_eq!(memo.get(key, 1), Some(Effect::ZERO));
        }
        assert_eq!(memo.get(keys[32], 1), None);
        let attempts = memo.stats.growth_attempts;
        memo.insert(keys[32], Effect::ZERO, 1);
        assert_eq!(memo.stats.growth_attempts, attempts);
        assert_eq!(memo.entries.as_ptr(), pointer);
        assert_eq!(memo.used, 32);
        memo.warmup_successes = WARMUP_SUCCESSES;
        memo.discard_answers();
        assert_eq!(memo.entries.as_ptr(), pointer);
        assert_eq!(memo.used, 0);
        assert!(memo.entries.iter().all(Option::is_none));
        assert!(memo.growth_blocked);
        assert!(!memo.unavailable);
        assert_eq!(memo.warmup_successes, WARMUP_SUCCESSES);
        for &key in &keys[..33] {
            memo.insert(key, Effect::ZERO, 1);
        }
        assert_eq!(memo.stats.growth_attempts, attempts);
        assert_eq!(memo.entries.as_ptr(), pointer);
        assert_eq!(memo.used, 32);
    }

    #[test]
    fn oversized_growth_is_rejected_without_publishing_or_losing_old_entries() {
        let keys = ordered_growth_keys();
        let mut memo = Memo::default();
        for &key in &keys[..32] {
            memo.insert(key, Effect::ZERO, 1);
        }
        let pointer = memo.entries.as_ptr();
        assert!(!memo.grow_with(
            Entry {
                key: keys[32],
                value: Value::Zero
            },
            33,
            |entries, _| {
                entries.try_reserve_exact(RETAINED_BYTES / size_of::<Option<Entry>>() + 1)
            }
        ));
        assert_eq!(memo.entries.as_ptr(), pointer);
        assert_eq!(memo.entries.len(), 64);
        assert_eq!(memo.used, 32);
        assert!(memo.growth_blocked);
        assert!(memo.stats.peak_attempted_transient > RETAINED_BYTES);
        assert!(memo.stats.peak_guarded_transient <= RETAINED_BYTES);
        for &key in &keys[..32] {
            assert_eq!(memo.get(key, 1), Some(Effect::ZERO));
        }
    }

    #[test]
    fn irreducible_candidate_collision_rolls_back_growth_and_keeps_old_handles() {
        let mut memo = Memo {
            force_collisions: true,
            ..Memo::default()
        };
        for value in 0..u32::try_from(PROBES).unwrap() {
            memo.insert(Key::Reduce(value, u32::MAX), Effect::ZERO, u64::MAX);
        }
        let pointer = memo.entries.as_ptr();
        let rejected = Key::Reduce(u32::try_from(PROBES).unwrap(), u32::MAX);
        memo.insert(rejected, Effect::ZERO, u64::MAX);
        assert_eq!(memo.entries.as_ptr(), pointer);
        assert_eq!(memo.entries.len(), 64);
        assert_eq!(usize::from(memo.used), PROBES);
        assert!(memo.growth_blocked);
        assert_eq!(memo.stats.growth_attempts, 1);
        assert_eq!(memo.stats.growths, 0);
        for value in 0..u32::try_from(PROBES).unwrap() {
            assert_eq!(
                memo.get(Key::Reduce(value, u32::MAX), u64::MAX),
                Some(Effect::ZERO)
            );
        }
        assert_eq!(memo.get(rejected, u64::MAX), None);
        memo.insert(rejected, Effect::ZERO, u64::MAX);
        assert_eq!(memo.stats.growth_attempts, 1);
        assert_eq!(memo.entries.as_ptr(), pointer);
    }
}
