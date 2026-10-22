use crate::*;
use joints_engine::{ForeignPolicy, Query};
use std::sync::Arc;
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_query_compile(
    parser: *const JntParser,
    scm: *const c_char,
    len: usize,
    out: *mut *mut JntQuery,
) -> i32 {
    status_boundary!({
        // SAFETY: the C caller provides aligned writable output storage; output rejects NULL.
        unsafe { output(out)? };
        let p = parser_handle(parser as usize)?;
        // SAFETY: the C caller keeps len input bytes readable and immutable for this call.
        let source = unsafe { input(scm, len)? };
        let query =
            Query::compile(Arc::clone(&p.grammar), source).map_err(|e| fault(JNT_FORMAT, e))?;
        let token = insert(Handle::Query(Arc::new(QueryData {
            parser: parser as usize,
            _parser: p,
            query,
        })))?;
        // SAFETY: output validated out above; the caller retains its writable storage for this
        // call.
        unsafe { out.write(token as *mut JntQuery) };
        Ok(())
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_query_free(query: *mut JntQuery) {
    boundary!((), {
        remove(query as usize, Kind::Query)?;
        Ok(())
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_query_pattern_count(query: *const JntQuery) -> u32 {
    boundary!(0, {
        count(query_handle(query as usize)?.query.pattern_count())
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_query_capture_count(query: *const JntQuery) -> u32 {
    boundary!(0, {
        count(query_handle(query as usize)?.query.capture_count())
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_query_capture_name(
    query: *const JntQuery,
    id: u32,
    len: *mut usize,
) -> *const c_char {
    boundary!(ptr::null(), {
        // SAFETY: the C caller supplies a writable len pointer or NULL; no byte view is
        // returned.
        unsafe { view(None, len) };
        let q = query_handle(query as usize)?;
        // SAFETY: len is writable or NULL by the C contract; the registered owner retains these
        // bytes.
        Ok(unsafe {
            view(
                q.query
                    .capture_names()
                    .get(id as usize)
                    .map(|s| s.as_bytes()),
                len,
            )
        })
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_query_exec(
    query: *const JntQuery,
    tree: *const JntTree,
    text: *const c_char,
    len: usize,
    foreign: i32,
    out: *mut *mut JntQueryResult,
) -> i32 {
    status_boundary!({
        // SAFETY: the C caller provides aligned writable output storage; output rejects NULL.
        unsafe { output(out)? };
        let q = query_handle(query as usize)?;
        let t = tree_handle(tree as usize)?;
        if q.parser != t.parser {
            return Err(invalid("query and tree belong to different parsers"));
        }
        let policy = match foreign {
            0 => ForeignPolicy::Refuse,
            1 => ForeignPolicy::Admit,
            2 => ForeignPolicy::Deny,
            _ => return Err(invalid("unknown foreign predicate policy")),
        };
        // SAFETY: the C caller keeps len input bytes readable and immutable for this call.
        let bytes = unsafe { input(text, len)? };
        let version_guard = t
            .version
            .read()
            .map_err(|_| invalid("tree version lock poisoned"))?;
        let v = version_guard
            .clone()
            .ok_or_else(|| invalid("weave has not been warped"))?;
        if bytes != v.tree.source() {
            return Err(invalid(
                "query text differs from the tree's original parsed bytes",
            ));
        }
        let found = q
            .query
            .execute(&v.tree, policy)
            .map_err(|e| fault(JNT_FORMAT, e))?;
        let mut matches = Vec::new();
        matches.try_reserve(found.len()).map_err(|_| nomem())?;
        for m in found {
            let mut captures = Vec::new();
            captures
                .try_reserve(m.captures.len())
                .map_err(|_| nomem())?;
            for c in m.captures {
                captures.push((count(c.id.index())?, count(c.node.index())?));
            }
            matches.push(Match {
                pattern: count(m.pattern.index())?,
                captures,
            });
        }
        let token = insert(Handle::Result(Arc::new(ResultData {
            query: query as usize,
            tree: tree as usize,
            _query: q,
            _tree: Arc::clone(&t),
            _version: v,
            matches,
        })))?;
        // SAFETY: output validated out above; the caller retains its writable storage for this
        // call.
        unsafe { out.write(token as *mut JntQueryResult) };
        Ok(())
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_query_result_free(result: *mut JntQueryResult) {
    boundary!((), {
        remove(result as usize, Kind::Result)?;
        Ok(())
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_query_result_count(result: *const JntQueryResult) -> u32 {
    boundary!(0, { count(result_handle(result as usize)?.matches.len()) })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_query_result_pattern(result: *const JntQueryResult, m: u32) -> u32 {
    boundary!(JNT_NONE, {
        Ok(result_handle(result as usize)?
            .matches
            .get(m as usize)
            .map_or(JNT_NONE, |m| m.pattern))
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_query_result_capture_count(
    result: *const JntQueryResult,
    m: u32,
) -> u32 {
    boundary!(0, {
        count(
            result_handle(result as usize)?
                .matches
                .get(m as usize)
                .map_or(0, |m| m.captures.len()),
        )
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_query_result_capture_id(
    result: *const JntQueryResult,
    m: u32,
    c: u32,
) -> u32 {
    boundary!(JNT_NONE, {
        Ok(result_handle(result as usize)?
            .matches
            .get(m as usize)
            .and_then(|m| m.captures.get(c as usize))
            .map_or(JNT_NONE, |c| c.0))
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_query_result_capture_node(
    result: *const JntQueryResult,
    m: u32,
    c: u32,
) -> u32 {
    boundary!(JNT_NONE, {
        Ok(result_handle(result as usize)?
            .matches
            .get(m as usize)
            .and_then(|m| m.captures.get(c as usize))
            .map_or(JNT_NONE, |c| c.1))
    })
}
