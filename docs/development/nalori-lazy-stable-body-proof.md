# IMPLEMENT-P04-LAZY-STABLE-BODY-002

Implemented the stable-body/persistence/reopen prerequisite on
`rescue/change-039-device-failure-2026-09-19`, starting at
`92bf7fe9fae6cf228ebd334fc9a2523f50ac3fc2`. No commit was created. Recovery
`a130bda2785a57ed2e94ae3fd0630572d3f9d010`, design
`4ad765d8a56fe88d0b4917b351cdab2672d251b7`, entry baseline
`008989ca3457e5ed6c3fdb48b8d1337f8fbbbea4`, and historical proofs remain intact.
The prompt's proof-hash placeholder was resolved from the actual branch HEAD.

The owner decision in this task authorizes the versioned lazy domain and
DEC-REQ-001/002 semantic migration policy. It supersedes the earlier documents'
unselected-version/recovery decision gate for this prerequisite only.

## Exact files changed

- `lib/models/lazy_stable_card.dart`: immutable stable body and source-slice codec.
- `lib/services/lazy_stable_card_service.dart`: pinned section membership,
  checked resident projection, production P05 emission and exact admission.
- `lib/models/reader_checkpoint.dart`: lazy payload v2 discriminator and codec;
  ordinary v1 creation retains its bytes and rules.
- `lib/services/reader_checkpoint_store.dart`: shared journal supports v2,
  rejects downgrade, and conditionally rolls back stale/cancelled publication
  commits. Old coordinator cannot authorize a v2 restore with signature alone.
- `lib/services/lazy_checkpoint_recovery.dart`: bounded prepared-target recovery,
  explicit exact/migration/unavailable outcomes and guarded publication commit.
- `test/reader_contract/regression/lazy_stable_body_test.dart`: separate R03–R12
  and L03 production proofs; generated image EPUB exists only under test temp.
- `docs/development/nalori-lazy-stable-body-proof.md`: this report.
- `docs/development/nalori-lazy-snapshot-handoff-entry-proof.md`: current pointer;
  previous evidence remains unchanged below it.
- `docs/development/nalori-reader-reliability-change-log.md`: task entry.

## Selected format and validation

This is a **payload-version change**, not a schema-free implementation.
SQLite database schema remains **1**, using existing
`reader_checkpoint_journal.checkpoint_json` and `integrity_checksum` columns.
No table migration, physical display-cache replacement, or parsed-source cache
version change was needed.

| Domain | Version | Persisted evidence |
| --- | --- | --- |
| `nalori.lazy.stable-card` | 1 | `publication`, exact `section`, complete `membership`, structural `payload`, canonical ordered `slices`, `layout`, canonical `identity`, domain-separated SHA-256 `digest` |
| `nalori.lazy.checkpoint` | `formatVersion: 2` | Stable body plus book/publication, card/semantic anchor, layout/pagination identity, epoch/revision/time/state and navigation source |
| Semantic conversion | `lazy_semantic_migration_v1` | Explicit `lazyMigration` marker on the newly committed v2 checkpoint |
| Ordinary checkpoint | `formatVersion: 1` | Existing full-snapshot payload; no new fields added by ordinary creation |

Publication authority uses `PublicationSpineAuthorityV1`: book/publication,
index schema, parser/dependency revisions and ordered spine item index/idref,
normalized href/full path, linear scope and full source checksum. Exact section
JSON is checked against that index. Membership includes complete ordered source
ownership digests, count, and the complete parsed-section record digest. Local
source indexes must be consecutive. Insert/remove/reorder and record changes
cannot preserve membership. Capture rejects evidence exceeding 432 sources or
4 MiB of canonical section JSON; body encoding is also capped at 4 MiB. It does
not truncate evidence or parse preceding sections to discover a flat ordinal.

Each `LazySourceAddressV1` binds publication authority, exact section digest and
section-local source position. Each stable slice preserves every canonical
ownership/structural/fragment/list/publisher/rich-metadata field and its tagged
UTF-16 or table-row interval. Images and synthetic atomic owners use full-source
ownership with null text/row coordinates. Table cells, list fragments, rich
text and image bytes remain in the structural payload and source/layout digests.

`LazyPackingIdentityV1` binds publication authority, structural revision, P05
metrics, renderer and pagination fingerprints, classifier revision and font
delivery digest. Ordered resolved block layout/font/source-structure digests
are retained. Emission requires accepted production pagination, checks its
source snapshot against complete section membership, and reruns the unmodified
P05 block/card resolvers and rendering adapter with current source font/image
evidence. No F202/F208 override or renderer-check relaxation occurs.

The codec verifies version/domain, integrity, shape, slice membership/address,
ordered intervals and canonical identity. **Decode alone is not admission.**
Exact admission regenerates through the production paginator/P05 contracts and
compares the entire stable encoding, including payload/slices/layout. A digest
recomputed over altered evidence cannot bypass that comparison.

Runtime-only fields are `BookChunk.index`/root `payload.i`, range `ci`,
`sourceOrdinalHint`, resident slots, snapshot digest/revision, source-bound P05
contract/F202/F208 and physical card component objects. They remain on the
original P05 objects. New body emission builds a separate payload; it never
modifies accepted legacy JSON. Source-range `ci` is represented in the new
domain by checked local position/address. Nested list `i` remains its existing
string item ID, not a runtime ordinal. V2 checkpoints omit legacy global/display
location hints entirely. `LazyStableResidentProjection` maps authenticated
stable owners to resident slots and rejects a wrong hint when used.

## Production proofs and historical truth

| Requirement | Evidence |
| --- | --- |
| A+B/B-only exact new bytes; runtime 14/0 independent | R03, complete canonical encoding and digest equality; old card JSON still differs |
| Equal local positions cannot alias; wrong hint rejects | R03, separate section addresses and checked source/slice projection |
| Eviction/reload equality | R03, actual session pressure eviction of B followed by repository reload and production regeneration |
| SQLite exact reopen | R04, real write/close/reopen, B-only regeneration and `exactStableBody`; full body admission; old coordinator/downgrade rejected |
| Backward exact body/signature | R05, production `generateBackward`, regenerated committed card, exact new-body admission |
| Source mutations reject | Eight R06 cases: insert/remove/reorder/text/parser/dependency/image bytes/structure |
| Layout evidence mutations reject | Eight R07 cases, including recomputed envelope digests; R09 uses an actually rebuilt different production layout; R11 revokes current source font evidence |
| Rich source coordinates retained | R10, all cards from complete parsed A preserve text/list/table payloads and slices after independent regeneration; R12 real parsed PNG with production decoded image metrics and atomic body equality across windows |
| Old/new discrimination | R08, old body rejected, relabeled v1→v2 rejected, v2→v1 rejected, bad digest rejected, immutable encoding |
| Legacy same-window exact | L01 remains green; L03 exact requires the externally known original snapshot digest and original composite/signature |
| Legacy changed-window migration | L03 migration and stable-anchor fallback use explicit `semanticMigrationV1`, never `exactSignature` or `layout_changed` |
| Unavailable recovery | L03 unavailable/missing-anchor preserve old record, return typed `exactUnavailable` with Retry/Back actions |
| Cancel/failure/stale safety | L03 cancellation, newer epoch, transaction-time exception and cancellation-after-insert rollback; direct read-only SQLite audit checks one unchanged original row |
| Accepted migration commit | L03 commits only the prepared body reported published by the current owner; SQLite audit checks two journal rows and byte-identical original first row |
| Ordinary P05 controls | 90 unchanged layout/font/classifier cases, 10 unchanged backward cases, 7 unchanged segment-admission cases; 25 existing checkpoint cases pass with host SQLite loader alias |

R02 is **still red**: old A+B `payload.i/sourceOrdinalHint=14` versus B-only
`0`, with different old source-bound P05 payloads. R01 remains green. No R02
assertion or JSON was normalized. L02 is **still red**: old coordinator returns
`semanticAnchor / layout_changed` for the window-only composite change; its old
checkpoint remains preserved. L03 is the separate authorized migration path.

Historical aggregate is **15 passed / 9 failed / 0 skipped**. Failures remain
R02, L02, H01, H02, H03 (both priorities in one case), H04, S01, K02 and D02.
These reds are not counted as passed acceptance gates.

Recovery consumes already prepared, bounded production sessions. It does not
enumerate historical windows or reconstruct a whole book. A caller can supply
original-window provenance when it actually exists; absence is never filled
with the current snapshot's ordinal history. Unique exact semantic ownership,
or an independently matching durable section/local anchor, permits selecting
the nearest verified new card. Missing/ambiguous evidence stays unavailable.
Preparing, retrying or abandoning never writes a checkpoint. `commitPublished`
requires the exact pending body, current publication owner, matching previous
checkpoint checksum and current database epoch/revision. Cancellation during
the journal transaction rolls back insertion and pruning. UI publication
ownership is supplied by the caller; real ReaderScreen wiring remains deferred.

## Commands and exact results

All counts below are passed/failed/skipped. No device ran.

```sh
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_stable_body_test.dart
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_stable_body_test.dart --name 'R03|R04|R05'
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_stable_body_test.dart --name 'R05|L03'
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_stable_body_test.dart --name 'R10|R11'
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_stable_body_test.dart --name R12
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_stable_body_test.dart > /tmp/nalori-stable-body-final.log 2>&1
```

- Initial 27-case run: **10/17/0**, exit 1. Found incorrect envelope key count
  and an eviction test assuming the reloaded window had already shed A.
- Focused R03/R04/R05: **2/1/0**, exit 1; the backward test supplied a prefix
  equal to its desired predecessor. Corrected to the committed later prefix.
- Focused R05/L03: **7/1/0**, exit 1; the expected failure was being caught by
  the widget fake-zone wrapper. Assertion moved inside `runAsync`.
- Full 27-case run: **27/0/0**, exit 0.
- Expanded 30-case run: **30/0/0**, exit 0.
- Focused R10/R11: **1/1/0**, exit 1; list membership is metadata on text
  structural owners, not a `structuralType` containing the word “list”. The new
  test now asserts actual parsed list semantics and emitted `ls/lf` preservation.
- Full 32-case run: **32/0/0**, exit 0.
- Focused real-image R12: **1/0/0**, exit 0.
- Final complete suite including journal row audit: **33/0/0**, completed log
  reports `All tests passed!`. The process handle expired across the user's
  continuation, so its exit code was not separately retrieved. Complete output
  remains in `/tmp/nalori-stable-body-final.log`.

Observed per-generation maxima across these proofs: **19 loaded sources,
6 accepted cards, 1 guard, 14 consumed work entries and 14 entered sources**.
The largest window includes the independently generated real image fixture.
These are bounded reconstruction observations, not aggregate handoff-lineage
or retention-transfer measurements.

```sh
rtk flutter test --no-pub --reporter expanded test/reader_contract/layout/reader_layout_contract_shared_test.dart test/reader_contract/layout/reader_font_evidence_gate_test.dart test/reader_contract/layout/reader_compatibility_classifier_test.dart test/reader_contract/pagination/reader_card_paginator_backward_preparation_test.dart test/unit/services/reader_checkpoint_store_test.dart test/reader_contract/pagination/canonical_display_segment_admission_test.dart > /tmp/nalori-stable-controls.log 2>&1
rtk proxy env LD_LIBRARY_PATH=/tmp/nalori-stable-sqlite rtk flutter test --no-pub --reporter expanded test/unit/services/reader_checkpoint_store_test.dart
```

Combined controls: **112/20/0**, exit 1. All 20 failures were the unchanged
checkpoint suite's unavailable `libsqlite3.so` loader name. The other suites
were **107/0/0** (P05 90, backward 10, admission 7); five checkpoint pure-model
tests also passed. Created `/tmp/nalori-stable-sqlite/libsqlite3.so` as a symlink
to installed `/lib/x86_64-linux-gnu/libsqlite3.so.0`, then reran the unchanged
checkpoint suite with that loader path: **25/0/0**, exit 0. Thus all **132 unique
control cases** passed; no control file changed. P05 retained-size evidence is
unchanged at contract/block/card **4696/1462/1728 bytes**.

```sh
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_snapshot_handoff_reopen_payload_test.dart test/reader_contract/regression/lazy_snapshot_handoff_characterization_test.dart test/reader_contract/regression/lazy_snapshot_handoff_screen_test.dart test/reader_contract/regression/lazy_snapshot_handoff_packing_test.dart test/reader_contract/regression/lazy_direct_target_entry_test.dart test/reader_contract/regression/lazy_source_address_entry_test.dart > /tmp/nalori-stable-historical.log 2>&1
```

Historical result: **15/9/0**, exit 1, exact historical failures listed above.
The first redirected invocation of each of the three suites failed before test
loading (exit 1, zero tests executed) because the sandbox denied Flutter SDK
engine-stamp writes. They were rerun with approved SDK-cache access. This was
not a product-test failure or a device run.

```sh
rtk dart format lib/models/lazy_stable_card.dart lib/models/reader_checkpoint.dart lib/services/lazy_stable_card_service.dart lib/services/lazy_checkpoint_recovery.dart lib/services/reader_checkpoint_store.dart test/reader_contract/regression/lazy_stable_body_test.dart
rtk dart analyze lib/models/lazy_stable_card.dart lib/models/reader_checkpoint.dart lib/services/lazy_stable_card_service.dart lib/services/lazy_checkpoint_recovery.dart lib/services/reader_checkpoint_store.dart test/reader_contract/regression/lazy_stable_body_test.dart
rtk git diff --check
rtk git status --short
rtk git diff --stat
rtk proxy git rev-parse HEAD
```

Formatting and scoped analysis were also run on subsets during implementation.
Early analysis found seven style infos, then one unused import/nine style infos,
then four style infos; all corrected. Final scoped analysis: no issues, exit 0.
Whitespace check clean. Read-only `rg`, `cat`, `sed`, Git status/log/diff and
temporary-log inspection supplied the source audit; no Git mutation command ran.

Final preservation checks, all exit 0:

```sh
rtk proxy git merge-base --is-ancestor a130bda2785a57ed2e94ae3fd0630572d3f9d010 HEAD
rtk proxy git merge-base --is-ancestor 4ad765d8a56fe88d0b4917b351cdab2672d251b7 HEAD
rtk proxy git merge-base --is-ancestor 008989ca3457e5ed6c3fdb48b8d1337f8fbbbea4 HEAD
rtk proxy git diff --exit-code -- test/reader_contract/regression/lazy_snapshot_handoff_reopen_payload_test.dart test/reader_contract/regression/lazy_snapshot_handoff_characterization_test.dart test/reader_contract/regression/lazy_snapshot_handoff_screen_test.dart test/reader_contract/regression/lazy_snapshot_handoff_packing_test.dart test/reader_contract/regression/lazy_source_address_entry_test.dart test/reader_contract/regression/lazy_direct_target_entry_test.dart test/reader_contract/layout test/reader_contract/fixtures test/unit/services/reader_checkpoint_store_test.dart
rtk git diff --check
```

## Remaining gates and next bounded prompt

P04 remains **ARCHITECTURAL_CORRECTION_REQUIRED**, P06 remains
**REGRESSED_ON_DEVICE**, progress **46/89**, P07 **UNSTARTED**. This prerequisite
does not complete an existing checklist item's entire acceptance criteria.

No SectionEndReceiptV1, LazySnapshotHandoffV1 or publishSnapshotHandoff wiring;
no screen navigation scheduling/direct-target seam/preemption fix; no retention
transfer or scrubber. Actual screen migration/Retry/Back presentation and
acceptance ownership still need wiring/proofs. Screen warmup/promotion,
failure settlement, queued hydration, close/switch-held-work, latest/identical
direct demand and first-card-before-cache-write gates remain open. Two-handoff
empty/oversized sections, aggregate 96-card/25-guard/432-source/110–158-work
retention and backward transfer remain open. Host bounded regeneration here is
not transfer, lineage nonmultiplication, or device latency evidence.

Next bounded prompt:

> Continue only the real-screen P04 entry-proof follow-up on
> rescue/change-039-device-failure-2026-09-19, preserving the uncommitted
> IMPLEMENT-P04-LAZY-STABLE-BODY-002 changes and all named recovery/design/proof
> commits. Read this stable-body report and design §§11–14. Add only the narrow
> real direct-target/first-acceptance observation seam and prove actual screen
> target ownership, prior readable-card preservation, identical/latest demand,
> typed lazy recovery/write barrier, and failure/close/switch settlement with
> deterministic held production work. Preserve all historical reds; do not
> silently convert them to green expectations. Record preemption and first-card
> ordering failures without expanding into scheduling fixes. Do not implement
> snapshot handoff, retention/backward transfer, scrubber, P07, device work or
> Git mutations. Keep P04/P06 open and 46/89; report the next remaining gate.
