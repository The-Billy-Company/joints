//! Independent regex semantics where the pinned parser oracle disagrees.
use joints_engine::CompiledGrammar;
use serde_json::json;

#[test]
fn open_repetition_keeps_its_unbounded_tail_and_bounded_forms_keep_their_bounds() {
    let source = b"\\xffc";
    for (pattern, expected) in [
        (r"x[0-9a-fA-F]{2,}", 5),
        (r"x[0-9a-fA-F]{2,5}", 5),
        (r"x[0-9a-fA-F]{2}", 4),
        (r"x[0-9a-fA-F]{2}[0-9a-fA-F]*", 5),
    ] {
        let oracle = pcre2::bytes::Regex::new(&format!(r"\A\\{pattern}")).unwrap();
        assert_eq!(oracle.find(source).unwrap().unwrap().end(), expected);
        let specification = json!({"name":"repetition","extras":[],"rules":{
            "doc":{"type":"REPEAT1","content":{"type":"CHOICE","members":[
                {"type":"SYMBOL","name":"escape"},{"type":"SYMBOL","name":"content"}]}},
            "escape":{"type":"TOKEN","content":{"type":"PREC","value":1,"content":{
                "type":"SEQ","members":[{"type":"STRING","value":"\\"},
                    {"type":"PATTERN","value":pattern}]}}},
            "content":{"type":"PATTERN","value":"[a-z]+"}}});
        let grammar =
            CompiledGrammar::compile(&serde_json::to_vec(&specification).unwrap()).unwrap();
        let tree = grammar.session().parse(source).unwrap();
        let children: Vec<_> = tree.root().unwrap().children().collect();
        assert_eq!(children[0].name(), "escape");
        assert_eq!(children[0].span().range(), 0..expected);
        assert_eq!(children.len(), if expected == source.len() { 1 } else { 2 });
        if expected < source.len() {
            assert_eq!(children[1].name(), "content");
            assert_eq!(children[1].text(), b"c");
        }
    }
    // TS 0.26.11 truncates the first form to its minimum, unlike its expanded
    // equivalent. The four-parser capture and pinned Zig grammar preserve the
    // disagreement in .local/rust-migration/native-phase3/zig-repetition.
}
