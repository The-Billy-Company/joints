//! Conservative prefix reuse over complete source-read dependencies. Regex
//! events retain bounded interior-read proofs; program events retain full replay.
//! Unknown regex reads stop validation before the affected transaction.
use super::*;
use crate::{scanner::ScanHit, sequence::Segment};

const MAX_CACHE_BYTES: usize = 32 * 1024 * 1024;
const MAX_CHECKPOINTS: usize = 16;

#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct ReuseStats {
    pub resumed_at: usize,
    pub validated_events: usize,
    pub parser_work: usize,
    pub lexical_work: usize,
    pub token_reads: usize,
    pub materialized_nodes: usize,
}
pub(crate) struct DocumentParse {
    pub tree: TreeSnapshot,
    pub segments: Vec<Segment>,
    pub stats: ReuseStats,
}

/// A lossless observation under the document's checked u32 source ceiling.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum CachedScan {
    None,
    Token {
        symbol: SymbolId,
        start: u32,
        end: u32,
        extra: bool,
        provisional: bool,
    },
    End {
        provisional: bool,
    },
    Stray {
        at: u32,
        provisional: bool,
    },
}
impl CachedScan {
    fn new(scanned: Option<Scanned>) -> Result<Self, Error> {
        let offset = |at| {
            u32::try_from(at).map_err(|_| Error::InvalidTable("cache source offset exceeds u32"))
        };
        Ok(match scanned {
            None => Self::None,
            Some(Scanned {
                scan: Scan::Token(token),
                provisional,
            }) => Self::Token {
                symbol: token.symbol,
                start: offset(token.start)?,
                end: offset(token.end)?,
                extra: token.extra,
                provisional,
            },
            Some(Scanned {
                scan: Scan::End,
                provisional,
            }) => Self::End { provisional },
            Some(Scanned {
                scan: Scan::Stray { at },
                provisional,
            }) => Self::Stray {
                at: offset(at)?,
                provisional,
            },
        })
    }
}

#[derive(PartialEq, Eq)]
enum Receipt {
    Regex {
        scope: ScanScope,
        at: usize,
        fresh: bool,
        admitted: Option<Box<[SymbolId]>>,
        empty_permit: Box<[SymbolId]>,
        provisional_empty: Box<[SymbolId]>,
        eof: bool,
        result: CachedScan,
    },
    Program(Box<ProgramReceipt>),
}
#[derive(PartialEq, Eq)]
struct ProgramReceipt {
    scope: ScanScope,
    ordered: bool,
    at: usize,
    fresh: bool,
    after_node: bool,
    wanted: Box<[SymbolId]>,
    named: Box<[SymbolId]>,
    before: Box<ScannerState>,
    after: Box<ScannerState>,
    result: Option<ScanHit>,
}
impl Receipt {
    fn work(&self) -> usize {
        match self {
            Self::Regex {
                admitted,
                empty_permit,
                provisional_empty,
                ..
            } => 2usize
                .saturating_add(admitted.as_ref().map_or(0, |s| s.len()))
                .saturating_add(empty_permit.len())
                .saturating_add(provisional_empty.len()),
            Self::Program(p) => 1usize
                .saturating_add(p.wanted.len())
                .saturating_add(p.named.len())
                .saturating_add(p.before.clone_work())
                .saturating_add(p.after.clone_work()),
        }
    }
}
fn semantic_snapshot(state: &ScannerState) -> ScannerState {
    let mut saved = state.clone();
    // Derived whole-file indexes are replay scratch, never retained per version
    // in semantic receipts/checkpoints. Their Arc payload is not cache metadata.
    saved.copy_source_index_from(&ScannerState::default());
    saved
}

// Regex-only transactions need only the exclusive source-read bound. A bound
// at or beyond the edited prefix stops validation; the preceding checkpoint
// already owns every concrete state and draft needed to resume safely.
enum Event {
    Interior(u32),
    Replay(Box<ReplayEvent>),
}
impl Event {
    fn owned_bytes(&self) -> usize {
        match self {
            Self::Interior(_) => 0,
            Self::Replay(event) => event.owned_bytes,
        }
    }
}
struct ReplayEvent {
    states: Box<[StateId]>,
    at: usize,
    fresh: bool,
    after_node: bool,
    before: Option<Box<ScannerState>>,
    after: Option<Box<ScannerState>>,
    result: CachedScan,
    after_at: usize,
    after_fresh: bool,
    after_node_after: bool,
    extras: Box<[Use]>,
    receipts: std::ops::Range<usize>,
    owned_bytes: usize,
}
struct Checkpoint {
    head: Box<Head>,
    drafts: usize,
    moves: usize,
    events: usize,
    receipts: usize,
    owned_bytes: usize,
}
pub(super) struct ParseCache {
    source: Arc<[u8]>,
    drafts: Vec<Draft>,
    recording: Recording,
    recovery: Recovery,
    supply: Supply,
}
fn initial_buffer_allowance() -> usize {
    size_of::<ParseCache>()
}
#[derive(Clone, Copy)]
enum RecordKind {
    Event,
    Receipt,
    Checkpoint,
    Payload,
}
fn elements_bytes<T>(n: usize) -> usize {
    n.saturating_mul(size_of::<T>())
}
fn scanner_bytes(state: &ScannerState) -> usize {
    // Every cloned scanner organ entry is at most 128 bytes; clone_work also
    // counts every delimiter/tag byte, including the independent spent shape.
    size_of::<ScannerState>().saturating_add(state.clone_work().saturating_mul(128))
}
fn head_bytes(head: &Head) -> usize {
    head.frames.iter().fold(
        size_of::<Head>()
            .saturating_add(elements_bytes::<StateId>(head.states.len()))
            .saturating_add(elements_bytes::<Frame>(head.frames.len()))
            .saturating_add(elements_bytes::<Use>(head.pending.len()))
            .saturating_add(head.scanner.clone_work().saturating_mul(128)),
        |n, frame| {
            n.saturating_add(elements_bytes::<Use>(
                frame.lead.len().saturating_add(frame.body.heap_len()),
            ))
        },
    )
}
impl Receipt {
    fn owned_bytes(&self) -> usize {
        match self {
            Self::Regex {
                admitted,
                empty_permit,
                provisional_empty,
                ..
            } => elements_bytes::<SymbolId>(
                admitted
                    .as_ref()
                    .map_or(0, |s| s.len())
                    .saturating_add(empty_permit.len())
                    .saturating_add(provisional_empty.len()),
            ),
            Self::Program(p) => size_of::<ProgramReceipt>()
                .saturating_add(elements_bytes::<SymbolId>(p.wanted.len() + p.named.len()))
                .saturating_add(scanner_bytes(&p.before))
                .saturating_add(scanner_bytes(&p.after)),
        }
    }
}
pub(super) struct Recording {
    events: Vec<Event>,
    receipts: Vec<Receipt>,
    checkpoints: Vec<Checkpoint>,
    probe: bool,
    disabled: bool,
    used: usize,
    read_bound: Option<usize>,
}
impl Recording {
    fn new(probe: bool) -> Self {
        Self {
            events: vec![],
            receipts: vec![],
            checkpoints: vec![],
            probe,
            disabled: false,
            used: initial_buffer_allowance(),
            read_bound: None,
        }
    }
    fn metadata_bytes(&self) -> usize {
        self.events
            .iter()
            .map(Event::owned_bytes)
            .chain(self.receipts.iter().map(Receipt::owned_bytes))
            .chain(self.checkpoints.iter().map(|c| c.owned_bytes))
            .fold(
                initial_buffer_allowance()
                    .saturating_add(elements_bytes::<Event>(self.events.capacity()))
                    .saturating_add(elements_bytes::<Receipt>(self.receipts.capacity()))
                    .saturating_add(elements_bytes::<Checkpoint>(self.checkpoints.capacity())),
                usize::saturating_add,
            )
    }
}

impl ParseSession {
    pub(crate) fn set_document_reuse(&mut self, enabled: bool) {
        self.document_reuse = enabled;
        if !enabled {
            self.cache = None;
        }
    }

    /// An operational failure may discard scratch/cache; the caller owns the
    /// previously published immutable snapshot and source.
    pub(crate) fn parse_document(
        &mut self,
        source: Arc<[u8]>,
        edit_start: Option<usize>,
        store: &mut EffectStore,
    ) -> Result<DocumentParse, Error> {
        let result = self.prepare_document(source, edit_start, store);
        if result.is_err() {
            self.cache = None;
            self.recording = None;
            self.resume = None;
            self.document_source = None;
            self.run = RunState::Parsing;
        }
        result
    }
    fn prepare_document(
        &mut self,
        source: Arc<[u8]>,
        edit_start: Option<usize>,
        store: &mut EffectStore,
    ) -> Result<DocumentParse, Error> {
        if !Arc::ptr_eq(&self.grammar.automaton, store.automaton()) {
            return Err(EffectError::ForeignAutomaton.into());
        }
        let old = self.cache.take();
        let old_trace = std::mem::take(&mut self.trace);
        let old_ends = std::mem::take(&mut self.ends);
        self.recording = None;
        self.resume = None;
        self.document_source = Some(Arc::clone(&source));
        self.reset_run();
        let max = self.limits.source_bytes.min(u32::MAX as usize);
        if source.len() > max {
            return Err(Error::SourceTooLarge {
                actual: source.len(),
                limit: max,
            });
        }
        if self.limits.heads == 0 {
            return Err(Error::LimitExceeded(Resource::Heads));
        }
        let mut stats = ReuseStats::default();
        if let (Some(old), Some(edit)) = (old, edit_start) {
            if self.document_reuse
                && !self.trace_enabled
                && old.recovery == self.recovery
                && old.supply == self.supply
            {
                self.restore_prefix(old, old_trace, old_ends, &source, edit, &mut stats)?;
            }
        }
        if self.document_reuse && self.recording.is_none() {
            self.recording = Some(Recording::new(false));
        }
        let result = self.parse_inner(&source);
        let mut tree = match result {
            Ok(tree) => tree,
            Err(error) => {
                self.recording = None;
                self.document_source = None;
                self.resume = None;
                return Err(error);
            }
        };
        stats.materialized_nodes += tree.nodes.len();
        if stats.resumed_at > 0
            && (!tree.confidence().is_strict()
                || self.recording.as_ref().is_some_and(|r| r.disabled))
        {
            // Repaired/ambiguous/untracked executions retain the cold contract.
            // The attempted validation/resume remains charged to this operation.
            self.trace.clear();
            self.ends.clear();
            self.drafts.clear();
            self.resume = None;
            self.recording = Some(Recording::new(false));
            self.run = RunState::Parsing;
            stats.resumed_at = 0;
            drop(tree); // release unpublished materialization before cold allocation
            tree = self.parse_inner(&source)?;
            stats.materialized_nodes += tree.nodes.len();
        }
        let segments = match self.segments(source.len(), store) {
            Ok(segments) => segments,
            Err(error) => {
                self.recording = None;
                self.document_source = None;
                self.run = RunState::Parsing;
                return Err(error);
            }
        };
        if let Some(recording) = self.recording.take() {
            if !recording.disabled {
                self.charge(self.drafts.len())?;
            }
            let draft_bytes = if recording.disabled {
                usize::MAX
            } else {
                self.drafts.iter().fold(
                    self.drafts.capacity().saturating_mul(size_of::<Draft>()),
                    |n, d| n.saturating_add(d.children.capacity().saturating_mul(size_of::<Use>())),
                )
            };
            if tree.confidence().is_strict()
                && !recording.disabled
                && recording.used.saturating_add(draft_bytes) <= MAX_CACHE_BYTES
            {
                self.cache = Some(ParseCache {
                    source,
                    drafts: std::mem::take(&mut self.drafts),
                    recording,
                    recovery: self.recovery,
                    supply: self.supply,
                });
            }
        }
        self.document_source = None;
        stats.parser_work = self.steps;
        stats.lexical_work = self.limits.lexical_steps - self.lexical_remaining;
        stats.token_reads = self.token_reads;
        Ok(DocumentParse {
            tree,
            segments,
            stats,
        })
    }

    fn restore_prefix(
        &mut self,
        mut old: ParseCache,
        mut trace: Vec<Move>,
        mut ends: Vec<usize>,
        source: &[u8],
        edit: usize,
        stats: &mut ReuseStats,
    ) -> Result<(), Error> {
        if edit > old.source.len() || edit > source.len() {
            return Ok(());
        }
        let Some(last) = old
            .recording
            .checkpoints
            .iter()
            .rposition(|c| c.head.at <= edit)
        else {
            return Ok(());
        };
        let target_events = old.recording.checkpoints[last].events;
        self.charge(edit)?;
        if old.source[..edit] != source[..edit] {
            return Ok(());
        }
        // Prefix replay has its own operation-local owner before parse_inner.
        let graph = Arc::clone(&self.grammar.automaton);
        let mut valid = 0;
        let mut index_owner = ScannerState::default();
        self.recording = Some(Recording::new(true));
        for event in &old.recording.events[..target_events] {
            self.charge(4)?;
            let event = match event {
                Event::Interior(bound) => {
                    if self.grammar.program.is_none()
                        && usize::try_from(*bound)
                            .is_ok_and(|bound| bound < old.source.len() && bound < edit)
                    {
                        valid += 1;
                        continue;
                    }
                    break;
                }
                Event::Replay(event) => event,
            };
            self.charge(
                event
                    .states
                    .len()
                    .saturating_add(event.before.as_deref().map_or(0, ScannerState::clone_work)),
            )?;
            let mut head = Head::new(self.grammar.automaton.start_state(), event.at);
            head.states = event.states.to_vec();
            head.slate = None;
            head.fresh = event.fresh;
            head.after_node = event.after_node;
            head.scanner = event.before.as_deref().cloned().unwrap_or_default();
            head.scanner.copy_source_index_from(&index_owner);
            self.drafts.clear();
            let result =
                self.document_scan(&graph, source, &mut head, &Exclusions::default(), None)?;
            if result.is_some_and(|scanned| scanned.provisional) {
                // Replay intentionally has states but no concrete frames. A
                // provisional End, like an Unknown token, must resume cold
                // before any actual parent advancement can be required.
                self.disable_recording();
            }
            let receipts = &old.recording.receipts[event.receipts.clone()];
            let bill = receipts
                .iter()
                .fold(0usize, |n, r| n.saturating_add(r.work()));
            self.charge(bill)?;
            let observed = self.recording.as_ref().unwrap();
            let same = !observed.disabled
                && observed.receipts == receipts
                && CachedScan::new(result)? == event.result
                && head.at == event.after_at
                && head.fresh == event.after_fresh
                && head.after_node == event.after_node_after
                && event.after.as_deref().map_or_else(
                    || head.scanner == ScannerState::default(),
                    |after| &head.scanner == after,
                );
            if !same || !self.same_extras(&old.drafts, &event.extras, &head.pending)? {
                break;
            }
            index_owner.copy_source_index_from(&head.scanner);
            let observed = self.recording.as_mut().unwrap();
            observed.receipts.clear();
            observed.used = observed.metadata_bytes();
            valid += 1;
        }
        stats.validated_events = valid;
        self.recording = None;
        self.drafts.clear();
        let Some(chosen) = old.recording.checkpoints[..=last]
            .iter()
            .rposition(|c| c.events <= valid)
        else {
            return Ok(());
        };
        old.recording.checkpoints.truncate(chosen + 1);
        let mut checkpoint = old.recording.checkpoints.pop().unwrap();
        stats.resumed_at = checkpoint.head.at;
        old.recording.events.truncate(checkpoint.events);
        old.recording.receipts.truncate(checkpoint.receipts);
        self.charge(
            old.recording
                .events
                .len()
                .saturating_add(old.recording.receipts.len())
                .saturating_add(old.recording.checkpoints.len()),
        )?;
        old.recording.used = old.recording.metadata_bytes();
        old.drafts.truncate(checkpoint.drafts);
        trace.truncate(checkpoint.moves);
        ends.truncate(checkpoint.moves);
        self.charge(
            History::<Move>::from_vec_work(trace.len())
                .saturating_add(History::<usize>::from_vec_work(ends.len())),
        )?;
        checkpoint.head.trace = History::from_vec(trace);
        checkpoint.head.ends = Some(History::from_vec(ends));
        checkpoint.head.slate = None;
        checkpoint.head.scanner.copy_source_index_from(&index_owner);
        self.drafts = old.drafts;
        self.resume = Some(checkpoint.head);
        self.recording = Some(old.recording);
        Ok(())
    }

    fn same_extras(&mut self, old: &[Draft], a: &[Use], b: &[Use]) -> Result<bool, Error> {
        if a.len() != b.len() {
            return Ok(false);
        }
        self.charge(a.len())?;
        let mut pending: Vec<_> = a.iter().copied().zip(b.iter().copied()).collect();
        while let Some((a, b)) = pending.pop() {
            self.charge(1)?;
            let left = &old[a.draft as usize];
            let right = &self.drafts[b.draft as usize];
            if a.alias != b.alias
                || a.field != b.field
                || left.symbol != right.symbol
                || left.span != right.span
                || left.extra != right.extra
                || left.children.len() != right.children.len()
            {
                return Ok(false);
            }
            let children_len = left.children.len();
            self.charge(children_len)?;
            let left = &old[a.draft as usize];
            let right = &self.drafts[b.draft as usize];
            let children = left
                .children
                .iter()
                .copied()
                .zip(right.children.iter().copied())
                .collect::<Vec<_>>();
            pending.extend(children);
        }
        Ok(true)
    }

    pub(super) fn disable_recording(&mut self) {
        if let Some(recording) = &mut self.recording {
            recording.disabled = true;
            recording.events = Vec::new();
            recording.receipts = Vec::new();
            recording.checkpoints = Vec::new();
            recording.used = initial_buffer_allowance();
        }
    }
    fn reserve_record(
        &mut self,
        work: usize,
        payload: usize,
        kind: RecordKind,
    ) -> Result<bool, Error> {
        let Some(recording) = &self.recording else {
            return Ok(false);
        };
        if recording.disabled {
            return Ok(false);
        }
        let (len, capacity, size) = match kind {
            RecordKind::Event => (
                recording.events.len(),
                recording.events.capacity(),
                size_of::<Event>(),
            ),
            RecordKind::Receipt => (
                recording.receipts.len(),
                recording.receipts.capacity(),
                size_of::<Receipt>(),
            ),
            RecordKind::Checkpoint => (
                recording.checkpoints.len(),
                recording.checkpoints.capacity(),
                size_of::<Checkpoint>(),
            ),
            RecordKind::Payload => (0, 1, 0),
        };
        let next = if len == capacity {
            if matches!(kind, RecordKind::Event)
                && self.grammar.program.is_none()
                && capacity >= 4096
            {
                // Cheap regex-only event headers need fewer large relocations.
                // Keep small documents on their original conservative schedule.
                capacity.saturating_mul(2)
            } else {
                capacity.saturating_add((capacity / 4).max(4))
            }
        } else {
            capacity
        };
        let bytes = payload.saturating_add(next.saturating_sub(capacity).saturating_mul(size));
        if recording.used.saturating_add(bytes) > MAX_CACHE_BYTES {
            self.disable_recording();
            return Ok(false);
        }
        self.charge(work.saturating_add(if next > capacity { len } else { 0 }))?;
        let recording = self.recording.as_mut().unwrap();
        let extra = next.saturating_sub(len);
        let allocation = match kind {
            RecordKind::Event => recording.events.try_reserve_exact(extra),
            RecordKind::Receipt => recording.receipts.try_reserve_exact(extra),
            RecordKind::Checkpoint => recording.checkpoints.try_reserve_exact(extra),
            RecordKind::Payload => Ok(()),
        };
        if allocation.is_err() {
            self.disable_recording();
            return Ok(false);
        }
        // Use reported capacity after reservation as well; allocator rounding
        // cannot turn the advisory ceiling into an unchecked lower estimate.
        let actual = match kind {
            RecordKind::Event => recording.events.capacity(),
            RecordKind::Receipt => recording.receipts.capacity(),
            RecordKind::Checkpoint => recording.checkpoints.capacity(),
            RecordKind::Payload => capacity,
        };
        let bytes = payload.saturating_add(actual.saturating_sub(capacity).saturating_mul(size));
        if recording.used.saturating_add(bytes) > MAX_CACHE_BYTES {
            self.disable_recording();
            return Ok(false);
        }
        recording.used += bytes;
        Ok(true)
    }
    pub(super) fn checkpoint(&mut self, head: &Head) -> Result<(), Error> {
        let Some(recording) = &self.recording else {
            return Ok(());
        };
        // Keep proved positions across the document, rather than only the
        // final few tokens. A late edit can then reuse a nearby earlier head.
        let spacing = self.document_source.as_ref().map_or(1, |source| {
            source.len().div_ceil(MAX_CHECKPOINTS - 1).max(1)
        });
        if recording.disabled
            || recording.probe
            || head.at == 0
            || recording
                .checkpoints
                .last()
                .is_some_and(|saved| head.at / spacing <= saved.head.at / spacing)
        {
            return Ok(());
        }
        self.charge(head.frames.len().saturating_add(head.pending.len()))?;
        if head.last_end > head.at
            || head.frames.iter().any(|frame| frame.span.end() > head.at)
            || head
                .pending
                .iter()
                .any(|use_| self.drafts[use_.draft as usize].span.end() > head.at)
        {
            self.disable_recording();
            return Ok(());
        }
        if self.recording.as_ref().unwrap().checkpoints.len() == MAX_CHECKPOINTS {
            let recording = self.recording.as_mut().unwrap();
            let removed = recording.checkpoints.remove(1);
            recording.used -= removed.owned_bytes;
        }
        let owned_bytes = head_bytes(head);
        if !self.reserve_record(
            head.clone_without_history_work(),
            owned_bytes,
            RecordKind::Checkpoint,
        )? {
            return Ok(());
        }
        let copy = Box::new(Head {
            slate: None,
            states: head.states.clone(),
            frames: head.frames.clone(),
            pending: head.pending.clone(),
            trace: History::default(),
            ends: None,
            tokens: None,
            at: head.at,
            last_end: head.last_end,
            fresh: head.fresh,
            after_node: head.after_node,
            scanner: semantic_snapshot(&head.scanner),
            dynamic: head.dynamic,
            rank: head.rank,
            birth: head.birth,
            repaired: head.repaired,
            declared: head.declared,
            shifted: head.shifted,
            kept: head.kept,
        });
        let recording = self.recording.as_mut().unwrap();
        recording.checkpoints.push(Checkpoint {
            head: copy,
            drafts: self.drafts.len(),
            moves: head.trace.len(),
            events: recording.events.len(),
            receipts: recording.receipts.len(),
            owned_bytes,
        });
        Ok(())
    }

    pub(super) fn document_scan(
        &mut self,
        graph: &Automaton,
        source: &[u8],
        head: &mut Head,
        excluded: &Exclusions,
        prebuilt: Option<&AdmissionSlate>,
    ) -> Result<Option<Scanned>, Error> {
        let capture = self
            .recording
            .as_ref()
            .is_some_and(|r| !r.disabled && !r.probe);
        if capture {
            self.recording.as_mut().unwrap().read_bound = Some(0);
        }
        let scanner = capture && self.grammar.program.is_some();
        #[cfg(test)]
        let replay = scanner || self.force_cache_replay;
        #[cfg(not(test))]
        let replay = scanner;
        if capture && !replay {
            let retained = self.reserve_record(1, 0, RecordKind::Event)?;
            let result = self.document_scan_inner(graph, source, head, excluded, prebuilt)?;
            if retained && self.recording.as_ref().is_some_and(|r| !r.disabled) {
                let recording = self.recording.as_mut().unwrap();
                let bound = recording
                    .read_bound
                    .and_then(|bound| u32::try_from(bound).ok())
                    .unwrap_or(u32::MAX);
                recording.events.push(Event::Interior(bound));
            }
            return Ok(result);
        }
        let before_bytes = size_of::<ReplayEvent>()
            .saturating_add(elements_bytes::<StateId>(head.states.len()))
            .saturating_add(if scanner {
                scanner_bytes(&head.scanner)
            } else {
                0
            });
        let entry = if capture
            && self.reserve_record(
                head.states.len().saturating_add(if scanner {
                    head.scanner.clone_work()
                } else {
                    0
                }),
                before_bytes,
                RecordKind::Event,
            )? {
            Some((
                head.states.clone().into_boxed_slice(),
                head.at,
                head.fresh,
                head.after_node,
                scanner.then(|| Box::new(semantic_snapshot(&head.scanner))),
                head.pending.len(),
                self.recording.as_ref().unwrap().receipts.len(),
            ))
        } else {
            None
        };
        let result = self.document_scan_inner(graph, source, head, excluded, prebuilt)?;
        if let Some((states, at, fresh, after_node, before, pending, start)) = entry {
            if self.recording.as_ref().is_some_and(|r| !r.disabled) {
                let after_bytes = elements_bytes::<Use>(head.pending.len() - pending)
                    .saturating_add(if scanner {
                        scanner_bytes(&head.scanner)
                    } else {
                        0
                    });
                if !self.reserve_record(
                    (if scanner {
                        head.scanner.clone_work()
                    } else {
                        0
                    })
                    .saturating_add(head.pending.len() - pending),
                    after_bytes,
                    RecordKind::Payload,
                )? {
                    return Ok(result);
                }
                let after = scanner.then(|| Box::new(semantic_snapshot(&head.scanner)));
                let extras = head.pending[pending..].to_vec().into_boxed_slice();
                let recording = self.recording.as_mut().unwrap();
                recording.events.push(Event::Replay(Box::new(ReplayEvent {
                    states,
                    at,
                    fresh,
                    after_node,
                    before,
                    after,
                    extras,
                    result: CachedScan::new(result)?,
                    after_at: head.at,
                    after_fresh: head.fresh,
                    after_node_after: head.after_node,
                    receipts: start..recording.receipts.len(),
                    owned_bytes: before_bytes.saturating_add(after_bytes),
                })));
            }
        }
        Ok(result)
    }

    pub(super) fn lexical_scan(
        &mut self,
        source: &[u8],
        at: usize,
        question: crate::lexer::LexicalQuestion<'_>,
        fresh: bool,
        scope: ScanScope,
    ) -> Result<Scan, Error> {
        let recording = self.recording.as_ref().is_some_and(|r| !r.disabled);
        self.charge(
            question
                .empty_permit
                .len()
                .saturating_add(question.provisional_empty.len())
                .saturating_add(1),
        )?;
        #[cfg(test)]
        let replay = self.grammar.program.is_some() || self.force_cache_replay;
        #[cfg(not(test))]
        let replay = self.grammar.program.is_some();
        let saved = if recording
            && replay
            && self.reserve_record(
                2usize
                    .saturating_add(question.admitted.map_or(0, <[SymbolId]>::len))
                    .saturating_add(question.empty_permit.len())
                    .saturating_add(question.provisional_empty.len()),
                elements_bytes::<SymbolId>(
                    question
                        .admitted
                        .map_or(0, <[SymbolId]>::len)
                        .saturating_add(question.empty_permit.len())
                        .saturating_add(question.provisional_empty.len()),
                ),
                RecordKind::Receipt,
            )? {
            Some((
                question.admitted.map(|s| s.to_vec().into_boxed_slice()),
                question.empty_permit.to_vec().into_boxed_slice(),
                question.provisional_empty.to_vec().into_boxed_slice(),
            ))
        } else {
            None
        };
        let allowance = self.limits.steps.saturating_sub(self.steps);
        let mut selection = allowance;
        #[cfg(all(test, feature = "munch-image"))]
        let observed = crate::lexer::working_image_trial::lexical_before(
            self.lexical_remaining,
            allowance,
            self.steps,
        );
        let lexical_before = self.lexical_remaining;
        let result = match question.admitted {
            Some(_) => self.grammar.lexer.scan_question_with_scratch(
                source,
                at,
                question,
                fresh,
                crate::lexer::ScanBudget {
                    transitions: &mut self.lexical_remaining,
                    selection: &mut selection,
                },
                &mut self.lexer_scratch,
            ),
            None => self.grammar.lexer.spot_with_scratch(
                source,
                at,
                fresh,
                &mut self.lexical_remaining,
                &mut self.lexer_scratch,
            ),
        };
        let read_bound = match &result {
            Ok(Scan::Token(_)) => lexical_before
                .checked_sub(self.lexical_remaining)
                .and_then(|spent| at.checked_add(spent))
                .filter(|&bound| bound < source.len()),
            _ => None,
        };
        if let Some(recording) = &mut self.recording {
            recording.read_bound = recording.read_bound.zip(read_bound).map(|(a, b)| a.max(b));
        }
        // Reconcile new election visits even when selection/lexing refuses.
        #[cfg(all(test, feature = "munch-image"))]
        let reconciled = self.charge(allowance - selection);
        #[cfg(all(test, feature = "munch-image"))]
        crate::lexer::working_image_trial::lexical_after(
            observed,
            self.lexical_remaining,
            selection,
            self.steps,
            &result,
            &reconciled,
        );
        #[cfg(all(test, feature = "munch-image"))]
        reconciled?;
        #[cfg(not(all(test, feature = "munch-image")))]
        self.charge(allowance - selection)?;
        let result = match result {
            Err(crate::lexer::LexError::QuestionWork { .. }) => {
                return Err(Error::LimitExceeded(Resource::Work));
            }
            other => other?,
        };
        if let Some((admitted, empty_permit, provisional_empty)) = saved {
            self.recording
                .as_mut()
                .unwrap()
                .receipts
                .push(Receipt::Regex {
                    scope,
                    at,
                    fresh,
                    admitted,
                    empty_permit,
                    provisional_empty,
                    eof: question.eof,
                    result: CachedScan::new(Some(Scanned {
                        scan: result,
                        provisional: false,
                    }))?,
                });
        }
        Ok(result)
    }
    #[allow(clippy::too_many_arguments)]
    pub(super) fn program_scan(
        &mut self,
        source: &[u8],
        head: &mut Head,
        at: usize,
        wanted: &[SymbolId],
        named: &[SymbolId],
        ordered: bool,
        scope: ScanScope,
    ) -> Result<Option<ScanHit>, Error> {
        let recording = self.recording.as_ref().is_some_and(|r| !r.disabled);
        if !recording {
            let Some(program) = &self.grammar.program else {
                return Ok(None);
            };
            return Ok(if ordered {
                program.ordered(
                    &mut head.scanner,
                    source,
                    at,
                    head.fresh,
                    head.after_node,
                    wanted,
                    named,
                    &mut self.lexical_remaining,
                )?
            } else {
                program.step(
                    &mut head.scanner,
                    source,
                    at,
                    head.fresh,
                    head.after_node,
                    wanted,
                    named,
                    &mut self.lexical_remaining,
                )?
            });
        }
        let Some(program) = self.grammar.program.as_ref().cloned() else {
            return Ok(None);
        };
        let saved = if recording
            && self.reserve_record(
                head.scanner
                    .clone_work()
                    .saturating_add(wanted.len())
                    .saturating_add(named.len()),
                size_of::<ProgramReceipt>()
                    .saturating_add(elements_bytes::<SymbolId>(
                        wanted.len().saturating_add(named.len()),
                    ))
                    .saturating_add(scanner_bytes(&head.scanner)),
                RecordKind::Receipt,
            )? {
            Some((
                Box::new(semantic_snapshot(&head.scanner)),
                wanted.to_vec().into_boxed_slice(),
                named.to_vec().into_boxed_slice(),
            ))
        } else {
            None
        };
        let result = if ordered {
            program.ordered(
                &mut head.scanner,
                source,
                at,
                head.fresh,
                head.after_node,
                wanted,
                named,
                &mut self.lexical_remaining,
            )?
        } else {
            program.step(
                &mut head.scanner,
                source,
                at,
                head.fresh,
                head.after_node,
                wanted,
                named,
                &mut self.lexical_remaining,
            )?
        };
        if let Some((before, wanted, named)) = saved {
            if !self.reserve_record(
                head.scanner.clone_work(),
                scanner_bytes(&head.scanner),
                RecordKind::Payload,
            )? {
                return Ok(result);
            }
            let after = Box::new(semantic_snapshot(&head.scanner));
            self.recording
                .as_mut()
                .unwrap()
                .receipts
                .push(Receipt::Program(Box::new(ProgramReceipt {
                    scope,
                    ordered,
                    at,
                    fresh: head.fresh,
                    after_node: head.after_node,
                    wanted,
                    named,
                    before,
                    after,
                    result,
                })));
        }
        Ok(result)
    }

    fn segments(&mut self, len: usize, store: &mut EffectStore) -> Result<Vec<Segment>, Error> {
        if self.trace.len() != self.ends.len() {
            return Err(Error::InvalidTable("move byte endpoints are missing"));
        }
        let mut segments: Vec<Segment> = vec![];
        let mut frontier = 0;
        for index in 0..self.trace.len() {
            self.charge(1)?;
            let end = self.ends[index];
            if end < frontier || end > len {
                return Err(Error::InvalidTable("invalid move byte endpoint"));
            }
            let effect = match self.trace[index] {
                Move::Shift { from, symbol } => store.shift(from, symbol)?,
                Move::Reduce { under, production } => {
                    self.charge(self.grammar.automaton.production(production).steps.len())?;
                    store.reduce(under, production)?
                }
                Move::Hole => Effect::ZERO,
            };
            if end == frontier && !segments.is_empty() {
                let last = segments.last_mut().unwrap();
                last.effect = store.compose(last.effect, effect)?;
            } else {
                segments.push(Segment {
                    bytes: end - frontier,
                    effect,
                });
            }
            frontier = end;
        }
        if frontier < len || segments.is_empty() {
            segments.push(Segment {
                bytes: len - frontier,
                effect: Effect::IDENTITY,
            });
        }
        Ok(segments)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn extent_image(tree: &TreeSnapshot) -> serde_json::Value {
        serde_json::json!({
            "source":tree.source(),"stop":format!("{:?}",tree.stop()),
            "confidence":format!("{:?}",tree.confidence()),"survey":format!("{:?}",tree.survey()),
            "repairs":format!("{:?}",tree.repairs()),"spurned":tree.spurned(),
            "roots":tree.roots().map(|n|n.index()).collect::<Vec<_>>(),
            "nodes":(0..tree.nodes.len()).map(|i| {
                let n=tree.node_at(i).unwrap();
                serde_json::json!({"name":n.name(),"named":n.is_named(),"extra":n.is_extra(),
                    "field":n.field(),"span":[n.span().start(),n.span().end()],"text":n.text(),
                    "start":format!("{:?}",n.start_point()),"end":format!("{:?}",n.end_point()),
                    "parent":n.parent().map(|p|p.index()),"children":n.children().map(|c|c.index()).collect::<Vec<_>>()})
            }).collect::<Vec<_>>()
        })
    }

    fn extent_change(
        grammar: &Arc<CompiledGrammar>,
        old: &[u8],
        new: &[u8],
        edit: usize,
    ) -> (ReuseStats, ReuseStats, usize) {
        let mut warm = grammar.session();
        let mut replay = grammar.session();
        replay.force_cache_replay = true;
        let mut warm_store = grammar.effect_store();
        let mut replay_store = grammar.effect_store();
        warm.parse_document(Arc::from(old), None, &mut warm_store)
            .unwrap();
        replay
            .parse_document(Arc::from(old), None, &mut replay_store)
            .unwrap();
        let cache = warm.cache.as_ref().expect("strict source retains evidence");
        let eligible = cache
            .recording
            .events
            .iter()
            .filter(|e| matches!(e, Event::Interior(bound) if usize::try_from(*bound).is_ok_and(|b| b < edit)))
            .count();
        let a = warm
            .parse_document(Arc::from(new), Some(edit), &mut warm_store)
            .unwrap();
        let b = replay
            .parse_document(Arc::from(new), Some(edit), &mut replay_store)
            .unwrap();
        let mut cold = grammar.session();
        let c = cold.parse_partial(new).unwrap();
        assert_eq!(extent_image(&a.tree), extent_image(&b.tree));
        assert_eq!(extent_image(&a.tree), extent_image(&c));
        let mut independent = grammar.effect_store();
        let expected = cold.product(&mut independent).unwrap();
        let actual = warm.product(&mut warm_store).unwrap();
        assert_eq!(
            warm_store.describe(actual).unwrap(),
            independent.describe(expected).unwrap()
        );
        (a.stats, b.stats, eligible)
    }

    #[test]
    fn read_extent_proves_unchanged_json_bytes_without_rereading_the_prefix() {
        let grammar =
            CompiledGrammar::compile(include_bytes!("../../../test/grammar/json.json")).unwrap();
        let old = format!(
            "[{}]",
            (0..96)
                .map(|i| format!("{{\"key\":{i},\"text\":\"item-{i}\"}}"))
                .collect::<Vec<_>>()
                .join(",\n")
        );
        let mut new = old.as_bytes().to_vec();
        let at = new.len() - 8;
        new[at] = b'I';
        let (warm, replay, eligible) = extent_change(&grammar, old.as_bytes(), &new, at);
        assert!(eligible > 100 && warm.resumed_at > old.len() / 2);
        assert!(warm.token_reads * 10 < replay.token_reads);
        assert!(warm.lexical_work * 10 < replay.lexical_work);
    }

    #[test]
    fn read_extent_replays_distant_failed_longest_walks_across_voices_and_tiers() {
        use serde_json::json;
        for tiers in [false, true] {
            let long = json!({"type":"PATTERN","value":"a+z"});
            let long = if tiers {
                json!({"type":"PREC","value":3,"content":long})
            } else {
                long
            };
            let mut rules = serde_json::Map::new();
            rules.insert(
                "doc".into(),
                json!({"type":"SEQ","members":[
                {"type":"REPEAT1","content":{"type":"SYMBOL","name":"item"}},
                {"type":"STRING","value":"!"}]}),
            );
            let mut choices = vec![
                json!({"type":"SYMBOL","name":"short"}),
                json!({"type":"SYMBOL","name":"long"}),
            ];
            rules.insert(
                "short".into(),
                json!({"type":"TOKEN","content":{"type":"STRING","value":"a"}}),
            );
            rules.insert("long".into(), json!({"type":"TOKEN","content":long}));
            for i in 0..70 {
                let name = format!("other{i}");
                choices.push(json!({"type":"SYMBOL","name":name}));
                rules.insert(
                    name,
                    json!({"type":"TOKEN","content":{"type":"STRING","value":format!("t{i}")}}),
                );
            }
            rules.insert("item".into(), json!({"type":"CHOICE","members":choices}));
            let grammar = CompiledGrammar::compile(
                &serde_json::to_vec(&json!({"rules":rules,"extras":[]})).unwrap(),
            )
            .unwrap();
            let old = format!("{}!", "a".repeat(96));
            let new = format!("{}z!", "a".repeat(96));
            let (warm, replay, eligible) =
                extent_change(&grammar, old.as_bytes(), new.as_bytes(), 96);
            assert_eq!(
                eligible, 0,
                "the failed alternative read through the edited boundary"
            );
            assert_eq!(warm.resumed_at, 0);
            assert!(warm.token_reads <= replay.token_reads);
        }
    }

    #[test]
    fn read_extent_accounts_for_failed_rule_extra_speculation_and_rollback() {
        use serde_json::json;
        let grammar=CompiledGrammar::compile(&serde_json::to_vec(&json!({"rules":{
            "doc":{"type":"SEQ","members":[{"type":"REPEAT","content":{"type":"STRING","value":"a"}},{"type":"STRING","value":"!"}]},
            "comment":{"type":"SEQ","members":[{"type":"STRING","value":"a"},{"type":"TOKEN","content":{"type":"PATTERN","value":"a*"}},{"type":"STRING","value":"z"}]}
        },"extras":[{"type":"SYMBOL","name":"comment"}]})).unwrap()).unwrap();
        assert!(grammar.program.is_none());
        let old = format!("{}!", "a".repeat(96));
        let new = format!("{}z!", "a".repeat(96));
        let (warm, replay, eligible) = extent_change(&grammar, old.as_bytes(), new.as_bytes(), 96);
        assert_eq!(
            eligible, 0,
            "failed auxiliary readers reached the changed boundary"
        );
        assert_eq!(warm.resumed_at, 0);
        assert!(warm.token_reads <= replay.token_reads);
    }

    fn frozen_scaled_json() -> Vec<u8> {
        let seed = include_bytes!(
            "../../../test/migration/reference/inputs/research/joinery/corpus/ledger.json"
        )
        .trim_ascii();
        let mut source = vec![b'['];
        for n in 0..170 {
            if n != 0 {
                source.extend_from_slice(b",\n");
            }
            source.extend_from_slice(seed);
        }
        source.extend_from_slice(b"]\n");
        assert_eq!(source.len(), 131_751);
        use sha2::{Digest, Sha256};
        use std::fmt::Write;
        let mut hash = String::with_capacity(64);
        for byte in Sha256::digest(&source) {
            write!(&mut hash, "{byte:02x}").unwrap();
        }
        assert_eq!(
            hash,
            "ebb4658528dcc1fd204bd41b3e15811f1aaf4a40c5f5b60335bdb3b81487ffc3"
        );
        source
    }

    #[test]
    fn read_extent_retains_exact_frozen_131751_byte_json_under_the_same_ceiling() {
        let grammar =
            CompiledGrammar::compile(include_bytes!("../../../test/grammar/json.json")).unwrap();
        let old = frozen_scaled_json();
        let mut new = old.clone();
        let at = 129116;
        new.splice(at..at, [b' ']);
        let (warm, replay, eligible) = extent_change(&grammar, &old, &new, at);
        assert!(eligible > 50_000);
        assert!(
            warm.resumed_at > old.len() * 9 / 10,
            "warm={warm:?} replay={replay:?} eligible={eligible}"
        );
        assert!(warm.token_reads * 10 < replay.token_reads);
        extent_change(&grammar, &new, &old, at);
    }

    #[test]
    fn read_extent_replays_eof_and_handles_deleted_boundaries_and_required_empty_tokens() {
        use serde_json::json;
        let grammar=CompiledGrammar::compile(&serde_json::to_vec(&json!({"rules":{
            "doc":{"type":"REPEAT1","content":{"type":"CHOICE","members":[
                {"type":"SYMBOL","name":"final"},{"type":"SYMBOL","name":"plain"},{"type":"STRING","value":"b"}]}},
            "final":{"type":"TOKEN","content":{"type":"PREC","value":1,"content":{"type":"PATTERN","value":"a$"}}},
            "plain":{"type":"TOKEN","content":{"type":"STRING","value":"a"}}},"extras":[]})).unwrap()).unwrap();
        let old = "a".repeat(96);
        let new = format!("{old}b");
        let (warm, replay, _) = extent_change(&grammar, old.as_bytes(), new.as_bytes(), old.len());
        assert!(warm.token_reads > 0 && warm.token_reads < replay.token_reads);
        let nullable=CompiledGrammar::compile(&serde_json::to_vec(&json!({"rules":{
            "doc":{"type":"SEQ","members":[{"type":"REPEAT1","content":{"type":"STRING","value":"p"}},
                {"type":"STRING","value":"u"},{"type":"STRING","value":"q"},{"type":"STRING","value":"r"},{"type":"SYMBOL","name":"zero"}]},
            "zero":{"type":"TOKEN","content":{"type":"PATTERN","value":"a*"}}},"extras":[]})).unwrap()).unwrap();
        let old = format!("{}uqr", "p".repeat(96));
        let new = format!("{old}aaa");
        extent_change(&nullable, old.as_bytes(), new.as_bytes(), old.len());
        let json =
            CompiledGrammar::compile(include_bytes!("../../../test/grammar/json.json")).unwrap();
        let old = format!(
            "[{}]",
            (0..96).map(|i| i.to_string()).collect::<Vec<_>>().join(",")
        );
        extent_change(
            &json,
            old.as_bytes(),
            &old.as_bytes()[..old.len() - 1],
            old.len() - 1,
        );
    }

    #[test]
    fn read_extent_keeps_limits_and_untrusted_edit_prefixes_fail_closed() {
        let grammar =
            CompiledGrammar::compile(include_bytes!("../../../test/grammar/json.json")).unwrap();
        let old = format!(
            "[{}]",
            (0..96).map(|i| i.to_string()).collect::<Vec<_>>().join(",")
        );
        let mut session = grammar.session();
        let mut store = grammar.effect_store();
        let first = session
            .parse_document(Arc::from(old.as_bytes()), None, &mut store)
            .unwrap();
        let retained = extent_image(&first.tree);
        let mut changed = old.as_bytes().to_vec();
        let at = changed.len() - 2;
        changed[at] = b'5';
        session.limits.lexical_steps = 0;
        assert!(matches!(
            session.parse_document(Arc::from(changed.as_slice()), Some(at), &mut store),
            Err(Error::Lex(crate::lexer::LexError::WorkLimit { .. }))
        ));
        assert_eq!(extent_image(&first.tree), retained);
        assert!(session.cache.is_none());
        // Supplying a later change index must not trust differing earlier bytes.
        let mut dishonest = old.as_bytes().to_vec();
        dishonest[1] = b'9';
        extent_change(&grammar, old.as_bytes(), &dishonest, at);
    }

    #[test]
    fn compact_scan_observations_preserve_flags_and_refuse_unrepresentable_offsets() {
        assert!(size_of::<CachedScan>() <= 16);
        assert_ne!(
            CachedScan::new(None).unwrap(),
            CachedScan::new(Some(Scanned {
                scan: Scan::End,
                provisional: false
            }))
            .unwrap()
        );
        let token = Lexeme {
            symbol: SymbolId::from_index(0),
            start: 1,
            end: 2,
            extra: false,
        };
        let ordinary = CachedScan::new(Some(Scanned {
            scan: Scan::Token(token),
            provisional: false,
        }))
        .unwrap();
        assert_ne!(
            ordinary,
            CachedScan::new(Some(Scanned {
                scan: Scan::Token(Lexeme {
                    extra: true,
                    ..token
                }),
                provisional: false
            }))
            .unwrap()
        );
        assert_ne!(
            ordinary,
            CachedScan::new(Some(Scanned {
                scan: Scan::Token(token),
                provisional: true
            }))
            .unwrap()
        );
        if usize::BITS > u32::BITS {
            assert!(
                CachedScan::new(Some(Scanned {
                    scan: Scan::Stray { at: usize::MAX },
                    provisional: false
                }))
                .is_err()
            );
        }
    }

    #[test]
    fn checkpoints_never_retain_the_live_permission_cache_payload() {
        let grammar =
            CompiledGrammar::compile(br#"{"rules":{"doc":{"type":"STRING","value":"x"}}}"#)
                .unwrap();
        let mut session = grammar.session();
        let mut head = Head::new(grammar.start_state(), 1);
        let slate = session
            .admission_slate(&grammar.automaton, &mut head)
            .unwrap();
        let weak = Arc::downgrade(&slate);
        drop(slate);
        session.recording = Some(Recording::new(false));
        session.checkpoint(&head).unwrap();
        let recording = session.recording.as_ref().unwrap();
        assert_eq!(recording.checkpoints.len(), 1);
        assert!(recording.checkpoints[0].head.slate.is_none());
        assert!(weak.upgrade().is_some());
        drop(head);
        // The run's bounded proof pool may own the slate; the checkpoint does
        // not. Releasing the pool must release that final owner as well.
        session.slates.clear();
        assert!(weak.upgrade().is_none());
    }

    #[test]
    fn a_resumed_generic_choice_uses_the_retained_prefix_derivation() {
        let cases: serde_json::Value =
            serde_json::from_str(include_str!("../../tests/fixtures/declared-choice.json"))
                .unwrap();
        let case = cases
            .as_array()
            .unwrap()
            .iter()
            .find(|c| c["name"] == "call_first")
            .unwrap();
        let mut rules: serde_json::Value =
            serde_json::from_str(case["grammar"].as_str().unwrap()).unwrap();
        rules["rules"]["program"] = serde_json::json!({"type":"REPEAT1","content":{
            "type":"SEQ","members":[{"type":"SYMBOL","name":"_expr"},{"type":"STRING","value":";"}]}});
        let grammar = CompiledGrammar::compile(&serde_json::to_vec(&rules).unwrap()).unwrap();
        let old = format!("{}f(\"b\");", "f(\"a\");\n".repeat(48));
        let at = old.len() - "f(\"b\");".len() + 1;
        let mut session = grammar.session();
        let mut store = grammar.effect_store();
        session
            .parse_document(Arc::from(old.as_bytes()), None, &mut store)
            .unwrap();
        let cache = session.cache.take().unwrap();
        assert!(
            cache
                .recording
                .checkpoints
                .iter()
                .all(|checkpoint| checkpoint.head.slate.is_none())
        );
        let trace = std::mem::take(&mut session.trace);
        let ends = std::mem::take(&mut session.ends);
        let mut edited = old.as_bytes().to_vec();
        edited.splice(at..at, b"<T>".iter().copied());
        let edited: Arc<[u8]> = Arc::from(edited);
        session.document_source = Some(Arc::clone(&edited));
        session.reset_run();
        let mut stats = ReuseStats::default();
        session
            .restore_prefix(cache, trace, ends, &edited, at, &mut stats)
            .unwrap();
        assert!(stats.resumed_at > 0);
        assert!(stats.validated_events > 0);
        assert!(!session.resume.as_ref().unwrap().trace.is_empty());
        assert!(session.resume.as_ref().unwrap().slate.is_none());
        // Inspect the actual resumed result before the document wrapper's
        // conservative cold fallback on ambiguous executions.
        let warm = session.parse_inner(&edited).unwrap();
        let cold = grammar.session().parse(&edited).unwrap();
        let image = |tree: &TreeSnapshot| {
            let mut pending: Vec<_> = tree.roots().rev().map(|n| (n, 0)).collect();
            let mut rows = vec![];
            while let Some((node, depth)) = pending.pop() {
                rows.push((
                    depth,
                    node.name().to_string(),
                    node.is_named(),
                    node.field().map(str::to_string),
                    node.span(),
                ));
                pending.extend(node.children().rev().map(|child| (child, depth + 1)));
            }
            rows
        };
        assert_eq!(image(&warm), image(&cold));
        assert!(warm.confidence().is_strict());
        let last = warm
            .root()
            .unwrap()
            .children()
            .rfind(|n| n.is_named())
            .unwrap();
        assert_eq!(last.name(), "call_expression");
        assert!(last.child_by_field("type_arguments").is_some());
    }

    #[test]
    fn move_segments_keep_eof_folds_trailing_bytes_holes_and_empty_sources() {
        let empty =
            CompiledGrammar::compile(br#"{"name":"empty","rules":{"doc":{"type":"BLANK"}}}"#)
                .unwrap();
        let json =
            CompiledGrammar::compile(include_bytes!("../../../test/grammar/json.json")).unwrap();
        for (grammar, source, recovered) in [
            (Arc::clone(&empty), b"".as_slice(), false),
            (Arc::clone(&json), b"[1]  \r\n".as_slice(), false),
            (Arc::clone(&json), b"[1,,2]".as_slice(), true),
        ] {
            let mut session = grammar.session();
            if recovered {
                session.set_recovery(Recovery::Fell);
                session.set_supply(Supply::UniqueLiteral);
            }
            let mut store = grammar.effect_store();
            let source: Arc<[u8]> = Arc::from(source);
            let parsed = session
                .parse_document(Arc::clone(&source), None, &mut store)
                .unwrap();
            assert!(Arc::ptr_eq(&source, &parsed.tree.source));
            assert_eq!(
                parsed.segments.iter().map(|s| s.bytes).sum::<usize>(),
                source.len()
            );
            assert!(!parsed.segments.is_empty());
            let measured = store
                .fold(parsed.segments.iter().map(|s| s.effect))
                .unwrap();
            assert_eq!(measured, session.product(&mut store).unwrap());
            if recovered {
                assert!(measured.is_zero());
            }
        }
    }
    #[test]
    fn advisory_cache_stands_down_on_deep_histories_without_changing_the_parse() {
        let grammar = CompiledGrammar::compile(br#"{"name":"nested","rules":{"doc":{"type":"CHOICE","members":[{"type":"STRING","value":"x"},{"type":"SEQ","members":[{"type":"STRING","value":"("},{"type":"SYMBOL","name":"doc"},{"type":"STRING","value":")"}]}]}}}"#).unwrap();
        let input = format!("{}x{}", "(".repeat(4096), ")".repeat(4096));
        let source: Arc<[u8]> = Arc::from(input.as_bytes());
        let mut session = grammar.session();
        let mut store = grammar.effect_store();
        let parsed = session.parse_document(source, None, &mut store).unwrap();
        assert!(parsed.tree.confidence().is_strict());
        if let Some(cache) = &session.cache {
            let drafts = cache.drafts.iter().fold(
                elements_bytes::<Draft>(cache.drafts.capacity()),
                |n, draft| n.saturating_add(elements_bytes::<Use>(draft.children.capacity())),
            );
            assert_eq!(cache.recording.used, cache.recording.metadata_bytes());
            assert!(cache.recording.used.saturating_add(drafts) <= MAX_CACHE_BYTES);
        }
        // The complete replay representation still refuses this deep history;
        // retaining cheap regex proofs must not relax its metadata ceiling.
        let mut full = grammar.session();
        full.force_cache_replay = true;
        let mut full_store = grammar.effect_store();
        let full_tree = full
            .parse_document(Arc::from(input.as_bytes()), None, &mut full_store)
            .unwrap();
        assert!(full.cache.is_none());
        assert_eq!(extent_image(&parsed.tree), extent_image(&full_tree.tree));
        let cold = grammar.session().parse(input.as_bytes()).unwrap();
        assert_eq!(parsed.tree.survey().walked, cold.survey().walked);
    }
    #[test]
    fn enabling_selected_receipts_discards_an_existing_document_checkpoint() {
        let grammar =
            CompiledGrammar::compile(include_bytes!("../../../test/grammar/json.json")).unwrap();
        let source = format!(
            "[{}]",
            (0..96).map(|n| n.to_string()).collect::<Vec<_>>().join(",")
        );
        let mut session = grammar.session();
        let mut store = grammar.effect_store();
        session
            .parse_document(Arc::from(source.as_bytes()), None, &mut store)
            .unwrap();
        assert!(session.cache.is_some());
        session.set_trace_enabled(true);
        assert!(session.cache.is_none());
        let mut edited = source.into_bytes();
        let at = edited.len() - 2;
        edited[at] = b'6';
        let parsed = session
            .parse_document(Arc::from(edited), Some(at), &mut store)
            .unwrap();
        assert!(parsed.tree.confidence().is_strict());
        assert_eq!(parsed.stats.resumed_at, 0);
        assert!(session.cache.is_none());
        let tokens = session.selected_tokens().unwrap();
        assert_eq!(tokens.len(), 193);
        assert_eq!(tokens.first().unwrap().span.start(), 0);
        assert_eq!(
            tokens.last().unwrap().span.end(),
            parsed.tree.source().len()
        );
        assert_eq!(tokens.first().unwrap().moves.start, 0);
        assert!(
            tokens
                .windows(2)
                .all(|p| p[0].moves.end == p[1].moves.start)
        );
    }

    #[test]
    fn deterministic_receipts_allow_a_large_json_prefix_resume() {
        let grammar =
            CompiledGrammar::compile(include_bytes!("../../../test/grammar/json.json")).unwrap();
        let input = format!(
            "[{}]",
            (0..96)
                .map(|i| format!("{{\"key\":{i},\"text\":\"item\"}}"))
                .collect::<Vec<_>>()
                .join(",\n")
        );
        let mut session = grammar.session();
        let mut store = grammar.effect_store();
        let initial = session
            .parse_document(Arc::from(input.as_bytes()), None, &mut store)
            .unwrap();
        assert!(initial.tree.confidence().is_strict());
        assert!(session.cache.is_some());
        let mut edited = input.into_bytes();
        let at = edited.len() - 7;
        edited[at] = b'I';
        let next = session
            .parse_document(Arc::from(edited), Some(at), &mut store)
            .unwrap();
        assert!(next.stats.resumed_at > 0);
        let mut refused = next.tree.source().to_vec();
        let changed = refused.len() - 8;
        refused[changed] = b'I'; // opening quote: the edited document is partial.
        let partial = session
            .parse_document(Arc::from(refused), Some(changed), &mut store)
            .unwrap();
        assert!(!partial.tree.confidence().is_strict());
        assert_eq!(partial.stats.resumed_at, 0);
        assert!(
            partial.stats.materialized_nodes > partial.tree.nodes.len(),
            "both the attempted prefix result and cold fallback must be measured"
        );
        let mut cold = grammar.session();
        cold.parse_partial(partial.tree.source()).unwrap();
        assert_eq!(partial.stats.token_reads, session.token_reads());
        assert!(
            partial.stats.token_reads > cold.token_reads(),
            "validation and the discarded warm attempt remain in the actual read bill"
        );
    }

    #[test]
    fn compact_metadata_retains_a_131k_json_prefix_within_the_same_32mib_ceiling() {
        let grammar =
            CompiledGrammar::compile(include_bytes!("../../../test/grammar/json.json")).unwrap();
        assert!(grammar.program.is_none());
        let seed = include_str!("../../../research/joinery/corpus/ledger.json").trim();
        let input = format!("[{}]\n", [seed; 170].join(",\n"));
        assert_eq!(input.len(), 131_751);
        let mut session = grammar.session();
        let mut store = grammar.effect_store();
        session
            .parse_document(Arc::from(input.as_bytes()), None, &mut store)
            .unwrap();
        let cache = session
            .cache
            .as_ref()
            .expect("large ordinary JSON should retain its checked prefix");
        assert_eq!(cache.recording.used, cache.recording.metadata_bytes());
        let drafts = cache
            .drafts
            .iter()
            .fold(elements_bytes::<Draft>(cache.drafts.capacity()), |n, d| {
                n.saturating_add(elements_bytes::<Use>(d.children.capacity()))
            });
        assert!(cache.recording.used.saturating_add(drafts) <= MAX_CACHE_BYTES);
        assert!(
            cache
                .recording
                .events
                .iter()
                .all(|e| matches!(e, Event::Interior(_)))
        );
        let target = input.len() * 98 / 100;
        let at = input[..target].rfind("\"total\"").unwrap() + 1;
        let mut edited = input.into_bytes();
        let image = |tree: &TreeSnapshot| {
            let mut pending: Vec<_> = tree.roots().rev().map(|n| (n, 0)).collect();
            let mut rows = vec![];
            while let Some((node, depth)) = pending.pop() {
                rows.push((
                    depth,
                    node.name().to_owned(),
                    node.is_named(),
                    node.field().map(str::to_owned),
                    node.span(),
                ));
                pending.extend(node.children().rev().map(|child| (child, depth + 1)));
            }
            rows
        };
        for byte in b"IRS" {
            edited[at] = *byte;
            let next = session
                .parse_document(Arc::from(edited.as_slice()), Some(at), &mut store)
                .unwrap();
            assert!(next.stats.resumed_at >= next.tree.source().len() * 9 / 10);
            assert!(next.stats.validated_events > 0);
            let cold = grammar.session().parse(next.tree.source()).unwrap();
            assert_eq!(image(&next.tree), image(&cold));
            assert_eq!(next.tree.stop(), cold.stop());
            let cache = session.cache.as_ref().unwrap();
            assert!(cache.recording.used <= MAX_CACHE_BYTES);
            assert_eq!(cache.recording.used, cache.recording.metadata_bytes());
            assert!(cache.recording.checkpoints.len() <= MAX_CHECKPOINTS);
        }
    }

    #[test]
    fn advisory_metadata_ceiling_includes_capacity_and_refuses_saturating_requests() {
        let grammar =
            CompiledGrammar::compile(br#"{"rules":{"doc":{"type":"STRING","value":"x"}}}"#)
                .unwrap();
        let mut session = grammar.session();
        session.recording = Some(Recording::new(false));
        assert!(session.reserve_record(0, 0, RecordKind::Event).unwrap());
        let recording = session.recording.as_ref().unwrap();
        assert_eq!(recording.used, recording.metadata_bytes());
        assert!(recording.events.capacity() >= 4);
        session.recording.as_mut().unwrap().used = MAX_CACHE_BYTES - 8;
        assert!(session.reserve_record(0, 8, RecordKind::Payload).unwrap());
        assert_eq!(session.recording.as_ref().unwrap().used, MAX_CACHE_BYTES);
        assert!(
            !session
                .reserve_record(0, usize::MAX, RecordKind::Payload)
                .unwrap()
        );
        let recording = session.recording.as_ref().unwrap();
        assert!(recording.disabled);
        assert_eq!(recording.events.capacity(), 0);
        assert_eq!(recording.used, recording.metadata_bytes());
    }

    #[test]
    fn distributed_checkpoints_handle_empty_small_and_changed_length_documents() {
        let grammar =
            CompiledGrammar::compile(include_bytes!("../../../test/grammar/json.json")).unwrap();
        let mut session = grammar.session();
        let mut store = grammar.effect_store();
        for (source, edit) in [
            (b"".as_slice(), None),
            (b"1", Some(0)),
            (b"[1]", Some(0)),
            (b"[10]", Some(2)),
            (b"[100,2]", Some(3)),
            (b"[0]", Some(1)),
            (b"[0] \n", Some(3)),
            (b"", Some(0)),
            (b"{}", Some(0)),
        ] {
            let parsed = session
                .parse_document(Arc::from(source), edit, &mut store)
                .unwrap();
            let cold = grammar.session().parse_partial(source).unwrap();
            assert_eq!(parsed.tree.source(), cold.source());
            assert_eq!(parsed.tree.stop(), cold.stop());
            assert_eq!(parsed.tree.survey().walked, cold.survey().walked);
            let nodes = |tree: &TreeSnapshot| {
                (0..tree.nodes.len())
                    .map(|i| {
                        let n = tree.node_at(i).unwrap();
                        (
                            n.name().to_owned(),
                            n.is_named(),
                            n.is_extra(),
                            n.field().map(str::to_owned),
                            n.span(),
                            n.parent().map(|p| p.index()),
                            n.children().map(|c| c.index()).collect::<Vec<_>>(),
                        )
                    })
                    .collect::<Vec<_>>()
            };
            assert_eq!(nodes(&parsed.tree), nodes(&cold));
            if let Some(cache) = &session.cache {
                assert!(cache.recording.checkpoints.len() <= MAX_CHECKPOINTS);
                assert!(
                    cache
                        .recording
                        .checkpoints
                        .windows(2)
                        .all(|p| p[0].head.at < p[1].head.at)
                );
                assert_eq!(cache.recording.used, cache.recording.metadata_bytes());
            }
        }
    }
}
