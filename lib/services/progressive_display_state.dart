import '../models/lazy_section_input.dart';
import 'lazy_snapshot_handoff_service.dart';
import 'package:flutter/foundation.dart';

import '../models/book_chunk.dart';
import '../models/canonical_display_segment.dart';
import '../models/canonical_pagination.dart';
import '../models/reader_checkpoint.dart';
import '../utils/reader_content_parser.dart';
import 'display_generation_coordinator.dart';

enum CanonicalDisplayPublicationOperation {
  initial,
  append,
  prepend,
  replacement,
}

enum CanonicalDisplayPublicationOutcomeKind {
  acceptedInitialPublication,
  acceptedAppend,
  acceptedPrepend,
  acceptedReplacement,
  idempotentAlreadyApplied,
  provisionalResultRejected,
  staleGenerationOrSession,
  incompatiblePublication,
  incompatibleSourceSnapshot,
  incompatibleLayout,
  incompatiblePagination,
  missingOrInvalidContinuation,
  seamGap,
  seamOverlap,
  duplicatedOwnership,
  reorderedOwnership,
  crossSectionOwnership,
  publishedCardIdentityMismatch,
  committedCardMismatch,
  boundViolation,
  cancellationBeforeCommit,
  validationError,
  canonicalRegenerationRequired,
}

@immutable
final class CanonicalDisplayPrependEvidence {
  const CanonicalDisplayPrependEvidence({
    required this.acceptedPublishedPrefix,
    required this.regeneratedPublishedPrefix,
    required this.acceptedCommittedCard,
    required this.regeneratedCommittedCard,
    required this.predecessorEndCursor,
    required this.currentStartCursor,
    required this.currentEndCursor,
    required this.successorStartCursor,
  });

  final CanonicalFinalizedReaderCard acceptedPublishedPrefix;
  final CanonicalFinalizedReaderCard regeneratedPublishedPrefix;
  final CanonicalFinalizedReaderCard acceptedCommittedCard;
  final CanonicalFinalizedReaderCard regeneratedCommittedCard;
  final CanonicalPaginationCursor predecessorEndCursor;
  final CanonicalPaginationCursor currentStartCursor;
  final CanonicalPaginationCursor currentEndCursor;
  final CanonicalPaginationCursor successorStartCursor;
}

@immutable
final class CanonicalDisplayPublicationRequest {
  CanonicalDisplayPublicationRequest({
    required this.operation,
    required this.sessionIdentity,
    required this.generationIdentity,
    required this.currentGenerationIdentity,
    required this.sourceSnapshot,
    required this.controlledLayoutIdentity,
    required this.paginationAlgorithmIdentity,
    required List<CanonicalFinalizedReaderCard> finalizedCards,
    required this.continuation,
    required this.isCancelled,
    this.predecessorContinuation,
    this.targetContainment,
    this.prependEvidence,
    this.committedCard,
    this.beforeCommit,
  }) : finalizedCards = List<CanonicalFinalizedReaderCard>.unmodifiable(
         finalizedCards,
       );

  final CanonicalDisplayPublicationOperation operation;
  final String sessionIdentity;
  final int generationIdentity;
  final int Function() currentGenerationIdentity;
  final CanonicalPaginationSourceSnapshot sourceSnapshot;
  final String controlledLayoutIdentity;
  final String paginationAlgorithmIdentity;
  final List<CanonicalFinalizedReaderCard> finalizedCards;
  final CanonicalPaginationContinuation continuation;
  final CanonicalPaginationContinuation? predecessorContinuation;
  final CanonicalPaginationTargetContainmentEvidence? targetContainment;
  final CanonicalDisplayPrependEvidence? prependEvidence;
  final CanonicalFinalizedReaderCard? committedCard;
  final bool Function() isCancelled;

  /// Synchronous test seam at the final validation/commit boundary.
  @visibleForTesting
  final void Function()? beforeCommit;
}

sealed class CanonicalDisplayPublicationResult {
  const CanonicalDisplayPublicationResult({required this.kind});

  final CanonicalDisplayPublicationOutcomeKind kind;
  bool get accepted => false;
  List<CanonicalFinalizedReaderCard> get publishableCards => const [];
  CanonicalPaginationContinuation? get acceptedContinuation => null;
  bool get hasCacheWriteAuthority => false;
  bool get hasCheckpointOrSettlementAuthority => false;
}

final class CanonicalDisplayPublicationAccepted
    extends CanonicalDisplayPublicationResult {
  CanonicalDisplayPublicationAccepted({
    required super.kind,
    required List<CanonicalFinalizedReaderCard> cards,
    required this.continuation,
    required this.insertedBefore,
    required this.committedDisplayIndex,
    required this.targetDisplayIndex,
  }) : _cards = List<CanonicalFinalizedReaderCard>.unmodifiable(cards);

  final List<CanonicalFinalizedReaderCard> _cards;
  final CanonicalPaginationContinuation continuation;
  final int insertedBefore;
  final int? committedDisplayIndex;
  final int? targetDisplayIndex;

  @override
  bool get accepted => true;
  @override
  List<CanonicalFinalizedReaderCard> get publishableCards => _cards;
  @override
  CanonicalPaginationContinuation get acceptedContinuation => continuation;
  @override
  bool get hasCacheWriteAuthority => true;
  @override
  bool get hasCheckpointOrSettlementAuthority => true;
}

final class CanonicalDisplayPublicationRejected
    extends CanonicalDisplayPublicationResult {
  const CanonicalDisplayPublicationRejected({
    required super.kind,
    required this.message,
  });

  final String message;
}

/// Private capability proving that one canonical record was derived from the
/// currently accepted P04 publication. Cache residence never creates this
/// capability and the cache service cannot manufacture it.
@immutable
final class CanonicalDisplayCacheWriteAuthorization {
  const CanonicalDisplayCacheWriteAuthorization._({
    required this.keyDigest,
    required this.recordDigest,
    required this.sourceSnapshotDigest,
  });

  final String keyDigest;
  final String recordDigest;
  final String sourceSnapshotDigest;
}

/// Stable-identity-only retention metadata minted from accepted publication
/// state. It deliberately contains no display/card/window index.
@immutable
final class CanonicalDisplayCacheRetentionAuthorization {
  CanonicalDisplayCacheRetentionAuthorization._(Iterable<String> digests)
    : pinnedKeyDigests = Set<String>.unmodifiable(digests);

  final Set<String> pinnedKeyDigests;
}

enum DisplayRangeDirection { initial, forward, backward, target }

enum DisplayBoundaryState { unavailable, preparing, ready, failed, complete }

final class SourceChunkRange {
  const SourceChunkRange(this.start, this.endExclusive)
    : assert(start >= 0),
      assert(endExclusive >= start);

  final int start;
  final int endExclusive;

  int get length => endExclusive - start;
  bool get isEmpty => length == 0;

  bool contains(int sourceIndex) =>
      sourceIndex >= start && sourceIndex < endExclusive;

  bool isAdjacentAfter(SourceChunkRange other) => start == other.endExclusive;
  bool isAdjacentBefore(SourceChunkRange other) => endExclusive == other.start;

  SourceChunkRange shift(int delta) {
    return SourceChunkRange(start + delta, endExclusive + delta);
  }

  @override
  String toString() => '[$start,$endExclusive)';
}

final class DisplayRangeRequest {
  const DisplayRangeRequest({
    required this.direction,
    required this.sourceRange,
    required this.generationId,
    required this.reason,
    this.targetOriginalIndex,
    this.targetTextOffset,
  });

  final DisplayRangeDirection direction;
  final SourceChunkRange sourceRange;
  final int generationId;
  final String reason;
  final int? targetOriginalIndex;
  final int? targetTextOffset;
}

final class DisplayRangeResult {
  const DisplayRangeResult({
    required this.request,
    required this.displayChunks,
    required this.displayToOriginal,
    required this.originalToDisplay,
    required this.inspectedSourceChunks,
    required this.elapsedMilliseconds,
    this.sliceCount = 1,
    this.yieldCount = 0,
    this.longestWorkIntervalMilliseconds = 0,
    this.maxSliceDurationMilliseconds = 0,
    this.totalYieldMilliseconds = 0,
    this.maxSourceChunksPerSlice = 0,
    this.maxDisplayChunksPerSlice = 0,
    this.cancellationLatencyMilliseconds,
    this.cancelled = false,
    this.error,
  });

  final DisplayRangeRequest request;
  final List<BookChunk> displayChunks;
  final List<List<int>> displayToOriginal;
  final Map<int, int> originalToDisplay;
  final int inspectedSourceChunks;
  final int elapsedMilliseconds;
  final int sliceCount;
  final int yieldCount;
  final int longestWorkIntervalMilliseconds;
  final int maxSliceDurationMilliseconds;
  final int totalYieldMilliseconds;
  final int maxSourceChunksPerSlice;
  final int maxDisplayChunksPerSlice;
  final int? cancellationLatencyMilliseconds;
  final bool cancelled;
  final Object? error;

  bool get succeeded => !cancelled && error == null;
}

final class PreparedDisplayRange {
  const PreparedDisplayRange({
    required this.sourceRange,
    required this.displayStart,
    required this.displayEndExclusive,
  });

  final SourceChunkRange sourceRange;
  final int displayStart;
  final int displayEndExclusive;

  int get displayLength => displayEndExclusive - displayStart;

  PreparedDisplayRange shiftDisplay(int delta) {
    return PreparedDisplayRange(
      sourceRange: sourceRange,
      displayStart: displayStart + delta,
      displayEndExclusive: displayEndExclusive + delta,
    );
  }
}

final class RemappedPreparedDisplaySnapshot {
  const RemappedPreparedDisplaySnapshot({
    required this.sourceRange,
    required this.displayChunks,
    required this.displayToOriginal,
    required this.originalToDisplay,
    required this.anchorDisplayIndex,
  });

  final SourceChunkRange sourceRange;
  final List<BookChunk> displayChunks;
  final List<List<int>> displayToOriginal;
  final Map<int, int> originalToDisplay;
  final int anchorDisplayIndex;
}

/// Remaps an already-published, layout-identical display run onto a replaced
/// lazy source window by stable source identity. Only the contiguous prepared
/// run containing [anchorStableKey] is retained, so no evicted source or hidden
/// gap can be published as ready.
RemappedPreparedDisplaySnapshot? remapPreparedDisplaySnapshot({
  required List<BookChunk> displayChunks,
  required List<List<int>> displayToOriginal,
  required Map<int, String> oldStableKeysBySourceIndex,
  required Map<String, int> newSourceIndexByStableKey,
  required Iterable<int> preparedOldSourceIndexes,
  required String anchorStableKey,
}) {
  final anchorSourceIndex = newSourceIndexByStableKey[anchorStableKey];
  if (anchorSourceIndex == null) return null;

  final preparedNewIndexes = <int>{};
  for (final oldIndex in preparedOldSourceIndexes) {
    final stableKey = oldStableKeysBySourceIndex[oldIndex];
    final newIndex = stableKey == null
        ? null
        : newSourceIndexByStableKey[stableKey];
    if (newIndex != null) preparedNewIndexes.add(newIndex);
  }
  if (!preparedNewIndexes.contains(anchorSourceIndex)) return null;

  var runStart = anchorSourceIndex;
  var runEnd = anchorSourceIndex;
  while (preparedNewIndexes.contains(runStart - 1)) {
    runStart--;
  }
  while (preparedNewIndexes.contains(runEnd + 1)) {
    runEnd++;
  }

  final retainedChunks = <BookChunk>[];
  final retainedMappings = <List<int>>[];
  final reverse = <int, int>{};
  int? anchorDisplayIndex;

  for (
    var displayIndex = 0;
    displayIndex < displayChunks.length;
    displayIndex++
  ) {
    if (displayIndex >= displayToOriginal.length) break;
    final originals = displayToOriginal[displayIndex];
    if (originals.isEmpty) continue;
    final remappedOriginals = <int>[];
    var intersectsRetainedRun = false;
    var canRetain = true;
    for (final oldIndex in originals) {
      final stableKey = oldStableKeysBySourceIndex[oldIndex];
      final newIndex = stableKey == null
          ? null
          : newSourceIndexByStableKey[stableKey];
      if (newIndex != null && newIndex >= runStart && newIndex <= runEnd) {
        intersectsRetainedRun = true;
      } else {
        canRetain = false;
      }
      if (newIndex != null && !remappedOriginals.contains(newIndex)) {
        remappedOriginals.add(newIndex);
      }
    }
    if (!intersectsRetainedRun) continue;
    if (!canRetain) return null;

    final remappedChunk = _remapDisplayChunkSourceIndexes(
      displayChunks[displayIndex],
      oldStableKeysBySourceIndex: oldStableKeysBySourceIndex,
      newSourceIndexByStableKey: newSourceIndexByStableKey,
      fallbackIndex: remappedOriginals.first,
    );
    if (remappedChunk == null) return null;

    final nextDisplayIndex = retainedChunks.length;
    retainedChunks.add(remappedChunk);
    retainedMappings.add(remappedOriginals);
    for (final sourceIndex in remappedOriginals) {
      reverse[sourceIndex] = nextDisplayIndex;
    }
    if (remappedOriginals.contains(anchorSourceIndex)) {
      anchorDisplayIndex ??= nextDisplayIndex;
    }
  }

  if (retainedChunks.isEmpty || anchorDisplayIndex == null) return null;
  return RemappedPreparedDisplaySnapshot(
    sourceRange: SourceChunkRange(runStart, runEnd + 1),
    displayChunks: retainedChunks,
    displayToOriginal: retainedMappings,
    originalToDisplay: reverse,
    anchorDisplayIndex: anchorDisplayIndex,
  );
}

BookChunk? _remapDisplayChunkSourceIndexes(
  BookChunk chunk, {
  required Map<int, String> oldStableKeysBySourceIndex,
  required Map<String, int> newSourceIndexByStableKey,
  required int fallbackIndex,
}) {
  final ranges = chunk.sourceRanges;
  if (ranges == null || ranges.isEmpty) {
    return chunk.copyWith(index: fallbackIndex);
  }
  final remapped = <ChunkSourceRange>[];
  for (final range in ranges) {
    final stableKey = oldStableKeysBySourceIndex[range.originalChunkIndex];
    final newIndex = stableKey == null
        ? null
        : newSourceIndexByStableKey[stableKey];
    if (newIndex == null) return null;
    remapped.add(
      ChunkSourceRange(
        originalChunkIndex: newIndex,
        originalStartOffset: range.originalStartOffset,
        originalEndOffset: range.originalEndOffset,
        displayStartOffset: range.displayStartOffset,
        displayEndOffset: range.displayEndOffset,
        logicalParagraphId: range.logicalParagraphId,
        paragraphStartOffset: range.paragraphStartOffset,
        paragraphEndOffset: range.paragraphEndOffset,
        isParagraphStart: range.isParagraphStart,
        isParagraphEnd: range.isParagraphEnd,
      ),
    );
  }
  return chunk.copyWith(index: fallbackIndex, sourceRanges: remapped);
}

final class ProgressiveDisplayState {
  ProgressiveDisplayState({
    required this.signature,
    required this.sourceChunkCount,
  });

  final DisplayGenerationSignature signature;
  int sourceChunkCount;
  List<PreparedDisplayRange> _ranges = [];
  List<BookChunk> _displayChunks = [];
  List<List<int>> _displayToOriginal = [];
  Map<int, int> _originalToDisplay = {};
  List<CanonicalFinalizedReaderCard> _canonicalCards = [];
  CanonicalPaginationContinuation? _acceptedCanonicalContinuation;
  CanonicalPaginationSourceSnapshot? _acceptedSourceSnapshot;
  String? _acceptedSessionIdentity;
  String? _acceptedLayoutIdentity;
  String? _acceptedPaginationIdentity;
  bool _canonicalCacheWriteAuthority = false;
  LazyAcceptedPublication? _lazyPublication;
  LazyPublicationOwner? _failedLazyAttempt;
  LazyAcceptedPublication? get lazyPublication => _lazyPublication;
  String? _lazyVisibleCardSignature;
  String? get lazyVisibleCardSignature => _lazyVisibleCardSignature;
  bool lazyAttemptFailed(LazyPublicationOwner owner) =>
      _failedLazyAttempt == owner;

  bool advanceLazyVisibleCard(
    String signature,
    LazyHandoffOperation operation,
  ) {
    final publication = _lazyPublication;
    if (publication == null ||
        !operation.isCurrent ||
        operation.owner.bookOpenEpoch != publication.owner.bookOpenEpoch ||
        operation.owner.displayOwner != publication.owner.displayOwner ||
        !publication.cards.any((c) => c.identity.signature == signature)) {
      return false;
    }
    _lazyVisibleCardSignature = signature;
    return true;
  }

  void latchLazyAttemptFailure(LazyHandoffOperation operation) {
    final old = _lazyPublication;
    if (operation.isCurrent &&
        old != null &&
        old.owner.bookOpenEpoch == operation.owner.bookOpenEpoch &&
        old.owner.displayOwner == operation.owner.displayOwner) {
      _failedLazyAttempt = operation.owner;
    }
  }

  LazySnapshotPublicationResult retainSnapshotSuffix({
    required LazyHandoffOperation operation,
    Set<String> pinnedRendererCards = const {},
    bool retainPredecessor = false,
    void Function(LazyRetainedSection)? onPrepared,
    void Function()? beforeCommit,
  }) {
    final old = _lazyPublication;
    if (old == null ||
        !operation.isCurrent ||
        old.owner.bookOpenEpoch != operation.owner.bookOpenEpoch ||
        old.owner.displayOwner != operation.owner.displayOwner) {
      return const LazySnapshotPublicationResult(
        LazySnapshotPublicationOutcome.stale,
      );
    }
    final selected = retainPredecessor ? old.predecessor : old.current;
    if (selected == null) {
      return const LazySnapshotPublicationResult(
        LazySnapshotPublicationOutcome.retentionRequired,
      );
    }
    final retainedSignatures = selected.cards
        .map((c) => c.identity.signature)
        .toSet();
    if (!retainedSignatures.contains(_lazyVisibleCardSignature) ||
        !pinnedRendererCards.every(retainedSignatures.contains)) {
      return const LazySnapshotPublicationResult(
        LazySnapshotPublicationOutcome.retentionRequired,
        'Visible card or renderer lease still pins the obsolete section',
      );
    }
    final visible = _lazyVisibleCardSignature;
    try {
      final retained = LazyRetainedSection.capture(selected);
      onPrepared?.call(retained);
      final candidate = LazyAcceptedPublication.retained(old, retained);
      final projection = _lazyProjection(candidate);
      beforeCommit?.call();
      if (!operation.isCurrent ||
          !identical(old, _lazyPublication) ||
          visible != _lazyVisibleCardSignature) {
        return const LazySnapshotPublicationResult(
          LazySnapshotPublicationOutcome.stale,
        );
      }
      retained.validate();
      _commitLazyPublication(candidate, projection);
      return const LazySnapshotPublicationResult(
        LazySnapshotPublicationOutcome.accepted,
      );
    } on Object catch (error) {
      return LazySnapshotPublicationResult(
        LazySnapshotPublicationOutcome.invalid,
        '$error',
      );
    }
  }

  LazySnapshotPublicationResult publishLazyInitial({
    required LazyPreparedSection prepared,
    required LazyHandoffOperation operation,
    void Function()? beforeCommit,
  }) {
    if (!operation.isCurrent || prepared.owner != operation.owner) {
      return const LazySnapshotPublicationResult(
        LazySnapshotPublicationOutcome.stale,
      );
    }
    if (_canonicalCards.isNotEmpty ||
        _lazyPublication != null ||
        prepared.input.sectionCount != 1 ||
        prepared.input.snapshot.bookId != signature.bookId) {
      return const LazySnapshotPublicationResult(
        LazySnapshotPublicationOutcome.invalid,
        'Initial lazy publication requires an empty matching reader',
      );
    }
    try {
      prepared.validate();
      final candidate = LazyAcceptedPublication.initial(
        prepared,
        operation.owner,
      );
      final projection = _lazyProjection(candidate);
      beforeCommit?.call();
      if (!operation.isCurrent ||
          _canonicalCards.isNotEmpty ||
          _lazyPublication != null) {
        return const LazySnapshotPublicationResult(
          LazySnapshotPublicationOutcome.stale,
        );
      }
      prepared.validate();
      if (!operation.isCurrent ||
          _canonicalCards.isNotEmpty ||
          _lazyPublication != null) {
        return const LazySnapshotPublicationResult(
          LazySnapshotPublicationOutcome.stale,
        );
      }
      _commitLazyPublication(candidate, projection);
      return const LazySnapshotPublicationResult(
        LazySnapshotPublicationOutcome.accepted,
      );
    } on Object catch (error) {
      return LazySnapshotPublicationResult(
        LazySnapshotPublicationOutcome.invalid,
        '$error',
      );
    }
  }

  /// Validated prepend imports only predecessor cards. The committed section
  /// stays byte-identical under its original renderer authority.
  LazySnapshotPublicationResult publishSnapshotPrepend({
    required LazyPreparedSection predecessor,
    required LazyPreparedSection reconstructedCurrent,
    required LazySectionInput window,
    required LazySnapshotHandoffV1 handoff,
    required LazyHandoffOperation operation,
    void Function()? beforeCommit,
  }) {
    final old = _lazyPublication;
    final visible = _lazyVisibleCardSignature;
    if (operation.pagination.isCancelled()) {
      return const LazySnapshotPublicationResult(
        LazySnapshotPublicationOutcome.cancelled,
      );
    }
    if (old == null ||
        visible == null ||
        !operation.isCurrent ||
        predecessor.owner != operation.owner ||
        reconstructedCurrent.owner != operation.owner ||
        old.owner.bookOpenEpoch != operation.owner.bookOpenEpoch ||
        old.owner.displayOwner != operation.owner.displayOwner) {
      return const LazySnapshotPublicationResult(
        LazySnapshotPublicationOutcome.stale,
      );
    }
    if (_failedLazyAttempt == operation.owner) {
      return const LazySnapshotPublicationResult(
        LazySnapshotPublicationOutcome.failedAttempt,
      );
    }
    try {
      final expected = buildLazySnapshotPrepend(
        old: old,
        predecessor: predecessor,
        reconstructedCurrent: reconstructedCurrent,
        window: window,
        committedCardSignature: visible,
      );
      if (expected.canonicalEncoding != handoff.canonicalEncoding ||
          expected.handoffDigest != handoff.handoffDigest) {
        throw StateError('Prepend evidence differs');
      }
      if (old.cards.length + predecessor.cards.length >
              CanonicalPaginationBounds.activeCardCeiling ||
          window.snapshot.sourceCount >
              CanonicalPaginationBounds.activeSourceCeiling) {
        throw StateError('Prepend exceeds publication bounds');
      }
      final candidate = LazyAcceptedPublication.prepended(
        old,
        predecessor,
        window,
        handoff,
      );
      final projection = _lazyProjection(candidate);
      beforeCommit?.call();
      if (operation.pagination.isCancelled()) {
        return const LazySnapshotPublicationResult(
          LazySnapshotPublicationOutcome.cancelled,
        );
      }
      if (!operation.isCurrent ||
          !identical(old, _lazyPublication) ||
          visible != _lazyVisibleCardSignature) {
        return const LazySnapshotPublicationResult(
          LazySnapshotPublicationOutcome.stale,
        );
      }
      final rechecked = buildLazySnapshotPrepend(
        old: old,
        predecessor: predecessor,
        reconstructedCurrent: reconstructedCurrent,
        window: window,
        committedCardSignature: visible,
      );
      if (rechecked.canonicalEncoding != expected.canonicalEncoding ||
          !operation.isCurrent ||
          !identical(old, _lazyPublication) ||
          visible != _lazyVisibleCardSignature) {
        return const LazySnapshotPublicationResult(
          LazySnapshotPublicationOutcome.stale,
        );
      }
      _commitLazyPublication(candidate, projection);
      return const LazySnapshotPublicationResult(
        LazySnapshotPublicationOutcome.accepted,
      );
    } on Object catch (error) {
      if (!operation.isCurrent || !identical(old, _lazyPublication)) {
        return const LazySnapshotPublicationResult(
          LazySnapshotPublicationOutcome.stale,
        );
      }
      _failedLazyAttempt = operation.owner;
      return LazySnapshotPublicationResult(
        error is LazyExactReconstructionUnavailable
            ? LazySnapshotPublicationOutcome.exactUnavailable
            : LazySnapshotPublicationOutcome.invalid,
        '$error',
      );
    }
  }

  /// Dedicated compare-and-swap append. Ordinary append validation is unchanged.
  LazySnapshotPublicationResult publishSnapshotHandoff({
    required LazyPreparedSection successor,
    required LazySnapshotHandoffV1 handoff,
    required LazyHandoffOperation operation,
    void Function()? beforeCommit,
  }) {
    final old = _lazyPublication;
    final visible = _lazyVisibleCardSignature;
    if (operation.pagination.isCancelled()) {
      return const LazySnapshotPublicationResult(
        LazySnapshotPublicationOutcome.cancelled,
      );
    }
    if (!operation.isCurrent ||
        successor.owner != operation.owner ||
        old == null ||
        old.owner.bookOpenEpoch != operation.owner.bookOpenEpoch ||
        old.owner.displayOwner != operation.owner.displayOwner) {
      return const LazySnapshotPublicationResult(
        LazySnapshotPublicationOutcome.stale,
      );
    }
    final ordinal = handoff.fields['handoffOrdinal'];
    if (ordinal is int && ordinal <= old.handoffOrdinal) {
      return const LazySnapshotPublicationResult(
        LazySnapshotPublicationOutcome.replayed,
      );
    }
    if (old.predecessor != null || old.current.input.sectionCount != 1) {
      return const LazySnapshotPublicationResult(
        LazySnapshotPublicationOutcome.retentionRequired,
      );
    }
    if (_failedLazyAttempt == operation.owner) {
      return const LazySnapshotPublicationResult(
        LazySnapshotPublicationOutcome.failedAttempt,
      );
    }
    try {
      final expected = buildLazySnapshotHandoff(
        old: old,
        successor: successor,
        committedCardSignature: _lazyVisibleCardSignature,
      );
      if (expected.canonicalEncoding != handoff.canonicalEncoding ||
          expected.handoffDigest != handoff.handoffDigest) {
        throw StateError(
          'Receipt, lineage, prefix or publication proof differs',
        );
      }
      if (_canonicalCards.length != old.cards.length ||
          !_sameCardSequence(_canonicalCards, old.cards)) {
        throw StateError('Accepted publication changed');
      }
      for (var i = 0; i < old.cards.length; i++) {
        LazyHandoffRenderingAdapter.block(
          retained: old.current,
          cardIndex: i,
          successor: successor,
        );
      }
      if (old.current.input.snapshot.sourceCount +
                  successor.input.snapshot.sourceCount >
              CanonicalPaginationBounds.activeSourceCeiling ||
          old.cards.length + successor.cards.length >
              CanonicalPaginationBounds.activeCardCeiling ||
          (old.current.session?.checkpointIndex.records.length ?? 0) +
                  successor.session.checkpointIndex.records.length >
              CanonicalPaginationBounds.residentContinuationRecordBasis) {
        throw StateError('Single-transfer aggregate authority bounds exceeded');
      }
      final candidate = LazyAcceptedPublication.transferred(
        old,
        successor,
        handoff,
        handoff.fields['successorSessionDigest']! as String,
      );
      final projection = _lazyProjection(candidate);
      final oldDigest = old.digest;
      beforeCommit?.call();
      if (operation.pagination.isCancelled()) {
        return const LazySnapshotPublicationResult(
          LazySnapshotPublicationOutcome.cancelled,
        );
      }
      if (!operation.isCurrent ||
          !identical(_lazyPublication, old) ||
          old.digest != oldDigest ||
          visible != _lazyVisibleCardSignature) {
        return const LazySnapshotPublicationResult(
          LazySnapshotPublicationOutcome.stale,
        );
      }
      // Recheck all retained bytes/evidence after the final callback. No mutation
      // of published cards, continuation ancestry or source records is involved.
      old.current.validate();
      successor.validate();
      if (!operation.isCurrent ||
          !identical(_lazyPublication, old) ||
          old.digest != oldDigest ||
          visible != _lazyVisibleCardSignature) {
        return const LazySnapshotPublicationResult(
          LazySnapshotPublicationOutcome.stale,
        );
      }
      _commitLazyPublication(candidate, projection);
      return const LazySnapshotPublicationResult(
        LazySnapshotPublicationOutcome.accepted,
      );
    } on Object catch (error) {
      if (!identical(_lazyPublication, old) || !operation.isCurrent) {
        return const LazySnapshotPublicationResult(
          LazySnapshotPublicationOutcome.stale,
        );
      }
      _failedLazyAttempt = operation.owner;
      return LazySnapshotPublicationResult(
        LazySnapshotPublicationOutcome.invalid,
        '$error',
      );
    }
  }

  ({
    List<BookChunk> chunks,
    List<List<int>> forward,
    Map<int, int> reverse,
    List<PreparedDisplayRange> ranges,
  })
  _lazyProjection(LazyAcceptedPublication publication) {
    final chunks = List<BookChunk>.unmodifiable(
      publication.cards.map((c) => c.card),
    );
    final forward = List<List<int>>.unmodifiable([
      for (final card in publication.cards)
        List<int>.unmodifiable(
          card.sourceSlices.map((s) {
            final owners = publication.sourceInput.snapshot.owners;
            final ordinal = owners.indexWhere(
              (o) =>
                  o.sourceIdentity == s.sourceIdentity &&
                  o.sectionIdentity == s.sectionIdentity &&
                  o.sourceDigest == s.sourceDigest,
            );
            if (ordinal < 0) {
              throw StateError('Retained stable source owner is absent');
            }
            return ordinal;
          }).toSet(),
        ),
    ]);
    final reverse = <int, int>{};
    for (var display = 0; display < forward.length; display++) {
      for (final source in forward[display]) {
        reverse[source] = display;
      }
    }
    return (
      chunks: chunks,
      forward: forward,
      reverse: Map.unmodifiable(reverse),
      ranges: List.unmodifiable([
        PreparedDisplayRange(
          sourceRange: SourceChunkRange(
            0,
            publication.sourceInput.snapshot.sourceCount,
          ),
          displayStart: 0,
          displayEndExclusive: chunks.length,
        ),
      ]),
    );
  }

  void _commitLazyPublication(
    LazyAcceptedPublication candidate,
    ({
      List<BookChunk> chunks,
      List<List<int>> forward,
      Map<int, int> reverse,
      List<PreparedDisplayRange> ranges,
    })
    projection,
  ) {
    _ranges = projection.ranges;
    _displayChunks = projection.chunks;
    _displayToOriginal = projection.forward;
    _originalToDisplay = projection.reverse;
    _canonicalCards = candidate.cards;
    _acceptedCanonicalContinuation = candidate.current.receipt == null
        ? candidate.current.continuation
        : null;
    _acceptedSourceSnapshot = candidate.sourceInput.snapshot;
    _acceptedSessionIdentity = candidate.sessionDigest;
    _acceptedLayoutIdentity = candidate.current.packingIdentity;
    _acceptedPaginationIdentity = readerPaginationAlgorithmVersion;
    _canonicalCacheWriteAuthority =
        false; // No ordinary cache terminal proof for a section receipt.
    sourceChunkCount = candidate.sourceInput.snapshot.sourceCount;
    initialWindowReady = true;
    generationComplete = candidate.current.input.verifiedBookEnd;
    _lazyPublication = candidate;
    _lazyVisibleCardSignature ??= candidate.cards.first.identity.signature;
    _failedLazyAttempt = null;
  }

  List<PreparedDisplayRange> get ranges => _ranges;
  List<BookChunk> get displayChunks => _displayChunks;
  List<List<int>> get displayToOriginal => _displayToOriginal;
  Map<int, int> get originalToDisplay => _originalToDisplay;
  List<CanonicalFinalizedReaderCard> get canonicalCards =>
      List<CanonicalFinalizedReaderCard>.unmodifiable(_canonicalCards);
  CanonicalPaginationContinuation? get acceptedCanonicalContinuation =>
      _acceptedCanonicalContinuation;
  bool get hasCanonicalCacheWriteAuthority => _canonicalCacheWriteAuthority;

  CanonicalDisplayCacheWriteAuthorization? authorizeCanonicalCacheWrite(
    CanonicalDisplaySegmentRecord record,
  ) {
    final snapshot = _acceptedSourceSnapshot;
    if (!_canonicalCacheWriteAuthority ||
        snapshot == null ||
        record.sourceSnapshotLink.snapshotDigest != snapshot.snapshotDigest ||
        !_recordCardsAreAccepted(record)) {
      return null;
    }
    return CanonicalDisplayCacheWriteAuthorization._(
      keyDigest: record.keyDigest,
      recordDigest: record.checksumDigest,
      sourceSnapshotDigest: snapshot.snapshotDigest,
    );
  }

  CanonicalDisplayCacheRetentionAuthorization?
  authorizeCanonicalCacheRetention({
    required String currentCardSignature,
    required Iterable<CanonicalDisplaySegmentRecord> residentRecords,
  }) {
    if (!_canonicalCacheWriteAuthority ||
        !_canonicalCards.any(
          (card) => card.identity.signature == currentCardSignature,
        )) {
      return null;
    }
    final records = residentRecords
        .where(_recordCardsAreAccepted)
        .toList(growable: false);
    final current =
        records
            .where(
              (record) => record.orderedFinalizedCards.any(
                (card) => card.physicalCardSignature == currentCardSignature,
              ),
            )
            .toList(growable: false)
          ..sort((left, right) => left.keyDigest.compareTo(right.keyDigest));
    if (current.isEmpty) return null;
    final selected = <String>{current.first.keyDigest};
    final currentRecord = current.first;
    final predecessors =
        records
            .where(
              (record) => record.stableEndCursor.samePositionAs(
                currentRecord.stableStartCursor,
              ),
            )
            .toList(growable: false)
          ..sort((left, right) => left.keyDigest.compareTo(right.keyDigest));
    final successors =
        records
            .where(
              (record) => record.stableStartCursor.samePositionAs(
                currentRecord.stableEndCursor,
              ),
            )
            .toList(growable: false)
          ..sort((left, right) => left.keyDigest.compareTo(right.keyDigest));
    if (predecessors.isNotEmpty) selected.add(predecessors.first.keyDigest);
    if (successors.isNotEmpty) selected.add(successors.first.keyDigest);
    return CanonicalDisplayCacheRetentionAuthorization._(selected);
  }

  bool _recordCardsAreAccepted(CanonicalDisplaySegmentRecord record) {
    if (record.orderedFinalizedCards.isEmpty || _canonicalCards.isEmpty) {
      return false;
    }
    final accepted = _canonicalCards
        .map((card) => card.identity.signature)
        .toList(growable: false);
    final candidate = record.orderedFinalizedCards
        .map((card) => card.physicalCardSignature)
        .toList(growable: false);
    for (
      var start = 0;
      start + candidate.length <= accepted.length;
      start += 1
    ) {
      var matches = true;
      for (var offset = 0; offset < candidate.length; offset += 1) {
        if (accepted[start + offset] != candidate[offset]) {
          matches = false;
          break;
        }
      }
      if (matches) return true;
    }
    return false;
  }

  DisplayRangeRequest? foregroundRequest;
  DisplayRangeRequest? lookaheadRequest;
  DisplayRangeRequest? failedRequest;
  Object? failure;
  bool initialWindowReady = false;
  bool generationComplete = false;
  bool externalUnavailableBefore = false;
  bool externalUnavailableAfter = false;

  bool get finalDisplayCountKnown => generationComplete;
  bool get hasPreparedContent => ranges.isNotEmpty;
  bool get hasUnavailableBefore =>
      externalUnavailableBefore ||
      (_canonicalCards.isNotEmpty &&
          (_canonicalCards.first.sourceSlices.first.sourceOrdinalHint > 0 ||
              (_canonicalCards.first.sourceSlices.first.startUtf16 ?? 0) > 0 ||
              (_canonicalCards.first.sourceSlices.first.tableRowStart ?? 0) >
                  0)) ||
      (ranges.isNotEmpty && ranges.first.sourceRange.start > 0);
  bool get hasUnavailableAfter =>
      externalUnavailableAfter ||
      (_acceptedCanonicalContinuation != null &&
          !_acceptedCanonicalContinuation!.terminal) ||
      (ranges.isNotEmpty &&
          ranges.last.sourceRange.endExclusive < sourceChunkCount);

  SourceChunkRange? get preparedSourceRange {
    if (ranges.isEmpty) return null;
    return SourceChunkRange(
      ranges.first.sourceRange.start,
      ranges.last.sourceRange.endExclusive,
    );
  }

  bool isSourcePrepared(int originalIndex) {
    return ranges.any((range) => range.sourceRange.contains(originalIndex));
  }

  int? displayIndexForSource(int originalIndex) {
    return originalToDisplay[originalIndex];
  }

  SourceChunkRange initialSourceRange({
    required int targetOriginalIndex,
    required int lookBehind,
    required int lookAhead,
    required int minimumWindow,
  }) {
    if (sourceChunkCount == 0) return const SourceChunkRange(0, 0);
    final target = targetOriginalIndex.clamp(0, sourceChunkCount - 1);
    var start = (target - lookBehind).clamp(0, sourceChunkCount);
    var end = (target + lookAhead + 1).clamp(0, sourceChunkCount);
    if (end - start < minimumWindow) {
      final needed = minimumWindow - (end - start);
      final growAfter = (sourceChunkCount - end).clamp(0, needed);
      end += growAfter;
      start = (start - (needed - growAfter)).clamp(0, sourceChunkCount);
    }
    return SourceChunkRange(start, end);
  }

  SourceChunkRange? nextForwardRange(int rangeSize) {
    if (ranges.isEmpty) return null;
    final canonicalCursor = _acceptedCanonicalContinuation?.nextSourceCursor;
    final start = canonicalCursor != null && !canonicalCursor.isLogicalEnd
        ? canonicalCursor.sourceOrdinalHint
        : ranges.last.sourceRange.endExclusive;
    if (start >= sourceChunkCount) return null;
    return SourceChunkRange(
      start,
      (start + rangeSize).clamp(0, sourceChunkCount),
    );
  }

  SourceChunkRange? nextBackwardRange(int rangeSize) {
    if (ranges.isEmpty) return null;
    final end = ranges.first.sourceRange.start;
    if (end <= 0) return null;
    return SourceChunkRange((end - rangeSize).clamp(0, sourceChunkCount), end);
  }

  SourceChunkRange targetRange({
    required int targetOriginalIndex,
    required int lookBehind,
    required int lookAhead,
    required int minimumWindow,
  }) {
    return initialSourceRange(
      targetOriginalIndex: targetOriginalIndex,
      lookBehind: lookBehind,
      lookAhead: lookAhead,
      minimumWindow: minimumWindow,
    );
  }

  bool shouldRequestForward({
    required int currentDisplayIndex,
    int threshold = 6,
  }) {
    return hasUnavailableAfter &&
        foregroundRequest?.direction != DisplayRangeDirection.forward &&
        displayChunks.isNotEmpty &&
        currentDisplayIndex >= displayChunks.length - 1 - threshold;
  }

  bool shouldRequestBackward({
    required int currentDisplayIndex,
    int threshold = 3,
  }) {
    return hasUnavailableBefore &&
        foregroundRequest?.direction != DisplayRangeDirection.backward &&
        displayChunks.isNotEmpty &&
        currentDisplayIndex <= threshold;
  }

  void publishInitial(DisplayRangeResult result) {
    _assertResultSucceeded(result);
    ranges
      ..clear()
      ..add(
        PreparedDisplayRange(
          sourceRange: result.request.sourceRange,
          displayStart: 0,
          displayEndExclusive: result.displayChunks.length,
        ),
      );
    displayChunks
      ..clear()
      ..addAll(result.displayChunks);
    displayToOriginal
      ..clear()
      ..addAll(result.displayToOriginal.map(List<int>.of));
    originalToDisplay
      ..clear()
      ..addAll(result.originalToDisplay);
    initialWindowReady = true;
    generationComplete =
        !externalUnavailableBefore &&
        !externalUnavailableAfter &&
        result.request.sourceRange.start == 0 &&
        result.request.sourceRange.endExclusive == sourceChunkCount;
    foregroundRequest = null;
    failedRequest = null;
    failure = null;
    _clearCanonicalAuthority();
  }

  int append(DisplayRangeResult result) {
    _assertResultSucceeded(result);
    if (ranges.isEmpty) {
      publishInitial(result);
      return result.displayChunks.length;
    }
    final sourceRange = result.request.sourceRange;
    if (!sourceRange.isAdjacentAfter(ranges.last.sourceRange)) {
      throw StateError(
        'Forward range $sourceRange is not adjacent to ${ranges.last.sourceRange}',
      );
    }
    final displayOffset = displayChunks.length;
    displayChunks.addAll(result.displayChunks);
    displayToOriginal.addAll(result.displayToOriginal.map(List<int>.of));
    for (final entry in result.originalToDisplay.entries) {
      originalToDisplay[entry.key] = entry.value + displayOffset;
    }
    ranges.add(
      PreparedDisplayRange(
        sourceRange: sourceRange,
        displayStart: displayOffset,
        displayEndExclusive: displayChunks.length,
      ),
    );
    _updateCompletion();
    foregroundRequest = null;
    lookaheadRequest = null;
    failedRequest = null;
    failure = null;
    _clearCanonicalAuthority();
    return result.displayChunks.length;
  }

  int prepend(DisplayRangeResult result) {
    _assertResultSucceeded(result);
    if (ranges.isEmpty) {
      publishInitial(result);
      return result.displayChunks.length;
    }
    final sourceRange = result.request.sourceRange;
    if (!sourceRange.isAdjacentBefore(ranges.first.sourceRange)) {
      throw StateError(
        'Backward range $sourceRange is not adjacent to ${ranges.first.sourceRange}',
      );
    }
    final inserted = result.displayChunks.length;
    displayChunks.insertAll(0, result.displayChunks);
    displayToOriginal.insertAll(0, result.displayToOriginal.map(List<int>.of));
    final shifted = <int, int>{
      for (final entry in originalToDisplay.entries)
        entry.key: entry.value + inserted,
    };
    shifted.addAll(result.originalToDisplay);
    originalToDisplay
      ..clear()
      ..addAll(shifted);
    ranges.replaceRange(0, ranges.length, [
      PreparedDisplayRange(
        sourceRange: sourceRange,
        displayStart: 0,
        displayEndExclusive: inserted,
      ),
      ...ranges.map((range) => range.shiftDisplay(inserted)),
    ]);
    _updateCompletion();
    foregroundRequest = null;
    failedRequest = null;
    failure = null;
    _clearCanonicalAuthority();
    return inserted;
  }

  CanonicalDisplayPublicationResult rejectNonCanonicalCachePublication({
    required String cacheKind,
  }) {
    return CanonicalDisplayPublicationRejected(
      kind:
          CanonicalDisplayPublicationOutcomeKind.canonicalRegenerationRequired,
      message:
          '$cacheKind cache data has no finalized canonical identity and continuation authority.',
    );
  }

  CanonicalDisplayPublicationResult publishCanonical(
    CanonicalDisplayPublicationRequest request,
  ) {
    final rejection = _validateCanonicalRequest(request);
    if (rejection != null) return rejection;

    try {
      final candidate = _buildCanonicalCandidate(request);
      if (candidate is CanonicalDisplayPublicationRejected) return candidate;
      final prepared = candidate as _CanonicalDisplayCandidate;
      if (request.isCancelled()) {
        return const CanonicalDisplayPublicationRejected(
          kind: CanonicalDisplayPublicationOutcomeKind.cancellationBeforeCommit,
          message: 'Canonical publication was cancelled before commit.',
        );
      }
      if (request.currentGenerationIdentity() != request.generationIdentity) {
        return const CanonicalDisplayPublicationRejected(
          kind: CanonicalDisplayPublicationOutcomeKind.staleGenerationOrSession,
          message: 'Canonical publication generation became stale.',
        );
      }
      request.beforeCommit?.call();
      if (request.isCancelled()) {
        return const CanonicalDisplayPublicationRejected(
          kind: CanonicalDisplayPublicationOutcomeKind.cancellationBeforeCommit,
          message: 'Canonical publication was cancelled at commit.',
        );
      }
      if (request.currentGenerationIdentity() != request.generationIdentity) {
        return const CanonicalDisplayPublicationRejected(
          kind: CanonicalDisplayPublicationOutcomeKind.staleGenerationOrSession,
          message: 'Canonical publication generation changed at commit.',
        );
      }

      // All values are complete private candidates. No validation, allocation,
      // callback, or throwing operation follows these synchronous swaps.
      _ranges = prepared.ranges;
      _displayChunks = prepared.displayChunks;
      _displayToOriginal = prepared.displayToOriginal;
      _originalToDisplay = prepared.originalToDisplay;
      _canonicalCards = prepared.canonicalCards;
      _acceptedCanonicalContinuation = prepared.continuation;
      _acceptedSourceSnapshot = request.sourceSnapshot;
      _acceptedSessionIdentity = request.sessionIdentity;
      _acceptedLayoutIdentity = request.controlledLayoutIdentity;
      _acceptedPaginationIdentity = request.paginationAlgorithmIdentity;
      _canonicalCacheWriteAuthority = true;
      _lazyPublication = null;
      _lazyVisibleCardSignature = null;
      _failedLazyAttempt = null;
      initialWindowReady = true;
      generationComplete = prepared.generationComplete;
      foregroundRequest = null;
      lookaheadRequest = null;
      failedRequest = null;
      failure = null;

      return CanonicalDisplayPublicationAccepted(
        kind: prepared.kind,
        cards: request.finalizedCards,
        continuation: prepared.continuation,
        insertedBefore: prepared.insertedBefore,
        committedDisplayIndex: prepared.committedDisplayIndex,
        targetDisplayIndex: prepared.targetDisplayIndex,
      );
    } on Object catch (error) {
      return CanonicalDisplayPublicationRejected(
        kind: CanonicalDisplayPublicationOutcomeKind.validationError,
        message: 'Canonical publication validation failed: $error',
      );
    }
  }

  CanonicalDisplayPublicationRejected? _validateCanonicalRequest(
    CanonicalDisplayPublicationRequest request,
  ) {
    if (request.isCancelled()) {
      return const CanonicalDisplayPublicationRejected(
        kind: CanonicalDisplayPublicationOutcomeKind.cancellationBeforeCommit,
        message: 'Canonical publication was already cancelled.',
      );
    }
    if (request.currentGenerationIdentity() != request.generationIdentity) {
      return const CanonicalDisplayPublicationRejected(
        kind: CanonicalDisplayPublicationOutcomeKind.staleGenerationOrSession,
        message: 'Canonical publication generation is stale.',
      );
    }
    if (request.sessionIdentity.isEmpty ||
        request.sourceSnapshot.bookId != signature.bookId ||
        request.continuation.key.bookId != signature.bookId ||
        request.continuation.key.publicationFingerprint !=
            request.sourceSnapshot.publicationFingerprint) {
      return const CanonicalDisplayPublicationRejected(
        kind: CanonicalDisplayPublicationOutcomeKind.incompatiblePublication,
        message: 'Book/publication identity is incompatible.',
      );
    }
    if (request.continuation.key.parserSourceIdentity !=
            request.sourceSnapshot.parserSourceIdentity ||
        request.continuation.key.sourceRevision !=
            request.sourceSnapshot.sourceRevision ||
        request.continuation.key.sourceSnapshotDigest !=
            request.sourceSnapshot.snapshotDigest) {
      return const CanonicalDisplayPublicationRejected(
        kind: CanonicalDisplayPublicationOutcomeKind.incompatibleSourceSnapshot,
        message: 'Parser/source snapshot identity is incompatible.',
      );
    }
    if (request.continuation.key.controlledLayoutIdentity !=
        request.controlledLayoutIdentity) {
      return const CanonicalDisplayPublicationRejected(
        kind: CanonicalDisplayPublicationOutcomeKind.incompatibleLayout,
        message: 'Controlled layout identity is incompatible.',
      );
    }
    if (request.continuation.key.paginationAlgorithmIdentity !=
        request.paginationAlgorithmIdentity) {
      return const CanonicalDisplayPublicationRejected(
        kind: CanonicalDisplayPublicationOutcomeKind.incompatiblePagination,
        message: 'Pagination identity is incompatible.',
      );
    }
    final decoded = CanonicalPaginationContinuationCodec.decode(
      CanonicalPaginationContinuationCodec.encode(request.continuation),
    );
    if (decoded is! CanonicalPaginationContinuationAccepted) {
      return const CanonicalDisplayPublicationRejected(
        kind:
            CanonicalDisplayPublicationOutcomeKind.missingOrInvalidContinuation,
        message: 'Canonical continuation integrity validation failed.',
      );
    }
    if (request.finalizedCards.isEmpty) {
      return const CanonicalDisplayPublicationRejected(
        kind: CanonicalDisplayPublicationOutcomeKind.provisionalResultRejected,
        message: 'No finalized canonical card is publishable.',
      );
    }
    if (request.operation != CanonicalDisplayPublicationOperation.initial &&
        request.operation != CanonicalDisplayPublicationOperation.replacement) {
      if (_acceptedSourceSnapshot == null ||
          _acceptedSessionIdentity != request.sessionIdentity ||
          _acceptedSourceSnapshot!.snapshotDigest !=
              request.sourceSnapshot.snapshotDigest) {
        return const CanonicalDisplayPublicationRejected(
          kind: CanonicalDisplayPublicationOutcomeKind.staleGenerationOrSession,
          message: 'Extension does not belong to the accepted session.',
        );
      }
      if (_acceptedLayoutIdentity != request.controlledLayoutIdentity) {
        return const CanonicalDisplayPublicationRejected(
          kind: CanonicalDisplayPublicationOutcomeKind.incompatibleLayout,
          message: 'Extension layout differs from the accepted snapshot.',
        );
      }
      if (_acceptedPaginationIdentity != request.paginationAlgorithmIdentity) {
        return const CanonicalDisplayPublicationRejected(
          kind: CanonicalDisplayPublicationOutcomeKind.incompatiblePagination,
          message: 'Extension pagination identity differs.',
        );
      }
    }
    return null;
  }

  Object _buildCanonicalCandidate(CanonicalDisplayPublicationRequest request) {
    final incoming = request.finalizedCards;
    for (final card in incoming) {
      final cardRejection = _validateCanonicalCard(card, request);
      if (cardRejection != null) return cardRejection;
    }

    final existing = _canonicalCards;
    if ((request.operation == CanonicalDisplayPublicationOperation.initial ||
            request.operation ==
                CanonicalDisplayPublicationOperation.replacement) &&
        !_boundaryOwnsCard(
          request.continuation.previousFinalizedBoundary,
          incoming.last,
        )) {
      return const CanonicalDisplayPublicationRejected(
        kind:
            CanonicalDisplayPublicationOutcomeKind.missingOrInvalidContinuation,
        message:
            'Initial/replacement continuation does not own its final card.',
      );
    }
    final acceptedContinuationMatches =
        request.operation == CanonicalDisplayPublicationOperation.prepend
        ? request.predecessorContinuation?.integrityDigest ==
              _acceptedCanonicalContinuation?.integrityDigest
        : _acceptedCanonicalContinuation?.integrityDigest ==
              request.continuation.integrityDigest;
    if (existing.isNotEmpty &&
        acceptedContinuationMatches &&
        _isAlreadyApplied(request.operation, existing, incoming)) {
      if (request.committedCard != null &&
          !existing.any(
            (card) => _sameFinalizedCard(card, request.committedCard!),
          )) {
        return const CanonicalDisplayPublicationRejected(
          kind: CanonicalDisplayPublicationOutcomeKind.committedCardMismatch,
          message: 'The stable committed card is absent from the snapshot.',
        );
      }
      if (request.targetContainment != null) {
        final targetRejection = _validateTarget(request, existing);
        if (targetRejection != null) return targetRejection;
      }
      return _candidateFromAcceptedSnapshot(request);
    }
    late final List<CanonicalFinalizedReaderCard> candidateCards;
    late final CanonicalDisplayPublicationOutcomeKind acceptedKind;
    var insertedBefore = 0;
    switch (request.operation) {
      case CanonicalDisplayPublicationOperation.initial:
        candidateCards = List.of(incoming);
        acceptedKind =
            CanonicalDisplayPublicationOutcomeKind.acceptedInitialPublication;
        if (request.targetContainment != null) {
          final targetRejection = _validateTarget(request, candidateCards);
          if (targetRejection != null) return targetRejection;
        }
      case CanonicalDisplayPublicationOperation.replacement:
        candidateCards = List.of(incoming);
        acceptedKind =
            CanonicalDisplayPublicationOutcomeKind.acceptedReplacement;
        if (request.targetContainment != null) {
          final targetRejection = _validateTarget(request, candidateCards);
          if (targetRejection != null) return targetRejection;
        }
      case CanonicalDisplayPublicationOperation.append:
        if (existing.isEmpty) {
          return const CanonicalDisplayPublicationRejected(
            kind: CanonicalDisplayPublicationOutcomeKind
                .publishedCardIdentityMismatch,
            message: 'Append requires an accepted canonical prefix.',
          );
        }
        final predecessor = request.predecessorContinuation;
        if (predecessor == null ||
            _acceptedCanonicalContinuation?.integrityDigest !=
                predecessor.integrityDigest ||
            request.continuation.parentDigest != predecessor.integrityDigest ||
            !_boundaryOwnsCard(
              predecessor.previousFinalizedBoundary,
              existing.last,
            )) {
          return const CanonicalDisplayPublicationRejected(
            kind: CanonicalDisplayPublicationOutcomeKind
                .missingOrInvalidContinuation,
            message: 'Append continuation does not own the accepted suffix.',
          );
        }
        final seam = _classifyCursorSeam(
          predecessor.previousFinalizedBoundary.endCursor,
          _cardStartCursor(incoming.first),
        );
        if (seam != null) return seam;
        if (!_boundaryOwnsCard(
          request.continuation.previousFinalizedBoundary,
          incoming.last,
        )) {
          return const CanonicalDisplayPublicationRejected(
            kind: CanonicalDisplayPublicationOutcomeKind
                .missingOrInvalidContinuation,
            message: 'Append result continuation does not own its final card.',
          );
        }
        candidateCards = <CanonicalFinalizedReaderCard>[
          ...existing,
          ...incoming,
        ];
        acceptedKind = CanonicalDisplayPublicationOutcomeKind.acceptedAppend;
      case CanonicalDisplayPublicationOperation.prepend:
        if (existing.isEmpty || request.prependEvidence == null) {
          return const CanonicalDisplayPublicationRejected(
            kind: CanonicalDisplayPublicationOutcomeKind
                .missingOrInvalidContinuation,
            message: 'Prepend requires canonical overlap/current evidence.',
          );
        }
        final evidence = request.prependEvidence!;
        final acceptedContinuation = _acceptedCanonicalContinuation;
        final predecessorContinuation = request.predecessorContinuation;
        if (acceptedContinuation == null ||
            predecessorContinuation == null ||
            acceptedContinuation.integrityDigest !=
                predecessorContinuation.integrityDigest) {
          return const CanonicalDisplayPublicationRejected(
            kind: CanonicalDisplayPublicationOutcomeKind
                .missingOrInvalidContinuation,
            message: 'Prepend must preserve the accepted continuation state.',
          );
        }
        if (!_sameStableFinalizedCard(
              existing.first,
              evidence.acceptedPublishedPrefix,
            ) ||
            !_sameStableFinalizedCard(
              evidence.acceptedPublishedPrefix,
              evidence.regeneratedPublishedPrefix,
            )) {
          return const CanonicalDisplayPublicationRejected(
            kind: CanonicalDisplayPublicationOutcomeKind
                .publishedCardIdentityMismatch,
            message: 'Regenerated prefix does not equal the accepted prefix.',
          );
        }
        final committedIndex = existing.indexWhere(
          (card) =>
              _sameStableFinalizedCard(card, evidence.acceptedCommittedCard),
        );
        final regenerationBoundary =
            request.continuation.previousFinalizedBoundary;
        final regenerationSpansCurrent =
            _cursorBelongsToSnapshot(
              request.continuation.startSourceCursor,
              request.sourceSnapshot,
            ) &&
            _cursorBelongsToSnapshot(
              regenerationBoundary.endCursor,
              request.sourceSnapshot,
            ) &&
            _compareCursor(
                  request.continuation.startSourceCursor,
                  evidence.currentStartCursor,
                ) <=
                0 &&
            _compareCursor(
                  regenerationBoundary.endCursor,
                  evidence.currentEndCursor,
                ) >=
                0;
        if (committedIndex < 0 ||
            request.committedCard == null ||
            !_sameStableFinalizedCard(
              evidence.acceptedCommittedCard,
              request.committedCard!,
            ) ||
            !_sameStableFinalizedCard(
              evidence.acceptedCommittedCard,
              evidence.regeneratedCommittedCard,
            ) ||
            !_sameStableCursorPosition(
              evidence.predecessorEndCursor,
              evidence.currentStartCursor,
            ) ||
            !_sameStableCursorPosition(
              evidence.currentEndCursor,
              evidence.successorStartCursor,
            ) ||
            regenerationBoundary.kind !=
                CanonicalPaginationBoundaryKind.finalizedCard ||
            regenerationBoundary.cardIdentity == null ||
            !regenerationSpansCurrent) {
          return const CanonicalDisplayPublicationRejected(
            kind: CanonicalDisplayPublicationOutcomeKind.committedCardMismatch,
            message: 'Prepend committed/current overlap evidence differs.',
          );
        }
        final seam = _classifyCursorSeam(
          _cardEndCursor(incoming.last, request.sourceSnapshot),
          _cardStartCursor(existing.first),
        );
        if (seam != null) return seam;
        candidateCards = <CanonicalFinalizedReaderCard>[
          ...incoming,
          ...existing,
        ];
        insertedBefore = incoming.length;
        acceptedKind = CanonicalDisplayPublicationOutcomeKind.acceptedPrepend;
    }

    if (candidateCards.length > CanonicalPaginationBounds.activeCardCeiling) {
      return const CanonicalDisplayPublicationRejected(
        kind: CanonicalDisplayPublicationOutcomeKind.boundViolation,
        message: 'Canonical publication exceeds the resident card bound.',
      );
    }
    final coverageRejection = _validateOrderedCoverage(
      candidateCards,
      request.sourceSnapshot,
    );
    if (coverageRejection != null) return coverageRejection;

    final current = request.committedCard;
    final committedIndex = current == null
        ? null
        : candidateCards.indexWhere(
            (card) => _sameFinalizedCard(card, current),
          );
    if (current != null && committedIndex! < 0) {
      return const CanonicalDisplayPublicationRejected(
        kind: CanonicalDisplayPublicationOutcomeKind.committedCardMismatch,
        message: 'The stable committed card is absent from the candidate.',
      );
    }
    final targetIdentity = request.targetContainment?.cardIdentity;
    final targetIndex = targetIdentity == null
        ? null
        : candidateCards.indexWhere(
            (card) => card.identity.signature == targetIdentity.signature,
          );

    final displayChunks = <BookChunk>[
      for (final card in candidateCards) card.card,
    ];
    final displayToOriginal = <List<int>>[
      for (final card in candidateCards)
        card.sourceSlices
            .map((slice) => slice.sourceOrdinalHint)
            .toSet()
            .toList(growable: false),
    ];
    final originalToDisplay = <int, int>{};
    for (var display = 0; display < displayToOriginal.length; display++) {
      for (final source in displayToOriginal[display]) {
        originalToDisplay[source] = display;
      }
    }
    final incomingStart = incoming.first.sourceSlices.first.sourceOrdinalHint;
    final incomingEnd = incoming.last.sourceSlices.last.sourceOrdinalHint + 1;
    late final List<PreparedDisplayRange> ranges;
    if (request.operation == CanonicalDisplayPublicationOperation.append) {
      ranges = <PreparedDisplayRange>[
        ..._ranges,
        PreparedDisplayRange(
          sourceRange: SourceChunkRange(incomingStart, incomingEnd),
          displayStart: existing.length,
          displayEndExclusive: candidateCards.length,
        ),
      ];
    } else if (request.operation ==
        CanonicalDisplayPublicationOperation.prepend) {
      ranges = <PreparedDisplayRange>[
        PreparedDisplayRange(
          sourceRange: SourceChunkRange(incomingStart, incomingEnd),
          displayStart: 0,
          displayEndExclusive: incoming.length,
        ),
        for (final range in _ranges) range.shiftDisplay(incoming.length),
      ];
    } else {
      ranges = <PreparedDisplayRange>[
        PreparedDisplayRange(
          sourceRange: SourceChunkRange(incomingStart, incomingEnd),
          displayStart: 0,
          displayEndExclusive: incoming.length,
        ),
      ];
    }

    final candidateContinuation =
        request.operation == CanonicalDisplayPublicationOperation.prepend
        ? _acceptedCanonicalContinuation!
        : request.continuation;
    final idempotent =
        _sameCardSequence(candidateCards, existing) &&
        _acceptedCanonicalContinuation?.integrityDigest ==
            candidateContinuation.integrityDigest;
    return _CanonicalDisplayCandidate(
      kind: idempotent
          ? CanonicalDisplayPublicationOutcomeKind.idempotentAlreadyApplied
          : acceptedKind,
      ranges: List<PreparedDisplayRange>.unmodifiable(ranges),
      displayChunks: List<BookChunk>.unmodifiable(displayChunks),
      displayToOriginal: List<List<int>>.unmodifiable(
        displayToOriginal.map(List<int>.unmodifiable),
      ),
      originalToDisplay: Map<int, int>.unmodifiable(originalToDisplay),
      canonicalCards: List<CanonicalFinalizedReaderCard>.unmodifiable(
        candidateCards,
      ),
      generationComplete:
          !externalUnavailableBefore &&
          !externalUnavailableAfter &&
          candidateCards.first.sourceSlices.first.sourceOrdinalHint == 0 &&
          candidateContinuation.terminal,
      insertedBefore: insertedBefore,
      committedDisplayIndex: committedIndex,
      targetDisplayIndex: targetIndex,
      continuation: candidateContinuation,
    );
  }

  CanonicalDisplayPublicationRejected? _validateCanonicalCard(
    CanonicalFinalizedReaderCard card,
    CanonicalDisplayPublicationRequest request,
  ) {
    if (card.identity.publicationFingerprint !=
        request.sourceSnapshot.publicationFingerprint) {
      return const CanonicalDisplayPublicationRejected(
        kind: CanonicalDisplayPublicationOutcomeKind.incompatiblePublication,
        message: 'Published card belongs to another publication.',
      );
    }
    if (card.identity.layoutFingerprint != request.controlledLayoutIdentity) {
      return const CanonicalDisplayPublicationRejected(
        kind: CanonicalDisplayPublicationOutcomeKind.incompatibleLayout,
        message: 'Published card belongs to another layout.',
      );
    }
    if (card.identity.paginationVersion !=
        request.paginationAlgorithmIdentity) {
      return const CanonicalDisplayPublicationRejected(
        kind: CanonicalDisplayPublicationOutcomeKind.incompatiblePagination,
        message: 'Published card belongs to another pagination algorithm.',
      );
    }
    for (final slice in card.sourceSlices) {
      final ordinal = request.sourceSnapshot.resolveOrdinal(
        sourceIdentity: slice.sourceIdentity,
        ordinalHint: slice.sourceOrdinalHint,
      );
      if (ordinal == null ||
          request.sourceSnapshot.ownerAt(ordinal).sectionIdentity !=
              slice.sectionIdentity ||
          request.sourceSnapshot.ownerAt(ordinal).spineIdentity !=
              slice.spineIdentity ||
          request.sourceSnapshot.ownerAt(ordinal).sourceDigest !=
              slice.sourceDigest) {
        return const CanonicalDisplayPublicationRejected(
          kind:
              CanonicalDisplayPublicationOutcomeKind.incompatibleSourceSnapshot,
          message: 'Published slice is not owned by the pinned snapshot.',
        );
      }
    }
    try {
      final rebuilt = CanonicalReaderCardIdentityBuilder.build(
        publicationFingerprint: request.sourceSnapshot.publicationFingerprint,
        controlledLayoutIdentity: request.controlledLayoutIdentity,
        paginationAlgorithmIdentity: request.paginationAlgorithmIdentity,
        orderedSourceSlices: card.sourceSlices,
      );
      if (canonicalJsonEncode(rebuilt.toJson()) !=
          canonicalJsonEncode(card.identity.toJson())) {
        return const CanonicalDisplayPublicationRejected(
          kind: CanonicalDisplayPublicationOutcomeKind
              .publishedCardIdentityMismatch,
          message: 'Published-card identity is not canonical for its slices.',
        );
      }
    } on FormatException catch (error) {
      return CanonicalDisplayPublicationRejected(
        kind: error.message.toString().contains('section/spine')
            ? CanonicalDisplayPublicationOutcomeKind.crossSectionOwnership
            : CanonicalDisplayPublicationOutcomeKind
                  .publishedCardIdentityMismatch,
        message: error.message.toString(),
      );
    }
    return null;
  }

  CanonicalDisplayPublicationRejected? _validateTarget(
    CanonicalDisplayPublicationRequest request,
    List<CanonicalFinalizedReaderCard> cards,
  ) {
    final evidence = request.targetContainment!;
    final matching = cards.where(
      (card) => card.identity.signature == evidence.cardIdentity.signature,
    );
    if (matching.length != 1 ||
        !matching.single.sourceSlices.any(
          (slice) =>
              canonicalJsonEncode(slice.toCanonicalJson()) ==
              canonicalJsonEncode(evidence.containingSlice.toCanonicalJson()),
        )) {
      return const CanonicalDisplayPublicationRejected(
        kind: CanonicalDisplayPublicationOutcomeKind.committedCardMismatch,
        message: 'Stable target is not contained by exactly one final card.',
      );
    }
    final slice = evidence.containingSlice;
    final offset = evidence.target.textOffsetUtf16;
    if ((slice.startUtf16 != null &&
            (offset < slice.startUtf16! || offset >= slice.endUtf16!)) ||
        (slice.startUtf16 == null && offset != 0)) {
      return const CanonicalDisplayPublicationRejected(
        kind: CanonicalDisplayPublicationOutcomeKind.committedCardMismatch,
        message: 'Stable target containment is approximate or invalid.',
      );
    }
    return null;
  }

  CanonicalDisplayPublicationRejected? _validateOrderedCoverage(
    List<CanonicalFinalizedReaderCard> cards,
    CanonicalPaginationSourceSnapshot snapshot,
  ) {
    final slices = cards.expand((card) => card.sourceSlices).toList();
    final seen = <String>{};
    CanonicalPaginationSourceSlice? previous;
    for (final slice in slices) {
      final key = canonicalJsonEncode(slice.toCanonicalJson());
      if (!seen.add(key)) {
        return const CanonicalDisplayPublicationRejected(
          kind: CanonicalDisplayPublicationOutcomeKind.duplicatedOwnership,
          message: 'Canonical ownership is duplicated.',
        );
      }
      final prior = previous;
      if (prior != null) {
        if (slice.sourceOrdinalHint < prior.sourceOrdinalHint) {
          return const CanonicalDisplayPublicationRejected(
            kind: CanonicalDisplayPublicationOutcomeKind.reorderedOwnership,
            message: 'Canonical ownership is reordered.',
          );
        }
        if (slice.sourceOrdinalHint == prior.sourceOrdinalHint) {
          final priorEnd = prior.endUtf16 ?? prior.tableRowEndExclusive;
          final nextStart = slice.startUtf16 ?? slice.tableRowStart;
          if (priorEnd == null || nextStart == null || priorEnd != nextStart) {
            return CanonicalDisplayPublicationRejected(
              kind:
                  priorEnd != null && nextStart != null && priorEnd > nextStart
                  ? CanonicalDisplayPublicationOutcomeKind.seamOverlap
                  : CanonicalDisplayPublicationOutcomeKind.seamGap,
              message: 'Adjacent canonical intervals do not meet exactly.',
            );
          }
        } else {
          final priorSource = snapshot.resolveOrdinalSource(
            prior.sourceOrdinalHint,
          );
          final priorReachedEnd = prior.tableRowEndExclusive != null
              ? prior.tableRowEndExclusive == _tableRowCount(priorSource)
              : prior.endUtf16 == (priorSource.text?.length ?? 0);
          final nextStartsAtBeginning = slice.tableRowStart != null
              ? slice.tableRowStart == 0
              : slice.startUtf16 == 0;
          if (!priorReachedEnd || !nextStartsAtBeginning) {
            return const CanonicalDisplayPublicationRejected(
              kind: CanonicalDisplayPublicationOutcomeKind.seamGap,
              message: 'Canonical source boundary is not fully covered.',
            );
          }
          for (
            var ordinal = prior.sourceOrdinalHint + 1;
            ordinal < slice.sourceOrdinalHint;
            ordinal++
          ) {
            final source = snapshot.resolveOrdinalSource(ordinal);
            if ((source.text?.isNotEmpty ?? false) ||
                (source.imageBytes?.isNotEmpty ?? false)) {
              return const CanonicalDisplayPublicationRejected(
                kind: CanonicalDisplayPublicationOutcomeKind.seamGap,
                message: 'Canonical publication skips readable ownership.',
              );
            }
          }
        }
      }
      previous = slice;
    }
    return null;
  }

  CanonicalDisplayPublicationRejected? _classifyCursorSeam(
    CanonicalPaginationCursor expected,
    CanonicalPaginationCursor actual,
  ) {
    if (expected.samePositionAs(actual)) return null;
    final comparison = _compareCursor(actual, expected);
    return CanonicalDisplayPublicationRejected(
      kind: comparison > 0
          ? CanonicalDisplayPublicationOutcomeKind.seamGap
          : CanonicalDisplayPublicationOutcomeKind.seamOverlap,
      message: 'Canonical seam cursors do not meet exactly.',
    );
  }

  int _compareCursor(
    CanonicalPaginationCursor first,
    CanonicalPaginationCursor second,
  ) {
    if (first.isLogicalEnd) return second.isLogicalEnd ? 0 : 1;
    if (second.isLogicalEnd) return -1;
    var comparison = first.sourceOrdinalHint.compareTo(
      second.sourceOrdinalHint,
    );
    if (comparison != 0) return comparison;
    comparison = first.tableRowIndex.compareTo(second.tableRowIndex);
    if (comparison != 0) return comparison;
    return first.textOffsetUtf16.compareTo(second.textOffsetUtf16);
  }

  CanonicalPaginationCursor _cardStartCursor(
    CanonicalFinalizedReaderCard card,
  ) {
    final slice = card.sourceSlices.first;
    return CanonicalPaginationCursor(
      kind: slice.tableRowStart != null
          ? (slice.tableRowStart == 0
                ? CanonicalPaginationCursorKind.wholeSource
                : CanonicalPaginationCursorKind.tableRow)
          : (slice.startUtf16 ?? 0) == 0
          ? CanonicalPaginationCursorKind.wholeSource
          : CanonicalPaginationCursorKind.sourceText,
      sourceIdentity: slice.sourceIdentity,
      sectionIdentity: slice.sectionIdentity,
      sourceOrdinalHint: slice.sourceOrdinalHint,
      textOffsetUtf16: slice.startUtf16 ?? 0,
      tableRowIndex: slice.tableRowStart ?? 0,
    );
  }

  CanonicalPaginationCursor _cardEndCursor(
    CanonicalFinalizedReaderCard card,
    CanonicalPaginationSourceSnapshot snapshot,
  ) {
    final slice = card.sourceSlices.last;
    final source = snapshot.resolveOrdinalSource(slice.sourceOrdinalHint);
    if (slice.tableRowEndExclusive != null &&
        slice.tableRowEndExclusive! < _tableRowCount(source)) {
      return CanonicalPaginationCursor(
        kind: CanonicalPaginationCursorKind.tableRow,
        sourceIdentity: slice.sourceIdentity,
        sectionIdentity: slice.sectionIdentity,
        sourceOrdinalHint: slice.sourceOrdinalHint,
        tableRowIndex: slice.tableRowEndExclusive!,
      );
    }
    if (slice.tableRowEndExclusive == null &&
        slice.endUtf16 != null &&
        slice.endUtf16! < (source.text?.length ?? 0)) {
      return CanonicalPaginationCursor(
        kind: CanonicalPaginationCursorKind.sourceText,
        sourceIdentity: slice.sourceIdentity,
        sectionIdentity: slice.sectionIdentity,
        sourceOrdinalHint: slice.sourceOrdinalHint,
        textOffsetUtf16: slice.endUtf16!,
      );
    }
    if (slice.sourceOrdinalHint + 1 < snapshot.sourceCount) {
      final next = snapshot.ownerAt(slice.sourceOrdinalHint + 1);
      return CanonicalPaginationCursor(
        kind: CanonicalPaginationCursorKind.wholeSource,
        sourceIdentity: next.sourceIdentity,
        sectionIdentity: next.sectionIdentity,
        sourceOrdinalHint: next.sourceOrdinalHint,
      );
    }
    return const CanonicalPaginationCursor.logicalEnd();
  }

  int _tableRowCount(BookChunk source) =>
      parseReaderContentBlocks(source.text ?? '')
          .where((block) => block.type == ReaderContentBlockType.table)
          .firstOrNull
          ?.table
          ?.rows
          .length ??
      0;

  bool _isAlreadyApplied(
    CanonicalDisplayPublicationOperation operation,
    List<CanonicalFinalizedReaderCard> existing,
    List<CanonicalFinalizedReaderCard> incoming,
  ) {
    if (operation == CanonicalDisplayPublicationOperation.initial ||
        operation == CanonicalDisplayPublicationOperation.replacement) {
      return _sameCardSequence(existing, incoming);
    }
    if (incoming.length > existing.length) return false;
    final offset = operation == CanonicalDisplayPublicationOperation.append
        ? existing.length - incoming.length
        : 0;
    return Iterable<int>.generate(incoming.length).every(
      (index) => _sameFinalizedCard(existing[offset + index], incoming[index]),
    );
  }

  _CanonicalDisplayCandidate _candidateFromAcceptedSnapshot(
    CanonicalDisplayPublicationRequest request,
  ) {
    final committed = request.committedCard;
    final committedIndex = committed == null
        ? null
        : _canonicalCards.indexWhere(
            (card) => _sameFinalizedCard(card, committed),
          );
    final targetIdentity = request.targetContainment?.cardIdentity;
    final targetIndex = targetIdentity == null
        ? null
        : _canonicalCards.indexWhere(
            (card) => card.identity.signature == targetIdentity.signature,
          );
    return _CanonicalDisplayCandidate(
      kind: CanonicalDisplayPublicationOutcomeKind.idempotentAlreadyApplied,
      ranges: _ranges,
      displayChunks: _displayChunks,
      displayToOriginal: _displayToOriginal,
      originalToDisplay: _originalToDisplay,
      canonicalCards: _canonicalCards,
      generationComplete: generationComplete,
      insertedBefore: 0,
      committedDisplayIndex: committedIndex,
      targetDisplayIndex: targetIndex,
      continuation: _acceptedCanonicalContinuation!,
    );
  }

  bool _boundaryOwnsCard(
    CanonicalPaginationFinalizedBoundary boundary,
    CanonicalFinalizedReaderCard card,
  ) =>
      boundary.kind == CanonicalPaginationBoundaryKind.finalizedCard &&
      canonicalJsonEncode(boundary.cardIdentity?.toJson()) ==
          canonicalJsonEncode(card.identity.toJson());

  bool _cursorBelongsToSnapshot(
    CanonicalPaginationCursor cursor,
    CanonicalPaginationSourceSnapshot snapshot,
  ) {
    if (cursor.isLogicalEnd) return true;
    final ordinal = snapshot.resolveOrdinal(
      sourceIdentity: cursor.sourceIdentity,
      ordinalHint: cursor.sourceOrdinalHint,
    );
    return ordinal != null &&
        snapshot.ownerAt(ordinal).sectionIdentity == cursor.sectionIdentity;
  }

  bool _sameStableCursorPosition(
    CanonicalPaginationCursor first,
    CanonicalPaginationCursor second,
  ) =>
      first.kind == second.kind &&
      first.sourceIdentity == second.sourceIdentity &&
      first.sectionIdentity == second.sectionIdentity &&
      first.textOffsetUtf16 == second.textOffsetUtf16 &&
      first.tableRowIndex == second.tableRowIndex;

  bool _sameStableFinalizedCard(
    CanonicalFinalizedReaderCard first,
    CanonicalFinalizedReaderCard second,
  ) =>
      canonicalJsonEncode(first.identity.toJson()) ==
          canonicalJsonEncode(second.identity.toJson()) &&
      canonicalBookChunkOwnershipDigest(first.card) ==
          canonicalBookChunkOwnershipDigest(second.card) &&
      canonicalJsonEncode(
            first.sourceSlices.map(_stableSliceProof).toList(growable: false),
          ) ==
          canonicalJsonEncode(
            second.sourceSlices.map(_stableSliceProof).toList(growable: false),
          );

  Map<String, Object?> _stableSliceProof(
    CanonicalPaginationSourceSlice slice,
  ) =>
      Map<String, Object?>.from(slice.toCanonicalJson())
        ..remove('sourceOrdinalHint');

  bool _sameFinalizedCard(
    CanonicalFinalizedReaderCard first,
    CanonicalFinalizedReaderCard second,
  ) =>
      canonicalJsonEncode(first.identity.toJson()) ==
          canonicalJsonEncode(second.identity.toJson()) &&
      canonicalJsonEncode(first.card.toJson()) ==
          canonicalJsonEncode(second.card.toJson()) &&
      canonicalJsonEncode(
            first.sourceSlices.map((slice) => slice.toCanonicalJson()).toList(),
          ) ==
          canonicalJsonEncode(
            second.sourceSlices
                .map((slice) => slice.toCanonicalJson())
                .toList(),
          );

  bool _sameCardSequence(
    List<CanonicalFinalizedReaderCard> first,
    List<CanonicalFinalizedReaderCard> second,
  ) =>
      first.length == second.length &&
      Iterable<int>.generate(
        first.length,
      ).every((index) => _sameFinalizedCard(first[index], second[index]));

  void _clearCanonicalAuthority() {
    _lazyPublication = null;
    _lazyVisibleCardSignature = null;
    _failedLazyAttempt = null;
    _canonicalCards = [];
    _acceptedCanonicalContinuation = null;
    _acceptedSourceSnapshot = null;
    _acceptedSessionIdentity = null;
    _acceptedLayoutIdentity = null;
    _acceptedPaginationIdentity = null;
    _canonicalCacheWriteAuthority = false;
  }

  void markRequest(DisplayRangeRequest request) {
    if (request.direction == DisplayRangeDirection.forward) {
      lookaheadRequest = request;
    } else {
      foregroundRequest = request;
    }
    failedRequest = null;
    failure = null;
  }

  void markFailure(DisplayRangeRequest request, Object error) {
    failedRequest = request;
    failure = error;
    if (foregroundRequest == request) foregroundRequest = null;
    if (lookaheadRequest == request) lookaheadRequest = null;
  }

  void cancelActiveRequests() {
    foregroundRequest = null;
    lookaheadRequest = null;
  }

  void shiftSourceIndexes(int delta) {
    if (delta == 0) return;
    ranges.replaceRange(0, ranges.length, [
      for (final range in ranges)
        PreparedDisplayRange(
          sourceRange: range.sourceRange.shift(delta),
          displayStart: range.displayStart,
          displayEndExclusive: range.displayEndExclusive,
        ),
    ]);
    for (var i = 0; i < displayToOriginal.length; i++) {
      displayToOriginal[i] = [
        for (final original in displayToOriginal[i]) original + delta,
      ];
    }
    final shiftedOriginalToDisplay = <int, int>{
      for (final entry in originalToDisplay.entries)
        entry.key + delta: entry.value,
    };
    originalToDisplay
      ..clear()
      ..addAll(shiftedOriginalToDisplay);
    for (var i = 0; i < displayChunks.length; i++) {
      displayChunks[i] = _shiftDisplayChunkSourceIndexes(
        displayChunks[i],
        delta,
      );
    }
  }

  void _updateCompletion() {
    generationComplete =
        ranges.isNotEmpty &&
        !externalUnavailableBefore &&
        !externalUnavailableAfter &&
        ranges.first.sourceRange.start == 0 &&
        ranges.last.sourceRange.endExclusive == sourceChunkCount;
  }

  void _assertResultSucceeded(DisplayRangeResult result) {
    if (!result.succeeded) {
      throw StateError('Cannot publish failed or cancelled display range');
    }
  }
}

final class _CanonicalDisplayCandidate {
  const _CanonicalDisplayCandidate({
    required this.kind,
    required this.ranges,
    required this.displayChunks,
    required this.displayToOriginal,
    required this.originalToDisplay,
    required this.canonicalCards,
    required this.generationComplete,
    required this.insertedBefore,
    required this.committedDisplayIndex,
    required this.targetDisplayIndex,
    required this.continuation,
  });

  final CanonicalDisplayPublicationOutcomeKind kind;
  final List<PreparedDisplayRange> ranges;
  final List<BookChunk> displayChunks;
  final List<List<int>> displayToOriginal;
  final Map<int, int> originalToDisplay;
  final List<CanonicalFinalizedReaderCard> canonicalCards;
  final bool generationComplete;
  final int insertedBefore;
  final int? committedDisplayIndex;
  final int? targetDisplayIndex;
  final CanonicalPaginationContinuation continuation;
}

BookChunk _shiftDisplayChunkSourceIndexes(BookChunk chunk, int delta) {
  final ranges = chunk.sourceRanges;
  if (ranges == null || ranges.isEmpty) {
    return chunk.copyWith(index: chunk.index + delta);
  }
  return chunk.copyWith(
    sourceRanges: [
      for (final range in ranges)
        ChunkSourceRange(
          originalChunkIndex: range.originalChunkIndex + delta,
          originalStartOffset: range.originalStartOffset,
          originalEndOffset: range.originalEndOffset,
          displayStartOffset: range.displayStartOffset,
          displayEndOffset: range.displayEndOffset,
          logicalParagraphId: range.logicalParagraphId,
          paragraphStartOffset: range.paragraphStartOffset,
          paragraphEndOffset: range.paragraphEndOffset,
          isParagraphStart: range.isParagraphStart,
          isParagraphEnd: range.isParagraphEnd,
        ),
    ],
  );
}
