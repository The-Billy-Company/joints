use std::ptr::{self, NonNull};

use crate::{Error, ErrorKind, Node, Parser, Result, Tree, ffi};

/// Treatment of predicates this engine does not implement.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(i32)]
pub enum ForeignPolicy {
    /// Refuse execution instead of publishing incomplete findings.
    Refuse = 0,
    /// Keep matches without evaluating the foreign filter.
    Admit = 1,
    /// Discard matches using a foreign filter.
    Deny = 2,
}

/// A compiled query borrowing the exact parser whose grammar compiled it.
pub struct Query<'parser> {
    raw: NonNull<ffi::Handle>,
    parser: &'parser Parser<'parser>,
}

/// One capture in one match; the name and node borrow their respective owners.
#[derive(Clone, Copy, Debug)]
pub struct Capture<'query, 'tree> {
    /// Capture ID within the compiled query.
    pub id: u32,
    /// Exact capture spelling, without the leading `@`.
    pub name: &'query [u8],
    /// Node in the particular tree passed to execution.
    pub node: Node<'tree>,
}

/// One query match, retaining the engine's pattern and capture order.
#[derive(Debug)]
pub struct Match<'query, 'tree> {
    /// Pattern index in query source order.
    pub pattern: u32,
    /// Captures in the engine's order; repetitions are retained.
    pub captures: Vec<Capture<'query, 'tree>>,
}

impl<'parser> Query<'parser> {
    pub(crate) fn compile(parser: &'parser Parser<'parser>, source: &str) -> Result<Self> {
        let mut raw = ptr::null_mut();
        // SAFETY: parser remains live for the query's borrow; source covers
        // len readable bytes for this call and the native query copies it.
        Error::status(unsafe {
            ffi::jnt_query_compile(
                parser.raw.as_ptr(),
                source.as_ptr().cast(),
                source.len(),
                &mut raw,
            )
        })?;
        Ok(Self {
            raw: Error::handle(raw)?,
            parser,
        })
    }

    /// Number of patterns in source order.
    pub fn pattern_count(&self) -> u32 {
        // SAFETY: self owns a live immutable compiled query.
        unsafe { ffi::jnt_query_pattern_count(self.raw.as_ptr()) }
    }

    /// Number of distinct capture names in this query.
    pub fn capture_count(&self) -> u32 {
        // SAFETY: self owns a live immutable compiled query.
        unsafe { ffi::jnt_query_capture_count(self.raw.as_ptr()) }
    }

    /// Capture spelling without `@`, absent for an out-of-range ID.
    pub fn capture_name(&self, id: u32) -> Option<&[u8]> {
        let mut len = 0;
        // SAFETY: the accessor bounds-checks id; non-null metadata belongs
        // to this live query and is borrowed no longer than self.
        unsafe {
            let pointer = ffi::jnt_query_capture_name(self.raw.as_ptr(), id, &mut len);
            (!pointer.is_null()).then(|| ffi::bytes(pointer, len))
        }
    }

    /// Eager matches using this tree's retained source bytes.
    ///
    /// The tree must come from this exact parser. Partial trees may be queried
    /// deliberately; inspect [`Tree::confidence`] before trusting findings.
    pub fn matches<'query, 'tree>(
        &'query self,
        tree: &'tree Tree<'tree>,
        foreign: ForeignPolicy,
    ) -> Result<Vec<Match<'query, 'tree>>> {
        if tree.parser.raw != self.parser.raw {
            return Err(Error::new(
                ErrorKind::Invalid,
                "query and tree belong to different parsers",
            ));
        }
        let mut raw = ptr::null_mut();
        // SAFETY: all handles and the tree's exact source are live on one
        // thread; the native call eagerly owns its match arrays on success.
        Error::status(unsafe {
            ffi::jnt_query_exec(
                self.raw.as_ptr(),
                tree.raw.as_ptr(),
                tree.source().as_ptr().cast(),
                tree.source().len(),
                foreign as i32,
                &mut raw,
            )
        })?;
        let result = NativeResult(Error::handle(raw)?);
        // SAFETY: the result guard owns a live native array until conversion finishes.
        let count = unsafe { ffi::jnt_query_result_count(result.0.as_ptr()) };
        (0..count)
            .map(|i| {
                // SAFETY: i is within this result; scalar lookups bounds-check
                // the underlying match, and the guard keeps arrays live.
                let (pattern, captures) = unsafe {
                    (
                        ffi::jnt_query_result_pattern(result.0.as_ptr(), i),
                        ffi::jnt_query_result_capture_count(result.0.as_ptr(), i),
                    )
                };
                let captures = (0..captures)
                    .map(|capture| {
                        // SAFETY: both indices address this live result's arrays.
                        let (id, node) = unsafe {
                            (
                                ffi::jnt_query_result_capture_id(result.0.as_ptr(), i, capture),
                                ffi::jnt_query_result_capture_node(result.0.as_ptr(), i, capture),
                            )
                        };
                        let name = self.capture_name(id).ok_or_else(|| {
                            Error::new(ErrorKind::Format, "invalid native capture ID")
                        })?;
                        let node = tree.node(node).ok_or_else(|| {
                            Error::new(ErrorKind::Format, "invalid native captured node")
                        })?;
                        Ok(Capture { id, name, node })
                    })
                    .collect::<Result<Vec<_>>>()?;
                Ok(Match { pattern, captures })
            })
            .collect()
    }
}

impl Drop for Query<'_> {
    fn drop(&mut self) {
        // SAFETY: capture-name borrows prevent this owner being freed while
        // any Rust match still refers to it; the parser also remains live.
        unsafe { ffi::jnt_query_free(self.raw.as_ptr()) };
    }
}

struct NativeResult(NonNull<ffi::Handle>);

impl Drop for NativeResult {
    fn drop(&mut self) {
        // SAFETY: this guard solely owns the eager native array; all matches
        // returned to Rust contain copied scalars and owner-borrowed views.
        unsafe { ffi::jnt_query_result_free(self.0.as_ptr()) };
    }
}
