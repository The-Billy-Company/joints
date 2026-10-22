//! A bounded reader for tree-sitter query notation. Predicates belong to the
//! surrounding top-level pattern regardless of where their parentheses appear.

use std::collections::BTreeMap;

use super::*;

pub(super) fn read(
    query: &mut Query,
    facts: &facts::Facts,
    budget: &mut Budget,
) -> Result<(), QueryError> {
    // The reader borrows source separately so it can append owned lowered steps.
    budget.charge(query.source.len())?;
    let source = query.source.clone();
    let mut reader = Reader {
        query,
        source: &source,
        facts,
        budget,
        at: 0,
        names: BTreeMap::new(),
        predicates: Vec::new(),
    };
    loop {
        reader.skip();
        if reader.at == source.len() {
            break;
        }
        let at = reader.at;
        reader.predicates.clear();
        let root = reader
            .item(0)?
            .ok_or_else(|| reader.error("predicate has no pattern"))?;
        if reader.query.steps[root].quantifier != Quantifier::One {
            return Err(reader.error("quantifier has no sibling position"));
        }
        reader.budget.charge(1 + reader.predicates.len())?;
        reader.query.patterns.push(Pattern {
            root,
            at,
            predicates: std::mem::take(&mut reader.predicates),
            regexes: Vec::new(),
            dead: false,
        });
    }
    Ok(())
}

struct Reader<'a> {
    query: &'a mut Query,
    source: &'a [u8],
    facts: &'a facts::Facts,
    budget: &'a mut Budget,
    at: usize,
    names: BTreeMap<String, CaptureId>,
    predicates: Vec<QueryPredicate>,
}

impl Reader<'_> {
    fn error(&self, message: &'static str) -> QueryError {
        QueryError::Syntax {
            at: self.at,
            message,
        }
    }
    fn skip(&mut self) {
        while let Some(&byte) = self.source.get(self.at) {
            if byte == b';' {
                while self.source.get(self.at).is_some_and(|b| *b != b'\n') {
                    self.at += 1;
                }
            } else if byte.is_ascii_whitespace() {
                self.at += 1;
            } else {
                break;
            }
        }
    }
    fn word(&mut self) -> Result<String, QueryError> {
        let start = self.at;
        while self
            .source
            .get(self.at)
            .is_some_and(|c| c.is_ascii_alphanumeric() || matches!(c, b'_' | b'-' | b'.'))
        {
            self.at += 1;
        }
        if start == self.at {
            return Err(self.error("expected a name"));
        }
        self.budget.charge(self.at - start)?;
        Ok(String::from_utf8(self.source[start..self.at].to_vec()).expect("ASCII word"))
    }
    fn capture(&mut self) -> Result<CaptureId, QueryError> {
        let name = self.word()?;
        if let Some(&id) = self.names.get(&name) {
            return Ok(id);
        }
        if self.query.capture_names.len() >= u32::MAX as usize {
            return Err(QueryError::Limit("capture identifiers"));
        }
        self.budget.charge(name.len() + 1)?;
        let id = CaptureId::from_index(self.query.capture_names.len());
        self.query.capture_names.push(name.clone());
        self.names.insert(name, id);
        Ok(id)
    }
    fn string(&mut self) -> Result<Vec<u8>, QueryError> {
        self.at += 1;
        let mut out = Vec::new();
        loop {
            let byte = *self
                .source
                .get(self.at)
                .ok_or_else(|| self.error("unclosed string"))?;
            self.at += 1;
            if byte == b'"' {
                return Ok(out);
            }
            let byte = if byte == b'\\' {
                let escaped = *self
                    .source
                    .get(self.at)
                    .ok_or_else(|| self.error("unclosed escape"))?;
                self.at += 1;
                match escaped {
                    b'n' => b'\n',
                    b'r' => b'\r',
                    b't' => b'\t',
                    b'0' => 0,
                    other => other,
                }
            } else {
                byte
            };
            self.budget.charge(1)?;
            out.push(byte);
        }
    }
    fn item(&mut self, depth: usize) -> Result<Option<usize>, QueryError> {
        if depth >= 64 || depth >= self.query.limits.depth {
            return Err(QueryError::Limit("syntax depth"));
        }
        self.skip();
        let at = self.at;
        let mut field = None;
        let start = self.at;
        while self
            .source
            .get(self.at)
            .is_some_and(|c| c.is_ascii_alphanumeric() || matches!(c, b'_' | b'-' | b'.'))
        {
            self.at += 1;
        }
        if self.at > start && self.source.get(self.at) == Some(&b':') {
            let name = std::str::from_utf8(&self.source[start..self.at]).expect("ASCII word");
            field = Some(self.facts.field(name, start)?);
            self.at += 1;
            self.skip();
        } else {
            self.at = start;
        }
        let mut step = Step {
            kind: Kind::Any,
            children: Vec::new(),
            captures: Vec::new(),
            field,
            absent: Vec::new(),
            quantifier: Quantifier::One,
            anchored: false,
            closed: false,
            at,
        };
        match self
            .source
            .get(self.at)
            .copied()
            .ok_or_else(|| self.error("expected a pattern"))?
        {
            b'"' => {
                let bytes = self.string()?;
                let name = std::str::from_utf8(&bytes)
                    .map_err(|_| self.error("literal name is not UTF-8"))?;
                step.kind = self.facts.kind(name, false, None, at, self.budget)?;
            }
            b'_' => {
                if self.word()? != "_" {
                    return Err(self.error("a bare name is not a pattern"));
                }
            }
            b'[' => {
                self.at += 1;
                step.kind = Kind::Choice;
                self.list(&mut step, b']', depth + 1)?;
            }
            b'(' => {
                self.at += 1;
                self.skip();
                if self.source.get(self.at) == Some(&b'#') {
                    self.predicate()?;
                    return Ok(None);
                }
                if self
                    .source
                    .get(self.at)
                    .is_some_and(|c| c.is_ascii_alphanumeric() || matches!(c, b'_' | b'-' | b'.'))
                {
                    let mut name = self.word()?;
                    let category = if self.source.get(self.at) == Some(&b'/') {
                        self.at += 1;
                        Some(std::mem::replace(&mut name, self.word()?))
                    } else {
                        None
                    };
                    step.kind =
                        self.facts
                            .kind(&name, true, category.as_deref(), at, self.budget)?;
                    self.list(&mut step, b')', depth + 1)?;
                } else {
                    step.kind = Kind::Group;
                    self.list(&mut step, b')', depth + 1)?;
                }
            }
            b')' | b']' => return Err(self.error("unexpected closing delimiter")),
            _ => return Err(self.error("unexpected byte")),
        }
        loop {
            self.skip();
            match self.source.get(self.at) {
                Some(b'?') => {
                    step.quantifier = Quantifier::Optional;
                    self.at += 1;
                }
                Some(b'*') => {
                    step.quantifier = Quantifier::Star;
                    self.at += 1;
                }
                Some(b'+') => {
                    step.quantifier = Quantifier::Plus;
                    self.at += 1;
                }
                Some(b'@') => {
                    self.at += 1;
                    let id = self.capture()?;
                    self.budget.charge(1)?;
                    step.captures.push(id);
                }
                _ => break,
            }
        }
        self.budget.charge(1)?;
        let id = self.query.steps.len();
        self.query.steps.push(step);
        Ok(Some(id))
    }
    fn list(&mut self, step: &mut Step, close: u8, depth: usize) -> Result<(), QueryError> {
        let mut anchored = false;
        loop {
            self.skip();
            match self
                .source
                .get(self.at)
                .copied()
                .ok_or_else(|| self.error("unclosed delimiter"))?
            {
                byte if byte == close => {
                    self.at += 1;
                    step.closed = anchored;
                    break;
                }
                b'.' => {
                    if anchored {
                        return Err(self.error("anchor has no position"));
                    }
                    anchored = true;
                    self.at += 1;
                }
                b'!' if !matches!(step.kind, Kind::Choice | Kind::Group) => {
                    self.at += 1;
                    let at = self.at;
                    let name = self.word()?;
                    self.budget.charge(1)?;
                    step.absent.push(self.facts.field(&name, at)?);
                }
                _ => {
                    if let Some(child) = self.item(depth)? {
                        self.query.steps[child].anchored = anchored;
                        anchored = false;
                        if matches!(step.kind, Kind::Choice)
                            && matches!(self.query.steps[child].kind, Kind::Group)
                        {
                            self.query
                                .unsupported_choice
                                .get_or_insert(self.query.steps[child].at);
                        }
                        self.budget.charge(1)?;
                        step.children.push(child);
                    }
                }
            }
        }
        Ok(())
    }
    fn predicate(&mut self) -> Result<(), QueryError> {
        let at = self.at;
        self.at += 1;
        let mut name = self.word()?;
        if let Some(&suffix) = self
            .source
            .get(self.at)
            .filter(|c| matches!(c, b'?' | b'!'))
        {
            name.push(char::from(suffix));
            self.at += 1;
        }
        let mut arguments = Vec::new();
        loop {
            self.skip();
            let argument = match self
                .source
                .get(self.at)
                .copied()
                .ok_or_else(|| self.error("unclosed predicate"))?
            {
                b')' => {
                    self.at += 1;
                    break;
                }
                b'@' => {
                    self.at += 1;
                    QueryArgument::Capture(self.capture()?)
                }
                b'"' => QueryArgument::Text(self.string()?),
                _ => QueryArgument::Text(self.word()?.into_bytes()),
            };
            self.budget.charge(1)?;
            arguments.push(argument);
        }
        self.budget.charge(1)?;
        self.predicates.push(QueryPredicate {
            at,
            name,
            arguments,
        });
        Ok(())
    }
}
