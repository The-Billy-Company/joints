//! Exercise the public process boundary, including evidence and failure exits.
use std::{
    fs,
    io::Write,
    path::{Path, PathBuf},
    process::{Command, Output, Stdio},
    sync::atomic::{AtomicUsize, Ordering},
};

use serde_json::{Value, json};

static NEXT: AtomicUsize = AtomicUsize::new(0);

struct Files(PathBuf);
impl Files {
    fn new() -> Self {
        let path = std::env::temp_dir().join(format!(
            "joints-cli-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&path).unwrap();
        Self(path)
    }
    fn put(&self, name: &str, bytes: impl AsRef<[u8]>) -> PathBuf {
        let path = self.0.join(name);
        fs::write(&path, bytes).unwrap();
        path
    }
    fn grammar(&self, name: &str) -> PathBuf {
        self.put(
            &format!("{name}.json"),
            serde_json::to_vec(&json!({
                "name":name,
                "rules":{
                    "document":{"type":"REPEAT","content":{"type":"SYMBOL","name":"word"}},
                    "word":{"type":"PATTERN","value":"[a-z]+"}
                },
                "extras":[{"type":"PATTERN","value":"\\s+"}]
            }))
            .unwrap(),
        )
    }
    fn run(&self, args: &[&str], stdin: Option<&[u8]>) -> Output {
        let mut child = Command::new(env!("CARGO_BIN_EXE_joints-rs"))
            .current_dir(&self.0)
            .env_remove("JOINTS_CUSTOMARY")
            .args(args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap();
        if let Some(bytes) = stdin {
            child.stdin.take().unwrap().write_all(bytes).unwrap();
        } else {
            drop(child.stdin.take());
        }
        child.wait_with_output().unwrap()
    }
}
impl Drop for Files {
    fn drop(&mut self) {
        fs::remove_dir_all(&self.0).unwrap();
    }
}
fn text(path: &Path) -> &str {
    path.to_str().unwrap()
}
fn code(output: &Output, expected: i32) {
    assert_eq!(
        output.status.code(),
        Some(expected),
        "stdout={}\nstderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}
fn lines(output: &Output) -> Vec<Value> {
    String::from_utf8(output.stdout.clone())
        .unwrap()
        .lines()
        .map(|s| serde_json::from_str(s).unwrap())
        .collect()
}

#[test]
fn parse_machine_protocol_streams_all_files_and_retains_io_failure() {
    let f = Files::new();
    let grammar = f.grammar("words");
    let a = f.put("a.txt", b"one two");
    let b = f.put("b.txt", b"three");
    let output = f.run(
        &[
            "parse",
            text(&grammar),
            text(&a),
            "missing.txt",
            text(&b),
            "--json",
            "--all",
            "--mend=none",
            "--no-supply",
        ],
        None,
    );
    code(&output, 2);
    let answers = lines(&output);
    assert_eq!(answers.len(), 2);
    for (answer, path) in answers.iter().zip([&a, &b]) {
        assert_eq!(answer["path"], text(path));
        assert_eq!(answer["language"], "words");
        assert_eq!(answer["stop"]["kind"], "accepted");
        assert_eq!(answer["roots"], 1);
        assert_eq!(answer["mends"], 0);
        assert_eq!(answer["supplied"], 0);
        assert_eq!(answer["survey"]["sound"], true);
        assert!(answer["tree"].is_array());
        assert!(answer["scars"].is_array());
        assert!(answer.get("accepted").is_none());
    }
    assert!(String::from_utf8_lossy(&output.stderr).contains("missing.txt"));
}

#[test]
fn parse_stdin_refusal_quiet_and_conflicting_options_have_distinct_exits() {
    let f = Files::new();
    let grammar = f.grammar("words");
    let output = f.run(
        &[
            "parse",
            text(&grammar),
            "-",
            "--json",
            "--mend=none",
            "--no-supply",
        ],
        Some(b"one 7"),
    );
    code(&output, 1);
    let answer = lines(&output).pop().unwrap();
    assert_ne!(answer["stop"]["kind"], "accepted");
    assert_eq!(answer["path"], "-");
    let quiet = f.run(&["parse", text(&grammar), "-", "--quiet"], Some(b"one"));
    code(&quiet, 0);
    assert!(quiet.stdout.is_empty());
    let bad = f.run(
        &["parse", text(&grammar), "-", "--json", "--ranges"],
        Some(b"one"),
    );
    code(&bad, 2);
    assert!(bad.stdout.is_empty());
}

#[test]
fn minted_single_and_bank_artifacts_select_every_member_and_reject_corruption() {
    let f = Files::new();
    let a = f.grammar("alpha");
    let b = f.grammar("beta");
    let source = f.put("source", b"one two");
    let single = f.0.join("single.folio");
    let bank = f.0.join("both.codex");
    let piped = f.0.join("piped.folio");
    code(
        &f.run(
            &["mint", "-", "-o", text(&piped)],
            Some(&fs::read(&a).unwrap()),
        ),
        0,
    );
    code(
        &f.run(&["parse", text(&piped), text(&source), "--quiet"], None),
        0,
    );
    let minted = f.run(&["mint", text(&a), "-o", text(&single)], None);
    code(&minted, 0);
    let encoded = fs::read(&single).unwrap();
    let version = u32::from_le_bytes(encoded[8..12].try_into().unwrap());
    assert_eq!(version, joints_engine::Bank::FORMAT_VERSION);
    assert!(String::from_utf8_lossy(&minted.stdout).starts_with(&format!("artifact v{version}: ")));
    let original = fs::read(&single).unwrap();
    let inspection = f.run(&["mint", text(&single)], None);
    code(&inspection, 0);
    // Inspection reports precisely the canonical bytes and shape reported by
    // actual minting at the same target, and cannot modify the input artifact.
    assert_eq!(inspection.stdout, minted.stdout);
    assert_eq!(inspection.stderr, minted.stderr);
    assert_eq!(fs::read(&single).unwrap(), original);
    let grammar = joints_engine::CompiledGrammar::from_artifact(&original).unwrap();
    let report = String::from_utf8(inspection.stdout).unwrap();
    let tail = report.find(':').unwrap();
    assert!(report[..tail].starts_with("artifact v"));
    assert_eq!(
        &report[tail..],
        format!(
            ": 1 languages, {} bytes  {}\n  alpha: {} symbols, {} states\n",
            original.len(),
            single.display(),
            grammar.symbol_count(),
            grammar.state_count()
        )
    );
    code(
        &f.run(&["parse", text(&single), text(&source), "--quiet"], None),
        0,
    );
    let implicit = f.run(&["parse", text(&single), text(&source), "--json"], None);
    let explicit = f.run(
        &[
            "parse",
            text(&single),
            text(&source),
            "--json",
            "--language=alpha",
        ],
        None,
    );
    code(&implicit, 0);
    code(&explicit, 0);
    assert_eq!(implicit.stdout, explicit.stdout);
    let missing = f.run(
        &["parse", text(&single), text(&source), "--language=absent"],
        None,
    );
    code(&missing, 2);
    assert!(
        String::from_utf8_lossy(&missing.stderr)
            .contains("has no language absent; available: alpha")
    );
    code(
        &f.run(&["mint", text(&single), text(&b), "-o", text(&bank)], None),
        0,
    );
    code(
        &f.run(&["parse", text(&bank), text(&source), "--quiet"], None),
        2,
    );
    for language in ["alpha", "beta"] {
        let output = f.run(
            &[
                "parse",
                text(&bank),
                text(&source),
                "--json",
                &format!("--language={language}"),
            ],
            None,
        );
        code(&output, 0);
        assert_eq!(lines(&output)[0]["language"], language);
    }
    code(&f.run(&["mint", text(&bank)], None), 0);
    let mut bytes = fs::read(&single).unwrap();
    let last = bytes.len() - 1;
    bytes[last] ^= 1;
    let corrupt = f.put("corrupt.folio", bytes);
    code(
        &f.run(&["parse", text(&corrupt), text(&source), "--quiet"], None),
        2,
    );
    for rejected in [
        corrupt,
        f.put("truncated.folio", b"JNTRART\0"),
        f.put("invalid.json", br#"{"name":"broken","rules":{}}"#),
    ] {
        let before = fs::read(&rejected).unwrap();
        let output = f.run(&["mint", text(&rejected)], None);
        code(&output, 2);
        assert!(output.stdout.is_empty());
        assert!(!output.stderr.is_empty());
        assert_eq!(fs::read(&rejected).unwrap(), before);
    }
    code(
        &f.run(&["mint", text(&a), text(&a), "-o", text(&bank)], None),
        2,
    );
}

#[test]
fn custom_scanner_book_is_checked_and_persisted_by_mint() {
    let f = Files::new();
    let grammar=f.put("external.json",br#"{"name":"custom","externals":[{"type":"SYMBOL","name":"answer"}],"rules":{"document":{"type":"SYMBOL","name":"answer"}}}"#);
    let book=f.put("book.json",br#"{"cohort":["answer"],"probes":{"body":"x+"},"rules":[{"phase":"bounded","when":[["wanted","answer"],["probe","body"]],"then":[["emit","answer"]]}]}"#);
    let source = f.put("source", b"xxx");
    let artifact = f.0.join("custom.folio");
    code(
        &f.run(
            &[
                "mint",
                text(&grammar),
                "--customary",
                text(&book),
                "-o",
                text(&artifact),
            ],
            None,
        ),
        0,
    );
    fs::remove_file(&book).unwrap();
    let parsed = f.run(
        &[
            "parse",
            text(&artifact),
            text(&source),
            "--json",
            "--mend=none",
            "--no-supply",
        ],
        None,
    );
    code(&parsed, 0);
    assert_eq!(lines(&parsed)[0]["tree"][0]["kids"][0]["name"], "answer");
    let lexed = f.run(&["lex", text(&artifact), text(&source)], None);
    code(&lexed, 1);
    let lexed = String::from_utf8(lexed.stdout).unwrap();
    assert!(lexed.contains("stray byte at 0"));
    assert!(lexed.contains("bound to customary: answer"));
    assert!(lexed.contains("stateful scanner hands are not asked"));
    f.put("external.customary.json", b"invalid JSON");
    code(
        &f.run(&["parse", text(&grammar), text(&source), "--quiet"], None),
        2,
    );
    let wrong = f.put("wrong.json", br#"{"cohort":["missing"],"rules":[]}"#);
    code(
        &f.run(
            &[
                "mint",
                text(&grammar),
                "--customary",
                text(&wrong),
                "-o",
                text(&artifact),
            ],
            None,
        ),
        2,
    );
}

#[test]
fn query_ndjson_has_explicit_confidence_and_match_exit_semantics() {
    let f = Files::new();
    let grammar = f.grammar("words");
    let source = f.put("source", b"one two");
    let query = f.put("query.scm", b"(word) @word");
    let output = f.run(
        &[
            "query",
            text(&grammar),
            text(&query),
            text(&source),
            "--json",
        ],
        None,
    );
    code(&output, 0);
    let answer = lines(&output).pop().unwrap();
    assert_eq!(answer["accepted"], true);
    assert_eq!(answer["sound"], true);
    assert_eq!(answer["mends"], 0);
    assert_eq!(answer["skipped"], 0);
    assert_eq!(answer["supplied"], 0);
    assert_eq!(answer["patterns"], 1);
    assert_eq!(answer["matches"].as_array().unwrap().len(), 2);
    assert_eq!(
        answer["matches"][0]["captures"][0],
        json!({"name":"word","start":0,"end":3})
    );
    let empty = f.put("empty.scm", b"((word) @word (#eq? @word \"absent\"))");
    code(
        &f.run(
            &[
                "query",
                text(&grammar),
                text(&empty),
                text(&source),
                "--quiet",
            ],
            None,
        ),
        1,
    );
    code(
        &f.run(
            &[
                "query",
                text(&grammar),
                text(&query),
                text(&source),
                "missing",
                "--json",
            ],
            None,
        ),
        2,
    );
}

#[test]
fn query_foreign_refusal_never_emits_a_partial_machine_answer() {
    let f = Files::new();
    let grammar = f.grammar("words");
    let source = f.put("source", b"one two");
    let query = f.put("query.scm", b"(word) @plain\n((word) @word (#host? @word))");
    let refused = f.run(
        &[
            "query",
            text(&grammar),
            text(&query),
            text(&source),
            "--json",
        ],
        None,
    );
    code(&refused, 2);
    assert!(refused.stdout.is_empty());
    let admitted = f.run(
        &[
            "query",
            text(&grammar),
            text(&query),
            text(&source),
            "--foreign=admit",
            "--json",
        ],
        None,
    );
    code(&admitted, 0);
    assert_eq!(lines(&admitted)[0]["matches"].as_array().unwrap().len(), 4);
    let denied = f.run(
        &[
            "query",
            text(&grammar),
            text(&query),
            text(&source),
            "--foreign=deny",
            "--json",
        ],
        None,
    );
    code(&denied, 0);
    assert_eq!(lines(&denied)[0]["matches"].as_array().unwrap().len(), 2);
}

#[test]
fn query_process_boundary_preserves_the_complete_independent_question_matrix() {
    let f = Files::new();
    let grammar = f.put("json.json", include_bytes!("../../test/grammar/json.json"));
    let oracle: Value =
        serde_json::from_slice(include_bytes!("fixtures/query-oracle.json")).unwrap();
    let differences: Value =
        serde_json::from_slice(include_bytes!("fixtures/query-contract-differences.json")).unwrap();
    let cases = oracle["cases"].as_array().unwrap();
    let known = differences["cases"].as_array().unwrap();
    assert_eq!((cases.len(), known.len()), (49, 4));
    let (mut executed, mut matched, mut captured, mut exact, mut inherited) = (0, 0, 0, 0, 0);
    for case in cases {
        let source = f.put("source.json", case["source"].as_str().unwrap());
        let query = f.put("query.scm", case["query"].as_str().unwrap());
        let expected = match known.iter().find(|d| d["case"] == case["case"]) {
            Some(contract) => {
                inherited += 1;
                &contract["native_matches"]
            }
            None => {
                exact += 1;
                &case["matches"]
            }
        };
        let expected_status = if expected.as_array().unwrap().is_empty() {
            1
        } else {
            0
        };
        let output = f.run(
            &[
                "query",
                text(&grammar),
                text(&query),
                text(&source),
                "--json",
                "--foreign=admit",
            ],
            None,
        );
        code(&output, expected_status);
        let answers = lines(&output);
        assert_eq!(answers.len(), 1, "{}", case["case"]);
        let answer = &answers[0];
        assert_eq!(answer["accepted"], true, "{}", case["case"]);
        assert_eq!(answer["sound"], true, "{}", case["case"]);
        assert_eq!(answer["mends"], 0, "{}", case["case"]);
        assert_eq!(&answer["matches"], expected, "{}", case["case"]);
        let matches = answer["matches"].as_array().unwrap();
        matched += matches.len();
        captured += matches
            .iter()
            .map(|m| m["captures"].as_array().unwrap().len())
            .sum::<usize>();
        executed += 1;
    }
    assert_eq!(
        (executed, exact, inherited, matched, captured),
        (49, 45, 4, 98, 125)
    );
}

#[test]
fn amend_applies_sequential_byte_edits_and_agrees_across_policies_and_cold() {
    let f = Files::new();
    let grammar = f.grammar("words");
    let source = f.put("source", b"one two");
    let expected = f.run(
        &["parse", text(&grammar), "-", "--all"],
        Some(b"one\nthree"),
    );
    code(&expected, 0);
    for flag in [
        "--policy=prove",
        "--policy=snap",
        "--policy=whole",
        "--cold",
    ] {
        let output = f.run(
            &[
                "amend",
                text(&grammar),
                text(&source),
                "4..7=three",
                "3..4=\\n",
                "--all",
                flag,
            ],
            None,
        );
        code(&output, 0);
        assert_eq!(output.stdout, expected.stdout, "{flag}");
        let stderr = String::from_utf8_lossy(&output.stderr);
        assert!(stderr.contains("4..7 +5"), "{stderr}");
        assert!(stderr.contains("3..4 +1"), "{stderr}");
        let rows = stderr
            .lines()
            .filter(|line| line.ends_with(" us"))
            .collect::<Vec<_>>();
        assert_eq!(rows.len(), 3, "{stderr}");
        for row in rows {
            assert!(row.contains("leaves reminted at "), "{row}");
            assert!(row.contains(", height "), "{row}");
            assert!(row.contains(", 0 lifts over 0 bytes, "), "{row}");
            let (read, elapsed) = row.rsplit_once(" tokens read, ").unwrap();
            read.rsplit_once(", ").unwrap().1.parse::<usize>().unwrap();
            elapsed
                .strip_suffix(" us")
                .unwrap()
                .parse::<u128>()
                .unwrap();
        }
        assert_eq!(fs::read(&source).unwrap(), b"one two");
    }
    let quiet = f.run(
        &[
            "amend",
            text(&grammar),
            text(&source),
            "0..3=three",
            "--quiet",
        ],
        None,
    );
    code(&quiet, 0);
    assert!(quiet.stdout.is_empty());
}

#[test]
fn amend_reports_real_leaf_costs_for_unchanged_and_whole_policies() {
    let f = Files::new();
    let grammar = f.grammar("words");
    let source = f.put("source", b"one two three");
    for flag in [
        "--policy=prove",
        "--policy=snap",
        "--policy=whole",
        "--cold",
    ] {
        let output = f.run(
            &[
                "amend",
                text(&grammar),
                text(&source),
                "4..7=two",
                "--quiet",
                flag,
            ],
            None,
        );
        code(&output, 0);
        let stderr = String::from_utf8_lossy(&output.stderr);
        let rows = stderr
            .lines()
            .filter(|line| line.ends_with(" us"))
            .collect::<Vec<_>>();
        assert_eq!(rows.len(), 2, "{stderr}");
        let opening = rows[0].split_once("accepted, ").unwrap().1;
        let change = rows[1].split_once("accepted, ").unwrap().1;
        let leaves = opening
            .split_once('/')
            .unwrap()
            .1
            .split(' ')
            .next()
            .unwrap()
            .parse::<usize>()
            .unwrap();
        assert!(leaves > 0);
        if flag == "--policy=prove" || flag == "--policy=snap" {
            assert!(
                change.starts_with(&format!("0/{leaves} leaves reminted at {leaves}, ")),
                "{stderr}"
            );
            assert!(change.contains(", 0 tokens read, "), "{stderr}");
        } else {
            assert!(
                change.starts_with(&format!("{leaves}/{leaves} leaves reminted at 0, ")),
                "{stderr}"
            );
            assert!(!change.contains(", 0 tokens read, "), "{stderr}");
        }
    }
}

#[test]
fn amend_rejects_bad_spelling_and_current_version_spans_without_writing_source() {
    let f = Files::new();
    let grammar = f.grammar("words");
    let source = f.put("source", b"one two");
    for edits in [
        vec!["wrong"],
        vec!["3..1=x"],
        vec!["0..3=", "5..6=x"],
        vec!["--policy=guess"],
    ] {
        let mut args = vec!["amend", text(&grammar), text(&source)];
        args.extend(edits);
        let output = f.run(&args, None);
        code(&output, 2);
        assert!(output.stdout.is_empty());
        assert_eq!(fs::read(&source).unwrap(), b"one two");
    }
}

#[test]
fn grammar_rules_and_actual_state_kernels_survive_native_artifact_loading() {
    let f = Files::new();
    let grammar = f.grammar("words");
    let artifact = f.0.join("words.folio");
    code(
        &f.run(&["mint", text(&grammar), "-o", text(&artifact)], None),
        0,
    );
    let json = f.run(&["grammar", text(&grammar), "--rules", "--conflicts"], None);
    let native = f.run(
        &["grammar", text(&artifact), "--rules", "--conflicts"],
        None,
    );
    code(&json, 0);
    code(&native, 0);
    assert_eq!(json.stdout, native.stdout);
    assert!(String::from_utf8_lossy(&json.stdout).contains("document ->"));
    let json = f.run(&["state", text(&grammar), "0"], None);
    let native = f.run(&["state", text(&artifact), "0"], None);
    code(&json, 0);
    code(&native, 0);
    assert_eq!(json.stdout, native.stdout);
    assert!(String::from_utf8_lossy(&json.stdout).contains("actual normalized kernel items"));
    code(&f.run(&["state", text(&artifact), "999999999"], None), 2);
    code(
        &f.run(&["state", text(&artifact), "--census", "absent"], None),
        1,
    );
}

#[test]
fn grammar_trace_reports_actual_construction_and_growth_never_rebuilds_artifacts() {
    let f = Files::new();
    let grammar = f.grammar("words");
    let output = f.run(&["grammar", text(&grammar), "--trace", "--growth=2"], None);
    code(&output, 0);
    let trace = String::from_utf8_lossy(&output.stderr);
    assert!(trace.contains("pass 0 Lalr: states Some("), "{trace}");
    assert!(
        trace.contains("table construction complete true"),
        "{trace}"
    );
    assert!(trace.contains("report truncated false"), "{trace}");
    let artifact = f.0.join("words.folio");
    code(
        &f.run(&["mint", text(&grammar), "-o", text(&artifact)], None),
        0,
    );
    let output = f.run(&["grammar", text(&artifact), "--trace"], None);
    code(&output, 0);
    assert!(String::from_utf8_lossy(&output.stderr).contains("no construction passes ran"));
    code(&f.run(&["grammar", text(&artifact), "--growth=2"], None), 2);
    for growth in ["--growth=", "--growth=-1", "--growth=4294967296"] {
        code(&f.run(&["grammar", text(&grammar), growth], None), 2);
    }
    let refused = f.put("ambiguous.json", serde_json::to_vec(&json!({
        "name":"ambiguous", "rules":{
            "document":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"a"},{"type":"SYMBOL","name":"b"}]},
            "a":{"type":"SEQ","members":[{"type":"STRING","value":"x"},{"type":"BLANK"}]},
            "b":{"type":"SEQ","members":[{"type":"STRING","value":"x"},{"type":"BLANK"}]}
        }
    })).unwrap());
    let output = f.run(&["grammar", text(&refused), "--trace"], None);
    code(&output, 2);
    let trace = String::from_utf8_lossy(&output.stderr);
    assert!(trace.contains("pass 0 Lalr:"), "{trace}");
    assert!(
        trace.contains("table construction complete false"),
        "{trace}"
    );
    assert!(trace.contains("unresolved conflict"), "{trace}");
}

#[test]
fn state_holding_matches_the_full_body_and_dot_and_chain_unwinds_exact_symbols() {
    let f = Files::new();
    let grammar=f.put("prefixes.json",br#"{"name":"prefixes","rules":{"doc":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"STRING","value":"a"},{"type":"STRING","value":"b"}]},{"type":"SEQ","members":[{"type":"STRING","value":"a"},{"type":"STRING","value":"b"},{"type":"STRING","value":"c"}]}]}}}"#);
    let held = f.run(
        &["state", text(&grammar), "--holding", "doc -> a b ."],
        None,
    );
    code(&held, 0);
    let stdout = String::from_utf8(held.stdout).unwrap();
    let items = stdout
        .lines()
        .filter(|line| line.contains(": doc ->"))
        .collect::<Vec<_>>();
    assert!(!items.is_empty());
    assert!(
        items.iter().all(|line| line.ends_with("doc -> a b .")),
        "{stdout}"
    );
    let state = items[0].split_once(':').unwrap().0;
    let chain = f.run(&["state", text(&grammar), "--chain", state], None);
    code(&chain, 0);
    assert!(String::from_utf8_lossy(&chain.stdout).contains("exact handle origin(s)"));
    code(
        &f.run(&["state", text(&grammar), "--holding", "doc -> a ."], None),
        1,
    );
    code(
        &f.run(
            &["state", text(&grammar), "--holding", "doc -> a . b ."],
            None,
        ),
        2,
    );
    let census = f.run(&["state", text(&grammar), "--census", "b", "absent"], None);
    code(&census, 0);
    assert!(String::from_utf8_lossy(&census.stdout).contains("reduce/accept lookahead"));
}

#[test]
fn lex_reports_context_free_coverage_and_a_real_unmatched_byte() {
    let f = Files::new();
    let grammar = f.grammar("words");
    let source = f.put("source", b"one two");
    let output = f.run(&["lex", text(&grammar), text(&source)], None);
    code(&output, 0);
    let stdout = String::from_utf8(output.stdout).unwrap();
    assert!(
        stdout.contains("2 tokens over 7 bytes (6 covered)"),
        "{stdout}"
    );
    assert!(stdout.contains("admitted context-free"));
    assert!(stdout.contains("1 extra bytes skipped"));
    let broken = f.put("broken", b"one7");
    let output = f.run(&["lex", text(&grammar), text(&broken)], None);
    code(&output, 1);
    assert!(String::from_utf8_lossy(&output.stdout).contains("stray byte at 3"));
}

#[test]
fn survey_runs_every_segmentation_and_compares_real_selected_path_effects() {
    let f = Files::new();
    let grammar = f.grammar("words");
    let source = f.put("source", b"one two three four five");
    for flags in [
        vec![],
        vec!["--exact", "--dump", "--confess", "--entries", "1"],
    ] {
        let mut args = vec!["survey", text(&grammar), text(&source)];
        args.extend(flags);
        let output = f.run(&args, None);
        code(&output, 0);
        let stdout = String::from_utf8(output.stdout).unwrap();
        assert!(
            stdout.contains("23 bytes -> 5 tokens, accepted"),
            "{stdout}"
        );
        assert_eq!(
            stdout
                .lines()
                .filter(|line| line.trim_start().starts_with("tok ")
                    || line.trim_start().starts_with("byte "))
                .count(),
            8,
            "{stdout}"
        );
        assert!(stdout.contains("8/8 chains held"), "{stdout}");
        assert!(!stdout.contains("DISAGREED"), "{stdout}");
    }
}

#[test]
fn survey_limit_refusals_empty_inputs_and_io_failures_never_count_as_success() {
    let f = Files::new();
    let grammar = f.grammar("words");
    let source = f.put("source", b"one two");
    let limited = f.run(
        &["survey", text(&grammar), text(&source), "--work", "0"],
        None,
    );
    code(&limited, 1);
    let stdout = String::from_utf8(limited.stdout).unwrap();
    assert!(stdout.contains("0/8 chains held"), "{stdout}");
    assert!(stdout.contains("8 refused at a ceiling"), "{stdout}");
    let empty = f.put("empty", b"");
    let nothing = f.run(&["survey", text(&grammar), text(&empty)], None);
    code(&nothing, 1);
    assert!(String::from_utf8_lossy(&nothing.stdout).contains("nothing measured"));
    let io = f.run(&["survey", text(&grammar), "missing", text(&source)], None);
    code(&io, 2);
    assert!(String::from_utf8_lossy(&io.stdout).contains("8/8 chains held"));
    assert!(String::from_utf8_lossy(&io.stderr).contains("missing"));
}
