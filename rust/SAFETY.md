# Rust runtime memory and ownership contracts

The engine forbids unsafe Rust. Its native regex dependency and the C adapter
have separate unsafe boundaries; safe engine code is not a proof about either
boundary or about arbitrary C callers. Qualification must identify the exact
sources, native archive, compiler, SDK, binaries, commands, and observations.
Historical passes do not qualify a changed checkout.

## Ownership and publication

Compiled grammars own their decoded tables, scanner programs, and lexical
slates. Caller artifact buffers may be changed or released after loading.
`Bank::open` transfers its owned file buffer into immutable backing storage;
borrowed loading copies before retaining a lazy member. Verification is tied
to that backing and its checked range. A failed lazy decode remains retryable.
Once every member is decoded, the bank releases its encoded backing.

Parser sessions own mutable scratch. Trees retain their grammar and immutable
source through `Arc`; nodes borrow one particular tree and resolve checked
arena positions. Alias, parent, field, child-range, and source-offset narrowing
uses checked conversions. Speculative branches share immutable draft nodes and
keep alias and field choices at their individual use sites.

Published node IDs follow a complete source-ordered preorder traversal. Each
sibling run is strictly increasing, including empty spans, and every subtree
occupies one contiguous ID interval. Wide sibling lookup can therefore use a
direct step between adjacent leaves, falling back to checked binary search
when a subtree intervenes. Subtree size can follow the final child chain without
allocating a traversal stack. Nodes continue to borrow their owning snapshot;
these shortcuts add no indexes, unsafe access, or retained storage. Independent
linear navigation and explicit descendant walks check the results on complete
trees and partial forests.

Structural validation first checks ordered root/child runs, exact parent links,
parent-before-child IDs, spans, and the total edge count. Unique incoming edges,
acyclic parents and one edge per node prove complete reachability without a
visited bitmap or width-sized frontier. A failed proof uses the original full
walk, preserving its exact diagnostic counters for malformed storage. Query
execution also uses the materializer's preorder arena directly; result capture
vectors are allocated once while retaining match order and work debits.

Advancement borrows an immutable automaton from an operation-owned `Arc`.
The borrow never escapes the operation. Singleton stack bodies keep their
use inline; persistent draft children remain independently owned vectors.

Document edits publish source, tree, measured sequence, and cost only after the
operation completes. A refusal preserves the prior published version and any
retained snapshots. Private scratch may change during a failed attempt. The
document removes unpublished effects before reusing their private indexes.
Queries retain their owners and use the C adapter's read guards
to exclude mutation while result views are live.

The C adapter checks handle kind, identity, owner, and lifecycle through its
registry before resolving an opaque token. Byte APIs reject oversized lengths
and address-plus-length wrap before constructing a Rust slice. C callers still
must supply an actual valid allocation, sufficient initialized readable bytes,
and the lifetime and concurrency required by the header. Arithmetic checks
cannot establish those caller obligations.

## Reuse and resource bounds

Permission memoization records every state-stack dependency reached across all
explored recovery branches. Floor-dependent proofs require the full stack;
other proofs require the complete observed suffix. Permission reuse never
reuses a lexical answer. Every source/scanner question still has its own proof.
The directory and retained permission payload together are capped at 1 MiB.

Action indexes use packed descriptors while their side ranges remain economical.
An index outside the packed domain or excessive side storage promotes once to
the original wide ranges, preserving the full supported index domain. Packed
heap capacities stay within the old wide capacity plus a fixed 64-byte prefix;
the construction and frozen enum headers add 24 and 16 bytes respectively on
the measured 64-bit layouts. Promotion temporarily owns both representations.
Allocator pages and process RSS require separate measurements.

Native image decoding copies little-endian words into aligned owned arrays.
Its fast path prepays the complete copy; insufficient work uses the scalar
path with the original partial-debit behavior. Reachability validation checks
every wire edge before indexing, deduplicates predecessor storage, and computes
the match-seeded least fixed point. Cycles cannot certify their own acceptance.

Document prefix reuse requires byte equality through the edit. A pure regex
event may use a conservative bound covering every actual native source read,
including speculative and failed extra scans. The bound must be strictly before
the edit and strictly inside the old source. Unknown bounds and stateful scanner
events use conservative checkpoint fallback or complete replay. Token ends alone
are insufficient evidence. Checkpoints cover the file within a fixed count.

At publication, the 32 MiB prefix-cache limit counts retained
event/receipt/checkpoint capacities, owned scanner metadata, and retained drafts.
Metadata growth is checked before allocation and reconciled with actual capacity.
Draft construction remains subject to the operation's node/work limits before
the final combined cache check. Overflow or insufficient cache space disables
advisory reuse. This limit excludes sources, snapshots, move traces,
effect stores, allocator overhead, and temporary relocation peaks. It is not a
process RSS ceiling. Repeated open/drop measurements are necessary: an allocator
can retain freed pages even when the live cache becomes smaller.

Successful immutable effect operations may use a store-local memo. Grammar
domains and both operands' complete owner/index identities are checked before
lookup; errors are never cached. The first 32 successful eligible misses retain
only the memo header. The next may allocate 64 slots. Growth doubles that count
up to 8,192 slots; each lookup and placement has at most eight probes. A bounded
rehash publishes only if every old entry and the new entry fit, with no eviction.
Entries retain full 32-bit keys and tagged Zero/Run answers, without extra run
owners or lexical/source answers. Accepted old-plus-new vector capacities and
their headers must fit 256 KiB before publication. Initial allocation failure
disables optional acceleration; failed growth keeps the old table and disables
further growth. Rejected allocator overdelivery remains outside that transient
bound. This is not a per-document RSS guarantee. Cache probes and rehashes do
not change the existing abstract parser work units.

Effect composition checks both handles before memoization and borrows its
immutable input runs while proving compatibility. Incompatible floor sets
return Zero before copying interior ledger claims. Surviving claims retain the
same order, guards, interning, and publication rules; this removes temporary
copies without changing effect identities or resource accounting.

Full selected-trace products may prove a concrete stack from the grammar's
start state before interning a single final grounded run. Stored LR links,
exact reduction RHS symbols/floors and every appended transition establish the
same guards as primitive folding. Empty traces remain Identity. Holes or any
failed proof use the original fold with an untouched store, including validation
after absorbing Zero. The optimized path retains fewer intermediate runs and
does not reproduce their opaque allocation order or memo warmup. Final runs
still obey the original interner capacity. Bounded move-range products retain
their existing general guarded fold and work accounting.

Public effect stores retain every distinct interned effect until the store is
dropped, because callers may have copied their handles. A document owns a private
store and exposes descriptions rather than handles. It marks the store before
an edit and drops every candidate segment and sequence before removing the new
interner suffix on failure. Cleanup preserves the owner and all earlier indexes,
and clears both memo keys and values before any suffix index can be reused.
It allocates no new production storage and does not relax the original refusal.
Memo capacity, warm-up state and allocation-failure disable flags are preserved.
Reclamation adds cleanup work for the newly created suffix; the existing
abstract parser counters do not include that cleanup or allocator costs.

The fixed-limit JSON, Go and Python refusal census found accumulation in the
previous implementation. With rollback, none of its 204 measurement-time refusals
retains new runs. The retained versions, full trees, products, cost counters and
old sequence effects remain valid. Portable regressions also cover immediate
payload release, stale memo keys and answers after index reuse, and a successful
edit after refusal. Evidence is under `failed-measurement-retention/` in the
performance directory; fresh combined and sanitizer qualification is separate.

Collection capacities and allocator retention can remain at a prior high-water
mark after cleanup. Successful edits still grow the private interner, and
operation limits do not bound its lifetime growth. Retaining many independent
snapshots also retains their respective owned storage. Rust metadata allocation
is not universally fallible; allocation failure may abort the process.

Native lexer workers use the binding's exclusive pool leases. Immutable native
program sharing and cloning have their own checked ownership rules. Each
worker's mutable buffers are separate. The core does not infer native exclusive
access from a reference count or bypass the binding's synchronization.
An unrestricted fresh lexical question, or a filtered permission list proved to
contain every tier ordinal, can use the binding's all-admitted representation.
The native machine, transition meter, winner checks and empty-token rules are
unchanged. Differential controls cover mask-word boundaries, tied winners,
invalid input offsets, binary inputs and exhausted budgets.

Filtered native permission ordinals may additionally use a worker-local cache
for larger lexer tiers. Its 64 slots use four-way buckets and exact admitted
IDs, freshness, tier and lexer identity; hashes alone never establish a hit.
A weak identity prevents allocation-address reuse without changing the native
worker's strong-owner hint. Directory and retained key/ordinal vector capacities
fit 64 KiB; optional allocation failure falls back to recomputation. This bound
excludes the cache header, allocator overhead and rejected allocator overdelivery.
No source, scanner result or transition answer is retained, and native scans,
winner checks and work debits remain unchanged.

The scanner-book artifact seal is computed once per process from the complete
ordered embedded sources. This immutable identity cache skips no artifact
envelope hash, native image check or source/roster validation.

## Validation

The default workspace tests and strict Clippy checks run on both Rust 1.85 and
the selected current compiler. All-target/all-feature checks include the C
adapter. The separate working gates exercise all 31 grammars, explicit scanner
and ambiguity witnesses, complete tree images, CLI behavior, native ownership,
and the full Go/Python consumer inventories.

[`safety_contract.rs`](tests/safety_contract.rs) exercises resealed malformed
artifacts, independent lazy-load lifetimes, and malformed query compilation.
The ABI suite covers malformed and binary edit streams, stale owners, failed
publication, oversized foreign lengths, retained views, and query guards.
Cache controls compare independent cold results and complete replay, including
the exact 131,751-byte benchmark input, successive edits, EOF sensitivity,
failed rule extras, provisional empty tokens, and bounded-cache refusal.

AddressSanitizer runs instrument the Rust engine and adapter and verify that the
test binaries contain sanitizer instrumentation. The prebuilt standard library
and Zig/C native archive are outside that instrumentation; the retained ASan
recipe disables leak detection. Native image and
ownership tests additionally run with Zig `ReleaseSafe`. Guarded allocator and
repeated lifecycle runs supplement these checks. Passing these tests supplies
evidence for the exercised inputs and lifecycles, not a guarantee that all
possible bugs or data races are absent. Miri cannot execute the native FFI path.

The selected Q7 source, including failed-edit suffix rollback, passes 443 ASan
tests with 17 declared ignores; instrumentation is verified in 33 test binaries.
The receipt is
`.local/rust-migration/perf-safety-2026-10-21/selected-final-attempt-6/receipt.json`.
The current-source join to Q7's three release outputs and the unchanged native
replay rechecks 23,882 file and absence pins. It is retained as
`selected-final-attempt-6-q7-join.json` in the same directory.
A separate deliberate heap-overflow control is detected by the same compiler's
ASan runtime. A leak-detector capability probe times out even on its clean
control, so it supplies no leak-detection qualification.

ThreadSanitizer supplies no engine coverage on this host. The first attempt
refuses the ABI mismatch with prebuilt standard libraries. A separate attempt
successfully rebuilds instrumented standard libraries and standalone controls,
but both the clean and deliberate-race controls exit with SIGSEGV before their
completion or diagnostic markers. All 27,537 captured inputs remain stable;
no engine or adapter TSan tests run. No ABI-check bypass is used. The exact
flags, binaries, logs, and negative receipts are retained in
`selected-thread-sanitizer-1/handoff.json` under the safety directory above.

The native ReleaseSafe controls also pass a focused replay with the complete
expanded build-package inventory captured before execution. Its receipt is
`selected-final-attempt-5-native-dependency-supplement-1/replay-1/receipt.json`
under the same safety directory. The original native run's package inventory
was captured afterward; that run alone does not supply this custody evidence.
Separate release controls exercise 3,270 edited publications, one successful
retry after a refusal, and 288 retained snapshot expirations. These controls
check ownership and publication; they do not measure allocator RSS or prove
bounded lifetime effect-interner growth.

Fresh reports and their source custody determine which of these checks qualify
the final candidate; see [the cutover record](CUTOVER.md) and
[performance evidence](PERFORMANCE.md).
