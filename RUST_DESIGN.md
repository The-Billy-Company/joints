# Native Rust parser design

Implement the [migration plan](RUST_REBUILD_PLAN.md) in phase order. The first
milestone is a generic grammar compiler, state-directed lexer, deterministic
parser with a concrete syntax tree, and guarded stack-effect algebra. JSON is
the first input grammar, not a special parsing algorithm. Parsing, grammar
compilation, trees, and guarded effects execute in Rust; tree-sitter remains an
independent test oracle. At the user's direction, reuse `irgx` as a dependency
instead of rebuilding its regex services. Its safe Rust API wraps the existing
native regex implementation, including Zig and PCRE2.

## Reference and phase gates

Phase 0 completed locally on macOS arm64: the existing Zig unit suite passed,
the pinned grammar inputs verified, and the rung-one sweep passed its measured
chain checks while retaining all refusals and unmeasured rows. The private
reference binary SHA-256 is
`709bf8c0ce4a3c9ad5deb400e42d5025439e76c45bbcfaaf0959be31cff768ec`.
The hardened reference bundle captured, verified, and replayed 36 cases with
zero failures. Its portable [JSON subset](test/migration/reference/manifest.json)
replayed all 25 cases. The full bundle is
`.local/rust-migration/reference-verified`; `tool/migration.py` owns reconstruction,
verification, and replay. Fifteen tooling tests check that absent or malformed
evidence, source drift, and executable replacement cannot count as success.

The Regulator reference is a parse of its checked-in grammar preparer under its
reviewed Python profile. It does not establish full facet equivalence. Linux
and installed-consumer validation remain later release gates.

Phase 3 found that this frozen profile's conflict declarations are incomplete:
Tree-sitter 0.26.11 also refuses the exact captured grammar and requests the
three-way `primary_expression`, `_default_primary_expression`,
`list_splat_pattern` conflict. The profile declares only two overlapping pairs.
The [reduced fixture](rust/tests/fixtures/profile-conflicts.json) preserves this
distinction: both native construction and the independent generator refuse it;
adding the exact three-party declaration makes both construct successfully.
Keep the frozen profile and its Zig parse as historical evidence. A reviewed,
versioned consumer recipe is required by the phase 5 Regulator gate;
do not relax conflict attribution to make this profile compile.

Phase 1 specifies all product areas below. Phase 2 must pass the JSON
no-recovery cases and guarded-algebra laws before grammar breadth work begins.
Default recovery goldens remain captured for phase 3. Implementing a later
feature never changes an earlier golden to make a disagreement disappear.

Phase 2 passed locally: 48 Rust tests, Clippy, formatting, release compilation,
and native replay of all 13 selected CLI cases. The ordinary-token DFA and
parser construction have deterministic scaling checks and explicit work limits.

Phase 3 passed its local cold-parser gate on candidate `acfa7e2fc5f5c349`.
All 150 default tests and Clippy pass. All 31 pinned grammars construct under
the public finite limits. The 66 scanner specimens all execute: 60 retain their
exact frozen trees, six match separately pinned independent corrections, and
all 66 retain their stop and repair records. Existing aspirational assertions
remain visible: 360 held, 17 still failing, none dropped or regressed. The full
reference replay has 35 exact matches and the independently justified refusal
of the invalid Regulator profile described above.

All 19 larger working sources execute without operational refusal, preserving
every previously strict case. Julia (6,945 nodes), Elixir (7,071), and OCaml
(7,419) match the independent complete trees. The Markdown tail correction,
three newly visible Kotlin `is` tokens, and Verilog's first diagnostic-token
difference have independent witnesses. Swift still has classified priority and
zero-width separator span differences; Haskell, Kotlin, SQL, and Verilog remain
partial on these larger inputs. Zig's four raw oracle findings remain recorded:
the independent repetition controls below identify a Tree-sitter 0.26.11 defect.
This gate establishes explained cold-parser behavior, not complete language
conformance or consumer readiness. Exact build/source hashes and raw reports
are retained under `.local/rust-migration`; phase 4 begins with this candidate
as its rollback point.

Phase 4 passed its local gate on candidate `cf4ccaa2c87ee10a`: 176 default
tests, formatting, and Clippy pass. Thirteen document contract tests execute
226 edit calls (207 byte changes, 14 no-ops, five intentional refusals). The
shared helper checks independently expected edited bytes before comparing full
cold trees and semantic products; all 25 portable JSON cases and every random
intermediate edit execute. Scanner state, distant lookahead, zero-width tokens,
GLR/recovery fallback, operational failure, and retained snapshots have explicit
controls. The 66 specimen gate remains unchanged, and all 19 larger-source
outputs are byte-identical to phase 3. The 36-case reference replay retains the
same 35 exact matches and invalid-profile refusal.

The measured sequence tests retain prior roots through 1,500 random splices
and compare ordered range products to independent linear folds. Across 256 to
65,536 leaves, mean single-leaf splice compositions rose from 25.26 to 50.84;
this counts compositions, not their internal cost or end-to-end edit latency.
The separate edit-cost record includes source copying, all attempted tree
materializations, and distinct retained snapshot payloads. That candidate has
about 12,657 production Rust lines under the same approximate convention;
queries, artifacts, and adapters follow in phase 5. Raw proofs and the local
gate record are under `.local/rust-migration/native-phase4`.

Phase 5 passed all 12 local qualification gates on release candidate
`e73eb9ee016afd74` (bundle `3d3c572062cbf5f8`). It passes 336 default tests, 14 explicitly
selected working-corpus witnesses, Clippy, formatting, and 66 helper tests.
All 31 pinned grammars construct; the 66 specimen results are unchanged,
and the full reference retains 35 exact cases and the invalid-profile refusal.
Eighteen of the 19 larger outputs are byte-identical to both earlier phase
baselines. All 95 changed Swift subtrees independently match; its remaining
two-node deficit comes from inherited multiline-member statement splitting.
The actual release C libraries pass all 62 header/export checks, C11 layouts,
static/dynamic parse-query-edit clients, and the existing Python and Rust
binding suites. Raw proofs are under `.local/rust-migration/native-phase5`.

The coherent Regulator snapshot's release ThinLTO build succeeds. All 12
reviewed artifacts mint and load. All 64 default tests now pass after correcting
Go toolchain selection, branch capacity, Swift/JSX scanner omissions, and
TypeScript ambiguity ordering. Independent controls and the broader replay
confirm the state-specific reconstruction and alias provenance correction.
The preceding candidate's full Go and Python failures remain historical
evidence. The qualified successor's contextual nullable-token correction fixes
all 17 empty-raw-string refusals. Its bounded persistent histories, exact-stack
admission slates, and shared-prefix derivation replay remove repeated work
under unchanged limits. A narrow static-precedence correction is applied to
freshly minted tables. Consumer projection corrections are retained as a
[reviewable four-file patch](test/migration/regulator/README.md), including one
independently verified Ruff visitor defect. With the original assertions and
corpus preserved, the fresh release consumer passes all 64 default tests,
all 6,216 Go sources, and all 102,906 Python sources. Independent fresh mints
produce identical artifacts for all 12 reviewed profiles. The qualification
report joins completed receipts with exact source, executable, runtime, and
corpus provenance at
`.local/rust-migration/native-phase5/qualification-E/report.json`. Two other
ignored consumer tests are manual measurements.
TypeScript/TSX's original profiles independently fail the pinned generator;
explicit v2 corrections add only its three sequentially requested conflict
groups. Original profiles and refusals remain evidence. A compiler budget
increase or broad conflict declaration was not justified.
The private governed dataset contains 110,014 files and 1,129,335,985 bytes.
It was assembled during active edits and explicitly sealed as a dataset
version, rather than claimed to be an atomic current Git checkout.

Including the CLI and C adapter, the qualified implementation has about 22,811
production Rust lines across 39 files. This excludes terminal unit-test modules,
blank/comment-only lines, integration tests, dependencies, and generated data;
inline test helpers remain in the approximate count. The 10,000-line target is
not met. Phase 6 is now measuring the complete product and preparing readable
simplifications and standalone packages. Target Linux/macOS correctness,
performance, memory, install, and rollback gates precede any default cutover.
The 622-file phase 5 source closure is retained before these subsequent edits.

The combined phase 6 candidate F, CLI `35f20e5cece02ef1` (bundle
`c03b29f397b965c2`), now passes a fresh full 12-gate compatibility qualification.
It passes 347 default Rust tests, 14 explicit witnesses, 93 helper tests,
Clippy, formatting, actual Rust 1.85 checks, and the complete C/binding gates.
The 31 constructors, 66 specimens, 36/25 frozen references, and 19 larger-source
classifications retain their required results. All 64 default consumer tests,
6,216 Go files, and 102,906 Python files pass under the original assertions.
Two independent fresh mints preserve all 12 qualified artifact byte sequences;
the post-run rehash verifies the full 110,014-file dataset.

F uses checked fixed recovery scratch, a private capability for already-verified
owned artifact bytes, and one fewer read-back on single-member inspection.
It also corrects the artifact version banner and macOS shared-library install
name. The engine, CLI, and C adapter total about 22,868 production lines across
39 files; the 10,000-line goal remains unmet. The full 628-file qualification
closure is retained at
`.local/rust-migration/native-phase6/compatibility-F-inputs/`; its positive
report is `.local/rust-migration/native-phase6/qualification-F/report.json`.
Subsequent delivery-tool and documentation changes have their own checks and
do not retag that historical source freeze. The 112 compiled inputs stay fixed.
The original F Mac regex tests passed, but the observed PCRE2 wrapper compile
call resolved to IRGX's bundled code; those runs do not establish two independent
backend copies.
A separate archive-boundary fix preserves all 105 public IRGX functions while
namespacing its 154 private globals. Its Linux and Mac prototypes each pass the
unchanged 347-test suite at Rust 1.85 and four independent-provider checks across
Rust 1.85/1.96 with and without LTO. Actual branch targets, archive members, and
byte-preservation proofs establish provider ownership. The reference reports
PCRE2 10.46 at runtime; IRGX's 10.49 version is source/build-attested because its
original archive has no private runtime configuration function. These are
delivery-boundary checks on the current Mac and emulated Linux, separate from
the original compatibility qualification. The shared helper suite now passes
149 tests. Fresh schema-2 packages from one 6,495-file offline export each pass
40 installed commands, including the unchanged 347-test suite and both four-arm
native-provider and C static-link checks. The actual hosts are macOS 26.6 ARM64
with SDK 26.5 and Ubuntu 24.04 amd64 under ARM Docker emulation.

The combined F cost matrix completes all 1,546 commands with stable custody.
The user authorized background work and battery power, so it is an observed-host
diagnostic, not an idle-host budget qualification. Go/Python cold CLI medians
remain about 11–12 times Zig and peak RSS about 3.3–3.6 times on these inputs;
see [the full cost review](rust/PERFORMANCE.md). The late sealed worker refused
before an accepted aggregate, and no raw diagnosis was read. The selected
10-percent latency/memory ceiling is unmet;
the sealed aggregate gate, and actual macOS 14/native Ubuntu 24.04 execution
remain open. Consumer and release defaults stay on Zig.
The additional working-only artifact probe passes all 31 frozen base grammars:
31 default-policy mints and 31 standalone inspections, exact report pairs, and
unchanged artifact hashes. This is separate from F's original 12-profile
qualification. Its report is
`.local/rust-migration/native-phase6/working-artifact-roundtrip/run-1/report.json`,
SHA-256 `ca332daecf40927412105c1bbf432f8f10f88ca3c26c40da24cf2d3dd734bc72`.
It does not identify the cause of the sealed worker refusal.

## Design rules

Follow [John Ousterhout's software design principles](https://web.stanford.edu/~ouster/cgi-bin/book.php)
by putting substantial behavior behind small interfaces. A client compiles a
grammar, creates a session, and receives a snapshot. It does not coordinate
scanner caches, LR stacks, interning pools, or tree builders.

Keep decisions local: grammar transformation belongs to the compiler, token
selection to the lexer, syntax construction to the parser, and guard composition
to the effect store. Functions should perform coherent work; do not split them
merely to meet an arbitrary length limit. Comments explain constraints,
counterexamples, and reasons that the type signatures cannot express.

Use distinct opaque IDs for symbols, states, productions, fields, and nodes.
Pattern ordinals never cross the lexer boundary. Tag public effect handles with
their owning store and reject foreign handles. Distinguish identity, zero,
unknown constraints, empty constraints, EOF, refusal, and operational errors
with enums and result types rather than integer sentinels or magic strings.

Use safe indexed storage. Bound grammar expansion, automaton size, regex
construction, parser work, and source offsets. Reject unsupported constructs
with typed errors. No silently dropped productions, scanner rules, or conflicts.
The engine forbids application-authored unsafe code. New dependencies must
replace real infrastructure rather than obscure joints's semantics.

## Native ownership and module boundaries

| Boundary | Owns and hides | Interface and invariant |
|---|---|---|
| Compiler | Ordered grammar AST, lowered BNF, FIRST/nullable sets, automaton, resolved actions, tree recipes | Compile grammar bytes into an immutable automaton or a typed diagnostic. Preserve authored order and use-site metadata. |
| Lexer | Compiled regex data, pattern-to-symbol attribution, precedence and extra metadata | Scan bytes from an offset against admitted symbols; return a typed token, EOF, or lexical refusal. |
| Compiled grammar | Automaton plus lexer program and immutable names | Shared by `Arc`; no document-specific mutable scratch. |
| Parse session | State stack, frames, pending extras, work buffers, and move trace | Parse through an exclusive mutable reference; clear per-input state before reuse. |
| Tree snapshot | Grammar ownership, original source bytes, flat nodes/children, roots, stop and repair evidence | Immutable and independent of session lifetime. A borrowed node remains tied to this snapshot. |
| Effect store | Shared automaton, canonical effects and all interning storage | Generate, compose, inspect, and fold opaque effects. Equality is constant time inside one store. |
| Document in phase 4 | Text, session, measured sequence, current snapshot and reuse checkpoints | Validate edit spans before mutation; expose a completed snapshot after each edit. |

An immutable compiled grammar and snapshot must support `Send + Sync`.
Workers own their mutable sessions and stores. Tests must reuse sessions across
many sources and share one grammar across threads. Do not make all parsing
serialize behind a shared mutable scanner lock.

Snapshots retain `Arc<CompiledGrammar>` because node kinds and fields address
its metadata. Future queries retain their grammar and verify tree identity.
Interned effect IDs must never address a pool cleared for another parse.

### Phase 6 design and size review

The historical phase-5 E source count separates product responsibilities below.
The combined phase-6 F total is 22,868 as reported above:

| Responsibility | Approximate production lines |
|---|---:|
| Scanner runtime and programs | 5,625 |
| Grammar compiler and table validation | 4,751 |
| Shared runtime, algebra, trees, and artifacts | 4,102 |
| Parser, recovery, and incremental proofs | 3,327 |
| CLI and research reporting | 2,084 |
| Queries | 1,518 |
| C boundary | 1,404 |
| Total | 22,811 |

These are physical source lines under the retained gate's approximate convention,
not a measure of complexity or a prediction that each category can shrink.
Compiler and scanner semantics alone exceed the proposed 10,000-line total.
The CLI includes bounded exploratory surveys and machine reports as well as
argument handling; replacing its argument loop cannot eliminate that behavior.

The review keeps the existing deep boundaries: a client compiles once, gives a
worker bytes, and receives an owned snapshot. Document edits publish a complete
new version transactionally. Queries bind to one grammar and borrow captures
from their source tree. C ownership checks and synchronization stay in the
boundary crate; native Rust clients do not pay for opaque handle lookup.
Grammar-scoped IDs, byte spans, refusal enums, and store-owned effects encode
different domains instead of relying on conventions about integers.

Prioritize a simplification when it removes a repeated decision, representation,
or proof. The phase 5 histories, admission slates, and shared-prefix chooser
already remove repeated copying and reconstruction behind private interfaces.
Their limits, invalidation, and equality checks are part of their contracts.
Do not replace them with an unproved cache, unify budgets with different
semantics, or split coherent functions into shallow forwarding layers merely
to shorten methods. This follows Ousterhout's emphasis on general-purpose deep
modules and his explicit distinction from arbitrary method-length rules in
the [second-edition notes](https://web.stanford.edu/~ouster/cgi-bin/book.php).

The remaining review is empirical: separate compile/load, parsing, tree
materialization, C navigation, edit positions, and independent-document work.
Specialized storage or a new dependency needs a demonstrated cost or a concrete
reduction of infrastructure. A source-count reduction alone cannot qualify a
change. Retain complete behavior and readable formatting while evaluating it.

## Grammar compilation

Preserve the order of authored JSON rules. The first rule is the start symbol;
add a distinct augmented start production. Classify plain literal/pattern rules
and explicit token wrappers as lexical atoms, retaining literal versus regex,
immediacy, signed lexical precedence, and declaration order. Syntactic wrappers
remain structural unless the grammar explicitly makes them tokens.

Lower sequences and choices to productions, and repetitions to invisible
left-recursive helpers. Preserve epsilon alternatives. Hidden authored rules
and supertypes splice their children; invented helpers are separately classified.
Fields and aliases belong to production steps, not globally to a symbol.
Reject unknown references, malformed forms, expansion beyond limits, and
unsupported features explicitly.

Construct LR(0) states in deterministic order. Compute LALR(1) lookaheads by
propagating FIRST sets and nullable suffix lookaheads within closure items and
across automaton edges to a fixed point. Seed the augmented start with EOF.
Only propagate from an item with a reachable lookahead: an empty lookahead set
must not spontaneously seed FIRST of its suffix on an unproductive path.
Retain every automaton transition even if conflict policy later removes an
action: effect composition asks about the graph, not only the chosen action.

Cursor identity keeps future syntax, the currently speaking precedence region,
and complete tree/field/alias/reserved/dynamic metadata. Earlier consumed
history can share a cursor when those future observations agree. A completed
cursor names a `ReductionId` family, distinct from a concrete `ProductionId`.
Before reducing, resolve a family member against the actual frame symbols;
recovery additionally proves the complete borrowed/overlay state path. Keep
concrete production IDs in syntax recipes and effect traces. A missing witness
is a refusal, never a reason to weaken symbol guards or select a representative
whose RHS differs. Canonical LR(1) remains a bounded fallback for unresolved
LALR contexts; immutable interned lookaheads share storage, not permissions.

Automaton construction has one shared work budget across cursor construction,
FIRST/lookahead propagation, context refinement, and exact fallback. A fallback never resets
the budget. The current finite policy permits 131,072 states, 10 million items,
and 3 billion work units. The pinned Verilog grammar measured 80,893 canonical
states, 6,765,899 items, and 2,164,356,322 total units; the earlier 2-billion
ceiling refused that input. Its roughly 43-second construction and 1.44 GB
peak RSS remain costs to address at phase 6, not evidence of a performance
improvement. Limits are configurable and do not establish a universal grammar
size bound.

Lookahead merging can change a settled shift/reduce decision even when no
residual conflict remains. Compare the decision with its unfrayed precedence
and continuation evidence; a changed decision requires exact context. Harmless
frays retain LALR tables. Exact LR(1) is also the fallback for a residual pure
reduce/reduce cell; only a complete canonical cell may prove an undeclared
conflict. The pinned Julia grammar measured 101,425 states and 8,833,069 items,
which motivates the 10-million-item policy. Broad canonical fallback for every
fray and repeated targeted refinement were measured and rejected; the former
needlessly exceeded size limits, and the latter exhausted the shared budget.

Initially refuse unresolved conflicts. Phase 3 adds declared GLR alternatives
and static/dynamic ranking using authored provenance. Never choose a yacc
default merely to make a grammar compile. Authored precedence region widths
must survive folding; widths recomputed from lowered alternatives can reverse
the intended parse. See [the recorded counterexample](research/press/RESULT-3-authored-width.md).

A numeric shift strictly below an implicit-zero reduction loses before dynamic
or declared ambiguity ranking. Do not retain a spare shift merely because its
precedence was unwritten on the reduction. Equal-level and frayed-context
continuations retain their existing rules. This distinction prevents negative
typed-parameter precedence from preserving an exponential set of lambda
annotation readings. The [static precedence controls](rust/tests/static_precedence_contract.rs)
compare independent trees and retain equal-level and declared counterexamples.

Reserved-word contexts are a known limitation inherited from the Zig compiler.
Preserve the authored metadata and report `CompileLimitation::ReservedWordContexts`
through the compiled grammar; do not claim enforcement from accepting the
wrapper. Runtime strict confidence establishes acceptance by the compiled
tables, sound structure, and absence of repairs. It does not certify constraints
listed in `grammar.limitations()`. Implementing reserved-word lexical contexts
requires an independent keyword-versus-identifier witness and state-specific
context handling, rather than globally banning spellings used as property names.

## Lexing

The scan operates on source bytes. It considers only parser-admitted terminals
and applicable extras; terminals requiring an immediate position are excluded
after an extra has been skipped. Return visible named extras as tokens so their
tree placement remains the parser's decision. A regex matching zero bytes does
not advance the scanner and is never an ordinary token.

The phase 2 `regex-automata` prototype established the selection contract. In
phase 3, reuse `irgx::Munch` through its safe byte API, with one slate per
lexical precedence tier. Restrict the native walk to eligible pattern ordinals;
filtering only its final winners loses earlier admitted matches. Reject native
pattern refusals explicitly and preserve transition budgets across the library
boundary. Scanner probes use `irgx`'s PCRE byte-capture arm with bounded match,
depth, and heap resources; exhaustion must remain an error, never "no match."

`CompileOptions` separates table-construction limits, `LexerLimits`, and
`ProbeLimits`; immutable compiled data retains the matching policy for every
worker. Probe defaults retain 100,000 match steps, 65,536 interpreter depth,
and 8 MiB matching heap. The original 1,000-depth/1 MiB policy refused valid
1,879-byte HTML script and 9,282-byte Elixir heredoc bodies; independent cap
experiments showed the latter needs both depth and heap headroom. These are
finite configurable ceilings, not a language-size guarantee. Zero is an
explicit budget. Reject values that the native interface would truncate or
reinterpret as its default sentinel, and require heap limits in whole KiB so
the configured byte count is exact. Ordinary scans separately meter native
DFA transitions across all precedence tiers, including failed matches.

The integration currently uses the sibling `irregex/bindings/rust` package at
version 2.6.0 with additive byte and metering APIs. Native validation records
both the binding source and the archive actually linked. A standalone release
requires publishing those additions or supplying an explicitly pinned source
dependency; an unchanged registry package does not contain the new methods.

The phase 6 `sheng` trial uses its whole-subject refutation contract. It
proves whole subjects match-free; it does not provide exact token spans or
replace state-directed maximal munch. Any use must save measured work, retain
an exact confirming engine, and handle its cost gate declining a sieve. Do not
put a full-subject prefilter in every token scan by assumption. The inspected
source is commit `49257fd0f82649f0247fab8d47c3eec8d2be2fd6` (version 0.2.0,
Rust 1.95 minimum). Its optional private trial preserves the product's Rust
1.85 floor; an unconditional dependency would raise it.

The exact-E-native semantic trial passes 1,420 predicate comparisons and 568
scalar/SIMD refutation controls over arbitrary byte subjects. All five candidate
literal patterns decline the cost gate. The advisory adapter preserves one
exact `irgx` call and therefore saves no exact work. A separate authored
necessary-literal experiment refutes a subject while exact PCRE2 returns
`BudgetExceeded` at each of four finite match limits; skipping confirmation
would suppress an observable error. No general extractor or per-token shortcut
is justified by that experiment. Production adoption is declined, and no
overhead-only benchmark is presented as an improvement. The preserved report is
`.local/rust-migration/native-phase6/sheng/semantics-3-e-native/report.json`.

Selection order is lexical precedence first, then length. Equal-length ties
use literal/pattern/extra standing, immediacy within that standing, and authored
declaration order. Preserve the grammar's word/keyword behavior. Extras that
the parser explicitly admits are structural tokens at that site, independently
of whether their nodes are named.

An ordinary nonliteral regex token may be empty only when the actual structural
stack permits its shift after reductions. Auxiliary-extra FIRST donations do not grant
that permission; external/provided roles and context-free reads stay
positive-width. Normal precedence and longest-match rules still apply. End of
input wins when the actual stack can accept it, and zero-byte source conservatively produces
End. A required empty token after existing source may precede End. Parser work,
node, and stack limits bound nonadvancing cycles; no partial result is published
on a resource refusal. Cache receipts retain and charge the exact structural
permission and End priority before reuse. Independent positive trees, shared
negative controls, and edit/resource checks are in
[the nullable-token contracts](rust/tests/nullable_token_contract.rs).

An immutable admission slate caches permission proofs for one complete concrete
state stack. Full stack equality guards reuse; a matching top state alone is
insufficient. Keep ordinary admissions, structural empty-token permission, End
priority, and document-extra donations distinct. Reuse the permission sets,
then execute each lexical/scanner question against live source, cursor flags,
and scanner memory. State changes and restored checkpoints clear the derived
cache. Charge construction, equality checks, sharing, and lexical execution;
cache hits never make scanner answers reusable without their separate proof.

New authored phase-6 diagnostics expose two gaps in F's implementation of this
contract. Its End bit comes from the raw merged row, so a donated End can hide
a required empty token even when that token has a successful concrete proof.
Its positive-token filter retains `Unknown` after the 256-work proof cap; a
donated longer token can then win lexing and fail in the actual caller context.
The eight-input adaptive/canonical diagnostic records both causes and confirms
strict canonical success for the seven valid inputs. The private correction
passes 355 default tests (16 ignored) and all-target checks on Rust 1.85 and
1.96. The private combined candidate with the selected SHA update passes 357
default tests on each toolchain, Clippy, a fresh release build, 31 byte-identical
artifacts, and all 14 working witnesses. Fresh local qualification also covers
55 classified CLI cases, C/Python/Rust ABI consumers, 64 default consumer tests,
6,216 Go inputs and all 102,906 Python inputs. All 110,014 source hashes remain
stable. The ABI evidence retains its initial failure and a separate corrected
archive-normalization run. This candidate has no performance result yet.
Unknown must remain distinct from both a positive proof and impossibility;
resource refusal must remain an error. The retained diagnostic is
`.local/rust-migration/native-phase6/baseline-admission-review/diagnostic/run-1/`.

The correction uses the existing parser executor to establish whether a
provisional lookahead actually shifts or accepts. Only an ordinary all-path
structural stop permits another election from the original complete head;
typed errors propagate, and consumed work and drafts remain charged. Accepted
End retains deterministic cache recording; a failed End retry or provisional
checkpoint replay invalidates it. It preserves the original longest failure
when every candidate stops, and never retries a token after a committed shift.

Extras use separate lexical reads. A bare literal shared with a structural
token can remain visible, while an atomic lexical separator has a private,
invisible identity. An alias inside a token or around a lexical extra does not
introduce a syntax node; structural aliases outside those lexical boundaries
still retain their authored tree recipe. Alias metadata remains validated.
Aliased symbol-shaped extras are refused, as they are by the pinned generator.

This contract does not implement Tree-sitter's separator closure inside a
token match. In the authored grammar `doc = seq("(", "x", ")")`, with
`token("x")` as an extra, Tree-sitter 0.26.11 parses `(xx)` with one structural
`x` spanning bytes 1..3. Native separate reads retain `x` at 1..2 and skip the
second separator. The frozen Zig engine also lacks this closure; its literal
extra additionally becomes visible. Keep the independent controls and the
native distinction explicit rather than claiming identical tree spans. Make
continuations require their own full-tree comparisons: matching strict/refusal
verdicts alone does not establish Make tree conformance.

Required counterexamples are JSON's `string_content` outside a quoted string,
comment-looking text inside a string, a short high-precedence token beside a
long low-precedence token, an admitted short pattern beside an excluded long
pattern, and immediate versus ordinary spellings. The
[current scanner tests](src/kernel/lex/scanner_test.zig) define these distinctions.

The independent oracle also has limits. Tree-sitter 0.26.11 truncates regex
`{n,}` to its minimum in the authored repetition control, while `{n,m}` and
an explicit fixed prefix followed by `*` agree with PCRE2, Python, frozen Zig,
and native Rust. Its [pinned expansion source](https://github.com/tree-sitter/tree-sitter/blob/v0.26.11/crates/generate/src/prepare_grammar/expand_tokens.rs#L298)
explains the disconnected unbounded tail. Keep standard greedy repetition in
Rust; [the regression](rust/tests/regex_contract.rs) checks it against PCRE2.
This accounts for the two longer `\xffc` escapes in the working Zig file and
their adjacent content nodes. Retain the four raw comparison findings rather
than report an exact Tree-sitter match or alter the grammar's `{2,}` silently.

## Parsing trees and confidence

The first runtime is an independent deterministic LR walk. The top state's
action row supplies lexical admissions. Reductions consume their right-hand
sides, construct syntax using their tree recipes, and follow goto from the
uncovered state. Keep a move trace for algebra comparisons.

Declared alternatives extend the same executor with independent heads: each
owns its cursor, exact scanner state, LR stack, pending extras, scores, and move
trace. Lex each head from its own actual stack admissions. Process births in
FIFO order and authored action order; ambiguity ordering is observable.
Forked move histories share immutable chunks of at most 64 records and copy
only the bounded tail. Optional document move ends use the same representation.
Materialize the selected history once into the session's flat arrays; move
ordinals and retained checkpoint boundaries keep their meaning. Charge forks,
iterator setup, import, and materialization for the storage actually visited.
Drop shared chunk chains iteratively so a long file cannot overflow the call
stack during destruction.
When a reduction family contains several consumed histories, order reduction
ties by the concrete production matching that head, preserving shift positions.
A family's earliest representative cannot stand in for another member's order.
In particular, the Elixir definition fixtures require the outer call to own
the do-block. Prefer larger accumulated dynamic precedence. Inferred cells
retain their action-order penalties; a true declared alternative has no such
penalty. If a clean history crossed a declared ambiguity, equal dynamic and
inferred scores compare its concrete authored derivation by underlying symbol
and arity in preorder. Generated helpers are transparent. A hidden unit
reduction is transparent only in an eligible pure-unit LR state: aside from
lexical-extra shifts, every action must reduce one child with an empty effective
tree recipe to the same eligible hidden symbol. Ordinary shifts, acceptance, other reductions, inherited fields,
remaining alias recipes, aliased wrappers, extras, and supertypes prevent this
elimination. Reconstruct the concrete pre-reduction state from the actual trace;
cache the bounded, immutable-grammar eligibility analysis within the session.
Aliases and field spellings do not replace symbol identity.
Reconstruct only at real merge/accept ties, charging visits, temporary nodes,
and comparisons before allocation. Retain each reduction's immediate RHS in
an indexed forest, including transparent reductions. Cache canonical arities
and expand that forest during preorder comparison. Flattening a generated
repetition after every reduction copies its growing prefix quadratically;
the forest keeps reconstruction and traversal linear in the actual history.
Its temporary helper nodes also consume the shared node allowance.
The chooser is shared by merge, acceptance
retention, and final selection. Its [independent controls](rust/tests/declared_choice_contract.rs)
include static/dynamic precedence, rule order, hidden rules, fields, aliases,
artifact reload, and incremental replay. This defines the native authored
ordering; it does not claim complete equivalence to Tree-sitter's generated
helper numbering. Entirely inferred-only histories, failed histories, and any
comparison involving a repaired history retain their previous dynamic/birth
arbitration. An exact final tie keeps the old merge/accept incumbent convention.
Never discard a reading silently to satisfy the head cap.

Within one comparison, identical initial states and exact move equality prove
a common history prefix. Replay it once into an immutable indexed forest, then
fork the small concrete LR stack and replay each distinct suffix. Node indices
cover the shared arena and each private tail; count the prefix once and both
tails against the temporary node allowance. Unequal entry states receive no
shared-prefix proof. Keep this sharing local to the comparison rather than
retaining large derivations between comparisons.

Width alone is insufficient for unit transparency. The initial width/field
approximation passed the small generic-call controls but added 20 incorrect
PHP union-type wrappers and changed 25 Swift navigation groupings in the larger
replay. Independent pinned parsers confirmed both regressions. Tree-sitter's
[unit-state minimizer](https://github.com/tree-sitter/tree-sitter/blob/v0.26.11/crates/generate/src/build_tables/minimize_parse_table.rs#L52)
tests complete LR rows, with inherited recipe metadata and alias exclusions;
even authored alternative count is not the criterion. Native state partitioning
can differ, so retain both the tiny state/metadata controls and the actual
PHP/Swift full-tree witnesses rather than claiming universal optimizer parity.
Native field summaries use a conservative boolean closure. They can retain a
unit that upstream visible-field pruning would erase, which can affect an
unmeasured ambiguity tie.
Rule extras use separate native LR entries. Their possible ordinary starts
protect document states only where the terminal key is absent; an existing
reduction keeps that key. This guard is scoped separately from auxiliary extra
reads. Extras without symbol descendants are lexical atoms in both native and
frozen Zig lowering, which can produce a different CST from Tree-sitter's rule
extra. The independent extra controls preserve that pre-existing difference.

The reference's executable `crowd` cap is 64; its older comment saying eight
is stale. At that bound it can decline new forks and continue. Native limits
instead refuse the operation explicitly. Coalesce exact twins before applying
the bound, and measure the necessary finite policy on the named working files.
A partial result obtained by withholding a branch is not an oracle proving
that all competing readings were evaluated.
The initial native default was 512 readings and 160 million work units: named
Swift/Elixir/Haskell runs measured peaks of 216/320/400 distinct readings and
the Haskell run used about 135 million units with the complete concrete-family
state-path proof included. The real consumer's twelve nested Go calls require
8,192 live readings: twelve independent call/type choices plus the late
selector's qualified-type alternative. The current default is therefore 8,192;
the work, node, lexical, and stack bounds are unchanged. Both independent full
trees match, while an explicit 512-reading policy refuses predictably. The
frozen Zig parser loses these rivals even at depth six. These are expanded
supported cases, rather than evidence that early pruning is safe.

This representation can still grow exponentially with independent ambiguities.
The finite bound does not promise arbitrary nesting; private optimized probes
of these two inputs used roughly 117–126 MB peak RSS. Those diagnostic samples
are not the phase 6 performance gate. A packed stack/forest representation is
the condition for removing the exponential head population; merely sharing
stack allocations would not change its count.

Draft syntax is immutable and use-site aliases and fields belong to each use.
Only the selected forest is materialized into snapshot nodes with parent links.
A losing branch cannot rename or reparent nodes in the winning tree. Inline
dynamic ranks merge by strongest absolute magnitude before runtime accumulation;
normalization must neither lose a rank nor count the same authored weight twice.

Each structural frame owns its produced nodes and extras read before that
symbol. A reduction claims only extras between its first and last structural
symbols. Leading extras remain outside the reduced node; trailing extras await
a later parent. Extras never inherit fields. A hidden child splices its nodes
and propagates the use-site field only where a nearer field is absent. A visible
wrapper receives its own outer field independently of its children's fields. Aliases rename
visible nodes or introduce the appropriate wrapper for hidden structure.

Swift's implied separators retain a known span difference inherited from the
Zig scanner: they are zero-width at the preceding cursor, while the pinned
Tree-sitter scanner marks their end after crossed whitespace. The authored
source `func f() {\n  return 1\n  }\n` produces a `statements` span of 13..21
in both native and frozen Zig, versus 13..24 in Tree-sitter 0.26.11, with all
three accepting without repairs. This is recorded in
`.local/rust-migration/native-phase3/swift-separator`; it is an explicit
compatibility limitation, not an exact independent-tree success.

Use flat indexed nodes and child runs. Preserve half-open byte spans and
original byte text. Positions are zero-based rows and byte columns. On
acceptance, the visible start node also receives unclaimed outer extras and
extends to EOF. Leading whitespace does not extend its start. A whitespace-only
document is an empty root at EOF. A stopped parse retains its completed forest;
it must not invent a successful start-symbol root.

Compute a real structural survey over every result: bounds, child containment,
sibling order, parent ownership, duplicate visits, and reachability. Strict
success requires accepted stop, sound structure, exactly one root, and zero
deletions/supplies. Diagnostic parsing returns evidence even on refusal.

The first comparison policy is `--mend=none --no-supply`. It records the exact
first stop and has no repair scars. Parser-state numbers and speculative arena
capacity are implementation details; compare semantic trees, confidence, and
repair facts while retaining raw reference diagnostics for investigation.
The comparator excludes `survey.held` (arena occupancy), retaining `walked`,
soundness, and every structural finding. For `json-stray-default`, Zig keeps
three suppressed ghost-derived nodes in its arena (held 9, walked 6); Rust
materializes the selected forest only (held 6, walked 6). Both publish the same
six nodes and repair evidence. The raw golden remains unchanged.

The initial corpus must include empty and whitespace-only input, multiple
top-level values, nested fields, comments, escaped/empty strings, UTF-8 byte
positions, invalid bytes, truncated containers, and illegal token placement.
Use the portable golden fixtures and
[hand-derived Zig expectations](src/kernel/quire/gather_test.zig).

## Guarded stack effects

Represent an effect as identity, zero, or a run. A run records its entry state,
an ordered ledger, and a pushed symbol sequence. At each popped depth, the
ledger constrains both the possible state underneath and the possible symbol.
Each constraint is Any or a canonical finite set; empty is not Any. Depth one
is the nearest popped symbol. Persistent sequence/interner details stay private.

To compose left then right, walk the left push from each possible left floor.
If the left ledger is empty, its sole starting floor is its entry state;
otherwise filter the deepest state set. Check right-hand claims only where
they overlap the left push, retaining deeper claims as debt.
At every depth the right ledger reaches, check both its state and symbol
constraints. The walk must finish at the right entry state. Refuse if no left
floor survives; otherwise narrow the left's deepest state constraint. Remove
the portion of the left push consumed by the right, or preserve the right's
remaining debt below the combined ledger if it reached deeper. Append the right
push. Never discard an interior constraint or approximate missing stack depth
with reverse reachability. Boundary grounding is a separate check.

Zero absorbs, including beside identity. Incompatible composition yields zero;
invalid handles or requests are errors. Grounding zero is false. Whole-effect
interning is an acceptable first representation: construction may scan sequences,
but canonical handles retain constant-time equality. Measure before introducing
a more complex persistent representation.

The current store strongly retains every distinct run until it drops. A
document keeps its store across edits, including entries from unpublished
attempts. Per-operation budgets and the separate receipt-cache cap do not bound
this cumulative storage. Long-lived document memory needs its own measurements;
any later reclamation scheme must preserve the validity of retained handles.

Tests must include two-sided identity, absorbing holes, all triples from a
small real automaton with equal defined/refused association outcomes, ledger
interior-depth preservation, wrong symbols, wrong floors, guard narrowing,
debt propagation, every segmentation versus the direct fold, foreign-store
rejection, and an independent concrete-stack oracle. Shape-only measurement
keys never prove equality. Exploratory history widening is deliberately lossy
and remains separate from exact actual-move composition.

## Incremental documents

`Document` owns a session, effect store, measured sequence, and current
`Arc<TreeSnapshot>`. It accepts checked byte spans, including non-UTF-8 source.
Build an edited version privately and publish its source, tree, and sequence
together after all operations succeed. Invalid spans and operational failures
leave the previous version intact. Retained snapshots remain immutable and
independent; byte-equal replacements retain the current snapshot without work.

The concrete sequence stores byte-weighted actual-move effects in an immutable
AVL tree. Branches cache byte/leaf counts and the ordered product. Splices
replace whole leaves; the sequence never guesses where a token or effect can
be split. Zero-byte leaves retain empty-file or EOF effects, and byte lookup
reports coincident boundaries explicitly. Every tree belongs to one effect
store, whose ownership checks apply even beside absorbing zero. Equal prefix
and suffix measurements can keep their old branches after a parse; this is
distinct from avoiding parser work.

The first reuse path resumes a deterministic prefix, without suffix subtree
lifts. A checkpoint must be at a collapsed single-head boundary, with no
accepted competing frontier, previous branch, repair, auxiliary trial, or
in-flight lookahead. It retains the complete head and immutable draft-prefix
high-water mark. All reachable draft spans must end before the edit. Ambiguous
or repaired runs take the cold path until their complete frontier and repair
seams have a separate proof.

Unchanged prefix bytes and entry state do not establish lexical equivalence.
For example, `a.*z|a` can initially return `a` after exploring a distant suffix;
inserting `z` there changes the earliest token. Revalidating one preceding
stride, as the legacy implementation does, cannot prove this safe. The initial
Rust implementation reexecutes every retained primitive lexical decision on
the complete edited source under its original permission, stack, cursor flags,
scanner effects, and trial/rollback schedule. It compares outcomes and semantic
scanner state, including failed asks and rule-extra trials. A mismatch declines
the checkpoint. Resumption uses the freshly validated scanner state and new
source index, never an old source-index cache inferred valid from pointer and
length equality.

Cache storage and deep cloning are bounded; exhausting an advisory cache
stands down reuse. Validation and fallback attempts share finite work budgets.
Work limits charge the executed proof and parsing work. Their operational
refusal thresholds can differ from a cold run because reuse both adds
validation and avoids old LR execution; completed results must still agree.
Direct cold session calls do not pay receipt-capture costs. Actual moves retain
byte ends for segmentation, zero-width reads ride with the next byte-bearing
segment, and EOF folds and trailing source remain in the measured product.
After every edit, compare the full tree, positions, stops, repairs, confidence,
and semantic product against a separate cold parse. Include distant lookahead,
scanner-memory and zero-width counterexamples, malformed intermediate source,
and cases that require genuine prefix reuse and conservative fallback.

`DocumentCost` distinguishes copied source bytes, source retained by the current
snapshot, materialized nodes, parser/lexer work, and sequence compositions and
allocations. Keeping old snapshots and edit positions are measured separately
in profiling. A logarithmic sequence splice is not a claim of logarithmic
total edit time; prefix validation and flat output construction remain visible.

## Later product contracts and their evidence

### Compiled artifacts

Native grammar and bank envelopes use `JNTRART\0` and `JNTRBNK\0`, explicit
little-endian lengths/tags, bounded decoding, and a SHA-256 integrity seal.
The current draft is envelope version 2 and table schema 3. Loading restores
compiled LR tables, concrete histories, lexical definitions, scanner selection,
and matching limits without LR construction. Banks retain owned bytes and
load members lazily into shared grammars. The seal detects corruption; it is
not authentication.

`Step.alias_recipe` retains typed `AliasRecipe::Empty` or `Local` information
computed before explicit inline lowering. Rendering aliases remain use-site
facts. Default-alias clearing and inline propagation can produce identical
rendering recipes with different local-alias effects on hidden-unit ordering;
reconstructing that distinction from normalized steps loses information. It
must participate in recipe identities, survive artifacts, and be validated on
decode. An impossible local marker without an alias is refused.
The analysis follows native sequence/choice factoring; upstream extracts
default aliases over fully flattened productions. Factoring can affect alias
frequencies and encounter ties, so this preserves native pre-inline provenance
rather than reconstructing every upstream default-alias decision.

Draft native version 1/schema 2 artifacts and legacy Zig `OTLFOLIO`/`OTLCODEX`
bytes are explicitly refused. Re-mint from the retained original grammar JSON
with the chosen runtime. Keep each backend paired with its compatible artifact
set for rollback; changing a filename does not migrate its bytes. Round-trip,
independent-build determinism, bank membership, truncated/corrupt/resealed
metadata, resource ceilings, and obsolete-format refusal are explicit tests.

### Query behavior

The source implementation, rather than its older prose counts, defines the
supported vocabulary. [Rubric](src/kernel/gloss/rubric.zig) distinguishes bare
`_` (any node) from `(_)` (a named node with optional child constraints), named
rules, anonymous strings, `supertype/subtype`, fields, absent `!field`, groups,
choices, multiple captures, `?/*/+`, and leading/intermediate/trailing `.`.
Anchors constrain named siblings; named extra comments participate. Quantified
groups are greedy and collect their captures in one match. A group used as an
alternative of a choice is explicitly declined at execution; the eager public
API must refuse the entire result rather than publish partial matches.

Resolve names to sets of grammar symbols and aliases, with named/anonymous
sorts distinct. Compute supertype membership and possible fields through hidden
productions to a fixed point. An uncertain static reachability check must not
mark a valid pattern impossible. Pattern indices follow authored source order;
capture IDs are query-local and capture arrays retain multiplicity. Deliver
matches by their finishing position, then the ancestor that opened higher,
then earlier pattern. An outer pattern may finish after an inner one.

[Sift](src/kernel/gloss/sift.zig) recognizes **six** core predicate spellings:
`eq?`, `not-eq?`, `any-of?`, `not-any-of?`, `match?`, and `not-match?`.
Equality's second argument may be text or a capture; membership requires text
arguments; regex requires one capture and one constant pattern. Validate arity,
argument sorts, and regex construction while compiling. An unbound optional
capture leaves its predicate unconstrained. A directive ending in `!` retains
its spelling and arguments and never filters; other opaque predicates use the
explicit refuse/admit/deny policy. The default refusal publishes no matches.
Queries own their source metadata and grammar, reject a tree from another
grammar identity, and evaluate predicates against the snapshot's original bytes.

### ABI and CLI inventory for phase 5

Keep [ABI 2](include/jnt.h) as the signature/layout authority. The adapter's
coverage gate must account for every declaration in these groups:

| Group | Required functions and behavior |
|---|---|
| Version and errors | `jnt_abi_version`, `jnt_version`, `jnt_last_error`; thread-local non-consuming error reads, cleared by a successful call. |
| Banks | `jnt_open`, `jnt_close`, `jnt_bank_count`, `jnt_bank_title`; grammar JSON or versioned artifact, exact language roster, bounded name access. |
| Parsers | `jnt_parser_new`, `jnt_parser_free`, `jnt_parser_language`, `jnt_parser_blind`; a missing language is selected only for a single-language bank, with one mutable worker per parser. |
| Trees | `jnt_parse`, `jnt_tree_free`, `jnt_tree_stop`, `jnt_tree_stop_at`, `jnt_tree_stop_word`, `jnt_tree_mends`, `jnt_tree_skipped`, `jnt_tree_supplied`, `jnt_tree_sound`, `jnt_tree_sexp`; partial parses are successful operations with diagnostic trees, source bytes survive the call, renders belong to their tree. |
| Repairs and roots | `jnt_tree_scars`, `jnt_tree_scar`, `jnt_tree_scar_word`, `jnt_tree_roots`, `jnt_tree_root`; scars are authoritative and have the documented C layout, supplies are zero-width, missing indices are explicit absence or `JNT_INVALID`. |
| Nodes | `jnt_node_name`, `jnt_node_named`, `jnt_node_start`, `jnt_node_end`, `jnt_node_kids`, `jnt_node_kid`, `jnt_node_field`, `jnt_node_parent`, `jnt_node_next`, `jnt_node_prev`, `jnt_node_next_named`, `jnt_node_prev_named`, `jnt_node_by_field`, `jnt_node_depth`, `jnt_node_covering`, `jnt_node_spread`; indices are local to one parse and bounds checked, roots are siblings, extras never inherit a field. |
| Queries | `jnt_query_compile`, `jnt_query_free`, `jnt_query_pattern_count`, `jnt_query_capture_count`, `jnt_query_capture_name`, `jnt_query_exec`, `jnt_query_result_free`, `jnt_query_result_count`, `jnt_query_result_pattern`, `jnt_query_result_capture_count`, `jnt_query_result_capture_id`, `jnt_query_result_capture_node`; eager results own arrays and borrow their exact tree/query owners. |
| Documents | `jnt_weave_new`, `jnt_weave_free`, `jnt_weave_warp`, `jnt_weave_amend`, `jnt_weave_tree`, `jnt_weave_len`, `jnt_weave_policy`, `jnt_weave_cost`; the lent tree handle stays stable across edits, node indices are invalidated, freeing that lent handle is a no-op, invalid spans leave text intact. |

Preserve statuses `OK/INVALID/IO/FORMAT/LANGUAGE/GRAMMAR/NOMEM`, stop codes,
`JNT_NONE`, and the exact `jnt_scar`/`jnt_cost` layouts. Distinguish a negative
operation status from an accepted or refused parse. Pointer-and-length strings
are borrowed views; only version, last error, and s-expressions promise NUL
termination. Free results before queries/trees, trees/documents before parsers,
and parsers before banks. A boundary design must explicitly address allocation
failure and panic containment before claiming the existing failure contract.

The current [dispatcher](src/surface/face/joints/main.zig) is the CLI authority
where its README is stale: cover `grammar`, `lex`, `survey`, `state`, `parse`,
`amend`, `mint`, and `query`, plus version/help. Preserve `state`'s census,
holding, and chain forms, artifact/codex language selection, multi-file parse
behavior, diagnostics, exit codes, and existing machine-readable output.

| Area and later phase | Required behavior | Existing executable evidence and condition for implementation |
|---|---|---|
| Grammar breadth and GLR in phase 3 | Declared alternatives, dynamic rank, full lowering and authored scope, per-reading lexical context | Import, docket, wall and gather tests; full pinned working set. Implement after phase 2 passes. |
| Recovery in phase 3 | `none/keep/fell/relent`, unique anonymous literal supply, bounded progress, exact deletion/supply scars, no hidden successful repair | Default golden arms, [broken inputs](research/joinery/broken/README.md), binding strict-refusal cases. Supply never counts as source text. |
| Stateful scanners in phase 3 | Scanner books, typed bounded memory, ordered phases, abstain/refuse, exact snapshots, bounded zero-width progress | [Scanner claim](research/customary/CLAIM.md), scanner specimens and scanner tests. Unsupported cohorts refuse explicitly. |
| Incrementality in phase 4 | Conservative reuse checked against entry state, exact lexical offer and scanner state; safe cold fallback | [Edit fuzz with negative control](src/kernel/weave/amend_test.zig), keystroke probes; compare after every edit. |
| Queries in phase 5 | Supported `.scm` syntax, names/supertypes/aliases/fields, quantifiers/anchors, predicates, foreign policy, capture multiplicity/order | [Query contract](src/kernel/gloss/README.md), rubric/scribe/alias tests and `tool/glance.py`. Match order is observable. |
| Artifacts in phase 5 | Explicit schema/version, checked layout/content, deterministic bytes, round trips and seals; codex language selection | [Folio rejection/roundtrip tests](src/folio/folio_test.zig), `research/press/wobble.py`. Select a versioned Rust encoding after the lexer trial. |
| CLI and C ABI in phase 5 | Eight CLI verbs and all ABI 2 signatures, statuses, diagnostics, lifetime/edit invalidation and byte strings | [Normative header](include/jnt.h), [CLI contract](src/surface/face/joints/README.md), native binding suites. No ABI function is silently omitted. |
| Python and Rust consumers in phase 5 | Strict/diagnostic parsing, navigation, source retention, ownership, queries, worker reuse, Regulator facets | [Python tests](bindings/python/tests/), [Rust tests](bindings/rust/tests/), local-source Regulator candidate arm; the published-release gate stays intact. |
| Succinct storage and research instruments in phase 6 | Equivalent tree navigation and honest cost reports where the consumer requires them | Vellum tests and benchmark rungs. Reintroduce specialized storage only for a demonstrated space/cost need. |
| Release and cutover in phase 6 | Comparable work, case counts and actual binary hashes; target Linux/macOS; agreed performance and memory budgets | Existing release checks and consumer comparisons, followed by sealed holdout aggregates. Preserve rollback before retiring Zig. |

The first milestone bounds the initial API; the remaining migration phases
follow in order. Features awaiting their phase are unsupported, not implicitly
implemented by the Rust standard library or a dependency. Every later gate
requires positive executed-case evidence, including known refusals, rather
than an exit status from a harness that can skip work.

## Published tables and worker scratch, 2026-10-21

`compiler/table.rs` owns immutable terminal keys, action offsets/actions,
transition symbol/state columns and a state-row directory. Compiler graph
construction retains its mutable maps; accepted rows are consumed only at
publication. Runtime accessors preserve ordered exact-size iterators and
borrowed action/admission slices. Direct artifact decoding retains count,
aggregate-budget, key-order, action-order and later semantic validation order;
serialization retains the Image1 V3/S4 bytes. Source publication explicitly
charges its additional traversal before allocating columns and records it in
construction diagnostics, without raising limits.

The session's lexical scratch owns only reusable ordinal buffers, bounded by
the immutable grammar's tier pattern counts. It carries no token answers.
Permission proofs may be shared between identical complete state stacks within
one parse through a direct-mapped 256-slot pool. Every lookup confirms full
key equality; the pool accounts for retained vector capacities, Arc storage and
its directory within 1 MiB, declines oversized entries and resets per run.
Lookup, initialization and ownership work is charged before publication.
Checkpoints continue to omit these derived handles. A work limit may therefore
refuse at a different operation than a predecessor; work is neither hidden nor
refunded and lexical/native resource failures remain observable.

The deterministic executor visits its initial head before allocating any
alternative FIFO, preserving branch order and head-limit decisions. Reusing
frontier buffers and leaving singleton frontiers in place preserve comparison
order. Each of these implementation changes requires new behavioral and cost
evidence; immutable predecessor reports cannot qualify the edited workspace.

The candidate also drains reduction frames without an intermediate allocation
and reuses empty bounded shift-frontier storage. Native bank members replace
their checked pending payload with an owned compiled grammar only after a
successful decode; failures retain the original proof for retry and concurrent
getters share one published grammar. This releases redundant raw artifact bytes.
The CLI directly decodes borrowed standalone artifacts when no explicit language
is requested, avoiding a second full payload copy while retaining the directory
path for explicit name selection. Tree, corruption, retry, lifetime, concurrency
and named-selection checks cover these paths.

The 2026-10-21 source now passes fresh workspace qualification on Rust 1.85
and 1.96 (381 passed, 16 declared ignored), the full working/artifact/ABI/CLI
gates, the original governed consumer assertions on 6,216 Go and 102,906 Python
inputs, and 40 extracted Mac package commands. The exact local evidence join
is `execution-2026-10-21/final-candidate-evidence.json` under the retained
phase-6 records. Source export 2 and its package remain immutable.

The corresponding 1,546-command cost matrix is complete and stable, while
the selected 1.10 latency/RSS ceiling remains failed. Cold CLI median ratios
range from 1.292 for small JSON to 4.655 for large JSON; compile/load, edits
and independent-worker costs also require investigation. A qualitative
three-second parse/drop sample points to head movement, lexer work, admission
proofs and allocation churn, without predicting savings or explaining every
cost. The [fresh measurements](rust/PERFORMANCE.md#fresh-public-candidate-full-cost-matrix)
retain the actual candidate/baseline identities and scope limits. Target-floor
execution, sealed qualification, adoption and release/rollback remain separate
from this local compatibility result.

The subsequent late sealed attempt retained stable, pin-verified aggregate
projections but measured 0 of 20 entries for both Rust and Zig. It establishes
no comparative engine result; the sealed gate remains incomplete. No agent
inspected raw diagnosis or sealed source. The immutable current records retain
the attempt and its correctness-only overlap with the capped Linux build.

The same source2 closure also has positive emulated Linux release results:
381 passed/16 ignored on both Rust versions, the same extracted Rust 1.85
roster and all 40 installed commands. A separate byte-only audit completes
custody verification after a private producer Path-type error, retaining the
original failed outcome. The [delivery record](rust/DELIVERY.md#fresh-public-workspace-native108-candidate)
separates actual functional execution from that audit and from unexecuted
physical-host, Linux debug, target-cost and default gates.
