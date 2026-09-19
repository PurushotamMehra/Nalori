import '../models/canonical_display_cache_invalidation.dart';
import 'canonical_display_segment_admission.dart';

/// Shared P06-004 policy and executor for display derivatives. This class
/// intentionally cannot publish cards, mutate checkpoints, create cache
/// records, perform migration, or clear a cache root.
final class CanonicalDisplayCacheInvalidationService {
  const CanonicalDisplayCacheInvalidationService({this.mutationInterceptor});

  final CanonicalDisplayInvalidationMutationInterceptor? mutationInterceptor;

  CanonicalDisplayInvalidationPlan planFor({
    required CanonicalDisplaySegmentValidationOutcome admissionOutcome,
    required CanonicalDisplayInvalidationCandidateType candidateType,
    required CanonicalDisplayMigrationEligibility migrationEligibility,
  }) {
    final diskAction =
        candidateType == CanonicalDisplayInvalidationCandidateType.sectionMemory
        ? CanonicalDisplayInvalidationAction.evictExactMemoryEntry
        : CanonicalDisplayInvalidationAction.invalidateExactDiskDerivative;
    final corruptAction =
        candidateType == CanonicalDisplayInvalidationCandidateType.sectionMemory
        ? CanonicalDisplayInvalidationAction.evictExactMemoryEntry
        : CanonicalDisplayInvalidationAction.quarantineExactDiskDerivative;
    final preserveForMigration =
        migrationEligibility ==
        CanonicalDisplayMigrationEligibility
            .strictCanonicalEvidenceMaySupportMigration;

    CanonicalDisplayInvalidationReason reason;
    CanonicalDisplayInvalidationAction action;
    switch (admissionOutcome) {
      case CanonicalDisplaySegmentValidationOutcome.exactCanonicalCompatible:
        reason = CanonicalDisplayInvalidationReason.exactCanonicalCompatible;
        action = CanonicalDisplayInvalidationAction.noAction;
      case CanonicalDisplaySegmentValidationOutcome.safeMissAbsent:
        reason = CanonicalDisplayInvalidationReason.absent;
        action = CanonicalDisplayInvalidationAction.noAction;
      case CanonicalDisplaySegmentValidationOutcome
          .safeMissIncompleteCanonicalEvidence:
        reason = CanonicalDisplayInvalidationReason.incompleteCanonicalEvidence;
        action =
            migrationEligibility ==
                CanonicalDisplayMigrationEligibility.knownNonmigratable
            ? diskAction
            : CanonicalDisplayInvalidationAction.deferMigrationAssessment;
      case CanonicalDisplaySegmentValidationOutcome
          .safeMissIncompatibleSourceOrParser:
        reason = CanonicalDisplayInvalidationReason.incompatibleSourceOrParser;
        action = preserveForMigration
            ? CanonicalDisplayInvalidationAction.deferMigrationAssessment
            : migrationEligibility ==
                  CanonicalDisplayMigrationEligibility.knownNonmigratable
            ? diskAction
            : CanonicalDisplayInvalidationAction.deferMigrationAssessment;
      case CanonicalDisplaySegmentValidationOutcome.safeMissChangedLayout:
        reason = CanonicalDisplayInvalidationReason.changedLayout;
        action = preserveForMigration
            ? CanonicalDisplayInvalidationAction.deferMigrationAssessment
            : migrationEligibility ==
                  CanonicalDisplayMigrationEligibility.knownNonmigratable
            ? diskAction
            : CanonicalDisplayInvalidationAction.deferMigrationAssessment;
      case CanonicalDisplaySegmentValidationOutcome
          .safeMissChangedRendererRules:
        reason = CanonicalDisplayInvalidationReason.changedRendererRules;
        action = preserveForMigration
            ? CanonicalDisplayInvalidationAction.deferMigrationAssessment
            : migrationEligibility ==
                  CanonicalDisplayMigrationEligibility.knownNonmigratable
            ? diskAction
            : CanonicalDisplayInvalidationAction.deferMigrationAssessment;
      case CanonicalDisplaySegmentValidationOutcome
          .safeMissChangedPaginationAlgorithm:
        reason = CanonicalDisplayInvalidationReason.changedPaginationAlgorithm;
        action = preserveForMigration
            ? CanonicalDisplayInvalidationAction.deferMigrationAssessment
            : migrationEligibility ==
                  CanonicalDisplayMigrationEligibility.knownNonmigratable
            ? diskAction
            : CanonicalDisplayInvalidationAction.deferMigrationAssessment;
      case CanonicalDisplaySegmentValidationOutcome.safeMissUnsupportedRevision:
        reason = CanonicalDisplayInvalidationReason.unsupportedFutureRevision;
        action =
            CanonicalDisplayInvalidationAction.retainUnsupportedFutureRecord;
      case CanonicalDisplaySegmentValidationOutcome
          .rejectedCorruptChecksumOrEncoding:
        reason = CanonicalDisplayInvalidationReason.corruptChecksumOrEncoding;
        action = corruptAction;
      case CanonicalDisplaySegmentValidationOutcome.rejectedBoundaryMismatch:
        reason = CanonicalDisplayInvalidationReason.boundaryMismatch;
        action = corruptAction;
      case CanonicalDisplaySegmentValidationOutcome
          .rejectedContinuationMismatch:
        reason = CanonicalDisplayInvalidationReason.continuationMismatch;
        action = corruptAction;
      case CanonicalDisplaySegmentValidationOutcome
          .rejectedCardIdentityOrContentMismatch:
        reason =
            CanonicalDisplayInvalidationReason.cardIdentityOrContentMismatch;
        action = corruptAction;
      case CanonicalDisplaySegmentValidationOutcome.rejectedStaleGeneration:
        reason = CanonicalDisplayInvalidationReason.staleGeneration;
        action =
            candidateType ==
                CanonicalDisplayInvalidationCandidateType.sectionMemory
            ? CanonicalDisplayInvalidationAction.evictExactMemoryEntry
            : CanonicalDisplayInvalidationAction.noAction;
      case CanonicalDisplaySegmentValidationOutcome.rejectedCrossBookScope:
        reason = CanonicalDisplayInvalidationReason.crossBookScope;
        action = corruptAction;
      case CanonicalDisplaySegmentValidationOutcome
          .rejectedCompatibilityEvidenceCorrupt:
        reason =
            CanonicalDisplayInvalidationReason.corruptCompatibilityEvidence;
        action = corruptAction;
      case CanonicalDisplaySegmentValidationOutcome.regenerationRequired:
        reason =
            migrationEligibility ==
                CanonicalDisplayMigrationEligibility.knownNonmigratable
            ? CanonicalDisplayInvalidationReason.legacyNonmigratable
            : CanonicalDisplayInvalidationReason.deferredMigrationAssessment;
        action =
            migrationEligibility ==
                CanonicalDisplayMigrationEligibility.knownNonmigratable
            ? diskAction
            : CanonicalDisplayInvalidationAction.deferMigrationAssessment;
    }
    return CanonicalDisplayInvalidationPlan(
      admissionOutcomeName: admissionOutcome.name,
      candidateType: candidateType,
      migrationEligibility: migrationEligibility,
      reason: reason,
      action: action,
      allowsBoundedRegeneration: true,
    );
  }

  /// P06-005 may remove an already validated old controlled candidate only
  /// after retaining its fully admitted replacement. This keeps physical
  /// deletion behind the P06-004 receipt boundary rather than migration code.
  CanonicalDisplayInvalidationPlan migrationReplacementPlan({
    required CanonicalDisplayInvalidationCandidateType candidateType,
  }) {
    // P06-005 is not a backdoor to old-format deletion. Only its fully
    // validated strict canonical predecessor may receive this handoff.
    if (candidateType !=
        CanonicalDisplayInvalidationCandidateType.strictCanonicalDisplay) {
      return CanonicalDisplayInvalidationPlan(
        admissionOutcomeName: 'controlled_migration_replacement_rejected',
        candidateType: candidateType,
        migrationEligibility:
            CanonicalDisplayMigrationEligibility.unavailableOrDeferred,
        reason: CanonicalDisplayInvalidationReason.unsafeScopeOrReceipt,
        action: CanonicalDisplayInvalidationAction.failedSafeInvalidation,
        allowsBoundedRegeneration: false,
      );
    }
    return CanonicalDisplayInvalidationPlan(
      admissionOutcomeName: 'controlled_migration_replacement',
      candidateType: candidateType,
      migrationEligibility: CanonicalDisplayMigrationEligibility
          .strictCanonicalEvidenceMaySupportMigration,
      reason: CanonicalDisplayInvalidationReason.controlledMigrationReplacement,
      action: CanonicalDisplayInvalidationAction.invalidateExactDiskDerivative,
      allowsBoundedRegeneration: true,
    );
  }

  Future<CanonicalDisplayInvalidationReceipt> execute({
    required CanonicalDisplayInvalidationStorageScope scope,
    required CanonicalDisplayInvalidationPlan plan,
    CanonicalDisplayInvalidationLookupReceipt? lookupReceipt,
  }) async {
    const noMutationActions = <CanonicalDisplayInvalidationAction>{
      CanonicalDisplayInvalidationAction.noAction,
      CanonicalDisplayInvalidationAction.retainUnsupportedFutureRecord,
      CanonicalDisplayInvalidationAction.deferMigrationAssessment,
      CanonicalDisplayInvalidationAction.failedSafeInvalidation,
    };
    if (noMutationActions.contains(plan.action)) {
      return _receipt(
        plan: plan,
        completed:
            plan.action !=
            CanonicalDisplayInvalidationAction.failedSafeInvalidation,
        retained:
            plan.action ==
                    CanonicalDisplayInvalidationAction
                        .retainUnsupportedFutureRecord ||
                plan.action ==
                    CanonicalDisplayInvalidationAction.deferMigrationAssessment
            ? 1
            : 0,
      );
    }
    if (lookupReceipt == null ||
        lookupReceipt.candidateType != plan.candidateType ||
        !lookupReceipt.scope.matches(scope)) {
      return _receipt(
        plan: _failedPlan(plan),
        completed: false,
        diagnosticCode: 'unsafe_scope_or_receipt',
      );
    }
    try {
      final mutation = await lookupReceipt.mutate(
        plan.action,
        interceptor: mutationInterceptor,
      );
      if (mutation.status ==
          CanonicalDisplayInvalidationMutationStatus.failed) {
        return _receipt(
          plan: _failedPlan(plan),
          completed: false,
          files: mutation.physicalFilesTouched,
          manifestEntries: mutation.manifestEntriesTouched,
          quarantined: mutation.recordsQuarantined,
          memoryEvicted: mutation.memoryEntriesEvicted,
          diagnosticCode: mutation.diagnosticCode ?? 'physical_mutation_failed',
        );
      }
      return _receipt(
        plan: plan,
        completed: true,
        files: mutation.physicalFilesTouched,
        manifestEntries: mutation.manifestEntriesTouched,
        quarantined: mutation.recordsQuarantined,
        memoryEvicted: mutation.memoryEntriesEvicted,
        diagnosticCode: mutation.diagnosticCode,
      );
    } on Object {
      return _receipt(
        plan: _failedPlan(plan),
        completed: false,
        diagnosticCode: 'physical_mutation_threw',
      );
    }
  }

  CanonicalDisplayInvalidationPlan _failedPlan(
    CanonicalDisplayInvalidationPlan plan,
  ) => CanonicalDisplayInvalidationPlan(
    admissionOutcomeName: plan.admissionOutcomeName,
    candidateType: plan.candidateType,
    migrationEligibility: plan.migrationEligibility,
    reason: CanonicalDisplayInvalidationReason.mutationFailure,
    action: CanonicalDisplayInvalidationAction.failedSafeInvalidation,
    allowsBoundedRegeneration: true,
  );

  CanonicalDisplayInvalidationReceipt _receipt({
    required CanonicalDisplayInvalidationPlan plan,
    required bool completed,
    int files = 0,
    int manifestEntries = 0,
    int retained = 0,
    int quarantined = 0,
    int memoryEvicted = 0,
    String? diagnosticCode,
  }) => CanonicalDisplayInvalidationReceipt(
    plan: plan,
    completed: completed,
    physicalFilesTouched: files,
    manifestEntriesTouched: manifestEntries,
    recordsRetained: retained,
    recordsQuarantined: quarantined,
    memoryEntriesEvicted: memoryEvicted,
    protectedRootsInspected: 1,
    sourceTextBytesCopied: 0,
    mutableIndexIdentityBytes: 0,
    cacheWriteAuthorityMutations: 0,
    publicationCheckpointSettlementMutations: 0,
    unrelatedFilesChanged: 0,
    diagnosticCode: diagnosticCode,
  );
}
