use std::ffi::CStr;
use std::fmt;
use std::ptr::NonNull;

use crate::{Confidence, ffi};

/// A binding or native refusal.
#[derive(Clone, Debug, Eq, PartialEq)]
#[non_exhaustive]
pub enum ErrorKind {
    /// Invalid input, including an embedded NUL or a parser identity mismatch.
    Invalid,
    /// The grammar artifact could not be read.
    Io,
    /// An artifact or query is unsupported or malformed.
    Format,
    /// The requested language is absent or ambiguous.
    Language,
    /// The grammar importer or scanner refused the grammar.
    Grammar,
    /// Allocation or the native soundness survey failed.
    OutOfMemory,
    /// The linked library has an incompatible ABI.
    AbiMismatch,
    /// Strict parsing refused the reported confidence.
    ParseRefused,
    /// A status outside this binding's native vocabulary.
    Unknown(i32),
}

/// An error with its native explanation and optional parse evidence.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Error {
    /// The class of refusal.
    pub kind: ErrorKind,
    /// A diagnostic copied before the next native call can change it.
    pub message: String,
    /// Evidence retained when strict parsing refused a returned tree.
    pub confidence: Option<Confidence>,
}

/// The result type used by fallible binding operations.
pub type Result<T> = std::result::Result<T, Error>;

impl Error {
    pub(crate) fn new(kind: ErrorKind, message: impl Into<String>) -> Self {
        Self {
            kind,
            message: message.into(),
            confidence: None,
        }
    }

    pub(crate) fn native(status: i32) -> Self {
        let kind = match status {
            -1 => ErrorKind::Invalid,
            -2 => ErrorKind::Io,
            -3 => ErrorKind::Format,
            -4 => ErrorKind::Language,
            -5 => ErrorKind::Grammar,
            -6 => ErrorKind::OutOfMemory,
            other => ErrorKind::Unknown(other),
        };
        // SAFETY: the C error channel is NUL-terminated, thread-local, and
        // valid until the next jnt call; copy it before making one.
        let message = unsafe { CStr::from_ptr(ffi::jnt_last_error()) }
            .to_string_lossy()
            .into_owned();
        Self::new(kind, message)
    }

    pub(crate) fn status(status: i32) -> Result<()> {
        if status == 0 {
            Ok(())
        } else {
            Err(Self::native(status))
        }
    }

    pub(crate) fn handle(pointer: *mut ffi::Handle) -> Result<NonNull<ffi::Handle>> {
        NonNull::new(pointer).ok_or_else(|| {
            Self::new(
                ErrorKind::Format,
                "libjnt returned a null successful handle",
            )
        })
    }
}

impl fmt::Display for Error {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{}", self.message)
    }
}

impl std::error::Error for Error {}
