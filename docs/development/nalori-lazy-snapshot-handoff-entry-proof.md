# IMPLEMENT-P04-LAZY-SNAPSHOT-HANDOFF-001: stopped entry proof

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
