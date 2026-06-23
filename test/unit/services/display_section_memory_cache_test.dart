import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/services/display_section_memory_cache.dart';
import 'package:nalori/services/progressive_display_state.dart';

void main() {
  DisplayRangeResult result({
    required int start,
    required int end,
    required String text,
  }) {
    return DisplayRangeResult(
      request: DisplayRangeRequest(
        direction: DisplayRangeDirection.forward,
        sourceRange: SourceChunkRange(start, end),
        generationId: 1,
        reason: 'test',
      ),
      displayChunks: [
        BookChunk(index: start, type: BookChunkType.text, text: text),
      ],
      displayToOriginal: [
        [start],
      ],
      originalToDisplay: {start: 0},
      inspectedSourceChunks: end - start,
      elapsedMilliseconds: 1,
    );
  }

  test('returns layout-compatible exact range without disk work', () {
    final cache = DisplaySectionMemoryCache();
    final range = result(start: 0, end: 10, text: 'cached display text');
    cache.put(cacheKey: 'layout-a', result: range);

    final hit = cache.get(
      const DisplaySectionMemoryCacheKey(
        cacheKey: 'layout-a',
        sourceRange: SourceChunkRange(0, 10),
      ),
    );

    expect(hit, isNotNull);
    expect(hit!.displayChunks.single.text, 'cached display text');
  });

  test('does not reuse ranges across layout cache keys', () {
    final cache = DisplaySectionMemoryCache();
    cache.put(
      cacheKey: 'layout-a',
      result: result(start: 0, end: 10, text: 'layout a'),
    );

    final miss = cache.get(
      const DisplaySectionMemoryCacheKey(
        cacheKey: 'layout-b',
        sourceRange: SourceChunkRange(0, 10),
      ),
    );

    expect(miss, isNull);
  });

  test('evicts least recently used unpinned range under budget pressure', () {
    final cache = DisplaySectionMemoryCache(byteBudget: 1800);
    cache.put(
      cacheKey: 'layout-a',
      result: result(start: 0, end: 10, text: _repeat('a', 120)),
    );
    cache.put(
      cacheKey: 'layout-a',
      result: result(start: 10, end: 20, text: _repeat('b', 120)),
      pinned: true,
    );
    cache.put(
      cacheKey: 'layout-a',
      result: result(start: 20, end: 30, text: _repeat('c', 120)),
    );

    expect(
      cache.get(
        const DisplaySectionMemoryCacheKey(
          cacheKey: 'layout-a',
          sourceRange: SourceChunkRange(10, 20),
        ),
      ),
      isNotNull,
    );
    expect(cache.entryCount, lessThan(3));
  });
}

String _repeat(String value, int count) => List.filled(count, value).join();
