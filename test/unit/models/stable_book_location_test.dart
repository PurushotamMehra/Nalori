import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_metadata.dart';
import 'package:nalori/models/bookmark.dart';
import 'package:nalori/models/highlight.dart';
import 'package:nalori/models/position_history.dart';
import 'package:nalori/models/saved_word.dart';
import 'package:nalori/models/stable_book_location.dart';

void main() {
  const location = StableBookLocation(
    bookId: 'book.epub',
    spineIndex: 3,
    href: 'text/chapter.xhtml',
    sourceChecksum: 'abc123',
    localChunkIndex: 7,
    textOffset: 12,
    anchorId: 'chapter',
    contextText: 'nearby text',
    legacyGlobalChunkIndex: 42,
    localDisplayIndex: 5,
    readerLayoutFingerprint: 'layout-v1',
    previousSpineIndex: 2,
    nextSpineIndex: 4,
    publicationFingerprint: 'publication-v2',
    normalizedHref: 'text/chapter.xhtml',
    sectionProgression: 0.4,
    publicationProgression: 0.6,
    sourceParserVersion: 'lazy-section-v1',
  );

  test('stable book location round trips through JSON', () {
    final decoded = StableBookLocation.fromJson(location.toJson());

    expect(decoded, location);
    expect(decoded.hasExactLocalTarget, isTrue);
  });

  test(
    'legacy bookmark JSON remains readable and stable location is additive',
    () {
      final legacy = Bookmark.fromJson({
        'chunkIndex': 42,
        'originalStartOffset': 12,
        'name': 'Legacy',
        'createdAt': DateTime(2026).toIso8601String(),
      });
      final migrated = legacy.copyWith(stableLocation: location);
      final decoded = Bookmark.fromJson(migrated.toJson());

      expect(legacy.stableLocation, isNull);
      expect(decoded.chunkIndex, 42);
      expect(decoded.originalStartOffset, 12);
      expect(decoded.stableLocation, location);
    },
  );

  test('highlight, saved word and history preserve legacy fields', () {
    final highlight = Highlight(
      id: 'h1',
      originalChunkIndex: 42,
      startOffset: 12,
      endOffset: 18,
      text: 'sample',
      createdAt: DateTime(2026),
      stableLocation: location,
    );
    final word = SavedWord(
      id: 'w1',
      word: 'sample',
      meaning: 'definition',
      bookId: 'book.epub',
      timestamp: DateTime(2026).millisecondsSinceEpoch,
      originalChunkIndex: 42,
      originalStartOffset: 12,
      originalEndOffset: 18,
      stableLocation: location,
    );
    final history = PositionHistory(
      chunkIndex: 42,
      displayIndex: 5,
      label: 'Page 6',
      stableLocation: location,
    );

    expect(
      Highlight.decodeList(
        Highlight.encodeList([highlight]),
      ).single.stableLocation,
      location,
    );
    expect(SavedWord.fromJson(word.toJson()).stableLocation, location);
    expect(PositionHistory.fromMap(history.toMap()).stableLocation, location);
  });

  test(
    'book metadata stores stable last-read location without dropping index',
    () {
      final metadata = BookMetadata(
        id: 'book.epub',
        title: 'Book',
        author: 'Author',
        lastReadIndex: 42,
        lastReadLocation: location,
      );
      final decoded = BookMetadata.fromJson(metadata.toJson());

      expect(decoded.lastReadIndex, 42);
      expect(decoded.lastReadLocation, location);
    },
  );
}
