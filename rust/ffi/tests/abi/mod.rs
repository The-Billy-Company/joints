use crate::*;
use std::{
    ffi::{CStr, CString},
    mem::{align_of, size_of},
    sync::atomic::{AtomicUsize, Ordering},
};
fn error() -> String {
    // SAFETY: the error channel is thread-local, NUL-terminated, and copied before another ABI
    // call.
    unsafe { CStr::from_ptr(jnt_last_error()) }
        .to_string_lossy()
        .into_owned()
}
fn grammar() -> CString {
    CString::new(format!(
        "{}/../../test/grammar/json.json",
        env!("CARGO_MANIFEST_DIR")
    ))
    .unwrap()
}
struct Fixture {
    bank: *mut JntBank,
    parser: *mut JntParser,
}
impl Fixture {
    fn new() -> Self {
        // SAFETY: CString lives through jnt_open; output pointers address local storage and
        // handles are closed by Fixture.
        unsafe {
            let mut bank = ptr::null_mut();
            assert_eq!(jnt_open(grammar().as_ptr(), &mut bank), 0, "{}", error());
            let mut parser = ptr::null_mut();
            assert_eq!(
                jnt_parser_new(bank, ptr::null(), &mut parser),
                0,
                "{}",
                error()
            );
            Self { bank, parser }
        }
    }
    fn parse(&self, text: &[u8]) -> *mut JntTree {
        // SAFETY: text stays readable for the call, tree points to local writable storage, and
        // self owns the parser.
        unsafe {
            let mut tree = ptr::null_mut();
            assert_eq!(
                jnt_parse(self.parser, text.as_ptr().cast(), text.len(), &mut tree),
                0,
                "{}",
                error()
            );
            assert!(!tree.is_null());
            tree
        }
    }
    fn query(&self, text: &[u8]) -> *mut JntQuery {
        // SAFETY: text stays readable for the call, q points to local writable storage, and
        // self owns the parser.
        unsafe {
            let mut q = ptr::null_mut();
            assert_eq!(
                jnt_query_compile(self.parser, text.as_ptr().cast(), text.len(), &mut q),
                0,
                "{}",
                error()
            );
            q
        }
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        // SAFETY: all test-owned dependent handles are freed before this fixture closes its
        // parser and bank.
        unsafe {
            jnt_parser_free(self.parser);
            assert_eq!(error(), "");
            jnt_close(self.bank);
            assert_eq!(error(), "");
        }
    }
}
unsafe fn bytes<'a>(p: *const c_char, n: usize) -> &'a [u8] {
    assert!(!p.is_null());
    // SAFETY: the caller retains the native owner and guarantees n readable bytes
    // for the returned borrow.
    unsafe { std::slice::from_raw_parts(p.cast(), n) }
}
#[test]
fn versions_status_tls_and_opaque_handle_checks() {
    // SAFETY: strings and outputs are valid; NULL is rejected and invented/wrong-kind opaque
    // tokens are only registry keys.
    unsafe {
        assert_eq!(jnt_abi_version(), 2);
        assert_eq!(CStr::from_ptr(jnt_version()).to_bytes(), b"0.1.0");
        let mut out = ptr::dangling_mut::<JntBank>();
        assert_eq!(jnt_open(ptr::null(), &mut out), JNT_INVALID);
        assert!(out.is_null());
        let first = error();
        assert!(!first.is_empty());
        assert_eq!(error(), first);
        assert_eq!(jnt_bank_count(0xdeadusize as *const JntBank), 0);
        assert!(error().contains("handle"));
        assert_eq!(jnt_abi_version(), 2);
        assert_eq!(error(), "");
        let f = Fixture::new();
        assert_eq!(jnt_bank_count(f.parser.cast()), 0);
        assert!(error().contains("kind"));
        assert_eq!(jnt_parser_blind(f.parser), 0);
        assert_eq!(error(), "");
        let mut parser = ptr::null_mut();
        assert_eq!(
            jnt_parser_new(f.bank, c"missing".as_ptr(), &mut parser),
            JNT_LANGUAGE
        );
        assert!(parser.is_null());
        assert_eq!(jnt_open(grammar().as_ptr(), ptr::null_mut()), JNT_INVALID);
    }
}
#[test]
fn owned_tree_nodes_navigation_and_cached_render() {
    // SAFETY: fixtures retain owners, outputs are local storage, and native byte views are
    // consumed before freeing their tree.
    unsafe {
        let f = Fixture::new();
        let mut source = Vec::from(b"{\"a\":[1,2]}".as_slice());
        let tree = f.parse(&source);
        source.fill(b'x');
        assert_eq!(jnt_tree_stop(tree), 0);
        assert_eq!(jnt_tree_stop_at(tree), 0);
        assert_eq!(jnt_tree_sound(tree), 1);
        assert_eq!(jnt_tree_roots(tree), 1);
        let root = jnt_tree_root(tree, 0);
        let object = jnt_node_kid(tree, root, 0);
        let pair = jnt_node_kid(tree, object, 1);
        let array = jnt_node_by_field(tree, pair, c"value".as_ptr(), 5);
        let one = jnt_node_kid(tree, array, 1);
        let comma = jnt_node_next(tree, one);
        let two = jnt_node_next_named(tree, one);
        let mut len = 999;
        assert_eq!(bytes(jnt_node_name(tree, root, &mut len), len), b"document");
        assert_eq!(bytes(jnt_node_field(tree, array, &mut len), len), b"value");
        assert_eq!(jnt_node_named(tree, comma), 0);
        assert_eq!(jnt_node_parent(tree, one), array);
        assert_eq!(jnt_node_prev(tree, two), comma);
        assert_eq!(jnt_node_prev_named(tree, two), one);
        assert_eq!(jnt_node_covering(tree, 6, 7), one);
        assert_eq!(jnt_node_start(tree, one), 6);
        assert_eq!(jnt_node_end(tree, one), 7);
        assert!(jnt_node_depth(tree, one) > jnt_node_depth(tree, array));
        assert!(jnt_node_spread(tree, array) > 2);
        assert_eq!(jnt_node_parent(tree, root), JNT_NONE);
        assert_eq!(jnt_node_kid(tree, root, 999), JNT_NONE);
        assert_eq!(jnt_tree_root(tree, 999), JNT_NONE);
        assert_eq!(jnt_node_kids(tree, JNT_NONE), 0);
        assert_eq!(jnt_node_start(tree, JNT_NONE), 0);
        assert_eq!(jnt_node_end(tree, JNT_NONE), 0);
        assert_eq!(jnt_node_spread(tree, JNT_NONE), 0);
        assert_eq!(jnt_node_covering(tree, 8, 2), JNT_NONE);
        assert_eq!(jnt_node_by_field(tree, pair, ptr::null(), 0), JNT_NONE);
        let p = jnt_tree_sexp(tree, 0, &mut len);
        let rendered = bytes(p, len).to_vec();
        assert_eq!(rendered,b"(document (object (pair key: (string (string_content)) value: (array (number) (number)))))\n");
        assert_eq!(*p.add(len), 0);
        assert_eq!(jnt_tree_sexp(tree, 0, ptr::null_mut()), p);
        assert!(
            CStr::from_ptr(jnt_tree_sexp(tree, 1, &mut len))
                .to_bytes()
                .contains(&b'[')
        );
        let second = f.parse(b"true");
        jnt_tree_free(second);
        assert_eq!(jnt_node_end(tree, root), 11);
        jnt_tree_free(tree);
        assert_eq!(jnt_tree_roots(tree), 0);
        assert!(!error().is_empty());
    }
}
#[test]
fn indices_and_null_length_contracts() {
    // SAFETY: outputs address local storage; NULL buffers are either empty or rejected before
    // any read.
    unsafe {
        let f = Fixture::new();
        let mut len = 123;
        assert!(jnt_bank_title(f.bank, 99, &mut len).is_null());
        assert_eq!(len, 0);
        assert_eq!(error(), "");
        assert_eq!(bytes(jnt_bank_title(f.bank, 0, &mut len), len), b"json");
        assert_eq!(bytes(jnt_parser_language(f.parser, &mut len), len), b"json");
        let mut t = ptr::dangling_mut::<JntTree>();
        assert_eq!(jnt_parse(f.parser, ptr::null(), 1, &mut t), JNT_INVALID);
        assert!(t.is_null());
        assert_eq!(jnt_parse(f.parser, ptr::null(), 0, &mut t), 0);
        assert!(!t.is_null());
        assert!(jnt_tree_stop_word(t, &mut len).is_null());
        assert_eq!(len, 0);
        assert!(jnt_node_name(t, JNT_NONE, &mut len).is_null());
        assert_eq!(len, 0);
        assert!(jnt_node_field(t, JNT_NONE, &mut len).is_null());
        assert_eq!(len, 0);
        jnt_tree_free(t);
    }
}
#[test]
fn scars_are_real_and_checked() {
    // SAFETY: the fixture retains the tree, output structs/lengths are writable locals, and
    // NULL outputs are rejected.
    unsafe {
        let f = Fixture::new();
        let tree = f.parse(b"{\"a\" @ 2}");
        let n = jnt_tree_scars(tree);
        assert!(n > 0);
        assert_eq!(n, jnt_tree_mends(tree) + jnt_tree_supplied(tree));
        let mut skipped = 0;
        let mut supplied = 0;
        for i in 0..n {
            let mut scar = JntScar::default();
            assert_eq!(jnt_tree_scar(tree, i, &mut scar), 0);
            assert!([1, 2].contains(&scar.stop));
            let mut len = 999;
            let word = jnt_tree_scar_word(tree, i, &mut len);
            if scar.supplied != 0 {
                supplied += 1;
                assert_eq!(scar.at, scar.over);
                assert!(!word.is_null());
                assert!(len > 0);
            } else {
                skipped += scar.over - scar.at;
                assert!(word.is_null());
                assert_eq!(len, 0);
            }
        }
        assert_eq!(skipped, jnt_tree_skipped(tree));
        assert_eq!(supplied, jnt_tree_supplied(tree));
        assert_eq!(jnt_tree_scar(tree, n, &mut JntScar::default()), JNT_INVALID);
        assert_eq!(jnt_tree_scar(tree, 0, ptr::null_mut()), JNT_INVALID);
        jnt_tree_free(tree);
    }
}
#[test]
fn query_results_own_arrays_preserve_order_and_check_exact_owner() {
    // SAFETY: buffers remain live, outputs are writable locals, and result dependencies prevent
    // premature owner removal.
    unsafe {
        let f = Fixture::new();
        let text = b"[1,22,3]";
        let tree = f.parse(text);
        let query = f.query(b"(number) @n");
        let mut len = 0;
        assert_eq!(jnt_query_pattern_count(query), 1);
        assert_eq!(jnt_query_capture_count(query), 1);
        assert_eq!(bytes(jnt_query_capture_name(query, 0, &mut len), len), b"n");
        assert!(jnt_query_capture_name(query, 99, &mut len).is_null());
        assert_eq!(len, 0);
        let mut result = ptr::null_mut();
        assert_eq!(
            jnt_query_exec(
                query,
                tree,
                text.as_ptr().cast(),
                text.len(),
                0,
                &mut result
            ),
            0
        );
        assert_eq!(jnt_query_result_count(result), 3);
        assert_eq!(jnt_query_result_pattern(result, 0), 0);
        assert_eq!(jnt_query_result_capture_count(result, 0), 1);
        assert_eq!(jnt_query_result_capture_id(result, 0, 0), 0);
        assert_eq!(
            jnt_node_start(tree, jnt_query_result_capture_node(result, 1, 0)),
            3
        );
        assert_eq!(jnt_query_result_pattern(result, 99), JNT_NONE);
        assert_eq!(jnt_query_result_capture_count(result, 99), 0);
        assert_eq!(jnt_query_result_capture_id(result, 0, 99), JNT_NONE);
        assert_eq!(jnt_query_result_capture_node(result, 99, 0), JNT_NONE);
        jnt_query_free(query);
        assert!(error().contains("dependent"));
        jnt_tree_free(tree);
        assert!(error().contains("dependent"));
        jnt_query_result_free(result);
        let mut bad = ptr::dangling_mut::<JntQueryResult>();
        assert_eq!(
            jnt_query_exec(
                query,
                tree,
                b"[9,22,3]".as_ptr().cast(),
                text.len(),
                0,
                &mut bad
            ),
            JNT_INVALID
        );
        assert!(bad.is_null());
        assert_eq!(
            jnt_query_exec(query, tree, text.as_ptr().cast(), text.len(), 99, &mut bad),
            JNT_INVALID
        );
        let mut other = ptr::null_mut();
        assert_eq!(jnt_parser_new(f.bank, ptr::null(), &mut other), 0);
        let mut otherq = ptr::null_mut();
        assert_eq!(
            jnt_query_compile(other, b"(number)".as_ptr().cast(), 8, &mut otherq),
            0
        );
        assert_eq!(
            jnt_query_exec(otherq, tree, text.as_ptr().cast(), text.len(), 0, &mut bad),
            JNT_INVALID
        );
        assert!(bad.is_null());
        jnt_query_free(otherq);
        jnt_parser_free(other);
        jnt_query_free(query);
        jnt_tree_free(tree);
    }
}
#[test]
fn foreign_refusal_is_eager_and_clean_empty_is_success() {
    // SAFETY: C literals cover each stated length; outputs are writable locals and dependent
    // handles are freed in order.
    unsafe {
        let f = Fixture::new();
        let tree = f.parse(b"1");
        let q = f.query(b"(number) @ok\n((number) @n (#foreign? @n))");
        let mut result = ptr::dangling_mut::<JntQueryResult>();
        assert_eq!(
            jnt_query_exec(q, tree, c"1".as_ptr(), 1, 0, &mut result),
            JNT_FORMAT
        );
        assert!(result.is_null());
        assert_eq!(jnt_query_exec(q, tree, c"1".as_ptr(), 1, 1, &mut result), 0);
        assert_eq!(jnt_query_result_count(result), 2);
        jnt_query_result_free(result);
        assert_eq!(jnt_query_exec(q, tree, c"1".as_ptr(), 1, 2, &mut result), 0);
        assert_eq!(jnt_query_result_count(result), 1);
        jnt_query_result_free(result);
        jnt_query_free(q);
        let q = f.query(b"(object) @o");
        assert_eq!(jnt_query_exec(q, tree, c"1".as_ptr(), 1, 0, &mut result), 0);
        assert_eq!(jnt_query_result_count(result), 0);
        jnt_query_result_free(result);
        jnt_query_free(q);
        let mut q = ptr::dangling_mut::<JntQuery>();
        assert_eq!(
            jnt_query_compile(f.parser, c"(unrecognized_kind)".as_ptr(), 19, &mut q),
            JNT_FORMAT
        );
        assert!(q.is_null());
        jnt_tree_free(tree);
    }
}
#[test]
fn lifecycle_rejects_stale_tokens_and_parent_free() {
    // SAFETY: opaque tokens are never dereferenced; registry checks reject stale tokens and
    // owners with dependents.
    unsafe {
        let f = Fixture::new();
        let tree = f.parse(b"1");
        jnt_parser_free(f.parser);
        assert!(error().contains("dependent"));
        jnt_close(f.bank);
        assert!(error().contains("dependent"));
        jnt_tree_free(tree);
        assert_eq!(error(), "");
        jnt_tree_free(tree);
        assert!(error().contains("handle"));
        let next = f.parse(b"2");
        assert_ne!(next, tree);
        jnt_tree_free(next);
    }
}
#[test]
fn weave_borrowed_handle_survives_edits_and_warp_with_atomic_failures() {
    // SAFETY: literal inputs and local outputs remain valid; byte views are consumed before
    // successful weave mutations.
    unsafe {
        let f = Fixture::new();
        let mut weave = ptr::null_mut();
        assert_eq!(jnt_weave_new(f.parser, &mut weave), 0);
        assert!(jnt_weave_tree(weave).is_null());
        assert_eq!(jnt_weave_len(weave), 0);
        assert_eq!(jnt_weave_amend(weave, 0, 0, ptr::null(), 0), JNT_INVALID);
        assert_eq!(jnt_weave_warp(weave, c"[1,2]".as_ptr(), 5), 0);
        let tree = jnt_weave_tree(weave);
        assert!(!tree.is_null());
        jnt_tree_free(tree);
        assert_eq!(jnt_tree_stop(tree), 0);
        assert_eq!(jnt_weave_amend(weave, 3, 4, c"22".as_ptr(), 2), 0);
        assert_eq!(jnt_weave_tree(weave), tree);
        assert_eq!(jnt_weave_len(weave), 6);
        let mut len = 0;
        assert_eq!(
            bytes(jnt_tree_sexp(tree, 0, &mut len), len),
            b"(document (array (number) (number)))\n"
        );
        assert_eq!(
            jnt_weave_amend(weave, 99, 100, c"x".as_ptr(), 1),
            JNT_INVALID
        );
        assert_eq!(jnt_weave_len(weave), 6);
        assert_eq!(jnt_weave_amend(weave, 4, 2, ptr::null(), 0), JNT_INVALID);
        assert_eq!(jnt_weave_len(weave), 6);
        let q = f.query(b"(number) @n");
        let mut result = ptr::null_mut();
        assert_eq!(
            jnt_query_exec(q, tree, c"[1,22]".as_ptr(), 6, 0, &mut result),
            0
        );
        assert_eq!(jnt_weave_amend(weave, 1, 2, c"3".as_ptr(), 1), JNT_INVALID);
        jnt_weave_free(weave);
        assert!(!error().is_empty());
        assert_eq!(jnt_query_result_count(result), 2);
        jnt_query_result_free(result);
        jnt_query_free(q);
        for policy in 0..=2 {
            assert_eq!(jnt_weave_policy(weave, policy), 0);
            assert_eq!(jnt_weave_amend(weave, 1, 2, c"3".as_ptr(), 1), 0);
            let mut cost = JntCost::default();
            assert_eq!(jnt_weave_cost(weave, &mut cost), 0);
            assert!(cost.leaves > 0);
            assert!(cost.height > 0);
            assert_eq!(cost.lifts, 0);
            assert_eq!(cost.skipped, 0);
            assert_eq!(cost.carried, 0);
            assert_eq!(cost.nodes, jnt_node_spread(tree, jnt_tree_root(tree, 0)));
            if policy == 2 {
                assert!(cost.stood <= 1);
                assert!(cost.minted > 0);
                assert_eq!(cost.kept + cost.minted, cost.leaves);
                let cold = f.parse(b"[3,22]");
                let edited = bytes(jnt_tree_sexp(tree, 1, &mut len), len).to_vec();
                assert_eq!(bytes(jnt_tree_sexp(cold, 1, &mut len), len), edited);
                assert_eq!(jnt_tree_stop(cold), jnt_tree_stop(tree));
                jnt_tree_free(cold);
            }
        }
        assert_eq!(jnt_weave_policy(weave, 99), JNT_INVALID);
        assert_eq!(jnt_weave_warp(weave, c"true".as_ptr(), 4), 0);
        assert_eq!(jnt_weave_tree(weave), tree);
        assert_eq!(jnt_weave_len(weave), 4);
        jnt_weave_free(weave);
        assert_eq!(jnt_tree_roots(tree), 0);
        assert!(!error().is_empty());
    }
}
#[test]
fn independent_workers_and_thread_local_errors() {
    let workers: Vec<_> = (0..4)
        .map(|_| {
            std::thread::spawn(|| {
                let f = Fixture::new();
                for _ in 0..3 {
                    // SAFETY: each thread owns its fixture and tree; NULL opaque handles are
                    // rejected by the registry.
                    unsafe {
                        let t = f.parse(b"[1,2]");
                        assert_eq!(jnt_tree_sound(t), 1);
                        jnt_tree_free(t);
                        assert_eq!(jnt_tree_roots(ptr::null()), 0);
                        let e = error();
                        std::thread::yield_now();
                        assert_eq!(error(), e);
                    }
                }
            })
        })
        .collect();
    for worker in workers {
        worker.join().unwrap();
    }
    assert_eq!(jnt_abi_version(), 2);
    assert_eq!(error(), "");
}
#[test]
fn panic_wrapper_contains_unwinds_and_clears_after_success() {
    assert_eq!(
        call(7, || -> Result<i32> { panic!("intentional ABI control") }),
        7
    );
    assert!(error().contains("panic contained"));
    assert_eq!(status(|| Ok(())), 0);
    assert_eq!(error(), "");
}
#[test]
fn header_layout_and_complete_declaration_roster() {
    assert_eq!(size_of::<JntScar>(), 28);
    assert_eq!(align_of::<JntScar>(), 4);
    assert_eq!(size_of::<JntCost>(), 44);
    assert_eq!(align_of::<JntCost>(), 4);
    let header = include_str!("../../../../include/jnt.h");
    let mut names = Vec::new();
    for line in header.lines() {
        let line = line.trim();
        if [
            "uint32_t ",
            "int32_t ",
            "size_t ",
            "void ",
            "const char *",
            "jnt_tree *",
        ]
        .iter()
        .any(|prefix| line.starts_with(prefix))
        {
            if let Some((before, _)) = line.split_once('(') {
                if let Some(at) = before.rfind("jnt_") {
                    names.push(&before[at..]);
                }
            }
        }
    }
    assert_eq!(names.len(), 62);
    let sources = [
        include_str!("../../src/lib.rs"),
        include_str!("../../src/tree.rs"),
        include_str!("../../src/query.rs"),
        include_str!("../../src/weave.rs"),
    ]
    .join("\n");
    for name in &names {
        assert!(sources.contains(&format!("{name}(")), "missing {name}");
    }
    static NEXT: AtomicUsize = AtomicUsize::new(0);
    let path = std::env::temp_dir().join(format!(
        "joints-abi-layout-{}-{}.c",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    let source = format!(
        "#include \"{}/../../include/jnt.h\"\n_Static_assert(sizeof(jnt_scar)==28,\"scar\");\n_Static_assert(sizeof(jnt_cost)==44,\"cost\");\nvoid *exports[]={{ {} }};\n",
        env!("CARGO_MANIFEST_DIR"),
        names
            .iter()
            .map(|n| format!("(void*)&{n}"))
            .collect::<Vec<_>>()
            .join(",")
    );
    std::fs::write(&path, source).unwrap();
    let result = std::process::Command::new("cc")
        .args(["-std=c11", "-Wall", "-Werror", "-fsyntax-only"])
        .arg(&path)
        .output()
        .unwrap();
    std::fs::remove_file(path).unwrap();
    assert!(
        result.status.success(),
        "{}",
        String::from_utf8_lossy(&result.stderr)
    );
}

#[test]
fn bank_dispatch_and_language_roster_fail_without_partial_handles() {
    use joints_engine::{Bank, CompiledGrammar};
    static NEXT: AtomicUsize = AtomicUsize::new(0);
    let path = std::env::temp_dir().join(format!(
        "joints-abi-bank-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    let name = CString::new(path.to_str().unwrap()).unwrap();
    // SAFETY: CString paths and C literals remain live for calls; handle/length outputs are
    // writable local storage.
    unsafe {
        let mut b = ptr::dangling_mut::<JntBank>();
        assert_eq!(jnt_open(name.as_ptr(), &mut b), JNT_IO);
        assert!(b.is_null());
        for (bytes, status) in [
            (b"invalid".as_slice(), JNT_FORMAT),
            (b"{}".as_slice(), JNT_GRAMMAR),
        ] {
            std::fs::write(&path, bytes).unwrap();
            assert_eq!(jnt_open(name.as_ptr(), &mut b), status);
            assert!(b.is_null());
        }
        let one = CompiledGrammar::compile(
            br#"{"name":"one","rules":{"doc":{"type":"STRING","value":"x"}}}"#,
        )
        .unwrap();
        let two = CompiledGrammar::compile(
            br#"{"name":"two","rules":{"doc":{"type":"STRING","value":"y"}}}"#,
        )
        .unwrap();
        std::fs::write(&path, Bank::pack(&[one, two]).unwrap()).unwrap();
        assert_eq!(jnt_open(name.as_ptr(), &mut b), 0);
        assert_eq!(jnt_bank_count(b), 2);
        let mut p = ptr::dangling_mut::<JntParser>();
        assert_eq!(jnt_parser_new(b, ptr::null(), &mut p), JNT_LANGUAGE);
        assert!(p.is_null());
        assert!(error().contains("one two"));
        assert_eq!(jnt_parser_new(b, c"two".as_ptr(), &mut p), 0);
        let mut len = 0;
        assert_eq!(bytes(jnt_parser_language(p, &mut len), len), b"two");
        let mut tree = ptr::null_mut();
        assert_eq!(jnt_parse(p, c"y".as_ptr(), 1, &mut tree), 0);
        assert_eq!(jnt_tree_stop(tree), 0);
        jnt_tree_free(tree);
        jnt_parser_free(p);
        jnt_close(b);
    }
    std::fs::remove_file(path).unwrap();
}

#[test]
fn operational_resource_failures_leave_weave_version_and_parser_outputs_atomic() {
    use joints_engine::{Document, DocumentOptions, ParseLimits, ParseSession};
    use std::sync::Arc;
    // SAFETY: fixtures retain all owners; C literals cover lengths and output pointers address
    // writable locals.
    unsafe {
        let f = Fixture::new();
        let p = parser_handle(f.parser as usize).unwrap();
        let limits = ParseLimits {
            source_bytes: 4,
            ..ParseLimits::default()
        };
        *lock(&p.session).unwrap() = ParseSession::with_limits(Arc::clone(&p.grammar), limits);
        let tree = f.parse(b"true");
        let mut failed = ptr::dangling_mut::<JntTree>();
        assert_eq!(
            jnt_parse(f.parser, c"false".as_ptr(), 5, &mut failed),
            JNT_NOMEM
        );
        assert!(failed.is_null());
        assert_eq!(jnt_tree_stop(tree), 0);
        jnt_tree_free(tree);
        let mut weave = ptr::null_mut();
        assert_eq!(jnt_weave_new(f.parser, &mut weave), 0);
        assert_eq!(jnt_weave_warp(weave, c"[1]".as_ptr(), 3), 0);
        let tree = jnt_weave_tree(weave);
        let w = weave_handle(weave as usize).unwrap();
        let mut s = lock(&w.state).unwrap();
        let opts = DocumentOptions {
            limits,
            ..DocumentOptions::default()
        };
        s.document = Some(Document::with_options(Arc::clone(&p.grammar), b"[1]", opts).unwrap());
        drop(s);
        assert_eq!(
            jnt_weave_amend(weave, 1, 2, c"12345".as_ptr(), 5),
            JNT_NOMEM
        );
        assert_eq!(jnt_weave_len(weave), 3);
        assert_eq!(jnt_weave_tree(weave), tree);
        assert_eq!(jnt_tree_stop(tree), 0);
        assert_eq!(jnt_weave_amend(weave, 1, 2, c"2".as_ptr(), 1), 0);
        assert_eq!(jnt_node_end(tree, jnt_tree_root(tree, 0)), 3);
        assert_eq!(
            lock(&w.state).unwrap().document.as_ref().unwrap().source(),
            b"[2]"
        );
        jnt_weave_free(weave);
    }
}

#[test]
fn oversized_foreign_lengths_refuse_before_reading_or_publishing() {
    // SAFETY: input checks reject oversized or wrapping spans before reading them; all output
    // pointers address writable locals.
    unsafe {
        let f = Fixture::new();
        let oversized = usize::try_from(isize::MAX).unwrap() + 1;
        // These deliberately unaddressable spans must fail the length check
        // before any byte is read. The pointer itself remains live throughout.
        let source = c"1".as_ptr();
        let mut tree = ptr::dangling_mut::<JntTree>();
        assert_eq!(
            jnt_parse(f.parser, source, oversized, &mut tree),
            JNT_INVALID
        );
        assert!(tree.is_null());
        let mut query = ptr::dangling_mut::<JntQuery>();
        assert_eq!(
            jnt_query_compile(f.parser, source, oversized, &mut query),
            JNT_INVALID
        );
        assert!(query.is_null());
        let tree = f.parse(b"1");
        let query = f.query(b"(number) @n");
        let mut result = ptr::dangling_mut::<JntQueryResult>();
        assert_eq!(
            jnt_query_exec(query, tree, source, oversized, 0, &mut result),
            JNT_INVALID
        );
        assert!(result.is_null());
        assert_eq!(jnt_node_by_field(tree, 0, source, oversized), JNT_NONE);
        assert!(error().contains("oversized"));
        let wrapping = usize::MAX as *const c_char;
        assert_eq!(
            jnt_query_exec(query, tree, wrapping, 1, 0, &mut result),
            JNT_INVALID
        );
        assert!(result.is_null());
        assert!(error().contains("wraps"));
        let mut weave = ptr::null_mut();
        assert_eq!(jnt_weave_new(f.parser, &mut weave), JNT_OK);
        assert_eq!(jnt_weave_warp(weave, source, 1), JNT_OK);
        assert_eq!(jnt_weave_warp(weave, source, oversized), JNT_INVALID);
        assert_eq!(jnt_weave_amend(weave, 0, 1, source, oversized), JNT_INVALID);
        assert_eq!(jnt_weave_len(weave), 1);
        assert_eq!(jnt_tree_stop(jnt_weave_tree(weave)), 0);
        jnt_weave_free(weave);
        jnt_query_free(query);
        jnt_tree_free(tree);
    }
}

#[test]
fn binary_edit_lifecycle_matches_cold_trees_and_retains_failed_edit_views() {
    // SAFETY: input slices remain live for each call; returned views are consumed before
    // mutation or retained only across failed edits.
    unsafe {
        let f = Fixture::new();
        let query = f.query(b"(number) @n");
        let mut random = 0x2b96_30e1_6f50_781du64;
        let mut next = |bound: usize| {
            random ^= random << 13;
            random ^= random >> 7;
            random ^= random << 17;
            usize::try_from(random % u64::try_from(bound).unwrap()).unwrap()
        };
        for policy in 0..=2 {
            let mut weave = ptr::null_mut();
            assert_eq!(jnt_weave_new(f.parser, &mut weave), JNT_OK);
            assert_eq!(jnt_weave_policy(weave, policy), JNT_OK);
            let mut source = b"{\"a\":[1,2],\"b\":true}".to_vec();
            assert_eq!(
                jnt_weave_warp(weave, source.as_ptr().cast(), source.len()),
                JNT_OK
            );
            let tree = jnt_weave_tree(weave);
            for step in 0..160 {
                let from = next(source.len() + 1);
                let to = from + next(source.len() - from + 1);
                let replacements: &[&[u8]] = &[
                    b"",
                    b"1",
                    b"[1,2]",
                    b"true",
                    b"\"x\"",
                    b"\x00\xff\x80",
                    b"{}",
                    b"\r\n",
                ];
                let insert = replacements[next(replacements.len())];
                assert_eq!(
                    jnt_weave_amend(
                        weave,
                        u32::try_from(from).unwrap(),
                        u32::try_from(to).unwrap(),
                        insert.as_ptr().cast(),
                        insert.len()
                    ),
                    JNT_OK,
                    "policy {policy}, step {step}: {}",
                    error()
                );
                source.splice(from..to, insert.iter().copied());
                assert_eq!(jnt_weave_tree(weave), tree);
                assert_eq!(jnt_weave_len(weave), source.len());
                let cold = f.parse(&source);
                assert_eq!(jnt_tree_stop(tree), jnt_tree_stop(cold));
                assert_eq!(jnt_tree_stop_at(tree), jnt_tree_stop_at(cold));
                assert_eq!(jnt_tree_sound(tree), 1);
                assert_eq!(jnt_tree_scars(tree), jnt_tree_scars(cold));
                for i in 0..jnt_tree_scars(tree) {
                    let mut edited = JntScar::default();
                    let mut baseline = JntScar::default();
                    assert_eq!(jnt_tree_scar(tree, i, &mut edited), JNT_OK);
                    assert_eq!(jnt_tree_scar(cold, i, &mut baseline), JNT_OK);
                    assert_eq!(edited, baseline);
                }
                for all in 0..=1 {
                    let mut len = 0;
                    let rendered = jnt_tree_sexp(tree, all, &mut len);
                    let expected = bytes(rendered, len).to_vec();
                    let mut cold_len = 0;
                    assert_eq!(
                        bytes(jnt_tree_sexp(cold, all, &mut cold_len), cold_len),
                        expected
                    );
                    assert_eq!(
                        jnt_weave_amend(weave, u32::MAX, u32::MAX, ptr::null(), 0),
                        JNT_INVALID
                    );
                    assert_eq!(bytes(rendered, len), expected);
                    assert_eq!(jnt_tree_sexp(tree, all, ptr::null_mut()), rendered);
                }
                let mut result = ptr::null_mut();
                assert_eq!(
                    jnt_query_exec(
                        query,
                        tree,
                        source.as_ptr().cast(),
                        source.len(),
                        0,
                        &mut result
                    ),
                    JNT_OK
                );
                assert_eq!(jnt_weave_warp(weave, ptr::null(), 0), JNT_INVALID);
                assert_eq!(jnt_weave_len(weave), source.len());
                for i in 0..jnt_query_result_count(result) {
                    let node = jnt_query_result_capture_node(result, i, 0);
                    assert!(jnt_node_start(tree, node) <= jnt_node_end(tree, node));
                    assert!(jnt_node_end(tree, node) as usize <= source.len());
                }
                jnt_query_result_free(result);
                jnt_tree_free(cold);
            }
            jnt_weave_free(weave);
            assert_eq!(jnt_tree_stop(tree), JNT_INVALID);
        }
        jnt_query_free(query);
    }
}
