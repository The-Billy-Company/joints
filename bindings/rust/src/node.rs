use std::ops::Range;

use crate::{Tree, ffi};

/// A zero-based source position with a byte column, matching tree-sitter.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Point {
    /// Zero-based row, counted by LF bytes.
    pub row: u32,
    /// Zero-based byte column within the row.
    pub column: u32,
}

/// A checked reference into a particular immutable tree.
#[derive(Clone, Copy)]
pub struct Node<'tree> {
    pub(crate) tree: &'tree Tree<'tree>,
    pub(crate) id: u32,
}

impl<'tree> Node<'tree> {
    /// The grammar's exact node-kind spelling.
    pub fn kind(self) -> &'tree [u8] {
        let mut len = 0;
        // SAFETY: construction validated id; the tree's parser owns the name
        // for at least 'tree and cannot be freed through a live node borrow.
        unsafe {
            let pointer = ffi::jnt_node_name(self.tree.raw.as_ptr(), self.id, &mut len);
            ffi::bytes(pointer, len)
        }
    }

    /// Whether queries can match this node by kind rather than its literal.
    pub fn is_named(self) -> bool {
        // SAFETY: this ref was validated and its immutable owner remains live.
        unsafe { ffi::jnt_node_named(self.tree.raw.as_ptr(), self.id) != 0 }
    }

    /// The source byte span, with an exclusive end.
    pub fn byte_range(self) -> Range<u32> {
        // SAFETY: scalar reads on a validated node in a live immutable tree.
        unsafe {
            ffi::jnt_node_start(self.tree.raw.as_ptr(), self.id)
                ..ffi::jnt_node_end(self.tree.raw.as_ptr(), self.id)
        }
    }

    /// Original source bytes in this node's span, absent for an invalid span.
    pub fn text(self) -> Option<&'tree [u8]> {
        let span = self.byte_range();
        self.tree
            .source()
            .get(span.start as usize..span.end as usize)
    }

    /// Position of the first byte, absent for a span beyond the source.
    pub fn start_point(self) -> Option<Point> {
        self.tree.point_at(self.byte_range().start)
    }

    /// Position immediately after the last byte, absent beyond the source.
    pub fn end_point(self) -> Option<Point> {
        self.tree.point_at(self.byte_range().end)
    }

    /// This node's field in its parent, absent when the grammar did not file it.
    pub fn field(self) -> Option<&'tree [u8]> {
        let mut len = 0;
        // SAFETY: a non-null name belongs to this node's live parser/bank.
        unsafe {
            let pointer = ffi::jnt_node_field(self.tree.raw.as_ptr(), self.id, &mut len);
            (!pointer.is_null()).then(|| ffi::bytes(pointer, len))
        }
    }

    /// Number of children, including anonymous nodes and comments.
    pub fn child_count(self) -> u32 {
        // SAFETY: a scalar read on this validated live node.
        unsafe { ffi::jnt_node_kids(self.tree.raw.as_ptr(), self.id) }
    }

    /// Child `index`, absent past the end.
    pub fn child(self, index: u32) -> Option<Self> {
        // SAFETY: the native accessor bounds-checks the child index.
        self.tree
            .node(unsafe { ffi::jnt_node_kid(self.tree.raw.as_ptr(), self.id, index) })
    }

    /// All children in source order, including anonymous nodes.
    pub fn children(self) -> impl ExactSizeIterator<Item = Self> {
        (0..self.child_count()).map(move |i| self.child(i).expect("native child exists"))
    }

    /// Children that queries can match by kind.
    pub fn named_children(self) -> impl Iterator<Item = Self> {
        self.children().filter(|node| node.is_named())
    }

    /// The first child filed under this exact field spelling.
    pub fn child_by_field(self, field: impl AsRef<[u8]>) -> Option<Self> {
        let field = field.as_ref();
        // SAFETY: field covers len readable bytes for this call, and lookup
        // is bounds-checked against a validated node in a live tree.
        self.tree.node(unsafe {
            ffi::jnt_node_by_field(
                self.tree.raw.as_ptr(),
                self.id,
                field.as_ptr().cast(),
                field.len(),
            )
        })
    }

    /// Parent node; roots in a partial forest have none.
    pub fn parent(self) -> Option<Self> {
        // SAFETY: native neighbourhood lookups bounds-check validated refs.
        self.tree
            .node(unsafe { ffi::jnt_node_parent(self.tree.raw.as_ptr(), self.id) })
    }

    /// Next sibling, including anonymous nodes.
    pub fn next_sibling(self) -> Option<Self> {
        // SAFETY: native neighbourhood lookups bounds-check validated refs.
        self.tree
            .node(unsafe { ffi::jnt_node_next(self.tree.raw.as_ptr(), self.id) })
    }

    /// Previous sibling, including anonymous nodes.
    pub fn previous_sibling(self) -> Option<Self> {
        // SAFETY: native neighbourhood lookups bounds-check validated refs.
        self.tree
            .node(unsafe { ffi::jnt_node_prev(self.tree.raw.as_ptr(), self.id) })
    }

    /// Next named sibling, including comments.
    pub fn next_named_sibling(self) -> Option<Self> {
        // SAFETY: native neighbourhood lookups bounds-check validated refs.
        self.tree
            .node(unsafe { ffi::jnt_node_next_named(self.tree.raw.as_ptr(), self.id) })
    }

    /// Previous named sibling, including comments.
    pub fn previous_named_sibling(self) -> Option<Self> {
        // SAFETY: native neighbourhood lookups bounds-check validated refs.
        self.tree
            .node(unsafe { ffi::jnt_node_prev_named(self.tree.raw.as_ptr(), self.id) })
    }

    /// Parent hops to a root; every root has depth zero.
    pub fn depth(self) -> u32 {
        // SAFETY: native depth lookup bounds-checks this validated live ref.
        unsafe { ffi::jnt_node_depth(self.tree.raw.as_ptr(), self.id) }
    }
}

impl PartialEq for Node<'_> {
    fn eq(&self, other: &Self) -> bool {
        self.tree.raw == other.tree.raw && self.id == other.id
    }
}

impl Eq for Node<'_> {}

impl std::fmt::Debug for Node<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Node")
            .field("kind", &self.kind())
            .field("span", &self.byte_range())
            .finish()
    }
}
