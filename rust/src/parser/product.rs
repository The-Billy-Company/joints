//! Replay a concrete selected trace before crossing the effect interning boundary.
//!
//! Unlike a move-range yield, a full actual trace starts on the grammar's
//! concrete start stack. Proving that path lets us retain only its final grounded
//! run instead of interning every primitive and intermediate prefix. Opaque run
//! allocation order and cache warmup are deliberately not reproduced.

use super::*;

pub(super) fn actual(
    trace: &[Move],
    graph: &Automaton,
    store: &mut EffectStore,
) -> Result<Option<Effect>, EffectError> {
    if trace.is_empty() {
        return Ok(Some(Effect::IDENTITY));
    }
    let start = graph.start_state();
    let mut state = start;
    // Each entry retains the state immediately beneath its symbol. Together
    // with `state`, these are the exact concrete stack and all its LR links.
    let mut stack: Vec<(StateId, SymbolId)> = Vec::new();
    for movement in trace {
        match *movement {
            Move::Shift { from, symbol } => {
                if from != state || symbol.index() >= graph.symbol_count() {
                    return Ok(None);
                }
                let Some(next) = graph.transition(from, symbol) else {
                    return Ok(None);
                };
                stack.push((from, symbol));
                state = next;
            }
            Move::Reduce { under, production } => {
                if under.index() >= graph.state_count()
                    || production.index() >= graph.production_count()
                {
                    return Ok(None);
                }
                let rule = graph.production(production);
                let Some(kept) = stack.len().checked_sub(rule.steps.len()) else {
                    return Ok(None);
                };
                let floor = if rule.steps.is_empty() {
                    state
                } else {
                    stack[kept].0
                };
                if floor != under
                    || !stack[kept..]
                        .iter()
                        .zip(&rule.steps)
                        .all(|(&(_, symbol), step)| symbol == step.symbol)
                {
                    return Ok(None);
                }
                // The retained LR links and matching RHS prove reduce's entry
                // path and every singleton claim. Prove the new goto too before
                // using it as the next move's concrete entry.
                let Some(next) = graph.transition(under, rule.lhs) else {
                    return Ok(None);
                };
                stack.truncate(kept);
                stack.push((under, rule.lhs));
                state = next;
            }
            // A hole can reset the concrete parser stack. Original folding must
            // still validate every later primitive even after absorbing Zero.
            Move::Hole => return Ok(None),
        }
    }
    // No store mutation occurs before the complete proof, so every failed proof
    // can use the original fold with its original error and Zero behavior.
    let push = stack.into_iter().map(|(_, symbol)| symbol).collect();
    store.exploratory(start, Vec::new(), push).map(Some)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fold(trace: &[Move], store: &mut EffectStore) -> Result<Effect, EffectError> {
        let mut product = Effect::IDENTITY;
        for movement in trace {
            let effect = match *movement {
                Move::Shift { from, symbol } => store.shift(from, symbol)?,
                Move::Reduce { under, production } => store.reduce(under, production)?,
                Move::Hole => Effect::ZERO,
            };
            product = store.compose(product, effect)?;
        }
        Ok(product)
    }

    fn compare(session: &ParseSession, must_fallback: bool) {
        let graph = &session.grammar.automaton;
        for prepopulate in [false, true] {
            let mut direct = session.grammar.effect_store();
            let mut original = session.grammar.effect_store();
            if prepopulate {
                for state in 0..graph.state_count().min(4) {
                    for symbol in 0..graph.symbol_count().min(4) {
                        direct
                            .shift(StateId::from_index(state), SymbolId::from_index(symbol))
                            .unwrap();
                        original
                            .shift(StateId::from_index(state), SymbolId::from_index(symbol))
                            .unwrap();
                    }
                }
            }
            let before = direct.document_mark();
            let proof = actual(&session.trace, graph, &mut direct).unwrap();
            if must_fallback {
                assert!(proof.is_none(), "trace={:?}", session.trace);
                assert_eq!(before, direct.document_mark(), "failed proof changed store");
            } else {
                assert!(proof.is_some(), "trace={:?}", session.trace);
            }
            let got = session.product(&mut direct);
            let expected = fold(&session.trace, &mut original);
            assert_eq!(
                got.as_ref().map(|&effect| direct.describe(effect)),
                expected.as_ref().map(|&effect| original.describe(effect)),
                "trace={:?}",
                session.trace,
            );
            if let Ok(got) = got {
                assert_eq!(
                    fold(&session.trace, &mut direct),
                    Ok(got),
                    "canonical final handle"
                );
                assert_eq!(
                    session.product(&mut direct),
                    Ok(got),
                    "repeated product handle"
                );
                if let Some(proved) = proof {
                    assert_eq!(got, proved);
                    assert!(direct.grounded(got).unwrap());
                }
            }
        }
    }

    #[test]
    fn direct_actual_products_match_original_selected_partial_and_empty_traces() {
        let grammar =
            CompiledGrammar::compile(include_bytes!("../../../test/grammar/json.json")).unwrap();
        let mut session = grammar.session();
        for source in [
            b"{\"x\":[1,{\"y\":false}]}".as_slice(),
            b"[1",
            b"[1,@",
            b"",
            b"[]",
        ] {
            session.parse_partial(source).unwrap();
            compare(&session, false);
        }
        let grammar = CompiledGrammar::compile(br#"{"name":"empty_product","rules":{"doc":{"type":"CHOICE","members":[{"type":"BLANK"},{"type":"STRING","value":"x"}]}},"extras":[]}"#).unwrap();
        let mut session = grammar.session();
        session.parse(b"").unwrap();
        assert!(
            matches!(session.trace.first(), Some(Move::Reduce { production, .. }) if grammar.automaton.production(*production).steps.is_empty())
        );
        compare(&session, false);
    }

    #[test]
    fn direct_actual_products_preserve_selected_glr_extras_supplies_and_hole_fallbacks() {
        let grammar = CompiledGrammar::compile(br#"{"name":"product_branch","rules":{
          "doc":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"SYMBOL","name":"a"},{"type":"STRING","value":"y"}]},{"type":"SEQ","members":[{"type":"SYMBOL","name":"b"},{"type":"STRING","value":"y"},{"type":"STRING","value":"z"}]}]},
          "a":{"type":"SYMBOL","name":"item"},"b":{"type":"SYMBOL","name":"item"},"item":{"type":"STRING","value":"x"},"comment":{"type":"PATTERN","value":"/\\*[^*]*\\*/"}},"conflicts":[["a","b"]],"extras":[{"type":"SYMBOL","name":"comment"}]}"#).unwrap();
        let mut session = grammar.session();
        for source in [b"xy".as_slice(), b"x/*note*/yz", b"x/*note*/y@"] {
            session.parse_partial(source).unwrap();
            compare(&session, false);
        }
        let grammar = CompiledGrammar::compile(br#"{"name":"product_rule_extra","rules":{
          "doc":{"type":"SEQ","members":[{"type":"STRING","value":"x"},{"type":"STRING","value":"y"}]},
          "note":{"type":"SEQ","members":[{"type":"STRING","value":"<"},{"type":"SYMBOL","name":"_body"},{"type":"STRING","value":">"}]},
          "_body":{"type":"CHOICE","members":[{"type":"PATTERN","value":"[a-z]+"},{"type":"SEQ","members":[{"type":"STRING","value":"("},{"type":"SYMBOL","name":"_body"},{"type":"STRING","value":")"}]}]}},
          "extras":[{"type":"PATTERN","value":"[ \\t\\n]+"},{"type":"SYMBOL","name":"note"}]}"#).unwrap();
        let mut session = grammar.session();
        for source in [b"<(a)>x<b>y<c>".as_slice(), b"<(a)", b"x<(a)>@"] {
            session.parse_partial(source).unwrap();
            compare(&session, false);
        }
        let grammar =
            CompiledGrammar::compile(include_bytes!("../../../test/grammar/json.json")).unwrap();
        let mut supplied = false;
        let mut holes = false;
        for policy in [
            Recovery::None,
            Recovery::Keep,
            Recovery::Fell,
            Recovery::Relent,
        ] {
            let mut session = grammar.session();
            session.set_trace_enabled(true);
            session.set_recovery(policy);
            session.set_supply(Supply::UniqueLiteral);
            // These frozen recovery witnesses establish a supplied colon and
            // a deleted invalid byte, rather than depending on which repair an
            // ordinary printable stray byte happens to admit.
            for source in [
                include_bytes!(
                    "../../../test/migration/reference/inputs/fixtures/json-missing-colon.json"
                )
                .as_slice(),
                include_bytes!(
                    "../../../test/migration/reference/inputs/fixtures/json-invalid-byte.json"
                )
                .as_slice(),
            ] {
                session.parse_partial(source).unwrap();
                let hole = session.trace.contains(&Move::Hole);
                holes |= hole;
                supplied |= session
                    .selected_tokens()
                    .unwrap()
                    .iter()
                    .any(|token| token.supplied);
                compare(&session, hole);
            }
        }
        assert!(
            supplied,
            "frozen missing-colon witness did not supply a literal"
        );
        assert!(holes, "frozen invalid-byte witness did not record a hole");
    }

    #[test]
    fn altered_traces_fall_back_without_mutation_and_keep_original_errors_and_zero() {
        let grammar =
            CompiledGrammar::compile(include_bytes!("../../../test/grammar/json.json")).unwrap();
        let mut session = grammar.session();
        session.parse(b"[1]").unwrap();
        let valid = session.trace.clone();
        let graph = &grammar.automaton;
        let invalid_state = StateId::from_index(graph.state_count());
        let invalid_symbol = SymbolId::from_index(graph.symbol_count());
        let invalid_production = ProductionId::from_index(graph.production_count());
        let reduction = valid
            .iter()
            .copied()
            .find(|movement| {
                matches!(movement,
            Move::Reduce { production, .. } if !graph.production(*production).steps.is_empty())
            })
            .unwrap();
        let no_shift = (0..graph.symbol_count())
            .map(SymbolId::from_index)
            .find(|&symbol| graph.transition(graph.start_state(), symbol).is_none())
            .unwrap();
        let Move::Shift { from, symbol } = valid[0] else {
            panic!("expected initial shift")
        };
        let other_state = (0..graph.state_count())
            .map(StateId::from_index)
            .find(|&state| state != from)
            .unwrap();
        for trace in [
            vec![Move::Shift {
                from: invalid_state,
                symbol,
            }],
            vec![Move::Shift {
                from,
                symbol: invalid_symbol,
            }],
            vec![Move::Shift {
                from: other_state,
                symbol,
            }],
            vec![Move::Shift {
                from,
                symbol: no_shift,
            }],
            vec![reduction],
            vec![Move::Reduce {
                under: invalid_state,
                production: invalid_production,
            }],
            vec![Move::Reduce {
                under: from,
                production: invalid_production,
            }],
            vec![Move::Hole],
            vec![
                Move::Hole,
                Move::Reduce {
                    under: invalid_state,
                    production: invalid_production,
                },
            ],
            vec![valid[0], valid[0]],
        ] {
            session.trace = trace;
            compare(&session, true);
        }
        // Interior altered state, symbol and reduction-floor receipts must also
        // abandon the proof before any primitive or prefix run is interned.
        for index in 0..valid.len() {
            let replacement = match valid[index] {
                Move::Shift { from, .. } => Move::Shift {
                    from,
                    symbol: (0..graph.symbol_count())
                        .map(SymbolId::from_index)
                        .find(|&symbol| graph.transition(from, symbol).is_none())
                        .unwrap(),
                },
                Move::Reduce { under, production } => Move::Reduce {
                    under: (0..graph.state_count())
                        .map(StateId::from_index)
                        .find(|&state| state != under)
                        .unwrap(),
                    production,
                },
                Move::Hole => unreachable!(),
            };
            session.trace = valid.clone();
            session.trace[index] = replacement;
            compare(&session, true);
        }
        // Equal pop lengths do not establish the required RHS symbol guards.
        let (index, under, production) = valid
            .iter()
            .enumerate()
            .find_map(|(index, movement)| match *movement {
                Move::Reduce { under, production }
                    if graph.production(production).steps.len() == 1 =>
                {
                    Some((index, under, production))
                }
                _ => None,
            })
            .unwrap();
        let other = (0..graph.production_count())
            .map(ProductionId::from_index)
            .find(|&candidate| {
                let other = graph.production(candidate);
                other.steps.len() == 1
                    && other.steps[0].symbol != graph.production(production).steps[0].symbol
            })
            .unwrap();
        session.trace = valid;
        session.trace[index] = Move::Reduce {
            under,
            production: other,
        };
        compare(&session, true);
    }
}
