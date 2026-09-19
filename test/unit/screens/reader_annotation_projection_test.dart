import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/book_list_semantics.dart';
import 'package:nalori/models/highlight.dart';
import 'package:nalori/models/stable_book_location.dart';
import 'package:nalori/screens/reader_screen.dart';

void main() {
  const publication = 'publication';
  const bookId = 'book.epub';
  const stable = StableBookLocation(
    bookId: bookId,
    spineIndex: 4,
    href: 'chapter-4.xhtml',
    sourceChecksum: 'checksum',
    publicationFingerprint: publication,
    normalizedHref: 'chapter-4.xhtml',
    localChunkIndex: 3,
    textOffset: 0,
    sourceParserVersion: 'section_v2',
  );

  Highlight annotation({
    String id = 'annotation',
    HighlightType type = HighlightType.highlight,
    int originalChunkIndex = 42,
    int startOffset = 0,
    int endOffset = 7,
    String text = 'McNeish',
  }) => Highlight(
    id: id,
    originalChunkIndex: originalChunkIndex,
    startOffset: startOffset,
    endOffset: endOffset,
    text: text,
    colorValue: Colors.teal.toARGB32(),
    type: type,
    createdAt: DateTime(2026, 7, 12),
    stableLocation: stable.copyWith(textOffset: startOffset),
  );

  const currentTargetWindow = <int, StableBookLocation>{
    0: StableBookLocation(
      bookId: bookId,
      spineIndex: 4,
      href: 'chapter-4.xhtml',
      sourceChecksum: 'checksum',
      publicationFingerprint: publication,
      normalizedHref: 'chapter-4.xhtml',
      localChunkIndex: 3,
      sourceParserVersion: 'section_v2',
    ),
  };

  test('stable annotation projects onto the current lazy-window index', () {
    final highlight = annotation();

    final resolved = resolveReaderHighlightsForSourceWindow(
      highlights: [highlight],
      locationsByChunkIndex: currentTargetWindow,
    );

    expect(resolved, hasLength(1));
    expect(resolved.single.id, highlight.id);
    expect(resolved.single.originalChunkIndex, 0);
    expect(resolved.single.stableLocation, highlight.stableLocation);
  });

  test('window replacement removes stale projection then restores target', () {
    final highlight = annotation();
    const unrelatedWindow = <int, StableBookLocation>{
      42: StableBookLocation(
        bookId: bookId,
        spineIndex: 1,
        href: 'chapter-1.xhtml',
        sourceChecksum: 'other',
        publicationFingerprint: publication,
        localChunkIndex: 3,
      ),
    };

    final before = resolveReaderHighlightsForSourceWindow(
      highlights: [highlight],
      locationsByChunkIndex: unrelatedWindow,
    );
    final after = resolveReaderHighlightsForSourceWindow(
      highlights: [highlight],
      locationsByChunkIndex: currentTargetWindow,
    );

    expect(before, isEmpty);
    expect(after.single.originalChunkIndex, 0);
  });

  test('stable projection resolves exact segment text after reindexing', () {
    final stored = Highlight(
      id: 'multi-range-note',
      originalChunkIndex: 42,
      startOffset: 0,
      endOffset: 7,
      text: 'unrelated whole display selection',
      colorValue: Colors.teal.toARGB32(),
      type: HighlightType.highlight,
      note: 'Remember this',
      createdAt: DateTime(2026, 7, 31),
      stableLocation: stable.copyWith(textOffset: 7),
    );

    final resolved = resolveReaderHighlightsForSourceWindow(
      highlights: <Highlight>[stored],
      locationsByChunkIndex: currentTargetWindow,
      sourceChunks: const <BookChunk>[
        BookChunk(
          index: 0,
          type: BookChunkType.text,
          text: 'prefix segment suffix',
        ),
      ],
    );

    expect(resolved.single.originalChunkIndex, 0);
    expect(resolved.single.startOffset, 7);
    expect(resolved.single.endOffset, 14);
    expect(resolved.single.text, 'segment');
    expect(resolved.single.note, 'Remember this');
  });

  test('migration projects one record without duplicate visual spans', () {
    final migrated = annotation(id: 'migrated-note', type: HighlightType.note);

    final resolved = resolveReaderHighlightsForSourceWindow(
      highlights: [migrated],
      locationsByChunkIndex: currentTargetWindow,
    );

    expect(resolved.map((entry) => entry.id), ['migrated-note']);
  });

  test('character span stays on source text instead of same-length text', () {
    const displayText = 'McNeish watches, and waits.';
    final character = annotation(type: HighlightType.character);
    final projected = resolveReaderHighlightsForSourceWindow(
      highlights: [character],
      locationsByChunkIndex: currentTargetWindow,
    ).single;
    const displayChunk = BookChunk(
      index: 99,
      type: BookChunkType.text,
      text: displayText,
      sourceRanges: [
        ChunkSourceRange(
          originalChunkIndex: 0,
          originalStartOffset: 0,
          originalEndOffset: displayText.length,
          displayStartOffset: 0,
          displayEndOffset: displayText.length,
        ),
      ],
    );

    final mapped = displayChunk.mapOriginalRangeToDisplay(
      projected.originalChunkIndex,
      projected.startOffset,
      projected.endOffset,
    );

    expect(mapped, hasLength(1));
    expect(
      displayText.substring(
        mapped.single.displayStartOffset,
        mapped.single.displayEndOffset,
      ),
      'McNeish',
    );
    expect(
      displayText.substring(
        displayText.indexOf('es, and'),
        displayText.indexOf('es, and') + 7,
      ),
      isNot('McNeish'),
    );
  });

  test(
    'legacy same-length span is not projected onto unrelated window text',
    () {
      final legacy = Highlight(
        id: 'legacy',
        originalChunkIndex: 0,
        startOffset: 0,
        endOffset: 7,
        text: 'McNeish',
        colorValue: Colors.teal.toARGB32(),
        type: HighlightType.character,
        createdAt: DateTime(2026, 7, 13),
      );
      const unrelated = BookChunk(
        index: 0,
        type: BookChunkType.text,
        text: 'Another unrelated paragraph.',
      );

      final resolved = resolveReaderHighlightsForSourceWindow(
        highlights: [legacy],
        locationsByChunkIndex: currentTargetWindow,
        sourceChunks: const [unrelated],
      );

      expect(resolved, isEmpty);
    },
  );

  test(
    'legacy annotation remains visible when exact source evidence matches',
    () {
      final legacy = Highlight(
        id: 'legacy-match',
        originalChunkIndex: 0,
        startOffset: 0,
        endOffset: 7,
        text: 'McNeish',
        colorValue: Colors.teal.toARGB32(),
        type: HighlightType.highlight,
        createdAt: DateTime(2026, 7, 13),
      );

      final resolved = resolveReaderHighlightsForSourceWindow(
        highlights: [legacy],
        locationsByChunkIndex: currentTargetWindow,
        sourceChunks: const [
          BookChunk(
            index: 0,
            type: BookChunkType.text,
            text: 'McNeish watches.',
          ),
        ],
      );

      expect(resolved.single.id, 'legacy-match');
    },
  );

  test('legacy marker-bearing list offset uses a unique body-text alias', () {
    final legacy = Highlight(
      id: 'legacy-list',
      originalChunkIndex: 0,
      startOffset: 3,
      endOffset: 6,
      text: 'Ada',
      createdAt: DateTime(2026, 8, 8),
    );
    const listSemantics = BookListSemantics(
      listId: 'chapter.xhtml#list-0',
      itemId: 'chapter.xhtml#list-0#item-0',
      ordered: true,
      depth: 0,
      markerType: BookListMarkerType.decimal,
      resolvedOrdinal: 4,
      orderedStart: 4,
      blockIndex: 0,
      beginsItem: true,
      endsItem: true,
    );

    final resolved = resolveReaderHighlightsForSourceWindow(
      highlights: [legacy],
      locationsByChunkIndex: currentTargetWindow,
      sourceChunks: const [
        BookChunk(index: 0, type: BookChunkType.text, text: 'Earlier prose.'),
        BookChunk(
          index: 1,
          type: BookChunkType.text,
          text: 'Ada reads.',
          listSemantics: listSemantics,
        ),
      ],
    );

    expect(resolved, hasLength(1));
    expect(resolved.single.originalChunkIndex, 1);
    expect(resolved.single.startOffset, 0);
    expect(resolved.single.endOffset, 3);
  });

  test('legacy list alias refuses ambiguous duplicate body text', () {
    final legacy = Highlight(
      id: 'ambiguous-list',
      originalChunkIndex: 0,
      startOffset: 3,
      endOffset: 6,
      text: 'Ada',
      createdAt: DateTime(2026, 8, 8),
    );
    const first = BookListSemantics(
      listId: 'list',
      itemId: 'item-0',
      ordered: true,
      depth: 0,
      markerType: BookListMarkerType.decimal,
      resolvedOrdinal: 4,
      orderedStart: 4,
      blockIndex: 0,
      beginsItem: true,
      endsItem: true,
    );
    const second = BookListSemantics(
      listId: 'list',
      itemId: 'item-1',
      ordered: true,
      depth: 0,
      markerType: BookListMarkerType.decimal,
      resolvedOrdinal: 5,
      orderedStart: 4,
      blockIndex: 0,
      beginsItem: true,
      endsItem: true,
    );

    final resolved = resolveReaderHighlightsForSourceWindow(
      highlights: [legacy],
      locationsByChunkIndex: currentTargetWindow,
      sourceChunks: const [
        BookChunk(
          index: 0,
          type: BookChunkType.text,
          text: 'Ada reads.',
          listSemantics: first,
        ),
        BookChunk(
          index: 1,
          type: BookChunkType.text,
          text: 'Ada returns.',
          listSemantics: second,
        ),
      ],
    );

    expect(resolved, isEmpty);
  });
}
