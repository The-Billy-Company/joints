use super::*;

#[test]
fn failed_measurement_reclaims_private_effects_then_successfully_reuses_indices() {
    let grammar =
        CompiledGrammar::compile(include_bytes!("../../../test/grammar/json.json")).unwrap();
    let source = b"0";
    let target = br#"[{"a":[1,2,3]},true,null,4,5]"#;
    let options = DocumentOptions {
        policy: DocumentPolicy::Cold,
        ..DocumentOptions::default()
    };
    let mut reference = Document::with_options(Arc::clone(&grammar), source, options).unwrap();
    reference
        .edit(ByteSpan::new(0, 1).unwrap(), target)
        .unwrap();
    let expected_product = reference.product().unwrap();
    let limit = reference.cost().parser_work - 1;
    let options = DocumentOptions {
        limits: ParseLimits {
            steps: limit,
            ..ParseLimits::default()
        },
        ..options
    };
    // First establish that this public limit actually reaches effect creation
    // before Work refuses, using the private inner operation and same cleanup.
    let mut inner = Document::with_options(Arc::clone(&grammar), source, options).unwrap();
    let mark = inner.store.document_mark();
    let before = inner.store.document_mark();
    assert!(matches!(
        inner.edit_inner(ByteSpan::new(0, 1).unwrap(), target),
        Err(DocumentError::Parse(Error::LimitExceeded(
            crate::Resource::Work
        )))
    ));
    assert_ne!(inner.store.document_mark(), before);
    assert!(inner.store.discard_document_suffix(mark).unwrap() > 0);
    assert_eq!(inner.store.document_mark(), before);
    // The public wrapper must preserve the published version and old handles.
    let mut document = Document::with_options(Arc::clone(&grammar), source, options).unwrap();
    let previous = Arc::clone(document.snapshot());
    let cost = document.cost();
    let product = document.product().unwrap();
    let old_effect = document.sequence.product();
    let mark = document.store.document_mark();
    assert!(matches!(
        document.edit(ByteSpan::new(0, 1).unwrap(), target),
        Err(DocumentError::Parse(Error::LimitExceeded(
            crate::Resource::Work
        )))
    ));
    assert_eq!(document.store.document_mark(), mark);
    assert!(Arc::ptr_eq(&previous, document.snapshot()));
    assert_eq!(document.source(), source);
    assert_eq!(document.product().unwrap(), product);
    assert_eq!(document.cost(), cost);
    assert_eq!(document.store.describe(old_effect).unwrap(), product);
    // Optional parser proof caches can make a retry cheaper. Index reuse must
    // still produce the independently computed canonical result.
    let mut completed = false;
    for _ in 0..8 {
        if document.edit(ByteSpan::new(0, 1).unwrap(), target).is_ok() {
            completed = true;
            break;
        }
        assert!(Arc::ptr_eq(&previous, document.snapshot()));
        assert_eq!(document.product().unwrap(), product);
        assert_eq!(document.cost(), cost);
    }
    assert!(completed);
    assert_eq!(document.source(), target);
    assert_eq!(document.product().unwrap(), expected_product);
    assert_eq!(document.store.describe(old_effect).unwrap(), product);
    assert_eq!(previous.source(), source);
    assert_eq!(previous.root().unwrap().text(), source);
}
