#![forbid(unsafe_code)]

use std::{
    collections::{BTreeMap, BTreeSet, VecDeque},
    env, fs,
    io::{self, Read, Write},
    path::{Path, PathBuf},
    process::ExitCode,
    sync::Arc,
    time::Instant,
};

use joints_engine::effects::{Constraint, EffectDescription};
use joints_engine::{
    Action, ArtifactLimits, Bank, ByteSpan, CompileOptions, CompileReport, CompiledGrammar,
    ConflictClass, Document, DocumentOptions, DocumentPolicy, ForeignPolicy, Lookahead, Node,
    ParseLimits, Query, QueryLimits, QueryMatch, Recovery, RepairKind, StateId, Stop, Supply,
    SymbolId, TreeSnapshot,
};

type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;

fn main() -> ExitCode {
    match run() {
        Ok(code) => ExitCode::from(code),
        Err(error) => {
            eprintln!("joints-rs: {error}");
            ExitCode::from(2)
        }
    }
}

fn run() -> Result<u8> {
    let args = env::args_os()
        .skip(1)
        .map(|arg| {
            arg.into_string()
                .map_err(|_| "command arguments must be UTF-8")
        })
        .collect::<std::result::Result<Vec<_>, _>>()?;
    let Some((command, args)) = args.split_first() else {
        help(&mut io::stderr().lock())?;
        return Ok(2);
    };
    match command.as_str() {
        "--version" | "-V" => {
            if !args.is_empty() {
                return Err("--version takes no arguments".into());
            }
            println!("joints-rs {} (native Rust)", env!("CARGO_PKG_VERSION"));
            Ok(0)
        }
        "--help" | "-h" | "help" => {
            help(&mut io::stdout().lock())?;
            Ok(0)
        }
        "parse" => parse_command(args),
        "mint" => mint_command(args),
        "grammar" => grammar_command(args),
        "query" => query_command(args),
        "amend" => amend_command(args),
        "state" => state_command(args),
        "lex" => lex_command(args),
        "survey" => survey_command(args),
        _ => Err(format!("unknown command {command}; use --help").into()),
    }
}

fn help(out: &mut impl Write) -> io::Result<()> {
    out.write_all(
        b"joints-rs - native parsing as algebra\n\n\
usage:\n\
  joints-rs grammar GRAMMAR [--rules] [--conflicts] [--trace] [--growth=N]\n\
  joints-rs parse GRAMMAR FILE... [--all] [--json|--ranges|--scars] [--quiet]\n\
  joints-rs mint GRAMMAR... [-o ARTIFACT]\n\
  joints-rs query GRAMMAR QUERY FILE... [--json|--captures] [--dead] [--quiet]\n\
  joints-rs amend GRAMMAR FILE [FROM..TO=TEXT...] [--all] [--quiet] [--cold]\n\
  joints-rs state GRAMMAR N | --census TERMINAL... | --holding ITEM | --chain N\n\
  joints-rs lex GRAMMAR FILE [--language=NAME]\n\
  joints-rs survey GRAMMAR FILE... [--exact] [--dump] [--confess]\n\
    [--entries N] [--limbs N] [--fan N] [--churn N] [--work N]\n\
amend policies: --policy=prove|snap|whole; snap uses exact prefix validation.\n\
  joints-rs --version\n\n\
GRAMMAR may be grammar JSON, a checked native artifact or a native bank.\n\
Use --language=NAME when a bank contains several languages. A FILE of - is stdin.\n\
parse options: --mend=none|keep|fell|relent (default fell), --no-supply\n",
    )
}

fn read(path: &str, limit: usize) -> io::Result<Vec<u8>> {
    if path == "-" {
        read_bounded(io::stdin().lock(), limit)
    } else {
        read_bounded(fs::File::open(path)?, limit)
    }
}

fn read_bounded(reader: impl Read, limit: usize) -> io::Result<Vec<u8>> {
    let cap = u64::try_from(limit).unwrap_or(u64::MAX).saturating_add(1);
    let mut bytes = vec![];
    reader.take(cap).read_to_end(&mut bytes)?;
    if bytes.len() > limit {
        return Err(io::Error::other(format!(
            "input exceeds {limit} byte limit"
        )));
    }
    Ok(bytes)
}

fn load_grammar(path: &str, language: Option<&str>) -> Result<Arc<CompiledGrammar>> {
    load_grammar_with_customary(path, language, None)
}

fn load_grammar_with_customary(
    path: &str,
    language: Option<&str>,
    customary: Option<&str>,
) -> Result<Arc<CompiledGrammar>> {
    let bytes = read(path, ArtifactLimits::default().bytes)?;
    load_grammar_bytes(path, &bytes, language, customary)
}

fn load_grammar_bytes(
    path: &str,
    bytes: &[u8],
    language: Option<&str>,
    customary: Option<&str>,
) -> Result<Arc<CompiledGrammar>> {
    let json = bytes.iter().find(|b| !b.is_ascii_whitespace()) == Some(&b'{');
    if json {
        let book = customary_source(path, bytes, customary)?;
        if let Some(book) = book {
            let grammar =
                CompiledGrammar::compile_with_customary(bytes, &book, CompileOptions::default())?;
            if language.is_some_and(|wanted| wanted != grammar.name()) {
                return Err(format!("{path} has no language {}", language.unwrap()).into());
            }
            return Ok(grammar);
        }
    } else if customary.is_some() {
        return Err("--customary applies to original grammar JSON; a native artifact retains its own scanner book".into());
    }
    if language.is_none() && bytes.starts_with(b"JNTRART\0") {
        // A one-shot standalone load can validate borrowed input directly.
        // A lazy Bank would retain a second complete payload while decoding.
        // Explicit name selection keeps the directory/error-order path below.
        return Ok(CompiledGrammar::from_artifact(bytes)?);
    }
    let bank = Bank::from_bytes(bytes)?;
    let names: Vec<_> = bank.languages().collect();
    let selected = match language {
        Some(name) => name,
        None if names.len() == 1 => names[0],
        None => {
            return Err(format!(
                "{path} holds {} languages; say --language=NAME: {}",
                names.len(),
                names.join(", ")
            )
            .into());
        }
    };
    bank.get(selected)?.ok_or_else(|| {
        format!(
            "{path} has no language {selected}; available: {}",
            names.join(", ")
        )
        .into()
    })
}

fn customary_source(path: &str, bytes: &[u8], customary: Option<&str>) -> Result<Option<Vec<u8>>> {
    if bytes.len() > CompileOptions::default().tables.source_bytes {
        return Err("grammar JSON exceeds source byte limit".into());
    }
    let data: serde_json::Value = serde_json::from_slice(bytes)?;
    let name = data
        .get("name")
        .and_then(serde_json::Value::as_str)
        .unwrap_or("grammar");
    if let Some(explicit) = customary {
        return Ok(Some(read(explicit, 1 << 20)?));
    }
    if let Some(dir) = env::var_os("JOINTS_CUSTOMARY") {
        if name.contains(['/', '\\', '\0']) || name == "." || name == ".." {
            return Err("grammar name cannot address a customary directory entry".into());
        }
        if let Some(book) = optional_file(&PathBuf::from(dir).join(format!("{name}.json")))? {
            return Ok(Some(book));
        }
    }
    if path != "-" {
        return Ok(optional_file(
            &Path::new(path).with_extension("customary.json"),
        )?);
    }
    Ok(None)
}

fn optional_file(path: &Path) -> io::Result<Option<Vec<u8>>> {
    match fs::File::open(path) {
        Ok(file) => Ok(Some(read_bounded(file, 1 << 20)?)),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error),
    }
}

fn parse_command(args: &[String]) -> Result<u8> {
    let (grammar_path, args) = args.split_first().ok_or("parse requires a grammar path")?;
    let mut paths = Vec::new();
    let mut all = false;
    let mut json = false;
    let mut ranges = false;
    let mut quiet = false;
    let mut scars = false;
    let mut language = None;
    let mut recovery = Recovery::Fell;
    let mut supply = Supply::UniqueLiteral;
    for arg in args {
        match arg.as_str() {
            "--all" => all = true,
            "--json" => json = true,
            "--ranges" => ranges = true,
            "--quiet" => quiet = true,
            "--scars" => scars = true,
            "--mend=none" => recovery = Recovery::None,
            "--mend=keep" => recovery = Recovery::Keep,
            "--mend=fell" => recovery = Recovery::Fell,
            "--mend=relent" => recovery = Recovery::Relent,
            "--no-supply" => supply = Supply::Disabled,
            flag if flag.starts_with("--language=") => language = Some(&flag[11..]),
            "-" => paths.push(arg),
            flag if flag.starts_with('-') => {
                return Err(format!("unsupported option {flag}").into());
            }
            _ => paths.push(arg),
        }
    }
    if paths.is_empty() {
        return Err("parse requires at least one source path".into());
    }
    if json && (ranges || scars) {
        return Err("--json cannot combine with --ranges or --scars".into());
    }
    let grammar = load_grammar(grammar_path, language)?;
    let blind = grammar.unsupported_externals().count();
    if blind > 0 {
        eprintln!(
            "joints: {}: blind to {blind} externally scanned terminal(s)",
            grammar.name()
        );
    }
    let mut session = grammar.session();
    session.set_recovery(recovery);
    session.set_supply(supply);
    let mut worst = 0;
    let stdout = io::stdout();
    let mut output = io::BufWriter::new(stdout.lock());
    for path in paths {
        let source = match read(path, ParseLimits::default().source_bytes) {
            Ok(source) => source,
            Err(error) => {
                eprintln!("joints-rs: {path}: {error}");
                worst = 2;
                continue;
            }
        };
        let tree = match session.parse_partial(&source) {
            Ok(tree) => tree,
            Err(error) => {
                eprintln!("joints-rs: {path}: {error}");
                worst = 2;
                continue;
            }
        };
        if tree.stop() != Stop::Accepted {
            worst = worst.max(1);
        }
        if quiet {
        } else if json {
            machine(&tree, path, all, &mut output)?;
        } else if scars {
            seams(&tree, &mut output)?;
        } else if ranges {
            outline(&tree, all, &mut output)?;
        } else {
            sexp(&tree, all, &mut output)?;
        }
        output.flush()?;
        verdict(&tree, path, &mut io::stderr().lock())?;
    }
    output.flush()?;
    Ok(worst)
}

fn seams(tree: &TreeSnapshot, out: &mut impl Write) -> io::Result<()> {
    let mut shifted = 0;
    for repair in tree.repairs() {
        match repair.kind {
            RepairKind::Supplied { .. } => write!(
                out,
                "scar {} gave {} ",
                repair.span.start(),
                tree.repair_symbol(repair).unwrap_or("<unknown>")
            )?,
            RepairKind::Deleted { felled } => write!(
                out,
                "scar {}..{} {}B {} ",
                repair.span.start(),
                repair.span.end(),
                repair.span.end() - repair.span.start(),
                if felled { "fell" } else { "kept" }
            )?,
        }
        match repair.context {
            Stop::Stray { .. } => out.write_all(b"stray")?,
            Stop::Unexpected { symbol, state, .. } => write!(
                out,
                "unexpected {} in state {}",
                tree.grammar().symbol_name(symbol).unwrap_or("<unknown>"),
                state.index()
            )?,
            _ => out.write_all(b"unreported")?,
        }
        writeln!(
            out,
            ", {} heads, +{} tokens",
            repair.heads,
            repair.shifted.saturating_sub(shifted)
        )?;
        shifted = repair.shifted;
    }
    Ok(())
}

fn mint_command(args: &[String]) -> Result<u8> {
    let mut paths = vec![];
    let mut output = None;
    let mut customary = None;
    let mut rest = args.iter();
    while let Some(arg) = rest.next() {
        match arg.as_str() {
            "-o" | "--out" => {
                if output.is_some() {
                    return Err("mint takes one output path".into());
                }
                output = Some(PathBuf::from(rest.next().ok_or("-o needs a path")?));
            }
            "--customary" => {
                if customary.is_some() {
                    return Err("mint takes one customary source".into());
                }
                customary = Some(rest.next().ok_or("--customary needs a path")?.as_str());
            }
            "-" => paths.push(arg),
            flag if flag.starts_with('-') => {
                return Err(format!("unsupported mint option {flag}").into());
            }
            _ => paths.push(arg),
        }
    }
    if paths.is_empty() {
        return Err("mint needs a grammar or artifact".into());
    }
    if paths.len() > 1 && output.is_none() {
        return Err("minting several languages needs -o PATH".into());
    }
    if paths.len() > 1 && customary.is_some() {
        return Err("--customary names one grammar's scanner; mint each member first".into());
    }
    // Retain encoded members, not several expensive compiler graphs at once.
    let mut members = vec![];
    let mut shapes = vec![];
    let mut retained_bytes = 0usize;
    let mut inspect = false;
    {
        let mut retain = |grammar: Arc<CompiledGrammar>| -> Result<()> {
            let encoded = grammar.artifact()?;
            retained_bytes = retained_bytes
                .checked_add(encoded.len())
                .ok_or("artifact size overflow")?;
            if retained_bytes > ArtifactLimits::default().bytes {
                return Err("combined member artifacts exceed the native byte limit".into());
            }
            shapes.push((
                grammar.name().to_owned(),
                grammar.symbol_count(),
                grammar.state_count(),
            ));
            members.push(encoded);
            Ok(())
        };
        for path in &paths {
            let bytes = read(path, ArtifactLimits::default().bytes)?;
            if bytes.iter().find(|b| !b.is_ascii_whitespace()) == Some(&b'{') {
                retain(load_grammar_bytes(path, &bytes, None, customary)?)?;
                continue;
            }
            if customary.is_some() {
                return Err("--customary needs original grammar JSON".into());
            }
            inspect = paths.len() == 1 && output.is_none();
            let names = {
                let bank = Bank::from_bytes(&bytes)?;
                bank.languages().map(str::to_owned).collect::<Vec<_>>()
            };
            if paths.len() > 1 && names.len() != 1 {
                return Err(
                    format!("{path} is already a bank; mint its individual members").into(),
                );
            }
            for name in names {
                let bank = Bank::from_bytes(&bytes)?;
                retain(bank.get(&name)?.ok_or("bank language disappeared")?)?;
            }
        }
    }
    let encoded = if members.len() == 1 {
        members.pop().unwrap()
    } else {
        Bank::pack_artifacts(&members.iter().map(Vec::as_slice).collect::<Vec<_>>())?
    };
    // Single-artifact inspection already decoded and validated the input and
    // canonically encoded it above. It publishes no new file. Actual minting,
    // repacking and multi-member banks retain the output read-back check.
    if !(inspect && shapes.len() == 1) {
        for (name, symbols, states) in &shapes {
            let checked = Bank::from_bytes(&encoded)?;
            let rebound = checked.get(name)?.ok_or("read-back lost a language")?;
            if rebound.state_count() != *states || rebound.symbol_count() != *symbols {
                return Err("artifact read-back shape differs".into());
            }
        }
    }
    let target = output.unwrap_or_else(|| {
        if inspect {
            PathBuf::from(paths[0])
        } else {
            Path::new(paths[0]).with_extension("folio")
        }
    });
    if !inspect {
        write_artifact(&target, &encoded)?;
    }
    println!(
        "artifact v{}: {} languages, {} bytes  {}",
        Bank::FORMAT_VERSION,
        shapes.len(),
        encoded.len(),
        target.display()
    );
    for (name, symbols, states) in shapes {
        println!("  {}: {} symbols, {} states", name, symbols, states);
    }
    Ok(0)
}

fn write_artifact(path: &Path, bytes: &[u8]) -> io::Result<()> {
    let mut temporary = path.as_os_str().to_owned();
    temporary.push(format!(".tmp-{}", std::process::id()));
    let temporary = PathBuf::from(temporary);
    let mut file = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&temporary)?;
    let result = (|| {
        file.write_all(bytes)?;
        file.sync_all()?;
        fs::rename(&temporary, path)
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    result
}

fn grammar_command(args: &[String]) -> Result<u8> {
    let (path, flags) = args.split_first().ok_or("grammar needs a grammar path")?;
    let mut rules = false;
    let mut conflicts = false;
    let mut trace = false;
    let mut growth = None;
    let mut language = None;
    for flag in flags {
        match flag.as_str() {
            "--rules" => rules = true,
            "--conflicts" => conflicts = true,
            "--trace" => trace = true,
            value if value.starts_with("--growth=") => growth = Some(value[9..].parse::<u32>()?),
            value if value.starts_with("--language=") => language = Some(&value[11..]),
            _ => return Err(format!("unsupported grammar option {flag}").into()),
        }
    }
    let grammar = if trace || growth.is_some() {
        let bytes = read(path, ArtifactLimits::default().bytes)?;
        if bytes.iter().find(|b| !b.is_ascii_whitespace()) == Some(&b'{') {
            let customary = customary_source(path, &bytes, None)?;
            let mut report = CompileReport::default();
            let result = CompiledGrammar::compile_with_diagnostics(
                &bytes,
                customary.as_deref(),
                CompileOptions::default(),
                growth,
                &mut report,
            );
            if trace || result.is_err() {
                construction_report(&report, &mut io::stderr().lock())?;
            }
            let grammar = result?;
            if language.is_some_and(|wanted| wanted != grammar.name()) {
                return Err(format!("{path} has no language {}", language.unwrap()).into());
            }
            grammar
        } else {
            if growth.is_some() {
                return Err("--growth applies to original grammar JSON; persisted tables are validated without construction".into());
            }
            let grammar = load_grammar_bytes(path, &bytes, language, None)?;
            eprintln!("joints: persisted tables validated; no construction passes ran");
            grammar
        }
    } else {
        load_grammar(path, language)?
    };
    let mut rhs = 0usize;
    let mut empty = 0usize;
    let mut longest = 0usize;
    for (_, p) in grammar.productions() {
        rhs += p.steps.len();
        empty += usize::from(p.steps.is_empty());
        longest = longest.max(p.steps.len());
    }
    println!(
        "{}\n  symbols        {}\n  productions    {} ({} empty, {} RHS symbols, longest {})\n  fields         {}\n  states         {}\n  limitations    {:?}",
        grammar.name(),
        grammar.symbol_count(),
        grammar.productions().len(),
        empty,
        rhs,
        longest,
        grammar.fields().len(),
        grammar.state_count(),
        grammar.limitations()
    );
    if conflicts {
        for conflict in grammar.conflict_diagnostics() {
            println!("  {conflict:?}");
        }
    }
    if rules {
        let fields = grammar.fields().collect::<BTreeMap<_, _>>();
        for (id, p) in grammar.productions() {
            println!(
                "  {}: {} [dynamic {}]",
                id.index(),
                production_text(&grammar, p.lhs, p.steps.iter().map(|s| s.symbol), None),
                p.dynamic_precedence
            );
            for (at, step) in p.steps.iter().enumerate() {
                if step.field.is_some() || step.alias.is_some() || step.reserved.is_some() {
                    println!(
                        "    step {at}: field {:?}, alias {:?}, reserved {:?}",
                        step.field.and_then(|f| fields.get(&f).copied()),
                        step.alias,
                        step.reserved
                    );
                }
            }
        }
    }
    Ok(0)
}

fn construction_report(report: &CompileReport, out: &mut impl Write) -> io::Result<()> {
    for round in &report.rounds {
        writeln!(
            out,
            "joints: pass {} {:?}: states {:?}, items {:?}, state limit {}, work {}..{}, contested {}, residual {}, priority-sensitive {}, completed {}",
            round.pass,
            round.stage,
            round.states,
            round.items,
            round.state_limit,
            round.work_before,
            round.work_after,
            round.contested,
            round.residual,
            round.priority_sensitive,
            round.completed
        )?;
    }
    writeln!(
        out,
        "joints: table construction complete {}, work {}, growth state limit {:?}, report truncated {}",
        report.tables_complete, report.work, report.growth_state_limit, report.truncated
    )
}

fn lex_command(args: &[String]) -> Result<u8> {
    let (grammar_path, args) = args.split_first().ok_or("lex needs a grammar path")?;
    let (path, flags) = args.split_first().ok_or("lex needs a source path")?;
    let mut language = None;
    for flag in flags {
        if let Some(name) = flag.strip_prefix("--language=") {
            language = Some(name);
        } else {
            return Err(format!("unsupported lex option {flag}").into());
        }
    }
    let grammar = load_grammar(grammar_path, language)?;
    let source = read(path, ParseLimits::default().source_bytes)?;
    let start = Instant::now();
    let walked = grammar.lexical_walk(&source, ParseLimits::default().lexical_steps)?;
    let micros = start.elapsed().as_micros();
    let mut out = io::BufWriter::new(io::stdout().lock());
    for token in &walked.tokens {
        write!(
            out,
            "{:>7} {:>4}  {:<24}",
            token.start,
            token.end - token.start,
            grammar
                .symbol_name(token.symbol)
                .ok_or("lexical symbol is missing")?
        )?;
        let bytes = &source[token.start..token.end];
        for &b in bytes.iter().take(48) {
            match b {
                b'\n' => out.write_all(b"\\n")?,
                b'\r' => out.write_all(b"\\r")?,
                b'\t' => out.write_all(b"\\t")?,
                _ => out.write_all(&[b])?,
            }
        }
        if bytes.len() > 48 {
            write!(out, "… +{}", bytes.len() - 48)?;
        }
        writeln!(out)?;
    }
    writeln!(
        out,
        "\n{}: {} tokens over {} bytes ({} covered) in {} us",
        grammar.name(),
        walked.tokens.len(),
        source.len(),
        walked.covered,
        micros
    )?;
    writeln!(
        out,
        "  admitted context-free: no parse state gates these; use `parse` for the real stream"
    )?;
    writeln!(
        out,
        "  stateful scanner hands are not asked without parser permissions; {} extra bytes skipped, {} lexical work",
        walked.skipped, walked.work
    )?;
    let mut roles = BTreeMap::<_, Vec<_>>::new();
    for (symbol, role) in grammar.external_bindings() {
        roles.entry(role.label()).or_default().push(symbol);
    }
    for (role, symbols) in roles {
        write!(out, "  {} terminal(s) bound to {role}:", symbols.len())?;
        for &symbol in symbols.iter().take(8) {
            write!(out, " {}", grammar.symbol_name(symbol).unwrap())?;
        }
        if symbols.len() > 8 {
            write!(out, " +{} more", symbols.len() - 8)?;
        }
        writeln!(out)?;
    }
    if let Some(at) = walked.stray {
        writeln!(out, "  stray byte at {at}: no lexical terminal begins here")?;
    }
    out.flush()?;
    Ok(u8::from(walked.stray.is_some()))
}

fn survey_command(args: &[String]) -> Result<u8> {
    let (path, args) = args.split_first().ok_or("survey needs a grammar path")?;
    let mut paths = vec![];
    let mut exact = false;
    let mut dump = false;
    let mut confess = false;
    let (mut entries, mut limbs, mut floor, mut churn) = (256, None, None, None);
    let mut remaining = 1_000_000_000usize;
    let mut language = None;
    let mut args = args.iter();
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--exact" => exact = true,
            "--dump" => dump = true,
            "--confess" => confess = true,
            "--entries" => entries = args.next().ok_or("--entries needs a count")?.parse()?,
            "--limbs" => limbs = Some(args.next().ok_or("--limbs needs a count")?.parse()?),
            "--fan" => floor = Some(args.next().ok_or("--fan needs a count")?.parse()?),
            "--churn" => churn = Some(args.next().ok_or("--churn needs a count")?.parse()?),
            "--work" => remaining = args.next().ok_or("--work needs a count")?.parse()?,
            flag if flag.starts_with("--language=") => language = Some(&flag[11..]),
            "-" => paths.push(arg),
            flag if flag.starts_with('-') => {
                return Err(format!("unsupported survey option {flag}").into());
            }
            _ => paths.push(arg),
        }
    }
    if paths.is_empty() {
        return Err("survey needs at least one source path".into());
    }
    let grammar = load_grammar(path, language)?;
    let mut cursor = grammar.survey_cursor()?;
    let mut limits = cursor.limits();
    if let Some(n) = limbs {
        limits.limbs = n;
    }
    if let Some(n) = floor {
        limits.floor = n;
    }
    if let Some(n) = churn.filter(|&n| n != 0) {
        limits.births_per_token = n;
    }
    cursor.set_limits(limits)?;
    cursor.set_exact(exact);
    cursor.set_confess(confess);
    let declared = grammar
        .conflict_diagnostics()
        .iter()
        .filter(|c| c.class == ConflictClass::Declared)
        .count();
    let residual = grammar
        .conflict_diagnostics()
        .iter()
        .filter(|c| c.class == ConflictClass::Residual)
        .count();
    println!(
        "{}  {} states, {} terminals, {} contested ({} declared, {} residual)",
        grammar.name(),
        grammar.state_count(),
        grammar.lexical_rules().count(),
        grammar.conflict_diagnostics().len(),
        declared,
        residual
    );
    println!(
        "  speculative declared-action explorer; {:?} fusion; finite exploration work budget {remaining}",
        cursor.fusion()
    );
    let mut session = grammar.session();
    session.set_recovery(Recovery::None);
    session.set_supply(Supply::Disabled);
    session.set_trace_enabled(true);
    let mut worst = 0;
    let (mut agreed, mut disagreed, mut refused, mut largest_rank, mut largest_residue) =
        (0, 0, 0, 0, 0);
    for path in paths {
        let parsed = (|| -> Result<TreeSnapshot> {
            let source = read(path, ParseLimits::default().source_bytes)?;
            Ok(session.parse_partial(&source)?)
        })();
        let tree = match parsed {
            Ok(tree) => tree,
            Err(error) => {
                eprintln!("joints-rs: {path}: {error}");
                worst = 2;
                continue;
            }
        };
        if tree.stop() != Stop::Accepted {
            worst = worst.max(1);
        }
        let tokens = session
            .selected_tokens()
            .ok_or("parser did not retain selected token receipts")?;
        println!(
            "\n  {path}  {} bytes -> {} tokens, {}",
            tree.source().len(),
            tokens.len(),
            if tree.stop() == Stop::Accepted {
                "accepted"
            } else {
                "partial selected prefix"
            }
        );
        if tokens.is_empty() {
            println!("    no structural tokens; nothing measured");
            continue;
        }
        let symbols = tokens.iter().map(|t| t.symbol).collect::<Vec<_>>();
        let mut sampled = BTreeSet::new();
        if entries == 0 || entries >= grammar.state_count() {
            for i in 0..grammar.state_count() {
                sampled.insert(grammar.state_id(i).unwrap());
            }
        } else {
            for i in 0..entries {
                let index =
                    ((i as u128) * (grammar.state_count() as u128) / (entries as u128)) as usize;
                sampled.insert(grammar.state_id(index).unwrap());
            }
        }
        sampled.extend(tokens.iter().map(|t| t.entry));
        let sampled = sampled.into_iter().collect::<Vec<_>>();
        println!(
            "    surveyed from {} of {} entry states, including every witnessed entry",
            sampled.len(),
            grammar.state_count()
        );
        let mut cuts = vec![];
        for span in [4, 8, 16, 32, 128] {
            let mut edges = (0..tokens.len()).step_by(span).collect::<Vec<_>>();
            edges.push(tokens.len());
            cuts.push(("tok", span, edges));
        }
        for span in [1024, 4096, 16384] {
            let mut edges = vec![0];
            let mut mark = span;
            for (i, t) in tokens.iter().enumerate() {
                if t.span.start() < mark {
                    continue;
                }
                if edges.last() != Some(&i) {
                    edges.push(i);
                }
                while mark <= t.span.start() {
                    mark = mark.checked_add(span).ok_or("byte cut overflow")?;
                }
            }
            if edges.last() != Some(&tokens.len()) {
                edges.push(tokens.len());
            }
            cuts.push(("byte", span, edges));
        }
        let mut actual_store = grammar.effect_store();
        let actual = match session.product_range(
            0..tokens.last().unwrap().moves.end,
            &mut actual_store,
            remaining,
        ) {
            Ok((effect, work)) => {
                remaining = remaining.saturating_sub(work);
                // Reserve a conservative bound for the final owned view too.
                if let Some(left) = remaining.checked_sub(work.saturating_add(1)) {
                    remaining = left;
                    Some(actual_store.describe(effect)?)
                } else {
                    None
                }
            }
            Err(error) => {
                // A failed concrete fold does not return its partial bill.
                // Reserve its full allowance so later files cannot reuse it.
                remaining = 0;
                println!("    actual-move reference refused: {error}");
                None
            }
        };
        for (unit, span, edges) in cuts {
            let started = Instant::now();
            let mut ranks = vec![];
            let mut domains = vec![];
            let mut pairs = 0usize;
            let mut defined = 0usize;
            let mut plural = 0usize;
            let mut landing = 0;
            let mut reasons = BTreeMap::<String, usize>::new();
            let mut measurement_refused = false;
            let mut shown = !dump;
            for range in edges.windows(2) {
                let (lo, hi) = (range[0], range[1]);
                let mut shapes = BTreeSet::new();
                let mut domain = 0usize;
                for &entry in &sampled {
                    if remaining == 0 {
                        measurement_refused = true;
                        break;
                    }
                    remaining -= 1;
                    cursor.set_work_limit(limits.work.min(remaining));
                    let result = cursor.run(entry, &symbols[lo..hi])?;
                    remaining = remaining.saturating_sub(cursor.work());
                    pairs += 1;
                    if let Some(ys) = result.yields() {
                        domain += 1;
                        defined += 1;
                        plural += usize::from(ys.len() > 1);
                        for y in ys {
                            landing = landing.max(y.landings);
                            let copy = cursor.description_work(y.effect)?;
                            if copy > remaining {
                                measurement_refused = true;
                                break;
                            }
                            cursor.set_work_limit(remaining);
                            let description = cursor.describe(y.effect)?;
                            remaining = remaining.saturating_sub(cursor.work());
                            if !shown {
                                println!(
                                    "      tokens [{lo}, {hi}) from {}: {description:?}",
                                    entry.index()
                                );
                            }
                            match description {
                                EffectDescription::Run { ledger, push, .. } => {
                                    shapes.insert((ledger.len(), push));
                                }
                                EffectDescription::Identity => {
                                    shapes.insert((0, vec![]));
                                }
                                EffectDescription::Zero => {}
                            }
                        }
                    } else if let Some((at, reason, limbs)) = result.refusal() {
                        *reasons.entry(format!("{reason:?}")).or_default() += 1;
                        if confess {
                            if !result.confession_complete() {
                                println!(
                                    "      refusal confession omitted at the diagnostic-word ceiling"
                                );
                            }
                            let words = result
                                .confession()
                                .iter()
                                .fold(0usize, |sum, l| {
                                    sum.saturating_add(l.floors.len())
                                        .saturating_add(l.pushed.len())
                                        .saturating_add(l.landings.len())
                                        .saturating_add(
                                            l.ledger
                                                .iter()
                                                .map(|c| {
                                                    constraint_words(&c.states).saturating_add(
                                                        constraint_words(&c.symbols),
                                                    )
                                                })
                                                .fold(0usize, usize::saturating_add),
                                        )
                                })
                                .saturating_mul(32);
                            if let Some(left) = remaining.checked_sub(words) {
                                remaining = left;
                                println!(
                                    "      refused tokens [{lo}, {hi}) from {} at {}: {reason:?}, {limbs} limbs; {:?}",
                                    entry.index(),
                                    lo + at,
                                    result.confession()
                                );
                            } else {
                                println!(
                                    "      refused tokens [{lo}, {hi}): {reason:?}; confession exceeds remaining work"
                                );
                            }
                        }
                    }
                    if measurement_refused {
                        break;
                    }
                }
                if measurement_refused {
                    break;
                }
                ranks.push(shapes.len());
                domains.push(domain);
                shown = true;
            }
            ranks.sort_unstable();
            domains.sort_unstable();
            largest_rank = largest_rank.max(quantile(&ranks, 99));
            let mut live = vec![cursor.identity()];
            let mut width = 1usize;
            let mut chain_refused = measurement_refused || actual.is_none();
            let mut chain_disagreed = false;
            if !chain_refused {
                for range in edges.windows(2) {
                    let (lo, hi) = (range[0], range[1]);
                    if remaining == 0 {
                        chain_refused = true;
                        break;
                    }
                    cursor.set_work_limit(limits.work.min(remaining));
                    let result = cursor.run(tokens[lo].entry, &symbols[lo..hi])?;
                    remaining = remaining.saturating_sub(cursor.work());
                    let Some(ys) = result.yields() else {
                        if let Some(at) = result.rejected_at() {
                            chain_disagreed = true;
                            println!(
                                "         oracle rejected selected tokens [{lo}, {hi}) at {} from {}",
                                lo + at,
                                tokens[lo].entry.index()
                            );
                        } else {
                            chain_refused = true;
                            println!(
                                "         oracle refused [{lo}, {hi}) from {}: {result:?}",
                                tokens[lo].entry.index()
                            );
                        }
                        break;
                    };
                    let Some(left) = remaining.checked_sub(ys.len()) else {
                        chain_refused = true;
                        break;
                    };
                    remaining = left;
                    let ways = ys.iter().map(|y| y.effect).collect::<Vec<_>>();
                    cursor.set_work_limit(limits.work.min(remaining));
                    let product = cursor.product_grounded(&live, &ways)?;
                    remaining = remaining.saturating_sub(cursor.work());
                    let Some(effects) = product.effects() else {
                        chain_refused = true;
                        println!(
                            "         oracle product refused [{lo}, {hi}): {:?}",
                            product.refusal()
                        );
                        break;
                    };
                    if effects.is_empty() {
                        chain_disagreed = true;
                        println!("         oracle has no grounded product at [{lo}, {hi})");
                        break;
                    }
                    let Some(left) = remaining.checked_sub(effects.len()) else {
                        chain_refused = true;
                        break;
                    };
                    remaining = left;
                    live = effects.to_vec();
                    width = width.max(live.len());
                }
            }
            if !chain_refused && !chain_disagreed {
                cursor.set_work_limit(limits.work.min(remaining));
                let whole = cursor.run(tokens[0].entry, &symbols)?;
                remaining = remaining.saturating_sub(cursor.work());
                if let Some(ys) = whole.yields() {
                    let comparisons = ys.len().saturating_mul(live.len().saturating_add(1));
                    let has_work = if let Some(left) = remaining.checked_sub(comparisons) {
                        remaining = left;
                        true
                    } else {
                        chain_refused = true;
                        false
                    };
                    let mut grounded = 0;
                    for y in ys.iter().filter(|_| has_work) {
                        if cursor.grounded(y.effect)? {
                            grounded += 1;
                            if !live.contains(&y.effect) {
                                chain_disagreed = true;
                            }
                        }
                    }
                    if grounded == 0 {
                        if has_work {
                            chain_disagreed = true;
                        }
                    } else if let Some(actual) = &actual {
                        cursor.set_work_limit(remaining);
                        match cursor.contains_actual(&live, actual) {
                            Ok(found) => {
                                chain_disagreed |= !found;
                            }
                            Err(error) => {
                                println!("         actual-move comparison refused: {error}");
                                chain_refused = true;
                            }
                        }
                        remaining = remaining.saturating_sub(cursor.work());
                    }
                } else if whole.rejected_at().is_some() {
                    chain_disagreed = true;
                    println!("         whole-stream oracle rejected a selected prefix");
                } else {
                    chain_refused = true;
                    println!("         whole-stream oracle refused: {whole:?}");
                }
            }
            let verdict = if chain_refused {
                refused += 1;
                "broken".to_owned()
            } else if chain_disagreed {
                disagreed += 1;
                "DISAGREED".to_owned()
            } else {
                agreed += 1;
                largest_residue = largest_residue.max(width);
                format!("agreed residue<={width}")
            };
            println!(
                "    {unit:>4} {span:<6} {:>5}/{} segments · rank med {} p99 {} · domain med {} p99 {} · defined {:.2}% plural {:.2}% · landing<={landing} · {verdict} · {} ms",
                ranks.len(),
                edges.len() - 1,
                quantile(&ranks, 50),
                quantile(&ranks, 99),
                quantile(&domains, 50),
                quantile(&domains, 99),
                percentage(defined, pairs),
                percentage(plural, pairs),
                started.elapsed().as_millis()
            );
            if !reasons.is_empty() {
                println!("         per-entry refusals: {reasons:?}");
            }
            if measurement_refused {
                println!(
                    "         command work ceiling reached; remaining entries/segments were not measured"
                );
            }
        }
    }
    let total = agreed + disagreed + refused;
    print!("\nworst p99 rank {largest_rank} · widest residue {largest_residue} · ");
    if total == 0 {
        println!("nothing measured");
        return Ok(worst.max(1));
    }
    print!("{agreed}/{total} chains held");
    if disagreed > 0 {
        print!(" · {disagreed} DISAGREED");
    }
    if refused > 0 {
        print!(" · {refused} refused at a ceiling");
    }
    println!();
    Ok(worst.max(u8::from(agreed != total)))
}

fn constraint_words<T>(c: &Constraint<T>) -> usize {
    match c {
        Constraint::Any => 1,
        Constraint::Finite(v) => v.len().saturating_add(1),
    }
}
fn quantile(sorted: &[usize], percent: usize) -> usize {
    if sorted.is_empty() {
        0
    } else {
        sorted[(sorted.len().saturating_mul(percent) / 100).min(sorted.len() - 1)]
    }
}
#[expect(
    clippy::cast_precision_loss,
    reason = "Display percentages intentionally round large counters; the stored counts remain integers."
)]
fn percentage(n: usize, total: usize) -> f64 {
    if total == 0 {
        0.0
    } else {
        100.0 * n as f64 / total as f64
    }
}

fn production_text(
    grammar: &CompiledGrammar,
    lhs: SymbolId,
    rhs: impl Iterator<Item = SymbolId>,
    dot: Option<usize>,
) -> String {
    let mut text = format!("{} ->", grammar.symbol_name(lhs).unwrap_or("<unknown>"));
    let rhs: Vec<_> = rhs.collect();
    for (at, symbol) in rhs.iter().enumerate() {
        if dot == Some(at) {
            text.push_str(" .");
        }
        text.push(' ');
        text.push_str(grammar.symbol_name(*symbol).unwrap_or("<unknown>"));
    }
    if dot == Some(rhs.len()) {
        text.push_str(" .");
    }
    text
}

fn state_command(args: &[String]) -> Result<u8> {
    let (path, args) = args.split_first().ok_or("state needs a grammar path")?;
    let (form, rest) = args
        .split_first()
        .ok_or("state needs a number or --census/--holding/--chain")?;
    let grammar = load_grammar(path, None)?;
    let mut work = 100_000_000usize;
    let productions = grammar.productions().collect::<BTreeMap<_, _>>();
    match form.as_str() {
        "--holding" => {
            if rest.len() != 1 {
                return Err("--holding needs exactly one quoted item".into());
            }
            let (lhs, body) =
                rest[0]
                    .split_once("->")
                    .map_or((None, rest[0].as_str()), |(lhs, body)| {
                        let lhs = lhs.trim();
                        (
                            if lhs.is_empty() || lhs == "*" {
                                None
                            } else {
                                Some(lhs)
                            },
                            body,
                        )
                    });
            let mut rhs = vec![];
            let mut dot = None;
            for word in body.split_ascii_whitespace() {
                if word == "." {
                    if dot.replace(rhs.len()).is_some() {
                        return Err("item has two dots".into());
                    }
                } else {
                    rhs.push(word);
                }
            }
            let mut states = 0;
            let mut items = 0;
            for index in 0..grammar.state_count() {
                let state = grammar.state_id(index).unwrap();
                let mut seen = BTreeSet::new();
                for &item in grammar.state_items(state).unwrap() {
                    for &id in grammar
                        .cursor_histories(item)
                        .ok_or("kernel has no authored history")?
                    {
                        let p = productions[&id];
                        diagnostic_charge(&mut work, 1usize.saturating_add(p.steps.len()))?;
                        if dot.is_some_and(|d| d != item.dot)
                            || lhs.is_some_and(|name| Some(name) != grammar.symbol_name(p.lhs))
                            || p.steps.len() != rhs.len()
                            || !p
                                .steps
                                .iter()
                                .zip(&rhs)
                                .all(|(step, name)| grammar.symbol_name(step.symbol) == Some(*name))
                        {
                            continue;
                        }
                        if seen.insert((id, item.dot)) {
                            println!(
                                "{index}: {}",
                                production_text(
                                    &grammar,
                                    p.lhs,
                                    p.steps.iter().map(|s| s.symbol),
                                    Some(item.dot)
                                )
                            );
                            items += 1;
                        }
                    }
                }
                states += usize::from(!seen.is_empty());
            }
            println!(
                "\n{states} of {} state(s) hold a kernel item matching `{}` ({items} concrete histories)",
                grammar.state_count(),
                rest[0]
            );
            if dot.is_none() {
                println!("  no dot in the query: any dot position matched");
            }
            Ok(u8::from(states == 0))
        }
        "--census" => {
            if rest.is_empty() {
                return Err("--census needs at least one terminal".into());
            }
            println!("{}: {} states", grammar.name(), grammar.state_count());
            let mut found = 0;
            for name in rest {
                let Some((symbol, _)) = grammar
                    .symbols()
                    .find(|(_, s)| s.name == *name && s.lexis.is_some())
                else {
                    println!("\n{name}\n  no such terminal");
                    continue;
                };
                found += 1;
                let mut shifts = 0;
                let mut follows = 0;
                let mut company = vec![];
                let mut rivals = BTreeSet::new();
                for at in 0..grammar.state_count() {
                    let state = grammar.state_id(at).unwrap();
                    let row = grammar.action_row(state).unwrap();
                    diagnostic_charge(&mut work, row.len().saturating_mul(3).saturating_add(1))?;
                    let row = row.collect::<Vec<_>>();
                    diagnostic_charge(
                        &mut work,
                        row.iter()
                            .map(|(_, actions)| actions.len())
                            .fold(0usize, usize::saturating_add)
                            .saturating_mul(3),
                    )?;
                    let actions = row
                        .iter()
                        .find_map(|(on, actions)| {
                            (*on == Lookahead::Terminal(symbol)).then_some(*actions)
                        })
                        .unwrap_or(&[]);
                    if actions
                        .iter()
                        .any(|a| matches!(a, Action::Reduce(_) | Action::Accept))
                    {
                        follows += 1;
                    }
                    if actions.iter().any(|a| matches!(a, Action::Shift(_))) {
                        shifts += 1;
                        let beside = row
                            .iter()
                            .filter_map(|(on, actions)| match on {
                                Lookahead::Terminal(other)
                                    if *other != symbol
                                        && actions
                                            .iter()
                                            .any(|a| matches!(a, Action::Shift(_))) =>
                                {
                                    Some(*other)
                                }
                                _ => None,
                            })
                            .collect::<Vec<_>>();
                        company.push(beside.len());
                        rivals.extend(beside);
                    }
                }
                println!(
                    "\n{name}\n  shift in {shifts} state(s), reduce/accept lookahead in {follows}"
                );
                if !company.is_empty() {
                    company.sort_unstable();
                    println!(
                        "  company where it shifts: min {}, median {}, max {}; sole shift in {} state(s)",
                        company[0],
                        company[company.len() / 2],
                        company[company.len() - 1],
                        company.iter().filter(|&&n| n == 0).count()
                    );
                }
                print!("  {} distinct rival(s):", rivals.len());
                for symbol in rivals.iter().take(12) {
                    print!(" {}", grammar.symbol_name(*symbol).unwrap());
                }
                if rivals.len() > 12 {
                    print!(" +{} more", rivals.len() - 12);
                }
                println!();
            }
            Ok(u8::from(found == 0))
        }
        "--chain" => {
            if rest.len() != 1 {
                return Err("--chain needs one state number".into());
            }
            let state = grammar
                .state_id(rest[0].parse()?)
                .ok_or("state number exceeds grammar")?;
            state_chain(&grammar, state)?;
            Ok(0)
        }
        number => {
            if !rest.is_empty() {
                return Err("state number takes no extra arguments".into());
            }
            let state = grammar
                .state_id(number.parse()?)
                .ok_or("state number exceeds grammar")?;
            println!(
                "state {} of {}\n\n  actual normalized kernel items:",
                state.index(),
                grammar.name()
            );
            for &item in grammar.state_items(state).unwrap() {
                let p = productions[&item.production];
                println!(
                    "    {}",
                    production_text(
                        &grammar,
                        p.lhs,
                        p.steps.iter().map(|s| s.symbol),
                        Some(item.dot)
                    )
                );
                let histories = grammar
                    .cursor_histories(item)
                    .ok_or("kernel history missing")?;
                if histories.len() > 1 {
                    println!(
                        "      {} concrete authored histories: {:?}",
                        histories.len(),
                        histories.iter().map(|id| id.index()).collect::<Vec<_>>()
                    );
                }
            }
            let row = grammar.action_row(state).unwrap().collect::<Vec<_>>();
            let mut shifted = BTreeSet::new();
            let mut followed = BTreeSet::new();
            for shift in [true, false] {
                println!(
                    "\n  {}:",
                    if shift {
                        "shifts"
                    } else {
                        "reduce/accept lookaheads"
                    }
                );
                for (on, actions) in &row {
                    let subset = actions
                        .iter()
                        .filter(|a| matches!(a, Action::Shift(_)) == shift)
                        .collect::<Vec<_>>();
                    if subset.is_empty() {
                        continue;
                    }
                    if shift {
                        shifted.insert(*on);
                    } else {
                        followed.insert(*on);
                    }
                    let name = match on {
                        Lookahead::Terminal(s) => grammar.symbol_name(*s).unwrap(),
                        Lookahead::End => "$end",
                    };
                    println!("    {name}: {subset:?}");
                }
            }
            println!(
                "\n  shift {}, reduce/accept lookahead {}, union {} (GLR cells may occur in both)",
                shifted.len(),
                followed.len(),
                shifted.union(&followed).count()
            );
            Ok(0)
        }
    }
}

fn state_chain(grammar: &CompiledGrammar, target: StateId) -> Result<()> {
    let mut work = 100_000_000usize;
    let mut charge = |n: usize| -> Result<()> {
        work = work
            .checked_sub(n)
            .ok_or("state-chain work limit exceeded")?;
        Ok(())
    };
    let mut backwards = vec![vec![]; grammar.state_count()];
    for at in 0..grammar.state_count() {
        let state = grammar.state_id(at).unwrap();
        for (symbol, to) in grammar.state_transitions(state).unwrap() {
            charge(1)?;
            backwards[to.index()].push((state, symbol));
        }
    }
    let mut arrivals = vec![None; grammar.state_count()];
    let start = grammar.start_state();
    let mut queue = VecDeque::from([start]);
    arrivals[start.index()] = Some((start, grammar.start_symbol()));
    while let Some(state) = queue.pop_front() {
        if state == target {
            break;
        }
        for (symbol, to) in grammar.state_transitions(state).unwrap() {
            charge(1)?;
            if arrivals[to.index()].is_none() {
                arrivals[to.index()] = Some((state, symbol));
                queue.push_back(to);
            }
        }
    }
    println!("state {} of {}", target.index(), grammar.name());
    if arrivals[target.index()].is_none() {
        println!("  no arrival from the document start (may be an auxiliary extra entry)");
    } else {
        let mut path = vec![];
        let mut at = target;
        while at != start {
            charge(1)?;
            let (from, symbol) = arrivals[at.index()].ok_or("broken arrival chain")?;
            path.push((from, symbol, at));
            at = from;
        }
        path.reverse();
        println!("  shortest graph arrival:");
        for (from, symbol, to) in path {
            println!(
                "    {} --{}--> {}",
                from.index(),
                grammar.symbol_name(symbol).unwrap(),
                to.index()
            );
        }
    }
    let productions = grammar.productions().collect::<BTreeMap<_, _>>();
    let mut seen = BTreeSet::new();
    for &item in grammar.state_items(target).unwrap() {
        for &id in grammar
            .cursor_histories(item)
            .ok_or("kernel history missing")?
        {
            let p = productions[&id];
            if item.dot != p.steps.len() || !seen.insert(id) {
                continue;
            }
            charge(p.steps.len())?;
            let mut origins = BTreeSet::from([target]);
            for step in p.steps.iter().rev() {
                let mut next = BTreeSet::new();
                for state in origins {
                    for &(from, symbol) in &backwards[state.index()] {
                        charge(1)?;
                        if symbol == step.symbol {
                            next.insert(from);
                        }
                    }
                }
                origins = next;
            }
            let mut exposed = BTreeSet::new();
            for &state in &origins {
                for (symbol, to) in grammar.state_transitions(state).unwrap() {
                    charge(1)?;
                    if symbol == p.lhs {
                        exposed.insert(to);
                    }
                }
            }
            println!(
                "  completed {}",
                production_text(
                    grammar,
                    p.lhs,
                    p.steps.iter().map(|s| s.symbol),
                    Some(item.dot)
                )
            );
            println!(
                "    {} exact handle origin(s): {:?}; {} exposed goto state(s): {:?}",
                origins.len(),
                origins
                    .iter()
                    .take(12)
                    .map(|s| s.index())
                    .collect::<Vec<_>>(),
                exposed.len(),
                exposed
                    .iter()
                    .take(12)
                    .map(|s| s.index())
                    .collect::<Vec<_>>()
            );
        }
    }
    Ok(())
}

fn diagnostic_charge(remaining: &mut usize, amount: usize) -> Result<()> {
    *remaining = remaining
        .checked_sub(amount)
        .ok_or("state diagnostic work limit exceeded")?;
    Ok(())
}

fn amend_command(args: &[String]) -> Result<u8> {
    let (grammar_path, args) = args.split_first().ok_or("amend needs a grammar path")?;
    let mut path = None;
    let mut edits = vec![];
    let mut all = false;
    let mut quiet = false;
    let mut cold = false;
    let mut language = None;
    let mut policy = DocumentPolicy::Prove;
    for arg in args {
        match arg.as_str() {
            "--all" => all = true,
            "--quiet" => quiet = true,
            "--cold" => cold = true,
            "--policy=prove" => policy = DocumentPolicy::Prove,
            "--policy=snap" => policy = DocumentPolicy::Snap,
            "--policy=whole" => policy = DocumentPolicy::Whole,
            flag if flag.starts_with("--language=") => language = Some(&flag[11..]),
            "-" if path.is_none() => path = Some(arg.as_str()),
            flag if flag.starts_with('-') => {
                return Err(format!("unsupported amend option {flag}").into());
            }
            _ if path.is_none() => path = Some(arg.as_str()),
            _ => edits.push(parse_edit(arg)?),
        }
    }
    let path = path.ok_or("amend needs a source file")?;
    let grammar = load_grammar(grammar_path, language)?;
    let source = read(path, ParseLimits::default().source_bytes)?;
    if cold {
        policy = DocumentPolicy::Cold;
    }
    let opened = Instant::now();
    let mut document = Document::with_options(
        grammar,
        &source,
        DocumentOptions {
            policy,
            ..DocumentOptions::default()
        },
    )?;
    let elapsed = opened.elapsed().as_micros();
    if policy == DocumentPolicy::Snap {
        eprintln!("joints: snap uses exact prefix validation in the native runtime");
    }
    eprintln!(
        "joints: tokens read counts actual token-returning scans, including proof and speculative reads"
    );
    let mut worst = u8::from(document.snapshot().stop() != Stop::Accepted);
    amend_cost(
        &document,
        &format!("{path}: opened"),
        elapsed,
        &mut io::stderr().lock(),
    )?;
    for (span, put) in edits {
        let started = Instant::now();
        document.edit(span, &put)?;
        let elapsed = started.elapsed().as_micros();
        worst = worst.max(u8::from(document.snapshot().stop() != Stop::Accepted));
        let label = format!("{path}: {}..{} +{}", span.start(), span.end(), put.len());
        amend_cost(&document, &label, elapsed, &mut io::stderr().lock())?;
    }
    if !quiet {
        sexp(document.snapshot(), all, &mut io::stdout().lock())?;
    }
    Ok(worst)
}

fn amend_cost(
    document: &Document,
    label: &str,
    micros: u128,
    out: &mut impl Write,
) -> io::Result<()> {
    write!(out, "joints: {label}: ")?;
    write_stop(document.snapshot(), out)?;
    let cost = document.cost();
    writeln!(
        out,
        ", {}/{} leaves reminted at {}, height {}, 0 lifts over 0 bytes, {} tokens read, {micros} us",
        cost.sequence_minted,
        cost.sequence_leaves,
        cost.sequence_start,
        cost.sequence_height,
        cost.read_events
    )
}

fn parse_edit(spelling: &str) -> Result<(ByteSpan, Vec<u8>)> {
    let (cut, put) = spelling
        .split_once('=')
        .ok_or("edit must be FROM..TO=TEXT")?;
    let (from, to) = cut.split_once("..").ok_or("edit must be FROM..TO=TEXT")?;
    if from.is_empty()
        || to.is_empty()
        || !from.bytes().all(|c| c.is_ascii_digit())
        || !to.bytes().all(|c| c.is_ascii_digit())
    {
        return Err(format!("invalid byte span {cut}").into());
    }
    let span = ByteSpan::new(from.parse()?, to.parse()?).ok_or("edit start exceeds its end")?;
    let mut text = Vec::with_capacity(put.len());
    let mut bytes = put.bytes();
    while let Some(byte) = bytes.next() {
        text.push(if byte == b'\\' {
            match bytes.next() {
                Some(b'n') => b'\n',
                Some(b't') => b'\t',
                Some(other) => other,
                None => b'\\',
            }
        } else {
            byte
        });
    }
    Ok((span, text))
}

fn query_command(args: &[String]) -> Result<u8> {
    let (grammar_path, args) = args.split_first().ok_or("query needs a grammar path")?;
    let (query_path, args) = args.split_first().ok_or("query needs a query path")?;
    let mut paths = vec![];
    let mut json = false;
    let mut flat = false;
    let mut quiet = false;
    let mut dead = false;
    let mut language = None;
    let mut foreign = ForeignPolicy::Refuse;
    for arg in args {
        match arg.as_str() {
            "--json" => json = true,
            "--captures" => flat = true,
            "--quiet" => quiet = true,
            "--dead" => dead = true,
            "--foreign=refuse" => foreign = ForeignPolicy::Refuse,
            "--foreign=admit" => foreign = ForeignPolicy::Admit,
            "--foreign=deny" => foreign = ForeignPolicy::Deny,
            flag if flag.starts_with("--language=") => language = Some(&flag[11..]),
            "-" => paths.push(arg),
            flag if flag.starts_with('-') => {
                return Err(format!("unsupported query option {flag}").into());
            }
            _ => paths.push(arg),
        }
    }
    if paths.is_empty() {
        return Err("query needs at least one source path".into());
    }
    if json && flat {
        return Err("--json cannot combine with --captures".into());
    }
    let grammar = load_grammar(grammar_path, language)?;
    let query = Query::compile(
        Arc::clone(&grammar),
        &read(query_path, QueryLimits::default().source_bytes)?,
    )?;
    // Diagnostics belong to stderr so machine output remains one object per file.
    if dead && !quiet {
        for pattern in query.dead_patterns() {
            eprintln!(
                "joints: {query_path}: pattern {} at {}: {}",
                pattern.pattern.index(),
                pattern.at,
                pattern.cause
            );
        }
    }
    let mut session = grammar.session();
    let mut worst = 1;
    let mut out = io::BufWriter::new(io::stdout().lock());
    for path in paths {
        let answer = (|| -> Result<_> {
            let source = read(path, ParseLimits::default().source_bytes)?;
            Ok(session.parse_partial(&source)?)
        })();
        let tree = match answer {
            Ok(tree) => tree,
            Err(error) => {
                eprintln!("joints-rs: {path}: {error}");
                worst = 2;
                continue;
            }
        };
        let matches = match query.execute(&tree, foreign) {
            Ok(matches) => matches,
            Err(error) => {
                eprintln!("joints-rs: {path}: {error}");
                worst = 2;
                continue;
            }
        };
        if !quiet {
            if json {
                query_machine(&query, &tree, path, &matches, &mut out)?;
            } else {
                for (index, found) in matches.iter().enumerate() {
                    if !flat {
                        writeln!(out, "match {index} pattern {}", found.pattern.index())?;
                    }
                    for capture in &found.captures {
                        if flat {
                            write!(out, "{} ", found.pattern.index())?;
                        } else {
                            out.write_all(b"  ")?;
                        }
                        write!(
                            out,
                            "@{} [{}, {}) `",
                            query.capture_name(capture.id).unwrap_or("<unknown>"),
                            capture.node.span().start(),
                            capture.node.span().end()
                        )?;
                        excerpt(capture.node.text(), 40, &mut out)?;
                        out.write_all(b"`\n")?;
                    }
                }
            }
        }
        out.flush()?;
        verdict(&tree, path, &mut io::stderr().lock())?;
        eprintln!(
            "joints: {path}: {} patterns, {} matches, {} captures",
            query.pattern_count(),
            matches.len(),
            matches.iter().map(|m| m.captures.len()).sum::<usize>()
        );
        if worst == 1 && !matches.is_empty() {
            worst = 0;
        }
    }
    Ok(worst)
}

fn query_machine(
    query: &Query,
    tree: &TreeSnapshot,
    path: &str,
    matches: &[QueryMatch<'_>],
    out: &mut impl Write,
) -> io::Result<()> {
    out.write_all(b"{\"language\":")?;
    string(out, tree.grammar().name())?;
    out.write_all(b",\"path\":")?;
    string(out, path)?;
    write!(
        out,
        ",\"patterns\":{},\"accepted\":{},\"sound\":{}",
        query.pattern_count(),
        tree.stop() == Stop::Accepted,
        tree.survey().is_sound()
    )?;
    query_evidence(tree, out)?;
    out.write_all(b",\"matches\":[")?;
    for (index, found) in matches.iter().enumerate() {
        if index > 0 {
            out.write_all(b",")?;
        }
        write!(
            out,
            "{{\"pattern\":{},\"captures\":[",
            found.pattern.index()
        )?;
        for (index, capture) in found.captures.iter().enumerate() {
            if index > 0 {
                out.write_all(b",")?;
            }
            out.write_all(b"{\"name\":")?;
            string(out, query.capture_name(capture.id).unwrap_or("<unknown>"))?;
            write!(
                out,
                ",\"start\":{},\"end\":{}}}",
                capture.node.span().start(),
                capture.node.span().end()
            )?;
        }
        out.write_all(b"]}")?;
    }
    out.write_all(b"]}\n")
}

fn query_evidence(tree: &TreeSnapshot, out: &mut impl Write) -> io::Result<()> {
    out.write_all(b",\"stop\":{")?;
    match tree.stop() {
        Stop::Accepted => out.write_all(b"\"kind\":\"accepted\"")?,
        Stop::Truncated => out.write_all(b"\"kind\":\"truncated\"")?,
        Stop::Stray { at } => write!(out, "\"kind\":\"stray\",\"at\":{at}")?,
        Stop::Unexpected { at, state, .. } => {
            out.write_all(b"\"kind\":\"unexpected\",\"symbol\":")?;
            string(out, tree.stop_symbol().unwrap_or("<unknown>"))?;
            write!(out, ",\"at\":{at},\"state\":{}", state.index())?;
        }
    }
    write!(
        out,
        "}},\"roots\":{},\"mends\":{},\"skipped\":{},\"supplied\":{},\"spurned\":{},\"scars\":[",
        tree.confidence().roots,
        tree.mends(),
        tree.skipped(),
        tree.supplied(),
        tree.spurned()
    )?;
    for (index, repair) in tree.repairs().iter().enumerate() {
        if index > 0 {
            out.write_all(b",")?;
        }
        write!(
            out,
            "{{\"at\":{},\"over\":{}",
            repair.span.start(),
            repair.span.end()
        )?;
        let felled = match repair.kind {
            RepairKind::Deleted { felled } => felled,
            RepairKind::Supplied { .. } => {
                out.write_all(b",\"gave\":")?;
                string(
                    out,
                    tree.repair_symbol(repair)
                        .ok_or_else(|| io::Error::other("repair symbol is missing"))?,
                )?;
                false
            }
        };
        write!(
            out,
            ",\"felled\":{felled},\"heads\":{},\"shifted\":{}}}",
            repair.heads, repair.shifted
        )?;
    }
    let s = tree.survey();
    write!(
        out,
        "],\"survey\":{{\"walked\":{},\"held\":{},\"sound\":{},\"loose\":{},\"disorder\":{},\"torn\":{}}}",
        s.walked,
        s.held,
        s.is_sound(),
        s.loose,
        s.disorder,
        s.torn
    )
}

fn excerpt(bytes: &[u8], shown: usize, out: &mut impl Write) -> io::Result<()> {
    for &b in bytes.iter().take(shown) {
        match b {
            b'\n' => out.write_all(b"\\n")?,
            b'\r' => out.write_all(b"\\r")?,
            b'\t' => out.write_all(b"\\t")?,
            b'`' => out.write_all(b"\\`")?,
            b'\\' => out.write_all(b"\\\\")?,
            0..=31 => write!(out, "\\x{b:02x}")?,
            _ => out.write_all(&[b])?,
        }
    }
    if bytes.len() > shown {
        out.write_all(b"...")?;
    }
    Ok(())
}

/// Preserve the evidence protocol consumed by the existing comparison tools.
fn verdict(tree: &TreeSnapshot, path: &str, out: &mut impl Write) -> io::Result<()> {
    write!(out, "joints: {path}: ")?;
    write_stop(tree, out)?;
    let roots = tree.confidence().roots;
    write!(out, ", {roots} root{}", if roots == 1 { "" } else { "s" })?;
    if tree.mends() > 0 {
        write!(out, ", mended {} over {}B", tree.mends(), tree.skipped())?;
    }
    if tree.supplied() > 0 || tree.spurned() > 0 {
        write!(
            out,
            ", supplied {}, spurned {}",
            tree.supplied(),
            tree.spurned()
        )?;
    }
    let survey = tree.survey();
    write!(out, ", surveyed {} of {} nodes", survey.walked, survey.held)?;
    if !survey.is_sound() {
        write!(
            out,
            ", UNSOUND: {} loose, {} disorder, {} torn",
            survey.loose, survey.disorder, survey.torn
        )?;
    }
    writeln!(out)
}

fn write_stop(tree: &TreeSnapshot, out: &mut impl Write) -> io::Result<()> {
    match tree.stop() {
        Stop::Accepted => out.write_all(b"accepted")?,
        Stop::Truncated => out.write_all(b"truncated")?,
        Stop::Stray { at } => write!(out, "stray byte at {at}")?,
        Stop::Unexpected { at, state, .. } => write!(
            out,
            "unexpected {} at {at} in state {}",
            tree.stop_symbol().unwrap_or("<unknown>"),
            state.index()
        )?,
    }
    Ok(())
}

fn outline(tree: &TreeSnapshot, all: bool, out: &mut impl Write) -> io::Result<()> {
    let mut pending: Vec<_> = tree.roots().map(|node| (node, 0usize)).collect();
    pending.reverse();
    while let Some((node, depth)) = pending.pop() {
        for _ in 0..depth {
            out.write_all(b"  ")?;
        }
        if let Some(field) = node.field() {
            write!(out, "{field}: ")?;
        }
        if node.is_named() {
            write!(out, "{}", node.name())?;
        } else {
            string(out, node.name())?;
        }
        writeln!(out, " [{}, {})", node.span().start(), node.span().end())?;
        let children: Vec<_> = node.children().filter(|n| all || n.is_named()).collect();
        pending.extend(children.into_iter().rev().map(|child| (child, depth + 1)));
    }
    Ok(())
}

fn string(out: &mut impl Write, value: &str) -> io::Result<()> {
    serde_json::to_writer(out, value).map_err(io::Error::other)
}

/// Iterative output keeps deeply nested source from consuming the host stack.
fn machine(tree: &TreeSnapshot, path: &str, all: bool, out: &mut impl Write) -> io::Result<()> {
    out.write_all(b"{\"language\":")?;
    string(out, tree.grammar().name())?;
    out.write_all(b",\"path\":")?;
    string(out, path)?;
    out.write_all(b",\"stop\":{")?;
    match tree.stop() {
        Stop::Accepted => out.write_all(b"\"kind\":\"accepted\"")?,
        Stop::Truncated => out.write_all(b"\"kind\":\"truncated\"")?,
        Stop::Stray { at } => write!(out, "\"kind\":\"stray\",\"at\":{at}")?,
        Stop::Unexpected { at, state, .. } => {
            out.write_all(b"\"kind\":\"unexpected\",\"symbol\":")?;
            string(out, tree.stop_symbol().unwrap_or("<unknown>"))?;
            write!(out, ",\"at\":{at},\"state\":{}", state.index())?;
        }
    }
    let survey = tree.survey();
    write!(
        out,
        "}},\"roots\":{},\"mends\":{},\"skipped\":{},\"supplied\":{},\"spurned\":{},\"scars\":[",
        tree.confidence().roots,
        tree.mends(),
        tree.skipped(),
        tree.supplied(),
        tree.spurned()
    )?;
    for (index, repair) in tree.repairs().iter().enumerate() {
        if index > 0 {
            out.write_all(b",")?;
        }
        write!(
            out,
            "{{\"at\":{},\"over\":{}",
            repair.span.start(),
            repair.span.end()
        )?;
        let felled = match repair.kind {
            RepairKind::Deleted { felled } => felled,
            RepairKind::Supplied { .. } => {
                out.write_all(b",\"gave\":")?;
                string(
                    out,
                    tree.repair_symbol(repair)
                        .ok_or_else(|| io::Error::other("repair symbol is missing"))?,
                )?;
                false
            }
        };
        write!(
            out,
            ",\"felled\":{felled},\"heads\":{},\"shifted\":{}}}",
            repair.heads, repair.shifted
        )?;
    }
    write!(
        out,
        "],\"survey\":{{\"walked\":{},\"held\":{},\"sound\":{},\"loose\":{},\"disorder\":{},\"torn\":{}}},\"tree\":[",
        survey.walked,
        survey.held,
        survey.is_sound(),
        survey.loose,
        survey.disorder,
        survey.torn
    )?;
    enum Task<'a> {
        Node(Node<'a>),
        Close,
        Comma,
    }
    let mut tasks = Vec::new();
    for (index, root) in tree
        .roots()
        .enumerate()
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
    {
        tasks.push(Task::Node(root));
        if index > 0 {
            tasks.push(Task::Comma);
        }
    }
    while let Some(task) = tasks.pop() {
        match task {
            Task::Comma => out.write_all(b",")?,
            Task::Close => out.write_all(b"]}")?,
            Task::Node(node) => {
                out.write_all(b"{\"name\":")?;
                string(out, node.name())?;
                if let Some(field) = node.field() {
                    out.write_all(b",\"field\":")?;
                    string(out, field)?;
                }
                write!(
                    out,
                    ",\"named\":{},\"start\":{},\"end\":{},\"kids\":[",
                    node.is_named(),
                    node.span().start(),
                    node.span().end()
                )?;
                tasks.push(Task::Close);
                let children: Vec<_> = node
                    .children()
                    .filter(|child| all || child.is_named())
                    .collect();
                for (index, child) in children.into_iter().enumerate().rev() {
                    tasks.push(Task::Node(child));
                    if index > 0 {
                        tasks.push(Task::Comma);
                    }
                }
            }
        }
    }
    out.write_all(b"]}\n")
}

fn sexp(tree: &TreeSnapshot, all: bool, out: &mut impl Write) -> io::Result<()> {
    enum Task<'a> {
        Node(Node<'a>),
        Close,
        Space,
    }
    for root in tree.roots() {
        let mut pending = vec![Task::Node(root)];
        while let Some(task) = pending.pop() {
            match task {
                Task::Close => out.write_all(b")")?,
                Task::Space => out.write_all(b" ")?,
                Task::Node(node) => {
                    if let Some(field) = node.field() {
                        write!(out, "{field}: ")?;
                    }
                    if node.is_named() {
                        write!(out, "({}", node.name())?;
                    } else {
                        string(out, node.name())?;
                        continue;
                    }
                    pending.push(Task::Close);
                    let children: Vec<_> = node
                        .children()
                        .filter(|child| all || child.is_named())
                        .collect();
                    // A leading space is part of each child task, avoiding recursion.
                    for child in children.into_iter().rev() {
                        pending.push(Task::Node(child));
                        pending.push(Task::Space);
                    }
                }
            }
        }
        out.write_all(b"\n")?;
    }
    Ok(())
}
