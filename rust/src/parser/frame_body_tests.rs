use super::*;

fn value(n: u32) -> Use {
    Use {
        draft: n,
        alias: None,
        field: None,
    }
}
fn drafts(body: &Body) -> Vec<u32> {
    body.iter().map(|value| value.draft).collect()
}

#[test]
fn singleton_bodies_preserve_owned_buffers_order_and_mutable_alias_slots() {
    assert_eq!(size_of::<Body>(), 32);
    assert_eq!(size_of::<Frame>(), 72);
    assert_eq!(size_of::<Draft>(), 40);
    for left in 0..3 {
        for right in 0..3 {
            let make = |shape| match shape {
                0 => Body::Empty,
                1 => Body::One(value(7)),
                _ => Body::Many(vec![value(8), value(9)]),
            };
            let mut body = make(left);
            let other = make(right);
            let expected = body
                .iter()
                .chain(other.iter())
                .map(|v| v.draft)
                .collect::<Vec<_>>();
            body.extend(other);
            assert_eq!(drafts(&body), expected);
            for use_ in &mut body {
                use_.field = Some(FieldId::from_index(0));
            }
            assert!(body.iter().all(|v| v.field == Some(FieldId::from_index(0))));
            assert_eq!(
                body.into_vec()
                    .into_iter()
                    .map(|v| v.draft)
                    .collect::<Vec<_>>(),
                expected
            );
        }
    }
    let mut buffer = Vec::with_capacity(128);
    buffer.push(value(3));
    let pointer = buffer.as_ptr();
    let body = Body::from(buffer);
    assert_eq!(body.heap_len(), 1);
    let restored = body.into_vec();
    assert_eq!(restored.as_ptr(), pointer);
    assert_eq!(restored.capacity(), 128);
    let mut inline = Body::One(value(6));
    inline.extend(Vec::<Use>::with_capacity(128));
    assert!(matches!(inline, Body::One(_)));
    assert_eq!(drafts(&inline), [6]);
    let mut one = Body::One(value(4));
    assert_eq!(one.heap_len(), 0);
    one.push(value(5));
    assert_eq!(drafts(&one), [4, 5]);
}

#[test]
fn deep_empty_many_and_singleton_stacks_are_iterative_and_account_for_inline_payload() {
    let graph =
        CompiledGrammar::compile(br#"{"rules":{"doc":{"type":"STRING","value":"x"}}}"#).unwrap();
    for shape in 0..3 {
        let mut head = Head::new(graph.automaton.start_state(), 0);
        for _ in 0..8192 {
            head.frames.push(Frame {
                symbol: graph.automaton.start_symbol(),
                span: span(0, 0).unwrap(),
                lead: vec![],
                body: match shape {
                    0 => Body::Empty,
                    1 => Body::One(value(0)),
                    _ => Body::Many(vec![value(0)]),
                },
                unproven: false,
            });
        }
        let cloned = head.clone();
        assert_eq!(cloned.frames.len(), 8192);
        assert_eq!(head.clone_work(), cloned.clone_work());
        let heap_uses = head
            .frames
            .iter()
            .map(|frame| frame.body.heap_len())
            .sum::<usize>();
        assert_eq!(heap_uses, if shape == 2 { 8192 } else { 0 });
        assert_eq!(
            head.frames.len() * size_of::<Frame>() + heap_uses * size_of::<Use>(),
            if shape == 2 { 786432 } else { 589824 }
        );
        drop(head);
        drop(cloned);
    }
}
