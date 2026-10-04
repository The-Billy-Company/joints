use std::ops::Range;
use std::ptr::{self, NonNull};

use crate::{Error, ErrorKind, Node, Parser, Point, Result, ffi};

/// How a parse stopped, independently of structural soundness.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Stop {
    /// The start symbol accepted the input, possibly after repair.
    Accepted,
    /// No terminal could lex the byte.
    Stray,
    /// A terminal was lexed but could not be folded.
    Unexpected,
    /// Input ended before the start symbol accepted.
    Truncated,
}

impl Stop {
    pub(crate) fn from_native(value: i32) -> Result<Self> {
        match value {
            0 => Ok(Self::Accepted),
            1 => Ok(Self::Stray),
            2 => Ok(Self::Unexpected),
            3 => Ok(Self::Truncated),
            _ => Err(Error::new(ErrorKind::Format, "unknown native parse stop")),
        }
    }
}

/// Parse evidence used to decide whether an outline or finding can be trusted.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Confidence {
    /// How the parse ended.
    pub stop: Stop,
    /// Refused byte for stray/unexpected stops, otherwise zero.
    pub stop_at: u32,
    /// Number of roots in the returned forest.
    pub roots: u32,
    /// Deletion repairs.
    pub mends: u32,
    /// Bytes deleted by repair.
    pub skipped: u32,
    /// Terminals inserted by repair.
    pub supplied: u32,
    /// Every node is reached once, ordered, and inside its parent.
    pub sound: bool,
}

impl Confidence {
    /// Whether this evidence satisfies the binding's default strict policy.
    pub fn is_strict(self) -> bool {
        self.stop == Stop::Accepted
            && self.roots == 1
            && self.mends == 0
            && self.skipped == 0
            && self.supplied == 0
            && self.sound
    }
}

/// One authoritative parser repair, rather than a synthetic error node.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Repair {
    /// Source span deleted; an insertion has zero width.
    pub span: Range<u32>,
    /// Whether this was an insertion rather than a deletion.
    pub supplied: bool,
    /// Inserted terminal spelling, absent for a deletion.
    pub word: Option<Vec<u8>>,
    /// Refusal that prompted this repair.
    pub stop: Stop,
    /// Number of live heads at the refusal.
    pub heads: u32,
    /// Tokens shifted during recovery.
    pub shifted: u32,
    /// Whether recovery felled the stack.
    pub felled: bool,
}

/// An owned, immutable parse and the exact bytes from which it was built.
pub struct Tree<'parser> {
    pub(crate) raw: NonNull<ffi::Handle>,
    pub(crate) parser: &'parser Parser<'parser>,
    source: Vec<u8>,
    lines: Vec<usize>,
    confidence: Confidence,
}

impl<'parser> Tree<'parser> {
    pub(crate) fn parse(parser: &'parser Parser<'parser>, source: &[u8]) -> Result<Self> {
        if source.len() > u32::MAX as usize {
            return Err(Error::new(
                ErrorKind::Invalid,
                "source exceeds native 32-bit byte offsets",
            ));
        }
        let source = source.to_vec();
        let mut raw = ptr::null_mut();
        // SAFETY: parser is live on this thread, source covers len bytes, and
        // out is writable; success transfers tree ownership to this wrapper.
        Error::status(unsafe {
            ffi::jnt_parse(
                parser.raw.as_ptr(),
                source.as_ptr().cast(),
                source.len(),
                &mut raw,
            )
        })?;
        let mut tree = Self {
            raw: Error::handle(raw)?,
            parser,
            source,
            lines: vec![0],
            confidence: Confidence {
                stop: Stop::Truncated,
                stop_at: 0,
                roots: 0,
                mends: 0,
                skipped: 0,
                supplied: 0,
                sound: false,
            },
        };
        // Install the RAII owner before surveying so any refusal frees the tree.
        // SAFETY: the tree is live, immutable, and confined to this thread;
        // the native soundness call only fills its private cached survey.
        let sound = unsafe { ffi::jnt_tree_sound(tree.raw.as_ptr()) };
        if sound < 0 {
            // jnt_tree_sound reports NOMEM without updating the error channel.
            return Err(Error::new(
                ErrorKind::OutOfMemory,
                "native tree survey could not be allocated",
            ));
        }
        // SAFETY: all accessors read this live tree and return scalar evidence.
        tree.confidence = unsafe {
            Confidence {
                stop: Stop::from_native(ffi::jnt_tree_stop(tree.raw.as_ptr()))?,
                stop_at: ffi::jnt_tree_stop_at(tree.raw.as_ptr()),
                roots: ffi::jnt_tree_roots(tree.raw.as_ptr()),
                mends: ffi::jnt_tree_mends(tree.raw.as_ptr()),
                skipped: ffi::jnt_tree_skipped(tree.raw.as_ptr()),
                supplied: ffi::jnt_tree_supplied(tree.raw.as_ptr()),
                sound: sound != 0,
            }
        };
        tree.lines.extend(
            tree.source
                .iter()
                .enumerate()
                .filter_map(|(i, byte)| (*byte == b'\n').then_some(i + 1)),
        );
        Ok(tree)
    }

    /// The evidence measured once when this tree was parsed.
    pub fn confidence(&self) -> Confidence {
        self.confidence
    }

    /// The original bytes, retained for traversal and text predicates.
    pub fn source(&self) -> &[u8] {
        &self.source
    }

    /// The terminal refused by an unexpected stop, otherwise absent.
    pub fn stop_word(&self) -> Option<&[u8]> {
        let mut len = 0;
        // SAFETY: a non-null view belongs to the live tree/parser chain.
        unsafe {
            let pointer = ffi::jnt_tree_stop_word(self.raw.as_ptr(), &mut len);
            (!pointer.is_null()).then(|| ffi::bytes(pointer, len))
        }
    }

    /// The exact deletion spans and inserted terminals recorded by recovery.
    pub fn repairs(&self) -> Result<Vec<Repair>> {
        // SAFETY: self holds the immutable tree throughout this iteration.
        let count = unsafe { ffi::jnt_tree_scars(self.raw.as_ptr()) };
        (0..count)
            .map(|i| {
                let mut scar = ffi::Scar::default();
                // SAFETY: i is within the scar list and scar is writable.
                Error::status(unsafe { ffi::jnt_tree_scar(self.raw.as_ptr(), i, &mut scar) })?;
                let mut len = 0;
                // SAFETY: the optional view belongs to this live tree; copy it
                // into the repair before returning the independently owned list.
                let word = unsafe {
                    let pointer = ffi::jnt_tree_scar_word(self.raw.as_ptr(), i, &mut len);
                    (!pointer.is_null()).then(|| ffi::bytes(pointer, len).to_vec())
                };
                Ok(Repair {
                    span: scar.at..scar.over,
                    supplied: scar.supplied != 0,
                    word,
                    stop: Stop::from_native(scar.stop)?,
                    heads: scar.heads,
                    shifted: scar.shifted,
                    felled: scar.felled != 0,
                })
            })
            .collect()
    }

    /// Root `index`, absent past the end of the forest.
    pub fn root(&self, index: u32) -> Option<Node<'_>> {
        // SAFETY: the accessor bounds-checks index into this live tree.
        self.node(unsafe { ffi::jnt_tree_root(self.raw.as_ptr(), index) })
    }

    /// Every root in source order; a strict parse has exactly one.
    pub fn roots(&self) -> impl ExactSizeIterator<Item = Node<'_>> {
        (0..self.confidence.roots).map(|i| self.root(i).expect("native root exists"))
    }

    /// The deepest node covering the given byte range, if any root covers it.
    pub fn covering(&self, span: Range<u32>) -> Option<Node<'_>> {
        if span.start > span.end || span.end as usize > self.source.len() {
            return None;
        }
        // SAFETY: the native lookup bounds-checks a range on this live tree.
        self.node(unsafe { ffi::jnt_node_covering(self.raw.as_ptr(), span.start, span.end) })
    }

    /// Convert a byte offset to a zero-based row and byte column.
    pub fn point_at(&self, offset: u32) -> Option<Point> {
        let offset = offset as usize;
        if offset > self.source.len() {
            return None;
        }
        let row = self.lines.partition_point(|start| *start <= offset) - 1;
        Some(Point {
            row: row as u32,
            column: (offset - self.lines[row]) as u32,
        })
    }

    /// The forest in tree-sitter s-expression notation, retaining anonymous
    /// nodes when `all` is true. Rendering is cached by the native tree.
    pub fn sexp(&self, all: bool) -> Result<&[u8]> {
        let mut len = 0;
        // SAFETY: the tree remains live, immutable and thread-confined; each
        // render is cached separately and never invalidates prior views.
        unsafe {
            let pointer = ffi::jnt_tree_sexp(self.raw.as_ptr(), i32::from(all), &mut len);
            if pointer.is_null() {
                Err(Error::new(
                    ErrorKind::OutOfMemory,
                    "native tree render could not be allocated",
                ))
            } else {
                Ok(ffi::bytes(pointer, len))
            }
        }
    }

    pub(crate) fn node(&self, id: u32) -> Option<Node<'_>> {
        if id == ffi::NONE {
            None
        } else {
            let mut len = 0;
            // SAFETY: jnt_node_name bounds-checks any native result ref.
            let pointer = unsafe { ffi::jnt_node_name(self.raw.as_ptr(), id, &mut len) };
            (!pointer.is_null()).then_some(Node { tree: self, id })
        }
    }
}

impl Drop for Tree<'_> {
    fn drop(&mut self) {
        // SAFETY: only this wrapper owns this non-weave tree; node borrows
        // prevent its destruction while a captured or traversed node lives.
        unsafe { ffi::jnt_tree_free(self.raw.as_ptr()) };
    }
}
