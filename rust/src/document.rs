//! An editable file owns its parser, effect space, and immutable current version.
//! A failed edit may discard scratch work, but never publishes half a version.

use std::sync::Arc;

use crate::{
    ByteSpan, CompiledGrammar, Error, ParseLimits, ParseSession, Recovery, Supply, TreeSnapshot,
    effects::{EffectDescription, EffectError, EffectStore},
    sequence::{Segment, Sequence, SequenceCost, SequenceError},
};

#[derive(Clone, Copy, Debug, Default)]
pub struct DocumentOptions {
    pub limits: ParseLimits,
    pub recovery: Recovery,
    pub supply: Supply,
    pub policy: DocumentPolicy,
}

/// Snap uses the same exact proof as Prove. Whole is a cold baseline,
/// rebuilding measurements even for byte-equal replacements.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum DocumentPolicy {
    #[default]
    Prove,
    Snap,
    Whole,
}

/// Reusing the measured sequence and resuming the parser are separate costs.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Reuse {
    Cold,
    Prefix {
        bytes: usize,
        validated_events: usize,
    },
    Unchanged,
}

/// Work for the latest completed operation, including its proof and output.
/// These counters do not imply that an edit's total cost is logarithmic.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct DocumentCost {
    pub reuse: Reuse,
    /// Bytes copied into the new source buffer and immutable source allocation.
    pub text_bytes_copied: usize,
    /// Source bytes owned by the resulting snapshot, shared by its readers.
    pub snapshot_source_bytes: usize,
    /// All output nodes built, including a resumed tree discarded for fallback.
    pub materialized_nodes: usize,
    pub parser_work: usize,
    pub lexical_work: usize,
    pub read_events: usize,
    pub sequence_leaves: usize,
    pub sequence_height: u32,
    /// First changed leaf index, or the leaf count for an empty change window.
    pub sequence_start: usize,
    pub sequence_minted: usize,
    pub sequence_leaves_kept: usize,
    /// Spine operations; the linear leaf comparison and parser work are separate.
    pub sequence_compositions: usize,
    pub sequence_nodes_created: usize,
}

#[derive(Debug, thiserror::Error)]
pub enum DocumentError {
    #[error("edit span {span:?} exceeds the document's {source_bytes} source bytes")]
    InvalidSpan { span: ByteSpan, source_bytes: usize },
    #[error("edited source length exceeds the addressable range")]
    LengthOverflow,
    #[error(transparent)]
    Parse(#[from] Error),
    #[error(transparent)]
    Measurement(#[from] SequenceError),
}

/// One mutable document with independently retainable immutable snapshots.
/// Invalid source is represented by a diagnostic tree; operational failures
/// leave the previously published source, tree, and product intact.
pub struct Document {
    session: ParseSession,
    store: EffectStore,
    sequence: Sequence,
    snapshot: Arc<TreeSnapshot>,
    options: DocumentOptions,
    cost: DocumentCost,
}

struct MeasuredChange {
    sequence: Sequence,
    kept: usize,
    start: usize,
    minted: usize,
    work: SequenceCost,
}

impl Document {
    pub fn new(grammar: Arc<CompiledGrammar>, source: &[u8]) -> Result<Self, DocumentError> {
        Self::with_options(grammar, source, DocumentOptions::default())
    }

    pub fn with_options(
        grammar: Arc<CompiledGrammar>,
        source: &[u8],
        options: DocumentOptions,
    ) -> Result<Self, DocumentError> {
        check_length(source.len(), options.limits)?;
        let mut session = ParseSession::with_limits(Arc::clone(&grammar), options.limits);
        session.set_recovery(options.recovery);
        session.set_supply(options.supply);
        session.set_document_reuse(options.policy != DocumentPolicy::Whole);
        let mut store = grammar.effect_store();
        let parsed = session.parse_document(Arc::from(source), None, &mut store)?;
        let sequence = Sequence::from_segments(&mut store, &parsed.segments)?;
        check_coverage(&sequence, source.len())?;
        let measured = sequence.cost();
        let cost = DocumentCost {
            reuse: Reuse::Cold,
            text_bytes_copied: source.len(),
            snapshot_source_bytes: source.len(),
            materialized_nodes: parsed.stats.materialized_nodes,
            parser_work: parsed.stats.parser_work,
            lexical_work: parsed.stats.lexical_work,
            read_events: parsed.stats.token_reads,
            sequence_leaves: sequence.len(),
            sequence_height: sequence.height(),
            sequence_start: 0,
            sequence_minted: sequence.len(),
            sequence_leaves_kept: 0,
            sequence_compositions: measured.compositions,
            sequence_nodes_created: measured.nodes_created,
        };
        Ok(Self {
            session,
            store,
            sequence,
            snapshot: Arc::new(parsed.tree),
            options,
            cost,
        })
    }

    pub fn source(&self) -> &[u8] {
        self.snapshot.source()
    }

    /// Clone this Arc to keep the current version across subsequent edits.
    pub fn snapshot(&self) -> &Arc<TreeSnapshot> {
        &self.snapshot
    }

    pub fn cost(&self) -> DocumentCost {
        self.cost
    }

    pub fn set_policy(&mut self, policy: DocumentPolicy) {
        self.options.policy = policy;
        self.session
            .set_document_reuse(policy != DocumentPolicy::Whole);
    }

    /// Canonical values can be compared across documents' private intern spaces.
    pub fn product(&self) -> Result<EffectDescription, EffectError> {
        self.store.describe(self.sequence.product())
    }

    /// Replace a checked half-open byte span. Bytes need not be valid UTF-8.
    /// Only a fully parsed and measured version becomes visible to readers.
    pub fn edit(
        &mut self,
        span: ByteSpan,
        replacement: &[u8],
    ) -> Result<&TreeSnapshot, DocumentError> {
        if span.end() > self.source().len() {
            return Err(DocumentError::InvalidSpan {
                span,
                source_bytes: self.source().len(),
            });
        }
        if self.options.policy != DocumentPolicy::Whole
            && &self.source()[span.range()] == replacement
        {
            self.cost = DocumentCost {
                reuse: Reuse::Unchanged,
                text_bytes_copied: 0,
                snapshot_source_bytes: self.source().len(),
                materialized_nodes: 0,
                parser_work: 0,
                lexical_work: 0,
                read_events: 0,
                sequence_leaves: self.sequence.len(),
                sequence_height: self.sequence.height(),
                sequence_start: self.sequence.len(),
                sequence_minted: 0,
                sequence_leaves_kept: self.sequence.len(),
                sequence_compositions: 0,
                sequence_nodes_created: 0,
            };
            return Ok(&self.snapshot);
        }
        let new_len = self
            .source()
            .len()
            .checked_sub(span.end() - span.start())
            .and_then(|len| len.checked_add(replacement.len()))
            .ok_or(DocumentError::LengthOverflow)?;
        check_length(new_len, self.options.limits)?;
        let mut bytes = Vec::with_capacity(new_len);
        bytes.extend_from_slice(&self.source()[..span.start()]);
        bytes.extend_from_slice(replacement);
        bytes.extend_from_slice(&self.source()[span.end()..]);
        let parsed =
            self.session
                .parse_document(Arc::from(bytes), Some(span.start()), &mut self.store)?;
        let measured = self.splice_sequence(&parsed.segments)?;
        check_coverage(&measured.sequence, new_len)?;
        let cost = DocumentCost {
            reuse: if parsed.stats.resumed_at == 0 {
                Reuse::Cold
            } else {
                Reuse::Prefix {
                    bytes: parsed.stats.resumed_at,
                    validated_events: parsed.stats.validated_events,
                }
            },
            text_bytes_copied: new_len.saturating_mul(2),
            snapshot_source_bytes: new_len,
            materialized_nodes: parsed.stats.materialized_nodes,
            parser_work: parsed.stats.parser_work,
            lexical_work: parsed.stats.lexical_work,
            read_events: parsed.stats.token_reads,
            sequence_leaves: measured.sequence.len(),
            sequence_height: measured.sequence.height(),
            sequence_start: measured.start,
            sequence_minted: measured.minted,
            sequence_leaves_kept: measured.kept,
            sequence_compositions: measured.work.compositions,
            sequence_nodes_created: measured.work.nodes_created,
        };
        self.sequence = measured.sequence;
        self.snapshot = Arc::new(parsed.tree);
        self.cost = cost;
        Ok(&self.snapshot)
    }

    fn splice_sequence(&mut self, segments: &[Segment]) -> Result<MeasuredChange, SequenceError> {
        if self.options.policy == DocumentPolicy::Whole {
            let sequence = Sequence::from_segments(&mut self.store, segments)?;
            return Ok(MeasuredChange {
                work: sequence.cost(),
                sequence,
                kept: 0,
                start: 0,
                minted: segments.len(),
            });
        }
        let prefix = self
            .sequence
            .iter()
            .zip(segments)
            .take_while(|(old, new)| old == *new)
            .count();
        let suffix = self
            .sequence
            .iter()
            .rev()
            .zip(segments.iter().rev())
            .take(self.sequence.len().min(segments.len()) - prefix)
            .take_while(|(old, new)| old == *new)
            .count();
        if prefix == self.sequence.len() && prefix == segments.len() {
            return Ok(MeasuredChange {
                sequence: self.sequence.clone(),
                kept: prefix,
                start: prefix,
                minted: 0,
                work: SequenceCost {
                    compositions: 0,
                    nodes_created: 0,
                },
            });
        }
        let sequence = self.sequence.splice(
            prefix..self.sequence.len() - suffix,
            &segments[prefix..segments.len() - suffix],
            &mut self.store,
        )?;
        Ok(MeasuredChange {
            work: sequence.cost(),
            sequence,
            kept: prefix + suffix,
            start: prefix,
            minted: segments.len() - prefix - suffix,
        })
    }
}

fn check_length(actual: usize, limits: ParseLimits) -> Result<(), Error> {
    let limit = limits.source_bytes.min(u32::MAX as usize);
    if actual > limit {
        Err(Error::SourceTooLarge { actual, limit })
    } else {
        Ok(())
    }
}

fn check_coverage(sequence: &Sequence, source_bytes: usize) -> Result<(), Error> {
    if sequence.byte_len() == source_bytes {
        Ok(())
    } else {
        Err(Error::InvalidTable("document effects do not cover source"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn grammar() -> Arc<CompiledGrammar> {
        CompiledGrammar::compile(include_bytes!("../../test/grammar/json.json")).unwrap()
    }

    #[test]
    fn invalid_edits_and_size_refusals_preserve_the_published_version() {
        let mut document = Document::with_options(
            grammar(),
            b"[1]",
            DocumentOptions {
                limits: ParseLimits {
                    source_bytes: 5,
                    ..ParseLimits::default()
                },
                ..DocumentOptions::default()
            },
        )
        .unwrap();
        let snapshot = Arc::clone(document.snapshot());
        let product = document.product().unwrap();
        let cost = document.cost();
        assert!(matches!(
            document.edit(ByteSpan::new(2, 4).unwrap(), b""),
            Err(DocumentError::InvalidSpan { .. })
        ));
        assert!(matches!(
            document.edit(ByteSpan::new(1, 2).unwrap(), b"123456"),
            Err(DocumentError::Parse(Error::SourceTooLarge { .. }))
        ));
        assert!(Arc::ptr_eq(&snapshot, document.snapshot()));
        assert_eq!(document.source(), b"[1]");
        assert_eq!(document.product().unwrap(), product);
        assert_eq!(document.cost(), cost);
    }

    #[test]
    fn byte_equal_edits_keep_the_snapshot_and_do_no_parser_or_sequence_work() {
        let mut document = Document::new(grammar(), b"[1]").unwrap();
        let snapshot = Arc::clone(document.snapshot());
        document.edit(ByteSpan::new(1, 2).unwrap(), b"1").unwrap();
        assert!(Arc::ptr_eq(&snapshot, document.snapshot()));
        assert_eq!(document.cost().reuse, Reuse::Unchanged);
        assert_eq!(document.cost().text_bytes_copied, 0);
        assert_eq!(document.cost().parser_work, 0);
        assert_eq!(document.cost().sequence_compositions, 0);
    }

    #[test]
    fn policies_keep_the_same_results_and_whole_is_an_executed_cold_baseline() {
        let grammar = grammar();
        let mut documents: Vec<_> = [
            DocumentPolicy::Prove,
            DocumentPolicy::Snap,
            DocumentPolicy::Whole,
        ]
        .into_iter()
        .map(|policy| {
            Document::with_options(
                Arc::clone(&grammar),
                b"[1,2,3]",
                DocumentOptions {
                    policy,
                    ..DocumentOptions::default()
                },
            )
            .unwrap()
        })
        .collect();
        for (span, replacement) in [
            (ByteSpan::new(3, 4).unwrap(), b"4".as_slice()),
            (ByteSpan::new(3, 4).unwrap(), b"4".as_slice()),
        ] {
            let previous = Arc::clone(documents[2].snapshot());
            for document in &mut documents {
                document.edit(span, replacement).unwrap();
            }
            let product = documents[0].product().unwrap();
            for document in &documents {
                assert_eq!(document.source(), b"[1,4,3]");
                assert_eq!(document.product().unwrap(), product);
                assert!(document.snapshot().confidence().is_strict());
            }
            let baseline = documents[2].cost();
            assert_eq!(baseline.reuse, Reuse::Cold);
            assert_eq!(baseline.sequence_leaves_kept, 0);
            assert_eq!(baseline.sequence_minted, baseline.sequence_leaves);
            assert!(baseline.read_events > 0);
            assert!(!Arc::ptr_eq(&previous, documents[2].snapshot()));
        }
        assert_eq!(documents[0].cost().reuse, Reuse::Unchanged);
        assert_eq!(documents[1].cost().reuse, Reuse::Unchanged);
        documents[2].set_policy(DocumentPolicy::Prove);
        documents[2]
            .edit(ByteSpan::new(3, 4).unwrap(), b"4")
            .unwrap();
        assert_eq!(documents[2].cost().reuse, Reuse::Unchanged);
    }

    #[test]
    fn an_interrupted_parse_keeps_old_snapshots_and_allows_the_next_edit() {
        let mut document = Document::with_options(
            grammar(),
            b"[1]",
            DocumentOptions {
                limits: ParseLimits {
                    nodes: 32,
                    ..ParseLimits::default()
                },
                ..DocumentOptions::default()
            },
        )
        .unwrap();
        let old = Arc::clone(document.snapshot());
        let product = document.product().unwrap();
        let too_many_nodes = format!("[{}]", vec!["0"; 100].join(","));
        assert!(matches!(
            document.edit(ByteSpan::new(0, 3).unwrap(), too_many_nodes.as_bytes()),
            Err(DocumentError::Parse(Error::LimitExceeded(
                crate::Resource::Nodes
            )))
        ));
        assert!(Arc::ptr_eq(&old, document.snapshot()));
        assert_eq!(document.product().unwrap(), product);
        document.edit(ByteSpan::new(1, 2).unwrap(), b"2").unwrap();
        assert_eq!(old.source(), b"[1]");
        assert_eq!(old.root().unwrap().text(), b"[1]");
        assert_eq!(document.source(), b"[2]");
        assert!(document.snapshot().confidence().is_strict());
    }
}
