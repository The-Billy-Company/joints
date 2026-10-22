//! Continuations keep a child's alternatives alive until its parent's remaining
//! siblings hold. Repeated positions commit their first complete greedy run.

use std::rc::Rc;

use super::*;
use crate::tree::NodeId;

#[derive(Clone, Copy)]
struct Capture {
    id: CaptureId,
    node: NodeId,
}
struct Held<'t> {
    pattern: PatternId,
    finish: usize,
    begin: usize,
    captures: Vec<QueryCapture<'t>>,
}

struct Bindings<'q> {
    captures: &'q [CaptureId],
    field: Option<FieldId>,
    parent: Option<Rc<Bindings<'q>>>,
}

#[derive(Clone)]
struct Frame<'q> {
    steps: &'q [usize],
    si: usize,
    ki: usize,
    seen: bool,
    pin: bool,
    head: Option<usize>,
    greedy: bool,
    stalled: bool,
    up: Option<Rc<Frame<'q>>>,
    bindings: Option<Rc<Bindings<'q>>>,
}
impl<'q> Frame<'q> {
    fn new(steps: &'q [usize], ki: usize) -> Self {
        Self {
            steps,
            si: 0,
            ki,
            seen: false,
            pin: false,
            head: None,
            greedy: false,
            stalled: false,
            up: None,
            bindings: None,
        }
    }
}

enum After<'a, 'q, 't> {
    Done {
        pattern: usize,
        root: NodeId,
    },
    More {
        kids: &'t [NodeId],
        frame: Frame<'q>,
        closed: bool,
        next: &'a After<'a, 'q, 't>,
    },
}

struct Cursor<'q, 't> {
    query: &'q Query,
    tree: &'t TreeSnapshot,
    foreign: ForeignPolicy,
    limits: QueryLimits,
    budget: Budget,
    found: Vec<Capture>,
    held: Vec<Held<'t>>,
    published_captures: usize,
}

pub(super) fn execute<'t>(
    query: &Query,
    tree: &'t TreeSnapshot,
    foreign: ForeignPolicy,
    limits: QueryLimits,
) -> Result<Vec<QueryMatch<'t>>, QueryError> {
    // Materialization stores every published node in source-ordered preorder.
    // Walking that arena preserves the former depth-first visit order without
    // allocating and maintaining a second frontier of the same node IDs.
    let nodes = (0..tree.nodes.len())
        .map(|index| NodeId(u32::try_from(index).expect("published tree node index")));
    execute_nodes(query, tree, foreign, limits, nodes)
}

fn execute_nodes<'t>(
    query: &Query,
    tree: &'t TreeSnapshot,
    foreign: ForeignPolicy,
    limits: QueryLimits,
    nodes: impl Iterator<Item = NodeId>,
) -> Result<Vec<QueryMatch<'t>>, QueryError> {
    let mut c = Cursor {
        query,
        tree,
        foreign,
        limits,
        budget: Budget::new(limits.work),
        found: Vec::new(),
        held: Vec::new(),
        published_captures: 0,
    };
    c.budget.charge(tree.roots.len())?;
    for root in nodes {
        c.budget.charge(1)?;
        for (index, pattern) in query.patterns.iter().enumerate() {
            c.budget.charge(1)?;
            if pattern.dead {
                continue;
            }
            let step = &query.steps[pattern.root];
            let done = After::Done {
                pattern: index,
                root,
            };
            if matches!(step.kind, Kind::Group) {
                let kids = &tree.children[tree.nodes[root.index()].child_range()];
                let mut frame = Frame::new(&step.children, 0);
                if !step.captures.is_empty() || step.field.is_some() {
                    c.budget.charge(1)?;
                    frame.bindings = Some(Rc::new(Bindings {
                        captures: &step.captures,
                        field: step.field,
                        parent: None,
                    }));
                }
                c.at(kids, frame, step.closed, &done, 0)?;
            } else {
                c.step(pattern.root, root, &done, false, 0, None)?;
            }
            c.found.clear();
        }
        c.budget
            .charge(tree.nodes[root.index()].child_range().len())?;
    }
    let count = c.held.len();
    c.budget
        .charge(count.saturating_mul((usize::BITS - count.leading_zeros()) as usize + 1))?;
    c.held.sort_by_key(|m| (m.finish, m.begin, m.pattern));
    c.budget.charge(count + c.published_captures)?;
    Ok(c.held
        .into_iter()
        .map(|m| QueryMatch {
            pattern: m.pattern,
            captures: m.captures,
        })
        .collect())
}

#[cfg(test)]
mod tests;

impl<'q, 't> Cursor<'q, 't> {
    fn enter(&mut self, depth: usize) -> Result<(), QueryError> {
        if depth >= self.limits.depth {
            return Err(QueryError::Limit("search depth"));
        }
        self.budget.charge(1)
    }
    fn step(
        &mut self,
        id: usize,
        node: NodeId,
        after: &After<'_, 'q, 't>,
        first: bool,
        depth: usize,
        bindings: Option<Rc<Bindings<'q>>>,
    ) -> Result<bool, QueryError> {
        self.enter(depth)?;
        let mark = self.found.len();
        let held = self.attempt(id, node, after, first, depth + 1, bindings)?;
        if !held {
            self.found.truncate(mark);
        }
        Ok(held)
    }
    fn attempt(
        &mut self,
        id: usize,
        node: NodeId,
        after: &After<'_, 'q, 't>,
        first: bool,
        depth: usize,
        bindings: Option<Rc<Bindings<'q>>>,
    ) -> Result<bool, QueryError> {
        self.enter(depth)?;
        let query = self.query;
        let step = &query.steps[id];
        let data = &self.tree.nodes[node.index()];
        if step.field.is_some() && step.field != data.field() {
            return Ok(false);
        }
        let mut inherited = bindings.as_deref();
        while let Some(binding) = inherited {
            self.budget.charge(1)?;
            if binding.field.is_some() && binding.field != data.field() {
                return Ok(false);
            }
            inherited = binding.parent.as_deref();
        }
        match &step.kind {
            Kind::Group => return Err(QueryError::UnsupportedChoiceGroup { at: step.at }),
            Kind::Choice => {
                self.budget.charge(1)?;
                let bindings = Some(Rc::new(Bindings {
                    captures: &step.captures,
                    field: None,
                    parent: bindings,
                }));
                let mark = self.found.len();
                for &child in &step.children {
                    self.budget.charge(1)?;
                    if self.step(child, node, after, first, depth + 1, bindings.clone())? {
                        return Ok(true);
                    }
                    self.found.truncate(mark);
                }
                return Ok(false);
            }
            Kind::Any => self.bind(step, node, bindings.as_deref())?,
            _ => {
                if !self.fits(step, node)? {
                    return Ok(false);
                }
                let kids = &self.tree.children[data.child_range()];
                if !step.absent.is_empty() {
                    for child in kids {
                        self.budget.charge(1 + step.absent.len())?;
                        if self.tree.nodes[child.index()]
                            .field()
                            .is_some_and(|field| step.absent.contains(&field))
                        {
                            return Ok(false);
                        }
                    }
                }
                self.bind(step, node, bindings.as_deref())?;
                if !step.children.is_empty() || step.closed {
                    let mut frame = Frame::new(&step.children, 0);
                    frame.greedy = first;
                    return self.at(kids, frame, step.closed, after, depth + 1);
                }
            }
        }
        self.proceed(after, depth + 1)
    }
    fn fits(&mut self, step: &Step, node: NodeId) -> Result<bool, QueryError> {
        let n = self.tree.node_at(node.index()).expect("checked tree node");
        Ok(match &step.kind {
            Kind::Named => n.is_named(),
            Kind::Name { name, named, under } => {
                self.budget.charge(name.len() + under.len())?;
                n.is_named() == *named
                    && n.name() == name
                    && under.contains(&self.tree.nodes[node.index()].symbol)
            }
            Kind::Category(members) => {
                self.budget.charge(members.len())?;
                members.contains(&self.tree.nodes[node.index()].symbol)
            }
            _ => true,
        })
    }
    fn bind(
        &mut self,
        step: &Step,
        node: NodeId,
        bindings: Option<&Bindings<'q>>,
    ) -> Result<(), QueryError> {
        self.bind_ids(&step.captures, node)?;
        let mut binding = bindings;
        while let Some(value) = binding {
            self.budget.charge(1)?;
            self.bind_ids(value.captures, node)?;
            binding = value.parent.as_deref();
        }
        Ok(())
    }
    fn bind_ids(&mut self, ids: &[CaptureId], node: NodeId) -> Result<(), QueryError> {
        self.budget.charge(ids.len())?;
        let count = self
            .published_captures
            .saturating_add(self.found.len())
            .saturating_add(ids.len());
        if count > self.limits.captures {
            return Err(QueryError::Limit("captures"));
        }
        self.found
            .extend(ids.iter().map(|&id| Capture { id, node }));
        Ok(())
    }
    fn proceed(&mut self, after: &After<'_, 'q, 't>, depth: usize) -> Result<bool, QueryError> {
        self.enter(depth)?;
        match after {
            After::Done { pattern, root } => {
                if self.holds(*pattern)? {
                    if self.held.len() >= self.limits.matches {
                        return Err(QueryError::Limit("matches"));
                    }
                    let count = self.published_captures.saturating_add(self.found.len());
                    if count > self.limits.captures {
                        return Err(QueryError::Limit("captures"));
                    }
                    self.budget.charge(1 + self.found.len())?;
                    self.published_captures = count;
                    let begin = self.tree.nodes[root.index()].span.start();
                    let finish = self.found.last().map_or(begin, |capture| {
                        self.tree.nodes[capture.node.index()].span.start()
                    });
                    self.held.push(Held {
                        pattern: PatternId::from_index(*pattern),
                        begin,
                        finish,
                        captures: self
                            .found
                            .iter()
                            .map(|capture| QueryCapture {
                                id: capture.id,
                                node: self
                                    .tree
                                    .node_at(capture.node.index())
                                    .expect("query captures checked tree node"),
                            })
                            .collect(),
                    });
                }
                // Predicate filtering does not ask a greedy occurrence to shorten.
                Ok(true)
            }
            After::More {
                kids,
                frame,
                closed,
                next,
            } => self.at(kids, frame.clone(), *closed, next, depth + 1),
        }
    }
    fn at(
        &mut self,
        kids: &'t [NodeId],
        frame: Frame<'q>,
        closed: bool,
        after: &After<'_, 'q, 't>,
        depth: usize,
    ) -> Result<bool, QueryError> {
        self.enter(depth)?;
        if frame.si == frame.steps.len() {
            if let Some(up) = &frame.up {
                self.budget.charge(1)?;
                let mut back = (**up).clone();
                back.stalled = frame.ki == up.ki;
                back.ki = frame.ki;
                back.seen = true;
                back.pin = false;
                back.head = frame.head;
                if frame.ki > up.ki {
                    back.bindings = None;
                }
                return self.at(kids, back, closed, after, depth + 1);
            }
            if closed {
                for child in &kids[frame.ki..] {
                    self.budget.charge(1)?;
                    if self
                        .tree
                        .node_at(child.index())
                        .expect("checked node")
                        .is_named()
                    {
                        return Ok(false);
                    }
                }
            }
            return self.proceed(after, depth + 1);
        }
        let query = self.query;
        let id = frame.steps[frame.si];
        let step = &query.steps[id];
        let mark = self.found.len();
        let pin = frame.pin || (step.anchored && (frame.si == 0 || frame.head.is_some()));
        let repeated = matches!(step.quantifier, Quantifier::Star | Quantifier::Plus);
        let first = frame.greedy || repeated;
        let mut matched = false;
        if (!frame.seen || repeated) && !frame.stalled {
            if matches!(step.kind, Kind::Group) {
                self.budget.charge(2)?;
                let mut sub = Frame::new(&step.children, frame.ki);
                sub.pin = pin;
                sub.head = frame.head;
                sub.greedy = first;
                sub.up = Some(Rc::new(frame.clone()));
                sub.bindings = if step.captures.is_empty() && step.field.is_none() {
                    frame.bindings.clone()
                } else {
                    self.budget.charge(1)?;
                    Some(Rc::new(Bindings {
                        captures: &step.captures,
                        field: step.field,
                        parent: frame.bindings.clone(),
                    }))
                };
                matched = self.at(kids, sub, closed, after, depth + 1)?;
                self.found.truncate(mark);
            } else {
                for position in frame.ki..kids.len() {
                    self.budget.charge(1)?;
                    let mut on = frame.clone();
                    on.ki = position + 1;
                    on.seen = true;
                    on.pin = false;
                    on.bindings = None;
                    if on.head.is_none() {
                        on.head = Some(position);
                    }
                    let next = After::More {
                        kids,
                        frame: on,
                        closed,
                        next: after,
                    };
                    let held = self.step(
                        id,
                        kids[position],
                        &next,
                        first,
                        depth + 1,
                        frame.bindings.clone(),
                    )?;
                    self.found.truncate(mark);
                    if held && first {
                        return Ok(true);
                    }
                    matched |= held;
                    if pin
                        && self
                            .tree
                            .node_at(kids[position].index())
                            .expect("checked node")
                            .is_named()
                    {
                        break;
                    }
                }
            }
        }
        if matched {
            return Ok(true);
        }
        if frame.seen || matches!(step.quantifier, Quantifier::Optional | Quantifier::Star) {
            let mut on = frame;
            on.si += 1;
            on.seen = false;
            on.stalled = false;
            if self.at(kids, on, closed, after, depth + 1)? {
                return Ok(true);
            }
            self.found.truncate(mark);
        }
        Ok(false)
    }
    fn text<'a>(&'a self, arg: &'a QueryArgument) -> Option<&'a [u8]> {
        match arg {
            QueryArgument::Text(text) => Some(text),
            QueryArgument::Capture(id) => self
                .found
                .iter()
                .find(|c| c.id == *id)
                .map(|c| &self.tree.source[self.tree.nodes[c.node.index()].span.range()]),
        }
    }
    fn holds(&mut self, index: usize) -> Result<bool, QueryError> {
        let pattern = &self.query.patterns[index];
        for (position, predicate) in pattern.predicates.iter().enumerate() {
            self.budget.charge(
                1usize
                    .saturating_add(self.found.len())
                    .saturating_add(predicate.arguments.len().saturating_mul(2)),
            )?;
            let name = predicate.name.as_str();
            if !core(name) {
                if !name.ends_with('!') && self.foreign == ForeignPolicy::Deny {
                    return Ok(false);
                }
                continue;
            }
            let Some(subject) = self.text(&predicate.arguments[0]) else {
                continue;
            };
            let negative = name.starts_with("not-");
            let holds = match name {
                "eq?" | "not-eq?" => {
                    let Some(other) = self.text(&predicate.arguments[1]) else {
                        continue;
                    };
                    let work = subject.len().min(other.len());
                    // Split field borrows so accounting precedes the comparison.
                    self.budget.charge(work)?;
                    self.text(&predicate.arguments[0]) == self.text(&predicate.arguments[1])
                }
                "any-of?" | "not-any-of?" => {
                    let work = predicate.arguments[1..]
                        .iter()
                        .map(|a| match a {
                            QueryArgument::Text(t) => subject.len().min(t.len()),
                            _ => 0,
                        })
                        .fold(0usize, usize::saturating_add);
                    self.budget.charge(work)?;
                    let subject = self.text(&predicate.arguments[0]).expect("bound subject");
                    predicate.arguments[1..]
                        .iter()
                        .any(|a| matches!(a, QueryArgument::Text(text) if subject == text))
                }
                "match?" | "not-match?" => {
                    self.budget.charge(subject.len() + 1)?;
                    pattern.regexes[position]
                        .as_ref()
                        .expect("compiled core regex")
                        .try_capture_ranges_at(
                            self.text(&predicate.arguments[0]).expect("bound subject"),
                            0,
                        )
                        .map_err(|e| QueryError::Regex {
                            at: predicate.at,
                            message: e.to_string(),
                        })?
                        .is_some()
                }
                _ => unreachable!(),
            };
            if holds == negative {
                return Ok(false);
            }
        }
        Ok(true)
    }
}
