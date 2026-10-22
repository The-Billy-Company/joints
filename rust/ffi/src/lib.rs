//! ABI 2. Opaque addresses are registry keys and are never dereferenced.
//! Foreign buffers obey jnt.h. Panics are caught; allocator aborts cannot be
//! caught, so process-wide OOM is not promised to return JNT_NOMEM.
#![deny(unsafe_op_in_unsafe_fn)]
use std::{
    ffi::{CStr, c_char},
    panic::{AssertUnwindSafe, catch_unwind},
    ptr,
};
mod handles;
mod query;
mod tree;
mod weave;
use handles::*;
pub use query::*;
pub use tree::*;
pub use weave::*;
#[cfg(test)]
#[path = "../tests/abi/mod.rs"]
mod tests;
pub const JNT_OK: i32 = 0;
pub const JNT_INVALID: i32 = -1;
pub const JNT_IO: i32 = -2;
pub const JNT_FORMAT: i32 = -3;
pub const JNT_LANGUAGE: i32 = -4;
pub const JNT_GRAMMAR: i32 = -5;
pub const JNT_NOMEM: i32 = -6;
pub const JNT_NONE: u32 = u32::MAX;
macro_rules! opaque {($($n:ident),*)=>{$(#[repr(C)] pub struct $n{_private:[u8;0]})*};}
opaque!(
    JntBank,
    JntParser,
    JntTree,
    JntQuery,
    JntQueryResult,
    JntWeave
);
#[derive(Debug)]
struct Fault {
    code: i32,
    message: String,
}
type Result<T> = std::result::Result<T, Fault>;
fn fault(code: i32, message: impl ToString) -> Fault {
    Fault {
        code,
        message: message.to_string(),
    }
}
fn invalid(message: impl ToString) -> Fault {
    fault(JNT_INVALID, message)
}
fn nomem() -> Fault {
    fault(JNT_NOMEM, "boundary allocation or resource limit exceeded")
}
thread_local! {static ERROR:std::cell::RefCell<[u8;4096]>=const{std::cell::RefCell::new([0;4096])};}
fn set_error(message: &str) {
    ERROR.with(|slot| {
        let mut b = slot.borrow_mut();
        let n = message.len().min(b.len() - 1);
        for (to, &from) in b[..n].iter_mut().zip(message.as_bytes()) {
            *to = if from == 0 { b'?' } else { from };
        }
        b[n] = 0;
    });
}
fn call<T>(fallback: T, f: impl FnOnce() -> Result<T>) -> T {
    set_error("");
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(Ok(v)) => v,
        Ok(Err(e)) => {
            set_error(&e.message);
            fallback
        }
        Err(_) => {
            set_error("panic contained at the C ABI boundary");
            fallback
        }
    }
}
fn status(f: impl FnOnce() -> Result<()>) -> i32 {
    set_error("");
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(Ok(())) => JNT_OK,
        Ok(Err(e)) => {
            set_error(&e.message);
            e.code
        }
        Err(_) => {
            set_error("panic contained at the C ABI boundary");
            JNT_INVALID
        }
    }
}
macro_rules! boundary {
    ($fallback:expr, $body:block) => {
        crate::call($fallback, || $body)
    };
}
macro_rules! status_boundary {
    ($body:block) => {
        crate::status(|| $body)
    };
}
pub(crate) use {boundary, status_boundary};
unsafe fn input<'a>(data: *const c_char, len: usize) -> Result<&'a [u8]> {
    if len == 0 {
        return Ok(&[]);
    }
    if data.is_null() || len > isize::MAX as usize {
        return Err(invalid("NULL or oversized byte buffer"));
    }
    Ok(unsafe { std::slice::from_raw_parts(data.cast(), len) })
}
unsafe fn c_string<'a>(data: *const c_char) -> Result<&'a CStr> {
    if data.is_null() {
        return Err(invalid("NULL string"));
    }
    Ok(unsafe { CStr::from_ptr(data) })
}
unsafe fn output<T>(out: *mut *mut T) -> Result<()> {
    if out.is_null() {
        return Err(invalid("NULL output handle"));
    }
    unsafe { out.write(ptr::null_mut()) };
    Ok(())
}
unsafe fn view(bytes: Option<&[u8]>, len: *mut usize) -> *const c_char {
    if !len.is_null() {
        unsafe { len.write(bytes.map_or(0, <[u8]>::len)) };
    }
    bytes.map_or(ptr::null(), |b| b.as_ptr().cast())
}
fn count(n: usize) -> Result<u32> {
    u32::try_from(n).map_err(|_| nomem())
}
#[unsafe(no_mangle)]
pub extern "C" fn jnt_abi_version() -> u32 {
    set_error("");
    2
}
#[unsafe(no_mangle)]
pub extern "C" fn jnt_version() -> *const c_char {
    set_error("");
    c"0.1.0".as_ptr()
}
#[unsafe(no_mangle)]
pub extern "C" fn jnt_last_error() -> *const c_char {
    ERROR.with(|b| b.borrow().as_ptr().cast())
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_open(path: *const c_char, out: *mut *mut JntBank) -> i32 {
    status_boundary!({
        unsafe { output(out)? };
        let path = unsafe { c_string(path)? };
        #[cfg(unix)]
        let path = {
            use std::os::unix::ffi::OsStrExt;
            std::path::Path::new(std::ffi::OsStr::from_bytes(path.to_bytes()))
        };
        #[cfg(not(unix))]
        let path = std::path::Path::new(path.to_str().map_err(|_| invalid("path is not UTF-8"))?);
        let bank = joints_engine::Bank::open(path).map_err(artifact_error)?;
        let token = insert(Handle::Bank(std::sync::Arc::new(BankData { bank })))?;
        unsafe { out.write(token as *mut JntBank) };
        Ok(())
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_close(bank: *mut JntBank) {
    boundary!((), {
        remove(bank as usize, Kind::Bank)?;
        Ok(())
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_bank_count(bank: *const JntBank) -> u32 {
    boundary!(0, {
        count(bank_handle(bank as usize)?.bank.languages().len())
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_bank_title(
    bank: *const JntBank,
    i: u32,
    len: *mut usize,
) -> *const c_char {
    boundary!(ptr::null(), {
        unsafe { view(None, len) };
        let b = bank_handle(bank as usize)?;
        Ok(unsafe { view(b.bank.languages().nth(i as usize).map(str::as_bytes), len) })
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_parser_new(
    bank: *mut JntBank,
    language: *const c_char,
    out: *mut *mut JntParser,
) -> i32 {
    status_boundary!({
        unsafe { output(out)? };
        let b = bank_handle(bank as usize)?;
        let name = if language.is_null() {
            if b.bank.languages().len() != 1 {
                return Err(fault(
                    JNT_LANGUAGE,
                    format!(
                        "select a language from: {}",
                        b.bank.languages().collect::<Vec<_>>().join(" ")
                    ),
                ));
            }
            b.bank.languages().next().expect("one member")
        } else {
            unsafe { c_string(language)? }
                .to_str()
                .map_err(|_| invalid("language is not UTF-8"))?
        };
        let grammar = b.bank.get(name).map_err(artifact_error)?.ok_or_else(|| {
            fault(
                JNT_LANGUAGE,
                format!(
                    "language {name:?} is absent; available: {}",
                    b.bank.languages().collect::<Vec<_>>().join(" ")
                ),
            )
        })?;
        let mut session = grammar.session();
        session.set_recovery(joints_engine::Recovery::Fell);
        session.set_supply(joints_engine::Supply::UniqueLiteral);
        let token = insert(Handle::Parser(std::sync::Arc::new(ParserData {
            bank: bank as usize,
            _bank: b,
            grammar,
            session: std::sync::Mutex::new(session),
        })))?;
        unsafe { out.write(token as *mut JntParser) };
        Ok(())
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_parser_free(parser: *mut JntParser) {
    boundary!((), {
        remove(parser as usize, Kind::Parser)?;
        Ok(())
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_parser_language(
    parser: *const JntParser,
    len: *mut usize,
) -> *const c_char {
    boundary!(ptr::null(), {
        unsafe { view(None, len) };
        let p = parser_handle(parser as usize)?;
        Ok(unsafe { view(Some(p.grammar.name().as_bytes()), len) })
    })
}
#[doc = "C ABI entry.\n\n# Safety\nForeign pointers must satisfy include/jnt.h; opaque handles are checked tokens."]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jnt_parser_blind(parser: *const JntParser) -> u32 {
    boundary!(0, {
        count(
            parser_handle(parser as usize)?
                .grammar
                .unsupported_externals()
                .count(),
        )
    })
}
fn artifact_error(error: joints_engine::ArtifactError) -> Fault {
    let code = match &error {
        joints_engine::ArtifactError::Io(_) => JNT_IO,
        joints_engine::ArtifactError::Grammar(_) => JNT_GRAMMAR,
        _ => JNT_FORMAT,
    };
    fault(code, error)
}
fn parse_error(error: impl ToString) -> Fault {
    fault(JNT_NOMEM, error)
}
