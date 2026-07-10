import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/bookmark.dart';
import 'package:nalori/models/stable_book_location.dart';
import 'package:nalori/services/card_depth_chapter_progress_service.dart';
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
            1: _location(spineIndex: 0, localChunkIndex: 1),
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
            1: _location(spineIndex: 0, localChunkIndex: 1),
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
        expect(meta.pageLabel, '1 / ?');
        expect(meta.progress, 0);
        expect(meta.isExact, isFalse);
        expect(meta.shouldRequestChapterCompletion, isTrue);
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
            1: _location(spineIndex: 0, localChunkIndex: 1),
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
        expect(meta.pageLabel, '2 / ?');
        expect(meta.progress, closeTo(1 / 3, 0.0001));
        expect(meta.isExact, isFalse);
        expect(meta.shouldRequestChapterCompletion, isTrue);
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
            1: _location(spineIndex: 0, localChunkIndex: 1),
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
        expect(meta.shouldRequestChapterCompletion, isFalse);
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
            1: _location(spineIndex: 0, localChunkIndex: 1),
          },
        );
        final exactFixture = _fixture(
          chapters: [
            _chapter('Chapter 1', spineIndex: 0, localChunkIndex: 0),
            _chapter('Chapter 2', spineIndex: 2, localChunkIndex: 0),
          ],
          locations: {
            0: _location(spineIndex: 0, localChunkIndex: 0),
            1: _location(spineIndex: 0, localChunkIndex: 1),
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

        expect(partial.pageLabel, '2 / ?');
        expect(partial.progress, closeTo(0.5, 0.0001));
        expect(partial.isExact, isFalse);
        expect(partial.shouldRequestChapterCompletion, isTrue);
        expect(exact.pageLabel, '2 / 3');
        expect(exact.progress, closeTo(0.5, 0.0001));
        expect(exact.isExact, isTrue);
        expect(exact.shouldRequestChapterCompletion, isFalse);
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
  });
}

CardDepthChapterPageMeta _calculate(
  _CardDepthFixture fixture, {
  required int displayIndex,
  required List<List<int>> displayToOriginal,
  bool displayChunksComplete = true,
}) {
  return CardDepthChapterProgressService.calculate(
    displayIndex: displayIndex,
    displayChunkCount: displayToOriginal.length,
    displayToOriginal: displayToOriginal,
    locationsByChunkIndex: fixture.locations,
    chapterNavigationTargets: fixture.targets,
    displayChunksComplete: displayChunksComplete,
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
}) {
  return ChapterInfo(
    title: title,
    chunkIndex: localChunkIndex,
    stableLocation: _location(
      spineIndex: spineIndex,
      localChunkIndex: localChunkIndex,
    ),
  );
}

StableBookLocation _location({
  required int spineIndex,
  required int localChunkIndex,
}) {
  return StableBookLocation(
    bookId: 'book.epub',
    spineIndex: spineIndex,
    href: 'section-$spineIndex.xhtml',
    sourceChecksum: 'checksum-$spineIndex',
    localChunkIndex: localChunkIndex,
    anchorId: 's${spineIndex}_$localChunkIndex',
  );
}
