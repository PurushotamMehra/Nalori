# IMPLEMENT-P04-REAL-SCREEN-AUTHORITY-003

Bounded implementation completed 2026-09-24 on `rescue/change-039-device-failure-2026-09-19`, starting at
`e6037812e5ca3785029963d91dacfae8acf2b4d1`. No Git mutation or device run.

## Captured pre-correction evidence

Mounted `ReaderScreen`, real lazy repository, parser delegation, canonical
pagination and publication. The only initial production edits were observation
and injected completion gates. Gates hold parser, physical cache entry,
private pagination, warmup, hydration and derived-index scheduling. Virtual
16 ms frame advancement services existing production timers; there are no
wall-clock test deadlines or sleeps.

The final pre-correction run of
`rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/real_screen_authority_test.dart`
reported **0 passed / 9 failed / 0 skipped**, exit 1. Captured output:

```text
A01 startsBeforeRelease=[0, 1] owner=1
A02 heldWriteTrace=[parse:5, write_start:5]
A03 publicationRetained=false cardRetained=true starts=[0, 5]
A04 identicalFuture=false parserStarts=[0, 5]
A05 result=true failure=Bad state: A terminal continuation cannot be resumed. surfaced=null error=Bad state: A terminal continuation cannot be resumed.
A06 afterClose=[parse:5, write_start:5, write_end:5]
A07 recovery=null presented=null cards=2
A08 exact and semantic fixtures: Bad state: Lazy emission requires accepted production P05 evidence
```

A08 exposed an earlier screen wiring gate: its accepted production paginator
uses the ordinary composite as controlled layout identity; the unchanged
stable-body emitter requires `LazyPackingIdentityV1`. Those two reds did not
reach persisted reopen. They are not claimed as exact/migration lifecycle
proofs. A07 exercised a valid unavailable legacy checkpoint in the mounted
initial lifecycle. A06 reproduced an old physical cache callback after close;
book switching was not yet covered in that pre-correction run.

The first attempts exposed fixture compilation and observer/isolate capture
errors and are not product red evidence. One un-escalated Flutter invocation
failed before loading because SDK engine stamp files were read-only. Test-hook
serialization was isolated from observer closures before valid red collection.
Subsequent fixture refinements gated indexing and awaited real initial visible
settlement; expectations were not changed to accept defective behavior.

The temporary full logs from 2026-09-21 were lost when the execution environment
was renewed on 2026-09-22. The exact traces above were retained in the conversation
and transcribed here; no claim is made that the old `/tmp` files still exist.

Historical D02 and S01 evidence in the handoff entry/stable-body reports is
preserved. R02/L02 and H01–H04 remain separate, intentional legacy/handoff reds.
P04/P06 remain open, progress **46/89**, P07 unstarted.


## Implemented authority and ordering

The mounted production `ReaderScreen` owns target settlement. The existing
state-bound test handle delegates to `_navigateToStableLocation`, real adjacent
work and real hydration; it observes publication, readable card, owner, recovery
and settlement. It supplies deterministic gates immediately before real
pagination and at actual physical cache entry/commit, plus production quiet-work
scheduling gates. No substitute paginator, navigator, coordinator, successful
acceptance or publication implementation exists in the tests. The parser gate
delegates to `EpubParserService` and acknowledges cancellation before releasing
its one physical slot. SQLite checks use the real checkpoint store.

Identical foreground requests return the same future. An identical speculative
request retains its parser and promotes its repository priority, including a
hydration request. A different foreground target revokes the old publication
and background authority immediately. The default parser runs in a cancellable
isolate: cancellation kills that worker and waits for its exit before the single
scheduler slot is reused. The mounted A01 test observes the target's job launch
in exactly the next scheduler drain after the held parser acknowledges
cancellation, with maximum parser concurrency **1**. This is a scheduler proof,
not a device latency or millisecond performance claim. The isolate kill/exit
sequence above is source inspection only: A01 uses an injected cooperative
parser and does **not** prove physical default-worker exit. See the checkpoint
verification below for the exact remaining coverage gap.

Direct chapter **1 → 6** has parser starts **[0, 5]**, with no sections 1–4.
Private preparation keeps both the old accepted publication digest and visible
card JSON digest unchanged. The real acceptance callback observes the old card;
the synchronous publication callback observes the new card and current owner.
Chapter 6 → 10 starts **[0, 5, 9]** and publishes only chapter 10. An old success
cannot clear a newer failure or its terminal flags.

Ordering is `parse target → paginate privately → accept first card → publish`
then deferred physical section persistence and quiet hydration/indexing/warmup.
A02 holds physical write completion while foreground navigation settles. B06
holds physical commit while another target finishes, then proves the stale write
cannot commit. Foreground cache lookup treats a busy disk queue as a safe miss;
it does not inherit that writer's barrier or mutate cache metadata on its read
path. Writes are serialized by the existing disk coordinator and coalesced by
canonical section key. Only sections in the accepted publication are enqueued;
epoch, owner and accepted-state guards are checked again immediately before
payload/manifest publication. A new accepted owner can replace a superseded
pending save. A write failure is detached and leaves the readable card intact.

The screen now uses the prerequisite `LazyPackingIdentityV1` for lazy production
pagination while retaining ordinary P05 validation. Exact v2 recovery is admitted
only by the unchanged stable-body service after production regeneration. V1
semantic migration prepares the verified target while the SQLite checksum stays
unchanged; only accepted current-owner publication authorizes a v2 append.
The original journal row survives successful migration. Failed, cancelled and
unavailable migration preserve its original checksum. Initial and direct-target settlement schedule their lazy save after publication
and preparation completion. Explicit initial targets also select the lazy coordinator, skipping stored restoration as requested by
the existing navigation flag, and persist accepted v2 bodies.

The existing preparation-error surface presents typed `exactUnavailable` with
Retry and Back. The mounted UI test taps Retry and observes exactly one new
preparation; Back pops the actual route and preserves the original checkpoint
and EPUB. No EPUB, bookmark, annotation, highlight or note deletion path was
added. Deterministic failure returns failure to every joined waiter, latches
automatic preparation, and blocks eviction-triggered rebuild, adjacent warmup,
hydration, indexing and persistence. Explicit retry alone creates a new attempt.
Close revokes the epoch and settles pending waiters; a keyed real reader State
isolates a same-element book/session switch. Preparing/rebuilding flags clear
on successful, failed, superseded and cancelled terminal paths.

## Mounted green matrix

| Requirement | Real-screen case |
| --- | --- |
| 1: bounded chapter 1 → 6 parser starts | A03, B08: `[0, 5]` |
| 2: unrelated held speculative work preempted | A01: `[0, 1, 5]` before gate release; next drain; max 1 parser |
| 3: same speculative target joined/promoted | B01 boundary, B10 hydration; no duplicate parser |
| 4–5: old visible bytes retained, atomic publication | A03 old/new digests and actual acceptance/publication owner |
| 6: latest chapter 6 → 10 wins | B02; B09 also preserves newer failure after old completion |
| 7–8: first card before physical write/hydration/index; detached write | A02, B06, B08 |
| 9: exact v2 recovery and settlement | A08 exact |
| 10: semantic v2 write only after accepted publication | A08 semantic, real SQLite row inspection |
| 11: unavailable/cancelled/failed migration preserves checkpoint | A07, B07 cancelled, B07 failed |
| 12: deterministic failure blocks background continuation | A05, B03, B09 |
| 13: one attempt per explicit Retry | A07 unavailable, B03 deterministic target failure |
| 14: close/switch invalidate old callbacks | A06, B05, B06 stale commit |
| 15: runtime flags clear on terminal paths | A03, A08, B01–B05, B07, B09, B11 |
| Extra controls | A04 identical future; B04 failed persistence preserves card; B11 initial explicit target uses v2 |

## Exact files changed

Production:
- `lib/screens/reader_screen.dart`: state-bound observation/gates; target ownership,
  atomic publication, lazy recovery, failure settlement and book/session remount.
- `lib/services/lazy_book_session.dart`: target-only prepared window; closed-session
  result rejection; accepted-section persistence delegation.
- `lib/services/lazy_section_repository.dart`: cancellable single-slot priority
  work; parsed evidence before persistence; post-publication coalesced writes.
- `lib/services/parsed_section_cache_service.dart`: write authority checks,
  foreground reads without writer barriers, physical-write observation.
- `lib/services/lazy_checkpoint_recovery.dart`: preloaded/explicit-open initialization
  and guarded accepted-body persistence using existing formats.

Tests and ledger:
- `test/reader_contract/regression/real_screen_authority_test.dart` (new).
- `test/reader_contract/regression/lazy_snapshot_handoff_screen_test.dart`: move
  real checkpoint close into the active widget-test body and pump its completion;
  all original behavior assertions are unchanged.
- `docs/development/nalori-real-screen-authority-proof.md` (this new report).
- `docs/development/nalori-lazy-snapshot-handoff-entry-proof.md` (current pointer only).
- `docs/development/nalori-reader-reliability-change-log.md` (append only).

## Commands and results

All counts below are passed / failed / skipped. Flutter commands use host SDK
cache access; no device was started. Tests use deterministic completers, event
counters, virtual frames and an injected quiet-period clock, not sleeps or
elapsed-time acceptance. The host SQLite alias is only a loader workaround for
the unchanged checkpoint controls.

```sh
# Screen iterations (the same command, with the log filename below).
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/real_screen_authority_test.dart

# First unchanged controls: 115 / 0 / 0.
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_stable_body_test.dart test/unit/services/display_generation_coordinator_test.dart test/unit/services/shared_lazy_section_work_coordinator_test.dart test/unit/services/lazy_section_repository_test.dart test/unit/services/lazy_book_session_test.dart test/unit/services/chapter_navigation_service_test.dart > /tmp/nalori-real-screen-controls-1.log 2>&1

# Add physical-cache controls: 133 / 0 / 0.
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_stable_body_test.dart test/unit/services/display_generation_coordinator_test.dart test/unit/services/shared_lazy_section_work_coordinator_test.dart test/unit/services/lazy_section_repository_test.dart test/unit/services/lazy_book_session_test.dart test/unit/services/chapter_navigation_service_test.dart test/unit/services/parsed_section_cache_service_test.dart > /tmp/nalori-real-screen-controls-final.log 2>&1

# Final combined run after accepted-section persistence guard: 153 / 0 / 0.
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/real_screen_authority_test.dart test/reader_contract/regression/lazy_stable_body_test.dart test/unit/services/display_generation_coordinator_test.dart test/unit/services/shared_lazy_section_work_coordinator_test.dart test/unit/services/lazy_section_repository_test.dart test/unit/services/lazy_book_session_test.dart test/unit/services/chapter_navigation_service_test.dart test/unit/services/parsed_section_cache_service_test.dart > /tmp/nalori-real-screen-final-combined.log 2>&1

# Recovery extension attempt: 33 stable-body passed; screen compilation failed (nullable fixture type).
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/real_screen_authority_test.dart test/reader_contract/regression/lazy_stable_body_test.dart > /tmp/nalori-real-screen-recovery-final.log 2>&1

# Historical unchanged controls: 16 / 8 / 0, exit 1.
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_snapshot_handoff_reopen_payload_test.dart test/reader_contract/regression/lazy_snapshot_handoff_characterization_test.dart test/reader_contract/regression/lazy_snapshot_handoff_screen_test.dart test/reader_contract/regression/lazy_snapshot_handoff_packing_test.dart test/reader_contract/regression/lazy_direct_target_entry_test.dart test/reader_contract/regression/lazy_source_address_entry_test.dart > /tmp/nalori-real-screen-historical.log 2>&1

# Unchanged ordinary P05/backward/admission/checkpoint controls: 132 / 0 / 0.
rtk proxy env LD_LIBRARY_PATH=/tmp/nalori-stable-sqlite rtk flutter test --no-pub --reporter expanded test/reader_contract/layout/reader_layout_contract_shared_test.dart test/reader_contract/layout/reader_font_evidence_gate_test.dart test/reader_contract/layout/reader_compatibility_classifier_test.dart test/reader_contract/pagination/reader_card_paginator_backward_preparation_test.dart test/unit/services/reader_checkpoint_store_test.dart test/reader_contract/pagination/canonical_display_segment_admission_test.dart > /tmp/nalori-real-screen-p05-checkpoint.log 2>&1

rtk dart format lib/screens/reader_screen.dart lib/services/lazy_book_session.dart lib/services/lazy_checkpoint_recovery.dart lib/services/lazy_section_repository.dart lib/services/parsed_section_cache_service.dart test/reader_contract/regression/real_screen_authority_test.dart
rtk dart analyze lib/screens/reader_screen.dart lib/services/lazy_book_session.dart lib/services/lazy_checkpoint_recovery.dart lib/services/lazy_section_repository.dart lib/services/parsed_section_cache_service.dart test/reader_contract/regression/real_screen_authority_test.dart > /tmp/nalori-real-screen-analyze-final.log 2>&1
rtk git diff --check
```

Screen-only log suffixes use `/tmp/nalori-real-screen-<suffix>.log` with the
screen command above redirected using `> ... 2>&1`:

| Suffix | Pass/fail/skip | Outcome |
| --- | --- | --- |
| pre-correction (lost log; traces above) | 0/9/0 | Product reds captured before correction |
| green-3 | 7/2/0 | Teardown timer and malformed legacy fixture |
| green-4 | 10/4/0 | Nearby-target terminal input, retry latch, recovery fixture and switch callback |
| green-5 | 0 executed | Compilation failure: accidental target-filter edit at another call site |
| green-6 | 5/9/0 | Closed-session persistence access during disposal |
| green-7 | 14/0/0 | Corrected lifecycle guard; repeated once, same count |
| green-8 | 16/1/0 | B06 exposed foreground read waiting behind physical disk writer |
| green-9 | 17/0/0 | Foreground cache miss avoids writer barrier |
| green-10 | 18/0/0 | Real post-publication hydration/index starts |
| green-11 | 19/0/0 | Old completion preserves newer failure |
| green-final | 20/0/0 | Hydration promotion and first eligible scheduler drain assertion |
| last-screen | 20/1/0 | B11 exposed missing save after accepted initial settlement |
| last-screen-2 | 19/2/0 | All behavior assertions passed; A03/B03 teardown left the shared statistics timer pending |
| last-screen-3 | 19/2/0 | Package teardown cleanup still ran after Flutter timer verification |
| last-screen-4 | 21/0/0 | Cleanup inside widget-test body; all final screen cases pass |

Earlier correction/debug runs were interrupted during fixture teardown: the
first run had initial-settlement fixture failures; another reached 6 passed / 3
failed before interruption; focused exact-recovery attempts reached one passed
before teardown. Their complete final counts were not retained and are not
claimed as completed validation. Focused commands used the screen suite with
`--name A08` or `--name 'A08.*exact'`; temporary log names were
`nalori-real-screen-recovery.log`, `nalori-real-screen-recovery-debug.log` and
`nalori-real-screen-recovery-2.log`. The latter reached one passed plus a teardown
failure before interruption. These fixture/debug runs are not product red proof.
The initial un-escalated Flutter/analyzer commands failed on SDK stamp access
before tests/analysis; approved reruns succeeded. Intermediate scoped analysis
reported 1 warning and 28 style infos, then 1 style info; these were corrected.
An interrupted final combined invocation did not create its log; the recorded
153-case run above is its completed rerun.

Historical S01 now passes: its previously caught deterministic failure settles
upstream as `false`. The old false-success trace remains in the entry/stable-body
ledger and in A05 above. The remaining reds are **R02, L02, H01–H04, K02, D02**.
D02 injects an uncooperative parser waiting on its original manual release;
its target remains queued until release, then revoked work throws
`SharedSectionWorkCancelled`. It cannot prove cancellation acknowledgement.
Its expectation and fixture are untouched. A01 proves bounded preemption via the
new approved cooperative gate and production scheduler without overlapping
parsers; B01/B10 separately prove identical-work promotion. No runtime defect was
preserved merely to keep a historical red.

The recovery-extension command reported **33 passed / 1 load failure**: all
unchanged stable-body cases passed, but B11's nullable test-fixture generic did
not compile. After correcting that type, `last-screen` reported 20/1/0 and
exposed the missing initial lazy save. Production now schedules new initial and
direct-target saves after actual accepted settlement. No assertion was weakened. The following 19/2 run failed only fixture teardown
on the shared statistics-service debounce timer; the final fixture cancels it with the existing `clearForTest` API inside the
widget-test body, after unmount/flush and before Flutter verifies timers. The
final mounted suite is **21 passed / 0 failed / 0 skipped**, exit 0.

Final scope commands (each ancestry check and protected-file diff exited 0):

```sh
rtk git branch --show-current
rtk git rev-parse HEAD
rtk git merge-base --is-ancestor a130bda2785a57ed2e94ae3fd0630572d3f9d010 HEAD
rtk git merge-base --is-ancestor 4ad765d8a56fe88d0b4917b351cdab2672d251b7 HEAD
rtk git merge-base --is-ancestor 008989ca3457e5ed6c3fdb48b8d1337f8fbbbea4 HEAD
rtk git merge-base --is-ancestor e6037812e5ca3785029963d91dacfae8acf2b4d1 HEAD
rtk proxy git diff --exit-code -- lib/models/lazy_stable_card.dart lib/models/reader_checkpoint.dart lib/services/lazy_stable_card_service.dart lib/services/reader_checkpoint_store.dart test/reader_contract/regression/lazy_stable_body_test.dart test/reader_contract/regression/lazy_snapshot_handoff_reopen_payload_test.dart test/reader_contract/regression/lazy_snapshot_handoff_characterization_test.dart test/reader_contract/regression/lazy_snapshot_handoff_packing_test.dart test/reader_contract/regression/lazy_source_address_entry_test.dart test/reader_contract/regression/lazy_direct_target_entry_test.dart test/reader_contract/layout test/reader_contract/fixtures test/unit/services/reader_checkpoint_store_test.dart
rtk git status --short
```

Final screen command and final historical S01 follow-up:

```sh
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/real_screen_authority_test.dart > /tmp/nalori-real-screen-last-screen-4.log 2>&1
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_snapshot_handoff_screen_test.dart > /tmp/nalori-real-screen-s01-final.log 2>&1
```

The final S01 follow-up printed **1 passed**, including
`SCREEN result=false ... presented=Bad state: A terminal continuation cannot be resumed.`
Its unchanged `tearDownAll` then stalled closing the singleton checkpoint store:
the new accepted initial save left SQLite continuations in the widget fixture's
fake async zone without further frame pumping. The process was interrupted
(exit 130), not counted as a complete run. A first cleanup-only follow-up
(`historical-final.log`) drained writes but still closed outside that zone; it
reached 16/8 and was likewise interrupted at teardown (exit 130).

The final S01 fixture moves the real checkpoint `close()` into the still-active
widget-test body, pumps its completion and asserts that it closed. No original
behavior assertion, expected card or failure value changed. This regression
fixture is outside frozen P02–P06 files. The final historical suite completes **16 passed / 8 failed / 0 skipped**,
exit 1, with S01 green and only the eight documented reds remaining. Its production terminal-failure expectation now passes because
of the authorized runtime settlement correction, not because of the cleanup.

```sh
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_snapshot_handoff_reopen_payload_test.dart test/reader_contract/regression/lazy_snapshot_handoff_characterization_test.dart test/reader_contract/regression/lazy_snapshot_handoff_screen_test.dart test/reader_contract/regression/lazy_snapshot_handoff_packing_test.dart test/reader_contract/regression/lazy_direct_target_entry_test.dart test/reader_contract/regression/lazy_source_address_entry_test.dart > /tmp/nalori-real-screen-historical-complete.log 2>&1
rtk dart format lib/screens/reader_screen.dart lib/services/lazy_book_session.dart lib/services/lazy_checkpoint_recovery.dart lib/services/lazy_section_repository.dart lib/services/parsed_section_cache_service.dart test/reader_contract/regression/real_screen_authority_test.dart test/reader_contract/regression/lazy_snapshot_handoff_screen_test.dart
rtk dart analyze lib/screens/reader_screen.dart lib/services/lazy_book_session.dart lib/services/lazy_checkpoint_recovery.dart lib/services/lazy_section_repository.dart lib/services/parsed_section_cache_service.dart test/reader_contract/regression/real_screen_authority_test.dart test/reader_contract/regression/lazy_snapshot_handoff_screen_test.dart > /tmp/nalori-real-screen-analyze-complete.log 2>&1
```

The first cleanup-only historical command was identical with its output directed
to `/tmp/nalori-real-screen-historical-final.log`. The final protected-file diff
excludes S01's cleanup-only change; its original assertions were reviewed in the
diff and remain byte-identical.

Final unique successful behavior/control coverage is **286 cases**: 21 new
screen cases, 33 unchanged stable-body cases, 100 unchanged service/cache controls,
and 132 unchanged P05/backward/admission/checkpoint controls. Repeated runs are
not added to that unique count. Final scoped analysis has **0 issues**; formatting
and whitespace checks pass.

## Remaining gate and next bounded prompt

No `SectionEndReceiptV1`, `LazySnapshotHandoffV1`, `publishSnapshotHandoff`,
two-handoff retention, backward transfer, whole-book reconstruction, chapter
scrubber or P07 implementation was added. Stable-body v1, lazy-checkpoint v2,
ordinary P05 validators, frozen tests and diagnostic source files are unchanged.
H01–H04/K02 still require their separately authorized handoff/adapter work.
Aggregate retention across handoffs is **not proven**. There is no device latency,
ANR or visual-quality acceptance claim. No existing checklist item's complete
acceptance criteria were closed: **P04 ARCHITECTURAL_CORRECTION_REQUIRED;
P06 REGRESSED_ON_DEVICE; progress 46/89; P07 UNSTARTED**.

Next bounded prompt (not executed):

> Audit only the remaining retention/handoff entry gate on this rescue branch,
> using the stable-body and real-screen authority proof ledgers. Preserve all
> formats, protected diagnostics, frozen oracles and historical red evidence.
> Inventory aggregate retained snapshots/cards/sources and pending work across
> two proposed handoffs, including backward transfer, without implementing a
> handoff or weakening P05. Produce deterministic red acceptance cases and a
> bounded ownership/budget plan for separate authorization. Account explicitly
> for the legacy D02 parser-fixture cancellation limitation. No device, P07,
> scrubber, whole-book reconstruction or Git mutation. Keep P04/P06 open, 46/89.


## Closure checkpoint verification — 2026-09-24

This section supersedes earlier final-tree verification claims for this
checkpoint. It is a single verification pass requested after implementation,
with **no production or test edits**. Only this completion report changed.
No retention or snapshot handoff work was begun, and no commit, staging, push,
reset, device run, schema change or scrubber work was performed.

### Scope and worktree identity

Branch: `rescue/change-039-device-failure-2026-09-19`.
Current HEAD before and after verification:
`e6037812e5ca3785029963d91dacfae8acf2b4d1`.
`git diff` contains eight tracked task files; the new report and new screen test
bring the task scope to **10 files**, exactly the list in this report.
The five pre-existing untracked artifacts (`nalori-last-anr.txt`,
`nalori-logcat.txt`, `nalori-meminfo.txt`, `regression.mp4`, `terminal_out.md`)
are excluded from the checkpoint. They were preserved.

SHA-256 hashes captured before the first suite were checked again after all
three suites. All 10 task files and all five pre-existing artifacts were
unchanged across test execution. After the report update, only this report's
hash differs. Thus the results below verify the same production and test tree;
no earlier run is counted toward this pass. The manifest snapshot is
`/tmp/nalori-close-003-before.json` (temporary host evidence).

### Completed single-pass commands

Working directory for every command:
`/home/uttam/Desktop/Antigravity Projects/Nalori`.
The documented SQLite alias was already available and was not recreated:
`/tmp/nalori-stable-sqlite/libsqlite3.so` points to
`/usr/lib/x86_64-linux-gnu/libsqlite3.so.0`.
The read-only availability check was:

```sh
rtk proxy ls -l /tmp/nalori-stable-sqlite/libsqlite3.so /usr/lib/x86_64-linux-gnu/libsqlite3.so.0
```

It exited 0. Flutter commands used approved access to the host SDK cache.
Each command below ran **once**, sequentially, on the current worktree:

```sh
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/real_screen_authority_test.dart > /tmp/nalori-close-003-screen.log 2>&1

rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_stable_body_test.dart test/unit/services/display_generation_coordinator_test.dart test/unit/services/shared_lazy_section_work_coordinator_test.dart test/unit/services/lazy_section_repository_test.dart test/unit/services/lazy_book_session_test.dart test/unit/services/chapter_navigation_service_test.dart test/unit/services/parsed_section_cache_service_test.dart > /tmp/nalori-close-003-controls-133.log 2>&1

rtk proxy env LD_LIBRARY_PATH=/tmp/nalori-stable-sqlite rtk flutter test --no-pub --reporter expanded test/reader_contract/layout/reader_layout_contract_shared_test.dart test/reader_contract/layout/reader_font_evidence_gate_test.dart test/reader_contract/layout/reader_compatibility_classifier_test.dart test/reader_contract/pagination/reader_card_paginator_backward_preparation_test.dart test/unit/services/reader_checkpoint_store_test.dart test/reader_contract/pagination/canonical_display_segment_admission_test.dart > /tmp/nalori-close-003-controls-132.log 2>&1
```

| Current-tree suite | Passed | Failed | Skipped | Exit | Completed reporter tail |
| --- | ---: | ---: | ---: | ---: | --- |
| Mounted real screen | 21 | 0 | 0 | 0 | `00:32 +21: All tests passed!` |
| Stable-body/service/cache | 133 | 0 | 0 | 0 | `00:59 +133: All tests passed!` |
| P05/backward/admission/checkpoint | 132 | 0 | 0 | 0 | `02:14 +132: All tests passed!` |
| Total distinct cases in this pass | **286** | **0** | **0** | — | All three reached completed teardown and process exit |

Progress updates were given after each suite. The long backward-preparation
case was monitored: it continued running, and the command completed normally.
There were **no hangs, interruptions or reruns** in this pass. Reporter durations
and the approximately 30-minute execution safeguard are operational records,
not performance-test assertions. This pass began at 12:21:56 UTC and finished
well within the safeguard. Historical suites were **not rerun** in this pass;
their earlier 16/8 result is classified below and is not included in the 286.

### Default isolate cancellation: exact unverified behavior

Historical status at the close-only checkpoint: the gap below is now closed
by the separately authorized default-parser host verification appended below.
The original search findings and cooperative-parser limitations are preserved.

**No existing test was found that exercises cancellation of the DEFAULT isolate
parser and asserts physical worker exit before single-slot reuse.** Search of
`test/` for isolate/worker exit, cancellation and parser references, followed by
inspection of the repository, coordinator, session, derived-index and mounted
screen tests, found these distinct kinds of evidence:

- `test/reader_contract/regression/real_screen_authority_test.dart:200` installs
  an injected parser callback. It waits on `request.cancellation!.checkpoint`
  at line 210, then delegates to `EpubParserService` in that callback; it does
  not invoke `_defaultLazySectionParser`. A01 starts at line 344. Its assertions
  at lines 363–369 require target 5 before the manual gate is released,
  `launchQuanta[5] == cancelledQuantum + 1`, and `maximumParsers == 1`.
  These prove cooperative callback cancellation and scheduler-slot ordering,
  **not exit of a spawned isolate**. The concurrency counter counts injected
  callback lifetimes, not operating-system/VM workers.
- `test/unit/services/lazy_section_repository_test.dart:263`, “interaction
  cancels active background parse before retention or cache write,” injects
  its parser at line 275. It manually releases the gate after cancellation,
  then asserts retained count 0, two parser invocations after retry, and retained
  spine `[0]` (lines 306–309). It has no default-worker exit assertion.
  The close/hydration case at line 197 also injects a manually released parser.
- `test/unit/services/shared_lazy_section_work_coordinator_test.dart:121`
  cancels a **queued** operation and asserts `SharedSectionWorkCancelled`,
  zero invocations and zero active jobs. No isolate is launched.
- `test/unit/services/lazy_section_repository_test.dart:51` does use the
  default parser: two same-target requests yield identical results and retained
  spine `[1]`. It tests normal join/completion, not cancellation. Normal default
  parsing in the other repository/session controls also supplies no worker-exit
  ordering assertion. The derived-index cancellation case at
  `test/unit/services/derived_book_index_service_test.dart:315` cancels before
  launch and only checks empty records and `isRunning == false`.

Source inspection shows the intended sequence in
`lib/services/lazy_section_repository.dart:964`: the default parser spawns its
worker with `onExit`; the cancellation branch calls `worker.kill` at line 989,
awaits `exited` at line 990, then throws `SharedSectionWorkCancelled`.
The coordinator releases `_runningJobs` in `whenComplete` at line 291.
That implementation sequence is **not runtime proof** of cancellation delivery,
physical exit, or lack of worker overlap. The exact missing proof is a test that
uses the default parser, observes an actually launched/held isolate, cancels it,
observes its exit, then asserts the next target launches only after that exit
with at most one live parser worker. No such test or seam was added in this
close-only pass. This coverage gap remains explicitly open at checkpoint.

### Individual historical-failure classification

These classifications use unchanged test assertions, current production source,
and the prior completed historical log. “Intentional red” does not imply that
every failure is merely an obsolete fixture.

| Failure | Classification | Exact remaining meaning and evidence |
| --- | --- | --- |
| R02 | Legacy-format characterization | `lazy_snapshot_handoff_reopen_payload_test.dart:291` compares historical raw card payload/slices/resolved-layout components across expanded and owning-only windows. Stable identity equality does not make the old dense/window-dependent payload byte-identical. This is not a failure of the new stable-body v1/v2 recovery suite. |
| L02 | Legacy-format characterization | `lazy_snapshot_handoff_reopen_payload_test.dart:329` exercises the old ordinary checkpoint resolver. At line 405 it expects no semantic restore when only the resident window changed; the historical result was `semanticAnchor` / `layout_changed`. The new explicit lazy migration/unavailable screen route is separate. The legacy resolver behavior remains characterized, not rewritten. |
| D02 | Test-double limitation | `lazy_direct_target_entry_test.dart:41` injects a parser that waits only on `release.future` at line 45 and never observes cancellation. Demand stays queued behind that callback; after manual release the revoked work throws cancellation. It cannot exercise default-isolate preemption. This classification does **not** close the default-worker coverage gap above. |
| H01 | Unresolved production defect | `lazy_snapshot_handoff_characterization_test.dart:66`: exhausting the pinned input still yields `terminalBookEnd` despite a known readable successor. Section-input exhaustion and real book end remain conflated in this path. |
| H02 | Unresolved production defect | `lazy_snapshot_handoff_characterization_test.dart:90`: loading the successor leaves the pinned session unchanged; forward continuation remains rejected as terminal. No authorized snapshot transition exists yet. |
| H03 | Unresolved production defect | `lazy_snapshot_handoff_characterization_test.dart:121`: both speculative and demand forward requests at that suffix remain rejected. Scheduling correction alone does not provide the missing cross-snapshot continuation. |
| H04 | Unresolved production defect (predicate-contract mismatch) | `lazy_snapshot_handoff_characterization_test.dart:151` requires `readerShouldSurfacePreparationFailure('lazy_forward_boundary') == true`; the unchanged helper at `reader_screen.dart:964` still returns false. This is specifically the helper's reason classification. The newly corrected unconditional failure settlement means S01 can now present/settle failure through another path; H04 alone does not prove that current UI presentation is still hidden. It is not a legacy format or parser-double issue, and should not be described solely as a handoff implementation requirement. |
| K02 | Unresolved production defect/capability gap | `lazy_snapshot_handoff_packing_test.dart:200`: the production rendering adapter rejects an old resolved card under the successor contract. Its strict P05 rejection is correct without transfer authority; the missing supported way to retain/render that card across the transition is unresolved. No validator relaxation is authorized. |

Classification totals: **2 legacy-format characterizations, 1 test-double
limitation, 5 unresolved production defects/capability gaps**. No expectation
was edited, and no historical failure was suppressed in this pass.

### Exact checkpoint manifest and disposition

These are the **only 10 files suitable for this task's checkpoint commit**;
this report does not create that commit:

```text
lib/screens/reader_screen.dart
lib/services/lazy_book_session.dart
lib/services/lazy_checkpoint_recovery.dart
lib/services/lazy_section_repository.dart
lib/services/parsed_section_cache_service.dart
test/reader_contract/regression/real_screen_authority_test.dart
test/reader_contract/regression/lazy_snapshot_handoff_screen_test.dart
docs/development/nalori-real-screen-authority-proof.md
docs/development/nalori-lazy-snapshot-handoff-entry-proof.md
docs/development/nalori-reader-reliability-change-log.md
```

Current-tree requested verification is complete: **21 + 133 + 132 pass**, all
exit 0. The checkpoint retains the explicitly untested default-isolate
cancellation/exit/reuse guarantee and the eight individually classified
historical reds. Static analysis was not rerun in this one-pass follow-up;
its earlier clean result remains historical, not a new result. `git diff
--check` and the protected-format/frozen-file diff check exited 0.

No retention/handoff audit or implementation was started. The earlier next-task
prompt remains unexecuted. P04 and P06 stay open at **46/89**, P07 unstarted.
This closes the requested verification/reporting pass, not the broader P04/P06
acceptance gates.


## Default parser isolate verification — 2026-09-25

This follow-up closes only the default-parser cancellation/physical-exit/
single-slot-reuse verification gap. Baseline and unchanged HEAD:
`89b5e45c346987725f2b638d77b722da5a496b6d`, on
`rescue/change-039-device-failure-2026-09-19`. The prior **286/286** final-tree
verification remains historical evidence for that baseline; it was **not rerun**
and is not counted as verification of this follow-up's edits.

### Narrow change and proof mechanism

The repository accepts optional `LazyParserIsolateTestAccess`. It does not
replace the parser: tests omit the repository's `parser` argument and execute
`_defaultLazySectionParser` → production `Isolate.spawn` → `_parseSectionWorker`
→ `EpubParserService.parseLazySection`. Only when the optional hook is supplied,
the real worker sends a startup acknowledgement containing a resume port and
waits on that port before parsing. The parent observes spawn requests, results,
kill calls and the existing VM `onExit` notification. Test callbacks themselves
stay in the parent isolate; only a send port crosses into the worker.

The production cancellation token, `Isolate.immediate` kill, awaited exit,
post-result authority check and coordinator `whenComplete` slot release are
unchanged. No worker lifecycle defect was exposed, so no correction to those
algorithms was needed. The optional startup branch adds an async worker return
type; with no hook, parsing proceeds directly. I04 explicitly exercises that
unhooked path.

`started` is an acknowledgement from inside the actual worker. `exited` is
observed only from its VM exit port, not inferred from cancellation or future
settlement. The counter conservatively spans **before spawn through observed
exit**. Its maximum of one bounds simultaneously live physical workers by one;
it is not a sampled OS thread count. I01 also asserts the old observed exit
precedes the successor's spawn request, and zero active coordinator jobs after
completion. This closes the gap that the earlier injected cooperative A01
could not prove.

All fixtures use the existing small three-section EPUB builder. No sleeps,
large inputs or elapsed-time assertions arrange the races. Per-test 45-second
timeouts detect hangs only. No timeout fired. These are host lifecycle proofs,
not device or throughput measurements.

### Focused assertions (five test cases)

| Test | Production evidence and assertions |
| --- | --- |
| I01 | Hold the actual speculative worker after its startup acknowledgement; submit unrelated foreground `prepareNavigation`. Both matching speculative waiters throw `SharedSectionWorkCancelled`; old worker is killed and exits before the new worker spawns. Exactly one old spawn, maximum live interval count one, successor window/current location/loaded and retained section are all section 1, and active jobs end at zero. Sending to the dead worker's resume port cannot resurrect a result. No old result, physical write or old cache entry exists. |
| I02 | Close the real session with an acknowledged active worker and another queued request. Active and queued requests both cancel; exit precedes close completion, queued worker never spawns, active jobs are zero and current/loaded/retained state is empty. No result or physical cache entry survives. |
| I03 supersession | Let the real worker parse and return its result. At the parent's result observation, submit the next foreground request before production admission. The old navigation future throws cancellation; only the successor enters the session/window and retained cache. Old worker exit still precedes successor spawn; no physical write or old cache entry exists. |
| I03 close | Close at the same actual-result observation boundary. Old navigation throws cancellation after worker exit; close completes with empty session/retained state, no active jobs and no physical write or old cache entry. |
| I04 | No hook and no injected parser. Production parsing returns section 1 with matching source checksum, current parser version, expected `Section 2 text.` content and `s2` anchor. Navigation succeeds and coordinator jobs drain. |

I03 observes the real parser result before its cancellation admission check;
it does not fabricate a parsed section or successful publication. The rejected
old navigation supplies no prepared window to publish or persist. These focused
tests cover repository/session admission and physical worker lifecycle; mounted
ReaderScreen card publication remains covered by the prior 21-case suite,
which was not repeated here.

### Actual final-run lifecycle traces

Spine indices below are zero-based. These are recorded final-run traces, with
the necessary ordering edges asserted by the tests:

```text
I01 [spawnRequested:0, started:0, killSent:0, exited:0,
     spawnRequested:1, started:1, resultReceived:1, exited:1]
I02 [spawnRequested:0, started:0, killSent:0, exited:0, closeCompleted]
I03-supersede [spawnRequested:0, started:0, resultReceived:0,
              foregroundRequested, exited:0, oldSettledCancelled,
              spawnRequested:1, started:1, resultReceived:1, exited:1]
I03-close [spawnRequested:0, started:0, resultReceived:0,
           closeRequested, exited:0, oldSettledCancelled]
```

Every observed case recorded `maxSpawnToExit=1` and `writes=[]`.

### Commands and completed results

Working directory: `/home/uttam/Desktop/Antigravity Projects/Nalori`.
Host Flutter/Dart SDK cache access was approved. SQLite overrides were not
needed for these focused service tests. Initial execution:

```sh
rtk dart format lib/services/lazy_section_repository.dart test/unit/services/default_lazy_parser_isolate_test.dart
rtk flutter test --no-pub --reporter expanded test/unit/services/default_lazy_parser_isolate_test.dart > /tmp/nalori-default-isolate-focused-1.log 2>&1
rtk flutter test --no-pub --reporter expanded test/unit/services/lazy_section_repository_test.dart test/unit/services/shared_lazy_section_work_coordinator_test.dart test/unit/services/lazy_book_session_test.dart > /tmp/nalori-default-isolate-controls.log 2>&1
rtk dart analyze lib/services/lazy_section_repository.dart test/unit/services/default_lazy_parser_isolate_test.dart
```

Initial format exited 0. Focused tests: **5 passed, 0 failed, 0 skipped**, exit 0.
Affected controls: **39 passed, 0 failed, 0 skipped**, exit 0. Initial analysis
exited 0 but reported two info findings (`avoid_void_async` and
`curly_braces_in_flow_control_structures`). Both were corrected in the added
code. This justified one final focused verification of those edits:

```sh
rtk dart format lib/services/lazy_section_repository.dart test/unit/services/default_lazy_parser_isolate_test.dart
rtk flutter test --no-pub --reporter expanded test/unit/services/default_lazy_parser_isolate_test.dart test/unit/services/lazy_section_repository_test.dart test/unit/services/shared_lazy_section_work_coordinator_test.dart test/unit/services/lazy_book_session_test.dart > /tmp/nalori-default-isolate-final.log 2>&1
rtk dart analyze lib/services/lazy_section_repository.dart test/unit/services/default_lazy_parser_isolate_test.dart
rtk proxy git diff --check
```

Final format: exit 0, two files checked, no formatting changes.
Final focused plus affected controls: **44 passed, 0 failed, 0 skipped**, exit 0,
completed reporter tail `00:01 +44: All tests passed!`, process exited normally.
Final scoped analysis: **No issues found**, exit 0. Diff check: exit 0.
The 44 are **5 focused + 39 controls**, not 88 distinct cases across the two
runs. No command hung and no broad matrix was repeated. Only this report was
edited after the final test run.

### Checkpoint files and remaining gates

Exactly three files belong to this follow-up checkpoint:

```text
lib/services/lazy_section_repository.dart
test/unit/services/default_lazy_parser_isolate_test.dart
docs/development/nalori-real-screen-authority-proof.md
```

The five pre-existing untracked artifacts remain outside this scope and were
not edited. No existing test expectations, protected diagnostics, frozen
oracles, stable-body/checkpoint schemas or P05 validators changed. No commit,
staging, push, reset, device run, handoff, retention transfer or scrubber work
was performed.

The requested default-parser host cancellation/exit/reuse gap is closed. The
prior eight historical failures and their individual classifications remain
unchanged; no historical suite was rerun or suppressed. This follow-up provides
no snapshot handoff or retention-transfer acceptance. P04 and P06 remain open,
progress **46/89**, P07 unstarted. No additional implementation is authorized by
this completion report.
