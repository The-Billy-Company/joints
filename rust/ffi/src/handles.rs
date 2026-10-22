use crate::*;
use joints_engine::{
    Bank, CompiledGrammar, Document, DocumentPolicy, ParseSession, Query, TreeSnapshot,
};
use std::{
    collections::HashMap,
    sync::{Arc, Mutex, MutexGuard, OnceLock, RwLock},
};
pub(crate) struct BankData {
    pub bank: Bank,
}
pub(crate) struct ParserData {
    pub bank: usize,
    pub _bank: Arc<BankData>,
    pub grammar: Arc<CompiledGrammar>,
    pub session: Mutex<ParseSession>,
}
pub(crate) struct Version {
    pub tree: Arc<TreeSnapshot>,
    pub renders: Mutex<[Option<Vec<u8>>; 2]>,
}
impl Version {
    pub fn new(tree: Arc<TreeSnapshot>) -> Arc<Self> {
        Arc::new(Self {
            tree,
            renders: Mutex::new([None, None]),
        })
    }
}
pub(crate) struct TreeData {
    pub parser: usize,
    pub _parser: Arc<ParserData>,
    pub borrowed: bool,
    pub version: RwLock<Option<Arc<Version>>>,
}
pub(crate) struct QueryData {
    pub parser: usize,
    pub _parser: Arc<ParserData>,
    pub query: Query,
}
pub(crate) struct Match {
    pub pattern: u32,
    pub captures: Vec<(u32, u32)>,
}
pub(crate) struct ResultData {
    pub query: usize,
    pub tree: usize,
    pub _query: Arc<QueryData>,
    pub _tree: Arc<TreeData>,
    pub _version: Arc<Version>,
    pub matches: Vec<Match>,
}
pub(crate) struct WeaveState {
    pub document: Option<Document>,
    pub policy: DocumentPolicy,
}
pub(crate) struct WeaveData {
    pub parser: usize,
    pub _parser: Arc<ParserData>,
    pub tree_token: usize,
    pub tree: Arc<TreeData>,
    pub state: Mutex<WeaveState>,
}
#[derive(Clone)]
pub(crate) enum Handle {
    Bank(Arc<BankData>),
    Parser(Arc<ParserData>),
    Tree(Arc<TreeData>),
    Query(Arc<QueryData>),
    Result(Arc<ResultData>),
    Weave(Arc<WeaveData>),
}
#[derive(Clone, Copy, PartialEq, Eq)]
pub(crate) enum Kind {
    Bank,
    Parser,
    Tree,
    Query,
    Result,
    Weave,
}
impl Handle {
    fn kind(&self) -> Kind {
        match self {
            Self::Bank(_) => Kind::Bank,
            Self::Parser(_) => Kind::Parser,
            Self::Tree(_) => Kind::Tree,
            Self::Query(_) => Kind::Query,
            Self::Result(_) => Kind::Result,
            Self::Weave(_) => Kind::Weave,
        }
    }
    fn depends_on(&self, id: usize) -> bool {
        match self {
            Self::Bank(_) => false,
            Self::Parser(p) => p.bank == id,
            Self::Tree(t) => t.parser == id,
            Self::Query(q) => q.parser == id,
            Self::Result(r) => r.query == id || r.tree == id,
            Self::Weave(w) => w.parser == id,
        }
    }
}
struct Registry {
    next: usize,
    handles: HashMap<usize, Handle>,
}
static REGISTRY: OnceLock<Mutex<Registry>> = OnceLock::new();
fn registry() -> MutexGuard<'static, Registry> {
    REGISTRY
        .get_or_init(|| {
            Mutex::new(Registry {
                next: 16,
                handles: HashMap::new(),
            })
        })
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}
pub(crate) fn lock<T>(m: &Mutex<T>) -> Result<MutexGuard<'_, T>> {
    m.lock()
        .map_err(|_| invalid("handle scratch poisoned by previous panic"))
}
fn live_parent(r: &Registry, id: usize, kind: Kind) -> bool {
    r.handles.get(&id).is_some_and(|h| h.kind() == kind)
}
fn valid_parents(r: &Registry, h: &Handle) -> bool {
    match h {
        Handle::Bank(_) => true,
        Handle::Parser(p) => live_parent(r, p.bank, Kind::Bank),
        Handle::Tree(t) => live_parent(r, t.parser, Kind::Parser),
        Handle::Query(q) => live_parent(r, q.parser, Kind::Parser),
        Handle::Result(v) => {
            live_parent(r, v.query, Kind::Query) && live_parent(r, v.tree, Kind::Tree)
        }
        Handle::Weave(w) => live_parent(r, w.parser, Kind::Parser),
    }
}
pub(crate) fn insert(h: Handle) -> Result<usize> {
    let mut r = registry();
    if !valid_parents(&r, &h) {
        return Err(invalid("owner was closed during operation"));
    }
    let id = r.next;
    r.next = id.checked_add(16).ok_or_else(nomem)?;
    r.handles.try_reserve(1).map_err(|_| nomem())?;
    r.handles.insert(id, h);
    Ok(id)
}
fn get(id: usize) -> Result<Handle> {
    registry()
        .handles
        .get(&id)
        .cloned()
        .ok_or_else(|| invalid("NULL, stale, or invented handle"))
}
macro_rules! accessor {
    ($f:ident,$v:ident,$t:ty) => {
        pub(crate) fn $f(id: usize) -> Result<Arc<$t>> {
            match get(id)? {
                Handle::$v(h) => Ok(h),
                _ => Err(invalid("wrong opaque handle kind")),
            }
        }
    };
}
accessor!(bank_handle, Bank, BankData);
accessor!(parser_handle, Parser, ParserData);
accessor!(tree_handle, Tree, TreeData);
accessor!(query_handle, Query, QueryData);
accessor!(result_handle, Result, ResultData);
accessor!(weave_handle, Weave, WeaveData);
pub(crate) fn version(t: &TreeData) -> Result<Arc<Version>> {
    t.version
        .read()
        .map_err(|_| invalid("tree version lock poisoned"))?
        .clone()
        .ok_or_else(|| invalid("weave has not been warped"))
}
pub(crate) fn remove(id: usize, kind: Kind) -> Result<()> {
    let mut r = registry();
    let h = r
        .handles
        .get(&id)
        .ok_or_else(|| invalid("NULL, stale, or invented handle"))?;
    if h.kind() != kind {
        return Err(invalid("wrong opaque handle kind"));
    }
    if matches!(h,Handle::Tree(t)if t.borrowed) {
        return Ok(());
    }
    if r.handles.values().any(|h| h.depends_on(id)) {
        return Err(invalid("free dependent handles first"));
    }
    let extra = match h {
        Handle::Weave(w) => Some(w.tree_token),
        _ => None,
    };
    if extra.is_some_and(|id| r.handles.values().any(|h| h.depends_on(id))) {
        return Err(invalid("free query results before their weave"));
    }
    r.handles.remove(&id);
    if let Some(id) = extra {
        r.handles.remove(&id);
    }
    Ok(())
}
pub(crate) fn has_results(tree: usize) -> bool {
    registry()
        .handles
        .values()
        .any(|h| matches!(h,Handle::Result(r)if r.tree==tree))
}

pub(crate) fn insert_weave(parser: usize, p: Arc<ParserData>) -> Result<usize> {
    let tree = Arc::new(TreeData {
        parser,
        _parser: Arc::clone(&p),
        borrowed: true,
        version: RwLock::new(None),
    });
    let mut r = registry();
    if !live_parent(&r, parser, Kind::Parser) {
        return Err(invalid("parser was closed during operation"));
    }
    r.handles.try_reserve(2).map_err(|_| nomem())?;
    let tree_token = r.next;
    let token = tree_token.checked_add(16).ok_or_else(nomem)?;
    r.next = token.checked_add(16).ok_or_else(nomem)?;
    let weave = Arc::new(WeaveData {
        parser,
        _parser: p,
        tree_token,
        tree: Arc::clone(&tree),
        state: Mutex::new(WeaveState {
            document: None,
            policy: DocumentPolicy::Prove,
        }),
    });
    r.handles.insert(tree_token, Handle::Tree(tree));
    r.handles.insert(token, Handle::Weave(weave));
    Ok(token)
}
