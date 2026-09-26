# Yielding handoff preparation and validation

Date: 2026-09-26. Branch: `rescue/change-039-device-failure-2026-09-19`.
Baseline and unchanged HEAD: `e620d8a8d29e5087a4b69176cffdff8665147dbd`.

This extends the production core described in
[nalori-backward-handoff-proof.md](nalori-backward-handoff-proof.md). It does
not close the full UI responsiveness gate. Complete-chapter preparation,
post-handoff reopen, several indivisible operations below, and mounted-screen
integration remain unresolved. P04/P06 remain open; progress stays **46/89**.
No persistence formats, ordinary append requirements or P05 acceptance rules
were changed. No device, commit, push, scrubber or P07 work was performed.
Previous proofs, frozen oracles and diagnostic artifacts are preserved.

## Supported production route

`LazyForwardHandoffCore.beginNextYielding` / `beginPreviousYielding` capture
pinned source evidence privately. The existing `prepare` now uses yielding
stable-body/coverage validation and handoff proof construction. The new
`publishYielding` and `retainYielding` perform sliced validation and projection
before a synchronous publication commit. Both forward and backward preparation
still use the real canonical paginator and existing strict renderer contracts.
The synchronous core/publication entry points remain available for existing
callers and controls; they do not acquire a responsiveness guarantee from
these new entry points. ReaderScreen is not wired here.

Preparation binds the actual immutable source records, pinned card payloads,
resolved layouts, operation owner, accepted publication object/revision and
visible signature. A supplied proposal is recomputed and compared exactly;
its digest alone cannot authorize publication. New canonical cards pin nested
payload lists and image bytes. Stable bodies retain their already-validated
identity/slices, avoiding repeated whole-body JSON decoding for those getters.
Stable serialization and signatures are unchanged.

A pending operation remains working through asynchronous proof construction.
Cancellation prevents publication immediately but retains its roots/reservations
until its future settles. A second operation cannot reuse the core while the
old validation is suspended. Publication rechecks the owner, token, accepted
publication, visible position and budget after preparation, immediately before
the existing synchronous `_commitLazyPublication`. Retirement also rechecks
all live renderer pins. No partial publication is exposed between slices.

## Actual expensive paths

| Production path | Work performed between scheduler checkpoints |
| --- | --- |
| `LazySectionInput.captureYielding` and stable section admission | Canonical section encoding, UTF-8 size counting, immutable record encoding, ownership hashes, section/publication digests. Caller metadata is pinned before suspension. |
| `CanonicalPaginationSourceSnapshot.pinLazyYielding`, join and retirement | Source-owner construction and incremental snapshot/source-revision digests; sharing immutable records rather than copying old section chains. |
| `LazyValidationWork` | Canonical JSON token traversal; strings split at at most 1024 UTF-16 units without dividing surrogate pairs. Encoder/canonical comparator checkpoints after 64 tokens or 2048 emitted units (the final token can exceed that threshold by one bounded token). SHA-256 receives bounded chunks. String hashing/comparison and UTF-8 counting use at most 4096 UTF-16 units; byte hashing uses at most 16384 bytes. |
| `LazyPreparedSection.prepare` | Existing yielding paginator plus per-source/per-slice complete-coverage validation, stable emission, card guards and proof construction. |
| `LazyStableCardEmitter.emitYielding`, `LazyStableCardBody.fromJsonYielding` | Exact accepted-card comparisons, payload/source ownership hashes, envelope digests, identity/slice checks. P05 renderer/font/image checks remain strict. |
| `buildLazySnapshotHandoffYielding` / `buildLazySnapshotPrependYielding` | Authority validation, exact prefix comparison/digest, exact reconstructed stable-body comparison, accepted-publication digest and seam evidence. |
| `LazyRetainedSection.captureYielding` | Strict retained authority validation, suffix-source view and retention/root hashes; no historical object chain. |
| `ProgressiveDisplayState` yielding transactions | Private per-card/per-slice projections followed by authority recheck and atomic field adoption. |

The existing `FrameBudgetedRangeScheduler` supplies frame/work quotas. Tests
inject a clock and explicit work quotas; no sleeps or elapsed-time thresholds
arrange races. Successful tests demonstrate real suspension with unfinished
production work, not physical frame latency.

### Indivisible operations still unproved

The following are explicitly **not** claimed to fit a physical frame budget:

- Initial object-graph pinning, list/map construction and image-byte copying;
  `BookChunk.toJson`, Base64 conversion, and a single source JSON decode.
- SDK map-key sorting and final `StringBuffer.toString` allocation/flattening.
- One source's normalized text/table parsing; one P05 renderer admission,
  font/image resolver invocation and identity construction. Iteration around
  these units yields, but their internals were not rewritten or weakened.
- Receipt/handoff metadata constructors and their ordinary codec hashes,
  bounded by the existing metadata ceiling; small identity/address hashes.
- Initial census serialization for an uncached object, and section membership
  census encoding. Weak identity caches avoid repeatedly encoding card,
  snapshot and index payloads, but do not prove the first call's latency.
- Final bounded collection wrappers and commit bookkeeping. The final commit
  does not rerun whole-source/body comparison or hashing.

Accordingly this proves resumable bulk encoding/hashing/comparison and yielding
core transactions, **not a complete UI-isolate latency guarantee**. It does not
turn complete-B preparation into first-readable-card preparation.

## Accounting

Existing limits remain: **432 source units, 96 cards, 25 guards, three sections,
6 MiB accounted bytes, 64 KiB metadata**, and the shared 110-entry reconstruction
work envelope. No worker is introduced, so worker/message copies are zero.

The census includes active/pending state, tracked rendering leases, cancelled
but unsettled work, incremental codec buffers and retained stable-body metadata.
Source capture reserves each private source record before constructing it,
then releases that reservation when ownership transfers or the attempt settles.
This prevents a near-cap capture from allocating an uncounted second set of
source records. Buffer checks use the latest stage census plus live private
reservations; they do not reserialize the complete census for every JSON token.

Encoding reserves UTF-16 output/builder copies plus codec scratch. Private
section/record encodings, decoded prefix graphs and prepared stable bodies are
held in the reservation until release/settlement. Some prepared-body reservation
is deliberately conservative after installation in the census. This is the
existing deterministic core storage model, **not VM heap/RSS, GC or whole-app
memory measurement**. SDK allocator overhead, arbitrary external caller roots,
repository caches and resolver closure captures remain outside that claim.

Observed small/rich yielding roundtrip peaks from the final handoff run:

| Quantity | Small | Rich |
| --- | ---: | ---: |
| Source units | 11 | 47 |
| Snapshot views | 4 | 4 |
| Sessions | 2 | 2 |
| Renderer authorities | 3 | 3 |
| Cards | 6 | 10 |
| Guards | 9 | 9 |
| Accounted bytes including buffer reservations | 293166 | 848384 |
| Validation buffer/reservation peak | 137372 | 351382 |
| Reconstruction entries | 4 | 18 |
| Injected scheduler yields over complete roundtrip | 495 | 1928 |

After retirement, tests require one snapshot, zero sessions and zero pending
transfers; the retained card's renderer lease still resolves the same block.
The source-cap test constructs 428 local records alongside accepted A, then
requires typed budget refusal, unchanged publication and complete release.
It is a refusal test, not a claim that a 428-source chapter can be fully prepared
within the smaller aggregate reconstruction allowance.

## Executable coverage

`test/reader_contract/regression/lazy_yielding_handoff_test.dart` has 12 cases:

- Y01: canonical bytes/digests across large Unicode, surrogate, escaping and
  byte-chunk boundaries; exact scheduler work/yield relationship.
- Y02: capture held during encoding; cancellation retains pending work until
  release, then settles with original publication and zero temporary buffers.
- Y03 (three cases): owner change, visible-position change and cancellation
  during private projection reject atomically and retain original card guards.
- Y04 (two cases): small and rich real parsed fixtures traverse forward and
  backward, reproduce ordinary production stable bodies exactly, retire old
  state, preserve renderer admission and exercise all major validation phases.
- Y05: near source ceiling exercises yielding capture and refuses excess
  aggregate live state without publishing; private source reservations reach
  exactly 432, never allowing another record allocation.
- Y06: a renderer lease acquired while retirement yields prevents retirement;
  release permits a later validated retirement.
- Y07: cancellation during stable validation settles as cancelled, preserves
  accepted A, and releases the pending session/buffers after the gate opens.
- Y08: a caller-created false proposal cannot authorize publication; accepted
  source-slice and payload range collections cannot be modified.
- Y09: cancelled retirement remains counted and refuses another operation while
  a validation slice is held; settlement releases it without publishing. A new
  retirement can then succeed.

## Commands and results

All commands ran in the same rescue worktree through `rtk`. Test invocations
were launched by `rtk proxy python3` using `subprocess.run`, combined stdout and
stderr redirected to the paths below. The `.exit` files record subprocess exit
codes for the latter runs. Flutter/Dart SDK host-cache access was approved.

| Log in `/tmp/` | Completed result | Exit |
| --- | --- | ---: |
| `nalori-yield-smoke.log` | 31 passed, 0 failed (forward/backward controls before later accounting refinements) | 0 |
| `nalori-yield-focused.log` | 6 passed, 1 failed: Y01's initial arbitrary `>100` yield assertion observed 53; byte/digest assertions passed | 1 |
| `nalori-yield-focused-2.log` | 9 passed, 0 failed, intermediate focused suite | 0 |
| `nalori-yield-final.log` | 66 passed, 0 failed: 11 new + 55 handoff controls | 0 |
| `nalori-yield-source-budget.log` | 27 passed, 0 failed: final source-reservation check, 11 new + 16 affected retention controls | 0 |
| `nalori-yield-controls.log` | 65 passed, 0 failed: stable-body, canonical publication/admission and scheduler controls | 0 |
| `nalori-yield-retirement-final.log` | 28 passed, 0 failed: final cancelled-retirement regression, 12 new + 16 retention controls | 0 |

The initial Y01 failure is preserved here: the test had imposed a yield count
unrelated to its source quota. It now asserts `yields == work.units ~/ 4` plus
many actual units, using a larger Unicode input. No historical oracle or
existing expectation was changed. The 66-case run preceded the final private
source-reservation refinement; the bounded 27-case rerun specifically checks
that refinement rather than repeating the broad matrix. Final review also found that cancelling a yielding retirement cleared its busy
flag prematurely. The correction retains the busy/accounting flag until the
finally block and records cancellation separately. Y09 specifically checks
that state while held. Its final 28-case run uses the same two test files as the
27-case source-budget run. Brace-only fixes were scoped to changed files.

Exact test commands (wrappers only capture logs/exit codes):

```sh
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_forward_retention_test.dart test/reader_contract/regression/lazy_backward_handoff_test.dart
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_yielding_handoff_test.dart
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_yielding_handoff_test.dart test/reader_contract/regression/lazy_single_handoff_test.dart test/reader_contract/regression/lazy_forward_retention_test.dart test/reader_contract/regression/lazy_backward_handoff_test.dart
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_yielding_handoff_test.dart test/reader_contract/regression/lazy_forward_retention_test.dart
rtk proxy env LD_LIBRARY_PATH=/tmp/nalori-stable-sqlite rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_stable_body_test.dart test/reader_contract/pagination/reader_card_paginator_canonical_paths_test.dart test/reader_contract/pagination/progressive_display_state_canonical_transaction_test.dart test/reader_contract/pagination/canonical_display_segment_admission_test.dart test/unit/services/frame_budgeted_range_scheduler_test.dart
```

The control wrapper supplies the shown `LD_LIBRARY_PATH` through Python's `env`
argument; it uses the existing host SQLite alias. No schema/setup change was
made. The preceding 286-case matrix and parser-isolate suite were not repeated.
Unique coverage is **132 passing / 0 failing cases**: 12 new cases, 55 handoff
controls and 65 additional controls. Repeated intermediate runs are not added
to those counts. No performance assertion uses the command's elapsed time.

Final scoped static analysis: **no issues**, exit **0**. Formatting: nine Dart
files, exit **0**. `rtk git diff --check`: clean, exit **0**. The final style pass
changed only formatting/comments after test compilation; no behavioral change
followed the final 28-case run. Logs: `/tmp/nalori-yield-final-analyze.log` and
`/tmp/nalori-yield-final-format.log`, with matching `.exit` files.

```sh
rtk dart analyze lib/models/canonical_pagination.dart lib/models/lazy_section_input.dart lib/models/lazy_stable_card.dart lib/services/lazy_validation_work.dart lib/services/lazy_forward_handoff_core.dart lib/services/lazy_snapshot_handoff_service.dart lib/services/lazy_stable_card_service.dart lib/services/progressive_display_state.dart test/reader_contract/regression/lazy_yielding_handoff_test.dart
rtk dart format lib/models/canonical_pagination.dart lib/models/lazy_section_input.dart lib/models/lazy_stable_card.dart lib/services/lazy_validation_work.dart lib/services/lazy_forward_handoff_core.dart lib/services/lazy_snapshot_handoff_service.dart lib/services/lazy_stable_card_service.dart lib/services/progressive_display_state.dart test/reader_contract/regression/lazy_yielding_handoff_test.dart
rtk git diff --check
```

## Files and remaining work

Checkpoint scope (10 files):

```text
lib/models/canonical_pagination.dart
lib/models/lazy_section_input.dart
lib/models/lazy_stable_card.dart
lib/services/lazy_validation_work.dart
lib/services/lazy_forward_handoff_core.dart
lib/services/lazy_snapshot_handoff_service.dart
lib/services/lazy_stable_card_service.dart
lib/services/progressive_display_state.dart
test/reader_contract/regression/lazy_yielding_handoff_test.dart
docs/development/nalori-yielding-handoff-proof.md
```

Preserved, excluded diagnostics: `nalori-last-anr.txt`, `nalori-logcat.txt`,
`nalori-meminfo.txt`, `regression.mp4`, `terminal_out.md`.

Remaining requirements: complete-chapter/first-readable-card preparation;
post-handoff reopen/checkpoint integration; empty-section chains and oversized
sections; the indivisible UI-isolate operations above; mounted ReaderScreen
forward/backward integration; physical-device verification. No semantic fallback
or relaxed validation is introduced. These gaps are not closed by rich-fixture
or injected-clock results.
