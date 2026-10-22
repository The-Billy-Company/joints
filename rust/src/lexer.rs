//! State-directed token selection over irgx's anchored lexer slates.

use crate::compiler::{Automaton, Lexis, Pattern};
use crate::ids::SymbolId;
use crate::scanner::ScannerProgram;
use irgx::{Munch, Pick};
use thiserror::Error;

mod recipe;

#[cfg(all(test, feature = "munch-image"))]
pub(crate) mod working_image_trial;

#[derive(Clone, Copy, Debug)]
pub struct LexerLimits {
    pub pattern_bytes: usize,
    pub scan_transitions: usize,
}
impl Default for LexerLimits {
    fn default() -> Self {
        Self {
            pattern_bytes: 1 << 20,
            scan_transitions: 1 << 20,
        }
    }
}

#[derive(Debug, Error)]
pub enum LexError {
    #[error("context-free lexical walk exceeds its {limit} token limit")]
    TokenLimit { limit: usize },
    #[error("lexical patterns exceed the {limit} byte limit")]
    PatternLimit { limit: usize },
    #[error("lexical transition budget exhausted at byte {at}")]
    WorkLimit { at: usize },
    #[error("ordinary empty-token selection work exhausted at byte {at}")]
    QuestionWork { at: usize },
    #[error("literal token {symbol:?} is not valid UTF-8")]
    LiteralEncoding { symbol: SymbolId },
    #[error("cannot compile lexical automaton: {0}")]
    Build(String),
    #[error("cannot allocate lexical {0}")]
    Allocation(&'static str),
    #[error("source offset {at} exceeds {len} bytes")]
    Offset { at: usize, len: usize },
    #[error("lexical automaton cannot inspect the source at {at}: {reason}")]
    Search { at: usize, reason: String },
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Lexeme {
    pub symbol: SymbolId,
    pub start: usize,
    pub end: usize,
    /// An explicit parser admission makes an extra structural at this site.
    pub extra: bool,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Scan {
    Token(Lexeme),
    End,
    Stray { at: usize },
}

/// Positive, proved-empty, and provisionally-empty ordinary roles are distinct.
/// Provisional empty winners must execute the parser before committing. Raw
/// diagnostic rows and donated extra FIRSTs never gain either empty role.
#[derive(Clone, Copy)]
pub(crate) struct LexicalQuestion<'a> {
    pub admitted: Option<&'a [SymbolId]>,
    pub empty_permit: &'a [SymbolId],
    /// Ordinary regex candidates that still require actual parser viability.
    pub provisional_empty: &'a [SymbolId],
    pub eof: bool,
}
pub(crate) struct ScanBudget<'a> {
    /// Native DFA transition units retain their existing independent meaning.
    pub transitions: &'a mut usize,
    /// New ordinary empty-token election visits use the parser work budget.
    pub selection: &'a mut usize,
}
/// Worker-owned ordinal buffers. They carry no lexical answers between calls;
/// the native scan clears and replaces the winners for every question.
#[derive(Default)]
pub(crate) struct ScanScratch {
    allow: Vec<u32>,
    winners: Vec<u32>,
}
impl<'a> LexicalQuestion<'a> {
    pub(crate) fn positive(admitted: Option<&'a [SymbolId]>) -> Self {
        Self {
            admitted,
            empty_permit: &[],
            provisional_empty: &[],
            eof: true,
        }
    }
}

#[derive(Clone, Copy, Debug)]
pub struct LexicalWalkLimits {
    pub source_bytes: usize,
    pub tokens: usize,
    pub work: usize,
}
impl Default for LexicalWalkLimits {
    fn default() -> Self {
        let p = crate::ParseLimits::default();
        Self {
            source_bytes: p.source_bytes,
            tokens: p.nodes,
            work: p.lexical_steps,
        }
    }
}
/// Context-free DFA output. Stateful scanner hands require parser admissions
/// and are deliberately not invoked. Extras are skipped, not emitted.
#[derive(Debug)]
pub struct LexicalWalk {
    pub tokens: Vec<Lexeme>,
    pub stray: Option<usize>,
    pub covered: usize,
    pub skipped: usize,
    pub work: usize,
}
impl crate::CompiledGrammar {
    pub fn lexical_walk(
        &self,
        source: &[u8],
        finite_work: usize,
    ) -> Result<LexicalWalk, crate::Error> {
        self.lexical_walk_with_limits(
            source,
            LexicalWalkLimits {
                work: finite_work,
                ..LexicalWalkLimits::default()
            },
        )
    }
    pub fn lexical_walk_with_limits(
        &self,
        source: &[u8],
        limits: LexicalWalkLimits,
    ) -> Result<LexicalWalk, crate::Error> {
        let max = limits.source_bytes.min(u32::MAX as usize);
        if source.len() > max {
            return Err(crate::Error::SourceTooLarge {
                actual: source.len(),
                limit: max,
            });
        }
        let mut remaining = limits.work;
        let mut selection = usize::MAX;
        let mut scratch = ScanScratch::default();
        let mut at = 0;
        let mut fresh = true;
        let mut result = LexicalWalk {
            tokens: Vec::new(),
            stray: None,
            covered: 0,
            skipped: 0,
            work: 0,
        };
        loop {
            match self.lexer.scan(
                source,
                at,
                LexicalQuestion::positive(None),
                fresh,
                ScanBudget {
                    transitions: &mut remaining,
                    selection: &mut selection,
                },
                Pick::Longest,
                &mut scratch,
            )? {
                Scan::End => break,
                Scan::Stray { at } => {
                    result.stray = Some(at);
                    break;
                }
                Scan::Token(token) => {
                    if token.extra {
                        result.skipped += token.end - token.start;
                        fresh = false;
                    } else {
                        if result.tokens.len() >= limits.tokens {
                            return Err(LexError::TokenLimit {
                                limit: limits.tokens,
                            }
                            .into());
                        }
                        result.covered += token.end - token.start;
                        result.tokens.push(token);
                        fresh = true;
                    }
                    at = token.end;
                }
            }
        }
        result.work = limits.work - remaining;
        Ok(result)
    }
}

#[derive(Debug)]
struct Entry {
    symbol: SymbolId,
    order: u32,
    immediate: bool,
    literal: bool,
    provided: bool,
    external: bool,
    extra: bool,
}
#[derive(Debug)]
struct Tier {
    #[cfg(all(test, feature = "munch-image"))]
    precedence: i32,
    slate: Munch,
    entries: Vec<Entry>,
}

#[derive(Clone, Copy)]
struct Choice {
    token: Lexeme,
    standing: u8,
    order: u32,
}
impl Choice {
    fn outranks(self, other: Self) -> bool {
        self.standing > other.standing
            || (self.standing == other.standing && self.order < other.order)
    }
    fn elect(slot: &mut Option<Self>, candidate: Self) {
        if slot.is_none_or(|old| candidate.outranks(old)) {
            *slot = Some(candidate);
        }
    }
}

/// Each lexical precedence tier owns one immutable attributed slate. A worker
/// leases native scratch through irgx's safe pool; no mutable handle is shared.
#[derive(Debug)]
pub struct Lexer {
    tiers: Vec<Tier>,
    word: Option<SymbolId>,
    scan_transitions: usize,
}
impl Lexer {
    #[cfg(test)]
    pub fn compile(grammar: &Automaton, limits: LexerLimits) -> Result<Self, LexError> {
        Self::compile_with_program(grammar, None, limits)
    }
    pub(crate) fn compile_with_program(
        grammar: &Automaton,
        program: Option<&ScannerProgram>,
        limits: LexerLimits,
    ) -> Result<Self, LexError> {
        let recipe = recipe::Recipe::new(grammar, program);
        Self::build_source(
            |budget| {
                // lexical_rules filters all symbols, including non-lexical ones.
                recipe::Budget::work(budget, recipe.symbol_visits())?;
                Ok(recipe.rules())
            },
            grammar.extras(),
            grammar.word(),
            limits,
        )
    }
    #[cfg(test)]
    fn rules<'a>(
        rules: impl Iterator<Item = (SymbolId, &'a Lexis)>,
        extras: &[SymbolId],
        word: Option<SymbolId>,
        limits: LexerLimits,
    ) -> Result<Self, LexError> {
        let rules = rules
            .map(|(id, rule)| (id, rule, false, false))
            .collect::<Vec<_>>();
        Self::build_source(|_| Ok(rules.iter().copied()), extras, word, limits)
    }
    #[cfg(test)]
    fn build<'a>(
        rules: impl Iterator<Item = recipe::Rule<'a>>,
        extras: &[SymbolId],
        word: Option<SymbolId>,
        limits: LexerLimits,
    ) -> Result<Self, LexError> {
        let rules = rules.collect::<Vec<_>>();
        Self::build_source(|_| Ok(rules.iter().copied()), extras, word, limits)
    }
    fn build_source<'a, I>(
        rules: impl Fn(&mut recipe::Source) -> Result<I, LexError>,
        extras: &[SymbolId],
        word: Option<SymbolId>,
        limits: LexerLimits,
    ) -> Result<Self, LexError>
    where
        I: Iterator<Item = recipe::Rule<'a>>,
    {
        recipe::assemble(
            rules,
            extras,
            word,
            limits,
            &mut recipe::Source,
            |patterns, entries, _| {
                let slate = Munch::new(&patterns).map_err(|e| LexError::Build(e.to_string()))?;
                if !slate.declined().is_empty() {
                    let reasons: Vec<_> = slate
                        .declined()
                        .iter()
                        .map(|r| format!("{:?}: {:?}", entries[r.pattern].symbol, r.why))
                        .collect();
                    return Err(LexError::Build(format!(
                        "refused token patterns: {}",
                        reasons.join(", ")
                    )));
                }
                Ok(slate)
            },
        )
    }
    pub(crate) fn load_with_program(
        grammar: &Automaton,
        program: Option<&ScannerProgram>,
        limits: LexerLimits,
        session: &mut crate::artifact::ImageSession<'_, '_, '_>,
    ) -> Result<Self, crate::artifact::ArtifactError> {
        let recipe = recipe::Recipe::new(grammar, program);
        recipe::assemble(
            |budget| {
                // lexical_rules filters all symbols, including non-lexical ones.
                recipe::Budget::work(budget, recipe.symbol_visits())?;
                Ok(recipe.rules())
            },
            grammar.extras(),
            grammar.word(),
            limits,
            session,
            |patterns, _, session| {
                let builder = irgx::MunchBuilder::from_owned(patterns);
                let frame = session.frame()?;
                let slate = session.load(&builder, frame)?;
                if !slate.declined().is_empty() {
                    return Err(crate::artifact::ArtifactError::Invalid(
                        "lexical image has declined patterns",
                    ));
                }
                Ok(slate)
            },
        )
    }
    pub(crate) fn write_images(
        &self,
        writer: &mut crate::artifact::Writer,
        operation: &mut crate::artifact::ImageOperation,
    ) -> Result<(), crate::artifact::ArtifactError> {
        writer.image_count(self.tiers.len(), operation)?;
        for tier in &self.tiers {
            operation.charge_work(1)?;
            let image = operation.save(&tier.slate)?;
            writer.image(image.as_bytes(), operation)?;
        }
        Ok(())
    }
    #[cfg(test)]
    pub fn scan_at(
        &self,
        source: &[u8],
        at: usize,
        admitted: &[SymbolId],
        fresh: bool,
    ) -> Result<Scan, LexError> {
        let mut budget = self.scan_transitions;
        self.scan_with_budget(source, at, admitted, fresh, &mut budget)
    }
    #[cfg(test)]
    pub(crate) fn scan_with_budget(
        &self,
        source: &[u8],
        at: usize,
        admitted: &[SymbolId],
        fresh: bool,
        remaining: &mut usize,
    ) -> Result<Scan, LexError> {
        let mut selection = usize::MAX;
        self.scan_question(
            source,
            at,
            LexicalQuestion::positive(Some(admitted)),
            fresh,
            ScanBudget {
                transitions: remaining,
                selection: &mut selection,
            },
        )
    }
    #[cfg(test)]
    pub(crate) fn scan_question(
        &self,
        source: &[u8],
        at: usize,
        question: LexicalQuestion<'_>,
        fresh: bool,
        budget: ScanBudget<'_>,
    ) -> Result<Scan, LexError> {
        self.scan_question_with_scratch(
            source,
            at,
            question,
            fresh,
            budget,
            &mut ScanScratch::default(),
        )
    }
    pub(crate) fn scan_question_with_scratch(
        &self,
        source: &[u8],
        at: usize,
        question: LexicalQuestion<'_>,
        fresh: bool,
        budget: ScanBudget<'_>,
        scratch: &mut ScanScratch,
    ) -> Result<Scan, LexError> {
        self.scan(source, at, question, fresh, budget, Pick::Longest, scratch)
    }
    #[cfg(test)]
    pub(crate) fn spot_with_budget(
        &self,
        source: &[u8],
        at: usize,
        fresh: bool,
        remaining: &mut usize,
    ) -> Result<Scan, LexError> {
        self.spot_with_scratch(source, at, fresh, remaining, &mut ScanScratch::default())
    }
    pub(crate) fn spot_with_scratch(
        &self,
        source: &[u8],
        at: usize,
        fresh: bool,
        remaining: &mut usize,
        scratch: &mut ScanScratch,
    ) -> Result<Scan, LexError> {
        let mut selection = usize::MAX;
        self.scan(
            source,
            at,
            LexicalQuestion::positive(None),
            fresh,
            ScanBudget {
                transitions: remaining,
                selection: &mut selection,
            },
            Pick::Shortest,
            scratch,
        )
    }
    #[allow(clippy::too_many_arguments)]
    fn scan(
        &self,
        source: &[u8],
        at: usize,
        question: LexicalQuestion<'_>,
        fresh: bool,
        work: ScanBudget<'_>,
        pick: Pick,
        scratch: &mut ScanScratch,
    ) -> Result<Scan, LexError> {
        if at > source.len() {
            return Err(LexError::Offset {
                at,
                len: source.len(),
            });
        }
        if source.is_empty()
            || (at == source.len()
                && (question.eof
                    || (question.empty_permit.is_empty() && question.provisional_empty.is_empty())))
        {
            return Ok(Scan::End);
        }
        let admitted = question.admitted;
        let permits_empty = |entry: &Entry| {
            !entry.provided
                && !entry.external
                && !entry.literal
                && admitted.is_some_and(|set| set.contains(&entry.symbol))
                && (question.empty_permit.binary_search(&entry.symbol).is_ok()
                    || question
                        .provisional_empty
                        .binary_search(&entry.symbol)
                        .is_ok())
        };
        let remaining = work.transitions;
        let allowance = self.scan_transitions.min(*remaining);
        let mut budget = allowance;
        let mut best_length = None;
        let mut plain = None;
        let mut keyword = None;
        let ScanScratch { allow, winners } = scratch;
        for tier in &self.tiers {
            allow.clear();
            allow.extend(
                tier.entries
                    .iter()
                    .enumerate()
                    .filter(|(_, entry)| {
                        let named = admitted.is_some_and(|set| set.contains(&entry.symbol));
                        (admitted.is_none() || entry.extra || named) && (!entry.immediate || fresh)
                    })
                    .map(|(i, _)| i as u32),
            );
            if allow.is_empty() {
                continue;
            }
            #[cfg(all(test, feature = "munch-image"))]
            let observed = working_image_trial::native_before(
                &tier.slate,
                source,
                at,
                Some(allow),
                pick,
                fresh,
                question,
                budget,
                *work.selection,
            );
            let result = tier.slate.scan_bytes_metered_into(
                source,
                at,
                Some(allow),
                pick,
                &mut budget,
                winners,
            );
            #[cfg(all(test, feature = "munch-image"))]
            working_image_trial::native_after(observed, &result, winners, budget, *work.selection);
            // Reconcile consumption even on failure. A refused scan has no winner.
            let used = allowance - budget;
            if let Err(error) = result {
                *remaining -= used;
                return Err(if budget == 0 {
                    LexError::WorkLimit { at }
                } else {
                    LexError::Search {
                        at,
                        reason: error.to_string(),
                    }
                });
            }
            let Some(len) = result.unwrap() else {
                continue;
            };
            if len == 0 {
                if question.empty_permit.is_empty() && question.provisional_empty.is_empty() {
                    continue;
                }
                // Both passes below may examine every winner, including
                // donated/automatic/provided entries with no empty role.
                // Prepay their membership comparisons before reading them.
                let search = |len: usize| {
                    if len == 0 {
                        0
                    } else {
                        (usize::BITS - (len - 1).leading_zeros() + 1) as usize
                    }
                };
                let search = search(question.empty_permit.len())
                    .saturating_add(search(question.provisional_empty.len()));
                let cost = winners.len().saturating_mul(2).saturating_mul(
                    2usize
                        .saturating_add(admitted.map_or(0, <[SymbolId]>::len))
                        .saturating_add(search),
                );
                let Some(left) = work.selection.checked_sub(cost) else {
                    *work.selection = 0;
                    *remaining -= used;
                    return Err(LexError::QuestionWork { at });
                };
                *work.selection = left;
                let mut permitted = false;
                for &index in winners.iter() {
                    let Some(entry) = tier.entries.get(index as usize) else {
                        *remaining -= used;
                        return Err(LexError::Search {
                            at,
                            reason: "native token has an invalid pattern ordinal".into(),
                        });
                    };
                    permitted |= permits_empty(entry);
                }
                if !permitted {
                    continue;
                }
            }
            if len > source.len() - at {
                *remaining -= used;
                return Err(LexError::Search {
                    at,
                    reason: "native token exceeds source".into(),
                });
            }
            if best_length.is_none_or(|old| len < old) {
                best_length = Some(len);
                plain = None;
                keyword = None;
            } else if best_length != Some(len) {
                continue;
            }
            for &index in winners.iter() {
                let Some(entry) = tier.entries.get(index as usize) else {
                    *remaining -= used;
                    return Err(LexError::Search {
                        at,
                        reason: "native token has an invalid pattern ordinal".into(),
                    });
                };
                if len == 0 && !permits_empty(entry) {
                    continue;
                }
                let extra = entry.extra && !admitted.is_some_and(|set| set.contains(&entry.symbol));
                let standing = if extra {
                    0
                } else {
                    (if entry.provided {
                        1
                    } else if entry.literal {
                        5
                    } else {
                        3
                    }) + u8::from(entry.immediate)
                };
                let candidate = Choice {
                    token: Lexeme {
                        symbol: entry.symbol,
                        start: at,
                        end: at + len,
                        extra,
                    },
                    standing,
                    order: entry.order,
                };
                Choice::elect(&mut plain, candidate);
                if Some(entry.symbol) != self.word && !entry.provided {
                    Choice::elect(&mut keyword, candidate);
                }
            }
            if pick == Pick::Longest {
                break;
            }
        }
        *remaining -= allowance - budget;
        let Some(mut selected) = plain else {
            return Ok(if at == source.len() {
                Scan::End
            } else {
                Scan::Stray { at }
            });
        };
        if Some(selected.token.symbol) == self.word {
            selected = keyword.unwrap_or(selected);
        }
        Ok(Scan::Token(selected.token))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reused_ordinal_buffers_preserve_questions_failures_and_exact_work() {
        let lexer = program(
            &[rx("[a-z]+", 0), lit("if", 1), rx("[ ]+", 2), rx("a*", 3)],
            &[2],
            Some(0),
        );
        let ids: Vec<_> = (0..4).map(SymbolId::from_index).collect();
        let mut scratch = ScanScratch::default();
        // Warm both ordinal buffers to this slate's maximum size. Following
        // questions must overwrite their contents without reallocating them.
        lexer
            .scan(
                b"if",
                0,
                LexicalQuestion::positive(Some(&ids)),
                true,
                ScanBudget {
                    transitions: &mut 1000,
                    selection: &mut 1000,
                },
                Pick::Longest,
                &mut scratch,
            )
            .unwrap();
        let storage = (
            scratch.allow.as_ptr(),
            scratch.allow.capacity(),
            scratch.winners.as_ptr(),
            scratch.winners.capacity(),
        );
        for _ in 0..3 {
            for (source, at, admitted, empty, pick, transitions, selection) in [
                (&b"if"[..], 0, &ids[..], &[][..], Pick::Longest, 1000, 1000),
                (&b"if"[..], 0, &ids[..1], &[][..], Pick::Longest, 1000, 1000),
                (&b" "[..], 0, &ids[..1], &[][..], Pick::Longest, 1000, 1000),
                (&b"!"[..], 0, &ids[..], &ids[3..], Pick::Longest, 1000, 1000),
                (&b"!"[..], 0, &ids[..], &ids[3..], Pick::Longest, 1000, 0),
                (&b"if"[..], 0, &ids[..], &[][..], Pick::Longest, 0, 1000),
                (&b"if"[..], 0, &ids[..], &[][..], Pick::Shortest, 1000, 1000),
                (&b"if"[..], 3, &ids[..], &[][..], Pick::Longest, 1000, 1000),
                (&b"if"[..], 2, &ids[..], &[][..], Pick::Longest, 1000, 1000),
            ] {
                let mut reused_work = (transitions, selection);
                let mut fresh_work = reused_work;
                let question = LexicalQuestion {
                    admitted: Some(admitted),
                    empty_permit: empty,
                    provisional_empty: &[],
                    eof: true,
                };
                let reused = lexer
                    .scan(
                        source,
                        at,
                        question,
                        true,
                        ScanBudget {
                            transitions: &mut reused_work.0,
                            selection: &mut reused_work.1,
                        },
                        pick,
                        &mut scratch,
                    )
                    .map_err(|e| e.to_string());
                let fresh = lexer
                    .scan(
                        source,
                        at,
                        question,
                        true,
                        ScanBudget {
                            transitions: &mut fresh_work.0,
                            selection: &mut fresh_work.1,
                        },
                        pick,
                        &mut ScanScratch::default(),
                    )
                    .map_err(|e| e.to_string());
                assert_eq!(reused, fresh);
                assert_eq!(reused_work, fresh_work);
                assert_eq!(
                    (
                        scratch.allow.as_ptr(),
                        scratch.allow.capacity(),
                        scratch.winners.as_ptr(),
                        scratch.winners.capacity(),
                    ),
                    storage
                );
            }
        }
    }

    #[test]
    fn context_free_walk_skips_extras_preserves_immediacy_and_refuses_finite_caps() {
        let grammar=crate::CompiledGrammar::compile(br#"{"rules":{"doc":{"type":"REPEAT1","content":{"type":"CHOICE","members":[{"type":"STRING","value":"x"},{"type":"IMMEDIATE_TOKEN","content":{"type":"STRING","value":"x"}}]}}},"extras":[{"type":"PATTERN","value":"[ ]+"}]}"#).unwrap();
        let immediate = grammar
            .lexical_rules()
            .find(|(_, l)| l.immediate)
            .unwrap()
            .0;
        let walk = grammar.lexical_walk(b"x x", 10000).unwrap();
        assert_eq!(
            (walk.tokens.len(), walk.covered, walk.skipped, walk.stray),
            (2, 2, 1, None)
        );
        assert_eq!(walk.tokens[0].symbol, immediate);
        assert_ne!(walk.tokens[1].symbol, immediate);
        assert_eq!((walk.tokens[1].start, walk.tokens[1].end), (2, 3));
        assert!(walk.work > 0);
        assert!(matches!(
            grammar.lexical_walk(b"x", 0),
            Err(crate::Error::Lex(LexError::WorkLimit { .. }))
        ));
        assert!(matches!(
            grammar.lexical_walk_with_limits(
                b"x",
                LexicalWalkLimits {
                    tokens: 0,
                    ..LexicalWalkLimits::default()
                }
            ),
            Err(crate::Error::Lex(LexError::TokenLimit { limit: 0 }))
        ));
        assert!(matches!(
            grammar.lexical_walk_with_limits(
                b"x",
                LexicalWalkLimits {
                    source_bytes: 0,
                    ..LexicalWalkLimits::default()
                }
            ),
            Err(crate::Error::SourceTooLarge { .. })
        ));
        assert!(grammar.lexical_walk(b"", 0).unwrap().tokens.is_empty());
    }
    #[test]
    fn context_free_walk_does_not_invent_scanner_permissions_or_a_parser_stream() {
        let source=br#"{"externals":[{"type":"SYMBOL","name":"answer"}],"rules":{"doc":{"type":"SYMBOL","name":"answer"}}}"#;
        let book=br#"{"cohort":["answer"],"probes":{"body":"x+"},"rules":[{"phase":"bounded","when":[["wanted","answer"],["probe","body"]],"then":[["emit","answer"]]}]}"#;
        let grammar = crate::CompiledGrammar::compile_with_customary(
            source,
            book,
            crate::CompileOptions::default(),
        )
        .unwrap();
        grammar.session().parse(b"xxx").unwrap();
        let walk = grammar.lexical_walk(b"xxx", 10000).unwrap();
        assert!(walk.tokens.is_empty());
        assert_eq!(walk.stray, Some(0));
        let json = crate::CompiledGrammar::compile(include_bytes!("../../test/grammar/json.json"))
            .unwrap();
        json.session().parse(b"[1,2]").unwrap();
        let slate = json.lexical_walk(b"[1,2]", 10000).unwrap();
        assert!(
            slate.tokens[0].end - slate.tokens[0].start > 1,
            "contextual body pattern should demonstrate why ungated output is not a parser stream"
        );
    }

    fn spec(pattern: Pattern, immediate: bool, precedence: i32, order: u32) -> Lexis {
        Lexis {
            pattern,
            immediate,
            precedence,
            declaration_order: order,
        }
    }

    fn program(rules: &[Lexis], extras: &[usize], word: Option<usize>) -> Lexer {
        Lexer::rules(
            rules
                .iter()
                .enumerate()
                .map(|(i, r)| (SymbolId::from_index(i), r)),
            &extras
                .iter()
                .copied()
                .map(SymbolId::from_index)
                .collect::<Vec<_>>(),
            word.map(SymbolId::from_index),
            LexerLimits::default(),
        )
        .unwrap()
    }

    fn rx(text: &str, order: u32) -> Lexis {
        spec(Pattern::Regex(text.into()), false, 0, order)
    }

    fn lit(text: &str, order: u32) -> Lexis {
        spec(Pattern::Literal(text.as_bytes().to_vec()), false, 0, order)
    }

    fn token(lexer: &Lexer, source: &[u8], admitted: &[usize], fresh: bool) -> Lexeme {
        let admitted = admitted
            .iter()
            .copied()
            .map(SymbolId::from_index)
            .collect::<Vec<_>>();
        match lexer.scan_at(source, 0, &admitted, fresh).unwrap() {
            Scan::Token(token) => token,
            other => panic!("expected token, got {other:?}"),
        }
    }

    #[test]
    fn eligibility_preserves_an_earlier_shorter_match() {
        let lexer = program(&[rx("[a-z]+", 0), rx("[a-z]+:[a-z]+", 1)], &[], None);
        let hit = token(&lexer, b"abc:def", &[0], true);
        assert_eq!((hit.symbol.index(), hit.end), (0, 3));
        assert_eq!(token(&lexer, b"abc:def", &[0, 1], true).end, 7);
    }

    #[test]
    fn precedence_outranks_length_and_retains_shorter_endpoints() {
        let mut short = lit("a", 1);
        short.precedence = 2;
        let lexer = program(&[rx("[a-z]+", 0), short], &[], None);
        assert_eq!(token(&lexer, b"alphabet", &[0, 1], true).symbol.index(), 1);
        assert_eq!(token(&lexer, b"alphabet", &[0, 1], true).end, 1);
    }

    #[test]
    fn json_permissions_and_string_content_prevent_comment_theft() {
        let mut body = rx(r#"[^\\"\n]+"#, 1);
        body.precedence = 1;
        body.immediate = true;
        let lexer = program(&[lit(":", 0), body, rx("//[^\\n]*", 2)], &[2], None);
        assert_eq!(token(&lexer, b": [1,true]", &[0], true).end, 1);
        let hit = token(&lexer, b"//", &[1], true);
        assert_eq!((hit.symbol.index(), hit.extra), (1, false));
        assert_eq!(token(&lexer, b"//", &[], true).symbol.index(), 2);
    }

    #[test]
    fn literal_then_immediacy_then_declaration_resolves_ties() {
        let mut immediate = lit("if", 2);
        immediate.immediate = true;
        let lexer = program(&[rx("[a-z]+", 0), lit("if", 1), immediate], &[], None);
        assert_eq!(token(&lexer, b"if", &[0, 1, 2], true).symbol.index(), 2);
        assert_eq!(token(&lexer, b"if", &[0, 1, 2], false).symbol.index(), 1);
        assert_eq!(token(&lexer, b"iff", &[0, 1, 2], true).symbol.index(), 0);
        let lexer = program(&[rx("if", 2), rx("if", 1)], &[], None);
        assert_eq!(token(&lexer, b"if", &[0, 1], true).symbol.index(), 1);
    }

    #[test]
    fn keyword_pattern_overrides_word_only_at_the_same_length() {
        let lexer = program(&[rx("[a-z]+", 0), rx("int|long", 1)], &[], Some(0));
        assert_eq!(token(&lexer, b"int", &[0, 1], true).symbol.index(), 1);
        assert_eq!(token(&lexer, b"integer", &[0, 1], true).symbol.index(), 0);
    }

    #[test]
    fn scoped_flags_keep_their_own_token_semantics() {
        let lexer = program(
            &[rx("(?i:abc)", 0), rx("(?s:a.b)", 1), lit("ABC", 2)],
            &[],
            None,
        );
        assert_eq!(token(&lexer, b"AbC", &[0], true).end, 3);
        assert_eq!(token(&lexer, b"a\nb", &[1], true).end, 3);
        assert_eq!(token(&lexer, b"ABC", &[0, 2], true).symbol.index(), 2);
    }

    #[test]
    fn extras_are_tokens_with_contextual_roles() {
        let lexer = program(
            &[rx(r"\s", 0), rx(r"\r?\n", 1), rx("[a-z]+", 2)],
            &[0, 1],
            None,
        );
        let hit = token(&lexer, b"\n", &[1, 2], true);
        assert_eq!((hit.symbol.index(), hit.extra), (1, false));
        assert!(token(&lexer, b" ", &[2], true).extra);
        assert!(token(&lexer, b"\n", &[2], true).extra);
    }

    #[test]
    fn positive_only_questions_never_return_zero_width_tokens() {
        let lexer = program(&[rx("a*", 0)], &[], None);
        assert_eq!(token(&lexer, b"aaa!", &[0], true).end, 3);
        assert_eq!(
            lexer
                .scan_at(b"!", 0, &[SymbolId::from_index(0)], true)
                .unwrap(),
            Scan::Stray { at: 0 }
        );
        assert_eq!(lexer.scan_at(b"", 0, &[], true).unwrap(), Scan::End);
    }

    #[test]
    fn ordinary_empty_tokens_need_a_structural_role_and_a_separate_work_budget() {
        let rules = [rx("a*", 0), rx("a*", 1), rx("a*", 2), lit("", 3)];
        let lexer = Lexer::build(
            rules
                .iter()
                .enumerate()
                .map(|(i, r)| (SymbolId::from_index(i), r, i == 1, i == 2)),
            &[SymbolId::from_index(0)],
            None,
            LexerLimits::default(),
        )
        .unwrap();
        let ids: Vec<_> = (0..4).map(SymbolId::from_index).collect();
        let ask = |source: &[u8], empty: &[SymbolId], eof, selection: &mut usize| {
            lexer.scan_question(
                source,
                0,
                LexicalQuestion {
                    admitted: Some(&ids),
                    empty_permit: empty,
                    provisional_empty: &[],
                    eof,
                },
                true,
                ScanBudget {
                    transitions: &mut 1000,
                    selection,
                },
            )
        };
        let mut work = 1000;
        let Scan::Token(hit) = ask(b"!", &ids, false, &mut work).unwrap() else {
            panic!("ordinary structural empty token was lost");
        };
        assert_eq!(
            (hit.symbol, hit.start, hit.end, hit.extra),
            (ids[0], 0, 0, false)
        );
        assert!(work < 1000);
        assert_eq!(
            ask(b"!", &ids[1..], false, &mut work).unwrap(),
            Scan::Stray { at: 0 }
        );
        assert_eq!(
            ask(b"!", &[], false, &mut work).unwrap(),
            Scan::Stray { at: 0 }
        );
        assert_eq!(ask(b"", &ids, true, &mut work).unwrap(), Scan::End);
        assert_eq!(ask(b"", &ids, false, &mut work).unwrap(), Scan::End);
        assert!(matches!(
            lexer.scan_question(
                b"x", 1,
                LexicalQuestion { admitted: Some(&ids), empty_permit: &ids, provisional_empty: &[], eof: false },
                true,
                ScanBudget { transitions: &mut 1000, selection: &mut work },
            ).unwrap(),
            Scan::Token(hit) if hit.start == 1 && hit.end == 1
        ));
        let mut limited = 1;
        assert!(matches!(
            ask(b"!", &ids, false, &mut limited),
            Err(LexError::QuestionWork { at: 0 })
        ));
        assert_eq!(limited, 0);
        assert!(
            matches!(ask(b"aaa!", &ids[1..], false, &mut work).unwrap(), Scan::Token(hit) if hit.end == 3)
        );
        assert!(
            !matches!(lexer.spot_with_budget(b"!", 0, true, &mut 1000).unwrap(), Scan::Token(hit) if hit.end == 0)
        );
    }

    #[test]
    fn unicode_offsets_eof_and_invalid_bytes_are_explicit() {
        let lexer = program(&[rx("[^\\\"\n]+", 0)], &[], None);
        assert_eq!(token(&lexer, "café".as_bytes(), &[0], true).end, 5);
        assert_eq!(
            lexer
                .scan_at(b"\xff", 0, &[SymbolId::from_index(0)], true)
                .unwrap(),
            Scan::Stray { at: 0 }
        );
        assert!(matches!(
            lexer.scan_at(b"x", 2, &[], true),
            Err(LexError::Offset { .. })
        ));
    }

    #[test]
    fn numeric_array_transition_work_scales_with_source_bytes() {
        let grammar =
            Automaton::from_tree_sitter(include_bytes!("../../test/grammar/json.json")).unwrap();
        let lexer = Lexer::compile(&grammar, LexerLimits::default()).unwrap();
        let admitted: Vec<_> = grammar
            .lexical_rules()
            .filter(|(id, _)| grammar.symbol(*id).name != "string_content")
            .map(|(id, _)| id)
            .collect();
        let measure = |values: usize| {
            let source = format!("[{}]", vec!["123"; values].join(",")).into_bytes();
            let mut remaining = usize::MAX;
            let mut at = 0;
            while at < source.len() {
                let Scan::Token(token) = lexer
                    .scan_with_budget(&source, at, &admitted, true, &mut remaining)
                    .unwrap()
                else {
                    panic!("array stopped at {at}");
                };
                assert!(token.end > at);
                at = token.end;
            }
            (source.len(), usize::MAX - remaining)
        };
        let small = measure(4096);
        let large = measure(8192);
        eprintln!("numeric arrays: {small:?} -> {large:?} (bytes, DFA transitions)");
        assert!(large.1 <= small.1 * 21 / 10);
        assert!(large.1 <= large.0 * 20);
    }

    #[test]
    fn higher_precedence_skips_lower_walks_and_budgets_bound_long_failures() {
        let mut high = lit("a", 1);
        high.precedence = 1;
        let lexer = program(&[rx("[a-z]+", 0), high], &[], None);
        let mut remaining = 10;
        let source = vec![b'a'; 100_000];
        let admitted = [SymbolId::from_index(0), SymbolId::from_index(1)];
        let Scan::Token(hit) = lexer
            .scan_with_budget(&source, 0, &admitted, true, &mut remaining)
            .unwrap()
        else {
            panic!("high precedence literal lost");
        };
        assert_eq!(hit.end, 1);
        assert!(remaining >= 6);
        let mut lexer = program(&[rx("a*b", 0), lit("a", 1)], &[], None);
        lexer.scan_transitions = 10;
        assert!(matches!(
            lexer.scan_at(&source, 0, &admitted, true),
            Err(LexError::WorkLimit { .. })
        ));
        lexer.scan_transitions = 1_000_000;
        let mut remaining = 10;
        assert!(matches!(
            lexer.scan_with_budget(&source, 0, &admitted, true, &mut remaining),
            Err(LexError::WorkLimit { .. })
        ));
        assert_eq!(remaining, 0);
    }

    #[test]
    fn diagnostic_spot_uses_shortest_spelling_without_lexical_precedence() {
        let mut broad = rx("[^\"]+", 0);
        broad.precedence = 10;
        let lexer = program(&[broad, lit(",", 1)], &[], None);
        let mut budget = 100;
        let Scan::Token(token) = lexer
            .spot_with_budget(b",bad", 0, true, &mut budget)
            .unwrap()
        else {
            panic!("no comma diagnostic");
        };
        assert_eq!((token.symbol.index(), token.end), (1, 1));
        let Scan::Token(token) = lexer
            .spot_with_budget(b"abc", 0, true, &mut budget)
            .unwrap()
        else {
            panic!("no body diagnostic");
        };
        assert_eq!((token.symbol.index(), token.end), (0, 1));
    }

    #[test]
    fn budgets_and_unsupported_patterns_refuse_explicitly() {
        let rule = rx("a{1,100}", 0);
        let rules = || std::iter::once((SymbolId::from_index(0), &rule));
        let tiny = LexerLimits {
            pattern_bytes: 1,
            ..LexerLimits::default()
        };
        assert!(matches!(
            Lexer::rules(rules(), &[], None, tiny),
            Err(LexError::PatternLimit { .. })
        ));
        // Native determinization has its own finite state cap and reports each
        // refusal. The adapter refuses partial slates instead of losing tokens.
        let bad = rx("(?=a)a", 0);
        assert!(matches!(
            Lexer::rules(
                std::iter::once((SymbolId::from_index(0), &bad)),
                &[],
                None,
                LexerLimits::default()
            ),
            Err(LexError::Build(_))
        ));
        fn shareable<T: Send + Sync>() {}
        shareable::<Lexer>();
    }
}
