import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/bookmark.dart';
import 'package:nalori/models/stable_book_location.dart';
import 'package:nalori/services/chapter_navigation_service.dart';

void main() {
  group('chapter navigation targets', () {
    test('orders same-spine anchors by resolved local source position', () {
      final chapters = [
        _chapter('Chapter 9', 'body.xhtml', 'ch9'),
        _chapter('Chapter 10', 'body.xhtml', 'ch10'),
        _chapter('Chapter 11', 'body.xhtml', 'ch11'),
      ];
      final targets = ChapterNavigationService.buildTargets(
        chapters: chapters,
        anchorMap: const {'ch9': 0, 'ch10': 1, 'ch11': 2},
        locationsByChunkIndex: {
          0: _location(anchor: 'ch9', localChunkIndex: 0),
          1: _location(anchor: 'ch10', localChunkIndex: 1),
          2: _location(anchor: 'ch11', localChunkIndex: 2),
        },
      );

      expect(targets.map((target) => target.title), [
        'Chapter 9',
        'Chapter 10',
        'Chapter 11',
      ]);
      expect(
        ChapterNavigationService.nextTarget(
          targets,
          _location(anchor: 'ch9', localChunkIndex: 0),
        )?.title,
        'Chapter 10',
      );
      expect(
        ChapterNavigationService.nextTarget(
          targets,
          _location(anchor: 'ch10', localChunkIndex: 1),
        )?.title,
        'Chapter 11',
      );
      expect(
        ChapterNavigationService.previousTarget(
          targets,
          _location(anchor: 'ch11', localChunkIndex: 2),
        )?.title,
        'Chapter 10',
      );
      expect(
        ChapterNavigationService.previousTarget(
          targets,
          _location(anchor: 'ch10', localChunkIndex: 1),
        )?.title,
        'Chapter 9',
      );
    });

    test('previous from chapter start is strictly earlier', () {
      final targets = ChapterNavigationService.buildTargets(
        chapters: [
          _chapter('Chapter 1', 'body.xhtml', 'ch1'),
          _chapter('Chapter 2', 'body.xhtml', 'ch2'),
        ],
        anchorMap: const {'ch1': 0, 'ch2': 4},
        locationsByChunkIndex: {
          0: _location(anchor: 'ch1', localChunkIndex: 0),
          4: _location(anchor: 'ch2', localChunkIndex: 4),
        },
      );

      final previous = ChapterNavigationService.previousTarget(
        targets,
        _location(anchor: 'ch2', localChunkIndex: 4),
      );

      expect(previous?.title, 'Chapter 1');
      expect(previous?.title, isNot('Chapter 2'));
      expect(
        ChapterNavigationService.compareTargetToLocation(
          previous!,
          _location(anchor: 'ch2', localChunkIndex: 4),
        ),
        lessThan(0),
      );
    });

    test('nested TOC includes unique parent section targets', () {
      final chapters = [
        _chapter(
          'Part One',
          'part1.xhtml',
          'part1',
          children: [
            _chapter('Chapter 1', 'chapter1.xhtml', 'ch1', spineIndex: 1),
            _chapter('Chapter 2', 'chapter2.xhtml', 'ch2', spineIndex: 2),
          ],
        ),
        _chapter(
          'Part Two',
          'part2.xhtml',
          'part2',
          spineIndex: 3,
          children: [
            _chapter('Chapter 3', 'chapter3.xhtml', 'ch3', spineIndex: 4),
          ],
        ),
      ];
      final targets = ChapterNavigationService.buildTargets(chapters: chapters);
      final selectableTitles = targets
          .where((target) => target.isSelectable)
          .map((target) => target.title)
          .toList();

      expect(selectableTitles, [
        'Part One',
        'Chapter 1',
        'Chapter 2',
        'Part Two',
        'Chapter 3',
      ]);
      expect(
        ChapterNavigationService.nextTarget(
          targets,
          _location(href: 'part1.xhtml', anchor: 'part1'),
        )?.title,
        'Chapter 1',
      );
      expect(
        ChapterNavigationService.nextTarget(
          targets,
          _location(href: 'chapter1.xhtml', anchor: 'ch1', spineIndex: 1),
        )?.title,
        'Chapter 2',
      );
      expect(
        ChapterNavigationService.previousTarget(
          targets,
          _location(href: 'chapter3.xhtml', anchor: 'ch3', spineIndex: 4),
        )?.title,
        'Part Two',
      );
    });

    test('parent duplicate of first child is excluded in favor of child', () {
      final targets = ChapterNavigationService.buildTargets(
        chapters: [
          _chapter(
            'Part Two',
            'section.xhtml',
            'chapter-four',
            children: [
              _chapter('Chapter Four', 'section.xhtml', 'chapter-four'),
              _chapter('Chapter Five', 'section.xhtml', 'chapter-five'),
            ],
          ),
        ],
      );

      expect(
        targets
            .where((target) => target.isSelectable)
            .map((target) => target.title),
        ['Chapter Four', 'Chapter Five'],
      );
    });

    test('same-spine parent before child remains navigable in order', () {
      final targets = ChapterNavigationService.buildTargets(
        chapters: [
          _chapter(
            'Part Two',
            'section.xhtml',
            'part-two',
            children: [
              _chapter('Chapter Four', 'section.xhtml', 'chapter-four'),
            ],
          ),
        ],
        anchorMap: const {'part-two': 0, 'chapter-four': 2},
        locationsByChunkIndex: {
          0: _location(anchor: 'part-two', localChunkIndex: 0),
          2: _location(anchor: 'chapter-four', localChunkIndex: 2),
        },
      );

      expect(
        targets
            .where((target) => target.isSelectable)
            .map((target) => target.title),
        ['Part Two', 'Chapter Four'],
      );
      expect(
        ChapterNavigationService.nextTarget(
          targets,
          _location(anchor: 'part-two', localChunkIndex: 0),
        )?.title,
        'Chapter Four',
      );
      expect(
        ChapterNavigationService.previousTarget(
          targets,
          _location(anchor: 'chapter-four', localChunkIndex: 2),
        )?.title,
        'Part Two',
      );
    });

    test(
      'dedupes identical fragments but preserves distinct same-href anchors',
      () {
        final targets = ChapterNavigationService.buildTargets(
          chapters: [
            _chapter('Chapter 1', 'body.xhtml', 'ch1'),
            _chapter('Chapter 1 duplicate', 'body.xhtml', 'ch1'),
            _chapter('Chapter 2', 'body.xhtml', 'ch2'),
          ],
          anchorMap: const {'ch1': 0, 'ch2': 5},
          locationsByChunkIndex: {
            0: _location(anchor: 'ch1', localChunkIndex: 0),
            5: _location(anchor: 'ch2', localChunkIndex: 5),
          },
        );

        expect(targets.map((target) => target.anchorId), ['ch1', 'ch2']);
      },
    );

    test('front matter is skipped for first reading chapter', () {
      final chapter = ChapterNavigationService.firstReadingEntry<ChapterInfo>(
        roots: [
          _chapter('Cover', 'cover.xhtml', 'cover'),
          _chapter('Preface', 'preface.xhtml', 'preface', spineIndex: 1),
          _chapter('Introduction', 'intro.xhtml', 'intro', spineIndex: 2),
          _chapter('Foreword', 'foreword.xhtml', 'foreword', spineIndex: 3),
          _chapter('Chapter One', 'chapter1.xhtml', 'ch1', spineIndex: 4),
        ],
        titleOf: (chapter) => chapter.title,
        childrenOf: (chapter) => chapter.children,
      );

      expect(chapter?.title, 'Chapter One');
    });

    test(
      'unnumbered child chapter entries under sections remain navigable',
      () {
        final targets = ChapterNavigationService.buildTargets(
          chapters: [
            _chapter(
              'Section One',
              'section1.xhtml',
              'section1',
              children: [
                _chapter('The Arrival', 'section1.xhtml', 'arrival'),
                _chapter('The Door', 'section1.xhtml', 'door'),
              ],
            ),
          ],
        );

        expect(
          targets
              .where((target) => target.isSelectable)
              .map((target) => target.title),
          ['Section One', 'The Arrival', 'The Door'],
        );
      },
    );

    test('unresolved first-open targets resolve after source maps arrive', () {
      final chapters = [
        _chapter('Part Two', 'section.xhtml', 'part-two'),
        _chapter('Chapter Four', 'section.xhtml', 'chapter-four'),
      ];

      final unresolved = ChapterNavigationService.buildTargets(
        chapters: chapters,
      );
      final resolved = ChapterNavigationService.buildTargets(
        chapters: chapters,
        anchorMap: const {'part-two': 0, 'chapter-four': 2},
        locationsByChunkIndex: {
          0: _location(anchor: 'part-two', localChunkIndex: 0),
          2: _location(anchor: 'chapter-four', localChunkIndex: 2),
        },
      );

      expect(
        unresolved
            .where((target) => target.isSelectable)
            .map((target) => target.resolvedLocalChunkIndex),
        [null, null],
      );
      expect(
        resolved
            .where((target) => target.isSelectable)
            .map((target) => target.resolvedLocalChunkIndex),
        [0, 2],
      );
      expect(
        ChapterNavigationService.currentTarget(
          resolved,
          _location(anchor: 'chapter-four', localChunkIndex: 2),
        )?.title,
        'Chapter Four',
      );
    });
  });
}

ChapterInfo _chapter(
  String title,
  String href,
  String anchor, {
  int spineIndex = 0,
  List<ChapterInfo> children = const [],
}) {
  return ChapterInfo(
    title: title,
    chunkIndex: 0,
    stableLocation: _location(
      href: href,
      anchor: anchor,
      spineIndex: spineIndex,
    ),
    children: children,
  );
}

StableBookLocation _location({
  String href = 'body.xhtml',
  String? anchor,
  int spineIndex = 0,
  int? localChunkIndex,
}) {
  return StableBookLocation(
    bookId: 'book.epub',
    spineIndex: spineIndex,
    href: href,
    sourceChecksum: 'checksum-$spineIndex',
    anchorId: anchor,
    localChunkIndex: localChunkIndex,
  );
}
