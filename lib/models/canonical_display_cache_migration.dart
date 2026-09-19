import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'canonical_display_cache_invalidation.dart';
import 'canonical_display_segment.dart';
import 'reader_compatibility.dart';

/// The physical or logical input being assessed. Legacy values are labels only:
/// their cards, visible text, maps, and integer ranges never enter migration.
enum CanonicalDisplayMigrationCandidateKind {
  wholeDisplayCache,
  segmentedLegacyRecord,
  sectionScopedLegacyRecord,
  sectionMemoryRecord,
  chapterLayoutRecord,
  rawDisplayRangeResult,
  checkpointOrStableLocation,
  continuationOnly,
  liveP04CardWithP05Evidence,
  strictCanonicalRecord,
}

enum CanonicalDisplayMigrationReason {
  exactRecordMigrationNotRequired,
  regeneratedCanonicalMigration,
  nonmigratableLegacyEvidence,
  incompleteEvidence,
  corruptEvidence,
  unsupportedFutureRevisionRetained,
  sourceCorrespondenceUnavailable,
  sourceCorrespondenceAmbiguous,
  incompatiblePublicationOrBookScope,
  migrationWorkBudgetExhausted,
  staleRequest,
  cancelledRequest,
  currentContractUnavailable,
  regeneratedRecordFailedStrictAdmission,
  controlledReplacementFailed,
  boundedSourceRegenerationRequired,
}

enum CanonicalDisplayMigrationOutcomeKind {
  exactRecordMigrationNotRequired,
  regeneratedCanonicalMigration,
  nonmigratableLegacyEvidence,
  incompleteEvidence,
  corruptEvidence,
  unsupportedFutureRevisionRetained,
  sourceCorrespondenceUnavailable,
  sourceCorrespondenceAmbiguous,
  incompatiblePublicationOrBookScope,
  migrationWorkBudgetExhausted,
  staleRequest,
  cancelledRequest,
  currentContractUnavailable,
  regeneratedRecordFailedStrictAdmission,
  controlledReplacementFailed,
  boundedSourceRegenerationRequired,
}

/// Opaque input bytes for the one strict record family. The caller must also
/// present its prior P06 exact-admission result to the migration service; raw
/// bytes alone never acquire old-card or publication authority.
@immutable
final class CanonicalDisplayMigrationCandidate {
  CanonicalDisplayMigrationCandidate.legacy({required this.kind})
    : _strictCanonicalBytes = null {
    assert(
      kind != CanonicalDisplayMigrationCandidateKind.strictCanonicalRecord,
    );
  }

  CanonicalDisplayMigrationCandidate.strictCanonical({
    required List<int> canonicalBytes,
  }) : kind = CanonicalDisplayMigrationCandidateKind.strictCanonicalRecord,
       _strictCanonicalBytes = Uint8List.fromList(canonicalBytes) {
    if (_strictCanonicalBytes!.isEmpty) {
      throw ArgumentError('A strict canonical candidate needs encoded bytes.');
    }
  }

  final CanonicalDisplayMigrationCandidateKind kind;
  final Uint8List? _strictCanonicalBytes;

  Uint8List? get strictCanonicalBytes => _strictCanonicalBytes == null
      ? null
      : Uint8List.fromList(_strictCanonicalBytes);
}

@immutable
final class CanonicalDisplayMigrationPlan {
  CanonicalDisplayMigrationPlan({
    required this.candidateKind,
    required this.eligibility,
    required this.reason,
    required List<ReaderCompatibilityIdentityDimension> changedDimensions,
    this.oldRecord,
    this.compatibilityClassification,
    required this.sourceRemapCandidatesInspected,
  }) : changedDimensions =
           List<ReaderCompatibilityIdentityDimension>.unmodifiable(
             changedDimensions,
           );

  final CanonicalDisplayMigrationCandidateKind candidateKind;
  final CanonicalDisplayMigrationEligibility eligibility;
  final CanonicalDisplayMigrationReason reason;
  final List<ReaderCompatibilityIdentityDimension> changedDimensions;
  final CanonicalDisplaySegmentRecord? oldRecord;
  final ReaderCompatibilityClassificationResult? compatibilityClassification;
  final int sourceRemapCandidatesInspected;

  bool get isEligible =>
      eligibility ==
      CanonicalDisplayMigrationEligibility
          .strictCanonicalEvidenceMaySupportMigration;

  bool get hasMigratedCards => false;
  bool get hasNewContinuationAuthority => false;
  bool get hasPublicationAuthority => false;
  bool get hasCheckpointOrSettlementAuthority => false;
  bool get hasLiveCacheWriteAuthority => false;
  bool get mayDeleteDeferredCandidate => false;

  int get diagnosticBytes => utf8
      .encode(
        jsonEncode(<String, Object?>{
          'candidate': candidateKind.name,
          'eligibility': eligibility.name,
          'reason': reason.name,
          'changed': changedDimensions.map((value) => value.name).toList(),
          'oldDigest': oldRecord?.checksumDigest,
          'remapCandidates': sourceRemapCandidatesInspected,
        }),
      )
      .length;
}

@immutable
final class CanonicalDisplayMigrationStorageWriteReceipt {
  const CanonicalDisplayMigrationStorageWriteReceipt({
    required this.recordsRetained,
    required this.recordBytes,
  });

  final int recordsRetained;
  final int recordBytes;
}

/// Controlled-only destination. Implementations are allowed to retain a fully
/// admitted record, but cannot choose a legacy deletion target. The latter is
/// always delegated to P06-004 through [oldCandidateLookupReceipt].
abstract interface class CanonicalDisplayMigrationReplacementTarget {
  CanonicalDisplayInvalidationStorageScope get scope;
  CanonicalDisplayInvalidationCandidateType get oldCandidateType;

  Future<CanonicalDisplayMigrationStorageWriteReceipt> retainValidatedRecord(
    CanonicalDisplaySegmentRecord record,
  );

  Future<CanonicalDisplayInvalidationLookupReceipt?>
  oldCandidateLookupReceipt();
}

@immutable
final class CanonicalDisplayMigrationReplacementReceipt {
  const CanonicalDisplayMigrationReplacementReceipt({
    required this.storageWrite,
    required this.invalidation,
  });

  final CanonicalDisplayMigrationStorageWriteReceipt storageWrite;
  final CanonicalDisplayInvalidationReceipt invalidation;
}

@immutable
final class CanonicalDisplayMigrationDiagnostics {
  const CanonicalDisplayMigrationDiagnostics({
    required this.assessmentBytes,
    required this.resultBytes,
    required this.oldRecordBytes,
    required this.newRecordBytes,
    required this.sourceUnitsRegenerated,
    required this.cardsRegenerated,
    required this.physicalBoundaryChanges,
    required this.compatibilityDimensionsChanged,
    required this.sourceRemapCandidatesInspected,
    required this.controlledRecordsRetained,
    required this.controlledRecordsReplaced,
    required this.migrationAttemptsPerRecord,
    required this.copiedOldCardIdentityBytes,
    required this.copiedSourceTextIdentityBytes,
    required this.mutableIndexAuthorityBytes,
    required this.partialRecordsExposed,
    required this.protectedDataMutations,
    required this.liveCacheWrites,
  });

  final int assessmentBytes;
  final int resultBytes;
  final int oldRecordBytes;
  final int newRecordBytes;
  final int sourceUnitsRegenerated;
  final int cardsRegenerated;
  final int physicalBoundaryChanges;
  final int compatibilityDimensionsChanged;
  final int sourceRemapCandidatesInspected;
  final int controlledRecordsRetained;
  final int controlledRecordsReplaced;
  final int migrationAttemptsPerRecord;
  final int copiedOldCardIdentityBytes;
  final int copiedSourceTextIdentityBytes;
  final int mutableIndexAuthorityBytes;
  final int partialRecordsExposed;
  final int protectedDataMutations;
  final int liveCacheWrites;
}

@immutable
final class CanonicalDisplayMigrationOutcome {
  const CanonicalDisplayMigrationOutcome({
    required this.kind,
    required this.plan,
    required this.diagnostics,
    this.record,
    this.replacementReceipt,
  });

  final CanonicalDisplayMigrationOutcomeKind kind;
  final CanonicalDisplayMigrationPlan plan;
  final CanonicalDisplayMigrationDiagnostics diagnostics;
  final CanonicalDisplaySegmentRecord? record;
  final CanonicalDisplayMigrationReplacementReceipt? replacementReceipt;

  bool get succeeded =>
      kind ==
      CanonicalDisplayMigrationOutcomeKind.regeneratedCanonicalMigration;
  bool get hasMigratedCards => false;
  bool get hasNewContinuationAuthority => false;
  bool get hasPublicationAuthority => false;
  bool get hasCheckpointOrSettlementAuthority => false;
  bool get hasLiveCacheWriteAuthority => false;
  bool get mayDeleteDeferredCandidate => false;
}
