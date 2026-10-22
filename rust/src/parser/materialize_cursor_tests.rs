use super::*;

fn image(tree: &TreeSnapshot) -> serde_json::Value {
    serde_json::json!({
        "source":tree.source(),"stop":format!("{:?}",tree.stop()),
        "confidence":format!("{:?}",tree.confidence()),"survey":format!("{:?}",tree.survey()),
        "repairs":format!("{:?}",tree.repairs()),"spurned":tree.spurned(),
        "roots":tree.roots().map(|n|n.index()).collect::<Vec<_>>(),
        "nodes":(0..tree.nodes.len()).map(|i| {
            let n=tree.node_at(i).unwrap();
            serde_json::json!({"name":n.name(),"named":n.is_named(),"extra":n.is_extra(),
                "field":n.field(),"span":[n.span().start(),n.span().end()],"text":n.text(),
                "start":format!("{:?}",n.start_point()),"end":format!("{:?}",n.end_point()),
                "parent":n.parent().map(|p|p.index()),"children":n.children().map(|c|c.index()).collect::<Vec<_>>()})
        }).collect::<Vec<_>>()
    })
}
fn materialize_image(
    session: &mut ParseSession,
    forest: &[Use],
    original: bool,
) -> serde_json::Value {
    session.steps = 0;
    let result = match if original {
        session.materialize_original(forest)
    } else {
        session.materialize(forest)
    } {
        Ok(Materialized {
            nodes,
            children,
            roots,
        }) => {
            let mut tree = TreeSnapshot {
                grammar: Arc::clone(&session.grammar),
                source: Arc::from(b"".as_slice()),
                nodes,
                children,
                roots,
                stop: Stop::Accepted,
                lines: vec![0],
                survey: Survey::default(),
                repairs: vec![],
                spurned: 0,
            };
            tree.survey = tree.measure();
            image(&tree)
        }
        Err(error) => serde_json::json!({"error":format!("{error:?}")}),
    };
    serde_json::json!({"result":result,"work":session.steps})
}
#[test]
fn cursor_preserves_dag_alias_fields_multiple_roots_and_every_refusal_boundary() {
    assert_eq!(size_of::<MaterializeCursor>(), 16);
    let grammar=CompiledGrammar::compile(br#"{"rules":{"doc":{"type":"SEQ","members":[{"type":"FIELD","name":"first","content":{"type":"ALIAS","named":true,"value":"first_alias","content":{"type":"STRING","value":"x"}}},{"type":"FIELD","name":"second","content":{"type":"ALIAS","named":true,"value":"second_alias","content":{"type":"STRING","value":"x"}}}]}}}"#).unwrap();
    let graph = Arc::clone(&grammar.automaton);
    let aliases = (0..graph.production_count())
        .flat_map(|i| {
            let id = ProductionId::from_index(i);
            graph
                .production(id)
                .steps
                .iter()
                .enumerate()
                .filter_map(move |(step, item)| {
                    item.alias
                        .as_ref()
                        .map(|_| (id, u32::try_from(step).unwrap()))
                })
        })
        .take(2)
        .collect::<Vec<_>>();
    assert_eq!(aliases.len(), 2);
    let mut session = grammar.session();
    let mut leaf = session
        .mint(graph.start_symbol(), span(0, 0).unwrap(), vec![], false)
        .unwrap();
    leaf.alias = Some(aliases[0]);
    leaf.field = Some(FieldId::from_index(0));
    let mut other = leaf;
    other.alias = Some(aliases[1]);
    other.field = Some(FieldId::from_index(1));
    let parent = session
        .mint(
            graph.start_symbol(),
            span(0, 0).unwrap(),
            vec![leaf, other, leaf, other],
            false,
        )
        .unwrap();
    let forest = [parent, other, parent];
    for nodes in 0..=12 {
        for work in 0..=14 {
            session.limits.nodes = nodes;
            session.limits.steps = work;
            let old = materialize_image(&mut session, &forest, true);
            let cursor = materialize_image(&mut session, &forest, false);
            assert_eq!(old, cursor, "nodes={nodes} work={work}");
        }
    }
}
#[test]
fn cursor_handles_wide_siblings_and_deep_first_last_and_unary_paths_iteratively() {
    let grammar =
        CompiledGrammar::compile(br#"{"rules":{"doc":{"type":"STRING","value":"x"}}}"#).unwrap();
    for shape in 0..4 {
        let mut session = grammar.session();
        let symbol = grammar.automaton.start_symbol();
        let leaf = session
            .mint(symbol, span(0, 0).unwrap(), vec![], false)
            .unwrap();
        let mut root = leaf;
        if shape == 0 {
            root = session
                .mint(symbol, span(0, 0).unwrap(), vec![leaf; 4096], false)
                .unwrap();
        } else {
            for _ in 0..4096 {
                let children = match shape {
                    1 => vec![root],
                    2 => vec![leaf, root],
                    _ => vec![root, leaf],
                };
                root = session
                    .mint(symbol, span(0, 0).unwrap(), children, false)
                    .unwrap();
            }
        }
        let forest = [root, leaf];
        let old = materialize_image(&mut session, &forest, true);
        let cursor = materialize_image(&mut session, &forest, false);
        assert_eq!(old, cursor, "shape={shape}");
    }
}
