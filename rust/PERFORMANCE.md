# Rust migration performance review

Further performance and memory-safety work is in progress on 2026-10-22.
The completed qualification and full-matrix results identify retained
source snapshots. Later runtime or qualification-input changes require fresh
combined correctness,
installed-package, and cost runs;
their individual ratios must not be multiplied into a predicted result.
The 1.10 latency/RSS ceiling and default cutover remain open.

## Fixed cutover candidate, 2026-10-22

The selected runtime is `c54221b`, with native source `bf19d6b`. It removes
the optional permission-cache trial. Fresh local qualification passes all
457 default tests, with 16 declared ignores, on Rust 1.85 and 1.96, plus
formatting, both strict all-target/all-feature checks and Clippy, and a fresh
release build. The complete compiled-source/runtime-fixture closure contains
568 files. The same candidate passes all 457 default tests under Rust ASan,
with instrumentation verified in 33 test binaries; the native archive and
prebuilt standard library remain outside it and leak detection is disabled.
The complete working replay also passes with stable inputs: all 31 grammars,
14 extended witnesses and the construction census, 55 functional checks, 24 ABI
checks, 64 default consumer tests, and all 6,216 Go and 102,906 Python inputs.
The final consumer custody covers 110,014 source hashes. Exact receipts are
under `.local/rust-cutover-2026-10-22/`: `qualification-2/report.json`
(SHA-256 `09f62afd3046a2fd173c2c6a658fbef76570ad0e65a55843539006c1d4c17529`),
`asan-2/receipt.json`
(`9745d081c83d362f113a258465c7d1e30d264293b1b606d31f0bda9b740b029b`),
and `working-2/report.json`
(`43ba2f979eb635343f592ab56f9e9c9a366738ba97d24872ceee43238b504036`).
Fresh packages pass all 40 extracted installed checks on the current Mac and
all 40 under Linux amd64 emulation. Both Linux Rust compilers pass the complete
457/16 roster. The Mac archive SHA-256 is
`5c0bc72b6bc905595528d483891c64ff514701cde3fe5767349ee9f3e18bc4a1`;
the Linux archive is
`a59b0e62fe348bc51bcbaa23bb7e5fe2eff4a63b5dde410a0a4d2d7e70fd9b81`.
The private Mac aggregate is
`e182268cea6119cbfb5478e20c10d270278b52b923bf99a8ca97099de962a3d6`;
the positive stable Linux outer receipt, `linux-preflight/run-1/execution.json`
under the isolated checkout's performance directory, is
`2c2a452132bca384f01b4757c95ecbc1631799869861bf58b82acf4ec44617db`.
The same exact archives also pass all 40 installed checks and the 457/16 default
roster on actual macOS 14.8.9 ARM64 and Ubuntu 24.04 x86-64 hosts in
[run 39890987250](https://github.com/The-Billy-Company/joints/actions/runs/39890987250),
helper `9327b86`. Independent GET-only collection verifies both host floors,
package/source/native identities, logs and complete retained proof custody:
138 Mac and 119 Linux evidence files, with 138/112 resolved references and no
unresolved proofs. A separate audit rehashes all six inputs and 287 retained
outputs. The receipt is
`.local/rust-cutover-2026-10-22/candidate-platform-1/collection-3/report.json`
(SHA-256 `c59bdfff18531fe0fcbd51566e33adb8e2b9d3abc440e05a152108beb1debd94`).
Linux's original emulated package scope remains recorded separately from this
native-host verification. The final sealed attempt below accepts no complete
aggregate; sealed, adoption and release/rollback gates remain open.

### Fresh Rust/Zig cost result

The fresh fixed Rust/Zig comparison uses a source-attested incumbent
CLI/library pair, recovered from exact Joints `9f5caf7` and IRGX `fc7a852`
sources and the retained reference overlay. Complete source, dependency,
compiler, build-log and output custody passes, with an independent recheck
of 21,816 proof files. Its receipt is
`.local/zig-source-attested-baseline-20261022/attempt-3/report.json`
(SHA-256 `e51c400487c3359ce4937dd78611f4820dd36d5e46412e26dd2a4116ae316ba4`).
This closes the old library-provenance gap for this comparison; it neither
attests the old library retroactively nor reuses its measured ratios. The
unchanged 1,486 scheduled commands plus 60 admissions complete, with all exit
codes zero and stable custody of 146,994 input hashes. Completion does not
establish cost acceptance: the unwaived 1.10 latency/RSS ceiling still fails.
The 180 metric rows retain 249 review triggers. Cold CLI median Rust/Zig ratios
are:

| Case | Latency | Peak process RSS |
|---|---:|---:|
| JSON | 1.106 | 1.068 |
| Large JSON | 2.364 | 1.463 |
| Go | 2.043 | 1.638 |
| Python | 2.215 | 1.565 |

All four cold-latency medians exceed the ceiling; large JSON, Go and Python
also exceed the median RSS ceiling. Four-worker median per-document latency
ratios are 1.995/4.871/3.618/4.253 for JSON/large JSON/Go/Python, with p95 ratios
2.908/4.636/4.779/5.844. Edit, load and compile rows retain further adverse
results. These current-host diagnostics keep every sample and tail; they
establish no platform floor or cutover pass. No protocol or ceiling changed.
The exact files are `.local/rust-cutover-2026-10-22/cost-matrix-3/run-1/raw.json`
(SHA-256 `8036278075fafb9148feb1b62995ba81499fb7257e8aadd534789f0ccfe68ee2`)
and `summary.json`
(`935b53ac3ebc98323b9f27daa958dc2bdc6abc0dd58b8541ca1fb0f3e7bb9310`).
This Rust/Zig acceptance comparison is separate from the starting-Rust 5–10×
diagnostics below.

### Current ready-load profile

Two owned three-second Go/Python samples complete with stable custody and a
positive current-Q2 profile receipt. They use the raw qualified Q2 shared
library, distinct from the installed Mach-O metadata derivative, joined to the
fresh working and package evidence. The principal sampled stack locations are
automaton decoding/validation, native lexer image loading and envelope
integrity. Their disjoint qualitative sample weights are:

| Stack location | Go | Python |
|---|---:|---:|
| Automaton decode and validation | 1,165 | 1,192 |
| Native lexer image load | 687 | 505 |
| Envelope integrity | 556 | 473 |

These integer weights describe stack locations, not CPU percentages, wall
latency, throughput or engine RSS. Stripped native frames limit finer native
attribution. The receipt is
`.local/rust-cutover-2026-10-22/current-ready-load-profile-1/run-1/receipt.json`
(SHA-256 `eb6ac85273b3f1006268bea2bd76c8961bc22e9682aacf293818873242458b10`);
`sample-summary.json` is
`f8a13b65fa9d73d6c37b8001a723a68b56e281cacb00d13ad7eaf6bdb23b5512`.

### Final sealed aggregate attempt

The single authorized attempt ends with exit code 1 and stable inputs. No
complete aggregate is accepted. Its strict global projections are:

| Backend | Measured entries | Reported `trued` | `measurement_complete` |
|---|---:|---:|---|
| Rust | 16/20 | 0.4024 | false |
| Zig | 19/20 | 0.2855 | false |

The measured subsets differ and both have incomplete coverage, so these
`trued` values establish no comparative correctness gain. Original control
files and pins remain stable, with `no_unsealing: true`. The sealed gate stays
open. The authoritative receipt is
`.local/rust-cutover-2026-10-22/sealed-aggregate-3/attempt-3/report.json`
(SHA-256 `1fcf93ec3757433424fad356b879ed46369c5311161f365e3cf44cc1a820aa37`).

A separate authored C++ external-scanner control generates successfully but
fails linking through the pinned automatic oracle loader. Its inputs remain
stable and owned processes are reaped. The retained refusal is
`sealed-cxx-authored-control-2/report.json` under the same evidence directory
(SHA-256 `e54dd6692e43bcaae8e153ccb84b1ab751cc1cea81b8a020f4527bbae06e19a0`).
This control supplies no cause for the sealed incompleteness, and no retry or
diagnosis is performed.

### Starting-Rust source-CI diagnostics

[Source CI run 39873594325](https://github.com/The-Billy-Company/joints/actions/runs/39873594325)
also passes the complete 457/16 roster on both compilers on actual macOS
14.8.9 ARM64 and Ubuntu 24.04.5 x86-64 hosts. It executes PR merge `b2a38ec`
whose candidate parent is `c54221b`. Both hosts produce the same byte-identical
starting/current JSON, Go and Python artifacts before timing. Standard CI
and CodeQL pass for the same candidate.

That source CI run's unchanged benchmark covers 15 public API workloads and
four cases per host. It does not time every internal function. Three alternating
rounds retain 45 observations per backend/workload/case, complete output digests,
raw samples and p95 values. Ranges below are starting-Rust (`9881c96`) /
selected median time across the four cases; values below one are regressions.

| Workload | macOS speedup range | Linux speedup range |
|---|---:|---:|
| Artifact load | 0.956–1.378 | 1.014–1.269 |
| Artifact write | 0.899–1.150 | 0.958–1.228 |
| Bank load | 0.929–1.129 | 1.009–1.255 |
| Compile | 0.685–1.035 | 0.895–1.027 |
| Paired end edits | 0.926–1.654 | 1.002–1.151 |
| Document open | 0.830–1.155 | 0.996–1.031 |
| Fresh-store effect product | 3.706–74.463 | 5.036–72.255 |
| Lexical walk | 0.913–1.007 | 0.984–1.077 |
| Fresh-session parse | 0.936–1.220 | 1.001–1.022 |
| Reused-session parse | 0.856–1.038 | 1.001–1.024 |
| Query compile | 1.091–1.487 | 1.130–1.217 |
| Query execute | 1.232–1.610 | 1.161–1.309 |
| Covering node | 0.975–1.071 | 0.970–1.009 |
| Sibling navigation | 1.067–4.267 | 1.131–4.763 |
| Root subtree size | 0.803–1.000 | 0.953–1.111 |

Only 3/60 macOS groups and 4/60 Linux groups meet 5×. Parsing on Linux is
near its starting baseline; macOS retains adverse reused-parse and compile
results. Some adverse directions recur across rounds. The reports preserve
them rather than attributing every regression to host noise. These results
establish neither the requested general 5–10× gain nor the separate fixed
Rust/Zig cost ceiling. Exact reports and custody are under
`.local/rust-cutover-2026-10-22/source-ci-c54221b-{macos-arm64,linux-x86_64}/`;
`source-ci-c54221b-summary.json` joins both hosts.

The later [source CI run 39882081890](https://github.com/The-Billy-Company/joints/actions/runs/39882081890)
also completes successfully on both actual hosts, with the full 457/16 roster
on both compilers and byte-identical starting/current JSON, Go and Python
artifacts. It executes merge `ac3810c` for tooling commit `4cecfd8`; its compiled
source maps remain exactly `c54221b` and native `bf19d6b`. Standard CI and CodeQL
also pass for that tooling commit. This separate hosted diagnostic reaches
5× in 6/120 groups, three on each host, compared with 7/120 in the earlier run
above. The observations are separate replicates and establish no isolated
cause for their differences. The general 5–10× target remains unmet. Its join
is `.local/rust-cutover-2026-10-22/source-ci-4cecfd8-summary.json`
(SHA-256 `90b39cd692c5741d7055c4f57489687677c5868d973ad3ac7d5fcd2050655340`).

Source-CI jobs on both host targets and standard CI are also green for later
tooling `9327b86`. This is an API-status observation pending artifact custody;
no newly checked compiled-map join or replicate counts are claimed. The 6/120
diagnostic above belongs to the earlier `4cecfd8` run. The separately collected
actual installed-platform result is recorded above; it establishes no new
performance ratio or default-cutover pass.

One same-source tree-validation ablation compares this candidate with its
unchanged full-walk fallback forced on. The normal/full median-time ratios
are 0.995 for JSON reused parsing, 1.017 for JSON fresh parsing, 1.016 for
Python reused parsing and 0.943 for Go reused parsing. Round directions are
mixed; Go whole-child CPU favors the normal path in every round. This does
not identify the shortcut as the cause of the larger hosted regressions, so
it is retained. The experiment restores its source and preserves exact
binaries, native selection, semantic digests, tails and child CPU under
`.local/tree-measure-ablation-20261022/`. Whole-child CPU includes setup and
validation and does not supply per-function CPU timings.

All earlier results below remain attached to their recorded sources. They
are not passes for `c54221b`.

## Cutover follow-on against starting Rust, 2026-10-22

The requested baseline is commit `9881c96`. A fresh benchmark executable was
captured from that checkout before these edits. The following diagnostic uses
the same benchmark source against runtime commit `26f48be`, with the same
checked native archive. It includes the concrete selected-trace product,
bounded lexer permission cache, compiler/artifact changes and query/tree paths.
Later CI-only changes and the equivalent MSRV comparison-expression rewrite
are qualified separately; these measurements do not claim their exact bytes.

Three alternating rounds retain 45 samples per backend/workload/case and
matching complete tree, lexical, query and effect digests. All team builds and
profiling jobs finished before timing. Other host processes remained heavily
active, and both medians and tails fluctuate. Values are starting/edited;
below one is a regression. Every p95 and raw sample is retained under
`.local/rust-optimization-followup-2026-10-22/measure-final/`.

| Workload | Wide JSON | Ledger JSON | Go | Python |
|---|---:|---:|---:|---:|
| Artifact load | 1.330 | 1.355 | 1.230 | 1.056 |
| Artifact write | 1.148 | 1.353 | 1.855 | 1.209 |
| Bank load | 1.250 | 1.154 | 0.821 | 0.778 |
| Compile | 1.121 | 1.209 | 2.000 | 1.519 |
| Paired end edits | 1.250 | 1.082 | 0.886 | 1.442 |
| Document open | 0.970 | 1.156 | 0.751 | 1.633 |
| Fresh-store effect product | 2.670 | 49.450 | 59.962 | 113.841 |
| Lexical walk | 1.002 | 0.923 | 0.947 | 0.945 |
| Fresh-session parse | 0.987 | 1.164 | 0.667 | 1.366 |
| Reused-session parse | 0.992 | 0.959 | 0.788 | 0.916 |
| Query compile | 1.353 | 1.361 | 1.125 | 1.497 |
| Query execute | 1.318 | 1.307 | 1.389 | 1.296 |
| Covering node | 1.031 | 1.000 | 0.968 | 0.953 |
| Sibling navigation | 3.915 | 0.900 | 0.875 | 0.859 |
| Root subtree size | 1.000 | 1.000 | 1.000 | 1.000 |

Only three of 60 groups meet 5×. Fresh-store products avoid the original
intermediate effect interning, so their gain varies with trace diversity and
does not describe parsing throughput. No broad parsing or lexical gain is
established. Single-call subtree timings are near clock granularity.
The general 5–10× target remains unmet.

A separately rebuilt starting CLI and the current runtime CLI produce
byte-identical JSON, Go and Python folios with the same fresh native108
selection. The three sizes are 161,950, 4,008,638 and 4,649,374 bytes;
`artifact-comparison/report.json` retains source/native identities, executable
hashes, mint commands and artifact hashes. This checks the compiler and seal
changes without inferring wire equivalence from equal file sizes.

The initial combined candidate had alarming Go compile wall-time regressions.
Separate whole-process CPU controls did not reproduce those regressions:
baseline/edited median child CPU ratios were 1.035 for the first candidate
and 1.091 after kernel-directory/product changes. Those controls include setup,
validation and destruction; they are diagnostics, not per-function CPU times
or a reason to discard adverse wall samples. Raw controls and inclusive CPU
profiles remain in the same evidence directory.

The combined local release suite passes 460 tests with 16 declared ignores,
including independent compiler, cache-accounting, selected-product and
malformed-tree controls. The source CI workflow now repeats strict checks and
the complete default roster on both Rust compilers and actual target hosts,
then separately retains starting-Rust benchmark executables, artifact-byte
comparisons, raw samples and summaries. Installed delivery, full working
consumers, fixed Rust/Zig cost acceptance, sealed validation and rollback
remain separate gates. Earlier receipts below are historical snapshots.

The same comparison also completed on the actual macOS ARM64 and Ubuntu
x86_64 CI hosts in [source CI run 39867510800](https://github.com/The-Billy-Company/joints/actions/runs/39867510800).
Both hosts passed the full 460-test roster, with 16 declared ignores, on Rust
1.85 and 1.96. This run identifies PR merge source `792e67d` and native
`0e74778`; it does not qualify subsequent source or dependency revisions.
Its performance jobs retain 45 observations per backend/workload/case.

| Workload | macOS speedup range | Linux speedup range |
|---|---:|---:|
| Artifact load | 0.997–1.191 | 1.013–1.266 |
| Compile | 1.020–1.037 | 0.919–1.074 |
| Fresh-store effect product | 3.429–72.411 | 5.278–72.568 |
| Fresh-session parse | 0.937–1.073 | 0.967–1.028 |
| Reused-session parse | 0.860–1.007 | 0.933–1.040 |
| Query execute | 1.270–1.335 | 1.138–1.235 |
| Sibling navigation | 0.907–3.571 | 0.973–4.062 |

Each range covers the four retained cases, using starting/edited median time.
Go fresh/reused parsing is 0.937/0.860 on macOS and 0.967/0.933 on Linux;
Python is 0.983/0.946 and 0.983/0.957 respectively. These actual-host results
confirm that broad parsing improvements and the general 5–10× target have
not been achieved. They do not isolate a responsible change. Exact reports,
binary hashes, p95 values and raw observations are retained under
`source-ci-a63830d-{macos-arm64,linux-x86_64}/rust-engine-ci/` in the same
local evidence directory.

The optional permission cache in `26f48be` was subsequently withdrawn. A
same-source activation ablation retained identical native/archive/binding and
569 source/fixture identities, exact output digests and 45 observations per
backend/group. Cache-off/cache-on median speedups were 1.067/1.207 for Go
fresh/reused parsing and 1.060/0.969 for Python. Whole-child CPU includes grammar
setup and validation, so these wall-time ratios alone do not identify equivalent
per-function CPU gains. Exact binaries, patch, rounds, tails and CPU observations
are retained under `.local/permission-cache-ablation-20261022/`. The final source
also removes redundant tree-proof checks and specializes sibling direction/name
flags at compile time; it requires fresh qualification and measurement.

## Earlier safe public-API profiling trial, 2026-10-22

The development checkout adds checked sibling lookup over preorder IDs,
allocation-free subtree counting, full-tier native lexer admission, a single
newline-index search, and effect compatibility checks before ledger copying.
No unsafe engine code, unchecked indexing, new per-node fields, relaxed
validation, or larger resource ceilings are introduced. The parser child-arena
trial remains private: its paired run regressed large-JSON parse medians by
11–15 percent and one whole-process edit RSS measurement by 36 percent.

The new `rust/benches/runtime.rs` exercises 15 public API workloads: grammar
compilation, artifact writing/loading, bank loading, lexical walks, fresh/reused
parsing, effect products, query compilation/execution, sibling navigation,
covering nodes, subtree size, document opening, and paired end edits. Setup,
complete output checks and SHA calculation are outside timed regions;
allocations and destruction are included. An edit row contains two edits.
Standalone lexical walks report coverage because they can stop before the end
of a contextual language. This is workload coverage, not a claim to time every
internal function or every scanner, recovery policy, input size and worker count.

`tool/rust_perf.py` alternates before/after process order, retains raw samples
and p95 values, and refuses mismatched source/grammar, full tree, lexical,
query or effect digests. It also checks sample coverage, iteration counts and
unchanged executable/input hashes. Four portable regression tests exercise
these refusal paths. It records the requested 5×/10× median targets per
workload without treating one fast component as a whole-program improvement.
The comparison baseline is the starting Rust checkout; the separate Rust/Zig
cutover ceiling remains unchanged.

With the checked native archive selected as described in [README.md](README.md),
build the benchmark with `cargo bench --manifest-path rust/Cargo.toml --bench
runtime --no-run`. The resulting executable accepts `--grammar`, `--source`,
`--samples`, `--iterations`, `--entries` and `--only`. Retain one executable per
revision, then compare them:

```sh
python3 tool/rust_perf.py --baseline /absolute/path/before-runtime \
  --candidate /absolute/path/after-runtime \
  --output /absolute/path/new-comparison --rounds 3 --samples 15
```

Development evidence is retained under
`.local/rust-optimization-2026-10-22/`. The isolated full-permission native
kernel improves 1.22–7.82× for 8–512 patterns. An uncached incompatible
eight-claim effect composition improves 19.14× by avoiding discarded copies;
accepted calls and warm memo hits show much smaller or mixed changes.
These synthetic results supply no parser-wide gain. Fresh qualitative CPU
samples still identify lexical scanning, parser advancement, native image
validation and integrity hashing as substantial remaining costs. The samples
are inclusive diagnostics and cannot be added into a predicted speedup.

The combined diagnostic compares the same benchmark source against the captured
starting engine and the edited engine. Three alternating rounds retain 45
samples per backend/workload/case and matching complete output digests. All
60 workload groups retain their p95 values in `measure/*/summary.json`;
several tails regress substantially under uncontrolled host activity. Median
speedups below are **before / after**, so values below one are regressions.

| Workload | Wide JSON | Ledger JSON | Go | Python |
|---|---:|---:|---:|---:|
| Sibling navigation | 117.475 | 1.117 | 1.025 | 0.959 |
| Root subtree size | 57.886 | 11.014 | 8.135 | 11.832 |
| Lexical walk | 1.048 | 0.950 | 0.987 | 1.593 |
| Fresh-session parse | 1.057 | 0.974 | 0.797 | 0.906 |
| Reused-session parse | 1.076 | 0.991 | 0.820 | 0.780 |
| Paired end edits | 1.000 | 1.001 | 0.954 | 1.158 |

The subtree operation becomes very short. Separate controls with 1,024 calls
per sample confirm its improvement beyond single-call clock granularity;
`subtree-batched/` retains those repeated-call results. The wide sibling
workload visits every node and asks for both ordinary and named neighbors.
Its large gain does not describe a small sibling list or parsing throughput.

Focused parse controls use five alternating rounds, 21 samples and 16 calls
per sample. Go fresh/reused speedups are 0.788/1.082, and Python fresh/reused
are 0.928/1.062. A separate one-file lexer ablation changes Go fresh parsing by
about 3 percent, with mixed round directions; it does not attribute the earlier
large gap to that shortcut. The general parsing target remains open rather
than treating these conflicting diagnostic results as a pass.

Three whole-process peak-RSS observations per backend/case give edited/starting
median ratios of 1.022 for wide JSON, 1.020 for ledger JSON, 1.044 for Go and
0.987 for Python. These include setup, validation, all workloads and allocator
retention. They establish no per-function memory reduction or leak result.
Raw observations are under `memory/`.

The development source passes 446 release-profile tests with 16 declared
ignores and the same 446-test AddressSanitizer roster; ASan instrumentation is
verified in 34 binaries. The Rust standard library and native archive remain
outside Rust ASan, with leak detection disabled. Strict all-target/all-feature
checks pass on Rust 1.85 and 1.96. The exact Rust 1.85 source closure contains
565 files. Formatting, the separate four-test recorder controls and focused
tree checks supplement these results; the final local receipt identifies their
sources and logs. Historical package qualification is not inherited.

The final source-backed build refreshes stale producer metadata for the checked
native boundary. Its archive container and private symbol namespace differ from
the measured archive, while the complete raw `irgx.o` payload is byte-identical
(SHA-256 `d492698c84ebf7a4e60983cd2da12f174d257bb0a41d815d82d2b8fbebe141e7`).
Both checked transforms retain the same runtime sections, relocation counts,
public exports and unresolved imports. Fresh JSON/Go/Python smoke runs with the
refreshed native boundary preserve every tree, lexical, query and effect digest
and artifact size. `native-object-join.json` and `final-native-context.json`
retain that join; complete performance figures still identify their original
immutable benchmark executables.

The 5–10× target across all functions remains unmet. These development checks
do not replace the complete fixed cost matrix, working consumers, installed
delivery, physical platforms, sealed aggregate or rollback gates below.

## Current packaged Q7 result, 2026-10-22

The selected source completes fresh installed checks and the full fixed cost
protocol. Both Rust 1.85 and 1.96 pass 443 default tests with 16 ignores on the
Mac and under Linux amd64 emulation. All 40 extracted installed checks pass
on each platform. The full working replay, all 6,216 Go and 102,906 Python
inputs, and the separate 443-test Rust ASan run remain tied to this same
564-file compiled-source/runtime-fixture closure. No later trial is selected.

All 1,546 benchmark commands exit successfully without a timeout, with 1,420
measured rows, 180 metric groups, and unchanged inputs. All known team build
and profiling jobs finished before timing. Other host work was uncontrolled;
this remains a contended current-host diagnostic. Cold CLI means a fresh
process with ordinary warm filesystem caches.

| Case | Cold median Rust/Zig | Cold p95 Rust/Zig | Median peak RSS Rust/Zig |
|---|---:|---:|---:|
| JSON | 1.208 | 1.021 | 1.080 |
| Large JSON | 2.436 | 2.286 | 1.522 |
| Go | 2.134 | 1.853 | 1.642 |
| Python | 2.312 | 2.241 | 1.531 |

All four cold-latency medians fail 1.10. Only small JSON meets the cold RSS
ceiling; its RSS p95 ratio is 1.067. Large JSON, Go and Python RSS p95 ratios
are 1.367, 1.665 and 1.589. The complete result retains 244 review triggers,
including 38 RSS and three artifact-size facets. Individual trial gains are
not multiplied into these results.
At these measured ratios, reaching 1.10 would require approximately another
49–55 percent reduction in cold latency for large JSON, Go and Python, with
the measured Zig costs held fixed.

The unchanged native worker also retains substantial gaps. Its one/two/four
worker per-document median Rust/Zig ratios are:

| Case | One worker | Two workers | Four workers |
|---|---:|---:|---:|
| JSON | 3.278 | 3.719 | 2.290 |
| Large JSON | 3.545 | 4.335 | 5.894 |
| Go | 3.493 | 3.823 | 3.167 |
| Python | 4.118 | 4.072 | 3.845 |

Late large-JSON Whole insert/delete median ratios are 41.086/38.789; Prove
ratios are 37.834/34.722. All tails remain in the report. Parse/edit timing
includes ctypes call overhead; strict and full-image validation occurs outside
those timed ABI calls. Throughput timing also includes Python orchestration,
strict validation and tree teardown. The immutable
Zig library lacks source-to-library attestation, so these ABI comparisons are
diagnostic. Each native peak-RSS series has five whole-worker samples and no
reported p95. The cold CLI baseline has separate source attestation. Artifacts
also remain much larger: Rust/Zig byte ratios are 14.669 for JSON, 27.210 for
Go and 19.054 for Python.

Evidence under `.local/rust-migration/performance-2026-10-21/`:

- `final-candidate-evidence-6.json` joins current workspace, working-consumer,
  source export, package and installed Mac results; SHA-256
  `7652f84f389d10afdcf1f5fb91b300380fd17ab8ea5766b358727f99e4da7ff8`.
- `linux-preflight/run-6/execution.json` separately records positive emulated
  Linux execution and custody; SHA-256
  `6e1580ec797b2cdc4f12912009e27723371eab3d67a6c0cf6f97d819c6688107`.
- `full-matrix/run-6/raw.json` has SHA-256
  `c6cfa1d6a24645c438c386d8d805538e168af464c858ec101ab2dccd3a8c58e8`;
  `summary.json` has SHA-256
  `0ce60c47e127c7fa850be9c012922c9ff674ea6b9c17f6e970696e4048402b94`.

The source count remains 25,737 production Rust lines. Performance acceptance,
physical target floors, the sealed aggregate, installed-consumer adoption and
release/rollback remain open. Zig remains the default.
The checked native decoder changes are recorded in the sibling IRGX repository
at commit `59dede3d8ac5a280ca5addc8d5ceefe3aa9917f9`.

## Intermediate performance checkpoint, 2026-10-22

The current Q7 source additionally reclaims unpublished effect runs after failed
document edits. It passes 443 default tests with 16 ignores on each compiler,
formatting, strict Clippy, all-target checks and a release build, with a stable
564-file source/runtime-fixture closure. Its report is
`qualification-7/report.json` (SHA-256
`34bdb7a92e931ffcbd7743e6844240fdeb14f2657f40fe6183297d870f8029b8`).
The same source passes 443 ASan tests with instrumentation verified in 33
binaries. The refusal comparison preserves all 408 outcomes and work counters;
none of its 204 measurement-time refusals retains newly created runs after
cleanup. Collection capacities can retain their high-water marks. The same
Q7 source passes all five working stages: 31 grammars, 14 extended witnesses,
55 functional checks, 24 ABI checks, and the complete consumer replay. All
6,216 Go and 102,906 Python inputs agree, with 12 paired deterministic artifact
profiles. The stable report is `working-5/report.json` (SHA-256
`4528b2ee5cd94a711ec77fa5de7b71fe3acdf8dbbd214e73fdae419554f15cf0`).
The installed and complete cost runs are recorded above; the Q6 figures below
describe the retained predecessor.
The stopped Q6 working run passed grammar, extended-witness, functional and ABI
stages, but its consumer replay was intentionally cancelled for this fix and
does not qualify the final source.

The selected combined Q6 snapshot passes 440 default tests with 16 declared
ignores on each of Rust 1.85 and 1.96, formatting, all-target/all-feature checks,
strict Clippy, and a release build. The complete 562-file closure is stable.
Its report is `qualification-6/report.json` in the performance directory below
(SHA-256 `89c36cc678baac691ad90c9d57ef3ce0acd8ac9c52a6b2a79657aeb2c2a48258`).
This includes the adaptive memo described below. The same selected source has
a separate 440-test ASan pass with instrumentation verified in 33 binaries,
plus native ReleaseSafe controls with expanded dependency custody. See
[the safety boundaries and receipts](SAFETY.md#validation). Fresh working-consumer
inventories, installed delivery, and the full cost matrix were pending at that
Q6 checkpoint; the current Q7 results are recorded above.

The Q6 development comparison completes 540 cold/admission commands and 693
native commands with stable qualified inputs and exact full-tree checks. Its
receipt is `combined-q6-diagnostic-1/receipt.json` in the performance directory
below (SHA-256 `c800e4b479befb7a2daffe2d5fd2f6882e7514be95b764490537e1be4c21c65c`).
Concurrent host activity remains present, so this is not an acceptance run.

| Case | Cold median Q6/prior Rust | Cold median Q6/Zig | Median peak RSS Q6/Zig |
|---|---:|---:|---:|
| JSON | 0.910 | 1.116 | 1.063 |
| Large JSON | 0.536 | 2.607 | 1.514 |
| Go | 0.775 | 2.248 | 1.645 |
| Python | 0.786 | 2.372 | 1.535 |

All four cold-latency medians still exceed 1.10. Warm parse medians improve by
about 56–79 percent and four-worker per-document medians by about 83–86 percent
against the retained Rust baseline, but remain above the diagnostic Zig ABI
baseline. Late large-JSON Whole edit medians fall to about 9 percent of prior
Rust, while remaining about 35–37 times the diagnostic Zig result. The full raw
rows retain all tails; none of these improvements passes the acceptance gate.

Two later candidates remain unselected after exact controls and measurements:
native adjacent-target proof reuse made loading 1–3 percent slower; sparse lexer
metadata improved Python warm parsing but regressed Go edits and added code and
scratch space. Their complete results, including tails and failed preparation
attempts, remain under `next-load-1/native-adjacent-targets/` and
`../performance-work/parser/sparse-allow/` respectively. Neither changes Q6.

A later private Q7 checkpoint-summary trial also remains unselected. Its
19 focused controls, strict checks on both compilers, and 354-command paired
comparison pass with unchanged inputs and complete syntax/cost agreement.
Whole late-edit medians improve only 1–2 percent, while cold medians and edit
worker RSS rise slightly. The complete evidence is retained under
`../performance-work/parser/checkpoint-read-max/`; it does not change Q7.

A private exact-kernel-sharing trial also remains unselected. Its simplified
variant preserves the original scalar decoder, all logical state identities,
full S4 bytes and validation. Focused controls and strict checks pass on both
Rust versions, including allocation refusal and metadata-header accounting.
Owned storage falls by 528,776 bytes for Go and 412,312 bytes for Python.
However, its 442-command paired diagnostic observes only about 3.5 and 2.1
percent lower cold CLI RSS respectively, while all four cold medians rise
about 2–4 percent. Loaded Go/Python parse medians rise about 5/8 percent, with
mixed worker and tail results. This does not justify the added code and CPU
cost. All raw results, rejected preparation attempts and scope limits remain
under `kernel-row-sharing-1/`; `final-handoff.json` has SHA-256
`62b32d05b06f9c809ba275efef4fd7fa5bc50c86057e82c0461222563708b901`.
Q7 remains unchanged.

A three-arm arena-growth trial also remains unselected. All 885 workload
commands and 240 owned RSS probes complete with unchanged inputs, complete
tree agreement and equal exposed work counters. Growing only the output-node
arena in smaller steps reduces repeated large-JSON process peak RSS by about
22 percent and resident memory after tree drop by about 15 percent. However,
cold large-JSON RSS rises 5.6 percent, its cold median rises 2 percent, and
several warm, edit and worker latency series regress. The large-JSON warm
parse p95 rises 64 percent; Python warm median/p95 rise 8/23 percent.
Changing both node and draft growth also has mixed or adverse results.
The complete 81-row comparison is retained at
`../performance-work/parser/arena-growth/measure-1/summary.json`, with raw
SHA-256 `c1d5ee1e1e7ecaf7a93e9d697a5ce5f49ff6e03f9b308b9837bd81365b0c8a76`.
Native workers include Python inspection and allocator retention; their RSS
cannot be attributed solely to Rust vector capacity or treated as a leak
measurement. Their five process peak-RSS samples have no reported p95.
Neither policy changes the selected source.

The later combined Q5 snapshot passes 436 default tests with 16 declared ignores
on each of Rust 1.85 and 1.96, formatting, all-target/all-feature checks, strict
Clippy, and a release build. Its complete 562-file source/runtime-fixture closure
includes the repaired inventories described below. The stable report is
`.local/rust-migration/performance-2026-10-21/qualification-5/report.json`
(SHA-256 `4eec744a1421d354eaa577bd303787d05352a98cc105fd3cfcc1ca795356704f`).
Its native provenance refresh preserves both raw and selected archive bytes.
Fresh sanitizer, working, installed, consumer, and complete cost checks remain
separate; this is a combined workspace correctness result.

Q5 additionally selects checked charge arithmetic without eager error dropping,
eight-way permission buckets within the existing storage cap, and a bounded
successful-effect memo. Two isolated memo comparisons reduce late large-JSON
edit medians by about 70–74 percent against their unchanged baseline. They also
retain regressions in some parse, drop, worker, and tail observations; no cold
or worker gain is claimed. The raw controls and both cost runs are under
`effect-memo-delay32/` in the performance directory above. The memo currently
allocated its fixed table after 32 successful eligible misses. A separate
many-store census found about 80 MiB of table buffers for 512 warmed one-key
stores, motivating the subsequently selected adaptive table. That table begins
with 64 slots and grows transactionally to the same maximum. The 512 warmed
one-key stores use 640 KiB of table buffers, a 128-fold reduction; corpus entry
and hit counts remain equal. Two comparisons retain mixed latency and tail
results, so selection is for memory rather than speed. Its controls and raw
costs are under `effect-memo-adaptive/`; Q6 completes combined qualification.
Q5 qualifies the preceding fixed-table snapshot. The census observed payload and
grammar owners releasing after drop; it did not measure allocator RSS.

The combined Q4 snapshot passes 425 default tests with 16 declared ignores on
each of Rust 1.85 and 1.96, formatting, all-target/all-feature checks, strict
Clippy, and a release build. Its report is
`.local/rust-migration/performance-2026-10-21/qualification-4/report.json`
(SHA-256 `eb1b063c4d8c58a4af0ce31cf1c283fc21cfa8319838bb2d14a7d1a96bcbcc01`).
A separate stable run passes 425 AddressSanitizer tests with 17 ignores and
checks instrumentation in 33 test binaries. It instruments Rust engine/adapter
code; the prebuilt standard library and native Zig/C archive remain outside
ASan. Native image controls also pass in ReleaseSafe. The exact safety receipt
is `perf-safety-2026-10-21/selected-final-attempt-4/receipt.json` under
`.local/rust-migration/`. These are observed Q4 passes before subsequent trials.

A later private reconstruction found omitted runtime fixtures in the retained
input closure: specimen exports and runtime-only grammar/source inventories.
The live-checkout tests executed successfully, but that incomplete snapshot
cannot independently reproduce every default test. The inventory helper and
its regression test are repaired, and Q5 completes fresh combined workspace
qualification with the full closure. The repair receipt is
`runtime-custody-followon-2/receipt.json` under the performance directory above.
The development benchmark inputs have their own independent file guards.

Two development comparisons bind the same Q4 CLI/library and unchanged inputs:
`combined-cold-development-4` (540 commands) and
`combined-native-development-4` (693 commands), under the performance directory
above. They use the frozen four cases and retained full-image admissions.
Other host work remains present. These diagnostics are separate from the
complete 1,546-command acceptance protocol and cannot pass that protocol.

| Case | Cold median Q4/prior Rust | Cold median Q4/Zig | Median peak RSS Q4/Zig |
|---|---:|---:|---:|
| JSON | 0.956 | 1.141 | 1.063 |
| Large JSON | 0.646 | 3.034 | 1.400 |
| Go | 0.813 | 2.076 | 1.714 |
| Python | 0.811 | 2.238 | 1.579 |

All four cold-latency medians still exceed 1.10. Cold p95 ratios are
1.863/2.774/1.548/2.656 in the same order. Four-worker per-document medians
improve by approximately 79–81 percent against prior Rust, but remain
3.21/8.15/4.51/4.97 times the diagnostic Zig ABI baseline. The large-JSON
two-worker p95 regresses against prior Rust by 1.670 times; Python drop median
and p95 also regress by 1.117 and 1.141 times. These observations remain in
the raw report. Late edits still spend substantial time reconstructing effects
and materializing the complete tree despite retained-prefix reuse.

Qualitative profiles identify automaton decoding/validation, native image
loading, and envelope integrity checking as the largest loading costs. Hardware
SHA-256 is already active; the per-input seal remains required. Parsing spends
substantial time in lexing, advancement, and permission proofs. Component trials
must preserve complete images, resource/refusal behavior, ownership, and input
custody. Their gains are not multiplied into a prediction for the combined build.
Q5 completed combined correctness for the selected follow-on changes; their
safety, delivery, working-consumer and complete cost checks were pending at
that checkpoint. The current Q7 results are recorded above.
The Q7 source count is 25,737 production Rust lines: 22,235 engine, 2,093 CLI
and 1,409 C adapter, 15,737 above the independent 10,000-line goal. The same
retained counting convention excludes the two new test-only modules; its stable
receipt is `production-count-current-4/receipt.json` (SHA-256
`04a363745bac8ce000b465aa464e0293e357d6f9212fe896c7ce24f7f116894f`).

The retained Q6 source count is 25,684 production Rust lines, 15,684 above the separate
size goal, under the unchanged approximate counting convention. Its receipt is
`production-count-current-3/receipt.json` in the performance directory above.

## Retained full-matrix results

Phase 6 remains open. The retained public-workspace Rust candidate passes its
fresh local compatibility and installed Mac package checks, but the complete
cost matrix still exceeds the agreed 1.10 latency/memory ceiling. These results
do not justify switching consumer or release defaults. Candidate F has
approximately 22,868 production Rust lines; the private Image1 successor had
approximately 23,808 under the same engine, CLI and C-adapter scope, excluding
actual test-only observers. The 10,000-line goal remains unmet. Results below
retain each candidate's identity; the latest measurements are in
[the fresh public-candidate review](#fresh-public-candidate-full-cost-matrix).

## Fixed candidate and method

The initial measurement uses the immutable phase-5 E CLI `e73eb9ee016afd74`
and source-attested Zig CLI `709bf8c0ce4a3c9a`. The Rust build uses Rust 1.96,
LLVM 22.1.2, and macOS SDK 26.5 on macOS arm64. The full input identities,
host record, commands, and raw observations are retained under
`.local/rust-migration/native-phase6/performance/`.

The protocol was frozen before results. All 1,540 commands completed with
unchanged inputs in an exclusive measurement window. Each latency series has
40 raw observations; p95 is an empirical nearest-rank statistic. CLI runs use
fresh processes after three retained warmups. Filesystem caches remain warm.
The four cases are the frozen JSON, Go, and Python ledger examples and an
authored 131,751-byte JSON array built from the JSON seed. They establish costs
on these inputs, rather than whole-language performance.

Admission requires equal complete preorder tree images, fields, byte spans,
and repair evidence. Independent cold images agree for the 12 edited inputs.
Every timed native parse/edit checks strictness and the expected reachable node
count outside its timer; full images are additionally checked at block edges.
All 344 quiet CLI verdicts match their backend's exact preflight counters.
The incumbent can retain unreachable arena nodes, so its held-node count is
not incorrectly required to equal its reachable-node count. The original
overstrict counter validator and its failure remain retained.

## Primary CLI results

Cold parse includes process startup, loading the backend's native artifact,
parsing, and exit. RSS is the actual whole CLI process high-water mark. Times
are milliseconds and memory is decimal megabytes; ratios use unrounded values.

| Case | Zig median ms | Rust median ms | Rust/Zig latency | Zig RSS MB | Rust RSS MB | Rust/Zig RSS |
|---|---:|---:|---:|---:|---:|---:|
| JSON ledger | 3.150 | 5.480 | 1.74 | 3.375 | 4.637 | 1.37 |
| JSON 128 KiB | 7.442 | 61.819 | 8.31 | 10.412 | 20.210 | 1.94 |
| Go ledger | 4.499 | 48.739 | 10.83 | 8.159 | 29.032 | 3.56 |
| Python ledger | 4.969 | 59.202 | 11.92 | 10.355 | 33.767 | 3.26 |

Startup alone is 2.804 ms for Rust and 3.137 ms for Zig. Most of the difference
therefore lies after process startup. Go compile/mint costs 414.592 ms versus
49.350 ms; Python costs 733.038 ms versus 75.032 ms. Artifact inspection,
which includes each product's validation and rebinding, costs 100.371 ms versus
3.495 ms for Go and 120.709 ms versus 3.794 ms for Python.

| Native artifact | Zig bytes | Rust bytes | Rust/Zig |
|---|---:|---:|---:|
| JSON | 11,040 | 8,486 | 0.77 |
| Go | 147,320 | 2,788,154 | 18.93 |
| Python | 244,008 | 3,371,750 | 13.82 |

These are different encodings; byte-for-byte equality between backends is not
expected. Repeated fresh minting must remain deterministic within each backend.

## Native diagnostics and causes to investigate

The co-installed Zig library is pinned to its observed bytes but lacks the
historical CLI's source-to-output attestation. All ABI comparisons with that
library remain diagnostic. The complete report includes ready-load, native
parse/drop, navigation, edit positions at 2/50/98 percent, and independent
document throughput with 1/2/4 workers. ABI timings include the stated common
ctypes/clock boundary. Worker RSS includes Python and fingerprint validation;
no engine-only memory estimate is inferred by subtraction. Five blocks of
eight observations are not forty independently started processes.

Diagnostic native parse medians are approximately 13.2/14.9/25.0/27.0 times
the incumbent for JSON/large JSON/Go/Python. Whole-tree navigation is much
closer, around 1.04–1.10 times in the measured medians. Incremental Rust parsing
still rematerializes the tree and proves retained prefixes; late edits do not
establish position-independent total cost or suffix lifting.

Qualitative samples of the Rust process identify admission proofs, parser
advancement, and lexing as parse costs. Loading spends substantial CPU in
lexer compilation and two envelope checks. Compiler samples identify canonical
LR construction. Inclusive stack percentages overlap and are not additive.
Layout probes show spare capacity in immutable tree arrays and substantial
action/transition tables in large artifacts. Kernel/history metadata is a
small minority of those artifacts; deleting inspector behavior would not
address their main size cost.

The initial isolated trials therefore test recovery scratch allocation,
inline deterministic head buffers, immutable snapshot arrays, and removal of
one redundant envelope hash after ownership and verification are established.
Correctness checks alone do not establish an optimization. Each trial needs
its own unchanged-source parity check and controlled comparison against E;
combined changes require a new qualified candidate.

## Allocation trial decisions

The completed follow-up compares three separate changes against exact E on the
same four sources, plus an authored grammar with competing reductions after a
shared prefix. All five full trees and 16 minted artifacts agree across the
four arms. The fixed run completes all 1,302 commands with unchanged inputs;
each latency cell has 40 raw observations. No combined arm is measured here.

Recovery scratch storage is supported for a new candidate. It replaces bounded
heap scratch with a checked fixed array and keeps the initial search item local.
The differential control preserves both answers and charged work for 22,655
admission/insertion questions. Native parse-plus-drop median ratios against E
are 0.799/0.806/0.808/0.815 for JSON/large JSON/Go/Python; empirical p95 ratios
are 0.746/0.821/0.880/0.853. Large JSON CLI latency improves by about 17 percent.
All 24 edit median cells improve by more than 10 percent; no edit median or p95
regresses by more than 10 percent. Peak process memory shows no material gain.

Two isolated drop-tail flags remain: Go p95 rises from 1,208 to 1,334 ns and
Python from 917 to 1,208 ns. Their combined parse-plus-drop p95 improves by
12.0 and 14.7 percent respectively. This explicit tradeoff supports selecting
the optimization for fresh qualification; it does not accept the remaining
Rust-versus-Zig costs or satisfy cutover budgets.

Inline head buffers are declined. They add a dependency, show no material
benefit on the original cases, and increase branching-case parse-plus-drop
median by 11.3 percent (709 ns). The final snapshot-array change is deferred:
its retained payload is smaller, but CLI peak RSS is essentially unchanged and
large JSON parse-plus-drop p95 rises 12.3 percent (7.00 ms). No such regression
is silently accepted in exchange for an unmeasured resident-memory benefit.

The complete follow-up is retained under
`.local/rust-migration/native-phase6/trials/comparison-v2/run-1/`.
Its executed/stable raw receipt has SHA-256
`ed4e25b8efcd057357ee9b899f95105377e28a88b091541cdc0b47c9fec9fe6f`;
the complete summary has SHA-256
`419c63fb225248865b4484c1f7e76cacca0764b6d252b55ae619bdbee51f1549`.

## Loading trial decisions

The separate three-arm loading run completes all 983 commands with unchanged
inputs. Removing the second read-back for single-member inspection improves
inspection medians by 24.6 percent for JSON and about 41.5 percent for Go and
Python. It retains complete input decoding and canonical encoding; actual
minting and bank repacking retain their read-back checks. Exact inspection
output, artifact bytes, and complete tree images remain unchanged.

Verified payloads improve Go/Python ready-load medians by 11.9/12.8 percent in
the first run. JSON ready-load median rises 44.5 microseconds and p95 rises
714.167 microseconds, with all eight observations in one block slower. Its
cause is unproved. One separately sealed repeat retains the same five blocks
of eight observations for every artifact and backend: all 38 commands and 240
observations complete with unchanged inputs. Go/Python ready medians improve
12.4 percent again. JSON median/p95 instead improve 3.4/2.9 percent. The original
five JSON component/tail flags remain recorded; no observations are excluded,
replaced, or pooled, and no universal tail-latency claim follows.

These two load changes, recovery scratch, and the artifact-banner/macOS-path
correctness fixes are integrated in candidate F. Its fresh full compatibility
qualification passes all 12 gates, including 347 default Rust tests, 14 explicit
witnesses, 93 helper tests, the binding contracts, and the complete consumer's
6,216 Go and 102,906 Python sources. The report is
`.local/rust-migration/native-phase6/qualification-F/report.json`, SHA-256
`673f79fbfe1207173bbdbde66f95019e175e58b15715841e035c6aceac92f4a6`.
F retains E's artifact bytes for all 12 profiles across two fresh mints.
The prior E qualification and trial measurements remain historical evidence
for their exact bytes. No consumer or release default changes with F.

The two-run review is
`.local/rust-migration/native-phase6/trials/load-comparison/review-two-runs.json`,
SHA-256 `3cc24f264d87088185991dab722a8770176504980a9c75c17c5d819170f9b0e0`.
It retains both complete runs, all 52 metric rows, and all 35 statistic-level
benefit/regression flags.

## Combined F observed-host measurement

The actual combined F CLI `35f20e5cece02ef1` and matching library completed a
fresh matrix against the same frozen Zig bytes. The user explicitly directed
execution despite background work. Host records retain observed CPU activity
and battery power; this run is labeled `contended_host_diagnostic`, with
`exclusive_window: false`. It describes these observed conditions and does not
establish an idle-host baseline or target-platform cutover budgets.

All 1,546 commands completed in 299.779 seconds with stable inputs: 60 untimed
admissions, 540 ABI worker processes, and 946 CLI executions. The original
1,486 scheduled commands, observation counts, seeded order, input cases, and
measurement boundaries remain unchanged. Six additional admissions compare
each artifact inspector with its own source-mint metadata before timing.
Twenty-nine pure controls cover the harness and closed report parser; seven
read-only checks also replay retained report formats. Every raw sample remains
included. Trial ratios and earlier runs are not pooled into these results.

The first F attempt remains failed at 597 commands because the harness compared
Zig source-mint and inspection reports byte-for-byte, although their documented
presentation and internal timing lines differ. Its logs and original inputs
remain retained without a partial summary. The corrected validator checks every
stable metadata byte and only the documented mode-specific fields and numeric
timing syntax. Rust reports remain byte-exact. The intermediate v2 was prepared
and reviewed but never executed; v3 carries the explicit host-scope override.

Cold CLI times below include startup, native artifact loading, parsing, and
exit. Each cell has 40 fresh-process observations; p95 is empirical nearest-rank.

| Case | Zig median ms | Rust median ms | Rust/Zig median | Zig p95 ms | Rust p95 ms |
|---|---:|---:|---:|---:|---:|
| JSON ledger | 2.536 | 4.835 | 1.91 | 2.690 | 5.414 |
| JSON 128 KiB | 6.707 | 49.890 | 7.44 | 7.119 | 52.795 |
| Go ledger | 3.804 | 41.802 | 10.99 | 4.050 | 43.788 |
| Python ledger | 4.274 | 50.610 | 11.84 | 4.647 | 52.426 |

| Cold CLI peak RSS | Zig median MB | Rust median MB | Rust/Zig median |
|---|---:|---:|---:|
| JSON ledger | 3.383 | 4.620 | 1.37 |
| JSON 128 KiB | 10.428 | 20.267 | 1.94 |
| Go ledger | 8.159 | 29.131 | 3.57 |
| Python ledger | 10.355 | 33.653 | 3.25 |

Go compile/mint medians are 386.752 ms for Rust and 46.548 ms for Zig;
Python is 688.118 versus 71.445 ms. Go inspection is 51.787 versus 2.815 ms;
Python is 61.855 versus 3.077 ms. Startup alone is 2.242 versus 2.545 ms.
F's artifact bytes remain identical to E: JSON 8,486 bytes, Go 2,788,154,
and Python 3,371,750. Their Rust/Zig size ratios remain 0.77, 18.93, and 13.82.

The full summary retains all 180 metric rows, including each edit position,
policy, operation, load component, and 1/2/4-worker throughput comparison.
There are 265 statistic-level review triggers across 154 groups. The Zig ABI
library remains an observed-byte diagnostic baseline. Worker RSS includes the
Python process and fingerprint checks; its five observations have no p95.
No concurrency speedup or engine-only memory estimate is inferred from it.

The final raw report is
`.local/rust-migration/native-phase6/performance-F-v3/final-f-vs-zig-1/raw.json`,
SHA-256 `f2da0f9f3028f0c860064bcb3c38f5cd7396749902e0501038f3b684fb1c1e11`;
the summary SHA-256 is
`8e5a955fad6b305e9b8266b72343d474dbf5c24c495fd3d9684d765ffa34aa7f`.
Root independently rehashed all 3,092 command logs and input/artifact/clearance
joins, then recomputed all scope-keyed rows, flags, and artifact comparisons.
These costs still require substantial work before cutover; no blanket tradeoff
acceptance follows from compatibility success.

## Sheng decision and remaining gates

The exact-native Sheng trial preserves 1,420 subject/pattern/polarity
comparisons and 568 scalar/SIMD checks. All five ordinary work gates decline
the proposed rejection work. A sound advisory adapter still performs the
exact IRGX call and saves no calls. A lab shortcut demonstrates why suppressing
that call can hide observable resource failures. Sheng is not enabled in the
product on this evidence. The base Rust 1.85 floor remains intact.

The predeclared Rust/Zig ratio above 1.10 requests review; it does not itself
approve a tradeoff. The original E baseline has 265 statistic-level review flags
across
154 metric groups, not 265 independent regressions. No blanket acceptance of
the measured regressions has been recorded. F costs have been measured and the
fresh installed packages pass on the current Mac and emulated Ubuntu. Native
target-platform execution, meeting the selected budgets, and the late sealed
aggregate gate
remain required before the [cutover](CUTOVER.md). Any further runtime candidate
requires its own
fresh consumer qualification.

The original E baseline's machine-readable findings are
`.local/rust-migration/native-phase6/performance/findings.json`, SHA-256
`82ab1f64997591568155347ff610c23ae9b0326ceef7446702b3887ec2b017ea`.
Its raw execution report has status `executed` and `stable: true`, SHA-256
`cb73f635ce1eda58a9c1924fd7abcaae82526d442bd96b12defd8566be0eac72`.
The retained v2 CLI verdict validation is also required when reviewing it.

The user has now selected a cutover budget of key latency and peak process
memory costs within 10 percent of Zig. This is an acceptance ceiling, separate
from the earlier 10-percent review trigger; candidate F has not met it. Continue
with profiled, independently checked changes and fresh qualification for any
selected combined candidate. Existing Zig ABI cost rows remain diagnostic
until their library has matching source attestation.

Four additional five-second samples of the exact combined F library preserve
full strict tree images before and after sampling. Go and Python loading
repeatedly enter Munch compilation; Python construction repeatedly enters
canonical LR construction and closure. JSON scanning includes lexer, admission,
and parser advancement work. The counts are inclusive and nonadditive; they
are attribution evidence, not latency percentages or projected savings. The
retained report is
`.local/rust-migration/native-phase6/performance-F-profile/samples-1/report.json`
(SHA-256
`6bc9d307ebd378220497778eb5b7b57d98a5dfcea08e98b3f44e5d9092ce1726`).
The private context-refinement trial was declined after two of its four focused
controls failed: a disjoint required empty token at EOF and a disjoint long
handle both parsed canonically but were refused by the refined table. The other
two controls passed. No broad suite or performance run followed, and no runtime
change was selected. The retained decision is
`.local/rust-migration/native-phase6/trials/priority-refinement-F/root-decision.json`.
The SHA-256 dependency trial selects exact `sha2` 0.11.0 with default features
disabled for the next qualified candidate. Both Rust 1.85 and 1.96 pass 349
default tests on the current ARM Mac and emulated Ubuntu x86-64. All 31 working
artifacts retain F's exact bytes. The same-native, same-policy comparison
completes 924 commands with stable inputs, including 40 fresh processes per
measured cell. Go/Python inspection medians improve 23.7/23.4 percent;
cold-parse medians improve 9.7/10.3 percent. Peak RSS is substantially unchanged.
No measured trial/control median or p95 regresses by more than 10 percent.
These are contended-host diagnostics. The dependency is included in the private
combined candidate qualified below; public runtime adoption remains open.

The trial still takes 9.05/9.66 times Zig's cold-parse median for Go/Python,
with 3.56/3.25 times peak RSS. It does not meet the selected budget. The raw
report is `.local/rust-migration/native-phase6/trials/sha2-hardware-F/costs/run-1/raw.json`
(SHA-256 `333fa11eb3e165f0f9cf2eed38c51b2acc77ee6280b0bf5454a22279dedf8bce`);
the component decision is `trials/sha2-hardware-F/root-decision.json` under the
same phase-6 directory. Production hashing policy, parser tables, wire bytes
and native sources are unchanged by this trial.

A separate authored baseline check now exposes two correctness questions in F.
For `doc = u H Z | v H`, `H = q r`, `Z = token(a*)`, both F and Zig refuse
`uqr` at EOF despite the required empty Z. For a 260-symbol H followed by `d+`
in one branch and `dd` in another, F refuses the valid first branch after
choosing `dd`; Zig accepts it. The corresponding eight-symbol control passes
both implementations. All 22 observation commands and their inputs are stable.
The separate test-only adaptive/canonical diagnostic confirms both causes.
The required Z has a successful five-work permission proof, but the raw donated
End bypasses it. The long H exhausts both d/dd proofs at 256 work; donated dd
wins lexing and fails after the real reduction reaches the u branch. Canonical
parsing keeps the callers separate and strictly accepts all seven valid inputs;
the invalid suffix remains refused. The eight-symbol control proves dd
impossible in 11 work. All three diagnostic commands pass with stable inputs.
A private correction now passes all-target checks and 355 default tests
(16 ignored) on both Rust 1.85 and 1.96. Its first full run exposed three
existing cache regressions; retained diagnostics showed cache recording was
disabled before End actually accepted. The corrected run preserves those
assertions and passes all six cache tests plus eight new semantic tests.
This establishes private correctness evidence, with no new performance result.
The private combined candidate includes the selected SHA update and passes 357
default tests on each toolchain, Clippy, a fresh release build, 31 exact artifact
round trips, and all 14 working witnesses. Fresh local qualification covers
55 classified CLI cases, C/Python/Rust ABI consumers and the full governed
6,216 Go / 102,906 Python populations; all 110,014 source hashes are stable.
The ABI evidence retains the first failed attempt and the separate corrected
archive-normalization run. No combined performance measurements have run. These
authored cases do not diagnose the sealed gate. The retained trace is
`.local/rust-migration/native-phase6/baseline-admission-review/diagnostic/run-1/`.
The corrected full report is
`.local/rust-migration/native-phase6/trials/contextual-viability-F/cache-preserving-full-1/report.json`
(SHA-256 `f0cb54d1751ca3bf7f66a32cfde6cd702bf2a904a556c165c40c16e32b336821`).

The next private optimization persists validated native lexer machines to avoid
repeating determinization during artifact loading. Its native prototype passes
78 focused Munch/Image1 controls and five ABI controls, plus two compile-only C
layout targets. Safe Rust pooling passes 13 focused controls on each of Rust
1.85 and 1.96; native108 archive isolation passes its complete byte proof.
The actual working Go/Python tier probe passes on Rust 1.96: 191 patterns and
963 native-question controls agree after loading and after source-first clone
drops. Both image pairs are byte-canonical; shared save/load/re-save budgets fit
unchanged caps. Private artifact integration now passes its focused controls
on both compilers, including shared-budget and full-tree round trips. The full
default workspace gate now passes 371 tests with 16 declared ignores on both
compilers, both all-targets checks, Clippy with warnings denied, and the release
build. All 31 working grammars also pass new V3/S4 canonical mint/repack checks
and exact metadata comparisons across 124 CLI calls. All 14 fresh working
witnesses pass, including 66 specimens and 28 ambiguity comparisons. The
55-case CLI replay also passes with 38 strict parses, 16 matching partial
parses and the one independently invalid profile refused. All 24 ABI commands
now pass, including Rust 1.85/1.96 with and without LTO. The governed consumer
passes 64 default tests (four declared ignores), all 6,216 Go inputs and all
102,906 Python inputs. Its final integrity writer verifies all 110,014 source
hashes. The current private compatibility join is
`.local/rust-migration/native-phase6/trials/checked-munch-image/qualification-1/report.json`
(SHA-256 `0c760df6ec8a6a85ed4d1f5f05cca7224222947879549f6e96a4418c96007bce`).

## Private Image1 full cost matrix

The fresh complete matrix ran once on 2026-10-20. All 1,546 commands exited
successfully without timeout: 60 admission commands and the unchanged 1,486
scheduled commands, including 66 warmups. All 26,245 pinned inputs stayed
unchanged. The Rust CLI is `af2ebb5083c13835`, its library is
`a129009d5306d52e`, and the frozen Zig CLI remains `709bf8c0ce4a3c9a`.
The exact binding, command records and observations are retained under
`.local/rust-migration/native-phase6/trials/checked-munch-image/costs-3/`.
Raw SHA-256 is
`9e20595f4deb8fbc5fa6225c7a2eb2d1c8e9f7047b2a5c35b61c89379349698a`;
summary SHA-256 is
`46b9ba889a0bf8fd13f8c86b21e8d3792063c0143b4743f1cf834c4cb7b7c4e8`.

The user explicitly authorized concurrent host work. All of this migration's
build, test and corpus jobs finished before timing, but the run has no exclusive
host window. These are diagnostic costs under the recorded conditions; they
do not establish a target-platform performance floor. Each latency series
retains 40 observations. ABI series use five blocks of eight observations and
five whole-worker RSS observations; no ABI RSS p95 is estimated. CLI series
retain 40 process RSS observations. The original frozen cases, policies,
2/50/98-percent edits and 1/2/4-worker schedule were retained without pooling.

Cold CLI parse includes startup, artifact loading, parsing and exit. Times are
milliseconds, memory is decimal megabytes, and ratios use unrounded values.

| Case | Zig median ms | Rust median ms | Median ratio | p95 ratio | Zig RSS MB | Rust RSS MB | RSS ratio |
|---|---:|---:|---:|---:|---:|---:|---:|
| JSON ledger | 2.942 | 4.143 | 1.41 | 1.37 | 3.375 | 4.260 | 1.26 |
| JSON 128 KiB | 7.119 | 54.377 | 7.64 | 7.20 | 10.420 | 19.268 | 1.85 |
| Go ledger | 4.315 | 21.027 | 4.87 | 4.48 | 8.159 | 29.360 | 3.60 |
| Python ledger | 4.729 | 25.580 | 5.41 | 5.20 | 10.355 | 34.324 | 3.31 |

The agreed ceiling is 1.10. All four cold-parse cases exceed it in median,
p95 and median RSS. Rust startup alone is within the ceiling (0.89 median,
0.98 p95), which does not establish full-parser parity. Other material costs
remain: Go/Python compile-and-mint medians are 7.79/9.28 times Zig, and artifact
inspection medians are 7.99/8.48 times Zig. Diagnostic ABI ready-load medians
are 14.51/13.06 times the observed Zig library. The library comparison retains
its existing provenance limitation and includes the common Python boundary.
Edits and document throughput retain their individual results in the summary;
neither favorable substeps nor worker RSS ratios waive the cold-parse misses.

Persisting lexer images also increases artifact storage: JSON is 161,950 bytes
(14.67 times Zig), Go is 4,008,638 (27.21 times), and Python is 4,649,374
(19.05 times). These storage ratios trigger review; they are not RSS ratios.
The fresh within-run Rust/Zig comparisons stand on their own. Historical
component trial ratios are not multiplied into an estimated combined result.

The candidate remains private and phase 6 remains open. Immutable table columns
are the next proposed way to reduce retained maps and per-cell allocations.
Their conversion cost, allocation peak, ordered lookups and error/work-budget
semantics require controls and measurements. The proposal establishes no
performance saving. Physical Linux/macOS floor execution, the late sealed
aggregate and rollback/release qualification remain separate gates.

## Fresh public candidate full cost matrix

The 2026-10-21 combined public-workspace candidate is bound to fresh workspace,
working compatibility, governed consumer, source export and installed Mac
package evidence. Its candidate identity is
`8cb7ab23d553ed392dd0c9d0e8b07d3d376055fa80a5b4c495aa335b302f2c55`;
the exact aggregate is
`.local/rust-migration/native-phase6/execution-2026-10-21/final-candidate-evidence.json`
(SHA-256 `b54177dd5b2fcf21d28f0c51f6a65baf218bffdc826bb23ce832e3314f22e972`).
The measured CLI and shared library come from the verified extracted
`installed-macos-2` package, with SHA-256
`de105b74d8bd1c3ba432f5e7007c3f2ef89622d35cf9b04db278082159ce55e1`
and `7053741d7602943c0e90fbde16be01d0454ccac0d48c06ae3408890db8f04e10`.
The library is the recorded relocatable/signed deployment derivative of the
qualified release output. Source export 2 and its package remain immutable.

The new matrix retained the frozen cases, exact schedule, limits, policies,
2/50/98-percent edits, 1/2/4 workers, three CLI warmups and 40 latency
observations per backend. All 1,546 commands completed successfully without
timeout: 60 complete-tree admission commands and 1,486 scheduled commands,
including 66 warmups. All 125,214 pinned files and declared absences remained
stable. Each backend minted its own deterministic artifacts; complete strict
trees, fields, spans and selected edited images agreed before timing. Each
timed ABI parse/edit also checks strictness and node count, with full images at
block edges. There was no duplicate timing run. The first launcher refusal
concerned the clearance JSON shape and occurred before any native invocation;
its receipt and both clearance records remain retained.

This is a current-host, contended-host diagnostic on macOS arm64. This
migration's native, corpus and package jobs were stopped or finished before
timing; unrelated user/system activity was uncontrolled. Filesystem caches
were ordinary warm caches. Five ABI blocks supply 40 latency observations
and five whole-worker RSS observations; no ABI RSS p95 is estimated. CLI RSS
has 40 fresh-process observations. The frozen Zig CLI is source-attested;
the co-installed Zig library retains only observed-byte provenance, so ABI
comparisons remain diagnostic. ABI parse-call and edit-call timers include the
Python/ctypes call boundary and exclude subsequent strictness, node-count,
image and cost validation. Throughput batch timers include their validation;
whole-worker RSS includes Python and validation storage.
No physical platform floor or cutover qualification follows from these costs.

Cold CLI parse includes startup, loading the backend's own artifact, parsing
and exit. Times are milliseconds and RSS is decimal megabytes; ratios use
unrounded observations.

| Case | Zig median ms | Rust median ms | Median ratio | Zig p95 ms | Rust p95 ms | p95 ratio | Zig median RSS MB | Rust median RSS MB | RSS ratio | RSS p95 ratio |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| JSON ledger | 3.533 | 4.563 | 1.292 | 4.499 | 11.180 | 2.485 | 3.391 | 4.080 | 1.203 | 1.207 |
| JSON 128 KiB | 8.141 | 37.893 | 4.655 | 9.420 | 51.042 | 5.419 | 10.420 | 19.726 | 1.893 | 1.812 |
| Go ledger | 5.162 | 14.615 | 2.831 | 6.597 | 17.202 | 2.608 | 8.159 | 16.957 | 2.078 | 2.302 |
| Python ledger | 5.565 | 17.013 | 3.057 | 7.040 | 20.305 | 2.884 | 10.355 | 18.678 | 1.804 | 1.906 |

The full cost gate still fails the unchanged 1.10 ceiling. All four cold-parse
cases exceed it in latency median/p95 and process RSS median/p95. Across the
180 latency/RSS comparisons, 151 medians and 117 available p95s exceed 1.10;
with three artifact-storage comparisons, these give 271 review triggers. The
explicit acceptance ceiling concerns latency and RSS; artifact-size rows are
separate diagnostic review triggers. The manifest's review-trigger terminology
grants no budget waiver. Startup median is 1.012 times Zig, while startup p95
is 1.167 times. Go/Python compile-and-mint
medians are 8.508/9.899 times Zig; artifact-inspection medians are 5.477/5.608.
Diagnostic ABI ready-load medians for JSON/Go/Python are
4.518/8.633/7.819 times the observed Zig library, and ABI parse-call medians for
JSON/large JSON/Go/Python are 8.517/8.212/15.020/19.753 times.

Holding the measured Zig observations fixed, the remaining cold-latency gap is
the reduction from current Rust to 1.10 times Zig. These are arithmetic targets,
not predicted optimization gains or stable limits on a future host run.

| Case | Required Rust median ms | Median reduction needed | Required Rust p95 ms | p95 reduction needed |
|---|---:|---:|---:|---:|
| JSON ledger | 3.886 | 14.84% | 4.949 | 55.73% |
| JSON 128 KiB | 8.955 | 76.37% | 10.362 | 79.70% |
| Go ledger | 5.678 | 61.15% | 7.256 | 57.82% |
| Python ledger | 6.122 | 64.02% | 7.744 | 61.86% |

All 48 edit-latency comparisons exceed the ceiling in median and p95. The
late large-JSON whole-policy insertion takes 61.007 ms versus 0.107 ms in
median (572.616 times); exact edited images still agree. Every throughput
latency comparison exceeds the ceiling. Large-JSON time per document is
7.181/18.848/38.617 times Zig with 1/2/4 workers. These observations leave
incremental total cost and worker scaling as material open work. Favorable
worker RSS or navigation substeps do not waive the failed full cost gate.

Both C adapters map `prove=0` and `whole=2`, matching the frozen schedule and
public header. The header defines Whole as re-deriving everything past the
edit. Rust currently takes a full-file cold path and rebuilds its measured
sequence, while Zig retains prefix resume and subtree reuse under that same
policy. In all 40 late large-JSON Whole insertion samples, Rust reports
`stood=0`, 81,262 reads, 49,132 minted leaves and no kept leaves; Zig reports
`stood=129076..129096`, 24..34 reads, 17 minted leaves, 48,145 kept leaves and
seven subtree lifts. Both return 67,493 reachable nodes, strict results and
matching sampled full images. The 572.616 ratio therefore measures this
concrete reuse-strategy gap. The Zig source contract matches frozen authority
hashes, but the measured ABI library still lacks a source-to-library
attestation; its retained cost counters corroborate the reuse observation.

Artifact sizes are JSON 161,950 bytes (14.669 times Zig), Go 4,008,638
(27.210 times) and Python 4,649,374 (19.054 times). Storage ratios are separate
from RSS. The fresh within-run Rust/Zig comparisons stand on their own;
historical component or Image1 ratios are not multiplied into these results,
and the combined run attributes no speedup to a particular source change.

The complete manifest, clearance, command outputs and observations are under
`.local/rust-migration/native-phase6/execution-2026-10-21/performance/full-matrix/`.
Manifest SHA-256 is
`7b881aedf72728a1a9a2096283a8c37591fafe318bc6959b9f9d7de94a871d2b`.
The executed/stable `run-1/raw.json` has SHA-256
`45a2799070b5cf767c46833b5ccdb17d3625cc43be66f94c3509f6349f1f558f`;
`run-1/summary.json` has SHA-256
`f61a45ed9c941c9ed9f6a40014d0e90ef5bc3640a7a0ec2adf3a940e4ac5d71b`.

After the stable failing matrix, one cleared three-second own-process
large-JSON CPU sample used that exact installed library and freshly minted
matrix artifact. Complete trees and the full input closure agree before and
after. Its receipt is
`.local/rust-migration/native-phase6/execution-2026-10-21/performance/profile-final-1/report.json`
(SHA-256 `960c482aeafd7ab0f24b535add2af5427b943880693ae26918778a6a63c73882`);
`sample.txt` has SHA-256
`035067375ff4e7eb3b8404a0eed97c25de04de0eac0e17091bfa2ca6f0bd1cbc`.
Among 2,310 main-thread observations, collapsed top-of-stack counts include
memmove 282, lexer scan 224, parser advance 172, admission-slate construction
154, error drop glue 126, action lookup 104, transition lookup 95, tiny malloc
91 and free 87. The advancement path still moves owned heads and grows
containers; slate insertion also retains allocation/drop churn and proof work.
These qualitative counts overlap with inclusive paths and predict no savings.
The sample process retains large Python custody maps, so its footprint is not
a Rust-only heap measurement. This one parse/drop sample does not explain the
full excess in compile, load, edit or parallel-document costs.

The next investigations should measure ownership transfers of large parser
heads, remaining frame/slate allocations and repeated admission proofs,
ordered table lookup and artifact decode/validation costs, and the total work
of edits and independent workers. Each proposed change still needs exact
semantic/work-limit controls and fresh qualification plus measurement. The
cost, physical-host-floor, sealed, release and default gates remain distinct.
