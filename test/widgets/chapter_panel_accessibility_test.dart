import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/bookmark.dart';
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/models/stable_book_location.dart';
import 'package:nalori/services/chapter_navigation_service.dart';
import 'package:nalori/widgets/chapter_panel.dart';

void main() {
  testWidgets('chapter panel exposes chapter and bookmark navigation labels', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChapterPanel(
            chapters: const [
              ChapterInfo(title: 'Opening', chunkIndex: 0),
              ChapterInfo(title: 'Second Chapter', chunkIndex: 4),
            ],
            currentPage: 0,
            originalToDisplay: const {0: 0, 4: 4},
            onNavigate: (_) {},
            settings: const ReadingSettings(),
            bookmarks: [
              Bookmark(
                chunkIndex: 4,
                name: 'Important passage',
                createdAt: DateTime.fromMillisecondsSinceEpoch(1),
                previewText: 'Important bookmarked passage.',
              ),
            ],
            totalDisplayPages: 10,
            chunkTexts: const {4: 'Important bookmarked passage.'},
            onRemoveBookmark: (_) {},
            onClearAllBookmarks: () {},
            onRestoreBookmarks: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Chapters'), findsOneWidget);
    expect(find.text('Bookmarks'), findsOneWidget);
    expect(find.bySemanticsLabel('Opening'), findsOneWidget);

    await tester.tap(find.text('Bookmarks'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Important passage'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('chapter panel marks canonical section target as current', (
    tester,
  ) async {
    final chapters = _sectionChapters();
    final targets = ChapterNavigationService.buildTargets(
      chapters: chapters,
      anchorMap: const {'part-two': 0, 'chapter-four': 2},
      locationsByChunkIndex: {
        0: _location(anchor: 'part-two', localChunkIndex: 0),
        2: _location(anchor: 'chapter-four', localChunkIndex: 2),
      },
    );

    await _pumpPanel(
      tester,
      chapters: chapters,
      targets: targets,
      currentStableLocation: _location(anchor: 'part-two', localChunkIndex: 0),
    );

    expect(
      tester.widget<Text>(find.text('Part Two')).style?.fontWeight,
      FontWeight.w800,
    );
  });

  testWidgets('chapter panel marks canonical child target as current', (
    tester,
  ) async {
    final chapters = _sectionChapters();
    final targets = ChapterNavigationService.buildTargets(
      chapters: chapters,
      anchorMap: const {'part-two': 0, 'chapter-four': 2},
      locationsByChunkIndex: {
        0: _location(anchor: 'part-two', localChunkIndex: 0),
        2: _location(anchor: 'chapter-four', localChunkIndex: 2),
      },
    );

    await _pumpPanel(
      tester,
      chapters: chapters,
      targets: targets,
      currentStableLocation: _location(
        anchor: 'chapter-four',
        localChunkIndex: 2,
      ),
    );

    expect(
      tester.widget<Text>(find.text('Chapter Four')).style?.fontWeight,
      FontWeight.w800,
    );
  });
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required List<ChapterInfo> chapters,
  required List<ChapterNavigationTarget> targets,
  required StableBookLocation currentStableLocation,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChapterPanel(
          chapters: chapters,
          currentPage: 0,
          currentStableLocation: currentStableLocation,
          chapterNavigationTargets: targets,
          originalToDisplay: const {0: 0, 2: 2},
          onNavigate: (_) {},
          settings: const ReadingSettings(),
          bookmarks: const [],
          totalDisplayPages: 5,
          onRemoveBookmark: (_) {},
          onClearAllBookmarks: () {},
          onRestoreBookmarks: (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Chapters'));
  await tester.pumpAndSettle();
}

List<ChapterInfo> _sectionChapters() {
  return [
    ChapterInfo(
      title: 'Part Two',
      chunkIndex: 0,
      stableLocation: _location(anchor: 'part-two'),
      children: [
        ChapterInfo(
          title: 'Chapter Four',
          chunkIndex: 2,
          stableLocation: _location(anchor: 'chapter-four'),
        ),
      ],
    ),
  ];
}

StableBookLocation _location({required String anchor, int? localChunkIndex}) {
  return StableBookLocation(
    bookId: 'book.epub',
    spineIndex: 0,
    href: 'section.xhtml',
    sourceChecksum: 'checksum',
    anchorId: anchor,
    localChunkIndex: localChunkIndex,
  );
}
