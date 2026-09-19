import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// The exact physical representation found beneath a caller-owned display
/// cache root. These are storage classifications only; none carries reader
/// publication, checkpoint, settlement, or migration authority.
enum CanonicalDisplayInvalidationCandidateType {
  wholeDisplay,
  segmentedDisplay,
  sectionScopedSegment,
  sectionMemory,
  chapterLayout,
  strictCanonicalDisplay,
}

enum CanonicalDisplayInvalidationReason {
  exactCanonicalCompatible,
  absent,
  incompleteCanonicalEvidence,
  incompatibleSourceOrParser,
  changedLayout,
  changedRendererRules,
  changedPaginationAlgorithm,
  unsupportedFutureRevision,
  corruptChecksumOrEncoding,
  boundaryMismatch,
  continuationMismatch,
  cardIdentityOrContentMismatch,
  staleGeneration,
  crossBookScope,
  corruptCompatibilityEvidence,
  legacyNonmigratable,
  deferredMigrationAssessment,
  controlledMigrationReplacement,
  unsafeScopeOrReceipt,
  mutationFailure,
}

enum CanonicalDisplayInvalidationAction {
  noAction,
  evictExactMemoryEntry,
  invalidateExactDiskDerivative,
  quarantineExactDiskDerivative,
  retainUnsupportedFutureRecord,
  deferMigrationAssessment,
  failedSafeInvalidation,
}

/// P06-004 does not decide migration. This evidence only distinguishes the
/// already-proven legacy safe-miss records from a strict future record that
/// P06-005 must assess without guessing.
enum CanonicalDisplayMigrationEligibility {
  knownNonmigratable,
  strictCanonicalEvidenceMaySupportMigration,
  unavailableOrDeferred,
}

/// A caller-owned, explicit display-cache root. It is deliberately separate
/// from book ids and decoded cache fields so they cannot choose a mutation
/// target. Cache services independently revalidate this scope before every
/// filesystem mutation.
@immutable
final class CanonicalDisplayInvalidationStorageScope {
  CanonicalDisplayInvalidationStorageScope({
    required Directory rootDirectory,
    required this.bookScope,
  }) : rootDirectory = rootDirectory,
       rootPath = p.normalize(rootDirectory.absolute.path) {
    if (bookScope.isEmpty || !p.isAbsolute(rootPath)) {
      throw ArgumentError(
        'A nonempty book scope and absolute root are required.',
      );
    }
  }

  final Directory rootDirectory;
  final String rootPath;
  final String bookScope;

  bool matches(CanonicalDisplayInvalidationStorageScope other) =>
      rootPath == other.rootPath && bookScope == other.bookScope;
}

enum CanonicalDisplayInvalidationMutationStep {
  beforePayloadMutation,
  beforeManifestUpdate,
}

/// Test-only fault seam at real physical mutation boundaries. It does not
/// emulate cache codecs, admission, pagination, or manifest selection.
typedef CanonicalDisplayInvalidationMutationInterceptor =
    FutureOr<void> Function(CanonicalDisplayInvalidationMutationStep step);

enum CanonicalDisplayInvalidationMutationStatus { applied, noOp, failed }

@immutable
final class CanonicalDisplayInvalidationPhysicalMutation {
  const CanonicalDisplayInvalidationPhysicalMutation({
    required this.status,
    required this.physicalFilesTouched,
    required this.manifestEntriesTouched,
    required this.recordsQuarantined,
    required this.memoryEntriesEvicted,
    this.diagnosticCode,
  });

  const CanonicalDisplayInvalidationPhysicalMutation.noOp()
    : status = CanonicalDisplayInvalidationMutationStatus.noOp,
      physicalFilesTouched = 0,
      manifestEntriesTouched = 0,
      recordsQuarantined = 0,
      memoryEntriesEvicted = 0,
      diagnosticCode = null;

  final CanonicalDisplayInvalidationMutationStatus status;
  final int physicalFilesTouched;
  final int manifestEntriesTouched;
  final int recordsQuarantined;
  final int memoryEntriesEvicted;
  final String? diagnosticCode;
}

/// An opaque capability issued only after a cache service has identified one
/// exact record under [scope]. The executor never receives a payload filename,
/// decoded book id, or cache key from which it could derive a physical path.
abstract interface class CanonicalDisplayInvalidationLookupReceipt {
  CanonicalDisplayInvalidationStorageScope get scope;
  CanonicalDisplayInvalidationCandidateType get candidateType;

  Future<CanonicalDisplayInvalidationPhysicalMutation> mutate(
    CanonicalDisplayInvalidationAction action, {
    CanonicalDisplayInvalidationMutationInterceptor? interceptor,
  });
}

@immutable
final class CanonicalDisplayInvalidationPlan {
  const CanonicalDisplayInvalidationPlan({
    required this.admissionOutcomeName,
    required this.candidateType,
    required this.migrationEligibility,
    required this.reason,
    required this.action,
    required this.allowsBoundedRegeneration,
  });

  final String admissionOutcomeName;
  final CanonicalDisplayInvalidationCandidateType candidateType;
  final CanonicalDisplayMigrationEligibility migrationEligibility;
  final CanonicalDisplayInvalidationReason reason;
  final CanonicalDisplayInvalidationAction action;
  final bool allowsBoundedRegeneration;

  int get diagnosticBytes => utf8
      .encode(
        jsonEncode(<String, Object?>{
          'outcome': admissionOutcomeName,
          'type': candidateType.name,
          'migration': migrationEligibility.name,
          'reason': reason.name,
          'action': action.name,
          'regeneration': allowsBoundedRegeneration,
        }),
      )
      .length;
}

@immutable
final class CanonicalDisplayInvalidationReceipt {
  const CanonicalDisplayInvalidationReceipt({
    required this.plan,
    required this.completed,
    required this.physicalFilesTouched,
    required this.manifestEntriesTouched,
    required this.recordsRetained,
    required this.recordsQuarantined,
    required this.memoryEntriesEvicted,
    required this.protectedRootsInspected,
    required this.sourceTextBytesCopied,
    required this.mutableIndexIdentityBytes,
    required this.cacheWriteAuthorityMutations,
    required this.publicationCheckpointSettlementMutations,
    required this.unrelatedFilesChanged,
    this.diagnosticCode,
  });

  final CanonicalDisplayInvalidationPlan plan;
  final bool completed;
  final int physicalFilesTouched;
  final int manifestEntriesTouched;
  final int recordsRetained;
  final int recordsQuarantined;
  final int memoryEntriesEvicted;
  final int protectedRootsInspected;
  final int sourceTextBytesCopied;
  final int mutableIndexIdentityBytes;
  final int cacheWriteAuthorityMutations;
  final int publicationCheckpointSettlementMutations;
  final int unrelatedFilesChanged;
  final String? diagnosticCode;

  int get diagnosticBytes => utf8
      .encode(
        jsonEncode(<String, Object?>{
          'outcome': plan.admissionOutcomeName,
          'type': plan.candidateType.name,
          'reason': plan.reason.name,
          'action': plan.action.name,
          'completed': completed,
          'files': physicalFilesTouched,
          'manifestEntries': manifestEntriesTouched,
          'retained': recordsRetained,
          'quarantined': recordsQuarantined,
          'memoryEvicted': memoryEntriesEvicted,
          'protectedRoots': protectedRootsInspected,
          'sourceTextBytes': sourceTextBytesCopied,
          'mutableIndexIdentityBytes': mutableIndexIdentityBytes,
          'cacheWriteAuthorityMutations': cacheWriteAuthorityMutations,
          'publicationCheckpointSettlementMutations':
              publicationCheckpointSettlementMutations,
          'unrelatedFilesChanged': unrelatedFilesChanged,
          'diagnostic': diagnosticCode,
        }),
      )
      .length;
}
