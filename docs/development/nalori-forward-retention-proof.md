# Repeated forward handoff and core retention proof

Date: 2026-09-25 (Asia/Kolkata). Baseline and unchanged HEAD:
`e88bb0f9da60946b90550191c9ca4284608e713c`.
Branch: `rescue/change-039-device-failure-2026-09-19`.

This implements the explicitly authorized next production capability after
[the single-transfer proof](nalori-single-adjacent-handoff-proof.md), using
[the approved design §7](nalori-lazy-snapshot-handoff-design.md#7-bounds-retention-repeated-handoffs-and-backward-navigation)
and its dual renderer/source-authority decision. Previous proof files remain
historical evidence. No architecture decision was reopened.

## Supported production capability

`LazyForwardHandoffCore` coordinates repeated adjacent, nonempty, bounded
linear-section transfers through the production canonical paginator,
`LazyPreparedSection`, and `ProgressiveDisplayState.publishSnapshotHandoff`.
The tested sequence is A → A+B → retained B → B+C. The reader advances its
explicit visible signature into B before the separate suffix-retirement
transaction can discard A. The longer fixture executes 17 transfers across
18 small sections, retiring after each transfer.

The lazy source view shares immutable `CanonicalLazySourceRecord` backing
objects. Expansion shares retained source text; suffix retirement shares the
exact retained encoded section and source records. Only the ephemeral engine
view projects source indices into its current address space. Stored records,
accepted card payloads, source slices, signatures and resolved renderer blocks
are not reindexed or rewritten. Ordinary dense source decoding and ordinary
append/renderer validation stay strict.

Retirement validates an exact source suffix and every retained card, then
atomically adopts a detached `LazyRetainedSection`. It keeps the original P05
renderer contract, stable bodies, card guards and sealed section receipt. It
drops the paginator session, original layout resolver callbacks, obsolete
snapshot and predecessor preparation. A compact retention digest establishes
a new root; old continuations are neither relabelled nor resumed. Lineage
keeps digest links, not prior publication/handoff object chains. This task
retains sealed complete sections with empty frontiers; it does not transfer
partially prepared live frontiers.

`LazyRendererLease` resolves through current accepted authority and pins its
card signature. A visible A card or outstanding A renderer lease blocks
retirement and the next expansion with `retentionRequired`; neither is
silently evicted. Releasing a lease removes its core reference. B's renderer
returns the identical resolved block after retirement and the next transfer.
Integrations must use tracked leases; arbitrary caller-held historical
publication snapshots are not owned by the core.

There is one pending transfer. Handles contain only an integer. Terminal
settlement clears private input, raw parsed section, layout, session,
prepared evidence and handoff. Active cancellation keeps physical pagination
accounted until its future settles. Stale owner/publication/visible-card work,
invalid proposals, cancellation and replay cannot replace accepted state.
An old token cannot clear a later transfer. Commit binds visible signature
as well as epoch, owner and publication. Oversized supplied handoffs are
counted and rejected before publication validation.

A known successor still produces loaded-input exhaustion and a sealed
receipt, not logical book end. The final section uses the unchanged genuine
terminal continuation path. Retirement preserves verified book-end state
without retaining or transplanting that terminal continuation. No ordinary
cache-write authority is granted by these lazy transfers.

## Deterministic evidence

The tests reuse the existing real EPUB/default-parser fixture loader and
production layout harness. They do not substitute a paginator or fake accepted
publication. Synchronous owner/commit/cancellation checkpoints arrange races;
there are no sleeps, timing thresholds or large performance fixtures.

| Cases | Assertions |
| --- | --- |
| F01 | A→B→C; advance into B before retirement; identical B backing objects, stable-body bytes, card guards, renderer block and stable source projection; retired sessions/preparations disappear; genuine final-book state. |
| F02 | Visible A and an A renderer lease independently prevent retirement and expansion; digest and renderer remain valid; explicit release permits retirement. |
| F03 | Pending source/backing/view/byte state is counted; another attempt is refused; cancellation restores the exact baseline census and invalidates its token. |
| F04 (3 cases) | Cancelled, stale-epoch and invalid second transfers preserve the identical publication and restore the baseline census; consumed tokens reject replay. |
| F05 | Cancellation during actual canonical pagination releases private state after settlement. |
| F06 | Tightened aggregate source/card budgets reject without evicting visible A. |
| F07 | 18 sections/17 transfers: after each retirement one source view, one renderer, two fixture source records, zero sessions, zero preparation/resolver references and zero pending work; bounded peaks. |
| F08 | Cancellation at the second commit releases private roots and preserves B. |
| F09 | Replaying the second token cannot clear a later third transfer. |
| F10 | Tightened byte/metadata limits release rejected candidates without changing publication. |
| F11 | The visible B body card, not just a heading/first card, remains byte-identical and is bound in the second handoff. |
| F12 (2 cases) | Visible-position change at commit and oversized proposal reject the second transfer atomically and release its roots. |
| F13 | `cancelPending` during active production pagination keeps session/pending reservations counted until settlement, then restores baseline. |

There are **16 new cases**, plus **24 existing single-transfer cases**. The
single-transfer helper was exported for reuse; none of its expected results
changed. Its direct second-transfer rejection remains correct without the
required suffix transaction; the new core supplies that missing capability.
Historical red/oracle files were not changed or rerun. No new historical-suite
red count is claimed.

## Live-state accounting and observed bounds

The core enforces approved ceilings across accepted authorities, pending work,
private retention candidates and tracked renderer leases: 432 source units,
96 published/prepared cards, 25 continuation/receipt/lineage guards, three
sections, 6 MiB accounted payload, 64 KiB UTF-8 receipt/handoff metadata,
one pending transfer and a two-card frontier reservation. Preparation consumes
remaining aggregate card/guard allowances, not multiplied per-session limits.
Existing 110-entry normal and 158-entry recovery envelopes are not expanded.
Supplied limits can only tighten these ceilings.

The census traverses live roots and deduplicates shared backing objects,
snapshots, sessions, renderer contracts, cards and stable bodies by identity.
It includes pending raw parsed content, decoded-source/scratch reservations,
section encodings, stable bodies, card/source slices, guards, renderer retained
state, display maps, lease references and pinned publication-index metadata.
Private suffix candidates count before commit, hence the transient third
source view. The publication index is fixed for a book and counted; it does
not grow with the handoff ordinal.

Byte accounting is a deterministic storage model: UTF-16 encoded payloads,
existing renderer `retainedStateBytes` estimates and scratch/reference
reservations. It is **not an exact Dart heap measurement**. Metadata wire size
uses UTF-8. Font/image resolver references are counted and all are released
upon retirement. External provider caches, caller-held fixture/publication
objects, repository caches, native font/image memory and allocator/GC overhead
are not core-owned byte allocations. Arbitrary closure-capture graphs cannot
be sized by this census. Screen integration must account its additional
owners; these numbers are not whole-reader or physical-device memory totals.

Final focused-run traces:

| Quantity | A→B→C peak | 18-section peak | Final retired state, 18 sections |
| --- | ---: | ---: | ---: |
| Source units including raw/scratch reservations | 11 | 11 | 2 |
| Immutable backing records | 4 | 4 | 2 |
| Source snapshot views | 3 | 3 | 1 |
| Canonical sessions | 2 | 2 | 0 |
| Renderer authorities | 2 | 2 | 1 |
| Cards | 4 | 4 | 2 |
| Continuation/receipt/lineage guards | 9 | 9 | 4 |
| Sections | 2 | 2 | 1 |
| Accounted bytes | 115,036 | 123,902 | 50,596 |
| Encoded receipt/handoff metadata bytes | 12,148 | 12,359 | 0 |
| Preparation references | 2 | 2 | 0 |
| Resolver references | 2 | 2 | 0 |
| Pending transfers/candidates | 1 | 1 | 0 |
| Frontier card reservation | 2 | 2 | 0 |
| Pinned index metadata bytes, included above | 2,168 | 10,194 | 10,194 |

F01 also keeps one renderer lease across retirement and the next transfer.
Tight-limit tests establish refusal without eviction. These small-fixture
peaks do not claim every admissible section has the same size. They do not
prove bounded UI-isolate validation time or first-card latency.

## Verification commands and results

All tests ran on the current rescue worktree with approved host SDK access.
The existing SQLite alias `/tmp/nalori-stable-sqlite/libsqlite3.so` points to
the system library. No dependency or schema setup changed. The prior 286-case
matrix and closed parser-isolate suite were not repeated.

Development commands:

```sh
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_forward_retention_test.dart > /tmp/nalori-forward-retention-first.log 2>&1
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_forward_retention_test.dart test/reader_contract/regression/lazy_single_handoff_test.dart > /tmp/nalori-forward-retention-second.log 2>&1
```

Initial run: **8 passed / 1 failed**, exit **1**. F06 set a one-card ceiling
below the initial two-card publication and failed in construction before its
intended pending-budget assertion. The fixture ceiling was corrected to two;
no assertion or validator was weakened. Expanded run: **37 passed / 0 failed**,
exit **0**. Final review added visible-commit binding, proposal accounting and
three more focused cases.

Final focused command with durable exit capture:

```sh
rtk proxy python3 - <<'PY'
import subprocess
from pathlib import Path
with open('/tmp/nalori-forward-retention-final.log', 'w') as log:
    result = subprocess.run(['rtk', 'flutter', 'test', '--no-pub', '--reporter', 'expanded', 'test/reader_contract/regression/lazy_forward_retention_test.dart', 'test/reader_contract/regression/lazy_single_handoff_test.dart'], stdout=log, stderr=subprocess.STDOUT)
Path('/tmp/nalori-forward-retention-final.exit').write_text(str(result.returncode) + '\n')
print('Focused exit:', result.returncode)
raise SystemExit(result.returncode)
PY
```

Completed **40 passed / 0 failed / 0 skipped**, exit **0**;
`00:27 +40: All tests passed!`.

Directly affected controls:

```sh
rtk proxy python3 - <<'PY'
import os, subprocess
from pathlib import Path
cases = [
 'test/reader_contract/regression/lazy_stable_body_test.dart',
 'test/reader_contract/pagination/reader_card_paginator_canonical_paths_test.dart',
 'test/reader_contract/pagination/reader_card_paginator_canonical_state_machine_test.dart',
 'test/reader_contract/pagination/progressive_display_state_canonical_transaction_test.dart',
 'test/reader_contract/pagination/canonical_display_segment_admission_test.dart',
]
env = dict(os.environ, LD_LIBRARY_PATH='/tmp/nalori-stable-sqlite')
with open('/tmp/nalori-forward-retention-controls.log', 'w') as log:
    result = subprocess.run(['rtk', 'flutter', 'test', '--no-pub', '--reporter', 'expanded', *cases], env=env, stdout=log, stderr=subprocess.STDOUT)
Path('/tmp/nalori-forward-retention-controls.exit').write_text(str(result.returncode) + '\n')
print('Control exit:', result.returncode)
raise SystemExit(result.returncode)
PY
```

Completed **76 passed / 0 failed / 0 skipped**, exit **0**, including normal
`(tearDownAll)`. Total distinct final verification: **116 passing cases**.
Both final runner exits were retrieved from their processes and saved in
their `.exit` files. No production/test changes followed these runs.

Evidence limitation: a report-writing heredoc delimiter collision caused a
shell command failure (exit 127) and accidentally attempted the embedded SDK
commands in the restricted sandbox. That extra control invocation failed
before running tests (exit 1, SDK cache read-only), and truncated the early
portion of the still-running original control log. The original approved
runner was unaffected, completed 76 cases and exited 0; its final test/teardown
tail survives after a sparse region. The original full early log cannot be
claimed as preserved. No source changes resulted; this was not a production
test failure. No repeat control run was used to conceal the logging error.

```sh
rtk dart analyze lib/models/canonical_pagination.dart lib/models/lazy_section_input.dart lib/services/lazy_forward_handoff_core.dart lib/services/lazy_snapshot_handoff_service.dart lib/services/progressive_display_state.dart test/reader_contract/regression/lazy_forward_retention_test.dart test/reader_contract/regression/lazy_single_handoff_test.dart
rtk dart format lib/models/canonical_pagination.dart lib/models/lazy_section_input.dart lib/services/lazy_forward_handoff_core.dart lib/services/lazy_snapshot_handoff_service.dart lib/services/progressive_display_state.dart test/reader_contract/regression/lazy_forward_retention_test.dart test/reader_contract/regression/lazy_single_handoff_test.dart
rtk proxy git diff --check
```

Approved scoped analysis: **No issues found**, exit **0**. Formatting and diff
checks exit **0**. Reporter durations are records, not latency assertions.

## Exact checkpoint scope and remaining gates

These eight files belong to this task:

```text
lib/models/canonical_pagination.dart
lib/models/lazy_section_input.dart
lib/services/lazy_forward_handoff_core.dart
lib/services/lazy_snapshot_handoff_service.dart
lib/services/progressive_display_state.dart
test/reader_contract/regression/lazy_forward_retention_test.dart
test/reader_contract/regression/lazy_single_handoff_test.dart
docs/development/nalori-forward-retention-proof.md
```

Stable-body v1, checkpoint v2, continuation/persistent cache formats, strict
ordinary validators, frozen oracles, earlier recovery/proof history and the
five pre-existing untracked diagnostic artifacts are preserved. No staging,
commit, push, reset, device execution, scrubber or P07 work occurred.

Explicit remaining requirements:

- Backward navigation, predecessor reconstruction and prepend transfer after
  retirement; partial/live-frontier transfer.
- Empty-section chains/certificates and oversized-section subdivision or
  resumable preparation. Over-bound inputs reject without evicting pinned
  authority. No whole-book reconstruction is attempted.
- First-readable-card preparation without waiting for an entire large chapter.
  **This core prepares complete B before publication; it does not satisfy the
  first-card latency requirement.**
- Bounded/yielding comparison, hashing, encoding and validation on the UI
  isolate. Current validation remains synchronous within source/byte caps.
- Mounted ReaderScreen integration, demand joining/promotion and automatic
  receipt-driven loading, screen task/Retry/Back lifecycle, post-handoff
  hydration/index/cache scheduling, and physical-device verification.
- Whole-reader retained memory, including external caches and callback owners;
  handoff persistence/reopening is not newly proved here.

P04 and P06 remain open; progress stays **46/89**; P07 remains unstarted.
A next bounded task can prove backward reconstruction after retirement under
the same stable packing/source authority, with exact retained-card and
aggregate-state checks. Screen and first-card/yielding work remain separate
gates; none is started by this report.
