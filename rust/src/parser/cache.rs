//! Conservative prefix reuse. Validation reexecutes complete scanner calls,
//! including speculative extras, rather than assuming a token's end bounds its reads.
use super::*;
use crate::{scanner::ScanHit, sequence::Segment};

const MAX_CACHE_BYTES: usize = 32 * 1024 * 1024;

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

#[derive(PartialEq, Eq)]
enum Receipt {
    Regex {
        scope: ScanScope,
        at: usize,
        fresh: bool,
        admitted: Option<Vec<SymbolId>>,
        empty_permit: Vec<SymbolId>,
        provisional_empty: Vec<SymbolId>,
        eof: bool,
        result: Scan,
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
    wanted: Vec<SymbolId>,
    named: Vec<SymbolId>,
    before: ScannerState,
    after: ScannerState,
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
                .saturating_add(admitted.as_ref().map_or(0, Vec::len))
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

struct Event {
    states: Vec<StateId>,
    at: usize,
    fresh: bool,
    after_node: bool,
    before: ScannerState,
    after: ScannerState,
    result: Option<Scanned>,
    after_at: usize,
    after_fresh: bool,
    after_node_after: bool,
    extras: Vec<Use>,
    receipts: std::ops::Range<usize>,
}
struct Checkpoint {
    head: Head,
    drafts: usize,
    moves: usize,
    events: usize,
    receipts: usize,
}
pub(super) struct ParseCache {
    source: Arc<[u8]>,
    drafts: Vec<Draft>,
    recording: Recording,
    recovery: Recovery,
    supply: Supply,
}
fn initial_buffer_allowance() -> usize {
    4 * (std::mem::size_of::<Event>()
        + std::mem::size_of::<Receipt>()
        + std::mem::size_of::<Checkpoint>())
}
pub(super) struct Recording {
    events: Vec<Event>,
    receipts: Vec<Receipt>,
    checkpoints: Vec<Checkpoint>,
    probe: bool,
    disabled: bool,
    used: usize,
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
        }
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
                    self.drafts
                        .capacity()
                        .saturating_mul(std::mem::size_of::<Draft>()),
                    |n, d| {
                        n.saturating_add(
                            d.children
                                .capacity()
                                .saturating_mul(std::mem::size_of::<Use>()),
                        )
                    },
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
        let prefix = old.recording.checkpoints[last].head.at;
        self.charge(prefix)?;
        if old.source[..prefix] != source[..prefix] {
            return Ok(());
        }
        let mut valid = 0;
        let mut index_owner = ScannerState::default();
        self.recording = Some(Recording::new(true));
        for event in &old.recording.events[..target_events] {
            self.charge(event.states.len().saturating_add(event.before.clone_work()))?;
            let mut head = Head::new(self.grammar.automaton.start_state(), event.at);
            head.states = event.states.clone();
            head.slate = None;
            head.fresh = event.fresh;
            head.after_node = event.after_node;
            head.scanner = event.before.clone();
            head.scanner.copy_source_index_from(&index_owner);
            self.drafts.clear();
            let result = self.document_scan(source, &mut head, &Exclusions::default(), None)?;
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
                && result == event.result
                && head.at == event.after_at
                && head.fresh == event.after_fresh
                && head.after_node == event.after_node_after
                && head.scanner == event.after;
            if !same || !self.same_extras(&old.drafts, &event.extras, &head.pending)? {
                break;
            }
            index_owner.copy_source_index_from(&head.scanner);
            let observed = self.recording.as_mut().unwrap();
            observed.receipts.clear();
            observed.used = initial_buffer_allowance();
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
            let left = &old[a.draft];
            let right = &self.drafts[b.draft];
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
            let left = &old[a.draft];
            let right = &self.drafts[b.draft];
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
            recording.events.clear();
            recording.receipts.clear();
            recording.checkpoints.clear();
        }
    }
    fn reserve_record(&mut self, work: usize) -> Result<bool, Error> {
        let Some(recording) = &self.recording else {
            return Ok(false);
        };
        if recording.disabled {
            return Ok(false);
        }
        // A conservative upper bound for every owned entry/tag byte copied by
        // scanner snapshots, states, uses and receipt/vector headers.
        let fixed = std::mem::size_of::<Event>()
            .max(std::mem::size_of::<Receipt>())
            .max(std::mem::size_of::<ProgramReceipt>())
            .max(std::mem::size_of::<Checkpoint>());
        let bytes = work
            .saturating_add(1)
            .saturating_mul(128)
            .saturating_add(fixed.saturating_mul(2));
        if recording.used.saturating_add(bytes) > MAX_CACHE_BYTES {
            self.disable_recording();
            return Ok(false);
        }
        self.charge(work)?;
        self.recording.as_mut().unwrap().used += bytes;
        Ok(true)
    }
    pub(super) fn checkpoint(&mut self, head: &Head) -> Result<(), Error> {
        let Some(recording) = &self.recording else {
            return Ok(());
        };
        if recording.disabled
            || recording.probe
            || head.at == 0
            || (!recording.checkpoints.is_empty() && recording.events.len() % 8 != 0)
        {
            return Ok(());
        }
        self.charge(head.frames.len().saturating_add(head.pending.len()))?;
        if head.last_end > head.at
            || head.frames.iter().any(|frame| frame.span.end() > head.at)
            || head
                .pending
                .iter()
                .any(|use_| self.drafts[use_.draft].span.end() > head.at)
        {
            self.disable_recording();
            return Ok(());
        }
        if !self.reserve_record(head.clone_without_history_work())? {
            return Ok(());
        }
        let copy = Head {
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
        };
        let recording = self.recording.as_mut().unwrap();
        if recording.checkpoints.len() == 64 {
            recording.checkpoints.remove(1);
        }
        recording.checkpoints.push(Checkpoint {
            head: copy,
            drafts: self.drafts.len(),
            moves: head.trace.len(),
            events: recording.events.len(),
            receipts: recording.receipts.len(),
        });
        Ok(())
    }

    pub(super) fn document_scan(
        &mut self,
        source: &[u8],
        head: &mut Head,
        excluded: &Exclusions,
        prebuilt: Option<&AdmissionSlate>,
    ) -> Result<Option<Scanned>, Error> {
        let capture = self
            .recording
            .as_ref()
            .is_some_and(|r| !r.disabled && !r.probe);
        let entry = if capture
            && self.reserve_record(head.states.len().saturating_add(head.scanner.clone_work()))?
        {
            Some((
                head.states.clone(),
                head.at,
                head.fresh,
                head.after_node,
                semantic_snapshot(&head.scanner),
                head.pending.len(),
                self.recording.as_ref().unwrap().receipts.len(),
            ))
        } else {
            None
        };
        let result = self.document_scan_inner(source, head, excluded, prebuilt)?;
        if let Some((states, at, fresh, after_node, before, pending, start)) = entry {
            if self.recording.as_ref().is_some_and(|r| !r.disabled) {
                if !self.reserve_record(
                    head.scanner
                        .clone_work()
                        .saturating_add(head.pending.len() - pending),
                )? {
                    return Ok(result);
                }
                let after = semantic_snapshot(&head.scanner);
                let extras = head.pending[pending..].to_vec();
                let recording = self.recording.as_mut().unwrap();
                recording.events.push(Event {
                    states,
                    at,
                    fresh,
                    after_node,
                    before,
                    after,
                    extras,
                    result,
                    after_at: head.at,
                    after_fresh: head.fresh,
                    after_node_after: head.after_node,
                    receipts: start..recording.receipts.len(),
                });
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
        let saved = if recording
            && self.reserve_record(
                2usize
                    .saturating_add(question.admitted.map_or(0, <[SymbolId]>::len))
                    .saturating_add(question.empty_permit.len())
                    .saturating_add(question.provisional_empty.len()),
            )? {
            Some((
                question.admitted.map(<[SymbolId]>::to_vec),
                question.empty_permit.to_vec(),
                question.provisional_empty.to_vec(),
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
                    result,
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
            )? {
            Some((
                semantic_snapshot(&head.scanner),
                wanted.to_vec(),
                named.to_vec(),
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
            if !self.reserve_record(head.scanner.clone_work())? {
                return Ok(result);
            }
            let after = semantic_snapshot(&head.scanner);
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

    #[test]
    fn checkpoints_never_retain_the_live_permission_cache_payload() {
        let grammar =
            CompiledGrammar::compile(br#"{"rules":{"doc":{"type":"STRING","value":"x"}}}"#)
                .unwrap();
        let mut session = grammar.session();
        let mut head = Head::new(grammar.start_state(), 1);
        let slate = session.admission_slate(&mut head).unwrap();
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
        session.document_source = Some(edited.clone());
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
        let input = format!("{}x{}", "(".repeat(1500), ")".repeat(1500));
        let source: Arc<[u8]> = Arc::from(input.as_bytes());
        let mut session = grammar.session();
        let mut store = grammar.effect_store();
        let parsed = session.parse_document(source, None, &mut store).unwrap();
        assert!(parsed.tree.confidence().is_strict());
        assert!(
            session.cache.is_none(),
            "deep state receipts must not grow without an advisory bound"
        );
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
}
