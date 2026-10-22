//! The pinned working grammar has thirteen independent call/type choices here.
//! Their late selector must remain available until the closing argument lists.
#![forbid(unsafe_code)]

use joints_engine::{CompiledGrammar, Error, Node, ParseLimits, ParseSession, Resource};
use serde_json::json;
use sha2::{Digest, Sha256};
use std::sync::Arc;

fn fingerprint(root: Node<'_>) -> String {
    let mut pending = vec![(root, 0)];
    let mut ledger = vec![];
    while let Some((node, depth)) = pending.pop() {
        ledger.push(json!([
            depth,
            node.name(),
            node.is_named(),
            node.field(),
            node.span().start(),
            node.span().end()
        ]));
        pending.extend(node.children().rev().map(|child| (child, depth + 1)));
    }
    Sha256::digest(serde_json::to_vec(&ledger).unwrap())
        .iter()
        .fold(String::new(), |mut text, byte| {
            use std::fmt::Write as _;
            write!(text, "{byte:02x}").expect("writing to a String cannot fail");
            text
        })
}

#[test]
fn deep_calls_keep_late_selector_rivals_with_an_explicit_lower_limit_control() {
    let grammar = include_bytes!("../../upstream/grammars/go.json");
    assert_eq!(
        Sha256::digest(grammar)
            .iter()
            .fold(String::new(), |mut text, byte| {
                use std::fmt::Write as _;
                write!(text, "{byte:02x}").expect("writing to a String cannot fail");
                text
            }),
        "0dcc665aa521a1b73a200be13b4e376780cca037d764a165f12864babfe28000"
    );
    let grammar = CompiledGrammar::compile(grammar).unwrap();
    assert_eq!(ParseLimits::default().heads, 8192);
    for (open, close, count, expected) in [
        (
            "a(",
            ")",
            87,
            "cb7f9aefcc6dc61a1146db6c2e007b77dfd873ed8d2e672a168d9c61c38ad482",
        ),
        (
            "a.b(",
            ",v)",
            147,
            "34f51c3a4a37bad0ebfcd68abffc7e71025dec16fa00c6e4df8b20c4312fddbc",
        ),
    ] {
        let source = format!(
            "package fixture\nfunc f() {{ _ = {}r.Context(){} }}\n",
            open.repeat(12),
            close.repeat(12)
        );
        let mut limited = ParseSession::with_limits(
            Arc::clone(&grammar),
            ParseLimits {
                heads: 512,
                ..ParseLimits::default()
            },
        );
        assert!(matches!(
            limited.parse(source.as_bytes()),
            Err(Error::LimitExceeded(Resource::Heads))
        ));

        let mut session = grammar.session();
        let tree = session.parse(source.as_bytes()).unwrap();
        assert!(tree.confidence().is_strict());
        assert!(tree.repairs().is_empty());
        assert_eq!(tree.survey().walked, count);
        // Independent TS 0.26.11, using the exact grammar above, confirms every
        // node's field, name, namedness, extent and position in the tree.
        assert_eq!(fingerprint(tree.root().unwrap()), expected);
        assert!(
            !session
                .product(&mut grammar.effect_store())
                .unwrap()
                .is_zero()
        );
    }
}
