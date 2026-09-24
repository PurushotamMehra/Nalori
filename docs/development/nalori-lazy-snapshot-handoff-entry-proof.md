# IMPLEMENT-P04-LAZY-SNAPSHOT-HANDOFF-001: stopped entry proof

Current prerequisite implementation: [IMPLEMENT-P04-LAZY-STABLE-BODY-002](nalori-lazy-stable-body-proof.md).
That report records the authorized new payload versions and legacy recovery
policy. The historical CHANGE-041 findings and red expectations below remain
unchanged. Screen and retention gates remain open; progress is 46/89.

Current screen-authority correction: [IMPLEMENT-P04-REAL-SCREEN-AUTHORITY-003](nalori-real-screen-authority-proof.md).
It records real-screen red/green evidence and the corrected failure settlement;
the historical findings below remain evidence. Retention/handoff entry remains
open, and no checklist count changes (46/89).

## Current continuation — CHANGE-20260921-041 (2026-09-21)

**Stopped at the stable-address/legacy-recovery entry boundary. All three
implementation-entry gates remain unsatisfied. Production handoff is not
authorized.** This section supersedes earlier “current result” wording below;
prior results remain historical evidence.

### Captured state and scope

Branch `rescue/change-039-device-failure-2026-09-19`; entry/final HEAD
`008989ca3457e5ed6c3fdb48b8d1337f8fbbbea4`. Its three immediate ancestors are
`7f226c7268fbcc1212eab82cb4eb4b955f364f32`,
`4ad765d8a56fe88d0b4917b351cdab2672d251b7`, and immutable recovery
`a130bda2785a57ed2e94ae3fd0630572d3f9d010`. Tracked tree was clean on entry;
`nalori-last-anr.txt`, `nalori-logcat.txt`, `nalori-meminfo.txt`,
`regression.mp4`, and `terminal_out.md` were already untracked and remain
untouched. No production file, persistent schema/version, protected evidence,
or frozen oracle changed. No device, commit/amend/reset/rebase/push or P07 work.

Entry CHANGE-040 state: H01–H04 red / H06 green; S01 red / K01 green / K02
ordinary-adapter red; R01 green / R02 red. Existing screen seam and owner
dual-authority decision remain in force. That decision is not being reopened.

### Plan-only amendments

Design §§11–14 and reliability-plan §7A now record:

- Adjacent receipt/handoff and direct stable-target preparation as different
  operations. Chapter 1 → 6 must parse/paginate/handoff through zero
  intermediate chapters; retain the old readable card until target acceptance,
  preempt speculative work, join identical demand, and let latest foreground
  demand own publication.
- First-card ordering and A059 acceptance targets: prepared ≤100 ms,
  prefetched boundary/cached direct ≤250 ms, uncached ideal ≤500 ms/hard 1 s,
  zero awaited hydration/index/cache-write work first, one-quantum preemption,
  injected-clock ≤8 ms cooperative UI slices, zero ANR including debug.
  These are requirements, **not achieved latency claims**.
- `DEFERRED-UX-CHAPTER-CARD-SCRUBBER-001`: UNSTARTED, outside the historical
  89-task denominator, after P06 device and stable-address/reopen gates.
  Chapter-only navigation/counting, no invented total or first-card delay,
  progressive/disabled/bounded-completion choice left for later design.
  No scrubber implementation, widget or UI-test edit.

### Address audit and representation proposal

[The source-address inventory](nalori-lazy-source-address-inventory.md) gives
exact files/symbols for production `payload.i`, `BookChunk.index`,
`sourceOrdinalHint`, codecs, projection, bookmark/annotation and checkpoint
boundaries. Resolved analysis found 321 expression records (280 unique
file/line/kind records), grouped into 145 file/symbol entries, with manual
declaration/string-codec/indirect-consumer supplements. Runtime, local,
persisted, identity-bearing, ordering and diagnostic uses are distinguished.

Proposed minimal address:
`(publicationSpineAuthorityDigest, exactSectionIdentityDigest, localSourcePosition)`.
Source canonical bytes, ordered membership, offsets/structural ownership, and
all packing/font/image/P05 inputs remain independently authenticated. Runtime
dense projections sit outside the stable body. See design §12 for text/table/
list/image offsets and empty/oversized evidence rules. **No durable encoding is
selected and no existing accepted body is rewritten.**

New `lazy_source_address_entry_test.dart` uses actual lazy parsing and real
memory-pressure/section reload. Its test-only comparison witness binds the full
parsed-section identity and ordered records. A01/A02 prove resident-window
independence and nonaliasing of equal local positions; eight A03 mutations
(insert/remove/reorder/text/parser/dependency/image-byte injection/structure)
are rejected against that witness. All **10 pass**.

This is deliberately limited evidence: those eight mutations exercise the
candidate witness, **not a newly installed production lazy validator**. The
image case injects contradictory bytes into a parsed text record; it is not a
claim that a real decoded-image handoff was admitted and rejected. The witness
does not generate display cards or validate handoff prefix admission. The
production-pagination and real snapshot-bound P05 evidence remains R01/R02 and
L01/L02; none of those bodies or validators is normalized.

| Requested stable-address proof | Evidence / remaining gate |
| --- | --- |
| A+B vs B-only stable address, section-local nonaliasing | A01/A02 green for the proposed comparison tuple and existing stable owner/signature (R01); exact emitted body still R02 red. |
| Source insertion/removal/reorder/mutation; parser/dependency | A03 witness controls green; production typed lazy admission remains unimplemented. |
| Font/layout/renderer/pagination/image/structure | Unchanged 90 P05 controls pass, including F001–F211 mutations. These are strict ordinary-path controls, not proof of the proposed lazy split. |
| Eviction/bounded section reload | A01 passes through production pressure/reload; at most three retained sections asserted. Exact stable card body after eviction is not proved. |
| Backward regeneration | Ten unchanged fixed-snapshot backward tests pass. Cross-window backward byte equality, empty/oversized transfer and two-handoff bounds remain unproved. |
| Fresh reopen | R01 same-history signature/checkpoint/B-only regeneration green; R02 A+B→B-only exact payload/slices/layout red. |
| Ordinary/full-snapshot P05 | Production unchanged; 90 controls green. F202/F208 membership checks remain strict. |
| Invalid prefix / all lazy packing mutations | Not implemented after representation/recovery stop; no prefix bypass or alternate validator introduced. |

R02 still fails exactly:
`Which: at location ['payload']['i'] is <0> instead of <14>`.
B's signature and checkpoint are equal under stable packing, but card JSON,
slice hints and source-bound resolved layout differ. A test-only address tuple
does not fix this. No existing red expectation was rewritten.

### Direct target: service evidence and exact missing screen seam

`lazy_direct_target_entry_test.dart` uses a new isolated seven-section EPUB
builder, real repository/session and injected parser delegates that call the
production parser. Deterministic completion gates/queue state, not elapsed time,
decide the assertions.

- D01 green: after chapter 1, `resolveChapterTarget` and
  `prepareNavigation` for chapter 6 start parsers `[0,5]`; chapters 2–5
  have **zero** starts.
- D02 red: hold a chapter-7 `boundaryPrefetch` parser, queue chapter 6 as
  `explicitNavigation`, observe queued priority before release. It cannot
  start before the held parse is released. Final starts `[0,6,5]`;
  intermediate starts still zero. Exact failure:
  `Expected: true; Actual: <false>`;
  `Explicit target remains queued behind held boundaryPrefetch; no preemption before parser release.`

This is a **service** characterization, not an actual ReaderScreen warmup/
publication test. Existing `ReaderAdjacentWorkTestAccess` only delegates
adjacent forward/warmup/hydration and reports owned publication/failure state.
It cannot invoke the private `_navigateToStableLocation` or await first target
card acceptance. Exact missing seam: a narrow state-bound delegation to that
real entry method plus read-only target ownership and real first-acceptance/
settlement observation, using existing repository/pagination gates. No new
screen API or alternate coordinator was added.

Old visible-card retention, latest/identical direct requests, screen warmup
preemption and first-card order are therefore **mandatory pre-handoff gates**,
not inferred from `prepareNavigation` completion. Source audit also shows
`LazySectionRepository._loadSectionUnshared` at :592 awaits
`_cache.writeSection` before returning: the required no-awaited-physical-write
path is not achieved. No fix or production scheduling change is authorized by
this proof result.

### Executable legacy persistence/recovery and UI limitation

Extended the existing reopen test without altering R01/R02 assertions. L01/L02
use the production paginator, contracts rebuilt against each actual lazy
snapshot, real `ReaderCheckpointStore` SQLite encode/write/close/reopen and
`ReaderCheckpointCoordinator.resolveRestore`. Legacy mode uses the original
source-bound P05 `contract.identity`, not the proposed stable packing digest.

L01 **passes**: when the original A+B window is supplied as known evidence,
bounded regeneration after persistence returns `exactSignature` and identical
card body, ordered slices and resolved layout. This refines earlier uncertainty:
legacy exact reconstruction is possible **conditionally**, not proven impossible.

L02 **fails**: reconstruct only B, with equal resolved layout metrics, and the
source-bound composite changes. Actual trace:

```text
LEGACY changedWindow strategy=semanticAnchor reason=layout_changed checkpointPreserved=true
Expected: null
  Actual: <Instance of 'ReaderRestoreResolution'>
Window-only F202/F208 change is not genuine reflow; preserve legacy checkpoint and require explicit exact-unavailable.
```

The same-layout/missing-signature branch returns null, as a passing control
inside L02. But the actual B-only current fingerprint reaches the changed-layout
semantic branch. Tests only observe it: the old stored/current checkpoint bytes
are intact and ordinary checkpoint writes remain disabled. Nothing was
semantically settled, reset, deleted, re-signed or silently migrated.

This is executable **recovery-coordinator evidence, not mounted UI evidence**.
Source inspection: `ReaderScreen._resolveCanonicalCheckpointRestore` :8648
passes the active composite to the coordinator; the caller at :3795 handles
non-null restore results. `_buildReaderPreparationError` :3016 offers generic
Retry/Back to library and clears failure/rebuild state; it is not a typed legacy
exact-unavailable view. The file-open error's “Remove unavailable entry” is a
different path, not a recovery decision. No button was invoked or UI behavior
claimed from these source reads. Required further proof: mount a stored legacy
checkpoint through actual initial restore, hold target generation, and observe
exact-unavailable/retry and write blocking through production state. Existing
adjacent handle has no restore-resolution/first-acceptance observation; this
remains a gate pending the owner recovery outcome.

**Persistence conclusion:** schema-free stable-body/address reopen is **not
demonstrated**. Old checkpoint type compatibility and R01's equal codec payload
do not encode historical body/layout provenance. A legacy composite can verify
a candidate original window, as L01 proves, but we have not proved that every
historical candidate can be enumerated deterministically within bounds, or
that cold restore can recover its provenance. Do not conflate R01's two
stable-packing histories with L01's window-dependent legacy signature.

Stop for DEC-REQ-001/002 if bounded exact proof is unavailable. Explicit
alternatives in design §13: separately authorized versioned lazy address/
checkpoint migration preserving originals; typed exact-unavailable with user
data preserved and owner-chosen retry/cold-reader UX; bounded authoritative
candidate reconstruction with strict equality and global caps; explicit
restoration UX decision for exhaustion. None is selected implicitly.

### Observed work, gates and invariants

Per **new paginator reconstruction session** maxima: **2 retained cards,
1 continuation guard, 18 sources, 4 consumed generation entries and 4 entered
sources**. B-only has four sources. L01 constructs original and reopened
sessions sequentially; each is closed. Keeping the original card as a test
comparison oracle is not a measured live handoff lineage. A01 asserts
session-retained sections ≤3 but does not measure aggregate source/guard storage
across retired sessions.

These numbers do **not** demonstrate two handoffs or global nonmultiplication
of 96 cards / 25 guards / 432 sources / 110–158 work entries. No oversized
source-bound reconstruction, empty intervening handoff, whole-book-free backward
transfer, or universal legacy reconstruction bound was claimed. The existing
micro-fixture's eager setup parse is not production bounded-reopen evidence.

| Implementation-entry gate | Final status |
| --- | --- |
| 1 — actual screen authority/failure settlement | NOT SATISFIED. Historical S01 red and remaining warmup/hydration/eviction/close/switch gaps unchanged; direct target first-card/publication observation also missing. |
| 2 — stable packing/source authority/reopen/legacy | NOT SATISFIED. Owner dual authority accepted; representation/persistence unresolved, R02 and L02 red; typed lazy validation/mutation/UI gates incomplete. |
| 3 — two handoffs/retention/backward | NOT SATISFIED. Fixed-snapshot controls pass, but transfer/empty/oversized/global-bound evidence absent. |

H01–H06 characterization truth is preserved: H01–H04 red/H06 green rerun;
H05's screen-settlement evidence remains historical S01 and incomplete cases.
No false “no successor,” replacement publication, snapshot mutation, terminal
clearing or validation relaxation. P04 **ARCHITECTURAL_CORRECTION_REQUIRED**;
P06 **REGRESSED_ON_DEVICE**; **46/89**; P07 **UNSTARTED**.

### Commands and exact results

Final combined entry proof:

```sh
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_source_address_entry_test.dart test/reader_contract/regression/lazy_direct_target_entry_test.dart test/reader_contract/regression/lazy_snapshot_handoff_reopen_payload_test.dart
```

**13 passed / 3 failed / 0 skipped**, exit 1: source witness 10/0; direct target
1/1; reopen 2/2. Failures D02, R02, L02 exactly as above.

Unchanged controls plus original red characterization:

```sh
rtk flutter test --no-pub --reporter expanded test/reader_contract/layout/reader_layout_contract_shared_test.dart test/reader_contract/layout/reader_font_evidence_gate_test.dart test/reader_contract/layout/reader_compatibility_classifier_test.dart test/reader_contract/pagination/reader_card_paginator_backward_preparation_test.dart test/reader_contract/regression/lazy_snapshot_handoff_characterization_test.dart
```

**101 passed / 4 failed / 0 skipped**, exit 1: P05 90/0; backward preparation
10/0; characterization 1/4. H01 actual `terminalBookEnd`; H02/H03
`terminalStateContradiction: A terminal continuation cannot be resumed.`;
H04 `Expected: true; Actual: <false>`. P05 retained-record maxima remain
4696-byte contract / 1462-byte block / 1728-byte card; not handoff memory bounds.

Focused runs during this continuation:

```sh
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_direct_target_entry_test.dart
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_snapshot_handoff_reopen_payload_test.dart --name 'L0'
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_source_address_entry_test.dart
```

Direct: **1/1/0**, exit 1. Legacy: **1/1/0**, exit 1. Source final:
**10/0/0**, exit 0. Earlier source setup run: **9/1/0**, exit 1
(`Bad state: No element` from assuming an image in the lazy fixture section);
fixed to explicit image-byte injection, not counted as a product failure.
An earlier L0 SQLite setup attempt was cancelled (exit 130, no completed test
count) because the store's initial future was created in the widget fake zone;
constructing it in `tester.runAsync` corrected setup. No semantic assertion
was relaxed. One final rerun lost its tool-session result during continuation;
it was repeated to captured completion, with no inferred outcome.

```sh
rtk dart format test/reader_contract/regression/lazy_source_address_entry_test.dart test/reader_contract/regression/lazy_direct_target_entry_test.dart test/reader_contract/regression/lazy_snapshot_handoff_reopen_payload_test.dart test/reader_contract/regression/support/lazy_address_fixture.dart
rtk dart analyze test/reader_contract/regression/lazy_source_address_entry_test.dart test/reader_contract/regression/lazy_direct_target_entry_test.dart test/reader_contract/regression/lazy_snapshot_handoff_reopen_payload_test.dart test/reader_contract/regression/support/lazy_address_fixture.dart
rtk git diff --check
rtk git branch --show-current
rtk git log -4 --format=%H
rtk git status --short
```

Final scoped analyzer: **No issues found**, exit 0. Whitespace check: clean.
Initial analysis found three style infos (two braces, one redundant default); corrected.
The inventory's commands/method are recorded in its own audit section.
No host result substitutes for ordinary profile/release A059 acceptance.

### Next bounded prompt (entry proofs only)

> Continue only IMPLEMENT-P04-LAZY-SNAPSHOT-HANDOFF-001 on
> rescue/change-039-device-failure-2026-09-19 at HEAD
> 008989ca3457e5ed6c3fdb48b8d1337f8fbbbea4 with the uncommitted
> CHANGE-20260921-041 proofs. Preserve all four named commits, protected
> diagnostics, frozen oracles and 46/89. Read design §§11–14, the source-address
> inventory and current entry report. First propose the smallest production
> lazy stable-body/source-address contract and prove whether exact encode,
> store reopen and bounded production regeneration can use existing persistence
> semantics without reinterpreting old records. Keep runtime dense projections
> outside exact identity; retain every P05/source/font/image/structure check.
> Do not normalize existing card bytes or turn R02 green by changing equality.
> Prove bounded legacy candidate discovery from authoritative evidence; if it
> cannot be proved, obtain DEC-REQ-001/002 owner choice among versioned
> migration, preserved typed exact-unavailable, bounded reconstruction and
> explicit recovery UX before implementing that choice. Specify/use only the
> narrow real-screen direct-target/first-card observation seam; prove zero
> intermediate parses, old readable-card retention, latest/identical ownership
> and speculative preemption with deterministic gates. Complete remaining
> screen failure and aggregate two-handoff/backward entry proofs only within
> those approved contracts. No production handoff transaction, scrubber,
> schema/version change, frozen-oracle edit, device, P07 or git mutation.
> Stop on any further architecture/persistence/UX decision. Report each gate
> separately; production handoff needs a separately authorized bounded task.


## Continuation after owner dual-authority decision

The following is the current result; the original entry-proof record below is
preserved as history. Entry HEAD is now
`7f226c7268fbcc1212eab82cb4eb4b955f364f32` on
`rescue/change-039-device-failure-2026-09-19`. Tracked files were clean on entry;
the same five diagnostic files were untracked. Recovery and CHANGE-040 commits
remain unchanged. No production file was edited in this continuation.

The owner has authorized a strict dual-authority resolved-card validation path:
stable LazyPackingIdentityV1 for measurement/rendering/packing; exact separate
snapshot/source/prefix membership; ordinary non-lazy F202/F208 behavior remains
strict. The prior request for that decision is **resolved**. The old K02 test
still exercises the ordinary adapter, so its failure must not be mistaken for
a refutation of the newly approved lazy validation path.

Before implementing that path, a production-paginator precondition test found
a **different stop condition: window-dependent card payload/slice semantics
prevent history-independent exact-byte reopen**. This is not a request to undo
or repeat the owner's dual-authority decision.

### New executable evidence

Added `test/reader_contract/regression/lazy_snapshot_handoff_reopen_payload_test.dart`.
It uses independent real lazy repositories/indexes/parser runs and fresh parsed
cache directories for A+B, B alone, and a further B-only reopen. Each repository
is closed before the next opens. The existing controlled layout harness supplies
the environment and production font resolver. Each P05 contract is then built
again with the **actual lazy snapshot's** publication, parser, source revision
and snapshot digest, using the real font gate and contract builder. No F202/F208
field is copied or overridden, and no validator is removed.

The test computes the design's stable packing tuple from actual index metadata,
parser/dependency/structural revisions and P05 metric/renderer/pagination/font
evidence. This is a test-only digest input to the existing production paginator,
not a new typed authority or proof of authenticated handoff. Both sessions start
at B's validated hard section root and run the production paginator and canonical
identity builder. A is not paginated to reach B. B is the genuine final section;
no false no-successor claim is used to alter H01–H03.

R01 is a green counterexample/control:

- Packing digest, physical card signature, source owner/digest, and resolved
  block fingerprint are identical between the two histories.
- The production `ReaderCheckpoint.create` / `fromPayload` codec produces
  identical valid checkpoint payloads and integrity checksums, including the
  actual stable locations emitted by each lazy window. These in-memory codec
  checks are not a checkpoint-store or restoration-UI test.
- Historical A+B emits card JSON `i: 14` and slice `sourceOrdinalHint: 14`.
  B alone emits `i: 0` and `sourceOrdinalHint: 0`. No field is normalized.
- P05 `contractIdentity` and physical card components also differ, as expected
  for distinct source-bound contracts. The ordinal payload mismatch exists
  independently of those P05 fields and of the rendering membership check.
- Fresh B-only reopen reproduces the B-only signature, card JSON, slices and
  resolved layout exactly. The failure is not nondeterministic parsing/layout.

R02 is the intended red entry gate: equal signatures and checkpoints do not
reproduce the historical A+B payload under bounded B-only reconstruction.

```text
Which: at location ['payload']['i'] is <0> instead of <14>
Equal stable packing/signature/checkpoint cannot choose between different
historical card bytes, slice hints and P05 layout payloads. No normalization,
re-signing or checkpoint mutation is permitted.
```

In the final snapshot-bound-contract run, both histories have signature
`5734818046b94814136be161b63561536708a36692635c7157e3b6f3b9b08281` and checkpoint
checksum `883187c4902a2ca200c0b1a0af554d5838c37138b23bfbce58033a39f15923dc`.
The card payload digests differ:

- A+B: `2d537b9a6c9d7031461aa5f6b3d97ab734a0bec2d41b4285cfceba5d50a65f78`.
- B alone: `eb5654439862c545f3c0ab217669e1e4e02e0dbdf7a20c6fb92272b78e998666`.

Publication-dependent hashes can change when the temporary EPUB is rebuilt;
the executable assertions require equality across histories within one opened
publication, not hardcoded fixture hash values.

### Why this activates the owner's stop condition

`CanonicalReaderCardIdentityBuilder` intentionally excludes ordinal hints from
the signature; `LazyBookSession.loadedWindow` assigns dense window indexes;
`CanonicalPaginationSourceSnapshot.pin` requires those indexes and owner hints
to agree. The generated card JSON and canonical slice encoding retain those
indexes. The checkpoint holds the stable card identity, not the original card
JSON/resolved layout or the historical loaded-window provenance.

Consequently the same surviving checkpoint and stable publication inputs admit
two distinct required historical byte sequences. Loading A as an adjacent
section can recreate the A+B candidate, but cannot establish that A+B rather
than B-only was the original history. Inspecting more book content does not
recover that absent history. This does not prove that the dual-authority
architecture is impossible; it proves that **validation alone** cannot satisfy
the exact-byte reopen requirement with the existing emitted representation.

The owner expressly required stopping if this model needs changes to existing
card payload/signature semantics, persistent migration, unbounded reopen, or new
restoration UX. A review must now specify a deterministic lazy payload/address
space from initial emission (including the treatment of ordinal hints and
source-bound resolved-layout provenance), or explicitly revise what exact
equality means across reopen. Persisting historical window provenance would be
another, separately authorized persistence change. None was chosen or
implemented here. Existing retained cards/signatures were not rewritten, and
no exact-unavailable UI or reset policy was invented.

### Current gate status and observed work

| Entry gate | Current result |
| --- | --- |
| 1: screen authority/failure settlement | Still partial at the entry-proof commit. Missing warmup promotion, queued hydration, eviction/rebuild, repeated failure, held-close and held-book-switch cases were not added after this stop. |
| 2: dual authority, mutations, reopen, legacy | Not satisfied. Owner's K02 architecture decision accepted; typed lazy validator and mutation suite not implemented before the payload precondition failed. Stable signatures and same-history reopen pass, cross-history exact bytes/slices fail. Legacy bounded exact recovery and actual retry/exact-unavailable UI remain unproved; this new test is not legacy recovery evidence. |
| 3: two handoffs/retention/backward | Not satisfied. No authenticated handoffs, empty/oversized-section transfer, or aggregate backward bound proof was executed. |

Actual maxima **per tested pagination session**: 2 retained published cards,
1 continuation guard, 18 snapshot sources (A+B; B-only has 4), 4 consumed work
entries and 4 entered sources per initial section-root generation. These are
not two-handoff or aggregate-retention maxima. The test retains result cards
for comparison, not a live handoff lineage; it does not prove that 96/25/432
or 110/158 allowances cannot multiply across sessions. The pre-existing S01
screen trace's 6 cards/18 sources is historical evidence, not rerun here.

```sh
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_snapshot_handoff_reopen_payload_test.dart
rtk dart analyze test/reader_contract/regression/lazy_snapshot_handoff_reopen_payload_test.dart
rtk git diff --check
```

Final snapshot-bound-contract test run: **1 passed / 1 failed / 0 skipped**, exit
1. R01 green, R02 red at the payload index assertion above. Analyzer: no issues.
Whitespace check: clean. The earlier exploratory run using the harness's generic
contract had the same counterexample, but the final result above is the one with
actual lazy snapshot-bound P05 evidence. Frozen P02–P06 files, H01–H06, the
production seam, schemas/versions and protected diagnostics were not edited.

**All three entry gates remain unsatisfied; separately reviewable production
handoff implementation is not authorized.** No commit, amend, reset, rebase,
push, device run or P07 work was performed. P04 remains
`ARCHITECTURAL_CORRECTION_REQUIRED`, P06 `REGRESSED_ON_DEVICE`, progress 46/89.

## Original entry-proof record (historical)

Recorded 2026-09-20. **Incomplete; production handoff is not authorized.**
The packing/renderer authority integration needs explicit architectural review.
This report does not close any implementation-entry gate.

## Captured starting state

- Branch: `rescue/change-039-device-failure-2026-09-19`.
- HEAD and CHANGE-040 design: `4ad765d8a56fe88d0b4917b351cdab2672d251b7`.
- Immutable recovery commit: `a130bda2785a57ed2e94ae3fd0630572d3f9d010`.
- Tracked working tree initially clean. Existing untracked files:
  `nalori-last-anr.txt`, `nalori-logcat.txt`, `nalori-meminfo.txt`,
  `regression.mp4`, `terminal_out.md`. None was edited.
- Design status: `DESIGN_SPECIFIED_WITH_IMPLEMENTATION_GATES`.
- Baseline H01/H02/H03/H04 red, H06 green; H05 had no executable screen test.
- No commit, amend, reset, rebase, push, device run, schema change, oracle edit,
  or P07 work was performed. HEAD remains the captured design commit.

## Changes

- `lib/screens/reader_screen.dart`: optional `ReaderAdjacentWorkTestAccess`.
- `test/reader_contract/regression/lazy_snapshot_handoff_screen_test.dart`:
  mounted-screen failure-settlement red test with a repeated-demand control.
- `test/reader_contract/regression/lazy_snapshot_handoff_packing_test.dart`:
  actual P05 contract/block/card control and renderer-compatibility red test.
- This report.

The handle attaches to the real State and detaches on disposal. It rejects
access after detachment or widget/handle/book replacement. It delegates forward
requests, warmup, and hydration directly to the existing private screen methods.
It exposes actual task futures, book owner, generation, counts, publication
payload/identity/slice/layout-fingerprint digest, internal failure and presented
failure. No settlement is synthesized. The only scheduling substitutions are
optional delays at the existing 16 ms warmup and hydration-quiet waits; normal
construction retains `Future.delayed`. No catch, paginator, coordinator,
publication, layout validation, or failure policy was replaced.

The screen test uses the existing injected repository parser to hold work,
then calls `EpubParserService.parseLazySection` with all original arguments.
It mounts a normal ReaderScreen with its real lazy session and loaded inputs.
Host adapters use temporary paths, real SQLite FFI, mock preferences, and real
bundled Inter bytes aliased to the names requested by Google Fonts for chrome.
Canonical Lexend font evidence and the production layout builder remain active.
The fixture's eager parse is existing test setup, not evidence of bounded
production residency. The test uses bounded event/frame pumping and completion
gates, not timing sleeps. Initial setup errors (wrong window property/null
location, fake-zone SQLite work, missing chrome font aliases, and fake-zone
teardown) were corrected before recording the semantic red below.

## Executable findings

S01 publishes six canonical cards from the first parsed section. A second
foreground request returns the **same Future**. On releasing the real successor
parse, the screen reports:

```
SCREEN result=true error=Bad state: A terminal continuation cannot be resumed. failure=Bad state: A terminal continuation cannot be resumed. presented=null starts=2 cards=6 sources=18
```

The publication digest remains equal. The failing assertion is:

```
Expected: false
  Actual: <true>
Caught terminal pagination rejection must not settle adjacent demand as success.
```

The absence of a presented failure is observed through the real screen state;
this is not an executable test of legacy exact-unavailable/retry UI.

K01 uses the production font gate, layout contract builder, block resolver and
card resolver. Across A and A+B with different representative probes it proves
identical F196, F206, F204, font-delivery digest, and retained block fingerprint;
F202 and the actual contract identity differ. A test-only candidate
LazyPackingIdentityV1 tuple stays equal; its publication/spine/parser/dependency
values are fixed test inputs, **not a new publication-authority implementation**.
Reconstructing A with its old evidence reproduces the resolved card. Resolving
that same block under A+B changes physical card identity components. Missing
per-source font evidence still throws. No F202/F208 value is overridden.

K02 passes the unmodified retained A card to the real rendering adapter under
the A+B contract:

```
Expected: return normally
Which: threw StateError:<Bad state: Resolved card does not belong to this layout contract.>
LazyPackingIdentityV1 alone cannot authorize an old P05 resolved card under the successor contract.
```

Relevant production behavior: `ReaderCardLayoutResolver.resolve` puts F202 in
physical card components and stores `contract.identity` in the resolved card;
`ReaderLayoutRenderingAdapter.block` requires exact contract identity equality.
The proposed session-level packing digest alone does not change these checks.
This proves incompatibility of **directly adopting the successor P05 contract**,
not impossibility of the selected handoff architecture. Keeping A's contract
instead also needs a proved deterministic reopen derivation; that alternative
has not been implemented or proved here.

Owner/architecture review needed: specify the lazy resolved-card/renderer
contract authority and deterministic reopen derivation, with mandatory separate
source/font/image/structure validation and unchanged retained card payloads.
Do not resolve this by relabeling contracts, copying F202/F208, re-signing cards,
or relaxing the renderer check. This is the stopping boundary from the user's
instruction and design §10. No proposed authority extension was implemented.

## Gate ledger and limits

| Entry gate | Result |
| --- | --- |
| 1: real-screen failure/ownership cases | Partial: caught failure is semantically red; repeated foreground demand shares the real future. Warmup promotion, repeated failure settlement, queued hydration after failure, failure→eviction/rebuild, close-held-work and switch-held-work assertions remain unproved. The hooks exist but their mere presence is not coverage. |
| 2: packing/source evidence/reload/legacy | Blocked at real P05 retained-card contract compatibility. Metrics/block/font and same-old-evidence reconstruction controls pass. Full per-source extension, publication-derived tuple and new-protocol reopen are unproved. Existing P05 structure/font/image validator controls pass, which does not close the handoff gate. |
| 3: two handoffs/retention/backward | Not executed after stopping at gate 2. No authenticated handoffs, retained suffix/frontier transfer or backward reconstruction were built. |

**Legacy checkpoint conclusion: unresolved and still an entry blocker.**
Same-contract resolved-card reconstruction in K01 is not exact checkpoint
restoration. No executable conclusion is claimed about reconstructing a missing
old window, bounded legacy recovery, or the existing retry/exact-unavailable UI.
No checkpoint was semantically migrated, reset, re-signed or deleted.

Observed screen maxima in this tiny trace: 6 published cards, 18 loaded source
chunks (14 before extension), and 2 parser starts. Resident guard count and
backward regeneration work were not measured. These are not aggregate lineage
maxima and do not prove any of the 96-card, 25-guard, 432-source, 110/158-entry
bounds. Empty/oversized sections and two-handoff retention remain untested.
There is no claim of bounded whole-book residency or nonmultiplication.

## Exact commands and results

Baseline, before the seam:

```sh
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_snapshot_handoff_characterization_test.dart
```

1 passed / 4 failed / 0 skipped, exit 1. H01 actually produces
`terminalBookEnd`. H02 and both H03 priorities reject with
`terminalStateContradiction: A terminal continuation cannot be resumed.` H04
expects true but receives false. H06 validates final-section terminal encoding.
The characterization file is unchanged. A post-seam repeat returned the same
1 pass / 4 failures with the same messages.

New entry proofs:

```sh
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_snapshot_handoff_screen_test.dart test/reader_contract/regression/lazy_snapshot_handoff_packing_test.dart
```

1 passed / 2 failed / 0 skipped, exit 1: K01 green; S01 and K02 semantic reds
shown above. A focused S01 rerun after adding layout fingerprints to its
publication digest returned the same 0 pass / 1 semantic failure. No red was
skipped, quarantined or counted as a passing gate.

Frozen P05 controls (executed, not edited):

```sh
rtk flutter test --no-pub --reporter expanded test/reader_contract/layout/reader_layout_contract_shared_test.dart test/reader_contract/layout/reader_font_evidence_gate_test.dart test/reader_contract/layout/reader_compatibility_classifier_test.dart
```

90 passed / 0 failed / 0 skipped, exit 0, including source/font/structural/image
validation and the F001–F211 mutation oracle. Emitted P05 maxima:
contract 4696 bytes, block 1462 bytes, card 1728 bytes. These are P05 record sizes,
not handoff retention evidence.

```sh
rtk dart analyze lib/screens/reader_screen.dart test/reader_contract/regression/lazy_snapshot_handoff_screen_test.dart test/reader_contract/regression/lazy_snapshot_handoff_packing_test.dart
rtk git diff --check
```

No analyzer issues; no whitespace errors.

## Bounded subsequent task prompt

> Continue only IMPLEMENT-P04-LAZY-SNAPSHOT-HANDOFF-001 on
> rescue/change-039-device-failure-2026-09-19, from the uncommitted entry-proof
> changes documented in nalori-lazy-snapshot-handoff-entry-proof.md. Preserve
> immutable recovery a130bda2785a57ed2e94ae3fd0630572d3f9d010 and design commit
> 4ad765d8a56fe88d0b4917b351cdab2672d251b7. First obtain a reviewed specification
> for the lazy resolved-card/renderer contract authority and deterministic
> reopen derivation exposed by K02; do not infer permission to bypass F202/F208,
> re-sign retained cards or relax validators. Then complete the remaining real
> ReaderScreen warmup/promotion, repeated failure, queued hydration,
> failure→eviction/rebuild, close-held-work and switch-held-work red proofs.
> Establish legacy bounded exact restoration and actual retry/exact-unavailable
> UI without checkpoint mutation. Prove two-handoff aggregate retention and
> exact backward regeneration including empty/oversized sections and all
> 96/25/432/110/158 bounds. Preserve H01–H06 truth. Production changes remain
> limited to the approved narrow screen seam. Do not wire receipt→successor
> session→publication, alter schemas/frozen oracles/protected evidence, start
> P07, run devices, commit, amend, reset, rebase or push. Stop on any further
> product or architecture decision; report exact evidence and open gates.

P04 remains `ARCHITECTURAL_CORRECTION_REQUIRED`; P06 remains
`REGRESSED_ON_DEVICE`; overall progress remains 46/89; P07 remains unstarted.
