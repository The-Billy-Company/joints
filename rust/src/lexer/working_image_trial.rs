//! Private working-tier falsifier. Never compiled without both test and trial feature.
//! Observer/output storage is diagnostic work outside parser/image accounting.
use super::*;
use crate::CompiledGrammar;
use irgx::{ImageBudget, ImageError, ImageLimits, MunchBuilder, MunchImage};
use serde::Serialize;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::cell::RefCell;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Arc;

const MAX_EVENTS: usize = 4096;
const ALLOCATION: u64 = 256 << 20;
const WORK: u64 = 128_000_000;
const TRANSITIONS: usize = 1 << 20;
const ROOT: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/..");
type Trial<T> = Result<T, String>;

#[derive(Clone, Serialize, Debug, PartialEq, Eq)]
struct Outcome {
    answer: Option<usize>,
    error: Option<String>,
    winners: Vec<u32>,
    remaining: usize,
}
impl Outcome {
    fn of(result: &Result<Option<usize>, irgx::Error>, winners: &[u32], remaining: usize) -> Self {
        Self {
            answer: result.as_ref().ok().copied().flatten(),
            error: result.as_ref().err().map(|e| format!("{e:?}")),
            winners: winners.to_vec(),
            remaining,
        }
    }
}
#[derive(Clone, Serialize)]
struct Question {
    at: usize,
    allow: Option<Vec<u32>>,
    pick: &'static str,
    initial: usize,
}
fn pick_name(pick: Pick) -> &'static str {
    match pick {
        Pick::Longest => "longest",
        Pick::Shortest => "shortest",
    }
}
fn pick_value(pick: &str) -> Pick {
    match pick {
        "longest" => Pick::Longest,
        "shortest" => Pick::Shortest,
        _ => unreachable!(),
    }
}
#[derive(Clone, Serialize)]
struct NativeEvent {
    context: Value,
    lexical_event: usize,
    question: Question,
    fresh: bool,
    admitted: Option<Vec<usize>>,
    empty_permit: Vec<usize>,
    provisional_empty: Vec<usize>,
    eof: bool,
    selection_before: usize,
    selection_after: Option<usize>,
    outcome: Option<Outcome>,
}
#[derive(Clone, Serialize)]
struct LexicalEvent {
    context: Value,
    transitions_before: usize,
    transitions_after: Option<usize>,
    selection_before: usize,
    selection_after: Option<usize>,
    parser_steps_before: usize,
    parser_steps_after: Option<usize>,
    result: Option<String>,
    reconciliation_error: Option<String>,
}
#[derive(Serialize)]
struct Events {
    native: Vec<NativeEvent>,
    lexical: Vec<LexicalEvent>,
}
struct Capture {
    target: usize,
    source: Vec<u8>,
    context: Value,
    lexical: Option<usize>,
    events: Events,
}
thread_local! { static CAPTURE: RefCell<Option<Capture>> = const { RefCell::new(None) }; }
fn observing<T>(f: impl FnOnce(&mut Capture) -> T) -> Option<T> {
    CAPTURE.with(|slot| slot.borrow_mut().as_mut().map(f))
}
pub(crate) struct ContextGuard(Option<Value>);
impl Drop for ContextGuard {
    fn drop(&mut self) {
        if let Some(previous) = self.0.take() {
            observing(|c| c.context = previous);
        }
    }
}
pub(crate) fn context(details: Value) -> ContextGuard {
    ContextGuard(observing(|c| std::mem::replace(&mut c.context, details)))
}
pub(crate) fn call_site(label: &'static str) -> ContextGuard {
    let old = observing(|c| {
        let previous = c.context.clone();
        c.context["call_site"] = json!(label);
        previous
    });
    ContextGuard(old)
}
pub(crate) struct LexicalToken {
    index: usize,
    previous: Option<usize>,
}
pub(crate) fn lexical_before(
    transitions: usize,
    selection: usize,
    steps: usize,
) -> Option<LexicalToken> {
    observing(|c| {
        assert!(
            c.events.lexical.len() < MAX_EVENTS,
            "complete lexical observer exceeded fixed ceiling"
        );
        let index = c.events.lexical.len();
        c.events.lexical.push(LexicalEvent {
            context: c.context.clone(),
            transitions_before: transitions,
            transitions_after: None,
            selection_before: selection,
            selection_after: None,
            parser_steps_before: steps,
            parser_steps_after: None,
            result: None,
            reconciliation_error: None,
        });
        LexicalToken {
            index,
            previous: c.lexical.replace(index),
        }
    })
}
pub(crate) fn lexical_after(
    token: Option<LexicalToken>,
    transitions: usize,
    selection: usize,
    steps: usize,
    result: &Result<Scan, LexError>,
    reconciliation: &Result<(), crate::Error>,
) {
    if let Some(token) = token {
        observing(|c| {
            let event = &mut c.events.lexical[token.index];
            event.transitions_after = Some(transitions);
            event.selection_after = Some(selection);
            event.parser_steps_after = Some(steps);
            event.result = Some(format!("{result:?}"));
            event.reconciliation_error = reconciliation.as_ref().err().map(|e| format!("{e:?}"));
            c.lexical = token.previous;
        });
    }
}
#[expect(
    clippy::too_many_arguments,
    reason = "The test observer records each native call input and both independent work budgets."
)]
pub(crate) fn native_before(
    slate: &Munch,
    source: &[u8],
    at: usize,
    allow: Option<&[u32]>,
    pick: Pick,
    fresh: bool,
    question: LexicalQuestion<'_>,
    transitions: usize,
    selection: usize,
) -> Option<usize> {
    observing(|c| {
        if c.target != std::ptr::from_ref(slate) as usize {
            return None;
        }
        assert_eq!(
            source, c.source,
            "native observation used different source bytes"
        );
        assert!(
            c.events.native.len() < MAX_EVENTS,
            "complete native observer exceeded fixed ceiling"
        );
        assert!(c.context["stack"].is_array() && c.context["call_site"].is_string());
        let lexical_event = c
            .lexical
            .expect("native observation lacks enclosing lexical call");
        let index = c.events.native.len();
        c.events.native.push(NativeEvent {
            context: c.context.clone(),
            lexical_event,
            question: Question {
                at,
                allow: allow.map(<[u32]>::to_vec),
                pick: pick_name(pick),
                initial: transitions,
            },
            fresh,
            admitted: question
                .admitted
                .map(|v| v.iter().map(|s| s.index()).collect()),
            empty_permit: question.empty_permit.iter().map(|s| s.index()).collect(),
            provisional_empty: question
                .provisional_empty
                .iter()
                .map(|s| s.index())
                .collect(),
            eof: question.eof,
            selection_before: selection,
            selection_after: None,
            outcome: None,
        });
        Some(index)
    })
    .flatten()
}
pub(crate) fn native_after(
    index: Option<usize>,
    result: &Result<Option<usize>, irgx::Error>,
    winners: &[u32],
    transitions: usize,
    selection: usize,
) {
    if let Some(index) = index {
        observing(|c| {
            let event = &mut c.events.native[index];
            event.outcome = Some(Outcome::of(result, winners, transitions));
            event.selection_after = Some(selection);
        });
    }
}
struct CaptureGuard;
impl CaptureGuard {
    fn start(slate: &Munch, source: &[u8]) -> Self {
        CAPTURE.with(|slot| {
            assert!(slot.borrow().is_none());
            *slot.borrow_mut() = Some(Capture {
                target: std::ptr::from_ref(slate) as usize,
                source: source.to_vec(),
                context: Value::Null,
                lexical: None,
                events: Events {
                    native: vec![],
                    lexical: vec![],
                },
            });
        });
        Self
    }
    fn take(self) -> (Events, bool, Option<usize>) {
        let capture = CAPTURE.with(|slot| slot.borrow_mut().take().unwrap());
        let complete = capture.context.is_null()
            && capture.lexical.is_none()
            && !capture.events.native.is_empty()
            && capture
                .events
                .native
                .iter()
                .all(|e| e.outcome.is_some() && e.selection_after.is_some())
            && capture.events.lexical.iter().all(|e| {
                e.result.is_some() && e.transitions_after.is_some() && e.selection_after.is_some()
            });
        (capture.events, complete, capture.lexical)
    }
}
impl Drop for CaptureGuard {
    fn drop(&mut self) {
        CAPTURE.with(|slot| {
            slot.borrow_mut().take();
        });
    }
}
fn require(condition: bool, label: &str) -> Trial<()> {
    if condition { Ok(()) } else { Err(label.into()) }
}
fn digest(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .fold(String::new(), |mut text, b| {
            use std::fmt::Write as _;
            write!(text, "{b:02x}").expect("writing to a String cannot fail");
            text
        })
}
struct Case {
    name: &'static str,
    grammar: &'static str,
    grammar_sha: &'static str,
    source: &'static str,
    source_sha: &'static str,
    positions: &'static [usize],
}
static CASES: [Case; 2] = [
    Case {
        name: "go",
        grammar: ".local/rust-migration/native-phase5/regulator/profiles-coherent/go.json",
        grammar_sha: "ffc8a018d1af9c45dbc2b2638a353a180d179247b9e82524cbcc3c263301ead4",
        source: "research/joinery/specimen/go/call-with-two-arguments.go",
        source_sha: "1e8ea189a9f8a9eec7ee8a4f769a36b2588646cde6956adf3374062eb314665b",
        positions: &[0, 8, 14, 21, 22, 28, 33, 43, 47, 53, 58, 65],
    },
    Case {
        name: "python",
        grammar: ".local/rust-migration/native-phase5/regulator/profiles-coherent/python.json",
        grammar_sha: "c901af1e95bfb72287491a32af098067262a194ecc123599fa512ed1c1af8d7d",
        source: "research/joinery/specimen/python/escape-interpolation.py",
        source_sha: "1c4b96ef93d965870b7b567df581722ce4888e1a7bbee3083e0f89db1ea04b60",
        positions: &[0, 2, 4, 6, 13, 16, 17, 19, 21],
    },
];
fn input(relative: &str, sha: &str) -> Trial<Vec<u8>> {
    let path = Path::new(ROOT).join(relative);
    let bytes = fs::read(&path).map_err(|e| format!("read {}: {e}", path.display()))?;
    require(digest(&bytes) == sha, "pinned working input differs")?;
    Ok(bytes)
}
struct Prepared {
    case: &'static Case,
    source: Vec<u8>,
    grammar: Arc<CompiledGrammar>,
    tier: usize,
    builder: MunchBuilder,
    events: Events,
    image: Option<MunchImage>,
    loaded: Option<Munch>,
    resaved: Option<MunchImage>,
    controls: Vec<Control>,
}
#[derive(Clone, Serialize)]
struct Control {
    origin: String,
    question: Question,
    expected: Outcome,
}
fn scan(slate: &Munch, body: &[u8], question: &Question) -> Outcome {
    let mut remaining = question.initial;
    let mut winners = Vec::new();
    let result = slate.scan_bytes_metered_into(
        body,
        question.at,
        question.allow.as_deref(),
        pick_value(question.pick),
        &mut remaining,
        &mut winners,
    );
    Outcome::of(&result, &winners, remaining)
}
fn add_family(
    controls: &mut Vec<Control>,
    slate: &Munch,
    body: &[u8],
    at: usize,
    allow: Option<Vec<u32>>,
    origin: &str,
) -> Trial<()> {
    for pick in ["longest", "shortest"] {
        let mut q = Question {
            at,
            allow: allow.clone(),
            pick,
            initial: TRANSITIONS,
        };
        let baseline = scan(slate, body, &q);
        require(
            baseline.error.is_none(),
            "source control exceeded fixed transition policy",
        )?;
        let spent = TRANSITIONS
            .checked_sub(baseline.remaining)
            .ok_or("source counter grew")?;
        for initial in [0, 1, spent, spent.saturating_sub(1)] {
            q.initial = initial;
            controls.push(Control {
                origin: origin.into(),
                question: q.clone(),
                expected: scan(slate, body, &q),
            });
        }
    }
    Ok(())
}
fn controls(state: &Prepared) -> Trial<Vec<Control>> {
    let slate = &state.grammar.lexer.tiers[state.tier].slate;
    let mut result = Vec::new();
    for event in &state.events.native {
        let observed = event.outcome.as_ref().unwrap();
        require(
            &scan(slate, &state.source, &event.question) == observed,
            "source replay differs from actual parser native call",
        )?;
        result.push(Control {
            origin: "actual-parser-native-call".into(),
            question: event.question.clone(),
            expected: observed.clone(),
        });
        add_family(
            &mut result,
            slate,
            &state.source,
            event.question.at,
            event.question.allow.clone(),
            "actual-permit-budget-boundary",
        )?;
    }
    for &at in state.case.positions {
        let borrowed = state
            .events
            .native
            .iter()
            .find(|e| e.question.at == at)
            .unwrap_or(&state.events.native[0])
            .question
            .allow
            .clone();
        for allow in [None, Some(vec![]), borrowed] {
            add_family(
                &mut result,
                slate,
                &state.source,
                at,
                allow,
                "supplemental-fixed-source-position",
            )?;
        }
    }
    Ok(result)
}
#[derive(Clone, Copy, Default, Serialize)]
struct Shape {
    encoded: u64,
    expanded: u64,
    patterns: u64,
    voices: u64,
    states: u64,
    transitions: u64,
    auxiliary: u64,
}
#[derive(Clone, Copy, Serialize)]
struct Header {
    shape: Shape,
    declined: u32,
    admitted: u32,
    source_bytes: u64,
    flags: u32,
}
impl Shape {
    fn remaining(&self, base: ImageLimits) -> Trial<ImageLimits> {
        Ok(ImageLimits {
            encoded_bytes: base
                .encoded_bytes
                .checked_sub(self.encoded)
                .ok_or("aggregate encoded cap")?,
            decoded_bytes: base
                .decoded_bytes
                .checked_sub(self.expanded)
                .ok_or("aggregate expanded cap")?,
            patterns: base
                .patterns
                .checked_sub(self.patterns)
                .ok_or("aggregate patterns cap")?,
            voices: base
                .voices
                .checked_sub(self.voices)
                .ok_or("aggregate voices cap")?,
            states: base
                .states
                .checked_sub(self.states)
                .ok_or("aggregate states cap")?,
            transition_entries: base
                .transition_entries
                .checked_sub(self.transitions)
                .ok_or("aggregate transitions cap")?,
            auxiliary_entries: base
                .auxiliary_entries
                .checked_sub(self.auxiliary)
                .ok_or("aggregate auxiliary cap")?,
            live_owned_bytes: base.live_owned_bytes,
        })
    }
    fn add(&mut self, other: Shape) -> Trial<()> {
        self.encoded = self
            .encoded
            .checked_add(other.encoded)
            .ok_or("encoded overflow")?;
        self.expanded = self
            .expanded
            .checked_add(other.expanded)
            .ok_or("expanded overflow")?;
        self.patterns = self
            .patterns
            .checked_add(other.patterns)
            .ok_or("patterns overflow")?;
        self.voices = self
            .voices
            .checked_add(other.voices)
            .ok_or("voices overflow")?;
        self.states = self
            .states
            .checked_add(other.states)
            .ok_or("states overflow")?;
        self.transitions = self
            .transitions
            .checked_add(other.transitions)
            .ok_or("transitions overflow")?;
        self.auxiliary = self
            .auxiliary
            .checked_add(other.auxiliary)
            .ok_or("auxiliary overflow")?;
        Ok(())
    }
}
// Only called after successful native save/load; this is paid header projection,
// not a second seal/graph/identity decoder or an independent source oracle.
fn header(bytes: &[u8], budget: &mut ImageBudget) -> Trial<Header> {
    budget
        .charge_work(176)
        .map_err(|e| format!("header projection: {e:?}"))?;
    require(
        bytes.len() >= 208 && &bytes[..8] == b"IRGXMCH1",
        "validated frame header absent",
    )?;
    let u32_at = |at: usize| u32::from_le_bytes(bytes[at..at + 4].try_into().unwrap());
    let u64_at = |at: usize| u64::from_le_bytes(bytes[at..at + 8].try_into().unwrap());
    require(
        u32_at(8) == 1 && u32_at(12) == 176 && u32_at(28) == 0,
        "actual source tier flags/header differ",
    )?;
    require(
        u64_at(32) == bytes.len() as u64,
        "validated frame size differs",
    )?;
    Ok(Header {
        shape: Shape {
            encoded: u64_at(32),
            expanded: u64_at(40),
            patterns: u32_at(48).into(),
            voices: u32_at(52).into(),
            states: u64_at(64),
            transitions: u64_at(72),
            auxiliary: u64_at(80),
        },
        declined: u32_at(56),
        admitted: u32_at(60),
        source_bytes: u64_at(88),
        flags: u32_at(28),
    })
}
fn limits_value(limits: &ImageLimits) -> Value {
    json!({"encoded_bytes":limits.encoded_bytes,"decoded_bytes":limits.decoded_bytes,
        "patterns":limits.patterns,"voices":limits.voices,"states":limits.states,
        "transition_entries":limits.transition_entries,"auxiliary_entries":limits.auxiliary_entries,
        "live_owned_bytes":limits.live_owned_bytes})
}
fn left(budget: &ImageBudget) -> Value {
    json!({"allocation":budget.allocation_left(),"work":budget.work_left()})
}
fn call_row<T>(
    report: &mut Value,
    phase: &str,
    case: &str,
    before: Value,
    budget: &ImageBudget,
    result: &Result<T, ImageError>,
) -> usize {
    let rows = report["phases"].as_array_mut().unwrap();
    let index = rows.len();
    rows.push(
        json!({"phase":phase,"case":case,"before":before,"native_after":left(budget),
        "ok":result.is_ok(),"error":result.as_ref().err().map(|e|format!("{e:?}"))}),
    );
    index
}
fn projected(
    report: &mut Value,
    index: usize,
    bytes: &[u8],
    budget: &mut ImageBudget,
    shape: &mut Shape,
    limits: ImageLimits,
) -> Trial<Header> {
    let result = header(bytes, budget);
    report["phases"][index]["after_projection"] = left(budget);
    report["phases"][index]["projection_error"] = json!(result.as_ref().err());
    let header = result?;
    shape.add(header.shape)?;
    shape.remaining(limits)?;
    report["phases"][index]["header"] = json!(header);
    report["phases"][index]["aggregate_shape"] = json!(shape);
    Ok(header)
}
fn retain(out: &Path, name: &str, bytes: &[u8]) -> Trial<Value> {
    let path = out.join(name);
    require(
        !path.exists() && !path.is_symlink(),
        "output already exists",
    )?;
    fs::write(&path, bytes).map_err(|e| format!("write image: {e}"))?;
    Ok(json!({"path":path,"bytes":bytes.len(),"sha256":digest(bytes)}))
}
fn run(out: &Path, report: &mut Value) -> Trial<()> {
    let mut prepared = Vec::new();
    for case in &CASES {
        report["preparing"] = json!(case.name);
        let grammar_source = input(case.grammar, case.grammar_sha)?;
        let source = input(case.source, case.source_sha)?;
        let grammar = CompiledGrammar::compile(&grammar_source)
            .map_err(|e| format!("{} source compile: {e:?}", case.name))?;
        let choices = grammar
            .lexer
            .tiers
            .iter()
            .enumerate()
            .filter(|(_, t)| t.precedence == 0)
            .collect::<Vec<_>>();
        require(
            choices.len() == 1,
            "expected unique actual lexical precedence0 tier",
        )?;
        let (tier_index, tier) = choices[0];
        require(
            tier.entries.len() == tier.slate.patterns().len() && tier.slate.declined().is_empty(),
            "actual tier roster/refusals differ",
        )?;
        let builder = MunchBuilder::new(tier.slate.patterns()); // preexisting preparation, default flags0
        let capture = CaptureGuard::start(&tier.slate, &source);
        // Keep the guard outside the local catch: a parser/observer failure must
        // retain all actual observations before the unchanged refusal propagates.
        let parsed = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            grammar.session().parse(&source)
        }));
        let (events, capture_complete, pending_lexical) = capture.take();
        let strict = parsed
            .as_ref()
            .ok()
            .and_then(|r| r.as_ref().ok())
            .is_some_and(|t| t.confidence().is_strict() && t.repairs().is_empty());
        let parse_error = match &parsed {
            Ok(Ok(_)) => None,
            Ok(Err(e)) => Some(format!("actual strict parser: {e:?}")),
            Err(e) => Some(format!(
                "actual parser/observer panic: {}",
                panic_text(e.as_ref())
            )),
        };
        report["cases"].as_array_mut().unwrap().push(json!({
            "case":case.name,"grammar":case.grammar,"grammar_sha256":case.grammar_sha,
            "source":case.source,"source_sha256":case.source_sha,"source_bytes":source.len(),
            "precedence":0,"flags":0,"tier_index":tier_index,"patterns":tier.slate.patterns(),
            "pattern_bytes":tier.slate.patterns().iter().map(String::len).sum::<usize>(),
            "word":grammar.automaton.word().map(|s|s.index()),
            "provided_entries":tier.entries.iter().filter(|e|e.provided).count(),
            "entries":tier.entries.iter().enumerate().map(|(i,e)|json!({"ordinal":i,"symbol":e.symbol.index(),
                "name":grammar.automaton.symbol(e.symbol).name,"order":e.order,"immediate":e.immediate,
                "literal":e.literal,"provided":e.provided,"external":e.external,"extra":e.extra})).collect::<Vec<_>>(),
            "strict":strict,"parse_error":&parse_error,"capture_complete":capture_complete,
            "pending_lexical_event":pending_lexical,"native_events":&events.native,"lexical_events":&events.lexical,
        }));
        if let Some(error) = parse_error {
            return Err(format!("{} {error}", case.name));
        }
        require(strict, "working source not strict")?;
        require(capture_complete, "incomplete actual parser observation")?;
        prepared.push(Prepared {
            case,
            source,
            grammar,
            tier: tier_index,
            builder,
            events,
            image: None,
            loaded: None,
            resaved: None,
            controls: vec![],
        });
    }
    report["preparing"] = Value::Null;
    let limits = ImageLimits::default();
    report["policy"]["limits"] = limits_value(&limits);
    let mut saves = ImageBudget::new(ALLOCATION, WORK, &limits);
    let mut shape = Shape::default();
    for state in &mut prepared {
        let effective = shape.remaining(limits)?;
        let before = left(&saves);
        let result = state.grammar.lexer.tiers[state.tier]
            .slate
            .save_image(&effective, &mut saves);
        let row = call_row(report, "save", state.case.name, before, &saves, &result);
        report["phases"][row]["effective_limits"] = limits_value(&effective);
        let image = result.map_err(|e| format!("{} save refused: {e:?}", state.case.name))?;
        report["phases"][row]["image"] = retain(
            out,
            &format!("{}-source.image1", state.case.name),
            image.as_bytes(),
        )?;
        let stats = projected(
            report,
            row,
            image.as_bytes(),
            &mut saves,
            &mut shape,
            limits,
        )?;
        let slate = &state.grammar.lexer.tiers[state.tier].slate;
        require(
            stats.shape.patterns == slate.patterns().len() as u64
                && stats.admitted as usize == slate.admitted()
                && stats.declined as usize == slate.declined().len()
                && stats.source_bytes
                    == slate.patterns().iter().map(|p| p.len() as u64).sum::<u64>(),
            "header roster differs from actual source tier",
        )?;
        state.image = Some(image);
    }
    let mut loads = ImageBudget::new(ALLOCATION, WORK, &limits);
    let mut shape = Shape::default();
    for state in &mut prepared {
        let effective = shape.remaining(limits)?;
        let before = left(&loads);
        let bytes = state.image.as_ref().unwrap().as_bytes();
        let result = state.builder.load_image(bytes, &effective, &mut loads);
        let row = call_row(report, "load", state.case.name, before, &loads, &result);
        report["phases"][row]["effective_limits"] = limits_value(&effective);
        let loaded = result.map_err(|e| format!("{} load refused: {e:?}", state.case.name))?;
        projected(report, row, bytes, &mut loads, &mut shape, limits)?;
        let slate = &state.grammar.lexer.tiers[state.tier].slate;
        require(
            loaded.patterns() == slate.patterns()
                && loaded.declined() == slate.declined()
                && loaded.admitted() == slate.admitted(),
            "loaded roster/refusal differs",
        )?;
        state.controls = controls(state)?;
        for (control_index, control) in state.controls.iter().enumerate() {
            let actual = scan(&loaded, &state.source, &control.question);
            if actual != control.expected {
                report["comparison_refusal"] = json!({"case":state.case.name,"phase":"load-replay",
                    "control_index":control_index,"control":control,"actual":actual});
                return Err(
                    "loaded answer/order/error/remaining transition allowance differs".into(),
                );
            }
        }
        report["replays"]
            .as_array_mut()
            .unwrap()
            .push(json!({"case":state.case.name,"controls":&state.controls,"all_equal":true}));
        state.loaded = Some(loaded);
    }
    let mut resaves = ImageBudget::new(ALLOCATION, WORK, &limits);
    let mut shape = Shape::default();
    for state in &mut prepared {
        let effective = shape.remaining(limits)?;
        let before = left(&resaves);
        let result = state
            .loaded
            .as_ref()
            .unwrap()
            .save_image(&effective, &mut resaves);
        let row = call_row(report, "resave", state.case.name, before, &resaves, &result);
        report["phases"][row]["effective_limits"] = limits_value(&effective);
        let image =
            result.map_err(|e| format!("{} canonical resave refused: {e:?}", state.case.name))?;
        report["phases"][row]["image"] = retain(
            out,
            &format!("{}-loaded.image1", state.case.name),
            image.as_bytes(),
        )?;
        projected(
            report,
            row,
            image.as_bytes(),
            &mut resaves,
            &mut shape,
            limits,
        )?;
        require(
            image.as_bytes() == state.image.as_ref().unwrap().as_bytes(),
            "canonical source/load/resave bytes differ",
        )?;
        state.resaved = Some(image);
    }
    for mut state in prepared {
        let parent = state.loaded.take().unwrap();
        let first = parent
            .try_clone()
            .map_err(|e| format!("loaded clone: {e:?}"))?;
        let second = first
            .try_clone()
            .map_err(|e| format!("clone clone: {e:?}"))?;
        drop(parent);
        drop(first);
        let mut image = state.image.take().unwrap().into_bytes();
        image.fill(0xa5);
        drop(image);
        let mut resaved = state.resaved.take().unwrap().into_bytes();
        resaved.fill(0x5a);
        drop(resaved);
        drop(state.builder);
        drop(state.grammar);
        for (control_index, control) in state.controls.iter().enumerate() {
            let actual = scan(&second, &state.source, &control.question);
            if actual != control.expected {
                report["comparison_refusal"] = json!({"case":state.case.name,"phase":"clone-replay",
                    "control_index":control_index,"control":control,"actual":actual});
                return Err("source-first drop/clone/first lease changed native question".into());
            }
        }
        report["clones"].as_array_mut().unwrap().push(json!({"case":state.case.name,"clone_chain":2,"source_first_drop":true,
            "caller_images_poisoned_and_freed":true,"controls":state.controls.len(),"all_equal":true}));
    }
    report["operation_remaining"] =
        json!({"save":left(&saves),"load":left(&loads),"resave":left(&resaves)});
    Ok(())
}
fn panic_text(error: &(dyn std::any::Any + Send)) -> &str {
    error
        .downcast_ref::<String>()
        .map(String::as_str)
        .or_else(|| error.downcast_ref::<&str>().copied())
        .unwrap_or("non-string")
}
#[test]
#[ignore = "explicit working-corpus Image1 trial; requires pinned .local inputs and JOINTS_IMAGE_WORKING_OUTPUT"]
fn actual_working_precedence_zero_images_preserve_parser_questions() {
    let out = PathBuf::from(
        std::env::var_os("JOINTS_IMAGE_WORKING_OUTPUT").expect("explicit fresh output required"),
    );
    assert!(out.is_absolute() && !out.exists() && !out.is_symlink());
    fs::create_dir(&out).expect("create fresh diagnostic output");
    let mut report = json!({"schema":1,"status":"running","pass":false,"cases":[],"phases":[],"replays":[],"clones":[],
        "scope":"actual working precedence0 tier Image1 falsifier; no artifact integration or performance claim",
        "policy":{"allocation":ALLOCATION,"work":WORK,"header_projection_work":176,"event_limit":MAX_EVENTS},
        "observer_work_is_diagnostic":true,"expected_builder_preparation_preexists_image_allowance":true});
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| run(&out, &mut report)));
    let error = match result {
        Ok(Ok(())) => None,
        Ok(Err(e)) => Some(e),
        Err(e) => Some(format!(
            "observer/assertion panic: {}",
            panic_text(e.as_ref())
        )),
    };
    report["pass"] = json!(error.is_none());
    report["status"] = json!(if error.is_none() {
        "complete"
    } else {
        "refused"
    });
    report["error"] = json!(error);
    fs::write(
        out.join("report.json"),
        serde_json::to_vec_pretty(&report).unwrap(),
    )
    .expect("retain actual diagnostic report");
    assert!(
        error.is_none(),
        "working Image1 falsifier refused: {error:?}"
    );
}
