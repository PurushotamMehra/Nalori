import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/canonical_display_cache_invalidation.dart';
import 'package:nalori/models/canonical_display_cache_migration.dart';
import 'package:nalori/models/canonical_display_segment.dart';
import 'package:nalori/models/canonical_pagination.dart';
import 'package:nalori/models/reader_checkpoint.dart';
import 'package:nalori/models/reader_compatibility.dart';
import 'package:nalori/models/reader_font_evidence.dart';
import 'package:nalori/models/reader_layout_contract.dart';
import 'package:nalori/services/canonical_display_cache_invalidation_service.dart';
import 'package:nalori/services/canonical_display_cache_migration_service.dart';
import 'package:nalori/services/canonical_display_segment_admission.dart';
import 'package:nalori/services/display_generation_coordinator.dart';
import 'package:nalori/services/display_section_memory_cache.dart';
import 'package:nalori/services/progressive_display_state.dart';
import 'package:nalori/services/reader_card_paginator.dart';
import 'package:nalori/services/segmented_display_cache_service.dart';

import '../support/reader_contract_sandbox.dart';
import 'reader_core_pagination_harness.dart';

void main() {
  late ReaderCoreParsedFixture fixture;

  setUpAll(() async {
    fixture = await ReaderCoreParsedFixture.load(
      'nalori_reader_p06_migration_',
    );
  });
  tearDownAll(() => fixture.close());

  group('[REQ-009, REQ-013, REQ-044, REQ-045, REQ-046, REQ-048, REQ-051] '
      'TASK-P06-005 canonical cache migration', () {
    testWidgets('complete migratability matrix remains fail closed', (
      tester,
    ) async {
      final material = await _material(tester, fixture);
      const service = CanonicalDisplayCacheMigrationService();
      final legacyKinds = <CanonicalDisplayMigrationCandidateKind>[
        CanonicalDisplayMigrationCandidateKind.wholeDisplayCache,
        CanonicalDisplayMigrationCandidateKind.segmentedLegacyRecord,
        CanonicalDisplayMigrationCandidateKind.sectionScopedLegacyRecord,
        CanonicalDisplayMigrationCandidateKind.sectionMemoryRecord,
        CanonicalDisplayMigrationCandidateKind.chapterLayoutRecord,
        CanonicalDisplayMigrationCandidateKind.rawDisplayRangeResult,
        CanonicalDisplayMigrationCandidateKind.checkpointOrStableLocation,
        CanonicalDisplayMigrationCandidateKind.continuationOnly,
      ];
      for (final kind in legacyKinds) {
        final admission = CanonicalDisplaySegmentAdmission.legacySafeMiss(
          cacheKind: kind.name,
        );
        final plan = service.assess(
          candidate: CanonicalDisplayMigrationCandidate.legacy(kind: kind),
          oldAdmission: admission,
          currentContext: material.currentContext,
          limits: _limits,
        );
        expect(
          plan.eligibility,
          CanonicalDisplayMigrationEligibility.knownNonmigratable,
        );
        expect(
          plan.reason,
          CanonicalDisplayMigrationReason.nonmigratableLegacyEvidence,
        );
        expect(plan.hasMigratedCards, isFalse);
        expect(plan.hasNewContinuationAuthority, isFalse);
        expect(plan.hasPublicationAuthority, isFalse);
      }
      final liveOnly = service.assess(
        candidate: CanonicalDisplayMigrationCandidate.legacy(
          kind:
              CanonicalDisplayMigrationCandidateKind.liveP04CardWithP05Evidence,
        ),
        oldAdmission: material.oldAdmission,
        currentContext: material.currentContext,
        limits: _limits,
      );
      expect(
        liveOnly.reason,
        CanonicalDisplayMigrationReason.incompleteEvidence,
      );

      final exact = service.assess(
        candidate: CanonicalDisplayMigrationCandidate.strictCanonical(
          canonicalBytes: CanonicalDisplaySegmentCodec.encode(
            material.oldRecord,
          ),
        ),
        oldAdmission: material.oldAdmission,
        currentContext: material.oldContext,
        limits: _limits,
      );
      expect(
        exact.reason,
        CanonicalDisplayMigrationReason.exactRecordMigrationNotRequired,
      );

      final incomplete = service.assess(
        candidate: CanonicalDisplayMigrationCandidate.strictCanonical(
          canonicalBytes: CanonicalDisplaySegmentCodec.encode(
            material.oldRecord,
          ),
        ),
        oldAdmission: null,
        currentContext: material.currentContext,
        limits: _limits,
      );
      expect(
        incomplete.reason,
        CanonicalDisplayMigrationReason.incompleteEvidence,
      );
      final forgedAdmission = CanonicalDisplaySegmentAdmissionResult.exact(
        candidate: material.oldRecord,
        exactCandidate: material.oldAdmission.exactCandidate!,
        diagnostics: 'caller-assembled exact result',
      );
      final forged = service.assess(
        candidate: CanonicalDisplayMigrationCandidate.strictCanonical(
          canonicalBytes: CanonicalDisplaySegmentCodec.encode(
            material.oldRecord,
          ),
        ),
        oldAdmission: forgedAdmission,
        currentContext: material.currentContext,
        limits: _limits,
      );
      expect(
        forged.reason,
        CanonicalDisplayMigrationReason.incompleteEvidence,
        reason: 'Only the strict admission service may attest old evidence.',
      );
      final corruptBytes = Uint8List.fromList(
        CanonicalDisplaySegmentCodec.encode(material.oldRecord),
      )..[1] ^= 0x01;
      final corrupt = service.assess(
        candidate: CanonicalDisplayMigrationCandidate.strictCanonical(
          canonicalBytes: corruptBytes,
        ),
        oldAdmission: material.oldAdmission,
        currentContext: material.currentContext,
        limits: _limits,
      );
      expect(corrupt.reason, CanonicalDisplayMigrationReason.corruptEvidence);

      final rejectedLegacyReplacement =
          const CanonicalDisplayCacheInvalidationService()
              .migrationReplacementPlan(
                candidateType:
                    CanonicalDisplayInvalidationCandidateType.wholeDisplay,
              );
      expect(
        rejectedLegacyReplacement.action,
        CanonicalDisplayInvalidationAction.failedSafeInvalidation,
      );
      expect(rejectedLegacyReplacement.allowsBoundedRegeneration, isFalse);
    });

    for (final entry
        in <
          ({
            String label,
            _CompatibilityChange change,
            ReaderCorePaginationLayout layout,
          })
        >[
          (
            label: 'layout',
            change: _CompatibilityChange.layout,
            layout: ReaderCorePaginationLayout.splitStress,
          ),
          (
            label: 'renderer',
            change: _CompatibilityChange.renderer,
            layout: ReaderCorePaginationLayout.standard,
          ),
          (
            label: 'pagination',
            change: _CompatibilityChange.pagination,
            layout: ReaderCorePaginationLayout.standard,
          ),
          (
            label: 'compound',
            change: _CompatibilityChange.compound,
            layout: ReaderCorePaginationLayout.splitStress,
          ),
        ]) {
      testWidgets(
        'strict ${entry.label} migration regenerates current cards',
        (tester) => _verifyStrictMigration(tester, fixture, entry),
      );
    }

    testWidgets(
      'source/parser changes, future revisions, stale, cancelled, and budget outcomes retain safe misses',
      (tester) async {
        final sourceChanged = await _material(
          tester,
          fixture,
          oldChange: _CompatibilityChange.source,
        );
        final sourceOutcome = await _execute(
          tester: tester,
          material: sourceChanged,
          label: 'source',
        );
        expect(
          sourceOutcome.kind,
          CanonicalDisplayMigrationOutcomeKind.sourceCorrespondenceUnavailable,
        );
        expect(sourceOutcome.diagnostics.sourceRemapCandidatesInspected, 0);
        expect(sourceOutcome.record, isNull);

        final future = await _material(
          tester,
          fixture,
          oldChange: _CompatibilityChange.unsupportedPagination,
        );
        final futureOutcome = await _execute(
          tester: tester,
          material: future,
          label: 'future',
        );
        expect(
          futureOutcome.kind,
          CanonicalDisplayMigrationOutcomeKind
              .unsupportedFutureRevisionRetained,
        );

        final normal = await _material(
          tester,
          fixture,
          currentLayout: ReaderCorePaginationLayout.splitStress,
        );
        final stale = await _execute(
          tester: tester,
          material: normal,
          label: 'stale',
          stale: () => true,
        );
        final cancelled = await _execute(
          tester: tester,
          material: normal,
          label: 'cancelled',
          cancelled: () => true,
        );
        final exhausted = await _execute(
          tester: tester,
          material: normal,
          label: 'budget',
          workBudgetExhausted: true,
        );
        final laterSegment = await _material(
          tester,
          fixture,
          currentLayout: ReaderCorePaginationLayout.splitStress,
          oldRecordIndex: 1,
        );
        final wrongSourceRoute = await _execute(
          tester: tester,
          material: laterSegment,
          label: 'wrong-source-route',
        );
        expect(stale.kind, CanonicalDisplayMigrationOutcomeKind.staleRequest);
        expect(
          cancelled.kind,
          CanonicalDisplayMigrationOutcomeKind.cancelledRequest,
        );
        expect(
          exhausted.kind,
          CanonicalDisplayMigrationOutcomeKind.migrationWorkBudgetExhausted,
        );
        expect(
          wrongSourceRoute.kind,
          CanonicalDisplayMigrationOutcomeKind
              .regeneratedRecordFailedStrictAdmission,
          reason: 'A replacement must begin at the old stable source cursor.',
        );
        for (final outcome in <CanonicalDisplayMigrationOutcome>[
          sourceOutcome,
          futureOutcome,
          stale,
          cancelled,
          exhausted,
          wrongSourceRoute,
        ]) {
          expect(outcome.record, isNull);
          expect(outcome.replacementReceipt, isNull);
          expect(outcome.hasMigratedCards, isFalse);
          expect(outcome.hasNewContinuationAuthority, isFalse);
          expect(outcome.hasPublicationAuthority, isFalse);
        }
      },
    );

    testWidgets(
      'replacement is P06-004-controlled, atomic on failure, and idempotent',
      (tester) async {
        final sandbox = (await tester.runAsync(ReaderContractSandbox.create))!;
        addTearDown(sandbox.close);
        final material = await _material(
          tester,
          fixture,
          currentLayout: ReaderCorePaginationLayout.splitStress,
        );
        final root = Directory('${sandbox.root.path}/canonical-migration');
        final disk = CanonicalDisplaySegmentControlledDiskStore(
          rootDirectory: root,
        );
        final memory = CanonicalDisplaySegmentMemoryTransport();
        await tester.runAsync(() => disk.write(material.oldRecord));
        final beforeOld = await tester.runAsync(
          () async => (await disk.read(material.oldRecord.keyDigest))!,
        );
        final target = _ControlledTarget(
          disk: disk,
          memory: memory,
          oldKeyDigest: material.oldRecord.keyDigest,
          scope: CanonicalDisplayInvalidationStorageScope(
            rootDirectory: root,
            bookScope: 'p06-005-controlled-book',
          ),
        );
        final failing = await _execute(
          tester: tester,
          material: material,
          label: 'replacement-failure',
          target: target,
          service: CanonicalDisplayCacheMigrationService(
            invalidationService: CanonicalDisplayCacheInvalidationService(
              mutationInterceptor: (_) =>
                  throw StateError('injected-delete-failure'),
            ),
          ),
        );
        expect(
          failing.kind,
          CanonicalDisplayMigrationOutcomeKind.controlledReplacementFailed,
        );
        expect(
          await tester.runAsync(() => disk.read(material.oldRecord.keyDigest)),
          beforeOld,
        );
        expect(memory.get(material.oldRecord.keyDigest), isNull);

        var staleDuringRetain = false;
        final staleTarget = _ControlledTarget(
          disk: disk,
          memory: memory,
          oldKeyDigest: material.oldRecord.keyDigest,
          scope: target.scope,
          afterRetainValidatedRecord: () => staleDuringRetain = true,
        );
        final stale = await _execute(
          tester: tester,
          material: material,
          label: 'stale-during-retain',
          target: staleTarget,
          stale: () => staleDuringRetain,
        );
        expect(stale.kind, CanonicalDisplayMigrationOutcomeKind.staleRequest);
        expect(
          await tester.runAsync(() => disk.read(material.oldRecord.keyDigest)),
          beforeOld,
          reason: 'A stale request must not delete the old candidate.',
        );

        final first = await _execute(
          tester: tester,
          material: material,
          label: 'replacement-success',
          target: target,
        );
        final second = await _execute(
          tester: tester,
          material: material,
          label: 'replacement-repeat',
          target: target,
        );
        expect(first.succeeded, isTrue);
        expect(second.succeeded, isTrue);
        expect(
          await tester.runAsync(() => disk.read(material.oldRecord.keyDigest)),
          isNull,
        );
        expect(
          await tester.runAsync(() => disk.read(first.record!.keyDigest)),
          CanonicalDisplaySegmentCodec.encode(first.record!),
        );
        expect(
          memory.get(first.record!.keyDigest)?.checksumDigest,
          first.record!.checksumDigest,
        );
        expect(second.record!.checksumDigest, first.record!.checksumDigest);
        expect(
          await tester.runAsync(() => disk.byteCount),
          CanonicalDisplaySegmentCodec.encode(first.record!).length,
        );
        // ignore: avoid_print
        print(
          'P06_MIGRATION_MAX assessmentBytes=${first.diagnostics.assessmentBytes} '
          'resultBytes=${first.diagnostics.resultBytes} '
          'oldRecordBytes=${first.diagnostics.oldRecordBytes} '
          'newRecordBytes=${first.diagnostics.newRecordBytes} '
          'sourceUnits=${first.diagnostics.sourceUnitsRegenerated} '
          'cards=${first.diagnostics.cardsRegenerated} '
          'boundaryChanges=${first.diagnostics.physicalBoundaryChanges} '
          'dimensions=${first.diagnostics.compatibilityDimensionsChanged} '
          'remapCandidates=${first.diagnostics.sourceRemapCandidatesInspected} '
          'retained=${first.diagnostics.controlledRecordsRetained} '
          'replaced=${first.diagnostics.controlledRecordsReplaced} '
          'attempts=${first.diagnostics.migrationAttemptsPerRecord} '
          'copiedOldCardIdentityBytes=0 copiedSourceTextIdentityBytes=0 '
          'mutableIndexAuthorityBytes=0 partialRecordsExposed=0 '
          'protectedDataMutations=0 liveCacheWrites=0',
        );
      },
    );
  });
}

const _limits = CanonicalDisplaySegmentCodecLimits(
  maxEncodedBytes: 1 << 20,
  maxDecodedBytes: 1 << 20,
  maxFieldBytes: 1 << 18,
  maxCards: 96,
  maxSourceSlices: 432,
  maxBlockLayouts: 4096,
  maxContinuationBytes: 1 << 18,
  maxManifestSegments: 64,
  maxContinuationChainOrdinal: 25,
);

enum _CompatibilityChange {
  none,
  layout,
  renderer,
  pagination,
  compound,
  source,
  unsupportedPagination,
}

final class _Material {
  const _Material({
    required this.oldHarness,
    required this.currentHarness,
    required this.oldRecord,
    required this.oldAdmission,
    required this.oldContext,
    required this.currentContext,
  });

  final ReaderCorePaginationHarness oldHarness;
  final ReaderCorePaginationHarness currentHarness;
  final CanonicalDisplaySegmentRecord oldRecord;
  final CanonicalDisplaySegmentAdmissionResult oldAdmission;
  final CanonicalDisplaySegmentAdmissionContext oldContext;
  final CanonicalDisplaySegmentAdmissionContext currentContext;
}

Future<void> _verifyStrictMigration(
  WidgetTester tester,
  ReaderCoreParsedFixture fixture,
  ({
    String label,
    _CompatibilityChange change,
    ReaderCorePaginationLayout layout,
  })
  entry,
) async {
  final material = await _material(
    tester,
    fixture,
    currentLayout: entry.layout,
    oldChange: entry.change == _CompatibilityChange.layout
        ? _CompatibilityChange.none
        : entry.change,
  );
  final outcome = await _execute(
    tester: tester,
    material: material,
    label: entry.label,
  );
  expect(
    outcome.kind,
    CanonicalDisplayMigrationOutcomeKind.regeneratedCanonicalMigration,
    reason: entry.label,
  );
  final record = outcome.record!;
  expect(record.keyDigest, isNot(material.oldRecord.keyDigest));
  expect(record.checksumDigest, isNot(material.oldRecord.checksumDigest));
  expect(
    record.compatibilityEvidence.readerCompatibility.fingerprint,
    material
        .currentContext
        .currentCompatibilityEvidence
        .readerCompatibilityIdentity!
        .fingerprint,
  );
  expect(outcome.replacementReceipt!.invalidation.completed, isTrue);
  expect(outcome.diagnostics.copiedOldCardIdentityBytes, 0);
  expect(outcome.diagnostics.copiedSourceTextIdentityBytes, 0);
  expect(outcome.diagnostics.mutableIndexAuthorityBytes, 0);
  expect(outcome.diagnostics.partialRecordsExposed, 0);
  expect(outcome.diagnostics.protectedDataMutations, 0);
  expect(outcome.diagnostics.liveCacheWrites, 0);
  expect(
    outcome.diagnostics.compatibilityDimensionsChanged,
    entry.change == _CompatibilityChange.compound ? 3 : 1,
  );
  expect(record.exactHalfOpenSourceInterval.orderedOwners, isNotEmpty);
  final coldCurrent = await material.currentHarness.canonicalColdSegments(
    bookStorageScopeDigest: readerSha256('p06-005-storage-scope'),
    label: 'p06-005-current-cold-${entry.label}',
  );
  expect(
    CanonicalDisplaySegmentCodec.encode(coldCurrent.records.first),
    CanonicalDisplaySegmentCodec.encode(record),
  );
  // The current cold record is independently built from current P04 cards;
  // equality proves all F209/F210/F211 values and card signatures were
  // recomputed instead of translated from the old candidate.
  expect(
    record.orderedFinalizedCards
        .map(
          (card) => (
            card.physicalCardSignature,
            card.physicalLayoutCompositeFingerprint,
            card.physicalCardIdentityComponents,
          ),
        )
        .toList(growable: false),
    coldCurrent.records.first.orderedFinalizedCards
        .map(
          (card) => (
            card.physicalCardSignature,
            card.physicalLayoutCompositeFingerprint,
            card.physicalCardIdentityComponents,
          ),
        )
        .toList(growable: false),
  );
  if (entry.change == _CompatibilityChange.layout) {
    expect(outcome.diagnostics.physicalBoundaryChanges, greaterThan(0));
  }
}

Future<_Material> _material(
  WidgetTester tester,
  ReaderCoreParsedFixture fixture, {
  ReaderCorePaginationLayout currentLayout =
      ReaderCorePaginationLayout.standard,
  _CompatibilityChange oldChange = _CompatibilityChange.none,
  int oldRecordIndex = 0,
}) async {
  final oldHarness = await ReaderCorePaginationHarness.install(
    tester: tester,
    sourceChunks: fixture.sourceChunks,
    bookId: 'p06-005-book',
    publicationFingerprint: 'p06-005-publication',
    stateCacheKey: 'p06-005-old',
  );
  final currentHarness = currentLayout == ReaderCorePaginationLayout.standard
      ? oldHarness
      : await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: fixture.sourceChunks,
          layout: currentLayout,
          bookId: 'p06-005-book',
          publicationFingerprint: 'p06-005-publication',
          stateCacheKey: 'p06-005-current',
        );
  final scope = readerSha256('p06-005-storage-scope');
  final cold = await oldHarness.canonicalColdSegments(
    bookStorageScopeDigest: scope,
    label: 'p06-005-old-cold',
  );
  final oldIdentity = _changedIdentity(
    oldHarness.paginatorLayout.contract!.identities.readerCompatibilityIdentity,
    oldChange,
  );
  final oldEvidence = ReaderCompatibilityEvidence.fromIdentity(oldIdentity);
  final oldRecord = _withCompatibility(
    cold.records[oldRecordIndex],
    oldEvidence,
  );
  final restartEncoding =
      oldRecord.leftBoundaryProof.restartContinuationEncoding;
  final acceptedRestart = restartEncoding == null
      ? null
      : (CanonicalPaginationContinuationCodec.decode(restartEncoding)
                as CanonicalPaginationContinuationAccepted)
            .continuation;
  final oldContext = _context(
    harness: oldHarness,
    compatibility: oldEvidence,
    scope: scope,
    acceptedCards: cold.construction.state.canonicalCards,
    support: _supportFor(oldIdentity),
    acceptedRestart: acceptedRestart,
  );
  final oldAdmission = CanonicalDisplaySegmentAdmission.admitMemoryRecord(
    record: oldRecord,
    limits: _limits,
    context: oldContext,
  );
  expect(oldAdmission.isExact, isTrue, reason: oldAdmission.diagnostics);
  final currentIdentity = currentHarness
      .paginatorLayout
      .contract!
      .identities
      .readerCompatibilityIdentity;
  final currentEvidence = ReaderCompatibilityEvidence.fromIdentity(
    currentIdentity,
  );
  final currentContext = _context(
    harness: currentHarness,
    compatibility: currentEvidence,
    scope: scope,
    acceptedCards: const <CanonicalFinalizedReaderCard>[],
    support: oldChange == _CompatibilityChange.unsupportedPagination
        ? _supportFor(currentIdentity)
        : _supportFor(oldIdentity, current: currentIdentity),
  );
  return _Material(
    oldHarness: oldHarness,
    currentHarness: currentHarness,
    oldRecord: oldRecord,
    oldAdmission: oldAdmission,
    oldContext: oldContext,
    currentContext: currentContext,
  );
}

Future<CanonicalDisplayMigrationOutcome> _execute({
  required WidgetTester tester,
  required _Material material,
  required String label,
  CanonicalDisplayCacheMigrationService service =
      const CanonicalDisplayCacheMigrationService(),
  CanonicalDisplayMigrationReplacementTarget? target,
  bool Function()? stale,
  bool Function()? cancelled,
  bool workBudgetExhausted = false,
}) async {
  final temporaryRoot = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('nalori_p06_005_'),
  ))!;
  final disk = CanonicalDisplaySegmentControlledDiskStore(
    rootDirectory: temporaryRoot,
  );
  await tester.runAsync(() => disk.write(material.oldRecord));
  final replacement =
      target ??
      _ControlledTarget(
        disk: disk,
        memory: CanonicalDisplaySegmentMemoryTransport(),
        oldKeyDigest: material.oldRecord.keyDigest,
        scope: CanonicalDisplayInvalidationStorageScope(
          rootDirectory: temporaryRoot,
          bookScope: 'p06-005-controlled-book',
        ),
      );
  try {
    return (await tester.runAsync(
      () => service.execute(
        candidate: CanonicalDisplayMigrationCandidate.strictCanonical(
          canonicalBytes: CanonicalDisplaySegmentCodec.encode(
            material.oldRecord,
          ),
        ),
        oldAdmission: material.oldAdmission,
        currentContext: material.currentContext,
        limits: _limits,
        regenerate: (_) => _regenerate(
          harness: material.currentHarness,
          context: material.currentContext,
          label: label,
          workBudgetExhausted: workBudgetExhausted,
        ),
        replacementTarget: replacement,
        isCancelled: cancelled ?? () => false,
        isStale: stale ?? () => false,
      ),
    ))!;
  } finally {
    if (target == null &&
        (await tester.runAsync(temporaryRoot.exists) ?? false)) {
      await tester.runAsync(() => temporaryRoot.delete(recursive: true));
    }
  }
}

Future<CanonicalDisplayMigrationRegeneration> _regenerate({
  required ReaderCorePaginationHarness harness,
  required CanonicalDisplaySegmentAdmissionContext context,
  required String label,
  required bool workBudgetExhausted,
}) async {
  final session = harness.canonicalSessionForP04(deferPublicationCommit: true);
  final result = await session.generateInitial(
    restart: const CanonicalPaginationPublicationStart(),
    operation: harness.canonicalOperationForP04(),
    budget: const CanonicalPaginationWorkBudget(maxSourceChunks: 8),
  );
  if (result is! CanonicalReaderPaginationPathAccepted ||
      result.publishableCards.isEmpty) {
    throw StateError('Current bounded P04 regeneration was unavailable.');
  }
  final state = _state(harness, label);
  const generation = 5005;
  return CanonicalDisplayMigrationRegeneration(
    publicationState: state,
    publicationRequest: CanonicalDisplayPublicationRequest(
      operation: CanonicalDisplayPublicationOperation.initial,
      sessionIdentity: 'p06-005|$label',
      generationIdentity: generation,
      currentGenerationIdentity: () => generation,
      sourceSnapshot: session.sourceSnapshot,
      controlledLayoutIdentity: context.controlledLayoutIdentity,
      paginationAlgorithmIdentity: context.paginationAlgorithmIdentity,
      finalizedCards: result.publishableCards,
      continuation: result.continuation,
      isCancelled: () => false,
    ),
    acceptedRestart: null,
    sourceUnitsRegenerated: result.boundedWorkEntriesConsumed,
    cardsRegenerated: result.publishableCards.length,
    commitPaginationPublication: () => session.commitPublication(result),
    workBudgetExhausted: workBudgetExhausted,
  );
}

CanonicalDisplaySegmentAdmissionContext _context({
  required ReaderCorePaginationHarness harness,
  required ReaderCompatibilityEvidence compatibility,
  required String scope,
  required List<CanonicalFinalizedReaderCard> acceptedCards,
  required ReaderCompatibilityRevisionSupport support,
  CanonicalPaginationContinuation? acceptedRestart,
}) {
  final session = harness.canonicalSessionForP04();
  return CanonicalDisplaySegmentAdmissionContext(
    bookStorageScopeDigest: scope,
    publicationFingerprint: session.sourceSnapshot.publicationFingerprint,
    sourceSnapshot: session.sourceSnapshot,
    currentCompatibilityEvidence: compatibility,
    supportedCompatibilityRevisions: support,
    controlledLayoutIdentity: harness.layoutIdentity,
    paginationAlgorithmIdentity: readerPaginationAlgorithmVersion,
    acceptedFinalizedCards: acceptedCards,
    acceptedRestart: acceptedRestart,
  );
}

ProgressiveDisplayState _state(
  ReaderCorePaginationHarness harness,
  String label,
) => ProgressiveDisplayState(
  signature: DisplayGenerationSignature(
    bookId: harness.bookId,
    parsedContentVersion: 1,
    layoutSignature: harness.layoutIdentity,
    settingsSignature: 'p06-005',
    viewportSignature: harness.environment.inputs.diagnosticJson,
    cacheKey: label,
  ),
  sourceChunkCount: harness.sourceChunks.length,
);

CanonicalDisplaySegmentRecord _withCompatibility(
  CanonicalDisplaySegmentRecord record,
  ReaderCompatibilityEvidence compatibility,
) {
  final evidence =
      CanonicalDisplaySegmentCompatibilityEvidence.fromReaderEvidence(
        compatibility,
      );
  final oldKey = CanonicalDisplaySegmentKey.decode(
    record.canonicalKeyBytes,
    limits: _limits,
  );
  return CanonicalDisplaySegmentRecord.create(
    key: CanonicalDisplaySegmentKey(
      bookStorageScopeDigest: oldKey.bookStorageScopeDigest,
      publicationFingerprint: oldKey.publicationFingerprint,
      sourceCompatibilityFingerprint: evidence.sourceCompatibility.fingerprint,
      layoutMetricsFingerprint: evidence.layoutMetrics.fingerprint,
      rendererLayoutFingerprint: evidence.rendererLayout.fingerprint,
      paginationAlgorithmFingerprint: evidence.paginationAlgorithm.fingerprint,
      compatibilityClassifierRevision: evidence.classifierRevision,
      readerCompatibilityFingerprint: evidence.readerCompatibility.fingerprint,
      stableStartCursor: oldKey.stableStartCursor,
      stableEndCursor: oldKey.stableEndCursor,
      boundaryRole: oldKey.boundaryRole,
    ),
    compatibilityEvidence: evidence,
    sourceSnapshotLink: record.sourceSnapshotLink,
    exactHalfOpenSourceInterval: record.exactHalfOpenSourceInterval,
    orderedFinalizedCards: record.orderedFinalizedCards,
    leftBoundaryProof: record.leftBoundaryProof,
    rightBoundaryProof: record.rightBoundaryProof,
    continuationEvidence: record.continuationEvidence,
    manifestRevision: record.manifestBinding.manifestRevision,
  );
}

ReaderCompatibilityIdentity _changedIdentity(
  ReaderCompatibilityIdentity base,
  _CompatibilityChange change,
) {
  LayoutMetricsIdentity? layout;
  SourceCompatibilityIdentity? source;
  PaginationAlgorithmIdentity? pagination;
  RendererLayoutIdentity? renderer;
  if (change == _CompatibilityChange.renderer ||
      change == _CompatibilityChange.compound) {
    final bytes = _replaceAscii(
      base.rendererLayoutIdentity.canonicalBytes,
      readerRendererRulesRevision,
      'reader_renderer_layout_v2',
    );
    renderer = RendererLayoutIdentity(
      rulesRevisionLink: 'reader_renderer_layout_v2',
      canonicalBytes: bytes,
      fingerprint: ReaderFontCanonicalEncoder.digest(bytes),
    );
  }
  if (change == _CompatibilityChange.pagination ||
      change == _CompatibilityChange.compound ||
      change == _CompatibilityChange.unsupportedPagination) {
    const revision = 'nalori_cards_v17_lists';
    final bytes = _replaceAscii(
      base.paginationAlgorithmIdentity.canonicalBytes,
      readerPaginationSemanticRevision,
      revision,
    );
    pagination = PaginationAlgorithmIdentity(
      semanticRevision: revision,
      canonicalBytes: bytes,
      fingerprint: ReaderFontCanonicalEncoder.digest(bytes),
    );
  }
  if (change == _CompatibilityChange.source) {
    final bytes = _replaceAscii(
      base.sourceCompatibilityIdentity.canonicalBytes,
      readerStructuralOwnershipRevision,
      'p04_structural_ownership_v2',
    );
    source = SourceCompatibilityIdentity(
      canonicalBytes: bytes,
      fingerprint: ReaderFontCanonicalEncoder.digest(bytes),
    );
  }
  if (change == _CompatibilityChange.layout ||
      change == _CompatibilityChange.compound) {
    // The actual split-stress current contract supplies the layout transition.
    layout = base.layoutMetricsIdentity;
  }
  return ReaderCompatibilityIdentity.compose(
    layoutMetricsIdentity: layout ?? base.layoutMetricsIdentity,
    sourceCompatibilityIdentity: source ?? base.sourceCompatibilityIdentity,
    paginationAlgorithmIdentity: pagination ?? base.paginationAlgorithmIdentity,
    rendererLayoutIdentity: renderer ?? base.rendererLayoutIdentity,
    classifierRevision: base.classifierRevision,
  );
}

ReaderCompatibilityRevisionSupport _supportFor(
  ReaderCompatibilityIdentity old, {
  ReaderCompatibilityIdentity? current,
}) => ReaderCompatibilityRevisionSupport(
  layoutContractRevisions: const <String>[readerLayoutContractRevision],
  layoutMetricsIdentityRevisions: const <String>[
    readerLayoutMetricsIdentityRevision,
  ],
  parserSourceSchemaIdentities: const <String>['reader-core-fixture-parser'],
  structuralOwnershipRevisions: const <String>[
    readerStructuralOwnershipRevision,
    'p04_structural_ownership_v2',
  ],
  paginationSemanticRevisions: <String>[
    old.paginationAlgorithmIdentity.semanticRevision,
    if (current != null) current.paginationAlgorithmIdentity.semanticRevision,
  ],
  rendererRulesRevisions: <String>[
    old.rendererLayoutIdentity.rulesRevisionLink,
    if (current != null) current.rendererLayoutIdentity.rulesRevisionLink,
  ],
  classifierRevisions: const <String>[readerCompatibilityClassifierRevision],
);

Uint8List _replaceAscii(Uint8List source, String oldValue, String newValue) {
  final oldBytes = ascii.encode(oldValue);
  final newBytes = ascii.encode(newValue);
  expect(newBytes.length, oldBytes.length);
  final copy = Uint8List.fromList(source);
  for (var start = 0; start <= copy.length - oldBytes.length; start += 1) {
    if (Iterable<int>.generate(
      oldBytes.length,
      (index) => index,
    ).every((index) => copy[start + index] == oldBytes[index])) {
      copy.setRange(start, start + oldBytes.length, newBytes);
      return copy;
    }
  }
  throw StateError('Expected canonical compatibility component was absent.');
}

final class _ControlledTarget
    implements CanonicalDisplayMigrationReplacementTarget {
  _ControlledTarget({
    required this.disk,
    required this.memory,
    required this.oldKeyDigest,
    required this.scope,
    this.afterRetainValidatedRecord,
  });

  final CanonicalDisplaySegmentControlledDiskStore disk;
  final CanonicalDisplaySegmentMemoryTransport memory;
  final String oldKeyDigest;
  final void Function()? afterRetainValidatedRecord;
  @override
  final CanonicalDisplayInvalidationStorageScope scope;

  @override
  CanonicalDisplayInvalidationCandidateType get oldCandidateType =>
      CanonicalDisplayInvalidationCandidateType.strictCanonicalDisplay;

  @override
  Future<CanonicalDisplayMigrationStorageWriteReceipt> retainValidatedRecord(
    CanonicalDisplaySegmentRecord record,
  ) async {
    await disk.write(record);
    memory.put(record);
    afterRetainValidatedRecord?.call();
    return CanonicalDisplayMigrationStorageWriteReceipt(
      recordsRetained: 1,
      recordBytes: CanonicalDisplaySegmentCodec.encode(record).length,
    );
  }

  @override
  Future<CanonicalDisplayInvalidationLookupReceipt?>
  oldCandidateLookupReceipt() async {
    final receipt = await disk.lookupForMigrationReplacement(
      scope: scope,
      trustedKeyDigest: oldKeyDigest,
    );
    return receipt is CanonicalDisplayInvalidationLookupReceipt
        ? receipt
        : _NoOpControlledReceipt(scope);
  }
}

final class _NoOpControlledReceipt
    implements CanonicalDisplayInvalidationLookupReceipt {
  const _NoOpControlledReceipt(this.scope);

  @override
  final CanonicalDisplayInvalidationStorageScope scope;

  @override
  CanonicalDisplayInvalidationCandidateType get candidateType =>
      CanonicalDisplayInvalidationCandidateType.strictCanonicalDisplay;

  @override
  Future<CanonicalDisplayInvalidationPhysicalMutation> mutate(
    CanonicalDisplayInvalidationAction action, {
    CanonicalDisplayInvalidationMutationInterceptor? interceptor,
  }) async {
    if (action !=
        CanonicalDisplayInvalidationAction.invalidateExactDiskDerivative) {
      return const CanonicalDisplayInvalidationPhysicalMutation(
        status: CanonicalDisplayInvalidationMutationStatus.failed,
        physicalFilesTouched: 0,
        manifestEntriesTouched: 0,
        recordsQuarantined: 0,
        memoryEntriesEvicted: 0,
        diagnosticCode: 'unsafe_noop_action',
      );
    }
    return const CanonicalDisplayInvalidationPhysicalMutation.noOp();
  }
}
