//! Independent witnesses from the pinned, unsealed working corpus.

#![forbid(unsafe_code)]

use joints_engine::{CompiledGrammar, Node, TreeSnapshot};
use sha2::{Digest, Sha256};
use std::{fs, path::Path};

fn pinned(path: &str, expected: &str) -> Vec<u8> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap();
    let bytes = fs::read(root.join(path)).unwrap_or_else(|e| panic!("{path}: {e}"));
    assert_eq!(
        Sha256::digest(&bytes)
            .iter()
            .fold(String::new(), |mut text, byte| {
                use std::fmt::Write as _;
                write!(text, "{byte:02x}").expect("writing to a String cannot fail");
                text
            }),
        expected,
        "{path}"
    );
    bytes
}

fn nodes(tree: &TreeSnapshot) -> Vec<Node<'_>> {
    let mut pending: Vec<_> = tree.roots().collect();
    let mut all = Vec::new();
    while let Some(node) = pending.pop() {
        pending.extend(node.children());
        all.push(node);
    }
    all
}

fn syntax_digest(tree: &TreeSnapshot) -> String {
    fn number(hash: &mut Sha256, value: usize) {
        hash.update((value as u64).to_le_bytes());
    }
    fn text(hash: &mut Sha256, value: &str) {
        number(hash, value.len());
        hash.update(value.as_bytes());
    }
    let roots: Vec<_> = tree.roots().collect();
    let mut hash = Sha256::new();
    number(&mut hash, roots.len());
    let mut pending: Vec<_> = roots.into_iter().rev().collect();
    while let Some(node) = pending.pop() {
        text(&mut hash, node.name());
        hash.update([u8::from(node.is_named()), u8::from(node.field().is_some())]);
        if let Some(field) = node.field() {
            text(&mut hash, field);
        }
        number(&mut hash, node.span().start());
        number(&mut hash, node.span().end());
        let children: Vec<_> = node.children().collect();
        number(&mut hash, children.len());
        pending.extend(children.into_iter().rev());
    }
    hash.finalize()
        .iter()
        .fold(String::new(), |mut text, byte| {
            use std::fmt::Write as _;
            write!(text, "{byte:02x}").expect("writing to a String cannot fail");
            text
        })
}

#[test]
#[ignore = "explicit pinned Markdown working-corpus oracle witness"]
fn markdown_final_link_definition_keeps_its_structure() {
    let grammar = CompiledGrammar::compile(&pinned(
        "upstream/grammars/markdown.json",
        "a96d7cd418f0af885bdee8cbdef098879c1542e8895fe4f977e248b630011ce2",
    ))
    .unwrap();
    let source = pinned(
        "upstream/sources/README.md",
        "b3f6ef2fef88b98cb9ec013a5c86213095e53e40eb228679574e4d06517f33c8",
    );
    let tree = grammar.session().parse(&source).unwrap();
    // Tree-sitter 0.26.11 independently confirms these kinds, fields, and spans
    // on the exact pinned bytes. The frozen Zig tree calls this a paragraph.
    let all = nodes(&tree);
    let definition = all
        .iter()
        .find(|n| n.name() == "link_reference_definition" && n.span().range() == (3239..3304))
        .expect("final link definition was parsed as ordinary inline text");
    let children: Vec<_> = definition.children().collect();
    assert_eq!(
        children
            .iter()
            .map(|n| (n.name(), n.is_named(), n.span().range(), n.field()))
            .collect::<Vec<_>>(),
        [
            ("link_label", true, 3239..3258, None),
            (":", false, 3258..3259, None),
            ("link_destination", true, 3260..3303, None),
        ]
    );
    assert_eq!(children[0].text(), b"[policies-licenses]");
    assert_eq!(
        children[2].text(),
        b"https://www.rust-lang.org/policies/licenses"
    );
    assert!(tree.confidence().is_strict());
}

#[test]
#[ignore = "explicit pinned OCaml working-corpus oracle witness"]
fn ocaml_rule_comments_preserve_the_whole_standard_library_file() {
    let grammar = CompiledGrammar::compile(&pinned(
        "upstream/grammars/ocaml.json",
        "618293e3e7924b25c23f1827af7dd604807cc8da17c31a06a2f446d2f260d541",
    ))
    .unwrap();
    let source = pinned(
        "upstream/sources/list.ml",
        "3703bdaf69c532b535c3de70cafdc50cb6c4a31c6cb8ded0454b41f8178cc982",
    );
    let tree = grammar.session().parse(&source).unwrap();
    // Full independent Tree-sitter 0.26.11 comparison found zero differences
    // across all 7,419 nodes. Hash names/sorts/fields/spans/child order, excluding
    // implementation-local IDs and arena occupancy. Zig's frozen parse stops
    // inside a rule-shaped comment at byte 1996 and subsequently repairs.
    assert!(tree.confidence().is_strict());
    assert_eq!(tree.survey().walked, 7419);
    assert_eq!(
        syntax_digest(&tree),
        "0c9b90687fce92ff5a351a7aa9e75a19716a7ae538d82e5d0bfa5b73ab4612a2"
    );
}
