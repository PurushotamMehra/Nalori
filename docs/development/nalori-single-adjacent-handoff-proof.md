# Single adjacent-section canonical core handoff

Date: 2026-09-25 (Asia/Kolkata).
Baseline/unchanged HEAD: `8e7fc4c68b428c0f609e9f51d3535cfe2ed2fc88`.
Branch: `rescue/change-039-device-failure-2026-09-19`.

This implements the owner's separately authorized **one adjacent transfer** in
the production model/session/publication layer. That authorization permits this
core without completed screen wiring or repeated/backward retention proofs.
The approved sealed-receipt architecture and dual renderer/source-authority
decision were sufficient; no architecture decision was reopened.

## Supported capability

A lazy canonical publication holding a complete nonempty section A can adopt
an immutable A+B source snapshot and append the complete immediately following
linear section B through `ProgressiveDisplayState.publishSnapshotHandoff`.
The operation uses the sole production `ReaderCardPaginator` and
`CanonicalReaderPaginationSession`. It does not implement another paginator,
resume an old terminal continuation, use ordinary append with false ancestry,
or use replacement publication to conceal an append.

The opt-in `LazySectionInput` pins complete section records and immutable spine
metadata. The default ordinary full-snapshot request behavior is unchanged.
When that lazy input has a known successor, production pagination returns
`CanonicalInputExhaustedAwaitingSuccessor`; the session exposes
`CanonicalReaderInputExhausted` and seals its forward path. **No v1 terminal
continuation is created for that outcome.** A `SectionEndReceiptV1` binds the
complete owning section, finalized suffix, empty frontier, tagged section end,
next candidate and compatibility evidence. An independently verified final
linear section still produces the unchanged terminal continuation codec.

B is prepared privately from its trusted root in A+B, with an empty frontier.
Its chain starts at ordinal zero with no continuation parent. The separate
`LazySnapshotHandoffV1` records receipt, prefix, source extension, accepted
publication, retained card, root and compatibility proofs. Record digests are
recomputed; a caller's digest or stable record cannot confer runtime authority.

The transaction compares exact source owners **and all canonical prefix
records**, revalidates stable bodies and per-source font/image/structural P05
evidence, and checks the expected publication and operation at commit. It
atomically adopts the successor session, source snapshot, cards, projections,
receipt/continuation and lineage. A retains its original card objects, payloads,
slices, signatures and resolved renderer objects. All retained cards are
preserved, including the initial committed first card.

The dedicated `LazyHandoffRenderingAdapter` validates A under its original P05
contract, with exact A membership in A+B and matching lazy packing identity.
It never asserts that A's and A+B's F202/F208 are equal. Each contract's existing
F202 source tuple must bind its own snapshot. Ordinary renderer admission and
ordinary `publishCanonical` append remain strict. Ordinary display-cache write
authority is not issued for a section receipt.

Preparation stores its book-open/display/attempt owner. Reusing old prepared
work with a freshly labelled operation is rejected. The publication transaction
rejects cancellation, stale owners/revisions, replay and malformed transfers
without changing accepted publication. Invalid transfers latch that exact
attempt; a fresh attempt needs newly owned preparation. No automatic screen
retry or background continuation is wired by this core.

## Executable evidence

`test/reader_contract/regression/lazy_single_handoff_test.dart` runs real lazy
index/repository/default-parser output through the canonical session and
publication state. The small generated EPUB and existing rich micro fixture
are read without modifying frozen fixture bytes. Races use synchronous commit
hooks and owner changes; there are no sleeps or elapsed-time success assertions.

| Cases | Assertions |
| --- | --- |
| J01 | Known successor yields a tagged sealed receipt, no terminal continuation or terminal checkpoint, and incomplete-book publication state. |
| J02 | A publication remains unchanged during B preparation and at the commit hook. Every retained A object/guard/stable body survives; the successor session is adopted; source coverage has no missing/duplicate owner. B's root has chain ordinal 0 and null parent. Ordinary renderer rejects A under B's contract; dedicated dual authority admits the unchanged A renderer object. |
| J03 | Independently verified final section has a valid terminal codec, logical-end cursor and empty frontier. Attempted terminal resume rejects without changing that continuation. |
| J04 (4 cases) | Cancellation before/at commit, book-open epoch change and display-owner change reject, preserving the same accepted publication and full display digest. |
| J05 | Consumed handoff cannot replay or append twice. |
| J06 (7 cases) | Mutated receipt, publication digest, exact-prefix digest, successor owner, first-card signature, packing or successor-session digest rejects even after recomputing the proposal hash. Matching automatic attempts remain latched. |
| J07 | Changed complete A records and skipped B reject; a third section cannot be added through this one-transfer input. |
| J08 | Ordinary append rejects a successor root/snapshot/session and preserves publication. |
| J09 | B with another known successor produces a receipt, not book end; one A→B transfer succeeds, while B→C remains explicitly unsupported. |
| J10 | Real rich EPUB sections (14 A sources, 4 B sources) transfer with exact section coverage and retained A guards, including heading/list/table layout paths. |
| J11 | A renderer contract bound to the wrong source snapshot rejects private B preparation. |
| J12 | Stale per-source font evidence rejects publication without changing the accepted card/display digest. |
| J13 | A proposal racing a successful commit cannot overwrite it or append B twice. |
| J14 | Removing the successor from the caller's original index list does not alter the pinned authority; the previously proved successor still validates and transfers. |
| J15 | Old B preparation cannot be relabelled with a fresh attempt. Newly prepared evidence under that attempt can transfer. |

These are **24 distinct focused cases** (J04 and J06 are parameterized).
The final owner binding was added after code review identified that the first
implementation had checked current publication/operation ownership but had not
stored the preparation's own epoch/attempt. J15 exercises that corrected gap.

## Commands and results

All commands ran in `/home/uttam/Desktop/Antigravity Projects/Nalori` with
approved host Flutter/Dart cache access. The existing documented SQLite alias
`/tmp/nalori-stable-sqlite/libsqlite3.so` was used; no setup or dependency schema
was changed.

```sh
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_single_handoff_test.dart > /tmp/nalori-single-handoff-first.log 2>&1
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_single_handoff_test.dart > /tmp/nalori-single-handoff-second.log 2>&1
rtk proxy env LD_LIBRARY_PATH=/tmp/nalori-stable-sqlite rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_single_handoff_test.dart test/reader_contract/regression/lazy_stable_body_test.dart test/reader_contract/pagination/reader_card_paginator_canonical_paths_test.dart test/reader_contract/pagination/reader_card_paginator_canonical_state_machine_test.dart test/reader_contract/pagination/progressive_display_state_canonical_transaction_test.dart test/reader_contract/pagination/canonical_display_segment_admission_test.dart > /tmp/nalori-single-handoff-controls.log 2>&1
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_single_handoff_test.dart test/reader_contract/pagination/progressive_display_state_canonical_transaction_test.dart > /tmp/nalori-single-handoff-final.log 2>&1
rtk dart analyze lib/models/lazy_section_input.dart lib/models/canonical_pagination.dart lib/services/reader_card_paginator.dart lib/services/lazy_snapshot_handoff_service.dart lib/services/progressive_display_state.dart test/reader_contract/regression/lazy_single_handoff_test.dart
rtk proxy git diff --check
```

| Run | Passed | Failed | Skipped | Exit | Meaning |
| --- | ---: | ---: | ---: | ---: | --- |
| Initial focused | 17 | 1 | 0 | 1 | J07 test setup used compact chunk type key `t` for a text mutation. Corrected to the actual text key `tx`; no assertion was weakened. |
| Expanded focused | 22 | 0 | 0 | 0 | Includes rich EPUB, source-contract, font and racing-commit coverage. |
| Affected controls batch | 98 | 0 | 0 | 0 | 22 focused cases plus 76 existing controls; completed tail `02:55 +98: All tests passed!`. |
| Final owner-binding verification | 33 | 0 | 0 | Not retrieved | 24 focused cases plus 9 publication controls. Completed tail `01:14 +33: All tests passed!`, after `(tearDownAll)`. The process handle expired across the user continuation before exit-status retrieval. |
| Durable final focused verification | 24 | 0 | 0 | 0 | Final tree; completed tail `00:26 +24: All tests passed!`; process exit retrieved and saved. |

On continuation, only the focused cases were rerun to close that exit-status
capture gap. The exact durable wrapper was:

```sh
rtk proxy python3 - <<'PY'
import subprocess
from pathlib import Path
with open('/tmp/nalori-single-handoff-final-focused.log', 'w') as log:
    result = subprocess.run(['rtk', 'flutter', 'test', '--no-pub', '--reporter', 'expanded', 'test/reader_contract/regression/lazy_single_handoff_test.dart'], stdout=log, stderr=subprocess.STDOUT)
Path('/tmp/nalori-single-handoff-final-focused.exit').write_text(str(result.returncode) + '\n')
print('Focused test exit:', result.returncode)
raise SystemExit(result.returncode)
PY
```

Both tool completion and `/tmp/nalori-single-handoff-final-focused.exit` record
**0**. Final distinct coverage is **24 focused + 76 existing controls = 100
passing cases**; overlapping/repeated cases are not added to that total. The
final 9 publication controls also appear in the completed 33-case run. No
production or test file was edited after durable final verification.

The control batch compiled before the final preparation-owner guard. The final
run specifically rechecks that new lazy path and its directly affected
publication controls. The other canonical/stable-body paths were not edited
after their control run. Initial analyzer info findings (braces and one const)
were fixed; final scoped analysis reports **No issues found**, exit 0. Formatting
and diff checks exit 0. No completed test is described as a fresh run of the
prior **286-case** matrix; that matrix and the closed default-isolate suite
were not repeated.

The longer canonical source-267→280 control was monitored while computing;
it completed with its existing bounded-work assertions and normal teardown.
No test timed out or was terminated by the agent. The final combined runner reached completed teardown; its expired process handle prevented exit-code retrieval on continuation. Reporter durations are operational
records, not performance assertions.

## Scope, historical evidence and remaining gates

Exactly these seven files belong to this task:

```text
lib/models/canonical_pagination.dart
lib/models/lazy_section_input.dart
lib/services/reader_card_paginator.dart
lib/services/lazy_snapshot_handoff_service.dart
lib/services/progressive_display_state.dart
test/reader_contract/regression/lazy_single_handoff_test.dart
docs/development/nalori-single-adjacent-handoff-proof.md
```

The existing stable-body v1 and checkpoint v2 formats, ordinary P05 validators,
frozen oracles and historical test expectations are unchanged. The earlier
real-screen/default-isolate completion report and all five pre-existing
untracked diagnostics are preserved. No staging, commit, reset, rebase, push,
device execution, scrubber or P07 work occurred.

The core defects characterized by H01/H02 now have passing production evidence
through J01/J02/J09 and the dedicated protocol. The approved dual-authority K02
capability is exercised by J02 while ordinary renderer rejection remains valid.
The old characterization callers still use the old snapshot-only/ordinary
forward or renderer APIs; those tests were not rewritten to fabricate success
and were not rerun here. No new eight-red or zero-red historical-suite count is
claimed. H04's separate screen reason predicate is untouched. R02/L02 remain
historical legacy-format evidence; their expectations were not changed.

Explicit limits, not inferred capabilities:

- **One transfer only.** A complete nonempty linear A and immediate nonempty B
  must fit the current bounds. Input refuses a third section and publication
  refuses a second transfer. Empty-section chains/certificates, nonlinear
  continuation and resumable oversized private preparation remain unsupported.
- Preparation uses the existing 110-entry work envelope with the remaining
  budget passed to each canonical forward call. Section/snapshot evidence has
  source/byte caps; the transaction checks combined A and A+B source counts,
  card counts and checkpoint-record counts against 432/96/25.
- These checks are **not aggregate retained-memory proof** for all reader,
  repository/cache, font/image, pending or repeated-transfer state. Source/body
  encoding, all live copies and UI-thread validation slicing/latency still need
  measured aggregate evidence. No device latency claim is made.
- **No backward retention/transfer or exact backward regeneration after a
  handoff** is implemented or proved. Lazy handoff sessions reject that route.
- **No automatic ReaderScreen handoff wiring.** Screen owner integration,
  receipt-driven adjacent loading, first-card/provisional publication policy,
  demand joining, hydration/index/cache scheduling and screen failure/Retry
  behavior for this new transfer remain separate integration work.
- Stable-body/checkpoint reopening after an accepted handoff is not newly
  proved here. The unchanged stable-body controls cover their existing scope.

P04 and P06 remain open, progress **46/89**, P07 unstarted. This report establishes
one production core transfer and leaves the stated integration/retention gates
open.
