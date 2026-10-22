//! One authoritative source recipe for source construction and checked images.
use super::{
    Automaton, Entry, LexError, Lexer, LexerLimits, Lexis, Munch, Pattern, ScannerProgram,
    SymbolId, Tier,
};
use crate::artifact::{ArtifactError, ImageSession};

pub(super) type Rule<'a> = (SymbolId, &'a Lexis, bool, bool);

#[derive(Clone, Copy)]
pub(super) struct Recipe<'a> {
    grammar: &'a Automaton,
    program: Option<&'a ScannerProgram>,
}
impl<'a> Recipe<'a> {
    pub(super) fn new(grammar: &'a Automaton, program: Option<&'a ScannerProgram>) -> Self {
        Self { grammar, program }
    }
    pub(super) fn symbol_visits(self) -> usize {
        self.grammar.symbol_count()
    }
    pub(super) fn rules(self) -> impl Iterator<Item = Rule<'a>> + 'a {
        let grammar = self.grammar;
        grammar
            .lexical_rules()
            .map(move |(id, rule)| (id, rule, false, grammar.symbol(id).external))
            .chain(
                self.program
                    .into_iter()
                    .flat_map(ScannerProgram::lexical_rules)
                    .map(|(id, rule)| (id, rule, true, true)),
            )
    }
}

pub(super) trait Budget {
    type Error;
    fn work(&mut self, n: usize) -> Result<(), Self::Error>;
    fn allocation(&mut self, bytes: usize) -> Result<(), Self::Error>;
    fn tier_count(&mut self, expected: usize) -> Result<(), Self::Error>;
    fn lexical(error: LexError) -> Self::Error;
    fn storage(what: &'static str) -> Self::Error;
}
pub(super) struct Source;
impl Budget for Source {
    type Error = LexError;
    fn work(&mut self, _: usize) -> Result<(), LexError> {
        Ok(())
    }
    fn allocation(&mut self, _: usize) -> Result<(), LexError> {
        Ok(())
    }
    fn tier_count(&mut self, _: usize) -> Result<(), LexError> {
        Ok(())
    }
    fn lexical(error: LexError) -> LexError {
        error
    }
    fn storage(what: &'static str) -> LexError {
        LexError::Allocation(what)
    }
}
impl Budget for ImageSession<'_, '_, '_> {
    type Error = ArtifactError;
    fn work(&mut self, n: usize) -> Result<(), ArtifactError> {
        self.charge_work(n)
    }
    fn allocation(&mut self, bytes: usize) -> Result<(), ArtifactError> {
        self.charge_allocation(bytes)
    }
    fn tier_count(&mut self, expected: usize) -> Result<(), ArtifactError> {
        ImageSession::tier_count(self, expected)
    }
    fn lexical(error: LexError) -> ArtifactError {
        ArtifactError::Grammar(crate::Error::Lex(error))
    }
    fn storage(what: &'static str) -> ArtifactError {
        ArtifactError::Allocation(what)
    }
}

fn vector<T, B: Budget>(
    count: usize,
    what: &'static str,
    budget: &mut B,
) -> Result<Vec<T>, B::Error> {
    let bytes = count
        .checked_mul(size_of::<T>())
        .ok_or_else(|| B::storage(what))?;
    budget.allocation(bytes)?;
    let mut result = Vec::new();
    result
        .try_reserve_exact(count)
        .map_err(|_| B::storage(what))?;
    Ok(result)
}

fn escaped(ch: char) -> bool {
    matches!(
        ch,
        '\\' | '^' | '$' | '.' | '|' | '?' | '*' | '+' | '(' | ')' | '[' | ']' | '{' | '}'
    )
}

// Validation and escaped-size measurement remain in original source order.
// A literal's UTF-8 check, character measurement and later fill are distinct
// paid passes; no String is allocated by this measurement.
struct Spelling<'a> {
    text: &'a str,
    len: usize,
    literal: bool,
}
fn measure<'a, B: Budget>(
    symbol: SymbolId,
    pattern: &'a Pattern,
    budget: &mut B,
) -> Result<Option<Spelling<'a>>, B::Error> {
    match pattern {
        Pattern::External => Ok(None),
        Pattern::Regex(text) => Ok(Some(Spelling {
            text,
            len: text.len(),
            literal: false,
        })),
        Pattern::Literal(bytes) => {
            budget.work(bytes.len())?;
            let text = std::str::from_utf8(bytes)
                .map_err(|_| B::lexical(LexError::LiteralEncoding { symbol }))?;
            budget.work(bytes.len())?;
            let mut len = bytes.len();
            for ch in text.chars() {
                if escaped(ch) {
                    len = len
                        .checked_add(1)
                        .ok_or_else(|| B::storage("escaped pattern"))?;
                }
            }
            Ok(Some(Spelling {
                text,
                len,
                literal: true,
            }))
        }
    }
}
fn pattern<B: Budget>(
    symbol: SymbolId,
    source: &Pattern,
    budget: &mut B,
) -> Result<(String, bool), B::Error> {
    let spelling = measure(symbol, source, budget)?.expect("external rules are not tier members");
    budget.allocation(spelling.len)?;
    budget.work(spelling.len)?;
    let mut result = String::new();
    result
        .try_reserve_exact(spelling.len)
        .map_err(|_| B::storage("pattern bytes"))?;
    if spelling.literal {
        for ch in spelling.text.chars() {
            if escaped(ch) {
                result.push('\\');
            }
            result.push(ch);
        }
    } else {
        result.push_str(spelling.text);
    }
    Ok((result, spelling.literal))
}
fn next_precedence<'a, I, B: Budget>(
    rules: impl Fn(&mut B) -> Result<I, B::Error>,
    below: Option<i32>,
    budget: &mut B,
) -> Result<Option<i32>, B::Error>
where
    I: Iterator<Item = Rule<'a>>,
{
    let mut next = None;
    for (_, rule, _, _) in rules(budget)? {
        budget.work(1)?;
        if !matches!(rule.pattern, Pattern::External)
            && below.is_none_or(|previous| rule.precedence < previous)
            && next.is_none_or(|greatest| rule.precedence > greatest)
        {
            next = Some(rule.precedence);
        }
    }
    Ok(next)
}

pub(super) fn assemble<'a, I, B: Budget>(
    rules: impl Fn(&mut B) -> Result<I, B::Error>,
    extras: &[SymbolId],
    word: Option<SymbolId>,
    limits: LexerLimits,
    budget: &mut B,
    mut slate: impl FnMut(Vec<String>, &[Entry], &mut B) -> Result<Munch, B::Error>,
) -> Result<Lexer, B::Error>
where
    I: Iterator<Item = Rule<'a>>,
{
    let mut bytes = 0usize;
    for (symbol, rule, _, _) in rules(budget)? {
        budget.work(1)?;
        let Some(spelling) = measure(symbol, &rule.pattern, budget)? else {
            continue;
        };
        bytes = bytes.checked_add(spelling.len).ok_or_else(|| {
            B::lexical(LexError::PatternLimit {
                limit: limits.pattern_bytes,
            })
        })?;
        if bytes > limits.pattern_bytes {
            return Err(B::lexical(LexError::PatternLimit {
                limit: limits.pattern_bytes,
            }));
        }
    }
    let mut count = 0usize;
    let mut below = None;
    while let Some(precedence) = next_precedence(&rules, below, budget)? {
        count = count
            .checked_add(1)
            .ok_or_else(|| B::storage("tier count"))?;
        below = Some(precedence);
    }
    budget.tier_count(count)?;
    let mut tiers = vector(count, "tiers", budget)?;
    let mut below = None;
    while let Some(precedence) = next_precedence(&rules, below, budget)? {
        let mut count = 0usize;
        for (_, rule, _, _) in rules(budget)? {
            budget.work(1)?;
            if rule.precedence == precedence && !matches!(rule.pattern, Pattern::External) {
                count = count
                    .checked_add(1)
                    .ok_or_else(|| B::storage("tier entries"))?;
            }
        }
        let mut patterns = vector(count, "pattern metadata", budget)?;
        let mut entries = vector(count, "entries", budget)?;
        for (symbol, rule, provided, external) in rules(budget)? {
            budget.work(1)?;
            if rule.precedence != precedence || matches!(rule.pattern, Pattern::External) {
                continue;
            }
            let (pattern, literal) = pattern(symbol, &rule.pattern, budget)?;
            let mut extra = false;
            for candidate in extras {
                budget.work(1)?;
                if *candidate == symbol {
                    extra = true;
                    break;
                }
            }
            patterns.push(pattern);
            entries.push(Entry {
                symbol,
                order: rule.declaration_order,
                immediate: rule.immediate,
                literal,
                provided,
                external,
                extra,
            });
        }
        let slate = slate(patterns, &entries, budget)?;
        tiers.push(Tier {
            #[cfg(all(test, feature = "munch-image"))]
            precedence,
            slate,
            entries,
        });
        below = Some(precedence);
    }
    Ok(Lexer {
        tiers,
        word,
        scan_transitions: limits.scan_transitions,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Default)]
    struct Counted {
        work: usize,
        allocation: usize,
    }
    impl Budget for Counted {
        type Error = LexError;
        fn work(&mut self, n: usize) -> Result<(), LexError> {
            self.work += n;
            Ok(())
        }
        fn allocation(&mut self, n: usize) -> Result<(), LexError> {
            self.allocation += n;
            Ok(())
        }
        fn tier_count(&mut self, _: usize) -> Result<(), LexError> {
            Ok(())
        }
        fn lexical(error: LexError) -> LexError {
            error
        }
        fn storage(what: &'static str) -> LexError {
            LexError::Allocation(what)
        }
    }
    fn lexis(pattern: Pattern, precedence: i32) -> Lexis {
        Lexis {
            pattern,
            immediate: false,
            precedence,
            declaration_order: 0,
        }
    }

    #[test]
    fn lexical_recipe_extreme_precedence_is_descending_and_skips_external_only_keys() {
        let rules = [
            lexis(Pattern::Regex("a".into()), i32::MIN),
            lexis(Pattern::External, 19),
            lexis(Pattern::Literal(b"b".to_vec()), i32::MAX),
            lexis(Pattern::Regex("c".into()), -1),
            lexis(Pattern::Regex("d".into()), i32::MAX),
        ];
        let borrowed = |_: &mut Counted| {
            Ok(rules
                .iter()
                .enumerate()
                .map(|(i, r)| (SymbolId::from_index(i), r, false, false)))
        };
        let mut budget = Counted::default();
        let mut below = None;
        let mut actual = Vec::new();
        while let Some(precedence) = next_precedence(&borrowed, below, &mut budget).unwrap() {
            actual.push(precedence);
            below = Some(precedence);
        }
        assert_eq!(actual, [i32::MAX, -1, i32::MIN]);
        assert_eq!(budget.work, 4 * rules.len());
        assert_eq!(budget.allocation, 0);
    }

    #[test]
    fn lexical_recipe_original_order_errors_precede_tier_construction() {
        let first = SymbolId::from_index(0);
        let bad = lexis(Pattern::Literal(vec![0xff]), i32::MIN);
        let large = lexis(Pattern::Regex("oversized".into()), i32::MAX);
        let make = |_: Vec<String>, _: &[Entry], _: &mut Source| -> Result<Munch, LexError> {
            panic!("validation must finish before constructing a slate")
        };
        let limits = LexerLimits {
            pattern_bytes: 1,
            scan_transitions: 9,
        };
        let result = assemble(
            |_| {
                Ok([
                    (first, &bad, false, false),
                    (SymbolId::from_index(1), &large, false, false),
                ]
                .into_iter())
            },
            &[],
            None,
            limits,
            &mut Source,
            make,
        );
        assert!(matches!(result, Err(LexError::LiteralEncoding { symbol }) if symbol == first));
        let result = assemble(
            |_| {
                Ok([
                    (first, &large, false, false),
                    (SymbolId::from_index(1), &bad, false, false),
                ]
                .into_iter())
            },
            &[],
            None,
            limits,
            &mut Source,
            make,
        );
        assert!(matches!(result, Err(LexError::PatternLimit { limit: 1 })));
    }

    #[test]
    fn lexical_recipe_literal_storage_is_exact_and_external_only_has_no_tier() {
        let source = Pattern::Literal("é.(x)".as_bytes().to_vec());
        let mut budget = Counted::default();
        let (text, literal) = pattern(SymbolId::from_index(0), &source, &mut budget).unwrap();
        assert!(literal);
        assert_eq!(text, "é\\.\\(x\\)");
        assert_eq!(budget.allocation, 9);
        assert_eq!(budget.work, 6 + 6 + 9);
        let external = lexis(Pattern::External, i32::MAX);
        let result = assemble(
            |_| Ok([(SymbolId::from_index(0), &external, false, true)].into_iter()),
            &[],
            None,
            LexerLimits::default(),
            &mut Source,
            |_, _, _| -> Result<Munch, LexError> {
                panic!("external-only recipe has no native slate")
            },
        )
        .unwrap();
        assert!(result.tiers.is_empty());
    }
}
