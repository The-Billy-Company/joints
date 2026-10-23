# Local Rust candidate delivery

The source exporter and package validator are preparation for phase 6. They
do not publish a release, change the default engine, or establish support on
a host that has not executed the candidate. See [CUTOVER.md](CUTOVER.md) for
activation, artifact re-minting, and rollback.

The fixed cutover runtime is `c54221b`, with native source `bf19d6b`. Its
workspace, actual-host source checks and full working consumers pass. Its
fresh Mac archive passes all 40 extracted installed checks, including the
457-test default suite and native/static coexistence. The private aggregate is
`final-candidate-evidence-1.json` under the isolated qualification worktree's
`.local/rust-migration/performance-2026-10-21/` (SHA-256
`e182268cea6119cbfb5478e20c10d270278b52b923bf99a8ca97099de962a3d6`).
Linux packaging and actual installed platform-floor execution remain open. See
[the fixed candidate](PERFORMANCE.md#fixed-cutover-candidate-2026-10-22).
The Q7 receipts below remain attached to their earlier source.

The retained Q7 source completes fresh native108 V3/S4 delivery on 2026-10-22.
All 40 extracted installed checks pass on the current Mac and under Linux
amd64 emulation. Both Rust 1.85 and 1.96 pass 443 default tests with 16 ignores
in the Linux release replay. The same 564-file compiled-source/runtime-fixture
closure joins the current workspace and complete working-consumer results.
The Mac compatibility receipt is
`.local/rust-migration/performance-2026-10-21/final-candidate-evidence-6.json`;
the separate Linux receipt is `linux-preflight/run-6/execution.json` under
that directory. Both executions finish naturally with stable inputs; the Linux
client, parent and exact container are confirmed gone.

The preceding delivery attempt is preserved as a failure: export requested an
optional unrelated image that was no longer present. The orchestration now
includes that exclusion only when the file exists. Interruption, timeout and
post-spawn callback cleanup also use the reviewed owned-process guard, with
exact-ID container cleanup for Linux. All 21 prior preparation controls plus
six new cleanup controls pass. This does not relax source-export, native ABI,
installed-consumer or artifact-refusal checks. No engine source changed during
this packaging repair.

The complete packaged benchmark still fails the 1.10 latency/RSS ceiling;
see [the current measurements](PERFORMANCE.md#current-packaged-q7-result-2026-10-22).
These remain private local packages. Physical target floors, adoption,
sealed qualification and release/rollback remain separate.

The local candidate deliberately preserves the current version authorities:

| Component | Recorded version |
| --- | --- |
| Native Rust engine and `joints-rs` CLI | `0.0.0` |
| C ABI | `2` |
| C package version and portable Python/Rust bindings | `0.1.0` |

Every manifest says `publishable: false`. These labels are not permission to
upload an existing `0.1.0` release again. The current release workflow continues
to build the Zig engine; it cannot be reused unchanged to deliver this candidate.

The current workspace uses native108 (`irgx-abi2-108-munch-image1`) and native
artifact envelope version 3/table schema 4. Select that family explicitly when
packaging. The helper's default native105 mode remains for retained older
V2/S3 candidates; it cannot package the current source as native105.

## Standalone source closure

The separate [Rust source workflow](../.github/workflows/rust-engine.yml) runs
on pull requests and manual dispatches. It builds native108 from the exact IRGX
commit pinned in the workflow, then checks formatting, all targets/features,
Clippy, and the unfiltered release-profile default test roster on Rust 1.85 and
1.96. Each job verifies its actual Ubuntu 24.04 x86-64 or macOS 14 ARM64 host;
the Mac job selects Xcode 15.4 and SDK 14.5 explicitly. Host, source, tool,
checked native-boundary, command, and named test records are retained.

The workflow fetches and verifies public `grammars.toml` pins because several
default tests embed gitignored grammar files. All other fixture inputs must
be committed. It uses no private consumer checkout or sealed holdout and
preserves declared ignored tests. The pinned IRGX commit must first be
reachable on its remote. Source CI supplies correctness evidence; installed
packages, complete working consumers, performance and cutover still require
their own checks.

macOS builds the pinned official Python 3.12.15 source because that security
release has no `setup-python` binary for the macOS 14 ARM64 image. The source
and installed workflows share `tool/rust_python_bootstrap.py`, retaining the
source, helper and workflow hashes, eight build commands, logs and resulting
interpreter identity. The installed workflow pins the helper before executing
it and checks the receipt with that exact interpreter.
After correctness checks, the workflow separately compares the unchanged
15-workload benchmark with starting Rust commit `9881c96` on four cases.
It retains raw samples and p95 results without treating those diagnostics as
the complete Rust/Zig cost protocol or a cutover verdict.

Run with Python 3.12 or newer, Cargo, and the exact qualified source checkouts:

```sh
mise exec zig@0.16.0 python@3.12.15 -- python tool/rust_delivery.py export \
  --irregex ../irregex \
  --compiled-proof QUALIFIED_BUNDLE/build.json \
  --zig-cache "$HOME/.cache/zig" \
  --output .local/delivery/source
```

This command copies sources and vendors dependencies; it does not build the
engine. It requires a new output directory and never edits either checkout.
It records both Git identities, dirty state, and the exact source bytes. The
qualified compiled-input join is checked independently from the current docs
and delivery tooling. Exporting updated docs does not retag a historical
whole-checkout qualification freeze.

The directory retains this relative layout:

```text
source/
  source-manifest.json
  .cargo/config.toml
  joints/rust/
  joints/bindings/{python,rust}/
  joints/customary/
  joints/test/ and working upstream inputs
  irregex/                       # native sources and safe Rust binding
  dependencies/cargo/           # cargo vendor --locked, including sync manifests
  dependencies/python/          # pinned build/backend wheels
  dependencies/zig-cache/p/     # exact Brigade package used by build.zig.zon
```

The engine's dependency on `../../irregex/bindings/rust` remains unchanged.
The additive `source-engine` APIs are included as source along with their
matching native implementation and licenses. An older crates.io `irgx 2.6.0`
or its bundled native archive cannot substitute for those bytes. Old irgx Rust
vendor archives are omitted. PCRE2 and libsais source floors remain included.

Cargo vendoring covers the engine workspace and the safe irgx and portable
Rust binding manifests. Missing lockfiles are generated only in the staging
copy and are included in its file manifest. Export creates a relative Cargo
source replacement and offline configuration. Python build/backend wheels are
downloaded separately and hashed in the closure. To prepare without network
access, supply an already populated wheelhouse and cached Cargo sources:

```sh
python3 tool/rust_delivery.py export --offline --wheelhouse PREPARED_WHEELS \
  --irregex ../irregex --compiled-proof QUALIFIED_BUNDLE/build.json \
  --zig-cache PREPARED_ZIG_CACHE --output NEW_SOURCE_DIRECTORY
```

The exporter refuses missing dependencies. A failed export does not publish
its output directory. Its exact successful dependency commands and logs are
retained. They include actual staging paths, so two independent exports are
not claimed to have byte-identical provenance. Packaging the same completed
source tree and native bundle uses ordered members, fixed archive timestamps,
and fixed gzip metadata.

## Target-specific native build

Build only in a scheduled validation window. Preserve the export as read-only
input, and keep Cargo/Zig output and writable caches outside it. Zig 0.16 also
expands packages into project-local `zig-pkg/`; build the native code in an
exact private copy and recheck its original source hashes afterward. Copy the
exported Zig package seed into a new writable global cache before building.
Record input hashes before and after, tool versions and executable hashes,
the exact commands, target, CPU floor, SDK, and produced archive hashes.

For Ubuntu 24.04 x86-64, the intended explicit native command is:

```sh
zig build --prefix OUTPUT/irgx -Dtarget=x86_64-linux-gnu.2.39 \
  -Dcpu=baseline -Doptimize=ReleaseFast -Dlib-optimize=ReleaseFast -Dstrip=true -j2
IRGX_LIB_DIR=OUTPUT/irgx/lib CARGO_TARGET_DIR=OUTPUT/cargo \
  cargo build --manifest-path SOURCE/joints/rust/Cargo.toml \
  --locked --offline --release --workspace
```

Run Zig in the private copy of `SOURCE/irregex`. Linux must not inherit `SDKROOT` or a macOS
deployment target. The host-only `tool/rust.py` helper does not establish
cross-archive provenance: select and hash the target archive explicitly.
Both the CLI/shared library and every static archive object must have the
named machine architecture. The original build bundle retains the payload-preserving member normalization
proof from `tool/rust_archive.py`. Packaging then applies the separate opaque
C static boundary described below; the two transformations have different
contracts and receipts.

For the current macOS validation host, explicitly use the working 26.5 SDK:

```sh
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk \
  IRGX_LIB_DIR=TARGET_MATCHING_IRGX/lib CARGO_TARGET_DIR=OUTPUT/cargo \
  cargo build --manifest-path SOURCE/joints/rust/Cargo.toml \
  --locked --offline --release --workspace
```

The native build bundle must contain the CLI, normalized static library,
shared library, `build.json`, and `bundle.json`. `build.json` retains the
existing stable Rust/native/toolchain input proof. `bundle.json` uses the
phase-5 identity format: schema 1, `identity` with `rust_inputs`, `native`,
`toolchain`, and `raw_files`; `identity_sha256` is SHA-256 of sorted indented
JSON plus newline. Its `files` map pins the actual copied artifacts and proof.
This identity is a local build custody record, not an assertion that tests
passed or that a dirty checkout is a publishable release.

For ordinary current-host Cargo work, `tool/rust.py test --workspace` builds
the raw archive under `.local/rust-native/source-irgx`, then selects a verified
IRGX C boundary for `IRGX_LIB_DIR`. The historical raw archive under
`.local/rust-native/irgx` is preserved. The derivative cache binds the raw
archive, source/header, ABI family, producer/parser source, selected tools and
target; a corrupt or partial entry refuses without a raw fallback. One lock
covers production, selection, Cargo and the final source/archive attestation.
`fmt` does not discover native tools or build an archive.

The helper selects explicit `--objcopy` first, then `llvm-objcopy` or
`rust-objcopy` on PATH, then the selected rustc sysroot's llvm-tools. Install
that component or pass a working LLVM executable explicitly; GNU objcopy is
not a fallback. On macOS, `--indexer` selects Apple libtool, otherwise `xcrun`
selects it. The executable bytes and actual version are recorded. A launcher
identity does not establish unobserved backend bytes. `last-cargo.json` keeps
the raw build provenance separate from the actually selected archive and its
proof, including failure attestations after Cargo.

## Candidate archive and installed checks

After a target build has its recorded input/output proof:

```sh
python3 tool/rust_delivery.py pack --source SOURCE \
  --bundle TARGET_BUNDLE --irgx-archive TARGET_MATCHING_IRGX/lib/libirgx.a \
  --irgx-abi-family=irgx-abi2-108-munch-image1 \
  --target macos-arm64 --execution-scope native-host \
  --objcopy EXPLICIT_LLVM_OBJCOPY --indexer EXPLICIT_APPLE_LIBTOOL \
  --output .local/delivery/candidate-macos-arm64.tar.gz
```

Omit `--indexer` for Linux. Use `linux-x86_64` and the appropriate execution
scope for Linux. The archive
retains that declared build/package scope as immutable metadata. A verification
run records its actual execution context independently, so the same emulated
build archive can later be checked on an actual native Ubuntu runner without
repackaging, changing its hash or rewriting earlier receipts. Both mode values
must be valid; target OS and architecture must still match the executing host.
The verification report's `execution_scope` describes that run and its
`package_execution_scope` retains the archive's declaration.

The archive
contains the complete source closure, CLI, C static/shared libraries, irgx
archive, header, JSON grammar, licenses, and source/build identity records.
The candidate envelope uses schema 2; old schema-1 packages require a new
package and are explicitly refused. Source and original build schemas remain
unchanged. The complete original build bundle stays under `proof/build/`. The packaged
static archive is an explicit derivative produced by
`tool/rust_static_boundary.py`, with its receipt in `static-boundary.json`
and command/intermediate evidence under `proof/static-boundary/`. The selected
LLVM objcopy path, version and hash are recorded. On macOS, the packaged
shared-library derivative is given install name
`@rpath/libjnt.dylib` and an ad-hoc signature. Its deployment receipt joins the
original and derived hashes, all `__TEXT` section payloads, exports, dependency
metadata, and actual transformation commands. This local normalization does
not change the immutable qualified build. The canonical `lib/` directory
contains the deployable copy for ordinary consumers.
The native IRGX archive is a separate checked selection: the current source's
108 authoritative header functions remain public, and every other owned global or weak
symbol is namespaced. `native-boundary.json` joins the raw original under
`proof/build/lib/libirgx.a` to the selected `lib/libirgx.a` and the exported
helper/parser/header. The manifest retains distinct raw and selected hashes;
the original build-native identity continues to describe the raw archive.
This isolation permits a native Rust consumer's independent bundled PCRE2 to
coexist with IRGX's private PCRE2. On macOS, an explicit Apple libtool step may
restore the original sorted BSD index after LLVM renaming; unchanged member
names, order, bytes and the complete index proof are still required.
Native108 packages also carry `selection.json` and `proof.json` beside `lib/`
for the checked Rust binding. The portable selection binds the raw and selected
archives, exact boundary proof, source, header, target and producer hashes.
Package verification rechecks the full archive transformation before checking
this declaration; the declaration does not replace the byte proof.
Symlinks, path escapes, duplicate archive members, changed checksums, wrong
targets, and mismatched source/native joins are refused.

The static C boundary namespaces every defined global/weak symbol except the
62 functions declared by the packaged ABI2 header, using a prefix derived from
the original archive hash. All definitions and references to owned symbols
follow that map. Unresolved system imports stay unchanged. Only verified
compiler-only LLVM bitcode/command metadata is removed; its original bytes
remain in `proof/build/`. Every surviving runtime, code, data, EH/unwind section
payload and relative order, symbol attribute, relocation target, COMDAT group,
LLVM address-significance role and archive member selection is checked.
Mach-O relocation pairing and ADDEND payloads are preserved. A sorted BSD TOC
may be stably re-sorted after renaming, preserving every duplicate's member
priority. ELF keeps its full symbol-index entry order. Unsupported formats,
linker-special definitions, indirect aliases and unproved object metadata refuse
packaging. Extraction recomputes this proof before executing a consumer.

This archive is a native C ABI boundary. It intentionally drops embedded Rust
LTO metadata, so a Rust client's LTO does not optimize the engine's private Rust
runtime across that boundary. Native Rust clients use `joints-engine` with the
matching source-engine irgx APIs. No member merge, symbol weakening, runtime
handler replacement or duplicate-definition linker override is performed.

Offline authored controls and explicit current-host C controls are available:

```sh
python3 -m unittest discover -s tool -p 'test_rust_static_boundary.py'
python3 tool/test_rust_static_boundary.py --native macos-arm64 \
  --objcopy EXPLICIT_LLVM_OBJCOPY --output NEW_RETAINED_CONTROL_DIR \
  --sdkroot /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
```

Use `--native linux-x86_64` without `--sdkroot` on the matching Linux host or
explicitly recorded amd64 Ubuntu emulation. The default suite authors its own
ELF/Mach-O/archive bytes; it imports no private prototype fixtures. The explicit
C control uses competing strong/weak runtime functions, cross-member global and
thread-local state and verifies that both owners remain independent.

The package retains Mach-O CPU subtypes, executable/library deployment floors,
static-object maximum deployment floors, and actual linked dependencies. ELF
receipts retain required GLIBC versions, dependencies, and CPU notes; a GLIBC
requirement newer than 2.39 or embedded library search path is refused. These
are binary metadata checks, not execution on a target-floor host. In particular,
an ARM64 header and a successful run on the current Mac do not prove macOS 14.

Verify a new archive in a fresh retained scratch directory:

```sh
python3 tool/rust_delivery.py verify \
  --archive .local/delivery/candidate-macos-arm64.tar.gz \
  --output .local/delivery/install-macos-arm64 \
  --execution-scope native-host --rust-toolchain 1.85.0 \
  --python PYTHON_3_12 \
  --sdkroot /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
```

The verifier executes the extracted CLI for strict, sound parse, exact query
capture content, artifact mint/load, and prior native format/schema refusal.
It compiles and executes C consumers against both static and shared libraries,
including source ownership, parser reuse, and `dladdr` verification of the
actual loaded library. A historical macOS dylib can retain its original absolute
install name, so a client-only rewrite would give a misleading packaging pass.
The verifier rechecks the packaged derivative's text/export/identity proof,
then links and runs an ordinary unmodified dynamic client against it.
It builds the portable Python wheel and sdist offline, installs the
wheel and rebuilt sdist wheel into isolated environments, and runs their
existing parse/query/refusal checks. It packages and extracts the portable
Rust crate and runs its native and compile-fail contracts. It executes static
clients with both Rust 1.85 and 1.96 in default and LTO modes, checks distinct
consumer/engine exception-handler addresses and consumer panic recovery, and
verifies source ownership, parser reuse and query results. Both toolchains must
already be installed; verification does not fetch them. It checks every native
engine target and executes the unfiltered default workspace suite, including
doctests, at the selected primary toolchain (1.85 by default). Actual positive
test totals are recorded; ignored corpus and witness tests are not enabled.
The native Rust API client also runs under both toolchains in default and
release-LTO modes. It checks the additive irgx limited-capture API, independent
forced-static PCRE2 captures/refusals, actual reference-provider configuration
and distinct compile/match addresses. Detailed ownership research remains in
the separate STEP2 evidence. Cargo has a new home, private target, and explicit vendored
sources. Compiler/build overrides and preload hooks are cleared; `IRGX_LIB_DIR`
selects the extracted matching archive. Python uses isolated installed packages.
`PCRE2_SYS_STATIC=1` and `LIBPCRE2_8_NO_PKG_CONFIG=1` prevent a system PCRE2
from substituting for the consumer's bundled reference implementation.
No original checkout path dependency is selected. On macOS this is resolution
isolation, not a filesystem sandbox.

Every attempted command and output hash is recorded. A failed check writes
`pass: false` and retains its scratch evidence; it cannot leave a successful
acceptance receipt. This check is not a benchmark.

## Execution scope still to qualify

On an ARM Mac, Docker Desktop can execute an amd64 Ubuntu 24.04 userland
through emulation. Such a run must use `--execution-scope emulated` and record
the pinned image, ARM Docker daemon, x86-64 ELF identity, LinuxKit kernel,
Ubuntu/glibc versions, and executed commands. It is actual target-code execution,
but is not a physical Ubuntu 24.04 runner or a useful native speed measurement.

Native Ubuntu 24.04 x86-64 and the published macOS host-floor CI gates remain
separate until actually executed. No workflow dispatch, source push, package
upload, or default-engine switch is performed by this tool.

The opt-in [candidate workflow](../.github/workflows/rust-candidate.yml) checks
installed archives on Ubuntu 24.04 x86-64 and macOS 14 ARM64. It requires an exact
helper-present commit and independently supplied archive SHA-256 digests. Select
either HTTPS archive URLs or exact asset IDs in an unpublished draft release
of this repository. The verifier bootstrap is pinned separately from the candidate archive.
No workflow is dispatched by editing this file or by an ordinary push.

Draft mode binds `release_id`, `candidate_commit`, `linux_asset_id` and
`macos_asset_id`, with both target digests. The fixed asset names are
`candidate-linux-x86_64.tar.gz` and `candidate-macos-arm64.tar.gz`.
`candidate_commit` identifies the runtime source independently from
`helper_ref`. The GET-only helper checks release membership, unpublished
status, source commit, metadata and actual downloaded bytes before installed
verification. Signed storage requests receive no GitHub bearer token.

The optional `transport_only` mode downloads just the selected Linux asset on
Ubuntu and skips the installed matrix. The actual read-token probe in
[run 39881082673](https://github.com/The-Billy-Company/joints/actions/runs/39881082673)
was refused with HTTP 403. Draft transfers therefore use an isolated GET-only
job with `contents: write`; that job never extracts or executes candidate
bytes. It uploads immutable same-run artifacts for separate installed jobs
with `contents: read` and `actions: read`, which independently check the archive
SHA-256 and transport receipt. A transport-only pass supplies no installed
qualification. The isolated transfer passes in
[run 39882119855](https://github.com/The-Billy-Company/joints/actions/runs/39882119855)
for a 213-byte transport-only probe; all installed jobs are skipped. This
checks transport only and supplies no installed package or platform-floor
proof. No workflow step publishes or edits a release.

Installed evidence retains generated Rust client sources and lockfiles, C
consumer source, Cargo configuration and old-format refusal inputs alongside
the reports and logs. The explicit hidden configuration path is included;
build caches are excluded from these selected artifact paths.

Keep the workflow's three verifier SHA-256 pins synchronized when changing
`tool/rust_delivery.py`, `tool/rust_archive.py`, or
`tool/rust_static_boundary.py`. Its separate Python bootstrap pin must match
`tool/rust_python_bootstrap.py`; draft transport and receipt identities must match
`tool/rust_candidate_download.py`. Before preparing a helper commit, run the
offline delivery and bootstrap controls with Python 3.12 or newer:

```sh
python3.12 -B -m unittest discover -s tool -p test_rust_delivery.py
python3.12 -B -m unittest discover -s tool -p test_rust_python_bootstrap.py
python3.12 -B -m unittest discover -s tool -p test_rust_candidate_download.py
```

The controls check those exact workflow pins as well as package and input
refusals. A stale bootstrap pin otherwise prevents the installed checks from
starting, even when the candidate archive itself is valid.

Each job checks its actual OS and architecture before execution, retains the
package's original build scope, and records the new verification scope. An
emulated Linux build can therefore be verified later on a native host without
rewriting its earlier receipts. Passing installed contracts is one platform
check; performance, the late sealed aggregate, real consumer adoption and
rollback remain separate cutover gates.

GitHub currently lists `macos-14` as ARM64, with retirement on 2026-11-02 and
scheduled brownouts. Recheck runner availability before dispatch; if unavailable,
provide an actual macOS 14 ARM64 runner. A newer OS cannot establish that floor.
See [GitHub's runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
and [the image retirement notice](https://github.com/actions/runner-images/issues/13518).

## Historical local F validation before native IRGX isolation

The fresh standalone source export contains 6,495 files. Its source-manifest
SHA-256 is `1b6e58d0ddf9b8bf52e3c9586df96400865a21d8cceec40621567138ef6263a0`;
the compiled-input join is exactly the qualified F runtime's 112 inputs and
matching 550 native/binding inputs. The current delivery helper suite passed
115 tests separately from the historical F helper suite's 93 tests.

| Local archive | SHA-256 | Executed context |
| --- | --- | --- |
| `candidate-macos-arm64.tar.gz` | `4bc93ff1fdbbfd92db80c0de5b904bbeb56e8e644c2c4ae9d8d659a2844436bd` | Current ARM64 macOS 26.6 host, SDK 26.5 |
| `candidate-linux-x86_64.tar.gz` | `7780154531dcba3a0c17a9fef31699af4a70f139972906b4d17fe5918f1ca8d5` | Ubuntu 24.04 amd64 userland/glibc 2.39 under ARM-host Docker LinuxKit emulation |

Each archive passed all 36 generic installed commands, including CLI and query
content, artifact refusals, C ownership, offline Python wheel/sdist consumers,
native Rust API execution and Rust 1.85/1.96 default/static-LTO coexistence.
The existing default engine workspace tests were additionally executed at Rust
1.85 on the extracted macOS package: 347 passed, none failed, and 16 remained
explicitly ignored. The corresponding Linux default suite refused during
linking: the raw IRGX archive and the bundled reference dependency both defined
PCRE2 symbols. The historical Mac suite passed, but later call-target inspection
showed reference calls selecting IRGX's PCRE2 rather than proving distinct
providers. These outcomes remain retained. Subsequent isolated-IRGX STEP2
tests passed the unchanged 347-test suite on both hosts and four compiler/profile
coexistence arms with independent providers; they do not retag these packages.

These are nonpublishable local candidates. The source/archive snapshots retain
their original documentation bytes; this later status note does not rewrite
their manifests. Current-host and emulated execution establish neither actual
Ubuntu hardware qualification nor macOS 14 execution, and make no performance,
publication, default-engine-switch or cutover claim.


## Fresh schema-2 installed validation

The second local delivery keeps the same 6,495-file standalone layout and exact
qualified F inputs: 112 compiled inputs and 550 native/binding inputs. Its
source-manifest SHA-256 is
`6eced5d3f40b6dc9b5424d15cd71834ffc153a6b1b47bef05424722e45b0f911`.
The promoted helper suite passed 149 tests; this is separate from historical
F's 93 tests and the first delivery's 115 tests above.

| Schema-2 local archive | SHA-256 | Executed context |
| --- | --- | --- |
| `candidate-macos-arm64.tar.gz` | `42a864375bb6e1897ddef82dc4f59c8bdf2508adcc714807ab3f8ee0d499972b` | Native ARM64 macOS 26.6, SDK 26.5 |
| `candidate-linux-x86_64.tar.gz` | `6a623ef59b24e81b334e31d79086b4e76477305b22eb33b73366a87506a65924` | Ubuntu 24.04 amd64/glibc 2.39 under ARM-host Docker LinuxKit emulation |

Each candidate passed all 40 installed commands. The ordinary verifier executed
the unchanged default workspace at Rust 1.85 once: 347 passed, zero failed,
16 explicitly ignored, and zero filtered, including doctests. Each also passed
four native Rust API/static-PCRE coexistence arms and four C static-boundary
runtime arms: Rust 1.85 and 1.96, default and release-LTO. Both PCRE providers
remain distinct; the reference reports its actual 10.46 configuration, while
IRGX's 10.49 version remains source-attested with public-version corroboration.
The remaining CLI, artifact-refusal, C ownership, offline Python and portable
Rust binding checks also passed.

The package's raw native build proof is unchanged. Schema 2 separately records
the verified selected IRGX derivative (Mac `ebae7691…8747`, Linux `47bfa05f…b380`)
that Cargo actually uses. Sources, archive inputs and outputs, command logs and
helper identities were checked before and after. The qualified F CLI, original
raw archives, historical 628-file closure and first delivery snapshots remain
preserved. The immutable second source snapshot retains its earlier
`DELIVERY.md` bytes; this appended status does not retag that export or either
candidate archive.

These remain nonpublishable local candidates. The Linux run does not establish
physical Ubuntu hardware support, and current-Mac execution does not establish
the macOS 14 floor. This correctness qualification makes no performance,
publishing, workflow-dispatch, default-switch or cutover claim.

## Fresh public-workspace native108 candidate

The 2026-10-21 candidate has fresh workspace, working, consumer and installed
Mac evidence joined by
`.local/rust-migration/native-phase6/execution-2026-10-21/final-candidate-evidence.json`
(SHA-256 `b54177dd5b2fcf21d28f0c51f6a65baf218bffdc826bb23ce832e3314f22e972`).
This is the V3/S4/native108 public-workspace successor to the historical
candidates above. The join rehashes 125,102 concrete proof files. It establishes
local compatibility and package custody, with cost and target-floor gates
recorded separately.

The immutable `source-2/source-manifest.json` has SHA-256
`68b23ec46f819131b6a79f10ed53d85372cd7e3e26250a7a56402e30c33aca10`.
Its 6,581 files include the offline dependency closure and the qualified
compiled/native inputs. A single unrelated root PNG is explicitly excluded
with a receipt; the user's original file is preserved. Current helper controls
pass all 125 tests. The source snapshot's documentation is retained as captured;
later status edits do not replace its manifest or alter its runtime identity.

The current Mac archive `candidate-macos-arm64-2.tar.gz` has SHA-256
`fd194db9c3b03a3cc6140b168f1441498aeba36ca56b2ffd8a4daa2d695a3ede`.
Its `installed-macos-2/report.json` passes all 40 commands, including the full
381-passed/16-ignored engine roster under Rust 1.85, legacy-artifact refusals,
C and Python clients, offline wheel/sdist/crate clients, static LTO/coexistence
and independent native clients under Rust 1.85 and 1.96. The CLI has SHA-256
`de105b74d8bd1c3ba432f5e7007c3f2ef89622d35cf9b04db278082159ce55e1`;
the deployed shared library has SHA-256
`7053741d7602943c0e90fbde16be01d0454ccac0d48c06ae3408890db8f04e10`.
The original raw outputs and independently normalized static derivative remain
separate in `bundle-1`.

The first installed attempt exposed a missing portable native108 selection
pair. Packaging now includes `proof.json` and `selection.json` beside the
selected `lib/` directory; verification binds those exact bytes to the checked
native boundary, source, target, producer and family. Relocation, missing-pair
and tamper controls pass. Source/archive/installed attempts 1 are preserved
unchanged; attempt 2 supplies the positive current evidence. This Mac run uses
macOS 26.6 ARM64 and SDK 26.5 and does not establish macOS 14 execution.

The opt-in `.github/workflows/rust-candidate.yml` validates actual Ubuntu 24.04
x86-64 and macOS 14 ARM64 before installed verification. Its actions and helper
hashes are pinned, and actionlint passes. It still requires a helper-present
commit and accessible candidate archives with independent hashes. At this
historical checkpoint it had not been committed, pushed or dispatched. A newer Mac, Linux emulation,
or binary deployment metadata cannot establish those execution floors.

The same immutable source2 closure also completed fresh native108 compilation,
the full release-profile workspace suites on Rust 1.96 and 1.85 (381 passed,
16 ignored, zero failures/filters each), a release build, package creation and
all 40 extracted installed checks under Ubuntu 24.04 amd64 emulation. Both
named rosters and the extracted Rust 1.85 roster match qualification3. The
private installed adapter changed exactly the primary engine test command to
`--release` and restored the original command function; every other installed
command remained unchanged. These are release-profile/emulated results, with
no Linux debug, physical-host or timing claim.

The original `linux-preflight/run-3` producer remains failed: after those
successful commands, its final custody loop passed a JSON string path to the
Path-only digest helper. The outer receipt is failed/stable with SHA-256
`793064210945205b2e8f4f73c2485fda9b03c1e4293b5954784bb53670d0c0ee`;
the inner failed report retains its unset pass/stability flags. Separately,
`work/installed/report.json` is positive with SHA-256
`e8fa946e380c663110907267b48dda9165f0cbaafc9df6510a70d0bc2b151b44`.
The adapter's positive, restored receipt has SHA-256
`92f780d5e6afbc29df79874a1909f1f3a811458465e49e097f3fac7bb4225263`.
Those outcomes and files are preserved independently; an installed pass does
not retag the failed producer.

A distinct read-only completion audit now passes with all 14,591 retained
input pins stable. It reparses the actual direct and installed test logs,
checks all 40 installed commands, joins the extracted manifest to the original
archive and revalidates native/static/normalization/selection proofs. It also
executes the three remaining helper/tool/compiler hash guards with explicit
Path values. Native/static facts use the existing canonical JSON encoding,
preserving every field across parser-tuple/JSON-list representations. The
earlier audit refusal is retained separately. No build, test, client, object
tool or native command was rerun, and source/prior/control mounts were read-only.

The positive completion receipt is
`linux-preflight/run-3-completion-5/execution.json` under the current execution
directory (SHA-256
`cfd82325c288dc7d093dc4f27e0299e250bbcabd98bfcc82aa949043b2ad6581`);
its inner byte-audit report has SHA-256
`ec33aa9f88a10bb0b80cbe71511f8668c4ae8e8543cf0be9d65002c2c9ff82ad`.
The Linux archive is 78,303,853 bytes with SHA-256
`ead0bd0414e85ca330ae7dddbbf76503e8ff4b525e8036074a4b2e884c60e453`.
Together the retained functional results and fresh custody audit establish
this source2 candidate's emulated Linux release compatibility and delivery.
The original producer remains failed. Physical Ubuntu execution, Linux debug
qualification, target performance, adoption and release/default qualification
remain separate.
