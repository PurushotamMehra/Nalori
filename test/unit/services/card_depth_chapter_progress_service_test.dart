import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/bookmark.dart';
import 'package:nalori/models/stable_book_location.dart';
import 'package:nalori/services/card_depth_chapter_progress_service.dart';
import 'package:nalori/services/chapter_card_layout_service.dart';
import 'package:nalori/services/chapter_navigation_service.dart';

void main() {
  group('CardDepthChapterProgressService', () {
    test('first page of a chapter starts at zero progress', () {
      final fixture = _fixture(
        chapters: [
          _chapter('Chapter 1', spineIndex: 0, localChunkIndex: 0),
          _chapter('Chapter 2', spineIndex: 1, localChunkIndex: 0),
        ],
        locations: {
          0: _location(spineIndex: 0, localChunkIndex: 0),
          1: _location(spineIndex: 0, localChunkIndex: 1),
          2: _location(spineIndex: 0, localChunkIndex: 2),
          3: _location(spineIndex: 1, localChunkIndex: 0),
        },
      );

      final meta = _calculate(
        fixture,
        displayIndex: 0,
        displayToOriginal: const [
          [0],
          [1],
          [2],
          [3],
        ],
      );

      expect(meta.title, 'Chapter 1');
      expect(meta.pageLabel, '1 / 3');
      expect(meta.progress, 0);
      expect(meta.isExact, isTrue);
    });

    test('swiping into the next chapter resets progress', () {
      final fixture = _fixture(
        chapters: [
          _chapter('Chapter 1', spineIndex: 0, localChunkIndex: 0),
          _chapter('Chapter 2', spineIndex: 1, localChunkIndex: 0),
        ],
        locations: {
          0: _location(spineIndex: 0, localChunkIndex: 0),
          1: _location(spineIndex: 0, localChunkIndex: 1),
          2: _location(spineIndex: 0, localChunkIndex: 2),
          3: _location(spineIndex: 1, localChunkIndex: 0),
          4: _location(spineIndex: 1, localChunkIndex: 1),
        },
      );

      final meta = _calculate(
        fixture,
        displayIndex: 3,
        displayToOriginal: const [
          [0],
          [1],
          [2],
          [3],
          [4],
        ],
      );

      expect(meta.title, 'Chapter 2');
      expect(meta.pageLabel, '1 / 2');
      expect(meta.progress, 0);
    });

    test('final page of a fully known chapter reaches 100 percent', () {
      final fixture = _fixture(
        chapters: [
          _chapter('Chapter 1', spineIndex: 0, localChunkIndex: 0),
          _chapter('Chapter 2', spineIndex: 1, localChunkIndex: 0),
        ],
        locations: {
          0: _location(spineIndex: 0, localChunkIndex: 0),
          1: _location(spineIndex: 0, localChunkIndex: 1),
          2: _location(spineIndex: 0, localChunkIndex: 2),
          3: _location(spineIndex: 1, localChunkIndex: 0),
        },
      );

      final meta = _calculate(
        fixture,
        displayIndex: 2,
        displayToOriginal: const [
          [0],
          [1],
          [2],
          [3],
        ],
      );

      expect(meta.pageLabel, '3 / 3');
      expect(meta.progress, 1);
    });

    test(
      'multiple chapters in one spine item use local chapter boundaries',
      () {
        final fixture = _fixture(
          chapters: [
            _chapter('Chapter 1', spineIndex: 0, localChunkIndex: 0),
            _chapter('Chapter 2', spineIndex: 0, localChunkIndex: 3),
            _chapter('Chapter 3', spineIndex: 0, localChunkIndex: 5),
          ],
          locations: {
            for (var i = 0; i < 6; i++)
              i: _location(spineIndex: 0, localChunkIndex: i),
          },
        );

        final meta = _calculate(
          fixture,
          displayIndex: 3,
          displayToOriginal: const [
            [0],
            [1],
            [2],
            [3],
            [4],
            [5],
          ],
        );

        expect(meta.title, 'Chapter 2');
        expect(meta.pageLabel, '1 / 2');
        expect(meta.progress, 0);
        expect(meta.isExact, isTrue);
      },
    );

    test(
      'chapter spanning multiple spine items counts pages until next target',
      () {
        final fixture = _fixture(
          chapters: [
            _chapter('Chapter 1', spineIndex: 0, localChunkIndex: 0),
            _chapter('Chapter 2', spineIndex: 2, localChunkIndex: 0),
          ],
          locations: {
            0: _location(spineIndex: 0, localChunkIndex: 0),
            1: _location(
              spineIndex: 0,
              localChunkIndex: 1,
              sectionProgression: 1 / 3,
            ),
            2: _location(spineIndex: 1, localChunkIndex: 0),
            3: _location(spineIndex: 1, localChunkIndex: 1),
            4: _location(spineIndex: 2, localChunkIndex: 0),
          },
        );

        final meta = _calculate(
          fixture,
          displayIndex: 3,
          displayToOriginal: const [
            [0],
            [1],
            [2],
            [3],
            [4],
          ],
        );

        expect(meta.title, 'Chapter 1');
        expect(meta.pageLabel, '4 / 4');
        expect(meta.progress, 1);
      },
    );

    test(
      'lazy partial window with missing next boundary does not use window length',
      () {
        final fixture = _fixture(
          chapters: [
            _chapter('Chapter 1', spineIndex: 0, localChunkIndex: 0),
            _chapter('Chapter 2', spineIndex: 2, localChunkIndex: 0),
          ],
          locations: {
            0: _location(spineIndex: 0, localChunkIndex: 0),
            1: _location(
              spineIndex: 0,
              localChunkIndex: 1,
              sectionProgression: 1 / 3,
            ),
          },
        );

        final meta = _calculate(
          fixture,
          displayIndex: 0,
          displayToOriginal: const [
            [0],
            [1],
          ],
          displayChunksComplete: false,
        );

        expect(meta.title, 'Chapter 1');
        expect(meta.pageLabel, 'Page 1');
        expect(meta.progress, 0);
        expect(meta.isExact, isFalse);
      },
    );

    test(
      'lazy partial window with missing next boundary advances provisionally after first page',
      () {
        final fixture = _fixture(
          chapters: [
            _chapter('Chapter 1', spineIndex: 0, localChunkIndex: 0),
            _chapter('Chapter 2', spineIndex: 2, localChunkIndex: 0),
          ],
          locations: {
            0: _location(spineIndex: 0, localChunkIndex: 0),
            1: _location(
              spineIndex: 0,
              localChunkIndex: 1,
              sectionProgression: 0.5,
            ),
            2: _location(spineIndex: 0, localChunkIndex: 2),
          },
        );

        final meta = _calculate(
          fixture,
          displayIndex: 1,
          displayToOriginal: const [
            [0],
            [1],
            [2],
          ],
          displayChunksComplete: false,
        );

        expect(meta.title, 'Chapter 1');
        expect(meta.pageLabel, 'Page 2');
        expect(meta.progress, closeTo(0.5, 0.0001));
        expect(meta.isExact, isFalse);
      },
    );

    test(
      'lazy forward append keeps previous chapter denominator canonical',
      () {
        final fixture = _fixture(
          chapters: [
            _chapter('Chapter 1', spineIndex: 0, localChunkIndex: 0),
            _chapter('Chapter 2', spineIndex: 1, localChunkIndex: 0),
          ],
          locations: {
            0: _location(spineIndex: 0, localChunkIndex: 0),
            1: _location(
              spineIndex: 0,
              localChunkIndex: 1,
              sectionProgression: 0.5,
            ),
            2: _location(spineIndex: 0, localChunkIndex: 2),
            3: _location(spineIndex: 1, localChunkIndex: 0),
            4: _location(spineIndex: 1, localChunkIndex: 1),
          },
        );

        final meta = _calculate(
          fixture,
          displayIndex: 1,
          displayToOriginal: const [
            [0],
            [1],
            [2],
            [3],
            [4],
          ],
          displayChunksComplete: false,
        );

        expect(meta.title, 'Chapter 1');
        expect(meta.pageLabel, '2 / 3');
        expect(meta.progress, 0.5);
        expect(meta.isExact, isTrue);
      },
    );

    test(
      'integrated missing boundary recomputes from provisional to exact progress',
      () {
        final partialFixture = _fixture(
          chapters: [
            _chapter('Chapter 1', spineIndex: 0, localChunkIndex: 0),
            _chapter('Chapter 2', spineIndex: 2, localChunkIndex: 0),
          ],
          locations: {
            0: _location(spineIndex: 0, localChunkIndex: 0),
            1: _location(
              spineIndex: 0,
              localChunkIndex: 1,
              sectionProgression: 0.5,
            ),
          },
        );
        final exactFixture = _fixture(
          chapters: [
            _chapter('Chapter 1', spineIndex: 0, localChunkIndex: 0),
            _chapter('Chapter 2', spineIndex: 2, localChunkIndex: 0),
          ],
          locations: {
            0: _location(spineIndex: 0, localChunkIndex: 0),
            1: _location(
              spineIndex: 0,
              localChunkIndex: 1,
              sectionProgression: 0.5,
            ),
            2: _location(spineIndex: 1, localChunkIndex: 0),
            3: _location(spineIndex: 2, localChunkIndex: 0),
          },
        );

        final partial = _calculate(
          partialFixture,
          displayIndex: 1,
          displayToOriginal: const [
            [0],
            [1],
          ],
          displayChunksComplete: false,
        );
        final exact = _calculate(
          exactFixture,
          displayIndex: 1,
          displayToOriginal: const [
            [0],
            [1],
            [2],
            [3],
          ],
          displayChunksComplete: false,
        );

        expect(partial.pageLabel, 'Page 2');
        expect(partial.progress, closeTo(0.5, 0.0001));
        expect(partial.isExact, isFalse);
        expect(exact.pageLabel, '2 / 3');
        expect(exact.progress, closeTo(0.5, 0.0001));
        expect(exact.isExact, isTrue);
      },
    );

    test('lazy backward prepend preserves current chapter progress', () {
      final fixture = _fixture(
        chapters: [
          _chapter('Chapter 1', spineIndex: 0, localChunkIndex: 0),
          _chapter('Chapter 2', spineIndex: 1, localChunkIndex: 0),
        ],
        locations: {
          0: _location(spineIndex: 0, localChunkIndex: 0),
          1: _location(spineIndex: 0, localChunkIndex: 1),
          2: _location(spineIndex: 1, localChunkIndex: 0),
          3: _location(spineIndex: 1, localChunkIndex: 1),
        },
      );

      final meta = _calculate(
        fixture,
        displayIndex: 2,
        displayToOriginal: const [
          [0],
          [1],
          [2],
          [3],
        ],
      );

      expect(meta.title, 'Chapter 2');
      expect(meta.pageLabel, '1 / 2');
      expect(meta.progress, 0);
    });

    test('reader settings re-pagination recomputes chapter page totals', () {
      final fixture = _fixture(
        chapters: [
          _chapter('Chapter 1', spineIndex: 0, localChunkIndex: 0),
          _chapter('Chapter 2', spineIndex: 1, localChunkIndex: 0),
        ],
        locations: {
          0: _location(spineIndex: 0, localChunkIndex: 0),
          1: _location(spineIndex: 0, localChunkIndex: 1),
          2: _location(spineIndex: 0, localChunkIndex: 2),
          3: _location(spineIndex: 1, localChunkIndex: 0),
        },
      );

      final before = _calculate(
        fixture,
        displayIndex: 1,
        displayToOriginal: const [
          [0],
          [1],
          [2],
          [3],
        ],
      );
      final after = _calculate(
        fixture,
        displayIndex: 2,
        displayToOriginal: const [
          [0],
          [0],
          [1],
          [2],
          [3],
        ],
      );

      expect(before.pageLabel, '2 / 3');
      expect(after.pageLabel, '3 / 4');
      expect(after.progress, closeTo(2 / 3, 0.0001));
    });

    test('complete lazy window is not a complete final chapter', () {
      final fixture = _fixture(
        chapters: [
          _chapter('Final chapter', spineIndex: 4, localChunkIndex: 0),
        ],
        locations: {
          0: _location(spineIndex: 4, localChunkIndex: 0),
          1: _location(spineIndex: 4, localChunkIndex: 1),
        },
      );

      final meta = _calculate(
        fixture,
        displayIndex: 1,
        displayToOriginal: const [
          [0],
          [1],
        ],
        displayChunksComplete: true,
        allowWindowExactFallback: false,
      );

      expect(meta.pageLabel, 'Page 2');
      expect(meta.progress, lessThan(1));
      expect(meta.isExact, isFalse);
    });

    test('missing TOC in a lazy window degrades to unknown total', () {
      final meta = CardDepthChapterProgressService.calculate(
        displayIndex: 1,
        displayChunkCount: 3,
        displayToOriginal: const [
          [0],
          [1],
          [2],
        ],
        locationsByChunkIndex: {
          0: _location(spineIndex: 2, localChunkIndex: 0),
          1: _location(spineIndex: 2, localChunkIndex: 1),
          2: _location(spineIndex: 2, localChunkIndex: 2),
        },
        chapterNavigationTargets: const [],
        displayChunksComplete: true,
        allowWindowExactFallback: false,
      );

      expect(meta.title, 'Current chapter');
      expect(meta.pageLabel, 'Page 2');
      expect(meta.progress, lessThan(1));
      expect(meta.isExact, isFalse);
    });

    test('partial chapter rail uses weighted structural source progress', () {
      final fixture = _fixture(
        chapters: [
          _chapter(
            'Chapter 1',
            spineIndex: 0,
            localChunkIndex: 0,
            publicationProgression: 0.2,
          ),
          _chapter(
            'Chapter 2',
            spineIndex: 2,
            localChunkIndex: 0,
            publicationProgression: 0.8,
          ),
        ],
        locations: {
          0: _location(
            spineIndex: 1,
            localChunkIndex: 0,
            publicationProgression: 0.5,
          ),
        },
      );

      final meta = _calculate(
        fixture,
        displayIndex: 0,
        displayToOriginal: const [
          [0],
        ],
        displayChunksComplete: false,
        allowWindowExactFallback: false,
      );

      expect(meta.pageLabel, 'Page 1');
      expect(meta.progress, closeTo(0.5, 0.0001));
      expect(meta.isExact, isFalse);
    });

    test(
      'loaded section boundary does not change multi-section chapter progress',
      () {
        final chapters = [
          _chapter(
            'Chapter 1',
            spineIndex: 0,
            localChunkIndex: 0,
            publicationProgression: 0.1,
          ),
          _chapter(
            'Chapter 2',
            spineIndex: 3,
            localChunkIndex: 0,
            publicationProgression: 0.9,
          ),
        ];
        final partial = _fixture(
          chapters: chapters,
          locations: {
            0: _location(
              spineIndex: 1,
              localChunkIndex: 2,
              publicationProgression: 0.5,
            ),
          },
        );
        final expanded = _fixture(
          chapters: chapters,
          locations: {
            0: _location(
              spineIndex: 1,
              localChunkIndex: 2,
              publicationProgression: 0.5,
            ),
            1: _location(
              spineIndex: 2,
              localChunkIndex: 0,
              publicationProgression: 0.7,
            ),
          },
        );

        final before = _calculate(
          partial,
          displayIndex: 0,
          displayToOriginal: const [
            [0],
          ],
          displayChunksComplete: true,
          allowWindowExactFallback: false,
        );
        final after = _calculate(
          expanded,
          displayIndex: 0,
          displayToOriginal: const [
            [0],
            [1],
          ],
          displayChunksComplete: true,
          allowWindowExactFallback: false,
        );

        expect(before.pageLabel, 'Page 1');
        expect(before.progress, closeTo(0.5, 0.0001));
        expect(after.progress, closeTo(before.progress, 0.0001));
        expect(after.progress, lessThan(1));
      },
    );

    test('rapid structural forward and backward movement stays monotonic', () {
      final targets = [
        _chapter(
          'Chapter 1',
          spineIndex: 0,
          localChunkIndex: 0,
          publicationProgression: 0.2,
        ),
        _chapter(
          'Chapter 2',
          spineIndex: 4,
          localChunkIndex: 0,
          publicationProgression: 0.8,
        ),
      ];

      double progressAt(double publicationProgression) {
        final fixture = _fixture(
          chapters: targets,
          locations: {
            0: _location(
              spineIndex: 2,
              localChunkIndex: 0,
              publicationProgression: publicationProgression,
            ),
          },
        );
        return _calculate(
          fixture,
          displayIndex: 0,
          displayToOriginal: const [
            [0],
          ],
          displayChunksComplete: false,
          allowWindowExactFallback: false,
        ).progress;
      }

      final forward = [0.3, 0.42, 0.55, 0.7].map(progressAt).toList();
      expect(forward, orderedEquals(forward.toList()..sort()));
      expect(progressAt(0.42), lessThan(progressAt(0.55)));
    });

    test('exact total requires both structural boundaries to be rendered', () {
      final fixture = _fixture(
        chapters: [
          _chapter('Chapter 1', spineIndex: 0, localChunkIndex: 0),
          _chapter('Chapter 2', spineIndex: 2, localChunkIndex: 0),
        ],
        locations: {
          0: _location(spineIndex: 1, localChunkIndex: 0),
          1: _location(spineIndex: 2, localChunkIndex: 0),
        },
      );

      final meta = _calculate(
        fixture,
        displayIndex: 0,
        displayToOriginal: const [
          [0],
          [1],
        ],
        displayChunksComplete: true,
        allowWindowExactFallback: false,
      );

      expect(meta.pageLabel, 'Page 1');
      expect(meta.isExact, isFalse);
    });

    test('unknown card total can reach structural chapter completion', () {
      final fixture = _fixture(
        chapters: [
          _chapter(
            'Chapter 1',
            spineIndex: 0,
            localChunkIndex: 0,
            publicationProgression: 0.1,
          ),
          _chapter(
            'Chapter 2',
            spineIndex: 2,
            localChunkIndex: 0,
            publicationProgression: 0.6,
          ),
        ],
        locations: {
          0: _location(
            spineIndex: 1,
            localChunkIndex: 8,
            publicationProgression: 0.58,
          ),
        },
      );

      final meta = _calculate(
        fixture,
        displayIndex: 0,
        displayToOriginal: const [
          [0],
        ],
        displayChunksComplete: false,
        allowWindowExactFallback: false,
        currentCardReachesChapterBoundary: true,
      );

      expect(meta.pageLabel, 'Page 1');
      expect(meta.progress, 1);
      expect(meta.isExact, isFalse);
    });

    test('unproven loaded section end remains below chapter completion', () {
      final fixture = _fixture(
        chapters: [
          _chapter(
            'Chapter 1',
            spineIndex: 0,
            localChunkIndex: 0,
            publicationProgression: 0.1,
          ),
          _chapter(
            'Chapter 2',
            spineIndex: 2,
            localChunkIndex: 0,
            publicationProgression: 0.6,
          ),
        ],
        locations: {
          0: _location(
            spineIndex: 1,
            localChunkIndex: 8,
            publicationProgression: 0.58,
          ),
        },
      );

      final meta = _calculate(
        fixture,
        displayIndex: 0,
        displayToOriginal: const [
          [0],
        ],
        displayChunksComplete: true,
        allowWindowExactFallback: false,
      );

      expect(meta.progress, lessThan(1));
      expect(meta.isExact, isFalse);
    });

    test('chapter rail reacts to every card end within one source chunk', () {
      final fixture = _fixture(
        chapters: [
          _chapter(
            'Chapter 1',
            spineIndex: 0,
            localChunkIndex: 0,
            publicationProgression: 0.2,
          ),
          _chapter(
            'Chapter 2',
            spineIndex: 0,
            localChunkIndex: 1,
            publicationProgression: 0.4,
          ),
        ],
        locations: {
          0: _location(
            spineIndex: 0,
            localChunkIndex: 0,
            publicationProgression: 0.2,
          ),
          1: _location(
            spineIndex: 0,
            localChunkIndex: 1,
            publicationProgression: 0.4,
          ),
        },
      );
      final start = fixture.locations[0]!;
      final values = <double>[];
      for (final end in [0.24, 0.29, 0.34]) {
        values.add(
          _calculate(
            fixture,
            displayIndex: 0,
            displayToOriginal: const [
              [0],
            ],
            allowWindowExactFallback: false,
            currentCardStartLocation: start,
            currentCardEndLocation: start.copyWith(
              textOffset: (end * 1000).round(),
              publicationProgression: end,
            ),
          ).progress,
        );
      }

      expect(values[1], greaterThan(values[0]));
      expect(values[2], greaterThan(values[1]));
    });

    test('background-complete layout changes Page n to n / total', () {
      final fixture = _fixture(
        chapters: [
          _chapter('Chapter 1', spineIndex: 0, localChunkIndex: 0),
          _chapter('Chapter 2', spineIndex: 1, localChunkIndex: 0),
        ],
        locations: {
          0: _location(spineIndex: 0, localChunkIndex: 0, textOffset: 100),
        },
      );
      final current = fixture.locations[0]!;
      final before = _calculate(
        fixture,
        displayIndex: 0,
        displayToOriginal: const [
          [0],
        ],
        allowWindowExactFallback: false,
        currentCardStartLocation: current,
        currentCardEndLocation: current.copyWith(textOffset: 200),
      );
      final complete = ChapterCardLayout(
        key: const ChapterCardLayoutKey(
          bookId: 'book.epub',
          publicationFingerprint: 'publication',
          chapterIdentity: 'chapter-1',
          parserSchema: 2,
          displaySchema: 'display',
          settingsSignature: 'settings',
          viewportSignature: 'viewport',
          cardMode: true,
        ),
        pages: [
          ChapterCardSourceRange(
            start: current.copyWith(textOffset: 0),
            end: current.copyWith(textOffset: 100),
          ),
          ChapterCardSourceRange(
            start: current.copyWith(textOffset: 100),
            end: current.copyWith(textOffset: 200),
          ),
          ChapterCardSourceRange(
            start: current.copyWith(textOffset: 200),
            end: current.copyWith(textOffset: 300),
          ),
        ],
        completedAtMs: 1,
      );
      final after = _calculate(
        fixture,
        displayIndex: 0,
        displayToOriginal: const [
          [0],
        ],
        allowWindowExactFallback: false,
        currentCardStartLocation: current,
        currentCardEndLocation: current.copyWith(textOffset: 200),
        completeChapterLayout: complete,
      );

      expect(before.pageLabel, 'Page 1');
      expect(after.pageLabel, '2 / 3');
      expect(after.isExact, isTrue);
    });
  });
}

CardDepthChapterPageMeta _calculate(
  _CardDepthFixture fixture, {
  required int displayIndex,
  required List<List<int>> displayToOriginal,
  bool displayChunksComplete = true,
  bool allowWindowExactFallback = true,
  bool currentCardReachesChapterBoundary = false,
  StableBookLocation? currentCardStartLocation,
  StableBookLocation? currentCardEndLocation,
  ChapterCardLayout? completeChapterLayout,
}) {
  return CardDepthChapterProgressService.calculate(
    displayIndex: displayIndex,
    displayChunkCount: displayToOriginal.length,
    displayToOriginal: displayToOriginal,
    locationsByChunkIndex: fixture.locations,
    chapterNavigationTargets: fixture.targets,
    displayChunksComplete: displayChunksComplete,
    currentCardReachesChapterBoundary: currentCardReachesChapterBoundary,
    currentCardStartLocation: currentCardStartLocation,
    currentCardEndLocation: currentCardEndLocation,
    completeChapterLayout: completeChapterLayout,
    allowWindowExactFallback: allowWindowExactFallback,
  );
}

_CardDepthFixture _fixture({
  required List<ChapterInfo> chapters,
  required Map<int, StableBookLocation> locations,
}) {
  final anchorMap = <String, int>{};
  for (final entry in locations.entries) {
    final anchor = entry.value.anchorId;
    if (anchor != null) anchorMap[anchor] = entry.key;
  }
  return _CardDepthFixture(
    targets: ChapterNavigationService.buildTargets(
      chapters: chapters,
      anchorMap: anchorMap,
      locationsByChunkIndex: locations,
    ),
    locations: locations,
  );
}

class _CardDepthFixture {
  const _CardDepthFixture({required this.targets, required this.locations});

  final List<ChapterNavigationTarget> targets;
  final Map<int, StableBookLocation> locations;
}

ChapterInfo _chapter(
  String title, {
  required int spineIndex,
  required int localChunkIndex,
  double? publicationProgression,
}) {
  return ChapterInfo(
    title: title,
    chunkIndex: localChunkIndex,
    stableLocation: _location(
      spineIndex: spineIndex,
      localChunkIndex: localChunkIndex,
      publicationProgression: publicationProgression,
    ),
  );
}

StableBookLocation _location({
  required int spineIndex,
  required int localChunkIndex,
  double? publicationProgression,
  double? sectionProgression,
  int textOffset = 0,
}) {
  return StableBookLocation(
    bookId: 'book.epub',
    spineIndex: spineIndex,
    href: 'section-$spineIndex.xhtml',
    sourceChecksum: 'checksum-$spineIndex',
    localChunkIndex: localChunkIndex,
    textOffset: textOffset,
    publicationProgression: publicationProgression,
    sectionProgression: sectionProgression,
    anchorId: 's${spineIndex}_$localChunkIndex',
  );
}
