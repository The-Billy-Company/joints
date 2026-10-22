//! Independent pre-optimization construction oracles.

use super::*;

fn builders() -> Vec<Builder> {
    let sources: &[&[u8]] = &[
        include_bytes!("../../../test/grammar/json.json"),
        br#"{"rules":{"doc":{"type":"REPEAT","content":{"type":"SYMBOL","name":"s"}},"s":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"STRING","value":"a"},{"type":"SYMBOL","name":"s"}]},{"type":"BLANK"},{"type":"STRING","value":"x"}]}},"extras":[]}"#,
        br#"{"rules":{"doc":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"STRING","value":"a"},{"type":"SYMBOL","name":"A"},{"type":"STRING","value":"d"}]},{"type":"SEQ","members":[{"type":"STRING","value":"b"},{"type":"SYMBOL","name":"A"},{"type":"STRING","value":"e"}]},{"type":"SEQ","members":[{"type":"STRING","value":"a"},{"type":"SYMBOL","name":"B"},{"type":"STRING","value":"e"}]},{"type":"SEQ","members":[{"type":"STRING","value":"b"},{"type":"SYMBOL","name":"B"},{"type":"STRING","value":"d"}]}]},"A":{"type":"STRING","value":"c"},"B":{"type":"STRING","value":"c"}}}"#,
        br#"{"rules":{"doc":{"type":"REPEAT","content":{"type":"SYMBOL","name":"word"}},"word":{"type":"PATTERN","value":"[a-z]+"},"comment":{"type":"SEQ","members":[{"type":"STRING","value":"/*"},{"type":"REPEAT","content":{"type":"SYMBOL","name":"word"}},{"type":"STRING","value":"*/"}]}},"extras":[{"type":"SYMBOL","name":"comment"}]}"#,
    ];
    sources
        .iter()
        .map(|source| {
            let UniqueValue(root) = serde_json::from_slice(source).unwrap();
            let mut builder = Builder::read(root, CompileLimits::default()).unwrap();
            builder.lower().unwrap();
            builder
        })
        .collect()
}

#[test]
fn kernel_interning_preserves_states_edges_numbering_and_frozen_lanes() {
    let mut saved_work = 0;
    for builder in builders() {
        let before = builder.work.used.get();
        let base = legacy_lr0(&builder, &SplitPlan::new()).unwrap();
        let original_work = builder.work.used.get() - before;
        builder.work.used.set(before);
        assert_eq!(lr0(&builder, &SplitPlan::new()).unwrap(), base);
        let current_work = builder.work.used.get() - before;
        assert!(current_work <= original_work);
        saved_work += original_work - current_work;

        // Every edge supplies an authored, immutable partition identity. Also
        // exercise extra entry states and cycles arriving on a nonzero lane.
        let mut plan = SplitPlan::new();
        for (from, edges) in base.1.iter().enumerate() {
            for (index, to) in edges.values().enumerate() {
                plan.entry(kernel(&base.0[to.index()]))
                    .or_default()
                    .insert((kernel(&base.0[from]), 0), index % 3 + 1);
            }
        }
        builder.work.used.set(before);
        let reference = legacy_lr0(&builder, &plan).unwrap();
        builder.work.used.set(before);
        assert_eq!(lr0(&builder, &plan).unwrap(), reference);
    }
    assert!(saved_work > 0, "the fixtures must include reused closures");
}

#[test]
fn borrowed_first_unions_preserve_nullable_sets_and_every_work_boundary() {
    for builder in builders() {
        let reference = CompileWork::new(usize::MAX);
        let expected =
            legacy_first_sets(&builder.symbols, &builder.productions, &reference).unwrap();
        let required = reference.used.get();
        // Each original debit must remain: this optimization changes temporary
        // storage, including self-unions, rather than the accepted work ruler.
        for limit in 0..=required {
            let old = CompileWork::new(limit);
            let new = CompileWork::new(limit);
            let old_result = legacy_first_sets(&builder.symbols, &builder.productions, &old);
            let new_result = first_sets(&builder.symbols, &builder.productions, &new);
            assert_eq!(old.used.get(), new.used.get());
            match (old_result, new_result) {
                (Ok(old), Ok(new)) => assert_eq!(old, new),
                (Err(old), Err(new)) => assert_eq!(old.to_string(), new.to_string()),
                (old, new) => panic!("FIRST outcomes differ: old={old:?}, new={new:?}"),
            }
        }
        assert_eq!(
            first_sets(
                &builder.symbols,
                &builder.productions,
                &CompileWork::new(required)
            )
            .unwrap(),
            expected
        );
    }
}

#[test]
fn kernel_interning_keeps_exact_state_item_and_construction_work_ceilings() {
    for mut builder in builders() {
        let before = builder.work.used.get();
        let (states, _, _) = lr0(&builder, &SplitPlan::new()).unwrap();
        let required_work = builder.work.used.get() - before;
        let required_items = states.iter().map(Vec::len).sum();
        let required_states = states.len();
        for (states, items, work, label) in [
            (required_states, required_items, required_work, None),
            (
                required_states - 1,
                required_items,
                required_work,
                Some("LR states"),
            ),
            (
                required_states,
                required_items - 1,
                required_work,
                Some("LR items"),
            ),
            (
                required_states,
                required_items,
                required_work - 1,
                Some("LR construction work"),
            ),
        ] {
            builder.limits.states = states;
            builder.limits.items = items;
            builder.work = CompileWork::new(work);
            match (lr0(&builder, &SplitPlan::new()), label) {
                (Ok(_), None) => {}
                (Err(CompileError::Limit(actual)), Some(expected)) => assert_eq!(actual, expected),
                (actual, expected) => panic!("unexpected boundary: {actual:?}, {expected:?}"),
            }
        }
    }
}

fn legacy_lr0(
    gr: &Builder,
    plan: &SplitPlan,
) -> Result<(Vec<StateItems>, Graph, Vec<usize>), CompileError> {
    let symbols = &gr.symbols;
    let productions = &gr.productions;
    let limits = &gr.limits;
    let rules = by_lhs(symbols, productions);
    let mut work = 0;
    let mut known = BTreeMap::new();
    let mut states = Vec::new();
    let mut marks = Vec::new();
    let mut graph = Vec::new();
    let mut count = 0usize;
    for production in gr.entry_productions() {
        if states.len() >= limits.states {
            return Err(CompileError::Limit("LR states"));
        }
        let initial = closure(
            BTreeSet::from([Item { production, dot: 0 }]),
            productions,
            &rules,
            &gr.cursors,
            &mut work,
            limits,
            &gr.work,
        )?;
        count = count
            .checked_add(initial.len())
            .ok_or(CompileError::Limit("LR items"))?;
        if count > limits.items {
            return Err(CompileError::Limit("LR items"));
        }
        known.insert((initial.clone(), 0usize), StateId::from_index(states.len()));
        states.push(initial);
        marks.push(0usize);
        graph.push(BTreeMap::new());
    }
    let mut at = 0;
    while at < states.len() {
        let mut kernels = BTreeMap::<SymbolId, BTreeSet<Item>>::new();
        for item in &states[at] {
            charge_work(&mut work, 1, &gr.work, "LR construction work")?;
            if let Some(step) = productions[item.production.index()].steps.get(item.dot) {
                kernels
                    .entry(step.symbol)
                    .or_default()
                    .insert(gr.cursors.at(item.production, item.dot + 1));
            }
        }
        for (symbol, kernel) in kernels {
            let target: StateItems = kernel.iter().copied().collect();
            let source = (crate::compiler::kernel(&states[at]), marks[at]);
            let lane = plan
                .get(&target)
                .and_then(|p| p.get(&source))
                .copied()
                .unwrap_or(0);
            let items = closure(
                kernel,
                productions,
                &rules,
                &gr.cursors,
                &mut work,
                limits,
                &gr.work,
            )?;
            let key = (items.clone(), lane);
            let id = if let Some(&id) = known.get(&key) {
                id
            } else {
                if states.len() >= limits.states {
                    return Err(CompileError::Limit("LR states"));
                }
                count += items.len();
                if count > limits.items {
                    return Err(CompileError::Limit("LR items"));
                }
                let id = StateId::from_index(states.len());
                known.insert(key, id);
                states.push(items);
                marks.push(lane);
                graph.push(BTreeMap::new());
                id
            };
            graph[at].insert(symbol, id);
        }
        at += 1;
    }
    Ok((states, graph, marks))
}

fn legacy_first_sets(
    symbols: &[Symbol],
    productions: &[Production],
    shared: &CompileWork,
) -> Result<(Vec<BTreeSet<usize>>, Vec<bool>), CompileError> {
    let mut first = vec![BTreeSet::new(); symbols.len()];
    let mut nullable = vec![false; symbols.len()];
    for (i, s) in symbols.iter().enumerate() {
        if s.lexis.is_some() {
            first[i].insert(i);
        }
    }
    let mut work = 0;
    loop {
        let mut changed = false;
        for p in productions {
            let mut empty = true;
            for step in &p.steps {
                charge_work(
                    &mut work,
                    1 + first[step.symbol.index()].len(),
                    shared,
                    "FIRST work",
                )?;
                let additions = first[step.symbol.index()].clone();
                let dst = &mut first[p.lhs.index()];
                let before = dst.len();
                dst.extend(additions);
                changed |= before != dst.len();
                if !nullable[step.symbol.index()] {
                    empty = false;
                    break;
                }
            }
            if empty && !nullable[p.lhs.index()] {
                nullable[p.lhs.index()] = true;
                changed = true;
            }
        }
        if !changed {
            break;
        }
    }
    Ok((first, nullable))
}
