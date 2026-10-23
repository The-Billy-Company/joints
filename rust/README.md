# Native Rust engine

This workspace implements the core parser and guarded-effect milestone from
[the migration plan](../RUST_REBUILD_PLAN.md). It is independent of the existing
Rust C binding. Grammar compilation, parsing, trees, and guarded effects execute
in Rust. Regex services reuse the sibling `irgx` safe Rust binding and its
native library; production parsing does not use tree-sitter.

The 2026-10-22 development follow-on adds safe tree-navigation and allocation
optimizations plus a repeatable 15-workload public API benchmark. It does not
achieve the requested 5–10× gain across every function or qualify a default
switch. See the [profiling follow-on](PERFORMANCE.md#safe-public-api-profiling-follow-on-2026-10-22).
The retained package results below identify their earlier immutable sources.

The fixed runtime `c54221b`, with native source `bf19d6b`, now passes fresh Q2
workspace qualification on Rust 1.85 and 1.96, the same 457-test roster under
Rust ASan, and the complete working replay, including all 6,216 Go and 102,906
Python consumer inputs. Actual-host source CI also passes for tooling commit
`4cecfd8`, whose compiled runtime maps remain `c54221b`/`bf19d6b`. Its separate
diagnostic reaches 5× in only 6/120 groups; the earlier `c54221b` source-CI run
reached 7/120. The fresh Mac package passes all 40 installed checks. Linux
packaging, profiles, Rust/Zig costs, installed platform floors and sealed
qualification remain open. See the [fixed candidate
checkpoint](PERFORMANCE.md#fixed-cutover-candidate-2026-10-22) for exact receipts.

The workspace now includes the Image1 implementation: cold and incremental
parsing, scanner programs, guarded effects, queries, all eight CLI verbs, the
ABI 2 adapter, and checked native lexer images in V3/S4 artifacts. Regex image
support requires the sibling IRGX native108 source and Rust binding additions.

The earlier immutable Image1 candidate passed its local Rust, working-corpus,
ABI and governed consumer gates. Its cold Go/Python costs still exceeded the
agreed 1.10 Rust/Zig latency and memory ceiling. The current workspace adds
flat immutable parser tables, bounded full-stack permission-proof reuse,
worker-owned lexical buffers, and deterministic parser allocation reductions.
The retained 2026-10-21 candidate's workspace qualification passes 381 default
tests with 16 declared ignores
on each of Rust 1.85 and 1.96, formatting, all-target checks, Clippy with warnings
denied, and a release build. The exact report is
`.local/rust-migration/native-phase6/execution-2026-10-21/qualification-3/report.json`.
Fresh local qualification also passes all 31 canonical grammars, 14 working
witnesses, 55 classified CLI cases, 24 ABI commands, 64 default consumer tests,
6,216 Go inputs and 102,906 Python inputs. The extracted Mac package passes
40 installed commands. The exact compatibility join is
`.local/rust-migration/native-phase6/execution-2026-10-21/final-candidate-evidence.json`.
It identifies the immutable source export and installed candidate; historical
candidate passes do not qualify edited sources.

The retained Q7 performance follow-on changes parser ownership, permission reuse,
prefix validation, native image decoding, and bounded table storage. Its
combined Q7 snapshot passes 443 default tests on both Rust versions, formatting,
all-target checks, strict Clippy and a release build with a complete 564-file
source/runtime-fixture closure. It includes the adaptive effect memo and
reclaims unpublished runs after failed edits without invalidating old IDs or
versions. The selected source also passes 443 AddressSanitizer
tests, with instrumentation checked in 33 binaries, and focused native
ReleaseSafe controls. The prebuilt standard library and native Zig/C remain
outside Rust ASan, and leak detection is disabled. In the complete packaged
measurement, all four cold-latency medians still exceed the ceiling; large JSON, Go and
Python also exceed the median RSS ceiling. Later source edits require fresh
combined correctness, cost and safety checks.
A reconstruction found missing runtime fixture
capture in Q4; the repaired full input closure passes Q6 workspace qualification.
The same Q7 source passes the complete working replay, including all 31 grammars,
14 extended witnesses, 55 functional checks, 24 ABI checks, and all 6,216 Go and
102,906 Python consumer inputs. Fresh installed checks pass all 40 commands on
the current Mac and all 40 under Linux amd64 emulation. Both Linux compiler
versions also pass the complete 443/16 release test roster. See the
[current measurements](PERFORMANCE.md#current-packaged-q7-result-2026-10-22)
and [memory and ownership
contracts](SAFETY.md) for the exercised safety boundaries and their limits.

The fresh Q7 1,546-command benchmark completed with stable inputs, but the 1.10
latency/RSS ceiling still fails. Cold CLI median Rust/Zig ratios are 1.208 for
JSON, 2.436 for large JSON, 2.134 for Go and 2.312 for Python; median RSS ratios
are 1.080, 1.522, 1.642 and 1.531 respectively. Incremental and worker costs
also remain open. This is a contended current-host comparison, with a separate
source-attestation limit for that historical diagnostic Zig ABI library. The Q7
Mac compatibility join is
`.local/rust-migration/performance-2026-10-21/final-candidate-evidence-6.json`;
Linux evidence is separately recorded under `linux-preflight/run-6/`.

The retained late sealed attempt produced stable but incomplete aggregates:
0 of 20 entries measured on each backend. This establishes no comparative
correctness result. Raw diagnosis remains sealed; the gate remains open.

The retained 2026-10-21 source export also passes both full release-profile suites and all
40 extracted installed checks under Linux amd64 emulation. A distinct read-only
audit completes custody verification after a private producer path-type error;
the original failed run is retained. This establishes emulated release delivery,
with physical-host execution still separate. See [the delivery record](DELIVERY.md#fresh-public-workspace-native108-candidate).

Consumer and release defaults remain on Zig until correctness, performance,
installed delivery, physical platform floors, sealed aggregates, and rollback
qualification pass. The 10,000-line size goal is still open. See the
[performance review](PERFORMANCE.md) and [cutover requirements](CUTOVER.md).

## Build and verify

From the repository root:

```sh
mise exec zig@0.16.0 python@3.12.15 -- python3 tool/rust.py test --irgx-abi-family=irgx-abi2-108-munch-image1 --locked --workspace
mise exec zig@0.16.0 python@3.12.15 -- python3 tool/rust.py clippy --irgx-abi-family=irgx-abi2-108-munch-image1 --locked --workspace --all-targets --all-features -- -D warnings
mise exec python@3.12.15 -- python3 tool/rust.py fmt -p joints-engine -p joints-ffi --check
mise exec zig@0.16.0 python@3.12.15 -- python3 tool/rust.py build --irgx-abi-family=irgx-abi2-108-munch-image1 --locked --release --workspace
rust/target/release/joints-rs parse test/grammar/json.json research/joinery/corpus/ledger.json --all --json --mend=none --no-supply
```

The workspace shares a deny-by-default compiler and Clippy policy across the
engine, CLI, ABI adapter, tests, and build scripts. It checks future compatibility,
explicit lifetimes, internal visibility, FFI type correctness, numeric conversions,
pointer conversions, shared ownership, and unsafe-block safety explanations.
The engine and CLI forbid unsafe code; the ABI crate contains the foreign-memory
operations. The standalone crate in `bindings/rust` carries its own matching
policy so the checks also apply after packaging. Keep checks compatible with
both Rust 1.85 and the qualification toolchain.

Run Clippy with `--all-targets --all-features` to include the optional lexer
instrumentation and every test. A few intentional exceptions are scoped to the
specific item and explain the reason, including rounded CLI display percentages.
The working Image1 corpus trial stays explicitly ignored because it requires
the pinned private `.local` grammar profiles and a fresh absolute
`JOINTS_IMAGE_WORKING_OUTPUT` directory. Once those inputs exist, select
`actual_working_precedence_zero_images_preserve_parser_questions` with
`--features munch-image -- --ignored --exact`, using its full module path
`lexer::working_image_trial::actual_working_precedence_zero_images_preserve_parser_questions`.
Strict Python checks cover the public bindings and the native archive proof
tools; see [the tooling instructions](../tool/README.md#static-typing-for-the-rust-archive-proof).

The validation host's selected macOS 27 SDK cannot link with its installed
linker. Local checks used the installed macOS 26.5 SDK by prefixing Cargo
commands with `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`.
No machine-specific SDK path is embedded in the package configuration.

For a fresh recorded host qualification after that native context exists:

```sh
mise exec python@3.12.15 -- python3 -B tool/rust_qualify.py \
  --native-context .local/rust-native/last-cargo-munch-image1.json \
  --output .local/rust-migration/current/qualification-1 \
  --sdkroot /absolute/path/to/selected/sdk
```

Use a new output directory for every attempt. The recorder runs formatting,
all-target/all-feature checks and Clippy on Rust 1.96/1.85, default tests on both,
and a release build. It retains named results, logs and source/native/dependency
hashes. Both selected toolchains need Clippy; the primary also needs rustfmt.
Ignored
working-corpus witnesses, actual consumers and installed-package checks remain
separate explicit gates. `tool/rust_bundle.py` can form a delivery bundle only
from a positive unchanged report; it preserves the raw static archive and
normalizes a copy. See [delivery](DELIVERY.md) for export, native108 packaging
and installed verification.

The CLI defaults to felling recovery with unique literal supply, matching the
reference. `--mend=none --no-supply` selects the original comparison mode;
native sessions default to no recovery. It returns 0 for acceptance, 1 for a parse stop,
and 2 for operational failures. The JSON response retains the established tree,
confidence, and structural-survey fields. `--help` describes grammar inspection,
lexing, states, exploratory surveys, parsing, edits, queries, and artifact minting.
The Zig CLI remains the default until the migration gates pass.

Installed Rust consumers linking the C static library need the archive produced
by the [delivery procedure](DELIVERY.md). Validate it with both Rust 1.85
and 1.96, with and without LTO. A raw Cargo static library is an intermediate
build artifact. Archive member normalization is one preparation step:

```sh
mise exec zig@0.16.0 python@3.12.15 -- python3 tool/rust_archive.py \
  rust/target/release/libjnt.a --receipt .local/rust-native/jnt-archive.json
```

Rust's LTO treats bundled members named `*.rcgu.o` as Rust bitcode. The
normalizer changes only archive member names and regenerates the symbol index;
it checks every object byte and its order before atomic publication. Its receipt
records the input/output hashes and the selected archiver. Distribution also
requires the separately checked C static boundary, which isolates private
runtime symbols and retains the original build bytes in the package proof.
Historical F schema-2 packages passed all 40 installed checks on the recorded
Mac and emulated Linux hosts. Current native108 packages require fresh checks;
physical target-floor execution remains separate.
The shared library needs no archive normalization. Native Rust callers should
depend on `joints-engine`.

The source dependency on `../../irregex/bindings/rust` is deliberate while its
additive byte and metering APIs are developed. Builds must retain that sibling
checkout until these APIs have a published version. The helper builds the raw
library under `.local/rust-native/source-irgx-munch-image1`, preserving historical
archives. It selects a checked archive under
`.local/rust-native/native-boundary-munch-image1/`: all 108 public IRGX
functions remain public, and private symbols are namespaced
so Rust applications can also link PCRE2. The original archive stays intact.

The helper holds a lock through Cargo and checks sources, raw and selected
archives, proof files, and tool identities before and afterward. The record at
`.local/rust-native/last-cargo-munch-image1.json` separates the raw `native` build
from the actual `native_link` and `IRGX_LIB_DIR`.
Cache reuse recomputes the byte proof. Exact Rust and native input files remain
under `.local/rust-native/sources`, including uncommitted edits.

LLVM objcopy must be on PATH or available in the selected compiler's LLVM tools;
`--objcopy /absolute/path/to/llvm-objcopy` selects it explicitly. On Mac, Apple
libtool comes from `xcrun` or `--indexer`. Missing tools or failed proofs refuse
the build. Formatting needs neither native tools nor a native build. Direct
Cargo calls must select the checked archive recorded by `native_link`, or the
verified archive from a [candidate package](DELIVERY.md). A raw source-built
archive can collide with another PCRE2 library; the dependency's older bundled
archive also lacks the additive APIs.
The dependency enables its explicit `source-engine` and `munch-image` features; ordinary irgx
consumers keep the original bundled-library API and install path.
The helper builds for the host; cross compilation needs an explicit target
archive. The Rust engine itself forbids unsafe code; `rust/ffi` isolates the C
boundary and the dependency owns its native regex boundary. The phase-6
`sheng` trial is complete: its safe advisory path saves no exact calls and the
tested work gates decline the inputs. It remains disabled; see the
[performance review](PERFORMANCE.md).

## Native interface

```rust,no_run
use joints_engine::CompiledGrammar;

let grammar = CompiledGrammar::compile(&std::fs::read("grammar.json")?)?;
let mut session = grammar.session();
let tree = session.parse(b"{\"answer\":42}")?;
assert!(tree.confidence().is_strict());
drop(session);
assert_eq!(tree.root().unwrap().name(), "document");
# Ok::<(), Box<dyn std::error::Error>>(())
```

`parse` is strict; a refusal error retains the diagnostic snapshot through
`partial_tree`. `parse_partial` returns a completed forest and its stop evidence.
Snapshots own their source and compiled grammar. Borrowed nodes cannot outlive
their snapshot. Share the compiled grammar between workers and create one
mutable session per worker.

`CompiledGrammar::compile_with_options` accepts `CompileOptions` for table
construction, ordinary lexer transitions, and scanner-probe resources. The
immutable grammar retains those budgets for every worker; each session also
has its own `ParseLimits`. Probe limits are finite steps, interpreter depth,
and whole-KiB heap bytes. Zero is an explicit budget. Invalid native numeric
values are refused before scanner construction. Exhaustion is an operational
error and never a token miss.

`grammar.effect_store()` creates a private interning space. `session.product`
folds the latest completed parse's actual moves, checks grammar identity, and
rejects missing or operationally interrupted traces. Grounding an effect does
not establish parse acceptance. The store rejects handles from another store.

`Document::new(grammar, source)` opens an editable diagnostic snapshot.
`document.edit(ByteSpan::new(start, end).unwrap(), replacement)` publishes a
completed version or preserves the old version on operational failure. Clone
`document.snapshot()`'s Arc to retain a previous version. Inputs and offsets are
bytes. `document.cost()` separates validated prefix reuse, source copying,
materialized nodes, and measured-sequence work; `document.product()` returns
values comparable with a separate cold effect store. A partial or ambiguous
run conservatively falls back to cold parsing. Proof-cache metadata is capped
at 32 MiB; the additional permission pool retains at most 1,024 slates within
a 1 MiB payload-and-directory bound across this grammar-bound session. Each proof records
all state-stack dependencies across its explored branches. Reuse checks the
complete recorded suffix, or the full stack when the proof reached its floor.
Lexical ordinal scratch is worker-owned and bounded by the grammar. Permission
proofs and ordinal scratch retain no scanner answers. The prefix cache retains
lossless observations for exact replay comparison; pure regex events may instead
use a conservative bound covering every source read. That shortcut requires the
complete prefix through the edit to remain byte-equal and the bound to precede
the edit. Program scanners retain exact replay. An unknown pure-regex bound
stops validation before that event and selects an earlier checkpoint. The 32 MiB
count excludes source, snapshots, move traces, the effect store, allocator
overhead, and transient allocations during buffer growth.
The effect store retains every distinct interned run until the document or
store is dropped, including runs created during unsuccessful edit attempts.
Operation limits do not bound that cumulative storage over a document's lifetime.

`DocumentOptions.policy` selects the exact proof used by `Prove` and `Snap`.
`Whole` retains a proved prefix and re-derives the suffix, matching the C policy;
`Cold` and the CLI's `--cold` reparse from the beginning. Costs report source copies, actual
token reads, output materialization, and sequence work separately. The changed
sequence window starts at a leaf index, rather than a byte offset.

`Query::compile(grammar, source)` owns its source and grammar. Execute it against
a snapshot with an explicit `ForeignPolicy`; captures borrow that snapshot.
Compilation and execution have finite, independently configurable limits. A
refusal publishes no partial match array.

`grammar.artifact()` stores checked compiled tables. `Bank::open(path)` accepts
grammar JSON, a native artifact, or a sorted multi-language bank. Loading native
tables restores checked lexer machines and scanner bindings without reconstructing
LR states. The current candidate uses envelope version 3 and table schema 4,
including checked native lexer images and typed local-alias recipes retained
through inlining. Earlier native drafts
and legacy Zig folios/codices require re-minting from the original grammar JSON;
obsolete formats are refused explicitly. Bank members release checked raw
payloads after successful owned decoding; failed loads retain their proof for
retry, and concurrent getters share one grammar. Standalone CLI loads without
explicit language selection decode borrowed bytes directly. Keep each runtime
paired with its own compatible artifacts for rollback.

```sh
rust/target/release/joints-rs mint grammar.json -o grammar.jnt
rust/target/release/joints-rs parse grammar.jnt source.txt --quiet
rust/target/release/joints-rs query grammar.jnt captures.scm source.txt --json
```

The C adapter implements all 62 declarations in `include/jnt.h`, using checked,
non-recycled handle tokens, per-parser scratch locks, and thread-local errors.
Children must be freed before their owners. A weave lends a stable tree handle;
node indices and borrowed byte views are invalidated by its next successful edit.
Outstanding query results must be freed before changing that weave. Boundary
panics are contained, and checked limits or explicit allocation refusals are
reported. Ordinary Rust allocator exhaustion can abort the process; recoverable
process-wide out-of-memory behavior is not promised.

## First milestone evidence

The local gate passed 48 Rust tests, including all 13 first-milestone frozen
reference cases, independent worker/session comparisons, tree lifetime and byte
position checks, construction budgets, and more than 100,000 algebra association
cases. The separate release binary also replayed all 13 selected CLI cases.
The full 25-case fixture bundle retains default repair cases for phase 3.

Phase 3 additionally records all 66 working scanner specimens in
[`test/migration/specimens`](../test/migration/specimens/manifest.json), with
source, grammar, book, assertion, and output hashes. Five desired specimen
claims already fail against the frozen Zig reference; the desired assertions
remain intact. The explicit native specimen gate distinguishes those existing
failures from regressions and compares published trees on supported cases.

The phase 3 candidate `acfa7e2fc5f5c349` passes 150 default tests and Clippy;
all 31 pinned grammars construct under the public limits. All 66 specimens
execute: 60 frozen trees match exactly and six match pinned independent
corrections (five Julia delimiters and Swift's nearer field). All stop and
repair records agree. Of 377 desired assertions, 360 hold and 17 unchanged
aspirational failures remain visible. All 19 larger sources execute without
operational refusal; known partial support and classified differences are
recorded in the design. These results close the local cold-parser gate without
establishing complete language conformance or the later consumer gates.

To compare a candidate executable without silently skipping deferred cases:

```sh
python3 tool/migration.py verify --bundle test/migration/reference
python3 tool/migration.py replay --bundle test/migration/reference --suite core-parser --binary rust/target/release/joints-rs
```

This requires the repository's Python toolchain. Full reference reconstruction
also requires Zig 0.16 and the pinned grammar fetches; see the design's phase 0
instructions. The local full 36-case reference is kept under
`.local/rust-migration/reference-verified`.

The first slice is about 2,900 production code lines, excluding unit-test modules,
blank lines, and comment-only lines. This is a partial product. It supports the
smaller implementation approach without establishing a final full-product line
count.

The phase 4 candidate `cf4ccaa2c87ee10a` has about 12,657 production
Rust lines under the same counting convention, including the CLI and excluding
test modules and dependencies. At that point the remaining product interfaces
were still pending.

The qualified phase 5 implementation has about 22,811 production Rust lines
across 39 files, including all eight CLI verbs and the C adapter. Candidate
`e73eb9ee016afd74` passes 336
default Rust tests, 14 explicit working-corpus witnesses, Clippy, formatting, and 66
helper tests. Release C export/layout/client checks and both binding suites
pass. All 64 default Regulator tests and the broader ambiguity replay pass.
The full consumer comparison passes all 6,216 Go sources and all 102,906 Python
sources with fresh artifacts. Scoped projection corrections, contextual empty
tokens, and removal of repeated parser work preserve the original assertions,
corpus, and runtime limits. The predecessor's failures remain retained.
Independent fresh mints produce identical artifacts for all 12 reviewed profiles.
The 12-gate qualification report and exact provenance are retained at
`.local/rust-migration/native-phase5/qualification-E/report.json`, with the
622-file input closure archived before phase 6 edits. The 10,000-line
goal is not met. The final simplification phase must assess the complete
product without shortening formatting or dropping behavior to satisfy a count.

The combined phase 6 candidate F, CLI `35f20e5cece02ef1`, passes a fresh
12-gate compatibility qualification with 347 default Rust tests, 14 explicit
witnesses, 93 helper tests, actual Rust 1.85 checks, and the C/binding contracts.
It also passes all 64 default consumer tests, 6,216 Go sources, and 102,906
Python sources under the original assertions and unchanged limits. Two fresh
mints retain the same artifact bytes for all 12 reviewed profiles. The final
110,014-file source rehash is exact. Its report is
`.local/rust-migration/native-phase6/qualification-F/report.json`, with the
628-file input closure retained separately before nonruntime tooling edits.
F totals about 22,868 production Rust lines across 39 files; the 10,000-line
goal remains unmet. The fresh measured cost matrix completes all 1,546 commands,
with substantial regressions under user-authorized background activity and
battery power. The source exporter and native boundary helpers separately pass
149 tests. Schema-2 packages pass all 40 installed checks each, including 347
default tests and independent native providers, on macOS 26.6 ARM64 and emulated
Ubuntu 24.04 amd64. Neither establishes the physical target-floor CI gates.
The late sealed worker refused before an accepted aggregate; its diagnosis
remains unread. The selected 10-percent performance/memory ceiling is unmet,
and the sealed gate remains open.
A separate working-corpus check also passes all 31 base grammar artifact
roundtrips: 31 fresh mints and 31 standalone inspections, with exact report
pairs and unchanged artifacts. This adds coverage without attributing a cause
to the unrelated sealed refusal.

A nine-run local measurement compiled the same JSON grammar and parsed/rendered
the same 774-byte ledger in a fresh CLI process with warm filesystem caches.
Median process time was 6.65 ms for Rust and 6.58 ms for Zig; median maximum RSS
was 3.96 MB and 4.49 MB. These are small startup measurements, not general parser
throughput claims. Private binary hashes and samples are recorded in
`.local/rust-migration/native-core/measurement.json`.

The [design](../RUST_DESIGN.md) defines invariants and later product gates.
