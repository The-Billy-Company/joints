#![forbid(unsafe_code)]

use joints_engine::{ByteSpan, CompileOptions, CompiledGrammar};
use serde_json::json;

#[test]
fn scanner_tab_columns_saturate_at_the_expression_limit() {
    let source = serde_json::to_vec(&json!({
        "name": "saturated_layout",
        "rules": {
            "doc": {
                "type": "SEQ",
                "members": [
                    { "type": "SYMBOL", "name": "layout" },
                    { "type": "STRING", "value": "x" }
                ]
            }
        },
        "externals": [{ "type": "SYMBOL", "name": "layout" }],
        "extras": []
    }))
    .unwrap();
    for tab in [1, 2, 8, 256] {
        let book = serde_json::to_vec(&json!({
            "cohort": ["layout"],
            "tab": tab,
            "rules": [{
                "phase": "bounded",
                "when": [
                    ["wanted", "layout"],
                    ["soak", "from", i64::MAX - 1, "to", i64::MAX],
                    ["lead", "=", u32::MAX]
                ],
                "then": [["emit", "layout"]]
            }]
        }))
        .unwrap();
        let grammar =
            CompiledGrammar::compile_with_customary(&source, &book, CompileOptions::default())
                .unwrap();
        let mut session = grammar.session();
        for input in [b"\tx", b" x"] {
            let tree = session.parse(input).unwrap();
            assert!(tree.confidence().is_strict(), "tab width {tab}");
            let layout = tree
                .root()
                .unwrap()
                .children()
                .find(|node| node.name() == "layout")
                .unwrap();
            assert_eq!(layout.text(), &input[..1], "tab width {tab}");
        }
        // Reaching the ceiling ends soaking. A wrapped column would instead
        // consume the following space and falsely accept this source.
        assert!(session.parse(b"\t x").is_err(), "tab width {tab}");
    }
}

#[test]
fn byte_spans_preserve_the_full_addressable_range_and_reject_overflow() {
    let maximum = usize::try_from(u32::MAX).unwrap();
    let entire = ByteSpan::new(0, maximum).unwrap();
    assert_eq!(entire.range(), 0..maximum);
    let at_end = ByteSpan::new(maximum, maximum).unwrap();
    assert!(at_end.is_empty());
    assert_eq!(at_end.start(), maximum);
    assert!(ByteSpan::new(1, 0).is_none());
    if let Some(oversized) = maximum.checked_add(1) {
        assert!(ByteSpan::new(0, oversized).is_none());
        assert!(ByteSpan::new(oversized, oversized).is_none());
    }
}
