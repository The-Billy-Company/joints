//! Repeatable public-API workloads. Run an optimized build; timings include drop.
#![forbid(unsafe_code)]

use joints_engine::{
    Bank, ByteSpan, CompiledGrammar, Document, ForeignPolicy, Node, Query, TreeSnapshot,
};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{error::Error, fmt::Write, hint::black_box, path::PathBuf, sync::Arc, time::Instant};

struct Options {
    grammar: PathBuf,
    source: Option<PathBuf>,
    samples: usize,
    iterations: usize,
    entries: usize,
    only: Option<String>,
}

fn options() -> Result<Options, Box<dyn Error>> {
    let mut result = Options {
        grammar: PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../test/grammar/json.json"),
        source: None,
        samples: 15,
        iterations: 1,
        entries: 4096,
        only: None,
    };
    let mut args = std::env::args().skip(1);
    let mut test_mode = false;
    while let Some(arg) = args.next() {
        if arg == "--bench" {
            continue;
        }
        if arg == "--test" || arg.starts_with("--test-threads=") {
            test_mode = true;
            continue;
        }
        let value = args.next().ok_or("missing option value")?;
        match arg.as_str() {
            "--grammar" => result.grammar = value.into(),
            "--source" => result.source = Some(value.into()),
            "--samples" => result.samples = value.parse()?,
            "--iterations" => result.iterations = value.parse()?,
            "--entries" => result.entries = value.parse()?,
            "--only" => result.only = Some(value),
            _ => return Err(format!("unknown option {arg}").into()),
        }
    }
    if test_mode {
        result.samples = 1;
        result.iterations = 1;
        result.entries = 16;
    }
    if result.samples == 0 || result.iterations == 0 || result.entries == 0 {
        return Err("samples, iterations and entries must be positive".into());
    }
    Ok(result)
}

// Include complete observable structure, source, aliases, fields and ownership links.
fn image(tree: &TreeSnapshot) -> Vec<u8> {
    let nodes: Vec<_> = (0..tree.survey().held)
        .map(|at| {
            let node = tree.node_at(at).expect("published node");
            json!([
                node.index(),
                node.name(),
                node.is_named(),
                node.is_extra(),
                node.span().start(),
                node.span().end(),
                node.field(),
                node.parent().map(Node::index),
                node.children().map(Node::index).collect::<Vec<_>>()
            ])
        })
        .collect();
    serde_json::to_vec(&json!({
        "source": tree.source(), "nodes": nodes,
        "roots": tree.roots().map(Node::index).collect::<Vec<_>>(),
        "stop": format!("{:?}", tree.stop()),
        "repairs": format!("{:?}", tree.repairs()),
        "survey": format!("{:?}", tree.survey()),
    }))
    .expect("serializable tree")
}

fn digest(bytes: &[u8]) -> String {
    let mut hex = String::with_capacity(64);
    for byte in Sha256::digest(bytes) {
        write!(hex, "{byte:02x}").expect("writing to a String cannot fail");
    }
    hex
}

fn record<F>(
    options: &Options,
    rows: &mut Vec<Value>,
    name: &str,
    mut operation: F,
) -> Result<(), Box<dyn Error>>
where
    F: FnMut() -> Result<(), Box<dyn Error>>,
{
    if options.only.as_deref().is_some_and(|only| only != name) {
        return Ok(());
    }
    operation()?;
    for sample in 0..options.samples {
        let start = Instant::now();
        for _ in 0..options.iterations {
            operation()?;
        }
        rows.push(json!({
            "operation": name, "sample": sample,
            "elapsed_ns": start.elapsed().as_nanos(),
            "iterations": options.iterations,
        }));
    }
    Ok(())
}

fn main() -> Result<(), Box<dyn Error>> {
    let options = options()?;
    let grammar_source = std::fs::read(&options.grammar)?;
    let source = match &options.source {
        Some(path) => std::fs::read(path)?,
        None => format!("[{}]", vec!["123"; options.entries].join(",")).into_bytes(),
    };
    let grammar = CompiledGrammar::compile(&grammar_source)?;
    let artifact = grammar.artifact()?;
    let loaded = CompiledGrammar::from_artifact(&artifact)?;
    let tree = grammar.session().parse(&source)?;
    let expected = image(&tree);
    if image(&loaded.session().parse(&source)?) != expected {
        return Err("compiled and loaded full trees disagree".into());
    }
    let query_source = b"(_) @node";
    let query = Query::compile(Arc::clone(&grammar), query_source)?;
    let lexical = grammar.lexical_walk(&source, 100_000_000)?;
    let lexical_image = json!({
        "covered": lexical.covered, "skipped": lexical.skipped,
        "stray": lexical.stray, "work": lexical.work,
        "tokens": format!("{:?}", lexical.tokens),
    });
    let query_image: Vec<_> = query
        .execute(&tree, ForeignPolicy::Refuse)?
        .iter()
        .map(|found| {
            json!([
                format!("{:?}", found.pattern),
                found
                    .captures
                    .iter()
                    .map(|capture| (format!("{:?}", capture.id), capture.node.index()))
                    .collect::<Vec<_>>()
            ])
        })
        .collect();
    let mut session = grammar.session();
    session.parse(&source)?;
    let mut rows = Vec::new();
    record(&options, &mut rows, "compile", || {
        black_box(CompiledGrammar::compile(black_box(&grammar_source))?);
        Ok(())
    })?;
    record(&options, &mut rows, "artifact_write", || {
        black_box(grammar.artifact()?);
        Ok(())
    })?;
    record(&options, &mut rows, "artifact_load", || {
        black_box(CompiledGrammar::from_artifact(black_box(&artifact))?);
        Ok(())
    })?;
    record(&options, &mut rows, "bank_load", || {
        let bank = Bank::from_bytes(black_box(&artifact))?;
        black_box(bank.get(grammar.name())?.ok_or("missing bank grammar")?);
        Ok(())
    })?;
    record(&options, &mut rows, "lexical_walk", || {
        black_box(grammar.lexical_walk(black_box(&source), 100_000_000)?);
        Ok(())
    })?;
    record(&options, &mut rows, "parse_fresh_session", || {
        black_box(grammar.session().parse(black_box(&source))?);
        Ok(())
    })?;
    record(&options, &mut rows, "parse_reused_session", || {
        black_box(session.parse(black_box(&source))?);
        Ok(())
    })?;
    record(&options, &mut rows, "effect_product_fresh_store", || {
        let mut store = grammar.effect_store();
        black_box(session.product(&mut store)?);
        Ok(())
    })?;
    record(&options, &mut rows, "query_compile", || {
        black_box(Query::compile(
            Arc::clone(&grammar),
            black_box(query_source),
        )?);
        Ok(())
    })?;
    record(&options, &mut rows, "query_execute", || {
        black_box(query.execute(black_box(&tree), ForeignPolicy::Refuse)?);
        Ok(())
    })?;
    record(&options, &mut rows, "tree_siblings", || {
        let tree = black_box(&tree);
        for at in 0..tree.survey().held {
            let node = tree.node_at(at).expect("published node");
            black_box((
                node.next_sibling(),
                node.prev_sibling(),
                node.next_named_sibling(),
                node.prev_named_sibling(),
            ));
        }
        Ok(())
    })?;
    record(&options, &mut rows, "tree_covering", || {
        let tree = black_box(&tree);
        for at in (0..source.len()).step_by(16) {
            black_box(tree.covering(ByteSpan::new(at, at + 1).expect("ordered span")));
        }
        Ok(())
    })?;
    record(&options, &mut rows, "tree_subtree_size", || {
        black_box(
            black_box(&tree)
                .root()
                .ok_or("missing root")?
                .subtree_size()?,
        );
        Ok(())
    })?;
    record(&options, &mut rows, "document_open", || {
        black_box(Document::new(Arc::clone(&grammar), black_box(&source))?);
        Ok(())
    })?;
    // Paired whitespace insertion/removal restores the exact initial source.
    // Validate the final publication outside timing against a cold parse.
    let mut document = Document::new(Arc::clone(&grammar), &source)?;
    record(&options, &mut rows, "document_edit_end_pair", || {
        let end = document.source().len();
        document.edit(ByteSpan::new(end, end).expect("empty span"), b" ")?;
        document.edit(ByteSpan::new(end, end + 1).expect("ordered span"), b"")?;
        black_box(document.snapshot());
        Ok(())
    })?;
    let mut store = grammar.effect_store();
    let product = session.product(&mut store)?;
    let description = store.describe(product)?;
    if image(document.snapshot()) != expected
        || document.source() != source
        || document.product()? != description
    {
        return Err("edited full tree differs from cold parse".into());
    }
    if rows.is_empty() {
        return Err("unknown operation selected".into());
    }
    println!(
        "{}",
        serde_json::to_string(&json!({
            "schema": 1, "grammar": grammar.name(), "source_bytes": source.len(),
            "source_sha256": digest(&source),
            "grammar_sha256": digest(&grammar_source),
            "tree_sha256": digest(&expected),
        "lexical_sha256": digest(&serde_json::to_vec(&lexical_image)?),
        "lexical_covered": lexical.covered, "lexical_stray": lexical.stray,
        "query_sha256": digest(&serde_json::to_vec(&query_image)?),
        "effect_sha256": digest(format!("{description:?}").as_bytes()),
            "nodes": tree.survey().held, "artifact_bytes": artifact.len(),
            "scope": "public API workloads; release build; one warm-up; allocations and drop included; edit rows contain two edits; no cross-process RSS measurement",
            "rows": rows,
        }))?
    );
    Ok(())
}
