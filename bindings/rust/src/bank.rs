use std::ffi::CString;
use std::marker::PhantomData;
use std::path::Path;
use std::ptr::{self, NonNull};
use std::rc::Rc;

use crate::{Error, ErrorKind, Query, Result, Tree, ffi};

/// An owned grammar bank, restricted to the thread that opens it.
pub struct Bank {
    pub(crate) raw: NonNull<ffi::Handle>,
    _thread: PhantomData<Rc<()>>,
}

impl Bank {
    /// Open a folio, a multi-language codex, or a tree-sitter grammar JSON.
    ///
    /// On Unix, paths preserve their original bytes. Other platforms require
    /// UTF-8 paths because that is the path representation the C API accepts.
    pub fn open(path: impl AsRef<Path>) -> Result<Self> {
        if crate::abi_version() != 2 {
            return Err(Error::new(
                ErrorKind::AbiMismatch,
                "libjnt ABI 2 is required",
            ));
        }
        let path = path.as_ref();
        #[cfg(unix)]
        let path_bytes = {
            use std::os::unix::ffi::OsStrExt;
            path.as_os_str().as_bytes()
        };
        #[cfg(not(unix))]
        let path_bytes = path
            .to_str()
            .ok_or_else(|| Error::new(ErrorKind::Invalid, "grammar path must be UTF-8"))?
            .as_bytes();
        let path = CString::new(path_bytes)
            .map_err(|_| Error::new(ErrorKind::Invalid, "grammar path contains NUL"))?;
        let mut raw = ptr::null_mut();
        // SAFETY: path is NUL-terminated and out points to writable storage;
        // success transfers the new bank's ownership to this wrapper.
        Error::status(unsafe { ffi::jnt_open(path.as_ptr(), &mut raw) })?;
        Ok(Self {
            raw: Error::handle(raw)?,
            _thread: PhantomData,
        })
    }

    /// The exact grammar titles stored in this bank.
    pub fn languages(&self) -> Vec<&[u8]> {
        // SAFETY: self keeps the bank live throughout this call and returned views.
        let count = unsafe { ffi::jnt_bank_count(self.raw.as_ptr()) };
        (0..count)
            .map(|i| {
                let mut len = 0;
                // SAFETY: i is below the bank count; its view lives until bank drop.
                unsafe {
                    let pointer = ffi::jnt_bank_title(self.raw.as_ptr(), i, &mut len);
                    ffi::bytes(pointer, len)
                }
            })
            .collect()
    }

    /// Borrow one language's parser; `None` requires an unambiguous bank.
    pub fn parser(&self, language: Option<&str>) -> Result<Parser<'_>> {
        Parser::new(BankOwner::Borrowed(self), language)
    }

    /// Transfer this bank into one language's parser for reuse in this thread.
    ///
    /// `None` requires an unambiguous bank. The returned parser owns its bank,
    /// so its lifetime does not borrow this stack frame. Trees and queries still
    /// borrow the parser, which remains restricted to the creating thread.
    ///
    /// ```no_run
    /// use joints::{Bank, Parser};
    /// fn worker_parser() -> joints::Result<Parser<'static>> {
    ///     Bank::open("python.folio")?.into_parser(Some("python"))
    /// }
    /// ```
    ///
    /// Consuming the bank prevents another handle from closing it prematurely:
    ///
    /// ```compile_fail
    /// use joints::Bank;
    /// let bank = Bank::open("json.folio").unwrap();
    /// let parser = bank.into_parser(None).unwrap();
    /// drop(bank);
    /// let _tree = parser.parse(b"1").unwrap();
    /// ```
    pub fn into_parser(self, language: Option<&str>) -> Result<Parser<'static>> {
        Parser::new(BankOwner::Owned(self), language)
    }
}

impl Drop for Bank {
    fn drop(&mut self) {
        // SAFETY: borrowed parsers cannot survive this drop, and an owning
        // parser frees its native handle before dropping this bank.
        unsafe { ffi::jnt_close(self.raw.as_ptr()) };
    }
}

enum BankOwner<'bank> {
    Borrowed(&'bank Bank),
    Owned(Bank),
}

impl BankOwner<'_> {
    fn bank(&self) -> &Bank {
        match self {
            Self::Borrowed(bank) => bank,
            Self::Owned(bank) => bank,
        }
    }
}

/// One thread's parser, borrowing or owning the bank that owns its grammar.
///
/// An owned parser has no external bank borrow; its trees and queries still
/// cannot outlive it:
///
/// ```compile_fail
/// use joints::Bank;
/// let parser = Bank::open("json.folio").unwrap().into_parser(None).unwrap();
/// let tree = parser.parse(b"1").unwrap();
/// drop(parser);
/// let _node = tree.root(0).unwrap();
/// ```
///
/// ```compile_fail
/// use joints::Bank;
/// let parser = Bank::open("json.folio").unwrap().into_parser(None).unwrap();
/// let query = parser.query("(number) @n").unwrap();
/// drop(parser);
/// let _name = query.capture_name(0);
/// ```
///
/// Owning the bank does not allow a parser to move between threads or be shared:
///
/// ```compile_fail
/// use joints::Parser;
/// fn requires_send<T: Send>() {}
/// requires_send::<Parser<'static>>();
/// ```
///
/// ```compile_fail
/// use joints::Parser;
/// fn requires_sync<T: Sync>() {}
/// requires_sync::<Parser<'static>>();
/// ```
pub struct Parser<'bank> {
    pub(crate) raw: NonNull<ffi::Handle>,
    _bank: BankOwner<'bank>,
}

impl<'bank> Parser<'bank> {
    fn new(bank: BankOwner<'bank>, language: Option<&str>) -> Result<Self> {
        let language = language
            .map(CString::new)
            .transpose()
            .map_err(|_| Error::new(ErrorKind::Invalid, "language contains NUL"))?;
        let mut raw = ptr::null_mut();
        // SAFETY: this owner keeps the native bank live. The parser refers to
        // its native allocation, not the Rust Bank's address, so moving an
        // owned Bank into Parser is safe. Language is NUL-terminated and out
        // points to writable storage.
        Error::status(unsafe {
            ffi::jnt_parser_new(
                bank.bank().raw.as_ptr(),
                language.as_ref().map_or(ptr::null(), |s| s.as_ptr()),
                &mut raw,
            )
        })?;
        Ok(Self {
            raw: Error::handle(raw)?,
            _bank: bank,
        })
    }
}

impl Parser<'_> {
    /// The exact grammar title.
    pub fn language(&self) -> &[u8] {
        let mut len = 0;
        // SAFETY: self keeps both parser and bank alive for the returned view.
        unsafe {
            let pointer = ffi::jnt_parser_language(self.raw.as_ptr(), &mut len);
            ffi::bytes(pointer, len)
        }
    }

    /// External terminals for which this build has no scanner.
    pub fn blind_terminals(&self) -> u32 {
        // SAFETY: the parser is live and cannot be accessed by another thread.
        unsafe { ffi::jnt_parser_blind(self.raw.as_ptr()) }
    }

    /// Parse only when accepted, sound, with one root and no repairs.
    pub fn parse(&self, source: impl AsRef<[u8]>) -> Result<Tree<'_>> {
        let tree = self.parse_partial(source)?;
        if tree.confidence().is_strict() {
            Ok(tree)
        } else {
            let confidence = tree.confidence();
            Err(Error {
                kind: ErrorKind::ParseRefused,
                message: format!("strict parse refused: {confidence:?}"),
                confidence: Some(confidence),
            })
        }
    }

    /// Parse while retaining partial forests and exact repair evidence.
    pub fn parse_partial(&self, source: impl AsRef<[u8]>) -> Result<Tree<'_>> {
        Tree::parse(self, source.as_ref())
    }

    /// Compile tree-sitter query notation against this exact parser.
    pub fn query(&self, source: &str) -> Result<Query<'_>> {
        Query::compile(self, source)
    }
}

impl Drop for Parser<'_> {
    fn drop(&mut self) {
        // SAFETY: borrowed trees and queries cannot survive this parser.
        // Rust drops _bank only after this destructor returns, so an owned
        // bank remains live while its native parser is freed.
        unsafe { ffi::jnt_parser_free(self.raw.as_ptr()) };
    }
}
