# Rust migration performance review

Phase 6 remains open. The current public-workspace Rust candidate passes its
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
approve a tradeoff. The original E baseline has 265 statistic-level review flags across
154 metric groups, not 265 independent regressions. No blanket acceptance of
the measured regressions has been recorded. F costs have been measured and the
fresh installed packages pass on the current Mac and emulated Ubuntu. Native
target-platform execution, meeting the selected budgets, and the late sealed aggregate gate
remain required before the [cutover](CUTOVER.md). Any further runtime candidate requires its own
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
retained report is `.local/rust-migration/native-phase6/performance-F-profile/samples-1/report.json` (SHA-256
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
