//! A pinned witness distinguishes signed literals from rule-shaped comment extras.

use joints_engine::{CompiledGrammar, Node};
use sha2::{Digest, Sha256};
use std::{fs, path::Path};

#[test]
#[ignore = "explicit pinned Scala annotation/comment oracle witness"]
fn trailing_rule_extra_keeps_the_signed_annotation_argument() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap();
    let bytes = fs::read(root.join("upstream/grammars/scala.json")).unwrap();
    assert_eq!(
        Sha256::digest(&bytes)
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect::<String>(),
        "0040c891e6f062e929a7c1b596a306c8a7661d9f868a6ccdd9963381482d3589"
    );
    let grammar = CompiledGrammar::compile(&bytes).unwrap();
    let source = b"@SerialVersionUID(-114498752079829388L) // note\nclass Box\n";
    let tree = grammar.session().parse(source).unwrap();
    assert!(tree.confidence().is_strict());
    assert!(tree.survey().is_sound());
    let mut pending: Vec<Node<'_>> = tree.roots().collect();
    let mut found = vec![];
    while let Some(node) = pending.pop() {
        pending.extend(node.children());
        if matches!(node.name(), "integer_literal" | "comment") {
            found.push((node.name(), node.span().range(), node.text()));
        }
    }
    found.sort_by_key(|(_, span, _)| span.start);
    // Independently generated Tree-sitter 0.26.11 parser, exact pinned grammar.
    assert_eq!(
        found,
        [
            (
                "integer_literal",
                18..38,
                b"-114498752079829388L".as_slice()
            ),
            ("comment", 40..47, b"// note".as_slice()),
        ]
    );
}
