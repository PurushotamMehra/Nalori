import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/bookmark.dart';
import 'package:nalori/models/stable_book_location.dart';
import 'package:nalori/services/lazy_parsed_book.dart';
import 'package:nalori/services/reader_source_projection_service.dart';
import 'package:nalori/services/reader_structural_progress_service.dart';

void main() {
  const bookId = 'book.epub';
  const publication = 'publication-v1';
  const parser = 'section-v2';

  StableBookLocation location({
    required int spine,
    required String href,
    required String checksum,
    required int localChunk,
    int textOffset = 0,
  }) {
    return StableBookLocation(
      bookId: bookId,
      spineIndex: spine,
      href: href,
      normalizedHref: href,
      sourceChecksum: checksum,
      sourceParserVersion: parser,
      publicationFingerprint: publication,
      localChunkIndex: localChunk,
      textOffset: textOffset,
    );
  }

  LazySourceChunkIdentity identity(StableBookLocation location) {
    return LazySourceChunkIdentity(
      section: LazySectionIdentity(
        bookId: location.bookId,
        publicationFingerprint: location.publicationFingerprint!,
        spineIndex: location.spineIndex,
        href: location.href,
        normalizedHref: location.normalizedHref!,
        fullPath: location.normalizedHref!,
        sourceChecksum: location.sourceChecksum,
        parserVersion: location.sourceParserVersion!,
        dependencySignature: 'dependencies',
        dependencySchemaVersion: 1,
      ),
      localChunkIndex: location.localChunkIndex!,
    );
  }

  BookChunk displayChunk({
    required int sourceIndex,
    required int sourceStart,
    required int sourceEnd,
    String text = 'Repeated display text',
  }) {
    return BookChunk(
      index: sourceIndex,
      type: BookChunkType.text,
      text: text,
      sourceRanges: <ChunkSourceRange>[
        ChunkSourceRange(
          originalChunkIndex: sourceIndex,
          originalStartOffset: sourceStart,
          originalEndOffset: sourceEnd,
          displayStartOffset: 0,
          displayEndOffset: text.length,
        ),
      ],
    );
  }

  group('exact layout restore', () {
    final sourceLocation = location(
      spine: 2,
      href: 'chapter-2.xhtml',
      checksum: 'chapter-2-checksum',
      localChunk: 4,
    );
    final locations = <int, StableBookLocation>{7: sourceLocation};
    final identities = <int, LazySourceChunkIdentity>{
      7: identity(sourceLocation),
    };

    test('font family reflow preserves the exact source offset', () {
      final oldCards = <BookChunk>[
        displayChunk(sourceIndex: 7, sourceStart: 0, sourceEnd: 40),
        displayChunk(sourceIndex: 7, sourceStart: 40, sourceEnd: 85),
      ];
      final captured = readerStableLocationForDisplayIndex(
        displayIndex: 1,
        displayChunks: oldCards,
        displayToOriginal: const <List<int>>[
          <int>[7],
          <int>[7],
        ],
        locationsByChunkIndex: locations,
      );
      expect(captured?.textOffset, 40);

      final rebuiltCards = <BookChunk>[
        displayChunk(sourceIndex: 7, sourceStart: 0, sourceEnd: 25),
        displayChunk(sourceIndex: 7, sourceStart: 25, sourceEnd: 50),
        displayChunk(sourceIndex: 7, sourceStart: 50, sourceEnd: 85),
      ];
      expect(
        readerDisplayIndexForStableLocation(
          location: captured!,
          displayChunks: rebuiltCards,
          locationsByChunkIndex: locations,
          sourceIdentitiesByChunkIndex: identities,
        ),
        1,
      );
    });

    for (final layoutChange in <String>[
      'font size',
      'side margins',
      'density',
      'orientation signature',
    ]) {
      test(
        '$layoutChange reflow follows source text across new boundaries',
        () {
          final target = sourceLocation.copyWith(textOffset: 63);
          final rebuiltCards = <BookChunk>[
            displayChunk(sourceIndex: 7, sourceStart: 0, sourceEnd: 32),
            displayChunk(sourceIndex: 7, sourceStart: 32, sourceEnd: 58),
            displayChunk(sourceIndex: 7, sourceStart: 58, sourceEnd: 90),
          ];
          expect(
            readerDisplayIndexForStableLocation(
              location: target,
              displayChunks: rebuiltCards,
              locationsByChunkIndex: locations,
              sourceIdentitiesByChunkIndex: identities,
            ),
            2,
          );
        },
      );
    }

    test('repeated display text cannot override the stable source offset', () {
      final target = sourceLocation.copyWith(textOffset: 70);
      final rebuiltCards = <BookChunk>[
        displayChunk(sourceIndex: 7, sourceStart: 0, sourceEnd: 30),
        displayChunk(sourceIndex: 7, sourceStart: 30, sourceEnd: 60),
        displayChunk(sourceIndex: 7, sourceStart: 60, sourceEnd: 90),
      ];
      expect(rebuiltCards.map((chunk) => chunk.text).toSet(), hasLength(1));
      expect(
        readerDisplayIndexForStableLocation(
          location: target,
          displayChunks: rebuiltCards,
          locationsByChunkIndex: locations,
          sourceIdentitiesByChunkIndex: identities,
        ),
        2,
      );
    });

    test('card boundaries use half-open source ranges', () {
      final cards = <BookChunk>[
        displayChunk(sourceIndex: 7, sourceStart: 0, sourceEnd: 40),
        displayChunk(sourceIndex: 7, sourceStart: 40, sourceEnd: 85),
      ];

      expect(
        readerDisplayIndexForStableLocation(
          location: sourceLocation.copyWith(textOffset: 40),
          displayChunks: cards,
          locationsByChunkIndex: locations,
          sourceIdentitiesByChunkIndex: identities,
        ),
        1,
      );
    });

    test('captured source location survives lazy-window replacement', () async {
      final originalCards = <BookChunk>[
        displayChunk(sourceIndex: 7, sourceStart: 0, sourceEnd: 40),
        displayChunk(sourceIndex: 7, sourceStart: 40, sourceEnd: 85),
      ];
      final captured = readerStableLocationForDisplayIndex(
        displayIndex: 1,
        displayChunks: originalCards,
        displayToOriginal: const <List<int>>[
          <int>[7],
          <int>[7],
        ],
        locationsByChunkIndex: locations,
      );
      final queue = ReaderPositionPersistenceQueue()
        ..stage(
          ReaderCommittedPosition(
            revision: 1,
            displayIndex: 1,
            originalIndex: 7,
            location: captured,
          ),
        );

      final replacementLocation = location(
        spine: 8,
        href: 'chapter-8.xhtml',
        checksum: 'replacement-checksum',
        localChunk: 0,
      );
      final replacementCards = <BookChunk>[
        displayChunk(sourceIndex: 0, sourceStart: 0, sourceEnd: 25),
      ];

      expect(replacementCards, hasLength(1));
      expect(replacementLocation.spineIndex, 8);
      ReaderCommittedPosition? persisted;
      await queue.flush((position) async => persisted = position);
      expect(persisted?.location?.spineIndex, 2);
      expect(persisted?.location?.localChunkIndex, 4);
      expect(persisted?.location?.textOffset, 40);
    });
  });

  group('bookmark projection', () {
    final target = location(
      spine: 5,
      href: 'chapter-5.xhtml',
      checksum: 'target-checksum',
      localChunk: 3,
      textOffset: 6,
    );
    final unrelated = location(
      spine: 1,
      href: 'chapter-1.xhtml',
      checksum: 'other-checksum',
      localChunk: 3,
    );

    Bookmark stableBookmark({int legacyChunkIndex = 0}) => Bookmark(
      chunkIndex: legacyChunkIndex,
      originalStartOffset: 0,
      name: 'Bookmark 1',
      previewText: 'target passage',
      stableLocation: target,
      createdAt: DateTime(2026, 7, 31),
    );

    test('bookmark follows its stable source after window reindexing', () {
      final projected = resolveReaderBookmarksForSourceWindow(
        bookmarks: <Bookmark>[stableBookmark(legacyChunkIndex: 42)],
        sourceChunks: const <BookChunk>[
          BookChunk(
            index: 0,
            type: BookChunkType.text,
            text: 'xxxxxxTarget passage in the new window.',
          ),
        ],
        locationsByChunkIndex: <int, StableBookLocation>{0: target},
        sourceIdentitiesByChunkIndex: <int, LazySourceChunkIdentity>{
          0: identity(target),
        },
      );
      expect(projected.single.chunkIndex, 0);
      expect(projected.single.originalStartOffset, 6);
    });

    test('same window-relative index with another identity never renders', () {
      final projected = resolveReaderBookmarksForSourceWindow(
        bookmarks: <Bookmark>[stableBookmark()],
        sourceChunks: const <BookChunk>[
          BookChunk(
            index: 0,
            type: BookChunkType.text,
            text: 'xxxxxxUnrelated passage in this window.',
          ),
        ],
        locationsByChunkIndex: <int, StableBookLocation>{0: unrelated},
        sourceIdentitiesByChunkIndex: <int, LazySourceChunkIdentity>{
          0: identity(unrelated),
        },
      );
      expect(projected, isEmpty);
    });

    test('stable identity and offset override conflicting legacy fields', () {
      final projected = resolveReaderBookmarksForSourceWindow(
        bookmarks: <Bookmark>[stableBookmark()],
        sourceChunks: const <BookChunk>[
          BookChunk(
            index: 0,
            type: BookChunkType.text,
            text: 'Legacy coordinate points here.',
          ),
          BookChunk(
            index: 1,
            type: BookChunkType.text,
            text: 'xxxxxxTarget passage belongs here.',
          ),
        ],
        locationsByChunkIndex: <int, StableBookLocation>{
          0: unrelated,
          1: target,
        },
        sourceIdentitiesByChunkIndex: <int, LazySourceChunkIdentity>{
          0: identity(unrelated),
          1: identity(target),
        },
      );
      expect(projected.single.chunkIndex, 1);
      expect(projected.single.originalStartOffset, 6);
    });

    test('ambiguous legacy bookmark remains unresolved', () {
      final legacy = Bookmark(
        chunkIndex: 0,
        name: 'Legacy',
        previewText: 'Repeated passage',
      );
      final projected = resolveReaderBookmarksForSourceWindow(
        bookmarks: <Bookmark>[legacy],
        sourceChunks: const <BookChunk>[
          BookChunk(
            index: 0,
            type: BookChunkType.text,
            text: 'Repeated passage in one source.',
          ),
          BookChunk(
            index: 1,
            type: BookChunkType.text,
            text: 'Repeated passage in another source.',
          ),
        ],
        locationsByChunkIndex: const <int, StableBookLocation>{},
      );
      expect(projected, isEmpty);
    });

    test('uniquely verified legacy bookmark remains compatible', () {
      final legacy = Bookmark(
        chunkIndex: 99,
        name: 'Legacy',
        previewText: 'Unique legacy passage',
      );
      final projected = resolveReaderBookmarksForSourceWindow(
        bookmarks: <Bookmark>[legacy],
        sourceChunks: const <BookChunk>[
          BookChunk(index: 0, type: BookChunkType.text, text: 'Other source.'),
          BookChunk(
            index: 1,
            type: BookChunkType.text,
            text: 'Unique legacy passage remains readable.',
          ),
        ],
        locationsByChunkIndex: const <int, StableBookLocation>{},
      );
      expect(projected.single.chunkIndex, 1);
    });
  });

  test('multi-source mapping persists each exact source substring', () {
    final segments = readerMappedSourceSegments(
      ranges: const <MappedTextRange>[
        MappedTextRange(
          originalChunkIndex: 0,
          originalStartOffset: 6,
          originalEndOffset: 11,
          displayStartOffset: 0,
          displayEndOffset: 5,
        ),
        MappedTextRange(
          originalChunkIndex: 1,
          originalStartOffset: 0,
          originalEndOffset: 6,
          displayStartOffset: 5,
          displayEndOffset: 11,
        ),
      ],
      sourceChunks: const <BookChunk>[
        BookChunk(index: 0, type: BookChunkType.text, text: 'First alpha'),
        BookChunk(index: 1, type: BookChunkType.text, text: 'second source'),
      ],
    );
    expect(segments.map((segment) => segment.text), <String>[
      'alpha',
      'second',
    ]);
  });
}
