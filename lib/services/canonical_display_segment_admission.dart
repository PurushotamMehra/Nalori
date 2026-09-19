import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../models/canonical_display_segment.dart';
import '../models/canonical_pagination.dart';
import '../models/reader_checkpoint.dart';
import '../models/reader_compatibility.dart';
import 'reader_compatibility_classifier.dart';

/// The only P06 candidate-admission boundary.  It accepts logical records for
/// inspection only; it neither writes cache data nor grants publication,
/// checkpoint, settlement, or reuse authority.
enum CanonicalDisplaySegmentValidationOutcome {
  exactCanonicalCompatible,
  safeMissAbsent,
  safeMissIncompleteCanonicalEvidence,
  safeMissIncompatibleSourceOrParser,
  safeMissChangedLayout,
  safeMissChangedRendererRules,
  safeMissChangedPaginationAlgorithm,
  safeMissUnsupportedRevision,
  rejectedCorruptChecksumOrEncoding,
  rejectedBoundaryMismatch,
  rejectedContinuationMismatch,
  rejectedCardIdentityOrContentMismatch,
  rejectedStaleGeneration,
  rejectedCrossBookScope,
  rejectedCompatibilityEvidenceCorrupt,
  regenerationRequired,
}

@immutable
final class CanonicalDisplaySegmentAdmissionResult {
  const CanonicalDisplaySegmentAdmissionResult._({
    required this.outcome,
    required this.diagnostics,
    required bool strictAdmissionAttested,
    this.candidate,
    this.exactCandidate,
  }) : _strictAdmissionAttested = strictAdmissionAttested;

  /// Builds nonauthoritative diagnostic evidence. Only the admission service
  /// can create the attested result accepted by migration.
  factory CanonicalDisplaySegmentAdmissionResult.exact({
    required CanonicalDisplaySegmentRecord candidate,
    required CanonicalDisplaySegmentExactCandidate exactCandidate,
    required String diagnostics,
  }) => CanonicalDisplaySegmentAdmissionResult._(
    outcome: CanonicalDisplaySegmentValidationOutcome.exactCanonicalCompatible,
    diagnostics: diagnostics,
    strictAdmissionAttested: false,
    candidate: candidate,
    exactCandidate: exactCandidate,
  );

  factory CanonicalDisplaySegmentAdmissionResult._admittedExact({
    required CanonicalDisplaySegmentRecord candidate,
    required CanonicalDisplaySegmentExactCandidate exactCandidate,
    required String diagnostics,
  }) => CanonicalDisplaySegmentAdmissionResult._(
    outcome: CanonicalDisplaySegmentValidationOutcome.exactCanonicalCompatible,
    diagnostics: diagnostics,
    strictAdmissionAttested: true,
    candidate: candidate,
    exactCandidate: exactCandidate,
  );

  factory CanonicalDisplaySegmentAdmissionResult.rejected(
    CanonicalDisplaySegmentValidationOutcome outcome,
    String diagnostics,
  ) {
    assert(
      outcome !=
          CanonicalDisplaySegmentValidationOutcome.exactCanonicalCompatible,
    );
    return CanonicalDisplaySegmentAdmissionResult._(
      outcome: outcome,
      diagnostics: diagnostics,
      strictAdmissionAttested: false,
    );
  }

  final CanonicalDisplaySegmentValidationOutcome outcome;
  final String diagnostics;
  final CanonicalDisplaySegmentRecord? candidate;
  final CanonicalDisplaySegmentExactCandidate? exactCandidate;
  final bool _strictAdmissionAttested;

  bool get isExact =>
      outcome ==
      CanonicalDisplaySegmentValidationOutcome.exactCanonicalCompatible;
  bool get hasStrictAdmissionAttestation => _strictAdmissionAttested;

  /// Exact candidates are immutable evidence only.  P06-003 must still prove
  /// contextual anchoring and route any future publication through P04.
  bool get hasJoinAuthority => false;
  bool get hasPublicationAuthority => false;
  bool get hasCacheWriteAuthority => false;
  bool get hasCheckpointOrSettlementAuthority => false;
  List<CanonicalFinalizedReaderCard> get cards => const [];
  CanonicalPaginationContinuation? get continuation => null;

  Uint8List get canonicalOutcomeBytes => Uint8List.fromList(
    utf8.encode(
      canonicalJsonEncode(<String, Object?>{
        'candidateDigest': candidate?.checksumDigest,
        'diagnostics': diagnostics,
        'outcome': outcome.name,
      }),
    ),
  );
}

/// Immutable input that has passed the shared logical admission and contextual
/// anchoring checks. It remains non-authoritative until publishCanonical
/// accepts its cards and continuation atomically.
@immutable
final class CanonicalDisplaySegmentExactCandidate {
  CanonicalDisplaySegmentExactCandidate({
    required this.record,
    required List<CanonicalFinalizedReaderCard> finalizedCards,
    required this.continuation,
  }) : finalizedCards = List<CanonicalFinalizedReaderCard>.unmodifiable(
         finalizedCards,
       );

  final CanonicalDisplaySegmentRecord record;
  final List<CanonicalFinalizedReaderCard> finalizedCards;
  final CanonicalPaginationContinuation continuation;

  bool get hasPublicationAuthority => false;
  bool get hasCacheWriteAuthority => false;
  bool get hasCheckpointOrSettlementAuthority => false;
}

/// Context consists only of currently accepted P04/P05 constituents.  It is
/// intentionally explicit so the validator cannot derive authority from a
/// legacy cache map, a filename, a display range, or resident object identity.
@immutable
final class CanonicalDisplaySegmentAdmissionContext {
  CanonicalDisplaySegmentAdmissionContext({
    required this.bookStorageScopeDigest,
    required this.publicationFingerprint,
    required this.sourceSnapshot,
    required this.currentCompatibilityEvidence,
    required this.supportedCompatibilityRevisions,
    required this.controlledLayoutIdentity,
    required this.paginationAlgorithmIdentity,
    required List<CanonicalFinalizedReaderCard> acceptedFinalizedCards,
    this.acceptedPredecessor,
    this.acceptedSuccessor,
    this.acceptedRestart,
    this.expectedGeneration,
  }) : acceptedFinalizedCards = List<CanonicalFinalizedReaderCard>.unmodifiable(
         acceptedFinalizedCards,
       ) {
    if (bookStorageScopeDigest.isEmpty ||
        publicationFingerprint.isEmpty ||
        controlledLayoutIdentity.isEmpty ||
        paginationAlgorithmIdentity.isEmpty) {
      throw ArgumentError(
        'Canonical admission context identity is incomplete.',
      );
    }
  }

  final String bookStorageScopeDigest;
  final String publicationFingerprint;
  final CanonicalPaginationSourceSnapshot sourceSnapshot;
  final ReaderCompatibilityEvidence currentCompatibilityEvidence;
  final ReaderCompatibilityRevisionSupport supportedCompatibilityRevisions;
  final String controlledLayoutIdentity;
  final String paginationAlgorithmIdentity;
  final List<CanonicalFinalizedReaderCard> acceptedFinalizedCards;
  final CanonicalFinalizedReaderCard? acceptedPredecessor;
  final CanonicalFinalizedReaderCard? acceptedSuccessor;
  final CanonicalPaginationContinuation? acceptedRestart;
  final String? expectedGeneration;
}

abstract final class CanonicalDisplaySegmentAdmission {
  static CanonicalDisplaySegmentAdmissionResult absent() =>
      CanonicalDisplaySegmentAdmissionResult.rejected(
        CanonicalDisplaySegmentValidationOutcome.safeMissAbsent,
        'No canonical segment candidate was supplied.',
      );

  /// Legacy cache payloads deliberately remain uninterpreted.  This lets all
  /// existing current cache paths continue their bounded canonical regeneration.
  static CanonicalDisplaySegmentAdmissionResult legacySafeMiss({
    required String cacheKind,
  }) => CanonicalDisplaySegmentAdmissionResult.rejected(
    CanonicalDisplaySegmentValidationOutcome.regenerationRequired,
    'Legacy $cacheKind cache evidence has no canonical segment contract.',
  );

  static CanonicalDisplaySegmentAdmissionResult admitDiskBytes({
    required Uint8List bytes,
    required CanonicalDisplaySegmentCodecLimits limits,
    required CanonicalDisplaySegmentAdmissionContext context,
    String? claimedGeneration,
  }) {
    try {
      final record = CanonicalDisplaySegmentCodec.decode(bytes, limits: limits);
      return admitRecord(
        record: record,
        limits: limits,
        context: context,
        claimedGeneration: claimedGeneration,
      );
    } on CanonicalDisplaySegmentFormatException catch (error) {
      return CanonicalDisplaySegmentAdmissionResult.rejected(
        CanonicalDisplaySegmentValidationOutcome
            .rejectedCorruptChecksumOrEncoding,
        error.message,
      );
    } on ArgumentError catch (error) {
      return CanonicalDisplaySegmentAdmissionResult.rejected(
        CanonicalDisplaySegmentValidationOutcome
            .rejectedCorruptChecksumOrEncoding,
        '$error',
      );
    }
  }

  /// Memory candidates are serialized and decoded first so residency cannot
  /// bypass the exact disk validation sequence or outcome evidence.
  static CanonicalDisplaySegmentAdmissionResult admitMemoryRecord({
    required CanonicalDisplaySegmentRecord record,
    required CanonicalDisplaySegmentCodecLimits limits,
    required CanonicalDisplaySegmentAdmissionContext context,
    String? claimedGeneration,
  }) {
    try {
      return admitDiskBytes(
        bytes: CanonicalDisplaySegmentCodec.encode(record),
        limits: limits,
        context: context,
        claimedGeneration: claimedGeneration,
      );
    } on CanonicalDisplaySegmentFormatException catch (error) {
      return CanonicalDisplaySegmentAdmissionResult.rejected(
        CanonicalDisplaySegmentValidationOutcome
            .rejectedCorruptChecksumOrEncoding,
        error.message,
      );
    }
  }

  static CanonicalDisplaySegmentAdmissionResult admitRecord({
    required CanonicalDisplaySegmentRecord record,
    required CanonicalDisplaySegmentCodecLimits limits,
    required CanonicalDisplaySegmentAdmissionContext context,
    String? claimedGeneration,
  }) {
    if (context.expectedGeneration != null &&
        claimedGeneration != context.expectedGeneration) {
      return _rejected(
        CanonicalDisplaySegmentValidationOutcome.rejectedStaleGeneration,
        'Candidate generation is stale or absent.',
      );
    }
    if (record.bookStorageScopeDigest != context.bookStorageScopeDigest ||
        record.publicationFingerprint != context.publicationFingerprint ||
        record.sourceSnapshotLink.publicationFingerprint !=
            context.publicationFingerprint) {
      return _rejected(
        CanonicalDisplaySegmentValidationOutcome.rejectedCrossBookScope,
        'Book storage scope or publication fingerprint does not match.',
      );
    }

    final compatibility = _classifyCompatibility(record, context);
    if (compatibility != null) return compatibility;
    if (!_sameSnapshot(record.sourceSnapshotLink, context.sourceSnapshot)) {
      return _rejected(
        CanonicalDisplaySegmentValidationOutcome
            .safeMissIncompatibleSourceOrParser,
        'Pinned source snapshot linkage does not match.',
      );
    }
    if (!_intervalOwnersResolve(record, context.sourceSnapshot)) {
      return _rejected(
        CanonicalDisplaySegmentValidationOutcome
            .rejectedCardIdentityOrContentMismatch,
        'Segment source owners do not resolve exactly in the pinned snapshot.',
      );
    }
    final validatedCards = _validatedCards(record, context);
    if (validatedCards == null) {
      return _rejected(
        CanonicalDisplaySegmentValidationOutcome
            .rejectedCardIdentityOrContentMismatch,
        'Finalized card, source-slice, layout, or payload evidence disagrees.',
      );
    }
    final continuation = _decodeContinuation(record, context, limits);
    if (continuation == null) {
      return _rejected(
        CanonicalDisplaySegmentValidationOutcome.rejectedContinuationMismatch,
        'Continuation is malformed, incompatible, or has an invalid frontier seam.',
      );
    }
    if (!_validateBoundaries(record, context, continuation, limits)) {
      return _rejected(
        CanonicalDisplaySegmentValidationOutcome.rejectedBoundaryMismatch,
        'Canonical predecessor/successor/book boundary proof does not join.',
      );
    }
    return CanonicalDisplaySegmentAdmissionResult._admittedExact(
      candidate: record,
      exactCandidate: CanonicalDisplaySegmentExactCandidate(
        record: record,
        finalizedCards: validatedCards,
        continuation: continuation,
      ),
      diagnostics:
          'All canonical key, compatibility, source, card, seam, and continuation evidence match.',
    );
  }

  /// P06-003 may call this only after separately admitting both candidates.
  /// Numerically adjacent source ranges have no joining authority by themselves.
  static CanonicalDisplaySegmentAdmissionResult join(
    CanonicalDisplaySegmentAdmissionResult left,
    CanonicalDisplaySegmentAdmissionResult right,
  ) {
    final first = left.candidate;
    final second = right.candidate;
    if (!left.isExact || !right.isExact || first == null || second == null) {
      return _rejected(
        CanonicalDisplaySegmentValidationOutcome.rejectedBoundaryMismatch,
        'Only independently exact candidates may be considered for a join.',
      );
    }
    final leftProof = first.rightBoundaryProof;
    final rightProof = second.leftBoundaryProof;
    if (leftProof.kind != CanonicalDisplaySegmentRightBoundaryKind.successor ||
        rightProof.kind !=
            CanonicalDisplaySegmentLeftBoundaryKind.predecessor ||
        leftProof.successorCardSignature !=
            second.orderedFinalizedCards.first.physicalCardSignature ||
        rightProof.predecessorCardSignature !=
            first.orderedFinalizedCards.last.physicalCardSignature ||
        !_sameCursor(
          leftProof.finalCardEndCursor,
          rightProof.firstCardStartCursor,
        ) ||
        !_sameCursor(
          leftProof.successorStartCursor,
          rightProof.firstCardStartCursor,
        ) ||
        !_sameCursor(
          rightProof.predecessorEndCursor,
          leftProof.finalCardEndCursor,
        ) ||
        leftProof.continuationDigest !=
            rightProof.predecessorContinuationDigest ||
        first.keyDigest == second.keyDigest ||
        first.publicationFingerprint != second.publicationFingerprint ||
        first.sourceCompatibilityFingerprint !=
            second.sourceCompatibilityFingerprint ||
        first.layoutMetricsFingerprint != second.layoutMetricsFingerprint ||
        first.rendererLayoutFingerprint != second.rendererLayoutFingerprint ||
        first.paginationAlgorithmFingerprint !=
            second.paginationAlgorithmFingerprint ||
        first.compatibilityClassifierRevision !=
            second.compatibilityClassifierRevision ||
        first.readerCompatibilityFingerprint !=
            second.readerCompatibilityFingerprint) {
      return _rejected(
        CanonicalDisplaySegmentValidationOutcome.rejectedBoundaryMismatch,
        'Adjacent ranges lack exact mutual cursor/card/continuation seam proof.',
      );
    }
    return _rejected(
      CanonicalDisplaySegmentValidationOutcome.regenerationRequired,
      'Join evidence is exact but P06-003 owns controlled reuse/publication.',
    );
  }

  static CanonicalDisplaySegmentAdmissionResult? _classifyCompatibility(
    CanonicalDisplaySegmentRecord record,
    CanonicalDisplaySegmentAdmissionContext context,
  ) {
    ReaderCompatibilityClassificationResult classification;
    try {
      classification = ReaderCompatibilityClassifier.classify(
        previous: record.compatibilityEvidence.toReaderEvidence(),
        current: context.currentCompatibilityEvidence,
        supportedRevisions: context.supportedCompatibilityRevisions,
      );
    } on Object catch (_) {
      return _rejected(
        CanonicalDisplaySegmentValidationOutcome
            .rejectedCompatibilityEvidenceCorrupt,
        'Stored compatibility evidence cannot be reconstructed faithfully.',
      );
    }
    return switch (classification.kind) {
      ReaderCompatibilityClassificationKind.exactCompatible => null,
      ReaderCompatibilityClassificationKind.sourceCompatibilityChanged ||
      ReaderCompatibilityClassificationKind
          .multipleAuthoritativeChanges => _rejected(
        CanonicalDisplaySegmentValidationOutcome
            .safeMissIncompatibleSourceOrParser,
        'Compatibility classifier rejected authoritative source/parser change: ${classification.changedDimensions.map((value) => value.name).join(',')}.',
      ),
      ReaderCompatibilityClassificationKind.layoutMetricsChanged => _rejected(
        CanonicalDisplaySegmentValidationOutcome.safeMissChangedLayout,
        'Compatibility classifier rejected layout metrics.',
      ),
      ReaderCompatibilityClassificationKind.rendererLayoutChanged => _rejected(
        CanonicalDisplaySegmentValidationOutcome.safeMissChangedRendererRules,
        'Compatibility classifier rejected renderer layout rules.',
      ),
      ReaderCompatibilityClassificationKind.paginationAlgorithmChanged =>
        _rejected(
          CanonicalDisplaySegmentValidationOutcome
              .safeMissChangedPaginationAlgorithm,
          'Compatibility classifier rejected pagination algorithm.',
        ),
      ReaderCompatibilityClassificationKind.unsupportedRevision => _rejected(
        CanonicalDisplaySegmentValidationOutcome.safeMissUnsupportedRevision,
        'Compatibility classifier rejected an unsupported revision.',
      ),
      ReaderCompatibilityClassificationKind.incompleteEvidence => _rejected(
        CanonicalDisplaySegmentValidationOutcome
            .safeMissIncompleteCanonicalEvidence,
        'Compatibility classifier received incomplete evidence.',
      ),
      ReaderCompatibilityClassificationKind.corruptEvidence => _rejected(
        CanonicalDisplaySegmentValidationOutcome
            .rejectedCompatibilityEvidenceCorrupt,
        'Compatibility classifier detected corrupt evidence.',
      ),
    };
  }

  static List<CanonicalFinalizedReaderCard>? _validatedCards(
    CanonicalDisplaySegmentRecord record,
    CanonicalDisplaySegmentAdmissionContext context,
  ) {
    if (record.orderedFinalizedCards.length != record.declaredCardCount ||
        context.acceptedFinalizedCards.isEmpty) {
      return null;
    }
    final expectedBySignature = <String, CanonicalFinalizedReaderCard>{
      for (final card in context.acceptedFinalizedCards)
        card.identity.signature: card,
    };
    final seen = <String>{};
    CanonicalDisplaySegmentCardRecord? prior;
    var sliceCount = 0;
    var blockCount = 0;
    for (final card in record.orderedFinalizedCards) {
      final expected = expectedBySignature[card.physicalCardSignature];
      if (expected == null || !seen.add(card.physicalCardSignature)) {
        return null;
      }
      final rebuilt = CanonicalDisplaySegmentCardRecord.fromFinalized(
        expected,
        sourceSnapshot: context.sourceSnapshot,
      );
      if (!_sameCard(card, rebuilt) ||
          !_allSlicesResolve(
            card.orderedStableSourceSlices,
            context.sourceSnapshot,
          )) {
        return null;
      }
      if (prior != null &&
          !_sameCursor(prior.cardEndCursor, card.cardStartCursor)) {
        return null;
      }
      prior = card;
      sliceCount += card.declaredSourceSliceCount;
      blockCount += card.declaredBlockLayoutCount;
    }
    final first = record.orderedFinalizedCards.first;
    final last = record.orderedFinalizedCards.last;
    final valid =
        sliceCount == record.declaredSourceSliceCount &&
        blockCount == record.declaredBlockLayoutCount &&
        _sameCursor(record.stableStartCursor, first.cardStartCursor) &&
        _sameCursor(record.stableEndCursor, last.cardEndCursor) &&
        _sameCursor(
          record.exactHalfOpenSourceInterval.startCursor,
          first.cardStartCursor,
        ) &&
        _sameCursor(
          record.exactHalfOpenSourceInterval.endCursor,
          last.cardEndCursor,
        );
    if (!valid) return null;
    return List<CanonicalFinalizedReaderCard>.unmodifiable(
      <CanonicalFinalizedReaderCard>[
        for (final card in record.orderedFinalizedCards)
          expectedBySignature[card.physicalCardSignature]!,
      ],
    );
  }

  static CanonicalPaginationContinuation? _decodeContinuation(
    CanonicalDisplaySegmentRecord record,
    CanonicalDisplaySegmentAdmissionContext context,
    CanonicalDisplaySegmentCodecLimits limits,
  ) {
    final decoded = CanonicalPaginationContinuationCodec.decode(
      record.continuationEvidence.canonicalEncoding,
    );
    if (decoded is! CanonicalPaginationContinuationAccepted) return null;
    final continuation = decoded.continuation;
    if (continuation.integrityDigest !=
            record.continuationEvidence.continuationDigest ||
        continuation.chainOrdinal < 0 ||
        continuation.chainOrdinal > limits.maxContinuationChainOrdinal ||
        continuation.key.bookId != context.sourceSnapshot.bookId ||
        continuation.key.publicationFingerprint !=
            context.publicationFingerprint ||
        continuation.key.parserSourceIdentity !=
            context.sourceSnapshot.parserSourceIdentity ||
        continuation.key.sourceRevision !=
            context.sourceSnapshot.sourceRevision ||
        continuation.key.sourceSnapshotDigest !=
            context.sourceSnapshot.snapshotDigest ||
        continuation.key.paginationAlgorithmIdentity !=
            context.paginationAlgorithmIdentity ||
        continuation.key.controlledLayoutIdentity !=
            context.controlledLayoutIdentity ||
        !_cursorResolves(
          context.sourceSnapshot,
          continuation.startSourceCursor,
        ) ||
        !_cursorResolves(
          context.sourceSnapshot,
          continuation.nextSourceCursor,
        ) ||
        !_cursorResolves(
          context.sourceSnapshot,
          continuation.previousFinalizedBoundary.endCursor,
        )) {
      return null;
    }
    final frontierStart = _frontierStart(continuation.frontier);
    final frontierEnd = _frontierEnd(
      continuation.frontier,
      context.sourceSnapshot,
    );
    if (frontierStart != null) {
      if (!_sameCursor(
            continuation.previousFinalizedBoundary.endCursor,
            frontierStart,
          ) ||
          frontierEnd == null ||
          !_sameCursor(frontierEnd, continuation.nextSourceCursor)) {
        return null;
      }
    } else if (!_sameCursor(
      continuation.previousFinalizedBoundary.endCursor,
      continuation.nextSourceCursor,
    )) {
      return null;
    }
    return continuation;
  }

  static bool _validateBoundaries(
    CanonicalDisplaySegmentRecord record,
    CanonicalDisplaySegmentAdmissionContext context,
    CanonicalPaginationContinuation continuation,
    CanonicalDisplaySegmentCodecLimits limits,
  ) {
    final key = CanonicalDisplaySegmentKey.decode(
      record.canonicalKeyBytes,
      limits: limits,
    );
    final first = record.orderedFinalizedCards.first;
    final last = record.orderedFinalizedCards.last;
    final left = record.leftBoundaryProof;
    final right = record.rightBoundaryProof;
    if (!_sameCursor(left.firstCardStartCursor, first.cardStartCursor) ||
        right.finalCardSignature != last.physicalCardSignature ||
        !_sameCursor(right.finalCardEndCursor, last.cardEndCursor)) {
      return false;
    }
    final leftValid = switch (left.kind) {
      CanonicalDisplaySegmentLeftBoundaryKind.bookStart =>
        left.predecessorCardSignature == null &&
            left.predecessorEndCursor == null &&
            first.cardStartCursor.sourceOrdinalHint == 0,
      CanonicalDisplaySegmentLeftBoundaryKind.predecessor =>
        context.acceptedPredecessor != null &&
            left.predecessorCardSignature ==
                context.acceptedPredecessor!.identity.signature &&
            left.predecessorEndCursor != null &&
            _sameCursor(left.predecessorEndCursor, first.cardStartCursor) &&
            (left.predecessorContinuationDigest == null ||
                left.predecessorContinuationDigest ==
                    continuation.parentDigest),
      CanonicalDisplaySegmentLeftBoundaryKind.restart =>
        left.restartContinuationEncoding != null &&
            left.restartContinuationDigest != null &&
            context.acceptedRestart != null &&
            left.restartContinuationEncoding ==
                context.acceptedRestart!.canonicalEncoding &&
            left.restartContinuationDigest ==
                context.acceptedRestart!.integrityDigest &&
            _sameCursor(
              context.acceptedRestart!.previousFinalizedBoundary.endCursor,
              first.cardStartCursor,
            ),
    };
    if (!leftValid) return false;
    final rightValid = switch (right.kind) {
      CanonicalDisplaySegmentRightBoundaryKind.logicalEnd =>
        right.successorCardSignature == null &&
            right.successorStartCursor == null &&
            continuation.terminal &&
            last.cardEndCursor.isLogicalEnd,
      CanonicalDisplaySegmentRightBoundaryKind.successor =>
        !continuation.terminal &&
            context.acceptedSuccessor != null &&
            right.successorCardSignature ==
                context.acceptedSuccessor!.identity.signature &&
            right.successorStartCursor != null &&
            _sameCursor(right.successorStartCursor, last.cardEndCursor) &&
            right.continuationDigest == continuation.integrityDigest,
      CanonicalDisplaySegmentRightBoundaryKind.frontier =>
        !continuation.terminal &&
            right.continuationDigest == continuation.integrityDigest &&
            _sameCursor(
              continuation.previousFinalizedBoundary.endCursor,
              last.cardEndCursor,
            ) &&
            _sameNullableCursor(
              right.frontierStartCursor,
              _frontierStart(continuation.frontier),
            ) &&
            _sameNullableCursor(
              right.frontierEndCursor,
              _frontierEnd(continuation.frontier, context.sourceSnapshot),
            ),
    };
    if (!rightValid) return false;
    return switch (key.boundaryRole) {
      CanonicalDisplaySegmentBoundaryRole.bookStartAnchored =>
        left.kind == CanonicalDisplaySegmentLeftBoundaryKind.bookStart,
      CanonicalDisplaySegmentBoundaryRole.continuationAnchored =>
        left.kind != CanonicalDisplaySegmentLeftBoundaryKind.bookStart,
      CanonicalDisplaySegmentBoundaryRole.interior =>
        left.kind != CanonicalDisplaySegmentLeftBoundaryKind.bookStart &&
            right.kind != CanonicalDisplaySegmentRightBoundaryKind.logicalEnd,
      CanonicalDisplaySegmentBoundaryRole.logicalEndAnchored =>
        right.kind == CanonicalDisplaySegmentRightBoundaryKind.logicalEnd,
    };
  }

  static bool _sameSnapshot(
    CanonicalDisplaySegmentSourceSnapshotLink link,
    CanonicalPaginationSourceSnapshot snapshot,
  ) =>
      link.snapshotDigest == snapshot.snapshotDigest &&
      link.sourceRevision == snapshot.sourceRevision &&
      link.parserSourceIdentity == snapshot.parserSourceIdentity &&
      link.publicationFingerprint == snapshot.publicationFingerprint &&
      link.sourceCount == snapshot.sourceCount;

  static bool _intervalOwnersResolve(
    CanonicalDisplaySegmentRecord record,
    CanonicalPaginationSourceSnapshot snapshot,
  ) {
    final interval = record.exactHalfOpenSourceInterval;
    final start = interval.startCursor.sourceOrdinalHint;
    final end = interval.endCursor.isLogicalEnd
        ? snapshot.sourceCount
        : interval.endCursor.sourceOrdinalHint +
              (interval.endCursor.kind ==
                      CanonicalPaginationCursorKind.wholeSource
                  ? 0
                  : 1);
    if (start < 0 ||
        start >= end ||
        end > snapshot.sourceCount ||
        interval.orderedOwners.length != end - start) {
      return false;
    }
    for (var ordinal = start; ordinal < end; ordinal += 1) {
      final claimed = interval.orderedOwners[ordinal - start];
      final actual = snapshot.ownerAt(ordinal);
      if (claimed.sourceIdentity != actual.sourceIdentity ||
          claimed.sectionIdentity != actual.sectionIdentity ||
          claimed.spineIdentity != actual.spineIdentity ||
          claimed.sourceOrdinalHint != actual.sourceOrdinalHint ||
          claimed.sourceDigest != actual.sourceDigest) {
        return false;
      }
    }
    return true;
  }

  static bool _allSlicesResolve(
    List<CanonicalPaginationSourceSlice> slices,
    CanonicalPaginationSourceSnapshot snapshot,
  ) {
    CanonicalPaginationCursor? priorEnd;
    for (final slice in slices) {
      final ordinal = snapshot.resolveOrdinal(
        sourceIdentity: slice.sourceIdentity,
        ordinalHint: slice.sourceOrdinalHint,
      );
      if (ordinal == null ||
          snapshot.ownerAt(ordinal).sourceDigest != slice.sourceDigest) {
        return false;
      }
      final start = _sliceStart(slice);
      if (priorEnd != null &&
          priorEnd.sourceOrdinalHint == start.sourceOrdinalHint &&
          !_sameCursor(priorEnd, start)) {
        return false;
      }
      priorEnd = _sliceEnd(slice, snapshot);
    }
    return true;
  }

  static bool _sameCard(
    CanonicalDisplaySegmentCardRecord first,
    CanonicalDisplaySegmentCardRecord second,
  ) =>
      first.physicalCardSignature == second.physicalCardSignature &&
      first.physicalLayoutCompositeFingerprint ==
          second.physicalLayoutCompositeFingerprint &&
      first.physicalCardIdentityComponents ==
          second.physicalCardIdentityComponents &&
      _sameCursor(first.cardStartCursor, second.cardStartCursor) &&
      _sameCursor(first.cardEndCursor, second.cardEndCursor) &&
      first.declaredSourceSliceCount == second.declaredSourceSliceCount &&
      first.declaredBlockLayoutCount == second.declaredBlockLayoutCount &&
      _sameStringLists(
        first.orderedBlockLayoutFingerprints,
        second.orderedBlockLayoutFingerprints,
      ) &&
      _sameStringLists(
        first.orderedStableSourceSlices
            .map((slice) => canonicalJsonEncode(slice.toCanonicalJson()))
            .toList(),
        second.orderedStableSourceSlices
            .map((slice) => canonicalJsonEncode(slice.toCanonicalJson()))
            .toList(),
      ) &&
      first.structuralCardPayloadDigest == second.structuralCardPayloadDigest &&
      _sameBytes(first.structuralCardPayload, second.structuralCardPayload);

  static bool _cursorResolves(
    CanonicalPaginationSourceSnapshot snapshot,
    CanonicalPaginationCursor cursor,
  ) =>
      cursor.isLogicalEnd ||
      snapshot.resolveOrdinal(
            sourceIdentity: cursor.sourceIdentity,
            ordinalHint: cursor.sourceOrdinalHint,
          ) !=
          null;

  static CanonicalPaginationCursor? _frontierStart(
    CanonicalPaginationFrontier frontier,
  ) {
    final slices = <CanonicalPaginationSourceSlice>[
      ...?frontier.deferredPredecessor?.sourceSlices,
      ...?frontier.pendingTail?.sourceSlices,
    ];
    return slices.isEmpty ? null : _sliceStart(slices.first);
  }

  static CanonicalPaginationCursor? _frontierEnd(
    CanonicalPaginationFrontier frontier,
    CanonicalPaginationSourceSnapshot snapshot,
  ) {
    final slices = <CanonicalPaginationSourceSlice>[
      ...?frontier.deferredPredecessor?.sourceSlices,
      ...?frontier.pendingTail?.sourceSlices,
    ];
    return slices.isEmpty ? null : _sliceEnd(slices.last, snapshot);
  }

  static CanonicalPaginationCursor _sliceStart(
    CanonicalPaginationSourceSlice slice,
  ) => CanonicalPaginationCursor(
    kind: slice.startUtf16 != null
        ? slice.startUtf16 == 0
              ? CanonicalPaginationCursorKind.wholeSource
              : CanonicalPaginationCursorKind.sourceText
        : slice.tableRowStart != null
        ? slice.tableRowStart == 0
              ? CanonicalPaginationCursorKind.wholeSource
              : CanonicalPaginationCursorKind.tableRow
        : CanonicalPaginationCursorKind.wholeSource,
    sourceIdentity: slice.sourceIdentity,
    sectionIdentity: slice.sectionIdentity,
    sourceOrdinalHint: slice.sourceOrdinalHint,
    textOffsetUtf16: slice.startUtf16 ?? 0,
    tableRowIndex: slice.tableRowStart ?? 0,
  );

  static CanonicalPaginationCursor _sliceEnd(
    CanonicalPaginationSourceSlice slice,
    CanonicalPaginationSourceSnapshot snapshot,
  ) {
    if (slice.endUtf16 != null) {
      final source = snapshot.resolveOrdinalSource(slice.sourceOrdinalHint);
      if (slice.endUtf16! < (source.text?.length ?? 0)) {
        return CanonicalPaginationCursor(
          kind: CanonicalPaginationCursorKind.sourceText,
          sourceIdentity: slice.sourceIdentity,
          sectionIdentity: slice.sectionIdentity,
          sourceOrdinalHint: slice.sourceOrdinalHint,
          textOffsetUtf16: slice.endUtf16!,
        );
      }
    }
    if (slice.sourceOrdinalHint + 1 >= snapshot.sourceCount) {
      return const CanonicalPaginationCursor.logicalEnd();
    }
    final next = snapshot.ownerAt(slice.sourceOrdinalHint + 1);
    return CanonicalPaginationCursor(
      kind: CanonicalPaginationCursorKind.wholeSource,
      sourceIdentity: next.sourceIdentity,
      sectionIdentity: next.sectionIdentity,
      sourceOrdinalHint: next.sourceOrdinalHint,
    );
  }

  static bool _sameCursor(
    CanonicalPaginationCursor? first,
    CanonicalPaginationCursor? second,
  ) => first != null && second != null && first.samePositionAs(second);

  static bool _sameNullableCursor(
    CanonicalPaginationCursor? first,
    CanonicalPaginationCursor? second,
  ) => first == null ? second == null : _sameCursor(first, second);

  static bool _sameStringLists(List<String> first, List<String> second) =>
      listEquals(first, second);

  static bool _sameBytes(List<int> first, List<int> second) =>
      listEquals(first, second);

  static CanonicalDisplaySegmentAdmissionResult _rejected(
    CanonicalDisplaySegmentValidationOutcome outcome,
    String diagnostics,
  ) => CanonicalDisplaySegmentAdmissionResult.rejected(outcome, diagnostics);
}
