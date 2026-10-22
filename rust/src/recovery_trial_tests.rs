//! Differential controls for the private fixed-overlay/lazy-pending trial.
use super::*;
use std::collections::VecDeque;

fn reason(old: frozen_e::Uncertain) -> Uncertain {
    match old {
        frozen_e::Uncertain::Branch => Uncertain::Branch,
        frozen_e::Uncertain::Depth => Uncertain::Depth,
        frozen_e::Uncertain::Work => Uncertain::Work,
    }
}
fn proof(old: frozen_e::Proof) -> Proof {
    match old {
        frozen_e::Proof::Reads(to) => Proof::Reads(to),
        frozen_e::Proof::Stops => Proof::Stops,
        frozen_e::Proof::Unknown(why) => Proof::Unknown(reason(why)),
    }
}
fn insertion_answer(old: frozen_e::Insertion) -> Insertion {
    match old {
        frozen_e::Insertion::Unique(symbol) => Insertion::Unique(symbol),
        frozen_e::Insertion::None => Insertion::None,
        frozen_e::Insertion::Ambiguous => Insertion::Ambiguous,
        frozen_e::Insertion::Unknown(why) => Insertion::Unknown(reason(why)),
    }
}
fn compare(graph: &Automaton, states: &[StateId], symbol: SymbolId) {
    let old = frozen_e::admission(graph, states, symbol);
    assert_eq!(
        admission(graph, states, symbol),
        (proof(old.0), old.1),
        "admission on {states:?} for {symbol:?}"
    );
    let old = frozen_e::insertion(graph, states, symbol);
    assert_eq!(
        insertion(graph, states, symbol),
        (insertion_answer(old.0), old.1),
        "insertion on {states:?} for {symbol:?}"
    );
}
fn compile_graph(value: serde_json::Value) -> Automaton {
    Automaton::from_tree_sitter(&serde_json::to_vec(&value).unwrap()).unwrap()
}
fn sym(name: &str) -> serde_json::Value {
    serde_json::json!({"type":"SYMBOL","name":name})
}
fn literal(text: &str) -> serde_json::Value {
    serde_json::json!({"type":"STRING","value":text})
}
fn seq(items: Vec<serde_json::Value>) -> serde_json::Value {
    serde_json::json!({"type":"SEQ","members":items})
}

#[test]
fn real_fixture_state_paths_preserve_every_proof_insertion_and_spent_count() {
    let mut inputs = vec![
        include_bytes!("../../test/grammar/json.json").to_vec(),
        include_bytes!("../tests/fixtures/cursor-histories.json").to_vec(),
        include_bytes!("../tests/fixtures/cursor-ranks.json").to_vec(),
        include_bytes!("../tests/fixtures/factoring.json").to_vec(),
        include_bytes!("../tests/fixtures/dynamic.json").to_vec(),
        include_bytes!("../tests/fixtures/operators.json").to_vec(),
    ];
    for source in [
        include_str!("../tests/fixtures/declared-choice.json"),
        include_str!("../tests/fixtures/nullable-token.json"),
    ] {
        for case in serde_json::from_str::<Vec<serde_json::Value>>(source).unwrap() {
            inputs.push(case["grammar"].as_str().unwrap().as_bytes().to_vec());
        }
    }
    let mut queries = 0;
    let mut real_paths = 0;
    for input in &inputs {
        let graph = Automaton::from_tree_sitter(input).unwrap();
        let mut paths = vec![None; graph.state_count()];
        paths[graph.start_state().index()] = Some(vec![graph.start_state()]);
        let mut queue = VecDeque::from([graph.start_state()]);
        while let Some(from) = queue.pop_front() {
            for (_, to) in graph.state_transitions(from) {
                if paths[to.index()].is_none() {
                    let mut path = paths[from.index()].as_ref().unwrap().clone();
                    path.push(to);
                    paths[to.index()] = Some(path);
                    queue.push_back(to);
                }
            }
        }
        let symbols: Vec<_> = graph.lexical_rules().map(|(id, _)| id).collect();
        for prefix in paths.iter().flatten() {
            real_paths += 1;
            for &symbol in &symbols {
                compare(&graph, prefix, symbol);
                queries += 1;
            }
            // A missing predecessor must not acquire a witness from quotient rows.
            let mut broken = prefix.clone();
            broken.fill(graph.start_state());
            for &symbol in &symbols {
                compare(&graph, &broken, symbol);
                queries += 1;
            }
        }
        for floor in paths.iter().flatten() {
            for id in 0..graph.production_count() {
                let production = graph.production(crate::ProductionId::from_index(id));
                let mut path = floor.clone();
                let concrete = production.steps.iter().all(|step| {
                    if let Some(to) = graph.transition(*path.last().unwrap(), step.symbol) {
                        path.push(to);
                        true
                    } else {
                        false
                    }
                });
                if concrete {
                    real_paths += 1;
                    for &symbol in &symbols {
                        compare(&graph, &path, symbol);
                        queries += 1;
                    }
                }
            }
        }
    }
    assert_eq!(inputs.len(), 33);
    assert!(real_paths > 500, "{real_paths}");
    assert!(queries > 10_000, "{queries}");
    eprintln!(
        "RECOVERY_DIFFERENTIAL graphs={} paths={real_paths} queries={queries} admission+insertion",
        inputs.len()
    );
}

#[test]
fn authored_branch_preserves_pending_order_and_unique_continuation_uncertainty() {
    let graph = compile_graph(serde_json::json!({"name":"declared_branches","rules":{
        "doc":seq(vec![serde_json::json!({"type":"CHOICE","members":[sym("left"),sym("right")]}),literal("!")]),
        "left":seq(vec![sym("atom")]),"right":seq(vec![sym("atom")]),"atom":literal("a")},"conflicts":[["left","right"]]}));
    let atom = graph.symbol_by_name("atom").unwrap();
    let end = graph.symbol_by_name("!").unwrap();
    let start = graph.start_state();
    let states = [start, graph.transition(start, atom).unwrap()];
    assert!(graph.actions(states[1], Lookahead::Terminal(end)).len() >= 2);
    compare(&graph, &states, end);
    let mut work = 0;
    assert_eq!(
        take(&graph, &mut Stack::new(&states), end, &mut work),
        Proof::Unknown(Uncertain::Branch)
    );
    assert_eq!(work, 1);
    assert!(matches!(admission(&graph, &states, end), (Proof::Reads(_), spent) if spent > 1));
}

#[test]
fn authored_nullable_depth_and_long_chain_work_refusals_match_exactly() {
    let mut rules = serde_json::Map::new();
    rules.insert(
        "doc".into(),
        seq((0..10)
            .map(|i| sym(&format!("empty{i}")))
            .chain([literal("z")])
            .collect()),
    );
    for i in 0..10 {
        rules.insert(format!("empty{i}"), serde_json::json!({"type":"BLANK"}));
    }
    let graph = compile_graph(serde_json::json!({"name":"overlay_depth","rules":rules}));
    let end = graph.symbol_by_name("z").unwrap();
    let states = [graph.start_state()];
    compare(&graph, &states, end);
    assert_eq!(
        admission(&graph, &states, end).0,
        Proof::Unknown(Uncertain::Depth)
    );
    let mut rules = serde_json::Map::new();
    rules.insert("doc".into(), seq(vec![sym("n0"), literal("z")]));
    for i in 0..96 {
        rules.insert(format!("n{i}"), sym(&format!("n{}", i + 1)));
    }
    rules.insert("n96".into(), seq(vec![literal("a"), literal("b")]));
    let graph = compile_graph(serde_json::json!({"name":"proof_work","rules":rules}));
    let mut states = vec![graph.start_state()];
    for text in ["a", "b"] {
        states.push(
            graph
                .transition(*states.last().unwrap(), graph.symbol_by_name(text).unwrap())
                .unwrap(),
        );
    }
    let end = graph.symbol_by_name("z").unwrap();
    compare(&graph, &states, end);
    assert_eq!(
        admission(&graph, &states, end),
        (Proof::Unknown(Uncertain::Work), 256)
    );
    let mut work = usize::MAX;
    assert_eq!(
        take(&graph, &mut Stack::new(&states), end, &mut work),
        Proof::Unknown(Uncertain::Work)
    );
    assert_eq!(work, usize::MAX);
}

#[test]
fn authored_consuming_cycle_preserves_repeated_state_paths_and_empty_stack() {
    let graph = compile_graph(serde_json::json!({"name":"consuming_cycle","rules":{
        "doc":seq(vec![sym("nested"),literal("!")]),
        "nested":{"type":"CHOICE","members":[seq(vec![literal("("),sym("nested"),literal(")")]),{"type":"BLANK"}]}}}));
    let open = graph.symbol_by_name("(").unwrap();
    let symbols: Vec<_> = graph.lexical_rules().map(|(id, _)| id).collect();
    let mut states = vec![graph.start_state()];
    for _ in 0..64 {
        states.push(graph.transition(*states.last().unwrap(), open).unwrap());
        for &symbol in &symbols {
            compare(&graph, &states, symbol);
        }
    }
    assert!(states.windows(2).any(|pair| pair[0] == pair[1]));
    for symbol in symbols {
        compare(&graph, &[], symbol);
    }
    let mut stack = Stack::new(&[]);
    for i in 0..8 {
        assert!(stack.push(StateId::from_index(i)));
    }
    assert!(!stack.push(StateId::from_index(8)));
    assert_eq!(stack.state(8), None);
    stack.overlay_len = 0;
    assert_eq!(stack.top(), None);
    assert_eq!(stack.state(0), None);
}
