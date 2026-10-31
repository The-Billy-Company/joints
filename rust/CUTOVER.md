# Rust candidate activation and rollback

The optimization follow-on must qualify its own frozen source and packages
before adoption. Earlier Q7 and predecessor receipts below remain evidence for
their recorded snapshots; later runtime changes do not inherit those passes.
The existing local sequence is `tool/rust_qualify.py`, then
`tool/rust_bundle.py`, followed by `tool/rust_delivery.py export`, `pack`, and
`verify`. These steps create new outputs and check the preceding source and artifact
identities. See [delivery](DELIVERY.md) for the exact
arguments and the native108 selection required by the current source.

The fixed cutover candidate is `c54221b` with native source `bf19d6b`. Its
fresh local workspace qualification and actual-host source CI pass 457 default
tests with 16 ignores on both Rust versions. The same 457/16 roster passes Rust
ASan with instrumentation verified in 33 binaries, and the complete working
replay passes with stable final custody, including all 6,216 Go and 102,906
Python inputs. Completed source CI for tooling `4cecfd8` retains the same
compiled `c54221b`/`bf19d6b` maps; its separate hosted diagnostic reaches 5× in
6/120 groups, compared with 7/120 in the earlier source-CI run. The general
5–10× performance target remains unmet. Fresh Mac and emulated Linux packages
pass all 40 installed checks, with both Linux Rust compilers passing 457/16.
Current qualitative profiles and the full source-attested 1,546-command cost
run complete with stable custody, but the unchanged 1.10 Rust/Zig latency/RSS
ceiling fails. Later tooling `9327b86` has green source-CI jobs and standard CI
by API status, with artifact custody still pending. Actual installed-platform
run `39890987250` passes all 40 checks and 457/16 on both native hosts, with
exact package identities, logs and retained proof custody independently
verified by collector receipt `c59bdfff…debd94`. The single sealed attempt exits
1 with stable pins but incomplete coverage: Rust 16/20 and Zig 19/20 entries,
both `measurement_complete: false`. No complete comparative aggregate is
accepted. Sealed qualification and adoption/release/rollback remain open. The
unwaived failed performance ceiling still blocks cutover; Zig remains the
default. See
[the fixed candidate](PERFORMANCE.md#fixed-cutover-candidate-2026-10-22) for
exact source identities, receipts and the earlier 15 workload ranges. The
older results below qualify their own snapshots only.

The retained Q7 source reclaims unpublished effects after rejected document
edits. It passes 443 default tests on each Rust version, strict checks and the
release build with a stable 564-file source/runtime-fixture closure. The same
source passes 443 ASan tests with instrumentation verified in 33 binaries.
Its complete working replay also passes: all 31 grammars, 14 extended
witnesses, 55 functional checks, 24 ABI checks, and all 6,216 Go and 102,906
Python consumer inputs. Fresh installed checks pass 40/40 on the current Mac
and 40/40 under Linux amd64 emulation, with both Linux compiler versions also
passing 443 default tests and 16 ignores. The complete 1,546-command cost run
finishes with stable inputs but still fails the 1.10 ceiling. Cold median
Rust/Zig latency ratios are 1.208/2.436/2.134/2.312 for JSON/large JSON/Go/Python;
median RSS ratios are 1.080/1.522/1.642/1.531. Edit and worker costs also remain
open. The local compatibility join is
`.local/rust-migration/performance-2026-10-21/final-candidate-evidence-6.json`;
Linux execution is separately recorded under `linux-preflight/run-6/`.
Neither the contended-host cost result nor emulation establishes a physical
target floor. Zig remains the default. See
[the current result](PERFORMANCE.md#current-packaged-q7-result-2026-10-22).
The Q6 results below remain attached to their retained predecessor snapshot.
The latest combined Q6 snapshot passes 440 default tests on each of Rust
1.85 and 1.96, formatting, all-target checks, strict Clippy and a release build.
Its complete 562-file source/runtime-fixture closure repairs the omissions
identified in Q4. Q6 includes the selected adaptive effect memo. The same
selected source passes 440 AddressSanitizer tests with instrumentation verified
in 33 binaries, plus a native ReleaseSafe replay with complete build-package
custody. Native Zig/C and the prebuilt standard library remain outside Rust
ASan; leak detection is disabled. The Q6 development comparison still exceeds
the performance ceiling: cold median Rust/Zig ratios are
1.116/2.607/2.248/2.372 for JSON/large JSON/Go/Python, with RSS ratios
1.063/1.514/1.645/1.535. The full cost matrix was pending at that Q6
checkpoint; the current Q7 result is recorded above.
Its exact workspace report is
`.local/rust-migration/performance-2026-10-21/qualification-6/report.json`.
Performance acceptance, target-floor, sealed, and release gates remain open for this follow-on. Zig
remains the default. See [the intermediate checkpoint](PERFORMANCE.md#intermediate-performance-checkpoint-2026-10-22).

The retained 2026-10-21 candidate below contains Image1 V3/S4 and native108 support, plus
parser/table allocation changes. Its `qualification-3` passes 381 default
tests with 16 declared ignores on each of Rust 1.85 and 1.96, both all-target
checks, formatting, Clippy and a release build. The fresh 31-grammar gate also
passes all 124 CLI calls and preserves the exact prior Image1 artifact bytes.
Fresh local qualification additionally passes the 14 working witnesses,
55 classified CLI cases, 24 ABI commands, all 64 default consumer tests,
6,216 Go inputs and 102,906 Python inputs. The extracted Mac package passes
40 installed commands. Current receipts are under
`.local/rust-migration/native-phase6/execution-2026-10-21/`; the exact local
compatibility join is `final-candidate-evidence.json`, candidate identity
`8cb7ab23d553ed392dd0c9d0e8b07d3d376055fa80a5b4c495aa335b302f2c55`.

That candidate's full 1,546-command cost run completed with stable inputs. The
1.10 latency/RSS acceptance ceiling remains failed: cold CLI median ratios
are 1.292 for JSON, 4.655 for large JSON, 2.831 for Go and 3.057 for Python.
Process RSS and incremental/worker costs also need work. This is a contended
current-host comparison, with separate ABI-baseline provenance limits.
See [the fresh cost review](PERFORMANCE.md#fresh-public-candidate-full-cost-matrix).

The historical F and Image1 results below identify immutable predecessor
candidates. Use the new qualification report and its exact bundle for adoption;
predecessor passes cannot qualify edited sources. No default switch is
authorized by a workspace or installed-package pass alone. Target-floor
execution, the late sealed aggregate, real installed-consumer adoption and
release/rollback qualification remain separate gates. The 10,000-line goal
is separate design debt, with 24,225 production Rust lines counted for that
retained candidate.

The retained late sealed attempt has aggregate projections for both
backends, with 0 of 20 entries measured in each. Pins and control files remain
stable; neither comparative correctness nor a cause follows from those
incomplete measurements. Raw diagnosis remains sealed. The record is
`sealed-gate/attempt-final-1/report.json` under the current execution directory
(SHA-256 `d85856d1aa046855ca04219ef5d185a3e4c59528842159e19b773b3cb72baf44`).
It overlapped the capped Linux correctness build after all timing/profile work
had finished. No sealed or default-cutover pass is claimed.

The same source2 closure also has positive emulated Linux release and installed
functional results: both Rust versions pass the full 381/16 roster and all
40 extracted installed commands pass. A separate byte-only audit completes
custody after the private producer's final path-type error; its original failed
outcome and an earlier audit refusal remain unchanged. See [the complete delivery
record](DELIVERY.md#fresh-public-workspace-native108-candidate). This supplies
no physical Linux, Linux debug, timing or default qualification.

## Retained predecessor evidence

The combined phase 6 candidate F has passed fresh full local compatibility
qualification on macOS arm64. Candidate CLI SHA-256 is
`35f20e5cece02ef136e01d273371ff96111a4282f7496c33f2d3681cb825debf`;
the immutable bundle identity is
`c03b29f397b965c22e69039b65cac24d3df6a76a70ad4f0ea4f120f26744f4f8`.
Its 12-gate report is retained at
`.local/rust-migration/native-phase6/qualification-F/report.json`. The original
assertions pass for all 64 default consumer tests, 6,216 Go files, and 102,906
Python files in the sealed working dataset. This is private source-consumer
qualification; the published-release and target-platform gates remain separate.
Fresh schema-2 installed packages now pass 40 commands each on the current
macOS 26.6 ARM64 host and emulated Ubuntu 24.04 amd64. The complete 1,546-command
F cost run records user-authorized background work and battery power and still
shows substantial regressions. The late sealed worker refused before an accepted
aggregate; no failure diagnosis was read. These results leave phase 6 open:
the selected 10-percent latency/memory ceiling, the sealed gate, and physical target-floor execution must pass
before activation becomes a default cutover.
Two newly authored baseline controls also require a correctness decision:
F refuses a valid long-reduction case accepted by Zig, and both engines refuse
a required empty token at EOF. Test-only traces confirm donated lexical
permissions on these inputs. The private correction passes all-target checks
and 355 default tests (16 ignored) on Rust 1.85 and 1.96. The private combined
candidate with the selected SHA dependency improvement passes 357 default tests
on both toolchains, Clippy, a fresh release build, 31 byte-identical artifacts,
and all 14 working witnesses. Fresh local qualification also covers 55 classified
CLI cases, C/Python/Rust ABI consumers, 64 default consumer tests, 6,216 Go inputs
and all 102,906 Python inputs, with all 110,014 source hashes stable. The ABI
proof uses a separate corrected run with archive-member normalization and
retains its first failed attempt. Combined performance and platform-floor
qualification remain open. This does not change the frozen F qualification or
authorize cutover.
The later private Image1 successor also passes its full local workspace,
artifact, ABI and governed consumer gates. Its new 1,546-command cost run
completed under user-authorized concurrent host work, but all four cold-parse
cases still exceed the 1.10 ceiling in median, p95 and median RSS. Its private
lexer-image format is envelope version 3/table schema 4; the historical F activation used V2/S3. The artifact instructions below now
describe the current workspace format. Image1 native108 packaging,
physical platform floors, the late sealed aggregate and release/rollback
qualification remain open. See [the current cost review](PERFORMANCE.md#private-image1-full-cost-matrix).
The complete 628-file qualification input closure is retained under
`.local/rust-migration/native-phase6/compatibility-F-inputs/`. Later delivery
tooling and documentation have separate checks; the 112 compiled inputs stay
fixed. The prior E qualification and failed predecessors remain retained.

The [migration plan](../RUST_REBUILD_PLAN.md) requires measured performance,
memory, target-platform correctness, installed-package checks, and rollback
before switching defaults. Phase 6 is in progress. The source closure includes
unpublished `irgx` additions and must travel with the candidate or be published
as an explicit dependency first. The current engine/CLI version is `0.0.0`;
the existing C interfaces have their own package version and ABI 2 contract.
Local candidate validation does not mint a release version.

## Activate an isolated candidate

Keep the candidate in its own installation prefix and artifact directory.
Select its exact CLI and matching library explicitly. For example, after
verifying an extracted macOS candidate:

```sh
candidate=/absolute/path/to/verified/candidate
python3 tool/migration.py replay --bundle test/migration/reference \
  --binary "$candidate/bin/joints-rs"
PYTHONPATH=bindings/python JOINTS_LIB="$candidate/lib/libjnt.dylib" \
  python3 -m unittest discover \
  -s bindings/python/tests
JOINTS_LIB_DIR="$candidate/lib" JOINTS_LINK_KIND=static \
  cargo test --manifest-path bindings/rust/Cargo.toml --locked
```

These commands replay the checkout's portable references and binding contracts;
installed-package validation must additionally run outside the checkout.
Use `libjnt.so` for the Python library on Linux. These variables select the
already-built candidate; they do not rebuild the engine. Rust consumers linking
the C static archive need the delivery tool's C boundary archive, validated
with the consuming compiler and LTO policy. Member-name normalization alone
does not isolate bundled runtime symbols. See [DELIVERY.md](DELIVERY.md).
Native Rust clients can depend on the extracted `joints/rust`
workspace directly, with the sibling `irregex` layout and pinned offline
dependency closure intact.

Before adopting a consumer, prepare its reviewed versioned grammar recipes and
apply its exact source projection patch in a separate checkout. The
[consumer migration fixtures](../test/migration/regulator/README.md) retain
the profile and patch lineage. The qualified E and F cohorts use that precise patch;
its original source, assertions, and failed predecessor remain preserved.
Re-run the actual consumer against the installation being adopted. A library
smoke test or grammar generator success cannot replace that workload.

## Transition artifacts as a set

Current native artifacts use envelope version 3 and table schema 4, including
checked native lexer images. Older native
artifacts and legacy Zig folios are refused explicitly. Re-mint from the pinned
grammar JSON and customary book, using the reviewed recipe when applicable:

```sh
"$candidate/bin/joints-rs" mint /absolute/path/to/reviewed-grammar.json \
  -o /absolute/path/to/candidate-artifacts/language.folio
```

Verify newly minted artifacts load without LR construction and that the
installed consumer selects the matching profile identity. Keep the original
Zig folios unchanged alongside them. The same ABI version does not imply the
same artifact encoding. Do not overwrite the legacy artifact directory or
rename a reviewed v2 profile to its invalid v1 identity.

## Restore the incumbent

Stop the candidate workers, restore the pinned Zig executable/library and its
original artifact directory together, and restart the consumer. A statically
linked consumer must restore or rebuild its incumbent executable; changing a
runtime environment variable cannot replace linked native code. Keep engine
handles and snapshots within the process/library that created them.

The retained local Zig reference CLI has SHA-256
`709bf8c0ce4a3c9ad5deb400e42d5025439e76c45bbcfaaf0959be31cff768ec`.
Production rollback must retain its own installed release, matching libraries,
source identity, and folios. The historical local CLI attestation does not
attest the co-installed Zig library bytes; phase 6 labels those ABI measurements
as diagnostics. No consumer default, release workflow, or live Billy checkout
has been switched by this migration.
