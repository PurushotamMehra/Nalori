import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/services/display_generation_coordinator.dart';
import 'package:nalori/services/progressive_display_state.dart';

void main() {
  DisplayGenerationSignature signature() {
    return const DisplayGenerationSignature(
      bookId: 'book',
      parsedContentVersion: 4,
      layoutSignature: 'v11',
      settingsSignature: 'settings',
      viewportSignature: 'viewport',
      cacheKey: 'cache',
    );
  }

  BookChunk chunk(int index, String text) {
    return BookChunk(index: index, type: BookChunkType.text, text: text);
  }

  DisplayRangeResult result({
    required DisplayRangeDirection direction,
    required int start,
    required int end,
    required int generationId,
    required List<BookChunk> displayChunks,
    required List<List<int>> displayToOriginal,
    required Map<int, int> originalToDisplay,
  }) {
    return DisplayRangeResult(
      request: DisplayRangeRequest(
        direction: direction,
        sourceRange: SourceChunkRange(start, end),
        generationId: generationId,
        reason: 'test',
      ),
      displayChunks: displayChunks,
      displayToOriginal: displayToOriginal,
      originalToDisplay: originalToDisplay,
      inspectedSourceChunks: end - start,
      elapsedMilliseconds: 1,
    );
  }

  test(
    'initial range is bounded around target and does not know final count',
    () {
      final state = ProgressiveDisplayState(
        signature: signature(),
        sourceChunkCount: 1000,
      );

      final range = state.initialSourceRange(
        targetOriginalIndex: 500,
        lookBehind: 32,
        lookAhead: 128,
        minimumWindow: 192,
      );

      expect(range.start, 468);
      expect(range.endExclusive, 660);
      expect(state.finalDisplayCountKnown, isFalse);
    },
  );

  test('publishes initial prepared range with mappings', () {
    final state = ProgressiveDisplayState(
      signature: signature(),
      sourceChunkCount: 20,
    );

    state.publishInitial(
      result(
        direction: DisplayRangeDirection.initial,
        start: 5,
        end: 9,
        generationId: 1,
        displayChunks: [chunk(5, 'five'), chunk(7, 'seven eight')],
        displayToOriginal: [
          [5, 6],
          [7, 8],
        ],
        originalToDisplay: {5: 0, 6: 0, 7: 1, 8: 1},
      ),
    );

    expect(state.initialWindowReady, isTrue);
    expect(state.hasUnavailableBefore, isTrue);
    expect(state.hasUnavailableAfter, isTrue);
    expect(state.displayIndexForSource(8), 1);
    expect(state.displayChunks, hasLength(2));
    expect(state.finalDisplayCountKnown, isFalse);
  });

  test('external lazy content keeps covered local window incomplete', () {
    final state =
        ProgressiveDisplayState(signature: signature(), sourceChunkCount: 8)
          ..externalUnavailableBefore = true
          ..externalUnavailableAfter = true;

    state.publishInitial(
      result(
        direction: DisplayRangeDirection.initial,
        start: 0,
        end: 8,
        generationId: 1,
        displayChunks: [chunk(0, 'loaded section')],
        displayToOriginal: [
          [0, 1, 2, 3, 4, 5, 6, 7],
        ],
        originalToDisplay: {
          for (var sourceIndex = 0; sourceIndex < 8; sourceIndex++)
            sourceIndex: 0,
        },
      ),
    );

    expect(state.hasUnavailableBefore, isTrue);
    expect(state.hasUnavailableAfter, isTrue);
    expect(state.finalDisplayCountKnown, isFalse);
  });

  test('appends adjacent range and shifts local mappings', () {
    final state = ProgressiveDisplayState(
      signature: signature(),
      sourceChunkCount: 12,
    );

    state.publishInitial(
      result(
        direction: DisplayRangeDirection.initial,
        start: 3,
        end: 6,
        generationId: 1,
        displayChunks: [chunk(3, 'three')],
        displayToOriginal: [
          [3, 4, 5],
        ],
        originalToDisplay: {3: 0, 4: 0, 5: 0},
      ),
    );

    final added = state.append(
      result(
        direction: DisplayRangeDirection.forward,
        start: 6,
        end: 9,
        generationId: 2,
        displayChunks: [chunk(6, 'six'), chunk(8, 'eight')],
        displayToOriginal: [
          [6, 7],
          [8],
        ],
        originalToDisplay: {6: 0, 7: 0, 8: 1},
      ),
    );

    expect(added, 2);
    expect(state.displayChunks, hasLength(3));
    expect(state.displayIndexForSource(6), 1);
    expect(state.displayIndexForSource(8), 2);
    expect(state.preparedSourceRange.toString(), '[3,9)');
  });

  test('prepends adjacent range and preserves existing source mappings', () {
    final state = ProgressiveDisplayState(
      signature: signature(),
      sourceChunkCount: 12,
    );

    state.publishInitial(
      result(
        direction: DisplayRangeDirection.initial,
        start: 6,
        end: 9,
        generationId: 1,
        displayChunks: [chunk(6, 'six'), chunk(8, 'eight')],
        displayToOriginal: [
          [6, 7],
          [8],
        ],
        originalToDisplay: {6: 0, 7: 0, 8: 1},
      ),
    );

    final inserted = state.prepend(
      result(
        direction: DisplayRangeDirection.backward,
        start: 3,
        end: 6,
        generationId: 2,
        displayChunks: [chunk(3, 'three')],
        displayToOriginal: [
          [3, 4, 5],
        ],
        originalToDisplay: {3: 0, 4: 0, 5: 0},
      ),
    );

    expect(inserted, 1);
    expect(state.displayIndexForSource(3), 0);
    expect(state.displayIndexForSource(6), 1);
    expect(state.displayIndexForSource(8), 2);
    expect(state.preparedSourceRange.toString(), '[3,9)');
  });

  test('shifts prepared source indexes after lazy prepend', () {
    final state = ProgressiveDisplayState(
      signature: signature(),
      sourceChunkCount: 10,
    );
    state.publishInitial(
      result(
        direction: DisplayRangeDirection.initial,
        start: 0,
        end: 10,
        generationId: 1,
        displayChunks: [
          BookChunk(
            index: 0,
            type: BookChunkType.text,
            text: 'Current',
            sourceRanges: const [
              ChunkSourceRange(
                originalChunkIndex: 0,
                originalStartOffset: 0,
                originalEndOffset: 7,
                displayStartOffset: 0,
                displayEndOffset: 7,
              ),
            ],
          ),
        ],
        displayToOriginal: [
          [0],
        ],
        originalToDisplay: {0: 0},
      ),
    );

    state.shiftSourceIndexes(3);

    expect(state.ranges.single.sourceRange.toString(), '[3,13)');
    expect(state.displayToOriginal.single, [3]);
    expect(state.originalToDisplay, {3: 0});
    expect(
      state.displayChunks.single.sourceRanges!.single.originalChunkIndex,
      3,
    );
  });

  test('rejects non-adjacent append to prevent hidden gaps', () {
    final state = ProgressiveDisplayState(
      signature: signature(),
      sourceChunkCount: 12,
    );

    state.publishInitial(
      result(
        direction: DisplayRangeDirection.initial,
        start: 3,
        end: 6,
        generationId: 1,
        displayChunks: [chunk(3, 'three')],
        displayToOriginal: [
          [3, 4, 5],
        ],
        originalToDisplay: {3: 0, 4: 0, 5: 0},
      ),
    );

    expect(
      () => state.append(
        result(
          direction: DisplayRangeDirection.forward,
          start: 7,
          end: 9,
          generationId: 2,
          displayChunks: [chunk(7, 'seven')],
          displayToOriginal: [
            [7, 8],
          ],
          originalToDisplay: {7: 0, 8: 0},
        ),
      ),
      throwsStateError,
    );
  });

  test('boundary thresholds request expansion near prepared edges only', () {
    final state = ProgressiveDisplayState(
      signature: signature(),
      sourceChunkCount: 20,
    );

    state.publishInitial(
      result(
        direction: DisplayRangeDirection.initial,
        start: 5,
        end: 10,
        generationId: 1,
        displayChunks: List.generate(8, (index) => chunk(index, '$index')),
        displayToOriginal: List.generate(8, (index) => [index + 5]),
        originalToDisplay: {for (var i = 0; i < 8; i++) i + 5: i},
      ),
    );

    expect(
      state.shouldRequestForward(currentDisplayIndex: 1, threshold: 2),
      isFalse,
    );
    expect(
      state.shouldRequestForward(currentDisplayIndex: 6, threshold: 2),
      isTrue,
    );
    expect(state.shouldRequestBackward(currentDisplayIndex: 4), isFalse);
    expect(state.shouldRequestBackward(currentDisplayIndex: 1), isTrue);
  });

  test('eviction remap preserves stable card text and source boundaries', () {
    const currentText = 'Current card stays exactly split here';
    final snapshot = remapPreparedDisplaySnapshot(
      displayChunks: [
        chunk(0, 'evicted'),
        const BookChunk(
          index: 1,
          type: BookChunkType.text,
          text: currentText,
          sourceRanges: [
            ChunkSourceRange(
              originalChunkIndex: 1,
              originalStartOffset: 40,
              originalEndOffset: 77,
              displayStartOffset: 0,
              displayEndOffset: 37,
            ),
          ],
        ),
        chunk(2, 'next retained card'),
      ],
      displayToOriginal: const [
        [0],
        [1],
        [2],
      ],
      oldStableKeysBySourceIndex: const {0: 'A0', 1: 'B0', 2: 'B1'},
      newSourceIndexByStableKey: const {'B0': 0, 'B1': 1, 'C0': 2},
      preparedOldSourceIndexes: const [0, 1, 2],
      anchorStableKey: 'B0',
    );

    expect(snapshot, isNotNull);
    expect(snapshot!.sourceRange.toString(), '[0,2)');
    expect(snapshot.displayChunks.map((entry) => entry.text), [
      currentText,
      'next retained card',
    ]);
    final currentRange = snapshot.displayChunks.first.sourceRanges!.single;
    expect(currentRange.originalChunkIndex, 0);
    expect(currentRange.originalStartOffset, 40);
    expect(currentRange.originalEndOffset, 77);
    expect(snapshot.anchorDisplayIndex, 0);
    expect(snapshot.originalToDisplay, {0: 0, 1: 1});
  });

  test('eviction remap cannot retain stale or gapped display cards', () {
    final snapshot = remapPreparedDisplaySnapshot(
      displayChunks: [
        chunk(0, 'retained'),
        chunk(1, 'gap'),
        chunk(2, 'anchor'),
      ],
      displayToOriginal: const [
        [0],
        [1],
        [2],
      ],
      oldStableKeysBySourceIndex: const {0: 'B0', 1: 'X0', 2: 'B2'},
      newSourceIndexByStableKey: const {'B0': 4, 'B2': 6},
      preparedOldSourceIndexes: const [0, 1, 2],
      anchorStableKey: 'B2',
    );

    expect(snapshot, isNotNull);
    expect(snapshot!.sourceRange.toString(), '[6,7)');
    expect(snapshot.displayChunks.single.text, 'anchor');
    expect(snapshot.displayToOriginal, const [
      [6],
    ]);
  });

  test('repeated window remaps do not duplicate skip or reorder text', () {
    final first = remapPreparedDisplaySnapshot(
      displayChunks: [chunk(0, 'B0'), chunk(1, 'B1')],
      displayToOriginal: const [
        [0],
        [1],
      ],
      oldStableKeysBySourceIndex: const {0: 'B0', 1: 'B1'},
      newSourceIndexByStableKey: const {'B0': 2, 'B1': 3},
      preparedOldSourceIndexes: const [0, 1],
      anchorStableKey: 'B0',
    );
    final second = remapPreparedDisplaySnapshot(
      displayChunks: first!.displayChunks,
      displayToOriginal: first.displayToOriginal,
      oldStableKeysBySourceIndex: const {2: 'B0', 3: 'B1'},
      newSourceIndexByStableKey: const {'B0': 1, 'B1': 2},
      preparedOldSourceIndexes: const [2, 3],
      anchorStableKey: 'B0',
    );

    expect(second, isNotNull);
    expect(second!.displayChunks.map((entry) => entry.text), ['B0', 'B1']);
    expect(second.displayToOriginal, const [
      [1],
      [2],
    ]);
    expect(second.originalToDisplay, {1: 0, 2: 1});
  });
}
