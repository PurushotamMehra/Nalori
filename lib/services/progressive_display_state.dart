import '../models/book_chunk.dart';
import 'display_generation_coordinator.dart';

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
  });

  final DisplayRangeDirection direction;
  final SourceChunkRange sourceRange;
  final int generationId;
  final String reason;
  final int? targetOriginalIndex;
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
  final List<PreparedDisplayRange> ranges = [];
  final List<BookChunk> displayChunks = [];
  final List<List<int>> displayToOriginal = [];
  final Map<int, int> originalToDisplay = {};
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
      (ranges.isNotEmpty && ranges.first.sourceRange.start > 0);
  bool get hasUnavailableAfter =>
      externalUnavailableAfter ||
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
    final start = ranges.last.sourceRange.endExclusive;
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
    return inserted;
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
        ),
    ],
  );
}
