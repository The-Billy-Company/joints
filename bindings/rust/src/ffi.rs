use std::ffi::{c_char, c_void};

pub(crate) type Handle = c_void;
pub(crate) const NONE: u32 = u32::MAX;

#[derive(Default)]
#[repr(C)]
pub(crate) struct Scar {
    pub at: u32,
    pub over: u32,
    pub supplied: u32,
    pub heads: u32,
    pub shifted: u32,
    pub felled: u32,
    pub stop: i32,
}

unsafe extern "C" {
    pub fn jnt_abi_version() -> u32;
    pub fn jnt_version() -> *const c_char;
    pub fn jnt_last_error() -> *const c_char;
    pub fn jnt_open(path: *const c_char, out: *mut *mut Handle) -> i32;
    pub fn jnt_close(bank: *mut Handle);
    pub fn jnt_bank_count(bank: *const Handle) -> u32;
    pub fn jnt_bank_title(bank: *const Handle, i: u32, len: *mut usize) -> *const c_char;
    pub fn jnt_parser_new(bank: *mut Handle, language: *const c_char, out: *mut *mut Handle)
    -> i32;
    pub fn jnt_parser_free(parser: *mut Handle);
    pub fn jnt_parser_language(parser: *const Handle, len: *mut usize) -> *const c_char;
    pub fn jnt_parser_blind(parser: *const Handle) -> u32;
    pub fn jnt_parse(
        parser: *mut Handle,
        text: *const c_char,
        len: usize,
        out: *mut *mut Handle,
    ) -> i32;
    pub fn jnt_tree_free(tree: *mut Handle);
    pub fn jnt_tree_stop(tree: *const Handle) -> i32;
    pub fn jnt_tree_stop_at(tree: *const Handle) -> u32;
    pub fn jnt_tree_stop_word(tree: *const Handle, len: *mut usize) -> *const c_char;
    pub fn jnt_tree_mends(tree: *const Handle) -> u32;
    pub fn jnt_tree_skipped(tree: *const Handle) -> u32;
    pub fn jnt_tree_supplied(tree: *const Handle) -> u32;
    pub fn jnt_tree_sound(tree: *mut Handle) -> i32;
    pub fn jnt_tree_sexp(tree: *mut Handle, all: i32, len: *mut usize) -> *const c_char;
    pub fn jnt_tree_scars(tree: *const Handle) -> u32;
    pub fn jnt_tree_scar(tree: *const Handle, i: u32, out: *mut Scar) -> i32;
    pub fn jnt_tree_scar_word(tree: *const Handle, i: u32, len: *mut usize) -> *const c_char;
    pub fn jnt_tree_roots(tree: *const Handle) -> u32;
    pub fn jnt_tree_root(tree: *const Handle, i: u32) -> u32;
    pub fn jnt_node_name(tree: *const Handle, node: u32, len: *mut usize) -> *const c_char;
    pub fn jnt_node_named(tree: *const Handle, node: u32) -> i32;
    pub fn jnt_node_start(tree: *const Handle, node: u32) -> u32;
    pub fn jnt_node_end(tree: *const Handle, node: u32) -> u32;
    pub fn jnt_node_kids(tree: *const Handle, node: u32) -> u32;
    pub fn jnt_node_kid(tree: *const Handle, node: u32, i: u32) -> u32;
    pub fn jnt_node_field(tree: *const Handle, node: u32, len: *mut usize) -> *const c_char;
    pub fn jnt_node_parent(tree: *const Handle, node: u32) -> u32;
    pub fn jnt_node_next(tree: *const Handle, node: u32) -> u32;
    pub fn jnt_node_prev(tree: *const Handle, node: u32) -> u32;
    pub fn jnt_node_next_named(tree: *const Handle, node: u32) -> u32;
    pub fn jnt_node_prev_named(tree: *const Handle, node: u32) -> u32;
    pub fn jnt_node_by_field(
        tree: *const Handle,
        node: u32,
        field: *const c_char,
        len: usize,
    ) -> u32;
    pub fn jnt_node_depth(tree: *const Handle, node: u32) -> u32;
    pub fn jnt_node_covering(tree: *const Handle, from: u32, to: u32) -> u32;
    pub fn jnt_query_compile(
        parser: *const Handle,
        source: *const c_char,
        len: usize,
        out: *mut *mut Handle,
    ) -> i32;
    pub fn jnt_query_free(query: *mut Handle);
    pub fn jnt_query_pattern_count(query: *const Handle) -> u32;
    pub fn jnt_query_capture_count(query: *const Handle) -> u32;
    pub fn jnt_query_capture_name(query: *const Handle, id: u32, len: *mut usize) -> *const c_char;
    pub fn jnt_query_exec(
        query: *const Handle,
        tree: *const Handle,
        text: *const c_char,
        len: usize,
        foreign: i32,
        out: *mut *mut Handle,
    ) -> i32;
    pub fn jnt_query_result_free(result: *mut Handle);
    pub fn jnt_query_result_count(result: *const Handle) -> u32;
    pub fn jnt_query_result_pattern(result: *const Handle, i: u32) -> u32;
    pub fn jnt_query_result_capture_count(result: *const Handle, i: u32) -> u32;
    pub fn jnt_query_result_capture_id(result: *const Handle, i: u32, capture: u32) -> u32;
    pub fn jnt_query_result_capture_node(result: *const Handle, i: u32, capture: u32) -> u32;
}

/// Borrow a native pointer/length view only for its owner's lifetime.
pub(crate) unsafe fn bytes<'owner>(pointer: *const c_char, len: usize) -> &'owner [u8] {
    if len == 0 {
        return &[];
    }
    // SAFETY: each caller obtains this view from a live native owner and
    // constrains 'owner to its borrow; the C contract supplies len bytes.
    unsafe { std::slice::from_raw_parts(pointer.cast(), len) }
}
