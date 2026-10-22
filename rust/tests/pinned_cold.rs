//! Explicit gates over the already pinned working population. These are not
//! holdouts: each specimen's own named claims, rather than an acceptance rate,
//! determine its result. Run with `--ignored --nocapture`.

#![forbid(unsafe_code)]

use joints_engine::{CompiledGrammar, Node, Recovery, RepairKind, Stop, Supply, TreeSnapshot};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    path::{Path, PathBuf},
    sync::Arc,
};

const SPECIMENS: &[&str] = &[
    "bash/file-descriptor.sh",
    "bash/regex-in-test-command.sh",
    "cpp/raw-string-delimiter.cpp",
    "elixir/charlist-heredoc.ex",
    "elixir/do-block-as-keyword-argument.ex",
    "elixir/do-block-on-inner-call.ex",
    "elixir/do-block-without-inner-call.ex",
    "elixir/escaped-close.ex",
    "elixir/hash-is-not-interpolation.ex",
    "elixir/heredoc-quote-inside.ex",
    "elixir/newline-before-operator.ex",
    "elixir/quoted-atom.ex",
    "elixir/sigil-delimiters.ex",
    "elixir/sigil-uppercase-holds-its-braces.ex",
    "go/call-with-two-arguments.go",
    "go/conversion-without-a-selector.go",
    "go/qualified-type-in-var.go",
    "go/selector-field.go",
    "haskell/cpp-directive.hs",
    "html/erroneous-end-tag.html",
    "javascript/escape-sequence.js",
    "javascript/regex-pattern.js",
    "julia/command.jl",
    "julia/interpolation.jl",
    "julia/nested-interpolation.jl",
    "julia/raw-string.jl",
    "julia/triple-quote.jl",
    "kotlin/embedded-quote.kt",
    "kotlin/escaped-quote.kt",
    "kotlin/greedy-close.kt",
    "kotlin/interpolation.kt",
    "kotlin/nested-interpolation.kt",
    "kotlin/unterminated.kt",
    "latex/iffalse-fi.tex",
    "latex/verbatim-body.tex",
    "ocaml/nested-comment.ml",
    "php/dollar-digit-is-text.php",
    "php/double-quoted-string.php",
    "php/execution-string.php",
    "php/heredoc-still-blind.php",
    "php/subscript-after-variable.php",
    "php/text-swallows-remainder.php",
    "python/call-that-is-not-print.py",
    "python/escape-interpolation.py",
    "python/print-as-statement.py",
    "python/print-in-expression-position.py",
    "python/print-with-two-arguments.py",
    "ruby/hash-key-symbol.rb",
    "rust/raw-string-content.rs",
    "rust/string-close.rs",
    "scala/nested-comment.scala",
    "scala/offside-braceless.scala",
    "scala/offside-through-comment.scala",
    "swift/catch-keyword.swift",
    "swift/default-keyword.swift",
    "swift/interpolation.swift",
    "swift/multiline-comment.swift",
    "swift/nested-comment.swift",
    "swift/nested-interpolation.swift",
    "swift/raw-delimiter-in-body.swift",
    "swift/raw-string.swift",
    "toml/comment-after-pair.toml",
    "toml/pair-without-comment.toml",
    "typescript/escape-sequence.ts",
    "typescript/regex-pattern.ts",
    "yaml/comment.yml",
];

fn root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .to_owned()
}
fn nodes(tree: &TreeSnapshot) -> Vec<Node<'_>> {
    let mut pending: Vec<_> = tree.roots().collect();
    let mut out = vec![];
    while let Some(node) = pending.pop() {
        pending.extend(node.children());
        out.push(node);
    }
    out
}
fn enumerate(dir: &Path, base: &Path, out: &mut BTreeSet<String>) {
    for entry in fs::read_dir(dir).unwrap() {
        let path = entry.unwrap().path();
        if path.is_dir() {
            enumerate(&path, base, out);
        } else if let Some(name) = path
            .strip_prefix(base)
            .unwrap()
            .to_str()
            .unwrap()
            .strip_suffix(".expect")
        {
            assert!(out.insert(name.to_owned()));
        }
    }
}
fn claims(path: &Path) -> Vec<(usize, String)> {
    let text = fs::read_to_string(path).unwrap();
    let claims: Vec<_> = text
        .lines()
        .enumerate()
        .filter_map(|(line, s)| {
            let s = s.split('#').next().unwrap().trim();
            (!s.is_empty()).then(|| (line + 1, s.to_owned()))
        })
        .collect();
    assert!(!claims.is_empty(), "{} contains no claims", path.display());
    claims
}
fn judge(tree: &TreeSnapshot, line: usize, claim: &str) -> Value {
    let words: Vec<_> = claim.split_whitespace().collect();
    let all = nodes(tree);
    let count = |s: &str| {
        s.parse::<usize>()
            .unwrap_or_else(|_| panic!("invalid count in claim {claim}"))
    };
    let (holds, actual) = match words.as_slice() {
        ["roots", n] => (tree.roots().len() == count(n), json!(tree.roots().len())),
        ["mends", n] => (tree.mends() == count(n), json!(tree.mends())),
        ["holds", name] => (
            all.iter().any(|n| n.name() == *name),
            json!(all.iter().filter(|n| n.name() == *name).count()),
        ),
        ["lacks", name] => (
            !all.iter().any(|n| n.name() == *name),
            json!(all.iter().filter(|n| n.name() == *name).count()),
        ),
        ["spans", name, start, end] => {
            let spans: Vec<_> = all
                .iter()
                .filter(|n| n.name() == *name)
                .map(|n| (n.span().start(), n.span().end()))
                .collect();
            (spans.contains(&(count(start), count(end))), json!(spans))
        }
        _ => panic!("unknown or malformed claim on line {line}: {claim}"),
    };
    json!({"line":line,"claim":claim,"holds":holds,"actual":actual})
}

fn shape(node: Node<'_>) -> Value {
    let mut value = json!({"name":node.name(),"named":node.is_named(),"start":node.span().start(),
        "end":node.span().end(),"kids":node.children().map(shape).collect::<Vec<_>>()});
    if let Some(field) = node.field() {
        value["field"] = json!(field);
    }
    value
}
fn evidence(tree: &TreeSnapshot) -> Value {
    let stop = match tree.stop() {
        Stop::Accepted => json!({"kind":"accepted"}),
        Stop::Truncated => json!({"kind":"truncated"}),
        Stop::Stray { at } => json!({"kind":"stray","at":at}),
        Stop::Unexpected { at, .. } => {
            json!({"kind":"unexpected","at":at,"symbol":tree.stop_symbol().unwrap()})
        }
    };
    let scars:Vec<_>=tree.repairs().iter().map(|repair| {
        let mut scar=json!({"at":repair.span.start(),"over":repair.span.end(),"felled":matches!(repair.kind,RepairKind::Deleted {felled:true}),"heads":repair.heads,"shifted":repair.shifted});
        if let Some(gave)=tree.repair_symbol(repair) {scar["gave"]=json!(gave);}scar
    }).collect();
    json!({"stop":stop,"roots":tree.roots().len(),"mends":tree.mends(),"skipped":tree.skipped(),"supplied":tree.supplied(),"spurned":tree.spurned(),"scars":scars,"tree":tree.roots().map(shape).collect::<Vec<_>>()})
}
fn sha256(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .fold(String::new(), |mut text, byte| {
            use std::fmt::Write as _;
            write!(text, "{byte:02x}").expect("writing to a String cannot fail");
            text
        })
}
fn relative(path: &str) -> &Path {
    let path = Path::new(path);
    assert!(
        path.components()
            .all(|c| matches!(c, std::path::Component::Normal(_))),
        "baseline path must stay relative: {}",
        path.display()
    );
    path
}
fn baseline(root: &Path, roster: &BTreeSet<String>) -> BTreeMap<String, (Value, Value)> {
    let bundle = root.join("test/migration/specimens");
    let bytes = fs::read(bundle.join("manifest.json")).unwrap();
    let manifest: Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(manifest["schema"], 1);
    assert_eq!(
        manifest["reference_binary_sha256"],
        "709bf8c0ce4a3c9ad5deb400e42d5025439e76c45bbcfaaf0959be31cff768ec"
    );
    // The portable JSON25 export has a different manifest from the full36
    // sealed capture used to execute this population. Both identify this binary.
    assert_eq!(
        manifest["reference_manifest_sha256"],
        "4be57bd42e493b13b6b017d75e0361a86fa2b0ad5a1a78ebc1b76e9c02d32831",
        "sealed full36 reference lineage drift"
    );
    let portable: Value = serde_json::from_slice(
        &fs::read(root.join("test/migration/reference/manifest.json")).unwrap(),
    )
    .unwrap();
    assert_eq!(
        portable["binary"]["sha256"], manifest["reference_binary_sha256"],
        "portable/reference binary lineage drift"
    );
    let cases = manifest["cases"].as_array().unwrap();
    assert_eq!(cases.len(), 66);
    let mut checked = BTreeMap::new();
    for case in cases {
        let name = case["case"].as_str().unwrap();
        assert!(roster.contains(name), "unknown baseline case {name}");
        let language = name.split('/').next().unwrap();
        let inputs = case["inputs"].as_object().unwrap();
        for required in [
            format!("research/joinery/specimen/{name}"),
            format!("research/joinery/specimen/{name}.expect"),
            format!("upstream/grammars/{language}.json"),
        ] {
            assert!(
                inputs.contains_key(&required),
                "{name}: absent input attestation {required}"
            );
        }
        for (path, expected) in inputs {
            assert_eq!(
                sha256(&fs::read(root.join(relative(path))).unwrap()),
                expected.as_str().unwrap(),
                "{name}: input drift {path}"
            );
        }
        let output_path = case["output"].as_str().unwrap();
        let output = fs::read(bundle.join(relative(output_path))).unwrap();
        assert_eq!(
            sha256(&output),
            case["output_sha256"].as_str().unwrap(),
            "{name}: output drift"
        );
        let output: Value = serde_json::from_slice(&output).unwrap();
        assert!(
            output["tree"].is_array(),
            "{name}: malformed reference tree"
        );
        assert!(output["stop"].is_object(), "{name}: missing reference stop");
        let assertions = claims(&root.join(format!("research/joinery/specimen/{name}.expect")));
        let recorded = case["claims"].as_array().unwrap();
        assert_eq!(
            recorded.len(),
            assertions.len(),
            "{name}: claim count drift"
        );
        for ((line, text), claim) in assertions.iter().zip(recorded) {
            assert_eq!(
                usize::try_from(claim["line"].as_u64().unwrap()).expect("fixture count fits usize"),
                *line,
                "{name}: claim line drift"
            );
            assert_eq!(
                claim["claim"].as_str().unwrap(),
                text,
                "{name}: claim text drift"
            );
            assert!(claim["holds"].is_boolean());
        }
        assert!(case["strict"].is_boolean());
        assert!(
            checked
                .insert(name.into(), (case.clone(), output))
                .is_none(),
            "duplicate baseline case {name}"
        );
    }
    assert_eq!(checked.keys().cloned().collect::<BTreeSet<_>>(), *roster);
    checked
}

/// An adjudication retains the sealed result and permits one fully specified
/// replacement tree, backed by independent raw parser evidence.
fn adjudications(
    root: &Path,
    baseline: &BTreeMap<String, (Value, Value)>,
) -> BTreeMap<String, (Value, Value)> {
    let bundle = root.join("test/migration/specimens");
    let manifest: Value =
        serde_json::from_slice(&fs::read(bundle.join("adjudications/manifest.json")).unwrap())
            .unwrap();
    assert_eq!(manifest["schema"], 1);
    assert_eq!(
        manifest["baseline_manifest_sha256"],
        sha256(&fs::read(bundle.join("manifest.json")).unwrap()),
        "independent adjudication baseline lineage drift"
    );
    let mut checked = BTreeMap::new();
    for correction in manifest["cases"].as_array().unwrap() {
        let name = correction["case"].as_str().unwrap();
        let (case, output) = baseline.get(name).expect("unknown adjudicated specimen");
        assert_eq!(correction["classification"], "independent_correction");
        assert!(!correction["rationale"].as_str().unwrap().is_empty());
        assert_eq!(
            correction["inputs"], case["inputs"],
            "{name}: adjudication input drift"
        );
        assert_eq!(correction["baseline_output_sha256"], case["output_sha256"]);
        let oracle = &correction["oracle"];
        assert_eq!(oracle["implementation"], "tree-sitter");
        assert_eq!(oracle["version"], "0.26.11");
        assert_eq!(oracle["errors"], 0);
        assert_eq!(oracle["stable"], true);
        assert!(oracle["nodes"].as_u64().unwrap() > 0);
        assert_eq!(oracle["binary_sha256"].as_str().unwrap().len(), 64);
        let proofs = oracle["proofs"].as_object().unwrap();
        assert!(!proofs.is_empty(), "{name}: absent independent raw proof");
        for (path, expected) in proofs {
            let bytes = fs::read(bundle.join(relative(path))).unwrap();
            assert!(!bytes.is_empty(), "{name}: empty raw proof {path}");
            assert_eq!(
                sha256(&bytes),
                expected.as_str().unwrap(),
                "{name}: proof drift {path}"
            );
        }
        let bytes = fs::read(bundle.join(relative(correction["tree"].as_str().unwrap()))).unwrap();
        assert_eq!(sha256(&bytes), correction["tree_sha256"].as_str().unwrap());
        let expected: Value = serde_json::from_slice(&bytes).unwrap();
        let mut patched = output["tree"].clone();
        let changes = correction["changes"].as_array().unwrap();
        assert!(!changes.is_empty(), "{name}: unspecified tree correction");
        let mut pointers = BTreeSet::new();
        for change in changes {
            let pointer = change["pointer"].as_str().unwrap();
            assert!(pointers.insert(pointer), "{name}: duplicate tree change");
            let target = patched
                .pointer_mut(pointer)
                .expect("invalid tree correction pointer");
            assert_eq!(*target, change["before"], "{name}: original tree drift");
            assert_ne!(change["before"], change["after"]);
            *target = change["after"].clone();
        }
        assert_eq!(
            patched, expected,
            "{name}: correction differs from exact specified changes"
        );
        assert_ne!(output["tree"], expected);
        assert!(
            checked
                .insert(name.into(), (correction.clone(), expected))
                .is_none()
        );
    }
    checked
}

#[test]
fn sealed_specimen_evidence_preserves_all_cases_and_known_aspirations() {
    let roster = SPECIMENS.iter().map(|s| s.to_string()).collect();
    let cases = baseline(&root(), &roster);
    let corrections = adjudications(&root(), &cases);
    assert_eq!(
        corrections.keys().map(String::as_str).collect::<Vec<_>>(),
        vec![
            "julia/command.jl",
            "julia/interpolation.jl",
            "julia/nested-interpolation.jl",
            "julia/raw-string.jl",
            "julia/triple-quote.jl",
            "swift/default-keyword.swift"
        ]
    );
    let aspirational: BTreeSet<_> = cases
        .iter()
        .filter(|(_, (case, _))| {
            case["claims"]
                .as_array()
                .unwrap()
                .iter()
                .any(|c| c["holds"] == false)
        })
        .map(|(name, _)| name.as_str())
        .collect();
    assert_eq!(
        aspirational,
        BTreeSet::from([
            "bash/regex-in-test-command.sh",
            "html/erroneous-end-tag.html",
            "kotlin/greedy-close.kt",
            "kotlin/unterminated.kt",
            "php/heredoc-still-blind.php"
        ])
    );
}

#[test]
#[ignore = "explicit 66-specimen working-population gate; emits per-case evidence"]
fn pinned_specimens_have_their_declared_trees() {
    assert_eq!(SPECIMENS.len(), 66);
    let root = root();
    let base = root.join("research/joinery/specimen");
    let mut actual = BTreeSet::new();
    enumerate(&base, &base, &mut actual);
    let expected: BTreeSet<_> = SPECIMENS.iter().map(|s| s.to_string()).collect();
    assert_eq!(expected.len(), 66, "duplicate specimen in expected roster");
    assert_eq!(
        actual, expected,
        "working specimen roster drifted; review explicitly"
    );
    let baseline = baseline(&root, &expected);
    let corrections = adjudications(&root, &baseline);
    let mut grammars: BTreeMap<String, Result<Arc<CompiledGrammar>, String>> = BTreeMap::new();
    let mut report = vec![];
    let mut failures = vec![];
    let mut judged = 0;
    for &name in SPECIMENS {
        let language = name.split('/').next().unwrap();
        let source = fs::read(base.join(name)).unwrap();
        let assertions = claims(&base.join(format!("{name}.expect")));
        let (reference, reference_output) = &baseline[name];
        let grammar = grammars.entry(language.into()).or_insert_with(|| {
            CompiledGrammar::compile(
                &fs::read(root.join(format!("upstream/grammars/{language}.json"))).unwrap(),
            )
            .map_err(|e| e.to_string())
        });
        let result = match grammar {
            Ok(grammar) => {
                let blind: Vec<_> = grammar.unsupported_externals().collect();
                let mut session = grammar.session();
                session.set_recovery(Recovery::Fell);
                session.set_supply(Supply::UniqueLiteral);
                match session.parse_partial(&source) {
                    Ok(tree) => {
                        judged += 1;
                        let mut checks: Vec<_> = assertions
                            .iter()
                            .map(|(line, claim)| judge(&tree, *line, claim))
                            .collect();
                        let sound = tree.survey().is_sound();
                        for (check, prior) in checks
                            .iter_mut()
                            .zip(reference["claims"].as_array().unwrap())
                        {
                            let before = prior["holds"].as_bool().unwrap();
                            let now = check["holds"].as_bool().unwrap();
                            check["baseline_holds"] = json!(before);
                            check["comparison"] = json!(match (before, now) {
                                (true, false) => "regressed",
                                (false, true) => "improved",
                                (false, false) => "aspirational_failure",
                                (true, true) => "held",
                            });
                        }
                        let failed: Vec<_> = checks
                            .iter()
                            .filter(|c| c["comparison"] == "regressed")
                            .map(|c| c["claim"].as_str().unwrap())
                            .collect();
                        if !sound || !failed.is_empty() {
                            failures.push(format!(
                                "{name}: sound={sound}; failed {}",
                                failed.join("; ")
                            ));
                        }
                        let native = evidence(&tree);
                        let strict_reference = reference["strict"].as_bool().unwrap();
                        let tree_equal = native["tree"] == reference_output["tree"];
                        let correction = corrections.get(name);
                        let corrected_equal =
                            correction.map(|(_, expected)| native["tree"] == *expected);
                        let expected_equal = corrected_equal.unwrap_or(tree_equal);
                        let mut prior_stop = reference_output["stop"].clone();
                        prior_stop.as_object_mut().unwrap().remove("state");
                        let evidence_equal = native["stop"] == prior_stop
                            && ["roots", "mends", "skipped", "supplied", "spurned", "scars"]
                                .iter()
                                .all(|key| native[*key] == reference_output[*key]);
                        if strict_reference && (!expected_equal || !tree.confidence().is_strict()) {
                            failures.push(format!("{name}: strict reference syntax differs (names, fields, spans or shape)"));
                        }
                        if !strict_reference && !evidence_equal {
                            failures.push(format!("{name}: refusal stop/repair evidence differs"));
                        }
                        json!({"case":name,"status":"parsed","strict":tree.confidence().is_strict(),"baseline_strict":strict_reference,"semantic_tree_equal":tree_equal,"independent_tree_equal":corrected_equal,"tree_comparison":if correction.is_some() {"independent_correction"} else {"sealed_reference"},"adjudication":correction.map(|(record,_)|record),"stop_and_repairs_equal":evidence_equal,"sound":sound,"nodes":tree.survey().walked,"unsupported_externals":blind,"claims":checks,"native":native})
                    }
                    Err(error) => {
                        failures.push(format!("{name}: parse error {error}"));
                        json!({"case":name,"status":"parse_error","error":error.to_string(),"unsupported_externals":blind,"claim_count":assertions.len()})
                    }
                }
            }
            Err(error) => {
                failures.push(format!("{name}: compile error {error}"));
                json!({"case":name,"status":"compile_error","error":error,"claim_count":assertions.len()})
            }
        };
        if let Some(error) = result.get("error") {
            eprintln!("{name}: {}: {error}", result["status"]);
        } else {
            eprintln!("{name}: {}", result["status"]);
        }
        report.push(result);
    }
    assert_eq!(report.len(), 66);
    assert!(judged > 0, "no specimen reached the runtime");
    let evidence = root.join(".local/rust-migration/native-specimens.json");
    fs::create_dir_all(evidence.parent().unwrap()).unwrap();
    fs::write(&evidence,serde_json::to_vec_pretty(&json!({"population":"pinned working specimens","baseline_manifest_sha256":sha256(&fs::read(root.join("test/migration/specimens/manifest.json")).unwrap()),"expected_cases":66,"judged_cases":judged,"cases":report})).unwrap()).unwrap();
    eprintln!("per-case evidence: {}", evidence.display());
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

#[test]
#[ignore = "explicit pinned Go ledger semantic gate"]
fn pinned_go_ledger_retains_calls_comments_and_declarations() {
    let root = root();
    let grammar =
        CompiledGrammar::compile(&fs::read(root.join("upstream/grammars/go.json")).unwrap())
            .unwrap();
    let source = fs::read(root.join("research/joinery/corpus/ledger.go")).unwrap();
    let mut session = grammar.session();
    let tree = session.parse(&source).unwrap();
    assert!(tree.survey().is_sound());
    assert_eq!(tree.root().unwrap().name(), "source_file");
    assert_eq!(tree.root().unwrap().span().range(), 0..source.len());
    let all = nodes(&tree);
    let count = |name: &str| all.iter().filter(|n| n.name() == name).count();
    assert_eq!(count("method_declaration"), 2);
    assert_eq!(count("function_declaration"), 2);
    assert_eq!(count("type_declaration"), 1);
    assert_eq!(count("raw_string_literal"), 1);
    for text in [
        b"fmt.Print(banner)".as_slice(),
        b"fmt.Printf(\"total=%d\\n\", l.Total())",
        b"l.Total()",
    ] {
        assert!(
            all.iter()
                .any(|n| n.name() == "call_expression" && n.text() == text),
            "call lost: {}",
            String::from_utf8_lossy(text)
        );
    }
    assert!(
        all.iter()
            .any(|n| n.name() == "comment" && n.is_extra() && n.text().starts_with(b"/*"))
    );
    assert!(
        all.iter()
            .filter(|n| n.name() == "selector_expression")
            .all(|n| n
                .child_by_field("field")
                .is_some_and(|f| f.name() == "field_identifier"))
    );
    assert!(
        !session
            .product(&mut grammar.effect_store())
            .unwrap()
            .is_zero()
    );
}

#[test]
#[ignore = "explicit pinned Elixir attachment regression gate"]
fn pinned_elixir_definition_blocks_attach_to_the_outer_call() {
    let root = root();
    let roster = SPECIMENS.iter().map(|s| s.to_string()).collect();
    let baseline = baseline(&root, &roster);
    let grammar =
        CompiledGrammar::compile(&fs::read(root.join("upstream/grammars/elixir.json")).unwrap())
            .unwrap();
    let mut session = grammar.session();
    for name in [
        "elixir/do-block-on-inner-call.ex",
        "elixir/do-block-without-inner-call.ex",
    ] {
        let source = fs::read(root.join(format!("research/joinery/specimen/{name}"))).unwrap();
        let tree = session.parse(&source).unwrap();
        assert_eq!(
            tree.roots().map(shape).collect::<Vec<_>>(),
            baseline[name].1["tree"].as_array().unwrap().clone(),
            "{name}: call attachment"
        );
    }
}

#[test]
#[ignore = "explicit sealed full36 Rust rule-extra regression gate"]
fn pinned_rust_ledger_preserves_complete_rule_extra_trees() {
    let root = root();
    let bundle = root.join(".local/rust-migration/reference-verified");
    let bytes = fs::read(bundle.join("manifest.json")).unwrap();
    assert_eq!(
        sha256(&bytes),
        "4be57bd42e493b13b6b017d75e0361a86fa2b0ad5a1a78ebc1b76e9c02d32831"
    );
    let manifest: Value = serde_json::from_slice(&bytes).unwrap();
    let case = manifest["cases"]
        .as_array()
        .unwrap()
        .iter()
        .find(|c| c["id"] == "corpus-rust")
        .unwrap();
    assert_eq!(case["strict"], true);
    let mut inputs = Vec::new();
    for path in [
        case["argv"][1].as_str().unwrap(),
        case["argv"][2].as_str().unwrap(),
        "outputs/corpus-rust.json",
    ] {
        let bytes = fs::read(bundle.join(relative(path))).unwrap();
        assert_eq!(
            sha256(&bytes),
            manifest["files"][path].as_str().unwrap(),
            "sealed Rust input/output drift {path}"
        );
        inputs.push(bytes);
    }
    let grammar = CompiledGrammar::compile(&inputs[0]).unwrap();
    let mut session = grammar.session();
    let tree = session.parse(&inputs[1]).unwrap();
    let expected: Value = serde_json::from_slice(&inputs[2]).unwrap();
    assert_eq!(
        tree.roots().map(shape).collect::<Vec<_>>(),
        expected["tree"].as_array().unwrap().clone()
    );
    assert!(tree.survey().is_sound());
    assert!(
        !session
            .product(&mut grammar.effect_store())
            .unwrap()
            .is_zero()
    );
}
