use crate::*;
use joints_engine::{ByteSpan, Document, DocumentOptions, DocumentPolicy, Recovery, Reuse, Supply};
use std::sync::Arc;
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct JntCost {
    pub leaves: u32,
    pub height: u32,
    pub at: u32,
    pub minted: u32,
    pub kept: u32,
    pub lifts: u32,
    pub skipped: u32,
    pub carried: u32,
    pub nodes: u32,
    pub read: u32,
    pub stood: u32,
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_weave_new(parser: *mut JntParser, out: *mut *mut JntWeave) -> i32 {
    status_boundary!({
        // SAFETY: the C caller provides aligned writable output storage; output rejects NULL.
        unsafe { output(out)? };
        let p = parser_handle(parser as usize)?;
        let token = insert_weave(parser as usize, p)?;
        // SAFETY: output validated out above; the caller retains its writable storage for this
        // call.
        unsafe { out.write(token as *mut JntWeave) };
        Ok(())
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_weave_free(weave: *mut JntWeave) {
    boundary!((), {
        remove(weave as usize, Kind::Weave)?;
        Ok(())
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_weave_warp(
    weave: *mut JntWeave,
    text: *const c_char,
    len: usize,
) -> i32 {
    status_boundary!({
        let w = weave_handle(weave as usize)?;
        // SAFETY: the C caller keeps len input bytes readable and immutable for this call.
        let source = unsafe { input(text, len)? };
        let mut state = lock(&w.state)?;
        let mut slot = w
            .tree
            .version
            .write()
            .map_err(|_| invalid("tree version lock poisoned"))?;
        if has_results(w.tree_token) {
            return Err(invalid("free query results before changing a weave tree"));
        }
        let options = DocumentOptions {
            recovery: Recovery::Fell,
            supply: Supply::UniqueLiteral,
            policy: state.policy,
            ..DocumentOptions::default()
        };
        let document = Document::with_options(Arc::clone(&w._parser.grammar), source, options)
            .map_err(parse_error)?;
        let v = Version::new(Arc::clone(document.snapshot()));
        state.document = Some(document);
        *slot = Some(v);
        Ok(())
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_weave_amend(
    weave: *mut JntWeave,
    from: u32,
    to: u32,
    insert: *const c_char,
    len: usize,
) -> i32 {
    status_boundary!({
        let w = weave_handle(weave as usize)?;
        // SAFETY: the C caller keeps len input bytes readable and immutable for this call.
        let source = unsafe { input(insert, len)? };
        let span = ByteSpan::new(from as usize, to as usize)
            .ok_or_else(|| invalid("reversed edit span"))?;
        let mut state = lock(&w.state)?;
        let document = state
            .document
            .as_mut()
            .ok_or_else(|| invalid("weave has not been warped"))?;
        if span.end() > document.source().len() {
            return Err(invalid("edit span exceeds current source"));
        }
        let mut slot = w
            .tree
            .version
            .write()
            .map_err(|_| invalid("tree version lock poisoned"))?;
        if has_results(w.tree_token) {
            return Err(invalid("free query results before changing a weave tree"));
        }
        document.edit(span, source).map_err(parse_error)?;
        *slot = Some(Version::new(Arc::clone(document.snapshot())));
        Ok(())
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_weave_tree(weave: *mut JntWeave) -> *mut JntTree {
    boundary!(ptr::null_mut(), {
        let w = weave_handle(weave as usize)?;
        Ok(if lock(&w.state)?.document.is_some() {
            w.tree_token as *mut JntTree
        } else {
            ptr::null_mut()
        })
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_weave_len(weave: *const JntWeave) -> usize {
    boundary!(0, {
        let w = weave_handle(weave as usize)?;
        Ok(lock(&w.state)?
            .document
            .as_ref()
            .map_or(0, |d| d.source().len()))
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_weave_policy(weave: *mut JntWeave, policy: i32) -> i32 {
    status_boundary!({
        let p = match policy {
            0 => DocumentPolicy::Prove,
            1 => DocumentPolicy::Snap,
            2 => DocumentPolicy::Whole,
            _ => return Err(invalid("unknown weave policy")),
        };
        let w = weave_handle(weave as usize)?;
        let mut s = lock(&w.state)?;
        s.policy = p;
        if let Some(d) = &mut s.document {
            d.set_policy(p);
        }
        Ok(())
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_weave_cost(weave: *const JntWeave, out: *mut JntCost) -> i32 {
    status_boundary!({
        if out.is_null() {
            return Err(invalid("NULL cost output"));
        }
        let w = weave_handle(weave as usize)?;
        let s = lock(&w.state)?;
        let cost = match &s.document {
            None => JntCost::default(),
            Some(d) => {
                let c = d.cost();
                JntCost {
                    leaves: count(c.sequence_leaves)?,
                    height: c.sequence_height,
                    at: count(c.sequence_start)?,
                    minted: count(c.sequence_minted)?,
                    kept: count(c.sequence_leaves_kept)?,
                    lifts: 0,
                    skipped: 0,
                    carried: 0,
                    nodes: count(d.snapshot().survey().walked)?,
                    read: count(c.read_events)?,
                    stood: match c.reuse {
                        Reuse::Prefix { bytes, .. } => count(bytes)?,
                        _ => 0,
                    },
                }
            }
        };
        // SAFETY: out is non-NULL and the C caller provides aligned writable output storage.
        unsafe { out.write(cost) };
        Ok(())
    })
}
