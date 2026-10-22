//! Authored contextual-token regressions, with retained exact-F canonical images.
#![forbid(unsafe_code)]

use joints_engine::{
    ByteSpan, CompiledGrammar, Document, DocumentError, DocumentOptions, DocumentPolicy, Error,
    Node, ParseLimits, ParseSession, Recovery, Resource, Reuse, Stop, Supply, TreeSnapshot,
};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{collections::BTreeSet, sync::Arc};

const FIXTURE: &[u8] = include_bytes!("fixtures/contextual-viability.json");
fn digest(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .fold(String::new(), |mut text, byte| {
            use std::fmt::Write as _;
            write!(text, "{byte:02x}").expect("writing to a String cannot fail");
            text
        })
}
fn fixture() -> Value {
    assert_eq!(
        digest(FIXTURE),
        "75115f1b162e230903db0034b083ae85f15a2387028319f5dcf8e2bdce0c685d"
    );
    let f: Value = serde_json::from_slice(FIXTURE).unwrap();
    let names: BTreeSet<_> = f["cases"]
        .as_array()
        .unwrap()
        .iter()
        .map(|c| c["name"].as_str().unwrap())
        .collect();
    assert_eq!(f["cases"].as_array().unwrap().len(), 8);
    assert_eq!(
        names,
        BTreeSet::from([
            "zero-u",
            "zero-v",
            "zero-u-positive",
            "zero-v-invalid",
            "long-h-260-u",
            "long-h-260-v",
            "short-h-8-u",
            "short-h-8-v"
        ])
    );
    assert_eq!(
        f["grammars"]
            .as_object()
            .unwrap()
            .keys()
            .map(String::as_str)
            .collect::<BTreeSet<_>>(),
        BTreeSet::from(["required-zero", "long-h-260", "short-h-8"])
    );
    f
}
fn compile(source: &str, expected_hash: &str) -> Arc<CompiledGrammar> {
    assert_eq!(digest(source.as_bytes()), expected_hash);
    CompiledGrammar::compile(source.as_bytes()).unwrap()
}
fn original(f: &Value, name: &str) -> Arc<CompiledGrammar> {
    let g = &f["grammars"][name];
    compile(g["source"].as_str().unwrap(), g["sha256"].as_str().unwrap())
}
fn authored(f: &Value, name: &str) -> Arc<CompiledGrammar> {
    compile(
        f[name]["grammar"].as_str().unwrap(),
        f[name]["sha256"].as_str().unwrap(),
    )
}
fn case<'a>(f: &'a Value, name: &str) -> &'a Value {
    f["cases"]
        .as_array()
        .unwrap()
        .iter()
        .find(|c| c["name"] == name)
        .unwrap()
}
fn point(source: &[u8], at: usize) -> [usize; 2] {
    let prefix = &source[..at];
    [
        prefix.iter().filter(|&&b| b == b'\n').count(),
        prefix
            .iter()
            .rposition(|&b| b == b'\n')
            .map_or(at, |p| at - p - 1),
    ]
}
fn node(n: Node<'_>, source: &[u8], parent: Option<Node<'_>>) -> Value {
    let span = n.span();
    assert!(span.end() <= source.len());
    assert_eq!(n.text(), &source[span.range()]);
    assert_eq!(
        [
            n.start_point().row as usize,
            n.start_point().column as usize
        ],
        point(source, span.start())
    );
    assert_eq!(
        [n.end_point().row as usize, n.end_point().column as usize],
        point(source, span.end())
    );
    assert_eq!(
        n.parent().map(|p| (p.name().to_owned(), p.span())),
        parent.map(|p| (p.name().to_owned(), p.span()))
    );
    let children: Vec<_> = n.children().collect();
    for child in &children {
        if let Some(field) = child.field() {
            let expected = children.iter().find(|n| n.field() == Some(field)).unwrap();
            let actual = n.child_by_field(field).unwrap();
            assert_eq!(
                (actual.name(), actual.span()),
                (expected.name(), expected.span())
            );
        }
    }
    json!({"name":n.name(),"named":n.is_named(),"extra":n.is_extra(),"field":n.field(),
        "start":span.start(),"end":span.end(),"bytes":n.text(),
        "start_point":point(source,span.start()),"end_point":point(source,span.end()),
        "kids":children.into_iter().map(|c| node(c,source,Some(n))).collect::<Vec<_>>()})
}
fn image(t: &TreeSnapshot) -> Value {
    let s = t.survey();
    json!({"stop":format!("{:?}",t.stop()),"stop_symbol":t.stop_symbol(),"strict":t.confidence().is_strict(),
        "source":t.source(),"roots":t.confidence().roots,"mends":t.mends(),"skipped":t.skipped(),
        "supplied":t.supplied(),"spurned":t.spurned(),"survey":{"walked":s.walked,"held":s.held,
        "sound":s.is_sound(),"loose":s.loose,"disorder":s.disorder,"torn":s.torn},
        "repairs":t.repairs().iter().map(|r|format!("{r:?}")).collect::<Vec<_>>(),
        "tree":t.roots().map(|n|node(n,t.source(),None)).collect::<Vec<_>>()})
}
fn no_repairs(t: &TreeSnapshot) {
    assert!(t.survey().is_sound());
    assert!(t.repairs().is_empty());
    assert_eq!(
        (t.mends(), t.skipped(), t.supplied(), t.spurned()),
        (0, 0, 0, 0)
    );
}
fn named<'a>(t: &'a TreeSnapshot, name: &str) -> Vec<Node<'a>> {
    let mut pending: Vec<_> = t.roots().collect();
    let mut found = Vec::new();
    while let Some(n) = pending.pop() {
        if n.name() == name {
            found.push(n);
        }
        pending.extend(n.children());
    }
    found
}

#[test]
fn eight_authored_contexts_match_full_canonical_images_directly_and_after_loading() {
    let f = fixture();
    let mut executed = 0;
    for (name, _) in f["grammars"].as_object().unwrap() {
        let grammar = original(&f, name);
        let bytes = grammar.artifact().unwrap();
        let loaded = CompiledGrammar::from_artifact(&bytes).unwrap();
        assert_eq!(loaded.artifact().unwrap(), bytes);
        for grammar in [grammar, loaded] {
            for c in f["cases"]
                .as_array()
                .unwrap()
                .iter()
                .filter(|c| c["grammar"].as_str() == Some(name.as_str()))
            {
                let source = c["source"].as_str().unwrap().as_bytes();
                assert_eq!(digest(source), c["source_sha256"]);
                let mut session = grammar.session();
                session.set_trace_enabled(true);
                let tree = session.parse_partial(source).unwrap();
                no_repairs(&tree);
                if c["name"] == "zero-v-invalid" {
                    assert!(!tree.confidence().is_strict());
                    assert!(matches!(tree.stop(), Stop::Unexpected { at: 3, .. }));
                    assert_eq!(tree.stop_symbol(), Some("Z"));
                    // Canonical StateIds and partial forests are not LALR identities.
                } else {
                    assert_eq!(image(&tree), c["canonical_observed_image"], "{}", c["name"]);
                    let tokens = session.selected_tokens().unwrap();
                    assert_eq!(
                        json!(
                            tokens
                                .iter()
                                .map(|t| json!({"name":grammar.symbol_name(t.symbol).unwrap(),
                        "start":t.span.start(),"end":t.span.end(),"supplied":t.supplied}))
                                .collect::<Vec<_>>()
                        ),
                        c["expected_tokens"]
                    );
                    let mut store = grammar.effect_store();
                    let whole = session.product(&mut store).unwrap();
                    assert!(!whole.is_zero());
                    assert!(store.grounded(whole).unwrap());
                    let mut pieces = Vec::new();
                    for t in tokens {
                        pieces.push(
                            session
                                .product_range(t.moves.clone(), &mut store, 10_000_000)
                                .unwrap()
                                .0,
                        );
                    }
                    let prefix = session
                        .product_range(0..tokens.last().unwrap().moves.end, &mut store, 10_000_000)
                        .unwrap()
                        .0;
                    assert_eq!(store.fold(pieces).unwrap(), prefix);
                }
                executed += 1;
            }
        }
    }
    assert_eq!(executed, 16);
}

#[test]
fn actual_accepting_end_keeps_priority_over_an_optional_empty_token() {
    let f = fixture();
    let c = &f["optional_end"];
    let g = compile(
        c["grammar"].as_str().unwrap(),
        c["oracle"]["grammar_sha256"].as_str().unwrap(),
    );
    for grammar in [
        Arc::clone(&g),
        CompiledGrammar::from_artifact(&g.artifact().unwrap()).unwrap(),
    ] {
        let mut session = grammar.session();
        session.set_trace_enabled(true);
        let tree = session.parse(b"x").unwrap();
        no_repairs(&tree);
        assert!(tree.confidence().is_strict());
        let root = tree.root().unwrap();
        assert_eq!(root.name(), "doc");
        assert_eq!(
            root.children()
                .map(|n| (n.name(), n.span().range()))
                .collect::<Vec<_>>(),
            [("x", 0..1)]
        );
        assert_eq!(session.selected_tokens().unwrap().len(), 1);
        image(&tree);
    }
}

#[test]
fn an_unknown_ordinary_nullable_candidate_requires_a_real_shift_without_becoming_a_supply() {
    let f = fixture();
    let grammar = authored(&f, "long_required_zero");
    let loaded = CompiledGrammar::from_artifact(&grammar.artifact().unwrap()).unwrap();
    for grammar in [grammar, loaded] {
        for branch in [b'u', b'v'] {
            let expected = f["long_required_zero"]["cases"]
                .as_array()
                .unwrap()
                .iter()
                .find(|c| c["branch"].as_str().unwrap().as_bytes() == [branch])
                .unwrap();
            let source = expected["source"].as_str().unwrap().as_bytes();
            assert_eq!(digest(source), expected["source_sha256"]);
            let mut session = grammar.session();
            session.set_trace_enabled(true);
            let tree = session.parse(source).unwrap();
            no_repairs(&tree);
            assert!(tree.confidence().is_strict());
            assert_eq!(named(&tree, "H").len(), 1);
            let h = named(&tree, "H")[0];
            assert_eq!(h.span().range(), 1..261);
            assert_eq!(
                h.children()
                    .map(|n| (n.name(), n.span().range()))
                    .collect::<Vec<_>>(),
                (1..261).map(|i| ("q", i..i + 1)).collect::<Vec<_>>()
            );
            let zero = named(&tree, "Z");
            assert_eq!(zero.len(), usize::from(branch == b'u'));
            if let Some(z) = zero.first() {
                assert_eq!(z.span().range(), 261..261);
                assert!(!z.is_extra());
            }
            assert_eq!(
                session
                    .selected_tokens()
                    .unwrap()
                    .iter()
                    .filter(|t| t.span.is_empty())
                    .count(),
                usize::from(branch == b'u')
            );
            assert!(
                session
                    .selected_tokens()
                    .unwrap()
                    .iter()
                    .all(|t| !t.supplied)
            );
            assert_eq!(image(&tree), expected["expected_image"]);
        }
    }
}

#[test]
fn rejected_raw_openers_restore_delimiter_memory_and_do_not_reenter_raw_fallback() {
    let f = fixture();
    let grammar = authored(&f, "raw_rollback");
    assert_eq!(
        grammar.unsupported_externals().count(),
        0,
        "complete existing raw scanner cohort"
    );
    for (branch, suffix, content) in [
        (b'u', "r#\"a\"#xr##\"tail\"##", Some("tail")),
        (b'v', "r#\"a\"#", Some("a")),
        (b'u', "r#\"a\"#", None),
    ] {
        let mut source = vec![branch];
        source.extend([b'q'; 260]);
        source.extend_from_slice(suffix.as_bytes());
        let mut session = grammar.session();
        let tree = session.parse_partial(&source).unwrap();
        no_repairs(&tree);
        assert_eq!(tree.confidence().is_strict(), content.is_some());
        if let Some(content) = content {
            let nodes = named(&tree, "raw_string_literal_content");
            assert_eq!(nodes.len(), 1);
            assert_eq!(nodes[0].text(), content.as_bytes());
            assert!(!nodes[0].is_extra());
        }
        image(&tree);
    }
}

#[test]
fn all_invalid_candidates_keep_the_original_longest_failure_and_post_reduction_prefix() {
    let f = fixture();
    let grammar = authored(&f, "all_invalid");
    let mut source = b"u".to_vec();
    source.extend([b'q'; 260]);
    source.extend_from_slice(b"dd");
    let tree = grammar.session().parse_partial(&source).unwrap();
    no_repairs(&tree);
    assert!(!tree.confidence().is_strict());
    assert!(matches!(tree.stop(), Stop::Unexpected { at: 261, .. }));
    assert_eq!(tree.stop_symbol(), Some("dd"));
    assert_eq!(
        image(&tree)["tree"],
        f["all_invalid"]["expected_first_failure_tree"]
    );
}

#[test]
fn a_limit_in_the_first_real_reduction_is_not_reclassified_as_token_impossibility() {
    let f = fixture();
    let grammar = original(&f, "long-h-260");
    let c = case(&f, "long-h-260-u");
    let source = c["source"].as_str().unwrap().as_bytes();
    // u +260q already mint261 real leaves; the next H reduction must allocate.
    let mut limited = ParseSession::with_limits(
        Arc::clone(&grammar),
        ParseLimits {
            nodes: 261,
            ..ParseLimits::default()
        },
    );
    limited.set_trace_enabled(true);
    assert!(matches!(
        limited.parse(source),
        Err(Error::LimitExceeded(Resource::Nodes))
    ));
    assert!(limited.selected_tokens().is_none());
    assert!(limited.product(&mut grammar.effect_store()).is_err());
    // Speculative drafts are real resource consumption; selected266 is not a capacity promise.
    let mut enough = ParseSession::with_limits(
        Arc::clone(&grammar),
        ParseLimits {
            nodes: 1024,
            ..ParseLimits::default()
        },
    );
    let tree = enough.parse(source).unwrap();
    assert_eq!(tree.survey().walked, 266);
    assert_eq!(image(&tree), c["canonical_observed_image"]);
    let options = DocumentOptions {
        limits: ParseLimits {
            nodes: 265,
            ..ParseLimits::default()
        },
        ..DocumentOptions::default()
    };
    let mut doc = Document::with_options(
        grammar,
        case(&f, "long-h-260-v")["source"]
            .as_str()
            .unwrap()
            .as_bytes(),
        options,
    )
    .unwrap();
    let before = Arc::clone(doc.snapshot());
    let product = doc.product().unwrap();
    let cost = doc.cost();
    assert!(matches!(
        doc.edit(ByteSpan::new(0, 1).unwrap(), b"u"),
        Err(DocumentError::Parse(Error::LimitExceeded(Resource::Nodes)))
    ));
    assert!(Arc::ptr_eq(doc.snapshot(), &before));
    assert_eq!(doc.source(), before.source());
    assert_eq!(doc.product().unwrap(), product);
    assert_eq!(doc.cost(), cost);
}

fn cold(document: &Document, grammar: &Arc<CompiledGrammar>, options: DocumentOptions) {
    let mut session = ParseSession::with_limits(Arc::clone(grammar), options.limits);
    session.set_recovery(options.recovery);
    session.set_supply(options.supply);
    let tree = session.parse_partial(document.source()).unwrap();
    assert_eq!(image(document.snapshot()), image(&tree));
    let mut store = grammar.effect_store();
    let effect = session.product(&mut store).unwrap();
    assert_eq!(document.product().unwrap(), store.describe(effect).unwrap());
}
fn edit(
    document: &mut Document,
    grammar: &Arc<CompiledGrammar>,
    options: DocumentOptions,
    start: usize,
    end: usize,
    text: &[u8],
    strict: bool,
) {
    let old = Arc::clone(document.snapshot());
    let old_image = image(&old);
    let mut expected = document.source()[..start].to_vec();
    expected.extend_from_slice(text);
    expected.extend_from_slice(&document.source()[end..]);
    document
        .edit(ByteSpan::new(start, end).unwrap(), text)
        .unwrap();
    assert_eq!(document.source(), expected);
    assert_eq!(document.snapshot().source(), expected);
    assert_eq!(document.snapshot().confidence().is_strict(), strict);
    cold(document, grammar, options);
    assert_eq!(image(&old), old_image);
}
fn prefixed(source: &str) -> Arc<CompiledGrammar> {
    let mut g: Value = serde_json::from_str(source).unwrap();
    let old = g["rules"]["doc"].take();
    g["rules"]["doc"] = json!({"type":"SEQ","members":[{"type":"REPEAT","content":{"type":"STRING","value":"p"}},old]});
    CompiledGrammar::compile(&serde_json::to_vec(&g).unwrap()).unwrap()
}

#[test]
fn contextual_and_nullable_edits_preserve_cold_products_and_published_versions() {
    let f = fixture();
    for policy in [
        DocumentPolicy::Prove,
        DocumentPolicy::Snap,
        DocumentPolicy::Whole,
    ] {
        let options = DocumentOptions {
            policy,
            recovery: Recovery::None,
            supply: Supply::Disabled,
            ..DocumentOptions::default()
        };
        for (name, long) in [("required-zero", false), ("long_required_zero", true)] {
            let source = if long {
                f[name]["grammar"].as_str().unwrap()
            } else {
                f["grammars"][name]["source"].as_str().unwrap()
            };
            let grammar = prefixed(source);
            let mut bytes = vec![b'p'; 96];
            bytes.push(b'u');
            bytes.extend(vec![b'q'; if long { 260 } else { 1 }]);
            if !long {
                bytes.push(b'r');
            }
            let mut document =
                Document::with_options(Arc::clone(&grammar), &bytes, options).unwrap();
            assert!(document.snapshot().confidence().is_strict());
            cold(&document, &grammar, options);
            edit(&mut document, &grammar, options, 96, 97, b"v", true);
            let end = document.source().len();
            edit(&mut document, &grammar, options, end, end, b"a", false);
            edit(&mut document, &grammar, options, 96, 97, b"u", true);
            let end = document.source().len();
            edit(&mut document, &grammar, options, end - 1, end, b"", true);
            assert_eq!(document.cost().reuse, Reuse::Cold);
        }
        let grammar = prefixed(f["grammars"]["long-h-260"]["source"].as_str().unwrap());
        let mut bytes = vec![b'p'; 96];
        bytes.extend_from_slice(
            case(&f, "long-h-260-u")["source"]
                .as_str()
                .unwrap()
                .as_bytes(),
        );
        let mut document = Document::with_options(Arc::clone(&grammar), &bytes, options).unwrap();
        assert!(document.snapshot().confidence().is_strict());
        edit(&mut document, &grammar, options, 96, 97, b"v", true);
        let end = document.source().len();
        edit(&mut document, &grammar, options, end - 1, end, b"", false);
        edit(&mut document, &grammar, options, 96, 97, b"u", true);
        let end = document.source().len();
        edit(&mut document, &grammar, options, end, end, b"d", true);
        assert_eq!(document.cost().reuse, Reuse::Cold);
    }
}

#[test]
fn dormant_unknown_reducers_cannot_run_on_frame_less_checkpoint_replay() {
    let f = fixture();
    let grammar = authored(&f, "dormant_replay");
    let mut source = b"u".to_vec();
    source.extend([b'q'; 260]);
    source.push(b'x');
    source.extend([b'p'; 96]);
    for policy in [
        DocumentPolicy::Prove,
        DocumentPolicy::Snap,
        DocumentPolicy::Whole,
    ] {
        let options = DocumentOptions {
            policy,
            ..DocumentOptions::default()
        };
        let mut document = Document::with_options(Arc::clone(&grammar), &source, options).unwrap();
        assert!(document.snapshot().confidence().is_strict());
        assert!(named(document.snapshot(), "W").is_empty());
        let end = document.source().len();
        edit(&mut document, &grammar, options, end, end, b"z", true);
        let winner = named(document.snapshot(), "W");
        assert_eq!(winner.len(), 1);
        assert_eq!(winner[0].span().range(), 261..end + 1);
        assert_eq!(named(document.snapshot(), "H").len(), 1);
        assert_eq!(document.cost().reuse, Reuse::Cold);
        edit(&mut document, &grammar, options, end, end + 1, b"", true);
        assert!(named(document.snapshot(), "W").is_empty());
    }
}
