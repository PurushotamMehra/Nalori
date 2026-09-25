# Bounded backward reconstruction after forward retirement

Date: 2026-09-26 (Asia/Kolkata).
Branch: `rescue/change-039-device-failure-2026-09-19`.
Baseline/current HEAD: `ceb68445ce984f90035fbbeb7b2023b354af013a`.

The supplied `<NEW_COMMIT_HASH>` was a placeholder. HEAD initially remained
`e88bb0f9da60946b90550191c9ca4284608e713c`, with the prior eight-file forward
retention change uncommitted. Following the explicit instruction “i did not
commit, do so and proceed”, those eight files were committed as `ceb68445…`
(`Implement repeated forward handoffs with core retention`). The diagnostic
artifacts were excluded. The backward work described here remains uncommitted;
there was no push, reset or device execution.

This implements the next bounded core capability under the existing
[forward-retention proof](nalori-forward-retention-proof.md) and
[approved backward design, §7](nalori-lazy-snapshot-handoff-design.md#7-bounds-retention-repeated-handoffs-and-backward-navigation).
No architecture decision was reopened. Previous reports and protected evidence
remain unchanged.

## Production behavior

The core now supports A→B→C with actual retirement, followed by C→B→A and
forward navigation again. Each backward operation adds one verified immediate
linear predecessor, using pinned publication/spine authority. The existing
`LazyForwardHandoffCore` owns both directions so cancellation, pending work,
renderer leases and aggregate budgets are not split between coordinators.

`beginPrevious` captures the predecessor's immutable source evidence and a
shared predecessor+current source window. `prepare` uses the existing
`LazyPreparedSection` and production `CanonicalReaderPaginationSession` to:

1. Regenerate the complete bounded predecessor from its validated section root.
2. Regenerate the current section, including the committed visible card, from
   its own exact source snapshot and trusted root.
3. Compare every regenerated current stable body with accepted evidence and
   prove the complete predecessor boundary meets the current section's first
   source/cursor without gaps, duplicates or reordering.

Both preparations share the existing **110-entry** normal work allowance.
The second receives only the remainder. Neither old terminal continuations
nor snapshot-specific checkpoints are transplanted. There is no historical
handoff-chain walk, whole-book reconstruction, semantic substitute, alternate
paginator or fabricated accepted card. The existing 158-entry recovery ceiling
is not enlarged or consumed as an automatic extra attempt.

`buildLazySnapshotPrepend` binds publication, visible signature, lineage,
predecessor root/receipt, stable-body digests, exact shared source window,
packing evidence and successor cursor. `publishSnapshotPrepend` is a dedicated
transaction that imports only predecessor cards. It preserves all previously
accepted current card objects and their original renderer authority. It
revalidates evidence and owner/publication/visible position after the final
callback before atomically adopting cards, source window, projections and
lineage. Ordinary append validation is unchanged.

Stable-body equality includes payload, signatures, stable source slices and
resolved layout metrics. Newly reconstructed runtime card indexes and ordinal
hints may differ; they are not stable identity. B01 explicitly observes changed
runtime slices while requiring byte-identical stable bodies. Retained current
cards themselves are not rewritten or re-signed.

As with forward transfer, publication and visible-position advancement are
explicit core steps. The prepend keeps the committed C card valid; after
acceptance the caller advances into B and invokes `retainSnapshotPrefix`.
That separate transaction retains B, drops obsolete C/session/preparation
state and refuses retirement while a tracked C renderer lease remains pinned.
The accepted publication has a separate immutable source window, allowing
strict original renderer contracts and stable source projection to coexist.
Retirement keeps compact digest links, never predecessor object chains.

Cancellation stays counted until active pagination settles. Publication checks
the core token as well as the external operation. A cancelled commit cannot
clear a newer pending attempt. Stale epoch/owner/visible-position work and
invalid proposals leave publication unchanged and release private evidence.
An exact preparation mismatch returns `exactUnavailable`; aggregate refusal
returns `boundExceeded`. Matching preparation failures latch the attempt;
explicit retry creates a newly owned attempt. No semantic fallback or automatic
rebuild is introduced. Retry/Back UI is not part of this core task.

## Focused executable evidence

`lazy_backward_handoff_test.dart` contains **15 cases**, using the production
repository/default parser, canonical paginator, stable-body emitter, handoff
service, rendering adapter and publication state. The fixture loader is shared
with existing handoff tests; their expectations are unchanged. Races use
synchronous callbacks and cancellation predicates, not sleeps or timing gates.

| Cases | Evidence |
| --- | --- |
| B01 | Real forward retirement, C→B→A, exact previous stable bodies/signatures/slices, current card and renderer preservation, explicit visible advancement and prefix retirement, then A→B→C again. |
| B02 | Six backward/forward cycles: 12 backward crossings and 14 forward crossings including initial traversal; each retirement returns to one source view/renderer and zero sessions, leases, pending and resolver references. |
| B03 (6 cases) | Cancellation before commit, stale epoch, invalid proposal, external cancellation at commit, visible-position race and core cancellation at commit all preserve publication and release private state. |
| B04 | A skipped predecessor is unavailable; invalid font evidence cannot produce semantic success. |
| B05 | Cancellation during the second real pagination session keeps active work accounted until settlement and restores the baseline census. |
| B06 | Eight-section EPUB; initial traversal loads only sections 0–2. Fresh production repository sessions reload only predecessor sections 1 and 0 after canonical retirement. Later chapters are not loaded. |
| B07 | A four-card aggregate limit admits predecessor preparation but refuses the additional current-section verification cards. Failure releases state and latches matching work without eviction. |
| B08 | Wrong current-section restart/layout authority returns exact unavailable; matching automatic work is blocked; one explicitly new attempt can prepare and publish. Concurrent duplicate preparation is refused. |
| B09 | Rich production EPUB reconstructs heading/list/table stable bodies exactly and moves forward again, within the shared work envelope. |
| B10 | Cancellation in an old commit callback followed by a new request cannot clear that new pending reconstruction. |

The pre-edit test first traversed and retired A→B→C, then called the missing
production entry point. It completed **0 passed / 1 failed**, exit **1**:

```text
NoSuchMethodError: Class 'LazyForwardHandoffCore' has no instance method 'beginPrevious'.
00:02 +0 -1: Some tests failed.
```

This is missing-capability evidence, not a claim that old code silently
accepted backward work. The final test uses the statically typed production
entry point and checks the complete round trip.

## Observed live-state bounds

The shared census includes accepted and private source windows, canonical
sessions, verification cards, renderer authorities, section encodings, stable
bodies, receipts/guards/lineage, pending parsed input, scratch reservations,
tracked renderer leases and pinned publication metadata. No per-direction
allowance multiplies the approved 432-source / 96-card / 25-guard / three-section
/ 6 MiB / 64 KiB metadata ceilings. One pending transfer and the existing
two-card frontier reservation remain in force.

| Quantity | Six-cycle oscillation peak | Rich backward/forward peak | After each small-fixture retirement |
| --- | ---: | ---: | ---: |
| Source units including scratch/raw reservation | 11 | 47 | 2 |
| Immutable backing records | 4 | 18 | 2 |
| Source snapshot views | 4 | 4 | 1 |
| Canonical sessions | 2 | 2 | 0 |
| Renderer authorities | 3 | 3 | 1 |
| Cards, including verification | 6 | 10 | 2 |
| Continuation/receipt/lineage guards | 10 | 9 | 4 |
| Sections | 2 | 2 | 1 |
| Accounted bytes | 141,462 | 427,596 | 42,274 |
| UTF-8 receipt/handoff metadata bytes | 12,273 | 9,665 | 0 |
| Preparation references | 2 | 2 | 0 |
| Resolver references | 2 | 2 | 0 |
| Pending transfers | 1 | 1 | 0 |
| Frontier card reservation | 2 | 2 | 0 |
| Tracked leases | 1 | 0 | 0 |
| Shared backward reconstruction work entries | 4 | 18 | — |

The fourth transient snapshot view is the private retirement candidate, in
addition to the shared publication window and its separate section authorities.
The third renderer is the private regenerated current-section contract; it is
released after verification/publication. No historical chain accumulates.

These are deterministic core-root counts and storage estimates, **not Dart
heap, native memory or physical-device measurements**. The existing accounting
qualifications still apply: external repository/font/image caches, arbitrary
caller-held old publications and resolver closure captures outside the core
are not measured as whole-app memory. Byte accounting uses encoded payloads,
renderer retained-state estimates and scratch reservations. It does not prove
UI-isolate latency or allocation/GC behavior.

## Commands and results

All commands ran on the rescue worktree. Host Flutter/Dart cache access was
approved. The controls used the existing SQLite alias
`/tmp/nalori-stable-sqlite/libsqlite3.so`; no setup/schema change was made.
The previous 286-case matrix and closed parser-isolate verification were not
repeated.

All test invocations used `rtk flutter test --no-pub --reporter expanded`,
launched through `rtk proxy python3` with `subprocess.run`, redirecting combined
output to the named log and writing the actual return code to the matching
`.exit` file before returning it. Exact file arguments and completed results:

| Log prefix in `/tmp/` | File arguments | Passed | Failed | Exit |
| --- | --- | ---: | ---: | ---: |
| `nalori-backward-red` | backward test before implementation | 0 | 1 | 1 |
| `nalori-backward-first` | backward test | 9 | 0 | 0 |
| `nalori-backward-second` | backward, forward-retention, single-handoff tests | 53 | 0 | 0 |
| `nalori-backward-final` | backward, forward-retention, single-handoff tests | 55 | 0 | 0 |

Final focused invocation and durable wrapper:

```sh
rtk proxy python3 - <<'BACK_FINAL_RUN'
import subprocess
from pathlib import Path
with open('/tmp/nalori-backward-final.log','w') as log:
 r=subprocess.run(['rtk','flutter','test','--no-pub','--reporter','expanded','test/reader_contract/regression/lazy_backward_handoff_test.dart','test/reader_contract/regression/lazy_forward_retention_test.dart','test/reader_contract/regression/lazy_single_handoff_test.dart'],stdout=log,stderr=subprocess.STDOUT)
Path('/tmp/nalori-backward-final.exit').write_text(str(r.returncode)+'\n')
print('Final backward and handoff controls exit:',r.returncode)
raise SystemExit(r.returncode)
BACK_FINAL_RUN
```

Final focused tail: `00:49 +55: All tests passed!`; **0 skipped**, exit **0**.
The only subsequent test edit added braces around two existing `if` bodies
to resolve style-only analyzer findings; no assertion or execution path changed.

Directly affected canonical/stable-body controls:

```sh
rtk proxy python3 - <<'BACK_AFFECTED_CONTROLS'
import os, subprocess
from pathlib import Path
cases = [
 'test/reader_contract/regression/lazy_stable_body_test.dart',
 'test/reader_contract/pagination/reader_card_paginator_canonical_paths_test.dart',
 'test/reader_contract/pagination/reader_card_paginator_canonical_state_machine_test.dart',
 'test/reader_contract/pagination/progressive_display_state_canonical_transaction_test.dart',
 'test/reader_contract/pagination/canonical_display_segment_admission_test.dart',
]
with open('/tmp/nalori-backward-controls.log','w') as log:
 r=subprocess.run(['rtk','flutter','test','--no-pub','--reporter','expanded',*cases],env=dict(os.environ,LD_LIBRARY_PATH='/tmp/nalori-stable-sqlite'),stdout=log,stderr=subprocess.STDOUT)
Path('/tmp/nalori-backward-controls.exit').write_text(str(r.returncode)+'\n')
print('Backward affected controls exit:',r.returncode)
raise SystemExit(r.returncode)
BACK_AFFECTED_CONTROLS
```

Control result: **76 passed / 0 failed / 0 skipped**, exit **0**;
`02:52 +76: All tests passed!` after normal `(tearDownAll)`. The full log and
durable exit file were captured successfully. Total distinct final coverage:
**15 backward + 16 forward-retention + 24 single-handoff + 76 canonical/stable-body
controls = 131 passing cases**. Repeated development runs are not added to
this total. No production changes followed final verification.

```sh
rtk dart analyze lib/models/lazy_section_input.dart lib/services/lazy_snapshot_handoff_service.dart lib/services/lazy_forward_handoff_core.dart lib/services/progressive_display_state.dart test/reader_contract/regression/lazy_backward_handoff_test.dart test/reader_contract/regression/lazy_single_handoff_test.dart
rtk dart format lib/models/lazy_section_input.dart lib/services/lazy_snapshot_handoff_service.dart lib/services/lazy_forward_handoff_core.dart lib/services/progressive_display_state.dart test/reader_contract/regression/lazy_backward_handoff_test.dart test/reader_contract/regression/lazy_single_handoff_test.dart
rtk proxy git diff --check
```

Final scoped analysis: **No issues found**, exit **0**. Formatting and diff
checks exit **0**. Reporter durations are operational records, not performance
assertions. Historical characterization/oracle files and expectations were
not changed or rerun; no new historical red count is claimed.

## Changed files and remaining limits

These seven files belong to the backward change, relative to `ceb68445…`:

```text
lib/models/lazy_section_input.dart
lib/services/lazy_forward_handoff_core.dart
lib/services/lazy_snapshot_handoff_service.dart
lib/services/progressive_display_state.dart
test/reader_contract/regression/lazy_backward_handoff_test.dart
test/reader_contract/regression/lazy_single_handoff_test.dart
docs/development/nalori-backward-handoff-proof.md
```

Stable-body v1, checkpoint v2, continuation/cache formats, ordinary strict
validators, frozen oracles, prior recovery history and all five diagnostic
artifacts remain preserved. The one authorized commit contains only the prior
forward checkpoint. No backward commit, push, device run, scrubber or P07 work
was performed.

Remaining requirements are explicit:

- Empty-section chains, nonlinear predecessor policy beyond the pinned linear
  order, oversized-section subdivision and resumable reconstruction are not
  implemented. This path requires complete nonempty sections within bounds.
- First-readable-card preparation without complete-chapter preparation remains
  open. Backward verification currently prepares both complete bounded sections;
  it does not meet a first-card latency requirement.
- Bounded/yielding comparison, hashing, encoding and validation on the UI
  isolate remain open. Validation is synchronous within source/byte caps.
- Partial/live-frontier transfer and snapshot-specific checkpoint fallback
  across sections are not introduced; the supported restart is the trusted
  owning-section root, without an automatic fallback attempt.
- Mounted ReaderScreen integration, automatic direction/receipt scheduling,
  screen Retry/Back behavior, hydration/index/cache authority and physical-device
  verification remain separate work. Post-handoff persistence/reopen is not
  newly proved by these tests.
- Whole-app memory, external callback/cache owners and native/GC behavior are
  not established by the core census.

P04 and P06 remain open, progress **46/89**; P07 remains unstarted. This report
establishes bounded bidirectional core reconstruction for the stated complete
section case and does not close the remaining integration or latency gates.
