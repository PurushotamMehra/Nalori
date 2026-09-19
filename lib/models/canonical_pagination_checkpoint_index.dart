import 'package:flutter/foundation.dart';

import 'canonical_pagination.dart';

/// Bounded process-local checkpoint collection for one active loaded
/// publication window. It never writes display caches or durable checkpoints.
final class CanonicalPaginationCheckpointIndex {
  CanonicalPaginationCheckpointIndex({
    required this.bookId,
    required this.publicationFingerprint,
    required this.parserSourceIdentity,
    required this.sourceRevision,
    required this.sourceSnapshotDigest,
    required this.paginationAlgorithmIdentity,
    required this.controlledLayoutIdentity,
    int maximumRecords =
        CanonicalPaginationBounds.residentContinuationRecordBasis,
  }) : maximumRecords = _validateMaximumRecords(maximumRecords);

  final String bookId;
  final String publicationFingerprint;
  final String parserSourceIdentity;
  final String sourceRevision;
  final String sourceSnapshotDigest;
  final String paginationAlgorithmIdentity;
  final String controlledLayoutIdentity;
  final int maximumRecords;

  final List<_IndexedContinuation> _entries = <_IndexedContinuation>[];
  String? _activeDigest;

  static int _validateMaximumRecords(int value) {
    if (value <= 0 ||
        value > CanonicalPaginationBounds.residentContinuationRecordBasis) {
      throw RangeError.range(
        value,
        1,
        CanonicalPaginationBounds.residentContinuationRecordBasis,
        'maximumRecords',
      );
    }
    return value;
  }

  List<CanonicalPaginationContinuation> get records =>
      List<CanonicalPaginationContinuation>.unmodifiable(
        _entries.map((entry) => entry.continuation),
      );

  CanonicalPaginationContinuation? get activeFrontier {
    final digest = _activeDigest;
    if (digest == null) return null;
    for (final entry in _entries) {
      if (entry.continuation.integrityDigest == digest) {
        return entry.continuation;
      }
    }
    return null;
  }

  CanonicalPaginationCheckpointIndex copy() {
    final copied = CanonicalPaginationCheckpointIndex(
      bookId: bookId,
      publicationFingerprint: publicationFingerprint,
      parserSourceIdentity: parserSourceIdentity,
      sourceRevision: sourceRevision,
      sourceSnapshotDigest: sourceSnapshotDigest,
      paginationAlgorithmIdentity: paginationAlgorithmIdentity,
      controlledLayoutIdentity: controlledLayoutIdentity,
      maximumRecords: maximumRecords,
    );
    copied._entries.addAll(
      _entries.map(
        (entry) => _IndexedContinuation(
          continuation: entry.continuation,
          sectionBoundary: entry.sectionBoundary,
          activeFrontier: entry.activeFrontier,
        ),
      ),
    );
    copied._activeDigest = _activeDigest;
    return copied;
  }

  /// Returns at most [limit] compatible restart candidates, nearest first.
  ///
  /// The target's ordinal is only a validated hint: its stable source and
  /// section owners must match the index snapshot before any candidate is
  /// returned by the caller's pinned-snapshot validation.
  List<CanonicalPaginationContinuation> predecessorsAtOrBefore(
    CanonicalPaginationTargetCursor target, {
    int limit = 2,
  }) {
    if (limit <= 0 || limit > 2) {
      throw RangeError.range(limit, 1, 2, 'limit');
    }
    final targetCursor = CanonicalPaginationCursor(
      kind: CanonicalPaginationCursorKind.sourceText,
      sourceIdentity: target.sourceIdentity,
      sectionIdentity: target.sectionIdentity,
      sourceOrdinalHint: target.sourceOrdinalHint,
      textOffsetUtf16: target.textOffsetUtf16,
    );
    final candidates = <CanonicalPaginationContinuation>[];
    for (final entry in _entries.reversed) {
      final continuation = entry.continuation;
      if (_compareCursor(continuation.nextSourceCursor, targetCursor) <= 0) {
        candidates.add(continuation);
        if (candidates.length == limit) break;
      }
    }
    return List<CanonicalPaginationContinuation>.unmodifiable(candidates);
  }

  /// Returns at most [limit] compatible restart candidates strictly before
  /// [target], nearest first.
  ///
  /// Backward preparation must replay the desired predecessor itself, so a
  /// continuation positioned exactly at that cursor is not restart authority.
  List<CanonicalPaginationContinuation> predecessorsBefore(
    CanonicalPaginationTargetCursor target, {
    int limit = 2,
  }) {
    if (limit <= 0 || limit > 2) {
      throw RangeError.range(limit, 1, 2, 'limit');
    }
    final targetCursor = CanonicalPaginationCursor(
      kind: CanonicalPaginationCursorKind.sourceText,
      sourceIdentity: target.sourceIdentity,
      sectionIdentity: target.sectionIdentity,
      sourceOrdinalHint: target.sourceOrdinalHint,
      textOffsetUtf16: target.textOffsetUtf16,
    );
    final candidates = <CanonicalPaginationContinuation>[];
    for (final entry in _entries.reversed) {
      final continuation = entry.continuation;
      if (_compareCursor(continuation.nextSourceCursor, targetCursor) < 0) {
        candidates.add(continuation);
        if (candidates.length == limit) break;
      }
    }
    return List<CanonicalPaginationContinuation>.unmodifiable(candidates);
  }

  CanonicalPaginationContinuation? parentOf(
    CanonicalPaginationContinuation continuation,
  ) {
    final parentDigest = continuation.parentDigest;
    if (parentDigest == null) return null;
    for (final entry in _entries) {
      if (entry.continuation.integrityDigest == parentDigest) {
        return entry.continuation;
      }
    }
    return null;
  }

  /// Creates a private active branch rooted at an already resident validated
  /// continuation. This is used by target-first work so a successful jump can
  /// replace the prior forward frontier without replaying a stale fork into
  /// this index. The original index is unchanged.
  CanonicalPaginationCheckpointBranch forkAt(
    CanonicalPaginationContinuation continuation,
  ) {
    final resident = _entries.any(
      (entry) =>
          entry.continuation.integrityDigest == continuation.integrityDigest,
    );
    if (!resident) {
      return CanonicalPaginationCheckpointBranch.rejected(
        _rejected(
          CanonicalPaginationContinuationValidationKind.requiredEarlierRestart,
          'Selected checkpoint is no longer resident.',
        ),
      );
    }
    final decoded = CanonicalPaginationContinuationCodec.decode(
      continuation.canonicalEncoding,
    );
    if (decoded is CanonicalPaginationContinuationRejected) {
      return CanonicalPaginationCheckpointBranch.rejected(decoded);
    }
    final parent = parentOf(continuation);
    if (continuation.chainOrdinal > 0 && parent == null) {
      return CanonicalPaginationCheckpointBranch.rejected(
        _rejected(
          CanonicalPaginationContinuationValidationKind.requiredEarlierRestart,
          'Selected checkpoint parent is unavailable.',
        ),
      );
    }
    final branch = CanonicalPaginationCheckpointIndex(
      bookId: bookId,
      publicationFingerprint: publicationFingerprint,
      parserSourceIdentity: parserSourceIdentity,
      sourceRevision: sourceRevision,
      sourceSnapshotDigest: sourceSnapshotDigest,
      paginationAlgorithmIdentity: paginationAlgorithmIdentity,
      controlledLayoutIdentity: controlledLayoutIdentity,
      maximumRecords: maximumRecords,
    );
    if (parent != null) {
      branch._entries.add(
        _IndexedContinuation(
          continuation: parent,
          sectionBoundary:
              parent.checkpointReason ==
              CanonicalPaginationCheckpointReason.sectionBoundary,
          activeFrontier: false,
        ),
      );
    }
    branch._entries.add(
      _IndexedContinuation(
        continuation: continuation,
        sectionBoundary:
            continuation.checkpointReason ==
            CanonicalPaginationCheckpointReason.sectionBoundary,
        activeFrontier: true,
      ),
    );
    branch._entries.sort(branch._compareEntries);
    branch._activeDigest = continuation.integrityDigest;
    return CanonicalPaginationCheckpointBranch.accepted(branch, parent: parent);
  }

  CanonicalPaginationContinuationValidationResult insert(
    CanonicalPaginationAcceptedResult acceptedResult,
  ) {
    final continuation = acceptedResult.continuation;
    final decoded = CanonicalPaginationContinuationCodec.decode(
      continuation.canonicalEncoding,
    );
    if (decoded is CanonicalPaginationContinuationRejected) return decoded;
    final key = continuation.key;
    if (key.bookId != bookId ||
        key.publicationFingerprint != publicationFingerprint) {
      return _rejected(
        CanonicalPaginationContinuationValidationKind.incompatiblePublication,
        'Checkpoint belongs to another publication.',
      );
    }
    if (key.parserSourceIdentity != parserSourceIdentity ||
        key.sourceRevision != sourceRevision ||
        key.sourceSnapshotDigest != sourceSnapshotDigest) {
      return _rejected(
        CanonicalPaginationContinuationValidationKind
            .incompatibleParserSourceSnapshot,
        'Checkpoint belongs to another parser/source snapshot.',
      );
    }
    if (key.paginationAlgorithmIdentity != paginationAlgorithmIdentity) {
      return _rejected(
        CanonicalPaginationContinuationValidationKind
            .incompatiblePaginationIdentity,
        'Checkpoint pagination identity is incompatible.',
      );
    }
    if (key.controlledLayoutIdentity != controlledLayoutIdentity) {
      return _rejected(
        CanonicalPaginationContinuationValidationKind.incompatibleLayout,
        'Checkpoint layout identity is incompatible.',
      );
    }

    for (final entry in _entries) {
      if (entry.continuation.integrityDigest == continuation.integrityDigest) {
        if (continuation.integrityDigest == _activeDigest) {
          return CanonicalPaginationContinuationAccepted(entry.continuation);
        }
        return _rejected(
          CanonicalPaginationContinuationValidationKind.staleForkReplay,
          'An older checkpoint cannot be replayed as the active frontier.',
        );
      }
    }

    final active = activeFrontier;
    if (active == null) {
      if (continuation.chainOrdinal != 0 || continuation.parentDigest != null) {
        return _rejected(
          CanonicalPaginationContinuationValidationKind.brokenParentChain,
          'The first checkpoint must be a chain root.',
        );
      }
    } else {
      if (_compareCursor(
            continuation.nextSourceCursor,
            active.nextSourceCursor,
          ) <
          0) {
        return _rejected(
          CanonicalPaginationContinuationValidationKind
              .invalidCursorOffsetRowInterval,
          'Checkpoint cursor regresses behind the active frontier.',
        );
      }
      if (continuation.parentDigest != active.integrityDigest) {
        return _rejected(
          CanonicalPaginationContinuationValidationKind.staleForkReplay,
          'Checkpoint is a replay, stale fork, or child of another chain.',
        );
      }
      if (continuation.chainOrdinal != active.chainOrdinal + 1) {
        return _rejected(
          CanonicalPaginationContinuationValidationKind.ordinalMismatch,
          'Checkpoint ordinal is not the next active-chain ordinal.',
        );
      }
      if (!continuation.startSourceCursor.samePositionAs(
        active.nextSourceCursor,
      )) {
        return _rejected(
          CanonicalPaginationContinuationValidationKind.brokenParentChain,
          'Checkpoint does not start at the active frontier cursor.',
        );
      }
    }

    final candidateEntries = <_IndexedContinuation>[
      for (final entry in _entries)
        _IndexedContinuation(
          continuation: entry.continuation,
          sectionBoundary: entry.sectionBoundary,
          activeFrontier: false,
        ),
      _IndexedContinuation(
        continuation: continuation,
        sectionBoundary:
            continuation.checkpointReason ==
            CanonicalPaginationCheckpointReason.sectionBoundary,
        activeFrontier: true,
      ),
    ]..sort(_compareEntries);

    while (candidateEntries.length > maximumRecords) {
      final removable = _removableIndex(candidateEntries);
      if (removable == null) {
        return _rejected(
          CanonicalPaginationContinuationValidationKind.boundViolation,
          'The 25-record bound cannot preserve all required seam guards.',
        );
      }
      candidateEntries.removeAt(removable);
    }

    _entries
      ..clear()
      ..addAll(candidateEntries);
    _activeDigest = continuation.integrityDigest;
    return CanonicalPaginationContinuationAccepted(continuation);
  }

  CanonicalPaginationContinuationValidationResult requireDigest(String digest) {
    for (final entry in _entries) {
      if (entry.continuation.integrityDigest == digest) {
        return CanonicalPaginationContinuationAccepted(entry.continuation);
      }
    }
    return _rejected(
      CanonicalPaginationContinuationValidationKind.requiredEarlierRestart,
      'Required continuation is unavailable in the bounded index.',
    );
  }

  int? _removableIndex(List<_IndexedContinuation> entries) {
    // Preserve the prefix guard plus the active suffix and its exact parent.
    for (var index = 1; index < entries.length - 2; index++) {
      final entry = entries[index];
      if (!entry.sectionBoundary && !entry.activeFrontier) return index;
    }
    return null;
  }

  int _compareEntries(_IndexedContinuation first, _IndexedContinuation second) {
    final cursorOrder = _compareCursor(
      first.continuation.key.boundaryCursor,
      second.continuation.key.boundaryCursor,
    );
    if (cursorOrder != 0) return cursorOrder;
    final ordinalOrder = first.continuation.chainOrdinal.compareTo(
      second.continuation.chainOrdinal,
    );
    if (ordinalOrder != 0) return ordinalOrder;
    return first.continuation.integrityDigest.compareTo(
      second.continuation.integrityDigest,
    );
  }

  int _compareCursor(
    CanonicalPaginationCursor first,
    CanonicalPaginationCursor second,
  ) {
    if (first.isLogicalEnd != second.isLogicalEnd) {
      return first.isLogicalEnd ? 1 : -1;
    }
    var result = first.sourceOrdinalHint.compareTo(second.sourceOrdinalHint);
    if (result != 0) return result;
    result = first.textOffsetUtf16.compareTo(second.textOffsetUtf16);
    if (result != 0) return result;
    result = first.tableRowIndex.compareTo(second.tableRowIndex);
    if (result != 0) return result;
    return first.kind.index.compareTo(second.kind.index);
  }

  CanonicalPaginationContinuationRejected _rejected(
    CanonicalPaginationContinuationValidationKind kind,
    String message,
  ) => CanonicalPaginationContinuationRejected(kind: kind, message: message);
}

@immutable
final class CanonicalPaginationCheckpointBranch {
  const CanonicalPaginationCheckpointBranch.accepted(
    CanonicalPaginationCheckpointIndex this.index, {
    this.parent,
  }) : rejection = null;

  const CanonicalPaginationCheckpointBranch.rejected(
    CanonicalPaginationContinuationRejected this.rejection,
  ) : index = null,
      parent = null;

  final CanonicalPaginationCheckpointIndex? index;
  final CanonicalPaginationContinuation? parent;
  final CanonicalPaginationContinuationRejected? rejection;

  bool get accepted => index != null;
}

@immutable
final class _IndexedContinuation {
  const _IndexedContinuation({
    required this.continuation,
    required this.sectionBoundary,
    required this.activeFrontier,
  });

  final CanonicalPaginationContinuation continuation;
  final bool sectionBoundary;
  final bool activeFrontier;
}
