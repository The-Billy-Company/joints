//! Exact-stack memoization of permission proofs, never of scanner answers.
use super::*;

pub(super) struct AdmissionSlate {
    states: Vec<StateId>,
    pub(super) ordinary: Vec<SymbolId>,
    pub(super) empty: Vec<SymbolId>,
    pub(super) uncertain: Vec<SymbolId>,
    pub(super) provisional_empty: Vec<SymbolId>,
    pub(super) extras: Vec<SymbolId>,
    pub(super) eof: bool,
    wanted: Vec<SymbolId>,
    document: Option<DocumentSlate>,
}

struct DocumentSlate {
    lexical: Vec<SymbolId>,
    wanted: Vec<SymbolId>,
}

impl AdmissionSlate {
    fn retained_bytes(&self) -> Option<usize> {
        let mut bytes = size_of::<Self>().checked_add(2 * size_of::<usize>())?;
        bytes = bytes.checked_add(self.states.capacity().checked_mul(size_of::<StateId>())?)?;
        for ids in [
            &self.ordinary,
            &self.empty,
            &self.uncertain,
            &self.provisional_empty,
            &self.extras,
            &self.wanted,
        ]
        .into_iter()
        .chain(self.document.iter().flat_map(|d| [&d.lexical, &d.wanted]))
        {
            bytes = bytes.checked_add(ids.capacity().checked_mul(size_of::<SymbolId>())?)?;
        }
        Some(bytes)
    }

    pub(super) fn view(&self, scope: ScanScope) -> (&[SymbolId], &[SymbolId]) {
        match (&self.document, scope) {
            (Some(document), ScanScope::Document) => (&document.lexical, &document.wanted),
            _ => (&self.ordinary, &self.wanted),
        }
    }
}

// Repeated structural stacks need the same proofs even after a shift cleared
// the head's derived handle. This direct-mapped pool retains only immutable
// proofs. A hash collision is a miss unless every state agrees; source reads,
// scanner memory, offsets, and lexical transition budgets remain live.
const POOL_SLOTS: usize = 256;
const POOL_BYTES: usize = 1 << 20;

struct RetainedSlate {
    slate: Arc<AdmissionSlate>,
    bytes: usize,
}

#[derive(Default)]
pub(super) struct SlatePool {
    slots: Box<[Option<RetainedSlate>]>,
    bytes: usize,
}

impl SlatePool {
    pub(super) fn clear(&mut self) {
        self.slots = Box::default();
        self.bytes = 0;
    }

    fn slot(states: &[StateId]) -> usize {
        // This hash locates one candidate, never establishes identity. Full
        // state equality below makes collisions ordinary bounded cache misses.
        let mut hash = (states.len() as u64) ^ 0x9e37_79b9_7f4a_7c15;
        for state in states {
            hash = hash.rotate_left(5).wrapping_mul(0x517c_c1b7_2722_0a95) ^ state.index() as u64;
        }
        usize::try_from((hash ^ (hash >> 32)) % (POOL_SLOTS as u64))
            .expect("bounded slate pool slot")
    }

    fn get(&self, slot: usize, states: &[StateId]) -> Option<&Arc<AdmissionSlate>> {
        self.slots
            .get(slot)?
            .as_ref()
            .filter(|entry| entry.slate.states == states)
            .map(|entry| &entry.slate)
    }

    fn retention(&self, slot: usize, slate: &AdmissionSlate) -> Option<(usize, usize)> {
        let bytes = slate.retained_bytes()?;
        let old = self
            .slots
            .get(slot)
            .and_then(Option::as_ref)
            .map_or(0, |entry| entry.bytes);
        let total = self.bytes.checked_sub(old)?.checked_add(bytes)?;
        let directory = POOL_SLOTS.checked_mul(size_of::<Option<RetainedSlate>>())?;
        (total.checked_add(directory)? <= POOL_BYTES).then_some((bytes, total))
    }

    fn insert(&mut self, slot: usize, slate: Arc<AdmissionSlate>, bytes: usize, total: usize) {
        if self.slots.is_empty() {
            self.slots = std::iter::repeat_with(|| None).take(POOL_SLOTS).collect();
        }
        self.slots[slot] = Some(RetainedSlate { slate, bytes });
        self.bytes = total;
    }
}

pub(super) struct FilteredAdmissions {
    pub(super) ordinary: Vec<SymbolId>,
    pub(super) lexical: Vec<SymbolId>,
    pub(super) wanted: Vec<SymbolId>,
    pub(super) empty: Vec<SymbolId>,
    pub(super) provisional_empty: Vec<SymbolId>,
}

#[cfg(test)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(super) struct Stats {
    pub(super) builds: usize,
    pub(super) hits: usize,
    pub(super) proofs: usize,
    pub(super) pooled_hits: usize,
}

impl ParseSession {
    pub(super) fn admission_slate(
        &mut self,
        head: &mut Head,
    ) -> Result<Arc<AdmissionSlate>, Error> {
        // Full content equality is a defensive check even though all real
        // state-stack mutations explicitly clear the head's derived cache.
        self.charge(head.states.len().saturating_add(1))?;
        #[cfg(test)]
        let reuse = !self.slate_cache_disabled;
        #[cfg(not(test))]
        let reuse = true;
        if reuse {
            if let Some(cached) = &head.slate {
                if cached.states == head.states {
                    self.charge(1)?;
                    #[cfg(test)]
                    {
                        self.slate_stats.hits += 1;
                    }
                    return Ok(Arc::clone(cached));
                }
            }
        }
        let pool_slot = if reuse {
            // Hash the full stack, compare at most one equally long key, and
            // share two handles only after this charge succeeds.
            self.charge(head.states.len().saturating_mul(2).saturating_add(3))?;
            let slot = SlatePool::slot(&head.states);
            if let Some(cached) = self.slates.get(slot, &head.states).map(Arc::clone) {
                head.slate = Some(Arc::clone(&cached));
                #[cfg(test)]
                {
                    self.slate_stats.hits += 1;
                    self.slate_stats.pooled_hits += 1;
                }
                return Ok(cached);
            }
            Some(slot)
        } else {
            None
        };
        let graph = Arc::clone(&self.grammar.automaton);
        let state = *head
            .states
            .last()
            .ok_or(Error::InvalidTable("empty state stack"))?;
        let row = graph.row_admissions(state);
        self.charge(row.len().saturating_mul(5))?;
        let mut ordinary = Vec::with_capacity(row.len());
        let mut empty = Vec::with_capacity(row.len());
        let mut uncertain = Vec::with_capacity(row.len());
        let mut provisional_empty = Vec::with_capacity(row.len());
        for &symbol in row {
            let (proof, work) = recovery::admission(&graph, &head.states, symbol);
            self.charge(work)?;
            #[cfg(test)]
            {
                self.slate_stats.proofs += 1;
            }
            if !matches!(proof, Proof::Stops) {
                ordinary.push(symbol);
            }
            if matches!(proof, Proof::Unknown(_)) {
                uncertain.push(symbol);
            }
            let spec = graph.symbol(symbol);
            if !spec.external
                && spec
                    .lexis
                    .as_ref()
                    .is_some_and(|rule| matches!(rule.pattern, crate::compiler::Pattern::Regex(_)))
            {
                match proof {
                    Proof::Reads(_) => empty.push(symbol),
                    Proof::Unknown(_) => {
                        // Eligibility to ask the real executor, never a
                        // completed proof or an extra-entry donation.
                        provisional_empty.push(symbol);
                    }
                    Proof::Stops => {}
                }
            }
        }
        // Compiler extras are sorted, but the artifact contract requires only
        // uniqueness. Canonicalize without trusting an unchecked ordering.
        let extras = self.slate_sorted(graph.extras())?;
        let wanted = self.slate_union(&ordinary, &extras)?;
        let document = if graph.extra_entries().is_empty() {
            None
        } else {
            self.charge(
                ordinary
                    .len()
                    .saturating_mul(2)
                    .saturating_add(graph.extra_entries().len()),
            )?;
            let mut lexical = ordinary.clone();
            for &(_, entry) in graph.extra_entries() {
                lexical = self.slate_union(&lexical, graph.row_admissions(entry))?;
            }
            let wanted = self.slate_union(&lexical, &extras)?;
            Some(DocumentSlate { lexical, wanted })
        };
        self.charge(head.states.len().saturating_mul(2).saturating_add(2))?;
        let cached = Arc::new(AdmissionSlate {
            states: head.states.clone(),
            ordinary,
            empty,
            uncertain,
            provisional_empty,
            extras,
            eof: !graph.actions(state, Lookahead::End).is_empty(),
            wanted,
            document,
        });
        #[cfg(test)]
        {
            self.slate_stats.builds += 1;
        }
        if reuse {
            self.charge(17)?;
            if let Some((slot, (bytes, total))) = pool_slot.and_then(|slot| {
                self.slates
                    .retention(slot, &cached)
                    .map(|size| (slot, size))
            }) {
                // Bounded directory initialization and fixed payload/header
                // ownership work; vector elements are shared rather than copied.
                self.charge(if self.slates.slots.is_empty() {
                    POOL_SLOTS + 16
                } else {
                    16
                })?;
                self.slates.insert(slot, Arc::clone(&cached), bytes, total);
            }
            head.slate = Some(Arc::clone(&cached));
        }
        Ok(cached)
    }

    pub(super) fn filtered_admissions(
        &mut self,
        slate: &AdmissionSlate,
        scope: ScanScope,
        excluded: &Exclusions,
    ) -> Result<Option<FilteredAdmissions>, Error> {
        if excluded.ordinary.is_empty() && excluded.auxiliary.is_empty() {
            return Ok(None);
        }
        let ordinary = self.slate_without(&slate.ordinary, &excluded.ordinary)?;
        let mut lexical = self.slate_union(&ordinary, &[])?;
        if scope == ScanScope::Document {
            let graph = Arc::clone(&self.grammar.automaton);
            for &(_, entry) in graph.extra_entries() {
                let first = self.slate_without(graph.row_admissions(entry), &excluded.auxiliary)?;
                lexical = self.slate_union(&lexical, &first)?;
            }
        }
        // Automatic extras remain independently eligible after an ordinary
        // role stopped. Their election standing and `extra` bit are explicit
        // consequences of this role-separated question, not token exclusion.
        let wanted = self.slate_union(&lexical, &slate.extras)?;
        Ok(Some(FilteredAdmissions {
            ordinary,
            lexical,
            wanted,
            empty: self.slate_without(&slate.empty, &excluded.ordinary)?,
            provisional_empty: self.slate_without(&slate.provisional_empty, &excluded.ordinary)?,
        }))
    }

    pub(super) fn slate_without(
        &mut self,
        ids: &[SymbolId],
        excluded: &[SymbolId],
    ) -> Result<Vec<SymbolId>, Error> {
        self.charge(
            ids.len()
                .saturating_mul(search_work(excluded.len()).saturating_add(2)),
        )?;
        Ok(ids
            .iter()
            .copied()
            .filter(|id| excluded.binary_search(id).is_err())
            .collect())
    }

    /// Each input is sorted and unique; action-row admissions guarantee this.
    fn slate_union(&mut self, a: &[SymbolId], b: &[SymbolId]) -> Result<Vec<SymbolId>, Error> {
        let capacity = a
            .len()
            .checked_add(b.len())
            .ok_or(Error::LimitExceeded(Resource::Work))?;
        // Allocate slots, visit the two inputs, and write the merged output.
        self.charge(capacity.saturating_mul(3).saturating_add(1))?;
        let mut merged = Vec::with_capacity(capacity);
        let (mut i, mut j) = (0, 0);
        while i < a.len() || j < b.len() {
            let symbol = match (a.get(i), b.get(j)) {
                (Some(&x), Some(&y)) if x < y => {
                    i += 1;
                    x
                }
                (Some(&x), Some(&y)) if x == y => {
                    i += 1;
                    j += 1;
                    x
                }
                (Some(_), Some(&y)) => {
                    j += 1;
                    y
                }
                (Some(&x), None) => {
                    i += 1;
                    x
                }
                (None, Some(&y)) => {
                    j += 1;
                    y
                }
                _ => break,
            };
            merged.push(symbol);
        }
        Ok(merged)
    }

    fn slate_sorted(&mut self, input: &[SymbolId]) -> Result<Vec<SymbolId>, Error> {
        self.charge(input.len())?;
        let mut sorted = Vec::with_capacity(input.len());
        for &symbol in input {
            self.charge(search_work(sorted.len()))?;
            if let Err(at) = sorted.binary_search(&symbol) {
                self.charge(sorted.len().saturating_sub(at).saturating_add(1))?;
                sorted.insert(at, symbol);
            }
        }
        Ok(sorted)
    }
}

pub(super) fn search_work(len: usize) -> usize {
    (usize::BITS - len.leading_zeros()) as usize + 1
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{CompiledGrammar, Node, TreeSnapshot};
    use serde_json::{Value, json};

    const CONTEXT: &[u8] = br#"{"name":"slate_context","rules":{
      "doc":{"type":"CHOICE","members":[
        {"type":"SEQ","members":[{"type":"STRING","value":"a"},{"type":"SYMBOL","name":"item"},{"type":"STRING","value":"x"}]},
        {"type":"SEQ","members":[{"type":"STRING","value":"b"},{"type":"SYMBOL","name":"item"},{"type":"STRING","value":"y"}]}]},
      "item":{"type":"SEQ","members":[{"type":"STRING","value":"q"},{"type":"STRING","value":"r"}]}},
      "extras":[{"type":"PATTERN","value":"[ ]"}]}"#;

    fn prefix(grammar: &CompiledGrammar, names: &[&str]) -> Head {
        let graph = &grammar.automaton;
        let mut head = Head::new(graph.start_state(), names.len());
        for name in names {
            let symbol = graph.terminal_by_name(name).unwrap();
            let next = graph
                .transition(*head.states.last().unwrap(), symbol)
                .unwrap();
            head.states.push(next);
        }
        head
    }

    fn image(node: Node<'_>) -> Value {
        json!({"name":node.name(),"named":node.is_named(),"extra":node.is_extra(),
            "span":[node.span().start(),node.span().end()],"field":node.field(),"text":node.text(),
            "start":[node.start_point().row,node.start_point().column],
            "end":[node.end_point().row,node.end_point().column],
            "children":node.children().map(image).collect::<Vec<_>>()})
    }

    fn assert_same(a: &TreeSnapshot, b: &TreeSnapshot) {
        assert_eq!(a.source(), b.source());
        assert_eq!(a.stop(), b.stop());
        assert_eq!(a.confidence(), b.confidence());
        assert_eq!(a.survey(), b.survey());
        assert_eq!(a.repairs(), b.repairs());
        assert_eq!(a.spurned(), b.spurned());
        assert_eq!(
            a.roots().map(image).collect::<Vec<_>>(),
            b.roots().map(image).collect::<Vec<_>>()
        );
    }

    fn compare_cached(grammar: &Arc<CompiledGrammar>, source: &[u8]) -> bool {
        let mut cached = grammar.session();
        let mut uncached = grammar.session();
        uncached.slate_cache_disabled = true;
        let a = cached.parse_partial(source).unwrap();
        let b = uncached.parse_partial(source).unwrap();
        assert_same(&a, &b);
        let mut store_a = grammar.effect_store();
        let mut store_b = grammar.effect_store();
        let a_effect = cached.product(&mut store_a).unwrap();
        let b_effect = uncached.product(&mut store_b).unwrap();
        assert_eq!(
            store_a.describe(a_effect).unwrap(),
            store_b.describe(b_effect).unwrap()
        );
        a.confidence().is_strict()
    }

    #[test]
    fn recurring_structural_stacks_share_proofs_while_tokens_remain_live() {
        let grammar =
            CompiledGrammar::compile(include_bytes!("../../../test/grammar/json.json")).unwrap();
        let source = format!(
            "[{}]",
            (0..1024)
                .map(|n| n.to_string())
                .collect::<Vec<_>>()
                .join(",")
        );
        let mut cached = grammar.session();
        let mut uncached = grammar.session();
        uncached.slate_cache_disabled = true;
        let a = cached.parse(source.as_bytes()).unwrap();
        let b = uncached.parse(source.as_bytes()).unwrap();
        assert_same(&a, &b);
        assert!(cached.slate_stats.pooled_hits > 1000);
        assert!(cached.slate_stats.proofs * 10 < uncached.slate_stats.proofs);
        assert_eq!(cached.token_reads, uncached.token_reads);
        let mut sa = grammar.effect_store();
        let mut sb = grammar.effect_store();
        let pa = cached.product(&mut sa).unwrap();
        let pb = uncached.product(&mut sb).unwrap();
        assert_eq!(sa.describe(pa).unwrap(), sb.describe(pb).unwrap());
        // A subsequent run uses its own live bytes and begins a fresh pool.
        let changed = source.replace("1023", "false");
        assert_same(
            &cached.parse(changed.as_bytes()).unwrap(),
            &uncached.parse(changed.as_bytes()).unwrap(),
        );
    }

    #[test]
    fn pool_collisions_require_full_keys_and_large_payloads_stand_down() {
        let grammar = CompiledGrammar::compile(CONTEXT).unwrap();
        let mut session = grammar.session();
        let mut head = prefix(&grammar, &["a", "q", "r"]);
        let slate = session.admission_slate(&mut head).unwrap();
        let slot = SlatePool::slot(&head.states);
        let mut collision = head.states.clone();
        collision[0] = (1..10_000)
            .map(StateId::from_index)
            .find(|&state| {
                let mut key = head.states.clone();
                key[0] = state;
                key != head.states && SlatePool::slot(&key) == slot
            })
            .expect("a colliding distinct full key");
        assert!(session.slates.get(slot, &collision).is_none());
        assert!(Arc::ptr_eq(
            session.slates.get(slot, &head.states).unwrap(),
            &slate
        ));
        let oversized = AdmissionSlate {
            states: vec![StateId::from_index(0); POOL_BYTES / size_of::<StateId>()],
            ordinary: vec![],
            empty: vec![],
            uncertain: vec![],
            provisional_empty: vec![],
            extras: vec![],
            eof: false,
            wanted: vec![],
            document: None,
        };
        assert!(session.slates.retention(slot, &oversized).is_none());
        assert!(
            session.slates.bytes + session.slates.slots.len() * size_of::<Option<RetainedSlate>>()
                <= POOL_BYTES
        );
        // No pooled handle may be published when the complete-key charge fails.
        head.slate = None;
        session.steps = 0;
        session.limits.steps = head.states.len() + 1;
        assert!(matches!(
            session.admission_slate(&mut head),
            Err(Error::LimitExceeded(Resource::Work))
        ));
        assert!(head.slate.is_none());
    }

    #[test]
    fn identical_tops_do_not_reuse_a_different_predecessor_stack() {
        let grammar = CompiledGrammar::compile(CONTEXT).unwrap();
        let mut a = prefix(&grammar, &["a", "q", "r"]);
        let mut b = prefix(&grammar, &["b", "q", "r"]);
        assert_eq!(a.states.last(), b.states.last());
        assert_ne!(a.states, b.states);
        let mut session = grammar.session();
        let old = session.admission_slate(&mut a).unwrap();
        b.slate = Some(Arc::clone(&old)); // Deliberately defeat explicit clears.
        let other = session.admission_slate(&mut b).unwrap();
        assert!(!Arc::ptr_eq(&old, &other));
        for (head, slate, wanted, refused) in [(&a, &old, "x", "y"), (&b, &other, "y", "x")] {
            let yes = grammar.automaton.terminal_by_name(wanted).unwrap();
            let no = grammar.automaton.terminal_by_name(refused).unwrap();
            assert!(matches!(
                recovery::admission(&grammar.automaton, &head.states, yes).0,
                Proof::Reads(_)
            ));
            assert_eq!(
                recovery::admission(&grammar.automaton, &head.states, no).0,
                Proof::Stops
            );
            assert!(slate.ordinary.contains(&yes));
            assert!(!slate.ordinary.contains(&no));
        }
        let before = session.slate_stats;
        assert!(Arc::ptr_eq(&old, &session.admission_slate(&mut a).unwrap()));
        assert_eq!(session.slate_stats.builds, before.builds);
        assert_eq!(session.slate_stats.proofs, before.proofs);
        assert_eq!(session.slate_stats.hits, before.hits + 1);
    }

    #[test]
    fn thousands_of_extra_reads_reuse_proofs_but_still_read_the_source() {
        let grammar = CompiledGrammar::compile(CONTEXT).unwrap();
        let mut short = grammar.session();
        let mut long = grammar.session();
        short.parse(b"aqr x").unwrap();
        let source = format!("aqr{}x", " ".repeat(4096));
        long.parse(source.as_bytes()).unwrap();
        assert_eq!(short.slate_stats.builds, long.slate_stats.builds);
        assert_eq!(short.slate_stats.proofs, long.slate_stats.proofs);
        assert_eq!(long.slate_stats.hits, short.slate_stats.hits + 4095);
        assert_eq!(long.token_reads(), short.token_reads() + 4095);
        assert!(long.lexical_remaining < short.lexical_remaining);
        assert!(compare_cached(&grammar, source.as_bytes()));
    }

    #[test]
    fn freshness_and_raw_fallback_are_not_cached_scanner_answers() {
        let grammar = CompiledGrammar::compile(
            br#"{"rules":{"doc":{"type":"SEQ","members":[
          {"type":"STRING","value":"a"},{"type":"CHOICE","members":[
          {"type":"IMMEDIATE_TOKEN","content":{"type":"STRING","value":"b"}},
          {"type":"STRING","value":"c"}]},{"type":"STRING","value":"!"}]}},
          "extras":[{"type":"PATTERN","value":"[ ]"}]}"#,
        )
        .unwrap();
        for (source, strict) in [(b"ab!".as_slice(), true), (b"a b!", false), (b"a c!", true)] {
            assert_eq!(compare_cached(&grammar, source), strict);
        }
        let mut value: Value = serde_json::from_slice(CONTEXT).unwrap();
        value["rules"]["doc"]["members"][0]["members"][2]["value"] = json!("xx");
        value["rules"]["doc"]["members"][1]["members"][2]["value"] = json!("yy");
        value["rules"]["doc"]["members"]
            .as_array_mut()
            .unwrap()
            .push(json!({"type":"SEQ","members":[
            {"type":"STRING","value":"c"},{"type":"STRING","value":"y"}]}));
        let grammar = CompiledGrammar::compile(&serde_json::to_vec(&value).unwrap()).unwrap();
        let tree = grammar.session().parse_partial(b"aqryy").unwrap();
        assert_eq!(tree.stop_symbol(), Some("yy"));
        assert!(matches!(tree.stop(), Stop::Unexpected { at: 3, .. }));
        assert!(!compare_cached(&grammar, b"aqryy"));
    }

    #[test]
    fn auxiliary_firsts_cannot_donate_empty_or_plain_permissions() {
        let grammar = CompiledGrammar::compile(br##"{"rules":{
          "doc":{"type":"STRING","value":"x"},
          "comment":{"type":"SEQ","members":[{"type":"SYMBOL","name":"zero"},{"type":"STRING","value":"#"}]},
          "zero":{"type":"TOKEN","content":{"type":"PATTERN","value":"a*"}}},
          "extras":[{"type":"SYMBOL","name":"comment"}]}"##).unwrap();
        let mut session = grammar.session();
        let mut head = Head::new(grammar.start_state(), 0);
        let slate = session.admission_slate(&mut head).unwrap();
        let zero = grammar.automaton.terminal_by_name("zero").unwrap();
        assert!(slate.view(ScanScope::Document).0.contains(&zero));
        assert!(!slate.view(ScanScope::Structural).0.contains(&zero));
        assert!(!slate.view(ScanScope::Extra).0.contains(&zero));
        assert!(!slate.empty.contains(&zero));
        assert!(!slate.eof);
        assert!(compare_cached(&grammar, b"x"));
        assert!(!compare_cached(&grammar, b"#x"));
    }

    #[test]
    fn exhausted_proof_stays_positive_but_never_grants_an_empty_shift() {
        let mut rules = serde_json::Map::new();
        rules.insert(
            "doc".into(),
            json!({"type":"SEQ","members":[
            {"type":"SYMBOL","name":"n0"},{"type":"SYMBOL","name":"end"}]}),
        );
        for i in 0..96 {
            rules.insert(
                format!("n{i}"),
                json!({"type":"SYMBOL","name":format!("n{}",i+1)}),
            );
        }
        rules.insert(
            "n96".into(),
            json!({"type":"SEQ","members":[
            {"type":"STRING","value":"a"},{"type":"STRING","value":"b"}]}),
        );
        rules.insert(
            "end".into(),
            json!({"type":"TOKEN","content":{"type":"PATTERN","value":"z*"}}),
        );
        let grammar = CompiledGrammar::compile(
            &serde_json::to_vec(&json!({"rules":rules,"extras":[]})).unwrap(),
        )
        .unwrap();
        let mut head = prefix(&grammar, &["a", "b"]);
        let end = grammar.automaton.terminal_by_name("end").unwrap();
        assert!(matches!(
            recovery::admission(&grammar.automaton, &head.states, end).0,
            Proof::Unknown(_)
        ));
        let mut session = grammar.session();
        let slate = session.admission_slate(&mut head).unwrap();
        assert!(slate.ordinary.contains(&end));
        assert!(!slate.empty.contains(&end));
        assert!(compare_cached(&grammar, b"abz"));
    }

    #[test]
    fn state_mutation_invalidates_only_the_mutated_fork() {
        let grammar = CompiledGrammar::compile(CONTEXT).unwrap();
        let graph = &grammar.automaton;
        let mut session = grammar.session();
        let mut head = Head::new(graph.start_state(), 0);
        for (at, name) in ["a", "q", "r"].into_iter().enumerate() {
            session.admission_slate(&mut head).unwrap();
            let from = *head.states.last().unwrap();
            let symbol = graph.terminal_by_name(name).unwrap();
            let to = graph.transition(from, symbol).unwrap();
            session
                .shift(
                    &mut head,
                    Lexeme {
                        symbol,
                        start: at,
                        end: at + 1,
                        extra: false,
                    },
                    from,
                    to,
                    false,
                )
                .unwrap();
            assert!(head.slate.is_none());
        }
        let shared = session.admission_slate(&mut head).unwrap();
        let mut branch = head.clone();
        assert!(Arc::ptr_eq(branch.slate.as_ref().unwrap(), &shared));
        let x = graph.terminal_by_name("x").unwrap();
        let Action::Reduce(family) =
            graph.actions(*branch.states.last().unwrap(), Lookahead::Terminal(x))[0]
        else {
            panic!("expected item reduction")
        };
        session.reduce(&mut branch, family).unwrap();
        assert!(branch.slate.is_none());
        assert!(Arc::ptr_eq(head.slate.as_ref().unwrap(), &shared));
        session.admission_slate(&mut branch).unwrap();
        let from = *branch.states.last().unwrap();
        let to = graph.transition(from, x).unwrap();
        session
            .shift(
                &mut branch,
                Lexeme {
                    symbol: x,
                    start: 3,
                    end: 4,
                    extra: false,
                },
                from,
                to,
                false,
            )
            .unwrap();
        assert!(branch.slate.is_none());
    }

    #[test]
    fn scanner_delimiter_memory_and_unordered_extra_inputs_stay_live() {
        let cohort = [
            "_raw_string_literal_start",
            "raw_string_literal_content",
            "_raw_string_literal_end",
        ];
        let grammar = CompiledGrammar::compile(&serde_json::to_vec(&json!({"name":"slate_raw","rules":{
            "doc":{"type":"SEQ","members":cohort.iter().map(|name|json!({"type":"SYMBOL","name":name})).collect::<Vec<_>>()}},
            "externals":cohort.iter().map(|name|json!({"type":"SYMBOL","name":name})).collect::<Vec<_>>()})).unwrap()).unwrap();
        for source in [b"r\"\"".as_slice(), b"r#\"x\\\"y\"#"] {
            assert!(compare_cached(&grammar, source));
        }
        let mut session = grammar.session();
        let ids = [4, 1, 2, 1].map(SymbolId::from_index);
        assert_eq!(
            session.slate_sorted(&ids).unwrap(),
            [1, 2, 4].map(SymbolId::from_index)
        );
    }

    #[test]
    fn hit_and_miss_refuse_before_key_or_payload_work_without_publication() {
        let grammar = CompiledGrammar::compile(CONTEXT).unwrap();
        let mut head = prefix(&grammar, &["a", "q", "r"]);
        let mut session = grammar.session();
        let slate = session.admission_slate(&mut head).unwrap();
        session.steps = 0;
        session.limits.steps = head.states.len();
        assert!(matches!(
            session.admission_slate(&mut head),
            Err(Error::LimitExceeded(Resource::Work))
        ));
        assert!(Arc::ptr_eq(head.slate.as_ref().unwrap(), &slate));
        assert_eq!(session.slate_stats.hits, 0);
        let mut other = prefix(&grammar, &["b", "q", "r"]);
        session.steps = 0;
        session.limits.steps = other.states.len() + 1;
        assert!(matches!(
            session.admission_slate(&mut other),
            Err(Error::LimitExceeded(Resource::Work))
        ));
        assert!(other.slate.is_none());
        assert_eq!(session.slate_stats.builds, 1);
    }
}
