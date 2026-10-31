//! A closed, validated scanner instruction set compiled from the checked-in books.

use super::{ScannerError, probe::Probe};
use crate::{compiler::Automaton, ids::SymbolId};
use serde_json::{Map, Value};
use std::collections::BTreeMap;

pub(super) const SWIFT_BOOK: &str = include_str!("../../../customary/swift.json");

pub(super) const BOOKS: [&str; 8] = [
    include_str!("../../../customary/elixir.json"),
    SWIFT_BOOK,
    include_str!("../../../customary/markdown.json"),
    include_str!("../../../customary/yaml.json"),
    include_str!("../../../customary/scala.json"),
    include_str!("../../../customary/html.json"),
    include_str!("../../../customary/haskell.json"),
    include_str!("../../../customary/kotlin.json"),
];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum Phase {
    Inside,
    Matched,
    Layout,
    Commanded,
    Opening,
    Enclosing,
    Bounded,
    Ordered,
}
impl Phase {
    pub(super) const SWEEP: [Self; 7] = [
        Self::Inside,
        Self::Layout,
        Self::Commanded,
        Self::Opening,
        Self::Enclosing,
        Self::Bounded,
        Self::Ordered,
    ];
}
#[derive(Clone, Copy, Debug)]
pub(super) enum Cmp {
    Eq,
    Ne,
    Lt,
    Le,
    Gt,
    Ge,
}
impl Cmp {
    pub(super) fn holds(self, a: i64, b: i64) -> bool {
        match self {
            Self::Eq => a == b,
            Self::Ne => a != b,
            Self::Lt => a < b,
            Self::Le => a <= b,
            Self::Gt => a > b,
            Self::Ge => a >= b,
        }
    }
}
#[derive(Clone, Debug)]
pub(super) enum Expr {
    Num(i64),
    Lead,
    Column,
    Width,
    Cursor,
    FrameWidth,
    Frames,
    Marks,
    MarkCount,
    Pass(usize),
    Span(usize),
    Number(usize),
    Reg(usize),
    FrameAt(Box<Self>),
    Bin(Bin, Box<Self>, Box<Self>),
}
#[derive(Clone, Copy, Debug)]
pub(super) enum Bin {
    Add,
    Sub,
    Max,
    Min,
}
#[derive(Clone, Copy, Debug)]
pub(super) enum Fact {
    Bol,
    Blank,
    Lull,
    Broke,
    Eof,
    Fresh,
}
#[derive(Clone, Copy, Debug)]
pub(super) enum Permission {
    Wanted,
    Named,
    Sole,
}
#[derive(Clone, Copy, Debug)]
pub(super) enum Measure {
    Lead,
    Frames,
    Marks,
    FrameWidth,
    MarkCount,
    Reg(usize),
    FrameAt,
}
#[derive(Debug)]
pub(super) enum Test {
    Fact(Fact, bool),
    Permission(Permission, SymbolId, bool),
    Compare(Measure, Cmp, Expr, Option<Expr>),
    Probe(usize, bool),
    Nest(usize, usize),
    Soak {
        to: Option<Expr>,
        from: Option<Expr>,
        one: bool,
    },
    Pass {
        start: Expr,
        after: bool,
        until: Option<Expr>,
        compare: Option<(Cmp, Expr)>,
    },
    Kind {
        stack: Stack,
        at: Option<Expr>,
        set: u32,
    },
    Has(Stack, u8),
    Tag {
        any: bool,
        folded: bool,
        group: Option<Expr>,
    },
    Fires {
        group: u32,
        after: bool,
        from: Option<(Expr, Expr)>,
        positive: bool,
    },
}
#[derive(Clone, Copy, Debug)]
pub(super) enum Stack {
    Frames,
    Marks,
}
#[derive(Debug)]
pub(super) enum Tag {
    Empty,
    Match,
    Group(usize),
    Literal(Vec<u8>),
}
#[derive(Debug)]
pub(super) enum Action {
    Emit {
        symbol: SymbolId,
        width: Option<Expr>,
        class: Option<usize>,
    },
    Skip(Expr),
    PushFrame(Expr, u8),
    PushMark(u8, Expr, Tag),
    Pop(Stack, Option<u8>),
    Set(usize, Expr),
    Refuse,
    Abstain,
}
#[derive(Debug)]
pub(super) struct Rule {
    pub phase: Phase,
    pub kind: Option<u8>,
    pub closes: Option<u8>,
    pub groups: u32,
    pub tests: Vec<Test>,
    pub actions: Vec<Action>,
    pub reach: Vec<SymbolId>,
}
#[derive(Debug)]
pub(super) struct Book {
    pub tab: u32,
    pub budget: Option<usize>,
    pub trivia: Option<usize>,
    pub opaque: u32,
    pub probes: Vec<Probe>,
    pub classes: Vec<Vec<(Probe, SymbolId)>>,
    pub rules: Vec<Rule>,
}

fn bad(s: impl Into<String>) -> ScannerError {
    ScannerError::Program(s.into())
}
fn word(v: &Value) -> Result<&str, ScannerError> {
    v.as_str().ok_or_else(|| bad("expected scanner name"))
}
fn array(v: &Value) -> Result<&[Value], ScannerError> {
    v.as_array()
        .map(Vec::as_slice)
        .ok_or_else(|| bad("expected scanner list"))
}
fn object(v: &Value) -> Result<&Map<String, Value>, ScannerError> {
    v.as_object().ok_or_else(|| bad("expected scanner object"))
}
fn integer(v: &Value) -> Result<i64, ScannerError> {
    v.as_i64().ok_or_else(|| bad("expected scanner integer"))
}
fn get<'a>(o: &'a Map<String, Value>, k: &str) -> Result<&'a Value, ScannerError> {
    o.get(k).ok_or_else(|| bad(format!("missing scanner {k}")))
}
fn reg(v: &Value) -> Result<usize, ScannerError> {
    let n = integer(v)?;
    if !(0..8).contains(&n) {
        return Err(bad("register outside 0..8"));
    }
    usize::try_from(n).map_err(|_| bad("scanner index out of range"))
}
fn cmp(v: &Value) -> Result<Cmp, ScannerError> {
    Ok(match word(v)? {
        "=" | "==" => Cmp::Eq,
        "!=" => Cmp::Ne,
        "<" => Cmp::Lt,
        "<=" => Cmp::Le,
        ">" => Cmp::Gt,
        ">=" => Cmp::Ge,
        s => return Err(bad(format!("unknown scanner comparison {s}"))),
    })
}
fn expr(v: &Value, depth: usize) -> Result<Expr, ScannerError> {
    if depth > 32 {
        return Err(ScannerError::Limit("value depth"));
    }
    if let Some(n) = v.as_i64() {
        return Ok(Expr::Num(n));
    }
    if let Some(s) = v.as_str() {
        return Ok(match s {
            "lead" => Expr::Lead,
            "column" => Expr::Column,
            "width" | "eaten" => Expr::Width,
            "cursor" => Expr::Cursor,
            "frames.top.width" => Expr::FrameWidth,
            "frames.depth" => Expr::Frames,
            "marks.depth" => Expr::Marks,
            "marks.top.count" => Expr::MarkCount,
            "pass.ran" => Expr::Pass(0),
            "pass.cursor" => Expr::Pass(1),
            "pass.budget" => Expr::Pass(2),
            "pass.eaten" => Expr::Pass(3),
            "pass.at" => Expr::Pass(4),
            "pass.more" => Expr::Pass(5),
            _ => return Err(bad(format!("unknown scanner value {s}"))),
        });
    }
    let a = array(v)?;
    let op = word(a.first().ok_or_else(|| bad("empty value"))?)?;
    if a.len() == 2 {
        return Ok(match op {
            "span" => Expr::Span(capture(&a[1])?),
            "number" => Expr::Number(capture(&a[1])?),
            "reg" => Expr::Reg(reg(&a[1])?),
            "frames.at.width" => Expr::FrameAt(Box::new(expr(&a[1], depth + 1)?)),
            _ => return Err(bad(format!("unknown scanner value {op}"))),
        });
    }
    if a.len() != 3 {
        return Err(bad("value arity"));
    }
    let op = match op {
        "+" => Bin::Add,
        "-" => Bin::Sub,
        "max" => Bin::Max,
        "min" => Bin::Min,
        _ => return Err(bad("unknown binary scanner value")),
    };
    Ok(Expr::Bin(
        op,
        Box::new(expr(&a[1], depth + 1)?),
        Box::new(expr(&a[2], depth + 1)?),
    ))
}
fn capture(v: &Value) -> Result<usize, ScannerError> {
    let n = integer(v)?;
    if !(0..32).contains(&n) {
        return Err(bad("capture outside 0..32"));
    }
    usize::try_from(n).map_err(|_| bad("scanner index out of range"))
}

struct Reader<'a> {
    grammar: &'a Automaton,
    kinds: BTreeMap<String, u8>,
    probes: BTreeMap<String, usize>,
    classes: BTreeMap<String, usize>,
    groups: BTreeMap<String, u32>,
}
impl Reader<'_> {
    fn terminal(&self, v: &Value, _emit: bool) -> Result<SymbolId, ScannerError> {
        let name = word(v)?;
        // Permission tests may name external terminals too. The compiler's
        // ordinary-terminal resolver deliberately excludes Pattern::External.
        self.grammar
            .external_by_name(name)
            .or_else(|| self.grammar.terminal_by_name(name))
            .ok_or_else(|| bad(format!("unknown scanner terminal {name}")))
    }
    fn kind(&self, v: &Value) -> Result<u8, ScannerError> {
        if let Some(n) = v.as_i64() {
            return if (1..32).contains(&n) {
                u8::try_from(n).map_err(|_| bad("kind outside 1..32"))
            } else {
                Err(bad("kind outside 1..32"))
            };
        }
        self.kinds
            .get(word(v)?)
            .copied()
            .ok_or_else(|| bad("unknown scanner kind"))
    }
    fn set(&self, how: &Value, v: &Value) -> Result<u32, ScannerError> {
        match word(how)? {
            "=" => Ok(1u32 << self.kind(v)?),
            "in" => array(v)?
                .iter()
                .try_fold(0, |bits, v| Ok(bits | (1u32 << self.kind(v)?))),
            _ => Err(bad("kind comparison must be = or in")),
        }
    }
    fn probe(&self, v: &Value) -> Result<usize, ScannerError> {
        self.probes
            .get(word(v)?)
            .copied()
            .ok_or_else(|| bad("unknown scanner probe"))
    }
    fn test(&self, v: &Value) -> Result<Test, ScannerError> {
        let a = array(v)?;
        let op = word(a.first().ok_or_else(|| bad("empty test"))?)?;
        let arity = |n| {
            if a.len() == n {
                Ok(())
            } else {
                Err(bad(format!("{op}: test arity")))
            }
        };
        let positive = !op.starts_with("not_");
        let bare = match op {
            "bol" | "not_bol" => Some(Fact::Bol),
            "blank" | "not_blank" => Some(Fact::Blank),
            "lull" | "not_lull" => Some(Fact::Lull),
            "broke" | "not_broke" => Some(Fact::Broke),
            "eof" | "not_eof" => Some(Fact::Eof),
            "fresh" => Some(Fact::Fresh),
            _ => None,
        };
        if let Some(f) = bare {
            arity(1)?;
            return Ok(Test::Fact(f, positive));
        }
        let permission = match op {
            "wanted" | "not_wanted" => Some(Permission::Wanted),
            "named" | "not_named" => Some(Permission::Named),
            "sole" => Some(Permission::Sole),
            _ => None,
        };
        if let Some(p) = permission {
            arity(2)?;
            return Ok(Test::Permission(p, self.terminal(&a[1], false)?, positive));
        }
        let measure = match op {
            "lead" => Some(Measure::Lead),
            "frames.depth" => Some(Measure::Frames),
            "marks.depth" => Some(Measure::Marks),
            "frames.top.width" => Some(Measure::FrameWidth),
            "marks.top.count" => Some(Measure::MarkCount),
            _ => None,
        };
        if let Some(m) = measure {
            arity(3)?;
            return Ok(Test::Compare(m, cmp(&a[1])?, expr(&a[2], 0)?, None));
        }
        Ok(match op {
            "probe" | "probe_at" | "no_probe" => {
                arity(2)?;
                Test::Probe(self.probe(&a[1])?, op != "no_probe")
            }
            "nest" => {
                arity(3)?;
                Test::Nest(self.probe(&a[1])?, self.probe(&a[2])?)
            }
            "soak" => {
                let (mut to, mut from, mut one) = (None, None, false);
                let mut i = 1;
                while i < a.len() {
                    match word(&a[i])? {
                        "one" => one = true,
                        "to" => {
                            i += 1;
                            to = Some(expr(a.get(i).ok_or_else(|| bad("soak to"))?, 0)?);
                        }
                        "from" => {
                            i += 1;
                            from = Some(expr(a.get(i).ok_or_else(|| bad("soak from"))?, 0)?);
                        }
                        _ => return Err(bad("unknown soak modifier")),
                    }
                    i += 1;
                }
                Test::Soak { to, from, one }
            }
            "pass" => {
                if a.len() < 2 {
                    return Err(bad("pass arity"));
                }
                let (mut after, mut until, mut compare) = (false, None, None);
                let mut i = 2;
                while i < a.len() {
                    match word(&a[i])? {
                        "after" => after = true,
                        "until" => {
                            i += 1;
                            until = Some(expr(a.get(i).ok_or_else(|| bad("pass until"))?, 0)?);
                        }
                        _ => {
                            if i + 2 != a.len() {
                                return Err(bad("pass comparison"));
                            }
                            compare = Some((cmp(&a[i])?, expr(&a[i + 1], 0)?));
                            break;
                        }
                    }
                    i += 1;
                }
                Test::Pass {
                    start: expr(&a[1], 0)?,
                    after,
                    until,
                    compare,
                }
            }
            "frames.top.kind" | "marks.top.kind" => {
                arity(3)?;
                Test::Kind {
                    stack: if op.starts_with('f') {
                        Stack::Frames
                    } else {
                        Stack::Marks
                    },
                    at: None,
                    set: self.set(&a[1], &a[2])?,
                }
            }
            "frames.at.kind" => {
                arity(4)?;
                Test::Kind {
                    stack: Stack::Frames,
                    at: Some(expr(&a[1], 0)?),
                    set: self.set(&a[2], &a[3])?,
                }
            }
            "frames.at.width" => {
                arity(4)?;
                Test::Compare(
                    Measure::FrameAt,
                    cmp(&a[2])?,
                    expr(&a[3], 0)?,
                    Some(expr(&a[1], 0)?),
                )
            }
            "frames.has" | "marks.has" => {
                arity(2)?;
                Test::Has(
                    if op.starts_with('f') {
                        Stack::Frames
                    } else {
                        Stack::Marks
                    },
                    self.kind(&a[1])?,
                )
            }
            "marks.top.tag" | "marks.has.tag" => {
                let (mut folded, mut group) = (false, None);
                let mut i = 1;
                while i < a.len() {
                    match word(&a[i])? {
                        "folded" => folded = true,
                        "group" => {
                            i += 1;
                            group = Some(expr(a.get(i).ok_or_else(|| bad("tag group"))?, 0)?);
                        }
                        _ => return Err(bad("unknown tag modifier")),
                    }
                    i += 1;
                }
                Test::Tag {
                    any: op == "marks.has.tag",
                    folded,
                    group,
                }
            }
            "reg" => {
                arity(4)?;
                Test::Compare(
                    Measure::Reg(reg(&a[1])?),
                    cmp(&a[2])?,
                    expr(&a[3], 0)?,
                    None,
                )
            }
            "fires" | "no_fires" => {
                if a.len() < 2 {
                    return Err(bad("fires arity"));
                }
                let group = *self
                    .groups
                    .get(word(&a[1])?)
                    .ok_or_else(|| bad("unknown rule group"))?;
                let (mut after, mut from) = (false, None);
                if a.len() > 2 {
                    match word(&a[2])? {
                        "after" => {
                            arity(3)?;
                            after = true;
                        }
                        "from" => {
                            if !(4..=5).contains(&a.len()) {
                                return Err(bad("fires from arity"));
                            }
                            from = Some((
                                expr(&a[3], 0)?,
                                if a.len() == 5 {
                                    expr(&a[4], 0)?
                                } else {
                                    Expr::Num(0)
                                },
                            ));
                        }
                        _ => return Err(bad("unknown fires modifier")),
                    }
                }
                Test::Fires {
                    group,
                    after,
                    from,
                    positive: op == "fires",
                }
            }
            _ => return Err(bad(format!("unknown scanner test {op}"))),
        })
    }
    fn action(&self, v: &Value) -> Result<Action, ScannerError> {
        let a = array(v)?;
        let op = word(a.first().ok_or_else(|| bad("empty action"))?)?;
        let at = |n| {
            a.get(n)
                .ok_or_else(|| bad(format!("{op}: missing action argument")))
        };
        Ok(match op {
            "refuse" if a.len() == 1 => Action::Refuse,
            "abstain" if a.len() == 1 => Action::Abstain,
            "emit" => {
                let symbol = self.terminal(at(1)?, true)?;
                let (mut width, mut class) = (None, None);
                if a.len() == 4 && word(&a[2])? == "classified" {
                    class = Some(
                        *self
                            .classes
                            .get(word(&a[3])?)
                            .ok_or_else(|| bad("unknown classifier"))?,
                    );
                } else if a.len() == 3 {
                    width = Some(expr(&a[2], 0)?);
                } else if a.len() != 2 {
                    return Err(bad("emit arity"));
                }
                Action::Emit {
                    symbol,
                    width,
                    class,
                }
            }
            "skip" if a.len() == 2 => Action::Skip(expr(&a[1], 0)?),
            "set" if a.len() == 3 => Action::Set(reg(&a[1])?, expr(&a[2], 0)?),
            "push" => match word(at(1)?)? {
                "frames" if a.len() == 4 => Action::PushFrame(expr(&a[2], 0)?, self.kind(&a[3])?),
                "marks" if (4..=5).contains(&a.len()) => {
                    let tag = if a.len() == 4 {
                        Tag::Empty
                    } else if let Some(s) = a[4].as_str() {
                        if s == "match" {
                            Tag::Match
                        } else {
                            Tag::Literal(s.as_bytes().into())
                        }
                    } else {
                        let x = array(&a[4])?;
                        if x.len() != 2 || word(&x[0])? != "group" {
                            return Err(bad("mark tag"));
                        }
                        Tag::Group(capture(&x[1])?)
                    };
                    Action::PushMark(self.kind(&a[2])?, expr(&a[3], 0)?, tag)
                }
                _ => return Err(bad("push shape")),
            },
            "pop" => {
                let stack = match word(at(1)?)? {
                    "frames" => Stack::Frames,
                    "marks" => Stack::Marks,
                    _ => return Err(bad("pop stack")),
                };
                let until = if a.len() == 4 && word(&a[2])? == "until" {
                    Some(self.kind(&a[3])?)
                } else if a.len() == 2 {
                    None
                } else {
                    return Err(bad("pop arity"));
                };
                Action::Pop(stack, until)
            }
            _ => return Err(bad(format!("unknown scanner action {op}"))),
        })
    }
}

impl Book {
    pub(super) fn matches(source: &str, grammar: &Automaton) -> Result<bool, ScannerError> {
        if source.len() > 1 << 20 {
            return Err(ScannerError::Limit("book bytes"));
        }
        let crate::compiler::UniqueValue(v) =
            serde_json::from_str(source).map_err(|e| bad(e.to_string()))?;
        let cohort = array(get(object(&v)?, "cohort")?)?;
        if cohort.is_empty() {
            return Err(bad("empty scanner cohort"));
        }
        Ok(cohort
            .iter()
            .all(|v| word(v).is_ok_and(|s| grammar.external_by_name(s).is_some())))
    }
    #[cfg(test)]
    pub(super) fn compile(source: &str, grammar: &Automaton) -> Result<Self, ScannerError> {
        Self::compile_with_limits(source, grammar, super::ProbeLimits::default())
    }
    pub(super) fn compile_with_limits(
        source: &str,
        grammar: &Automaton,
        limits: super::ProbeLimits,
    ) -> Result<Self, ScannerError> {
        limits.validate()?;
        if source.len() > 1 << 20 {
            return Err(ScannerError::Limit("book bytes"));
        }
        let crate::compiler::UniqueValue(v) =
            serde_json::from_str(source).map_err(|e| bad(e.to_string()))?;
        let o = object(&v)?;
        for key in o.keys() {
            if ![
                "tab",
                "budget",
                "asks",
                "trivia",
                "opaque",
                "kinds",
                "probes",
                "classes",
                "rules",
                "grammar",
                "note",
                "notes",
                "cohort",
                "organs",
                "registers",
            ]
            .contains(&key.as_str())
            {
                return Err(bad(format!("unknown scanner key {key}")));
            }
        }
        let tab = o.get("tab").map(integer).transpose()?.unwrap_or(8);
        if !(1..=256).contains(&tab) {
            return Err(bad("tab outside 1..256"));
        }
        if let Some(asks) = o.get("asks") {
            if !["line", "token"].contains(&word(asks)?) {
                return Err(bad("unknown scanner ask point"));
            }
        }
        // Refuse aggregate native-program counts before compiling any probe.
        // Classifier arms own compiled probes just as the named probe map does.
        let raw = array(get(o, "rules")?)?;
        let mut probe_count = o
            .get("probes")
            .map(object)
            .transpose()?
            .map_or(0, |p| p.len());
        if let Some(classes) = o.get("classes") {
            for arms in object(classes)?.values() {
                probe_count = probe_count.saturating_add(array(arms)?.len());
            }
        }
        if raw.len() > 4096 || probe_count > 1024 {
            return Err(ScannerError::Limit("book instructions"));
        }
        let mut r = Reader {
            grammar,
            kinds: BTreeMap::new(),
            probes: BTreeMap::new(),
            classes: BTreeMap::new(),
            groups: BTreeMap::new(),
        };
        if let Some(k) = o.get("kinds") {
            for (n, v) in object(k)? {
                r.kinds.insert(n.clone(), r.kind(v)?);
            }
        }
        let opaque = o
            .get("opaque")
            .map(|v| {
                array(v)?
                    .iter()
                    .try_fold(0, |bits, v| Ok::<_, ScannerError>(bits | (1 << r.kind(v)?)))
            })
            .transpose()?
            .unwrap_or(0);
        let mut probes = Vec::new();
        if let Some(p) = o.get("probes") {
            for (n, p) in object(p)? {
                r.probes.insert(n.clone(), probes.len());
                probes.push(Probe::compile_with_limits(word(p)?, false, limits)?);
            }
        }
        let trivia = o.get("trivia").map(|v| r.probe(v)).transpose()?;
        let mut classes = Vec::new();
        if let Some(c) = o.get("classes") {
            for (n, arms) in object(c)? {
                r.classes.insert(n.clone(), classes.len());
                let mut class = Vec::new();
                for arm in array(arms)? {
                    let a = array(arm)?;
                    if a.len() != 2 {
                        return Err(bad("classifier arity"));
                    }
                    class.push((
                        Probe::compile_with_limits(word(&a[0])?, true, limits)?,
                        r.terminal(&a[1], true)?,
                    ));
                }
                classes.push(class);
            }
        }
        for rule in raw {
            if let Some(groups) = object(rule)?.get("groups") {
                for group in array(groups)? {
                    let n = word(group)?;
                    if !r.groups.contains_key(n) {
                        if r.groups.len() == 32 {
                            return Err(ScannerError::Limit("rule groups"));
                        }
                        r.groups.insert(
                            n.into(),
                            u32::try_from(r.groups.len()).expect("at most 32 rule groups"),
                        );
                    }
                }
            }
        }
        let mut rules = Vec::new();
        for rule in raw {
            let rule = object(rule)?;
            for key in rule.keys() {
                if ![
                    "name", "phase", "kind", "closes", "groups", "when", "then", "note", "why",
                ]
                .contains(&key.as_str())
                {
                    return Err(bad(format!("unknown rule key {key}")));
                }
            }
            let phase = match word(get(rule, "phase")?)? {
                "inside" => Phase::Inside,
                "matched" => Phase::Matched,
                "layout" => Phase::Layout,
                "commanded" => Phase::Commanded,
                "opening" => Phase::Opening,
                "enclosing" => Phase::Enclosing,
                "bounded" => Phase::Bounded,
                "ordered" => Phase::Ordered,
                _ => return Err(bad("unknown scanner phase")),
            };
            let kind = rule.get("kind").map(|v| r.kind(v)).transpose()?;
            if (phase == Phase::Matched) != kind.is_some() {
                return Err(bad("matched rule kind"));
            }
            let closes = rule.get("closes").map(|v| r.kind(v)).transpose()?;
            let groups = rule
                .get("groups")
                .map(|v| {
                    array(v)?.iter().try_fold(0, |bits, v| {
                        Ok::<_, ScannerError>(bits | (1 << r.groups[word(v)?]))
                    })
                })
                .transpose()?
                .unwrap_or(0);
            let tests = rule
                .get("when")
                .map(|v| {
                    array(v)?
                        .iter()
                        .map(|v| r.test(v))
                        .collect::<Result<Vec<_>, _>>()
                })
                .transpose()?
                .unwrap_or_default();
            let actions = rule
                .get("then")
                .map(|v| {
                    array(v)?
                        .iter()
                        .map(|v| r.action(v))
                        .collect::<Result<Vec<_>, _>>()
                })
                .transpose()?
                .unwrap_or_default();
            let mut reach = Vec::new();
            for a in &actions {
                if let Action::Emit { symbol, class, .. } = a {
                    reach.push(*symbol);
                    if let Some(c) = class {
                        reach.extend(classes[*c].iter().map(|x| x.1));
                    }
                }
            }
            reach.sort();
            reach.dedup();
            rules.push(Rule {
                phase,
                kind,
                closes,
                groups,
                tests,
                actions,
                reach,
            });
        }
        Ok(Self {
            tab: u32::try_from(tab).map_err(|_| bad("tab width out of range"))?,
            budget: o.get("budget").map(reg).transpose()?,
            trivia,
            opaque,
            probes,
            classes,
            rules,
        })
    }
    pub(super) fn claims(&self, symbol: SymbolId) -> bool {
        self.rules.iter().any(|r| r.reach.contains(&symbol))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::collections::BTreeSet;

    pub(super) fn grammar(names: &[&str]) -> Automaton {
        let source = json!({"name":"scanner-test","externals":names.iter().map(|name|json!({"type":"SYMBOL","name":name})).collect::<Vec<_>>(),"rules":{"document":{"type":"STRING","value":"x"}}});
        Automaton::from_tree_sitter(&serde_json::to_vec(&source).unwrap()).unwrap()
    }
    #[test]
    fn every_shipped_book_lowers_to_the_closed_instruction_set() {
        let mut count = 0;
        for source in BOOKS {
            let v: Value = serde_json::from_str(source).unwrap();
            let mut names = BTreeSet::new();
            for n in v["cohort"].as_array().unwrap() {
                names.insert(n.as_str().unwrap());
            }
            if let Some(classes) = v["classes"].as_object() {
                for arms in classes.values() {
                    for arm in arms.as_array().unwrap() {
                        names.insert(arm[1].as_str().unwrap());
                    }
                }
            }
            for r in v["rules"].as_array().unwrap() {
                for t in r["when"].as_array().map(Vec::as_slice).unwrap_or(&[]) {
                    if ["wanted", "not_wanted", "named", "not_named", "sole"]
                        .contains(&t[0].as_str().unwrap())
                    {
                        names.insert(t[1].as_str().unwrap());
                    }
                }
                for a in r["then"].as_array().map(Vec::as_slice).unwrap_or(&[]) {
                    if a[0] == "emit" {
                        names.insert(a[1].as_str().unwrap());
                    }
                }
            }
            let grammar = grammar(&names.into_iter().collect::<Vec<_>>());
            let book = Book::compile(source, &grammar).unwrap();
            assert!(!book.rules.is_empty());
            count += book.rules.len();
        }
        assert_eq!(count, 275);
    }
    #[test]
    fn unknown_opcodes_names_and_excessive_expression_depth_refuse_at_bind() {
        let grammar = grammar(&["answer"]);
        for rule in [
            json!({"phase":"inside","when":[["typo"]]}),
            json!({"phase":"inside","when":[["probe","missing"]]}),
            json!({"phase":"inside","then":[["emit","missing"]]}),
            json!({"phase":"matched"}),
        ] {
            let source = json!({"rules":[rule]}).to_string();
            assert!(Book::compile(&source, &grammar).is_err());
        }
        let mut e = json!(1);
        for _ in 0..34 {
            e = json!(["+", 1, e]);
        }
        assert!(
            Book::compile(
                &json!({"rules":[{"phase":"inside","then":[["skip",e]]}]}).to_string(),
                &grammar
            )
            .is_err()
        );
    }
}
