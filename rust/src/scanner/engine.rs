//! Ordered scanner execution with isolated scratch scoring and bounded organs.

use super::{
    Frame, Mark, ScanHit, ScannerError, ScannerState, charge, probe::Captures, program::*,
};
use crate::ids::SymbolId;

#[derive(Clone, Copy, Default)]
struct Facts {
    bol: bool,
    lead: u32,
    blank: bool,
    lull: bool,
    column: u32,
    eof: bool,
    broke: bool,
}
#[derive(Default)]
struct Bound {
    eaten: Option<usize>,
    lead: Option<u32>,
    cursor: usize,
    abstain: bool,
    ran: Option<[usize; 6]>,
    captures: Option<Captures>,
    figures: Vec<i64>,
}
impl Bound {
    fn cursor(&self, at: usize) -> usize {
        at.saturating_add(self.eaten.unwrap_or(0))
    }
}
fn u32_value(n: i64) -> u32 {
    n.clamp(0, u32::MAX as i64) as u32
}
#[derive(Debug)]
pub(super) struct SourceIndex {
    pointer: usize,
    len: usize,
    tab: u32,
    lines: Vec<Line>,
    breaks: Vec<usize>,
}
const MAX_INDEX_ENTRIES: usize = 1 << 20;

#[derive(Debug)]
struct Line {
    start: usize,
    lead: u32,
    blank: bool,
}
impl SourceIndex {
    fn build(source: &[u8], tab: u32, remaining: &mut usize) -> Result<Self, ScannerError> {
        let mut lines = vec![Line {
            start: 0,
            lead: 0,
            blank: true,
        }];
        let mut breaks = Vec::new();
        for (i, &c) in source.iter().enumerate() {
            charge(remaining)?;
            if matches!(c, b'\r' | b'\n') {
                if breaks.len() == MAX_INDEX_ENTRIES {
                    return Err(ScannerError::Limit("line index entries"));
                }
                breaks.push(i);
            }
            if c == b'\n' {
                if lines.len() == MAX_INDEX_ENTRIES {
                    return Err(ScannerError::Limit("line index entries"));
                }
                lines.push(Line {
                    start: i + 1,
                    lead: 0,
                    blank: true,
                });
                continue;
            }
            let line = lines.last_mut().expect("initial line");
            if line.blank {
                match c {
                    b' ' => line.lead = line.lead.saturating_add(1),
                    b'\t' => line.lead = line.lead.saturating_add(tab - line.lead % tab),
                    _ => line.blank = false,
                }
            }
        }
        Ok(Self {
            pointer: source.as_ptr() as usize,
            len: source.len(),
            tab,
            lines,
            breaks,
        })
    }
    fn covers(&self, source: &[u8], tab: u32) -> bool {
        self.pointer == source.as_ptr() as usize && self.len == source.len() && self.tab == tab
    }
    fn facts(&self, at: usize) -> Facts {
        let index = self
            .lines
            .partition_point(|l| l.start <= at)
            .saturating_sub(1);
        let line = &self.lines[index];
        Facts {
            bol: at == line.start,
            lead: line.lead,
            blank: line.blank,
            lull: index > 0 && self.lines[index - 1].blank,
            column: at.saturating_sub(line.start).min(u32::MAX as usize) as u32,
            eof: at >= self.len,
            broke: false,
        }
    }
    fn broke(&self, from: usize, to: usize) -> bool {
        self.breaks.partition_point(|&i| i < from) != self.breaks.partition_point(|&i| i < to)
    }
}
fn soak(
    source: &[u8],
    mut at: usize,
    tab: u32,
    mut col: u32,
    remaining: &mut usize,
) -> Result<(usize, u32), ScannerError> {
    while let Some(&c) = source.get(at) {
        match c {
            b' ' => col = col.saturating_add(1),
            b'\t' => col = col.saturating_add(tab - col % tab),
            _ => break,
        }
        charge(remaining)?;
        at += 1;
    }
    Ok((at, col))
}
fn group<'a>(b: &Bound, source: &'a [u8], n: usize) -> &'a [u8] {
    b.captures.as_ref().map_or(&[], |c| c.group(source, n))
}
fn eval(e: &Expr, o: &ScannerState, f: Facts, b: &Bound, source: &[u8]) -> i64 {
    match e {
        Expr::Num(n) => *n,
        Expr::Lead => b.lead.unwrap_or(f.lead) as i64,
        Expr::Column => f.column as i64,
        Expr::Width => b.eaten.unwrap_or(0) as i64,
        Expr::Cursor => b.cursor as i64,
        Expr::FrameWidth => o.frames.last().map_or(0, |x| x.width) as i64,
        Expr::Frames => o.frames.len() as i64,
        Expr::Marks => o.marks.len() as i64,
        Expr::MarkCount => o.marks.last().map_or(0, |x| x.count) as i64,
        Expr::Pass(i) => b.ran.map_or(0, |r| r[*i]) as i64,
        Expr::Span(i) => group(b, source, *i).len() as i64,
        Expr::Number(i) => b.figures.get(*i).copied().unwrap_or(0),
        Expr::Reg(i) => o.registers[*i] as i64,
        Expr::FrameAt(i) => {
            let i = eval(i, o, f, b, source);
            if i < 0 {
                0
            } else {
                o.frames.get(i as usize).map_or(0, |x| x.width) as i64
            }
        }
        Expr::Bin(op, a, c) => {
            let a = eval(a, o, f, b, source);
            let c = eval(c, o, f, b, source);
            match op {
                Bin::Add => a.saturating_add(c),
                Bin::Sub => a.saturating_sub(c),
                Bin::Max => a.max(c),
                Bin::Min => a.min(c),
            }
        }
    }
}
struct Ask<'a, 'b> {
    book: &'a Book,
    source: &'a [u8],
    index: std::sync::Arc<SourceIndex>,
    fresh: bool,
    wanted: &'a [SymbolId],
    named: &'a [SymbolId],
    broke: bool,
    remaining: &'b mut usize,
}
impl Book {
    #[allow(clippy::too_many_arguments)]
    pub fn step(
        &self,
        o: &mut ScannerState,
        source: &[u8],
        at: usize,
        fresh: bool,
        wanted: &[SymbolId],
        named: &[SymbolId],
        already: &[SymbolId],
        remaining: &mut usize,
    ) -> Result<Option<ScanHit>, ScannerError> {
        if at > source.len() {
            return Ok(None);
        }
        // Sessions retain the same immutable source allocation. The line index
        // is shared by cloned heads and excluded from lexical state equality.
        if !o.index.as_ref().is_some_and(|i| i.covers(source, self.tab)) {
            o.index = Some(std::sync::Arc::new(SourceIndex::build(
                source, self.tab, remaining,
            )?));
        }
        let index = o.index.as_ref().expect("installed index").clone();
        let mut a = Ask {
            book: self,
            source,
            index,
            fresh,
            wanted,
            named,
            broke: false,
            remaining,
        };
        let over = if let Some(p) = self.trivia {
            a.probe(p, at)?.map_or(0, |c| c.width())
        } else {
            0
        };
        a.broke = self.trivia.is_some()
            && a.index
                .broke(o.since.min(at), (at + over).min(source.len()));
        let arrival = at + over;
        let mut plain = a.index.facts(arrival);
        plain.broke = a.broke;
        for phase in Phase::SWEEP {
            if phase == Phase::Layout && !fresh {
                continue;
            }
            let stood = if phase == Phase::Layout {
                soak(
                    source,
                    arrival,
                    self.tab,
                    self.budget.map_or(0, |r| o.registers[r]),
                    a.remaining,
                )?
            } else {
                (arrival, plain.lead)
            };
            let mut f = if phase == Phase::Layout {
                a.index.facts(stood.0)
            } else {
                plain
            };
            f.lead = stood.1;
            f.broke = a.broke;
            for rule in self.rules.iter().filter(|r| r.phase == phase) {
                if phase == Phase::Layout
                    && o.frames.last().is_some_and(|t| {
                        self.opaque & (1 << t.kind) != 0 && rule.closes != Some(t.kind)
                    })
                {
                    continue;
                }
                if !rule.reach.is_empty()
                    && (!rule.reach.iter().any(|s| wanted.contains(s))
                        || rule.reach.iter().all(|s| already.contains(s)))
                {
                    continue;
                }
                let mut b = Bound::default();
                if a.guard(rule, o, stood.0, f, &mut b, 0, false)? && a.admits(rule, stood.0, &b)? {
                    if let Some(mut hit) = a.apply(rule, o, stood.0, &mut b)? {
                        // Layout reads after its initial soak, but the reference
                        // reports only explicit skip actions from the arrival.
                        let layout_over = stood.0 - arrival;
                        hit.start -= layout_over;
                        hit.end -= layout_over;
                        if hit.end > hit.start {
                            o.since = hit.end;
                        }
                        return Ok(Some(hit));
                    }
                    if b.abstain {
                        return Ok(None);
                    }
                }
            }
        }
        Ok(None)
    }
}
impl Ask<'_, '_> {
    fn probe(&mut self, p: usize, at: usize) -> Result<Option<Captures>, ScannerError> {
        self.book.probes[p].capture(self.source, at, self.remaining)
    }
    #[allow(clippy::too_many_arguments)]
    fn guard(
        &mut self,
        r: &Rule,
        o: &ScannerState,
        at: usize,
        f: Facts,
        b: &mut Bound,
        depth: u8,
        scoring: bool,
    ) -> Result<bool, ScannerError> {
        for test in &r.tests {
            charge(self.remaining)?;
            if scoring && matches!(test, Test::Fires { .. }) {
                continue;
            }
            if !self.test(test, o, at, f, b, depth)? {
                return Ok(false);
            }
        }
        Ok(true)
    }
    fn test(
        &mut self,
        t: &Test,
        o: &ScannerState,
        at: usize,
        f: Facts,
        b: &mut Bound,
        depth: u8,
    ) -> Result<bool, ScannerError> {
        Ok(match t {
            Test::Fact(fact, positive) => {
                let yes = match fact {
                    Fact::Bol => f.bol,
                    Fact::Blank => f.blank,
                    Fact::Lull => f.lull,
                    Fact::Broke => f.broke,
                    Fact::Eof => f.eof,
                    Fact::Fresh => self.fresh,
                };
                yes == *positive
            }
            Test::Permission(p, s, positive) => {
                let yes = match p {
                    Permission::Wanted => self.wanted.contains(s),
                    Permission::Named => self.named.contains(s),
                    Permission::Sole => self.wanted == [*s],
                };
                yes == *positive
            }
            Test::Compare(m, cmp, e, index) => {
                let n = match m {
                    Measure::Lead => Some(b.lead.unwrap_or(f.lead) as i64),
                    Measure::Frames => Some(o.frames.len() as i64),
                    Measure::Marks => Some(o.marks.len() as i64),
                    Measure::FrameWidth => o.frames.last().map(|t| t.width as i64),
                    Measure::MarkCount => o.marks.last().map(|t| t.count as i64),
                    Measure::Reg(i) => Some(o.registers[*i] as i64),
                    Measure::FrameAt => index.as_ref().and_then(|e| {
                        let i = eval(e, o, f, b, self.source);
                        if i < 0 {
                            None
                        } else {
                            o.frames.get(i as usize).map(|t| t.width as i64)
                        }
                    }),
                };
                n.is_some_and(|n| cmp.holds(n, eval(e, o, f, b, self.source)))
            }
            Test::Probe(p, positive) => {
                let caps = self.probe(*p, b.cursor(at))?;
                if *positive {
                    if let Some(c) = caps {
                        b.eaten = Some(b.eaten.unwrap_or(0) + c.width());
                        if b.captures.is_none() {
                            // Figure values are derived once from the first
                            // capture. Every examined digit pays the same work
                            // budget as byte loops, including leading zeros.
                            for slot in &c.slots {
                                let mut number = 0i64;
                                if let Some(range) = slot {
                                    for &byte in &self.source[range.clone()] {
                                        if !byte.is_ascii_digit() {
                                            break;
                                        }
                                        charge(self.remaining)?;
                                        number = (number * 10 + (byte - b'0') as i64)
                                            .min(u16::MAX as i64);
                                    }
                                }
                                b.figures.push(number);
                            }
                            b.captures = Some(c);
                        }
                        true
                    } else {
                        false
                    }
                } else {
                    caps.is_none()
                }
            }
            Test::Nest(open, close) => {
                let mut off = b.cursor(at);
                let mut nesting = 1usize;
                while off < self.source.len() && nesting > 0 {
                    charge(self.remaining)?;
                    if let Some(c) = self.probe(*close, off)? {
                        nesting -= 1;
                        off += c.width();
                        if nesting > 0 && c.width() == 0 {
                            off += 1;
                        }
                    } else if let Some(c) = self.probe(*open, off)? {
                        nesting += 1;
                        off += c.width().max(1);
                    } else {
                        off += 1;
                    }
                }
                b.eaten = Some(off - at);
                true
            }
            Test::Soak { to, from, one } => {
                let want = to
                    .as_ref()
                    .map_or(1 << 30, |e| eval(e, o, f, b, self.source));
                let mut col = from.as_ref().map_or_else(
                    || {
                        b.lead
                            .unwrap_or_else(|| self.book.budget.map_or(f.lead, |r| o.registers[r]))
                            as i64
                    },
                    |e| eval(e, o, f, b, self.source),
                );
                let mut off = b.cursor(at);
                let begin = off;
                while off < self.source.len() && col < want && (!one || off == begin) {
                    charge(self.remaining)?;
                    match self.source[off] {
                        b' ' => col += 1,
                        b'\t' => col += self.book.tab as i64 - col.rem_euclid(self.book.tab as i64),
                        _ => break,
                    }
                    off += 1;
                }
                b.eaten = Some(off - at);
                b.lead = Some(u32_value(col));
                true
            }
            Test::Pass {
                start,
                after,
                until,
                compare,
            } => {
                let start = eval(start, o, f, b, self.source).max(0) as usize;
                let (off, lead) = if *after {
                    let (off, col) =
                        soak(self.source, b.cursor(at), self.book.tab, 0, self.remaining)?;
                    (off, Some(col))
                } else {
                    (at, None)
                };
                let until = until
                    .as_ref()
                    .map(|e| eval(e, o, f, b, self.source).max(0) as usize);
                let ran = self.pass(o, off, start, lead, until, depth)?;
                b.ran = Some(ran);
                compare
                    .as_ref()
                    .is_none_or(|(c, e)| c.holds(ran[0] as i64, eval(e, o, f, b, self.source)))
            }
            Test::Kind {
                stack,
                at: index,
                set,
            } => {
                let kind = match stack {
                    Stack::Frames => {
                        if let Some(e) = index {
                            let i = eval(e, o, f, b, self.source);
                            if i < 0 {
                                None
                            } else {
                                o.frames.get(i as usize).map(|x| x.kind)
                            }
                        } else {
                            o.frames.last().map(|x| x.kind)
                        }
                    }
                    Stack::Marks => o.marks.last().map(|x| x.kind),
                };
                kind.is_some_and(|k| set & (1u32 << k) != 0)
            }
            Test::Has(stack, kind) => match stack {
                Stack::Frames => o.frames.iter().any(|x| x.kind == *kind),
                Stack::Marks => o.marks.iter().any(|x| x.kind == *kind),
            },
            Test::Tag {
                any,
                folded,
                group: g,
            } => {
                let saw = g.as_ref().map(|e| {
                    group(
                        b,
                        self.source,
                        eval(e, o, f, b, self.source).max(0) as usize,
                    )
                });
                let same = |m: &Mark| {
                    let got = saw.or_else(|| self.source.get(at..at.saturating_add(m.tag.len())));
                    got.is_some_and(|got| {
                        if *folded {
                            got.eq_ignore_ascii_case(&m.tag)
                        } else {
                            got == m.tag
                        }
                    })
                };
                if *any {
                    o.marks.iter().any(same)
                } else {
                    o.marks.last().is_some_and(same)
                }
            }
            Test::Fires {
                group,
                after,
                from,
                positive,
            } => {
                let (off, lead) = if let Some((off, lead)) = from {
                    (
                        (eval(off, o, f, b, self.source).max(0) as usize).min(self.source.len()),
                        u32_value(eval(lead, o, f, b, self.source)),
                    )
                } else {
                    soak(
                        self.source,
                        if *after { b.cursor(at) } else { at }.min(self.source.len()),
                        self.book.tab,
                        0,
                        self.remaining,
                    )?
                };
                self.scored(*group, o, off, lead, depth)? == *positive
            }
        })
    }
    fn classify(
        &mut self,
        class: usize,
        fallback: SymbolId,
        at: usize,
        width: usize,
    ) -> Result<SymbolId, ScannerError> {
        let text = &self.source
            [at.min(self.source.len())..at.saturating_add(width).min(self.source.len())];
        for (probe, symbol) in &self.book.classes[class] {
            if probe.capture(text, 0, self.remaining)?.is_some() {
                return Ok(*symbol);
            }
        }
        Ok(fallback)
    }
    fn admits(&mut self, r: &Rule, at: usize, b: &Bound) -> Result<bool, ScannerError> {
        let mut emits = false;
        for a in &r.actions {
            if let Action::Emit { symbol, class, .. } = a {
                emits = true;
                let symbol = if let Some(c) = class {
                    self.classify(*c, *symbol, at, b.eaten.unwrap_or(0))?
                } else {
                    *symbol
                };
                if self.wanted.contains(&symbol) {
                    return Ok(true);
                }
            }
        }
        Ok(!emits)
    }
    fn apply(
        &mut self,
        r: &Rule,
        o: &mut ScannerState,
        at: usize,
        b: &mut Bound,
    ) -> Result<Option<ScanHit>, ScannerError> {
        let f = self.index.facts(at);
        let mut hit = None;
        let mut skip = 0usize;
        for a in &r.actions {
            charge(self.remaining)?;
            match a {
                Action::Refuse => return Ok(None),
                Action::Abstain => {
                    b.abstain = true;
                    return Ok(None);
                }
                Action::Emit {
                    symbol,
                    width,
                    class,
                } => {
                    let mut width_value = b.eaten.unwrap_or(0);
                    let symbol = if let Some(c) = class {
                        self.classify(*c, *symbol, at, width_value)?
                    } else {
                        if let Some(e) = width {
                            width_value = eval(e, o, f, b, self.source).max(0) as usize;
                        }
                        *symbol
                    };
                    let start = at
                        .checked_add(skip)
                        .ok_or(ScannerError::Limit("token extent"))?;
                    let end = start
                        .checked_add(width_value)
                        .ok_or(ScannerError::Limit("token extent"))?;
                    if end > self.source.len() {
                        return Err(ScannerError::Program("scanner emitted past input".into()));
                    }
                    hit = Some(ScanHit { symbol, start, end });
                }
                Action::Skip(e) => {
                    skip = skip
                        .checked_add(eval(e, o, f, b, self.source).max(0) as usize)
                        .ok_or(ScannerError::Limit("token extent"))?
                }
                Action::PushFrame(width, kind) => {
                    if o.frames.len() == 96 {
                        return Err(ScannerError::Limit("frames"));
                    }
                    o.frames.push(Frame {
                        width: u32_value(eval(width, o, f, b, self.source)).min(u16::MAX as u32),
                        kind: *kind,
                    });
                }
                Action::PushMark(kind, count, tag) => {
                    let tag = match tag {
                        Tag::Empty => &[][..],
                        Tag::Match => group(b, self.source, 0),
                        Tag::Group(i) => group(b, self.source, *i),
                        Tag::Literal(s) => s,
                    };
                    if o.marks.len() == 64
                        || tag.len() > 24
                        || o.marks.iter().map(|m| m.tag.len()).sum::<usize>() + tag.len() > 192
                    {
                        return Err(ScannerError::Limit("marks or tag bytes"));
                    }
                    o.marks.push(Mark {
                        kind: *kind,
                        count: u32_value(eval(count, o, f, b, self.source)).min(u16::MAX as u32),
                        tag: tag.into(),
                    });
                }
                Action::Pop(stack, until) => match stack {
                    Stack::Frames => {
                        while let Some(top) = o.frames.pop() {
                            if until.is_none_or(|kind| kind == top.kind) {
                                break;
                            }
                        }
                    }
                    Stack::Marks => {
                        while let Some(top) = o.marks.pop() {
                            if until.is_none_or(|kind| kind == top.kind) {
                                break;
                            }
                        }
                    }
                },
                Action::Set(i, e) => o.registers[*i] = u32_value(eval(e, o, f, b, self.source)),
            }
        }
        Ok(hit)
    }
    fn pass(
        &mut self,
        o: &ScannerState,
        at: usize,
        start: usize,
        lead: Option<u32>,
        until: Option<usize>,
        depth: u8,
    ) -> Result<[usize; 6], ScannerError> {
        if depth >= 2 {
            return Ok([0, start, 0, 0, at, usize::from(start < o.frames.len())]);
        }
        super::charge_work(self.remaining, o.clone_work())?;
        let mut scratch = o.clone();
        if let (Some(lead), Some(reg)) = (lead, self.book.budget) {
            scratch.registers[reg] = lead;
        }
        let mut off = at;
        let mut ran = 0;
        let mut cursor = start;
        let ceiling = until
            .unwrap_or(scratch.frames.len())
            .min(scratch.frames.len());
        while cursor < ceiling {
            charge(self.remaining)?;
            let mut f = self.index.facts(off);
            f.lead = self.book.budget.map_or(0, |r| scratch.registers[r]);
            let Some(kind) = scratch.frames.get(cursor).map(|x| x.kind) else {
                break;
            };
            let mut took = None;
            for rule in self
                .book
                .rules
                .iter()
                .filter(|r| r.phase == Phase::Matched && r.kind == Some(kind))
            {
                let mut b = Bound {
                    cursor,
                    ..Bound::default()
                };
                if self.guard(rule, &scratch, off, f, &mut b, depth + 1, false)? {
                    self.apply(rule, &mut scratch, off, &mut b)?;
                    took = b.eaten;
                    break;
                }
            }
            let Some(width) = took else {
                break;
            };
            off += width;
            ran += 1;
            cursor += 1;
        }
        Ok([
            ran,
            cursor,
            self.book.budget.map_or(0, |r| scratch.registers[r]) as usize,
            off - at,
            off,
            usize::from(cursor < scratch.frames.len()),
        ])
    }
    fn scored(
        &mut self,
        group: u32,
        o: &ScannerState,
        at: usize,
        lead: u32,
        depth: u8,
    ) -> Result<bool, ScannerError> {
        if depth >= 2 {
            return Ok(false);
        }
        let mut f = self.index.facts(at);
        f.lead = lead;
        for rule in self
            .book
            .rules
            .iter()
            .filter(|r| r.groups & (1u32 << group) != 0)
        {
            if self.guard(rule, o, at, f, &mut Bound::default(), depth + 1, true)? {
                return Ok(true);
            }
        }
        Ok(false)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::compiler::Automaton;
    use serde_json::{Value, json};
    fn graph() -> Automaton {
        Automaton::from_tree_sitter(&serde_json::to_vec(&json!({"name":"engine-test","externals":[{"type":"SYMBOL","name":"answer"},{"type":"SYMBOL","name":"other"}],"rules":{"doc":{"type":"STRING","value":"x"}}})).unwrap()).unwrap()
    }
    fn book(graph: &Automaton, rules: Value) -> Book {
        Book::compile(&json!({"kinds":{"outer":1,"inner":2},"probes":{"a":"(a)","b":"(b)","space":"( *)(x)","open":"/\\*","close":"\\*/"},"rules":rules}).to_string(),graph).unwrap()
    }
    fn run(
        book: &Book,
        state: &mut ScannerState,
        source: &[u8],
        wanted: &[SymbolId],
    ) -> Option<ScanHit> {
        book.step(state, source, 0, true, wanted, wanted, &[], &mut 10000)
            .unwrap()
    }
    #[test]
    fn first_probe_captures_action_order_and_snapshot_replay_are_exact() {
        let g = graph();
        let answer = g.external_by_name("answer").unwrap();
        let b = book(
            &g,
            json!([{"phase":"inside","when":[["probe","a"],["probe","b"]],"then":[["emit","answer",["span",1]],["push","marks","outer",["span",1],["group",1]]]}]),
        );
        let mut state = ScannerState::default();
        let saved = state.clone();
        let hit = run(&b, &mut state, b"ab", &[answer]).unwrap();
        assert_eq!((hit.start, hit.end), (0, 1));
        assert_eq!(state.marks[0].tag, b"a");
        assert_eq!(state.marks[0].count, 1);
        let after = state.clone();
        state = saved;
        assert_eq!(run(&b, &mut state, b"ab", &[answer]), Some(hit));
        assert_eq!(state, after);
        let b = book(
            &g,
            json!([{"phase":"inside","when":[["probe","space"]],"then":[["skip",["span",1]],["emit","answer",["span",2]]]}]),
        );
        let hit = run(&b, &mut ScannerState::default(), b"   x", &[answer]).unwrap();
        assert_eq!((hit.start, hit.end), (3, 4));
    }
    #[test]
    fn denied_emission_has_no_effect_but_refuse_and_abstain_keep_prior_writes() {
        let g = graph();
        let answer = g.external_by_name("answer").unwrap();
        let other = g.external_by_name("other").unwrap();
        let b = book(
            &g,
            json!([{"phase":"inside","then":[["push","frames",4,"outer"],["emit","other",0]]},{"phase":"inside","then":[["set",0,7],["refuse"]]},{"phase":"inside","then":[["emit","answer",0]]}]),
        );
        let mut state = ScannerState::default();
        assert!(run(&b, &mut state, b"", &[answer]).is_some());
        assert!(state.frames.is_empty());
        assert_eq!(state.registers[0], 7);
        assert!(run(&b, &mut ScannerState::default(), b"", &[other]).is_some());
        let b = book(
            &g,
            json!([{"phase":"inside","then":[["set",0,8],["abstain"]]},{"phase":"inside","then":[["emit","answer",0]]}]),
        );
        let mut state = ScannerState::default();
        assert!(run(&b, &mut state, b"", &[answer]).is_none());
        assert_eq!(state.registers[0], 8);
    }
    #[test]
    fn nested_comments_and_scored_guards_do_not_commit_scratch_actions() {
        let g = graph();
        let answer = g.external_by_name("answer").unwrap();
        let b = book(
            &g,
            json!([{"phase":"opening","groups":["opening"],"when":[["probe","a"]],"then":[["set",0,99]]},{"phase":"inside","when":[["fires","opening"]],"then":[["emit","answer",1]]}]),
        );
        let mut state = ScannerState::default();
        assert_eq!(run(&b, &mut state, b"a", &[answer]).unwrap().end, 1);
        assert_eq!(state.registers[0], 0);
        let b = book(
            &g,
            json!([{"phase":"inside","when":[["probe","open"],["nest","open","close"]],"then":[["emit","answer"]]}]),
        );
        let source = b"/*a/*b*/c*/";
        assert_eq!(
            run(&b, &mut ScannerState::default(), source, &[answer])
                .unwrap()
                .end,
            source.len()
        );
    }
    #[test]
    fn zero_width_cycles_and_byte_loops_have_independent_finite_limits() {
        let g = graph();
        let answer = g.external_by_name("answer").unwrap();
        let b = book(
            &g,
            json!([{"phase":"inside","then":[["emit","answer",0],["push","frames",1,"outer"]]}]),
        );
        let mut state = ScannerState::default();
        for _ in 0..96 {
            run(&b, &mut state, b"", &[answer]).unwrap();
        }
        assert!(matches!(
            b.step(
                &mut state,
                b"",
                0,
                true,
                &[answer],
                &[answer],
                &[],
                &mut 100
            ),
            Err(ScannerError::Limit("frames"))
        ));
        let b = book(
            &g,
            json!([{"phase":"inside","when":[["probe","open"],["nest","open","close"]],"then":[["emit","answer"]]}]),
        );
        assert!(matches!(
            b.step(
                &mut ScannerState::default(),
                b"/* long unclosed",
                0,
                true,
                &[answer],
                &[answer],
                &[],
                &mut 4
            ),
            Err(ScannerError::Limit("program work"))
        ));
    }
}

#[cfg(test)]
mod scaling {
    use super::*;
    use crate::compiler::Automaton;
    use serde_json::json;
    fn work(n: usize) -> usize {
        let grammar=Automaton::from_tree_sitter(&serde_json::to_vec(&json!({"name":"line-index","externals":[{"type":"SYMBOL","name":"answer"}],"rules":{"doc":{"type":"STRING","value":"x"}}})).unwrap()).unwrap();
        let symbol = grammar.external_by_name("answer").unwrap();
        let book=Book::compile(&json!({"rules":[{"phase":"inside","when":[["wanted","answer"]],"then":[["emit","answer",1]]}]}).to_string(),&grammar).unwrap();
        let source = vec![b'a'; n];
        let mut state = ScannerState::default();
        let mut remaining = usize::MAX;
        for at in 0..n {
            assert_eq!(
                book.step(
                    &mut state,
                    &source,
                    at,
                    true,
                    &[symbol],
                    &[symbol],
                    &[],
                    &mut remaining
                )
                .unwrap()
                .unwrap()
                .end,
                at + 1
            );
        }
        usize::MAX - remaining
    }
    #[test]
    fn repeated_asks_on_one_long_line_charge_linear_source_work() {
        let a = work(8192);
        let b = work(16384);
        eprintln!("book line-index work 8192 bytes: {a}; 16384 bytes: {b}");
        assert_eq!(a, 8192 * 3);
        assert_eq!(b, a * 2);
    }
    #[test]
    fn line_index_facts_and_gap_breaks_match_crlf_and_blank_lines() {
        let source = b"a\r\n\t\n  b";
        let index = SourceIndex::build(source, 8, &mut 100).unwrap();
        assert!(index.facts(7).lull);
        assert_eq!(index.facts(7).lead, 2);
        assert_eq!(index.facts(7).column, 2);
        assert!(index.broke(1, 2));
        assert!(!index.broke(0, 1));
    }

    #[test]
    fn source_index_copy_work_is_constant_and_shares_the_allocation() {
        let mut state = ScannerState::default();
        let cost = state.clone_work();
        let source = vec![b'\n'; 4096];
        state.index = Some(std::sync::Arc::new(
            SourceIndex::build(&source, 8, &mut 5000).unwrap(),
        ));
        assert_eq!(state.clone_work(), cost + 1);
        let copy = state.clone();
        assert!(std::sync::Arc::ptr_eq(
            state.index.as_ref().unwrap(),
            copy.index.as_ref().unwrap()
        ));
    }
}
