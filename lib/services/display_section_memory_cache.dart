import '../models/book_chunk.dart';
import 'progressive_display_state.dart';

final class DisplaySectionMemoryCacheKey {
  const DisplaySectionMemoryCacheKey({
    required this.cacheKey,
    required this.sourceRange,
  });

  final String cacheKey;
  final SourceChunkRange sourceRange;

  @override
  bool operator ==(Object other) {
    return other is DisplaySectionMemoryCacheKey &&
        other.cacheKey == cacheKey &&
        other.sourceRange.start == sourceRange.start &&
        other.sourceRange.endExclusive == sourceRange.endExclusive;
  }

  @override
  int get hashCode =>
      Object.hash(cacheKey, sourceRange.start, sourceRange.endExclusive);
}

final class DisplaySectionMemoryCacheEntry {
  const DisplaySectionMemoryCacheEntry({
    required this.key,
    required this.displayChunks,
    required this.displayToOriginal,
    required this.originalToDisplay,
    required this.estimatedBytes,
  });

  final DisplaySectionMemoryCacheKey key;
  final List<BookChunk> displayChunks;
  final List<List<int>> displayToOriginal;
  final Map<int, int> originalToDisplay;
  final int estimatedBytes;

  DisplayRangeResult toResult({
    required DisplayRangeDirection direction,
    required int generationId,
    required String reason,
    int? targetOriginalIndex,
  }) {
    return DisplayRangeResult(
      request: DisplayRangeRequest(
        direction: direction,
        sourceRange: key.sourceRange,
        generationId: generationId,
        reason: reason,
        targetOriginalIndex: targetOriginalIndex,
      ),
      displayChunks: displayChunks,
      displayToOriginal: displayToOriginal,
      originalToDisplay: originalToDisplay,
      inspectedSourceChunks: key.sourceRange.length,
      elapsedMilliseconds: 0,
    );
  }
}

final class DisplaySectionMemoryCache {
  DisplaySectionMemoryCache({int byteBudget = 8 * 1024 * 1024})
    : _byteBudget = byteBudget;

  final int _byteBudget;
  final _entries =
      <DisplaySectionMemoryCacheKey, DisplaySectionMemoryCacheEntry>{};
  final _pins = <DisplaySectionMemoryCacheKey>{};
  int _estimatedBytes = 0;

  int get estimatedBytes => _estimatedBytes;
  int get entryCount => _entries.length;
  Iterable<DisplaySectionMemoryCacheKey> get keys => _entries.keys;

  DisplaySectionMemoryCacheEntry? get(DisplaySectionMemoryCacheKey key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    _entries[key] = entry;
    return entry;
  }

  void put({
    required String cacheKey,
    required DisplayRangeResult result,
    bool pinned = false,
  }) {
    if (!result.succeeded || result.displayChunks.isEmpty) return;
    final key = DisplaySectionMemoryCacheKey(
      cacheKey: cacheKey,
      sourceRange: result.request.sourceRange,
    );
    final existing = _entries.remove(key);
    if (existing != null) _estimatedBytes -= existing.estimatedBytes;
    final entry = DisplaySectionMemoryCacheEntry(
      key: key,
      displayChunks: List<BookChunk>.of(result.displayChunks),
      displayToOriginal: result.displayToOriginal.map(List<int>.of).toList(),
      originalToDisplay: Map<int, int>.of(result.originalToDisplay),
      estimatedBytes: _estimateResultBytes(result),
    );
    _entries[key] = entry;
    _estimatedBytes += entry.estimatedBytes;
    if (pinned) _pins.add(key);
    _evictUntilWithinBudget();
  }

  void pinPreparedRanges(String cacheKey, Iterable<SourceChunkRange> ranges) {
    _pins
      ..clear()
      ..addAll(
        ranges.map(
          (range) => DisplaySectionMemoryCacheKey(
            cacheKey: cacheKey,
            sourceRange: range,
          ),
        ),
      );
    _evictUntilWithinBudget();
  }

  void clear() {
    _entries.clear();
    _pins.clear();
    _estimatedBytes = 0;
  }

  void _evictUntilWithinBudget() {
    while (_estimatedBytes > _byteBudget && _entries.isNotEmpty) {
      final evictable = _entries.keys
          .cast<DisplaySectionMemoryCacheKey?>()
          .firstWhere(
            (key) => key != null && !_pins.contains(key),
            orElse: () => null,
          );
      if (evictable == null) break;
      final removed = _entries.remove(evictable);
      if (removed != null) _estimatedBytes -= removed.estimatedBytes;
    }
  }

  int _estimateResultBytes(DisplayRangeResult result) {
    var bytes = 1024;
    bytes += result.displayToOriginal.fold<int>(
      0,
      (sum, originals) => sum + originals.length * 8,
    );
    bytes += result.originalToDisplay.length * 16;
    for (final chunk in result.displayChunks) {
      bytes += 128;
      bytes += (chunk.text?.length ?? 0) * 2;
      bytes += chunk.imageBytes?.length ?? 0;
      bytes += (chunk.links?.length ?? 0) * 48;
      bytes += (chunk.inlineStyles?.length ?? 0) * 24;
      bytes += (chunk.footnotes?.length ?? 0) * 96;
      bytes += (chunk.sourceRanges?.length ?? 0) * 40;
    }
    return bytes;
  }
}
