use super::*;

fn frontier_order(tree: &TreeSnapshot) -> Vec<NodeId> {
    let mut frontier: Vec<_> = tree.roots.iter().rev().copied().collect();
    let mut nodes = Vec::new();
    while let Some(node) = frontier.pop() {
        nodes.push(node);
        frontier.extend(
            tree.children[tree.nodes[node.index()].child_range()]
                .iter()
                .rev()
                .copied(),
        );
    }
    nodes
}

fn image(result: Result<Vec<QueryMatch<'_>>, QueryError>) -> serde_json::Value {
    match result {
        Ok(matches) => serde_json::json!({"matches": matches.into_iter().map(|found| {
            (found.pattern.index(), found.captures.into_iter()
                .map(|capture| (capture.id.index(), capture.node.index())).collect::<Vec<_>>())
        }).collect::<Vec<_>>() }),
        Err(error) => serde_json::json!({"error": format!("{error:?}")}),
    }
}

fn compare(query: &Query, tree: &TreeSnapshot) {
    let order = frontier_order(tree);
    assert_eq!(
        order.iter().map(|node| node.index()).collect::<Vec<_>>(),
        (0..tree.nodes.len()).collect::<Vec<_>>()
    );
    // Exercise every work boundary, including failures during search, sorting
    // and final publication, as well as independent capture/match/depth limits.
    let limits = QueryLimits::default();
    for work in 0..=2048 {
        let limits = QueryLimits { work, ..limits };
        assert_eq!(
            image(execute(query, tree, ForeignPolicy::Refuse, limits)),
            image(execute_nodes(
                query,
                tree,
                ForeignPolicy::Refuse,
                limits,
                order.iter().copied(),
            )),
            "work={work}"
        );
    }
    for ceiling in 0..=16 {
        for limits in [
            QueryLimits {
                captures: ceiling,
                ..limits
            },
            QueryLimits {
                matches: ceiling,
                ..limits
            },
            QueryLimits {
                depth: ceiling,
                ..limits
            },
        ] {
            assert_eq!(
                image(execute(query, tree, ForeignPolicy::Refuse, limits)),
                image(execute_nodes(
                    query,
                    tree,
                    ForeignPolicy::Refuse,
                    limits,
                    order.iter().copied(),
                ))
            );
        }
    }
}

#[test]
fn arena_visits_preserve_forests_aliases_extras_results_and_limit_boundaries() {
    let grammar =
        CompiledGrammar::compile(include_bytes!("../../../../test/grammar/json.json")).unwrap();
    let query = Query::compile(
        Arc::clone(&grammar),
        b"_ @all\n(number) @n @n\n(array (number) @a (number) @b)\n(array (number)+ @many)",
    )
    .unwrap();
    for source in [b"[1,2,3]".as_slice(), b"[1,@", b""] {
        let tree = grammar.session().parse_partial(source).unwrap();
        compare(&query, &tree);
    }

    let grammar = CompiledGrammar::compile(br##"{"name":"query_arena","rules":{
      "doc":{"type":"SEQ","members":[{"type":"FIELD","name":"left","content":{"type":"ALIAS","named":true,"value":"renamed","content":{"type":"SYMBOL","name":"item"}}},{"type":"STRING","value":":"},{"type":"SYMBOL","name":"item"}]},
      "item":{"type":"PATTERN","value":"[a-z]+"},"comment":{"type":"PATTERN","value":"#[^\\n]*"}},
      "extras":[{"type":"PATTERN","value":"\\s"},{"type":"SYMBOL","name":"comment"}]}"##).unwrap();
    let query = Query::compile(
        Arc::clone(&grammar),
        b"_ @all\n(doc left: (renamed) @r (item) @i)\n(comment) @c",
    )
    .unwrap();
    compare(&query, &grammar.session().parse(b"a: #between\nb").unwrap());
}
