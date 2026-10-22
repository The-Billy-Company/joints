//! Grammar-bound structural queries. Compilation proves names and predicate shapes;
//! execution borrows the immutable tree and never detaches captures from its source.

mod facts;
mod run;
mod syntax;

use std::sync::Arc;

use irgx::{Regex, RegexBuilder};

use crate::ids::{CaptureId, FieldId, PatternId, SymbolId};
use crate::{CompiledGrammar, Node, ProbeLimits, TreeSnapshot};

/// Finite construction, search, publication, and native-regex ceilings.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct QueryLimits {
    pub source_bytes: usize,
    pub work: usize,
    pub depth: usize,
    pub matches: usize,
    pub captures: usize,
    pub regex: ProbeLimits,
}

impl Default for QueryLimits {
    fn default() -> Self {
        Self {
            source_bytes: 1 << 20,
            work: 100_000_000,
            depth: 512,
            matches: 1_000_000,
            captures: 4_000_000,
            regex: ProbeLimits::default(),
        }
    }
}

#[derive(Debug, thiserror::Error)]
pub enum QueryError {
    #[error("query syntax at byte {at}: {message}")]
    Syntax { at: usize, message: &'static str },
    #[error("unknown query {sort} `{name}` at byte {at}")]
    UnknownName {
        at: usize,
        sort: &'static str,
        name: String,
    },
    #[error("invalid predicate `{name}` at byte {at}: {message}")]
    Predicate {
        at: usize,
        name: String,
        message: &'static str,
    },
    #[error("query regular expression at byte {at}: {message}")]
    Regex { at: usize, message: String },
    #[error("query exceeded its {0} limit")]
    Limit(&'static str),
    #[error("invalid query limits: {0}")]
    InvalidLimits(&'static str),
    #[error("query and tree belong to different grammars")]
    ForeignGrammar,
    #[error("query does not implement predicate `{name}` at byte {at}")]
    ForeignPredicate { at: usize, name: String },
    #[error("query does not implement a group inside a choice at byte {at}")]
    UnsupportedChoiceGroup { at: usize },
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum ForeignPolicy {
    #[default]
    Refuse,
    Admit,
    Deny,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum QueryArgument {
    Capture(CaptureId),
    Text(Vec<u8>),
}

/// Predicate spelling and arguments are retained, including host directives.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct QueryPredicate {
    pub name: String,
    pub arguments: Vec<QueryArgument>,
    pub at: usize,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DeadCause {
    FieldNotCarried,
    ChildNotAdmitted,
    CategoryNotMember,
}

impl std::fmt::Display for DeadCause {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Self::FieldNotCarried => "field not carried",
            Self::ChildNotAdmitted => "child not admitted",
            Self::CategoryNotMember => "category not member",
        })
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DeadPattern {
    pub pattern: PatternId,
    pub at: usize,
    pub cause: DeadCause,
}

#[derive(Clone, Copy, Debug)]
pub struct QueryCapture<'tree> {
    pub id: CaptureId,
    pub node: Node<'tree>,
}

#[derive(Clone, Debug)]
pub struct QueryMatch<'tree> {
    pub pattern: PatternId,
    pub captures: Vec<QueryCapture<'tree>>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Quantifier {
    One,
    Optional,
    Star,
    Plus,
}

#[derive(Debug)]
enum Kind {
    Any,
    Named,
    Name {
        name: String,
        named: bool,
        under: Vec<SymbolId>,
    },
    Category(Vec<SymbolId>),
    Group,
    Choice,
}

#[derive(Debug)]
struct Step {
    kind: Kind,
    children: Vec<usize>,
    captures: Vec<CaptureId>,
    field: Option<FieldId>,
    absent: Vec<FieldId>,
    quantifier: Quantifier,
    anchored: bool,
    closed: bool,
    at: usize,
}

struct Pattern {
    root: usize,
    at: usize,
    predicates: Vec<QueryPredicate>,
    regexes: Vec<Option<Regex>>,
    dead: bool,
}

/// A query owns its source and immutable grammar; each execution owns its search.
/// Capture and pattern identifiers are local to this query.
pub struct Query {
    grammar: Arc<CompiledGrammar>,
    source: Vec<u8>,
    steps: Vec<Step>,
    patterns: Vec<Pattern>,
    capture_names: Vec<String>,
    dead: Vec<DeadPattern>,
    unsupported_choice: Option<usize>,
    foreign_predicate: Option<(usize, usize)>,
    limits: QueryLimits,
}

impl std::fmt::Debug for Query {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Query")
            .field("patterns", &self.patterns.len())
            .field("captures", &self.capture_names)
            .field("dead", &self.dead)
            .finish()
    }
}

impl Query {
    pub fn compile(grammar: Arc<CompiledGrammar>, source: &[u8]) -> Result<Self, QueryError> {
        Self::compile_with_limits(grammar, source, QueryLimits::default())
    }

    pub fn compile_with_limits(
        grammar: Arc<CompiledGrammar>,
        source: &[u8],
        limits: QueryLimits,
    ) -> Result<Self, QueryError> {
        validate_limits(limits)?;
        if source.len() > limits.source_bytes {
            return Err(QueryError::Limit("source bytes"));
        }
        let mut budget = Budget::new(limits.work);
        budget.charge(source.len())?;
        let facts = facts::Facts::new(&grammar.automaton, &mut budget)?;
        let mut query = Self {
            grammar: Arc::clone(&grammar),
            source: source.to_vec(),
            steps: Vec::new(),
            patterns: Vec::new(),
            capture_names: Vec::new(),
            dead: Vec::new(),
            unsupported_choice: None,
            foreign_predicate: None,
            limits,
        };
        syntax::read(&mut query, &facts, &mut budget)?;
        for index in 0..query.patterns.len() {
            let root = query.patterns[index].root;
            if let Some((at, cause)) = facts.dead(root, &query.steps, &mut budget)? {
                query.patterns[index].dead = true;
                query.dead.push(DeadPattern {
                    pattern: PatternId::from_index(index),
                    at,
                    cause,
                });
            }
            query.prepare_predicates(index, &mut budget)?;
        }
        Ok(query)
    }

    pub fn execute<'tree>(
        &self,
        tree: &'tree TreeSnapshot,
        foreign: ForeignPolicy,
    ) -> Result<Vec<QueryMatch<'tree>>, QueryError> {
        self.execute_with_limits(tree, foreign, self.limits)
    }

    /// Execute with operation-local limits. Regex interpreter ceilings are fixed
    /// at compilation; the supplied regex fields must equal those ceilings.
    pub fn execute_with_limits<'tree>(
        &self,
        tree: &'tree TreeSnapshot,
        foreign: ForeignPolicy,
        limits: QueryLimits,
    ) -> Result<Vec<QueryMatch<'tree>>, QueryError> {
        validate_limits(limits)?;
        if limits.regex != self.limits.regex {
            return Err(QueryError::InvalidLimits(
                "regex ceilings belong to the compiled query",
            ));
        }
        if !Arc::ptr_eq(&self.grammar, tree.grammar()) {
            return Err(QueryError::ForeignGrammar);
        }
        if let Some(at) = self.unsupported_choice {
            return Err(QueryError::UnsupportedChoiceGroup { at });
        }
        // Refuse before publishing even when a foreign predicate's pattern is dead
        // or never matches. A complete answer cannot silently omit its question.
        if foreign == ForeignPolicy::Refuse {
            if let Some((pattern, predicate)) = self.foreign_predicate {
                let predicate = &self.patterns[pattern].predicates[predicate];
                return Err(QueryError::ForeignPredicate {
                    at: predicate.at,
                    name: predicate.name.clone(),
                });
            }
        }
        run::execute(self, tree, foreign, limits)
    }

    pub fn source(&self) -> &[u8] {
        &self.source
    }
    pub fn pattern_count(&self) -> usize {
        self.patterns.len()
    }
    pub fn capture_count(&self) -> usize {
        self.capture_names.len()
    }
    pub fn capture_names(&self) -> &[String] {
        &self.capture_names
    }
    pub fn capture_id(&self, index: usize) -> Option<CaptureId> {
        (index < self.capture_names.len()).then(|| CaptureId::from_index(index))
    }
    pub fn pattern_id(&self, index: usize) -> Option<PatternId> {
        (index < self.patterns.len()).then(|| PatternId::from_index(index))
    }
    pub fn capture_name(&self, id: CaptureId) -> Option<&str> {
        self.capture_names.get(id.index()).map(String::as_str)
    }
    pub fn pattern_start(&self, id: PatternId) -> Option<usize> {
        self.patterns.get(id.index()).map(|p| p.at)
    }
    pub fn predicates(&self, id: PatternId) -> Option<&[QueryPredicate]> {
        self.patterns
            .get(id.index())
            .map(|p| p.predicates.as_slice())
    }
    pub fn dead_patterns(&self) -> &[DeadPattern] {
        &self.dead
    }

    fn prepare_predicates(&mut self, index: usize, budget: &mut Budget) -> Result<(), QueryError> {
        let mut bound = std::collections::BTreeSet::new();
        let mut todo = vec![self.patterns[index].root];
        while let Some(id) = todo.pop() {
            let s = &self.steps[id];
            budget.charge(1 + s.children.len() + s.captures.len())?;
            bound.extend(s.captures.iter().copied());
            todo.extend(s.children.iter().copied());
        }
        let pattern = &mut self.patterns[index];
        for (predicate_index, predicate) in pattern.predicates.iter().enumerate() {
            if !core(&predicate.name) && !predicate.name.ends_with('!') {
                self.foreign_predicate
                    .get_or_insert((index, predicate_index));
            }
            budget.charge(1 + predicate.arguments.len())?;
            for arg in &predicate.arguments {
                if let QueryArgument::Capture(id) = arg {
                    if !core(&predicate.name) {
                        continue;
                    }
                    if !bound.contains(id) {
                        return Err(QueryError::Predicate {
                            at: predicate.at,
                            name: predicate.name.clone(),
                            message: "capture is not bound in this pattern",
                        });
                    }
                }
            }
            let args = &predicate.arguments;
            let malformed = match predicate.name.as_str() {
                "eq?" | "not-eq?" => {
                    args.len() != 2 || !matches!(args.first(), Some(QueryArgument::Capture(_)))
                }
                "match?" | "not-match?" => {
                    args.len() != 2
                        || !matches!(args.first(), Some(QueryArgument::Capture(_)))
                        || !matches!(args.get(1), Some(QueryArgument::Text(_)))
                }
                "any-of?" | "not-any-of?" => {
                    args.len() < 2
                        || !matches!(args.first(), Some(QueryArgument::Capture(_)))
                        || args[1..]
                            .iter()
                            .any(|a| !matches!(a, QueryArgument::Text(_)))
                }
                _ => false,
            };
            if malformed {
                return Err(QueryError::Predicate {
                    at: predicate.at,
                    name: predicate.name.clone(),
                    message: "wrong argument count or type",
                });
            }
            let regex = if matches!(predicate.name.as_str(), "match?" | "not-match?") {
                let QueryArgument::Text(bytes) = &args[1] else {
                    unreachable!()
                };
                if bytes.len() > 16 << 10 {
                    return Err(QueryError::Limit("regex pattern bytes"));
                }
                let text = std::str::from_utf8(bytes).map_err(|_| QueryError::Regex {
                    at: predicate.at,
                    message: "pattern is not UTF-8".into(),
                })?;
                budget.charge(bytes.len())?;
                let rx = RegexBuilder::new(text)
                    .unicode(false)
                    .pcre(true)
                    .match_limit(self.limits.regex.match_steps)
                    .depth_limit(self.limits.regex.depth)
                    .heap_limit_bytes(self.limits.regex.heap_bytes)
                    .build()
                    .map_err(|e| QueryError::Regex {
                        at: predicate.at,
                        message: e.to_string(),
                    })?;
                if rx.groups().is_none_or(|n| n > 32) {
                    return Err(QueryError::Limit("regex capture groups"));
                }
                Some(rx)
            } else {
                None
            };
            pattern.regexes.push(regex);
        }
        Ok(())
    }
}

fn core(name: &str) -> bool {
    matches!(
        name,
        "eq?" | "not-eq?" | "any-of?" | "not-any-of?" | "match?" | "not-match?"
    )
}

fn validate_limits(limits: QueryLimits) -> Result<(), QueryError> {
    if limits.depth > 1024 {
        return Err(QueryError::InvalidLimits("depth exceeds 1024"));
    }
    let p = limits.regex;
    if p.match_steps > u32::MAX.into()
        || p.depth > u32::MAX.into()
        || p.heap_bytes > usize::MAX as u64
        || p.heap_bytes / 1024 > u64::from(u32::MAX)
        || p.heap_bytes % 1024 != 0
    {
        return Err(QueryError::InvalidLimits(
            "regex ceilings exceed the native counters or whole KiB",
        ));
    }
    Ok(())
}

struct Budget {
    remaining: usize,
}
impl Budget {
    fn new(work: usize) -> Self {
        Self { remaining: work }
    }
    fn charge(&mut self, amount: usize) -> Result<(), QueryError> {
        self.remaining = self
            .remaining
            .checked_sub(amount)
            .ok_or(QueryError::Limit("work"))?;
        Ok(())
    }
}
