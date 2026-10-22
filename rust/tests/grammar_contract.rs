//! Small authored grammars pin semantics the JSON-only golden cannot exercise.

use std::sync::Arc;

use joints_engine::{
    Action, CompileError, CompileLimitation, CompiledGrammar, ConflictClass, Error, Node, Stop,
    TreeSnapshot,
};

fn compile(rules: &str, extras: &str) -> Arc<CompiledGrammar> {
    let source = format!(r#"{{"name":"contract","rules":{{{rules}}}{extras}}}"#);
    CompiledGrammar::compile(source.as_bytes()).unwrap()
}

fn parse(grammar: &Arc<CompiledGrammar>, source: &[u8]) -> TreeSnapshot {
    let tree = grammar.session().parse(source).unwrap();
    assert!(tree.survey().is_sound());
    assert_eq!(tree.survey().walked, tree.survey().held);
    tree
}

fn named(node: Node<'_>) -> String {
    let mut result = format!("({}", node.name());
    for child in node.children().filter(|child| child.is_named()) {
        result.push(' ');
        if let Some(field) = child.field() {
            result.push_str(field);
            result.push_str(": ");
        }
        result.push_str(&named(child));
    }
    result.push(')');
    result
}

const SPACES: &str = r#", "extras":[{"type":"PATTERN","value":"\\s"}]"#;
const ASIDES: &str =
    r#", "extras":[{"type":"PATTERN","value":"\\s"},{"type":"SYMBOL","name":"comment"}]"#;
const COMMENT: &str = r##", "comment":{"type":"TOKEN","content":{"type":"SEQ","members":[{"type":"STRING","value":"#"},{"type":"PATTERN","value":"[^\n]*"}]}}"##;

#[test]
fn merged_origins_cannot_reverse_an_authored_numeric_precedence() {
    // Independently generated tree-sitter 0.26.11 chooses expression + two
    // trailing d's in axdd. Merged arrival lookaheads formerly withheld the
    // call's negative precedence and made call + one trailing d primary.
    let grammar =
        CompiledGrammar::compile(include_bytes!("fixtures/frayed-priority.json")).unwrap();
    for (source, expected) in [
        (
            b"axdd".as_slice(),
            "(doc (wrapper (expression (id))) (tail))",
        ),
        (b"bxe", "(doc (wrapper (expression (id))))"),
        (b"bxde", "(doc (wrapper (call (id))))"),
    ] {
        let tree = parse(&grammar, source);
        assert_eq!(named(tree.root().unwrap()), expected);
        if source == b"axdd" {
            let tail = tree
                .root()
                .unwrap()
                .children()
                .find(|n| n.name() == "tail")
                .unwrap();
            assert_eq!(tail.span().range(), 2..4);
        }
    }
    for invalid in [b"ax".as_slice(), b"bxdd"] {
        assert!(grammar.session().parse(invalid).is_err());
    }
}

#[test]
fn neutral_factoring_keeps_use_site_fields_and_aliases_and_cannot_hide_authored_ambiguity() {
    let source = include_bytes!("fixtures/factoring.json");
    let grammar = CompiledGrammar::compile(source).unwrap();
    for (input, expected) in [
        (b"az".as_slice(), "(doc (A tail: (tailA)))"),
        (b"bp0p3y", "(doc (B tail: (tailB)))"),
    ] {
        let tree = parse(&grammar, input);
        assert_eq!(named(tree.root().unwrap()), expected);
        let tail = tree
            .root()
            .unwrap()
            .children()
            .next()
            .unwrap()
            .children()
            .find(|n| n.field() == Some("tail"))
            .unwrap();
        assert_eq!(tail.text(), &input[input.len() - 1..]);
    }
    // Erasing the distinguishing prefix makes two authored completions compete.
    // Different aliases/fields in helper recipes cannot license that ambiguity.
    let mut ambiguous: serde_json::Value = serde_json::from_slice(source).unwrap();
    ambiguous["rules"]["B"]["content"]["members"][0]["value"] = "a".into();
    assert!(matches!(
        CompiledGrammar::compile(&serde_json::to_vec(&ambiguous).unwrap()),
        Err(Error::Compile(CompileError::Conflict { .. }))
    ));
}

#[test]
fn absorbed_wide_inline_sides_order_but_never_delete_the_other_reading() {
    let source = include_bytes!("fixtures/absorbed.json");
    let grammar = CompiledGrammar::compile(source).unwrap();
    let absorbed: Vec<_> = grammar
        .conflict_diagnostics()
        .iter()
        .filter(|c| c.class == ConflictClass::Absorbed)
        .collect();
    assert!(!absorbed.is_empty());
    assert!(absorbed.iter().all(|c| c.actions.len() == 2
        && matches!(c.actions[0], Action::Reduce(_))
        && matches!(c.actions[1], Action::Shift(_))));
    let tree = parse(&grammar, b"x!");
    assert_eq!(named(tree.root().unwrap()), "(doc (b))");

    let mut unranked: serde_json::Value = serde_json::from_slice(source).unwrap();
    unranked["rules"]["_atom"] = unranked["rules"]["_atom"]["content"].clone();
    assert!(matches!(
        CompiledGrammar::compile(&serde_json::to_vec(&unranked).unwrap()),
        Err(Error::Compile(CompileError::Conflict { .. }))
    ));
}

#[test]
fn reserved_contexts_report_the_current_enforcement_gap_explicitly() {
    let grammar = CompiledGrammar::compile(include_bytes!("fixtures/reserved-gap.json")).unwrap();
    assert_eq!(
        grammar.limitations(),
        &[CompileLimitation::ReservedWordContexts {
            contexts: vec!["global".into(), "properties".into()]
        }]
    );
    // TS0.26.11 / languageABI15 rejects `x if;` and accepts `.if;` for this
    // fixture. The current importer retains the contexts but reports that it
    // cannot enforce them, so this is explicit limitation evidence, not parity.
    assert_eq!(parse(&grammar, b"x if;").stop(), Stop::Accepted);
    assert_eq!(parse(&grammar, b".if;").stop(), Stop::Accepted);
}

#[test]
fn dynamic_ranks_survive_inline_and_factoring_exactly_once() {
    let source = include_bytes!("fixtures/inline-dynamic.json");
    let grammar = CompiledGrammar::compile(source).unwrap();
    assert_eq!(
        named(parse(&grammar, b"xz").root().unwrap()),
        "(doc (outer))"
    );
    let mut negative: serde_json::Value = serde_json::from_slice(source).unwrap();
    negative["rules"]["_atom"]["value"] = (-5).into();
    negative["rules"]["plain"]["value"] = 1.into();
    let grammar = CompiledGrammar::compile(&serde_json::to_vec(&negative).unwrap()).unwrap();
    assert_eq!(
        named(parse(&grammar, b"xz").root().unwrap()),
        "(doc (plain))"
    );

    // A's factored terminal contributes2 once. B's authored production carries3.
    // Charging the factored terminal twice would incorrectly make A win4to3.
    let grammar =
        CompiledGrammar::compile(include_bytes!("fixtures/factoring-dynamic.json")).unwrap();
    assert_eq!(
        named(parse(&grammar, b"az").root().unwrap()),
        "(doc (B tail: (tailB)))"
    );
}

#[test]
fn visible_aliases_change_only_the_authored_sites_and_namedness() {
    let grammar = compile(
        r#"
      "doc":{"type":"SEQ","members":[
        {"type":"ALIAS","named":true,"value":"renamed","content":{"type":"SYMBOL","name":"item"}},
        {"type":"ALIAS","named":false,"value":"tag","content":{"type":"SYMBOL","name":"item"}},
        {"type":"SYMBOL","name":"item"}]},
      "item":{"type":"PATTERN","value":"[a-z]+"}"#,
        SPACES,
    );
    let tree = parse(&grammar, b"one two three");
    assert_eq!(named(tree.root().unwrap()), "(doc (renamed) (item))");
    let children: Vec<_> = tree.root().unwrap().children().collect();
    assert_eq!(
        children.iter().map(|n| n.name()).collect::<Vec<_>>(),
        ["renamed", "tag", "item"]
    );
    assert_eq!(
        children.iter().map(|n| n.is_named()).collect::<Vec<_>>(),
        [true, false, true]
    );
    assert_eq!(children[0].text(), b"one");
    assert_eq!(children[1].text(), b"two");
    assert_eq!(children[2].span().range(), 8..13);
}

#[test]
fn aliasing_hidden_structure_makes_one_wrapper_over_its_splice() {
    let grammar = compile(
        r#"
      "doc":{"type":"SEQ","members":[
        {"type":"ALIAS","named":true,"value":"group","content":{"type":"SYMBOL","name":"_pair"}},
        {"type":"STRING","value":"."}]},
      "_pair":{"type":"SEQ","members":[{"type":"SYMBOL","name":"item"},{"type":"SYMBOL","name":"item"}]},
      "item":{"type":"PATTERN","value":"[a-z]+"}"#,
        SPACES,
    );
    let tree = parse(&grammar, b"a b.");
    assert_eq!(named(tree.root().unwrap()), "(doc (group (item) (item)))");
    let group = tree.root().unwrap().children().next().unwrap();
    assert_eq!(group.span().range(), 0..3);
    assert!(
        group
            .children()
            .all(|child| child.parent().unwrap().name() == "group")
    );
}

#[test]
fn a_field_on_hidden_structure_reaches_each_item_but_never_its_extra() {
    let rules = format!(
        r#"
      "doc":{{"type":"SEQ","members":[
        {{"type":"FIELD","name":"part","content":{{"type":"SYMBOL","name":"_pair"}}}},
        {{"type":"STRING","value":"."}}]}},
      "_pair":{{"type":"SEQ","members":[{{"type":"SYMBOL","name":"item"}},{{"type":"SYMBOL","name":"item"}}]}},
      "item":{{"type":"PATTERN","value":"[a-z]+"}}{COMMENT}"#
    );
    let grammar = compile(&rules, ASIDES);
    let tree = parse(&grammar, b"a #x\nb .");
    assert_eq!(
        named(tree.root().unwrap()),
        "(doc part: (item) (comment) part: (item))"
    );
    let comment = tree
        .root()
        .unwrap()
        .children()
        .find(|n| n.name() == "comment")
        .unwrap();
    assert!(comment.is_extra());
    assert_eq!(comment.field(), None);
    assert_eq!(comment.span().range(), 2..4);
    assert_eq!(comment.parent().unwrap().name(), "doc");
}

#[test]
fn extras_between_a_pairs_items_belong_inside_and_after_its_last_item_outside() {
    let rules = format!(
        r#"
      "doc":{{"type":"REPEAT1","content":{{"type":"SYMBOL","name":"pair"}}}},
      "pair":{{"type":"SEQ","members":[{{"type":"SYMBOL","name":"item"}},{{"type":"SYMBOL","name":"item"}}]}},
      "item":{{"type":"PATTERN","value":"[a-z]+"}}{COMMENT}"#
    );
    let grammar = compile(&rules, ASIDES);
    let tree = parse(&grammar, b"a #one\nb #two\nc d");
    assert_eq!(
        named(tree.root().unwrap()),
        "(doc (pair (item) (comment) (item)) (comment) (pair (item) (item)))"
    );
    let outer = tree
        .root()
        .unwrap()
        .children()
        .find(|n| n.name() == "comment")
        .unwrap();
    assert_eq!(outer.text(), b"#two");
    let inner = tree
        .root()
        .unwrap()
        .children()
        .next()
        .unwrap()
        .children()
        .find(|n| n.is_extra())
        .unwrap();
    assert_eq!(inner.text(), b"#one");
}

#[test]
fn shared_named_literals_wrap_without_renaming_the_other_literal_site() {
    let grammar = compile(
        r#"
      "doc":{"type":"SEQ","members":[{"type":"STRING","value":"x"},{"type":"SYMBOL","name":"keyword"}]},
      "keyword":{"type":"STRING","value":"x"}"#,
        "",
    );
    let tree = parse(&grammar, b"xx");
    assert_eq!(named(tree.root().unwrap()), "(doc (keyword))");
    let children: Vec<_> = tree.root().unwrap().children().collect();
    assert_eq!(children[0].name(), "x");
    assert!(!children[0].is_named());
    assert_eq!(children[1].name(), "keyword");
    assert!(children[1].is_named());
    let wrapped = children[1].children().next().unwrap();
    assert_eq!(wrapped.name(), "x");
    assert_eq!(wrapped.span().range(), 1..2);
}

#[test]
fn hidden_literal_tokens_keep_their_anonymous_spelling_and_use_site_recipes() {
    let literal = serde_json::json!({"type":"STRING","value":"\""});
    for body in [
        literal.clone(),
        serde_json::json!({"type":"TOKEN","content":literal}),
        serde_json::json!({"type":"IMMEDIATE_TOKEN","content":literal}),
        serde_json::json!({"type":"TOKEN","content":{"type":"PREC","value":1,"content":literal}}),
    ] {
        let source = serde_json::json!({"rules":{
            "doc":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_open"},{"type":"STRING","value":"x"}]},
            "_open":body
        }});
        let grammar = CompiledGrammar::compile(&serde_json::to_vec(&source).unwrap()).unwrap();
        let tree = parse(&grammar, b"\"x");
        let children: Vec<_> = tree.root().unwrap().children().collect();
        assert_eq!(
            children
                .iter()
                .map(|n| (n.name(), n.is_named(), n.span().range()))
                .collect::<Vec<_>>(),
            [("\"", false, 0..1), ("x", false, 1..2)]
        );
    }
    // A hidden regular expression remains invisible even when its only match
    // is this same character. The anonymous atom comes from STRING syntax.
    let regex = compile(
        r#""doc":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_open"},{"type":"STRING","value":"x"}]},"_open":{"type":"PATTERN","value":"\""}"#,
        "",
    );
    let tree = parse(&regex, b"\"x");
    assert_eq!(
        tree.root()
            .unwrap()
            .children()
            .map(|n| n.name())
            .collect::<Vec<_>>(),
        ["x"]
    );
    let shared = compile(
        r#""doc":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_open"},{"type":"STRING","value":"\""}]},"_open":{"type":"STRING","value":"\""}"#,
        "",
    );
    let tree = parse(&shared, b"\"\"");
    assert_eq!(
        tree.root()
            .unwrap()
            .children()
            .map(|n| (n.name(), n.is_named()))
            .collect::<Vec<_>>(),
        [("\"", false), ("\"", false)]
    );
    let recipes = compile(
        r#""doc":{"type":"SEQ","members":[{"type":"FIELD","name":"opening","content":{"type":"SYMBOL","name":"_open"}},{"type":"ALIAS","named":true,"value":"closing","content":{"type":"SYMBOL","name":"_open"}}]},"_open":{"type":"STRING","value":"\""}"#,
        "",
    );
    let tree = parse(&recipes, b"\"\"");
    let children: Vec<_> = tree.root().unwrap().children().collect();
    assert_eq!(
        (
            children[0].name(),
            children[0].is_named(),
            children[0].field()
        ),
        ("\"", false, Some("opening"))
    );
    assert_eq!(
        (
            children[1].name(),
            children[1].is_named(),
            children[1].field()
        ),
        ("closing", true, None)
    );
    let named_literal = compile(
        r#""doc":{"type":"SYMBOL","name":"open"},"open":{"type":"STRING","value":"\""}"#,
        "",
    );
    let tree = parse(&named_literal, b"\"");
    let open = tree.root().unwrap().children().next().unwrap();
    assert_eq!((open.name(), open.is_named()), ("open", true));
}

#[test]
fn epsilon_in_a_whitespace_gap_stands_at_the_previous_token_end() {
    let grammar = compile(
        r#"
      "doc":{"type":"SEQ","members":[{"type":"SYMBOL","name":"left"},{"type":"SYMBOL","name":"gap"},{"type":"SYMBOL","name":"right"}]},
      "left":{"type":"STRING","value":"a"}, "gap":{"type":"BLANK"}, "right":{"type":"STRING","value":"b"}"#,
        SPACES,
    );
    let tree = parse(&grammar, b"a  b");
    assert_eq!(named(tree.root().unwrap()), "(doc (left) (gap) (right))");
    let gap = tree
        .root()
        .unwrap()
        .children()
        .find(|n| n.name() == "gap")
        .unwrap();
    assert_eq!(gap.span().range(), 1..1);
    assert_eq!(gap.text(), b"");
}

#[test]
fn nullable_lists_accept_their_own_order_and_keep_helpers_invisible() {
    let grammar = compile(
        r#"
      "doc":{"type":"SEQ","members":[{"type":"REPEAT","content":{"type":"STRING","value":"x"}},{"type":"REPEAT","content":{"type":"STRING","value":"y"}}]}"#,
        "",
    );
    let mut session = grammar.session();
    for source in [b"".as_slice(), b"xx", b"yy", b"xxyy"] {
        let tree = session.parse(source).unwrap();
        assert_eq!(named(tree.root().unwrap()), "(doc)");
        assert!(
            tree.root()
                .unwrap()
                .children()
                .all(|n| matches!(n.name(), "x" | "y"))
        );
    }
    let refused = session.parse_partial(b"yx").unwrap();
    assert!(matches!(refused.stop(), Stop::Unexpected { at: 1, .. }));
    assert!(!refused.confidence().is_strict());
}

#[test]
fn an_anonymous_extra_explicitly_admitted_by_the_parser_is_structural() {
    let grammar = compile(
        r#"
      "doc":{"type":"SEQ","members":[{"type":"SYMBOL","name":"item"},{"type":"STRING","value":"\n"},{"type":"SYMBOL","name":"item"}]},
      "item":{"type":"PATTERN","value":"[a-z]+"}"#,
        r#", "extras":[{"type":"STRING","value":"\n"},{"type":"PATTERN","value":"[ \t]"}]"#,
    );
    let tree = parse(&grammar, b"a\nb");
    let newline = tree
        .root()
        .unwrap()
        .children()
        .find(|n| n.name() == "\n")
        .unwrap();
    assert!(!newline.is_named());
    assert!(!newline.is_extra());
    assert_eq!(newline.span().range(), 1..2);
}

#[test]
fn unsupported_wrappers_and_excessive_nesting_fail_explicitly() {
    {
        let src = br#"{"rules":{"doc":{"type":"UNRECOGNIZED","value":1,"content":{"type":"STRING","value":"x"}}}}"#;
        assert!(matches!(
            CompiledGrammar::compile(src),
            Err(Error::Compile(CompileError::Unsupported(_)))
        ));
    }
    let mut body = serde_json::json!({"type":"STRING","value":"x"});
    for _ in 0..150 {
        body = serde_json::json!({"type":"FIELD","name":"nested","content":body});
    }
    let grammar = serde_json::json!({"rules":{"doc":body}});
    assert!(matches!(
        CompiledGrammar::compile(&serde_json::to_vec(&grammar).unwrap()),
        Err(Error::Compile(_))
    ));
}

#[test]
fn authored_operator_precedence_and_sides_control_complete_derivations() {
    let grammar = CompiledGrammar::compile(include_bytes!("fixtures/operators.json")).unwrap();
    for (source, left, right) in [
        (b"a+a+a".as_slice(), 0..3, 4..5),
        (b"a^a^a".as_slice(), 0..1, 2..5),
        (b"a+a*a".as_slice(), 0..1, 2..5),
        (b"a*a+a".as_slice(), 0..3, 4..5),
    ] {
        let tree = parse(&grammar, source);
        let expression = tree.root().unwrap().children().next().unwrap();
        let operands: Vec<_> = expression
            .children()
            .filter(|n| n.name() == "expression")
            .collect();
        assert_eq!(operands.len(), 2);
        assert_eq!(
            operands[0].span().range(),
            left,
            "{}",
            String::from_utf8_lossy(source)
        );
        assert_eq!(
            operands[1].span().range(),
            right,
            "{}",
            String::from_utf8_lossy(source)
        );
    }
}

#[test]
fn dynamic_ranks_choose_after_both_complete_readings_are_available() {
    let grammar = CompiledGrammar::compile(include_bytes!("fixtures/dynamic.json")).unwrap();
    let tree = parse(&grammar, b"xy");
    assert_eq!(named(tree.root().unwrap()), "(document (plain))");
}

#[test]
fn cursor_equivalence_erases_only_spent_precedence_and_keeps_tree_recipes() {
    let bytes = include_bytes!("fixtures/cursor-ranks.json");
    let grammar = CompiledGrammar::compile(bytes).unwrap();
    let tree = parse(&grammar, b"xw;");
    assert_eq!(named(tree.root().unwrap()), "(doc (node))");

    // Those consumed alternatives cease being equivalent when they author
    // different aliases, fields, or dynamic weights on the same spelling.
    for feature in ["alias", "field", "dynamic"] {
        let mut different: serde_json::Value = serde_json::from_slice(bytes).unwrap();
        for (name, value) in [("_high", "higher"), ("_low", "lower")] {
            let body = serde_json::json!({"type":"STRING","value":"x"});
            different["rules"][name] = match feature {
                "alias" => {
                    serde_json::json!({"type":"ALIAS","named":true,"value":value,"content":body})
                }
                "field" => serde_json::json!({"type":"FIELD","name":value,"content":body}),
                _ => {
                    serde_json::json!({"type":"PREC_DYNAMIC","value":if name == "_high" {1} else {2},"content":body})
                }
            };
        }
        // Removing the competing `other` reading isolates the two recipes.
        different["rules"]["doc"] = serde_json::json!({"type":"SEQ","members":[{"type":"SYMBOL","name":"node"},{"type":"STRING","value":";"}]});
        assert!(
            matches!(
                CompiledGrammar::compile(&serde_json::to_vec(&different).unwrap()),
                Err(Error::Compile(CompileError::Conflict { .. }))
            ),
            "{feature} cannot be erased"
        );
    }
}

#[test]
fn cursor_families_keep_actual_named_children_and_contextual_maximal_munch() {
    let grammar =
        CompiledGrammar::compile(include_bytes!("fixtures/cursor-histories.json")).unwrap();
    for (source, child) in [
        (b"aAz=".as_slice(), "A"),
        (b"aBz=", "B"),
        (b"bAz==", "A"),
        (b"bBz==", "B"),
    ] {
        let tree = parse(&grammar, source);
        assert_eq!(
            named(tree.root().unwrap()),
            format!("(doc (parent ({child})))")
        );
    }
    let mut session = grammar.session();
    for source in [b"aAz==".as_slice(), b"bBz="] {
        assert!(
            session.parse(source).is_err(),
            "{}",
            String::from_utf8_lossy(source)
        );
    }
}

#[test]
fn cursor_families_preserve_fields_inherited_from_each_actual_hidden_child() {
    let grammar = compile(
        r#""doc":{"type":"SEQ","members":[{"type":"SYMBOL","name":"parent"},{"type":"STRING","value":"!"}]},
        "parent":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"SYMBOL","name":"_a"},{"type":"STRING","value":"z"}]},{"type":"SEQ","members":[{"type":"SYMBOL","name":"_b"},{"type":"STRING","value":"z"}]}]},
        "_a":{"type":"FIELD","name":"left","content":{"type":"SYMBOL","name":"A"}},
        "_b":{"type":"FIELD","name":"right","content":{"type":"SYMBOL","name":"B"}},
        "A":{"type":"STRING","value":"a"},"B":{"type":"STRING","value":"b"}"#,
        "",
    );
    for (source, expected) in [
        (b"az!".as_slice(), "(doc (parent left: (A)))"),
        (b"bz!", "(doc (parent right: (B)))"),
    ] {
        let tree = parse(&grammar, source);
        assert_eq!(named(tree.root().unwrap()), expected);
    }
}
