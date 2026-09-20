# IMPLEMENT-P04-LAZY-SNAPSHOT-HANDOFF-001: stopped entry proof

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
