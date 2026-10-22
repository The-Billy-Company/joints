#![forbid(unsafe_code)]

use joints_engine::{CompiledGrammar, Node, Recovery, RepairKind, Stop, Supply};
use serde_json::{Value, json};
use std::{fs, path::PathBuf};

fn shape(node: Node<'_>) -> Value {
    let mut value = json!({"name":node.name(),"named":node.is_named(),"start":node.span().start(),
        "end":node.span().end(),"kids":node.children().map(shape).collect::<Vec<_>>()});
    if let Some(field) = node.field() {
        value["field"] = json!(field);
    }
    value
}

#[test]
fn all_twenty_five_frozen_cases_preserve_trees_repairs_and_first_stops() {
    let bundle = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../test/migration/reference");
    let manifest: Value =
        serde_json::from_slice(&fs::read(bundle.join("manifest.json")).unwrap()).unwrap();
    let cases = manifest["cases"].as_array().unwrap();
    assert_eq!(cases.len(), 25);
    let grammar = CompiledGrammar::compile(include_bytes!("../../test/grammar/json.json")).unwrap();
    let mut session = grammar.session();
    for case in cases {
        let id = case["id"].as_str().unwrap();
        let default = id.ends_with("-default");
        session.set_recovery(if default {
            Recovery::Fell
        } else {
            Recovery::None
        });
        session.set_supply(if default {
            Supply::UniqueLiteral
        } else {
            Supply::Disabled
        });
        let source = fs::read(bundle.join(case["argv"][2].as_str().unwrap())).unwrap();
        let expected: Value =
            serde_json::from_slice(&fs::read(bundle.join(format!("outputs/{id}.json"))).unwrap())
                .unwrap();
        let tree = session.parse_partial(&source).unwrap();
        assert_eq!(
            tree.roots().map(shape).collect::<Vec<_>>(),
            expected["tree"].as_array().unwrap().clone(),
            "{id}: syntax"
        );
        let stop = match tree.stop() {
            Stop::Accepted => json!({"kind":"accepted"}),
            Stop::Truncated => json!({"kind":"truncated"}),
            Stop::Stray { at } => json!({"kind":"stray","at":at}),
            Stop::Unexpected { at, .. } => {
                json!({"kind":"unexpected","at":at,"symbol":tree.stop_symbol().unwrap()})
            }
        };
        let mut reference_stop = expected["stop"].clone();
        reference_stop.as_object_mut().unwrap().remove("state");
        assert_eq!(stop, reference_stop, "{id}: first stop");
        assert_eq!(
            tree.mends(),
            usize::try_from(expected["mends"].as_u64().unwrap()).expect("fixture count fits usize"),
            "{id}: deletions"
        );
        assert_eq!(
            tree.skipped(),
            usize::try_from(expected["skipped"].as_u64().unwrap())
                .expect("fixture count fits usize"),
            "{id}: skipped bytes"
        );
        assert_eq!(
            tree.supplied(),
            usize::try_from(expected["supplied"].as_u64().unwrap())
                .expect("fixture count fits usize"),
            "{id}: supplies"
        );
        assert_eq!(
            tree.spurned(),
            usize::try_from(expected["spurned"].as_u64().unwrap())
                .expect("fixture count fits usize"),
            "{id}: ambiguity"
        );
        assert_eq!(
            tree.survey().is_sound(),
            expected["survey"]["sound"].as_bool().unwrap(),
            "{id}: soundness"
        );
        assert_eq!(
            tree.survey().walked,
            usize::try_from(expected["survey"]["walked"].as_u64().unwrap())
                .expect("fixture count fits usize"),
            "{id}: published nodes"
        );
        assert_eq!(
            tree.survey().walked,
            tree.survey().held,
            "{id}: selected forest owns every materialized node"
        );
        let scars: Vec<_> = tree.repairs().iter().map(|repair| {
            let felled = matches!(repair.kind, RepairKind::Deleted { felled:true });
            let mut scar = json!({"at":repair.span.start(),"over":repair.span.end(),"felled":felled,
                "heads":repair.heads,"shifted":repair.shifted});
            if let Some(gave) = tree.repair_symbol(repair) { scar["gave"] = json!(gave); }
            scar
        }).collect();
        assert_eq!(
            scars,
            expected["scars"].as_array().unwrap().clone(),
            "{id}: scars"
        );
        assert_eq!(
            tree.confidence().is_strict(),
            case["strict"].as_bool().unwrap(),
            "{id}: strict"
        );
        let product = session.product(&mut grammar.effect_store()).unwrap();
        assert_eq!(
            product.is_zero(),
            tree.mends() > 0,
            "{id}: breaks absorb stack products"
        );
    }
}

#[test]
fn keeping_felling_and_relenting_are_distinct_and_none_disables_supplies() {
    let grammar = CompiledGrammar::compile(include_bytes!("../../test/grammar/json.json")).unwrap();
    for policy in [
        Recovery::None,
        Recovery::Keep,
        Recovery::Fell,
        Recovery::Relent,
    ] {
        let mut session = grammar.session();
        session.set_recovery(policy);
        let tree = session.parse_partial(b"[1,,,2]").unwrap();
        assert!(!tree.confidence().is_strict());
        assert!(tree.survey().is_sound());
        match policy {
            Recovery::None => assert_eq!(tree.mends(), 0),
            Recovery::Keep => assert!(
                tree.repairs()
                    .iter()
                    .all(|r| r.kind == RepairKind::Deleted { felled: false })
            ),
            Recovery::Fell => assert!(
                tree.repairs()
                    .iter()
                    .all(|r| r.kind == RepairKind::Deleted { felled: true })
            ),
            Recovery::Relent => {
                assert_eq!(
                    tree.repairs()[0].kind,
                    RepairKind::Deleted { felled: false }
                );
                assert_eq!(tree.repairs()[1].kind, RepairKind::Deleted { felled: true });
            }
        }
    }
    let mut session = grammar.session();
    session.set_supply(Supply::UniqueLiteral);
    assert!(
        session
            .parse_partial(br#"{"a" 1}"#)
            .unwrap()
            .repairs()
            .is_empty()
    );
}

#[test]
fn multiple_literal_candidates_do_not_invent_a_delimiter() {
    let grammar = CompiledGrammar::compile(br#"{"name":"ambiguous_repair","rules":{"doc":{"type":"SEQ","members":[
        {"type":"STRING","value":"a"},{"type":"CHOICE","members":[{"type":"STRING","value":","},{"type":"STRING","value":";"}]},
        {"type":"STRING","value":"b"}]}}}"#).unwrap();
    let mut session = grammar.session();
    session.set_recovery(Recovery::Keep);
    session.set_supply(Supply::UniqueLiteral);
    let tree = session.parse_partial(b"ab").unwrap();
    assert_eq!(tree.supplied(), 0);
    assert_eq!(tree.spurned(), 1);
}

#[test]
fn a_known_repair_is_declined_when_a_competing_literal_has_an_unproven_reading() {
    let mut specification = json!({"name":"uncertain_repair","rules":{
        "doc":{"type":"CHOICE","members":[
          {"type":"SEQ","members":[{"type":"SYMBOL","name":"a"},{"type":"STRING","value":"s"},{"type":"STRING","value":"w"}]},
          {"type":"SEQ","members":[{"type":"SYMBOL","name":"b"},{"type":"STRING","value":"t"},{"type":"STRING","value":"q"}]},
          {"type":"SEQ","members":[{"type":"SYMBOL","name":"c"},{"type":"STRING","value":"t"},{"type":"STRING","value":"r"}]}]},
        "a":{"type":"SYMBOL","name":"item"},
        "b":{"type":"SYMBOL","name":"item"},
        "c":{"type":"SYMBOL","name":"item"},
        "item":{"type":"PATTERN","value":"g"}},"conflicts":[["b","c"]]});
    let parse = |specification: &Value| {
        let grammar =
            CompiledGrammar::compile(&serde_json::to_vec(specification).unwrap()).unwrap();
        let mut session = grammar.session();
        session.set_recovery(Recovery::Keep);
        session.set_supply(Supply::UniqueLiteral);
        session.parse_partial(b"gw").unwrap()
    };
    // Supplying s resumes the real w, but candidate t reaches an authored
    // reduction fork. Uncertainty about t cannot establish that s is unique.
    let uncertain = parse(&specification);
    assert_eq!(uncertain.supplied(), 0);
    assert_eq!(uncertain.mends(), 1);
    assert!(
        uncertain
            .repairs()
            .iter()
            .all(|repair| matches!(repair.kind, RepairKind::Deleted { .. }))
    );
    // Removing the uncertain competitor makes the same two-leg proof decisive.
    specification["rules"]["doc"] = json!({"type":"SEQ","members":[
        {"type":"SYMBOL","name":"a"},{"type":"STRING","value":"s"},{"type":"STRING","value":"w"}]});
    specification["conflicts"] = json!([]);
    let decisive = parse(&specification);
    assert_eq!(decisive.supplied(), 1);
    assert_eq!(decisive.mends(), 0);
    assert_eq!(decisive.repair_symbol(&decisive.repairs()[0]), Some("s"));
    assert_eq!(decisive.root().unwrap().name(), "doc");
}
