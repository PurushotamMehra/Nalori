import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
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
}
