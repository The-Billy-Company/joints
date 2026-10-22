use crate::*;
use joints_engine::{ByteSpan, Node, RepairKind, Stop, TreeSnapshot};
use std::sync::{Arc, RwLock};
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct JntScar {
    pub at: u32,
    pub over: u32,
    pub supplied: u32,
    pub heads: u32,
    pub shifted: u32,
    pub felled: u32,
    pub stop: i32,
}
fn stop(s: Stop) -> i32 {
    match s {
        Stop::Accepted => 0,
        Stop::Stray { .. } => 1,
        Stop::Unexpected { .. } => 2,
        Stop::Truncated => 3,
    }
}
fn snapshot(t: *const JntTree) -> Result<Arc<Version>> {
    version(tree_handle(t as usize)?.as_ref())
}
fn node_id(n: Option<Node<'_>>) -> Result<u32> {
    n.map_or(Ok(JNT_NONE), |n| count(n.index()))
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_parse(
    parser: *mut JntParser,
    text: *const c_char,
    len: usize,
    out: *mut *mut JntTree,
) -> i32 {
    status_boundary!({
        // SAFETY: the C caller provides aligned writable output storage; output rejects NULL.
        unsafe { output(out)? };
        let p = parser_handle(parser as usize)?;
        // SAFETY: the C caller keeps len input bytes readable and immutable for this call.
        let bytes = unsafe { input(text, len)? };
        let tree = lock(&p.session)?
            .parse_partial(bytes)
            .map_err(parse_error)?;
        let token = insert(Handle::Tree(Arc::new(TreeData {
            parser: parser as usize,
            _parser: p,
            borrowed: false,
            version: RwLock::new(Some(Version::new(Arc::new(tree)))),
        })))?;
        // SAFETY: output validated out above; the caller retains its writable storage for this
        // call.
        unsafe { out.write(token as *mut JntTree) };
        Ok(())
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_tree_free(tree: *mut JntTree) {
    boundary!((), {
        remove(tree as usize, Kind::Tree)?;
        Ok(())
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_tree_stop(tree: *const JntTree) -> i32 {
    boundary!(JNT_INVALID, { Ok(stop(snapshot(tree)?.tree.stop())) })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_tree_stop_at(tree: *const JntTree) -> u32 {
    boundary!(0, {
        match snapshot(tree)?.tree.stop() {
            Stop::Stray { at } | Stop::Unexpected { at, .. } => count(at),
            _ => Ok(0),
        }
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_tree_stop_word(
    tree: *const JntTree,
    len: *mut usize,
) -> *const c_char {
    boundary!(ptr::null(), {
        // SAFETY: the C caller supplies a writable len pointer or NULL; no byte view is
        // returned.
        unsafe { view(None, len) };
        let v = snapshot(tree)?;
        // SAFETY: len is writable or NULL by the C contract; the registered owner retains these
        // bytes.
        Ok(unsafe { view(v.tree.stop_symbol().map(str::as_bytes), len) })
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_tree_mends(tree: *const JntTree) -> u32 {
    boundary!(0, { count(snapshot(tree)?.tree.mends()) })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_tree_skipped(tree: *const JntTree) -> u32 {
    boundary!(0, { count(snapshot(tree)?.tree.skipped()) })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_tree_supplied(tree: *const JntTree) -> u32 {
    boundary!(0, { count(snapshot(tree)?.tree.supplied()) })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_tree_sound(tree: *mut JntTree) -> i32 {
    boundary!(JNT_INVALID, {
        Ok(i32::from(snapshot(tree)?.tree.survey().is_sound()))
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_tree_scars(tree: *const JntTree) -> u32 {
    boundary!(0, { count(snapshot(tree)?.tree.repairs().len()) })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_tree_scar(tree: *const JntTree, i: u32, out: *mut JntScar) -> i32 {
    status_boundary!({
        if out.is_null() {
            return Err(invalid("NULL scar output"));
        }
        let v = snapshot(tree)?;
        let r = v
            .tree
            .repairs()
            .get(i as usize)
            .ok_or_else(|| invalid("scar index is out of range"))?;
        let supplied = matches!(r.kind, RepairKind::Supplied { .. });
        let felled = matches!(r.kind, RepairKind::Deleted { felled: true });
        let scar = JntScar {
            at: count(r.span.start())?,
            over: count(r.span.end())?,
            supplied: u32::from(supplied),
            heads: count(r.heads)?,
            shifted: count(r.shifted)?,
            felled: u32::from(felled),
            stop: stop(r.context),
        };
        // SAFETY: out is non-NULL and the C caller provides aligned writable output storage.
        unsafe { out.write(scar) };
        Ok(())
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_tree_scar_word(
    tree: *const JntTree,
    i: u32,
    len: *mut usize,
) -> *const c_char {
    boundary!(ptr::null(), {
        // SAFETY: the C caller supplies a writable len pointer or NULL; no byte view is
        // returned.
        unsafe { view(None, len) };
        let v = snapshot(tree)?;
        let word = v
            .tree
            .repairs()
            .get(i as usize)
            .and_then(|r| v.tree.repair_symbol(r));
        // SAFETY: len is writable or NULL by the C contract; the registered owner retains these
        // bytes.
        Ok(unsafe { view(word.map(str::as_bytes), len) })
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_tree_roots(tree: *const JntTree) -> u32 {
    boundary!(0, { count(snapshot(tree)?.tree.roots().len()) })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_tree_root(tree: *const JntTree, i: u32) -> u32 {
    boundary!(JNT_NONE, {
        node_id(snapshot(tree)?.tree.roots().nth(i as usize))
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_node_name(
    tree: *const JntTree,
    id: u32,
    len: *mut usize,
) -> *const c_char {
    boundary!(ptr::null(), {
        // SAFETY: the C caller supplies a writable len pointer or NULL; no byte view is
        // returned.
        unsafe { view(None, len) };
        let v = snapshot(tree)?;
        // SAFETY: len is writable or NULL by the C contract; the registered owner retains these
        // bytes.
        Ok(unsafe {
            view(
                v.tree.node_at(id as usize).map(|n| n.name().as_bytes()),
                len,
            )
        })
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_node_field(
    tree: *const JntTree,
    id: u32,
    len: *mut usize,
) -> *const c_char {
    boundary!(ptr::null(), {
        // SAFETY: the C caller supplies a writable len pointer or NULL; no byte view is
        // returned.
        unsafe { view(None, len) };
        let v = snapshot(tree)?;
        // SAFETY: len is writable or NULL by the C contract; the registered owner retains these
        // bytes.
        Ok(unsafe {
            view(
                v.tree
                    .node_at(id as usize)
                    .and_then(Node::field)
                    .map(str::as_bytes),
                len,
            )
        })
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_node_named(tree: *const JntTree, id: u32) -> i32 {
    boundary!(0, {
        Ok(i32::from(
            snapshot(tree)?
                .tree
                .node_at(id as usize)
                .is_some_and(Node::is_named),
        ))
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_node_start(tree: *const JntTree, id: u32) -> u32 {
    boundary!(0, {
        snapshot(tree)?
            .tree
            .node_at(id as usize)
            .map_or(Ok(0), |n| count(n.span().start()))
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_node_end(tree: *const JntTree, id: u32) -> u32 {
    boundary!(0, {
        snapshot(tree)?
            .tree
            .node_at(id as usize)
            .map_or(Ok(0), |n| count(n.span().end()))
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_node_kids(tree: *const JntTree, id: u32) -> u32 {
    boundary!(0, {
        count(
            snapshot(tree)?
                .tree
                .node_at(id as usize)
                .map_or(0, |n| n.children().len()),
        )
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_node_kid(tree: *const JntTree, id: u32, i: u32) -> u32 {
    boundary!(JNT_NONE, {
        node_id(
            snapshot(tree)?
                .tree
                .node_at(id as usize)
                .and_then(|n| n.children().nth(i as usize)),
        )
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_node_parent(tree: *const JntTree, id: u32) -> u32 {
    boundary!(JNT_NONE, {
        node_id(
            snapshot(tree)?
                .tree
                .node_at(id as usize)
                .and_then(Node::parent),
        )
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_node_next(tree: *const JntTree, id: u32) -> u32 {
    boundary!(JNT_NONE, {
        node_id(
            snapshot(tree)?
                .tree
                .node_at(id as usize)
                .and_then(Node::next_sibling),
        )
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_node_prev(tree: *const JntTree, id: u32) -> u32 {
    boundary!(JNT_NONE, {
        node_id(
            snapshot(tree)?
                .tree
                .node_at(id as usize)
                .and_then(Node::prev_sibling),
        )
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_node_next_named(tree: *const JntTree, id: u32) -> u32 {
    boundary!(JNT_NONE, {
        node_id(
            snapshot(tree)?
                .tree
                .node_at(id as usize)
                .and_then(Node::next_named_sibling),
        )
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_node_prev_named(tree: *const JntTree, id: u32) -> u32 {
    boundary!(JNT_NONE, {
        node_id(
            snapshot(tree)?
                .tree
                .node_at(id as usize)
                .and_then(Node::prev_named_sibling),
        )
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_node_by_field(
    tree: *const JntTree,
    id: u32,
    field: *const c_char,
    len: usize,
) -> u32 {
    boundary!(JNT_NONE, {
        // SAFETY: the C caller keeps len input bytes readable and immutable for this call.
        let bytes = unsafe { input(field, len)? };
        let v = snapshot(tree)?;
        let n = v.tree.node_at(id as usize).and_then(|n| {
            n.children()
                .find(|c| !c.is_extra() && c.field().is_some_and(|f| f.as_bytes() == bytes))
        });
        node_id(n)
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_node_depth(tree: *const JntTree, id: u32) -> u32 {
    boundary!(0, {
        count(
            snapshot(tree)?
                .tree
                .node_at(id as usize)
                .map_or(0, Node::depth),
        )
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_node_covering(tree: *const JntTree, from: u32, to: u32) -> u32 {
    boundary!(JNT_NONE, {
        let v = snapshot(tree)?;
        node_id(ByteSpan::new(from as usize, to as usize).and_then(|s| v.tree.covering(s)))
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_node_spread(tree: *const JntTree, id: u32) -> u32 {
    boundary!(0, {
        let v = snapshot(tree)?;
        match v.tree.node_at(id as usize) {
            None => Ok(0),
            Some(n) => count(n.subtree_size().map_err(|_| nomem())?),
        }
    })
}

const RENDER_BYTES: usize = 256 << 20;
struct RenderBuffer {
    bytes: Vec<u8>,
    limit: usize,
}
fn append(out: &mut RenderBuffer, bytes: &[u8]) -> Result<()> {
    if out
        .bytes
        .len()
        .checked_add(bytes.len())
        .is_none_or(|n| n > out.limit)
    {
        return Err(nomem());
    }
    out.bytes.try_reserve(bytes.len()).map_err(|_| nomem())?;
    out.bytes.extend_from_slice(bytes);
    Ok(())
}
fn quote(out: &mut RenderBuffer, name: &str) -> Result<()> {
    append(out, b"\"")?;
    for b in name.bytes() {
        match b {
            b'"' => append(out, b"\\\"")?,
            b'\\' => append(out, b"\\\\")?,
            b'\n' => append(out, b"\\n")?,
            b'\r' => append(out, b"\\r")?,
            b'\t' => append(out, b"\\t")?,
            0..=31 | 127 => {
                let h = b"0123456789abcdef";
                append(
                    out,
                    &[b'\\', b'x', h[usize::from(b >> 4)], h[usize::from(b & 15)]],
                )?
            }
            _ => append(out, &[b])?,
        }
    }
    append(out, b"\"")
}
enum Task<'a> {
    Node(Node<'a>),
    Bytes(&'static [u8]),
}
fn render(tree: &TreeSnapshot, all: bool) -> Result<Vec<u8>> {
    render_with_limit(tree, all, RENDER_BYTES)
}
fn render_with_limit(tree: &TreeSnapshot, all: bool, limit: usize) -> Result<Vec<u8>> {
    let mut out = RenderBuffer {
        bytes: Vec::new(),
        limit,
    };
    let mut work = Vec::new();
    work.try_reserve(tree.roots().len().saturating_mul(2))
        .map_err(|_| nomem())?;
    for root in tree.roots().rev() {
        work.push(Task::Bytes(b"\n"));
        work.push(Task::Node(root));
    }
    while let Some(task) = work.pop() {
        match task {
            Task::Bytes(b) => append(&mut out, b)?,
            Task::Node(n) => {
                if let Some(field) = n.field() {
                    append(&mut out, field.as_bytes())?;
                    append(&mut out, b": ")?;
                }
                if !n.is_named() && n.children().len() == 0 {
                    quote(&mut out, n.name())?;
                    continue;
                }
                append(&mut out, b"(")?;
                if n.is_named() {
                    append(&mut out, n.name().as_bytes())?
                } else {
                    quote(&mut out, n.name())?
                }
                let capacity = n
                    .children()
                    .len()
                    .checked_mul(2)
                    .and_then(|n| n.checked_add(1))
                    .ok_or_else(nomem)?;
                work.try_reserve(capacity).map_err(|_| nomem())?;
                work.push(Task::Bytes(b")"));
                for child in n.children().rev() {
                    if all || child.is_named() {
                        work.push(Task::Node(child));
                        work.push(Task::Bytes(b" "));
                    }
                }
            }
        }
    }
    append(&mut out, &[0])?;
    Ok(out.bytes)
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_tree_sexp(
    tree: *mut JntTree,
    all: i32,
    len: *mut usize,
) -> *const c_char {
    boundary!(ptr::null(), {
        // SAFETY: the C caller supplies a writable len pointer or NULL; no byte view is
        // returned.
        unsafe { view(None, len) };
        let v = snapshot(tree)?;
        let mut renders = lock(&v.renders)?;
        let slot = &mut renders[usize::from(all != 0)];
        if slot.is_none() {
            *slot = Some(render(&v.tree, all != 0)?)
        }
        let b = slot.as_ref().expect("render initialized");
        // SAFETY: len is writable or NULL by the C contract; the registered owner retains these
        // bytes.
        Ok(unsafe { view(Some(&b[..b.len() - 1]), len) })
    })
}

#[cfg(test)]
mod render_tests {
    use super::*;
    #[test]
    fn render_limit_refuses_before_publishing_and_exact_fit_keeps_terminator() {
        let grammar = joints_engine::CompiledGrammar::compile(include_bytes!(
            "../../../test/grammar/json.json"
        ))
        .unwrap();
        let tree = grammar.session().parse_partial(b"[1,2]").unwrap();
        let expected = render(&tree, true).unwrap();
        assert_eq!(
            render_with_limit(&tree, true, expected.len() - 1)
                .unwrap_err()
                .code,
            JNT_NOMEM
        );
        assert_eq!(
            render_with_limit(&tree, true, expected.len()).unwrap(),
            expected
        );
        assert_eq!(expected.last(), Some(&0));
    }
}
