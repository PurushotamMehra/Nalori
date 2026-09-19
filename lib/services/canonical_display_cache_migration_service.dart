import 'dart:typed_data';

import '../models/canonical_display_cache_invalidation.dart';
import '../models/canonical_display_cache_migration.dart';
import '../models/canonical_display_segment.dart';
import '../models/canonical_pagination.dart';
import '../models/reader_compatibility.dart';
import 'canonical_display_cache_invalidation_service.dart';
import 'canonical_display_segment_admission.dart';
import 'progressive_display_state.dart';
import 'reader_compatibility_classifier.dart';

/// The bounded current-contract result supplied by the real P04 paginator.
/// It deliberately contains no old cards or source remapping callback.
final class CanonicalDisplayMigrationRegeneration {
  const CanonicalDisplayMigrationRegeneration({
    required this.publicationState,
    required this.publicationRequest,
    required this.acceptedRestart,
    required this.sourceUnitsRegenerated,
    required this.cardsRegenerated,
    required this.commitPaginationPublication,
    this.workBudgetExhausted = false,
  });

  final ProgressiveDisplayState publicationState;
  final CanonicalDisplayPublicationRequest publicationRequest;
  final CanonicalPaginationContinuation? acceptedRestart;
  final int sourceUnitsRegenerated;
  final int cardsRegenerated;
  final bool Function() commitPaginationPublication;
  final bool workBudgetExhausted;
}

typedef CanonicalDisplayMigrationRegenerator =
    Future<CanonicalDisplayMigrationRegeneration> Function(
      CanonicalDisplayMigrationPlan plan,
    );

/// P06-005's sole migration planner/executor. It never interprets a legacy
/// physical card, selects a visible-text match, or exposes publication/cache
/// authority. Successful work returns only a newly rebuilt strict record and
/// the P06-004-controlled replacement receipt.
final class CanonicalDisplayCacheMigrationService {
  const CanonicalDisplayCacheMigrationService({
    this.invalidationService = const CanonicalDisplayCacheInvalidationService(),
  });

  final CanonicalDisplayCacheInvalidationService invalidationService;

  CanonicalDisplayMigrationPlan assess({
    required CanonicalDisplayMigrationCandidate candidate,
    required CanonicalDisplaySegmentAdmissionResult? oldAdmission,
    required CanonicalDisplaySegmentAdmissionContext currentContext,
    required CanonicalDisplaySegmentCodecLimits limits,
  }) {
    if (candidate.kind !=
        CanonicalDisplayMigrationCandidateKind.strictCanonicalRecord) {
      return _plan(
        candidateKind: candidate.kind,
        eligibility: CanonicalDisplayMigrationEligibility.knownNonmigratable,
        reason:
            candidate.kind ==
                CanonicalDisplayMigrationCandidateKind
                    .liveP04CardWithP05Evidence
            ? CanonicalDisplayMigrationReason.incompleteEvidence
            : CanonicalDisplayMigrationReason.nonmigratableLegacyEvidence,
      );
    }
    final bytes = candidate.strictCanonicalBytes;
    if (bytes == null) {
      return _plan(
        candidateKind: candidate.kind,
        eligibility: CanonicalDisplayMigrationEligibility.unavailableOrDeferred,
        reason: CanonicalDisplayMigrationReason.incompleteEvidence,
      );
    }
    final CanonicalDisplaySegmentRecord oldRecord;
    try {
      oldRecord = CanonicalDisplaySegmentCodec.decode(bytes, limits: limits);
    } on Object {
      return _plan(
        candidateKind: candidate.kind,
        eligibility: CanonicalDisplayMigrationEligibility.unavailableOrDeferred,
        reason: CanonicalDisplayMigrationReason.corruptEvidence,
      );
    }
    if (oldAdmission == null ||
        !oldAdmission.isExact ||
        !oldAdmission.hasStrictAdmissionAttestation ||
        oldAdmission.candidate?.checksumDigest != oldRecord.checksumDigest ||
        oldAdmission.candidate?.keyDigest != oldRecord.keyDigest) {
      return _plan(
        candidateKind: candidate.kind,
        eligibility: CanonicalDisplayMigrationEligibility.unavailableOrDeferred,
        reason: CanonicalDisplayMigrationReason.incompleteEvidence,
        oldRecord: oldRecord,
      );
    }
    if (oldRecord.bookStorageScopeDigest !=
            currentContext.bookStorageScopeDigest ||
        oldRecord.publicationFingerprint !=
            currentContext.publicationFingerprint ||
        oldRecord.sourceSnapshotLink.publicationFingerprint !=
            currentContext.publicationFingerprint) {
      return _plan(
        candidateKind: candidate.kind,
        eligibility: CanonicalDisplayMigrationEligibility.unavailableOrDeferred,
        reason:
            CanonicalDisplayMigrationReason.incompatiblePublicationOrBookScope,
        oldRecord: oldRecord,
      );
    }
    final ReaderCompatibilityClassificationResult classification;
    try {
      classification = ReaderCompatibilityClassifier.classify(
        previous: oldRecord.compatibilityEvidence.toReaderEvidence(),
        current: currentContext.currentCompatibilityEvidence,
        supportedRevisions: currentContext.supportedCompatibilityRevisions,
      );
    } on Object {
      return _plan(
        candidateKind: candidate.kind,
        eligibility: CanonicalDisplayMigrationEligibility.unavailableOrDeferred,
        reason: CanonicalDisplayMigrationReason.corruptEvidence,
        oldRecord: oldRecord,
      );
    }
    switch (classification.kind) {
      case ReaderCompatibilityClassificationKind.incompleteEvidence:
        return _plan(
          candidateKind: candidate.kind,
          eligibility:
              CanonicalDisplayMigrationEligibility.unavailableOrDeferred,
          reason: CanonicalDisplayMigrationReason.incompleteEvidence,
          oldRecord: oldRecord,
          classification: classification,
        );
      case ReaderCompatibilityClassificationKind.corruptEvidence:
        return _plan(
          candidateKind: candidate.kind,
          eligibility:
              CanonicalDisplayMigrationEligibility.unavailableOrDeferred,
          reason: CanonicalDisplayMigrationReason.corruptEvidence,
          oldRecord: oldRecord,
          classification: classification,
        );
      case ReaderCompatibilityClassificationKind.unsupportedRevision:
        return _plan(
          candidateKind: candidate.kind,
          eligibility:
              CanonicalDisplayMigrationEligibility.unavailableOrDeferred,
          reason:
              CanonicalDisplayMigrationReason.unsupportedFutureRevisionRetained,
          oldRecord: oldRecord,
          classification: classification,
        );
      case ReaderCompatibilityClassificationKind.exactCompatible:
        return _plan(
          candidateKind: candidate.kind,
          eligibility:
              CanonicalDisplayMigrationEligibility.unavailableOrDeferred,
          reason:
              CanonicalDisplayMigrationReason.exactRecordMigrationNotRequired,
          oldRecord: oldRecord,
          classification: classification,
        );
      case ReaderCompatibilityClassificationKind.sourceCompatibilityChanged:
      case ReaderCompatibilityClassificationKind.multipleAuthoritativeChanges:
        if (classification.changedDimensions.contains(
          ReaderCompatibilityIdentityDimension.sourceCompatibility,
        )) {
          // Production offers no source/parser-version correspondence resolver.
          // In particular, stable-location quote matching is not one.
          return _plan(
            candidateKind: candidate.kind,
            eligibility:
                CanonicalDisplayMigrationEligibility.unavailableOrDeferred,
            reason:
                CanonicalDisplayMigrationReason.sourceCorrespondenceUnavailable,
            oldRecord: oldRecord,
            classification: classification,
          );
        }
        break;
      case ReaderCompatibilityClassificationKind.layoutMetricsChanged:
      case ReaderCompatibilityClassificationKind.paginationAlgorithmChanged:
      case ReaderCompatibilityClassificationKind.rendererLayoutChanged:
        break;
    }
    if (!_sameSnapshot(
          oldRecord.sourceSnapshotLink,
          currentContext.sourceSnapshot,
        ) ||
        !_exactIntervalOwners(oldRecord, currentContext.sourceSnapshot)) {
      return _plan(
        candidateKind: candidate.kind,
        eligibility: CanonicalDisplayMigrationEligibility.unavailableOrDeferred,
        reason: CanonicalDisplayMigrationReason.sourceCorrespondenceUnavailable,
        oldRecord: oldRecord,
        classification: classification,
      );
    }
    return _plan(
      candidateKind: candidate.kind,
      eligibility: CanonicalDisplayMigrationEligibility
          .strictCanonicalEvidenceMaySupportMigration,
      reason: CanonicalDisplayMigrationReason.boundedSourceRegenerationRequired,
      oldRecord: oldRecord,
      classification: classification,
    );
  }

  Future<CanonicalDisplayMigrationOutcome> execute({
    required CanonicalDisplayMigrationCandidate candidate,
    required CanonicalDisplaySegmentAdmissionResult? oldAdmission,
    required CanonicalDisplaySegmentAdmissionContext currentContext,
    required CanonicalDisplaySegmentCodecLimits limits,
    required CanonicalDisplayMigrationRegenerator regenerate,
    required CanonicalDisplayMigrationReplacementTarget replacementTarget,
    required bool Function() isCancelled,
    required bool Function() isStale,
  }) async {
    final plan = assess(
      candidate: candidate,
      oldAdmission: oldAdmission,
      currentContext: currentContext,
      limits: limits,
    );
    if (!plan.isEligible) return _nonSuccess(plan);
    if (isCancelled()) {
      return _outcome(
        plan,
        CanonicalDisplayMigrationOutcomeKind.cancelledRequest,
      );
    }
    if (isStale()) {
      return _outcome(plan, CanonicalDisplayMigrationOutcomeKind.staleRequest);
    }

    final CanonicalDisplayMigrationRegeneration regenerated;
    try {
      regenerated = await regenerate(plan);
    } on Object {
      return _outcome(
        plan,
        CanonicalDisplayMigrationOutcomeKind.currentContractUnavailable,
      );
    }
    if (regenerated.workBudgetExhausted) {
      return _outcome(
        plan,
        CanonicalDisplayMigrationOutcomeKind.migrationWorkBudgetExhausted,
        sourceUnits: regenerated.sourceUnitsRegenerated,
        cards: regenerated.cardsRegenerated,
      );
    }
    if (isCancelled()) {
      return _outcome(
        plan,
        CanonicalDisplayMigrationOutcomeKind.cancelledRequest,
        sourceUnits: regenerated.sourceUnitsRegenerated,
        cards: regenerated.cardsRegenerated,
      );
    }
    if (isStale()) {
      return _outcome(
        plan,
        CanonicalDisplayMigrationOutcomeKind.staleRequest,
        sourceUnits: regenerated.sourceUnitsRegenerated,
        cards: regenerated.cardsRegenerated,
      );
    }
    final publication = regenerated.publicationState.publishCanonical(
      regenerated.publicationRequest,
    );
    if (publication is! CanonicalDisplayPublicationAccepted ||
        !regenerated.commitPaginationPublication()) {
      return _outcome(
        plan,
        publication.kind ==
                CanonicalDisplayPublicationOutcomeKind.cancellationBeforeCommit
            ? CanonicalDisplayMigrationOutcomeKind.cancelledRequest
            : publication.kind ==
                  CanonicalDisplayPublicationOutcomeKind
                      .staleGenerationOrSession
            ? CanonicalDisplayMigrationOutcomeKind.staleRequest
            : CanonicalDisplayMigrationOutcomeKind.currentContractUnavailable,
        sourceUnits: regenerated.sourceUnitsRegenerated,
        cards: regenerated.cardsRegenerated,
      );
    }
    if (isCancelled()) {
      return _outcome(
        plan,
        CanonicalDisplayMigrationOutcomeKind.cancelledRequest,
        sourceUnits: regenerated.sourceUnitsRegenerated,
        cards: regenerated.cardsRegenerated,
      );
    }
    if (isStale()) {
      return _outcome(
        plan,
        CanonicalDisplayMigrationOutcomeKind.staleRequest,
        sourceUnits: regenerated.sourceUnitsRegenerated,
        cards: regenerated.cardsRegenerated,
      );
    }
    final oldRecord = plan.oldRecord!;
    final record = CanonicalDisplaySegmentRecordBuilder.build(
      bookStorageScopeDigest: currentContext.bookStorageScopeDigest,
      compatibilityEvidence:
          CanonicalDisplaySegmentCompatibilityEvidence.fromReaderEvidence(
            currentContext.currentCompatibilityEvidence,
          ),
      sourceSnapshot: regenerated.publicationRequest.sourceSnapshot,
      finalizedCards: publication.publishableCards,
      continuation: publication.continuation,
      acceptedRestart: regenerated.acceptedRestart,
    );
    if (!record.stableStartCursor.samePositionAs(oldRecord.stableStartCursor)) {
      return _outcome(
        plan,
        CanonicalDisplayMigrationOutcomeKind
            .regeneratedRecordFailedStrictAdmission,
        sourceUnits: regenerated.sourceUnitsRegenerated,
        cards: regenerated.cardsRegenerated,
      );
    }
    final strict = CanonicalDisplaySegmentAdmission.admitMemoryRecord(
      record: record,
      limits: limits,
      context: _currentAdmissionContext(currentContext, regenerated),
    );
    if (!strict.isExact) {
      return _outcome(
        plan,
        CanonicalDisplayMigrationOutcomeKind
            .regeneratedRecordFailedStrictAdmission,
        sourceUnits: regenerated.sourceUnitsRegenerated,
        cards: regenerated.cardsRegenerated,
      );
    }
    if (isCancelled()) {
      return _outcome(
        plan,
        CanonicalDisplayMigrationOutcomeKind.cancelledRequest,
        sourceUnits: regenerated.sourceUnitsRegenerated,
        cards: regenerated.cardsRegenerated,
      );
    }
    if (isStale()) {
      return _outcome(
        plan,
        CanonicalDisplayMigrationOutcomeKind.staleRequest,
        sourceUnits: regenerated.sourceUnitsRegenerated,
        cards: regenerated.cardsRegenerated,
      );
    }
    final CanonicalDisplayMigrationStorageWriteReceipt write;
    try {
      write = await replacementTarget.retainValidatedRecord(record);
    } on Object {
      return _outcome(
        plan,
        CanonicalDisplayMigrationOutcomeKind.controlledReplacementFailed,
        sourceUnits: regenerated.sourceUnitsRegenerated,
        cards: regenerated.cardsRegenerated,
        newRecordBytes: CanonicalDisplaySegmentCodec.encode(record).length,
      );
    }
    if (isCancelled()) {
      return _outcome(
        plan,
        CanonicalDisplayMigrationOutcomeKind.cancelledRequest,
        sourceUnits: regenerated.sourceUnitsRegenerated,
        cards: regenerated.cardsRegenerated,
        newRecordBytes: write.recordBytes,
        retained: write.recordsRetained,
      );
    }
    if (isStale()) {
      return _outcome(
        plan,
        CanonicalDisplayMigrationOutcomeKind.staleRequest,
        sourceUnits: regenerated.sourceUnitsRegenerated,
        cards: regenerated.cardsRegenerated,
        newRecordBytes: write.recordBytes,
        retained: write.recordsRetained,
      );
    }
    final replacementPlan = invalidationService.migrationReplacementPlan(
      candidateType: replacementTarget.oldCandidateType,
    );
    final oldReceipt = await replacementTarget.oldCandidateLookupReceipt();
    if (isCancelled()) {
      return _outcome(
        plan,
        CanonicalDisplayMigrationOutcomeKind.cancelledRequest,
        sourceUnits: regenerated.sourceUnitsRegenerated,
        cards: regenerated.cardsRegenerated,
        newRecordBytes: write.recordBytes,
        retained: write.recordsRetained,
      );
    }
    if (isStale()) {
      return _outcome(
        plan,
        CanonicalDisplayMigrationOutcomeKind.staleRequest,
        sourceUnits: regenerated.sourceUnitsRegenerated,
        cards: regenerated.cardsRegenerated,
        newRecordBytes: write.recordBytes,
        retained: write.recordsRetained,
      );
    }
    final invalidation = await invalidationService.execute(
      scope: replacementTarget.scope,
      plan: replacementPlan,
      lookupReceipt: oldReceipt,
    );
    if (!invalidation.completed) {
      return _outcome(
        plan,
        CanonicalDisplayMigrationOutcomeKind.controlledReplacementFailed,
        sourceUnits: regenerated.sourceUnitsRegenerated,
        cards: regenerated.cardsRegenerated,
        newRecordBytes: write.recordBytes,
        retained: write.recordsRetained,
      );
    }
    final receipt = CanonicalDisplayMigrationReplacementReceipt(
      storageWrite: write,
      invalidation: invalidation,
    );
    return CanonicalDisplayMigrationOutcome(
      kind: CanonicalDisplayMigrationOutcomeKind.regeneratedCanonicalMigration,
      plan: plan,
      record: record,
      replacementReceipt: receipt,
      diagnostics: _diagnostics(
        plan: plan,
        kind:
            CanonicalDisplayMigrationOutcomeKind.regeneratedCanonicalMigration,
        oldRecordBytes: CanonicalDisplaySegmentCodec.encode(oldRecord).length,
        newRecordBytes: write.recordBytes,
        sourceUnits: regenerated.sourceUnitsRegenerated,
        cards: regenerated.cardsRegenerated,
        physicalBoundaryChanges: _physicalBoundaryChanges(oldRecord, record),
        retained: write.recordsRetained,
        replaced: invalidation.physicalFilesTouched > 0 ? 1 : 0,
      ),
    );
  }

  CanonicalDisplayMigrationPlan _plan({
    required CanonicalDisplayMigrationCandidateKind candidateKind,
    required CanonicalDisplayMigrationEligibility eligibility,
    required CanonicalDisplayMigrationReason reason,
    CanonicalDisplaySegmentRecord? oldRecord,
    ReaderCompatibilityClassificationResult? classification,
  }) => CanonicalDisplayMigrationPlan(
    candidateKind: candidateKind,
    eligibility: eligibility,
    reason: reason,
    changedDimensions:
        classification?.changedDimensions ??
        const <ReaderCompatibilityIdentityDimension>[],
    oldRecord: oldRecord,
    compatibilityClassification: classification,
    sourceRemapCandidatesInspected: 0,
  );

  CanonicalDisplayMigrationOutcome _nonSuccess(
    CanonicalDisplayMigrationPlan plan,
  ) => _outcome(plan, switch (plan.reason) {
    CanonicalDisplayMigrationReason.exactRecordMigrationNotRequired =>
      CanonicalDisplayMigrationOutcomeKind.exactRecordMigrationNotRequired,
    CanonicalDisplayMigrationReason.nonmigratableLegacyEvidence =>
      CanonicalDisplayMigrationOutcomeKind.nonmigratableLegacyEvidence,
    CanonicalDisplayMigrationReason.corruptEvidence =>
      CanonicalDisplayMigrationOutcomeKind.corruptEvidence,
    CanonicalDisplayMigrationReason.unsupportedFutureRevisionRetained =>
      CanonicalDisplayMigrationOutcomeKind.unsupportedFutureRevisionRetained,
    CanonicalDisplayMigrationReason.sourceCorrespondenceUnavailable =>
      CanonicalDisplayMigrationOutcomeKind.sourceCorrespondenceUnavailable,
    CanonicalDisplayMigrationReason.sourceCorrespondenceAmbiguous =>
      CanonicalDisplayMigrationOutcomeKind.sourceCorrespondenceAmbiguous,
    CanonicalDisplayMigrationReason.incompatiblePublicationOrBookScope =>
      CanonicalDisplayMigrationOutcomeKind.incompatiblePublicationOrBookScope,
    CanonicalDisplayMigrationReason.boundedSourceRegenerationRequired =>
      CanonicalDisplayMigrationOutcomeKind.boundedSourceRegenerationRequired,
    _ => CanonicalDisplayMigrationOutcomeKind.incompleteEvidence,
  });

  CanonicalDisplayMigrationOutcome _outcome(
    CanonicalDisplayMigrationPlan plan,
    CanonicalDisplayMigrationOutcomeKind kind, {
    int sourceUnits = 0,
    int cards = 0,
    int newRecordBytes = 0,
    int retained = 0,
  }) => CanonicalDisplayMigrationOutcome(
    kind: kind,
    plan: plan,
    diagnostics: _diagnostics(
      plan: plan,
      kind: kind,
      oldRecordBytes: plan.oldRecord == null
          ? 0
          : CanonicalDisplaySegmentCodec.encode(plan.oldRecord!).length,
      newRecordBytes: newRecordBytes,
      sourceUnits: sourceUnits,
      cards: cards,
      retained: retained,
    ),
  );

  CanonicalDisplayMigrationDiagnostics _diagnostics({
    required CanonicalDisplayMigrationPlan plan,
    required CanonicalDisplayMigrationOutcomeKind kind,
    required int oldRecordBytes,
    required int newRecordBytes,
    required int sourceUnits,
    required int cards,
    int physicalBoundaryChanges = 0,
    int retained = 0,
    int replaced = 0,
  }) {
    final resultBytes = Uint8List.fromList(<int>[
      ...plan.diagnosticBytes.toString().codeUnits,
      ...kind.name.codeUnits,
    ]).length;
    return CanonicalDisplayMigrationDiagnostics(
      assessmentBytes: plan.diagnosticBytes,
      resultBytes: resultBytes,
      oldRecordBytes: oldRecordBytes,
      newRecordBytes: newRecordBytes,
      sourceUnitsRegenerated: sourceUnits,
      cardsRegenerated: cards,
      physicalBoundaryChanges: physicalBoundaryChanges,
      compatibilityDimensionsChanged: plan.changedDimensions.length,
      sourceRemapCandidatesInspected: plan.sourceRemapCandidatesInspected,
      controlledRecordsRetained: retained,
      controlledRecordsReplaced: replaced,
      migrationAttemptsPerRecord: plan.isEligible ? 1 : 0,
      copiedOldCardIdentityBytes: 0,
      copiedSourceTextIdentityBytes: 0,
      mutableIndexAuthorityBytes: 0,
      partialRecordsExposed: 0,
      protectedDataMutations: 0,
      liveCacheWrites: 0,
    );
  }

  CanonicalDisplaySegmentAdmissionContext _currentAdmissionContext(
    CanonicalDisplaySegmentAdmissionContext current,
    CanonicalDisplayMigrationRegeneration regeneration,
  ) => CanonicalDisplaySegmentAdmissionContext(
    bookStorageScopeDigest: current.bookStorageScopeDigest,
    publicationFingerprint: current.publicationFingerprint,
    sourceSnapshot: regeneration.publicationRequest.sourceSnapshot,
    currentCompatibilityEvidence: current.currentCompatibilityEvidence,
    supportedCompatibilityRevisions: current.supportedCompatibilityRevisions,
    controlledLayoutIdentity: current.controlledLayoutIdentity,
    paginationAlgorithmIdentity: current.paginationAlgorithmIdentity,
    acceptedFinalizedCards: regeneration.publicationState.canonicalCards,
    acceptedPredecessor: current.acceptedPredecessor,
    acceptedSuccessor: current.acceptedSuccessor,
    acceptedRestart: regeneration.acceptedRestart,
  );
}

bool _sameSnapshot(
  CanonicalDisplaySegmentSourceSnapshotLink link,
  CanonicalPaginationSourceSnapshot snapshot,
) =>
    link.snapshotDigest == snapshot.snapshotDigest &&
    link.sourceRevision == snapshot.sourceRevision &&
    link.parserSourceIdentity == snapshot.parserSourceIdentity &&
    link.publicationFingerprint == snapshot.publicationFingerprint &&
    link.sourceCount == snapshot.sourceCount;

bool _exactIntervalOwners(
  CanonicalDisplaySegmentRecord record,
  CanonicalPaginationSourceSnapshot snapshot,
) {
  final start = record.stableStartCursor.sourceOrdinalHint;
  final end = record.stableEndCursor.isLogicalEnd
      ? snapshot.sourceCount
      : record.stableEndCursor.sourceOrdinalHint +
            (record.stableEndCursor.kind ==
                    CanonicalPaginationCursorKind.wholeSource
                ? 0
                : 1);
  if (start < 0 || end <= start || end > snapshot.sourceCount) return false;
  final owners = record.exactHalfOpenSourceInterval.orderedOwners;
  if (owners.length != end - start) return false;
  for (var ordinal = start; ordinal < end; ordinal += 1) {
    final expected = snapshot.ownerAt(ordinal);
    final actual = owners[ordinal - start];
    if (actual.sourceIdentity != expected.sourceIdentity ||
        actual.sectionIdentity != expected.sectionIdentity ||
        actual.spineIdentity != expected.spineIdentity ||
        actual.sourceOrdinalHint != expected.sourceOrdinalHint ||
        actual.sourceDigest != expected.sourceDigest) {
      return false;
    }
  }
  return true;
}

int _physicalBoundaryChanges(
  CanonicalDisplaySegmentRecord oldRecord,
  CanonicalDisplaySegmentRecord newRecord,
) {
  final oldCards = oldRecord.orderedFinalizedCards;
  final newCards = newRecord.orderedFinalizedCards;
  final common = oldCards.length < newCards.length
      ? oldCards.length
      : newCards.length;
  var changed = (oldCards.length - newCards.length).abs();
  for (var index = 0; index < common; index += 1) {
    final oldCard = oldCards[index];
    final newCard = newCards[index];
    if (!oldCard.cardStartCursor.samePositionAs(newCard.cardStartCursor) ||
        !oldCard.cardEndCursor.samePositionAs(newCard.cardEndCursor)) {
      changed += 1;
    }
  }
  return changed;
}
