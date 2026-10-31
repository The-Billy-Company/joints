# Rust rebuild design and migration plan

Rebuild joints in Rust from its current behavioral contracts and corrected
research results. Redesign ownership, interfaces, and ordinary infrastructure;
retain the Zig implementation as an executable reference while each Rust
capability becomes usable. The selected first milestone is the core parser and
guarded-effect algebra; queries and consumer adapters follow afterward. The
proposed migration eventually covers the current product.

The deliverable before substantial implementation is one concise design file
containing the algorithms, invariants, counterexamples, and acceptance tests a
Rust implementation needs. This plan seeds that file with the decisions already
supported by the repository. Complete the behavioral inventory in phase 1.

## Scope and size target

The checkout counted on 2026-10-18 contains 37,292 nonblank, non-comment Zig
lines across 129 files. That includes tests, benchmarks, and build code.
Removing dedicated test files, test roots, and inline test blocks leaves about
23,700 production lines under `src/`. This second count is approximate because
test helpers outside test blocks remain included.

Target **10,000 or fewer first-party production Rust lines**, including the
engine, compiler, CLI, and C adapter. Count tests, benchmarks, generated code,
and dependencies separately for both languages. Treat the target as a design
constraint to evaluate after the first working slice, not a forecast. Preserve
readability and coverage; do not compress formatting or remove required
behavior to meet it. Also measure dependency footprint, build time, and memory.

The eventual scope includes grammar import and compilation, stateful lexing,
cold and incremental parsing, trees and repair evidence, queries, grammar
artifacts, CLI, C ABI, and Python/Rust consumer integration. Experimental storage
and research instruments may remain outside the initial engine; record every
deferral explicitly. The current product remains available throughout migration.

## How to recover the design

Use current source, regression tests, and recorded results together. Research
prose explains motivation and failed approaches; it is not a complete current
specification. For example, `research/README.md` predates `src/`, and the joint
README describes a representation superseded by `effect.zig`.

For every subsystem, write down its inputs, outputs, ownership, algorithm,
invariants, failure modes, observable compatibility, and the smallest fixture
that catches a wrong simplification. Link each entry to source and evidence.
Distinguish a required contract, a measured result on named inputs, and an open
research goal. Resolve contradictory descriptions before implementing that part.

### Research corrections that govern the rebuild

| Topic | Design to carry forward | Evidence |
|---|---|---|
| Stack effects | An effect has an entry state, an interned ledger constraining states and symbols at every popped depth, and an interned pushed-symbol sequence. Composition checks and refines the guards. Neither a pop count alone nor enumerated hypothetical popped strings is sufficient. | [Current effect](src/kernel/joint/effect.zig), [ledger](src/kernel/joint/ledger.zig) |
| Composition | Preserve identity, partial composition, semantic equality, and recovery holes that absorb composition. Test both association orders, including refusal. IDs are meaningful only within their interning space. | [Effect](src/kernel/joint/effect.zig), [spine](src/kernel/spine/README.md) |
| Convergence | Rank-one convergence failed. Later sweeps report bounded guarded product residue and agreement with whole-file effects on their workloads. Residue at most two is a recorded result, not a universal bound. | [Amended claim](research/joinery/CLAIM.md), [rung results](research/joinery/TESTING.md) |
| Incrementality | Current leaves record actual parse moves and entry states. A state change can invalidate a suffix. Logarithmic tree maintenance does not establish logarithmic total edit time. | [Weave](src/kernel/weave/README.md), [keystroke results](research/keystroke/README.md) |
| Lexing | Restrict patterns by parser permissions before selecting a token. Keep precedence, immediacy, keyword rules, comments, Unicode behavior, and scanner memory explicit. | [Lexer](src/kernel/lex/README.md), [scanner](src/kernel/lex/scanner.zig) |
| Grammar lowering | Preserve authored precedence scope through transformations, plus aliases and fields at their use sites. A zero residual conflict count does not establish correct parses. | [Authored width](research/press/RESULT-3-authored-width.md), [grammar IR](src/press/copy/grammar.zig) |
| Reuse | Restore the exact scanner state and lexical admission context. Check each intermediate edit against a cold parse. Attractive reuse relaxations have produced faster, wrong trees. | [Forest negative result](research/keystroke/RESULT-2-forest.md), [scanner restoration](research/keystroke/RESULT-4-book.md) |
| Scanner programs | Keep scanner books as data with explicit state, ordered effects, abstention/refusal, and bounded progress for zero-width tokens. | [Scanner claim](research/customary/CLAIM.md), [measured composition](research/customary/RESULT-1-algebra.md), [books](customary/) |

Full scanner composition, parallel parsing within one file, universally better
recovery, and position-independent total edit costs remain goals to validate.
Do not make them prerequisites for a useful native Rust implementation.

## Contracts to preserve

The initial specification must cover these observable behaviors, with fixtures:

1. Grammars remain data imported from pinned tree-sitter `grammar.json` inputs;
   the production runtime does not depend on tree-sitter to parse source.
2. Trees retain names, named/anonymous distinctions, aliases, fields, original
   bytes, byte spans, row/byte-column positions, extras, and navigation order.
   Source is bytes; do not silently require UTF-8 or reinterpret byte columns.
3. Strict success requires acceptance, structural soundness, exactly one root,
   and no deleted or supplied tokens. Diagnostic results retain forests and
   authoritative repair evidence. Acceptance alone is insufficient.
4. Queries preserve supported syntax, captures, pattern indices, match ordering,
   source predicates, and explicit handling of unsupported predicates.
5. Incremental results agree with fresh results after every edit, including
   intermediate invalid source, scanner state, spans, repairs, and products.
6. Corrupt artifacts and invalid public inputs are refused predictably. Preserve
   resource limits and progress guarantees rather than relying on assertions.

Use the [root contract](README.md), [tree behavior](src/kernel/quire/README.md),
[query contract](src/kernel/gloss/README.md), [ABI](include/jnt.h), and
[binding tests](bindings/) to complete the inventory. Zig output is evidence,
not an instruction to reproduce known bugs: classify disagreements against
grammar intent, independent references, and a written regression test.

## Proposed Rust architecture

Start with one native engine crate organized by responsibility. Separate CLI
and C boundary crates only where their dependencies or unsafe code require it.
During migration, place the workspace under `rust/`, use a distinct engine
package name, and run a `joints-rs` binary. The existing `bindings/rust` workspace
and published `joints` binding must continue to build independently.

| Type or module | Responsibility and ownership |
|---|---|
| `CompiledGrammar` | Immutable grammar IR, tables, compiled lexer, scanner program, and names; shared as `Arc<CompiledGrammar>`. |
| `ParseSession` | Worker-owned parser and lexer scratch, scanner state, interning pools, graph stack, recovery, and reuse working state. Parsing takes `&mut self`. |
| `TreeSnapshot` | Owns `Arc<CompiledGrammar>`, immutable source storage, indexed nodes/children, confidence, and repair evidence. Can outlive the mutable session. |
| `Document` | Current text, line index, measured tree, session, and snapshot; editing takes `&mut self`. |
| `compile` | Grammar import, lowering, LR/LALR construction, and conflict policy. |
| `effects` and `document` | Guarded effects, measured sequence, and incremental reuse. |
| `query` | Compiled queries retain their grammar ownership and identity; execution checks the tree's grammar before matching. |
| `artifact` | Explicit encoding, checked decoding, and versioning. |
| adapters | CLI, C ABI, and Python integration over the native API. |

Use typed integer IDs and indexed storage instead of pointer graphs. Keep the
engine free of application-authored `unsafe`; isolate justified exceptions in
boundary crates. Avoid a trait or generic framework until a second concrete
use requires it. Implement the recovery behavior actually needed before adding
a general semiring API. Defer succinct tree encodings until their measured
space benefit justifies their complexity.

No retained ID may outlive or be confused with its owning storage. In
particular, grammar IDs remain backed by the snapshot's grammar; retained
effects must not reference interning pools cleared for another parse.

Compiled data and completed snapshots should be shareable; mutable work stays
with each worker or document. `Arc` only supplies shared ownership and requires
the contained type to support the desired thread safety; it does not make
mutable internals safe by itself. Verify the intended `Send`/`Sync` properties
with compile-time checks. See the [Rust ownership documentation](https://doc.rust-lang.org/std/sync/struct.Arc.html#thread-safety).

Start concurrency across independent documents, using standard threads or
Rayon with one session per worker. Keep output ordering deterministic. Add
parallel work within a document only after validating scanner dependencies,
cross-worker interning, and ordered effect composition. Associativity permits
regrouping; it does not permit reversing source order. Rayon's
[reduction contract](https://docs.rs/rayon/latest/rayon/iter/trait.ParallelIterator.html#method.reduce)
also requires an associative operation and true identity.

## Ecosystem substitutions to test

Use standard collections, ownership, error propagation, serialization tools,
and test infrastructure where they remove code. Keep custom code where it
expresses joints's semantics. Select and pin dependencies after small trials.

The phase 2 prototype tested replacing irregex's token matcher. The user then
authorized reusing `irgx` and considering `sheng`; phase 3 now integrates the
existing safe Rust `irgx` binding instead of rebuilding regex services. Its
[public surface](../irregex/src/root.zig) also supplies succinct operations,
partitioning, and artifact support. Inventory actual imports individually;
reusing its regex service retains a native library dependency.

The completed first slice evaluated `regex-automata` for anchored matching and
match attribution. Its
[match semantics](https://docs.rs/regex-automata/latest/regex_automata/enum.MatchKind.html)
are configurable, but that does not establish compatibility with joints's
state-restricted longest matching. Prototype parser permission subsets,
precedence tiers, Unicode/JavaScript pattern translation, keyword ties, and
serialization. The `irgx::Munch` integration must satisfy those same fixtures,
with safe byte input and metered native transitions. A match selected from all
tokens and filtered afterward is
incorrect; JSON's `string_content` is a required counterexample. Scanner probes
reuse `irgx`'s bounded byte captures. `sheng` remains a phase 6 candidate for
measured rejection work; its refutation contract cannot supply exact token spans.

Consider Serde for grammar/book input, a CLI parser for command handling, and
property-test tools for algebra and edits. None replaces grammar lowering,
guarded effects, or stateful scanner semantics.

Load artifacts into owned bytes first. Memory mapping is a later optimization
with an explicit safety contract: file-backed mappings can become unsafe if
another process modifies the file, as documented by
[memmap2](https://docs.rs/memmap2/latest/memmap2/struct.MmapOptions.html#safety).
Preserve checked offsets, tags, sizes, and schema validation in either path.

## Migration phases and completion gates

### Phase 0 Freeze reproducible references

Build a private Zig reference binary using `tool/pin.py`; never compare against
the shared `zig-out/bin/joints`. Capture canonical outputs on the pinned corpus
and a representative Billy Regulator workload. Record existing refusals and
known defects separately from supported behavior.

Extend the migration manifest beyond the existing pin record: include joints
and sibling irregex commits and dirty-content digests, `customary/` book hashes,
grammar/fixture pins, `include/jnt.h`, toolchain versions, binary digests, host,
and command arguments. The existing source stamp does not cover all those
inputs. This inspected checkout is joints
`9f5caf7bae7d370033fe55d0bcaaba7a75e9d8a6` with irregex
`fc7a8526c3cd34b672f34aa53b488ff43ba507ee`; record actual state when building.

**Gate:** another clean checkout can reconstruct the inputs and verify the
reference binaries and captured cases.

### Phase 1 Complete the executable specification

Fill in the subsystem inventory above. Extract small regression fixtures for
each invariant and failed simplification. Record supported query constructs,
scanner cohorts, recovery policies, artifact versions, and all public functions.
Use one design file with linked fixtures rather than copying the research tree
into an ever-growing specification.

**Gate:** each required behavior has an observable comparison or invariant;
each omitted feature has an explicit reason and reintroduction condition.

### Phase 2 Prove a native Rust slice and the risky substitutions

Create the isolated workspace and safe ownership model. Import the committed
JSON grammar, construct its tables, lex from parser permissions, cold-parse,
and expose nodes, confidence, and repair evidence. Include malformed JSON.
Separately implement guarded effects against small automata and test identity,
association/refusal, absorbing holes, and agreement with a simple stack walk.
Prototype replacing irregex and sharing one compiled grammar across workers.

**Gate:** canonical JSON trees, fields, spans, repairs, and strict refusal
agree; algebra tests include the current ledger counterexamples; independent
workers reproduce sequential results. Measure code size and complexity here
before committing to a final line-count forecast or schedule.

### Phase 3 Establish cold parsing across difficult grammars

Generalize lowering, conflict handling, forest construction, recovery, and
scanner books. Add Python indentation and one grammar with declared ambiguity,
then exercise the full pinned breadth set. Include nested strings/comments,
zero-width and EOF tokens, aliases, fields, extras, and byte/Unicode boundaries.

**Gate:** no unexplained regressions on supported cases; new behavior has
independent evidence. Match trees and repair/confidence evidence rather than
using acceptance percentages or conflict counts as proxies for correctness.

### Phase 4 Add incremental documents

Implement the measured sequence and conservative reuse. Validate replay entry
state, lexical admission, scanner snapshots, and checkpoint offset/token
consistency. Retain a cold-parse fallback whenever reuse cannot be proved.

**Gate:** after every randomized and corpus-derived edit, Rust incremental and
cold results agree. Check malformed intermediate states and edits at the start,
middle, and end. Compare effect products semantically across interning pools.
Measure text copying, tree materialization, and snapshot retention separately;
an inexpensive spine splice must not conceal linear work elsewhere.

### Phase 5 Complete artifacts queries and consumer adapters

Finish the supported query language, CLI, and C boundary. Reuse the Python and
Rust binding suites. Native Rust callers should use the engine directly.
Run the real Regulator compatibility workload before changing its default.

Decide artifact compatibility after the lexer prototype. Prefer an explicit
format version and re-minting grammars if the Rust lexer encoding differs;
keep the legacy engine available for existing artifacts during transition.
If legacy folios must load directly, account for their lexer encoding and
validate cross-language readers with fixtures. Never silently reinterpret them.
API compatibility and artifact compatibility are separate decisions.

Preserve ABI 2's documented behavior where promised. Review allocation errors,
panic behavior, handle lifetimes, edit invalidation, and thread-local errors at
the boundary; ordinary Rust allocation and panic handling do not automatically
implement every existing C failure contract.

**Gate:** public function coverage and consumer comparisons pass; artifact
corruption, round trips, independent-build determinism, and version refusal
are tested. Any compatibility break has an explicit migration path.

### Phase 6 Optimize simplify and switch implementations

Profile before adding specialized storage, unsafe access, sparse tables, or
parallel work within a file. Remove duplicate representations and adapter
ceremony where the measured design permits it. Keep tests and evidence intact.

Report cold parse/compile latency, memory, artifact size, edit latency by
position, and independent-file throughput for both implementations. Set
numerical budgets from phase 0's consumer baseline before optimizing. A useful
initial review trigger is a repeatable regression above 10% in a key median or
p95; account for measurement noise and document any accepted tradeoff.

**Gate:** agreed correctness, consumer, memory, and performance budgets pass
on target Linux and macOS environments. Switch consumers and release packaging
only after those gates; retire Zig once rollback and artifact transition are
covered. Evaluate the 10,000-line target using the same production scope.

## Existing evidence to reuse

| Tool or fixture | Migration use |
|---|---|
| `tool/pin.py`, `grammars.toml`, `test/grammar/` | Immutable references and reproducible input bytes; supplement the manifest as above. |
| `tool/rung1.py` | Segmented-product agreement, refusals, and residue growth. |
| `tool/differential.py`, `tool/sound.py`, `tool/standing.py` | Tree differences, structural validity, and coverage reported separately. |
| `tool/glance.py` | Capture multiplicity and order against an independent query engine. |
| `research/press/wobble.py`, folio tests | Artifact determinism, field preservation, corruption rejection. |
| `src/kernel/weave/amend_test.zig`, keystroke probes | Edit sequences, negative controls, shrinking, and cold/incremental agreement. |
| `tool/bench.py`, `tool/amend.py`, `bench/` | Cost and edit-position measurements. |
| `bindings/python/tests/`, `bindings/rust/tests/` | Strict refusal, repair evidence, source retention, owners, queries, and workers. |
| `tool/holdout.py`, `holdout/README.md` | Late aggregate generalization checks while preserving the existing holdout seal. |

Several CLI harnesses select a binary through `JOINTS_BIN`; preserve their
machine-readable interface or add a narrow comparison adapter. Run Zig and
Rust sequentially against separately pinned binaries with equivalent release
settings. Use tree-sitter and consumer expectations to adjudicate known Zig
defects rather than letting either implementation grade itself.

Require the expected cases and independent references to actually execute.
Some harnesses can succeed when tree-sitter is unavailable, and the benchmark
tool can retain a previous binary after a build failure. Verify binary hashes,
oracle identities, case counts, and build success before accepting a report.
Keep holdout diagnosis sealed; reproduce aggregate failures on working-corpus
or authored examples rather than inspecting held-out witnesses.

## Immediate next implementation task

Phase 0 has completed locally: the private reference and all 36 requested cases
were captured, verified, and replayed; the portable JSON subset replayed all 25
cases. Phase 1 is specified in [RUST_DESIGN.md](RUST_DESIGN.md), including the
corrected symbol-and-state guard model and initial no-recovery comparison mode.

Phase 2 has passed its local gate: 48 Rust tests, Clippy, the native release
build, and all 13 selected frozen CLI cases pass. The core is about 2,900
production code lines. Shared-grammar workers agree with sequential parsing;
guarded effects and parser traces pass association and split checks. The
ordinary-token lexer substitution works on the first slice and has explicit
transition budgets and scaling regressions. See [the native workspace](rust/README.md).

Phase 3 has passed its local gate on candidate `acfa7e2fc5f5c349`: all 31 pinned
grammars construct, all 66 scanner specimens pass their explicit baseline or
independent correction checks, and all 19 larger sources execute without
operational refusal. The full reference replay retains 35 exact matches and
the independently justified invalid Regulator profile refusal. Known partial
grammars and independently classified differences remain explicit in
[the design](RUST_DESIGN.md); this is not a complete product cutover.

Phase 4 has passed its local gate: 176 default tests and Clippy, 226 explicit
edit calls with expected-byte checks and cold comparisons, persistent measured
sequence tests, unchanged 66-specimen results, and byte-identical outputs for
all 19 larger sources. That candidate has about 12,657 production Rust lines.

Phase 5 passed its complete local qualification on candidate
`e73eb9ee016afd74` (bundle `3d3c572062cbf5f8`). It passes 336 default Rust tests,
14 explicitly run
working-corpus witnesses, Clippy, formatting, and 66 helper tests. All 31 pinned
grammars construct; the 66 specimens and full frozen reference retain their
classified results. Both C libraries expose all 62 ABI functions; actual
static/dynamic C clients and the existing Python/Rust binding
suites pass. Native artifacts load compiled tables without LR construction;
legacy artifacts require explicit re-minting and retain Zig for rollback.

The coherent Regulator snapshot has 68 tests: 64 default, two governed-corpus
gates, and two manual measurements. Its release ThinLTO build passes. All 12
reviewed grammar artifacts mint and load. The original authored TypeScript/TSX
profiles are independently invalid; explicit versioned corrections add only
the three conflicts requested by the pinned generator. The full default run
now passes all 64 tests after correcting Go toolchain selection, branch
capacity, Swift/JSX scanner tokens, and TypeScript ambiguity ordering.
Independent synthetic and real-source controls confirm the state-specific
reconstruction and alias provenance. The broader replay passes: PHP is
independently exact and all 95 changed Swift subtrees match,
with its inherited multiline-member split retained. The preceding candidate's
full Go and Python failures remain preserved. The qualified successor fixes
contextual empty tokens, repeated parser work, and static precedence, and uses
the [reviewable consumer projection patch](test/migration/regulator/README.md).
Its fresh artifacts pass all 6,216 Go sources and all 102,906 Python sources
under the original assertions and unchanged runtime limits. Two independent
mint processes produce identical artifacts for all 12 reviewed profiles.
The complete private corpus contains 110,014 files and is an explicit assembled
dataset version, not an atomic live checkout. Qualification joins 12 completed
gates with exact source, binary, runtime, and corpus provenance; the report is
`.local/rust-migration/native-phase5/qualification-E/report.json`. The complete
622-file gate input closure is retained before subsequent edits.

Phase 6 is in progress. The first controlled baseline completed all 1,540
commands with stable inputs and shows substantial latency, memory, and artifact
size regressions. Separate controlled trials selected bounded recovery scratch,
verified artifact payload ownership, and removal of one redundant inspection
read-back. Inline head buffers were declined; snapshot packing was deferred.
Sheng is declined on the measured semantics/work-gate evidence. See the
[performance review](rust/PERFORMANCE.md).

The combined candidate F, CLI `35f20e5cece02ef1` (bundle `c03b29f397b965c2`),
passes a fresh complete 12-gate compatibility qualification: 347 default Rust
tests, 14 explicit witnesses, 93 helper tests, actual Rust 1.85 checks, all 62
C exports and the Python/Rust binding contracts. All 64 default consumer tests,
6,216 Go sources, and 102,906 Python sources pass the original assertions.
Two fresh mints agree byte-for-byte for all 12 profiles and retain E's artifact
bytes. All 110,014 dataset files were rehashed after both governed runs.
The report is `.local/rust-migration/native-phase6/qualification-F/report.json`.
Its complete 628-file source closure is retained before delivery-tool and
documentation changes; the 112 compiled inputs remain unchanged.

F has about 22,868 production Rust lines across 39 files under the same
approximate counting convention. The two additional recovery oracle/test files
are compiled only for tests; build scripts are reported outside the runtime
count. The 10,000-line goal remains unmet. The actual F cost matrix now
completes all 1,546 commands under the user-authorized observed host conditions;
its substantial performance and memory regressions remain unaccepted. The
shared native boundary/delivery helpers pass 149 controls. Both fresh schema-2
packages pass all 40 installed checks, including the full 347-test suite, on the
current Mac and emulated Ubuntu. These do not establish physical target-floor
execution. The late sealed worker refused before producing an accepted aggregate;
raw diagnosis remains unread. Meeting the selected budgets, the sealed gate, and
native
platform execution are still open. No consumer or release default has changed.
A separate working-only artifact probe closes the base-grammar roundtrip gap:
all 31 fresh default-policy mints and 31 standalone inspections pass, with exact
report pairs and unchanged artifact hashes. No sealed diagnosis is used or
inferred from that success.

Every retained lexical decision must be validated against the edited source;
checking a nearby token or unchanged prefix bytes cannot prove an unbounded
regex or scanner did not inspect the changed suffix. Cold fallback remains
mandatory where reuse is unproved.

The probe trial compared all 218 shipped patterns against PCRE2 across 234,350
offset/capture questions. The user-selected `irgx` adapter passes those same
comparisons and replaces the earlier pure Rust candidate. Native capture faults
and lexer transition budgets must cross the binding without becoming misses.
The 10,000-line target remains a design goal; scanner programs, full grammar
conflicts, and remaining consumer interfaces still determine the final size.

The user has now selected a cutover budget of key latency and peak process
memory costs within 10 percent of Zig. This is an acceptance ceiling, separate
from the earlier 10-percent review trigger; candidate F has not met it. Continue
with profiled, independently checked changes and fresh qualification for any
selected combined candidate. Historical Zig ABI cost rows remain diagnostic
because their frozen library lacks source attestation. The fresh attested
baseline recorded below applies only to a new comparison.

The isolated SHA dependency successor passes its Rust 1.85/1.96 checks on the
current Mac and emulated Ubuntu, and retains all 31 working artifact bytes.
Its focused comparison improves Go/Python cold-parse medians by about 10 percent
with substantially unchanged memory. It is included in the locally qualified
combined candidate below; the 10-percent Zig budget remains unmet.
New authored baseline controls reveal a long-reduction refusal in F where Zig
accepts and a required empty-token refusal shared by both implementations.
Adaptive/canonical traces confirm donated lexical permissions as the cause on
these inputs. A private correction passes all-target checks and 355 default
tests (16 ignored) on Rust 1.85 and 1.96, including existing cache assertions
and eight new semantic regressions. The private combined candidate now includes
both components and passes 357 default tests on each toolchain, Clippy, a fresh
release build, 31 byte-identical artifacts, and all 14 working witnesses. Fresh
local qualification also covers 55 classified CLI cases, C/Python/Rust ABI
consumers, 64 default consumer tests, 6,216 Go inputs and all 102,906 Python
inputs. All 110,014 source hashes are stable. The ABI evidence preserves the
initial failed run and the separate corrected archive-normalization run.
The next isolated trial persists checked native lexer machines, beginning with
shared immutable ownership and independent worker scratch before image codecs
or artifact integration. It retains this qualified candidate for rollback.
That trial's focused ownership step now passes 51 Munch controls and five ABI
controls, including allocation failures and concurrent worker clones. The raw
runner refusal is retained: Zig extracted ten build-dependency files inside the
source directory. Independent review verified each against the pinned archive
and confirmed all implementation files stayed unchanged. No tests were rerun.
The native image codec passes its focused gate: all 78 Munch/Image1 controls
and five ABI controls pass, including 42 independently authored frames and 84
scan questions with exact transition budgets. C record layouts compile for
ARM64 macOS and x86-64 Linux. Independent audits verify the actual logs and all
1,240 source files. The first failed C syntax-only probe remains retained;
the corrected object-only gate passes without changing engine assertions.
Safe Rust wrappers now pass 13 focused controls on each of Rust 1.85 and
1.96, including shared resource budgets, clone lifetimes, concurrency and all
35 typed malformed-frame outcomes. The separate native108 static archive
passes its symbol, runtime-payload, relocation and ownership proof. Actual Go
and Python lexer-tier probes now pass on Rust 1.96: 191 patterns, 51 actual
parser-native questions and 963 replay controls, repeated after clone chains
and source-first drops. Both image pairs are canonical and all three shared
operation budgets fit unchanged caps. This is native-tier parity, not full
loaded-parser or performance qualification. Private VERSION3/SCHEMA4 artifact
integration now passes 34 focused controls on each compiler (68 pass
observations, including 16 new controls per compiler). The existing profiling
probe stays explicitly ignored. The first compile refusal and its narrow
test-helper correction are retained. The private candidate now also passes all
371 default tests with 16 declared ignores on each compiler, both all-targets
checks, Clippy with warnings denied, and a fresh release build. Independent
audits confirm the exact test rosters, source closure and native linkage.
The full workspace qualification is recorded in
`.local/rust-migration/native-phase6/trials/checked-munch-image/artifact-full-validation/qualification.json`
(SHA-256 `d8477a133b18aea2f1d08128557cbc5967b58940ce716d077634816d500a3b57`).
All 31 working grammars now also pass 124 CLI calls: two source mints, a loaded
repack and an inspection per grammar. Their three new V3/S4 artifacts are
byte-identical and retain the frozen grammar metadata. All 14 fresh working
witnesses pass with 66 specimens and 28 ambiguity comparisons. The 55-case CLI
replay passes with 38 strict parses, 16 matching partial parses and the one
independently invalid profile refused. The corrected ABI gate passes all 24
commands, including Rust 1.85/1.96 with and without LTO, using the existing
archive-member normalization and opaque C boundary. Governed consumers pass
64 default tests (four declared ignores), all 6,216 Go inputs and all 102,906
Python inputs. The final integrity writer verifies all 110,014 source hashes.
The current private compatibility join is
`.local/rust-migration/native-phase6/trials/checked-munch-image/qualification-1/report.json`
(SHA-256 `0c760df6ec8a6a85ed4d1f5f05cca7224222947879549f6e96a4418c96007bce`).
These controls establish local compatibility; Linux execution remains open.
The local compatibility join is recorded in
`.local/rust-migration/native-phase6/trials/contextual-sha-F/qualification-3/report.json`
(SHA-256 `2896b4acd236fac3d436b64b2d5c6abb17e91fb969784d0314b66a4ee141f7e5`).
That earlier combined candidate has approximately 23,168 production Rust lines;
it has no direct cost measurement of its own.
The private Image1 successor has approximately 23,808 production Rust lines
under the same engine, CLI and C-adapter scope, excluding actual test-only
observers. Its separate IRGX binding dependency is outside that count. The
10,000-line goal remains unmet; line counts establish no runtime cost reduction.

The fresh Image1 cost matrix completed all 1,546 commands once with unchanged
inputs on 2026-10-20. The user authorized concurrent host work, so its scope is
an observed, contended-host diagnostic. The agreed maximum Rust/Zig ratio
remains 1.10; no regressions have been accepted. Cold-parse median/p95/RSS
ratios are 1.41/1.37/1.26 for JSON, 7.64/7.20/1.85 for large JSON,
4.87/4.48/3.60 for Go, and 5.41/5.20/3.31 for Python. The budget remains unmet.
The complete results, including edits and 1/2/4-worker throughput, are retained
under `.local/rust-migration/native-phase6/trials/checked-munch-image/costs-3/run-1/`.
See [the performance review](rust/PERFORMANCE.md#private-image1-full-cost-matrix).
The next proposed storage optimization is one private immutable table module
that shares terminal admissions and stores actions/transitions in flat columns.
It requires byte, error-order, work-budget and lookup controls before another
candidate can be qualified. No saving is inferred from its payload arithmetic.
The earlier phase gates remain evidence for their frozen cases;
they do not establish these newly discovered cases or a sealed failure cause.

## Workspace promotion and optimization, 2026-10-21

The Image1 V3/S4 engine, regression tests, native108 IRGX implementation and
binding, and explicit native-family build helpers are now in the working
checkouts. Promotion copied 95 exact qualified files only after matching every
existing destination to its retained predecessor and backing up its old bytes.
The receipt is
`.local/rust-migration/native-phase6/execution-2026-10-21/promotion/receipt.json`.
The original private candidates and proof closures remain intact.

The current candidate additionally freezes parser actions and transitions in
flat immutable columns, shares terminal admission keys, and decodes artifact
rows directly into those columns. Singleton action validation avoids a set
allocation. Source publication bills its new traversal before allocation;
public limits are unchanged. Old-map construction and decoder oracles cover
ordered cells, empty cells, malformed-field precedence and exact work/count
boundaries. The construction test's private budget now includes that explicit
publication pass and continues to forbid another LR precision construction.

Workers reuse lexical ordinal buffers. Parsing has a 256-slot, 1 MiB bounded
pool of exact-stack permission proofs, cleared on each run; hash collisions
require full stack equality. Scanner questions and native transition charges
remain live. Deterministic reads avoid an initial queue allocation, reuse the
outer frontier buffers, and skip singleton frontier deduplication.

Fresh validation, measurements and packages belong under
`.local/rust-migration/native-phase6/execution-2026-10-21/`. The new
`tool/rust_qualify.py` records actual cross-toolchain test rosters and immutable
inputs; `tool/rust_bundle.py` forms a separate checked bundle while preserving
the raw static archive. Delivery supports explicit native108 with source-pinned
V3/S4 checks. Fresh workspace qualification of the edited sources now passes
381 tests with 16 declared ignores on each of Rust 1.85 and 1.96, both all-target
checks, formatting, Clippy with warnings denied, and a fresh release build.
The unchanged positive report is
`.local/rust-migration/native-phase6/execution-2026-10-21/qualification-3/report.json`
(SHA-256
`425610b7483cd70da1b1e609e1e0e019ef9b00614236ff0f6d3af093a43c0864`).
Fresh local working, ABI, CLI, governed consumer and installed Mac gates now
pass for this exact candidate. The compatibility join is
`.local/rust-migration/native-phase6/execution-2026-10-21/final-candidate-evidence.json`
(SHA-256 `b54177dd5b2fcf21d28f0c51f6a65baf218bffdc826bb23ce832e3314f22e972`):
31 canonical grammars, 14 witnesses, 55 classified CLI cases, 24 ABI commands,
64 consumer tests, 6,216 Go and 102,906 Python inputs, 125 helper controls and
40 extracted Mac commands. All 110,014 governed source files remain stable.
The immutable source export/package and measured runtime have their own exact
identities; later documentation updates do not replace those bytes.

The new full 1,546-command matrix completed with stable inputs and still fails
the selected 1.10 latency/RSS ceiling. Cold CLI median Rust/Zig ratios are
1.292/4.655/2.831/3.057 for JSON/large JSON/Go/Python. Holding that run's Zig
observations fixed, Rust needs median latency reductions of roughly
15/76/61/64 percent to reach the ceiling. Incremental and worker costs also
remain material work. See the [fresh performance review](rust/PERFORMANCE.md#fresh-public-candidate-full-cost-matrix).
No consumer or release default has changed. Target-floor execution, the late
sealed aggregate and release/adoption/rollback qualification remain separate.
The production-size goal remains separate design debt.

The same source2 closure also passes full release-profile suites on Rust 1.96
and 1.85 under Ubuntu 24.04 amd64 emulation, with all 381 passed/16 ignored and
zero failures/filters in each; the extracted installation repeats that roster
under Rust 1.85 and passes all 40 installed commands. The private producer then
failed in its final Path-only hashing guard. A distinct, positive read-only
audit verifies the actual logs, package and source/proof joins plus all three
remaining helper/tool/compiler guards, with no repeated runtime execution.
The original failed producer and first audit refusal remain retained. The
completion receipt is `linux-preflight/run-3-completion-5/execution.json`
under the current execution directory (SHA-256
`cfd82325c288dc7d093dc4f27e0299e250bbcabd98bfcc82aa949043b2ad6581`).
This establishes emulated Linux release delivery, with physical-host/debug/
timing/default qualification explicitly separate. See [the delivery record](rust/DELIVERY.md#fresh-public-workspace-native108-candidate).

One fresh late sealed attempt retained stable aggregate projections for both
backends, but measured 0 of 20 entries on each. The gate remains incomplete;
this establishes no comparative engine result or failure cause. Pins and
control files stayed unchanged, and raw diagnosis remains sealed. The receipt
is `sealed-gate/attempt-final-1/report.json` under the current execution
directory (SHA-256
`d85856d1aa046855ca04219ef5d185a3e4c59528842159e19b773b3cb72baf44`).
The attempt overlapped the capped Linux correctness build only after all cost
and profile work completed; that overlap carries no timing qualification.

The candidate also drains reduction frames without an intermediate allocation
and reuses empty bounded shift-frontier storage. Native bank members replace
their checked pending payload with an owned compiled grammar only after a
successful decode; failures retain the original proof for retry and concurrent
getters share one published grammar. This releases redundant raw artifact bytes.
The CLI directly decodes borrowed standalone artifacts when no explicit language
is requested, avoiding a second full payload copy while retaining the directory
path for explicit name selection. Tree, corruption, retry, lifetime, concurrency
and named-selection checks cover these paths.

That retained source has 24,225 first-party production Rust lines under the same
retained scope: 20,731 engine, 2,090 CLI and 1,404 C adapter. That is 417 more
than Image1 and 14,225 above the 10,000-line goal. Tests and the separate IRGX
dependency are excluded consistently; formatting was not compressed. The
source-bound count is retained at
`.local/rust-migration/native-phase6/execution-2026-10-21/current-production-count-final-source.json`.

### Performance follow-on checkpoint, 2026-10-22

The fixed runtime is now `c54221b` with native source `bf19d6b`. Fresh Q2
qualification passes all 457 default tests with 16 ignores on Rust 1.85 and
1.96, strict checks and a release build, with a complete 568-file input closure.
The same 457/16 named roster passes Rust ASan, with instrumentation verified in
33 launched binaries; native Zig/C and the prebuilt standard library remain
outside that instrumentation and leak detection is disabled. The complete
working replay also passes with stable custody: all 31 grammars, 14 extended
witnesses and construction census, 55 functional cases, 24 ABI checks, 64
default consumer tests, and all 6,216 Go and 102,906 Python inputs. Its report
is `.local/rust-cutover-2026-10-22/working-2/report.json` (SHA-256
`43ba2f979eb635343f592ab56f9e9c9a366738ba97d24872ceee43238b504036`).
Exact Q2 and ASan receipts are joined in the
[fixed-candidate review](rust/PERFORMANCE.md#fixed-cutover-candidate-2026-10-22).

Completed actual-host source CI for tooling commit `4cecfd8` retains the exact
compiled `c54221b`/`bf19d6b` maps and passes 457/16 on both compilers and hosts.
Its separate diagnostic reaches 5× in 6/120 groups; the earlier `c54221b`
source-CI run reached 7/120. These are distinct hosted replicates. The `4cecfd8`
summary is `.local/rust-cutover-2026-10-22/source-ci-4cecfd8-summary.json`
(SHA-256 `90b39cd692c5741d7055c4f57489687677c5868d973ad3ac7d5fcd2050655340`).
Later tooling `9327b86` has green source-CI jobs on both host targets and
standard CI by API status; its artifact custody and new diagnostic counts have
not been joined. The general 5–10× target remains unmet.

Fresh Mac and emulated Linux packages pass all 40 installed checks, with both
Linux Rust compilers passing the complete 457/16 roster. Mac archive SHA-256 is
`5c0bc72b6bc905595528d483891c64ff514701cde3fe5767349ee9f3e18bc4a1`;
Linux is `a59b0e62fe348bc51bcbaa23bb7e5fe2eff4a63b5dde410a0a4d2d7e70fd9b81`.
The private Mac aggregate is `e182268cea6119cbfb5478e20c10d270278b52b923bf99a8ca97099de962a3d6`;
the positive stable Linux outer receipt is
`2c2a452132bca384f01b4757c95ecbc1631799869861bf58b82acf4ec44617db`.
Fresh current-Q2 qualitative ready-load profiles also pass with stable custody;
automaton decode/validation, envelope integrity and native image loading are
principal sampled stack locations. The raw Q2 library is distinguished from
the installed Mach-O metadata derivative; sample weights establish no CPU
percentage, timing or engine RSS result.

The fresh source-attested Rust/Zig matrix completes all 1,546 commands with
all exit codes zero and stable custody of 146,994 input hashes, retaining 180
metric rows and 249 review triggers. The unchanged 1.10 ceiling still fails. Cold
median latency ratios are 1.106/2.364/2.043/2.215 for
JSON/large JSON/Go/Python; median RSS ratios are
1.068/1.463/1.638/1.565. These current-host diagnostics are
separate from the starting-Rust 5–10× comparison. Exact cost/profile receipts
and limits are recorded in the [fixed-candidate review](rust/PERFORMANCE.md#fixed-cutover-candidate-2026-10-22).
Actual installed-platform run `39890987250`, helper `9327b86`, passes all 40
installed checks and 457/16 on actual macOS 14 ARM64 and Ubuntu 24.04 x86-64
hosts. Independent collector receipt `c59bdfff…debd94` verifies the exact
packages, host floors, logs and complete retained proof custody. The single
authorized sealed attempt ends with exit code 1 and stable controls/pins:
Rust measures 16/20 entries and Zig 19/20, both with
`measurement_complete: false`. No complete aggregate is accepted; differing
measured subsets support no comparative correctness gain. The authoritative
report is `.local/rust-cutover-2026-10-22/sealed-aggregate-3/attempt-3/report.json`
(SHA-256 `1fcf93ec3757433424fad356b879ed46369c5311161f365e3cf44cc1a820aa37`),
with `no_unsealing: true`. Sealed qualification, adoption and release/rollback
remain open. The failed, unwaived cost ceiling and 249 review triggers keep
Zig as the default.

The retained Q7 source reclaims unpublished effects after rejected document edits
while preserving old versions and handles. It passes 443 default tests with
16 ignores on each Rust version, strict checks and a release build, with a
stable 564-file source/runtime-fixture closure. The same source passes 443
ASan tests with instrumentation verified in 33 binaries. Its report is
`qualification-7/report.json`. Its complete working replay passes all 31
grammars, 14 extended witnesses, 55 functional checks, 24 ABI checks and all
6,216 Go and 102,906 Python consumer inputs. The stable report is
`working-5/report.json`. Fresh installed checks pass 40/40 on the current Mac
and 40/40 under Linux amd64 emulation; both Linux compiler versions pass the
complete 443/16 release roster. The Q7 compatibility join is
`final-candidate-evidence-6.json`, with Linux execution recorded separately at
`linux-preflight/run-6/execution.json`, under the performance directory below.
The full 1,546-command benchmark completes with stable inputs but still fails
the 1.10 ceiling: cold median Rust/Zig latency ratios are
1.208/2.436/2.134/2.312 for JSON/large JSON/Go/Python; median RSS ratios are
1.080/1.522/1.642/1.531. All 180 metric groups and 244 review triggers remain
in `full-matrix/run-6/`. This is a contended current-host diagnostic, with
separate Zig ABI provenance limits. Physical floors, sealed qualification,
real adoption, release/rollback and the 10,000-line goal remain open.

The combined Q6 snapshot passes 440 default tests with 16 ignores on each
of Rust 1.85 and 1.96, strict checks, and a release build. Its complete 562-file
source/runtime-fixture closure repairs omissions found during Q4 reconstruction.
The report is `qualification-6/report.json` under the performance directory
below. Q6 selects charge arithmetic, eight-way permission buckets, and the
adaptive bounded successful-effect memo. The same selected source passes
440 ASan tests with 17 ignores and instrumentation verified in 33 binaries;
native Zig/C and the prebuilt standard library are outside that instrumentation,
and leak detection is disabled. Native image controls additionally pass a
ReleaseSafe replay with complete expanded build-package custody. See
[the safety contracts and receipts](rust/SAFETY.md).

Separate stable Q4 development runs complete 540 cold-CLI/admission commands and
693 native commands. Cold median Rust/Zig ratios are
1.141/3.034/2.076/2.238 for JSON/large JSON/Go/Python, and median peak RSS ratios
are 1.063/1.400/1.714/1.579. The 1.10 ceiling remains failed. Four-worker
per-document medians improve approximately 79–81 percent against prior Rust,
with retained tail regressions and diagnostic ABI provenance limits. These
runs do not replace the full 1,546-command protocol, installed qualification,
or the complete consumer inventories. See [the checkpoint and source-bound
receipts](rust/PERFORMANCE.md#intermediate-performance-checkpoint-2026-10-22).

The later Q6 development comparison completes the same 540/693 command rosters
with exact images and stable qualified inputs. Cold median Rust/Zig ratios are
1.116/2.607/2.248/2.372; median peak RSS ratios are
1.063/1.514/1.645/1.535. The ceiling still fails. The later native adjacent-target
and sparse-lexer metadata trials remain unselected after mixed or slower costs.
The fresh full acceptance matrix and installed-consumer checks remain separate.

The Q7 count is 25,737 production Rust lines: 22,235 engine, 2,093 CLI and
1,409 C adapter, 15,737 above the independent 10,000-line goal. Its stable
receipt is `production-count-current-4/receipt.json` under the performance
directory.

The retained Q6 count is 25,684 production Rust lines: 22,182 engine, 2,093 CLI
and
1,409 C adapter, using the same exclusions and formatting convention. This
is 15,684 above the independent 10,000-line goal. The count receipt is
`.local/rust-migration/performance-2026-10-21/production-count-current-3/receipt.json`.

### Remaining work after the follow-on checkpoint

The core feature and local compatibility implementation is present. The main
remaining engineering risk is total cost, followed by sealed qualification and
release adoption. A percentage based on ported files would hide that risk.

1. Reduce cold latency and peak memory. Stable parser-head ownership transfers,
   worker-owned lexical buffers, bounded permission reuse, compact tree/table
   metadata, and checked native image loading are selected in Q4. Fresh
   ready-load profiles identify automaton decode/validation, envelope integrity
   and native image loading as principal sampled stack locations. These are
   qualitative weights, without per-function timing or CPU-percentage claims.
   Further changes need separate measurements that preserve validation,
   work/head limits, and exact branches.
2. Preserve the unaffected prefix during edits. Both adapters use `prove=0`
   and `whole=2`; the public Whole contract re-derives past the edit. Rust now
   proves and reuses a bounded prefix, including approximately 93 percent of
   the large-JSON late-edit case. Effect-sequence reconstruction and complete
   tree materialization remain substantial costs. The Q5 memo reduces isolated
   late large-JSON edit medians by about 70–74 percent in two runs, with retained
   parse/worker/tail flags. Its warmed tiny-store memory cost motivates a private
   adaptive table, subsequently selected for 128-fold smaller one-key table
   buffers; its mixed latency flags remain retained and combined workspace
   qualification passes Q6. Further reuse must preserve
   source/read proofs, effect ownership, refusal atomicity, and bounded storage.
3. Reduce worker overhead. Separate parser sessions exist, but the Rust ABI
   has a process-wide handle-registry mutex. Handle removal can perform final
   tree or session destruction while guarded. A candidate change is to retire
   both tokens atomically, unlock, then finish owned teardown synchronously;
   it needs deterministic lifetime/concurrency checks and a separate measured
   comparison before selection. Parsing runs outside that registry lock and
   uses its own session lock. The fresh source-attested four-worker median
   per-document Rust/Zig ratios are 1.995/4.871/3.618/4.253 for
   JSON/large JSON/Go/Python, with p95 ratios 2.908/4.636/4.779/5.844.
   Q4 clones safe native workers for concurrent
   sessions and keeps their mutable buffers separate. Further lock changes
   require measured contribution and explicit owner/lifetime checks. The worker
   throughput timer includes Python/ctypes, strict validation and tree teardown.
   The earlier Q7 comparison's frozen Zig library remains unattested. The fresh
   CLI/ABI pair from exact Joints `9f5caf7` and IRGX `fc7a852` now passes source
   attestation and final custody, independently rechecked across 21,816 proof
   files. The
   receipt is `.local/zig-source-attested-baseline-20261022/attempt-3/report.json`
   (SHA-256 `e51c400487c3359ce4937dd78611f4820dd36d5e46412e26dd2a4116ae316ba4`).
   This closes the baseline-preparation gap for a fresh comparison only; it
   neither attests the historical library nor qualifies its measured ratios.
   The unchanged 1,486 scheduled commands and 60 admissions now complete
   against the fresh installed candidate with stable custody. The 1.10 ceiling
   remains failed; neither protocol nor budget is waived.
4. Requalify target floors after any candidate change. The exact current
   archives pass all 40 installed checks and 457/16 on actual Ubuntu 24.04
   x86-64 and macOS 14 ARM64 hosts in run `39890987250`, with independently
   retained package/log/proof custody. New sources or packages need their own
   immutable archives, committed helper and actual host execution. Current-Mac
   execution, emulation and deployment metadata alone do not replace that
   check. The earlier successful 213-byte transport probe `39882119855` skipped
   installed jobs and supplies no floor proof.
5. Complete the late sealed aggregate and qualify real installed-consumer
   adoption. The single authorized sealed attempt accepts no complete aggregate;
   its gate remains open. Keep diagnosis sealed and transition V3/S4 artifacts
   with the executable. The private candidate draft `421396620` remains unpublished;
   PR #2 remains a draft.
6. Complete Rust public release engineering. `tool/release/artifacts.py` still
   builds and accepts Zig packages and pins IRGX `508ad315`. Add a reviewed Rust
   release path, carry the exact approved native dependency, select and align
   release versions and changelog entries, and run exact-release checks before
   publication. Qualify rollback with the retained executable Zig cohort.
   The failed cost ceiling and remaining gates authorize no default switch.

The 10,000-line target remains separate design debt. Preserve behavior and
readability while evaluating it; reducing formatting or excluding required
product code is not progress toward that goal. Further runtime changes require
new qualification and fresh costs rather than reusing this candidate's passes.
