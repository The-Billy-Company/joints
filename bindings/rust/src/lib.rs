//! Experimental, safe access to an already-built `libjnt`.
//!
//! A [`Bank`] owns a grammar artifact; a [`Parser`] borrows or owns its bank;
//! [`Tree`] and [`Query`] borrow their parser. Nodes borrow an immutable tree. None of
//! these handles can move between threads or be shared across them: create a
//! bank and parser in each worker. The crate never builds Zig during Cargo
//! compilation. See the package README for `JOINTS_LIB_DIR` setup.
//!
//! [`Parser::parse`] refuses partial, repaired, or structurally unsound trees.
//! [`Parser::parse_partial`] retains their evidence for diagnostics instead.
//! Grammar names and source text are exposed as bytes to preserve exact names,
//! offsets, and non-UTF-8 source. Query matching always uses the bytes retained
//! by the tree, and the treatment of foreign predicates is explicit.
//!
//! Handle lifetimes also enforce destruction order:
//!
//! ```compile_fail
//! use joints::Bank;
//! let bank = Bank::open("json.folio").unwrap();
//! let parser = bank.parser(None).unwrap();
//! drop(bank);
//! let _tree = parser.parse(b"1").unwrap();
//! ```
//!
//! ```compile_fail
//! use joints::Bank;
//! let bank = Bank::open("json.folio").unwrap();
//! let parser = bank.parser(None).unwrap();
//! let tree = parser.parse(b"1").unwrap();
//! drop(parser);
//! let _node = tree.root(0).unwrap();
//! ```
//!
//! ```compile_fail
//! use joints::Bank;
//! let bank = Bank::open("json.folio").unwrap();
//! let parser = bank.parser(None).unwrap();
//! let tree = parser.parse(b"1").unwrap();
//! let node = tree.root(0).unwrap();
//! drop(tree);
//! let _text = node.text();
//! ```
//!
//! ```compile_fail
//! use joints::{Bank, ForeignPolicy};
//! let bank = Bank::open("json.folio").unwrap();
//! let parser = bank.parser(None).unwrap();
//! let tree = parser.parse(b"1").unwrap();
//! let query = parser.query("(number) @n").unwrap();
//! let matches = query.matches(&tree, ForeignPolicy::Refuse).unwrap();
//! drop(query);
//! let _name = matches[0].captures[0].name;
//! ```
//!
//! ```compile_fail
//! use joints::Bank;
//! let bank = Bank::open("json.folio").unwrap();
//! let parser = bank.parser(None).unwrap();
//! let query = parser.query("(number) @n").unwrap();
//! drop(parser);
//! let _name = query.capture_name(0);
//! ```
//!
//! ```compile_fail
//! use joints::Bank;
//! fn requires_send<T: Send>() {}
//! requires_send::<Bank>();
//! ```
//!
//! ```compile_fail
//! use joints::Bank;
//! fn requires_sync<T: Sync>() {}
//! requires_sync::<Bank>();
//! ```

mod bank;
mod error;
mod ffi;
mod node;
mod query;
mod tree;

pub use bank::{Bank, Parser};
pub use error::{Error, ErrorKind, Result};
pub use node::{Node, Point};
pub use query::{Capture, ForeignPolicy, Match, Query};
pub use tree::{Confidence, Repair, Stop, Tree};

/// The native package version, borrowed from the linked library.
pub fn version() -> &'static str {
    // SAFETY: the C contract gives this pointer a static lifetime and a NUL.
    unsafe { std::ffi::CStr::from_ptr(ffi::jnt_version()) }
        .to_str()
        .unwrap_or("<invalid native version>")
}

/// The compatibility version reported by the linked C ABI.
pub fn abi_version() -> u32 {
    // SAFETY: this call has no inputs or handle lifetimes.
    unsafe { ffi::jnt_abi_version() }
}
